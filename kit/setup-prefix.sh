#!/bin/bash
# Black Ops Mac: the Wine prefix the games run in, with Plutonium.
#
#   setup-prefix.sh create <game folder>    new prefix; installs Plutonium with
#                                           the game folder's plutonium.exe
#   setup-prefix.sh import <prefix>         copy an existing prefix (keeps the
#                                           Plutonium login and game settings)
#   setup-prefix.sh plutonium <game folder> (re)install Plutonium in the prefix
#
# Progress lines start with "==> "; errors with "ERROR: ".
set -uo pipefail
kit=$(cd -- "$(dirname -- "$0")" && pwd)
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
engine="$home/engine"
export WINEPREFIX="$home/prefix" CX_ROOT="$engine" WINESERVER="$engine/bin/wineserver"
export WINEDLLPATH="$engine/lib/wine/x86_64-windows:$engine/lib/wine/x86_64-unix"
# plutonium.exe (Plutonium's installer) is a .NET program: keep Wine Mono on
# here (launch.sh turns it off for the games and the launcher, which are not).
export WINEMSYNC=1 WINEDEBUG=-all WINEDLLOVERRIDES="mshtml="
wine="$engine/lib/wine/x86_64-unix/wine"
step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ -x "$wine" ] || die "install the engine first"
mkdir -p "$home/logs"

install_plutonium() {
  local game=$1
  [ -f "$game/plutonium.exe" ] || die "no plutonium.exe in $game (download it from plutonium.pw)"
  step "Installing Plutonium: sign in when its window opens, wait for the launcher, then close it"
  "$wine" "$game/plutonium.exe" > "$home/logs/plutonium-install.log" 2>&1
  "$WINESERVER" -w 2>/dev/null
  [ -f "$WINEPREFIX/drive_c/users/crossover/AppData/Local/Plutonium/bin/plutonium-launcher-win32.exe" ] ||
    die "Plutonium did not finish installing (see logs/plutonium-install.log)"
  step "Plutonium installed"
}

case "${1:-}" in
create)
  game=${2:-}
  [ -d "$game/zone" ] || die "pick the game folder (the one with zone/ and plutonium.exe)"
  if [ ! -f "$WINEPREFIX/system.reg" ]; then
    step "Creating the Wine prefix"
    "$wine" wineboot --init > "$home/logs/wineboot.log" 2>&1
    "$WINESERVER" -w 2>/dev/null
    [ -f "$WINEPREFIX/system.reg" ] || die "Wine could not create the prefix (see logs/wineboot.log)"
  fi
  install_plutonium "$game"
  ;;
import)
  src=${2:-}
  [ -f "$src/system.reg" ] && [ -d "$src/drive_c" ] || die "not a Wine prefix: $src"
  [ -e "$WINEPREFIX" ] && die "a prefix already exists in $WINEPREFIX"
  step "Copying the prefix (Plutonium login and game settings included)"
  cp -cR "$src" "$WINEPREFIX" 2>/dev/null || cp -R "$src" "$WINEPREFIX"
  step "Updating it for this engine"
  "$wine" wineboot -u > "$home/logs/wineboot.log" 2>&1
  "$WINESERVER" -w 2>/dev/null
  step "Prefix ready"
  ;;
plutonium)
  install_plutonium "${2:-}"
  ;;
*)
  die "usage: setup-prefix.sh create <game folder> | import <prefix> | plutonium <game folder>"
  ;;
esac
