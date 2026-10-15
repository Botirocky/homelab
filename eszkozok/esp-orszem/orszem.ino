#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_BME280.h>
#include <Adafruit_NeoPixel.h>
#include <time.h>
#include <stdarg.h>
#include "config.h"
#include "web_ui.h"

enum Allapot : uint8_t { INDUL, RENDBEN, ELAVULT, WEB_HIBA, NEM_VALASZOL, HALOZAT_HIBA, NINCS_WIFI };

struct PiAdat {
  char gep[24] = PI_NEV;
  time_t ido = 0;
  int cpu = -1;
  float ho = NAN;
  int ram = -1;
  int lemez = -1;
  int kontFut = -1;
  int kontOssz = -1;
  uint32_t uptime = 0;
  bool van = false;
};

struct Esemeny {
  time_t ido;
  uint32_t ms;
  char szoveg[80];
};

struct Ertesites {
  char cim[48];
  char szoveg[160];
  uint8_t prio;
};

struct Gomb {
  uint8_t lab;
  bool lent;
  uint32_t lenyomvaMs;
  bool hosszuVolt;
};

const int ESEMENY_DB = 20;
const int SOR_DB = 6;

Adafruit_SSD1306 oled(128, 64, &Wire, OLED_RST);
Adafruit_BME280 bme;
Adafruit_NeoPixel pixel(1, NEOPIXEL_LAB, NEO_GRB + NEO_KHZ800);
WebServer web(80);
Preferences nvs;

bool oledVan = false;
bool bmeVan = false;
float benti = NAN, para = NAN, nyomas = NAN;

PiAdat pi;
Allapot allapot = INDUL;
uint32_t allapotOtaMs = 0;

bool kiesesAktiv = false;
bool nemitva = false;
uint32_t kiesesKezdoMs = 0;
time_t kiesesKezdete = 0;
bool figyAktiv = false;
bool rackMeleg = false;
bool piMeleg = false;
uint32_t utolsoRiasztasMs = 0;

uint32_t kiesesDb = 0;
time_t utolsoKieses = 0;
uint32_t utolsoKiesesMp = 0;

Esemeny esemenyek[ESEMENY_DB];
uint8_t esemenyFej = 0, esemenyDb = 0;

Ertesites sor[SOR_DB];
uint8_t sorDb = 0;
uint32_t kovKuldesMs = 0;

uint32_t utolsoEllenorzesMs = 0;
uint32_t utolsoBmeMs = 0;
uint32_t utolsoOledMs = 0;
uint32_t wifiElveszettMs = 0;
uint8_t lap = 0;
uint32_t kezziLapozasMs = 0;
uint32_t lapValtasMs = 0;
uint32_t uzenetVegeMs = 0;
char uzenet[24] = "";

Gomb gombFel = {GOMB_FEL}, gombLe = {GOMB_LE}, gombOk = {GOMB_OK}, gombMod = {GOMB_MOD};

bool elmult(uint32_t kezdet, uint32_t hossz) {
  return (uint32_t)(millis() - kezdet) >= hossz;
}

bool idoOk() {
  return time(nullptr) > 1700000000;
}

bool ejjel() {
  if (!idoOk()) return false;
  time_t t = time(nullptr);
  struct tm lt;
  localtime_r(&t, &lt);
  return EJJEL_TOL > EJJEL_IG ? (lt.tm_hour >= EJJEL_TOL || lt.tm_hour < EJJEL_IG)
                              : (lt.tm_hour >= EJJEL_TOL && lt.tm_hour < EJJEL_IG);
}

void idoSzoveg(time_t t, char *buf, size_t n) {
  if (t < 1700000000) {
    snprintf(buf, n, "?");
    return;
  }
  struct tm lt;
  localtime_r(&t, &lt);
  strftime(buf, n, "%m.%d. %H:%M", &lt);
}

void hosszSzoveg(uint32_t mp, char *buf, size_t n, bool ascii) {
  const char *o = ascii ? "o" : "ó";
  if (mp < 60) snprintf(buf, n, "%u mp", (unsigned)mp);
  else if (mp < 3600) snprintf(buf, n, "%u p", (unsigned)(mp / 60));
  else if (mp < 86400) snprintf(buf, n, "%u %s %u p", (unsigned)(mp / 3600), o, (unsigned)(mp % 3600 / 60));
  else snprintf(buf, n, "%u nap %u %s", (unsigned)(mp / 86400), (unsigned)(mp % 86400 / 3600), o);
}

