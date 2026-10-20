__lazy_modules__ = [
    "base64",
    "hashlib",
    "html",
    "json",
    "re",
    "secrets",
    "time",
    "urllib.error",
    "urllib.parse",
    "urllib.request",
    "html.parser",
    "http.cookiejar",
]

import base64
import hashlib
import html
import json
import re
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from http.cookiejar import CookieJar

IDP = "https://idp.e-kreta.hu"
CLIENT_ID = "kreta-ellenorzo-student-mobile-ios"
REDIRECT_URI = "https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect"
SCOPE = (
    "openid email offline_access kreta-ellenorzo-webapi.public "
    "kreta-eugyintezes-webapi.public kreta-fileservice-webapi.public "
    "kreta-mobile-global-webapi.public kreta-dkt-webapi.public kreta-ier-webapi.public"
)
BONGESZO = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
API_FEJLEC = {
    "User-Agent": "hu.ekreta.tanulo/1.0.5/Android/0/0",
    "apiKey": "21ff6c25-d1da-4a68-a811-c881a6057463",
}


class KretaHiba(Exception):
    pass


class BelepesKell(KretaHiba):
    pass


class KetlepcsosKell(BelepesKell):
    def __init__(self, folyamat, uzenet="a Kréta kétlépcsős azonosító kódot kér"):
        super().__init__(uzenet)
        self.folyamat = folyamat


