#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h>

// Keyboard MIDI TFT display renderer.
// Wiring target: ESP32-S3 DevKitC-1 + 2.8 inch ILI9341 SPI TFT.
// Serial protocol from keyboard-midi-controller:
//   S <active> <channel> <bank> <transport_running>
//   N <note> <velocity>
//   P <channel> <note> <velocity>
//   K <channel> <cc> <value>
//   C

const uint8_t TFT_CS = 10;
const uint8_t TFT_DC = 9;
const uint8_t TFT_RST = 14;
const uint8_t TFT_SCK = 12;
const uint8_t TFT_MOSI = 11;
const uint8_t TFT_MISO = 13;

const uint8_t NOTE_BASE = 36;
const uint8_t NOTE_COUNT = 64;
const uint8_t CC_BASE = 10;
const uint8_t MIDI_EDITOR_GRID_CC = 90;
const uint8_t TRACK_COUNT = 8;
const uint8_t MON_OFF_MAX = 42;
const uint8_t MON_ON_MAX = 84;
const uint16_t FLASH_DURATION_MS = 180;

Adafruit_ILI9341 tft(&SPI, TFT_DC, TFT_CS, TFT_RST);

uint8_t noteValues[16][NOTE_COUNT];
uint32_t noteFlashUntil[16][NOTE_COUNT];
uint8_t ccValues[16][128];
bool ccKnown[16][128];
bool midiModeActive = false;
bool transportRunning = false;
uint8_t currentChannel = 1;
uint8_t currentBank = 1;
bool fullRedraw = true;
bool headerTopDirty = false;
bool midiEditorGridHeaderDirty = false;
bool midiEditorGridTypeHeaderDirty = false;
bool midiEditorSnapHeaderDirty = false;
bool badgeDirty[5];
bool tileDirty[4][8];

char serialLine[48];
uint8_t serialLineLength = 0;

const char *keys[4][8] = {
    {"1", "2", "3", "4", "5", "6", "7", "8"},
    {"q", "w", "e", "r", "t", "y", "u", "i"},
    {"a", "s", "d", "f", "g", "h", "j", "k"},
    {"z", "x", "c", "v", "b", "n", "m", ","},
};

enum BadgeIndex {
  BADGE_PLAY = 0,
  BADGE_REC = 1,
  BADGE_LOOP = 2,
  BADGE_METR = 3,
  BADGE_MIDI = 4,
};

const char *channelContext() {
  switch (currentChannel) {
    case 1:
      return "Mixer";
    case 2:
      return "Selected";
    case 3:
      return currentBank == 2 ? "FX" : "Sends";
    case 9:
      return "Grid";
    case 10:
      return "Transport";
    case 11:
      return "Markers";
    case 12:
      return "Items";
    case 16:
      return "Global";
    default:
      return "Custom";
  }
}

uint16_t dimColor(uint16_t color) {
  uint8_t r = ((color >> 11) & 0x1F) / 4;
  uint8_t g = ((color >> 5) & 0x3F) / 4;
  uint8_t b = (color & 0x1F) / 4;
  return (r << 11) | (g << 5) | b;
}

uint16_t foregroundColor(uint16_t color, bool active) {
  if (!active) {
    return ILI9341_WHITE;
  }
  switch (color) {
    case ILI9341_GREEN:
    case ILI9341_CYAN:
    case ILI9341_YELLOW:
    case ILI9341_WHITE:
      return ILI9341_BLACK;
    default:
      return ILI9341_WHITE;
  }
}

uint8_t noteValue(uint8_t note) {
  if (note < NOTE_BASE || note >= NOTE_BASE + NOTE_COUNT) {
    return 0;
  }
  return noteValues[currentChannel - 1][note - NOTE_BASE];
}

bool noteOn(uint8_t note) {
  return noteValue(note) > 0;
}

uint8_t padNote(uint8_t padRow, uint8_t col) {
  return NOTE_BASE + (currentBank - 1) * 16 + padRow * TRACK_COUNT + col;
}

bool isSelectedTrackMonitorNote(uint8_t note) {
  return currentChannel == 2 && note == padNote(0, 5);
}

bool isSelectedTrackMonitorNoteForChannel(uint8_t channel, uint8_t note) {
  uint8_t bankNote = NOTE_BASE + (currentBank - 1) * 16 + 5;
  return channel == 2 && note == bankNote;
}

