# homelab

Egy otthoni szerverpark teljes forrása egy helyen: egy Raspberry Pi 4 és egy
x86-os „nagy gép”, a köréjük épült telepítővel, saját Debian-disztróval,
terminálos vezérlővel és a hozzájuk tartozó ESP32/Pico eszközökkel.

| Mappa | Mi ez |
|---|---|
| [`telepito/`](telepito/) | Moduláris bash telepítő friss Debian 13-ra: Docker, Caddy, Pi-hole, Nextcloud, AI (Ollama + Open WebUI), mentés (restic), figyelés és még ~30 választható modul. Belépési pont: `telepito.sh`, kezelés: `park` parancs. |
| [`os/`](os/) | **Botirocky** – Debian live-build alapú szerver-disztró és mentő ISO (BIOS + UEFI), automata telepítővel. |
| [`picloud-cli/`](picloud-cli/) | Terminálos dashboard és vezérlő a két géphez (`picloud --all`, `park`). |
| [`pihole/`](pihole/) | A Pi első beállítása: SD-kártya előkészítése, Pi-hole. |
| [`csevego/`](csevego/) | Böngészős, többfelhasználós házi chat (Python websockets). |
| [`elo/`](elo/) | „Élő szerverterem” bemutató oldal a szerverek állapotával. |
| [`eszkozok/`](eszkozok/) | A szerverekhez kapcsolódó mikrovezérlős eszközök: ESP32 állapotkijelző (CYD), ESP32 ébresztő (Wake-on-LAN, éjszakai leállás), ESP32 őrszem, Pico biztonsági őr (SSH/sudo riasztás). |

## Titkok

A repóban nincs valódi jelszó, kulcs, IP-cím vagy hálózatnév. Minden ilyen
értéket a gépen kell megadni:

- a telepítő a jelszavakat telepítéskor generálja a `/srv/szerverpark/.env`-be,
  a beállítások mintája: [`telepito/szerver.conf.pelda`](telepito/szerver.conf.pelda);
- az eszközöknél a `titkok.h.pelda` / `titkok.py.pelda` fájlt kell
  `titkok.h` / `titkok.py` néven lemásolni és kitölteni;
- a kijelzőnél a `szerver_kijelzo.txt.pelda` kerül `szerver_kijelzo.txt`
  néven az SD-kártyára.

A példákban szereplő `100.64.0.x`, `aa:bb:cc:…`, `pelda-tailnet` és
`SAJAT-WIFI` értékek helyőrzők.
