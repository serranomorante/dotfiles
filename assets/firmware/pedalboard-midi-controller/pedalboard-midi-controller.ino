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
//   range <zero_percent> <full_percent>
//   range reset
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
const uint8_t CONTINUOUS_DEFAULT_ZERO_PERCENT = 15;
const uint8_t CONTINUOUS_DEFAULT_FULL_PERCENT = 60;
const uint8_t CONTINUOUS_MIN_RANGE_PERCENT = 5;
const uint8_t CONTINUOUS_SAMPLE_COUNT = 8;
const uint8_t CONTINUOUS_EMIT_DEADBAND = 2;
const uint8_t CONTINUOUS_REVERSAL_THRESHOLD = 6;
const uint8_t CONTINUOUS_REVERSAL_CONFIRMATIONS = 3;
const uint8_t CONTINUOUS_MAX_STEP = 4;
const uint8_t CONTINUOUS_ENDPOINT_DEADBAND = 2;

const uint8_t EEPROM_PROFILE_ADDR = 0;
const uint8_t PROFILE_MAGIC_ADDR = 1;
const uint8_t PROFILE_MAGIC = 0x42;
const uint8_t RANGE_MAGIC_ADDR = 2;
const uint8_t RANGE_ZERO_ADDR = 3;
const uint8_t RANGE_FULL_ADDR = 4;
const uint8_t RANGE_MAGIC = 0x52;

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
uint8_t continuousZeroPercent = CONTINUOUS_DEFAULT_ZERO_PERCENT;
uint8_t continuousFullPercent = CONTINUOUS_DEFAULT_FULL_PERCENT;
int lastContinuousValue = -1;
int filteredContinuousValue = -1;
int continuousDirection = 0;
int continuousReversalCandidate = -1;
uint8_t continuousReversalCount = 0;
char serialBuffer[COMMAND_BUFFER_SIZE];
uint8_t serialLength = 0;

void sendControlChange(uint8_t channel, uint8_t controller, uint8_t value) {
  midiEventPacket_t event = {0x0B, static_cast<uint8_t>(0xB0 | (channel & 0x0F)), controller, value};
  MidiUSB.sendMIDI(event);
  MidiUSB.flush();
}

void resetContinuousFilter() {
  lastContinuousValue = -1;
  filteredContinuousValue = -1;
  continuousDirection = 0;
  continuousReversalCandidate = -1;
  continuousReversalCount = 0;
}

int continuousRawValue() {
  long total = 0;
  for (uint8_t i = 0; i < CONTINUOUS_SAMPLE_COUNT; i++) {
    total += analogRead(CONTINUOUS_PIN);
  }

  int raw = static_cast<int>((total + (CONTINUOUS_SAMPLE_COUNT / 2)) / CONTINUOUS_SAMPLE_COUNT);
  return constrain(raw, CONTINUOUS_RAW_MIN, CONTINUOUS_RAW_MAX);
}

int rawForPercent(uint8_t percent) {
  percent = constrain(percent, 0, 100);
  long raw = CONTINUOUS_RAW_MIN + ((static_cast<long>(CONTINUOUS_RAW_MAX - CONTINUOUS_RAW_MIN) * percent) / 100);
  return constrain(raw, CONTINUOUS_RAW_MIN, CONTINUOUS_RAW_MAX);
}

int continuousMappedValue() {
  int raw = continuousRawValue();
  int zeroRaw = rawForPercent(continuousZeroPercent);
  int fullRaw = rawForPercent(continuousFullPercent);

  if (raw <= zeroRaw) {
    return 0;
  }
  if (raw >= fullRaw) {
    return 127;
  }

  long mapped = map(raw, zeroRaw, fullRaw, 0, 127);
  if (CONTINUOUS_INVERT) {
    mapped = 127 - mapped;
  }
  int value = constrain(mapped, 0, 127);
  if (value <= CONTINUOUS_ENDPOINT_DEADBAND) {
    return 0;
  }
  if (value >= 127 - CONTINUOUS_ENDPOINT_DEADBAND) {
    return 127;
  }
  return value;
}

int stepContinuousToward(int current, int target) {
  int delta = target - current;
  if (abs(delta) <= CONTINUOUS_MAX_STEP) {
    return target;
  }
  return current + (delta > 0 ? CONTINUOUS_MAX_STEP : -CONTINUOUS_MAX_STEP);
}

