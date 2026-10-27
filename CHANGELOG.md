# Changelog

## 0.2.0

### Features

- Naturalist (18+), a new theme for Druids and nature, mature and a touch gory:
  melee crits mix claw scratches (two to four), bites, and splatter, at
  any angle, in blood that sometimes drips straight down (tick "Claws
  only in Cat or Bear form", under the theme, to keep them to Cat and
  Bear form and a Hunter's pet, with Brutal's splatter otherwise);
  Wrath-like crits a murky green burst with
  insects and torn leaves bursting out; arcane silver fireworks that fade;
  fire charred, burning leaves and embers on a scorch; frost frozen leaves
  with ice shards on frozen blood; holy a harsh searing flare; shadow
  rotting black leaves on dark ichor. Crit heals sprout vines and green and
  gold smoke, never flowers; a new record darkens the screen's edges in
  deep green. Growls, a tiger, angry cats, and bear and lion roars.
- Brutal in Cat or Bear form: your melee crits (and a Hunter's pet's)
  are claw scratches, bites, and splatter in Brutal's red, dripping
  straight down; out of form and for every other class, its blood
  splatter as before.
- Effects by damage school: every theme keeps its own look, and a crit's
  school adds a color and a small touch. Brutal is always wounds: charred
  blood with embers for fire, frozen blood with an ice shard for frost,
  blood-soaked leaves stuck on the wound for nature, slowly smearing
  down, black ichor, blood with a violet crackle, seared
  wounds with a light flare. Fel is always its smoke and cracks, with
  hellfire flame licks, rime, a leaf that catches fire and falls to ash,
  violet, or pale light. Spellburst is always its bursts, colored by
  school, with a flame or ice shard inside, and a puff of leaves blowing
  up out of its green burst. Melee crits are blood in every theme but Tame (on Spellburst
  only with the 18+ box, else a white flash). Tame has cartoon looks: a
  pow, little flames, snowflakes, leaves, dusky puffs, twinkly stars, gold
  sparkles, never blood. A spell of two schools shows one, magic first:
  fire, frost, shadow, arcane, nature, holy.
- Random Effects (Tame, off by default): tick it for Tame's playful mix of
  stars, butterflies, and sparkles on every crit, whatever its school.
- Leaves for nature: a Michigan maple, an oak, and a birch leaf. Tame's
  nature crits are a tumble of them in autumn colors, maple most, with a
  puff of leaves blowing out and drifting down; Spellburst's blow out and
  up; Brutal's are soaked in blood and stick; Fel's burn to ash.
- Tame has rainbows: a little cartoon rainbow joins its stars, butterflies,
  and sparkles (and its holy crits), in its own colors.
- Others' crits: anyone's crit on your target and on nearby enemies (with
  a nameplate shown) now plays the effects and sounds too, in a group and
  solo. Choose Off, My target, or Nearby enemies (the default). Others'
  crits are trimmed so a raid stays readable (one effect each, a few per
  half second); yours always play. Your records stay yours alone.

### Other changes

- Fel's own sounds (Dyre's Fel Sounds, Dyre's Sounds 1.4.0): a wet smash,
  a mud splat, or a heartbeat on each crit, a deep demon growl for a new
  record, and now and then a heartbeat from Medium. With an older Dyre's
  Sounds, Fel keeps its earlier sounds. Needs Dyre's Sounds 1.4.0 for them.
- "Guess my crits in a group" (WoW: Forever) is gone: in a group, a crit on
  your target or an enemy nameplate plays as others' crits, and no records
  are kept from it.

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
