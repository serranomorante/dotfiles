package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net"
	"reflect"
	"sync"
	"testing"
	"time"
)

type recordedMIDIEvent struct {
	kind       string
	channel    int
	note       int
	velocity   int
	on         bool
	controller int
	value      int
	eventType  int
}

type recordingMIDIOut struct {
	mu     sync.Mutex
	events []recordedMIDIEvent
	closed bool
	err    error
}

type recordedCommand struct {
	name string
	args []string
}

type recordedTFTEvent struct {
	kind             string
	active           bool
	channel          int
	bank             int
	transportRunning bool
	note             int
	velocity         int
	controller       int
	value            int
}

type recordingTFTOut struct {
	mu     sync.Mutex
	events []recordedTFTEvent
	closed bool
}

func (r *recordingMIDIOut) note(channel, note, velocity int, on bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.err != nil {
		return r.err
	}
	r.events = append(r.events, recordedMIDIEvent{
		kind:     "note",
		channel:  channel,
		note:     note,
		velocity: velocity,
		on:       on,
	})
	return nil
}

func (r *recordingMIDIOut) cc(channel, controller, value int) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.err != nil {
		return r.err
	}
	r.events = append(r.events, recordedMIDIEvent{
		kind:       "cc",
		channel:    channel,
		controller: controller,
		value:      value,
	})
	return nil
}

func (r *recordingMIDIOut) realtime(eventType int) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.err != nil {
		return r.err
	}
	r.events = append(r.events, recordedMIDIEvent{
		kind:      "realtime",
		eventType: eventType,
	})
	return nil
}

func (r *recordingMIDIOut) close() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.closed = true
}

func (r *recordingMIDIOut) snapshot() []recordedMIDIEvent {
	r.mu.Lock()
	defer r.mu.Unlock()
	events := make([]recordedMIDIEvent, len(r.events))
	copy(events, r.events)
	return events
}

func (r *recordingMIDIOut) reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = nil
}

func (r *recordingTFTOut) setState(active bool, channel, bank int, transportRunning bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, recordedTFTEvent{
		kind:             "state",
		active:           active,
		channel:          channel,
		bank:             bank,
		transportRunning: transportRunning,
	})
}

func (r *recordingTFTOut) setNote(note, velocity int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, recordedTFTEvent{kind: "note", note: note, velocity: velocity})
}

func (r *recordingTFTOut) setPad(channel, note, velocity int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, recordedTFTEvent{kind: "pad", channel: channel + 1, note: note, velocity: velocity})
}

func (r *recordingTFTOut) setCC(channel, controller, value int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, recordedTFTEvent{kind: "cc", channel: channel + 1, controller: controller, value: value})
}

func (r *recordingTFTOut) clear() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, recordedTFTEvent{kind: "clear"})
}

func (r *recordingTFTOut) close() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.closed = true
}

func (r *recordingTFTOut) snapshot() []recordedTFTEvent {
	r.mu.Lock()
	defer r.mu.Unlock()
	events := make([]recordedTFTEvent, len(r.events))
	copy(events, r.events)
	return events
}

func newTestDaemon(active bool) (*daemon, *recordingMIDIOut) {
	out := &recordingMIDIOut{}
	d := newDaemon(out)
	d.state.active = active
	return d, out
}

func newTestDaemonWithLED(active bool) (*daemon, *recordingMIDIOut, *recordingMIDIOut) {
	out := &recordingMIDIOut{}
	led := &recordingMIDIOut{}
	d := newDaemonWithLED(out, led)
	d.state.active = active
	return d, out, led
}

func newTestDaemonWithLEDAndTFT(active bool) (*daemon, *recordingMIDIOut, *recordingMIDIOut, *recordingTFTOut) {
	out := &recordingMIDIOut{}
	led := &recordingMIDIOut{}
	tft := &recordingTFTOut{}
	d := newDaemonWithFeedbackRenderers(out, led, tft)
	d.state.active = active
	return d, out, led, tft
}

func finalLEDVelocities(events []recordedMIDIEvent) map[int]int {
	result := make(map[int]int)
	for _, ev := range events {
		if ev.kind != "note" {
			continue
		}
		if !ev.on {
			result[ev.note] = 0
			continue
		}
		result[ev.note] = ev.velocity
	}
	return result
}

func TestMultiMIDIOutFansOutAndToleratesPartialFailure(t *testing.T) {
	working := &recordingMIDIOut{}
	failing := &recordingMIDIOut{err: errors.New("offline")}
	out := newMultiMIDIOut()
	out.add("working", working)
	out.add("failing", failing)

	if err := out.note(2, 64, 100, true); err != nil {
		t.Fatalf("note returned error with one working output: %v", err)
	}
	if events := working.snapshot(); len(events) != 1 || events[0].kind != "note" {
		t.Fatalf("working output events = %#v, want one note", events)
	}

	if got := out.outputNames(); !reflect.DeepEqual(got, []string{"working", "failing"}) {
		t.Fatalf("output names = %#v, want working/failing", got)
	}

	out.close()
	working.mu.Lock()
	workingClosed := working.closed
	working.mu.Unlock()
	failing.mu.Lock()
	failingClosed := failing.closed
	failing.mu.Unlock()
	if !workingClosed || !failingClosed {
		t.Fatalf("close did not close every output: working=%t failing=%t", workingClosed, failingClosed)
	}
}

