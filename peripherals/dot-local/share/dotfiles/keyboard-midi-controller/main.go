package main

/*
#cgo pkg-config: jack
#cgo LDFLAGS: -lasound
#include <alsa/asoundlib.h>
#include <errno.h>
#include <jack/jack.h>
#include <jack/midiport.h>
#include <jack/ringbuffer.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	jack_client_t *client;
	jack_port_t *port;
	jack_ringbuffer_t *ring;
} kmc_jack_out_t;

static int kmc_open(snd_seq_t **seq, const char *client_name, const char *port_name, int *out_port) {
	int err = snd_seq_open(seq, "default", SND_SEQ_OPEN_OUTPUT, 0);
	if (err < 0) {
		return err;
	}

	err = snd_seq_set_client_name(*seq, client_name);
	if (err < 0) {
		snd_seq_close(*seq);
		*seq = NULL;
		return err;
	}

	int port = snd_seq_create_simple_port(
		*seq,
		port_name,
		SND_SEQ_PORT_CAP_READ | SND_SEQ_PORT_CAP_SUBS_READ,
		SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_HARDWARE | SND_SEQ_PORT_TYPE_PORT
	);
	if (port < 0) {
		snd_seq_close(*seq);
		*seq = NULL;
		return port;
	}

	*out_port = port;
	return 0;
}

typedef struct {
	int kind;
	int channel;
	int param;
	int value;
	int on;
	int event_type;
} kmc_feedback_event_t;

static int kmc_open_input(snd_seq_t **seq, const char *client_name, const char *port_name, int *in_port) {
	int err = snd_seq_open(seq, "default", SND_SEQ_OPEN_INPUT, 0);
	if (err < 0) {
		return err;
	}

	err = snd_seq_set_client_name(*seq, client_name);
	if (err < 0) {
		snd_seq_close(*seq);
		*seq = NULL;
		return err;
	}

	int port = snd_seq_create_simple_port(
		*seq,
		port_name,
		SND_SEQ_PORT_CAP_WRITE | SND_SEQ_PORT_CAP_SUBS_WRITE,
		SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_HARDWARE | SND_SEQ_PORT_TYPE_PORT
	);
	if (port < 0) {
		snd_seq_close(*seq);
		*seq = NULL;
		return port;
	}

	*in_port = port;
	return 0;
}

static int kmc_connect_to_named_port(snd_seq_t *seq, int source_port, const char *client_name, const char *port_name) {
	if (seq == NULL) {
		return -ENODEV;
	}

	snd_seq_client_info_t *client_info;
	snd_seq_port_info_t *port_info;
	snd_seq_client_info_alloca(&client_info);
	snd_seq_port_info_alloca(&port_info);

	snd_seq_client_info_set_client(client_info, -1);
	while (snd_seq_query_next_client(seq, client_info) >= 0) {
		int client = snd_seq_client_info_get_client(client_info);
		const char *candidate_client_name = snd_seq_client_info_get_name(client_info);
		if (candidate_client_name == NULL || strcmp(candidate_client_name, client_name) != 0) {
			continue;
		}

		snd_seq_port_info_set_client(port_info, client);
		snd_seq_port_info_set_port(port_info, -1);
		while (snd_seq_query_next_port(seq, port_info) >= 0) {
			const char *candidate_port_name = snd_seq_port_info_get_name(port_info);
			if (candidate_port_name == NULL || strcmp(candidate_port_name, port_name) != 0) {
				continue;
			}

			unsigned int capability = snd_seq_port_info_get_capability(port_info);
			if ((capability & SND_SEQ_PORT_CAP_WRITE) == 0 || (capability & SND_SEQ_PORT_CAP_SUBS_WRITE) == 0) {
				continue;
			}

			int err = snd_seq_connect_to(seq, source_port, client, snd_seq_port_info_get_port(port_info));
			if (err == -EBUSY) {
				return 0;
			}
			return err;
		}
	}

	return -ENOENT;
}

static const char *kmc_strerror(int err) {
	return snd_strerror(err);
}

static int kmc_send_note(snd_seq_t *seq, int port, int channel, int note, int velocity, int on) {
	snd_seq_event_t ev;
	snd_seq_ev_clear(&ev);
	snd_seq_ev_set_source(&ev, port);
	snd_seq_ev_set_subs(&ev);
	snd_seq_ev_set_direct(&ev);
	if (on) {
		snd_seq_ev_set_noteon(&ev, channel, note, velocity);
	} else {
		snd_seq_ev_set_noteoff(&ev, channel, note, velocity);
	}
	return snd_seq_event_output_direct(seq, &ev);
}

static int kmc_send_cc(snd_seq_t *seq, int port, int channel, int controller, int value) {
	snd_seq_event_t ev;
	snd_seq_ev_clear(&ev);
	snd_seq_ev_set_source(&ev, port);
	snd_seq_ev_set_subs(&ev);
	snd_seq_ev_set_direct(&ev);
	snd_seq_ev_set_controller(&ev, channel, controller, value);
	return snd_seq_event_output_direct(seq, &ev);
}

static int kmc_send_realtime(snd_seq_t *seq, int port, int event_type) {
	snd_seq_event_t ev;
	snd_seq_ev_clear(&ev);
	snd_seq_ev_set_source(&ev, port);
	snd_seq_ev_set_subs(&ev);
	snd_seq_ev_set_direct(&ev);
	ev.type = event_type;
	return snd_seq_event_output_direct(seq, &ev);
}

static int kmc_event_start() { return SND_SEQ_EVENT_START; }
static int kmc_event_stop() { return SND_SEQ_EVENT_STOP; }
static int kmc_event_continue() { return SND_SEQ_EVENT_CONTINUE; }

static int kmc_feedback_kind_ignore() { return 0; }
static int kmc_feedback_kind_note() { return 1; }
static int kmc_feedback_kind_cc() { return 2; }
static int kmc_feedback_kind_realtime() { return 3; }

static int kmc_read_feedback_event(snd_seq_t *seq, kmc_feedback_event_t *out) {
	snd_seq_event_t *ev = NULL;
	int err = snd_seq_event_input(seq, &ev);
	if (err < 0) {
		return err;
	}

	memset(out, 0, sizeof(*out));
	out->kind = kmc_feedback_kind_ignore();

	switch (ev->type) {
	case SND_SEQ_EVENT_NOTEON:
		out->kind = kmc_feedback_kind_note();
		out->channel = ev->data.note.channel;
		out->param = ev->data.note.note;
		out->value = ev->data.note.velocity;
		out->on = 1;
		break;
	case SND_SEQ_EVENT_NOTEOFF:
		out->kind = kmc_feedback_kind_note();
		out->channel = ev->data.note.channel;
		out->param = ev->data.note.note;
		out->value = ev->data.note.velocity;
		out->on = 0;
		break;
	case SND_SEQ_EVENT_CONTROLLER:
		out->kind = kmc_feedback_kind_cc();
		out->channel = ev->data.control.channel;
		out->param = ev->data.control.param;
		out->value = ev->data.control.value;
		break;
	case SND_SEQ_EVENT_START:
	case SND_SEQ_EVENT_STOP:
	case SND_SEQ_EVENT_CONTINUE:
		out->kind = kmc_feedback_kind_realtime();
		out->event_type = ev->type;
		break;
	default:
		break;
	}

	return 0;
}

static int kmc_jack_process(jack_nframes_t nframes, void *arg) {
	kmc_jack_out_t *out = (kmc_jack_out_t *)arg;
	void *buffer = jack_port_get_buffer(out->port, nframes);
	jack_midi_clear_buffer(buffer);

	unsigned char frame[4];
	while (jack_ringbuffer_read_space(out->ring) >= sizeof(frame)) {
		jack_ringbuffer_read(out->ring, (char *)frame, sizeof(frame));
		size_t size = frame[0];
		if (size == 0 || size > 3) {
			continue;
		}
		jack_midi_data_t *event = jack_midi_event_reserve(buffer, 0, size);
		if (event == NULL) {
			break;
		}
		memcpy(event, frame + 1, size);
	}

	return 0;
}

static int kmc_jack_open(kmc_jack_out_t **out, const char *client_name, const char *port_name, unsigned int *out_status) {
	jack_status_t status = 0;
	jack_client_t *client = jack_client_open(client_name, JackNoStartServer, &status);
	if (out_status != NULL) {
		*out_status = (unsigned int)status;
	}
	if (client == NULL) {
		return -ENODEV;
	}

	kmc_jack_out_t *jack_out = calloc(1, sizeof(kmc_jack_out_t));
	if (jack_out == NULL) {
		jack_client_close(client);
		return -ENOMEM;
	}
	jack_out->client = client;

	jack_out->port = jack_port_register(client, port_name, JACK_DEFAULT_MIDI_TYPE, JackPortIsOutput | JackPortIsPhysical | JackPortIsTerminal, 0);
	if (jack_out->port == NULL) {
		jack_client_close(client);
		free(jack_out);
		return -EIO;
	}

	jack_out->ring = jack_ringbuffer_create(4096);
	if (jack_out->ring == NULL) {
		jack_client_close(client);
		free(jack_out);
		return -ENOMEM;
	}
	jack_ringbuffer_mlock(jack_out->ring);

	int err = jack_set_process_callback(client, kmc_jack_process, jack_out);
	if (err != 0) {
		jack_ringbuffer_free(jack_out->ring);
		jack_client_close(client);
		free(jack_out);
		return err;
	}

	err = jack_activate(client);
	if (err != 0) {
		jack_ringbuffer_free(jack_out->ring);
		jack_client_close(client);
		free(jack_out);
		return err;
	}

	*out = jack_out;
	return 0;
}

static void kmc_jack_close(kmc_jack_out_t *out) {
	if (out == NULL) {
		return;
	}
	if (out->client != NULL) {
		jack_deactivate(out->client);
		jack_client_close(out->client);
		out->client = NULL;
	}
	if (out->ring != NULL) {
		jack_ringbuffer_free(out->ring);
		out->ring = NULL;
	}
	free(out);
}

static int kmc_jack_send_raw(kmc_jack_out_t *out, unsigned char status, unsigned char data1, unsigned char data2, unsigned char size) {
	if (out == NULL || out->ring == NULL) {
		return -ENODEV;
	}
	if (size == 0 || size > 3) {
		return -EINVAL;
	}
	if (jack_ringbuffer_write_space(out->ring) < 4) {
		return -ENOBUFS;
	}
	unsigned char frame[4] = { size, status, data1, data2 };
	jack_ringbuffer_write(out->ring, (const char *)frame, sizeof(frame));
	return 0;
}
*/
import "C"

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const (
	termiosCBAUD = 0x100f

	clientName = "Keyboard MIDI Controller"
	portName   = "BeatStep Out"

	ledClientName        = "Keyboard MIDI Controller LED"
	ledPortName          = "LED Out"
	feedbackClientName   = "Keyboard MIDI Controller Feedback"
	feedbackPortName     = "Feedback In"
	arduinoLEDClientName = "Arduino Micro"
	arduinoLEDPortName   = "Arduino Micro MIDI 1"
	tftSerialPortEnv     = "KMC_TFT_SERIAL_PORT"

	showMIDIOSDCommand = "show_keyboard_midi_osd"
	hideMIDIOSDCommand = "hide_keyboard_midi_osd"

	minBank = 0
	maxBank = 3

	basePadNote   = 36
	baseEncoderCC = 10
	ledBaseNote   = 36
	ledCellCount  = 64

	ledPlayNote      = 92
	ledRecordNote    = 93
	ledLoopNote      = 94
	ledMetronomeNote = 95
	ledBankDownNote  = 96
	ledBankUpNote    = 97
	ledPanicNote     = 98
	ledModeNote      = 99

	padVelocity = 100

	ledOff      = 0
	ledRed      = 1
	ledAmber    = 2
	ledYellow   = 3
	ledGreen    = 4
	ledCyan     = 5
	ledBlue     = 6
	ledPurple   = 7
	ledDimWhite = 100

	stepFine   = 1
	stepMedium = 2
	stepFast   = 6

	keydListenCommand = "keyd"

	tftSerialBaud = 115200
)

