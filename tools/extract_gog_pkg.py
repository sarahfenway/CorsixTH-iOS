#!/usr/bin/env python3
"""Pull the Theme Hospital game data out of GOG's macOS installer (.pkg).

Usage: extract_gog_pkg.py <theme_hospital_*.pkg> <output folder>

A GOG .pkg is a xar archive. Inside it, the game lives in a gzip-compressed
cpio archive (GOG puts it in "Scripts" rather than the usual "Payload"), as a
DOSBox app whose Resources/game folder holds the original DOS game. Only the
folders CorsixTH needs are written out. Uses only the Python standard library.
"""

import gzip
import io
import os
import stat
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

# Folders CorsixTH reads. ANIMS/INTRO hold the movies, which this build of
# CorsixTH cannot play, so they are left out to keep the app smaller.
WANTED = {"DATA", "DATAM", "QDATA", "QDATAM", "LEVELS", "SOUND"}


class SubFile(io.RawIOBase):
    """Read-only view of part of a file."""

    def __init__(self, f, offset, length):
        self.f, self.start, self.length, self.pos = f, offset, length, 0

    def readable(self):
        return True

    def readinto(self, b):
        n = min(len(b), self.length - self.pos)
        if n <= 0:
            return 0
        self.f.seek(self.start + self.pos)
        data = self.f.read(n)
        b[: len(data)] = data
        self.pos += len(data)
        return len(data)


def xar_entries(f):
    """Yield (path, offset, length, encoding) for each file in a xar archive."""
    magic, header_size, _version, toc_len, _toc_raw_len, _cksum = struct.unpack(
        ">4sHHQQI", f.read(28))
    if magic != b"xar!":
        raise SystemExit("This doesn't look like a macOS .pkg (xar) file.")
    f.seek(header_size)
    toc = ET.fromstring(zlib.decompress(f.read(toc_len)))
    heap = header_size + toc_len

    def walk(element, prefix):
        for entry in element.findall("file"):
            name = entry.findtext("name")
            path = prefix + name
            if entry.findtext("type") == "directory":
                yield from walk(entry, path + "/")
            else:
                data = entry.find("data")
                if data is None:
                    continue
                yield (path, heap + int(data.findtext("offset")),
                       int(data.findtext("length")),
                       data.find("encoding").get("style"))

    yield from walk(toc.find("toc"), "")


def open_entry(f, offset, length, encoding):
    raw = io.BufferedReader(SubFile(f, offset, length), 1 << 20)
    if "gzip" in encoding:
        return io.BufferedReader(gzip.GzipFile(fileobj=raw), 1 << 20)
    return raw


def cpio_files(stream):
    """Yield (name, mode, data) from a cpio archive (odc or newc format)."""
    def read(n):
        b = stream.read(n)
        if len(b) != n:
            raise SystemExit("The installer's archive is truncated.")
        return b

    while True:
        magic = read(6)
        if magic == b"070707":
            h = read(70)
            mode = int(h[12:18], 8)
            namesize = int(h[53:59], 8)
            size = int(h[59:70], 8)
            name = read(namesize)[:-1].decode("utf-8", "replace")
            data = read(size)
        elif magic in (b"070701", b"070702"):
            h = read(104)
            fields = [int(h[i * 8:(i + 1) * 8], 16) for i in range(13)]
            mode, size, namesize = fields[1], fields[6], fields[11]
            name = read(namesize)[:-1].decode("utf-8", "replace")
            read((4 - (110 + namesize) % 4) % 4)
            data = read(size)
            read((4 - size % 4) % 4)
        else:
            raise SystemExit("Unknown archive format inside the installer.")
        if name == "TRAILER!!!":
            return
        yield name, mode, data


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    pkg, out_dir = sys.argv[1], sys.argv[2]
    written = 0
    with open(pkg, "rb") as f:
        archives = [e for e in xar_entries(f)
                    if e[0].split("/")[-1] in ("Scripts", "Payload")]
        for _path, offset, length, encoding in archives:
            stream = open_entry(f, offset, length, encoding)
            head = stream.peek(2)[:2] if hasattr(stream, "peek") else b""
            if head == b"\x1f\x8b":  # The cpio archive is itself gzipped.
                stream = io.BufferedReader(gzip.GzipFile(fileobj=stream), 1 << 20)
            for name, mode, data in cpio_files(stream):
                if not stat.S_ISREG(mode):
                    continue
                if name.upper().endswith((".EXE", ".COM", ".BAT")):
                    continue  # DOS programs; CorsixTH doesn't need them.
                parts = os.path.normpath(name).split(os.sep)
                # .../Resources/game/<DATA folder>/... -> <out>/<DATA folder>/...
                for i, part in enumerate(parts[:-1]):
                    if part.upper() in WANTED and i > 0 and parts[i - 1].lower() == "game":
                        rel = parts[i:]
                        if any(p in ("", ".", "..") for p in rel):
                            break
                        dest = os.path.join(out_dir, *rel)
                        os.makedirs(os.path.dirname(dest), exist_ok=True)
                        with open(dest, "wb") as out:
                            out.write(data)
                        written += 1
                        break
    if written == 0:
        raise SystemExit("Couldn't find the Theme Hospital data in that installer.")
    print(f"Extracted {written} game files to {out_dir}")


if __name__ == "__main__":
    main()
