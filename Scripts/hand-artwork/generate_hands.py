#!/usr/bin/env python3
"""Generates the starting geometry for Keyflow's hand illustrations.

Writes Assets/Hands/left-hand.svg and Assets/Hands/right-hand.svg. The SVG
files are the source of truth for the app; this script only produced their
first version from a few anatomical parameters (finger axes, lengths, widths,
joint positions). If the SVGs are later edited by hand, do not re-run it.

Usage: python3 Scripts/hand-artwork/generate_hands.py
"""
import math
import os

W, H = 320, 380  # viewBox of each hand

# Left hand, dorsal view, fingertips up: the thumb is on the right.
# base   centre of the finger where it leaves the webbing
# angle  degrees from vertical (negative leans left)
# length base to tip; wb, wt widths at base and near the tip
FINGERS = {
    "pinky":  dict(base=(91, 202), angle=-16, length=88,  wb=24.5, wt=20.5),
    "ring":   dict(base=(123, 176), angle=-7.5, length=118, wb=27.0, wt=23.0),
    "middle": dict(base=(159, 166), angle=0.5, length=130, wb=27.5, wt=23.5),
    "index":  dict(base=(195, 174), angle=10, length=116, wb=27.5, wt=23.0),
}
THUMB = dict(base=(212, 276), angle=48, length=98, wb=46, wt=29)
ORDER = ["pinky", "ring", "middle", "index"]
WRIST_Y = 372


