package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNormalizeTitleCompactsAndTruncates(t *testing.T) {
	title := normalizeTitle("  first\n\nsecond\t" + strings.Repeat("x", titleMaxRunes+50))

	if strings.Contains(title, "\n") || strings.Contains(title, "\t") {
		t.Fatalf("title was not compacted: %q", title)
	}
	if !strings.HasPrefix(title, "first second ") {
		t.Fatalf("unexpected title prefix: %q", title)
	}
	if !strings.HasSuffix(title, "...") {
		t.Fatalf("long title should be truncated with ellipsis: %q", title)
	}
	if len([]rune(title)) > titleMaxRunes+3 {
		t.Fatalf("title exceeded max length: %d", len([]rune(title)))
	}
}

func TestNormalizeTitleRejectsGeneratedContext(t *testing.T) {
	title := normalizeTitle("# AGENTS.md instructions for /tmp/project\n\n" + strings.Repeat("x", 1000))

	if title != "" {
		t.Fatalf("generated context should not become a title: %q", title)
	}
}

func TestContentTextBoundsArrayPrompts(t *testing.T) {
	content := []any{
		map[string]any{"text": strings.Repeat("a", titleMaxRunes*8)},
		map[string]any{"text": strings.Repeat("b", titleMaxRunes*8)},
	}

	title := normalizeTitle(contentText(content))
	if !strings.HasSuffix(title, "...") {
		t.Fatalf("array content title should be truncated: %q", title)
	}
	if strings.Contains(title, strings.Repeat("b", 20)) {
		t.Fatalf("contentText should stop after enough title material: %q", title)
	}
}

func TestParseGeminiJSONLSessionUsesProjectRoot(t *testing.T) {
	root := t.TempDir()
	cwd := filepath.Join(root, "repo")
	sessionDir := filepath.Join(root, "gemini", "playbooks", "chats")
	if err := os.MkdirAll(sessionDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "gemini", "playbooks", ".project_root"), []byte(cwd), 0o644); err != nil {
		t.Fatal(err)
	}
	sessionPath := filepath.Join(sessionDir, "session-2026-06-19T10-20-abcd1234.jsonl")
	lines := strings.Join([]string{
		`{"sessionId":"abcd1234-1111-2222-3333-444455556666","startTime":"2026-06-19T10:20:30.000Z","lastUpdated":"2026-06-19T10:21:30.000Z","kind":"main"}`,
		`{"role":"user","parts":[{"text":"Summarize the current playbook change"}]}`,
	}, "\n")
	if err := os.WriteFile(sessionPath, []byte(lines), 0o644); err != nil {
		t.Fatal(err)
	}

	session := parseGeminiSession(sessionPath, cwd)
	if session == nil {
		t.Fatal("expected Gemini session")
	}
	if session.ID != "abcd1234-1111-2222-3333-444455556666" {
		t.Fatalf("unexpected id: %q", session.ID)
	}
	if session.CWD != cwd {
		t.Fatalf("unexpected cwd: %q", session.CWD)
	}
	if session.Title != "Summarize the current playbook change" {
		t.Fatalf("unexpected title: %q", session.Title)
	}
	if session.UpdatedAt != "2026-06-19T10:21:30.000Z" {
		t.Fatalf("unexpected updated_at: %q", session.UpdatedAt)
	}
}

func TestParseGeminiJSONSessionUsesNestedMessages(t *testing.T) {
	root := t.TempDir()
	cwd := filepath.Join(root, "repo")
	sessionDir := filepath.Join(root, "gemini", "playbooks", "chats")
	if err := os.MkdirAll(sessionDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "gemini", "playbooks", ".project_root"), []byte(cwd), 0o644); err != nil {
		t.Fatal(err)
	}
	sessionPath := filepath.Join(sessionDir, "session-2026-06-19T10-20-abcd1234.json")
	payload := `{
  "sessionId": "abcd1234-1111-2222-3333-444455556666",
  "startTime": "2026-06-19T10:20:30.000Z",
  "lastUpdated": "2026-06-19T10:21:30.000Z",
  "messages": [
    { "role": "user", "content": "Review the generic agent task wrapper" }
  ]
}`
	if err := os.WriteFile(sessionPath, []byte(payload), 0o644); err != nil {
		t.Fatal(err)
	}

	session := parseGeminiSession(sessionPath, cwd)
	if session == nil {
		t.Fatal("expected Gemini session")
	}
	if session.Title != "Review the generic agent task wrapper" {
		t.Fatalf("unexpected title: %q", session.Title)
	}
}

func TestParseGeminiSessionRejectsOtherCWD(t *testing.T) {
	root := t.TempDir()
	sessionDir := filepath.Join(root, "gemini", "playbooks", "chats")
	if err := os.MkdirAll(sessionDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "gemini", "playbooks", ".project_root"), []byte(filepath.Join(root, "repo")), 0o644); err != nil {
		t.Fatal(err)
	}
	sessionPath := filepath.Join(sessionDir, "session-2026-06-19T10-20-abcd1234.jsonl")
	line := `{"sessionId":"abcd1234-1111-2222-3333-444455556666","startTime":"2026-06-19T10:20:30.000Z"}`
	if err := os.WriteFile(sessionPath, []byte(line), 0o644); err != nil {
		t.Fatal(err)
	}

	if session := parseGeminiSession(sessionPath, filepath.Join(root, "other")); session != nil {
		t.Fatalf("expected cwd filter to reject session: %#v", session)
	}
}
