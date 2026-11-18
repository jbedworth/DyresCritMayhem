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
-- The records rows' tooltip while the client hides damage amounts (WoW:
-- Forever; author's words).
DCM.AMOUNTS_BLOCKED = "Presently, WoW Forever blocks addons ability to read damage amounts you do. If they "
    .. "fix this, we can enable these features again."

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
        local initializer = CreateSettingsButtonInitializer(name, text, onClick, tooltip, true)
        layout:AddInitializer(initializer)
        return initializer
    end
end

-- A records row while the client hides damage amounts (author: "On Forever,
-- we should disable the show highest crit stuff, since we can't do it"):
-- greyed, with the reason as its tooltip. Checkboxes and sliders grey
-- through Blizzard's modify predicate (SettingsControlMixin:IsEnabled); a
-- button row does not read it (SettingsButtonControlMixin), so its button is
-- disabled after each init, and its click does nothing.
local function Block(initializer)
    if type(initializer) ~= "table" then
        return
    end
    initializer.data = type(initializer.data) == "table" and initializer.data or {}
    initializer.data.tooltip = DCM.AMOUNTS_BLOCKED
    initializer.tooltip = DCM.AMOUNTS_BLOCKED
    if type(initializer.AddModifyPredicate) == "function" then
        initializer:AddModifyPredicate(function() return false end)
    end
    if initializer.data.buttonClick then
        initializer.data.buttonClick = function() end
    end
    if initializer.onClick then
        initializer.onClick = function() end
    end
    initializer.dcmBlocked = true
    if type(initializer.InitFrame) == "function" then
        local initFrame = initializer.InitFrame
        function initializer:InitFrame(frame)
            local result = initFrame(self, frame)
            local button = type(frame) == "table" and frame.Button
            if type(button) == "table" and type(button.SetEnabled) == "function" then
                button:SetEnabled(false)
                if type(frame.DisplayEnabled) == "function" then
                    frame:DisplayEnabled(false)
                end
            end
            return result
        end
    end
end

-- Runs add(), blocking every row it puts on the layout (the toolkit's
-- record pop rows too) when blocked.
local function Blocked(blocked, add)
    if not blocked or type(layout) ~= "table" then
        return add()
    end
    local addInitializer = layout.AddInitializer
    layout.AddInitializer = function(self, initializer)
        Block(initializer)
        return addInitializer(self, initializer)
    end
    add()
    layout.AddInitializer = addInitializer
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
    if seconds == 0 or DCM.Theme().none then
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

-- None first (author: "Have it be the first item, above Tame"), then the
-- themes: each 18+ theme reads "Brutal (18+)" and so on while the box is clear.
local function ThemeChoices()
    local container = Settings.CreateControlTextContainer()
    container:Add(DCM.NONE_THEME, DCM.FindTheme(DCM.NONE_THEME).name)
    for _, theme in ipairs(DCM.Themes()) do
        container:Add(theme.key, theme.mature and not DCM.IsAdult() and theme.name .. " (18+)" or theme.name)
    end
    return container:GetData()
end

-- The 18+ box that unlocks Brutal, Fel, and Naturalist first (author: "Put the 'I'm 18+' check first"), then the theme.
local function AddTheme()
    local adult = Proxy("DCM_ADULT", Settings.VarType.Boolean, "I'm 18 or over", false,
        function() return DCM.IsAdult() end,
        function(value) DCM.SetAdult(value == true) end)
    Settings.CreateCheckbox(category, adult,
        "Unlocks the Brutal, Spellburst, Fel, and Naturalist themes for every character on this account. Untick "
            .. "it to lock "
            .. "them again: a character on one goes back to Tame.")
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
    local dropdown = Settings.CreateDropdown(category, setting, ThemeChoices,
        "What your crits look and sound like. None: no effects or sounds; your records still count. Tame "
            .. "(the default): butterflies, stars, and sparkles in soft pastels, with "
            .. "light shimmers. Brutal (18+): heavy flesh impacts, bone crunches, and blood splatter, dripping "
            .. "at High and Total Mayhem. Spellburst, Fel, and Naturalist (18+) style Brutal for your own "
            .. "damage (damage on you keeps Brutal's look): Spellburst a glow in your spell's school and brighter "
            .. "spell hits; Fel dark blood, purple, and fel green for every school, even holy, with cracks and "
            .. "dark smoke; Naturalist claws and bites, earthy tints, and leaves. More themes are planned.")
    -- Under the theme, live only for a theme that offers it (Tame): Blizzard
    -- re-checks a child row whenever its parent's setting changes.
    local random = Flag("DCM_RANDOM_EFFECTS", "Random Effects", "randomEffects",
        "Tame only: ticked, every crit shows Tame's playful mix of stars, butterflies, and sparkles, whatever "
            .. "its damage school. Clear (the default): a look for each school (a cartoon pow for melee, little "
            .. "flames, snowflakes, leaves, puffs, violet stars, gold sparkles).")
    if type(random.SetParentInitializer) == "function" then
        random:SetParentInitializer(dropdown, function() return DCM.Theme().randomEffects == true end)
    end
    -- Naturalist's form check (author: "if the form check is doable, maybe
    -- we keep it?"), off so its random mix stays the default.
    local claws = Flag("DCM_CLAWS_IN_FORM", "Claws only in Cat or Bear form", "clawsInForm",
        "Naturalist only: ticked, your melee crits show claw scratches and bites only in Cat, Bear, or Dire "
            .. "Bear form (and a Hunter's pet's crits always do); in other forms, for other classes, and for "
            .. "crits on you or others' crits, Brutal's blood splatter. Clear (the default): claws, bites, and "
            .. "splatter mixed on every melee crit.")
    if type(claws.SetParentInitializer) == "function" then
        claws:SetParentInitializer(dropdown, function() return DCM.Theme().formClaws == true end)
    end
end

-- The intensity (author: "leave the slider for 'Intensity'"), then how long
-- the effects stay.
local function AddIntensity()
    local setting = Proxy(INTENSITY_VARIABLE, Settings.VarType.Number, "Intensity",
        DCM.INTENSITY_INDEX[DCM.DEFAULT_INTENSITY],
        function() return DCM.IntensityIndex() end,
        function(value)
            DCM.SetIntensityIndex(math.floor((tonumber(value) or 1) + 0.5))
            -- The stay slider's seconds follow the intensity.
            LaterRefresh()
        end)
    local options = Settings.CreateSliderOptions(1, #DCM.INTENSITIES, 1)
    if type(MinimalSliderWithSteppersMixin) == "table" and type(options.SetLabelFormatter) == "function" then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, IntensityLabel)
    end
    Settings.CreateSlider(category, setting, options,
        "How much your crits show, in your theme: each step is more, bigger, and stays longer. Low (the "
            .. "default): one small effect. Medium, High, and Total Mayhem: more of them, bigger, for "
            .. "longer. To turn every effect off, pick the None theme. With an 18+ theme (Brutal, Fel, "
            .. "Naturalist), it also turns up the game's own blood on hit models (its violence level): Low 3, "
            .. "Medium 4, High and Total Mayhem 5. None, or a cute theme, puts your own level back.")
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
    Flag("DCM_SPRAY", "Hit effects on enemies", "spray",
        "Every hit that does damage plays its school's effect on the enemy, from its nameplate down over "
            .. "its body, following it: blood for physical (18+), snow and ice for frost, the body burning "
            .. "for fire, sparks for arcane and nature, smoke for shadow, golden sparkles for holy, green plus signs "
            .. "for heals. A crit doubles it. AddOns cannot draw on the mob itself, so this needs enemy "
            .. "nameplates on. Not in the Tame theme yet.")
    Flag("DCM_HITS_ON_YOU", "Hit effects on you", "hitsOnYou",
        "The same effects on your own character when you are hit or healed, in the middle of the screen "
            .. "where the camera keeps you. Not in the Tame theme yet.")
end

local function OthersChoices()
    local container = Settings.CreateControlTextContainer()
    container:Add("off", "Off")
    container:Add("target", "My target")
    container:Add("nearby", "Nearby enemies (nameplates)")
    return container:GetData()
end

local function AddCrits()
    Header("Which crits")
    Flag("DCM_MINE", "My crits", "mine", "Your own crits, melee, ranged, and spells.")
    Flag("DCM_PET", "My pet's crits", "pet", "Your pet's crits.")
    Flag("DCM_TAKEN", "Crits on me", "taken", "Crits that hit you. Their effects land at the edges of "
        .. "the screen.")
    Flag("DCM_HEALS", "Heals too", "heals", "Crit heals play the sounds and show the theme's gentle heal "
        .. "effects, rising (no blood), and your heals get records too.")
    local others = Proxy("DCM_OTHERS", Settings.VarType.String, "Others' crits", DCM.DEFAULT_OTHERS_SCOPE,
        function() return DCM.db.othersScope end,
        function(value)
            DCM.db.othersScope = DCM.OTHERS_SCOPES[value] and value or DCM.DEFAULT_OTHERS_SCOPE
        end)
    Settings.CreateDropdown(category, others, OthersChoices,
        "Anyone's crits play the effects too: the mob is getting critted, whoever did it. Off: only yours. "
            .. "My target: on the mob you target. Nearby enemies: on your target and every enemy with a "
            .. "nameplate shown. Others' crits are trimmed first so a raid stays readable (one effect each, a "
            .. "few per half second); yours always play. Never a record or a new record. The same setting shows hits "
            .. "on bystanders (other players, guards, your friendly target): their hit effects on their nameplates, "
            .. "and their crits as others' crits.")
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
    -- The client hides damage amounts (WoW: Forever): no records, so their
    -- rows are greyed with the reason. "Test crit" stays.
    local blocked = DCM.AmountsHidden()
    local rows = {}
    rows[#rows + 1] = Flag("DCM_ANNOUNCE_SCREEN", "Show new records on screen", "announceScreen",
        "A pop in the middle of the screen for a new record. /dcm unlock (or Dyre's Toolkit's unlock) "
            .. "shows a sample to drag. Your chat always says it, seen only by you.")
    rows[#rows + 1] = Flag("DCM_ANNOUNCE_PARTY", "Announce in party", "announceParty",
        "Say new records in party chat, at most one every 10 seconds.")
    rows[#rows + 1] = Flag("DCM_ANNOUNCE_GUILD", "Announce in guild", "announceGuild",
        "Say new records in guild chat, at most one every 10 seconds.")
    -- The toolkit's pop size slider is made through Settings, which adds it
    -- to this layout too (Blizzard's CreateSlider), so Blocked catches it.
    Blocked(blocked, function()
        if DCM.popWidget then
            DCM.toolkit.AddWidgetSettings(category, layout, DCM.popWidget, {
                labels = {scale = "Record pop size"},
                tooltips = {scale = "How big the new record pop is, in percent."},
                resetTooltip = "The record pop back to 100%.",
            })
        end
        Button("Your records", "Show records", function() DCM.ToggleWindow() end,
            "Every ability's highest hit and crit on this character. /dcm does the same.")
    end)
    Button("Try it", "Test crit", function() DCM.TestCrit() end,
        "Plays a crit at this intensity, and a new record's bigger one every third time.")
    rows[#rows + 1] = Button("Start over", "Reset records", function() DCM.ConfirmResetRecords() end,
        "Clears every record on this character, after asking. Out of combat only.")
    if blocked then
        for _, initializer in ipairs(rows) do
            Block(initializer)
        end
    end
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
