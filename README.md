# Dyre's Crit Mayhem

Dial up the mayhem on your crits. **Dyre's Crit Mayhem** plays sounds and
splatters blood on your screen when you crit, as much as you choose, and keeps
your personal records: each ability's highest hit and highest crit.

It starts on **Tame** at **Low**: small, cute effects. Pick the **None**
theme to turn every effect off. It never changes
your volume or sound. The one game setting it changes is the violence level,
and only with an 18+ theme turned up (see Intensity).

For World of Warcraft Classic Era and Anniversary. WoW: Forever support is
built but unconfirmed until Forever launches (see Compatibility).

## The mayhem

- **Theme**, near the top of the settings, under **I'm 18 or over**:
  - **Tame** (the default): little pastel butterflies, stars, sparkles, and
    rainbows that float away, with light chimes: the stars turn, the butterflies
    flutter, and the sparkles twinkle. No blood.
  - **Brutal**: heavy impacts, crunches, and blood splatter, with a squelch
    from Medium and dripping blood from High. Some splats stay put while a
    trickle runs down from them, more often at higher intensities. In Cat
    or Bear form (and for a Hunter's pet) melee crits are claw scratches,
    bites, and splatter instead. Brutal
    is locked until you tick **I'm 18 or over** (once, for your whole
    account); untick it and those characters go back to Tame.
  - **Spellburst**, **Fel**, and **Naturalist** are styles of Brutal: the
    same blood, drips, and hit effects, but your own damage takes on the
    theme's character. Damage on you and other people's damage keep
    Brutal's plain look. Each is 18+, like Brutal, and keeps its own sounds.
    - **Spellburst**, for casters and healers: a glow in your spell's
      school color on every crit, and stronger, brighter spell hits.
    - **Fel**, dark and demonic: every school turns to dark blood, purple,
      and fel green, with cracks creeping from the wounds and a wisp of dark
      smoke on each crit. Even holy goes black, purple, and green: a
      Paladin on Fel is a shadowknight. A new record darkens the screen's
      edges. Wet smashes, mud splats, a heartbeat, and a demon growl.
    - **Naturalist**, for Druids and nature: melee crits mix claw
      scratches, bites, and splatter (or, with **Claws only in Cat or Bear
      form** ticked under the theme, only in those forms and for a Hunter's
      pet); the other schools take earthy tints (moss, bark, amber,
      silver), and nature crits throw leaves. Crit heals sprout vines and
      green and gold smoke; a new record darkens the screen's edges in deep
      green. Growls and roars.
  - More themes are planned.
- **By damage school**: Brutal's wounds are charred with embers, frozen
  with an ice shard, stuck with blood-soaked leaves, black ichor, crackling
  violet, or seared with a flare; the styles recolor the same looks. Tame's
  are cartoon looks, never blood (or tick **Random Effects**, under the
  theme, for its stars, butterflies, and sparkles on every crit). A spell
  of two schools shows one, magic first: fire, frost, shadow, arcane,
  nature, holy. `artwork/style-matrix-preview.png` shows them all.
- **Intensity**: Low (the default), Medium, High, and Total Mayhem, for any
  theme. To turn every effect off, pick the **None** theme, the first in the
  Theme list. Each step is more, bigger, and stays longer: about 2.5 seconds at
  Low up to 12 at Total Mayhem. With an 18+ theme (Brutal, Spellburst, Fel, Naturalist)
  it also turns up the game's own blood on hit models, its violence level:
  Low 3, Medium 4, High and Total Mayhem 5. None, a cute theme, or clearing
  the 18+ box puts your own level back.
- **Stays on screen**, right under it: 25% to 300% of your intensity's time,
  to tune how long without changing the intensity. It shows the seconds.
- **Which crits**: yours (on by default), **others' crits** (Off, My
  target, or Nearby enemies, the default: anyone's crit on your target or
  on an enemy with a nameplate shown; trimmed so a raid stays readable,
  and records stay yours), your pet's, crits on you
  (their blood lands at the edges of the screen), and crit heals: a sound and
  gentle rising light in your theme's style (hearts on Tame, warm red and
  gold on Brutal, never blood, holy and nature light on Spellburst, fel-green
  wisps on Fel, vines and green and gold smoke on Naturalist).
- Effects land under your action bars and unit frames, and your own crits
  never cover the middle of the screen. **On-screen effects** has a switch.
