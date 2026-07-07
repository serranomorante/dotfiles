package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadEventsFiltersAndSorts(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "2026-06-04.jsonl"), []byte(`{"event_id":"b","started_at":"2026-06-04T19:42:01+02:00","victim_kind":"xorg","victim":{"pid":2,"comm":"Xorg"}}`+"\n"+"not-json\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "2026-06-03.jsonl"), []byte(`{"event_id":"a","started_at":"2026-06-03T19:42:00+02:00","victim_kind":"generic","victim":{"pid":1,"comm":"node"}}`), 0o644); err != nil {
		t.Fatal(err)
	}

	events, err := readEventsFromDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := len(events), 2; got != want {
		t.Fatalf("len(events) = %d, want %d", got, want)
	}
	if got, want := events[0].eventID(), "a"; got != want {
		t.Fatalf("first event = %q, want %q", got, want)
	}
	if got, want := events[1].eventID(), "b"; got != want {
		t.Fatalf("second event = %q, want %q", got, want)
	}
}

func TestPrimarySuspectIgnoresMonitorUnits(t *testing.T) {
	event := newSpikeEvent(rawMap{
		"victim_kind":     "xorg",
		"trigger_cpu_pct": float64(92),
		"victim":          rawMap{"comm": "Xorg", "unit": "sddm.service"},
		"suspects": []any{
			rawMap{"comm": "dotfiles-spikes", "unit": "dotfiles-spikes.service", "cpu_pct": float64(40)},
			rawMap{"comm": "node", "unit": "app.service", "cpu_pct": float64(30), "role": "foreground"},
		},
	}, 0)

	if got, want := event.suspectLabel(), "app.service"; got != want {
		t.Fatalf("suspectLabel = %q, want %q", got, want)
	}
}

func TestPreserveManualBlock(t *testing.T) {
	path := filepath.Join(t.TempDir(), "system-spikes.md")
	body := strings.Join([]string{
		"# System Spikes",
		manualStart,
		"",
		"- [ ] custom reminder",
		"",
		manualEnd,
		"after",
	}, "\n")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}

	got := preserveManualBlock(path)
	if !strings.Contains(got, "custom reminder") {
		t.Fatalf("manual block was not preserved: %q", got)
	}
	if strings.Contains(got, "after") {
		t.Fatalf("manual block included content after marker: %q", got)
	}
}

func TestBrowserTabSummaryUsesTaskCPU(t *testing.T) {
	tab := rawMap{
		"title":                   "Busy tab",
		"url":                     "https://example.test/page",
		"browser_task_cpu_pct":    float64(17.2),
		"browser_task_shared":     true,
		"browser_task_process_id": float64(42),
		"browser_task_source":     "extension",
		"browser_task_age_s":      float64(1.5),
		"browser_task_os_pid":     float64(1234),
		"visibility_state":        "visible",
	}

	summary := browserTabEvidenceLabel(tab)
	for _, want := range []string{"browser cpu `17.2%`", "shared-process", "os-pid `1234`", "visible"} {
		if !strings.Contains(summary, want) {
			t.Fatalf("summary %q missing %q", summary, want)
		}
	}
}
