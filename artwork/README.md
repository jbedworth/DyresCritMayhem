# Dyre's Crit Mayhem artwork

## Logo

Original vector artwork: a gold crit starburst with a bold exclamation mark,
bursting over a deep red blood splatter that drips below it, on the rich
dark-brown field and fine gold border the other Dyre's AddOns' logos share.
No font or external-image dependencies.

- `dyres-crit-mayhem-logo.svg`: editable, resolution-independent source.
- `dyres-crit-mayhem-logo.png`: 1024 x 1024 PNG master.
- `dyres-crit-mayhem-logo-512.png`: 512 x 512 PNG for square project images.

The PNGs are rendered from the SVG with headless Chrome, for example:

```sh
chrome --headless=new --hide-scrollbars --window-size=1024,1024 --force-device-scale-factor=0.5 --screenshot=dyres-crit-mayhem-logo-512.png dyres-crit-mayhem-logo.svg
```

## Splatters

`splatters-preview.png` shows the six splatter textures tinted Brutal red,
and `tame-preview.png` the Tame theme's butterflies, star, and sparkle in its
pastels, each on a light and a dark strip, for review (Textures/, made by
`scripts/build_splatters.py --preview`). Rebuild them whenever the textures
change. `fel-preview.png` shows Fel's smoke, embers, crack, and vignette in its
palette (the vignette stretched, as on screen).
`spellburst-preview.png` shows Spellburst's glows (two bursts, a mote, a
ring) tinted by school; in the client they are drawn as added light.
`motion-preview.png` shows frames of each moving effect: a star
turning, a butterfly fluttering, a sparkle twinkling, and a run growing
down from under a Brutal splat.

Keep this directory out of the runtime release ZIP; the TOC uses a built-in
client icon (Ability_Rogue_Eviscerate).

This artwork is covered by the repository's MIT License. Copyright (c) 2026
John Bedworth. Include the applicable license notice with distributed copies.