var (
	encoderRepeatDelay     = 120 * time.Millisecond
	encoderRepeatInterval  = 30 * time.Millisecond
	encoderReleaseGrace    = 45 * time.Millisecond
	ledAutoConnectInterval = 2 * time.Second
)

type midiOut struct {
	mu   sync.Mutex
	seq  *C.snd_seq_t
	port C.int
}

type jackMIDIOut struct {
	mu     sync.Mutex
	client *C.kmc_jack_out_t
}

type feedbackMIDIIn struct {
	mu   sync.Mutex
	seq  *C.snd_seq_t
	port C.int
}

type managedMIDIOutput interface {
	midiOutput
	close()
}

type namedMIDIOutput struct {
	name string
	out  managedMIDIOutput
}

type multiMIDIOut struct {
	mu      sync.RWMutex
	outputs []namedMIDIOutput
}

type midiOutput interface {
	note(channel, note, velocity int, on bool) error
	cc(channel, controller, value int) error
	realtime(eventType int) error
}

type tftOutput interface {
	setState(active bool, channel, bank int, transportRunning bool)
	setNote(note, velocity int)
	setPad(channel, note, velocity int)
	setCC(channel, controller, value int)
	clear()
	close()
}

type heldNote struct {
	channel  int
	note     int
	velocity int
}

type encoderHold struct {
	stop         chan struct{}
	releaseTimer *time.Timer
}

type controllerState struct {
	mu               sync.Mutex
	active           bool
	bank             int
	channel          int
	transportRunning bool
	shift            bool
	alt              bool
	altgr            bool
	control          bool
	bankSelect       bool
	channelSelect    bool
	tabAsModifier    bool
	entrySelect      bool
	held             map[string]heldNote
}

