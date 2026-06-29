package main

import (
	"bufio"
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

const defaultPollInterval = 2 * time.Second

type config struct {
	stateDir           string
	eventsDir          string
	notifyStateDir     string
	notifiedFile       string
	spikesCmd          string
	notificationAction string
	notesRoot          string
	sectionID          string
	pollInterval       time.Duration
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

type event struct {
	EventID        string       `json:"event_id"`
	StartedAt      string       `json:"started_at"`
	VictimKind     string       `json:"victim_kind"`
	TriggerCPUPct  json.Number  `json:"trigger_cpu_pct"`
	TriggerProcess processRef   `json:"trigger_process"`
	Victim         processRef   `json:"victim"`
	Suspects       []suspectRef `json:"suspects"`
}

func main() {
	prog := filepath.Base(os.Args[0])
	if prog == "." || prog == string(filepath.Separator) || prog == "" {
		prog = "system-spike-notify"
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
	stateDir := getenv("DOTFILES_SPIKES_STATE_DIR", filepath.Join(home, ".local/state/dotfiles/system-spikes"))
	eventsDir := filepath.Join(stateDir, "events")
	notifyStateDir := getenv("DOTFILES_SPIKE_NOTIFY_STATE_DIR", filepath.Join(stateDir, "notify"))
	return config{
		stateDir:           stateDir,
		eventsDir:          eventsDir,
		notifyStateDir:     notifyStateDir,
		notifiedFile:       filepath.Join(notifyStateDir, "xorg-notified-events"),
		spikesCmd:          getenv("DOTFILES_SPIKE_NOTIFY_DOTFILES_SPIKES", "dotfiles-spikes"),
		notificationAction: getenv("DOTFILES_SPIKE_NOTIFY_NOTIFICATION_ACTION", "notification-action"),
		notesRoot:          getenv("DOTFILES_SPIKE_NOTIFY_FOAM_CWD", filepath.Join(home, "data/notes/foam")),
		sectionID:          getenv("DOTFILES_SPIKE_NOTIFY_SECTION_ID", "system-spikes-report"),
		pollInterval:       parsePollInterval(getenv("DOTFILES_SPIKE_NOTIFY_POLL_INTERVAL", "2")),
	}
}

func getenv(name, fallback string) string {
	if value, ok := os.LookupEnv(name); ok && value != "" {
		return value
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
		waitForChange(cfg.eventsDir, cfg.pollInterval)
		if err := processOnce(cfg, "notify"); err != nil {
			return err
		}
	}
}

func processOnce(cfg config, mode string) error {
	if err := os.MkdirAll(cfg.eventsDir, 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(cfg.notifyStateDir, 0o755); err != nil {
		return err
	}
	if err := runUpdate(cfg.spikesCmd); err != nil {
		return err
	}

	events, err := readEvents(cfg.eventsDir)
	if err != nil {
		return err
	}
	notified, stateExisted, err := readNotified(cfg.notifiedFile)
	if err != nil {
		return err
	}

	allIDs := make(map[string]struct{}, len(events))
	for _, ev := range events {
		allIDs[eventID(ev)] = struct{}{}
	}

	if !stateExisted && mode != "notify-existing" {
		if err := writeNotified(cfg.notifiedFile, allIDs); err != nil {
			return err
		}
		fmt.Printf("initialized %d xorg events\n", len(allIDs))
		return nil
	}

	newEvents := make([]event, 0)
	for _, ev := range events {
		id := eventID(ev)
		if _, ok := notified[id]; ok {
			continue
		}
		newEvents = append(newEvents, ev)
	}

	for _, ev := range newEvents {
		if err := sendNotification(cfg, ev); err != nil {
			return err
		}
		notified[eventID(ev)] = struct{}{}
	}

	if len(newEvents) > 0 || !stateExisted {
		if err := writeNotified(cfg.notifiedFile, unionIDs(notified, allIDs)); err != nil {
			return err
		}
	}

	return nil
}

func printCheck(cfg config) error {
	if err := os.MkdirAll(cfg.eventsDir, 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(cfg.notifyStateDir, 0o755); err != nil {
		return err
	}
	fmt.Printf("state_dir=%s\n", cfg.stateDir)
	fmt.Printf("events_dir=%s\n", cfg.eventsDir)
	fmt.Printf("notify_state_dir=%s\n", cfg.notifyStateDir)
	fmt.Printf("spikes_cmd=%s\n", cfg.spikesCmd)
	fmt.Printf("notification_action=%s\n", cfg.notificationAction)
	return nil
}

func runUpdate(spikesCmd string) error {
	cmd := exec.Command(spikesCmd, "update")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func readEvents(eventsDir string) ([]event, error) {
	entries, err := os.ReadDir(eventsDir)
	if err != nil {
		return nil, nil
	}

	var events []event
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
			if line == "" {
				continue
			}
			var ev event
			if err := json.Unmarshal([]byte(line), &ev); err != nil {
				continue
			}
			if isXorgEvent(ev) {
				events = append(events, ev)
			}
		}
		_ = file.Close()
	}

	sort.SliceStable(events, func(i, j int) bool {
		if events[i].StartedAt == events[j].StartedAt {
			return eventID(events[i]) < eventID(events[j])
		}
		return events[i].StartedAt < events[j].StartedAt
	})
	return events, nil
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

func eventID(ev event) string {
	if ev.EventID != "" {
		return ev.EventID
	}
	return fmt.Sprintf("%s:%d:%s", ev.StartedAt, ev.Victim.PID, ev.Victim.Comm)
}

func isXorgEvent(ev event) bool {
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

func suspectLabel(ev event) string {
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

func sendNotification(cfg config, ev event) error {
	executable := cfg.notificationAction
	if !strings.Contains(executable, string(os.PathSeparator)) {
		resolved, err := exec.LookPath(executable)
		if err != nil {
			fmt.Fprintln(os.Stderr, "system-spike-notify: notification-action not found")
			return nil
		}
		executable = resolved
	}

	payload := map[string]string{
		"schema":          "dotfiles.notification-action.v1",
		"action":          "open-foam-block-section",
		"cwd":             cfg.notesRoot,
		"foam-section-id": cfg.sectionID,
	}
	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	body := strings.Join([]string{
		ev.StartedAtOrUnknown(),
		fmt.Sprintf("trigger %s, suspect %s", formatCPU(ev.TriggerCPUPct), suspectLabel(ev)),
		fmt.Sprintf("unit %s", ev.Victim.UnitOrUnknown()),
		"Report updated: [[system-spikes]]",
	}, "\n")

	cmd := exec.Command(
		executable,
		"send",
		"--summary",
		"Xorg CPU spike",
		"--body",
		body,
		"--label",
		"Open report",
		"--app-name",
		"system-spike-notify",
		"--category",
		"system.spike",
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
	fmt.Printf("notified %s rc=%d\n", eventID(ev), rc)
	return nil
}

func waitForChange(eventsDir string, interval time.Duration) {
	if _, err := exec.LookPath("inotifywait"); err == nil {
		cmd := exec.Command("inotifywait", "-q", "-e", "close_write,create,moved_to", eventsDir)
		cmd.Stdout = io.Discard
		cmd.Stderr = io.Discard
		if err := cmd.Run(); err == nil {
			return
		}
	}
	time.Sleep(interval)
}

func (ev event) StartedAtOrUnknown() string {
	if ev.StartedAt != "" {
		return ev.StartedAt
	}
	return "unknown time"
}

func (p processRef) UnitOrUnknown() string {
	if p.Unit != "" {
		return p.Unit
	}
	return "unknown unit"
}
