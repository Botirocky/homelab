#!/usr/bin/env python3
"""Privát Csevegő — adatvédelem-központú, többszobás csevegőszerver.

Funkciók:
  - Szobák (külön előzményekkel; az előzmény helyben, a `chat_data/` mappában
    JSONL-fájlokban tárolódik, így szerver-újraindítás után is megmarad)
  - Végpontok közötti titkosítás támogatása (a szerver csak titkosított
    szöveget továbbít, a kulcsot sosem látja — a kliens oldalon történik minden)
  - Privát üzenetek (DM) felhasználók között
  - "Éppen ír…" jelzés
  - VPN-állapot ellenőrzés (Mullvad / Proton / egyéb felismerés)
  - HTTPS/WSS támogatás (ha van cert.pem + key.pem a mappában)
  - PWA fájlok kiszolgálása (telepíthető app minden platformon)

Indítás:  python3 server.py
Megnyitás:  http://localhost:8765  (HTTPS-sel: https://localhost:8765)
"""

__lazy_modules__ = [
    "argparse",
    "asyncio",
    "hashlib",
    "hmac",
    "http",
    "json",
    "logging",
    "pathlib",
    "re",
    "secrets",
    "ssl",
    "time",
    "urllib.request",
    "collections",
    "datetime",
    "websockets",
    "websockets.http11",
    "websockets.datastructures",
]

import argparse
import asyncio
import hashlib
import hmac
import http
import json
import logging
import pathlib
import re
import secrets
import ssl
import time
import urllib.request
from collections import deque
from datetime import datetime

import websockets
from websockets.http11 import Response
from websockets.datastructures import Headers

PORT = 8765
BASE_DIR = pathlib.Path(__file__).parent
DATA_DIR = BASE_DIR / "chat_data"
ACCOUNTS_FILE = DATA_DIR / "accounts.json"
HISTORY_LIMIT = 50

STATIC_FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/manifest.webmanifest": ("manifest.webmanifest", "application/manifest+json"),
    "/sw.js": ("sw.js", "text/javascript; charset=utf-8"),
    "/icon.svg": ("icon.svg", "image/svg+xml"),
    "/icon-192.png": ("icon-192.png", "image/png"),
    "/icon-512.png": ("icon-512.png", "image/png"),
    "/apple-touch-icon.png": ("apple-touch-icon.png", "image/png"),
    "/admin": ("admin.html", "text/html; charset=utf-8"),
}

REACTIONS = {"👍", "❤️", "😂", "🎉", "😮"}

MAX_CONN_PER_IP = 8
RATE_MSGS = 15
RATE_WINDOW = 10.0
JOIN_TIMEOUT = 15
MAX_WS_FRAME = 64 * 1024
_CTRL_CHARS = re.compile(r"[\x00-\x1f\x7f​-‏‪-‮]")

conn_per_ip = {}

rooms = {}

DEV = False
admin_clients = set()
banned_ips = set()
admin_events = deque(maxlen=200)
stats = {"start": time.time(), "total_conns": 0, "total_msgs": 0}
log = logging.getLogger("csevego")

def load_admin_token():
    """Admin token betöltése/létrehozása (.admin_token, csak a tulaj olvashatja)."""
    f = BASE_DIR / ".admin_token"
    if f.exists():
        return f.read_text().strip()
    token = secrets.token_urlsafe(32)
    f.write_text(token + "\n")
    f.chmod(0o600)
    return token

ADMIN_TOKEN = load_admin_token()

def token_ok(token):
    return hmac.compare_digest(str(token or ""), ADMIN_TOKEN)

PBKDF2_ITERATIONS = 200_000

def load_accounts():
    if ACCOUNTS_FILE.exists():
        try:
            return json.loads(ACCOUNTS_FILE.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}
    return {}

accounts = load_accounts()

