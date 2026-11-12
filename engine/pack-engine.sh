#!/bin/bash
# Packs a built Wine (engine/build-engine.sh) into the engine archive:
#   pack-engine.sh <wine obj dir> <template Frameworks dir> <wine-mono tar.xz> <out.tar.xz>
# Layout (what kit/install-engine.sh and kit/launch.sh expect):
#   bin/wine, bin/wineserver
#   lib/wine/{i386-windows,x86_64-windows,x86_64-unix}/...
#   lib64/   the x86_64 libraries Wine loads, with their dependencies
#   share/wine/{fonts,nls,wine.inf,mono/wine-mono-10.4.1}
#   licenses/
set -euo pipefail
obj=$1 F=$2 mono=$3 out=$4
step() { printf '==> %s\n' "$*"; }
stage=$(mktemp -d)/engine
trap 'rm -rf "$(dirname "$stage")"' EXIT

step "Installing Wine into the package"
make -C "$obj" install-lib DESTDIR="$stage" prefix= > /dev/null
rm -rf "$stage/include" "$stage/share/man" "$stage/share/applications"
# the loader where the kit runs it from
[ -e "$stage/lib/wine/x86_64-unix/wine" ] || cp -p "$stage/bin/wine" "$stage/lib/wine/x86_64-unix/wine"

step "Adding the libraries Wine loads"
mkdir -p "$stage/lib64"
# everything the given libraries need from the template, recursively
queue=(libfreetype.6.dylib libgnutls.30.dylib libSDL2-2.0.0.dylib libSDL3.0.dylib libinotify.0.dylib)
seen=" "
while [ ${#queue[@]} -gt 0 ]; do
  lib=${queue[0]}; queue=("${queue[@]:1}")
  case "$seen" in *" $lib "*) continue ;; esac
  seen="$seen$lib "
  [ -f "$F/$lib" ] || { echo "missing in template: $lib" >&2; exit 1; }
  cp -pL "$F/$lib" "$stage/lib64/$lib"
  for dep in $(otool -L "$F/$lib" | awk 'NR>1 {print $1}' | grep '^@rpath/' | sed 's|@rpath/||'); do
    queue+=("$dep")
  done
done
# the names Wine opens them by
ln -sf libfreetype.6.dylib "$stage/lib64/libfreetype.dylib"
ln -sf libgnutls.30.dylib "$stage/lib64/libgnutls.dylib"
# the template's SDL2 is sdl2-compat (SDL2 on SDL3): it opens SDL3 by this name
ln -sf libSDL3.0.dylib "$stage/lib64/libSDL3.dylib"
for l in "$stage"/lib64/*.dylib; do
  [ -L "$l" ] && continue
  install_name_tool -add_rpath @loader_path "$l" 2>/dev/null || true
  codesign -fs - "$l" 2>/dev/null
done

# Wine's modules find lib64 from lib/wine/x86_64-unix
for f in "$stage"/lib/wine/x86_64-unix/*.so "$stage"/lib/wine/x86_64-unix/wine; do
  install_name_tool -add_rpath @loader_path/../../../lib64 "$f" 2>/dev/null || true
  codesign -fs - "$f" 2>/dev/null
done
install_name_tool -add_rpath @loader_path/../lib64 "$stage/bin/wine" 2>/dev/null || true
codesign -fs - "$stage/bin/wine" 2>/dev/null

# wineserver and some modules (winebus: controllers) link libinotify by its
# bare name, which macOS cannot load: point them at the bundled copy
for f in "$stage"/bin/* "$stage"/lib/wine/x86_64-unix/*.so; do
  if otool -L "$f" 2>/dev/null | grep -q "^[[:space:]]*libinotify.dylib"; then
    install_name_tool -change libinotify.dylib @rpath/libinotify.0.dylib "$f"
    codesign -fs - "$f" 2>/dev/null
  fi
done
install_name_tool -add_rpath @executable_path/../lib64 "$stage/bin/wineserver"
codesign -fs - "$stage/bin/wineserver" 2>/dev/null

step "Adding Wine Mono"
mkdir -p "$stage/share/wine/mono"
tar -xJf "$mono" -C "$stage/share/wine/mono"

step "Licenses"
mkdir -p "$stage/licenses"
cp "$obj/../src/COPYING.LIB" "$stage/licenses/wine-COPYING.LIB" 2>/dev/null || true
cp "$obj/../src/LICENSE" "$stage/licenses/wine-LICENSE" 2>/dev/null || true
cat > "$stage/licenses/README" <<'EOF'
Black Ops Mac engine.
Wine: built from CodeWeavers' published CrossOver 26.3 source with the
patches in the Black Ops Mac repository (kit/patches), LGPL-2.1-or-later.
lib64: x86_64 libraries from Sikarugir's wrapper template
(github.com/Sikarugir-App/Template), each under its own license (FreeType:
FTL/GPL-2; GnuTLS, nettle, gmp, libtasn1, libidn2, libunistring, gettext:
LGPL; SDL2: zlib).
Wine Mono: WineHQ (dl.winehq.org), its own licenses.
EOF

step "Packing $out"
mkdir -p "$(dirname "$out")"
tar -C "$(dirname "$stage")" -cJf "$out" engine
shasum -a 256 "$out"
du -h "$out"
