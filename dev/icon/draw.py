"""Draw AppIcon.svg: a gnomon standing on half a sundial's dial, in one color on black.

The drawing is built from a few rules rather than tuned by eye, so each number follows from them:

- The dial is always exactly half an oval: an invisible line through its center cuts it, and the
  cut ends of its rim lie along that line. Where the line cuts the tail decides how far the top
  runs on, through the gnomon.
- The gnomon's straight edge lies along that same line, so the cut and the gnomon read as one
  diagonal, and is one radius long. Its base is that edge divided by the golden ratio. Its back is
  one curve from the tip that lands flat on the base, so all three tips come to points. The outline
  rounds its corner outward, so the gnomon is slid until the outline's outer edges meet at the
  dial's center.
- The half dial is filled with a faint wash of the ink.
- The base is centered across the icon, the padding is even left and right (the cut's angle is
  solved for that), and the drawing is centered top to bottom.

An unfilled dial cut along the gnomon's edge read as a pointy tail; the fill fixed that. Cutting
the dial at a different angle from the gnomon instead left a sliver of dial above the gnomon's
edge. Run render.sh afterwards.
"""
import math, pathlib

PHI = (1 + 5 ** 0.5) / 2
ASPECT = 0.5        # the dial's height against its width: rounder put its top higher up the gnomon
BASE = 1 / PHI      # the gnomon's base, in dial radii; its straight edge is one radius
DEPTH = 0.7         # how far the back curves in toward the gnomon's corner: 1 left the tips hairlines
SIDE_PAD = 23.3     # left and right, on the 170 grid: at this size the diagonal is exactly one radius
LINE = 5            # the dial's rim: 7 looked heavy beside the filled face
TIP = 3.5           # the outline round the filled gnomon: points, softened this much
GROUND = "#121417"
INK = "#FFA43D"
GLOW = 5
GLOW_OPACITY = 0.2  # at 0.8 the halo pooled where lines meet and blurred the dial; 0.4 fringed the face
FACE_OPACITY = 0.18

# Dial units, y up, the dial's center at the origin. The gnomon's angle is the cut's, in degrees.
def gnomon_at(deg, sc, n=200):
    # The straight edge to the tip, then the back from the tip to the base's end, pulled toward the
    # corner by DEPTH; slid along the corner's bisector by the outline's half width.
    g = math.radians(deg)
    tip = (math.cos(g), math.sin(g))
    h = TIP / 2 / sc
    return [(x + h / math.tan(g / 2), y + h) for x, y in [(0, 0)] + back(tip, n)]


def back(tip, n):
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c = (1 - t) ** 2, 2 * DEPTH * t * (1 - t), t * t
        pts.append(((a * tip[0] + c * BASE) / (a + b + c), (a * tip[1]) / (a + b + c)))
    return pts


def rim_ink(cut, sc, n=4000):
    # The stroked rim's outer and inner edges, kept where they fall on the dial's side of the cut.
    d = (math.cos(math.radians(cut)), math.sin(math.radians(cut)))
    hw = LINE / 2 / sc
    out = []
    for i in range(n):
        th = 2 * math.pi * i / n
        x, y = math.cos(th), ASPECT * math.sin(th)
        nx, ny = ASPECT * math.cos(th), math.sin(th)
        k = math.hypot(nx, ny)
        for s in (-hw, hw):
            p = (x + s * nx / k, y + s * ny / k)
            if p[0] * d[1] - p[1] * d[0] >= 0:   # right of the cut line, looking along it
                out.append(p)
    return out


def ink_box(cut, sc, ox, oy):
    pts = [(ox + sc * x, oy - sc * y) for x, y in rim_ink(cut, sc)]
    fin = [(ox + sc * x, oy - sc * y) for x, y in gnomon_at(cut, sc)]
    xs = [p[0] for p in pts] + [p[0] - TIP / 2 for p in fin] + [p[0] + TIP / 2 for p in fin]
    ys = [p[1] for p in pts] + [p[1] - TIP / 2 for p in fin] + [p[1] + TIP / 2 for p in fin]
    return min(xs), max(xs), min(ys), max(ys)


def balanced_cut(sc, ox):
    # A steeper cut shortens the tail, moving the left edge in; the rim fixes the right edge.
    lo, hi = 35.0, 85.0
    for _ in range(40):
        m = (lo + hi) / 2
        l, r, _, _ = ink_box(m, sc, ox, 85)
        lo, hi = (m, hi) if l < 170 - r else (lo, m)
    return (lo + hi) / 2


sc = 100.0
for _ in range(8):
    ox = 85 - sc * BASE / 2
    cut = balanced_cut(sc, ox)
    l, r, _, _ = ink_box(cut, sc, ox, 85)
    sc *= (170 - 2 * SIDE_PAD) / (r - l)
ox = 85 - sc * BASE / 2
cut = balanced_cut(sc, ox)
_, _, t, b = ink_box(cut, sc, ox, 85)
oy = 85 + (170 - t - b) / 2
l, r, t, b = ink_box(cut, sc, ox, oy)

fmt = lambda p: f"{ox + sc * p[0]:.2f} {oy - sc * p[1]:.2f}"
line = lambda ps: "M" + " L".join(fmt(p) for p in ps)
d = (math.cos(math.radians(cut)), math.sin(math.radians(cut)))
Q = 5
half = [(d[0] * Q, d[1] * Q), (d[0] * Q + d[1] * Q, d[1] * Q - d[0] * Q),
        (-d[0] * Q + d[1] * Q, -d[1] * Q - d[0] * Q), (-d[0] * Q, -d[1] * Q)]
c = math.atan2(d[1] / ASPECT, d[0])
face = [(math.cos(c - math.pi * k / 160), ASPECT * math.sin(c - math.pi * k / 160)) for k in range(161)]
rim = [(math.cos(2 * math.pi * i / 240), ASPECT * math.sin(2 * math.pi * i / 240)) for i in range(240)]
gnomon = gnomon_at(cut, sc)
face_svg = f'<path d="{line(face)} Z" fill="{INK}" fill-opacity="{FACE_OPACITY}" stroke="none"/>'
shapes = (face_svg + f'<path d="{line(rim)} Z" fill="none" stroke-width="{LINE}" clip-path="url(#half)"/>'
          f'<path d="{line(gnomon)} Z" fill="{INK}" stroke-width="{TIP}"/>')
svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <!-- Generated by draw.py. macOS icon grid: an 824pt body centered on 1024; drawn on a 170 grid. -->
  <g transform="translate(100 100) scale(4.847)" stroke-linejoin="round">
    <defs>
      <filter id="glow" filterUnits="userSpaceOnUse" x="-20" y="-20" width="210" height="210">
        <feGaussianBlur stdDeviation="{GLOW}"/>
      </filter>
      <clipPath id="body"><rect width="170" height="170" rx="38"/></clipPath>
      <clipPath id="half"><path d="{line(half)} Z"/></clipPath>
    </defs>
    <g clip-path="url(#body)">
      <rect width="170" height="170" rx="38" fill="{GROUND}"/>
      <g stroke="{INK}" opacity="{GLOW_OPACITY}" filter="url(#glow)">{shapes}</g>
      <g stroke="{INK}">{shapes}</g>
    </g>
  </g>
</svg>
"""
pathlib.Path(__file__).with_name("AppIcon.svg").write_text(svg)
print(f"cut and gnomon {cut:.2f}°, scale {sc:.2f}, padding {l:.1f}/{170 - r:.1f} sides, {t:.1f}/{170 - b:.1f} top and bottom")
