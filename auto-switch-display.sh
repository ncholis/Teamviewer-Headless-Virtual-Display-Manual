#!/usr/bin/env bash
set -euo pipefail

USERNAME="${1:-hexa}"
USER_UID="$(id -u "$USERNAME")"
STATE_FILE="/var/lib/teamviewer-display-monitor/state"
LOG_TAG="tv-display-monitor"
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"

mkdir -p /var/lib/teamviewer-display-monitor

log() {
  echo "[$(date '+%F %T')] $*" | systemd-cat -t "$LOG_TAG"
  echo "[$(date '+%F %T')] $*"
}

get_x_env() {
  export DISPLAY=:0

  local auth=""
  auth="$(ps aux | awk '/[X]org/ && /-auth/ {for(i=1;i<=NF;i++) if($i=="-auth") {print $(i+1); exit}}')"

  if [[ -n "${auth}" && -f "${auth}" ]]; then
    export XAUTHORITY="$auth"
    return 0
  fi

  if [[ -f "/run/user/${USER_UID}/gdm/Xauthority" ]]; then
    export XAUTHORITY="/run/user/${USER_UID}/gdm/Xauthority"
    return 0
  fi

  if [[ -f "/home/${USERNAME}/.Xauthority" ]]; then
    export XAUTHORITY="/home/${USERNAME}/.Xauthority"
    return 0
  fi

  return 1
}

wait_for_x() {
  local i
  for i in $(seq 1 30); do
    if get_x_env && xrandr >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

physical_connected() {
  get_x_env
  xrandr | grep -E '^(HDMI|DP|VGA|DVI)-[0-9]+ connected' >/dev/null 2>&1
}

dummy_connected() {
  get_x_env
  xrandr | grep -E '^DUMMY0 connected' >/dev/null 2>&1
}

current_mode() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo "unknown"
  fi
}

set_state() {
  echo "$1" > "$STATE_FILE"
}

write_dummy_xorg() {
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
        Modes "1920x1080_60.00" "1920x1080" "1280x800" "1024x768"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "DummyLayout"
    Screen "DummyScreen"
EndSection
EOF
}

enable_gdm_autologin() {
  if [[ -f /etc/gdm3/custom.conf ]]; then
    cp /etc/gdm3/custom.conf /etc/gdm3/custom.conf.bak.tvmon 2>/dev/null || true

    if grep -q '^AutomaticLoginEnable=' /etc/gdm3/custom.conf; then
      sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=true/' /etc/gdm3/custom.conf
    else
      sed -i '/^\[daemon\]/a AutomaticLoginEnable=true' /etc/gdm3/custom.conf
    fi

    if grep -q '^AutomaticLogin=' /etc/gdm3/custom.conf; then
      sed -i "s/^AutomaticLogin=.*/AutomaticLogin=${USERNAME}/" /etc/gdm3/custom.conf
    else
      sed -i "/^\[daemon\]/a AutomaticLogin=${USERNAME}" /etc/gdm3/custom.conf
    fi

    if grep -q '^WaylandEnable=' /etc/gdm3/custom.conf; then
      sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
    else
      sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf
    fi
  fi
}

restart_stack() {
  log "Restarting gdm3 and teamviewerd"
  systemctl restart gdm3
  sleep 8
  systemctl restart teamviewerd || true
  sleep 3
}

switch_to_dummy() {
  log "Switching to dummy display mode"

  enable_gdm_autologin
  write_dummy_xorg
  restart_stack

  if wait_for_x; then
    get_x_env
    if ! xrandr | grep -q '1920x1080_60.00'; then
      xrandr --newmode "1920x1080_60.00" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync || true
    fi
    xrandr --addmode DUMMY0 "1920x1080_60.00" || true
    xrandr --output DUMMY0 --mode "1920x1080_60.00" || true
    set_state "dummy"
    log "Dummy mode active"
  else
    log "Failed waiting for X after switching to dummy mode"
  fi
}

switch_to_physical() {
  log "Switching to physical display mode"

  rm -f /etc/X11/xorg.conf
  restart_stack

  if wait_for_x; then
    get_x_env
    local output=""
    output="$(xrandr | awk '/^(HDMI|DP|VGA|DVI)-[0-9]+ connected/ {print $1; exit}')"

    if [[ -n "$output" ]]; then
      xrandr --output "$output" --auto || true
      set_state "physical"
      log "Physical mode active on output: $output"
    else
      log "No physical output found after restart; falling back to dummy"
      switch_to_dummy
      return 0
    fi
  else
    log "Failed waiting for X after switching to physical mode"
  fi
}

ensure_initial_mode() {
  local mode
  mode="$(current_mode)"

  if physical_connected; then
    if [[ "$mode" != "physical" ]]; then
      switch_to_physical
    else
      log "Initial state already physical"
    fi
  else
    if [[ "$mode" != "dummy" ]]; then
      switch_to_dummy
    else
      log "Initial state already dummy"
    fi
  fi
}

monitor_loop() {
  while true; do
    local mode
    mode="$(current_mode)"

    if physical_connected; then
      if [[ "$mode" != "physical" ]]; then
        log "Detected physical monitor connected"
        switch_to_physical
      fi
    else
      if [[ "$mode" != "dummy" ]]; then
        log "Detected no physical monitor, switching to dummy"
        switch_to_dummy
      fi
    fi

    sleep "$CHECK_INTERVAL"
  done
}

main() {
  if [[ $EUID -ne 0 ]]; then
    echo "Run as root"
    exit 1
  fi

  if ! id "$USERNAME" >/dev/null 2>&1; then
    echo "User '$USERNAME' not found"
    exit 1
  fi

  log "Starting display monitor for user: $USERNAME"

  if ! wait_for_x; then
    log "X not ready yet, continuing with best effort"
  fi

  ensure_initial_mode
  monitor_loop
}

main "$@"