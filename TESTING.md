# Testing

## Automated

From the repository root (tools in ../MageToolsForever/.tools):

```sh
lua5.1 tests/run.lua
luac5.1 -p *.lua tests/run.lua tests/toolkit/*.lua
python -m unittest discover -s tests -p 'test_*.py'
actionlint .github/workflows/*.yml
```

tests/run.lua mocks the client: the combat log (fields at their real
positions), `UNIT_COMBAT`, Settings, frames, AnimationGroups, chat, popups,
Dyre's Sounds, and the real Dyre's Toolkit files: from ../DyresToolkit when
that checkout exists, else from the vendored tests/toolkit copy (as in CI).
No test checks that the copy matches the checkout. Its
`SetCVar` raises for any CVar but `violenceLevel` (and for that one in
combat), and registering the combat log raises when the fixture
restricts it, as Forever does. Mocks cannot show how the effects look, the
real sounds, layout, taint, or secret values; those need the client.

## Source evidence

From C:\Users\jbed\wow-ui-source, classic_era (8165d4c, 1.15.9 70003) and
classic_anniversary (2cfec7c, 2.5.6 70006):

- `CombatLogDocumentation.lua`: `C_CombatLog.GetCurrentEventInfo`
  (HasRestrictions), `IsCombatLogRestricted`, and
  `COMBAT_LOG_EVENT_UNFILTERED` (HasRestrictions).
- `Blizzard_DeprecatedCombatLog/Deprecated_CombatLog.lua`:
  `CombatLogGetCurrentEventInfo` is an alias, only with the
  `loadDeprecationFallbacks` CVar; DCM prefers `C_CombatLog`.
- `UnitDocumentation.lua`: `UNIT_COMBAT` (unitTarget, event, flagText,
  amount, schoolMask).
- `ChatInfoDocumentation.lua`: `SendChatMessage` (HasRestrictions; SAY and
  YELL need a hardware event, PARTY and GUILD do not on Classic).
- Forever: Warlock Tools Forever found `IsCombatLogRestricted()` true and
  registering the combat log blocked (its TESTING.md).

## In-client checklist (Classic Era first)

Install Dyre's Toolkit, Dyre's Sounds, and DCM. Turn off other crit AddOns
(CritsBloodyCrits, LightsaberCrit, RainingBlood) so their effects don't mix
in, and BugSack on to catch errors.

1. **Login**: `DCM: Dyre's Crit Mayhem 0.2.0 by Dyre` and the ready line; no
   errors. `/dcm debug` says `detection=combatlog combatLogRestricted=false
   theme=tame intensity=low adult=false stay=100`.
2. **None**: pick the None theme, then fight something. No sound, nothing
   on screen, no hit effects. `/dcm` lists your abilities' highest hit and crit
   anyway, and beating one says so in chat. `/dcm test` says the theme is
   None. A character saved at Off in 0.2.1 logs in on None at Low.
3. **Settings**: Options > AddOns > Dyre's AddOns > Crit Mayhem. From the
   top: I'm 18 or over, Theme (None first, then Tame, the default,
   and "Brutal (18+)"), Intensity (Low, the default,
   Medium, High, Total Mayhem; no Off), and Stays on screen (100% with a gold mark). Choose
   Brutal: chat says it is for 18 and over and the theme stays Tame. Tick
   "I'm 18 or over": Brutal works. Untick it: back to Tame, with a line.
