-- ======================================================================================
-- Mod Name: Relic Terminal Checklist
-- Author: Spuddeh
-- Description: Handles Passive (Event-Driven) detection of Relic Terminals.
-- Mod Version: 2.0.1
-- ======================================================================================

local Automation = {}
local Utils = require("Modules/Utils")
local Cron = require("Modules/Cron")
local GameSession = require("Modules/GameSession")
local Ref = require("Modules/Ref")
-- local RelicTerminalsDB -- Injected via Init

-- ### STATE ###
local sessionState = nil
local uiCallbacks = nil
local _isDebug = false
local _observersInitialized = false
local _settings = nil      -- Injected settings
local _db = nil            -- Store DB ref
local _createdMappins = {} -- Track created mappins
local _lastScanTime = 0
local _notified = {}       -- Cache for notifications to avoid spam

-- Cache for ID string to Entry mapping to avoid looping DB every event
local _idToEntryMap = {}
local _wasPaused = true
local _unpauseTime = 0

-- ### QUEUE SYSTEM ###
local processingQueue = {}

function Automation.ProcessQueue()
    if #processingQueue == 0 then return end

    local entity = table.remove(processingQueue, 1)

    -- Double check if entity is still valid before processing
    if entity then
        -- Use pcall to avoid crash if entity is gone
        pcall(function()
            Automation.CheckDevice(entity, "Queue")
        end)
    end
end

-- ### INIT ###

function Automation.Init(state, callbacks, debugMode, db, settings)
    sessionState = state
    uiCallbacks = callbacks
    _isDebug = debugMode or false
    _settings = settings
    _db = db

    -- Build ID Map for fast lookup (Safe to rebuild)
    _idToEntryMap = {}
    if db then
        for catIndex, cat in ipairs(db) do
            for entryIndex, entry in ipairs(cat.entries) do
                if entry.id then
                    -- Map human-readable ID
                    _idToEntryMap[entry.id] = { cat = catIndex, entry = entryIndex, data = entry }
                end

                if entry.entityID then
                    -- CLEAN the ID string for matching: "12345ULL" -> "12345"
                    -- Because tostring(entID.hash) likely returns just digits or matches strict patterns.
                    -- Let's support both raw string and cleaned string.

                    _idToEntryMap[entry.entityID] = { cat = catIndex, entry = entryIndex, data = entry }

                    -- Strip ULL for robust matching if needed
                    local cleanHash = entry.entityID:gsub("ULL", "")
                    _idToEntryMap[cleanHash] = { cat = catIndex, entry = entryIndex, data = entry }
                end
            end
        end
    else
        Utils.Log("Automation Init Error: RelicTerminalsDB is nil!", Utils.LogLevel.Error)
    end

    -- Setup Observers ONLY ONCE per session lifecycle
    if not _observersInitialized then
        Automation.SetupObservers()
        _observersInitialized = true
    else
        if _isDebug then Utils.Log("Automation Init: Observers already running. Skipping re-hook.", Utils.LogLevel.Debug) end
    end

    -- Initial State Check
    Automation.UpdateState()

    if _isDebug then Utils.Log("Automation Module Initialized (Event-Driven + Cron).", Utils.LogLevel.Debug) end
end

-- ### EVENT OBSERVERS ###

-- ### PROXIMITY SCANNER ###

local _cronTimerId = nil

function Automation.SetupObservers()
    if _isDebug then Utils.Log("Automation: Hooking events...", Utils.LogLevel.Debug) end
    -- No constant observers needed for RTC currently.
    -- Cron is managed via Start/Stop
end

function Automation.StartScanner()
    if _cronTimerId then return end -- Already running

    if _isDebug then Utils.Log("Automation: Starting Proximity Scanner Loop.", Utils.LogLevel.Debug) end

    -- Start Passive Proximity Scanner (Cron Loop 1.0s)
    _cronTimerId = Cron.Every(1.0, function()
        local currentTime = os.clock()
        local interval = _settings and _settings.scanner_interval or 5.0

        if (currentTime - _lastScanTime) >= interval then
            Automation.ProximityScan()
            _lastScanTime = currentTime
        end
    end)
