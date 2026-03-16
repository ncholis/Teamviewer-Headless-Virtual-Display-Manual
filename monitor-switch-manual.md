# Auto Switch Monitor Manual

## Tujuan
Dokumen ini menambahkan monitoring otomatis pada Ubuntu headless agar:

- jika **monitor fisik terdeteksi aktif**, sistem **switch ke display fisik**
- jika **monitor fisik tidak ada / mati**, sistem **switch ke dummy display 1920x1080**
- perubahan ini dimonitor terus-menerus oleh service systemd

## Catatan penting
Setiap kali terjadi perpindahan mode, script akan me-restart:

- `gdm3`
- `teamviewerd`

Akibatnya, sesi desktop / TeamViewer akan terputus sebentar saat switching. Ini normal.

## File yang disediakan

- `auto-switch-display.sh` — daemon monitoring dan switching
- `install-monitor-switch.sh` — installer otomatis
- `teamviewer-display-monitor.service` — unit systemd

## Cara kerja
Script membaca status monitor fisik dari `/sys/class/drm/card*-*/status`.

Logika switching:

- Jika ada konektor fisik berstatus `connected` → hapus config dummy → restart `gdm3` dan `teamviewerd`
- Jika tidak ada konektor fisik yang `connected` → aktifkan config dummy → restart `gdm3` dan `teamviewerd`

Connector virtual seperti `DUMMY*` diabaikan.

## Instalasi cepat

Jalankan installer berikut sebagai root:

```bash
chmod +x install-monitor-switch.sh auto-switch-display.sh
sudo ./install-monitor-switch.sh hexa
```

Ganti `hexa` dengan username GUI yang dipakai untuk auto-login.

## Menjalankan manual tanpa install service

```bash
sudo ./auto-switch-display.sh --interval 10 --user hexa
```

## Lokasi file setelah instalasi

- Script: `/usr/local/bin/auto-switch-display.sh`
- Service: `/etc/systemd/system/teamviewer-display-monitor.service`
- Template dummy: `/etc/X11/xorg.conf.dummy-template`
- Config aktif dummy: `/etc/X11/xorg.conf`
- State file: `/var/lib/teamviewer-display-switch/state`

## Monitoring status service

Cek status:

```bash
systemctl status teamviewer-display-monitor.service
```

Lihat log real-time:

```bash
journalctl -u teamviewer-display-monitor.service -f
```

## Verifikasi mode aktif

### Cek session GUI

```bash
loginctl list-sessions
```

### Cek output display

```bash
DISPLAY=:0 xrandr
```

Jika dummy aktif, biasanya terlihat:

```text
DUMMY0 connected primary 1920x1080
```

Jika monitor fisik aktif dan config dummy dilepas, output akan kembali menunjukkan konektor seperti:

```text
HDMI-1 connected
DP-1 connected
```

## Menghentikan monitoring

```bash
sudo systemctl disable --now teamviewer-display-monitor.service
```

## Menghapus konfigurasi

```bash
sudo systemctl disable --now teamviewer-display-monitor.service
sudo rm -f /etc/systemd/system/teamviewer-display-monitor.service
sudo rm -f /usr/local/bin/auto-switch-display.sh
sudo rm -f /etc/X11/xorg.conf
sudo systemctl daemon-reload
sudo reboot
```

## Saran operasional

- gunakan interval 10–15 detik agar tidak terlalu agresif
- saat plugging / unplugging monitor, tunggu beberapa detik sampai service mendeteksi perubahan
- jika ada kebutuhan tanpa restart `gdm3`, perlu pendekatan lain yang lebih kompleks dan tidak selalu stabil di TeamViewer