4. **Effects** at each intensity with `/dcm test`, then real crits, on both
   themes:
   - Tame: pastel butterflies, stars, and sparkles floating up, with light
     shimmers; no blood, never drips. Low one, Total Mayhem seven. Stars
     turn slowly, butterflies flutter (does the pinch look like wings, or
     should it be two wing frames?), sparkles twinkle, and all of it still
     pops in and floats up.
   - Brutal: Low one splat and a hit sound; Medium two, plus a squelch;
     High four, one dripping down; Total Mayhem the most. Some splats stay
     put while a run grows down from under them (about a quarter at Low,
     more higher up), then fade with them.
   - At Total Mayhem in a long fight, at most 12 effects move at once; no
     frame drops.
   - Each intensity stays noticeably longer (at 100%: about 2.5, 4, 7, and
     12 seconds). "Stays on screen" shows the seconds for your intensity; at
     300% High stays about 21 seconds, at 25% under 2.
   - Characters set up with earlier test builds: a character that was on
     Gory is on Brutal at High (Tame at High without the 18+ box).
   - The blood is under the action bars and unit frames, never in the
     middle, and fades on its own.
   - Sounds (Dyre's Sounds 1.2.0 installed): Brutal plays a gore slice, chop,
     or bash per crit, never the same twice in a row, a bloody impact or
     splat for a new record, and a wet splat or punch from Medium; Tame a
     kiss, swish, or shimmer, and kisses or a rising chime for a record.
   - An area spell critting many targets doesn't flood the screen.
5. **Styles of Brutal** (Spellburst, Fel, Naturalist; nameplates on):
   - Each reads "(18+)" and is refused with "I'm 18 or over" clear; clear
     the box while on one: back to Tame, with a line. A character saved on
     Spellburst without the box logs in on Tame.
   - Your own damage takes the style; damage on you and others' stay
     Brutal's. Check with `/dcm test fire` (and the other schools) on a
     target, then let a mob hit you, then watch a groupmate's crits.
   - **Spellburst** (a Mage, then a Priest): Brutal's wounds with a glow in
     the school's color on each crit (Fireball orange, Frostbolt blue,
     Shadow Bolt purple, Arcane Missiles violet, melee white); a ring
     closes a new record's set. Spell hits on the mob are denser than on
     Brutal, with a bigger crit flash. "Heals too": a crit heal rises in
     gold or green light. Sounds on Era: Magical disappear or Fading slow
     disappear per crit, Disappear blow swoosh for a record. The extra
     sound joins only about 3 crits in 10, from Medium.
   - **Fel** (a Warlock, then a Paladin): every school in dark blood,
     purple, and fel green: Shadow Bolt black-purple, Immolate fel green,
     a Paladin's holy black, purple, and green smoke on the mob, never
     gold. Cracks creep from the wounds; a wisp of dark smoke rises on each
     crit; a new record darkens the screen's edges. Sounds on Era (Dyre's
     Sounds 1.4.0): Wet smash, Mud splat, or Heartbeat per crit; Demon growl
     for a record; never two heartbeats at once. With Dyre's Sounds 1.3.0:
     Gore: Bash or Chop, Big monster roar or Monster bear.
   - **Naturalist** (a Druid): Cat or Bear form melee crits mix claw
     scratches, bite marks, and splatter, each at its own angle, some with
     a trickle straight down. "Claws only in Cat or Bear form" sits under
     the Theme, greyed except on Naturalist, clear by default; tick it: out
     of form, a Warrior, and crits on you are Brutal's splatter; a Hunter's
     pet claws, a Warlock's demon splatters. Other schools in earthy tints
     (moss, bark, amber, silver); Wrath throws leaves on the screen, and
     its hits on the mob are a flurry of leaves and beetles; Moonfire's are
     silver sparks. Crit heals: vines and green or gold smoke. A new
     record: the screen's edges go deep green. Sounds on Era: Angry cat,
     Tiger growl, or Gore: Slice; Bear roar, Monster bear, or Lion roar.
   - Brutal: a Druid in Cat or Bear form gets claws, bites, and splatter in
     Brutal's red; in caster form, and a Warrior, Brutal's splatter.
7. **Sounds section**: tick "Crit: my own sound", choose Dyre's Blades:
   Laser sword swing (it plays once); crits now always play it, also after
   switching theme. "Reset sounds to theme": the theme's random ones again.
   With an older Dyre's Sounds (1.1.0), crits still make a sound. Choose
   Text to Speech for a row: the preview says "Crit!" (or "New record!",
   "Boom!"), and so do the crits.
   **Switches**: Sounds off (effects only), On-screen effects off (sounds
   only, no squelch). My pet's crits (a Hunter or Warlock pet), Crits on me (blood at
   the edges), Heals too (heal records labeled "(heal)"). On a Paladin with "Heals too",
   crit Holy Light or Flash of Light: Tame shows pink and gold hearts (they
   beat), a sparkle, or a butterfly rising; Brutal warm red and gold
   droplets of light rising, no blood; Fel glowing green wisps rising;
   Spellburst gold or green light. Damage crits look as before.