def add(a, b): return (a[0] + b[0], a[1] + b[1])
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def mul(a, s): return (a[0] * s, a[1] * s)
def lerp(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
def fmt(p): return f"{p[0]:.2f},{p[1]:.2f}"


class Finger:
    """A tapered finger with slight joint bulges and a rounded tip."""

    def __init__(self, base, angle, length, wb, wt, thumb=False):
        a = math.radians(angle)
        self.u = (math.sin(a), -math.cos(a))   # along the finger, towards the tip
        self.n = (math.cos(a), math.sin(a))    # across, to the right
        self.base, self.length, self.wb, self.wt, self.thumb = base, length, wb, wt, thumb
        self.cap = 0.6 * wt
        self.shaft = length - self.cap

    def width(self, t):
        w = self.wb + (self.wt - self.wb) * (t ** 0.8 if self.thumb and t > 0 else t)
        if not self.thumb:
            # Knuckle bulges (PIP, DIP) and slimmer phalanges between them.
            w += 1.0 * math.exp(-((t - 0.47) / 0.07) ** 2)
            w += 0.5 * math.exp(-((t - 0.79) / 0.06) ** 2)
            w -= 0.5 * math.exp(-((t - 0.63) / 0.08) ** 2)
        else:
            w += 0.8 * math.exp(-((t - 0.6) / 0.08) ** 2)
        return w

    def axis(self, t): return add(self.base, mul(self.u, t * self.shaft))

    def edge(self, t, side):  # side -1 left, +1 right
        return add(self.axis(t), mul(self.n, side * self.width(t) / 2))

    def point(self, t, across=0.0):
        return add(self.axis(t), mul(self.n, across * self.width(min(max(t, 0), 1)) / 2))

    def tip(self):
        c = self.axis(1.0)
        return [add(c, add(mul(self.n, self.wt / 2 * math.cos(math.radians(d))),
                           mul(self.u, self.cap * math.sin(math.radians(d)))))
                for d in (152, 120, 90, 60, 28)]

    def outline(self, stations):
        left = [self.edge(t, -1) for t in stations]
        right = [self.edge(t, +1) for t in reversed(stations)]
        return left + self.tip() + right


fingers = {name: Finger(**spec) for name, spec in FINGERS.items()}
thumb = Finger(**THUMB, thumb=True)
STATIONS = (0.0, 0.24, 0.47, 0.63, 0.8, 0.93)


def web(a, b):
    """The webbing between two fingers: a soft U a few units below their bases."""
    pa, pb = a.edge(0, +1), b.edge(0, -1)
    low = max(pa[1], pb[1]) + 4.5
    mid = ((pa[0] + pb[0]) / 2, low)
    return [(pa[0] + 0.6, (pa[1] + low) / 2 + 1.5), mid, (pb[0] - 0.6, (pb[1] + low) / 2 + 1.5)], mid


# ---------------------------------------------------------------- silhouette

def silhouette():
    """Points around the hand, clockwise from the wrist, and the index
    where the wrist edge starts, so the outline can leave it open."""
    p = fingers["pinky"]
    lb = p.edge(0, -1)
    pts = [(111, WRIST_Y), (101, 347), (89, 320), (80.5, 292), (76.5, 264), (lb[0] - 3.6, lb[1] + 36), (lb[0] - 1.8, lb[1] + 15)]
    for i, name in enumerate(ORDER):
        f = fingers[name]
        pts += f.outline(STATIONS)
        if i + 1 < len(ORDER):
            pts += web(f, fingers[ORDER[i + 1]])[0]
    ix = fingers["index"]
    rb = ix.edge(0, +1)
    # First web space: a soft U from the index finger into the thumb.
    a, j = (rb[0] + 0.8, rb[1] + 12), thumb.edge(0.5, -1)
    c = (a[0] + 3, j[1] + 6)
    for t in (0.3, 0.58, 0.82):
        pts.append(lerp(lerp(a, c, t), lerp(c, j, t), t))
    pts += thumb.outline((0.5, 0.66, 0.82, 0.94))
    # Outside of the thumb, then the thenar eminence bulging into the wrist.
    pts += [thumb.edge(0.3, +1), thumb.edge(0.12, +1)]
    o = thumb.edge(-0.06, +1)
    pts += [(o[0] + 2.5, o[1] + 15), (o[0] - 0.5, o[1] + 37), (o[0] - 9, o[1] + 60), (205, WRIST_Y)]
    wrist_start = len(pts) - 1
    pts += [(181, WRIST_Y + 3), (160, WRIST_Y + 4), (138, WRIST_Y + 3)]
    return pts, wrist_start


def bezier_segments(points, closed=True):
    """Catmull-Rom through the points, as cubic Bézier segments."""
    n = len(points)
    P = (lambda i: points[i % n]) if closed else (lambda i: points[max(0, min(n - 1, i))])
    segs = []
    for i in range(n if closed else n - 1):
        p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
        c1 = add(p1, mul(sub(p2, p0), 1 / 6))
        c2 = sub(p2, mul(sub(p3, p1), 1 / 6))
        segs.append((p1, c1, c2, p2))
    return segs


def path_from(segs, closed):
    d = [f"M{fmt(segs[0][0])}"] + [f"C{fmt(c1)} {fmt(c2)} {fmt(p2)}" for _, c1, c2, p2 in segs]
    return "".join(d) + ("Z" if closed else "")


# ------------------------------------------------------------------ regions

def regions():
    """Five finger regions. Each runs from a soft base line at the webbing
    to well beyond the fingertip, with sides up the middle of the gaps
    between fingers. Drawn clipped to the silhouette, so only the base line
    and the shared gap lines shape what is seen."""
    out = {}
    webs = [web(fingers[a], fingers[b])[1] for a, b in zip(ORDER, ORDER[1:])]

    def gap(a, b, w):  # bottom → top
        mid = lerp(a.point(0.55, 1), b.point(0.55, -1), 0.5)
        top = lerp(a.point(1.2), b.point(1.2), 0.5)
        return [w, mid, (top[0], -30)]

    gaps = [gap(fingers[a], fingers[b], w) for (a, b), w in zip(zip(ORDER, ORDER[1:]), webs)]
    p, ix = fingers["pinky"], fingers["index"]
    outer_left = (p.edge(0, -1)[0] - 1.2, p.edge(0, -1)[1] + 10)
    left_side = [(outer_left[0] - 40, outer_left[1]), (outer_left[0] - 40, -30)]
    rb = ix.edge(0, +1)
    inner_right = (rb[0] + 0.8, rb[1] + 12)
    right_side = [(inner_right[0] + 16, inner_right[1]), (ix.point(1.25)[0] + 30, -30)]

    for i, name in enumerate(ORDER):
        f = fingers[name]
        start = outer_left if i == 0 else gaps[i - 1][0]
        end = inner_right if i == len(ORDER) - 1 else gaps[i][0]
        sag = f.point(-0.1)  # the base line dips slightly over the knuckle
        ctrl = (2 * sag[0] - (start[0] + end[0]) / 2, 2 * sag[1] - (start[1] + end[1]) / 2)
        d = f"M{fmt(start)}Q{fmt(ctrl)} {fmt(end)}"
        up = right_side if i == len(ORDER) - 1 else gaps[i][1:]
        down = list(reversed(left_side)) if i == 0 else list(reversed(gaps[i - 1][1:]))
        for q in up + down:
            d += f"L{fmt(q)}"
        out[name] = d + "Z"

    # Thumb: base line from the first web space across the thumb's base to its outer edge.
    j = thumb.edge(0.42, -1)
    o = thumb.edge(-0.02, +1)
    sag = thumb.point(0.1)
    ctrl = (2 * sag[0] - (j[0] + o[0]) / 2, 2 * sag[1] - (j[1] + o[1]) / 2)
    far = add(o, mul(thumb.n, 40))
    out["thumb"] = (f"M{fmt(j)}Q{fmt(ctrl)} {fmt(o)}L{fmt(far)}L{fmt((W + 20, far[1] - 60))}"
                    f"L{fmt((W + 20, -30))}L{fmt(right_side[1])}L{fmt(add(j, mul(thumb.n, -14)))}Z")
    return out, webs


# ------------------------------------------------------------------ details

def crease(center, f, half, bow):
    a, b = add(center, mul(f.n, -half)), add(center, mul(f.n, half))
    return f"M{fmt(a)}Q{fmt(add(center, mul(f.u, bow)))} {fmt(b)}"


def details():
    joints, knuckles, nails, palm = [], [], [], []
    for f in list(fingers.values()) + [thumb]:
        for t in ((0.47, 0.79) if not f.thumb else (0.6,)):
            w = f.width(t)
            joints.append(crease(f.axis(t), f, w * 0.22, -1.5))
            joints.append(crease(add(f.axis(t), mul(f.u, 3.0)), f, w * 0.15, -1.1))
        # Nail: a soft shield near the tip.
        c, hw = f.axis(0.985), f.wt * 0.3
        top = add(c, mul(f.u, f.cap * 0.62))
        side = lambda s, k, f=f, c=c, hw=hw: add(add(c, mul(f.u, f.cap * k)), mul(f.n, s * hw))
        bottom = add(c, mul(f.u, -f.cap * 0.95))
        nails.append(f"M{fmt(side(-1, -0.7))}C{fmt(side(-1, 0.1))} {fmt(side(-0.75, 0.6))} {fmt(top)}"
                     f"C{fmt(side(0.75, 0.6))} {fmt(side(1, 0.1))} {fmt(side(1, -0.7))}"
                     f"Q{fmt(bottom)} {fmt(side(-1, -0.7))}Z")
    # MCP knuckles: soft rises just below each finger.
    for f in fingers.values():
        knuckles.append(crease(f.point(-0.16), f, f.wb * 0.26, -2.0))
    # Extensor tendons fanning from the knuckles towards the wrist.
    wrist = (158, WRIST_Y - 6)
    for f in fingers.values():
        k = f.point(-0.24)
        end = lerp(k, wrist, 0.42)
        mid = lerp(k, end, 0.5)
        palm.append(f"M{fmt(k)}Q{fmt(add(mid, (0, 4)))} {fmt(end)}")
    # The thumb's metacarpal, continuing its axis into the hand.
    a, b = thumb.point(0.05), thumb.point(-0.5)
    palm.append(f"M{fmt(a)}Q{fmt(add(lerp(a, b, 0.5), mul(thumb.n, 3)))} {fmt(b)}")
    return joints, knuckles, nails, palm


def markers():
    pts = {name: f.point(0.6) for name, f in fingers.items()}
    pts["thumb"] = thumb.point(0.44)
    return pts


# --------------------------------------------------------------------- write

def mirror(d):
    """x → W − x for path data made of absolute M L Q C Z commands."""
    out, i, expect_x = [], 0, True
    while i < len(d):
        ch = d[i]
        if ch.isalpha():
            out.append(ch); expect_x = True; i += 1
        elif ch in "-0123456789.":
            j = i + 1
            while j < len(d) and d[j] in "0123456789.": j += 1
            v = float(d[i:j])
            out.append(f"{W - v:.2f}," if expect_x else f"{v:.2f} ")
            expect_x = not expect_x; i = j
        else:
            i += 1
    return "".join(out).replace(" Z", "Z").replace(" C", "C").replace(" L", "L").replace(" Q", "Q").strip()


def svg(side):
    pts, wrist_start = silhouette()
    segs = bezier_segments(pts)
    closed = path_from(segs, True)
    # The outline stops at the wrist, so the arm fades instead of ending in a line.
    outline = path_from(segs[:wrist_start], False)
    regs, _ = regions()
    joints, knuckles, nails, palm = details()
    marks = markers()
    m = mirror if side == "right" else (lambda d: d)
    mx = (lambda p: (W - p[0], p[1])) if side == "right" else (lambda p: p)
    title = "Left hand" if side == "left" else "Right hand"
    T = "  "
    L = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" id="{side}-hand">',
        f'{T}<title>{title}, dorsal view, fingertips up</title>',
        f'{T}<desc>Keyflow finger heatmap artwork. Layers: hand-silhouette (A); finger-regions (B) thumb, index, middle, ring, '
        f'pinky, clipped to the silhouette; anatomy (C); outline; interaction (D) hit regions; markers, anchors for status '
        f'symbols. All layers share this viewBox.</desc>',
        f'{T}<style>',
        f'{T}{T}.hand {{ fill: #F2F2F4; }}',
        f'{T}{T}.region {{ fill: #8E8E93; fill-opacity: 0.08; }}',
        f'{T}{T}.line {{ fill: none; stroke: #6E6E73; stroke-width: 1; stroke-linejoin: round; stroke-linecap: round; }}',
        f'{T}{T}.detail {{ fill: none; stroke: #8E8E93; stroke-opacity: 0.5; stroke-width: 0.7; stroke-linecap: round; }}',
        f'{T}{T}.faint {{ fill: none; stroke: #8E8E93; stroke-opacity: 0.16; stroke-width: 0.8; stroke-linecap: round; }}',
        f'{T}{T}.nail {{ fill: #FFFFFF; fill-opacity: 0.6; stroke: #8E8E93; stroke-opacity: 0.45; stroke-width: 0.6; }}',
        f'{T}{T}.hit {{ fill: transparent; }}',
        f'{T}</style>',
        f'{T}<defs>',
        f'{T}{T}<clipPath id="{side}-hand-clip"><path d="{m(closed)}"/></clipPath>',
        f'{T}{T}<linearGradient id="{side}-wrist-fade" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0.86" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>',
        f'{T}{T}<mask id="{side}-wrist-mask"><rect width="{W}" height="{H}" fill="url(#{side}-wrist-fade)"/></mask>',
        f'{T}</defs>',
        f'{T}<g mask="url(#{side}-wrist-mask)">',
        f'{T}<g id="hand-silhouette">',
        f'{T}{T}<path id="silhouette" class="hand" d="{m(closed)}"/>',
        f'{T}</g>',
        f'{T}<g id="finger-regions" clip-path="url(#{side}-hand-clip)">',
    ]
    for name in ["thumb", "index", "middle", "ring", "pinky"]:
        L.append(f'{T}{T}<path id="{name}" class="region" d="{m(regs[name])}"/>')
    L += [f'{T}</g>', f'{T}<g id="anatomy">']
    for group, cls, items in (("tendons", "faint", palm), ("knuckles", "detail", knuckles),
                              ("joint-creases", "detail", joints), ("nails", "nail", nails)):
        L.append(f'{T}{T}<g id="{group}">')
        L += [f'{T}{T}{T}<path class="{cls}" d="{m(d)}"/>' for d in items]
        L.append(f'{T}{T}</g>')
    L += [f'{T}</g>',
          f'{T}<g id="outline">', f'{T}{T}<path id="silhouette-outline" class="line" d="{m(outline)}"/>', f'{T}</g>',
          f'{T}</g>',
          f'{T}<g id="interaction" clip-path="url(#{side}-hand-clip)">']
    for name in ["thumb", "index", "middle", "ring", "pinky"]:
        L.append(f'{T}{T}<path id="{name}-hit" class="hit" d="{m(regs[name])}"/>')
    L += [f'{T}</g>', f'{T}<g id="markers">']
    for name in ["thumb", "index", "middle", "ring", "pinky"]:
        p = mx(marks[name])
        L.append(f'{T}{T}<circle id="{name}-marker" cx="{p[0]:.2f}" cy="{p[1]:.2f}" r="0"/>')
    L += [f'{T}</g>', '</svg>']
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Assets", "Hands")
    os.makedirs(root, exist_ok=True)
    for side in ("left", "right"):
        with open(os.path.join(root, f"{side}-hand.svg"), "w") as f:
            f.write(svg(side))
    print("Wrote", os.path.normpath(root))
