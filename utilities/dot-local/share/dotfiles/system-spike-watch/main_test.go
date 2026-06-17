package main

import "testing"

func TestParseRemoteDebuggingPort(t *testing.T) {
	tests := map[string]int{
		"/usr/lib/chromium/chromium --remote-debugging-port=9222":     9222,
		"/usr/bin/brave --remote-debugging-port 9223 --type=renderer": 9223,
		"/usr/bin/brave --remote-debugging-port=not-a-port":           0,
		"/usr/bin/brave --remote-debugging-port=0":                    0,
		"/usr/bin/brave": 0,
	}
	for cmdline, want := range tests {
		if got := parseRemoteDebuggingPort(cmdline); got != want {
			t.Fatalf("parseRemoteDebuggingPort(%q) = %d, want %d", cmdline, got, want)
		}
	}
}

func TestBrowserProcessKindAndRendererClientID(t *testing.T) {
	cmdline := "/usr/lib/chromium/chromium --type=renderer --renderer-client-id=7"
	if got := browserProcessKind(cmdline); got != "renderer" {
		t.Fatalf("browserProcessKind() = %q, want renderer", got)
	}
	if got := rendererClientID(cmdline); got != "7" {
		t.Fatalf("rendererClientID() = %q, want 7", got)
	}
}

func TestSanitizeBrowserURL(t *testing.T) {
	got := sanitizeBrowserURL("https://example.test/docs?q=secret#token")
	want := "https://example.test/docs"
	if got != want {
		t.Fatalf("sanitizeBrowserURL() = %q, want %q", got, want)
	}
}

func TestNormalizeKittyListenOn(t *testing.T) {
	tests := map[string]string{
		"/run/user/1000/kitty.sock":      "unix:/run/user/1000/kitty.sock",
		"unix:/run/user/1000/kitty.sock": "unix:/run/user/1000/kitty.sock",
		"":                               "",
	}
	for value, want := range tests {
		if got := normalizeKittyListenOn(value); got != want {
			t.Fatalf("normalizeKittyListenOn(%q) = %q, want %q", value, got, want)
		}
	}
}

func TestParseXdotoolActiveWindow(t *testing.T) {
	id, pid, title, ok := parseXdotoolActiveWindow("8388615\n1234\nDocs - Chromium\n")
	if !ok {
		t.Fatal("parseXdotoolActiveWindow() returned ok=false")
	}
	if id != "8388615" || pid != 1234 || title != "Docs - Chromium" {
		t.Fatalf("parseXdotoolActiveWindow() = %q, %d, %q, want active window fields", id, pid, title)
	}
}

func TestMarkBrowserTabsFromActiveWindowTitle(t *testing.T) {
	tabs := []browserTabContext{
		{ID: "1", Type: "page", Title: "Background", URL: "https://background.test/"},
		{ID: "2", Type: "page", Title: "Docs", URL: "https://example.test/docs"},
	}
	activeWindow := activeWindowContext{Title: "Docs - Chromium", Unit: "browser-chromium-test.scope", Status: "ok"}
	got := markBrowserTabs(tabs, &activeWindow, "browser-chromium-test.scope")
	if len(got) != 2 || got[0].Title != "Docs" || !got[0].Active || got[0].Match != "active-window-title" {
		t.Fatalf("markBrowserTabs() = %#v, want Docs marked active first", got)
	}
}

func TestSortBrowserTabsByEvidence(t *testing.T) {
	tabs := []browserTabContext{
		{ID: "1", Type: "page", Title: "Low activity", Score: 3, Probable: true},
		{ID: "2", Type: "page", Title: "High activity", Score: 40, Probable: true},
		{ID: "3", Type: "page", Title: "Browser CPU", BrowserTaskCPUPct: 16, BrowserTaskSource: "chrome.processes"},
	}
	got := sortBrowserTabsByEvidence(tabs)
	if got[0].Title != "Browser CPU" || got[1].Title != "High activity" || got[2].Title != "Low activity" {
		t.Fatalf("sortBrowserTabsByEvidence() = %#v, want browser CPU ordered before CDP score", got)
	}
}

func TestBrowserTabScoreUsesRecentMetrics(t *testing.T) {
	tab := browserTabContext{
		TaskDurationMS:        12,
		ScriptDurationMS:      5,
		LayoutDurationMS:      2,
		RecalcStyleDurationMS: 1,
		VisibilityState:       "visible",
	}
	if got := browserTabScore(tab); got <= 20 {
		t.Fatalf("browserTabScore() = %.1f, want recent activity plus visible bias", got)
	}
}

func TestMergeBrowserTaskSnapshotAddsBrowserCPU(t *testing.T) {
	tabs := []browserTabContext{
		{ID: "A", Type: "page", Title: "Docs", URL: "https://example.test/docs"},
		{ID: "B", Type: "page", Title: "Music", URL: "https://example.test/music"},
	}
	snap := &browserTaskSnapshot{
		Schema: "dotfiles.browser-task-sampler.v1",
		Status: "ok",
		AgeS:   1.2,
		Processes: []browserTaskProcess{
			{
				ID:          42,
				OSProcessID: 4242,
				Type:        "renderer",
				CPUPct:      16,
				Tabs: []browserTaskTab{
					{TabID: 3, Title: "Music", URL: "https://example.test/music", Active: true},
				},
			},
		},
	}

	got := sortBrowserTabsByEvidence(mergeBrowserTaskSnapshot(tabs, snap))

	if got[0].Title != "Music" || got[0].BrowserTaskCPUPct != 16 || got[0].BrowserTaskOSPID != 4242 || !got[0].Probable {
		t.Fatalf("merged tabs = %#v, want Music with browser task CPU evidence", got)
	}
}

