package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const defaultPollInterval = 6 * time.Second

type config struct {
	stateDir           string
	notifyStateDir     string
	notifiedFile       string
	notificationAction string
	notesRoot          string
	pollInterval       time.Duration
	spikeEventsDir     string
	ansibleEventsDir   string
	xorgSectionID      string
	ansibleSectionID   string
}

type processRef struct {
	PID  int    `json:"pid"`
	Comm string `json:"comm"`
	Unit string `json:"unit"`
}

type suspectRef struct {
	Unit string `json:"unit"`
	Comm string `json:"comm"`
}

type spikeEvent struct {
	EventID        string       `json:"event_id"`
	StartedAt      string       `json:"started_at"`
	VictimKind     string       `json:"victim_kind"`
	TriggerCPUPct  json.Number  `json:"trigger_cpu_pct"`
	TriggerProcess processRef   `json:"trigger_process"`
	Victim         processRef   `json:"victim"`
	Suspects       []suspectRef `json:"suspects"`
}

type ansibleEvent struct {
	Timestamp string `json:"timestamp"`
	Severity  string `json:"severity"`
	EventType string `json:"event_type"`
	Ignored   bool   `json:"ignored"`
	Host      string `json:"host"`
	Task      string `json:"task"`
	Playbook  string `json:"playbook"`
	Cwd       string `json:"cwd"`
	RunID     string `json:"run_id"`
	Message   string `json:"message"`
}

type notificationEvent struct {
	ID        string
	StartedAt string
	Summary   string
	Body      string
	Label     string
	AppName   string
	Category  string
	Urgency   string
	SectionID string
}

func main() {
	prog := filepath.Base(os.Args[0])
	if prog == "." || prog == string(filepath.Separator) || prog == "" {
		prog = "dotfiles-health-notify"
	}

	switch firstArg() {
	case "run":
		if err := processLoop(loadConfig()); err != nil {
			fail(err)
		}
	case "once":
		if err := processOnce(loadConfig(), "notify"); err != nil {
			fail(err)
		}
	case "check":
		if err := printCheck(loadConfig()); err != nil {
			fail(err)
		}
	case "-h", "--help":
		usage(prog)
	default:
		usage(prog)
	}
}

func firstArg() string {
	if len(os.Args) < 2 {
		return ""
	}
	return os.Args[1]
}