end

function Automation.StopScanner()
    if _cronTimerId then
        Cron.Halt(_cronTimerId)
        _cronTimerId = nil
        Utils.Log("Automation: Stopped Proximity Scanner Loop.")
        _createdMappins = {} -- Reset mappins
    end
end

-- Check if all items in DB are collected (Returns: bool, collectedCount, totalCount)
function Automation.CheckAllCollected()
    local total = 0
    local collected = 0

    if _db then
        for _, cat in ipairs(_db) do
            for _, entry in ipairs(cat.entries) do
                total = total + 1
                if sessionState and sessionState.progress and sessionState.progress[entry.id] then
                    collected = collected + 1
                end
            end
        end
    end

    if collected >= total and total > 0 then
        return true, collected, total
    end
    return false, collected, total
end

function Automation.SetItemStatus(id, collected)
    if not sessionState or not sessionState.progress then return end

    sessionState.progress[id] = collected
    -- Save is handled by GameSession monitoring the table changes

    -- Check completion and stop scanner if needed
    local isComplete, count, total = Automation.CheckAllCollected()

    if _isDebug then
        Utils.Log(string.format("[SetItemStatus] Item: %s | Status: %s | Progress: %d/%d | Complete: %s",
            id, tostring(collected), count, total, tostring(isComplete)), Utils.LogLevel.Debug)
    end

    if isComplete then
        Automation.StopScanner()
    end
end

function Automation.UpdateState()
    if _settings and _settings.automation_enabled then
        local isComplete = Automation.CheckAllCollected()
        if isComplete then
            Automation.StopScanner()
        else
            Automation.StartScanner()
        end
    else
        Automation.StopScanner()
    end
end

--- Periodic check for player proximity
function Automation.ProximityScan()
    local player = Game.GetPlayer()
    if not player then return end

    -- PAUSE CHECK: Suspend automation during Menus/Loading
    local isPaused = GameSession.IsPaused()

    if isPaused then
        _wasPaused = true
        return
    end

    -- Just unpaused?
    if _wasPaused then
        _unpauseTime = os.clock()
        _wasPaused = false
    end

    -- Grace Period Check (3.0s for Fade-In)
    if (os.clock() - _unpauseTime) < 3.0 then
        return
    end

    if _isDebug then
        local status = _settings and
            ("Enabled: " .. tostring(_settings.automation_enabled) .. ", Radius: " .. tostring(_settings.scanner_radius)) or
            "No Settings"
        Utils.Log("[Proximity] Scanning... " .. status, Utils.LogLevel.Debug)
    end

    local playerPos = player:GetWorldPosition()
    local radius = _settings and _settings.scanner_radius or 100.0
    local radiusSq = radius * radius

    local nativeRangeSq = 25.0 * 25.0 -- Native Icon appears at ~25m

    -- Iterate through our DB (using ID Map for convenience)
    for id, mapEntry in pairs(_idToEntryMap) do
        local entry = mapEntry.data

        -- Check Logic
        if not sessionState.progress[entry.id] then
            -- Mappin & Proximity Logic
            if entry.coords then
                local dx = playerPos.x - entry.coords.x
                local dy = playerPos.y - entry.coords.y
                local dz = playerPos.z - entry.coords.z
                local distSq = (dx * dx) + (dy * dy) + (dz * dz)

                if distSq < nativeRangeSq then
                    -- 1. TOO CLOSE: Native icon takes over. Remove ours.
                    if _createdMappins[entry.id] then
                        Automation.RemoveMappin(entry.id)
                    end

                    -- Still try to scan target for auto-resolve logic
                    Automation.ProximityScanTarget(mapEntry)
                elseif distSq < radiusSq then
                    -- 2. IN RANGE: Show custom icon
                    if not _createdMappins[entry.id] then
                        Automation.CreateMappin(entry)
                    end

                    -- Scan target for auto-resolve logic
                    Automation.ProximityScanTarget(mapEntry)
                else
                    -- 3. OUT OF RANGE: Cleanup
                    if _createdMappins[entry.id] then
                        Automation.RemoveMappin(entry.id)
                    end

                    -- Reset notification wrapper
                    if _notified[entry.id] then
                        _notified[entry.id] = nil
                    end
                end
            end
        else
            -- Already Collected: Cleanup
            if _createdMappins[entry.id] then
                Automation.RemoveMappin(entry.id)
            end
        end
    end
