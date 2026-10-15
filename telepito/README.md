# Szerverpark

Egyetlen paranccsal felállítható otthoni szerver: helyi **AI**, **fájltárolás**,
**hálózati megosztás**, **saját weboldalak**, **virtuális gépek**, és az egészet
körbevevő **figyelés + automatikus mentés**. Plusz egy script, ami a nagy gépet
összeköti a Raspberry Pi-vel.

Elsődlegesen **Debian 13 (Trixie)** rendszerre készült, de a csomagkezelő-réteg
disztró-független (apt · dnf · zypper · pacman).

---

## Tartalom

1. [Mit rak fel?](#mit-rak-fel)
2. [Telepítés](#telepítés)
3. [Beállítások](#beállítások)
4. [A `park` parancs](#a-park-parancs)
5. [Szép címek és DNS](#szép-címek-és-dns)
6. [AI: helyi és felhős modellek](#ai-helyi-és-felhős-modellek)
7. [Órarend (Kréta)](#órarend-kréta)
8. [Fájlok: Nextcloud és Samba](#fájlok-nextcloud-és-samba)
9. [Saját weboldalak](#saját-weboldalak)
10. [Virtuális gépek és test lab](#virtuális-gépek-és-test-lab)
11. [A Raspberry Pi összekötése](#a-raspberry-pi-összekötése)
12. [Mentés és visszaállítás](#mentés-és-visszaállítás)
13. [Mennyi vas kell hozzá?](#mennyi-vas-kell-hozzá)
14. [Fájlszerkezet](#fájlszerkezet)
15. [Hibakeresés](#hibakeresés)
16. [Biztonság](#biztonság)

---

## Mit rak fel?

| Modul | Mi kerül fel | Cím |
|---|---|---|
| `alap` | csomagok, időzóna, tűzfal, fail2ban, automatikus biztonsági frissítés, zram | – |
| `docker` | Docker Engine + Compose, közös `park` hálózat, naplókorlát | – |
| `proxy` | **Caddy** reverse proxy, automatikus HTTPS | 80 / 443 |
| `ai` | **Ollama** (helyi modellek) + **LiteLLM** (Claude/GPT/Gemini átjáró) + **Open WebUI** + **SearXNG** + opcionális **ComfyUI** | `ai.park.lan` |
| `fajlok` | **Nextcloud** (+MariaDB, Redis) és **FileBrowser** | `felho.park.lan`, `fajlok.park.lan` |
| `samba` | **Samba** – Windows/telefon/Linux fájlmegosztás a LAN-on | `\\szerver\megosztas` |
| `web` | statikus weboldalak kiszolgálása, több domainnel | `https://sajatdomain.hu` |
| `szinkron` | **FileBrowser** (webes fájlkezelő) + **Syncthing** (eszközök közti szinkron) | `fajlok.park.lan`, `szinkron.park.lan` |
| `selfhost` | **Dockge**, **Uptime Kuma**, **Homepage**, **Vaultwarden**, **Forgejo** | `kezdolap.park.lan` stb. |
| `media` | **Jellyfin** (film, sorozat) + **Navidrome** (zene) | `media.park.lan`, `zene.park.lan` |
| `iratok` | **Paperless-ngx** (OCR-es irattár), **Linkding** (könyvjelzők), **Wallabag** (cikkek) | `iratok.park.lan`, `konyvjelzo.park.lan`, `olvaso.park.lan` |
| `karbantartas` | **Watchtower** (konténer-frissítés), **Dozzle** (naplók), **Speedtest Tracker** | `naplo.park.lan`, `sebesseg.park.lan` |
| `vm` | **KVM/libvirt** VM-ek + **Incus** test lab + **Cockpit** webfelület | `vm.park.lan` |
| `mentes` | **restic** + napi automatikus mentés, ritkítással | 03:30 |

**Opcionális modulok** – alapból nem települnek, egyenként kérhetők
(`sudo ./telepito.sh --csak fotok,otthon`), vagy a confban `MOD_…="i"`:

| Modul | Mi kerül fel | Cím |
|---|---|---|
| `dns` | **Unbound** rekurzív DNS-feloldó a Pi-hole mögé (127.0.0.1#5335) | – |
| `otthon` | **Home Assistant** + **Mosquitto** MQTT (ESP32-szenzorokhoz) | `otthon.park.lan`, `:1883` |
| `fotok` | **Immich** fotókezelő; a tárolók csak olvasva, külső könyvtárként | `fotok.park.lan` |
| `konyvek` | **Kavita** (e-könyv, képregény) + **Audiobookshelf** (hangoskönyv, podcast) | `konyvek.park.lan`, `hangoskonyv.park.lan` |
| `hirek` | **Miniflux** (RSS) + **changedetection.io** (weboldal-figyelő) | `hirek.park.lan`, `valtozas.park.lan` |
| `eszkozok` | **Stirling-PDF** + **IT-Tools** | `pdf.park.lan`, `eszkozok.park.lan` |
| `offline` | **Kiwix** offline Wikipédia (`.zim` fájlokból) | `wiki.park.lan` |
| `penz` | **Actual Budget** (HTTPS kell neki: saját tanúsítvány vagy Tailscale) | `https://penz.park.lan` |
| `orarend` | **Órarend** a saját Kréta-fiókodból: helyettesítés/elmaradás/teremcsere-értesítés, számonkérések, házik, naptár-feed | `http://orarend.park.lan` |
| `jatek` | **Minecraft** (Paper/Fabric, Modrinth-modok) – csak elfogadott EULA-val | `:25565` |
| `botok` | saját **Python botok** konténerben, a `BOTOK_DIR` almappáiból | – |
| `ci` | **Forgejo Actions runner** (`runs-on: debian`) | a Forgejóban |
| `monitor` | **Beszel** – CPU/RAM/lemez/hőfok grafikonok, konténerenként is | `monitor.park.lan` |
| `jegyzetek` | **Memos** (gyors jegyzetek) + **Vikunja** (teendők, kanban, magyar felület) | `jegyzet.park.lan`, `teendo.park.lan` |
| `megosztas` | **PrivateBin** (végponttól titkosított paste, lejárattal) + **Excalidraw** (rajztábla) | `paste.park.lan`, `rajz.park.lan` |
| `leltar` | **Homebox** – háztartási leltár, QR-címkék, garanciák | `leltar.park.lan` |
| `lemez` | **Scrutiny** – a lemezek S.M.A.R.T. adatai és hőfoka, hibánál ntfy | `lemez.park.lan` |
| `cronfigyelo` | **Healthchecks** – a `park-mentes` minden futáskor jelez; ha kimarad vagy hibával áll le, ntfy-on szól | `cron.park.lan` |
| `vedelem` | **CrowdSec** + tűzfal-bouncer (a Docker-portokra is), LAN/tailnet fehérlistán | – |
| `kijelzo` | **park-allapot** – a gép állapota JSON-ban, 30 mp-enként (ESP32 CYD kijelzőnek); **park-gepek** – VM-ek indítása/leállítása HTTP-n, kulccsal (ESP32 WoL-gomb); **park-ejszaka** – kíméletes éjszakai leállás (megvárja a mentést, apt-ot, VM-et, belépést, Samba-fájlt), az ESP32 indítja és ébreszti GPIO3-on | `http://<ip>/allapot.json`, `http://<ip>:8097/gepek` |
| `sso` | **Tinyauth** közös belépés az `SSO_VEDETT` címek elé | `auth.park.lan` |
| `leallas` | **park-leallas** – `sudo shutdown`/`reboot` előtt sorban leállítja a futó konténereket (előbb az appokat, aztán az adatbázisokat) és memóriával együtt elmenti a VM-eket, indításkor pontosan ezeket indítja vissza; kikapcsoláskor (nem újraindításkor, és nem az éjszakai leállásnál) a Tapo P100 dugaljat is lekapcsolja egy időzítővel, a nagygépet pedig SSH-n leállítja és induláskor WoL-lal ébreszti (csak ha a nagygép kábelen van) | – |
| `portal` | **park-portal** – captive portál a `picloud-net` hotspothoz: új eszköz csak e-mail + wifi-jelszó megadása után, **ntfy-értesítésben jóváhagyva** kap netet (30 napra, MAC alapján; addig csak DNS és a portál). Kezelés: `park-portal lista|eszkozok|enged|tilt`, ill. `http://<tailscale-ip>:8077/admin` | `http://10.42.0.1:8077` |

Kis gépen (Pi 4, 8 GB) nem fér el mind egyszerre: az Immich, a Home Assistant,
a Stirling-PDF és a Minecraft a legnagyobb falatok (egyenként 0,5–2,5 GB).

A modulok külön-külön is telepíthetők, és a telepítő **idempotens**: bármikor
újrafuttatható, a meglévőt kihagyja, a jelszavakat nem generálja újra.

---

## Telepítés

**Előfeltétel:** friss Debian 13 (netinst, asztali környezet nélkül, SSH
szerverrel), root vagy sudo hozzáférés.

```bash
# 1) másold fel a szerverre
scp -r szerverpark/ root@szerver:/root/

# 2) PRÓBA mód – megmutatja, mit tenne, de semmit nem módosít (root sem kell)
ssh root@szerver
cd /root/szerverpark
./telepito.sh --proba

# 3) éles telepítés – a varázsló végigkérdezi a fontos dolgokat
sudo ./telepito.sh
```

További kapcsolók:

```bash
sudo ./telepito.sh --lista          # mit tud telepíteni
sudo ./telepito.sh --csak ai,web    # csak a felsorolt modulok
sudo ./telepito.sh --auto           # kérdés nélkül, /etc/szerverpark.conf alapján
sudo ./telepito.sh --conf sajat.conf
```

A telepítő a végén kiírja az összes címet, a hozzájuk tartozó hosts-sorokat a
saját IP-ddel, és hogy hol vannak a generált jelszavak.

Napló: `/var/log/szerverpark-telepito.log`

### Csak a kezelő-szkriptek (`skriptek-telepito.sh`)

Ha nem a teljes self-hosting stacket akarod, csak a `park` kezelő- és
felügyeleti eszközöket egy gépre, ez a kisebb telepítő letölti a szükséges
csomagokat (Docker, restic, curl, jq, git), felrakja a szkripteket, és beállítja
az időzítőket, a bash-kiegészítést meg a belépési üzenőfalat:

```bash
sudo ./skriptek-telepito.sh              # varázsló: letölt + beállít mindent
sudo ./skriptek-telepito.sh --proba      # dry-run (root sem kell)
sudo ./skriptek-telepito.sh --auto       # kérdés nélkül
sudo ./skriptek-telepito.sh --no-docker  # a Docker kihagyása
sudo ./skriptek-telepito.sh --csak szkriptek,idozitok   # csak egyes lépések

./skriptek-telepito.sh --allapot         # mi van telepítve
./skriptek-telepito.sh --onteszt         # a felrakott szkriptek próbája
sudo ./skriptek-telepito.sh --frissit    # csak a szkriptek frissítése a repóból
sudo ./skriptek-telepito.sh --eltavolit  # szkriptek/időzítők/üzenőfal eltávolítása
```

Beállítja: `park-orzo.timer` (5 perces őrszem), `park-egeszseg.timer` (napi
08:00 egészség-jelentés), a tároló-automatikát (`park-tarolo`), a hálózati
automatikát (`park-halozat`), a `park` bash-kiegészítést, a belépési üzenőfalat,
és generál egy `.env`-et a titkokkal. Lépések listája: `--lista`.

---

## Beállítások

A válaszaidat a telepítő a `/etc/szerverpark.conf` fájlba menti, és `--auto`
módban onnan olvassa. Minta és magyarázat: **`szerver.conf.pelda`**.

A legfontosabbak:

| Beállítás | Mit jelent |
|---|---|
| `PARK_DIR` | ide kerülnek a beállítások és a compose-fájlok (alap: `/srv/szerverpark`) |
| `ADAT_DIR` | **ide kerül minden adat** – ide tedd a nagy lemezt, pl. `/mnt/adatlemez` |
| `BELSO_DOMAIN` | a belső nevek vége (alap: `park.lan`) |
| `PUBLIKUS_DOMAIN` | ha lesz internetről elérhető weboldal |
| `AI_MODELLEK` | üresen hagyva a gép méretéhez válogat |
| `MENTES_CEL` | hová mentsen a restic |
| `MOD_*` | melyik modul fusson |

A generált jelszavak külön fájlban vannak: `/srv/szerverpark/.env` (csak root
olvashatja). Kiíratásuk: `park jelszavak`.

---

## A `park` parancs

```
park allapot                  mi fut, mennyi hely van, mikor lesz mentés
park indit [stack]            indítás (stack nélkül: mind)
park leallit [stack]          leállítás
park ujra <stack>             újraindítás
park naplo <stack>            élő napló
park frissit [stack]          konténer-képek frissítése + újraindítás
park takarit                  régi képfájlok, árva kötetek törlése

park koszonto                 belépési üzenőfal (szolgáltatások, állapot)
park egeszseg [--json]        állapot-ellenőrzés (kilépési kóddal riaszt)
park orzo [--szaraz]          leállt konténerek újraindítása most
park ertesit <cím> <üzenet>   kézi/teszt értesítés

park oldal <domain>           ÚJ WEBOLDAL felvétele egy paranccsal
park tavoli <név> <ip:port>   másik gép szolgáltatása park.lan néven
park tars                     a társgép (Raspberry Pi) állapota

sudo park-figyelo             az Uptime Kuma feltöltése: admin fiók, ntfy
                              értesítő és figyelő minden futó szolgáltatáshoz
sudo park-figyelo --frissit   csak a hiányzó figyelők felvétele

park mentes                   azonnali mentés
park mentesek                 a meglévő mentések listája
park jelszavak                a generált jelszavak

park ai-katalogus             letölthető AI modellek (méret, RAM-igény)
park ai-modellek              mi van fent (helyi + felhős)
park ai-modell <név>          modell letöltése
park ai-torol <név>           modell törlése
park ai-kulcs <hol> <kulcs>   felhős kulcs (anthropic/openai/gemini/…), előbb kipróbálja
park ai-kulcs lista           mely szolgáltatóhoz van kulcs (`<hol> torol` törli)

park lab uj <név> [kép]       test-lab gép másodpercek alatt (Incus)
park lab lista|shell|torol <név>
park lab pillanatkep <név> [cimke]
park lab vissza <név> <cimke>
park vm lista                 libvirt VM-ek
park vm uj <név> <iso>        VM telepítése ISO-ból
park vm indit|leallit|konzol|torol <név>
park vm iso <url>             ISO letöltése a gyűjteménybe
```

---

## Felügyelet és riasztás

A telepítő segéd-szkripteket is felrak a `park` mellé (a `skriptek/`
mappából, `/usr/local/bin/`-be):

- **`park-koszonto`** – belépési üzenőfal: minden SSH-belépéskor egy
  pillantással mutatja a szolgáltatások címeit, a konténerek állapotát, a
  rendszert (RAM/lemez/terhelés) és az utolsó mentést. Szándékosan gyors (nincs
  hálózati hívás), a telepítő a `/etc/profile.d`-be teszi, hogy magától
  megjelenjen. Kézzel: `park koszonto`.


- **`park-egeszseg`** – végigméri a rendszert: futnak-e a `park-` konténerek
  (és egészségesek-e), tele van-e a lemez, szűkös-e a RAM/terhelés, friss-e a
  mentés, elérhető-e a társgép. A **kilépési kód** `0` = rendben, `1` =
  figyelmeztetés, `2` = hiba – így cronból magától riaszthat:

  ```sh
  park egeszseg               # olvasható jelentés
  park egeszseg --json        # gépi feldolgozásra
  park egeszseg --csendes --ertesit   # csak gond esetén ír + értesít (cronhoz)
  ```

- **`park-orzo`** – őrszem: a leállt / egészségtelen konténereket megpróbálja
  újraindítani, és riaszt, ha nem sikerül. A telepítő **5 percenkénti systemd
  időzítőt** kapcsol be hozzá (`park-orzo.timer`). Kézzel: `park orzo`
  (`--szaraz` csak megmutatja, mit tenne).
  A frissen indult, még „egészségtelen" konténereket **türelmi időn belül békén
  hagyja** (`ORZO_TUREM`, alapból 600 mp): egy Open WebUI vagy Paperless percekig
  indul egy kis gépen, és ha közben újraindítanánk, sosem érne a végére. Ami
  viszont egyáltalán nem fut, azt azonnal elindítja. A kort a gép ébrenlétéhez
  is méri, így az óra nélküli gépek bootkori időugrása nem zavarja meg.

- **`park-tarolo`** – a bedugott háttértárakat magától felismeri és felcsatolja
  a `/srv/tarolok/<címke>` alá, majd Sambán megosztja őket (Windowsból és
  Linuxból is látszanak). **Soha nem formáz**: amit nem ismer fel, azt jelenti és
  békén hagyja. ext4/btrfs/xfs/exFAT/NTFS/FAT32 kezelve; udev-szabály indítja, így
  bedugásra magától történik minden. Kézzel: `park-tarolo lista | auto | lecsatol <név>`.

  **Védelem a kihúzott lemez ellen:** a `sudo park-tarolo vedelem` (a `--telepit`
  is lefuttatja) minden olyan tároló csatolási pontját, amire a beállítások
  hivatkoznak (pl. `NC_FAJL_DIR=/srv/tarolok/PARKADAT/felho`), üresen zárolja
  (`chattr +i`). Ha a lemez nincs bent, a konténerek így nem a rendszerlemezen
  kezdenek új, üres adatmappát, hanem el sem indulnak. A `park-orzo` ilyenkor
  egyszer szól („hiányzó tároló”), a `park-mentes` hibával kimarad. Amint a lemez
  felcsatolódik, a várakozó konténerek maguktól elindulnak (a `park-tarolo`
  csatolása, fstab-os lemeznél a `park-tarolo-utana@` egység indítja őket).
  Kézzel: `sudo park-tarolo inditas /srv/tarolok/<név>`.

- **`park-halozat`** – ha van bedugva hálózati kábel, a gép **arra vált**
  (a vezetékes kapcsolat kisebb útvonal-metrikát kap, mint a wifi), és a belső
  `*.park.lan` nevek automatikusan az új IP-re állnak át. Egy NetworkManager
  dispatcher-hook figyeli az IP-változást, plusz induláskor is igazít.
  Kézzel: `park-halozat allapot | dns-frissit`.

- **`park-ertesito`** – egységes értesítő, amin a fenti kettő riaszt. Egyszerre
  több csatornára küld; elég egyet beállítani a konfigban (vagy a `.env`-ben):

  ```ini
  NTFY_URL="https://ntfy.sh/valami-titkos-topic"   # telefon-push
  DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
  ERTESITO_EMAIL="te@pelda.hu"
  ```

  Teszt: `park ertesit --teszt`.

Napi állapot-jelentéshez pl. egy cron- vagy systemd-időzítő:
`park egeszseg --csendes --ertesit`.

---

## Szép címek és DNS

A szolgáltatások `*.park.lan` néven érhetők el. Ehhez a neveknek a szerver
IP-jére kell mutatniuk. Két megoldás:

**1) DNS (ez a jó):** AdGuard Home a Raspberry Pi-n vagy a router DNS-e:

```
*.park.lan  →  192.168.1.50
```

Az [összekötő script](#a-raspberry-pi-összekötése) ezt automatikusan fel tudja
venni a Pi AdGuardjába.

**2) hosts fájl** minden kliensen (Linux/macOS: `/etc/hosts`, Windows:
`C:\Windows\System32\drivers\etc\hosts`):

```
192.168.1.50  kezdolap.park.lan ai.park.lan ai-api.park.lan kereso.park.lan
192.168.1.50  felho.park.lan fajlok.park.lan vm.park.lan
192.168.1.50  dockge.park.lan figyelo.park.lan jelszo.park.lan git.park.lan
```

A telepítő a végén a saját IP-ddel kiírja ezeket a sorokat.

---

## AI: helyi és felhős modellek

**Helyi modellek** (Ollama): a telepítő a gép RAM/VRAM mérete alapján
automatikusan válogat egy csomagot – csevegő, kódoló, gondolkodó, képértő és
beágyazó modellt.

```bash
park ai-katalogus              # 24 modell: méret, RAM-igény, mire jó
park ai-modell qwen2.5:14b
park ai-torol llava:7b
```

**Felhős modellek** (Claude, GPT, Gemini, Groq, Mistral, DeepSeek, xAI,
OpenRouter): ezek **nem futnak a szerveren** – zárt modellek, API-n át érhetők
el. Egy **LiteLLM** átjáró fogadja őket, így ugyanabban az Open WebUI-ban
jelennek meg, mint a helyiek:

```bash
park ai-kulcs anthropic sk-ant-...
park ai-kulcs gemini AIza...
```

A konfig `*` mintákkal dolgozik (`anthropic/*`, `openai/*`…), így egy új modell
megjelenésekor nem kell hozzányúlni semmihez – elég a nevét beírni.

Az átjáró egyben **közös OpenAI-kompatibilis API** minden modellhez:

```bash
curl http://ai-api.park.lan/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_KULCS" \
  -d '{"model":"claude-sonnet-5","messages":[{"role":"user","content":"szia"}]}'
```

**Extrák a felületen:** SearXNG webkeresés · dokumentum-kérdezés (RAG) helyi
beágyazó modellel · hangüzenet → szöveg (Whisper) · képgenerálás (ComfyUI,
`AI_KEPGENERALAS="i"`, erős GPU kell).

---

## Órarend (Kréta)

Az `orarend` modul egy kis saját szolgáltatás (`park-orarend`, Python, külső
függőség nélkül), amely a **saját Kréta-fiókoddal** belép, és letölti az
órarendet (ez és a jövő hét), a bejelentett számonkéréseket és a házikat.

- **Cím:** a tailneten valódi tanúsítvánnyal
  `https://<gép>.<tailnet>.ts.net:8444` (`tailscale serve`, a port:
  `ORAREND_TS_PORT`), itthon `http://orarend.park.lan` is. Saját belépése van:
  a jelszó a `.env`-ben az `ORAREND_JELSZO`, a böngésző 90 napig emlékszik.
  A kezdőlapon élő kártya mutatja a mostani és a következő órát.
- **Első lépés:** a `/belepes` oldalon add meg az oktatási azonosítót, a
  jelszót és az intézmény azonosítóját (a Kréta-címed eleje, pl.
  `klik012345678`). Ha a Kréta captchát kér, ugyanott van **kézi belépés**: a
  böngésződben lépsz be, és a végén kapott `…oauthredirect?code=…` címet
  beilleszted.
- **Belépés fájlból:** a Pi-n az `adat/orarend/kreta.txt` fájlba írd be a
  `FELHASZNALO=`, `JELSZO=` és `ISKOLA=` sort (vagy csak a három adatot
  egymás alá, ebben a sorrendben; `=` helyett `:` vagy szóköz is jó). Az iskolánál elég a név, a
  kódot a szerver kikeresi; ha több iskola is illik rá, a hibaüzenetben
  felsorolja a kódokat. A szerver 15 másodpercen belül belép, és a fájlt
  törli. Hiba esetén `kreta.txt.hibas` néven félreteszi, és az oldalon
  kiírja, mi volt a gond. Mintafájl: `kreta.txt.minta`.
- **Frissítés:** tanítási napokon 6 és 18 óra között 20 percenként, este
  óránként, éjjel 3 óránként. A „Frissítés most” gomb azonnal frissít.
- **Értesítés (ntfy):** ha egy óra elmarad, helyettesítés vagy teremcsere
  van, új számonkérés vagy házi jön. Este 19:00-kor összefoglalót is küld a
  holnapi napról. Az `NTFY_URL`-t használja; külön csatornát az
  `ORAREND_NTFY_URL` ad, kikapcsolni az `ORAREND_ERTESITES=ki` lehet.
- **Naptár:** az oldal alján lévő `.ics` linkre a telefon naptára
  feliratkozhat (titkos kulcs a linkben: `ORAREND_ICS_KULCS`).
- **JSON:** `/api/orarend.json` (például kijelzőhöz).
- A token és, ha bejelölöd, a Kréta-jelszó az `adat/orarend/` alatt van
  (0600). A jelszó csak akkor kell, ha a frissítő token lejár.

## Fájlok: Nextcloud és Samba

| Mire | Hol | Megjegyzés |
|---|---|---|
| Telefonos szinkron, megosztás linkkel, naptár | Nextcloud – `felho.park.lan` | belépés: a `SMB_FELHASZNALO` név, jelszó a `.env`-ben |
| Gyors webes fájlkezelő | FileBrowser – `fajlok.park.lan` | első belépés `admin`/`admin` – **írd át** |
| Windows/telefon fájlmegosztás a LAN-on | Samba – `\\szerver\megosztas` | csak a helyi hálózatról, kívülről zárva |

A Samba és a FileBrowser **ugyanazt a mappát** látja (`adat/megosztas`), tehát
amit a hálózati meghajtóra másolsz, az böngészőből is elérhető.

---

## Saját weboldalak

```bash
park oldal sajatdomain.hu
# fájlok ide: /srv/szerverpark/web/sajatdomain.hu/
```

A Caddy automatikusan kér Let's Encrypt tanúsítványt. Ehhez kell:

1. a domain **A-rekordja** a lakás IP-jére mutasson,
2. a routeren a **80** és **443** port át legyen irányítva a szerverre.

---

## Virtuális gépek és test lab

Két eszköz, két feladatra:

| | **KVM / libvirt** | **Incus (test lab)** |
|---|---|---|
| Mire | „igazi" VM bármilyen ISO-ból: Windows, BSD, régi disztró | gyors próbagépek kész rendszerképből |
| Indulás | percek (telepíteni kell) | ~10 másodperc |
| Kezelés | `park vm …` vagy Cockpit | `park lab …` |

```bash
# Test lab
park lab uj teszt1                      # Debian 13 VM ~10 mp alatt
park lab uj gentoo images:gentoo/openrc --vm
park lab shell teszt1
park lab pillanatkep teszt1 tiszta      # mentés a piszkálás előtt
park lab vissza teszt1 tiszta           # 5 másodperc, és minden olyan, mint volt

# Igazi VM ISO-ból
park vm iso https://.../debian-13.0.0-amd64-netinst.iso
park vm uj tesztgep debian-13.0.0-amd64-netinst.iso
```

A **Cockpit** webfelületen (`vm.park.lan`) kattintgatva is csinálhatsz VM-et, és
a böngészőben látod a képernyőjüket. Belépés a rendszer-felhasználóddal.

### VM-ek a házi hálózaton (bridge)

Alapból a VM-ek **NAT** mögött vannak: kifelé mennek, de a hálózat többi gépe
nem látja őket. Ez a biztonságos alapértelmezés.

Ha egy VM saját LAN-IP-t kapjon, hálózati **bridge** kell. Ezt a telepítő
**szándékosan nem állítja be**: ha SSH-n keresztül rontod el, megszakad a
kapcsolat a szerverrel. Csak akkor csináld, ha fizikailag hozzáférsz a géphez:

```bash
# /etc/network/interfaces.d/br0
auto br0
iface br0 inet dhcp
    bridge_ports enp3s0        # a VALÓDI hálókártyád: ip -br link
    bridge_stp off
    bridge_fd 0
```

Utána a VM-nek `--network bridge=br0`, az Incusnak macvlan vagy bridge-elt profil.

---

## A Raspberry Pi összekötése

> **Csak egy gép van?** Akkor ez a fejezet kimarad: az `osszekotes.sh` két
> gépet kapcsol össze. Egygépes üzemben a mentés gépen kívüli példányáról
> külön kell gondoskodni – a legegyszerűbb, ha egy másik gép (pl. a laptop)
> **húzza** le a repót: nem kell hozzá semmit nyitni a szerveren, és nem kell
> éjjel futnia. Lásd „Mentés gépen kívülre, húzásos módon" alább.

A két gép jól kiegészíti egymást:

| Raspberry Pi (24/7, pár watt) | Nagy gép (izom) |
|---|---|
| AdGuard DNS, Tailscale exit node, Uptime Kuma, Home Assistant, MQTT | AI, Nextcloud, VM-ek, git, weboldalak |
| Akkor is megy, ha a nagy gép áll vagy frissül | Nem éri meg 24/7 járatni |

Az összekötést egy script intézi, a **szerveren** futtatva:

```bash
sudo ./osszekotes.sh --proba     # előbb nézd meg, mit tenne
sudo ./osszekotes.sh             # aztán élesben
sudo ./osszekotes.sh --csak mentes
sudo ./osszekotes.sh --pi 192.168.1.42
```

Hét lépés:

| Lépés | Mit csinál |
|---|---|
| `kapcsolat` | eléri-e a két gép egymást, fut-e a Tailscale (fel is rakja, ha kéred) |
| `kulcs` | jelszó nélküli SSH a szervertől a Pi felé + `park-tars` SSH-bejegyzés |
| `felderites` | mi fut a Pi-n: nyitott portok, konténerek, szolgáltatások |
| `proxy` | a kiválasztott Pi-szolgáltatásokat bekötni `név.park.lan` alá |
| `dns` | a Pi AdGuardjában `*.park.lan → szerver IP` (API-n keresztül is) |
| `mentes` | kölcsönös mentés (lásd lent) |
| `figyeles` | mit vegyél fel az Uptime Kumába |

**A kölcsönös mentés két irányban működik:**

- **Pi → szerver**: a `park-pi-mentes` rsync-cel lehúzza a Pi fontos mappáit az
  `adat/pi-mentes/` alá, ahonnan a napi restic mentés viszi tovább. A Pi-re nem
  kell semmit telepíteni.
- **Szerver → Pi**: a napi mentés végén `restic copy` átmásolja a
  pillanatképeket a Pi-re dugott külső lemezre.

Így egyik gép elvesztése sem visz el mindent. Ha a Pi épp nem elérhető, a mentés
nem hal el, csak kihagyja azt a részt.

```bash
park tars        # a Pi elérhető-e, mi van bekötve, mikor volt mentés
ssh park-tars    # belépés a dedikált kulccsal
```

## Mentés gépen kívülre, húzásos módon

Ha nincs társgép, a napi mentés a szerveren marad – egy tűz vagy egy ellopott
gép mindent elvisz. A legkisebb munkával járó megoldás: egy **másik gép húzza le**
a restic repót, amikor éppen be van kapcsolva. A szerveren semmit nem kell
nyitni, és nem kell éjjel járatni a másik gépet.

A húzó gépen (pl. laptop) kell: `restic`, SSH-elérés a szerverre, és a repó
jelszava (a szerver `.env`-jében: `RESTIC_JELSZO`). A repó root-tulajdonú, ezért
az sftp-kiszolgálót sudo-val indítjuk:

```bash
export RESTIC_PASSWORD_FILE=~/.config/park-mentes/jelszo
export RESTIC_FROM_PASSWORD_FILE=$RESTIC_PASSWORD_FILE
restic --repo ~/mentesek/park-repo \
       -o sftp.command="ssh szerver sudo /usr/lib/openssh/sftp-server" \
       copy --from-repo sftp:szerver:/srv/tarolok/<lemez>/mentes/repo
restic --repo ~/mentesek/park-repo forget --prune \
       --keep-daily 7 --keep-weekly 5 --keep-monthly 12
```

Tedd napi `systemd --user` időzítőbe (`Persistent=true`), és az elején ellenőrizd,
hogy a szerver elérhető-e – ha nem, lépjen ki 0-val, hogy ne riasszon hiába.

Klaszterezni (Docker Swarm, Incus cluster) is lehetne a két gépet, de a Pi
ARM-os, a szerver x86 – a kétarchitektúrás képek több macera, mint haszon. A
fenti szerepmegosztás egyszerűbb és stabilabb.

---

## Mentés és visszaállítás

A napi mentés **hajnali 3:30-kor** fut (`park-mentes.timer`), és ezt menti:
`adat/`, `stackek/`, `web/`, `.env`, `/etc/szerverpark.conf`, a Samba-konfig,
valamint a Nextcloud adatbázisát külön kimentve (a futó MariaDB fájljait nem
elég másolni).

Megtartás: **7 napi + 5 heti + 12 havi + 2 éves** pillanatkép (deduplikálva,
titkosítva – ugyanaz a fájl csak egyszer foglal helyet).

```bash
park mentes            # azonnali mentés
park mentesek          # mi van elmentve
```

**Visszaállítás** (a jelszó a `.env`-ben, `RESTIC_JELSZO`):

```bash
set -a; source /srv/szerverpark/.env; set +a
export RESTIC_PASSWORD="$RESTIC_JELSZO"

# mi van a mentésben
restic -r "$MENTES_CEL" snapshots

# egyetlen fájl/mappa visszahozása egy próbamappába
restic -r "$MENTES_CEL" restore latest --target /tmp/vissza --include /srv/szerverpark/adat/megosztas

# teljes visszaállítás (új gépre is: telepítsd a parkot, majd)
restic -r "$MENTES_CEL" restore latest --target /
park indit
```

A Nextcloud adatbázisa visszatöltéshez:

```bash
docker exec -i park-nextcloud-db mariadb -u root -p"$NC_DB_ROOT_JELSZO" nextcloud \
  < /srv/szerverpark/mentes/db/nextcloud.sql
```

> **Figyelem:** ha a `MENTES_CEL` ugyanazon a gépen van, az csak a „félrenyomtam"
> ellen véd, tűz/lopás ellen nem. Ezért érdemes az összekötő scripttel a Pi-re is
> átmásoltatni, vagy külső lemezt megadni.

---

## Mennyi vas kell hozzá?

### Memória

| Mi fut | RAM |
|---|---|
| Debian + Docker alap | 0,6 GB |
| Caddy, FileBrowser, Vaultwarden, Dockge | 0,2 GB |
| Nextcloud + MariaDB + Redis | 0,8–1 GB |
| Forgejo, Uptime Kuma, Homepage, SearXNG | 0,6 GB |
| LiteLLM + Open WebUI | 0,8–1 GB |
| libvirt + Incus démonok üresen | 0,15 GB |
| **Összesen, AI-modell és VM nélkül** | **~3–3,5 GB** |
| + betöltött 3B modell | +2,5 GB |
| + betöltött 7B modell | +5 GB |
| + egy futó teszt-VM | +1–2 GB |

**8 GB**: elég mindenre, de **nem egyszerre**. A telepítő ezt kezeli: 10 GB
alatt egyszerre 1 modell tölthető be, 2 perc tétlenség után kiesik, és 12 GB
alatt bekapcsol a **zram**. VM indítása előtt ne legyen betöltve modell.

**16 GB**: kényelmes. **32 GB**: 14B modell + több VM egyszerre.

**Raspberry Pi 4/5 (ARM, 8 GB)**: minden modul felmegy, de tudd, mit várhatsz.
A telepítő architektúrát néz: ARM-on `qemu-system-arm` kerül fel, és a CPU
virtualizációját a `/dev/kvm` megléte jelzi (nincs vmx/svm flag). Amire figyelj:

| Mi | Hogy megy egy Pi 4-en |
|---|---|
| Caddy, Pi-hole, Forgejo, Vaultwarden, Syncthing, Paperless | jól |
| Nextcloud | megy, de lassabb; SD-kártyán ne tartsd rajta az adatot |
| Ollama 3B modell | ~2–4 szó/mp – kipróbálásra jó, munkára nem |
| LiteLLM + Open WebUI | jól: a felhős modellek itt futnak igazán |
| Jellyfin | direkt lejátszás jó, átkódolás nem |
| KVM VM-ek | csak ARM vendég; x86-os ISO emulációval használhatatlan |
| Incus rendszer-konténerek | jól – ARM-on ez a test lab jó útja |

**Két adathordozó okos elosztása.** Nem kell mindent egy lemezre tenni: a
`/etc/szerverpark.conf`-ban külön megmondhatod, mi hova kerüljön.

| Kulcs | Mi kerül oda | Hova érdemes |
|---|---|---|
| `NC_FAJL_DIR` | a Nextcloud felhasználói fájljai | nagy lemez |
| `IRATOK_DIR` | a Paperless iratai (media/export/**consume**) | nagy lemez |
| `AI_MODELL_DIR` | az Ollama modellek (több GB, újratölthető) | nagy lemez |
| `MEDIA_DIR` | film, sorozat, zene | nagy lemez |
| `MEGOSZTAS_DIR` | a Samba megosztások | nagy lemez |
| `MENTES_CEL` | a restic mentés | **másik** adathordozó, mint az adatok |
| (`ADAT_DIR`) | adatbázisok, konténer-adatok | **rendszerlemez** – ott gyorsak |

Az adatbázisokat szándékosan hagyd a rendszerlemezen: ott gyorsak, és egy
véletlenül kihúzott külső tár nem viszi magával őket. A `consume` mappát a
telepítő Sambán is megosztja `beolvasas` néven – oda dobva a szkennelt lapokat
a Paperless magától felszedi és OCR-ezi.

### Tárhely

| Mi | Hely |
|---|---|
| Debian + konténer-képek (az Open WebUI egymaga ~4 GB) | 15–20 GB |
| AI modellek (3B ≈ 2 GB, 7B ≈ 5 GB, 14B ≈ 9 GB) | 10–25 GB |
| VM-lemezek (40 GB-os qcow2, csak a használtat foglalja) | 20–60 GB |
| Incus rendszerképek | 5–10 GB |
| **Eddig** | **~50–115 GB** |

Egy 512 GB-os lemezen ez elfér, és marad ~400 GB az adatoknak. Amint lehet,
tegyél be külön lemezt az `ADAT_DIR`-nek és a mentésnek.

---

## Fájlszerkezet

### A projektben (amit felmásolsz)

```
szerverpark/
├── telepito.sh            fő telepítő (--proba / --auto / --csak / --lista)
├── osszekotes.sh          szerver ↔ Raspberry Pi összekötés
├── szerver.conf.pelda     minden beállítás kommentelve
├── lib/
│   ├── kozos.sh           log, kérdezés, titkok, stack-kezelés
│   ├── csomagkezelo.sh    apt / dnf / zypper / pacman réteg
│   └── ai-katalogus.txt   a letölthető AI modellek listája
├── modulok/               alap, docker, proxy, ai, fajlok, samba, web,
│                          selfhost, vm, mentes
├── sablonok/              docker compose fájlok szolgáltatásonként
└── skriptek/park          a kezelő parancs
```

### A szerveren (telepítés után)

```
/srv/szerverpark/
├── .env                 ← minden generált jelszó (chmod 600)
├── ai-katalogus.txt
├── stackek/             ← docker compose fájlok
│   ├── proxy/           ← Caddyfile + sites.d/*.caddy (vhostok)
│   ├── ai/  fajlok/  selfhost/  git/
├── web/                 ← a weboldalak fájljai
├── mentes/              ← restic tároló
└── adat/                ← MINDEN ADAT (ide tedd a nagy lemezt)
    ├── megosztas/       ← Samba + FileBrowser ugyanezt látja
    ├── nextcloud/  ai/  vm/  pi-mentes/  vaultwarden/  forgejo/ …

/etc/szerverpark.conf         ← a válaszaid (újrafuttatáshoz)
/etc/szerverpark-tars.conf    ← a társgép (Pi) adatai
/usr/local/bin/park           ← a kezelő parancs
/usr/local/bin/park-mentes    ← a napi mentés
/usr/local/bin/park-pi-mentes ← a Pi adatainak áthúzása
```

---

## Hibakeresés

| Tünet | Mi a baj általában |
|---|---|
| **Nem jön be a `*.park.lan` cím** | a DNS nincs beállítva – nézd meg: `ping ai.park.lan` a kliensről. Megoldás: AdGuard/router DNS vagy hosts fájl. |
| **A Samba nem fogadja el a `park jelszavak` által mutatott jelszót** | a Samba-felhasználó már a telepítő előtt létezett, így a jelszava nem az `SMB_JELSZO`. A telepítő újrafuttatáskor ezt jelzi is. Megoldás: `sudo smbpasswd <felhasználó>`, és az új jelszót írd át a `.env`-ben is. Windowson utána: `net use * /delete /y` |
| **A Caddy nem indul** | a 80/443 port foglalt (másik webszerver?): `ss -tlnp \| grep -E ':(80\|443)'` |
| **Nextcloud: „Access through untrusted domain"** | a `NEXTCLOUD_TRUSTED_DOMAINS` nem tartalmazza a címet – írd át a `.env`-ben, majd `park ujra fajlok` |
| **Az AI lassú vagy kifagy** | kevés a RAM: `park allapot`. Válts kisebb modellre (`park ai-katalogus`), vagy állítsd 1-re az `OLLAMA_MAX_LOADED_MODELS`-t. |
| **A GPU-t nem látja az Ollama** | `docker exec park-ollama nvidia-smi` – ha hibás, hiányzik a `nvidia-container-toolkit` vagy nincs `compose.override.yml` az ai stackben |
| **Egy konténer folyton újraindul** | `park naplo <stack>` megmutatja, miért |
| **Bootolás után „2 napja fut" egy frissen indult konténer** | óra nélküli gépen (Raspberry Pi) a Docker a mentett, régi idővel indult. A telepítő ilyenkor a `docker.service`-t az NTP-szinkronhoz köti (`/etc/systemd/system/docker.service.d/50-park-ido.conf`) – ha hiányzik, futtasd újra: `sudo ./telepito.sh --csak alap` |
| **A VM nem indul / nagyon lassú** | a BIOS-ban nincs bekapcsolva az Intel VT-x / AMD-V. Ellenőrzés: `ls /dev/kvm` |
| **A mentés nem fut le** | `systemctl status park-mentes.timer`, majd `journalctl -u park-mentes` |
| **A Pi mentés kimarad** | `park tars` – valószínűleg SSH vagy hálózat. Újra: `sudo ./osszekotes.sh --csak kulcs` |
| **Elfogyott a hely** | `park takarit` (régi képek), `df -h`, majd `du -sh /srv/szerverpark/adat/*` |

Minden szolgáltatás naplója: `park naplo <stack>`.
A telepítő naplói: `/var/log/szerverpark-telepito.log` és
`/var/log/szerverpark-osszekotes.log`.

---

## Biztonság

Amit a telepítő megcsinál:

- **tűzfal**: csak SSH, 80 és 443 nyitva kifelé; a Samba és a Cockpit **csak a
  helyi hálózatról**; minden más zárva. Ha a gépen már fut valami, aminek nyitva
  kell maradnia (pl. Pi-hole DNS, meglévő webalkalmazás), vedd fel a
  `TUZFAL_EXTRA` sorba a `/etc/szerverpark.conf`-ban:
  `TUZFAL_EXTRA="53/tcp,53/udp,8080/tcp"` – proto nélkül tcp-t jelent.
- **fail2ban** az SSH brute-force ellen
- **automatikus biztonsági frissítések** (újraindítás nélkül)
- minden jelszó **véletlenszerűen generált**, a `.env` csak root által olvasható

Amire neked kell figyelned:

- Az **Open WebUI**, a **Vaultwarden** és a **Forgejo** első regisztrálója lesz
  az admin – regisztrálj azonnal a telepítés után, majd tiltsd le a további
  regisztrációt.
- A **FileBrowser** alap belépése `admin`/`admin` – változtasd meg elsőként.
- **Ne nyisd meg** a Nextcloudot vagy az AI-t az internet felé jelszó és 2FA
  nélkül. Ha kívülről is kell: Tailscale, vagy Caddy elé Authelia/Authentik.
- A publikus weboldal az egyetlen, aminek tényleg kifelé kell néznie – a többi
  szolgáltatás maradjon a LAN-on vagy a tailneten.
