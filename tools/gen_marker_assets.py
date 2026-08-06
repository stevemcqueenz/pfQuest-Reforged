#!/usr/bin/env python3
"""Generate the compass/pin marker housing TGAs (uncompressed 32-bit, pow2).

Two layers per marker, both WHITE so SetVertexColor tints them at runtime --
the fill dark (theme bg), the edge with the theme accent (teal standalone,
GW2 gold when GW2_UI is loaded). One asset set serves both identities.

Diamond plate, 64x64, antialiased edges via distance-based alpha.
Usage: python3 tools/gen_marker_assets.py  (writes img/marker_fill.tga, img/marker_edge.tga)
"""
import struct, os

SIZE = 64
CX = CY = (SIZE - 1) / 2.0
HALF = SIZE * 0.42          # diamond half-diagonal
EDGE_W = 3.0                # border thickness in px
AA = 1.2                    # antialias falloff in px

def diamond_dist(x, y):
    # L1 (Manhattan) distance from center, so the iso-lines are diamonds
    return abs(x - CX) + abs(y - CY)

def alpha_fill(d):
    inner = HALF - EDGE_W
    if d <= inner - AA: return 255
    if d >= inner: return 0
    return int(255 * (inner - d) / AA)

def alpha_edge(d):
    inner, outer = HALF - EDGE_W, HALF
    if inner + AA <= d <= outer - AA: return 255
    if d < inner: return 0
    if d < inner + AA: return int(255 * (d - inner) / AA)
    if d > outer: return 0
    return int(255 * (outer - d) / AA)

def write_tga(path, alpha_fn):
    # header: uncompressed truecolor (type 2), 32bpp, origin top-left (descriptor 0x28)
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    px = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            a = alpha_fn(diamond_dist(x, y))
            px += bytes((255, 255, 255, a))   # BGRA, white
    with open(path, "wb") as f:
        f.write(hdr + px)
    print("wrote %s (%d bytes)" % (path, len(hdr) + len(px)))

os.makedirs("img", exist_ok=True)
write_tga("img/marker_fill.tga", alpha_fill)
write_tga("img/marker_edge.tga", alpha_edge)