bool isMomentaryPadFlashNote(uint8_t channel, uint8_t note) {
  if (note < NOTE_BASE || note >= NOTE_BASE + NOTE_COUNT) {
    return false;
  }
  uint8_t noteInBank = (note - NOTE_BASE) % 16;
  if (channel == 2) {
    return noteInBank == 0 || noteInBank == 1 || noteInBank >= 8;
  }
  if (channel == 9) {
    return noteInBank <= 4 || noteInBank == 9 || noteInBank >= 11;
  }
  if (channel == 10) {
    return noteInBank == 0 || noteInBank == 1 || noteInBank == 7 || noteInBank >= 8;
  }
  if (channel == 11) {
    return noteInBank <= 13;
  }
  if (channel == 12) {
    return noteInBank <= 3 || noteInBank == 5 || noteInBank == 6 || noteInBank >= 8;
  }
  return false;
}

uint8_t monitorModeFromValue(uint8_t value) {
  if (value <= MON_OFF_MAX) {
    return 0;
  }
  if (value <= MON_ON_MAX) {
    return 1;
  }
  return 2;
}

uint8_t encoderCC(uint8_t row, uint8_t col) {
  return CC_BASE + (currentBank - 1) * 16 + row * TRACK_COUNT + col;
}

void drawBadge(int16_t x, const char *text, uint16_t color, bool active) {
  uint16_t bg = active ? color : dimColor(color);
  uint16_t fg = foregroundColor(color, active);
  tft.fillRect(x, 32, 43, 16, bg);
  tft.drawRect(x, 32, 43, 16, ILI9341_BLACK);
  tft.setTextColor(fg, bg);
  tft.setTextSize(1);
  tft.setCursor(x + 5, 36);
  tft.print(text);
}

void drawHeaderTop() {
  uint16_t headerColor = ILI9341_NAVY;
  tft.fillRect(0, 0, 320, 31, headerColor);
  tft.setTextColor(ILI9341_WHITE, headerColor);

  if (currentChannel == 9) {
    tft.setTextSize(1);
    tft.setCursor(6, 5);
    tft.print("Ch 9 Grid | ");
    drawMidiEditorGridHeaderValue();
    drawMidiEditorSnapHeaderValue();
    return;
  }

  tft.setTextSize(2);
  tft.setCursor(6, 7);
  tft.print("Ch ");
  tft.print(currentChannel);
  tft.print(" ");
  tft.print(channelContext());
  tft.print(" | B");
  tft.print(currentBank);
}

void drawMidiEditorGridHeaderValue() {
  uint16_t headerColor = ILI9341_NAVY;
  tft.fillRect(78, 0, 242, 16, headerColor);
  tft.setTextColor(ILI9341_WHITE, headerColor);
  tft.setTextSize(1);
  tft.setCursor(78, 5);
  tft.print(midiEditorGridLabel());
  tft.print(" ");
  tft.print(midiEditorGridTypeLabel());
}

void drawMidiEditorSnapHeaderValue() {
  uint16_t headerColor = ILI9341_NAVY;
  tft.fillRect(6, 16, 80, 15, headerColor);
  tft.setTextColor(ILI9341_WHITE, headerColor);
  tft.setTextSize(1);
  tft.setCursor(6, 18);
  tft.print("Snap ");
  tft.print(noteOn(padNote(1, 2)) ? "ON" : "OFF");
}

const char *midiEditorGridLabel() {
  uint8_t channelIndex = 8;
  if (!ccKnown[channelIndex][MIDI_EDITOR_GRID_CC]) {
    return "?";
  }
  switch (ccValues[channelIndex][MIDI_EDITOR_GRID_CC]) {
    case 1:
      return "MEASURE";
    case 2:
      return "1";
    case 3:
      return "1/2";
    case 4:
      return "1/4";
    case 5:
      return "1/8";
    case 6:
      return "1/16";
    case 7:
      return "1/32";
    case 8:
      return "1/64";
    case 9:
      return "1/128";
    case 10:
      return "1/256";
    case 11:
      return "1/512";
    case 12:
      return "1/1024";
    case 13:
      return "1/2048";
    case 14:
      return "1/4096";
    case 15:
      return "1/8192";
    case 16:
      return "1/16384";
    case 17:
      return "1/32768";
    case 20:
      return "1/3";
    case 21:
      return "1/6";
    case 22:
      return "1/12";
    case 23:
      return "1/24";
    case 24:
      return "1/48";
    case 25:
      return "1/96";
    default:
      return "?";
  }
}

