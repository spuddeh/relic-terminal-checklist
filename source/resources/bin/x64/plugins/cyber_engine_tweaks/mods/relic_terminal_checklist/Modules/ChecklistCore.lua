-- ======================================================================================
-- ChecklistCore.lua
-- Author: Spuddeh
-- Description: Shared automation core for all Checklist mods.
--              Handles SpatialSet lifecycle, mappin management, suppression state,
--              notification queuing, and item status. All mod-specific values
--              (setName, mappinVariant, callbacks) are injected via Core.Init().
--              This file is byte-identical across all four checklist mods.
-- ======================================================================================

local ChecklistCore = {}
local Utils = require("Modules/Utils")
local Ref   = require("Modules/Ref")

-- ### STATE ###

local _engine       = nil
local _sessionState = nil
local _settings     = nil
local _isDebug      = false
local _config       = nil   -- injected by each mod's Automation.Init()

-- SpatialSet
local _spatialHandle  = nil
local _entryMap       = {}   -- id → spatial entry table (for lazy removal)
local _nearbyEntries  = {}   -- id → dbEntry for items currently within scanner_radius

-- Detection zones (pre-registered per uncollected item with container_id)
-- Two zones per entry: large for mappin snap, small for LookAt-gated inventory check.
-- Persist until item collected.
local _snapZones     = {}   -- id → zone handle (wide radius: entity resolve + mappin snap)
local _lookAtZones   = {}   -- id → zone handle (tight radius: LookAt gate + checkInventory)
local _mappinSnapped = {}   -- id → bool (whether mappin has been snapped to entity pos)

-- Suppression
local _wasPaused      = true  -- starts paused; cleared by SetMenuPaused(false) in WhenReady
local _inCombat       = false
local _inCutscene     = false
local _unpauseTime    = 0     -- os.clock() timestamp; future value = teleport cooldown
local _scanTimerHandle = nil  -- deferred post-grace Scan() handle

-- Mappin tracking. This is ONLY the proximity auto-mappin. The user "Set Pin"
-- waypoint is owned entirely by each mod's init.lua and never enters Core — that
-- decoupling is deliberate (see decisions/user-pin-decoupled-from-core).
local _createdMappins = {}    -- id → proximity auto-mappin handle
local _notifiedCache  = {}

-- Vendor notification queue
local _isVendorOpen = false
local _msgQueue     = {}

-- Entity cache
local _entityCache = {}

-- ### SUPPRESSION ###

