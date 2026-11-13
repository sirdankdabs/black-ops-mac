#!/bin/bash
# BO-Mac: start World at War (t4), Black Ops (t5) or Black Ops II (t6) through Plutonium on
# the BO-Mac engine (install-engine.sh) in its prefix (setup-prefix.sh).
#
#   launch.sh bo1|bo2 online              Plutonium launcher (sign in, play online)
#   launch.sh bo1 zombies|campaign|mp [name]   offline (LAN)
#   launch.sh bo2 zombies|mp [name]            offline (LAN)
#   launch.sh bo2 declassified [name]          offline Zombies with the Zombies
#                                         Declassified mod (zombies-declassified.sh)
#   launch.sh stop                         stop everything
#
# Settings come from $BOM_HOME/settings.conf (NAME=value lines; the
# environment wins):
#   BO1_DIR, BO2_DIR   game folders
#   MAXFPS             frame-rate cap (default: the display's refresh rate; 0: none)
#   X87=0              no x87 acceleration
#   AIM_ACCEL=1        keep the games' stick turn acceleration (default: off)
#   STICK_DEADZONE     stick deadzone (default 0.08)
#   RAW_INPUT=0        keep the games' raw_input (default: on)
#   STREAM=1           keep BO1's texture streaming (default: off)
#   Patches (on unless set to the value shown):
#   EXEC_ON_DEMAND=0   DEP-off code made executable all at once (BO2 slow motion)
#   RUMBLE_FIX=0       CrossOver's xinput (vibration stalls controller input)
#   CAPTURE_DISPLAY=0  fullscreen through the window compositor
#   DISPLAY_MODE=0     keep the desktop's display mode while in fullscreen
#   MSAA_FIX=0         allow the games' 8x+ MSAA (not supported by Apple GPUs)
#   BO1_ASYNC=0        BO1 shaders compile while drawing (stutters)
#   BO1_WARM=0         BO1 shaders compile during play instead of on the loading screen
#   BO1_SHADER_CACHE=0 BO1 keeps no shader caches between runs
#   BO1_METAL_PARALLEL=0  Metal compiles a few shaders at a time
#   BO1_NO_SHADOWS=0   BO1 shadow setting left to the game
#   BO1_XAUDIO=0       Wine's XAudio2 (BO1 gunfire is silent)
#   BO1_VIDMEM=0       BO1 sees 128 MB of video memory (low-res textures)
#   BO2_ASYNC=0        BO2 shaders compile while drawing
#   BO2_FRAME_PACING=0 no DXMT frame pacing at the frame-rate cap
#   BO2_HW_PROFILE=0   BO2 keeps its own hardware profile
#   BO2_MODS="..."     extra arguments for BO2 offline, e.g. "+set fs_game mods/dlc5"
#   GAME_ARGS="..."    extra game arguments (offline modes)
set -uo pipefail
kit=$(cd -- "$(dirname -- "$0")" && pwd)
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
if [ -f "$home/settings.conf" ]; then
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue ;; esac
    k=${k//[[:space:]]/}; v=${v%%#*}; v=${v%"${v##*[![:space:]]}"}
    [[ "$k" =~ ^[A-Z_][A-Z0-9_]*$ ]] && [ -z "${!k+x}" ] && export "$k=$v"
  done < "$home/settings.conf"
fi
engine="$home/engine"
export WINEPREFIX="$home/prefix" CX_ROOT="$engine" WINESERVER="$engine/bin/wineserver"
# Black Ops II's campaign has its own prefix, with Windows Steam (bo2-campaign.sh)
if [ "${1:-}" = bo2c ]; then
  export WINEPREFIX="$home/prefix-bo2c"
  # its Steam stays open: its Wine server runs through a link outside the
  # engine folder, so the app doesn't count it as a game running
  mkdir -p "$home/campaign"; ln -sfn "$engine/bin/wineserver" "$home/campaign/wineserver"
  export WINESERVER="$home/campaign/wineserver"
fi
export WINEDLLPATH="$engine/lib/wine/x86_64-windows:$engine/lib/wine/x86_64-unix"
export WINEMSYNC=1 WINEDEBUG=${WINEDEBUG:--all} WINEDLLOVERRIDES="mscoree,mshtml="
wine="$engine/lib/wine/x86_64-unix/wine"
plutonium="$WINEPREFIX/drive_c/users/crossover/AppData/Local/Plutonium"
mkdir -p "$home/logs" "$home/cache"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
stop_all() { "$WINESERVER" -k 2>/dev/null; "$WINESERVER" -w 2>/dev/null; }

game=${1:-}; mode=${2:-}
[ "$game" = stop ] && { stop_all; WINEPREFIX="$home/prefix-bo2c" "$WINESERVER" -k 2>/dev/null; exit 0; }
[ -x "$wine" ] || die "the engine is not installed"
[ -d "$WINEPREFIX/drive_c" ] || die "the Wine prefix is not set up"
case "$game:$mode" in
  waw:online|waw:zombies|waw:campaign|waw:mp) dir=${WAW_DIR:-} t=t4 ;;
  bo1:online|bo1:zombies|bo1:campaign|bo1:mp) dir=${BO1_DIR:-} t=t5 ;;
  bo2:online|bo2:zombies|bo2:mp|bo2:declassified) dir=${BO2_DIR:-} t=t6 ;;
  boiii:play) dir=${BOIII_DIR:-} t=t7 GAME_ARGS=${GAME_ARGS---launch} ;;
  boiii:launcher) dir=${BOIII_DIR:-} t=t7 ;;
  bo2c:play) dir=${BO2C_DIR:-} t=t6c ;;
  *) die "usage: launch.sh waw|bo1|bo2 online|zombies|campaign|mp [name], launch.sh boiii play|launcher, or launch.sh stop" ;;
