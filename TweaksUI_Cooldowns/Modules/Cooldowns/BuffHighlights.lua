-- ============================================================================
-- TUICD BuffHighlights.lua
-- Creates positionable highlight clones for tracked buffs
-- Detects active/inactive state via auraInstanceID (no secret value math)
-- ============================================================================

local addonName, TUICD = ...
TUICD.BuffHighlights = TUICD.BuffHighlights or {}
local BuffHighlights = TUICD.BuffHighlights

-- ============================================================================
-- MIDNIGHT API WRAPPERS (v2.0.0)
-- ============================================================================

local AuraAPI = TUICD.AuraAPI
local DurationAPI = TUICD.DurationAPI

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local UPDATE_INTERVAL = 0.25  -- 4 Hz update rate (was 10 Hz)
local DEFAULT_SIZE = 48
local FRAME_PREFIX = "TweaksUI_BuffHighlight_"

-- ============================================================================
-- STATE
-- ============================================================================

local highlightFrames = {}  -- [slotIndex] = frame (visual frames stay positional)
local cachedTextures = {}   -- [spellID or slotIndex] = textureID (keyed by settings key)
-- updateFrame is defined in the UPDATE SYSTEM section
local isInitialized = false

-- Debug mode
local debugMode = false
local function dprint(...)
    -- Debug printing disabled
end

-- ============================================================================
-- SPELL ID-BASED SETTINGS KEY (v3.2.0)
-- Settings are stored by spellID so they follow the spell, not the position.
-- Uses BuffIdentityBridge for combat-safe slotIndex → spellID resolution.
-- Falls back to raw slotIndex when bridge data isn't available yet.
-- SpellIDs are always > 1000; slotIndexes are always 1-20.
-- ============================================================================

local function IsSpellIDKey(key)
    return type(key) == "number" and key > 100
end

local function GetSettingsKey(slotIndex)
    if not slotIndex then return nil end
    local Bridge = TUICD.BuffIdentityBridge
    if Bridge then
        local spellID = Bridge:GetSpellIDForSlot(slotIndex)
        if spellID then return spellID end
    end
    -- Fallback: raw slotIndex (legacy or bridge not populated yet)
    return slotIndex
end

-- Lazy migration: when bridge first resolves a spellID for a slot that still
-- has old slotIndex-keyed data, migrate those entries on the fly.
local function LazyMigrateSlot(db, slotIndex, spellID)
    if not db or not slotIndex or not spellID then return end
    if slotIndex == spellID then return end  -- Already same key
    if IsSpellIDKey(slotIndex) then return end  -- Already a spellID key
    
    -- List of all flat DB tables that store per-icon settings
    local flatTables = {
        "enabled", "hidden", "positions", "dockAssignment",
        "cooldownTextScale", "cooldownTextColor", "cooldownTextOffsetX", "cooldownTextOffsetY", "cooldownTextAnchor",
        "countTextScale", "countTextColor", "countTextOffsetX", "countTextOffsetY", "countTextAnchor",
        "labelEnabled", "labelText", "labelFontSize", "labelColor", "labelOffsetX", "labelOffsetY", "labelAnchor",
        "showSweep", "showCountdownText", "showProcGlow",
    }
    
    local migrated = false
    for _, tableName in ipairs(flatTables) do
        if db[tableName] and db[tableName][slotIndex] ~= nil then
            db[tableName][spellID] = db[tableName][slotIndex]
            db[tableName][slotIndex] = nil
            migrated = true
        end
    end
    
    -- Migrate state sub-tables (active/inactive)
    for _, state in ipairs({"active", "inactive"}) do
        if db[state] then
            for _, key in ipairs({"size", "opacity", "saturation", "aspectRatio", "customAspectW", "customAspectH", "show"}) do
                if db[state][key] and db[state][key][slotIndex] ~= nil then
                    db[state][key][spellID] = db[state][key][slotIndex]
                    db[state][key][slotIndex] = nil
                    migrated = true
                end
            end
        end
    end
    
    -- Migrate cachedTextures too
    if cachedTextures[slotIndex] and not cachedTextures[spellID] then
        cachedTextures[spellID] = cachedTextures[slotIndex]
        cachedTextures[slotIndex] = nil
    end
    
    return migrated
end

-- Smart key resolver: gets settings key AND triggers lazy migration if needed
local function GetSettingsKeyWithMigration(slotIndex)
    if not slotIndex then return nil end
    local Bridge = TUICD.BuffIdentityBridge
    if Bridge then
        local spellID = Bridge:GetSpellIDForSlot(slotIndex)
        if spellID then
            -- Check if lazy migration is needed
            local db = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.buffHighlights
            if db and not IsSpellIDKey(slotIndex) then
                -- Only migrate if old slotIndex data exists
                if db.enabled and db.enabled[slotIndex] ~= nil then
                    LazyMigrateSlot(db, slotIndex, spellID)
                end
            end
            return spellID
        end
    end
    return slotIndex
end

-- Resolve a settings key (spellID or slotIndex) back to a visual slotIndex
-- Used when iterating db.enabled which now stores spellID keys
local function ResolveToSlotIndex(settingsKey)
    if not settingsKey then return nil end
    -- If it's already a small number, it's a legacy slotIndex
    if not IsSpellIDKey(settingsKey) then return settingsKey end
    -- It's a spellID — look up the current slotIndex via Bridge
    local Bridge = TUICD.BuffIdentityBridge
    if Bridge then
        return Bridge:GetSlotForSpellID(settingsKey)
    end
    return nil  -- Can't resolve without Bridge
end

-- Iterate all enabled highlights, yielding (slotIndex, settingsKey) pairs
-- Handles both legacy slotIndex keys and migrated spellID keys
local GetDB  -- forward declaration (defined in DATABASE section below)
local function ForEachEnabledHighlight(callback)
    local db = GetDB()
    if not db.enabled then return end
    for settingsKey, enabled in pairs(db.enabled) do
        if enabled then
            local slotIndex = ResolveToSlotIndex(settingsKey)
            if slotIndex then
                callback(slotIndex, settingsKey)
            end
        end
    end
end

-- ============================================================================
-- DATABASE
-- ============================================================================

GetDB = function()
    if not TweaksUI_Cooldowns_CharDB then TweaksUI_Cooldowns_CharDB = {} end
    if not TweaksUI_Cooldowns_CharDB.buffHighlights then
        TweaksUI_Cooldowns_CharDB.buffHighlights = {
            hideTracker = false,  -- Hide the main buff tracker
            enabled = {},  -- [slotIndex] = true/false
            positions = {}, -- [slotIndex] = {point, relPoint, x, y}
            -- Active state settings (when buff is present)
            active = {
                size = {},          -- [slotIndex] = size
                opacity = {},       -- [slotIndex] = 0.0-1.0
                saturation = {},    -- [slotIndex] = true/false
                aspectRatio = {},   -- [slotIndex] = "1:1", "custom", etc.
                customAspectW = {}, -- [slotIndex] = width
                customAspectH = {}, -- [slotIndex] = height
                show = {},          -- [slotIndex] = true/false (show when active)
            },
            -- Inactive state settings (when buff is missing)
            inactive = {
                size = {},
                opacity = {},
                saturation = {},
                aspectRatio = {},
                customAspectW = {},
                customAspectH = {},
                show = {},          -- [slotIndex] = true/false (show when inactive)
            },
        }
    end
    -- Ensure all fields exist (for existing databases)
    local db = TweaksUI_Cooldowns_CharDB.buffHighlights
    if not db.enabled then db.enabled = {} end
    if not db.positions then db.positions = {} end
    
    -- Migrate old format to new format
    if db.triggerOn or db.sizes then
        -- Old format detected, migrate
        if not db.active then db.active = {} end
        if not db.inactive then db.inactive = {} end
        
        for _, state in ipairs({"active", "inactive"}) do
            if not db[state].size then db[state].size = {} end
            if not db[state].opacity then db[state].opacity = {} end
            if not db[state].saturation then db[state].saturation = {} end
            if not db[state].aspectRatio then db[state].aspectRatio = {} end
            if not db[state].customAspectW then db[state].customAspectW = {} end
            if not db[state].customAspectH then db[state].customAspectH = {} end
            if not db[state].show then db[state].show = {} end
        end
        
        -- Migrate old settings to active state
        if db.sizes then
            for k, v in pairs(db.sizes) do
                db.active.size[k] = v
                db.inactive.size[k] = v
            end
            db.sizes = nil
        end
        if db.opacity then
            for k, v in pairs(db.opacity) do
                db.active.opacity[k] = v
                db.inactive.opacity[k] = 0.3  -- Default inactive to lower opacity
            end
            db.opacity = nil
        end
        if db.saturation then
            for k, v in pairs(db.saturation) do
                db.active.saturation[k] = v
                db.inactive.saturation[k] = false  -- Default inactive to desaturated
            end
            db.saturation = nil
        end
        if db.aspectRatio then
            for k, v in pairs(db.aspectRatio) do
                db.active.aspectRatio[k] = v
                db.inactive.aspectRatio[k] = v
            end
            db.aspectRatio = nil
        end
        if db.triggerOn then
            for k, v in pairs(db.triggerOn) do
                if v == "active" then
                    db.active.show[k] = true
                    db.inactive.show[k] = false
                else
                    db.active.show[k] = false
                    db.inactive.show[k] = true
                end
            end
            db.triggerOn = nil
        end
    end
    
    -- Ensure nested tables exist
    if not db.active then db.active = {} end
    if not db.inactive then db.inactive = {} end
    for _, state in ipairs({"active", "inactive"}) do
        if not db[state].size then db[state].size = {} end
        if not db[state].opacity then db[state].opacity = {} end
        if not db[state].saturation then db[state].saturation = {} end
        if not db[state].aspectRatio then db[state].aspectRatio = {} end
        if not db[state].customAspectW then db[state].customAspectW = {} end
        if not db[state].customAspectH then db[state].customAspectH = {} end
        if not db[state].show then db[state].show = {} end
    end
    
    -- Text scale fields (state-independent)
    if not db.cooldownTextScale then db.cooldownTextScale = {} end
    if not db.cooldownTextColor then db.cooldownTextColor = {} end
    if not db.cooldownTextOffsetX then db.cooldownTextOffsetX = {} end
    if not db.cooldownTextOffsetY then db.cooldownTextOffsetY = {} end
    if not db.cooldownTextAnchor then db.cooldownTextAnchor = {} end
    if not db.countTextScale then db.countTextScale = {} end
    if not db.countTextColor then db.countTextColor = {} end
    if not db.countTextOffsetX then db.countTextOffsetX = {} end
    if not db.countTextOffsetY then db.countTextOffsetY = {} end
    if not db.countTextAnchor then db.countTextAnchor = {} end
    
    -- Custom label fields (state-independent)
    if not db.labelEnabled then db.labelEnabled = {} end
    if not db.labelText then db.labelText = {} end
    if not db.labelFontSize then db.labelFontSize = {} end
    if not db.labelColor then db.labelColor = {} end
    if not db.labelOffsetX then db.labelOffsetX = {} end
    if not db.labelOffsetY then db.labelOffsetY = {} end
    if not db.labelAnchor then db.labelAnchor = {} end
    
    -- Per-icon sweep and countdown text settings (overrides tracker-level when set)
    if not db.showSweep then db.showSweep = {} end
    if not db.showCountdownText then db.showCountdownText = {} end
    
    -- Hidden icons (state-independent) - hides icon from tracker completely
    if not db.hidden then db.hidden = {} end
    
    -- Dock assignment (state-independent) - which dock (1-4) icon is assigned to
    if not db.dockAssignment then db.dockAssignment = {} end
    
    -- =========================================================================
    -- v3.2.0 MIGRATION: slotIndex keys → spellID keys
    -- Run once on first load when bridge has data (outside combat, APIs non-secret)
    -- =========================================================================
    if not db._migratedToSpellID then
        local Bridge = TUICD.BuffIdentityBridge
        if Bridge and Bridge.GetSpellIDForSlot then
            -- Try to migrate all known slots
            for slotIndex = 1, 20 do
                local spellID = Bridge:GetSpellIDForSlot(slotIndex)
                if spellID then
                    LazyMigrateSlot(db, slotIndex, spellID)
                end
            end
            -- Mark complete — lazy migration handles any slots resolved later
            db._migratedToSpellID = true
        end
    end
    
    return db
end

local function IsHighlightEnabled(slotIndex)
    local db = GetDB()
    local key = GetSettingsKeyWithMigration(slotIndex)
    return db.enabled[key] == true
end

local function SetHighlightEnabled(slotIndex, enabled)
    local db = GetDB()
    local key = GetSettingsKeyWithMigration(slotIndex)
    db.enabled[key] = enabled
end

local function IsIconHidden(slotIndex)
    local db = GetDB()
    local key = GetSettingsKeyWithMigration(slotIndex)
    return db.hidden[key] == true
end

local function SetIconHidden(slotIndex, hidden)
    local db = GetDB()
    local key = GetSettingsKeyWithMigration(slotIndex)
    db.hidden[key] = hidden
end

local function GetDockAssignment(slotIndex)
    local db = GetDB()
    local key = GetSettingsKeyWithMigration(slotIndex)
    return db.dockAssignment[key]  -- nil, 1, 2, 3, or 4
end

local function SetDockAssignment(slotIndex, dockIndex)
    local db = GetDB()
    local key = GetSettingsKeyWithMigration(slotIndex)
    local oldDock = db.dockAssignment[key]
    db.dockAssignment[key] = dockIndex
    
    -- Update Docks module
    if TUICD.Docks then
        if dockIndex and dockIndex >= 1 and dockIndex <= 4 then
            TUICD.Docks:AssignIcon(dockIndex, "buffs", slotIndex)
        else
            -- Unassign from all docks
            for i = 1, 4 do
                TUICD.Docks:UnassignIcon(i, "buffs", slotIndex)
            end
        end
    end
    
    -- Refresh layout mode overlay (show/hide based on dock status)
    if TUICD.LayoutMode and TUICD.LayoutMode.RefreshPerIconOverlay then
        TUICD.LayoutMode:RefreshPerIconOverlay("buffs", slotIndex)
    end
end

-- State-aware getters/setters
local function GetStateSetting(slotIndex, state, key)
    local db = GetDB()
    local settingsKey = GetSettingsKeyWithMigration(slotIndex)
    return db[state] and db[state][key] and db[state][key][settingsKey]
end

local function SetStateSetting(slotIndex, state, key, value)
    local db = GetDB()
    local settingsKey = GetSettingsKeyWithMigration(slotIndex)
    if db[state] and db[state][key] then
        db[state][key][settingsKey] = value
    end
end

local function GetHighlightSize(slotIndex, state)
    return GetStateSetting(slotIndex, state or "active", "size") or DEFAULT_SIZE
end

local function SetHighlightSize(slotIndex, state, size)
    SetStateSetting(slotIndex, state, "size", size)
end

local function GetHighlightOpacity(slotIndex, state)
    local default = (state == "inactive") and 0.4 or 1.0
    return GetStateSetting(slotIndex, state or "active", "opacity") or default
end

local function SetHighlightOpacity(slotIndex, state, opacity)
    SetStateSetting(slotIndex, state, "opacity", opacity)
end

local function GetHighlightSaturation(slotIndex, state)
    local default = (state == "inactive") and false or true
    local val = GetStateSetting(slotIndex, state or "active", "saturation")
    if val == nil then return default end
    return val
end

local function SetHighlightSaturation(slotIndex, state, saturated)
    SetStateSetting(slotIndex, state, "saturation", saturated)
