-- ======================================================================================
-- Mod Name: Relic Terminal Checklist
-- Author: Spuddeh
-- Description: Main entry point and initialization logic.
-- Mod Version: 2.0.1
-- ======================================================================================

local GameSession = require("Modules/GameSession")
local ChecklistUI = require("Modules/ChecklistUI")
local SettingsUI = require("Modules/SettingsUI")
local Automation = require("Modules/Automation")
local Utils = require("Modules/Utils")
local RelicTerminalsDB = require("db")
local Cron = require("Modules/Cron")

-- ### MOD STATE ###

-- Persistent State Container (Session Progress)
local sessionState = {
  progress = {}
}

-- Global Settings (Config.json)
local settings = {
  lazy_mode = false
}

-- Init Utils
local isOverlayOpen = false
local isSessionActive = false
-- Runtime State (Non-persistent)
local runtimeState = {
  current_mappin = nil
}
local config_file = "config.json"

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
  -- Dev mode state is managed by saved config or manual toggle
  -- settings.dev_mode_enabled = false
end

-- ### HELPERS ###

local function InitializeProgress()
  -- Utils.Log("Initializing new progress table...")
  local new_progress = {}
  for _, cat in ipairs(RelicTerminalsDB) do
    for _, entry in ipairs(cat.entries) do
      new_progress[entry.id] = false
    end
  end
  return new_progress
end

-- ### DEBUG HELPERS ###
local isFactLogging = false
local factObserver = nil

local function SetupFactObserver()
  if factObserver then return end -- Already registered

  factObserver = Observe("QuestsSystem", "SetFactStr", function(this, factName, factVal)
    if isFactLogging then
      Utils.Log("[Fact Changed] " .. factName .. ": " .. tostring(factVal), Utils.LogLevel.Debug)
    end
  end)
  Utils.Log("Fact Observer Initialized.", Utils.LogLevel.Debug)
end

local function ToggleFactDebug()
  isFactLogging = not isFactLogging
  local state = isFactLogging and "ENABLED" or "DISABLED"
  Utils.Log("Fact Debugging " .. state, Utils.LogLevel.Debug)
end



-- ### CALLBACKS ###

local uiCallbacks = {
  onToggle = function(id, value)
    if Automation.SetItemStatus then
      Automation.SetItemStatus(id, value)
    else
      sessionState.progress[id] = value
    end
  end,

  onAction = function(action, entry)
    local player = GetPlayer()
    if not player then return end

    if action == "teleport" then
      if entry.coords then
        local pos = ToVector4 { x = entry.coords.x, y = entry.coords.y, z = entry.coords.z, w = 1 }
        local rot = ToEulerAngles { roll = 0, pitch = 0, yaw = entry.coords.yaw or 0 }
        Game.GetTeleportationFacility():Teleport(player, pos, rot)
        Utils.Log("Teleported to: " .. entry.name, Utils.LogLevel.Info)
      end
    elseif action == "mappin" then
      if runtimeState.current_mappin then
        Game.GetMappinSystem():UnregisterMappin(runtimeState.current_mappin)
        runtimeState.current_mappin = nil
      end
      if entry.coords then
        local mappinData = MappinData.new()
        mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
        mappinData.variant = gamedataMappinVariant.CustomPositionVariant
        mappinData.visibleThroughWalls = true
        local pin_pos = Vector4.new(entry.coords.x, entry.coords.y, entry.coords.z, 0)
        runtimeState.current_mappin = Game.GetMappinSystem():RegisterMappin(mappinData, pin_pos)
        Utils.Log("Map pin set for: " .. entry.name, Utils.LogLevel.Info)
      end
    end
  end,

  drawSettings = function()
    -- Delegate to SettingsUI with Runtime State
    SettingsUI.Draw(settings, runtimeState, {
      onSettingChanged = function()
        Automation.UpdateState()
        SaveConfig()
      end,
      drawCustomSettings = function()
        if settings.dev_mode_enabled then
          ImGui.Spacing()
          ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "Developer Tools")
          if ImGui.Button(IconGlyphs.Bug .. " Analyze Target (Log)") then
            Automation.DebugTarget()
          end
          if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Logs details about the object under your crosshair to the console.")
          end

          ImGui.Spacing()

          -- Fact Debugger Checkbox
          local new_fact_logging = ImGui.Checkbox("Log Fact Changes", isFactLogging)
          if new_fact_logging ~= isFactLogging then
            ToggleFactDebug()
          end
          if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Spams the console with every Quest Fact change. Use only when debugging triggers.")
          end
        end
      end
    })
  end
}