func TestMultiMIDIOutReturnsErrorWhenEveryOutputFails(t *testing.T) {
	out := newMultiMIDIOut()
	out.add("failing", &recordingMIDIOut{err: errors.New("offline")})

	if err := out.cc(0, 10, 127); err == nil {
		t.Fatal("cc returned nil with every output failing")
	}
}

func TestLEDAutoConnectTarget(t *testing.T) {
	if arduinoLEDClientName != "Arduino Micro" {
		t.Fatalf("arduinoLEDClientName = %q, want Arduino Micro", arduinoLEDClientName)
	}
	if arduinoLEDPortName != "Arduino Micro MIDI 1" {
		t.Fatalf("arduinoLEDPortName = %q, want Arduino Micro MIDI 1", arduinoLEDPortName)
	}
	if ledAutoConnectInterval <= 0 {
		t.Fatalf("ledAutoConnectInterval = %s, want positive retry interval", ledAutoConnectInterval)
	}
}

func TestRelativeCCValueAndAddressing(t *testing.T) {
	tests := []struct {
		name  string
		delta int
		want  int
	}{
		{name: "zero", delta: 0, want: 0},
		{name: "medium increment", delta: 4, want: 4},
		{name: "medium decrement", delta: -4, want: 124},
		{name: "clamp positive", delta: 100, want: 63},
		{name: "clamp negative", delta: -100, want: 65},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := relativeCCValue(tt.delta); got != tt.want {
				t.Fatalf("relativeCCValue(%d) = %d, want %d", tt.delta, got, tt.want)
			}
		})
	}

	if got := controllerForEncoder(0, 1); got != 10 {
		t.Fatalf("controllerForEncoder(bank 1, encoder 1) = %d, want 10", got)
	}
	if got := controllerForEncoder(1, 16); got != 41 {
		t.Fatalf("controllerForEncoder(bank 2, encoder 16) = %d, want 41", got)
	}
	if got := controllerForEncoder(10, 16); got != 119 {
		t.Fatalf("controllerForEncoder should cap at 119, got %d", got)
	}
	if got := noteForPad(0, 1); got != 36 {
		t.Fatalf("noteForPad(bank 1, pad 1) = %d, want 36", got)
	}
	if got := noteForPad(3, 16); got != 99 {
		t.Fatalf("noteForPad(bank 4, pad 16) = %d, want 99", got)
	}
}

func TestParseIndexedLayer(t *testing.T) {
	tests := []struct {
		layer string
		want  int
		ok    bool
	}{
		{layer: "midi_enc_01", want: 1, ok: true},
		{layer: "midi_enc_16", want: 16, ok: true},
		{layer: "midi_enc_17", ok: false},
		{layer: "midi_enc_xx", ok: false},
		{layer: "midi_pad_00", ok: false},
		{layer: "readline", ok: false},
	}

	for _, tt := range tests {
		t.Run(tt.layer, func(t *testing.T) {
			got, ok := parseIndexedLayer(tt.layer, "midi_enc_", 16)
			if ok != tt.ok || got != tt.want {
				t.Fatalf("parseIndexedLayer(%q) = %d/%t, want %d/%t", tt.layer, got, ok, tt.want, tt.ok)
			}
		})
	}
}

func captureExternalCommands(t *testing.T) *[]recordedCommand {
	t.Helper()
	var commands []recordedCommand
	previous := runExternalCommand
	runExternalCommand = func(name string, args ...string) error {
		commands = append(commands, recordedCommand{name: name, args: append([]string(nil), args...)})
		return nil
	}
	t.Cleanup(func() {
		runExternalCommand = previous
	})
	return &commands
}

func TestSetActiveControlsMIDIModeOSD(t *testing.T) {
	t.Setenv("HOME", "/home/tester")
	commands := captureExternalCommands(t)
	d, out := newTestDaemon(false)

	if err := d.setActive(true); err != nil {
		t.Fatalf("setActive(true) failed: %v", err)
	}
	if err := d.setActive(false); err != nil {
		t.Fatalf("setActive(false) failed: %v", err)
	}

	wantCommands := []recordedCommand{
		{name: "/home/tester/bin/show_keyboard_midi_osd"},
		{name: "/home/tester/bin/hide_keyboard_midi_osd"},
	}
	if !reflect.DeepEqual(*commands, wantCommands) {
		t.Fatalf("OSD commands = %#v, want %#v", *commands, wantCommands)
	}
	if events := out.snapshot(); len(events) != 0 {
		t.Fatalf("setActive(false) emitted %#v, want no MIDI reset events", events)
	}
}

