# Changelog

## 0.1.0

### Features

- Two themes: Tame (the default), little pastel butterflies, stars, and
  sparkles that float away with light chimes, the stars turning, the
  butterflies fluttering, and the sparkles twinkling; and Brutal, impacts,
  crunches, a squelch, and original blood splatter that drips at High and
  Total Mayhem, some splats staying put while a trickle runs down from them.
  Brutal stays locked until you tick "I'm 18 or over" (for your whole
  account).
- A third theme, Spellburst, for casters and healers: bursts of light in
  your spell's school, glowing motes, and a ring of light for a new record;
  crit heals show too.
- A fourth theme, Fel, dark and demonic: smoke curling as it rises, falling
  embers, creeping cracks, and a dark shadow around the screen for a new
  record, in fel green, shadow, and hellfire. Like Brutal, it stays locked
  until you tick "I'm 18 or over".
- Intensity, from Off (the default) through Low, Medium, and High to Total
  Mayhem, for any theme: each step is more, bigger, and stays longer, from
  about 2.5 seconds at Low to 12 at Total Mayhem.
- "Stays on screen" tunes how long the effects stay, 25% to 300% of your
  intensity's time, and shows the seconds.
- A new record hits harder: the theme's big sound and one more, bigger effect.
- Sounds: each theme has 2-3 sounds for a crit, a new record, and an
  extra (Brutal's squelch, on about 3 crits in 10), picked at random and never the same twice in a row (Brutal: gore
  slices, chops, bashes, and wet splats; Tame: kisses, swishes, and
  shimmers). Choose your own for any of them in the Sounds section; "Reset
  sounds to theme" puts the theme's back. Text to Speech says "Crit!" or
  "New record!". Sounds the client cannot play (the game's sound kits on
  Classic Era and Anniversary) are skipped. Needs Dyre's Sounds 1.2.0.
- Which crits count: yours (on by default), your pet's, crits on you (their
  blood lands at the edges of the screen), and crit heals, shown as gentle
  rising light in each theme's own style (hearts on Tame, warm red and gold
  on Brutal, fel-green wisps on Fel).
- Personal records: each ability's highest hit and crit on this character,
  yours and your pet's, at every intensity, Off included. A new record always
  says so in your chat; it can also go to party, guild (at most one every 10
  seconds), and a pop on screen you can place with Dyre's Toolkit.
- `/dcm` opens your records in a dark, easy-to-read panel, sortable by
  ability, highest hit, or highest crit, with Options and Reset records (it
  asks first, never in combat).
- `/dcm test` plays a crit at your intensity. `/critmayhem` is the backup.

### Other changes

- Never changes your game settings (violence level, volume, sound): the sounds
  play on the Sound Effects channel.
- WoW: Forever closes the combat log to AddOns, so there DCM reads combat
  text: your crits on your target, focus, and nameplates (best solo; in a
  group only with "Guess my crits in a group"), crits and crit heals on you,
  and records kept solo as best guesses. Unconfirmed until Forever launches.
- `/dcm probe` logs what the game tells AddOns about hits for 3 minutes, for
  Forever's launch day.