const char *allapotKod(Allapot a) {
  switch (a) {
    case RENDBEN: return "rendben";
    case ELAVULT: return "elavult";
    case WEB_HIBA: return "web_hiba";
    case NEM_VALASZOL: return "nem_valaszol";
    case HALOZAT_HIBA: return "halozat_hiba";
    case NINCS_WIFI: return "nincs_wifi";
    default: return "indul";
  }
}

const char *allapotSzoveg(Allapot a) {
  switch (a) {
    case RENDBEN: return "rendben";
    case ELAVULT: return "az állapotadat elavult";
    case WEB_HIBA: return "a gép él, a web nem válaszol";
    case NEM_VALASZOL: return "nem válaszol";
    case HALOZAT_HIBA: return "a router sem válaszol";
    case NINCS_WIFI: return "az őrszemnek nincs WiFi-je";
    default: return "indul";
  }
}

const char *allapotOled(Allapot a) {
  switch (a) {
    case RENDBEN: return "RENDBEN";
    case ELAVULT: return "ELAVULT";
    case WEB_HIBA: return "WEB HIBA";
    case NEM_VALASZOL: return "NEM VALASZ";
    case HALOZAT_HIBA: return "HALO HIBA";
    case NINCS_WIFI: return "NINCS WIFI";
    default: return "INDUL...";
  }
}

bool piEl(Allapot a) {
  return a == RENDBEN || a == ELAVULT || a == WEB_HIBA;
}

void kiir(const char *s) {
  strlcpy(uzenet, s, sizeof(uzenet));
  uzenetVegeMs = millis() + 2500;
}

void esemeny(const char *fmt, ...) {
  Esemeny &e = esemenyek[esemenyFej];
  va_list args;
  va_start(args, fmt);
  vsnprintf(e.szoveg, sizeof(e.szoveg), fmt, args);
  va_end(args);
  e.ido = idoOk() ? time(nullptr) : 0;
  e.ms = millis();
  esemenyFej = (esemenyFej + 1) % ESEMENY_DB;
  if (esemenyDb < ESEMENY_DB) esemenyDb++;
  Serial.printf("[%lu] %s\n", (unsigned long)(millis() / 1000), e.szoveg);
}

void ertesit(const char *cim, uint8_t prio, const char *fmt, ...) {
  char szoveg[160];
  va_list args;
  va_start(args, fmt);
  vsnprintf(szoveg, sizeof(szoveg), fmt, args);
  va_end(args);
  esemeny("%s – %s", cim, szoveg);
  if (!NTFY_TEMA[0] && !DISCORD_WEBHOOK[0]) return;
  if (sorDb == SOR_DB) {
    memmove(&sor[0], &sor[1], sizeof(Ertesites) * (SOR_DB - 1));
    sorDb--;
  }
  Ertesites &e = sor[sorDb++];
  strlcpy(e.cim, cim, sizeof(e.cim));
  strlcpy(e.szoveg, szoveg, sizeof(e.szoveg));
  e.prio = prio;
  kovKuldesMs = millis();
}

bool httpsPost(const char *url, const String &test) {
  WiFiClientSecure kliens;
  kliens.setInsecure();
  HTTPClient http;
  http.setConnectTimeout(5000);
  http.setTimeout(6000);
  if (!http.begin(kliens, url)) return false;
  http.addHeader("Content-Type", "application/json");
  int kod = http.POST(test);
  http.end();
  return kod >= 200 && kod < 300;
}

bool kuld(const Ertesites &e) {
  bool sikerult = false;
  if (NTFY_TEMA[0]) {
    JsonDocument d;
    d["topic"] = NTFY_TEMA;
    d["title"] = e.cim;
    d["message"] = e.szoveg;
    d["priority"] = e.prio;
    d["tags"].add(e.prio >= 4 ? "rotating_light" : "white_check_mark");
    String s;
    serializeJson(d, s);
    sikerult |= httpsPost(NTFY_SZERVER, s);
  }
  if (DISCORD_WEBHOOK[0]) {
    JsonDocument d;
    d["content"] = String(e.prio >= 4 ? "🚨 **" : "✅ **") + e.cim + "**\n" + e.szoveg;
    String s;
    serializeJson(d, s);
    sikerult |= httpsPost(DISCORD_WEBHOOK, s);
  }
  return sikerult;
}

