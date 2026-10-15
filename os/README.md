# Botirocky

Saját, **Debian-alapú szerver-disztribúció** egyetlen bootolható ISO-ban. Két
dolgot tud, ugyanabból a lemezből:

1. **Mentő / recovery mód** — élő rendszer a `mento` eszközkészlettel: lemez- és
   fájlrendszer-javítás, chroot a telepített rendszerbe, GRUB újratelepítés, root
   jelszó visszaállítás, hálózat felhúzás, restic-mentés visszaállítása, lemez
   klónozás (ddrescue), memóriateszt.
2. **Automata telepítő** — feltelepít egy előkonfigurált Debiant, és rá a teljes
   [szerverpark](../szerverpark) self-hosting stacket (`szerverpark-telepit`).

A motor a Debian-natív **live-build**, ami rendes **hibrid ISO-t** készít (BIOS és
UEFI is bootolja), USB-re `dd`-vel írható.

## Mihez jó

- **Nem indul a szerver?** Bootold erről az USB-ről, `mento` → chroot / GRUB-újra
  / fsck / jelszó — és már megy is.
- **Új gép beüzemelése?** Ugyanez az USB feltelepíti a Debiant, majd a
  szerverpark stacket (Docker, Nextcloud, AI, mentés, proxy…) — egy menetben.
- **Egy USB az egész flottához.** A recovery és a telepítő ugyanaz a lemez.

## Építés

**Build-gép:** Debian/Ubuntu, root. A `keszit.sh` letölti a függőségeket
(`live-build`, `xorriso`), összeállítja a konfigot, és megépíti az ISO-t.

```bash
./keszit.sh --docker             # bármilyen Linuxon: privilegizált Debian-konténerben épít
sudo ./keszit.sh                 # Debian/Ubuntu build-gépen közvetlenül (~15-40 perc, több GB)
sudo ./keszit.sh --proba         # csak a terv + függőség-ellenőrzés (root sem kell)
sudo ./keszit.sh --disztro bookworm     # Debian 12 (alap: trixie = 13)
sudo ./keszit.sh --nev pi-park          # a rendszer hostneve
sudo ./keszit.sh --nincs-szerver        # csak a mentő rész, szerver stack nélkül
./keszit.sh --teszt [--uefi]     # a kész ISO bootolása QEMU-ban (qemu-system-x86 kell)
./keszit.sh --ssh-kulcs ~/.ssh/kulcs.pub   # ez a kulcs léphet be rootként (alap: ~/.ssh/id_ed25519.pub)
sudo ./keszit.sh --tiszta        # a build-melléktermékek törlése (lb clean)
```

Eredmény: `botirocky-<disztró>-<arch>.iso` (+ `.sha256`).

USB-re írás:

```bash
sudo dd if=botirocky-trixie-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## A `mento` mentőkészlet

Bootolt élő rendszeren és futó gépen is (`sudo mento`). Argumentum nélkül
interaktív menü (whiptail, vagy szöveges); közvetlenül is hívható:

| parancs | mit csinál |
|---------|------------|
| `mento rendszer` | hardver- és rendszer-infó (CPU, RAM, lemezek, hálózat, UEFI/BIOS) |
| `mento lemezek` | partíciók, helyfoglalás, SMART-egészség |
| `mento halozat [teszt]` | hálózat felhúzása (DHCP) + IP/DNS-teszt |
| `mento ssh be\|ki` | SSH bekapcsolása távoli segítséghez (élő rendszeren új jelszót kér) |
| `mento fajlrendszer` | fsck a megfelelő eszközzel (ext/xfs/btrfs/vfat/ntfs) |
| `mento chroot` | a telepített rendszer csatolása + chroot javításhoz |
| `mento rendszerbetolto` | GRUB újratelepítése (BIOS és UEFI) |
| `mento jelszo` | root jelszó visszaállítása (chroot + passwd) |
| `mento mentes` | restic pillanatképek listája + visszaállítás |
| `mento klonozas` | lemez mentése képfájlba (ddrescue) |
| `mento memoria` | memóriateszt (memtester / GRUB-memtest) |

A veszélyes műveletek `IGEN` beírását kérik, és a nem-root eszközök (infó,
lemez-lista, hálózat-teszt) rootolás nélkül is futnak.

## SSH és biztonság

- **Élő rendszer:** az SSH alapból **ki van kapcsolva**. `sudo mento ssh be` új jelszót
  kér a `user` felhasználónak (az alap `live` jelszóval nem indul), csak erre a
  munkamenetre. A beépített kulcs tulajdonosa rootként is beléphet.
- **Telepített rendszer:** SSH fut, **csak kulccsal** (`PasswordAuthentication no`,
  root: `prohibit-password`). A kulcsot a build teszi bele (`--ssh-kulcs`).
- **Host-kulcsok:** az ISO-ban nincsenek; minden gép az első indításkor saját kulcsot
  generál (`botirocky-ssh-kulcsok.service`).

## A telepítő

A „Botirocky telepítése” menüpont a preseed alapján dolgozik: magyar nyelv és
billentyűzet, Europe/Budapest, GPT, egy root-partíció + swap, deb.debian.org +
biztonsági frissítések. **Megkérdezi:** a root jelszót, több lemeznél a céllemezt,
és a végén, hogy felírja-e a partíciókat (ez az egyetlen biztonsági megerősítés).
Meglévő RAID/LVM-et nem töröl magától.

## Mi kerül az ISO-ba

- **Mentő-eszközök**: parted, gdisk, e2fsprogs, xfsprogs, btrfs-progs, ntfs-3g,
  exfatprogs, cryptsetup, lvm2, mdadm, smartmontools, nvme-cli, gddrescue,
  testdisk, rsync, restic, whiptail, network-manager, memtester…
- **`/usr/local/bin/mento`** — a fenti eszközkészlet.
- **`/opt/szerverpark` + `szerverpark-telepit`** — a self-hosting stack (kihagyható:
  `--nincs-szerver`).
- **preseed** — automata Debian-telepítés (magyar billentyűzet, Europe/Budapest,
  root-belépés, egész-lemezes particionálás).
- **branding** — Botirocky boot-menü (saját splash, magyar menüpontok), os-release
  (dpkg-divert, frissítéskor sem íródik felül), `/etc/issue`, `/etc/motd`.

## Felépítés

```
szerverpark-os/
  keszit.sh        # az ISO-készítő (live-build köré) – ez a belépési pont
  rendszer/mento   # a mentőkészlet (az ISO-ba kerül, de önállóan is futtatható)
  rendszer/splash.svg  # a boot-menü háttere
  README.md
```

A `keszit.sh` a build-időben állítja elő a live-build konfigot (`auto/`, `config/`),
ezért ezek nincsenek a repóban (lásd `.gitignore`). A tervet a `--proba` mutatja.

## Igények

- **Build-gép:** Debian/Ubuntu (`live-build`, `xorriso`, `librsvg2-bin`), vagy bármilyen
  Linux Dockerrel (`--docker`); ~10 GB hely, net.
- **Teszt (opcionális):** `qemu-system-x86` (+ `ovmf` az UEFI-hez).
- **Cél:** bármilyen amd64 gép (fizikai vagy VM), BIOS vagy UEFI.
