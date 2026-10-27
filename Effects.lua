local _, DCM = ...

-- The mayhem itself: the theme's sounds and splatters on the screen, as much
-- as the intensity says. Splatters are textures on one full-screen frame in
-- the BACKGROUND strata, under the action bars and unit frames, that never
-- takes the mouse. Each one pops in, holds, and fades with an AnimationGroup
-- (the engine runs it; no OnUpdate), then goes back to the pool.
--
-- Some move while they hold (author: "make some of the splatters stay in
-- place and drip (or animate - rotate stars or fluttering wings)"), as the
-- theme's data says:
--   - a looping animation per texture (theme.animations): "spin" (a slow
--     full turn), "flutter" (wings pinch and open), "twinkle" (a swell and
--     back), each its own looping AnimationGroup on the splat, made once per
--     splat and kind, stopped when the splat goes;
--   - a run (theme.run, theme.runChance by intensity): the splat stays put
--     and a trickle grows down from under it (a Scale from its top edge),
--     fading with it.
-- At most MAX_MOVING splats move at once; past that they show still.
local SPLAT_SIZE = 256
local MAX_SPLATS = 32
local POP_SECONDS = 0.08
local POP_FROM = 0.55
-- Drips slide down while they fade, and floating effects (Tame's
-- butterflies and stars) rise, in UIParent units.
local DRIP_SLIDE = 48
local FLOAT_RISE = 40
-- Floating effects only tilt a little, never upside down.
local FLOAT_TILT = 0.4
-- A crit this soon after the last one adds one splatter, not a full set:
-- an area spell crits many targets at once.
local BURST_GAP = 0.15
local SOUND_GAP = 0.1
-- A new record's splatters are this much bigger.
local BIG_SIZE = 1.35
local SIZE_JITTER = 0.2
-- Your own crits land outside this middle part of the screen, so you can
-- still see what you are hitting; crits on you land in this band at the edges.
local CLEAR_MIDDLE = 0.22
local EDGE_BAND = 0.14
local PLACE_TRIES = 6
local MAX_MOVING = 12
-- Others' crits (kind "others": anyone's on your target or a nearby enemy)
-- are trimmed first, so a raid pull cannot flood the screen: at most
-- OTHERS_BURSTS (by intensity) in any OTHERS_WINDOW seconds, one still
-- effect each (no drips, runs, rings, or loops), their sound under its own
-- gap and never over yours, and never into the last OWN_RESERVE pool slots.
-- Your crits and crits on you always go through.
local OTHERS_WINDOW = 0.5
local OTHERS_BURSTS = {low = 2, medium = 3, high = 4, max = 6}
local OWN_RESERVE = 8
-- /dcm test's schools in turn: fire, frost, arcane, shadow, nature, holy.
local TEST_SCHOOLS = {4, 16, 64, 32, 8, 2}
local SPIN_SECONDS = 6
local FLUTTER_SECONDS = 0.14
local FLUTTER_PINCH = 0.55
local TWINKLE_SECONDS = 0.35
local TWINKLE_GROW = 1.3
-- A run: its size against its splat's, how far below the splat's center it
-- starts, and how short it starts before growing to full length.
local RUN_SIZE = 0.9
local RUN_DROP = 0.12
local RUN_START = 0.05
-- Fel's vignette: seconds to darken, then to fade at 100% "Stays on screen".
local VIGNETTE_IN = 0.35
local VIGNETTE_FADE = 3

-- math.random, replaced by the tests.
DCM.random = math.random

local overlay
local free, active = {}, {}
local lastSplat, lastSound = -math.huge, -math.huge
local lastOthersSound = -math.huge
local othersTimes = {}
local moving = 0

local function Now()
    return GetTime()
end

-- Stops what moves with a splat: its loop and its run.
local function Release(splat)
    if splat.loop then
        splat.loop:Stop()
        splat.loop = nil
        moving = moving - 1
    end
    if splat.running then
        splat.run.group:Stop()
        splat.run:Hide()
        splat.running = false
        moving = moving - 1
    end
end

