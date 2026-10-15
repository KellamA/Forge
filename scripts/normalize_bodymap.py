"""Convert react-native-body-highlighter path data into a normalized JSON body map.

Every path is rewritten with absolute M/L/C/Q/Z commands only (arcs become cubics),
and each figure is shifted so that its viewBox starts at (0, 0).
Usage: python3 -I normalize_bodymap.py <package/dist dir> <output.json>
"""
import json
import math
import re
import sys

NUM_RE = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")


def tokenize(d):
    i, n = 0, len(d)
    tokens = []
    while i < n:
        ch = d[i]
        if ch.isalpha():
            tokens.append(ch)
            i += 1
        elif ch in " ,\t\n\r":
            i += 1
        else:
            m = NUM_RE.match(d, i)
            if not m:
                raise ValueError(f"bad char {ch!r} at {i}: {d[i:i+20]}")
            tokens.append(m.group(0))
            i = m.end()
    return tokens


def split_arc_flags(tokens):
    """Arc flags may be packed ("012.89" == 0, 1, 2.89). Re-split them."""
    out = []
    cmd = None
    argi = 0
    for t in tokens:
        if t.isalpha():
            cmd = t
            argi = 0
            out.append(t)
            continue
        if cmd in ("a", "A"):
            pos = argi % 7
            if pos in (3, 4) and len(t) > 1 and t[0] in "01" and not t.startswith(("0.", "1.")):
                # packed flag(s)
                rest = t
                while rest and argi % 7 in (3, 4) and rest[0] in "01":
                    out.append(rest[0])
                    rest = rest[1:]
                    argi += 1
                    if rest.startswith("."):
                        break
                if rest:
                    out.append(rest)
                    argi += 1
                continue
            out.append(t)
            argi += 1
        else:
            out.append(t)
            argi += 1
    return out


def arc_to_cubics(x1, y1, rx, ry, phi_deg, fa, fs, x2, y2):
    if (x1, y1) == (x2, y2):
        return []
    if rx == 0 or ry == 0:
        return [("L", x2, y2)]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(phi_deg)
    cos_p, sin_p = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cos_p * dx + sin_p * dy
    y1p = -sin_p * dx + cos_p * dy
    lam = (x1p ** 2) / (rx ** 2) + (y1p ** 2) / (ry ** 2)
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    coef = math.sqrt(max(0, num / den)) if den else 0
    if fa == fs:
        coef = -coef
    cxp = coef * (rx * y1p / ry)
    cyp = coef * (-ry * x1p / rx)
    cx = cos_p * cxp - sin_p * cyp + (x1 + x2) / 2
    cy = sin_p * cxp + cos_p * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        ln = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1, min(1, dot / ln)))
        if ux * vy - uy * vx < 0:
            a = -a
        return a

    t1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not fs and dt > 0:
        dt -= 2 * math.pi
    elif fs and dt < 0:
        dt += 2 * math.pi
    segs = max(1, int(math.ceil(abs(dt) / (math.pi / 2))))
    delta = dt / segs
    k = 4 / 3 * math.tan(delta / 4)
    out = []
    t = t1
    for _ in range(segs):
        c1, s1 = math.cos(t), math.sin(t)
        c2, s2 = math.cos(t + delta), math.sin(t + delta)
        p1 = (c1 - k * s1, s1 + k * c1)
        p2 = (c2 + k * s2, s2 - k * c2)
        p3 = (c2, s2)

        def tr(p):
            x = rx * p[0]
            y = ry * p[1]
            return (cos_p * x - sin_p * y + cx, sin_p * x + cos_p * y + cy)

        a, b, c = tr(p1), tr(p2), tr(p3)
        out.append(("C", a[0], a[1], b[0], b[1], c[0], c[1]))
        t += delta
    return out


