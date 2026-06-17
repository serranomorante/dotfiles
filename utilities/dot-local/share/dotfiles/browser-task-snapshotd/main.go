package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	defaultAddr = "127.0.0.1:17643"
	schema      = "dotfiles.browser-task-sampler.v1"
	maxBodySize = 1024 * 1024
)

type snapshot struct {
	Schema           string            `json:"schema"`
	Status           string            `json:"status,omitempty"`
	Reason           string            `json:"reason,omitempty"`
	Browser          string            `json:"browser,omitempty"`
	ExtensionID      string            `json:"extension_id,omitempty"`
	CapturedAt       string            `json:"captured_at,omitempty"`
	CapturedAtUnixMS int64             `json:"captured_at_unix_ms,omitempty"`
	UserAgent        string            `json:"user_agent,omitempty"`
	ServerReceivedAt string            `json:"server_received_at,omitempty"`
	Processes        []snapshotProcess `json:"processes,omitempty"`
}

type snapshotProcess struct {
	ID          int            `json:"id,omitempty"`
	OSProcessID int            `json:"os_process_id,omitempty"`
	Type        string         `json:"type,omitempty"`
	CPUPct      float64        `json:"cpu_pct,omitempty"`
	NetworkBPS  float64        `json:"network_bps,omitempty"`
	Profile     string         `json:"profile,omitempty"`
	Tasks       []snapshotTask `json:"tasks,omitempty"`
	Tabs        []snapshotTab  `json:"tabs,omitempty"`
}

type snapshotTask struct {
	TabID int    `json:"tab_id,omitempty"`
	Title string `json:"title,omitempty"`
}

type snapshotTab struct {
	TabID     int    `json:"tab_id,omitempty"`
	Title     string `json:"title,omitempty"`
	URL       string `json:"url,omitempty"`
	Active    bool   `json:"active,omitempty"`
	Audible   bool   `json:"audible,omitempty"`
	Discarded bool   `json:"discarded,omitempty"`
	Pinned    bool   `json:"pinned,omitempty"`
	WindowID  int    `json:"window_id,omitempty"`
}

type server struct {
	stateDir string
	now      func() time.Time
}

func main() {
	log.SetFlags(0)
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "run":
		run(os.Args[2:])
	case "check":
		check(os.Args[2:])
	case "-h", "--help":
		usage()
	default:
		usage()
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "usage: %s [run|check] [options...]\n", filepath.Base(os.Args[0]))
	os.Exit(2)
}

