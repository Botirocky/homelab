#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <SPI.h>
#include <SD.h>
#include <TFT_eSPI.h>
#include <XPT2046_Touchscreen.h>

#include "config.h"
#include "fontok.h"

constexpr int SZ = 320;
constexpr int MA = 240;
constexpr int LED_R = 4;
constexpr int LED_G = 16;
constexpr int LED_B = 17;
constexpr int GOMB = 0;
constexpr int T_CLK = 25;
constexpr int T_MISO = 39;
constexpr int T_MOSI = 32;
constexpr int T_CS = 33;
constexpr int T_IRQ = 36;
constexpr int SD_CS = 5;
constexpr int SD_SCK = 18;
constexpr int SD_MISO = 19;
constexpr int SD_MOSI = 23;
constexpr int TORT_HOSSZ = 90;
const char* VERZIO = "1.1";

constexpr uint16_t rgb(uint8_t r, uint8_t g, uint8_t b) {
  return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

constexpr uint16_t C_HATTER = rgb(10, 13, 19);
constexpr uint16_t C_KARTYA = rgb(24, 30, 41);
constexpr uint16_t C_VONAL = rgb(46, 55, 70);
constexpr uint16_t C_SZOVEG = rgb(236, 239, 244);
constexpr uint16_t C_HALVANY = rgb(138, 149, 166);
constexpr uint16_t C_ZOLD = rgb(52, 199, 120);
constexpr uint16_t C_SARGA = rgb(245, 181, 45);
constexpr uint16_t C_PIROS = rgb(240, 72, 72);
constexpr uint16_t C_KEK = rgb(84, 160, 255);
constexpr uint16_t C_LILA = rgb(170, 120, 255);

TFT_eSPI tft;
TFT_eSprite spr(&tft);
SPIClass erintoSpi(VSPI);
XPT2046_Touchscreen erinto(T_CS, T_IRQ);

struct Lemez {
  char nev[16];
  int szazalek;
  float szabad;
};

struct Allapot {
  bool van = false;
  uint32_t ido = 0;
  char ora[6] = "--:--";
  uint32_t uptime = 0;
  int cpu = 0;
  float homer = 0;
  float terheles = 0;
  int ramSzazalek = 0;
  int ramHasznalt = 0;
  int ramOssz = 0;
  Lemez lemezek[4];
  int lemezDb = 0;
  int kFut = 0;
  int kOssz = 0;
  char leallt[4][24];
  int lealltDb = 0;
  int lealltOssz = 0;
  char beteg[4][24];
  int betegDb = 0;
  bool pihole = false;
  long lekerdezes = 0;
  long blokkolt = 0;
  float blokkSzazalek = 0;
  int egSzint = -1;
  char gondok[5][100];
  int gondDb = 0;
  bool tailscale = false;
  int mentesKor = -1;
};

enum Lap { ATTEKINTES, TARHELY, ELOZMENY, GONDOK, LAP_DB };

String cfgSsid = WIFI_SSID;
String cfgJelszo = WIFI_JELSZO;
String cfgUrl = SZERVER_URL;
String cfgNev = SZERVER_NEV;
bool cfgForditott = FORDITOTT;
bool sdBeallitasOk = false;

Allapot all;
uint8_t cpuTort[TORT_HOSSZ];
uint8_t homTort[TORT_HOSSZ];
int tortDb = 0;

int lap = ATTEKINTES;
int kirajzoltLap = -1;
bool kieses = false;
bool kiesesKirajzolva = false;
int szint = 0;
int elozoSzint = 0;
uint32_t utolsoSiker = 0;
uint32_t utolsoLekeres = 0;
uint32_t utolsoLapozas = 0;
uint32_t kezPihenoIg = 0;
uint32_t utolsoErintes = 0;
uint32_t szerverIdoValtozott = 0;
uint32_t elozoSzerverIdo = 0;
bool elavult = false;
bool ejszaka = false;
bool infoLap = false;
uint32_t infoIg = 0;
uint32_t sikeresDb = 0;
uint32_t sikertelenDb = 0;

enum Esemeny { NINCS, ELORE, VISSZA, HOSSZU };
bool nyomvaVolt = false;
bool hosszuKiadva = false;
bool gombbal = false;
uint32_t nyomasKezd = 0;
uint32_t utolsoNyomva = 0;
int nyomasX = 0;

template <typename G>
void betu(G& g, const uint8_t* f) {
  g.unloadFont();
  g.loadFont(f);
}

void betu(const uint8_t* f) {
  betu(spr, f);
}

uint16_t homerSzin(float c) {
  if (c >= 75) return C_PIROS;
  if (c >= 65) return C_SARGA;
  return C_ZOLD;
}

uint16_t szazalekSzin(int p, int sarga, int piros) {
  if (p >= piros) return C_PIROS;
  if (p >= sarga) return C_SARGA;
  return C_KEK;
}

String tizedes(float v, int jegy) {
  String s = String(v, jegy);
  s.replace('.', ',');
  return s;
}

String fentIdo(uint32_t mp) {
  uint32_t nap = mp / 86400;
  uint32_t ora = (mp % 86400) / 3600;
  uint32_t perc = (mp % 3600) / 60;
  if (nap > 0) return String(nap) + " nap " + String(ora) + " óra";
  if (ora > 0) return String(ora) + " óra " + String(perc) + " perc";
  return String(perc) + " perc";
}

String mentesSzoveg(int kor) {
  if (kor < 0) return "nincs adat";
  if (kor == 0) return "1 órán belül";
  if (kor < 48) return String(kor) + " órája";
  return String(kor / 24) + " napja";
}

void led(int r, int g, int b) {
  digitalWrite(LED_R, r ? LOW : HIGH);
  digitalWrite(LED_G, g ? LOW : HIGH);
  digitalWrite(LED_B, b ? LOW : HIGH);
}

void masol(char* cel, size_t meret, const char* forras) {
  strncpy(cel, forras ? forras : "", meret - 1);
  cel[meret - 1] = 0;
}

bool lekerdez() {
  if (WiFi.status() != WL_CONNECTED) return false;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(4000);
  if (!http.begin(cfgUrl)) return false;
  int kod = http.GET();
  if (kod != 200) {
    http.end();
    return false;
  }
  String torzs = http.getString();
  http.end();

  JsonDocument doc;
  if (deserializeJson(doc, torzs)) return false;

  Allapot a;
  a.van = true;
  a.ido = doc["ido"] | 0;
  masol(a.ora, sizeof(a.ora), doc["ora"] | "--:--");
  a.uptime = doc["uptime"] | 0;
  a.cpu = doc["cpu"] | 0;
  a.homer = doc["homerseklet"] | 0.0f;
  a.terheles = doc["terheles"] | 0.0f;
  a.ramSzazalek = doc["ram"]["szazalek"] | 0;
  a.ramHasznalt = doc["ram"]["hasznalt_mb"] | 0;
  a.ramOssz = doc["ram"]["ossz_mb"] | 0;

  for (JsonObject l : doc["lemezek"].as<JsonArray>()) {
    if (a.lemezDb >= 4) break;
    Lemez& d = a.lemezek[a.lemezDb++];
    masol(d.nev, sizeof(d.nev), l["nev"] | "?");
    d.szazalek = l["szazalek"] | 0;
    d.szabad = l["szabad_gb"] | 0.0f;
  }

  JsonObject k = doc["kontenerek"];
  a.kFut = k["fut"] | 0;
  a.kOssz = k["ossz"] | 0;
  for (JsonVariant n : k["leallt"].as<JsonArray>()) {
    if (a.lealltDb >= 4) break;
    masol(a.leallt[a.lealltDb++], 24, n.as<const char*>());
  }
  a.lealltOssz = k["leallt"].size();
  for (JsonVariant n : k["beteg"].as<JsonArray>()) {
    if (a.betegDb >= 4) break;
    masol(a.beteg[a.betegDb++], 24, n.as<const char*>());
  }

  JsonObject p = doc["pihole"];
  a.pihole = !p.isNull();
  a.lekerdezes = p["lekerdezes"] | 0;
  a.blokkolt = p["blokkolt"] | 0;
  a.blokkSzazalek = p["szazalek"] | 0.0f;

  JsonObject e = doc["egeszseg"];
  a.egSzint = e.isNull() ? -1 : (e["szint"] | 0);
  for (JsonVariant g : e["gondok"].as<JsonArray>()) {
    if (a.gondDb >= 5) break;
    masol(a.gondok[a.gondDb++], 100, g.as<const char*>());
  }

  a.tailscale = doc["tailscale"] | false;
  a.mentesKor = doc["mentes"]["kor_ora"] | -1;

  if (a.ido != elozoSzerverIdo) {
    elozoSzerverIdo = a.ido;
    szerverIdoValtozott = millis();
  }
  all = a;
  return true;
}

void tortenetHozzaad() {
  if (tortDb == TORT_HOSSZ) {
    memmove(cpuTort, cpuTort + 1, TORT_HOSSZ - 1);
    memmove(homTort, homTort + 1, TORT_HOSSZ - 1);
    tortDb--;
  }
  cpuTort[tortDb] = constrain(all.cpu, 0, 100);
  homTort[tortDb] = constrain((int)(all.homer + 0.5f), 0, 255);
  tortDb++;
}

int szintSzamol() {
  if (kieses) return 2;
  int s = 0;
  if (all.egSzint >= 1 || all.homer >= 70 || all.ramSzazalek >= 90 || all.betegDb > 0 || elavult ||
      all.mentesKor > 36 || !all.tailscale)
    s = 1;
  for (int i = 0; i < all.lemezDb; i++)
    if (all.lemezek[i].szazalek >= 90) s = max(s, 1);
  if (all.egSzint >= 2 || all.lealltDb > 0 || all.homer >= 80) s = 2;
  return s;
}

bool vanGond() {
  return szint > 0;
}

void fejlec() {
  spr.createSprite(SZ, 30);
  spr.fillSprite(C_HATTER);
  betu(font_kozep);
  spr.setTextDatum(TL_DATUM);
  spr.setTextColor(C_SZOVEG, C_HATTER);
  spr.drawString(cfgNev, 12, 6);
  int x = 18 + spr.textWidth(cfgNev);

  uint16_t szin = szint == 0 ? C_ZOLD : (szint == 1 ? C_SARGA : C_PIROS);
  const char* felirat = szint == 0 ? "rendben" : (szint == 1 ? "figyelem" : "hiba");
  spr.fillSmoothCircle(x + 5, 15, 5, szin, C_HATTER);
  betu(font_kicsi);
  spr.setTextColor(szin, C_HATTER);
  spr.drawString(felirat, x + 15, 9);

  betu(font_kozep);
  spr.setTextDatum(TR_DATUM);
  spr.setTextColor(C_HALVANY, C_HATTER);
  spr.drawString(all.ora, SZ - 12, 6);
  spr.drawFastHLine(0, 29, SZ, C_KARTYA);
  spr.pushSprite(0, 0);
  spr.unloadFont();
  spr.deleteSprite();
}

void lapPontok() {
  int db = vanGond() ? LAP_DB : LAP_DB - 1;
  int w = db * 14;
  int x0 = (SZ - w) / 2 + 7;
  tft.fillRect(0, 228, SZ, 12, C_HATTER);
  for (int i = 0; i < db; i++) {
    uint16_t c = i == lap ? C_SZOVEG : C_VONAL;
    tft.fillSmoothCircle(x0 + i * 14, 234, i == lap ? 3 : 2, c, C_HATTER);
  }
}

void csempe(int x, int y, int w, int h, const char* cim, const String& ertek, const String& al, float arany,
            uint16_t szin) {
  spr.createSprite(w, h);
  spr.fillSprite(C_HATTER);
  spr.fillSmoothRoundRect(0, 0, w, h, 10, C_KARTYA, C_HATTER);
  spr.setTextDatum(TL_DATUM);
  betu(font_kicsi);
  spr.setTextColor(C_HALVANY, C_KARTYA);
  spr.drawString(cim, 12, 7);
  betu(font_nagy);
  spr.setTextColor(szin, C_KARTYA);
  spr.drawString(ertek, 11, 21);
  betu(font_kicsi);
  spr.setTextColor(C_HALVANY, C_KARTYA);
  spr.drawString(al, 12, h - 24);
  int bw = w - 24;
  spr.fillSmoothRoundRect(12, h - 9, bw, 4, 2, C_VONAL, C_KARTYA);
  int fw = constrain((int)(bw * arany + 0.5f), 0, bw);
  if (fw > 3) spr.fillSmoothRoundRect(12, h - 9, fw, 4, 2, szin, C_KARTYA);
  spr.pushSprite(x, y);
  spr.unloadFont();
  spr.deleteSprite();
}

void sav(int y, int h, const String& szoveg, uint16_t szin) {
  spr.createSprite(SZ, h);
  spr.fillSprite(C_HATTER);
  betu(font_kicsi);
  spr.setTextDatum(MC_DATUM);
  spr.setTextColor(szin, C_HATTER);
  spr.drawString(szoveg, SZ / 2, h / 2);
  spr.pushSprite(0, y);
  spr.unloadFont();
  spr.deleteSprite();
}

void lapAttekintes() {
  const int w = 150, h = 82, x1 = 7, x2 = 163, y1 = 36, y2 = 124;

  csempe(x1, y1, w, h, "CPU", String(all.cpu) + "%", "terhelés " + tizedes(all.terheles, 2), all.cpu / 100.0f,
         szazalekSzin(all.cpu, 70, 90));
  csempe(x2, y1, w, h, "Hőmérséklet", tizedes(all.homer, 1) + "°", all.homer >= 65 ? "melegszik" : "hűvös",
         constrain((all.homer - 30) / 55.0f, 0.0f, 1.0f), homerSzin(all.homer));
  csempe(x1, y2, w, h, "Memória", String(all.ramSzazalek) + "%",
         tizedes(all.ramHasznalt / 1024.0f, 1) + " / " + tizedes(all.ramOssz / 1024.0f, 1) + " GB",
         all.ramSzazalek / 100.0f, szazalekSzin(all.ramSzazalek, 80, 90));

  String al;
  uint16_t szin = C_ZOLD;
  if (all.lealltDb > 0) {
    al = String(all.lealltOssz) + " leállt";
    szin = C_PIROS;
  } else if (all.betegDb > 0) {
    al = String(all.betegDb) + " nem egészséges";
    szin = C_SARGA;
  } else {
    al = "mind fut";
  }
  csempe(x2, y2, w, h, "Konténerek", String(all.kFut) + "/" + String(all.kOssz), al,
         all.kOssz ? (float)all.kFut / all.kOssz : 0, szin);

  String also = "mentés: " + mentesSzoveg(all.mentesKor);
  if (all.pihole) also += "  •  Pi-hole: " + tizedes(all.blokkSzazalek, 1) + "% szűrve";
  sav(208, 18, also, all.mentesKor > 36 ? C_SARGA : C_HALVANY);
}

void lapTarhely() {
  int y = 34;
  for (int i = 0; i < all.lemezDb; i++) {
    Lemez& d = all.lemezek[i];
    uint16_t szin = szazalekSzin(d.szazalek, 80, 90);
    spr.createSprite(SZ, 38);
    spr.fillSprite(C_HATTER);
    betu(font_kozep);
    spr.setTextDatum(TL_DATUM);
    spr.setTextColor(C_SZOVEG, C_HATTER);
    spr.drawString(d.nev, 14, 2);
    betu(font_kicsi);
    spr.setTextDatum(TR_DATUM);
    spr.setTextColor(C_HALVANY, C_HATTER);
    spr.drawString(String(d.szazalek) + "%  •  " + tizedes(d.szabad, 1) + " GB szabad", SZ - 14, 6);
    spr.fillSmoothRoundRect(14, 26, SZ - 28, 6, 3, C_KARTYA, C_HATTER);
    int fw = (SZ - 28) * constrain(d.szazalek, 0, 100) / 100;
    if (fw > 5) spr.fillSmoothRoundRect(14, 26, fw, 6, 3, szin, C_HATTER);
    spr.pushSprite(0, y);
    spr.unloadFont();
    spr.deleteSprite();
    y += 38;
  }

  struct Sor {
    const char* cim;
    String ertek;
    uint16_t szin;
  } sorok[] = {
      {"Pi-hole", all.pihole ? String(all.blokkolt) + " / " + String(all.lekerdezes) + " szűrve" : "nincs adat",
       C_SZOVEG},
      {"Tailscale", all.tailscale ? "kapcsolódva" : "nincs kapcsolat", all.tailscale ? C_ZOLD : C_SARGA},
      {"Üzemidő", fentIdo(all.uptime), C_SZOVEG},
      {"WiFi (kijelző)", String(WiFi.RSSI()) + " dBm", C_HALVANY},
  };
  int maradek = 226 - y;
  int db = min(4, (maradek - 8) / 19);
  if (db <= 0) return;
  spr.createSprite(SZ, 8 + db * 19);
  spr.fillSprite(C_HATTER);
  spr.drawFastHLine(14, 2, SZ - 28, C_KARTYA);
  betu(font_kicsi);
  for (int i = 0; i < db; i++) {
    int sy = 8 + i * 19;
    spr.setTextDatum(TL_DATUM);
    spr.setTextColor(C_HALVANY, C_HATTER);
    spr.drawString(sorok[i].cim, 14, sy);
    spr.setTextDatum(TR_DATUM);
    spr.setTextColor(sorok[i].szin, C_HATTER);
    spr.drawString(sorok[i].ertek, SZ - 14, sy);
  }
  spr.pushSprite(0, y);
  spr.unloadFont();
  spr.deleteSprite();
}

void grafikon(int y0, int h, const char* cim, const String& ertek, const uint8_t* adat, int minV, int maxV,
              uint16_t szin) {
  spr.createSprite(SZ - 14, h);
  spr.fillSprite(C_HATTER);
  spr.fillSmoothRoundRect(0, 0, SZ - 14, h, 10, C_KARTYA, C_HATTER);
  betu(font_kicsi);
  spr.setTextDatum(TL_DATUM);
  spr.setTextColor(C_HALVANY, C_KARTYA);
  spr.drawString(cim, 12, 7);
  betu(font_kozep);
  spr.setTextDatum(TR_DATUM);
  spr.setTextColor(szin, C_KARTYA);
  spr.drawString(ertek, SZ - 26, 4);

  const int gx = 12, gy = 28, gw = SZ - 14 - 24, gh = h - 36;
  for (int i = 1; i < 4; i++) spr.drawFastHLine(gx, gy + gh * i / 4, gw, C_VONAL);
  if (tortDb >= 2) {
    uint16_t halvany = spr.alphaBlend(70, szin, C_KARTYA);
    int elozoX = 0, elozoY = 0;
    for (int i = 0; i < tortDb; i++) {
      int x = gx + (TORT_HOSSZ - tortDb + i) * gw / (TORT_HOSSZ - 1);
      int v = constrain((int)adat[i], minV, maxV);
      int yy = gy + gh - (v - minV) * gh / (maxV - minV);
      spr.drawFastVLine(x, yy, gy + gh - yy, halvany);
      if (i > 0) spr.drawWideLine(elozoX, elozoY, x, yy, 2, szin, C_KARTYA);
      elozoX = x;
      elozoY = yy;
    }
  } else {
    betu(font_kicsi);
    spr.setTextDatum(MC_DATUM);
    spr.setTextColor(C_HALVANY, C_KARTYA);
    spr.drawString("gyűlnek az adatok…", (SZ - 14) / 2, gy + gh / 2);
  }
  spr.pushSprite(7, y0);
  spr.unloadFont();
  spr.deleteSprite();
}

void lapElozmeny() {
  grafikon(36, 94, "CPU", String(all.cpu) + "%", cpuTort, 0, 100, C_KEK);
  grafikon(134, 90, "Hőmérséklet", tizedes(all.homer, 1) + "°C", homTort, 35, 85, homerSzin(all.homer));
}

template <typename G>
int sortor(G& g, const String& szoveg, int x, int y, int szel, int sorMag, int maxY) {
  String sor, szo;
  String s = szoveg + " ";
  for (size_t i = 0; i < s.length(); i++) {
    char c = s[i];
    if (c == ' ') {
      String probal = sor.length() ? sor + " " + szo : szo;
      if (g.textWidth(probal) > szel && sor.length()) {
        if (y > maxY) return y;
        g.drawString(sor, x, y);
        y += sorMag;
        sor = szo;
      } else {
        sor = probal;
      }
      szo = "";
    } else {
      szo += c;
    }
  }
  if (sor.length() && y <= maxY) {
    g.drawString(sor, x, y);
    y += sorMag;
  }
  return y;
}

void lapGondok() {
  tft.fillRect(0, 32, SZ, 194, C_HATTER);
  if (!vanGond()) {
    uint16_t kor = tft.alphaBlend(60, C_ZOLD, C_HATTER);
    tft.fillSmoothCircle(SZ / 2, 94, 34, kor, C_HATTER);
    tft.drawWideLine(SZ / 2 - 15, 95, SZ / 2 - 4, 106, 5, C_ZOLD, kor);
    tft.drawWideLine(SZ / 2 - 4, 106, SZ / 2 + 17, 83, 5, C_ZOLD, kor);
    betu(tft, font_kozep);
    tft.setTextDatum(MC_DATUM);
    tft.setTextColor(C_SZOVEG, C_HATTER);
    tft.drawString("Minden rendben", SZ / 2, 154);
    betu(tft, font_kicsi);
    tft.setTextColor(C_HALVANY, C_HATTER);
    tft.drawString(String(all.kFut) + "/" + String(all.kOssz) + " konténer fut", SZ / 2, 178);
  } else {
    betu(tft, font_kicsi);
    tft.setTextDatum(TL_DATUM);
    int y = 40;
    auto tetel = [&](const String& t, uint16_t szin) {
      if (y > 208) return;
      tft.fillSmoothCircle(18, y + 7, 3, szin, C_HATTER);
      tft.setTextColor(C_SZOVEG, C_HATTER);
      y = sortor(tft, t, 28, y, SZ - 42, 17, 208) + 5;
    };
    for (int i = 0; i < all.lealltDb; i++) tetel(String("leállt: ") + all.leallt[i], C_PIROS);
    if (all.lealltOssz > all.lealltDb) tetel("… és még " + String(all.lealltOssz - all.lealltDb) + " leállt", C_PIROS);
    for (int i = 0; i < all.betegDb; i++) tetel(String("nem egészséges: ") + all.beteg[i], C_SARGA);
    for (int i = 0; i < all.gondDb; i++) tetel(all.gondok[i], all.egSzint >= 2 ? C_PIROS : C_SARGA);
    if (all.homer >= 70) tetel("magas hőmérséklet: " + tizedes(all.homer, 1) + "°C", C_SARGA);
    if (all.ramSzazalek >= 90) tetel("kevés a szabad memória: " + String(all.ramSzazalek) + "%", C_SARGA);
    for (int i = 0; i < all.lemezDb; i++)
      if (all.lemezek[i].szazalek >= 90)
        tetel(String("majdnem tele: ") + all.lemezek[i].nev + " (" + all.lemezek[i].szazalek + "%)", C_SARGA);
    if (all.mentesKor > 36) tetel("a legutóbbi mentés " + mentesSzoveg(all.mentesKor), C_SARGA);
    if (!all.tailscale) tetel("a Tailscale nem kapcsolódik", C_SARGA);
    if (elavult) tetel("az állapotadat nem frissül (park-allapot.timer)", C_SARGA);
  }
  tft.unloadFont();
}

void kiesesKepernyo() {
  tft.fillScreen(C_HATTER);
  tft.drawSmoothRoundRect(4, 4, 8, 8, SZ - 9, MA - 9, C_PIROS, C_HATTER);
  tft.fillSmoothCircle(SZ / 2, 78, 32, C_PIROS, C_HATTER);
  tft.fillSmoothRoundRect(SZ / 2 - 3, 58, 7, 26, 3, C_HATTER, C_PIROS);
  tft.fillSmoothCircle(SZ / 2, 94, 4, C_HATTER, C_PIROS);
  betu(tft, font_kozep);
  tft.setTextDatum(MC_DATUM);
  tft.setTextColor(C_SZOVEG, C_HATTER);
  tft.drawString("A " + cfgNev + " nem válaszol", SZ / 2, 136);
  betu(tft, font_kicsi);
  tft.setTextColor(C_HALVANY, C_HATTER);
  String mikor = "még nem jött adat";
  if (all.van) {
    uint32_t perc = (millis() - utolsoSiker) / 60000;
    mikor = perc < 1 ? "utolsó adat: 1 percen belül" : "utolsó adat: " + String(perc) + " perce";
  }
  tft.drawString(mikor, SZ / 2, 164);
  tft.drawString(WiFi.status() == WL_CONNECTED ? "WiFi rendben – a szerver vagy a Caddy áll?" : "nincs WiFi-kapcsolat",
                 SZ / 2, 184);
  tft.setTextColor(C_VONAL, C_HATTER);
  tft.drawString(cfgUrl, SZ / 2, 212);
  tft.unloadFont();
}

void infoKepernyo() {
  tft.fillScreen(C_HATTER);
  betu(tft, font_kozep);
  tft.setTextDatum(TL_DATUM);
  tft.setTextColor(C_SZOVEG, C_HATTER);
  tft.drawString("A kijelző", 12, 6);
  tft.drawFastHLine(0, 29, SZ, C_KARTYA);

  uint32_t fent = millis() / 1000;
  bool wifi = WiFi.status() == WL_CONNECTED;
  struct Sor {
    const char* cim;
    String ertek;
    uint16_t szin;
  } sorok[] = {
      {"WiFi", wifi ? cfgSsid : "nincs kapcsolat", wifi ? C_SZOVEG : C_PIROS},
      {"IP-cím", wifi ? WiFi.localIP().toString() : "–", C_SZOVEG},
      {"Jelerősség", wifi ? String(WiFi.RSSI()) + " dBm" : "–",
       !wifi ? C_HALVANY : (WiFi.RSSI() > -67 ? C_ZOLD : (WiFi.RSSI() > -78 ? C_SARGA : C_PIROS))},
      {"Lekérések", String(sikeresDb) + " sikeres, " + String(sikertelenDb) + " hibás",
       sikertelenDb > sikeresDb ? C_SARGA : C_SZOVEG},
      {"Utolsó adat", all.van ? String((millis() - utolsoSiker) / 1000) + " mp-e" : "még nem jött", C_SZOVEG},
      {"Bekapcsolva", fentIdo(fent), C_SZOVEG},
      {"Szabad memória", String(ESP.getFreeHeap() / 1024) + " KB", C_HALVANY},
      {"Beállítás", sdBeallitasOk ? "SD-kártya" : "config.h", C_HALVANY},
      {"Verzió", String(VERZIO) + (cfgForditott ? " • fordított kép" : ""), C_HALVANY},
  };
  betu(tft, font_kicsi);
  int y = 38;
  for (auto& s : sorok) {
    tft.setTextDatum(TL_DATUM);
    tft.setTextColor(C_HALVANY, C_HATTER);
    tft.drawString(s.cim, 14, y);
    tft.setTextDatum(TR_DATUM);
    tft.setTextColor(s.szin, C_HATTER);
    tft.drawString(s.ertek, SZ - 14, y);
    y += 20;
  }
  tft.setTextDatum(MC_DATUM);
  tft.setTextColor(C_VONAL, C_HATTER);
  tft.drawString(cfgUrl, SZ / 2, 228);
  tft.unloadFont();
}

void kirajzol(bool teljes) {
  if (infoLap) {
    if (teljes) infoKepernyo();
    kirajzoltLap = -1;
    kiesesKirajzolva = false;
    return;
  }
  if (kieses) {
    if (!kiesesKirajzolva || teljes) kiesesKepernyo();
    kiesesKirajzolva = true;
    kirajzoltLap = -1;
    return;
  }
  if (kiesesKirajzolva || kirajzoltLap != lap || teljes) {
    tft.fillScreen(C_HATTER);
    kiesesKirajzolva = false;
  }
  fejlec();
  switch (lap) {
    case ATTEKINTES: lapAttekintes(); break;
    case TARHELY: lapTarhely(); break;
    case ELOZMENY: lapElozmeny(); break;
    case GONDOK: lapGondok(); break;
  }
  lapPontok();
  kirajzoltLap = lap;
}

void kovetkezoLap(int irany = 1) {
  int db = vanGond() ? LAP_DB : LAP_DB - 1;
  lap = (lap + irany + db) % db;
  utolsoLapozas = millis();
  kirajzol(true);
}

void ledFrissit() {
  uint32_t most = millis();
  if (szint == 2) {
    bool villog = kieses ? ((most / 500) % 2) : true;
    led(villog, 0, 0);
  } else if (szint == 1) {
    led(1, 1, 0);
  } else {
    led(0, ejszaka ? 0 : 1, 0);
  }
}

void fenyero() {
  int ora = atoi(all.ora);
  bool uj = all.van && (EJSZAKA_TOL > EJSZAKA_IG ? (ora >= EJSZAKA_TOL || ora < EJSZAKA_IG)
                                                  : (ora >= EJSZAKA_TOL && ora < EJSZAKA_IG));
  if (kieses) uj = false;
  ejszaka = uj;
  ledcWrite(TFT_BL, ejszaka ? FENYERO_EJJEL : FENYERO_NAPPAL);
}

void indulas() {
  tft.fillScreen(C_HATTER);
  spr.createSprite(SZ, 90);
  spr.fillSprite(C_HATTER);
  betu(font_kozep);
  spr.setTextDatum(MC_DATUM);
  spr.setTextColor(C_SZOVEG, C_HATTER);
  spr.drawString("Szerver-kijelző", SZ / 2, 20);
  betu(font_kicsi);
  spr.setTextColor(C_HALVANY, C_HATTER);
  spr.drawString("kapcsolódás: " + cfgSsid + "…", SZ / 2, 52);
  spr.setTextColor(C_VONAL, C_HATTER);
  spr.drawString(sdBeallitasOk ? "beállítás: SD-kártya" : "beállítás: config.h", SZ / 2, 72);
  spr.pushSprite(0, 80);
  spr.unloadFont();
  spr.deleteSprite();
}

void sdBeallitas() {
  SPIClass sdSpi(VSPI);
  sdSpi.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
  if (SD.begin(SD_CS, sdSpi, 20000000)) {
    File f = SD.open("/szerver_kijelzo.txt");
    if (f) {
      while (f.available()) {
        String sor = f.readStringUntil('\n');
        sor.trim();
        if (sor.isEmpty() || sor[0] == '#') continue;
        int eq = sor.indexOf('=');
        if (eq < 0) continue;
        String k = sor.substring(0, eq);
        String v = sor.substring(eq + 1);
        k.trim();
        v.trim();
        k.toLowerCase();
        if (k == "wifi_ssid") cfgSsid = v;
        else if (k == "wifi_jelszo") cfgJelszo = v;
        else if (k == "url") cfgUrl = v;
        else if (k == "nev") cfgNev = v;
        else if (k == "forditott") cfgForditott = !(v == "0" || v == "nem" || v == "false");
      }
      f.close();
      sdBeallitasOk = true;
    }
    SD.end();
  }
  sdSpi.end();
}

int erintes() {
  uint32_t most = millis();
  bool gomb = digitalRead(GOMB) == LOW;
  bool erint = !gomb && erinto.tirqTouched() && erinto.touched();
  if (gomb || erint) {
    utolsoNyomva = most;
    if (!nyomvaVolt) {
      nyomvaVolt = true;
      hosszuKiadva = false;
      gombbal = gomb;
      nyomasKezd = most;
      nyomasX = erint ? erinto.getPoint().x : 4095;
    }
    if (!hosszuKiadva && most - nyomasKezd >= HOSSZU_NYOMAS_MS) {
      hosszuKiadva = true;
      return HOSSZU;
    }
    return NINCS;
  }
  if (!nyomvaVolt || most - utolsoNyomva < 80) return NINCS;
  nyomvaVolt = false;
  if (hosszuKiadva || most - utolsoErintes < 250) return NINCS;
  utolsoErintes = most;
  return (!gombbal && nyomasX < 1400) ? VISSZA : ELORE;
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_R, OUTPUT);
  pinMode(LED_G, OUTPUT);
  pinMode(LED_B, OUTPUT);
  led(0, 0, 1);
  pinMode(GOMB, INPUT_PULLUP);

  tft.init();
  sdBeallitas();

  tft.setRotation(cfgForditott ? 3 : 1);
  ledcAttach(TFT_BL, 5000, 8);
  ledcWrite(TFT_BL, FENYERO_NAPPAL);

  erintoSpi.begin(T_CLK, T_MISO, T_MOSI, T_CS);
  erinto.begin(erintoSpi);
  erinto.setRotation(cfgForditott ? 3 : 1);

  indulas();

  WiFi.mode(WIFI_STA);
  WiFi.setHostname("szerver-kijelzo");
  WiFi.setAutoReconnect(true);
  WiFi.begin(cfgSsid.c_str(), cfgJelszo.c_str());
  uint32_t kezd = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - kezd < 20000) delay(200);

  utolsoLekeres = millis() - LEKERDEZES_MP * 1000UL;
  utolsoLapozas = millis();
}

