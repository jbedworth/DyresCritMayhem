local _, DCM = ...

local USAGE = "Use /dcm (your records; the options on WoW: Forever), /dcm options, /dcm test [fire, frost, arcane, shadow, nature, holy, physical, or heal], /dcm unlock, /dcm lock, /dcm reset, "
    .. "/dcm resetrecords, /dcm debug, or /dcm probe."
local UNAVAILABLE = "Dyre's Crit Mayhem is unavailable. Check the DCM login message."

-- Each command is one word; "" opens the records window, or the settings
-- while the client hides damage amounts (author: "On Forever, we should make
-- typing '/dcm' bypass the highest crit screen we leave blank, and go right
-- to the settings"). Handlers live in the other files. Diagnostics also run
-- when DCM is unavailable.
local COMMANDS = {
    [""] = {handler = "OpenMain"},
    records = {handler = "ToggleWindow"},
    options = {handler = "OpenSettings"},
    -- "test fire" (author: "dcm test <type> ... when blank, have it continue
    -- to rotate"): the one command with a word after it.
    test = {handler = "TestCrit", argument = true},
    unlock = {handler = "Unlock"},
    lock = {handler = "Lock"},
    reset = {handler = "ResetPosition"},
    resetrecords = {handler = "ConfirmResetRecords"},
    debug = {handler = "ReportDebug", always = true},
    probe = {handler = "StartProbe", always = true},
}

function DCM.ParseCommand(message)
    if type(message) ~= "string" then
        return nil, USAGE
    end
    local command = message:match("^%s*(.-)%s*$"):lower()
    local word, argument = command:match("^(%S+)%s+(%S+)$")
    if word and COMMANDS[word] and COMMANDS[word].argument then
        return word, argument
    end
    if command:find("%s") or not COMMANDS[command] then
        return nil, USAGE
    end
    return command
end

function DCM.OpenMain()
    if DCM.AmountsHidden() then
        DCM.OpenSettings()
    else
        DCM.ToggleWindow()
    end
end

function DCM.HandleCommand(message)
    local command, argument = DCM.ParseCommand(message)
    local usage = argument
    if not command then
        DCM.Report(usage)
        return
    end
    local entry = COMMANDS[command]
    if not DCM.available and not entry.always then
        DCM.Report(UNAVAILABLE)
        return
    end
    if entry.argument then
        DCM[entry.handler](argument)
    else
        DCM[entry.handler]()
    end
end
