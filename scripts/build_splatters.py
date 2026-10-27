#!/usr/bin/env python3
"""Build Dyre's Crit Mayhem's splatter and Tame textures: original procedural art.

Each texture is a grey splatter on a transparent square: a lumpy central
pool, tapering streaks thrown outward, and droplets that get smaller farther
out. The drips are a splatter high up with runs trickling down from it. The
grey is darkest where the pool is deepest and lightest at its thin edges;
the AddOn tints it with the theme's color (Brutal: deep red), so one set of
textures serves every theme. Edges are anti-aliased from signed distances.

The Tame theme's textures (author: "maybe a little butterfly or star") are two
butterflies, a five-point star, a sparkle, and a heart (for heal crits): white inside with a darker
rim, so a pastel tint still reads, and the butterflies' bodies and wing spots
darker still.

Written as run-length encoded 32-bit TGAs (image type 10, top-left origin),
which the client reads; the transparent background packs small. Seeded, so
the output is byte-for-byte deterministic. Python 3 standard library only.

The run is a single trickle with a bulb at its foot: Brutal grows it down
from under a splat that stays put (Effects.lua), so its top is round and
hidden under the splat.

Fel's textures are dark and have no sparkle: two smoke clouds with curling
tendrils, a few embers or flakes of ash, cracks branching from the middle,
and a vignette, dark at the edges and clear in the middle, stretched over
the screen on a big crit; --preview writes artwork/fel-preview.png.

Spellburst's glows (a starburst of rays, a glowing mote, a soft ring) are
white with soft alpha: the client draws them additively, tinted by spell
school; --preview writes artwork/spellburst-preview.png with them tinted.

--preview also writes artwork/motion-preview.png, frames of each looping
animation (stars spin, butterflies flutter, sparkles twinkle, a run grows),
and artwork/splatters-preview.png (the splatters tinted Brutal
red) and artwork/tame-preview.png (the Tame theme's textures in its pastels),
each on a light and a dark strip, for review.
"""

import argparse
import math
import random
import struct
import zlib
from pathlib import Path

SIZE = 256
ROOT = Path(__file__).resolve().parent.parent
TEXTURES = ROOT / "Textures"
PREVIEW = ROOT / "artwork" / "splatters-preview.png"
TAME_PREVIEW = ROOT / "artwork" / "tame-preview.png"
SPELLBURST_PREVIEW = ROOT / "artwork" / "spellburst-preview.png"
FEL_PREVIEW = ROOT / "artwork" / "fel-preview.png"
NATURALIST_PREVIEW = ROOT / "artwork" / "naturalist-preview.png"
SCHOOL_PREVIEW = ROOT / "artwork" / "school-textures-preview.png"
MOTION_PREVIEW = ROOT / "artwork" / "motion-preview.png"
# How deep in the pool, in pixels, the grey reaches its darkest.
DEPTH = 22.0
DARKEST = 0.5
# Brutal's tint and Tame pastels (Themes.lua), for the previews only.
BRUTAL = (0.62, 0.02, 0.02)
PASTELS = ((1, 0.72, 0.84), (0.8, 0.72, 1), (0.68, 0.95, 0.82), (1, 0.93, 0.62))
# Cute textures: the grey at the rim, how many pixels it takes to reach white,
# and the grey of a butterfly's body and wing spots.
RIM_GREY = 0.55
RIM = 3.0
BODY_GREY = 0.38
SPOT_GREY = 0.78
# Nothing is drawn this close to the texture's edge, so nothing is cut off.
MARGIN = 3
TGA_RLE = 10
MAX_RUN = 128

# name: (kind, seed). Seeds were picked by eye for four splatters that read
# differently from each other, and two drips.
TEXTURE_SPECS = {
    "Splat1.tga": ("splat", 11),
    "Splat2.tga": ("splat", 23),
    "Splat3.tga": ("splat", 37),
    "Splat4.tga": ("splat", 58),
    "Drip1.tga": ("drip", 71),
    "Drip2.tga": ("drip", 94),
    "Run1.tga": ("run", 41),
    "Butterfly1.tga": ("butterfly", 5),
    "Butterfly2.tga": ("butterfly", 17),
    "Star1.tga": ("star", 3),
    "Sparkle1.tga": ("sparkle", 9),
    "Heart1.tga": ("heart", 0),
    "Burst1.tga": ("burst", 13),
    "Burst2.tga": ("burst", 29),
    "Mote1.tga": ("mote", 0),
    "Ring1.tga": ("ring", 0),
    "Smoke1.tga": ("smoke", 19),
    "Smoke2.tga": ("smoke", 47),
    "Embers1.tga": ("embers", 61),
    "Crack1.tga": ("crack", 8),
    "Vignette1.tga": ("vignette", 0),
    "Flame1.tga": ("flame", 33),
    "Shard1.tga": ("shard", 52),
    "Snowflake1.tga": ("snowflake", 0),
    "Pow1.tga": ("pow", 21),
    "Rainbow1.tga": ("rainbow", 0),
    "Maple1.tga": ("maple", 0),
    "Oak1.tga": ("oak", 0),
    "Birch1.tga": ("birch", 0),
    "Claw1.tga": ("claw", 5),
    "Claw2.tga": ("claw", 4),
    "Claw3.tga": ("claw", 6),
    "Bite1.tga": ("bite", 27),
    "Insect1.tga": ("insect", 0),
    "Vine1.tga": ("vine", 14),
    "Firework1.tga": ("firework", 31),
    "Vignette2.tga": ("lightvignette", 0),
}
CUTE_KINDS = {"butterfly", "star", "sparkle", "heart"}
# Spellburst's glows: soft-edged, white, drawn additively and tinted by spell
# school in the client.
GLOW_KINDS = {"burst", "mote", "ring"}
# Fel's dark kinds: soft smoke and embers, and a full-screen vignette (the one
# texture that reaches its edges, since it frames the screen).
SOFT_KINDS = GLOW_KINDS | {"smoke", "embers", "vignette"}
FEL_KINDS = {"smoke", "embers", "crack", "vignette"}
# Shared by the themes' school looks (fire, frost, nature, physical): a soft
# flame, and white-with-a-rim ice shards, a leaf, a snowflake, and a cartoon
# "pow" burst, tinted per theme.
SCHOOL_KINDS = {"flame", "shard", "snowflake", "pow", "maple", "oak", "birch"}
RIMMED_KINDS = CUTE_KINDS | {"shard", "snowflake", "pow", "maple", "oak", "birch"}
SOFT_KINDS = SOFT_KINDS | {"flame"}
# Naturalist's (a mature nature theme): claw rakes and a bite in the blood shading,
# a beetle and a curling vine white with a rim, a silver firework spray (a
# glow), and a white vignette tinted deep green in the client.
NATURALIST_KINDS = {"claw", "bite", "insect", "vine", "firework", "lightvignette"}
RIMMED_KINDS = RIMMED_KINDS | {"insect", "vine"}
SOFT_KINDS = SOFT_KINDS | {"firework", "lightvignette"}
# Drawn in its own colors, never tinted (the theme marks it untinted): Tame's
# rainbow, pastel bands with a little cloud at each end.
COLORED_KINDS = {"rainbow"}
RAINBOW_BANDS = ((255, 150, 160), (255, 195, 140), (255, 235, 150), (170, 235, 160), (150, 200, 255),
                 (195, 165, 255))
