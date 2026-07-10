package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	manualStart        = "<!-- dotfiles-spikes:manual-reminders:start -->"
	manualEnd          = "<!-- dotfiles-spikes:manual-reminders:end -->"
	incidentGapSeconds = 180
)

var (
	monitorUnits = map[string]bool{
		"system-spike-watch.service":     true,
		"dotfiles-spikes.service":        true,
		"dotfiles-health.service":        true,
		"browser-task-snapshotd.service": true,
	}
	displayHostUnits = map[string]bool{
		"sddm.service":            true,
		"display-manager.service": true,
	}
	interactiveKinds = map[string]bool{
		"xorg":       true,
		"compositor": true,
		"audio":      true,
		"input":      true,
	}
	sourceStems = []string{"system-spike-xorg", "system-spike-compositor", "system-spike-audio", "system-spike-input", "system-spike-generic"}
)

type rawMap map[string]any

type spikeEvent struct {
	Raw                       rawMap
	readIndex                 int
	eventIDValue              string
	startedAtValue            time.Time
	victimCommValue           string
	victimUnitValue           string
	victimKindValue           string
	dominantUnitValue         string
	topUnitLabelValue         string
	triggerCPUValue           float64
	monitorCPUValue           float64
	confidenceValue           string
	classificationValue       string
	durationValue             float64
	notesValue                string
	primarySuspectValue       rawMap
	suspectLabelValue         string
	contextSummaryValue       string
	contextDetailsValue       []string
	contextEvidenceLinesValue []string
	sourceSuspectLinesValue   []string
	topUnitDetailsValue       []string
}

type contextSummaryPart struct {
	Text   string
	Unit   string
	CPUPct float64
	Kind   string
}

type patternRow struct {
	Victim             string
	Suspect            string
	Count              int
	VictimUnit         string
	TopUnit            string
	FirstSeen          string
	LastSeen           string
	AvgDuration        float64
	MaxDuration        float64
	MaxTriggerCPU      float64
	MaxMonitorOverhead float64
	Confidence         string
	Classification     string
}

type incidentRow struct {
	Start              time.Time
	End                time.Time
	Count              int
	Victim             string
	VictimUnit         string
	Suspects           string
	TopUnits           string
	MaxTriggerCPU      float64
	MaxMonitorOverhead float64
	Confidence         string
	Classification     string
	Context            string
}

type orderedCounter struct {
	counts map[string]int
	order  []string
}

func newCounter() *orderedCounter {
	return &orderedCounter{counts: make(map[string]int)}
}

func (c *orderedCounter) Add(value string) {
	if _, ok := c.counts[value]; !ok {
		c.order = append(c.order, value)
	}
	c.counts[value]++
}

func (c *orderedCounter) Len() int {
	return len(c.counts)
}

func (c *orderedCounter) MostCommon(limit int) []counterItem {
	items := make([]counterItem, 0, len(c.counts))
	index := make(map[string]int, len(c.order))
	for i, name := range c.order {
		index[name] = i
		items = append(items, counterItem{Name: name, Count: c.counts[name]})
	}
	sort.SliceStable(items, func(i, j int) bool {
		if items[i].Count != items[j].Count {
			return items[i].Count > items[j].Count
		}
		return index[items[i].Name] < index[items[j].Name]
	})
	if limit > 0 && len(items) > limit {
		return items[:limit]
	}
	return items
}

type counterItem struct {
	Name  string
	Count int
}

func isMonitorUnit(unit string) bool {
	return monitorUnits[unit]
}

func isDisplayHostUnit(unit string) bool {
	return displayHostUnits[unit]
}

func isActionableUnit(unit string) bool {
	return unit != "" && unit != "unknown" && unit != "init.scope" && !isMonitorUnit(unit) && !isDisplayHostUnit(unit)
}

func isDockerUnit(unit string) bool {
	return strings.HasPrefix(unit, "docker-") && strings.HasSuffix(unit, ".scope")
}

func sourceStem(event spikeEvent) string {
	switch event.victimKind() {
	case "xorg":
		return "system-spike-xorg"
	case "compositor":
		return "system-spike-compositor"
	case "audio":
		return "system-spike-audio"
	case "input":
		return "system-spike-input"
	default:
		return "system-spike-generic"
	}
}

func formatCPU(value any) string {
	return fmt.Sprintf("%.1f%%", cpuValue(value))
}

func formatFloat(value any) string {
	return fmt.Sprintf("%.1f", cpuValue(value))
}

func formatID(value any) string {
	switch v := value.(type) {
	case float64:
		if v == math.Trunc(v) {
			return strconv.FormatInt(int64(v), 10)
		}
	case float32:
		f := float64(v)
		if f == math.Trunc(f) {
			return strconv.FormatInt(int64(f), 10)
		}
	case int:
		return strconv.Itoa(v)
	case int64:
		return strconv.FormatInt(v, 10)
	case json.Number:
		if out, err := v.Int64(); err == nil {
			return strconv.FormatInt(out, 10)
		}
	case string:
		return v
	}
	return fmt.Sprint(orEmpty(value))
}

func cpuValue(value any) float64 {
	switch v := value.(type) {
	case float64:
		return v
	case float32:
		return float64(v)
	case int:
		return float64(v)
	case int64:
		return float64(v)
	case json.Number:
		out, _ := v.Float64()
		return out
	case string:
		out, err := strconv.ParseFloat(v, 64)
		if err == nil {
			return out
		}
	}
	return 0
}

func compactText(value any, limit int) string {
	text := strings.Join(strings.Fields(fmt.Sprint(orEmpty(value))), " ")
	if limit <= 0 || len(text) <= limit {
		return text
	}
	if limit <= 3 {
		return "..."
	}
	return text[:limit-3] + "..."
}

func inlineCode(value any, limit int) string {
	return "`" + strings.ReplaceAll(compactText(value, limit), "`", "'") + "`"
}

func orEmpty(value any) any {
	if value == nil {
		return ""
	}
	return value
}

func asMap(value any) rawMap {
	if value == nil {
		return rawMap{}
	}
	if m, ok := value.(map[string]any); ok {
		return rawMap(m)
	}
	if m, ok := value.(rawMap); ok {
		return m
	}
	return rawMap{}
}

func asSlice(value any) []any {
	if value == nil {
		return nil
	}
	if items, ok := value.([]any); ok {
		return items
	}
	return nil
}

func stringValue(m rawMap, key string) string {
	value := m[key]
	if value == nil {
		return ""
	}
	return fmt.Sprint(value)
}

func boolValue(m rawMap, key string) bool {
	value := m[key]
	switch v := value.(type) {
	case bool:
		return v
	case string:
		return v != "" && v != "0" && v != "false"
	case float64:
		return v != 0
	}
	return false
}

func (e spikeEvent) eventID() string {
	return e.eventIDValue
}

func newSpikeEvent(raw rawMap, readIndex int) spikeEvent {
	e := spikeEvent{Raw: raw, readIndex: readIndex}
	e.eventIDValue = valueOrDefault(stringValue(raw, "event_id"), "unknown")
	e.startedAtValue = parseStartedAt(raw)
	e.victimKindValue = valueOrDefault(stringValue(raw, "victim_kind"), "generic")
	e.victimCommValue = computeVictimComm(raw)
	e.victimUnitValue = computeVictimUnit(raw, e.victimCommValue)
	e.dominantUnitValue = computeDominantUnit(raw)
	e.topUnitLabelValue = valueOrDefault(e.dominantUnitValue, "unknown")
	e.triggerCPUValue = cpuValue(raw["trigger_cpu_pct"])
	e.monitorCPUValue = computeMonitorOverheadCPU(raw)
	e.confidenceValue = valueOrDefault(stringValue(raw, "confidence"), "low")
	e.classificationValue = valueOrDefault(stringValue(raw, "classification"), "warning")
	e.durationValue = cpuValue(raw["duration_s"])
	e.notesValue = stringValue(raw, "notes")
	e.primarySuspectValue = computePrimarySuspect(e)
	e.suspectLabelValue = computeSuspectLabel(e.primarySuspectValue)
	e.Raw = nil
	return e
}

func (e *spikeEvent) enrichDetails(raw rawMap) {
	e.Raw = raw
	e.contextSummaryValue = computeContextSummary(*e)
	e.contextDetailsValue = computeContextDetails(*e)
	e.contextEvidenceLinesValue = contextEvidenceLines(*e)
	e.sourceSuspectLinesValue = sourceSuspectLines(*e)
	e.topUnitDetailsValue = topUnitDetails(raw)
	e.Raw = nil
}

func (e spikeEvent) startedAt() time.Time {
	return e.startedAtValue
}

func parseStartedAt(raw rawMap) time.Time {
	value := stringValue(raw, "started_at")
	if value != "" {
		if ts, err := time.Parse(time.RFC3339Nano, value); err == nil {
			return ts
		}
		if ts, err := time.Parse("2006-01-02T15:04:05-07:00", value); err == nil {
			return ts
		}
	}
	return time.Unix(0, 0).In(time.Local)
}

func (e spikeEvent) victim() rawMap {
	return asMap(e.Raw["victim"])
}

func (e spikeEvent) victimComm() string {
	return e.victimCommValue
}

func computeVictimComm(raw rawMap) string {
	victim := asMap(raw["victim"])
	if comm := stringValue(victim, "comm"); comm != "" {
		return comm
	}
	trigger := asMap(raw["trigger_process"])
	if comm := stringValue(trigger, "comm"); comm != "" {
		return comm
	}
	return "unknown"
}

