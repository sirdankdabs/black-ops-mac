#!/bin/bash
# BO-Mac: Black Ops II's campaign (t6sp.exe) without Steam.
#
# Black Ops II's t6sp.exe is wrapped in Steam's DRM (SteamStub), so it refuses
# to start unless the Steam client is running. This prepares the game folder
# to start on its own:
#
#   1. Steamless (atom0s, bundled with the app) removes SteamStub from
#      t6sp.exe. The original is kept beside it as t6sp.exe.steam.
#   2. The game needs a Steam API replacement that works offline. Black Ops II
#      works with the "Redacted" steam_api.dll (the FIX REDACTED files): it is
#      used exactly as it is, never modified, downloaded or copied anywhere.
#   3. Redacted.ini is switched to offline mode (OfflineMode = 1) and
#      steam_appid.txt is set to the game's id (202970).
#
# No Windows Steam is installed and nothing signs in to Steam.
#
#   bo2-campaign.sh status [game folder]    engine=, patcher=, folder=,
#                                           packed=, emulator=, ready=
#   bo2-campaign.sh patch <game folder>     prepares the folder (idempotent)
#   bo2-campaign.sh check <game folder>     is it ready? (used by launch.sh)
#   bo2-campaign.sh restore <game folder>   puts the original t6sp.exe back
#
# Progress lines start with "==> "; errors with "ERROR: ".
set -uo pipefail
kit=$(cd -- "$(dirname -- "$0")" && pwd)
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
engine="$home/engine"
wine="$engine/lib/wine/x86_64-unix/wine"
wineserver="$engine/bin/wineserver"
payload="$kit/payload/steamless"
prefix="$home/prefix-bo2c"
step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# The game folder: the argument, or the one saved by the app.
folder_for() {
  local f=${1:-}
  if [ -z "$f" ] && [ -f "$home/settings.conf" ]; then
    f=$(sed -n 's/^BO2C_DIR=//p' "$home/settings.conf" | tail -1)
  fi
  printf '%s' "$f"
}

# A SteamStub-packed exe has a .bind section; the unpacked one does not.
packed() {
  [ -f "$1" ] || return 1
  /usr/bin/python3 -I - "$1" <<'PY'
import struct, sys
try:
    d = open(sys.argv[1], 'rb').read(0x2000)
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    n = struct.unpack_from('<H', d, pe + 6)[0]
    opt = struct.unpack_from('<H', d, pe + 20)[0]
    tbl = pe + 24 + opt
    for i in range(n):
        name = d[tbl + i * 40: tbl + i * 40 + 8].rstrip(b'\0').lower()
        if name == b'.bind':
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY
}

# The offline Steam API: Redacted's steam_api.dll (SteamBase). Valve's DLL,
# or a proxy that expects Steam, cannot start the game without Steam.
offline_api() {
  [ -f "$1" ] && LC_ALL=C grep -aq -e 'SteamBase' -e 'Redacted' "$1"
}

# The Redacted build that starts t6sp.exe offline (the FIX REDACTED
# steam_api.dll). Redacted repacks often keep the multiplayer/zombies build
# as steam_api.dll_zmp, which crashes the campaign, so only this build is
# used; a copy may sit in the folder as steam_api.dll.redacted or *_zm.
KNOWN_REDACTED=3dd088b88800f982b122b1d31fad2bb1c08a3035c4bfdcef4ce6f62c91f16292
known_redacted() {
  [ -f "$1" ] && [ "$(shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1)" = "$KNOWN_REDACTED" ]
}

redacted_source() {
  local f
  for f in steam_api.dll.redacted steam_api.dll_redacted steam_api.dll_zm steam_api.dll_zmp steam_api.dll; do
    [ -f "$1/$f" ] && known_redacted "$1/$f" && { printf '%s' "$1/$f"; return 0; }
  done
  return 1
}

# A Redacted repack t6sp.exe carries its own loader in a .conceal section;
# that loader crashes under Wine. The Steam exe (.bind, or already unpacked)
# is the one to use.
concealed() {
  [ -f "$1" ] || return 1
  /usr/bin/python3 -I - "$1" <<'PY'
import struct, sys
try:
    d = open(sys.argv[1], 'rb').read(0x2000)
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    n = struct.unpack_from('<H', d, pe + 6)[0]
    opt = struct.unpack_from('<H', d, pe + 20)[0]
    tbl = pe + 24 + opt
    for i in range(n):
        name = d[tbl + i * 40: tbl + i * 40 + 8].rstrip(b'\0').lower()
        if name == b'.conceal':
            sys.exit(0)
except Exception:
    pass
sys.exit(0 if False else 1)
PY
}

