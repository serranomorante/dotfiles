package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"math"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	hz                  = 100
	genericThreshold    = 150.0
	genericConsecutive  = 2
	totalCPUThreshold   = 80.0
	totalCPUConsecutive = 5
)

var watchedThresholds = map[string]threshold{
	"Xorg":           {cpuPct: 60, consecutive: 1, kind: "xorg"},
	"picom":          {cpuPct: 50, consecutive: 1, kind: "compositor"},
	"plasmashell":    {cpuPct: 60, consecutive: 2, kind: "compositor"},
	"pipewire":       {cpuPct: 30, consecutive: 1, kind: "audio"},
	"pipewire-pulse": {cpuPct: 30, consecutive: 1, kind: "audio"},
	"wireplumber":    {cpuPct: 30, consecutive: 1, kind: "audio"},
	"node":           {cpuPct: 80, consecutive: 1, kind: "generic"},
	"keyd":           {cpuPct: 20, consecutive: 1, kind: "input"},
	"keyd-observer":  {cpuPct: 20, consecutive: 1, kind: "input"},
	"mouseless":      {cpuPct: 20, consecutive: 1, kind: "input"},
	"ydotoold":       {cpuPct: 20, consecutive: 1, kind: "input"},
}

var (
	unitPattern        = regexp.MustCompile(`([^/:]+?\.(?:service|scope|slice|timer))`)
	dockerScopePattern = regexp.MustCompile(`^docker-([a-f0-9]{12,64})\.scope$`)
	monitorUnits       = map[string]bool{
		"system-spike-watch.service":     true,
		"system-spike-notify.service":    true,
		"dotfiles-spikes.service":        true,
		"dotfiles-health.service":        true,
		"browser-task-snapshotd.service": true,
	}
	displayHostUnits = map[string]bool{"sddm.service": true, "display-manager.service": true}
	interactiveKinds = map[string]bool{"xorg": true, "compositor": true, "audio": true, "input": true}
)

type threshold struct {
	cpuPct      float64
	consecutive int
	kind        string
}

type procSample struct {
	pid   int
	ticks int64
	comm  string
}

type procMeta struct {
	pid     int
	comm    string
	cmdline string
	cwd     string
	ppid    int
	cgroup  string
	unit    string
}

type procDelta struct {
	pid    int
	comm   string
	cpuPct float64
	ticks  int64
}

type cpuTotal struct {
	total int64
	idle  int64
}

type processInfo struct {
	PID       int     `json:"pid"`
	Comm      string  `json:"comm"`
	Cmdline   string  `json:"cmdline"`
	Cwd       string  `json:"cwd,omitempty"`
	Unit      string  `json:"unit"`
	CPUPct    float64 `json:"cpu_pct"`
	FirstSeen float64 `json:"first_seen"`
	LastSeen  float64 `json:"last_seen"`
}

type suspectInfo struct {
	PID       int     `json:"pid"`
	Comm      string  `json:"comm"`
	Cmdline   string  `json:"cmdline"`
	Cwd       string  `json:"cwd,omitempty"`
	Unit      string  `json:"unit"`
	CPUPct    float64 `json:"cpu_pct"`
	FirstSeen float64 `json:"first_seen"`
	LastSeen  float64 `json:"last_seen"`
	Role      string  `json:"role,omitempty"`
	Reason    string  `json:"reason"`
}

type unitCPU struct {
	Unit   string  `json:"unit"`
	CPUPct float64 `json:"cpu_pct"`
}

type eventProcess struct {
	PID     int    `json:"pid"`
	Comm    string `json:"comm"`
	Cmdline string `json:"cmdline,omitempty"`
	Cwd     string `json:"cwd,omitempty"`
	Unit    string `json:"unit,omitempty"`
}

type contextProcess struct {
	PID              int     `json:"pid,omitempty"`
	Comm             string  `json:"comm,omitempty"`
	Cmdline          string  `json:"cmdline,omitempty"`
	Cwd              string  `json:"cwd,omitempty"`
	Unit             string  `json:"unit,omitempty"`
	CPUPct           float64 `json:"cpu_pct,omitempty"`
	Kind             string  `json:"kind,omitempty"`
	RendererClientID string  `json:"renderer_client_id,omitempty"`
}

type kittyWindowContext struct {
	ID                  int              `json:"id,omitempty"`
	Title               string           `json:"title,omitempty"`
	Cwd                 string           `json:"cwd,omitempty"`
	Cmdline             string           `json:"cmdline,omitempty"`
	LastReportedCmdline string           `json:"last_reported_cmdline,omitempty"`
	IsFocused           bool             `json:"is_focused,omitempty"`
	IsActive            bool             `json:"is_active,omitempty"`
	ForegroundProcesses []contextProcess `json:"foreground_processes,omitempty"`
}

type kittyContext struct {
	Unit          string               `json:"unit,omitempty"`
	PID           int                  `json:"pid,omitempty"`
	Socket        string               `json:"socket,omitempty"`
	Status        string               `json:"status,omitempty"`
	Error         string               `json:"error,omitempty"`
	UnitProcesses []contextProcess     `json:"unit_processes,omitempty"`
	Windows       []kittyWindowContext `json:"windows,omitempty"`
}

type browserTabContext struct {
	ID                    string  `json:"id,omitempty"`
	Type                  string  `json:"type,omitempty"`
	Title                 string  `json:"title,omitempty"`
	URL                   string  `json:"url,omitempty"`
	Active                bool    `json:"active,omitempty"`
	Probable              bool    `json:"probable,omitempty"`
	Match                 string  `json:"match,omitempty"`
	Score                 float64 `json:"score,omitempty"`
	ScoreReason           string  `json:"score_reason,omitempty"`
	VisibilityState       string  `json:"visibility_state,omitempty"`
	HasFocus              bool    `json:"has_focus,omitempty"`
	TaskDurationMS        float64 `json:"task_ms,omitempty"`
	ScriptDurationMS      float64 `json:"script_ms,omitempty"`
	LayoutDurationMS      float64 `json:"layout_ms,omitempty"`
	RecalcStyleDurationMS float64 `json:"recalc_style_ms,omitempty"`
	BrowserTaskCPUPct     float64 `json:"browser_task_cpu_pct,omitempty"`
	BrowserTaskProcessID  int     `json:"browser_task_process_id,omitempty"`
	BrowserTaskOSPID      int     `json:"browser_task_os_pid,omitempty"`
	BrowserTaskNetworkBPS float64 `json:"browser_task_network_bps,omitempty"`
	BrowserTaskAgeS       float64 `json:"browser_task_age_s,omitempty"`
	BrowserTaskSource     string  `json:"browser_task_source,omitempty"`
	BrowserTaskShared     bool    `json:"browser_task_shared,omitempty"`
	WebSocketDebuggerURL  string  `json:"-"`
}

type browserContext struct {
	Browser           string              `json:"browser"`
	Unit              string              `json:"unit,omitempty"`
	DebugPort         int                 `json:"debug_port,omitempty"`
	Status            string              `json:"status,omitempty"`
	Error             string              `json:"error,omitempty"`
	TaskSamplerStatus string              `json:"task_sampler_status,omitempty"`
	TaskSamplerAgeS   float64             `json:"task_sampler_age_s,omitempty"`
	TaskSamplerError  string              `json:"task_sampler_error,omitempty"`
	Processes         []contextProcess    `json:"processes,omitempty"`
	Tabs              []browserTabContext `json:"tabs,omitempty"`
}

type dockerContext struct {
	Unit            string           `json:"unit,omitempty"`
	ContainerID     string           `json:"container_id,omitempty"`
	ShortID         string           `json:"short_id,omitempty"`
	Name            string           `json:"name,omitempty"`
	Image           string           `json:"image,omitempty"`
	ContainerStatus string           `json:"container_status,omitempty"`
	Health          string           `json:"health,omitempty"`
	StartedAt       string           `json:"started_at,omitempty"`
	ComposeProject  string           `json:"compose_project,omitempty"`
	ComposeService  string           `json:"compose_service,omitempty"`
	InspectStatus   string           `json:"inspect_status,omitempty"`
	Error           string           `json:"error,omitempty"`
	Processes       []contextProcess `json:"processes,omitempty"`
}

type pipewireNodeContext struct {
	ID          int     `json:"id"`
	State       string  `json:"state,omitempty"`
	Name        string  `json:"name,omitempty"`
	Description string  `json:"description,omitempty"`
	MediaClass  string  `json:"media_class,omitempty"`
	AppName     string  `json:"app_name,omitempty"`
	ProcessID   int     `json:"process_id,omitempty"`
	ClientID    int     `json:"client_id,omitempty"`
	DeviceID    int     `json:"device_id,omitempty"`
	Quantum     string  `json:"quantum,omitempty"`
	Rate        string  `json:"rate,omitempty"`
	Wait        string  `json:"wait,omitempty"`
	Busy        string  `json:"busy,omitempty"`
	WaitQuantum string  `json:"wait_quantum,omitempty"`
	BusyQuantum string  `json:"busy_quantum,omitempty"`
	Errors      int     `json:"errors,omitempty"`
	Format      string  `json:"format,omitempty"`
	BusyScore   float64 `json:"busy_score,omitempty"`
}

type audioContext struct {
	Status    string                `json:"status,omitempty"`
	Error     string                `json:"error,omitempty"`
	Processes []contextProcess      `json:"processes,omitempty"`
	Nodes     []pipewireNodeContext `json:"nodes,omitempty"`
}

type activeWindowContext struct {
	ID      string `json:"id,omitempty"`
	Title   string `json:"title,omitempty"`
	PID     int    `json:"pid,omitempty"`
	Comm    string `json:"comm,omitempty"`
	Cmdline string `json:"cmdline,omitempty"`
	Cwd     string `json:"cwd,omitempty"`
	Unit    string `json:"unit,omitempty"`
	Status  string `json:"status,omitempty"`
	Error   string `json:"error,omitempty"`
}

type spikeContext struct {
	Window   *activeWindowContext `json:"window,omitempty"`
	Kitty    []kittyContext       `json:"kitty,omitempty"`
	Browsers []browserContext     `json:"browsers,omitempty"`
	Docker   []dockerContext      `json:"docker,omitempty"`
	Audio    *audioContext        `json:"audio,omitempty"`
}

type spikeEvent struct {
	SchemaVersion   int           `json:"schema_version"`
	EventID         string        `json:"event_id"`
	StartedAt       string        `json:"started_at"`
	EndedAt         string        `json:"ended_at"`
	DurationS       float64       `json:"duration_s"`
	TriggerProcess  eventProcess  `json:"trigger_process"`
	TriggerCPUPct   float64       `json:"trigger_cpu_pct"`
	Victim          eventProcess  `json:"victim"`
	VictimKind      string        `json:"victim_kind"`
	TopProcesses    []processInfo `json:"top_processes"`
	TopUnits        []unitCPU     `json:"top_units"`
	MonitorOverhead []processInfo `json:"monitor_overhead"`
	Suspects        []suspectInfo `json:"suspects"`
	Context         *spikeContext `json:"context,omitempty"`
	Confidence      string        `json:"confidence"`
	Classification  string        `json:"classification"`
	Notes           string        `json:"notes"`
}