func usage(prog string) {
	fmt.Fprintf(os.Stderr, "usage: %s run|once|check\n", prog)
	os.Exit(2)
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

func loadConfig() config {
	home := os.Getenv("HOME")
	stateDir := getenv("DOTFILES_HEALTH_NOTIFY_STATE_DIR", filepath.Join(home, ".local/state/dotfiles/health-notify"))
	notifyStateDir := filepath.Join(stateDir, "notify")
	spikeStateDir := getenv("DOTFILES_SPIKES_STATE_DIR", filepath.Join(home, ".local/state/dotfiles/system-spikes"))
	ansibleStateDir := getenv("DOTFILES_ANSIBLE_EVENTS_DIR", filepath.Join(home, ".local/state/dotfiles/ansible-events"))
	return config{
		stateDir:           stateDir,
		notifyStateDir:     notifyStateDir,
		notifiedFile:       filepath.Join(notifyStateDir, "notified-events"),
		notificationAction: getenvAny([]string{"DOTFILES_HEALTH_NOTIFY_NOTIFICATION_ACTION", "DOTFILES_SPIKE_NOTIFY_NOTIFICATION_ACTION"}, "notification-action"),
		notesRoot:          getenvAny([]string{"DOTFILES_HEALTH_NOTIFY_FOAM_CWD", "DOTFILES_SPIKE_NOTIFY_FOAM_CWD"}, filepath.Join(home, "data/notes/foam")),
		pollInterval:       parsePollInterval(getenvAny([]string{"DOTFILES_HEALTH_NOTIFY_POLL_INTERVAL", "DOTFILES_SPIKE_NOTIFY_POLL_INTERVAL"}, "6")),
		spikeEventsDir:     getenv("DOTFILES_HEALTH_NOTIFY_SPIKE_EVENTS_DIR", filepath.Join(spikeStateDir, "events")),
		ansibleEventsDir:   getenv("DOTFILES_HEALTH_NOTIFY_ANSIBLE_EVENTS_DIR", filepath.Join(ansibleStateDir, "events")),
		xorgSectionID:      getenvAny([]string{"DOTFILES_HEALTH_NOTIFY_XORG_SECTION_ID", "DOTFILES_SPIKE_NOTIFY_SECTION_ID"}, "system-spikes-report"),
		ansibleSectionID:   getenv("DOTFILES_HEALTH_NOTIFY_ANSIBLE_SECTION_ID", "system-health-ansible"),
	}
}

func getenv(name, fallback string) string {
	if value, ok := os.LookupEnv(name); ok && value != "" {
		return value
	}
	return fallback
}

func getenvAny(names []string, fallback string) string {
	for _, name := range names {
		if value, ok := os.LookupEnv(name); ok && value != "" {
			return value
		}
	}
	return fallback
}

func parsePollInterval(raw string) time.Duration {
	seconds, err := strconv.ParseFloat(raw, 64)
	if err != nil || seconds <= 0 {
		return defaultPollInterval
	}
	return time.Duration(seconds * float64(time.Second))
}

func processLoop(cfg config) error {
	if err := processOnce(cfg, "initialize"); err != nil {
		return err
	}
	for {
		waitForChange(cfg.watchDirs(), cfg.pollInterval)
		if err := processOnce(cfg, "notify"); err != nil {
			return err
		}
	}
}

func processOnce(cfg config, mode string) error {
	if err := cfg.ensureDirs(); err != nil {
		return err
	}

	events, err := readNotificationEvents(cfg)
	if err != nil {
		return err
	}
	notified, stateExisted, err := readNotified(cfg.notifiedFile)
	if err != nil {
		return err
	}

	allIDs := make(map[string]struct{}, len(events))
	for _, ev := range events {
		allIDs[ev.ID] = struct{}{}
	}

	if !stateExisted && mode != "notify-existing" {
		if err := writeNotified(cfg.notifiedFile, allIDs); err != nil {
			return err
		}
		fmt.Printf("initialized %d health notification events\n", len(allIDs))
		return nil
	}

	newEvents := make([]notificationEvent, 0)
	for _, ev := range events {
		if _, ok := notified[ev.ID]; ok {
			continue
		}
		newEvents = append(newEvents, ev)
	}

	for _, ev := range newEvents {
		if err := sendNotification(cfg, ev); err != nil {
			return err
		}
		notified[ev.ID] = struct{}{}
	}

	if len(newEvents) > 0 || !stateExisted {
		if err := writeNotified(cfg.notifiedFile, unionIDs(notified, allIDs)); err != nil {
			return err
		}
	}

	return nil
}

func (cfg config) ensureDirs() error {
	for _, dir := range []string{cfg.spikeEventsDir, cfg.ansibleEventsDir, cfg.notifyStateDir} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	return nil
}

func (cfg config) watchDirs() []string {
	return []string{cfg.spikeEventsDir, cfg.ansibleEventsDir}
}

func printCheck(cfg config) error {
	if err := cfg.ensureDirs(); err != nil {
		return err
	}
	fmt.Printf("state_dir=%s\n", cfg.stateDir)
	fmt.Printf("notify_state_dir=%s\n", cfg.notifyStateDir)
	fmt.Printf("spike_events_dir=%s\n", cfg.spikeEventsDir)
	fmt.Printf("ansible_events_dir=%s\n", cfg.ansibleEventsDir)
	fmt.Printf("notification_action=%s\n", cfg.notificationAction)
	return nil
}

func readNotificationEvents(cfg config) ([]notificationEvent, error) {
	var events []notificationEvent
	spikeEvents, err := readSpikeNotificationEvents(cfg)
	if err != nil {
		return nil, err
	}
	ansibleEvents, err := readAnsibleNotificationEvents(cfg)
	if err != nil {
		return nil, err
	}
	events = append(events, spikeEvents...)
	events = append(events, ansibleEvents...)
	sort.SliceStable(events, func(i, j int) bool {
		if events[i].StartedAt == events[j].StartedAt {
			return events[i].ID < events[j].ID
		}
		return events[i].StartedAt < events[j].StartedAt
	})
	return events, nil
}

func readSpikeNotificationEvents(cfg config) ([]notificationEvent, error) {
	lines, err := readJSONLLines(cfg.spikeEventsDir)
	if err != nil {
		return nil, err
	}
	events := make([]notificationEvent, 0)
	for _, line := range lines {
		var ev spikeEvent
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			continue
		}
		if !isXorgEvent(ev) {
			continue
		}
		events = append(events, notificationEvent{
			ID:        "spike:xorg:" + spikeEventID(ev),
			StartedAt: ev.StartedAt,
			Summary:   "Xorg CPU spike",
			Body: strings.Join([]string{
				unknownIfEmpty(ev.StartedAt, "unknown time"),
				fmt.Sprintf("trigger %s, suspect %s", formatCPU(ev.TriggerCPUPct), suspectLabel(ev)),
				fmt.Sprintf("unit %s", ev.Victim.UnitOrUnknown()),
				"Report updated: [[system-spikes]]",
			}, "\n"),
			Label:     "Open report",
			AppName:   "dotfiles-health-notify",
			Category:  "system.spike",
			Urgency:   "normal",
			SectionID: cfg.xorgSectionID,
		})
	}
	return events, nil
}