func (e spikeEvent) victimUnit() string {
	return e.victimUnitValue
}

func computeVictimUnit(raw rawMap, victimComm string) string {
	victim := asMap(raw["victim"])
	if unit := stringValue(victim, "unit"); unit != "" {
		return unit
	}
	for _, item := range asSlice(raw["top_processes"]) {
		proc := asMap(item)
		if valuesEqual(proc["pid"], victim["pid"]) || stringValue(proc, "comm") == victimComm {
			return stringValue(proc, "unit")
		}
	}
	trigger := asMap(raw["trigger_process"])
	return stringValue(trigger, "unit")
}

func (e spikeEvent) victimKind() string {
	return e.victimKindValue
}

func (e spikeEvent) dominantUnit() string {
	return e.dominantUnitValue
}

func computeDominantUnit(raw rawMap) string {
	for _, item := range asSlice(raw["top_units"]) {
		unit := stringValue(asMap(item), "unit")
		if isActionableUnit(unit) {
			return unit
		}
	}
	return ""
}

func (e spikeEvent) unitCPUPct(unitName string) float64 {
	if unitName == "" {
		return 0
	}
	for _, item := range asSlice(e.Raw["top_units"]) {
		unit := asMap(item)
		if stringValue(unit, "unit") == unitName {
			return cpuValue(unit["cpu_pct"])
		}
	}
	total := 0.0
	for _, item := range asSlice(e.Raw["top_processes"]) {
		proc := asMap(item)
		if stringValue(proc, "unit") == unitName {
			total += cpuValue(proc["cpu_pct"])
		}
	}
	return total
}

func (e spikeEvent) primarySuspect() rawMap {
	return e.primarySuspectValue
}

func (e spikeEvent) suspectLabel() string {
	return e.suspectLabelValue
}

func computePrimarySuspect(e spikeEvent) rawMap {
	suspects := asSlice(e.Raw["suspects"])
	if (e.victimKindValue == "generic" || e.victimKindValue == "saturation") && isActionableUnit(e.victimUnitValue) {
		victimCPU := e.unitCPUPct(e.victimUnitValue)
		if victimCPU >= 20 {
			return rawMap{"unit": e.victimUnitValue, "comm": e.victimUnitValue, "role": "victim-unit", "cpu_pct": victimCPU}
		}
	}
	for _, item := range suspects {
		suspect := asMap(item)
		unit := stringValue(suspect, "unit")
		cpuPct := cpuValue(suspect["cpu_pct"])
		if isMonitorUnit(unit) || (e.victimKindValue == "xorg" && isDisplayHostUnit(unit)) {
			continue
		}
		if stringValue(suspect, "role") == "concurrent" {
			continue
		}
		if (e.victimKindValue == "generic" || e.victimKindValue == "saturation") && e.dominantUnitValue != "" {
			if unit == e.dominantUnitValue || cpuPct < 5 {
				break
			}
		}
		if unit != "" || suspect["comm"] != nil {
			return compactSuspect(suspect)
		}
	}
	if e.dominantUnitValue != "" {
		return rawMap{"unit": e.dominantUnitValue, "comm": e.dominantUnitValue, "role": "dominant-unit"}
	}
	return rawMap{}
}

func computeSuspectLabel(suspect rawMap) string {
	if len(suspect) == 0 {
		return "unknown"
	}
	if unit := stringValue(suspect, "unit"); unit != "" {
		return unit
	}
	if comm := stringValue(suspect, "comm"); comm != "" {
		return comm
	}
	return "unknown"
}

func compactSuspect(suspect rawMap) rawMap {
	out := rawMap{}
	for _, key := range []string{"unit", "comm", "role", "cpu_pct"} {
		if suspect[key] != nil {
			out[key] = suspect[key]
		}
	}
	return out
}

func (e spikeEvent) topUnitLabel() string {
	return e.topUnitLabelValue
}

func (e spikeEvent) triggerCPUPct() float64 {
	return e.triggerCPUValue
}

func (e spikeEvent) monitorOverheadCPU() float64 {
	return e.monitorCPUValue
}

func computeMonitorOverheadCPU(raw rawMap) float64 {
	total := 0.0
	units := asSlice(raw["top_units"])
	if len(units) > 0 {
		for _, item := range units {
			unit := asMap(item)
			if isMonitorUnit(stringValue(unit, "unit")) {
				total += cpuValue(unit["cpu_pct"])
			}
		}
		return total
	}
	for _, item := range asSlice(raw["monitor_overhead"]) {
		total += cpuValue(asMap(item)["cpu_pct"])
	}
	return total
}

func (e spikeEvent) confidence() string {
	return e.confidenceValue
}

func (e spikeEvent) classification() string {
	return e.classificationValue
}

func (e spikeEvent) duration() float64 {
	return e.durationValue
}

func (e spikeEvent) notes() string {
	return e.notesValue
}

func (e spikeEvent) summaryNote() string {
	suspect := e.primarySuspect()
	if stringValue(suspect, "role") == "victim-unit" {
		return fmt.Sprintf("%s spiked inside active victim unit %s; other burst units are concurrent context", e.victimComm(), e.suspectLabel())
	}
	if e.suspectLabel() != "unknown" {
		return fmt.Sprintf("%s spiked; selected suspect %s from burst unit/process evidence", e.victimComm(), e.suspectLabel())
	}
	if e.notes() != "" {
		return e.notes()
	}
	return fmt.Sprintf("%s spiked but no clear suspect was captured", e.victimComm())
}

func (e spikeEvent) contextSummary() string {
	return e.contextSummaryValue
}

func (e spikeEvent) contextDetails() []string {
	return e.contextDetailsValue
}

func computeContextSummary(e spikeEvent) string {
	visible := e.visibleContextParts(false)
	var pieces []string
	for i, part := range visible {
		if i >= 2 {
			break
		}
		pieces = append(pieces, part.Text)
	}
	return strings.Join(pieces, "; ")
}

func computeContextDetails(e spikeEvent) []string {
	visible := e.visibleContextParts(true)
	out := make([]string, 0, 2)
	for i, part := range visible {
		if i >= 2 {
			break
		}
		out = append(out, part.Text)
	}
	return out
}

func (e spikeEvent) visibleContextParts(fullCommands bool) []contextSummaryPart {
	parts := e.contextParts(fullCommands)
	if len(parts) == 0 {
		return nil
	}
	sort.SliceStable(parts, func(i, j int) bool {
		pi, ci := e.contextSummaryPriority(parts[i])
		pj, cj := e.contextSummaryPriority(parts[j])
		if pi != pj {
			return pi < pj
		}
		return ci < cj
	})
	var visible []contextSummaryPart
	for _, part := range parts {
		priority, _ := e.contextSummaryPriority(part)
		if priority < 80 {
			visible = append(visible, part)
		}
	}
	if len(visible) == 0 {
		return parts
	}
	return visible
}

