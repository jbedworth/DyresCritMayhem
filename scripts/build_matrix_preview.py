#!/usr/bin/env python3
"""Render artwork/style-matrix-preview.png: each theme's look for each damage
school, as Themes.lua defines it (read through scripts/style_matrix.lua), on a
dark strip. Rows: Tame, Brutal, Spellburst with and without the 18+ box, Fel;
columns: physical, holy, fire, nature, frost, shadow, arcane. Up to two
textures per cell, the second smaller in front, tinted, and added as light
where the client adds it. Python 3 standard library and a Lua 5.1 binary:

    python scripts/build_matrix_preview.py --lua path/to/lua5.1
"""

import argparse
import importlib.util
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_SPEC = importlib.util.spec_from_file_location("build_splatters", ROOT / "scripts" / "build_splatters.py")
tex = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(tex)
OUTPUT = ROOT / "artwork" / "style-matrix-preview.png"
KINDS = ["physical", "holy", "fire", "nature", "frost", "shadow", "arcane"]
ROWS = [("tame", "", "TAME"), ("brutal", "", "BRUTAL"), ("spellburst", "adult", "SPELLBURST 18+"),
        ("spellburst", "", "SPELLBURST"), ("fel", "", "FEL"), ("naturalist", "", "NATURALIST"),
        ("brutal", "feral", "BRUTAL CAT")]
CELL, GAP, LABEL = 112, 10, 180
BACKGROUND = (34, 30, 28)
TEXT = (230, 214, 170)
# A 3x5 pixel font for the labels: each glyph is five rows of three bits.
FONT = {
    "A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
    "E": "111100110100111", "F": "111100110100100", "H": "101101111101101", "I": "111010010010111",
    "L": "100100100100111", "M": "101111111101101", "N": "110101101101101", "O": "010101101101010",
    "P": "110101110100100", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
    "U": "101101101101111", "W": "101101111111101", "Y": "101101010010010", "8": "010101010101010",
    "1": "010110010010111", "+": "000010111010000", " ": "000000000000000",
}


def styles(lua, mode):
    """mode: "" (no 18+ box), "adult", or "feral" (in Cat or Bear form)."""
    out = subprocess.run([lua, "scripts/style_matrix.lua"] + ([mode] if mode else []), cwd=ROOT,
                         check=True, capture_output=True, text=True).stdout
    cells = {}
    for line in out.splitlines():
        theme, kind, texture, r, g, b, blend = line.split()
        cells.setdefault((theme, kind), []).append((texture + ".tga", (float(r), float(g), float(b)), blend))
    return cells


def text(canvas, x, y, words, scale=3):
    for char in words.upper():
        glyph = FONT.get(char, FONT[" "])
        for row in range(5):
            for col in range(3):
                if glyph[row * 3 + col] == "1":
                    for dy in range(scale):
                        line = canvas[y + row * scale + dy]
                        for dx in range(scale):
                            line[(x + col * scale + dx) * 3:(x + col * scale + dx) * 3 + 3] = bytes(TEXT)
        x += 4 * scale


def draw(canvas, data, tint, box, add):
    """Like build_splatters._draw, adding light for ADD."""
    bx, by, size = box
    ratio = tex.SIZE / size
    for y in range(size):
        row = canvas[by + y]
        for x in range(size):
            index = (int(y * ratio) * tex.SIZE + int(x * ratio)) * 4
            alpha = data[index + 3] / 255
            if not alpha:
                continue
            for channel in range(3):
                # BGRA, per channel, so a colored texture keeps its colors.
                shade = data[index + 2 - channel] / 255
                old = row[(bx + x) * 3 + channel]
                light = shade * tint[channel] * 255 * alpha
                row[(bx + x) * 3 + channel] = min(255, round(old + light)) if add else round(
                    light + old * (1 - alpha))


def render(lua):
    textures = {name: tex.decode(tex.build(name))[2] for name in tex.TEXTURE_SPECS}
    matrix = {mode: styles(lua, mode) for mode in ("", "adult", "feral")}
    width = LABEL + len(KINDS) * (CELL + GAP) + GAP
    height = 40 + len(ROWS) * (CELL + GAP) + GAP
    canvas = [bytearray(bytes(BACKGROUND) * width) for _ in range(height)]
    for column, kind in enumerate(KINDS):
        text(canvas, LABEL + GAP + column * (CELL + GAP), 14, kind)
    for row, (theme, mode, label) in enumerate(ROWS):
        y = 40 + row * (CELL + GAP)
        text(canvas, 10, y + CELL // 2 - 8, label)
        for column, kind in enumerate(KINDS):
            x = LABEL + GAP + column * (CELL + GAP)
            for index, (name, tint, blend) in enumerate(matrix[mode][(theme, kind)][:2]):
                size = CELL if index == 0 else CELL * 3 // 5
                offset = 0 if index == 0 else CELL - size
                draw(canvas, textures[name], tint, (x + offset, y + offset, size), blend == "ADD")
    return tex.png(width, height, [bytes(line) for line in canvas])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", required=True, help="a Lua 5.1 interpreter")
    args = parser.parse_args()
    OUTPUT.write_bytes(render(args.lua))


if __name__ == "__main__":
    main()