esac
if [ "$t" = t7 ]; then
  [ -n "$dir" ] && [ -f "$dir/boiii.exe" ] || die "the Black Ops III (Windows) folder is not set (or has no boiii.exe)"
else
  [ -n "$dir" ] && [ -d "$dir/zone" ] || die "the $game game folder is not set (or has no zone folder)"
  [ "$t" != t6c ] || [ -f "$dir/t6sp.exe" ] || die "the Black Ops II campaign folder has no t6sp.exe"
fi
[ "$t" = t6c ] || stop_all   # the campaign keeps its Steam signed in

# --- Environment for the games ---------------------------------------------
# Plutonium starts the games with an environment built from HKCU\Environment.
reg() { "$wine" reg "$@" > /dev/null 2>&1 || true; }
set_env() { export "$1=$2"; reg add 'HKCU\Environment' /v "$1" /d "$2" /f; }
clear_env() { unset "$1"; reg delete 'HKCU\Environment' /v "$1" /f; }

read -r dw dh hz < <("$kit/tools/displaymode" current 2>/dev/null || true)
maxfps=${MAXFPS:-${hz:-0}}
if [ "${X87:-1}" = 1 ] && [ -x "$engine/bin/x87sidecar" ]; then
  set_env X87_SIDECAR_PATH "$engine/bin/x87sidecar"
  if [ "$t" = t6c ]; then set_env X87_SIDECAR_PROGRAMS t6sp.exe; else set_env X87_SIDECAR_PROGRAMS plutonium-bootstrapper-win32.exe; fi
else
  clear_env X87_SIDECAR_PATH; clear_env X87_SIDECAR_PROGRAMS
fi
on() { [ "${!1:-1}" != 0 ]; }   # a patch is on unless set to 0
if on EXEC_ON_DEMAND; then clear_env BO_EXEC_ON_DEMAND; else set_env BO_EXEC_ON_DEMAND 0; fi
xi="$engine/lib/wine/i386-windows"
if on RUMBLE_FIX; then xsrc="$xi/xinput1_3.bom.dll"; else xsrc="$xi/xinput1_3.cx.dll"; fi
[ -f "$xsrc" ] && ! cmp -s "$xsrc" "$xi/xinput1_3.dll" && cp "$xsrc" "$xi/xinput1_3.dll"
wb="$engine/lib/wine/x86_64-windows"
if on RUMBLE_FIX; then wsrc="$wb/winebus.bom.sys"; else wsrc="$wb/winebus.cx.sys"; fi
[ -f "$wsrc" ] && ! cmp -s "$wsrc" "$wb/winebus.sys" && cp "$wsrc" "$wb/winebus.sys"
# Black Ops 1 (DXVK): background pipeline compilation and a persistent
# pipeline list; MoltenVK's translated shaders are kept by the engine's shim.
# Our DXVK also compiles in the background during BO1's one-frame shader
# warming pass (it reads the game's warming flag), so warming only queues.
if on BO1_ASYNC; then set_env DXVK_ASYNC 1; clear_env DXVK_WARM_ASYNC; else set_env DXVK_ASYNC 0; set_env DXVK_WARM_ASYNC 0; fi
if on BO1_WARM; then clear_env DXVK_WARM_WAIT; else set_env DXVK_WARM_WAIT 0; fi
# Let Metal compile on every core at once (by default macOS runs only a few
# shader compilations at a time, and BO1's first shader warming took minutes),
# and skip MoltenVK's timing of every call.
if on BO1_METAL_PARALLEL; then set_env MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION 1
else clear_env MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION; fi
set_env MVK_CONFIG_PERFORMANCE_TRACKING 0
set_env DXVK_STATE_CACHE_PATH "Z:${home//\//\\}\\cache"
if on BO1_SHADER_CACHE; then clear_env MVKCACHE_OFF; clear_env DXVK_STATE_CACHE
else set_env MVKCACHE_OFF 1; set_env DXVK_STATE_CACHE 0; fi
# Black Ops II (DXMT): background pipeline compilation, frame pacing.
if on BO2_ASYNC; then dxmt="d3d11.asyncPipelineCompile=True;"; else dxmt="d3d11.asyncPipelineCompile=False;"; fi
[ "$maxfps" != 0 ] && on BO2_FRAME_PACING && dxmt="d3d11.preferredMaxFrameRate=$maxfps;$dxmt"
set_env DXMT_CONFIG "$dxmt"
set_env CX_GRAPHICS_BACKEND dxmt
for v in MTL_HUD_ENABLED MVKCACHE_FPS MVKCACHE_LOG BO_STATS BO_DRLOG; do
  if [ -n "${!v:-}" ]; then set_env "$v" "${!v}"; else clear_env "$v"; fi
