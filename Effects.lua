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
--
-- Hit effects (author: "Build the nameplate blood spray too", then "The hit
-- effects should trigger every time a hit lands and does damage (even DoTs,
-- ideally). It should look like it's happening to the target (mob, player
-- avatar)"): AddOns cannot draw on a mob in the world, so every damaging hit
-- on an enemy whose nameplate shows plays its school's effect from the
-- plate, over the body (SPRAY_DROP under the plate's center), and a hit on
-- you over your character. Small textures on their own frame (hitLayer,
-- BACKGROUND), each anchored to the plate so it follows the mob, at most
-- MAX_HITS; a plate that goes away (NAME_PLATE_UNIT_REMOVED) takes its
-- effects with it, since the client reuses plates. Needs enemy nameplates
-- on; DCM never turns them on.
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
-- Hit effects: pieces per hit by intensity (a crit doubles them, makes
-- them HIT_CRIT_SIZE bigger and fly HIT_CRIT_REACH farther, and adds the
-- style's flash: one big piece at the impact that swells by FLASH_GROW and
-- fades in FLASH_SECONDS; a new record adds HIT_BIG; others' hits half,
-- at most OTHERS_HITS per OTHERS_WINDOW); one set per target per HIT_GAP
-- unless it crits. AVATAR_Y: your character's body below the screen's
-- center, as a part of its height (no nameplate of your own).
local MAX_HITS = 120
local SPRAY_SIZE = 34
-- The body below an enemy's nameplate (author: "about 2x further down, so
-- it looks like it's coming from the mob, instead of sitting on top of it's
-- head"), at full size.
local SPRAY_DROP = -76
local HIT_COUNT = {low = 2, medium = 3, high = 5, max = 7}
local HIT_CRIT_SIZE = 1.6
local HIT_CRIT_REACH = 1.5
-- An upright style's pieces (flames) tilt at most this far, in radians.
local UPRIGHT_TILT = 0.3
local FLASH_SECONDS = 0.45
local FLASH_GROW = 1.5
local FLASH_FADE_AT = 0.3
local HIT_BIG = 3
local OTHERS_HITS = {low = 2, medium = 3, high = 4, max = 6}
local HIT_GAP = 0.1
local AVATAR_Y = -0.05

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

local hitLayer
local hitFree, hitActive = {}, {}
local othersHitTimes = {}
local lastHit = {}

local function FinishHit(hit)
    hit:Hide()
    hit.unit, hit.anchor = nil, nil
    for index, other in ipairs(hitActive) do
        if other == hit then
            table.remove(hitActive, index)
            break
        end
    end
    hitFree[#hitFree + 1] = hit
end

local function NewHit()
    local hit = hitLayer:CreateTexture(nil, "ARTWORK")
    hit:Hide()
    local group = hit:CreateAnimationGroup()
    hit.pop = group:CreateAnimation("Scale")
    hit.pop:SetDuration(POP_SECONDS)
    if type(hit.pop.SetScaleFrom) == "function" then
        hit.pop:SetScaleFrom(POP_FROM, POP_FROM)
        hit.pop:SetScaleTo(1, 1)
    end
    hit.grow = group:CreateAnimation("Scale")
    hit.fly = group:CreateAnimation("Translation")
    hit.spin = group:CreateAnimation("Rotation")
    hit.fade = group:CreateAnimation("Alpha")
    hit.fade:SetFromAlpha(1)
    hit.fade:SetToAlpha(0)
    group:SetScript("OnFinished", function() FinishHit(hit) end)
    hit.group = group
    return hit
end

-- Where a piece's pop and grow scale from (a flame from its base), and its
-- pop: from popFrom (x, y) over popSeconds, else the usual pop.
local function Shape(item, origin, popFrom, popSeconds)
    if type(item.pop.SetOrigin) == "function" then
        item.pop:SetOrigin(origin or "CENTER", 0, 0)
        item.grow:SetOrigin(origin or "CENTER", 0, 0)
    end
    item.pop:SetDuration(popSeconds or POP_SECONDS)
    if type(item.pop.SetScaleFrom) == "function" then
        item.pop:SetScaleFrom(popFrom and popFrom[1] or POP_FROM, popFrom and popFrom[2] or POP_FROM)
    end
end

local function TakeHit()
    local hit = table.remove(hitFree)
    if not hit and #hitActive >= MAX_HITS then
        hit = table.remove(hitActive, 1)
        hit.group:Stop()
    end
    hit = hit or NewHit()
    hitActive[#hitActive + 1] = hit
    return hit
end

-- The nameplate frame shown for a unit, or nil (nameplates off, out of
-- range, secret, or a forbidden frame no AddOn may anchor to).
local function Plate(unit)
    if type(unit) ~= "string" or type(C_NamePlate) ~= "table"
            or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        return nil
    end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if DCM.IsSecret(plate) or type(plate) ~= "table" then
        return nil
    end
    if type(plate.IsForbidden) == "function" and plate:IsForbidden() then
        return nil
    end
    return plate
end

-- Where a hit plays: the enemy's nameplate (its body is SPRAY_DROP below
-- the plate's center), or for a hit on you your own nameplate when the
-- client shows one, else the screen's middle, where the camera keeps your
-- character (AVATAR_Y of the screen's height below the center). Returns the
-- frame, the body's offset from its center, and the unit it follows.
-- How far an enemy is (author: "the size of the effect should scale down
-- with distance. If I'm within 1-3 meters, use the current size, if the
-- mob is 30m away, it should be much smaller"). The client tells AddOns
-- only whether a unit is within a range, and blocks it in combat for
-- friendly units only (LibRangeCheck-3.0's InCombatLockdownRestriction), so
-- enemies answer in combat: CheckInteractDistance's duel (3, about 10 yd)
-- and follow (4, about 28 yd), and C_Item.IsItemInRange on items with known
-- ranges (LibRangeCheck-3.0's Era list), nearest first. Each is (yards,
-- probe); the first true gives the distance. An item the client has not
-- loaded answers nil, and is skipped.
local DISTANCE_PROBES = {
    {5, "item", 8149},   -- Voodoo Charm
    {5, "item", 15826},  -- Curative Animal Salve
    {10, "interact", 3},
    {20, "item", 10645}, -- Gnomish Death Ray
    {20, "item", 1191},  -- Bag of Marbles
    {28, "interact", 4},
    {30, "item", 835},   -- Large Rope Net
    {30, "item", 1404},  -- Tidal Charm
    {40, "item", 4945},  -- Faintly Glowing Skull
    {40, "item", 8348},  -- Helm of Fire
}
-- The effect's scale by distance (yards, scale), between them in a line;
-- past the last, FAR_SCALE. Unknown (no probe answered): 1. Tuned in play
-- (author: "At max spell range (30+ m) the effect should be a bit smaller
-- than it is now. Up close, it could be slightly bigger").
local DISTANCE_SCALES = {{5, 1.15}, {10, 0.95}, {20, 0.6}, {30, 0.3}, {40, 0.24}}
local FAR_SCALE = 0.22
local BYSTANDER_SCALE = 0.6

local function Probe(kind, value, unit)
    local result
    if kind == "interact" then
        if type(CheckInteractDistance) ~= "function" then
            return nil
        end
        result = CheckInteractDistance(unit, value)
    else
        if type(C_Item) ~= "table" or type(C_Item.IsItemInRange) ~= "function" then
            return nil
        end
        result = C_Item.IsItemInRange(value, unit)
    end
    if DCM.IsSecret(result) or result == nil then
        return nil
    end
    return result == true or result == 1
end

-- The unit's distance band in yards: the first probe it is within, past the
-- last one answered false, or nil when no probe answered.
function DCM.UnitDistance(unit)
    -- In combat the client blocks these for a unit you cannot attack (found
    -- in client: ADDON_ACTION_BLOCKED on IsItemInRange and
    -- CheckInteractDistance; LibRangeCheck-3.0 skips the same case): no
    -- distance, full size.
    if type(InCombatLockdown) ~= "function" or InCombatLockdown() then
        local enemy = type(UnitCanAttack) == "function" and UnitCanAttack("player", unit)
        if DCM.IsSecret(enemy) or enemy ~= true then
            return nil
        end
    end
    local answered = false
    for _, probe in ipairs(DISTANCE_PROBES) do
        local within = Probe(probe[2], probe[3], unit)
        if within then
            return probe[1]
        elseif within == false then
            answered = true
        end
    end
    return answered and math.huge or nil
end

function DCM.DistanceScale(yards)
    if not yards then
        return 1
    end
    if yards <= DISTANCE_SCALES[1][1] then
        return DISTANCE_SCALES[1][2]
    end
    for index = 2, #DISTANCE_SCALES do
        local near, far = DISTANCE_SCALES[index - 1], DISTANCE_SCALES[index]
        if yards <= far[1] then
            return near[2] + (far[2] - near[2]) * (yards - near[1]) / (far[1] - near[1])
        end
    end
    return FAR_SCALE
end

-- The items' data, so their ranges answer (an item never seen is not loaded).
local function LoadProbeItems()
    if type(C_Item) ~= "table" or type(C_Item.RequestLoadItemDataByID) ~= "function" then
        return
    end
    for _, probe in ipairs(DISTANCE_PROBES) do
        if probe[2] == "item" then
            C_Item.RequestLoadItemDataByID(probe[3])
        end
    end
end

local function HitAnchor(hit)
    if hit.kind == "taken" or hit.kind == "self" then
        local plate = Plate("player")
        if plate then
            return plate, SPRAY_DROP, "player"
        end
        local height = type(UIParent.GetHeight) == "function" and UIParent:GetHeight() or 0
        return UIParent, (type(height) == "number" and height or 0) * AVATAR_Y, nil
    end
    local plate = Plate(hit.unit)
    if plate then
        local yards = DCM.UnitDistance(hit.unit)
        -- A bystander's distance cannot be read in combat: a middle size.
        local scale = yards and DCM.DistanceScale(yards) or hit.bystander and BYSTANDER_SCALE or 1
        return plate, SPRAY_DROP * scale, hit.unit, scale
    end
end

-- Clears the hit effects on a unit's nameplate (it is about to be reused).
function DCM.ReleaseSprays(unit)
    for index = #hitActive, 1, -1 do
        local hit = hitActive[index]
        if hit.unit == unit then
            hit.group:Stop()
            FinishHit(hit)
        end
    end
end

local HIT_STYLES = DCM.HIT_STYLES

-- Each motion: seconds; the start above the body and its spread; the move
-- (x and y ranges, or an angle range and distance for spray and burst); a
-- turn in degrees; a grow; when the fade starts.
local HIT_MOTIONS = {
    spray = {seconds = 0.75, startY = 0, spread = 14, angle = {-0.35, math.pi + 0.35}, distance = {22, 64},
        fall = 30, fadeAt = 0.3},
    burst = {seconds = 0.5, startY = 0, spread = 8, angle = {0, 2 * math.pi}, distance = {30, 80},
        fall = 0, fadeAt = 0.4},
    flurry = {seconds = 1.3, startY = 35, spread = 30, x = {-25, 25}, y = {-90, -60}, turn = 180, fadeAt = 0.5},
    blaze = {seconds = 0.9, startY = 0, spread = 14, x = {-8, 8}, y = {6, 18}, turn = 70, grow = 1.5,
        fadeAt = 0.35},
    smoke = {seconds = 1.3, startY = 0, spread = 16, x = {-15, 15}, y = {20, 45}, turn = 40, grow = 1.6,
        fadeAt = 0.25},
    rise = {seconds = 1, startY = -10, spread = 20, x = {-15, 15}, y = {40, 70}, fadeAt = 0.4},
}

-- The style a hit draws: a heal's green plus signs, else its school's (nil
-- or secret: physical), the theme's tints over it (Fel's green smoke and fel
-- fire), and no blood without the 18+ box.
local function HitStyle(theme, school, heal)
    local kind = heal and "heal" or DCM.SchoolKind(school) or "physical"
    if kind == "physical" and not DCM.IsAdult() then
        kind = "impact"
    end
    local style = theme.hitStyles and theme.hitStyles[kind] or HIT_STYLES[kind]
    return style, style.colors, kind
end

-- Whose look an effect draws (author: "effects on me retain the brutal
-- effect. What I'm stylizing is the damage I'm doing"): a variant of Brutal
-- (Themes.lua BrutalBase) styles only your, your pet's, and /dcm test's;
-- damage on you, others', and bystanders' draw Brutal itself. Tame (not a
-- variant) draws its own for everything.
function DCM.Look(theme, kind)
    if theme.variant and kind ~= "mine" and kind ~= "pet" and kind ~= "self" then
        return DCM.FindTheme("brutal")
    end
    return theme
end

-- One hit's effect on its target. hit: {kind = "mine" | "pet" | "others" |
-- "taken" | "self", unit, school, crit, big, heal}. Every theme but Tame and None
-- (author: "Tame gets none of these on target effects for now"); a crit
-- doubles it (author: "when it crits, it should double the intensity of the
-- effect at it's setting"), a new record adds HIT_BIG.
function DCM.PlayHit(hit)
    local theme = DCM.Theme()
    if not hitLayer or theme.none or theme.noHits then
        return
    end
    local onYou = hit.kind == "taken" or hit.kind == "self"
    if onYou and not DCM.db.hitsOnYou or not onYou and not DCM.db.spray then
        return
    end
    local look = DCM.Look(theme, hit.kind)
    local anchor, body, unit, scale = HitAnchor(hit)
    scale = scale or 1
    if not anchor then
        return
    end
    local intensity = DCM.Intensity()
    local now = Now()
    local count = HIT_COUNT[intensity.key] or 2
    if hit.kind == "others" then
        -- Others' hits: fewer, and at most OTHERS_HITS by intensity in any
        -- OTHERS_WINDOW, so a raid cannot flood the pool.
        for index = #othersHitTimes, 1, -1 do
            if now - othersHitTimes[index] > OTHERS_WINDOW then
                table.remove(othersHitTimes, index)
            end
        end
        if #othersHitTimes >= (OTHERS_HITS[intensity.key] or 2) then
            return
        end
        othersHitTimes[#othersHitTimes + 1] = now
        count = math.ceil(count / 2)
    end
    -- The same target hit again this soon (a melee swing and its proc) adds
    -- one more set only after HIT_GAP.
    local key = unit or "you"
    if not hit.crit and lastHit[key] and now - lastHit[key] < HIT_GAP then
        return
    end
    lastHit[key] = now
    local style, colors = HitStyle(look, hit.school, hit.heal)
    -- emphasis: a variant's stronger school (Spellburst's spells).
    count = math.ceil(count * (style.count or 1) * (style.emphasis or 1))
    if hit.crit then
        count = count * 2
    end
    if hit.big then
        count = count + HIT_BIG
    end
    local motion = HIT_MOTIONS[style.motion]
    for _ = 1, count do
        local texture = Pick(style.textures)
        local tint = style.textureColors and style.textureColors[texture] or Pick(colors)
        local item = TakeHit()
        item.group:Stop()
        item.unit = unit
        item:SetTexture(texture)
        item:SetBlendMode(style.blend)
        item:SetVertexColor(tint[1], tint[2], tint[3])
        local size = SPRAY_SIZE * style.size * intensity.size * (hit.crit and HIT_CRIT_SIZE or 1)
            * Between(0.6, 1.2) * scale
        item:SetSize(size, size)
        if type(item.SetRotation) == "function" then
            item:SetRotation(style.upright and Between(-UPRIGHT_TILT, UPRIGHT_TILT) or Between(0, 2 * math.pi))
        end
        item:ClearAllPoints()
        item:SetPoint("CENTER", anchor, "CENTER", Between(-motion.spread, motion.spread) * scale,
            body + (motion.startY + Between(-motion.spread, motion.spread) / 2) * scale)
        local x, y
        if motion.angle then
            local angle = Between(motion.angle[1], motion.angle[2])
            local distance = Between(motion.distance[1], motion.distance[2])
            x, y = math.cos(angle) * distance, math.sin(angle) * distance * 0.5 - motion.fall
        else
            x, y = Between(motion.x[1], motion.x[2]), Between(motion.y[1], motion.y[2])
        end
        if hit.crit then
            x, y = x * HIT_CRIT_REACH, y * HIT_CRIT_REACH
        end
        x, y = x * scale, y * scale
        item.fly:SetDuration(motion.seconds)
        item.fly:SetOffset(x, y)
        item.spin:SetDuration(motion.seconds)
        if type(item.spin.SetDegrees) == "function" then
            item.spin:SetDegrees(motion.turn and Between(-motion.turn, motion.turn) or 0)
        end
        item.grow:SetDuration(motion.seconds)
        if type(item.grow.SetScaleFrom) == "function" then
            item.grow:SetScaleFrom(1, 1)
            if motion.stretch then
                item.grow:SetScaleTo(motion.stretch[1], motion.stretch[2])
            else
                item.grow:SetScaleTo(motion.grow or 1, motion.grow or 1)
            end
        end
        Shape(item, motion.origin, motion.popFrom, motion.popSeconds)
        item.fade:SetStartDelay(motion.seconds * motion.fadeAt)
        item.fade:SetDuration(motion.seconds * (1 - motion.fadeAt))
        item:SetAlpha(1)
        item:Show()
        item.group:Play()
    end
    if hit.crit and style.flash then
        -- The crit's flash, under nothing else: one big piece at the impact.
        local flash = style.flash
        local tint = Pick(colors)
        local item = TakeHit()
        item.group:Stop()
        item.unit = unit
        item:SetTexture(flash.texture)
        item:SetBlendMode(flash.blend)
        item:SetVertexColor(tint[1], tint[2], tint[3])
        local size = SPRAY_SIZE * flash.size * (style.flashScale or 1) * intensity.size
            * (hit.big and BIG_SIZE or 1) * scale
        item:SetSize(size, size)
        if type(item.SetRotation) == "function" then
            item:SetRotation(Between(0, 2 * math.pi))
        end
        item:ClearAllPoints()
        item:SetPoint("CENTER", anchor, "CENTER", 0, body)
        item.fly:SetDuration(FLASH_SECONDS)
        item.fly:SetOffset(0, 0)
        item.spin:SetDuration(FLASH_SECONDS)
        if type(item.spin.SetDegrees) == "function" then
            item.spin:SetDegrees(0)
        end
        item.grow:SetDuration(FLASH_SECONDS)
        if type(item.grow.SetScaleFrom) == "function" then
            item.grow:SetScaleFrom(1, 1)
            item.grow:SetScaleTo(FLASH_GROW, FLASH_GROW)
        end
        Shape(item, nil, nil, nil)
        item.fade:SetStartDelay(FLASH_SECONDS * FLASH_FADE_AT)
        item.fade:SetDuration(FLASH_SECONDS * (1 - FLASH_FADE_AT))
        item:SetAlpha(1)
        item:Show()
        item.group:Play()
    end
end

-- The school of a hit for /dcm test: the effect on your target's nameplate,
-- else on you.
function DCM.TestHit(school, heal)
    local plate = Plate("target")
    DCM.PlayHit({kind = plate and "mine" or "self", unit = plate and "target" or nil, school = school,
        crit = true, heal = heal})
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
    -- A variant's own touch (Fel's smoke, Spellburst's glow, Naturalist's
    -- leaves), over Brutal's school accent.
    if theme.extraAccent and not crit.heal then
        ShowAccent(intensity, theme, theme.extraAccent, taken, base)
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
    local sounds = DCM.Theme()
    if sounds.none or not overlay then
        return
    end
    -- What a damage crit draws: the look's style for its school (your
    -- variant for your damage, else Brutal); the sounds stay the theme's.
    local theme = DCM.Look(sounds, crit.kind)
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
        Sound(sounds, crit.big, crit.heal)
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
-- /dcm test <type>: one school every time (author: "so I can lock in on
-- fire"), or a heal; none: the schools in turn.
local TEST_TYPES = {physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64,
    heal = "heal"}
local TEST_NAMES = {[1] = "physical", [2] = "holy", [4] = "fire", [8] = "nature", [16] = "frost", [32] = "shadow",
    [64] = "arcane"}
local TEST_USAGE = "Use /dcm test, or /dcm test with one of: fire, frost, arcane, shadow, nature, holy, physical, heal."

function DCM.TestCrit(kind)
    local intensity = DCM.Intensity()
    if DCM.Theme().none then
        DCM.Report("Theme is None: every effect is off. Pick a theme in /dcm options.")
        return
    end
    local chosen = kind and TEST_TYPES[kind]
    if kind and not chosen then
        DCM.Report(TEST_USAGE)
        return
    end
    DCM.tests = (DCM.tests or 0) + 1
    local big = DCM.tests % 3 == 0
    -- Each test a different school, so a school-tinted theme shows its colors.
    local school = TEST_SCHOOLS[(DCM.tests - 1) % #TEST_SCHOOLS + 1]
    local heal = chosen == "heal"
    if chosen and not heal then
        school = chosen
    elseif heal then
        school = 2
    end
    DCM.PlayCrit({kind = "mine", big = big, school = school, heal = heal})
    DCM.TestHit(school, heal)
    DCM.Report("Test crit: " .. (heal and "heal" or TEST_NAMES[school]) .. ", " .. DCM.Theme().name .. " at "
        .. intensity.name .. (big and ", as a new record." or "."))
end

-- Clears the screen (the intensity went down, or the theme changed).
function DCM.ClearEffects()
    generation = generation + 1
    for index = #active, 1, -1 do
        local splat = active[index]
        splat.group:Stop()
        Finish(splat)
    end
    for index = #hitActive, 1, -1 do
        hitActive[index].group:Stop()
        FinishHit(hitActive[index])
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
    hitLayer = CreateFrame("Frame", nil, UIParent)
    hitLayer:SetAllPoints(UIParent)
    hitLayer:SetFrameStrata("BACKGROUND")
    hitLayer:EnableMouse(false)
    DCM.hitLayer = hitLayer
    LoadProbeItems()
end
