local addonName, DCM = ...

-- Themes say what the mayhem looks and sounds like; the intensity (Core's
-- INTENSITIES) says how much, how big, and how long, for any theme (author:
-- "make 'Tame' a theme, and leave the slider for 'Intensity'"). Tame comes
-- first and is the default: butterflies, stars, and sparkles in pastels with
-- light shimmers. Brutal is for 18 and over (author: "Require 18+ to turn on
-- the 'Brutal' theme"): heavy flesh impacts, bone crunches, blood splatter.
-- Others plug in the same way later (planned: Cartoon smack, Laser sword,
-- Arcane, Retro arcade, Kung fu), each flagged mature or not. Never a film's
-- name, audio, or marks (author: no "Lightsaber").
--
-- A theme is data:
--   key, name, description, mature (needs the account's 18+ box);
--   splats: texture paths, one picked per effect; colors: tints, one picked
--   per effect (the textures are grey, so one set serves every color);
--   size: times the intensity's size; motion: "float" (rises and only tilts,
--   for butterflies) or nil (turned any way, for blood);
--   drips and dripsFrom: dripping textures, one per crit from that intensity
--   (dripMotion "float" makes them rise instead);
--   ring and ringFrom: one ring closes the set for a new record, and from
--   that intensity; blend "ADD" for glows; schoolColors: tint by spell school
--   (DCM.SchoolColor) instead of colors; schoolPalette: a few colors for
--   some schools, else colors (DCM.PaletteColor); textureBlend: a blend per
--   texture; untinted: textures drawn in their own colors (a rainbow);
--   runGrow "center": the run spreads from the splat's spot;
--   vignette: a dark frame around the screen for a new record;
--   heals: crit heals show too, rising, in the theme's own look (Spellburst);
--   heal: a heal style instead (author: every theme gets a heal-crit visual,
--   gentle, rising, and clearly not damage): splats, colors, blend,
--   animations, and size, drawn rising;
--   animations: texture path -> a looping move while it holds ("spin",
--   "flutter", "twinkle"); run and runChance (intensity key -> 0 to 1): a
--   splat that stays put while a trickle grows down from under it;
--   sounds: a pool of 2-3 Dyre's Sounds keys per event (author: "Each theme
--   should set defaults - there should be 2-3 sounds that play randomly on
--   each crit"): crit, big (a new record), and optional extra with
--   extraFrom and extraChance (Brutal's squelch, about 30% of the time
--   with the effects on screen, from that
--   intensity). DCM.PickSound picks one at random, never the same twice in
--   a row; the player's own pick per event (the Sounds section) wins. The
--   library plays it, and DCM ships no sound. fallback: pools per event for
--   an older Dyre's Sounds without the theme's keys (Fel's).
local TEXTURES = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
local SOUNDS_MISSING = "The crit sounds come from Dyre's Sounds: install it from CurseForge to hear them."
-- The events a theme has sounds for, in the Sounds section's order.
DCM.SOUND_EVENTS = {"crit", "big", "extra"}
-- When none of a theme's keys can play here: Interface: Talent ready, a
-- sound kit by name that every client plays. (Classic Era and Anniversary
-- play none of Dyre's Sounds' kit-ID or file-ID sounds, Impacts through
-- Hellish imp; found in client.)
local FALLBACK_SOUND = "talent"
-- What Text to Speech says for each event, when a theme's sound or your own
-- pick is a voice (Dyre's Sounds plays a voice only with words to say).
DCM.SOUND_SPEECH = {crit = "Crit!", big = "New record!", extra = "Boom!"}
-- How often the extra joins a crit that may have it; a theme's
-- sounds.extraChance overrides it.
DCM.EXTRA_CHANCE = 0.3

local themes, order = {}, {}

-- None (author: "Move 'None' (zero) from the slider ... to the Theme
-- selector. Have it be the first item, above Tame"): every effect and sound
-- off; records still count. Not in DCM.Themes() (the effect themes); the
-- Theme dropdown lists it first.
DCM.NONE_THEME = "none"
themes[DCM.NONE_THEME] = {key = DCM.NONE_THEME, name = "None", none = true, sounds = {},
    description = "No effects or sounds. Your records still count."}

function DCM.RegisterTheme(theme)
    assert(type(theme) == "table" and type(theme.key) == "string" and type(theme.name) == "string",
        "DCM.RegisterTheme: key and name")
    assert(themes[theme.key] == nil, "DCM.RegisterTheme: " .. theme.key .. " is registered already")
    -- A heal style draws like a small theme of its own: it rises, with no
    -- drips, runs, rings, or vignette.
    if theme.heal then
        theme.heal.motion = "float"
        theme.heal.size = theme.heal.size or theme.size
    end
    themes[theme.key] = theme
    order[#order + 1] = theme.key
end

function DCM.Themes()
    local list = {}
    for _, key in ipairs(order) do
        list[#list + 1] = themes[key]
    end
    return list
end

function DCM.FindTheme(key)
    return themes[key]
end

-- The character's theme, else the default (a theme that was removed).
function DCM.Theme()
    return themes[DCM.db and DCM.db.theme] or themes[DCM.DEFAULT_THEME]
end

-- How each school's hit looks on its target (author: "physical:
-- bloodspray/splatter, cold/frost: snow/ice flurries; fire: burning flames
-- raining down; arcane: spark showers; shadow/fel: black or greenish smoke";
-- "heals should be little green +'s"): textures, tints, blend, size, and
-- motion (Effects.lua HIT_MOTIONS); upright: turned only a little, tip up:
--   spray: out from the body and falling (blood);
--   flurry: from above the body, drifting down and turning (snow and ice);
--   blaze: the body on fire (author: "When you cast a warlock's immolate
--   spell, it makes it look like the mob is burning ... I want that same
--   effect for every tick of fire damage"; then, from screenshots, our
--   flame shapes were "cartoon flame leafs" next to Immolate's soft glow):
--   soft smoke puffs drawn as added light in fire colors around a bright
--   yellow core, roiling and swelling on the body, then fading;
--   burst: out in every direction, fast and short (sparks);
--   smoke: rising slowly and spreading;
--   rise: floating up (holy light, heals).
-- Nature (lightning, Wrath, poisons) is a green crackle of sparks. Physical
-- blood needs the 18+ box, as on the screen; without it, a white impact
-- (impact). A variant's `hits` restyle these for your damage (Variant).
-- flash: a crit's one big piece at the impact (author, 2026-11-17: "crits
-- are not visibly discernable from normal hits"), times the piece size:
-- a burst of blood, else a glow or a puff in the school's colors.
DCM.HIT_STYLES = {
    physical = {textures = {TEXTURES .. "Splat1", TEXTURES .. "Splat2", TEXTURES .. "Splat3", TEXTURES .. "Splat4"},
        colors = {{0.55, 0, 0}, {0.42, 0.02, 0.02}}, blend = "BLEND", size = 1, motion = "spray",
        flash = {texture = TEXTURES .. "Splat3", blend = "BLEND", size = 3.2}},
    impact = {textures = {TEXTURES .. "Sparkle1", TEXTURES .. "Mote1"},
        colors = {{1, 1, 1}, {0.9, 0.9, 0.85}}, blend = "ADD", size = 0.6, motion = "burst",
        flash = {texture = TEXTURES .. "Burst1", blend = "ADD", size = 4}},
    -- Dense and fine (author: "increase the number of frost particles and
    -- cut their size so it's not so obviously a cartoon snowflake"): mostly
    -- soft motes, some small flakes and shards. count: times the pieces.
    frost = {textures = {TEXTURES .. "Mote1", TEXTURES .. "Mote1", TEXTURES .. "Mote1", TEXTURES .. "Snowflake1",
        TEXTURES .. "Snowflake1", TEXTURES .. "Shard1"},
        colors = {{0.85, 0.95, 1}, {0.6, 0.8, 1}, {1, 1, 1}}, blend = "BLEND", size = 0.35, count = 2.5,
        motion = "flurry",
        flash = {texture = TEXTURES .. "Burst1", blend = "ADD", size = 4}},
    fire = {textures = {TEXTURES .. "Smoke1", TEXTURES .. "Smoke2", TEXTURES .. "Smoke1", TEXTURES .. "Burst2"},
        colors = {{1, 0.3, 0.04}, {1, 0.5, 0.08}, {1, 0.72, 0.2}}, blend = "ADD", size = 1.1, motion = "blaze",
        textureColors = {[TEXTURES .. "Burst2"] = {1, 0.88, 0.4}},
        flash = {texture = TEXTURES .. "Burst2", blend = "ADD", size = 3.5}},
    arcane = {textures = {TEXTURES .. "Sparkle1", TEXTURES .. "Sparkle1", TEXTURES .. "Mote1"},
        colors = {{0.75, 0.5, 1}, {0.95, 0.82, 1}}, blend = "ADD", size = 0.6, motion = "burst",
        flash = {texture = TEXTURES .. "Burst1", blend = "ADD", size = 4.5}},
    shadow = {textures = {TEXTURES .. "Smoke1", TEXTURES .. "Smoke2"},
        colors = {{0.12, 0.05, 0.16}, {0.05, 0.05, 0.06}}, blend = "BLEND", size = 1.2, motion = "smoke",
        flash = {texture = TEXTURES .. "Smoke1", blend = "BLEND", size = 2.6}},
    -- Dense and fine, as frost (author: "Do the same for nature").
    nature = {textures = {TEXTURES .. "Mote1", TEXTURES .. "Mote1", TEXTURES .. "Mote1", TEXTURES .. "Sparkle1"},
        colors = {{0.55, 1, 0.35}, {0.9, 1, 0.65}, {0.75, 1, 0.5}}, blend = "ADD", size = 0.3, count = 2.5,
        motion = "burst",
        flash = {texture = TEXTURES .. "Burst1", blend = "ADD", size = 4.5}},
    -- As arcane, in gold (author: "drop the circle-halo thingy, and make it
    -- look more like arcane, but with golden sparkles").
    holy = {textures = {TEXTURES .. "Sparkle1", TEXTURES .. "Sparkle1", TEXTURES .. "Mote1"},
        colors = {{1, 0.82, 0.3}, {1, 0.93, 0.6}}, blend = "ADD", size = 0.6, motion = "burst",
        flash = {texture = TEXTURES .. "Burst1", blend = "ADD", size = 4.5}},
    heal = {textures = {TEXTURES .. "Plus1"},
        colors = {{0.35, 1, 0.35}, {0.6, 1, 0.5}}, blend = "BLEND", size = 0.45, motion = "rise",
        flash = {texture = TEXTURES .. "Burst1", blend = "ADD", size = 6}},
}

-- Whether a theme's touch (drips, the squelch) is on at this intensity.
function DCM.ThemeFrom(fromKey, intensityIndex)
    return fromKey ~= nil and intensityIndex >= DCM.INTENSITY_INDEX[fromKey]
end

DCM.RegisterTheme({
    key = "tame",
    name = "Tame",
    description = "Butterflies, stars, and sparkles in soft pastels, with light shimmers.",
    -- No hit effects on the target yet (author: "Tame gets none of these on
    -- target effects for now; we can design this later").
    noHits = true,
    -- A rainbow among them (author: "I intended it as a texture to add to
    -- Tame to vary what shows up"), drawn in its own colors.
    splats = {TEXTURES .. "Butterfly1", TEXTURES .. "Butterfly2", TEXTURES .. "Star1", TEXTURES .. "Sparkle1",
        TEXTURES .. "Rainbow1"},
    untinted = {[TEXTURES .. "Rainbow1"] = true},
    -- Pink, lavender, mint, butter.
    colors = {{1, 0.72, 0.84}, {0.8, 0.72, 1}, {0.68, 0.95, 0.82}, {1, 0.93, 0.62}},
    size = 0.6,
    motion = "float",
    -- The "Random Effects" setting (author: "make it a setting I can toggle
    -- if the Tame theme is selected"): ticked, every damage school draws the
    -- stars, butterflies, and sparkles above; clear (the default), Tame's
    -- look for each school.
    randomEffects = true,
    -- Heal crits: hearts (beating), a sparkle, or a butterfly, in pink and gold.
    heal = {
        splats = {TEXTURES .. "Heart1", TEXTURES .. "Heart1", TEXTURES .. "Sparkle1", TEXTURES .. "Butterfly1"},
        colors = {{1, 0.6, 0.75}, {1, 0.85, 0.4}},
        animations = {
            [TEXTURES .. "Heart1"] = "twinkle",
            [TEXTURES .. "Sparkle1"] = "twinkle",
            [TEXTURES .. "Butterfly1"] = "flutter",
        },
    },
    -- Stars turn slowly, butterflies flutter, sparkles twinkle (author).
    animations = {
        [TEXTURES .. "Butterfly1"] = "flutter",
        [TEXTURES .. "Butterfly2"] = "flutter",
        [TEXTURES .. "Star1"] = "spin",
        [TEXTURES .. "Sparkle1"] = "twinkle",
    },
    -- Playful: a kiss, a swish, a shimmer; kisses or a rising chime for a record.
    sounds = {
        crit = {"kiss", "swishsmack", "war3magicshimmer"},
        big = {"kisses", "instrumentschimeascending"},
    },
})

-- Spell-school tints (school masks: 1 physical, 2 holy, 4 fire, 8 nature,
-- 16 frost, 32 shadow, 64 arcane), in the order a mixed school (Frostfire)
-- is read, the same as DCM.SchoolKind's; shadow is purple, since black adds
-- no light. An unknown or secret school: arcane white.
local SCHOOL_COLORS = {
    {mask = 4, color = {1, 0.5, 0.12}},
    {mask = 16, color = {0.45, 0.8, 1}},
    {mask = 32, color = {0.6, 0.3, 0.95}},
    {mask = 64, color = {0.9, 0.45, 1}},
    {mask = 8, color = {0.4, 1, 0.4}},
    {mask = 2, color = {1, 0.92, 0.6}},
    {mask = 1, color = {1, 1, 1}},
}
local UNKNOWN_SCHOOL = {0.85, 0.85, 1}
local HOLY = {1, 0.92, 0.6}

local function HasSchool(school, mask)
    return school % (mask * 2) >= mask
end

-- The tint for a crit of this school; a heal is holy or nature, else holy.
function DCM.SchoolColor(theme, school, heal)
    if type(school) ~= "number" or DCM.IsSecret(school) or school <= 0 then
        return heal and HOLY or UNKNOWN_SCHOOL
    end
    for _, entry in ipairs(SCHOOL_COLORS) do
        if HasSchool(school, entry.mask) and (not heal or entry.mask == 2 or entry.mask == 8) then
            return entry.color
        end
    end
    return heal and HOLY or UNKNOWN_SCHOOL
end

DCM.RegisterTheme({
    key = "brutal",
    name = "Brutal",
    description = "Heavy flesh impacts, bone crunches, and blood splatter.",
    mature = true,
    splats = {TEXTURES .. "Splat1", TEXTURES .. "Splat2", TEXTURES .. "Splat3", TEXTURES .. "Splat4"},
    colors = {{0.62, 0.02, 0.02}},
    size = 1,
    drips = {TEXTURES .. "Drip1", TEXTURES .. "Drip2"},
    dripsFrom = "high",
    -- Some splats stay put and drip (author), more at higher intensities.
    run = TEXTURES .. "Run1",
    runChance = {low = 0.25, medium = 0.33, high = 0.45, max = 0.6},
    -- Heal crits: no gore. Warm red and gold droplets of light rising, as a
    -- wound seals.
    heal = {
        splats = {TEXTURES .. "Embers1", TEXTURES .. "Mote1"},
        colors = {{0.95, 0.3, 0.2}, {1, 0.75, 0.3}},
        blend = "ADD",
        size = 0.8,
    },
    -- Dyre's Gore (Dyre's Sounds 1.2.0).
    sounds = {
        crit = {"goreslice", "gorechop", "gorebash"},
        big = {"gorebloody", "goresplat"},
        extra = {"wetsplat", "wetpunch"},
        extraFrom = "medium",
    },
})

-- Variants of Brutal (author, 2026-11-17: "pivot the themes to be variants
-- of Brutal that stylize the baseline effects, instead of being a completely
-- different set ... Brutal is neutral, keeps the default effects looking
-- default. But picking a theme puts me 'in character'"; "effects on me
-- retain the brutal effect. What I'm stylizing is the damage I'm doing").
-- A variant (`variant = true`) draws Brutal's splatter, drips, runs, and
-- school looks for your and your pet's damage, in its own colors, with its
-- own touch (`extraAccent`) and hit effects (`hits`, over DCM.HIT_STYLES);
-- damage on you and others' damage draw Brutal itself (DCM.Look,
-- Effects.lua). Each keeps its own sounds and heal style. Built at the end
-- of this file (Variant).
local function BrutalBase(theme)
    local brutal = themes.brutal
    for _, field in ipairs({"splats", "colors", "size", "drips", "dripsFrom", "run", "runChance"}) do
        if theme[field] == nil then
            theme[field] = brutal[field]
        end
    end
    theme.variant = true
    return theme
end
themes.brutal.variant = true

-- Spellburst (author: "something for mages, warlocks and priests ... doing
-- their thing at range"): Brutal's gore charged with magic, a glow of your
-- spell's school on every crit, a ring for a new record, and stronger,
-- brighter spell hits. 18+ (author: "18+ only"), since it shows Brutal's
-- blood. Crit heals: light rising, holy gold and nature green.
DCM.RegisterTheme(BrutalBase({
    key = "spellburst",
    name = "Spellburst",
    description = "Brutal's gore charged with magic: a glow of your spell's school on every crit, and brighter "
        .. "spell hits.",
    mature = true,
    ring = TEXTURES .. "Ring1",
    heal = {
        splats = {TEXTURES .. "Burst1", TEXTURES .. "Mote1"},
        colors = {{1, 0.92, 0.6}, {0.4, 1, 0.4}},
        blend = "ADD",
        size = 0.8,
        animations = {[TEXTURES .. "Burst1"] = "spin"},
    },
    -- From Dyre's Sounds' own until dedicated magic sounds join it. Its
    -- files (Dyre's Picks) play everywhere; the game's kit sounds only where
    -- Dyre's Sounds says they are Playable (not on Classic Era).
    sounds = {
        crit = {"magical", "fadingslow", "war2magicchimes", "instrumentsbelltrill"},
        big = {"blowswoosh", "war2choir", "instrumentschimeascending"},
        extra = {"teleportvanish", "disappearingswoosh", "impactsbubblesmash"},
        extraFrom = "medium",
    },
}))

-- A color for a crit of this school from the theme's schoolPalette, or nil
-- for the theme's own colors (picked per effect).
function DCM.PaletteColor(theme, school)
    if type(school) ~= "number" or DCM.IsSecret(school) or school <= 0 then
        return nil
    end
    for _, entry in ipairs(theme.schoolPalette) do
        if HasSchool(school, entry.mask) then
            return entry.colors[DCM.random(#entry.colors)]
        end
    end
end

local FEL_GREEN = {0.35, 0.9, 0.15}
local SHADOW = {0.22, 0.08, 0.3}

local FEL_PURPLE, FEL_DUSK, FEL_DARK = {0.38, 0.1, 0.55}, {0.16, 0.05, 0.22}, {0.14, 0.38, 0.05}
local DARK_BLOOD = {0.45, 0.02, 0.05}

-- Fel (author: "a darker, more... mature theme for warlocks ... keep it
-- scary/dark"; then: "Fel is gives the effects from Brutal an evil,
-- demonic tinge, mixing in fel green and purple shades", and "If I choose
-- Fel on my Paladin, Holy is no longer a golden glow/sparkle. It's now a
-- more evil black/purple/fel-green effect"): Brutal's wounds in dark blood,
-- purple, and fel green for every school, cracks creeping from them, a
-- wisp of dark smoke on each crit, and the dark vignette for a new record.
-- 18+ (author: "If we do anything truly demonic, it gets 18+").
DCM.RegisterTheme(BrutalBase({
    key = "fel",
    name = "Fel",
    description = "Brutal's gore with a demonic tinge: dark blood, purple, and fel green for every school, "
        .. "creeping cracks, and dark smoke.",
    mature = true,
    colors = {DARK_BLOOD, DARK_BLOOD, FEL_DUSK, FEL_DARK},
    run = TEXTURES .. "Crack1",
    runGrow = "center",
    vignette = TEXTURES .. "Vignette1",
    -- Heal crits: glowing fel-green wisps drawn upward, no sparkle.
    heal = {
        splats = {TEXTURES .. "Smoke1", TEXTURES .. "Smoke2", TEXTURES .. "Embers1"},
        colors = {FEL_GREEN, {0.6, 1, 0.4}},
        blend = "ADD",
        size = 0.8,
        animations = {
            [TEXTURES .. "Smoke1"] = "spin",
            [TEXTURES .. "Smoke2"] = "spin",
        },
    },
    -- Dyre's Fel Sounds (Dyre's Sounds 1.4.0; author: "Here are some 'Fel
    -- Sounds' for that theme"), files, so they play on Classic Era: a wet
    -- smash, a mud splat, or a heartbeat per crit, the demon growl for a
    -- record, and a heartbeat as the extra (skipped when the crit's own
    -- sound was the heartbeat). fallback: the earlier pools, for an older
    -- Dyre's Sounds without them (the game's kit sounds only where
    -- Playable).
    sounds = {
        crit = {"felwetsmash", "felmudsplat", "felheartbeat"},
        big = {"feldemongrowl"},
        extra = {"felheartbeat"},
        extraFrom = "medium",
        fallback = {
            crit = {"gorebash", "gorechop", "impactslowthud", "impactsstrangeclang", "instrumentssynthbuzz"},
            big = {"bigmonsterroar", "monsterbear"},
            extra = {"orcfury", "instrumentspitchpipedistressed"},
        },
    },
}))

-- Naturalist, for Druids and nature (author: "let's make it more mature and a
-- touch gory, not whimsical"; "Naturalist is the theme name"), a variant of
-- Brutal (author: "Yes, a variant"): physical its claw rakes of two, three,
-- or four scratches, a bite mark, and Brutal's splatter, mixed in every set
-- (author: "make sure it mixes up the base effect (bite, scratches,
-- splatter) ... the bite and scratch direction (and number of scratches)
-- should be random; not uniform"), each turned any way, mirrored at
-- random, and sized a little differently; some grow a run, always straight
-- down the screen (StartRun). Its "Claws only in Cat or Bear form" box
-- (`clawsInForm`, off by default; `formClaws` marks the theme that offers
-- it) keeps the claws to a beast's crits (DCM.FeralCrit), Brutal's splatter
-- otherwise. The other schools: Brutal's in earthy tints (moss, bark,
-- amber, silver), with leaves blowing from a nature crit. Heal crits: vines
-- sprouting and green and gold smoke rising, never flowers. A new record:
-- the vignette in deep green. 18+ like Brutal and Fel.
DCM.RegisterTheme(BrutalBase({
    key = "naturalist",
    name = "Naturalist",
    description = "Brutal's gore gone feral: claws and bites, earthy tints, and leaves torn loose.",
    mature = true,
    splats = {TEXTURES .. "Claw1", TEXTURES .. "Claw2", TEXTURES .. "Claw3", TEXTURES .. "Bite1",
        TEXTURES .. "Splat1", TEXTURES .. "Splat3"},
    colors = {{0.6, 0.02, 0.02}, {0.48, 0.02, 0.02}},
    -- Some marks drip at random (author: "3-4 claw scratches that randomly
    -- drip blood"), a little more often than Brutal's.
    runChance = {low = 0.3, medium = 0.4, high = 0.5, max = 0.65},
    formClaws = true,
    vignette = TEXTURES .. "Vignette2",
    vignetteColor = {0.04, 0.22, 0.04},
    -- Heal crits (author: "no flowers, sprouting vines are fine and/or
    -- green/gold rising smoke"): a vine, or a wisp of green or gold smoke.
    heal = {
        splats = {TEXTURES .. "Vine1", TEXTURES .. "Vine1", TEXTURES .. "Smoke1", TEXTURES .. "Smoke2"},
        colors = {{0.4, 0.75, 0.3}, {0.85, 0.72, 0.3}},
        textureBlend = {[TEXTURES .. "Smoke1"] = "ADD", [TEXTURES .. "Smoke2"] = "ADD"},
        size = 0.8,
        animations = {
            [TEXTURES .. "Smoke1"] = "spin",
            [TEXTURES .. "Smoke2"] = "spin",
        },
    },
    -- Dyre's Cats and Bears, and Dyre's Gore: files, so they play on Classic
    -- Era.
    sounds = {
        crit = {"angrycat", "tigerroar", "goreslice"},
        big = {"bearroar", "monsterbear", "lionroar"},
        extra = {"wetsplat"},
        extraFrom = "medium",
    },
}))

-- Effects by damage school (author: "Physical vs. magic, and each school of
-- magic ... has it's own effect for each theme, with some shared if
-- needed"; then, after play: each theme keeps its own language, and the
-- school adds a tint and an accent, with gore for physical in every theme
-- but Tame). A theme's
-- styles[kind] is a style (a small theme of its own: splats, colors,
-- textureColors, blend, textureBlend, animations, motion, size, drips, run,
-- ring, accent) that reads whatever it does not set from a base theme (Restyle), so
-- styles share; or a function returning one (Spellburst's physical, by the
-- 18+ box). A kind with no style, or an unknown or secret school, draws the
-- theme's own look. Heals keep the theme's heal style; sounds stay the
-- theme's.
DCM.SCHOOL_KINDS = {"physical", "holy", "fire", "nature", "frost", "shadow", "arcane"}
-- A mask with several schools is one kind (author: "no combo, pick one for
-- each"): any magic before physical, in this order.
local KIND_ORDER = {
    {kind = "fire", mask = 4},
    {kind = "frost", mask = 16},
    {kind = "shadow", mask = 32},
    {kind = "arcane", mask = 64},
    {kind = "nature", mask = 8},
    {kind = "holy", mask = 2},
    {kind = "physical", mask = 1},
}

function DCM.SchoolKind(school)
    if type(school) ~= "number" or DCM.IsSecret(school) or school <= 0 then
        return nil
    end
    for _, entry in ipairs(KIND_ORDER) do
        if HasSchool(school, entry.mask) then
            return entry.kind
        end
    end
end

-- A beast's crit (claws and bites in Brutal, and in Naturalist with its box):
-- yours in Cat, Bear, or Dire
-- Bear form (Detect.lua's form cache), or a Hunter's pet's (Hunter pets are
-- beasts; a Warlock's demon is not). Others' crits and crits on you: never.
function DCM.FeralCrit(crit)
    if not crit then
        return false
    end
    if crit.kind == "mine" then
        return DCM.feralForm == true
    end
    return crit.kind == "pet" and DCM.beastPet == true
end

-- The style a crit of this school draws in this theme, and its kind. A theme
-- that offers Random Effects (Tame), with the setting ticked, draws its own
-- look for every school. crit (optional) is DCM.PlayCrit's: a style may
-- depend on whose crit it is (Naturalist's claws).
function DCM.CritStyle(theme, school, crit)
    local kind = DCM.SchoolKind(school)
    if theme.randomEffects and DCM.db and DCM.db.randomEffects then
        return theme, kind
    end
    local style = kind and theme.styles and theme.styles[kind]
    if type(style) == "function" then
        style = style(theme, crit)
    end
    return style or theme, kind
end

local function Restyle(base, fields)
    return setmetatable(fields, {__index = base})
end

local FIRE, FLAME = {1, 0.5, 0.12}, {1, 0.8, 0.3}
local ICE, RIME = {0.55, 0.85, 1}, {0.85, 0.95, 1}
local ARCANE, HOLY_LIGHT = {0.85, 0.45, 1}, {1, 0.92, 0.6}
local function T(name)
    return TEXTURES .. name
end
-- The leaves: maple three times as often as oak or birch.
local LEAVES = {T("Maple1"), T("Maple1"), T("Maple1"), T("Oak1"), T("Birch1")}
local LEAF_TUMBLE = {[T("Maple1")] = "spin", [T("Oak1")] = "spin", [T("Birch1")] = "spin"}

do
    local tame, brutal, spellburst, fel, naturalist = themes.tame, themes.brutal, themes.spellburst, themes.fel,
        themes.naturalist
    -- Tame: never gore. A cartoon pow, little flames, snowflakes, leaves,
    -- small dusky puffs, twinkly stars, gold sparkles.
    tame.styles = {
        physical = Restyle(tame, {splats = {T("Pow1"), T("Pow1"), T("Star1")},
            colors = {{1, 0.9, 0.45}, {1, 0.75, 0.6}}, animations = {[T("Pow1")] = "twinkle", [T("Star1")] = "spin"}}),
        fire = Restyle(tame, {splats = {T("Flame1"), T("Flame1"), T("Sparkle1")},
            colors = {{1, 0.7, 0.45}, {1, 0.85, 0.5}}, textureBlend = {[T("Flame1")] = "ADD"},
            animations = {[T("Flame1")] = "twinkle", [T("Sparkle1")] = "twinkle"}}),
        frost = Restyle(tame, {splats = {T("Snowflake1")}, colors = {{0.75, 0.9, 1}, {0.9, 0.95, 1}},
            animations = {[T("Snowflake1")] = "spin"}}),
        -- Leaves (author: "I'm from MI, so Maple might be better"): maple
        -- most, oak, birch, in autumn pastels, tumbling as they rise.
        nature = Restyle(tame, {splats = LEAVES, colors = {{1, 0.6, 0.55}, {1, 0.75, 0.45}, {1, 0.88, 0.45},
            {0.65, 0.92, 0.55}}, animations = LEAF_TUMBLE}),
        shadow = Restyle(tame, {splats = {T("Smoke1"), T("Smoke2")}, colors = {{0.6, 0.55, 0.75}, {0.5, 0.48, 0.62}},
            size = 0.45, animations = {}}),
        arcane = Restyle(tame, {splats = {T("Star1"), T("Sparkle1")}, colors = {{0.85, 0.7, 1}, {0.75, 0.65, 1}}}),
        holy = Restyle(tame, {splats = {T("Sparkle1"), T("Sparkle1"), T("Star1"), T("Rainbow1")},
            colors = {{1, 0.88, 0.45}, {1, 0.95, 0.7}}}),
    }
    -- Each theme keeps its own language; the school adds a tint and at most
    -- one small accent (author: "Go with 1, keeping the physical-gore
    -- exception in all non-Tame themes"). An accent (`accent`, drawn by
    -- Effects.lua's ShowAccent) is a few small effects of its own: textures,
    -- colors, blend, size, motion, count, and optionally onTop (on the set's
    -- first splat), spread and drift (a blowing cluster), runs (a run grows
    -- from under it), loop (the theme's loop, a tumble), overlay (one more on
    -- the same spot), and after (one more there once the first starts to
    -- fade).
    local function Accent(texture, colors, blend, motion)
        return {textures = {T(texture)}, colors = colors, blend = blend, motion = motion}
    end
    -- Nature's leaves, per theme (author: "For brutal, it should look like
    -- the leaves are wet with blood and splatter on the screen and stick,
    -- maybe slowly smear down. For Tame, and Spellburst, bursts/puffs of
    -- blowing/falling is fine. Fel, make them burn and fall to ash").
    local BLOODY_LEAVES = {textures = {T("Maple1"), T("Maple1"), T("Oak1"), T("Birch1")},
        colors = {{0.5, 0.12, 0.06}, {0.42, 0.24, 0.08}}, size = 0.55, onTop = true, runs = true}
    local function BlowingLeaves(colors, drift)
        return {textures = LEAVES, colors = colors, count = {3, 5}, size = 0.35, spread = 40, drift = drift,
            loop = true}
    end
    -- Brutal: always gore and wounds. Fire charred blood with embers; frost
    -- frozen blood with an ice shard; nature blood-soaked leaves stuck on
    -- the splat, smearing down; shadow black ichor with a wisp of smoke;
    -- arcane blood with a violet crackle; holy seared wounds with a light
    -- flare.
    local function Wound(colors, accent)
        return Restyle(brutal, {colors = colors, accent = accent})
    end
    brutal.styles = {
        fire = Wound({{0.32, 0.06, 0.02}, {0.45, 0.09, 0.02}}, Accent("Embers1", {FIRE, FLAME}, "ADD", "float")),
        frost = Wound({{0.42, 0.12, 0.25}, {0.33, 0.16, 0.36}}, Accent("Shard1", {ICE, RIME})),
        nature = Wound({{0.62, 0.02, 0.02}}, BLOODY_LEAVES),
        shadow = Wound({{0.08, 0.02, 0.08}, {0.14, 0.03, 0.12}}, Accent("Smoke2", {SHADOW})),
        arcane = Wound({{0.62, 0.02, 0.02}}, Accent("Crack1", {ARCANE}, "ADD")),
        holy = Wound({{0.45, 0.12, 0.05}}, Accent("Burst1", {HOLY_LIGHT}, "ADD")),
    }
    -- A beast's physical crit, shared by Brutal (always) and Naturalist (its
    -- "Claws only in Cat or Bear form" box): claw rakes, a bite, and
    -- splatter mixed, in the base theme's colors and run chances (author:
    -- "Add the form check to the Brutal theme and use claw/bite/splat there
    -- too, because, why not").
    local CLAW_MIX = {T("Claw1"), T("Claw2"), T("Claw3"), T("Bite1"), T("Splat1"), T("Splat3")}
    local function Beast(base)
        return Restyle(base, {splats = CLAW_MIX})
    end
    local brutalBeast = Beast(brutal)
    brutal.beast = brutalBeast
    brutal.styles.physical = function(_, crit)
        if DCM.FeralCrit(crit) then
            return brutalBeast
        end
        return brutal
    end
    -- Tame's nature: its rising leaves, and a puff of leaves blowing out and
    -- drifting down.
    tame.styles.nature.accent = BlowingLeaves(tame.styles.nature.colors, "down")
    -- The variants (see BrutalBase): each school is Brutal's look, in the
    -- variant's colors for its splats (`colors[kind]`, else Brutal's) and
    -- its accent (`accents[kind]`, overlay and after too), plus the
    -- variant's own touch (`extra[kind]` or `extra.all`), and its run.
    local function Recolor(accent, colors)
        if not accent or not colors then
            return accent
        end
        local copy = Restyle(accent, {colors = colors})
        if accent.overlay then
            copy.overlay = Restyle(accent.overlay, {colors = colors})
        end
        if accent.after then
            copy.after = Restyle(accent.after, {colors = colors})
        end
        return copy
    end
    local function Variant(theme, spec)
        local function Style(base, kind)
            return Restyle(base, {colors = spec.colors and spec.colors[kind], schoolColors = false,
                schoolPalette = false, accent = Recolor(base.accent, spec.accents and spec.accents[kind]),
                extraAccent = spec.extra and (spec.extra[kind] or spec.extra.all) or false,
                run = theme.run, runGrow = theme.runGrow or false, ring = theme.ring or false})
        end
        theme.styles = {}
        for _, kind in ipairs(DCM.SCHOOL_KINDS) do
            if kind ~= "physical" then
                theme.styles[kind] = Style(brutal.styles[kind] or brutal, kind)
            end
        end
        local plain, beast = Style(brutal, "physical"), Style(brutalBeast, "physical")
        theme.styles.physical = spec.physical or function(_, crit)
            return DCM.FeralCrit(crit) and beast or plain
        end
        theme.hitStyles = {}
        for kind, fields in pairs(spec.hits or {}) do
            theme.hitStyles[kind] = Restyle(DCM.HIT_STYLES[kind], fields)
        end
    end
    -- Spellburst: Brutal's own looks, a glow and a ring in the school's
    -- color on top, and spell hits 40% denser with a 30% bigger flash.
    local function Glow(color)
        return {textures = {T("Burst1"), T("Burst2")}, colors = {color}, blend = "ADD", size = 0.9, onTop = true}
    end
    local CHARGED = {emphasis = 1.4, flashScale = 1.3}
    Variant(spellburst, {
        extra = {physical = Glow({1, 1, 1}), fire = Glow(FIRE), frost = Glow(ICE), shadow = Glow({0.6, 0.3, 0.95}),
            arcane = Glow(ARCANE), nature = Glow({0.4, 1, 0.4}), holy = Glow(HOLY_LIGHT)},
        hits = {fire = CHARGED, frost = CHARGED, shadow = CHARGED, arcane = CHARGED, nature = CHARGED,
            holy = CHARGED},
    })
    -- Fel: every school dark blood, purple, and fel green; its accents too;
    -- a wisp of dark smoke on each crit; cracks creep from the wounds.
    local FEL_LIGHT = {FEL_GREEN, {0.6, 0.3, 0.95}}
    Variant(fel, {
        colors = {physical = fel.colors, fire = {FEL_DARK, {0.2, 0.5, 0.06}, FEL_DUSK},
            frost = {{0.3, 0.35, 0.5}, FEL_DUSK}, shadow = {{0.06, 0.04, 0.07}, FEL_DUSK},
            arcane = {FEL_PURPLE, FEL_DUSK}, nature = {FEL_DARK, {0.2, 0.25, 0.05}},
            holy = {FEL_DUSK, {0.06, 0.04, 0.07}, FEL_DARK}},
        accents = {fire = FEL_LIGHT, frost = {{0.7, 0.95, 0.7}, {0.75, 0.65, 1}},
            nature = {{0.2, 0.3, 0.05}, {0.25, 0.08, 0.3}}, shadow = {{0.06, 0.04, 0.07}, FEL_DUSK},
            arcane = FEL_LIGHT, holy = FEL_LIGHT},
        extra = {all = {textures = {T("Smoke1"), T("Smoke2")}, colors = {FEL_DUSK, FEL_DARK}, size = 0.6,
            motion = "float", onTop = true}},
        hits = {
            physical = {colors = {DARK_BLOOD, FEL_DUSK, FEL_DARK}},
            frost = {colors = {{0.65, 0.95, 0.6}, {0.7, 0.6, 0.95}, {0.85, 1, 0.8}}},
            fire = {colors = {{0.45, 1, 0.2}, {0.25, 0.85, 0.1}, {0.6, 1, 0.35}},
                textureColors = {[T("Burst2")] = {0.7, 1, 0.45}}},
            arcane = {colors = {{0.6, 0.3, 1}, {0.4, 1, 0.3}}},
            shadow = {colors = {{0.16, 0.32, 0.06}, {0.06, 0.1, 0.03}, FEL_DUSK}},
            nature = {colors = {{0.35, 0.85, 0.1}, {0.25, 0.5, 0.05}}},
            -- Holy turns unholy (author: "Holy is no longer a golden
            -- glow/sparkle. It's now a more evil black/purple/fel-green").
            holy = {textures = {T("Smoke1"), T("Smoke2"), T("Sparkle1")}, blend = "BLEND",
                colors = {{0.3, 0.08, 0.45}, FEL_DARK, {0.06, 0.04, 0.07}}, motion = "smoke",
                flash = {texture = T("Smoke1"), blend = "BLEND", size = 2.6}},
            heal = {colors = {{0.4, 1, 0.15}, {0.55, 0.3, 0.85}}},
        },
    })
    -- Naturalist: claws for physical (its own mix; with its box, only for a
    -- beast's crit), earthy tints for the rest, leaves blowing from nature.
    local MOSS, BARK, AMBER = {0.3, 0.45, 0.1}, {0.3, 0.18, 0.08}, {0.75, 0.5, 0.12}
    local SILVER = {0.8, 0.83, 0.9}
    naturalist.beast = naturalist
    Variant(naturalist, {
        physical = function(_, crit)
            if DCM.db and DCM.db.clawsInForm and not DCM.FeralCrit(crit) then
                return brutal
            end
            return naturalist
        end,
        colors = {fire = {AMBER, {0.35, 0.12, 0.03}}, frost = {{0.45, 0.55, 0.4}, {0.3, 0.4, 0.3}},
            shadow = {{0.1, 0.08, 0.03}, {0.18, 0.12, 0.05}}, arcane = {SILVER, {0.5, 0.55, 0.4}},
            nature = {MOSS, {0.4, 0.6, 0.15}}, holy = {AMBER, {0.85, 0.75, 0.35}}},
        accents = {fire = {AMBER, {1, 0.7, 0.2}}, frost = {{0.75, 0.9, 0.8}}, nature = {MOSS, BARK},
            shadow = {BARK, {0.1, 0.1, 0.05}}, arcane = {SILVER}, holy = {AMBER, {1, 0.9, 0.5}}},
        extra = {nature = BlowingLeaves({MOSS, {0.4, 0.6, 0.15}, BARK}, "down")},
        hits = {
            nature = {textures = {T("Maple1"), T("Maple1"), T("Oak1"), T("Birch1"), T("Insect1")},
                colors = {MOSS, {0.4, 0.6, 0.15}, {0.55, 0.4, 0.12}}, blend = "BLEND", size = 0.5, count = 1.5,
                motion = "flurry"},
            fire = {colors = {AMBER, {1, 0.6, 0.15}}, textureColors = {[T("Burst2")] = {1, 0.8, 0.35}}},
            frost = {colors = {{0.8, 0.95, 0.85}, {0.6, 0.8, 0.7}}},
            arcane = {textures = {T("Firework1"), T("Sparkle1")}, colors = {SILVER, {0.7, 0.75, 0.85}}},
            shadow = {colors = {{0.12, 0.1, 0.04}, {0.2, 0.15, 0.06}}},
            holy = {colors = {AMBER, {1, 0.85, 0.4}}},
            heal = {colors = {{0.4, 0.85, 0.25}, {0.85, 0.75, 0.3}}},
        },
    })
end

-- Dyre's Sounds, contract 1, else nil.
local function Library()
    local library = rawget(_G, "DyresSounds")
    if type(library) ~= "table" or type(library.RequireContract) ~= "function" then
        return nil
    end
    library = library.RequireContract(1)
    if type(library) ~= "table" or type(library.Play) ~= "function" then
        return nil
    end
    return library
end

-- In the installed Dyre's Sounds and playable on this client (Playable,
-- Dyre's Sounds 1.2.0; an older one plays all it has).
local function Installed(library, key)
    if library == nil or type(library.Resolve) ~= "function" or library.Resolve(key) == nil then
        return false
    end
    return type(library.Playable) ~= "function" or library.Playable(key) == true
end

-- A theme's pool for an event. The hook for crit sizes (author: "we could
-- pick which to play for high/med/low crit ranges, random for now"): a pool
-- could become {low = {...}, high = {...}} chosen by the amount here.
local function Pool(theme, event)
    return theme.sounds[event] or {}
end

-- The keys of a list this Dyre's Sounds has and plays here.
local function Playable(library, list)
    local pool = {}
    for _, key in ipairs(list or {}) do
        if Installed(library, key) then
            pool[#pool + 1] = key
        end
    end
    return pool
end

local lastPicks = {}

-- The sound for an event: the player's own pick, else one of the theme's
-- pool at random, never the same twice in a row. Keys the installed Dyre's
-- Sounds lacks are left out; with none left, the theme's other events' keys,
-- else FALLBACK_SOUND.
function DCM.PickSound(event)
    local own = DCM.db.soundPicks[event]
    if own.on and own.key then
        return own.key
    end
    local library, theme = Library(), DCM.Theme()
    local pool = Playable(library, Pool(theme, event))
    -- An older Dyre's Sounds without the theme's keys: its fallback pool.
    if #pool == 0 and theme.sounds.fallback then
        pool = Playable(library, theme.sounds.fallback[event])
    end
    if #pool == 0 then
        for _, other in ipairs(DCM.SOUND_EVENTS) do
            for _, key in ipairs(Pool(theme, other)) do
                if Installed(library, key) then
                    pool[#pool + 1] = key
                end
            end
        end
    end
    if #pool == 0 then
        return FALLBACK_SOUND
    end
    local choices = pool
    if #pool > 1 and lastPicks[event] then
        choices = {}
        for _, key in ipairs(pool) do
            if key ~= lastPicks[event] then
                choices[#choices + 1] = key
            end
        end
    end
    local key = choices[DCM.random(#choices)]
    lastPicks[event] = key
    return key
end

-- The first of the theme's pool: what a sound picker shows before a pick.
function DCM.ThemeSound(event)
    return Pool(DCM.Theme(), event)[1] or FALLBACK_SOUND
end

-- Back to the theme's pools (the Sounds section's reset).
function DCM.ResetSounds()
    for _, event in ipairs(DCM.SOUND_EVENTS) do
        DCM.db.soundPicks[event].on = false
    end
    DCM.Report("Sounds are back to " .. DCM.Theme().name .. "'s, picked at random.")
    if type(DCM.RefreshOptions) == "function" then
        DCM.RefreshOptions()
    end
end

DCM.SoundLibrary = Library

-- Plays one sound key through Dyre's Sounds, on the SFX channel so the
-- game's sound effects volume sets it (DCM never changes a volume); a voice
-- says the event's words. Without the library, says so once.
function DCM.PlaySound(key, event)
    local library = DCM.SoundLibrary()
    if not library then
        if not DCM.saidSoundsMissing then
            DCM.saidSoundsMissing = true
            DCM.Report(SOUNDS_MISSING)
        end
        return false
    end
    return library.Play(key, DCM.SOUND_SPEECH[event or "crit"], "SFX") == true
end
