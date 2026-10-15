import asyncio
import json
import time

import machine
import network
import os
import rp2
from machine import I2C, PWM, SPI, Pin, SoftI2C

import titkok

OLED_CLK, OLED_DATA, OLED_DC, OLED_CS, OLED_RST = 10, 11, 8, 9, 12
OLED_CIM = 0x3D
I2C_SDA = 4
I2C_SCL = 5
BUZZER_LAB = 20
LED_LAB = 21
SD_SCK, SD_MOSI, SD_MISO, SD_CS = 18, 19, 16, 17
RTC_CIM = 0x68
SD_NAPLO = "/sd/or_naplo.csv"
ELETJEL_HATAR_MP = 180
ISMETLES_MP = 30
ISMETLES_MAX = 5
NAPLO_MERET = 20
WEB_FAJL = "web.html"
KI_FAJL = "kikapcsolva"
HOSSZU_NYOMAS_MS = 3000
KIJELZO = getattr(titkok, "KIJELZO", True)

EKEZET = {"á": "a", "é": "e", "í": "i", "ó": "o", "ö": "o", "ő": "o", "ú": "u", "ü": "u", "ű": "u",
          "Á": "A", "É": "E", "Í": "I", "Ó": "O", "Ö": "O", "Ő": "O", "Ú": "U", "Ü": "U", "Ű": "U"}

CIMKE = {"belepes": "BELEPES", "sudo": "SUDO", "sudo_hiba": "SUDO HIBA", "tiltas": "TILTAS",
         "sikertelen": "SIKERTELEN", "teszt": "TESZT"}


def ascii(s, hossz=21):
    return "".join(EKEZET.get(c, c) if ord(c) < 128 or c in EKEZET else "?" for c in str(s))[:hossz]


def bcd(b):
    return (b >> 4) * 10 + (b & 0x0F)


