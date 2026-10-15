# picloud

Színes terminál-dashboard az otthoni Pi-szerverhez (`picloud`). Egyetlen
SSH-hívással lekéri és kirajzolja a **szolgáltatások**, a **rendszer**, a
**top folyamatok** és a **Tailscale** állapotát, majd egy összesített
**állapotsorral** zár. Tiszta Ruby — nincs gem-függőség.

```
┌─ picloud · picloud ──────────────────────────────────┐
│ Model    RPi 4 Model B Rev 1.5                       │
│ Idő      2026-09-27 17:51:02 Budapest NTP ✓          │
│ Uptime   31 minutes                                  │
│ Load     0.93 0.48 0.74                              │
│ CPU      1% (1800 MHz, 4 mag)                        │
│ Hőmérs.  55.0 °C (ventilátor ki)                     │
│ Táp      0.9360 V · rendben                          │
│ RAM      3786/7819 MB (48%)                          │
│ Disk /   37G/59G (66%)                               │
├─ fogyasztás (becslés) ───────────────────────────────┤
│ Most     ≈ 3,7 W                                     │
│ Naponta  0,09 kWh (≈ 3 Ft)                           │
│ Havonta  2,7 kWh (≈ 97 Ft)                           │
├─ hálózat ────────────────────────────────────────────┤
│ LAN      192.168.1.185/24 (eth0)                     │
│ Átjáró   192.168.1.1                                 │
│ Tailnet  100.64.0.1                               │
│ Publikus 203.0.113.50                                │
│ Forgalom ↓ 1.9 kB/s  ↑ 862 B/s                       │
│ Boot óta ↓ 19 MB  ↑ 9.4 MB                           │
│ Hotspot  1 kliens (wlan0)                            │
├─ internet (utolsó speedtest) ────────────────────────┤
│ Letölt.  90,1 Mbit/s                                 │
│ Feltölt. 92,0 Mbit/s                                 │
│ Ping     10,0 ms (2026-09-19 12:00)                  │
├─ tárolók · docker · pi-hole ─────────────────────────┤
│ PARKADAT 4.7 GB/15 GB (31%)                          │
│ Docker   25/25 konténer fut                          │
│ Pi-hole  3022 kérés, 349 blokkolva (11,5% ma)        │
├─ szolgáltatások ─────────────────────────────────────┤
│ ● csevego                                     active │
├─ tailnet ────────────────────────────────────────────┤
│ ● picloud (ez a gép)                   100.64.0.1 │
├─ állapot ────────────────────────────────────────────┤
│ ● OK                                                 │
└──────────────────────────────────────────────────────┘
```

## Használat

```sh
./picloud                    # alapból a "picloud" SSH-hostot nézi
./picloud --host local       # a saját géped (SSH nélkül)
./picloud --watch 5          # 5 mp-enként frissít (élő monitor)
./picloud --services csevego,tailscaled,sshd
./picloud --top 5            # 5 legnagyobb CPU-fogyasztó (0 = kikapcsolva)
./picloud --json             # nyers adat JSON-ként (dobozrajz helyett)
./picloud --log allapot.csv  # minden lekérdezés egy CSV-sorként hozzáfűzve
./picloud --no-color         # színek nélkül
```

A host `local`-on kívül bármilyen SSH-alias/cím lehet. A `local` közvetlenül a
gépeden futtatja ugyanazokat a próbákat — így teszteléshez és a saját géped
figyeléséhez is jó.

### Állapot és kilépési kód

A doboz alján az összesített állapot: `● OK`, `▲ figyelmeztetés` vagy `✗ hiba`
(meleg CPU, magas RAM/disk, vagy nem `active` szolgáltatás alapján). A kilépési
kód szkriptekhez is használható: **0** = OK, **1** = figyelmeztetés/hiba-állapot,
**2** = a host nem elérhető. Így cronból is riaszthatsz:

```sh
./picloud --host picloud --json >> /var/log/picloud.jsonl || echo "picloud gond!"
```

A `--log FILE` gépi feldolgozásra készít idősort (fejléc + soronként egy minta:
időbélyeg, host, elérhető, állapot, load1, hőmérséklet, RAM%, disk%, futó/összes
szolgáltatás) — `--watch`-csal együtt élő trendet naplóz.

## Hogyan működik

Egy kis `bash` probe-szkriptet küld a hostnak (`ssh <host> bash -s`), ami
`KULCS=ÉRTÉK` sorokat ír ki. Egy kapcsolat, egy kör (a CPU-terhelés és a
hálózati forgalom miatt 1 mp mintavétellel). Ha a host nem elérhető, tiszta
hibadobozt kapsz a valódi okkal. Amit nem talál (pl. nincs Docker vagy
speedtest), az a szekció egyszerűen kimarad.

