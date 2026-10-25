local _, DCM = ...

-- /dcm probe: a launch-day check for WoW: Forever (author: "we absolutely
-- MUST make this work in Forever"), useful on any client. For PROBE_SECONDS
-- it logs what the client tells AddOns about hits: every UNIT_COMBAT (unit,
-- event, flag, amount, school, which of them are secret, and the ability DCM
-- would guess), your and your pet's casts, and after each fight a dump of the
-- damage meter (C_DamageMeter). The first CHAT_LINES lines go to chat; all
-- of them (up to SAVED_LINES) to DyresCritMayhemDB.probe, written to the
-- SavedVariables file on /reload or logout. Values are never compared or
-- printed when secret: they read "<secret>".
local PROBE_SECONDS = 180
local CHAT_LINES = 40
local SAVED_LINES = 600
local METER_SOURCES = 10
local METER_SPELLS = 20

local frame
local said = 0

local function Describe(value)
    if DCM.IsSecret(value) then
        return "<secret>"
    end
    return tostring(value)
end

-- "S" for each secret value, "-" for each plain one.
local function Secrets(...)
    local marks = {}
    for index = 1, select("#", ...) do
        marks[index] = DCM.IsSecret((select(index, ...))) and "S" or "-"
    end
    return table.concat(marks)
end

local function Line(text)
    local lines = DCM.db.probe.lines
    if #lines < SAVED_LINES then
        lines[#lines + 1] = text
    end
    said = said + 1
    if said <= CHAT_LINES then
        DCM.Report("probe: " .. text)
    elseif said == CHAT_LINES + 1 then
        DCM.Report("probe: more lines go to the saved log only (/reload writes it).")
    end
end

local function SpellName(spellID)
    if DCM.IsSecret(spellID) or type(spellID) ~= "number" or type(C_Spell) ~= "table"
            or type(C_Spell.GetSpellName) ~= "function" then
        return "?"
    end
    return Describe(C_Spell.GetSpellName(spellID))
end

local function OnUnitCombat(unit, action, flagText, amount, schoolMask)
    local text = ("UNIT_COMBAT %s %s %s amount=%s school=%s secret=%s"):format(Describe(unit), Describe(action),
        Describe(flagText), Describe(amount), Describe(schoolMask),
        Secrets(unit, action, flagText, amount, schoolMask))
    if not DCM.IsSecret(unit) and not DCM.IsSecret(action) and action == "WOUND" and DCM.EnemyUnit(unit) then
        local name, isPet = DCM.GuessAbility(schoolMask, GetTime())
        text = text .. " guess=" .. (name or "none") .. (isPet and " (pet)" or "")
    end
    Line(text)
end

local function OnCast(unit, _, spellID)
    local harmful = "?"
    if not DCM.IsSecret(spellID) and type(spellID) == "number" and type(C_Spell) == "table"
            and type(C_Spell.IsSpellHarmful) == "function" then
        harmful = Describe(C_Spell.IsSpellHarmful(spellID))
    end
    Line(("CAST %s spell=%s %s harmful=%s secret=%s"):format(Describe(unit), Describe(spellID), SpellName(spellID),
        harmful, Secrets(spellID)))
end

-- Your spells in the fight just over: totals per spell, and what maxAmount
-- holds (DCM reads it as the bars' scale, not a largest hit).
local function DumpMySpells(current, damage)
    if type(C_DamageMeter.GetCombatSessionSourceFromType) ~= "function" or not DCM.playerGUID then
        return
    end
    local mine = C_DamageMeter.GetCombatSessionSourceFromType(current, damage, DCM.playerGUID)
    if DCM.IsSecret(mine) or type(mine) ~= "table" or DCM.IsSecret(mine.combatSpells)
            or type(mine.combatSpells) ~= "table" then
        Line("meter: my source " .. Describe(mine))
        return
    end
    Line(("meter: my spells %d, maxAmount=%s total=%s"):format(#mine.combatSpells, Describe(mine.maxAmount),
        Describe(mine.totalAmount)))
    for index, spell in ipairs(mine.combatSpells) do
        if index > METER_SPELLS then
            break
        end
        local details = not DCM.IsSecret(spell.combatSpellDetails) and type(spell.combatSpellDetails) == "table"
            and spell.combatSpellDetails or {}
        Line(("meter spell: %s %s total=%s detailAmount=%s isPet=%s"):format(Describe(spell.spellID),
            SpellName(spell.spellID), Describe(spell.totalAmount), Describe(details.amount),
            Describe(details.isPet)))
    end
end

local function DumpMeter()
    if type(C_DamageMeter) ~= "table" or type(C_DamageMeter.GetCombatSessionFromType) ~= "function"
            or type(Enum) ~= "table" or type(Enum.DamageMeterSessionType) ~= "table"
            or type(Enum.DamageMeterType) ~= "table" then
        Line("meter: C_DamageMeter is not on this client")
        return
    end
    local current, damage = Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone
    local session = C_DamageMeter.GetCombatSessionFromType(current, damage)
    if DCM.IsSecret(session) or type(session) ~= "table" or DCM.IsSecret(session.combatSources)
            or type(session.combatSources) ~= "table" then
        Line("meter: session " .. Describe(session))
        return
    end
    Line(("meter: %d sources, maxAmount=%s total=%s"):format(#session.combatSources, Describe(session.maxAmount),
        Describe(session.totalAmount)))
    for index, source in ipairs(session.combatSources) do
        if index > METER_SOURCES then
            break
        end
        Line(("meter source %d: local=%s name=%s total=%s guidSecret=%s"):format(index,
            Describe(source.isLocalPlayer), Describe(source.name), Describe(source.totalAmount),
            DCM.IsSecret(source.sourceGUID) and "yes" or "no"))
    end
    DumpMySpells(current, damage)
end

local function Header()
    if type(GetBuildInfo) == "function" then
        local version, build, _, interface = GetBuildInfo()
        Line(("client %s build %s interface %s"):format(Describe(version), Describe(build), Describe(interface)))
    end
    local restricted = type(C_CombatLog) == "table" and type(C_CombatLog.IsCombatLogRestricted) == "function"
        and C_CombatLog.IsCombatLogRestricted()
    Line(("detection=%s combatLogRestricted=%s inGroup=%s pet=%s"):format(DCM.DetectionMode(),
        Describe(restricted), Describe(type(IsInGroup) == "function" and IsInGroup()), tostring(DCM.petGUID ~= nil)))
    if type(C_DamageMeter) == "table" and type(C_DamageMeter.IsDamageMeterAvailable) == "function" then
        local available, reason = C_DamageMeter.IsDamageMeterAvailable()
        Line(("meter available=%s reason=%s"):format(Describe(available), Describe(reason)))
    else
        Line("meter: C_DamageMeter is not on this client")
    end
end

function DCM.StopProbe()
    if not frame or not frame.running then
        return
    end
    frame.running = false
    frame:UnregisterEvent("UNIT_COMBAT")
    frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    DCM.Report(("probe: done, %d lines saved to DyresCritMayhemDB.probe; /reload writes them to the "
        .. "SavedVariables file."):format(#DCM.db.probe.lines))
end

function DCM.StartProbe()
    if not DCM.db then
        DCM.Report("probe: not loaded yet.")
        return
    end
    if frame and frame.running then
        DCM.Report("probe: already running.")
        return
    end
    frame = frame or CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_COMBAT" then
            OnUnitCombat(...)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnCast(...)
        elseif event == "PLAYER_REGEN_DISABLED" then
            Line("combat starts")
        elseif event == "PLAYER_REGEN_ENABLED" then
            Line("combat ends")
            DumpMeter()
        end
    end)
    DCM.db.probe = {lines = {}}
    said = 0
    frame.running = true
    DCM.Report(("probe: logging hits for %d minutes; fight something, solo and in a group, and use /dcm test.")
        :format(PROBE_SECONDS / 60))
    Header()
    frame:RegisterEvent("UNIT_COMBAT")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    C_Timer.After(PROBE_SECONDS, DCM.StopProbe)
end
