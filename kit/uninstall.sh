#!/bin/bash
# Black Ops Mac: remove a game's setup so it can be set up again from scratch.
# Everything removed goes to the Trash (nothing is deleted for good), and the
# games themselves are never touched.
#
#   uninstall.sh bo1    forget the Black Ops folder; its shader caches go
#   uninstall.sh bo2    forget the Black Ops II folder
#   uninstall.sh all    the engine, the Wine prefix (Plutonium and its login),
#                       caches, logs and settings: Black Ops and Black Ops II
#                       both start from the beginning (Black Ops III untouched)
#   uninstall.sh bo3    BO3 Mac Client: Steam's launcher goes back into the
#                       game, BO3MacFix and the server browser go; the identity
#                       key is kept for the next install
#
# Progress lines start with "==> "; errors with "ERROR: ".
set -uo pipefail
kit=$(cd -- "$(dirname -- "$0")" && pwd)
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Move to the Trash under a unique name.
trash() {
  local p=$1 name
  [ -e "$p" ] || return 0
  name="$(basename "$p") (Black Ops Mac $(date '+%Y-%m-%d %H.%M.%S'))"
  mkdir -p "$HOME/.Trash"
  mv "$p" "$HOME/.Trash/$name" || die "cannot move $p to the Trash"
}
forget() {  # remove settings.conf lines
  local k
  [ -f "$home/settings.conf" ] || return 0
  for k in "$@"; do sed -i '' "/^$k=/d" "$home/settings.conf"; done
}
stop_games() { [ -x "$kit/launch.sh" ] && bash "$kit/launch.sh" stop >/dev/null 2>&1; true; }

case "${1:-}" in
bo1)
  stop_games
  step "Removing the Black Ops setup"
  forget BO1_DIR
  trash "$home/cache/plutonium-bootstrapper-win32.dxvk-cache"
  for f in "$home"/engine/lib64/mvkcache.bin.*; do trash "$f"; done
  step "Black Ops can be set up again"
  ;;
bo2)
  stop_games
  step "Removing the Black Ops II setup"
  forget BO2_DIR BO2_MODS
  step "Black Ops II can be set up again"
  ;;
all)
  stop_games
  step "Removing the engine, Plutonium and settings"
  for d in engine prefix cache logs downloads; do trash "$home/$d"; done
  # BO3's choice stays with BO3
  if [ -f "$home/settings.conf" ]; then
    grep '^BO3_' "$home/settings.conf" > "$home/settings.keep" || true
    trash "$home/settings.conf"
    if [ -s "$home/settings.keep" ]; then mv "$home/settings.keep" "$home/settings.conf"; else rm -f "$home/settings.keep"; fi
  fi
  step "Black Ops and Black Ops II can be set up again"
  ;;
bo3)
  pgrep -f CoDBlkOps3_Exe >/dev/null && die "quit Black Ops III first"
  osascript -e 'quit app id "io.github.bo3macclient"' >/dev/null 2>&1
  g=$(bash "$kit/bo3.sh" status 2>/dev/null | sed -n 's/^game=//p')
  step "Removing BO3 Mac Client"
  if [ -n "$g" ] && [ -d "$g/BO3MacFix" ]; then
    # keep the identity key (rank and VIP on community servers): the
    # installer restores identity-key-*.dat from bo3/Personal
    if [ -f "$g/BO3MacFix/boiii_key.dat" ]; then
      mkdir -p "$home/bo3/Personal"
      cp -p "$g/BO3MacFix/boiii_key.dat" "$home/bo3/Personal/identity-key-saved.dat"
      step "Identity key kept in $home/bo3/Personal"
    fi
    m="$g/CoDBlkOps3.app/Contents/MacOS"
    if [ -f "$m/AppBundleExe_backup" ]; then
      mv -f "$m/AppBundleExe_backup" "$m/AppBundleExe" || die "cannot restore Steam's launcher"
      step "Steam's launcher is back in the game"
    fi
    trash "$g/BO3MacFix"
  fi
  trash "$home/bo3/T7 Server Browser.app"
  rm -f "$home/bo3/version"
  step "BO3 Mac Client removed"
  ;;
*)
  die "usage: uninstall.sh bo1 | bo2 | all | bo3"
  ;;
esac