end

function Automation.CreateMappin(entry)
    local mappinData = MappinData.new()
    mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
    mappinData.variant = gamedataMappinVariant.Zzz16_RelicDeviceBasicVariant -- Native Relic Icon
    mappinData.visibleThroughWalls = true

    local pos = Vector4.new(entry.coords.x, entry.coords.y, entry.coords.z + 1.0, 1.0)
    local id = Game.GetMappinSystem():RegisterMappin(mappinData, pos)
    _createdMappins[entry.id] = id
end

function Automation.RemoveMappin(entryID)
    local id = _createdMappins[entryID]
    if id then
        Game.GetMappinSystem():UnregisterMappin(id)
        _createdMappins[entryID] = nil
    end
end

-- Cache for Weak References to entities
local _weakCache = {}

--- Attempts to find and check a specific terminal entity at its known location
--- @param entry table The DB entry for the terminal
function Automation.ProximityScanTarget(entry)
    -- DEBUG PROBE 1: Entry Point
    -- if _isDebug then Utils.Log("[Proximity] Scanning Target ID: " .. tostring(entry.data.entityID), Utils.LogLevel.Debug) end

    if not entry.data.entityID then return end

    local entity = nil
    local idKey = entry.data.id

    -- 1. Try Weak Cache First
    if _weakCache[idKey] and not Ref.IsExpired(_weakCache[idKey]) then
        entity = _weakCache[idKey]
        -- if _isDebug then Utils.Log("[Proximity] Using Cached Entity: " .. idKey, Utils.LogLevel.Debug) end
    else
        -- 2. Not in cache/Expired, resolve ID and Find
        -- Construct the Entity ID from the DB string (e.g., "12345ULL")
        local success, hashVal = pcall(loadstring("return " .. entry.data.entityID))

        if success and hashVal then
            local targetID = entEntityID.new()
            targetID.hash = hashVal
            entity = Game.FindEntityByID(targetID)

            -- 3. Cache if found
            if entity then
                _weakCache[idKey] = Ref.Weak(entity)
            end
        end
    end

    if entity then
        -- VISUAL NOTIFICATION (Only notify if we confirm entity exists & is loaded)
        if not _notified[entry.data.id] then
            Utils.Notify("Operational Data Terminal detected: " .. entry.data.name)
            _notified[entry.data.id] = true
            if _isDebug then Utils.Log("[Proximity] Notification sent for: " .. entry.data.name, Utils.LogLevel.Debug) end
        end

        if entity:IsA('PerkTraining') then
            -- Found it! Check status.
            Automation.CheckDevice(entity, "Proximity", false)
        end
    else
        -- DEBUG PROBE 2: Entity Lookup Result
        -- if _isDebug then Utils.Log("[Proximity] Entity not found/streamed for: " .. tostring(entry.data.entityID), Utils.LogLevel.Debug) end
    end
end

-- ### CHECK LOGIC ###