def normalize(d, ox, oy):
    toks = split_arc_flags(tokenize(d))
    i = 0
    cmds = []
    cx = cy = sx = sy = 0.0
    last_c2 = None  # last cubic control point for S
    last_q = None  # last quad control point for T
    cmd = None

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]
            i += 1
            if cmd in "zZ":
                cmds.append(("Z",))
                cx, cy = sx, sy
                last_c2 = last_q = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            x, y = num(), num()
            if rel:
                x, y = cx + x, cy + y
            cmds.append(("M", x, y))
            cx, cy = sx, sy = x, y
            cmd = "l" if rel else "L"
            last_c2 = last_q = None
        elif c == "L":
            x, y = num(), num()
            if rel:
                x, y = cx + x, cy + y
            cmds.append(("L", x, y))
            cx, cy = x, y
            last_c2 = last_q = None
        elif c == "H":
            x = num()
            if rel:
                x = cx + x
            cmds.append(("L", x, cy))
            cx = x
            last_c2 = last_q = None
        elif c == "V":
            y = num()
            if rel:
                y = cy + y
            cmds.append(("L", cx, y))
            cy = y
            last_c2 = last_q = None
        elif c == "C":
            vals = [num() for _ in range(6)]
            if rel:
                vals = [vals[j] + (cx if j % 2 == 0 else cy) for j in range(6)]
            cmds.append(("C", *vals))
            last_c2 = (vals[2], vals[3])
            cx, cy = vals[4], vals[5]
            last_q = None
        elif c == "S":
            vals = [num() for _ in range(4)]
            if rel:
                vals = [vals[j] + (cx if j % 2 == 0 else cy) for j in range(4)]
            if last_c2:
                c1 = (2 * cx - last_c2[0], 2 * cy - last_c2[1])
            else:
                c1 = (cx, cy)
            cmds.append(("C", c1[0], c1[1], *vals))
            last_c2 = (vals[0], vals[1])
            cx, cy = vals[2], vals[3]
            last_q = None
        elif c == "Q":
            vals = [num() for _ in range(4)]
            if rel:
                vals = [vals[j] + (cx if j % 2 == 0 else cy) for j in range(4)]
            cmds.append(("Q", *vals))
            last_q = (vals[0], vals[1])
            cx, cy = vals[2], vals[3]
            last_c2 = None
        elif c == "T":
            x, y = num(), num()
            if rel:
                x, y = cx + x, cy + y
            q1 = (2 * cx - last_q[0], 2 * cy - last_q[1]) if last_q else (cx, cy)
            cmds.append(("Q", q1[0], q1[1], x, y))
            last_q = q1
            cx, cy = x, y
            last_c2 = None
        elif c == "A":
            rx, ry, rot, fa, fs, x, y = (num() for _ in range(7))
            if rel:
                x, y = cx + x, cy + y
            cmds.extend(arc_to_cubics(cx, cy, rx, ry, rot, int(fa), int(fs), x, y))
            cx, cy = x, y
            last_c2 = last_q = None
        else:
            raise ValueError(f"unsupported command {cmd}")

    def fmt(v):
        s = f"{v:.2f}".rstrip("0").rstrip(".")
        return "0" if s == "-0" else s

    parts = []
    xs, ys = [], []
    for c in cmds:
        if c[0] == "Z":
            parts.append("Z")
            continue
        coords = list(c[1:])
        for j in range(0, len(coords), 2):
            coords[j] += ox
            coords[j + 1] += oy
            xs.append(coords[j])
            ys.append(coords[j + 1])
        parts.append(c[0] + " " + " ".join(fmt(v) for v in coords))
    bbox = [round(min(xs), 1), round(min(ys), 1), round(max(xs), 1), round(max(ys), 1)] if xs else None
    return " ".join(parts), bbox


BLOCK_RE = re.compile(r'slug:\s*"([a-z-]+)"(.*?)(?=slug:|\Z)', re.S)
KEY_RE = re.compile(r'(left|right|common):\s*\[(.*?)\]', re.S)
STR_RE = re.compile(r'"([^"]+)"')


def load_regions(path, ox, oy):
    src = open(path).read()
    regions = []
    for slug, body in BLOCK_RE.findall(src):
        for side, arr in KEY_RE.findall(body):
            for d in STR_RE.findall(arr):
                nd, bbox = normalize(d, ox, oy)
                regions.append({"slug": slug, "side": side, "d": nd, "bbox": bbox})
    return regions


def load_outlines(path):
    src = open(path).read()
    front = re.search(r'side === "front" && \(<react_native_svg_1\.Path[^>]*?d="([^"]+)"', src, re.S)
    back = re.search(r'side === "back" && \(<react_native_svg_1\.Path[^>]*?d="([^"]+)"', src, re.S)
    return front.group(1), back.group(1)


def main():
    dist, out = sys.argv[1], sys.argv[2]
    result = {}
    configs = {
        "male": {
            "wrapper": "components/SvgMaleWrapper.js",
            "front": ("assets/bodyFront.js", 0, 0, 724, 1448),
            "back": ("assets/bodyBack.js", -724, 0, 724, 1448),
        },
        "female": {
            "wrapper": "components/SvgFemaleWrapper.js",
            "front": ("assets/bodyFemaleFront.js", 50, 40, 734, 1538),
            "back": ("assets/bodyFemaleBack.js", -756, 0, 774, 1448),
        },
    }
    for model, cfg in configs.items():
        fo, bo = load_outlines(f"{dist}/{cfg['wrapper']}")
        result[model] = {}
        for view, outline in (("front", fo), ("back", bo)):
            file, ox, oy, w, h = cfg[view]
            regions = load_regions(f"{dist}/{file}", ox, oy)
            od, _ = normalize(outline, ox, oy)
            result[model][view] = {"width": w, "height": h, "outline": od, "regions": regions}
    with open(out, "w") as f:
        json.dump(result, f, separators=(",", ":"))
    for model in result:
        for view in result[model]:
            regs = result[model][view]["regions"]
            print(model, view, len(regs), "regions")
            for r in regs:
                if r["slug"] in ("upper-back", "trapezius", "deltoids", "lower-back"):
                    print("   ", r["slug"], r["side"], r["bbox"])


if __name__ == "__main__":
    main()
