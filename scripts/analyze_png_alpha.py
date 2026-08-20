#!/usr/bin/env python3
from pathlib import Path
import struct, zlib, collections

paths = [
    Path("/opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem/DimensionalStorageIcon.png"),
    Path("/opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem/42/media/textures/Item_KS_DStorage.png"),
]


def parse_png(path: Path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos = 8
    chunks = []
    while pos < len(data):
        ln = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        cdata = data[pos + 8 : pos + 8 + ln]
        chunks.append((ctype.decode("ascii", "replace"), ln, cdata))
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


def unfilter(raw: bytes, w: int, h: int, bpp: int) -> bytes:
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
    return bytes(out)


def analyze(path: Path):
    print("=" * 60)
    print(path)
    print("size", path.stat().st_size)
    chunks = parse_png(path)
    print("chunks", [(t, l) for t, l, _ in chunks])
    ihdr = chunks[0][2]
    w, h, bit, color, comp, filt, inter = struct.unpack(">IIBBBBB", ihdr)
    color_names = {0: "gray", 2: "RGB", 3: "palette", 4: "grayA", 6: "RGBA"}
    print(f"{w}x{h} bit={bit} color={color}({color_names.get(color)}) inter={inter}")
    idat = b"".join(c for t, l, c in chunks if t == "IDAT")
    raw = zlib.decompress(idat)

    if not (color == 6 and bit == 8 and inter == 0):
        print("unsupported layout for pixel dump")
        return

    pix = unfilter(raw, w, h, 4)
    alphas = [pix[i + 3] for i in range(0, len(pix), 4)]
    uniq = sorted(set(alphas))
    print("alpha min/max/nunique", min(alphas), max(alphas), len(uniq))
    print("alpha unique sample", uniq[:30])
    transparent = semi = opaque = 0
    bg_colors = collections.Counter()
    fg_colors = collections.Counter()
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            r, g, b, a = pix[i], pix[i + 1], pix[i + 2], pix[i + 3]
            if a == 0:
                transparent += 1
                bg_colors[(r, g, b)] += 1
            elif a == 255:
                opaque += 1
                fg_colors[(r, g, b)] += 1
            else:
                semi += 1
                fg_colors[(r, g, b, a)] += 1
    print("pixels transparent/semi/opaque", transparent, semi, opaque)
    print("top bg RGB under a=0", bg_colors.most_common(8))
    print("top fg", fg_colors.most_common(12))

    grayish = []
    for c, n in list(fg_colors.items()) + [(k, v) for k, v in bg_colors.items()]:
        rgb = c[:3]
        if abs(rgb[0] - rgb[1]) < 12 and abs(rgb[1] - rgb[2]) < 12 and 60 <= rgb[0] <= 230:
            grayish.append((rgb, n))
    print("grayish colors", grayish[:10])

    print("alpha map (.=0 +=semi #=255):")
    for y in range(h):
        row = []
        for x in range(w):
            a = pix[(y * w + x) * 4 + 3]
            if a == 0:
                row.append(".")
            elif a == 255:
                row.append("#")
            else:
                row.append("+")
        print("".join(row))


if __name__ == "__main__":
    for p in paths:
        analyze(p)