type daemon struct {
	out          midiOutput
	led          midiOutput
	tft          tftOutput
	state        *controllerState
	encoderMu    sync.Mutex
	encoderHolds map[string]*encoderHold
}

var runExternalCommand = func(name string, args ...string) error {
	return exec.Command(name, args...).Run()
}

func main() {
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)
	log.SetPrefix("keyboard-midi-controller: ")

	if len(os.Args) < 2 {
		usage()
	}

	switch os.Args[1] {
	case "run":
		if len(os.Args) != 2 {
			usage()
		}
		if err := run(); err != nil {
			log.Fatal(err)
		}
	case "toggle", "enter", "exit", "status", "panic":
		if len(os.Args) != 2 {
			usage()
		}
		if err := sendCommand(os.Args[1]); err != nil {
			log.Fatal(err)
		}
	case "feedback-note", "feedback-cc":
		if len(os.Args) != 5 {
			usage()
		}
		if err := sendCommand(strings.Join(os.Args[1:], " ")); err != nil {
			log.Fatal(err)
		}
	case "-h", "--help":
		usage()
	default:
		usage()
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "usage: keyboard-midi-controller [run|toggle|enter|exit|status|panic|feedback-note CH NOTE VEL|feedback-cc CH CC VALUE]\n")
	os.Exit(2)
}

func run() error {
	out := waitForMIDI()
	defer out.close()

	ledOut := waitForLEDMIDI()
	defer ledOut.close()
	go runLEDAutoConnectLoop(ledOut)

	tftOut := newSerialTFTOutput()
	defer tftOut.close()

	feedbackIn := waitForFeedbackMIDI()
	defer feedbackIn.close()

	d := newDaemonWithFeedbackRenderers(out, ledOut, tftOut)
	setMIDIModeNotification(false)
	d.refreshLocalLEDState()

	if err := d.startControlSocket(); err != nil {
		return err
	}

	go d.runKeydListenLoop()
	go d.runFeedbackLoop(feedbackIn)

	select {}
}

func newDaemon(out midiOutput) *daemon {
	return newDaemonWithLED(out, nil)
}

func newDaemonWithLED(out midiOutput, led midiOutput) *daemon {
	return newDaemonWithFeedbackRenderers(out, led, nil)
}

func newDaemonWithFeedbackRenderers(out midiOutput, led midiOutput, tft tftOutput) *daemon {
	return &daemon{
		out:          out,
		led:          led,
		tft:          tft,
		state:        newControllerState(),
		encoderHolds: make(map[string]*encoderHold),
	}
}

func newControllerState() *controllerState {
	return &controllerState{
		channel: 0,
		held:    make(map[string]heldNote),
	}
}

func waitForMIDI() *multiMIDIOut {
	for {
		out, err := openMIDI()
		if err == nil {
			multi := newMultiMIDIOut()
			multi.add("alsa", out)
			go attachJACKMIDI(multi)
			return multi
		}
		log.Printf("could not open ALSA sequencer: %v; retrying", err)
		time.Sleep(2 * time.Second)
	}
}

func waitForLEDMIDI() *midiOut {
	for {
		out, err := openNamedMIDI(ledClientName, ledPortName)
		if err == nil {
			return out
		}
		log.Printf("could not open ALSA LED sequencer: %v; retrying", err)
		time.Sleep(2 * time.Second)
	}
}

func waitForFeedbackMIDI() *feedbackMIDIIn {
	for {
		in, err := openFeedbackMIDI()
		if err == nil {
			return in
		}
		log.Printf("could not open ALSA feedback sequencer: %v; retrying", err)
		time.Sleep(2 * time.Second)
	}
}

func newMultiMIDIOut() *multiMIDIOut {
	return &multiMIDIOut{}
}

func (m *multiMIDIOut) add(name string, out managedMIDIOutput) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, existing := range m.outputs {
		if existing.name == name {
			out.close()
			return
		}
	}
	m.outputs = append(m.outputs, namedMIDIOutput{name: name, out: out})
}

func (m *multiMIDIOut) snapshot() []namedMIDIOutput {
	m.mu.RLock()
	defer m.mu.RUnlock()
	outputs := make([]namedMIDIOutput, len(m.outputs))
	copy(outputs, m.outputs)
	return outputs
}

func (m *multiMIDIOut) outputNames() []string {
	outputs := m.snapshot()
	names := make([]string, 0, len(outputs))
	for _, output := range outputs {
		names = append(names, output.name)
	}
	return names
}

func (m *multiMIDIOut) close() {
	m.mu.Lock()
	outputs := m.outputs
	m.outputs = nil
	m.mu.Unlock()

	for _, output := range outputs {
		output.out.close()
	}
}

func (m *multiMIDIOut) note(channel, note, velocity int, on bool) error {
	return m.send(func(out midiOutput) error {
		return out.note(channel, note, velocity, on)
	})
}

func (m *multiMIDIOut) cc(channel, controller, value int) error {
	return m.send(func(out midiOutput) error {
		return out.cc(channel, controller, value)
	})
}

func (m *multiMIDIOut) realtime(eventType int) error {
	return m.send(func(out midiOutput) error {
		return out.realtime(eventType)
	})
}

func (m *multiMIDIOut) send(sendOne func(midiOutput) error) error {
	outputs := m.snapshot()
	if len(outputs) == 0 {
		return errors.New("no MIDI outputs are open")
	}

	var result error
	successes := 0
	for _, output := range outputs {
		if err := sendOne(output.out); err != nil {
			result = errors.Join(result, fmt.Errorf("%s: %w", output.name, err))
			continue
		}
		successes++
	}
	if successes > 0 {
		return nil
	}
	return result
}

func attachJACKMIDI(out *multiMIDIOut) {
	for {
		jackOut, err := openJACKMIDI()
		if err == nil {
			out.add("jack", jackOut)
			return
		}
		log.Printf("could not open JACK MIDI port: %v; retrying", err)
		time.Sleep(2 * time.Second)
	}
}

func openMIDI() (*midiOut, error) {
	return openNamedMIDI(clientName, portName)
}

func openNamedMIDI(clientNameValue, portNameValue string) (*midiOut, error) {
	client := C.CString(clientNameValue)
	port := C.CString(portNameValue)
	defer C.free(unsafe.Pointer(client))
	defer C.free(unsafe.Pointer(port))

	var seq *C.snd_seq_t
	var outPort C.int
	if code := C.kmc_open(&seq, client, port, &outPort); code < 0 {
		return nil, alsaError(code)
	}

	log.Printf("opened ALSA sequencer client %q port %q", clientNameValue, portNameValue)
	return &midiOut{seq: seq, port: outPort}, nil
}

