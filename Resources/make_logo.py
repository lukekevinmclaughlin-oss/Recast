#!/usr/bin/env python3
"""Recast 'Jarvis' logo: a holographic data-core (wireframe icosahedron) being
scanned and assembled from converging fragments, inside a HUD reticle with
targeting brackets. Geometry computed so edges/nodes are exact."""
import math

S = 1024
cx = cy = S / 2
PHI = (1 + 5 ** 0.5) / 2

raw = []
for s1 in (-1, 1):
    for s2 in (-1, 1):
        raw += [(0, s1, s2 * PHI), (s1, s2 * PHI, 0), (s2 * PHI, 0, s1)]
verts = list({(round(x, 4), round(y, 4), round(z, 4)) for (x, y, z) in raw})

def rot(p, ax, ay):
    x, y, z = p
    ca, sa = math.cos(ay), math.sin(ay)
    x, z = x * ca + z * sa, -x * sa + z * ca
    cb, sb = math.cos(ax), math.sin(ax)
    y, z = y * cb - z * sb, y * sb + z * cb
    return (x, y, z)

AX, AY = math.radians(-22), math.radians(34)
scale = 150
proj = []
for v in verts:
    x, y, z = rot(v, AX, AY)
    proj.append((cx + x * scale, cy - y * scale, z))

edges = []
n = len(verts)
for i in range(n):
    for j in range(i + 1, n):
        if abs(math.dist(verts[i], verts[j]) - 2.0) < 0.05:
            edges.append((i, j))

zmin = min(p[2] for p in proj); zmax = max(p[2] for p in proj)
def depth01(z): return (z - zmin) / (zmax - zmin + 1e-6)

edge_svg = []
for (i, j) in edges:
    a, b = proj[i], proj[j]
    dd = (depth01(a[2]) + depth01(b[2])) / 2
    edge_svg.append(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" '
                    f'stroke="#4FE9F5" stroke-opacity="{0.28+0.55*dd:.2f}" stroke-width="{2.2+2.2*dd:.1f}" stroke-linecap="round"/>')

node_svg = []
for (sx, sy, z) in proj:
    dd = depth01(z); r = 5 + 7 * dd
    node_svg.append(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{r:.1f}" fill="#EAFEFF"/>')
    node_svg.append(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{r*2.1:.1f}" fill="#5CE9F5" fill-opacity="{0.10+0.10*dd:.2f}"/>')

frag_svg = []
for k, ang in enumerate((28, 118, 208, 298)):
    a = math.radians(ang)
    fx, fy = cx + 372 * math.cos(a), cy + 372 * math.sin(a)
    tx, ty = cx + 168 * math.cos(a), cy + 168 * math.sin(a)
    accent = "#FFC24D" if k == 0 else "#4FE9F5"
    frag_svg.append(f'<line x1="{fx:.1f}" y1="{fy:.1f}" x2="{tx:.1f}" y2="{ty:.1f}" '
                    f'stroke="{accent}" stroke-opacity="0.45" stroke-width="2.5" stroke-dasharray="3 10" stroke-linecap="round"/>')
    frag_svg.append(f'<g transform="translate({fx:.1f} {fy:.1f}) rotate({ang})">'
                    f'<rect x="-13" y="-13" width="26" height="26" rx="6" fill="none" stroke="{accent}" stroke-width="3.5" stroke-opacity="0.9"/>'
                    f'<rect x="-5" y="-5" width="10" height="10" rx="2" fill="{accent}"/></g>')

def ticks(r, count, length):
    out = []
    for t in range(count):
        a = 2 * math.pi * t / count
        out.append(f'<line x1="{cx+r*math.cos(a):.1f}" y1="{cy+r*math.sin(a):.1f}" '
                   f'x2="{cx+(r+length)*math.cos(a):.1f}" y2="{cy+(r+length)*math.sin(a):.1f}" '
                   f'stroke="#3FC9E6" stroke-opacity="0.5" stroke-width="3"/>')
    return "".join(out)

def bracket(x, y, dx, dy, L=78, w=9):
    return (f'<path d="M {x+dx*L} {y} L {x} {y} L {x} {y+dy*L}" fill="none" '
            f'stroke="#5CE9F5" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>')

inset = 150
brackets = "".join([bracket(inset, inset, 1, 1), bracket(S-inset, inset, -1, 1),
                    bracket(inset, S-inset, 1, -1), bracket(S-inset, S-inset, -1, -1)])

scan = (f'<path d="M {cx+300*math.cos(math.radians(-40)):.1f} {cy+300*math.sin(math.radians(-40)):.1f} '
        f'A 300 300 0 0 1 {cx+300*math.cos(math.radians(60)):.1f} {cy+300*math.sin(math.radians(60)):.1f}" '
        f'fill="none" stroke="#7CF3FF" stroke-width="6" stroke-linecap="round" opacity="0.85" filter="url(#glow)"/>')

def build(rx):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <radialGradient id="bg" cx="0.5" cy="0.42" r="0.75">
      <stop offset="0" stop-color="#12233B"/><stop offset="0.55" stop-color="#0A1526"/><stop offset="1" stop-color="#05080F"/>
    </radialGradient>
    <radialGradient id="core" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#7CF3FF" stop-opacity="0.55"/><stop offset="0.4" stop-color="#2CB6E8" stop-opacity="0.16"/><stop offset="1" stop-color="#2CB6E8" stop-opacity="0"/>
    </radialGradient>
    <filter id="glow" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="7" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
    <filter id="softglow" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="16"/></filter>
  </defs>
  <rect x="0" y="0" width="{S}" height="{S}" rx="{rx}" ry="{rx}" fill="url(#bg)"/>
  <g opacity="0.9">
    <circle cx="{cx}" cy="{cy}" r="410" fill="none" stroke="#2A6E8A" stroke-opacity="0.35" stroke-width="2"/>
    <circle cx="{cx}" cy="{cy}" r="330" fill="none" stroke="#3FC9E6" stroke-opacity="0.35" stroke-width="2.5" stroke-dasharray="2 16"/>
    {ticks(300, 48, 14)}
    {brackets}
  </g>
  <circle cx="{cx}" cy="{cy}" r="250" fill="url(#core)"/>
  <g filter="url(#glow)">{''.join(frag_svg)}</g>
  <g filter="url(#glow)">{''.join(edge_svg)}</g>
  <g>{''.join(node_svg)}</g>
  {scan}
  <circle cx="{cx}" cy="{cy}" r="10" fill="#FFFFFF" filter="url(#softglow)"/>
</svg>'''

with open('AppIcon.svg', 'w') as f: f.write(build(230))
with open('AppIcon-ios.svg', 'w') as f: f.write(build(0))
print(f'wrote logo — {len(verts)} nodes, {len(edges)} edges')