- **Hit effects on enemies** (on by default): every hit that does damage,
  damage over time too, plays its school's effect on the enemy, from its
  nameplate down over its body, following it: a blood spray for physical
  (18+), snow and ice for frost, the body burning for fire, sparks for
  arcane and nature, smoke for shadow, golden sparkles for holy, and green
  plus signs for heals, in your theme's style for your own damage. A crit
  doubles it. The game draws its own green cloud on a poisoned mob, so
  nature damage over time adds nothing. AddOns cannot draw on the mob
  itself, so this needs enemy nameplates on (V). Not in Tame yet.
- **Hit effects on you** (on by default): the same when you are hit or
  healed, over your character in the middle of the screen.
- Hits on bystanders (other players, guards, your friendly target) play
  their hit effects on their nameplates too, and their crits splatter
  your screen as others' crits, by **Others' crits**; never a record.
- **Sounds**: each theme has 2-3 sounds for a crit, a new record, and an
  extra (Brutal's squelch), one picked at random each time (Brutal's gore
  impacts and wet splats; Tame's kisses, swishes, and shimmers). Tick "my
  own sound" on a row to choose your own instead, whatever the theme;
  **Reset sounds to theme** puts the theme's back. They play on the Sound
  Effects channel and come from Dyre's Sounds (1.4.0 or later for Fel's
  own; an older one plays its earlier sounds). Fel has wet smashes, mud
  splats, a heartbeat, and a demon growl for a new record.

## Personal records

- Every ability's highest hit and highest crit on this character, yours and
  your pet's (and heals, with **Heals too**), in every theme, None included.
- A new record always says so in your chat, seen only by you. You can also
  announce it in **party**, in **guild** (at most one every 10 seconds), and
  **on screen** with a pop you can place.
- A new crit record hits harder: a bigger sound and more blood.
- `/dcm` opens your records: click a heading to sort by ability, highest
  hit, or highest crit. **Reset records** asks first, and only out of combat.

## Your profile

With Dyre's Toolkit 2.10.0 or newer, your Crit Mayhem settings are part of
your Dyre's Toolkit profile, with every other Dyre's AddOn: the theme,
intensity, stay, every switch, your sound picks, the record pop's place and
size, and the records window's sort. On the Toolkit's settings page (Options
> AddOns > Dyre's AddOns), copy them from another character, go back to the
Defaults, or export and import them as a line of text. A copy applies at
once, with no reload. Your records stay with each character, and the
**I'm 18 or over** box stays account-wide: a mature theme copied onto an
account without the box shows Tame.

## Commands

- `/dcm`: your records. `/dcm options`: the settings (also under Options >
  AddOns > Dyre's AddOns > Crit Mayhem).
- `/dcm test`: a crit at your intensity (every third one as a new record),
  each one a different school. `/dcm test fire` (or frost, arcane, shadow,
  nature, holy, physical, heal) plays only that one.
- `/dcm unlock` and `/dcm lock`: move the record pop (with all of Dyre's
  AddOns' frames); `/dcm reset` puts the pop back.
- `/dcm resetrecords`, and `/dcm debug` for diagnostics. `/dcm probe` logs
  what the game tells AddOns about hits for 3 minutes (for WoW: Forever's
  launch day).
- `/critmayhem` works the same, in case another AddOn uses `/dcm`.

## Requirements

- **Dyre's Toolkit** 2.0 or later (required): one layout mode and settings
  home for all of Dyre's AddOns.
- **Dyre's Sounds** (recommended): the crit sounds. Without it the blood
  still shows.

The CurseForge app installs both with it.

## Compatibility

- **Classic Era and Anniversary**: everything, from the combat log.
- **WoW: Forever**: the combat log is closed to AddOns there, so DCM reads
  the game's combat text instead. Your crits are detected on your target,
  your focus, and nameplates: best solo, where every crit on an enemy is
  yours or your pet's. In a group, any crit on your target or an enemy
  nameplate plays as others' crits. Crits on you and crit heals on you work
  too. **No records on Forever**: it hides how much each hit does from
  AddOns, so DCM cannot tell a highest hit or crit. There the Records
  settings are greyed (their tooltip says why), and `/dcm` opens the
  settings; `/dcm records` shows the records window, which says so.

Verified in client: nothing yet (0.1.0 is in development).

Not yet verified: everything in TESTING.md's checklist.

## Support

Dyre's Crit Mayhem is free. If you enjoy it, you can support its development
on Ko-fi: https://ko-fi.com/dyre_janelle

## License

MIT License, Copyright (c) 2026 John Bedworth. The splatter textures and the
logo are original art under the same license. The sounds belong to Dyre's
Sounds and its licenses.
