#include <EEPROM.h>
#include "MIDIUSB.h"

// Pedalboard MIDI controller for Arduino Micro.
// Wiring:
//   every pedal sleeve -> GND
//   switch pedal 1 tip -> D2
//   switch pedal 2 tip -> D3
//   continuous damper tip -> A0
//
// Serial commands at 115200 baud:
//   status
//   profile piano
//   profile guitar
//   profile desktop
//
// Boot profile selection:
//   hold switch 1 while connecting USB -> guitar
//   hold switch 2 while connecting USB -> piano
//   hold both switches while connecting USB -> desktop

const uint8_t SWITCH_1_PIN = 2;
const uint8_t SWITCH_2_PIN = 3;
const uint8_t CONTINUOUS_PIN = A0;
const bool SWITCH_INPUT_INVERTED = true;

const int CONTINUOUS_RAW_MIN = 30;
const int CONTINUOUS_RAW_MAX = 480;
const bool CONTINUOUS_INVERT = false;

const uint8_t EEPROM_PROFILE_ADDR = 0;
const uint8_t PROFILE_MAGIC_ADDR = 1;
const uint8_t PROFILE_MAGIC = 0x42;

const uint16_t DEBOUNCE_MS = 18;
const uint16_t COMMAND_BUFFER_SIZE = 32;

enum SwitchMode {
  SWITCH_MOMENTARY,
  SWITCH_LATCH,
};

struct PedalMapping {
  const char *name;
  uint8_t channel;
  uint8_t continuousCC;
  uint8_t switch1CC;
  uint8_t switch2CC;
  SwitchMode switch1Mode;
  SwitchMode switch2Mode;
};

const PedalMapping PROFILES[] = {
    {"piano", 0, 64, 66, 67, SWITCH_MOMENTARY, SWITCH_MOMENTARY},
    {"guitar", 1, 4, 80, 81, SWITCH_LATCH, SWITCH_LATCH},
    {"desktop", 15, 4, 80, 81, SWITCH_MOMENTARY, SWITCH_MOMENTARY},
};

const uint8_t PROFILE_COUNT = sizeof(PROFILES) / sizeof(PROFILES[0]);

struct SwitchState {
  uint8_t pin;
  bool stablePressed;
  bool lastRawPressed;
  bool latchedOn;
  uint32_t lastRawChangeMs;
};

SwitchState switch1 = {SWITCH_1_PIN, false, false, false, 0};
SwitchState switch2 = {SWITCH_2_PIN, false, false, false, 0};

uint8_t profileIndex = 0;
int lastContinuousValue = -1;
char serialBuffer[COMMAND_BUFFER_SIZE];
uint8_t serialLength = 0;

void sendControlChange(uint8_t channel, uint8_t controller, uint8_t value) {
  midiEventPacket_t event = {0x0B, static_cast<uint8_t>(0xB0 | (channel & 0x0F)), controller, value};
  MidiUSB.sendMIDI(event);
  MidiUSB.flush();
}

int continuousValue() {
  int raw = analogRead(CONTINUOUS_PIN);
  raw = constrain(raw, CONTINUOUS_RAW_MIN, CONTINUOUS_RAW_MAX);

  long mapped = map(raw, CONTINUOUS_RAW_MIN, CONTINUOUS_RAW_MAX, 0, 127);
  if (CONTINUOUS_INVERT) {
    mapped = 127 - mapped;
  }
  return constrain(mapped, 0, 127);
}

bool switchPressed(uint8_t pin) {
  bool pulledLow = digitalRead(pin) == LOW;
  return SWITCH_INPUT_INVERTED ? !pulledLow : pulledLow;
}

void emitContinuousIfChanged(bool force) {
  const PedalMapping &profile = PROFILES[profileIndex];
  int value = continuousValue();
  if (!force && lastContinuousValue >= 0 && abs(value - lastContinuousValue) < 2) {
    return;
  }

  lastContinuousValue = value;
  sendControlChange(profile.channel, profile.continuousCC, value);
}

void emitSwitch(const PedalMapping &profile, uint8_t controller, SwitchMode mode, SwitchState &state, bool pressed) {
  if (mode == SWITCH_LATCH) {
    if (!pressed) {
      return;
    }
    state.latchedOn = !state.latchedOn;
    sendControlChange(profile.channel, controller, state.latchedOn ? 127 : 0);
    return;
  }

  sendControlChange(profile.channel, controller, pressed ? 127 : 0);
}