done
# Settings of older setups' engines (prefixes imported from them): unused here.
for v in WINE_ROSETTA_CALL_WORKAROUND WINE_ROSETTA_EXEC_BREAKPOINTS WINE_ROSETTA_LAZY_EXEC \
         WINE_ROSETTA_WOW64_BREAKPOINTS WINE_SOCK_FASTPATH WINE_X87_SIDECAR; do
  grep -q "^\"$v\"=" "$WINEPREFIX/user.reg" 2>/dev/null && clear_env "$v"
done

# --- Wine settings -------------------------------------------------------------
bootstrapper='HKCU\Software\Wine\AppDefaults\plutonium-bootstrapper-win32.exe'
# Direct3D is DXVK's (9) or DXMT's (11); wined3d only backs DirectDraw, where
# BO1 reads its video memory (no3d reports 128 MB and caps textures to it).
reg add "$bootstrapper\\Direct3D" /v renderer /d no3d /f
if on BO1_VIDMEM; then reg add "$bootstrapper\\Direct3D" /v VideoMemorySize /d 4096 /f
else reg delete "$bootstrapper\\Direct3D" /v VideoMemorySize /f; fi
# Fullscreen: Wine captures the display, macOS shows the frames directly.
if on CAPTURE_DISPLAY; then reg add "$bootstrapper\\Mac Driver" /v CaptureDisplaysForFullscreen /d y /f
else reg add "$bootstrapper\\Mac Driver" /v CaptureDisplaysForFullscreen /d n /f; fi
# The Plutonium launcher's window is drawn with OpenGL.
reg add 'HKCU\Software\Wine\AppDefaults\plutonium-launcher-win32.exe\Direct3D' /v renderer /d gl /f
[ "$t" = t6c ] || "$WINESERVER" -w 2>/dev/null   # the campaign's Steam never exits

# --- macOS input ----------------------------------------------------------------
# Holding a key (W, A, S, D…) would open macOS's accent menu in the game's window:
# turn press-and-hold off for Wine's process only.
defaults write com.codeweavers.CrossOver.wineloader ApplePressAndHoldEnabled -bool false 2>/dev/null

# --- File pickers ---------------------------------------------------------------
# Wine's file dialogs (Plutonium's "Browse" for the game folder) open on the
# Windows desktop: give it shortcuts to the Mac's folders and the game folders,
# and the home folder as drive H:.
wdesk="$WINEPREFIX/drive_c/users/crossover/Desktop"
if [ -d "$wdesk" ] && [ ! -L "$wdesk" ]; then
  ln -sfn "$HOME" "$wdesk/Mac Home"
  for d in Downloads Documents; do [ -d "$HOME/$d" ] && ln -sfn "$HOME/$d" "$wdesk/$d"; done
  [ -d "${BO1_DIR:-}" ] && ln -sfn "$BO1_DIR" "$wdesk/Black Ops" || rm -f "$wdesk/Black Ops"
  [ -d "${BO2_DIR:-}" ] && ln -sfn "$BO2_DIR" "$wdesk/Black Ops II" || rm -f "$wdesk/Black Ops II"
  [ -d "${BOIII_DIR:-}" ] && ln -sfn "$BOIII_DIR" "$wdesk/Black Ops III" || rm -f "$wdesk/Black Ops III"
fi
[ -e "$WINEPREFIX/dosdevices/h:" ] || ln -s "$HOME" "$WINEPREFIX/dosdevices/h:"