func openFeedbackMIDI() (*feedbackMIDIIn, error) {
	client := C.CString(feedbackClientName)
	port := C.CString(feedbackPortName)
	defer C.free(unsafe.Pointer(client))
	defer C.free(unsafe.Pointer(port))

	var seq *C.snd_seq_t
	var inPort C.int
	if code := C.kmc_open_input(&seq, client, port, &inPort); code < 0 {
		return nil, alsaError(code)
	}

	log.Printf("opened ALSA feedback client %q port %q", feedbackClientName, feedbackPortName)
	return &feedbackMIDIIn{seq: seq, port: inPort}, nil
}

func (m *midiOut) close() {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.seq != nil {
		C.snd_seq_close(m.seq)
		m.seq = nil
	}
}

func (m *midiOut) connectTo(clientNameValue, portNameValue string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.seq == nil {
		return errors.New("alsa sequencer is closed")
	}

	client := C.CString(clientNameValue)
	port := C.CString(portNameValue)
	defer C.free(unsafe.Pointer(client))
	defer C.free(unsafe.Pointer(port))

	if code := C.kmc_connect_to_named_port(m.seq, m.port, client, port); code < 0 {
		return alsaError(code)
	}
	return nil
}

func runLEDAutoConnectLoop(out *midiOut) {
	connected := false
	attempts := 0
	for {
		err := out.connectTo(arduinoLEDClientName, arduinoLEDPortName)
		if err == nil {
			if !connected {
				log.Printf("connected ALSA LED port %q:%q to %q:%q", ledClientName, ledPortName, arduinoLEDClientName, arduinoLEDPortName)
			}
			connected = true
			attempts = 0
		} else {
			if connected {
				log.Printf("ALSA LED connection to %q:%q is not available; reconnecting: %v", arduinoLEDClientName, arduinoLEDPortName, err)
			} else if attempts == 0 || attempts%30 == 0 {
				log.Printf("could not connect ALSA LED port to %q:%q: %v; retrying", arduinoLEDClientName, arduinoLEDPortName, err)
			}
			connected = false
			attempts++
		}
		time.Sleep(ledAutoConnectInterval)
	}
}

type serialTFTOutput struct {
	mu       sync.Mutex
	file     *os.File
	port     string
	attempts int
}

func newSerialTFTOutput() *serialTFTOutput {
	return &serialTFTOutput{}
}

func (t *serialTFTOutput) setState(active bool, channel, bank int, transportRunning bool) {
	t.sendLine(fmt.Sprintf("S %d %d %d %d", boolToInt(active), channel, bank, boolToInt(transportRunning)))
}

func (t *serialTFTOutput) setNote(note, velocity int) {
	if !isLEDNote(note) {
		return
	}
	t.sendLine(fmt.Sprintf("N %d %d", note, clampMIDIData(velocity)))
}

func (t *serialTFTOutput) setPad(channel, note, velocity int) {
	if !isLEDNote(note) {
		return
	}
	t.sendLine(fmt.Sprintf("P %d %d %d", clampMIDIChannel(channel)+1, note, clampMIDIData(velocity)))
}

func (t *serialTFTOutput) setCC(channel, controller, value int) {
	t.sendLine(fmt.Sprintf("K %d %d %d", clampMIDIChannel(channel)+1, clampMIDIData(controller), clampMIDIData(value)))
}

func (t *serialTFTOutput) clear() {
	t.sendLine("C")
}

func (t *serialTFTOutput) close() {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.closeLocked()
}

func (t *serialTFTOutput) sendLine(line string) {
	t.mu.Lock()
	defer t.mu.Unlock()

	if t.file == nil {
		if err := t.openLocked(); err != nil {
			if t.attempts == 0 || t.attempts%30 == 0 {
				log.Printf("could not open TFT serial output: %v; retrying", err)
			}
			t.attempts++
			return
		}
		t.attempts = 0
	}

	if _, err := fmt.Fprintln(t.file, line); err != nil {
		log.Printf("TFT serial write to %s failed: %v; reconnecting", t.port, err)
		t.closeLocked()
	}
}

func (t *serialTFTOutput) openLocked() error {
	port, err := discoverTFTSerialPort()
	if err != nil {
		return err
	}
	file, err := os.OpenFile(port, os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	if err := configureSerialPort(file); err != nil {
		_ = file.Close()
		return err
	}
	t.file = file
	t.port = port
	log.Printf("opened TFT serial output %s", port)
	return nil
}

func (t *serialTFTOutput) closeLocked() {
	if t.file != nil {
		_ = t.file.Close()
		t.file = nil
	}
	t.port = ""
}

func discoverTFTSerialPort() (string, error) {
	if port := strings.TrimSpace(os.Getenv(tftSerialPortEnv)); port != "" {
		return port, nil
	}

	matches, _ := filepath.Glob("/dev/serial/by-id/*")
	for _, match := range matches {
		name := strings.ToLower(filepath.Base(match))
		if strings.Contains(name, "arduino") {
			continue
		}
		if strings.Contains(name, "esp") || strings.Contains(name, "serial") || strings.Contains(name, "1a86") || strings.Contains(name, "ch910") || strings.Contains(name, "ch343") {
			return match, nil
		}
	}

	return "", fmt.Errorf("no TFT serial device found; set %s=/dev/...", tftSerialPortEnv)
}

func configureSerialPort(file *os.File) error {
	var term syscall.Termios
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, file.Fd(), uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&term))); errno != 0 {
		return errno
	}

	term.Iflag = syscall.IGNPAR
	term.Oflag = 0
	term.Lflag = 0
	term.Cflag &^= syscall.CSIZE | syscall.PARENB | syscall.CSTOPB | termiosCBAUD
	term.Cflag |= syscall.CS8 | syscall.CREAD | syscall.CLOCAL | syscall.B115200
	term.Ispeed = syscall.B115200
	term.Ospeed = syscall.B115200
	term.Cc[syscall.VMIN] = 0
	term.Cc[syscall.VTIME] = 1

	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, file.Fd(), uintptr(syscall.TCSETS), uintptr(unsafe.Pointer(&term))); errno != 0 {
		return errno
	}
	return nil
}

func boolToInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func (f *feedbackMIDIIn) close() {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.seq != nil {
		C.snd_seq_close(f.seq)
		f.seq = nil
	}
}

func alsaError(code C.int) error {
	return fmt.Errorf("alsa: %s", C.GoString(C.kmc_strerror(code)))
}

func (m *midiOut) note(channel, note, velocity int, on bool) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.seq == nil {
		return errors.New("alsa sequencer is closed")
	}
	onFlag := C.int(0)
	if on {
		onFlag = 1
	}
	if code := C.kmc_send_note(m.seq, m.port, C.int(channel), C.int(note), C.int(velocity), onFlag); code < 0 {
		return alsaError(code)
	}
	return nil
}

func (m *midiOut) cc(channel, controller, value int) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.seq == nil {
		return errors.New("alsa sequencer is closed")
	}
	if code := C.kmc_send_cc(m.seq, m.port, C.int(channel), C.int(controller), C.int(value)); code < 0 {
		return alsaError(code)
	}
	return nil
}