func TestMIDILayerControlsActiveStateAndOSD(t *testing.T) {
	t.Setenv("HOME", "/home/tester")
	commands := captureExternalCommands(t)
	d, _ := newTestDaemon(false)

	d.handleKeydLayerEvent("+midi")
	if !d.isActive() {
		t.Fatal("daemon did not become active after +midi")
	}

	d.handleKeydLayerEvent("-midi")
	if d.isActive() {
		t.Fatal("daemon stayed active after -midi")
	}

	wantCommands := []recordedCommand{
		{name: "/home/tester/bin/show_keyboard_midi_osd"},
		{name: "/home/tester/bin/hide_keyboard_midi_osd"},
	}
	if !reflect.DeepEqual(*commands, wantCommands) {
		t.Fatalf("OSD commands = %#v, want %#v", *commands, wantCommands)
	}
}

func TestMIDILayerUpdatesLocalLEDModeState(t *testing.T) {
	t.Setenv("HOME", "/home/tester")
	captureExternalCommands(t)
	d, _, led := newTestDaemonWithLED(false)

	d.handleKeydLayerEvent("+midi")
	activeState := finalLEDVelocities(led.snapshot())
	if activeState[ledModeNote] != ledGreen {
		t.Fatalf("active LED mode velocity = %d, want green", activeState[ledModeNote])
	}

	led.reset()
	d.handleKeydLayerEvent("-midi")
	inactiveState := finalLEDVelocities(led.snapshot())
	if inactiveState[ledModeNote] != ledOff {
		t.Fatalf("inactive LED mode velocity = %d, want off", inactiveState[ledModeNote])
	}
}

func TestSetActiveFalseReleasesHeldNotesWithoutControllerReset(t *testing.T) {
	t.Setenv("HOME", "/home/tester")
	captureExternalCommands(t)
	d, out := newTestDaemon(true)
	d.state.held["midi_pad_01"] = heldNote{channel: 1, note: 36, velocity: 100}

	if err := d.setActive(false); err != nil {
		t.Fatalf("setActive(false) failed: %v", err)
	}

	want := []recordedMIDIEvent{
		{kind: "note", channel: 1, note: 36, velocity: 0, on: false},
	}
	if got := out.snapshot(); !reflect.DeepEqual(got, want) {
		t.Fatalf("exit events = %#v, want only held note off %#v", got, want)
	}
}

func TestInactiveModeOnlyTracksModifiers(t *testing.T) {
	d, out := newTestDaemon(false)

	d.handleKeydLayerEvent("+shift")
	d.handleKeydLayerEvent("+midi_enc_01")
	d.handleKeydLayerEvent("+midi_pad_01")

	if events := out.snapshot(); len(events) != 0 {
		t.Fatalf("inactive controller emitted events: %#v", events)
	}
	if !d.state.shift {
		t.Fatal("inactive controller should still track modifier state")
	}
}

func TestEncoderModifiersUseSymmetricSpeedAndDirection(t *testing.T) {
	tests := []struct {
		name      string
		modifiers []string
		wantValue int
	}{
		{name: "no modifier medium increment", wantValue: 2},
		{name: "shift medium decrement", modifiers: []string{"shift"}, wantValue: 126},
		{name: "alt fast increment", modifiers: []string{"alt"}, wantValue: 6},
		{name: "altgr fast increment", modifiers: []string{"altgr"}, wantValue: 6},
		{name: "control fine increment", modifiers: []string{"control"}, wantValue: 1},
		{name: "shift alt fast decrement", modifiers: []string{"shift", "alt"}, wantValue: 122},
		{name: "shift control fine decrement", modifiers: []string{"shift", "control"}, wantValue: 127},
		{name: "alt takes priority over control", modifiers: []string{"alt", "control"}, wantValue: 6},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d, out := newTestDaemon(true)
			for _, modifier := range tt.modifiers {
				d.handleKeydLayerEvent("+" + modifier)
			}

			d.handleKeydLayerEvent("+midi_enc_01")
			d.handleKeydLayerEvent("-midi_enc_01")

			events := out.snapshot()
			if len(events) != 1 {
				t.Fatalf("event count = %d, want 1: %#v", len(events), events)
			}
			got := events[0]
			if got.kind != "cc" || got.channel != 0 || got.controller != 10 || got.value != tt.wantValue {
				t.Fatalf("encoder event = %#v, want channel 0 controller 10 value %d", got, tt.wantValue)
			}
		})
	}
}

func TestEncoderRepeatEmitsRepeatedRelativeCC(t *testing.T) {
	oldDelay := encoderRepeatDelay
	oldInterval := encoderRepeatInterval
	encoderRepeatDelay = time.Millisecond
	encoderRepeatInterval = time.Millisecond
	t.Cleanup(func() {
		encoderRepeatDelay = oldDelay
		encoderRepeatInterval = oldInterval
	})

	d, out := newTestDaemon(true)
	t.Cleanup(d.stopAllEncoders)

	d.handleKeydLayerEvent("+midi_enc_09")
	deadline := time.Now().Add(250 * time.Millisecond)
	for len(out.snapshot()) < 2 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	d.handleKeydLayerEvent("-midi_enc_09")

	events := out.snapshot()
	if len(events) < 2 {
		t.Fatalf("event count = %d, want at least 2: %#v", len(events), events)
	}
	for i, ev := range events[:2] {
		if ev.kind != "cc" || ev.controller != 18 || ev.value != 2 {
			t.Fatalf("repeat encoder event %d = %#v, want controller 18 value 2", i, ev)
		}
	}
}

