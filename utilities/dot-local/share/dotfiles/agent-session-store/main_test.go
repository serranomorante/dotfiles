package main

import (
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
