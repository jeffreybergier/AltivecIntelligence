#!/usr/bin/env python3
"""Regenerate libs/cocoa/AIFontAwesome.h's AIFontAwesomeIcon enum.

Names and code points are read *directly out of the bundled
Resources/Fonts/FA7-Solid-900.otf* -- the cmap gives codepoint -> glyph id,
the CFF charset gives glyph id -> v7 glyph name. Nothing is copied from any
cheat sheet, so the enum can never drift from the font we actually ship.

Usage:  python3 libs/cocoa/tools/gen_aifontawesome_icons.py
(stdlib only; no fonttools dependency, runs on the build host's python3.)
"""
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "Resources/Fonts/FA7-Solid-900.otf")
HEADER = os.path.join(ROOT, "AIFontAwesome.h")


def u16(b, o):
    return struct.unpack(">H", b[o:o + 2])[0]


def u32(b, o):
    return struct.unpack(">I", b[o:o + 4])[0]


def tables(d):
    n = u16(d, 4)
    out = {}
    o = 12
    for _ in range(n):
        out[d[o:o + 4]] = u32(d, o + 8)
        o += 16
    return out


def load_cmap(d, off):
    n = u16(d, off + 2)
    sub = None
    for i in range(n):
        rec = off + 4 + i * 8
        pid, eid = u16(d, rec), u16(d, rec + 2)
        if (pid == 3 and eid in (1, 10)) or pid == 0:
            sub = off + u32(d, rec + 4)
    fmt = u16(d, sub)
    m = {}
    if fmt == 4:
        segx2 = u16(d, sub + 6)
        segc = segx2 // 2
        endo = sub + 14
        starto = endo + segx2 + 2
        deltao = starto + segx2
        rangeo = deltao + segx2
        for s in range(segc):
            end = u16(d, endo + s * 2)
            start = u16(d, starto + s * 2)
            delta = u16(d, deltao + s * 2)
            ro = u16(d, rangeo + s * 2)
            for c in range(start, end + 1):
                if c == 0xFFFF:
                    continue
                if ro == 0:
                    g = (c + delta) & 0xFFFF
                else:
                    g = u16(d, rangeo + s * 2 + ro + (c - start) * 2)
                    if g:
                        g = (g + delta) & 0xFFFF
                if g:
                    m[c] = g
    elif fmt == 12:
        ng = u32(d, sub + 12)
        for i in range(ng):
            go = sub + 16 + i * 12
            sc, ec, sg = u32(d, go), u32(d, go + 4), u32(d, go + 8)
            for c in range(sc, ec + 1):
                m[c] = sg + (c - sc)
    return m


def cff_index(d, off):
    count = u16(d, off)
    if count == 0:
        return [], off + 2
    osz = d[off + 2]
    base = off + 3
    offs = []
    for i in range(count + 1):
        p = base + i * osz
        v = 0
        for b in d[p:p + osz]:
            v = (v << 8) | b
        offs.append(v)
    db = base + (count + 1) * osz - 1
    items = [d[db + offs[i]:db + offs[i + 1]] for i in range(count)]
    return items, db + offs[-1]


def cff_dict(b):
    ops, operands, i = {}, [], 0
    while i < len(b):
        c = b[i]
        if c <= 21:
            op = c
            i += 1
            if c == 12:
                op = 1200 + b[i]
                i += 1
            ops[op] = operands
            operands = []
        elif c == 28:
            operands.append(struct.unpack(">h", b[i + 1:i + 3])[0])
            i += 3
        elif c == 29:
            operands.append(struct.unpack(">i", b[i + 1:i + 5])[0])
            i += 5
        elif c == 30:
            i += 1
            while i < len(b):
                hi, lo = b[i] >> 4, b[i] & 0xF
                i += 1
                if hi == 0xF or lo == 0xF:
                    break
            operands.append(0.0)
        elif 32 <= c <= 246:
            operands.append(c - 139)
            i += 1
        elif 247 <= c <= 250:
            operands.append((c - 247) * 256 + b[i + 1] + 108)
            i += 2
        elif 251 <= c <= 254:
            operands.append(-(c - 251) * 256 - b[i + 1] - 108)
            i += 2
        else:
            i += 1
    return ops


def glyph_names(d, cff):
    p = cff + d[cff + 2]
    _, p = cff_index(d, p)            # Name INDEX
    topdicts, p = cff_index(d, p)     # Top DICT INDEX
    strings, p = cff_index(d, p)      # String INDEX
    top = cff_dict(topdicts[0])
    nglyphs = u16(d, cff + top[17][0])
    cs_off = cff + top[15][0]
    gid2sid = {0: 0}
    fmt = d[cs_off]
    q = cs_off + 1
    gid = 1
    if fmt == 0:
        while gid < nglyphs:
            gid2sid[gid] = u16(d, q)
            q += 2
            gid += 1
    elif fmt in (1, 2):
        while gid < nglyphs:
            first = u16(d, q)
            q += 2
            if fmt == 1:
                nleft = d[q]
                q += 1
            else:
                nleft = u16(d, q)
                q += 2
            for k in range(nleft + 1):
                if gid >= nglyphs:
                    break
                gid2sid[gid] = first + k
                gid += 1

    def name(sid):
        if sid == 0:
            return ".notdef"
        if sid < 391:
            return "std%d" % sid
        j = sid - 391
        return strings[j].decode("latin1") if j < len(strings) else "sid%d" % sid

    return {g: name(s) for g, s in gid2sid.items()}


def camel(n):
    return "AIFA" + "".join(
        p[:1].upper() + p[1:] for p in n.replace(".", "-").split("-") if p)


def main():
    if not os.path.exists(FONT):
        sys.exit("font not found: %s" % FONT)
    d = open(FONT, "rb").read()
    t = tables(d)
    cmap = load_cmap(d, t[b"cmap"])
    g2n = glyph_names(d, t[b"CFF "])

    cp2name = {}
    for cp, g in cmap.items():
        if 0xE000 <= cp <= 0xF8FF and g in g2n:
            cp2name[cp] = g2n[g]

    seen = {}
    rows = []
    for cp in sorted(cp2name):
        ident = camel(cp2name[cp])
        if ident in seen:        # alias codepoint of an already-listed icon
            continue
        seen[ident] = cp
        rows.append((ident, cp))

    body = "\n".join("  %-30s = 0x%04X," % r for r in rows)
    body = body[:body.rfind(",")] + body[body.rfind(",") + 1:]

    src = open(HEADER).read()
    head = src[:src.index("typedef enum {") + len("typedef enum {")]
    tail = src[src.index("} AIFontAwesomeIcon;"):]
    open(HEADER, "w").write(head + "\n" + body + "\n" + tail)
    print("wrote %d icons to %s" % (len(rows), HEADER))


if __name__ == "__main__":
    main()