# Textures smaller than SIZE: the vignette is a smooth gradient stretched over
# the whole screen, so 64 pixels lose nothing and keep the file small.
SIZES = {"Vignette1.tga": 64, "Vignette2.tga": 64}


def texture_size(name):
    return SIZES.get(name, SIZE)
# Fel's palette, for the preview only: fel green, shadow, hellfire.
FEL = ((0.35, 0.9, 0.15), (0.22, 0.08, 0.3), (0.95, 0.3, 0.08))
GLOW_CUT = 0.03
# Spell-school tints, for the preview only (Themes.lua holds the client's).
SCHOOLS = ((1, 0.55, 0.15), (0.45, 0.8, 1), (0.85, 0.45, 1), (0.55, 0.3, 0.9), (0.45, 1, 0.45),
           (1, 0.92, 0.6))


class Shape:
    """A union of a lumpy pool, capsules (streaks and runs), circles,
    ellipses, and polygons. A cute shape may carry darker parts: dark (a
    butterfly's body) and mid (its wing spots), shapes of their own."""

    def __init__(self):
        self.pool = None
        self.capsules = []
        self.circles = []
        self.ellipses = []
        self.polygons = []
        self.dark = None
        self.mid = None

    def distance(self, x, y):
        best = math.inf
        if self.pool:
            cx, cy, radius, waves = self.pool
            dx, dy = x - cx, y - cy
            angle = math.atan2(dy, dx)
            edge = radius * (1 + sum(amp * math.sin(freq * angle + phase) for amp, freq, phase in waves))
            best = math.hypot(dx, dy) - edge
        for ax, ay, bx, by, ra, rb, box in self.capsules:
            if not (box[0] <= x <= box[2] and box[1] <= y <= box[3]):
                continue
            px, py = x - ax, y - ay
            vx, vy = bx - ax, by - ay
            t = max(0.0, min(1.0, (px * vx + py * vy) / (vx * vx + vy * vy)))
            d = math.hypot(px - vx * t, py - vy * t) - (ra + (rb - ra) * t)
            best = min(best, d)
        for cx, cy, r in self.circles:
            if abs(x - cx) > r + 2 or abs(y - cy) > r + 2:
                continue
            best = min(best, math.hypot(x - cx, y - cy) - r)
        for cx, cy, rx, ry, cos, sin in self.ellipses:
            dx, dy = x - cx, y - cy
            u, v = dx * cos + dy * sin, -dx * sin + dy * cos
            # Close to the true distance for these gentle ellipses.
            best = min(best, (math.hypot(u / rx, v / ry) - 1) * min(rx, ry))
        for points in self.polygons:
            best = min(best, polygon_distance(points, x, y))
        return best

    def ellipse(self, cx, cy, rx, ry, angle):
        self.ellipses.append((cx, cy, rx, ry, math.cos(angle), math.sin(angle)))

    def circle(self, cx, cy, r):
        """A droplet, left out when it would be cut by the texture's edge."""
        if MARGIN + r <= cx <= SIZE - MARGIN - r and MARGIN + r <= cy <= SIZE - MARGIN - r:
            self.circles.append((cx, cy, r))

    def capsule(self, ax, ay, bx, by, ra, rb):
        pad = max(ra, rb) + 2
        box = (min(ax, bx) - pad, min(ay, by) - pad, max(ax, bx) + pad, max(ay, by) + pad)
        self.capsules.append((ax, ay, bx, by, ra, rb, box))


def polygon_distance(points, x, y):
    """Signed distance to a closed polygon: negative inside."""
    best = math.inf
    inside = False
    for index, (ax, ay) in enumerate(points):
        bx, by = points[index - 1]
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)))
        best = min(best, math.hypot(x - ax - vx * t, y - ay - vy * t))
        if (ay > y) != (by > y) and x < ax + (y - ay) * vx / vy:
            inside = not inside
    return -best if inside else best


def star_points(cx, cy, points, outer, inner, turn):
    return [(cx + (outer if i % 2 == 0 else inner) * math.cos(turn + math.pi * i / points),
             cy + (outer if i % 2 == 0 else inner) * math.sin(turn + math.pi * i / points))
            for i in range(2 * points)]


def lumpy_pool(rng, cx, cy, radius):
    waves = [(rng.uniform(0.04, 0.12) / (1 + i * 0.4), rng.randint(2 + i, 4 + 2 * i), rng.uniform(0, 2 * math.pi))
             for i in range(5)]
    return (cx, cy, radius, waves)


def splat(seed):
    rng = random.Random(seed)
    shape = Shape()
    c = SIZE / 2
    radius = rng.uniform(34, 46)
    shape.pool = lumpy_pool(rng, c, c, radius)
    # Streaks thrown outward, thick at the pool and thin at the tip, some
    # ending in a droplet.
    for _ in range(rng.randint(7, 12)):
        angle = rng.uniform(0, 2 * math.pi)
        start = radius * 0.6
        length = rng.uniform(radius * 0.5, c - 14 - start)
        end = start + length
        ax, ay = c + math.cos(angle) * start, c + math.sin(angle) * start
        bx, by = c + math.cos(angle) * end, c + math.sin(angle) * end
        shape.capsule(ax, ay, bx, by, rng.uniform(5, 10), rng.uniform(0.8, 2.2))
        if rng.random() < 0.55:
            shape.circle(bx + math.cos(angle) * 4, by + math.sin(angle) * 4, rng.uniform(2.5, 5))
    # Droplets: many small far out, a few big near.
    for _ in range(rng.randint(26, 40)):
        angle = rng.uniform(0, 2 * math.pi)
        reach = rng.uniform(radius * 1.05, c - 8)
        scale = 1 - (reach - radius) / (c - radius)
        r = max(1.2, rng.uniform(1.5, 7.5) * (0.35 + scale))
        shape.circle(c + math.cos(angle) * reach, c + math.sin(angle) * reach, r)
    return shape