func TestEncoderReleaseStopsRepeatDuringGraceWindow(t *testing.T) {
	oldDelay := encoderRepeatDelay
	oldInterval := encoderRepeatInterval
	oldGrace := encoderReleaseGrace
	encoderRepeatDelay = 20 * time.Millisecond
	encoderRepeatInterval = time.Millisecond
	encoderReleaseGrace = 100 * time.Millisecond
	t.Cleanup(func() {
		encoderRepeatDelay = oldDelay
		encoderRepeatInterval = oldInterval
		encoderReleaseGrace = oldGrace
	})

	d, out := newTestDaemon(true)
	t.Cleanup(d.stopAllEncoders)

	d.handleKeydLayerEvent("+midi_enc_01")
	d.handleKeydLayerEvent("-midi_enc_01")
	time.Sleep(50 * time.Millisecond)

	events := out.snapshot()
	if len(events) != 1 {
		t.Fatalf("event count after release grace = %d, want only initial turn: %#v", len(events), events)
	}
	if got := events[0]; got.kind != "cc" || got.controller != 10 || got.value != 2 {
		t.Fatalf("initial encoder event = %#v, want controller 10 value 2", got)
	}
}

func TestEncoderRepeatSurvivesReleaseBounceBeforeInitialDelay(t *testing.T) {
	oldDelay := encoderRepeatDelay
	oldInterval := encoderRepeatInterval
	oldGrace := encoderReleaseGrace
	encoderRepeatDelay = 40 * time.Millisecond
	encoderRepeatInterval = 5 * time.Millisecond
	encoderReleaseGrace = 60 * time.Millisecond
	t.Cleanup(func() {
		encoderRepeatDelay = oldDelay
		encoderRepeatInterval = oldInterval
		encoderReleaseGrace = oldGrace
	})

	d, out := newTestDaemon(true)
	t.Cleanup(d.stopAllEncoders)

	d.handleKeydLayerEvent("+midi_enc_01")
	time.Sleep(20 * time.Millisecond)
	d.handleKeydLayerEvent("-midi_enc_01")
	time.Sleep(5 * time.Millisecond)
	d.handleKeydLayerEvent("+midi_enc_01")

	deadline := time.Now().Add(100 * time.Millisecond)
	for len(out.snapshot()) < 3 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	d.handleKeydLayerEvent("-midi_enc_01")

	events := out.snapshot()
	if len(events) < 3 {
		t.Fatalf("event count after release bounce = %d, want at least 3: %#v", len(events), events)
	}
	for i, ev := range events[:3] {
		if ev.kind != "cc" || ev.controller != 10 || ev.value != 2 {
			t.Fatalf("release-bounce encoder event %d = %#v, want controller 10 value 2", i, ev)
		}
	}
}

func TestPadHoldsOriginalNoteAcrossBankAndChannelChanges(t *testing.T) {
	d, out := newTestDaemon(true)

	d.handleKeydLayerEvent("+midi_pad_01")
	d.handleKeydLayerEvent("+midi_pad_01")
	d.handleKeydLayerEvent("+midi_bank_select")
	d.handleKeydLayerEvent("+midi_enc_02")
	d.handleKeydLayerEvent("-midi_enc_02")
	d.handleKeydLayerEvent("-midi_bank_select")
	d.handleKeydLayerEvent("+midi_channel_select")
	d.handleKeydLayerEvent("+midi_enc_02")
	d.handleKeydLayerEvent("-midi_enc_02")
	d.handleKeydLayerEvent("-midi_channel_select")
	d.handleKeydLayerEvent("-midi_pad_01")

	events := out.snapshot()
	if len(events) != 2 {
		t.Fatalf("event count = %d, want note on/off only: %#v", len(events), events)
	}
	if got := events[0]; got.kind != "note" || !got.on || got.channel != 0 || got.note != 36 || got.velocity != 100 {
		t.Fatalf("note on = %#v, want channel 0 note 36 velocity 100", got)
	}
	if got := events[1]; got.kind != "note" || got.on || got.channel != 0 || got.note != 36 || got.velocity != 0 {
		t.Fatalf("note off = %#v, want original channel 0 note 36 velocity 0", got)
	}
}

