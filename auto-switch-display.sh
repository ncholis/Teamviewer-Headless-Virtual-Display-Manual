#!/usr/bin/env bash
set -euo pipefail

# Auto switch between physical monitor and dummy Xorg config for headless TeamViewer use.
# Usage:
#   sudo ./auto-switch-display.sh [--interval 10] [--user hexa] [--dummy-config /etc/X11/xorg.d/99-dummy-monitor.conf]
#
# Behavior:
# - If any physical connector is connected -> remove/disable dummy config and restart gdm3 + teamviewerd
# - If no physical connector is connected -> enable dummy config and restart gdm3 + teamviewerd
# - Runs continuously and logs to stdout/stderr (best used with systemd)

INTERVAL=10
DESKTOP_USER="hexa"
DUMMY_CONFIG="/etc/X11/xorg.conf"
DUMMY_CONFIG_TEMPLATE="/etc/X11/xorg.conf.dummy-template"
DISPLAY_MANAGER="gdm3"
TEAMVIEWER_SERVICE="teamviewerd"
STATE_FILE="/var/lib/teamviewer-display-switch/state"

log() {
  echo "[$(date '+%F %T')] $*"
}

usage() {
  sed -n '2,14p' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      INTERVAL="$2"; shift 2 ;;
    --user)
      DESKTOP_USER="$2"; shift 2 ;;
    --dummy-config)
      DUMMY_CONFIG="$2"; shift 2 ;;
    --dummy-template)
      DUMMY_CONFIG_TEMPLATE="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

mkdir -p "$(dirname "$STATE_FILE")"
mkdir -p "$(dirname "$DUMMY_CONFIG_TEMPLATE")"

ensure_dummy_template() {
  if [[ ! -f "$DUMMY_CONFIG_TEMPLATE" ]]; then
    cat > "$DUMMY_CONFIG_TEMPLATE" <<'EOC'
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
    chmod 0644 "$DUMMY_CONFIG_TEMPLATE"
  fi
}

physical_monitor_connected() {
  local status_file status connector base
  shopt -s nullglob
  for status_file in /sys/class/drm/card*-*/status; do
    connector="$(basename "$(dirname "$status_file")")"
    base="${connector#*-}"
    case "$base" in
      DUMMY*|VIRTUAL*|Virtual*|Writeback*|LVDS*|eDP*)
        continue ;;
    esac
    if read -r status < "$status_file" && [[ "$status" == "connected" ]]; then
      return 0
    fi
  done
  return 1
}

dummy_config_enabled() {
  [[ -f "$DUMMY_CONFIG" ]] && grep -q 'Driver[[:space:]]*"dummy"' "$DUMMY_CONFIG"
}

apply_dummy() {
  ensure_dummy_template
  install -m 0644 "$DUMMY_CONFIG_TEMPLATE" "$DUMMY_CONFIG"
  sed -i "s/^AutomaticLogin=.*/AutomaticLogin=${DESKTOP_USER}/" /etc/gdm3/custom.conf 2>/dev/null || true
  log "Enabled dummy monitor config: $DUMMY_CONFIG"
}

remove_dummy() {
  if [[ -f "$DUMMY_CONFIG" ]] && grep -q 'Driver[[:space:]]*"dummy"' "$DUMMY_CONFIG"; then
    rm -f "$DUMMY_CONFIG"
    log "Removed dummy monitor config: $DUMMY_CONFIG"
  fi
}

restart_stack() {
  log "Restarting ${DISPLAY_MANAGER} and ${TEAMVIEWER_SERVICE}"
  systemctl restart "$DISPLAY_MANAGER"
  sleep 4
  systemctl restart "$TEAMVIEWER_SERVICE"
}

switch_to_mode() {
  local target="$1"
  local current="unknown"
  [[ -f "$STATE_FILE" ]] && current="$(cat "$STATE_FILE" 2>/dev/null || true)"
  if [[ "$current" == "$target" ]]; then
    return 0
  fi
  case "$target" in
    dummy)
      apply_dummy
      restart_stack
      ;;
    physical)
      remove_dummy
      restart_stack
      ;;
    *)
      echo "Invalid target mode: $target" >&2
      return 1
      ;;
  esac
  echo "$target" > "$STATE_FILE"
  log "Switched display mode to: $target"
}

bootstrap_state() {
  if physical_monitor_connected; then
    echo "physical" > "$STATE_FILE"
  elif dummy_config_enabled; then
    echo "dummy" > "$STATE_FILE"
  else
    echo "physical" > "$STATE_FILE"
  fi
}

log "Starting auto display monitor (interval=${INTERVAL}s, user=${DESKTOP_USER})"
bootstrap_state

while true; do
  if physical_monitor_connected; then
    if dummy_config_enabled; then
      switch_to_mode physical
    fi
  else
    if ! dummy_config_enabled; then
      switch_to_mode dummy
    fi
  fi
  sleep "$INTERVAL"
done
