#!/bin/bash
# Önaláírt HTTPS-tanúsítvány készítése a Privát Csevegőhöz.
# Ezzel a helyi hálózaton is működik a végpontok közötti titkosítás (E2EE),
# mert a böngészők csak biztonságos kapcsolaton engedik a WebCrypto API-t.
#
# Használat:  ./make_cert.sh
# Utána indítsd újra a szervert — automatikusan HTTPS-re vált.
# A böngésző először figyelmeztetni fog (önaláírt tanúsítvány) — ez normális,
# kattints a "Speciális" → "Tovább" lehetőségre.

set -e
cd "$(dirname "$0")"

# A géped helyi IP-címei bekerülnek a tanúsítványba
IPS=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
SAN="DNS:localhost,IP:127.0.0.1"
for ip in $IPS; do SAN="$SAN,IP:$ip"; done

openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes \
  -keyout key.pem -out cert.pem \
  -subj "/CN=privat-csevego" \
  -addext "subjectAltName=$SAN"

chmod 600 key.pem
echo
echo "Kész: cert.pem + key.pem"
echo "Tartalmazott címek: $SAN"
echo "Indítsd újra a szervert: python3 server.py  →  https://localhost:8765"
