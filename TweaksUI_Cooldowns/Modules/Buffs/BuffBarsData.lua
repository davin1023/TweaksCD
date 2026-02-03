-- ============================================================================
-- TUICD: Buff Timer Bars - Data Layer
-- Discovers buff slots from Blizzard's Cooldown Manager (BuffIconCooldownViewer)
-- Tracks active/inactive state via auraInstanceID (combat-safe, no secret math)
-- Provides Duration Objects for self-updating timer bars
--
-- KEY SYSTEM: Slot-based barKeys in format "buff:N" where N is CDM icon index
--
-- DETECTION PATTERN (proven in BuffHighlights.lua):
--   Priority 1: C_UnitAuras.GetPlayerAuraBySpellID(spellID)  [direct API]
--   Priority 2: icon.auraInstanceID from CDM frame            [frame property]
--   Duration:   C_UnitAuras.GetUnitAuraDuration("player", auraInstanceID)
--   Stacks:     Deferred to BuffBarsFrames (GetAuraApplicationDisplayCount)
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BuffBarsData = TUICD.BuffBarsData or {}
local BuffBarsData = TUICD.BuffBarsData

local SpellAPI = TUICD.SpellAPI

-- ============================================================================
-- CONSTANTS
-- ============================================================================

BuffBarsData.TYPE_BUFF = "buff"

-- Icon aspect ratios (matches BarsData for visual consistency)
BuffBarsData.ICON_ASPECTS = {
    ["1:1"]  = { w = 1, h = 1 },
    ["4:3"]  = { w = 4, h = 3 },
    ["3:4"]  = { w = 3, h = 4 },
    ["16:9"] = { w = 16, h = 9 },
    ["9:16"] = { w = 9, h = 16 },
    ["2:1"]  = { w = 2, h = 1 },
    ["1:2"]  = { w = 1, h = 2 },
}

-- ============================================================================
-- KEY HELPERS
-- ============================================================================

-- Create bar key from slot index: "buff:3"
function BuffBarsData.MakeBarKey(slotIndex)
    return "buff:" .. tostring(slotIndex)
end

-- Parse bar key -> slotIndex (number), or nil if invalid
function BuffBarsData.ParseBarKey(barKey)
    if not barKey then return nil end
    local idx = barKey:match("^buff:(%d+)$")
    return idx and tonumber(idx) or nil
end

-- Sanitize key for frame naming (e.g. "buff:3" -> "buff_3")
function BuffBarsData.SanitizeKey(barKey)
    return barKey:gsub("[^%w]", "_")
end

function BuffBarsData.TypeLabel()
    return "(Buff)"
end

-- ============================================================================
-- CDM VIEWER DISCOVERY
-- ============================================================================

-- Cached references to CDM buff icon frames
local cdmIcons = {}          -- [slotIndex] = iconFrame
local discoveredSlots = {}   -- [slotIndex] = { slotIndex, spellID, name, texture }
local discoveryDone = false

-- Forward declarations (defined in EVENT HANDLING section below)
local SetupViewerHook
local HookCDMBuffCooldowns

-- Check if a frame looks like a CDM icon (has an Icon texture child)
local function IsCDMIcon(frame)
    if not frame then return false end
    if not frame.GetObjectType then return false end
    local objType = frame:GetObjectType()
    if objType ~= "Frame" and objType ~= "Button" then return false end
    return (frame.Icon or frame.icon) ~= nil
end

