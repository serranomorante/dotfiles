package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestEventIDFallsBackToVictimIdentity(t *testing.T) {
	ev := event{
		StartedAt: "2026-06-04T19:42:00+02:00",
		Victim:    processRef{PID: 1320, Comm: "Xorg"},
	}

	if got, want := eventID(ev), "2026-06-04T19:42:00+02:00:1320:Xorg"; got != want {
		t.Fatalf("eventID = %q, want %q", got, want)
	}
}

func TestIsXorgEventRecognizesVictimAndTrigger(t *testing.T) {
	if !isXorgEvent(event{VictimKind: "xorg"}) {
		t.Fatal("victim_kind xorg should match")
	}
	if !isXorgEvent(event{Victim: processRef{Comm: "Xorg"}}) {
		t.Fatal("victim comm Xorg should match")
	}
	if !isXorgEvent(event{TriggerProcess: processRef{Comm: "Xorg"}}) {
		t.Fatal("trigger comm Xorg should match")
	}
	if isXorgEvent(event{}) {
		t.Fatal("empty event should not match")
	}
}

func TestReadEventsFiltersAndSorts(t *testing.T) {
	dir := t.TempDir()
	write := func(name, contents string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(contents), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("2026-06-04.jsonl", `{"event_id":"b","started_at":"2026-06-04T19:42:01+02:00","victim_kind":"xorg","victim":{"pid":2,"comm":"Xorg"}}`+"\n"+
		`{"event_id":"skip","started_at":"2026-06-04T19:42:02+02:00","victim_kind":"generic","victim":{"pid":3,"comm":"node"}}`)
	write("2026-06-03.jsonl", `{"started_at":"2026-06-03T19:42:00+02:00","victim_kind":"xorg","victim":{"pid":1,"comm":"Xorg"}}`)

	events, err := readEvents(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := len(events), 2; got != want {
		t.Fatalf("len(events) = %d, want %d", got, want)
	}
	if got, want := eventID(events[0]), "2026-06-03T19:42:00+02:00:1:Xorg"; got != want {
		t.Fatalf("first event = %q, want %q", got, want)
	}
	if got, want := eventID(events[1]), "b"; got != want {
		t.Fatalf("second event = %q, want %q", got, want)
	}
}
