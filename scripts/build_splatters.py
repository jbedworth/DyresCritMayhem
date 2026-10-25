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
}
CUTE_KINDS = {"butterfly", "star", "sparkle", "heart"}
# Spellburst's glows: soft-edged, white, drawn additively and tinted by spell
# school in the client.
GLOW_KINDS = {"burst", "mote", "ring"}
# Fel's dark kinds: soft smoke and embers, and a full-screen vignette (the one
# texture that reaches its edges, since it frames the screen).
SOFT_KINDS = GLOW_KINDS | {"smoke", "embers", "vignette"}
FEL_KINDS = {"smoke", "embers", "crack", "vignette"}
# Textures smaller than SIZE: the vignette is a smooth gradient stretched over
# the whole screen, so 64 pixels lose nothing and keep the file small.
SIZES = {"Vignette1.tga": 64}


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
            "heart": heart,
            "burst": burst, "mote": mote, "ring": ring, "smoke": smoke, "embers": embers, "vignette": vignette,
            "crack": crack}


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


def pixels(name):
    """BGRA bytes, top row first."""
    kind, seed = TEXTURE_SPECS[name]
    if kind in SOFT_KINDS:
        return glow_pixels(kind, seed, texture_size(name))
    shape = BUILDERS[kind](seed)
    cute = kind in CUTE_KINDS
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
    return [name for name, (kind, _) in TEXTURE_SPECS.items() if kind not in CUTE_KINDS | GLOW_KINDS | FEL_KINDS]


def fel_names():
    return [name for name, (kind, _) in TEXTURE_SPECS.items() if kind in FEL_KINDS]


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
                    shade = r / 255
                    for channel in range(3):
                        tinted = shade * tints[column][channel] * 255
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
        TAME_PREVIEW.write_bytes(preview(textures, names, [PASTELS[i % len(PASTELS)] for i in range(len(names))]))
        MOTION_PREVIEW.write_bytes(motion_preview(textures))
        names = glow_names()
        SPELLBURST_PREVIEW.write_bytes(preview(textures, names, [SCHOOLS[i % len(SCHOOLS)] for i in range(len(names))]))
        names = fel_names()
        FEL_PREVIEW.write_bytes(preview(textures, names, [FEL[i % len(FEL)] for i in range(len(names))]))


if __name__ == "__main__":
    main()