def drip(seed):
    rng = random.Random(seed)
    shape = Shape()
    c = SIZE / 2
    top = 76.0
    radius = rng.uniform(30, 38)
    shape.pool = lumpy_pool(rng, c, top, radius)
    # Runs trickling down, each ending in a bulb.
    for _ in range(rng.randint(3, 5)):
        x = c + rng.uniform(-radius * 0.8, radius * 0.8)
        y0 = top + radius * 0.4
        y1 = rng.uniform(top + radius + 20, SIZE - 20)
        width = rng.uniform(3, 6.5)
        wobble = rng.uniform(-6, 6)
        shape.capsule(x, y0, x + wobble, y1, width, width * 0.7)
        shape.circle(x + wobble, y1, width * rng.uniform(1.3, 1.7))
    # Droplets around the pool, wider than tall.
    for _ in range(rng.randint(14, 22)):
        angle = rng.uniform(0, 2 * math.pi)
        reach = rng.uniform(radius * 1.1, radius * 2.6)
        shape.circle(c + math.cos(angle) * reach, top + math.sin(angle) * reach * 0.7, rng.uniform(1.4, 4.5))
    return shape


def run(seed):
    """One trickle down the middle, narrowing, with a bulb at its foot."""
    rng = random.Random(seed)
    shape = Shape()
    c = SIZE / 2
    top, foot = 18.0, SIZE - 34.0
    sway = rng.uniform(-5, 5)
    middle = (top + foot) / 2
    shape.capsule(c, top, c + sway, middle, 15, 11)
    shape.capsule(c + sway, middle, c, foot, 11, 8)
    shape.circle(c, foot + 4, 16)
    return shape


def butterfly(seed):
    """Seen from above: four rounded wings, a body, and curled antennae."""
    rng = random.Random(seed)
    shape, body, spots = Shape(), Shape(), Shape()
    c = SIZE / 2
    upper = (rng.uniform(40, 50), rng.uniform(30, 38), rng.uniform(0.35, 0.6))
    lower = (rng.uniform(26, 34), rng.uniform(22, 28), rng.uniform(0.5, 0.8))
    for side in (-1, 1):
        ux, uy = c + side * (upper[0] * 0.82), c - 22
        shape.ellipse(ux, uy, upper[0], upper[1], -side * upper[2])
        lx, ly = c + side * (lower[0] * 0.8), c + 24
        shape.ellipse(lx, ly, lower[0], lower[1], side * lower[2])
        spots.circle(ux + side * upper[0] * 0.25, uy - 4, upper[1] * 0.3)
        spots.circle(lx + side * lower[0] * 0.2, ly + 4, lower[1] * 0.25)
        # Antennae: a thin stalk with a round tip.
        tip = (c + side * rng.uniform(22, 30), c - 82)
        shape.capsule(c + side * 2, c - 44, tip[0], tip[1], 1.8, 1.4)
        shape.circle(tip[0], tip[1], 4.5)
        body.circle(tip[0], tip[1], 4.5)
    body.capsule(c, c - 40, c, c + 50, 8, 4.5)
    body.circle(c, c - 46, 9)
    shape.capsules += body.capsules
    shape.circles += body.circles
    shape.dark, shape.mid = body, spots
    return shape


def star(seed):
    """A plump five-point star with rounded points."""
    shape = Shape()
    rounding = 7
    shape.polygons.append(star_points(SIZE / 2, SIZE / 2 + 6, 5, 104 - rounding, 46 - rounding, -math.pi / 2))
    shape.rounding = rounding
    return shape


def flame(seed):
    """A flame: three soft tongues, brightest low in the middle."""
    rng = random.Random(seed)
    bottom = SIZE / 2 + 96
    tongues = [(0.0, 190.0, 54.0)] + [(rng.choice((-1, 1)) * rng.uniform(18, 32), rng.uniform(110, 150),
                                       rng.uniform(26, 36)) for _ in range(2)]

    def light(dx, dy):
        y = dy + SIZE / 2
        alpha, core = 0.0, 0.0
        for cx, height, width in tongues:
            v = (bottom - y) / height
            if v <= 0 or v >= 1:
                continue
            half = width * 2.2 * math.sqrt(v) * (1 - v) ** 1.2
            off = abs(dx - cx * (0.3 + v))
            alpha = max(alpha, _clamp((half - off) / 7))
            if half > 0:
                core = max(core, _clamp(1 - off / half) * (1 - v))
        return 0.7 + 0.3 * core, alpha
    return light


def shard(seed):
    """Ice shards: sharp splinters flying out from the middle, a few chips."""
    rng = random.Random(seed)
    shape = Shape()
    c = SIZE / 2
    for index in range(rng.randint(5, 7)):
        angle = 2 * math.pi * index / 6 + rng.uniform(-0.3, 0.3)
        length, width = rng.uniform(60, 105), rng.uniform(9, 16)
        start = rng.uniform(4, 14)
        tip = (c + math.cos(angle) * length, c + math.sin(angle) * length)
        left = (c + math.cos(angle) * start + math.cos(angle + math.pi / 2) * width,
                c + math.sin(angle) * start + math.sin(angle + math.pi / 2) * width)
        right = (c + math.cos(angle) * start - math.cos(angle + math.pi / 2) * width,
                 c + math.sin(angle) * start - math.sin(angle + math.pi / 2) * width)
        shape.polygons.append([left, tip, right])
    for _ in range(6):
        angle, reach = rng.uniform(0, 2 * math.pi), rng.uniform(70, 110)
        x, y, r = c + math.cos(angle) * reach, c + math.sin(angle) * reach, rng.uniform(4, 8)
        shape.polygons.append([(x, y - r), (x + r * 0.7, y), (x, y + r), (x - r * 0.7, y)])
    return shape


