package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSnapshotHandlerWritesLatestBrowserFile(t *testing.T) {
	stateDir := t.TempDir()
	srv := &server{stateDir: stateDir, now: func() time.Time {
		return time.Date(2026, 6, 4, 16, 0, 0, 0, time.UTC)
	}}
	body := `{"schema":"dotfiles.browser-task-sampler.v1","status":"ok","browser":"brave","captured_at":"2026-06-04T16:00:00Z","captured_at_unix_ms":1780588800000,"processes":[{"id":10,"os_process_id":4242,"type":"renderer","cpu_pct":16,"tabs":[{"tab_id":3,"title":"Music","url":"https://example.test/music"}]}]}`
	req := httptest.NewRequest(http.MethodPost, "/v1/browser-task-snapshot", strings.NewReader(body))
	rec := httptest.NewRecorder()

	srv.handleSnapshot(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
	data, err := os.ReadFile(filepath.Join(stateDir, "latest-brave.json"))
	if err != nil {
		t.Fatal(err)
	}
	var got snapshot
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got.Browser != "brave" || len(got.Processes) != 1 || got.Processes[0].CPUPct != 16 {
		t.Fatalf("snapshot = %#v, want brave process cpu", got)
	}
}

func TestSnapshotHandlerRejectsWrongSchema(t *testing.T) {
	srv := &server{stateDir: t.TempDir(), now: time.Now}
	req := httptest.NewRequest(http.MethodPost, "/v1/browser-task-snapshot", strings.NewReader(`{"schema":"other"}`))
	rec := httptest.NewRecorder()

	srv.handleSnapshot(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}
