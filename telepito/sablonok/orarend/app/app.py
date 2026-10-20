__lazy_modules__ = [
    "hashlib",
    "hmac",
    "html",
    "json",
    "os",
    "re",
    "secrets",
    "threading",
    "time",
    "traceback",
    "urllib.parse",
    "urllib.request",
    "datetime",
    "http.server",
    "zoneinfo",
    "kreta",
]

import hashlib
import hmac
import html
import json
import os
import re
import secrets
import threading
import time
import traceback
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from zoneinfo import ZoneInfo

import kreta

ADAT = os.environ.get("ORAREND_ADAT", "/data")
TZ = ZoneInfo(os.environ.get("TZ") or "Europe/Budapest")
PORT = int(os.environ.get("ORAREND_PORT", "8080"))
ICS_KULCS = os.environ.get("ORAREND_ICS_KULCS", "")
JELSZO = os.environ.get("ORAREND_JELSZO", "")
SUTI = "orarend_munkamenet"
SUTI_NAP = 90
sikertelen = {}
NTFY_URL = os.environ.get("NTFY_URL", "")
DISCORD_WEBHOOK = os.environ.get("DISCORD_WEBHOOK", "")
ERTESITES = os.environ.get("ORAREND_ERTESITES", "be") != "ki"
ESTI = os.environ.get("ORAREND_ESTI_OSSZEFOGLALO", "19:00")
PERC_NAPKOZBEN = int(os.environ.get("ORAREND_FRISSITES_PERC", "20"))
NAPOK = ["Hétfő", "Kedd", "Szerda", "Csütörtök", "Péntek", "Szombat", "Vasárnap"]

zar = threading.Lock()
ebreszto = threading.Event()


def ut(nev):
    return os.path.join(ADAT, nev)