int continuousValue() {
  int value = continuousMappedValue();
  if (filteredContinuousValue < 0) {
    filteredContinuousValue = value;
    return filteredContinuousValue;
  }

  if (value == 0 || value == 127) {
    continuousDirection = 0;
    filteredContinuousValue = value;
    continuousReversalCandidate = -1;
    continuousReversalCount = 0;
    return filteredContinuousValue;
  }

  int delta = value - filteredContinuousValue;
  if (delta == 0) {
    return filteredContinuousValue;
  }

  int nextDirection = delta > 0 ? 1 : -1;
  if (continuousDirection == 0 || nextDirection == continuousDirection) {
    filteredContinuousValue = stepContinuousToward(filteredContinuousValue, value);
    continuousDirection = nextDirection;
    continuousReversalCandidate = -1;
    continuousReversalCount = 0;
    return filteredContinuousValue;
  }

  bool strongerReversal = continuousReversalCandidate < 0 ||
                          (nextDirection > 0 && value > continuousReversalCandidate) ||
                          (nextDirection < 0 && value < continuousReversalCandidate);
  if (strongerReversal) {
    continuousReversalCandidate = value;
    continuousReversalCount = 1;
  } else {
    continuousReversalCount++;
  }

  if (abs(continuousReversalCandidate - filteredContinuousValue) >= CONTINUOUS_REVERSAL_THRESHOLD &&
      continuousReversalCount >= CONTINUOUS_REVERSAL_CONFIRMATIONS) {
    filteredContinuousValue = stepContinuousToward(filteredContinuousValue, continuousReversalCandidate);
    continuousDirection = nextDirection;
    continuousReversalCandidate = -1;
    continuousReversalCount = 0;
  }

  return filteredContinuousValue;
}

bool switchPressed(uint8_t pin) {
  bool pulledLow = digitalRead(pin) == LOW;
  return SWITCH_INPUT_INVERTED ? !pulledLow : pulledLow;
}

void emitContinuousIfChanged(bool force) {
  const PedalMapping &profile = PROFILES[profileIndex];
  int value = continuousValue();
  if (!force && lastContinuousValue >= 0 && abs(value - lastContinuousValue) < CONTINUOUS_EMIT_DEADBAND) {
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

bool validContinuousRange(uint8_t zeroPercent, uint8_t fullPercent) {
  return zeroPercent < fullPercent && fullPercent <= 100 && fullPercent - zeroPercent >= CONTINUOUS_MIN_RANGE_PERCENT;
}

void saveContinuousRange() {
  EEPROM.update(RANGE_MAGIC_ADDR, RANGE_MAGIC);
  EEPROM.update(RANGE_ZERO_ADDR, continuousZeroPercent);
  EEPROM.update(RANGE_FULL_ADDR, continuousFullPercent);
}

void loadContinuousRange() {
  if (EEPROM.read(RANGE_MAGIC_ADDR) != RANGE_MAGIC) {
    continuousZeroPercent = CONTINUOUS_DEFAULT_ZERO_PERCENT;
    continuousFullPercent = CONTINUOUS_DEFAULT_FULL_PERCENT;
    saveContinuousRange();
    return;
  }

  uint8_t zeroPercent = EEPROM.read(RANGE_ZERO_ADDR);
  uint8_t fullPercent = EEPROM.read(RANGE_FULL_ADDR);
  if (!validContinuousRange(zeroPercent, fullPercent)) {
    continuousZeroPercent = CONTINUOUS_DEFAULT_ZERO_PERCENT;
    continuousFullPercent = CONTINUOUS_DEFAULT_FULL_PERCENT;
    saveContinuousRange();
    return;
  }

  continuousZeroPercent = zeroPercent;
  continuousFullPercent = fullPercent;
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
  Serial.print(" range_zero=");
  Serial.print(continuousZeroPercent);
  Serial.print(" range_full=");
  Serial.print(continuousFullPercent);
  Serial.print(" raw=");
  Serial.print(continuousRawValue());
  Serial.print(" value=");
  Serial.println(continuousValue());
}

bool setProfileByName(const char *name) {
  for (uint8_t i = 0; i < PROFILE_COUNT; i++) {
    if (strcmp(name, PROFILES[i].name) == 0) {
      profileIndex = i;
      switch1.latchedOn = false;
      switch2.latchedOn = false;
      resetContinuousFilter();
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

  const char rangePrefix[] = "range ";
  if (strncmp(line, rangePrefix, sizeof(rangePrefix) - 1) == 0) {
    char *args = line + sizeof(rangePrefix) - 1;
    if (strcmp(args, "reset") == 0) {
      continuousZeroPercent = CONTINUOUS_DEFAULT_ZERO_PERCENT;
      continuousFullPercent = CONTINUOUS_DEFAULT_FULL_PERCENT;
      resetContinuousFilter();
      saveContinuousRange();
      sendProfileState();
      printStatus();
      return;
    }

    char *space = strchr(args, ' ');
    if (space == NULL) {
      Serial.println("error: expected range <zero_percent> <full_percent>");
      return;
    }

    *space = '\0';
    int zeroInput = atoi(args);
    int fullInput = atoi(space + 1);
    if (zeroInput < 0 || zeroInput > 100 || fullInput < 0 || fullInput > 100) {
      Serial.println("error: range values must be 0..100");
      return;
    }

    uint8_t zeroPercent = static_cast<uint8_t>(zeroInput);
    uint8_t fullPercent = static_cast<uint8_t>(fullInput);
    if (!validContinuousRange(zeroPercent, fullPercent)) {
      Serial.println("error: invalid range; expected zero < full and gap >= 5");
      return;
    }

    continuousZeroPercent = zeroPercent;
    continuousFullPercent = fullPercent;
    resetContinuousFilter();
    saveContinuousRange();
    sendProfileState();
    printStatus();
    return;
  }

  if (*line != '\0') {
    Serial.println("error: expected status, profile <piano|guitar|desktop>, range <zero> <full>, or range reset");
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
  loadContinuousRange();
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