func (e spikeEvent) contextParts(fullCommands bool) []contextSummaryPart {
	textLimit := 60
	cmdLimit := 90
	if fullCommands {
		textLimit = 0
		cmdLimit = 0
	}
	var parts []contextSummaryPart
	victim := e.victim()
	if strings.HasPrefix(e.victimUnit(), "kitty-") && (victim["cwd"] != nil || victim["cmdline"] != nil) {
		detail := fmt.Sprintf("kitty victim %s %s", firstNonEmpty(stringValue(victim, "comm"), e.victimComm()), formatCPU(e.triggerCPUPct()))
		if victim["cwd"] != nil {
			detail += " cwd " + compactText(victim["cwd"], textLimit)
		}
		if victim["cmdline"] != nil {
			detail += " cmd " + inlineCode(victim["cmdline"], cmdLimit)
		}
		parts = append(parts, contextSummaryPart{Text: detail, Unit: e.victimUnit(), CPUPct: e.triggerCPUPct(), Kind: "victim"})
	}
	context := asMap(e.Raw["context"])
	window := asMap(context["window"])
	if stringValue(window, "status") == "ok" {
		detail := "active window " + compactText(firstNonEmpty(stringValue(window, "title"), "untitled"), 70)
		if unit := stringValue(window, "unit"); unit != "" && unit != e.victimUnit() && unit != e.suspectLabel() {
			detail += " unit " + compactText(unit, 70)
		}
		if comm := stringValue(window, "comm"); comm != "" {
			detail += " process " + compactText(comm, 30)
		}
		parts = append(parts, contextSummaryPart{Text: detail, Unit: stringValue(window, "unit"), Kind: "window"})
	}
	for _, item := range asSlice(context["browsers"]) {
		browser := asMap(item)
		name := firstNonEmpty(stringValue(browser, "browser"), "browser")
		unit := stringValue(browser, "unit")
		prefix := e.contextPrefix(browser["unit"])
		processes := asSlice(browser["processes"])
		var renderers []any
		for _, proc := range processes {
			if stringValue(asMap(proc), "kind") == "renderer" {
				renderers = append(renderers, proc)
			}
		}
		renderer := firstContextProcess(renderers)
		tabs := asSlice(browser["tabs"])
		cpuPct := 0.0
		if len(renderer) > 0 {
			cpuPct = cpuValue(renderer["cpu_pct"])
			suffix := " renderer " + formatCPU(renderer["cpu_pct"])
			if renderer["renderer_client_id"] != nil {
				suffix += " renderer-client-id " + stringValue(renderer, "renderer_client_id")
			}
			active := activeBrowserTab(tabs)
			if len(active) > 0 && !anyBrowserTabHasScore(tabs) {
				suffix += "; active tab " + compactText(firstNonEmpty(stringValue(active, "title"), "untitled"), 50) + " " + compactText(active["url"], 70)
			} else {
				suffix += "; " + browserTabsSummary(tabs, 3)
			}
			parts = append(parts, contextSummaryPart{Text: prefix + name + suffix, Unit: unit, CPUPct: cpuPct, Kind: "browser"})
		} else if len(tabs) > 0 {
			active := activeBrowserTab(tabs)
			if len(active) > 0 && !anyBrowserTabHasScore(tabs) {
				parts = append(parts, contextSummaryPart{Text: prefix + name + " active tab " + compactText(firstNonEmpty(stringValue(active, "title"), "untitled"), 50) + " " + compactText(active["url"], 70), Unit: unit, Kind: "browser"})
			} else {
				parts = append(parts, contextSummaryPart{Text: prefix + name + " " + browserTabsSummary(tabs, 3), Unit: unit, Kind: "browser"})
			}
		} else if status := stringValue(browser, "status"); status != "" {
			parts = append(parts, contextSummaryPart{Text: fmt.Sprintf("%s%s tabs %s", prefix, name, status), Unit: unit, Kind: "browser"})
		}
	}
	for _, item := range asSlice(context["kitty"]) {
		kitty := asMap(item)
		unit := stringValue(kitty, "unit")
		prefix := e.contextPrefix(kitty["unit"])
		proc := e.expandContextProcess(firstContextProcess(asSlice(kitty["unit_processes"])))
		if len(proc) > 0 {
			cpuPct := cpuValue(proc["cpu_pct"])
			detail := fmt.Sprintf("%skitty process %s %s", prefix, firstNonEmpty(stringValue(proc, "comm"), "unknown"), formatCPU(proc["cpu_pct"]))
			if proc["cwd"] != nil {
				detail += " cwd " + compactText(proc["cwd"], textLimit)
			}
			if proc["cmdline"] != nil {
				detail += " cmd " + inlineCode(proc["cmdline"], cmdLimit)
			}
			parts = append(parts, contextSummaryPart{Text: detail, Unit: unit, CPUPct: cpuPct, Kind: "kitty"})
			continue
		}
		windows := asSlice(kitty["windows"])
		if len(windows) > 0 {
			foreground := asSlice(asMap(windows[0])["foreground_processes"])
			fg := e.expandContextProcess(firstContextProcess(foreground))
			if len(fg) > 0 {
				parts = append(parts, contextSummaryPart{Text: fmt.Sprintf("%skitty foreground %s cwd %s", prefix, firstNonEmpty(stringValue(fg, "comm"), "unknown"), compactText(fg["cwd"], 60)), Unit: unit, Kind: "kitty"})
			}
		}
	}
	for _, item := range asSlice(context["docker"]) {
		docker := asMap(item)
		unit := stringValue(docker, "unit")
		prefix := e.contextPrefix(docker["unit"])
		label := firstNonEmpty(stringValue(docker, "name"), stringValue(docker, "short_id"), stringValue(docker, "unit"), "unknown")
		detail := prefix + "docker container " + label
		if docker["image"] != nil {
			detail += " image " + compactText(docker["image"], 60)
		}
		if docker["compose_service"] != nil {
			detail += " compose service " + compactText(docker["compose_service"], 40)
		}
		proc := firstContextProcess(asSlice(docker["processes"]))
		cpuPct := 0.0
		if len(proc) > 0 {
			cpuPct = cpuValue(proc["cpu_pct"])
			detail += fmt.Sprintf(" process %s %s", firstNonEmpty(stringValue(proc, "comm"), "unknown"), formatCPU(proc["cpu_pct"]))
		} else if docker["inspect_status"] != nil {
			detail += " inspect " + stringValue(docker, "inspect_status")
		}
		parts = append(parts, contextSummaryPart{Text: detail, Unit: unit, CPUPct: cpuPct, Kind: "docker"})
	}
	audio := asMap(context["audio"])
	for i, item := range asSlice(audio["nodes"]) {
		if i >= 2 {
			break
		}
		node := asMap(item)
		label := firstNonEmpty(stringValue(node, "description"), stringValue(node, "name"), stringValue(node, "id"), "unknown")
		detail := "audio node " + label
		if node["media_class"] != nil {
			detail += " class " + compactText(node["media_class"], 40)
		}
		if busyQuantum := stringValue(node, "busy_quantum"); busyQuantum != "" && busyQuantum != "---" {
			detail += " B/Q " + busyQuantum
		} else if busy := stringValue(node, "busy"); busy != "" && busy != "---" {
			detail += " busy " + busy
		}
		if node["errors"] != nil {
			detail += " errors " + stringValue(node, "errors")
		}
		parts = append(parts, contextSummaryPart{Text: detail, Kind: "audio"})
	}
	if len(asSlice(audio["nodes"])) == 0 {
		if status := stringValue(audio, "status"); status != "" && status != "ok" {
			parts = append(parts, contextSummaryPart{Text: "audio context " + status, Kind: "audio"})
		}
	}
	return parts
}

func (e spikeEvent) expandContextProcess(proc rawMap) rawMap {
	if len(proc) == 0 {
		return rawMap{}
	}
	expanded := rawMap{}
	for k, v := range proc {
		expanded[k] = v
	}
	procPID := proc["pid"]
	procUnit := stringValue(proc, "unit")
	procComm := stringValue(proc, "comm")
	for _, item := range asSlice(e.Raw["top_processes"]) {
		topProc := asMap(item)
		samePID := procPID != nil && valuesEqual(topProc["pid"], procPID)
		sameProcess := procUnit != "" && procComm != "" && stringValue(topProc, "unit") == procUnit && stringValue(topProc, "comm") == procComm
		if !samePID && !sameProcess {
			continue
		}
		for _, key := range []string{"cmdline", "cwd"} {
			current := stringValue(expanded, key)
			candidate := stringValue(topProc, key)
			if len(candidate) > len(current) {
				expanded[key] = candidate
			}
		}
		if topProc["cpu_pct"] != nil {
			expanded["cpu_pct"] = topProc["cpu_pct"]
		}
		break
	}
	return expanded
}

func (e spikeEvent) contextSummaryPriority(part contextSummaryPart) (int, float64) {
	relevantUnits := map[string]bool{e.victimUnit(): true, e.suspectLabel(): true, e.topUnitLabel(): true}
	if part.Kind == "victim" {
		return -10, -part.CPUPct
	}
	if part.Unit != "" && relevantUnits[part.Unit] {
		return 0, -part.CPUPct
	}
	if part.CPUPct >= 20 {
		return 20, -part.CPUPct
	}
	if part.Kind == "browser" && part.CPUPct < 10 {
		return 80, -part.CPUPct
	}
	return 40, -part.CPUPct
}

func (e spikeEvent) contextPrefix(unit any) string {
	name := fmt.Sprint(orEmpty(unit))
	if name == "" || name == e.suspectLabel() || name == e.victimUnit() {
		return ""
	}
	if interactiveKinds[e.victimKind()] && isDockerUnit(name) {
		return "system pressure "
	}
	return "concurrent "
}

func (e spikeEvent) visibleSuspects() []rawMap {
	var visible []rawMap
	for _, item := range asSlice(e.Raw["suspects"]) {
		suspect := asMap(item)
		unit := stringValue(suspect, "unit")
		if isMonitorUnit(unit) || (e.victimKind() == "xorg" && isDisplayHostUnit(unit)) {
			continue
		}
		if cpuValue(suspect["cpu_pct"]) < 5 && unit != e.suspectLabel() {
			continue
		}
		visible = append(visible, suspect)
	}
	return visible
}

func nowLocal() string {
	return time.Now().Format("2006-01-02 15:04:05 MST")
}

func homeDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return home
}

func expandUser(path string) string {
	if path == "~" {
		return homeDir()
	}
	if strings.HasPrefix(path, "~/") {
		return filepath.Join(homeDir(), path[2:])
	}
	return path
}

func notesRoot() string {
	if value := os.Getenv("DOTFILES_SPIKES_NOTES_ROOT"); value != "" {
		return expandUser(value)
	}
	return filepath.Join(homeDir(), "data/notes/foam")
}

func spikesDir() string {
	if value := os.Getenv("DOTFILES_SPIKES_DIR"); value != "" {
		return expandUser(value)
	}
	return filepath.Join(notesRoot(), "ops/system-health/spikes")
}

func stateDir() string {
	if value := os.Getenv("DOTFILES_SPIKES_STATE_DIR"); value != "" {
		return expandUser(value)
	}
	return filepath.Join(homeDir(), ".local/state/dotfiles/system-spikes")
}

func readEvents() ([]spikeEvent, error) {
	return readEventsFromDir(filepath.Join(stateDir(), "events"))
}

func readEventsFromDir(eventsDir string) ([]spikeEvent, error) {
	entries, err := os.ReadDir(eventsDir)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
	var events []spikeEvent
	readIndex := 0
	err = readRawEvents(eventsDir, entries, func(raw rawMap) {
		events = append(events, newSpikeEvent(raw, readIndex))
		readIndex++
	})
	if err != nil {
		return nil, err
	}
	sort.SliceStable(events, func(i, j int) bool {
		return events[i].startedAt().Before(events[j].startedAt())
	})
	if err := enrichRecentEventDetails(eventsDir, entries, events); err != nil {
		return nil, err
	}
	return events, nil
}

