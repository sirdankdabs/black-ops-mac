"""Declare Wine's loader a game, so macOS turns on Game Mode for BO1.

macOS enables Game Mode (CPU/GPU priority for the game, fewer background
tasks, half the Bluetooth latency for mice, keyboards and controllers) only
for a fullscreen app whose Info.plist says LSApplicationCategoryType is a
games category. Wine's loader embeds its Info.plist in a __TEXT,__info_plist
section without one. This adds the key in place, keeping the section's size
by dropping CrossOver's XML comments and indentation.

    python3 -I gamemode-plist.py <path to wine>   (prints "patched" or "already")
"""
import re
import sys

KEY = b"<key>LSApplicationCategoryType</key><string>public.app-category.action-games</string>"
# and the reason it uses the microphone (games' voice chat): without one,
# macOS never answers Wine's request for microphone access and the game waits
MIC = b"<key>NSMicrophoneUsageDescription</key><string>In-game voice chat.</string>"

path = sys.argv[1]
data = bytearray(open(path, "rb").read())
start = data.find(b'<?xml version="1.0"')
end = data.find(b"</plist>", start)
if start < 0 or end < 0:
    sys.exit("no embedded Info.plist")
end += len(b"</plist>")
plist = bytes(data[start:end])
add = b""
if b"LSApplicationCategoryType" not in plist: add += KEY
if b"NSMicrophoneUsageDescription" not in plist: add += MIC
if not add:
    print("already")
    sys.exit(0)
new = re.sub(rb"<!--.*?-->", b"", plist)
new = re.sub(rb">\s+<", b"><", new)
new = new.replace(b"</dict>", add + b"</dict>")
if len(new) > len(plist):
    # make room: entries macOS no longer uses
    new = re.sub(rb"<key>CFBundleSignature</key><string>[^<]*</string>", b"", new)
    new = re.sub(rb"<key>CFBundleAllowMixedLocalizations</key><(true|false)/>", b"", new)
if len(new) > len(plist):
    sys.exit("no room in the embedded Info.plist")
new += b"\n" * (len(plist) - len(new))
data[start:end] = new
open(path, "wb").write(data)
print("patched")
