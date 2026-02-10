-- ============================================================================
-- TUICD: Buff Timer Bars - Data Layer
-- Discovers buff slots from Blizzard's Cooldown Manager (BuffIconCooldownViewer)
-- Tracks active/inactive state via BuffIdentityBridge (combat-safe, no secret math)
-- Provides Duration Objects for self-updating timer bars
--
-- KEY SYSTEM (v3.2.0): SpellID-based barKeys in format "buff:SPELLID"
--   e.g. "buff:203819" for Demon Spikes
--   Legacy "buff:N" (slotIndex) keys migrated automatically on first load
--
-- DETECTION PATTERN:
--   Priority 1: BuffIdentityBridge (combat-safe, never secret)
--   Priority 2: C_UnitAuras.GetPlayerAuraBySpellID (direct API, outside combat)
--   Priority 3: icon.auraInstanceID from CDM frame (frame property)
--   Duration:   C_UnitAuras.GetAuraDataByAuraInstanceID for timing
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
-- KEY HELPERS (v3.2.0: spellID-based keys)
-- ============================================================================

-- Create bar key from spellID (preferred) or slotIndex (legacy fallback)
-- Format: "buff:203819" (spellID) or "buff:3" (legacy slotIndex)
function BuffBarsData.MakeBarKey(identifier)
    return "buff:" .. tostring(identifier)
end

-- Create bar key from a slotIndex, resolving through Bridge to get spellID
function BuffBarsData.MakeBarKeyFromSlot(slotIndex)
    local Bridge = TUICD.BuffIdentityBridge
    if Bridge then
        local spellID = Bridge:GetSpellIDForSlot(slotIndex)
        if spellID then return "buff:" .. tostring(spellID) end
    end
    return "buff:" .. tostring(slotIndex)
end

-- Parse bar key -> the numeric identifier (spellID or legacy slotIndex)
function BuffBarsData.ParseBarKey(barKey)
    if not barKey then return nil end
    local idx = barKey:match("^buff:(%d+)$")
    return idx and tonumber(idx) or nil
end

-- Check if a barKey contains a spellID (> 100) vs a legacy slotIndex (1-20)
function BuffBarsData.IsSpellIDBarKey(barKey)
    local id = BuffBarsData.ParseBarKey(barKey)
    return id and id > 100
end

-- Get slotIndex for a barKey (resolves spellID keys through Bridge)
function BuffBarsData.GetSlotIndexForBarKey(barKey)
    local id = BuffBarsData.ParseBarKey(barKey)
    if not id then return nil end
    if id <= 100 then return id end  -- Already a slotIndex
    -- It's a spellID — resolve to current slot via Bridge
    local Bridge = TUICD.BuffIdentityBridge
    if Bridge then
        return Bridge:GetSlotForSpellID(id)
    end
    return nil
end