def _leaf_parts(shape, top, foot):
    """A leaf's stem below its foot and a darker midrib up its middle."""
    vein = Shape()
    c = SIZE / 2
    shape.capsule(c, foot - 4, c + 3, foot + 24, 4, 3)
    vein.capsule(c, top + 18, c, foot - 2, 2.2, 2.6)
    shape.mid = vein


def maple(seed):
    """A sugar maple leaf (author: "I'm from MI, so Maple"): five pointed
    lobes, each with two side teeth, deep notches between, and a stem."""
    shape = Shape()
    c, cy = SIZE / 2, SIZE / 2 + 6
    # Lobes: angle from straight up (radians) and length.
    lobes = [(-2.15, 74), (-1.08, 106), (0.0, 112), (1.08, 106), (2.15, 74)]
    # Each lobe broad, with a tooth each side between its base and its tip.
    shape_of_lobe = ((-0.42, 0.62), (-0.32, 0.78), (-0.24, 0.68), (-0.12, 0.9), (0.0, 1.0), (0.12, 0.9),
                     (0.24, 0.68), (0.32, 0.78), (0.42, 0.62))
    points = []
    for index, (angle, length) in enumerate(lobes):
        for offset, scale in shape_of_lobe:
            points.append((angle + offset, length * scale))
        if index < len(lobes) - 1:
            points.append(((angle + lobes[index + 1][0]) / 2, 50))
    # The base, either side of the stem.
    points = [(-2.75, 34)] + points + [(2.75, 34)]
    shape.polygons.append([(c + math.sin(a) * r, cy - math.cos(a) * r) for a, r in points])
    vein = Shape()
    shape.capsule(c, cy + 26, c + 4, cy + 72, 4, 3)
    for angle, length in lobes:
        vein.capsule(c, cy, c + math.sin(angle) * length * 0.8, cy - math.cos(angle) * length * 0.8, 2.2, 1.4)
    shape.mid = vein
    return shape


def oak(seed):
    """An oak leaf: long, with rounded lobes down both sides."""
    shape = Shape()
    c = SIZE / 2
    points = []
    for index in range(160):
        t = 2 * math.pi * index / 160
        y = -math.sin(t)
        # Narrower toward the stem, rounded lobes along the sides.
        width = 70 * (0.5 + 0.5 * (1 + y) / 2) * (0.6 + 0.4 * abs(math.cos(4.5 * math.asin(y))))
        points.append((c + math.cos(t) * width, c - 6 - y * 92))
    shape.polygons.append(points)
    _leaf_parts(shape, c - 6 - 92, c - 6 + 92)
    return shape


def birch(seed):
    """A birch or aspen leaf: a simple oval with a saw-toothed edge."""
    shape = Shape()
    c = SIZE / 2
    points = []
    teeth = 26
    for index in range(teeth * 4):
        t = 2 * math.pi * index / (teeth * 4)
        saw = 1 + 0.06 * ((index % 4) / 3 - 0.5)
        x, y = 62 * math.cos(t) * saw, 86 * math.sin(t) * saw
        # A point at the tip: narrow the top half.
        if y < 0:
            x *= 1 - 0.35 * (-y / 86) ** 2
        points.append((c + x, c - 10 + y))
    shape.polygons.append(points)
    _leaf_parts(shape, c - 10 - 86, c - 10 + 86)
    return shape


def snowflake(seed):
    """A snowflake: six arms, each with two pairs of branches."""
    shape = Shape()
    c = SIZE / 2
    for index in range(6):
        angle = math.pi / 2 + index * math.pi / 3
        ex, ey = c + math.cos(angle) * 100, c + math.sin(angle) * 100
        shape.capsule(c, c, ex, ey, 7, 5)
        for along, length in ((0.45, 30), (0.72, 20)):
            bx, by = c + math.cos(angle) * 100 * along, c + math.sin(angle) * 100 * along
            for side in (-1, 1):
                branch = angle + side * math.pi / 3
                shape.capsule(bx, by, bx + math.cos(branch) * length, by + math.sin(branch) * length, 5, 4)
    shape.circle(c, c, 16)
    return shape


def pow(seed):
    """A cartoon "pow": a jagged burst with uneven points."""
    rng = random.Random(seed)
    shape = Shape()
    c = SIZE / 2
    points = []
    count = 13
    for index in range(2 * count):
        angle = math.pi * index / count + rng.uniform(-0.08, 0.08)
        radius = rng.uniform(88, 112) if index % 2 == 0 else rng.uniform(48, 62)
        points.append((c + math.cos(angle) * radius, c + math.sin(angle) * radius))
    shape.polygons.append(points)
    shape.rounding = 3
    return shape


def heart(seed):
    """A plump heart, for Tame's heal crits."""
    shape = Shape()
    c, scale = SIZE / 2, 6.2
    points = []
    for index in range(120):
        t = 2 * math.pi * index / 120
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        points.append((c + x * scale, c - (y + 2.5) * scale))
    shape.polygons.append(points)
    return shape


def sparkle(seed):
    """A four-point twinkle with a smaller one across it and a bright heart."""
    shape = Shape()
    c = SIZE / 2
    shape.polygons.append(star_points(c, c, 4, 108, 16, -math.pi / 2))
    shape.polygons.append(star_points(c, c, 4, 54, 12, -math.pi / 4))
    shape.circle(c, c, 16)
    return shape




def _blend(grey, part, x, y, part_grey):
    """Darkens toward part_grey where the point is inside part (anti-aliased)."""
    if part is None:
        return grey
    cover = max(0.0, min(1.0, 0.5 - part.distance(x, y)))
    return grey + (part_grey - grey) * cover


def _clamp(value):
    return max(0.0, min(1.0, value))


def burst(seed):
    """A starburst: a bright core and tapering rays of light, unevenly long."""
    rng = random.Random(seed)
    count = rng.randint(10, 14)
    rays = []
    for index in range(count):
        angle = 2 * math.pi * (index + rng.uniform(-0.25, 0.25)) / count
        rays.append((angle, rng.uniform(70, SIZE / 2 - 12), rng.uniform(0.07, 0.13)))

    def light(dx, dy):
        r = math.hypot(dx, dy)
        theta = math.atan2(dy, dx)
        ray = 0.0
        for angle, length, width in rays:
            if r >= length:
                continue
            off = abs((theta - angle + math.pi) % (2 * math.pi) - math.pi)
            reach = width * (1 - r / length) + 0.004
            ray = max(ray, _clamp(1 - off / reach) * (1 - r / length))
        core = math.exp(-(r / 22) ** 2)
        return 0.78 + 0.22 * core, _clamp(core + 0.9 * ray)
    return light


