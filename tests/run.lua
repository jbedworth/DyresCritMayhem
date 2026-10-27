-- Run from the repository root: lua tests/run.lua
-- These mocks test AddOn logic, not client compatibility, protected actions,
-- secret-value behavior, layout, how the effects look, or taint.
-- Every test gets its own globals, clock, event frames, and namespace.
if _VERSION ~= "Lua 5.1" then
    io.stderr:write("This suite requires Lua 5.1; found " .. tostring(_VERSION) .. "\n")
    os.exit(1)
end

local tests = {}
local function test(name, body)
    tests[#tests + 1] = {name = name, body = body}
end
local function equal(actual, expected, context)
    if actual ~= expected then
        error((context or "value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end
local function contains(actual, fragment, context)
    if type(actual) ~= "string" or not actual:find(fragment, 1, true) then
        error((context or "text") .. ": expected text containing " .. fragment
            .. ", got " .. tostring(actual), 2)
    end
end

-- Rolls: DCM.random(n) picks the first; DCM.random() returns roll.
local function rolls(state, roll)
    state.dcm.random = function(low) if low then return 1 end return roll end
end

local ADDON = "DyresCritMayhem"
local RUNTIME_FILES = {"Commands.lua", "Core.lua", "Themes.lua", "Effects.lua", "Detect.lua", "Records.lua",
    "Window.lua", "Probe.lua", "Options.lua"}
-- Dyre's Toolkit's runtime files, without the minimap (it needs the embedded
-- libraries); tests/toolkit holds a copy, checked against ../DyresToolkit.
local TOOLKIT_FILES = {"Core.lua", "Layout.lua", "Widgets.lua", "Settings.lua"}
local PLAYER, PET, ENEMY = "Player-1-0001", "Pet-0-0002", "Creature-0-0003"

-- A secret stands in for the client's opaque combat values; tests mark them with
-- issecretvalue, and any comparison or concatenation with one raises an error.
local function secret()
    return setmetatable({}, {
        __eq = function() error("compared a secret value") end,
        __lt = function() error("compared a secret value") end,
        __le = function() error("compared a secret value") end,
        __concat = function() error("concatenated a secret value") end,
        __tostring = function() error("printed a secret value") end,
        __index = function() error("indexed a secret value") end,
    })
end

local function fixture(options)
    options = options or {}
    local state = {frames = {}, messages = {}, now = 100, combat = false, secrets = {}, settings = {},
        categories = {}, sounds = {}, chat = {}, popups = {}, timers = {}}
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.SlashCmdList = options.slashCmdList or {}
    for key, value in pairs(options.globals or {}) do env[key] = value end
    env.DEFAULT_CHAT_FRAME = {AddMessage = function(_, message)
        state.messages[#state.messages + 1] = message
    end}
    state.toc = {}
    for text in io.lines(ADDON .. ".toc") do
        local key, value = text:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then state.toc[key] = value end
    end
    env.C_AddOns = {GetAddOnMetadata = function(name, field)
        if name ~= ADDON then return nil end
        return state.toc[field] or ""
    end}
    env.GetTime = function() return state.now end
    env.InCombatLockdown = function() return state.combat end
    env.issecretvalue = function(value) return state.secrets[value] == true end
    env.SetCVar = function() error("DCM must never change a CVar") end
    env.C_CVar = {SetCVar = env.SetCVar}
    env.UnitGUID = function(unit)
        if unit == "player" then return PLAYER end
        if unit == "pet" then return state.pet end
        if unit == "target" then return state.target end
        if state.plates and state.plates[unit] then return state.plates[unit] end
    end
    env.IsInGroup = function() return state.group == true end
    -- The player's class (options.class, default MAGE) and Druid form
    -- (state.form: a form's spell ID, or nil for none; state.formSecret).
    env.UnitClass = function(unit)
        if unit == "player" then
            local class = options.class or "MAGE"
            return class:sub(1, 1) .. class:sub(2):lower(), class
        end
    end
    env.GetNumShapeshiftForms = function() return 5 end
    env.GetShapeshiftFormInfo = function(index)
        local forms = {5487, 768, 783, 24858, 9634}
        local active = state.form == forms[index]
        local spellID = forms[index]
        if state.formSecret then spellID = secret() end
        return "icon", active, true, spellID
    end
    env.UnitCanAttack = function(_, unit) return not (state.friendly and state.friendly[unit]) end
    env.IsInGuild = function() return state.guild == true end
    env.C_ChatInfo = {SendChatMessage = function(message, channel)
        state.chat[#state.chat + 1] = {message = message, channel = channel}
    end}
    env.BreakUpLargeNumbers = function(value)
        local text = tostring(value)
        local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        return (result:gsub("^,", ""))
    end
    env.C_Timer = {After = function(seconds, callback)
        state.timers[#state.timers + 1] = {at = state.now + seconds, callback = callback}
    end}
    function state.runTimers()
        local due = state.timers
        state.timers = {}
        for _, timer in ipairs(due) do timer.callback() end
    end
    -- The combat log: the event's fields, or refused as on Forever.
    env.C_CombatLog = {
        GetCurrentEventInfo = function() return unpack(state.log, 1, 24) end,
        IsCombatLogRestricted = function() return options.restrictCombatLog == true end,
    }
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function(name)
        equal(state.combat, false, "no popups in combat")
        state.popups[#state.popups + 1] = name
    end
    env.UISpecialFrames = {}
    local SPELLS = {[1752] = "Sinister Strike", [133] = "Fireball", [2061] = "Flash Heal", [3716] = "Torment"}
    env.C_Spell = {
        GetSpellName = function(id) return SPELLS[id] end,
        IsSpellHarmful = function(id) return id ~= 2061 end,
    }
    env.GetBuildInfo = function() return "1.60.1", "70450", "Oct 1 2026", 16001 end
    -- Forever's damage meter, faked: options.meter.
    if options.meter then
        env.Enum = {DamageMeterSessionType = {Current = 1}, DamageMeterType = {DamageDone = 0}}
        env.C_DamageMeter = {
            IsDamageMeterAvailable = function() return true, "" end,
            GetCombatSessionFromType = function()
                return {maxAmount = 900, totalAmount = 1400, combatSources = {
                    {isLocalPlayer = true, name = "Dyre", totalAmount = 900, sourceGUID = PLAYER},
                    {isLocalPlayer = false, name = "Friend", totalAmount = 500, sourceGUID = "Player-1-0099"},
                }}
            end,
            GetCombatSessionSourceFromType = function(_, _, guid)
                equal(guid, PLAYER)
                return {maxAmount = 900, totalAmount = 900, combatSpells = {
                    {spellID = 133, totalAmount = 900, combatSpellDetails = {amount = 900, isPet = false}},
                }}
            end,
        }
    end
    -- Dyre's Sounds, faked (the library has its own suite); options.noSounds
    -- leaves it out.
    if not options.noSounds then
        local library = {}
        -- The catalog's keys DCM uses (Dyre's Sounds 1.2.0); options.missingKeys
        -- leaves some out, as an older library would.
        local catalog = {}
        for _, key in ipairs({"goreslice", "gorechop", "gorebash", "goresplat", "gorebloody", "wetsplat",
            "wetpunch", "kiss", "kisses", "swishsmack", "war3magicshimmer", "instrumentschimeascending",
            "impactspopclick", "laserswing", "magical", "war2magicchimes", "instrumentsbelltrill", "war2choir",
            "teleportvanish", "impactsbubblesmash", "impactslowthud", "impactsstrangeclang", "instrumentssynthbuzz",
            "bigmonsterroar", "monsterbear", "instrumentspitchpipedistressed", "fadingslow", "blowswoosh",
            "disappearingswoosh", "orcfury", "talent", "voice", "angrycat", "tigerroar", "bearroar", "lionroar",
            "felheartbeat", "felwetsmash", "felmudsplat", "feldemongrowl"}) do
            catalog[key] = true
        end
        for _, key in ipairs(options.missingKeys or {}) do catalog[key] = nil end
        -- The game's kit-ID and file-ID sounds, which Classic Era and
        -- Anniversary cannot play (options.classic).
        local function GameSound(key)
            return key:find("^impacts") or key:find("^instruments") or key:find("^war2") or key:find("^war3")
        end
        if not options.noPlayable then
            function library.Playable(key)
                return catalog[key] ~= nil and not (options.classic and GameSound(key))
            end
        end
        function library.RequireContract(minimum)
            if minimum <= 1 then return library end
        end
        function library.Resolve(key) if catalog[key] then return key end end
        function library.Choices()
            return function()
                local list = {}
                for key in pairs(catalog) do list[#list + 1] = {value = key, label = key} end
                return list
            end
        end
        function library.SetupCheckboxMenu(initializer) initializer.soundMenu = true end
        function library.Play(key, speech, channel)
            if options.classic and GameSound(key) then return false end
            if key == "voice" and type(speech) ~= "string" then return false end
            state.sounds[#state.sounds + 1] = {key = key, speech = speech, channel = channel}
            return true
        end
        env.DyresSounds = library
    end

    -- Settings: proxy settings with getters and setters, as the client builds them.
    local function newCategory(name, parent)
        local category = {name = name, initializers = {}, parent = parent, rows = {}}
        function category:GetID() return "id:" .. name end
        state.categories[name] = category
        return category
    end
    local function initializer(category, setting, extra, tooltip)
        local object = {setting = setting, options = extra, tooltip = tooltip}
        function object:SetParentInitializer(parent, predicate)
            self.parentInitializer, self.predicate = parent, predicate
        end
        object.modifyPredicates = {}
        function object:AddModifyPredicate(predicate)
            self.modifyPredicates[#self.modifyPredicates + 1] = predicate
        end
        category.initializers[#category.initializers + 1] = object
        category.rows[#category.rows + 1] = object
        return object
    end
    env.MinimalSliderWithSteppersMixin = {Label = {Right = "right"}}
    env.Settings = {
        VarType = {Boolean = "boolean", Number = "number", String = "string"},
        RegisterVerticalLayoutCategory = function(name) return newCategory(name) end,
        RegisterVerticalLayoutSubcategory = function(parent, name)
            local page = newCategory(name, parent)
            local layout = {}
            function layout:AddInitializer(row) page.rows[#page.rows + 1] = row end
            return page, layout
        end,
        NotifyUpdate = function(variable)
            state.notified = state.notified or {}
            state.notified[#state.notified + 1] = variable
        end,
        RegisterProxySetting = function(category, variable, variableType, name, default, getValue, setValue)
            equal(state.settings[variable], nil, "setting variables are unique")
            local setting = {category = category, variable = variable, type = variableType, name = name,
                default = default}
            function setting:GetValue() return getValue() end
            function setting:SetValue(value) setValue(value) end
            state.settings[variable] = setting
            return setting
        end,
        RegisterAddOnCategory = function(category) state.registered = category end,
        CreateCheckbox = function(category, setting, tooltip) return initializer(category, setting, nil, tooltip) end,
        CreateSlider = function(category, setting, sliderOptions, tooltip)
            return initializer(category, setting, sliderOptions, tooltip)
        end,
        CreateSliderOptions = function(minValue, maxValue, step)
            local object = {minValue = minValue, maxValue = maxValue, step = step}
            function object:SetLabelFormatter(label, formatter) self.label, self.formatter = label, formatter end
            return object
        end,
        CreateControlTextContainer = function()
            local container = {data = {}}
            function container:Add(value, label) self.data[#self.data + 1] = {value = value, label = label} end
            function container:GetData() return self.data end
            return container
        end,
        CreateDropdown = function(category, setting, choices, tooltip)
            local object = initializer(category, setting, nil, tooltip)
            object.choices = choices
            return object
        end,
        OpenToCategory = function(id) state.opened = id end,
    }
    env.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip)
        return {button = true, name = name, buttonText = buttonText, onClick = onClick, tooltip = tooltip}
    end
    env.CreateSettingsListSectionHeaderInitializer = function(name)
        local header = {header = name}
        function header:InitFrame() end
        return header
    end
    env.SettingsTooltip = {shown = false}
    function env.SettingsTooltip:Show() self.shown = true end
    function env.SettingsTooltip:Hide() self.shown = false end
    env.CreateSettingsCheckboxDropdownInitializer = function(setting, label, tooltip, soundSetting, choices,
            soundLabel, soundTooltip)
        local row = {checkboxDropdown = true, name = label, setting = setting, tooltip = tooltip,
            data = {dropdownSetting = soundSetting}, choices = choices, soundLabel = soundLabel}
        function row:InitFrame() end
        return row
    end

    local function animationGroup(owner)
        local group = {owner = owner, animations = {}, scripts = {}, playing = false}
        function group:CreateAnimation(kind)
            local animation = {kind = kind}
            function animation:SetDuration(value) self.duration = value end
            function animation:SetStartDelay(value) self.delay = value end
            function animation:SetFromAlpha(value) self.from = value end
            function animation:SetToAlpha(value) self.to = value end
            function animation:SetScaleFrom(x, y) self.scaleFrom = {x, y} end
            function animation:SetScaleTo(x, y) self.scaleTo = {x, y} end
            function animation:SetOffset(x, y) self.offset = {x, y} end
            function animation:SetOrigin(point, x, y) self.origin = {point, x, y} end
            function animation:SetDegrees(value) self.degrees = value end
            self.animations[#self.animations + 1] = animation
            return animation
        end
        function group:SetScript(name, callback) self.scripts[name] = callback end
        function group:SetLooping(mode) self.looping = mode end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        function group:IsPlaying() return self.playing end
        -- The engine finishing it.
        function group:Finish()
            self.playing = false
            if self.scripts.OnFinished then self.scripts.OnFinished(self) end
        end
        state.groups = state.groups or {}
        state.groups[#state.groups + 1] = group
        return group
    end

    local function widget(kind, name, parent, template)
        local object = {kind = kind, name = name, parent = parent, template = template, events = {},
            unitEvents = {}, scripts = {}, points = {}, shown = true, text = "", children = {}}
        if parent and parent.children then parent.children[#parent.children + 1] = object end
        function object:EnableMouse(value) self.mouse = value == true end
        function object:SetAlpha(value) self.alpha = value end
        function object:GetAlpha() return self.alpha or 1 end
        function object:SetScale(value) self.scale = value end
        function object:GetScale() return self.scale or 1 end
        function object:GetEffectiveScale()
            local parentScale = 1
            if self.parent and self.parent.GetEffectiveScale then parentScale = self.parent:GetEffectiveScale() end
            return (self.scale or 1) * parentScale
        end
        function object:SetSize(width, height) self.width, self.height = width, height end
        function object:SetWidth(width) self.width = width end
        function object:SetHeight(height) self.height = height end
        function object:GetWidth()
            if self == env.UIParent then return self.width end
            if self.allPoints then return self.allPoints:GetWidth() end
            return self.width or 0
        end
        function object:GetHeight()
            if self == env.UIParent then return self.height end
            if self.allPoints then return self.allPoints:GetHeight() end
            return self.height or 0
        end
        function object:SetAllPoints(target) self.allPoints = target or self.parent end
        function object:GetNumPoints() return #self.points end
        function object:GetCenter()
            if self ~= env.UIParent and #self.points == 0 then return end
            local x, y = state.absCenter(self)
            local scale = self:GetEffectiveScale()
            return x / scale, y / scale
        end
        function object:IsProtected() return false end
        function object:SetShown(value)
            if value then self:Show() else self:Hide() end
        end
        function object:RegisterEvent(event)
            if event == "COMBAT_LOG_EVENT_UNFILTERED" and options.restrictCombatLog then
                error("COMBAT_LOG_EVENT_UNFILTERED is restricted")
            end
            self.events[event] = true
        end
        function object:RegisterUnitEvent(event, ...) self.unitEvents[event] = {...} end
        function object:UnregisterEvent(event) self.events[event] = nil end
        function object:SetScript(script, callback) self.scripts[script] = callback end
        function object:Show()
            local was = self.shown
            self.shown = true
            if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function object:Hide() self.shown = false end
        function object:IsShown() return self.shown end
        function object:SetPoint(...) self.points[#self.points + 1] = {...} end
        function object:ClearAllPoints() self.points = {} end
        function object:GetPoint()
            local point = self.points[#self.points]
            if not point then return end
            return point[1], point[2], point[3], point[4], point[5]
        end
        function object:SetText(text) self.text = text end
        function object:GetText() return self.text end
        function object:SetTextColor(...) self.textColor = {...} end
        function object:SetTexture(texture) self.texture = texture end
        function object:SetVertexColor(...) self.vertexColor = {...} end
        function object:SetRotation(value) self.rotation = value end
        function object:SetTexCoord(...) self.texCoord = {...} end
        function object:SetBlendMode(mode) self.blend = mode end
        function object:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
        function object:CreateTexture() return widget("Texture", nil, self) end
        function object:CreateFontString() return widget("FontString", nil, self) end
        function object:CreateAnimationGroup() return animationGroup(self) end
        function object:SetScrollChild(child) self.scrollChild = child end
        function object:SetBackdrop(backdrop) self.backdrop = backdrop end
        function object:SetBackdropBorderColor(...) self.backdropBorder = {...} end
        function object:SetBackdropColor(...) self.backdropColor = {...} end
        -- Unknown methods (layout, colors, and so on) do nothing here.
        return setmetatable(object, {__index = function(_, key)
            if type(key) == "string" and key:match("^%u") then return function() end end
        end})
    end
    env.CreateFrame = function(kind, name, parent, template)
        local frame = widget(kind, name, parent, template)
        if name then env[name] = frame end
        -- The template's scroll bar, shown by default as in client.
        if template == "UIPanelScrollFrameTemplate" then
            frame.ScrollBar = widget("Slider", nil, frame)
        end
        state.frames[#state.frames + 1] = frame
        return frame
    end
    env.UIParent = widget("Frame", "UIParent")
    env.UIParent.width, env.UIParent.height = 1000, 800
    env.IsShiftKeyDown = function() return false end
    env.IsControlKeyDown = function() return false end
    local SPOTS = {CENTER = {0.5, 0.5}, BOTTOMLEFT = {0, 0}, TOP = {0.5, 1}, TOPLEFT = {0, 1}, LEFT = {0, 0.5},
        BOTTOMRIGHT = {1, 0}, RIGHT = {1, 0.5}, BOTTOM = {0.5, 0}, TOPRIGHT = {1, 1}}
    function state.absCenter(frame)
        if frame == env.UIParent or frame == nil then return 500, 400 end
        local point = frame.points[#frame.points]
        local relative = point[2] or env.UIParent
        if type(relative) == "string" then
            return 500, 400
        end
        local relativeScale = relative == env.UIParent and 1 or relative:GetEffectiveScale()
        local rx, ry = state.absCenter(relative)
        local spot = SPOTS[point[3]] or SPOTS.CENTER
        local width = (relative.width or 0) * relativeScale
        local height = (relative.height or 0) * relativeScale
        local scale = frame:GetEffectiveScale()
        return rx + (spot[1] - 0.5) * width + (point[4] or 0) * scale,
            ry + (spot[2] - 0.5) * height + (point[5] or 0) * scale
    end
    function state.emit(event, ...)
        for _, frame in ipairs(state.frames) do
            local units = frame.unitEvents[event]
            local first = ...
            local wanted = frame.events[event]
            for _, unit in ipairs(units or {}) do
                if unit == first then wanted = true end
            end
            if wanted then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end

    for _, name in ipairs(options.remove or {}) do env[name] = nil end
    if not options.noToolkit then
        state.toolkitNS = {InitializeMinimap = function() end}
        env.DyresToolkitDB = {snapToGrid = false}
        for _, path in ipairs(TOOLKIT_FILES) do
            local chunk = assert(loadfile("tests/toolkit/" .. path))
            setfenv(chunk, env)
            chunk("DyresToolkit", state.toolkitNS)
        end
        state.toolkit = env.DyresToolkit
    end
    state.dcm = {}
    for _, path in ipairs(RUNTIME_FILES) do
        local chunk, message = loadfile(path)
        if not chunk then error(message) end
        setfenv(chunk, env)
        chunk(ADDON, state.dcm)
    end
    -- Random numbers in a fixed cycle, so the effects are repeatable.
    local cycle = 0
    state.dcm.random = function(low, high)
        cycle = cycle + 1
        local fraction = ((cycle * 37) % 100) / 100
        if low and high then return low + math.floor(fraction * (high - low + 1)) end
        if low then return 1 + math.floor(fraction * low) end
        return fraction
    end
    env.DyresCritMayhemDB = options.db
    env.DyresCritMayhemAccountDB = options.account
    state.env = env
    state.emit("ADDON_LOADED", "DyresToolkit")
    state.emit("ADDON_LOADED", ADDON)
    state.emit("PLAYER_LOGIN")

    function state.slash(text) env.SlashCmdList.DYRESCRITMAYHEM(text) end
    function state.cast(unit, spellID)
        state.emit("UNIT_SPELLCAST_SUCCEEDED", unit, "cast-" .. spellID, spellID)
    end
    function state.db() return env.DyresCritMayhemDB end
    -- One combat log event: the 11 common fields, then the rest as given.
    function state.log(subevent, source, dest, ...)
        state.log = nil
        state.logEvent(subevent, source, dest, ...)
    end
    function state.logEvent(subevent, source, dest, ...)
        state.log = {state.now, subevent, false, source, "Source", 0, 0, dest, "Dest", 0, 0, ...}
        state.emit("COMBAT_LOG_EVENT_UNFILTERED")
    end
    -- SWING_DAMAGE: amount 12 ... critical 18.
    function state.swing(source, dest, amount, critical)
        state.logEvent("SWING_DAMAGE", source, dest, amount, -1, 1, nil, nil, nil, critical == true)
    end
    -- SPELL_DAMAGE: spellId 12, name 13, school 14, amount 15 ... critical 21.
    function state.spell(source, dest, name, amount, critical, subevent, school)
        -- No school given: 0, which no style claims, so the theme's own look.
        state.logEvent(subevent or "SPELL_DAMAGE", source, dest, 0, name, school or 0, amount, -1, school or 0, nil,
            nil, nil, critical == true)
    end
    -- SPELL_HEAL: spellId 12, name 13, school 14, amount 15, overhealing 16, absorbed 17, critical 18.
    function state.heal(source, dest, name, amount, critical)
        state.logEvent("SPELL_HEAL", source, dest, 0, name, 2, amount, 0, 0, critical == true)
    end
    -- Runs (Brutal's trickle, Fel's crack) grow from their splats.
    local function isRun(texture) return texture:find("Run1", 1, true) or texture:find("Crack1", 1, true) end
    -- Splatters on screen: shown textures on the overlay, not counting runs or the vignette.
    function state.splats()
        local shown = {}
        for _, child in ipairs(state.dcm.overlay and state.dcm.overlay.children or {}) do
            local texture = child.texture or ""
            if child.shown and not isRun(texture) and not texture:find("Vignette", 1, true) then
                shown[#shown + 1] = child
            end
        end
        return shown
    end
    function state.runs()
        local shown = {}
        for _, child in ipairs(state.dcm.overlay and state.dcm.overlay.children or {}) do
            if child.shown and isRun(child.texture or "") then shown[#shown + 1] = child end
        end
        return shown
    end
    -- The animation groups on a region, and whether any loops and plays.
    function state.groupsOf(region)
        local list = {}
        for _, group in ipairs(state.groups or {}) do
            if group.owner == region then list[#list + 1] = group end
        end
        return list
    end
    function state.moving()
        local count = 0
        for _, group in ipairs(state.groups or {}) do
            if group.playing and (group.looping or isRun(group.owner.texture or "")) then
                count = count + 1
            end
        end
        return count
    end
    function state.soundKeys()
        local keys = {}
        for _, sound in ipairs(state.sounds) do keys[#keys + 1] = sound.key end
        return table.concat(keys, ",")
    end
    -- A theme (Brutal ticks the 18+ box first) and an intensity.
    function state.mayhem(theme, intensity)
        if state.dcm.FindTheme(theme).mature then state.dcm.SetAdult(true) end
        equal(state.dcm.SetTheme(theme).key, theme)
        state.dcm.SetIntensityIndex(state.dcm.INTENSITY_INDEX[intensity])
    end
    function state.last() return state.messages[#state.messages] end
    function state.clear() state.messages, state.sounds, state.chat = {}, {}, {} end
    function state.said(fragment)
        for _, message in ipairs(state.messages) do
            if message:find(fragment, 1, true) then return true end
        end
        return false
    end
    function state.row(name)
        for _, row in ipairs(state.categories["Crit Mayhem"].rows) do
            if row.setting and row.setting.name == name then return row end
            if row.name == name or row.header == name then return row end
        end
    end
    return state
end

-- Startup and commands ----------------------------------------------------------

test("login prints the banner from the TOC and the ready hint", function()
    local state = fixture()
    equal(state.messages[1], "DCM: Dyre's Crit Mayhem 0.2.0 by Dyre")
    contains(state.messages[2], "Type /dcm for your records")
    equal(#state.messages, 2, "nothing else at login")
end)
test("the TOC requires the toolkit, nests under it, and loads the files in order", function()
    local state = fixture()
    equal(state.toc.Title, "Dyre's Crit Mayhem")
    equal(state.toc.Dependencies, "DyresToolkit")
    equal(state.toc.OptionalDeps, "DyresSounds")
    equal(state.toc.Group, "DyresToolkit")
    equal(state.toc.Interface, "16001, 11509")
    equal(state.toc.SavedVariables, "DyresCritMayhemAccountDB")
    equal(state.toc.SavedVariablesPerCharacter, "DyresCritMayhemDB")
    local loads = {}
    for line in io.lines(ADDON .. ".toc") do
        if line:find("%S") and not line:find("^#") then loads[#loads + 1] = line end
    end
    equal(table.concat(loads, " "), table.concat(RUNTIME_FILES, " "))
end)
test("no runtime file changes a CVar or registers an idle OnUpdate", function()
    for _, path in ipairs(RUNTIME_FILES) do
        local source = assert(io.open(path)):read("*a")
        equal(source:find("SetCVar", 1, true), nil, path .. " SetCVar")
        equal(source:find("\"OnUpdate\"", 1, true), nil, path .. " OnUpdate")
        equal(source:find("pcall", 1, true), nil, path .. " pcall")
    end
end)
test("commands are one word; others show usage", function()
    local state = fixture()
    state.clear()
    state.slash("bogus")
    contains(state.last(), "Use /dcm")
    state.slash("test now")
    contains(state.last(), "Use /dcm")
end)
test("/dcm and /critmayhem toggle the records window", function()
    local state = fixture()
    equal(state.env.SLASH_DYRESCRITMAYHEM1, "/dcm")
    equal(state.env.SLASH_DYRESCRITMAYHEM2, "/critmayhem")
    state.slash("")
    equal(state.dcm.window:IsShown(), true)
    state.slash("records")
    equal(state.dcm.window:IsShown(), false)
    equal(state.env.UISpecialFrames[1], "DyresCritMayhemRecordsFrame", "Escape closes it")
end)
test("without the toolkit DCM stays off and says so", function()
    local state = fixture({noToolkit = true})
    equal(state.dcm.available, false)
    contains(state.last(), "needs Dyre's Toolkit 2.0")
    state.slash("")
    contains(state.last(), "unavailable")
    state.slash("debug")
    contains(state.last(), "debug:")
end)
test("a slash clash is reported once at login", function()
    local state = fixture({globals = {SLASH_OTHER1 = "/DCM"}, slashCmdList = {OTHER = function() end}})
    contains(state.last(), "Another AddOn (OTHER) also uses /dcm. Use /critmayhem instead.")
end)

-- Settings, the theme, and the intensity ---------------------------------------

test("a new character starts on Tame at Off, with only its own crits counting", function()
    local state = fixture()
    local db = state.db()
    equal(db.theme, "tame")
    equal(db.intensity, "off")
    equal(db.stay, 100)
    equal(db.mine, true)
    equal(db.pet, false)
    equal(db.taken, false)
    equal(db.heals, false)
    equal(db.announceParty, false)
    equal(db.announceGuild, false)
    equal(db.announceScreen, false)
    equal(state.env.DyresCritMayhemAccountDB.adult, false)
end)
test("damaged saved settings are repaired", function()
    local state = fixture({db = {intensity = "extreme", theme = 5, mine = "yes", records = {
        Fireball = {name = "Fireball", hit = 120, crit = -3},
        Broken = {name = 7, hit = 10},
        Empty = {name = "Empty"},
        [3] = {name = "Number", hit = 1},
    }, sortKey = "bogus"}, account = {adult = "yes"}})
    local db = state.db()
    equal(db.intensity, "off")
    equal(db.theme, "tame")
    equal(db.mine, true)
    equal(db.records.Fireball.hit, 120)
    equal(db.records.Fireball.crit, nil)
    equal(db.records.Broken, nil)
    equal(db.records.Empty, nil)
    equal(db.records[3], nil)
    equal(db.sortKey, "crit")
    equal(state.env.DyresCritMayhemAccountDB.adult, false)
    equal(fixture({db = {theme = "bogus"}}).db().theme, "tame", "an unknown theme")
end)
test("earlier test builds' levels become a theme and an intensity", function()
    local cases = {
        {level = "off", adult = false, theme = "tame", intensity = "off"},
        {level = "tame", adult = true, theme = "tame", intensity = "low"},
        {level = "fun", adult = true, theme = "brutal", intensity = "low"},
        {level = "spicy", adult = true, theme = "brutal", intensity = "medium"},
        {level = "gory", adult = true, theme = "brutal", intensity = "high"},
        {level = "mature", adult = true, theme = "brutal", intensity = "max"},
        {level = "gory", adult = false, theme = "tame", intensity = "high"},
        {level = "fun", adult = false, theme = "tame", intensity = "low"},
    }
    for _, case in ipairs(cases) do
        -- Earlier builds saved theme "brutal" on every character.
        local db = fixture({db = {level = case.level, theme = "brutal"}, account = {adult = case.adult}}).db()
        local context = case.level .. (case.adult and " 18+" or "")
        equal(db.theme, case.theme, context)
        equal(db.intensity, case.intensity, context)
        equal(db.level, nil, context .. ": the old key goes")
    end
    local db = fixture({db = {level = "gory", intensity = "low"}, account = {adult = true}}).db()
    equal(db.intensity, "low", "a newer save wins")
end)
test("Brutal is locked until the 18+ box is ticked", function()
    local state = fixture()
    state.clear()
    equal(state.dcm.SetTheme("brutal").key, "tame")
    equal(state.db().theme, "tame")
    equal(state.last(), "DCM: Brutal is for 18 and over: tick \"I'm 18 or over\" in /dcm options first.")
    state.dcm.SetAdult(true)
    equal(state.dcm.SetTheme("brutal").key, "brutal")
    equal(state.db().theme, "brutal")
    equal(state.env.DyresCritMayhemAccountDB.adult, true, "account-wide")
    equal(state.dcm.SetTheme("bogus").key, "brutal", "an unknown theme changes nothing")
end)
test("unticking the 18+ box puts a character on Brutal back on Tame", function()
    local state = fixture({account = {adult = true}, db = {theme = "brutal", intensity = "high"}})
    equal(state.db().theme, "brutal")
    state.dcm.SetAdult(false)
    equal(state.db().theme, "tame")
    equal(state.db().intensity, "high", "the intensity stays")
    equal(state.last(), "DCM: Brutal is locked again; your theme is back to Tame.")
end)
test("a character saved on Brutal logs in on Tame when the account is not 18+", function()
    local state = fixture({db = {theme = "brutal", intensity = "max"}, account = {adult = false}})
    equal(state.db().theme, "tame")
    equal(state.db().intensity, "max")
end)
test("the settings page: the 18+ box first, the theme, then the intensity and its stay", function()
    local state = fixture()
    local page = state.categories["Crit Mayhem"]
    equal(page.parent, state.categories["Dyre's AddOns"], "under Dyre's AddOns")
    local adult, theme, intensity, stay = page.rows[1], page.rows[2], page.rows[5], page.rows[6]
    equal(adult.setting.name, "I'm 18 or over", "the 18+ box is at the top")
    equal(theme.setting.name, "Theme")
    equal(intensity.setting.name, "Intensity")
    equal(stay.setting.name, "Stays on screen", "under the intensity")
    local labels = {}
    for _, choice in ipairs(theme.choices()) do labels[#labels + 1] = choice.value .. "=" .. choice.label end
    equal(table.concat(labels, ","),
        "tame=Tame,brutal=Brutal (18+),spellburst=Spellburst,fel=Fel (18+),naturalist=Naturalist (18+)")
    equal(intensity.options.minValue, 1)
    equal(intensity.options.maxValue, 5)
    local names = {}
    for value = 1, 5 do names[#names + 1] = intensity.options.formatter(value) end
    equal(table.concat(names, ","), "Off,Low,Medium,High,Total Mayhem")
    intensity.setting:SetValue(5)
    equal(state.db().intensity, "max", "the saved key is unchanged")
    intensity.setting:SetValue(1)
    state.clear()
    theme.setting:SetValue("brutal")
    equal(theme.setting:GetValue(), "tame", "refused Brutal shows Tame")
    contains(state.last(), "Brutal is for 18 and over")
    state.notified = {}
    state.runTimers()
    equal(state.notified[1], "DCM_THEME", "the dropdown redraws")
    adult.setting:SetValue(true)
    equal(theme.choices()[2].label, "Brutal")
    theme.setting:SetValue("brutal")
    equal(theme.setting:GetValue(), "brutal")
    intensity.setting:SetValue(5)
    equal(intensity.setting:GetValue(), 5)
    equal(state.db().intensity, "max")
    state.notified = {}
    state.runTimers()
    equal(state.notified[3], "DCM_STAY", "the stay seconds follow the intensity")
end)
test("the settings page has the switches, the crit kinds, and the records rows", function()
    local state = fixture()
    for _, name in ipairs({"Sounds", "On-screen effects", "My crits", "My pet's crits", "Crits on me",
        "Heals too", "Show new records on screen", "Announce in party", "Announce in guild"}) do
        equal(state.row(name) ~= nil, true, name)
    end
    equal(state.row("Which crits").header, "Which crits")
    equal(state.settings.DYRE_DYRESCRITMAYHEM_RECORDPOP_SCALE ~= nil, true, "the pop's size slider")
    equal(state.row("Your records").buttonText, "Show records")
    state.row("Your records").onClick()
    equal(state.dcm.window:IsShown(), true)
end)
test("/dcm options and the window's Options button open the page", function()
    local state = fixture()
    state.slash("options")
    equal(state.opened, "id:Crit Mayhem")
end)

-- Effects ----------------------------------------------------------------------

test("Off plays nothing, but records and their chat line still count", function()
    for _, theme in ipairs({"tame", "brutal"}) do
        local state = fixture({account = {adult = true}, db = {theme = theme}})
        state.spell(PLAYER, ENEMY, "Fireball", 300, true)
        state.spell(PLAYER, ENEMY, "Fireball", 400, true)
        equal(#state.sounds, 0)
        equal(#state.splats(), 0)
        equal(state.db().records.Fireball.crit, 400)
        contains(state.last(), "New record! Fireball crit 400")
        state.clear()
        state.slash("test")
        contains(state.last(), "Intensity is Off")
    end
end)
test("Tame: pastel butterflies and stars that float up, light sounds, and no blood", function()
    local state = fixture()
    state.mayhem("tame", "low")
    local theme = state.dcm.Theme()
    equal(theme.key, "tame")
    for _ = 1, 8 do
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    end
    local splats = state.splats()
    equal(#splats, 8)
    local pastels = {}
    for _, color in ipairs(theme.colors) do pastels[color[1] .. "," .. color[2]] = true end
    for _, splat in ipairs(splats) do
        equal(splat.texture:find("Splat", 1, true) == nil and splat.texture:find("Drip", 1, true) == nil, true,
            "no blood")
        local known = false
        for _, texture in ipairs(theme.splats) do known = known or texture == splat.texture end
        equal(known, true, splat.texture)
        equal(pastels[splat.vertexColor[1] .. "," .. splat.vertexColor[2]], true, "a pastel")
        equal(math.abs(splat.rotation) <= 0.4, true, "only tilted")
        equal(splat.width < 256 * 0.5, true, "smaller than Brutal's at Low")
    end
    for _, sound in ipairs(state.sounds) do
        local light = false
        for _, key in ipairs(theme.sounds.crit) do light = light or key == sound.key end
        equal(light, true, sound.key)
    end
    equal(#state.sounds, 8)
    state.clear()
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Fireball", 900, true)
    equal(#state.sounds, 1, "a new record's sound, no extra")
    local record = false
    for _, key in ipairs(theme.sounds.big) do record = record or key == state.sounds[1].key end
    equal(record, true, state.sounds[1].key)
    for _, splat in ipairs(state.splats()) do
        local rise
        for _, animation in ipairs(state.groupsOf(splat)[1].animations) do
            if animation.kind == "Translation" then rise = animation.offset[2] end
        end
        equal(rise > 0, true, "floats up")
    end
end)
test("Tame scales with the intensity too, and never drips", function()
    local state = fixture()
    state.mayhem("tame", "max")
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    equal(#state.splats(), state.dcm.Intensity().splats)
    for _, splat in ipairs(state.splats()) do
        equal(splat.texture:find("Drip", 1, true), nil)
    end
end)
test("Tame: stars spin, butterflies flutter, and sparkles twinkle, in loops that stop with them", function()
    local state = fixture()
    state.mayhem("tame", "low")
    local kinds = {}
    for _ = 1, 12 do
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    end
    for _, splat in ipairs(state.splats()) do
        local loop
        for _, group in ipairs(state.groupsOf(splat)) do
            if group.looping then loop = group end
        end
        -- The rainbow only floats.
        if splat.texture:find("Rainbow1", 1, true) then
            equal(loop == nil or not loop.playing, true, "the rainbow does not loop")
        else
            equal(loop ~= nil and loop.playing, true, splat.texture .. " loops")
            local animation = loop.animations[1]
            local name = splat.texture:match("Textures\\(%a+)")
            kinds[name] = true
            if name == "Star" then
                equal(animation.kind, "Rotation")
                equal(math.abs(animation.degrees), 360, "a full turn")
                equal(loop.looping, "REPEAT")
            elseif name == "Butterfly" then
                equal(animation.kind, "Scale")
                equal(animation.scaleTo[1] < 1 and animation.scaleTo[2] == 1, true, "the wings pinch")
                equal(loop.looping, "BOUNCE")
            else
                equal(name, "Sparkle")
                equal(animation.scaleTo[1] > 1, true, "it swells")
                equal(loop.looping, "BOUNCE")
            end
        end
    end
    equal(kinds.Star and kinds.Butterfly and kinds.Sparkle, true, "every kind seen")
    local splat
    for _, candidate in ipairs(state.splats()) do
        if not splat and not candidate.texture:find("Rainbow1", 1, true) then splat = candidate end
    end
    local loop
    for _, group in ipairs(state.groupsOf(splat)) do
        if group.looping then loop = group end
    end
    state.groupsOf(splat)[1]:Finish()
    equal(splat.shown, false)
    equal(loop.playing, false, "the loop stops when the splat goes")
end)
test("Brutal: some splats stay put while a run grows down from under them, and it goes with them", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    -- Every roll low: the run's chance always wins.
    state.dcm.random = function(low) if low then return 1 end return 0 end
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    local splat = state.splats()[1]
    local run = state.runs()[1]
    equal(run ~= nil, true, "a run")
    local point = run.points[#run.points]
    equal(point[1], "TOP")
    equal(point[2], splat, "under its splat")
    equal(point[3], "CENTER")
    equal(run.vertexColor[1], splat.vertexColor[1], "the same red")
    local group = state.groupsOf(run)[1]
    equal(group.playing, true)
    local grow, fade = group.animations[1], group.animations[2]
    equal(grow.kind, "Scale")
    equal(grow.origin[1], "TOP", "grows down from its top")
    equal(grow.scaleFrom[2] < 0.1 and grow.scaleTo[2] == 1, true)
    equal(grow.duration, state.dcm.Intensity().hold)
    equal(fade.delay, state.dcm.Intensity().hold)
    equal(fade.duration, state.dcm.Intensity().fade)
    local slide
    for _, animation in ipairs(state.groupsOf(splat)[1].animations) do
        if animation.kind == "Translation" then slide = animation end
    end
    equal(slide.offset[2], 0, "the splat stays put")
    state.groupsOf(splat)[1]:Finish()
    equal(run.shown, false, "the run goes with its splat")
    equal(group.playing, false)
end)
test("Brutal's runs grow more likely with the intensity; Tame has none", function()
    local dcm = fixture().dcm
    local chance = dcm.FindTheme("brutal").runChance
    equal(chance.low < chance.medium and chance.medium < chance.high and chance.high < chance.max, true)
    equal(dcm.FindTheme("tame").run, nil)
end)
test("at most 12 splats move at once, and a reused splat stops moving", function()
    local state = fixture()
    state.mayhem("tame", "max")
    for _ = 1, 20 do
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    end
    equal(#state.splats(), 32, "the pool is full")
    equal(state.moving() <= 12 and state.moving() >= 10, true, "only 12 move (rainbows float without a loop)")
    state.dcm.ClearEffects()
    equal(state.moving(), 0, "clearing stops them all")
    state.mayhem("brutal", "max")
    state.dcm.random = function(low) if low then return 1 end return 0 end
    for _ = 1, 20 do
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    end
    equal(state.moving() <= 12, true, "runs count too")
    equal(#state.runs() <= 12, true)
end)
test("sounds: each theme has 2 or more per event, picked at random, never twice in a row", function()
    local dcm = fixture().dcm
    for _, theme in ipairs(dcm.Themes()) do
        for _, event in ipairs({"crit", "big"}) do
            local pool = theme.sounds[event]
            -- Fel's record is its one demon growl (the author's Fel Sounds).
            local least = (theme.key == "fel" and event == "big") and 1 or 2
            equal(#pool >= least and #pool <= 5, true, theme.key .. " " .. event)
        end
    end
    equal(#dcm.FindTheme("brutal").sounds.extra, 2)
    local state = fixture()
    state.mayhem("brutal", "low")
    local seen, last = {}, nil
    for _ = 1, 30 do
        local key = state.dcm.PickSound("crit")
        equal(key ~= last, true, "no repeat: " .. key)
        seen[key], last = true, key
    end
    equal(seen.goreslice and seen.gorechop and seen.gorebash, true, "every one of the pool comes up")
end)
test("sounds: your own pick wins, stays across themes, and Reset puts the theme's back", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    local row
    for _, candidate in ipairs(state.categories["Crit Mayhem"].rows) do
        if candidate.name == "Crit: my own sound" then row = candidate end
    end
    equal(row.checkboxDropdown, true, "a box and its sound on one row")
    equal(row.soundMenu, true, "Dyre's Sounds' nested menu")
    local sound = row.data.dropdownSetting
    equal(sound:GetValue(), "goreslice", "shows the theme's first before a pick")
    row.setting:SetValue(true)
    sound:SetValue("laserswing")
    equal(state.sounds[#state.sounds].key, "laserswing", "choosing one plays it")
    for _ = 1, 5 do equal(state.dcm.PickSound("crit"), "laserswing") end
    state.mayhem("tame", "low")
    equal(state.dcm.PickSound("crit"), "laserswing", "kept across theme changes")
    equal(state.row("Theme sounds").buttonText, "Reset sounds to theme")
    state.row("Theme sounds").onClick()
    contains(state.last(), "back to Tame's")
    equal(state.db().soundPicks.crit.on, false)
    equal(state.db().soundPicks.crit.key, "laserswing", "the pick is remembered for next time")
    local key = state.dcm.PickSound("crit")
    equal(key == "kiss" or key == "swishsmack" or key == "war3magicshimmer", true, key)
end)
test("sounds: a theme change shows the new theme's sounds in rows whose box is clear", function()
    local state = fixture({account = {adult = true}})
    local function Row(name)
        for _, candidate in ipairs(state.categories["Crit Mayhem"].rows) do
            if candidate.name == name then return candidate end
        end
    end
    local crit, big = Row("Crit: my own sound"), Row("New record: my own sound")
    equal(crit.data.dropdownSetting:GetValue(), "kiss", "Tame's first")
    equal(big.data.dropdownSetting:GetValue(), "kisses")
    -- A pick made earlier, then the box cleared: the pick is kept.
    crit.setting:SetValue(true)
    crit.data.dropdownSetting:SetValue("laserswing")
    crit.setting:SetValue(false)
    equal(crit.data.dropdownSetting:GetValue(), "kiss", "clear: the theme's, not the pick")
    state.notified = {}
    state.row("Theme").setting:SetValue("brutal")
    state.runTimers()
    local notified = table.concat(state.notified, ",")
    contains(notified, "DCM_SOUND_CRIT,", "the crit row redraws")
    contains(notified, "DCM_SOUND_BIG,")
    contains(notified, "DCM_SOUND_EXTRA")
    equal(crit.data.dropdownSetting:GetValue(), "goreslice", "Brutal's now")
    equal(big.data.dropdownSetting:GetValue(), "gorebloody")
    equal(state.db().soundPicks.crit.key, "laserswing", "the pick is kept")
    crit.setting:SetValue(true)
    equal(crit.data.dropdownSetting:GetValue(), "laserswing", "ticked: your pick again")
    state.notified = {}
    state.row("Theme sounds").onClick()
    contains(table.concat(state.notified, ","), "DCM_SOUND_CRIT", "reset redraws the rows")
    equal(crit.data.dropdownSetting:GetValue(), "goreslice")
end)
-- A settings row frame as the client pools it: showing one initializer, its
-- dropdown text read from the setting when its menu is built.
local function rowFrame(initializer)
    local frame = {elementData = initializer, scripts = {}}
    function frame:GetElementData() return self.elementData end
    function frame:HookScript(name, callback) self.scripts[name] = callback end
    if initializer.data then
        local dropdown = {}
        function dropdown:GenerateMenu()
            self.built = (self.built or 0) + 1
            self.text = initializer.data.dropdownSetting:GetValue()
        end
        frame.Control = {Dropdown = dropdown}
    end
    initializer:InitFrame(frame)
    if frame.Control then frame.Control.Dropdown:GenerateMenu() end
    return frame
end
test("sounds: the shown rows redraw their sound on a theme change, both ways", function()
    for _, case in ipairs({{from = "tame", to = "brutal", before = "kiss", after = "goreslice"},
        {from = "brutal", to = "tame", before = "goreslice", after = "kiss"}}) do
        local state = fixture({account = {adult = true}, db = {theme = case.from}})
        local rows = {}
        for _, candidate in ipairs(state.categories["Crit Mayhem"].rows) do
            if candidate.checkboxDropdown then rows[#rows + 1] = rowFrame(candidate) end
        end
        equal(#rows, 3)
        equal(rows[1].Control.Dropdown.text, case.before, "opens on the saved theme's sound: " .. case.from)
        local theme = state.row("Theme")
        theme.setting:SetValue(case.to)
        state.runTimers()
        equal(rows[1].Control.Dropdown.text, case.after, case.from .. " to " .. case.to)
        equal(rows[2].Control.Dropdown.built, 2, "every shown row is built again")
        -- A frame the pool gave to another row is left alone.
        rows[3].elementData = {}
        local built = rows[3].Control.Dropdown.built
        theme.setting:SetValue(case.from)
        state.runTimers()
        equal(rows[3].Control.Dropdown.built, built)
        equal(rows[1].Control.Dropdown.text, case.before)
    end
end)
test("sounds: Reset and the box redraw the rows too", function()
    local state = fixture()
    local crit
    for _, candidate in ipairs(state.categories["Crit Mayhem"].rows) do
        if candidate.name == "Crit: my own sound" then crit = candidate end
    end
    local frame = rowFrame(crit)
    crit.setting:SetValue(true)
    crit.data.dropdownSetting:SetValue("laserswing")
    state.runTimers()
    equal(frame.Control.Dropdown.text, "laserswing")
    state.row("Theme sounds").onClick()
    equal(frame.Control.Dropdown.text, "kiss", "reset: the theme's again")
end)
test("section headers show no tooltip that only repeats their name", function()
    local state = fixture()
    local headers = 0
    for _, row in ipairs(state.categories["Crit Mayhem"].rows) do
        if row.header then
            headers = headers + 1
            local frame = rowFrame(row)
            state.env.SettingsTooltip:Show()
            frame.scripts.OnEnter(frame)
            equal(state.env.SettingsTooltip.shown, false, row.header)
            -- The same pooled frame on another page keeps Blizzard's tooltip.
            frame.elementData = {}
            state.env.SettingsTooltip:Show()
            frame.scripts.OnEnter(frame)
            equal(state.env.SettingsTooltip.shown, true)
        end
    end
    equal(headers, 3, "Which crits, Sounds, Records")
end)
test("sounds: keys an older Dyre's Sounds lacks fall back to the theme's others, then a chime", function()
    local state = fixture({missingKeys = {"goreslice", "gorechop", "gorebash"}})
    state.mayhem("brutal", "low")
    for _ = 1, 10 do
        local key = state.dcm.PickSound("crit")
        equal(key ~= "goreslice" and key ~= "gorechop" and key ~= "gorebash", true, key)
    end
    local none = {"goreslice", "gorechop", "gorebash", "goresplat", "gorebloody", "wetsplat", "wetpunch"}
    state = fixture({missingKeys = none})
    state.mayhem("brutal", "low")
    equal(state.dcm.PickSound("crit"), "talent", "Interface: Talent ready, which every client plays")
    equal(state.dcm.PickSound("big"), "talent")
end)
-- Dyre's Fel Sounds, new in Dyre's Sounds 1.4.0.
local FEL_KEYS = {"felheartbeat", "felwetsmash", "felmudsplat", "feldemongrowl"}
test("sounds on Classic: the game's kit sounds are skipped, so every theme still has a sound for each event",
        function()
    local state = fixture({classic = true})
    for _, theme in ipairs({"tame", "brutal", "spellburst", "fel", "naturalist"}) do
        state.mayhem(theme, "medium")
        for _, event in ipairs({"crit", "big"}) do
            for _ = 1, 12 do
                local key = state.dcm.PickSound(event)
                equal(state.env.DyresSounds.Playable(key), true, theme .. " " .. event .. ": " .. key)
            end
        end
    end
    -- Two or more playable for a crit, so the no-repeat rule still varies them.
    state.mayhem("spellburst", "low")
    local seen = {}
    for _ = 1, 20 do seen[state.dcm.PickSound("crit")] = true end
    equal(seen.magical and seen.fadingslow, true, "Spellburst on Era: its Dyre's Picks")
    state.mayhem("fel", "low")
    seen = {}
    for _ = 1, 20 do seen[state.dcm.PickSound("crit")] = true end
    equal(seen.felwetsmash and seen.felmudsplat and seen.felheartbeat, true, "Fel on Era: its Fel Sounds")
    -- Dyre's Sounds 1.3.0 (no Fel Sounds) on Era: the fallback's Dyre's Gore,
    -- no kit sounds.
    state = fixture({classic = true, missingKeys = FEL_KEYS})
    state.mayhem("fel", "low")
    seen = {}
    for _ = 1, 20 do seen[state.dcm.PickSound("crit")] = true end
    equal(seen.gorebash and seen.gorechop, true, "Fel on Era with 1.3.0: Dyre's Gore")
    equal(seen.impactslowthud, nil)
    -- Where kit sounds play, they stay in the fallback pool.
    state = fixture({missingKeys = FEL_KEYS})
    state.mayhem("fel", "low")
    seen = {}
    for _ = 1, 40 do seen[state.dcm.PickSound("crit")] = true end
    equal(seen.impactslowthud ~= nil or seen.impactsstrangeclang ~= nil or seen.instrumentssynthbuzz ~= nil, true,
        "kit sounds on a client that plays them")
end)
test("sounds with an older Dyre's Sounds (no Playable): every key it has may play", function()
    local state = fixture({noPlayable = true, missingKeys = FEL_KEYS})
    state.mayhem("fel", "low")
    local seen = {}
    for _ = 1, 40 do seen[state.dcm.PickSound("crit")] = true end
    equal(seen.impactslowthud ~= nil or seen.impactsstrangeclang ~= nil or seen.instrumentssynthbuzz ~= nil, true)
end)
test("Text to Speech says the event's words, also in the preview", function()
    local state = fixture()
    state.mayhem("tame", "low")
    for _, row in ipairs(state.categories["Crit Mayhem"].rows) do
        if row.checkboxDropdown then row.setting:SetValue(true) end
    end
    local crit, big
    for _, row in ipairs(state.categories["Crit Mayhem"].rows) do
        if row.name == "Crit: my own sound" then crit = row end
        if row.name == "New record: my own sound" then big = row end
    end
    crit.data.dropdownSetting:SetValue("voice")
    equal(state.sounds[#state.sounds].speech, "Crit!", "the preview speaks")
    big.data.dropdownSetting:SetValue("voice")
    equal(state.sounds[#state.sounds].speech, "New record!")
    state.clear()
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    equal(state.sounds[1].key, "voice")
    equal(state.sounds[1].speech, "Crit!")
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Fireball", 900, true)
    equal(state.sounds[#state.sounds].speech, "New record!")
end)
test("damaged sound picks are repaired", function()
    local db = fixture({db = {soundPicks = {crit = {on = "yes", key = 5}, big = "x"}}}).db()
    equal(db.soundPicks.crit.on, false)
    equal(db.soundPicks.crit.key, nil)
    equal(db.soundPicks.big.on, false)
    equal(db.soundPicks.extra.on, false)
end)
-- The effect's first shown texture after one crit, and every one.
local function firstSplat(state) return state.splats()[1] end
local function sameColor(color, expected) return color[1] == expected[1] and color[2] == expected[2]
    and color[3] == expected[3] end
test("Spellburst: bursts of light tinted by spell school, drawn additively", function()
    local state = fixture()
    state.mayhem("spellburst", "low")
    local cases = {
        {school = 4, color = {1, 0.5, 0.12}, name = "fire", textures = {"Burst1", "Flame1"}},
        {school = 16, color = {0.45, 0.8, 1}, name = "frost", textures = {"Burst2", "Shard1"}},
        {school = 64, color = {0.9, 0.45, 1}, name = "arcane"},
        {school = 32, color = {0.6, 0.3, 0.95}, name = "shadow"},
        {school = 8, color = {0.4, 1, 0.4}, name = "nature", textures = {"Burst1", "Maple1", "Oak1", "Birch1"}},
        {school = 2, color = {1, 0.92, 0.6}, name = "holy"},
        {school = 20, color = {1, 0.5, 0.12}, name = "frostfire reads as fire", textures = {"Burst1", "Flame1"}},
        {school = 0, color = {0.85, 0.85, 1}, name = "unknown: arcane white"},
    }
    for _, case in ipairs(cases) do
        state.dcm.ClearEffects()
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Spell", 100, true, "SPELL_DAMAGE", case.school)
        local splat = firstSplat(state)
        equal(sameColor(splat.vertexColor, case.color), true, case.name)
        equal(splat.blend, "ADD")
        local known = false
        for _, name in ipairs(case.textures or {"Burst1", "Burst2"}) do
            known = known or splat.texture:find(name, 1, true) ~= nil
        end
        equal(known, true, case.name .. ": " .. splat.texture)
    end
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.swing(PLAYER, ENEMY, 50, true)
    contains(firstSplat(state).texture, "Textures\\", "a melee crit")
    equal(firstSplat(state).texture:find("Splat", 1, true), nil, "no blood without the 18+ box")
    local school = secret()
    state.secrets[school] = true
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Spell", 100, true, "SPELL_DAMAGE", school)
    equal(sameColor(firstSplat(state).vertexColor, {0.85, 0.85, 1}), true, "a secret school: arcane white")
    -- Back on Brutal, a reused texture blends normally again.
    state.mayhem("brutal", "low")
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Spell", 100, true)
    equal(firstSplat(state).blend, "BLEND")
end)
test("Spellburst: motes rise from Medium, and a ring closes a new record's set and every set from High", function()
    local state = fixture()
    state.mayhem("spellburst", "low")
    state.spell(PLAYER, ENEMY, "Fireball", 100, true, "SPELL_DAMAGE", 4)
    for _, splat in ipairs(state.splats()) do
        equal(splat.texture:find("Mote", 1, true) == nil and splat.texture:find("Ring", 1, true) == nil, true,
            "Low: bursts only")
    end
    state.now = state.now + 1
    state.dcm.ClearEffects()
    state.spell(PLAYER, ENEMY, "Fireball", 300, true, "SPELL_DAMAGE", 4)
    local rings = 0
    for _, splat in ipairs(state.splats()) do
        if splat.texture:find("Ring1", 1, true) then rings = rings + 1 end
    end
    equal(rings, 1, "a new record's ring")
    state.mayhem("spellburst", "high")
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Frostbolt", 100, true, "SPELL_DAMAGE", 16)
    local motes, ring = 0, 0
    for _, splat in ipairs(state.splats()) do
        if splat.texture:find("Mote1", 1, true) then
            motes = motes + 1
            local rise
            for _, animation in ipairs(state.groupsOf(splat)[1].animations) do
                if animation.kind == "Translation" then rise = animation.offset[2] end
            end
            equal(rise > 0, true, "a mote rises")
        elseif splat.texture:find("Ring1", 1, true) then
            ring = ring + 1
        end
    end
    equal(motes, 1)
    equal(ring, 1, "High: a ring every crit")
    equal(#state.runs(), 0, "no blood runs")
end)
test("Spellburst shows crit heals rising in holy or nature light", function()
    local state = fixture({db = {heals = true}})
    state.mayhem("spellburst", "low")
    state.logEvent("SPELL_HEAL", PLAYER, PLAYER, 0, "Flash Heal", 2, 500, 0, 0, true)
    local splat = firstSplat(state)
    equal(splat ~= nil, true, "a heal shows")
    equal(sameColor(splat.vertexColor, {1, 0.92, 0.6}), true, "holy")
    local rise
    for _, animation in ipairs(state.groupsOf(splat)[1].animations) do
        if animation.kind == "Translation" then rise = animation.offset[2] end
    end
    equal(rise > 0, true, "rises")
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.logEvent("SPELL_HEAL", PLAYER, PLAYER, 0, "Healing Touch", 8, 500, 0, 0, true)
    equal(sameColor(firstSplat(state).vertexColor, {0.4, 1, 0.4}), true, "nature")
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.logEvent("SPELL_HEAL", PLAYER, PLAYER, 0, "Drain Life", 32, 50, 0, 0, true)
    equal(sameColor(firstSplat(state).vertexColor, {1, 0.92, 0.6}), true, "any other heal: holy")
    contains(firstSplat(state).texture, "Burst", "Spellburst's own look")
end)
-- Each theme's heal crit: its heal style's textures and colors, rising.
local HEALS = {
    tame = {textures = {"Heart1", "Sparkle1", "Butterfly1"}, colors = {{1, 0.6, 0.75}, {1, 0.85, 0.4}}},
    brutal = {textures = {"Embers1", "Mote1"}, colors = {{0.95, 0.3, 0.2}, {1, 0.75, 0.3}}, blend = "ADD"},
    fel = {textures = {"Smoke1", "Smoke2", "Embers1"}, colors = {{0.35, 0.9, 0.15}, {0.6, 1, 0.4}}, blend = "ADD"},
    naturalist = {textures = {"Vine1", "Smoke1", "Smoke2"}, colors = {{0.4, 0.75, 0.3}, {0.85, 0.72, 0.3}}},
}
local function healLook(state, splat, theme)
    local look = HEALS[theme]
    local known, colored = false, false
    for _, name in ipairs(look.textures) do known = known or splat.texture:find(name, 1, true) ~= nil end
    for _, color in ipairs(look.colors) do colored = colored or sameColor(splat.vertexColor, color) end
    local rise
    for _, animation in ipairs(state.groupsOf(splat)[1].animations) do
        if animation.kind == "Translation" then rise = animation.offset[2] end
    end
    return known and colored and rise > 0 and (not look.blend or splat.blend == look.blend)
end
test("every theme draws heal crits in its own gentle, rising style; damage is unchanged", function()
    for _, theme in ipairs({"tame", "brutal", "fel", "naturalist"}) do
        local state = fixture({db = {heals = true}})
        state.mayhem(theme, "high")
        rolls(state, 0)
        for _ = 1, 6 do
            state.now = state.now + 1
            state.heal(PLAYER, PLAYER, "Holy Light", 500, true)
        end
        equal(#state.splats() > 0, true, theme .. ": a heal shows")
        for _, splat in ipairs(state.splats()) do
            equal(healLook(state, splat, theme), true, theme .. ": " .. splat.texture)
        end
        equal(#state.runs(), 0, theme .. ": no runs or cracks for heals")
        equal(state.dcm.vignette, nil, theme .. ": no vignette for heals")
        -- Damage looks as before.
        state.dcm.ClearEffects()
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Crusader Strike", 100, true)
        for _, splat in ipairs(state.splats()) do
            equal(splat.texture:find("Heart1", 1, true), nil, theme .. ": no hearts for damage")
            if theme == "brutal" then
                equal((splat.texture:find("Splat", 1, true) or splat.texture:find("Drip", 1, true)) ~= nil, true,
                    "Brutal's blood")
            end
            if theme == "fel" then equal(splat.blend == "BLEND" or splat.texture:find("Embers1", 1, true) ~= nil,
                true, "Fel's dark smoke") end
        end
    end
end)
test("Tame's hearts beat; Brutal's heals have no blood", function()
    local state = fixture({db = {heals = true}})
    state.mayhem("tame", "low")
    rolls(state, 0)
    state.heal(PLAYER, PLAYER, "Holy Light", 500, true)
    local heart = firstSplat(state)
    contains(heart.texture, "Heart1")
    local loop
    for _, group in ipairs(state.groupsOf(heart)) do
        if group.looping then loop = group end
    end
    equal(loop.animations[1].kind, "Scale", "it pulses")
    state.mayhem("brutal", "max")
    for _ = 1, 10 do
        state.now = state.now + 1
        state.heal(PLAYER, PLAYER, "Holy Light", 500, true)
    end
    for _, splat in ipairs(state.splats()) do
        equal(splat.texture:find("Splat", 1, true) == nil and splat.texture:find("Drip", 1, true) == nil, true,
            "no gore: " .. splat.texture)
    end
end)
test("with Heals too off, heal crits show and sound nothing in any theme", function()
    for _, theme in ipairs({"tame", "brutal", "spellburst", "fel"}) do
        local state = fixture()
        state.mayhem(theme, "high")
        state.heal(PLAYER, PLAYER, "Holy Light", 500, true)
        equal(#state.splats(), 0, theme)
        equal(#state.sounds, 0, theme)
    end
end)
test("Spellburst on Forever: the school comes from combat text", function()
    local state = fixture({restrictCombatLog = true})
    state.mayhem("spellburst", "low")
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 300, 16)
    equal(sameColor(firstSplat(state).vertexColor, {0.45, 0.8, 1}), true, "frost")
end)
test("Spellburst's sounds come from Dyre's Sounds' own, in one table", function()
    local state = fixture()
    state.mayhem("spellburst", "medium")
    rolls(state, 0)
    local sounds = state.dcm.FindTheme("spellburst").sounds
    equal(table.concat(sounds.crit, ","), "magical,fadingslow,war2magicchimes,instrumentsbelltrill")
    equal(table.concat(sounds.big, ","), "blowswoosh,war2choir,instrumentschimeascending")
    equal(table.concat(sounds.extra, ","), "teleportvanish,disappearingswoosh,impactsbubblesmash")
    state.spell(PLAYER, ENEMY, "Fireball", 100, true, "SPELL_DAMAGE", 4)
    local keys = state.soundKeys()
    equal((keys:find("magical", 1, true) or keys:find("fadingslow", 1, true) or keys:find("war2magicchimes", 1, true)
        or keys:find("instrumentsbelltrill", 1, true)) ~= nil, true, keys)
    equal((keys:find("teleportvanish", 1, true) or keys:find("disappearingswoosh", 1, true)
        or keys:find("impactsbubblesmash", 1, true)) ~= nil, true, "the extra from Medium: " .. keys)
end)
test("/dcm test runs through the schools", function()
    local state = fixture()
    state.mayhem("spellburst", "low")
    state.slash("test")
    equal(sameColor(firstSplat(state).vertexColor, {1, 0.5, 0.12}), true, "fire first")
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.slash("test")
    equal(sameColor(firstSplat(state).vertexColor, {0.45, 0.8, 1}), true, "then frost")
end)
local FEL_GREEN, SHADOW, HELLFIRE = {0.35, 0.9, 0.15}, {0.22, 0.08, 0.3}, {0.95, 0.3, 0.08}
local function felColor(color)
    return sameColor(color, FEL_GREEN) or sameColor(color, SHADOW) or sameColor(color, HELLFIRE)
end
test("Fel is 18+ like Brutal: refused without the box, back to Tame when it is cleared", function()
    local state = fixture()
    local fel = state.dcm.FindTheme("fel")
    equal(fel.name, "Fel")
    equal(fel.mature, true)
    state.clear()
    equal(state.dcm.SetTheme("fel").key, "tame", "refused without the box")
    equal(state.last(), "DCM: Fel is for 18 and over: tick \"I'm 18 or over\" in /dcm options first.")
    state.dcm.SetAdult(true)
    equal(state.dcm.SetTheme("fel").key, "fel")
    state.dcm.SetAdult(false)
    equal(state.db().theme, "tame")
    equal(state.last(), "DCM: Fel is locked again; your theme is back to Tame.")
    equal(fixture({db = {theme = "fel"}}).db().theme, "tame", "saved on Fel without the box: Tame at login")
    equal(fixture({db = {theme = "fel"}, account = {adult = true}}).db().theme, "fel")
    equal(fixture().db().theme, "tame", "new characters start on Tame")
    for _, texture in ipairs(fel.splats) do
        equal(texture:find("Star") or texture:find("Sparkle") or texture:find("Butterfly") or texture:find("Burst")
            or texture:find("Mote"), nil, "no sparkle: " .. texture)
    end
end)
test("Fel: shadow crits are shadow, fire crits hellfire or fel, anything else the fel palette", function()
    local state = fixture()
    state.mayhem("fel", "low")
    local function colorOf(school)
        state.dcm.ClearEffects()
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Spell", 100, true, "SPELL_DAMAGE", school)
        return firstSplat(state).vertexColor
    end
    equal(sameColor(colorOf(32), SHADOW), true, "shadow")
    for _ = 1, 4 do
        local color = colorOf(4)
        equal(sameColor(color, HELLFIRE) or sameColor(color, FEL_GREEN), true, "fire")
    end
    local shadowflame = colorOf(36)
    equal(sameColor(shadowflame, HELLFIRE) or sameColor(shadowflame, FEL_GREEN), true,
        "shadowflame reads as fire (fire comes first)")
    local frost = colorOf(16)
    equal(sameColor(frost, {0.5, 0.65, 0.8}) or sameColor(frost, {0.35, 0.45, 0.6}), true, "frost: Fel's icy smoke")
    local school = secret()
    state.secrets[school] = true
    equal(felColor(colorOf(school)), true, "a secret school: the fel palette")
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Spell", 100, true, "SPELL_DAMAGE", 0)
    equal(felColor(firstSplat(state).vertexColor), true, "an unknown school: the fel palette")
    equal(firstSplat(state).blend, "BLEND", "smoke is dark, not added light")
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.swing(PLAYER, ENEMY, 50, true)
    local gore = firstSplat(state)
    equal((gore.texture:find("Splat", 1, true) or gore.texture:find("Drip", 1, true)) ~= nil, true, "melee: gore")
    equal(sameColor(gore.vertexColor, {0.62, 0.02, 0.02}), true, "Brutal's blood")
end)
test("Fel: smoke curls and rises, embers fall from Medium, cracks spread from where it landed", function()
    local state = fixture()
    state.mayhem("fel", "medium")
    state.dcm.random = function(low) if low then return 1 end return 0 end
    state.spell(PLAYER, ENEMY, "Shadow Bolt", 100, true, "SPELL_DAMAGE", 32)
    local smoke, embers = 0, 0
    for _, splat in ipairs(state.splats()) do
        local main = state.groupsOf(splat)[1]
        local offset
        for _, animation in ipairs(main.animations) do
            if animation.kind == "Translation" then offset = animation.offset[2] end
        end
        if splat.texture:find("Embers1", 1, true) then
            embers = embers + 1
            equal(offset < 0, true, "embers fall")
            equal(splat.blend, "ADD", "embers glow")
        else
            smoke = smoke + 1
            equal(offset > 0, true, "smoke rises")
            local loop
            for _, group in ipairs(state.groupsOf(splat)) do
                if group.looping then loop = group end
            end
            equal(loop.animations[1].kind, "Rotation", "it curls")
        end
    end
    equal(embers, 1)
    equal(smoke, 1)
    local cracks = {}
    for _, child in ipairs(state.dcm.overlay.children) do
        if child.shown and (child.texture or ""):find("Crack1", 1, true) then cracks[#cracks + 1] = child end
    end
    equal(#cracks, 1, "a crack under the smoke")
    local point = cracks[1].points[#cracks[1].points]
    equal(point[1], "CENTER")
    equal(point[2], state.dcm.overlay, "on the overlay, where the smoke landed")
    local grow = state.groupsOf(cracks[1])[1].animations[1]
    equal(grow.origin[1], "CENTER", "spreads from its middle")
    equal(grow.scaleFrom[1] < 0.1 and grow.scaleFrom[2] < 0.1, true)
    equal(cracks[1].blend, "BLEND")
end)
test("Fel: a new record darkens the screen's edges, then fades slowly", function()
    local state = fixture()
    state.mayhem("fel", "low")
    state.spell(PLAYER, ENEMY, "Shadow Bolt", 100, true, "SPELL_DAMAGE", 32)
    equal(state.dcm.vignette, nil, "not for a plain crit")
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Shadow Bolt", 300, true, "SPELL_DAMAGE", 32)
    local vignette = state.dcm.vignette
    equal(vignette.shown, true)
    contains(vignette.texture, "Vignette1")
    equal(vignette.allPoints, state.dcm.overlay, "the whole screen")
    local group = state.groupsOf(vignette)[1]
    equal(group.playing, true)
    local fade = group.animations[2]
    equal(fade.from, 1)
    equal(fade.to, 0)
    equal(fade.duration >= 2, true, "a slow fade")
    group:Finish()
    equal(vignette.shown, false)
    state.mayhem("brutal", "low")
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Shadow Bolt", 900, true)
    equal(vignette.shown, false, "only Fel has it")
end)
test("Fel's sounds: Dyre's Fel Sounds in one table, the extra never doubling the crit's heartbeat", function()
    local state = fixture()
    state.mayhem("fel", "medium")
    rolls(state, 0)
    local sounds = state.dcm.FindTheme("fel").sounds
    equal(table.concat(sounds.crit, ","), "felwetsmash,felmudsplat,felheartbeat")
    equal(table.concat(sounds.big, ","), "feldemongrowl")
    equal(table.concat(sounds.extra, ","), "felheartbeat")
    equal(sounds.extraFrom, "medium")
    state.spell(PLAYER, ENEMY, "Corruption", 100, true, "SPELL_DAMAGE", 32)
    equal(state.soundKeys(), "felwetsmash,felheartbeat", "a smash, then the heartbeat from Medium")
    -- The crit's own sound the heartbeat: no second heartbeat.
    state.sounds = {}
    state.now = state.now + 1
    state.dcm.random = function(low) if low then return low end return 0 end
    state.spell(PLAYER, ENEMY, "Corruption", 100, true, "SPELL_DAMAGE", 32)
    equal(state.soundKeys(), "felheartbeat", "one heartbeat")
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Shadow Bolt", 100, true, "SPELL_DAMAGE", 32)
    state.sounds = {}
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Shadow Bolt", 900, true, "SPELL_DAMAGE", 32)
    equal(state.soundKeys(), "feldemongrowl", "the demon growl for a record")
end)
test("Fel's sounds with Dyre's Sounds 1.3.0 (no Fel Sounds): the earlier pools", function()
    local state = fixture({missingKeys = FEL_KEYS})
    state.mayhem("fel", "medium")
    local seen = {}
    for _ = 1, 30 do seen[state.dcm.PickSound("crit")] = true end
    equal(seen.gorebash and seen.gorechop, true, "Dyre's Gore")
    equal(seen.felwetsmash, nil)
    local big = state.dcm.PickSound("big")
    equal(big == "bigmonsterroar" or big == "monsterbear", true, big)
    local extra = state.dcm.PickSound("extra")
    equal(extra == "orcfury" or extra == "instrumentspitchpipedistressed", true, extra)
end)
local KINDS = {"physical", "holy", "fire", "nature", "frost", "shadow", "arcane"}
local function bloody(texture)
    return texture:find("Splat", 1, true) or texture:find("Drip", 1, true) or texture:find("Run1", 1, true)
end
local function gore(style)
    for _, texture in ipairs(style.splats) do
        if bloody(texture) then return true end
    end
    for _, texture in ipairs(style.drips or {}) do
        if bloody(texture) then return true end
    end
    return style.run and bloody(style.run) and true or false
end
test("nature leaves: maple most, oak, and birch, tumbling; Tame in autumn pastels", function()
    local state = fixture()
    local tame, spellburst = state.dcm.FindTheme("tame"), state.dcm.FindTheme("spellburst")
    local counts = {}
    for _, texture in ipairs(state.dcm.CritStyle(tame, 8).splats) do
        local name = texture:match("(%w+)$")
        counts[name] = (counts[name] or 0) + 1
    end
    equal(counts.Maple1 > counts.Oak1 and counts.Maple1 > counts.Birch1, true, "maple weighted highest")
    equal(counts.Leaf1, nil, "Leaf1 is retired")
    local style = state.dcm.CritStyle(tame, 8)
    equal(#style.colors, 4, "soft red, orange, gold, and a green")
    for _, name in ipairs({"Maple1", "Oak1", "Birch1"}) do
        local texture = "Interface\\AddOns\\DyresCritMayhem\\Textures\\" .. name
        equal(style.animations[texture], "spin", name .. " tumbles in Tame")
        equal(state.dcm.CritStyle(spellburst, 8).animations[texture], "spin", name .. " tumbles in Spellburst")
    end
    local leaves = {}
    for _, texture in ipairs(state.dcm.CritStyle(spellburst, 8).accent.textures) do
        leaves[texture:match("(%w+)$")] = true
    end
    equal(leaves.Maple1 and leaves.Oak1 and leaves.Birch1, true, "leaves blow from the green burst")
    equal(state.dcm.CritStyle(spellburst, 8).splats[1]:match("(%w+)$"), "Burst1", "the green burst")
end)
-- The accent's effects: drawn above the set (ARTWORK sublevel 2, an
-- overlay 3).
local function accents(state, sublevel)
    local list = {}
    for _, splat in ipairs(state.splats()) do
        if splat.sublevel == (sublevel or 2) then list[#list + 1] = splat end
    end
    return list
end
local function slideOf(state, splat)
    for _, animation in ipairs(state.groupsOf(splat)[1].animations) do
        if animation.kind == "Translation" then return animation.offset end
    end
end
local function looping(state, splat)
    for _, group in ipairs(state.groupsOf(splat)) do
        if group.looping and group.playing then return true end
    end
    return false
end
local function leaf(texture)
    return texture:find("Maple1", 1, true) or texture:find("Oak1", 1, true) or texture:find("Birch1", 1, true)
end
test("nature accents: Tame and Spellburst blow a puff of 3 to 5 tumbling leaves, down and up", function()
    for _, case in ipairs({{"tame", -1}, {"spellburst", 1}}) do
        local state = fixture()
        state.mayhem(case[1], "low")
        rolls(state, 0)
        state.spell(PLAYER, ENEMY, "Wrath", 100, true, "SPELL_DAMAGE", 8)
        local puff = accents(state)
        equal(#puff, 3, case[1] .. ": the fewest leaves on the lowest roll")
        local first = state.splats()[1]
        for _, splat in ipairs(puff) do
            equal(leaf(splat.texture) ~= nil, true, case[1] .. ": a leaf")
            local offset = slideOf(state, splat)
            equal(offset[2] * case[2] > 0, true, case[1] .. ": drifts " .. (case[2] > 0 and "up" or "down"))
            equal(offset[1] ~= 0, true, case[1] .. ": blows outward")
            equal(looping(state, splat), true, case[1] .. ": tumbles")
            local point, base = splat.points[#splat.points], first.points[#first.points]
            equal(math.abs(point[4] - base[4]) <= 40 and math.abs(point[5] - base[5]) <= 40, true,
                case[1] .. ": around the set's first splat")
        end
        equal(#state.runs(), 0, case[1] .. ": no runs")
        local style = state.dcm.CritStyle(state.dcm.FindTheme(case[1]), 8)
        equal(style.accent.count[1], 3)
        equal(style.accent.count[2], 5)
    end
    local state = fixture()
    state.mayhem("tame", "low")
    rolls(state, 0)
    state.dcm.random = function(low, high)
        if low and high then return high end
        if low then return low end
        return 0
    end
    state.spell(PLAYER, ENEMY, "Wrath", 100, true, "SPELL_DAMAGE", 8)
    equal(#accents(state), 5, "the most leaves on the highest roll")
end)
test("nature accents: Brutal's blood-soaked leaves stick on the splat and smear down", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    rolls(state, 0)
    state.spell(PLAYER, ENEMY, "Wrath", 100, true, "SPELL_DAMAGE", 8)
    local stuck = accents(state)
    equal(#stuck, 1, "one leaf on the lowest roll")
    local leafSplat, first = stuck[1], state.splats()[1]
    equal(leaf(leafSplat.texture) ~= nil, true, "a leaf")
    equal(bloody(first.texture) ~= nil, true, "on a blood splat")
    equal(sameColor(first.vertexColor, {0.62, 0.02, 0.02}), true, "red blood, no acid green")
    equal(sameColor(leafSplat.vertexColor, {0.5, 0.12, 0.06}) or sameColor(leafSplat.vertexColor, {0.42, 0.24, 0.08}),
        true, "blood-soaked: dark red-brown with a little green")
    local point, base = leafSplat.points[#leafSplat.points], first.points[#first.points]
    equal(point[4] == base[4] and point[5] == base[5], true, "stuck on top of the splat")
    equal(slideOf(state, leafSplat)[2], 0, "sticks")
    equal(leafSplat.blend, "BLEND")
    local smear = false
    for _, run in ipairs(state.runs()) do
        local at = run.points[#run.points]
        smear = smear or (at[2] == leafSplat and at[1] == "TOP" and run.vertexColor[1] == leafSplat.vertexColor[1])
    end
    equal(smear, true, "a smear runs down from the leaf")
    for _, splat in ipairs(state.splats()) do
        equal(splat.texture:find("Embers1", 1, true), nil, "no bubbling acid")
    end
end)
test("nature accents: Fel's leaf catches fire, then falls to ash; a clear cancels the ash", function()
    local state = fixture()
    state.mayhem("fel", "low")
    rolls(state, 0)
    state.spell(PLAYER, ENEMY, "Wrath", 100, true, "SPELL_DAMAGE", 8)
    local burning, flames = accents(state), accents(state, 3)
    equal(#burning, 1, "one leaf")
    equal(leaf(burning[1].texture) ~= nil, true, "a leaf")
    equal(sameColor(burning[1].vertexColor, {0.95, 0.3, 0.08}) or sameColor(burning[1].vertexColor, {0.35, 0.9, 0.15}),
        true, "hellfire or fel green")
    equal(#flames, 1, "one flame lick on it")
    equal(flames[1].texture:find("Flame1", 1, true) ~= nil, true, "a flame")
    equal(flames[1].blend, "ADD", "it glows")
    local at, on = burning[1].points[#burning[1].points], flames[1].points[#flames[1].points]
    equal(at[4] == on[4] and at[5] == on[5], true, "on the leaf")
    equal(#state.timers, 1, "the ash comes later")
    local delay = state.timers[1].at - state.now
    equal(delay > 0 and delay < state.dcm.Intensity().hold, true, "before the leaf fades")
    state.runTimers()
    local ash
    for _, splat in ipairs(accents(state, 3)) do
        if sameColor(splat.vertexColor, {0.45, 0.42, 0.4}) then ash = splat end
    end
    equal(ash ~= nil and ash.texture:find("Embers1", 1, true) ~= nil, true, "grey ash")
    equal(slideOf(state, ash)[2] < 0, true, "falls")
    local there = ash.points[#ash.points]
    equal(there[4] == at[4] and there[5] == at[5], true, "where the leaf burned")
    for _, splat in ipairs(state.splats()) do
        equal(splat.texture:find("Sparkle", 1, true), nil, "no sparkles")
    end
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Wrath", 100, true, "SPELL_DAMAGE", 8)
    state.dcm.ClearEffects()
    state.runTimers()
    equal(#state.splats(), 0, "no ash after a clear")
end)
test("nature accents keep the caps: splats and moving effects", function()
    for _, key in ipairs({"tame", "spellburst", "brutal", "fel"}) do
        local state = fixture({account = {adult = true}})
        state.mayhem(key, "max")
        rolls(state, 0)
        for _ = 1, 30 do
            state.now = state.now + 0.3
            state.spell(PLAYER, ENEMY, "Wrath", 100, true, "SPELL_DAMAGE", 8)
            state.runTimers()
        end
        equal(#state.splats() <= 32, true, key .. ": the pool")
        equal(state.moving() <= 12, true, key .. ": moving")
    end
end)
-- Naturalist (working name): 18+, a Druid's savage, darker nature theme.
local function naturalistTextures(state)
    local names = {}
    for _, splat in ipairs(state.splats()) do names[#names + 1] = splat.texture:match("(%w+)$") end
    return names
end
test("Naturalist is 18+ like Brutal and Fel: refused without the box, back to Tame when it is cleared", function()
    local state = fixture()
    local naturalist = state.dcm.FindTheme("naturalist")
    equal(naturalist.name, "Naturalist")
    equal(naturalist.mature, true)
    state.clear()
    equal(state.dcm.SetTheme("naturalist").key, "tame", "refused without the box")
    equal(state.last(), "DCM: Naturalist is for 18 and over: tick \"I'm 18 or over\" in /dcm options first.")
    state.dcm.SetAdult(true)
    equal(state.dcm.SetTheme("naturalist").key, "naturalist")
    state.dcm.SetAdult(false)
    equal(state.db().theme, "tame")
    equal(fixture({db = {theme = "naturalist"}}).db().theme, "tame", "saved without the box: Tame at login")
    equal(fixture({db = {theme = "naturalist"}, account = {adult = true}}).db().theme, "naturalist")
    equal(fixture().db().theme, "tame", "nobody starts on Naturalist")
end)
-- A Druid in a form: 768 Cat, 5487 Bear, 9634 Dire Bear, 24858 Moonkin.
local function shift(state, form)
    state.form = form
    state.emit("UPDATE_SHAPESHIFT_FORM")
end
test("Naturalist physical in Cat form: claws, bites, and splatter in blood red, mixed; some dripping", function()
    local state = fixture({class = "DRUID"})
    state.mayhem("naturalist", "low")
    shift(state, 768)
    rolls(state, 0)
    state.swing(PLAYER, ENEMY, 50, true)
    for _, splat in ipairs(state.splats()) do
        local name = splat.texture:match("(%w+)$")
        equal(name:find("^Claw") or name == "Bite1" or name:find("^Splat"), 1, "claws, a bite, or a splat: " .. name)
        equal(sameColor(splat.vertexColor, {0.6, 0.02, 0.02}) or sameColor(splat.vertexColor, {0.48, 0.02, 0.02}),
            true, "blood red")
    end
    equal(#state.runs() >= 1, true, "a mark drips on a low roll")
    local naturalist, brutal = state.dcm.FindTheme("naturalist"), state.dcm.FindTheme("brutal")
    for key, chance in pairs(naturalist.beast.runChance) do
        equal(chance > 0 and chance < 1, true, key .. ": at random")
        equal(chance >= brutal.runChance[key], true, key .. ": at least Brutal's")
    end
    state.dcm.ClearEffects()
    state.now = state.now + 1
    rolls(state, 0.99)
    state.swing(PLAYER, ENEMY, 50, true)
    equal(#state.runs(), 0, "none on a high roll")
end)
test("Naturalist physical: never uniform; marks turn and mirror at random, drips always run down", function()
    local state = fixture({class = "DRUID"})
    state.mayhem("naturalist", "max")
    shift(state, 5487)
    math.randomseed(7)
    state.dcm.random = function(low, high)
        if low and high then return math.random(low, high) end
        if low then return math.random(low) end
        return math.random()
    end
    local seen, turns, mirrors, sizes, runs = {}, {}, {}, {}, 0
    for _ = 1, 40 do
        state.now = state.now + 1
        state.swing(PLAYER, ENEMY, 50, true)
        for _, splat in ipairs(state.splats()) do
            local name = splat.texture:match("(%w+)$")
            seen[name] = true
            if name:find("^Claw") or name == "Bite1" then
                turns[string.format("%.3f", splat.rotation)] = true
                mirrors[splat.texCoord[1]] = true
                sizes[string.format("%.1f", splat.width)] = true
            elseif name:find("^Drip") then
                equal(splat.rotation, 0, "a drip hangs straight down")
            end
        end
        for _, run in ipairs(state.runs()) do
            runs = runs + 1
            equal(run.rotation, 0, "a run is never turned")
            equal(run.texCoord[1], 0, "nor mirrored")
            local point = run.points[#run.points]
            equal(point[1] == "TOP" and point[3] == "CENTER", true, "hangs from its mark's center")
            equal(point[5] <= 0, true, "below it")
            local grow = state.groupsOf(run)[1].animations[1]
            equal(grow.origin[1], "TOP", "grows down")
            equal(grow.scaleFrom[1] == 1 and grow.scaleFrom[2] < 0.1, true, "lengthens downward only")
        end
        state.dcm.ClearEffects()
    end
    equal(seen.Claw1 and seen.Claw2 and seen.Claw3 and seen.Bite1 and (seen.Splat1 or seen.Splat3), true,
        "scratches, bites, and splatter all appear")
    equal(seen.Claw1 and seen.Claw2 and seen.Claw3, true, "four, three, and two scratches")
    local count = 0
    for _ in pairs(turns) do count = count + 1 end
    equal(count > 20, true, "scratches and bites at any angle")
    equal(mirrors[0] and mirrors[1], true, "mirrored at random")
    count = 0
    for _ in pairs(sizes) do count = count + 1 end
    equal(count > 5, true, "sizes vary")
    equal(runs > 0, true, "some drip")
end)
-- Claws or bites among a few crits' effects.
local function clawed(state, crit)
    local found = false
    for _ = 1, 8 do
        state.now = state.now + 1
        crit()
        for _, splat in ipairs(state.splats()) do
            local name = splat.texture:match("(%w+)$")
            found = found or name:find("^Claw") ~= nil or name == "Bite1"
            if not found then
                equal(name:find("^Splat") or name:find("^Drip"), 1, "Brutal's splatter: " .. name)
            end
        end
        state.dcm.ClearEffects()
    end
    return found
end
local function randomly(state)
    math.randomseed(3)
    state.dcm.random = function(low, high)
        if low and high then return math.random(low, high) end
        if low then return math.random(low) end
        return math.random()
    end
end
test("Naturalist, box ticked: claws and bites only in Cat, Bear, or Dire Bear form; else splatter", function()
    local state = fixture({class = "DRUID", db = {clawsInForm = true}})
    state.mayhem("naturalist", "high")
    randomly(state)
    local function melee() state.swing(PLAYER, ENEMY, 50, true) end
    for _, form in ipairs({768, 5487, 9634}) do
        shift(state, form)
        equal(clawed(state, melee), true, form .. ": claws or bites")
    end
    for _, form in ipairs({false, 24858, 783}) do
        shift(state, form or nil)
        equal(clawed(state, melee), false, tostring(form) .. ": splatter only")
    end
    shift(state, nil)
    local first
    state.now = state.now + 1
    rolls(state, 0)
    melee()
    first = state.splats()[1]
    equal(sameColor(first.vertexColor, {0.62, 0.02, 0.02}), true, "Brutal's red")
    equal(#state.runs() >= 1, true, "with Brutal's runs")
    local warrior = fixture({class = "WARRIOR", db = {clawsInForm = true}})
    warrior.mayhem("naturalist", "high")
    randomly(warrior)
    equal(clawed(warrior, function() warrior.swing(PLAYER, ENEMY, 50, true) end), false, "a Warrior: splatter")
end)
test("Naturalist, box ticked: a Hunter's pet claws; a demon, others' crits, and crits on you splatter", function()
    local hunter = fixture({class = "HUNTER", db = {pet = true, clawsInForm = true}})
    hunter.mayhem("naturalist", "high")
    randomly(hunter)
    hunter.pet = PET
    hunter.emit("UNIT_PET", "player")
    equal(clawed(hunter, function() hunter.swing(PET, ENEMY, 50, true) end), true, "a Hunter's pet: claws")
    local warlock = fixture({class = "WARLOCK", db = {pet = true, clawsInForm = true}})
    warlock.mayhem("naturalist", "high")
    randomly(warlock)
    warlock.pet = PET
    warlock.emit("UNIT_PET", "player")
    equal(clawed(warlock, function() warlock.swing(PET, ENEMY, 50, true) end), false, "a demon: splatter")
    local druid = fixture({class = "DRUID", db = {taken = true, clawsInForm = true}})
    druid.mayhem("naturalist", "high")
    randomly(druid)
    shift(druid, 768)
    druid.target = ENEMY
    druid.emit("PLAYER_TARGET_CHANGED")
    equal(clawed(druid, function() druid.swing("Player-1-0042", ENEMY, 50, true) end), false, "others: splatter")
    equal(clawed(druid, function() druid.swing(ENEMY, PLAYER, 50, true) end), false, "on you: splatter")
end)
test("Naturalist, box clear (the default): claws, bites, and splatter mixed for every physical crit", function()
    local state = fixture({class = "WARRIOR", account = {adult = true}})
    equal(state.db().clawsInForm, false, "off by default")
    state.mayhem("naturalist", "high")
    randomly(state)
    equal(clawed(state, function() state.swing(PLAYER, ENEMY, 50, true) end), true, "a Warrior: claws too")
    local druid = fixture({class = "DRUID", db = {taken = true}})
    druid.mayhem("naturalist", "high")
    randomly(druid)
    shift(druid, 24858)
    equal(clawed(druid, function() druid.swing(PLAYER, ENEMY, 50, true) end), true, "Moonkin: claws too")
    equal(clawed(druid, function() druid.swing(ENEMY, PLAYER, 50, true) end), true, "on you: the mix too")
    equal(fixture({db = {clawsInForm = "yes"}}).db().clawsInForm, false, "repaired")
end)
test("the Claws only in Cat or Bear form row sits under the theme and is live only on Naturalist", function()
    local state = fixture({account = {adult = true}})
    local page = state.categories["Crit Mayhem"]
    local theme, row = page.rows[2], page.rows[4]
    equal(row.setting.name, "Claws only in Cat or Bear form")
    equal(row.parentInitializer, theme, "a child of the theme row")
    equal(row.predicate(), false, "greyed on Tame")
    theme.setting:SetValue("naturalist")
    equal(row.predicate(), true, "live on Naturalist")
    theme.setting:SetValue("brutal")
    equal(row.predicate(), false, "greyed on Brutal: it always checks")
    contains(row.tooltip, "Naturalist only")
    row.setting:SetValue(true)
    equal(state.db().clawsInForm, true)
end)
test("Brutal: claws and bites in Cat, Bear, or Dire Bear form, in its red and run chances", function()
    local state = fixture({class = "DRUID", account = {adult = true}})
    state.mayhem("brutal", "high")
    randomly(state)
    local function melee() state.swing(PLAYER, ENEMY, 50, true) end
    for _, form in ipairs({768, 5487, 9634}) do
        shift(state, form)
        equal(clawed(state, melee), true, form .. ": claws or bites")
    end
    local brutal = state.dcm.FindTheme("brutal")
    equal(brutal.beast.colors, brutal.colors, "Brutal's red")
    equal(brutal.beast.runChance, brutal.runChance, "Brutal's run chances")
    for _, form in ipairs({false, 24858, 783}) do
        shift(state, form or nil)
        equal(clawed(state, melee), false, tostring(form) .. ": splatter as ever")
    end
    local warrior = fixture({class = "WARRIOR", account = {adult = true}})
    warrior.mayhem("brutal", "high")
    randomly(warrior)
    equal(clawed(warrior, function() warrior.swing(PLAYER, ENEMY, 50, true) end), false, "a Warrior: splatter")
end)
test("Brutal: a Hunter's pet claws; a demon, others' crits, and crits on you splatter; spells unchanged", function()
    local hunter = fixture({class = "HUNTER", db = {pet = true}})
    hunter.mayhem("brutal", "high")
    randomly(hunter)
    hunter.pet = PET
    hunter.emit("UNIT_PET", "player")
    equal(clawed(hunter, function() hunter.swing(PET, ENEMY, 50, true) end), true, "a Hunter's pet: claws")
    local warlock = fixture({class = "WARLOCK", db = {pet = true}})
    warlock.mayhem("brutal", "high")
    randomly(warlock)
    warlock.pet = PET
    warlock.emit("UNIT_PET", "player")
    equal(clawed(warlock, function() warlock.swing(PET, ENEMY, 50, true) end), false, "a demon: splatter")
    local druid = fixture({class = "DRUID", db = {taken = true}})
    druid.mayhem("brutal", "high")
    randomly(druid)
    shift(druid, 768)
    druid.target = ENEMY
    druid.emit("PLAYER_TARGET_CHANGED")
    equal(clawed(druid, function() druid.swing("Player-1-0042", ENEMY, 50, true) end), false, "others: splatter")
    equal(clawed(druid, function() druid.swing(ENEMY, PLAYER, 50, true) end), false, "on you: splatter")
    local brutal = druid.dcm.FindTheme("brutal")
    for _, mask in ipairs({2, 4, 8, 16, 32, 64}) do
        local style = druid.dcm.CritStyle(brutal, mask, {kind = "mine"})
        equal(style, brutal.styles[druid.dcm.SchoolKind(mask)], mask .. ": its school look, unchanged")
    end
    equal(druid.dcm.CritStyle(druid.dcm.FindTheme("fel"), 1, {kind = "mine"}), brutal, "Fel's melee: Brutal's blood")
end)
test("Naturalist's form cache: updated on UPDATE_SHAPESHIFT_FORM, read once per change; secret is no form", function()
    local state = fixture({class = "DRUID"})
    equal(state.dcm.feralForm, false, "caster form at login")
    state.form = 768
    equal(state.dcm.feralForm, false, "not read per crit")
    state.emit("UPDATE_SHAPESHIFT_FORM")
    equal(state.dcm.feralForm, true, "Cat")
    shift(state, 24858)
    equal(state.dcm.feralForm, false, "Moonkin")
    state.formSecret = true
    shift(state, 768)
    equal(state.dcm.feralForm, false, "a secret form is no form")
end)
test("Naturalist nature: a murky green burst with insects and torn leaves poofing out", function()
    local state = fixture()
    state.mayhem("naturalist", "low")
    rolls(state, 0)
    state.spell(PLAYER, ENEMY, "Wrath", 100, true, "SPELL_DAMAGE", 8)
    local first = state.splats()[1]
    equal(first.texture:find("Burst", 1, true) ~= nil, true, "a burst")
    equal(first.blend, "BLEND", "murky: drawn, not added light")
    equal(first.vertexColor[2] < 0.5 and first.vertexColor[2] > first.vertexColor[1], true, "dark green")
    local debris = accents(state)
    equal(#debris, 4, "the fewest bits on the lowest roll")
    for _, splat in ipairs(debris) do
        equal((splat.texture:find("Insect1", 1, true) or leaf(splat.texture)) ~= nil, true, "an insect or a leaf")
        local offset = slideOf(state, splat)
        equal(offset[1] ~= 0, true, "poofs outward")
    end
    equal(#state.runs(), 0, "no runs")
    local style = state.dcm.CritStyle(state.dcm.FindTheme("naturalist"), 8)
    local insects = false
    for _, texture in ipairs(style.accent.textures) do insects = insects or texture:find("Insect1", 1, true) ~= nil end
    equal(insects, true, "insects among the debris")
    equal(style.accent.count[2], 6)
end)
test("Naturalist arcane: silver firework sprays that fade, at random spots", function()
    local state = fixture()
    state.mayhem("naturalist", "medium")
    rolls(state, 0)
    state.spell(PLAYER, ENEMY, "Arcane Missiles", 100, true, "SPELL_DAMAGE", 64)
    equal(#state.splats() >= 1, true)
    for _, splat in ipairs(state.splats()) do
        contains(splat.texture, "Firework1")
        equal(splat.blend, "ADD", "light")
        equal(sameColor(splat.vertexColor, {0.85, 0.88, 0.95}) or sameColor(splat.vertexColor, {0.72, 0.76, 0.85}),
            true, "silver")
        equal(looping(state, splat), false, "no twinkle")
    end
    equal(#state.runs(), 0, "no runs")
end)
test("Naturalist fire, frost, holy, shadow: graphic and darker", function()
    local state = fixture()
    state.mayhem("naturalist", "low")
    rolls(state, 0)
    -- Fire: a scorched splat with a charred leaf burning on it, then embers.
    state.spell(PLAYER, ENEMY, "Moonfire", 100, true, "SPELL_DAMAGE", 4)
    local scorch = state.splats()[1]
    equal(bloody(scorch.texture) ~= nil and scorch.vertexColor[1] < 0.35, true, "a scorched splat")
    equal(leaf(accents(state)[1].texture) ~= nil, true, "a charred leaf")
    contains(accents(state, 3)[1].texture, "Flame1")
    equal(#state.runs(), 0, "a scorch does not run")
    state.runTimers()
    local embers = false
    for _, splat in ipairs(accents(state, 3)) do embers = embers or splat.texture:find("Embers1", 1, true) ~= nil end
    equal(embers, true, "embers after")
    -- Frost: rimed leaves with a shard on frozen blood.
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Frostbolt", 100, true, "SPELL_DAMAGE", 16)
    equal(leaf(accents(state)[1].texture) ~= nil, true, "a frozen leaf")
    contains(accents(state, 3)[1].texture, "Shard1")
    -- Holy: a harsh searing flare and ring on a scorch.
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Smite", 100, true, "SPELL_DAMAGE", 2)
    local flare = accents(state)[1]
    contains(flare.texture, "Burst1")
    equal(flare.blend, "ADD")
    contains(accents(state, 3)[1].texture, "Ring1")
    equal(#state.runs(), 0, "no runs")
    -- Shadow: rotting black leaves on dark ichor, smearing.
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Shadow Word: Pain", 100, true, "SPELL_DAMAGE", 32)
    local rot = accents(state)[1]
    equal(leaf(rot.texture) ~= nil and rot.vertexColor[1] < 0.15, true, "a black leaf")
    equal(state.splats()[1].vertexColor[1] < 0.15, true, "dark ichor")
    equal(#state.runs() >= 1, true, "it smears")
    for _, name in ipairs(naturalistTextures(state)) do
        equal(name:find("Star") or name:find("Sparkle") or name:find("Butterfly") or name:find("Heart"), nil,
            "never whimsical: " .. name)
    end
end)
test("Naturalist's heals: sprouting vines and green and gold smoke, never flowers", function()
    local naturalist = fixture().dcm.FindTheme("naturalist")
    for _, texture in ipairs(naturalist.heal.splats) do
        local name = texture:match("(%w+)$")
        equal(name == "Vine1" or name == "Smoke1" or name == "Smoke2", true, name)
    end
    equal(naturalist.heal.motion, "float", "rising")
end)
test("Naturalist: a new record pulses Fel's vignette in deep green; Fel's stays black", function()
    local state = fixture()
    state.mayhem("naturalist", "low")
    state.spell(PLAYER, ENEMY, "Wrath", 100, true, "SPELL_DAMAGE", 8)
    equal(state.dcm.vignette, nil, "not for a plain crit")
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Wrath", 300, true, "SPELL_DAMAGE", 8)
    local vignette = state.dcm.vignette
    equal(vignette.shown, true)
    contains(vignette.texture, "Vignette2")
    equal(vignette.vertexColor[2] > vignette.vertexColor[1] and vignette.vertexColor[2] < 0.4, true, "deep green")
    state.mayhem("fel", "low")
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Shadow Bolt", 100, true, "SPELL_DAMAGE", 32)
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Shadow Bolt", 900, true, "SPELL_DAMAGE", 32)
    contains(vignette.texture, "Vignette1")
    equal(sameColor(vignette.vertexColor, {1, 1, 1}), true, "Fel's untinted")
end)
test("Naturalist keeps the caps at Total Mayhem, every school", function()
    for _, school in ipairs({1, 2, 4, 8, 16, 32, 64}) do
        local state = fixture({account = {adult = true}})
        state.mayhem("naturalist", "max")
        rolls(state, 0)
        for _ = 1, 30 do
            state.now = state.now + 0.3
            state.spell(PLAYER, ENEMY, "Claw", 100, true, "SPELL_DAMAGE", school)
            state.runTimers()
        end
        equal(#state.splats() <= 32, true, school .. ": the pool")
        equal(state.moving() <= 12, true, school .. ": moving")
    end
end)
test("Naturalist's sounds: Dyre's Cats, Bears, and Gore, in one table", function()
    local sounds = fixture().dcm.FindTheme("naturalist").sounds
    equal(table.concat(sounds.crit, ","), "angrycat,tigerroar,goreslice")
    equal(table.concat(sounds.big, ","), "bearroar,monsterbear,lionroar")
    equal(table.concat(sounds.extra, ","), "wetsplat")
end)
test("a school mask is one kind: magic before physical, fire, frost, shadow, arcane, nature, holy", function()
    local dcm = fixture().dcm
    local cases = {
        [1] = "physical", [2] = "holy", [4] = "fire", [8] = "nature", [16] = "frost", [32] = "shadow",
        [64] = "arcane", [20] = "fire", [36] = "fire", [48] = "frost", [96] = "shadow", [72] = "arcane",
        [10] = "nature", [3] = "holy", [65] = "arcane", [127] = "fire",
    }
    for mask, kind in pairs(cases) do equal(dcm.SchoolKind(mask), kind, "mask " .. mask) end
    equal(dcm.SchoolKind(0), nil)
    equal(dcm.SchoolKind(nil), nil)
    equal(dcm.SchoolKind(128), nil, "an unknown school")
    equal(dcm.SchoolKind("fire"), nil)
    local state = fixture()
    local school = secret()
    state.secrets[school] = true
    equal(state.dcm.SchoolKind(school), nil, "a secret school")
end)
test("every theme has a style for every kind, and an unknown school draws the theme's own look", function()
    local state = fixture({account = {adult = true}})
    for _, theme in ipairs(state.dcm.Themes()) do
        for _, kind in ipairs(KINDS) do
            local style = state.dcm.CritStyle(theme, ({physical = 1, holy = 2, fire = 4, nature = 8, frost = 16,
                shadow = 32, arcane = 64})[kind])
            equal(type(style) == "table" and #style.splats > 0 and #style.colors > 0, true, theme.key .. " " .. kind)
        end
        equal(state.dcm.CritStyle(theme, 0), theme, theme.key .. ": unknown school")
        equal(state.dcm.CritStyle(theme, nil), theme)
    end
end)
test("Tame never shows gore, whatever the school", function()
    local state = fixture({account = {adult = true}})
    local tame = state.dcm.FindTheme("tame")
    for kind, mask in pairs({physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64}) do
        equal(gore(state.dcm.CritStyle(tame, mask)), false, kind)
    end
    equal(gore(tame), false, "its own look")
    state.mayhem("tame", "max")
    rolls(state, 0)
    for _ = 1, 5 do
        state.now = state.now + 1
        state.swing(PLAYER, ENEMY, 50, true)
    end
    for _, splat in ipairs(state.splats()) do
        equal(splat.texture:find("Splat", 1, true) == nil and splat.texture:find("Drip", 1, true) == nil, true,
            splat.texture)
    end
    equal(#state.runs(), 0)
end)
test("Tame's mix has a rainbow, drawn in its own colors", function()
    local state = fixture()
    local tame = state.dcm.FindTheme("tame")
    local inMix = false
    for _, texture in ipairs(tame.splats) do inMix = inMix or texture:find("Rainbow1", 1, true) ~= nil end
    equal(inMix, true, "in the playful mix")
    equal(#tame.splats, 5, "one of five, a similar weight")
    state.mayhem("tame", "max")
    local rainbows = 0
    for _ = 1, 30 do
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Spell", 100, true, "SPELL_DAMAGE", 0)
    end
    for _, child in ipairs(state.dcm.overlay.children) do
        if child.texture and child.texture:find("Rainbow1", 1, true) and child.vertexColor then
            rainbows = rainbows + 1
            equal(sameColor(child.vertexColor, {1, 1, 1}), true, "untinted")
        elseif child.texture and child.vertexColor then
            equal(sameColor(child.vertexColor, {1, 1, 1}), false, "the others are tinted: " .. child.texture)
        end
    end
    equal(rainbows > 0, true, "rainbows show")
    local holy = state.dcm.CritStyle(tame, 2)
    local inHoly = false
    for _, texture in ipairs(holy.splats) do inHoly = inHoly or texture:find("Rainbow1", 1, true) ~= nil end
    equal(inHoly, true, "and in Tame's holy look")
end)
test("Random Effects: ticked, Tame ignores the school; clear (the default), a look per school", function()
    local state = fixture({account = {adult = true}})
    local tame = state.dcm.FindTheme("tame")
    equal(state.db().randomEffects, false, "off by default")
    equal(state.dcm.CritStyle(tame, 4) ~= tame, true, "clear: Tame's fire look")
    local row = state.row("Random Effects")
    row.setting:SetValue(true)
    equal(state.db().randomEffects, true)
    for _, mask in ipairs({1, 2, 4, 8, 16, 32, 64}) do
        equal(state.dcm.CritStyle(tame, mask), tame, "ticked: mask " .. mask)
    end
    state.mayhem("tame", "low")
    state.swing(PLAYER, ENEMY, 50, true)
    local texture = firstSplat(state).texture
    equal(texture:find("Pow1", 1, true), nil, "no pow: the playful mix")
    -- Other themes ignore it.
    local brutal = state.dcm.FindTheme("brutal")
    equal(state.dcm.CritStyle(brutal, 4) ~= brutal, true, "Brutal keeps its fire look")
    equal(state.dcm.CritStyle(state.dcm.FindTheme("spellburst"), 4) ~= state.dcm.FindTheme("spellburst"), true)
    equal(fixture({db = {randomEffects = "yes"}}).db().randomEffects, false, "repaired")
end)
test("the Random Effects row sits under the theme and is live only on Tame", function()
    local state = fixture({account = {adult = true}})
    local page = state.categories["Crit Mayhem"]
    local theme, row = page.rows[2], page.rows[3]
    equal(row.setting.name, "Random Effects", "right under the theme")
    equal(row.parentInitializer, theme, "a child of the theme row")
    equal(row.predicate(), true, "live on Tame")
    theme.setting:SetValue("brutal")
    equal(row.predicate(), false, "greyed on Brutal")
    theme.setting:SetValue("spellburst")
    equal(row.predicate(), false)
    theme.setting:SetValue("tame")
    equal(row.predicate(), true)
end)
test("Spellburst: a melee crit is blood only with the 18+ box, else a white flash", function()
    local state = fixture()
    state.mayhem("spellburst", "low")
    local spellburst = state.dcm.FindTheme("spellburst")
    equal(gore(state.dcm.CritStyle(spellburst, 1)), false, "no box: no gore")
    state.swing(PLAYER, ENEMY, 50, true)
    local flash = firstSplat(state)
    equal((flash.texture:find("Burst1", 1, true) or flash.texture:find("Ring1", 1, true)) ~= nil, true,
        "Spellburst's own language: " .. flash.texture)
    equal(sameColor(flash.vertexColor, {1, 1, 1}), true, "a white flash")
    equal(flash.texture:find("Pow1", 1, true), nil, "not Tame's pow")
    state.dcm.SetAdult(true)
    equal(gore(state.dcm.CritStyle(spellburst, 1)), true, "with the box: blood")
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.swing(PLAYER, ENEMY, 50, true)
    equal(bloody(firstSplat(state).texture) ~= nil, true, "a wizard's stick draws blood")
    state.dcm.SetAdult(false)
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.swing(PLAYER, ENEMY, 50, true)
    equal(bloody(firstSplat(state).texture), nil, "box cleared: no blood again")
end)
local MAGIC = {holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64}
test("each non-Tame theme keeps its own language for every magic school, with the school's tint", function()
    local state = fixture({account = {adult = true}})
    local brutal, fel, spellburst = state.dcm.FindTheme("brutal"), state.dcm.FindTheme("fel"),
        state.dcm.FindTheme("spellburst")
    local tints = {}
    for kind, mask in pairs(MAGIC) do
        local b = state.dcm.CritStyle(brutal, mask)
        equal(b.splats, brutal.splats, "Brutal " .. kind .. ": its blood")
        equal(b.drips, brutal.drips, "Brutal " .. kind .. ": its drips")
        equal(b.run, brutal.run, "Brutal " .. kind .. ": its runs")
        tints[#tints + 1] = b.colors[1][1] .. "," .. b.colors[1][2]
        local f = state.dcm.CritStyle(fel, mask)
        equal(f.splats, fel.splats, "Fel " .. kind .. ": its smoke")
        equal(f.run, fel.run, "Fel " .. kind .. ": its cracks")
        equal(f.drips, fel.drips, "Fel " .. kind .. ": its embers")
        local sb = state.dcm.CritStyle(spellburst, mask)
        local burst = false
        for _, texture in ipairs(sb.splats) do burst = burst or texture:find("Burst", 1, true) ~= nil end
        equal(burst, true, "Spellburst " .. kind .. ": its bursts")
        equal(sb.schoolColors, true, "Spellburst " .. kind .. ": tinted by school")
    end
    local distinct = {}
    for _, tint in ipairs(tints) do distinct[tint] = true end
    local count = 0
    for _ in pairs(distinct) do count = count + 1 end
    equal(count >= 5, true, "Brutal's schools are told apart by tint")
end)
test("school accents: Brutal's embers, shard, crackle, and flare; Fel's flame licks and rime", function()
    local state = fixture()
    local brutal, fel = state.dcm.FindTheme("brutal"), state.dcm.FindTheme("fel")
    local function accent(theme, mask)
        local style = state.dcm.CritStyle(theme, mask)
        return style.accent and style.accent.textures[1]:match("(%w+)$")
    end
    equal(accent(brutal, 4), "Embers1", "fire")
    equal(accent(brutal, 16), "Shard1", "frost")
    equal(accent(brutal, 64), "Crack1", "arcane")
    equal(accent(brutal, 2), "Burst1", "holy")
    equal(accent(fel, 4), "Flame1", "fel fire")
    equal(accent(fel, 16), "Shard1", "fel frost")
    state.mayhem("brutal", "low")
    rolls(state, 0)
    state.spell(PLAYER, ENEMY, "Fiery Weapon", 100, true, "SPELL_DAMAGE", 4)
    local blood, embers = 0, 0
    for _, splat in ipairs(state.splats()) do
        if splat.texture:find("Embers1", 1, true) then
            embers = embers + 1
            equal(splat.blend, "ADD", "embers glow")
            equal(sameColor(splat.vertexColor, {1, 0.5, 0.12}) or sameColor(splat.vertexColor, {1, 0.8, 0.3}), true,
                "fire-colored")
        elseif bloody(splat.texture) then
            blood = blood + 1
            equal(sameColor(splat.vertexColor, {0.32, 0.06, 0.02}) or sameColor(splat.vertexColor, {0.45, 0.09, 0.02}),
                true, "charred blood")
        else
            error("fire drew " .. splat.texture)
        end
    end
    equal(blood >= 1 and embers == 1, true, "the set of blood and one accent")
end)
test("physical is gore in Brutal, Fel, and Spellburst with the 18+ box; never in Tame", function()
    local state = fixture({account = {adult = true}})
    for _, key in ipairs({"brutal", "fel", "spellburst"}) do
        equal(gore(state.dcm.CritStyle(state.dcm.FindTheme(key), 1)), true, key)
    end
    equal(gore(state.dcm.CritStyle(state.dcm.FindTheme("tame"), 1)), false, "tame")
    state.mayhem("fel", "low")
    state.swing(PLAYER, ENEMY, 50, true)
    equal(bloody(firstSplat(state).texture) ~= nil, true, "Fel melee: blood")
end)
test("school styles: others' crits draw them too, and heals keep the heal style", function()
    local state = fixture({db = {heals = true}})
    state.mayhem("brutal", "low")
    state.target = ENEMY
    state.emit("PLAYER_TARGET_CHANGED")
    state.spell("Player-1-0042", ENEMY, "Fireball", 100, true, "SPELL_DAMAGE", 4)
    local fire = firstSplat(state)
    equal(bloody(fire.texture) ~= nil, true, "a groupmate's fire crit on your target: Brutal's wound")
    equal(sameColor(fire.vertexColor, {0.32, 0.06, 0.02}) or sameColor(fire.vertexColor, {0.45, 0.09, 0.02}), true,
        "charred")
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.logEvent("SPELL_HEAL", PLAYER, PLAYER, 0, "Holy Light", 2, 500, 0, 0, true)
    local texture = firstSplat(state).texture
    equal((texture:find("Embers1", 1, true) or texture:find("Mote1", 1, true)) ~= nil, true, "Brutal's heal style")
end)
test("each intensity stays noticeably longer: Low 2.5 s up to Total Mayhem 12 s", function()
    local dcm = fixture().dcm
    local seconds = {}
    for index, intensity in ipairs(dcm.INTENSITIES) do seconds[index] = dcm.StaySeconds(intensity, 100) end
    equal(seconds[1], 0, "Off")
    for index = 3, #seconds do
        equal(seconds[index] >= seconds[index - 1] * 1.5, true, dcm.INTENSITIES[index].key .. " stays longer")
    end
    equal(seconds[2], 2.5)
    equal(seconds[#seconds], 12)
end)
test("Stays on screen scales the hold and the fade, from 25% to 300%", function()
    local state = fixture()
    local slider = state.row("Stays on screen")
    equal(slider.setting.default, 100)
    equal(slider.options.minValue, 25)
    equal(slider.options.maxValue, 300)
    equal(slider.options.step, 25)
    equal(slider.options.formatter(100), "100%", "Off has no seconds")
    contains(slider.tooltip, "Low 2.5 s, Medium 4 s, High 7 s, Total Mayhem 12 s")
    state.mayhem("brutal", "high")
    equal(slider.options.formatter(100), "100% (7 s)")
    equal(slider.options.formatter(250), "250% (17.5 s)")
    slider.setting:SetValue(200)
    equal(state.db().stay, 200)
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    local splat = state.splats()[1]
    local fade
    for _, group in ipairs(state.groups) do
        if group.owner == splat then
            for _, animation in ipairs(group.animations) do
                if animation.kind == "Alpha" then fade = animation end
            end
        end
    end
    equal(fade.delay, state.dcm.Intensity().hold * 2)
    equal(fade.duration, state.dcm.Intensity().fade * 2)
    slider.setting:SetValue(1000)
    equal(state.db().stay, 300, "clamped")
    slider.setting:SetValue(60)
    equal(state.db().stay, 50, "on its steps")
end)
test("a damaged stay is repaired", function()
    equal(fixture({db = {stay = "long"}}).db().stay, 100)
    equal(fixture({db = {stay = 5}}).db().stay, 25)
end)
test("Brutal at Low: a crit plays one hit sound and one splatter; a plain hit plays nothing", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    state.spell(PLAYER, ENEMY, "Fireball", 300, false)
    equal(#state.sounds, 0)
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    equal(#state.sounds, 1)
    equal(state.sounds[1].channel, "SFX")
    local theme = state.dcm.Theme()
    local hit = false
    for _, key in ipairs(theme.sounds.crit) do hit = hit or key == state.sounds[1].key end
    equal(hit, true, "one of the theme's crit sounds")
    local splats = state.splats()
    equal(#splats, 1)
    contains(splats[1].texture, "Interface\\AddOns\\DyresCritMayhem\\Textures\\Splat")
    equal(splats[1].vertexColor[1], theme.colors[1][1], "tinted by the theme")
end)
test("higher intensities splatter more, bigger, and longer", function()
    local counts, sizes, holds = {}, {}, {}
    for index, key in ipairs({"low", "medium", "high"}) do
        local state = fixture()
        state.mayhem("brutal", key)
        state.spell(PLAYER, ENEMY, "Fireball", 300, true)
        local splats = state.splats()
        counts[index] = #splats
        holds[index] = state.dcm.Intensity().hold
        sizes[index] = state.dcm.Intensity().size
    end
    equal(counts[1] < counts[2] and counts[2] < counts[3], true, "count grows")
    equal(sizes[1] < sizes[2] and sizes[2] < sizes[3], true, "size grows")
    equal(holds[1] < holds[2] and holds[2] < holds[3], true, "stays longer")
    local levels = fixture().dcm.INTENSITIES
    equal(levels[5].splats > levels[4].splats and levels[5].hold > levels[4].hold, true, "Total Mayhem is the most")
end)
test("Brutal: from Medium the squelch joins; from High one splatter drips", function()
    local state = fixture()
    state.mayhem("brutal", "medium")
    rolls(state, 0)
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    equal((state.soundKeys():find("wetsplat", 1, true) or state.soundKeys():find("wetpunch", 1, true)) ~= nil, true,
        "the squelch: " .. state.soundKeys())
    state.now = state.now + 5
    state.mayhem("brutal", "high")
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    local drips = 0
    for _, splat in ipairs(state.splats()) do
        if splat.texture:find("Drip", 1, true) then drips = drips + 1 end
    end
    equal(drips, 1)
end)
test("splatters fade by animation and go back to the pool", function()
    local state = fixture()
    state.mayhem("brutal", "medium")
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    local splat = state.splats()[1]
    equal(#state.splats(), 2)
    local group
    for _, candidate in ipairs(state.groups) do
        if candidate.owner == splat then group = candidate end
    end
    equal(group.playing, true)
    local fade
    for _, animation in ipairs(group.animations) do
        if animation.kind == "Alpha" then fade = animation end
    end
    equal(fade.delay, state.dcm.Intensity().hold)
    equal(fade.duration, state.dcm.Intensity().fade)
    group:Finish()
    equal(splat.shown, false)
    equal(#state.splats(), 1)
end)
test("an area burst adds one splatter per extra crit, and the pool has a cap", function()
    local state = fixture()
    state.mayhem("brutal", "high")
    state.spell(PLAYER, ENEMY, "Blizzard", 100, true)
    local first = #state.splats()
    state.spell(PLAYER, ENEMY, "Blizzard", 100, true)
    equal(#state.splats(), first + 1)
    for _ = 1, 80 do
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Blizzard", 100, true)
    end
    equal(#state.splats() <= 32, true, "at most 32 on screen")
end)
test("your own crits avoid the middle; crits on you land at the edges", function()
    local state = fixture()
    state.db().taken = true
    state.mayhem("brutal", "high")
    for _ = 1, 10 do
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    end
    for _, splat in ipairs(state.splats()) do
        local point = splat.points[#splat.points]
        local x, y = point[4] / 1000, point[5] / 800
        equal(math.abs(x - 0.5) > 0.22 or math.abs(y - 0.5) > 0.22, true, "outside the middle")
    end
    state.dcm.ClearEffects()
    equal(#state.splats(), 0)
    for _ = 1, 10 do
        state.now = state.now + 1
        state.spell(ENEMY, PLAYER, "Shadow Bolt", 300, true)
    end
    for _, splat in ipairs(state.splats()) do
        local point = splat.points[#splat.points]
        local x, y = point[4] / 1000, point[5] / 800
        equal(x <= 0.14 or x >= 0.86 or y <= 0.14 or y >= 0.86, true, "at an edge")
    end
end)
test("the extra plays on about 30% of the crits that may have it", function()
    local state = fixture()
    state.mayhem("brutal", "medium")
    local function extra()
        local keys = state.soundKeys()
        return keys:find("wetsplat", 1, true) ~= nil or keys:find("wetpunch", 1, true) ~= nil
    end
    local function crit(amount)
        state.clear()
        state.dcm.ClearEffects()
        state.now = state.now + 1
        state.spell(PLAYER, ENEMY, "Fireball", amount or 100, true)
    end
    equal(state.dcm.EXTRA_CHANCE, 0.3)
    rolls(state, 0.29)
    crit()
    equal(extra(), true, "under the chance: plays")
    rolls(state, 0.3)
    crit()
    equal(extra(), false, "at the chance: not")
    rolls(state, 0.9)
    crit()
    equal(extra(), false, "over it: not")
    -- The other conditions still decide first.
    rolls(state, 0)
    state.mayhem("brutal", "low")
    crit()
    equal(extra(), false, "below the theme's intensity")
    state.mayhem("brutal", "medium")
    state.db().splatter = false
    crit()
    equal(extra(), false, "on-screen effects off")
    state.db().splatter = true
    crit(5000)
    equal(extra(), false, "not with a new record's sound")
    state.db().heals = true
    state.clear()
    state.now = state.now + 1
    state.heal(PLAYER, PLAYER, "Flash Heal", 300, true)
    equal(extra(), false, "not for a heal")
    crit(100)
    equal(extra(), true, "and then it plays again")
    -- A theme may set its own chance.
    state.dcm.FindTheme("brutal").sounds.extraChance = 0.5
    rolls(state, 0.4)
    crit()
    equal(extra(), true, "the theme's own chance")
    state.dcm.FindTheme("brutal").sounds.extraChance = nil
end)
test("the sounds and the blood each have a switch", function()
    local state = fixture()
    state.mayhem("brutal", "medium")
    state.db().sound = false
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    equal(#state.sounds, 0)
    equal(#state.splats() > 0, true)
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.db().sound, state.db().splatter = true, false
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    equal(#state.splats(), 0)
    equal(state.soundKeys():find("wet", 1, true), nil, "no squelch without blood")
end)
test("without Dyre's Sounds the effects play and it says so once", function()
    local state = fixture({noSounds = true})
    state.mayhem("brutal", "low")
    state.clear()
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    local count = 0
    for _, message in ipairs(state.messages) do
        if message:find("Dyre's Sounds", 1, true) then count = count + 1 end
    end
    equal(count, 1)
    equal(#state.splats(), 2)
end)
test("/dcm test plays a crit, and a big one every third time", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    state.slash("test")
    contains(state.last(), "Test crit: Brutal at Low.")
    state.now = state.now + 1
    state.slash("test")
    state.now = state.now + 1
    state.slash("test")
    contains(state.last(), "as a new record")
    equal(state.sounds[#state.sounds].key:find("^gore") ~= nil, true, "one of Brutal's big sounds")
end)

-- Crit detection -------------------------------------------------------------

test("the combat log reads swings, spells, ranged, and dots at their fields", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    state.swing(PLAYER, ENEMY, 150, true)
    equal(state.db().records.Melee.crit, 150)
    state.spell(PLAYER, ENEMY, "Auto Shot", 90, false, "RANGE_DAMAGE")
    equal(state.db().records["Auto Shot"].hit, 90)
    state.spell(PLAYER, ENEMY, "Corruption", 40, true, "SPELL_PERIODIC_DAMAGE")
    equal(state.db().records.Corruption.crit, 40)
    equal(#state.splats(), 2, "two crits")
end)
test("other players' crits and missed swings do nothing", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    state.spell("Player-1-0099", ENEMY, "Fireball", 300, true)
    state.logEvent("SWING_MISSED", PLAYER, ENEMY, "DODGE")
    equal(#state.sounds, 0)
    equal(next(state.db().records), nil)
end)
test("pet crits count with their switch and get their own records", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    state.pet = PET
    state.emit("UNIT_PET", "player")
    state.spell(PET, ENEMY, "Claw", 50, true)
    equal(#state.sounds, 0, "pet switch off")
    equal(state.db().records["pet:Claw"].crit, 50)
    equal(state.dcm.RecordLabel(state.db().records["pet:Claw"]), "Claw (pet)")
    state.db().pet = true
    state.now = state.now + 1
    state.spell(PET, ENEMY, "Claw", 40, true)
    equal(#state.sounds, 1)
end)
test("crits on you count with their switch; never a record", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    state.spell(ENEMY, PLAYER, "Shadow Bolt", 300, true)
    equal(#state.sounds, 0)
    state.db().taken = true
    state.spell(ENEMY, PLAYER, "Shadow Bolt", 300, true)
    equal(#state.sounds, 1)
    equal(next(state.db().records), nil)
end)
test("heals count only with Heals too: sounds and records, rising light and no blood", function()
    local state = fixture()
    state.mayhem("brutal", "medium")
    state.heal(PLAYER, PLAYER, "Flash Heal", 500, true)
    equal(#state.sounds, 0)
    equal(next(state.db().records), nil)
    state.db().heals = true
    state.heal(PLAYER, PLAYER, "Flash Heal", 500, true)
    equal(#state.sounds, 1, "a hit sound, no squelch")
    for _, splat in ipairs(state.splats()) do
        equal(splat.texture:find("Splat", 1, true), nil, "no blood")
    end
    equal(state.db().records["heal:Flash Heal"].crit, 500)
    equal(state.dcm.RecordLabel(state.db().records["heal:Flash Heal"]), "Flash Heal (heal)")
end)
test("secret amounts still play the effect but make no record", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    local amount = secret()
    state.secrets[amount] = true
    state.spell(PLAYER, ENEMY, "Fireball", amount, true)
    equal(#state.sounds, 1)
    equal(next(state.db().records), nil)
end)
test("the debug line names the detection path", function()
    local state = fixture()
    state.slash("debug")
    contains(state.last(),
        "detection=combatlog combatLogRestricted=false theme=tame intensity=off adult=false stay=100")
end)

-- WoW: Forever (the combat log refused) ---------------------------------------

test("where the combat log is restricted it is never registered; UNIT_COMBAT stands in", function()
    local state = fixture({restrictCombatLog = true})
    equal(state.dcm.available, true)
    equal(state.dcm.DetectionMode(), "unitcombat")
    state.mayhem("brutal", "low")
    state.db().taken = true
    state.emit("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 300, 1)
    equal(#state.sounds, 1, "a crit on you")
    state.now = state.now + 1
    state.emit("UNIT_COMBAT", "player", "WOUND", "CRUSHING", 300, 1)
    equal(#state.sounds, 2, "a crushing blow on you")
    state.now = state.now + 1
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 300, 1)
    equal(#state.sounds, 3, "your crit while solo")
    state.now = state.now + 1
    state.emit("UNIT_COMBAT", "nameplate7", "WOUND", "CRITICAL", 250, 4)
    equal(#state.sounds, 4, "a crit on a nameplate, solo")
    state.now = state.now + 1
    state.emit("UNIT_COMBAT", "target", "WOUND", "", 300, 1)
    state.emit("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
    state.emit("UNIT_COMBAT", "party1", "WOUND", "CRITICAL", 300, 1)
    equal(#state.sounds, 4, "not crits, or not on an enemy")
    local flag = secret()
    state.secrets[flag] = true
    state.emit("UNIT_COMBAT", "player", "WOUND", flag, 300, 1)
    state.emit("UNIT_COMBAT", "target", "WOUND", flag, 300, 1)
    equal(#state.sounds, 4, "a secret flag is not read")
end)
test("Forever: the same hit on the target and its nameplate counts once", function()
    local state = fixture({restrictCombatLog = true})
    state.mayhem("brutal", "low")
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 300, 1)
    state.emit("UNIT_COMBAT", "nameplate2", "WOUND", "CRITICAL", 300, 1)
    equal(#state.splats(), 1)
    state.now = state.now + 0.02
    state.emit("UNIT_COMBAT", "nameplate3", "WOUND", "CRITICAL", 280, 1)
    equal(#state.splats(), 2, "a different hit (an area spell) counts")
end)
test("Forever, solo: hits are matched to your casts for records", function()
    local state = fixture({restrictCombatLog = true})
    -- Sinister Strike: physical, lands with its cast.
    state.cast("player", 1752)
    state.emit("UNIT_COMBAT", "target", "WOUND", "", 120, 1)
    state.now = state.now + 0.1
    state.cast("player", 1752)
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 250, 1)
    local record = state.db().records["Sinister Strike"]
    equal(record.hit, 120)
    equal(record.crit, 250)
    -- A physical hit with no cast just before it is a melee swing.
    state.now = state.now + 2
    state.emit("UNIT_COMBAT", "target", "WOUND", "", 60, 1)
    equal(state.db().records.Melee.hit, 60)
    -- Fireball: a spell school, landing within a projectile's flight.
    state.cast("player", 133)
    state.now = state.now + 1.2
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 500, 4)
    equal(state.db().records.Fireball.crit, 500)
    -- Too long after any cast: no record.
    state.now = state.now + 3
    state.emit("UNIT_COMBAT", "target", "WOUND", "", 40, 32)
    equal(state.db().records.Fireball.hit, nil)
    -- A helpful cast is never matched.
    state.cast("player", 2061)
    state.emit("UNIT_COMBAT", "target", "WOUND", "", 70, 2)
    equal(state.db().records["Flash Heal"], nil)
    -- A secret amount plays nothing into the records.
    local amount = secret()
    state.secrets[amount] = true
    state.now = state.now + 1
    state.cast("player", 133)
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", amount, 4)
    equal(state.db().records.Fireball.crit, 500)
    state.slash("")
    contains(state.dcm.window.sorted.text, "Solo guesses from combat text.")
end)
test("Forever, solo with a pet: its casts are its own, and unmatched physical hits make no record", function()
    local state = fixture({restrictCombatLog = true})
    state.mayhem("brutal", "low")
    state.db().pet = true
    state.pet = PET
    state.emit("UNIT_PET", "player")
    state.emit("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
    equal(state.db().records.Melee, nil, "your swing or your pet's: unknown")
    state.cast("pet", 3716)
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 90, 4)
    equal(state.db().records["pet:Torment"].crit, 90)
    equal(#state.splats() >= 1, true, "the pet's crit plays with the pet switch")
end)
test("Forever, in a group: crits on your target and enemy nameplates play by the setting, never a record",
        function()
    local state = fixture({restrictCombatLog = true})
    state.mayhem("brutal", "low")
    state.group = true
    equal(state.db().othersScope, "nearby", "Nearby enemies by default")
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 300, 4)
    equal(#state.sounds, 1, "a crit on your target, whoever's")
    equal(#state.splats(), 1)
    state.now = state.now + 1
    state.emit("UNIT_COMBAT", "nameplate4", "WOUND", "CRITICAL", 320, 4)
    equal(#state.splats(), 2, "a crit on an enemy nameplate")
    state.now = state.now + 1
    state.friendly = {nameplate5 = true}
    state.emit("UNIT_COMBAT", "nameplate5", "WOUND", "CRITICAL", 320, 4)
    state.emit("UNIT_COMBAT", "focus", "WOUND", "CRITICAL", 330, 4)
    equal(#state.splats(), 2, "not a friendly nameplate, not focus")
    state.now = state.now + 1
    state.cast("player", 133)
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 900, 4)
    equal(next(state.db().records), nil, "never a record in a group, even after your cast")
    state.db().othersScope = "target"
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.emit("UNIT_COMBAT", "nameplate4", "WOUND", "CRITICAL", 340, 4)
    equal(#state.splats(), 0, "My target: not nameplates")
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 350, 4)
    equal(#state.splats(), 1, "My target: the target")
    state.db().othersScope = "off"
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 360, 4)
    equal(#state.splats(), 0, "Off: nothing in a group")
end)
test("Others' crits: Off, My target, Nearby enemies; Nearby by default; older saves repaired", function()
    local state = fixture()
    local row = state.row("Others' crits")
    local labels = {}
    for _, choice in ipairs(row.choices()) do labels[#labels + 1] = choice.value .. "=" .. choice.label end
    equal(table.concat(labels, ","), "off=Off,target=My target,nearby=Nearby enemies (nameplates)")
    equal(row.setting:GetValue(), "nearby")
    row.setting:SetValue("target")
    equal(state.db().othersScope, "target")
    row.setting:SetValue("bogus")
    equal(state.db().othersScope, "nearby")
    equal(fixture({restrictCombatLog = true}).row("Others' crits") ~= nil, true, "on Forever too")
    equal(fixture().row("Guess my crits in a group"), nil)
    local db = fixture({db = {groupGuess = true}}).db()
    equal(db.othersScope, "nearby")
    equal(db.groupGuess, nil)
    equal(fixture({db = {others = false}}).db().othersScope, "off", "a test build's switch, off")
    equal(fixture({db = {others = true}}).db().others, nil)
    equal(fixture({db = {othersScope = "target"}}).db().othersScope, "target", "a choice is kept")
end)
test("Era: groupmates' crits on your target and nearby enemies play by the setting, never a record", function()
    local state = fixture()
    state.mayhem("brutal", "low")
    local MATE, NEAR, FAR = "Player-1-0042", "Creature-0-0004", "Creature-0-0005"
    state.target = ENEMY
    state.emit("PLAYER_TARGET_CHANGED")
    state.plates = {nameplate1 = ENEMY, nameplate2 = NEAR}
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
    state.spell(MATE, ENEMY, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    equal(#state.splats(), 1, "a groupmate's crit on your target")
    equal(next(state.db().records), nil, "not your record")
    state.now = state.now + 1
    state.spell(MATE, NEAR, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    equal(#state.splats(), 2, "on a nearby enemy (its nameplate shown)")
    state.now = state.now + 1
    state.spell(MATE, FAR, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    state.spell(MATE, NEAR, "Mortal Strike", 900, false, "SPELL_DAMAGE", 1)
    state.logEvent("SPELL_HEAL", MATE, NEAR, 0, "Flash Heal", 2, 500, 0, 0, true)
    equal(#state.splats(), 2, "not a mob without a nameplate, a plain hit, or a heal crit")
    -- Its nameplate goes: it no longer counts.
    state.emit("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    state.now = state.now + 1
    state.spell(MATE, NEAR, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    equal(#state.splats(), 2, "nameplate gone")
    -- A friendly nameplate never counts.
    state.friendly = {nameplate3 = true}
    state.plates.nameplate3 = "Player-1-0043"
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate3")
    state.spell(MATE, "Player-1-0043", "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    equal(#state.splats(), 2, "a friendly nameplate")
    -- My target only.
    state.emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
    state.db().othersScope = "target"
    state.now = state.now + 1
    state.spell(MATE, NEAR, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    equal(#state.splats(), 2, "My target: not a nearby enemy")
    state.spell(MATE, ENEMY, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    equal(#state.splats(), 3, "My target: the target")
    -- Off.
    state.db().othersScope = "off"
    state.now = state.now + 1
    state.spell(MATE, ENEMY, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    equal(#state.splats(), 3, "Off: nothing")
    -- Your own crit is yours, with its record, whatever the setting.
    state.now = state.now + 1
    state.spell(PLAYER, FAR, "Fireball", 300, true)
    equal(state.db().records.Fireball.crit, 300)
    equal(#state.splats() > 3, true)
end)
test("others' crits are trimmed: a few per half second, one still effect each, and yours always play", function()
    local state = fixture()
    state.mayhem("brutal", "max")
    rolls(state, 0)
    local MATE = "Player-1-0042"
    state.target = ENEMY
    state.emit("PLAYER_TARGET_CHANGED")
    -- A raid pull: 30 crits on your target in the same instant.
    for _ = 1, 30 do
        state.spell(MATE, ENEMY, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    end
    equal(#state.splats(), 6, "Total Mayhem: at most 6 per half second, one effect each")
    equal(#state.runs(), 0, "no runs for others")
    equal(state.moving(), 0, "no loops for others")
    equal(#state.sounds, 1, "one sound in the gap")
    -- Your crit at the same moment still plays in full.
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    equal(#state.sounds > 1, true, "your sound is not held up by theirs")
    equal(#state.splats() >= 6 + 7, true, "your full set")
    -- Half a second later others may play again.
    state.now = state.now + 0.6
    state.spell(MATE, ENEMY, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    equal(#state.splats() >= 6 + 7 + 1, true)
    -- At Low only 2 per half second.
    state = fixture()
    state.mayhem("brutal", "low")
    state.target = ENEMY
    state.emit("PLAYER_TARGET_CHANGED")
    for _ = 1, 10 do
        state.spell(MATE, ENEMY, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1)
    end
    equal(#state.splats(), 2)
end)
test("others' crits leave the last 8 pool slots for yours", function()
    local state = fixture()
    state.mayhem("brutal", "max")
    rolls(state, 0)
    local MATE = "Player-1-0042"
    state.target = ENEMY
    state.emit("PLAYER_TARGET_CHANGED")
    for _ = 1, 40 do
        state.now = state.now + 0.6
        for _ = 1, 6 do state.spell(MATE, ENEMY, "Mortal Strike", 900, true, "SPELL_DAMAGE", 1) end
    end
    equal(#state.splats(), 24, "others stop at 32 - 8")
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    equal(#state.splats(), 31, "yours still get a full set")
end)
test("/dcm probe logs combat text, casts, and the damage meter, then stops", function()
    local state = fixture({restrictCombatLog = true, meter = true})
    state.clear()
    state.slash("probe")
    contains(state.messages[1], "probe: logging hits for 3 minutes")
    local lines = state.db().probe.lines
    contains(lines[1], "client 1.60.1 build 70450 interface 16001")
    contains(lines[2], "detection=unitcombat combatLogRestricted=true")
    contains(lines[3], "meter available=true")
    state.cast("player", 133)
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 500, 4)
    local amount = secret()
    state.secrets[amount] = true
    state.emit("UNIT_COMBAT", "nameplate1", "WOUND", "", amount, 1)
    local text = table.concat(lines, "\n")
    contains(text, "CAST player spell=133 Fireball harmful=true secret=-")
    contains(text, "UNIT_COMBAT target WOUND CRITICAL amount=500 school=4 secret=----- guess=Fireball")
    contains(text, "UNIT_COMBAT nameplate1 WOUND  amount=<secret> school=1 secret=---S-")
    state.emit("PLAYER_REGEN_ENABLED")
    text = table.concat(lines, "\n")
    contains(text, "combat ends")
    contains(text, "meter: 2 sources, maxAmount=900 total=1400")
    contains(text, "meter source 1: local=true")
    contains(text, "meter: my spells 1, maxAmount=900 total=900")
    contains(text, "meter spell: 133 Fireball total=900")
    state.slash("probe")
    contains(state.last(), "already running")
    state.now = state.now + 200
    state.runTimers()
    contains(state.last(), "probe: done")
    local count = #lines
    state.emit("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 500, 4)
    equal(#lines, count, "stopped")
end)
test("/dcm probe says when there is no damage meter, and keeps chat short", function()
    local state = fixture()
    state.slash("probe")
    contains(table.concat(state.db().probe.lines, "\n"), "meter: C_DamageMeter is not on this client")
    for index = 1, 60 do
        state.emit("UNIT_COMBAT", "target", "WOUND", "", index, 1)
    end
    local chat = 0
    for _, message in ipairs(state.messages) do
        if message:find("DCM: probe: UNIT_COMBAT", 1, true) then chat = chat + 1 end
    end
    equal(chat < 40, true, "at most 40 lines in chat")
    equal(#state.db().probe.lines > 60, true, "all of them saved")
end)

-- Records ----------------------------------------------------------------------

test("an ability's first hit and crit set its record quietly; a higher one says so", function()
    local state = fixture()
    state.clear()
    state.spell(PLAYER, ENEMY, "Sinister Strike", 200, false)
    state.spell(PLAYER, ENEMY, "Sinister Strike", 400, true)
    equal(#state.messages, 0, "quiet first records")
    state.spell(PLAYER, ENEMY, "Sinister Strike", 190, false)
    state.spell(PLAYER, ENEMY, "Sinister Strike", 400, true)
    equal(#state.messages, 0, "not higher")
    state.spell(PLAYER, ENEMY, "Sinister Strike", 1234, true)
    equal(state.last(), "DCM: New record! Sinister Strike crit 1,234 (was 400).")
    state.spell(PLAYER, ENEMY, "Sinister Strike", 250, false)
    equal(state.last(), "DCM: New record! Sinister Strike hit 250 (was 200).")
    local record = state.db().records["Sinister Strike"]
    equal(record.hit, 250)
    equal(record.crit, 1234)
    equal(#state.chat, 0, "nothing to party or guild by default")
end)
test("a new crit record plays the big sound and bigger splatters", function()
    local state = fixture()
    state.mayhem("brutal", "medium")
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    local normal = #state.splats()
    state.dcm.ClearEffects()
    state.now = state.now + 1
    state.clear()
    state.spell(PLAYER, ENEMY, "Fireball", 900, true)
    equal(state.sounds[1].key == "gorebloody" or state.sounds[1].key == "goresplat", true, "a big sound")
    equal(#state.splats(), normal + 1)
end)
test("records go to party and guild when asked, in a group or guild, at most every 10 seconds", function()
    local state = fixture()
    local db = state.db()
    db.announceParty, db.announceGuild = true, true
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    state.spell(PLAYER, ENEMY, "Fireball", 400, true)
    equal(#state.chat, 0, "not in a group or guild")
    state.group, state.guild = true, true
    state.now = state.now + 1
    state.spell(PLAYER, ENEMY, "Fireball", 500, true)
    equal(#state.chat, 2)
    equal(state.chat[1].channel, "PARTY")
    equal(state.chat[2].channel, "GUILD")
    equal(state.chat[1].message, "[Crit Mayhem] New personal record: Fireball crit 500!")
    state.now = state.now + 5
    state.spell(PLAYER, ENEMY, "Fireball", 600, true)
    equal(#state.chat, 2, "too soon")
    contains(state.last(), "Fireball crit 600", "your chat still says it")
    state.now = state.now + 10
    state.spell(PLAYER, ENEMY, "Fireball", 700, true)
    equal(#state.chat, 4)
end)
test("the on-screen pop is a toolkit widget and shows new records when asked", function()
    local state = fixture()
    local widgets = state.toolkit.Widgets("DyresCritMayhem")
    equal(#widgets, 1)
    equal(widgets[1], state.dcm.popWidget)
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    state.spell(PLAYER, ENEMY, "Fireball", 400, true)
    equal(state.dcm.pop.content.shown, false, "off by default")
    state.db().announceScreen = true
    state.spell(PLAYER, ENEMY, "Fireball", 500, true)
    equal(state.dcm.pop.content.shown, true)
    equal(state.dcm.pop.line.text, "Fireball crit 500")
    equal(state.dcm.pop.fader.playing, true)
    state.dcm.pop.fader:Finish()
    equal(state.dcm.pop.content.shown, false)
end)
test("unlocking shows a sample pop to drag; /dcm reset puts it back", function()
    local state = fixture()
    state.slash("unlock")
    equal(state.dcm.pop.content.shown, true)
    equal(state.dcm.pop.title.text, "New record!")
    state.slash("lock")
    equal(state.dcm.pop.content.shown, false)
    state.db().pop.position = {point = "CENTER", relativePoint = "BOTTOMLEFT", x = 10, y = 10}
    state.slash("reset")
    equal(state.db().pop.position, nil)
    contains(state.last(), "default place")
end)
test("the window lists records sorted by a heading, again for the other way", function()
    local state = fixture()
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    state.spell(PLAYER, ENEMY, "Arcane Missiles", 100, false)
    state.spell(PLAYER, ENEMY, "Arcane Missiles", 500, true)
    state.spell(PLAYER, ENEMY, "Frostbolt", 250, false)
    local function names()
        local list = {}
        for _, record in ipairs(state.dcm.SortedRecords()) do list[#list + 1] = record.name end
        return table.concat(list, ",")
    end
    equal(names(), "Arcane Missiles,Fireball,Frostbolt", "highest crit first by default")
    state.slash("")
    state.dcm.SortBy("crit")
    equal(names(), "Frostbolt,Fireball,Arcane Missiles", "low to high")
    state.dcm.SortBy("name")
    equal(names(), "Arcane Missiles,Fireball,Frostbolt")
    state.dcm.SortBy("name")
    equal(names(), "Frostbolt,Fireball,Arcane Missiles")
    state.dcm.SortBy("hit")
    equal(names(), "Frostbolt,Arcane Missiles,Fireball")
    contains(state.dcm.window.sorted.text, "Sorted by highest hit, high to low")
    equal(state.db().sortKey, "hit", "the sort is saved")
end)
test("the window shows each record's hit and crit, a dash for none", function()
    local state = fixture()
    state.spell(PLAYER, ENEMY, "Fireball", 1500, true)
    state.slash("")
    local row = state.dcm.window.list.children[1]
    equal(row.cells[1].text, "Fireball")
    equal(row.cells[2].text, "-")
    equal(row.cells[3].text, "1,500")
    equal(state.dcm.window.empty.shown, false)
end)
-- Where a cell's text ends, from its last point and width (left-anchored to its row).
local function cellRight(cell)
    local point = cell.points[#cell.points]
    return point[4] + cell.width
end
test("the window's columns use the whole width when every row fits, with no scroll bar", function()
    local state = fixture()
    for _, name in ipairs({"Claw", "Melee", "Rake", "Regrowth", "Rejuvenation", "Rip", "Wrath"}) do
        state.spell(PLAYER, ENEMY, name, 64, true)
    end
    state.slash("")
    local window = state.dcm.window
    equal(window.fits, true)
    equal(window.scroll.ScrollBar.shown, false, "no scroll bar for 7 rows")
    equal(window.listWidth, 460 - 2 * 16)
    local columns = window.columns
    equal(columns[1].width, 214, "Ability half")
    equal(columns[2].width, 107)
    equal(columns[3].width, 107)
    local row = window.list.children[1]
    equal(row.width, window.listWidth)
    equal(cellRight(row.cells[3]) <= window.listWidth - 6, true, "the crit ends inside the list")
    for column, heading in ipairs(window.headings) do
        local point = heading.points[#heading.points]
        equal(point[4], 16 + columns[column].x, "heading " .. column .. " over its column")
        equal(heading.width, columns[column].width)
    end
    equal(window.headerStrip.width, window.listWidth)
end)
test("with more rows than fit, the scroll bar shows and the columns end left of it", function()
    local state = fixture()
    for index = 1, 20 do
        state.spell(PLAYER, ENEMY, "Spell " .. index, 50 + index, true)
    end
    state.slash("")
    local window = state.dcm.window
    equal(window.fits, false)
    equal(window.scroll.ScrollBar.shown, true)
    equal(window.listWidth, 460 - 2 * 16 - 26)
    -- The bar starts 6 right of the scroll frame, which ends where the list does.
    local scrollRight = window.scroll.points[2]
    equal(scrollRight[1], "BOTTOMRIGHT")
    equal(460 + scrollRight[4], 16 + window.listWidth)
    local row = window.list.children[1]
    equal(cellRight(row.cells[3]) < window.listWidth, true)
    equal(16 + window.listWidth + 6 + 16 <= 460 - 4, true, "the bar stays inside the panel's edge")
    -- Clearing the records lays it out full width again.
    state.dcm.ResetRecords()
    equal(window.fits, true)
    equal(window.scroll.ScrollBar.shown, false)
end)
test("the window is a nearly opaque gold-edged panel", function()
    local state = fixture()
    state.slash("")
    local window = state.dcm.window
    contains(window.backdrop.bgFile, "UI-Tooltip-Background")
    equal(window.backdropColor[4] >= 0.9, true, "opaque enough to read")
    equal(window.backdropBorder[1], 1)
    equal(window.scroll.scrollBarHideable, true)
end)
test("an empty window says so", function()
    local state = fixture()
    state.slash("")
    equal(state.dcm.window.empty.text, "No records yet. Go hit something!")
end)
test("resetting records asks first and never in combat", function()
    local state = fixture()
    state.spell(PLAYER, ENEMY, "Fireball", 300, true)
    state.combat = true
    state.slash("resetrecords")
    contains(state.last(), "out of combat")
    equal(#state.popups, 0)
    state.combat = false
    state.slash("resetrecords")
    equal(state.popups[1], "DYRESCRITMAYHEM_RESET_RECORDS")
    equal(state.db().records.Fireball ~= nil, true, "not until accepted")
    state.env.StaticPopupDialogs.DYRESCRITMAYHEM_RESET_RECORDS.OnAccept()
    equal(next(state.db().records), nil)
    contains(state.last(), "cleared")
end)

local failures = 0
for _, entry in ipairs(tests) do
    local ok, message = pcall(entry.body)
    if ok then
        io.write("ok   ", entry.name, "\n")
    else
        failures = failures + 1
        io.write("FAIL ", entry.name, "\n     ", tostring(message), "\n")
    end
end
io.write(string.format("%d tests, %d failures\n", #tests, failures))
os.exit(failures == 0 and 0 or 1)