func (m *midiOut) realtime(eventType int) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.seq == nil {
		return errors.New("alsa sequencer is closed")
	}
	if code := C.kmc_send_realtime(m.seq, m.port, C.int(eventType)); code < 0 {
		return alsaError(code)
	}
	return nil
}

type feedbackEvent struct {
	kind      int
	channel   int
	param     int
	value     int
	on        bool
	eventType int
}

func feedbackKindIgnore() int {
	return int(C.kmc_feedback_kind_ignore())
}

func feedbackKindNote() int {
	return int(C.kmc_feedback_kind_note())
}

func feedbackKindCC() int {
	return int(C.kmc_feedback_kind_cc())
}

func feedbackKindRealtime() int {
	return int(C.kmc_feedback_kind_realtime())
}

func (f *feedbackMIDIIn) read() (feedbackEvent, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.seq == nil {
		return feedbackEvent{}, errors.New("feedback sequencer is closed")
	}
	var ev C.kmc_feedback_event_t
	if code := C.kmc_read_feedback_event(f.seq, &ev); code < 0 {
		return feedbackEvent{}, alsaError(code)
	}
	return feedbackEvent{
		kind:      int(ev.kind),
		channel:   int(ev.channel),
		param:     int(ev.param),
		value:     int(ev.value),
		on:        int(ev.on) != 0,
		eventType: int(ev.event_type),
	}, nil
}

func openJACKMIDI() (*jackMIDIOut, error) {
	client := C.CString(clientName)
	port := C.CString(portName)
	defer C.free(unsafe.Pointer(client))
	defer C.free(unsafe.Pointer(port))

	var out *C.kmc_jack_out_t
	var status C.uint
	if code := C.kmc_jack_open(&out, client, port, &status); code != 0 {
		return nil, jackError(code, status)
	}

	log.Printf("opened JACK MIDI client %q port %q", clientName, portName)
	return &jackMIDIOut{client: out}, nil
}

func jackError(code C.int, status C.uint) error {
	return fmt.Errorf("jack: open failed code=%d status=%d", int(code), uint(status))
}

func (j *jackMIDIOut) close() {
	j.mu.Lock()
	defer j.mu.Unlock()
	if j.client != nil {
		C.kmc_jack_close(j.client)
		j.client = nil
	}
}

func (j *jackMIDIOut) note(channel, note, velocity int, on bool) error {
	status := 0x80 | clampMIDIChannel(channel)
	if on {
		status = 0x90 | clampMIDIChannel(channel)
	}
	return j.sendRaw(status, clampMIDIData(note), clampMIDIData(velocity), 3)
}

func (j *jackMIDIOut) cc(channel, controller, value int) error {
	status := 0xB0 | clampMIDIChannel(channel)
	return j.sendRaw(status, clampMIDIData(controller), clampMIDIData(value), 3)
}

func (j *jackMIDIOut) realtime(eventType int) error {
	switch eventType {
	case midiEventStart():
		return j.sendRaw(0xFA, 0, 0, 1)
	case midiEventContinue():
		return j.sendRaw(0xFB, 0, 0, 1)
	case midiEventStop():
		return j.sendRaw(0xFC, 0, 0, 1)
	default:
		return fmt.Errorf("unsupported JACK realtime event type %d", eventType)
	}
}

func (j *jackMIDIOut) sendRaw(status, data1, data2, size int) error {
	j.mu.Lock()
	defer j.mu.Unlock()
	if j.client == nil {
		return errors.New("JACK MIDI client is closed")
	}
	if code := C.kmc_jack_send_raw(j.client, C.uchar(status), C.uchar(data1), C.uchar(data2), C.uchar(size)); code != 0 {
		return fmt.Errorf("jack midi send failed: code=%d", int(code))
	}
	return nil
}

func clampMIDIChannel(channel int) int {
	if channel < 0 {
		return 0
	}
	if channel > 15 {
		return 15
	}
	return channel
}

func clampMIDIData(value int) int {
	if value < 0 {
		return 0
	}
	if value > 127 {
		return 127
	}
	return value
}

func midiEventStart() int {
	return int(C.kmc_event_start())
}

func midiEventStop() int {
	return int(C.kmc_event_stop())
}

func midiEventContinue() int {
	return int(C.kmc_event_continue())
}

func isLEDNote(note int) bool {
	return note >= ledBaseNote && note < ledBaseNote+ledCellCount
}

func (d *daemon) setLED(note, velocity int) {
	if !isLEDNote(note) {
		return
	}
	if d.tft != nil {
		d.tft.setNote(note, velocity)
	}
	if d.led == nil {
		return
	}
	on := velocity > 0
	if err := d.led.note(0, note, velocity, on); err != nil {
		log.Printf("LED note=%d velocity=%d failed: %v", note, velocity, err)
	}
}

func (d *daemon) allLEDsOff() {
	if d.tft != nil {
		d.tft.clear()
	}
	if d.led != nil {
		if err := d.led.cc(0, 123, 0); err != nil {
			log.Printf("LED all-off failed: %v", err)
		}
	}
}

func (d *daemon) refreshLocalLEDState() {
	d.state.mu.Lock()
	active := d.state.active
	bank := d.state.bank
	channel := d.state.channel
	transportRunning := d.state.transportRunning
	d.state.mu.Unlock()

	if d.tft != nil {
		d.tft.setState(active, channel+1, bank+1, transportRunning)
	}

	d.setLED(ledModeNote, ledOff)
	d.setLED(ledPlayNote, ledOff)
	d.setLED(ledBankDownNote, ledOff)
	d.setLED(ledBankUpNote, ledOff)

	if active {
		d.setLED(ledModeNote, ledGreen)
	}
	if transportRunning {
		d.setLED(ledPlayNote, ledGreen)
	}
	if bank > minBank {
		d.setLED(ledBankDownNote, ledDimWhite)
	}
	if bank < maxBank {
		d.setLED(ledBankUpNote, ledDimWhite)
	}
}

func (d *daemon) setActive(active bool) error {
	if active {
		d.state.mu.Lock()
		d.state.active = true
		d.state.mu.Unlock()
		setMIDIModeNotification(true)
		d.refreshLocalLEDState()
		return nil
	}

	d.state.mu.Lock()
	d.state.active = false
	d.state.bankSelect = false
	d.state.channelSelect = false
	d.state.entrySelect = false
	d.state.mu.Unlock()

	var result error
	d.stopAllEncoders()
	if err := d.releaseHeldNotes(); err != nil {
		log.Printf("note release on midi exit failed: %v", err)
		result = errors.Join(result, err)
	}
	setMIDIModeNotification(false)
	d.refreshLocalLEDState()
	return result
}

func setMIDIModeNotification(active bool) {
	command := hideMIDIOSDCommand
	action := "hide"
	if active {
		command = showMIDIOSDCommand
		action = "show"
	}
	if err := runExternalCommand(userBinCommand(command)); err != nil {
		log.Printf("could not %s MIDI mode notification: %v", action, err)
	}
}

func userBinCommand(command string) string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return command
	}
	return filepath.Join(home, "bin", command)
}