func readAnsibleNotificationEvents(cfg config) ([]notificationEvent, error) {
	lines, err := readJSONLLines(cfg.ansibleEventsDir)
	if err != nil {
		return nil, err
	}
	events := make([]notificationEvent, 0)
	for _, line := range lines {
		var ev ansibleEvent
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			continue
		}
		if !isNotifiableAnsibleEvent(ev) {
			continue
		}
		severity := strings.ToLower(ev.Severity)
		events = append(events, notificationEvent{
			ID:        "ansible:" + ansibleEventID(ev),
			StartedAt: ev.Timestamp,
			Summary:   "Ansible " + severity,
			Body:      ansibleBody(ev),
			Label:     "Open health",
			AppName:   "dotfiles-health-notify",
			Category:  "system.ansible",
			Urgency:   ansibleUrgency(severity),
			SectionID: cfg.ansibleSectionID,
		})
	}
	return events, nil
}

func readJSONLLines(eventsDir string) ([]string, error) {
	entries, err := os.ReadDir(eventsDir)
	if err != nil {
		return nil, nil
	}

	var lines []string
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
		scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line != "" {
				lines = append(lines, line)
			}
		}
		_ = file.Close()
	}
	return lines, nil
}

func isNotifiableAnsibleEvent(ev ansibleEvent) bool {
	if ev.Ignored {
		return false
	}
	switch strings.ToLower(ev.Severity) {
	case "warning", "error":
		return true
	default:
		return false
	}
}

func ansibleEventID(ev ansibleEvent) string {
	if ev.RunID != "" {
		return stableID(ev.RunID, ev.Timestamp, ev.Host, ev.Task, ev.EventType, ev.Message)
	}
	return stableID(ev.Timestamp, ev.Playbook, ev.Host, ev.Task, ev.EventType, ev.Message)
}

func stableID(parts ...string) string {
	hash := sha1.Sum([]byte(strings.Join(parts, "\x00")))
	return hex.EncodeToString(hash[:])
}

func ansibleBody(ev ansibleEvent) string {
	context := ev.Task
	if context == "" {
		context = filepath.Base(ev.Playbook)
	}
	if context == "" {
		context = "unknown task"
	}
	location := ev.Host
	if ev.Playbook != "" {
		location = strings.TrimSpace(location + " " + filepath.Base(ev.Playbook))
	}
	return strings.Join([]string{
		unknownIfEmpty(ev.Timestamp, "unknown time"),
		context,
		truncate(ev.Message, 600),
		unknownIfEmpty(location, "unknown host/playbook"),
	}, "\n")
}

func ansibleUrgency(severity string) string {
	if severity == "error" {
		return "critical"
	}
	return "normal"
}

