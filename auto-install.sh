#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Jalankan script ini dengan sudo atau sebagai root."
  exit 1
fi

USERNAME="${1:-}"
if [[ -z "${USERNAME}" ]]; then
  echo "Usage: sudo ./auto-install.sh <username>"
  exit 1
fi

if ! id "${USERNAME}" >/dev/null 2>&1; then
  echo "User '${USERNAME}' tidak ditemukan."
  exit 1
fi

echo "[1/7] Install package dummy display..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y xserver-xorg-video-dummy

echo "[2/7] Backup konfigurasi lama..."
mkdir -p /root/teamviewer-headless-backup
if [[ -f /etc/gdm3/custom.conf ]]; then
  cp /etc/gdm3/custom.conf /root/teamviewer-headless-backup/custom.conf.bak
fi
if [[ -f /etc/X11/xorg.conf ]]; then
  cp /etc/X11/xorg.conf /root/teamviewer-headless-backup/xorg.conf.bak
fi

echo "[3/7] Tulis konfigurasi GDM autologin..."
cat > /etc/gdm3/custom.conf <<EOF
# GDM configuration storage

[daemon]
WaylandEnable=false
AutomaticLoginEnable=true
AutomaticLogin=${USERNAME}

[security]

[xdmcp]

[chooser]

[debug]
EOF

echo "[4/7] Tulis konfigurasi Xorg dummy 1920x1080..."
cat > /etc/X11/xorg.conf <<'EOF'
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
EOF

echo "[5/7] Restart service..."
systemctl restart gdm3 || true
systemctl restart teamviewerd || true

echo "[6/7] Verifikasi dasar..."
echo "---- loginctl list-sessions ----"
loginctl list-sessions || true
echo "---- teamviewerd status ----"
systemctl --no-pager --full status teamviewerd || true
echo "---- xrandr ----"
su - "${USERNAME}" -c 'DISPLAY=:0 xrandr' || true

echo "[7/7] Selesai."
echo
echo "Langkah berikutnya:"
echo "1. Reboot mesin: sudo reboot"
echo "2. Reconnect TeamViewer"
echo "3. Verifikasi DUMMY0 muncul pada DISPLAY=:0 xrandr"
