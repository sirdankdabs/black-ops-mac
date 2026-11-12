#!/bin/bash
# Black Ops Mac: Zombies Declassified (github.com/Logo-2K/zombies-declassified,
# by Logo-2K), Black Ops II's unreleased "DLC 5": Black Ops 1 and World at
# War's zombies maps ported to Black Ops II, as a Plutonium mod.
#
# Installed with the project's own installer (zdinstall.py, from its latest
# release): every file is downloaded (~9 GB), checked against the release's
# SHA-256 and placed in Black Ops II's sound/ folder and in Plutonium's
# storage (mods/dlc5, mods/zm_weapons). Anything it replaces is backed up.
#
#   zombies-declassified.sh status    installed=<release> latest=<release>
#   zombies-declassified.sh install   install or update to the latest release
#   zombies-declassified.sh verify    check the installed files
#   zombies-declassified.sh remove    move the mod's files to the Trash
#
# Progress lines start with "==> "; errors with "ERROR: ".
set -uo pipefail
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
repo=Logo-2K/zombies-declassified
export ZDINSTALL_HOME="$home/zombies-declassified"   # the installer's record and backups
state="$ZDINSTALL_HOME/state.json"
t6="$home/prefix/drive_c/users/crossover/AppData/Local/Plutonium/storage/t6"
step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
bo2=${BO2_DIR:-}
if [ -z "$bo2" ] && [ -f "$home/settings.conf" ]; then bo2=$(sed -n 's/^BO2_DIR=//p' "$home/settings.conf" | tail -1); fi

installed() { [ -f "$state" ] && /usr/bin/python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s.get("releaseTag") or "") if s.get("files") else None' "$state" 2>/dev/null; }
latest_json() { curl -fsSL "https://api.github.com/repos/$repo/releases/latest"; }

case "${1:-}" in
status)
  echo "installed=$(installed)"
  echo "latest=$(latest_json 2>/dev/null | /usr/bin/python3 -I -c 'import json,sys
try: print(json.load(sys.stdin)["tag_name"])
except Exception: pass')"
  ;;
install|verify)
  [ -d "$bo2/zone" ] && [ -d "$bo2/sound" ] || die "set the Black Ops II folder first"
  [ -d "$home/prefix/drive_c" ] || die "set up Plutonium first"
  mkdir -p "$t6" "$ZDINSTALL_HOME"
  work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
  latest_json > "$work/release.json" 2>/dev/null || die "cannot reach GitHub"
  asset() { /usr/bin/python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1]))
print(next(a["browser_download_url"] for a in r["assets"] if a["name"]==sys.argv[2]))' "$work/release.json" "$1"; }
  tag=$(/usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "$work/release.json")
  curl -fsSL "$(asset zdinstall.py)" -o "$work/zdinstall.py" || die "download failed"
  curl -fsSL "$(asset manifest.json)" -o "$work/manifest.json" || die "download failed"
  if [ "$1" = verify ]; then
    step "Checking Zombies Declassified"
    /usr/bin/python3 -I -u "$work/zdinstall.py" --pluto "$t6" --bo2 "$bo2" --manifest "$work/manifest.json" --verify ||
      die "some files are missing or changed: install again to repair them"
    step "All files are as installed"
  else
    step "Installing Zombies Declassified $tag (about 9 GB the first time)"
    /usr/bin/python3 -I -u "$work/zdinstall.py" --pluto "$t6" --bo2 "$bo2" --manifest "$work/manifest.json"
    rc=$?
    case $rc in
      0) step "Zombies Declassified $tag installed" ;;
      4) die "some files differ from every release and were kept as they are" ;;
      *) die "the installer failed (run Install again: downloads resume)" ;;
    esac
  fi
  ;;
remove)
  [ -f "$state" ] || die "Zombies Declassified is not installed"
  [ -d "$bo2/sound" ] || die "set the Black Ops II folder first"
  step "Moving Zombies Declassified's files to the Trash"
  dest="$HOME/.Trash/Zombies Declassified (Black Ops Mac $(date '+%Y-%m-%d %H.%M.%S'))"
  /usr/bin/python3 -I - "$state" "$t6" "$bo2" "$dest" <<'PY'
import json, os, shutil, sys
state, t6, bo2, dest = sys.argv[1:5]
roots = {"PLUTO_T6": t6, "BO2": bo2}
moved = 0
for f in json.load(open(state))["files"]:
    parts = f["relpath"].replace("\\", "/").split("/")
    src = os.path.join(roots[f["root"]], *parts)
    if os.path.exists(src):
        d = os.path.join(dest, f["root"], *parts)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.move(src, d)
        moved += 1
for d in ("mods/dlc5", "mods/zm_weapons"):   # now-empty mod folders
    p = os.path.join(t6, d)
    for root, dirs, files in os.walk(p, topdown=False):
        if not files and not os.listdir(root):
            os.rmdir(root)
print("==> %d files moved to the Trash" % moved)
PY
  [ $? = 0 ] || die "could not remove every file"
  # Game files the first install replaced come back from its backup.
  b="$ZDINSTALL_HOME/backups/pre-install/sound"
  [ -d "$b" ] && cp -Rp "$b/." "$bo2/sound/"
  mv "$state" "$state.removed"
  step "Zombies Declassified removed"
  ;;
*)
  die "usage: zombies-declassified.sh status | install | verify | remove"
  ;;
esac
