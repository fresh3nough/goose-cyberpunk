#!/usr/bin/env bash
# Apply neon cyberpunk theme to Goose desktop (Linux + macOS)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSS_SRC="$ROOT/theme/cyberpunk-neon.css"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/goose-cyberpunk"
BACKUP_DIR="${GOOSE_CYBERPUNK_BACKUP:-$HOME/.local/share/goose-cyberpunk/backups}"
WORK_DIR="${TMPDIR:-/tmp}/goose-cyberpunk-work-$$"
LOG_FILE="$STATE_DIR/apply.log"

mkdir -p "$STATE_DIR" "$BACKUP_DIR"

log() { printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# Resolve Goose app.asar path
find_asar() {
  if [[ -n "${GOOSE_ASAR:-}" && -f "$GOOSE_ASAR" ]]; then
    printf '%s\n' "$GOOSE_ASAR"
    return 0
  fi

  local candidates=()
  case "$(uname -s)" in
    Darwin)
      candidates+=(
        "/Applications/Goose.app/Contents/Resources/app.asar"
        "$HOME/Applications/Goose.app/Contents/Resources/app.asar"
        "/Applications/goose.app/Contents/Resources/app.asar"
      )
      # Homebrew cask / alternate names
      local app
      for app in /Applications/*.app "$HOME"/Applications/*.app; do
        [[ -d "$app" ]] || continue
        local base
        base="$(basename "$app" .app | tr '[:upper:]' '[:lower:]')"
        if [[ "$base" == *goose* ]]; then
          candidates+=("$app/Contents/Resources/app.asar")
        fi
      done
      ;;
    Linux|*)
      candidates+=(
        "/usr/lib/goose/resources/app.asar"
        "/usr/lib64/goose/resources/app.asar"
        "/opt/Goose/resources/app.asar"
        "/opt/goose/resources/app.asar"
        "$HOME/.local/share/Goose/resources/app.asar"
        "$HOME/squashfs-root/resources/app.asar"
      )
      # Flatpak
      if [[ -d "$HOME/.local/share/flatpak/app" ]]; then
        while IFS= read -r p; do candidates+=("$p"); done < <(find "$HOME/.local/share/flatpak/app" -path '*/resources/app.asar' 2>/dev/null | head -20)
      fi
      ;;
  esac

  local c
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

find_settings_json() {
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "$HOME/Library/Application Support/Goose/settings.json"
      ;;
    *)
      printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/Goose/settings.json"
      ;;
  esac
}

ensure_asar_tools() {
  if command -v npx >/dev/null 2>&1; then
    ASAR_EXTRACT=(npx --yes asar extract)
    ASAR_PACK=(npx --yes asar pack)
    return 0
  fi
  if command -v asar >/dev/null 2>&1; then
    ASAR_EXTRACT=(asar extract)
    ASAR_PACK=(asar pack)
    return 0
  fi
  die "need Node.js npx (or global asar). Install Node 18+ then retry."
}

write_root() {
  # write $1 -> $2 with root if needed
  local src="$1" dst="$2"
  if [[ -w "$(dirname "$dst")" ]] && { [[ ! -e "$dst" ]] || [[ -w "$dst" ]]; }; then
    cp -a "$src" "$dst"
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo cp -a "$src" "$dst"
    return 0
  fi
  if command -v pkexec >/dev/null 2>&1; then
    pkexec cp -a "$src" "$dst"
    return 0
  fi
  die "cannot write $dst (need sudo)"
}