void sorKezel() {
  if (!sorDb || WiFi.status() != WL_CONNECTED || (int32_t)(millis() - kovKuldesMs) < 0) return;
  if (kuld(sor[0])) {
    memmove(&sor[0], &sor[1], sizeof(Ertesites) * (SOR_DB - 1));
    sorDb--;
    kovKuldesMs = millis() + 1000;
  } else {
    kovKuldesMs = millis() + 60000;
  }
}

void mentes() {
  nvs.putUInt("kiesesDb", kiesesDb);
  nvs.putULong64("utKieses", (uint64_t)utolsoKieses);
  nvs.putUInt("utHossz", utolsoKiesesMp);
}

void hang(uint16_t f, uint16_t ms) {
  tone(BUZZER_PIN, f, ms);
  delay(ms + 40);
}

void riasztoHang() {
  if (ejjel() || nemitva) return;
  for (uint8_t i = 0; i < 3; i++) {
    hang(2200, 180);
    hang(1500, 180);
  }
  utolsoRiasztasMs = millis();
}

void figyHang() {
  if (ejjel()) return;
  hang(1800, 120);
}

void visszajottHang() {
  if (ejjel()) return;
  hang(1200, 100);
  hang(1800, 100);
  hang(2400, 160);
}

void kattanas() {
  tone(BUZZER_PIN, 3000, 15);
}

bool tcpProba(IPAddress ip, uint16_t port, int32_t ms) {
  WiFiClient c;
  bool ok = c.connect(ip, port, ms);
  c.stop();
  return ok;
}

Allapot piLekerdez() {
  WiFiClient kliens;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(4000);
  if (http.begin(kliens, ALLAPOT_URL)) {
    int kod = http.GET();
    if (kod == 200) {
      String test = http.getString();
      http.end();
      JsonDocument d;
      if (deserializeJson(d, test)) return WEB_HIBA;
      strlcpy(pi.gep, d["gep"] | PI_NEV, sizeof(pi.gep));
      pi.ido = d["ido"] | (time_t)0;
      pi.cpu = d["cpu"] | -1;
      pi.ho = d["homerseklet"] | NAN;
      pi.ram = d["ram"]["szazalek"] | -1;
      pi.uptime = d["uptime"] | 0;
      pi.kontFut = d["kontenerek"]["fut"] | -1;
      pi.kontOssz = d["kontenerek"]["ossz"] | -1;
      pi.lemez = -1;
      for (JsonObject l : d["lemezek"].as<JsonArray>()) pi.lemez = max(pi.lemez, (int)(l["szazalek"] | -1));
      pi.van = true;
      if (idoOk() && pi.ido > 0 && time(nullptr) - pi.ido > ELAVULT_MP) return ELAVULT;
      return RENDBEN;
    }
    http.end();
  }
  IPAddress cim;
  cim.fromString(PI_CIM);
  if (tcpProba(cim, PI_SSH_PORT, 2000)) return WEB_HIBA;
  return NEM_VALASZOL;
}

void allapotValt(Allapot uj) {
  if (uj == allapot) return;
  esemeny("%s: %s", PI_NEV, allapotSzoveg(uj));
  allapot = uj;
  allapotOtaMs = millis();
}