void updateSwitch(SwitchState &state, uint8_t controller, SwitchMode mode) {
  bool rawPressed = switchPressed(state.pin);
  uint32_t now = millis();

  if (rawPressed != state.lastRawPressed) {
    state.lastRawPressed = rawPressed;
    state.lastRawChangeMs = now;
  }

  if (now - state.lastRawChangeMs < DEBOUNCE_MS || rawPressed == state.stablePressed) {
    return;
  }

  state.stablePressed = rawPressed;
  emitSwitch(PROFILES[profileIndex], controller, mode, state, state.stablePressed);
}

void sendProfileState() {
  const PedalMapping &profile = PROFILES[profileIndex];
  sendControlChange(profile.channel, profile.continuousCC, lastContinuousValue < 0 ? continuousValue() : lastContinuousValue);
  sendControlChange(profile.channel, profile.switch1CC, switch1.latchedOn ? 127 : 0);
  sendControlChange(profile.channel, profile.switch2CC, switch2.latchedOn ? 127 : 0);
}

void saveProfile() {
  EEPROM.update(EEPROM_PROFILE_ADDR, profileIndex);
  EEPROM.update(PROFILE_MAGIC_ADDR, PROFILE_MAGIC);
}

void loadProfile() {
  if (EEPROM.read(PROFILE_MAGIC_ADDR) != PROFILE_MAGIC) {
    profileIndex = 0;
    return;
  }

  uint8_t stored = EEPROM.read(EEPROM_PROFILE_ADDR);
  if (stored < PROFILE_COUNT) {
    profileIndex = stored;
  }
}

void applyBootProfileOverride() {
  bool switch1Pressed = switchPressed(SWITCH_1_PIN);
  bool switch2Pressed = switchPressed(SWITCH_2_PIN);

  if (switch1Pressed && switch2Pressed) {
    profileIndex = 2;
    saveProfile();
    return;
  }
  if (switch1Pressed) {
    profileIndex = 1;
    saveProfile();
    return;
  }
  if (switch2Pressed) {
    profileIndex = 0;
    saveProfile();
  }
}

void printStatus() {
  const PedalMapping &profile = PROFILES[profileIndex];
  Serial.print("profile=");
  Serial.print(profile.name);
  Serial.print(" channel=");
  Serial.print(profile.channel + 1);
  Serial.print(" continuous_cc=");
  Serial.print(profile.continuousCC);
  Serial.print(" switch1_cc=");
  Serial.print(profile.switch1CC);
  Serial.print(" switch2_cc=");
  Serial.print(profile.switch2CC);
  Serial.print(" raw=");
  Serial.print(analogRead(CONTINUOUS_PIN));
  Serial.print(" value=");
  Serial.println(continuousValue());
}

bool setProfileByName(const char *name) {
  for (uint8_t i = 0; i < PROFILE_COUNT; i++) {
    if (strcmp(name, PROFILES[i].name) == 0) {
      profileIndex = i;
      switch1.latchedOn = false;
      switch2.latchedOn = false;
      lastContinuousValue = -1;
      saveProfile();
      sendProfileState();
      printStatus();
      return true;
    }
  }
  return false;
}

void handleSerialLine(char *line) {
  while (*line == ' ' || *line == '\t') {
    line++;
  }

  if (strcmp(line, "status") == 0) {
    printStatus();
    return;
  }

  const char prefix[] = "profile ";
  if (strncmp(line, prefix, sizeof(prefix) - 1) == 0) {
    if (!setProfileByName(line + sizeof(prefix) - 1)) {
      Serial.println("error: unknown profile");
    }
    return;
  }

  if (*line != '\0') {
    Serial.println("error: expected status or profile <piano|guitar|desktop>");
  }
}

void pollSerial() {
  while (Serial.available() > 0) {
    char ch = static_cast<char>(Serial.read());
    if (ch == '\r') {
      continue;
    }
    if (ch == '\n') {
      serialBuffer[serialLength] = '\0';
      handleSerialLine(serialBuffer);
      serialLength = 0;
      continue;
    }
    if (serialLength < COMMAND_BUFFER_SIZE - 1) {
      serialBuffer[serialLength++] = ch;
    }
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(SWITCH_1_PIN, INPUT_PULLUP);
  pinMode(SWITCH_2_PIN, INPUT_PULLUP);
  pinMode(CONTINUOUS_PIN, INPUT_PULLUP);

  loadProfile();
  delay(200);
  applyBootProfileOverride();
  delay(50);
  emitContinuousIfChanged(true);
  printStatus();
}

void loop() {
  const PedalMapping &profile = PROFILES[profileIndex];
  pollSerial();
  updateSwitch(switch1, profile.switch1CC, profile.switch1Mode);
  updateSwitch(switch2, profile.switch2CC, profile.switch2Mode);
  emitContinuousIfChanged(false);
  delay(5);
}
