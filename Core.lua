local addonName, DCM = ...

-- Dyre's Crit Mayhem: opt-in mayhem on crits (author's design). A theme says
-- what the effects look and sound like (Tame's butterflies and stars, the
-- default; Brutal's blood, locked until the account's 18+ box is ticked); an
-- intensity from Off (the default) to Total Mayhem says how much, how big,
-- and how long; a personal record tracker keeps each ability's highest hit and crit.
-- This file owns the saved settings, the intensity, the 18+ lock, migration
-- from earlier test builds, the login banner, install checks, the lock, slash
-- commands, and startup.
-- Never changes a CVar (violence level, volume, sound): the AddOns we learned
-- from did, and that is out (author).
local DEFAULT_TITLE = "Dyre's Crit Mayhem"
local READY_MESSAGE = "  Ready. Type /dcm for your records, /dcm options for the mayhem."
local SLASH_KEY = "DYRESCRITMAYHEM"
local PRIMARY_SLASH = "/dcm"
local BACKUP_SLASH = "/critmayhem"
local MAX_SLASH_ALIASES = 10
local TOOLKIT_CONTRACT = 2
local TOOLKIT_FUNCTIONS = {"RegisterAddOn", "RegisterSettingsCategory", "IsLocked", "SetLocked", "OpenSettings",
    "CreateWidget", "AddWidgetSettings"}
local TOOLKIT_MISSING = "Dyre's Crit Mayhem needs Dyre's Toolkit 2.0 or later: install or update it from "
    .. "CurseForge. DCM stays off until then."
local THEME_LOCKED = "%s is for 18 and over: tick \"I'm 18 or over\" in /dcm options first."