type config struct {
	stateDir      string
	interval      time.Duration
	burstDuration time.Duration
	burstInterval time.Duration
	cooldown      time.Duration
	stdout        bool
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "system-spike-watch: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	command := "run"
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		command = args[0]
		args = args[1:]
	}

	switch command {
	case "run":
		cfg, err := parseRunConfig(args)
		if err != nil {
			return err
		}
		return runWatch(cfg)
	case "check":
		stateDir := defaultStateDir()
		fs := flag.NewFlagSet("check", flag.ContinueOnError)
		fs.StringVar(&stateDir, "state-dir", envString("DOTFILES_SPIKES_STATE_DIR", stateDir), "state directory")
		if err := fs.Parse(args); err != nil {
			return err
		}
		fmt.Printf("state_dir=%s\n", expandHome(stateDir))
		fmt.Printf("events_dir=%s\n", filepath.Join(expandHome(stateDir), "events"))
		fmt.Printf("hz=%d\n", hz)
		fmt.Printf("cpu_count=%d\n", runtime.NumCPU())
		return nil
	default:
		return fmt.Errorf("unknown command: %s", command)
	}
}

func parseRunConfig(args []string) (config, error) {
	cfg := config{
		stateDir:      envString("DOTFILES_SPIKES_STATE_DIR", defaultStateDir()),
		interval:      envDurationSeconds("SYSTEM_SPIKE_INTERVAL", time.Second),
		burstDuration: envDurationSeconds("SYSTEM_SPIKE_BURST_DURATION", 3*time.Second),
		burstInterval: envDurationSeconds("SYSTEM_SPIKE_BURST_INTERVAL", 200*time.Millisecond),
		cooldown:      envDurationSeconds("SYSTEM_SPIKE_COOLDOWN", 5*time.Second),
	}
	interval := formatSeconds(cfg.interval)
	burstDuration := formatSeconds(cfg.burstDuration)
	burstInterval := formatSeconds(cfg.burstInterval)
	cooldown := formatSeconds(cfg.cooldown)
	fs := flag.NewFlagSet("run", flag.ContinueOnError)
	fs.StringVar(&cfg.stateDir, "state-dir", cfg.stateDir, "state directory")
	fs.StringVar(&interval, "interval", interval, "normal sample interval in seconds")
	fs.StringVar(&burstDuration, "burst-duration", burstDuration, "burst capture duration in seconds")
	fs.StringVar(&burstInterval, "burst-interval", burstInterval, "burst sample interval in seconds")
	fs.StringVar(&cooldown, "cooldown", cooldown, "minimum interval between events in seconds")
	fs.BoolVar(&cfg.stdout, "stdout", false, "print events to stdout")
	if err := fs.Parse(args); err != nil {
		return cfg, err
	}
	var err error
	if cfg.interval, err = parseDurationFlexible(interval); err != nil {
		return cfg, fmt.Errorf("invalid --interval: %w", err)
	}
	if cfg.burstDuration, err = parseDurationFlexible(burstDuration); err != nil {
		return cfg, fmt.Errorf("invalid --burst-duration: %w", err)
	}
	if cfg.burstInterval, err = parseDurationFlexible(burstInterval); err != nil {
		return cfg, fmt.Errorf("invalid --burst-interval: %w", err)
	}
	if cfg.cooldown, err = parseDurationFlexible(cooldown); err != nil {
		return cfg, fmt.Errorf("invalid --cooldown: %w", err)
	}
	cfg.stateDir = expandHome(cfg.stateDir)
	return cfg, nil
}

func defaultStateDir() string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return ".local/state/dotfiles/system-spikes"
	}
	return filepath.Join(home, ".local/state/dotfiles/system-spikes")
}

func envString(name, fallback string) string {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	return value
}

func envDurationSeconds(name string, fallback time.Duration) time.Duration {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	duration, err := parseDurationFlexible(value)
	if err != nil || duration <= 0 {
		return fallback
	}
	return duration
}

func parseDurationFlexible(value string) (time.Duration, error) {
	if duration, err := time.ParseDuration(value); err == nil {
		return duration, nil
	}
	seconds, err := strconv.ParseFloat(value, 64)
	if err != nil || seconds <= 0 {
		return 0, fmt.Errorf("expected positive seconds or Go duration, got %q", value)
	}
	return time.Duration(seconds * float64(time.Second)), nil
}

func formatSeconds(duration time.Duration) string {
	return strconv.FormatFloat(duration.Seconds(), 'f', -1, 64)
}

func expandHome(path string) string {
	if path == "~" || strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err == nil && home != "" {
			return filepath.Join(home, strings.TrimPrefix(path, "~/"))
		}
	}
	return path
}

func runWatch(cfg config) error {
	if err := os.MkdirAll(cfg.stateDir, 0o755); err != nil {
		return err
	}

	consecutive := map[string]int{}
	var lastEvent time.Time
	beforeCPU, err := readCPUTotal()
	if err != nil {
		return err
	}
	before := readProcSnapshot()

	for {
		time.Sleep(cfg.interval)
		afterCPU, err := readCPUTotal()
		if err != nil {
			return err
		}
		after := readProcSnapshot()
		totalBusy := cpuBusyPct(beforeCPU, afterCPU)
		if totalBusy >= totalCPUThreshold {
			consecutive["total"]++
		} else {
			consecutive["total"] = 0
		}

		activeKeys := map[string]bool{}
		for _, delta := range procDeltas(before, after, cfg.interval.Seconds()) {
			kind, ok := triggerForDelta(delta, consecutive, activeKeys)
			if !ok {
				continue
			}
			if time.Since(lastEvent) < cfg.cooldown {
				continue
			}
			lastEvent = time.Now()
			event := burstCapture(delta, kind, cfg.burstDuration, cfg.burstInterval)
			if err := appendEvent(cfg.stateDir, event); err != nil {
				return err
			}
			if cfg.stdout {
				if err := json.NewEncoder(os.Stdout).Encode(event); err != nil {
					return err
				}
			}
			break
		}
		for key := range consecutive {
			if key != "total" && !activeKeys[key] {
				consecutive[key] = 0
			}
		}

		if consecutive["total"] >= totalCPUConsecutive && time.Since(lastEvent) >= cfg.cooldown {
			lastEvent = time.Now()
			event := burstCapture(procDelta{pid: 0, comm: "total-cpu", cpuPct: totalBusy}, "saturation", cfg.burstDuration, cfg.burstInterval)
			if err := appendEvent(cfg.stateDir, event); err != nil {
				return err
			}
			if cfg.stdout {
				if err := json.NewEncoder(os.Stdout).Encode(event); err != nil {
					return err
				}
			}
		}

		beforeCPU = afterCPU
		before = after
	}
}

func readText(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(data)
}

func parseStatLine(line string) (string, int, int64, bool) {
	left := strings.Index(line, "(")
	right := strings.LastIndex(line, ")")
	if left < 0 || right < left {
		return "", 0, 0, false
	}
	comm := line[left+1 : right]
	rest := strings.Fields(line[right+2:])
	if len(rest) < 13 {
		return "", 0, 0, false
	}
	ppid, err1 := strconv.Atoi(rest[1])
	utime, err2 := strconv.ParseInt(rest[11], 10, 64)
	stime, err3 := strconv.ParseInt(rest[12], 10, 64)
	if err1 != nil || err2 != nil || err3 != nil {
		return "", 0, 0, false
	}
	return comm, ppid, utime + stime, true
}

func readProcSample(pid int) (procSample, bool) {
	line := readText(filepath.Join("/proc", strconv.Itoa(pid), "stat"))
	if line == "" {
		return procSample{}, false
	}
	comm, _, ticks, ok := parseStatLine(line)
	if !ok {
		return procSample{}, false
	}
	return procSample{pid: pid, ticks: ticks, comm: comm}, true
}

func readProcMeta(pid int, commHint string) (procMeta, bool) {
	line := readText(filepath.Join("/proc", strconv.Itoa(pid), "stat"))
	if line == "" {
		return procMeta{}, false
	}
	comm, ppid, _, ok := parseStatLine(line)
	if !ok {
		return procMeta{}, false
	}
	if comm == "" {
		comm = commHint
	}
	cgroup := strings.TrimSpace(readText(filepath.Join("/proc", strconv.Itoa(pid), "cgroup")))
	return procMeta{
		pid:     pid,
		comm:    comm,
		cmdline: readCmdline(pid),
		cwd:     readProcCwd(pid),
		ppid:    ppid,
		cgroup:  cgroup,
		unit:    unitFromCgroup(cgroup),
	}, true
}

func readCmdlineParts(pid int) []string {
	data, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "cmdline"))
	if err != nil {
		return nil
	}
	rawParts := bytes.Split(data, []byte{0})
	parts := make([]string, 0, len(rawParts))
	for _, part := range rawParts {
		if len(part) == 0 {
			continue
		}
		parts = append(parts, string(part))
	}
	return parts
}

func readCmdline(pid int) string {
	return strings.Join(readCmdlineParts(pid), " ")
}

func readProcCwd(pid int) string {
	target, err := os.Readlink(filepath.Join("/proc", strconv.Itoa(pid), "cwd"))
	if err != nil {
		return ""
	}
	return target
}

func readEnvVar(pid int, name string) string {
	data, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "environ"))
	if err != nil {
		return ""
	}
	prefix := []byte(name + "=")
	for _, item := range bytes.Split(data, []byte{0}) {
		if bytes.HasPrefix(item, prefix) {
			return string(item[len(prefix):])
		}
	}
	return ""
}

func readProcSnapshot() map[int]procSample {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return map[int]procSample{}
	}
	snapshot := make(map[int]procSample, len(entries))
	for _, entry := range entries {
		if !isDigits(entry.Name()) {
			continue
		}
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		sample, ok := readProcSample(pid)
		if ok {
			snapshot[pid] = sample
		}
	}
	return snapshot
}

func isDigits(value string) bool {
	if value == "" {
		return false
	}
	for _, char := range value {
		if char < '0' || char > '9' {
			return false
		}
	}
	return true
}

