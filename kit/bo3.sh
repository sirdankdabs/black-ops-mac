#!/bin/bash
# Black Ops Mac: Black Ops III on the community servers, through BO3 Mac Client
# (bundled in kit/payload/bo3, source in bo3/), installed as it is:
#  - BO3MacFix goes into the Steam game (CoDBlkOps3.app), the same way the
#    project's own installer does it;
#  - its server browser app is kept inside Black Ops Mac's folder as
#    "T7 Server Browser.app" and opened from the Black Ops Mac app.
#
#   bo3.sh status     game=<folder>, state=ready|downloading|missing, installed=<version>, latest=<version>
#   bo3.sh install    install the bundled version (then opens the browser)
#   bo3.sh open       open the server browser
#   bo3.sh steam      start Black Ops III from Steam (official servers)
#   bo3.sh spoof on|off   BO3MacFix's ranked spoofing (off unless chosen:
#                     ban risk). Kept in settings.conf as BO3_SPOOF_RANKED.
#
# Progress lines start with "==> "; errors with "ERROR: ".
set -uo pipefail
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
dir="$home/bo3"
app="$dir/T7 Server Browser.app"
steam="$HOME/Library/Application Support/Steam"
step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# BO3MACFIX_SPOOF_RANKED in the game's bo3macfix.conf: on, or commented out.
set_spoof() {
  local conf="$1/BO3MacFix/bo3macfix.conf" v=$2
  [ -f "$conf" ] || return 0
  sed -i '' -E '/^#?[[:space:]]*BO3MACFIX_SPOOF_RANKED=/d' "$conf"
  if [ "$v" = 1 ]; then echo "BO3MACFIX_SPOOF_RANKED=1" >> "$conf"
  else echo "#BO3MACFIX_SPOOF_RANKED=1" >> "$conf"; fi
}
saved_spoof() { sed -n 's/^BO3_SPOOF_RANKED=//p' "$home/settings.conf" 2>/dev/null | tail -1; }
save_spoof() {
  mkdir -p "$home"; touch "$home/settings.conf"
  sed -i '' '/^BO3_SPOOF_RANKED=/d' "$home/settings.conf"
  echo "BO3_SPOOF_RANKED=$1" >> "$home/settings.conf"
}

kit=$(cd -- "$(dirname -- "$0")" && pwd)
bundle="$kit/payload/bo3"
latest() { cat "$bundle/VERSION" 2>/dev/null; }

# The Steam library that has Black Ops III (installed or downloading).
game_dir() {
  local lib
  while IFS= read -r lib; do
    [ -f "$lib/steamapps/appmanifest_311210.acf" ] || continue
    echo "$lib/steamapps/common/Call of Duty Black Ops III"; return
  done < <({ echo "$steam"; grep '"path"' "$steam/steamapps/libraryfolders.vdf" 2>/dev/null | awk -F'"' '{print $4}'; })
}
game_state() {
  local g=$1
  if [ -x "$g/CoDBlkOps3.app/Contents/MacOS/CoDBlkOps3_Exe" ]; then echo ready
  elif [ -n "$g" ]; then echo downloading
  else echo missing; fi
}

case "${1:-}" in
status)
  g=$(game_dir)
  echo "game=$g"
  echo "state=$(game_state "$g")"
  if [ -d "$app" ] && [ -f "$g/BO3MacFix/BO3MacFix.dylib" ]; then echo "installed=$(cat "$dir/version" 2>/dev/null)"; else echo "installed="; fi
  grep -q '^BO3MACFIX_SPOOF_RANKED=1' "$g/BO3MacFix/bo3macfix.conf" 2>/dev/null && echo "spoof=1" || echo "spoof=0"
  echo "latest=$(latest)"
  ;;
install)
  [ -d /Applications/Steam.app ] || die "install Steam first (store.steampowered.com)"
  g=$(game_dir)
  case $(game_state "$g") in
    missing) die "Black Ops III is not in your Steam library: install it in Steam first" ;;
    downloading) die "Black Ops III is still downloading in Steam: install BO3 Mac Client when it finishes" ;;
  esac
  mkdir -p "$dir"
  sha=$(latest)
  [ -f "$bundle/Install BO3 Mac Client.command" ] || die "BO3 Mac Client is missing from Black Ops Mac"
  step "Preparing BO3 Mac Client ($sha)"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  src="$tmp/src"
  ditto "$bundle" "$src"
  step "Checking BO3MacFix"
  (cd "$src/1 - Install/BO3MacFix" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1) || die "BO3MacFix files do not match their checksums"
  # the user's private folder (identity key, settings), kept across updates
  if [ -d "$dir/Personal" ]; then cp -R "$dir/Personal" "$src/3 - Personal (keep private)"; fi
  step "Installing BO3MacFix into the game and the server browser"
  # The project's installer, unchanged: app into $APPS, BO3MacFix into the
  # game ("Install BO3MacFix?" yes), saved settings restore ("no": only on request).
  mkdir -p "$tmp/apps"
  printf 'y\nn\n' | APPS="$tmp/apps" NO_OPEN=1 bash "$src/Install BO3 Mac Client.command" > "$tmp/install.log" 2>&1
  cat "$tmp/install.log"
  [ -d "$tmp/apps/BO3 Mac Client.app" ] || die "the installer did not install the app"
  cmp -s "$src/1 - Install/BO3MacFix/BO3MacFix.dylib" "$g/BO3MacFix/BO3MacFix.dylib" &&
    [ -f "$g/CoDBlkOps3.app/Contents/MacOS/AppBundleExe_backup" ] || die "BO3MacFix was not installed into the game"
  # Our name for it; same app otherwise.
  osascript -e 'quit app id "io.github.bo3macclient"' >/dev/null 2>&1
  rm -rf "$app"
  mv "$tmp/apps/BO3 Mac Client.app" "$app"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName T7 Server Browser" -c "Set :CFBundleDisplayName T7 Server Browser" "$app/Contents/Info.plist"
  codesign -fs - --deep "$app" 2>/dev/null
  xattr -dr com.apple.quarantine "$app" 2>/dev/null
  # The project's bo3macfix.conf turns ranked spoofing on; here it is the
  # user's choice (off unless they turned it on).
  set_spoof "$g" "$(saved_spoof)"
  # Holding a movement key would open macOS's accent menu: off for the game only.
  defaults write com.aspyr.codblkops3.steam ApplePressAndHoldEnabled -bool false 2>/dev/null
  echo "$sha" > "$dir/version"
  step "Installed ($sha)"
  [ -n "${NO_OPEN:-}" ] || open "$app"
  ;;
open)
  [ -d "$app" ] || die "the server browser is not installed"
  open "$app"
  ;;
spoof)
  case "${2:-}" in on) v=1 ;; off) v=0 ;; *) die "usage: bo3.sh spoof on|off" ;; esac
  save_spoof $v
  g=$(game_dir)
  set_spoof "$g" $v
  step "Ranked spoofing $2"
  ;;
steam)
  open "steam://rungameid/311210"
  ;;
*)
  die "usage: bo3.sh status | install | open | steam | spoof on|off"
  ;;
esac
