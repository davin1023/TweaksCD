-- ============================================================================
-- TUI:CD Timeline - Data Layer
-- Cooldown state tracking using isOnGCD + Duration Object pass-through
--
-- GCD FILTER: C_Spell.GetSpellCooldown().isOnGCD (non-secret boolean)
-- STATE: DurationAPI:IsActive() (secret-safe)
-- TIMING: GetTotalDuration()/GetRemainingDuration() cached when non-secret
--         for timeline icon positioning (needs real numbers)
--
-- DATA SOURCE: Reads from MultiTracker entries (which already handles
-- Essential, Utility, and Custom trackers). No duplicate CDM scraping.
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.TimelineData = TUICD.TimelineData or {}
local TimelineData = TUICD.TimelineData

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Minimum remaining time to consider "on cooldown" (avoid float precision issues)
local MIN_REMAINING_SEC = 0.1

-- ============================================================================
-- STATE
-- ============================================================================

-- Tracked spells: { [spellID] = { name, icon, source, trackerKey } }
local trackedSpells = {}

-- Cooldown states: { [spellID] = { isOnCD, remaining, duration, startTime } }
local cooldownStates = {}

-- Absolute timing cache for combat extrapolation
-- When the sensor returns real data, we store the absolute start time so we can
-- extrapolate during combat when Duration Object methods return secrets.
-- { [spellID] = { cdStart = <GetTime when CD started>, cdDuration = <total seconds> } }
local cdTimingCache = {}

-- Persistent cache of each spell's known full cooldown duration (seconds).
-- Populated any time the sensor reads a real CD out of combat.  Survives CD expiry
-- so we can recognize new-in-combat CDs as real (not GCD).
-- { [spellID] = durationSeconds }
local knownFullDurations = {}

-- Callbacks for state changes
local stateCallbacks = {}

-- Debug mode
local debugMode = false

-- ============================================================================
-- DEBUG
-- ============================================================================

local function dprint(...)
    if debugMode then
        print("|cff00ccff[Timeline]|r", ...)
    end
end

function TimelineData:SetDebug(enabled)
    debugMode = enabled
    dprint("Debug mode:", enabled and "ON" or "OFF")
end

function TimelineData:IsDebug()
    return debugMode
end

-- ============================================================================
-- SPELL INFO HELPER (Midnight API compatibility)
-- ============================================================================

