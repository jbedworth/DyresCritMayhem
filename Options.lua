local _, DCM = ...

-- One settings page, "Crit Mayhem" under Dyre's Toolkit's "Dyre's AddOns"
-- (Blizzard's vertical layout, proxy settings on DyresCritMayhemDB). The 18+
-- box that unlocks Brutal comes first (author), then the theme, the intensity
-- and how long effects stay, which crits count, and the records.
local TITLE = "Dyre's Crit Mayhem"
local UNAVAILABLE = "The AddOn settings page is unavailable on this client. Use /dcm and /dcm test."
local THEME_VARIABLE = "DCM_THEME"
local INTENSITY_VARIABLE = "DCM_INTENSITY"
local STAY_VARIABLE = "DCM_STAY"

local REQUIRED_SETTINGS = {
    "RegisterProxySetting", "CreateCheckbox", "CreateSlider", "CreateSliderOptions", "CreateDropdown",
    "CreateControlTextContainer", "OpenToCategory",
}

local category, layout
-- The Sounds rows' initializers, and our section headers.
local soundRows, quietHeaders = {}, {}

local function HasSettingsAPI()
    if type(Settings) ~= "table" or type(Settings.VarType) ~= "table" then
        return false
    end
    for _, name in ipairs(REQUIRED_SETTINGS) do
        if type(Settings[name]) ~= "function" then
            return false
        end
    end
    return true
end

local function Proxy(variable, variableType, name, default, getValue, setValue)
    return Settings.RegisterProxySetting(category, variable, variableType, name, default, getValue, setValue)
end

-- A checkbox for one saved flag.
local function Flag(variable, name, key, tooltip)
    local setting = Proxy(variable, Settings.VarType.Boolean, name, DCM.FLAGS[key],
        function() return DCM.db[key] end,
        function(value) DCM.db[key] = value == true end)
    return Settings.CreateCheckbox(category, setting, tooltip)
end

-- Blizzard's section header shows its own name as a tooltip when hovered
-- (InitializeSettingTooltip); ours say nothing more, so it is hidden again
-- (author: the "Which crits" tooltip just said "Which crits"). Header frames
-- are pooled with other pages, so the hook acts only while one of ours uses
-- the frame.
local function QuietHeader(header)
    if type(SettingsTooltip) == "table" and quietHeaders[header.GetElementData and header:GetElementData()] then
        SettingsTooltip:Hide()
    end
end

local function Header(text)
    if type(CreateSettingsListSectionHeaderInitializer) ~= "function" or not layout then
        return
    end
    local initializer = CreateSettingsListSectionHeaderInitializer(text)
    if type(initializer.InitFrame) == "function" then
        quietHeaders[initializer] = true
        local initFrame = initializer.InitFrame
        function initializer:InitFrame(frame)
            local result = initFrame(self, frame)
            if not frame.dcmQuietHeader and type(frame.HookScript) == "function" then
                frame.dcmQuietHeader = true
                frame:HookScript("OnEnter", QuietHeader)
            end
            return result
        end
    end
    layout:AddInitializer(initializer)
end

local function Button(name, text, onClick, tooltip)
    if type(CreateSettingsButtonInitializer) == "function" and layout then
        layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
    end
end

local function IntensityLabel(value)
    local intensity = DCM.INTENSITIES[math.floor((tonumber(value) or 1) + 0.5)]
    return intensity and intensity.name or ""
end

-- One row per sound event: a box for your own sound and, with Dyre's Sounds,
-- the sound on the same row (the family's checkbox-and-sound row, as Dyre's
-- Buff Reminders' chimes; Blizzard's control greys the sound while the box is
-- clear). Clear, the theme's pool plays, picked at random.
local SOUND_ROWS = {
    {event = "crit", variable = "CRIT", label = "Crit: my own sound",
        tooltip = "Clear: one of the theme's crit sounds, picked at random. Ticked: the sound you choose, "
            .. "whatever the theme."},
    {event = "big", variable = "BIG", label = "New record: my own sound",
        tooltip = "Clear: one of the theme's sounds for a new record, picked at random. Ticked: the sound "
            .. "you choose, whatever the theme."},
    {event = "extra", variable = "EXTRA", label = "Extra: my own sound",
        tooltip = "The theme's extra sound, on about 3 in 10 crits with the effects on screen (Brutal's "
            .. "squelch, from Medium; Tame has none). Clear: the theme's, picked at random. Ticked: the sound "
            .. "you choose."},
}

-- The controls show what is saved: after a refused Brutal the theme moves
-- back, once the setter has returned; "Stays on screen" shows the new
-- intensity's seconds; and each Sounds row shows the theme's sound while its
-- box is clear (found in client: after a theme change the rows kept showing
-- the old theme's sounds).
function DCM.RefreshOptions()
    if type(Settings.NotifyUpdate) == "function" and category then
        Settings.NotifyUpdate(THEME_VARIABLE)
        Settings.NotifyUpdate(INTENSITY_VARIABLE)
        Settings.NotifyUpdate(STAY_VARIABLE)
        for _, row in ipairs(SOUND_ROWS) do
            Settings.NotifyUpdate("DCM_SOUND_" .. row.variable .. "_OWN")
            Settings.NotifyUpdate("DCM_SOUND_" .. row.variable)
        end
    end
    -- Blizzard's checkbox-and-dropdown row redraws only its enabled state
    -- when its sound setting changes (SettingsCheckboxDropdownControlMixin:
    -- Init), not the sound it shows; so each shown row's menu is built again,
    -- which reads the setting anew (found in client: after Brutal to Tame the
    -- rows kept Brutal's sounds).
    for _, initializer in ipairs(soundRows) do
        local frame = initializer.dcmFrame
        local dropdown = frame and frame.Control and frame.Control.Dropdown
        if dropdown and type(frame.GetElementData) == "function" and frame:GetElementData() == initializer
                and type(dropdown.GenerateMenu) == "function" then
            dropdown:GenerateMenu()
        end
    end
end

local function LaterRefresh()
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0, DCM.RefreshOptions)
    end
end

local function Seconds(seconds)
    return (string.format("%.1f", seconds):gsub("%.0$", "")) .. " s"
end

-- "100% (7 s)": the percent, and how long this intensity's effects stay with it.
local function StayLabel(value)
    local percent = DCM.SanitizeStay(value)
    local seconds = DCM.StaySeconds(DCM.Intensity(), percent)
    if seconds == 0 then
        return string.format("%d%%", percent)
    end
    return string.format("%d%% (%s)", percent, Seconds(seconds))
end

-- "Low 2.5 s, Medium 4 s, ...", for the tooltip.
local function StayTimes()
    local times = {}
    for _, intensity in ipairs(DCM.INTENSITIES) do
        local seconds = DCM.StaySeconds(intensity, DCM.STAY_DEFAULT)
        if seconds > 0 then
            times[#times + 1] = intensity.name .. " " .. Seconds(seconds)
        end
    end
    return table.concat(times, ", ")
end

-- "Brutal (18+)" and "Fel (18+)" while the box is clear.
local function ThemeChoices()
    local container = Settings.CreateControlTextContainer()
    for _, theme in ipairs(DCM.Themes()) do
        container:Add(theme.key, theme.mature and not DCM.IsAdult() and theme.name .. " (18+)" or theme.name)
    end
    return container:GetData()
end

-- The 18+ box that unlocks Brutal and Fel first (author: "Put the 'I'm 18+' check first"), then the theme.
local function AddTheme()
    local adult = Proxy("DCM_ADULT", Settings.VarType.Boolean, "I'm 18 or over", false,
        function() return DCM.IsAdult() end,
        function(value) DCM.SetAdult(value == true) end)
    Settings.CreateCheckbox(category, adult,
        "Unlocks the Brutal and Fel themes for every character on this account. Untick it to lock them "
            .. "again: a character on either goes back to Tame.")
    local setting = Proxy(THEME_VARIABLE, Settings.VarType.String, "Theme", DCM.DEFAULT_THEME,
        function() return DCM.Theme().key end,
        function(value)
            local before = DCM.Theme()
            local theme = DCM.SetTheme(value)
            if theme ~= before then
                DCM.ClearEffects()
            end
            -- A refused Brutal moves the dropdown back; a new theme shows its
            -- sounds in the Sounds rows.
            LaterRefresh()
        end)
    Settings.CreateDropdown(category, setting, ThemeChoices,
        "What your crits look and sound like. Tame: butterflies, stars, and sparkles in soft pastels, with "
            .. "light shimmers. Brutal (18+): heavy flesh impacts, bone crunches, and blood splatter, dripping "
            .. "at High and Total Mayhem. Spellburst: bursts of light in your spell's school, for casters and "
            .. "healers; crit heals show too. Fel (18+): dark smoke, falling embers, and creeping cracks in fel "
            .. "green, shadow, and hellfire. More themes are planned.")
end

-- The intensity (author: "leave the slider for 'Intensity'"), then how long
-- the effects stay.
local function AddIntensity()
    local setting = Proxy(INTENSITY_VARIABLE, Settings.VarType.Number, "Intensity",
        DCM.INTENSITY_INDEX[DCM.DEFAULT_INTENSITY],
        function() return DCM.IntensityIndex() end,
        function(value)
            DCM.SetIntensityIndex(math.floor((tonumber(value) or 1) + 0.5))
            if not DCM.Intensity().splats then
                DCM.ClearEffects()
            end
            -- The stay slider's seconds follow the intensity.
            LaterRefresh()
        end)
    local options = Settings.CreateSliderOptions(1, #DCM.INTENSITIES, 1)
    if type(MinimalSliderWithSteppersMixin) == "table" and type(options.SetLabelFormatter) == "function" then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, IntensityLabel)
    end
    Settings.CreateSlider(category, setting, options,
        "How much your crits show, in your theme: each step is more, bigger, and stays longer. Off: "
            .. "nothing. Low: one small effect. Medium, High, and Total Mayhem: more of them, bigger, for "
            .. "longer. Your records count at every intensity.")
    local stay = Proxy(STAY_VARIABLE, Settings.VarType.Number, "Stays on screen", DCM.STAY_DEFAULT,
        function() return DCM.db.stay end,
        function(value) DCM.db.stay = DCM.SanitizeStay(value) end)
    options = Settings.CreateSliderOptions(DCM.STAY_MIN, DCM.STAY_MAX, DCM.STAY_STEP)
    if type(MinimalSliderWithSteppersMixin) == "table" and type(options.SetLabelFormatter) == "function" then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, StayLabel)
    end
    local slider = Settings.CreateSlider(category, stay, options,
        "How long the effects stay on screen, as a percent of the intensity's own time; the seconds beside "
            .. "it are for your intensity now. At 100%: " .. StayTimes() .. ".")
    if type(DCM.toolkit.AddDefaultTick) == "function" then
        DCM.toolkit.AddDefaultTick(slider, {min = DCM.STAY_MIN, max = DCM.STAY_MAX, default = DCM.STAY_DEFAULT})
    end
    Flag("DCM_SPLATTER", "On-screen effects", "splatter",
        "The theme's effects on the screen on a crit, under your action bars and unit frames. Never in "
            .. "the middle of the screen for your own crits; at its edges for crits on you.")
end

local function AddCrits()
    Header("Which crits")
    Flag("DCM_MINE", "My crits", "mine", "Your own crits, melee, ranged, and spells.")
    Flag("DCM_PET", "My pet's crits", "pet", "Your pet's crits.")
    Flag("DCM_TAKEN", "Crits on me", "taken", "Crits that hit you. Their effects land at the edges of "
        .. "the screen.")
    Flag("DCM_HEALS", "Heals too", "heals", "Crit heals play the sounds and show the theme's gentle heal "
        .. "effects, rising (no blood), and your heals get records too.")
    -- Only where the combat log is closed to AddOns (WoW: Forever).
    if DCM.RecordsGuessed() then
        Flag("DCM_GROUP_GUESS", "Guess my crits in a group", "groupGuess",
            "This client keeps the combat log from AddOns, so in a group DCM cannot tell whose crit it was. "
                .. "Ticked, a crit on your target just after your own cast counts as yours: about one in three "
                .. "will be someone else's. Solo, every crit is yours. Records are only kept solo.")
    end
end

local function HasSoundRows(library)
    return library and type(CreateSettingsCheckboxDropdownInitializer) == "function" and type(layout) == "table"
        and type(layout.AddInitializer) == "function" and type(library.SetupCheckboxMenu) == "function"
        and type(library.Choices) == "function"
end

local function AddSoundRow(row, library)
    local function Pick()
        return DCM.db.soundPicks[row.event]
    end
    local own = Proxy("DCM_SOUND_" .. row.variable .. "_OWN", Settings.VarType.Boolean, row.label, false,
        function() return Pick().on end,
        function(value)
            Pick().on = value == true
            Pick().key = Pick().key or DCM.ThemeSound(row.event)
            -- Ticked, the row shows your pick; clear, the theme's.
            LaterRefresh()
        end)
    if not HasSoundRows(library) then
        Settings.CreateCheckbox(category, own, row.tooltip)
        return
    end
    local sound = Proxy("DCM_SOUND_" .. row.variable, Settings.VarType.String, "Sound", "",
        -- Clear, the theme's sound shows (greyed); your pick is kept for when
        -- the box is ticked again.
        function() return Pick().on and Pick().key or DCM.ThemeSound(row.event) end,
        function(value)
            Pick().key = value
            -- Choosing one plays it once.
            DCM.PlaySound(value, row.event)
        end)
    local initializer = CreateSettingsCheckboxDropdownInitializer(own, row.label, row.tooltip, sound,
        library.Choices(), "Sound", "The sound for this, from Dyre's Sounds. Choosing one plays it once.")
    layout:AddInitializer(initializer)
    library.SetupCheckboxMenu(initializer)
    -- The row's frame while it shows this row (frames are pooled), so a theme
    -- change can redraw its sound.
    if type(initializer.InitFrame) == "function" then
        local initFrame = initializer.InitFrame
        function initializer:InitFrame(frame)
            local result = initFrame(self, frame)
            self.dcmFrame = frame
            return result
        end
        soundRows[#soundRows + 1] = initializer
    end
end

-- The sounds (author: each theme sets its defaults, 2-3 played at random;
-- the family's rule: a picker per sound, with the theme's as the default).
local function AddSounds()
    Header("Sounds")
    Flag("DCM_SOUND", "Sounds", "sound",
        "Play the theme's sounds on a crit. They play on the Sound Effects channel, so the game's sound "
            .. "effects volume sets them. They come from Dyre's Sounds.")
    local library = DCM.SoundLibrary()
    for _, row in ipairs(SOUND_ROWS) do
        AddSoundRow(row, library)
    end
    Button("Theme sounds", "Reset sounds to theme", function() DCM.ResetSounds() end,
        "Clears your own sounds, so every sound is the theme's again, picked at random.")
end

local function AddRecords()
    Header("Records")
    Flag("DCM_ANNOUNCE_SCREEN", "Show new records on screen", "announceScreen",
        "A pop in the middle of the screen for a new record. /dcm unlock (or Dyre's Toolkit's unlock) "
            .. "shows a sample to drag. Your chat always says it, seen only by you.")
    Flag("DCM_ANNOUNCE_PARTY", "Announce in party", "announceParty",
        "Say new records in party chat, at most one every 10 seconds.")
    Flag("DCM_ANNOUNCE_GUILD", "Announce in guild", "announceGuild",
        "Say new records in guild chat, at most one every 10 seconds.")
    if DCM.popWidget then
        DCM.toolkit.AddWidgetSettings(category, layout, DCM.popWidget, {
            labels = {scale = "Record pop size"},
            tooltips = {scale = "How big the new record pop is, in percent."},
            resetTooltip = "The record pop back to 100%.",
        })
    end
    Button("Your records", "Show records", function() DCM.ToggleWindow() end,
        "Every ability's highest hit and crit on this character. /dcm does the same.")
    Button("Try it", "Test crit", function() DCM.TestCrit() end,
        "Plays a crit at this intensity, and a new record's bigger one every third time.")
    Button("Start over", "Reset records", function() DCM.ConfirmResetRecords() end,
        "Clears every record on this character, after asking. Out of combat only.")
end

function DCM.InitializeOptions()
    if not HasSettingsAPI() then
        return
    end
    category, layout = DCM.toolkit.RegisterSettingsCategory(TITLE)
    if not category then
        return
    end
    AddTheme()
    AddIntensity()
    AddCrits()
    AddSounds()
    AddRecords()
end

function DCM.OpenSettings()
    if not category then
        DCM.Report(UNAVAILABLE)
        return
    end
    -- The toolkit's opener says so in combat instead.
    DCM.toolkit.OpenSettings(category)
end
