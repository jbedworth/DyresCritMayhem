# CurseForge listing

Copy-ready text for the CurseForge project form. Keep it aligned with README.md
and the tested clients; do not advertise clients or versions that have not been
tested. Draft: the project does not exist yet (the author creates it).

## Project fields

| Field | Value |
| --- | --- |
| Name | Dyre's Crit Mayhem |
| Class | Addons |
| Main category | Combat. Keep it identical to the TOC `## Category`, which groups the AddOn in the in-game AddOn list. |
| Additional categories | Audio & Video (CurseForge allows up to 4; unrelated ones can send the project back for changes). |
| Author shown | Dyre, set through the CurseForge account's username |
| License | MIT License |
| Logo | artwork/dyres-crit-mayhem-logo.png (1024 x 1024) |
| Source | https://github.com/jbedworth/DyresCritMayhem (once the author creates it) |
| Issues | https://github.com/jbedworth/DyresCritMayhem/issues |
| Donation | Ko-fi, https://ko-fi.com/dyre_janelle (the project's Donation field) |
| Relations | Required dependencies: Dyre's Toolkit (`dyres-toolkit`) and Dyre's Sounds (`dyres-sounds`). Each upload sets them (`RELATIONS` in scripts/publish_curseforge.py); the project's Default Relations should list the same two. |
| Game versions | Classic Era and Anniversary once tested there; WoW: Forever once confirmed after launch. |

## Summary

Dial up the mayhem on your crits: from cute butterflies to blood on the screen, Off to Total Mayhem, with themes and your personal records for every ability.

## Screenshots

Upload the PNGs in artwork/screenshots/ (taken on Classic Era):

| File | Title | Description |
| --- | --- | --- |
| artwork/screenshots/brutal-blood.png | Brutal | Melee crits on the Brutal theme (18+): blood splatter, some of it running down the screen. |
| artwork/screenshots/tame-butterflies.png | Tame | The Tame theme, for everyone: butterflies, stars, and sparkles on your crits. |

Still to take in client: Spellburst and Fel crits; the records window; the
settings page with the theme and intensity; the new record pop.

## Description

Paste this with the description editor in Markdown mode. Pasted into the rich
text editor, the headings, bullets, and bold show as raw, escaped markdown.

Per-file changelogs need no manual text: each CI upload uses the version's
`CHANGELOG.md` section, through `release-notes.md`.

```markdown
**Dyre's Crit Mayhem** makes your crits feel like crits: a crunch, a squelch, and blood on the screen, as much as you dial up. It also keeps your personal records: every ability's highest hit and highest crit.

It starts **Off**, and it never changes your game settings (violence level, volume, or sound).

### Pick a theme
- **Tame** (the default): little pastel butterflies, stars, sparkles, and rainbows that float away with light chimes: the stars turn, the butterflies flutter, and the sparkles twinkle. No blood.
- **Brutal**: heavy flesh impacts, bone crunches, a squelch, and blood splatter that drips at High and Total Mayhem, some splats staying put while a trickle runs down from them, in original art; in Cat or Bear form, claw scratches and bites too. The Brutal theme is locked until you tick **I'm 18 or over** (once for your account).
- **Spellburst**, for casters and healers: bursts of light in your spell's school (fire, frost, arcane, shadow, nature, holy), glowing motes, and a ring of light for a new record. Crit heals show too.
- **Fel**, dark and demonic: smoke curling as it rises, falling embers, creeping cracks, and a dark shadow around the screen for a new record, in fel green, shadow, and hellfire. Like Brutal, it is locked until you tick **I'm 18 or over**.
- **Naturalist**, for Druids and nature, savage and a touch gory: claw scratches, bites, and splatter at any angle, dripping blood, on melee crits (or, with **Claws only in Cat or Bear form**, only in those forms and from a Hunter's pet), murky green bursts with insects and torn leaves on nature crits, silver fireworks for arcane, and burning, frozen, seared, or rotting leaves for the other schools. Crit heals sprout vines and green and gold smoke; a new record darkens the screen's edges in deep green. Also locked until you tick **I'm 18 or over**.
- More themes are on the way.

### By damage school
Each theme keeps its own look, and the damage school (physical, holy, fire, nature, frost, shadow, arcane) adds a color and a small touch: Brutal's wounds charred with embers or frozen with an ice shard, Fel's smoke with hellfire flame licks or rime, Spellburst's bursts colored by school with a flame, ice shard, or a puff of leaves. Nature crits bring leaves in every theme: blowing in Tame and Spellburst, blood-soaked and stuck on in Brutal, burning to ash in Fel. Melee crits are blood in every theme but Tame (Spellburst only with the 18+ box). Tame's are cartoon looks (a pow, little flames, snowflakes, leaves), never blood; tick **Random Effects** for Tame's stars, butterflies, and sparkles on every crit instead.

### Dial up the intensity
- **Off**, **Low**, **Medium**, **High**, **Total Mayhem**: each step is more, bigger, and stays longer.
- **Stays on screen**: 25% to 300% of your intensity's time (about 2.5 seconds at Low to 12 at Total Mayhem), with the seconds shown.
- Effects land under your action bars and unit frames, never in the middle of the screen, and fade on their own. Sounds and on-screen effects each have a switch.

### Which crits
Yours (on by default), others' crits on your target or on nearby enemies (Off, My target, or Nearby enemies; trimmed so a raid stays readable; records stay yours), your pet's, crits on you (blood at the edges of the screen), and crit heals, shown as gentle rising light in your theme's style (hearts on Tame, warm red and gold on Brutal, fel-green wisps on Fel, vines and green and gold smoke on Naturalist).

### Personal records
- Every ability's highest hit and highest crit on each character, yours and your pet's.
- A new record says so in your chat; you can also announce it in party, in guild, or with a pop on screen. A new crit record hits harder.
- `/dcm` opens your records, sortable by ability, highest hit, or highest crit.

### Commands
- `/dcm` your records, `/dcm options` the settings, `/dcm test` a crit at your intensity.
- `/dcm unlock`, `/dcm lock`, `/dcm reset` place the record pop; `/dcm resetrecords` starts over (it asks first).
- `/dcm probe` logs what the game tells AddOns about hits for 3 minutes, for troubleshooting.

### Sounds
Each theme plays 2-3 sounds at random for a crit, a new record, and extras: gore slices, chops, and wet splats on Brutal; kisses, swishes, and shimmers on Tame; wet smashes, mud splats, a heartbeat, and a demon growl on Fel; growls and roars on Naturalist. Pick your own for any of them in the settings.
- `/critmayhem` works the same, in case another AddOn uses `/dcm`.

### With Dyre's Toolkit and Dyre's Sounds
Needs Dyre's Toolkit 2.0 or later, and plays its sounds from Dyre's Sounds; the CurseForge app installs both with it. Settings are under Options > AddOns > Dyre's AddOns > Crit Mayhem.

### Compatibility
World of Warcraft Classic Era and Anniversary.

On WoW: Forever (to be confirmed at launch), crits are detected on your target (best solo; in a group, anyone's crit on your target or a nearby enemy plays); records come from combat text while you play solo, as best guesses.

Source, issues, and license (MIT): https://github.com/jbedworth/DyresCritMayhem
```
