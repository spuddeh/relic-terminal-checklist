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

-- Cached "game has detected this terminal" check. WasDetected is a persistent flag set by
-- the game when the player first crosses a terminal's trigger volume; once true it stays
-- true across save reloads and triggers the game's own native relic mappin permanently.
-- The cache is positive-only (once true, stays true for the session) and is reset in
-- Automation.Init so reloading an earlier save where the terminal hadn't been detected
-- yet doesn't inherit a stale `true` from the OnAreaEnter observer.
local _detectedCache = {}

local function HasGameDetected(entry)
    if _detectedCache[entry.id] then return true end
    local entity = ResolveTerminalEntity(entry)
    if not entity then return false end
    local ok, ps = pcall(function() return entity:GetDevicePS() end)
    if not ok or not ps then return false end
    local okDet, detected = pcall(function() return ps:WasDetected() end)
    if okDet and detected then
        _detectedCache[entry.id] = true
        return true
    end
    return false
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

-- SpatialSet.onEnter (player enters scanner_radius ring): notification only.
-- Always notifies on boundary cross — even after the game's native mappin took over —
-- so the player gets a heads-up they're approaching an unactivated terminal.
-- Mod mappin creation is handled by Core, gated by CanMappin below.
local function OnItemEnter(spatialEntry, _)
    local entry = spatialEntry.dbEntry
    if not Core.IsNotified(entry.id) then
        Core.QueueOrShow("Operational Data Terminal detected: " .. entry.name)
        Core.SetNotified(entry.id)
    end
end

-- canMappin gate: skip mod MAPPIN creation once the game has detected the terminal
-- (m_wasDetected is persistent and triggers the game's own native relic mappin).
-- Without this gate, re-entering scanner range after a trigger crossing produces
-- duplicate icons (mod mappin + native mappin at the same coords). The notification
-- is intentionally NOT gated here — onItemEnter still fires so the player gets a
-- "terminal detected" prompt on re-entry even after the native mappin took over.
local function CanMappin(entry)
    return not HasGameDetected(entry)
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

    -- Reset the positive cache. Lua module state persists across save reloads (only a
    -- full game restart clears it), so without this reset, loading an earlier save
    -- where a terminal hadn't been crossed yet would inherit a stale `true` from the
    -- OnAreaEnter observer and incorrectly suppress the mod mappin. WasDetected on the
    -- entity itself is authoritative — the cache will repopulate on next query if the
    -- save was made after a real detection.
    _detectedCache = {}

    NormaliseEntries()
    BuildHashLookup()

    Core.Init(GetMod("0-Engine"), sessionState, settings, {
        setName       = "rtc_items",
        mappinVariant = gamedataMappinVariant.Zzz16_RelicDeviceBasicVariant,
        -- No snap zone callbacks: per-terminal trigger volumes are observed instead
        -- (ObserveAfter on PerkTraining.OnAreaEnter, installed by Automation.SetupObservers).
        -- Snap zone is registered by Core but is dormant (noAutoSnap, no onSnapEnter/Exit).
        noAutoSnap    = true,
        buildEntries  = BuildEntries,
        canMappin     = CanMappin,       -- mappin-only gate: hides our icon when game's native takes over
        onItemEnter   = OnItemEnter,
        isCollected   = IsCollected,
    }, _isDebug)

    local _, count, total = Core.CheckAllCollected()
    Utils.Log(string.format("Automation Init: %d/%d collected.", count, total))
end

-- ### OBSERVER SETUP ###
-- Called once from init.lua. Installs both Redscript-method observers:
--   1. PerkTrainingControllerPS.TryGrantPerk → activation detection (auto-collect)
--   2. PerkTraining.OnAreaEnter → game's trigger-volume entry (hide mod mappin, native takes over)

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

    -- 1. Activation detection: fires when player completes the personal-link interaction.
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

    -- 2. Game-detected trigger: fires when player crosses the terminal's native trigger volume.
    -- The game sets m_wasDetected = true and shows its own native relic mappin permanently.
    -- We remove ours and flip _detectedCache true so canShow suppresses recreation on
    -- subsequent SpatialSet boundary crosses (otherwise we'd duplicate the native mappin).
    ObserveAfter("PerkTraining", "OnAreaEnter", function(this)
        if not _sessionState or not _sessionState.progress then return end

        local entID = this:GetEntityID()
        if not entID then return end
        local entry = MatchEntryByHash(tostring(entID.hash))
        if not entry then return end
        if IsCollected(entry.id) then return end

        if not _detectedCache[entry.id] then
            _detectedCache[entry.id] = true
            if _isDebug then
                Utils.Log("[Observer] OnAreaEnter for " .. entry.name ..
                    " — game showing native mappin; hiding ours.", Utils.LogLevel.Debug)
            end
        end
        Core.RemoveMappin(entry.id)
    end)

    Utils.Log("Observers installed: TryGrantPerk + OnAreaEnter.")
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