macos_refresh_integrity_and_signature() {
  local asar="$1" app_root plist staged_plist header_hash
  [[ "$(uname -s)" == "Darwin" ]] || return 0

  app_root="$(cd "$(dirname "$asar")/../.." && pwd)"
  plist="$app_root/Contents/Info.plist"
  [[ -f "$plist" ]] || die "could not find Info.plist for $app_root"

  # Electron validates the SHA-256 of the raw ASAR JSON header at startup. A
  # repacked archive has a new header, so the packaged value must be refreshed.
  header_hash="$(python3 - "$asar" <<'PY'
import hashlib, struct, sys
with open(sys.argv[1], "rb") as archive:
    prefix = archive.read(16)
    if len(prefix) != 16:
        raise SystemExit("ASAR is too small")
    header_size = struct.unpack_from("<I", prefix, 12)[0]
    header = archive.read(header_size)
    if len(header) != header_size:
        raise SystemExit("ASAR header is truncated")
print(hashlib.sha256(header).hexdigest())
PY
)" || die "could not calculate ASAR header hash"

  staged_plist="$WORK_DIR/out/Info.plist"
  cp -a "$plist" "$staged_plist"
  /usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:algorithm SHA256" "$staged_plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :ElectronAsarIntegrity:Resources/app.asar:algorithm string SHA256" "$staged_plist"
  /usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $header_hash" "$staged_plist"

  log "updating Electron ASAR integrity metadata"
  write_root "$staged_plist" "$plist"

  # Updating Info.plist invalidates the vendor signature. Re-signing ad hoc is
  # sufficient for local use and keeps macOS and Electron in agreement.
  log "re-signing macOS app bundle for local use"
  if [[ -w "$app_root" ]]; then
    codesign --force --deep --sign - "$app_root"
  elif command -v sudo >/dev/null 2>&1; then
    sudo codesign --force --deep --sign - "$app_root"
  else
    die "cannot re-sign $app_root (need write access to the app bundle)"
  fi
  codesign --verify --deep --strict --verbose=2 "$app_root" || die "macOS signature verification failed"
}

force_dark_settings() {
  local settings
  settings="$(find_settings_json)"
  mkdir -p "$(dirname "$settings")"
  python3 - "$settings" <<'PY'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.isfile(path):
    try:
        with open(path) as f:
            data = json.load(f) or {}
    except Exception:
        data = {}
data["theme"] = "dark"
data["useSystemTheme"] = False
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(path)
PY
}