def save_accounts():
    DATA_DIR.mkdir(exist_ok=True)
    ACCOUNTS_FILE.write_text(
        json.dumps(accounts, ensure_ascii=False, indent=1), encoding="utf-8")
    ACCOUNTS_FILE.chmod(0o600)

def hash_password(password, salt):
    return hashlib.pbkdf2_hmac(
        "sha256", password.encode(), salt, PBKDF2_ITERATIONS).hex()

def register_account(nick, password):
    salt = secrets.token_bytes(16)
    accounts[nick.lower()] = {
        "nick": nick,
        "salt": salt.hex(),
        "hash": hash_password(password, salt),
        "created": datetime.now().isoformat(timespec="seconds"),
    }
    save_accounts()

def verify_account(acc, password):
    return hmac.compare_digest(
        hash_password(password, bytes.fromhex(acc["salt"])), acc["hash"])

def admin_log(text):
    entry = {"time": datetime.now().strftime("%H:%M:%S"), "text": text}
    admin_events.append(entry)
    if DEV:
        log.info(text)
    if admin_clients:
        data = json.dumps({"type": "admin_event", **entry}, ensure_ascii=False)
        websockets.broadcast(admin_clients, data)

def admin_state():
    return {
        "type": "admin_state",
        "dev": DEV,
        "uptime": int(time.time() - stats["start"]),
        "total_conns": stats["total_conns"],
        "total_msgs": stats["total_msgs"],
        "active_conns": sum(conn_per_ip.values()),
        "accounts": len(accounts),
        "rooms": [
            {
                "name": name,
                "users": [{"nick": n, "ip": client_ip(ws)}
                          for ws, n in room["clients"].items()],
                "history_len": len(room["history"]),
            }
            for name, room in rooms.items()
        ],
        "bans": sorted(banned_ips),
        "conns_per_ip": dict(conn_per_ip),
    }

def push_admin_state():
    if admin_clients:
        data = json.dumps(admin_state(), ensure_ascii=False)
        websockets.broadcast(admin_clients, data)

def clean(text, limit):
    """Vezérlő- és irányváltó karakterek eltávolítása (spoofing ellen)."""
    return _CTRL_CHARS.sub("", str(text)).strip()[:limit]

def client_ip(websocket):
    addr = websocket.remote_address
    return addr[0] if addr else "?"

class RateLimiter:
    """Csúszóablakos sebességkorlát — üzenetáradat (flood) ellen."""

    def __init__(self):
        self.stamps = deque()
        self.strikes = 0

    def allow(self):
        t = time.monotonic()
        while self.stamps and t - self.stamps[0] > RATE_WINDOW:
            self.stamps.popleft()
        if len(self.stamps) >= RATE_MSGS:
            self.strikes += 1
            return False
        self.stamps.append(t)
        return True

_vpn_cache = {"time": 0.0, "data": None}

def now():
    return datetime.now().strftime("%H:%M")

def room_file(name):
    """A szoba előzményfájljának útvonala (fájlnévbe nem kerülhet /, .. stb.)."""
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", name)[:64] or "szoba"
    return DATA_DIR / f"{safe}.jsonl"

def load_history(name):
    """Előzmény betöltése lemezről (legfeljebb HISTORY_LIMIT üzenet)."""
    path = room_file(name)
    hist = deque(maxlen=HISTORY_LIMIT)
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines()[-HISTORY_LIMIT:]:
            try:
                hist.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return hist

def append_history(name, payload):
    """Üzenet hozzáfűzése a szoba helyi előzményfájljához."""
    DATA_DIR.mkdir(exist_ok=True)
    with open(room_file(name), "a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")

def rewrite_history(name, hist):
    """Az előzményfájl újraírása (reakció, szerkesztés vagy törlés után)."""
    DATA_DIR.mkdir(exist_ok=True)
    with open(room_file(name), "w", encoding="utf-8") as f:
        for payload in hist:
            f.write(json.dumps(payload, ensure_ascii=False) + "\n")

