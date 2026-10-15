#!/bin/bash
# A Privát Csevegő megosztása az interneten — Cloudflare Tunnel segítségével.
#
# Miért ez a legjobb megoldás?
#   - NEM kell port forwarding, a router beállításához sem kell nyúlni
#   - az otthoni IP-címed REJTVE marad (a látogatók a Cloudflare-t látják)
#   - automatikus HTTPS → a végpontok közötti titkosítás (E2EE) is működik
#   - ingyenes, fiók sem kell a gyors ("quick") tunnelhez
#
# Használat:
#   1. terminál:  python3 server.py
#   2. terminál:  ./start_tunnel.sh
#   → kapsz egy https://valami.trycloudflare.com címet, ezt küldd el bárkinek.

PORT=8765

if command -v cloudflared >/dev/null; then
    echo "Tunnel indítása… A kapott https://… címet oszd meg a többiekkel."
    exec cloudflared tunnel --url "http://localhost:$PORT"
fi

echo "A cloudflared nincs telepítve. Telepítés (Arch/CachyOS):"
echo
echo "    sudo pacman -S cloudflared"
echo
echo "Alternatívák:"
echo "  - Tailscale (privát hálózat barátoknak, fiók kell):"
echo "        sudo pacman -S tailscale && sudo systemctl enable --now tailscaled"
echo "        sudo tailscale up   →  a gépeid privát VPN-ben látják egymást"
echo "  - ngrok:  https://ngrok.com  (fiók kell)"
exit 1