void loop() {
  uint32_t most = millis();

  if (most - utolsoLekeres >= LEKERDEZES_MP * 1000UL) {
    utolsoLekeres = most;
    if (lekerdez()) {
      utolsoSiker = millis();
      sikeresDb++;
      tortenetHozzaad();
    } else {
      sikertelenDb++;
    }
    kieses = !all.van ? (millis() > 25000) : (millis() - utolsoSiker > KIESES_MP * 1000UL);
    elavult = all.van && !kieses && millis() - szerverIdoValtozott > 150000UL;
    elozoSzint = szint;
    szint = szintSzamol();
    if (szint == 2 && elozoSzint < 2 && !kieses) lap = GONDOK;
    if (!vanGond() && lap == GONDOK) lap = ATTEKINTES;
    fenyero();
    if (all.van || kieses) kirajzol(false);
  }

  int e = erintes();
  if (e == HOSSZU) {
    infoLap = !infoLap;
    infoIg = millis() + INFO_MP * 1000UL;
    kezPihenoIg = millis() + 60000;
    kirajzol(true);
  } else if (e != NINCS) {
    kezPihenoIg = millis() + 60000;
    if (infoLap) {
      infoLap = false;
      kirajzol(true);
    } else if (!kieses) {
      kovetkezoLap(e == VISSZA ? -1 : 1);
    }
  }

  if (infoLap && millis() > infoIg) {
    infoLap = false;
    kirajzol(true);
  }

  if (!infoLap && !kieses && all.van && millis() > kezPihenoIg && millis() - utolsoLapozas >= LAPOZAS_MP * 1000UL) {
    if (!(szint == 2 && lap == GONDOK)) kovetkezoLap();
    else utolsoLapozas = millis();
  }

  ledFrissit();
  delay(20);
}