end

local function GetHighlightAspectRatio(slotIndex, state)
    return GetStateSetting(slotIndex, state or "active", "aspectRatio") or "1:1"
end

local function SetHighlightAspectRatio(slotIndex, state, ratio)
    SetStateSetting(slotIndex, state, "aspectRatio", ratio)
end

local function GetShowState(slotIndex, state)
    local val = GetStateSetting(slotIndex, state, "show")
    if val == nil then
        -- Default: show active, hide inactive
        return (state == "active")
    end
    return val
end

local function SetShowState(slotIndex, state, show)
    SetStateSetting(slotIndex, state, "show", show)
end

local function GetHighlightPosition(slotIndex)
    local db = GetDB()
    local key = GetSettingsKeyWithMigration(slotIndex)
    return db.positions[key]
end

local function SetHighlightPosition(slotIndex, point, relPoint, x, y)
    local db = GetDB()
    local key = GetSettingsKeyWithMigration(slotIndex)
    db.positions[key] = {point = point, relPoint = relPoint, x = x, y = y}
end

local function IsTrackerHidden()
    local db = GetDB()
    return db.hideTracker == true
end

local function SetTrackerHidden(hidden)
    local db = GetDB()
    db.hideTracker = hidden
end

-- ============================================================================
-- VISIBILITY CONDITION CHECKING
-- Per-icon highlights should respect the tracker's visibility conditions
-- ============================================================================

-- Get current player state for visibility checks (mirrors Cooldowns.lua logic)
local function GetPlayerState()
    local state = {
        inCombat = InCombatLockdown() or UnitAffectingCombat("player"),
        inGroup = IsInGroup(),
        inRaid = IsInRaid(),
        inInstance = false,
        inArena = false,
        inBattleground = false,
        isSolo = not IsInGroup(),
        hasTarget = UnitExists("target"),
        isMounted = TUICD.UnitAPI:IsMountedOrTravelForm(),
    }
    
    -- Check instance type
    local _, instanceType = IsInInstance()
    if instanceType == "party" or instanceType == "raid" then
        state.inInstance = true
    elseif instanceType == "arena" then
        state.inArena = true
    elseif instanceType == "pvp" then
        state.inBattleground = true
    end
    
    return state
end

-- Check if highlight should be visible based on tracker's visibility conditions
local function ShouldHighlightBeVisible()
    -- Always show in Layout Mode for positioning
    local layoutContainer = _G["TweaksUI_LayoutContainer"]
    if layoutContainer and layoutContainer:IsShown() then
        return true
    end
    
    -- Always show in Edit Mode
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return true
    end
    
    -- Get tracker settings via Database
    if not TUICD.Database then return true end
    
    local trackerKey = "buffs"
    
    local visibilityEnabled = TUICD.Database:GetTrackerSetting(trackerKey, "visibilityEnabled")
    if not visibilityEnabled then
        return true  -- Visibility system disabled = always show
    end
    
    local state = GetPlayerState()
    
    -- OR logic: if ANY checked condition is true, show the highlight
    if state.inCombat and TUICD.Database:GetTrackerSetting(trackerKey, "showInCombat") then return true end
    if not state.inCombat and TUICD.Database:GetTrackerSetting(trackerKey, "showOutOfCombat") then return true end
    if state.isSolo and TUICD.Database:GetTrackerSetting(trackerKey, "showSolo") then return true end
    if state.inGroup and not state.inRaid and TUICD.Database:GetTrackerSetting(trackerKey, "showInParty") then return true end
    if state.inRaid and TUICD.Database:GetTrackerSetting(trackerKey, "showInRaid") then return true end
    if state.inInstance and TUICD.Database:GetTrackerSetting(trackerKey, "showInInstance") then return true end
    if state.inArena and TUICD.Database:GetTrackerSetting(trackerKey, "showInArena") then return true end
    if state.inBattleground and TUICD.Database:GetTrackerSetting(trackerKey, "showInBattleground") then return true end
    if state.hasTarget and TUICD.Database:GetTrackerSetting(trackerKey, "showHasTarget") then return true end
    if not state.hasTarget and TUICD.Database:GetTrackerSetting(trackerKey, "showNoTarget") then return true end
    if state.isMounted and TUICD.Database:GetTrackerSetting(trackerKey, "showMounted") then return true end
    if not state.isMounted and TUICD.Database:GetTrackerSetting(trackerKey, "showNotMounted") then return true end
    
    -- No conditions matched
    return false
end

