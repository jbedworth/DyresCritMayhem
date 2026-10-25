local _, DCM = ...

local USAGE = "Use /dcm (your records), /dcm options, /dcm test, /dcm unlock, /dcm lock, /dcm reset, "
    .. "/dcm resetrecords, /dcm debug, or /dcm probe."
local UNAVAILABLE = "Dyre's Crit Mayhem is unavailable. Check the DCM login message."

-- Each command is one word; "" opens the records window. Handlers live in
-- the other files. Diagnostics also run when DCM is unavailable.
local COMMANDS = {
    [""] = {handler = "ToggleWindow"},
    records = {handler = "ToggleWindow"},
    options = {handler = "OpenSettings"},
    test = {handler = "TestCrit"},
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
    if command:find("%s") or not COMMANDS[command] then
        return nil, USAGE
    end
    return command
end

function DCM.HandleCommand(message)
    local command, usage = DCM.ParseCommand(message)
    if not command then
        DCM.Report(usage)
        return
    end
    local entry = COMMANDS[command]
    if not DCM.available and not entry.always then
        DCM.Report(UNAVAILABLE)
        return
    end
    DCM[entry.handler]()
end