func TestSelectedTrackNavigationPadsFlashTFTOnLocalPress(t *testing.T) {
	d, out, _, tft := newTestDaemonWithLEDAndTFT(true)
	d.state.channel = 1

	d.handleKeydLayerEvent("+midi_pad_01")
	d.handleKeydLayerEvent("-midi_pad_01")
	d.handleKeydLayerEvent("+midi_pad_02")
	d.handleKeydLayerEvent("-midi_pad_02")

	wantMIDI := []recordedMIDIEvent{
		{kind: "note", channel: 1, note: 36, velocity: 100, on: true},
		{kind: "note", channel: 1, note: 36, velocity: 0, on: false},
		{kind: "note", channel: 1, note: 37, velocity: 100, on: true},
		{kind: "note", channel: 1, note: 37, velocity: 0, on: false},
	}
	if got := out.snapshot(); !reflect.DeepEqual(got, wantMIDI) {
		t.Fatalf("navigation MIDI events = %#v, want %#v", got, wantMIDI)
	}

	wantTFT := []recordedTFTEvent{
		{kind: "pad", channel: 2, note: 36, velocity: 100},
		{kind: "pad", channel: 2, note: 37, velocity: 100},
	}
	if got := tft.snapshot(); !reflect.DeepEqual(got, wantTFT) {
		t.Fatalf("navigation TFT flash events = %#v, want %#v", got, wantTFT)
	}
}

func TestSelectedTrackActionRowPadsFlashTFTOnLocalPress(t *testing.T) {
	d, out, _, tft := newTestDaemonWithLEDAndTFT(true)
	d.state.channel = 1

	d.handleKeydLayerEvent("+midi_pad_09")
	d.handleKeydLayerEvent("-midi_pad_09")
	d.handleKeydLayerEvent("+midi_pad_16")
	d.handleKeydLayerEvent("-midi_pad_16")

	wantMIDI := []recordedMIDIEvent{
		{kind: "note", channel: 1, note: 44, velocity: 100, on: true},
		{kind: "note", channel: 1, note: 44, velocity: 0, on: false},
		{kind: "note", channel: 1, note: 51, velocity: 100, on: true},
		{kind: "note", channel: 1, note: 51, velocity: 0, on: false},
	}
	if got := out.snapshot(); !reflect.DeepEqual(got, wantMIDI) {
		t.Fatalf("selected track action row MIDI events = %#v, want %#v", got, wantMIDI)
	}

	wantTFT := []recordedTFTEvent{
		{kind: "pad", channel: 2, note: 44, velocity: 100},
		{kind: "pad", channel: 2, note: 51, velocity: 100},
	}
	if got := tft.snapshot(); !reflect.DeepEqual(got, wantTFT) {
		t.Fatalf("selected track action row TFT flash events = %#v, want %#v", got, wantTFT)
	}
}

func TestGridPadsFlashTFTOnLocalPress(t *testing.T) {
	d, out, _, tft := newTestDaemonWithLEDAndTFT(true)
	d.state.channel = 8

	d.handleKeydLayerEvent("+midi_pad_01")
	d.handleKeydLayerEvent("-midi_pad_01")

	wantMIDI := []recordedMIDIEvent{
		{kind: "note", channel: 8, note: 36, velocity: 100, on: true},
		{kind: "note", channel: 8, note: 36, velocity: 0, on: false},
	}
	if got := out.snapshot(); !reflect.DeepEqual(got, wantMIDI) {
		t.Fatalf("grid MIDI events = %#v, want %#v", got, wantMIDI)
	}

	wantTFT := []recordedTFTEvent{{kind: "pad", channel: 9, note: 36, velocity: 100}}
	if got := tft.snapshot(); !reflect.DeepEqual(got, wantTFT) {
		t.Fatalf("grid TFT flash events = %#v, want %#v", got, wantTFT)
	}
}

func TestGridPersistentStatePadsDoNotFlashTFTOnLocalPress(t *testing.T) {
	d, out, _, tft := newTestDaemonWithLEDAndTFT(true)
	d.state.channel = 8

	d.handleKeydLayerEvent("+midi_pad_11")
	d.handleKeydLayerEvent("-midi_pad_11")

	wantMIDI := []recordedMIDIEvent{
		{kind: "note", channel: 8, note: 46, velocity: 100, on: true},
		{kind: "note", channel: 8, note: 46, velocity: 0, on: false},
	}
	if got := out.snapshot(); !reflect.DeepEqual(got, wantMIDI) {
		t.Fatalf("grid persistent MIDI events = %#v, want %#v", got, wantMIDI)
	}
	if got := tft.snapshot(); len(got) != 0 {
		t.Fatalf("grid persistent TFT events = %#v, want none", got)
	}
}

func TestControlFeedbackCommandsUpdateRenderers(t *testing.T) {
	d, _, led, tft := newTestDaemonWithLEDAndTFT(true)

	response := runControlCommand(t, d, "feedback-note 9 41 90\n")
	if response != "ok\n" {
		t.Fatalf("feedback-note response = %q, want ok", response)
	}
	wantLED := []recordedMIDIEvent{{kind: "note", channel: 0, note: 41, velocity: 90, on: true}}
	if got := led.snapshot(); !reflect.DeepEqual(got, wantLED) {
		t.Fatalf("feedback-note LED events = %#v, want %#v", got, wantLED)
	}
	wantTFTPad := []recordedTFTEvent{{kind: "pad", channel: 9, note: 41, velocity: 90}}
	if got := tft.snapshot(); !reflect.DeepEqual(got, wantTFTPad) {
		t.Fatalf("feedback-note TFT events = %#v, want %#v", got, wantTFTPad)
	}

	response = runControlCommand(t, d, "feedback-cc 9 90 6\n")
	if response != "ok\n" {
		t.Fatalf("feedback-cc response = %q, want ok", response)
	}
	wantTFT := []recordedTFTEvent{
		{kind: "pad", channel: 9, note: 41, velocity: 90},
		{kind: "cc", channel: 9, controller: 90, value: 6},
	}
	if got := tft.snapshot(); !reflect.DeepEqual(got, wantTFT) {
		t.Fatalf("feedback-cc TFT events = %#v, want %#v", got, wantTFT)
	}
}