class _Urlapok(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urlapok = []

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if tag == "form":
            self.urlapok.append({"action": a.get("action", ""), "method": a.get("method", "get").lower(), "mezok": []})
        elif tag in ("input", "select", "button") and self.urlapok and a.get("name"):
            alap = {"input": "text", "select": "select", "button": "submit"}[tag]
            tipus = alap if tag == "select" else a.get("type", alap).lower()
            self.urlapok[-1]["mezok"].append({"nev": a["name"], "tipus": tipus, "ertek": a.get("value", "")})


class _NemKovet(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def _b64(adat):
    return base64.urlsafe_b64encode(adat).rstrip(b"=").decode()


def pkce():
    verifier = _b64(secrets.token_bytes(32))
    challenge = _b64(hashlib.sha256(verifier.encode()).digest())
    return verifier, challenge


def authorize_query(challenge, nonce=None, state="kreten_student_mobile"):
    return urllib.parse.urlencode(
        {
            "prompt": "login",
            "nonce": nonce or _b64(secrets.token_bytes(32)),
            "response_type": "code",
            "code_challenge_method": "S256",
            "scope": SCOPE,
            "code_challenge": challenge,
            "redirect_uri": REDIRECT_URI,
            "client_id": CLIENT_ID,
            "state": state,
            "suppressed_prompt": "login",
        },
        quote_via=urllib.parse.quote,
    )


def kezi_belepes_link(challenge):
    return f"{IDP}/connect/authorize?{authorize_query(challenge)}"


class _Kliens:
    def __init__(self):
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(CookieJar()), _NemKovet()
        )

    def kuld(self, modszer, url, adat=None, fejlec=None, kovet=True, ido=30):
        for _ in range(10):
            torzs = None
            h = {"User-Agent": BONGESZO}
            h.update(fejlec or {})
            if adat is not None:
                torzs = urllib.parse.urlencode(adat).encode()
                h.setdefault("Content-Type", "application/x-www-form-urlencoded")
            kerelem = urllib.request.Request(url, data=torzs, headers=h, method=modszer)
            try:
                with self.opener.open(kerelem, timeout=ido) as v:
                    return v.status, dict(v.headers), v.read().decode("utf-8", "replace"), url
            except urllib.error.HTTPError as e:
                hely = e.headers.get("Location")
                if e.code in (301, 302, 303, 307, 308) and hely:
                    uj = urllib.parse.urljoin(url, hely)
                    if not kovet:
                        return e.code, dict(e.headers), "", uj
                    url, modszer, adat = uj, "GET", None
                    continue
                return e.code, dict(e.headers), e.read().decode("utf-8", "replace"), url
        raise KretaHiba("túl sok átirányítás")


def _token_keres(adat):
    k = _Kliens()
    allapot, _, torzs, _ = k.kuld("POST", f"{IDP}/connect/token", adat=adat, fejlec=API_FEJLEC)
    try:
        valasz = json.loads(torzs)
    except ValueError:
        raise KretaHiba(f"a token-végpont nem JSON-t adott (HTTP {allapot})")
    if allapot != 200 or "access_token" not in valasz:
        hiba = valasz.get("error_description") or valasz.get("error") or f"HTTP {allapot}"
        if allapot in (400, 401):
            raise BelepesKell(hiba)
        raise KretaHiba(hiba)
    return valasz


def intezmeny_kereses(szoveg):
    if len(szoveg.strip()) < 3:
        return []
    url = f"{IDP}/logininstituteselector?" + urllib.parse.urlencode({"searchValue": szoveg.strip()})
    _, _, torzs, _ = _Kliens().kuld("GET", url, ido=15)
    talalat = []
    for kod, nev in re.findall(r'data-val="([^"]*)"[^>]*>([^<]*)<', torzs):
        if kod:
            talalat.append({"kod": html.unescape(kod), "nev": html.unescape(nev).strip()})
    return talalat[:25]


def kod_csere(kod, verifier):
    return _token_keres(
        {
            "code": kod,
            "code_verifier": verifier,
            "redirect_uri": REDIRECT_URI,
            "client_id": CLIENT_ID,
            "grant_type": "authorization_code",
        }
    )


def kod_a_linkbol(szoveg):
    szoveg = szoveg.strip()
    m = re.search(r"[?&#]code=([^&#\s]+)", szoveg)
    if m:
        return urllib.parse.unquote(m.group(1))
    if re.fullmatch(r"[A-Za-z0-9_\-\.]{20,}", szoveg):
        return szoveg
    raise KretaHiba("a beillesztett szövegben nincs 'code=' rész")


def _hibaszoveg(oldal):
    hibak = re.search(r'validation-summary-errors[^>]*>(.*?)</div>', oldal, re.S) or re.search(
        r'class="[^"]*(?:field-validation-error|alert-danger)[^"]*"[^>]*>(.*?)</', oldal, re.S
    )
    if not hibak:
        return ""
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", hibak.group(1)))).strip()


def _ketlepcsos_urlap(k, url, oldal, verifier, return_url):
    p = _Urlapok()
    p.feed(oldal)
    for u in p.urlapok:
        if u["method"] != "post":
            continue
        jeloltek = [m for m in u["mezok"] if m["tipus"] in ("text", "number", "tel", "password") and not m["nev"].startswith("__")]
        jelolt = next((m for m in jeloltek if re.search(r"code|kod", m["nev"], re.I)), jeloltek[0] if jeloltek else None)
        if not jelolt:
            continue
        mezok = {}
        for m in u["mezok"]:
            if m["nev"] == jelolt["nev"] or m["tipus"] in ("submit", "button"):
                continue
            if m["tipus"] == "checkbox":
                mezok[m["nev"]] = m["ertek"] or "true"
            elif m["nev"] not in mezok:
                mezok[m["nev"]] = m["ertek"]
        return {
            "kliens": k,
            "verifier": verifier,
            "return_url": return_url,
            "url": url,
            "action": urllib.parse.urljoin(url, html.unescape(u["action"]) or url),
            "mezok": mezok,
            "kod_mezo": jelolt["nev"],
            "ido": time.time(),
        }
    nevek = [[m["nev"] + ":" + m["tipus"] for m in u["mezok"]] for u in p.urlapok]
    print(f"Kréta 2FA-oldal ismeretlen formájú: {urllib.parse.urlsplit(url).path} űrlapok={nevek}", flush=True)
    return None


def _kod_kovetes(k, url, return_url):
    for _ in range(10):
        if url.startswith(REDIRECT_URI) or "code=" in url and "oauthredirect" in url:
            return kod_a_linkbol(url)
        allapot, _, _, uj = k.kuld("GET", url, kovet=False)
        if allapot not in (301, 302, 303, 307, 308):
            break
        url = uj
    allapot, _, _, hely = k.kuld("GET", f"{IDP}{return_url}", kovet=False)
    if "code=" not in hely:
        raise BelepesKell("a Kréta nem adott belépési kódot – használd a kézi belépést")
    return kod_a_linkbol(hely)


def ketlepcsos_befejez(folyamat, kod):
    kod = re.sub(r"\s+", "", kod or "")
    if not re.fullmatch(r"[0-9A-Za-z]{4,12}", kod):
        raise KetlepcsosKell(folyamat, "a kód 4–12 számjegy/betű legyen")
    if time.time() - folyamat["ido"] > 300:
        raise BelepesKell("lejárt a 2FA-lépés (5 perc) – lépj be újra a jelszóval")
    k = folyamat["kliens"]
    adat = dict(folyamat["mezok"])
    adat[folyamat["kod_mezo"]] = kod
    allapot, _, oldal, hely = k.kuld(
        "POST", folyamat["action"], adat=adat, fejlec={"Origin": IDP, "Referer": folyamat["url"]}, kovet=False
    )
    if allapot == 200:
        szoveg = _hibaszoveg(oldal) or "a Kréta nem fogadta el a kódot"
        uj = _ketlepcsos_urlap(k, folyamat["url"], oldal, folyamat["verifier"], folyamat["return_url"])
        if uj:
            raise KetlepcsosKell(uj, szoveg)
        raise BelepesKell(szoveg)
    if allapot not in (301, 302, 303, 307, 308):
        raise BelepesKell(f"a 2FA-kód beküldése nem sikerült (HTTP {allapot})")
    return kod_csere(_kod_kovetes(k, hely, folyamat["return_url"]), folyamat["verifier"])


def jelszavas_belepes(felhasznalo, jelszo, intezmeny):
    verifier, challenge = pkce()
    q = authorize_query(challenge)
    k = _Kliens()
    allapot, _, oldal, vegso = k.kuld("GET", f"{IDP}/connect/authorize?{q}")
    if allapot != 200:
        raise KretaHiba(f"a belépő oldal nem töltődött be (HTTP {allapot})")
    m = re.search(r'name="__RequestVerificationToken"[^>]*value="([^"]+)"', oldal) or re.search(
        r'value="([^"]+)"[^>]*name="__RequestVerificationToken"', oldal
    )
    if not m:
        raise KretaHiba("a belépő oldalon nincs ellenőrző token – a Kréta megváltozhatott")
    return_url = "/connect/authorize/callback?" + q
    time.sleep(0.5)
    allapot, _, valasz, post_hely = k.kuld(
        "POST",
        f"{IDP}/account/login",
        adat={
            "ReturnUrl": return_url,
            "IsTemporaryLogin": "False",
            "UserName": felhasznalo,
            "Password": jelszo,
            "InstituteCode": intezmeny,
            "ClientId": "",
            "loginType": "InstituteLogin",
            "__RequestVerificationToken": m.group(1),
        },
        fejlec={"Origin": IDP, "Referer": vegso},
        kovet=False,
    )
    hibak = re.search(r'validation-summary-errors[^>]*>(.*?)</div>', valasz, re.S)
    if hibak:
        szoveg = html.unescape(re.sub(r"<[^>]+>", " ", hibak.group(1)))
        szoveg = re.sub(r"\s+", " ", szoveg).strip() or "a Kréta elutasította a belépést"
        if "captcha" in szoveg.lower():
            szoveg += " – most a kézi belépés megy (lent), vagy próbáld később"
        raise BelepesKell(szoveg)
    if allapot not in (200, 302):
        if "captcha" in valasz.lower():
            raise BelepesKell("a Kréta captchát kér – használd a kézi belépést")
        raise BelepesKell(f"hibás felhasználónév, jelszó vagy intézménykód (HTTP {allapot})")
    if allapot in (301, 302, 303) and re.search(r"twofactor|2fa", post_hely, re.I):
        allapot, _, oldal2, url2 = k.kuld("GET", post_hely)
        folyamat = _ketlepcsos_urlap(k, url2, oldal2, verifier, return_url) if allapot == 200 else None
        if folyamat:
            raise KetlepcsosKell(folyamat)
        raise BelepesKell("a fiókodon kétlépcsős azonosítás (2FA) van, de a kódkérő oldalát nem ismertem fel – a kézi belépéssel tudsz belépni")
    return kod_csere(_kod_kovetes(k, f"{IDP}{return_url}", return_url), verifier)


def frissites(refresh_token, intezmeny):
    return _token_keres(
        {
            "institute_code": intezmeny,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
            "client_id": CLIENT_ID,
        }
    )


def jwt_torzs(token):
    resz = token.split(".")[1]
    resz += "=" * (-len(resz) % 4)
    return json.loads(base64.urlsafe_b64decode(resz))


def api_get(access_token, intezmeny, ut, parameterek=None):
    url = f"https://{intezmeny}.e-kreta.hu/ellenorzo/v3/{ut}"
    if parameterek:
        url += "?" + urllib.parse.urlencode(parameterek)
    h = dict(API_FEJLEC)
    h["Authorization"] = f"Bearer {access_token}"
    allapot, _, torzs, _ = _Kliens().kuld("GET", url, fejlec=h, ido=40)
    if allapot == 401:
        raise BelepesKell("lejárt a token")
    if allapot != 200:
        raise KretaHiba(f"{ut}: HTTP {allapot}")
    return json.loads(torzs)
