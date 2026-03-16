# TeamViewer Headless Fix for Ubuntu

Panduan singkat untuk mengatasi TeamViewer black screen pada Ubuntu headless dengan virtual display dummy 1920x1080.

## Isi
- `auto-install.sh` — script otomatis untuk memasang konfigurasi dummy display dan autologin
- `manual-installation.md` — panduan langkah demi langkah
- `manual-installation.pdf` — versi PDF

## Kasus yang Ditangani
- TeamViewer connect tapi layar hitam
- Ubuntu memakai GNOME/GDM
- Mesin tidak memiliki monitor fisik
- Perlu desktop virtual 1920x1080

## Quick Start

```bash
chmod +x auto-install.sh
sudo ./auto-install.sh hexa
```

Ganti `hexa` dengan username desktop yang ingin dipakai untuk auto-login.

Setelah script selesai:

```bash
sudo reboot
```

Sesudah reboot, verifikasi:

```bash
DISPLAY=:0 xrandr
loginctl list-sessions
systemctl status teamviewerd
```

Target utama:
- `DUMMY0 connected primary 1920x1080`
- user login pada `seat0`
- TeamViewer tidak lagi black screen

## Restore ke Monitor Fisik

```bash
sudo rm /etc/X11/xorg.conf
sudo reboot
```

## Catatan
Jika suatu saat monitor fisik ingin dipakai kembali, hapus konfigurasi dummy di atas. Saat `xorg.conf` dummy aktif, monitor fisik biasanya tidak digunakan.
