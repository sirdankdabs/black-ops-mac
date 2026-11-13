#!/bin/bash
# BO-Mac: boiii.exe, the BOIII / Ezz community client for the Windows
# version of Black Ops III (github.com/Ezz-lol/boiii-free).
#
#   boiii.sh status     installed=<sha> latest=<release tag>
#   boiii.sh download   the latest release's boiii.exe into the game folder,
#                       checked against the SHA-256 GitHub publishes for it
#   boiii.sh backup <folder>   saves the player's boiii data in one zip there:
#                       stats, loadouts, save games and settings (the game's
#                       boiii_players folder) and the identity keys the
#                       servers know the player by (AppData\Local\boiii\user)
#   boiii.sh restore <zip>     puts a backup back (on this or another Mac, or
#                       by hand on Windows); what it replaces goes to the Trash
#
# Progress lines start with "==> "; errors with "ERROR: ".
set -uo pipefail
home=${BOM_HOME:-"$HOME/Library/Application Support/Black Ops Mac"}
repo=Ezz-lol/boiii-free
step() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
dir=${BOIII_DIR:-}
if [ -z "$dir" ] && [ -f "$home/settings.conf" ]; then dir=$(sed -n 's/^BOIII_DIR=//p' "$home/settings.conf" | tail -1); fi

release() {  # prints: tag url sha256
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | /usr/bin/python3 -I -c 'import json,sys
try:
    r = json.load(sys.stdin)
    a = next(a for a in r["assets"] if a["name"] == "boiii.exe")
    print(r["tag_name"], a["browser_download_url"], (a.get("digest") or "").split(":")[-1])
except Exception: pass'
}

keys="$home/prefix/drive_c/users/crossover/AppData/Local/boiii/user"
trash() {
  [ -e "$1" ] || return 0
  mkdir -p "$HOME/.Trash"
  mv "$1" "$HOME/.Trash/$(basename "$1") (BO-Mac $(date '+%Y-%m-%d %H.%M.%S'))"
}

case "${1:-}" in
backup)
  out=${2:-}
  [ -d "$out" ] || die "choose a folder for the backup"
  [ -d "$dir/boiii_players" ] || die "there is nothing to back up yet: play once first"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  b="$tmp/BOIII Backup"
  mkdir -p "$b/key"
  ditto --norsrc --noextattr "$dir/boiii_players" "$b/boiii_players"
  find "$b" -name .DS_Store -delete
  for k in "$keys"/ezz-*.key; do [ -f "$k" ] && cp -p "$k" "$b/key/"; done
  cat > "$b/README.txt" <<'TXT'
BOIII (Ezz) player backup, made by BO-Mac.

boiii_players/  stats, loadouts, save games and settings. It goes in the
                Black Ops III game folder (next to boiii.exe).
key/            the identity keys the community servers know you by. On
                Windows they go in %LOCALAPPDATA%\boiii\user\ ; on a Mac,
                BO-Mac's Restore puts them in place.

Keep this file private: anyone with the keys can play as you.
TXT
  zip_name="BOIII Backup $(date '+%Y-%m-%d %H.%M').zip"
  (cd "$tmp" && ditto -c -k --norsrc --noextattr --keepParent "BOIII Backup" "$out/$zip_name") || die "cannot write the backup"
  step "Saved $out/$zip_name"
  ;;
restore)
  zip=${2:-}
  [ -f "$zip" ] || die "choose a backup zip"
  [ -d "$dir" ] || die "choose the Black Ops III (Windows) folder first"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  ditto -x -k "$zip" "$tmp" || die "this is not a BOIII backup"
  b=$(find "$tmp" -maxdepth 2 -type d -name boiii_players -print -quit)
  [ -n "$b" ] || die "this is not a BOIII backup"
  b=$(dirname "$b")
  pgrep -f "boiii.exe|BlackOps3.exe" >/dev/null && die "quit Black Ops III first"
  trash "$dir/boiii_players"
  ditto "$b/boiii_players" "$dir/boiii_players"
  if ls "$b"/key/ezz-*.key >/dev/null 2>&1; then
    mkdir -p "$keys"
    for k in "$keys"/ezz-*.key; do [ -f "$k" ] && trash "$k"; done
    cp -p "$b"/key/ezz-*.key "$keys/"
  fi
  step "Stats, loadouts and identity restored"
  ;;
status)
  [ -f "$dir/boiii.exe" ] && echo "installed=$(shasum -a 256 "$dir/boiii.exe" | cut -c1-12)" || echo "installed="
  read -r tag _ _ < <(release); echo "latest=${tag:-}"
  ;;
download)
  [ -d "$dir" ] || die "choose the Black Ops III (Windows) folder first"
  read -r tag url sha < <(release)
  [ -n "${url:-}" ] && [ -n "${sha:-}" ] || die "cannot reach the boiii release on GitHub"
  step "Downloading boiii.exe $tag"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fL --retry 3 -o "$tmp/boiii.exe" "$url" 2>/dev/null || die "download failed"
  [ "$(shasum -a 256 "$tmp/boiii.exe" | cut -d' ' -f1)" = "$sha" ] || die "boiii.exe does not match its published SHA-256"
  mv -f "$tmp/boiii.exe" "$dir/boiii.exe"
  step "boiii.exe $tag installed in the game folder"
  ;;
*)
  die "usage: boiii.sh status | download | backup <folder> | restore <zip>"
  ;;
esac
