__lazy_modules__ = [
    "asyncio",
    "os",
    "sys",
    "kasa",
]

import asyncio
import os
import sys

from kasa import Credentials, Device, DeviceConfig, DeviceConnectionParameters


def beallitas():
    return DeviceConfig(
        host=os.environ["TAPO_HOST"],
        credentials=Credentials(os.environ["KASA_USERNAME"], os.environ["KASA_PASSWORD"]),
        connection_type=DeviceConnectionParameters.from_dict(
            {
                "device_family": "SMART.TAPOPLUG",
                "encryption_type": "TPAP",
                "login_version": 2,
                "https": False,
                "http_port": 80,
            }
        ),
        timeout=int(os.environ.get("TAPO_TIMEOUT", "8")),
    )


async def futtat(muvelet, mp):
    eszkoz = await Device.connect(config=beallitas())
    try:
        valasz = await eszkoz._query_helper("get_countdown_rules")
        szabalyok = valasz.get("get_countdown_rules", valasz).get("rule_list", [])
        if muvelet == "allapot":
            print(szabalyok or "nincs időzítő")
        elif muvelet == "torol":
            await eszkoz._query_helper("remove_countdown_rules", {"remove_all": True})
            print("időzítő törölve")
        else:
            adat = {"delay": mp, "desired_states": {"on": False}, "enable": True, "remain": mp}
            if szabalyok:
                await eszkoz._query_helper("remove_countdown_rules", {"remove_all": True})
            await eszkoz._query_helper("add_countdown_rule", adat)
            print(f"a dugalj {mp} mp múlva kikapcsol")
    finally:
        await eszkoz.disconnect()


async def probalkozik(muvelet, mp, kiserlet):
    for i in range(kiserlet):
        try:
            await futtat(muvelet, mp)
            return 0
        except Exception as e:
            print(f"hiba ({i + 1}/{kiserlet}): {e}", file=sys.stderr)
            await asyncio.sleep(2)
    return 1


if __name__ == "__main__":
    muvelet = sys.argv[1] if len(sys.argv) > 1 else "allapot"
    mp = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    sys.exit(asyncio.run(probalkozik(muvelet, mp, int(os.environ.get("TAPO_KISERLET", "3")))))