func runControlCommand(t *testing.T, d *daemon, command string) string {
	t.Helper()
	server, client := net.Pipe()
	done := make(chan struct{})
	go func() {
		defer close(done)
		d.handleControlConn(server)
	}()
	if _, err := client.Write([]byte(command)); err != nil {
		t.Fatalf("write control command: %v", err)
	}
	response, err := io.ReadAll(client)
	if err != nil {
		t.Fatalf("read control response: %v", err)
	}
	<-done
	return string(response)
}

func TestDirectSelectorsSetBankChannelAndAffectOutput(t *testing.T) {
	d, out := newTestDaemon(true)

	d.handleKeydLayerEvent("+midi_bank_select")
	d.handleKeydLayerEvent("+midi_enc_04")
	d.handleKeydLayerEvent("-midi_enc_04")
	d.handleKeydLayerEvent("-midi_bank_select")
	d.handleKeydLayerEvent("+midi_channel_select")
	d.handleKeydLayerEvent("+midi_enc_16")
	d.handleKeydLayerEvent("-midi_enc_16")
	d.handleKeydLayerEvent("-midi_channel_select")
	d.handleKeydLayerEvent("+midi_enc_16")
	d.handleKeydLayerEvent("-midi_enc_16")
	d.handleKeydLayerEvent("+midi_pad_16")

	events := out.snapshot()
	if len(events) != 2 {
		t.Fatalf("event count = %d, want encoder and pad: %#v", len(events), events)
	}
	if got := events[0]; got.kind != "cc" || got.channel != 15 || got.controller != 73 || got.value != 2 {
		t.Fatalf("selected bank/channel encoder = %#v, want channel 15 controller 73 value 2", got)
	}
	if got := events[1]; got.kind != "note" || !got.on || got.channel != 15 || got.note != 99 {
		t.Fatalf("selected bank/channel pad = %#v, want channel 15 note 99", got)
	}
}

func TestDirectSelectorsCanUsePadIndexesAndSuppressMIDI(t *testing.T) {
	d, out := newTestDaemon(true)

	d.handleKeydLayerEvent("+midi_channel_select")
	d.handleKeydLayerEvent("+midi_pad_16")
	d.handleKeydLayerEvent("-midi_pad_16")
	d.handleKeydLayerEvent("-midi_channel_select")
	d.handleKeydLayerEvent("+midi_bank_select")
	d.handleKeydLayerEvent("+midi_pad_04")
	d.handleKeydLayerEvent("-midi_pad_04")
	d.handleKeydLayerEvent("-midi_bank_select")
	d.handleKeydLayerEvent("+midi_enc_01")
	d.handleKeydLayerEvent("-midi_enc_01")

	events := out.snapshot()
	if len(events) != 1 {
		t.Fatalf("event count = %d, want only encoder after selections: %#v", len(events), events)
	}
	if got := events[0]; got.kind != "cc" || got.channel != 15 || got.controller != 58 || got.value != 2 {
		t.Fatalf("selected via pad encoder = %#v, want channel 15 controller 58 value 2", got)
	}
}

func TestEntrySelectionSetsChannelAndBankWhileTabIsHeld(t *testing.T) {
	d, out := newTestDaemon(false)

	d.handleKeydLayerEvent("+tab_as_modifier")
	d.handleKeydLayerEvent("+midi")
	d.handleKeydLayerEvent("+midi_enc_16")
	d.handleKeydLayerEvent("-midi_enc_16")
	d.handleKeydLayerEvent("+midi_pad_04")
	d.handleKeydLayerEvent("-midi_pad_04")
	d.handleKeydLayerEvent("-tab_as_modifier")
	d.handleKeydLayerEvent("+midi_enc_01")
	d.handleKeydLayerEvent("-midi_enc_01")

	events := out.snapshot()
	if len(events) != 1 {
		t.Fatalf("event count = %d, want only encoder after entry selection: %#v", len(events), events)
	}
	if got := events[0]; got.kind != "cc" || got.channel != 15 || got.controller != 58 || got.value != 2 {
		t.Fatalf("entry-selected encoder = %#v, want channel 15 controller 58 value 2", got)
	}
}

func TestEntrySelectionIsNotArmedWithoutTab(t *testing.T) {
	d, out := newTestDaemon(false)

	d.handleKeydLayerEvent("+midi")
	d.handleKeydLayerEvent("+midi_enc_02")
	d.handleKeydLayerEvent("-midi_enc_02")

	events := out.snapshot()
	if len(events) != 1 {
		t.Fatalf("event count = %d, want encoder without entry selection: %#v", len(events), events)
	}
	if got := events[0]; got.kind != "cc" || got.channel != 0 || got.controller != 11 || got.value != 2 {
		t.Fatalf("plain entry encoder = %#v, want channel 0 controller 11 value 2", got)
	}
}