def clear_history_file(name):
    room_file(name).unlink(missing_ok=True)

def find_message(room, mid):
    """Üzenet keresése azonosító alapján a szoba (memóriabeli) előzményében."""
    if not mid:
        return None
    for payload in room["history"]:
        if payload.get("id") == mid:
            return payload
    return None

def get_room(name):
    if name not in rooms:
        rooms[name] = {"clients": {}, "history": load_history(name)}
    return rooms[name]

async def broadcast(room_name, payload, exclude=None):
    room = rooms.get(room_name)
    if not room:
        return
    data = json.dumps(payload, ensure_ascii=False)
    targets = [ws for ws in room["clients"] if ws is not exclude]
    if targets:
        websockets.broadcast(targets, data)

async def send_userlist(room_name):
    room = rooms.get(room_name)
    if room:
        users = sorted(set(room["clients"].values()), key=str.lower)
        await broadcast(room_name, {"type": "users", "users": users})

async def kick_user(room_name, nick):
    room = rooms.get(room_name)
    if not room:
        return False
    for ws, n in list(room["clients"].items()):
        if n == nick:
            await ws.close(4001, "Az üzemeltető kizárt a szobából")
            return True
    return False

async def ban_ip(ip):
    banned_ips.add(ip)
    for room in list(rooms.values()):
        for ws in list(room["clients"]):
            if client_ip(ws) == ip:
                await ws.close(4002, "Az üzemeltető kitiltott")

async def admin_handler(websocket, first_msg):
    """Hitelesített admin kapcsolat: állapot + eseménynapló + parancsok."""
    if not token_ok(first_msg.get("token")):
        await asyncio.sleep(1)
        admin_log(f"SIKERTELEN admin belépés innen: {client_ip(websocket)}")
        await websocket.close(4003, "Hibás token")
        return

    admin_clients.add(websocket)
    admin_log(f"Admin belépett ({client_ip(websocket)})")
    try:
        await websocket.send(json.dumps({
            "type": "admin_ok",
            "events": list(admin_events),
        }, ensure_ascii=False))
        await websocket.send(json.dumps(admin_state(), ensure_ascii=False))

        async for raw in websocket:
            msg = json.loads(raw)
            if msg.get("type") != "admin_cmd":
                continue
            cmd = msg.get("cmd")

            if cmd == "refresh":
                await websocket.send(json.dumps(admin_state(), ensure_ascii=False))

            elif cmd == "kick":
                ok = await kick_user(msg.get("room"), msg.get("nick"))
                admin_log(f"Kizárás: {msg.get('nick')} ({msg.get('room')})"
                          + ("" if ok else " — nem található"))

            elif cmd == "ban":
                ip = clean(msg.get("ip", ""), 45)
                if ip:
                    await ban_ip(ip)
                    admin_log(f"IP kitiltva: {ip}")

            elif cmd == "unban":
                banned_ips.discard(msg.get("ip"))
                admin_log(f"Kitiltás feloldva: {msg.get('ip')}")

            elif cmd == "announce":
                text = clean(msg.get("text", ""), 500)
                if text:
                    for name in list(rooms):
                        await broadcast(name, {
                            "type": "info",
                            "text": f"Üzemeltetői közlemény: {text}",
                            "time": now(),
                        })
                    admin_log(f"Közlemény kiküldve: {text}")

            elif cmd == "clear":
                target = str(msg.get("room") or "")
                room = rooms.get(target)
                if room:
                    room["history"].clear()
                if target:
                    clear_history_file(target)
                admin_log(f"Előzmény törölve: {target}")

            push_admin_state()
    except (websockets.ConnectionClosed, json.JSONDecodeError):
        pass
    finally:
        admin_clients.discard(websocket)
        admin_log(f"Admin kilépett ({client_ip(websocket)})")

