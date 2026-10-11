#!/usr/bin/env python3
"""FFCamera LUT generator.

Writes 24 film-style 3D LUTs (Adobe .cube, float values) used by the app.
Pure standard library - reproducible on any machine / CI.

Usage:
    python tools/gen_luts.py --out FFCamera/Resources/LUTs --size 33
"""

import argparse
import os
import time


def clamp(x, lo=0.0, hi=1.0):
    if x < lo:
        return lo
    if x > hi:
        return hi
    return x


def smoothstep(x):
    return x * x * (3.0 - 2.0 * x)


def base(**kw):
    d = dict(
        wr=1.0, wg=1.0, wb=1.0,
        lr=0.0, lg=0.0, lb=0.0,
        contrast=0.0,
        saturation=1.0,
        fade=0.0,
        scurve=0.0,
        shadow_tint=None,
        highlight_tint=None,
        mono=False,
        mono_tint=(1.0, 1.0, 1.0),
    )
    d.update(kw)
    return d


FILTERS = [
    ("ff_01", base(contrast=0.06, saturation=1.05)),
    ("ff_02", base(contrast=-0.04, saturation=0.98, fade=0.01)),
    ("ff_03", base(contrast=0.12, saturation=1.18)),
    ("ff_04", base(contrast=0.02, saturation=0.85)),
    ("ff_05", base(wr=1.03, wb=0.97)),
    ("ff_06", base(wr=0.98, wb=1.04)),
    ("ff_07", base(mono=True, mono_tint=(1.04, 1.00, 0.92), contrast=0.08)),
    ("ff_08", base(fade=0.06, contrast=-0.02, saturation=0.92)),
    ("ff_09", base(shadow_tint=(-0.010, 0.005, 0.030))),
    ("ff_10", base(wr=1.05, wg=1.01, wb=0.94, highlight_tint=(0.030, 0.015, -0.010))),
    ("ff_11", base(mono=True, contrast=0.15)),
    ("ff_12", base(saturation=0.80, fade=0.04, highlight_tint=(0.020, 0.010, 0.000))),
    ("ff_13", base(wr=1.04, lg=0.01, saturation=0.95)),
    ("ff_14", base(wr=1.07, wg=1.02, wb=0.92, fade=0.03)),
    ("ff_15", base(contrast=0.08, saturation=1.10, shadow_tint=(0.020, 0.005, -0.010))),
    ("ff_16", base(wb=1.06, saturation=0.95, contrast=0.05)),
    ("ff_17", base(wb=1.09, wg=1.02, wr=0.96, fade=0.02)),
    ("ff_18", base(fade=0.08, contrast=-0.03, saturation=0.90, highlight_tint=(0.000, 0.005, 0.015))),
    ("ff_19", base(lg=0.02, contrast=-0.02)),
    ("ff_20", base(shadow_tint=(0.000, 0.005, 0.020), fade=0.04)),
    ("ff_21", base(scurve=0.25, saturation=0.95)),
    ("ff_22", base(fade=0.10, saturation=0.85, contrast=-0.05)),
    ("ff_23", base(mono=True, mono_tint=(1.07, 1.00, 0.82), contrast=0.04)),
    ("ff_24", base(shadow_tint=(-0.005, 0.010, 0.040), highlight_tint=(0.020, 0.010, -0.010), fade=0.05, contrast=0.04)),
]


def grade(r, g, b, p):
    r = r * p["wr"] + p["lr"]
    g = g * p["wg"] + p["lg"]
    b = b * p["wb"] + p["lb"]

    c = 1.0 + p["contrast"]
    r = 0.5 + (r - 0.5) * c
    g = 0.5 + (g - 0.5) * c
    b = 0.5 + (b - 0.5) * c

    m = p["scurve"]
    if m > 0.0:
        r = r * (1.0 - m) + smoothstep(clamp(r)) * m
        g = g * (1.0 - m) + smoothstep(clamp(g)) * m
        b = b * (1.0 - m) + smoothstep(clamp(b)) * m

    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    s = p["saturation"]
    r = luma + (r - luma) * s
    g = luma + (g - luma) * s
    b = luma + (b - luma) * s

    st = p["shadow_tint"]
    ht = p["highlight_tint"]
    if st is not None or ht is not None:
        l = clamp(0.2126 * r + 0.7152 * g + 0.0722 * b)
        ws = (1.0 - l) * (1.0 - l)
        wh = l * l
        if st is not None:
            r += st[0] * ws
            g += st[1] * ws
            b += st[2] * ws
        if ht is not None:
            r += ht[0] * wh
            g += ht[1] * wh
            b += ht[2] * wh

    f = p["fade"]
    if f > 0.0:
        r = f + (1.0 - f) * r
        g = f + (1.0 - f) * g
        b = f + (1.0 - f) * b

    if p["mono"]:
        l = 0.2126 * r + 0.7152 * g + 0.0722 * b
        mt = p["mono_tint"]
        r = l * mt[0]
        g = l * mt[1]
        b = l * mt[2]

    return clamp(r), clamp(g), clamp(b)


def write_cube(path, size, params):
    scale = 1.0 / (size - 1)
    lines = []
    lines.append('TITLE "FFCamera %s"' % os.path.splitext(os.path.basename(path))[0])
    lines.append("LUT_3D_SIZE %d" % size)
    for bi in range(size):
        b = bi * scale
        for gi in range(size):
            g = gi * scale
            for ri in range(size):
                r = ri * scale
                rr, gg, bb = grade(r, g, b, params)
                lines.append("%.5f %.5f %.5f" % (rr, gg, bb))
    with open(path, "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines))
        fh.write("\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="FFCamera/Resources/LUTs")
    ap.add_argument("--size", type=int, default=33)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    t0 = time.time()
    total = 0
    for fid, params in FILTERS:
        path = os.path.join(args.out, fid + ".cube")
        write_cube(path, args.size, params)
        total += os.path.getsize(path)
    elapsed = time.time() - t0
    print("wrote %d LUTs (%d^3) to %s in %.1fs, total %.1f MB"
          % (len(FILTERS), args.size, args.out, elapsed, total / 1024.0 / 1024.0))


if __name__ == "__main__":
    main()