const char *midiEditorGridTypeLabel() {
  if (noteOn(padNote(0, 6))) {
    return "Triplet";
  }
  if (noteOn(padNote(0, 5))) {
    return "Straight";
  }
  return "Type ?";
}

void drawBadgeStripBackground() {
  tft.fillRect(0, 31, 320, 19, ILI9341_BLACK);
  tft.setTextColor(ILI9341_LIGHTGREY, ILI9341_BLACK);
  tft.setTextSize(1);
  tft.setCursor(245, 36);
  tft.print("36-99");
}

void drawBadgeByIndex(uint8_t badge) {
  switch (badge) {
    case BADGE_PLAY:
      drawBadge(5, "PLAY", ILI9341_GREEN, transportRunning || noteOn(92));
      break;
    case BADGE_REC:
      drawBadge(52, "REC", ILI9341_RED, noteOn(93));
      break;
    case BADGE_LOOP:
      drawBadge(99, "LOOP", ILI9341_CYAN, noteOn(94));
      break;
    case BADGE_METR:
      drawBadge(146, "METR", ILI9341_PURPLE, noteOn(95));
      break;
    case BADGE_MIDI:
      drawBadge(193, "MIDI", ILI9341_BLUE, midiModeActive || noteOn(99));
      break;
  }
}

void drawHeader() {
  drawHeaderTop();
  drawBadgeStripBackground();
  for (uint8_t badge = 0; badge < 5; badge++) {
    drawBadgeByIndex(badge);
  }
}

uint16_t colorForChannel2(uint8_t row, uint8_t col) {
  if (row == 0) {
    const uint16_t colors[8] = {ILI9341_GREEN, ILI9341_CYAN, ILI9341_BLUE, ILI9341_GREEN, ILI9341_DARKGREY, ILI9341_DARKGREY, ILI9341_DARKGREY, ILI9341_DARKGREY};
    return colors[col];
  }
  if (row == 1) {
    return col < 4 ? ILI9341_CYAN : ILI9341_DARKGREY;
  }
  if (row == 2) {
    const uint16_t colors[8] = {ILI9341_BLUE, ILI9341_BLUE, ILI9341_RED, ILI9341_YELLOW, ILI9341_RED, ILI9341_GREEN, ILI9341_PURPLE, ILI9341_PURPLE};
    return colors[col];
  }
  const uint16_t colors[8] = {ILI9341_WHITE, ILI9341_WHITE, ILI9341_BLUE, ILI9341_BLUE, ILI9341_ORANGE, ILI9341_CYAN, ILI9341_GREEN, ILI9341_WHITE};
  return colors[col];
}

uint16_t colorForGrid(uint8_t row, uint8_t col) {
  if (row < 2) {
    return ILI9341_DARKGREY;
  }
  if (row == 3 && (col == 5 || col == 6)) {
    return ILI9341_BLUE;
  }
  if (row == 3 && col == 7) {
    return ILI9341_RED;
  }
  if (row == 3 && col == 2) {
    return ILI9341_GREEN;
  }
  return ILI9341_CYAN;
}

uint16_t colorForTransport(uint8_t row, uint8_t col) {
  if (row < 2) {
    return ILI9341_DARKGREY;
  }
  if (row == 2) {
    const uint16_t colors[8] = {ILI9341_BLUE, ILI9341_WHITE, ILI9341_GREEN, ILI9341_RED, ILI9341_GREEN, ILI9341_YELLOW, ILI9341_YELLOW, ILI9341_YELLOW};
    return colors[col];
  }
  const uint16_t colors[8] = {ILI9341_BLUE, ILI9341_BLUE, ILI9341_WHITE, ILI9341_WHITE, ILI9341_WHITE, ILI9341_CYAN, ILI9341_BLUE, ILI9341_WHITE};
  return colors[col];
}

uint16_t colorForMarkers(uint8_t row, uint8_t col) {
  if (row < 2) {
    return ILI9341_DARKGREY;
  }
  if (row == 2) {
    return col < 5 ? ILI9341_BLUE : ILI9341_ORANGE;
  }
  if (col <= 2 || col == 4 || col == 5) {
    return ILI9341_BLUE;
  }
  return ILI9341_ORANGE;
}