def mote(seed):
    """A glowing mote: a soft round glow with a faint cross of light."""
    def light(dx, dy):
        r = math.hypot(dx, dy)
        glow = math.exp(-(r / 26) ** 2)
        cross = max(math.exp(-(dx / 2.5) ** 2) * math.exp(-(abs(dy) / 22)),
                    math.exp(-(dy / 2.5) ** 2) * math.exp(-(abs(dx) / 22)))
        if r > SIZE / 2 - MARGIN:
            return 1.0, 0.0
        return 1.0, _clamp(glow + 0.6 * cross)
    return light


def ring(seed):
    """A soft ring of light, for a big crit's flash."""
    def light(dx, dy):
        r = math.hypot(dx, dy)
        edge = math.exp(-((r - 80) / 9) ** 2) + 0.3 * math.exp(-((r - 80) / 14) ** 2)
        return 1.0, _clamp(edge)
    return light




def smoke(seed):
    """A smoke cloud: overlapping soft puffs with tendrils curling out."""
    rng = random.Random(seed)
    puffs = []
    for _ in range(rng.randint(6, 9)):
        angle, reach = rng.uniform(0, 2 * math.pi), rng.uniform(0, 34)
        puffs.append((math.cos(angle) * reach, math.sin(angle) * reach, rng.uniform(20, 34), rng.uniform(0.5, 0.9)))
    for _ in range(rng.randint(3, 5)):
        angle, turn = rng.uniform(0, 2 * math.pi), rng.choice((-1, 1)) * rng.uniform(0.012, 0.025)
        # Close, overlapping puffs along a curl, thinning out.
        for step in range(32):
            r = 30 + step * 2.4
            a = angle + turn * r
            puffs.append((math.cos(a) * r, math.sin(a) * r, 11 - step * 0.25, 0.3 * (1 - step / 34)))

    def light(dx, dy):
        if math.hypot(dx, dy) > SIZE / 2 - MARGIN:
            return 0.0, 0.0
        density = 0.0
        for px, py, radius, weight in puffs:
            ex, ey = dx - px, dy - py
            if abs(ex) < radius * 3 and abs(ey) < radius * 3:
                density += weight * math.exp(-(ex * ex + ey * ey) / (radius * radius))
        alpha = _clamp(density) * 0.85
        # Darker where it is thickest.
        return 0.95 - 0.35 * _clamp(density - 0.5), alpha
    return light


def embers(seed):
    """A few embers or flakes of ash: small soft dots, no rays."""
    rng = random.Random(seed)
    dots = [(rng.uniform(-70, 70), rng.uniform(-70, 70), rng.uniform(3, 7)) for _ in range(rng.randint(5, 8))]

    def light(dx, dy):
        alpha = 0.0
        for px, py, radius in dots:
            alpha = max(alpha, math.exp(-((dx - px) ** 2 + (dy - py) ** 2) / (radius * radius)))
        return 1.0, alpha
    return light


def vignette(seed):
    """Dark at the screen's edges, clear in the middle: stretched over the screen."""
    def light(dx, dy):
        nx, ny = abs(dx) / (SIZE / 2), abs(dy) / (SIZE / 2)
        d = (nx ** 4 + ny ** 4) ** 0.25
        return 0.0, 0.95 * _clamp((d - 0.55) / 0.45) ** 1.6
    return light


def lightvignette(seed):
    """Vignette1's frame in white, for a theme that tints it (Naturalist's deep green)."""
    dark = vignette(seed)

    def light(dx, dy):
        return 1.0, dark(dx, dy)[1]
    return light


def claw(seed):
    """Claw rakes: two, three, or four (2 + seed % 3) roughly parallel gashes,
    unevenly spaced, curved a little, each
    swelling in the middle and tapering to a point at both ends, with a few
    flecks thrown off."""
    rng = random.Random(seed)
    shape = Shape()
    c = SIZE / 2
    marks = 2 + seed % 3
    angle = rng.uniform(-1.05, -0.75)
    along, across = (math.cos(angle), math.sin(angle)), (-math.sin(angle), math.cos(angle))
    bend = rng.uniform(10, 18)
    gap = rng.uniform(22, 30)
    for mark in range(marks):
        offset = (mark - (marks - 1) / 2) * gap + rng.uniform(-5, 5)
        length = rng.uniform(84, 100) * (0.85 if mark in (0, marks - 1) else 1)
        shift = rng.uniform(-10, 10)
        steps = 10
        points = []
        for step in range(steps + 1):
            t = step / steps
            u = (t - 0.5) * 2 * length + shift
            v = offset + bend * (1 - (2 * t - 1) ** 2)
            points.append((c + along[0] * u + across[0] * v, c + along[1] * u + across[1] * v,
                           0.6 + 6.5 * math.sin(math.pi * t) ** 0.8))
        for (ax, ay, ra), (bx, by, rb) in zip(points, points[1:]):
            shape.capsule(ax, ay, bx, by, ra, rb)
        for _ in range(rng.randint(2, 4)):
            t = rng.uniform(0.25, 0.75)
            x, y, _ = points[int(t * steps)]
            shape.circle(x + rng.uniform(-14, 14), y + rng.uniform(4, 22), rng.uniform(1.4, 3.2))
    return shape


def bite(seed):
    """A bite mark: an upper and a lower arc of punctures, the canines at
    each end deeper, a few trickling a little."""
    rng = random.Random(seed)
    shape = Shape()
    c = SIZE / 2
    for jaw, (cy, sign) in enumerate(((c - 14, -1), (c + 14, 1))):
        teeth = 7 if jaw == 0 else 6
        for tooth in range(teeth):
            t = tooth / (teeth - 1)
            x = c + (t - 0.5) * 2 * 74
            y = cy + sign * 34 * (1 - (2 * t - 1) ** 2) * -1 + sign * 6
            canine = tooth in (1, teeth - 2)
            rx, ry = (10, 14) if canine else (rng.uniform(6, 8), rng.uniform(7, 10))
            shape.ellipse(x + rng.uniform(-2, 2), y + rng.uniform(-2, 2), rx, ry, rng.uniform(-0.3, 0.3))
            if canine or rng.random() < 0.3:
                length = rng.uniform(14, 34) if canine else rng.uniform(8, 16)
                width = 3.6 if canine else 2.4
                shape.capsule(x, y, x + rng.uniform(-2, 2), y + length, width, width * 0.7)
                shape.circle(x, y + length + 1, width * 1.4)
    return shape


