-- ======================================================================================
-- Mod Name: Relic Terminal Checklist
-- Author: Spuddeh
-- Description: RTC-specific automation logic. Delegates shared behaviour to ChecklistCore.
-- Mod Version: 3.0.0
-- ======================================================================================
--
-- RTC does NOT draw its own proximity mappin. Instead, when the player comes within
-- scanner_radius and the PerkTraining device entity has streamed in, RTC triggers the
-- game's OWN native detection (PerkTrainingControllerPS:SetDeviceAsDetected +
-- PerkTraining:TryShowMappin). The game then owns the relic mappin entirely: show
-- AND teardown-on-grant. Core is therefore wired with a constant-false canMappin gate
-- (see below) so it never draws a mappin of its own, and the proximity zone is used
-- only for the "approaching terminal" notification.
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
local _settings     = nil  -- captured at Init (for live scanner_radius in debug logs)
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

-- ### RTC-SPECIFIC: ENTITY HELPERS ###

-- Resolves the PerkTraining entity for a DB entry via its entityID.
-- Returns the entity (if loaded) or nil.
local function ResolveTerminalEntity(entry)
    if not entry.entityID then return nil end
    local success, hashVal = pcall(loadstring("return " .. tostring(entry.entityID)))
    if not success or not hashVal then return nil end
    local tid = entEntityID.new()
    tid.hash = hashVal
    return Game.FindEntityByID(tid)
end

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
                local entity = ResolveTerminalEntity(entry)
                if entity and IsEntityGranted(entity) == true then
                    Core.SetItemStatus(entry.id, true)
                    Utils.Log("[PerkGrants] Retroactive: " .. entry.name, Utils.LogLevel.Debug)
                    count = count + 1
                end
            end
        end
    end
    if count > 0 then
        Utils.Log("Retroactively marked " .. count .. " terminal(s) via IsPerkGranted.", Utils.LogLevel.Info)
    end
end

-- ### RTC-SPECIFIC: CALLBACKS ###

-- SpatialSet.onEnter (player crosses scanner_radius): notification only — an early
-- "terminal nearby" heads-up. The native relic mappin is handled by the game once
-- TriggerNativeDetection fires (see below); RTC draws no mappin of its own.
local function OnItemEnter(spatialEntry, _)
    local entry = spatialEntry.dbEntry
    if not Core.IsNotified(entry.id) then
        Core.QueueOrShow("Operational Data Terminal detected: " .. entry.name)
        Core.SetNotified(entry.id)
    end
end

-- Core never draws a mappin for RTC. canMappin is a constant-false gate so Core's
-- SpatialSet.onEnter / Scan / snap-zone all skip CreateMappin entirely.
local function CanMappin()
    return false
end

-- onZoneTick: fires every throttled tick (~1s) while the player is within the
-- detection zone (sized to the live scanner_radius). `entity` is the resolved
-- PerkTraining device, or nil until the game streams it in. The instant it's
-- available and the game hasn't already detected/granted it, trigger the game's
-- OWN detection so its native relic mappin appears at our (wider) range. The
-- WasDetected check makes this idempotent and self-limiting: once SetDeviceAsDetected
-- runs, WasDetected is permanently true and every later tick returns early.
local function TriggerNativeDetection(entry, entity)
    if not entity then return end
    if IsCollected(entry.id) then return end

    local ok, ps = pcall(function() return entity:GetDevicePS() end)
    if not ok or not ps then return end

    local okDet, wasDetected = pcall(function() return ps:WasDetected() end)
    if not okDet then return end
    if wasDetected then return end   -- game already has it; nothing to do

    local okGrant, granted = pcall(function() return ps:IsPerkGranted() end)
    if okGrant and granted then return end   -- already collected

    pcall(function() ps:SetDeviceAsDetected() end)
    pcall(function() entity:TryShowMappin() end)

    if _isDebug then
        local radius = (_settings and _settings.scanner_radius) or 0
        local dist = -1
        pcall(function()
            local p = Game.GetPlayer()
            if p then
                local pp, ep = p:GetWorldPosition(), entity:GetWorldPosition()
                local dx, dy, dz = pp.x - ep.x, pp.y - ep.y, pp.z - ep.z
                dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            end
        end)
        Utils.Log(string.format(
            "[NativeDetect] Triggered game detection for: %s | scanner_radius=%.0fm | dist=%.1fm",
            entry.name, radius, dist), Utils.LogLevel.Debug)
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
    _settings     = settings

    NormaliseEntries()
    BuildHashLookup()

    Core.Init(GetMod("0-Engine"), sessionState, settings, {
        setName       = "rtc_items",
        -- RTC draws no mappin of its own; the game owns the native relic icon.
        noAutoSnap    = true,                  -- no Core entity-snap behaviour
        canMappin     = CanMappin,             -- constant-false: Core never creates a mappin for RTC
        detectionZoneUsesScannerRadius = true, -- detection zone spans the live scanner_radius
        buildEntries  = BuildEntries,
        onItemEnter   = OnItemEnter,           -- notification only
        onZoneTick    = TriggerNativeDetection,-- triggers the game's native detection
        isCollected   = IsCollected,
    }, _isDebug)

    local _, count, total = Core.CheckAllCollected()
    Utils.Log(string.format("Automation Init: %d/%d collected.", count, total))
end

-- ### OBSERVER SETUP ###
-- Called once from init.lua. Installs the activation observer:
--   PerkTrainingControllerPS.TryGrantPerk → instant session-time auto-collect.
-- (No OnAreaEnter observer needed: RTC triggers detection itself via onZoneTick,
-- and the game's own OnAreaEnter still runs natively as a harmless idempotent
-- fallback if the player reaches the real trigger volume first.)

local _observersInstalled = false

local function MatchEntryByHash(hashStr)
    local entry = _hashToEntry[hashStr]
    if entry then return entry end
    -- Defensive: strip ULL suffix for compatibility with formats that drop it
    return _hashToEntry[hashStr:gsub("ULL", "")]
end

function Automation.SetupObservers()
    if _observersInstalled then return end
    _observersInstalled = true

    -- Activation detection: fires when player completes the personal-link interaction.
    ObserveAfter("PerkTrainingControllerPS", "TryGrantPerk", function(this)
        if not _sessionState or not _sessionState.progress then return end

        local pid = this:GetID()
        if not pid then return end
        local entry = MatchEntryByHash(tostring(pid.entityHash))
        if not entry then
            if _isDebug then
                Utils.Log("[Observer] TryGrantPerk fired on unknown hash: " ..
                    tostring(pid.entityHash), Utils.LogLevel.Debug)
            end
            return
        end

        if IsCollected(entry.id) then return end

        Utils.Log("[Observer] Terminal activated: " .. entry.name, Utils.LogLevel.Info)
        Core.SetItemStatus(entry.id, true)
        Utils.Notify("Terminal Data Acquired: " .. entry.name)
    end)

    Utils.Log("Observer installed: TryGrantPerk.")
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
