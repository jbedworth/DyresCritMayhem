"""Splatter texture tests. Run: python3 -m unittest discover -s tests -p test_splatters.py"""

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("build_splatters", ROOT / "scripts" / "build_splatters.py")
splatters = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(splatters)
BUILDER_SPEC = importlib.util.spec_from_file_location("build_release", ROOT / "scripts" / "build_release.py")
builder = importlib.util.module_from_spec(BUILDER_SPEC)
BUILDER_SPEC.loader.exec_module(builder)


class SplatterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.built = {name: splatters.build(name) for name in splatters.TEXTURE_SPECS}

    def test_committed_textures_match_the_build(self):
        for name, data in self.built.items():
            self.assertEqual((ROOT / "Textures" / name).read_bytes(), data, name)

    def test_the_build_is_deterministic(self):
        for name, data in self.built.items():
            self.assertEqual(splatters.build(name), data, name)

    def test_textures_pass_the_release_check_and_stay_small(self):
        for name, data in self.built.items():
            builder._validate_tga(name, data)
            # Soft glows pack less well than hard edges; still modest.
            self.assertLess(len(data), 80 * 1024, name)

    def test_the_run_length_data_decodes_to_the_pixels(self):
        for name in splatters.TEXTURE_SPECS:
            width, height, data = splatters.decode(self.built[name])
            size = splatters.texture_size(name)
            self.assertEqual((width, height), (size, size))
            self.assertEqual(data, splatters.pixels(name), name)

    def test_nothing_touches_the_edge_and_each_has_enough_blood(self):
        size = splatters.SIZE
        for name, (kind, _) in splatters.TEXTURE_SPECS.items():
            if kind in ("vignette", "lightvignette"):
                # They frame the screen, so it reaches its edges by design.
                continue
            _, _, data = splatters.decode(self.built[name])
            alphas = data[3::4]
            for index in range(size):
                for x, y in ((index, 0), (index, size - 1), (0, index), (size - 1, index)):
                    self.assertEqual(alphas[y * size + x], 0, f"{name} edge at {x},{y}")
            covered = sum(1 for alpha in alphas if alpha) / len(alphas)
            # A few embers cover little; everything else at least 5%.
            self.assertGreater(covered, 0.005 if kind == "embers" else 0.05, name)
            self.assertLess(covered, 0.5, name)

    def test_the_grey_is_darker_deep_in_the_pool(self):
        for name in [name for name, (kind, _) in splatters.TEXTURE_SPECS.items() if kind in ("splat", "drip")]:
            _, _, data = splatters.decode(self.built[name])
            greys = {data[index] for index in range(0, len(data), 4) if data[index + 3] == 255}
            self.assertEqual(min(greys), round(255 * splatters.DARKEST), name)
            self.assertGreater(max(greys), 240, name)
            for index in range(0, len(data), 4):
                b, g, r = data[index:index + 3]
                self.assertTrue(b == g == r, name)

    def test_the_run_is_one_trickle_down_the_middle_darker_inside(self):
        size = splatters.SIZE
        _, _, data = splatters.decode(self.built["Run1.tga"])
        middle = size // 2
        top = [data[(y * size + middle) * 4 + 3] for y in range(size)]
        first = next(y for y, alpha in enumerate(top) if alpha)
        last = max(y for y, alpha in enumerate(top) if alpha)
        self.assertLess(first, 12, "starts near the top, under its splat")
        self.assertGreater(last, size - 40, "reaches near the foot")
        # Narrow: nothing in the outer quarters.
        for y in range(size):
            for x in list(range(size // 4)) + list(range(3 * size // 4, size)):
                self.assertEqual(data[(y * size + x) * 4 + 3], 0)
        greys = [data[(y * size + middle) * 4] for y in range(first + 20, last - 20)]
        self.assertLess(min(greys), 200, "darker inside")

    def test_fel_has_no_sparkle_and_its_vignette_frames_the_screen(self):
        names = splatters.fel_names()
        self.assertEqual(names, ["Smoke1.tga", "Smoke2.tga", "Embers1.tga", "Crack1.tga", "Vignette1.tga"])
        width, _, data = splatters.decode(self.built["Vignette1.tga"])
        self.assertEqual(width, 64)
        alpha = lambda x, y: data[(y * width + x) * 4 + 3]
        self.assertEqual(alpha(width // 2, width // 2), 0, "clear in the middle")
        self.assertGreater(alpha(0, width // 2), 200, "dark at the edges")
        self.assertGreater(alpha(0, 0), 200)
        self.assertEqual({data[index] for index in range(0, len(data), 4) if data[index + 3]}, {0}, "black")

    def test_the_rainbow_is_colored_with_a_rim_and_clear_below(self):
        _, _, data = splatters.decode(self.built["Rainbow1.tga"])
        size = splatters.SIZE
        colors = {tuple(data[i:i + 3]) for i in range(0, len(data), 4) if data[i + 3] == 255}
        self.assertGreater(len({(b, g, r) for b, g, r in colors if not (b == g == r)}), 6, "colored bands")
        # The middle of its arc's foot is clear: an arc, not a disc.
        middle = (size // 2 + 40) * size + size // 2
        self.assertEqual(data[middle * 4 + 3], 0)

    def test_cute_textures_are_white_inside_with_a_darker_rim(self):
        names = splatters.cute_names()
        self.assertEqual(names, ["Butterfly1.tga", "Butterfly2.tga", "Star1.tga", "Sparkle1.tga", "Heart1.tga"])
        for name in names:
            _, _, data = splatters.decode(self.built[name])
            greys = [data[index] for index in range(0, len(data), 4) if data[index + 3] == 255]
            self.assertEqual(max(greys), 255, name)
            # The rim: the first opaque pixels are clearly darker than the inside.
            self.assertLess(min(greys), 180, name)
            # Mostly light, so a pastel tint stays pastel.
            light = sum(1 for grey in greys if grey >= 230) / len(greys)
            self.assertGreater(light, 0.5, name)
        _, _, data = splatters.decode(self.built["Butterfly1.tga"])
        center = (splatters.SIZE // 2 * splatters.SIZE + splatters.SIZE // 2) * 4
        self.assertEqual(data[center], round(255 * splatters.BODY_GREY), "the body is dark")

    def test_themes_lua_names_every_texture(self):
        source = (ROOT / "Themes.lua").read_text(encoding="utf-8")
        for name in splatters.TEXTURE_SPECS:
            self.assertTrue('TEXTURES .. "' + name[:-4] + '"' in source or 'T("' + name[:-4] + '")' in source, name)

    def test_the_preview_is_a_png(self):
        for data in (splatters.preview(self.built),
                     splatters.preview(self.built, splatters.cute_names(),
                                       [splatters.PASTELS[i % 4] for i in range(len(splatters.cute_names()))])):
            self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertTrue(splatters.motion_preview(self.built).startswith(b"\x89PNG\r\n\x1a\n"))


class ToolkitCopyTests(unittest.TestCase):
    def test_the_suites_toolkit_copy_matches_the_toolkit(self):
        toolkit = ROOT.parent / "DyresToolkit"
        if not toolkit.is_dir():
            self.skipTest("no ../DyresToolkit checkout")
        for name in ("Core.lua", "Layout.lua", "Widgets.lua", "Settings.lua"):
            self.assertEqual((ROOT / "tests" / "toolkit" / name).read_bytes(), (toolkit / name).read_bytes(),
                             name)


if __name__ == "__main__":
    unittest.main()
