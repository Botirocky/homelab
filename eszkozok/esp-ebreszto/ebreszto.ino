#include <WiFi.h>
#include <WiFiUdp.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_NeoPixel.h>
#include <time.h>
#include <Preferences.h>
#include "lwip/sockets.h"
#include "lwip/inet_chksum.h"
#include "lwip/prot/icmp.h"
#include "lwip/prot/ip4.h"
#include "config.h"
#include "web_ui.h"

enum Tipus : uint8_t { WOL, LIBVIRT, INCUS };
enum GepAllapot : int8_t { ISMERETLEN = -1, ALL = 0, FUT = 1 };
enum Kepernyo : uint8_t { LISTA, MENU, MEGEROSIT, FOLYAMAT, EREDMENY };
enum Muvelet : uint8_t { M_NINCS, M_EBRESZT, M_INDIT, M_LEALLIT, M_KENYSZER, M_VISSZA };

struct Gep {
  char nev[24];
  Tipus tipus;
  GepAllapot allapot;
};

struct Gomb {
  uint8_t lab;
  bool lent;
  uint32_t lenyomvaMs;
  bool hosszuVolt;
};

const int GEP_MAX = 12;

Adafruit_SSD1306 oled(128, 64, &Wire, OLED_RST);
Adafruit_NeoPixel pixel(1, NEOPIXEL_LAB, NEO_GRB + NEO_KHZ800);
WebServer web(80);
WiFiUDP udp;

bool oledVan = false;
bool kijelzoAlszik = false;
uint32_t utolsoGombMs = 0;

Gep gepek[GEP_MAX];
uint8_t gepDb = 1;
bool piElerheto = false;
IPAddress laptopIp;

Kepernyo kepernyo = LISTA;
uint8_t kivalasztott = 0;
uint8_t gorgetes = 0;
Muvelet menu[4];
uint8_t menuDb = 0;
uint8_t menuPoz = 0;
Muvelet megerositendo = M_NINCS;
Muvelet fuggoMuv = M_NINCS;
uint8_t fuggoGep = 0;

Muvelet folyMuv = M_NINCS;
uint8_t folyGep = 0;
uint32_t folyKezdetMs = 0;
uint8_t wolKuldve = 0;
bool eredmenyJo = false;
char eredmenySzoveg[28] = "";
uint32_t eredmenyVegeMs = 0;

uint32_t utolsoFrissitesMs = 0;
uint32_t utolsoDnsMs = 0;
uint32_t wifiElveszettMs = 0;

uint16_t pingSorszam = 0;

Preferences beallitas;
bool ejszBe = false;
uint16_t leallPerc = EJSZAKA_ALAP_LEALL;
uint16_t ebresztPerc = EJSZAKA_ALAP_EBRESZT;
char piEjszAllapot[16] = "?";
char piEjszOk[48] = "";
bool piEjszFut = false;
time_t utolsoLeallKeres = 0;
time_t utolsoEbresztKesz = 0;

Gomb gombFel = {GOMB_FEL}, gombLe = {GOMB_LE}, gombOk = {GOMB_OK}, gombMod = {GOMB_MOD};

bool elmult(uint32_t kezdet, uint32_t hossz) {
  return (uint32_t)(millis() - kezdet) >= hossz;
}

bool ejjel() {
  time_t t = time(nullptr);
  if (t < 1700000000) return false;
  struct tm lt;
  localtime_r(&t, &lt);
  return EJJEL_TOL > EJJEL_IG ? (lt.tm_hour >= EJJEL_TOL || lt.tm_hour < EJJEL_IG)
                              : (lt.tm_hour >= EJJEL_TOL && lt.tm_hour < EJJEL_IG);
}

void hang(uint16_t f, uint16_t ms) {
  if (ejjel()) return;
  tone(BUZZER_PIN, f, ms);
  delay(ms + 30);
}

void kattanas() {
  if (!ejjel()) tone(BUZZER_PIN, 3000, 12);
}

const char *muvNev(Muvelet m) {
  switch (m) {
    case M_EBRESZT: return "Ebresztes";
    case M_INDIT: return "Inditas";
    case M_LEALLIT: return "Leallitas";
    case M_KENYSZER: return "Kenyszer-leallitas";
    default: return "Vissza";
  }
}