async def handler(websocket):
    nick = None
    room_name = None
    ip = client_ip(websocket)

    if ip in banned_ips:
        await websocket.close(4002, "Kitiltva")
        return

    if conn_per_ip.get(ip, 0) >= MAX_CONN_PER_IP:
        await websocket.close(4008, "Túl sok kapcsolat erről a címről")
        return
    conn_per_ip[ip] = conn_per_ip.get(ip, 0) + 1
    limiter = RateLimiter()

    try:
        raw = await asyncio.wait_for(websocket.recv(), timeout=JOIN_TIMEOUT)
        msg = json.loads(raw)
        if msg.get("type") == "admin":
            await admin_handler(websocket, msg)
            return
        if msg.get("type") != "join":
            return
        nick = clean(msg.get("nick", ""), 24)
        password = str(msg.get("password", ""))[:64]
        room_name = clean(msg.get("room", ""), 32) or "kozos"

        async def reject(text):
            await websocket.send(json.dumps(
                {"type": "join_error", "text": text}, ensure_ascii=False))
            await websocket.close(4004, "Sikertelen belépés")

        if not nick or not password:
            await reject("A belépéshez becenév és fiókjelszó kell.")
            return

        acc = accounts.get(nick.lower())
        registered_now = False
        if acc is None:
            register_account(nick, password)
            registered_now = True
            admin_log(f"Új fiók regisztrálva: {nick} ({ip})")
        elif verify_account(acc, password):
            nick = acc["nick"]
        else:
            await asyncio.sleep(1)
            admin_log(f"HIBÁS jelszó: {nick} ({ip})")
            await reject("Hibás jelszó — ezt a becenevet más regisztrálta.")
            return

        room = get_room(room_name)
        room["clients"][websocket] = nick

        await websocket.send(json.dumps({
            "type": "welcome",
            "nick": nick,
            "room": room_name,
            "registered": registered_now,
            "history": list(room["history"]),
        }, ensure_ascii=False))
        await broadcast(room_name, {"type": "info", "text": f"{nick} csatlakozott", "time": now()})
        await send_userlist(room_name)
        stats["total_conns"] += 1
        admin_log(f"Belépés: {nick} → #{room_name} ({ip})")
        push_admin_state()

        async for raw in websocket:
            msg = json.loads(raw)
            mtype = msg.get("type")

            if mtype in ("message", "dm", "react", "edit", "delete") and not limiter.allow():
                if limiter.strikes > 30:
                    admin_log(f"Flood miatt bontva: {nick} ({ip})")
                    await websocket.close(4009, "Üzenetáradat — kapcsolat bontva")
                    break
                await websocket.send(json.dumps({
                    "type": "info",
                    "text": "Lassíts! Túl sok üzenetet küldesz.",
                    "time": now(),
                }, ensure_ascii=False))
                continue

            if mtype == "message":
                text = str(msg.get("text", ""))[:8000]
                if not text.strip():
                    continue
                payload = {
                    "type": "message",
                    "id": secrets.token_hex(4),
                    "nick": nick,
                    "text": text,
                    "enc": bool(msg.get("enc")),
                    "time": now(),
                }
                reply_to = str(msg.get("reply_to", ""))[:16]
                if reply_to:
                    payload["reply_to"] = reply_to
                room["history"].append(payload)
                append_history(room_name, payload)
                await broadcast(room_name, payload)
                stats["total_msgs"] += 1
                if DEV:
                    log.debug("üzenet: %s → #%s (%d karakter, e2ee=%s)",
                              nick, room_name, len(text), payload["enc"])

            elif mtype == "react":
                emoji = str(msg.get("emoji", ""))
                target = find_message(room, str(msg.get("id", "")))
                if emoji not in REACTIONS or not target or target.get("deleted"):
                    continue
                reacts = target.setdefault("reactions", {})
                users = reacts.setdefault(emoji, [])
                if nick in users:
                    users.remove(nick)
                    if not users:
                        del reacts[emoji]
                else:
                    users.append(nick)
                if not reacts:
                    target.pop("reactions", None)
                rewrite_history(room_name, room["history"])
                await broadcast(room_name, {
                    "type": "react", "id": target["id"], "reactions": reacts,
                })

            elif mtype == "edit":
                text = str(msg.get("text", ""))[:8000]
                target = find_message(room, str(msg.get("id", "")))
                if not text.strip() or not target or target.get("deleted") \
                        or target["nick"] != nick:
                    continue
                target["text"] = text
                target["enc"] = bool(msg.get("enc"))
                target["edited"] = True
                rewrite_history(room_name, room["history"])
                await broadcast(room_name, {
                    "type": "edit", "id": target["id"],
                    "text": text, "enc": target["enc"],
                })

            elif mtype == "delete":
                target = find_message(room, str(msg.get("id", "")))
                if not target or target.get("deleted") or target["nick"] != nick:
                    continue
                target["text"] = ""
                target["enc"] = False
                target["deleted"] = True
                target.pop("reactions", None)
                target.pop("edited", None)
                rewrite_history(room_name, room["history"])
                await broadcast(room_name, {"type": "delete", "id": target["id"]})

            elif mtype == "dm":
                text = str(msg.get("text", ""))[:8000]
                target_nick = str(msg.get("to", ""))
                if not text.strip():
                    continue
                payload = json.dumps({
                    "type": "dm",
                    "from": nick,
                    "to": target_nick,
                    "text": text,
                    "enc": bool(msg.get("enc")),
                    "time": now(),
                }, ensure_ascii=False)
                for ws, n in room["clients"].items():
                    if n == target_nick or ws is websocket:
                        await ws.send(payload)
                stats["total_msgs"] += 1

            elif mtype == "typing":
                await broadcast(room_name, {"type": "typing", "nick": nick},
                                exclude=websocket)

    except (websockets.ConnectionClosed, json.JSONDecodeError,
            asyncio.TimeoutError, UnicodeDecodeError):
        pass
    finally:
        conn_per_ip[ip] = conn_per_ip.get(ip, 1) - 1
        if conn_per_ip.get(ip, 0) <= 0:
            conn_per_ip.pop(ip, None)
        room = rooms.get(room_name)
        if room and websocket in room["clients"]:
            del room["clients"][websocket]
            if room["clients"]:
                await broadcast(room_name, {"type": "info", "text": f"{nick} kilépett", "time": now()})
                await send_userlist(room_name)
            else:
                del rooms[room_name]
            admin_log(f"Kilépés: {nick} (#{room_name})")
            push_admin_state()