func readRawEvents(eventsDir string, entries []os.DirEntry, visit func(raw rawMap)) error {
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".jsonl") {
			continue
		}
		path := filepath.Join(eventsDir, entry.Name())
		file, err := os.Open(path)
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(file)
		scanner.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" {
				continue
			}
			var raw rawMap
			if err := json.Unmarshal([]byte(line), &raw); err != nil {
				continue
			}
			visit(raw)
		}
		if err := scanner.Err(); err != nil {
			_ = file.Close()
			return err
		}
		_ = file.Close()
	}
	return nil
}

func enrichRecentEventDetails(eventsDir string, entries []os.DirEntry, events []spikeEvent) error {
	targets := detailedEventTargets(events)
	if len(targets) == 0 {
		return nil
	}
	readIndex := 0
	return readRawEvents(eventsDir, entries, func(raw rawMap) {
		if eventIndex, ok := targets[readIndex]; ok {
			events[eventIndex].enrichDetails(raw)
		}
		readIndex++
	})
}

func detailedEventTargets(events []spikeEvent) map[int]int {
	targets := make(map[int]int)
	for _, index := range recentEventIndexes(events, 12) {
		targets[events[index].readIndex] = index
	}
	for _, index := range recentIncidentIndexes(events, 8) {
		targets[events[index].readIndex] = index
	}
	bySource := make(map[string][]int)
	for index, event := range events {
		bySource[sourceStem(event)] = append(bySource[sourceStem(event)], index)
	}
	for _, indexes := range bySource {
		start := len(indexes) - 10
		if start < 0 {
			start = 0
		}
		for _, index := range indexes[start:] {
			targets[events[index].readIndex] = index
		}
	}
	return targets
}

func recentIncidentIndexes(events []spikeEvent, limit int) []int {
	groups := incidentIndexGroups(events)
	start := len(groups) - limit
	if start < 0 {
		start = 0
	}
	var indexes []int
	for _, group := range groups[start:] {
		indexes = append(indexes, group...)
	}
	return indexes
}

func incidentIndexGroups(events []spikeEvent) [][]int {
	var groups [][]int
	var current []int
	for index, event := range events {
		if len(current) == 0 {
			current = []int{index}
			continue
		}
		previous := events[current[len(current)-1]]
		gap := event.startedAt().Sub(previous.startedAt()).Seconds()
		if incidentKey(event) == incidentKey(previous) && gap <= incidentGapSeconds {
			current = append(current, index)
			continue
		}
		groups = append(groups, current)
		current = []int{index}
	}
	if len(current) > 0 {
		groups = append(groups, current)
	}
	return groups
}

func recentEventIndexes(events []spikeEvent, limit int) []int {
	start := len(events) - limit
	if start < 0 {
		start = 0
	}
	indexes := make([]int, 0, len(events)-start)
	for index := start; index < len(events); index++ {
		indexes = append(indexes, index)
	}
	return indexes
}

func ensureDirs() error {
	root := spikesDir()
	year := time.Now().Format("2006")
	for _, path := range []string{root, filepath.Join(root, "sources"), filepath.Join(root, "reports", year)} {
		if err := os.MkdirAll(path, 0o755); err != nil {
			return err
		}
	}
	return nil
}

func preserveManualBlock(path string) string {
	file, err := os.Open(path)
	if err != nil {
		return defaultManualBlock()
	}
	defer file.Close()
	text, err := io.ReadAll(file)
	if err != nil {
		return defaultManualBlock()
	}
	body := string(text)
	start := strings.Index(body, manualStart)
	end := strings.Index(body, manualEnd)
	if start < 0 || end < start {
		return defaultManualBlock()
	}
	return body[start : end+len(manualEnd)]
}

func defaultManualBlock() string {
	return strings.Join([]string{
		manualStart,
		"",
		"## Review Reminders",
		"",
		"- [ ] **Review system spike patterns**",
		"",
		"  Open [[system-spikes]], inspect repeated high-confidence suspects, and decide whether each pattern needs a fix, threshold adjustment, or allowlist entry.",
		"",
		manualEnd,
	}, "\n")
}

func patternKey(event spikeEvent) string {
	return event.victimComm() + "\x00" + event.suspectLabel()
}

func aggregatePatterns(events []spikeEvent) []patternRow {
	groups := make(map[string][]spikeEvent)
	var order []string
	for _, event := range events {
		key := patternKey(event)
		if _, ok := groups[key]; !ok {
			order = append(order, key)
		}
		groups[key] = append(groups[key], event)
	}
	rows := make([]patternRow, 0, len(groups))
	for _, key := range order {
		group := groups[key]
		parts := strings.SplitN(key, "\x00", 2)
		victim, suspect := parts[0], parts[1]
		durations := make([]float64, 0, len(group))
		victimUnits := newCounter()
		topUnits := newCounter()
		confidences := newCounter()
		classifications := newCounter()
		maxDuration := 0.0
		durationTotal := 0.0
		maxTriggerCPU := 0.0
		maxMonitorOverhead := 0.0
		for _, event := range group {
			if event.duration() > 0 {
				durations = append(durations, event.duration())
				durationTotal += event.duration()
				if event.duration() > maxDuration {
					maxDuration = event.duration()
				}
			}
			victimUnits.Add(firstNonEmpty(event.victimUnit(), "unknown"))
			topUnits.Add(event.topUnitLabel())
			confidences.Add(event.confidence())
			classifications.Add(event.classification())
			if event.triggerCPUPct() > maxTriggerCPU {
				maxTriggerCPU = event.triggerCPUPct()
			}
			if event.monitorOverheadCPU() > maxMonitorOverhead {
				maxMonitorOverhead = event.monitorOverheadCPU()
			}
		}
		avgDuration := 0.0
		if len(durations) > 0 {
			avgDuration = round(durationTotal/float64(len(durations)), 2)
		}
		rows = append(rows, patternRow{
			Victim:             victim,
			Suspect:            suspect,
			Count:              len(group),
			VictimUnit:         victimUnits.MostCommon(1)[0].Name,
			TopUnit:            topUnits.MostCommon(1)[0].Name,
			FirstSeen:          formatEventTime(group[0].startedAt()),
			LastSeen:           formatEventTime(group[len(group)-1].startedAt()),
			AvgDuration:        avgDuration,
			MaxDuration:        round(maxDuration, 2),
			MaxTriggerCPU:      round(maxTriggerCPU, 1),
			MaxMonitorOverhead: round(maxMonitorOverhead, 1),
			Confidence:         confidences.MostCommon(1)[0].Name,
			Classification:     classifications.MostCommon(1)[0].Name,
		})
	}
	sort.SliceStable(rows, func(i, j int) bool {
		if rows[i].Count != rows[j].Count {
			return rows[i].Count > rows[j].Count
		}
		return rows[i].MaxDuration > rows[j].MaxDuration
	})
	return rows
}

func incidentKey(event spikeEvent) string {
	return event.victimKind() + "\x00" + event.victimComm()
}

func aggregateIncidents(events []spikeEvent) []incidentRow {
	sortedEvents := append([]spikeEvent(nil), events...)
	sort.SliceStable(sortedEvents, func(i, j int) bool { return sortedEvents[i].startedAt().Before(sortedEvents[j].startedAt()) })
	var incidents [][]spikeEvent
	var current []spikeEvent
	for _, event := range sortedEvents {
		if len(current) == 0 {
			current = []spikeEvent{event}
			continue
		}
		previous := current[len(current)-1]
		gap := event.startedAt().Sub(previous.startedAt()).Seconds()
		if incidentKey(event) == incidentKey(previous) && gap <= incidentGapSeconds {
			current = append(current, event)
			continue
		}
		incidents = append(incidents, current)
		current = []spikeEvent{event}
	}
	if len(current) > 0 {
		incidents = append(incidents, current)
	}
	rows := make([]incidentRow, 0, len(incidents))
	for _, group := range incidents {
		victims := newCounter()
		victimUnits := newCounter()
		suspects := newCounter()
		topUnits := newCounter()
		confidences := newCounter()
		classifications := newCounter()
		maxTriggerCPU := 0.0
		maxMonitorOverhead := 0.0
		var contexts []string
		for i := len(group) - 1; i >= 0; i-- {
			if context := group[i].contextSummary(); context != "" {
				contexts = append(contexts, context)
			}
		}
		for _, event := range group {
			victims.Add(event.victimComm())
			victimUnits.Add(firstNonEmpty(event.victimUnit(), "unknown"))
			suspects.Add(event.suspectLabel())
			topUnits.Add(event.topUnitLabel())
			confidences.Add(event.confidence())
			classifications.Add(event.classification())
			if event.triggerCPUPct() > maxTriggerCPU {
				maxTriggerCPU = event.triggerCPUPct()
			}
			if event.monitorOverheadCPU() > maxMonitorOverhead {
				maxMonitorOverhead = event.monitorOverheadCPU()
			}
		}
		context := ""
		if len(contexts) > 0 {
			context = contexts[0]
		}
		rows = append(rows, incidentRow{
			Start:              group[0].startedAt(),
			End:                group[len(group)-1].startedAt(),
			Count:              len(group),
			Victim:             victims.MostCommon(1)[0].Name,
			VictimUnit:         victimUnits.MostCommon(1)[0].Name,
			Suspects:           counterSummary(suspects, 3),
			TopUnits:           counterSummary(topUnits, 3),
			MaxTriggerCPU:      round(maxTriggerCPU, 1),
			MaxMonitorOverhead: round(maxMonitorOverhead, 1),
			Confidence:         confidences.MostCommon(1)[0].Name,
			Classification:     classifications.MostCommon(1)[0].Name,
			Context:            context,
		})
	}
	sort.SliceStable(rows, func(i, j int) bool { return rows[i].Start.After(rows[j].Start) })
	return rows
}