func readCPUTotal() (cpuTotal, error) {
	file, err := os.Open("/proc/stat")
	if err != nil {
		return cpuTotal{}, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	if !scanner.Scan() {
		return cpuTotal{}, errors.New("unable to read /proc/stat")
	}
	fields := strings.Fields(scanner.Text())
	if len(fields) < 5 || fields[0] != "cpu" {
		return cpuTotal{}, errors.New("unexpected /proc/stat cpu line")
	}
	values := make([]int64, 0, len(fields)-1)
	for _, field := range fields[1:] {
		value, err := strconv.ParseInt(field, 10, 64)
		if err != nil {
			return cpuTotal{}, err
		}
		values = append(values, value)
	}
	var total int64
	for _, value := range values {
		total += value
	}
	idle := values[3]
	if len(values) > 4 {
		idle += values[4]
	}
	return cpuTotal{total: total, idle: idle}, nil
}

func cpuBusyPct(before, after cpuTotal) float64 {
	totalDelta := after.total - before.total
	idleDelta := after.idle - before.idle
	if totalDelta <= 0 {
		return 0
	}
	return clamp((float64(totalDelta-idleDelta) / float64(totalDelta)) * 100)
}

func procDeltas(before, after map[int]procSample, elapsed float64) []procDelta {
	if elapsed <= 0 {
		return nil
	}
	deltas := []procDelta{}
	for pid, current := range after {
		previous, ok := before[pid]
		if !ok {
			continue
		}
		ticks := current.ticks - previous.ticks
		if ticks <= 0 {
			continue
		}
		deltas = append(deltas, procDelta{
			pid:    pid,
			comm:   current.comm,
			cpuPct: float64(ticks) / float64(hz) / elapsed * 100,
			ticks:  ticks,
		})
	}
	sort.Slice(deltas, func(i, j int) bool { return deltas[i].cpuPct > deltas[j].cpuPct })
	return deltas
}

func unitFromCgroup(cgroup string) string {
	if cgroup == "" {
		return ""
	}
	text := strings.ReplaceAll(cgroup, `\x2d`, "-")
	matches := unitPattern.FindAllStringSubmatch(text, -1)
	if len(matches) == 0 {
		return ""
	}
	for i := len(matches) - 1; i >= 0; i-- {
		unit := matches[i][1]
		if unit != "app.slice" && unit != "system.slice" && unit != "user.slice" && unit != "session.slice" && unit != "background.slice" {
			return unit
		}
	}
	return matches[len(matches)-1][1]
}

func triggerForDelta(delta procDelta, consecutive map[string]int, activeKeys map[string]bool) (string, bool) {
	if threshold, ok := watchedThresholds[delta.comm]; ok {
		key := "comm:" + delta.comm
		if delta.cpuPct >= threshold.cpuPct {
			consecutive[key]++
			activeKeys[key] = true
		} else if !activeKeys[key] {
			consecutive[key] = 0
		}
		return threshold.kind, consecutive[key] >= threshold.consecutive
	}

	key := "generic:" + strconv.Itoa(delta.pid)
	if delta.cpuPct >= genericThreshold {
		consecutive[key]++
		activeKeys[key] = true
	} else {
		consecutive[key] = 0
	}
	return "generic", consecutive[key] >= genericConsecutive
}

func burstCapture(trigger procDelta, victimKind string, burstDuration, burstInterval time.Duration) spikeEvent {
	started := time.Now()
	metas := map[int]procMeta{}
	totals := map[int]procDelta{}
	firstSeen := map[int]time.Time{}
	lastSeen := map[int]time.Time{}
	before := readProcSnapshot()
	beforeTS := started
	for pid, sample := range before {
		firstSeen[pid] = started
		lastSeen[pid] = started
		if _, watched := watchedThresholds[sample.comm]; pid == trigger.pid || watched {
			if meta, ok := readProcMeta(pid, sample.comm); ok {
				metas[pid] = meta
			}
		}
	}

	for time.Since(started) < burstDuration {
		time.Sleep(burstInterval)
		now := time.Now()
		after := readProcSnapshot()
		for pid := range after {
			if _, ok := firstSeen[pid]; !ok {
				firstSeen[pid] = now
			}
			lastSeen[pid] = now
		}
		elapsed := math.Max(0.001, now.Sub(beforeTS).Seconds())
		for _, delta := range procDeltas(before, after, elapsed) {
			current := totals[delta.pid]
			if current.pid == 0 {
				totals[delta.pid] = delta
			} else {
				current.cpuPct += delta.cpuPct
				current.ticks += delta.ticks
				totals[delta.pid] = current
			}
			_, watched := watchedThresholds[delta.comm]
			if _, ok := metas[delta.pid]; !ok && (delta.cpuPct >= 5 || watched) {
				if meta, metaOK := readProcMeta(delta.pid, delta.comm); metaOK {
					metas[delta.pid] = meta
				}
			}
		}
		before = after
		beforeTS = now
	}

	ended := time.Now()
	duration := math.Max(0.001, ended.Sub(started).Seconds())
	topDeltas := make([]procDelta, 0, len(totals))
	for _, delta := range totals {
		topDeltas = append(topDeltas, delta)
	}
	sort.Slice(topDeltas, func(i, j int) bool { return topDeltas[i].ticks > topDeltas[j].ticks })
	if len(topDeltas) > 15 {
		topDeltas = topDeltas[:15]
	}

	topProcesses := make([]processInfo, 0, len(topDeltas))
	for _, delta := range topDeltas {
		meta, ok := metas[delta.pid]
		if !ok {
			meta, _ = readProcMeta(delta.pid, delta.comm)
			metas[delta.pid] = meta
		}
		topProcesses = append(topProcesses, processInfo{
			PID:       delta.pid,
			Comm:      delta.comm,
			Cmdline:   meta.cmdline,
			Cwd:       meta.cwd,
			Unit:      meta.unit,
			CPUPct:    round1(float64(delta.ticks) / float64(hz) / duration * 100),
			FirstSeen: round3(firstSeen[delta.pid].Sub(started).Seconds()),
			LastSeen:  round3(lastSeen[delta.pid].Sub(started).Seconds()),
		})
	}

	topUnits := topUnitsFromProcesses(topProcesses)
	victimProc := processForTrigger(topProcesses, trigger)
	victimUnit := victimProc.Unit
	dominant := dominantUnit(topUnits)
	suspects := suspectsForEvent(trigger, victimKind, duration, topProcesses, dominant, victimProc)
	context := collectSpikeContext(victimKind, topProcesses, topUnits)
	confidence := confidenceForSuspects(victimKind, suspects)
	primary := suspectInfo{}
	if len(suspects) > 0 {
		primary = suspects[0]
	}
	notes := fmt.Sprintf("%s spiked but no clear suspect was captured", trigger.comm)
	if primary.Unit != "" || primary.Comm != "" {
		label := primary.Unit
		if label == "" {
			label = primary.Comm
		}
		notes = fmt.Sprintf("%s spiked; likely related to %s", trigger.comm, label)
	}

	return spikeEvent{
		SchemaVersion: 1,
		EventID:       fmt.Sprintf("%s-%s-%d", started.Format("20060102T150405-0700"), trigger.comm, trigger.pid),
		StartedAt:     started.Local().Format(time.RFC3339Nano),
		EndedAt:       ended.Local().Format(time.RFC3339Nano),
		DurationS:     round3(ended.Sub(started).Seconds()),
		TriggerProcess: eventProcess{
			PID:  trigger.pid,
			Comm: trigger.comm,
			Unit: victimUnit,
		},
		TriggerCPUPct: round1(trigger.cpuPct),
		Victim: eventProcess{
			PID:     trigger.pid,
			Comm:    trigger.comm,
			Cmdline: victimProc.Cmdline,
			Cwd:     victimProc.Cwd,
			Unit:    victimUnit,
		},
		VictimKind:      victimKind,
		TopProcesses:    topProcesses,
		TopUnits:        topUnits,
		MonitorOverhead: monitorOverhead(topProcesses),
		Suspects:        suspects,
		Context:         context,
		Confidence:      confidence,
		Classification:  classifyEvent(victimKind, primary),
		Notes:           notes,
	}
}

func collectSpikeContext(victimKind string, topProcesses []processInfo, topUnits []unitCPU) *spikeContext {
	activeWindow := collectActiveWindowContext(victimKind, topProcesses, topUnits)
	context := spikeContext{
		Window:   activeWindow,
		Kitty:    collectKittyContext(topProcesses, topUnits),
		Browsers: collectBrowserContexts(topProcesses, topUnits, activeWindow),
		Docker:   collectDockerContexts(topProcesses, topUnits),
		Audio:    collectAudioContext(victimKind, topProcesses),
	}
	if context.Window == nil && len(context.Kitty) == 0 && len(context.Browsers) == 0 && len(context.Docker) == 0 && context.Audio == nil {
		return nil
	}
	return &context
}

func collectActiveWindowContext(victimKind string, topProcesses []processInfo, topUnits []unitCPU) *activeWindowContext {
	if os.Getenv("DISPLAY") == "" {
		return nil
	}
	if !interactiveKinds[victimKind] && !hasUnit(topUnits, isBrowserOrKittyUnit) && !hasProcessUnit(topProcesses, isBrowserOrKittyUnit) {
		return nil
	}
	ctx, errText := queryActiveWindow(250 * time.Millisecond)
	if errText != "" {
		return &activeWindowContext{Status: "x11-active-window-unavailable", Error: errText}
	}
	if ctx == nil {
		return nil
	}
	ctx.Status = "ok"
	if ctx.PID > 0 {
		if meta, ok := readProcMeta(ctx.PID, ""); ok {
			ctx.Comm = meta.comm
			ctx.Cmdline = trimContextText(meta.cmdline, 220)
			ctx.Cwd = meta.cwd
			ctx.Unit = meta.unit
		}
	}
	return ctx
}

func collectKittyContext(topProcesses []processInfo, topUnits []unitCPU) []kittyContext {
	units := orderedRelevantUnits(topProcesses, topUnits, isKittyUnit)
	contexts := []kittyContext{}
	for _, unit := range units {
		ctx := kittyContext{
			Unit:          unit,
			Status:        "unit-processes-only",
			UnitProcesses: contextProcessesForUnit(topProcesses, unit, 8),
		}
		kittyMetas := scanProcessesByUnit(unit, isKittyMeta, 3)
		if len(kittyMetas) == 0 {
			contexts = append(contexts, ctx)
			continue
		}
		meta := kittyMetas[0]
		ctx.PID = meta.pid
		ctx.Socket = kittyListenOn(meta)
		if ctx.Socket == "" {
			ctx.Status = "remote-control-unavailable"
			contexts = append(contexts, ctx)
			continue
		}
		windows, err := queryKittyWindows(ctx.Socket, 600*time.Millisecond)
		if err != "" {
			ctx.Status = "remote-control-error"
			ctx.Error = err
		} else {
			ctx.Status = "ok"
			ctx.Windows = windows
		}
		contexts = append(contexts, ctx)
		if len(contexts) >= 3 {
			break
		}
	}
	return contexts
}

func collectBrowserContexts(topProcesses []processInfo, topUnits []unitCPU, activeWindow *activeWindowContext) []browserContext {
	unitsByBrowser := map[string][]string{}
	for _, browser := range []string{"brave", "chromium"} {
		unitsByBrowser[browser] = orderedRelevantUnits(topProcesses, topUnits, func(unit string) bool {
			return browserFromUnit(unit) == browser
		})
	}
	contexts := []browserContext{}
	for _, browser := range []string{"brave", "chromium"} {
		for _, unit := range unitsByBrowser[browser] {
			processes := contextProcessesForUnit(topProcesses, unit, 8)
			port := browserDebugPort(browser, processes)
			taskSnapshot, taskStatus, taskError, taskAge := readBrowserTaskSnapshot(browser, 12*time.Second)
			ctx := browserContext{
				Browser:           browser,
				Unit:              unit,
				DebugPort:         port,
				Processes:         processes,
				TaskSamplerStatus: taskStatus,
				TaskSamplerAgeS:   taskAge,
				TaskSamplerError:  taskError,
			}
			if port <= 0 {
				ctx.Status = "devtools-port-unconfigured"
				if taskSnapshot != nil {
					ctx.Tabs = topBrowserTabs(sortBrowserTabsByEvidence(browserTabsFromTaskSnapshot(taskSnapshot)), 3)
					ctx.Status = "task-sampler-only"
				}
				contexts = append(contexts, ctx)
				continue
			}
			tabs, err := queryBrowserTabs(port, 700*time.Millisecond)
			if err != "" {
				ctx.Status = "devtools-unavailable"
				ctx.Error = err
				if taskSnapshot != nil {
					ctx.Tabs = topBrowserTabs(sortBrowserTabsByEvidence(browserTabsFromTaskSnapshot(taskSnapshot)), 3)
				}
			} else if len(tabs) == 0 {
				ctx.Status = "devtools-ok-no-tabs"
				if taskSnapshot != nil {
					ctx.Tabs = topBrowserTabs(sortBrowserTabsByEvidence(browserTabsFromTaskSnapshot(taskSnapshot)), 3)
				}
			} else {
				ctx.Status = "ok"
				tabs = markBrowserTabs(tabs, activeWindow, unit)
				tabs = mergeBrowserTaskSnapshot(tabs, taskSnapshot)
				ctx.Tabs = topBrowserTabs(scoreBrowserTabs(tabs, 850*time.Millisecond), 3)
			}
			contexts = append(contexts, ctx)
			if len(contexts) >= 4 {
				return contexts
			}
		}
	}
	return contexts
}

func collectDockerContexts(topProcesses []processInfo, topUnits []unitCPU) []dockerContext {
	units := orderedRelevantUnits(topProcesses, topUnits, isDockerUnit)
	contexts := []dockerContext{}
	for _, unit := range units {
		containerID := dockerContainerIDFromUnit(unit)
		if containerID == "" {
			continue
		}
		ctx := dockerContext{
			Unit:          unit,
			ContainerID:   containerID,
			ShortID:       shortContainerID(containerID),
			InspectStatus: "not-queried",
			Processes:     contextProcessesForUnit(topProcesses, unit, 8),
		}
		inspected, err := queryDockerContainer(containerID, 800*time.Millisecond)
		if err != "" {
			ctx.InspectStatus = "inspect-error"
			ctx.Error = err
		} else {
			inspected.Unit = ctx.Unit
			inspected.Processes = ctx.Processes
			ctx = inspected
			ctx.InspectStatus = "ok"
		}
		contexts = append(contexts, ctx)
		if len(contexts) >= 4 {
			break
		}
	}
	return contexts
}

func collectAudioContext(victimKind string, topProcesses []processInfo) *audioContext {
	if victimKind != "audio" && !hasAudioProcess(topProcesses) {
		return nil
	}
	ctx := audioContext{
		Status:    "not-queried",
		Processes: audioProcesses(topProcesses, 8),
	}
	props, propsErr := queryPipewireNodeProps(700 * time.Millisecond)
	nodes, topErr := queryPipewireTop(900*time.Millisecond, props)
	ctx.Nodes = nodes
	if topErr != "" && propsErr != "" {
		ctx.Status = "error"
		ctx.Error = "pw-top: " + topErr + "; pw-dump: " + propsErr
	} else if topErr != "" {
		ctx.Status = "pw-top-error"
		ctx.Error = topErr
	} else if propsErr != "" {
		ctx.Status = "pw-dump-error"
		ctx.Error = propsErr
	} else if len(nodes) == 0 {
		ctx.Status = "ok-no-nodes"
	} else {
		ctx.Status = "ok"
	}
	return &ctx
}

func hasAudioProcess(topProcesses []processInfo) bool {
	for _, proc := range topProcesses {
		if isAudioProcess(proc.Comm) || strings.Contains(proc.Unit, "pipewire") || strings.Contains(proc.Unit, "wireplumber") {
			return true
		}
	}
	return false
}

func audioProcesses(topProcesses []processInfo, limit int) []contextProcess {
	processes := []contextProcess{}
	for _, proc := range topProcesses {
		if !isAudioProcess(proc.Comm) && !strings.Contains(proc.Unit, "pipewire") && !strings.Contains(proc.Unit, "wireplumber") {
			continue
		}
		processes = append(processes, contextProcessFromProcessInfo(proc))
		if len(processes) >= limit {
			break
		}
	}
	return processes
}

func isAudioProcess(comm string) bool {
	switch comm {
	case "pipewire", "pipewire-pulse", "wireplumber":
		return true
	default:
		return false
	}
}

func orderedRelevantUnits(topProcesses []processInfo, topUnits []unitCPU, match func(string) bool) []string {
	seen := map[string]bool{}
	units := []string{}
	add := func(unit string) {
		if unit == "" || seen[unit] || !match(unit) {
			return
		}
		seen[unit] = true
		units = append(units, unit)
	}
	for _, unit := range topUnits {
		add(unit.Unit)
	}
	for _, proc := range topProcesses {
		add(proc.Unit)
	}
	return units
}

func contextProcessesForUnit(topProcesses []processInfo, unit string, limit int) []contextProcess {
	processes := []contextProcess{}
	for _, proc := range topProcesses {
		if proc.Unit != unit {
			continue
		}
		processes = append(processes, contextProcessFromProcessInfo(proc))
		if len(processes) >= limit {
			break
		}
	}
	return processes
}

func contextProcessFromProcessInfo(proc processInfo) contextProcess {
	return contextProcess{
		PID:              proc.PID,
		Comm:             proc.Comm,
		Cmdline:          trimContextText(proc.Cmdline, 240),
		Cwd:              proc.Cwd,
		Unit:             proc.Unit,
		CPUPct:           proc.CPUPct,
		Kind:             browserProcessKind(proc.Cmdline),
		RendererClientID: rendererClientID(proc.Cmdline),
	}
}

func contextProcessFromMeta(meta procMeta) contextProcess {
	return contextProcess{
		PID:              meta.pid,
		Comm:             meta.comm,
		Cmdline:          trimContextText(meta.cmdline, 240),
		Cwd:              meta.cwd,
		Unit:             meta.unit,
		Kind:             browserProcessKind(meta.cmdline),
		RendererClientID: rendererClientID(meta.cmdline),
	}
}

func isKittyUnit(unit string) bool {
	return strings.HasPrefix(unit, "kitty-")
}

func isBrowserOrKittyUnit(unit string) bool {
	return isKittyUnit(unit) || browserFromUnit(unit) != ""
}

func browserFromUnit(unit string) string {
	if strings.HasPrefix(unit, "browser-brave-") {
		return "brave"
	}
	if strings.HasPrefix(unit, "browser-chromium-") {
		return "chromium"
	}
	return ""
}

func isDockerUnit(unit string) bool {
	return dockerScopePattern.MatchString(unit)
}

func hasUnit(units []unitCPU, match func(string) bool) bool {
	for _, unit := range units {
		if match(unit.Unit) {
			return true
		}
	}
	return false
}

func hasProcessUnit(processes []processInfo, match func(string) bool) bool {
	for _, proc := range processes {
		if match(proc.Unit) {
			return true
		}
	}
	return false
}

func dockerContainerIDFromUnit(unit string) string {
	matches := dockerScopePattern.FindStringSubmatch(unit)
	if len(matches) < 2 {
		return ""
	}
	return matches[1]
}

func isKittyMeta(meta procMeta) bool {
	return meta.comm == "kitty" || strings.Contains(meta.cmdline, "/kitty ") || strings.Contains(meta.cmdline, "/kitty.app/bin/kitty")
}

func scanProcessesByUnit(unit string, match func(procMeta) bool, limit int) []procMeta {
	if unit == "" {
		return nil
	}
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil
	}
	matches := []procMeta{}
	for _, entry := range entries {
		if !isDigits(entry.Name()) {
			continue
		}
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		meta, ok := readProcMeta(pid, "")
		if !ok || meta.unit != unit || !match(meta) {
			continue
		}
		matches = append(matches, meta)
		if len(matches) >= limit {
			break
		}
	}
	sort.Slice(matches, func(i, j int) bool { return matches[i].pid < matches[j].pid })
	return matches
}

