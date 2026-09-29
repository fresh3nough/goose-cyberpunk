#!/usr/bin/env bash
# Apply inverted neon cyberpunk theme to Goose desktop (Linux + macOS)
# Bright neon surfaces + bold black text
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
      # dpkg-installed desktop binary path (symlink target dir)
      if command -v goose >/dev/null 2>&1; then
        local goose_bin goose_dir
        goose_bin="$(command -v goose)"
        if [[ -L "$goose_bin" ]]; then
          goose_bin="$(readlink -f "$goose_bin" 2>/dev/null || readlink "$goose_bin")"
        fi
        goose_dir="$(dirname "$goose_bin")"
        candidates+=("$goose_dir/resources/app.asar")
      fi
      # Broad search under common prefixes (bounded)
      while IFS= read -r p; do candidates+=("$p"); done < <(
        find /usr/lib /usr/lib64 /opt "$HOME/.local" -path '*/goose*/resources/app.asar' 2>/dev/null | head -20
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

# Prefer system npx, then Goose-bundled Electron helper binaries, then global asar.
ensure_asar_tools() {
  # Goose desktop ships node/npx under resources/bin on Linux.
  local goose_bin_paths=(
    "/usr/lib/goose/resources/bin"
    "/usr/lib64/goose/resources/bin"
    "/opt/Goose/resources/bin"
    "/opt/goose/resources/bin"
  )
  local p
  for p in "${goose_bin_paths[@]}"; do
    if [[ -x "$p/npx" || -x "$p/node" ]]; then
      export PATH="$p:$PATH"
      log "using Goose-bundled node tools from $p"
      break
    fi
  done

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
  die "need Node.js npx (or global asar). Install Node 18+ then retry (or install Goose desktop which bundles npx)."
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
    """// Cyberpunk override: force themed class (inverted neon CSS hooks .dark)
              document.documentElement.classList.add('dark');
              document.documentElement.style.colorScheme = 'light';
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
          // Cyberpunk override: force themed class (inverted neon CSS hooks .dark)
          try {
            document.documentElement.classList.add('dark');
            document.documentElement.style.colorScheme = 'light';
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
  # inverted neon: bright surfaces + bold black text
  "--color-background-primary": "#fff200",
  "--color-background-secondary": "#ffe600",
  "--color-background-tertiary": "#ffd400",
  "--color-background-inverse": "#0a0a0a",
  "--color-background-ghost": "transparent",
  "--color-background-info": "#00e5ff",
  "--color-background-danger": "#ff2a2a",
  "--color-background-success": "#39ff14",
  "--color-background-warning": "#ff6b00",
  "--color-background-disabled": "#ffe066",
  "--color-text-primary": "#0a0a0a",
  "--color-text-secondary": "#1a1a1a",
  "--color-text-tertiary": "#2a2a2a",
  "--color-text-inverse": "#fff200",
  "--color-text-ghost": "#1a1a1a",
  "--color-text-info": "#003844",
  "--color-text-danger": "#3b0000",
  "--color-text-success": "#062a00",
  "--color-text-warning": "#2a1000",
  "--color-text-disabled": "#4a4a4a",
  "--color-border-primary": "#0a0a0a",
  "--color-border-secondary": "#ff2a2a",
  "--color-border-tertiary": "#00b8d4",
  "--color-border-inverse": "#fff200",
  "--color-border-ghost": "transparent",
  "--color-border-info": "#007a8a",
  "--color-border-danger": "#b30000",
  "--color-border-success": "#1a7a00",
  "--color-border-warning": "#b34a00",
  "--color-border-disabled": "#c9a800",
  "--color-ring-primary": "#ff2a2a",
  "--color-ring-secondary": "#00e5ff",
  "--color-ring-inverse": "#fff200",
  "--color-ring-info": "#00e5ff",
  "--color-ring-danger": "#ff2a2a",
  "--color-ring-success": "#39ff14",
  "--color-ring-warning": "#ff6b00",
  "--shadow-hairline": "0 0 0 2px rgba(10, 10, 10, 0.85)",
  "--shadow-sm": "0 0 10px rgba(0, 229, 255, 0.45)",
  "--shadow-md": "0 0 16px rgba(255, 42, 42, 0.35), 0 4px 12px rgba(0,0,0,0.2)",
  "--shadow-lg": "0 0 28px rgba(255, 107, 0, 0.4), 0 10px 24px rgba(0,0,0,0.25)",
}
obj = "{" + ",".join(f'"{k}":"{v}"' for k, v in cyber.items()) + "}"

# Match known stock dark/light token objects by distinctive first colors
# Also match previous cyberpunk dark void + inverted neon so re-apply upgrades cleanly.
patterns = [
    # dark stock
    r'\{"--color-background-primary":"#22252a".*?"--shadow-lg":"[^"]*"\}',
    # light stock
    r'\{"--color-background-primary":"#ffffff".*?"--shadow-lg":"[^"]*"\}',
    # previous void cyberpunk
    r'\{"--color-background-primary":"#07070f".*?"--shadow-lg":"[^"]*"\}',
    # already inverted neon (this theme)
    r'\{"--color-background-primary":"#fff200".*?"--shadow-lg":"[^"]*"\}',
]

bubble_reps = [
    # stock dark
    (".dark .user-message-bubble{color:#d2dae6;background-color:#171d30}",
     ".dark .user-message-bubble{color:#0a0a0a;background-color:#ff2a2a;border:2px solid #0a0a0a;box-shadow:0 0 14px #ff2a2a88;font-weight:700}"),
    (".dark .agent-message-bubble{background-color:#1f2126;border-radius:.75rem;padding:.625rem 1rem}",
     ".dark .agent-message-bubble{background-color:#7df9ff;border:2px solid #0a0a0a;border-radius:.75rem;padding:.625rem 1rem;box-shadow:0 0 14px #00e5ff88;color:#0a0a0a;font-weight:700}"),
    # previous void cyberpunk bubbles → inverted
    (".dark .user-message-bubble{color:#ffb3ec;background-color:#2a0a24;border:1px solid #ff00aa88;box-shadow:0 0 12px #ff00aa44}",
     ".dark .user-message-bubble{color:#0a0a0a;background-color:#ff2a2a;border:2px solid #0a0a0a;box-shadow:0 0 14px #ff2a2a88;font-weight:700}"),
    (".dark .agent-message-bubble{background-color:#0a1a28;border:1px solid #00e5ff66;border-radius:.75rem;padding:.625rem 1rem;box-shadow:0 0 12px #00e5ff44;color:#c8f7ff}",
     ".dark .agent-message-bubble{background-color:#7df9ff;border:2px solid #0a0a0a;border-radius:.75rem;padding:.625rem 1rem;box-shadow:0 0 14px #00e5ff88;color:#0a0a0a;font-weight:700}"),
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
  log "SUCCESS: inverted neon cyberpunk theme applied (bright neon + bold black text). Restart Goose to see it."
  echo
  echo "Restart Goose completely (quit + reopen) to load the theme."
  echo "Backup: $BACKUP_DIR/app.asar.stock"
  echo "Restore: $ROOT/scripts/restore-theme.sh"
}

main "$@"