func (d *daemon) encoderDelta(direction int) int {
	d.state.mu.Lock()
	alt := d.state.alt || d.state.altgr
	control := d.state.control
	d.state.mu.Unlock()

	step := stepMedium
	switch {
	case alt:
		step = stepFast
	case control:
		step = stepFine
	}

	return direction * step
}

func (d *daemon) runKeydListenLoop() {
	for {
		if err := d.consumeKeydListen(); err != nil {
			log.Printf("keyd listen ended: %v", err)
		}
		time.Sleep(time.Second)
	}
}

func (d *daemon) consumeKeydListen() error {
	cmd := exec.Command(keydListenCommand, "listen")
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return err
	}

	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		d.handleKeydLayerEvent(scanner.Text())
	}
	return errors.Join(scanner.Err(), cmd.Wait())
}

func (d *daemon) handleKeydLayerEvent(line string) {
	line = strings.TrimSpace(line)
	if len(line) < 2 {
		return
	}

	pressed := false
	switch line[0] {
	case '+':
		pressed = true
	case '-':
	default:
		return
	}
	layer := line[1:]

	if d.updateLayerModifier(layer, pressed) {
		return
	}

	if layer == "midi" {
		if err := d.setActive(pressed); err != nil {
			log.Printf("midi layer active=%t failed: %v", pressed, err)
		}
		if pressed {
			d.armEntrySelection()
		}
		return
	}

	if index, ok := parseIndexedLayer(layer, "midi_enc_", 16); ok {
		if pressed {
			if d.handleDirectSelection(index, selectionEncoder) {
				return
			}
			d.encoderOn(layer, index)
		} else {
			d.encoderOff(layer)
		}
		return
	}

	if index, ok := parseIndexedLayer(layer, "midi_pad_", 16); ok {
		if pressed {
			if !d.isActive() {
				return
			}
			if d.handleDirectSelection(index, selectionPad) {
				return
			}
			if err := d.padOn(layer, index); err != nil {
				log.Printf("pad layer %s failed: %v", layer, err)
			}
		} else if err := d.padOff(layer); err != nil {
			log.Printf("pad layer %s release failed: %v", layer, err)
		}
		return
	}

	if !pressed || !d.isActive() {
		return
	}

	var err error
	switch layer {
	case "midi_transport_toggle":
		err = d.transportToggle()
	case "midi_transport_continue":
		err = d.out.realtime(midiEventContinue())
	case "midi_panic":
		err = d.panic()
	default:
		return
	}
	if err != nil {
		log.Printf("utility layer %s failed: %v", layer, err)
	}
}

func (d *daemon) updateLayerModifier(layer string, pressed bool) bool {
	d.state.mu.Lock()
	defer d.state.mu.Unlock()

	switch layer {
	case "midi_bank_select":
		d.state.bankSelect = pressed
	case "midi_channel_select":
		d.state.channelSelect = pressed
	case "tab_as_modifier":
		d.state.tabAsModifier = pressed
		if !pressed {
			d.state.entrySelect = false
		}
	case "shift":
		d.state.shift = pressed
	case "alt":
		d.state.alt = pressed
	case "altgr":
		d.state.altgr = pressed
	case "control":
		d.state.control = pressed
	default:
		return false
	}
	return true
}

type selectionSource int

const (
	selectionEncoder selectionSource = iota
	selectionPad
)

func (d *daemon) armEntrySelection() {
	d.state.mu.Lock()
	defer d.state.mu.Unlock()
	if d.state.active && d.state.tabAsModifier {
		d.state.entrySelect = true
	}
}

func (d *daemon) handleDirectSelection(index int, source selectionSource) bool {
	d.state.mu.Lock()

	if !d.state.active {
		d.state.mu.Unlock()
		return false
	}

	refreshLED := false
	switch {
	case d.state.channelSelect:
		d.state.channel = index - 1
		refreshLED = true
		log.Printf("channel=%d", index)
	case d.state.bankSelect:
		if index < minBank+1 || index > maxBank+1 {
			log.Printf("bank selection index=%d ignored", index)
			d.state.mu.Unlock()
			return true
		}
		d.state.bank = index - 1
		refreshLED = true
		log.Printf("bank=%d", index)
	case d.state.entrySelect && source == selectionEncoder:
		d.state.channel = index - 1
		refreshLED = true
		log.Printf("entry channel=%d", index)
	case d.state.entrySelect && source == selectionPad:
		if index < minBank+1 || index > maxBank+1 {
			log.Printf("entry bank selection index=%d ignored", index)
			d.state.mu.Unlock()
			return true
		}
		d.state.bank = index - 1
		refreshLED = true
		log.Printf("entry bank=%d", index)
	default:
		d.state.mu.Unlock()
		return false
	}
	d.state.mu.Unlock()
	if refreshLED {
		d.refreshLocalLEDState()
	}
	return true
}

func (d *daemon) isActive() bool {
	d.state.mu.Lock()
	defer d.state.mu.Unlock()
	return d.state.active
}

func parseIndexedLayer(layer, prefix string, max int) (int, bool) {
	if !strings.HasPrefix(layer, prefix) {
		return 0, false
	}
	index, err := strconv.Atoi(strings.TrimPrefix(layer, prefix))
	if err != nil || index < 1 || index > max {
		return 0, false
	}
	return index, true
}

func (d *daemon) encoderOn(signal string, index int) {
	if !d.isActive() {
		return
	}

	d.encoderMu.Lock()
	if hold, exists := d.encoderHolds[signal]; exists {
		if hold.releaseTimer != nil {
			hold.releaseTimer.Stop()
			hold.releaseTimer = nil
			if hold.stop == nil {
				hold.stop = make(chan struct{})
				go d.repeatEncoder(index, hold.stop)
			}
			d.encoderMu.Unlock()
			d.emitEncoder(index)
			return
		}
		d.encoderMu.Unlock()
		return
	}
	hold := &encoderHold{stop: make(chan struct{})}
	d.encoderHolds[signal] = hold
	d.encoderMu.Unlock()

	d.emitEncoder(index)
	go d.repeatEncoder(index, hold.stop)
}

func (d *daemon) repeatEncoder(index int, stop <-chan struct{}) {
	timer := time.NewTimer(encoderRepeatDelay)
	defer timer.Stop()

	select {
	case <-timer.C:
	case <-stop:
		return
	}
	select {
	case <-stop:
		return
	default:
	}

	ticker := time.NewTicker(encoderRepeatInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			select {
			case <-stop:
				return
			default:
			}
			d.emitEncoder(index)
		case <-stop:
			return
		}
	}
}

func (d *daemon) emitEncoder(index int) {
	direction := 1
	d.state.mu.Lock()
	if d.state.shift {
		direction = -1
	}
	d.state.mu.Unlock()

	if err := d.encoder(index, d.encoderDelta(direction)); err != nil {
		log.Printf("encoder layer index=%d failed: %v", index, err)
	}
}