def insect(seed):
    """A beetle seen from above: a round shell split down the middle, a head
    with two feelers, and three bent legs a side."""
    shape = Shape()
    c = SIZE / 2
    shape.ellipse(c, c + 16, 42, 58, 0)
    shape.ellipse(c, c - 40, 26, 16, 0)
    shape.circle(c, c - 60, 16)
    for side in (-1, 1):
        shape.capsule(c + side * 8, c - 72, c + side * 26, c - 104, 3, 2)
        shape.capsule(c + side * 26, c - 104, c + side * 40, c - 112, 2, 1.6)
        for leg, (y, out, foot) in enumerate(((c - 30, 58, -24), (c + 6, 66, 6), (c + 40, 60, 36))):
            knee = (c + side * out, y + foot * 0.4)
            shape.capsule(c + side * 30, y, knee[0], knee[1], 4.5, 3.5)
            shape.capsule(knee[0], knee[1], knee[0] + side * 14, y + foot + 14, 3.5, 2)
    dark = Shape()
    dark.capsule(c, c - 36, c, c + 70, 2.2, 1.6)
    dark.ellipse(c, c - 60, 9, 7, 0)
    shape.dark = dark
    return shape


def vine(seed):
    """A vine sprouting up: a stem swaying up from the bottom, curling into a
    spiral at the top, with small leaves along it and a tendril."""
    rng = random.Random(seed)
    shape = Shape()
    c = SIZE / 2
    points = []
    for step in range(15):
        t = step / 14
        points.append((c + 18 * math.sin(t * 2.6 + 0.4), SIZE - 14 - t * 150, 7.5 - 3 * t))
    # The curl: a shrinking spiral from the stem's top.
    x, y, r = points[-1]
    turns = 22
    for step in range(1, turns + 1):
        t = step / turns
        angle = math.pi + t * 1.7 * math.pi
        radius = 38 * (1 - 0.65 * t)
        points.append((x + 38 + math.cos(angle) * radius, y - math.sin(angle) * radius * 0.9, 4.5 - 2.5 * t))
    for (ax, ay, ra), (bx, by, rb) in zip(points, points[1:]):
        shape.capsule(ax, ay, bx, by, ra, rb)
    mid = Shape()
    for index, side in ((3, -1), (6, 1), (9, -1), (12, 1)):
        px, py, _ = points[index]
        angle = side * 0.9 - 0.3 * side
        lx, ly = px + side * 22, py - 10
        shape.ellipse(lx, ly, 20, 9, -angle)
        mid.capsule(px, py, lx + side * 12, ly - 4, 1.4, 1)
    # A tendril off the stem.
    tx, ty, _ = points[7]
    for step in range(8):
        a0, a1 = step * 0.7, (step + 1) * 0.7
        r0, r1 = 16 - step * 1.6, 16 - (step + 1) * 1.6
        shape.capsule(tx - 18 - math.cos(a0) * r0, ty - math.sin(a0) * r0,
                      tx - 18 - math.cos(a1) * r1, ty - math.sin(a1) * r1, 2, 1.6)
    shape.mid = mid
    rng.random()
    return shape


def firework(seed):
    """A firework spray: many thin streaks out from the middle, each ending in
    a bright spark, a few sparks falling short; white, drawn additively."""
    rng = random.Random(seed)
    streaks = []
    count = 26
    for index in range(count):
        angle = 2 * math.pi * (index + rng.uniform(-0.3, 0.3)) / count
        streaks.append((math.cos(angle), math.sin(angle), rng.uniform(72, SIZE / 2 - 14)))
    sparks = [(cos * length, sin * length, 5.0) for cos, sin, length in streaks]
    for _ in range(18):
        angle, reach = rng.uniform(0, 2 * math.pi), rng.uniform(30, 90)
        sparks.append((math.cos(angle) * reach, math.sin(angle) * reach, 3.0))

    def light(dx, dy):
        r = math.hypot(dx, dy)
        best = 0.0
        if r > 1:
            ux, uy = dx / r, dy / r
            for cos, sin, length in streaks:
                if r > length or ux * cos + uy * sin < 0.9:
                    continue
                off = abs(dx * sin - dy * cos)
                best = max(best, math.exp(-(off / 1.4) ** 2) * (0.25 + 0.75 * r / length))
        for sx, sy, size in sparks:
            if abs(dx - sx) < size * 3 and abs(dy - sy) < size * 3:
                best = max(best, math.exp(-((dx - sx) ** 2 + (dy - sy) ** 2) / size ** 2))
        best = max(best, 0.6 * math.exp(-(r / 14) ** 2))
        return 1.0, _clamp(best)
    return light


def crack(seed):
    """Creeping cracks: jagged lines branching out from the middle."""
    rng = random.Random(seed)
    shape = Shape()
    c = SIZE / 2

    def grow(x, y, angle, width, depth):
        steps = rng.randint(4, 7)
        for _ in range(steps):
            angle += rng.uniform(-0.6, 0.6)
            length = rng.uniform(9, 16)
            nx, ny = x + math.cos(angle) * length, y + math.sin(angle) * length
            if math.hypot(nx - c, ny - c) > c - 10:
                return
            shape.capsule(x, y, nx, ny, width, width * 0.85)
            x, y, width = nx, ny, width * 0.85
            if depth < 2 and rng.random() < 0.3:
                grow(x, y, angle + rng.choice((-1, 1)) * rng.uniform(0.6, 1.1), width * 0.8, depth + 1)

    for index in range(rng.randint(5, 7)):
        grow(c, c, 2 * math.pi * index / 6 + rng.uniform(-0.3, 0.3), 3.2, 0)
    shape.circle(c, c, 6)
    return shape


BUILDERS = {"splat": splat, "drip": drip, "run": run, "butterfly": butterfly, "star": star, "sparkle": sparkle,
            "heart": heart, "flame": flame, "shard": shard, "snowflake": snowflake, "pow": pow, "maple": maple,
            "oak": oak, "birch": birch,
            "burst": burst, "mote": mote, "ring": ring, "smoke": smoke, "embers": embers, "vignette": vignette,
            "crack": crack, "claw": claw, "bite": bite, "insect": insect, "vine": vine, "firework": firework,
            "lightvignette": lightvignette}