func run(args []string) {
	flags := flag.NewFlagSet("run", flag.ExitOnError)
	addr := flags.String("addr", envDefault("BROWSER_TASK_SNAPSHOT_ADDR", defaultAddr), "listen address")
	stateDir := flags.String("state-dir", defaultStateDir(), "snapshot state directory")
	_ = flags.Parse(args)

	srv := &server{stateDir: *stateDir, now: time.Now}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", srv.handleHealth)
	mux.HandleFunc("/v1/browser-task-snapshot", srv.handleSnapshot)
	mux.HandleFunc("/v1/browser-task-snapshot/latest", srv.handleLatest)

	log.Printf("browser-task-snapshotd listening on %s state_dir=%s", *addr, *stateDir)
	if err := http.ListenAndServe(*addr, mux); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

func check(args []string) {
	flags := flag.NewFlagSet("check", flag.ExitOnError)
	addr := flags.String("addr", envDefault("BROWSER_TASK_SNAPSHOT_ADDR", defaultAddr), "listen address")
	stateDir := flags.String("state-dir", defaultStateDir(), "snapshot state directory")
	_ = flags.Parse(args)
	fmt.Printf("addr=%s\n", *addr)
	fmt.Printf("state_dir=%s\n", *stateDir)
}

func (srv *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = io.WriteString(w, "ok\n")
}

func (srv *server) handleSnapshot(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	defer req.Body.Close()
	var snap snapshot
	decoder := json.NewDecoder(http.MaxBytesReader(w, req.Body, maxBodySize))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&snap); err != nil {
		http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
		return
	}
	if snap.Schema != schema {
		http.Error(w, "unsupported schema", http.StatusBadRequest)
		return
	}
	if snap.CapturedAt == "" {
		snap.CapturedAt = srv.now().UTC().Format(time.RFC3339Nano)
	}
	if snap.CapturedAtUnixMS == 0 {
		snap.CapturedAtUnixMS = srv.now().UnixMilli()
	}
	snap.ServerReceivedAt = srv.now().UTC().Format(time.RFC3339Nano)
	snap.Browser = normalizeBrowser(snap.Browser, snap.UserAgent)
	snap.Status = normalizeStatus(snap.Status)
	trimSnapshot(&snap)

	if err := writeSnapshot(srv.stateDir, snap); err != nil {
		http.Error(w, "write snapshot: "+err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = io.WriteString(w, `{"status":"ok"}`+"\n")
}

func (srv *server) handleLatest(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	browser := normalizeBrowser(req.URL.Query().Get("browser"), "")
	path := filepath.Join(srv.stateDir, "latest-"+browser+".json")
	body, err := os.ReadFile(path)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write(body)
}

func writeSnapshot(stateDir string, snap snapshot) error {
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return err
	}
	payload, err := json.Marshal(snap)
	if err != nil {
		return err
	}
	for _, name := range []string{"latest-" + snap.Browser + ".json", "latest.json"} {
		dest := filepath.Join(stateDir, name)
		tmp, err := os.CreateTemp(stateDir, "."+name+".tmp.")
		if err != nil {
			return err
		}
		tmpName := tmp.Name()
		_, writeErr := tmp.Write(append(payload, '\n'))
		closeErr := tmp.Close()
		if writeErr != nil {
			_ = os.Remove(tmpName)
			return writeErr
		}
		if closeErr != nil {
			_ = os.Remove(tmpName)
			return closeErr
		}
		if err := os.Chmod(tmpName, 0o644); err != nil {
			_ = os.Remove(tmpName)
			return err
		}
		if err := os.Rename(tmpName, dest); err != nil {
			_ = os.Remove(tmpName)
			return err
		}
	}
	return nil
}

func normalizeBrowser(value, userAgent string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	switch value {
	case "brave", "chromium":
		return value
	}
	if strings.Contains(strings.ToLower(userAgent), "brave") {
		return "brave"
	}
	if strings.Contains(strings.ToLower(userAgent), "chromium") || strings.Contains(strings.ToLower(userAgent), "chrome") {
		return "chromium"
	}
	return "unknown"
}

var statusPattern = regexp.MustCompile(`^[a-z0-9_.-]+$`)

func normalizeStatus(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	if value == "" {
		return "ok"
	}
	if !statusPattern.MatchString(value) {
		return "unknown"
	}
	return trim(value, 80)
}

func trimSnapshot(snap *snapshot) {
	snap.Reason = trim(snap.Reason, 200)
	snap.ExtensionID = trim(snap.ExtensionID, 120)
	snap.UserAgent = trim(snap.UserAgent, 240)
	if len(snap.Processes) > 48 {
		snap.Processes = snap.Processes[:48]
	}
	for index := range snap.Processes {
		proc := &snap.Processes[index]
		proc.Type = trim(proc.Type, 40)
		proc.Profile = trim(proc.Profile, 80)
		if len(proc.Tasks) > 16 {
			proc.Tasks = proc.Tasks[:16]
		}
		if len(proc.Tabs) > 16 {
			proc.Tabs = proc.Tabs[:16]
		}
		for taskIndex := range proc.Tasks {
			proc.Tasks[taskIndex].Title = trim(proc.Tasks[taskIndex].Title, 160)
		}
		for tabIndex := range proc.Tabs {
			tab := &proc.Tabs[tabIndex]
			tab.Title = trim(tab.Title, 160)
			tab.URL = trim(tab.URL, 240)
		}
	}
}

func trim(value string, limit int) string {
	value = strings.TrimSpace(strings.Join(strings.Fields(value), " "))
	if len(value) <= limit {
		return value
	}
	if limit <= 3 {
		return value[:limit]
	}
	return value[:limit-3] + "..."
}

func defaultStateDir() string {
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

func envDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