func TestTransportUtilityKeys(t *testing.T) {
	d, out := newTestDaemon(true)

	d.handleKeydLayerEvent("+midi_transport_toggle")
	d.handleKeydLayerEvent("+midi_transport_toggle")
	d.handleKeydLayerEvent("+midi_transport_continue")

	want := []int{midiEventStart(), midiEventStop(), midiEventContinue()}
	events := out.snapshot()
	if len(events) != len(want) {
		t.Fatalf("event count = %d, want %d: %#v", len(events), len(want), events)
	}
	for i, wantEvent := range want {
		if got := events[i]; got.kind != "realtime" || got.eventType != wantEvent {
			t.Fatalf("transport event %d = %#v, want realtime type %d", i, got, wantEvent)
		}
	}
}

func TestFeedbackNoteEventsForwardToLEDAddressRange(t *testing.T) {
	d, _, led, tft := newTestDaemonWithLEDAndTFT(true)

	d.handleFeedbackEvent(feedbackEvent{kind: feedbackKindNote(), param: ledBaseNote, value: ledGreen, on: true})
	d.handleFeedbackEvent(feedbackEvent{kind: feedbackKindNote(), param: ledBaseNote - 1, value: ledRed, on: true})
	d.handleFeedbackEvent(feedbackEvent{kind: feedbackKindNote(), param: ledBaseNote, value: 64, on: false})

	want := []recordedMIDIEvent{
		{kind: "note", channel: 0, note: ledBaseNote, velocity: ledGreen, on: true},
		{kind: "note", channel: 0, note: ledBaseNote, velocity: 0, on: false},
	}
	if got := led.snapshot(); !reflect.DeepEqual(got, want) {
		t.Fatalf("LED feedback events = %#v, want %#v", got, want)
	}

	wantTFT := []recordedTFTEvent{
		{kind: "pad", channel: 1, note: ledBaseNote, velocity: ledGreen},
		{kind: "pad", channel: 1, note: ledBaseNote, velocity: 0},
	}
	if got := tft.snapshot(); !reflect.DeepEqual(got, wantTFT) {
		t.Fatalf("TFT feedback events = %#v, want %#v", got, wantTFT)
	}
}

func TestFeedbackTransportUpdatesLocalLEDState(t *testing.T) {
	d, _, led, tft := newTestDaemonWithLEDAndTFT(true)
	d.state.bank = 1
	d.state.channel = 2

	d.handleFeedbackEvent(feedbackEvent{kind: feedbackKindRealtime(), eventType: midiEventStart()})
	startState := finalLEDVelocities(led.snapshot())
	if startState[ledPlayNote] != ledGreen {
		t.Fatalf("play LED after start = %d, want green", startState[ledPlayNote])
	}
	if startState[ledModeNote] != ledGreen {
		t.Fatalf("mode LED after start = %d, want green", startState[ledModeNote])
	}
	if startState[ledBankDownNote] != ledDimWhite || startState[ledBankUpNote] != ledDimWhite {
		t.Fatalf("bank LEDs after start = down %d up %d, want dim white", startState[ledBankDownNote], startState[ledBankUpNote])
	}
	tftEvents := tft.snapshot()
	if len(tftEvents) == 0 || tftEvents[0] != (recordedTFTEvent{kind: "state", active: true, channel: 3, bank: 2, transportRunning: true}) {
		t.Fatalf("TFT first transport event = %#v, want active channel/bank/running state", tftEvents)
	}

	led.reset()
	d.handleFeedbackEvent(feedbackEvent{kind: feedbackKindRealtime(), eventType: midiEventStop()})
	stopState := finalLEDVelocities(led.snapshot())
	if stopState[ledPlayNote] != ledOff {
		t.Fatalf("play LED after stop = %d, want off", stopState[ledPlayNote])
	}
}

func TestFeedbackResetCCsAreIgnored(t *testing.T) {
	d, _, led, tft := newTestDaemonWithLEDAndTFT(true)

	d.handleFeedbackEvent(feedbackEvent{kind: feedbackKindCC(), param: 120, value: 0})
	d.handleFeedbackEvent(feedbackEvent{kind: feedbackKindCC(), param: 121, value: 0})
	d.handleFeedbackEvent(feedbackEvent{kind: feedbackKindCC(), param: 123, value: 0})

	if events := led.snapshot(); len(events) != 0 {
		t.Fatalf("feedback reset CCs emitted LED events = %#v, want ignored", events)
	}
	if events := tft.snapshot(); len(events) != 0 {
		t.Fatalf("feedback reset CCs emitted TFT events = %#v, want ignored", events)
	}
}

