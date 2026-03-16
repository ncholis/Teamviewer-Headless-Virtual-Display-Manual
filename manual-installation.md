# Fix TeamViewer Black Screen + Virtual Display 1920x1080 (Ubuntu)

Panduan ini menjelaskan cara memperbaiki TeamViewer yang hanya menampilkan layar hitam pada Ubuntu headless, dengan membuat virtual display dummy dan mengatur resolusi 1920x1080.

## 1. Gejala Masalah

Gejala umum:
- TeamViewer berhasil connect
- layar hanya hitam
- GNOME/GUI sebenarnya berjalan
- mesin tidak memiliki monitor fisik

Cek kondisi display:

```bash
DISPLAY=:0 xrandr
```

Jika hasilnya menunjukkan semua port `disconnected`, berarti GPU tidak mendeteksi monitor fisik.

## 2. Pastikan GUI dan TeamViewer Berjalan

Cek GDM:

```bash
systemctl status gdm3
```

Cek TeamViewer:

```bash
teamviewer info
# atau
systemctl status teamviewerd
```

Keduanya harus berstatus `active (running)`.

## 3. Aktifkan Auto Login User Desktop

Edit file konfigurasi GDM:

```bash
sudo nano /etc/gdm3/custom.conf
```

Isi bagian `[daemon]` seperti ini:

```ini
[daemon]
WaylandEnable=false
AutomaticLoginEnable=true
AutomaticLogin=hexa
```

Ganti `hexa` dengan username yang dipakai.

Restart GDM:

```bash
sudo systemctl restart gdm3
```

## 4. Install Driver Dummy

```bash
sudo apt update
sudo apt install -y xserver-xorg-video-dummy
```

## 5. Buat Konfigurasi Xorg Dummy 1920x1080

Buat file `/etc/X11/xorg.conf`:

```bash
sudo nano /etc/X11/xorg.conf
```

Isi dengan konfigurasi ini:

```conf
Section "Device"
    Identifier  "DummyDevice"
    Driver      "dummy"
    VideoRam    256000
EndSection

Section "Monitor"
    Identifier  "DummyMonitor"
    HorizSync   28-80
    VertRefresh 48-75
    Modeline "1920x1080_60.00" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync
EndSection

Section "Screen"
    Identifier  "DummyScreen"
    Device      "DummyDevice"
    Monitor     "DummyMonitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Virtual 1920 1080
        Modes "1920x1080_60.00" "1280x800" "1024x768"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "DummyLayout"
    Screen "DummyScreen"
EndSection
```

## 6. Restart GUI

```bash
sudo systemctl restart gdm3
# atau
sudo reboot
```

## 7. Verifikasi Virtual Monitor

```bash
DISPLAY=:0 xrandr
```

Target output:

```text
DUMMY0 connected primary 1920x1080
```

## 8. Restart TeamViewer

```bash
sudo systemctl restart teamviewerd
# atau
sudo teamviewer daemon restart
```

Lalu reconnect dari client TeamViewer.

## 9. Verifikasi Session Desktop

```bash
loginctl list-sessions
```

Pastikan user desktop muncul di `seat0`, misalnya:

```text
5 1000 hexa seat0 tty2 active no -
```

## 10. Jika Ingin Kembali ke Monitor Fisik

Hapus konfigurasi dummy lalu reboot:

```bash
sudo rm /etc/X11/xorg.conf
sudo reboot
```

## 11. Catatan Penting

- Dengan `xorg.conf` dummy aktif, monitor fisik biasanya tidak akan dipakai.
- Setup ini cocok untuk robot, workstation remote, dan server grafis headless.
- Solusi hardware yang lebih stabil adalah memakai HDMI dummy plug.

## 12. Ringkasan Alur

```text
Install dummy driver
-> aktifkan autologin
-> buat xorg.conf dummy
-> restart gdm3
-> verifikasi DUMMY0 1920x1080
-> restart TeamViewer
-> reconnect
```
