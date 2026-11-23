local addonName, DCM = ...

-- Dyre's Crit Mayhem: opt-in mayhem on crits (author's design). A theme says
-- what the effects look and sound like (Tame's butterflies and stars, the
-- default; Brutal's blood, locked until the account's 18+ box is ticked); an
-- intensity from Low (the default) to Total Mayhem says how much, how big,
-- and how long; the None theme turns it all off. A personal record tracker
-- keeps each ability's highest hit and crit.
-- This file owns the saved settings, the intensity, the 18+ lock, migration
-- from earlier test builds, the login banner, install checks, the lock, slash
-- commands, and startup.
-- Never changes a CVar but the violence level (DCM.ApplyGore): volume and
-- sound stay out (author).
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
-- on screen and fading out, before the "Stays on screen" scale. Low is the
-- default. Off moved to the Theme dropdown as None (author: "Move 'None'
-- (zero) from the slider ... to the Theme selector"); a saved "off" becomes
-- None at Low. Records count at every intensity. Low to
-- Total Mayhem carry the earlier Fun, Spicy, Gory, and Mature numbers. The
-- top step's key stays "max" (author renamed it "Total Mayhem"), so saved
-- settings carry over. violence: the game's violence level (0-5, its blood
-- on hit models) a mature theme sets at this step (author: "the slot before
-- Max and Max could set it to 5, with gradients in between"; None leaves the
-- player's own level, not 0, which would take away the game's own blood);
-- see DCM.ApplyGore.
DCM.INTENSITIES = {
    {key = "low", name = "Low", splats = 1, size = 0.5, hold = 1.6, fade = 0.9, violence = 3},
    {key = "medium", name = "Medium", splats = 2, size = 0.7, hold = 2.8, fade = 1.2, violence = 4},
    {key = "high", name = "High", splats = 4, size = 0.9, hold = 5.5, fade = 1.5, violence = 5},
    {key = "max", name = "Total Mayhem", splats = 7, size = 1.15, hold = 10, fade = 2, violence = 5},
}
DCM.INTENSITY_INDEX = {}
for index, intensity in ipairs(DCM.INTENSITIES) do
    DCM.INTENSITY_INDEX[intensity.key] = index
end
DCM.DEFAULT_INTENSITY = "low"
-- "Stays on screen" (author): a percent of the intensity's hold and fade.
DCM.STAY_MIN, DCM.STAY_MAX, DCM.STAY_STEP, DCM.STAY_DEFAULT = 25, 300, 25, 100
DCM.DEFAULT_THEME = "tame"
-- Earlier test builds' levels (0.1.0 in development): each one's theme and
-- intensity. Brutal only with the 18+ box, else Tame.
local OLD_LEVELS = {
    off = {theme = "none", intensity = "low"},
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
    spray = true,       -- hit effects on enemies (on their nameplates)
    hitsOnYou = true,   -- hit effects on your character
    mine = true,        -- your own crits
    pet = false,        -- your pet's crits
    taken = false,      -- crits that hit you
    heals = false,      -- crit heals too (effects and records)
    randomEffects = false, -- Tame: its playful mix for every damage school
    clawsInForm = false, -- Naturalist: claws and bites only in Cat or Bear form
    announceParty = false,
    announceGuild = false,
    announceScreen = false,
}
DCM.FLAGS = FLAGS
DCM.OTHERS_SCOPES = {off = true, target = true, nearby = true}
DCM.DEFAULT_OTHERS_SCOPE = "nearby"
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

-- Dyre's Toolkit 2.14.0's "Welcome messages at login" (John, 2026-11-23:
-- "toggle off our welcome messages unless there is an error/problem").
-- Without ShowWelcome (an older toolkit, or none), the banner prints as before.
-- It skips only the banner and the ready line; problems always print.
local function WelcomeShown()
    local toolkit = _G.DyresToolkit
    return not (type(toolkit) == "table" and type(toolkit.ShowWelcome) == "function"
        and toolkit.ShowWelcome() == false)
