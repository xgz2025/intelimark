#!/usr/bin/env python3
"""Nextmark app icon — "Next Ribbon".

A bookmark ribbon with a forward chevron cut out of it: a saved thing that
knows its next step. Generates the SVG masters; render.js turns them into PNGs.

    python3 Design/AppIcon/make_icon.py          # writes Design/AppIcon/masters/*.svg
    node Design/AppIcon/render.js …              # see Design/AppIcon/README.md
"""
from pathlib import Path

W = 1024
CORAL_LIGHT, CORAL, RASPBERRY = "#FF9B62", "#FA6B61", "#E8386A"
SHADOW = "#7A0F2E"

# Glyph geometry on the 1024 grid (shared by every variant and by Icon Composer layers).
X0, X1, Y0, Y1, R, NOTCH = 330, 694, 204, 806, 60, 142
CHEVRON = "M458,338 L578,458 L458,578"
CHEVRON_WIDTH = 86


def ribbon_path(x0=X0, x1=X1, y0=Y0, y1=Y1, r=R, d=NOTCH):
    cx = (x0 + x1) / 2
    return (f"M{x0},{y0 + r} A{r},{r} 0 0 1 {x0 + r},{y0} L{x1 - r},{y0} "
            f"A{r},{r} 0 0 1 {x1},{y0 + r} L{x1},{y1} L{cx},{y1 - d} L{x0},{y1} Z")


def glyph(fill, shadow_color=None, shadow_opacity=0.0):
    """The ribbon with the chevron knocked out (true transparency through a mask)."""
    shadow = ""
    if shadow_color:
        shadow = (f'<filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">'
                  f'<feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="{shadow_color}" '
                  f'flood-opacity="{shadow_opacity}"/></filter>')
    defs = f'''{shadow}
<mask id="cut" maskUnits="userSpaceOnUse" x="0" y="0" width="{W}" height="{W}">
  <rect width="{W}" height="{W}" fill="#fff"/>
  <path d="{CHEVRON}" fill="none" stroke="#000" stroke-width="{CHEVRON_WIDTH}" stroke-linecap="round" stroke-linejoin="round"/>
</mask>'''
    body = (f'<g{" filter=\"url(#shadow)\"" if shadow_color else ""}><g mask="url(#cut)">'
            f'<path d="{ribbon_path()}" fill="{fill}" stroke="{fill}" stroke-width="28" stroke-linejoin="round"/>'
            f'</g></g>')
    return defs, body


def svg(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" viewBox="0 0 {W} {W}">\n'
            f'<defs>\n{defs}\n</defs>\n{body}\n</svg>\n')


BACKGROUND_DEFS = f'''<linearGradient id="bg" x1="0.15" y1="0" x2="0.85" y2="1">
  <stop offset="0" stop-color="{CORAL_LIGHT}"/><stop offset="0.55" stop-color="{CORAL}"/><stop offset="1" stop-color="{RASPBERRY}"/>
</linearGradient>
<radialGradient id="sheen" cx="0.28" cy="0.04" r="0.85">
  <stop offset="0" stop-color="#fff" stop-opacity="0.30"/><stop offset="0.6" stop-color="#fff" stop-opacity="0"/>
</radialGradient>
<linearGradient id="paper" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FFF0EA"/>
</linearGradient>'''


def light_ios():
    gdefs, gbody = glyph("url(#paper)", SHADOW, 0.35)
    return svg(BACKGROUND_DEFS + gdefs,
               f'<rect width="{W}" height="{W}" fill="url(#bg)"/>\n<rect width="{W}" height="{W}" fill="url(#sheen)"/>\n{gbody}')


def dark_ios():
    gdefs, gbody = glyph("url(#coral)", "#000000", 0.5)
    defs = f'''<linearGradient id="dark" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2A2A2E"/><stop offset="1" stop-color="#121214"/></linearGradient>
<linearGradient id="coral" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="{CORAL_LIGHT}"/><stop offset="1" stop-color="{RASPBERRY}"/></linearGradient>{gdefs}'''
    return svg(defs, f'<rect width="{W}" height="{W}" fill="url(#dark)"/>\n{gbody}')


def tinted_ios():
    # Grayscale: the system tints by luminance.
    gdefs, gbody = glyph("#FFFFFF")
    return svg(gdefs, f'<rect width="{W}" height="{W}" fill="#000000"/>\n{gbody}')


def macos():
    """macOS draws no mask: the icon carries its own rounded square (824 grid) and shadow."""
    inset, size, radius = 100, 824, 185
    scale = size / W
    gdefs, gbody = glyph("url(#paper)", SHADOW, 0.35)
    defs = BACKGROUND_DEFS + gdefs + f'''
<clipPath id="squircle"><rect x="{inset}" y="{inset}" width="{size}" height="{size}" rx="{radius}"/></clipPath>
<filter id="drop" x="-20%" y="-20%" width="140%" height="140%">
  <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.28"/>
</filter>'''
    body = f'''<g filter="url(#drop)"><rect x="{inset}" y="{inset}" width="{size}" height="{size}" rx="{radius}" fill="url(#bg)"/></g>
<g clip-path="url(#squircle)">
  <rect x="{inset}" y="{inset}" width="{size}" height="{size}" fill="url(#sheen)"/>
  <g transform="translate({inset},{inset}) scale({scale})">{gbody}</g>
</g>
<rect x="{inset + 1}" y="{inset + 1}" width="{size - 2}" height="{size - 2}" rx="{radius - 1}" fill="none" stroke="#fff" stroke-opacity="0.18" stroke-width="2"/>'''
    return svg(defs, body)


def layer_background():
    return svg(BACKGROUND_DEFS, f'<rect width="{W}" height="{W}" fill="url(#bg)"/>')


def layer_glyph():
    gdefs, gbody = glyph("#FFFFFF")
    return svg(gdefs, gbody)


if __name__ == "__main__":
    out = Path(__file__).parent / "masters"
    out.mkdir(exist_ok=True)
    for name, make in {
        "AppIcon-iOS": light_ios,
        "AppIcon-iOS-Dark": dark_ios,
        "AppIcon-iOS-Tinted": tinted_ios,
        "AppIcon-macOS": macos,
        "Layer-1-Background": layer_background,
        "Layer-2-Glyph": layer_glyph,
    }.items():
        (out / f"{name}.svg").write_text(make())
        print("wrote", out / f"{name}.svg")
