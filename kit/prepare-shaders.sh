#!/bin/bash
# Black Ops Mac: compile Black Ops 1's shaders for every map, once.
#
# The first time a map loads, its loading screen stays up until all of its
# pipelines are compiled (about a minute; afterwards it takes no time). This
# loads each map in turn and waits for that, so every map is ready the first
# time it is played.
#
#   prepare-shaders.sh            zombies maps
#   prepare-shaders.sh mp         multiplayer maps
#   prepare-shaders.sh all        both
#   prepare-shaders.sh <map>...   just these
#
# Progress lines start with "==> "; errors with "ERROR: ".
set -uo pipefail
kit=$(cd -- "$(dirname -- "$0")" && pwd)
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
dir=${BO1_DIR:-}
if [ -z "$dir" ] && [ -f "$home/settings.conf" ]; then
  dir=$(sed -n 's/^BO1_DIR=//p' "$home/settings.conf" | tail -1)
fi
[ -d "$dir/zone" ] || die "set the Black Ops folder first"

zm="zombie_theater zombie_pentagon zombie_cosmodrome zombie_coast zombie_temple zombie_moon
zombie_cod5_prototype zombie_cod5_asylum zombie_cod5_sumpf zombie_cod5_factory"
mp="mp_array mp_cracked mp_crisis mp_firingrange mp_duga mp_hanoi mp_cairo mp_havoc mp_cosmodrome
mp_nuked mp_radiation mp_mountain mp_villa mp_russianbase mp_berlinwall2 mp_discovery mp_kowloon
mp_stadium mp_gridlock mp_hotel mp_outskirts mp_zoo mp_drivein mp_area51 mp_golfcourse mp_silo"
case "${1:-zm}" in
zm) maps=$zm ;; mp) maps=$mp ;; all) maps="$zm $mp" ;; *) maps="$*" ;;
esac

# DXVK writes its log next to the game; the line below ends each map.
dlog="$dir/plutonium-bootstrapper-win32_d3d9.log"
trap '"$kit/launch.sh" stop >/dev/null 2>&1; exit 130' INT TERM
"$kit/launch.sh" stop >/dev/null 2>&1
n=0 total=$(echo $maps | wc -w | tr -d ' ') failed=0
for map in $maps; do
  n=$((n + 1))
  case "$map" in mp_*) mode=mp ;; *) mode=zombies ;; esac
  step "[$n/$total] $map"
  rm -f "$dlog"
  GAME_ARGS="+map $map" "$kit/launch.sh" bo1 "$mode" >/dev/null 2>&1 &
  start=$(date +%s) ok=0
  while [ $(( $(date +%s) - start )) -lt 400 ]; do
    sleep 3
    if grep -q "waited [0-9]* ms for shader warming" "$dlog" 2>/dev/null; then ok=1; break; fi
  done
  ms=$(grep -o "waited [0-9]* ms" "$dlog" 2>/dev/null | tail -1 | tr -dc 0-9)
  "$kit/launch.sh" stop >/dev/null 2>&1
  sleep 3
  if [ $ok = 1 ]; then step "[$n/$total] $map ready (compiled for $(( ${ms:-0} / 1000 )) s)"
  else printf 'ERROR: %s did not finish loading\n' "$map" >&2; failed=$((failed + 1)); fi
done
[ $failed = 0 ] && step "All $total maps are ready" || die "$failed maps did not finish"