end

local function ReportLoaded(available)
    if not WelcomeShown() then
        return
    end
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
    -- Intensity Off (0.2.1 and older): the None theme at Low.
    if db.intensity == "off" then
        db.theme, db.intensity = DCM.NONE_THEME, DCM.DEFAULT_INTENSITY
    end
    if not DCM.INTENSITY_INDEX[db.intensity] then
        db.intensity = DCM.DEFAULT_INTENSITY
    end
    if type(db.theme) ~= "string" then
        db.theme = DCM.DEFAULT_THEME
    end
    db.stay = DCM.SanitizeStay(db.stay)
    -- Others' crits (effects only, never records): off, on your target, or
    -- on your target and nearby enemies (the default). 0.1.0's "Guess my
    -- crits in a group" and a test build's on/off switch are replaced.
    if db.others == false and db.othersScope == nil then
        db.othersScope = "off"
    end
    if not DCM.OTHERS_SCOPES[db.othersScope] then
        db.othersScope = DCM.DEFAULT_OTHERS_SCOPE
    end
    db.others, db.groupGuess = nil, nil
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
    -- The player's own violence level, kept while a mature theme has raised
    -- it (DCM.ApplyGore); nil when DCM has not changed it.
    local own = tonumber(db.violenceOwn)
    db.violenceOwn = own and own >= 0 and own <= 5 and tostring(math.floor(own)) or nil
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
    DCM.ApplyGore()
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
    DCM.ApplyGore()
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
    DCM.ApplyGore()
    if type(DCM.RefreshOptions) == "function" then
        DCM.RefreshOptions()
    end
end

-- The game's gore (author: "If we can figure out how to make it work, we
-- already have a slider and a setting"; the one CVar DCM changes, by the
-- author's ruling: never volume or mute). A mature theme (Brutal, Fel,
-- Naturalist) at Low to Total Mayhem sets the violence level to its step's
-- `violence`, first keeping the player's own level account-wide (the
-- CVar is account-wide); None, a cute theme, or the 18+ box cleared puts the
-- player's own level back. Only when the client has the CVar; in combat it
-- waits for combat to end.
local VIOLENCE_CVAR = "violenceLevel"
local goreWaiting

local function GetViolence()
    local value
    if type(C_CVar) == "table" and type(C_CVar.GetCVar) == "function" then
        value = C_CVar.GetCVar(VIOLENCE_CVAR)
    elseif type(GetCVar) == "function" then
        value = GetCVar(VIOLENCE_CVAR)
    end
    if DCM.IsSecret(value) or value == nil then
        return nil
    end
    return tostring(value)
end

local function SetViolence(value)
    if type(C_CVar) == "table" and type(C_CVar.SetCVar) == "function" then
        C_CVar.SetCVar(VIOLENCE_CVAR, value)
    elseif type(SetCVar) == "function" then
        SetCVar(VIOLENCE_CVAR, value)
    end
end

-- The level DCM wants now, or nil to leave the player's own.
function DCM.GoreLevel()
    if not DCM.db or not DCM.Theme().mature or not DCM.IsAdult() then
        return nil
    end
    return DCM.Intensity().violence
end

function DCM.ApplyGore()
    if not DCM.db or not DCM.account then
        return
    end
    local current = GetViolence()
    if current == nil then
        return
    end
    if InCombatLockdown() then
        if not goreWaiting then
            goreWaiting = CreateFrame("Frame")
            goreWaiting:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                DCM.ApplyGore()
            end)
        end
        goreWaiting:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local level = DCM.GoreLevel()
    if level then
        if DCM.account.violenceOwn == nil then
            DCM.account.violenceOwn = current
        end
        if current ~= tostring(level) then
            SetViolence(tostring(level))
        end
    elseif DCM.account.violenceOwn ~= nil then
        if current ~= DCM.account.violenceOwn then
            SetViolence(DCM.account.violenceOwn)
        end
        DCM.account.violenceOwn = nil
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
    -- Why solo hits made no record (combat text only; zero on the combat log).
    DCM.Report("debug: since login " .. DCM.RecordCountsText())