# --- Black Ops II's campaign (t6sp.exe, Steam copy) --------------------------------
# Same Direct3D 11 -> Metal setup as Black Ops II through Plutonium (DXMT,
# background pipelines, frame pacing, set above), in its own prefix where
# Windows Steam is signed in: the game's Steam DRM needs it running.
if [ "$t" = t6c ]; then
  if on CAPTURE_DISPLAY; then reg add 'HKCU\Software\Wine\AppDefaults\t6sp.exe\Mac Driver' /v CaptureDisplaysForFullscreen /d y /f
  else reg add 'HKCU\Software\Wine\AppDefaults\t6sp.exe\Mac Driver' /v CaptureDisplaysForFullscreen /d n /f; fi
  camp="$kit/bo2-campaign.sh"
  bash "$camp" library "$dir" || exit 1
  # started from here rather than from Steam's library: tell the Steam API which game it is
  [ -f "$dir/steam_appid.txt" ] || printf '202970' > "$dir/steam_appid.txt"
  # a hardware profile made on an Apple GPU (fullscreen 1920x1080), once, as for BO2
  if on BO2_HW_PROFILE && [ ! -f "$dir/players/.bom-defaults-hardware" ]; then
    mkdir -p "$dir/players"
    cp "$kit/payload/bo2/hardware.chp" "$dir/players/hardware.chp" && : > "$dir/players/.bom-defaults-hardware"
  fi
  start_game() { (cd "$dir" && "$wine" t6sp.exe >> "$home/logs/bo2c-play.log" 2>&1 &); }
  # The game is running when a t6sp.exe works the CPU (one that only shows a
  # Steam error, or hands the start to Steam and quits, doesn't): its pid
  game_running() {  # game_running <seconds>
    local pid cpu
    for _ in $(seq 1 "$1"); do
      for pid in $(pgrep -f 't6sp\.exe'); do
        cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' '); cpu=${cpu%%.*}
        [ "${cpu:-0}" -gt 20 ] && { echo "$pid"; return 0; }
      done
      sleep 1
    done
    return 1
  }
  : > "$home/logs/bo2c-play.log"
  # t6sp.exe first: with Steam open and signed in, the game just starts
  start_game
  game_pid=$(game_running 40)
  if [ -z "$game_pid" ]; then
    # Steam didn't take it (not open, not signed in yet, or a Steam error):
    # close that attempt, get Steam ready (its window opens to sign in the
    # first time; after that it signs in by itself) and start the game again
    pkill -f 't6sp\.exe'; sleep 1
    if bash "$camp" status | grep -q '^signedin=yes'; then
      bash "$camp" steam -silent || exit 1
    else
      bash "$camp" show || exit 1
    fi
    bash "$camp" wait || exit 1
    start_game
    game_pid=$(game_running 90) || die "the campaign did not start (see logs/bo2c-play.log)"
  fi
  if on DISPLAY_MODE && [ -n "${dw:-}" ] && [ -n "${dh:-}" ]; then
    "$kit/tools/displaymode" "$dw" "$dh" "$game_pid" >> "$home/logs/displaymode.log" 2>&1 &
  fi
  # the game may hand itself to Steam's own start: follow whichever t6sp.exe runs
  while pgrep -f 't6sp\.exe' >/dev/null; do sleep 2; done
  exit 0
fi