func (d *daemon) encoderOff(signal string) {
	d.encoderMu.Lock()
	hold, exists := d.encoderHolds[signal]
	if !exists {
		d.encoderMu.Unlock()
		return
	}
	if hold.releaseTimer != nil {
		hold.releaseTimer.Stop()
	}
	d.stopEncoderRepeat(hold)
	var releaseTimer *time.Timer
	releaseTimer = time.AfterFunc(encoderReleaseGrace, func() {
		d.finishEncoderOff(signal, hold, releaseTimer)
	})
	hold.releaseTimer = releaseTimer
	d.encoderMu.Unlock()
}

func (d *daemon) finishEncoderOff(signal string, hold *encoderHold, releaseTimer *time.Timer) {
	d.encoderMu.Lock()
	current, exists := d.encoderHolds[signal]
	if !exists || current != hold || hold.releaseTimer != releaseTimer {
		d.encoderMu.Unlock()
		return
	}
	delete(d.encoderHolds, signal)
	hold.releaseTimer = nil
	d.stopEncoderRepeat(hold)
	d.encoderMu.Unlock()
}

func (d *daemon) stopAllEncoders() {
	d.encoderMu.Lock()
	holds := d.encoderHolds
	d.encoderHolds = make(map[string]*encoderHold)
	d.encoderMu.Unlock()

	for _, hold := range holds {
		if hold.releaseTimer != nil {
			hold.releaseTimer.Stop()
		}
		d.stopEncoderRepeat(hold)
	}
}

func (d *daemon) stopEncoderRepeat(hold *encoderHold) {
	if hold.stop == nil {
		return
	}
	close(hold.stop)
	hold.stop = nil
}

func (d *daemon) encoder(index, delta int) error {
	d.state.mu.Lock()
	bank := d.state.bank
	channel := d.state.channel
	d.state.mu.Unlock()

	controller := controllerForEncoder(bank, index)

	value := relativeCCValue(delta)
	if err := d.out.cc(channel, controller, value); err != nil {
		return err
	}
	log.Printf("encoder=%02d bank=%d channel=%d cc=%d delta=%d value=%d", index, bank+1, channel+1, controller, delta, value)
	return nil
}

func controllerForEncoder(bank, index int) int {
	controller := baseEncoderCC + bank*16 + index - 1
	if controller > 119 {
		return 119
	}
	return controller
}

func relativeCCValue(delta int) int {
	if delta > 63 {
		delta = 63
	}
	if delta < -63 {
		delta = -63
	}
	if delta >= 0 {
		return delta
	}
	return 128 + delta
}

func (d *daemon) padOn(signal string, index int) error {
	d.state.mu.Lock()
	if _, exists := d.state.held[signal]; exists {
		d.state.mu.Unlock()
		return nil
	}
	bank := d.state.bank
	channel := d.state.channel
	note := noteForPad(bank, index)
	held := heldNote{channel: channel, note: note, velocity: padVelocity}
	d.state.held[signal] = held
	d.state.mu.Unlock()

	if err := d.out.note(held.channel, held.note, held.velocity, true); err != nil {
		return err
	}
	if d.tft != nil && isLocalTFTMomentaryPadFlash(held.channel, held.note) {
		d.tft.setPad(held.channel, held.note, held.velocity)
	}
	log.Printf("pad=%02d note_on bank=%d channel=%d note=%d", index, bank+1, channel+1, note)
	return nil
}

func noteForPad(bank, index int) int {
	return basePadNote + bank*16 + index - 1
}

func isLocalTFTMomentaryPadFlash(channel, note int) bool {
	if !isLEDNote(note) {
		return false
	}
	noteInBank := (note - basePadNote) % 16
	if channel == 1 {
		return noteInBank == 0 || noteInBank == 1 || noteInBank >= 8
	}
	if channel == 8 {
		return noteInBank <= 4 || noteInBank == 9 || noteInBank >= 11
	}
	if channel == 9 {
		return noteInBank == 0 || noteInBank == 1 || noteInBank == 7 || noteInBank >= 8
	}
	// Daemon channels are zero-based; this is display/ReaLearn channel 11.
	if channel == 10 {
		return noteInBank <= 13
	}
	// Daemon channels are zero-based; this is display/ReaLearn channel 12.
	if channel == 11 {
		return noteInBank <= 3 || noteInBank == 5 || noteInBank == 6 || noteInBank >= 8
	}
	return false
}

func (d *daemon) padOff(signal string) error {
	d.state.mu.Lock()
	held, exists := d.state.held[signal]
	if exists {
		delete(d.state.held, signal)
	}
	d.state.mu.Unlock()
	if !exists {
		return nil
	}
	if err := d.out.note(held.channel, held.note, 0, false); err != nil {
		return err
	}
	log.Printf("note_off channel=%d note=%d", held.channel+1, held.note)
	return nil
}

func (d *daemon) transportToggle() error {
	d.state.mu.Lock()
	running := d.state.transportRunning
	d.state.transportRunning = !running
	d.state.mu.Unlock()
	d.refreshLocalLEDState()

	if running {
		log.Printf("transport stop")
		return d.out.realtime(midiEventStop())
	}
	log.Printf("transport start")
	return d.out.realtime(midiEventStart())
}

func (d *daemon) panic() error {
	if err := d.releaseHeldNotes(); err != nil {
		return err
	}

	for channel := 0; channel < 16; channel++ {
		if err := d.out.cc(channel, 123, 0); err != nil {
			return err
		}
		if err := d.out.cc(channel, 121, 0); err != nil {
			return err
		}
	}
	log.Printf("panic sent")
	d.allLEDsOff()
	d.setLED(ledPanicNote, ledRed)
	d.refreshLocalLEDState()
	return nil
}

func (d *daemon) runFeedbackLoop(in *feedbackMIDIIn) {
	for {
		ev, err := in.read()
		if err != nil {
			log.Printf("feedback read failed: %v", err)
			time.Sleep(time.Second)
			continue
		}
		d.handleFeedbackEvent(ev)
	}
}

func (d *daemon) handleFeedbackEvent(ev feedbackEvent) {
	switch ev.kind {
	case feedbackKindNote():
		velocity := ev.value
		if !ev.on {
			velocity = 0
		}
		d.applyFeedbackNote(ev.channel, ev.param, velocity)
	case feedbackKindCC():
		switch ev.param {
		case 120, 121, 123:
			// DAWs often send reset CC bursts on transport changes; treating them as
			// matrix clears delays the realtime play/stop LED feedback.
			return
		}
		if d.tft != nil {
			d.tft.setCC(ev.channel, ev.param, ev.value)
		}
	case feedbackKindRealtime():
		switch ev.eventType {
		case midiEventStart(), midiEventContinue():
			d.state.mu.Lock()
			d.state.transportRunning = true
			d.state.mu.Unlock()
			d.refreshLocalLEDState()
		case midiEventStop():
			d.state.mu.Lock()
			d.state.transportRunning = false
			d.state.mu.Unlock()
			d.refreshLocalLEDState()
		}
	}
}

