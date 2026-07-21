package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSpikeEventIDFallsBackToVictimIdentity(t *testing.T) {
	ev := spikeEvent{
		StartedAt: "2026-06-04T19:42:00+02:00",
		Victim:    processRef{PID: 1320, Comm: "Xorg"},
	}

	if got, want := spikeEventID(ev), "2026-06-04T19:42:00+02:00:1320:Xorg"; got != want {
		t.Fatalf("spikeEventID = %q, want %q", got, want)
	}
}

func TestIsXorgEventRecognizesVictimAndTrigger(t *testing.T) {
	if !isXorgEvent(spikeEvent{VictimKind: "xorg"}) {
		t.Fatal("victim_kind xorg should match")
	}
	if !isXorgEvent(spikeEvent{Victim: processRef{Comm: "Xorg"}}) {
		t.Fatal("victim comm Xorg should match")
	}
	if !isXorgEvent(spikeEvent{TriggerProcess: processRef{Comm: "Xorg"}}) {
		t.Fatal("trigger comm Xorg should match")
	}
	if isXorgEvent(spikeEvent{}) {
		t.Fatal("empty event should not match")
	}
}

func TestReadNotificationEventsFiltersAndSorts(t *testing.T) {
	spikeDir := t.TempDir()
	ansibleDir := t.TempDir()
	write := func(name, contents string) {
		if err := os.WriteFile(filepath.Join(spikeDir, name), []byte(contents), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("2026-06-04.jsonl", `{"event_id":"b","started_at":"2026-06-04T19:42:01+02:00","victim_kind":"xorg","victim":{"pid":2,"comm":"Xorg"}}`+"\n"+
		`{"event_id":"skip","started_at":"2026-06-04T19:42:02+02:00","victim_kind":"generic","victim":{"pid":3,"comm":"node"}}`)
	write("2026-06-03.jsonl", `{"started_at":"2026-06-03T19:42:00+02:00","victim_kind":"xorg","victim":{"pid":1,"comm":"Xorg"}}`)

	events, err := readNotificationEvents(config{
		spikeEventsDir:   spikeDir,
		ansibleEventsDir: ansibleDir,
		xorgSectionID:    "system-spikes-report",
		ansibleSectionID: "system-health-ansible",
	})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := len(events), 2; got != want {
		t.Fatalf("len(events) = %d, want %d", got, want)
	}
	if got, want := events[0].ID, "spike:xorg:2026-06-03T19:42:00+02:00:1:Xorg"; got != want {
		t.Fatalf("first event = %q, want %q", got, want)
	}
	if got, want := events[1].ID, "spike:xorg:b"; got != want {
		t.Fatalf("second event = %q, want %q", got, want)
	}
}

func TestReadNotificationEventsSinceInitializesOffsetsWithoutParsing(t *testing.T) {
	spikeDir := t.TempDir()
	ansibleDir := t.TempDir()
	path := filepath.Join(spikeDir, "2026-07-21.jsonl")
	content := `{"event_id":"old","started_at":"2026-07-21T08:52:41+02:00","victim_kind":"xorg","victim":{"pid":1,"comm":"Xorg"}}` + "\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	events, offsets, err := readNotificationEventsSince(config{
		spikeEventsDir:   spikeDir,
		ansibleEventsDir: ansibleDir,
		recentDays:       3,
		xorgSectionID:    "system-spikes-report",
		ansibleSectionID: "system-health-ansible",
	}, fileOffsets{}, true, time.Date(2026, 7, 21, 9, 0, 0, 0, time.Local))
	if err != nil {
		t.Fatal(err)
	}
	if got, want := len(events), 0; got != want {
		t.Fatalf("len(events) = %d, want %d", got, want)
	}
	if got, want := offsets[path], int64(len(content)); got != want {
		t.Fatalf("offset = %d, want %d", got, want)
	}
}

func TestReadNotificationEventsSinceReadsOnlyAppendedBytes(t *testing.T) {
	spikeDir := t.TempDir()
	ansibleDir := t.TempDir()
	path := filepath.Join(spikeDir, "2026-07-21.jsonl")
	oldContent := `{"event_id":"old","started_at":"2026-07-21T08:52:41+02:00","victim_kind":"xorg","victim":{"pid":1,"comm":"Xorg"}}` + "\n"
	newContent := `{"event_id":"new","started_at":"2026-07-21T08:53:41+02:00","victim_kind":"xorg","victim":{"pid":2,"comm":"Xorg"}}` + "\n"
	if err := os.WriteFile(path, []byte(oldContent+newContent), 0o644); err != nil {
		t.Fatal(err)
	}

	events, offsets, err := readNotificationEventsSince(config{
		spikeEventsDir:   spikeDir,
		ansibleEventsDir: ansibleDir,
		recentDays:       3,
		xorgSectionID:    "system-spikes-report",
		ansibleSectionID: "system-health-ansible",
	}, fileOffsets{path: int64(len(oldContent))}, false, time.Date(2026, 7, 21, 9, 0, 0, 0, time.Local))
	if err != nil {
		t.Fatal(err)
	}
	if got, want := len(events), 1; got != want {
		t.Fatalf("len(events) = %d, want %d", got, want)
	}
	if got, want := events[0].ID, "spike:xorg:new"; got != want {
		t.Fatalf("event ID = %q, want %q", got, want)
	}
	if got, want := offsets[path], int64(len(oldContent+newContent)); got != want {
		t.Fatalf("offset = %d, want %d", got, want)
	}
}

func TestReadNotificationEventsSinceSkipsOldFiles(t *testing.T) {
	spikeDir := t.TempDir()
	ansibleDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(spikeDir, "2026-07-01.jsonl"), []byte(`{"event_id":"old","started_at":"2026-07-01T08:52:41+02:00","victim_kind":"xorg","victim":{"pid":1,"comm":"Xorg"}}`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	events, offsets, err := readNotificationEventsSince(config{
		spikeEventsDir:   spikeDir,
		ansibleEventsDir: ansibleDir,
		recentDays:       3,
		xorgSectionID:    "system-spikes-report",
		ansibleSectionID: "system-health-ansible",
	}, fileOffsets{}, false, time.Date(2026, 7, 21, 9, 0, 0, 0, time.Local))
	if err != nil {
		t.Fatal(err)
	}
	if got, want := len(events), 0; got != want {
		t.Fatalf("len(events) = %d, want %d", got, want)
	}
	if got, want := len(offsets), 0; got != want {
		t.Fatalf("len(offsets) = %d, want %d", got, want)
	}
}

func TestIsNotifiableAnsibleEventFiltersSeverityAndIgnored(t *testing.T) {
	if !isNotifiableAnsibleEvent(ansibleEvent{Severity: "warning"}) {
		t.Fatal("warning should notify")
	}
	if !isNotifiableAnsibleEvent(ansibleEvent{Severity: "error"}) {
		t.Fatal("error should notify")
	}
	if isNotifiableAnsibleEvent(ansibleEvent{Severity: "debug"}) {
		t.Fatal("debug should not notify")
	}
	if isNotifiableAnsibleEvent(ansibleEvent{Severity: "error", Ignored: true}) {
		t.Fatal("ignored errors should not notify")
	}
}
