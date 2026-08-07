#!/usr/bin/env python3
"""Generate the compass/pin marker housing TGAs (uncompressed 32-bit, pow2).

All art is WHITE so SetVertexColor/SetGradientAlpha tints it at runtime --
one asset set serves both identities (teal standalone, GW2 gold when GW2_UI
is loaded). Idempotent: re-running rewrites byte-identical files.

  marker_fill / marker_edge  64x64 diamond plate, two layers (fill dark via
                             theme bg, edge via the theme accent), antialiased
                             via L1-distance alpha.
  marker_glow                64x64 soft radial glow for the ADD-blended halo
                             behind a plate: smooth (1-r^2)^2 falloff to zero
                             at the rim (zero-slope rim, no visible edge).
  beam_soft                  32x256 vertical light-shaft strip: horizontally a
                             bright narrow core with gaussian falloff to fully
                             transparent edges; vertically FULL alpha -- the
                             runtime SetGradientAlpha keeps owning the vertical
                             fade, so beam height scaling behaves exactly as
                             with the old solid strip.

Usage: python3 tools/gen_marker_assets.py   (writes into img/)
"""
import math, struct, os

SIZE = 64
CX = CY = (SIZE - 1) / 2.0
HALF = SIZE * 0.42          # diamond half-diagonal
EDGE_W = 3.0                # border thickness in px
AA = 1.2                    # antialias falloff in px

def diamond_dist(x, y):
    # L1 (Manhattan) distance from center, so the iso-lines are diamonds
    return abs(x - CX) + abs(y - CY)

def alpha_fill(x, y):
    d = diamond_dist(x, y)
    inner = HALF - EDGE_W
    if d <= inner - AA: return 255
    if d >= inner: return 0
    return int(255 * (inner - d) / AA)

def alpha_edge(x, y):
    d = diamond_dist(x, y)
    inner, outer = HALF - EDGE_W, HALF
    if inner + AA <= d <= outer - AA: return 255
    if d < inner: return 0
    if d < inner + AA: return int(255 * (d - inner) / AA)
    if d > outer: return 0
    return int(255 * (outer - d) / AA)

def alpha_glow(x, y):
    # radial (1-r^2)^2: smooth quadratic-of-quadratic falloff, gaussian-ish,
    # reaching zero WITH zero slope at the rim so the ADD blend never shows a
    # circular edge
    dx, dy = x - CX, y - CY
    r = math.sqrt(dx * dx + dy * dy) / (SIZE * 0.5 - 0.5)
    if r >= 1.0: return 0
    t = 1.0 - r * r
    return int(255 * t * t)

BEAM_W, BEAM_H = 32, 256
BEAM_SIGMA = BEAM_W / 5.0   # gaussian sigma: core ~6px bright, edges ~0

def alpha_beam(x, y):
    # horizontal gaussian profile, vertically constant (full alpha); clamp the
    # sub-1% tail to 0 so the outermost columns are exactly transparent
    dx = x - (BEAM_W - 1) / 2.0
    a = math.exp(-(dx / BEAM_SIGMA) ** 2)
    v = int(255 * a)
    return v if v >= 3 else 0

def write_tga(path, w, h, alpha_fn):
    # header: uncompressed truecolor (type 2), 32bpp, origin top-left (descriptor 0x28)
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    px = bytearray()
    for y in range(h):
        for x in range(w):
            a = alpha_fn(x, y)
            px += bytes((255, 255, 255, a))   # BGRA, white
    with open(path, "wb") as f:
        f.write(hdr + px)
    print("wrote %s (%d bytes)" % (path, len(hdr) + len(px)))

def verify(path, w, h):
    # machine-verify the header the client will parse: type 2, 32bpp, pow2 dims
    with open(path, "rb") as f:
        hdr = f.read(18)
    idl, cmap, itype, _, _, _, _, _, iw, ih, bpp, desc = struct.unpack("<BBBHHBHHHHBB", hdr)
    assert itype == 2 and bpp == 32 and (iw, ih) == (w, h), path
    assert iw & (iw - 1) == 0 and ih & (ih - 1) == 0, path + " not pow2"
    assert os.path.getsize(path) == 18 + iw * ih * 4, path + " truncated"
    print("ok    %s (%dx%d, 32bpp, uncompressed, pow2)" % (path, iw, ih))

os.makedirs("img", exist_ok=True)
write_tga("img/marker_fill.tga", SIZE, SIZE, alpha_fill)
write_tga("img/marker_edge.tga", SIZE, SIZE, alpha_edge)
write_tga("img/marker_glow.tga", SIZE, SIZE, alpha_glow)
write_tga("img/beam_soft.tga", BEAM_W, BEAM_H, alpha_beam)
verify("img/marker_fill.tga", SIZE, SIZE)
verify("img/marker_edge.tga", SIZE, SIZE)
verify("img/marker_glow.tga", SIZE, SIZE)
verify("img/beam_soft.tga", BEAM_W, BEAM_H)
