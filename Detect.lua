local _, DCM = ...

-- Finding crits. Gated on the client's APIs, never on its version.
--
-- The combat log (Classic Era 1.15.9, Anniversary 2.5.6): COMBAT_LOG_EVENT_UNFILTERED
-- with C_CombatLog.GetCurrentEventInfo (CombatLogGetCurrentEventInfo is only
-- a deprecation fallback there). Damage and heals from you or your pet,
-- damage to you, and anyone's damage crits on your target or, by default,
-- any nearby enemy with a nameplate shown (author: "The mob I'm targeting is
-- getting critted, blood should spatter no matter who caused it" and "maybe
-- it should be on for all nameplates visible"; the "Others' crits" setting:
-- Off, My target, Nearby enemies). Effects.lua trims them first. Records
-- stay yours. Fields after the 11 common ones:
--   SWING_DAMAGE               amount 12, critical 18 (physical)
--   RANGE_ / SPELL_ / SPELL_PERIODIC_DAMAGE   name 13, school 14, amount 15,
--                                             critical 21
--   SPELL_ / SPELL_PERIODIC_HEAL              name 13, school 14, amount 15,
--                                             critical 18
-- The school (a mask) tints a school-colored theme (Spellburst).
-- Classic logs no spell IDs (0), so abilities go by name, every rank as one.
--
-- WoW: Forever refuses the combat log: registering it is blocked, and
-- C_CombatLog.IsCombatLogRestricted() is true (found in client by Warlock
-- Tools Forever). It is never registered there. Instead (author: "we
-- absolutely MUST make this work in Forever"; pinned source 943764493e):
--   - UNIT_COMBAT (unit, event, flagText, amount, schoolMask), registered
--     for every unit, has no secret markings. "WOUND" with "CRITICAL" on
--     "target", "focus", or a nameplate is a crit on an enemy; "WOUND" with
--     "CRITICAL" or "CRUSHING" on "player" is one on you; "HEAL" with
--     "CRITICAL" on "player" a crit heal on you. One hit can arrive for the
--     target and its nameplate both: the same flag, amount, and school
--     within DEDUPE seconds count once.
--   - Solo (no group), every crit on an enemy is yours or your pet's.
--   - In a group whose crit it was cannot be told, so a crit on your target
--     (and, with Nearby enemies, on an enemy nameplate) plays as others'
--     crits; focus plays nothing, and nothing in a group makes a record.
--   - Records, solo only: UNIT_COMBAT names no ability, so the hit is
--     matched to your (or your pet's) last harmful cast from
--     UNIT_SPELLCAST_SUCCEEDED (its spellID is readable for your own casts,
--     found by Warlock Tools Forever). A physical hit within MELEE_WINDOW
--     of a cast is that ability; another physical hit is Melee (unless a
--     pet is out: then unknown); a spell-school hit is the latest cast
--     within SPELL_WINDOW (a projectile's flight); otherwise no record.
--     These are best guesses: damage over time lands as the last cast.
--   - The damage meter (C_DamageMeter) gives per-spell totals per fight,
--     not the largest hit: its maxAmount only scales the bars (Blizzard's
--     DamageMeterSourceWindow), so it cannot give records. /dcm probe dumps
--     it after a fight anyway, to confirm.
-- Unconfirmed: Forever's servers are closed until launch (Nov 4); /dcm probe
-- (Probe.lua) checks all of it in client.
local SWING = "SWING_DAMAGE"
local SPELL_DAMAGE = {RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true}
local SPELL_HEAL = {SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true}
local MELEE_NAME = "Melee"
DCM.MELEE_NAME = MELEE_NAME
local PHYSICAL = 1
local MELEE_WINDOW = 0.4
local SPELL_WINDOW = 1.5
local DEDUPE = 0.05
local TAKEN_FLAGS = {CRITICAL = true, CRUSHING = true}

local mode
local events
-- The last harmful cast by you and by your pet: {name, at}.
local lastCast = {}
local lastWound
-- Solo records from combat text, since login (/dcm debug): hits on an enemy
-- (after DEDUPE), hits that made a record, and why the others made none. A
-- hit can count under one school reason and one amount reason.
local RECORD_REASONS = {"grouped", "secretSchool", "noCast", "secretAmount", "noAmount"}
local recordCounts = {}

local function ResetRecordCounts()
    recordCounts = {hits = 0, recorded = 0}
    for _, reason in ipairs(RECORD_REASONS) do
        recordCounts[reason] = 0
    end
end
ResetRecordCounts()
DCM.ResetRecordCounts = ResetRecordCounts

local function Count(field)
    recordCounts[field] = recordCounts[field] + 1
end

-- "hits=N recorded=N grouped=N ...", for /dcm debug.
function DCM.RecordCountsText()
    local parts = {"hits=" .. recordCounts.hits, "recorded=" .. recordCounts.recorded}
    for _, reason in ipairs(RECORD_REASONS) do
        parts[#parts + 1] = reason .. "=" .. recordCounts[reason]
    end
    return table.concat(parts, " ")
end

local function EventInfoFunction()
    if type(C_CombatLog) == "table" and type(C_CombatLog.GetCurrentEventInfo) == "function" then
        return C_CombatLog.GetCurrentEventInfo
    end
    if type(CombatLogGetCurrentEventInfo) == "function" then
        return CombatLogGetCurrentEventInfo
    end
end

function DCM.CombatLogUsable()
    if type(C_CombatLog) == "table" and type(C_CombatLog.IsCombatLogRestricted) == "function"
            and C_CombatLog.IsCombatLogRestricted() then
        return false
    end
    return EventInfoFunction() ~= nil
end

-- "combatlog", "unitcombat", or "none".
function DCM.DetectionMode()
    return mode or "none"
end

-- Records need the ability's name and a readable amount: from the combat
-- log, or guessed from combat text (UNIT_COMBAT) while solo. Combat text's
-- amounts can be secret: WoW: Forever build 70938 hides every one in
-- combat (John's /dcm probe, 2026-11-16: 996 of 996 hits), and its
-- damage meter gives only per-spell totals after a fight, never a largest
-- hit. So combat text keeps records only after a readable amount on an
-- enemy (DCM.amountsReadable, the latest one seen wins); until then, and
-- after a secret one, the window says records are not kept on this client.
function DCM.RecordsAvailable()
    return mode == "combatlog" or mode == "unitcombat" and DCM.amountsReadable == true
end

function DCM.RecordsGuessed()
    return mode == "unitcombat" and DCM.amountsReadable == true
end

-- Combat text whose amounts this client hides (or has not shown yet).
function DCM.AmountsHidden()
    return mode == "unitcombat" and DCM.amountsReadable ~= true
end

local function Plain(value)
    return not DCM.IsSecret(value)
end

-- One hit or heal from you or your pet: the record, then the crit's effect.
-- A school mask to pass on, or nil when it is secret or not a number.
local function School(value)
    return Plain(value) and type(value) == "number" and value or nil
end

-- A hit that did something: a readable positive amount, or one the client
-- hides (it still landed).
local function Landed(amount)
    return not Plain(amount) or type(amount) == "number" and amount > 0
end

-- Where a hit plays (author: "It should look like it's happening to the
-- target (mob, player avatar)"): on you, or on an enemy's nameplate (a heal
-- on your target, on its plate, friendly plates shown). nil: nowhere.
local function HitTarget(destGUID, heal)
    if destGUID == DCM.playerGUID then
        return "self", nil
    end
    local unit = DCM.PlateUnit(destGUID)
    if not unit and heal and destGUID == DCM.targetGUID then
        unit = "target"
    end
    return unit and "target" or nil, unit
end

-- The hit effect for any damage or heal that landed (author: "every time a
-- hit lands and does damage (even DoTs, ideally) ... when it crits, it
-- should double"). Nature damage over time shows nothing: the game draws
-- its own green cloud on a poisoned mob.
local function Hit(kind, subevent, amount, critical, heal, school, destGUID, big, bystander)
    if not Landed(amount) or subevent == "SPELL_PERIODIC_DAMAGE" and DCM.SchoolKind(school) == "nature" then
        return
    end
    local where, unit = HitTarget(destGUID, heal)
    if not where then
        return
    end
    DCM.PlayHit({kind = where == "self" and "taken" or kind, unit = unit, school = school, crit = critical,
        big = big, heal = heal, bystander = bystander})
end

local function Mine(kind, name, amount, critical, heal, school, destGUID, subevent)
    local big = false
    if (not heal or DCM.db.heals) and Plain(name) and Plain(amount) and type(name) == "string"
            and type(amount) == "number" then
        big = DCM.Record(name, amount, critical, kind == "pet", heal)
    end
    if not DCM.db[kind] then
        return
    end
    Hit(kind, subevent, amount, critical, heal, school, destGUID, big)
    if critical and (not heal or DCM.db.heals) then
        DCM.PlayCrit({kind = kind, big = big, heal = heal, school = school,
            unit = not heal and DCM.PlateUnit(destGUID) or nil})
    end
end

local function OnCombatLog(...)
    local _, subevent, _, sourceGUID, _, _, _, destGUID = ...
    if not Plain(subevent) or not Plain(sourceGUID) or not Plain(destGUID) then
        return
    end
    local name, amount, critical, heal, school
    if subevent == SWING then
        name, amount, critical, school = MELEE_NAME, select(12, ...), select(18, ...), PHYSICAL
    elseif SPELL_DAMAGE[subevent] then
        name, school, amount, critical = select(13, ...), School((select(14, ...))), select(15, ...), select(21, ...)
    elseif SPELL_HEAL[subevent] then
        name, school, amount, critical = select(13, ...), School((select(14, ...))), select(15, ...), select(18, ...)
        heal = true
    else
        return
    end
    if not Plain(critical) then
        return
    end
    critical = critical == true
    local player = DCM.playerGUID
    if sourceGUID == player then
        Mine("mine", name, amount, critical, heal, school, destGUID, subevent)
    elseif sourceGUID ~= nil and sourceGUID == DCM.petGUID then
        Mine("pet", name, amount, critical, heal, school, destGUID, subevent)
    elseif destGUID == player then
        -- A hit or heal on you, from anyone.
        Hit("taken", subevent, amount, critical, heal, school, destGUID, false)
        if critical and not heal and DCM.db.taken then
            DCM.PlayCrit({kind = "taken", school = school})
        end
    elseif not heal and DCM.OthersOn(destGUID) then
        -- Someone else's hit on your target or a nearby enemy: the effect,
        -- never a record.
        Hit("others", subevent, amount, critical, false, school, destGUID, false)
        if critical then
            DCM.PlayCrit({kind = "others", school = school, unit = DCM.PlateUnit(destGUID)})
        end
    elseif not heal and DCM.BystanderOn(destGUID) then
        -- A hit on someone not your enemy (another player, a guard, your
        -- friendly target): its hit effect, and a crit as others' crits
        -- (author: "put the crit splatter from other's crits back").
        Hit("others", subevent, amount, critical, false, school, destGUID, false, true)
        if critical then
            DCM.PlayCrit({kind = "others", school = school, unit = DCM.PlateUnit(destGUID)})
        end
    end
end

local function InGroup()
    return type(IsInGroup) == "function" and IsInGroup() == true
end

function DCM.EnemyUnit(unit)
    return unit == "target" or unit == "focus" or (type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil)
end

-- A successful harmful cast by you or your pet: what later hits are matched to.
local function OnCast(unit, _, spellID)
    if (unit ~= "player" and unit ~= "pet") or not Plain(spellID) or type(spellID) ~= "number"
            or type(C_Spell) ~= "table" or type(C_Spell.GetSpellName) ~= "function" then
        return
    end
    if type(C_Spell.IsSpellHarmful) == "function" then
        local harmful = C_Spell.IsSpellHarmful(spellID)
        if Plain(harmful) and harmful == false then
            return
        end
    end
    local name = C_Spell.GetSpellName(spellID)
    if Plain(name) and type(name) == "string" then
        lastCast[unit] = {name = name, at = GetTime()}
    end
end
DCM.OnCast = OnCast

-- The ability a hit on an enemy came from, solo: name and whether it is your
-- pet's, or nil when it cannot be told.
function DCM.GuessAbility(schoolMask, now)
    if not Plain(schoolMask) or type(schoolMask) ~= "number" then
        return nil
    end
    local mine, pet = lastCast.player, lastCast.pet
    if schoolMask == PHYSICAL then
        if mine and now - mine.at <= MELEE_WINDOW then
            return mine.name, false
        end
        if pet and now - pet.at <= MELEE_WINDOW then
            return pet.name, true
        end
        if DCM.petGUID then
            return nil
        end
        return MELEE_NAME, false
    end
    local best, isPet
    for unit, cast in pairs(lastCast) do
        if now - cast.at <= SPELL_WINDOW and (not best or cast.at > best.at) then
            best, isPet = cast, unit == "pet"
        end
    end
    if best then
        return best.name, isPet
    end
end

-- The same hit seen on the target and on its nameplate counts once.
local function Repeated(flagText, amount, schoolMask, now)
    local key = flagText .. ":" .. (Plain(amount) and tostring(amount) or "?") .. ":"
        .. (Plain(schoolMask) and tostring(schoolMask) or "?")
    local repeated = lastWound and now - lastWound.at <= DEDUPE and lastWound.key == key
    lastWound = {at = now, key = key}
    return repeated
end

-- Enemy nameplates shown now, by unit token and by GUID (the combat log
-- names units by GUID); and the other nameplates shown (bystanders: other
-- players, guards), for their hit effects (author, 2026-11-17: someone "not
-- in my group, and they were not being targeted ... I could still see their
-- bloodsplatter as if they were an enemy mob, and, I liked it").
local plates, plateGUIDs = {}, {}
local bystanders, bystanderGUIDs = {}, {}

local function Enemy(unit)
    if type(UnitCanAttack) ~= "function" then
        return true
    end
    local enemy = UnitCanAttack("player", unit)
    return Plain(enemy) and enemy == true
end

local function PlateAdded(unit)
    local guid = type(UnitGUID) == "function" and UnitGUID(unit) or nil
    if not Plain(unit) or not Plain(guid) or guid == nil or guid == DCM.playerGUID then
        return
    end
    if Enemy(unit) then
        plates[unit] = guid
        plateGUIDs[guid] = (plateGUIDs[guid] or 0) + 1
    else
        bystanders[unit] = guid
        bystanderGUIDs[guid] = (bystanderGUIDs[guid] or 0) + 1
    end
end

-- The unit token for an enemy GUID from the combat log, for the spray on
-- its nameplate: your target, or a shown enemy nameplate; else nil.
function DCM.PlateUnit(guid)
    if guid == nil or not Plain(guid) then
        return nil
    end
    if guid == DCM.targetGUID then
        return "target"
    end
    for unit, plateGUID in pairs(plates) do
        if plateGUID == guid then
            return unit
        end
    end
    for unit, plateGUID in pairs(bystanders) do
        if plateGUID == guid then
            return unit
        end
    end
end

local function PlateRemoved(unit)
    if Plain(unit) and DCM.ReleaseSprays then
        -- Nameplates are reused: a spray never moves on to the next enemy.
        DCM.ReleaseSprays(unit)
    end
    if not Plain(unit) then
        return
    end
    local guid = plates[unit]
    if guid then
        plates[unit] = nil
        plateGUIDs[guid] = plateGUIDs[guid] > 1 and plateGUIDs[guid] - 1 or nil
    end
    guid = bystanders[unit]
    if guid then
        bystanders[unit] = nil
        bystanderGUIDs[guid] = bystanderGUIDs[guid] > 1 and bystanderGUIDs[guid] - 1 or nil
    end
end

-- Whether others' crits on this GUID play: your target (My target, Nearby
-- enemies), or a shown enemy nameplate (Nearby enemies).
function DCM.OthersOn(destGUID)
    local scope = DCM.db.othersScope
    if scope == "off" or destGUID == nil then
        return false
    end
    if destGUID == DCM.targetGUID then
        return Enemy("target")
    end
    return scope == "nearby" and plateGUIDs[destGUID] ~= nil
end

-- Whether a hit on this GUID plays as a bystander's: your friendly target
-- (My target, Nearby enemies), or another nameplate shown (Nearby enemies).
function DCM.BystanderOn(destGUID)
    local scope = DCM.db.othersScope
    if scope == "off" or destGUID == nil or destGUID == DCM.playerGUID then
        return false
    end
    if destGUID == DCM.targetGUID then
        return not Enemy("target")
    end
    return scope == "nearby" and bystanderGUIDs[destGUID] ~= nil
end

local function OnUnitCombat(unit, action, flagText, amount, schoolMask)
    if not Plain(unit) or not Plain(action) or not Plain(flagText) then
        return
    end
    if unit == "player" then
        -- Every hit and heal on you plays on you.
        if action == "WOUND" or action == "HEAL" then
            DCM.PlayHit({kind = "taken", school = School(schoolMask), crit = flagText == "CRITICAL",
                heal = action == "HEAL"})
        end
        if action == "WOUND" and TAKEN_FLAGS[flagText] and DCM.db.taken then
            DCM.PlayCrit({kind = "taken", school = School(schoolMask)})
        elseif action == "HEAL" and flagText == "CRITICAL" and DCM.db.heals and not InGroup() then
            -- Solo, a crit heal on you is most likely yours.
            DCM.PlayCrit({kind = "mine", heal = true, school = School(schoolMask)})
        end
        return
    end
    if action == "HEAL" and unit == "target" then
        -- A heal on your (friendly) target, on its plate when one shows.
        DCM.PlayHit({kind = "mine", unit = unit, crit = flagText == "CRITICAL", heal = true})
        return
    end
    if action ~= "WOUND" or not DCM.EnemyUnit(unit) then
        return
    end
    local now = GetTime()
    if Repeated(flagText, amount, schoolMask, now) then
        return
    end
    -- A unit you cannot attack (author: "enemies only") is never your hit:
    -- a bystander (another player, a guard, your friendly target), by the
    -- Others' crits setting: its hit effect, and a crit as others' crits
    -- (author: "put the crit splatter from other's crits back"); never a
    -- record.
    if not Enemy(unit) then
        local scope = DCM.db.othersScope
        if unit == "target" and scope ~= "off" or scope == "nearby" and unit:find("^nameplate%d+$") then
            local critical = flagText == "CRITICAL"
            DCM.PlayHit({kind = "others", bystander = true, school = School(schoolMask), unit = unit,
                crit = critical})
            if critical then
                DCM.PlayCrit({kind = "others", school = School(schoolMask), unit = unit})
            end
        end
        return
    end
    local critical = flagText == "CRITICAL"
    Count("hits")
    if InGroup() then
        Count("grouped")
        -- Anyone's: your target, or with Nearby enemies an enemy nameplate;
        -- no record.
        local scope = DCM.db.othersScope
        if unit == "target" and scope ~= "off"
                or scope == "nearby" and unit:find("^nameplate%d+$") then
            DCM.PlayHit({kind = "others", school = School(schoolMask), unit = unit, crit = critical})
            if critical then
                DCM.PlayCrit({kind = "others", school = School(schoolMask), unit = unit})
            end
        end
        return
    end
    local name, isPet = DCM.GuessAbility(schoolMask, now)
    if not Plain(schoolMask) or type(schoolMask) ~= "number" then
        Count("secretSchool")
    elseif not name then
        Count("noCast")
    end
    local readable = Plain(amount) and type(amount) == "number" and amount > 0
    if not Plain(amount) then
        DCM.amountsReadable = false
        Count("secretAmount")
    elseif not readable then
        Count("noAmount")
    end
    if readable then
        DCM.amountsReadable = true
    end
    local big = false
    if name and readable then
        Count("recorded")
        big = DCM.Record(name, amount, critical, isPet, false)
    end
    local kind = isPet and "pet" or "mine"
    if DCM.db[kind] then
        DCM.PlayHit({kind = kind, school = School(schoolMask), unit = unit, crit = critical, big = big})
        if critical then
            DCM.PlayCrit({kind = kind, big = big, school = School(schoolMask), unit = unit})
        end
    end
end
DCM.OnUnitCombat = OnUnitCombat

local function UpdatePet()
    local guid = type(UnitGUID) == "function" and UnitGUID("pet") or nil
    DCM.petGUID = Plain(guid) and guid or nil
end

-- Druid forms whose crits are a beast's (Naturalist's claws): Cat 768, Bear
-- 5487, Dire Bear 9634. GetShapeshiftFormInfo's fourth value is the form's
-- spell (the pinned StanceBar.lua; Dyre's Buff Reminders reads it the same
-- way). Cached on UPDATE_SHAPESHIFT_FORM; unreadable or secret: no form.
local FERAL_FORMS = {[768] = true, [5487] = true, [9634] = true}

local function UpdateForm()
    DCM.feralForm = false
    if type(GetNumShapeshiftForms) ~= "function" or type(GetShapeshiftFormInfo) ~= "function" then
        return
    end
    local count = GetNumShapeshiftForms()
    if not Plain(count) or type(count) ~= "number" then
        return
    end
    for index = 1, count do
        local _, active, _, spellID = GetShapeshiftFormInfo(index)
        if Plain(active) and active == true then
            DCM.feralForm = Plain(spellID) and FERAL_FORMS[spellID] == true
            return
        end
    end
end
DCM.UpdateForm = UpdateForm

-- A Hunter's pet is a beast (its crits claw on Naturalist); any other class's
-- pet (a Warlock's demon) is not. The class never changes, so read once.
local function UpdateClass()
    local _, class = nil, nil
    if type(UnitClass) == "function" then
        _, class = UnitClass("player")
    end
    DCM.beastPet = Plain(class) and class == "HUNTER"
end

local function UpdateTarget()
    local guid = type(UnitGUID) == "function" and UnitGUID("target") or nil
    DCM.targetGUID = Plain(guid) and guid or nil
end

function DCM.InitializeDetect()
    local guid = UnitGUID("player")
    DCM.playerGUID = Plain(guid) and guid or nil
    UpdatePet()
    UpdateTarget()
    UpdateForm()
    UpdateClass()
    events = CreateFrame("Frame")
    events:RegisterUnitEvent("UNIT_PET", "player")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    local info = EventInfoFunction()
    if DCM.CombatLogUsable() and DCM.playerGUID then
        mode = "combatlog"
        events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        mode = "unitcombat"
        -- Every unit: the target, focus, and nameplates, and you.
        events:RegisterEvent("UNIT_COMBAT")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
    end
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            OnCombatLog(info())
        elseif event == "UNIT_COMBAT" then
            OnUnitCombat(...)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnCast(...)
        elseif event == "UNIT_PET" then
            UpdatePet()
        elseif event == "PLAYER_TARGET_CHANGED" then
            UpdateTarget()
        elseif event == "UPDATE_SHAPESHIFT_FORM" then
            UpdateForm()
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            PlateAdded(...)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            PlateRemoved(...)
        end
    end)
end