-- Sanitize key for frame naming (e.g. "buff:203819" -> "buff_203819")
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

    local Bridge = TUICD.BuffIdentityBridge

    for i, icon in ipairs(icons) do
        cdmIcons[i] = icon

        local spellID, spellName, texture
        local isActive = false
        local auraInstanceID = nil

        -- PRIORITY 1: Use BuffIdentityBridge (combat-safe, always non-secret)
        if Bridge then
            spellID = Bridge:GetSpellIDForSlot(i)
            if spellID then
                local bridgeInfo = Bridge:GetBuffInfo(spellID)
                if bridgeInfo then
                    spellName = bridgeInfo.name
                    texture = bridgeInfo.icon
                end
                isActive = Bridge:IsBuffActive(spellID) or false
                auraInstanceID = Bridge:GetAuraIDForSpellID(spellID)
            end
        end

        -- PRIORITY 2: Fallback - read icon properties directly (outside combat only)
        if not spellID then
            pcall(function()
                spellID = icon.spellID or icon.SpellID or icon.spellId
            end)
            if not spellID and icon.GetSpellID then
                pcall(function() spellID = icon:GetSpellID() end)
            end
        end

        -- Get texture from icon frame if Bridge didn't provide it
        if not texture then
            pcall(function()
                local texObj = icon.Icon or icon.icon
                if texObj then texture = texObj:GetTexture() end
            end)
        end

        -- Fallback active state from icon frame
        if not isActive and not Bridge then
            pcall(function()
                auraInstanceID = icon.auraInstanceID
                isActive = (auraInstanceID ~= nil)
            end)
        end

        -- Look up spell name via SpellAPI if still missing
        if spellID and not issecretvalue(spellID) then
            if not spellName and SpellAPI then
                local info = SpellAPI:GetSpellInfo(spellID)
                if info then spellName = info.name end
            end
            if not texture and SpellAPI then
                texture = SpellAPI:GetSpellTexture(spellID)
            end
        end

        discoveredSlots[i] = {
            slotIndex = i,
            spellID = (spellID and not issecretvalue(spellID)) and spellID or nil,
            name = (spellName and not issecretvalue(spellName)) and spellName or ("Buff Slot " .. i),
            texture = (texture and not issecretvalue(texture)) and texture or nil,
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
        local id = BuffBarsData.ParseBarKey(barKey)
        if id then
            -- Find matching discovered slot (by spellID match or legacy slotIndex match)
            local slotInfo
            if BuffBarsData.IsSpellIDBarKey(barKey) then
                -- SpellID-keyed: find the slot that has this spellID
                for _, info in pairs(discoveredSlots) do
                    if info.spellID == id then slotInfo = info; break end
                end
            else
                -- Legacy slotIndex-keyed: direct lookup
                slotInfo = discoveredSlots[id]
            end
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
                config.slotIndex = slotInfo.slotIndex  -- Keep current slot position
            end
        end
    end

    -- Persist newly discovered slots using spellID-based keys
    for slotIndex, slotInfo in pairs(discoveredSlots) do
        local barKey
        if slotInfo.spellID then
            barKey = BuffBarsData.MakeBarKey(slotInfo.spellID)
        else
            barKey = BuffBarsData.MakeBarKey(slotIndex)  -- Legacy fallback
        end
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

    -- Prune orphaned spellID entries that no longer match any discovered slot
    -- This cleans up stale configs from Blizzard spell ID changes between patches
    if db.spells then
        local activeSpellIDs = {}
        for _, slotInfo in pairs(discoveredSlots) do
            if slotInfo.spellID then
                activeSpellIDs[slotInfo.spellID] = true
            end
        end
        local pruned = 0
        for barKey, config in pairs(db.spells) do
            if BuffBarsData.IsSpellIDBarKey(barKey) then
                local spellID = config.cachedSpellID
                if spellID and not activeSpellIDs[spellID] then
                    db.spells[barKey] = nil
                    pruned = pruned + 1
                    TUICD:PrintDebug("BuffBarsData: Pruned orphan " .. barKey .. " (" .. (config.name or "?") .. ")")
                end
            end
        end
        if pruned > 0 then
            TUICD:PrintDebug("BuffBarsData: Pruned " .. pruned .. " orphaned spell config(s)")
        end
    end

    -- Install CDM hooks and viewer hook after every discovery
    SetupViewerHook()
    HookCDMBuffCooldowns()

    return #icons
end

-- Re-discover slots after talent change / spec change / CDM layout update
-- With spellID-based keys, no remapping is needed — "buff:203819" stays correct
-- regardless of which slot position that spell occupies.
function BuffBarsData:RediscoverSlots()
    -- Run lazy migration for any remaining legacy slotIndex-keyed entries
    local db = self:GetDB()
    if db and db.spells then
        local Bridge = TUICD.BuffIdentityBridge
        if Bridge then
            local toMigrate = {}
            for barKey, config in pairs(db.spells) do
                if not BuffBarsData.IsSpellIDBarKey(barKey) then
                    local slotIdx = BuffBarsData.ParseBarKey(barKey)
                    if slotIdx then
                        -- Try to resolve spellID from bridge or cached value
                        local spellID = Bridge:GetSpellIDForSlot(slotIdx) or config.cachedSpellID
                        if spellID then
                            toMigrate[barKey] = { spellID = spellID, config = config }
                        end
                    end
                end
            end
            for oldKey, data in pairs(toMigrate) do
                local newKey = BuffBarsData.MakeBarKey(data.spellID)
                if not db.spells[newKey] then
                    data.config.cachedSpellID = data.spellID
                    db.spells[newKey] = data.config
                    db.spells[oldKey] = nil
                    TUICD:PrintDebug("BuffBarsData: Migrated " .. oldKey .. " -> " .. newKey)
                end
            end
        end
    end

    -- Re-run discovery to refresh slot positions and sync DB
    local count = self:DiscoverSlots()

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

-- Get CDM icon reference from a barKey (resolves spellID keys through Bridge)
function BuffBarsData:GetCDMIconForBarKey(barKey)
    local slotIndex = BuffBarsData.GetSlotIndexForBarKey(barKey)
    return slotIndex and cdmIcons[slotIndex]
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
        justify = "CENTER",       -- "START", "CENTER", "END" (arrival order placement)
        sortMode = "arrival",     -- "arrival" (FIFO center-out) or "list" (spell list order)
        -- Visibility settings
        visibilityEnabled = false,  -- Master toggle (false = always show)
        showInCombat = true,
        showOutOfCombat = true,
        showSolo = true,
        showInParty = true,
        showInRaid = true,
        showInDungeon = true,
        showInDelve = true,
        showInArena = true,
        showInBattleground = true,
        showHasTarget = true,
        showNoTarget = true,
        showMounted = true,
        showNotMounted = true,
        -- Override system: when enabled, dock settings override individual bar settings
        overrideBarSettings = false,
        barOverrides = {
            -- Bar dimensions
            width = 200,
            height = 20,
            -- Appearance
            barTexture = "Blizzard",
            barColor = { r = 0.2, g = 0.8, b = 0.2, a = 1.0 },
            backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
            borderColor = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },
            showBorder = true,
            -- Icon
            showIcon = true,
            iconPosition = "LEFT",
            iconSizeMode = "auto",
            iconSize = 20,
            iconAspect = "1:1",
            -- Text
            showName = true,
            showTime = true,
            font = nil,
            nameFontSize = 11,
            timeFontSize = 11,
            nameOffsetX = 0,
            nameOffsetY = 0,
            timeOffsetX = 0,
            timeOffsetY = 0,
            -- Behavior
            showWhenReady = false,
            showWhenInactive = false,
            fillMode = "drain",
            barDirection = "RIGHT",
        },
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
    
    -- =========================================================================
    -- v3.2.0 MIGRATION: slotIndex barKeys → spellID barKeys
    -- "buff:1" → "buff:203819" using cachedSpellID from saved configs
    -- Run once per character, lazy migration handles anything missed
    -- =========================================================================
    if db.spells and not db._migratedToSpellID then
        local migrated = {}
        local anyMigrated = false
        for barKey, config in pairs(db.spells) do
            if not BuffBarsData.IsSpellIDBarKey(barKey) and config.cachedSpellID then
                local newKey = BuffBarsData.MakeBarKey(config.cachedSpellID)
                if not db.spells[newKey] then
                    migrated[barKey] = newKey
                    anyMigrated = true
                end
            end
        end
        for oldKey, newKey in pairs(migrated) do
            db.spells[newKey] = db.spells[oldKey]
            db.spells[oldKey] = nil
        end
        -- Also migrate spell positions
        if db.spellPositions then
            local posMigrated = {}
            for barKey, pos in pairs(db.spellPositions) do
                if not BuffBarsData.IsSpellIDBarKey(barKey) then
                    local slotIdx = BuffBarsData.ParseBarKey(barKey)
                    local config = slotIdx and db.spells["buff:" .. slotIdx]
                    -- Check if the old key still exists (wasn't migrated) and has a cachedSpellID
                    if not config then
                        -- Key was migrated, find by cachedSpellID
                        for newKey, cfg in pairs(db.spells) do
                            if cfg.slotIndex == slotIdx and cfg.cachedSpellID then
                                posMigrated[barKey] = BuffBarsData.MakeBarKey(cfg.cachedSpellID)
                                break
                            end
                        end
                    end
                end
            end
            for oldKey, newKey in pairs(posMigrated) do
                if not db.spellPositions[newKey] then
                    db.spellPositions[newKey] = db.spellPositions[oldKey]
                end
                db.spellPositions[oldKey] = nil
            end
        end
        db._migratedToSpellID = true
    end
    
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
    local id = BuffBarsData.ParseBarKey(barKey)
    if id then
        local slot
        if BuffBarsData.IsSpellIDBarKey(barKey) then
            -- SpellID key: find discovered slot by spellID match
            for _, info in pairs(discoveredSlots) do
                if info.spellID == id then slot = info; break end
            end
        else
            -- Legacy slotIndex key: direct lookup
            slot = discoveredSlots[id]
        end
        if slot then
            return {
                enabled = false,
                name = slot.name,
                texture = slot.texture,
                iconID = slot.texture,
                type = BuffBarsData.TYPE_BUFF,
                slotIndex = slot.slotIndex,
                cachedSpellID = slot.spellID,
            }
        end
    end
    return nil
end

-- Get effective config: handles both normal mode and override mode
-- Normal mode: dock settings are base, per-spell values override
-- Override mode: dock barOverrides replace per-spell visual settings
function BuffBarsData:GetEffectiveConfig(barKey)
    local config = self:GetSpellConfig(barKey)
    if not config then return nil end

    local db = self:GetDB()
    local dockSettings = db.dockSettings or {}
    
    -- Check if override mode is enabled
    if dockSettings.overrideBarSettings and dockSettings.barOverrides then
        -- OVERRIDE MODE: Start with spell config, apply dock barOverrides on top
        local effective = {}
        for k, v in pairs(config) do 
            if type(v) == "table" then
                effective[k] = {}
                for k2, v2 in pairs(v) do effective[k][k2] = v2 end
            else
                effective[k] = v
            end
        end
        
        -- Apply visual overrides from dock
        local overrides = dockSettings.barOverrides
        local VISUAL_KEYS = {
            "width", "height", "barTexture", "barColor", "backgroundColor", "borderColor",
            "showBorder", "showIcon", "iconPosition", "iconSizeMode", "iconSize", "iconAspect",
            "showName", "showTime", "font", "nameFontSize", "timeFontSize",
            "nameOffsetX", "nameOffsetY", "timeOffsetX", "timeOffsetY",
            "showWhenReady", "showWhenInactive", "fillMode", "barDirection",
        }
        for _, k in ipairs(VISUAL_KEYS) do
            if overrides[k] ~= nil then
                if type(overrides[k]) == "table" then
                    effective[k] = {}
                    for k2, v2 in pairs(overrides[k]) do effective[k][k2] = v2 end
                else
                    effective[k] = overrides[k]
                end
            end
        end
        return effective
    else
        -- NORMAL MODE: Start with dock defaults, overlay per-spell config
        local merged = {}
        
        -- Start with dock defaults (deep copy tables)
        for k, v in pairs(dockSettings) do
            if k ~= "barOverrides" and k ~= "overrideBarSettings" then
                if type(v) == "table" then
                    merged[k] = {}
                    for k2, v2 in pairs(v) do merged[k][k2] = v2 end
                else
                    merged[k] = v
                end
            end
        end

        -- Overlay per-spell overrides
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
end

-- Enable a discovered slot for bar display (accepts slotIndex)
function BuffBarsData:EnableSlot(slotIndex, enabled)
    local barKey = BuffBarsData.MakeBarKeyFromSlot(slotIndex)
    return self:EnableByBarKey(barKey, slotIndex, enabled)
end

-- Enable/disable a bar by its barKey directly (used by UI when barKey is already known)
function BuffBarsData:EnableByBarKey(barKey, slotIndex, enabled)
    local db = self:GetDB()
    db.spells = db.spells or {}

    if enabled then
        if db.spells[barKey] then
            -- Entry already exists (persisted from discovery) - just enable it
            db.spells[barKey].enabled = true
        else
            -- Need discovery info to create new entry
            local slotInfo = slotIndex and discoveredSlots[slotIndex]
            if not slotInfo then
                -- Try to find by spellID
                local id = BuffBarsData.ParseBarKey(barKey)
                if id and BuffBarsData.IsSpellIDBarKey(barKey) then
                    for _, info in pairs(discoveredSlots) do
                        if info.spellID == id then slotInfo = info; break end
                    end
                end
            end
            if not slotInfo then return nil end
            db.spells[barKey] = {
                enabled = true,
                name = slotInfo.name,
                texture = slotInfo.texture,
                iconID = slotInfo.texture,
                type = BuffBarsData.TYPE_BUFF,
                slotIndex = slotInfo.slotIndex,
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
-- DOCK BAR OVERRIDES
-- ============================================================================

-- Dock bar override accessors
function BuffBarsData:GetDockOverrides()
    local dockSettings = self:GetDockSettings()
    return dockSettings.barOverrides or {}
end

function BuffBarsData:SetDockOverride(key, value)
    local db = self:GetDB()
    db.dockSettings = db.dockSettings or {}
    db.dockSettings.barOverrides = db.dockSettings.barOverrides or {}
    db.dockSettings.barOverrides[key] = value
    
    -- Fire event to refresh all bars when a dock override changes
    if TUICD.Events and TUICD.EVENTS and TUICD.EVENTS.BUFFBARS_DATA_UPDATED then
        TUICD.Events:Fire(TUICD.EVENTS.BUFFBARS_DATA_UPDATED, nil, "dock_override")
    end
end

function BuffBarsData:IsOverrideEnabled()
    local dockSettings = self:GetDockSettings()
    return dockSettings.overrideBarSettings == true
end

function BuffBarsData:SetOverrideEnabled(enabled)
    self:SetDockSetting("overrideBarSettings", enabled)
    -- Fire event to refresh all bars
    if TUICD.Events and TUICD.EVENTS and TUICD.EVENTS.BUFFBARS_DATA_UPDATED then
        TUICD.Events:Fire(TUICD.EVENTS.BUFFBARS_DATA_UPDATED, nil, "dock_override")
    end
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
    local seenSlots = {}   -- [slotIndex] = true
    local seenSpells = {}  -- [spellID] = true

    -- First: entries already in saved config
    for barKey, config in pairs(db.spells or {}) do
        local id = BuffBarsData.ParseBarKey(barKey)
        local slotIndex, spellID
        if BuffBarsData.IsSpellIDBarKey(barKey) then
            spellID = id
            slotIndex = BuffBarsData.GetSlotIndexForBarKey(barKey) or config.slotIndex
        else
            slotIndex = id
            spellID = config.cachedSpellID
        end
        if slotIndex then seenSlots[slotIndex] = true end
        if spellID then seenSpells[spellID] = true end
        
        -- Use discovery name if available (more current than saved name)
        local discoveryInfo = slotIndex and discoveredSlots[slotIndex]
        local currentName = discoveryInfo and discoveryInfo.name or config.name or ("Buff Slot " .. (slotIndex or "?"))
        local currentTexture = discoveryInfo and discoveryInfo.texture or config.texture or config.iconID
        
        list[#list + 1] = {
            barKey = barKey,
            slotIndex = slotIndex or 999,  -- Sort unknown slots to end
            name = currentName,
            displayName = currentName .. " " .. BuffBarsData.TypeLabel(),
            enabled = config.enabled,
            texture = currentTexture,
            cachedSpellID = spellID or (discoveryInfo and discoveryInfo.spellID) or config.cachedSpellID,
        }
    end

    -- Second: discovered slots not yet saved (show as disabled)
    for slotIndex, slotInfo in pairs(discoveredSlots) do
        local alreadySeen = seenSlots[slotIndex] or (slotInfo.spellID and seenSpells[slotInfo.spellID])
        if not alreadySeen then
            local barKey
            if slotInfo.spellID then
                barKey = BuffBarsData.MakeBarKey(slotInfo.spellID)
            else
                barKey = BuffBarsData.MakeBarKey(slotIndex)
            end
            list[#list + 1] = {
                barKey = barKey,
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

    local id = BuffBarsData.ParseBarKey(barKey)
    if not id then return false end

    -- Resolve slotIndex (for CDM icon access) and spellID (for state queries)
    local slotIndex, spellID
    if BuffBarsData.IsSpellIDBarKey(barKey) then
        spellID = id
        slotIndex = BuffBarsData.GetSlotIndexForBarKey(barKey)
    else
        slotIndex = id
        spellID = config.cachedSpellID
    end

    local sourceIcon = slotIndex and cdmIcons[slotIndex]
    local Bridge = TUICD.BuffIdentityBridge

    local state = spellStates[barKey]
    if not state then
        state = { type = BuffBarsData.TYPE_BUFF, isActive = false }
        spellStates[barKey] = state
    end

    local wasActive = state.isActive
    local prevAuraID = state.auraInstanceID
    local isActive = false
    local auraInstanceID = nil

    -- Priority 1: BuffIdentityBridge (combat-safe, never secret)
    if spellID and Bridge then
        isActive = Bridge:IsBuffActive(spellID) or false
        auraInstanceID = Bridge:GetAuraIDForSpellID(spellID)
    end

    -- Priority 2: Direct aura API (works outside combat, blocked when secret)
    if not isActive and spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        pcall(function()
            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if auraData then
                isActive = true
                auraInstanceID = auraData.auraInstanceID
            end
        end)
    end

    -- Priority 3: Fallback to CDM icon auraInstanceID
    if not isActive and sourceIcon then
        pcall(function()
            auraInstanceID = sourceIcon.auraInstanceID
            isActive = (auraInstanceID ~= nil)
        end)
    end

    -- Get timing data for bar rendering (duration in seconds, expirationTime in GetTime format)
    local duration, expirationTime
    if isActive and auraInstanceID then
        -- Method 1: Aura API (most reliable - returns seconds directly)
        if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
            pcall(function()
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
                if auraData then
                    if auraData.duration and auraData.duration > 0 then
                        duration = auraData.duration
                    end
                    if auraData.expirationTime and auraData.expirationTime > 0 then
                        expirationTime = auraData.expirationTime
                    end
                end
            end)
        end

        -- Method 2: CDM cooldown frame (fallback - returns milliseconds)
        if not duration and sourceIcon then
            local sourceCooldown = sourceIcon.Cooldown or sourceIcon.cooldown
            if sourceCooldown and sourceCooldown.GetCooldownTimes then
                pcall(function()
                    local startMs, durMs = sourceCooldown:GetCooldownTimes()
                    if durMs and durMs > 0 then
                        duration = durMs / 1000
                        expirationTime = (startMs + durMs) / 1000
                    end
                end)
            end
        end
    end
    
    -- COLOR-BY-TIME: Capture non-secret milliseconds from CDM cooldown frame
    -- This is the primary source for color-by-time since Duration Objects are secret
    local cdStartMs, cdDurationMs
    if isActive and sourceIcon then
        local sourceCooldown = sourceIcon.Cooldown or sourceIcon.cooldown
        if sourceCooldown and sourceCooldown.GetCooldownTimes then
            pcall(function()
                local startMs, durMs = sourceCooldown:GetCooldownTimes()
                if startMs and durMs and durMs > 0 then
                    cdStartMs = startMs
                    cdDurationMs = durMs
                end
            end)
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
        if type(expirationTime) == "number" and type(prevExpiration) == "number" then
            if expirationTime > prevExpiration + 0.5 then
                expirationChanged = true
            end
        end
    end
    
    local stateChanged = (wasActive ~= isActive) or (prevAuraID ~= auraInstanceID) or expirationChanged

    state.isActive = isActive
    state.duration = duration
    state.expirationTime = expirationTime
    state.auraInstanceID = auraInstanceID
    state.cdStartMs = isActive and cdStartMs or nil
    state.cdDurationMs = isActive and cdDurationMs or nil

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
                        BuffBarsData:UpdateAndFire(BuffBarsData.MakeBarKeyFromSlot(slot))
                    end
                end)
            end

            -- Hook SetCooldown (traditional method)
            hooksecurefunc(sourceCooldown, "SetCooldown", function(self)
                local slot = self._TUICD_BuffBar_SlotIndex
                if slot then
                    BuffBarsData:UpdateAndFire(BuffBarsData.MakeBarKeyFromSlot(slot))
                end
            end)

            -- Hook Clear (buff expired)
            hooksecurefunc(sourceCooldown, "Clear", function(self)
                local slot = self._TUICD_BuffBar_SlotIndex
                if slot then
                    BuffBarsData:UpdateAndFire(BuffBarsData.MakeBarKeyFromSlot(slot))
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
                print(string.format("  %s [%s] slot=%d name='%s' tex=%s - %s",
                    enabled, entry.barKey, entry.slotIndex or -1, entry.name or "?", 
                    tostring(entry.texture), status
                ))
            end
        end
        
    elseif cmd == "debug" then
        -- Debug: show saved config vs discovery
        local db = self:GetDB()
        TUICD:Print("=== DEBUG: Saved Config ===")
        for barKey, config in pairs(db.spells or {}) do
            local slotIdx = BuffBarsData.ParseBarKey(barKey)
            print(string.format("  %s (slot %d): saved_name='%s' saved_tex=%s spell=%s",
                barKey, slotIdx or -1, config.name or "?", tostring(config.texture), tostring(config.cachedSpellID)))
        end
        TUICD:Print("=== DEBUG: Discovered Slots ===")
        for idx, info in pairs(discoveredSlots) do
            print(string.format("  slot %d: disc_name='%s' disc_tex=%s spell=%s",
                idx, info.name or "?", tostring(info.texture), tostring(info.spellID)))
        end
        TUICD:Print("=== DEBUG: GetSpellList() output ===")
        local list = self:GetSpellList()
        for i, entry in ipairs(list) do
            print(string.format("  row %d: barKey=%s slot=%d name='%s' tex=%s",
                i, entry.barKey, entry.slotIndex or -1, entry.name or "?", tostring(entry.texture)))
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

    elseif cmd == "reset" then
        -- Clear all saved buff bar data and rediscover
        local db = self:GetDB()
        if db then
            -- Clear saved spells (keeps dock settings)
            db.spells = {}
            wipe(discoveredSlots)
            wipe(spellStates)
            wipe(cdmIcons)
            discoveryDone = false
            
            -- Rediscover
            C_Timer.After(0.5, function()
                local count = self:DiscoverSlots()
                TUICD:Print("Reset complete. Rediscovered " .. count .. " buff slot(s).")
                TUICD:Print("Use '/tuicd buffbars list' to see slots, then '/tuicd buffbars enable N' to enable.")
            end)
        end
        TUICD:Print("Clearing saved buff bar data...")

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
        print("  reset     - Clear saved data and rediscover")
        print("  colortime - Toggle color-by-time (green->yellow->red)")
        print("  layout    - Toggle layout/drag mode")
        print("  show      - Force show all bars (debug)")
        print("  hide      - Hide all bars")
        print("  debug     - Dump saved config, discovered slots, spell list")
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
