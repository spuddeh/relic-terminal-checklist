-- ======================================================================================
-- Mod Name: Relic Terminal Checklist
-- Author: Spuddeh
-- Description: RTC-specific automation logic. Delegates shared behaviour to ChecklistCore.
-- Mod Version: 2.1.0
-- ======================================================================================

local Automation        = {}
local Core              = require("Modules/ChecklistCore")
local RelicTerminalsDB  = require("db")
local Utils             = require("Modules/Utils")

-- ### FORWARDED CORE API ###
-- init.lua calls these; they delegate to ChecklistCore.

Automation.SetInCombat              = Core.SetInCombat
Automation.SetInCutscene            = Core.SetInCutscene
Automation.SetMenuPaused            = Core.SetMenuPaused
Automation.SetItemStatus            = Core.SetItemStatus
Automation.UpdateState              = Core.UpdateState
Automation.RegisterItemSet          = Core.RegisterItemSet
Automation.UnregisterItemSet        = Core.UnregisterItemSet
Automation.RemoveMappin             = Core.RemoveMappin
Automation.HasNearbyEntries         = Core.HasNearbyEntries

-- ### RTC-SPECIFIC: STATE ###

local _sessionState = nil
local _isDebug      = false
local _hashToEntry  = {}   -- entityID string → DB entry (built at Init)

local function IsCollected(id)
    return _sessionState and _sessionState.progress and _sessionState.progress[id] == true
end

-- ### RTC-SPECIFIC: BUILD ENTRIES ###

-- RTC's DB uses `entityID` (not `container_id`) — alias into each entry so Core's
-- ResolveEntity works unchanged. One-time mutation per session.
local function NormaliseEntries()
    for _, cat in ipairs(RelicTerminalsDB) do
        for _, entry in ipairs(cat.entries) do
            if entry.entityID and not entry.container_id then
                entry.container_id = entry.entityID
            end
        end
    end
end

local function BuildEntries()
    NormaliseEntries()
    local entries = {}
    for _, cat in ipairs(RelicTerminalsDB) do
        for _, entry in ipairs(cat.entries) do
            if not IsCollected(entry.id) and entry.coords and entry.container_id then
                table.insert(entries, {
                    x       = entry.coords.x,
                    y       = entry.coords.y,
                    z       = entry.coords.z,
                    id      = entry.id,
                    name    = entry.name,
                    dbEntry = entry,
                })
            end
        end
    end
    return entries
end

local function BuildHashLookup()
    _hashToEntry = {}
    for _, cat in ipairs(RelicTerminalsDB) do
        for _, entry in ipairs(cat.entries) do
            if entry.entityID then
                _hashToEntry[entry.entityID] = entry
                local stripped = entry.entityID:gsub("ULL", "")
                _hashToEntry[stripped] = entry
            end
        end
    end
end

-- ### RTC-SPECIFIC: PERK GRANT HELPERS ###

-- Returns true if the terminal's PS reports IsPerkGranted = true, false otherwise, nil on failure.
local function IsEntityGranted(entity)
    if not entity then return nil end
    local ok, ps = pcall(function() return entity:GetDevicePS() end)
    if not ok or not ps then return nil end
    local okGrant, granted = pcall(function() return ps:IsPerkGranted() end)
    if not okGrant then return nil end
    return granted
end

-- Retroactive grant scan — iterates all uncollected entries, tries to resolve their entity,
-- and auto-collects any whose IsPerkGranted = true. Runs on WhenReady + overlay open for
-- entities already loaded in the world (typically player is in Dogtown).
function Automation.CheckPerkGrants()
    local count = 0
    for _, cat in ipairs(RelicTerminalsDB) do
        for _, entry in ipairs(cat.entries) do
            if not IsCollected(entry.id) and entry.entityID then
                local success, hashVal = pcall(loadstring("return " .. tostring(entry.entityID)))
                if success and hashVal then
                    local tid = entEntityID.new()
                    tid.hash = hashVal
                    local entity = Game.FindEntityByID(tid)
                    if entity and IsEntityGranted(entity) == true then
                        Core.SetItemStatus(entry.id, true)
                        Utils.Log("[PerkGrants] Retroactive: " .. entry.name, Utils.LogLevel.Debug)
                        count = count + 1
                    end
                end
            end
        end
    end
    if count > 0 then
        Utils.Log("Retroactively marked " .. count .. " terminal(s) via IsPerkGranted.", Utils.LogLevel.Info)
    end
end

-- ### RTC-SPECIFIC: CALLBACKS ###

-- SpatialSet.onEnter (player enters 50m ring): notification only.
-- Mod mappin is created by Core.RegisterItemSet's default SpatialSet onEnter.
local function OnItemEnter(spatialEntry, _)
    local entry = spatialEntry.dbEntry
    if not Core.IsNotified(entry.id) then
        Core.QueueOrShow("Operational Data Terminal detected: " .. entry.name)
        Core.SetNotified(entry.id)
    end
