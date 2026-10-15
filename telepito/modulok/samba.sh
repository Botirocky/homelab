#!/usr/bin/env bash
# Modul: Samba – helyi hálózati fájlmegosztás
# Ettől látszik a szerver a Windows Hálózatok alatt, a telefon fájlkezelőjében
# és a Linux fájlkezelőkben is (smb://szerver/megosztas).

cim "Helyi fájlmegosztás (Samba)"

if ! csomag_van samba; then
    info "Samba telepítése…"
    case "$OS_CSALAD" in
        debian) csomag_telepit samba samba-common-bin ;;
        fedora|suse) csomag_telepit samba samba-client ;;
        arch) csomag_telepit samba ;;
    esac
fi

# --- a megosztáshoz kell egy rendszer-felhasználó ----------------------------
if ! id "$SMB_FELHASZNALO" >/dev/null 2>&1; then
    info "felhasználó létrehozása: $SMB_FELHASZNALO"
    fut useradd -M -s /usr/sbin/nologin "$SMB_FELHASZNALO"
fi

SMB_JELSZO="$(titok SMB_JELSZO 16)"
if [[ "$PROBA" != "1" ]]; then
    if ! pdbedit -L 2>/dev/null | grep -q "^${SMB_FELHASZNALO}:"; then
        printf '%s\n%s\n' "$SMB_JELSZO" "$SMB_JELSZO" | smbpasswd -s -a "$SMB_FELHASZNALO" >/dev/null
        ok "Samba-felhasználó létrehozva: $SMB_FELHASZNALO (jelszó a .env-ben)"
    else
        kihagy "Samba-felhasználó: $SMB_FELHASZNALO"
        # A meglévő felhasználó jelszavához nem nyúlunk (lehet, hogy kézzel
        # állították be), de megnézzük, hogy a .env-ben lévő még érvényes-e.
        # A pdbedit a jelszó NT-hash-ét adja; ugyanezt számoljuk az SMB_JELSZO-ból.
        # 0 = egyezik, 1 = eltér, 2 = nem sikerült ellenőrizni
        smb_eredmeny=0
        SMB_NTHASH="$(pdbedit -L -w -u "$SMB_FELHASZNALO" 2>/dev/null | cut -d: -f4 || true)"
        SMB_JELSZO="$SMB_JELSZO" SMB_NTHASH="$SMB_NTHASH" python3 - <<'NTHASH' || smb_eredmeny=$?
import os, struct, sys
jelszo = os.environ["SMB_JELSZO"].encode("utf-16-le")
tarolt = os.environ.get("SMB_NTHASH", "").strip().upper()
if len(tarolt) != 32 or not all(c in "0123456789ABCDEF" for c in tarolt):
    sys.exit(2)

def md4(adat):
    # Az OpenSSL 3 alapból nem ad MD4-et, ezért saját, rövid megvalósítás.
    m = 0xFFFFFFFF
    rol = lambda x, n: ((x << n) | (x >> (32 - n))) & m
    adat += b"\x80" + b"\x00" * ((55 - len(adat)) % 64) + struct.pack("<Q", len(adat) * 8)
    h = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476]
    for i in range(0, len(adat), 64):
        x = struct.unpack("<16I", adat[i:i + 64])
        a, b, c, d = h
        for k in range(16):
            s = (3, 7, 11, 19)[k % 4]
            a, b, c, d = d, rol((a + ((b & c) | (~b & d)) + x[k]) & m, s), b, c
        for k in range(16):
            s = (3, 5, 9, 13)[k % 4]
            j = (k % 4) * 4 + k // 4
            a, b, c, d = d, rol((a + ((b & c) | (b & d) | (c & d)) + x[j] + 0x5A827999) & m, s), b, c
        for k, j in enumerate((0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15)):
            s = (3, 9, 11, 15)[k % 4]
            a, b, c, d = d, rol((a + (b ^ c ^ d) + x[j] + 0x6ED9EBA1) & m, s), b, c
        h = [(v + w) & m for v, w in zip(h, (a, b, c, d))]
    return struct.pack("<4I", *h).hex().upper()

sys.exit(0 if md4(jelszo) == tarolt else 1)
NTHASH
        unset SMB_NTHASH
        case "$smb_eredmeny" in
            0) ok "a .env-ben lévő Samba-jelszó érvényes" ;;
            1) figy "A Samba-jelszó NEM az, ami a .env-ben van (SMB_JELSZO) – a 'park jelszavak' rosszat mutat."
               figy "Új jelszó:  sudo smbpasswd ${SMB_FELHASZNALO}   – utána írd át a .env-ben is: ${PARK_DIR}/.env" ;;
            *) figy "a Samba-jelszót nem sikerült összevetni a .env-nel – ha nem enged be: sudo smbpasswd ${SMB_FELHASZNALO}" ;;
        esac
    fi
