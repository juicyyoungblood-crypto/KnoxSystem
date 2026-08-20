#!/usr/bin/env python3
"""Convert baked checkerboard 'fake transparency' to true PNG alpha.

Detects light near-neutral gray background (Photoshop/GIMP checker look)
and sets alpha=0. Keeps colored icon pixels; softens near-bg edges.
"""
from __future__ import annotations

from pathlib import Path
import struct
import zlib
import collections
import math

ROOT = Path("/opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem")
SRC_CANDIDATES = [
    ROOT / "DimensionalStorageIcon.png",
    ROOT / "42/media/textures/Item_KS_DStorage.png",
]
OUT_TEXTURE = ROOT / "42/media/textures/Item_KS_DStorage.png"
OUT_SOURCE = ROOT / "DimensionalStorageIcon.png"
BACKUP_DIR = ROOT / "_icon_backups"


def parse_png(path: Path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos = 8
    chunks = []
    while pos < len(data):
        ln = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        cdata = data[pos + 8 : pos + 8 + ln]
        chunks.append((ctype.decode("ascii", "replace"), cdata))
        pos += 12 + ln
        if ctype == b"IEND":
            break
    return chunks


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def unfilter(raw: bytes, w: int, h: int, bpp: int) -> bytearray:
    stride = w * bpp
    out = bytearray()
    i = 0
    prev = bytearray(stride)
    for _y in range(h):
        f = raw[i]
        i += 1
        scan = bytearray(raw[i : i + stride])
        i += stride
        if f == 0:
            pass
        elif f == 1:
            for x in range(stride):
                left = scan[x - bpp] if x >= bpp else 0
                scan[x] = (scan[x] + left) & 255
        elif f == 2:
            for x in range(stride):
                scan[x] = (scan[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                left = scan[x - bpp] if x >= bpp else 0
                up = prev[x]
                scan[x] = (scan[x] + ((left + up) // 2)) & 255
        elif f == 4:
            for x in range(stride):
                left = scan[x - bpp] if x >= bpp else 0
                up = prev[x]
                upleft = prev[x - bpp] if x >= bpp else 0
                scan[x] = (scan[x] + paeth(left, up, upleft)) & 255
        else:
            raise ValueError(f"bad filter {f}")
        out.extend(scan)
        prev = scan
    return out


def load_rgba(path: Path):
    chunks = parse_png(path)
    w, h, bit, color, comp, filt, inter = struct.unpack(">IIBBBBB", chunks[0][1])
    if not (bit == 8 and color == 6 and inter == 0):
        raise ValueError(f"need 8-bit RGBA non-interlaced, got {w}x{h} bit={bit} color={color}")
    idat = b"".join(c for t, c in chunks if t == "IDAT")
    raw = zlib.decompress(idat)
    pix = unfilter(raw, w, h, 4)
    return w, h, pix


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def save_rgba(path: Path, w: int, h: int, pix: bytes | bytearray):
    # filter 0 rows
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw.extend(pix[y * stride : (y + 1) * stride])
    compressed = zlib.compress(bytes(raw), 9)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def is_checker_bg(r, g, b, a=255) -> bool:
    """Light near-neutral gray typical of baked transparency checkers."""
    # already transparent stays transparent
    if a < 8:
        return True
    mx, mn = max(r, g, b), min(r, g, b)
    chroma = mx - mn
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    # checker cells are light grays ~180-255 with very low chroma
    # also catch slightly dirty grays from compression
    if chroma <= 18 and luma >= 170:
        return True
    # mid checker board sometimes ~128-170
    if chroma <= 12 and 120 <= luma < 170:
        return True
    return False


def color_score_purpleish(r, g, b) -> float:
    """Higher = more likely part of the mystic purple star."""
    # purple/magenta: R and B high relative to G
    if max(r, g, b) < 40:
        return 0.0
    return (r + b) / 2.0 - g + (b - g) * 0.25


def convert(pix: bytearray, w: int, h: int) -> bytearray:
    out = bytearray(pix)
    bg_mask = [[False] * w for _ in range(h)]
    fg_count = bg_count = 0

    # pass 1: hard classify
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            r, g, b, a = out[i], out[i + 1], out[i + 2], out[i + 3]
            if is_checker_bg(r, g, b, a):
                bg_mask[y][x] = True
                bg_count += 1
            else:
                fg_count += 1

    # pass 1b: flood-fill from corners/edges only through bg_mask so interior
    # gray-ish star glow isn't wiped if any. Checker is connected to borders.
    from collections import deque

    visited = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg_mask[y][x] and not visited[y][x]:
                visited[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if bg_mask[y][x] and not visited[y][x]:
                visited[y][x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and bg_mask[ny][nx] and not visited[ny][nx]:
                visited[ny][nx] = True
                q.append((nx, ny))

    # only border-connected bg is true background
    true_bg = visited
    border_bg = sum(1 for y in range(h) for x in range(w) if true_bg[y][x])

    # pass 2: set alpha
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            if true_bg[y][x]:
                # pure transparent; zero RGB for clean premultiplied-ish consumers
                out[i] = out[i + 1] = out[i + 2] = 0
                out[i + 3] = 0
            else:
                # keep color; ensure fully opaque unless already semi
                if out[i + 3] == 0:
                    out[i + 3] = 255

    # pass 3: edge feather — pixels adjacent to true bg with weak purple get partial alpha
    # helps kill checker fringing without eroding the star core
    work = bytearray(out)
    for y in range(h):
        for x in range(w):
            if true_bg[y][x]:
                continue
            i = (y * w + x) * 4
            r, g, b = work[i], work[i + 1], work[i + 2]
            # neighbor bg?
            near_bg = False
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h and true_bg[ny][nx]:
                    near_bg = True
                    break
            if not near_bg:
                continue
            score = color_score_purpleish(r, g, b)
            chroma = max(r, g, b) - min(r, g, b)
            # leftover dirty gray fringe next to checker
            if chroma < 25 and score < 20:
                work[i] = work[i + 1] = work[i + 2] = 0
                work[i + 3] = 0
            elif chroma < 40 and score < 35:
                # soft edge
                work[i + 3] = min(work[i + 3], 140)

    alphas = [work[i + 3] for i in range(0, len(work), 4)]
    print(
        f"classified fg={fg_count} hard_bg={bg_count} border_bg={border_bg} "
        f"final transparent={sum(1 for a in alphas if a == 0)} "
        f"semi={sum(1 for a in alphas if 0 < a < 255)} opaque={sum(1 for a in alphas if a == 255)}"
    )
    return work


def summarize(path: Path, w, h, pix):
    alphas = [pix[i + 3] for i in range(0, len(pix), 4)]
    fg = collections.Counter()
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            if pix[i + 3] > 0:
                fg[(pix[i], pix[i + 1], pix[i + 2])] += 1
    print(path.name, f"{w}x{h}", "alpha", min(alphas), max(alphas), "transparent", sum(a == 0 for a in alphas))
    print(" top fg", fg.most_common(6))


def main():
    # Prefer texture path if identical sources exist
    src = None
    for p in SRC_CANDIDATES:
        if p.exists():
            src = p
            break
    if src is None:
        raise SystemExit("no source icon found")

    w, h, pix = load_rgba(src)
    print("source", src, f"{w}x{h}")
    alphas = [pix[i + 3] for i in range(0, len(pix), 4)]
    print("before alpha unique", sorted(set(alphas))[:10], "transparent", sum(a == 0 for a in alphas))

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    for p in SRC_CANDIDATES:
        if p.exists():
            bak = BACKUP_DIR / (p.name + ".bak")
            if not bak.exists():
                bak.write_bytes(p.read_bytes())
                print("backup", bak)

    out = convert(bytearray(pix), w, h)
    save_rgba(OUT_TEXTURE, w, h, out)
    save_rgba(OUT_SOURCE, w, h, out)

    # verify
    for p in (OUT_TEXTURE, OUT_SOURCE):
        ww, hh, pp = load_rgba(p)
        summarize(p, ww, hh, pp)
        # alpha map
        print("alpha map:")
        for y in range(hh):
            row = []
            for x in range(ww):
                a = pp[(y * ww + x) * 4 + 3]
                row.append("." if a == 0 else ("+" if a < 255 else "#"))
            print("".join(row))


if __name__ == "__main__":
    main()