func queryActiveWindow(timeout time.Duration) (*activeWindowContext, string) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, activeWindowCommand(), "getactivewindow", "getwindowpid", "getwindowname")
	output, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return nil, "timeout"
	}
	if err != nil {
		message := trimContextText(strings.TrimSpace(string(output)), 160)
		if message == "" {
			message = err.Error()
		}
		return nil, message
	}
	id, pid, title, ok := parseXdotoolActiveWindow(string(output))
	if !ok {
		return nil, "invalid xdotool output"
	}
	return &activeWindowContext{
		ID:    id,
		PID:   pid,
		Title: trimContextText(title, 160),
	}, ""
}

func parseXdotoolActiveWindow(output string) (string, int, string, bool) {
	lines := []string{}
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			lines = append(lines, line)
		}
	}
	if len(lines) < 2 {
		return "", 0, "", false
	}
	pid, err := strconv.Atoi(lines[1])
	if err != nil {
		return "", 0, "", false
	}
	title := ""
	if len(lines) > 2 {
		title = strings.Join(lines[2:], " ")
	}
	return lines[0], pid, title, true
}

func activeWindowCommand() string {
	if value := os.Getenv("SYSTEM_SPIKE_XDOTOOL_COMMAND"); value != "" {
		return value
	}
	if _, err := os.Stat("/usr/bin/xdotool"); err == nil {
		return "/usr/bin/xdotool"
	}
	return "xdotool"
}

func kittyListenOn(meta procMeta) string {
	if value := normalizeKittyListenOn(readEnvVar(meta.pid, "KITTY_LISTEN_ON")); value != "" {
		return value
	}
	parts := readCmdlineParts(meta.pid)
	for index, part := range parts {
		if part == "--listen-on" && index+1 < len(parts) {
			return normalizeKittyListenOn(parts[index+1])
		}
		if strings.HasPrefix(part, "--listen-on=") {
			return normalizeKittyListenOn(strings.TrimPrefix(part, "--listen-on="))
		}
		if strings.HasPrefix(part, "--override=listen_on=") {
			return normalizeKittyListenOn(strings.TrimPrefix(part, "--override=listen_on="))
		}
	}
	return ""
}

func normalizeKittyListenOn(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	if strings.HasPrefix(value, "unix:") {
		return value
	}
	if strings.HasPrefix(value, "/") {
		return "unix:" + value
	}
	return value
}

type kittyLSOSWindow struct {
	ID        int          `json:"id"`
	IsActive  bool         `json:"is_active"`
	IsFocused bool         `json:"is_focused"`
	Tabs      []kittyLSTab `json:"tabs"`
}

type kittyLSTab struct {
	ID        int             `json:"id"`
	Title     string          `json:"title"`
	IsActive  bool            `json:"is_active"`
	IsFocused bool            `json:"is_focused"`
	Windows   []kittyLSWindow `json:"windows"`
}

type kittyLSWindow struct {
	ID                  int                 `json:"id"`
	Title               string              `json:"title"`
	Cwd                 string              `json:"cwd"`
	Cmdline             []string            `json:"cmdline"`
	LastReportedCmdline string              `json:"last_reported_cmdline"`
	IsActive            bool                `json:"is_active"`
	IsFocused           bool                `json:"is_focused"`
	ForegroundProcesses []kittyLSForeground `json:"foreground_processes"`
}

