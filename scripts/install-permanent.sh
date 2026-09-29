#!/usr/bin/env bash
# Make inverted neon cyberpunk theme re-apply on login / if Goose is updated
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT/scripts/apply-theme.sh"
chmod +x "$ROOT/scripts/"*.sh

# Ensure themed copy exists
"$APPLY"

case "$(uname -s)" in
  Darwin)
    mkdir -p "$HOME/Library/LaunchAgents"
    PLIST="$HOME/Library/LaunchAgents/com.goose.cyberpunk-theme.plist"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.goose.cyberpunk-theme</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$APPLY</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/goose-cyberpunk.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/goose-cyberpunk.err</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "Installed LaunchAgent: $PLIST"
    echo "Runs at login and hourly."
    ;;
  Linux)
    mkdir -p "$HOME/.config/systemd/user" "$HOME/.config/autostart" "$HOME/.local/bin"
    # Wrapper on PATH
    ln -sfn "$APPLY" "$HOME/.local/bin/goose-apply-cyberpunk-theme"

    cat > "$HOME/.config/systemd/user/goose-cyberpunk-theme.service" <<EOF
[Unit]
Description=Apply Goose inverted neon cyberpunk desktop theme
After=default.target

[Service]
Type=oneshot
ExecStart=$APPLY
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF

    # Resolve live asar path for the path unit (may differ by package layout).
    ASAR_PATH="/usr/lib/goose/resources/app.asar"
    if [[ ! -f "$ASAR_PATH" ]]; then
      ASAR_PATH="$(find /usr/lib /usr/lib64 /opt -path '*/goose*/resources/app.asar' 2>/dev/null | head -1 || true)"
    fi
    ASAR_PATH="${ASAR_PATH:-/usr/lib/goose/resources/app.asar}"
    cat > "$HOME/.config/systemd/user/goose-cyberpunk-theme.path" <<EOF
[Unit]
Description=Watch Goose app.asar and re-apply inverted neon cyberpunk theme

[Path]
PathModified=${ASAR_PATH}
PathChanged=${ASAR_PATH}
Unit=goose-cyberpunk-theme.service

[Install]
WantedBy=default.target
EOF

    cat > "$HOME/.config/autostart/goose-cyberpunk-theme.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Goose Cyberpunk Theme
Comment=Re-apply inverted neon cyberpunk theme to Goose on login
Exec=$APPLY
X-GNOME-Autostart-enabled=true
StartupNotify=false
NoDisplay=true
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now goose-cyberpunk-theme.service
    systemctl --user enable --now goose-cyberpunk-theme.path 2>/dev/null || true
    echo "Installed systemd user service + path watcher + autostart."
    ;;
  *)
    echo "Unsupported OS for permanence helper; run scripts/apply-theme.sh manually after updates."
    ;;
esac

echo "Permanent install complete."