def glow_pixels(kind, seed, size=SIZE):
    light = BUILDERS[kind](seed)
    step = SIZE / size
    out = bytearray()
    for y in range(size):
        for x in range(size):
            level, alpha = light((x + 0.5) * step - SIZE / 2, (y + 0.5) * step - SIZE / 2)
            # The faintest glow is cut, which also keeps the file small.
            value = round(alpha * 255) if alpha >= GLOW_CUT else 0
            if value == 0:
                out += b"\x00\x00\x00\x00"
                continue
            grey = round(255 * level)
            out += bytes((grey, grey, grey, value))
    return bytes(out)


def rainbow_pixels():
    """A cartoon rainbow: six pastel bands in an arc, a cloud at each end,
    each with the same darker rim as Tame's other art."""
    c, base = SIZE / 2, SIZE / 2 + 34
    outer, inner = 104.0, 56.0
    band = (outer - inner) / len(RAINBOW_BANDS)
    clouds = Shape()
    for side in (-1, 1):
        x = c + side * (outer + inner) / 2
        for dx, dy, r in ((0, 6, 20), (side * -16, 12, 15), (side * 16, 12, 15), (0, 20, 14)):
            clouds.circle(x + dx, base + dy, r)
    out = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            px, py = x + 0.5, y + 0.5
            r = math.hypot(px - c, py - base)
            arc = max(r - outer, inner - r)
            if py > base:
                arc = max(arc, py - base)
            cloud = clouds.distance(px, py)
            d = min(arc, cloud)
            alpha = max(0.0, min(1.0, 0.5 - d))
            if alpha == 0:
                out += b"\x00\x00\x00\x00"
                continue
            rim = RIM_GREY + (1 - RIM_GREY) * max(0.0, min(1.0, -d / RIM))
            if cloud <= arc:
                color = (255, 255, 255)
            else:
                index = min(len(RAINBOW_BANDS) - 1, max(0, int((outer - r) / band)))
                color = RAINBOW_BANDS[index]
            red, green, blue = (round(channel * rim) for channel in color)
            out += bytes((blue, green, red, round(alpha * 255)))
    return bytes(out)


def pixels(name):
    """BGRA bytes, top row first."""
    kind, seed = TEXTURE_SPECS[name]
    if kind in COLORED_KINDS:
        return rainbow_pixels()
    if kind in SOFT_KINDS:
        return glow_pixels(kind, seed, texture_size(name))
    shape = BUILDERS[kind](seed)
    cute = kind in RIMMED_KINDS
    rounding = getattr(shape, "rounding", 0)
    out = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            px, py = x + 0.5, y + 0.5
            d = shape.distance(px, py) - rounding
            alpha = max(0.0, min(1.0, 0.5 - d))
            if alpha == 0:
                out += b"\x00\x00\x00\x00"
                continue
            if cute:
                level = RIM_GREY + (1 - RIM_GREY) * max(0.0, min(1.0, -d / RIM))
                level = _blend(level, shape.mid, px, py, SPOT_GREY)
                level = _blend(level, shape.dark, px, py, BODY_GREY)
            else:
                level = 1 - (1 - DARKEST) * max(0.0, min(1.0, -d / DEPTH))
            grey = round(255 * level)
            out += bytes((grey, grey, grey, round(alpha * 255)))
    return bytes(out)


def rle(data):
    """TGA run-length packets over 4-byte pixels."""
    count = len(data) // 4
    out = bytearray()
    index = 0
    while index < count:
        pixel = data[index * 4:index * 4 + 4]
        run = 1
        while (index + run < count and run < MAX_RUN
               and data[(index + run) * 4:(index + run) * 4 + 4] == pixel):
            run += 1
        if run > 1:
            out.append(0x80 | (run - 1))
            out += pixel
            index += run
            continue
        start = index
        index += 1
        while (index < count and index - start < MAX_RUN
               and not (index + 1 < count and data[index * 4:index * 4 + 4] == data[(index + 1) * 4:(index + 1) * 4 + 4])):
            index += 1
        out.append(index - start - 1)
        out += data[start * 4:index * 4]
    return bytes(out)


def build(name):
    size = texture_size(name)
    header = bytes((0, 0, TGA_RLE)) + bytes(9) + size.to_bytes(2, "little") + size.to_bytes(2, "little") \
        + bytes((32, 0x28))
    return header + rle(pixels(name))


def decode(data):
    """Pixels from a TGA this script wrote (for the tests and the preview)."""
    width = int.from_bytes(data[12:14], "little")
    height = int.from_bytes(data[14:16], "little")
    body = data[18 + data[0]:]
    out = bytearray()
    index = 0
    while len(out) < width * height * 4:
        packet = body[index]
        index += 1
        count = (packet & 0x7F) + 1
        if packet & 0x80:
            out += body[index:index + 4] * count
            index += 4
        else:
            out += body[index:index + 4 * count]
            index += 4 * count
    if index != len(body) or len(out) != width * height * 4:
        raise ValueError("TGA run-length data does not match its size")
    return width, height, bytes(out)


def png(width, height, rows):
    """A PNG from RGB rows of bytes."""
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def cute_names():
    return [name for name, (kind, _) in TEXTURE_SPECS.items() if kind in CUTE_KINDS]


def splat_names():
    return [name for name, (kind, _) in TEXTURE_SPECS.items()
            if kind not in CUTE_KINDS | GLOW_KINDS | FEL_KINDS | SCHOOL_KINDS | NATURALIST_KINDS]


def school_names():
    return [name for name, (kind, _) in TEXTURE_SPECS.items() if kind in SCHOOL_KINDS]


def fel_names():
    return [name for name, (kind, _) in TEXTURE_SPECS.items() if kind in FEL_KINDS]


def naturalist_names():
    return [name for name, (kind, _) in TEXTURE_SPECS.items() if kind in NATURALIST_KINDS]


def glow_names():
    return [name for name, (kind, _) in TEXTURE_SPECS.items() if kind in GLOW_KINDS]