end

-- The Dyre's Toolkit Profile (Toolkit 2.10.0; John, 2026-11-17: "one place
-- to go to persist your profile"; ../DyresToolkit/docs/PROFILES.md). DCM's
-- part is DyresCritMayhemDB: the theme, intensity, stay, others' scope, the
-- flags, the sound picks, the record pop's place and scale (pop), and the
-- records window's sort. These stay with the character, never copied,
-- exported, or imported: records (this character's own crits) and probe
-- (a /dcm probe log for the author). The account's 18+ box and the
-- player's own violence level (DyresCritMayhemAccountDB) are not in a
-- profile (John: account-wide is "user-centric, not per character").
DCM.PROFILE_CHARACTER_KEYS = {"records", "probe"}

-- A full, repaired settings table from any table (empty, partial, older,
-- newer, or another character's). Keys DCM does not know are dropped (an
-- imported line's junk or a newer version's). A mature theme needs this
-- account's 18+ box, as at login: a line from an account without it gets
-- Tame.
local PROFILE_KEYS = {intensity = true, theme = true, stay = true, othersScope = true, soundPicks = true,
    records = true, pop = true, sortKey = true, sortDescending = true, probe = true}
for key in pairs(FLAGS) do
    PROFILE_KEYS[key] = true
end

function DCM.SanitizeProfile(settings)
    local db = DCM.SanitizeDB(settings)
    for key in pairs(db) do
        if not PROFILE_KEYS[key] then
            db[key] = nil
        end
    end
    local theme = DCM.FindTheme(db.theme)
    if not theme or (theme.mature and not (DCM.account and DCM.account.adult == true)) then
        db.theme = DCM.DEFAULT_THEME
    end
    return db
end

-- Live apply after a copy or import: the Toolkit has written the part into
-- DCM.db in place (pop is the same table, so the widget's store sees it).
-- Everything that reads the settings reads them on each crit or hit, so
-- this sets again only what was set once: the game's gore (18+ only), the
-- record pop's place and scale, the settings page's sound rows, and an open
-- records window's sort.
function DCM.ApplyProfile()
    DCM.SanitizeTheme()
    DCM.ApplyGore()
    local toolkit = rawget(_G, "DyresToolkit")
    if DCM.popWidget and type(toolkit) == "table" and type(toolkit.ReapplyWidgets) == "function" then
        toolkit.ReapplyWidgets(addonName)
    end
    if type(DCM.RefreshOptions) == "function" then
        DCM.RefreshOptions()
    end
    if type(DCM.RefreshWindow) == "function" then
        DCM.RefreshWindow()
    end
end

-- With a toolkit older than 2.10.0 nothing changes.
local function JoinProfile(toolkit)
    if type(toolkit.RegisterProfilePart) ~= "function" then
        return
    end
    toolkit.RegisterProfilePart({
        addon = addonName,
        title = DCM.Title(),
        current = function() return DyresCritMayhemDB end,
        sanitize = DCM.SanitizeProfile,
        characterKeys = DCM.PROFILE_CHARACTER_KEYS,
        refresh = DCM.ApplyProfile,
    })
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
    -- Before the frames: they read the settings a waiting part may change.
    JoinProfile(toolkit)
    -- Called here rather than from each file's own PLAYER_LOGIN handler, so
    -- startup never depends on event handler order.
    DCM.InitializeEffects()
    DCM.InitializeRecords()
    DCM.InitializeDetect()
    DCM.InitializeOptions()
    DCM.ApplyGore()
    toolkit.RegisterAddOn({addon = addonName, title = DCM.Title(), openSettings = DCM.OpenSettings})
end)