def _fetch_vpn_status():
    """Kimenő IP ellenőrzése a Mullvad nyilvános API-jával (szinkron)."""
    req = urllib.request.Request(
        "https://am.i.mullvad.net/json",
        headers={"User-Agent": "privat-csevego/1.0"},
    )
    with urllib.request.urlopen(req, timeout=6) as resp:
        info = json.loads(resp.read().decode())
    org = (info.get("organization") or "")
    provider = None
    if info.get("mullvad_exit_ip"):
        provider = "Mullvad"
    elif "proton" in org.lower():
        provider = "Proton"
    elif any(k in org.lower() for k in ("vpn", "ivpn", "windscribe", "nordvpn", "surfshark")):
        provider = org
    return {
        "vpn": provider is not None,
        "provider": provider,
        "ip": info.get("ip"),
        "country": info.get("country"),
        "organization": org,
    }

async def vpn_status():
    if time.time() - _vpn_cache["time"] < 60 and _vpn_cache["data"]:
        return _vpn_cache["data"]
    try:
        data = await asyncio.to_thread(_fetch_vpn_status)
    except Exception as e:
        data = {"vpn": None, "error": str(e)}
    _vpn_cache["time"] = time.time()
    _vpn_cache["data"] = data
    return data

CSP = ("default-src 'self'; script-src 'self' 'unsafe-inline'; "
       "style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
       "connect-src 'self' ws: wss:; manifest-src 'self'; "
       "frame-ancestors 'none'; base-uri 'none'; form-action 'none'; "
       "object-src 'none'")