# --- Black Ops III for Windows through boiii (BOIII / Ezz client) ----------------
# boiii.exe sits in the game folder and starts the game from there (it is the
# working directory), on DXMT (Direct3D 11 -> Metal, 64-bit).
if [ "$t" = t7 ]; then
  for exe in boiii.exe BlackOps3.exe; do
    if on CAPTURE_DISPLAY; then reg add "HKCU\\Software\\Wine\\AppDefaults\\$exe\\Mac Driver" /v CaptureDisplaysForFullscreen /d y /f
    else reg add "HKCU\\Software\\Wine\\AppDefaults\\$exe\\Mac Driver" /v CaptureDisplaysForFullscreen /d n /f; fi
  done
  # The game refuses to start unless Steam is installed ("Steam must be
  # installed for the game to run"), but boiii plays without it: register an
  # empty Steam folder whose steam.exe does nothing (no Steam, no login).
  steam="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
  mkdir -p "$steam"
  [ -f "$steam/steam.exe" ] || cp "$WINEPREFIX/drive_c/windows/system32/rundll32.exe" "$steam/steam.exe"
  reg add 'HKCU\Software\Valve\Steam' /v SteamExe /d 'c:/program files (x86)/steam/steam.exe' /f
  reg add 'HKCU\Software\Valve\Steam' /v SteamPath /d 'c:/program files (x86)/steam' /f
  reg add 'HKLM\Software\Wow6432Node\Valve\Steam' /v InstallPath /d 'C:\Program Files (x86)\Steam' /f
  # boiii's launcher is Internet Explorer's browser control (Wine's mshtml,
  # drawn by Wine Gecko). The prefix is made with mshtml off (Plutonium's
  # installer), which leaves its registration incomplete (the HTML document
  # class may be there, its content types are not) and the launcher white:
  # run mshtml's own registration once per prefix.
  if [ ! -f "$WINEPREFIX/.bom-mshtml" ]; then
    WINEDLLOVERRIDES="mscoree=" "$wine" regsvr32 /s mshtml.dll > /dev/null 2>&1 &&
    WINEDLLOVERRIDES="mscoree=" "$wine" 'C:\windows\syswow64\regsvr32.exe' /s mshtml.dll > /dev/null 2>&1 &&
      : > "$WINEPREFIX/.bom-mshtml"
  fi
  # Prefixes made before the engine had winegstreamer: register it once.
  sys="$WINEPREFIX/drive_c/windows"
  if [ ! -f "$sys/system32/winegstreamer.dll" ] && [ -f "$engine/lib/wine/x86_64-windows/winegstreamer.dll" ]; then
    cp "$engine/lib/wine/x86_64-windows/winegstreamer.dll" "$sys/system32/"
    cp "$engine/lib/wine/i386-windows/winegstreamer.dll" "$sys/syswow64/" 2>/dev/null
    "$wine" regsvr32 /s winegstreamer.dll > /dev/null 2>&1
    "$wine" 'C:\windows\syswow64\regsvr32.exe' /s winegstreamer.dll > /dev/null 2>&1
  fi
  "$WINESERVER" -w 2>/dev/null
  # Black Ops III checks for Media Foundation's video decoders ("requires the
  # Windows Media Feature Pack"): the engine's winegstreamer, with GStreamer
  # and its plugins (Apple's VideoToolbox decoder among them) in lib64.
  export GST_PLUGIN_SYSTEM_PATH_1_0="$engine/lib64/gstreamer-1.0" GST_PLUGIN_PATH_1_0= \
         GST_REGISTRY_1_0="$home/cache/gstreamer-registry.bin"
  # boiii keeps the game's location in AppData\Local\boiii\user\game_path.txt
  # (Windows path, no newline; it guesses Steam's default otherwise): point
  # it at the chosen folder, so the folder never has to be picked in boiii.
  bdir="$WINEPREFIX/drive_c/users/crossover/AppData/Local/boiii/user"
  mkdir -p "$bdir"
  printf '%s' "Z:${dir//\//\\}" > "$bdir/game_path.txt"
  log="$home/logs/boiii-play.log"
  # boiii's launcher window: mshtml stays on here
  export WINEDLLOVERRIDES="mscoree="
  # mods' unsafe Lua functions without boiii's question (its prompt broke some
  # mods); BOIII_UNSAFE_LUA=0 makes boiii ask first
  on BOIII_UNSAFE_LUA && GAME_ARGS="${GAME_ARGS:+$GAME_ARGS }-unsafe-lua"
  # Workshop mods: boiii takes Wine for Linux and runs steamcmd/steamcmd.sh
  # (it would fetch Linux SteamCMD, which can't run on macOS: "Retry Limit
  # Reached"). Give it Valve's macOS SteamCMD (checked against Valve's
  # signature) behind a steamcmd.sh of ours: SteamCMD gets its own home in the
  # game folder (never the Mac Steam app's), and its steamapps is linked
  # where boiii looks for the downloaded mod.
  scmd="$dir/steamcmd"
  if [ ! -x "$scmd/mac/steamcmd" ]; then
    tmp=$(mktemp -d)
    if curl -fsSL --retry 2 -o "$tmp/s.tgz" https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz &&
       mkdir -p "$tmp/x" && tar -xzf "$tmp/s.tgz" -C "$tmp/x" &&
       codesign -v "$tmp/x/steamcmd" 2>/dev/null &&
       codesign -dv "$tmp/x/steamcmd" 2>&1 | grep -q 'TeamIdentifier=MXGJJ98X76'; then
      rm -rf "$scmd/mac"; mkdir -p "$scmd"; mv "$tmp/x" "$scmd/mac"
    fi
    rm -rf "$tmp"
  fi
  if [ -x "$scmd/mac/steamcmd" ]; then
    rm -rf "$dir/steamcmd.tar.gz" "$scmd/linux32"
    # steamcmd.sh is a small Windows program of ours (kit/tools/steamcmd-bridge.c):
    # boiii can only wait for Windows programs; it runs the Mac script below
    cp "$kit/payload/bo3w/steamcmd-bridge.exe" "$scmd/steamcmd.sh"
    cat > "$scmd/bom-steamcmd.sh" <<'SH'