uint16_t colorForItems(uint8_t row, uint8_t col) {
  if (row < 2) {
    return ILI9341_DARKGREY;
  }
  if ((row == 2 && col == 4) || (row == 3 && (col == 3 || col == 7))) {
    return ILI9341_RED;
  }
  if ((row == 2 && col == 7) || (row == 3 && col == 1)) {
    return ILI9341_YELLOW;
  }
  if (row == 3 && col == 2) {
    return ILI9341_BLUE;
  }
  return ILI9341_ORANGE;
}

uint16_t colorForGlobal(uint8_t row, uint8_t col) {
  if (row < 2) {
    return ILI9341_DARKGREY;
  }
  if (row == 2 && (col == 0 || col == 4 || col == 5)) {
    return ILI9341_RED;
  }
  if (row == 2 && col == 7) {
    return ILI9341_CYAN;
  }
  if (row == 3 && col == 0) {
    return ILI9341_PURPLE;
  }
  return ILI9341_WHITE;
}

uint16_t tileBaseColor(uint8_t row, uint8_t col) {
  switch (currentChannel) {
    case 1:
      switch (row) {
        case 0:
          return ILI9341_GREEN;
        case 1:
          return ILI9341_CYAN;
        case 2:
          return ILI9341_RED;
        case 3:
          return ILI9341_YELLOW;
      }
      break;
    case 2:
      return colorForChannel2(row, col);
    case 3:
      if (currentBank == 2) {
        if (row < 2) {
          return ILI9341_PURPLE;
        }
        return row == 2 ? ILI9341_RED : ILI9341_PURPLE;
      }
      switch (row) {
        case 0:
          return ILI9341_GREEN;
        case 1:
          return ILI9341_CYAN;
        case 2:
          return ILI9341_RED;
        case 3:
          return ILI9341_ORANGE;
      }
      break;
    case 9:
      return colorForGrid(row, col);
    case 10:
      return colorForTransport(row, col);
    case 11:
      return colorForMarkers(row, col);
    case 12:
      return colorForItems(row, col);
    case 16:
      return colorForGlobal(row, col);
  }
  return ILI9341_DARKGREY;
}

bool tileAssigned(uint8_t row, uint8_t col) {
  switch (currentChannel) {
    case 1:
      return true;
    case 2:
      return row > 1 || (row == 0 && col < 4) || (row == 1 && col < 4);
    case 3:
      return true;
    case 9:
    case 10:
    case 11:
    case 16:
      return row > 1;
    case 12:
      return row > 1;
    default:
      return false;
  }
}

bool tileActive(uint8_t row, uint8_t col) {
  if (!tileAssigned(row, col)) {
    return false;
  }
  if (currentChannel == 2 && row == 2 && col == 5) {
    return monitorModeFromValue(noteValue(padNote(0, col))) > 0;
  }
  if (row == 2) {
    return noteOn(padNote(0, col));
  }
  if (row == 3) {
    return noteOn(padNote(1, col));
  }
  return false;
}

void formatPercentValue(uint8_t value, char *out, size_t outSize) {
  snprintf(out, outSize, "%u%%", (uint16_t)value * 100 / 127);
}

void formatPanValue(uint8_t value, char *out, size_t outSize) {
  if (value >= 62 && value <= 66) {
    snprintf(out, outSize, "C");
  } else if (value < 64) {
    snprintf(out, outSize, "L%u", (uint16_t)(64 - value) * 100 / 64);
  } else {
    snprintf(out, outSize, "R%u", (uint16_t)(value - 64) * 100 / 63);
  }
}