func TestFeedbackCCEventsForwardToTFT(t *testing.T) {
	d, _, led, tft := newTestDaemonWithLEDAndTFT(true)

	d.handleFeedbackEvent(feedbackEvent{kind: feedbackKindCC(), channel: 0, param: 10, value: 96})

	if events := led.snapshot(); len(events) != 0 {
		t.Fatalf("CC feedback emitted LED events = %#v, want none", events)
	}
	want := []recordedTFTEvent{{kind: "cc", channel: 1, controller: 10, value: 96}}
	if got := tft.snapshot(); !reflect.DeepEqual(got, want) {
		t.Fatalf("TFT CC feedback events = %#v, want %#v", got, want)
	}
}

func TestPanicSendsHeldNoteOffAndControllerReset(t *testing.T) {
	d, out := newTestDaemon(true)
	d.handleKeydLayerEvent("+midi_pad_01")
	out.reset()

	d.handleKeydLayerEvent("+midi_panic")

	events := out.snapshot()
	if len(events) != 33 {
		t.Fatalf("event count = %d, want one note off plus 32 CC resets: %#v", len(events), events)
	}
	if got := events[0]; got.kind != "note" || got.on || got.channel != 0 || got.note != 36 || got.velocity != 0 {
		t.Fatalf("panic note off = %#v, want channel 0 note 36 velocity 0", got)
	}
	for channel := 0; channel < 16; channel++ {
		allNotesOff := events[1+channel*2]
		resetControllers := events[2+channel*2]
		if allNotesOff.kind != "cc" || allNotesOff.channel != channel || allNotesOff.controller != 123 || allNotesOff.value != 0 {
			t.Fatalf("all notes off event for channel %d = %#v", channel, allNotesOff)
		}
		if resetControllers.kind != "cc" || resetControllers.channel != channel || resetControllers.controller != 121 || resetControllers.value != 0 {
			t.Fatalf("reset controllers event for channel %d = %#v", channel, resetControllers)
		}
	}
	if len(d.state.held) != 0 {
		t.Fatalf("held notes after panic = %d, want 0", len(d.state.held))
	}
}

func TestPanicClearsLEDsAndShowsPanicCell(t *testing.T) {
	d, _, led, tft := newTestDaemonWithLEDAndTFT(true)

	if err := d.panic(); err != nil {
		t.Fatalf("panic failed: %v", err)
	}

	events := led.snapshot()
	if len(events) == 0 || events[0].kind != "cc" || events[0].controller != 123 {
		t.Fatalf("LED panic first event = %#v, want all-off CC", events)
	}
	state := finalLEDVelocities(events)
	if state[ledPanicNote] != ledRed {
		t.Fatalf("panic LED = %d, want red", state[ledPanicNote])
	}
	if state[ledModeNote] != ledGreen {
		t.Fatalf("mode LED after panic = %d, want green", state[ledModeNote])
	}

	tftEvents := tft.snapshot()
	if len(tftEvents) == 0 || tftEvents[0].kind != "clear" {
		t.Fatalf("TFT panic first event = %#v, want clear", tftEvents)
	}
}

func TestStatusJSONReportsUserFacingState(t *testing.T) {
	out := newMultiMIDIOut()
	out.add("alsa", &recordingMIDIOut{})
	out.add("jack", &recordingMIDIOut{})
	d := newDaemon(out)
	d.state.active = true
	d.state.bank = 1
	d.state.channel = 2
	d.state.transportRunning = true
	d.state.altgr = true
	d.state.control = true
	d.state.bankSelect = true
	d.state.channelSelect = true
	d.state.tabAsModifier = true
	d.state.entrySelect = true
	d.state.held["midi_pad_01"] = heldNote{channel: 2, note: 52, velocity: 100}

	var buf bytes.Buffer
	d.writeStatus(&buf)

	var status map[string]any
	if err := json.Unmarshal(buf.Bytes(), &status); err != nil {
		t.Fatalf("status is not JSON: %v\n%s", err, buf.String())
	}

	assertStatus := func(key string, want any) {
		t.Helper()
		if got := status[key]; got != want {
			t.Fatalf("status[%q] = %#v, want %#v", key, got, want)
		}
	}
	assertStatus("active", true)
	assertStatus("bank", float64(2))
	assertStatus("channel", float64(3))
	assertStatus("held_notes", float64(1))
	assertStatus("transport_running", true)
	assertStatus("alt_speed", true)
	assertStatus("control_fine", true)
	assertStatus("bank_select", true)
	assertStatus("channel_select", true)
	assertStatus("tab_modifier", true)
	assertStatus("entry_select", true)
	assertStatus("client", clientName)
	assertStatus("port", portName)
	assertStatus("led_client", ledClientName)
	assertStatus("led_port", ledPortName)
	assertStatus("feedback_client", feedbackClientName)
	assertStatus("feedback_port", feedbackPortName)
	assertStatus("tft_serial_port", "")

	outputs, ok := status["outputs"].([]any)
	if !ok {
		t.Fatalf("status[outputs] = %#v, want array", status["outputs"])
	}
	if !reflect.DeepEqual(outputs, []any{"alsa", "jack"}) {
		t.Fatalf("status[outputs] = %#v, want alsa/jack", outputs)
	}
}
