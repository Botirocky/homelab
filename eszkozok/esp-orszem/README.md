# picloud őrszem (Adafruit Feather ESP32 V2)

Riasztó a picloud mellé. Egy különálló ESP32 **kívülről** figyeli a Pi-t, és ha gond van, a saját kijelzőjén, hanggal és
a telefonon szól. A Pi-hez nem nyúl.

## Mit csinál

- **Figyelés:** 15 mp-enként lekéri a `http://192.168.1.185/allapot.json`-t. Ha az nem jön, az SSH-portot próbálja, ha az sem,
  a routert. Állapotok: *rendben* · *elavult* (a `park-allapot` időzítő állt le) · *a gép él, a web nem* · *nem válaszol* ·
  *a router sem válaszol* (ilyenkor nem a Pi a hibás, nem riaszt).
- **Riasztás:** 2 perc teljes csend után:
  - az OLED-en villogó „PICLOUD LEÁLLT” jelenik meg,
  - a NeoPixel pirosan villog,
  - a zümmer szól, és 10 percenként ismétel (éjjel 22–7 között hallgat),
  - **ntfy**-értesítés megy a telefonra.
  Ha a Pi visszajön, azt is jelzi, a kiesés hosszával. Figyelmeztet akkor is, ha a Pi 5 percig csak félig él, vagy ha
  75 °C fölé melegszik. Ha épp nincs net, az értesítéseket sorba teszi, és később küldi el.
- **NeoPixel:** zöld = rendben (éjjel nem világít), narancs = figyelem, piros = nem válaszol, villogó piros = riasztás,
  villogó kék = nincs WiFi vagy a router sem válaszol.
- **Web:** `http://orszem.local` (most: 192.168.1.179): állapot, eseménynapló, teszt-értesítés, némítás.
- **BME280 (ha rákötöd):** a Pi körüli hőmérséklet, pára és légnyomás külön lapon, 40 °C fölött riaszt.

## Gombok

| Gomb | Láb | Rövid | Hosszú (1 mp) |
|---|---|---|---|
| FEL | 26 | előző lap | |
| LE | 25 | következő lap | |
| OK | 15 | riasztás közben: **némítás**, egyébként következő lap | |
| MÓD | 13 | következő lap | teszt-értesítés a telefonra |

A lapok maguktól is váltanak 8 mp-enként; kézi lapozás után 1 percig nem.

## Hardver (a meglévő bekötés, a wifi_scanner szerint)

OLED SSD1306 a Feather I2C-jén (SDA 22, SCL 20, RST 14, 0x3C); zümmer: 4; NeoPixel: 0 (táp: 2).
A BME280 ugyanerre az I2C-re köthető, a firmware magától felismeri.

**Az őrszem ne a Pi-ről kapja az áramot**, hanem külön töltőről vagy a Feather LiPo-akkujáról. Különben a Pi-vel együtt ő is leáll.

## Feltöltés

```
cd ~/Dokumentumok/projectek/esp/orszem
./feltolt.sh usb           # USB-n (/dev/ttyACM0)
./feltolt.sh ota           # WiFi-n, kábel nélkül
./feltolt.sh figyel        # soros napló
```

A `titkok.h` (WiFi-jelszó, ntfy-téma, OTA-kulcs) és a `build/` csak neked olvasható, ne oszd meg őket.
Új titkok: `rm titkok.h && ./feltolt.sh titkok`.

A kártyán eredetileg lévő wifi_scanner mentése: `mentes/esp32-pico-teljes-2026-09-29.bin`
(visszaállítás: `esptool --port /dev/ttyACM0 write-flash 0 mentes/esp32-pico-teljes-2026-09-29.bin`).

## Értesítések a telefonra

1. Telepítsd az **ntfy** appot.
2. Iratkozz fel a `titkok.h` `NTFY_TEMA` sorában lévő témára (`picloud-orszem-…`), ntfy.sh szerverrel.
3. Tartsd lenyomva a MÓD gombot 1 mp-ig, vagy a webes felületen nyomd meg a **Teszt-értesítés** gombot.

Discordra is küldhet: a `titkok.h`-ban `DISCORD_WEBHOOK`, utána `./feltolt.sh ota`.

## Beállítások (`config.h`)

| | Alap | |
|---|---|---|
| `KIESES_MP` | 120 | ennyi mp teljes csend után riaszt |
| `FIGY_MP` | 300 | ennyi ideig tartó félállapot után figyelmeztet |
| `EMLEKEZTETO_PERC` | 10 | a riasztó hang ismétlése (némításig) |
| `PI_MELEG_C` / `RACK_MELEG_C` | 75 / 40 | melegedés-riasztás |
| `EJJEL_TOL` / `EJJEL_IG` | 22 / 7 | éjjel nincs hang, és nem világít a zöld LED |
| `NEOPIXEL_FENY` | 25 | a NeoPixel fényereje (0–255) |