void tileLabel(uint8_t row, uint8_t col, char *out, size_t outSize) {
  out[0] = '\0';

  if (currentChannel == 1) {
    const char *rowLabels[4] = {"VOL", "PAN", "MUTE", "SOLO"};
    snprintf(out, outSize, "%s", rowLabels[row]);
    return;
  }

  if (currentChannel == 2) {
    const char *labels[4][8] = {
        {"VOL", "PAN", "WIDTH", "TRIM", "", "", "", ""},
        {"S1VOL", "S2VOL", "S3VOL", "S4VOL", "", "", "", ""},
        {"PREV", "NEXT", "MUTE", "SOLO", "ARM", "MON", "FX", "BYP"},
        {"NEW", "DUP", "FREEZ", "UNFRZ", "ITEMS", "ROUTE", "ENV", "NAME"},
    };
    snprintf(out, outSize, "%s", labels[row][col]);
    return;
  }

  if (currentChannel == 3 && currentBank == 2) {
    if (row == 0) {
      snprintf(out, outSize, "P%u", col + 1);
    } else if (row == 1) {
      snprintf(out, outSize, "P%u", col + 9);
    } else if (row == 2) {
      snprintf(out, outSize, "FX%uB", col + 1);
    } else {
      snprintf(out, outSize, "FX%uO", col + 1);
    }
    return;
  }

  if (currentChannel == 3) {
    if (row == 0) {
      snprintf(out, outSize, "S%uVOL", col + 1);
    } else if (row == 1) {
      snprintf(out, outSize, "S%uPAN", col + 1);
    } else if (row == 2) {
      snprintf(out, outSize, "S%uMUT", col + 1);
    } else {
      snprintf(out, outSize, "S%uOPN", col + 1);
    }
    return;
  }

  if (currentChannel == 9) {
    const char *labels[4][8] = {
        {"", "", "", "", "", "", "", ""},
        {"", "", "", "", "", "", "", ""},
        {"/2", "/3", "x2", "x3", "LEN", "STR", "TRIP", "GRID1"},
        {"MEAS", "QUANT", "SNAP", "HUMAN", "LEGAT", "-1ST", "+1ST", "DEL"},
    };
    snprintf(out, outSize, "%s", labels[row][col]);
    return;
  }

  if (currentChannel == 10) {
    const char *labels[4][8] = {
        {"", "", "", "", "", "", "", ""},
        {"", "", "", "", "", "", "", ""},
        {"START", "STOP", "PLAY", "REC", "LOOP", "METRO", "COUNT", "TAP"},
        {"PREV", "NEXT", "UNDO", "REDO", "SAVE", "MIXER", "FOCUS", "ACTNS"},
    };
    snprintf(out, outSize, "%s", labels[row][col]);
    return;
  }

  if (currentChannel == 11) {
    const char *labels[4][8] = {
        {"", "", "", "", "", "", "", ""},
        {"", "", "", "", "", "", "", ""},
        {"PMKR", "NMKR", "ADDMK", "EDIT", "DELMK", "ADREG", "PREG", "NREG"},
        {"TSST", "TSEND", "CLRTS", "SELRG", "START", "END", "RNDR", "MGR"},
    };
    snprintf(out, outSize, "%s", labels[row][col]);
    return;
  }

  if (currentChannel == 12) {
    const char *labels[4][8] = {
        {"", "", "", "", "", "", "", ""},
        {"", "", "", "", "", "", "", ""},
        {"SPLIT", "GLUE", "TRIM L", "TRIM R", "MUTE", "PROPS", "NORM", "LOCK"},
        {"ADD L", "ONE L", "COMP", "DEL L", "FADEI", "FADEO", "DUP", "REMOVE"},
    };
    snprintf(out, outSize, "%s", labels[row][col]);
    return;
  }

  if (currentChannel == 16) {
    const char *labels[4][8] = {
        {"", "", "", "", "", "", "", ""},
        {"", "", "", "", "", "", "", ""},
        {"PANIC", "UNMUT", "UNSOL", "UNARM", "BYPFX", "MSTRM", "SAVE", "PERF"},
        {"CLSFX", "MIXER", "NAV", "MEDIA", "ROUTE", "TRKMG", "BAY", "ACTNS"},
    };
    snprintf(out, outSize, "%s", labels[row][col]);
  }
}