void kiesesKezel() {
  uint32_t tart = millis() - allapotOtaMs;
  char h[24];

  if (allapot == NEM_VALASZOL && !kiesesAktiv && tart >= KIESES_MP * 1000UL) {
    kiesesAktiv = true;
    nemitva = false;
    kiesesKezdoMs = allapotOtaMs;
    kiesesKezdete = idoOk() ? time(nullptr) - tart / 1000 : 0;
    kiesesDb++;
    mentes();
    hosszSzoveg(tart / 1000, h, sizeof(h), false);
    ertesit("picloud nem válaszol", 5, "%s óta nem válaszol se weben, se SSH-n. A router elérhető, tehát a Pi a hibás.", h);
    riasztoHang();
  }

  if (kiesesAktiv && piEl(allapot)) {
    uint32_t hossz = (millis() - kiesesKezdoMs) / 1000;
    kiesesAktiv = false;
    nemitva = false;
    utolsoKieses = kiesesKezdete;
    utolsoKiesesMp = hossz;
    mentes();
    hosszSzoveg(hossz, h, sizeof(h), false);
    ertesit("picloud újra elérhető", 3, "A kiesés %s volt.", h);
    visszajottHang();
  }

  if (kiesesAktiv && elmult(utolsoRiasztasMs, EMLEKEZTETO_PERC * 60000UL)) riasztoHang();

  if ((allapot == ELAVULT || allapot == WEB_HIBA) && !figyAktiv && tart >= FIGY_MP * 1000UL) {
    figyAktiv = true;
    ertesit("picloud: figyelem", 4, "%s. A gép él, de valami nem fut rendesen.", allapotSzoveg(allapot));
    figyHang();
  }
  if (figyAktiv && allapot == RENDBEN) {
    figyAktiv = false;
    ertesit("picloud: rendben", 2, "Minden szolgáltatás újra válaszol.");
  }

  if (piEl(allapot) && pi.van && !isnan(pi.ho)) {
    if (!piMeleg && pi.ho >= PI_MELEG_C) {
      piMeleg = true;
      ertesit("picloud melegszik", 4, "A CPU %.1f °C.", pi.ho);
      figyHang();
    } else if (piMeleg && pi.ho < PI_MELEG_C - 5) {
      piMeleg = false;
      esemeny("a Pi lehűlt: %.1f °C", pi.ho);
    }
  }
  if (bmeVan && !isnan(benti)) {
    if (!rackMeleg && benti >= RACK_MELEG_C) {
      rackMeleg = true;
      ertesit("Meleg van a Pi körül", 4, "Az őrszem %.1f °C-ot mér.", benti);
      figyHang();
    } else if (rackMeleg && benti < RACK_MELEG_C - 2) {
      rackMeleg = false;
      esemeny("a Pi környéke lehűlt: %.1f °C", benti);
    }
  }
}

void ellenorzes() {
  Allapot uj;
  if (WiFi.status() != WL_CONNECTED) {
    uj = NINCS_WIFI;
  } else {
    uj = piLekerdez();
    if (uj == NEM_VALASZOL) {
      IPAddress gw = WiFi.gatewayIP();
      if (!tcpProba(gw, 80, 1500) && !tcpProba(gw, 53, 1500)) uj = HALOZAT_HIBA;
    }
  }
  allapotValt(uj);
  kiesesKezel();
}

void bmeOlvas() {
  if (!bmeVan) return;
  benti = bme.readTemperature();
  para = bme.readHumidity();
  nyomas = bme.readPressure() / 100.0f;
}

void wifiKezel() {
  if (WiFi.status() == WL_CONNECTED) {
    wifiElveszettMs = 0;
    return;
  }
  if (!wifiElveszettMs) wifiElveszettMs = millis();
  static uint32_t utolsoProba = 0;
  if (elmult(wifiElveszettMs, 20000) && elmult(utolsoProba, 30000)) {
    utolsoProba = millis();
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_JELSZO);
  }
}

bool nemit() {
  if (!kiesesAktiv || nemitva) return false;
  nemitva = true;
  noTone(BUZZER_PIN);
  esemeny("a riasztó hangja némítva");
  return true;
}

bool teszt() {
  if (!NTFY_TEMA[0] && !DISCORD_WEBHOOK[0]) return false;
  ertesit("Őrszem teszt", 3, "Az értesítés működik. %s: %s.", PI_NEV, allapotSzoveg(allapot));
  return true;
}

