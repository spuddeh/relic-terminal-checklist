-- ======================================================================================
-- Mod Name: Relic Terminal Checklist
-- Author: Spuddeh
-- Description: Shared utility functions and constants for Relic Terminal Checklist
-- Mod Version: 2.0.1
-- ======================================================================================

local Utils = {}

-- Standard Logging Prefix
Utils.LogPrefix = IconGlyphs.DataMatrixScan .. " [Relic Terminal Checklist] "

-- Log Levels
Utils.LogLevel = {
    Info = "INFO",
    Warn = "WARN",
    Error = "ERROR",
    Debug = "DEBUG"
}

--- Safe Logger Helper (Console + File)
--- @param msg string
--- @param level string|nil (Optional) Default: Info
function Utils.Log(msg, level)
    level = level or Utils.LogLevel.Info

    -- Format: [Mod Name] [LEVEL] Message
    local fullMsg = string.format("%s[%s] %s", (Utils.LogPrefix or ""), level, tostring(msg))

    -- 1. Console Output (All levels)
    print(fullMsg)

    -- 2. File Output (Error & Debug Only)
    if spdlog then
        if level == Utils.LogLevel.Error and spdlog.error then
            spdlog.error(fullMsg)
        elseif level == Utils.LogLevel.Debug and spdlog.info then
            -- spdlog.debug might not be exposed, using info
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
