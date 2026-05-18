-- ======================================================================================
-- Mod Name: Relic Terminal Checklist
-- Author: Spuddeh
-- Description: Tracks all 9 Relic Data Terminals via 0-Engine and TryGrantPerk observer.
-- Mod Version: 2.1.0
-- ======================================================================================

local RelicTerminalsDB = require("db")
local GameSession      = require("Modules/GameSession")
local GameUI           = require("Modules/GameUI")
local ChecklistUI      = require("Modules/ChecklistUI")
local SettingsUI       = require("Modules/SettingsUI")
local Utils            = require("Modules/Utils")
Utils.LogPrefix = IconGlyphs.DataMatrixScan .. " [Relic Terminal Checklist] "
local Automation       = require("Modules/Automation")

-- ### MOD STATE ###

local sessionState = {
    progress = {}
}

local settings = {
    lazy_mode        = false,
    dev_mode_enabled = false,
}

local isOverlayOpen   = false
local isSessionActive = false
local runtimeState    = { current_mappin = nil }
local config_file     = "config.json"

-- ### CONFIG IO ###

local function SaveConfig()
    local file = io.open(config_file, "w")
    if file then
        file:write(json.encode(settings))
        file:close()
    end
end

local function LoadConfig()
    local file = io.open(config_file, "r")
    if file then
        local content = file:read("*a")
        file:close()
        if content then
            local loaded = json.decode(content)
            for k, v in pairs(loaded) do
                settings[k] = v
            end
        end
    end
    if settings.automation_enabled == nil then settings.automation_enabled = true end
    if not settings.scanner_radius then settings.scanner_radius = 50.0 end
end

-- ### DEBUG HELPERS (fact observer) ###

local isFactLogging = false
local factObserverInstalled = false

local function SetupFactObserver()
    if factObserverInstalled then return end
    factObserverInstalled = true
    Observe("QuestsSystem", "SetFactStr", function(_, factName, factVal)
        if isFactLogging then
            Utils.Log("[Fact Changed] " .. factName .. ": " .. tostring(factVal), Utils.LogLevel.Debug)
        end
    end)
end

local function ToggleFactDebug()
    isFactLogging = not isFactLogging
    Utils.Log("Fact Debugging " .. (isFactLogging and "ENABLED" or "DISABLED"), Utils.LogLevel.Debug)
end

-- ### CALLBACKS ###

local uiCallbacks = {
    onToggle = function(id, value)
        Automation.SetItemStatus(id, value)
    end,

    onAction = function(action, entry)
        local player = GetPlayer()
        if not player then return end

        if action == "teleport" then
            if entry.coords then
                local pos = ToVector4 { x = entry.coords.x, y = entry.coords.y, z = entry.coords.z, w = 1 }
                local rot = ToEulerAngles { roll = 0, pitch = 0, yaw = entry.coords.yaw or 0 }
                Game.GetTeleportationFacility():Teleport(player, pos, rot)
                Utils.Log("Teleported to: " .. entry.name, Utils.LogLevel.Debug)
            end
        elseif action == "mappin" then
            -- Standalone manual waypoint, fully owned here. Independent of Core's
            -- proximity automation: behaves exactly like a user-placed map waypoint,
            -- just at the entry's exact coords. Single-pin slot.
            if runtimeState.current_mappin then
                Game.GetMappinSystem():UnregisterMappin(runtimeState.current_mappin)
                runtimeState.current_mappin = nil
            end
            if entry.coords then
                local mappinData = MappinData.new()
                mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
                mappinData.variant = gamedataMappinVariant.CustomPositionVariant
                mappinData.visibleThroughWalls = true
                local pin_pos = Vector4.new(entry.coords.x, entry.coords.y, entry.coords.z, 1.0)
                runtimeState.current_mappin = Game.GetMappinSystem():RegisterMappin(mappinData, pin_pos)
                Utils.Log("Map pin set for: " .. entry.name)
            end
        end
    end,

    drawSettings = function()
        SettingsUI.Draw(settings, runtimeState, {
            onSettingChanged = function()
                Automation.UpdateState()
                SaveConfig()
            end,
            onClearAllPins = function()
                if runtimeState.current_mappin then
                    Game.GetMappinSystem():UnregisterMappin(runtimeState.current_mappin)
                    runtimeState.current_mappin = nil
                    Utils.Log("Last map pin cleared.")
                else
                    Utils.Log("No map pin to clear.")
                end
            end,
            drawCustomSettings = function()
                if settings.dev_mode_enabled then
                    ImGui.Spacing()
                    ImGui.TextDisabled("Dev Tools")

                    if ImGui.Button(IconGlyphs.Bug .. " Analyze Target (Log)") then
                        Automation.DebugTarget()
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Logs details about the object under your crosshair to the console.")
                    end

                    ImGui.Spacing()
                    local new_fact_logging = ImGui.Checkbox("Log Fact Changes (Spammy!)", isFactLogging)
                    if new_fact_logging ~= isFactLogging then
                        ToggleFactDebug()
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Prints quest facts as they change. Useful for identifying activation triggers.")
                    end
                end
            end
        })
    end
}

