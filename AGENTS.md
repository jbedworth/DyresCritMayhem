# Agent Guidelines

## Project purpose and scope

Dyre's Crit Mayhem (DCM, `/dcm`) is a World of Warcraft AddOn for Classic Era,
Anniversary, and WoW: Forever: opt-in "dial up the mayhem" on crits, with
sounds and blood on the screen in themes, plus a personal record tracker
(author's design, 2026-10-23, after looking at three crit AddOns on Era:
CritsBloodyCrits, LightsaberCrit, and RainingBlood). We learned from their
behavior only; no code, art, or sound is copied from them. Keep this feature
set; do not add speculative features without agreement.

Naming (author-approved): title "Dyre's Crit Mayhem"; folder, TOC,
repository, saved variables, and globals `DyresCritMayhem`
(`DyresCritMayhemDB` per character, `DyresCritMayhemAccountDB` account-wide);
commands `/dcm` and `/critmayhem` (backup); chat prefix `DCM:`.

### The design (author)

- **Theme and intensity** (author: "make 'Tame' a theme, and leave the
  slider for 'Intensity'. Require 18+ to turn on the 'Brutal' theme"). The
  settings page starts with the account's "I'm 18 or over" box (author: "Put
  the 'I'm 18+' check first"), then the Theme dropdown, the Intensity slider,
  and "Stays on screen". Theme and intensity are per character.
- **Themes** (Themes.lua) are data, each flagged `mature` or not:
  - **Tame**, the default: butterflies, stars, and sparkles in soft
    pastels (one tint picked per effect), smaller (theme size 0.6), only
    tilted and floating up as they fade. Sounds: crit {kiss, swishsmack,
    war3magicshimmer}, new record {kisses, instrumentschimeascending}.
  - **Brutal**, mature: heavy flesh impacts, bone crunches, blood splatter
    in deep red, a squelch from Medium, and one dripping splatter per crit
    from High (`dripsFrom`, `extraFrom`). Sounds (Dyre's Gore): crit
    {goreslice, gorechop, gorebash}, new record {gorebloody, goresplat},
    extra (the squelch) {wetsplat, wetpunch}. Some splats stay put while a
    run grows down from under them (`run`, `runChance`: 25%, 33%, 45%, 60%
    from Low up). A beast's physical crit (author: "Add the form check to
    the Brutal theme and use claw/bite/splat there too, because, why
    not"; `DCM.FeralCrit`, below) draws `brutal.beast`, Naturalist's claw,
    bite, and splatter mix in Brutal's red and run chances; always on,
    no setting.
  - **Variants of Brutal** (John, 2026-11-17: "pivot the themes to be
    variants of Brutal that stylize the baseline effects, instead of being a
    completely different set ... Brutal is neutral, keeps the default
    effects looking default. But picking a theme puts me 'in
    character'"; "effects on me retain the brutal effect. What I'm
    stylizing is the damage I'm doing"; Spellburst "18+ only"; Naturalist
    "Yes, a variant"; the crit splatter "Baseline, styled"). Themes.lua
    `BrutalBase` fills a variant's splats, colors, size, drips, runs from
    Brutal and sets `variant`; `Variant(theme, spec)` builds its school
    styles: Brutal's look for each school (`brutal.styles[kind]`, the beast
    mix in Cat or Bear form) with the variant's splat colors
    (`spec.colors[kind]`), its accent recolored (`spec.accents[kind]`,
    overlay and after too), its own touch (`extraAccent`, from
    `spec.extra[kind]` or `.all`, drawn by Splatter after the accent), its
    run, and its hit styles (`spec.hits[kind]` over `DCM.HIT_STYLES`, as
    `theme.hitStyles`; `emphasis` multiplies the pieces, `flashScale` the
    crit flash). `DCM.Look(theme, kind)` (Effects.lua): a variant draws
    for "mine", "pet", and "self" (/dcm test); "taken", "others", and
    bystanders draw Brutal. Sounds and the heal style stay the theme's
    for every crit. Each variant is mature (18+).
    - **Spellburst** (author: "something for mages, warlocks and priests"):
      Brutal's looks, a glow (Burst1-2, ADD, onTop) in the school's color
      on each crit (physical white), a Ring1 closing a new record's set;
      spell hits `emphasis` 1.4 and `flashScale` 1.3. Heals: Burst1 and
      Mote1 rising, holy gold and nature green. Sounds unchanged (Dyre's
      Sounds' own: crit {magical, fadingslow, war2magicchimes,
      instrumentsbelltrill}, new record {blowswoosh, war2choir,
      instrumentschimeascending}, extra {teleportvanish, disappearingswoosh,
      impactsbubblesmash} from Medium). A character saved on it without the
      18+ box logs in on Tame.
    - **Fel** (author: "Fel is gives the effects from Brutal an evil,
      demonic tinge, mixing in fel green and purple shades"; "If I choose
      Fel on my Paladin, Holy is no longer a golden glow/sparkle. It's now a
      more evil black/purple/fel-green effect"): every school's splats in
      dark blood, purple-black, and fel green; accents in fel green and
      violet; Crack1 runs spreading from the wound (`runGrow = "center"`);
      a wisp of dark smoke on each crit; Vignette1 for a new record. Hits:
      every school recolored, holy turned to purple, green, and black smoke
      (motion smoke, Smoke1 flash). Heals: fel-green wisps. Sounds: Dyre's
      Fel Sounds (Dyre's Sounds 1.4.0): crit {felwetsmash, felmudsplat,
      felheartbeat}, new record {feldemongrowl}, extra {felheartbeat} from
      Medium (`Sound` skips an extra equal to the crit's own sound);
      `sounds.fallback` for 1.3.0 and older.
    - **Naturalist** (author: "a Druid/nature theme ... more mature and a
      touch gory"): physical its own mix of Claw1-3, Bite1, Splat1, Splat3
      in blood red, turned and mirrored at random, runs straight down
      (StartRun), 30/40/50/65% (author: "3-4 claw scratches that randomly
      drip blood", "make sure it mixes up the base effect (bite, scratches,
      splatter)"); with "Claws only in Cat or Bear form" (`clawsInForm`,
      default off, a child row of the Theme live where `formClaws`) only a
      beast's crit (`DCM.FeralCrit`: yours in Cat 768, Bear 5487, Dire
      Bear 9634 from `DCM.feralForm`, cached on UPDATE_SHAPESHIFT_FORM; a
      Hunter's pet, `DCM.beastPet`), Brutal's splatter otherwise. Other
      schools earthy (moss, bark, amber, silver); nature crits throw a puff
      of leaves (BlowingLeaves, down). Hits: nature a flurry of Maple1,
      Oak1, Birch1, and Insect1 (count 1.5); arcane Firework1 and sparkles
      in silver; the rest recolored. Heals: Vine1 and Smoke1-2 (ADD), green
      and gold. A new record: Vignette2 tinted `vignetteColor` deep green.
      Sounds: crit {angrycat, tigerroar, goreslice}, new record {bearroar,
      monsterbear, lionroar}, extra {wetsplat} from Medium.
  - Every new character starts on Tame, whatever its class (author: "start
    everyone on tame, let people pick"); Spellburst is a dropdown choice.
  - Tame's textures move while they hold (`animations`, author: "rotate
    stars or fluttering wings"): stars spin (a full turn in 6 s, either
    way), butterflies flutter (a 0.14 s pinch on X, bouncing), sparkles
    twinkle (a 0.35 s swell to 130%, bouncing). Twinkle is a scale, not an
    alpha pulse, so it never fights the fade.
  - A theme holds: textures (`splats`, `drips`), `colors` for the grey
    textures, `size`, `motion`, and Dyre's Sounds pools (`sounds.crit`,
    `big`, `extra`, `extraFrom`). Planned (Laser sword can use Dyre's Blades): Cartoon smack (BAM/POW), Laser sword, Arcane, Retro
    arcade, Kung fu. Never "Lightsaber" or any film's audio or marks.
- **None** (author, 2026-11-17: "Move 'None' (zero) from the slider (so
  the slider goes from Low to Total Mayhem) to the Theme selector. Have it
  be the first item, above Tame. Make Tame the default."): a theme key
  `none` (`DCM.NONE_THEME`, Themes.lua, `none = true`, `sounds = {}`),
  outside `DCM.Themes()` (the effect themes; style matrix, sound checks),
  listed first in the Theme dropdown. It plays no effect, sound, or hit effect
  (`PlayCrit`, `/dcm test` says so); records count; the stay slider shows
  no seconds; not mature, so it puts the violence level back. A saved
  intensity `off` (0.2.1 and older) becomes None at Low; so does an old
  test build's level `off`.
- **Intensity** (Core.lua `INTENSITIES`): Low (the default) → Medium →
  High → Total Mayhem, for any theme: more, bigger, longer. At
  100%: Low 2.5 s, Medium 4 s, High 7 s, Total Mayhem 12 s (hold plus fade; the
  earlier Fun, Spicy, Gory, and Mature numbers). Records and their chat line
  work in every theme, None too. Total Mayhem stays 12 s, not "until combat ends"
  (the author has not chosen that).
- **Stays on screen** (author), right under the intensity: 25-300% in steps
  of 25, default 100% with the toolkit's gold default mark
  (`AddDefaultTick`); it scales the intensity's hold and fade together. Its
  value reads "100% (7 s)" for the current intensity, and its tooltip lists
  every intensity's seconds at 100%.
- **The 18+ lock is on the theme**: Brutal, Spellburst, Fel, and Naturalist need the account-wide box.
  Choosing it without the box says so and keeps the theme; unticking the
  box puts a character on Brutal back on Tame, with a line; a character
  saved on Brutal logs in on Tame while the box is clear. The dropdown reads
  "Brutal (18+)" while locked.
- **Migration** from earlier 0.1.0 test builds (Core.lua `OLD_LEVELS`): old
  level tame → Tame at Low; fun, spicy, gory, mature → Brutal at Low,
  Medium, High, Total Mayhem (Tame without the 18+ box); off → None at Low. The old `level`
  key goes; a save that already has `intensity` keeps it.
- **Records** (Records.lua, "definitely include"): per character, each
  ability's highest hit and highest crit, yours and your pet's (labeled
  "(pet)"), and heals (labeled "(heal)") with the heals option. Abilities go
  by name (Classic's combat log has no spell IDs; every rank is one). A new
  record always says so in your own chat; options add party and guild
  (together at most one every 10 seconds, only in a group or guild) and an
  on-screen pop, a Dyre's Toolkit widget. An ability's first hit and first
  crit set the record quietly (DCM's call: otherwise every first swing would
  be "a new record"). A new crit record makes that crit "big": the big sound
  and one more, bigger splatter.
- `/dcm` opens the records window (sortable by ability, highest hit, highest
  crit; the sort is saved), with Options and Reset records. Reset asks first
  with a StaticPopup and never in combat. The settings open from the
  toolkit's "Dyre's AddOns" page, the window's button, or `/dcm options`.
- Commands: `/dcm` (the settings while amounts are hidden), `records`, `options`, `test`, `unlock`, `lock`,
  `reset` (the pop's place), `resetrecords`, `debug` (its second line counts
  solo hits on enemies since login and why each made no record:
  DCM.RecordCountsText in Detect.lua) and `probe` (both run
  while unavailable).

### Effects by damage school (0.2.0)

- Author: "Physical vs. magic, and each school of magic (holy, fire,
  nature, frost, shadow, arcane (no combo, pick one for each) has it's own
  effect for each theme, with some shared if needed." The school decides
  what is drawn, the theme how; sounds stay the theme's; heals keep the
  heal style.
- `DCM.SchoolKind(mask)` (Themes.lua `KIND_ORDER`): any magic before
  physical, in the order fire, frost, shadow, arcane, nature, holy, then
  physical; 0, unknown bits, or a secret mask: nil, the theme's own look.
  Spellburst's school tints use the same order.
- `DCM.CritStyle(theme, school)`: `theme.styles[kind]`, a style table that
  reads what it does not set from a base theme (`Restyle`, a metatable),
  or a function returning one; none: the theme itself. Styles add
  `textureColors` (per-texture tints: Brutal's char scorch, rime). The
  matrix:
  - Tame: physical a cartoon pow and stars; fire little flames and
    sparkles; frost snowflakes; nature leaves (maple three times as often
    as oak or birch, autumn pastels: soft red, orange, gold, green,
    tumbling as they rise); shadow small dusky puffs;
    arcane twinkly violet stars; holy gold sparkles. Never gore (tested).
    The per-character "Random Effects" box (author: "make it a setting I can
    toggle if the Tame theme is selected"; `randomEffects`, off by default
    so the school looks are tried first) dials it back: ticked, every
    school draws Tame's own stars, butterflies, and sparkles. A theme offers
    it with `randomEffects = true` (Tame only). The row sits right under the
    Theme dropdown as its child (`SetParentInitializer`), so Blizzard greys
    it at once when another theme is chosen.
  - Tame's rainbow (author: "I intended it as a texture to add to Tame to
    vary what shows up"): Rainbow1, six pastel bands with a cloud at each
    end, is in Tame's own mix (one of five, so Random Effects shows it too)
    and its holy look. It is the one pre-colored texture: a theme's
    `untinted` set draws a texture at vertex color white. It floats up with
    Tame's motion and has no loop.
  - After play testing (author: "with this change, there is not really a
    distinction between 'Brutal' 'Fel', etc., only 'Brutal' and 'Tame'
    themes", then "Go with 1, keeping the physical-gore exception in all
    non-Tame themes"): every theme but Tame keeps its own language for
    every magic school; the school adds a tint and at most one small
    accent (`accent`, drawn by Effects.lua's ShowAccent above the set:
    its own textures, colors, blend, size, motion, and count, plus
    optional onTop, spread and drift, runs, loop, overlay, and after; see
    Themes.lua).
  - Brutal: always its blood, drips, and runs. Fire charred blood with a
    few rising embers; frost frozen blood with an ice shard; nature red
    blood with one or two blood-soaked leaves (dark red-brown, a little
    green) stuck on its first splat, a run smearing down from under them
    (author: "the leaves are wet with blood and splatter on the screen and
    stick, maybe slowly smear down"); shadow black ichor
    with a wisp of smoke; arcane its blood with a violet crackle; holy
    seared wounds with a light flare.
  - Spellburst, Fel, Naturalist: Brutal's looks above, restyled (see
    Variants of Brutal). The old per-theme languages (Spellburst's bursts,
    Fel's smoke and burning leaves, Naturalist's fireworks and insect
    bursts) are gone.
- New shared textures (scripts/build_splatters.py): Flame1 (soft, drawn as
  added light), Shard1, Snowflake1, Pow1, and the leaves Maple1, Oak1, and
  Birch1 (white with a rim). Leaf1, a plain lens leaf, was retired for them
  (author: "I'm from MI, so Maple might be better"; birch is the plain oval,
  serrated).
  scripts/style_matrix.lua prints the matrix from Themes.lua, and
  scripts/build_matrix_preview.py renders artwork/style-matrix-preview.png
  from it (`--lua` a Lua 5.1 binary).
- Possible school sounds, not built (sounds stay per theme): Dyre's Blades'
  Sword cut for physical on Spellburst, Dyre's Picks' Teleport warp vanish
  for arcane; dedicated fire and frost sounds would need new packs.

### Effects (Effects.lua)

- Splatters are textures on one full-screen frame in the BACKGROUND strata
  (under the action bars and unit frames), never taking the mouse. Each pops
  in, holds, and fades with an AnimationGroup (the engine runs it; no
  OnUpdate), then returns to a pool of at most 32; when all are out, the
  oldest goes.
- Your own crits land outside the middle of the screen; crits on you land
  in a band at its edges. A crit within 0.15 s of the last adds one
  effect (area spells), not a full set. Brutal's drip slides down as it
  fades; Tame's effects rise.
- The "On-screen effects" switch covers every theme's effects.
- Hit effects (author: "Build the nameplate blood spray too", then
  2026-11-17: "The hit effects should trigger every time a hit lands and
  does damage (even DoTs, ideally). It should look like it's happening to
  the target (mob, player avatar), and when it crits, it should double",
  "physical: bloodspray/splatter, cold/frost: snow/ice flurries; fire:
  burning flames raining down; arcane: spark showers; shadow/fel: black or
  greenish smoke", "heals should be little green +'s", "Tame gets none of
  these on target effects for now"). `DCM.PlayHit` (Effects.lua) for every
  damage or heal that landed (a readable amount above 0, or a secret one):
  by you or your pet (`mine`, `pet` switches), others on `OthersOn`
  targets (half, at most `OTHERS_HITS` per 0.5 s), and anything on you
  (`taken`). Settings: `spray` "Hit effects on enemies" and `hitsOnYou`
  "Hit effects on you", per character, default on. Styles are data in
  Themes.lua `DCM.HIT_STYLES` (physical, impact, frost, fire, arcane,
  shadow, nature, holy (as arcane, gold; John: "drop the circle-halo"), heal: textures, colors, blend, size, motion);
  motions in Effects.lua `HIT_MOTIONS` (spray, burst, flurry, blaze,
  smoke, rise). A variant's `hitStyles` restyle your own hits (see
  Variants of Brutal); `noHits` (Tame) and None show none. Physical
  blood needs the 18+ box, else `impact`; an unknown or secret school is
  physical. Nature `SPELL_PERIODIC_DAMAGE` shows nothing (the game's own
  poison cloud); Forever's `UNIT_COMBAT` cannot tell ticks apart. Pieces:
  Low 2, Medium 3, High 5, Total Mayhem 7, times a style's `count`
  (frost and nature 2.5: fine motes, with small flakes and shards for
  frost and small sparks for nature; John: "denser ... more subtle", "Do
  the same for nature"); a crit (John, after play
  testing: "crits are not visibly discernable from normal hits") doubles
  them, makes them 60% bigger, sends them 50% farther, and adds the
  style's `flash`, one big piece at the impact that swells 1.5x and fades
  in 0.45 s (a blood burst for physical; a glow or smoke puff in
  the school's colors otherwise); a new record +3; one set per target per 0.1 s unless
  it crits. Anchor: an enemy's nameplate (`C_NamePlate.GetNamePlateForUnit`;
  secret, missing, or `IsForbidden` skip it), 76 px under its center (John:
  "about 2x further down, so it looks like it's coming from the mob"); a
  heal on your target, its plate when one shows; you: your own nameplate
  if the client shows one, else UIParent's center, 5% of its height
  below (where the camera keeps your character). Own frame `hitLayer`
  (BACKGROUND), pool of 120. Distance (John: "within 1-3 meters, use the
  current size, if the mob is 30m away, it should be much smaller"):
  `DCM.UnitDistance` probes nearest first, CheckInteractDistance 3 and 4
  (about 10 and 28 yd) and `C_Item.IsItemInRange` on LibRangeCheck-3.0's
  Era items (5, 20, 30, 40 yd; requested at load, skipped while not
  loaded); the client blocks these in combat for a unit you cannot attack
  (found in client on Forever: ADDON_ACTION_BLOCKED), so in combat
  `UnitDistance` checks `UnitCanAttack` first and skips (full size).
  `DCM.DistanceScale` (tuned in play, John: "a bit smaller" at 30+,
  "slightly bigger" up close): 1.15 up to 5 yd, 0.95 at 10, 0.6 at 20,
  0.3 at 30, 0.24 at 40, 0.22 beyond, in a line between; no answer, 1. It scales an
  enemy's pieces, their spread and travel, the flash, and the drop under
  the plate; hits on you stay full size. Unconfirmed in client: the items
  answering, and on Forever. `NAME_PLATE_UNIT_REMOVED` releases a plate's
  effects (`DCM.ReleaseSprays`). The screen splatter and the sounds stay
  crit-only. `/dcm test [type]` (John: "dcm test <type> ... when blank,
  have it continue to rotate"; the one command with a second word:
  fire, frost, arcane, shadow, nature, holy, physical, heal) also plays its school's hit on your target's
  plate, else on you (`DCM.TestHit`). No `PlayerModel` spell visuals:
  unverified display IDs, and a model per hit costs more. Unconfirmed in
  client: the spot under the plate, the spot for your character, and
  Forever's plates.
- Moving effects: each loop is its own AnimationGroup on the splat, made
  once per splat and kind and stopped when the splat finishes, is reused,
  or is cleared; a run is one more pooled texture per splat, under it in the
  ARTWORK sublevel -1, anchored TOP to the splat's CENTER, growing with a
  Scale from its TOP while the splat holds, then fading with it. At most 12
  splats move at once (loops and runs together); past that they show still.
  Unconfirmed in client: the flutter's and twinkle's Scale combining with
  the pop's Scale in the main group.
- Sounds (author: "Each theme should set defaults - there should be 2-3
  sounds that play randomly on each crit"): `DCM.PickSound(event)` for crit,
  big (a new record), and extra (Brutal's squelch with the effects, from
  Medium, and then on about 30% of those crits: author, "only play it, say
  30% of the time"; `DCM.EXTRA_CHANCE`, or a theme's `sounds.extraChance`,
  rolled with `DCM.random()`). The player's own pick for the event wins; else one of the
  theme's pool at random, never the same twice in a row. Keys the installed
  Dyre's Sounds lacks, or says this client cannot play
  (`DyresSounds.Playable`, 1.2.0, guarded for older ones: Classic Era and
  Anniversary play none of its kit-ID or file-ID sounds, found in client),
  are skipped; with none left, the theme's other events' keys, else
  Interface: Talent ready (a kit by name, which every client plays). A
  Text to Speech sound says the event's words (`DCM.SOUND_SPEECH`: "Crit!",
  "New record!", "Boom!"), also in the picker's preview; Dyre's Sounds
  plays a voice only with words (found in client). The hook for crit-size bands
  (author: "high/med/low crit ranges, random for now") is the theme pool
  lookup (`Pool` in Themes.lua). At most one set per 0.1 s.
- The Sounds section: the Sounds switch, then one row per event (crit, new
  record, extra): a box "…: my own sound" with the sound beside it
  (Blizzard's checkbox-and-dropdown row with Dyre's Sounds'
  `SetupCheckboxMenu`, as Dyre's Buff Reminders' chimes). Clear means the
  theme's pool at random (the shared sound menu has no "Theme default"
  entry, so the box carries it). A pick is saved per character in
  `soundPicks` and stays across theme changes; choosing one plays it once;
  "Reset sounds to theme" clears every box (the picks are remembered).
  While a box is clear its row shows the theme's first sound (greyed);
  theme changes, the box, and the reset redraw the rows (`RefreshOptions`,
  after the setter returns). Blizzard's checkbox-and-dropdown row redraws
  only its enabled state on a value notify, so each shown row's dropdown
  menu is built again (`GenerateMenu`, on the frame captured in its
  InitFrame while it still shows that row; found in client: rows kept the
  old theme's sounds).
- Section headers: Blizzard's header shows its own name as a tooltip; an
  OnEnter hook hides it for our headers only (pooled frames), since ours
  have nothing to add. Played through Dyre's Sounds on
  the SFX channel.
- Heal crits (author: every theme gets a heal-crit visual): with "Heals
  too", each theme draws its heal style (`heal` in the theme: splats,
  colors, blend, animations, size), always rising and with no drips, runs,
  rings, or vignette: Tame hearts (beating), a sparkle, or a butterfly in
  pink and gold; Brutal warm red and gold droplets of light (embers and
  motes, added light; never blood); Fel glowing fel-green wisps.
  Spellburst Burst1 and Mote1 light, holy gold and nature green; Naturalist vines.
- **Never change a CVar but the violence level** (volume and sound mute stay
  out). The first brief said no CVars at all, since the AddOns we studied
  changed them; John lifted it for gore (2026-11-17, "That is a stupid rule",
  then "Build it anyway" after `violenceLevel` read 5 across a logout):
  `DCM.ApplyGore` (Core.lua) sets `violenceLevel` from the intensity's
  `violence` (Low 3, Medium 4, High and Total Mayhem 5) for a mature theme
  with the 18+ box, first keeping the player's own level account-wide
  (`DyresCritMayhemAccountDB.violenceOwn`); None, a cute theme, or the box
  cleared puts it back. Runs on login and on the theme, intensity, and 18+
  setters; in combat it waits for `PLAYER_REGEN_ENABLED`; nothing without
  the CVar. Unconfirmed in client: whether the level shows more blood
  (John saw no change on a plant mob at 5). tests/run.lua fails on any other
  `SetCVar` and on an `"OnUpdate"` or `pcall` in runtime code.

### Crit detection (Detect.lua)

- Gated on APIs, never on the client version. The combat log is used when
  `C_CombatLog.IsCombatLogRestricted` is absent or false and
  `C_CombatLog.GetCurrentEventInfo` (or the deprecated
  `CombatLogGetCurrentEventInfo`, only loaded with `loadDeprecationFallbacks`
  on Era/Anniversary) exists.
- Fields after the 11 common ones: SWING_DAMAGE amount 12, critical 18;
  RANGE_/SPELL_/SPELL_PERIODIC_DAMAGE name 13, amount 15, critical 21;
  SPELL_/SPELL_PERIODIC_HEAL name 13, amount 15, critical 18. Source is you
  (`UnitGUID("player")`) or your pet (`UnitGUID("pet")`, re-read on
  `UNIT_PET`); crits on you are damage with dest you.
- Others' crits (0.2.0; author: "The mob I'm targeting is getting critted,
  blood should spatter no matter who caused it", then "maybe it should be
  on for all nameplates visible"): the "Others' crits" dropdown
  (`othersScope`: off, target, nearby; default nearby) plays the effects
  and sounds (kind "others") for anyone's damage crit on your target
  (target, nearby) or on an enemy with a nameplate shown (nearby). On the
  combat log: dest is `UnitGUID("target")` (re-read on
  `PLAYER_TARGET_CHANGED`) or a GUID from `NAME_PLATE_UNIT_ADDED`/`REMOVED`
  where `UnitCanAttack("player", unit)`; the source is not you or your pet
  (those stay "mine"/"pet" with their switches). Never focus, never
  others' heal crits, never a record or a new-record effect: records stay
  yours, exact on the combat log, solo guesses on Forever. A test build's
  `others` switch (false → off) and 0.1.0's `groupGuess` are repaired away.
- Others' crits are trimmed first (Effects.lua): at most `OTHERS_BURSTS`
  per `OTHERS_WINDOW` (0.5 s): Low 2, Medium 3, High 4, Total Mayhem 6;
  each one still effect (no drips, runs, rings, or loops); their sound only
  when no sound played in SOUND_GAP (0.1 s), on its own gap, never holding
  up yours; and never into the last `OWN_RESERVE` (8) of the 32 pool slots.
  Your crits and crits on you keep their own burst gap, sound gap, and full
  sets.
- WoW: Forever: never register `COMBAT_LOG_EVENT_UNFILTERED` there (the
  client blocks it and `IsCombatLogRestricted()` is true; found in client by
  Warlock Tools Forever). Instead (author: "we absolutely MUST make this
  work in Forever"; checked against the pinned source 943764493e):
  - `UNIT_COMBAT` (no secret markings), registered for every unit: "WOUND"
    with "CRITICAL" on "target", "focus", or "nameplateN" is a crit on an
    enemy, only when `UnitCanAttack` says so (John, 2026-11-17: "enemies
    only"). A wound on a unit you cannot attack is a bystander's (John:
    a stranger's "bloodsplatter as if they were an enemy mob, and, I liked
    it"): its hit effect only (`PlayHit` kind "others", `bystander`), by
    `othersScope` (your friendly target from My target, any other shown
    nameplate from Nearby enemies), and a crit as others' crits (John:
    "put the crit splatter from other's crits back"); never a record or a
    count.
    On the combat log the same: `DCM.BystanderOn` (Detect.lua tracks
    non-enemy nameplates apart, `bystanders`), and `OthersOn` takes your
    target only when it is an enemy. A bystander's distance cannot be read
    in combat: scale 0.6; "WOUND" with "CRITICAL" or "CRUSHING" on "player" one on you;
    "HEAL" with "CRITICAL" on "player" a crit heal on you (solo only). The
    same flag, amount, and school within 0.05 s count once (the target and
    its nameplate both fire).
  - Solo: every crit on an enemy is yours or your pet's. In a group, whose
    crit it was cannot be told: a crit on your target (My target, Nearby
    enemies) or an enemy `nameplateN` (Nearby enemies) plays as others'
    crits; focus plays nothing, and nothing makes a record. (0.1.0's "Guess my crits in a group" is gone; its saved
    key `groupGuess` is dropped on load.)
  - Records, solo: matched to the last harmful cast (`UNIT_SPELLCAST_SUCCEEDED`
    for player and pet, `C_Spell.IsSpellHarmful`, `GetSpellName`): a physical
    hit within 0.4 s of a cast is that ability; another physical hit is
    Melee, or unknown with a pet out; a spell-school hit is the latest cast
    within 1.5 s (projectiles); else no record. Damage over time lands as the
    last cast: best guesses, and the window says so.
  - **Confirmed in client (build 70938, 2026-11-16, /dcm probe on Danger
    Klose and /dcm debug on Dyra Darkwing): every `UNIT_COMBAT` amount on an
    enemy is secret** (996 of 996 hits). So no records on Forever:
    `DCM.amountsReadable` (the latest enemy hit's amount, readable or
    secret) gates `RecordsAvailable`/`RecordsGuessed`, and
    `DCM.AmountsHidden()` gives the window its "No records on this client"
    text (John: "Hide on Forever"). The matching code stays, so a client
    that shows amounts keeps records again. Effects are unchanged.
  - While `DCM.AmountsHidden()` at login (John, 2026-11-17: "On Forever,
    we should disable the show highest crit stuff, since we can't do it"):
    the Records rows (Show new records on screen, Announce in party and
    guild, the toolkit's Record pop size and Reset size, Show records,
    Reset records) are greyed with the tooltip `DCM.AMOUNTS_BLOCKED`
    (John's words: "Presently, WoW Forever blocks addons ability to read
    damage amounts you do. If they fix this, we can enable these features
    again."). Options.lua `Block`: checkboxes and sliders through
    `AddModifyPredicate`; button rows ignore it
    (`SettingsButtonControlMixin`), so the button is disabled after each
    `InitFrame` and its click emptied; the toolkit's rows are caught by
    wrapping `layout.AddInitializer` (Blizzard's `Settings.CreateSlider`
    adds through the category's layout). Test crit stays. Plain `/dcm`
    opens the settings instead of the empty window (`DCM.OpenMain`; John:
    "make typing '/dcm' bypass the highest crit screen"); `/dcm records`
    still opens it. Gated on hidden amounts, not on the client.
  - `C_DamageMeter` (SecretWhenInCombat) has per-spell totals per fight but
    no largest hit: confirmed in client (Danger Klose: `maxAmount=41` is
    Attack's total, the largest spell total; `detailAmount=0`). It cannot
    give records.
  - `/dcm probe` (Probe.lua, 3 minutes): every `UNIT_COMBAT`, cast, and the
    meter after combat, each value's secrecy, and DCM's guess; 40 lines to
    chat, up to 600 to `DyresCritMayhemDB.probe`.
  **Unconfirmed**: Forever's servers are closed until launch (Nov 4).
- Every value that could be secret is checked with `issecretvalue` before it
  is compared or stored; a secret amount still plays the effect but makes no
  record.

### Sounds (Dyre's Sounds)

- DCM ships no sounds. Every theme sound is a Dyre's Sounds key
  (`DyresSounds.RequireContract(1)`, `Play(key, nil, "SFX")`), listed as
  `## OptionalDeps: DyresSounds` and a CurseForge required dependency. Without
  the library the blood still shows and DCM says once to install it.
- The themes' keys are the author's licensed Envato sounds in Dyre's Sounds
  1.2.0 (Dyre's Gore, Dyre's Smacks; Dyre's Blades for a Laser sword theme
  later) and 1.4.0 (Dyre's Fel Sounds), so DCM 0.2.0's release follows
  Dyre's Sounds 1.4.0 (older ones fall back: Fel's `sounds.fallback`). New
  sounds go into Dyre's Sounds, owned by the coordinator session; never
  edit it from here.

### Dyre's Toolkit

- Contract 2 is required (`## Dependencies: DyresToolkit`, CurseForge
  `dyres-toolkit`): `DCM.Toolkit()` checks it, else DCM stays off with one
  line. The record pop is a widget (key `recordpop`, store
  `DyresCritMayhemDB.pop`, size slider "Record pop size"); its text lives in
  a child that fades, so the widget stays shown for the toolkit's outline.
  While unlocked it shows a sample. DCM never moves or scales it itself.
- The records window is a plain dialog, not a widget: it opens in the middle,
  drags by its body while open, closes with Escape, and saves nothing but
  the sort. It is the family's black and gold panel (Dyre's Quest Targeting's
  box style), 95% opaque for reading. The columns come from the list's width
  (Ability half, each number a quarter, text 6 px inside its column); the
  scroll bar shows only when the rows don't fit, and then the list, rows,
  headings, and the heading strip end left of it (author, found in client:
  the crit column was cut off under the bar). Laid out from constants, never
  from the frames' sizes.

## Project structure

- Runtime: DyresCritMayhem.toc, then Commands.lua, Core.lua, Themes.lua,
  Effects.lua, Detect.lua, Records.lua, Window.lua, Probe.lua, Options.lua, plus the thirty-eight
  textures in Textures/ (Splat1-4, Drip1-2, Run1, Butterfly1-2, Star1,
  Sparkle1, Heart1, Burst1-2, Mote1, Ring1, Smoke1-2, Embers1, Crack1, Vignette1
  (64 px, stretched over the screen), Flame1, Shard1, Snowflake1,
  Pow1, Rainbow1 (pre-colored), Maple1, Oak1, Birch1, and Naturalist's Claw1-3,
  Bite1, Insect1, Vine1, Firework1, Vignette2 (64 px, white, tinted), and
  Plus1 (a heal's plus sign, white with a rim, tinted green)).
- scripts/build_splatters.py makes the textures: original procedural art,
  grey (the theme tints them; the cute ones white inside with a darker rim,
  so a pastel reads), run-length encoded 32-bit TGAs, seeded and
  byte-for-byte deterministic; `--preview` writes
  artwork/splatters-preview.png, artwork/tame-preview.png, and
  artwork/motion-preview.png (frames of each moving effect), and
  artwork/naturalist-preview.png. tests/test_splatters.py checks the committed
  textures match it.
- tests/run.lua: the Lua 5.1 mock suite, loading the toolkit's real files
  from ../DyresToolkit when that checkout exists, else from the vendored
  tests/toolkit copy (as in CI). No test checks that the copy matches the
  checkout (John: a shared resource may change); the tests check behavior. tests/test_*.py: the release helpers and
  textures. .github/workflows/: CI, opt-in publishing, the approval gate
  check.
- README.md (players), TESTING.md (method, source evidence, in-client
  checklist), docs/RELEASE_PLAN.md, docs/CURSEFORGE_LISTING.md, CHANGELOG.md.
  Documentation describes design and rules; no dated status reports.
- MIT License; the public author name is `Dyre`, LICENSE keeps John
  Bedworth. TOC `## Group: DyresToolkit` nests DCM under the toolkit in the
  AddOn list; `## Category: Combat` matches the CurseForge main category.
- Add no other runtime assets without agreement. Text is LF under
  .gitattributes. Git origin: none yet (the author creates the repository).

## Client and API verification

- Testing happens on Classic Era 1.15.9 (70003) first; Anniversary 2.5.6
  (70006) next; Forever after launch. Source reviewed in
  C:\Users\jbed\wow-ui-source (classic_era 8165d4c, classic_anniversary
  2cfec7c): `C_CombatLog.GetCurrentEventInfo`, `IsCombatLogRestricted`,
  `UNIT_COMBAT`'s payload, `C_ChatInfo.SendChatMessage`, and
  `C_EventUtils` are documented there. Treat client behavior as authoritative.
- One TOC at Interface 16001, which Era and Anniversary accept as newer.
- WoW APIs can return no values rather than nil; store results in locals
  before `tostring`. The client may hide Lua errors; report in chat.

## Clean coding

- Lua 5.1 only. Four-space indentation. Locals; share state through the
  namespace. Globals only where WoW needs them (slash commands, saved
  variables, the window's name for Escape).
- Event-driven only; OnUpdate never (animations run in the engine). No
  blanket `pcall`, no popups in combat. Repair saved settings on load.
  Startup runs from Core at `PLAYER_LOGIN`, never on handler order.

## Testing, releases, and collaboration

- Run `lua5.1 tests/run.lua`, `luac5.1 -p` on every Lua file, and
  `python -m unittest discover -s tests -p 'test_*.py'`; actionlint on
  workflow changes (tools in ../MageToolsForever/.tools). Report actual
  results.
- Read docs/RELEASE_PLAN.md before packaging. No commits, tags, GitHub
  repository, CurseForge project, uploads, or releases without the author's
  explicit go. Every release needs a CHANGELOG `## <version>` section
  (`### Features` / `### Fixes` / `### Other changes`).
- Commit messages: imperative, capitalized, about 50 characters, no ending
  punctuation, and no Claude or Anthropic attribution (author's rule).
