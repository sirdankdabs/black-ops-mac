#!/bin/bash
# Black Ops Mac: boiii.exe, the BOIII / Ezz community client for the Windows
# version of Black Ops III (github.com/Ezz-lol/boiii-free).
#
#   boiii.sh status     installed=<sha> latest=<release tag>
#   boiii.sh download   the latest release's boiii.exe into the game folder,
#                       checked against the SHA-256 GitHub publishes for it
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

case "${1:-}" in
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
  die "usage: boiii.sh status | download"
  ;;
esac
