#!/bin/bash
# BO-Mac: Black Ops II's campaign (t6sp.exe) from your Steam copy. Plutonium
# has no campaign, and the game's Steam DRM needs the Steam client: it runs
# in its own Wine prefix (prefix-bo2c) with Windows Steam, signed in to your
# account, so nothing here touches the other games' prefix.
#
#   bo2-campaign.sh status   steam=installed|missing  signedin=yes|no
#   bo2-campaign.sh setup    creates prefix-bo2c and installs Windows Steam
#                            (Valve's installer), then opens it to sign in
#   bo2-campaign.sh steam [-silent]   opens Windows Steam (to sign in), or
#                            starts it in the background
#   bo2-campaign.sh wait     waits (up to 2 minutes) until Steam is signed in
#   bo2-campaign.sh library <game folder>   points Windows Steam at the game,
#                            wherever its folder is
#
# Progress lines start with "==> "; errors with "ERROR: ".
set -uo pipefail
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
engine="$home/engine"
export WINEPREFIX="$home/prefix-bo2c" WINEMSYNC=1 WINEDEBUG=${WINEDEBUG:--all}
# Steam stays open in the background: its Wine server runs through a link
# outside the engine folder, so the app doesn't count it as a game running
mkdir -p "$home/campaign"
ln -sfn "$engine/bin/wineserver" "$home/campaign/wineserver"
export WINESERVER="$home/campaign/wineserver"
wine="$engine/lib/wine/x86_64-unix/wine"
steamdir="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
downloads="$home/downloads"
step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# signed in now: Steam's latest connection state is "Logged On"
signed_in() {
  grep -oE '^\[[^]]+\] \[[A-Za-z ]+,' "$steamdir/logs/connection_log.txt" 2>/dev/null | tail -1 | grep -q 'Logged On'
}
running() { pgrep -f 'Steam\\Steam.exe|Program Files \(x86\)\\Steam\\steam.exe' >/dev/null 2>&1; }

# Steam's web windows draw nothing with GPU rendering or the sandbox under Wine.
start_steam() {
  # Steam's in-game overlay is off: it is injected into the game when Steam
  # starts it, and its rendering does not work under Wine (Steam may restore
  # these files when it updates itself, so this runs every time)
  for f in GameOverlayRenderer.dll GameOverlayRenderer64.dll; do
    [ -f "$steamdir/$f" ] && mv -f "$steamdir/$f" "$steamdir/$f.off"
  done
  running && return 0
  (cd "$steamdir" && nohup "$wine" Steam.exe "$@" -cef-disable-gpu -cef-disable-gpu-compositing \
    -cef-disable-sandbox > "$home/logs/bo2-campaign-steam.log" 2>&1 &)
}

case "${1:-}" in
status)
  [ -f "$steamdir/Steam.exe" ] && echo "steam=installed" || echo "steam=missing"
  grep -q '"RememberPassword"[[:space:]]*"1"' "$steamdir/config/loginusers.vdf" 2>/dev/null && echo "signedin=yes" || echo "signedin=no"
  running && echo "running=yes" || echo "running=no"
  signed_in && echo "online=yes" || echo "online=no"
  ;;
setup)
  [ -x "$wine" ] || die "install the BO-Mac engine first"
  mkdir -p "$downloads" "$home/logs"
  if [ ! -f "$WINEPREFIX/system.reg" ]; then
    step "Creating the campaign's own Wine prefix"
    WINEDLLOVERRIDES="mscoree,mshtml=" "$wine" wineboot --init > "$home/logs/bo2-campaign-wineboot.log" 2>&1
    "$WINESERVER" -w
  fi
  step "Downloading Steam for Windows (Valve)"
  curl -fsSL --retry 3 -o "$downloads/SteamSetup.exe" https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe ||
    die "cannot download Steam"
  strings -a "$downloads/SteamSetup.exe" | grep -q "Valve Corp" || die "unexpected Steam installer"
  step "Installing Steam for Windows"
  "$wine" "$downloads/SteamSetup.exe" /S > /dev/null 2>&1
  "$WINESERVER" -w
  [ -f "$steamdir/Steam.exe" ] || die "Steam did not install"
  step "Opening Steam: sign in to your account (the window may stay black: click it, type your user name, Tab, password, Enter)"
  start_steam
  ;;
