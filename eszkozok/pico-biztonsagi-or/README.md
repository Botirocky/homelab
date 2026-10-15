# Biztonsági őr – Pico WH + picloud

A Pico az asztalon szól, ha valaki belép a picloudra, sudót használ, vagy a fail2ban kitilt valakit.
Külső szolgáltatás (Telegram, ntfy) nem kell, minden a helyi hálón megy.

## Mit jelez

| Esemény | Mikor hangos | Egyébként |
|---|---|---|
| SSH-belépés | ismeretlen felhasználó **vagy** ismeretlen IP | csendben számolja (te a laptopról, Tailscale-ről) |
| sudo | nem a `picloud` felhasználó futtatja | csendben számolja |
| rossz sudo-jelszó | mindig | – |
| fail2ban-tiltás | – | egy halk csipp, éjjel (22–7) néma |
| sikertelen SSH-próba | – | csak számláló |
| a Pi nem jelentkezik 3 percig | mély hang, a LED lassan villog | – |

Hangos riasztáskor az OLED kiírja, ki, honnan és mikor, a LED villog, és a buzzer 30 másodpercenként
újra szól (legfeljebb 5-ször), amíg nem nyugtázod.

Az OLED fejlécében: pontos idő, `Pi:ok` / `Pi:NINCS`, és `SD`, ha az SD-kártya működik.

**BOOTSEL gomb:** riasztás alatt nyugtáz, egyébként a főképernyő és a napló (utolsó 5 esemény) között vált.

## Kikapcsolás (pl. szerver-átépítés idejére)

Kikapcsolva az őr **nem riaszt semmire**: nem szól, a LED nem villog, és az sem riaszt, ha a picloud eltűnik.
Az eseményeket csendben tovább számolja és naplózza. Az OLED-en `KIKAPCSOLVA` áll. Az állapotot a Pico
flash-én tárolja (`kikapcsolva` fájl), így áramtalanítás után is kikapcsolva indul.

- **BOOTSEL 3 mp-ig nyomva:** ki/be (kikapcsoláskor ereszkedő, bekapcsoláskor emelkedő két hang)
- **Webes felület:** „Őrzés” kártya → Kikapcsolás / Bekapcsolás
- **A laptopról:** `./feltolt.sh ki`, `./feltolt.sh be` (`PICO_CIM`, alapból `192.168.1.20:8080`)

Bekapcsoláskor a Pico elfelejti az utolsó életjelet, így nem riaszt rögtön „Pi eltűnt”-tel: megvárja a picloud első jelentkezését.

## Webes felület

Böngészőből: `http://or.park.lan/` (a picloud Caddyje továbbítja, `sites.d/81-or.caddy`), vagy közvetlenül `http://192.168.1.20:8080/`. Első alkalommal elkéri a kulcsot
(a `titkok.py` KULCS-a, vagy `sudo park-or --kulcs` a Pi-n), és a böngésző megjegyzi.
3 másodpercenként frissül. Mutatja a riasztást (nyugtázni is lehet), hogy él-e a picloud, a számlálókat,
az utolsó 10 eseményt, és ha van SD-kártya, az SD-naplót is. Új riasztáskor a lap csippan egyet,
ha előtte rákattintottál valahova az oldalon (ezt a böngésző így szabja meg).

Maga az oldal (`pico/web.html`) kulcs nélkül is letölthető, de adat nincs benne. Minden adatkéréshez kell a kulcs.

Ha az OLED-re már nincs szükség, írd a `titkok.py`-ba, hogy `KIJELZO = False`. A Pico ezután nem
próbálja hajtani a kijelzőt, a hang, a LED és a webes felület ugyanúgy működik.

## Hardver: Pico WH + PiCowbell Adalogger

Az Adalogger rajta van a Picón, és két dolgot ad:
- **Valós idejű óra (PCF8523, CR1220 elemmel):** a Pico pontos idővel naplóz akkor is, ha nincs net,
  vagy a Pi nem fut. WiFi-n 6 óránként NTP-ről igazítja, a magyar nyári/téli időt maga számolja.
- **microSD:** a Pico **saját naplót** vezet a kártyára (`or_naplo.csv`). Ez akkor is megmarad,
  ha valaki bejut a Pi-re és ott törli a naplókat. Bekerül minden esemény, a nyugták, a Pico indulása
  (az okával együtt, pl. `WDT_RESET`), és az, ha a Pi eltűnt vagy visszajött.
  FAT32-re formázott kártya kell.

