#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo ./install-monitor-switch.sh [desktop_user]" >&2
  exit 1
fi

DESKTOP_USER="${1:-hexa}"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/teamviewer-display-monitor.service"
DUMMY_TEMPLATE="/etc/X11/xorg.conf.dummy-template"
AUTO_SWITCH_SRC="$(dirname "$0")/auto-switch-display.sh"

apt update
apt install -y xserver-xorg-video-dummy teamviewer

mkdir -p "$INSTALL_DIR"
install -m 0755 "$AUTO_SWITCH_SRC" "$INSTALL_DIR/auto-switch-display.sh"

sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf || true
if grep -q '^#\?AutomaticLoginEnable' /etc/gdm3/custom.conf; then
  sed -i 's/^#\?AutomaticLoginEnable.*/AutomaticLoginEnable=true/' /etc/gdm3/custom.conf
else
  printf '\nAutomaticLoginEnable=true\n' >> /etc/gdm3/custom.conf
fi
if grep -q '^#\?AutomaticLogin=' /etc/gdm3/custom.conf; then
  sed -i "s/^#\?AutomaticLogin=.*/AutomaticLogin=${DESKTOP_USER}/" /etc/gdm3/custom.conf
else
  printf 'AutomaticLogin=%s\n' "$DESKTOP_USER" >> /etc/gdm3/custom.conf
fi

cat > "$DUMMY_TEMPLATE" <<'EOC'
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
EOC
chmod 0644 "$DUMMY_TEMPLATE"

cat > "$SERVICE_FILE" <<EOC
[Unit]
Description=Monitor physical display and switch between physical and dummy Xorg config for TeamViewer
After=network.target teamviewerd.service gdm.service
Wants=teamviewerd.service

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/auto-switch-display.sh --interval 10 --user ${DESKTOP_USER}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOC

systemctl daemon-reload
systemctl enable --now teamviewer-display-monitor.service

echo "Installed. Check status with: systemctl status teamviewer-display-monitor.service"
echo "Logs: journalctl -u teamviewer-display-monitor.service -f"