#!/bin/bash
# BO-Mac: Valve's macOS SteamCMD for boiii's Workshop downloads, started by
# steamcmd.sh (our Windows bridge), which waits for done.<token>
here="$(cd "${0%/*}" && pwd -P)"
token=$1; shift
export HOME="$here/home"
root="$HOME/Library/Application Support/Steam"
mkdir -p "$root/steamapps"
[ -L "$here/steamapps" ] || rm -rf "$here/steamapps"
ln -sfn "$root/steamapps" "$here/steamapps"
# SteamCMD's log stays out of boiii's sight: when boiii reads "update
# started" in steamcmd/logs/content_log.txt it empties the download folder
# (Windows SteamCMD's leftovers), which the macOS one is still writing
rm -rf "$here/logs"
"$here/mac/steamcmd.sh" "$@"
rc=$?
echo "$rc" > "$here/done.$token.tmp" && mv "$here/done.$token.tmp" "$here/done.$token"
exit "$rc"
SH
    chmod +x "$scmd/bom-steamcmd.sh"
  fi
  cd "$dir" || exit 1
  # BlackOps3.start stays behind when the game is stopped from the app, and the
  # next start would offer Safe Mode (which lowers the graphics settings).
  rm -f BlackOps3.start
  # The player name from the app's settings, in boiii's own profile, only
  # while boiii has none of its own: the name typed in boiii's launcher is kept
  if [ -n "${3:-}" ] || [ -n "${PLAYER_NAME:-}" ]; then
    /usr/bin/python3 -I - "$dir/boiii_players/properties.json" "${3:-$PLAYER_NAME}" <<'PY' 2>/dev/null || true
import json, os, sys
p, name = sys.argv[1], sys.argv[2]
d = {}
if os.path.exists(p):
    try: d = json.load(open(p, encoding="utf-8-sig"))   # boiii writes a BOM
    except Exception: sys.exit(0)                        # unreadable: leave it alone
if d.get("playerName", "") in ("", "crossover", "Unknown Soldier"):
    d["playerName"] = name
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump(d, open(p, "w", encoding="utf-8-sig"), separators=(",", ":"))
PY
  fi
  # First start: the game's auto-detect picks for an unknown GPU (half
  # resolution, no shadows, no ambient occlusion). Set it up once like BO1 and
  # BO2 instead: fullscreen at the desktop's size and refresh rate with sync,
  # full resolution and full detail. Afterwards the game's own options rule.
  ini="$dir/boiii_players/config.ini"
  if on BOIII_GRAPHICS && [ ! -f "$dir/boiii_players/.bom-defaults-config.ini" ] && [ -n "${dw:-}" ]; then
    mkdir -p "$dir/boiii_players"; touch "$ini"
    ini_set() {   # ini_set key value: replace the line or add it
      if grep -q "^$1 = " "$ini"; then sed -i '' -E "s|^($1 = )\"[^\"]*\"|\1\"$2\"|" "$ini"
      else printf '%s = "%s"\n' "$1" "$2" >> "$ini"; fi
    }
    ini_set AutoDetectHasRun 1;           ini_set RestrictGraphicsOptions 0
    ini_set FullScreenMode 1;             ini_set WindowSize "${dw}x${dh}"
    ini_set RefreshRate "${hz:-60}";      ini_set Vsync 1
    ini_set ResolutionPercent 100;        ini_set MeshQuality 0
    ini_set TextureQuality 0;             ini_set TextureFilter 2
    ini_set DisableDynamicLightShadows 0; ini_set DisableDynamicSunShadows 0
    ini_set ShadowFiltering 1;            ini_set VolumetricLightingEnabled 1
    ini_set SSAOTechnique "GTAO Medium Quality"
    ini_set AATechnique "Filmic SMAA T2x"; ini_set SubsurfaceScattering 1
    ini_set MotionBlur Off
    : > "$dir/boiii_players/.bom-defaults-config.ini"
  fi
  # Fullscreen: a 1x display mode of the desktop's size while the game runs
  # (as for BO1/BO2). On a HiDPI desktop the game otherwise switches to the
  # panel's full pixel size and shows its 1080p picture in one corner.
  if on DISPLAY_MODE && [ -n "${dw:-}" ] && [ -n "${dh:-}" ]; then
    "$kit/tools/displaymode" "$dw" "$dh" $$ >> "$home/logs/displaymode.log" 2>&1 &
    sleep 2   # the switch first: Wine reads the desktop mode as the game starts
  fi
  # shellcheck disable=SC2086
  exec "$wine" boiii.exe ${GAME_ARGS:-} > "$log" 2>&1
fi

# --- Plutonium and game settings -----------------------------------------------
winpath="Z:${dir//\//\\}"
cfg="$plutonium/config.json"
if [ -f "$cfg" ]; then
  KEY=${t}Path VAL="$winpath" /usr/bin/python3 -I - "$cfg" <<'PY'
import json, os, sys
p = sys.argv[1]
c = json.load(open(p))
if c.get(os.environ["KEY"]) != os.environ["VAL"]:
    c[os.environ["KEY"]] = os.environ["VAL"]
    json.dump(c, open(p, "w"), separators=(",", ":"))
PY
fi
set_cvar() { sed -i '' -E "s/^seta $2 \"[^\"]*\"/seta $2 \"$3\"/" "$1"; }
set_or_add() { if grep -q "^seta $2 " "$1"; then set_cvar "$@"; else printf 'seta %s "%s"\n' "$2" "$3" >> "$1"; fi; }
desktop=${dw:+${dw}x$dh}
# Default settings, applied once per game profile (marker file), so what the
# player changes in the game afterwards is kept: fullscreen at the display's
# resolution, sync every frame, automatic texture quality, 16x anisotropy.
defaults_once() {   # defaults_once <cfg> <marker> name value ...
  local cfg=$1 marker=$2; shift 2
  [ -f "$marker" ] && return 0
  [ -f "$cfg" ] || : > "$cfg"
  while [ $# -ge 2 ]; do set_or_add "$cfg" "$1" "$2"; shift 2; done
  : > "$marker"
}
common_cvars() {
  on MSAA_FIX && sed -i '' -E 's/^seta r_aaSamples "(8|16|32)"/seta r_aaSamples "4"/' "$1"
  if [ -n "$desktop" ]; then
    local rmode
    rmode=$(sed -n -E 's/^seta r_mode "([0-9]+)x[0-9]+"/\1/p' "$1")
    if [ "$rmode" = 800 ] || { [ -n "$rmode" ] && [ "$rmode" -gt "${desktop%x*}" ]; }; then set_cvar "$1" r_mode "$desktop"; fi
  fi
  if [ "${RAW_INPUT:-1}" = 1 ]; then set_or_add "$1" raw_input 1; set_cvar "$1" m_filter 0; fi
  if [ "${AIM_ACCEL:-0}" = 0 ]; then set_or_add "$1" aim_accel_turnrate_enabled 0; fi
  set_or_add "$1" gpad_stick_deadzone_min "${STICK_DEADZONE:-0.08}"
  set_or_add "$1" cl_mouseAccel 0
}
if [ "$t" = t5 ]; then
  players="$plutonium/storage/t5/players"
  # DXVK compiles every pipeline in its state cache while a map loads, so fold
  # in the list that ships with BO-Mac (about 19,000 pipelines gathered
  # on every zombies map: which shader combinations the game uses, nothing
  # hardware-specific) and any an older setup left: then nothing is compiled
  # for the first time mid-game (first shot, first explosion, a new area).
  on BO1_SHADER_CACHE && /usr/bin/python3 -I "$kit/tools/statecache-merge.py" "$home/cache/plutonium-bootstrapper-win32.dxvk-cache" \
    "$kit/payload/bo1/pipelines.dxvk-cache" \
    "$dir/plutonium-bootstrapper-win32.dxvk-cache" "$dir"/*/cache/plutonium-bootstrapper-win32.dxvk-cache 2>/dev/null || true
  mkdir -p "$players"
  for c in config.cfg config_mp.cfg; do
    [ -f "$players/$c" ] || printf 'seta %s "%s"\n' com_first_time_pc 0 com_recommendedSet 1 sm_enable 0 \
      r_blur_allowed 0 r_distortion 0 com_maxfps 0 r_fullscreen 1 > "$players/$c"
    defaults_once "$players/$c" "$players/.bom-defaults-$c" r_fullscreen 1 r_mode "${desktop:-1920x1080}" \
      r_vsync 1 r_picmip_manual 0 r_texFilterAnisoMax 16 r_aaSamples 4 r_aspectRatio auto \
      r_dof_enable 1 r_glow_allowed 1 r_shaderWarming 1
    common_cvars "$players/$c"
    [ -n "${hz:-}" ] && set_or_add "$players/$c" r_displayRefresh "$hz Hz"
    on BO1_NO_SHADOWS && set_cvar "$players/$c" sm_enable 0   # shadows froze BO1
    # shader warming draws every material once while the map loads; our
    # DXVK compiles them all then, while the loading screen stays up
    if on BO1_WARM; then set_or_add "$players/$c" r_shaderWarming 1; else set_or_add "$players/$c" r_shaderWarming 0; fi
    if [ "${STREAM:-0}" = 1 ]; then sed -i '' '/^seta r_stream "/d' "$players/$c"
    else set_or_add "$players/$c" r_stream 0; fi
    set_cvar "$players/$c" com_maxfps 0
  done
  gamecfg="$players/config.cfg"; [ "$mode" = mp ] && gamecfg="$players/config_mp.cfg"
  # DXVK reads dxvk.conf from the working directory
  dxvk="d3d9.numBackBuffers = 3"$'\n'"dxvk.numCompilerThreads = 8"$'\n'"dxvk.numAsyncThreads = 8"$'\n'
  [ "$maxfps" != 0 ] && dxvk+="d3d9.maxFrameRate = $maxfps"$'\n'
  for d in "$dir" "$plutonium" "$plutonium/bin"; do [ -d "$d" ] && printf '%s' "$dxvk" > "$d/dxvk.conf"; done
  # XAudio2 2.7 from BO1's redist: Wine's leaves BO1's gunfire silent
  xa="$WINEPREFIX/xaudio2_7.native.dll"
  if [ ! -f "$xa" ] && [ -f "$dir/redist/DirectX/Jun2010_XAudio_x86.cab" ]; then
    tmp=$(mktemp -d)
    bsdtar -xf "$dir/redist/DirectX/Jun2010_XAudio_x86.cab" -C "$tmp" XAudio2_7.dll 2>/dev/null && cp "$tmp/XAudio2_7.dll" "$xa"
    rm -rf "$tmp"
  fi
  if ! on BO1_XAUDIO; then
    reg delete "$bootstrapper\\DllOverrides" /v xaudio2_7 /f
  elif [ -f "$xa" ]; then
    cmp -s "$xa" "$WINEPREFIX/drive_c/windows/syswow64/xaudio2_7.dll" || cp "$xa" "$WINEPREFIX/drive_c/windows/syswow64/xaudio2_7.dll"
    reg add "$bootstrapper\\DllOverrides" /v xaudio2_7 /d native /f
  fi
elif [ "$t" = t4 ]; then
  # World at War: Direct3D 9 like Black Ops, so the same DXVK setup (background
  # pipeline compilation, persistent caches, the x87 accelerator); the game's
  # defaults like BO1's: fullscreen at the display's resolution with sync,
  # full textures, 16x anisotropy, 4x anti-aliasing (what Apple GPUs support)
  players="$plutonium/storage/t4/players"
  # WaW keeps its settings per profile (players/profiles/<name>/config.cfg;
  # "$$$" is the one Plutonium uses offline): set up every profile, and the
  # offline one before the game creates it with windowed 1024x768
  mkdir -p "$players/profiles/\$\$\$"
  offline="$players/profiles/\$\$\$"
  for f in "$players"/config.cfg "$players"/config_mp.cfg "$offline/config.cfg" "$offline/config_mp.cfg" \
           "$players"/profiles/*/config.cfg "$players"/profiles/*/config_mp.cfg; do
    case "$f" in *'*'*) continue ;; esac
    defaults_once "$f" "$(dirname "$f")/.bom-defaults-$(basename "$f")" r_fullscreen 1 r_mode "${desktop:-1920x1080}" \
      r_vsync 1 r_picmip_manual 0 r_texFilterAnisoMax 16 r_aaSamples 4 r_aspectRatio auto
    common_cvars "$f"
    [ -n "${hz:-}" ] && set_or_add "$f" r_displayRefresh "$hz Hz"
    set_cvar "$f" com_maxfps 0
  done
  gamecfg="$players/profiles/\$\$\$/config.cfg"; [ "$mode" = mp ] && gamecfg="$players/profiles/\$\$\$/config_mp.cfg"
  dxvk="d3d9.numBackBuffers = 3"$'\n'"dxvk.numCompilerThreads = 8"$'\n'"dxvk.numAsyncThreads = 8"$'\n'
  [ "$maxfps" != 0 ] && dxvk+="d3d9.maxFrameRate = $maxfps"$'\n'
  for d in "$dir" "$plutonium" "$plutonium/bin"; do [ -d "$d" ] && printf '%s' "$dxvk" > "$d/dxvk.conf"; done
