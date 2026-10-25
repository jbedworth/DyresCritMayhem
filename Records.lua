local addonName, DCM = ...

-- Personal records (author: "definitely include"): per character, each
-- ability's highest hit and highest crit, yours and your pet's (and heals,
-- with the heals option). A new record always says so in your chat, seen
-- only by you; it can also go to party, guild, and an on-screen pop (a
-- Dyre's Toolkit widget). An ability's first hit or crit sets its record
-- quietly, or every first swing of the day would be "a new record".
local POP_WIDTH, POP_HEIGHT = 320, 58
local POP_PLACE = {point = "CENTER", relativePoint = "CENTER", x = 0, y = 190}
local POP_HOLD, POP_FADE = 2.5, 1.0
-- Party and guild hear at most one record in this many seconds; your own
-- chat hears them all.
local ANNOUNCE_GAP = 10
local GOLD = {1, 0.82, 0}
local RESET_POPUP = "DYRESCRITMAYHEM_RESET_RECORDS"

local pop
local lastAnnounce = -math.huge

function DCM.RecordKey(name, pet, heal)
    return (pet and "pet:" or "") .. (heal and "heal:" or "") .. name
end

-- How a record's ability reads: "Claw (pet)", "Flash Heal (heal)".
function DCM.RecordLabel(record)
    local label = record.name
    if record.pet then
        label = label .. " (pet)"
    end
    if record.heal then
        label = label .. " (heal)"
    end
    return label
end

function DCM.FormatAmount(amount)
    if type(BreakUpLargeNumbers) == "function" then
        return BreakUpLargeNumbers(amount)
    end
    return tostring(amount)
end

local function SendChat(message, channel)
    if type(C_ChatInfo) == "table" and type(C_ChatInfo.SendChatMessage) == "function" then
        C_ChatInfo.SendChatMessage(message, channel)
    elseif type(SendChatMessage) == "function" then
        SendChatMessage(message, channel)
    end
end

local function ShowPop(title, line)
    if not pop then
        return
    end
    pop.title:SetText(title)
    pop.line:SetText(line)
    pop.fader:Stop()
    pop.content:SetAlpha(1)
    pop.content:Show()
    pop.fader:Play()
end

local function Announce(record, field, amount, previous)
    local what = DCM.RecordLabel(record) .. " " .. field
    DCM.Report("New record! " .. what .. " " .. DCM.FormatAmount(amount) .. " (was "
        .. DCM.FormatAmount(previous) .. ").")
    if DCM.db.announceScreen then
        ShowPop("New record!", what .. " " .. DCM.FormatAmount(amount))
    end
    if not DCM.db.announceParty and not DCM.db.announceGuild then
        return
    end
    if GetTime() - lastAnnounce < ANNOUNCE_GAP then
        return
    end
    local message = "[Crit Mayhem] New personal record: " .. what .. " " .. DCM.FormatAmount(amount) .. "!"
    local sent = false
    if DCM.db.announceParty and type(IsInGroup) == "function" and IsInGroup() then
        SendChat(message, "PARTY")
        sent = true
    end
    if DCM.db.announceGuild and type(IsInGuild) == "function" and IsInGuild() then
        SendChat(message, "GUILD")
        sent = true
    end
    if sent then
        lastAnnounce = GetTime()
    end
end

-- One hit or heal of yours or your pet's (plain values; Detect checks). Returns
-- true when it is a new crit record, which the effects make bigger.
function DCM.Record(name, amount, critical, pet, heal)
    if amount <= 0 then
        return false
    end
    local key = DCM.RecordKey(name, pet, heal)
    local record = DCM.db.records[key]
    if not record then
        record = {name = name, pet = pet or nil, heal = heal or nil}
        DCM.db.records[key] = record
    end
    local field = critical and "crit" or "hit"
    local previous = record[field]
    if previous and amount <= previous then
        return false
    end
    record[field] = amount
    if DCM.RefreshWindow then
        DCM.RefreshWindow()
    end
    if not previous then
        return false
    end
    Announce(record, field, amount, previous)
    return critical == true
end

function DCM.ResetRecords()
    DCM.db.records = {}
    DCM.Report("Your records on this character are cleared.")
    if DCM.RefreshWindow then
        DCM.RefreshWindow()
    end
end

-- Asks first, and never in combat (no popups in combat).
function DCM.ConfirmResetRecords()
    if InCombatLockdown() then
        DCM.Report("Records can be reset out of combat.")
        return
    end
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then
        DCM.ResetRecords()
        return
    end
    StaticPopupDialogs[RESET_POPUP] = StaticPopupDialogs[RESET_POPUP] or {
        text = "Clear every Crit Mayhem record on this character? This cannot be undone.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function() DCM.ResetRecords() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show(RESET_POPUP)
end

-- The pop: a widget the toolkit places, drags, sizes, and saves. Its text
-- lives in a child that fades; the widget itself stays shown, so the
-- toolkit's outline shows while unlocked.
local function BuildPop()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints(frame)
    content:Hide()
    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", content, "TOP", 0, -2)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local line = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    line:SetPoint("TOP", title, "BOTTOM", 0, -4)
    local fader = content:CreateAnimationGroup()
    local fade = fader:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(POP_HOLD)
    fade:SetDuration(POP_FADE)
    fader:SetScript("OnFinished", function() content:Hide() end)
    pop = {frame = frame, content = content, title = title, line = line, fader = fader}
    DCM.pop = pop
    DCM.popWidget = DCM.toolkit.CreateWidget({
        addon = addonName,
        key = DCM.WIDGET_KEY,
        title = "Crit Mayhem record pop",
        frame = frame,
        store = DCM.db.pop,
        width = POP_WIDTH,
        height = POP_HEIGHT,
        point = POP_PLACE,
        sizes = {scale = true},
        -- A sample while unlocked, so there is something to drag.
        onUnlock = function(_, unlocked)
            if unlocked then
                pop.fader:Stop()
                pop.title:SetText("New record!")
                pop.line:SetText("Sinister Strike crit 1,234")
                pop.content:SetAlpha(1)
                pop.content:Show()
            elseif not pop.fader:IsPlaying() then
                pop.content:Hide()
            end
        end,
    })
end

function DCM.InitializeRecords()
    BuildPop()
end