-- Text scale helpers (state-independent) - keyed by spellID via GetSettingsKey
local function GetCooldownTextScale(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.cooldownTextScale[key] or 1.0
end

local function SetCooldownTextScale(slotIndex, scale)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.cooldownTextScale[key] = scale
end

local function GetCountTextScale(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.countTextScale[key] or 1.0
end

local function SetCountTextScale(slotIndex, scale)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.countTextScale[key] = scale
end

local function GetCooldownTextColor(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.cooldownTextColor[key] or {1, 1, 1, 1}  -- Default white
end

local function SetCooldownTextColor(slotIndex, color)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.cooldownTextColor[key] = color
end

local function GetCountTextColor(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.countTextColor[key] or {1, 1, 1, 1}  -- Default white
end

local function SetCountTextColor(slotIndex, color)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.countTextColor[key] = color
end

local function GetCooldownTextOffsetX(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.cooldownTextOffsetX[key] or 0
end

local function SetCooldownTextOffsetX(slotIndex, offset)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.cooldownTextOffsetX[key] = offset
end

local function GetCooldownTextOffsetY(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.cooldownTextOffsetY[key] or 0
end

local function SetCooldownTextOffsetY(slotIndex, offset)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.cooldownTextOffsetY[key] = offset
end

local function GetCountTextOffsetX(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.countTextOffsetX[key] or 0
end

local function SetCountTextOffsetX(slotIndex, offset)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.countTextOffsetX[key] = offset
end

local function GetCountTextOffsetY(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.countTextOffsetY[key] or 0
end

local function SetCountTextOffsetY(slotIndex, offset)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.countTextOffsetY[key] = offset
end

local function GetCooldownTextAnchor(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.cooldownTextAnchor[key] or "CENTER"
end

local function SetCooldownTextAnchor(slotIndex, anchor)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.cooldownTextAnchor[key] = anchor
end

local function GetCountTextAnchor(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.countTextAnchor[key] or "BOTTOMRIGHT"
end

local function SetCountTextAnchor(slotIndex, anchor)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.countTextAnchor[key] = anchor
end

-- Custom label functions - keyed by spellID via GetSettingsKey
local function GetLabelEnabled(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.labelEnabled[key] == true
end

local function SetLabelEnabled(slotIndex, enabled)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.labelEnabled[key] = enabled
end

local function GetLabelText(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.labelText[key] or ""
end

local function SetLabelText(slotIndex, text)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.labelText[key] = text
end

local function GetLabelFontSize(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.labelFontSize[key] or 14
end

local function SetLabelFontSize(slotIndex, size)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.labelFontSize[key] = size
end

local function GetLabelColor(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.labelColor[key] or {1, 1, 1, 1}
end

local function SetLabelColor(slotIndex, color)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.labelColor[key] = color
end

local function GetLabelOffsetX(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.labelOffsetX[key] or 0
end

local function SetLabelOffsetX(slotIndex, offset)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.labelOffsetX[key] = offset
end

local function GetLabelOffsetY(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.labelOffsetY[key] or 0
end

local function SetLabelOffsetY(slotIndex, offset)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.labelOffsetY[key] = offset
end

local function GetLabelAnchor(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.labelAnchor[key] or "CENTER"
end

local function SetLabelAnchor(slotIndex, anchor)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.labelAnchor[key] = anchor
end

-- Per-icon sweep visibility (nil = use tracker default) - keyed by spellID
local function GetShowSweep(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.showSweep[key]  -- Returns nil if not set (use tracker default)
end

local function SetShowSweep(slotIndex, show)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.showSweep[key] = show
end

-- Per-icon countdown text visibility (nil = use tracker default) - keyed by spellID
local function GetShowCountdownText(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.showCountdownText[key]  -- Returns nil if not set (use tracker default)
end

local function SetShowCountdownText(slotIndex, show)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.showCountdownText[key] = show
end

-- ============================================================================
-- BUFF SLOT ACCESS
-- ============================================================================

-- Get the buff viewer frame
local function GetBuffViewer()
    return _G["BuffIconCooldownViewer"]
end

-- Collect all icons from the buff viewer (reuses Cooldowns logic)
-- Note: We collect icons even if they're hidden (alpha 0) because we need their data
local function CollectBuffIcons()
    local viewer = GetBuffViewer()
    if not viewer then return {} end
    
    -- Don't check IsShown because we hide the tracker with alpha 0
    -- The icons still exist and have data even when hidden
    
    local icons = {}
    local numChildren = 0
    pcall(function() numChildren = viewer:GetNumChildren() or 0 end)
    
    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        -- Check if this looks like an icon (don't require IsShown)
        if child then
            local hasIcon = child.Icon or child.icon
            local hasCooldown = child.Cooldown or child.cooldown
            if hasIcon or hasCooldown then
                icons[#icons + 1] = child
            elseif child.GetNumChildren then
                -- Check nested children
                local numNested = 0
                pcall(function() numNested = child:GetNumChildren() or 0 end)
                for j = 1, numNested do
                    local nested = select(j, child:GetChildren())
                    if nested then
                        local nestedHasIcon = nested.Icon or nested.icon
                        local nestedHasCooldown = nested.Cooldown or nested.cooldown
                        if nestedHasIcon or nestedHasCooldown then
                            icons[#icons + 1] = nested
                        end
                    end
                end
            end
        end
    end
    
    -- Sort by visual position (top-to-bottom, left-to-right) to match Cooldowns module order
    table.sort(icons, function(a, b)
        local at, bt = 0, 0
        local al, bl = 0, 0
        pcall(function() at = a:GetTop() or 0 end)
        pcall(function() bt = b:GetTop() or 0 end)
        pcall(function() al = a:GetLeft() or 0 end)
        pcall(function() bl = b:GetLeft() or 0 end)
        
        -- Sort top-to-bottom first (higher Y = higher on screen)
        if math.abs(at - bt) > 5 then return at > bt end
        
        -- Then left-to-right for icons in same row
        return al < bl
    end)
    
    return icons
end

-- Get info about a specific buff slot
local function GetBuffSlotInfo(slotIndex)
    -- Use TUICD.Cooldowns.GetOrderedIcons if available (same order as layout/list)
    local icons
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer then
            icons = Cooldowns.GetOrderedIcons(viewer, "buffs")
        else
            icons = {}
        end
    else
        -- Fallback to local CollectBuffIcons
        icons = CollectBuffIcons()
    end
    
    local icon = icons[slotIndex]
    
    if not icon then return nil end
    
    local info = {
        icon = icon,
        isActive = false,
        auraInstanceID = nil,
        spellID = nil,  -- Resolved spellID (from Bridge or icon properties)
        texture = nil,
        name = "Buff Slot " .. slotIndex,
    }
    
    -- PRIORITY 1: Use BuffIdentityBridge (combat-safe, always non-secret)
    local Bridge = TUICD.BuffIdentityBridge
    if Bridge then
        info.spellID = Bridge:GetSpellIDForSlot(slotIndex)
        if info.spellID then
            info.isActive = Bridge:IsBuffActive(info.spellID)
            info.auraInstanceID = Bridge:GetAuraIDForSpellID(info.spellID)
            -- Get name from bridge or spell API
            local bridgeInfo = Bridge:GetBuffInfo(info.spellID)
            if bridgeInfo and bridgeInfo.name then
                info.name = bridgeInfo.name
            elseif GetSpellName then
                pcall(function() info.name = GetSpellName(info.spellID) or info.name end)
            end
        end
    end
    
    -- PRIORITY 2: Fallback to icon STATIC properties (may be tainted in combat)
    if not info.spellID then
        pcall(function()
            info.spellID = icon.spellID or icon.SpellID or icon.spellId
        end)
    end
    
    -- PRIORITY 3: If we have spellID but no Bridge active state, query aura API
    if not info.isActive and info.spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        pcall(function()
            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(info.spellID)
            if auraData then
                info.isActive = true
                info.auraInstanceID = auraData.auraInstanceID
            end
        end)
    end
    
    -- PRIORITY 4: Fallback to checking auraInstanceID from source icon
    if not info.isActive then
        pcall(function()
            info.auraInstanceID = icon.auraInstanceID
            info.isActive = (icon.auraInstanceID ~= nil)
        end)
    end
    
    -- Get texture safely
    local textureObj = icon.Icon or icon.icon
    if textureObj then
        pcall(function()
            info.texture = textureObj:GetTexture()
        end)
    end
    
    return info
end

-- Get count of buff slots
local function GetBuffSlotCount()
    -- Use TUICD.Cooldowns.GetOrderedIcons if available (same order as layout/list)
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer then
            return #Cooldowns.GetOrderedIcons(viewer, "buffs")
        end
    end
    -- Fallback
    return #CollectBuffIcons()
end

-- ============================================================================
-- HIGHLIGHT FRAME CREATION (Clone-based - we create our own frame and copy data)
-- ============================================================================

local function CreateHighlightFrame(slotIndex)
    if highlightFrames[slotIndex] then
        return highlightFrames[slotIndex]
    end
    
    local frameName = FRAME_PREFIX .. slotIndex
    local size = GetHighlightSize(slotIndex)
    
    -- Check if Masque is enabled for buffs tracker
    local useMasque = TUICD.Cooldowns and TUICD.Cooldowns.IsMasqueAvailable and TUICD.Cooldowns:IsMasqueAvailable()
    local masqueEnabled = useMasque and TUICD.Database and TUICD.Database:GetTrackerSetting("buffs", "useMasque")
    
    local frame = CreateFrame("Button", frameName, UIParent, "BackdropTemplate")
    frame:SetSize(size, size)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    
    -- CRITICAL: Make frame movable for Layout mode
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)  -- Don't eat mouse clicks - Layout overlay handles that
    
    -- Background (hide if Masque is enabled)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    
    if masqueEnabled then
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    else
        frame:SetBackdropColor(0, 0, 0, 0.6)
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end
    
    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon = frame.icon  -- Masque expects .Icon
    if masqueEnabled then
        frame.icon:SetAllPoints(frame)
        frame.icon:SetTexCoord(0, 1, 0, 1)  -- Let Masque handle texcoords
    else
        frame.icon:SetPoint("TOPLEFT", 2, -2)
        frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    
    -- Cooldown spiral
    frame.cooldown = CreateFrame("Cooldown", frameName .. "_Cooldown", frame, "CooldownFrameTemplate")
    frame.Cooldown = frame.cooldown  -- Masque expects .Cooldown
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetFrameLevel(frame:GetFrameLevel() + 2)  -- Above icon texture
    frame.cooldown:SetDrawEdge(not masqueEnabled)  -- Masque handles edge
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    
    -- Apply sweep and countdown text settings (per-icon overrides tracker-level)
    local showSweep = GetShowSweep(slotIndex)  -- Per-icon setting
    local showCountdownText = GetShowCountdownText(slotIndex)  -- Per-icon setting
    
    -- Fall back to tracker-level settings if per-icon not set
    if showSweep == nil and TUICD.Database then
        local sweepSetting = TUICD.Database:GetTrackerSetting("buffs", "showSweep")
        showSweep = (sweepSetting ~= nil) and sweepSetting or true
    end
    if showCountdownText == nil and TUICD.Database then
        local countdownSetting = TUICD.Database:GetTrackerSetting("buffs", "showCountdownText")
        showCountdownText = (countdownSetting ~= nil) and countdownSetting or true
    end
    
    -- Default to true if still nil
    if showSweep == nil then showSweep = true end
    if showCountdownText == nil then showCountdownText = true end
    
    frame.cooldown:SetDrawSwipe(showSweep)
    frame.cooldown:SetHideCountdownNumbers(not showCountdownText)
    
    -- Store settings on cooldown for hooks to use
    frame.cooldown._TUI_showSweep = showSweep
    frame.cooldown._TUI_showCountdownText = showCountdownText
    frame.cooldown._TUI_slotIndex = slotIndex
    
    -- Hook SetCooldown to reapply settings after Blizzard updates
    hooksecurefunc(frame.cooldown, "SetCooldown", function(self)
        pcall(function()
            self:SetDrawSwipe(self._TUI_showSweep)
            self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
        end)
    end)
    -- Also hook SetCooldownFromDurationObject for Midnight API
    if frame.cooldown.SetCooldownFromDurationObject then
        hooksecurefunc(frame.cooldown, "SetCooldownFromDurationObject", function(self)
            pcall(function()
                self:SetDrawSwipe(self._TUI_showSweep)
                self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
            end)
        end)
    end
    
    -- Stack count text (bottom right, larger font)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    frame.Count = frame.count  -- Masque expects .Count
    frame.count:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.count:SetJustifyH("RIGHT")
    
    -- Border texture for Masque
    frame.Border = frame:CreateTexture(nil, "OVERLAY")
    frame.Border:SetAllPoints(frame)
    frame.Border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.Border:SetBlendMode("ADD")
    frame.Border:SetAlpha(0)  -- Hidden, Masque controls this
    
    -- Proc glow overlay (using Blizzard's built-in glow style)
    frame.glowFrame = CreateFrame("Frame", frameName .. "_Glow", frame)
    frame.glowFrame:SetAllPoints()
    frame.glowFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
    frame.glowFrame:Hide()
    
    -- Create the glow texture (yellow spell activation border)
    frame.glowTexture = frame.glowFrame:CreateTexture(nil, "OVERLAY")
    frame.glowTexture:SetPoint("TOPLEFT", -8, 8)
    frame.glowTexture:SetPoint("BOTTOMRIGHT", 8, -8)
    frame.glowTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.glowTexture:SetBlendMode("ADD")
    frame.glowTexture:SetVertexColor(1, 1, 0.6, 0.8)
    
    -- Animated glow ants (the spinning border effect)
    frame.glowAnts = frame.glowFrame:CreateTexture(nil, "OVERLAY")
    frame.glowAnts:SetPoint("TOPLEFT", -4, 4)
    frame.glowAnts:SetPoint("BOTTOMRIGHT", 4, -4)
    frame.glowAnts:SetTexture("Interface\\Cooldown\\star4")
    frame.glowAnts:SetBlendMode("ADD")
    frame.glowAnts:SetVertexColor(1, 1, 0.5, 0.6)
    
    -- Animation group for the glow
    frame.glowAnim = frame.glowAnts:CreateAnimationGroup()
    frame.glowAnim:SetLooping("REPEAT")
    local rotation = frame.glowAnim:CreateAnimation("Rotation")
    rotation:SetDegrees(-360)
    rotation:SetDuration(4)
    
    -- Custom label (for accessibility / identification)
    frame.customLabel = frame:CreateFontString(nil, "OVERLAY")
    frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    frame.customLabel:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.customLabel:SetTextColor(1, 1, 1, 1)
    frame.customLabel:SetShadowOffset(1, -1)
    frame.customLabel:SetShadowColor(0, 0, 0, 1)
    frame.customLabel:SetDrawLayer("OVERLAY", 7)
    frame.customLabel:Hide()
    
    -- Store slot reference
    frame.slotIndex = slotIndex
    frame.trackerKey = "buffs"
    frame._TUI_useMasque = masqueEnabled
    
    -- Apply saved position or default
    local pos = GetHighlightPosition(slotIndex)
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        -- Default position - center with offset based on slot
        frame:SetPoint("CENTER", UIParent, "CENTER", -200 + (slotIndex * 60), -100)
    end
    
    -- Initially hidden
    frame:Hide()
    
    highlightFrames[slotIndex] = frame
    
    -- Register with LayoutMode for drag support
    if TUICD.LayoutMode and TUICD.LayoutMode.RegisterPerIconFrame then
        local displayName = "Buff Icon " .. slotIndex
        -- Try to get actual spell name from bridge
        local Bridge = TUICD.BuffIdentityBridge
        if Bridge then
            local spellID = Bridge:GetSpellIDForSlot(slotIndex)
            if spellID then
                local buffInfo = Bridge:GetBuffInfo(spellID)
                if buffInfo and buffInfo.name then
                    displayName = buffInfo.name
                else
                    pcall(function()
                        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                        if name and not issecretvalue(name) then
                            displayName = name
                        end
                    end)
                end
            end
        end
        TUICD.LayoutMode:RegisterPerIconFrame(frame, "buffs", slotIndex, displayName)
    end
    
    -- Add to Masque group if enabled
    if masqueEnabled then
        local masqueGroup = TUICD.Cooldowns:GetMasqueGroup("buffs")
        if masqueGroup then
            masqueGroup:AddButton(frame, {
                Icon = frame.icon,
                Cooldown = frame.cooldown,
                Count = frame.count,
                Border = frame.Border,
            })
            frame._TUI_MasqueGroup = "buffs"
            dprint("Added highlight frame to Masque group:", slotIndex)
        end
    end
    
    dprint("Created highlight frame for slot", slotIndex)
    
    return frame
end

-- ============================================================================
-- HIGHLIGHT FRAME UPDATE
-- ============================================================================

-- Parse aspect ratio string to get width/height multipliers
local function ParseAspectRatio(aspectStr, slotIndex, state)
    if not aspectStr or aspectStr == "1:1" then
        return 1, 1
    end
    
    -- Check for "custom" which uses per-slot custom values (keyed by spellID)
    if aspectStr == "custom" and slotIndex and state then
        local db = GetDB()
        local key = GetSettingsKey(slotIndex)
        local customW = db[state].customAspectW[key] or 1
        local customH = db[state].customAspectH[key] or 1
        return customW, customH
    end
    
    local w, h = aspectStr:match("(%d+):(%d+)")
    if w and h then
        return tonumber(w), tonumber(h)
    end
    return 1, 1
end

-- Apply aspect ratio to frame
local function ApplyAspectRatio(frame, size, aspectStr, slotIndex, state)
    local aspectW, aspectH = ParseAspectRatio(aspectStr, slotIndex, state)
    local width, height = size, size
    
    if aspectW > aspectH then
        -- Wide (e.g., 16:9)
        height = size * aspectH / aspectW
    elseif aspectH > aspectW then
        -- Tall (e.g., 9:16)
        width = size * aspectW / aspectH
    end
    
    frame:SetSize(width, height)
    
    -- Adjust texture coordinates to crop/zoom icon instead of stretching
    -- This makes non-square frames show a cropped portion of the icon
    if frame.icon and not frame._TUI_useMasque then
        local baseInset = 0.08  -- Standard WoW icon inset
        local texRange = 1 - (baseInset * 2)  -- 0.84
        
        local left, right, top, bottom = baseInset, 1 - baseInset, baseInset, 1 - baseInset
        
        if aspectW > aspectH then
            -- Wider than tall - crop top/bottom
            local cropFactor = aspectH / aspectW
            local vertRange = texRange * cropFactor
            local vertOffset = (texRange - vertRange) / 2
            top = baseInset + vertOffset
            bottom = 1 - baseInset - vertOffset
        elseif aspectH > aspectW then
            -- Taller than wide - crop left/right  
            local cropFactor = aspectW / aspectH
            local horizRange = texRange * cropFactor
            local horizOffset = (texRange - horizRange) / 2
            left = baseInset + horizOffset
            right = 1 - baseInset - horizOffset
        end
        
        frame.icon:SetTexCoord(left, right, top, bottom)
    end
end

-- ============================================================================
-- BUFF STATE ALERTS  (On Gained / On Expiring)
-- Fires glow and/or pulse effects at buff state transitions.
-- "On Start"  = buff gained   (inactive → active)
-- "On End"    = buff expiring (active → inactive)
-- ============================================================================

local BUFF_TRACKER_KEY = "buffs"

local function GetBuffAlertSetting(key)
    if not TUICD.Database then return nil end
    return TUICD.Database:GetTrackerSetting(BUFF_TRACKER_KEY, key)
end

-- Try to read remaining seconds for a buff (for pre-expiry warnings).
-- Returns nil when the value is secret or unavailable.
local function GetBuffRemainingSeconds(auraInstanceID)
    if not auraInstanceID then return nil end
    -- Method 1: DurationObject (Midnight primary)
    if C_UnitAuras and C_UnitAuras.GetUnitAuraDuration then
        local ok, dObj = pcall(C_UnitAuras.GetUnitAuraDuration, "player", auraInstanceID)
        if ok and dObj and dObj.GetRemainingDuration then
            local ok2, rem = pcall(dObj.GetRemainingDuration, dObj)
            if ok2 and rem then
                if issecretvalue and issecretvalue(rem) then return nil end
                if type(rem) == "number" and rem > 0 then return rem end
            end
        end
    end
    -- Method 2: AuraData fallback
    if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", auraInstanceID)
        if ok and ad then
            local exp = ad.expirationTime
            if exp and type(exp) == "number" then
                if issecretvalue and issecretvalue(exp) then return nil end
                local rem = exp - GetTime()
                if rem > 0 then return rem end
            end
        end
    end
    return nil
end

-- Create a getSetting closure for per-icon alerts keyed by spellID.
-- Returns a function(key) that reads from iconAlerts[spellID][key].
-- Compatible with PlayAlertGlow/PlayAlertPulse which expect getSetting(prefix..key).
local function MakePerIconAlertGetter(spellID)
    return function(key)
        return BuffHighlights:GetIconAlertSetting(spellID, key)
    end
end

-- Check if a spellID has any per-icon alerts enabled (quick bail-out).
local function HasAnyPerIconAlert(spellID)
    if not spellID then return false end
    local db = GetDB()
    if not db.iconAlerts then return false end
    local entry = db.iconAlerts[spellID]
    if not entry then return false end
    return entry["onStartGlowEnabled"] or entry["onStartPulseEnabled"]
        or entry["onEndGlowEnabled"] or entry["onEndPulseEnabled"]
        or false
end

-- ---------------------------------------------------------------------------
-- Alert glow frames  (lazily created, shared across On Start / On End)
-- These are SEPARATE from the proc-glow frames (frame.glowFrame).
-- ---------------------------------------------------------------------------

local function HideAlertGlows(frame)
    if frame._alertHideTimer then frame._alertHideTimer:Cancel(); frame._alertHideTimer = nil end
    frame._alertKeepAlive = nil
    if frame._alertPixelGlow then
        if frame._alertPixelGlow._pulseAG then frame._alertPixelGlow._pulseAG:Stop() end
        frame._alertPixelGlow:Hide()
    end
    if frame._alertShineGlow then
        if frame._alertShineGlow._pulseAG then frame._alertShineGlow._pulseAG:Stop() end
        frame._alertShineGlow:Hide()
    end
    if frame._alertSpellGlow then
        if frame._alertSpellGlow._pulseAG then frame._alertSpellGlow._pulseAG:Stop() end
        if frame._alertSpellGlow._antsAG then frame._alertSpellGlow._antsAG:Stop() end
        frame._alertSpellGlow:Hide()
    end
end

local function CancelAlertTimers(frame)
    local keys = {
        "_onStartGlowTimer", "_onStartPulseTimer",
        "_onEndGlowTimer",   "_onEndPulseTimer",
    }
    for _, k in ipairs(keys) do
        if frame[k] then frame[k]:Cancel(); frame[k] = nil end
    end
end

-- Play alert glow effect.  `prefix` is "onStart" or "onEnd".
local function PlayAlertGlow(frame, prefix, getSetting)
    if not frame then return end
    getSetting = getSetting or GetBuffAlertSetting
    local style     = getSetting(prefix .. "GlowStyle")     or "pixel"
    local r         = getSetting(prefix .. "GlowColorR")    or 1.0
    local g         = getSetting(prefix .. "GlowColorG")    or 0.82
    local b         = getSetting(prefix .. "GlowColorB")    or 0.0
    local speed     = getSetting(prefix .. "GlowSpeed")     or 0.6
    local intensity = getSetting(prefix .. "GlowIntensity") or 0.8
    local thickness = getSetting(prefix .. "GlowThickness") or 2
    local glowScale = getSetting(prefix .. "GlowScale")     or 1.0
    local duration  = getSetting(prefix .. "GlowDuration")  or 3.0

    HideAlertGlows(frame)

    if style == "pixel" then
        -- Pixel border ---------------------------------------------------
        if not frame._alertPixelGlow then
            local gf = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            gf:SetFrameLevel(frame:GetFrameLevel() + 6)
            local ag = gf:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local alpha = ag:CreateAnimation("Alpha")
            alpha:SetSmoothing("IN_OUT")
            gf._pulseAG    = ag
            gf._pulseAlpha = alpha
            frame._alertPixelGlow = gf
        end
        local gf = frame._alertPixelGlow
        local t = math.max(1, math.floor(thickness))
        gf:ClearAllPoints()
        gf:SetPoint("TOPLEFT", -t, t)
        gf:SetPoint("BOTTOMRIGHT", t, -t)
        gf:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = t })
        gf:SetBackdropBorderColor(r, g, b, intensity)
        gf._pulseAlpha:SetFromAlpha(intensity)
        gf._pulseAlpha:SetToAlpha(math.max(0.05, intensity * 0.2))
        gf._pulseAlpha:SetDuration(speed)
        gf:Show()
        gf._pulseAG:Play()

    elseif style == "shine" then
        -- Shine flash -----------------------------------------------------
        if not frame._alertShineGlow then
            local sh = frame:CreateTexture(nil, "OVERLAY")
            sh:SetAllPoints()
            sh:SetBlendMode("ADD")
            sh:SetDrawLayer("OVERLAY", 6)
            local ag = sh:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local alpha = ag:CreateAnimation("Alpha")
            alpha:SetSmoothing("IN_OUT")
            sh._pulseAG    = ag
            sh._pulseAlpha = alpha
            frame._alertShineGlow = sh
        end
        local sh = frame._alertShineGlow
        sh:SetColorTexture(r, g, b, intensity)
        sh._pulseAlpha:SetFromAlpha(intensity)
        sh._pulseAlpha:SetToAlpha(math.max(0.02, intensity * 0.1))
        sh._pulseAlpha:SetDuration(speed)
        sh:Show()
        sh._pulseAG:Play()

    else  -- "glow" (SpellActivation style)
        if not frame._alertSpellGlow then
            local glow = CreateFrame("Frame", nil, frame)
            glow:SetFrameLevel(frame:GetFrameLevel() + 6)
            local inner = glow:CreateTexture(nil, "ARTWORK")
            inner:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
            inner:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
            inner:SetBlendMode("ADD")
            inner:SetDrawLayer("ARTWORK", 1)
            glow._inner = inner
            local outer = glow:CreateTexture(nil, "ARTWORK")
            outer:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
            outer:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
            outer:SetBlendMode("ADD")
            outer:SetDrawLayer("ARTWORK", 0)
            glow._outer = outer
            local ants = glow:CreateTexture(nil, "OVERLAY")
            ants:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
            ants:SetBlendMode("ADD")
            ants:SetDrawLayer("OVERLAY", 5)
            glow._ants = ants
            local antsAG = ants:CreateAnimationGroup()
            antsAG:SetLooping("REPEAT")
            local rot = antsAG:CreateAnimation("Rotation")
            rot:SetDegrees(-360)
            rot:SetDuration(12)
            glow._antsAG = antsAG
            local pulseAG = glow:CreateAnimationGroup()
            pulseAG:SetLooping("BOUNCE")
            local alpha = pulseAG:CreateAnimation("Alpha")
            alpha:SetFromAlpha(1)
            alpha:SetToAlpha(0.5)
            alpha:SetSmoothing("IN_OUT")
            glow._pulseAG    = pulseAG
            glow._pulseAlpha = alpha
            frame._alertSpellGlow = glow
        end
        local glow = frame._alertSpellGlow
        local scale = glowScale or 1.0
        local w, h = frame:GetSize()
        local pad = (w * 0.4) * scale
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -pad,  pad)
        glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  pad, -pad)
        glow._inner:SetAllPoints(glow)
        glow._outer:SetAllPoints(glow)
        glow._ants:SetAllPoints(glow)
        glow._inner:SetVertexColor(r, g, b, 1)
        glow._outer:SetVertexColor(r, g, b, 0.6)
        glow._ants:SetVertexColor(r, g, b, 0.7)
        glow._pulseAlpha:SetDuration(speed)
        glow:Show()
        glow._antsAG:Play()
        glow._pulseAG:Play()
    end

    -- Auto-hide after duration
    frame._alertHideTimer = C_Timer.NewTimer(duration, function()
        frame._alertHideTimer = nil
        HideAlertGlows(frame)
    end)
end

-- Play alert pulse effect.  `prefix` is "onStart" or "onEnd".
local function PlayAlertPulse(frame, prefix, getSetting)
    if not frame then return end
    getSetting = getSetting or GetBuffAlertSetting
    local pulseScale    = getSetting(prefix .. "PulseScale")    or 1.3
    local pulseDuration = getSetting(prefix .. "PulseDuration") or 0.4
    local pulseCount    = getSetting(prefix .. "PulseCount")    or 3

    -- Use existing pulse animation group or create one
    if not frame._alertPulseAG then
        local ag = frame:CreateAnimationGroup()
        local grow = ag:CreateAnimation("Scale")
        grow:SetOrder(1)
        grow:SetSmoothing("IN_OUT")
        local shrink = ag:CreateAnimation("Scale")
        shrink:SetOrder(2)
        shrink:SetSmoothing("IN_OUT")
        ag._grow   = grow
        ag._shrink = shrink
        frame._alertPulseAG = ag
    end

    local ag = frame._alertPulseAG
    ag:Stop()

    ag._grow:SetScaleFrom(1, 1)
    ag._grow:SetScaleTo(pulseScale, pulseScale)
    ag._grow:SetDuration(pulseDuration / 2)

    ag._shrink:SetScaleFrom(pulseScale, pulseScale)
    ag._shrink:SetScaleTo(1, 1)
    ag._shrink:SetDuration(pulseDuration / 2)

    local played = 0
    ag:SetScript("OnFinished", function(self)
        played = played + 1
        if played < pulseCount then
            self:Play()
        end
    end)
    ag:Play()
end

-- ---------------------------------------------------------------------------
-- Scheduling helpers  (mirrors MultiTrackerFrames pattern)
-- ---------------------------------------------------------------------------

local function ScheduleAlertGlow(frame, prefix, timing, remaining, timerKey, getSetting)
    if frame[timerKey] then frame[timerKey]:Cancel(); frame[timerKey] = nil end

    if timing < 0 and remaining then
        -- Negative: fire |timing| seconds before the event
        local delay = remaining + timing  -- e.g. 30 + (-5) = 25s
        if delay <= 0 then
            PlayAlertGlow(frame, prefix, getSetting)
        else
            frame[timerKey] = C_Timer.NewTimer(delay, function()
                frame[timerKey] = nil
                PlayAlertGlow(frame, prefix, getSetting)
            end)
        end
    elseif timing == 0 then
        PlayAlertGlow(frame, prefix, getSetting)
    else
        -- Positive: fire timing seconds after the event
        frame[timerKey] = C_Timer.NewTimer(timing, function()
            frame[timerKey] = nil
            PlayAlertGlow(frame, prefix, getSetting)
        end)
    end
end

local function ScheduleAlertPulse(frame, prefix, timing, remaining, timerKey, getSetting)
    if frame[timerKey] then frame[timerKey]:Cancel(); frame[timerKey] = nil end

    if timing < 0 and remaining then
        local delay = remaining + timing
        if delay <= 0 then
            PlayAlertPulse(frame, prefix, getSetting)
        else
            frame[timerKey] = C_Timer.NewTimer(delay, function()
                frame[timerKey] = nil
                PlayAlertPulse(frame, prefix, getSetting)
            end)
        end
    elseif timing == 0 then
        PlayAlertPulse(frame, prefix, getSetting)
    else
        frame[timerKey] = C_Timer.NewTimer(timing, function()
            frame[timerKey] = nil
            PlayAlertPulse(frame, prefix, getSetting)
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Transition handlers
-- ---------------------------------------------------------------------------

-- Called when a buff is GAINED (inactive → active)
-- getSetting: function(key) returning setting value (allows tracker-level or per-icon)
local function OnBuffGained(frame, slotIndex, auraInstanceID, getSetting)
    getSetting = getSetting or GetBuffAlertSetting
    CancelAlertTimers(frame)
    HideAlertGlows(frame)

    -- ── On Start effects ──
    if getSetting("onStartGlowEnabled") then
        local timing = getSetting("onStartGlowTiming") or 0
        -- For On Start, negative timing doesn't apply (can't predict gain).
        -- Clamp to 0 minimum.
        if timing < 0 then timing = 0 end
        ScheduleAlertGlow(frame, "onStart", timing, nil, "_onStartGlowTimer", getSetting)
    end
    if getSetting("onStartPulseEnabled") then
        local timing = getSetting("onStartPulseTiming") or 0
        if timing < 0 then timing = 0 end
        ScheduleAlertPulse(frame, "onStart", timing, nil, "_onStartPulseTimer", getSetting)
    end

    -- ── On End effects with NEGATIVE timing (early warning before expiry) ──
    -- Schedule now using remaining duration so timer fires before buff drops.
    local remaining = GetBuffRemainingSeconds(auraInstanceID)
    if remaining and remaining > 0 then
        if getSetting("onEndGlowEnabled") then
            local timing = getSetting("onEndGlowTiming") or 0
            if timing < 0 then
                ScheduleAlertGlow(frame, "onEnd", timing, remaining, "_onEndGlowTimer", getSetting)
            end
        end
        if getSetting("onEndPulseEnabled") then
            local timing = getSetting("onEndPulseTiming") or 0
            if timing < 0 then
                ScheduleAlertPulse(frame, "onEnd", timing, remaining, "_onEndPulseTimer", getSetting)
            end
        end
    end
end

-- Called when a buff is LOST (active → inactive)
local function OnBuffLost(frame, slotIndex, getSetting)
    getSetting = getSetting or GetBuffAlertSetting
    -- Cancel any pending early-warning timers (they're no longer relevant)
    if frame._onEndGlowTimer then frame._onEndGlowTimer:Cancel(); frame._onEndGlowTimer = nil end
    if frame._onEndPulseTimer then frame._onEndPulseTimer:Cancel(); frame._onEndPulseTimer = nil end

    -- ── On End effects ──
    -- Always fire when the buff actually drops:
    --   timing >= 0: fire with that delay (0 = immediate, positive = delayed)
    --   timing < 0:  early-warning window has passed, fire immediately as fallback
    --                (the early-warning timer from OnBuffGained may or may not have fired)
    local hasOnEnd = false
    local maxDuration = 0
    if getSetting("onEndGlowEnabled") then
        hasOnEnd = true
        local timing = getSetting("onEndGlowTiming") or 0
        local effectiveDelay = math.max(timing, 0)
        local dur = (getSetting("onEndGlowDuration") or 3.0) + effectiveDelay
        if dur > maxDuration then maxDuration = dur end
        ScheduleAlertGlow(frame, "onEnd", effectiveDelay, nil, "_onEndGlowTimer", getSetting)
    end
    if getSetting("onEndPulseEnabled") then
        hasOnEnd = true
        local timing = getSetting("onEndPulseTiming") or 0
        local effectiveDelay = math.max(timing, 0)
        local pulseDur = (getSetting("onEndPulseDuration") or 0.4) * (getSetting("onEndPulseCount") or 3) + effectiveDelay
        if pulseDur > maxDuration then maxDuration = pulseDur end
        ScheduleAlertPulse(frame, "onEnd", effectiveDelay, nil, "_onEndPulseTimer", getSetting)
    end
    -- Keep the frame alive so On End effects are visible even if inactive state is hidden
    if hasOnEnd and maxDuration > 0 then
        frame._alertKeepAlive = GetTime() + maxDuration + 0.1
    end
end

-- ---------------------------------------------------------------------------
-- Exposed alert API  (for Cooldowns.lua to fire tracker-level alerts on main icons)
-- ---------------------------------------------------------------------------

-- Fire tracker-level buff gained alert on any frame (reads tracker settings)
function BuffHighlights:FireTrackerAlertGained(frame, auraInstanceID)
    if not frame then return end
    pcall(OnBuffGained, frame, nil, auraInstanceID, GetBuffAlertSetting)
end

-- Fire tracker-level buff lost alert on any frame (reads tracker settings)
function BuffHighlights:FireTrackerAlertLost(frame)
    if not frame then return end
    pcall(OnBuffLost, frame, nil, GetBuffAlertSetting)
end

-- Cleanup helpers (exposed for external callers)
function BuffHighlights:HideFrameAlertGlows(frame)
    if frame then HideAlertGlows(frame) end
end

function BuffHighlights:CancelFrameAlertTimers(frame)
    if frame then CancelAlertTimers(frame) end
end

-- ============================================================================
-- END BUFF STATE ALERTS
-- ============================================================================

local function UpdateHighlightFrame(slotIndex)
    local frame = highlightFrames[slotIndex]
    if not frame then return end
    
    -- Update sweep and countdown text settings (per-icon overrides tracker-level)
    if frame.cooldown then
        local showSweep = GetShowSweep(slotIndex)  -- Per-icon setting
        local showCountdownText = GetShowCountdownText(slotIndex)  -- Per-icon setting
        
        -- Fall back to tracker-level settings if per-icon not set
        if showSweep == nil and TUICD.Database then
            local sweepSetting = TUICD.Database:GetTrackerSetting("buffs", "showSweep")
            showSweep = (sweepSetting ~= nil) and sweepSetting or true
        end
        if showCountdownText == nil and TUICD.Database then
            local countdownSetting = TUICD.Database:GetTrackerSetting("buffs", "showCountdownText")
            showCountdownText = (countdownSetting ~= nil) and countdownSetting or true
        end
        
        -- Default to true if still nil
        if showSweep == nil then showSweep = true end
        if showCountdownText == nil then showCountdownText = true end
        
        -- Update stored values for hooks
        frame.cooldown._TUI_showSweep = showSweep
        frame.cooldown._TUI_showCountdownText = showCountdownText
        
        -- Apply immediately
        pcall(function()
            frame.cooldown:SetDrawSwipe(showSweep)
            frame.cooldown:SetHideCountdownNumbers(not showCountdownText)
        end)
    end
    
    if not IsHighlightEnabled(slotIndex) then
        CancelAlertTimers(frame)
        HideAlertGlows(frame)
        frame._alertLastActive = nil
        frame:Hide()
        return
    end
    
    -- =========================================================================
    -- FIND SOURCE ICON from Blizzard's tracker
    -- Use same method as GetBuffSlotInfo for consistent ordering
    -- =========================================================================
    
    local icons
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer then
            icons = Cooldowns.GetOrderedIcons(viewer, "buffs")
        else
            icons = {}
        end
    else
        icons = CollectBuffIcons()
    end
    
    local sourceIcon = icons[slotIndex]
    
    -- Check if Layout mode is active
    local isLayoutMode = false
    local layoutContainer = _G["TweaksUI_LayoutContainer"]
    if layoutContainer and layoutContainer:IsShown() then
        isLayoutMode = true
    end
    
    -- Get texture from source or cache (keyed by spellID via settings key)
    local settingsKey = GetSettingsKey(slotIndex)
    local cachedTex = cachedTextures[settingsKey]
    if sourceIcon and not cachedTex then
        local textureObj = sourceIcon.Icon or sourceIcon.icon
        if textureObj then
            pcall(function()
                cachedTex = textureObj:GetTexture()
                if cachedTex then
                    cachedTextures[settingsKey] = cachedTex
                end
            end)
        end
    end
    
    -- Determine if buff is active
    -- PRIORITY 1: Use BuffIdentityBridge (combat-safe, always non-secret)
    local isActive = false
    local auraInstanceID = nil
    local Bridge = TUICD.BuffIdentityBridge
    if Bridge then
        local spellID = Bridge:GetSpellIDForSlot(slotIndex)
        if spellID then
            isActive = Bridge:IsBuffActive(spellID)
            auraInstanceID = Bridge:GetAuraIDForSpellID(spellID)
        end
    end
    -- PRIORITY 2: Fallback to source icon's auraInstanceID (pre-bridge behavior)
    if not isActive and not Bridge and sourceIcon then
        pcall(function()
            auraInstanceID = sourceIcon.auraInstanceID
            isActive = (auraInstanceID ~= nil)
        end)
    end
    
    -- No source icon and no cache - show placeholder in layout mode
    if not sourceIcon and not cachedTex then
        if isLayoutMode then
            local size = GetHighlightSize(slotIndex, "active")
            local aspectRatio = GetHighlightAspectRatio(slotIndex, "active")
            ApplyAspectRatio(frame, size, aspectRatio, slotIndex, "active")
            frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            frame.icon:SetDesaturated(true)
            frame.count:Hide()
            frame.cooldown:Clear()
            frame._lastAuraInstanceID = nil
            if frame.glowFrame then frame.glowFrame:Hide() end
            frame:SetAlpha(0.5)
            frame:Show()
        else
            frame:Hide()
        end
        return
    end
    
    -- Get texture from source icon for display
    local displayTex = cachedTex
    if sourceIcon and not displayTex then
        local textureObj = sourceIcon.Icon or sourceIcon.icon
        if textureObj then
            pcall(function() displayTex = textureObj:GetTexture() end)
        end
    end
    
    -- Determine current state based on source icon's auraInstanceID
    local currentState = isActive and "active" or "inactive"
    local showThisState = GetShowState(slotIndex, currentState)
    
    -- =========================================================================
    -- PER-ICON ALERT TRANSITION DETECTION (Phase 3)
    -- Tracker-level alerts fire on main tracker icons via Cooldowns.lua.
    -- Per-icon alerts fire here on highlight frames using iconAlerts[spellID].
    -- =========================================================================
    local wasActive = frame._alertLastActive
    frame._alertLastActive = isActive
    
    -- Only fire on actual transitions (wasActive must be non-nil to avoid
    -- first-load false triggers).  Skip during layout mode.
    if wasActive ~= nil and wasActive ~= isActive and not isLayoutMode then
        -- Get spellID from bridge (per-icon alerts are keyed by spellID)
        local alertSpellID = nil
        if Bridge then
            alertSpellID = Bridge:GetSpellIDForSlot(slotIndex)
        end
        
        if alertSpellID and HasAnyPerIconAlert(alertSpellID) then
            local getter = MakePerIconAlertGetter(alertSpellID)
            if isActive then
                -- inactive → active = buff gained
                pcall(OnBuffGained, frame, slotIndex, auraInstanceID, getter)
            else
                -- active → inactive = buff lost
                pcall(OnBuffLost, frame, slotIndex, getter)
            end
        end
    end
    
    -- During layout mode, always show (using active state settings)
    if isLayoutMode then
        local size = GetHighlightSize(slotIndex, "active")
        local aspectRatio = GetHighlightAspectRatio(slotIndex, "active")
        ApplyAspectRatio(frame, size, aspectRatio, slotIndex, "active")
        
        if displayTex then
            frame.icon:SetTexture(displayTex)
        else
            frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        
        -- Show with slight desaturation if current state wouldn't normally show
        if not showThisState then
            frame.icon:SetDesaturated(true)
            frame:SetAlpha(0.4)
        else
            local saturated = GetHighlightSaturation(slotIndex, currentState)
            local opacity = GetHighlightOpacity(slotIndex, currentState)
            frame.icon:SetDesaturated(not saturated)
            frame:SetAlpha(opacity)
        end
        
        frame.count:Hide()
        frame.cooldown:Clear()
        frame._lastAuraInstanceID = nil
        if frame.glowFrame then frame.glowFrame:Hide() end
        frame:Show()
        return
    end
    
    -- Normal mode: only show if this state is enabled
    -- Exception: keep frame alive if On End alerts are still playing
    if not showThisState then
        local keepAlive = frame._alertKeepAlive and (GetTime() < frame._alertKeepAlive)
        if not keepAlive then
            frame._alertKeepAlive = nil
            frame:Hide()
            return
        end
        -- On End alert active: keep frame visible with inactive appearance
        -- (use active state size so the glow has something to attach to)
        local size = GetHighlightSize(slotIndex, "active")
        local aspectRatio = GetHighlightAspectRatio(slotIndex, "active")
        ApplyAspectRatio(frame, size, aspectRatio, slotIndex, "active")
        if displayTex then
            frame.icon:SetTexture(displayTex)
        end
        frame.icon:SetDesaturated(true)
        frame:SetAlpha(0.6)
        frame.count:Hide()
        frame.cooldown:Clear()
        frame:Show()
        return
    end
    
    -- Get state-specific settings
    local size = GetHighlightSize(slotIndex, currentState)
    local opacity = GetHighlightOpacity(slotIndex, currentState)
    local saturated = GetHighlightSaturation(slotIndex, currentState)
    local aspectRatio = GetHighlightAspectRatio(slotIndex, currentState)
    
    -- Apply size and aspect ratio
    ApplyAspectRatio(frame, size, aspectRatio, slotIndex, currentState)
    
    -- Update icon texture
    if displayTex then
        frame.icon:SetTexture(displayTex)
    else
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    -- Apply saturation and opacity
    frame.icon:SetDesaturated(not saturated)
    frame:SetAlpha(opacity)
    
    -- =========================================================================
    -- COUNT - Use Midnight API or pass through from source icon
    -- CRITICAL: No conditionals on returned values - they may be secret
    -- Just pass directly to SetText and let Blizzard handle it
    -- =========================================================================
    
    -- Method 1: Use C_UnitAuras.GetAuraApplicationDisplayCount API (Midnight)
    -- Pass directly to SetText - NO conditionals on the result
    if auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
        pcall(function()
            -- minDisplayCount of 2 means don't show "1" (only show 2+)
            frame.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount("player", auraInstanceID, 2))
            frame.count:Show()
        end)
    elseif sourceIcon then
        -- Method 2: Source icon's Count FontString pass-through (fallback)
        local sourceCountFS = sourceIcon.Count or sourceIcon.count
        
        -- Try icon's children if not found directly
        if not sourceCountFS and sourceIcon.GetChildren then
            pcall(function()
                for i = 1, sourceIcon:GetNumChildren() do
                    local child = select(i, sourceIcon:GetChildren())
                    if child then
                        local childCount = child.Count or child.count
                        if childCount then
                            sourceCountFS = childCount
                            break
                        end
                    end
                end
            end)
        end
        
        -- Pass through from source FontString - NO conditionals on GetText result
        if sourceCountFS and sourceCountFS.GetText then
            pcall(function()
                frame.count:SetText(sourceCountFS:GetText())
            end)
            -- Use SetAlphaFromBoolean for visibility (handles secret booleans)
            if sourceCountFS.IsShown and frame.count.SetAlphaFromBoolean then
                pcall(function()
                    frame.count:SetAlphaFromBoolean(sourceCountFS:IsShown(), 1, 0)
                end)
            end
            frame.count:Show()
        else
            frame.count:SetText("")
            frame.count:Hide()
        end
    else
        frame.count:SetText("")
        frame.count:Hide()
    end
    
    -- =========================================================================
    -- COOLDOWN - Mirror directly from source icon's Cooldown frame
    -- Primary: Copy Duration Object from source cooldown frame (works in combat)
    -- Fallback: Use C_UnitAuras.GetUnitAuraDuration (may fail when auras secret)
    -- NOTE: Do NOT call SetAlpha(1) - CooldownFrameTemplate manages its own
    -- alpha in Midnight (Beta 6: uses alpha secret aspect for show/hide)
    -- =========================================================================
    if sourceIcon and frame.cooldown then
        local sourceCooldown = sourceIcon.Cooldown or sourceIcon.cooldown
        if sourceCooldown then
            sourceCooldown._TUI_BuffHL_SlotIndex = slotIndex
            
            -- SetCooldownFromDurationObject creates a SELF-ANIMATING spiral.
            -- We only need to set it once when a new buff appears — re-setting
            -- every 0.25s tick causes flicker when GetCooldownDuration returns
            -- nil or zero mid-update (clearIfZero wipes the animation).
            -- Track by auraInstanceID so we only set once per buff application.
            local currentAuraID = sourceIcon.auraInstanceID
            if currentAuraID and currentAuraID ~= frame._lastAuraInstanceID then
                local cooldownSet = false
                
                -- Method 1 (Primary): Copy duration directly from source cooldown frame
                -- Works in combat by reading from Blizzard's already-set cooldown
                if sourceCooldown.GetCooldownDuration and frame.cooldown.SetCooldownFromDurationObject then
                    pcall(function()
                        local durationObj = sourceCooldown:GetCooldownDuration()
                        if durationObj then
                            frame.cooldown:SetCooldownFromDurationObject(durationObj)
                            cooldownSet = true
                        end
                    end)
                end
                
                -- Method 2 (Fallback): Use C_UnitAuras.GetUnitAuraDuration API
                -- Works out of combat; may error when aura access is secret
                if not cooldownSet then
                    if currentAuraID and C_UnitAuras and C_UnitAuras.GetUnitAuraDuration 
                       and frame.cooldown.SetCooldownFromDurationObject then
                        pcall(function()
                            local durationObj = C_UnitAuras.GetUnitAuraDuration("player", currentAuraID)
                            if durationObj then
                                frame.cooldown:SetCooldownFromDurationObject(durationObj)
                                cooldownSet = true
                            end
                        end)
                    end
                end
                
                -- Only update tracking if we successfully set the cooldown
                if cooldownSet then
                    frame._lastAuraInstanceID = currentAuraID
                end
                -- If both methods failed this tick, don't update tracking —
                -- next tick will try again for this same auraInstanceID
            end
            -- If currentAuraID matches _lastAuraInstanceID, the spiral is
            -- already animating correctly — do nothing.
            -- If currentAuraID is nil, buff has no aura tracking — also do nothing,
            -- the outer elseif handles clearing when sourceIcon is gone entirely.
        end
    elseif frame.cooldown then
        frame.cooldown:Clear()
        frame._lastAuraInstanceID = nil
    end
    
    -- Copy glow state from source icon (proc/spell activation glow)
    -- =========================================================================
    local showGlow = false
    
    -- First, check if per-icon proc glow is enabled (default true)
    local db = GetDB()
    local procGlowKey = GetSettingsKey(slotIndex)
    local procGlowEnabled = db.showProcGlow and db.showProcGlow[procGlowKey]
    if procGlowEnabled == nil then procGlowEnabled = true end
    
    if procGlowEnabled then
        -- Method 1: Direct API check using IsSpellOverlayed (most reliable)
        -- Get spellID from Bridge (combat-safe) or source icon (fallback)
        local spellID = nil
        if Bridge then
            spellID = Bridge:GetSpellIDForSlot(slotIndex)
        end
        if not spellID and sourceIcon then
            pcall(function()
                spellID = sourceIcon.spellID or sourceIcon.SpellID or sourceIcon.spellId
            end)
        end
        
        if spellID and IsSpellOverlayed then
            pcall(function()
                if IsSpellOverlayed(spellID) then
                    showGlow = true
                end
            end)
        end
        
        -- Method 2: Check source icon's overlay frames (fallback)
        if not showGlow and sourceIcon then
            pcall(function()
                -- Check for overlay glow frame (standard Blizzard glow)
                if sourceIcon.overlay and sourceIcon.overlay:IsShown() then
                    showGlow = true
                elseif sourceIcon.SpellActivationAlert and sourceIcon.SpellActivationAlert:IsShown() then
                    showGlow = true
                elseif sourceIcon.OverlayGlow and sourceIcon.OverlayGlow:IsShown() then
                    showGlow = true
                -- Check for children that might be glow frames
                elseif sourceIcon.GetChildren then
                    for i = 1, sourceIcon:GetNumChildren() do
                        local child = select(i, sourceIcon:GetChildren())
                        if child and child:IsShown() then
                            local name = child:GetName() or ""
                            if name:find("Glow") or name:find("Overlay") or name:find("Activation") then
                                showGlow = true
                                break
                            end
                        end
                    end
                end
            end)
        end
    end
    
    -- Apply glow state to our frame
    if frame.glowFrame then
        if showGlow then
            frame.glowFrame:Show()
            if frame.glowAnim and not frame.glowAnim:IsPlaying() then
                frame.glowAnim:Play()
            end
        else
            frame.glowFrame:Hide()
            if frame.glowAnim and frame.glowAnim:IsPlaying() then
                frame.glowAnim:Stop()
            end
        end
    end
    
    -- Apply text scale, color, and offset settings
    local cooldownTextScale = GetCooldownTextScale(slotIndex)
    local cooldownTextColor = GetCooldownTextColor(slotIndex)
    local cooldownTextOffsetX = GetCooldownTextOffsetX(slotIndex)
    local cooldownTextOffsetY = GetCooldownTextOffsetY(slotIndex)
    local cooldownTextAnchor = GetCooldownTextAnchor(slotIndex)
    local countTextScale = GetCountTextScale(slotIndex)
    local countTextColor = GetCountTextColor(slotIndex)
    local countTextOffsetX = GetCountTextOffsetX(slotIndex)
    local countTextOffsetY = GetCountTextOffsetY(slotIndex)
    local countTextAnchor = GetCountTextAnchor(slotIndex)
    
    -- Scale, color, and offset cooldown text (countdown numbers on the cooldown spiral)
    if frame.cooldown then
        pcall(function()
            -- Try to find the countdown text in the cooldown frame
            local cdText = frame.cooldown.Text or frame.cooldown.text
            if not cdText then
                -- Search regions for FontString
                for i = 1, frame.cooldown:GetNumRegions() do
                    local region = select(i, frame.cooldown:GetRegions())
                    if region and region:GetObjectType() == "FontString" then
                        cdText = region
                        break
                    end
                end
            end
            
            if cdText then
                if cdText.GetFont then
                    local fontPath, _, fontFlags = cdText:GetFont()
                    if fontPath then
                        local baseSize = 14  -- Base font size for cooldown text
                        cdText:SetFont(fontPath, baseSize * cooldownTextScale, fontFlags or "OUTLINE")
                    end
                end
                if cdText.SetTextColor then
                    cdText:SetTextColor(cooldownTextColor[1] or 1, cooldownTextColor[2] or 1, cooldownTextColor[3] or 1, cooldownTextColor[4] or 1)
                end
                -- Apply anchor and offset
                if cdText.ClearAllPoints then
                    cdText:ClearAllPoints()
                    cdText:SetPoint(cooldownTextAnchor, frame.cooldown, cooldownTextAnchor, cooldownTextOffsetX, cooldownTextOffsetY)
                end
            end
        end)
    end
    
    -- Scale, color, and offset count text (stack/charge numbers)
    if frame.count then
        pcall(function()
            local fontPath, _, fontFlags = frame.count:GetFont()
            if fontPath then
                local baseSize = 12  -- Base font size for count text
                frame.count:SetFont(fontPath, baseSize * countTextScale, fontFlags or "OUTLINE")
            end
            frame.count:SetTextColor(countTextColor[1] or 1, countTextColor[2] or 1, countTextColor[3] or 1, countTextColor[4] or 1)
            -- Apply anchor and offset
            frame.count:ClearAllPoints()
            frame.count:SetPoint(countTextAnchor, frame, countTextAnchor, countTextOffsetX, countTextOffsetY)
        end)
    end
    
    -- Update custom label
    if frame.customLabel then
        local labelEnabled = GetLabelEnabled(slotIndex)
        local labelText = GetLabelText(slotIndex)
        local fontSize = GetLabelFontSize(slotIndex)
        local labelColor = GetLabelColor(slotIndex)
        local offsetX = GetLabelOffsetX(slotIndex)
        local offsetY = GetLabelOffsetY(slotIndex)
        local labelAnchor = GetLabelAnchor(slotIndex)
        
        if labelEnabled and labelText and labelText ~= "" then
            frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            frame.customLabel:SetText(labelText)
            frame.customLabel:SetTextColor(labelColor[1] or 1, labelColor[2] or 1, labelColor[3] or 1, labelColor[4] or 1)
            frame.customLabel:ClearAllPoints()
            frame.customLabel:SetPoint(labelAnchor, frame, labelAnchor, offsetX, offsetY)
            frame.customLabel:Show()
        else
            frame.customLabel:Hide()
        end
    end
    
    -- Notify dock if this icon is docked (dock will re-layout based on visibility)
    local dockAssignment = GetDockAssignment(slotIndex)
    if dockAssignment and TUICD.Docks then
        TUICD.Docks:NotifyIconUpdate("buffs", slotIndex)
    end
    
    -- Check tracker visibility conditions (combat, group, instance, etc.)
    -- before showing the frame
    if ShouldHighlightBeVisible() then
        frame:Show()
    else
        frame:Hide()
    end
end

local function UpdateAllHighlights()
    local db = GetDB()
    -- Iterate by slot position (frame space), not by db keys (which are spellIDs after migration)
    local slotCount = GetBuffSlotCount()
    for slotIndex = 1, math.max(slotCount, 20) do
        if IsHighlightEnabled(slotIndex) then
            -- Ensure frame exists
            if not highlightFrames[slotIndex] then
                pcall(CreateHighlightFrame, slotIndex)
            end
            -- Use pcall to prevent combat errors from breaking the ticker
            local success, err = pcall(UpdateHighlightFrame, slotIndex)
            if not success and debugMode then
                dprint("UpdateHighlightFrame error for slot " .. slotIndex .. ": " .. tostring(err))
            end
        end
    end
end

-- ============================================================================
-- LAYOUT INTEGRATION
-- ============================================================================

local layoutWrappers = {}  -- [slotIndex] = wrapper

local function CreateLayoutWrapper(slotIndex)
    local frame = highlightFrames[slotIndex]
    if not frame then return nil end
    
    local wrapperId = "BuffHighlight_" .. slotIndex
    
    local wrapper = {
        id = wrapperId,
        name = "Buff Highlight " .. slotIndex,
        category = "Cooldowns",
        frame = frame,
        hideSizeMatching = true,  -- Don't show "Match Size to Parent" options for Per-Icon frames
        defaultPosition = {
            point = "CENTER",
            x = -200 + (slotIndex * 60),
            y = -100,
        },
        contentFrames = {},
        
        onPositionChanged = function(self, point, relFrame, relPoint, x, y)
            -- Skip if docked - dock controls position
            if GetDockAssignment(slotIndex) then return end
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point, x, y)
            SetHighlightPosition(slotIndex, point, point, x, y)
        end,
        
        -- TUIFrame API
        GetPosition = function(self)
            local point, relTo, relPoint, x, y = frame:GetPoint(1)
            return { point = point, relFrame = relTo, relPoint = relPoint, x = x, y = y }
        end,
        
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            -- Skip if docked - dock controls position
            if GetDockAssignment(slotIndex) then return end
            frame:ClearAllPoints()
            frame:SetPoint(point, relFrame or UIParent, relPoint or point, x or 0, y or 0)
            if self.onPositionChanged then
                self:onPositionChanged(point, relFrame, relPoint, x, y)
            end
        end,
        
        LoadSaveData = function(self, data)
            if not data then return end
            local point = data.point or "CENTER"
            self:SetPosition(point, UIParent, point, data.x, data.y)
            if data.scale then
                self:SetScale(data.scale)
            end
        end,
        
        SetScale = function(self, scale)
            if frame and scale then
                frame:SetScale(scale)
            end
        end,
        
        GetScale = function(self)
            return frame:GetScale() or 1
        end,
        
        GetSize = function(self)
            return frame:GetSize()
        end,
        
        SetSize = function(self, width, height)
            -- For buff highlights, size changes should go through aspect ratio
            -- Just apply directly for now
            if frame and width and height then
                frame:SetSize(width, height)
            end
        end,
        
        IsShown = function(self)
            -- Always report as shown during layout mode so overlay appears
            local layoutContainer = _G["TweaksUI_LayoutContainer"]
            if layoutContainer and layoutContainer:IsShown() then
                return true
            end
            return frame and frame:IsShown()
        end,
        
        GetSaveData = function(self)
            local left = frame:GetLeft()
            local bottom = frame:GetBottom()
            if not left or not bottom then
                local point, _, _, x, y = frame:GetPoint(1)
                return {
                    point = point or "CENTER",
                    x = x or 0,
                    y = y or 0,
                    scale = self:GetScale(),
                }
            end
            return {
                point = "BOTTOMLEFT",
                x = left,
                y = bottom,
                scale = self:GetScale(),
            }
        end,
        
        GetSnapTarget = function(self, tolerance)
            local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
            if not FlyPaper then return nil end
            tolerance = tolerance or 15
            local point, relFrame, relPoint, x, y = FlyPaper.GetBestAnchorForGroup(
                frame,
                "TUICD",
                tolerance
            )
            if point and relFrame then
                return relFrame, point, relPoint, x, y
            end
            return nil
        end,
        
        -- Size locking
        sizeLocked = false,
        SetSizeLocked = function(self, locked)
            self.sizeLocked = locked
        end,
        IsSizeLocked = function(self)
            return self.sizeLocked
        end,
        
        -- ForceSetSize - required by SnapLocking for size matching
        ForceSetSize = function(self, width, height)
            if frame and width and height then
                frame:SetSize(width, height)
            end
        end,
        
        -- GetWidth/GetHeight - required for size calculations
        GetWidth = function(self)
            return frame:GetWidth()
        end,
        GetHeight = function(self)
            return frame:GetHeight()
        end,
        SetWidth = function(self, width)
            if frame and width then
                frame:SetWidth(width)
            end
        end,
        SetHeight = function(self, height)
            if frame and height then
                frame:SetHeight(height)
            end
        end,
    }
    
    frame.tuiFrame = wrapper
    layoutWrappers[slotIndex] = wrapper
    
    -- Register with FlyPaper for snap highlighting
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    if FlyPaper and FlyPaper.AddFrame then
        FlyPaper.AddFrame("TUICD", wrapperId, frame)
    end
    
    return wrapper
end

local function RegisterWithLayout(slotIndex)
    if not TUICD.Layout then
        dprint("Layout module not available")
        return false
    end
    
    local Layout = TUICD.Layout
    
    -- Ensure frame and wrapper exist
    local frame = highlightFrames[slotIndex]
    if not frame then return false end
    
    local wrapper = layoutWrappers[slotIndex]
    if not wrapper then
        wrapper = CreateLayoutWrapper(slotIndex)
    end
    
    if not wrapper then return false end
    
    local wrapperId = "BuffHighlight_" .. slotIndex
    
    -- Register with FlyPaper if available
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    if FlyPaper then
        FlyPaper.AddFrame("TUICD", wrapperId, frame)
    end
    
    -- Register with Layout
    Layout:RegisterElement(wrapperId, {
        name = "Buff Highlight " .. slotIndex,
        category = "Cooldowns",
        tuiFrame = wrapper,
        defaultPosition = wrapper.defaultPosition,
    })
    
    dprint("Registered", wrapperId, "with Layout")
    return true
end

local function UnregisterFromLayout(slotIndex)
    if not TUICD.Layout then return end
    
    local wrapperId = "BuffHighlight_" .. slotIndex
    if TUICD.Layout.UnregisterElement then
        TUICD.Layout:UnregisterElement(wrapperId)
    end
    
    -- Remove from FlyPaper
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    if FlyPaper and FlyPaper.RemoveFrame then
        FlyPaper.RemoveFrame("TUICD", wrapperId)
    end
    
    layoutWrappers[slotIndex] = nil
end

local function RegisterAllWithLayout()
    if not TUICD.Layout then
        dprint("Layout module not available")
        return
    end
    
    ForEachEnabledHighlight(function(slotIndex)
        if highlightFrames[slotIndex] then
            RegisterWithLayout(slotIndex)
        end
    end)
end

-- ============================================================================
-- UPDATE SYSTEM - Simple OnUpdate for reliable updates
-- ============================================================================

local updateFrame = nil
local updateElapsed = 0

local function StartUpdateTicker()
    if updateFrame then return end
    
    updateFrame = CreateFrame("Frame")
    updateElapsed = 0
    updateFrame:SetScript("OnUpdate", function(self, elapsed)
        updateElapsed = updateElapsed + elapsed
        if updateElapsed >= UPDATE_INTERVAL then
            updateElapsed = 0
            pcall(UpdateAllHighlights)
        end
    end)
    
    dprint("Update OnUpdate started (throttled to " .. UPDATE_INTERVAL .. "s)")
end

local function StopUpdateTicker()
    if updateFrame then
        updateFrame:SetScript("OnUpdate", nil)
        updateFrame = nil
        dprint("Update OnUpdate stopped")
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function BuffHighlights:EnableHighlight(slotIndex, enabled)
    SetHighlightEnabled(slotIndex, enabled)
    local settingsKey = GetSettingsKey(slotIndex)
    
    if enabled then
        -- Capture texture from Blizzard's icon NOW (static, won't change)
        local icons = CollectBuffIcons()
        local sourceIcon = icons[slotIndex]
        if sourceIcon then
            local textureObj = sourceIcon.Icon or sourceIcon.icon
            if textureObj then
                pcall(function()
                    local tex = textureObj:GetTexture()
                    if tex then
                        cachedTextures[settingsKey] = tex
                        dprint("Captured texture for slot", slotIndex, "(key:", settingsKey, "):", tex)
                    end
                end)
            end
        end
        
        local frame = CreateHighlightFrame(slotIndex)
        
        -- Set default show states if not set (use spellID key)
        local db = GetDB()
        if db.active.show[settingsKey] == nil then
            db.active.show[settingsKey] = true
        end
        if db.inactive.show[settingsKey] == nil then
            db.inactive.show[settingsKey] = false
        end
        
        -- Show frame immediately so user can see it
        frame:Show()
        
        -- Do initial update
        UpdateHighlightFrame(slotIndex)
        
        RegisterWithLayout(slotIndex)
        StartUpdateTicker()
        
        -- If this icon has a dock assignment, reparent to dock
        local dockAssignment = GetDockAssignment(slotIndex)
        if dockAssignment and TUICD.Docks then
            TUICD.Docks:AssignIcon(dockAssignment, "buffs", slotIndex)
        end
        
        -- Open Layout mode so user can position it
        C_Timer.After(0.3, function()
            if TUICD.LayoutMode and TUICD.LayoutMode.Unlock then
                TUICD.LayoutMode:Unlock()
                print("|cff00ccff[TUI:CD]|r Individual Icon #" .. slotIndex .. " created. Position it now!")
            else
                print("|cff00ccff[TUI:CD]|r Individual Icon #" .. slotIndex .. " created. Use /tuicdlayout to position.")
            end
        end)
    else
        if highlightFrames[slotIndex] then
            highlightFrames[slotIndex]:Hide()
        end
        -- Clear cached texture (by settings key)
        cachedTextures[settingsKey] = nil
        UnregisterFromLayout(slotIndex)
    end
end

function BuffHighlights:SetShowState(slotIndex, state, show)
    SetShowState(slotIndex, state, show)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetShowState(slotIndex, state)
    return GetShowState(slotIndex, state)
end

function BuffHighlights:SetSize(slotIndex, state, size)
    SetHighlightSize(slotIndex, state, size)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetSize(slotIndex, state)
    return GetHighlightSize(slotIndex, state)
end

function BuffHighlights:SetOpacity(slotIndex, state, opacity)
    SetHighlightOpacity(slotIndex, state, opacity)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetOpacity(slotIndex, state)
    return GetHighlightOpacity(slotIndex, state)
end

function BuffHighlights:SetSaturation(slotIndex, state, saturated)
    SetHighlightSaturation(slotIndex, state, saturated)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetSaturation(slotIndex, state)
    return GetHighlightSaturation(slotIndex, state)
end

-- Proc glow API - keyed by spellID
function BuffHighlights:SetShowProcGlow(slotIndex, show)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db.showProcGlow = db.showProcGlow or {}
    db.showProcGlow[key] = show
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetShowProcGlow(slotIndex)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db.showProcGlow and db.showProcGlow[key]  -- Returns nil if not set (default true)
end

function BuffHighlights:SetAspectRatio(slotIndex, state, ratio)
    SetHighlightAspectRatio(slotIndex, state, ratio)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetAspectRatio(slotIndex, state)
    return GetHighlightAspectRatio(slotIndex, state)
end

function BuffHighlights:SetCustomAspectRatio(slotIndex, state, width, height)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    db[state].customAspectW[key] = width or 1
    db[state].customAspectH[key] = height or 1
    SetHighlightAspectRatio(slotIndex, state, "custom")
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCustomAspectRatio(slotIndex, state)
    local db = GetDB()
    local key = GetSettingsKey(slotIndex)
    return db[state].customAspectW[key] or 1, db[state].customAspectH[key] or 1
end

-- Text scale API
function BuffHighlights:SetCooldownTextScale(slotIndex, scale)
    SetCooldownTextScale(slotIndex, scale)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCooldownTextScale(slotIndex)
    return GetCooldownTextScale(slotIndex)
end

function BuffHighlights:SetCountTextScale(slotIndex, scale)
    SetCountTextScale(slotIndex, scale)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCountTextScale(slotIndex)
    return GetCountTextScale(slotIndex)
end

function BuffHighlights:SetCooldownTextColor(slotIndex, color)
    SetCooldownTextColor(slotIndex, color)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCooldownTextColor(slotIndex)
    return GetCooldownTextColor(slotIndex)
end

function BuffHighlights:SetCountTextColor(slotIndex, color)
    SetCountTextColor(slotIndex, color)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCountTextColor(slotIndex)
    return GetCountTextColor(slotIndex)
end

function BuffHighlights:SetCooldownTextOffsetX(slotIndex, offset)
    SetCooldownTextOffsetX(slotIndex, offset)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCooldownTextOffsetX(slotIndex)
    return GetCooldownTextOffsetX(slotIndex)
end

function BuffHighlights:SetCooldownTextOffsetY(slotIndex, offset)
    SetCooldownTextOffsetY(slotIndex, offset)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCooldownTextOffsetY(slotIndex)
    return GetCooldownTextOffsetY(slotIndex)
end

function BuffHighlights:SetCountTextOffsetX(slotIndex, offset)
    SetCountTextOffsetX(slotIndex, offset)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCountTextOffsetX(slotIndex)
    return GetCountTextOffsetX(slotIndex)
end

function BuffHighlights:SetCountTextOffsetY(slotIndex, offset)
    SetCountTextOffsetY(slotIndex, offset)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCountTextOffsetY(slotIndex)
    return GetCountTextOffsetY(slotIndex)
end

function BuffHighlights:SetCooldownTextAnchor(slotIndex, anchor)
    SetCooldownTextAnchor(slotIndex, anchor)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCooldownTextAnchor(slotIndex)
    return GetCooldownTextAnchor(slotIndex)
end

function BuffHighlights:SetCountTextAnchor(slotIndex, anchor)
    SetCountTextAnchor(slotIndex, anchor)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetCountTextAnchor(slotIndex)
    return GetCountTextAnchor(slotIndex)
end

-- Custom Label public functions
function BuffHighlights:SetLabelEnabled(slotIndex, enabled)
    SetLabelEnabled(slotIndex, enabled)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetLabelEnabled(slotIndex)
    return GetLabelEnabled(slotIndex)
end

function BuffHighlights:SetLabelText(slotIndex, text)
    SetLabelText(slotIndex, text)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetLabelText(slotIndex)
    return GetLabelText(slotIndex)
end

function BuffHighlights:SetLabelFontSize(slotIndex, size)
    SetLabelFontSize(slotIndex, size)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetLabelFontSize(slotIndex)
    return GetLabelFontSize(slotIndex)
end

function BuffHighlights:SetLabelColor(slotIndex, color)
    SetLabelColor(slotIndex, color)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetLabelColor(slotIndex)
    return GetLabelColor(slotIndex)
end

function BuffHighlights:SetLabelOffsetX(slotIndex, offset)
    SetLabelOffsetX(slotIndex, offset)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetLabelOffsetX(slotIndex)
    return GetLabelOffsetX(slotIndex)
end

function BuffHighlights:SetLabelOffsetY(slotIndex, offset)
    SetLabelOffsetY(slotIndex, offset)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetLabelOffsetY(slotIndex)
    return GetLabelOffsetY(slotIndex)
end

function BuffHighlights:SetLabelAnchor(slotIndex, anchor)
    SetLabelAnchor(slotIndex, anchor)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetLabelAnchor(slotIndex)
    return GetLabelAnchor(slotIndex)
end

-- Per-icon sweep visibility (overrides tracker-level setting when set)
function BuffHighlights:SetShowSweep(slotIndex, show)
    SetShowSweep(slotIndex, show)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetShowSweep(slotIndex)
    return GetShowSweep(slotIndex)
end

-- Per-icon countdown text visibility (overrides tracker-level setting when set)
function BuffHighlights:SetShowCountdownText(slotIndex, show)
    SetShowCountdownText(slotIndex, show)
    UpdateHighlightFrame(slotIndex)
end

function BuffHighlights:GetShowCountdownText(slotIndex)
    return GetShowCountdownText(slotIndex)
end

function BuffHighlights:RefreshAllHighlights()
    -- Refresh all highlight frames (used when tracker-level settings change)
    UpdateAllHighlights()
end

function BuffHighlights:IsTrackerHidden()
    return IsTrackerHidden()
end

function BuffHighlights:ApplyTrackerVisibility()
    local viewer = _G["BuffIconCooldownViewer"]
    local container = _G["TweaksUI_BuffsContainer"]
    local hidden = IsTrackerHidden()
    
    -- Also check layout mode - always show during layout mode
    local isLayoutMode = false
    local layoutContainer = _G["TweaksUI_LayoutContainer"]
    if layoutContainer and layoutContainer:IsShown() then
        isLayoutMode = true
    end
    
    if hidden and not isLayoutMode then
        -- Hide tracker but keep it functional (just hide the container)
        -- Note: We only set alpha on the container/viewer, NOT individual children
        -- because we need to read auraInstanceID from children even when hidden
        if viewer then
            viewer:SetAlpha(0)
            viewer:EnableMouse(false)
        end
        if container then
            container:SetAlpha(0)
            container:EnableMouse(false)
        end
    else
        -- Show tracker normally
        if viewer then
            viewer:SetAlpha(1)
            viewer:EnableMouse(true)
        end
        if container then
            container:SetAlpha(1)
            container:EnableMouse(true)
        end
    end
end

-- Ticker to enforce hide state (runs every 0.2 seconds when hide is enabled)
local hideEnforcementTicker = nil

local function StartHideEnforcement()
    if hideEnforcementTicker then return end
    
    hideEnforcementTicker = C_Timer.NewTicker(0.2, function()
        if not IsTrackerHidden() then
            -- Stop ticker if no longer hidden
            if hideEnforcementTicker then
                hideEnforcementTicker:Cancel()
                hideEnforcementTicker = nil
            end
            return
        end
        
        -- Check layout mode
        local layoutContainer = _G["TweaksUI_LayoutContainer"]
        if layoutContainer and layoutContainer:IsShown() then
            return  -- Don't enforce during layout mode
        end
        
        -- Force hide the tracker
        local viewer = _G["BuffIconCooldownViewer"]
        local container = _G["TweaksUI_BuffsContainer"]
        
        if viewer and viewer:GetAlpha() > 0 then
            viewer:SetAlpha(0)
            viewer:EnableMouse(false)
        end
        if container and container:GetAlpha() > 0 then
            container:SetAlpha(0)
            container:EnableMouse(false)
        end
    end)
end

local function StopHideEnforcement()
    if hideEnforcementTicker then
        hideEnforcementTicker:Cancel()
        hideEnforcementTicker = nil
    end
end

-- Override SetTrackerHidden to manage the enforcement ticker
local origSetTrackerHidden = BuffHighlights.SetTrackerHidden
function BuffHighlights:SetTrackerHidden(hidden)
    SetTrackerHidden(hidden)
    self:ApplyTrackerVisibility()
    
    if hidden then
        StartHideEnforcement()
    else
        StopHideEnforcement()
        -- Restore normal visibility
        local viewer = _G["BuffIconCooldownViewer"]
        local container = _G["TweaksUI_BuffsContainer"]
        if viewer then
            viewer:SetAlpha(1)
            viewer:EnableMouse(true)
        end
        if container then
            container:SetAlpha(1)
            container:EnableMouse(true)
        end
    end
end

-- Per-icon hidden API (hides icon completely from tracker)
function BuffHighlights:IsIconHidden(slotIndex)
    return IsIconHidden(slotIndex)
end

function BuffHighlights:SetIconHidden(slotIndex, hidden)
    SetIconHidden(slotIndex, hidden)
    UpdateHighlightFrame(slotIndex)
    -- Refresh the tracker layout to apply alpha=0 on hidden icons
    if TUICD.Cooldowns and TUICD.Cooldowns.RefreshTrackerLayout then
        TUICD.Cooldowns.RefreshTrackerLayout("buffs")
    end
    -- When unhiding, invalidate the buff state cache so visual state gets reapplied
    if not hidden and TUICD.Cooldowns and TUICD.Cooldowns.InvalidateBuffStateCache then
        TUICD.Cooldowns.InvalidateBuffStateCache(slotIndex)
    end
end

function BuffHighlights:GetDockAssignment(slotIndex)
    return GetDockAssignment(slotIndex)
end

function BuffHighlights:SetDockAssignment(slotIndex, dockIndex)
    SetDockAssignment(slotIndex, dockIndex)
    UpdateHighlightFrame(slotIndex)
end

-- Per-icon alert settings
function BuffHighlights:GetIconAlertSetting(spellID, key)
    if not spellID then return nil end
    local db = GetDB()
    if not db.iconAlerts then return nil end
    local entry = db.iconAlerts[spellID]
    if entry then return entry[key] end
    return nil
end

function BuffHighlights:SetIconAlertSetting(spellID, key, value)
    if not spellID then return end
    local db = GetDB()
    if not db.iconAlerts then db.iconAlerts = {} end
    if not db.iconAlerts[spellID] then db.iconAlerts[spellID] = {} end
    db.iconAlerts[spellID][key] = value
end

function BuffHighlights:GetSlotCount()
    return GetBuffSlotCount()
end

function BuffHighlights:SetPosition(slotIndex, point, relPoint, x, y)
    SetHighlightPosition(slotIndex, point, relPoint, x, y)
end

function BuffHighlights:GetSlotInfo(slotIndex)
    return GetBuffSlotInfo(slotIndex)
end

function BuffHighlights:GetFrame(slotIndex)
    return highlightFrames[slotIndex]
end

function BuffHighlights:IsEnabled(slotIndex)
    return IsHighlightEnabled(slotIndex)
end

function BuffHighlights:ToggleDebug()
    debugMode = not debugMode
    print("|cff00ff00TweaksUI BuffHighlights:|r Debug mode", debugMode and "ENABLED" or "DISABLED")
end

-- Global mapping of source cooldown frames to per-icon targets
local cooldownHookTargets = {}  -- [sourceCooldown] = highlightFrame.cooldown
local hookedCooldowns = {}  -- Track which cooldowns we've hooked

-- Set up hooks on BuffIconCooldownViewer to mirror cooldown updates
function BuffHighlights:SetupCooldownHooks()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then
        dprint("BuffIconCooldownViewer not found, will retry")
        C_Timer.After(1, function() self:SetupCooldownHooks() end)
        return
    end
    
    -- Hook the viewer's Layout to catch when icons are set up
    if not viewer._TUI_BuffHL_LayoutHooked then
        viewer._TUI_BuffHL_LayoutHooked = true
        
        hooksecurefunc(viewer, "Layout", function()
            -- After Layout, scan icons and set up cooldown hooks
            C_Timer.After(0, function()  -- Next frame, after Blizzard sets cooldowns
                self:HookAllBuffCooldowns()
            end)
        end)
        dprint("Hooked BuffIconCooldownViewer.Layout")
    end
    
    -- Initial scan of existing icons
    self:HookAllBuffCooldowns()
end

-- Hook all buff icon cooldowns to mirror to per-icon frames
function BuffHighlights:HookAllBuffCooldowns()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then return end
    
    local icons = {}
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        icons = Cooldowns.GetOrderedIcons(viewer, "buffs") or {}
    else
        icons = CollectBuffIcons()
    end
    
    for slotIndex, icon in ipairs(icons) do
        local sourceCooldown = icon.Cooldown or icon.cooldown
        if sourceCooldown and not hookedCooldowns[sourceCooldown] then
            hookedCooldowns[sourceCooldown] = true
            
            -- Store slot index on the source cooldown for lookup
            sourceCooldown._TUI_BuffHL_SlotIndex = slotIndex
            
            -- Hook SetCooldownFromDurationObject (Midnight primary method)
            if sourceCooldown.SetCooldownFromDurationObject then
                hooksecurefunc(sourceCooldown, "SetCooldownFromDurationObject", function(self, durationObj, clearIfZero)
                    local slot = self._TUI_BuffHL_SlotIndex
                    if slot and highlightFrames[slot] and highlightFrames[slot].cooldown then
                        local targetCd = highlightFrames[slot].cooldown
                        if targetCd.SetCooldownFromDurationObject then
                            pcall(function()
                                targetCd:SetCooldownFromDurationObject(durationObj, clearIfZero)
                                targetCd:Show()
                            end)
                        end
                    end
                end)
            end
            
            -- Hook SetCooldown (traditional method)
            hooksecurefunc(sourceCooldown, "SetCooldown", function(self, start, duration)
                local slot = self._TUI_BuffHL_SlotIndex
                if slot and highlightFrames[slot] and highlightFrames[slot].cooldown then
                    local targetCd = highlightFrames[slot].cooldown
                    pcall(function()
                        targetCd:SetCooldown(start, duration)
                        targetCd:Show()
                    end)
                end
            end)
            
            -- Hook Clear
            hooksecurefunc(sourceCooldown, "Clear", function(self)
                local slot = self._TUI_BuffHL_SlotIndex
                if slot and highlightFrames[slot] and highlightFrames[slot].cooldown then
                    pcall(function()
                        highlightFrames[slot].cooldown:Clear()
                    end)
                end
            end)
            
            dprint("Hooked cooldown for buff slot", slotIndex)
        else
            -- Update slot index in case icons reordered
            if sourceCooldown then
                sourceCooldown._TUI_BuffHL_SlotIndex = slotIndex
            end
        end
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function BuffHighlights:Initialize()
    if isInitialized then return end
    isInitialized = true
    
    dprint("Initializing BuffHighlights")
    
    -- Set up early hooks on BuffIconCooldownViewer to catch cooldown updates
    -- This must happen BEFORE Blizzard updates the cooldowns
    self:SetupCooldownHooks()
    
    -- Create frames for any enabled highlights (resolve spellID keys to slot indices)
    local db = GetDB()
    local hasEnabled = false
    ForEachEnabledHighlight(function(slotIndex)
        CreateHighlightFrame(slotIndex)
        hasEnabled = true
    end)
    
    -- Start update ticker if we have any enabled
    if hasEnabled then
        StartUpdateTicker()
    end
    
    -- Register with Layout after a delay
    C_Timer.After(2, RegisterAllWithLayout)
    
    -- Restore dock assignments after frames exist and Docks module is ready
    -- Use longer delay to ensure everything is initialized
    local function RestoreDockAssignments()
        if not TUICD.Docks then return end
        local assignmentDb = GetDB()
        if not assignmentDb.dockAssignment then return end
        
        local Bridge = TUICD.BuffIdentityBridge
        for settingsKey, dockIndex in pairs(assignmentDb.dockAssignment) do
            if dockIndex then
                -- Settings keys are spellIDs after migration; resolve to current slot
                local resolvedSlot = settingsKey
                if IsSpellIDKey(settingsKey) and Bridge then
                    resolvedSlot = Bridge:GetSlotForSpellID(settingsKey)
                end
                if resolvedSlot and highlightFrames[resolvedSlot] then
                    dprint("Restoring dock assignment for buff key", settingsKey, "slot", resolvedSlot, "-> dock", dockIndex)
                    TUICD.Docks:AssignIcon(dockIndex, "buffs", resolvedSlot)
                end
            end
        end
    end
    
    -- Try restoration at multiple times to handle varying load orders
    C_Timer.After(1, RestoreDockAssignments)
    C_Timer.After(3, RestoreDockAssignments)
    
    -- Apply initial tracker visibility and show icons after buff tracker is ready
    C_Timer.After(2.5, function()
        self:ApplyTrackerVisibility()
        -- Start hide enforcement if enabled
        if IsTrackerHidden() then
            StartHideEnforcement()
        end
        -- Initial update to show any enabled icons
        UpdateAllHighlights()
    end)
    
    -- Also update when entering world (in case buff tracker loads later)
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    initFrame:SetScript("OnEvent", function()
        C_Timer.After(3, function()
            UpdateAllHighlights()
            -- Re-setup hooks in case viewer was recreated
            self:SetupCooldownHooks()
        end)
    end)
    
    -- Hook into layout mode callbacks to show/hide frames
    TUICD.Events:Register("LAYOUT_MODE_ENTER", function()
        -- Show tracker during layout mode (temporarily)
        local viewer = _G["BuffIconCooldownViewer"]
        local container = _G["TweaksUI_BuffsContainer"]
        if viewer then
            viewer:SetAlpha(1)
            viewer:EnableMouse(true)
        end
        if container then
            container:SetAlpha(1)
            container:EnableMouse(true)
        end
        
        -- Show all enabled highlight frames during layout mode
        local db = GetDB()
        for slotIndex, enabled in pairs(db.enabled) do
            if enabled then
                local frame = highlightFrames[slotIndex]
                if frame then
                    frame:Show()
                    -- Update appearance
                    UpdateHighlightFrame(slotIndex)
                end
            end
        end
    end, "BuffHighlights")
    
    TUICD.Events:Register("LAYOUT_MODE_EXIT", function()
        -- Update all frames to respect their actual conditions
        UpdateAllHighlights()
        -- Re-apply tracker visibility setting
        BuffHighlights:ApplyTrackerVisibility()
    end, "BuffHighlights")
    
    dprint("BuffHighlights initialized")
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_TUIBUFFHIGHLIGHTS1 = "/tuibh"
SLASH_TUIBUFFHIGHLIGHTS2 = "/tuibuffhighlights"
SlashCmdList["TUIBUFFHIGHLIGHTS"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        args[#args + 1] = word:lower()
    end
    
    local cmd = args[1]
    
    if cmd == "config" or not cmd then
        BuffHighlights:ShowConfig()
    elseif cmd == "debug" then
        BuffHighlights:ToggleDebug()
    elseif cmd == "refresh" then
        BuffHighlights:RefreshConfigUI()
    elseif cmd == "dump" then
        -- Dump structure of first buff icon
        local slotIndex = tonumber(args[2]) or 1
        local icons = CollectBuffIcons()
        local icon = icons[slotIndex]
        if icon then
            print("|cff00ff00=== Buff Icon Slot " .. slotIndex .. " Structure ===|r")
            print("Frame: " .. tostring(icon:GetName() or "unnamed"))
            print("auraInstanceID: " .. tostring(icon.auraInstanceID))
            
            -- Check spellID properties (important for direct API queries)
            print("|cffff9900SpellID Properties:|r")
            print("  icon.spellID: " .. tostring(icon.spellID))
            print("  icon.SpellID: " .. tostring(icon.SpellID))
            print("  icon.spellId: " .. tostring(icon.spellId))
            if icon.GetSpellID then
                local ok, id = pcall(function() return icon:GetSpellID() end)
                print("  icon:GetSpellID(): " .. (ok and tostring(id) or "error"))
            else
                print("  icon:GetSpellID(): (method not found)")
            end
            
            -- Check count properties specifically
            print("|cffff9900Count Properties:|r")
            print("  icon.Count: " .. tostring(icon.Count))
            print("  icon.count: " .. tostring(icon.count))
            print("  icon.CountText: " .. tostring(icon.CountText))
            print("  icon.countText: " .. tostring(icon.countText))
            
            -- If we found a count object, show its text
            local countObj = icon.Count or icon.count or icon.CountText or icon.countText
            if countObj then
                local text = ""
                local shown = false
                pcall(function() text = countObj:GetText() or "" end)
                pcall(function() shown = countObj:IsShown() end)
                print("  Count text: '" .. tostring(text) .. "', shown: " .. tostring(shown))
            end
            
            -- Try to get aura data via API
            if icon.auraInstanceID then
                print("|cffff9900Aura Data (from API):|r")
                pcall(function()
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", icon.auraInstanceID)
                    if auraData then
                        print("  name: " .. tostring(auraData.name))
                        print("  applications (stacks): " .. tostring(auraData.applications))
                        print("  duration: " .. tostring(auraData.duration))
                        print("  expirationTime: " .. tostring(auraData.expirationTime))
                        if auraData.duration and auraData.expirationTime and auraData.duration > 0 then
                            local startTime = auraData.expirationTime - auraData.duration
                            local remaining = auraData.expirationTime - GetTime()
                            print("  startTime: " .. string.format("%.2f", startTime))
                            print("  remaining: " .. string.format("%.2f", remaining))
                        end
                    else
                        print("  No aura data returned")
                    end
                end)
                
                -- Try duration object API
                print("|cffff9900Duration Object API:|r")
                if C_UnitAuras.GetUnitAuraDuration then
                    pcall(function()
                        local durationObj = C_UnitAuras.GetUnitAuraDuration("player", icon.auraInstanceID)
                        print("  GetUnitAuraDuration returned: " .. tostring(durationObj))
                        if durationObj then
                            print("  type: " .. type(durationObj))
                        end
                    end)
                else
                    print("  GetUnitAuraDuration API not available")
                end
            end
            
            -- Check cooldown frame
            print("|cffff9900Cooldown Frame:|r")
            local sourceCooldown = icon.Cooldown or icon.cooldown
            print("  icon.Cooldown: " .. tostring(icon.Cooldown))
            print("  icon.cooldown: " .. tostring(icon.cooldown))
            if sourceCooldown then
                print("  GetCooldownDuration exists: " .. tostring(sourceCooldown.GetCooldownDuration ~= nil))
                print("  GetCooldownTimes exists: " .. tostring(sourceCooldown.GetCooldownTimes ~= nil))
                if sourceCooldown.GetCooldownTimes then
                    pcall(function()
                        local start, duration = sourceCooldown:GetCooldownTimes()
                        print("  GetCooldownTimes: start=" .. tostring(start) .. ", duration=" .. tostring(duration))
                    end)
                end
                if sourceCooldown.GetCooldownDuration then
                    pcall(function()
                        local durationObj = sourceCooldown:GetCooldownDuration()
                        print("  GetCooldownDuration returned: " .. tostring(durationObj))
                    end)
                end
            end
            
            -- Dump all regions
            print("|cffff9900Regions:|r")
            if icon.GetRegions then
                pcall(function()
                    for i, region in ipairs({icon:GetRegions()}) do
                        local rType = region:GetObjectType()
                        local rName = region:GetName() or "unnamed"
                        local rText = ""
                        if rType == "FontString" then
                            pcall(function() rText = region:GetText() or "" end)
                        end
                        print(string.format("  %d: %s (%s) text='%s'", i, tostring(rName), tostring(rType), tostring(rText)))
                    end
                end)
            end
            
            -- Dump children (wrapped in pcall to handle secret values)
            print("|cffff9900Children:|r")
            if icon.GetChildren then
                pcall(function()
                    for i, child in ipairs({icon:GetChildren()}) do
                        local cName = "unnamed"
                        local cType = "unknown"
                        pcall(function() cName = child:GetName() or "unnamed" end)
                        pcall(function() cType = child:GetObjectType() end)
                        print(string.format("  %d: %s (%s)", i, tostring(cName), tostring(cType)))
                        
                        -- Check child regions
                        if child.GetRegions then
                            pcall(function()
                                for j, region in ipairs({child:GetRegions()}) do
                                    local rType = "unknown"
                                    local rName = "unnamed"
                                    local rText = ""
                                    pcall(function() rType = region:GetObjectType() end)
                                    pcall(function() rName = region:GetName() or "unnamed" end)
                                    if rType == "FontString" then
                                        pcall(function() rText = region:GetText() or "" end)
                                    end
                                    print(string.format("    %d.%d: %s (%s) text='%s'", i, j, tostring(rName), tostring(rType), tostring(rText)))
                                end
                            end)
                        end
                    end
                end)
            end
        else
            print("|cffff0000No icon found at slot " .. slotIndex .. "|r")
        end
    elseif cmd == "status" then
        -- Show current status of everything
        print("|cff00ff00=== BuffHighlights Status ===|r")
        print("Initialized: " .. tostring(isInitialized))
        print("Update OnUpdate running: " .. tostring(updateFrame ~= nil))
        print("Hide enforcement running: " .. tostring(hideEnforcementTicker ~= nil))
        print("Tracker hidden setting: " .. tostring(IsTrackerHidden()))
        print("In combat: " .. tostring(InCombatLockdown()))
        print("Debug mode: " .. tostring(debugMode))
        
        local viewer = _G["BuffIconCooldownViewer"]
        print("Viewer exists: " .. tostring(viewer ~= nil))
        if viewer then
            print("Viewer alpha: " .. tostring(viewer:GetAlpha()))
            print("Viewer shown: " .. tostring(viewer:IsShown()))
            print("Viewer children: " .. tostring(viewer:GetNumChildren() or 0))
        end
        
        local icons = CollectBuffIcons()
        print("Icons collected: " .. #icons)
        
        -- Show details about each collected icon
        for i, icon in ipairs(icons) do
            local auraID = icon.auraInstanceID
            local name = icon:GetName() or "unnamed"
            print(string.format("  Icon %d: %s, auraInstanceID=%s", i, name, tostring(auraID)))
        end
        
        local db = GetDB()
        local enabledCount = 0
        print("|cffff9900Enabled Individual Icons slots:|r")
        for slotIndex, enabled in pairs(db.enabled) do
            if enabled then
                enabledCount = enabledCount + 1
                local slotInfo = GetBuffSlotInfo(slotIndex)
                local frame = highlightFrames[slotIndex]
                local showActive = GetShowState(slotIndex, "active")
                local showInactive = GetShowState(slotIndex, "inactive")
                print(string.format("  Slot %d: frame=%s, isActive=%s, shown=%s", 
                    slotIndex,
                    tostring(frame ~= nil),
                    slotInfo and tostring(slotInfo.isActive) or "NO INFO",
                    frame and tostring(frame:IsShown()) or "no frame"))
                print(string.format("    showActive=%s, showInactive=%s", 
                    tostring(showActive), tostring(showInactive)))
            end
        end
        print("Total enabled slots: " .. enabledCount)
    elseif cmd == "cdinfo" then
        -- Dump cooldown info for a specific slot
        local slotIndex = tonumber(args[2]) or 1
        print("|cff00ff00=== Cooldown Info for Slot " .. slotIndex .. " ===|r")
        
        local frame = highlightFrames[slotIndex]
        if frame then
            print("Highlight frame exists: true")
            print("Frame shown: " .. tostring(frame:IsShown()))
            print("Frame alpha: " .. tostring(frame:GetAlpha()))
            
            if frame.cooldown then
                print("|cffff9900Highlight Cooldown Frame:|r")
                print("  cooldown exists: true")
                print("  cooldown shown: " .. tostring(frame.cooldown:IsShown()))
                print("  cooldown alpha: " .. tostring(frame.cooldown:GetAlpha()))
                print("  frame level: " .. tostring(frame.cooldown:GetFrameLevel()))
                print("  GetDrawSwipe: " .. tostring(frame.cooldown:GetDrawSwipe()))
                
                if frame.cooldown.GetCooldownTimes then
                    local start, duration = frame.cooldown:GetCooldownTimes()
                    print("  GetCooldownTimes: start=" .. tostring(start) .. ", duration=" .. tostring(duration))
                    if start and duration and start > 0 and duration > 0 then
                        local remaining = (start/1000 + duration/1000) - GetTime()
                        print("  remaining: " .. string.format("%.2f", remaining) .. "s")
                    end
                end
            else
                print("  cooldown frame: NIL!")
            end
        else
            print("Highlight frame: NIL - not created for slot " .. slotIndex)
        end
        
        -- Also show source info
        local slotInfo = GetBuffSlotInfo(slotIndex)
        if slotInfo then
            print("|cffff9900Source Icon Info:|r")
            print("  isActive: " .. tostring(slotInfo.isActive))
            print("  auraInstanceID: " .. tostring(slotInfo.auraInstanceID))
            
            if slotInfo.icon then
                local sourceCd = slotInfo.icon.Cooldown or slotInfo.icon.cooldown
                if sourceCd then
                    print("  source cooldown exists: true")
                    if sourceCd.GetCooldownTimes then
                        local start, duration = sourceCd:GetCooldownTimes()
                        print("  source GetCooldownTimes: start=" .. tostring(start) .. ", duration=" .. tostring(duration))
                    end
                else
                    print("  source cooldown: NIL")
                end
            end
        else
            print("No slotInfo for slot " .. slotIndex)
        end
    elseif cmd == "debug" then
        -- Toggle debug mode
        debugMode = not debugMode
        print("|cff00ff00BuffHighlights:|r Debug mode: " .. (debugMode and "ON" or "OFF"))
    elseif cmd == "force" then
        -- Force update all highlight frames
        for slotIndex, _ in pairs(highlightFrames) do
            UpdateHighlightFrame(slotIndex)
        end
        print("|cff00ff00BuffHighlights:|r Forced update on all highlight frames")
    elseif cmd == "state" then
        -- Show detailed state info like update function sees it
        local slotIndex = tonumber(args[2]) or 1
        print("|cff00ff00=== Individual Icon State for Slot " .. slotIndex .. " ===|r")
        
        local enabled = IsHighlightEnabled(slotIndex)
        print("Enabled: " .. tostring(enabled))
        
        -- Use same icon collection as UpdateHighlightFrame
        local icons
        local Cooldowns = TUICD.Cooldowns
        if Cooldowns and Cooldowns.GetOrderedIcons then
            local viewer = _G["BuffIconCooldownViewer"]
            if viewer then
                icons = Cooldowns.GetOrderedIcons(viewer, "buffs")
                print("Using GetOrderedIcons")
            else
                icons = {}
                print("No viewer found")
            end
        else
            icons = CollectBuffIcons()
            print("Using CollectBuffIcons (fallback)")
        end
        print("Total icons collected: " .. #icons)
        
        local sourceIcon = icons[slotIndex]
        print("Source icon at slot " .. slotIndex .. ": " .. tostring(sourceIcon ~= nil))
        
        if sourceIcon then
            local auraID = nil
            pcall(function() auraID = sourceIcon.auraInstanceID end)
            print("  auraInstanceID: " .. tostring(auraID))
            
            local isActive = (auraID ~= nil)
            print("  isActive (has auraID): " .. tostring(isActive))
            
            local tex = nil
            local textureObj = sourceIcon.Icon or sourceIcon.icon
            if textureObj then
                pcall(function() tex = textureObj:GetTexture() end)
            end
            print("  texture: " .. tostring(tex))
            
            local debugKey = GetSettingsKey(slotIndex)
            local cachedTex = cachedTextures[debugKey]
            print("  cached texture: " .. tostring(cachedTex) .. " (key: " .. tostring(debugKey) .. ")")
        end
        
        local currentState = (sourceIcon and sourceIcon.auraInstanceID) and "active" or "inactive"
        local showThisState = GetShowState(slotIndex, currentState)
        print("Current state: " .. currentState)
        print("Show this state: " .. tostring(showThisState))
        
        local frame = highlightFrames[slotIndex]
        print("Highlight frame exists: " .. tostring(frame ~= nil))
        if frame then
            print("  frame:IsShown(): " .. tostring(frame:IsShown()))
            
            -- Check cooldown frame
            if frame.cooldown then
                print("|cffff9900Cooldown Frame Details:|r")
                print("  cooldown:IsShown(): " .. tostring(frame.cooldown:IsShown()))
                print("  GetDrawSwipe(): " .. tostring(frame.cooldown:GetDrawSwipe()))
                print("  GetHideCountdownNumbers(): " .. tostring(frame.cooldown:GetHideCountdownNumbers()))
                print("  _TUI_showSweep: " .. tostring(frame.cooldown._TUI_showSweep))
                print("  _TUI_showCountdownText: " .. tostring(frame.cooldown._TUI_showCountdownText))
                
                if frame.cooldown.GetCooldownTimes then
                    local start, duration = frame.cooldown:GetCooldownTimes()
                    print("  GetCooldownTimes: start=" .. tostring(start) .. ", duration=" .. tostring(duration))
                end
            else
                print("  cooldown frame: NIL!")
            end
            
            -- Test what API would return
            if sourceIcon and sourceIcon.auraInstanceID then
                print("|cffff9900API Query Test:|r")
                pcall(function()
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", sourceIcon.auraInstanceID)
                    if auraData then
                        print("  auraData.duration: " .. tostring(auraData.duration))
                        print("  auraData.expirationTime: " .. tostring(auraData.expirationTime))
                        if auraData.duration and auraData.duration > 0 then
                            local startTime = auraData.expirationTime - auraData.duration
                            local remaining = auraData.expirationTime - GetTime()
                            print("  calculated start: " .. string.format("%.2f", startTime))
                            print("  remaining: " .. string.format("%.2f", remaining))
                        end
                    else
                        print("  GetAuraDataByAuraInstanceID returned nil")
                    end
                end)
            end
        end
        -- Force update all highlights
        print("|cff00ff00Forcing update of all highlights...|r")
        UpdateAllHighlights()
        print("Done!")
    elseif cmd == "watch" then
        -- Toggle watch mode - print every update
        if not BuffHighlights._watchMode then
            BuffHighlights._watchMode = true
            BuffHighlights._watchTicker = C_Timer.NewTicker(0.5, function()
                local db = GetDB()
                local msg = "Watch: "
                for slotIndex, enabled in pairs(db.enabled) do
                    if enabled then
                        local slotInfo = GetBuffSlotInfo(slotIndex)
                        local frame = highlightFrames[slotIndex]
                        msg = msg .. string.format("[%d:%s/%s] ", 
                            slotIndex,
                            slotInfo and (slotInfo.isActive and "A" or "I") or "?",
                            frame and (frame:IsShown() and "V" or "H") or "X")
                    end
                end
                print(msg)
            end)
            print("|cff00ff00Watch mode ON - will print state every 0.5s. /tuibh watch to stop|r")
        else
            BuffHighlights._watchMode = false
            if BuffHighlights._watchTicker then
                BuffHighlights._watchTicker:Cancel()
                BuffHighlights._watchTicker = nil
            end
            print("|cffff0000Watch mode OFF|r")
        end
    else
        print("|cff00ff00TweaksUI BuffHighlights Commands:|r")
        print("  /tuibh - Open config UI")
        print("  /tuibh debug - Toggle debug mode")
        print("  /tuibh dump [slot] - Dump icon structure")
        print("  /tuibh cdinfo [slot] - Dump cooldown info for highlight frame")
        print("  /tuibh status - Show current status")
        print("  /tuibh force - Force update all highlights")
        print("  /tuibh watch - Toggle real-time state monitoring")
    end
end

-- Auto-initialize when Cooldowns module loads
if TUICD.Modules and TUICD.Modules.Cooldowns then
    -- Hook into Cooldowns initialization
    local origInit = TUICD.Modules.Cooldowns.Initialize
    if origInit then
        TUICD.Modules.Cooldowns.Initialize = function(...)
            local result = origInit(...)
            C_Timer.After(1, function()
                BuffHighlights:Initialize()
            end)
            return result
        end
    end
else
    -- Fallback: Initialize on PLAYER_LOGIN
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function()
        C_Timer.After(3, function()
            BuffHighlights:Initialize()
        end)
    end)
end