8. **By damage school** (full client restart: five new textures):
   - A Warrior on Brutal with a fire-damage enchant or proc (Fiery Weapon,
     a fire-damage weapon): its crit is still a wound, charred dark with a
     few rising embers; melee crits red blood as before. On Tame: little
     flames, and a pow for melee.
   - Nature crits (a Druid's Wrath or Moonfire, or `/dcm test`): Tame a
     puff of 3 to 5 small tumbling leaves blowing out and down; Brutal one
     or two dark, blood-soaked leaves stuck on the red splat with a smear
     running down (Fel's in dark green and purple). Never acid green on
     Brutal.
   - A spell of two schools (Frostfire, Shadowflame) shows its first:
     fire.
   - On Tame, now and then a little rainbow (in its own colors) floats up
     among the stars and butterflies, and with holy crits.
   - On Tame, "Random Effects" sits under the theme; tick it and every crit
     shows stars, butterflies, and sparkles again; clear it, the school
     looks. Choose Brutal: the row greys at once; back to Tame: live.
9. **Others' crits** (Era, in a group, nameplates on): stand back while a
   groupmate fights.
   - Nearby enemies (the default): their crits on your target and on any
     enemy with a nameplate shown play one effect each and a sound; nothing
     new appears in `/dcm`. A mob without a nameplate plays nothing.
   - My target: only their crits on your target.
   - Off: nothing of theirs.
   - Pull a big pack at Total Mayhem: their effects stay a trickle (a few
     per half second), and your own crits still play in full.
10. **Records**: beat an ability's record: chat says `New record! <ability>
   crit <n> (was <m>)`, and the crit sounds bigger. Show new records on
   screen: the pop shows and fades. `/dcm unlock`: a sample pop to drag and
   size ("Record pop size"); `/dcm lock`; `/dcm reset`.
11. **Announcements**: in a party, Announce in party sends one line; a
   second record within 10 seconds is not sent. Guild the same.
12. **Window**: `/dcm`. The panel is dark enough to read over the world.
   With a few records there is no scroll bar and the crit column sits fully
   inside the right edge; with more than 15 the scroll bar shows and every
   column ends left of it. The headings line up over their numbers, and the
   white heading is the sort the hint below names. Click each heading twice
   (both directions). Escape closes it. Options opens the page. Reset records in combat refuses; out
   of combat it asks, and Yes clears.
12a. **Hit effects** (Forever and Era, enemy nameplates on with V):
   Brutal at Low, hit a mob: every hit (a DoT tick too) plays from under
   its nameplate, over its body, following the mob. Melee: a blood spray.
   A crit: twice as much, bigger, thrown farther, and a big burst of
   blood (or a glow in the school's color) at the impact: tell a crit
   from a hit at a glance, on the mob and on you. `/dcm test` cycles (`/dcm test fire` and so on holds one) fire, frost, arcane, shadow,
   nature, holy on your target's plate (on you without a target): flames
   fall through the body, snow drifts and turns, sparks burst, smoke
   rises, holy throws golden sparkles (no ring). The effect starts at
   the mob's body, well under its nameplate. Distance: hit a mob up
   close, then one at 30 yd (a ranged pull or a wand): the far one's
   effect is much smaller, and nearer its plate. Is the spot on the body right, or too high
   or low? Get hit: the same over your character in the middle of the
   screen (is it on your character?). Get healed: green plus signs rise.
   Fel: shadow smoke is greenish. Tame or None: nothing on the mob.
   Turn nameplates off: nothing on the mob, the screen splatter still
   plays. Kill a mob mid-effect: its effects go with its plate. Clear
   **Hit effects on enemies** or **on you**: none there.
   Bystanders (Nearby enemies): a mob hitting another player or a guard
   with a nameplate shows its hit effect on them, and its crits splatter
   your screen as others' crits; on your friendly target too (My target). Others' crits Off: none.
13. **Game settings untouched**: master and effects volume and sound effects
   are what they were before.
13a. **Gore** (Forever and Era): `/run print(GetCVar("violenceLevel"))`
   first (your own level). Brutal at Low prints 3, Medium 4, High and Total
   Mayhem 5; None, Tame, or clearing the 18+ box prints your own level again.
   Hit a beast or humanoid on None and on Brutal at Total Mayhem: more blood on the
   model? Change it in combat: it applies when combat ends.
14. **Anniversary**: repeat 1, 2, 4, and 10.
15. **Forever, launch day** (about 5 minutes; Brutal or Tame at Medium):
    1. `/dcm debug`: `detection=unitcombat combatLogRestricted=true`, and no
       blocked-action error since login. Its second line, `since login
       hits=N recorded=N grouped=N secretSchool=N noCast=N secretAmount=N
       noAmount=N`, counts hits on enemies and why each made no record:
       in a group, a secret school, no cast to match, a secret amount, or
       an amount not above 0. After a solo fight, `recorded` should be
       above 0.
    2. `/dcm probe`, then solo: target a mob and fight it with your spells and
       melee, then let a fight end. In chat (first 40 lines):
       - `UNIT_COMBAT target WOUND CRITICAL amount=<n> school=<n>
         secret=-----`: combat text reaches AddOns, readable. Do lines also
         come for `nameplateN` (nameplates on) and `focus`? Is anything
         `<secret>`?
       - `CAST player spell=<id> <name> harmful=true secret=-`: your casts
         are readable; `guess=<ability>` on the hits after them is right?
       - after the fight, `meter: ...` lines: is the meter readable then,
         `local=true` on your line, and what are `maxAmount` and
         `detailAmount` (a largest hit, or totals)?
    3. Did crits play effects? `/dcm` opens the options, not the records
       window. In the Records section every row but Test crit is greyed,
       and each one's tooltip says "Presently, WoW Forever blocks addons
       ability to read damage amounts you do. ..."; the greyed buttons do
       nothing. `/dcm records` says "No records on this client: it
       hides how much each hit does from AddOns" (build 70938 hides every
       amount: `secretAmount` equals `hits` in `/dcm debug`).
    4. Group with someone: with Nearby enemies their crits on your target
       and on enemy nameplates play, with no record; My target only the
       target; Off nothing.
    5. `/reload`, then send `WTF/Account/<account>/<realm>/<character>/
       SavedVariables/DyresCritMayhem.lua` (its `probe.lines`).
