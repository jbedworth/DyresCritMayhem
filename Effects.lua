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
local function ShowSplat(intensity, theme, texture, motion, big, taken, runs, color)
    local splat = TakeSplat()
    splat.group:Stop()
    local size = SPLAT_SIZE * intensity.size * (theme.size or 1) * (big and BIG_SIZE or 1)
        * Between(1 - SIZE_JITTER, 1 + SIZE_JITTER)
    color = color or theme.colors[DCM.random(#theme.colors)]
    splat:SetTexture(texture)
    -- Glows (Spellburst, Fel's embers) add light; the pooled texture is set
    -- every time.
    splat:SetBlendMode(theme.textureBlend and theme.textureBlend[texture] or theme.blend or "BLEND")
    splat:SetVertexColor(color[1], color[2], color[3])
    splat:SetSize(size, size)
    -- A random turn and mirror, so four textures never look like four.
    if type(splat.SetRotation) == "function" then
        if motion == "float" then
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
    local x, y = Spot(overlay:GetWidth(), overlay:GetHeight(), taken)
    splat:ClearAllPoints()
    splat:SetPoint("CENTER", overlay, "BOTTOMLEFT", x, y)
    splat:SetAlpha(1)
    -- "Stays on screen" scales the intensity's hold and fade together.
    local stay = DCM.db.stay / 100
    local hold, fadeSeconds = intensity.hold * stay, intensity.fade * stay
    splat.fade:SetStartDelay(hold)
    splat.fade:SetDuration(fadeSeconds)
    splat.slide:SetOffset(0, motion == "drip" and -DRIP_SLIDE or motion == "float" and FLOAT_RISE or 0)
    splat.slide:SetDuration(hold + fadeSeconds)
    splat:Show()
    splat.group:Play()
    -- What moves while it holds, within the cap: a run (a splat that stays
    -- put, or one whose run spreads from where it landed), and a loop.
    if runs and moving < MAX_MOVING and motion ~= "drip" and (motion == nil or theme.runGrow == "center") then
        StartRun(splat, theme, color, size, hold, fadeSeconds, x, y)
    end
    local loop = theme.animations and theme.animations[texture]
    if loop and moving < MAX_MOVING then
        StartLoop(splat, loop)
    end
end

local function Pick(list)
    return list[DCM.random(#list)]
end

-- crit: as PlayCrit's. A theme with school colors tints every effect of the
-- crit by its spell school; heals (where the theme shows them) all rise.
local function Splatter(theme, intensity, crit)
    local big, taken = crit.big, crit.kind == "taken"
    local color = theme.schoolColors and DCM.SchoolColor(theme, crit.school, crit.heal)
        or theme.schoolPalette and DCM.PaletteColor(theme, crit.school)
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
        ShowSplat(intensity, theme, texture, motion, big, taken, not crit.heal and DCM.random() < runChance, color)
    end
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
    DCM.PlaySound(DCM.PickSound("crit"), "crit")
    -- The extra (Brutal's squelch) goes with the effects on screen, from the
    -- theme's intensity, and then only now and then (author: "only play it,
    -- say 30% of the time"; the theme's extraChance, else EXTRA_CHANCE).
    if theme.sounds.extra and not heal and DCM.db.splatter
            and DCM.ThemeFrom(theme.sounds.extraFrom, DCM.IntensityIndex())
            and DCM.random() < (theme.sounds.extraChance or DCM.EXTRA_CHANCE) then
        DCM.PlaySound(DCM.PickSound("extra"), "extra")
    end
end

-- One crit. crit: {kind = "mine" | "pet" | "taken", big = a new record,
-- heal = a heal, school = its spell school mask, when known}. Which kinds
-- count is Detect's call; this only plays it. Heals get the sound, and
-- rising effects in the theme's heal style (or, in Spellburst, its own look).
function DCM.PlayCrit(crit)
    local intensity = DCM.Intensity()
    if not intensity.splats or not overlay then
        return
    end
    local theme = DCM.Theme()
    if DCM.db.sound then
        Sound(theme, crit.big, crit.heal)
    end
    if DCM.db.splatter and (not crit.heal or theme.heals or theme.heal) then
        -- A heal crit in a theme with a heal style draws that style.
        Splatter(crit.heal and theme.heal or theme, intensity, crit)
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

-- A dark frame around the screen for a new record (Fel): in quickly, then an
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