def _response(status, ctype, body, secure=False):
    headers = Headers({
        "Content-Type": ctype,
        "Content-Length": str(len(body)),
        "Cache-Control": "no-cache",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
        "Content-Security-Policy": CSP,
        "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
        "Cross-Origin-Opener-Policy": "same-origin",
    })
    if secure:
        headers["Strict-Transport-Security"] = "max-age=31536000"
    return Response(status, http.HTTPStatus(status).phrase, headers, body)

def _origin_ok(request):
    """Csak a saját oldalról jövő WebSocket-kapcsolat engedett (CSWSH ellen)."""
    origin = request.headers.get("Origin")
    if not origin:
        return True
    host = request.headers.get("Host", "")
    return origin.split("://", 1)[-1] == host

async def serve_static(connection, request):
    if request.headers.get("Upgrade", "").lower() == "websocket":
        if not _origin_ok(request):
            return _response(403, "text/plain", "Tiltott eredet".encode())
        return None

    path = request.path.split("?")[0]

    if path == "/api/vpn":
        body = json.dumps(await vpn_status(), ensure_ascii=False).encode()
        return _response(200, "application/json; charset=utf-8", body)

    if path == "/api/state":
        query = request.path.partition("?")[2]
        params = dict(p.split("=", 1) for p in query.split("&") if "=" in p)
        if not token_ok(params.get("token")):
            return _response(403, "text/plain", "Hibás token".encode())
        body = json.dumps(admin_state(), ensure_ascii=False, indent=2).encode()
        return _response(200, "application/json; charset=utf-8", body)

    if path in STATIC_FILES:
        fname, ctype = STATIC_FILES[path]
        fpath = BASE_DIR / fname
        if fpath.exists():
            return _response(200, ctype, fpath.read_bytes())

    return _response(404, "text/plain", "Nincs ilyen oldal".encode())

def make_ssl_context():
    cert = BASE_DIR / "cert.pem"
    key = BASE_DIR / "key.pem"
    if cert.exists() and key.exists():
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert, key)
        return ctx
    return None

async def uptime_ticker():
    """Másodpercenkénti állapotfrissítés az admin felületnek (ha van admin)."""
    while True:
        await asyncio.sleep(3)
        push_admin_state()

async def main():
    ctx = make_ssl_context()
    scheme = "https" if ctx else "http"
    async with websockets.serve(handler, "0.0.0.0", PORT,
                                process_request=serve_static, ssl=ctx,
                                max_size=MAX_WS_FRAME, max_queue=32):
        print(f"Privát Csevegő fut:  {scheme}://localhost:{PORT}")
        print(f"Admin felület:       {scheme}://localhost:{PORT}/admin")
        print(f"Admin token:         {ADMIN_TOKEN}")
        print("                     (a .admin_token fájlban is megtalálod — ne oszd meg!)")
        if DEV:
            print("DEV MÓD: részletes naplózás + /api/state végpont aktív.")
        if ctx:
            print("HTTPS/WSS mód: a végpontok közötti titkosítás a helyi hálózaton is működik.")
        else:
            print("Tipp: futtasd a make_cert.sh szkriptet, hogy HTTPS-sel menjen"
                  " (E2EE a helyi hálózaton is).")
        print("Leállítás: Ctrl+C")
        asyncio.create_task(uptime_ticker())
        await asyncio.Future()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Privát Csevegő szerver")
    parser.add_argument("--dev", action="store_true",
                        help="fejlesztői mód: részletes naplózás, debug API")
    args = parser.parse_args()
    DEV = args.dev
    logging.basicConfig(
        level=logging.DEBUG if DEV else logging.WARNING,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )
    if DEV:
        logging.getLogger("websockets").setLevel(logging.INFO)
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nSzerver leállítva.")