fi

# --- megosztott mappák -------------------------------------------------------
MEGOSZTAS_DIR="${MEGOSZTAS_DIR:-${ADAT_DIR}/megosztas}"
konyvtar "${MEGOSZTAS_DIR}" 2775
konyvtar "${MEGOSZTAS_DIR}/kozos" 2775
konyvtar "${MEGOSZTAS_DIR}/${SMB_FELHASZNALO}" 2750
fut chown -R "${SMB_FELHASZNALO}:${SMB_FELHASZNALO}" "${MEGOSZTAS_DIR}"

# --- konfiguráció ------------------------------------------------------------
cat <<SMBCONF | fajlt_ir /etc/samba/szerverpark.conf
# A szerverpark telepítő írta. Az smb.conf ezt beolvassa.

[megosztas]
   comment = Szerverpark – közös megosztás
   path = ${MEGOSZTAS_DIR}/kozos
   browseable = yes
   read only = no
   create mask = 0664
   directory mask = 2775
   valid users = ${SMB_FELHASZNALO}
   force group = ${SMB_FELHASZNALO}

[${SMB_FELHASZNALO}]
   comment = ${SMB_FELHASZNALO} saját mappája
   path = ${MEGOSZTAS_DIR}/${SMB_FELHASZNALO}
   browseable = yes
   read only = no
   create mask = 0644
   directory mask = 0755
   valid users = ${SMB_FELHASZNALO}
SMBCONF

# A Paperless "consume" mappája: ide dobod a beolvasott lapokat, és pár perc
# múlva OCR-ezve, kereshetően megjelennek az iratok között. A Nextcloud adatait
# SZÁNDÉKOSAN nem osztjuk meg így: ott a fájlokat az alkalmazás tartja nyilván,
# a háta mögé írt fájlokról nem tudna.
IRATOK_DIR="${IRATOK_DIR:-}"
if [[ "$PROBA" != "1" && -n "$IRATOK_DIR" && -d "${IRATOK_DIR}/consume" ]]; then
    cat <<SMBIRAT >>/etc/samba/szerverpark.conf

[beolvasas]
   comment = Ide dobd a beolvasott iratokat (Paperless felszedi)
   path = ${IRATOK_DIR}/consume
   browseable = yes
   read only = no
   create mask = 0664
   directory mask = 2775
   valid users = ${SMB_FELHASZNALO}
SMBIRAT
    ok "Samba-megosztás a beolvasott iratoknak: \\\\<gép>\\beolvasas"
fi

# Bekötjük az smb.conf-ba (csak egyszer).
if [[ "$PROBA" == "1" ]]; then
    info "[próba] include sor az /etc/samba/smb.conf-ba"
elif grep -q 'szerverpark.conf' /etc/samba/smb.conf 2>/dev/null; then
    kihagy "smb.conf már tartalmazza a megosztásokat"
else
    cp /etc/samba/smb.conf "/etc/samba/smb.conf.mentes-$(date +%F)" 2>/dev/null || true
    printf '\n# --- szerverpark ---\ninclude = /etc/samba/szerverpark.conf\n' \
        >>/etc/samba/smb.conf
    ok "megosztások bekötve az smb.conf-ba"
fi

# --- tűzfal: csak a helyi hálózatról ----------------------------------------
# A helyi hálózat az ALAPÉRTELMEZETT útvonal interfészéhez tartozó tartomány
# (különben a docker0 172.17.0.0/16-ját hinnénk otthoni hálónak).
FO_IF="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}' || true)"
if [[ -n "$FO_IF" ]]; then
    HELYI_HALO="$(ip -4 route show scope link dev "$FO_IF" 2>/dev/null | awk '{print $1; exit}' || true)"
else
    HELYI_HALO=""
fi
if [[ -n "$HELYI_HALO" ]]; then
    tuzfal_halozatrol "$HELYI_HALO" "137,138,139,445" tcp
    tuzfal_ervenyesit
    ok "Samba engedve a helyi hálózatról ($HELYI_HALO), kívülről nem érhető el"
else
    figy "nem sikerült megállapítani a helyi hálózatot – a Samba-port zárva maradt"
fi

# shellcheck disable=SC2086
szolgaltatas_be $SAMBA_SZOLG
[[ "$PROBA" != "1" ]] && fut systemctl restart ${SAMBA_SZOLG%% *}

GEPNEV="$(hostname)"
szolgaltatas_jegyzes "Samba" "\\\\${GEPNEV}\\megosztas" "felhasználó: ${SMB_FELHASZNALO}"

:   # a modul sikeres visszatéréssel zárul (lásd: set -e + source)