steam)
  [ -f "$steamdir/Steam.exe" ] || die "Steam is not installed"
  shift; start_steam "$@"
  ;;
show)
  # Steam's window, to sign in: a background Steam that never signed in has
  # no window, so restart it in front
  [ -f "$steamdir/Steam.exe" ] || die "Steam is not installed"
  running && { "$WINESERVER" -k; sleep 2; }
  start_steam
  ;;
wait)
  for _ in $(seq 1 150); do signed_in && exit 0; sleep 2; done
  die "Steam did not sign in: sign in in Steam's window, then press Play Campaign again"
  ;;
library)
  # Steam's DRM only starts a game that sits in one of Steam's libraries.
  # BO-Mac keeps one inside the campaign's prefix ("C:\BO-Mac Library"),
  # whose game folder is a link to yours, wherever it is.
  game=${2:-}
  [ -f "$game/t6sp.exe" ] || die "no t6sp.exe in the game folder"
  vdf="$steamdir/steamapps/libraryfolders.vdf"
  # a new Steam writes its library list later: start it with Steam's own folder
  if [ ! -f "$vdf" ]; then
    mkdir -p "$(dirname "$vdf")"
    printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"\n\t\t"label"\t\t""\n\t\t"contentid"\t\t"0"\n\t\t"totalsize"\t\t"0"\n\t\t"apps"\n\t\t{\n\t\t}\n\t}\n}\n' > "$vdf"
  fi
  bomlib="$WINEPREFIX/drive_c/BO-Mac Library/steamapps"
  mkdir -p "$bomlib/common"
  ln -sfn "$game" "$bomlib/common/Call of Duty Black Ops II"
  # the game's manifest: the one of the Steam library it came from (the Mac
  # Steam app's, a Windows Steam's), so Steam sees the same build; otherwise
  # one for the current build
  src="$game/../../appmanifest_202970.acf"
  if [ -f "$src" ]; then
    sed -E 's/("installdir"[[:space:]]*)"[^"]*"/\1"Call of Duty Black Ops II"/' "$src" > "$bomlib/appmanifest_202970.acf"
  elif [ ! -f "$bomlib/appmanifest_202970.acf" ]; then
    cat > "$bomlib/appmanifest_202970.acf" <<'ACF'
"AppState"
{
	"appid"		"202970"
	"Universe"		"1"
	"name"		"Call of Duty: Black Ops II"
	"StateFlags"		"4"
	"installdir"		"Call of Duty Black Ops II"
	"LastUpdated"		"1794544466"
	"SizeOnDisk"		"12759123336"
	"buildid"		"24784288"
	"AutoUpdateBehavior"		"0"
	"AllowOtherDownloadsWhileRunning"		"0"
	"ScheduledAutoUpdate"		"0"
}
ACF
  fi
  grep -qF 'C:\\BO-Mac Library' "$vdf" && exit 0
  running && { "$WINESERVER" -k; sleep 2; }
  /usr/bin/python3 -I - "$vdf" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read().rstrip()
n = max([int(x) for x in re.findall(r'^\t"(\d+)"\s*$', s, re.M)] or [0]) + 1
entry = ('\t"%d"\n\t{\n\t\t"path"\t\t"C:\\\\BO-Mac Library"\n\t\t"label"\t\t""\n\t\t"contentid"\t\t"0"\n'
         '\t\t"totalsize"\t\t"0"\n\t\t"apps"\n\t\t{\n\t\t\t"202970"\t\t"0"\n\t\t}\n\t}\n') % n
open(p, "w").write(s[:-1] + entry + "}\n")
PY
  step "Steam library added"
  ;;
*)
  die "usage: bo2-campaign.sh status | setup | steam | library <game folder>"
  ;;
esac