# Unpack in a small Wine prefix of its own (Wine Mono runs Steamless); the
# campaign's prefix and the Plutonium prefix are never touched.
run_steamless() {
  local src=$1
  [ -f "$payload/Steamless.CLI.exe" ] || die "the DRM remover is missing from the app"
  mkdir -p "$home/campaign" "$home/logs"
  if [ ! -f "$home/campaign/steamless-prefix" ]; then
    WINEPREFIX="$home/prefix-steamless" WINEDEBUG=-all WINEDLLOVERRIDES="" \
      "$wine" wineboot --init >> "$home/logs/bo2c-drm.log" 2>&1
    WINEPREFIX="$home/prefix-steamless" "$wineserver" -w 2>/dev/null
    : > "$home/campaign/steamless-prefix"
  fi
  ( cd "$payload" && WINEPREFIX="$home/prefix-steamless" WINEDEBUG=-all \
      "$wine" "$payload/Steamless.CLI.exe" --quiet "$src" >> "$home/logs/bo2c-drm.log" 2>&1 )
}

case "${1:-}" in
status)
  game=$(folder_for "${2:-}")
  printf 'engine=%s\n' "$([ -x "$wine" ] && echo yes || echo no)"
  printf 'patcher=%s\n' "$([ -f "$payload/Steamless.CLI.exe" ] && echo yes || echo no)"
  printf 'folder=%s\n' "$game"
  if [ -z "$game" ] || [ ! -f "$game/t6sp.exe" ]; then
    printf 'packed=missing\nemulator=no\nready=no\n'
    exit 0
  fi
  if packed "$game/t6sp.exe"; then printf 'packed=yes\n'; else printf 'packed=no\n'; fi
  if known_redacted "$game/steam_api.dll" || redacted_source "$game" >/dev/null; then
    printf 'emulator=yes\n'
  else
    printf 'emulator=no\n'
  fi
  if ! packed "$game/t6sp.exe" && offline_api "$game/steam_api.dll" && [ -f "$game/Redacted.ini" ] && [ ! -d "$game/Plugins" ]; then
    printf 'ready=yes\n'
  else
    printf 'ready=no\n'
  fi
  ;;
