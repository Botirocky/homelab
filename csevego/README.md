# 🛡️ Privát Csevegő

Adatvédelem-központú, többszobás, végpontok közt titkosítható csevegőalkalmazás
**admin felülettel**. Python WebSocket-szerver + modern, üveghatású böngészős
felület — telepíthető appként Windowsra, Linuxra, Androidra és iPhone-ra.

**Egyszeri regisztráció: az első belépés becenév + jelszó párossal lefoglalja a
neved. Nincs külső szerver, nincs felhő.** Az egész alkalmazás a
te géped(ed)en fut, egyetlen Python-fájlból. Az üzenetek szobánként **helyben,
a `chat_data/` mappában** tárolódnak (JSONL-fájlokban) — szerver-újraindítás
után is megvannak, és soha nem hagyják el a gépedet.

---

## Tartalom

1. [Gyors indítás](#gyors-indítás)
2. [Funkciók](#funkciók)
3. [Csatlakozás más eszközökről](#-csatlakozás-más-eszközökről)
4. [Helyi adattárolás](#-helyi-adattárolás)
5. [Admin felület](#-admin-felület-csak-az-üzemeltetőnek)
6. [Dev mód](#%EF%B8%8F-dev-mód-fejlesztéshez)
7. [E2EE titkosítás](#-e2ee--végpontok-közötti-titkosítás)
8. [Elérhetővé tétel az interneten](#-elérhetővé-tétel-az-interneten)
9. [VPN-integráció](#%EF%B8%8F-vpn-integráció-mullvad-proton-)
10. [Telepítés appként](#-telepítés-appként-pwa)
11. [Biztonsági védelem](#-biztonsági-védelem-feltörés-ellen)
12. [Fájlok, követelmények, fenyegetettségi modell](#fájlok)

---

## Gyors indítás

```bash
cd ~/Dokumentumok/projectek/chat
python3 server.py
```

Megnyitás a böngészőben: **http://localhost:8765**

Adj meg egy becenevet és egy **fiókjelszót** — az első belépés egyben
regisztráció: a becenevet ezután csak ezzel a jelszóval lehet használni
(a jelszóból csak sózott PBKDF2-hash kerül a `chat_data/accounts.json`-ba).
Válassz szobanevet (bármit írhatsz — ha nem létezik, létrejön), és opcionálisan
egy **szobajelszót** a titkosításhoz. A böngésző a becenevet és a szobát
megjegyzi a következő belépéshez (a jelszót soha). Ennyi.

A szerver induláskor kiírja:

```
Privát Csevegő fut:  http://localhost:8765
Admin felület:       http://localhost:8765/admin
Admin token:         <a te titkos kulcsod>
```

---

## Funkciók

| | |
|---|---|
| 👤 **Regisztráció** | az első belépés becenév + jelszóval lefoglalja a neved (sózott PBKDF2-hash), a böngésző megjegyzi a beceneved |
| 🚪 **Szobák** | tetszőleges nevű szobák, külön előzményekkel (utolsó 50 üzenet szobánként) |
| 💾 **Helyi mentés** | az előzmény a `chat_data/` mappában, gépenként helyben tárolódik — újraindítás után is megvan |
| 🔐 **E2EE titkosítás** | szobajelszóval az üzenetek végpontok közt titkosítottak — a szerver sem olvashatja, a lemezre is titkosítva kerülnek |
| ✉️ **Privát üzenet (DM)** | koppints egy névre az oldalsávban — csak ti ketten látjátok, ezek nem kerülnek lemezre |
| ⌨️ **Gépelésjelzés** | látod, ha valaki éppen ír |
| 😀 **Reakciók** | 👍 ❤️ 😂 🎉 😮 bármely üzenetre — újra kattintva visszavonható, az előzményben is megmarad |
| ✏️ **Szerkesztés és törlés** | a saját üzeneted utólag javíthatod („szerkesztve" jelöléssel) vagy törölheted |
| 💬 **Válasz (idézet)** | bármely üzenetre válaszolhatsz, a buborék fölött látszik az idézett rész |
| 🖋️ **Formázás** | `**félkövér**`, `*dőlt*`, `` `kód` `` és kattintható linkek |
| 🎨 **Színes becenevek** | minden név állandó, saját színt kap az üzeneteknél és az online listában |
| 🖥️ **Asztali értesítés** | a fejléc harang gombjával rendszerszintű értesítést kapsz, ha a fül a háttérben van |
| 🛡️ **VPN-jelvény** | a fejléc mutatja, hogy a szerver Mullvad/Proton/más VPN mögött van-e |
| 🔔 **Értesítések** | hangjelzés + olvasatlan-számláló a lap címében, ha a fül nincs előtérben |
| 👑 **Admin felület** | élő irányítópult az üzemeltetőnek: kick, ban, közlemény, eseménynapló, előzménytörlés |
| 🛠️ **Dev mód** | részletes naplózás + állapot-API fejlesztéshez |
| 📱 **Telepíthető app** | PWA — Windows, Linux, Android, iPhone |
| 🌐 **Több eszközről elérhető** | telefonról, másik gépről ugyanazon a hálózaton, vagy az interneten át (tunnel) |
| ✨ **Modern felület** | OLED-sötét üveghatás (glassmorphism), animációk, mobilbarát, `prefers-reduced-motion` támogatás |

---

## 📶 Csatlakozás más eszközökről

A szerver egy gépen fut (mondjuk a laptopodon), de bárhonnan csatlakozhatsz rá
— telefonról, tabletről, másik számítógépről. Három szint van, aszerint hogy
honnan szeretnél csatlakozni:

### 1. Ugyanazon a Wi-Fi-n / helyi hálózaton (a legegyszerűbb)

Ha a másik eszköz **ugyanahhoz a routerhez** csatlakozik (otthoni Wi-Fi), nincs
szükség internetre vagy tunnelre.

1. Nézd meg a szervergép **helyi IP-címét**:

   ```bash
   hostname -I          # Linux — az első cím általában a jó (pl. 192.168.1.104)
   ```

   Windowson: `ipconfig` → „IPv4-cím". Macen: `ipconfig getifaddr en0`.

2. A másik eszköz böngészőjében nyisd meg:

   ```
   http://<a-gép-IP-je>:8765          # pl. http://192.168.1.104:8765
   ```

3. Ha a szervergépen tűzfal fut, engedélyezd a 8765-ös portot bejövő irányban
   a helyi hálózatról (Linuxon `ufw allow 8765/tcp`, Windows Defender Tűzfalnál
   egy engedélyezési szabály).

> **E2EE-hez (titkosított szobákhoz) HTTPS kell**, mert a böngészők a
> WebCrypto API-t csak biztonságos kontextusban engedik. Helyi hálózaton
> egyszerű `http://IP:port` felett a titkosítás **nem fog működni** — ehhez
> futtasd előbb a `./make_cert.sh` szkriptet (lásd az [E2EE fejezetet](#-e2ee--végpontok-közötti-titkosítás)),
> és a másik eszközön fogadd el az önaláírt tanúsítványra vonatkozó
> figyelmeztetést.

### 2. Más hálózatról / az interneten át

Ha a másik eszköz **más Wi-Fi-n vagy mobilneten** van, helyi IP nem elég — ekkor
kell egy **Cloudflare Tunnel** (lásd [Elérhetővé tétel az interneten](#-elérhetővé-tétel-az-interneten)).
Ez ad egy `https://…trycloudflare.com` címet, ami bárhonnan elérhető, és
automatikusan valódi HTTPS-t is biztosít (az E2EE is működik rajta).

### 3. Csak a saját eszközeid/barátaid között (zárt kör)

Ha nem akarod, hogy a cím bárki számára elérhető legyen, de más hálózatról is
kell a hozzáférés, használj **Tailscale**-t — ez egy privát VPN-hálózatot hoz
létre a résztvevő eszközök közt, IP-cím alapján (lásd [VPN-integráció](#️-vpn-integráció-mullvad-proton-)
alatti Tailscale-részt).

### Mindhárom esetben

- Telepítsd az appot a mobilodra/gépedre PWA-ként (lásd [Telepítés appként](#-telepítés-appként-pwa)),
  így egy ikonnal nyílik, mintha natív app lenne.
- A szobanév és (ha van) a szobajelszó a kapcsolódás módjától függetlenül
  ugyanaz — akárhonnan léptek be, ugyanabba a szobába kerültök, ha ugyanazt a
  nevet adjátok meg.

---

## 💾 Helyi adattárolás

Minden szoba üzenetei helyben, a szerver gépén tárolódnak — **sehova nem
küldődnek el, nincs felhő, nincs harmadik fél**.

- **Hol:** `chat_data/<szobanév>.jsonl` — soronként egy üzenet, JSON formában
- **Mikor íródik:** minden elküldött csoportos üzenetnél (a privát üzenetek,
  DM-ek **nem** kerülnek lemezre, azok csak a két fél kapcsolatában élnek)
- **Meddig marad meg:** a fájl a szerver újraindítása után is megvan — a
  memóriabeli 50-üzenetes előzmény ebből töltődik vissza, amikor valaki
  belép a szobába
- **Törlés:**
  - az admin felület **„Előzmény törlése"** gombja az adott szoba fájlját is
    törli a lemezről
  - kézzel is törölhető: `rm chat_data/<szobanév>.jsonl`, vagy az egész
    `chat_data/` mappa törlésével minden szoba előzménye egyszerre törlődik
- **Titkosított (E2EE) szobáknál** a lemezre is **csak a titkosított
  szöveg** kerül — a szerver a jelszót nem ismeri, így a `chat_data/` fájlokat
  megnyitva sem olvasható ki a tartalom jelszó nélkül
- **Fontos:** a `chat_data/` mappa **soha nem kerülhet fel GitHubra** — ott
  vannak a valódi beszélgetéseitek. A `.gitignore` ezt kizárja, de ha más
  módon (pl. tömörített mappa) osztod meg a projektet, mindig nézd át előtte.

---

## 👑 Admin felület (csak az üzemeltetőnek)

Nyisd meg: **http://localhost:8765/admin**

### Belépés

Az **admin tokennel** lépsz be, amit a szerver induláskor kiír a terminálba,
és a `.admin_token` fájlban is megtalálsz (első indításkor jön létre,
`chmod 600` — csak a te felhasználód olvashatja).

> ⚠️ **Soha ne oszd meg a tokent** — aki ismeri, az irányítja a szervert.
> Új tokent úgy kapsz, hogy törlöd a `.admin_token` fájlt és újraindítod
> a szervert.

### Mit tudsz az irányítópulton?

- **Élő statisztikák** (3 mp-enként frissül): üzemidő, aktív kapcsolatok,
  összes üzenet, szobák száma
- **Szobák és felhasználók IP-címmel** — felhasználónként:
  - **Kizárás** — kidobja a szobából (a kliense nem csatlakozik újra)
  - **IP-tiltás** — az adott cím összes kapcsolatát bontja, és nem engedi vissza
- **Kitiltott IP-k** — kézi tiltás beviteli mezőből, feloldás egy kattintással
  (a tiltólista memóriában él, újraindításkor ürül)
- **Közlemény** — üzenet egyszerre minden szobába
  („Üzemeltetői közlemény: …" formában jelenik meg)
- **Előzmény törlése** — szobánként azonnal üríti a memóriabeli előzményt
  **és törli a hozzá tartozó `chat_data/*.jsonl` fájlt is**
- **Élő eseménynapló** — belépések, kilépések, flood miatti bontások,
  **sikertelen admin belépési kísérletek** (a gyanús sorok sárgával kiemelve)

### Az admin belépés védelme

- időzítés-biztos token-összehasonlítás (`hmac.compare_digest`)
- hibás próbálkozás után 1 mp késleltetés (találgatás lassítása) + naplóbejegyzés
- az admin kapcsolatra is érvényes az Origin-ellenőrzés

---

## 🛠️ Dev mód (fejlesztéshez)

```bash
python3 server.py --dev
```

Mit ad?

- **Részletes napló a terminálba:** minden be-/kilépés, üzenet-metaadat
  (feladó, szoba, hossz, titkosított-e), kapcsolati események, hibák.
  **Az üzenetek tartalmát soha nem naplózza a terminálra** — titkosítás
  nélkül sem (a `chat_data/` fájlba viszont, a normál működéssel egyezően,
  a teljes üzenet bekerül).
- **Állapot-API parancssorból:**

  ```bash
  curl "http://localhost:8765/api/state?token=$(cat .admin_token)" | python3 -m json.tool
  ```

  Teljes pillanatképet ad: szobák, felhasználók IP-vel, tiltólista,
  kapcsolatszámok, statisztikák.

Éles használatra indítsd `--dev` **nélkül** — akkor csak a figyelmeztetések
kerülnek a terminálra, és a napló nem szivárogtat metaadatot a képernyőre.

---

## 🔐 E2EE — végpontok közötti titkosítás

Belépéskor adj meg egy **szobajelszót**, és oszd meg a többiekkel egy másik
csatornán (pl. személyesen). Akinél ugyanaz a jelszó, az olvassa az
üzeneteket — a szerver (és bárki, aki a hálózatot lehallgatná, vagy aki
belenéz a `chat_data/` mappába) csak értelmezhetetlen titkosított adatot lát.

**Hogyan működik?** A jelszóból a böngésző PBKDF2-vel (200 000 iteráció,
SHA-256) kulcsot képez, és minden üzenetet AES-GCM-256-tal titkosít.
**A jelszó és a kulcs soha nem hagyja el a böngésződet.** Eltérő jelszóval
belépők ezt látják: *„Nem sikerült visszafejteni (eltérő jelszó?)"*.

> **Fontos:** a böngészők a WebCrypto API-t csak biztonságos környezetben
> engedik — ez a `localhost` és a HTTPS. Ha a **helyi hálózaton** (pl.
> telefonról) akarsz titkosítva csevegni:
>
> ```bash
> ./make_cert.sh        # önaláírt tanúsítvány (a helyi IP-idet is tartalmazza)
> python3 server.py     # automatikusan HTTPS-re vált
> ```
>
> A böngésző először figyelmeztet az önaláírt tanúsítványra — „Speciális" →
> „Tovább", ez várható viselkedés. A Cloudflare tunnel (lásd lent) eleve
> valódi HTTPS-t ad, ott semmi teendő nincs.

---

## 🌍 Elérhetővé tétel az interneten

### Ajánlott: Cloudflare Tunnel

Nem kell router-beállítás vagy port forwarding, az otthoni IP-címed **rejtve
marad**, és automatikus, valódi HTTPS-t kapsz (így az E2EE is működik):

```bash
sudo pacman -S cloudflared    # egyszeri telepítés (Arch/CachyOS)

# 1. terminál:
python3 server.py
# 2. terminál:
./start_tunnel.sh
```

A szkript kiír egy `https://valami.trycloudflare.com` címet — **ezt küldd el
bárkinek**, és azonnal tudtok csevegni. Appként is erről a címről telepítenek.
Ez a cím minden induláskor **más lesz** (a `trycloudflare.com` ideiglenes),
úgyhogy indításonként újra kell küldeni azoknak, akikkel csevegsz.

> Az admin felület is elérhető a tunnelen (`…/admin`) — a token védi, de ha
> ez zavar, csak akkor indítsd a tunnelt, amíg tényleg kell.

### Alternatíva: Tailscale (zárt kör barátoknak)

```bash
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Minden résztvevő gépén/telefonján fut a Tailscale, és a gépek egy privát
WireGuard-hálózatban látják egymást — a chatet a géped Tailscale-IP-jén
(`http://100.x.y.z:8765`) éritek el. Kívülálló egyáltalán nem fér hozzá,
és a cím (ellentétben a Cloudflare tunnellel) állandó marad.

---

## 🛡️ VPN-integráció (Mullvad, Proton, …)

A VPN a rendszer szintjén fut; az alkalmazás **felismeri és jelzi** az
állapotát:

1. Indítsd el a VPN-t a szerver gépén (`mullvad connect`, Proton app stb.)
2. A chat fejlécében a pajzs-jelvény **zöldre vált**: „Mullvad VPN" / „Proton VPN"
3. Ha nincs VPN, **sárga figyelmeztetés** mutatja a védtelen kimenő IP-det

Az ellenőrzés a Mullvad nyilvános `am.i.mullvad.net` API-jával történik
(60 mp gyorsítótár, 90 mp-enként frissül a felületen), és a Proton meg több
más szolgáltató kilépőjét is felismeri a szolgáltatónévből.

> **Jó tudni:** Mullvad/Proton mögé **bejövő** kapcsolatot fogadni nem lehet
> (a port forwardingot megszüntették). A vendégek felé ezért a Cloudflare
> tunnel a járható út — a kettő remekül megfér együtt: **VPN a kimenő
> forgalmadra + tunnel a bejövőre.**

---

## 📱 Telepítés appként (PWA)

Nyisd meg a chat címét a böngészőben, majd:

| Platform | Lépések |
|---|---|
| **Android** (Chrome) | ⋮ menü → **„Alkalmazás telepítése"** |
| **iPhone / iPad** (Safari) | Megosztás gomb → **„Főképernyőhöz adás"** |
| **Windows** (Chrome/Edge) | címsor jobb széle, telepítés-ikon → **„Telepítés"** |
| **Linux** (Chrome/Chromium) | címsor, telepítés-ikon vagy ⋮ → **„Telepítés…"** |

Saját ikonnal, saját ablakban fut, mint egy natív app. Offline is elindul
(a felület gyorsítótárazódik), de a service worker **üzenetet soha nem tárol**
— az kizárólag a szervergép `chat_data/` mappájában van, nem a kliens
eszközén.

> A telepítéshez HTTPS kell (tunnel-cím vagy `make_cert.sh`) — sima
> `localhost`-on a Chrome enélkül is felajánlja.

---

## 🔒 Biztonsági védelem (feltörés ellen)

| Védelem | Mit véd ki |
|---|---|
| Sebességkorlát: 15 üzenet / 10 mp, makacs spammernél bontás | üzenetáradat (flood) |
| Kapcsolatkorlát: max. 8 egyidejű kapcsolat IP-nként | kapcsolat-elárasztás |
| Origin-ellenőrzés WebSocketen | idegen weboldal nem kapcsolódhat a nevedben (CSWSH) |
| Content-Security-Policy + X-Frame-Options + nosniff + Referrer-Policy | XSS, clickjacking, MIME-sniffing, adatszivárgás |
| Fehérlistás fájlkiszolgálás | útvonal-bejárás (path traversal) — a szerver csak a felsorolt fájlokat adja ki |
| Bemenet-tisztítás (vezérlő- és irányváltó karakterek szűrése) | név- és üzenethamisítás |
| 64 KB üzenetméret-korlát + korlátozott várósor | memória-kimerítés |
| 15 mp belépési időkorlát | lógó („zombi") kapcsolatok |
| Időzítés-biztos admin-token + próbálkozás-lassítás + napló | admin-fiók feltörése |
| HSTS fejléc HTTPS-en | visszaminősítéses (downgrade) támadás |
| Szobanevek fájlnév-tisztítása (`[^A-Za-z0-9_-]` szűrés) | könyvtár-bejárás a `chat_data/` mentésnél |

Minden üzenet `textContent`-ként kerül a DOM-ba — HTML-befecskendezés (XSS)
a kliensben sem lehetséges.

---

## Fájlok

| Fájl / mappa | Szerep |
|---|---|
| `server.py` | a teljes szerver: WebSocket + HTTP, biztonsági réteg, VPN-API, admin, dev mód, helyi mentés |
| `index.html` | a teljes csevegő-felület (dizájn, animációk, E2EE-kód) |
| `admin.html` | admin irányítópult (`/admin`) |
| `chat_data/` | **helyi adattár** — szobánként egy `.jsonl` fájl az üzenetelőzménnyel; soha ne kerüljön GitHubra |
| `.admin_token` | admin belépőkulcs — automatikusan jön létre, **titok!** |
| `manifest.webmanifest`, `sw.js`, `icon.svg`, `icon-*.png`, `apple-touch-icon.png` | PWA (telepíthető app) |
| `make_cert.sh` | önaláírt HTTPS-tanúsítvány a helyi hálózathoz |
| `start_tunnel.sh` | internetes megosztás Cloudflare tunnellel |
| `cert.pem`, `key.pem` | (opcionális) tanúsítvány — ha léteznek, a szerver HTTPS-en indul |

## Követelmények

- Python **3.10+**
- `websockets` csomag (`pip install websockets`)

Ennyi. Se külső adatbázis-szerver, se Node, se build-lépés — a helyi mentés is
sima fájlokkal működik, telepítendő extra függőség nélkül.

## Őszinte fenyegetettségi modell

- ✅ A szerver üzemeltetője **nem** olvashatja a jelszavas (E2EE) szobák
  üzeneteit — sem élőben, sem a lemezre mentett fájlokban
- ✅ Hálózati lehallgató HTTPS/tunnel mögött semmit sem lát
- ✅ Idegen weboldalak, floodolók, óriás-üzenetek, találgatásos admin-támadás,
  könyvtár-bejárás ellen van védelem
- ✅ Az adatok **sosem hagyják el a szervergépet** — nincs felhő, nincs
  harmadik fél, nincs kimenő adatküldés a csevegés tartalmáról
- ⚠️ **Változás a korábbi verzióhoz képest:** az üzenetek mostantól **helyben,
  lemezen is megmaradnak** (`chat_data/`), nem csak a memóriában — aki
  hozzáfér a szervergéphez (fizikailag vagy távolról), titkosítatlan
  szobáknál elolvashatja a mentett előzményt. Ha ez nem kívánt, az admin
  felület „Előzmény törlése" gombjával, vagy a `chat_data/` mappa kézi
  törlésével bármikor eltávolítható
- ⚠️ A **beceneveket és a szobaneveket** a szerver látja (a tagság elrejtéséhez Tor/Tailscale)
- ⚠️ Az E2EE annyira erős, amennyire a szobajelszó — hosszú, egyedi jelszót válassz
- ⚠️ Az önaláírt tanúsítványra a böngésző figyelmeztet — ez várható, nem hiba
- ⚠️ Az admin token birtokosa mindent lát és irányít — kezeld jelszóként