void tileValue(uint8_t row, uint8_t col, char *out, size_t outSize) {
  uint8_t track = (currentBank - 1) * TRACK_COUNT + col + 1;
  uint8_t channelIndex = currentChannel - 1;

  if (!tileAssigned(row, col)) {
    snprintf(out, outSize, "");
    return;
  }

  if (currentChannel == 1) {
    if (row == 0) {
      uint8_t cc = encoderCC(row, col);
      if (ccKnown[channelIndex][cc]) {
        formatPercentValue(ccValues[channelIndex][cc], out, outSize);
        return;
      }
    }
    if (row == 1) {
      uint8_t cc = encoderCC(row, col);
      if (ccKnown[channelIndex][cc]) {
        formatPanValue(ccValues[channelIndex][cc], out, outSize);
        return;
      }
    }
    snprintf(out, outSize, "Tr%u", track);
    return;
  }

  if (currentChannel == 2) {
    if (row == 2 && col == 5) {
      uint8_t monitorState = monitorModeFromValue(noteValue(padNote(0, col)));
      if (monitorState == 0) {
        snprintf(out, outSize, "OFF");
      } else if (monitorState == 1) {
        snprintf(out, outSize, "ON");
      } else {
        snprintf(out, outSize, "AUTO");
      }
      return;
    }
    if (row < 2) {
      uint8_t cc = encoderCC(row, col);
      if (ccKnown[channelIndex][cc]) {
        if (row == 0 && col == 1) {
          formatPanValue(ccValues[channelIndex][cc], out, outSize);
        } else {
          formatPercentValue(ccValues[channelIndex][cc], out, outSize);
        }
        return;
      }
    }
    snprintf(out, outSize, row < 2 ? "Sel" : "Track");
    return;
  }

  if (currentChannel == 3) {
    if (currentBank == 2) {
      snprintf(out, outSize, row < 2 ? "Param" : "Slot");
    } else {
      snprintf(out, outSize, "Send%u", col + 1);
    }
    return;
  }

  if (currentChannel == 9) {
    snprintf(out, outSize, "Grid");
    return;
  }

  if (currentChannel == 10) {
    snprintf(out, outSize, "Trans");
    return;
  }

  if (currentChannel == 11) {
    snprintf(out, outSize, "Mark");
    return;
  }

  if (currentChannel == 12) {
    snprintf(out, outSize, "Item");
    return;
  }

  if (currentChannel == 16) {
    snprintf(out, outSize, "Glob");
    return;
  }

  snprintf(out, outSize, "");
}

void drawTile(uint8_t row, uint8_t col) {
  const int16_t x = col * 40;
  const int16_t y = 50 + row * 47;
  const int16_t w = 39;
  const int16_t h = 46;

  bool assigned = tileAssigned(row, col);
  bool active = tileActive(row, col);
  uint16_t color = assigned ? tileBaseColor(row, col) : ILI9341_DARKGREY;
  uint16_t bg = active ? color : dimColor(color);
  uint16_t fg = foregroundColor(color, active);

  tft.fillRect(x, y, w, h, bg);
  tft.drawRect(x, y, w, h, ILI9341_BLACK);
  tft.setTextColor(fg, bg);

  tft.setTextSize(1);
  tft.setCursor(x + 3, y + 3);
  tft.print(keys[row][col]);

  char label[8];
  tileLabel(row, col, label, sizeof(label));
  tft.setCursor(x + 3, y + 16);
  tft.print(label);

  char value[8];
  tileValue(row, col, value, sizeof(value));
  tft.setCursor(x + 3, y + 30);
  tft.print(value);
}

void drawFooter() {
  tft.fillRect(0, 238, 320, 2, ILI9341_DARKGREY);
}

void drawDashboard() {
  drawHeader();
  for (uint8_t row = 0; row < 4; row++) {
    for (uint8_t col = 0; col < 8; col++) {
      drawTile(row, col);
      tileDirty[row][col] = false;
    }
  }
  drawFooter();
  fullRedraw = false;
  headerTopDirty = false;
  midiEditorGridHeaderDirty = false;
  midiEditorGridTypeHeaderDirty = false;
  midiEditorSnapHeaderDirty = false;
  for (uint8_t badge = 0; badge < 5; badge++) {
    badgeDirty[badge] = false;
  }
}

void clearNotes() {
  for (uint8_t channel = 0; channel < 16; channel++) {
    for (uint8_t i = 0; i < NOTE_COUNT; i++) {
      noteValues[channel][i] = 0;
      noteFlashUntil[channel][i] = 0;
    }
  }
}

void processFlashExpirations() {
  uint32_t now = millis();
  for (uint8_t channel = 0; channel < 16; channel++) {
    for (uint8_t i = 0; i < NOTE_COUNT; i++) {
      if (noteFlashUntil[channel][i] != 0 && (int32_t)(now - noteFlashUntil[channel][i]) >= 0) {
        noteFlashUntil[channel][i] = 0;
        if (noteValues[channel][i] != 0) {
          noteValues[channel][i] = 0;
          if (channel == currentChannel - 1) {
            markTileForNote(NOTE_BASE + i);
          }
        }
      }
    }
  }
}