def betolt(nev, alap=None):
    try:
        with open(ut(nev), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return alap


def ment(nev, ertek):
    tmp = ut(nev) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(ertek, f, ensure_ascii=False, indent=1)
    os.chmod(tmp, 0o600)
    os.replace(tmp, ut(nev))


def most():
    return datetime.now(TZ)


def helyi(iso):
    if not iso:
        return None
    d = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(TZ)


def nev_of(obj, kulcs="Nev"):
    return (obj or {}).get(kulcs) if isinstance(obj, dict) else None


def ora_atalakit(o):
    kezd, veg = helyi(o.get("KezdetIdopont")), helyi(o.get("VegIdopont"))
    if not kezd:
        return None
    tipus = nev_of(o.get("Tipus")) or ""
    allapot = nev_of(o.get("Allapot")) or ""
    return {
        "uid": o.get("Uid") or "",
        "datum": kezd.date().isoformat(),
        "kezd": kezd.strftime("%H:%M"),
        "veg": veg.strftime("%H:%M") if veg else "",
        "kezd_iso": kezd.isoformat(),
        "veg_iso": veg.isoformat() if veg else kezd.isoformat(),
        "oraszam": o.get("Oraszam"),
        "targy": nev_of(o.get("Tantargy")) or o.get("Nev") or "",
        "tanar": o.get("TanarNeve") or "",
        "helyettes": o.get("HelyettesTanarNeve") or "",
        "terem": o.get("TeremNeve") or "",
        "tema": o.get("Tema") or "",
        "elmarad": allapot == "Elmaradt",
        "ures": tipus == "UresOra",
        "esemeny": o.get("Oraszam") is None and tipus not in ("TanitasiOra", "OrarendiOra"),
        "tipus": tipus,
        "hazi": bool(o.get("HaziFeladatUid")),
        "szamonkeres": bool(o.get("BejelentettSzamonkeresUid")),
    }


def szamonkeres_atalakit(s):
    d = helyi(s.get("Datum"))
    return {
        "uid": s.get("Uid") or "",
        "datum": d.date().isoformat() if d else "",
        "oraszam": s.get("OrarendiOraOraszama"),
        "targy": s.get("TantargyNeve") or nev_of(s.get("Tantargy")) or "",
        "tema": s.get("Temaja") or "",
        "mod": nev_of(s.get("Modja"), "Leiras") or nev_of(s.get("Modja")) or "",
        "tanar": s.get("RogzitoTanarNeve") or "",
    }


def html_szoveg(s):
    s = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</li>", "\n", s or "")
    s = html.unescape(re.sub(r"<[^>]+>", "", s))
    return re.sub(r"\n{3,}", "\n\n", s).strip()


def hazi_atalakit(h):
    hat = helyi(h.get("HataridoDatuma"))
    return {
        "uid": h.get("Uid") or "",
        "hatarido": hat.date().isoformat() if hat else "",
        "targy": h.get("TantargyNeve") or nev_of(h.get("Tantargy")) or "",
        "szoveg": html_szoveg(h.get("Szoveg")),
        "tanar": h.get("RogzitoTanarNeve") or "",
        "kesz": bool(h.get("IsMegoldva")),
    }


def token_ervenyes():
    t = betolt("token.json")
    if not t:
        raise kreta.BelepesKell("még nincs belépve")
    if t.get("lejar", 0) - 60 > time.time():
        return t
    try:
        uj = kreta.frissites(t["refresh"], t["intezmeny"])
    except kreta.BelepesKell:
        fiok = betolt("fiok.json") or {}
        if not fiok.get("jelszo"):
            raise
        uj = kreta.jelszavas_belepes(fiok["felhasznalo"], fiok["jelszo"], fiok["intezmeny"])
    return token_ment(uj)


def token_ment(valasz):
    torzs = kreta.jwt_torzs(valasz["access_token"])
    t = {
        "access": valasz["access_token"],
        "refresh": valasz.get("refresh_token") or (betolt("token.json") or {}).get("refresh", ""),
        "lejar": torzs.get("exp", time.time() + 1500),
        "intezmeny": torzs.get("kreta:institute_code", ""),
        "nev": torzs.get("name", ""),
    }
    ment("token.json", t)
    return t


def letolt():
    t = token_ervenyes()
    ma = most().date()
    hetfo = ma - timedelta(days=ma.weekday())
    if ma.weekday() >= 5:
        hetfo += timedelta(days=7)
    vege = hetfo + timedelta(days=13)
    orak = kreta.api_get(
        t["access"], t["intezmeny"], "sajat/OrarendElemek",
        {"datumTol": hetfo.isoformat(), "datumIg": vege.isoformat()},
    )
    try:
        szk = kreta.api_get(
            t["access"], t["intezmeny"], "sajat/BejelentettSzamonkeresek",
            {"datumTol": (ma - timedelta(days=1)).isoformat()},
        )
    except kreta.KretaHiba:
        szk = []
    try:
        hazik = kreta.api_get(
            t["access"], t["intezmeny"], "sajat/HaziFeladatok",
            {"datumTol": (ma - timedelta(days=14)).isoformat()},
        )
    except kreta.KretaHiba:
        hazik = []
    orak = [x for x in (ora_atalakit(o) for o in orak) if x]
    orak.sort(key=lambda x: (x["datum"], x["kezd"]))
    return {
        "tol": hetfo.isoformat(),
        "ig": vege.isoformat(),
        "orak": orak,
        "szamonkeresek": sorted((szamonkeres_atalakit(s) for s in szk), key=lambda x: x["datum"]),
        "hazik": sorted((hazi_atalakit(h) for h in hazik), key=lambda x: x["hatarido"]),
        "nev": t.get("nev", ""),
    }


def ora_kulcs(o):
    return f'{o["datum"]}|{o["oraszam"] if o["oraszam"] is not None else o["kezd"]}'


def nap_cimke(datum_iso):
    d = date.fromisoformat(datum_iso)
    ma = most().date()
    if d == ma:
        return "Ma"
    if d == ma + timedelta(days=1):
        return "Holnap"
    return f"{NAPOK[d.weekday()]} ({d.month}.{d.day:02d}.)"


def ora_cimke(o):
    sz = f'{o["oraszam"]}. óra' if o.get("oraszam") is not None else o.get("kezd", "")
    return f'{nap_cimke(o["datum"])} {sz} ({o["targy"]})'


def valtozasok(regi, uj):
    if not regi:
        return []
    ma = most().date().isoformat()
    tol, ig = max(regi["tol"], uj["tol"], ma), min(regi["ig"], uj["ig"])
    def szur(lista):
        return {
            ora_kulcs(o): o for o in lista
            if tol <= o["datum"] <= ig and not o["esemeny"] and not o["ures"]
        }
    r, u = szur(regi["orak"]), szur(uj["orak"])
    uzenetek = []
    for k, o in sorted(u.items()):
        e = r.get(k)
        if o["datum"] == ma and o["veg_iso"] < most().isoformat():
            continue
        if e is None:
            uzenetek.append(f'Új óra: {ora_cimke(o)}{", " + o["terem"] if o["terem"] else ""}')
            continue
        if o["elmarad"] and not e["elmarad"]:
            uzenetek.append(f"Elmarad: {ora_cimke(o)}")
        elif o["targy"] != e["targy"]:
            uzenetek.append(f'Óracsere: {ora_cimke(o)} – eddig {e["targy"]}')
        if o["helyettes"] and o["helyettes"] != e["helyettes"]:
            uzenetek.append(f'Helyettesítés: {ora_cimke(o)} – {o["helyettes"]}')
        if o["terem"] and e["terem"] and o["terem"] != e["terem"]:
            uzenetek.append(f'Teremcsere: {ora_cimke(o)} – {e["terem"]} → {o["terem"]}')
    for k, e in sorted(r.items()):
        if k not in u and not e["elmarad"]:
            uzenetek.append(f"Kikerült az órarendből: {ora_cimke(e)}")
    regi_szk = {s["uid"] for s in regi.get("szamonkeresek", [])}
    for s in uj["szamonkeresek"]:
        if s["uid"] not in regi_szk and s["datum"] >= ma:
            uzenetek.append(
                f'Számonkérés: {s["targy"]} – {nap_cimke(s["datum"])}'
                + (f', {s["mod"]}' if s["mod"] else "")
                + (f': {s["tema"]}' if s["tema"] else "")
            )
    regi_h = {h["uid"] for h in regi.get("hazik", [])}
    for h in uj["hazik"]:
        if h["uid"] not in regi_h and h["hatarido"] >= ma:
            uzenetek.append(f'Új házi: {h["targy"]}, határidő {nap_cimke(h["hatarido"])}')
    return uzenetek


def ertesit(cim, szoveg, prio="default", tag="school"):
    if not ERTESITES:
        return
    if NTFY_URL:
        try:
            q = urllib.parse.urlencode({"title": cim, "priority": prio, "tags": tag})
            kerd = urllib.request.Request(
                f"{NTFY_URL}?{q}", data=szoveg.encode(), method="POST"
            )
            urllib.request.urlopen(kerd, timeout=15).close()
        except Exception as e:
            print("ntfy hiba:", e, flush=True)
    if DISCORD_WEBHOOK:
        try:
            kerd = urllib.request.Request(
                DISCORD_WEBHOOK,
                data=json.dumps({"content": f"**{cim}**\n{szoveg}"}).encode(),
                headers={"Content-Type": "application/json", "User-Agent": "park-orarend"},
                method="POST",
            )
            urllib.request.urlopen(kerd, timeout=15).close()
        except Exception as e:
            print("discord hiba:", e, flush=True)


def allapot():
    return betolt("allapot.json", {}) or {}


def allapot_ir(**kv):
    a = allapot()
    a.update(kv)
    ment("allapot.json", a)


def iskola_kod(ertek):
    ertek = ertek.strip()
    m = re.search(r"\(([a-z0-9][a-z0-9\-_.]{2,39}) - [^)]*\)\s*$", ertek, re.I)
    if m:
        return m.group(1).lower()
    ertek = ertek.strip("() ").lower() if re.fullmatch(r"\(?\s*[A-Za-z0-9][A-Za-z0-9\-_.]{2,39}\s*\)?", ertek) else ertek
    if re.fullmatch(r"[a-z0-9][a-z0-9\-_.]{2,39}", ertek):
        return ertek
    talalat = kreta.intezmeny_kereses(ertek)
    if len(talalat) == 1:
        return talalat[0]["kod"]
    if not talalat:
        raise kreta.KretaHiba(f"nincs ilyen iskola: {ertek}")
    lista = "; ".join(f'{t["kod"]} = {t["nev"]}' for t in talalat[:6])
    raise kreta.KretaHiba(f"több iskola is illik rá, írd az ISKOLA= sorba a kódot: {lista}")


def kreta_txt_kesz():
    try:
        return time.time() - os.path.getmtime(ut("kreta.txt")) >= 20
    except OSError:
        return False


def fajlbol_belepes():
    fajl = ut("kreta.txt")
    if not kreta_txt_kesz():
        return
    adatok = {}
    with open(fajl, encoding="utf-8-sig") as f:
        sorok = [x.strip() for x in f if x.strip()]
    nevek = {"FELHASZNALO": "FELHASZNALO", "FELHASZNÁLÓ": "FELHASZNALO", "AZONOSITO": "FELHASZNALO",
             "JELSZO": "JELSZO", "JELSZÓ": "JELSZO", "ISKOLA": "ISKOLA", "INTEZMENY": "ISKOLA", "INTÉZMÉNY": "ISKOLA"}
    for sor in sorok:
        m = re.match(r"([A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]+)(?:\s*[=:]\s*|\s+)(.*)$", sor)
        if m and m.group(1).upper() in nevek and m.group(2):
            adatok[nevek[m.group(1).upper()]] = m.group(2).strip().strip('"')
    if not adatok and len(sorok) == 3:
        adatok = dict(zip(("FELHASZNALO", "JELSZO", "ISKOLA"), sorok))
    try:
        felh, jelszo = adatok["FELHASZNALO"], adatok["JELSZO"]
        intezmeny = iskola_kod(adatok["ISKOLA"])
    except KeyError as hiany:
        os.replace(fajl, ut("kreta.txt.hibas"))
        return f"kreta.txt: hiányzik a {hiany.args[0]}= sor (javítsd, és mentsd újra kreta.txt néven)"
    except kreta.KretaHiba as hiba:
        os.replace(fajl, ut("kreta.txt.hibas"))
        return f"kreta.txt: {hiba} (javítsd, és mentsd újra kreta.txt néven)"
    try:
        token_ment(kreta.jelszavas_belepes(felh, jelszo, intezmeny))
    except kreta.KretaHiba as hiba:
        print(f"kreta.txt belépés sikertelen ({intezmeny}): {hiba}", flush=True)
        os.replace(fajl, ut("kreta.txt.hibas"))
        return f"kreta.txt: {hiba} (a fájl átnevezve kreta.txt.hibas-ra)"
    ment("fiok.json", {"felhasznalo": felh, "intezmeny": intezmeny, "jelszo": jelszo})
    os.remove(fajl)
    print(f"kreta.txt: belépve ({intezmeny}), a fájlt töröltem", flush=True)


def szinkron():
    try:
        fajl_hiba = fajlbol_belepes()
    except Exception as hiba:
        traceback.print_exc()
        fajl_hiba = f"kreta.txt: {hiba}"
        if os.path.exists(ut("kreta.txt")):
            os.replace(ut("kreta.txt"), ut("kreta.txt.hibas"))
    if fajl_hiba:
        allapot_ir(hiba=fajl_hiba, belepes_kell=True, probalva=most().isoformat())
        return
    with zar:
        regi = betolt("adat.json")
        try:
            uj = letolt()
        except kreta.BelepesKell as e:
            elozo = allapot().get("belepes_kell")
            allapot_ir(hiba=f"Belépés kell: {e}", belepes_kell=True, probalva=most().isoformat())
            if not elozo:
                ertesit("Órarend: belépés kell", f"A Kréta nem enged be ({e}). Lépj be újra az órarend oldalán.", "high", "warning")
            return
        except Exception as e:
            traceback.print_exc()
            allapot_ir(hiba=str(e), probalva=most().isoformat())
            return
        uzenetek = valtozasok(regi, uj)
        ment("adat.json", uj)
        allapot_ir(hiba=None, belepes_kell=False, frissitve=most().isoformat(), probalva=most().isoformat())
    if uzenetek:
        ertesit("Órarend változott", "\n".join(uzenetek[:15]))
        print("változások:", *uzenetek, sep="\n  ", flush=True)


def holnapi_osszefoglalo():
    adat = betolt("adat.json")
    if not adat:
        return
    holnap = (most().date() + timedelta(days=1)).isoformat()
    orak = [o for o in adat["orak"] if o["datum"] == holnap and not o["ures"] and not o["esemeny"]]
    if not orak:
        return
    sorok = []
    for o in orak:
        s = f'{o["oraszam"] if o["oraszam"] is not None else "–"}. {o["targy"]}'
        if o["terem"]:
            s += f' ({o["terem"]})'
        if o["elmarad"]:
            s += " – ELMARAD"
        elif o["helyettes"]:
            s += f' – helyettes: {o["helyettes"]}'
        sorok.append(s)
    kezdo = next((o for o in orak if not o["elmarad"]), None)
    for s in adat["szamonkeresek"]:
        if s["datum"] == holnap:
            sorok.append(f'📝 {s["targy"]}: {s["mod"] or "számonkérés"}' + (f' – {s["tema"]}' if s["tema"] else ""))
    for h in adat["hazik"]:
        if h["hatarido"] == holnap and not h["kesz"]:
            sorok.append(f'📚 házi: {h["targy"]}')
    cim = "Holnap" + (f' {kezdo["kezd"]}-kor kezdesz' if kezdo else ": minden óra elmarad")
    ertesit(cim, "\n".join(sorok), "low", "calendar")


def kovetkezo_ido():
    m = most()
    if m.weekday() < 5 and 6 <= m.hour < 18:
        return PERC_NAPKOZBEN * 60
    if 18 <= m.hour < 22:
        return 60 * 60
    return 3 * 60 * 60


def szinkron_ciklus():
    while True:
        try:
            szinkron()
        except Exception:
            traceback.print_exc()
        for _ in range(kovetkezo_ido() // 15):
            if ebreszto.is_set() or kreta_txt_kesz():
                break
            time.sleep(15)
        ebreszto.clear()


def esti_ciklus():
    try:
        ora, perc = (int(x) for x in ESTI.split(":"))
    except ValueError:
        return
    while True:
        m = most()
        cel = m.replace(hour=ora, minute=perc, second=0, microsecond=0)
        if cel <= m:
            cel += timedelta(days=1)
        time.sleep((cel - m).total_seconds())
        try:
            szinkron()
            holnapi_osszefoglalo()
        except Exception:
            traceback.print_exc()


def titok_kulcs():
    return hashlib.sha256(("park-orarend|" + JELSZO + "|" + ICS_KULCS).encode()).digest()


def munkamenet_uj():
    lejar = str(int(time.time()) + SUTI_NAP * 86400)
    alairas = hmac.new(titok_kulcs(), lejar.encode(), hashlib.sha256).hexdigest()
    return f"{lejar}.{alairas}"


def munkamenet_jo(suti_fejlec):
    if not JELSZO:
        return True
    for darab in (suti_fejlec or "").split(";"):
        nev, _, ertek = darab.strip().partition("=")
        if nev != SUTI or "." not in ertek:
            continue
        lejar, alairas = ertek.split(".", 1)
        vart = hmac.new(titok_kulcs(), lejar.encode(), hashlib.sha256).hexdigest()
        if hmac.compare_digest(alairas, vart) and lejar.isdigit() and int(lejar) > time.time():
            return True
    return False


def tul_sok_probalkozas(ip):
    most_ = time.time()
    lista = [t for t in sikertelen.get(ip, []) if most_ - t < 900]
    sikertelen[ip] = lista
    return len(lista) >= 8


def e(s):
    return html.escape(str(s or ""), quote=True)


CSS = """
:root{--h:#f6f7fb;--k:#fff;--sz:#1c1f26;--t:#6b7280;--v:#e5e7eb;--a:#2563eb;--aa:#dbeafe;
--p:#dc2626;--pp:#fee2e2;--s:#b45309;--ss:#fef3c7;--z:#047857;--zz:#d1fae5}
@media (prefers-color-scheme:dark){:root{--h:#0f1115;--k:#181b22;--sz:#e8eaf0;--t:#9aa1ad;--v:#2a2f3a;
--a:#60a5fa;--aa:#1e2a44;--p:#f87171;--pp:#3b1d1d;--s:#fbbf24;--ss:#3a2e12;--z:#34d399;--zz:#0f2e25}}
*{box-sizing:border-box}body{margin:0;background:var(--h);color:var(--sz);
font:15px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:1100px;margin:0 auto;padding:16px}
h1{font-size:22px;margin:4px 0 2px}h2{font-size:16px;margin:26px 0 10px;color:var(--t);
text-transform:uppercase;letter-spacing:.05em}
.al{color:var(--t);font-size:13px}a{color:var(--a)}
.kartya{background:var(--k);border:1px solid var(--v);border-radius:12px;padding:14px 16px}
.fo{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px;margin-top:14px}
.fo .cimke{font-size:12px;color:var(--t);text-transform:uppercase;letter-spacing:.06em}
.fo .nagy{font-size:20px;font-weight:650;margin:2px 0}
.lista{display:flex;flex-direction:column;gap:6px}
.sor{display:flex;gap:12px;align-items:baseline;background:var(--k);border:1px solid var(--v);
border-radius:10px;padding:9px 12px}
.sor .sz{font-weight:700;width:22px;color:var(--t)}.sor .ido{width:96px;color:var(--t);font-variant-numeric:tabular-nums}
.sor .t{flex:1;min-width:0}.sor .terem{color:var(--t)}
.most{border-color:var(--a);background:var(--aa)}.mult{opacity:.5}
.sor .ido{white-space:nowrap}
.elmarad .t b{text-decoration:line-through;color:var(--t)}
.cimk{display:inline-block;font-size:12px;border-radius:6px;padding:1px 7px;margin-left:6px;vertical-align:1px}
.c-p{background:var(--pp);color:var(--p)}.c-s{background:var(--ss);color:var(--s)}.c-z{background:var(--zz);color:var(--z)}
.c-a{background:var(--aa);color:var(--a)}
.racs-k{overflow-x:auto}
table{border-collapse:separate;border-spacing:4px;width:100%;min-width:640px}
th{font-size:13px;color:var(--t);font-weight:600;text-align:left;padding:2px 6px}
th.mai{color:var(--a)}
td{vertical-align:top;background:var(--k);border:1px solid var(--v);border-radius:8px;padding:6px 8px;
font-size:13px;height:56px;width:19%}
td.sz{width:34px;background:none;border:none;color:var(--t);font-weight:700;text-align:center}
td.ures{background:none;border-style:dashed}
td b{display:block;font-size:13.5px}td .al{font-size:12px}
td.elmarad{background:var(--pp)}td.elmarad b{text-decoration:line-through}
td.helyettes{background:var(--ss)}td.mai{border-color:var(--a)}
.gombok{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:12px}
button,.gomb{font:inherit;border:1px solid var(--v);background:var(--k);color:var(--sz);border-radius:8px;
padding:7px 12px;cursor:pointer;text-decoration:none}
button.f,.gomb.f{background:var(--a);border-color:var(--a);color:#fff}
.hiba{background:var(--pp);color:var(--p);border-radius:10px;padding:10px 14px;margin-top:12px}
form.belep{display:grid;gap:10px;max-width:420px}
input{font:inherit;padding:9px 11px;border-radius:8px;border:1px solid var(--v);background:var(--h);color:var(--sz);width:100%}
label{font-size:13px;color:var(--t)}
footer{margin:30px 0 10px;color:var(--t);font-size:12.5px}
@media (max-width:600px){main{padding:12px}.sor{gap:9px}.sor .ido{width:auto;font-size:13px}.sor .sz{width:14px}}
"""


def oldal(cim, torzs, frissul=False):
    meta = '<meta http-equiv="refresh" content="300">' if frissul else ""
    return f"""<!doctype html><html lang="hu"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">{meta}
<title>{e(cim)}</title><style>{CSS}</style></head><body><main>{torzs}</main></body></html>"""


def ora_sor(o, mostani=False, mult=False):
    osztaly = "sor" + (" most" if mostani else "") + (" mult" if mult else "") + (" elmarad" if o["elmarad"] else "")
    cimkek = ""
    if o["elmarad"]:
        cimkek += '<span class="cimk c-p">elmarad</span>'
    if o["helyettes"]:
        cimkek += f'<span class="cimk c-s">helyettes: {e(o["helyettes"])}</span>'
    if o["szamonkeres"]:
        cimkek += '<span class="cimk c-a">számonkérés</span>'
    if o["hazi"]:
        cimkek += '<span class="cimk c-z">házi</span>'
    sz = o["oraszam"] if o["oraszam"] is not None else ""
    tanar = o["tanar"] if not o["helyettes"] else ""
    tema = f'<div class="al">{e(o["tema"])}</div>' if o["tema"] else ""
    return (
        f'<div class="{osztaly}"><span class="sz">{e(sz)}</span>'
        f'<span class="ido">{e(o["kezd"])}–{e(o["veg"])}</span>'
        f'<span class="t"><b>{e(o["targy"])}</b>{cimkek}'
        f'<div class="al">{e(tanar)}</div>{tema}</span>'
        f'<span class="terem">{e(o["terem"])}</span></div>'
    )


def fooldal(het):
    adat = betolt("adat.json")
    a = allapot()
    m = most()
    ma = m.date().isoformat()
    fej = f'<h1>Órarend</h1><div class="al">{e(adat.get("nev") if adat else "")}</div>'
    hiba = ""
    if a.get("hiba"):
        hiba = f'<div class="hiba">{e(a["hiba"])} — <a href="/belepes">belépés</a></div>'
    if not adat:
        return oldal("Órarend", fej + hiba + '<div class="kartya" style="margin-top:14px">Még nincs letöltött órarend. '
                     '<a href="/belepes">Lépj be a Kréta-fiókoddal</a>.</div>')
    valodi = [o for o in adat["orak"] if not o["ures"] and not o["esemeny"]]
    mai = [o for o in valodi if o["datum"] == ma]
    mi = m.isoformat()
    folyik = next((o for o in mai if o["kezd_iso"] <= mi < o["veg_iso"] and not o["elmarad"]), None)
    kov = next((o for o in valodi if o["kezd_iso"] > mi and not o["elmarad"]), None)

    def kartya(cimke, o, ures):
        if not o:
            return f'<div class="kartya"><div class="cimke">{cimke}</div><div class="nagy">{ures}</div></div>'
        extra = f' · {e(o["terem"])}' if o["terem"] else ""
        hol = "" if o["datum"] == ma else f'{e(nap_cimke(o["datum"]))}, '
        return (f'<div class="kartya"><div class="cimke">{cimke}</div><div class="nagy">{e(o["targy"])}</div>'
                f'<div class="al">{hol}{e(o["kezd"])}–{e(o["veg"])}{extra}'
                f'{" · " + e(o["helyettes"] or o["tanar"]) if (o["helyettes"] or o["tanar"]) else ""}</div></div>')

    if folyik:
        hatra = int((datetime.fromisoformat(folyik["veg_iso"]) - m).total_seconds() // 60)
        mostkartya = kartya(f"Most · még {hatra} perc", folyik, "")
    else:
        mostkartya = kartya("Most", None, "nincs óra")
    kovkartya = kartya("Következő", kov, "a héten nincs több")
    holnap_szk = [s for s in adat["szamonkeresek"] if s["datum"] >= ma][:1]
    if holnap_szk:
        s = holnap_szk[0]
        harmadik = (f'<div class="kartya"><div class="cimke">Következő számonkérés</div><div class="nagy">{e(s["targy"])}</div>'
                    f'<div class="al">{e(nap_cimke(s["datum"]))}{" · " + e(s["mod"]) if s["mod"] else ""}'
                    f'{" · " + e(s["tema"]) if s["tema"] else ""}</div></div>')
    else:
        harmadik = '<div class="kartya"><div class="cimke">Következő számonkérés</div><div class="nagy">nincs bejelentve</div></div>'
    fo = f'<div class="fo">{mostkartya}{kovkartya}{harmadik}</div>'

    napi_esemeny = [o for o in adat["orak"] if o["datum"] == ma and o["esemeny"]]
    if mai:
        mai_html = "".join(ora_sor(o, o is folyik, o["veg_iso"] <= mi) for o in mai)
    elif napi_esemeny:
        mai_html = '<div class="kartya">' + ", ".join(e(o["targy"]) for o in napi_esemeny) + "</div>"
    else:
        mai_html = '<div class="kartya al">Ma nincs órád.</div>'
    ma_cim = "Ma" if mai or m.weekday() < 5 else "Ma (hétvége)"

    tol = date.fromisoformat(adat["tol"]) + timedelta(days=7 * het)
    napok = [tol + timedelta(days=i) for i in range(5)]
    het_orak = [o for o in adat["orak"] if napok[0].isoformat() <= o["datum"] <= napok[-1].isoformat()]
    szamok = sorted({o["oraszam"] for o in het_orak if o["oraszam"] is not None and not o["ures"]})
    racs = '<div class="racs-k"><table><tr><th></th>'
    for d in napok:
        racs += f'<th class="{"mai" if d.isoformat() == ma else ""}">{NAPOK[d.weekday()]} <span class="al">{d.month}.{d.day:02d}.</span></th>'
    racs += "</tr>"
    esemenyek = {d.isoformat(): [o for o in het_orak if o["datum"] == d.isoformat() and o["esemeny"]] for d in napok}
    if any(esemenyek.values()):
        racs += '<tr><td class="sz"></td>'
        for d in napok:
            ev = esemenyek[d.isoformat()]
            racs += f'<td class="ures">{"<br>".join(e(x["targy"]) for x in ev)}</td>' if ev else '<td class="ures"></td>'
        racs += "</tr>"
    for sz in szamok:
        racs += f'<tr><td class="sz">{sz}</td>'
        for d in napok:
            o = next((x for x in het_orak if x["datum"] == d.isoformat() and x["oraszam"] == sz and not x["ures"]), None)
            if not o:
                racs += '<td class="ures"></td>'
                continue
            osz = " ".join(filter(None, [
                "elmarad" if o["elmarad"] else "",
                "helyettes" if o["helyettes"] and not o["elmarad"] else "",
                "mai" if d.isoformat() == ma else "",
            ]))
            al = o["helyettes"] if o["helyettes"] else o["tanar"]
            jel = (" 📝" if o["szamonkeres"] else "") + (" 📚" if o["hazi"] else "")
            racs += (f'<td class="{osz}"><b>{e(o["targy"])}{jel}</b><span class="al">{e(o["terem"])}'
                     f'{" · " if o["terem"] and al else ""}{e(al)}</span></td>')
        racs += "</tr>"
    racs += "</table></div>"
    if not szamok:
        racs = '<div class="kartya al">Erre a hétre nincs óra (szünet?).</div>'
    hetvalto = ('<a class="gomb" href="/?het=0">Ez a hét</a>' if het else '<a class="gomb" href="/?het=1">Jövő hét →</a>')
    het_cim = "Jövő hét" if het else "Ez a hét"
    if date.fromisoformat(adat["tol"]) > m.date():
        het_cim = "Jövő hét" if not het else "Azutáni hét"

    szk_html = "".join(
        f'<div class="sor"><span class="ido">{e(nap_cimke(s["datum"]))}</span><span class="t"><b>{e(s["targy"])}</b>'
        f'{"<span class=\"cimk c-a\">" + e(s["mod"]) + "</span>" if s["mod"] else ""}'
        f'<div class="al">{e(s["tema"])}</div></span></div>'
        for s in adat["szamonkeresek"] if s["datum"] >= ma
    ) or '<div class="kartya al">Nincs bejelentett számonkérés.</div>'
    hazi_html = "".join(
        f'<div class="sor"><span class="ido">{e(nap_cimke(h["hatarido"]))}</span><span class="t"><b>{e(h["targy"])}</b>'
        f'{"<span class=\"cimk c-z\">kész</span>" if h["kesz"] else ""}'
        f'<div class="al" style="white-space:pre-line">{e(h["szoveg"][:400])}</div></span></div>'
        for h in adat["hazik"] if h["hatarido"] >= ma
    ) or '<div class="kartya al">Nincs nyitott házi.</div>'

    frissitve = a.get("frissitve")
    fr = helyi(frissitve).strftime("%m.%d. %H:%M") if frissitve else "–"
    ics = f'<a href="/naptar.ics?k={e(ICS_KULCS)}">naptár-feliratkozás (.ics)</a> · ' if ICS_KULCS else ""
    ki = '<form method="post" action="/kijelentkezes" style="display:inline"> · <button>Kilépés</button></form>' if JELSZO else ""
    lab = (f'<footer>Utolsó frissítés: {fr} · {ics}<a href="/belepes">Kréta-fiók</a>'
           f'<form method="post" action="/frissit" style="display:inline"> · <button>Frissítés most</button></form>{ki}</footer>')
    torzs = (fej + hiba + fo
             + f'<h2>{ma_cim}</h2><div class="lista">{mai_html}</div>'
             + f'<h2>{het_cim}</h2>{racs}<div class="gombok">{hetvalto}</div>'
             + f'<h2>Számonkérések</h2><div class="lista">{szk_html}</div>'
             + f'<h2>Házi feladatok</h2><div class="lista">{hazi_html}</div>' + lab)
    return oldal("Órarend", torzs, frissul=True)


def kezdolap_adat():
    adat = betolt("adat.json")
    a = allapot()
    if not adat:
        return {"most": "–", "kovetkezo": "nincs belépve" if a.get("belepes_kell", True) else "–", "szamonkeres": "–"}
    m = most()
    mi, ma = m.isoformat(), m.date().isoformat()
    valodi = [o for o in adat["orak"] if not o["ures"] and not o["esemeny"] and not o["elmarad"]]
    folyik = next((o for o in valodi if o["kezd_iso"] <= mi < o["veg_iso"]), None)
    kov = next((o for o in valodi if o["kezd_iso"] > mi), None)
    szk = next((s for s in adat["szamonkeresek"] if s["datum"] >= ma), None)
    def rovid(o):
        nap = "" if o["datum"] == ma else nap_cimke(o["datum"]).split(" (")[0] + " "
        return f'{o["targy"]} ({nap}{o["kezd"]})'
    return {
        "most": f'{folyik["targy"]} – {folyik["veg"]}-ig' if folyik else "nincs óra",
        "kovetkezo": rovid(kov) if kov else "–",
        "szamonkeres": f'{szk["targy"]} ({nap_cimke(szk["datum"]).split(" (")[0]})' if szk else "nincs",
        "hiba": "belépés kell" if a.get("belepes_kell") else "",
    }


def bejelentkezes_oldal(uzenet=""):
    uz = f'<div class="hiba" style="margin:12px 0">{e(uzenet)}</div>' if uzenet else ""
    torzs = f"""<h1>Órarend</h1>{uz}
<form class="belep" method="post" action="/bejelentkezes" style="margin-top:18px">
<input type="hidden" name="felhasznalo" value="orarend" autocomplete="username">
<label>Jelszó<input name="jelszo" type="password" required autofocus autocomplete="current-password"></label>
<div><button class="f">Belépés</button></div></form>
<p class="al" style="margin-top:18px">A jelszó a szerveren: <code>park jelszavak</code> → ORAREND_JELSZO</p>"""
    return oldal("Órarend – belépés", torzs)


ketlepcsos_varo = {}


def ketlepcsos_tarol(folyamat, felh, intezmeny):
    most_ = time.time()
    for k in [k for k, v in ketlepcsos_varo.items() if most_ - v["folyamat"]["ido"] > 300]:
        ketlepcsos_varo.pop(k, None)
    azon = secrets.token_urlsafe(16)
    ketlepcsos_varo[azon] = {"folyamat": folyamat, "felh": felh, "intezmeny": intezmeny}
    return azon


def ketlepcsos_oldal(azon, uzenet=""):
    uz = f'<div class="hiba" style="margin:12px 0">{e(uzenet)}</div>' if uzenet else ""
    torzs = f"""<h1>Kétlépcsős azonosítás</h1>{uz}
<p class="al">A Kréta elfogadta a jelszót, és most a második kódot kéri. Írd be a hitelesítő alkalmazásod
(vagy az e-mail / SMS) aktuális kódját. 5 perced van rá.</p>
<form class="belep" method="post" action="/ketlepcsos"><input type="hidden" name="azon" value="{e(azon)}">
<label>2FA-kód<input name="kod" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9A-Za-z ]{{4,14}}" required autofocus></label>
<div><button class="f">Belépés</button></div></form>
<footer><a href="/belepes">← vissza a Kréta-fiókhoz</a></footer>"""
    return oldal("Kréta – 2FA", torzs)


def belepes_sikeres(felh, intezmeny, jelszo):
    t = betolt("token.json") or {}
    ment("fiok.json", {"felhasznalo": felh, "intezmeny": intezmeny or t.get("intezmeny", ""), "jelszo": jelszo})
    szinkron()


def belepes_oldal(uzenet="", jo=False):
    fiok = betolt("fiok.json") or {}
    t = betolt("token.json") or {}
    kezi = betolt("kezi.json") or {}
    if not kezi.get("verifier"):
        v, c = kreta.pkce()
        kezi = {"verifier": v, "link": kreta.kezi_belepes_link(c)}
        ment("kezi.json", kezi)
    allapot_html = ""
    if t.get("nev"):
        allapot_html = f'<p class="al">Bejelentkezve: <b>{e(t["nev"])}</b> ({e(t.get("intezmeny"))})</p>'
    uz = f'<div class="{"kartya" if jo else "hiba"}" style="margin:12px 0">{e(uzenet)}</div>' if uzenet else ""
    torzs = f"""<h1>Kréta-fiók</h1>{allapot_html}{uz}
<h2>Belépés a laptopról (ajánlott)</h2>
<p class="al" style="line-height:1.7">A laptopon futtasd: <code>kreta-belepes</code>. Megnyílik egy ablak a Kréta saját belépő oldalával,
ott lépsz be (2FA-val együtt), és az ablak magától bezárul. A jelszavad nem jut el a szerverhez – a szerver csak egy
frissítő tokent kap, amivel utána magától tölti le az órarendet.</p>
<h2>Kézi belépés</h2>
<ol class="al" style="line-height:1.7"><li><a href="{e(kezi["link"])}" target="_blank" rel="noopener">Nyisd meg ezt a Kréta-belépést</a>, és lépj be.</li>
<li>A végén a böngésző egy <code>mobil.e-kreta.hu/…oauthredirect?code=…</code> címre ugrik (hibát írhat, nem baj).</li>
<li>Másold ki a címsorból a teljes címet, és illeszd be ide:</li></ol>
<form class="belep" method="post" action="/kezi"><input name="link" placeholder="https://mobil.e-kreta.hu/...?code=..." required>
<div><button class="f">Kód beváltása</button></div></form>
<details style="margin-top:26px"><summary class="al">Belépés jelszóval a szerverről (nem ajánlott – a Kréta gyanús belépésnek veheti)</summary>
<form class="belep" method="post" action="/belepes" style="margin-top:12px">
<label>Felhasználónév (oktatási azonosító)<input name="felhasznalo" value="{e(fiok.get("felhasznalo"))}" required autocomplete="username"></label>
<label>Jelszó<input name="jelszo" type="password" required autocomplete="current-password"></label>
<label>Iskola – kezdd el beírni a nevét vagy a városát, és válaszd ki a listából
<input id="iskola" name="iskola" list="iskolak" autocomplete="off" placeholder="pl. Petőfi Sándor Gimnázium"></label>
<datalist id="iskolak"></datalist>
<label>Intézmény azonosító (a keresés tölti ki; ha üresen hagyod, az iskola nevéből keresi ki)<input id="intezmeny" name="intezmeny" value="{e(fiok.get("intezmeny") or t.get("intezmeny"))}" placeholder="pl. beszc-kozgazd"></label>
<label style="display:flex;gap:8px;align-items:center"><input type="checkbox" name="megjegyez" value="1" style="width:auto"> jelszó megjegyzése (ha a token lejár, magától újra belép)</label>
<div><button class="f">Belépés</button></div></form>
<script>
(function(){{
  var be=document.getElementById("iskola"),dl=document.getElementById("iskolak"),kod=document.getElementById("intezmeny"),idoz,talalat=[];
  be.addEventListener("input",function(){{
    var v=be.value,egyezik=talalat.find(function(t){{return t.nev===v}});
    if(egyezik){{kod.value=egyezik.kod;return}}
    clearTimeout(idoz);
    if(v.length<3)return;
    idoz=setTimeout(function(){{
      fetch("/api/intezmeny?q="+encodeURIComponent(v)).then(function(r){{return r.json()}}).then(function(l){{
        talalat=l;dl.innerHTML="";
        l.forEach(function(t){{var o=document.createElement("option");o.value=t.nev;dl.appendChild(o)}});
      }});
    }},400);
  }});
}})();
</script>
</details>
<footer><a href="/">← vissza az órarendhez</a></footer>"""
    return oldal("Kréta-fiók", torzs)


def ics_ido(iso):
    return datetime.fromisoformat(iso).astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def ics_szoveg(s):
    return str(s or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def ics_sor(sor):
    b = sor.encode()
    ki = []
    while len(b) > 73:
        n = 73
        while (b[n] & 0xC0) == 0x80:
            n -= 1
        ki.append(b[:n].decode())
        b = b[n:]
    ki.append(b.decode())
    return "\r\n ".join(ki)


def naptar():
    adat = betolt("adat.json") or {"orak": [], "szamonkeresek": []}
    st = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    sorok = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//szerverpark//orarend//HU",
             "X-WR-CALNAME:Órarend", "X-PUBLISHED-TTL:PT30M", "REFRESH-INTERVAL;VALUE=DURATION:PT30M"]
    for o in adat["orak"]:
        if o["ures"] or o["esemeny"]:
            continue
        cim = ("ELMARAD: " if o["elmarad"] else "") + o["targy"] + (" (helyettesítés)" if o["helyettes"] and not o["elmarad"] else "")
        leiras = "\n".join(filter(None, [
            f'Tanár: {o["helyettes"] or o["tanar"]}' if (o["helyettes"] or o["tanar"]) else "",
            f'Téma: {o["tema"]}' if o["tema"] else "",
            "Számonkérés!" if o["szamonkeres"] else "",
            "Házi feladat van" if o["hazi"] else "",
        ]))
        sorok += ["BEGIN:VEVENT", f'UID:{ics_szoveg(o["uid"] or ora_kulcs(o))}@park-orarend', f"DTSTAMP:{st}",
                  f'DTSTART:{ics_ido(o["kezd_iso"])}', f'DTEND:{ics_ido(o["veg_iso"])}',
                  f"SUMMARY:{ics_szoveg(cim)}"]
        if o["terem"]:
            sorok.append(f'LOCATION:{ics_szoveg(o["terem"])}')
        if leiras:
            sorok.append(f"DESCRIPTION:{ics_szoveg(leiras)}")
        if o["elmarad"]:
            sorok.append("STATUS:CANCELLED")
        sorok.append("END:VEVENT")
    for s in adat["szamonkeresek"]:
        if not s["datum"]:
            continue
        d = date.fromisoformat(s["datum"])
        sorok += ["BEGIN:VEVENT", f'UID:szk-{ics_szoveg(s["uid"])}@park-orarend', f"DTSTAMP:{st}",
                  f"DTSTART;VALUE=DATE:{d:%Y%m%d}", f"DTEND;VALUE=DATE:{d + timedelta(days=1):%Y%m%d}",
                  f'SUMMARY:{ics_szoveg("📝 " + s["targy"] + (" – " + s["mod"] if s["mod"] else ""))}',
                  f'DESCRIPTION:{ics_szoveg(s["tema"])}', "END:VEVENT"]
    sorok.append("END:VCALENDAR")
    return "\r\n".join(ics_sor(x) for x in sorok) + "\r\n"


class Kezelo(BaseHTTPRequestHandler):
    server_version = "park-orarend"

    def log_message(self, format, *args):
        if "/egeszseg" not in (args[0] if args else ""):
            print(self.address_string(), format % args, flush=True)

    def valasz(self, kod, torzs, tipus="text/html; charset=utf-8", fejlec=None):
        b = torzs.encode() if isinstance(torzs, str) else torzs
        self.send_response(kod)
        self.send_header("Content-Type", tipus)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        for k, v in (fejlec or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(b)

    def at(self, hova, fejlec=None):
        self.valasz(303, "", fejlec={"Location": hova, **(fejlec or {})})

    def ip(self):
        return self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()

    def suti(self, ertek, max_age):
        biztonsagos = "; Secure" if (self.headers.get("Host") or "").split(":")[0].endswith(".ts.net") else ""
        return f"{SUTI}={ertek}; Path=/; Max-Age={max_age}; HttpOnly; SameSite=Lax{biztonsagos}"

    def belepve(self):
        return munkamenet_jo(self.headers.get("Cookie"))

    def urlap(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > 20000:
            return {}
        return {k: v[0] for k, v in urllib.parse.parse_qs(self.rfile.read(n).decode()).items()}

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/bejelentkezes":
            return self.valasz(200, bejelentkezes_oldal())
        if u.path == "/api/kezdolap":
            if not ICS_KULCS or not secrets.compare_digest(q.get("k", [""])[0], ICS_KULCS):
                return self.valasz(403, "{}", "application/json")
            return self.valasz(200, json.dumps(kezdolap_adat(), ensure_ascii=False), "application/json; charset=utf-8")
        if u.path not in ("/naptar.ics", "/egeszseg") and not self.belepve():
            return self.at("/bejelentkezes")
        if u.path == "/":
            het = 1 if q.get("het", ["0"])[0] == "1" else 0
            return self.valasz(200, fooldal(het))
        if u.path == "/belepes":
            return self.valasz(200, belepes_oldal())
        if u.path == "/api/kezi-link":
            v, c = kreta.pkce()
            ment("kezi.json", {"verifier": v, "link": kreta.kezi_belepes_link(c)})
            return self.valasz(200, json.dumps({"link": kreta.kezi_belepes_link(c)}), "application/json; charset=utf-8")
        if u.path == "/api/intezmeny":
            try:
                lista = kreta.intezmeny_kereses(q.get("q", [""])[0])
            except Exception as hiba:
                print("intézmény-keresés hiba:", hiba, flush=True)
                lista = []
            return self.valasz(200, json.dumps(lista, ensure_ascii=False), "application/json; charset=utf-8")
        if u.path == "/naptar.ics":
            if not ICS_KULCS or not secrets.compare_digest(q.get("k", [""])[0], ICS_KULCS):
                return self.valasz(403, "tiltott", "text/plain; charset=utf-8")
            return self.valasz(200, naptar(), "text/calendar; charset=utf-8")
        if u.path == "/api/orarend.json":
            return self.valasz(200, json.dumps({"allapot": allapot(), **(betolt("adat.json") or {})},
                                               ensure_ascii=False), "application/json; charset=utf-8")
        if u.path == "/egeszseg":
            return self.valasz(200, "ok", "text/plain")
        self.valasz(404, oldal("Nincs ilyen", '<h1>Nincs ilyen oldal</h1><a href="/">vissza</a>'))

    def do_POST(self):
        if self.headers.get("Sec-Fetch-Site") not in (None, "same-origin", "none"):
            return self.valasz(403, "tiltott", "text/plain; charset=utf-8")
        u = urllib.parse.urlparse(self.path)
        f = self.urlap()
        if u.path == "/bejelentkezes":
            ip = self.ip()
            if tul_sok_probalkozas(ip):
                return self.valasz(429, bejelentkezes_oldal("Túl sok rossz próbálkozás – várj 15 percet."))
            if JELSZO and hmac.compare_digest(f.get("jelszo", "").encode(), JELSZO.encode()):
                sikertelen.pop(ip, None)
                return self.at("/", {"Set-Cookie": self.suti(munkamenet_uj(), SUTI_NAP * 86400)})
            sikertelen.setdefault(ip, []).append(time.time())
            time.sleep(1.5)
            return self.valasz(200, bejelentkezes_oldal("Rossz jelszó."))
        if not self.belepve():
            return self.valasz(403, "előbb lépj be", "text/plain; charset=utf-8")
        if u.path == "/kijelentkezes":
            return self.at("/bejelentkezes", {"Set-Cookie": self.suti("", 0)})
        if u.path == "/frissit":
            threading.Thread(target=szinkron, daemon=True).start()
            time.sleep(4)
            return self.at("/")
        if u.path == "/belepes":
            felh_nyers, jelszo_nyers = f.get("felhasznalo", ""), f.get("jelszo", "")
            felh, jelszo = re.sub(r"\s+", "", felh_nyers), jelszo_nyers.strip()
            print(f"Kréta-belépés űrlapról: felhasználónév {len(felh)} karakter, csak szám: {felh.isdigit()}, "
                  f"szóköz volt benne: {felh != felh_nyers}; jelszó szélén szóköz: {jelszo != jelszo_nyers}, "
                  f"ékezetes/nem ASCII jelszó: {not jelszo.isascii()}", flush=True)
            try:
                intezmeny = iskola_kod(f.get("intezmeny", "").strip() or f.get("iskola", ""))
                token_ment(kreta.jelszavas_belepes(felh, jelszo, intezmeny))
            except kreta.KetlepcsosKell as k2:
                print(f"Kréta-belépés: 2FA-kód kell ({intezmeny})", flush=True)
                return self.valasz(200, ketlepcsos_oldal(ketlepcsos_tarol(k2.folyamat, felh, intezmeny)))
            except kreta.KretaHiba as hiba:
                print(f"Kréta-belépés sikertelen ({intezmeny}): {hiba}", flush=True)
                return self.valasz(200, belepes_oldal(f"Nem sikerült: {hiba}"))
            except Exception as hiba:
                traceback.print_exc()
                return self.valasz(200, belepes_oldal(f"Nem sikerült: {hiba}"))
            belepes_sikeres(felh, intezmeny, jelszo if f.get("megjegyez") else "")
            return self.at("/")
        if u.path == "/ketlepcsos":
            azon = f.get("azon", "")
            varo = ketlepcsos_varo.pop(azon, None)
            if not varo:
                return self.valasz(200, belepes_oldal("Lejárt vagy már felhasznált 2FA-lépés – lépj be újra a jelszóval."))
            try:
                token_ment(kreta.ketlepcsos_befejez(varo["folyamat"], f.get("kod", "")))
            except kreta.KetlepcsosKell as k2:
                varo["folyamat"] = k2.folyamat
                ketlepcsos_varo[azon] = varo
                return self.valasz(200, ketlepcsos_oldal(azon, f"Nem sikerült: {k2}"))
            except kreta.KretaHiba as hiba:
                print(f"Kréta 2FA sikertelen: {hiba}", flush=True)
                return self.valasz(200, belepes_oldal(f"Nem sikerült: {hiba}"))
            except Exception as hiba:
                traceback.print_exc()
                return self.valasz(200, belepes_oldal(f"Nem sikerült: {hiba}"))
            print("Kréta-belépés 2FA-val sikeres", flush=True)
            belepes_sikeres(varo["felh"], varo["intezmeny"], "")
            return self.at("/")
        if u.path == "/kezi":
            kezi = betolt("kezi.json") or {}
            try:
                kod = kreta.kod_a_linkbol(f.get("link", ""))
                token_ment(kreta.kod_csere(kod, kezi.get("verifier", "")))
            except Exception as hiba:
                try:
                    os.remove(ut("kezi.json"))
                except OSError:
                    pass
                return self.valasz(200, belepes_oldal(f"Nem sikerült: {hiba}. Kérj új linket (frissítsd az oldalt), és próbáld újra."))
            os.remove(ut("kezi.json"))
            t = betolt("token.json") or {}
            fiok = betolt("fiok.json") or {}
            fiok.setdefault("intezmeny", t.get("intezmeny", ""))
            ment("fiok.json", fiok)
            szinkron()
            return self.at("/")
        self.valasz(404, "nincs", "text/plain")


def main():
    os.makedirs(ADAT, exist_ok=True)
    threading.Thread(target=szinkron_ciklus, daemon=True).start()
    threading.Thread(target=esti_ciklus, daemon=True).start()
    print(f"park-orarend fut a {PORT}-es porton", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Kezelo).serve_forever()


if __name__ == "__main__":
    main()
