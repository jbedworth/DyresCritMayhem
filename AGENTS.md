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
    from Low up).
  - **Spellburst** (author: "something for mages, warlocks and priests ...
    doing their thing at range"; working name, one string to rename), not
    mature: bursts of light (Burst1-2: one spins, one twinkles) tinted by
    spell school (`schoolColors`, `DCM.SchoolColor`: fire, frost, arcane,
    shadow, nature, holy, physical white, read in that order for a mixed
    school; unknown or secret: arcane white), drawn with ADD blending
    (`blend`; every pooled texture is set again each time), motes that rise
    from Medium (`drips`, `dripMotion = "float"`), and a ring (`ring`,
    `ringFrom = "high"`) closing the set for a new record and from High.
    `heals = true`: crit heals show too, rising, tinted holy or nature
    (else holy). Sounds from Dyre's Sounds' own: crit {magical, fadingslow,
    war2magicchimes, instrumentsbelltrill}, new record {blowswoosh,
    war2choir, instrumentschimeascending}, extra {teleportvanish,
    disappearingswoosh, impactsbubblesmash} from Medium (the Dyre's Picks
    files play on Classic Era; the game's kit sounds only where Playable). The school comes from the combat log (`spellSchool`, 14;
    swings are physical) or `UNIT_COMBAT`'s school mask.
  - **Fel** (author: "a darker, more... mature theme for warlocks ... No
    magic twinkles or sparkles, keep it scary/dark"; working name, one
    string to rename): 18+ like Brutal (`mature = true`; author: "If we do
    anything truly demonic, it gets 18+"), with the same refusal and the
    same fall back to Tame when the box is cleared. Smoke that curls (a slow spin)
    as it rises and dissolves (Smoke1-2), embers or ash falling from Medium
    (Embers1, ADD via `textureBlend`), cracks spreading from where the smoke
    landed (`run` Crack1 with `runGrow = "center"`, on the overlay, since the
    smoke drifts; never with a falling ember), and for a new record a dark
    vignette around the whole screen (`vignette`, `DCM.PulseVignette`: in
    0.35 s, then a 3 s fade scaled by "Stays on screen"). Palette fel green,
    shadow purple-black, hellfire; `schoolPalette`: shadow crits shadow,
    fire crits hellfire or fel, anything else (or unknown) the palette.
    Heal crits: glowing fel-green wisps drawn upward (its smoke and embers,
    added light), no sparkle. **Placeholder sounds** (the darkest of Dyre's
    Sounds' own) until the author sends demonic, decay, or hellfire packs:
    crit {gorebash, gorechop, impactslowthud, impactsstrangeclang,
    instrumentssynthbuzz}, new record {bigmonsterroar, monsterbear}, extra
    {orcfury, instrumentspitchpipedistressed} from Medium (Dyre's Gore,
    Aggression, and Bears files play on Classic Era; the kit sounds only
    where Playable); swap them in Fel's one sound table.
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
- **Intensity** (Core.lua `INTENSITIES`): Off (the default: every effect
  off) → Low → Medium → High → Total Mayhem, for any theme: more, bigger, longer. At
  100%: Low 2.5 s, Medium 4 s, High 7 s, Total Mayhem 12 s (hold plus fade; the
  earlier Fun, Spicy, Gory, and Mature numbers). Records and their chat line
  work at every intensity, Off too. Total Mayhem stays 12 s, not "until combat ends"
  (the author has not chosen that).
- **Stays on screen** (author), right under the intensity: 25-300% in steps
  of 25, default 100% with the toolkit's gold default mark
  (`AddDefaultTick`); it scales the intensity's hold and fade together. Its
  value reads "100% (7 s)" for the current intensity, and its tooltip lists
  every intensity's seconds at 100%.
- **The 18+ lock is on the theme**: Brutal and Fel need the account-wide box.
  Choosing it without the box says so and keeps the theme; unticking the
  box puts a character on Brutal back on Tame, with a line; a character
  saved on Brutal logs in on Tame while the box is clear. The dropdown reads
  "Brutal (18+)" while locked.
- **Migration** from earlier 0.1.0 test builds (Core.lua `OLD_LEVELS`): old
  level tame → Tame at Low; fun, spicy, gory, mature → Brutal at Low,
  Medium, High, Total Mayhem (Tame without the 18+ box); off → Off. The old `level`
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
- Commands: `/dcm` (or `records`), `options`, `test`, `unlock`, `lock`,
  `reset` (the pop's place), `resetrecords`, `debug` and `probe` (both run
  while unavailable).

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
  Spellburst keeps its own look (`heals = true`), tinted holy or nature.
- **Never change a CVar** (violence level, volume, sound mute): the AddOns we
  studied did, and that is out (author). tests/run.lua fails on `SetCVar` and
  on an `"OnUpdate"` or `pcall` in runtime code.

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
- WoW: Forever: never register `COMBAT_LOG_EVENT_UNFILTERED` there (the
  client blocks it and `IsCombatLogRestricted()` is true; found in client by
  Warlock Tools Forever). Instead (author: "we absolutely MUST make this
  work in Forever"; checked against the pinned source 943764493e):
  - `UNIT_COMBAT` (no secret markings), registered for every unit: "WOUND"
    with "CRITICAL" on "target", "focus", or "nameplateN" is a crit on an
    enemy; "WOUND" with "CRITICAL" or "CRUSHING" on "player" one on you;
    "HEAL" with "CRITICAL" on "player" a crit heal on you (solo only). The
    same flag, amount, and school within 0.05 s count once (the target and
    its nameplate both fire).
  - Solo: every crit on an enemy is yours or your pet's. In a group: only
    with "Guess my crits in a group" (off by default; the switch shows only
    on this path): a crit on your target within 0.6 s of your own harmful
    cast. With three others on the target, about one cast in three also
    catches someone else's crit. No records in a group.
  - Records, solo: matched to the last harmful cast (`UNIT_SPELLCAST_SUCCEEDED`
    for player and pet, `C_Spell.IsSpellHarmful`, `GetSpellName`): a physical
    hit within 0.4 s of a cast is that ability; another physical hit is
    Melee, or unknown with a pet out; a spell-school hit is the latest cast
    within 1.5 s (projectiles); else no record. Damage over time lands as the
    last cast: best guesses, and the window says so.
  - `C_DamageMeter` (SecretWhenInCombat) has per-spell totals per fight but
    no largest hit: `maxAmount` only scales the bars
    (Blizzard_DamageMeter/DamageMeterSourceWindow.lua), so it cannot give
    records. `/dcm probe` dumps it after each fight to confirm.
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
  later), so DCM's release needs Dyre's Sounds 1.2.0 released first. New
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
  Effects.lua, Detect.lua, Records.lua, Window.lua, Probe.lua, Options.lua, plus the twenty-one
  textures in Textures/ (Splat1-4, Drip1-2, Run1, Butterfly1-2, Star1,
  Sparkle1, Heart1, Burst1-2, Mote1, Ring1, Smoke1-2, Embers1, Crack1, Vignette1
  (64 px, stretched over the screen)).
- scripts/build_splatters.py makes the textures: original procedural art,
  grey (the theme tints them; the cute ones white inside with a darker rim,
  so a pastel reads), run-length encoded 32-bit TGAs, seeded and
  byte-for-byte deterministic; `--preview` writes
  artwork/splatters-preview.png, artwork/tame-preview.png, and
  artwork/motion-preview.png (frames of each moving effect). tests/test_splatters.py checks the committed
  textures match it.
- tests/run.lua: the Lua 5.1 mock suite, loading the toolkit's real files
  from tests/toolkit (which must match ../DyresToolkit; a Python test
  checks when the checkout exists). tests/test_*.py: the release helpers and
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
