# TeamViewer Auto Switch: Physical Monitor <-> Dummy Display

This package adds automatic display switching for Ubuntu machines used headlessly with TeamViewer.

## Features

- Detects whether a physical monitor is connected
- Automatically switches to physical display when a monitor is present
- Automatically switches to dummy 1920x1080 display when no monitor is present
- Runs continuously under systemd
- Keeps TeamViewer usable on headless machines

## Included files

- `auto-switch-display.sh`
- `install-monitor-switch.sh`
- `teamviewer-display-monitor.service`
- `monitor-switch-manual.md`

## Quick start

```bash
chmod +x install-monitor-switch.sh auto-switch-display.sh
sudo ./install-monitor-switch.sh hexa
```

## Monitor logs

```bash
systemctl status teamviewer-display-monitor.service
journalctl -u teamviewer-display-monitor.service -f
```

## Important behavior

Whenever the mode changes, the script restarts `gdm3` and `teamviewerd`.
This means active remote sessions will briefly disconnect during a switch.

## Remove

```bash
sudo systemctl disable --now teamviewer-display-monitor.service
sudo rm -f /etc/systemd/system/teamviewer-display-monitor.service
sudo rm -f /usr/local/bin/auto-switch-display.sh
sudo rm -f /etc/X11/xorg.conf
sudo systemctl daemon-reload
sudo reboot
```