void apiAllapot() {
  JsonDocument d;
  char buf[32];
  d["allapot"] = allapotKod(allapot);
  d["szoveg"] = allapotSzoveg(allapot);
  d["ota_mp"] = (millis() - allapotOtaMs) / 1000;
  d["ido"] = idoOk() ? (long)time(nullptr) : 0;

  JsonObject o = d["orszem"].to<JsonObject>();
  o["ip"] = WiFi.localIP().toString();
  o["rssi"] = WiFi.RSSI();
  o["uptime"] = millis() / 1000;
  o["oled"] = oledVan;
  o["bme"] = bmeVan;
  o["ntfy"] = NTFY_TEMA[0] != 0;
  o["discord"] = DISCORD_WEBHOOK[0] != 0;
  o["fuggo"] = sorDb;
  o["ejjel"] = ejjel();

  JsonObject k = d["kieses"].to<JsonObject>();
  k["aktiv"] = kiesesAktiv;
  k["nemitva"] = nemitva;
  k["kezdete"] = (long)kiesesKezdete;
  k["tart_mp"] = kiesesAktiv ? (millis() - kiesesKezdoMs) / 1000 : 0;
  k["db"] = kiesesDb;
  k["utolso"] = (long)utolsoKieses;
  k["utolso_mp"] = utolsoKiesesMp;

  JsonObject p = d["pi"].to<JsonObject>();
  p["gep"] = pi.gep;
  p["van"] = pi.van;
  if (pi.van) {
    p["ido"] = (long)pi.ido;
    p["cpu"] = pi.cpu;
    if (!isnan(pi.ho)) p["ho"] = pi.ho;
    p["ram"] = pi.ram;
    p["lemez"] = pi.lemez;
    p["kont_fut"] = pi.kontFut;
    p["kont_ossz"] = pi.kontOssz;
    p["uptime"] = pi.uptime;
  }

  if (bmeVan) {
    JsonObject b = d["rack"].to<JsonObject>();
    b["ho"] = roundf(benti * 10) / 10;
    b["para"] = roundf(para);
    b["nyomas"] = roundf(nyomas * 10) / 10;
  }

  JsonArray e = d["esemenyek"].to<JsonArray>();
  for (uint8_t i = 0; i < esemenyDb; i++) {
    const Esemeny &x = esemenyek[(esemenyFej + ESEMENY_DB - 1 - i) % ESEMENY_DB];
    JsonObject j = e.add<JsonObject>();
    if (x.ido) {
      idoSzoveg(x.ido, buf, sizeof(buf));
      j["ido"] = buf;
    } else {
      hosszSzoveg((millis() - x.ms) / 1000, buf, sizeof(buf), false);
      j["ido"] = String(buf) + " ezelőtt";
    }
    j["szoveg"] = x.szoveg;
  }

  String s;
  serializeJson(d, s);
  web.send(200, "application/json; charset=utf-8", s);
}

void webIndit() {
  web.on("/", [] { web.send_P(200, "text/html; charset=utf-8", WEB_OLDAL); });
  web.on("/api/allapot", apiAllapot);
  web.on("/api/teszt", HTTP_POST, [] {
    if (teszt()) web.send(200, "text/plain; charset=utf-8", "Elküldve.");
    else web.send(409, "text/plain; charset=utf-8", "Nincs beállítva értesítési csatorna.");
  });
  web.on("/api/nemit", HTTP_POST, [] {
    if (nemit()) web.send(200, "text/plain; charset=utf-8", "A riasztó hangja némítva.");
    else web.send(409, "text/plain; charset=utf-8", "Nincs mit némítani.");
  });
  web.onNotFound([] { web.send(404, "text/plain", "nincs ilyen"); });
  web.begin();
}

void oledKozep(const char *s, int y, uint8_t meret) {
  int16_t x1, y1;
  uint16_t w, h;
  oled.setTextSize(meret);
  oled.getTextBounds(s, 0, 0, &x1, &y1, &w, &h);
  oled.setCursor((128 - w) / 2, y);
  oled.print(s);
}

void oledFejlec(const char *cim, uint8_t lapSzam, uint8_t lapDb) {
  oled.setTextSize(1);
  oled.setCursor(0, 0);
  oled.print(cim);
  if (idoOk()) {
    char ora[8];
    time_t t = time(nullptr);
    struct tm lt;
    localtime_r(&t, &lt);
    strftime(ora, sizeof(ora), "%H:%M", &lt);
    oled.setCursor(98, 0);
    oled.print(ora);
  }
  for (uint8_t i = 0; i < lapDb; i++) oled.fillRect(76 + i * 5, 3, 3, 3 - (i != lapSzam) * 2, SSD1306_WHITE);
  oled.drawFastHLine(0, 10, 128, SSD1306_WHITE);
}