patch)
  game=$(folder_for "${2:-}")
  [ -n "$game" ] || die "no game folder: choose it in BO-Mac first"
  [ -d "$game/zone" ] || die "that folder has no zone folder: pick the Black Ops II game folder"
  [ -f "$game/t6sp.exe" ] || die "no t6sp.exe in the game folder"
  [ -x "$wine" ] || die "install the BO-Mac engine first"
  concealed "$game/t6sp.exe" &&
    die "this t6sp.exe has a repack loader that crashes on Mac: put your Steam copy's t6sp.exe in the folder and press Prepare again"
  # A Redacted repack has the emulator in the folder under another name; use
  # the FIX REDACTED build when it is there.
  if ! known_redacted "$game/steam_api.dll"; then
    src=$(redacted_source "$game") || src=""
    if [ -n "$src" ] && [ "$src" != "$game/steam_api.dll" ]; then
      step "Using the game's offline steam_api.dll"
      [ -f "$game/steam_api.dll.bom-backup" ] || cp -p "$game/steam_api.dll" "$game/steam_api.dll.bom-backup" 2>/dev/null || true
      cp -p "$src" "$game/steam_api.dll"
    fi
  fi
  known_redacted "$game/steam_api.dll" ||
    die "the campaign needs the offline steam_api.dll: put it next to t6sp.exe, then press Prepare again (the repack's steam_api.dll_zmp is the multiplayer build and crashes t6sp.exe)"
  mkdir -p "$home/campaign" "$home/logs"

  # Redacted's plugins (OpenNet, ZonePlugin) are made for multiplayer, and
  # they panic when they load into t6sp.exe: set them aside for the campaign.
  if [ -d "$game/Plugins" ]; then
    step "Setting the repack's plugins aside for the campaign"
    mkdir -p "$game/Plugins.campaign-off"
    for f in "$game/Plugins"/*; do [ -e "$f" ] && mv "$f" "$game/Plugins.campaign-off/"; done
    rmdir "$game/Plugins" 2>/dev/null
  fi

  # The campaign's own Wine prefix (nothing of Steam goes in it).
  if [ ! -f "$prefix/system.reg" ]; then
    step "Creating the campaign's Wine prefix"
    WINEPREFIX="$prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
      "$wine" wineboot --init > "$home/logs/bo2c-wineboot.log" 2>&1
    WINEPREFIX="$prefix" "$wineserver" -w 2>/dev/null
  fi

  if packed "$game/t6sp.exe"; then
    step "Removing Steam's DRM from t6sp.exe"
    [ -f "$game/t6sp.exe.steam" ] || cp -p "$game/t6sp.exe" "$game/t6sp.exe.steam"
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/bom-campaign.XXXXXX") || die "cannot create a temporary folder"
    cp -p "$game/t6sp.exe" "$tmp/t6sp.exe"
    run_steamless "$tmp/t6sp.exe"
    [ -f "$tmp/t6sp.exe.unpacked.exe" ] ||
      die "the DRM removal did not produce an unpacked t6sp.exe (see logs/bo2c-drm.log)"
    packed "$tmp/t6sp.exe.unpacked.exe" && die "could not remove SteamStub from this t6sp.exe"
    [ "$(wc -c < "$tmp/t6sp.exe.unpacked.exe")" -gt 5000000 ] || die "the unpacked t6sp.exe is too small"
    cp -p "$tmp/t6sp.exe.unpacked.exe" "$game/t6sp.exe" || die "cannot replace t6sp.exe"
    chmod +x "$game/t6sp.exe"
    rm -rf "$tmp"
  else
    step "t6sp.exe is already Steam-free"
  fi

  # The Steam API replacement and the game id (Redacted reads both).
  printf '202970' > "$game/steam_appid.txt"
  /usr/bin/python3 -I - "$game/Redacted.ini" "${PLAYER_NAME:-Player}" <<'PY'
import re, sys
path, name = sys.argv[1], sys.argv[2]
try:
    s = open(path, encoding='utf-8', errors='replace').read()
except FileNotFoundError:
    s = ''
if not s.strip():
    s = ('[Steam]\nUsername = "%s"\nLanguage = "english"\n\n'
         '[System]\nOfflineMode = 1;\nDedicatedMode = 0;\n\n'
         '[Master]\nHostIP = "127.0.0.1"\nUsername = "STEAMRIP"\nPassword =\n\n'
         '[Plugins]\nAllowUnofficial = 1\n') % name
else:
    if re.search(r'(?im)^\s*OfflineMode\s*=', s):
        s = re.sub(r'(?im)^(\s*OfflineMode\s*=\s*)\d+', r'\g<1>1', s, count=1)
    elif re.search(r'(?m)^\[System\]', s):
        s = re.sub(r'(?m)^\[System\]', '[System]\nOfflineMode = 1;', s, count=1)
    else:
        s += '\n[System]\nOfflineMode = 1;\n'
open(path, 'w', encoding='utf-8').write(s)
PY
  step "Ready: Play Campaign starts t6sp.exe without Steam"
  ;;
check)
  game=$(folder_for "${2:-}")
  [ -x "$wine" ] || die "the engine is not installed"
  [ -n "$game" ] && [ -f "$game/t6sp.exe" ] || die "the campaign game folder is not set (or has no t6sp.exe)"
  packed "$game/t6sp.exe" &&
    die "the campaign is not prepared: in BO-Mac choose the game folder and press Prepare (no Steam)"
  known_redacted "$game/steam_api.dll" ||
    die "the campaign needs the offline steam_api.dll: press Prepare in BO-Mac (it uses the copy in the folder when there is one)"
  if [ -d "$game/Plugins" ]; then
    die "the repack's Plugins folder makes t6sp.exe crash: press Prepare in BO-Mac (it sets the plugins aside)"
  fi
  ;;
restore)
  game=$(folder_for "${2:-}")
  [ -n "$game" ] || die "no game folder"
  if [ -f "$game/t6sp.exe.steam" ]; then
    step "Putting the original t6sp.exe back"
    mv -f "$game/t6sp.exe.steam" "$game/t6sp.exe"
  fi
  if [ -f "$game/steam_appid.txt" ] && [ "$(cat "$game/steam_appid.txt")" = 202970 ]; then
    rm -f "$game/steam_appid.txt"
  fi
  if [ -d "$game/Plugins.campaign-off" ] && [ ! -d "$game/Plugins" ]; then
    mv "$game/Plugins.campaign-off" "$game/Plugins"
  fi
  step "Restored the original t6sp.exe"
  ;;
*)
  die "usage: bo2-campaign.sh status [game folder] | patch <game folder> | check <game folder> | restore <game folder>"
  ;;
esac