type kittyLSForeground struct {
	PID     int      `json:"pid"`
	Cwd     string   `json:"cwd"`
	Cmdline []string `json:"cmdline"`
}

func queryKittyWindows(socket string, timeout time.Duration) ([]kittyWindowContext, string) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, kittenCommand(), "@", "--to", socket, "ls")
	output, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return nil, "timeout"
	}
	if err != nil {
		message := trimContextText(strings.TrimSpace(string(output)), 160)
		if message == "" {
			message = err.Error()
		}
		return nil, message
	}
	var osWindows []kittyLSOSWindow
	if err := json.Unmarshal(output, &osWindows); err != nil {
		return nil, "invalid kitty ls json: " + err.Error()
	}
	windows := []kittyWindowContext{}
	for _, osWindow := range osWindows {
		for _, tab := range osWindow.Tabs {
			for _, window := range tab.Windows {
				item := kittyWindowContext{
					ID:                  window.ID,
					Title:               trimContextText(firstNonEmpty(window.Title, tab.Title), 120),
					Cwd:                 window.Cwd,
					Cmdline:             trimContextText(strings.Join(window.Cmdline, " "), 180),
					LastReportedCmdline: trimContextText(window.LastReportedCmdline, 120),
					IsFocused:           window.IsFocused || tab.IsFocused || osWindow.IsFocused,
					IsActive:            window.IsActive || tab.IsActive || osWindow.IsActive,
				}
				for _, proc := range window.ForegroundProcesses {
					item.ForegroundProcesses = append(item.ForegroundProcesses, contextProcess{
						PID:     proc.PID,
						Comm:    basename(firstArg(proc.Cmdline)),
						Cmdline: trimContextText(strings.Join(proc.Cmdline, " "), 180),
						Cwd:     proc.Cwd,
					})
					if len(item.ForegroundProcesses) >= 4 {
						break
					}
				}
				windows = append(windows, item)
			}
		}
	}
	sort.Slice(windows, func(i, j int) bool {
		if windows[i].IsFocused != windows[j].IsFocused {
			return windows[i].IsFocused
		}
		if windows[i].IsActive != windows[j].IsActive {
			return windows[i].IsActive
		}
		return windows[i].ID < windows[j].ID
	})
	if len(windows) > 8 {
		windows = windows[:8]
	}
	return windows, ""
}

func kittenCommand() string {
	home, err := os.UserHomeDir()
	if err == nil && home != "" {
		candidate := filepath.Join(home, ".local/kitty.app/bin/kitten")
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	if _, err := os.Stat("/usr/bin/kitten"); err == nil {
		return "/usr/bin/kitten"
	}
	return "kitten"
}

func browserDebugPort(browser string, processes []contextProcess) int {
	envName := "SYSTEM_SPIKE_" + strings.ToUpper(browser) + "_DEVTOOLS_PORT"
	if port := parsePositiveInt(os.Getenv(envName)); port > 0 {
		return port
	}
	for _, proc := range processes {
		if port := parseRemoteDebuggingPort(proc.Cmdline); port > 0 {
			return port
		}
	}
	switch browser {
	case "chromium":
		return 9222
	case "brave":
		return 9223
	default:
		return 0
	}
}

func parseRemoteDebuggingPort(cmdline string) int {
	fields := strings.Fields(cmdline)
	for index, field := range fields {
		if strings.HasPrefix(field, "--remote-debugging-port=") {
			return parsePositiveInt(strings.TrimPrefix(field, "--remote-debugging-port="))
		}
		if field == "--remote-debugging-port" && index+1 < len(fields) {
			return parsePositiveInt(fields[index+1])
		}
	}
	return 0
}

type browserTabRaw struct {
	ID                   string `json:"id"`
	Type                 string `json:"type"`
	Title                string `json:"title"`
	URL                  string `json:"url"`
	WebSocketDebuggerURL string `json:"webSocketDebuggerUrl"`
}

func queryBrowserTabs(port int, timeout time.Duration) ([]browserTabContext, string) {
	client := http.Client{Timeout: timeout}
	endpoint := fmt.Sprintf("http://127.0.0.1:%d/json/list", port)
	resp, err := client.Get(endpoint)
	if err != nil {
		return nil, trimContextText(err.Error(), 160)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, "http status " + strconv.Itoa(resp.StatusCode)
	}
	var rawTabs []browserTabRaw
	if err := json.NewDecoder(resp.Body).Decode(&rawTabs); err != nil {
		return nil, "invalid devtools json: " + err.Error()
	}
	tabs := []browserTabContext{}
	for _, raw := range rawTabs {
		if raw.Type != "page" {
			continue
		}
		tabs = append(tabs, browserTabContext{
			ID:                   raw.ID,
			Type:                 raw.Type,
			Title:                trimContextText(raw.Title, 140),
			URL:                  trimContextText(sanitizeBrowserURL(raw.URL), 220),
			WebSocketDebuggerURL: raw.WebSocketDebuggerURL,
		})
		if len(tabs) >= 12 {
			break
		}
	}
	return tabs, ""
}

type browserTaskSnapshot struct {
	Schema           string               `json:"schema"`
	Status           string               `json:"status,omitempty"`
	Reason           string               `json:"reason,omitempty"`
	Browser          string               `json:"browser,omitempty"`
	CapturedAt       string               `json:"captured_at,omitempty"`
	CapturedAtUnixMS int64                `json:"captured_at_unix_ms,omitempty"`
	ServerReceivedAt string               `json:"server_received_at,omitempty"`
	Processes        []browserTaskProcess `json:"processes,omitempty"`
	AgeS             float64              `json:"-"`
}

type browserTaskProcess struct {
	ID          int               `json:"id,omitempty"`
	OSProcessID int               `json:"os_process_id,omitempty"`
	Type        string            `json:"type,omitempty"`
	CPUPct      float64           `json:"cpu_pct,omitempty"`
	NetworkBPS  float64           `json:"network_bps,omitempty"`
	Tasks       []browserTaskTask `json:"tasks,omitempty"`
	Tabs        []browserTaskTab  `json:"tabs,omitempty"`
}

type browserTaskTask struct {
	TabID int    `json:"tab_id,omitempty"`
	Title string `json:"title,omitempty"`
}

type browserTaskTab struct {
	TabID     int    `json:"tab_id,omitempty"`
	Title     string `json:"title,omitempty"`
	URL       string `json:"url,omitempty"`
	Active    bool   `json:"active,omitempty"`
	Audible   bool   `json:"audible,omitempty"`
	Discarded bool   `json:"discarded,omitempty"`
	Pinned    bool   `json:"pinned,omitempty"`
	WindowID  int    `json:"window_id,omitempty"`
}

type browserTaskEvidence struct {
	Title      string
	URL        string
	Active     bool
	ProcessID  int
	OSPID      int
	CPUPct     float64
	NetworkBPS float64
	AgeS       float64
	Shared     bool
	Source     string
}

func readBrowserTaskSnapshot(browser string, maxAge time.Duration) (*browserTaskSnapshot, string, string, float64) {
	dir := browserTaskSnapshotDir()
	paths := []string{
		filepath.Join(dir, "latest-"+browser+".json"),
		filepath.Join(dir, "latest-unknown.json"),
	}
	var lastErr string
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			if !os.IsNotExist(err) {
				lastErr = trimContextText(err.Error(), 140)
			}
			continue
		}
		var snap browserTaskSnapshot
		if err := json.Unmarshal(data, &snap); err != nil {
			return nil, "invalid", trimContextText(err.Error(), 140), 0
		}
		if snap.Schema != "dotfiles.browser-task-sampler.v1" {
			return nil, "invalid-schema", trimContextText(snap.Schema, 80), 0
		}
		age := browserTaskSnapshotAge(snap)
		ageS := round1(age.Seconds())
		snap.AgeS = ageS
		if maxAge > 0 && age > maxAge {
			return nil, "stale", fmt.Sprintf("age %.1fs", age.Seconds()), ageS
		}
		status := strings.TrimSpace(snap.Status)
		if status == "" {
			status = "ok"
		}
		if status != "ok" {
			return nil, status, trimContextText(snap.Reason, 140), ageS
		}
		if len(snap.Processes) == 0 {
			return nil, "empty", "", ageS
		}
		return &snap, "ok", "", ageS
	}
	if lastErr != "" {
		return nil, "error", lastErr, 0
	}
	return nil, "not-found", "", 0
}

func browserTaskSnapshotDir() string {
	if value := os.Getenv("SYSTEM_SPIKE_BROWSER_TASK_SNAPSHOT_DIR"); value != "" {
		return value
	}
	if value := os.Getenv("BROWSER_TASK_SNAPSHOT_STATE_DIR"); value != "" {
		return value
	}
	if value := os.Getenv("XDG_STATE_HOME"); value != "" {
		return filepath.Join(value, "dotfiles", "browser-task-sampler")
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return filepath.Join(os.TempDir(), "dotfiles", "browser-task-sampler")
	}
	return filepath.Join(home, ".local", "state", "dotfiles", "browser-task-sampler")
}

func browserTaskSnapshotAge(snap browserTaskSnapshot) time.Duration {
	var captured time.Time
	if snap.CapturedAtUnixMS > 0 {
		captured = time.UnixMilli(snap.CapturedAtUnixMS)
	}
	if captured.IsZero() {
		for _, value := range []string{snap.CapturedAt, snap.ServerReceivedAt} {
			if value == "" {
				continue
			}
			if parsed, err := time.Parse(time.RFC3339Nano, value); err == nil {
				captured = parsed
				break
			}
		}
	}
	if captured.IsZero() {
		return 365 * 24 * time.Hour
	}
	age := time.Since(captured)
	if age < 0 {
		return 0
	}
	return age
}

func mergeBrowserTaskSnapshot(tabs []browserTabContext, snap *browserTaskSnapshot) []browserTabContext {
	if len(tabs) == 0 || snap == nil {
		return tabs
	}
	evidence := browserTaskEvidenceFromSnapshot(snap)
	if len(evidence) == 0 {
		return tabs
	}
	used := map[int]bool{}
	for index := range tabs {
		bestIndex := -1
		bestScore := 0
		for evidenceIndex, item := range evidence {
			if used[evidenceIndex] {
				continue
			}
			score := browserTaskMatchScore(tabs[index], item)
			if score > bestScore {
				bestScore = score
				bestIndex = evidenceIndex
			}
		}
		if bestIndex < 0 || bestScore < 40 {
			continue
		}
		tabs[index] = applyBrowserTaskEvidence(tabs[index], evidence[bestIndex])
		used[bestIndex] = true
	}
	return tabs
}