void clearCCs() {
  for (uint8_t channel = 0; channel < 16; channel++) {
    for (uint8_t cc = 0; cc < 128; cc++) {
      ccValues[channel][cc] = 0;
      ccKnown[channel][cc] = false;
    }
  }
}

void markAllTilesDirty() {
  for (uint8_t row = 0; row < 4; row++) {
    for (uint8_t col = 0; col < 8; col++) {
      tileDirty[row][col] = true;
    }
  }
}

void markAllBadgesDirty() {
  for (uint8_t badge = 0; badge < 5; badge++) {
    badgeDirty[badge] = true;
  }
}

void markTileForNote(uint8_t note) {
  if (currentChannel == 9) {
    if (note == padNote(0, 5) || note == padNote(0, 6)) {
      midiEditorGridTypeHeaderDirty = true;
    }
    if (note == padNote(1, 2)) {
      midiEditorSnapHeaderDirty = true;
    }
  }

  uint8_t bankNoteBase = NOTE_BASE + (currentBank - 1) * 16;
  if (note >= bankNoteBase && note < bankNoteBase + 8) {
    tileDirty[2][note - bankNoteBase] = true;
  } else if (note >= bankNoteBase + 8 && note < bankNoteBase + 16) {
    tileDirty[3][note - bankNoteBase - 8] = true;
  }

  switch (note) {
    case 92:
      badgeDirty[BADGE_PLAY] = true;
      break;
    case 93:
      badgeDirty[BADGE_REC] = true;
      break;
    case 94:
      badgeDirty[BADGE_LOOP] = true;
      break;
    case 95:
      badgeDirty[BADGE_METR] = true;
      break;
    case 99:
      badgeDirty[BADGE_MIDI] = true;
      break;
  }
}

void markTileForCC(uint8_t channel, uint8_t controller) {
  if (channel != currentChannel) {
    return;
  }

  if (channel == 9 && controller == MIDI_EDITOR_GRID_CC) {
    midiEditorGridHeaderDirty = true;
  }

  uint8_t bankCCBase = CC_BASE + (currentBank - 1) * 16;
  if (controller >= bankCCBase && controller < bankCCBase + 8) {
    tileDirty[0][controller - bankCCBase] = true;
  } else if (controller >= bankCCBase + 8 && controller < bankCCBase + 16) {
    tileDirty[1][controller - bankCCBase - 8] = true;
  }
}

void renderDirty() {
  if (fullRedraw) {
    drawDashboard();
    return;
  }

  if (headerTopDirty) {
    drawHeaderTop();
    headerTopDirty = false;
    midiEditorGridHeaderDirty = false;
    midiEditorGridTypeHeaderDirty = false;
    midiEditorSnapHeaderDirty = false;
  } else if (currentChannel == 9) {
    if (midiEditorGridHeaderDirty || midiEditorGridTypeHeaderDirty) {
      drawMidiEditorGridHeaderValue();
      midiEditorGridHeaderDirty = false;
      midiEditorGridTypeHeaderDirty = false;
    }
    if (midiEditorSnapHeaderDirty) {
      drawMidiEditorSnapHeaderValue();
      midiEditorSnapHeaderDirty = false;
    }
  }

  for (uint8_t badge = 0; badge < 5; badge++) {
    if (badgeDirty[badge]) {
      drawBadgeByIndex(badge);
      badgeDirty[badge] = false;
    }
  }

  for (uint8_t row = 0; row < 4; row++) {
    for (uint8_t col = 0; col < 8; col++) {
      if (tileDirty[row][col]) {
        drawTile(row, col);
        tileDirty[row][col] = false;
      }
    }
  }
}