Az Adalogger által foglalt lábak: GP4/GP5 (óra, I2C0, 0x68), GP16–19 (SD), GP15 (kártyaérzékelő, ha
be van forrasztva). Ezeket **ne** használd másra.

| Alkatrész | Pico láb |
|---|---|
| OLED Data | GP11 (15. láb) |
| OLED Clk | GP10 (14. láb) |
| OLED DC (A0) | GP8 (11. láb) |
| OLED CS | GP9 (12. láb) |
| OLED Rst | GP12 (16. láb) |
| OLED VIN / GND | 3V3 OUT (36. láb) / GND (13. vagy 38. láb) – a 3Vo marad szabadon |
| Buzzer + / − | GP20 (26. láb) / GND (28. láb) |
| LED + (220–330 Ω ellenállással) / − | GP21 (27. láb) / GND (23. láb) |

Az OLED az Adafruit 1,3"-os SSD1306, a hátoldali átkötőkkel **I2C-módra** állítva (cím: 0x3D).
A kód szoftveres I2C-n hajtja (Clk = SCL a GP10-en, Data = SDA a GP11-en). A DC lábat magasra húzza,
ez választja ki a 0x3D címet, a Rst lábat induláskor egy impulzussal alaphelyzetbe teszi, a CS lábat alacsonyan tartja.
Az óra (Adalogger) külön buszon marad (GP4/GP5). Passzív és aktív buzzer is megy.
A lábak a `pico/main.py` elején átírhatók. Ha az óra vagy az SD hiányzik, a Pico nélkülük is fut.

## Telepítés

Ha a Picón még nincs MicroPython: BOOTSEL-lel dugd be, és másold rá a Pico W `.uf2` fájlját
(micropython.org/download/RPI_PICO_W).

```
./feltolt.sh titkok        # WiFi a laptop aktív kapcsolatából, kulcs
./feltolt.sh pico          # ssd1306 + main.py + titkok.py a Picóra
./feltolt.sh pi or.local:8080   # park-or a picloudra (vagy a Pico IP-je az OLED-ről)
./feltolt.sh teszt         # próbariasztás
```

A Pico `or.local` néven (mDNS) és az OLED alján kiírt IP-n érhető el, a 8080-as porton.
Ha az mDNS nem megy, a router DHCP-jében foglald le a Pico IP-jét, és azt írd a `/etc/park-or.conf`-ba.

## A Pi-n

- `park-or` (`/usr/local/bin`), `park-or.service`. A `journalctl -f` kimenetét (sshd, sudo) és a
  `/var/log/fail2ban.log`-ot figyeli. **PAM-hoz és sshd-hez nem nyúl**, a belépést nem befolyásolja.
- Konfig: `/etc/park-or.conf` (0600):
  - `PICO_CIM` – a Pico címe:portja
  - `KULCS` – ugyanaz, mint a Pico `titkok.py`-jában
  - `ISMERT_IP` – szóközzel elválasztott IP-k, ahonnan a belépés nem riaszt (a `100.x` Tailscale-címek
    alapból ismertek)
  - `ISMERT_FELHASZNALO` – alapból `picloud`
  - `CSEND_TOL` / `CSEND_IG` – éjszakai csend a halk jelzésekre (a hangos riasztás éjjel is szól)
- Parancsok: `park-or --teszt`, `--allapot`, `--nyugta`, `--naplo [N]` (az SD-napló), `--kulcs`,
  `sudo park-or --telepit`. A laptopról: `./feltolt.sh sdnaplo 100`.
- Napló: `journalctl -u park-or -f`.

## A Pico API-ja

A `GET /` a webes felület (kulcs nélkül). Minden más kéréshez `X-Kulcs` fejléc kell, rossz kulcsra 401 jön.

- `POST /esemeny` – `{"tipus","szint","ki","honnan","reszlet","ido"}`, a szint `hangos`, `halk` vagy `nema`
- `POST /eletjel`, `POST /nyugta`, `POST /kikapcs`, `POST /bekapcs`
- `GET /allapot` – kikapcsolva-e, idő, óra/SD állapota, számlálók, aktív riasztás, utolsó 10 esemény
- `GET /naplo?n=50` – az SD-napló utolsó n sora (max 500)