-- The intensity, in slider order (author: "leave the slider for
-- 'Intensity'"), for whichever theme: each step is more, bigger, and longer.
-- splats: how many land per crit; size: of the texture's size
-- (Effects.SPLAT_SIZE, times the theme's own size); hold and fade: seconds
-- on screen and fading out, before the "Stays on screen" scale. Off (the
-- default) turns every effect off; records count at every intensity. Low to
-- Total Mayhem carry the earlier Fun, Spicy, Gory, and Mature numbers. The
-- top step's key stays "max" (author renamed it "Total Mayhem"), so saved
-- settings carry over.
DCM.INTENSITIES = {
    {key = "off", name = "Off"},
    {key = "low", name = "Low", splats = 1, size = 0.5, hold = 1.6, fade = 0.9},
    {key = "medium", name = "Medium", splats = 2, size = 0.7, hold = 2.8, fade = 1.2},
    {key = "high", name = "High", splats = 4, size = 0.9, hold = 5.5, fade = 1.5},
    {key = "max", name = "Total Mayhem", splats = 7, size = 1.15, hold = 10, fade = 2},
}
DCM.INTENSITY_INDEX = {}
for index, intensity in ipairs(DCM.INTENSITIES) do
    DCM.INTENSITY_INDEX[intensity.key] = index
end
DCM.DEFAULT_INTENSITY = "off"
-- "Stays on screen" (author): a percent of the intensity's hold and fade.
DCM.STAY_MIN, DCM.STAY_MAX, DCM.STAY_STEP, DCM.STAY_DEFAULT = 25, 300, 25, 100
DCM.DEFAULT_THEME = "tame"
-- Earlier test builds' levels (0.1.0 in development): each one's theme and
-- intensity. Brutal only with the 18+ box, else Tame.
local OLD_LEVELS = {
    off = {intensity = "off"},
    tame = {theme = "tame", intensity = "low"},
    fun = {theme = "brutal", intensity = "low"},
    spicy = {theme = "brutal", intensity = "medium"},
    gory = {theme = "brutal", intensity = "high"},
    mature = {theme = "brutal", intensity = "max"},
}
DCM.WIDGET_KEY = "recordpop"

-- Per-character settings, with their defaults. Records are kept apart.
local FLAGS = {
    sound = true,       -- the theme's sounds
    splatter = true,    -- the theme's effects on the screen
    mine = true,        -- your own crits
    pet = false,        -- your pet's crits
    taken = false,      -- crits that hit you
    heals = false,      -- crit heals too (effects and records)
    groupGuess = false, -- without the combat log: guess your crits in a group
    announceParty = false,
    announceGuild = false,
    announceScreen = false,
}
DCM.FLAGS = FLAGS
DCM.SORT_KEYS = {name = true, hit = true, crit = true}
DCM.available = false

function DCM.Report(message)
    DEFAULT_CHAT_FRAME:AddMessage("DCM: " .. tostring(message))
end

-- A value the client hides (Forever's secret values) is never compared,
-- printed, or indexed.
function DCM.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

-- Reads TOC fields so the banner follows the packaged version; never gates operations.
local function Metadata(field)
    if type(C_AddOns) ~= "table" or type(C_AddOns.GetAddOnMetadata) ~= "function" then
        return nil
    end
    local value = C_AddOns.GetAddOnMetadata(addonName, field)
    if type(value) == "string" and value:find("%S") then
        return value
    end
end
DCM.Metadata = Metadata

function DCM.Title()
    return Metadata("Title") or DEFAULT_TITLE
end

local function ReportLoaded(available)
    local banner = DCM.Title()
    local version, author = Metadata("Version"), Metadata("Author")
    if version then
        banner = banner .. " " .. version
    end
    if author then
        banner = banner .. " by " .. author
    end
    DCM.Report(banner)
    if available then
        DCM.Report(READY_MESSAGE)
    end
end

-- Functions other runtime files must define. A mixed install of old and new
-- files otherwise fails silently, because the client hides Lua errors by default.
local REQUIRED_NAMESPACE = {"ParseCommand", "HandleCommand", "Theme", "InitializeEffects", "PlayCrit",
    "InitializeDetect", "DetectionMode", "InitializeRecords", "Record", "ToggleWindow", "InitializeOptions",
    "OpenSettings"}

local function CheckInstalledFiles()
    for _, name in ipairs(REQUIRED_NAMESPACE) do
        if type(DCM[name]) ~= "function" then
            return false, "AddOn files are from different versions (missing " .. name
                .. "). Reinstall every Dyre's Crit Mayhem file, then restart the client."
        end
    end
    return true
end

local function Positive(value)
    return type(value) == "number" and value > 0 and value < math.huge and value or nil
end

-- One ability's record: {name, pet, heal, hit, crit}, or nil when damaged.
local function SanitizeRecord(record)
    if type(record) ~= "table" or type(record.name) ~= "string" or not record.name:find("%S") then
        return nil
    end
    local clean = {name = record.name, pet = record.pet == true or nil, heal = record.heal == true or nil,
        hit = Positive(record.hit), crit = Positive(record.crit)}
    if not clean.hit and not clean.crit then
        return nil
    end
    return clean
end

-- A "Stays on screen" percent, on its steps and in range.
function DCM.SanitizeStay(value)
    value = tonumber(value)
    if not value or value ~= value then
        return DCM.STAY_DEFAULT
    end
    value = math.floor(value / DCM.STAY_STEP + 0.5) * DCM.STAY_STEP
    return math.max(DCM.STAY_MIN, math.min(DCM.STAY_MAX, value))
end

-- Seconds an intensity's effects stay (hold and fade), with the stay scale.
function DCM.StaySeconds(intensity, stay)
    if not intensity.splats then
        return 0
    end
    return (intensity.hold + intensity.fade) * (stay or DCM.db.stay) / 100
end

-- Per-character settings in DyresCritMayhemDB, repaired on load so a damaged
-- or older table can never break the AddOn. The theme is checked against the
-- account's 18+ box later (DCM.SanitizeTheme), once both are loaded.
function DCM.SanitizeDB(db)
    db = type(db) == "table" and db or {}
    -- An earlier test build's level: its theme and intensity.
    local old = type(db.level) == "string" and OLD_LEVELS[db.level]
    if old and db.intensity == nil then
        db.intensity = old.intensity
        db.theme = old.theme or db.theme
    end
    db.level = nil
    if not DCM.INTENSITY_INDEX[db.intensity] then
        db.intensity = DCM.DEFAULT_INTENSITY
    end
    if type(db.theme) ~= "string" then
        db.theme = DCM.DEFAULT_THEME
    end
    db.stay = DCM.SanitizeStay(db.stay)
    -- The player's own sound per event: on (it wins over the theme's pool)
    -- and its key, kept across theme changes.
    local picks = type(db.soundPicks) == "table" and db.soundPicks or {}
    for _, event in ipairs({"crit", "big", "extra"}) do
        local pick = type(picks[event]) == "table" and picks[event] or {}
        picks[event] = {on = pick.on == true, key = type(pick.key) == "string" and pick.key or nil}
    end
    db.soundPicks = picks
    for key, default in pairs(FLAGS) do
        if type(db[key]) ~= "boolean" then
            db[key] = default
        end
    end
    local records = {}
    if type(db.records) == "table" then
        for key, record in pairs(db.records) do
            records[key] = type(key) == "string" and SanitizeRecord(record) or nil
        end
    end
    db.records = records
    if type(db.pop) ~= "table" then
        db.pop = {}
    end
    if not DCM.SORT_KEYS[db.sortKey] then
        db.sortKey = "crit"
    end
    db.sortDescending = db.sortDescending ~= false
    return db
end

-- Account-wide: the 18+ box, ticked by the player (author: Brutal is locked
-- until then).
function DCM.SanitizeAccountDB(db)
    db = type(db) == "table" and db or {}
    db.adult = db.adult == true
    return db
end

function DCM.IsAdult()
    return DCM.account.adult == true
end

-- A theme this character may use: a known one, and a mature one (Brutal)
-- only with the 18+ box (author); else the default.
function DCM.SanitizeTheme()
    local theme = DCM.FindTheme(DCM.db.theme)
    if not theme or (theme.mature and not DCM.IsAdult()) then
        DCM.db.theme = DCM.DEFAULT_THEME
    end
end

function DCM.Intensity()
    return DCM.INTENSITIES[DCM.INTENSITY_INDEX[DCM.db.intensity]]
end

function DCM.IntensityIndex()
    return DCM.INTENSITY_INDEX[DCM.db.intensity]
end

-- Sets the intensity by slider index. Returns the index now in effect.
function DCM.SetIntensityIndex(index)
    local intensity = type(index) == "number" and DCM.INTENSITIES[math.floor(index + 0.5)]
    if intensity then
        DCM.db.intensity = intensity.key
    end
    return DCM.IntensityIndex()
end

-- Chooses a theme. A mature one needs the 18+ box: refused with a line, and
-- the theme kept. Returns the theme now in effect.
function DCM.SetTheme(key)
    local theme = DCM.FindTheme(key)
    if not theme then
        return DCM.Theme()
    end
    if theme.mature and not DCM.IsAdult() then
        DCM.Report(THEME_LOCKED:format(theme.name))
        return DCM.Theme()
    end
    DCM.db.theme = theme.key
    return theme
end

function DCM.SetAdult(adult)
    DCM.account.adult = adult == true
    local theme = DCM.Theme()
    if not DCM.account.adult and theme.mature then
        DCM.db.theme = DCM.DEFAULT_THEME
        DCM.ClearEffects()
        DCM.Report(theme.name .. " is locked again; your theme is back to " .. DCM.Theme().name .. ".")
    end
    if type(DCM.RefreshOptions) == "function" then
        DCM.RefreshOptions()
    end
end

-- Another AddOn can register the same slash command; the last one loaded wins.
-- Returns the other command key, or nil when /dcm is ours alone.
local function FindSlashConflict()
    for key in pairs(SlashCmdList) do
        if key ~= SLASH_KEY then
            for index = 1, MAX_SLASH_ALIASES do
                local alias = _G["SLASH_" .. key .. index]
                if type(alias) == "string" and alias:lower() == PRIMARY_SLASH then
                    return key
                end
            end
        end
    end
end

-- Dyre's Toolkit with the contract and functions DCM uses, else nil.
function DCM.Toolkit()
    local toolkit = rawget(_G, "DyresToolkit")
    if type(toolkit) ~= "table" or type(toolkit.RequireContract) ~= "function" then
        return nil
    end
    toolkit = toolkit.RequireContract(TOOLKIT_CONTRACT)
    if type(toolkit) ~= "table" then
        return nil
    end
    for _, name in ipairs(TOOLKIT_FUNCTIONS) do
        if type(toolkit[name]) ~= "function" then
            return nil
        end
    end
    return toolkit
end

-- One layout mode for every Dyre's AddOn: the toolkit says one line for all,
-- draws the outline, and calls the record pop's onUnlock, which shows a sample.
function DCM.Unlock()
    DCM.toolkit.SetLocked(false)
end

function DCM.Lock()
    DCM.toolkit.SetLocked(true)
end

function DCM.ResetPosition()
    DCM.popWidget:ResetPosition()
    DCM.Report("The record pop moved back to its default place.")
end

function DCM.ReportDebug()
    if not DCM.db then
        DCM.Report("debug: not loaded yet.")
        return
    end
    local restricted = type(C_CombatLog) == "table" and type(C_CombatLog.IsCombatLogRestricted) == "function"
        and C_CombatLog.IsCombatLogRestricted()
    local count = 0
    for _ in pairs(DCM.db.records) do
        count = count + 1
    end
    DCM.Report("debug: detection=" .. tostring(DCM.DetectionMode()) .. " combatLogRestricted="
        .. tostring(restricted == true) .. " theme=" .. DCM.Theme().key .. " intensity=" .. DCM.db.intensity
        .. " adult=" .. tostring(DCM.IsAdult()) .. " stay=" .. DCM.db.stay
        .. " sounds=" .. tostring(DCM.SoundLibrary() ~= nil)
        .. " records=" .. count)
end

SLASH_DYRESCRITMAYHEM1 = PRIMARY_SLASH
SLASH_DYRESCRITMAYHEM2 = BACKUP_SLASH
SlashCmdList[SLASH_KEY] = function(message) DCM.HandleCommand(message) end

local function LoadDB()
    DyresCritMayhemDB = DCM.SanitizeDB(DyresCritMayhemDB)
    DyresCritMayhemAccountDB = DCM.SanitizeAccountDB(DyresCritMayhemAccountDB)
    DCM.db, DCM.account = DyresCritMayhemDB, DyresCritMayhemAccountDB
    DCM.SanitizeTheme()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, loadedName)
    if event == "ADDON_LOADED" then
        if loadedName == addonName then
            self:UnregisterEvent("ADDON_LOADED")
            LoadDB()
        end
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
    local available, message = CheckInstalledFiles()
    if available and not DCM.db then
        LoadDB()
    end
    DCM.available = available
    ReportLoaded(available)
    local conflict = FindSlashConflict()
    if conflict then
        DCM.Report("Another AddOn (" .. conflict .. ") also uses " .. PRIMARY_SLASH
            .. ". Use " .. BACKUP_SLASH .. " instead.")
    end
    if not available then
        DCM.Report(message)
        return
    end
    local toolkit = DCM.Toolkit()
    if not toolkit then
        DCM.available = false
        DCM.Report(TOOLKIT_MISSING)
        return
    end
    DCM.toolkit = toolkit
    -- Called here rather than from each file's own PLAYER_LOGIN handler, so
    -- startup never depends on event handler order.
    DCM.InitializeEffects()
    DCM.InitializeRecords()
    DCM.InitializeDetect()
    DCM.InitializeOptions()
    toolkit.RegisterAddOn({addon = addonName, title = DCM.Title(), openSettings = DCM.OpenSettings})
end)