end

-- Snap zone onEnter (player enters 25m ring): hide mod mappin (game's native icon takes over)
-- AND do a one-shot IsPerkGranted check for retroactive detection on this terminal.
local function OnSnapEnter(entry, entity)
    Core.RemoveMappin(entry.id)
    if IsEntityGranted(entity) == true then
        Utils.Log("[SnapEnter] Retroactive grant: " .. entry.name, Utils.LogLevel.Debug)
        Core.SetItemStatus(entry.id, true)
        Utils.Notify("Terminal Data Acquired: " .. entry.name)
    end
end

-- Snap zone onExit (player crosses 25m outward into 25-50m ring): restore mod mappin.
-- If item has been collected in the meantime, the zone is already unregistered so this
-- won't fire. If the player is still within 50m, the mappin should be visible.
local function OnSnapExit(entry)
    if not IsCollected(entry.id) then
        Core.CreateMappin(entry, nil)
    end
end

-- ### SCAN (overlay open + WhenReady) ###

function Automation.Scan()
    Automation.CheckPerkGrants()
    Core.Scan()
end

-- ### SETTINGS / LIFECYCLE ###

-- Ensures Core.Init runs with the RTC config table. Called from init.lua.
function Automation.Init(sessionState, _, debugMode, settings)
    _sessionState = sessionState
    _isDebug      = debugMode or false

    NormaliseEntries()
    BuildHashLookup()

    Core.Init(GetMod("0-Engine"), sessionState, settings, {
        setName          = "rtc_items",
        mappinVariant    = gamedataMappinVariant.Zzz16_RelicDeviceBasicVariant,
        snapRadius       = 25.0,          -- native relic icon takes over at this range
        buildEntries     = BuildEntries,
        onItemEnter      = OnItemEnter,
        onSnapEnter      = OnSnapEnter,
        onSnapExit       = OnSnapExit,
        noAutoSnap       = true,           -- RTC manages the mappin itself (hide at 25m, restore on exit)
        isCollected      = IsCollected,
    }, _isDebug)

    local _, count, total = Core.CheckAllCollected()
    Utils.Log(string.format("Automation Init: %d/%d collected.", count, total))
end

-- ### OBSERVER SETUP ###
-- Called once from init.lua after 0-Engine ready. Binds ObserveAfter on the PS grant method.
-- Also hashes the PS's entity ID back to our DB.

local _observerInstalled = false

function Automation.SetupGrantObserver()
    if _observerInstalled then return end
    _observerInstalled = true

    ObserveAfter("PerkTrainingControllerPS", "TryGrantPerk", function(this)
        if not _sessionState or not _sessionState.progress then return end

        local pid = this:GetID()
        if not pid then return end
        local hashStr = tostring(pid.entityHash)

        local entry = _hashToEntry[hashStr]
        if not entry then
            -- Try stripped form — defensive against ULL suffix differences
            local stripped = hashStr:gsub("ULL", "")
            entry = _hashToEntry[stripped]
            if not entry then
                if _isDebug then
                    Utils.Log("[Observer] TryGrantPerk fired on unknown hash: " .. hashStr,
                        Utils.LogLevel.Debug)
                end
                return
            end
        end

        if IsCollected(entry.id) then return end

        Utils.Log("[Observer] Terminal activated: " .. entry.name, Utils.LogLevel.Info)
        Core.SetItemStatus(entry.id, true)
        Utils.Notify("Terminal Data Acquired: " .. entry.name)
    end)

    Utils.Log("TryGrantPerk observer installed.")
end

-- ### DEV TOOL: DebugTarget ###

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
    Utils.Log("Target ID Hash: " .. tostring(idHash), Utils.LogLevel.Debug)

    local match = _hashToEntry[tostring(idHash)]
    if match then
        Utils.Log("MATCH FOUND in DB: " .. tostring(match.name or match.id), Utils.LogLevel.Debug)
    else
        Utils.Log("Target NOT found in DB.", Utils.LogLevel.Debug)
    end

    if target.GetDevicePS then
        local ok, localPS = pcall(function() return target:GetDevicePS() end)
        if ok and localPS then
            Utils.Log("Local target:GetDevicePS(): SUCCESS", Utils.LogLevel.Debug)
            if localPS.GetClassName then
                Utils.Log("Class Name: " .. tostring(localPS:GetClassName()), Utils.LogLevel.Debug)
            end
            local okG, granted = pcall(function() return localPS:IsPerkGranted() end)
            Utils.Log("IsPerkGranted(): " .. tostring(granted) .. " (ok=" .. tostring(okG) .. ")",
                Utils.LogLevel.Debug)
        else
            Utils.Log("Local target:GetDevicePS(): FAILED", Utils.LogLevel.Debug)
        end
    end

    Utils.Log("===== DEBUG ANALYSIS END =====", Utils.LogLevel.Debug)
end

return Automation