func browserTabsFromTaskSnapshot(snap *browserTaskSnapshot) []browserTabContext {
	if snap == nil {
		return nil
	}
	tabs := []browserTabContext{}
	seen := map[string]int{}
	for _, item := range browserTaskEvidenceFromSnapshot(snap) {
		key := normalizeTitle(item.Title) + "\x00" + item.URL
		if existing, ok := seen[key]; ok {
			if item.CPUPct > tabs[existing].BrowserTaskCPUPct {
				tabs[existing] = applyBrowserTaskEvidence(browserTabContext{
					Type:  "page",
					Title: trimContextText(item.Title, 140),
					URL:   trimContextText(item.URL, 220),
				}, item)
			}
			continue
		}
		tab := browserTabContext{
			Type:  "page",
			Title: trimContextText(item.Title, 140),
			URL:   trimContextText(item.URL, 220),
		}
		tabs = append(tabs, applyBrowserTaskEvidence(tab, item))
		seen[key] = len(tabs) - 1
	}
	return tabs
}

func browserTaskEvidenceFromSnapshot(snap *browserTaskSnapshot) []browserTaskEvidence {
	items := []browserTaskEvidence{}
	for _, proc := range snap.Processes {
		shared := len(proc.Tabs) > 1
		for _, tab := range proc.Tabs {
			title := tab.Title
			if title == "" {
				title = browserTaskTitleForTab(proc.Tasks, tab.TabID)
			}
			if title == "" && tab.URL == "" {
				continue
			}
			items = append(items, browserTaskEvidence{
				Title:      trimContextText(title, 140),
				URL:        trimContextText(sanitizeBrowserURL(tab.URL), 220),
				Active:     tab.Active,
				ProcessID:  proc.ID,
				OSPID:      proc.OSProcessID,
				CPUPct:     round1(proc.CPUPct),
				NetworkBPS: round1(proc.NetworkBPS),
				AgeS:       snap.AgeS,
				Shared:     shared,
				Source:     "chrome.processes",
			})
		}
	}
	sort.SliceStable(items, func(i, j int) bool {
		if items[i].CPUPct != items[j].CPUPct {
			return items[i].CPUPct > items[j].CPUPct
		}
		if items[i].Active != items[j].Active {
			return items[i].Active
		}
		return false
	})
	return items
}

func browserTaskTitleForTab(tasks []browserTaskTask, tabID int) string {
	for _, task := range tasks {
		if tabID == 0 || task.TabID == tabID {
			return task.Title
		}
	}
	return ""
}

func applyBrowserTaskEvidence(tab browserTabContext, item browserTaskEvidence) browserTabContext {
	if tab.Title == "" {
		tab.Title = trimContextText(item.Title, 140)
	}
	if tab.URL == "" {
		tab.URL = trimContextText(item.URL, 220)
	}
	if item.Active {
		tab.Active = true
		if tab.Match == "" {
			tab.Match = "browser-task-active-tab"
		}
	}
	tab.BrowserTaskCPUPct = round1(item.CPUPct)
	tab.BrowserTaskProcessID = item.ProcessID
	tab.BrowserTaskOSPID = item.OSPID
	tab.BrowserTaskNetworkBPS = round1(item.NetworkBPS)
	tab.BrowserTaskAgeS = round1(item.AgeS)
	tab.BrowserTaskSource = item.Source
	tab.BrowserTaskShared = item.Shared
	if tab.BrowserTaskCPUPct > 0 {
		tab.Probable = true
	}
	return tab
}

func browserTaskMatchScore(tab browserTabContext, item browserTaskEvidence) int {
	score := 0
	tabURL := sanitizeBrowserURL(tab.URL)
	if tabURL != "" && item.URL != "" && tabURL == item.URL {
		score += 60
	}
	tabTitle := normalizeTitle(tab.Title)
	itemTitle := normalizeTitle(item.Title)
	if tabTitle != "" && itemTitle != "" {
		switch {
		case tabTitle == itemTitle:
			score += 50
		case strings.Contains(tabTitle, itemTitle) || strings.Contains(itemTitle, tabTitle):
			score += 20
		}
	}
	if item.Active {
		score += 10
	}
	return score
}

func markBrowserTabs(tabs []browserTabContext, activeWindow *activeWindowContext, unit string) []browserTabContext {
	if len(tabs) == 0 || activeWindow == nil || activeWindow.Status != "ok" {
		return tabs
	}
	windowTitle := normalizeTitle(activeWindow.Title)
	unitMatches := activeWindow.Unit != "" && activeWindow.Unit == unit
	for index := range tabs {
		tabTitle := normalizeTitle(tabs[index].Title)
		if tabTitle != "" && windowTitle != "" && (strings.Contains(windowTitle, tabTitle) || strings.Contains(tabTitle, windowTitle)) {
			tabs[index].Active = true
			tabs[index].Match = "active-window-title"
			continue
		}
		if unitMatches && len(tabs) == 1 {
			tabs[index].Active = true
			tabs[index].Match = "active-window-unit"
		}
	}
	sort.SliceStable(tabs, func(i, j int) bool {
		if tabs[i].Active != tabs[j].Active {
			return tabs[i].Active
		}
		return false
	})
	return tabs
}

func scoreBrowserTabs(tabs []browserTabContext, timeout time.Duration) []browserTabContext {
	if len(tabs) == 0 || timeout <= 0 {
		return sortBrowserTabsByEvidence(tabs)
	}
	type result struct {
		index int
		tab   browserTabContext
	}
	results := make(chan result, len(tabs))
	for index, tab := range tabs {
		go func(index int, tab browserTabContext) {
			if tab.WebSocketDebuggerURL != "" {
				if scored, err := queryBrowserTabMetrics(tab, timeout); err == nil {
					tab = scored
				}
			}
			results <- result{index: index, tab: tab}
		}(index, tab)
	}
	for range tabs {
		item := <-results
		tabs[item.index] = item.tab
	}
	return sortBrowserTabsByEvidence(tabs)
}

func sortBrowserTabsByEvidence(tabs []browserTabContext) []browserTabContext {
	sort.SliceStable(tabs, func(i, j int) bool {
		if hasBrowserTaskCPU(tabs[i]) != hasBrowserTaskCPU(tabs[j]) {
			return hasBrowserTaskCPU(tabs[i])
		}
		if tabs[i].BrowserTaskCPUPct != tabs[j].BrowserTaskCPUPct {
			return tabs[i].BrowserTaskCPUPct > tabs[j].BrowserTaskCPUPct
		}
		if tabs[i].Probable != tabs[j].Probable {
			return tabs[i].Probable
		}
		if tabs[i].Score != tabs[j].Score {
			return tabs[i].Score > tabs[j].Score
		}
		if tabs[i].Active != tabs[j].Active {
			return tabs[i].Active
		}
		if tabs[i].HasFocus != tabs[j].HasFocus {
			return tabs[i].HasFocus
		}
		return false
	})
	for index := range tabs {
		tabs[index].WebSocketDebuggerURL = ""
	}
	return tabs
}

func hasBrowserTaskCPU(tab browserTabContext) bool {
	return tab.BrowserTaskCPUPct > 0 || tab.BrowserTaskSource != ""
}

func topBrowserTabs(tabs []browserTabContext, limit int) []browserTabContext {
	if limit <= 0 || len(tabs) <= limit {
		return tabs
	}
	return tabs[:limit]
}

func queryBrowserTabMetrics(tab browserTabContext, timeout time.Duration) (browserTabContext, error) {
	client, err := dialCDPWebSocket(tab.WebSocketDebuggerURL, timeout)
	if err != nil {
		return tab, err
	}
	defer client.close()
	_ = client.command("Performance.enable", nil, 120*time.Millisecond, nil)
	before, err := client.performanceMetrics(180 * time.Millisecond)
	if err != nil {
		return tab, err
	}
	visibility, hasFocus := client.pageState(160 * time.Millisecond)
	time.Sleep(220 * time.Millisecond)
	after, err := client.performanceMetrics(180 * time.Millisecond)
	if err != nil {
		return tab, err
	}
	tab.VisibilityState = visibility
	tab.HasFocus = hasFocus
	tab.TaskDurationMS = round1(metricDeltaMS(before, after, "TaskDuration"))
	tab.ScriptDurationMS = round1(metricDeltaMS(before, after, "ScriptDuration"))
	tab.LayoutDurationMS = round1(metricDeltaMS(before, after, "LayoutDuration"))
	tab.RecalcStyleDurationMS = round1(metricDeltaMS(before, after, "RecalcStyleDuration"))
	tab.Score = round1(browserTabScore(tab))
	if tab.Score > 0 {
		tab.Probable = true
		tab.ScoreReason = browserTabScoreReason(tab)
	}
	return tab, nil
}

func browserTabScore(tab browserTabContext) float64 {
	score := tab.TaskDurationMS + tab.ScriptDurationMS*0.8 + tab.LayoutDurationMS*0.6 + tab.RecalcStyleDurationMS*0.6
	if tab.Active {
		score += 20
	}
	if tab.HasFocus {
		score += 15
	}
	if tab.VisibilityState == "visible" {
		score += 5
	}
	return score
}

func browserTabScoreReason(tab browserTabContext) string {
	reasons := []string{}
	if tab.TaskDurationMS > 0 {
		reasons = append(reasons, fmt.Sprintf("task %.1fms", tab.TaskDurationMS))
	}
	if tab.ScriptDurationMS > 0 {
		reasons = append(reasons, fmt.Sprintf("script %.1fms", tab.ScriptDurationMS))
	}
	if tab.LayoutDurationMS > 0 {
		reasons = append(reasons, fmt.Sprintf("layout %.1fms", tab.LayoutDurationMS))
	}
	if tab.RecalcStyleDurationMS > 0 {
		reasons = append(reasons, fmt.Sprintf("style %.1fms", tab.RecalcStyleDurationMS))
	}
	if tab.HasFocus {
		reasons = append(reasons, "focused")
	}
	if tab.VisibilityState != "" {
		reasons = append(reasons, "visibility "+tab.VisibilityState)
	}
	if len(reasons) == 0 {
		return "no recent CDP activity captured"
	}
	return strings.Join(reasons, "; ")
}

func metricDeltaMS(before, after map[string]float64, name string) float64 {
	delta := after[name] - before[name]
	if delta < 0 {
		return 0
	}
	return delta * 1000
}

func normalizeTitle(value string) string {
	value = strings.ToLower(strings.Join(strings.Fields(value), " "))
	for _, suffix := range []string{
		" - brave",
		" - chromium",
		" - google chrome",
		" - google chrome unstable",
	} {
		value = strings.TrimSuffix(value, suffix)
	}
	return strings.TrimSpace(value)
}

type cdpWebSocket struct {
	conn   net.Conn
	reader *bufio.Reader
	nextID int
}