void oledRajzol() {
  if (!oledVan) return;
  oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE);
  char s[32], h[20];

  if ((int32_t)(millis() - uzenetVegeMs) < 0) {
    oled.drawRect(0, 18, 128, 28, SSD1306_WHITE);
    oledKozep(uzenet, 28, 1);
    oled.display();
    return;
  }

  if (kiesesAktiv) {
    bool villog = !nemitva && (millis() / 700) % 2;
    if (villog) oled.fillRect(0, 0, 128, 34, SSD1306_WHITE);
    oled.setTextColor(villog ? SSD1306_BLACK : SSD1306_WHITE);
    oledKozep("PICLOUD", 2, 2);
    oledKozep("LEALLT!", 18, 2);
    oled.setTextColor(SSD1306_WHITE);
    hosszSzoveg((millis() - kiesesKezdoMs) / 1000, h, sizeof(h), true);
    snprintf(s, sizeof(s), "%s ota nem valaszol", h);
    oledKozep(s, 40, 1);
    oledKozep(nemitva ? "(nemitva)" : "OK gomb: nemitas", 54, 1);
    oled.display();
    return;
  }

  uint8_t lapDb = bmeVan ? 3 : 2;
  lap %= lapDb;
  uint8_t tenyleges = (!bmeVan && lap == 1) ? 2 : lap;

  if (tenyleges == 0) {
    oledFejlec("PICLOUD", lap, lapDb);
    oledKozep(allapotOled(allapot), 15, 2);
    oled.setTextSize(1);
    if (pi.van && piEl(allapot)) {
      oled.setCursor(0, 36);
      oled.printf("CPU %d%%  %.1f C", pi.cpu, pi.ho);
      oled.setCursor(0, 46);
      oled.printf("RAM %d%%  lemez %d%%", pi.ram, pi.lemez);
      oled.setCursor(0, 56);
      oled.printf("kontener %d/%d", pi.kontFut, pi.kontOssz);
    } else {
      hosszSzoveg((millis() - allapotOtaMs) / 1000, h, sizeof(h), true);
      snprintf(s, sizeof(s), "%s ota", h);
      oledKozep(s, 42, 1);
    }
  } else if (tenyleges == 1) {
    oledFejlec("A PI KORUL", lap, lapDb);
    snprintf(s, sizeof(s), "%.1fC", benti);
    oledKozep(s, 16, 3);
    snprintf(s, sizeof(s), "%.0f%%  %.0f hPa", para, nyomas);
    oledKozep(s, 50, 1);
  } else {
    oledFejlec("ORSZEM", lap, lapDb);
    oled.setTextSize(1);
    oled.setCursor(0, 14);
    oled.print(WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString() : String("nincs WiFi"));
    oled.setCursor(0, 24);
    oled.printf("WiFi %d dBm", WiFi.RSSI());
    oled.setCursor(0, 34);
    oled.printf("kiesesek: %u", (unsigned)kiesesDb);
    oled.setCursor(0, 44);
    if (utolsoKiesesMp) {
      hosszSzoveg(utolsoKiesesMp, h, sizeof(h), true);
      idoSzoveg(utolsoKieses, s, sizeof(s));
      oled.printf("utolso: %s", s);
      oled.setCursor(0, 54);
      oled.printf("  %s-ig tartott", h);
    } else {
      hosszSzoveg(millis() / 1000, h, sizeof(h), true);
      oled.printf("fut: %s", h);
    }
  }
  oled.display();
}

uint32_t szin(uint8_t r, uint8_t g, uint8_t b) {
  return pixel.Color(r, g, b);
}

void pixelKezel() {
  static uint32_t elozo = 0xFFFFFFFF;
  uint32_t m = millis();
  uint32_t c;
  if (kiesesAktiv) c = ((m / 250) % 2) ? szin(255, 0, 0) : 0;
  else if (allapot == NEM_VALASZOL) c = szin(255, 0, 0);
  else if (allapot == ELAVULT || allapot == WEB_HIBA) c = szin(255, 140, 0);
  else if (allapot == NINCS_WIFI || allapot == HALOZAT_HIBA) c = ((m / 1000) % 2) ? szin(0, 0, 255) : 0;
  else if (allapot == RENDBEN) c = ejjel() ? 0 : szin(0, 120, 0);
  else c = szin(60, 60, 60);
  if (c != elozo) {
    pixel.setPixelColor(0, c);
    pixel.show();
    elozo = c;
  }
}