func (d *daemon) applyFeedbackNote(channel, note, velocity int) {
	if !isLEDNote(note) {
		return
	}
	velocity = clampMIDIData(velocity)
	if d.tft != nil {
		d.tft.setPad(channel, note, velocity)
	}
	if d.led != nil {
		on := velocity > 0
		if err := d.led.note(0, note, velocity, on); err != nil {
			log.Printf("LED note=%d velocity=%d failed: %v", note, velocity, err)
		}
	}
}

func (d *daemon) applyFeedbackCC(channel, controller, value int) {
	if d.tft == nil {
		return
	}
	d.tft.setCC(channel, controller, value)
}

func (d *daemon) releaseHeldNotes() error {
	d.state.mu.Lock()
	held := make([]heldNote, 0, len(d.state.held))
	for _, note := range d.state.held {
		held = append(held, note)
	}
	d.state.held = make(map[string]heldNote)
	d.state.mu.Unlock()

	for _, note := range held {
		if err := d.out.note(note.channel, note.note, 0, false); err != nil {
			return err
		}
	}
	return nil
}

func (d *daemon) startControlSocket() error {
	socketPath := controlSocketPath()
	if err := os.MkdirAll(filepath.Dir(socketPath), 0o700); err != nil {
		return err
	}
	if err := os.Remove(socketPath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}

	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		return err
	}

	go func() {
		defer listener.Close()
		for {
			conn, err := listener.Accept()
			if err != nil {
				log.Printf("control socket closed: %v", err)
				return
			}
			go d.handleControlConn(conn)
		}
	}()

	log.Printf("control socket %s", socketPath)
	return nil
}

func (d *daemon) handleControlConn(conn net.Conn) {
	defer conn.Close()
	reader := bufio.NewReader(conn)
	command, err := reader.ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		fmt.Fprintf(conn, "error: %v\n", err)
		return
	}
	command = strings.TrimSpace(command)
	fields := strings.Fields(command)

	switch {
	case len(fields) == 0:
		fmt.Fprintln(conn, "error: empty command")
	case command == "toggle":
		active, err := d.toggleActive()
		if err != nil {
			fmt.Fprintf(conn, "error: %v\n", err)
			return
		}
		fmt.Fprintf(conn, "active=%t\n", active)
	case command == "enter":
		if err := d.setActive(true); err != nil {
			fmt.Fprintf(conn, "error: %v\n", err)
			return
		}
		fmt.Fprintln(conn, "active=true")
	case command == "exit":
		if err := d.setActive(false); err != nil {
			fmt.Fprintf(conn, "error: %v\n", err)
			return
		}
		fmt.Fprintln(conn, "active=false")
	case command == "panic":
		if err := d.panic(); err != nil {
			fmt.Fprintf(conn, "error: %v\n", err)
			return
		}
		fmt.Fprintln(conn, "ok")
	case command == "status":
		d.writeStatus(conn)
	case fields[0] == "feedback-note":
		if len(fields) != 4 {
			fmt.Fprintln(conn, "error: usage feedback-note CH NOTE VEL")
			return
		}
		channel, note, velocity, err := parseExternalFeedbackTriple(fields[1:])
		if err != nil {
			fmt.Fprintf(conn, "error: %v\n", err)
			return
		}
		d.applyFeedbackNote(channel, note, velocity)
		fmt.Fprintln(conn, "ok")
	case fields[0] == "feedback-cc":
		if len(fields) != 4 {
			fmt.Fprintln(conn, "error: usage feedback-cc CH CC VALUE")
			return
		}
		channel, controller, value, err := parseExternalFeedbackTriple(fields[1:])
		if err != nil {
			fmt.Fprintf(conn, "error: %v\n", err)
			return
		}
		d.applyFeedbackCC(channel, controller, value)
		fmt.Fprintln(conn, "ok")
	default:
		fmt.Fprintf(conn, "error: unknown command %q\n", command)
	}
}

func parseExternalFeedbackTriple(args []string) (int, int, int, error) {
	if len(args) != 3 {
		return 0, 0, 0, errors.New("expected three numeric arguments")
	}
	channel, err := strconv.Atoi(args[0])
	if err != nil || channel < 1 || channel > 16 {
		return 0, 0, 0, fmt.Errorf("channel must be 1-16, got %q", args[0])
	}
	param, err := strconv.Atoi(args[1])
	if err != nil || param < 0 || param > 127 {
		return 0, 0, 0, fmt.Errorf("MIDI parameter must be 0-127, got %q", args[1])
	}
	value, err := strconv.Atoi(args[2])
	if err != nil || value < 0 || value > 127 {
		return 0, 0, 0, fmt.Errorf("MIDI value must be 0-127, got %q", args[2])
	}
	return channel - 1, param, value, nil
}

func (d *daemon) toggleActive() (bool, error) {
	d.state.mu.Lock()
	next := !d.state.active
	d.state.mu.Unlock()
	if err := d.setActive(next); err != nil {
		return false, err
	}
	return next, nil
}

func (d *daemon) writeStatus(w io.Writer) {
	d.state.mu.Lock()
	status := map[string]any{
		"active":            d.state.active,
		"bank":              d.state.bank + 1,
		"channel":           d.state.channel + 1,
		"held_notes":        len(d.state.held),
		"transport_running": d.state.transportRunning,
		"alt_speed":         d.state.alt || d.state.altgr,
		"control_fine":      d.state.control,
		"bank_select":       d.state.bankSelect,
		"channel_select":    d.state.channelSelect,
		"tab_modifier":      d.state.tabAsModifier,
		"entry_select":      d.state.entrySelect,
		"client":            clientName,
		"port":              portName,
		"led_client":        ledClientName,
		"led_port":          ledPortName,
		"feedback_client":   feedbackClientName,
		"feedback_port":     feedbackPortName,
		"tft_serial_port":   d.tftSerialPort(),
		"outputs":           d.outputNames(),
	}
	d.state.mu.Unlock()

	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(status); err != nil {
		fmt.Fprintf(w, "error: %v\n", err)
	}
}

func (d *daemon) tftSerialPort() string {
	tft, ok := d.tft.(*serialTFTOutput)
	if !ok || tft == nil {
		return ""
	}
	tft.mu.Lock()
	defer tft.mu.Unlock()
	return tft.port
}

func (d *daemon) outputNames() []string {
	out, ok := d.out.(interface{ outputNames() []string })
	if !ok {
		return nil
	}
	return out.outputNames()
}

func sendCommand(command string) error {
	conn, err := net.Dial("unix", controlSocketPath())
	if err != nil {
		return err
	}
	defer conn.Close()

	if _, err := fmt.Fprintln(conn, command); err != nil {
		return err
	}
	_, err = io.Copy(os.Stdout, conn)
	return err
}

func controlSocketPath() string {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = os.TempDir()
	}
	return filepath.Join(runtimeDir, "keyboard-midi-controller", "control.sock")
}
