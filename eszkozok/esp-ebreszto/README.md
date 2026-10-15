# Ébresztő – Wake-on-LAN gomb (Adafruit Feather ESP32 V2)

Gombnyomásra felébreszti a laptopot (Wake-on-LAN), és elindítja vagy leállítja a picloud virtuális gépeit.
Az OLED-en látszik, melyik gép fut.

## Használat

A kijelzőn egy géplista van. A **Laptop** mindig az első, alatta a Pi VM-jei (libvirt és Incus) következnek.
A tele kör azt jelzi, hogy a gép fut, az üres, hogy alszik vagy ki van kapcsolva.

| Gomb | Láb | Listában | Menüben |
|---|---|---|---|
| FEL / LE | 26 / 25 | választás | választás |
| OK | 15 | menü; **hosszan a laptopon: azonnali ébresztés** | végrehajtás / megerősítés |
| MÓD | 13 | lista frissítése | vissza / mégse |

- **Laptop → Ébresztés:** magic packetet küld a WiFi- és a vezetékes MAC-címre is, többször (0, 5, 15 és 40 mp-nél),
  és pinggel figyeli, mikor ébred fel (legfeljebb 2 percig).
- **VM → Indítás / Leállítás / Kényszer-leállítás:** a Pi `park-gepek` API-ján keresztül. A leállítást meg kell erősíteni.
  A normál leállításhoz a VM-nek kezelnie kell az ACPI-t. Az `alpine` VM-re ehhez `apk add acpid && rc-update add acpid`
  kell, addig csak a kényszer-leállítás működik.
- A NeoPixel művelet közben kéken lüktet, siker után zöld, hiba után piros. A zümmer éjjel (22–7) csendes.
- 90 mp tétlenség után a kijelző elalszik. Az első gombnyomás csak felébreszti.
- Webes felület: `http://ebreszto.local` (most: 192.168.1.179). Az első műveletnél elkéri a kulcsot, ez a `titkok.h` `WEB_KULCS` sora.

## A laptopon (egyszer, már be van állítva)

```
nmcli connection modify SAJAT-WIFI 802-11-wireless.wake-on-wlan magic
nmcli connection modify "1. vezetékes kapcsolat" 802-3-ethernet.wake-on-lan magic
```

- **WiFi-n** csak alvásból (suspend) ébred fel, teljesen kikapcsolt állapotból nem.
- **Kábellel** kikapcsolt állapotból is felébredhet, ha a BIOS-ban be van kapcsolva a Wake-on-LAN.

## A Pi-n

`park-gepek` (másolata: `pi/park-gepek`, eredetije: `szerverpark/skriptek/park-gepek`, a `kijelzo` modul telepíti):
`http://192.168.1.185:8097/gepek`, `X-Kulcs` fejléccel, és csak a 192.168.1.0/24 hálóról érhető el.
Kulcs: `sudo park-gepek --kulcs`, gépek listája: `sudo park-gepek --lista`.

## Feltöltés

```
cd ~/Dokumentumok/projectek/esp/ebreszto
./feltolt.sh usb      # USB-n (/dev/ttyACM0)
./feltolt.sh ota      # WiFi-n
./feltolt.sh figyel   # soros napló
```

A `titkok.h` (WiFi, webes kulcs, a Pi kulcsa) csak neked olvasható.

## Éjszakai leállás (picloud)

A weboldalon kapcsolható be (alapból KI), a leállás és az ébresztés ideje ott állítható (NVS-ben marad).

- **Leállás:** a beállított időben (30 perces ablak) `POST http://192.168.1.185:8097/ejszaka/leallit`. A Pi `park-ejszaka` kivárja a mentést, apt-ot, VM-et, SSH-belépést, nyitott Samba-fájlt, inhibitort és a terhelést (max. 3 óra, `/etc/park-ejszaka.conf`), aztán leáll. Kikapcsoláskor a várakozó leállást megszakítja (`/ejszaka/megse`).
- **Ébresztés:** a beállított időben (60 perces ablak), ha a Pi nem pingelhető, 300 ms-os LOW impulzus a GPIO32-n, legfeljebb 3-szor, 2 percenként.
- **Bekötés:** Feather **GPIO32** → Pi **5-ös tű (GPIO3)**, Feather **GND** → Pi **6-os tű (GND)**. A Pi EEPROM-jában `WAKE_ON_GPIO=1` (be van állítva).
- A Pi-n szándékosan nincs időzítő: ha a Feather nem él, a Pi bekapcsolva marad.
- Pi oldalon kézzel: `sudo park-ejszaka --okok | --allapot | --kihagy | --megse`.

OTA, ha a laptop tűzfala blokkol: a Pi-ről is mehet (ideiglenes `ufw allow from 192.168.1.179 to any port 47123`).
