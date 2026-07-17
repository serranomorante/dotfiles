package main

import (
	"os"
	"path/filepath"
	"testing"
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
