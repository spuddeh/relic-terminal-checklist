-- ======================================================================================
-- Module: Checklist Shared Utils
-- Author: Spuddeh
-- Description: Shared utility functions and constants for the Checklist mods.
-- Module Version: 2.0.2
-- ======================================================================================

local Utils = {}

-- Standard Logging Prefix — set by each mod's init.lua via Utils.LogPrefix = "..."
Utils.LogPrefix = ""

-- Log Levels
Utils.LogLevel = {
    Info  = "INFO",
    Warn  = "WARN",
    Error = "ERROR",
    Debug = "DEBUG"
}

-- Internal debug flag — set via Utils.SetDebugMode(bool)
local _debugMode = false

--- Enable or disable debug-level logging.
--- Call this after loading config: Utils.SetDebugMode(settings.dev_mode_enabled)
function Utils.SetDebugMode(enabled)
    _debugMode = enabled == true
end

--- Logger with two modes:
---   Debug mode OFF: Debug → nothing; Info/Warn/Error → console only (no disk writes)
---   Debug mode ON:  all levels → console + log file
--- @param msg string
--- @param level string|nil  Default: Info
function Utils.Log(msg, level)
    level = level or Utils.LogLevel.Info

    if not _debugMode then
        if level == Utils.LogLevel.Debug then return end
        -- Info/Warn/Error go to console only — no disk I/O
        print(string.format("%s[%s] %s", (Utils.LogPrefix or ""), level, tostring(msg)))
        return
    end

    -- Debug mode: all levels go to console AND log file
    local fullMsg = string.format("%s[%s] %s", (Utils.LogPrefix or ""), level, tostring(msg))
    print(fullMsg)
    if spdlog then
        if level == Utils.LogLevel.Error then
            spdlog.error(fullMsg)
        else
            spdlog.info(fullMsg)
        end
    end
end

--- Dumps a table to the log (Recursive)
--- @param o any
--- @param depth int|nil
function Utils.Dump(o, depth)
    depth = depth or 1
    if depth > 2 then return end -- Limit recursion

    if type(o) == 'userdata' then
        Utils.Log(tostring(o) .. " (Userdata)", Utils.LogLevel.Debug)
        return
    end

    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. tostring(v) .. ','
        end
        s = s .. ' } '
        Utils.Log(s, Utils.LogLevel.Debug)
    else
        Utils.Log(tostring(o), Utils.LogLevel.Debug)
    end
end

-- Helper for red/error logging to Spdlog
function Utils.LogSpdlogError(text)
    spdlog.error(Utils.LogPrefix .. text)
end

--- Displays an on-screen notification
---@param text string
function Utils.Notify(text)
    if not text or text == "" then return end

    local message = SimpleScreenMessage.new()
    message.message = text
    message.isShown = true
    message.duration = 5.0
    message.isInstant = true

    local blackboardDefs = Game.GetAllBlackboardDefs()
    local blackboardUI = Game.GetBlackboardSystem():Get(blackboardDefs.UI_Notifications)

    blackboardUI:SetVariant(
        blackboardDefs.UI_Notifications.OnscreenMessage,
        ToVariant(message),
        true
    )
end

--- Displays an on-screen warning notification
---@param text string
---@param duration number? Default 5.0
function Utils.NotifyWarning(text, duration)
    if not text or text == "" then return end

    local message = SimpleScreenMessage.new()
    message.message = text
    message.isShown = true
    message.duration = duration or 5.0
    message.isInstant = true

    local blackboardDefs = Game.GetAllBlackboardDefs()
    local blackboardUI = Game.GetBlackboardSystem():Get(blackboardDefs.UI_Notifications)

    blackboardUI:SetVariant(
        blackboardDefs.UI_Notifications.WarningMessage,
        ToVariant(message),
        true
    )
end

return Utils
