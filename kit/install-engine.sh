#!/bin/bash
# BO-Mac engine: assemble the Wine engine the games run on.
#
#   install-engine.sh [--update-x87]
#
# The base is our own Wine engine, built entirely from open source
# (engine/build-engine.sh: CodeWeavers' published CrossOver 26.3 source with
# our patches, Sikarugir's template libraries, Wine Mono), downloaded from the
# repository's releases. If it cannot be downloaded, CrossOver 26.3's runtime is
# used instead (installed, or CodeWeavers' download). Over it go:
#  - our ntdll.so (patches/wine-ntdll.patch): emulated execution breakpoints
#    under Rosetta (what Plutonium needs to start), execute-on-demand when a
#    program turns DEP off, and the x87sidecar handshake;
#  - our DXVK d3d9.dll (patches/dxvk-d3d9.patch) for Black Ops 1;
#  - DXMT (Direct3D 11 -> Metal) with background pipeline compilation, for
#    Black Ops II;
#  - our xinput1_3.dll: controller vibration without input delay;
#  - Khronos' MoltenVK 1.4.2 behind our persistent shader cache (mvkcache);
#  - athei's x87sidecar, its latest release (fast x87 maths under Rosetta);
#  - Wine's loader declared a game, so macOS turns Game Mode on.
#
# Environment: BOM_HOME (default: ~/Library/Application Support/Black Ops Mac),
# CROSSOVER_APP (default: /Applications/CrossOver.app).
# Progress lines start with "==> "; errors with "ERROR: ".
set -euo pipefail
kit=$(cd -- "$(dirname -- "$0")" && pwd)
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
cx_app=${CROSSOVER_APP:-/Applications/CrossOver.app}
cx_zip_version=26.3.0
cx_zip_url="https://media.codeweavers.com/pub/crossover/cxmac/demo/crossover-$cx_zip_version.zip"
cx_zip_sha256=8688e0848c4e5f79f1cc351cb52d32447da00c6c00cfd3b4bb2d164d44589a26
engine="$home/engine"
downloads="$home/downloads"
cx_version_wanted=26.3
engine_version=0.2.3
engine_url="https://github.com/sirdankdabs/bo-mac/releases/download/engine-$engine_version/black-ops-mac-engine-$engine_version.tar.xz"
engine_sha=347d849ab5cf7b2ce33fc1d8fcf51aee97e1ebbcfa1c3b0345e04d9b2640a0bb
moltenvk_url=https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-macos.tar
moltenvk_sha=f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e
# Wine Gecko (WineHQ): draws Windows' HTML control (boiii's launcher)
gecko_version=2.47.4
gecko_sha_x86_64=fd88fc7e537d058d7a8abf0c1ebc90c574892a466de86706a26d254710a82814
gecko_sha_x86=2cfc8d5c948602e21eff8a78613e1826f2d033df9672cace87fed56e8310afb6
x87_fallback_tag=v1.9.1
x87_fallback_sha=e18d1c2443f1440ae5a8e137dd0c85ec33e53506b67604675826094122106615

step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
fetch() { # url file sha256
  if [ ! -f "$2" ] || [ "$(sha "$2")" != "$3" ]; then
    curl -fsSL --retry 3 -o "$2.part" "$1" || die "cannot download $1"
    mv -f "$2.part" "$2"
  fi
  [ "$(sha "$2")" = "$3" ] || die "$(basename "$2"): SHA-256 does not match"
}

