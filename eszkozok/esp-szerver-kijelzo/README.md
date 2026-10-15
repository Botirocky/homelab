# Szerver-kijelző (CYD)

A picloud állapota egy ESP32-2432S028R („Cheap Yellow Display”, 2,8" 320×240) kijelzőn.

## Mit mutat

| Lap | Tartalom |
|---|---|
| Áttekintés | CPU, hőmérséklet, memória, konténerek (fut/összes); alul az utolsó mentés és a Pi-hole szűrési aránya |
| Tárhely | lemezek foglaltsága és szabad helye, Pi-hole, Tailscale, üzemidő, a kijelző WiFi-jele |
| Előzmény | CPU- és hőmérséklet-grafikon az utolsó 15 percről |
| Gondok | csak ha van gond: leállt/beteg konténerek, a `park-egeszseg` jelzései, meleg, tele lemez, régi mentés |

- **Fejléc:** gépnév, állapot (rendben / figyelem / hiba), a szerver órája.
- **Lapozás:** magától 12 mp-enként. Kézzel: a képernyő bal szélének érintése visszalapoz, máshol előre;
  a BOOT gomb előre lapoz (utána 1 percig nem lapoz magától).
- **Hosszú nyomás** (~1 mp, érintés vagy BOOT): a kijelző saját adatai – WiFi, IP, jelerősség, lekérések
  száma, utolsó adat kora, üzemidő, szabad memória, verzió. Érintésre vagy 20 mp után bezárul.
- **Fordított kép:** alapból 180°-kal elforgatva (`FORDITOTT` a `config.h`-ban, vagy `forditott=0/1`
  az SD-kártya `szerver_kijelzo.txt`-jében – ez felülírja).
- **Hiba esetén** magától a Gondok lapra ugrik.
- **Ha a Pi nem válaszol** (60 mp-ig nincs adat): piros teljes képernyős figyelmeztetés, hogy mióta.
- **RGB LED** a kártya hátulján: zöld = rendben, sárga = figyelem, piros = hiba, villogó piros = nem válaszol.
- **Éjszaka** (22–7 óra) a háttérfény lehalkul, és a zöld LED kialszik.

## Szerveroldal

A Pi-n a szerverpark `kijelzo` modulja fut (`park-allapot` + `park-allapot.timer`, 30 mp-enként), és a Caddy a
gép IP-jén kiszolgálja: `http://192.168.1.185/allapot.json`. Kézzel: `sudo park-allapot --kiir`.

## Bruce mellé, Launcherrel (SD-kártyáról)

A [Launcher](https://github.com/bmorcelli/Launcher) SD-kártyáról telepít és indít firmware-eket, így a Bruce és
a szerver-kijelző megfér egymás mellett. Bekapcsoláskor a Launcher kezdőképernyőjén érintéssel lehet belépni
és másik `.bin`-t választani; ha nem nyúlsz hozzá, a legutóbb telepített indul.

1. Ha a CYD-n még nincs Launcher, egyszer rá kell tenni: https://bmorcelli.github.io/Launcher/
   (böngészőből, USB-n; a CYD 2432S028R változatot válaszd). Ez a flash-ben lévő Bruce-t lecseréli – a Bruce
   `.bin`-jét is tedd az SD-kártyára, onnan a Launcher újra fel tudja rakni.
2. Az `sd-kartyara/` mappa két fájlját másold az SD-kártya gyökerébe:
   - `SzerverKijelzo-CYD.bin` – a firmware
   - `szerver_kijelzo.txt` – írd bele a WiFi nevét és jelszavát
3. Launcher → SD → `SzerverKijelzo-CYD.bin` → Install.

A beállítások az SD-kártya `szerver_kijelzo.txt` fájljából jönnek (`wifi_ssid`, `wifi_jelszo`, `url`, `nev`, `forditott`);
ha nincs ilyen fájl, a `config.h` értékei érvényesek. Az induló képernyő kiírja, melyikből dolgozik.

Új `.bin` készítése módosítás után:

```
arduino-cli compile --fqbn esp32:esp32:esp32 --export-binaries szerver_kijelzo
cp szerver_kijelzo/build/esp32.esp32.esp32/szerver_kijelzo.ino.bin szerver_kijelzo/sd-kartyara/SzerverKijelzo-CYD.bin
```

## Feltöltés USB-n (Launcher nélkül)

1. WiFi: `config.h` (`WIFI_SSID`, `WIFI_JELSZO`) vagy az SD-kártyán a `szerver_kijelzo.txt`. 2,4 GHz-es
   hálózat kell, az ESP32 5 GHz-re nem tud csatlakozni.
2. Könyvtárak (egyszer): `arduino-cli lib install TFT_eSPI XPT2046_Touchscreen ArduinoJson`
3. Fordítás és feltöltés a `projectek/esp` mappából:

```
arduino-cli compile --fqbn esp32:esp32:esp32 szerver_kijelzo
arduino-cli upload  --fqbn esp32:esp32:esp32 -p /dev/ttyUSB0 szerver_kijelzo
```

A kijelző beállításai a `build_opt.h`-ban vannak, nem a TFT_eSPI globális `User_Setup.h`-jában, így
a többi TFT_eSPI-s projektet nem érinti.

### Ha fehér vagy színes zaj a kép

A CYD-nek két változata van. A két USB-portos (USB-C + micro) típus ST7789 vezérlős. Ilyenkor:

```
cp eszkozok/build_opt_st7789.h build_opt.h
```

Ha a színek fordítottak (fekete helyett fehér), a `build_opt.h` utolsó sorát írd át:
`-DTFT_INVERSION_ON=1`.

## Fontok

A `fontok.h` az Inter betűtípusból készült, magyar ékezetekkel (ő, ű is), simított betűkkel.
Újragenerálás (pl. más méret vagy új karakter):

```
python3 eszkozok/font_gen.py fontok.h
```

Csak a `font_gen.py`-ban felsorolt karakterek jelennek meg; a nagy számjegy-font (`font_nagy`)
csak számokat és néhány jelet tud.