-- Safe spell info lookup (handles Midnight's C_Spell.GetSpellInfo which returns a table)
local function SafeGetSpellInfo(spellID)
    if not spellID then return nil, nil end
    
    -- Try SpellAPI first (our wrapper)
    if TUICD.SpellAPI and TUICD.SpellAPI.GetSpellInfo then
        local info = TUICD.SpellAPI:GetSpellInfo(spellID)
        if info then
            local icon = TUICD.SpellAPI:GetSpellTexture(spellID) or info.iconID
            return info.name, icon
        end
    end
    
    -- Try Midnight API (C_Spell.GetSpellInfo returns a table)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            return info.name, info.iconID
        end
    end
    
    return nil, nil
end

-- ============================================================================
-- SPELL TRACKING - Read from MultiTracker
-- ============================================================================

-- Rebuild tracked spell list from MultiTracker entries
function TimelineData:RebuildSpellList()
    wipe(trackedSpells)
    wipe(cooldownStates)
    
    local MultiTracker = TUICD.MultiTracker
    if MultiTracker then
        -- Get all registered trackers
        local trackerList = MultiTracker:GetTrackerList()
        
        for _, tracker in ipairs(trackerList) do
            local trackerKey = tracker.key
            local trackerName = tracker.name
            
            -- Get entries for this tracker (current spec)
            local entries = MultiTracker:GetEntries(trackerKey)
            
            for _, entry in ipairs(entries) do
                -- Only track enabled spell entries (not items)
                if entry.enabled ~= false and entry.type == "spell" and entry.id then
                    local spellID = entry.id
                    
                    -- Don't duplicate if already tracked from another tracker
                    if not trackedSpells[spellID] then
                        -- Look up spell info (entry may not have name/texture)
                        local spellName = entry.name
                        local spellIcon = entry.texture
                        
                        if not spellName or not spellIcon then
                            -- Use safe spell info lookup
                            local name, icon = SafeGetSpellInfo(spellID)
                            spellName = spellName or name
                            spellIcon = spellIcon or icon
                        end
                        
                        trackedSpells[spellID] = {
                            name = spellName or ("Spell " .. spellID),
                            icon = spellIcon,
                            source = tracker.source or "tracker",
                            trackerKey = trackerKey,
                            trackerName = trackerName,
                        }
                    end
                end
            end
        end
    end
    
    -- Also add custom spells from database directly (more reliable than TimelineUI)
    local customSpells = {}
    local DB = TUICD.Database
    
    -- Try TimelineUI first
    local TimelineUI = TUICD.TimelineUI
    if TimelineUI and TimelineUI.GetSetting then
        customSpells = TimelineUI:GetSetting("customSpells") or {}
    end
    
    -- Fallback: try database directly
    if not next(customSpells) and DB and DB.GetModuleSetting then
        customSpells = DB:GetModuleSetting("timeline", "customSpells") or {}
    end
    
    -- Debug: show what we found
    local customCount = 0
    for _ in pairs(customSpells) do customCount = customCount + 1 end
    dprint("Found", customCount, "custom spells in database")
    
    for key, val in pairs(customSpells) do
        -- Handle both numeric and string keys (SavedVariables can convert numeric keys to strings)
        local spellID = tonumber(key)
        if spellID and val and not trackedSpells[spellID] then
            local name, icon = SafeGetSpellInfo(spellID)
            if name then
                trackedSpells[spellID] = {
                    name = name,
                    icon = icon,
                    source = "custom",
                    trackerKey = "custom",
                    trackerName = "Custom",
                    isCustom = true,
                }
                dprint(string.format("Tracking custom: %s (%d)", name, spellID))
            end
        end
    end
    
    local count = 0
    for _ in pairs(trackedSpells) do count = count + 1 end
    dprint("Rebuilt spell list:", count, "spells tracked")
    
    return trackedSpells
end

-- Get current tracked spells
function TimelineData:GetTrackedSpells()
    return trackedSpells
end

-- Get spell info
function TimelineData:GetSpellInfo(spellID)
    return trackedSpells[spellID]
end

-- ============================================================================
-- COOLDOWN STATE DETECTION
-- Core function: uses CooldownFrame sensor to convert secret Duration Objects
-- into readable milliseconds, then filters GCD
-- ============================================================================

function TimelineData:GetCooldownState(spellID)
    if not C_Spell then
        return self:ExtrapolateFromCache(spellID)
    end
    
    -- Step 1: Check isOnGCD (non-secret boolean) — replaces sensor threshold
    local isOnGCD = false
    if C_Spell.GetSpellCooldown then
        pcall(function()
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.isOnGCD then
                isOnGCD = true
            end
        end)
    end
    
    -- If GCD only, not a real cooldown
    if isOnGCD then
        return false, 0, 0
    end
    
    -- Step 2: Get Duration Object
    local dObj
    if C_Spell.GetSpellCooldownDuration then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok then dObj = d end
    end
    
    if not dObj then
        return self:ExtrapolateFromCache(spellID)
    end
    
    -- Step 3: Is it active? (secret-safe)
    local DurationAPI = TUICD.DurationAPI
    local dObjIsActive = false
    if DurationAPI and DurationAPI.IsActive then
        local aOk, aResult = pcall(DurationAPI.IsActive, DurationAPI, dObj)
        dObjIsActive = aOk and aResult
    end
    
    if not dObjIsActive then
        cdTimingCache[spellID] = nil
        return false, 0, 0
    end
    
    -- Step 4: Try to read non-secret remaining/duration from Duration Object
    -- GetTotalDuration() and GetRemainingDuration() return secret values in combat
    local gotTiming = false
    pcall(function()
        local total = dObj:GetTotalDuration()
        local remaining = dObj:GetRemainingDuration()
        if total and remaining
           and type(total) == "number"
           and type(remaining) == "number"
           and not (issecretvalue and issecretvalue(total))
           and not (issecretvalue and issecretvalue(remaining)) then
            -- Non-secret: we can use these directly and cache for combat
            if remaining > MIN_REMAINING_SEC then
                gotTiming = true
                local now = GetTime()
                cdTimingCache[spellID] = {
                    cdStart = now - (total - remaining),
                    cdDuration = total,
                }
                knownFullDurations[spellID] = total
            end
        end
    end)
    
    if gotTiming then
        local cached = cdTimingCache[spellID]
        local remaining = (cached.cdStart + cached.cdDuration) - GetTime()
        return true, remaining, cached.cdDuration
    end
    
    -- Step 5: Secret fallback — try cache extrapolation
    local extraOK, extraRem, extraDur = self:ExtrapolateFromCache(spellID)
    if extraOK then return extraOK, extraRem, extraDur end
    
    -- Step 6: No cache but active — estimate using known duration
    if knownFullDurations[spellID] then
        local fullDur = knownFullDurations[spellID]
        local now = GetTime()
        cdTimingCache[spellID] = {
            cdStart = now,
            cdDuration = fullDur,
        }
        return true, fullDur, fullDur
    end
    
    -- Last resort: active but no timing data
    return true, 0, 0
end

-- Extrapolate cooldown state from cached absolute timing
-- Used when Duration Object values are secret (during combat)
function TimelineData:ExtrapolateFromCache(spellID)
    local cached = cdTimingCache[spellID]
    if not cached then
        return false, 0, 0
    end
    
    local remaining = (cached.cdStart + cached.cdDuration) - GetTime()
    if remaining > MIN_REMAINING_SEC then
        return true, remaining, cached.cdDuration
    else
        -- CD has expired based on timing
        cdTimingCache[spellID] = nil
        return false, 0, 0
    end
end

-- ============================================================================
-- STATE UPDATE
-- Update all tracked spell states and fire callbacks on changes
-- ============================================================================

function TimelineData:UpdateAllStates()
    local changes = {}
    
    for spellID, spellData in pairs(trackedSpells) do
        local isOnCD, remaining, duration = self:GetCooldownState(spellID)
        
        local oldState = cooldownStates[spellID]
        local wasOnCD = oldState and oldState.isOnCD or false
        
        -- Detect state transitions
        if isOnCD ~= wasOnCD then
            changes[spellID] = {
                isOnCD = isOnCD,
                remaining = remaining,
                duration = duration,
                name = spellData.name,
                icon = spellData.icon,
                source = spellData.source,
                trackerKey = spellData.trackerKey,
                transition = isOnCD and "started" or "ended"
            }
            dprint(string.format("%s (%d): %s -> %s (%.1fs remaining)",
                spellData.name, spellID,
                wasOnCD and "ON_CD" or "READY",
                isOnCD and "ON_CD" or "READY",
                remaining))
        end
        
        -- Update state
        cooldownStates[spellID] = {
            isOnCD = isOnCD,
            remaining = remaining,
            duration = duration,
            lastUpdate = GetTime()
        }
    end
    
    -- Fire callbacks for changes
    if next(changes) then
        self:FireStateChanges(changes)
    end
    
    return changes
end

-- Update single spell state
function TimelineData:UpdateSpellState(spellID)
    local spellData = trackedSpells[spellID]
    if not spellData then return nil end
    
    local isOnCD, remaining, duration = self:GetCooldownState(spellID)
    
    local oldState = cooldownStates[spellID]
    local wasOnCD = oldState and oldState.isOnCD or false
    
    cooldownStates[spellID] = {
        isOnCD = isOnCD,
        remaining = remaining,
        duration = duration,
        lastUpdate = GetTime()
    }
    
    -- Return change info if state transitioned
    if isOnCD ~= wasOnCD then
        return {
            spellID = spellID,
            isOnCD = isOnCD,
            remaining = remaining,
            duration = duration,
            name = spellData.name,
            icon = spellData.icon,
            source = spellData.source,
            trackerKey = spellData.trackerKey,
            transition = isOnCD and "started" or "ended"
        }
    end
    
    return nil
end

-- Get current state for a spell
function TimelineData:GetState(spellID)
    return cooldownStates[spellID]
end

-- Get all current states
function TimelineData:GetAllStates()
    return cooldownStates
end

-- Get all spells currently on cooldown
function TimelineData:GetActiveCooldowns()
    local active = {}
    
    -- Get TimelineUI reference for enabled check
    local TimelineUI = TUICD.TimelineUI
    
    for spellID, state in pairs(cooldownStates) do
        if state.isOnCD then
            local spellData = trackedSpells[spellID]
            if spellData then
                -- Check if spell is enabled in UI settings
                local isEnabled = true
                if TimelineUI and TimelineUI.IsSpellEnabled then
                    isEnabled = TimelineUI:IsSpellEnabled(spellID)
                end
                
                if isEnabled then
                    -- Recalculate remaining time (may have changed since last update)
                    local isOnCD, remaining, duration = self:GetCooldownState(spellID)
                    if isOnCD then
                        active[spellID] = {
                            spellID = spellID,
                            name = spellData.name,
                            icon = spellData.icon,
                            source = spellData.source,
                            trackerKey = spellData.trackerKey,
                            remaining = remaining,
                            duration = duration
                        }
                    end
                end
            end
        end
    end
    
    return active
end

-- Get all spells currently ready (not on cooldown)
-- Re-checks spells that cooldownStates thinks are on CD, to catch natural
-- CD expirations that may not yet have triggered SPELL_UPDATE_COOLDOWN
function TimelineData:GetReadySpells()
    local ready = {}
    
    -- Get TimelineUI reference for enabled check
    local TimelineUI = TUICD.TimelineUI
    
    for spellID, state in pairs(cooldownStates) do
        local spellData = trackedSpells[spellID]
        if spellData then
            local isReady = false
            
            if not state.isOnCD then
                -- Already known to be ready
                isReady = true
            else
                -- Cache says on CD - re-check actual state (may have naturally expired)
                local isOnCD, remaining, duration = self:GetCooldownState(spellID)
                if not isOnCD then
                    -- CD expired! Update cached state
                    cooldownStates[spellID] = {
                        isOnCD = false,
                        remaining = 0,
                        duration = duration,
                        lastUpdate = GetTime()
                    }
                    isReady = true
                end
            end
            
            if isReady then
                -- Check if spell is enabled in UI settings
                local isEnabled = true
                if TimelineUI and TimelineUI.IsSpellEnabled then
                    isEnabled = TimelineUI:IsSpellEnabled(spellID)
                end
                
                if isEnabled then
                    ready[spellID] = {
                        spellID = spellID,
                        name = spellData.name,
                        icon = spellData.icon,
                        source = spellData.source,
                        trackerKey = spellData.trackerKey,
                    }
                end
            end
        end
    end
    
    return ready
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

function TimelineData:RegisterCallback(callback)
    table.insert(stateCallbacks, callback)
end

function TimelineData:UnregisterCallback(callback)
    for i, cb in ipairs(stateCallbacks) do
        if cb == callback then
            table.remove(stateCallbacks, i)
            return
        end
    end
end

function TimelineData:FireStateChanges(changes)
    for _, callback in ipairs(stateCallbacks) do
        pcall(callback, changes)
    end
end

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

function TimelineData:DumpTrackedSpells()
    print("|cff00ccff[Timeline]|r Tracked Spells (from MultiTracker):")
    local count = 0
    for spellID, data in pairs(trackedSpells) do
        count = count + 1
        local sourceLabel = data.source or "custom"
        print(string.format("  %d. %s (%d) - %s [%s]", 
            count, data.name, spellID, sourceLabel, data.trackerName or "?"))
    end
    print(string.format("Total: %d spells", count))
end

function TimelineData:DumpCooldownStates()
    print("|cff00ccff[Timeline]|r Cooldown States:")
    local onCD, ready = 0, 0
    
    for spellID, state in pairs(cooldownStates) do
        local spellData = trackedSpells[spellID]
        local name = spellData and spellData.name or "Unknown"
        
        if state.isOnCD then
            onCD = onCD + 1
            print(string.format("  |cffff8800ON CD|r: %s (%d) - %.1fs remaining",
                name, spellID, state.remaining))
        else
            ready = ready + 1
            print(string.format("  |cff00ff00READY|r: %s (%d)", name, spellID))
        end
    end
    
    print(string.format("On Cooldown: %d | Ready: %d", onCD, ready))
end

function TimelineData:TestGCDFilter()
    print("|cff00ccff[Timeline]|r Testing GCD filter on all tracked spells...")
    
    for spellID, data in pairs(trackedSpells) do
        local isOnCD, remaining, duration = self:GetCooldownState(spellID)
        
        local status = isOnCD and "|cffff8800ON CD|r" or "|cff00ff00READY|r"
        
        print(string.format("  %s: %s - remaining: %.1fs, duration: %.1fs",
            data.name, status, remaining, duration))
    end
end

-- ============================================================================
-- RETURN
-- ============================================================================

return TimelineData