--- Checks a specific device entity (or PS) against the DB and Checklist
--- @param object userdata Entity OR PersistentState
--- @param sourceContext string
--- @param isPS boolean Set to true if object is already the PS
function Automation.CheckDevice(object, sourceContext, isPS)
    if not object then return end

    local ps = nil
    local hash = nil

    if isPS then
        ps = object
        local pid = ps:GetID()
        if pid then hash = tostring(pid.entityHash) end
    else
        -- Legacy/Entity fallback
        local entID = object:GetEntityID()
        if entID then hash = tostring(entID.hash) end
    end

    if not hash then
        if _isDebug then Utils.Log("[CheckDevice] Failed to get hash from object.", Utils.LogLevel.Debug) end
        return
    end

    local match = _idToEntryMap[hash]

    if match then
        -- We found a Relic Terminal!
        if _isDebug then Utils.Log("[CheckDevice] Checking: " .. match.data.name, Utils.LogLevel.Debug) end

        -- Double check if already collected (redundant safety)
        if sessionState.progress[match.data.id] then
            if _isDebug then Utils.Log("[CheckDevice] Already collected.", Utils.LogLevel.Debug) end
            return
        end

        -- If we passed an Entity, get the PS now (protected)
        if not isPS then
            if object.GetDevicePS then
                local success, result = pcall(function() return object:GetDevicePS() end)
                if success then
                    ps = result
                else
                    if _isDebug then
                        Utils.Log("[CheckDevice] GetDevicePS() crashed: " .. tostring(result),
                            Utils.LogLevel.Error)
                    end
                end
            else
                if _isDebug then Utils.Log("[CheckDevice] Entity missing GetDevicePS method!", Utils.LogLevel.Debug) end
            end
        end

        if ps then
            -- DEBUG: Check class name
            if _isDebug and ps.GetClassName then
                Utils.Log("[CheckDevice] PS Class: " .. tostring(ps:GetClassName()), Utils.LogLevel.Debug)
            end

            if ps.IsPerkGranted then
                local isGranted = false
                -- Protected call
                local status, err = pcall(function() isGranted = ps:IsPerkGranted() end)

                if not status then
                    if _isDebug then
                        Utils.Log("[CheckDevice] IsPerkGranted crashed: " .. tostring(err),
                            Utils.LogLevel.Error)
                    end
                end

                if _isDebug then
                    Utils.Log("[CheckDevice] IsPerkGranted result: " .. tostring(isGranted),
                        Utils.LogLevel.Debug)
                end

                if isGranted then
                    Utils.Log(
                        string.format("Automation [%s]: %s DETECTED & COLLECTED!", sourceContext, match.data.name),
                        Utils.LogLevel.Info)

                    -- NOTIFICATION: Explicitly notify about collection
                    Utils.Notify("Terminal Data Acquired: " .. match.data.name)

                    -- Mark as collected
                    sessionState.progress[match.data.id] = true

                    -- Save & Update UI
                    if uiCallbacks and uiCallbacks.onToggle then
                        uiCallbacks.onToggle(match.data.id, true)
                    end
                end
            else
                if _isDebug then Utils.Log("[CheckDevice] PS missing IsPerkGranted method!", Utils.LogLevel.Debug) end
            end
        else
            if _isDebug then Utils.Log("[CheckDevice] PS is nil.", Utils.LogLevel.Debug) end
        end
    else
        if _isDebug then Utils.Log("[CheckDevice] No DB match for hash: " .. tostring(hash), Utils.LogLevel.Debug) end
    end
end

-- Deprecated: Kept for compatibility with init.lua calls
function Automation.Scan()
    -- No-op in event driven mode
end