patch_extracted() {
  local root="$1"
  local html css_dest js_files
  html="$(find "$root" -path '*/renderer/main_window/index.html' | head -1)"
  [[ -n "$html" && -f "$html" ]] || die "could not find renderer index.html inside asar"
  local assets
  assets="$(dirname "$html")/assets"
  mkdir -p "$assets"
  cp -a "$CSS_SRC" "$assets/cyberpunk-neon.css"
  css_dest="./assets/cyberpunk-neon.css"

  python3 - "$html" "$css_dest" <<'PY'
import re, sys
from pathlib import Path
html_path = Path(sys.argv[1])
css_href = sys.argv[2]
html = html_path.read_text(encoding="utf-8")

# Force dark in early theme bootstrap (several possible shapes)
replacements = [
    # already patched block is fine
]
# Generic: after computing isDark, force dark class
html2 = re.sub(
    r"if\s*\(\s*isDark\s*\)\s*\{\s*document\.documentElement\.classList\.add\('dark'\);\s*document\.documentElement\.style\.colorScheme\s*=\s*'dark';\s*\}\s*else\s*\{\s*document\.documentElement\.classList\.remove\('dark'\);\s*document\.documentElement\.style\.colorScheme\s*=\s*'light';\s*\}",
    """// Cyberpunk override: always dark neon
              document.documentElement.classList.add('dark');
              document.documentElement.style.colorScheme = 'dark';
              try {
                localStorage.setItem('theme', 'dark');
                localStorage.setItem('use_system_theme', 'false');
              } catch (e) {}""",
    html,
    count=1,
)
if html2 == html:
    # fallback: ensure dark class near initializeTheme start
    if "Cyberpunk override" not in html:
        html2 = html.replace(
            "function initializeTheme() {",
            """function initializeTheme() {
          // Cyberpunk override: always dark neon
          try {
            document.documentElement.classList.add('dark');
            document.documentElement.style.colorScheme = 'dark';
            if (window.localStorage) {
              localStorage.setItem('theme', 'dark');
              localStorage.setItem('use_system_theme', 'false');
            }
          } catch (e) {}"""
        )
else:
    pass
html = html2

# Link CSS if missing
if "cyberpunk-neon.css" not in html:
    # after last stylesheet link, or before </head>
    if re.search(r'<link[^>]+rel="stylesheet"[^>]*>', html):
        html = re.sub(
            r'(<link[^>]+rel="stylesheet"[^>]*>)',
            r'\1\n    <link rel="stylesheet" href="%s">' % css_href,
            html,
            count=1,
        )
    else:
        html = html.replace("</head>", f'    <link rel="stylesheet" href="{css_href}">\n  </head>')

html_path.write_text(html, encoding="utf-8")
print(f"patched {html_path}")
PY

  # Patch runtime color token maps in JS bundles (dark + light -> cyberpunk)
  python3 - "$assets" <<'PY'
import re, sys
from pathlib import Path
assets = Path(sys.argv[1])

cyber = {
  "--color-background-primary": "#07070f",
  "--color-background-secondary": "#0e0e1a",
  "--color-background-tertiary": "#16162a",
  "--color-background-inverse": "#f0e6ff",
  "--color-background-ghost": "transparent",
  "--color-background-info": "#00e5ff",
  "--color-background-danger": "#ff2a6d",
  "--color-background-success": "#39ff14",
  "--color-background-warning": "#fcee0a",
  "--color-background-disabled": "#1a1a2e",
  "--color-text-primary": "#e8f6ff",
  "--color-text-secondary": "#8ab4c8",
  "--color-text-tertiary": "#5a7a8c",
  "--color-text-inverse": "#07070f",
  "--color-text-ghost": "#8ab4c8",
  "--color-text-info": "#00e5ff",
  "--color-text-danger": "#ff2a6d",
  "--color-text-success": "#39ff14",
  "--color-text-warning": "#fcee0a",
  "--color-text-disabled": "#3d4f5c",
  "--color-border-primary": "#2a1a40",
  "--color-border-secondary": "#525b68",
  "--color-border-tertiary": "#474e57",
  "--color-border-inverse": "#f0e6ff",
  "--color-border-ghost": "transparent",
  "--color-border-info": "#00e5ff",
  "--color-border-danger": "#ff2a6d",
  "--color-border-success": "#39ff14",
  "--color-border-warning": "#fcee0a",
  "--color-border-disabled": "#1a1a2e",
  "--color-ring-primary": "#ff00aa",
  "--color-ring-secondary": "#00e5ff",
  "--color-ring-inverse": "#07070f",
  "--color-ring-info": "#00e5ff",
  "--color-ring-danger": "#ff2a6d",
  "--color-ring-success": "#39ff14",
  "--color-ring-warning": "#fcee0a",
  "--shadow-hairline": "0 0 0 1px rgba(255, 0, 170, 0.2)",
  "--shadow-sm": "0 0 8px rgba(0, 229, 255, 0.25)",
  "--shadow-md": "0 0 16px rgba(255, 0, 170, 0.25), 0 4px 12px rgba(0,0,0,0.4)",
  "--shadow-lg": "0 0 28px rgba(0, 229, 255, 0.3), 0 10px 24px rgba(0,0,0,0.5)",
}
obj = "{" + ",".join(f'"{k}":"{v}"' for k, v in cyber.items()) + "}"

# Match known stock dark/light token objects by distinctive first colors
patterns = [
    # dark stock
    r'\{"--color-background-primary":"#22252a".*?"--shadow-lg":"[^"]*"\}',
    # light stock
    r'\{"--color-background-primary":"#ffffff".*?"--shadow-lg":"[^"]*"\}',
    # already cyber / alternate dark greys sometimes used
    r'\{"--color-background-primary":"#07070f".*?"--shadow-lg":"[^"]*"\}',
]

bubble_reps = [
    (".dark .user-message-bubble{color:#d2dae6;background-color:#171d30}",
     ".dark .user-message-bubble{color:#ffb3ec;background-color:#2a0a24;border:1px solid #ff00aa88;box-shadow:0 0 12px #ff00aa44}"),
    (".dark .agent-message-bubble{background-color:#1f2126;border-radius:.75rem;padding:.625rem 1rem}",
     ".dark .agent-message-bubble{background-color:#0a1a28;border:1px solid #00e5ff66;border-radius:.75rem;padding:.625rem 1rem;box-shadow:0 0 12px #00e5ff44;color:#c8f7ff}"),
]

count_files = 0
for js in assets.glob("*.js"):
    text = js.read_text(encoding="utf-8", errors="ignore")
    orig = text
    for pat in patterns:
        text = re.sub(pat, obj, text)
    for a, b in bubble_reps:
        text = text.replace(a, b)
    if text != orig:
        js.write_text(text, encoding="utf-8")
        count_files += 1
        print(f"patched tokens in {js.name}")
print(f"js files changed: {count_files}")
PY
}

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

