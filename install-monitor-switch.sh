#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: sudo ./install-monitor-switch.sh <username>"
}

USERNAME="${1:-}"

if [[ -z "$USERNAME" ]]; then
  usage
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

if ! id "$USERNAME" >/dev/null 2>&1; then
  echo "User '$USERNAME' not found"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/auto-switch-display.sh"

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
  echo "Missing required file: $SOURCE_SCRIPT"
  exit 1
fi

install -d /usr/local/bin
install -d /var/lib/teamviewer-display-monitor
install -m 0755 "$SOURCE_SCRIPT" /usr/local/bin/auto-switch-display.sh

cat > /etc/systemd/system/teamviewer-display-monitor.service <<EOF
[Unit]
Description=Monitor physical display and switch between physical and dummy Xorg config for TeamViewer
After=network.target teamviewerd.service gdm.service
Wants=teamviewerd.service

[Service]
Type=simple
# Desktop user that should own the session.
ExecStart=/usr/local/bin/auto-switch-display.sh --interval 10 --user ${USERNAME}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable teamviewer-display-monitor.service
systemctl restart teamviewer-display-monitor.service

echo "Installed successfully."
echo "Check status with:"
echo "  systemctl status teamviewer-display-monitor.service"
echo "  journalctl -u teamviewer-display-monitor.service -f"