x87_install() { # into $1/bin: athei's latest x87sidecar release, else the pinned one
  local dest=$1 tag sha url tmp json
  json=$(curl -fsSL https://api.github.com/repos/athei/x87sidecar/releases/latest 2>/dev/null || true)
  tag=$(printf '%s' "$json" | /usr/bin/python3 -I -c 'import json,sys
try: print(json.load(sys.stdin)["tag_name"])
except Exception: pass' 2>/dev/null)
  sha=$(printf '%s' "$json" | /usr/bin/python3 -I -c 'import json,sys
try:
    r = json.load(sys.stdin)
    print(next(a["digest"].split(":")[1] for a in r["assets"] if a["name"] == "x87sidecar.tar.xz"))
except Exception: pass' 2>/dev/null)
  if [ -z "$tag" ] || [ -z "$sha" ]; then tag=$x87_fallback_tag sha=$x87_fallback_sha; fi
  url="https://github.com/athei/x87sidecar/releases/download/$tag/x87sidecar.tar.xz"
  fetch "$url" "$downloads/x87sidecar-$tag.tar.xz" "$sha"
  tmp=$(mktemp -d)
  tar -xJf "$downloads/x87sidecar-$tag.tar.xz" -C "$tmp"
  xattr -d com.apple.quarantine "$tmp/x87sidecar" 2>/dev/null || true
  if ! "$tmp/x87sidecar" --probe > /dev/null 2>&1; then
    echo "note: x87sidecar $tag does not support this Rosetta; the games will run without x87 acceleration" >&2
  fi
  mkdir -p "$dest/bin"
  mv -f "$tmp/x87sidecar" "$dest/bin/x87sidecar"
  rm -rf "$tmp"
  echo "$tag" > "$dest/x87sidecar.version"
  step "x87sidecar $tag installed"
}

# --- Only the x87 accelerator ------------------------------------------------
if [ "${1:-}" = --update-x87 ]; then
  [ -d "$engine/lib/wine" ] || die "the engine is not installed yet"
  mkdir -p "$downloads"
  x87_install "$engine"
  exit 0
fi

# --- Checks ------------------------------------------------------------------
step "Checking this Mac"
[ "$(uname -m)" = arm64 ] || die "BO-Mac is for Apple Silicon Macs"
/usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null ||
  die "Rosetta 2 is missing. Install it with: softwareupdate --install-rosetta --agree-to-license"
mkdir -p "$home" "$downloads"
new="$engine.new"
rm -rf "$new"

# --- Base: our engine ------------------------------------------------------------
own=
archive=${BOM_ENGINE_ARCHIVE:-"$downloads/black-ops-mac-engine-$engine_version.tar.xz"}
if [ ! -f "$archive" ] || [ "$(sha "$archive")" != "$engine_sha" ]; then
  step "Downloading the BO-Mac engine $engine_version (130 MB)"
  if curl -fL --retry 3 -o "$archive.part" "$engine_url" 2>/dev/null; then mv -f "$archive.part" "$archive"; else rm -f "$archive.part"; fi
fi
if [ -f "$archive" ] && [ "$(sha "$archive")" = "$engine_sha" ]; then
  step "Unpacking the engine"
  tmp=$(mktemp -d)
  tar -xJf "$archive" -C "$tmp" || die "cannot unpack the engine"
  mv "$tmp/engine" "$new"; rm -rf "$tmp"
  own=1
  base="own $engine_version"
else
  step "The engine download is not available; using CrossOver 26.3's runtime instead"
fi

if [ -z "$own" ]; then
# CrossOver's runtime: from an installed CrossOver 26.3 when there is one,
# otherwise from CodeWeavers' own download of it (checked against its
# SHA-256). Only the Wine runtime inside is used; CrossOver itself is never
# installed or opened.
cx_ok() {
  [ -d "$1/Contents/SharedSupport/CrossOver/lib/wine" ] || return 1
  case "$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null)" in
    "$cx_version_wanted"|"$cx_version_wanted".*) return 0 ;; *) return 1 ;;
  esac
}
if ! cx_ok "$cx_app"; then
  cx_app="$downloads/CrossOver-$cx_zip_version.app"
  if ! cx_ok "$cx_app"; then
    zip="$downloads/crossover-$cx_zip_version.zip"
    if [ ! -f "$zip" ] || [ "$(shasum -a 256 "$zip" | cut -d' ' -f1)" != "$cx_zip_sha256" ]; then
      step "Downloading CrossOver $cx_zip_version's runtime from CodeWeavers (390 MB)"
      curl -fL -C - --retry 3 -o "$zip.part" "$cx_zip_url" 2>/dev/null ||
        curl -fL --retry 3 -o "$zip.part" "$cx_zip_url" || die "could not download CrossOver from codeweavers.com"
      mv -f "$zip.part" "$zip"
    fi
    [ "$(shasum -a 256 "$zip" | cut -d' ' -f1)" = "$cx_zip_sha256" ] || { rm -f "$zip"; die "the CrossOver download is damaged; try again"; }
    step "Unpacking the runtime"
    rm -rf "$downloads/cx.tmp"; mkdir -p "$downloads/cx.tmp"
    ditto -x -k "$zip" "$downloads/cx.tmp" || die "cannot unpack the CrossOver download"
    rm -rf "$cx_app"; mv "$downloads/cx.tmp/CrossOver.app" "$cx_app"; rm -rf "$downloads/cx.tmp" "$zip"
    cx_ok "$cx_app" || die "unexpected CrossOver download"
  fi
fi
cx_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$cx_app/Contents/Info.plist" 2>/dev/null || echo "?")
step "Copying CrossOver $cx_version's runtime"
cp -cR "$cx_app/Contents/SharedSupport/CrossOver" "$new" 2>/dev/null || cp -R "$cx_app/Contents/SharedSupport/CrossOver" "$new"
base="CrossOver $cx_version"
fi
L="$new/lib/wine"

# --- Our modules ---------------------------------------------------------------
step "Installing the BO-Mac modules"
if [ -z "$own" ]; then   # our engine has it built in
  cp "$kit/payload/x86_64-unix/ntdll.so" "$L/x86_64-unix/ntdll.so"
  codesign -fs - "$L/x86_64-unix/ntdll.so" 2>/dev/null
fi
# winemac.so (patches/wine-winemac-mouselook.patch): mouse look without
# warping the cursor every frame; built with our engine, so ours only
if [ -n "$own" ]; then
  cp "$kit/payload/x86_64-unix/winemac.so" "$L/x86_64-unix/winemac.so"
  codesign -fs - "$L/x86_64-unix/winemac.so" 2>/dev/null
fi
# ntdll.dll: WINE_HIDE_WINE_EXPORTS (boiii's Workshop downloads), same build as ntdll.so
cp "$kit/payload/x86_64-windows/ntdll.dll" "$L/x86_64-windows/ntdll.dll"
cp "$kit/payload/i386-windows/ntdll.dll" "$L/i386-windows/ntdll.dll"
cp "$kit/payload/i386-windows/d3d9.dll" "$L/i386-windows/d3d9.dll"
# xinput: ours and CrossOver's side by side, launch.sh picks one (RUMBLE_FIX)
cp "$kit/payload/orig/xinput1_3.dll" "$L/i386-windows/xinput1_3.cx.dll"
cp "$kit/payload/i386-windows/xinput1_3.dll" "$L/i386-windows/xinput1_3.bom.dll"
cp "$kit/payload/i386-windows/xinput1_3.dll" "$L/i386-windows/xinput1_3.dll"
# winebus.sys: vibration written without holding back the controller's input
cp "$kit/payload/orig/winebus.sys" "$L/x86_64-windows/winebus.cx.sys"
cp "$kit/payload/x86_64-windows/winebus.sys" "$L/x86_64-windows/winebus.bom.sys"
cp "$kit/payload/x86_64-windows/winebus.sys" "$L/x86_64-windows/winebus.sys"
for a in i386-windows x86_64-windows; do
  for d in d3d11 dxgi d3d10core winemetal; do
    cp "$kit/payload/dxmt/$a/$d.dll" "$L/$a/$d.dll"
  done
done
cp "$kit/payload/dxmt/x86_64-unix/winemetal.so" "$L/x86_64-unix/winemetal.so"
codesign -fs - "$L/x86_64-unix/winemetal.so" 2>/dev/null
# Media Foundation's video decoders (Black Ops III asks for them, "Windows
# Media Feature Pack"): winegstreamer with GStreamer 1.24 (LGPL) and its
# plugins, VideoToolbox's hardware decoder among them. CrossOver has its own.
if [ -n "$own" ]; then
  cp "$kit/payload/x86_64-unix/winegstreamer.so" "$L/x86_64-unix/winegstreamer.so"
  cp "$kit/payload/x86_64-windows/winegstreamer.dll" "$L/x86_64-windows/winegstreamer.dll"
  cp "$kit/payload/i386-windows/winegstreamer.dll" "$L/i386-windows/winegstreamer.dll"
  mkdir -p "$new/lib64/gstreamer-1.0"
  cp "$kit/payload/gstreamer/lib64/"*.dylib "$new/lib64/"
  cp "$kit/payload/gstreamer/lib64/gstreamer-1.0/"*.dylib "$new/lib64/gstreamer-1.0/"
  for f in "$L/x86_64-unix/winegstreamer.so" "$new/lib64/"libg*.dylib "$new/lib64/libpcre2-8.0.dylib" "$new/lib64/gstreamer-1.0/"*.dylib; do
    codesign -fs - "$f" 2>/dev/null
  done
fi

step "Installing MoltenVK 1.4.2 with the shader cache"
fetch "$moltenvk_url" "$downloads/MoltenVK-macos-1.4.2.tar" "$moltenvk_sha"
tmp=$(mktemp -d)
tar -xf "$downloads/MoltenVK-macos-1.4.2.tar" -C "$tmp" MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib
cp "$tmp/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$new/lib64/libMoltenVK.real.dylib"
rm -rf "$tmp"
install_name_tool -id @rpath/libMoltenVK.real.dylib "$new/lib64/libMoltenVK.real.dylib" 2>/dev/null
codesign -fs - "$new/lib64/libMoltenVK.real.dylib" 2>/dev/null
cp "$kit/payload/lib64/libMoltenVK.dylib" "$new/lib64/libMoltenVK.dylib"
codesign -fs - "$new/lib64/libMoltenVK.dylib" 2>/dev/null
# our engine's Vulkan (winevulkan) is MoltenVK, through the shader cache
[ -n "$own" ] && ln -sf libMoltenVK.dylib "$new/lib64/libvulkan.1.dylib"

step "Installing Wine Gecko $gecko_version (HTML for boiii's launcher)"
mkdir -p "$new/share/wine/gecko"
for a in x86_64 x86; do
  sha_var="gecko_sha_$a"
  f="wine-gecko-$gecko_version-$a.tar.xz"
  fetch "https://dl.winehq.org/wine/wine-gecko/$gecko_version/$f" "$downloads/$f" "${!sha_var}"
  tar -xJf "$downloads/$f" -C "$new/share/wine/gecko"
done

step "Installing the x87 accelerator"
x87_install "$new"

step "Declaring Wine a game (macOS Game Mode)"
/usr/bin/python3 -I "$kit/tools/gamemode-plist.py" "$L/x86_64-unix/wine" > /dev/null &&
  codesign -fs - "$L/x86_64-unix/wine" 2>/dev/null

# keep the shader cache of the previous engine
for c in "$engine"/lib64/mvkcache.bin.*; do [ -f "$c" ] && cp -p "$c" "$new/lib64/"; done
cat > "$new/black-ops-mac.version" <<EOF
base=$base
kit=$(cat "$kit/VERSION" 2>/dev/null || echo dev)
x87sidecar=$(cat "$new/x87sidecar.version")
EOF
rm -rf "$engine.old"
[ -d "$engine" ] && mv "$engine" "$engine.old"
mv "$new" "$engine"
rm -rf "$engine.old"
step "Engine ready in $engine"