else
  players="$plutonium/storage/t6/players"
  mkdir -p "$players"
  # an all-zero hardware profile makes BO2 detect a safe one (Apple GPUs stop at 4x MSAA)
  # BO2 keeps its display settings in a binary hardware profile (the cfg's
  # r_fullscreen/r_mode are overwritten from it). New profiles start from one
  # made on an Apple GPU: fullscreen 1920x1080, anti-aliasing Apple GPUs
  # support. Once per profile; the game re-detects if the hardware differs.
  if on BO2_HW_PROFILE; then
    for m in mp zm; do
      if [ ! -f "$players/.bom-defaults-hardware_$m" ]; then
        cp "$kit/payload/bo2/hardware.chp" "$players/hardware_$m.chp" && : > "$players/.bom-defaults-hardware_$m"
      fi
    done
  fi
  for c in plutonium_zm.cfg plutonium_mp.cfg; do
    defaults_once "$players/$c" "$players/.bom-defaults-$c" r_fullscreen 1 r_mode "${desktop:-1920x1080}" \
      r_vsync 1 r_monitor 0 r_picmip_manual 0 r_texFilterAnisoMax 16 r_aaSamples 1
    common_cvars "$players/$c"
    set_cvar "$players/$c" com_maxfps 0
  done
  gamecfg="$players/plutonium_zm.cfg"; [ "$mode" = mp ] && gamecfg="$players/plutonium_mp.cfg"
