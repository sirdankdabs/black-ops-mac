#!/bin/bash
# Builds the Black Ops Mac engine entirely from open source, with no CrossOver:
#   - Wine: CodeWeavers' published CrossOver 26.3 source (LGPL) + our patches
#     (kit/patches/wine-*.patch), for an x86_64 macOS host (runs under
#     Rosetta 2) with i386 and x86_64 Windows modules;
#   - the x86_64 macOS libraries Wine loads (FreeType, GnuTLS and its
#     dependencies, SDL2): from Sikarugir's wrapper template (open source);
#   - Wine Mono from WineHQ (for Plutonium's .NET installer).
# The result is one archive, dist/black-ops-mac-engine-<version>.tar.xz, that
# kit/install-engine.sh downloads and completes with DXVK, DXMT, MoltenVK and
# the x87 accelerator.
#
#   engine/build-engine.sh [work dir]       (default: ~/Library/Caches/bo-engine)
#
# Needs: Xcode command line tools, Homebrew with bison, flex, mingw-w64,
# freetype, sdl2, gnutls and vulkan-headers (headers only: the libraries used
# are the template's x86_64 ones).
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=${1:-"$HOME/Library/Caches/bo-engine"}
version=$(cat "$root/kit/VERSION")
step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
fetch() {  # fetch <url> <file> <sha256>
  [ -f "$2" ] && [ "$(shasum -a 256 "$2" | cut -d' ' -f1)" = "$3" ] && return 0
  curl -fL --retry 3 -o "$2.part" "$1" && mv -f "$2.part" "$2"
  [ "$(shasum -a 256 "$2" | cut -d' ' -f1)" = "$3" ] || die "checksum mismatch: $2"
}

cx_src_url=https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz
cx_src_sha=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
tpl_url=https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.24.tar.xz
tpl_sha=4b5f89eeb9ef139936bdfad33d9b420b05ea4597cb7d63376674f7a8e171321c
mono_url=https://dl.winehq.org/wine/wine-mono/10.4.1/wine-mono-10.4.1-x86.tar.xz
mono_sha=a16606ef0724202e6a6848ece6e0cbba64d11e2f11aefe744af1d93c6d9f99bb

mkdir -p "$work/downloads"
cd "$work"
step "Downloading sources"
fetch "$cx_src_url" downloads/crossover-sources-26.3.0.tar.gz "$cx_src_sha"
fetch "$tpl_url" downloads/Template-1.0.24.tar.xz "$tpl_sha"
fetch "$mono_url" downloads/wine-mono-10.4.1-x86.tar.xz "$mono_sha"

if [ ! -f src/.patched ]; then
  step "Unpacking Wine and applying our patches"
  rm -rf src unpack; mkdir unpack
  tar -xzf downloads/crossover-sources-26.3.0.tar.gz -C unpack
  mv "$(find unpack -maxdepth 3 -type f -name configure.ac -path '*wine*' -exec dirname {} \; | head -1)" src
  rm -rf unpack
  for p in "$root"/kit/patches/wine-*.patch; do
    (cd src && patch -p1 < "$p") > /dev/null || die "patch failed: $p"
  done
  touch src/.patched
fi
if [ ! -d template ]; then
  mkdir template; tar -xJf downloads/Template-1.0.24.tar.xz -C template
fi
F=$(find "$work/template" -maxdepth 3 -type d -name Frameworks -path '*Contents*' | head -1)

step "Configuring"
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p obj; cd obj
# Build tools (the font converter) load FreeType; make strips DYLD_* variables,
# so the template's libraries are linked where the tools look for them.
ln -sfn "$F" lib64; ln -sf "$F/libfreetype.dylib" libfreetype.dylib
[ -f Makefile ] || ../src/configure \
  --host=x86_64-apple-darwin --enable-archs=i386,x86_64 --disable-tests \
  --without-x --without-wayland --without-gstreamer --without-cups --without-sane \
  --without-gphoto --without-v4l2 --without-pcap --without-usb --without-krb5 \
  --without-capi --without-netapi --without-oss --without-pulse --without-alsa \
  --without-udev --without-dbus --without-unwind --without-opencl \
  --with-freetype --with-gnutls --with-sdl --with-vulkan \
  CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
  CFLAGS="-O2 -g" LDFLAGS="-arch x86_64 -L$F -Wl,-rpath,@loader_path/../../lib64" \
  FREETYPE_CFLAGS="-I/opt/homebrew/include/freetype2" FREETYPE_LIBS="-L$F -lfreetype" \
  GNUTLS_CFLAGS="-I/opt/homebrew/include" GNUTLS_LIBS="-L$F -lgnutls" \
  SDL2_CFLAGS="-I/opt/homebrew/include/SDL2" SDL2_LIBS="$F/libSDL2-2.0.0.dylib" > ../configure.log
step "Compiling (about 30 minutes)"
make -j"$(sysctl -n hw.ncpu)" > ../make.log 2>&1 || die "build failed (see $work/make.log)"
cd ..
"$root/engine/pack-engine.sh" "$work/obj" "$F" downloads/wine-mono-10.4.1-x86.tar.xz \
  "$root/dist/black-ops-mac-engine-$version.tar.xz"

# winegstreamer (Media Foundation's decoders, kit/payload) is built apart:
# a second configure of the same source with --with-gstreamer, GStreamer 1.24
# headers (Homebrew's gstreamer bottle: `brew fetch --force-bottle gstreamer`,
# include/ only) and CrossOver 26's x86_64 GStreamer libraries (LGPL), then
# `make dlls/winegstreamer/all`, with -DGLIB_VERSION_MAX_ALLOWED=GLIB_VERSION_2_78
# in GSTREAMER_CFLAGS and engine/glib-once-compat.c linked into winegstreamer.so
# (the headers are GLib 2.80, the runtime is 2.78). install-engine.sh ships it
# and the GStreamer runtime (kit/payload/gstreamer), whose libintl proxy is
# renamed libgstintl.8.dylib so it does not replace the engine's libintl.