function ChecklistCore.SetMenuPaused(isPaused)
    if _isDebug then
        Utils.Log(string.format("[Core] SetMenuPaused(%s) | wasPaused=%s | clock=%.2f",
            tostring(isPaused), tostring(_wasPaused), os.clock()), Utils.LogLevel.Debug)
    end
    if _scanTimerHandle and _engine then
        _engine.ClearTimer(_scanTimerHandle)
        _scanTimerHandle = nil
    end
    if isPaused then
        _wasPaused = true
    else
        _unpauseTime = os.clock()
        _wasPaused = false
        -- Schedule a scan after the grace period to create mappins for items
        -- the player is already near (SpatialSet.onEnter is suppressed during grace period
        -- and won't re-fire once the player is inside the boundary).
        if _engine then
            _scanTimerHandle = _engine.SetTimeout(3.5, function()
                _scanTimerHandle = nil
                ChecklistCore.Scan()
            end)
        end
    end
end

function ChecklistCore.SetInCombat(inCombat)
    _inCombat = inCombat
end

function ChecklistCore.SetInCutscene(inCutscene)
    _inCutscene = inCutscene
end

function ChecklistCore.IsSuppressed()
    if _wasPaused then return true end
    if _inCombat then return true end
    if _inCutscene then return true end
    local now = os.clock()
    if _unpauseTime > now then return true end
    if (now - _unpauseTime) < 3.0 then return true end
    return false
end

-- ### NOTIFICATION QUEUE ###

function ChecklistCore.SetVendorOpen(isOpen)
    _isVendorOpen = isOpen
    if not isOpen then
        for _, msg in ipairs(_msgQueue) do
            Utils.Notify(msg)
        end
        _msgQueue = {}
    end
end

function ChecklistCore.QueueOrShow(text)
    if _isVendorOpen then
        table.insert(_msgQueue, text)
        if _isDebug then Utils.Log("Queued notification: " .. text, Utils.LogLevel.Debug) end
    else
        Utils.Notify(text)
    end
end

function ChecklistCore.IsNotified(id)
    return _notifiedCache[id] == true
end

function ChecklistCore.SetNotified(id)
    _notifiedCache[id] = true
end

function ChecklistCore.ClearNotified(id)
    _notifiedCache[id] = nil
end

-- ### STATE HELPERS ###

function ChecklistCore.CheckAllCollected()
    if not _config or not _config.buildEntries then return false, 0, 0 end

    local uncollected = _config.buildEntries()
    local remaining   = #uncollected

    local collected = 0
    if _sessionState and _sessionState.progress then
        for _, v in pairs(_sessionState.progress) do
            if v == true then collected = collected + 1 end
        end
    end

    local total = collected + remaining
    return (remaining == 0 and total > 0), collected, total
end

-- ### ENTITY RESOLUTION ###

local function ResolveEntity(entry)
    if _entityCache[entry.id] and not Ref.IsExpired(_entityCache[entry.id]) then
        return _entityCache[entry.id]
    end
    if entry.container_id then
        local success, hashVal = pcall(loadstring("return " .. tostring(entry.container_id)))
        if success and hashVal then
            local tid = entEntityID.new()
            tid.hash = hashVal
            local entity = Game.FindEntityByID(tid)
            if entity then
                _entityCache[entry.id] = Ref.Weak(entity)
                return entity
            end
        end
    end
    return nil
end

-- ### MAPPINS ###

function ChecklistCore.CreateMappin(entry, entity)
    -- No-op if a proximity mappin already exists for this entry. Callers that want
    -- to refresh it must call RemoveMappin first.
    if _createdMappins[entry.id] then return end

    local mappinData = MappinData.new()
    mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
    mappinData.variant = (_config and _config.getMappinVariant and _config.getMappinVariant(entry))
        or (_config and _config.mappinVariant)
        or gamedataMappinVariant.CustomPositionVariant
    mappinData.visibleThroughWalls = true

    local pos = Vector4.new(entry.coords.x, entry.coords.y, entry.coords.z + 1.0, 1.0)
    if entity then
        pos   = entity:GetWorldPosition()
        pos.z = pos.z + 0.5
    end

    _createdMappins[entry.id] = Game.GetMappinSystem():RegisterMappin(mappinData, pos)

    if _isDebug then
        Utils.Log(string.format("[CreateMappin] %s (%s) at (%.1f,%.1f,%.1f)%s | handle=%s",
            entry.id, entry.name or "?", pos.x, pos.y, pos.z,
            entity and " [snapped to entity]" or " [coords]",
            tostring(_createdMappins[entry.id])), Utils.LogLevel.Debug)
    end
end

-- NOTE: There is intentionally no user-pin API here. The "Set Pin" waypoint is a
-- plain manual map waypoint owned by each mod's init.lua (runtimeState), completely
-- independent of Core's proximity automation. Threading it through Core's mappin
-- state caused a desync bug class under 0-Engine 1.18.2's aggressive PlayerInvalidated
-- churn — see decisions/user-pin-decoupled-from-core.

function ChecklistCore.RemoveMappin(entryID)
    local id = _createdMappins[entryID]
    if id then
        Game.GetMappinSystem():UnregisterMappin(id)
        _createdMappins[entryID] = nil
        _mappinSnapped[entryID]  = nil
    end
end

-- ### DETECTION ZONES ###
-- Two zones per uncollected item with a container_id:
--   Snap zone (wide): resolves entity and snaps the mappin to world pos.
--   LookAt zone (tight): runs checkInventory only when the player's crosshair
--       is on the container entity — guarantees inventory is fully streamed.
-- Zones persist until the item is collected; no dependency on SpatialSet timing.

local function RegisterDetectionZone(entry)
    if not _engine or not entry.container_id then return end

    -- Zone radius. RTC opts the zone to the live scanner_radius via
    -- detectionZoneUsesScannerRadius so it polls for the device entity across the
    -- whole approach (re-read here every RegisterItemSet, so the slider stays live).
    -- Snap-based mods keep the tight snapRadius default.
    local snapRadius   = (_config and _config.detectionZoneUsesScannerRadius
                            and _settings and _settings.scanner_radius)
                       or (_config and _config.snapRadius) or 20.0
    local lookAtRadius = (_config and _config.lookAtRadius) or 3.0
    local setName      = (_config and _config.setName) or "checklist"

    -- Snap zone: mappin creation + entity-position snap (default behaviour).
    -- Mods may override via onSnapEnter/onSnapExit callbacks and opt out of the
    -- default snap via config.noAutoSnap (e.g. RTC, where the game's own native
    -- mappin takes over inside the snap radius so we HIDE ours there).
    local snapHandle
    snapHandle = _engine.RegisterZone({
        id       = setName .. "_snap_" .. entry.id,
        x        = entry.coords.x,
        y        = entry.coords.y,
        z        = entry.coords.z,
        radius   = snapRadius,
        throttle = 30,
        onEnter  = function()
            if _config and _config.onSnapEnter then
                local entity = ResolveEntity(entry)
                _config.onSnapEnter(entry, entity)
            end
        end,
        onTick   = function()
            -- onZoneTick: unconditional per-tick hook (runs regardless of noAutoSnap
            -- and the canShow/canMappin gates). RTC uses this to trigger the game's
            -- own native detection once its PerkTraining entity has streamed in.
            -- Passed the resolved entity (may be nil until the game streams it).
            if _config and _config.onZoneTick then
                _config.onZoneTick(entry, ResolveEntity(entry))
            end

            if _config and _config.noAutoSnap then return end
            if _config and _config.canShow and not _config.canShow(entry) then return end
            if _config and _config.canMappin and not _config.canMappin(entry) then return end

            -- Ensure mappin exists (player may have loaded inside zone during grace period)
            if not _createdMappins[entry.id] then
                ChecklistCore.CreateMappin(entry, nil)
            end

            local entity = ResolveEntity(entry)
            if not entity then return end

            -- Snap mappin to entity world position via in-place SetMappinPosition.
            -- Same handle, so any tracked state (and GPS trail the player has triggered
            -- via map open/close) follows the position update. RemoveMappin + CreateMappin
            -- would break tracking because re-registration loses the tracked flag.
            if not _mappinSnapped[entry.id] then
                local handle = _createdMappins[entry.id]
                if handle then
                    local pos = entity:GetWorldPosition()
                    pos.z = pos.z + 0.5
                    Game.GetMappinSystem():SetMappinPosition(handle, pos)
                    _mappinSnapped[entry.id] = true
                    if _isDebug then
                        Utils.Log(string.format(
                            "[SnapZone] Mappin position updated in-place: %s at (%.1f,%.1f,%.1f)",
                            entry.id, pos.x, pos.y, pos.z), Utils.LogLevel.Debug)
                    end
                end
            end
        end,
        onExit = function()
            -- Reset snap so mappin re-snaps on next entry (handles mappin recreation)
            _mappinSnapped[entry.id] = nil
            if _config and _config.onSnapExit then _config.onSnapExit(entry) end
        end,
    })
    _snapZones[entry.id] = snapHandle

    -- LookAt zone: only registered if the mod uses inventory-based collection check
    if _config and _config.checkInventory then
        local lookHandle
        lookHandle = _engine.RegisterZone({
            id       = setName .. "_look_" .. entry.id,
            x        = entry.coords.x,
            y        = entry.coords.y,
            z        = entry.coords.z,
            radius   = lookAtRadius,
            throttle = 30,
            onTick   = function()
                local entity = ResolveEntity(entry)
                if not entity then return end

                local targeting = Game.GetTargetingSystem()
                local player    = Game.GetPlayer()
                if not targeting or not player then return end
                local lookedAt = targeting:GetLookAtObject(player, false, false)
                if not lookedAt then return end
                if lookedAt:GetEntityID().hash ~= entity:GetEntityID().hash then return end

                local result = _config.checkInventory(entry, entity)
                if _isDebug then
                    Utils.Log(string.format("[LookAt] %s | result=%s | clock=%.2f",
                        entry.id, tostring(result), os.clock()), Utils.LogLevel.Debug)
                end
                if result == false then
                    Utils.Log("[LookAt] Container empty. Auto-collecting: " .. entry.name,
                        Utils.LogLevel.Debug)
                    ChecklistCore.SetItemStatus(entry.id, true)
                    if _config.onAutoCollect then _config.onAutoCollect(entry) end
                elseif result == true then
                    -- Shard confirmed present; further LookAt polling is redundant.
                    -- OnInventoryItemAdded handles the actual loot event.
                    local h = _lookAtZones[entry.id]
                    if h then
                        h:unregister()
                        _lookAtZones[entry.id] = nil
                        if _isDebug then
                            Utils.Log("[LookAt] Shard confirmed present; zone retired: " ..
                                entry.id, Utils.LogLevel.Debug)
                        end
                    end
                end
                -- result == nil: keep polling on next tick
            end,
        })
        _lookAtZones[entry.id] = lookHandle
    end
end

local function CancelSnapZone(id)
    if _snapZones[id] then
        _snapZones[id]:unregister()
        _snapZones[id] = nil
    end
    if _lookAtZones[id] then
        _lookAtZones[id]:unregister()
        _lookAtZones[id] = nil
    end
    _mappinSnapped[id] = nil
end

local function CancelAllSnapZones()
    for _, handle in pairs(_snapZones) do handle:unregister() end
    for _, handle in pairs(_lookAtZones) do handle:unregister() end
    _snapZones     = {}
    _lookAtZones   = {}
    _mappinSnapped = {}
end

-- ### CONTAINER INVENTORY CHECK (shared by mods whose detection relies on container state) ###
-- Given a container entity and a prebuilt lookup table of target TweakDBID keys, returns:
--   true  → container holds at least one matching item
--   false → container holds no matching items (other loot may be present)
--   nil   → can't determine (entity/trans unavailable, binding missing, or GetItemList failed)

-- Builds a key-lookup table from a list of TweakDBID strings. Keys are normalised via
-- tostring(TweakDBID.new()) so they always match whatever form CET produces at iteration time.
function ChecklistCore.MakeKeyLookup(tdbidStrings)
    local keys = {}
    for _, s in ipairs(tdbidStrings) do
        keys[tostring(TweakDBID.new(s))] = true
    end
    return keys
end

-- Uses Inspector's proven pattern: fetch TransactionSystem inside, pcall the call,
-- handle the multi-return variant (CET may place the item list in either slot).
function ChecklistCore.ContainerContainsAny(entity, keys)
    if not entity then return nil end
    local trans = Game.GetTransactionSystem()
    if not trans then return nil end

    local ok, r1, r2 = pcall(function() return trans:GetItemList(entity) end)
    if not ok then
        if _isDebug then Utils.Log("[Inv] GetItemList error: " .. tostring(r1), Utils.LogLevel.Debug) end
        return nil
    end
    local itemList = (type(r2) == "table" and r2) or (type(r1) == "table" and r1) or nil
    if _isDebug then
        Utils.Log(string.format("[Inv] count=%s",
            itemList and tostring(#itemList) or "nil"), Utils.LogLevel.Debug)
    end
    if not itemList then return nil end
    for _, itemData in ipairs(itemList) do
        if itemData and itemData.GetID then
            local tdbidStr = tostring(ItemID.GetTDBID(itemData:GetID()))
            if _isDebug then Utils.Log("[Inv]   - " .. tdbidStr, Utils.LogLevel.Debug) end
            if keys[tdbidStr] then return true end
        end
    end
    return false
end

-- ### LOOT LOOKUP (O(1) inventory hook — only for mods with unique baseIDs per entry) ###

local _tdbidLookup = {}

local function BuildTDBIDLookup(entries)
    _tdbidLookup = {}
    for _, spatialEntry in ipairs(entries) do
        local entry = spatialEntry.dbEntry
        if entry and entry.baseID then
            local fullID = entry.baseID
            if not string.find(fullID, "Items%.") then fullID = "Items." .. fullID end
            _tdbidLookup[tostring(TweakDBID.new(fullID))] = entry
        end
    end
end

function ChecklistCore.OnItemLooted(tdbid, notifyPrefix)
    if not tdbid then return false end
    local entry = _tdbidLookup[tostring(tdbid)]
    if not entry then return false end
    if _config and _config.isCollected and _config.isCollected(entry.id) then return false end
    ChecklistCore.SetItemStatus(entry.id, true)
    if _isDebug then
        Utils.Log("[Loot] MATCH FOUND: " .. entry.name, Utils.LogLevel.Debug)
    end
    if notifyPrefix then
        Utils.Notify(notifyPrefix .. ": " .. entry.name)
    end
    return true
end

-- ### SPATIAL SET ###

local function BuildSpatialEntries()
    if not _config or not _config.buildEntries then return {} end
    local entries = {}
    _entryMap = {}
    for _, spatialEntry in ipairs(_config.buildEntries()) do
        table.insert(entries, spatialEntry)
        _entryMap[spatialEntry.id] = spatialEntry
    end
    return entries
end

function ChecklistCore.RegisterItemSet()
    if not _engine or not _config then return end

    if _spatialHandle then
        _spatialHandle:unregister()
        _spatialHandle = nil
        CancelAllSnapZones()
    end

    local entries = BuildSpatialEntries()
    BuildTDBIDLookup(entries)

    local radius  = (_settings and _settings.scanner_radius) or 50.0
    local setName = _config.setName or "checklist_items"

    if #entries == 0 then
        Utils.Log("All items collected. SpatialSet not registered.")
        return
    end

    _spatialHandle = _engine.RegisterSpatialSet(setName, entries, {
        gridSize     = 200,
        pollRadius   = radius,
        pollThrottle = 30,
        onEnter      = function(spatialEntry, distSq)
            local entry = spatialEntry.dbEntry
            _nearbyEntries[entry.id] = entry  -- always track, even during suppression
            if ChecklistCore.IsSuppressed() then return end
            -- canShow: full gate (mappin + notification). Used for entries that
            -- shouldn't be revealed at all yet (CSC/CCSC quest_fact / spawn_fact).
            if _config.canShow and not _config.canShow(entry) then return end
            -- canMappin: narrower gate, mappin only. onItemEnter still fires so
            -- the mod can notify even when the icon is suppressed (RTC, where the
            -- game's native mappin takes over after trigger crossing).
            if not (_config.canMappin and not _config.canMappin(entry)) then
                if not _createdMappins[entry.id] then
                    ChecklistCore.CreateMappin(entry, nil)
                end
            end
            if _config.onItemEnter then
                _config.onItemEnter(spatialEntry, distSq)
            end
        end,
        onExit       = function(spatialEntry)
            local entry = spatialEntry.dbEntry
            _nearbyEntries[entry.id] = nil
            if _config.onItemExit then
                _config.onItemExit(spatialEntry)
            else
                ChecklistCore.RemoveMappin(entry.id)
                ChecklistCore.ClearNotified(entry.id)
            end
        end,
    })

    -- Pre-register detection zones for all entries with a container_id.
    -- Zones are independent of SpatialSet timing: they handle entity snap
    -- and inventory checking once the player is within snapRadius (20m).
    for _, spatialEntry in ipairs(entries) do
        RegisterDetectionZone(spatialEntry.dbEntry)
    end

    local zoneCount = 0
    for _ in pairs(_snapZones) do zoneCount = zoneCount + 1 end
    Utils.Log(string.format("SpatialSet registered: %d items (radius %.0fm), %d detection zones.",
        #entries, radius, zoneCount))
end

function ChecklistCore.UnregisterItemSet()
    if _scanTimerHandle and _engine then
        _engine.ClearTimer(_scanTimerHandle)
        _scanTimerHandle = nil
    end
    if _spatialHandle then
        _spatialHandle:unregister()
        _spatialHandle = nil
    end
    CancelAllSnapZones()
    _entryMap       = {}
    _nearbyEntries  = {}
    _createdMappins = {}
    _notifiedCache  = {}
    Utils.Log("SpatialSet and detection zones unregistered.")
end

function ChecklistCore.HasNearbyEntries()
    return next(_nearbyEntries) ~= nil
end

-- ### ITEM STATUS ###

function ChecklistCore.SetItemStatus(id, collected)
    if not _sessionState or not _sessionState.progress then
        if _isDebug then
            Utils.Log("[SetItemStatus] Error: _sessionState is nil/invalid!", Utils.LogLevel.Error)
        end
        return
    end

    _sessionState.progress[id] = collected

    local isComplete, count, total = ChecklistCore.CheckAllCollected()

    if _isDebug then
        Utils.Log(string.format("[SetItemStatus] %s | %s | %d/%d | done: %s",
            id, tostring(collected), count, total, tostring(isComplete)), Utils.LogLevel.Debug)
    end

    if collected then
        if _spatialHandle and _entryMap[id] then
            _spatialHandle:remove(_entryMap[id])
            _entryMap[id] = nil
        end
        _nearbyEntries[id] = nil
        CancelSnapZone(id)
        ChecklistCore.RemoveMappin(id)
        if isComplete then
            ChecklistCore.UnregisterItemSet()
        end
    else
        ChecklistCore.UpdateState()
    end
end

-- ### CLOSEST UNCOLLECTED ###

function ChecklistCore.ResolveClosestUncollected(maxRadius)
    local player = Game.GetPlayer()
    if not player then return nil end

    local playerPos            = player:GetWorldPosition()
    local radiusSq             = (maxRadius or 100.0) ^ 2
    local closest, closestDistSq = nil, radiusSq

    local source = next(_nearbyEntries) ~= nil and _nearbyEntries or nil

    if source then
        for _, entry in pairs(source) do
            if entry.coords then
                local dx = playerPos.x - entry.coords.x
                local dy = playerPos.y - entry.coords.y
                local dz = playerPos.z - entry.coords.z
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq < closestDistSq then
                    closestDistSq = distSq
                    closest       = entry
                end
            end
        end
    elseif _config and _config.buildEntries then
        for _, spatialEntry in ipairs(_config.buildEntries()) do
            local entry = spatialEntry.dbEntry
            if entry and entry.coords then
                local dx = playerPos.x - entry.coords.x
                local dy = playerPos.y - entry.coords.y
                local dz = playerPos.z - entry.coords.z
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq < closestDistSq then
                    closestDistSq = distSq
                    closest       = entry
                end
            end
        end
    end

    if closest and _isDebug then
        Utils.Log("[Predict] Closest uncollected: " .. closest.name ..
            " (distSq: " .. closestDistSq .. ")", Utils.LogLevel.Debug)
    end
    return closest
end

-- ### STATE UPDATE ###

function ChecklistCore.UpdateState()
    if _settings and _settings.automation_enabled then
        local isComplete = ChecklistCore.CheckAllCollected()
        if isComplete then
            ChecklistCore.UnregisterItemSet()
        else
            ChecklistCore.RegisterItemSet()
        end
    else
        ChecklistCore.UnregisterItemSet()
    end
end

-- ### SCAN (belt-and-suspenders, called on overlay open and after grace period) ###

function ChecklistCore.Scan()
    if not (_engine and _spatialHandle and _settings and _config) then return end
    local player = Game.GetPlayer()
    if not player then return end

    local setName = _config.setName or "checklist_items"
    local radius  = _settings.scanner_radius or 50.0
    local nearby  = _engine.QueryWithin(setName, radius * radius)
    if not nearby then return end

    local playerPos = player:GetWorldPosition()

    for _, spatialEntry in ipairs(nearby) do
        local entry = spatialEntry.dbEntry
        if entry and entry.coords then
            if not (_config.canShow and not _config.canShow(entry)) then
                if not (_config.canMappin and not _config.canMappin(entry)) then
                    if not _createdMappins[entry.id] then
                        local entity = ResolveEntity(entry)
                        ChecklistCore.CreateMappin(entry, entity)
                    end
                end
                if _config.onItemEnter then
                    local dx     = playerPos.x - entry.coords.x
                    local dy     = playerPos.y - entry.coords.y
                    local dz     = playerPos.z - entry.coords.z
                    local distSq = dx * dx + dy * dy + dz * dz
                    _config.onItemEnter(spatialEntry, distSq)
                end
            end
        end
    end
end

-- ### INIT ###

function ChecklistCore.Init(engine, sessionState, settings, config, isDebug)
    _engine       = engine
    _sessionState = sessionState
    _settings     = settings
    _config       = config
    _isDebug      = isDebug or false

    _entityCache = {}
    _msgQueue    = {}

    Utils.Log("ChecklistCore initialized. (Debug: " .. tostring(_isDebug) .. ")")
end

return ChecklistCore