-- Collect ordered icons from BuffIconCooldownViewer
local function CollectCDMIcons()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer.GetNumChildren then return {} end

    -- Try the addon's ordered icon helper first (if Cooldowns module has it)
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local ordered = Cooldowns.GetOrderedIcons(viewer, "buffs")
        if ordered and #ordered > 0 then return ordered end
    end

    -- Manual collection from viewer children
    local raw = {}
    for i = 1, (viewer:GetNumChildren() or 0) do
        local child = select(i, viewer:GetChildren())
        if child and IsCDMIcon(child) then
            raw[#raw + 1] = child
        elseif child and child.GetNumChildren then
            -- Check one level of nesting
            for j = 1, (child:GetNumChildren() or 0) do
                local nested = select(j, child:GetChildren())
                if nested and IsCDMIcon(nested) then
                    raw[#raw + 1] = nested
                end
            end
        end
    end

    -- Sort by position: top-to-bottom, left-to-right (stable ordering)
    table.sort(raw, function(a, b)
        local al, at = 0, 0
        local bl, bt = 0, 0
        pcall(function() al = a:GetLeft() or 0 end)
        pcall(function() at = a:GetTop() or 0 end)
        pcall(function() bl = b:GetLeft() or 0 end)
        pcall(function() bt = b:GetTop() or 0 end)
        if math.abs(at - bt) > 5 then return at > bt end
        return al < bl
    end)

    return raw
end

-- Discover all buff slots from CDM, cache static info
-- Should be called outside combat when CDM has populated its icons
function BuffBarsData:DiscoverSlots()
    local icons = CollectCDMIcons()
    if #icons == 0 then
        TUICD:PrintDebug("BuffBarsData: No buff icons found in CDM")
        return 0
    end

    wipe(cdmIcons)
    wipe(discoveredSlots)

    for i, icon in ipairs(icons) do
        cdmIcons[i] = icon

        -- Read static properties (non-secret at config time outside combat)
        local spellID, spellName, texture

        -- Try direct property (Essential/Utility CDM icons have this)
        pcall(function()
            spellID = icon.spellID or icon.SpellID or icon.spellId
        end)

        -- Try GetSpellID method (some CDM icons expose this)
        if not spellID and icon.GetSpellID then
            pcall(function() spellID = icon:GetSpellID() end)
        end

        pcall(function()
            local texObj = icon.Icon or icon.icon
            if texObj then texture = texObj:GetTexture() end
        end)

        -- Determine initial active state via auraInstanceID from icon frame
        local isActive, auraInstanceID = false, nil
        pcall(function()
            auraInstanceID = icon.auraInstanceID
            isActive = (auraInstanceID ~= nil)
        end)

        -- If we have an auraInstanceID, resolve spellID from aura API
        -- This is the primary path for buff icons (which lack .spellID property)
        if auraInstanceID and not spellID and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
            pcall(function()
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
                if auraData then
                    spellID = auraData.spellId
                    if auraData.name then spellName = auraData.name end
                    if auraData.icon then texture = texture or auraData.icon end
                end
            end)
        end

        -- Also try GetPlayerAuraBySpellID if we resolved a spellID
        if spellID and not isActive and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            pcall(function()
                local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
                if auraData then
                    isActive = true
                    auraInstanceID = auraData.auraInstanceID
                end
            end)
        end

        -- Look up spell name via SpellAPI if still missing
        if spellID and not spellName and SpellAPI then
            local info = SpellAPI:GetSpellInfo(spellID)
            if info then spellName = info.name end
            if not texture then
                texture = SpellAPI:GetSpellTexture(spellID)
            end
        end

        discoveredSlots[i] = {
            slotIndex = i,
            spellID = spellID,
            name = spellName or ("Buff Slot " .. i),
            texture = texture,
            isActive = isActive,
            auraInstanceID = auraInstanceID,
        }
    end

    discoveryDone = true

    -- Sync discovered info into saved entries, and persist new discoveries
    local db = self:GetDB()
    db.spells = db.spells or {}

    -- Update existing entries with fresh discovery info
    for barKey, config in pairs(db.spells) do
        local slotIdx = BuffBarsData.ParseBarKey(barKey)
        local slotInfo = slotIdx and discoveredSlots[slotIdx]
        if slotInfo then
            if slotInfo.name and (not config.name or config.name:match("^Buff Slot %d")) then
                config.name = slotInfo.name
            end
            if slotInfo.texture then
                config.texture = slotInfo.texture
                config.iconID = slotInfo.texture
            end
            if slotInfo.spellID then
                config.cachedSpellID = slotInfo.spellID
            end
        end
    end

    -- Persist newly discovered slots (enabled=false) so they survive reloads
    for slotIndex, slotInfo in pairs(discoveredSlots) do
        local barKey = BuffBarsData.MakeBarKey(slotIndex)
        if not db.spells[barKey] then
            db.spells[barKey] = {
                enabled = false,
                name = slotInfo.name or ("Buff Slot " .. slotIndex),
                texture = slotInfo.texture,
                iconID = slotInfo.texture,
                type = BuffBarsData.TYPE_BUFF,
                slotIndex = slotIndex,
                cachedSpellID = slotInfo.spellID,
            }
        end
    end

    TUICD:PrintDebug("BuffBarsData: Discovered " .. #icons .. " buff slot(s)")

    -- Install CDM hooks and viewer hook after every discovery
    SetupViewerHook()
    HookCDMBuffCooldowns()

    return #icons
end

-- Re-discover and remap existing configs if slots shifted (e.g. talent change)
function BuffBarsData:RediscoverSlots()
    -- Remember old spellID -> slotIndex mapping
    local oldMapping = {}
    for idx, info in pairs(discoveredSlots) do
        if info.spellID then
            oldMapping[info.spellID] = idx
        end
    end

    local count = self:DiscoverSlots()

    -- Check for remapping needs
    local db = self:GetDB()
    if not db or not db.spells then return count end

    local remaps = {}
    for newIdx, info in pairs(discoveredSlots) do
        if info.spellID and oldMapping[info.spellID] then
            local oldIdx = oldMapping[info.spellID]
            if oldIdx ~= newIdx then
                remaps[oldIdx] = newIdx
            end
        end
    end

    -- Apply remaps to saved config
    if next(remaps) then
        local newSpells = {}
        for barKey, config in pairs(db.spells) do
            local oldSlot = BuffBarsData.ParseBarKey(barKey)
            if oldSlot and remaps[oldSlot] then
                local newKey = BuffBarsData.MakeBarKey(remaps[oldSlot])
                config.slotIndex = remaps[oldSlot]
                newSpells[newKey] = config
                TUICD:PrintDebug("BuffBarsData: Remapped " .. barKey .. " -> " .. newKey)
            else
                newSpells[barKey] = config
            end
        end
        db.spells = newSpells
    end

    -- Sync name/texture from discovery into saved entries (fixes stale "Buff Slot N" names)
    for barKey, config in pairs(db.spells) do
        local slotIdx = BuffBarsData.ParseBarKey(barKey)
        local slotInfo = slotIdx and discoveredSlots[slotIdx]
        if slotInfo then
            if slotInfo.name and (not config.name or config.name:match("^Buff Slot %d")) then
                config.name = slotInfo.name
            end
            if slotInfo.texture and not config.texture then
                config.texture = slotInfo.texture
                config.iconID = slotInfo.texture
            end
            if slotInfo.spellID and not config.cachedSpellID then
                config.cachedSpellID = slotInfo.spellID
            end
        end
    end

    return count
end

-- Get discovered slot info
function BuffBarsData:GetDiscoveredSlots()
    return discoveredSlots
end

function BuffBarsData:GetDiscoveredSlotCount()
    local count = 0
    for _ in pairs(discoveredSlots) do count = count + 1 end
    return count
end

function BuffBarsData:IsDiscoveryDone()
    return discoveryDone
end

-- Get CDM icon reference for a slot (used by BuffBarsFrames for stack counts)
function BuffBarsData:GetCDMIcon(slotIndex)
    return cdmIcons[slotIndex]
end

-- ============================================================================
-- DATABASE
-- ============================================================================

local DB_DEFAULTS = {
    spells = {},        -- [barKey] = { enabled, name, texture, iconID, ... }
    dockEnabled = false,
    dockSettings = {
        direction = "DOWN",
        spacing = 2,
        barWidth = 200,
        barHeight = 20,
        barTexture = nil,
        barColor = { r = 0.2, g = 0.8, b = 0.2, a = 1.0 },
        backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        showBorder = true,
        showIcon = true,
        iconPosition = "LEFT",
        iconAspect = "1:1",
        iconSizeMode = "auto",
        iconSize = 20,
        showName = true,
        showTime = true,
        nameFontSize = 11,
        timeFontSize = 11,
        font = nil,
        barDirection = "RIGHT",
        fillMode = "drain",
        showWhenReady = false,
        showWhenInactive = false,
        colorByTime = false,
        colorHighSeconds = 10,
        colorMedSeconds = 5,
        colorHigh = { r = 0.2, g = 0.8, b = 0.2 },
        colorMed = { r = 1.0, g = 0.8, b = 0.0 },
        colorLow = { r = 1.0, g = 0.2, b = 0.2 },
        nameOffsetX = 0,
        nameOffsetY = 0,
        timeOffsetX = 0,
        timeOffsetY = 0,
    },
    containerPosition = nil,  -- dock frame position
    positions = {},           -- [barKey] = { point, x, y } for standalone mode
}

-- Deep merge utility for defaults
local function MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                MergeDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            MergeDefaults(target[k], v)
        end
    end
end

function BuffBarsData:GetDB()
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = {}
    end
    if not TweaksUI_Cooldowns_CharDB.buffBars then
        TweaksUI_Cooldowns_CharDB.buffBars = {}
    end

    local db = TweaksUI_Cooldowns_CharDB.buffBars
    MergeDefaults(db, DB_DEFAULTS)
    return db
end

-- ============================================================================
-- SPELL CONFIG (per-slot bar settings)
-- ============================================================================

function BuffBarsData:GetTrackedSpells()
    local db = self:GetDB()
    return db.spells or {}
end

function BuffBarsData:GetSpellConfig(barKey)
    local db = self:GetDB()
    local saved = db.spells and db.spells[barKey]
    if saved then return saved end

    -- Fallback: return discovered slot info (not yet saved)
    local slotIndex = BuffBarsData.ParseBarKey(barKey)
    if slotIndex and discoveredSlots[slotIndex] then
        local slot = discoveredSlots[slotIndex]
        return {
            enabled = false,
            name = slot.name,
            texture = slot.texture,
            iconID = slot.texture,
            type = BuffBarsData.TYPE_BUFF,
            slotIndex = slotIndex,
            cachedSpellID = slot.spellID,
        }
    end
    return nil
end

-- Get effective config: per-spell overrides merged over dock defaults
-- Dock settings are the base, per-spell values override where set
function BuffBarsData:GetEffectiveConfig(barKey)
    local config = self:GetSpellConfig(barKey)
    if not config then return nil end

    local db = self:GetDB()
    local dock = db.dockSettings or {}
    local merged = {}

    -- Start with dock defaults (deep copy tables)
    for k, v in pairs(dock) do
        if type(v) == "table" then
            merged[k] = {}
            for k2, v2 in pairs(v) do merged[k][k2] = v2 end
        else
            merged[k] = v
        end
    end

    -- Overlay per-spell overrides (only keys that exist in config)
    for k, v in pairs(config) do
        if v ~= nil then
            if type(v) == "table" then
                merged[k] = {}
                for k2, v2 in pairs(v) do merged[k][k2] = v2 end
            else
                merged[k] = v
            end
        end
    end

    return merged
end

-- Enable a discovered slot for bar display
function BuffBarsData:EnableSlot(slotIndex, enabled)
    local barKey = BuffBarsData.MakeBarKey(slotIndex)
    local db = self:GetDB()
    db.spells = db.spells or {}

    if enabled then
        if db.spells[barKey] then
            -- Entry already exists (persisted from discovery) - just enable it
            db.spells[barKey].enabled = true
        else
            -- Need discovery info to create new entry
            local slotInfo = discoveredSlots[slotIndex]
            if not slotInfo then return nil end
            db.spells[barKey] = {
                enabled = true,
                name = slotInfo.name,
                texture = slotInfo.texture,
                iconID = slotInfo.texture,
                type = BuffBarsData.TYPE_BUFF,
                slotIndex = slotIndex,
                cachedSpellID = slotInfo.spellID,
            }
        end

        -- Start poll if not running
        if not self:IsPollRunning() then self:StartPoll() end

        self:FireUpdate(barKey)
        return barKey
    else
        if db.spells[barKey] then
            db.spells[barKey].enabled = false
            self:FireUpdate(barKey)
        end
        return barKey
    end
end

-- Remove a slot config entirely
function BuffBarsData:RemoveSlot(barKey)
    local db = self:GetDB()
    if db.spells then
        db.spells[barKey] = nil
    end
    if db.positions then
        db.positions[barKey] = nil
    end
    spellStates[barKey] = nil
    self:FireUpdate(barKey)
end

-- Set per-spell setting override
function BuffBarsData:SetSpellSetting(barKey, key, value)
    local db = self:GetDB()
    db.spells = db.spells or {}

    -- Auto-create entry from discovered slot if needed
    if not db.spells[barKey] then
        local slotIndex = BuffBarsData.ParseBarKey(barKey)
        local slotInfo = slotIndex and discoveredSlots[slotIndex]
        if slotInfo then
            db.spells[barKey] = {
                enabled = false,
                name = slotInfo.name,
                texture = slotInfo.texture,
                iconID = slotInfo.texture,
                type = BuffBarsData.TYPE_BUFF,
                slotIndex = slotIndex,
                cachedSpellID = slotInfo.spellID,
            }
        else
            return  -- No discovered slot, can't create
        end
    end

    db.spells[barKey][key] = value
end

-- Get per-spell setting
function BuffBarsData:GetSpellSetting(barKey, key)
    local config = self:GetSpellConfig(barKey)
    return config and config[key]
end

-- ============================================================================
-- DOCK SETTINGS
-- ============================================================================

function BuffBarsData:IsDockEnabled()
    local db = self:GetDB()
    return db.dockEnabled ~= false
end

function BuffBarsData:SetDockEnabled(enabled)
    local db = self:GetDB()
    db.dockEnabled = enabled
end

function BuffBarsData:GetDockSetting(key)
    local db = self:GetDB()
    return db.dockSettings and db.dockSettings[key]
end

function BuffBarsData:GetDockSettings()
    local db = self:GetDB()
    return db.dockSettings or {}
end

function BuffBarsData:SetDockSetting(key, value)
    local db = self:GetDB()
    db.dockSettings = db.dockSettings or {}
    db.dockSettings[key] = value
end

-- ============================================================================
-- POSITION PERSISTENCE
-- ============================================================================

function BuffBarsData:GetSpellPosition(barKey)
    local db = self:GetDB()
    return db.positions and db.positions[barKey]
end

function BuffBarsData:SetSpellPosition(barKey, point, x, y)
    local db = self:GetDB()
    db.positions = db.positions or {}
    db.positions[barKey] = { point = point, x = x, y = y }
end

-- ============================================================================
-- SPELL LIST (for UI display)
-- ============================================================================

function BuffBarsData:GetSpellList()
    local list = {}
    local db = self:GetDB()
    local seen = {}

    -- First: entries already in saved config
    for barKey, config in pairs(db.spells or {}) do
        local slotIndex = BuffBarsData.ParseBarKey(barKey)
        seen[slotIndex] = true
        list[#list + 1] = {
            barKey = barKey,
            slotIndex = slotIndex,
            name = config.name or ("Buff Slot " .. (slotIndex or "?")),
            displayName = (config.name or ("Buff Slot " .. (slotIndex or "?")))
                          .. " " .. BuffBarsData.TypeLabel(),
            enabled = config.enabled,
            texture = config.texture or config.iconID,
            cachedSpellID = config.cachedSpellID,
        }
    end

    -- Second: discovered slots not yet saved (show as disabled)
    for slotIndex, slotInfo in pairs(discoveredSlots) do
        if not seen[slotIndex] then
            list[#list + 1] = {
                barKey = BuffBarsData.MakeBarKey(slotIndex),
                slotIndex = slotIndex,
                name = slotInfo.name or ("Buff Slot " .. slotIndex),
                displayName = (slotInfo.name or ("Buff Slot " .. slotIndex))
                              .. " " .. BuffBarsData.TypeLabel(),
                enabled = false,
                texture = slotInfo.texture,
                cachedSpellID = slotInfo.spellID,
            }
        end
    end

    table.sort(list, function(a, b)
        return (a.slotIndex or 0) < (b.slotIndex or 0)
    end)
    return list
end

function BuffBarsData:GetSpellCount()
    local count = 0
    local db = self:GetDB()
    for _, config in pairs(db.spells or {}) do
        if config.enabled then count = count + 1 end
    end
    return count
end

-- ============================================================================
-- STATE MANAGEMENT (combat-safe via auraInstanceID)
-- ============================================================================

local spellStates = {}  -- [barKey] = { type, isActive, duration, expirationTime, auraInstanceID }

function BuffBarsData:GetSpellState(barKey)
    return spellStates[barKey]
end

-- Update state for a single buff slot
-- Detection approach:
--   Priority 1: C_UnitAuras.GetPlayerAuraBySpellID (direct API, fastest)
--   Priority 2: icon.auraInstanceID (CDM frame property, always available)
-- Duration: C_UnitAuras.GetUnitAuraDuration("player", auraInstanceID)
--
-- Returns true if state changed (active/inactive toggle or auraInstanceID change)
function BuffBarsData:UpdateSlotState(barKey)
    local config = self:GetSpellConfig(barKey)
    if not config or not config.enabled then return false end

    local slotIndex = BuffBarsData.ParseBarKey(barKey)
    if not slotIndex then return false end

    local sourceIcon = cdmIcons[slotIndex]
    
    -- Debug output when debugMode is on
    local debug = TUICD.debugMode
    if debug then
        print(string.format("[BuffBar] UpdateSlotState %s: slotIndex=%d, sourceIcon=%s, cachedSpellID=%s",
            barKey, slotIndex, tostring(sourceIcon ~= nil), tostring(config.cachedSpellID)))
    end

    local state = spellStates[barKey]
    if not state then
        state = { type = BuffBarsData.TYPE_BUFF, isActive = false }
        spellStates[barKey] = state
    end

    local wasActive = state.isActive
    local prevAuraID = state.auraInstanceID
    local isActive = false
    local auraInstanceID = nil
    local durationObj = nil

    -- Priority 1: Query aura API directly by spellID (bypasses frame lag)
    local spellID = config.cachedSpellID
    if spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        pcall(function()
            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if auraData then
                isActive = true
                auraInstanceID = auraData.auraInstanceID
                if debug then
                    print(string.format("[BuffBar]   Priority1 HIT: spellID=%d, auraInstanceID=%s", spellID, tostring(auraInstanceID)))
                end
            elseif debug then
                print(string.format("[BuffBar]   Priority1 MISS: spellID=%d not active", spellID))
            end
        end)
    elseif debug then
        print("[BuffBar]   Priority1 SKIP: no cachedSpellID or API missing")
    end

    -- Priority 2: Fallback to CDM icon auraInstanceID
    if not isActive and sourceIcon then
        pcall(function()
            auraInstanceID = sourceIcon.auraInstanceID
            isActive = (auraInstanceID ~= nil)
            if debug then
                print(string.format("[BuffBar]   Priority2: sourceIcon.auraInstanceID=%s, isActive=%s",
                    tostring(auraInstanceID), tostring(isActive)))
            end
        end)
    elseif not isActive and debug then
        print("[BuffBar]   Priority2 SKIP: no sourceIcon")
    end

    -- If active with auraInstanceID but no cached spellID, resolve it now
    -- CDM buff icons don't store .spellID, so we resolve lazily from aura data
    if isActive and auraInstanceID and not spellID then
        if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
            pcall(function()
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
                if auraData then
                    if auraData.spellId then
                        config.cachedSpellID = auraData.spellId
                        -- Also update display name if we only had "Buff Slot N"
                        if auraData.name and config.name and config.name:match("^Buff Slot %d+$") then
                            config.name = auraData.name
                            -- Update discovered slot info too
                            local slotInfo = discoveredSlots[slotIndex]
                            if slotInfo then
                                slotInfo.spellID = auraData.spellId
                                slotInfo.name = auraData.name
                            end
                        end
                    end
                    if auraData.icon and (not config.texture or config.texture == nil) then
                        config.texture = auraData.icon
                        config.iconID = auraData.icon
                    end
                end
            end)
        end
    end

    -- Get timing data for bar rendering
    -- PRIORITY: GetCooldownTimes() first (returns non-secret milliseconds usable in combat)
    -- FALLBACK: Aura API (may return secrets in combat)
    local duration, expirationTime
    local durationMs, startMs  -- non-secret milliseconds for color-by-time
    
    if isActive then
        -- Method 1: CDM cooldown frame GetCooldownTimes() - returns non-secret milliseconds
        -- This is the ONLY reliable source for color-by-time in combat
        if sourceIcon then
            local sourceCooldown = sourceIcon.Cooldown or sourceIcon.cooldown
            if sourceCooldown and sourceCooldown.GetCooldownTimes then
                pcall(function()
                    local sMs, dMs = sourceCooldown:GetCooldownTimes()
                    if dMs and type(dMs) == "number" and dMs > 0 then
                        startMs = sMs
                        durationMs = dMs
                        duration = dMs / 1000
                        expirationTime = (sMs + dMs) / 1000
                    end
                end)
            end
        end
        
        -- Method 2: Aura API fallback (for buffs without CDM icons, or if Method 1 failed)
        if not duration and auraInstanceID then
            if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
                pcall(function()
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
                    if auraData then
                        -- Only use if we get actual numbers (not secrets)
                        if auraData.duration and type(auraData.duration) == "number" and auraData.duration > 0 then
                            duration = auraData.duration
                            durationMs = auraData.duration * 1000
                        end
                        if auraData.expirationTime and type(auraData.expirationTime) == "number" and auraData.expirationTime > 0 then
                            expirationTime = auraData.expirationTime
                            startMs = (auraData.expirationTime - auraData.duration) * 1000
                        end
                    end
                end)
            end
        end
    end

    -- Refresh cached texture if icon changed
    if isActive and sourceIcon then
        pcall(function()
            local texObj = sourceIcon.Icon or sourceIcon.icon
            if texObj then
                local tex = texObj:GetTexture()
                if tex then
                    config.texture = tex
                    config.iconID = tex
                end
            end
        end)
    end

    -- Detect state changes: active/inactive toggle OR buff refresh (new auraInstanceID or expirationTime)
    local prevExpiration = state.expirationTime
    local expirationChanged = false
    
    -- Detect expirationTime change (buff refresh) - only if both values are numbers
    if isActive and expirationTime and prevExpiration then
        -- If expiration jumped forward by more than 0.5s, it's a refresh
        if type(expirationTime) == "number" and type(prevExpiration) == "number" then
            if expirationTime > prevExpiration + 0.5 then
                expirationChanged = true
                print("[BuffBar] Buff refresh detected: " .. tostring(barKey) .. " expiration " .. tostring(prevExpiration) .. " -> " .. tostring(expirationTime))
            end
        end
    end
    
    local stateChanged = (wasActive ~= isActive) or (prevAuraID ~= auraInstanceID) or expirationChanged

    state.isActive = isActive
    state.duration = duration
    state.expirationTime = expirationTime
    state.auraInstanceID = auraInstanceID
    -- Store non-secret milliseconds for color-by-time (like Bars module does)
    state.startMs = isActive and startMs or nil
    state.durationMs = isActive and durationMs or nil

    return stateChanged
end

-- Update all tracked buff states, fire callbacks for changes
-- Used by poll (only fires on actual changes for efficiency)
function BuffBarsData:UpdateAll()
    for barKey, config in pairs(self:GetTrackedSpells()) do
        if config.enabled then
            local changed = self:UpdateSlotState(barKey)
            if changed then
                self:FireUpdate(barKey)
            end
        end
    end
end

-- Update + always fire (used by CDM hooks for instant response)
function BuffBarsData:UpdateAndFire(barKey)
    self:UpdateSlotState(barKey)
    self:FireUpdate(barKey)
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

local updateCallbacks = {}

function BuffBarsData:RegisterUpdateCallback(id, callback)
    updateCallbacks[id] = callback
end

function BuffBarsData:UnregisterUpdateCallback(id)
    updateCallbacks[id] = nil
end

function BuffBarsData:FireUpdate(barKey)
    for _, cb in pairs(updateCallbacks) do
        pcall(cb, barKey)
    end
end

-- ============================================================================
-- EVENT HANDLING + CDM HOOKS
-- ============================================================================

local eventFrame = CreateFrame("Frame")
local hookedCooldowns = {}  -- [cooldownFrame] = true (prevent double-hooking)
local hookSetupDone = false

-- Hook CDM icon cooldowns to get instant updates when Blizzard updates them
-- Hooks fire on SetCooldownFromDurationObject, SetCooldown, and Clear
HookCDMBuffCooldowns = function()
    for slotIndex, icon in pairs(cdmIcons) do
        local sourceCooldown = icon.Cooldown or icon.cooldown
        if sourceCooldown and not hookedCooldowns[sourceCooldown] then
            hookedCooldowns[sourceCooldown] = true
            sourceCooldown._TUICD_BuffBar_SlotIndex = slotIndex

            -- Hook SetCooldownFromDurationObject (Midnight primary method)
            if sourceCooldown.SetCooldownFromDurationObject then
                hooksecurefunc(sourceCooldown, "SetCooldownFromDurationObject", function(self)
                    local slot = self._TUICD_BuffBar_SlotIndex
                    if slot then
                        BuffBarsData:UpdateAndFire(BuffBarsData.MakeBarKey(slot))
                    end
                end)
            end

            -- Hook SetCooldown (traditional method)
            hooksecurefunc(sourceCooldown, "SetCooldown", function(self)
                local slot = self._TUICD_BuffBar_SlotIndex
                if slot then
                    BuffBarsData:UpdateAndFire(BuffBarsData.MakeBarKey(slot))
                end
            end)

            -- Hook Clear (buff expired)
            hooksecurefunc(sourceCooldown, "Clear", function(self)
                local slot = self._TUICD_BuffBar_SlotIndex
                if slot then
                    BuffBarsData:UpdateAndFire(BuffBarsData.MakeBarKey(slot))
                end
            end)
        else
            -- Update slot index in case icons reordered
            if sourceCooldown then
                sourceCooldown._TUICD_BuffBar_SlotIndex = slotIndex
            end
        end
    end
end

-- Hook CDM viewer layout to catch icon additions/removals
SetupViewerHook = function()
    if hookSetupDone then return end

    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then return end

    hookSetupDone = true

    if viewer.Layout then
        hooksecurefunc(viewer, "Layout", function()
            -- Defer to next frame (CDM children may not be ready yet)
            C_Timer.After(0, function()
                BuffBarsData:RediscoverSlots()
                HookCDMBuffCooldowns()
                BuffBarsData:UpdateAll()
            end)
        end)
    end

    TUICD:PrintDebug("BuffBarsData: Hooked BuffIconCooldownViewer.Layout")
end

-- ============================================================================
-- SAFETY-NET POLL (0.25s interval, same as BuffHighlights)
-- Only fires callbacks on actual state changes (via UpdateAll)
-- ============================================================================

local POLL_INTERVAL = 0.25
local pollElapsed = 0
local pollFrame = CreateFrame("Frame")
local pollRunning = false

function BuffBarsData:StartPoll()
    if pollRunning then return end
    pollRunning = true
    pollFrame:SetScript("OnUpdate", function(_, elapsed)
        pollElapsed = pollElapsed + elapsed
        if pollElapsed >= POLL_INTERVAL then
            pollElapsed = 0
            pcall(BuffBarsData.UpdateAll, BuffBarsData)
        end
    end)
    TUICD:PrintDebug("BuffBarsData: Poll started (0.25s)")
end

function BuffBarsData:StopPoll()
    if not pollRunning then return end
    pollRunning = false
    pollFrame:SetScript("OnUpdate", nil)
    TUICD:PrintDebug("BuffBarsData: Poll stopped")
end

function BuffBarsData:IsPollRunning()
    return pollRunning
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function BuffBarsData:RegisterEvents()
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    local self_ref = self

    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            -- Delayed discovery: CDM needs time to populate icons (~2s)
            C_Timer.After(2.0, function()
                self_ref:DiscoverSlots()
                SetupViewerHook()
                HookCDMBuffCooldowns()

                -- Start poll if we have any enabled bars
                if self_ref:GetSpellCount() > 0 then
                    self_ref:StartPoll()
                end

                -- Initial state update (slightly delayed for CDM readiness)
                C_Timer.After(0.5, function()
                    self_ref:UpdateAll()
                    -- Fire all enabled bars to ensure frames get initial state
                    for barKey, config in pairs(self_ref:GetTrackedSpells()) do
                        if config.enabled then
                            self_ref:FireUpdate(barKey)
                        end
                    end
                end)
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- After combat: full refresh (some aura state may have changed)
            C_Timer.After(0, function()
                self_ref:UpdateAll()
            end)
        end
    end)
end

function BuffBarsData:UnregisterEvents()
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    self:StopPoll()
end

-- Initialize the data layer (called from BuffBars:OnInitialize)
function BuffBarsData:Initialize()
    -- Nothing critical here - discovery happens via PLAYER_ENTERING_WORLD
    -- But we can do early setup
    TUICD:PrintDebug("BuffBarsData:Initialize() called")
end

-- Immediate startup when module is enabled after player is already logged in
-- This bypasses waiting for PLAYER_ENTERING_WORLD which has already fired
function BuffBarsData:ImmediateStartup()
    TUICD:PrintDebug("BuffBarsData:ImmediateStartup() - player already in world")
    
    -- Discovery: find CDM buff icons
    self:DiscoverSlots()
    
    -- Setup hooks for instant updates
    SetupViewerHook()
    HookCDMBuffCooldowns()
    
    -- Initial state update
    self:UpdateAll()
    
    -- Fire updates for all enabled bars
    for barKey, config in pairs(self:GetTrackedSpells()) do
        if config.enabled then
            self:FireUpdate(barKey)
        end
    end
    
    -- Start poll if we have enabled bars
    if self:GetSpellCount() > 0 then
        self:StartPoll()
    end
end

-- Debug: Force a full refresh (useful for testing)
function BuffBarsData:ForceRefresh()
    TUICD:Print("[BuffBarsData] Force refresh:")
    TUICD:Print("  cdmIcons count: " .. tostring(#cdmIcons > 0 and #cdmIcons or "0 (using pairs)"))
    local iconCount = 0
    for _ in pairs(cdmIcons) do iconCount = iconCount + 1 end
    TUICD:Print("  cdmIcons actual: " .. iconCount)
    
    -- Do discovery
    local discovered = self:DiscoverSlots()
    TUICD:Print("  Discovered slots: " .. discovered)
    
    -- Setup hooks
    SetupViewerHook()
    HookCDMBuffCooldowns()
    
    -- Update all
    for barKey, config in pairs(self:GetTrackedSpells()) do
        if config.enabled then
            TUICD:Print("  Updating bar: " .. barKey)
            self:UpdateSlotState(barKey)
            self:FireUpdate(barKey)
        end
    end
    
    -- Report state
    for barKey, config in pairs(self:GetTrackedSpells()) do
        if config.enabled then
            local state = self:GetSpellState(barKey)
            local status = state and state.isActive and "|cff00ff00ACTIVE|r" or "|cffff0000inactive|r"
            local auraID = state and state.auraInstanceID or "nil"
            TUICD:Print(string.format("  %s: %s (auraID=%s)", barKey, status, tostring(auraID)))
        end
    end
    
    -- Start poll if needed
    if not self:IsPollRunning() then
        self:StartPoll()
        TUICD:Print("  Started poll")
    else
        TUICD:Print("  Poll already running")
    end
end

-- ============================================================================
-- SLASH COMMAND HELPERS (for testing/debugging)
-- ============================================================================

function BuffBarsData:HandleSlashCommand(args)
    if not args or args == "" then
        self:PrintStatus()
        return
    end

    local cmd, arg1 = strsplit(" ", args, 2)
    cmd = cmd and cmd:lower() or ""

    if cmd == "discover" then
        local count = self:DiscoverSlots()
        TUICD:Print("Buff discovery: found " .. count .. " slot(s)")
        for idx, info in pairs(discoveredSlots) do
            local status = info.isActive and "|cff00ff00ACTIVE|r" or "|cff888888inactive|r"
            print(string.format("  [%d] %s (ID:%s) %s",
                idx,
                info.name or "?",
                tostring(info.spellID or "?"),
                status
            ))
        end

    elseif cmd == "list" then
        local list = self:GetSpellList()
        if #list == 0 then
            TUICD:Print("No buff bars configured.")
        else
            TUICD:Print("Buff Bars (" .. #list .. " entries):")
            for _, entry in ipairs(list) do
                local state = self:GetSpellState(entry.barKey)
                local status = (state and state.isActive)
                    and "|cff00ff00ACTIVE|r" or "|cff888888inactive|r"
                local enabled = entry.enabled
                    and "|cff00ff00ON|r" or "|cffff0000OFF|r"
                print(string.format("  %s [%s] %s - %s",
                    enabled, entry.barKey, entry.name, status
                ))
            end
        end

    elseif cmd == "enable" then
        local slot = tonumber(arg1)
        if not slot then
            TUICD:Print("Usage: /tuicd buffbars enable <slotNumber>")
            return
        end
        local barKey = self:EnableSlot(slot, true)
        if barKey then
            local info = discoveredSlots[slot]
            TUICD:Print("Enabled buff bar: " .. (info and info.name or ("Slot " .. slot)))
        else
            TUICD:Print("Slot " .. slot .. " not found. Run 'discover' first.")
        end

    elseif cmd == "disable" then
        local slot = tonumber(arg1)
        if not slot then
            TUICD:Print("Usage: /tuicd buffbars disable <slotNumber>")
            return
        end
        self:EnableSlot(slot, false)
        TUICD:Print("Disabled buff bar slot " .. slot)

    elseif cmd == "state" then
        -- Force a fresh update before showing state
        self:UpdateAll()
        TUICD:Print("Buff bar states:")
        for barKey, state in pairs(spellStates) do
            local config = self:GetSpellConfig(barKey)
            local spellStr = config and config.cachedSpellID and tostring(config.cachedSpellID) or "nil"
            local nameStr = config and config.name or "?"
            local durStr = state.duration and string.format("%.1fs", state.duration) or "nil"
            local remStr = "n/a"
            if state.expirationTime and state.isActive then
                local rem = state.expirationTime - GetTime()
                remStr = rem > 0 and string.format("%.1fs", rem) or "expired"
            end
            print(string.format("  %s [%s] (spell:%s): active=%s auraID=%s dur=%s rem=%s",
                barKey, nameStr, spellStr,
                tostring(state.isActive),
                tostring(state.auraInstanceID or "nil"),
                durStr, remStr
            ))
        end

    elseif cmd == "probe" then
        -- Deep diagnostic: dump everything about a slot's CDM icon
        local slot = tonumber(arg1) or 1
        local icon = cdmIcons[slot]
        if not icon then
            TUICD:Print("No CDM icon at slot " .. slot .. ". Run 'discover' first.")
            return
        end

        TUICD:Print("=== Probe Buff Slot " .. slot .. " ===")
        print("|cffff9900Frame:|r " .. tostring(icon:GetName() or "unnamed"))

        -- SpellID properties
        print("|cffff9900SpellID props:|r")
        local sid = nil
        pcall(function() sid = icon.spellID end)
        print("  .spellID: " .. tostring(sid))
        if icon.GetSpellID then
            local ok, val = pcall(function() return icon:GetSpellID() end)
            print("  :GetSpellID(): " .. (ok and tostring(val) or ("err: " .. tostring(val))))
        end

        -- auraInstanceID
        local aid = nil
        pcall(function() aid = icon.auraInstanceID end)
        print("|cffff9900auraInstanceID:|r " .. tostring(aid))

        -- Texture
        local tex = nil
        pcall(function()
            local t = icon.Icon or icon.icon
            if t then tex = t:GetTexture() end
        end)
        print("|cffff9900Texture:|r " .. tostring(tex))

        -- Aura data from API
        if aid then
            print("|cffff9900GetAuraDataByAuraInstanceID:|r")
            local ok, err = pcall(function()
                local ad = C_UnitAuras.GetAuraDataByAuraInstanceID("player", aid)
                if ad then
                    print("  name=" .. tostring(ad.name) .. " spellId=" .. tostring(ad.spellId))
                    print("  duration=" .. tostring(ad.duration) .. " expTime=" .. tostring(ad.expirationTime))
                    print("  icon=" .. tostring(ad.icon) .. " applications=" .. tostring(ad.applications))
                else
                    print("  (returned nil)")
                end
            end)
            if not ok then print("  ERROR: " .. tostring(err)) end
        end

        -- Duration Object
        if aid then
            print("|cffff9900GetUnitAuraDuration:|r")
            if C_UnitAuras and C_UnitAuras.GetUnitAuraDuration then
                local ok, result = pcall(function()
                    return C_UnitAuras.GetUnitAuraDuration("player", aid)
                end)
                if ok and result then
                    print("  returned: " .. tostring(result) .. " type=" .. type(result))
                elseif ok then
                    print("  returned nil")
                else
                    print("  ERROR: " .. tostring(result))
                end
            else
                print("  (API not available)")
            end
        end

        -- Cooldown frame
        local cd = icon.Cooldown or icon.cooldown
        print("|cffff9900Cooldown frame:|r " .. tostring(cd))
        if cd then
            if cd.GetCooldownDuration then
                local ok, val = pcall(function() return cd:GetCooldownDuration() end)
                print("  :GetCooldownDuration(): " .. (ok and tostring(val) or ("err: " .. tostring(val))))
            end
            if cd.GetCooldownTimes then
                local ok, s, d = pcall(function() return cd:GetCooldownTimes() end)
                if ok then
                    print("  :GetCooldownTimes(): start=" .. tostring(s) .. " dur=" .. tostring(d))
                end
            end
        end

    elseif cmd == "poll" then
        if self:IsPollRunning() then
            TUICD:Print("Poll: |cff00ff00RUNNING|r (0.25s)")
        else
            TUICD:Print("Poll: |cff888888STOPPED|r")
        end

    elseif cmd == "colortime" or cmd == "colorbytime" then
        -- Toggle colorByTime setting
        local db = self:GetDB()
        local settings = db.dockSettings
        settings.colorByTime = not settings.colorByTime
        TUICD:Print("Color by time: " .. (settings.colorByTime and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        TUICD:Print("  High: " .. (settings.colorHighSeconds or 10) .. "s (green)")
        TUICD:Print("  Med:  " .. (settings.colorMedSeconds or 5) .. "s (yellow)")
        TUICD:Print("  Below med = red")
        -- Clear curve cache so new colors take effect
        if TUICD.BuffBarsFrames and TUICD.BuffBarsFrames.ClearColorCurveCache then
            TUICD.BuffBarsFrames.ClearColorCurveCache()
        end
        -- Force refresh all bars
        for barKey in pairs(spellStates) do
            self:FireUpdate(barKey)
        end

    elseif cmd == "layout" or cmd == "show" or cmd == "hide" then
        -- Forward to BuffBarsFrames
        local frames = TUICD.BuffBarsFrames
        if frames then
            frames:HandleSlashCommand(cmd)
        else
            TUICD:PrintError("BuffBarsFrames not loaded")
        end

    else
        TUICD:Print("Buff Bars commands:")
        print("  discover  - Scan CDM for buff icons")
        print("  list      - Show configured buff bars")
        print("  enable N  - Enable slot N as a bar")
        print("  disable N - Disable slot N")
        print("  state     - Show current bar states")
        print("  probe N   - Deep diagnostic for slot N")
        print("  poll      - Show poll status")
        print("  colortime - Toggle color-by-time (green->yellow->red)")
        print("  layout    - Toggle layout/drag mode")
        print("  show      - Force show all bars (debug)")
        print("  hide      - Hide all bars")
    end
end

function BuffBarsData:PrintStatus()
    local discovered = self:GetDiscoveredSlotCount()
    local enabled = self:GetSpellCount()
    local polling = self:IsPollRunning()
    TUICD:Print(string.format("Buff Bars: %d discovered, %d enabled, poll %s",
        discovered, enabled, polling and "ON" or "OFF"
    ))
end

return BuffBarsData
