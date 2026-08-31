#!/usr/bin/env bash
# Restore stock Goose desktop UI from backup
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${GOOSE_CYBERPUNK_BACKUP:-$HOME/.local/share/goose-cyberpunk/backups}"
STOCK="$BACKUP_DIR/app.asar.stock"

find_asar() {
  if [[ -n "${GOOSE_ASAR:-}" && -f "$GOOSE_ASAR" ]]; then
    printf '%s\n' "$GOOSE_ASAR"; return 0
  fi
  case "$(uname -s)" in
    Darwin)
      for c in \
        "/Applications/Goose.app/Contents/Resources/app.asar" \
        "$HOME/Applications/Goose.app/Contents/Resources/app.asar"; do
        [[ -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
      done
      ;;
    *)
      for c in \
        "/usr/lib/goose/resources/app.asar" \
        "/opt/Goose/resources/app.asar" \
        "/opt/goose/resources/app.asar"; do
        [[ -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
      done
      ;;
  esac
  return 1
}

[[ -f "$STOCK" ]] || { echo "No stock backup at $STOCK — run apply-theme.sh first."; exit 1; }
asar="$(find_asar)" || { echo "Goose asar not found"; exit 1; }

if [[ -w "$(dirname "$asar")" ]]; then
  cp -a "$STOCK" "$asar"
elif command -v sudo >/dev/null 2>&1; then
  sudo cp -a "$STOCK" "$asar"
else
  echo "Need write access to $asar"; exit 1
fi
echo "Restored stock UI -> $asar"
echo "Restart Goose to load stock theme."
