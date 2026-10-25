# Dyre's Crit Mayhem

Dial up the mayhem on your crits. **Dyre's Crit Mayhem** plays sounds and
splatters blood on your screen when you crit, as much as you choose, and keeps
your personal records: each ability's highest hit and highest crit.

It starts **Off**: every effect off until you turn it up. It never changes
your game settings (violence level, volume, or sound).

For World of Warcraft Classic Era and Anniversary. WoW: Forever support is
built but unconfirmed until Forever launches (see Compatibility).

## The mayhem

- **Theme**, near the top of the settings, under **I'm 18 or over**:
  - **Tame** (the default): little pastel butterflies, stars, and sparkles
    that float away, with light chimes: the stars turn, the butterflies
    flutter, and the sparkles twinkle. No blood.
  - **Brutal**: heavy impacts, crunches, and blood splatter, with a squelch
    from Medium and dripping blood from High. Some splats stay put while a
    trickle runs down from them, more often at higher intensities. Brutal
    is locked until you tick **I'm 18 or over** (once, for your whole
    account); untick it and those characters go back to Tame.
  - **Spellburst**, for casters and healers: bursts of light in your
    spell's school (fire orange, frost blue, arcane violet, shadow purple,
    nature green, holy gold, melee white), glowing motes that rise from
    Medium, and a ring of light from High and for a new record. Crit heals
    show too, rising in holy or nature light.
  - **Fel** (18+, like Brutal), dark and demonic: smoke that curls
    as it rises, embers falling from Medium, cracks creeping out from where
    it landed, and a dark shadow around the screen for a new record. Fel
    green, shadow, and hellfire: shadow crits are shadow, fire crits
    hellfire or fel. No sparkles.
  - More themes are planned.
- **Intensity**: Off (the default), Low, Medium, High, and Total Mayhem, for any
  theme. Each step is more, bigger, and stays longer: about 2.5 seconds at
  Low up to 12 at Total Mayhem.
- **Stays on screen**, right under it: 25% to 300% of your intensity's time,
  to tune how long without changing the intensity. It shows the seconds.
- **Which crits**: yours (on by default), your pet's, crits on you (their
  blood lands at the edges of the screen), and crit heals: a sound and
  gentle rising light in your theme's style (hearts on Tame, warm red and
  gold on Brutal, never blood, fel-green wisps on Fel).
- Effects land under your action bars and unit frames, and your own crits
  never cover the middle of the screen. **On-screen effects** has a switch.
- **Sounds**: each theme has 2-3 sounds for a crit, a new record, and an
  extra (Brutal's squelch), one picked at random each time (Brutal's gore
  impacts and wet splats; Tame's kisses, swishes, and shimmers). Tick "my
  own sound" on a row to choose your own instead, whatever the theme;
  **Reset sounds to theme** puts the theme's back. They play on the Sound
  Effects channel and come from Dyre's Sounds (1.2.0 or later).

## Personal records

- Every ability's highest hit and highest crit on this character, yours and
  your pet's (and heals, with **Heals too**), at every intensity, Off included.
- A new record always says so in your chat, seen only by you. You can also
  announce it in **party**, in **guild** (at most one every 10 seconds), and
  **on screen** with a pop you can place.
- A new crit record hits harder: a bigger sound and more blood.
- `/dcm` opens your records: click a heading to sort by ability, highest
  hit, or highest crit. **Reset records** asks first, and only out of combat.

## Commands

- `/dcm`: your records. `/dcm options`: the settings (also under Options >
  AddOns > Dyre's AddOns > Crit Mayhem).
- `/dcm test`: a crit at your intensity (every third one as a new record).
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
  yours or your pet's. In a group, "Guess my crits in a group" counts a crit
  on your target just after your own cast (about one in three will be
  someone else's). Records are kept solo, as best guesses: each hit is
  matched to your last cast. Crits on you and crit heals on you work too.
  Not yet confirmed in the client: `/dcm probe` checks it.

Verified in client: nothing yet (0.1.0 is in development).

Not yet verified: everything in TESTING.md's checklist.

## Support

Dyre's Crit Mayhem is free. If you enjoy it, you can support its development
on Ko-fi: https://ko-fi.com/dyre_janelle

## License

MIT License, Copyright (c) 2026 John Bedworth. The splatter textures and the
logo are original art under the same license. The sounds belong to Dyre's
Sounds and its licenses.