const char *muvNevHu(Muvelet m) {
  switch (m) {
    case M_EBRESZT: return "ébresztés";
    case M_INDIT: return "indítás";
    case M_LEALLIT: return "leállítás";
    case M_KENYSZER: return "kényszer-leállítás";
    default: return "";
  }
}

const char *tipusKod(Tipus t) {
  return t == WOL ? "wol" : t == LIBVIRT ? "libvirt" : "incus";
}

bool pingEgyszer(IPAddress ip, int ms) {
  int s = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
  if (s < 0) return false;
  struct timeval tv = {0, ms * 1000};
  setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  struct sockaddr_in cel = {};
  cel.sin_family = AF_INET;
  cel.sin_addr.s_addr = (uint32_t)ip;
  uint8_t ki[32] = {};
  struct icmp_echo_hdr *h = (struct icmp_echo_hdr *)ki;
  ICMPH_TYPE_SET(h, ICMP_ECHO);
  ICMPH_CODE_SET(h, 0);
  h->id = htons(0xEB12);
  h->seqno = htons(++pingSorszam);
  h->chksum = 0;
  h->chksum = inet_chksum(ki, sizeof(ki));
  bool jo = false;
  if (sendto(s, ki, sizeof(ki), 0, (struct sockaddr *)&cel, sizeof(cel)) > 0) {
    uint32_t kezdet = millis();
    while (!jo && !elmult(kezdet, ms)) {
      uint8_t be[128];
      struct sockaddr_in honnan;
      socklen_t hossz = sizeof(honnan);
      int n = recvfrom(s, be, sizeof(be), 0, (struct sockaddr *)&honnan, &hossz);
      if (n <= 0) break;
      struct ip_hdr *iph = (struct ip_hdr *)be;
      int fejHossz = IPH_HL(iph) * 4;
      if (n < fejHossz + (int)sizeof(struct icmp_echo_hdr)) continue;
      struct icmp_echo_hdr *v = (struct icmp_echo_hdr *)(be + fejHossz);
      jo = honnan.sin_addr.s_addr == cel.sin_addr.s_addr && ICMPH_TYPE(v) == ICMP_ER && v->id == h->id && v->seqno == h->seqno;
    }
  }
  close(s);
  return jo;
}

bool elE(IPAddress ip) {
  return pingEgyszer(ip, 700) || pingEgyszer(ip, 700);
}

void laptopCimFrissit() {
  IPAddress ip;
  if (WiFi.hostByName(LAPTOP_HOST, ip) && ip != IPAddress(0, 0, 0, 0)) laptopIp = ip;
  else laptopIp.fromString(LAPTOP_IP);
}