uint8_t gombOlvas(Gomb &g) {
  bool lent = digitalRead(g.lab) == LOW;
  uint8_t esemeny = 0;
  if (lent && !g.lent) {
    g.lenyomvaMs = millis();
    g.hosszuVolt = false;
  } else if (lent && g.lent && !g.hosszuVolt && elmult(g.lenyomvaMs, 1000)) {
    g.hosszuVolt = true;
    esemeny = 2;
  } else if (!lent && g.lent && !g.hosszuVolt && elmult(g.lenyomvaMs, 30)) {
    esemeny = 1;
  }
  g.lent = lent;
  return esemeny;
}

void lapoz(int8_t irany) {
  uint8_t lapDb = bmeVan ? 3 : 2;
  lap = (lap + lapDb + irany) % lapDb;
  kezziLapozasMs = millis();
  lapValtasMs = millis();
  kattanas();
}

void gombKezel() {
  if (gombOlvas(gombFel) == 1) lapoz(-1);
  if (gombOlvas(gombLe) == 1) lapoz(1);
  if (gombOlvas(gombOk) == 1) {
    if (nemit()) kiir("riaszto nemitva");
    else lapoz(1);
  }
  uint8_t m = gombOlvas(gombMod);
  if (m == 1) lapoz(1);
  else if (m == 2) {
    kattanas();
    kiir(teszt() ? "teszt elkuldve" : "nincs ertesites");
  }
  if (elmult(kezziLapozasMs, 60000) && elmult(lapValtasMs, 8000)) {
    lap++;
    lapValtasMs = millis();
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(GOMB_FEL, INPUT_PULLUP);
  pinMode(GOMB_LE, INPUT_PULLUP);
  pinMode(GOMB_OK, INPUT_PULLUP);
  pinMode(GOMB_MOD, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(NEOPIXEL_TAP, OUTPUT);
  digitalWrite(NEOPIXEL_TAP, HIGH);
  delay(10);
  pixel.begin();
  pixel.setBrightness(NEOPIXEL_FENY);
  pixel.setPixelColor(0, szin(60, 60, 60));
  pixel.show();

  nvs.begin(GEPNEV, false);
  kiesesDb = nvs.getUInt("kiesesDb", 0);
  utolsoKieses = (time_t)nvs.getULong64("utKieses", 0);
  utolsoKiesesMp = nvs.getUInt("utHossz", 0);

  Wire.begin();
  oledVan = oled.begin(SSD1306_SWITCHCAPVCC, OLED_CIM);
  if (oledVan) {
    oled.clearDisplay();
    oled.setTextColor(SSD1306_WHITE);
    oledKozep("ORSZEM", 16, 2);
    oledKozep("csatlakozas...", 44, 1);
    oled.display();
  }
  bmeVan = bme.begin(0x76, &Wire) || bme.begin(0x77, &Wire);
  bmeOlvas();

  WiFi.mode(WIFI_STA);
  WiFi.setHostname(GEPNEV);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_JELSZO);
  for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) delay(250);

  configTzTime(TZ_INFO, "pool.ntp.org", "time.google.com");
  MDNS.begin(GEPNEV);
  MDNS.addService("http", "tcp", 80);

  ArduinoOTA.setHostname(GEPNEV);
  if (WEB_KULCS[0]) ArduinoOTA.setPassword(WEB_KULCS);
  ArduinoOTA.onStart([] {
    esemeny("OTA frissítés indul");
    if (oledVan) {
      oled.clearDisplay();
      oledKozep("FRISSITES...", 28, 1);
      oled.display();
    }
  });
  ArduinoOTA.begin();

  webIndit();
  esemeny("őrszem elindult (OLED: %s, BME280: %s)", oledVan ? "van" : "nincs", bmeVan ? "van" : "nincs");
  hang(1500, 60);
  hang(2200, 60);
  allapotOtaMs = millis();
  utolsoEllenorzesMs = millis() - ELLENORZES_MP * 1000UL;
}

void loop() {
  ArduinoOTA.handle();
  web.handleClient();
  wifiKezel();
  gombKezel();
  pixelKezel();

  if (elmult(utolsoEllenorzesMs, ELLENORZES_MP * 1000UL)) {
    utolsoEllenorzesMs = millis();
    ellenorzes();
  }
  if (elmult(utolsoBmeMs, 10000)) {
    utolsoBmeMs = millis();
    bmeOlvas();
  }
  sorKezel();
  if (elmult(utolsoOledMs, 200)) {
    utolsoOledMs = millis();
    oledRajzol();
  }
  delay(5);
}
