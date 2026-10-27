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
Dyre's Sounds, and the real Dyre's Toolkit files from tests/toolkit. Its
`SetCVar` raises, and registering the combat log raises when the fixture
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
   theme=tame intensity=off adult=false stay=100`.
2. **Off**: fight something. No sound, nothing on screen. `/dcm` lists your
   abilities' highest hit and crit anyway, and beating one says so in chat.
3. **Settings**: Options > AddOns > Dyre's AddOns > Crit Mayhem. From the
   top: I'm 18 or over, Theme (Tame, "Brutal (18+)"), Intensity (Off, Low,
   Medium, High, Total Mayhem), and Stays on screen (100% with a gold mark). Choose
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
5. **Spellburst** (a Mage or Warlock, then a Priest):
   - A new character of any class starts on Tame; pick Spellburst in the
     Theme dropdown.
   - `/dcm test` runs through fire, frost, arcane, shadow, nature, and holy
     colors. Real crits: Fireball orange, Frostbolt blue, Shadow Bolt
     purple, Arcane Missiles violet; melee white. The bursts glow (added
     light) rather than cover the screen.
   - From Medium a mote rises with each crit; from High a ring of light
     closes each set, and a new record gets one at any intensity.
   - Priest with "Heals too": a crit Flash Heal shows gold light rising; a
     Druid's Healing Touch green.
   - The extra sound (any theme that has one) joins only about 3 crits in
     10, from its intensity.
   - Sounds on Era: Magical disappear or Fading slow disappear per crit,
     Disappear blow swoosh for a record, Teleport warp vanish or
     Disappearing swoosh from Medium (the game's kit sounds in the set play
     only where the client can, not on Era). None silent.
6. **Fel** (a Warlock):
   - With "I'm 18 or over" clear, the dropdown reads "Fel (18+)" and
     choosing it says it is for 18 and over. Tick the box: Fel works. Clear
     it: back to Tame, with a line. A new character still starts on Tame.
   - Shadow Bolt and Corruption crits: purple-black smoke that turns slowly
     as it rises and dissolves; Immolate or Searing Pain: hellfire red or
     fel green; melee or the pet's: the mix. No sparkles or stars.
   - From Medium an ember or two falls with each crit; now and then cracks
     creep out under the smoke where it landed and fade with it.
   - A new record: the screen's edges darken and fade slowly (longer with
     "Stays on screen" up).
   - Sounds on Era (Dyre's Sounds 1.4.0): Fel Sounds' Wet smash, Mud
     splat, or Heartbeat per crit; Demon growl for a record; from Medium a
     Heartbeat now and then after a smash or splat, never two heartbeats
     at once. None silent. With Dyre's Sounds 1.3.0: Gore: Bash or Chop,
     Big monster roar or Monster bear, Orc spitting fury.
6a. **Naturalist** (a Druid; full client restart: seven new textures):
   - With "I'm 18 or over" clear, the dropdown reads "Naturalist (18+)" and
     choosing it says it is for 18 and over. Tick the box: Naturalist works.
     Clear it: back to Tame, with a line. A new character starts on Tame.
   - Cat or Bear form (Claw, Rake, Maul, Swipe, white swings): a mix of
     claw scratches (two, three, or four lines), bite marks, and blood
     splatter, each at its own angle and size, never all alike; now and
     then one grows a trickle that runs straight down the screen, however
     the mark is turned. From High a dripping one too.
   - "Claws only in Cat or Bear form" sits under the Theme, greyed except
     on Naturalist, clear by default. Clear: caster form with a mace, and
     a Warrior on Naturalist, still mix claws, bites, and splatter.
   - Tick it: out of form (caster form with a mace or staff, Moonkin,
     Travel, Aquatic), a Warrior, crits on you, and others' crits are
     Brutal's blood splatter only, with its drips and runs. Shift back to
     Cat: claws again on the next crit. A Hunter's pet ("Pet's crits" on)
     claws and bites; a Warlock's demon splatters.
   - Brutal (no box): a Druid in Cat or Bear form gets claws, bites, and
     splatter in Brutal's red; in caster form, and a Warrior, Brutal's
     splatter as before. A Hunter's pet claws. Spells look as before.
   - Wrath: a murky dark-green burst (no glow, no twinkle) with 4 to 6
     beetles and dark leaf bits blowing out and falling, tumbling.
   - Moonfire (arcane on Era): silver firework sprays at random spots,
     fading. No stars.
   - Fire (a fire-damage weapon or proc): a scorched splat with a charred
     leaf burning on it, then embers rising. Frost: pale frozen leaves
     with an ice shard on frozen blood. Holy: a harsh flare and ring on a
     scorch. Shadow: black leaves on dark ichor with a smear.
   - "Heals too", a crit Healing Touch or Rejuvenation tick: vines and
     green or gold smoke rising, never flowers or hearts.
   - A new record: the screen's edges go deep green and fade slowly.
   - Sounds on Era: Angry cat, Tiger growl, or Gore: Slice per crit; Bear
     roar, Monster bear, or Lion roar for a record; Wet splat hit from
     Medium on about 3 crits in 10. None silent.
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
   Spellburst gold light. Damage crits look as before.
8. **By damage school** (full client restart: five new textures):
   - A Mage on Spellburst meleeing with a staff: a crit shows a white flash
     (a burst and a ring) without the 18+ box, blood with it. Fireball an
     orange burst with a flame; Frostbolt a blue burst with an ice shard;
     Arcane Missiles violet bursts. Every spell still looks like Spellburst.
   - A Warrior on Brutal with a fire-damage enchant or proc (Fiery Weapon,
     a fire-damage weapon): its crit is still a wound, charred dark with a
     few rising embers; melee crits red blood as before. On Tame: little
     flames, and a pow for melee.
   - A Warlock on Fel: Shadow Bolt purple-black smoke; Immolate or Searing
     Pain hellfire smoke with a flame lick; Frostbolt-like frost icy smoke
     with a shard; melee or the pet Brutal's red blood; no sparkles.
   - Each theme is recognisable at a glance whatever the school.
   - Nature crits (a Druid's Wrath or Moonfire, or `/dcm test`): Tame a
     puff of 3 to 5 small tumbling leaves blowing out and down; Spellburst
     a green burst with the puff blowing out and up; Brutal one or two
     dark, blood-soaked leaves stuck on the red splat with a smear running
     down; Fel a leaf in hellfire or fel green with a flame on it, then
     grey ash falling from it as it fades. Never acid green on Brutal.
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
13. **Game settings untouched**: violence level, master and effects volume,
   and sound effects are what they were before.
14. **Anniversary**: repeat 1, 2, 4, and 10.
15. **Forever, launch day** (about 5 minutes; Brutal or Tame at Medium):
    1. `/dcm debug`: `detection=unitcombat combatLogRestricted=true`, and no
       blocked-action error since login.
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
    3. Did crits play effects, and does `/dcm` show records (the hint says
       "Solo guesses from combat text")? Do they match your combat text?
    4. Group with someone: with Nearby enemies their crits on your target
       and on enemy nameplates play, with no record; My target only the
       target; Off nothing.
    5. `/reload`, then send `WTF/Account/<account>/<realm>/<character>/
       SavedVariables/DyresCritMayhem.lua` (its `probe.lines`).