| Szekció | Forrás |
|---|---|
| Rendszer | `uptime`, `/proc/stat` (CPU%), `cpufreq`, `vcgencmd` (hőm., magfeszültség, `get_throttled`), `free`, `df`, `timedatectl` (idő, NTP) |
| Ventilátor | `/etc/ventilator.conf` GPIO-ja + `pinctrl get` |
| Fogyasztás | Pi 5-ön **mért** (`vcgencmd pmic_read_adc`); Pi 4-en **becslés**: 2,7 W alap + 3,7 W × CPU% + 0,3 W/pendrive + 1,5 W/USB-SSD + 0,4 W hotspot + 0,5 W ventilátor. A Pi 4-ben nincs áramérzékelő – pontos értékhez USB-s mérő kell |
| Hálózat | alapértelmezett útvonal interfésze (LAN/IPv6/átjáró), `tailscale ip`, publikus IP (`api.ipify.org`, 10 percig gyorsítótárazva), `/sys/class/net` forgalom, 10.42.x hotspot kliensei |
| Internet | a Speedtest Tracker SQLite-adatbázisának utolsó sikeres mérése |
| Tárolók | a `/srv/tarolok/*` alá csatolt (1 GB-nál nagyobb) kötetek |
| Docker, Pi-hole | `docker ps`; a `pihole` konténer FTL-adatbázisából a mai kérések és blokkolások |

## Beállítás

- Alapértelmezett host felülírható: `PICLOUD_HOST=masik-gep ./picloud`
- Áramár a költséghez: `PICLOUD_FT_KWH=36` (Ft/kWh, alap 36)
- Speedtest-adatbázis: `PICLOUD_SPEEDTEST_DB=/srv/szerverpark/adat/speedtest/database.sqlite`
- Tárolók mappája: `PICLOUD_TAROLOK=/srv/tarolok`
- Telepítés PATH-ra: `ln -s "$PWD/picloud" ~/.local/bin/picloud`

Függőség: `ruby` (a Pi-oldalon csak szabványos `bash`, `systemctl`, opcionálisan
`tailscale`, `vcgencmd`, `pinctrl`, `sqlite3`, `docker`, `curl`). Kulcsos SSH-belépés ajánlott (`BatchMode`).

## Több gép egyszerre

```
picloud --all                 # picloud + nagy egymás mellett (PICLOUD_HOSTS felülírja)
picloud --host picloud,nagy   # ugyanez, kézzel megadva
```

Széles terminálban a dobozok egymás mellé kerülnek, keskenyben egymás alá.
`--json` több gépnél tömböt ad.

## `park` – a két szerver egy helyről

```
park                      mindkét gép állapota
park figyel [mp]          folyamatosan frissítve
park pi | park nagy       belépés ssh-val
park nagy naplo hirek     a nagy gép `sudo park naplo hirek` parancsa
park mind allapot         mindkét gépen
park pi -- df -h          tetszőleges shell-parancs
```

Telepítés: `ln -s "$PWD/park" ~/.local/bin/park`. A gépek SSH-nevei: `PARK_PI` (alap `picloud`), `PARK_NAGY` (alap `nagy`).

## `park dugalj` – a Pi Tapo-dugalja

A Pi egy Tapo P100 okosdugaljról kap áramot. A vezérlés a laptopról megy, mert a Pi-n futó
Home Assistant lekapcsolás után nem tudná visszakapcsolni.

```
park dugalj               a dugalj állapota, és hogy válaszol-e a Pi
park dugalj be            áram rá
park dugalj ki            a Pi rendes leállítása, utána áram le
park dugalj ujraindit     kemény újraindítás: áram le, 10 mp, áram fel
park dugalj or [be|ki]    az automatikus újraindító őr állapota / bekapcsolása / szüneteltetése
park dugalj or naplo      az őr naplója
```

Hitelesítés: `~/.config/park/tapo.env` (0600) – `TAPO_HOST`, `KASA_USERNAME`, `KASA_PASSWORD` (Tapo-fiók).
Az új Tapo-firmware TPAP titkosítást használ, ezt a kiadott python-kasa még nem tudja, a
[#1592-es PR](https://github.com/python-kasa/python-kasa/pull/1592) ága kell:

```
uv tool install "python-kasa @ git+https://github.com/ZeliardM/python-kasa@e7084472972f08f2e2235b342f3964aedbfaeb3b"
```

### Automatikus újraindító őr

A `park-dugalj-or` percenként fut (systemd user timer). Áramtalanítja, majd visszakapcsolja a Pi-t, ha
5 percig pingre sem válaszol, vagy pingel, de 15 percig se SSH-n, se weben nem érhető el.
Nem nyúl hozzá, ha a dugalj ki van kapcsolva, ha a laptop nincs otthon, ha a Feather éjszakai
ablakában vagyunk, 15 percig egy újraindítás után, és 24 órán belül 3 újraindítás után (akkor értesít).

```
ln -s "$PWD/systemd/park-dugalj-or.service" "$PWD/systemd/park-dugalj-or.timer" ~/.config/systemd/user/
systemctl --user daemon-reload
park dugalj or be
```

Beállítás környezeti változókkal: `OR_LE_PERC` (5), `OR_BENT_PERC` (15), `OR_TUREM_MP` (900),
`OR_NAPI_MAX` (3), `PARK_PI_IP`, `PARK_FEATHER`.