local function Finish(splat)
    Release(splat)
    splat:Hide()
    for index, other in ipairs(active) do
        if other == splat then
            table.remove(active, index)
            break
        end
    end
    free[#free + 1] = splat
end

local function NewSplat()
    local splat = overlay:CreateTexture(nil, "ARTWORK")
    splat:Hide()
    local group = splat:CreateAnimationGroup()
    splat.pop = group:CreateAnimation("Scale")
    splat.pop:SetDuration(POP_SECONDS)
    if type(splat.pop.SetScaleFrom) == "function" then
        splat.pop:SetScaleFrom(POP_FROM, POP_FROM)
        splat.pop:SetScaleTo(1, 1)
    end
    splat.fade = group:CreateAnimation("Alpha")
    splat.fade:SetFromAlpha(1)
    splat.fade:SetToAlpha(0)
    splat.slide = group:CreateAnimation("Translation")
    group:SetScript("OnFinished", function() Finish(splat) end)
    splat.group = group
    return splat
end

-- A splatter from the pool; when all are on screen, the oldest goes.
local function TakeSplat()
    local splat = table.remove(free)
    if not splat and #active >= MAX_SPLATS then
        splat = table.remove(active, 1)
        splat.group:Stop()
        Release(splat)
    end
    splat = splat or NewSplat()
    active[#active + 1] = splat
    return splat
end

local function Between(low, high)
    return low + (high - low) * DCM.random()
end

-- The splat's looping group for one kind, made the first time.
local function LoopGroup(splat, kind)
    splat.loops = splat.loops or {}
    local group = splat.loops[kind]
    if group then
        return group
    end
    group = splat:CreateAnimationGroup()
    if kind == "spin" then
        group.spin = group:CreateAnimation("Rotation")
        group.spin:SetDuration(SPIN_SECONDS)
        group:SetLooping("REPEAT")
    elseif kind == "flutter" then
        local pinch = group:CreateAnimation("Scale")
        pinch:SetScaleFrom(1, 1)
        pinch:SetScaleTo(FLUTTER_PINCH, 1)
        pinch:SetDuration(FLUTTER_SECONDS)
        group:SetLooping("BOUNCE")
    else
        local swell = group:CreateAnimation("Scale")
        swell:SetScaleFrom(1, 1)
        swell:SetScaleTo(TWINKLE_GROW, TWINKLE_GROW)
        swell:SetDuration(TWINKLE_SECONDS)
        group:SetLooping("BOUNCE")
    end
    splat.loops[kind] = group
    return group
end

-- The splat's run, made the first time: under the splat, growing from its
-- top edge, then fading.
local function Run(splat)
    if splat.run then
        return splat.run
    end
    local run = overlay:CreateTexture(nil, "ARTWORK", nil, -1)
    run:Hide()
    local group = run:CreateAnimationGroup()
    run.grow = group:CreateAnimation("Scale")
    run.grow:SetOrigin("TOP", 0, 0)
    run.grow:SetScaleFrom(1, RUN_START)
    run.grow:SetScaleTo(1, 1)
    run.fade = group:CreateAnimation("Alpha")
    run.fade:SetFromAlpha(1)
    run.fade:SetToAlpha(0)
    run.group = group
    splat.run = run
    return run
end

local function StartLoop(splat, kind)
    local group = LoopGroup(splat, kind)
    if kind == "spin" then
        -- Either way round.
        group.spin:SetDegrees(DCM.random(2) == 1 and 360 or -360)
    end
    group:Play()
    splat.loop = group
    moving = moving + 1
end

-- A run grows down from under its splat (Brutal's trickle); with the theme's
-- runGrow "center" it spreads out from the splat's spot instead (Fel's
-- cracks), placed on the overlay, since its splat may drift away.
local function StartRun(splat, theme, color, size, hold, fade, x, y)
    local run = Run(splat)
    run:SetTexture(theme.run)
    run:SetVertexColor(color[1], color[2], color[3])
    run:SetBlendMode("BLEND")
    -- Always straight down the screen, whatever its splat's turn or mirror
    -- (author: "the direction of the drips is always down"): the anchor is
    -- the splat's center, which a turn does not move.
    if type(run.SetRotation) == "function" then
        run:SetRotation(0)
    end
    run:SetTexCoord(0, 1, 0, 1)
    run:SetSize(size * RUN_SIZE, size * RUN_SIZE)
    run:ClearAllPoints()
    if theme.runGrow == "center" then
        run:SetPoint("CENTER", overlay, "BOTTOMLEFT", x, y)
        run.grow:SetOrigin("CENTER", 0, 0)
        run.grow:SetScaleFrom(RUN_START, RUN_START)
    else
        run:SetPoint("TOP", splat, "CENTER", 0, -size * RUN_DROP)
        run.grow:SetOrigin("TOP", 0, 0)
        run.grow:SetScaleFrom(1, RUN_START)
    end
    run:SetAlpha(1)
    -- It grows while the splat holds, then fades with it.
    run.grow:SetDuration(hold)
    run.fade:SetStartDelay(hold)
    run.fade:SetDuration(fade)
    run:Show()
    run.group:Play()
    splat.running = true
    moving = moving + 1
end

-- A spot in UIParent units from its bottom left, outside the clear middle;
-- for crits on you, in a band along one edge.
local function Spot(width, height, taken)
    if taken then
        local side = DCM.random(4)
        if side == 1 then
            return Between(0, EDGE_BAND) * width, Between(0, 1) * height
        elseif side == 2 then
            return Between(1 - EDGE_BAND, 1) * width, Between(0, 1) * height
        elseif side == 3 then
            return Between(0, 1) * width, Between(0, EDGE_BAND) * height
        end
        return Between(0, 1) * width, Between(1 - EDGE_BAND, 1) * height
    end
    local x, y
    for _ = 1, PLACE_TRIES do
        x, y = Between(0.06, 0.94), Between(0.08, 0.92)
        if math.abs(x - 0.5) > CLEAR_MIDDLE or math.abs(y - 0.5) > CLEAR_MIDDLE then
            break
        end
    end
    return x * width, y * height
end

-- motion: "drip" (slides down, never turned), "float" (butterflies: rise,
-- only tilted), or nil (a splatter, turned any way).
-- opts (accents): at {x, y} (a spot instead of a random one), scale (of
-- the size), slide {x, y} (instead of the motion's, any turn), blend, and
-- layer (the ARTWORK sublevel: accents sit on top of the set). Returns the
-- spot and size.
local function ShowSplat(intensity, theme, texture, motion, big, taken, runs, color, still, opts)
    opts = opts or {}
    local splat = TakeSplat()
    splat.group:Stop()
    local size = SPLAT_SIZE * intensity.size * (theme.size or 1) * (big and BIG_SIZE or 1)
        * Between(1 - SIZE_JITTER, 1 + SIZE_JITTER) * (opts.scale or 1)
    -- A texture may have colors of its own (Brutal's scorch marks and rime).
    local colors = theme.textureColors and theme.textureColors[texture] or theme.colors
    color = theme.textureColors and theme.textureColors[texture] and colors[DCM.random(#colors)]
        or color or colors[DCM.random(#colors)]
    splat:SetTexture(texture)
    -- Glows (Spellburst, Fel's embers) add light; the pooled texture is set
    -- every time.
    splat:SetBlendMode(opts.blend or theme.textureBlend and theme.textureBlend[texture] or theme.blend or "BLEND")
    splat:SetDrawLayer("ARTWORK", opts.layer or 0)
    -- A pre-colored texture (Tame's rainbow) is drawn in its own colors.
    if theme.untinted and theme.untinted[texture] then
        splat:SetVertexColor(1, 1, 1)
    else
        splat:SetVertexColor(color[1], color[2], color[3])
    end
    splat:SetSize(size, size)
    -- A random turn and mirror, so four textures never look like four.
    if type(splat.SetRotation) == "function" then
        if opts.slide then
            splat:SetRotation(Between(0, 2 * math.pi))
        elseif motion == "float" then
            splat:SetRotation(Between(-FLOAT_TILT, FLOAT_TILT))
        elseif motion == "drip" then
            splat:SetRotation(0)
        else
            splat:SetRotation(Between(0, 2 * math.pi))
        end
    end
    if DCM.random(2) == 1 then
        splat:SetTexCoord(1, 0, 0, 1)
    else
        splat:SetTexCoord(0, 1, 0, 1)
    end
    local x, y
    if opts.at then
        x, y = opts.at[1], opts.at[2]
    else
        x, y = Spot(overlay:GetWidth(), overlay:GetHeight(), taken)
    end
    splat:ClearAllPoints()
    splat:SetPoint("CENTER", overlay, "BOTTOMLEFT", x, y)
    splat:SetAlpha(1)
    -- "Stays on screen" scales the intensity's hold and fade together.
    local stay = DCM.db.stay / 100
    local hold, fadeSeconds = intensity.hold * stay, intensity.fade * stay
    splat.fade:SetStartDelay(hold)
    splat.fade:SetDuration(fadeSeconds)
    if opts.slide then
        splat.slide:SetOffset(opts.slide[1], opts.slide[2])
    else
        splat.slide:SetOffset(0, motion == "drip" and -DRIP_SLIDE or motion == "float" and FLOAT_RISE or 0)
    end
    splat.slide:SetDuration(hold + fadeSeconds)
    splat:Show()
    splat.group:Play()
    -- What moves while it holds, within the cap: a run (a splat that stays
    -- put, or one whose run spreads from where it landed), and a loop.
    if runs and moving < MAX_MOVING and motion ~= "drip" and (motion == nil or theme.runGrow == "center") then
        StartRun(splat, theme, color, size, hold, fadeSeconds, x, y)
    end
    if still then
        return x, y, size
    end
    local loop = theme.animations and theme.animations[texture]
    if loop and moving < MAX_MOVING then
        StartLoop(splat, loop)
    end
    return x, y, size
end

local function Pick(list)
    return list[DCM.random(#list)]
end

-- Bumped by ClearEffects, so an accent's later part (Fel's ash) scheduled
-- before a clear never shows.
local generation = 0
-- How far a blowing cluster drifts, in UIParent units.
local DRIFT = 50

-- A school's accent (Themes.lua `accent`): one or a few small, still effects
-- of their own textures and colors. onTop: on the set's first splat; spread:
-- scattered that far around it, drifting outward (drift "down" or "up");
-- runs: a run grows from under it (Brutal's smear); loop: the theme's loop
-- for it (a leaf's tumble); overlay: one more on the same spot (a flame
-- lick); after: one more on the same spot once delay (of the hold) has
-- passed, as the first starts to fade (ash).
local function ShowAccent(intensity, theme, accent, taken, base)
    local count = accent.count or 1
    if type(count) == "table" then
        count = count[1] + DCM.random(count[2] - count[1] + 1) - 1
    end
    for _ = 1, count do
        local at, slide
        if base and accent.onTop then
            at = {base[1], base[2]}
        elseif base and accent.spread then
            local dx, dy = Between(-accent.spread, accent.spread), Between(-accent.spread, accent.spread)
            at = {base[1] + dx, base[2] + dy}
            local out = dx >= 0 and 1 or -1
            slide = {out * Between(0.5, 1) * DRIFT, (accent.drift == "up" and 1 or -1) * DRIFT}
        end
        local x, y, size = ShowSplat(intensity, theme, Pick(accent.textures), accent.motion, false, taken,
            accent.runs, Pick(accent.colors), not accent.loop,
            {at = at, scale = accent.size, slide = slide, blend = accent.blend or "BLEND", layer = 2})
        local extra = accent.overlay
        if extra then
            ShowSplat(intensity, theme, Pick(extra.textures), extra.motion, false, taken, false, Pick(extra.colors),
                true, {at = {x, y}, scale = (extra.size or 1) * size / (SPLAT_SIZE * intensity.size
                    * (theme.size or 1)), blend = extra.blend, layer = 3})
        end
        local later = accent.after
        if later and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            local when = generation
            C_Timer.After(intensity.hold * DCM.db.stay / 100 * (later.delay or 0.6), function()
                if when == generation then
                    ShowSplat(intensity, theme, Pick(later.textures), later.motion, false, taken, false,
                        Pick(later.colors), true, {at = {x, y}, scale = later.size, blend = later.blend, layer = 3})
                end
            end)
        end
    end
end

-- crit: as PlayCrit's. A theme with school colors tints every effect of the
-- crit by its spell school; heals (where the theme shows them) all rise.
local function Splatter(theme, intensity, crit)
    local big, taken = crit.big, crit.kind == "taken"
    local color = theme.schoolColors and DCM.SchoolColor(theme, crit.school, crit.heal)
        or theme.schoolPalette and DCM.PaletteColor(theme, crit.school)
    if crit.kind == "others" then
        -- One still effect, and none when the pool is down to your reserve.
        if #active < MAX_SPLATS - OWN_RESERVE then
            ShowSplat(intensity, theme, Pick(theme.splats), theme.motion, false, false, false, color, true)
        end
        return
    end
    local count = intensity.splats
    if Now() - lastSplat < BURST_GAP then
        count = 1
    end
    lastSplat = Now()
    if big then
        count = count + 1
    end
    local drips = theme.drips and DCM.ThemeFrom(theme.dripsFrom, DCM.IntensityIndex())
    local runChance = theme.run and theme.runChance and theme.runChance[intensity.key] or 0
    -- A ring closes the set for a new record, and from the theme's intensity.
    local ring = theme.ring and (big or DCM.ThemeFrom(theme.ringFrom, DCM.IntensityIndex()))
    local base
    for index = 1, count do
        -- One effect in each set drips (Brutal) or rises (Spellburst's motes),
        -- where the theme has them at this intensity.
        local drip = drips and index == 1
        local texture = Pick(drip and theme.drips or theme.splats)
        local motion = drip and (theme.dripMotion or "drip") or theme.motion
        if ring and index == count and count > 1 then
            texture, motion = theme.ring, nil
        end
        if crit.heal then
            motion = "float"
        end
        local x, y = ShowSplat(intensity, theme, texture, motion, big, taken,
            not crit.heal and DCM.random() < runChance, color)
        base = base or {x, y}
    end
    if theme.accent and not crit.heal then
        ShowAccent(intensity, theme, theme.accent, taken, base)
    end
end

-- Others' crits: the theme's crit sound only, never within SOUND_GAP of any
-- sound, and never holding up yours (yours keep their own gap).
local function OthersSound()
    if Now() - lastOthersSound < SOUND_GAP or Now() - lastSound < SOUND_GAP then
        return
    end
    lastOthersSound = Now()
    DCM.PlaySound(DCM.PickSound("crit"), "crit")
end

-- Whether another one of others' crits may play now (OTHERS_BURSTS per
-- OTHERS_WINDOW at this intensity); counts it when it may.
local function OthersAllowed(intensity)
    local now, kept = Now(), {}
    for _, at in ipairs(othersTimes) do
        if now - at < OTHERS_WINDOW then
            kept[#kept + 1] = at
        end
    end
    othersTimes = kept
    if #othersTimes >= (OTHERS_BURSTS[intensity.key] or 1) then
        return false
    end
    othersTimes[#othersTimes + 1] = now
    return true
end

local function Sound(theme, big, heal)
    if Now() - lastSound < SOUND_GAP then
        return
    end
    lastSound = Now()
    if big then
        DCM.PlaySound(DCM.PickSound("big"), "big")
        return
    end
    local crit = DCM.PickSound("crit")
    DCM.PlaySound(crit, "crit")
    -- The extra (Brutal's squelch) goes with the effects on screen, from the
    -- theme's intensity, and then only now and then (author: "only play it,
    -- say 30% of the time"; the theme's extraChance, else EXTRA_CHANCE).
    if theme.sounds.extra and not heal and DCM.db.splatter
            and DCM.ThemeFrom(theme.sounds.extraFrom, DCM.IntensityIndex())
            and DCM.random() < (theme.sounds.extraChance or DCM.EXTRA_CHANCE) then
        -- Never the crit's own sound twice (Fel's heartbeat).
        local extra = DCM.PickSound("extra")
        if extra ~= crit then
            DCM.PlaySound(extra, "extra")
        end
    end
end

-- One crit. crit: {kind = "mine" | "pet" | "taken" | "others", big = a new record,
-- heal = a heal, school = its spell school mask, when known}. Which kinds
-- count is Detect's call; this only plays it. Heals get the sound, and
-- rising effects in the theme's heal style (or, in Spellburst, its own look).
function DCM.PlayCrit(crit)
    local intensity = DCM.Intensity()
    if not intensity.splats or not overlay then
        return
    end
    local theme = DCM.Theme()
    -- What a damage crit draws: the theme's style for its school.
    local style = DCM.CritStyle(theme, crit.school, crit)
    if crit.kind == "others" then
        if not OthersAllowed(intensity) then
            return
        end
        if DCM.db.sound then
            OthersSound()
        end
        if DCM.db.splatter then
            Splatter(style, intensity, crit)
        end
        return
    end
    if DCM.db.sound then
        Sound(theme, crit.big, crit.heal)
    end
    if DCM.db.splatter and (not crit.heal or theme.heals or theme.heal) then
        -- A heal crit in a theme with a heal style draws that style; a
        -- damage crit its school's style.
        Splatter(crit.heal and (theme.heal or theme) or style, intensity, crit)
        if crit.big and theme.vignette and not crit.heal then
            DCM.PulseVignette(theme)
        end
    end
end

-- /dcm test: a crit of your own at this intensity, and a big one every third time.
function DCM.TestCrit()
    local intensity = DCM.Intensity()
    if not intensity.splats then
        DCM.Report("Intensity is Off: every effect is off. Pick Low or more in /dcm options.")
        return
    end
    DCM.tests = (DCM.tests or 0) + 1
    local big = DCM.tests % 3 == 0
    -- Each test a different school, so a school-tinted theme shows its colors.
    local school = TEST_SCHOOLS[(DCM.tests - 1) % #TEST_SCHOOLS + 1]
    DCM.PlayCrit({kind = "mine", big = big, school = school})
    DCM.Report("Test crit: " .. DCM.Theme().name .. " at " .. intensity.name
        .. (big and ", as a new record." or "."))
end

-- Clears the screen (the intensity went down, or the theme changed).
function DCM.ClearEffects()
    generation = generation + 1
    for index = #active, 1, -1 do
        local splat = active[index]
        splat.group:Stop()
        Finish(splat)
    end
    if vignette then
        vignette.group:Stop()
        vignette:Hide()
    end
end

-- A dark frame around the screen for a new record (Fel, Naturalist): in quickly, then an
-- ominous slow fade, scaled by "Stays on screen". One texture, made once.
local vignette

function DCM.PulseVignette(theme)
    if not vignette then
        vignette = overlay:CreateTexture(nil, "OVERLAY")
        vignette:SetAllPoints(overlay)
        vignette:Hide()
        local group = vignette:CreateAnimationGroup()
        vignette.rise = group:CreateAnimation("Alpha")
        vignette.rise:SetFromAlpha(0)
        vignette.rise:SetToAlpha(1)
        vignette.rise:SetDuration(VIGNETTE_IN)
        vignette.fade = group:CreateAnimation("Alpha")
        vignette.fade:SetFromAlpha(1)
        vignette.fade:SetToAlpha(0)
        vignette.fade:SetStartDelay(VIGNETTE_IN)
        group:SetScript("OnFinished", function() vignette:Hide() end)
        vignette.group = group
        DCM.vignette = vignette
    end
    vignette.group:Stop()
    vignette:SetTexture(theme.vignette)
    -- A tint for a white vignette (Naturalist's deep green); Fel's is black.
    local tint = theme.vignetteColor or {1, 1, 1}
    vignette:SetVertexColor(tint[1], tint[2], tint[3])
    vignette.fade:SetDuration(VIGNETTE_FADE * DCM.db.stay / 100)
    vignette:SetAlpha(1)
    vignette:Show()
    vignette.group:Play()
end

function DCM.InitializeEffects()
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("BACKGROUND")
    overlay:EnableMouse(false)
    DCM.overlay = overlay
end