void handleLine(char *line) {
  int first = 0;
  int second = 0;
  int third = 0;
  int fourth = 0;

  if (line[0] == 'S' && sscanf(line, "S %d %d %d %d", &first, &second, &third, &fourth) == 4) {
    bool nextMidiModeActive = first != 0;
    uint8_t nextChannel = constrain(second, 1, 16);
    uint8_t nextBank = constrain(third, 1, 4);
    bool nextTransportRunning = fourth != 0;

    if (nextChannel != currentChannel || nextBank != currentBank) {
      fullRedraw = true;
    } else {
      if (nextMidiModeActive != midiModeActive) {
        badgeDirty[BADGE_MIDI] = true;
      }
      if (nextTransportRunning != transportRunning) {
        badgeDirty[BADGE_PLAY] = true;
      }
    }

    midiModeActive = nextMidiModeActive;
    currentChannel = nextChannel;
    currentBank = nextBank;
    transportRunning = nextTransportRunning;
    return;
  }

  if (line[0] == 'N' && sscanf(line, "N %d %d", &first, &second) == 2) {
    if (first >= NOTE_BASE && first < NOTE_BASE + NOTE_COUNT) {
      uint8_t nextValue = constrain(second, 0, 127);
      uint8_t channelIndex = currentChannel - 1;
      if (isSelectedTrackMonitorNote(first) && nextValue == 0) {
        return;
      }
      uint8_t noteIndex = first - NOTE_BASE;
      if (isMomentaryPadFlashNote(currentChannel, first) && nextValue > 0) {
        noteFlashUntil[channelIndex][noteIndex] = millis() + FLASH_DURATION_MS;
      } else if (nextValue == 0) {
        noteFlashUntil[channelIndex][noteIndex] = 0;
      }
      if (noteValues[channelIndex][noteIndex] != nextValue) {
        noteValues[channelIndex][noteIndex] = nextValue;
        markTileForNote(first);
      }
    }
    return;
  }

  if (line[0] == 'P' && sscanf(line, "P %d %d %d", &first, &second, &third) == 3) {
    if (first >= 1 && first <= 16 && second >= NOTE_BASE && second < NOTE_BASE + NOTE_COUNT) {
      uint8_t channel = first;
      uint8_t channelIndex = channel - 1;
      uint8_t note = second;
      uint8_t nextValue = constrain(third, 0, 127);
      if (isSelectedTrackMonitorNoteForChannel(channel, note) && nextValue == 0) {
        return;
      }
      uint8_t noteIndex = note - NOTE_BASE;
      if (isMomentaryPadFlashNote(channel, note) && nextValue > 0) {
        noteFlashUntil[channelIndex][noteIndex] = millis() + FLASH_DURATION_MS;
      } else if (nextValue == 0) {
        noteFlashUntil[channelIndex][noteIndex] = 0;
      }
      if (noteValues[channelIndex][noteIndex] != nextValue) {
        noteValues[channelIndex][noteIndex] = nextValue;
        if (channel == currentChannel) {
          markTileForNote(note);
        }
      }
    }
    return;
  }

  if (line[0] == 'K' && sscanf(line, "K %d %d %d", &first, &second, &third) == 3) {
    if (first >= 1 && first <= 16 && second >= 0 && second <= 127) {
      uint8_t channel = first;
      uint8_t channelIndex = channel - 1;
      uint8_t controller = second;
      uint8_t nextValue = constrain(third, 0, 127);
      if (!ccKnown[channelIndex][controller] || ccValues[channelIndex][controller] != nextValue) {
        ccKnown[channelIndex][controller] = true;
        ccValues[channelIndex][controller] = nextValue;
        markTileForCC(channel, controller);
      }
    }
    return;
  }

  if (line[0] == 'C') {
    clearNotes();
    clearCCs();
    fullRedraw = true;
  }
}

void readSerial() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\r') {
      continue;
    }
    if (c == '\n') {
      if (serialLineLength > 0) {
        serialLine[serialLineLength] = '\0';
        handleLine(serialLine);
        serialLineLength = 0;
      }
      continue;
    }
    if (serialLineLength < sizeof(serialLine) - 1) {
      serialLine[serialLineLength++] = c;
    } else {
      serialLineLength = 0;
    }
  }
}

void setup() {
  Serial.begin(115200);

  pinMode(TFT_CS, OUTPUT);
  digitalWrite(TFT_CS, HIGH);

  SPI.begin(TFT_SCK, TFT_MISO, TFT_MOSI, TFT_CS);
  tft.begin();
  tft.setRotation(1);
  tft.fillScreen(ILI9341_BLACK);
  clearNotes();
  clearCCs();
  drawDashboard();
}

void loop() {
  readSerial();
  processFlashExpirations();
  renderDirty();
}