bool macOlvas(const char *s, uint8_t *mac) {
  return sscanf(s, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx", &mac[0], &mac[1], &mac[2], &mac[3], &mac[4], &mac[5]) == 6;
}

void magicKuld(const char *macSzoveg) {
  uint8_t mac[6];
  if (!macOlvas(macSzoveg, mac)) return;
  uint8_t csomag[102];
  memset(csomag, 0xFF, 6);
  for (int i = 0; i < 16; i++) memcpy(csomag + 6 + i * 6, mac, 6);
  IPAddress helyi = WiFi.localIP(), maszk = WiFi.subnetMask();
  IPAddress szoras(helyi[0] | ~maszk[0], helyi[1] | ~maszk[1], helyi[2] | ~maszk[2], helyi[3] | ~maszk[3]);
  IPAddress celok[] = {IPAddress(255, 255, 255, 255), szoras, laptopIp};
  for (IPAddress &c : celok) {
    for (uint16_t port : {9, 7}) {
      udp.beginPacket(c, port);
      udp.write(csomag, sizeof(csomag));
      udp.endPacket();
    }
  }
}

void ebreszt() {
  magicKuld(LAPTOP_MAC_WIFI);
  magicKuld(LAPTOP_MAC_KABEL);
  wolKuldve++;
  Serial.printf("magic packet #%u -> %s\n", wolKuldve, laptopIp.toString().c_str());
}

void piGombNyom() {
  pinMode(PI_EBRESZTO_PIN, OUTPUT);
  digitalWrite(PI_EBRESZTO_PIN, LOW);
  delay(300);
  pinMode(PI_EBRESZTO_PIN, INPUT);
  Serial.println("pi ebreszto impulzus");
}

bool ablakban(int perc, int kezdet, int hossz) {
  return (perc - kezdet + 1440) % 1440 < hossz;
}

void ejszakaBetolt() {
  beallitas.begin("ejszaka", true);
  ejszBe = beallitas.getBool("be", false);
  leallPerc = beallitas.getUShort("leall", EJSZAKA_ALAP_LEALL);
  ebresztPerc = beallitas.getUShort("ebreszt", EJSZAKA_ALAP_EBRESZT);
  beallitas.end();
}

void ejszakaMent() {
  beallitas.begin("ejszaka", false);
  beallitas.putBool("be", ejszBe);
  beallitas.putUShort("leall", leallPerc);
  beallitas.putUShort("ebreszt", ebresztPerc);
  beallitas.end();
}

int piEjszakaKer(const char *mit) {
  WiFiClient kliens;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(8000);
  http.setReuse(false);
  if (!http.begin(kliens, String(EJSZAKA_URL) + "/" + mit)) return -1;
  http.addHeader("X-Kulcs", GEPEK_KULCS);
  int kod = http.POST("");
  http.end();
  Serial.printf("pi ejszaka/%s -> %d\n", mit, kod);
  return kod;
}

void piEjszakaAllapot() {
  WiFiClient kliens;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(5000);
  http.setReuse(false);
  if (!http.begin(kliens, EJSZAKA_URL)) return;
  http.addHeader("X-Kulcs", GEPEK_KULCS);
  if (http.GET() == 200) {
    JsonDocument d;
    if (!deserializeJson(d, http.getString())) {
      strlcpy(piEjszAllapot, d["allapot"] | "?", sizeof(piEjszAllapot));
      strlcpy(piEjszOk, d["okok"][0] | "", sizeof(piEjszOk));
      piEjszFut = d["fut"] | false;
    }
  }
  http.end();
}

void ejszakaKezel() {
  static uint32_t utolsoLeallProbaMs = 0, utolsoEbresztProbaMs = 0;
  static uint8_t ebresztProbak = 0;
  if (!ejszBe || WiFi.status() != WL_CONNECTED) return;
  time_t t = time(nullptr);
  if (t < 1700000000) return;
  struct tm lt;
  localtime_r(&t, &lt);
  int perc = lt.tm_hour * 60 + lt.tm_min;

  if (ablakban(perc, leallPerc, LEALL_ABLAK_PERC) && t - utolsoLeallKeres > 20 * 3600 &&
      (!utolsoLeallProbaMs || elmult(utolsoLeallProbaMs, 60000))) {
    utolsoLeallProbaMs = millis();
    if (piEjszakaKer("leallit") == 200) {
      utolsoLeallKeres = t;
      strlcpy(piEjszAllapot, "var", sizeof(piEjszAllapot));
      piEjszFut = true;
    }
  }

  if (!ablakban(perc, ebresztPerc, EBRESZT_ABLAK_PERC) || t - utolsoEbresztKesz < 20 * 3600) {
    ebresztProbak = 0;
    return;
  }
  if (ebresztProbak && !elmult(utolsoEbresztProbaMs, PI_PROBA_MP * 1000UL)) return;
  IPAddress pi;
  pi.fromString(PI_IP);
  if (elE(pi)) {
    Serial.printf("pi ebren (%u impulzus)\n", ebresztProbak);
    utolsoEbresztKesz = t;
    ebresztProbak = 0;
    return;
  }
  if (ebresztProbak >= PI_PROBA_MAX) {
    Serial.println("pi nem ebredt fel");
    utolsoEbresztKesz = t;
    ebresztProbak = 0;
    hang(400, 350);
    return;
  }
  piGombNyom();
  ebresztProbak++;
  utolsoEbresztProbaMs = millis();
}

bool piLista() {
  WiFiClient kliens;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(5000);
  http.setReuse(false);
  if (!http.begin(kliens, GEPEK_URL)) return false;
  http.addHeader("X-Kulcs", GEPEK_KULCS);
  int kod = http.GET();
  if (kod != 200) {
    http.end();
    return false;
  }
  String test = http.getString();
  http.end();
  JsonDocument d;
  if (deserializeJson(d, test)) return false;
  uint8_t db = 1;
  for (JsonObject g : d.as<JsonArray>()) {
    if (db >= GEP_MAX) break;
    Gep &x = gepek[db++];
    strlcpy(x.nev, g["nev"] | "?", sizeof(x.nev));
    x.tipus = strcmp(g["tipus"] | "", "incus") == 0 ? INCUS : LIBVIRT;
    const char *a = g["allapot"] | "";
    x.allapot = strcmp(a, "fut") == 0 ? FUT : strcmp(a, "all") == 0 ? ALL : ISMERETLEN;
  }
  gepDb = db;
  if (kivalasztott >= gepDb) kivalasztott = gepDb - 1;
  return true;
}

int piMuvelet(const Gep &g, Muvelet m) {
  const char *mit = m == M_INDIT ? "indit" : m == M_LEALLIT ? "leallit" : "kenyszer";
  String url = String(GEPEK_URL) + "/" + tipusKod(g.tipus) + "/" + g.nev + "/" + mit;
  WiFiClient kliens;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(65000);
  http.setReuse(false);
  if (!http.begin(kliens, url)) return -1;
  http.addHeader("X-Kulcs", GEPEK_KULCS);
  int kod = http.POST("");
  http.end();
  return kod;
}

void frissit() {
  utolsoFrissitesMs = millis();
  if (WiFi.status() != WL_CONNECTED) return;
  piElerheto = piLista();
  if (piElerheto) piEjszakaAllapot();
  if (elmult(utolsoDnsMs, 60000) || utolsoDnsMs == 0) {
    utolsoDnsMs = millis();
    laptopCimFrissit();
  }
  if (folyMuv != M_EBRESZT) gepek[0].allapot = elE(laptopIp) ? FUT : ALL;
}

void eredmeny(bool jo, const char *szoveg) {
  folyMuv = M_NINCS;
  eredmenyJo = jo;
  strlcpy(eredmenySzoveg, szoveg, sizeof(eredmenySzoveg));
  eredmenyVegeMs = millis() + 3000;
  kepernyo = EREDMENY;
  utolsoGombMs = millis();
  if (jo) {
    hang(1200, 90);
    hang(1800, 90);
    hang(2400, 150);
  } else {
    hang(400, 350);
  }
}

bool muveletIndit(uint8_t gi, Muvelet m) {
  if (folyMuv != M_NINCS || gi >= gepDb) return false;
  Gep &g = gepek[gi];
  folyMuv = m;
  folyGep = gi;
  folyKezdetMs = millis();
  wolKuldve = 0;
  kepernyo = FOLYAMAT;
  utolsoGombMs = millis();
  kijelzoFrissit();
  if (m == M_EBRESZT) {
    g.allapot = ALL;
    laptopCimFrissit();
    ebreszt();
    return true;
  }
  int kod = piMuvelet(g, m);
  if (kod != 200) {
    eredmeny(false, kod == 409 ? "a Pi elutasitotta" : "a Pi nem valaszol");
    return false;
  }
  return true;
}

void folyamatKezel() {
  if (folyMuv == M_NINCS) return;
  uint32_t eltelt = (millis() - folyKezdetMs) / 1000;
  Gep &g = gepek[folyGep];
  if (folyMuv == M_EBRESZT) {
    if ((wolKuldve == 1 && eltelt >= 5) || (wolKuldve == 2 && eltelt >= 15) || (wolKuldve == 3 && eltelt >= 40)) ebreszt();
    if (g.allapot == FUT) {
      eredmeny(true, "Felebredt!");
      return;
    }
    if (eltelt >= EBRESZTES_MAX_MP) eredmeny(false, "Nem ebredt fel");
    if (elmult(utolsoFrissitesMs, 3000)) {
      utolsoFrissitesMs = millis();
      if (pingEgyszer(laptopIp, 800)) g.allapot = FUT;
    }
    return;
  }
  GepAllapot cel = folyMuv == M_INDIT ? FUT : ALL;
  if (elmult(utolsoFrissitesMs, 3000)) {
    utolsoFrissitesMs = millis();
    piLista();
  }
  if (folyGep < gepDb && gepek[folyGep].allapot == cel) {
    eredmeny(true, cel == FUT ? "Elindult!" : "Leallt.");
    return;
  }
  if (eltelt >= VM_MAX_MP) eredmeny(false, cel == FUT ? "Nem indult el" : "Nem allt le");
}

void menuEpit() {
  Gep &g = gepek[kivalasztott];
  menuDb = 0;
  if (g.tipus == WOL) menu[menuDb++] = M_EBRESZT;
  else if (g.allapot == FUT) {
    menu[menuDb++] = M_LEALLIT;
    menu[menuDb++] = M_KENYSZER;
  } else menu[menuDb++] = M_INDIT;
  menu[menuDb++] = M_VISSZA;
  menuPoz = 0;
}

void kozep(const char *s, int y, uint8_t meret) {
  int16_t x1, y1;
  uint16_t w, h;
  oled.setTextSize(meret);
  oled.getTextBounds(s, 0, 0, &x1, &y1, &w, &h);
  oled.setCursor((128 - w) / 2, y);
  oled.print(s);
}

void fejlec(const char *cim) {
  oled.setTextSize(1);
  oled.setTextColor(SSD1306_WHITE);
  oled.setCursor(0, 0);
  oled.print(cim);
  time_t t = time(nullptr);
  if (t > 1700000000) {
    char ora[8];
    struct tm lt;
    localtime_r(&t, &lt);
    strftime(ora, sizeof(ora), "%H:%M", &lt);
    oled.setCursor(98, 0);
    oled.print(ora);
  }
  oled.drawFastHLine(0, 10, 128, SSD1306_WHITE);
}

void allapotJel(int x, int y, GepAllapot a, bool inverz) {
  uint16_t c = inverz ? SSD1306_BLACK : SSD1306_WHITE;
  if (a == FUT) oled.fillCircle(x, y, 3, c);
  else if (a == ALL) oled.drawCircle(x, y, 3, c);
  else {
    oled.setCursor(x - 2, y - 3);
    oled.setTextColor(c);
    oled.print("?");
  }
}

void kijelzoFrissit() {
  if (!oledVan || kijelzoAlszik) return;
  oled.clearDisplay();
  oled.setTextColor(SSD1306_WHITE);
  char s[40];

  if (kepernyo == LISTA) {
    fejlec(WiFi.status() == WL_CONNECTED ? (piElerheto ? "EBRESZTO" : "EBRESZTO  !Pi") : "NINCS WIFI");
    if (kivalasztott < gorgetes) gorgetes = kivalasztott;
    if (kivalasztott >= gorgetes + 4) gorgetes = kivalasztott - 3;
    for (uint8_t i = 0; i < 4 && gorgetes + i < gepDb; i++) {
      uint8_t gi = gorgetes + i;
      const Gep &g = gepek[gi];
      int y = 13 + i * 13;
      bool sel = gi == kivalasztott;
      if (sel) oled.fillRect(0, y - 1, 128, 12, SSD1306_WHITE);
      allapotJel(5, y + 4, g.allapot, sel);
      oled.setTextColor(sel ? SSD1306_BLACK : SSD1306_WHITE);
      oled.setCursor(13, y + 1);
      oled.print(g.nev);
      oled.setCursor(g.tipus == WOL ? 110 : 116, y + 1);
      oled.print(g.tipus == WOL ? "WoL" : "VM");
    }
    if (gepDb == 1 && piElerheto) {
      oled.setTextColor(SSD1306_WHITE);
      kozep("(nincs VM a Pi-n)", 40, 1);
    }
  } else if (kepernyo == MENU || kepernyo == MEGEROSIT) {
    const Gep &g = gepek[kivalasztott];
    fejlec(g.nev);
    if (kepernyo == MEGEROSIT) {
      snprintf(s, sizeof(s), "%s?", muvNev(megerositendo));
      kozep(s, 20, 1);
      kozep("OK = igen", 38, 1);
      kozep("MOD = megse", 50, 1);
    } else {
      oled.setCursor(0, 14);
      oled.printf("allapot: %s", g.allapot == FUT ? "fut" : g.allapot == ALL ? (g.tipus == WOL ? "alszik/ki" : "all") : "?");
      for (uint8_t i = 0; i < menuDb; i++) {
        int y = 27 + i * 12;
        bool sel = i == menuPoz;
        if (sel) oled.fillRect(0, y - 1, 128, 11, SSD1306_WHITE);
        oled.setTextColor(sel ? SSD1306_BLACK : SSD1306_WHITE);
        oled.setCursor(4, y + 1);
        oled.print(muvNev(menu[i]));
      }
    }
  } else if (kepernyo == FOLYAMAT) {
    const Gep &g = gepek[folyGep];
    uint32_t eltelt = (millis() - folyKezdetMs) / 1000;
    uint32_t max = folyMuv == M_EBRESZT ? EBRESZTES_MAX_MP : VM_MAX_MP;
    kozep(g.nev, 4, 2);
    snprintf(s, sizeof(s), "%s... %u mp", muvNev(folyMuv), (unsigned)eltelt);
    kozep(s, 28, 1);
    oled.drawRect(4, 44, 120, 8, SSD1306_WHITE);
    oled.fillRect(6, 46, (int)(116 * min(eltelt, max) / max), 4, SSD1306_WHITE);
    if (folyMuv == M_EBRESZT) {
      snprintf(s, sizeof(s), "magic packet: %ux", wolKuldve);
      kozep(s, 55, 1);
    }
  } else if (kepernyo == EREDMENY) {
    kozep(eredmenyJo ? "KESZ" : "HIBA", 6, 2);
    kozep(eredmenySzoveg, 32, 1);
    kozep(gepek[folyGep].nev, 46, 1);
  }
  oled.display();
}

void kijelzoAltat(bool alszik) {
  if (!oledVan || kijelzoAlszik == alszik) return;
  kijelzoAlszik = alszik;
  oled.ssd1306_command(alszik ? SSD1306_DISPLAYOFF : SSD1306_DISPLAYON);
}

uint32_t szin(uint8_t r, uint8_t g, uint8_t b) {
  return pixel.Color(r, g, b);
}

void pixelKezel() {
  static uint32_t elozo = 0xFFFFFFFF;
  uint32_t c = 0;
  uint32_t m = millis();
  if (folyMuv != M_NINCS) {
    uint8_t v = (m / 8) % 256;
    v = v < 128 ? v * 2 : (255 - v) * 2;
    c = szin(0, v / 3, v);
  } else if (kepernyo == EREDMENY) {
    c = eredmenyJo ? szin(0, 200, 0) : szin(220, 0, 0);
  } else if (WiFi.status() != WL_CONNECTED) {
    c = (m / 1000) % 2 ? szin(0, 0, 120) : 0;
  }
  if (c != elozo) {
    pixel.setPixelColor(0, c);
    pixel.show();
    elozo = c;
  }
}

uint8_t gombOlvas(Gomb &g) {
  bool lent = digitalRead(g.lab) == LOW;
  uint8_t e = 0;
  if (lent && !g.lent) {
    g.lenyomvaMs = millis();
    g.hosszuVolt = false;
  } else if (lent && g.lent && !g.hosszuVolt && elmult(g.lenyomvaMs, 800)) {
    g.hosszuVolt = true;
    e = 2;
  } else if (!lent && g.lent && !g.hosszuVolt && elmult(g.lenyomvaMs, 30)) {
    e = 1;
  }
  g.lent = lent;
  return e;
}

void muveletValaszt(Muvelet m) {
  if (m == M_VISSZA) {
    kepernyo = LISTA;
  } else if (m == M_LEALLIT || m == M_KENYSZER) {
    megerositendo = m;
    kepernyo = MEGEROSIT;
  } else {
    muveletIndit(kivalasztott, m);
  }
}

void gombKezel() {
  uint8_t fel = gombOlvas(gombFel), le = gombOlvas(gombLe), ok = gombOlvas(gombOk), mod = gombOlvas(gombMod);
  if (!(fel || le || ok || mod)) return;
  utolsoGombMs = millis();
  if (kijelzoAlszik) {
    kijelzoAltat(false);
    return;
  }
  kattanas();
  if (kepernyo == FOLYAMAT) return;
  if (kepernyo == EREDMENY) {
    kepernyo = LISTA;
    return;
  }
  if (kepernyo == LISTA) {
    if (fel == 1 && gepDb) kivalasztott = (kivalasztott + gepDb - 1) % gepDb;
    if (le == 1 && gepDb) kivalasztott = (kivalasztott + 1) % gepDb;
    if (ok == 1) {
      menuEpit();
      kepernyo = MENU;
    }
    if (ok == 2 && gepek[kivalasztott].tipus == WOL) muveletIndit(kivalasztott, M_EBRESZT);
    if (mod) frissit();
  } else if (kepernyo == MENU) {
    if (fel == 1) menuPoz = (menuPoz + menuDb - 1) % menuDb;
    if (le == 1) menuPoz = (menuPoz + 1) % menuDb;
    if (ok == 1) muveletValaszt(menu[menuPoz]);
    if (mod == 1) kepernyo = LISTA;
  } else if (kepernyo == MEGEROSIT) {
    if (ok == 1) muveletIndit(kivalasztott, megerositendo);
    if (mod == 1) kepernyo = MENU;
  }
}

void apiAllapot() {
  JsonDocument d;
  d["pi"] = piElerheto;
  d["laptop_ip"] = laptopIp.toString();
  d["rssi"] = WiFi.RSSI();
  d["uptime"] = millis() / 1000;
  JsonObject f = d["folyamat"].to<JsonObject>();
  f["fut"] = folyMuv != M_NINCS;
  if (folyMuv != M_NINCS) {
    f["gep"] = folyGep;
    f["muvelet"] = muvNevHu(folyMuv);
    f["mp"] = (millis() - folyKezdetMs) / 1000;
  } else if (eredmenySzoveg[0]) {
    f["utolso"] = eredmenySzoveg;
    f["jo"] = eredmenyJo;
  }
  JsonObject e = d["ejszaka"].to<JsonObject>();
  char ido[6];
  e["be"] = ejszBe;
  snprintf(ido, sizeof(ido), "%02u:%02u", leallPerc / 60, leallPerc % 60);
  e["leall"] = ido;
  snprintf(ido, sizeof(ido), "%02u:%02u", ebresztPerc / 60, ebresztPerc % 60);
  e["ebreszt"] = ido;
  e["pi_allapot"] = piEjszAllapot;
  e["pi_ok"] = piEjszOk;
  e["pi_fut"] = piEjszFut;
  JsonArray a = d["gepek"].to<JsonArray>();
  for (uint8_t i = 0; i < gepDb; i++) {
    JsonObject g = a.add<JsonObject>();
    g["nev"] = gepek[i].nev;
    g["tipus"] = tipusKod(gepek[i].tipus);
    g["allapot"] = gepek[i].allapot == FUT ? "fut" : gepek[i].allapot == ALL ? "all" : "?";
  }
  String s;
  serializeJson(d, s);
  web.send(200, "application/json; charset=utf-8", s);
}

void apiMuvelet() {
  if (!WEB_KULCS[0] || web.arg("kulcs") != WEB_KULCS) {
    web.send(403, "text/plain; charset=utf-8", "Rossz kulcs.");
    return;
  }
  int gi = web.arg("gep").toInt();
  String mit = web.arg("mit");
  Muvelet m = mit == "ebreszt" ? M_EBRESZT : mit == "indit" ? M_INDIT : mit == "leallit" ? M_LEALLIT : mit == "kenyszer" ? M_KENYSZER : M_NINCS;
  if (m == M_NINCS || gi < 0 || gi >= gepDb || (m == M_EBRESZT) != (gepek[gi].tipus == WOL)) {
    web.send(400, "text/plain; charset=utf-8", "Érvénytelen kérés.");
    return;
  }
  if (folyMuv != M_NINCS || fuggoMuv != M_NINCS) {
    web.send(409, "text/plain; charset=utf-8", "Már fut egy művelet.");
    return;
  }
  fuggoGep = gi;
  fuggoMuv = m;
  web.sendHeader("Connection", "close");
  web.send(200, "text/plain; charset=utf-8", "Elindítva.");
}

void apiPiEbreszt() {
  if (!WEB_KULCS[0] || web.arg("kulcs") != WEB_KULCS) {
    web.send(403, "text/plain; charset=utf-8", "Rossz kulcs.");
    return;
  }
  piGombNyom();
  web.send(200, "text/plain; charset=utf-8", "Impulzus elküldve.");
}

bool idoOlvas(const String &s, uint16_t &perc) {
  int o, p;
  if (sscanf(s.c_str(), "%d:%d", &o, &p) != 2 || o < 0 || o > 23 || p < 0 || p > 59) return false;
  perc = o * 60 + p;
  return true;
}

void apiEjszaka() {
  if (!WEB_KULCS[0] || web.arg("kulcs") != WEB_KULCS) {
    web.send(403, "text/plain; charset=utf-8", "Rossz kulcs.");
    return;
  }
  uint16_t l = leallPerc, e = ebresztPerc;
  if ((web.hasArg("leall") && !idoOlvas(web.arg("leall"), l)) || (web.hasArg("ebreszt") && !idoOlvas(web.arg("ebreszt"), e)) || l == e) {
    web.send(400, "text/plain; charset=utf-8", "Hibás időpont.");
    return;
  }
  bool regiBe = ejszBe;
  if (web.hasArg("be")) ejszBe = web.arg("be") == "1";
  if (l != leallPerc || e != ebresztPerc) utolsoLeallKeres = 0;
  leallPerc = l;
  ebresztPerc = e;
  ejszakaMent();
  String valasz = ejszBe ? "Éjszakai leállás bekapcsolva." : "Éjszakai leállás kikapcsolva.";
  if (regiBe && !ejszBe && piEjszFut && piEjszakaKer("megse") == 200) {
    piEjszFut = false;
    valasz += " A Pi várakozó leállása megszakítva.";
  }
  web.send(200, "text/plain; charset=utf-8", valasz);
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

void setup() {
  Serial.begin(115200);
  pinMode(GOMB_FEL, INPUT_PULLUP);
  pinMode(GOMB_LE, INPUT_PULLUP);
  pinMode(GOMB_OK, INPUT_PULLUP);
  pinMode(GOMB_MOD, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(PI_EBRESZTO_PIN, INPUT);
  pinMode(NEOPIXEL_TAP, OUTPUT);
  digitalWrite(NEOPIXEL_TAP, HIGH);
  delay(10);
  pixel.begin();
  pixel.setBrightness(NEOPIXEL_FENY);
  pixel.clear();
  pixel.show();

  strlcpy(gepek[0].nev, LAPTOP_NEV, sizeof(gepek[0].nev));
  gepek[0].tipus = WOL;
  gepek[0].allapot = ISMERETLEN;
  laptopIp.fromString(LAPTOP_IP);
  ejszakaBetolt();

  Wire.begin();
  oledVan = oled.begin(SSD1306_SWITCHCAPVCC, OLED_CIM);
  if (oledVan) {
    oled.clearDisplay();
    oled.setTextColor(SSD1306_WHITE);
    kozep("EBRESZTO", 16, 2);
    kozep("csatlakozas...", 44, 1);
    oled.display();
  }

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
    if (oledVan) {
      kijelzoAltat(false);
      oled.clearDisplay();
      kozep("FRISSITES...", 28, 1);
      oled.display();
    }
  });
  ArduinoOTA.begin();

  web.on("/", [] { web.send_P(200, "text/html; charset=utf-8", WEB_OLDAL); });
  web.on("/api/allapot", apiAllapot);
  web.on("/api/muvelet", HTTP_POST, apiMuvelet);
  web.on("/api/pi-ebreszt", HTTP_POST, apiPiEbreszt);
  web.on("/api/ejszaka", HTTP_POST, apiEjszaka);
  web.onNotFound([] { web.send(404, "text/plain", "nincs ilyen"); });
  web.begin();

  Serial.printf("ebreszto: %s\n", WiFi.localIP().toString().c_str());
  frissit();
  utolsoGombMs = millis();
  hang(1500, 50);
  hang(2200, 50);
}

void loop() {
  ArduinoOTA.handle();
  web.handleClient();
  wifiKezel();
  if (fuggoMuv != M_NINCS) {
    Muvelet m = fuggoMuv;
    fuggoMuv = M_NINCS;
    kijelzoAltat(false);
    kivalasztott = fuggoGep;
    muveletIndit(fuggoGep, m);
  }
  gombKezel();
  folyamatKezel();
  if (folyMuv == M_NINCS) ejszakaKezel();
  pixelKezel();

  if (folyMuv == M_NINCS && elmult(utolsoFrissitesMs, ALLAPOT_MP * 1000UL)) frissit();
  if (kepernyo == EREDMENY && (int32_t)(millis() - eredmenyVegeMs) >= 0) kepernyo = LISTA;
  if (folyMuv == M_NINCS && elmult(utolsoGombMs, KIJELZO_ALVAS_MP * 1000UL)) {
    kijelzoAltat(true);
    if (kepernyo != LISTA) kepernyo = LISTA;
  }

  static uint32_t utolsoRajz = 0;
  if (elmult(utolsoRajz, 100)) {
    utolsoRajz = millis();
    kijelzoFrissit();
  }
  delay(5);
}