fi

# Fullscreen: a 1x display mode of the game's resolution while it runs, so a
# HiDPI-scaled desktop does not make macOS compose every frame at 2x.
if on DISPLAY_MODE && [ -f "$gamecfg" ] && grep -q '^seta r_fullscreen "1"' "$gamecfg"; then
  res=$(sed -n -E 's/^seta r_mode "([0-9]+)x([0-9]+)"/\1 \2/p' "$gamecfg")
  # shellcheck disable=SC2086
  [ -n "$res" ] && "$kit/tools/displaymode" $res $$ >> "$home/logs/displaymode.log" 2>&1 &
fi

log="$home/logs/$game-$mode.log"
if [ "$mode" = online ]; then
  launcher="$plutonium/bin/plutonium-launcher-win32.exe"
  [ -f "$launcher" ] || die "Plutonium is not installed in the prefix"
  cd "$plutonium/bin" || exit 1
  exec "$wine" "$launcher" > "$log" 2>&1
fi
case "$t:$mode" in
  t4:zombies|t4:campaign) pmode=t4sp ;; t4:mp) pmode=t4mp ;;
  t5:zombies|t5:campaign) pmode=t5sp ;; t5:mp) pmode=t5mp ;;
  t6:zombies) pmode=t6zm ;; t6:mp) pmode=t6mp ;;
  t6:declassified) pmode=t6zm
    [ -f "$plutonium/storage/t6/mods/dlc5/mod.ff" ] || [ -d "$plutonium/storage/t6/mods/dlc5" ] || die "Zombies Declassified is not installed"
    GAME_ARGS="+set fs_game mods/dlc5 ${GAME_ARGS:-}" ;;
esac
extra=${GAME_ARGS:-}
[ "$t" = t6 ] && extra="${BO2_MODS:-} $extra"
cd "$plutonium" || exit 1
# shellcheck disable=SC2086
exec "$wine" bin/plutonium-bootstrapper-win32.exe "$pmode" "$winpath" +name "${3:-Player}" -lan $extra > "$log" 2>&1
