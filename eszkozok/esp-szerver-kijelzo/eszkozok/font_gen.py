#!/usr/bin/env python3
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

INTER = "/usr/share/fonts/inter/Inter.ttc"
MAGYAR = "áÁéÉíÍóÓöÖőŐúÚüÜűŰ°•–"
ASCII = "".join(chr(c) for c in range(0x20, 0x7F))

FONTOK = [
    ("font_kicsi", 10, 13, ASCII + MAGYAR),
    ("font_kozep", 12, 18, ASCII + MAGYAR),
    ("font_nagy", 32, 40, "0123456789%.,:-–°C /?"),
]


def vlw(ttf_index, meret, karakterek):
    font = ImageFont.truetype(INTER, meret, index=ttf_index)
    karakterek = sorted(set(karakterek), key=ord)
    fej, bitkepek = [], []
    for ch in karakterek:
        elore = round(font.getlength(ch))
        x0, y0, x1, y1 = font.getbbox(ch, anchor="ls")
        w, h = x1 - x0, y1 - y0
        if ch == " " or w <= 0 or h <= 0:
            fej.append((ord(ch), 0, 0, elore, 0, 0))
            continue
        kep = Image.new("L", (w, h), 0)
        ImageDraw.Draw(kep).text((-x0, -y0), ch, font=font, fill=255, anchor="ls")
        fej.append((ord(ch), h, w, elore, -y0, x0))
        bitkepek.append(kep.tobytes())
    ascent = -font.getbbox("d", anchor="ls")[1]
    descent = font.getbbox("p", anchor="ls")[3]
    ki = struct.pack(">6i", len(fej), 11, meret, 0, ascent, descent)
    for u, h, w, adv, dy, dx in fej:
        ki += struct.pack(">7i", u, h, w, adv, dy, dx, 0)
    return ki + b"".join(bitkepek)


def main():
    cel = Path(sys.argv[1] if len(sys.argv) > 1 else "fontok.h")
    sorok = ["#pragma once", "#include <pgmspace.h>", ""]
    for nev, idx, meret, kar in FONTOK:
        adat = vlw(idx, meret, kar)
        sorok.append(f"const uint8_t {nev}[] PROGMEM = {{")
        for i in range(0, len(adat), 20):
            sorok.append("  " + ",".join(f"0x{b:02X}" for b in adat[i:i + 20]) + ",")
        sorok.append("};")
        sorok.append("")
        print(f"{nev}: {len(adat)} bájt", file=sys.stderr)
    cel.write_text("\n".join(sorok))


if __name__ == "__main__":
    main()