-- ### EVENTS ###

registerForEvent("onInit", function()
  LoadConfig()
  GameSession.StoreInDir('sessions')
  -- Persist session state (progress only)
  GameSession.Persist(sessionState)

  -- Setup Observer safely at startup to avoid OnLoad freeze
  SetupFactObserver()

  GameSession.OnLoad(function()
    -- Initialize clean default progress
    local cleanProgress = InitializeProgress()

    -- Enforce defaults for new settings if missing
    if settings.automation_enabled == nil then settings.automation_enabled = true end
    if not settings.scanner_interval then settings.scanner_interval = 5.0 end

    -- Setup Observer if in Dev Mode (or just always, since it has a flag check)
    -- MOVED TO onInit TO PREVENT SAVE LOAD FREEZE
    -- SetupFactObserver()

    if not settings.scanner_radius then settings.scanner_radius = 50.0 end

    -- Ensure structure exists (if loading old save)
    if not sessionState.progress then sessionState.progress = {} end

    -- Merge Progress
    for id, _ in pairs(cleanProgress) do
      if sessionState.progress[id] == nil then
        sessionState.progress[id] = false
      end
    end
  end)

  GameSession.OnStart(function()
    isSessionActive = true
    Utils.Log("Game Session Started. Initializing Automation.", Utils.LogLevel.Info)

    -- Init Modules (Pass settings to Automation)
    Automation.Init(sessionState, uiCallbacks, settings.dev_mode_enabled, RelicTerminalsDB, settings)

    -- Initial Scan on Session Start
    Automation.Scan()
  end)

  GameSession.OnEnd(function()
    isSessionActive = false
    Utils.Log("Game Session Ended. Cleanup.", Utils.LogLevel.Info)
    Automation.StopScanner()
  end)

  GameSession.OnSave(function()
    SaveConfig()
  end)

  Utils.Log("Loaded (Wait for Session Start).", Utils.LogLevel.Info)
end)

registerForEvent("onOverlayOpen", function()
  isOverlayOpen = true
  if isSessionActive then
    Automation.Scan()
  end
end)
registerForEvent("onOverlayClose", function() isOverlayOpen = false end)

local checklist_mode = "manual"

registerForEvent("onDraw", function()
  if isOverlayOpen then
    if isSessionActive then
      ChecklistUI.Draw("Relic Terminal Checklist", true, RelicTerminalsDB, sessionState.progress, settings,
        uiCallbacks, checklist_mode)
    else
      ChecklistUI.DrawSplashScreen("Relic Terminal Checklist")
    end
  end
end)

registerForEvent("onUpdate", function(dt)
  if isSessionActive then
    Cron.Update(dt)
  end
end)

-- Console Command to Toggle Debug Mode
local function ToggleDebug()
  settings.dev_mode_enabled = not settings.dev_mode_enabled
  if settings.dev_mode_enabled then
    Utils.Log("Debug Mode ENABLED (Reload mod for full effect on INIT logic).")
  else
    Utils.Log("Debug Mode DISABLED.")
  end
  -- Re-init automation to update debug state
  Automation.Init(sessionState, uiCallbacks, settings.dev_mode_enabled, RelicTerminalsDB, settings)
  SaveConfig()
end

return {
  ToggleDebug = ToggleDebug,
  ToggleFactDebug = ToggleFactDebug,
  DebugTarget = Automation.DebugTarget
}
