#!/usr/bin/env bash
set -euo pipefail
case "$(uname -s)" in
  Darwin)
    PLIST="$HOME/Library/LaunchAgents/com.goose.cyberpunk-theme.plist"
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed LaunchAgent"
    ;;
  Linux)
    systemctl --user disable --now goose-cyberpunk-theme.service 2>/dev/null || true
    systemctl --user disable --now goose-cyberpunk-theme.path 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/goose-cyberpunk-theme.service"
    rm -f "$HOME/.config/systemd/user/goose-cyberpunk-theme.path"
    rm -f "$HOME/.config/autostart/goose-cyberpunk-theme.desktop"
    rm -f "$HOME/.local/bin/goose-apply-cyberpunk-theme"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "Removed systemd units + autostart"
    ;;
esac