def preview(textures, names=None, tints=None):
    """Textures tinted (Brutal red, or each its own tint), on a light strip above a dark one."""
    names = names or splat_names()
    tints = tints or [BRUTAL] * len(names)
    gap = 16
    width = len(names) * (SIZE + gap) + gap
    height = 2 * (SIZE + gap) + gap
    backgrounds = ((214, 206, 192), (34, 30, 28))
    canvas = [bytearray(bytes(backgrounds[0 if y < height // 2 else 1]) * width) for y in range(height)]
    for column, name in enumerate(names):
        texture_width, _, data = decode(textures[name])
        for strip, background in enumerate(backgrounds):
            ox = gap + column * (SIZE + gap)
            oy = gap + strip * (SIZE + gap)
            for y in range(SIZE):
                row = canvas[oy + y]
                for x in range(SIZE):
                    # A smaller texture is drawn stretched, as the client does.
                    index = ((y * texture_width // SIZE) * texture_width + x * texture_width // SIZE) * 4
                    b, g, r, a = data[index:index + 4]
                    if not a:
                        continue
                    alpha = a / 255
                    # Per channel, so a colored texture (the rainbow) shows its own colors.
                    for channel, value in enumerate((r, g, b)):
                        tinted = value / 255 * tints[column][channel] * 255
                        row[(ox + x) * 3 + channel] = round(tinted * alpha + background[channel] * (1 - alpha))
    return png(width, height, [bytes(row) for row in canvas])


def _sample(data, u, v):
    """The texture's pixel at (u, v) in texture pixels, or None outside it."""
    x, y = int(u), int(v)
    if 0 <= x < SIZE and 0 <= y < SIZE:
        index = (y * SIZE + x) * 4
        return data[index + 2] / 255, data[index + 3] / 255
    return None


def _draw(canvas, data, tint, box, scale_x=1.0, scale_y=1.0, turn=0.0, origin="center"):
    """Draws a texture into box (x, y, size) with the client's transforms:
    scale about the center (or the top edge), then a turn about the center."""
    bx, by, size = box
    ratio = SIZE / size
    cos, sin = math.cos(-turn), math.sin(-turn)
    oy = 0.0 if origin == "top" else size / 2
    for y in range(int(size)):
        row = canvas[by + y]
        for x in range(int(size)):
            # Undo the turn about the center, then the scale about its origin.
            dx, dy = x - size / 2, y - size / 2
            rx, ry = dx * cos - dy * sin, dx * sin + dy * cos
            u = (rx / scale_x + size / 2) * ratio
            v = ((ry + size / 2 - oy) / scale_y + oy) * ratio
            got = _sample(data, u, v)
            if not got or not got[1]:
                continue
            shade, alpha = got
            for channel in range(3):
                old = row[(bx + x) * 3 + channel]
                row[(bx + x) * 3 + channel] = round(shade * tint[channel] * 255 * alpha + old * (1 - alpha))


def motion_preview(textures):
    """Frames of each looping animation, left to right, one row each."""
    frames, cell, gap = 6, 128, 12
    width = frames * (cell + gap) + gap
    rows = 4
    height = rows * (cell + gap) + gap + cell // 2
    background = (34, 30, 28)
    canvas = [bytearray(bytes(background) * width) for _ in range(height)]
    data = {name: decode(textures[name])[2] for name in textures}

    def box(row, frame, size=cell, dy=0):
        return (gap + frame * (cell + gap) + (cell - size) // 2, gap + row * (cell + gap) + dy, size)

    for frame in range(frames):
        t = frame / (frames - 1)
        # Stars spin a full turn (here a fifth of one across the strip).
        _draw(canvas, data["Star1.tga"], PASTELS[2], box(0, frame), turn=t * 2 * math.pi / 5)
        # Butterflies pinch their wings and back.
        pinch = 1 - 0.45 * math.sin(t * math.pi)
        _draw(canvas, data["Butterfly1.tga"], PASTELS[0], box(1, frame), scale_x=pinch)
        # Sparkles swell and shrink.
        grow = 0.85 + 0.35 * math.sin(t * math.pi)
        size = int(cell * grow)
        _draw(canvas, data["Sparkle1.tga"], PASTELS[3], box(2, frame, size, (cell - size) // 2))
        # Brutal: the run grows down from under a splat that stays put.
        splat, run_size = 96, 96
        sx, sy, _ = box(3, frame, splat)
        stretch = max(0.05, t)
        _draw(canvas, data["Run1.tga"], BRUTAL, (sx, sy + splat // 2 - 8, run_size), scale_y=stretch, origin="top")
        _draw(canvas, data["Splat2.tga"], BRUTAL, (sx, sy, splat))
    return png(width, height, [bytes(row) for row in canvas])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=TEXTURES)
    parser.add_argument("--preview", action="store_true", help="also write " + str(PREVIEW.relative_to(ROOT)))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    textures = {}
    for name in TEXTURE_SPECS:
        textures[name] = build(name)
        (args.output_dir / name).write_bytes(textures[name])
    if args.preview:
        PREVIEW.parent.mkdir(parents=True, exist_ok=True)
        PREVIEW.write_bytes(preview(textures))
        names = cute_names()
        tints = [PASTELS[i % len(PASTELS)] for i in range(len(names))]
        names.append("Rainbow1.tga")
        tints.append((1, 1, 1))
        TAME_PREVIEW.write_bytes(preview(textures, names, tints))
        MOTION_PREVIEW.write_bytes(motion_preview(textures))
        names = glow_names()
        SPELLBURST_PREVIEW.write_bytes(preview(textures, names, [SCHOOLS[i % len(SCHOOLS)] for i in range(len(names))]))
        names = fel_names()
        FEL_PREVIEW.write_bytes(preview(textures, names, [FEL[i % len(FEL)] for i in range(len(names))]))
        names = naturalist_names()
        naturalist = {"claw": BRUTAL, "bite": BRUTAL, "insect": (0.3, 0.32, 0.12), "vine": (0.45, 0.75, 0.3),
                "firework": (0.85, 0.88, 0.95), "lightvignette": (0.05, 0.25, 0.05)}
        NATURALIST_PREVIEW.write_bytes(preview(textures, names, [naturalist[TEXTURE_SPECS[name][0]] for name in names]))
        names = school_names()
        tints = ((1, 0.5, 0.12), (0.55, 0.85, 1), (0.8, 0.92, 1), (1, 0.85, 0.3), (1, 0.6, 0.55), (1, 0.75, 0.45),
                 (0.65, 0.92, 0.55))
        SCHOOL_PREVIEW.write_bytes(preview(textures, names, [tints[i % len(tints)] for i in range(len(names))]))


if __name__ == "__main__":
    main()