func readNotified(path string) (map[string]struct{}, bool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return map[string]struct{}{}, false, nil
	}

	notified := make(map[string]struct{})
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		notified[line] = struct{}{}
	}
	return notified, true, nil
}

func writeNotified(path string, ids map[string]struct{}) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	names := make([]string, 0, len(ids))
	for id := range ids {
		if strings.TrimSpace(id) == "" {
			continue
		}
		names = append(names, id)
	}
	sort.Strings(names)
	tmp := path + ".tmp"
	content := ""
	if len(names) > 0 {
		content = strings.Join(names, "\n") + "\n"
	}
	if err := os.WriteFile(tmp, []byte(content), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func unionIDs(left, right map[string]struct{}) map[string]struct{} {
	out := make(map[string]struct{}, len(left)+len(right))
	for id := range left {
		out[id] = struct{}{}
	}
	for id := range right {
		out[id] = struct{}{}
	}
	return out
}

func spikeEventID(ev spikeEvent) string {
	if ev.EventID != "" {
		return ev.EventID
	}
	return fmt.Sprintf("%s:%d:%s", ev.StartedAt, ev.Victim.PID, ev.Victim.Comm)
}

func isXorgEvent(ev spikeEvent) bool {
	if ev.VictimKind == "xorg" {
		return true
	}
	if ev.Victim.Comm == "Xorg" {
		return true
	}
	return ev.TriggerProcess.Comm == "Xorg"
}

func formatCPU(value json.Number) string {
	if value == "" {
		return "unknown"
	}
	cpu, err := value.Float64()
	if err != nil {
		return "unknown"
	}
	return fmt.Sprintf("%.1f%%", cpu)
}

func suspectLabel(ev spikeEvent) string {
	if len(ev.Suspects) > 0 {
		first := ev.Suspects[0]
		if first.Unit != "" {
			return first.Unit
		}
		if first.Comm != "" {
			return first.Comm
		}
	}
	if ev.Victim.Unit != "" {
		return ev.Victim.Unit
	}
	if ev.Victim.Comm != "" {
		return ev.Victim.Comm
	}
	return "unknown"
}

func sendNotification(cfg config, ev notificationEvent) error {
	executable := cfg.notificationAction
	if !strings.Contains(executable, string(os.PathSeparator)) {
		resolved, err := exec.LookPath(executable)
		if err != nil {
			fmt.Fprintln(os.Stderr, "dotfiles-health-notify: notification-action not found")
			return nil
		}
		executable = resolved
	}

	payload := map[string]string{
		"schema":          "dotfiles.notification-action.v1",
		"action":          "open-foam-block-section",
		"cwd":             cfg.notesRoot,
		"foam-section-id": ev.SectionID,
	}
	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	cmd := exec.Command(
		executable,
		"send",
		"--summary",
		ev.Summary,
		"--body",
		ev.Body,
		"--label",
		ev.Label,
		"--app-name",
		ev.AppName,
		"--category",
		ev.Category,
		"--urgency",
		ev.Urgency,
		string(payloadJSON),
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err = cmd.Run()
	rc := 0
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			rc = exitErr.ExitCode()
		} else {
			return err
		}
	}
	fmt.Printf("notified %s rc=%d\n", ev.ID, rc)
	return nil
}

func waitForChange(eventsDirs []string, interval time.Duration) {
	if _, err := exec.LookPath("inotifywait"); err == nil {
		args := []string{"-q", "-e", "close_write,create,moved_to"}
		args = append(args, eventsDirs...)
		cmd := exec.Command("inotifywait", args...)
		cmd.Stdout = io.Discard
		cmd.Stderr = io.Discard
		if err := cmd.Run(); err == nil {
			return
		}
	}
	time.Sleep(interval)
}

func unknownIfEmpty(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func truncate(value string, limit int) string {
	value = strings.TrimSpace(value)
	if len(value) <= limit {
		return value
	}
	return value[:limit-3] + "..."
}

func (p processRef) UnitOrUnknown() string {
	if p.Unit != "" {
		return p.Unit
	}
	return "unknown unit"
}