def bcdbe(n):
    return ((n // 10) << 4) | (n % 10)


def utolso_vasarnap(ev, honap):
    for nap in range(31, 24, -1):
        if time.gmtime(time.mktime((ev, honap, nap, 0, 0, 0, 0, 0, 0)))[6] == 6:
            return nap


class Ora:
    def __init__(self, i2c):
        self.i2c = i2c
        self.rtc_van = False
        self.pontos = False
        if i2c is None:
            return
        try:
            if RTC_CIM in i2c.scan():
                self.i2c.writeto_mem(RTC_CIM, 0x02, b"\x00")
                self.rtc_van = True
                self.rtcbol()
        except Exception as hiba:
            print("RTC hiba:", hiba)

    def rtcbol(self):
        r = self.i2c.readfrom_mem(RTC_CIM, 0x03, 7)
        if r[0] & 0x80:
            print("RTC: az ora allt (elem?), NTP-re var")
            return
        ev = 2000 + bcd(r[6])
        if ev < 2025:
            return
        machine.RTC().datetime((ev, bcd(r[5] & 0x1F), bcd(r[3] & 0x3F), 0,
                                bcd(r[2] & 0x3F), bcd(r[1] & 0x7F), bcd(r[0] & 0x7F), 0))
        self.pontos = True

    def rtcbe(self):
        t = time.gmtime()
        self.i2c.writeto_mem(RTC_CIM, 0x03, bytes([bcdbe(t[5]), bcdbe(t[4]), bcdbe(t[3]), bcdbe(t[2]),
                                                    t[6], bcdbe(t[1]), bcdbe(t[0] - 2000)]))

    def ntp(self):
        try:
            import ntptime
            ntptime.host = getattr(titkok, "NTP", "pool.ntp.org")
            ntptime.settime()
            self.pontos = True
            if self.rtc_van:
                self.rtcbe()
            return True
        except Exception as hiba:
            print("NTP hiba:", hiba)
            return False

    def helyi(self):
        most = time.time()
        ev = time.gmtime(most)[0]
        nyar_eleje = time.mktime((ev, 3, utolso_vasarnap(ev, 3), 1, 0, 0, 0, 0, 0))
        nyar_vege = time.mktime((ev, 10, utolso_vasarnap(ev, 10), 1, 0, 0, 0, 0, 0))
        return time.gmtime(most + (7200 if nyar_eleje <= most < nyar_vege else 3600))

    def szoveg(self, csak_ido=False):
        if not self.pontos:
            return "--:--" if csak_ido else "ismeretlen"
        t = self.helyi()
        if csak_ido:
            return "{:02d}:{:02d}".format(t[3], t[4])
        return "{:04d}-{:02d}-{:02d} {:02d}:{:02d}:{:02d}".format(*t[:6])


class Kartya:
    def __init__(self):
        self.van = False
        try:
            import sdcard
            spi = SPI(0, baudrate=1000000, sck=Pin(SD_SCK), mosi=Pin(SD_MOSI), miso=Pin(SD_MISO))
            os.mount(os.VfsFat(sdcard.SDCard(spi, Pin(SD_CS, Pin.OUT))), "/sd")
            self.van = True
            try:
                os.stat(SD_NAPLO)
            except OSError:
                self.ir_sor("ido;tipus;szint;ki;honnan;reszlet")
        except Exception as hiba:
            print("SD nem elerheto:", hiba)

    def ir_sor(self, sor):
        with open(SD_NAPLO, "a") as f:
            f.write(sor + "\n")

    def ir(self, ido, e):
        if not self.van:
            return
        try:
            self.ir_sor(";".join([ido] + [str(e.get(k, "")).replace(";", ",") for k in
                                          ("tipus", "szint", "ki", "honnan", "reszlet")]))
        except Exception as hiba:
            print("SD irasi hiba:", hiba)
            self.van = False

    def utolso(self, n):
        if not self.van:
            return []
        sorok = []
        with open(SD_NAPLO) as f:
            for sor in f:
                sorok.append(sor.rstrip("\n"))
                if len(sorok) > n:
                    sorok.pop(0)
        return sorok


class Allapot:
    def __init__(self):
        self.naplo = []
        self.szamlalo = {"belepes": 0, "sudo": 0, "tiltas": 0, "sikertelen": 0}
        self.riasztas = None
        self.riasztas_ota = 0
        self.ismetlesek = 0
        self.utolso_eletjel = None
        self.oldal = 0
        self.ip = "-"
        try:
            os.stat(KI_FAJL)
            self.ki = True
        except OSError:
            self.ki = False

    def kapcsol(self, ki):
        if ki == self.ki:
            return
        self.ki = ki
        self.riasztas = None
        self.utolso_eletjel = None
        try:
            if ki:
                with open(KI_FAJL, "w") as f:
                    f.write("1")
            else:
                os.remove(KI_FAJL)
        except OSError as hiba:
            print("kapcsolo fajl hiba:", hiba)
        sajat("kikapcsolva" if ki else "bekapcsolva", "")
        hangot("ki" if ki else "be")

    def esemeny(self, e):
        tipus = e.get("tipus", "?")
        if tipus == "sudo_hiba":
            self.szamlalo["sudo"] += 1
        elif tipus in self.szamlalo:
            self.szamlalo[tipus] += 1
        if ora.pontos:
            e["ido"] = ora.szoveg(True)
        kartya.ir(ora.szoveg(), e)
        self.naplo.insert(0, e)
        del self.naplo[NAPLO_MERET:]
        if e.get("szint") == "hangos" and not self.ki:
            self.riasztas = e
            self.riasztas_ota = time.ticks_ms()
            self.ismetlesek = 0

    def nyugtaz(self):
        if self.riasztas:
            sajat("nyugta", self.riasztas.get("tipus", ""))
            self.riasztas = None
            return True
        return False

    def pi_eletben(self):
        if self.utolso_eletjel is None:
            return None
        return time.ticks_diff(time.ticks_ms(), self.utolso_eletjel) < ELETJEL_HATAR_MP * 1000

    def json(self):
        return {"ip": self.ip, "ido": ora.szoveg(), "rtc": ora.rtc_van, "sd": kartya.van, "oled_hibak": hw.oled_hibak,
                "kikapcsolva": self.ki,
                "szamlalo": self.szamlalo, "riasztas": self.riasztas,
                "pi_eletben": self.pi_eletben(), "naplo": self.naplo[:10]}


class Hardver:
    def __init__(self):
        self.led = Pin(LED_LAB, Pin.OUT)
        self.belso_led = Pin("LED", Pin.OUT)
        self.buzzer = PWM(Pin(BUZZER_LAB))
        self.buzzer.duty_u16(0)
        self.oled = None
        self.i2c = None
        try:
            self.i2c = I2C(0, sda=Pin(I2C_SDA), scl=Pin(I2C_SCL), freq=400000)
        except Exception as hiba:
            print("I2C hiba:", hiba)
        self.oled_hibak = 0
        self.oled_labak = (Pin(OLED_DC, Pin.OUT, value=OLED_CIM & 1), Pin(OLED_CS, Pin.OUT, value=0))
        self.oled_rst = Pin(OLED_RST, Pin.OUT, value=1)
        if KIJELZO:
            self.oled_indit()

    def oled_indit(self):
        self.oled = None
        try:
            import ssd1306
            self.oled_rst.value(0)
            time.sleep_ms(20)
            self.oled_rst.value(1)
            time.sleep_ms(20)
            busz = SoftI2C(scl=Pin(OLED_CLK), sda=Pin(OLED_DATA), freq=400000)
            Pin(OLED_CLK, Pin.OPEN_DRAIN, pull=Pin.PULL_UP, value=1)
            Pin(OLED_DATA, Pin.OPEN_DRAIN, pull=Pin.PULL_UP, value=1)
            self.oled = ssd1306.SSD1306_I2C(128, 64, busz, addr=OLED_CIM)
        except Exception as hiba:
            print("OLED nem elerheto:", hiba)

    async def hang(self, minta):
        for frekvencia, hossz, szunet in minta:
            if frekvencia:
                self.buzzer.freq(frekvencia)
                self.buzzer.duty_u16(32768)
            await asyncio.sleep_ms(hossz)
            self.buzzer.duty_u16(0)
            await asyncio.sleep_ms(szunet)

    def kiir(self, sorok, forditott_fejlec=False):
        if not KIJELZO:
            return
        for _ in range(2):
            if not self.oled:
                self.oled_indit()
            if not self.oled:
                return
            try:
                self.rajzol(sorok, forditott_fejlec)
                return
            except OSError as hiba:
                self.oled_hibak += 1
                print("OLED irasi hiba:", hiba)
                self.oled = None

    def rajzol(self, sorok, forditott_fejlec):
        o = self.oled
        o.fill(0)
        for i, sor in enumerate(sorok[:6]):
            y = 0 if i == 0 else 4 + i * 10
            if i == 0 and forditott_fejlec:
                o.fill_rect(0, 0, 128, 10, 1)
                o.text(ascii(sor, 16), 0, 1, 0)
            else:
                o.text(ascii(sor, 16), 0, y if i else 1, 1)
        if not forditott_fejlec:
            o.hline(0, 11, 128, 1)
        o.show()


HANG = {
    "hangos": [(2800, 120, 60), (2800, 120, 60), (3400, 250, 0)],
    "halk": [(2200, 40, 0)],
    "pi": [(900, 300, 100), (700, 400, 0)],
    "nyugta": [(1800, 30, 0)],
    "ki": [(1600, 120, 40), (1000, 200, 0)],
    "be": [(1000, 120, 40), (1600, 200, 0)],
}

allapot = Allapot()
hw = Hardver()
ora = Ora(hw.i2c)
kartya = Kartya()
hang_sor = []


def sajat(tipus, reszlet):
    kartya.ir(ora.szoveg(), {"tipus": tipus, "szint": "pico", "ki": "pico", "honnan": "", "reszlet": reszlet})


def hangot(nev):
    hang_sor.append(nev)


def kepernyo():
    if allapot.ki:
        hw.kiir([
            "KIKAPCSOLVA",
            "nem riaszt,",
            "csak naplot ir",
            "",
            allapot.ip,
            "BOOTSEL 3mp: be",
        ], forditott_fejlec=True)
        return
    if allapot.riasztas:
        e = allapot.riasztas
        hw.kiir([
            "!! " + CIMKE.get(e.get("tipus"), "ESEMENY") + " !!",
            e.get("ido", "") + " " + e.get("ki", ""),
            e.get("honnan", ""),
            e.get("reszlet", ""),
            "",
            "BOOTSEL: nyugta",
        ], forditott_fejlec=True)
        return
    pi = allapot.pi_eletben()
    pi_jel = "?" if pi is None else ("ok" if pi else "NINCS")
    if allapot.oldal == 0:
        s = allapot.szamlalo
        utolso = allapot.naplo[0] if allapot.naplo else None
        hw.kiir([
            ora.szoveg(True) + " Pi:" + pi_jel + (" SD" if kartya.van else " -"),
            "belep {:<3} sudo {}".format(s["belepes"], s["sudo"]),
            "tilt  {:<3} hiba {}".format(s["tiltas"], s["sikertelen"]),
            ("utolso " + utolso.get("ido", "")) if utolso else "nincs esemeny",
            (utolso.get("ki", "") + " " + utolso.get("honnan", "")) if utolso else "",
            allapot.ip,
        ])
    else:
        sorok = ["NAPLO"]
        for e in allapot.naplo[:5]:
            sorok.append(e.get("ido", "")[:5] + " " + CIMKE.get(e.get("tipus"), "?")[:4] + " " + e.get("ki", ""))
        if len(sorok) == 1:
            sorok.append("ures")
        hw.kiir(sorok)


async def valasz(writer, kod, adat):
    torzs = json.dumps(adat)
    szoveg = {200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found"}.get(kod, "OK")
    writer.write("HTTP/1.1 {} {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}".format(
        kod, szoveg, len(torzs), torzs).encode())
    await writer.drain()


async def weboldal(writer):
    try:
        meret = os.stat(WEB_FAJL)[6]
    except OSError:
        await valasz(writer, 404, {"hiba": "nincs web.html"})
        return
    writer.write("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\n"
                 "Cache-Control: no-cache\r\nConnection: close\r\n\r\n".format(meret).encode())
    await writer.drain()
    with open(WEB_FAJL, "rb") as f:
        while True:
            darab = f.read(1024)
            if not darab:
                break
            writer.write(darab)
            await writer.drain()


async def kapcsolat(reader, writer):
    try:
        elso = (await asyncio.wait_for(reader.readline(), 5)).decode().split()
        fejlec = {}
        while True:
            sor = (await asyncio.wait_for(reader.readline(), 5)).decode().strip()
            if not sor:
                break
            if ":" in sor:
                k, v = sor.split(":", 1)
                fejlec[k.strip().lower()] = v.strip()
        hossz = min(int(fejlec.get("content-length", "0")), 2048)
        torzs = b""
        while len(torzs) < hossz:
            darab = await asyncio.wait_for(reader.read(hossz - len(torzs)), 5)
            if not darab:
                break
            torzs += darab
        if len(elso) < 2:
            await valasz(writer, 400, {"hiba": "rossz keres"})
            return
        modszer, ut = elso[0], elso[1]
        if modszer == "GET" and ut in ("/", "/index.html"):
            await weboldal(writer)
            return
        if fejlec.get("x-kulcs") != titkok.KULCS:
            await valasz(writer, 401, {"hiba": "rossz kulcs"})
            return
        if modszer == "GET" and ut == "/allapot":
            await valasz(writer, 200, allapot.json())
        elif modszer == "POST" and ut == "/esemeny":
            e = json.loads(torzs)
            e = {k: ascii(e.get(k, ""), 40) for k in ("tipus", "szint", "ki", "honnan", "reszlet", "ido")}
            allapot.esemeny(e)
            allapot.utolso_eletjel = time.ticks_ms()
            if e["szint"] in ("hangos", "halk") and not allapot.ki:
                hangot(e["szint"])
            kepernyo()
            await valasz(writer, 200, {"ok": True})
        elif modszer == "GET" and ut.startswith("/naplo"):
            n = 50
            if "n=" in ut:
                n = max(1, min(500, int(ut.split("n=", 1)[1].split("&")[0])))
            await valasz(writer, 200, {"sd": kartya.van, "sorok": kartya.utolso(n)})
        elif modszer == "POST" and ut == "/eletjel":
            allapot.utolso_eletjel = time.ticks_ms()
            await valasz(writer, 200, {"ok": True})
        elif modszer == "POST" and ut in ("/kikapcs", "/bekapcs"):
            allapot.kapcsol(ut == "/kikapcs")
            kepernyo()
            await valasz(writer, 200, {"ok": True, "kikapcsolva": allapot.ki})
        elif modszer == "POST" and ut == "/nyugta":
            allapot.nyugtaz()
            kepernyo()
            await valasz(writer, 200, {"ok": True})
        else:
            await valasz(writer, 404, {"hiba": "nincs ilyen"})
    except Exception as hiba:
        print("keres hiba:", hiba)
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def wifi(wlan):
    utolso_ntp = None
    ntp_ok = False
    while True:
        if not wlan.isconnected():
            allapot.ip = "WiFi..."
            kepernyo()
            wlan.connect(titkok.WIFI_SSID, titkok.WIFI_JELSZO)
            for _ in range(40):
                if wlan.isconnected():
                    break
                hw.belso_led.toggle()
                await asyncio.sleep_ms(250)
        if wlan.isconnected():
            ip = wlan.ifconfig()[0] + ":" + str(titkok.PORT)
            if ip != allapot.ip:
                allapot.ip = ip
                print("IP:", ip)
                kepernyo()
            varas = 6 * 3600 * 1000 if ntp_ok else 300 * 1000
            if utolso_ntp is None or time.ticks_diff(time.ticks_ms(), utolso_ntp) > varas:
                ntp_ok = ora.ntp()
                utolso_ntp = time.ticks_ms()
                kepernyo()
        hw.belso_led.value(1 if wlan.isconnected() else 0)
        await asyncio.sleep(5)


async def gomb():
    lenyomva_ota = None
    hosszu = False
    while True:
        most = rp2.bootsel_button() == 1
        if most and lenyomva_ota is None:
            lenyomva_ota = time.ticks_ms()
            hosszu = False
        elif most and not hosszu and time.ticks_diff(time.ticks_ms(), lenyomva_ota) >= HOSSZU_NYOMAS_MS:
            hosszu = True
            allapot.kapcsol(not allapot.ki)
            kepernyo()
        elif not most and lenyomva_ota is not None:
            if not hosszu and not allapot.ki:
                if not allapot.nyugtaz():
                    allapot.oldal = 1 - allapot.oldal
                hangot("nyugta")
                kepernyo()
            lenyomva_ota = None
        await asyncio.sleep_ms(60)


async def jelzo():
    pi_volt = True
    utolso_kep = time.ticks_ms()
    while True:
        while hang_sor:
            await hw.hang(HANG[hang_sor.pop(0)])
        if allapot.ki:
            pi_volt = True
            hw.led.value(0)
            await asyncio.sleep_ms(200)
            continue
        if allapot.riasztas:
            hw.led.toggle()
            if time.ticks_diff(time.ticks_ms(), allapot.riasztas_ota) > ISMETLES_MP * 1000 and allapot.ismetlesek < ISMETLES_MAX:
                allapot.ismetlesek += 1
                allapot.riasztas_ota = time.ticks_ms()
                hangot("hangos")
            await asyncio.sleep_ms(200)
            continue
        pi = allapot.pi_eletben()
        if pi is False:
            if pi_volt:
                hangot("pi")
                sajat("pi_eltunt", "nincs eletjel")
                kepernyo()
            pi_volt = False
            hw.led.value((time.ticks_ms() // 1000) % 2)
        else:
            if not pi_volt:
                sajat("pi_vissza", "")
                kepernyo()
            pi_volt = True
            hw.led.value(0)
        if time.ticks_diff(time.ticks_ms(), utolso_kep) > 10000:
            utolso_kep = time.ticks_ms()
            kepernyo()
        await asyncio.sleep_ms(200)


async def orzott(nev, fn):
    while True:
        try:
            await fn()
        except Exception as hiba:
            print("feladat hiba:", nev, hiba)
            await asyncio.sleep(1)


async def orkutya(wdt):
    while True:
        wdt.feed()
        await asyncio.sleep(1)


async def fo():
    network.hostname(getattr(titkok, "NEV", "or"))
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    wlan.config(pm=0xa11140)
    ok = {getattr(machine, n, -1): n for n in ("PWRON_RESET", "WDT_RESET", "HARD_RESET", "SOFT_RESET")}
    sajat("indulas", ok.get(machine.reset_cause(), str(machine.reset_cause())))
    kepernyo()
    asyncio.create_task(orzott("wifi", lambda: wifi(wlan)))
    asyncio.create_task(orzott("gomb", gomb))
    asyncio.create_task(orzott("jelzo", jelzo))
    asyncio.create_task(orkutya(machine.WDT(timeout=8000)))
    await asyncio.start_server(kapcsolat, "0.0.0.0", titkok.PORT)
    while True:
        await asyncio.sleep(3600)


if __name__ == "__main__":
    try:
        asyncio.run(fo())
    except Exception as hiba:
        print("vegzetes hiba:", hiba)
        time.sleep(5)
        machine.reset()
