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
--   texture; runGrow "center": the run spreads from the splat's spot;
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
--   library plays it, and DCM ships no sound.
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

-- Whether a theme's touch (drips, the squelch) is on at this intensity.
function DCM.ThemeFrom(fromKey, intensityIndex)
    return fromKey ~= nil and intensityIndex >= DCM.INTENSITY_INDEX[fromKey]
end

DCM.RegisterTheme({
    key = "tame",
    name = "Tame",
    description = "Butterflies, stars, and sparkles in soft pastels, with light shimmers.",
    splats = {TEXTURES .. "Butterfly1", TEXTURES .. "Butterfly2", TEXTURES .. "Star1", TEXTURES .. "Sparkle1"},
    -- Pink, lavender, mint, butter.
    colors = {{1, 0.72, 0.84}, {0.8, 0.72, 1}, {0.68, 0.95, 0.82}, {1, 0.93, 0.62}},
    size = 0.6,
    motion = "float",
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
-- is read; shadow is purple, since black adds no light. An unknown or secret
-- school: arcane white.
local SCHOOL_COLORS = {
    {mask = 4, color = {1, 0.5, 0.12}},
    {mask = 16, color = {0.45, 0.8, 1}},
    {mask = 64, color = {0.9, 0.45, 1}},
    {mask = 32, color = {0.6, 0.3, 0.95}},
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

-- For casters and healers (author: "something for mages, warlocks and
-- priests ... doing their thing at range"): bursts of light tinted by spell
-- school, motes that rise from Medium, a ring from High and for a new
-- record; crit heals show too, rising in holy or nature light. Original
-- textures (scripts/build_splatters.py), drawn additively.
DCM.RegisterTheme({
    key = "spellburst",
    name = "Spellburst",
    description = "Bursts of light in your spell's school: fire, frost, arcane, shadow, nature, holy.",
    splats = {TEXTURES .. "Burst1", TEXTURES .. "Burst2"},
    colors = {UNKNOWN_SCHOOL},
    schoolColors = true,
    blend = "ADD",
    heals = true,
    size = 0.9,
    drips = {TEXTURES .. "Mote1"},
    dripsFrom = "medium",
    dripMotion = "float",
    ring = TEXTURES .. "Ring1",
    ringFrom = "high",
    animations = {
        [TEXTURES .. "Burst1"] = "spin",
        [TEXTURES .. "Burst2"] = "twinkle",
        [TEXTURES .. "Ring1"] = "twinkle",
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
})

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
local HELLFIRE = {0.95, 0.3, 0.08}

-- Dark and scary, not gory (author: "a darker, more... mature theme for
-- warlocks ... No magic twinkles or sparkles, keep it scary/dark"; working
-- name, one string to rename): smoke that curls as it rises and dissolves,
-- falling embers or ash from Medium, cracks that spread from where it
-- landed, and a dark vignette around the screen for a new record. Fel
-- green, shadow purple-black, and hellfire; shadow crits are shadow, fire
-- crits hellfire or fel. Original textures (scripts/build_splatters.py).
DCM.RegisterTheme({
    key = "fel",
    name = "Fel",
    description = "Dark smoke, falling embers, and creeping cracks in fel green, shadow, and hellfire.",
    -- Demonic, so 18+ like Brutal (author: "If we do anything truly demonic,
    -- it gets 18+").
    mature = true,
    splats = {TEXTURES .. "Smoke1", TEXTURES .. "Smoke2"},
    colors = {FEL_GREEN, SHADOW, HELLFIRE},
    schoolPalette = {
        {mask = 32, colors = {SHADOW}},
        {mask = 4, colors = {HELLFIRE, FEL_GREEN}},
    },
    size = 1,
    motion = "float",
    drips = {TEXTURES .. "Embers1"},
    dripsFrom = "medium",
    textureBlend = {[TEXTURES .. "Embers1"] = "ADD"},
    run = TEXTURES .. "Crack1",
    runGrow = "center",
    runChance = {low = 0.2, medium = 0.3, high = 0.4, max = 0.5},
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
    -- The smoke curls: a slow turn.
    animations = {
        [TEXTURES .. "Smoke1"] = "spin",
        [TEXTURES .. "Smoke2"] = "spin",
    },
    -- Placeholders, the darkest of Dyre's Sounds' own, until the author's
    -- demonic, decay, or hellfire sounds join it: swap them here. Its files
    -- (Dyre's Gore, Aggression, Bears) play everywhere; the game's kit
    -- sounds only where Playable.
    sounds = {
        crit = {"gorebash", "gorechop", "impactslowthud", "impactsstrangeclang", "instrumentssynthbuzz"},
        big = {"bigmonsterroar", "monsterbear"},
        extra = {"orcfury", "instrumentspitchpipedistressed"},
        extraFrom = "medium",
    },
})

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
    local pool = {}
    for _, key in ipairs(Pool(theme, event)) do
        if Installed(library, key) then
            pool[#pool + 1] = key
        end
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