main() {
  need_cmd python3
  [[ -f "$CSS_SRC" ]] || die "theme css missing: $CSS_SRC"
  ensure_asar_tools

  local asar
  asar="$(find_asar)" || die "Goose app.asar not found. Set GOOSE_ASAR=/path/to/app.asar"
  log "target asar: $asar"

  # Backup once per content hash
  local hash
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$asar" | awk '{print $1}')"
  else
    hash="$(shasum -a 256 "$asar" | awk '{print $1}')"
  fi
  local backup="$BACKUP_DIR/app.asar.stock.$hash"
  if [[ ! -f "$BACKUP_DIR/app.asar.stock" ]]; then
    cp -a "$asar" "$BACKUP_DIR/app.asar.stock"
    log "saved stock backup -> $BACKUP_DIR/app.asar.stock"
  fi
  if [[ ! -f "$backup" ]]; then
    cp -a "$asar" "$backup"
    log "saved hash backup -> $backup"
  fi

  mkdir -p "$WORK_DIR/extract" "$WORK_DIR/out"
  log "extracting asar..."
  "${ASAR_EXTRACT[@]}" "$asar" "$WORK_DIR/extract"

  log "patching theme into extract..."
  patch_extracted "$WORK_DIR/extract"

  log "packing asar..."
  "${ASAR_PACK[@]}" "$WORK_DIR/extract" "$WORK_DIR/out/app.asar"

  # Also store last themed copy for permanence helpers
  mkdir -p "$HOME/.local/share/goose-cyberpunk"
  cp -a "$WORK_DIR/out/app.asar" "$HOME/.local/share/goose-cyberpunk/app.asar.themed"
  cp -a "$CSS_SRC" "$HOME/.local/share/goose-cyberpunk/cyberpunk-neon.css"

  log "installing themed asar (may ask for password)..."
  write_root "$WORK_DIR/out/app.asar" "$asar"
  macos_refresh_integrity_and_signature "$asar"

  local settings_path
  settings_path="$(force_dark_settings)"
  log "forced dark settings -> $settings_path"

  # Record
  cat > "$STATE_DIR/last-apply.json" <<EOF
{
  "asar": "$asar",
  "hash_before": "$hash",
  "backup": "$BACKUP_DIR/app.asar.stock",
  "applied_at": "$(date -Iseconds 2>/dev/null || date)"
}
EOF
  log "SUCCESS: cyberpunk theme applied. Restart Goose to see it."
  echo
  echo "Restart Goose completely (quit + reopen) to load the theme."
  echo "Backup: $BACKUP_DIR/app.asar.stock"
  echo "Restore: $ROOT/scripts/restore-theme.sh"
}

main "$@"
