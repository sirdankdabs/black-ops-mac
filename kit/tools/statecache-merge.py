#!/usr/bin/python3 -I
"""Merge DXVK state caches (v8+ format) into one, without duplicates.

    statecache-merge.py <target> <source>...

Adds every valid entry of the sources that the target lacks. DXVK compiles
all of a state cache's pipelines when the game starts, so a cache gathered
on every map (an older install's, Precompile Shaders') means no pipeline
is compiled for the first time while playing.
"""
import hashlib
import os
import struct
import sys

HEADER = 12


def entries(path):
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None, []
    if len(data) < HEADER or data[:4] != b"DXVK":
        return None, []
    version = struct.unpack_from("<I", data, 4)[0]
    if version < 8:
        return version, []
    out, pos = [], HEADER
    while pos + 24 <= len(data):
        word = struct.unpack_from("<I", data, pos)[0]
        size = word >> 8
        end = pos + 24 + size
        if end > len(data):
            break
        body = data[pos + 24:end]
        if hashlib.sha1(body).digest() == data[pos + 4:pos + 24]:
            out.append(data[pos:end])
        pos = end
    return version, out


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    target = sys.argv[1]
    version, have = entries(target)
    known = {e[4:24] for e in have}
    added = []
    for src in sys.argv[2:]:
        if os.path.realpath(src) == os.path.realpath(target):
            continue
        v, es = entries(src)
        if v is None or (version is not None and v != version):
            continue
        version = v if version is None else version
        for e in es:
            if e[4:24] not in known:
                known.add(e[4:24])
                added.append(e)
    if not added:
        print("state cache: %d pipelines" % len(have))
        return
    tmp = "%s.%d.tmp" % (target, os.getpid())
    with open(tmp, "wb") as f:
        f.write(b"DXVK" + struct.pack("<II", version, 0))
        for e in have + added:
            f.write(e)
    os.replace(tmp, target)
    print("state cache: %d pipelines (%d added)" % (len(have) + len(added), len(added)))


main()