type cdpResponse struct {
	ID     int             `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

type cdpPerformanceResult struct {
	Metrics []struct {
		Name  string  `json:"name"`
		Value float64 `json:"value"`
	} `json:"metrics"`
}

type cdpEvaluateResult struct {
	Result struct {
		Value struct {
			VisibilityState string `json:"visibilityState"`
			HasFocus        bool   `json:"hasFocus"`
		} `json:"value"`
	} `json:"result"`
}

func dialCDPWebSocket(rawURL string, timeout time.Duration) (*cdpWebSocket, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	if parsed.Scheme != "ws" {
		return nil, fmt.Errorf("unsupported websocket scheme %s", parsed.Scheme)
	}
	conn, err := net.DialTimeout("tcp", parsed.Host, timeout)
	if err != nil {
		return nil, err
	}
	client := &cdpWebSocket{conn: conn, reader: bufio.NewReader(conn)}
	if err := client.handshake(parsed, timeout); err != nil {
		conn.Close()
		return nil, err
	}
	return client, nil
}

func (client *cdpWebSocket) handshake(parsed *url.URL, timeout time.Duration) error {
	keyBytes := make([]byte, 16)
	if _, err := rand.Read(keyBytes); err != nil {
		return err
	}
	key := base64.StdEncoding.EncodeToString(keyBytes)
	path := parsed.RequestURI()
	if path == "" {
		path = "/"
	}
	_ = client.conn.SetDeadline(time.Now().Add(timeout))
	request := fmt.Sprintf("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n", path, parsed.Host, key)
	if _, err := io.WriteString(client.conn, request); err != nil {
		return err
	}
	status, err := client.reader.ReadString('\n')
	if err != nil {
		return err
	}
	if !strings.Contains(status, " 101 ") {
		return fmt.Errorf("websocket handshake status %s", strings.TrimSpace(status))
	}
	for {
		line, err := client.reader.ReadString('\n')
		if err != nil {
			return err
		}
		if strings.TrimSpace(line) == "" {
			break
		}
	}
	return nil
}

func (client *cdpWebSocket) close() {
	if client.conn != nil {
		_ = client.conn.Close()
	}
}

func (client *cdpWebSocket) command(method string, params any, timeout time.Duration, result any) error {
	client.nextID++
	request := map[string]any{
		"id":     client.nextID,
		"method": method,
	}
	if params != nil {
		request["params"] = params
	}
	payload, err := json.Marshal(request)
	if err != nil {
		return err
	}
	_ = client.conn.SetDeadline(time.Now().Add(timeout))
	if err := client.writeTextFrame(payload); err != nil {
		return err
	}
	for {
		message, err := client.readTextFrame()
		if err != nil {
			return err
		}
		var response cdpResponse
		if err := json.Unmarshal(message, &response); err != nil || response.ID != client.nextID {
			continue
		}
		if response.Error != nil {
			return errors.New(response.Error.Message)
		}
		if result != nil {
			if err := json.Unmarshal(response.Result, result); err != nil {
				return err
			}
		}
		return nil
	}
}

func (client *cdpWebSocket) performanceMetrics(timeout time.Duration) (map[string]float64, error) {
	var result cdpPerformanceResult
	if err := client.command("Performance.getMetrics", nil, timeout, &result); err != nil {
		return nil, err
	}
	metrics := map[string]float64{}
	for _, metric := range result.Metrics {
		metrics[metric.Name] = metric.Value
	}
	return metrics, nil
}

func (client *cdpWebSocket) pageState(timeout time.Duration) (string, bool) {
	var result cdpEvaluateResult
	params := map[string]any{
		"expression":    "({visibilityState: document.visibilityState, hasFocus: document.hasFocus()})",
		"returnByValue": true,
	}
	if err := client.command("Runtime.evaluate", params, timeout, &result); err != nil {
		return "", false
	}
	return result.Result.Value.VisibilityState, result.Result.Value.HasFocus
}

func (client *cdpWebSocket) writeTextFrame(payload []byte) error {
	header := []byte{0x81}
	length := len(payload)
	switch {
	case length < 126:
		header = append(header, byte(0x80|length))
	case length <= 65535:
		header = append(header, 0x80|126, byte(length>>8), byte(length))
	default:
		header = append(header, 0x80|127)
		lengthBytes := make([]byte, 8)
		binary.BigEndian.PutUint64(lengthBytes, uint64(length))
		header = append(header, lengthBytes...)
	}
	mask := make([]byte, 4)
	if _, err := rand.Read(mask); err != nil {
		return err
	}
	header = append(header, mask...)
	masked := make([]byte, len(payload))
	for index, value := range payload {
		masked[index] = value ^ mask[index%4]
	}
	if _, err := client.conn.Write(header); err != nil {
		return err
	}
	_, err := client.conn.Write(masked)
	return err
}

func (client *cdpWebSocket) readTextFrame() ([]byte, error) {
	for {
		header := make([]byte, 2)
		if _, err := io.ReadFull(client.reader, header); err != nil {
			return nil, err
		}
		opcode := header[0] & 0x0f
		masked := header[1]&0x80 != 0
		length := uint64(header[1] & 0x7f)
		if length == 126 {
			extended := make([]byte, 2)
			if _, err := io.ReadFull(client.reader, extended); err != nil {
				return nil, err
			}
			length = uint64(binary.BigEndian.Uint16(extended))
		} else if length == 127 {
			extended := make([]byte, 8)
			if _, err := io.ReadFull(client.reader, extended); err != nil {
				return nil, err
			}
			length = binary.BigEndian.Uint64(extended)
		}
		var mask []byte
		if masked {
			mask = make([]byte, 4)
			if _, err := io.ReadFull(client.reader, mask); err != nil {
				return nil, err
			}
		}
		if length > 2*1024*1024 {
			return nil, fmt.Errorf("websocket frame too large: %d", length)
		}
		payload := make([]byte, int(length))
		if _, err := io.ReadFull(client.reader, payload); err != nil {
			return nil, err
		}
		if masked {
			for index := range payload {
				payload[index] ^= mask[index%4]
			}
		}
		switch opcode {
		case 0x1:
			return payload, nil
		case 0x8:
			return nil, errors.New("websocket closed")
		case 0x9:
			continue
		default:
			continue
		}
	}
}

type dockerInspectRaw struct {
	ID     string `json:"Id"`
	Name   string `json:"Name"`
	Config struct {
		Image  string            `json:"Image"`
		Labels map[string]string `json:"Labels"`
	} `json:"Config"`
	State struct {
		Status    string `json:"Status"`
		StartedAt string `json:"StartedAt"`
		Health    *struct {
			Status string `json:"Status"`
		} `json:"Health"`
	} `json:"State"`
}

func queryDockerContainer(containerID string, timeout time.Duration) (dockerContext, string) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, dockerCommand(), "inspect", containerID)
	output, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return dockerContext{}, "timeout"
	}
	if err != nil {
		message := trimContextText(strings.TrimSpace(string(output)), 180)
		if message == "" {
			message = err.Error()
		}
		return dockerContext{}, message
	}
	var inspected []dockerInspectRaw
	if err := json.Unmarshal(output, &inspected); err != nil {
		return dockerContext{}, "invalid docker inspect json: " + err.Error()
	}
	if len(inspected) == 0 {
		return dockerContext{}, "docker inspect returned no containers"
	}
	raw := inspected[0]
	id := raw.ID
	if id == "" {
		id = containerID
	}
	labels := raw.Config.Labels
	result := dockerContext{
		ContainerID:     id,
		ShortID:         shortContainerID(id),
		Name:            strings.TrimPrefix(raw.Name, "/"),
		Image:           raw.Config.Image,
		ContainerStatus: raw.State.Status,
		StartedAt:       raw.State.StartedAt,
		ComposeProject:  labels["com.docker.compose.project"],
		ComposeService:  labels["com.docker.compose.service"],
	}
	if raw.State.Health != nil {
		result.Health = raw.State.Health.Status
	}
	return result, ""
}

type pipewireDumpObject struct {
	ID   int    `json:"id"`
	Type string `json:"type"`
	Info struct {
		Props map[string]any `json:"props"`
	} `json:"info"`
	Props map[string]any `json:"props"`
}

type pipewireNodeProps struct {
	Name        string
	Description string
	MediaClass  string
	AppName     string
	ProcessID   int
	ClientID    int
	DeviceID    int
}

func queryPipewireNodeProps(timeout time.Duration) (map[int]pipewireNodeProps, string) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, pipewireDumpCommand(), "-N")
	output, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return nil, "timeout"
	}
	if err != nil {
		message := trimContextText(strings.TrimSpace(string(output)), 180)
		if message == "" {
			message = err.Error()
		}
		return nil, message
	}
	var objects []pipewireDumpObject
	if err := json.Unmarshal(output, &objects); err != nil {
		return nil, "invalid pw-dump json: " + err.Error()
	}
	propsByID := map[int]pipewireNodeProps{}
	for _, object := range objects {
		if !strings.Contains(object.Type, ":Node") {
			continue
		}
		props := object.Info.Props
		if props == nil {
			props = object.Props
		}
		propsByID[object.ID] = pipewireNodeProps{
			Name:        propString(props, "node.name"),
			Description: firstNonEmpty(propString(props, "node.description"), propString(props, "node.nick")),
			MediaClass:  propString(props, "media.class"),
			AppName:     firstNonEmpty(propString(props, "application.name"), propString(props, "application.process.binary")),
			ProcessID:   propInt(props, "application.process.id"),
			ClientID:    propInt(props, "client.id"),
			DeviceID:    propInt(props, "device.id"),
		}
	}
	return propsByID, ""
}

func queryPipewireTop(timeout time.Duration, props map[int]pipewireNodeProps) ([]pipewireNodeContext, string) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, pipewireTopCommand(), "-b", "-n", "1")
	output, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return nil, "timeout"
	}
	if err != nil {
		message := trimContextText(strings.TrimSpace(string(output)), 180)
		if message == "" {
			message = err.Error()
		}
		return nil, message
	}
	nodes := parsePipewireTop(string(output), props)
	if len(nodes) > 10 {
		nodes = nodes[:10]
	}
	return nodes, ""
}

func parsePipewireTop(output string, props map[int]pipewireNodeProps) []pipewireNodeContext {
	nodes := []pipewireNodeContext{}
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) >= 2 && fields[0] == "S" && fields[1] == "ID" {
			continue
		}
		if len(fields) < 9 || !isPipewireState(fields[0]) {
			continue
		}
		id, err := strconv.Atoi(fields[1])
		if err != nil {
			continue
		}
		format := ""
		name := ""
		if len(fields) >= 10 {
			name = fields[len(fields)-1]
			if len(fields) > 10 {
				format = strings.Join(fields[9:len(fields)-1], " ")
			}
		}
		errorsCount, _ := strconv.Atoi(fields[8])
		prop := props[id]
		if prop.Name == "" {
			prop.Name = name
		}
		if prop.Description == "" {
			prop.Description = name
		}
		node := pipewireNodeContext{
			ID:          id,
			State:       fields[0],
			Name:        firstNonEmpty(prop.Name, name),
			Description: prop.Description,
			MediaClass:  prop.MediaClass,
			AppName:     prop.AppName,
			ProcessID:   prop.ProcessID,
			ClientID:    prop.ClientID,
			DeviceID:    prop.DeviceID,
			Quantum:     fields[2],
			Rate:        fields[3],
			Wait:        fields[4],
			Busy:        fields[5],
			WaitQuantum: fields[6],
			BusyQuantum: fields[7],
			Errors:      errorsCount,
			Format:      format,
			BusyScore:   round1(pipewireBusyScore(fields[5], fields[7], errorsCount)),
		}
		if shouldKeepPipewireNode(node) {
			nodes = append(nodes, node)
		}
	}
	sort.Slice(nodes, func(i, j int) bool {
		if nodes[i].BusyScore != nodes[j].BusyScore {
			return nodes[i].BusyScore > nodes[j].BusyScore
		}
		if nodes[i].Errors != nodes[j].Errors {
			return nodes[i].Errors > nodes[j].Errors
		}
		return nodes[i].ID < nodes[j].ID
	})
	return nodes
}

func shouldKeepPipewireNode(node pipewireNodeContext) bool {
	if node.BusyScore > 0 || node.Errors > 0 {
		return true
	}
	if strings.HasPrefix(node.MediaClass, "Audio/") || strings.Contains(node.MediaClass, "/Audio") {
		return true
	}
	name := strings.ToLower(node.Name)
	return strings.Contains(name, "alsa_") || strings.Contains(name, "sink") || strings.Contains(name, "source") || strings.Contains(name, "rnnoise")
}

func isPipewireState(value string) bool {
	return value == "C" || value == "R" || value == "S" || value == "I"
}

func pipewireBusyScore(busy, busyQuantum string, errorsCount int) float64 {
	score := numericPrefix(busyQuantum)
	if score == 0 {
		score = numericPrefix(busy)
	}
	if score == 0 && errorsCount > 0 {
		score = float64(errorsCount)
	}
	return score
}

func numericPrefix(value string) float64 {
	value = strings.TrimSpace(value)
	if value == "" || value == "---" {
		return 0
	}
	end := 0
	for end < len(value) {
		char := value[end]
		if (char >= '0' && char <= '9') || char == '.' || char == '-' {
			end++
			continue
		}
		break
	}
	if end == 0 {
		return 0
	}
	parsed, err := strconv.ParseFloat(value[:end], 64)
	if err != nil {
		return 0
	}
	return parsed
}

func propString(props map[string]any, key string) string {
	value, ok := props[key]
	if !ok || value == nil {
		return ""
	}
	return fmt.Sprint(value)
}

func propInt(props map[string]any, key string) int {
	value, ok := props[key]
	if !ok || value == nil {
		return 0
	}
	switch typed := value.(type) {
	case float64:
		return int(typed)
	case int:
		return typed
	case string:
		return parsePositiveInt(typed)
	default:
		return 0
	}
}

func dockerCommand() string {
	if value := os.Getenv("SYSTEM_SPIKE_DOCKER_COMMAND"); value != "" {
		return value
	}
	if _, err := os.Stat("/usr/bin/docker"); err == nil {
		return "/usr/bin/docker"
	}
	return "docker"
}

func pipewireTopCommand() string {
	if value := os.Getenv("SYSTEM_SPIKE_PW_TOP_COMMAND"); value != "" {
		return value
	}
	if _, err := os.Stat("/usr/bin/pw-top"); err == nil {
		return "/usr/bin/pw-top"
	}
	return "pw-top"
}

func pipewireDumpCommand() string {
	if value := os.Getenv("SYSTEM_SPIKE_PW_DUMP_COMMAND"); value != "" {
		return value
	}
	if _, err := os.Stat("/usr/bin/pw-dump"); err == nil {
		return "/usr/bin/pw-dump"
	}
	return "pw-dump"
}

func shortContainerID(containerID string) string {
	if len(containerID) <= 12 {
		return containerID
	}
	return containerID[:12]
}

func sanitizeBrowserURL(value string) string {
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return value
	}
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed.String()
}

func browserProcessKind(cmdline string) string {
	fields := strings.Fields(cmdline)
	for index, field := range fields {
		if strings.HasPrefix(field, "--type=") {
			return strings.TrimPrefix(field, "--type=")
		}
		if field == "--type" && index+1 < len(fields) {
			return fields[index+1]
		}
	}
	return ""
}

func rendererClientID(cmdline string) string {
	fields := strings.Fields(cmdline)
	for index, field := range fields {
		if strings.HasPrefix(field, "--renderer-client-id=") {
			return strings.TrimPrefix(field, "--renderer-client-id=")
		}
		if field == "--renderer-client-id" && index+1 < len(fields) {
			return fields[index+1]
		}
	}
	return ""
}

func parsePositiveInt(value string) int {
	parsed, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || parsed <= 0 {
		return 0
	}
	return parsed
}

func firstArg(args []string) string {
	if len(args) == 0 {
		return ""
	}
	return args[0]
}

func basename(value string) string {
	if value == "" {
		return ""
	}
	return filepath.Base(value)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func trimContextText(value string, maxLen int) string {
	value = strings.Join(strings.Fields(value), " ")
	if maxLen <= 0 || len(value) <= maxLen {
		return value
	}
	if maxLen <= 3 {
		return value[:maxLen]
	}
	return value[:maxLen-3] + "..."
}

func topUnitsFromProcesses(processes []processInfo) []unitCPU {
	totals := map[string]float64{}
	for _, proc := range processes {
		unit := proc.Unit
		if unit == "" {
			unit = "unknown"
		}
		totals[unit] += proc.CPUPct
	}
	units := make([]unitCPU, 0, len(totals))
	for unit, cpu := range totals {
		units = append(units, unitCPU{Unit: unit, CPUPct: round1(cpu)})
	}
	sort.Slice(units, func(i, j int) bool { return units[i].CPUPct > units[j].CPUPct })
	if len(units) > 10 {
		units = units[:10]
	}
	return units
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

func dominantUnit(units []unitCPU) unitCPU {
	for _, unit := range units {
		if isActionableUnit(unit.Unit) {
			return unit
		}
	}
	return unitCPU{}
}

func processForTrigger(processes []processInfo, trigger procDelta) processInfo {
	for _, proc := range processes {
		if trigger.pid > 0 && proc.PID == trigger.pid {
			return proc
		}
	}
	for _, proc := range processes {
		if proc.Comm == trigger.comm {
			return proc
		}
	}
	return processInfo{}
}

func monitorOverhead(processes []processInfo) []processInfo {
	overhead := []processInfo{}
	for _, proc := range processes {
		if isMonitorUnit(proc.Unit) {
			overhead = append(overhead, proc)
			if len(overhead) >= 5 {
				break
			}
		}
	}
	return overhead
}

func suspectsForEvent(trigger procDelta, victimKind string, duration float64, topProcesses []processInfo, dominant unitCPU, victimProc processInfo) []suspectInfo {
	suspects := []suspectInfo{}
	if !interactiveKinds[victimKind] {
		primaryUnit := dominant
		relation := "dominant non-monitor unit during burst"
		if victimProc.Unit != "" && victimProc.Unit != "unknown" && !isMonitorUnit(victimProc.Unit) {
			if victimUnit := unitCPUFor(topProcesses, victimProc.Unit); victimUnit.CPUPct >= 20 {
				primaryUnit = victimUnit
				relation = "victim process belongs to this active burst unit"
				if dominant.Unit != "" && dominant.Unit != victimProc.Unit {
					relation = fmt.Sprintf("%s; dominant concurrent unit %s %.1f%% CPU", relation, dominant.Unit, dominant.CPUPct)
				}
			}
		}
		if primaryUnit.Unit != "" && primaryUnit.CPUPct >= 20 {
			if primaryUnit.Unit == dominant.Unit && primaryUnit.Unit == victimProc.Unit {
				relation = "victim process belongs to the dominant burst unit"
			}
			suspects = append(suspects, suspectInfo{
				PID:       trigger.pid,
				Comm:      trigger.comm,
				Cmdline:   victimProc.Cmdline,
				Cwd:       victimProc.Cwd,
				Unit:      primaryUnit.Unit,
				CPUPct:    round1(primaryUnit.CPUPct),
				FirstSeen: victimProc.FirstSeen,
				LastSeen:  nonzeroFloat(victimProc.LastSeen, round3(duration)),
				Role:      "victim-unit",
				Reason:    fmt.Sprintf("%s; unit total %.1f%% CPU", relation, primaryUnit.CPUPct),
			})
		}
	}
	for _, proc := range topProcesses {
		if proc.PID == trigger.pid || proc.Comm == trigger.comm {
			continue
		}
		if len(suspects) > 0 && proc.Unit == suspects[0].Unit {
			continue
		}
		if isMonitorUnit(proc.Unit) || (victimKind == "xorg" && isDisplayHostUnit(proc.Unit)) || proc.CPUPct < 5 {
			continue
		}
		reasons := []string{}
		if proc.Unit != "" {
			reasons = append(reasons, "concurrent burst cgroup/unit "+proc.Unit)
		}
		if proc.FirstSeen > 0 {
			reasons = append(reasons, "process appeared during burst")
		}
		if proc.Comm != "" {
			reasons = append(reasons, "command "+proc.Comm+" consumed CPU during victim spike")
		}
		reason := strings.Join(reasons, "; ")
		if reason == "" {
			reason = "CPU activity during victim spike"
		}
		suspects = append(suspects, suspectInfo{
			PID:       proc.PID,
			Comm:      proc.Comm,
			Cmdline:   proc.Cmdline,
			Cwd:       proc.Cwd,
			Unit:      proc.Unit,
			CPUPct:    proc.CPUPct,
			FirstSeen: proc.FirstSeen,
			LastSeen:  proc.LastSeen,
			Role:      "concurrent",
			Reason:    reason,
		})
		if len(suspects) >= 5 {
			break
		}
	}
	return suspects
}

func unitCPUFor(processes []processInfo, unit string) unitCPU {
	if unit == "" {
		return unitCPU{}
	}
	total := 0.0
	for _, proc := range processes {
		if proc.Unit == unit {
			total += proc.CPUPct
		}
	}
	if total <= 0 {
		return unitCPU{}
	}
	return unitCPU{Unit: unit, CPUPct: round1(total)}
}

func confidenceForSuspects(victimKind string, suspects []suspectInfo) string {
	if len(suspects) == 0 {
		return "low"
	}
	best := suspects[0]
	if victimKind == "xorg" && best.Unit != "" && best.Comm != "Xorg" && best.Comm != "picom" {
		return "high"
	}
	if best.Role == "dominant-unit" && (victimKind == "generic" || victimKind == "saturation") {
		if best.CPUPct >= 50 {
			return "medium"
		}
		return "low"
	}
	if best.Unit != "" || best.CPUPct >= 20 {
		return "medium"
	}
	return "low"
}

func classifyEvent(victimKind string, suspect suspectInfo) string {
	if victimKind == "xorg" || victimKind == "input" || victimKind == "audio" {
		return "interactive-path critical"
	}
	if suspect.Unit != "" && !strings.Contains(suspect.Unit, "app-") {
		return "background suspicious"
	}
	if victimKind == "generic" {
		return "informational"
	}
	return "warning"
}

func appendEvent(stateDir string, event spikeEvent) error {
	started, err := time.Parse(time.RFC3339Nano, event.StartedAt)
	if err != nil {
		started = time.Now()
	}
	path := filepath.Join(stateDir, "events", started.Local().Format("2006-01-02")+".jsonl")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer file.Close()
	encoder := json.NewEncoder(file)
	return encoder.Encode(event)
}

func clamp(value float64) float64 {
	if value < 0 {
		return 0
	}
	if value > 100 {
		return 100
	}
	return value
}

func round1(value float64) float64 {
	return math.Round(value*10) / 10
}

func round3(value float64) float64 {
	return math.Round(value*1000) / 1000
}

func nonzeroFloat(value, fallback float64) float64 {
	if value != 0 {
		return value
	}
	return fallback
}
