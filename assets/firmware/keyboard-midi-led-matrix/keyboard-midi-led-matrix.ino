#include <Adafruit_NeoPixel.h>
#include "MIDIUSB.h"

const uint8_t LED_PIN = 6;
const uint16_t NUM_LEDS = 64;
const uint8_t NOTE_BASE = 36;
const uint8_t BRIGHTNESS = 32;
const bool SERPENTINE = true;

Adafruit_NeoPixel pixels(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

uint16_t physicalPixel(uint8_t logicalPixel) {
  uint8_t row = logicalPixel / 8;
  uint8_t col = logicalPixel % 8;
  if (SERPENTINE && (row % 2 == 1)) {
    col = 7 - col;
  }
  return row * 8 + col;
}

uint32_t colorFromVelocity(uint8_t velocity) {
  if (velocity == 0) {
    return pixels.Color(0, 0, 0);
  }
  switch (velocity) {
    case 1: return pixels.Color(32, 0, 0);
    case 2: return pixels.Color(32, 12, 0);
    case 3: return pixels.Color(28, 28, 0);
    case 4: return pixels.Color(0, 32, 0);
    case 5: return pixels.Color(0, 24, 24);
    case 6: return pixels.Color(0, 0, 32);
    case 7: return pixels.Color(28, 0, 28);
    default: return pixels.Color(24, 24, 24);
  }
}

void allOff() {
  pixels.clear();
  pixels.show();
}

void setNoteLed(uint8_t note, uint8_t velocity) {
  if (note < NOTE_BASE || note >= NOTE_BASE + NUM_LEDS) {
    return;
  }
  uint8_t logicalPixel = note - NOTE_BASE;
  pixels.setPixelColor(physicalPixel(logicalPixel), colorFromVelocity(velocity));
  pixels.show();
}

void bootTest() {
  allOff();
  for (uint8_t i = 0; i < NUM_LEDS; i++) {
    pixels.setPixelColor(physicalPixel(i), pixels.Color(0, 8, 0));
    pixels.show();
    delay(8);
  }
  delay(150);
  allOff();
}

void handleMidi(midiEventPacket_t event) {
  uint8_t status = event.byte1 & 0xF0;
  uint8_t data1 = event.byte2;
  uint8_t data2 = event.byte3;

  switch (status) {
    case 0x80:
      setNoteLed(data1, 0);
      break;
    case 0x90:
      setNoteLed(data1, data2);
      break;
    case 0xB0:
      if (data1 == 120 || data1 == 121 || data1 == 123) {
        allOff();
      }
      break;
  }
}

void setup() {
  pixels.begin();
  pixels.setBrightness(BRIGHTNESS);
  bootTest();
}

void loop() {
  midiEventPacket_t event;
  do {
    event = MidiUSB.read();
    if (event.header != 0) {
      handleMidi(event);
    }
  } while (event.header != 0);
}