-- ### EVENTS ###

registerForEvent("onInit", function()
    local Engine = GetMod("0-Engine")
    if not Engine then
        spdlog.error("[RTC] FATAL: 0-Engine not found. Install from Nexus (ID 27967).")
        return
    end
    local Mod = Engine.Register("relic_terminal_checklist")

    LoadConfig()
    Utils.SetDebugMode(settings.dev_mode_enabled)

    GameSession.StoreInDir('sessions')
    GameSession.Persist(sessionState)

    GameSession.OnLoad(function()
        local cleanProgress = {}
        for _, cat in ipairs(RelicTerminalsDB) do
            for _, entry in ipairs(cat.entries) do
                cleanProgress[entry.id] = false
            end
        end
        if not sessionState.progress then sessionState.progress = {} end
        for id, _ in pairs(cleanProgress) do
            if sessionState.progress[id] == nil then
                sessionState.progress[id] = false
            end
        end
    end)

    GameSession.OnSave(function()
        SaveConfig()
    end)

    -- Fact observer (dev tool) — always installed, gated by isFactLogging flag.
    SetupFactObserver()

    -- 0-Engine: combat and cutscene suppression.
    Engine.Subscribe("CombatStateChanged", function(inCombat)
        Automation.SetInCombat(inCombat)
    end)
    Engine.Subscribe("SceneTierChanged", function(tier)
        Automation.SetInCutscene(tier > 1)
    end)

    -- GameUI: loading screens and menus (faster than GameSession for cross-zone).
    GameUI.OnLoadingStart(function() Automation.SetMenuPaused(true) end)
    GameUI.OnLoadingFinish(function() Automation.SetMenuPaused(false) end)
    GameUI.OnMenuOpen(function() Automation.SetMenuPaused(true) end)
    GameUI.OnMenuClose(function() Automation.SetMenuPaused(false) end)

    -- Observer — installed once: TryGrantPerk for instant session-time auto-collect.
    -- (Proximity detection is handled by Core's onZoneTick → game's native relic mappin.)
    Automation.SetupObservers()

    -- NO PlayerInvalidated teardown — deliberate. 0-Engine's SpatialHash.Reset()/
    -- Proximity.Reset() (called on PlayerInvalidated) only clear active state; they do
    -- NOT unregister our SpatialSet/zones. Calling UnregisterItemSet() here would
    -- destroy registrations that otherwise persist, turning a transient false-
    -- invalidation (0-Engine 1.18.2 fires PlayerInvalidated on saves) into a permanent
    -- "broken until reload". By doing nothing, the registrations survive and 0-Engine
    -- auto-resumes polling them once its Lifecycle recovers. isSessionActive stays
    -- gated by GameSession.OnEnd (true session end only).

    GameSession.OnEnd(function()
        Utils.Log("Game Session Ended.")
        isSessionActive = false
    end)

    Mod.WhenReady(function(_)
        Utils.Log("Player Ready. Initializing Automation.")
        isSessionActive = true

        Automation.Init(sessionState, uiCallbacks, settings.dev_mode_enabled, settings)
        Automation.UpdateState()
        if not GameSession.IsPaused() then
            Automation.Scan()
        end
    end, nil, 2)

    Utils.Log("Loaded (Wait for Player Ready).")
end)

registerForEvent("onOverlayOpen", function()
    isOverlayOpen = true
    if isSessionActive then
        Automation.Scan()
    end
end)

registerForEvent("onOverlayClose", function()
    isOverlayOpen = false
end)

registerForEvent("onDraw", function()
    if isOverlayOpen then
        if isSessionActive then
            ChecklistUI.Draw("Relic Terminal Checklist", true, RelicTerminalsDB, sessionState.progress,
                settings, uiCallbacks, "automatic")
        else
            ChecklistUI.DrawSplashScreen("Relic Terminal Checklist")
        end
    end
end)

-- ### CONSOLE COMMANDS ###

local function ToggleDebug()
    settings.dev_mode_enabled = not settings.dev_mode_enabled
    Utils.SetDebugMode(settings.dev_mode_enabled)
    Automation.Init(sessionState, uiCallbacks, settings.dev_mode_enabled, settings)
    Utils.Log("Debug Mode " .. (settings.dev_mode_enabled and "ENABLED" or "DISABLED") .. ".")
    SaveConfig()
end

return {
    ToggleDebug     = ToggleDebug,
    ToggleFactDebug = ToggleFactDebug,
    DebugTarget     = Automation.DebugTarget,
}