func recentEvents(events []spikeEvent, limit int) []spikeEvent {
	start := len(events) - limit
	if start < 0 {
		start = 0
	}
	out := append([]spikeEvent(nil), events[start:]...)
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

func writeMain(events []spikeEvent) error {
	path := filepath.Join(spikesDir(), "system-spikes.md")
	patterns := aggregatePatterns(events)
	incidents := aggregateIncidents(events)
	victims := newCounter()
	victimUnits := newCounter()
	suspects := newCounter()
	topUnits := newCounter()
	classifications := newCounter()
	today := time.Now().In(time.Local).Format("2006-01-02")
	todayCount := 0
	highConfidence := 0
	monitorOverheadEvents := 0
	for _, event := range events {
		victims.Add(event.victimComm())
		victimUnits.Add(firstNonEmpty(event.victimUnit(), "unknown"))
		suspects.Add(event.suspectLabel())
		topUnits.Add(event.topUnitLabel())
		classifications.Add(event.classification())
		if event.startedAt().In(time.Local).Format("2006-01-02") == today {
			todayCount++
		}
		if event.confidence() == "high" {
			highConfidence++
		}
		if event.monitorOverheadCPU() >= 5 {
			monitorOverheadEvents++
		}
	}
	manual := preserveManualBlock(path)
	recent := recentEvents(events, 12)
	var lines []string
	lines = append(lines,
		"# System Spikes",
		"",
		"@tags #system-health #performance #ops",
		"",
		"This generated report summarizes interactive CPU spikes captured by `system-spike-watch`; start here to see victims, likely suspects, confidence, and short evidence.",
		"@id system-spikes-report",
		"",
		"Last generated: "+nowLocal(),
		"",
		"## Current Status",
		"",
		fmt.Sprintf("- Spikes today: `%d`", todayCount),
		fmt.Sprintf("- Recorded spikes: `%d`", len(events)),
		fmt.Sprintf("- Unique patterns: `%d`", len(patterns)),
		fmt.Sprintf("- Unique incidents: `%d`", len(incidents)),
		fmt.Sprintf("- High-confidence events: `%d`", highConfidence),
		fmt.Sprintf("- Events with monitor overhead: `%d`", monitorOverheadEvents),
		"- Rules: [[system-spike-rules]]",
		"- Runbook: [[system-spike-runbook]]",
		"- Coverage: [[system-spike-coverage]]",
		fmt.Sprintf("- Monthly digest: [[%s]]", time.Now().Format("system-spikes-2006-01")),
		"",
		"## Top Victims",
		"",
	)
	lines = append(lines, counterLines(victims, "No victim processes recorded.")...)
	lines = append(lines, "", "## Top Victim Units", "")
	lines = append(lines, counterLines(victimUnits, "No victim units recorded.")...)
	lines = append(lines, "", "## Top Suspects", "")
	lines = append(lines, counterLines(suspects, "No suspects recorded.")...)
	lines = append(lines, "", "## Dominant Burst Units", "")
	lines = append(lines, counterLines(topUnits, "No dominant burst units recorded.")...)
	lines = append(lines, "", "## Classifications", "")
	lines = append(lines, counterLines(classifications, "No classifications recorded.")...)
	lines = append(lines, "", "## Monitor Overhead", "")
	overheadEvents := append([]spikeEvent(nil), events...)
	sort.SliceStable(overheadEvents, func(i, j int) bool {
		return overheadEvents[i].monitorOverheadCPU() > overheadEvents[j].monitorOverheadCPU()
	})
	addedOverhead := 0
	for _, event := range overheadEvents {
		if event.monitorOverheadCPU() < 5 {
			continue
		}
		if addedOverhead >= 8 {
			break
		}
		lines = append(lines, fmt.Sprintf("- `%s` monitor `%s` while victim `%s` top unit `%s`", formatEventTime(event.startedAt()), formatCPU(event.monitorOverheadCPU()), event.victimComm(), event.topUnitLabel()))
		addedOverhead++
	}
	if addedOverhead == 0 {
		lines = append(lines, "- No monitor overhead above 5% captured.")
	}
	lines = append(lines, "", "## Top Patterns", "")
	if len(patterns) > 0 {
		for i, row := range patterns {
			if i >= 10 {
				break
			}
			lines = append(lines, fmt.Sprintf("- `%s` <- `%s`: `%d` events, victim unit `%s`, top unit `%s`, confidence `%s`, classification `%s`, max trigger `%s`, max monitor `%s`, avg `%ss`, max `%ss`, last `%s`", row.Victim, row.Suspect, row.Count, row.VictimUnit, row.TopUnit, row.Confidence, row.Classification, formatCPU(row.MaxTriggerCPU), formatCPU(row.MaxMonitorOverhead), prettyFloat(row.AvgDuration), prettyFloat(row.MaxDuration), row.LastSeen))
		}
	} else {
		lines = append(lines, "- No spike patterns recorded.")
	}
	lines = append(lines, "", "## Recent Incidents", "")
	if len(incidents) > 0 {
		for i, row := range incidents {
			if i >= 8 {
				break
			}
			context := ""
			if row.Context != "" {
				context = ", context " + row.Context
			}
			lines = append(lines, fmt.Sprintf("- `%s` to `%s` victim `%s` unit `%s` events `%d` suspects `%s` top units `%s` max trigger `%s` max monitor `%s` confidence `%s` classification `%s`%s", formatEventTime(row.Start), formatEventTime(row.End), row.Victim, row.VictimUnit, row.Count, row.Suspects, row.TopUnits, formatCPU(row.MaxTriggerCPU), formatCPU(row.MaxMonitorOverhead), row.Confidence, row.Classification, context))
		}
	} else {
		lines = append(lines, "- No spike incidents recorded.")
	}
	lines = append(lines, "", "## Recent Events", "")
	if len(recent) > 0 {
		for _, event := range recent {
			lines = append(lines, fmt.Sprintf("- `%s` victim `%s` unit `%s` suspect `%s` top unit `%s` trigger `%s` monitor `%s` confidence `%s` classification `%s`: %s", formatEventTime(event.startedAt()), event.victimComm(), firstNonEmpty(event.victimUnit(), "unknown"), event.suspectLabel(), event.topUnitLabel(), formatCPU(event.triggerCPUPct()), formatCPU(event.monitorOverheadCPU()), event.confidence(), event.classification(), event.summaryNote()))
			for _, detail := range event.contextDetails() {
				lines = append(lines, "  - context: "+detail)
			}
		}
	} else {
		lines = append(lines, "- No recent spike events recorded.")
	}
	lines = append(lines,
		"",
		"## Source Pages",
		"",
		"- [[system-spike-xorg]]",
		"- [[system-spike-compositor]]",
		"- [[system-spike-audio]]",
		"- [[system-spike-input]]",
		"- [[system-spike-generic]]",
		"",
		"## Quick Commands",
		"",
		"```sh",
		"dotfiles-spikes update",
		"```",
		"",
		"```sh",
		"system-spike-watch check",
		"```",
		"",
		"```sh",
		"systemd-cgtop --batch --iterations=1 --raw --cpu=percentage --depth=4",
		"```",
		"",
		manual,
		"",
	)
	return writeText(path, strings.Join(lines, "\n"))
}

func counterLines(counter *orderedCounter, empty string) []string {
	if counter.Len() == 0 {
		return []string{"- " + empty}
	}
	var lines []string
	for _, item := range counter.MostCommon(10) {
		lines = append(lines, fmt.Sprintf("- `%s`: `%d`", item.Name, item.Count))
	}
	return lines
}

func firstContextProcess(processes []any) rawMap {
	for _, item := range processes {
		proc := asMap(item)
		comm := stringValue(proc, "comm")
		if comm != "kitty" && comm != "brave" && comm != "chromium" {
			return proc
		}
	}
	if len(processes) > 0 {
		return asMap(processes[0])
	}
	return rawMap{}
}

func activeBrowserTab(tabs []any) rawMap {
	for _, item := range tabs {
		tab := asMap(item)
		if boolValue(tab, "active") {
			return tab
		}
	}
	return rawMap{}
}

func browserTabsSummary(tabs []any, limit int) string {
	if len(tabs) == 0 {
		return "0 candidate tabs"
	}
	var items []string
	for i, item := range tabs {
		if i >= limit {
			break
		}
		items = append(items, browserTabSummaryItem(asMap(item)))
	}
	remaining := len(tabs) - len(items)
	suffix := ""
	if remaining > 0 {
		suffix = fmt.Sprintf("; +%d more", remaining)
	}
	label := "candidate tabs"
	if anyBrowserTabHasScore(tabs) {
		label = "probable tabs"
	}
	return fmt.Sprintf("%s %s%s", label, strings.Join(items, "; "), suffix)
}

func anyBrowserTabHasScore(tabs []any) bool {
	for _, item := range tabs {
		if browserTabHasScore(asMap(item)) {
			return true
		}
	}
	return false
}

func browserTabHasScore(tab rawMap) bool {
	return boolValue(tab, "probable") || cpuValue(tab["score"]) > 0 || cpuValue(tab["browser_task_cpu_pct"]) > 0
}

func browserTabSummaryItem(tab rawMap) string {
	title := compactText(firstNonEmpty(stringValue(tab, "title"), "untitled"), 45)
	details := []string{title}
	if tab["browser_task_cpu_pct"] != nil && cpuValue(tab["browser_task_cpu_pct"]) != 0 {
		details = append(details, "cpu "+formatFloat(tab["browser_task_cpu_pct"])+"%")
		if boolValue(tab, "browser_task_shared") {
			details = append(details, "shared-process")
		}
	}
	if browserTabHasScore(tab) && (tab["browser_task_cpu_pct"] == nil || cpuValue(tab["browser_task_cpu_pct"]) == 0) {
		details = append(details, "score "+formatFloat(tab["score"]))
		if tab["task_ms"] != nil && cpuValue(tab["task_ms"]) != 0 {
			details = append(details, "task "+formatFloat(tab["task_ms"])+"ms")
		}
		if tab["script_ms"] != nil && cpuValue(tab["script_ms"]) != 0 {
			details = append(details, "script "+formatFloat(tab["script_ms"])+"ms")
		}
	}
	if tab["visibility_state"] != nil {
		details = append(details, stringValue(tab, "visibility_state"))
	}
	if url := compactText(tab["url"], 60); url != "" {
		details = append(details, url)
	}
	return strings.Join(details, " ")
}

func processEvidenceLabel(proc rawMap) string {
	pieces := []string{inlineCode(firstNonEmpty(stringValue(proc, "comm"), "unknown"), 50)}
	if proc["kind"] != nil {
		pieces = append(pieces, "kind "+inlineCode(proc["kind"], 40))
	}
	if proc["renderer_client_id"] != nil {
		pieces = append(pieces, "renderer-client-id "+inlineCode(proc["renderer_client_id"], 20))
	}
	if cpu := cpuValue(proc["cpu_pct"]); cpu > 0 {
		pieces = append(pieces, formatCPU(cpu))
	}
	if proc["cwd"] != nil {
		pieces = append(pieces, "cwd "+inlineCode(proc["cwd"], 90))
	}
	if proc["cmdline"] != nil {
		pieces = append(pieces, "cmd "+inlineCode(proc["cmdline"], 140))
	}
	return strings.Join(pieces, " ")
}

func audioNodeEvidenceLabel(node rawMap) string {
	label := firstNonEmpty(stringValue(node, "description"), stringValue(node, "name"), stringValue(node, "id"), "unknown")
	pieces := []string{"node " + inlineCode(label, 90)}
	if node["id"] != nil {
		pieces = append(pieces, "id "+inlineCode(node["id"], 12))
	}
	if node["media_class"] != nil {
		pieces = append(pieces, "class "+inlineCode(node["media_class"], 50))
	}
	if node["app_name"] != nil {
		pieces = append(pieces, "app "+inlineCode(node["app_name"], 60))
	}
	if busyQuantum := stringValue(node, "busy_quantum"); busyQuantum != "" && busyQuantum != "---" {
		pieces = append(pieces, "B/Q "+inlineCode(busyQuantum, 20))
	}
	if busy := stringValue(node, "busy"); busy != "" && busy != "---" {
		pieces = append(pieces, "BUSY "+inlineCode(busy, 20))
	}
	if waitQuantum := stringValue(node, "wait_quantum"); waitQuantum != "" && waitQuantum != "---" {
		pieces = append(pieces, "W/Q "+inlineCode(waitQuantum, 20))
	}
	if node["errors"] != nil {
		pieces = append(pieces, "errors "+inlineCode(node["errors"], 20))
	}
	if node["format"] != nil {
		pieces = append(pieces, "format "+inlineCode(node["format"], 80))
	}
	return strings.Join(pieces, " ")
}

func browserTabEvidenceLabel(tab rawMap) string {
	var pieces []string
	if boolValue(tab, "probable") {
		pieces = append(pieces, "probable")
	}
	if boolValue(tab, "active") {
		pieces = append(pieces, "active")
	}
	pieces = append(pieces, inlineCode(firstNonEmpty(stringValue(tab, "title"), "untitled"), 90))
	pieces = append(pieces, inlineCode(tab["url"], 120))
	if tab["browser_task_cpu_pct"] != nil && cpuValue(tab["browser_task_cpu_pct"]) != 0 {
		pieces = append(pieces, "browser cpu "+inlineCode(formatFloat(tab["browser_task_cpu_pct"])+"%", 20))
		if tab["browser_task_process_id"] != nil {
			pieces = append(pieces, "browser-process-id "+inlineCode(formatID(tab["browser_task_process_id"]), 20))
		}
		if tab["browser_task_os_pid"] != nil {
			pieces = append(pieces, "os-pid "+inlineCode(formatID(tab["browser_task_os_pid"]), 20))
		}
		if tab["browser_task_source"] != nil {
			pieces = append(pieces, "source "+inlineCode(tab["browser_task_source"], 40))
		}
		if tab["browser_task_age_s"] != nil && cpuValue(tab["browser_task_age_s"]) != 0 {
			pieces = append(pieces, "age "+inlineCode(formatFloat(tab["browser_task_age_s"])+"s", 20))
		}
		if boolValue(tab, "browser_task_shared") {
			pieces = append(pieces, "shared-process")
		}
	}
	if browserTabHasScore(tab) && (tab["browser_task_cpu_pct"] == nil || cpuValue(tab["browser_task_cpu_pct"]) == 0) {
		pieces = append(pieces, "score "+inlineCode(formatFloat(tab["score"]), 20))
	}
	if tab["score_reason"] != nil {
		pieces = append(pieces, "reason "+inlineCode(tab["score_reason"], 120))
	} else if tab["task_ms"] != nil && cpuValue(tab["task_ms"]) != 0 {
		pieces = append(pieces, "task "+inlineCode(formatFloat(tab["task_ms"])+"ms", 20))
	}
	if tab["visibility_state"] != nil {
		pieces = append(pieces, "visibility "+inlineCode(tab["visibility_state"], 20))
	}
	if tab["match"] != nil {
		pieces = append(pieces, "match "+inlineCode(tab["match"], 40))
	}
	return strings.Join(pieces, " ")
}

func contextEvidenceLines(event spikeEvent) []string {
	context := asMap(event.Raw["context"])
	var lines []string
	window := asMap(context["window"])
	if len(window) > 0 {
		if stringValue(window, "status") == "ok" {
			parts := []string{"active window " + inlineCode(firstNonEmpty(stringValue(window, "title"), "untitled"), 100)}
			if window["id"] != nil {
				parts = append(parts, "id "+inlineCode(window["id"], 20))
			}
			if window["pid"] != nil {
				parts = append(parts, "pid "+inlineCode(window["pid"], 20))
			}
			if window["unit"] != nil {
				parts = append(parts, "unit "+inlineCode(window["unit"], 90))
			}
			if window["comm"] != nil {
				parts = append(parts, "process "+inlineCode(window["comm"], 50))
			}
			if window["cwd"] != nil {
				parts = append(parts, "cwd "+inlineCode(window["cwd"], 90))
			}
			if window["cmdline"] != nil {
				parts = append(parts, "cmd "+inlineCode(window["cmdline"], 140))
			}
			lines = append(lines, strings.Join(parts, " "))
		} else if status := stringValue(window, "status"); status != "" {
			extra := ""
			if window["error"] != nil {
				extra = " error " + inlineCode(window["error"], 100)
			}
			lines = append(lines, "active window context: "+inlineCode(status, 60)+extra)
		}
	}
	for _, item := range asSlice(context["kitty"]) {
		kitty := asMap(item)
		unit := firstNonEmpty(stringValue(kitty, "unit"), "unknown")
		processes := asSlice(kitty["unit_processes"])
		if len(processes) > 0 {
			var details []string
			for i, proc := range processes {
				if i >= 3 {
					break
				}
				details = append(details, processEvidenceLabel(asMap(proc)))
			}
			lines = append(lines, fmt.Sprintf("kitty unit %s process evidence: %s", inlineCode(unit, 80), strings.Join(details, ", ")))
		}
		if status := stringValue(kitty, "status"); status != "" && status != "ok" {
			extra := ""
			if kitty["error"] != nil {
				extra = " error " + inlineCode(kitty["error"], 100)
			}
			lines = append(lines, "kitty remote context: "+inlineCode(status, 60)+extra)
		}
		for i, windowItem := range asSlice(kitty["windows"]) {
			if i >= 3 {
				break
			}
			window := asMap(windowItem)
			foreground := asSlice(window["foreground_processes"])
			fg := "none"
			if len(foreground) > 0 {
				var details []string
				for j, proc := range foreground {
					if j >= 2 {
						break
					}
					details = append(details, processEvidenceLabel(asMap(proc)))
				}
				fg = strings.Join(details, ", ")
			}
			parts := []string{
				"kitty window " + inlineCode(window["id"], 20),
				"title " + inlineCode(firstNonEmpty(stringValue(window, "title"), "untitled"), 90),
			}
			if window["cwd"] != nil {
				parts = append(parts, "cwd "+inlineCode(window["cwd"], 90))
			}
			if window["last_reported_cmdline"] != nil {
				parts = append(parts, "last cmd "+inlineCode(window["last_reported_cmdline"], 90))
			}
			parts = append(parts, "foreground "+fg)
			lines = append(lines, strings.Join(parts, " "))
		}
	}
	for _, item := range asSlice(context["browsers"]) {
		browser := asMap(item)
		name := firstNonEmpty(stringValue(browser, "browser"), "browser")
		unit := firstNonEmpty(stringValue(browser, "unit"), "unknown")
		processes := asSlice(browser["processes"])
		if len(processes) > 0 {
			var details []string
			for i, proc := range processes {
				if i >= 4 {
					break
				}
				details = append(details, processEvidenceLabel(asMap(proc)))
			}
			lines = append(lines, fmt.Sprintf("%s unit %s process evidence: %s", name, inlineCode(unit, 90), strings.Join(details, ", ")))
		}
		tabs := asSlice(browser["tabs"])
		status := firstNonEmpty(stringValue(browser, "status"), "unknown")
		port := firstNonEmpty(stringValue(browser, "debug_port"), "unknown")
		if taskStatus := stringValue(browser, "task_sampler_status"); taskStatus != "" && taskStatus != "ok" && taskStatus != "not-found" {
			extra := ""
			if browser["task_sampler_error"] != nil {
				extra = " error " + inlineCode(browser["task_sampler_error"], 100)
			}
			age := ""
			if browser["task_sampler_age_s"] != nil && cpuValue(browser["task_sampler_age_s"]) != 0 {
				age = " age " + inlineCode(formatFloat(browser["task_sampler_age_s"])+"s", 20)
			}
			lines = append(lines, fmt.Sprintf("%s browser task sampler: %s%s%s", name, inlineCode(taskStatus, 60), age, extra))
		}
		if len(tabs) > 0 {
			source := "DevTools"
			for _, tab := range tabs {
				if asMap(tab)["browser_task_cpu_pct"] != nil && cpuValue(asMap(tab)["browser_task_cpu_pct"]) != 0 {
					source = "DevTools/task sampler"
					break
				}
			}
			var details []string
			for i, tab := range tabs {
				if i >= 5 {
					break
				}
				details = append(details, browserTabEvidenceLabel(asMap(tab)))
			}
			lines = append(lines, fmt.Sprintf("%s candidate tabs via %s %s: %s", name, source, inlineCode(port, 20), strings.Join(details, "; ")))
		} else {
			extra := ""
			if browser["error"] != nil {
				extra = " error " + inlineCode(browser["error"], 100)
			}
			lines = append(lines, fmt.Sprintf("%s tabs via DevTools %s: %s%s", name, inlineCode(port, 20), inlineCode(status, 60), extra))
		}
	}
	for _, item := range asSlice(context["docker"]) {
		docker := asMap(item)
		unit := firstNonEmpty(stringValue(docker, "unit"), "unknown")
		container := firstNonEmpty(stringValue(docker, "name"), stringValue(docker, "short_id"), "unknown")
		parts := []string{
			"docker unit " + inlineCode(unit, 110),
			"container " + inlineCode(container, 80),
		}
		for _, field := range []struct {
			key   string
			label string
			limit int
		}{
			{"short_id", "id", 20},
			{"image", "image", 100},
			{"container_status", "status", 40},
			{"health", "health", 40},
			{"compose_project", "compose project", 60},
			{"compose_service", "compose service", 60},
		} {
			if docker[field.key] != nil {
				parts = append(parts, field.label+" "+inlineCode(docker[field.key], field.limit))
			}
		}
		if inspect := stringValue(docker, "inspect_status"); inspect != "" && inspect != "ok" {
			parts = append(parts, "inspect "+inlineCode(inspect, 50))
		}
		if docker["error"] != nil {
			parts = append(parts, "error "+inlineCode(docker["error"], 100))
		}
		lines = append(lines, strings.Join(parts, " "))
		processes := asSlice(docker["processes"])
		if len(processes) > 0 {
			var details []string
			for i, proc := range processes {
				if i >= 4 {
					break
				}
				details = append(details, processEvidenceLabel(asMap(proc)))
			}
			lines = append(lines, fmt.Sprintf("docker unit %s process evidence: %s", inlineCode(unit, 110), strings.Join(details, ", ")))
		}
	}
	audio := asMap(context["audio"])
	processes := asSlice(audio["processes"])
	if len(processes) > 0 {
		var details []string
		for i, proc := range processes {
			if i >= 4 {
				break
			}
			details = append(details, processEvidenceLabel(asMap(proc)))
		}
		lines = append(lines, "audio process evidence: "+strings.Join(details, ", "))
	}
	nodes := asSlice(audio["nodes"])
	if len(nodes) > 0 {
		var details []string
		for i, node := range nodes {
			if i >= 6 {
				break
			}
			details = append(details, audioNodeEvidenceLabel(asMap(node)))
		}
		lines = append(lines, "pipewire node evidence: "+strings.Join(details, "; "))
	} else if status := stringValue(audio, "status"); status != "" && status != "ok" {
		extra := ""
		if audio["error"] != nil {
			extra = " error " + inlineCode(audio["error"], 120)
		}
		lines = append(lines, "pipewire node evidence: "+inlineCode(status, 60)+extra)
	}
	if len(lines) > 10 {
		return lines[:10]
	}
	return lines
}

func sourceSuspectLines(event spikeEvent) []string {
	var lines []string
	visibleSuspects := event.visibleSuspects()
	for i, suspect := range visibleSuspects {
		if i >= 2 {
			break
		}
		label := "suspect"
		if stringValue(suspect, "unit") != event.suspectLabel() || stringValue(suspect, "role") == "concurrent" {
			label = "concurrent"
		}
		details := []string{fmt.Sprintf("%s `%s` unit `%s`", label, firstNonEmpty(stringValue(suspect, "comm"), "unknown"), firstNonEmpty(stringValue(suspect, "unit"), "unknown"))}
		if suspect["cwd"] != nil {
			details = append(details, "cwd "+inlineCode(suspect["cwd"], 90))
		}
		if suspect["cmdline"] != nil {
			details = append(details, "cmd "+inlineCode(suspect["cmdline"], 140))
		}
		details = append(details, "reason `"+firstNonEmpty(stringValue(suspect, "reason"), "n/a")+"`")
		lines = append(lines, strings.Join(details, " "))
	}
	return lines
}

func topUnitDetails(raw rawMap) []string {
	var details []string
	for i, unitItem := range asSlice(raw["top_units"]) {
		if i >= 3 {
			break
		}
		unit := asMap(unitItem)
		details = append(details, fmt.Sprintf("%s %s", firstNonEmpty(stringValue(unit, "unit"), "unknown"), formatCPU(unit["cpu_pct"])))
	}
	return details
}

func writeRules() error {
	path := filepath.Join(spikesDir(), "system-spike-rules.md")
	if _, err := os.Stat(path); err == nil {
		return nil
	}
	return writeText(path, strings.Join([]string{
		"# System Spike Rules",
		"",
		"@tags #system-health #performance #ops",
		"",
		"This file documents how spike reports classify recurring workstation CPU bursts. It is policy, not raw evidence.",
		"",
		"## Critical",
		"",
		"- Repeated `Xorg`, compositor, input-helper, or audio spikes that visibly freeze the session.",
		"- High-confidence background suspects causing interactive-path victims.",
		"",
		"## Warning",
		"",
		"- Repeated background units, timers, indexers, sync jobs, or health checks that correlate with interactive spikes.",
		"- Medium-confidence Xorg spikes with recurring suspects.",
		"",
		"## Informational",
		"",
		"- Expected foreground builds, package installs, renders, exports, and benchmarks when they do not cause an interactive victim to spike.",
		"- Generic high-CPU processes outside latency-sensitive paths.",
		"- Self-contained generic spikes where the victim process belongs to the dominant burst unit.",
		"",
		"## Ignored Noise Candidates",
		"",
		"- `system-spike-watch.service`, `system-spike-notify.service`, `dotfiles-spikes.service`, `dotfiles-health.service`, and `browser-task-snapshotd.service` as primary suspects; report them as monitor overhead instead.",
		"- `sddm.service` as the host unit for `Xorg`; keep it as victim-unit context unless a separate client or helper process provides causal evidence.",
		"- One-off low-confidence spikes below the freeze threshold.",
		"- Known foreground commands that the user intentionally launched and that do not affect `Xorg`, input, compositor, or audio.",
		"",
	}, "\n"))
}

func writeRunbook() error {
	path := filepath.Join(spikesDir(), "system-spike-runbook.md")
	return writeText(path, strings.Join([]string{
		"# System Spike Runbook",
		"",
		"@tags #system-health #performance #ops",
		"",
		"Use these bounded commands when [[system-spikes]] points to recurring interactive CPU spikes.",
		"",
		"## Daily",
		"",
		"```sh",
		"dotfiles-spikes update",
		"```",
		"",
		"```sh",
		"system-spike-watch check",
		"```",
		"",
		"```sh",
		"systemd-cgtop --batch --iterations=1 --raw --cpu=percentage --depth=4",
		"```",
		"",
		"```sh",
		"systemctl --user list-timers --all",
		"```",
		"",
		"## Investigate A Suspect Unit",
		"",
		"```sh",
		"SYSTEMD_PAGER='less -R +G' journalctl --user -u UNIT --since today -n 200 --pager-end",
		"```",
		"",
	}, "\n"))
}

func writeCoverage() error {
	path := filepath.Join(spikesDir(), "system-spike-coverage.md")
	return writeText(path, strings.Join([]string{
		"# System Spike Coverage",
		"",
		"@tags #system-health #performance #ops",
		"",
		"This page documents what the generated spike report currently watches and where attribution is partial.",
		"",
		"Last updated: " + nowLocal(),
		"",
		"## Covered",
		"",
		"- Xorg victim spikes.",
		"- Picom and Plasma compositor/UI spikes.",
		"- PipeWire, WirePlumber, and pipewire-pulse spikes.",
		"- keyd, keyd-observer, mouseless, and ydotoold input-path spikes.",
		"- Node.js process spikes at lower-than-generic CPU levels.",
		"- Generic high-CPU processes as informational context.",
		"- Burst-only Kitty context for `kitty-*` scopes: top processes, cwd, remote-control socket, windows, and foreground processes when available.",
		"- Burst-only X11 active-window context when `DISPLAY` and `xdotool` are available: title, PID, unit, cwd, and command line.",
		"- Burst-only Brave and Chromium context for browser scopes: renderer process evidence plus DevTools tab candidates when a local debugging port is available, browser task CPU snapshots when the local extension and receiver have fresh data, and probable-tab ranking from task CPU, short CDP activity probes, and X11 active-window correlation.",
		"- Burst-only Docker context for `docker-*.scope` units: container name, image, status, Compose labels, and top processes when Docker inspect is available.",
		"- Burst-only PipeWire context for audio spikes: audio processes plus `pw-top` node load evidence enriched with `pw-dump` node metadata.",
		"",
		"## Partial",
		"",
		"- Root cause attribution is confidence-scored, not guaranteed causality.",
		"- Short-lived processes can be missed if they start and exit between burst samples.",
		"- X11 client attribution is inferred through timing, command, cgroup, and unit evidence.",
		"- Browser tab context prefers fresh `chrome.processes` task CPU snapshots when available, then falls back to recent CDP `Performance.getMetrics` deltas and X11 title correlation; shared renderer processes can still make per-tab causality approximate.",
		"- Docker container context depends on the user service being able to run `docker inspect` within the burst timeout.",
		"- PipeWire node context depends on `pw-top` and `pw-dump`; node load is graph/quantum evidence, not the same metric as Linux process CPU percentage.",
		"- Monitor overhead is reported separately and is excluded from primary suspect selection.",
		"- Deep stack traces are intentionally out of scope for the always-on monitor.",
		"",
	}, "\n"))
}

func writeSourcePages(events []spikeEvent) error {
	grouped := make(map[string][]spikeEvent)
	for _, event := range events {
		grouped[sourceStem(event)] = append(grouped[sourceStem(event)], event)
	}
	for _, stem := range sourceStems {
		group := grouped[stem]
		title := strings.Title(strings.ReplaceAll(strings.TrimPrefix(stem, "system-spike-"), "-", " ")) + " Spikes"
		path := filepath.Join(spikesDir(), "sources", stem+".md")
		lines := []string{
			"# " + title,
			"",
			"@tags #system-health #performance #ops",
			"",
			"This source page keeps bounded evidence for one class of recorded CPU spike events.",
			"",
			"Last updated: " + nowLocal(),
			"",
			"## Current Status",
			"",
			fmt.Sprintf("- Events: `%d`", len(group)),
			"",
			"## Recent Evidence",
			"",
		}
		if len(group) == 0 {
			lines = append(lines, "- No events recorded for this source.")
		}
		for _, event := range recentEvents(group, 10) {
			lines = append(lines, fmt.Sprintf("- `%s` victim `%s` unit `%s` suspect `%s` top unit `%s` trigger `%s` monitor `%s` confidence `%s` duration `%ss`", formatEventTime(event.startedAt()), event.victimComm(), firstNonEmpty(event.victimUnit(), "unknown"), event.suspectLabel(), event.topUnitLabel(), formatCPU(event.triggerCPUPct()), formatCPU(event.monitorOverheadCPU()), event.confidence(), prettyFloat(event.duration())))
			if len(event.topUnitDetailsValue) > 0 {
				lines = append(lines, "  - top units: "+strings.Join(event.topUnitDetailsValue, ", "))
			}
			if event.monitorOverheadCPU() >= 5 {
				lines = append(lines, fmt.Sprintf("  - monitor overhead: `%s` from dotfiles spike tooling", formatCPU(event.monitorOverheadCPU())))
			}
			for _, detail := range event.sourceSuspectLinesValue {
				lines = append(lines, "  - "+detail)
			}
			for _, detail := range event.contextEvidenceLinesValue {
				lines = append(lines, "  - "+detail)
			}
		}
		lines = append(lines, "", "## Quick Commands", "", "```sh", "dotfiles-spikes update", "```", "")
		if err := writeText(path, strings.Join(lines, "\n")); err != nil {
			return err
		}
	}
	return nil
}

func writeMonthlyDigest(events []spikeEvent) error {
	ym := time.Now().Format("2006-01")
	year := time.Now().Format("2006")
	path := filepath.Join(spikesDir(), "reports", year, "system-spikes-"+ym+".md")
	var monthEvents []spikeEvent
	for _, event := range events {
		if event.startedAt().Format("2006-01") == ym {
			monthEvents = append(monthEvents, event)
		}
	}
	patterns := aggregatePatterns(monthEvents)
	incidents := aggregateIncidents(monthEvents)
	lines := []string{
		"# System Spikes " + ym,
		"",
		"@tags #system-health #performance #ops",
		"",
		"This monthly digest keeps compact spike summaries so recurring performance patterns stay visible without storing raw process tables in Foam.",
		"",
		"Last generated: " + nowLocal(),
		"",
		fmt.Sprintf("- Events this month: `%d`", len(monthEvents)),
		fmt.Sprintf("- Unique patterns: `%d`", len(patterns)),
		fmt.Sprintf("- Unique incidents: `%d`", len(incidents)),
		"",
		"## Top Patterns",
		"",
	}
	if len(patterns) > 0 {
		for i, row := range patterns {
			if i >= 15 {
				break
			}
			lines = append(lines, fmt.Sprintf("- `%s` <- `%s`: `%d` events, victim unit `%s`, top unit `%s`, confidence `%s`, max trigger `%s`, max monitor `%s`, max `%ss`", row.Victim, row.Suspect, row.Count, row.VictimUnit, row.TopUnit, row.Confidence, formatCPU(row.MaxTriggerCPU), formatCPU(row.MaxMonitorOverhead), prettyFloat(row.MaxDuration)))
		}
	} else {
		lines = append(lines, "- No spike patterns recorded this month.")
	}
	return writeText(path, strings.Join(lines, "\n")+"\n")
}

func update() int {
	if err := ensureDirs(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	events, err := readEvents()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	for _, writer := range []func([]spikeEvent) error{writeMain, writeSourcePages, writeMonthlyDigest} {
		if err := writer(events); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
	}
	for _, writer := range []func() error{writeRules, writeRunbook, writeCoverage} {
		if err := writer(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
	}
	return 0
}

func report() int {
	fmt.Println(filepath.Join(spikesDir(), "system-spikes.md"))
	return 0
}

func check() int {
	events, err := readEvents()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Printf("events=%d\n", len(events))
	fmt.Printf("state_dir=%s\n", stateDir())
	fmt.Printf("spikes_dir=%s\n", spikesDir())
	return 0
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) != 1 {
		usage()
		return 2
	}
	switch args[0] {
	case "update":
		return update()
	case "report", "open":
		return report()
	case "check":
		return check()
	case "-h", "--help":
		usage()
		return 2
	default:
		usage()
		return 2
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: dotfiles-spikes update|report|open|check")
}

func writeText(path string, body string) error {
	return os.WriteFile(path, []byte(body), 0o644)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func valueOrDefault(value string, fallback string) string {
	if value != "" {
		return value
	}
	return fallback
}

func formatEventTime(ts time.Time) string {
	_, offset := ts.Zone()
	sign := "+"
	if offset < 0 {
		sign = "-"
		offset = -offset
	}
	hours := offset / 3600
	minutes := (offset % 3600) / 60
	return fmt.Sprintf("%s UTC%s%02d:%02d", ts.Format("2006-01-02 15:04:05"), sign, hours, minutes)
}

func counterSummary(counter *orderedCounter, limit int) string {
	var parts []string
	for _, item := range counter.MostCommon(limit) {
		parts = append(parts, fmt.Sprintf("%s x%d", item.Name, item.Count))
	}
	return strings.Join(parts, ", ")
}

func valuesEqual(left any, right any) bool {
	return fmt.Sprint(left) == fmt.Sprint(right)
}

func round(value float64, places int) float64 {
	factor := 1.0
	for i := 0; i < places; i++ {
		factor *= 10
	}
	if value >= 0 {
		return float64(int(value*factor+0.5)) / factor
	}
	return float64(int(value*factor-0.5)) / factor
}

func prettyFloat(value float64) string {
	text := strconv.FormatFloat(value, 'f', -1, 64)
	if text == "-0" {
		return "0"
	}
	if !strings.ContainsAny(text, ".eE") {
		return text + ".0"
	}
	return text
}