func TestDockerContainerIDFromUnit(t *testing.T) {
	unit := "docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope"
	want := "3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4"
	if got := dockerContainerIDFromUnit(unit); got != want {
		t.Fatalf("dockerContainerIDFromUnit() = %q, want %q", got, want)
	}
	if got := shortContainerID(want); got != "3c013d0077ce" {
		t.Fatalf("shortContainerID() = %q, want 3c013d0077ce", got)
	}
}

func TestXorgSuspectsSkipDisplayHostUnit(t *testing.T) {
	topProcesses := []processInfo{
		{PID: 10, Comm: "Xorg", Unit: "sddm.service", CPUPct: 88, LastSeen: 3},
		{PID: 11, Comm: "sddm-helper", Unit: "sddm.service", CPUPct: 22, LastSeen: 3},
		{PID: 20, Comm: "chromium", Unit: "browser-chromium-test.scope", CPUPct: 14, LastSeen: 3},
	}
	suspects := suspectsForEvent(procDelta{pid: 10, comm: "Xorg", cpuPct: 88}, "xorg", 3, topProcesses, unitCPU{Unit: "sddm.service", CPUPct: 110}, topProcesses[0])
	if len(suspects) == 0 {
		t.Fatal("suspectsForEvent() returned no suspects, want chromium context suspect")
	}
	if suspects[0].Unit != "browser-chromium-test.scope" {
		t.Fatalf("primary suspect unit = %q, want browser-chromium-test.scope", suspects[0].Unit)
	}
}

func TestSuspectsPreferActiveVictimUnitOverConcurrentDominantUnit(t *testing.T) {
	topProcesses := []processInfo{
		{PID: 10, Comm: "gulp watch", Unit: "hypothesis-self-hosted.service", CPUPct: 183, LastSeen: 3},
		{PID: 20, Comm: "MainThread", Unit: "kitty-5986-0.scope", CPUPct: 220, LastSeen: 3},
	}
	dominant := unitCPU{Unit: "kitty-5986-0.scope", CPUPct: 220}
	victim := topProcesses[0]
	suspects := suspectsForEvent(procDelta{pid: 10, comm: "gulp watch", cpuPct: 183}, "generic", 3, topProcesses, dominant, victim)
	if len(suspects) < 2 {
		t.Fatalf("suspects length = %d, want at least 2", len(suspects))
	}
	if suspects[0].Unit != "hypothesis-self-hosted.service" || suspects[0].Role != "victim-unit" {
		t.Fatalf("primary suspect = unit %q role %q, want hypothesis-self-hosted.service victim-unit", suspects[0].Unit, suspects[0].Role)
	}
	if suspects[1].Unit != "kitty-5986-0.scope" || suspects[1].Role != "concurrent" {
		t.Fatalf("secondary suspect = unit %q role %q, want kitty concurrent", suspects[1].Unit, suspects[1].Role)
	}
}

func TestNodeThresholdTriggersGenericSpikeAt80Percent(t *testing.T) {
	consecutive := map[string]int{}
	activeKeys := map[string]bool{}
	kind, ok := triggerForDelta(procDelta{pid: 10, comm: "node", cpuPct: 79.9}, consecutive, activeKeys)
	if kind != "generic" || ok {
		t.Fatalf("node 79.9%% trigger = kind %q ok %v, want generic false", kind, ok)
	}

	activeKeys = map[string]bool{}
	kind, ok = triggerForDelta(procDelta{pid: 10, comm: "node", cpuPct: 80}, consecutive, activeKeys)
	if kind != "generic" || !ok {
		t.Fatalf("node 80%% trigger = kind %q ok %v, want generic true", kind, ok)
	}
}

func TestParsePipewireTop(t *testing.T) {
	output := `S   ID  QUANT   RATE    WAIT    BUSY   W/Q   B/Q  ERR FORMAT           NAME
R   59   1024  48000   3.1us  9.4us  0.00  0.42    0 F32LE 2 48000 source_filter.rnnoise
C   82   1024  48000   ---    ---    ---   ---     0                  alsa_output.test
`
	props := map[int]pipewireNodeProps{
		59: {Name: "source_filter.rnnoise", Description: "RNNoise Source", MediaClass: "Audio/Source", AppName: "filter-chain"},
		82: {Name: "alsa_output.test", Description: "USB DAC", MediaClass: "Audio/Sink"},
	}
	nodes := parsePipewireTop(output, props)
	if len(nodes) != 2 {
		t.Fatalf("node count = %d, want 2", len(nodes))
	}
	if nodes[0].ID != 59 || nodes[0].Description != "RNNoise Source" || nodes[0].BusyQuantum != "0.42" {
		t.Fatalf("first node = %#v, want rnnoise with B/Q 0.42", nodes[0])
	}
	if nodes[1].ID != 82 || nodes[1].MediaClass != "Audio/Sink" {
		t.Fatalf("second node = %#v, want Audio/Sink", nodes[1])
	}
}