-- ### DEBUGGING HELPER ###
function Automation.DebugTarget()
    local player = GetPlayer()
    if not player then return end

    local target = Game.GetTargetingSystem():GetLookAtObject(player, false, false)
    if not target then
        Utils.Log("No target found. Look at a terminal.", Utils.LogLevel.Debug)
        return
    end

    local entID = target:GetEntityID()
    local idHash = entID.hash

    Utils.Log("===== DEBUG ANALYSIS START =====", Utils.LogLevel.Debug)
    Utils.Log("Debug Target Analysis:", Utils.LogLevel.Debug)
    Utils.Log("Target ID Hash: " .. tostring(idHash), Utils.LogLevel.Debug)

    -- Check Database Match
    local foundInDB = false
    -- Rebuild map just in case function is called standalone (though map is built in Init)
    -- Use the map we have
    local match = _idToEntryMap[tostring(idHash)]
    if match then
        Utils.Log("MATCH FOUND in DB: " .. match.data.label, Utils.LogLevel.Debug)
        foundInDB = true
    end

    if not foundInDB then
        Utils.Log("Target NOT found in DB. Please verify ID.", Utils.LogLevel.Debug)
    end

    -- Test DeviceSystem Lookup (EntityID)
    local deviceSystem = Game.GetScriptableSystemsContainer():Get(CName.new("DeviceSystem"))
    if not deviceSystem and Game.GetDeviceSystem then deviceSystem = Game.GetDeviceSystem() end

    if deviceSystem then
        local ps = nil
        pcall(function() ps = deviceSystem:GetDevicePS(entID) end)

        if ps then
            Utils.Log("DeviceSystem (EntityID) Lookup: SUCCESS", Utils.LogLevel.Debug)
            Utils.Log(string.format("State: IsDisabled=%s, IsOFF=%s, IsON=%s",
                tostring(ps:IsDisabled()), tostring(ps:IsOFF()), tostring(ps:IsON())), Utils.LogLevel.Debug)
        else
            Utils.Log("DeviceSystem (EntityID) Lookup: FAILED (Returned nil PS)", Utils.LogLevel.Debug)
        end

        -- Test PersistentID
        if target.GetPersistentID then
            local persID = target:GetPersistentID()
            if persID then
                Utils.Log("PersistentID found.", Utils.LogLevel.Debug)
                local ps_pers = nil
                pcall(function() ps_pers = deviceSystem:GetDevicePS(persID) end)
                if ps_pers then
                    Utils.Log("DeviceSystem (PersistentID) Lookup: SUCCESS", Utils.LogLevel.Debug)
                    Utils.Log(string.format("State: IsDisabled=%s, IsOFF=%s, IsON=%s",
                            tostring(ps_pers:IsDisabled()), tostring(ps_pers:IsOFF()), tostring(ps_pers:IsON())),
                        Utils.LogLevel.Debug)
                else
                    Utils.Log("DeviceSystem (PersistentID) Lookup: FAILED", Utils.LogLevel.Debug)
                end
            end
        end
    else
        Utils.Log("DeviceSystem: MISSING", Utils.LogLevel.Debug)
    end

    -- Test Local Access (Directly on Target)
    Utils.Log("Checking Local Target Direct Access...", Utils.LogLevel.Debug)
    if target.GetDevicePS then
        local localPS = target:GetDevicePS()
        if localPS then
            Utils.Log("Local target:GetDevicePS(): SUCCESS", Utils.LogLevel.Debug)
            Utils.Log(string.format("Local State: IsDisabled=%s, IsOFF=%s, IsON=%s",
                    tostring(localPS:IsDisabled()), tostring(localPS:IsOFF()), tostring(localPS:IsON())),
                Utils.LogLevel.Debug)

            -- Probe PerkTrainingControllerPS specific methods
            Utils.Log("--- CONTROLLER PROBE START ---", Utils.LogLevel.Debug)
            if localPS.GetClassName then
                Utils.Log("Class Name: " .. tostring(localPS:GetClassName()), Utils.LogLevel.Debug)
            end

            if localPS.IsPerkGranted then
                local status, result = pcall(function() return localPS:IsPerkGranted() end)
                Utils.Log("IsPerkGranted(): " .. tostring(result) .. " (Status: " .. tostring(status) .. ")",
                    Utils.LogLevel.Debug)
            else
                Utils.Log("IsPerkGranted: NIL", Utils.LogLevel.Debug)
            end

            if localPS.IsInteractive then
                local status, result = pcall(function() return localPS:IsInteractive() end)
                Utils.Log("IsInteractive(): " .. tostring(result) .. " (Status: " .. tostring(status) .. ")",
                    Utils.LogLevel.Debug)
            else
                Utils.Log("IsInteractive: NIL", Utils.LogLevel.Debug)
            end
            Utils.Log("--- CONTROLLER PROBE END ---", Utils.LogLevel.Debug)

            -- Deep Inspection
            Utils.Log("--- PS DUMP START ---", Utils.LogLevel.Debug)
            Utils.Dump(localPS, 1)
            Utils.Log("--- PS DUMP END ---", Utils.LogLevel.Debug)
        else
            Utils.Log("Local target:GetDevicePS(): RETURNED NIL", Utils.LogLevel.Debug)
        end
    else
        Utils.Log("Local target does not have GetDevicePS method.", Utils.LogLevel.Debug)
    end

    Utils.Log("===== DEBUG ANALYSIS END =====", Utils.LogLevel.Debug)
end

return Automation
