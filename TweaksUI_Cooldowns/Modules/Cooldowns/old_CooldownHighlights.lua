-- ============================================================================
-- TUICD CooldownHighlights.lua
-- Creates positionable highlight clones for cooldown trackers
-- Supports: Essential Cooldowns, Utility Cooldowns, Custom Trackers
-- Active = ability ready (off cooldown), Inactive = on cooldown
-- ============================================================================

local addonName, TUICD = ...
TUICD.CooldownHighlights = TUICD.CooldownHighlights or {}
local CooldownHighlights = TUICD.CooldownHighlights

-- ============================================================================
-- MIDNIGHT API WRAPPERS (v2.0.0)
-- ============================================================================

local SpellAPI = TUICD.SpellAPI
local DurationAPI = TUICD.DurationAPI

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local UPDATE_INTERVAL = 0.05  -- 20 Hz update rate for responsive per-icon tracking
local DEFAULT_SIZE = 48

-- Tracker definitions
local TRACKER_TYPES = {
    essential = {
        key = "essential",
        viewerName = "EssentialCooldownViewer",
        displayName = "Essential Cooldowns",
        framePrefix = "TweaksUI_EssentialHighlight_",
        dbKey = "essentialHighlights",
    },
    utility = {
        key = "utility",
        viewerName = "UtilityCooldownViewer",
        displayName = "Utility Cooldowns",
        framePrefix = "TweaksUI_UtilityHighlight_",
        dbKey = "utilityHighlights",
    },
    custom = {
        key = "custom",
        viewerName = "TweaksUI_CustomTrackerFrame",
        displayName = "Custom Trackers",
        framePrefix = "TweaksUI_CustomHighlight_",
        dbKey = "customHighlights",
    },
}

-- ============================================================================
-- STATE (per tracker type)
-- ============================================================================

local highlightFrames = {
    essential = {},
    utility = {},
    custom = {},
}

-- Track cooldown state per-icon (true = on cooldown, false = ready)
local iconCooldownState = {
    essential = {},
    utility = {},
    custom = {},
}

-- ============================================================================
-- SPELL ID CACHE (populated outside combat, used during combat)
-- This is critical for Midnight compatibility - we can't read spellIDs from
-- Blizzard's CDM icons during combat due to secret values
-- ============================================================================

local spellIDCache = {
    essential = {},  -- [slotIndex] = spellID
    utility = {},
    custom = {},
}

-- Track when cache was last updated
local cacheLastUpdated = {
    essential = 0,
    utility = 0,
    custom = 0,
}

local layoutWrappers = {
    essential = {},
    utility = {},
    custom = {},
}

local updateTickers = {}
local isInitialized = {}

-- Debug mode
local debugMode = false
local function dprint(...)
    -- Debug printing disabled
end

-- ============================================================================
-- DATABASE
-- ============================================================================

local function GetDB(trackerKey)
    if not TweaksUI_Cooldowns_CharDB then TweaksUI_Cooldowns_CharDB = {} end
    
    local trackerType = TRACKER_TYPES[trackerKey]
    if not trackerType then return nil end
    
    local dbKey = trackerType.dbKey
    if not TweaksUI_Cooldowns_CharDB[dbKey] then
        TweaksUI_Cooldowns_CharDB[dbKey] = {
            hideTracker = false,
            enabled = {},
            positions = {},
            active = {
                size = {},
                opacity = {},
                saturation = {},
                aspectRatio = {},
                customAspectW = {},
                customAspectH = {},
                show = {},
            },
            inactive = {
                size = {},
                opacity = {},
                saturation = {},
                aspectRatio = {},
                customAspectW = {},
                customAspectH = {},
                show = {},
            },
        }
    end
    
    local db = TweaksUI_Cooldowns_CharDB[dbKey]
    
    -- Ensure all fields exist
    if not db.enabled then db.enabled = {} end
    if not db.positions then db.positions = {} end
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
    
    -- Custom label fields (state-independent)
    if not db.labelEnabled then db.labelEnabled = {} end
    if not db.labelText then db.labelText = {} end
    if not db.labelFontSize then db.labelFontSize = {} end
    if not db.labelColor then db.labelColor = {} end
    if not db.labelOffsetX then db.labelOffsetX = {} end
    if not db.labelOffsetY then db.labelOffsetY = {} end
    
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
    if not db.labelAnchor then db.labelAnchor = {} end
    
    -- Per-icon sweep and countdown text settings (overrides tracker-level when set)
    if not db.showSweep then db.showSweep = {} end
    if not db.showCountdownText then db.showCountdownText = {} end
    
    -- Hidden icons (state-independent) - hides icon from tracker completely
    if not db.hidden then db.hidden = {} end
    
    -- Dock assignment (state-independent) - which dock (1-4) icon is assigned to
    if not db.dockAssignment then db.dockAssignment = {} end
    
    return db
end

-- ============================================================================
-- SETTINGS HELPERS
-- ============================================================================

local function IsHighlightEnabled(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.enabled[slotIndex] == true
end

local function SetHighlightEnabled(trackerKey, slotIndex, enabled)
    local db = GetDB(trackerKey)
    if db then db.enabled[slotIndex] = enabled end
end

local function IsIconHidden(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.hidden[slotIndex] == true
end

local function SetIconHidden(trackerKey, slotIndex, hidden)
    local db = GetDB(trackerKey)
    if db then db.hidden[slotIndex] = hidden end
end

local function GetDockAssignment(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.dockAssignment[slotIndex]  -- nil, 1, 2, 3, or 4
end

local function SetDockAssignment(trackerKey, slotIndex, dockIndex)
    local db = GetDB(trackerKey)
    if not db then return end
    
    db.dockAssignment[slotIndex] = dockIndex
    
    -- Update Docks module
    if TUICD.Docks then
        if dockIndex and dockIndex >= 1 and dockIndex <= 4 then
            TUICD.Docks:AssignIcon(dockIndex, trackerKey, slotIndex)
        else
            -- Unassign from all docks
            for i = 1, 4 do
                TUICD.Docks:UnassignIcon(i, trackerKey, slotIndex)
            end
        end
    end
    
    -- Refresh layout mode overlay (show/hide based on dock status)
    if TUICD.LayoutMode and TUICD.LayoutMode.RefreshPerIconOverlay then
        TUICD.LayoutMode:RefreshPerIconOverlay(trackerKey, slotIndex)
    end
end

local function GetStateSetting(trackerKey, slotIndex, state, key)
    local db = GetDB(trackerKey)
    return db and db[state] and db[state][key] and db[state][key][slotIndex]
end

local function SetStateSetting(trackerKey, slotIndex, state, key, value)
    local db = GetDB(trackerKey)
    if db and db[state] and db[state][key] then
        db[state][key][slotIndex] = value
    end
end

local function GetHighlightSize(trackerKey, slotIndex, state)
    return GetStateSetting(trackerKey, slotIndex, state or "active", "size") or DEFAULT_SIZE
end

local function SetHighlightSize(trackerKey, slotIndex, state, size)
    SetStateSetting(trackerKey, slotIndex, state, "size", size)
end

local function GetHighlightOpacity(trackerKey, slotIndex, state)
    local opacity = GetStateSetting(trackerKey, slotIndex, state or "active", "opacity")
    return opacity or 1.0
end

local function SetHighlightOpacity(trackerKey, slotIndex, state, opacity)
    SetStateSetting(trackerKey, slotIndex, state, "opacity", opacity)
end

local function GetHighlightSaturation(trackerKey, slotIndex, state)
    local sat = GetStateSetting(trackerKey, slotIndex, state or "active", "saturation")
    if sat == nil then
        return state == "active"  -- Default: saturated when active, desaturated when inactive
    end
    return sat
end

local function SetHighlightSaturation(trackerKey, slotIndex, state, saturated)
    SetStateSetting(trackerKey, slotIndex, state, "saturation", saturated)
end

local function GetHighlightAspectRatio(trackerKey, slotIndex, state)
    return GetStateSetting(trackerKey, slotIndex, state or "active", "aspectRatio") or "1:1"
end

local function SetHighlightAspectRatio(trackerKey, slotIndex, state, ratio)
    SetStateSetting(trackerKey, slotIndex, state, "aspectRatio", ratio)
end

local function GetShowState(trackerKey, slotIndex, state)
    local show = GetStateSetting(trackerKey, slotIndex, state, "show")
    if show == nil then
        -- Default: show when active (ready), hide when inactive (on cooldown)
        return state == "active"
    end
    return show
end

local function SetShowState(trackerKey, slotIndex, state, show)
    SetStateSetting(trackerKey, slotIndex, state, "show", show)
end

local function GetHighlightPosition(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.positions[slotIndex]
end

local function SetHighlightPosition(trackerKey, slotIndex, point, relPoint, x, y)
    local db = GetDB(trackerKey)
    if db then
        db.positions[slotIndex] = { point = point, relPoint = relPoint, x = x, y = y }
    end
end

local function IsTrackerHidden(trackerKey)
    local db = GetDB(trackerKey)
    return db and db.hideTracker == true
end

local function SetTrackerHidden(trackerKey, hidden)
    local db = GetDB(trackerKey)
    if db then
        db.hideTracker = hidden
    end
end

-- Custom label helpers (state-independent)
local function GetLabelEnabled(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.labelEnabled[slotIndex] == true
end

local function SetLabelEnabled(trackerKey, slotIndex, enabled)
    local db = GetDB(trackerKey)
    if db then db.labelEnabled[slotIndex] = enabled end
end

local function GetLabelText(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.labelText[slotIndex] or ""
end

local function SetLabelText(trackerKey, slotIndex, text)
    local db = GetDB(trackerKey)
    if db then db.labelText[slotIndex] = text end
end

local function GetLabelFontSize(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.labelFontSize[slotIndex] or 14
end

local function SetLabelFontSize(trackerKey, slotIndex, size)
    local db = GetDB(trackerKey)
    if db then db.labelFontSize[slotIndex] = size end
end

local function GetLabelColor(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.labelColor[slotIndex] or {1, 1, 1, 1}  -- Default white
end

local function SetLabelColor(trackerKey, slotIndex, color)
    local db = GetDB(trackerKey)
    if db then db.labelColor[slotIndex] = color end
end

local function GetLabelOffsetX(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.labelOffsetX[slotIndex] or 0
end

local function SetLabelOffsetX(trackerKey, slotIndex, offset)
    local db = GetDB(trackerKey)
    if db then db.labelOffsetX[slotIndex] = offset end
end

local function GetLabelOffsetY(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.labelOffsetY[slotIndex] or 0
end

local function SetLabelOffsetY(trackerKey, slotIndex, offset)
    local db = GetDB(trackerKey)
    if db then db.labelOffsetY[slotIndex] = offset end
end

-- Text scale helpers (state-independent)
local function GetCooldownTextScale(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.cooldownTextScale[slotIndex] or 1.0
end

local function SetCooldownTextScale(trackerKey, slotIndex, scale)
    local db = GetDB(trackerKey)
    if db then db.cooldownTextScale[slotIndex] = scale end
end

local function GetCountTextScale(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.countTextScale[slotIndex] or 1.0
end

local function SetCountTextScale(trackerKey, slotIndex, scale)
    local db = GetDB(trackerKey)
    if db then db.countTextScale[slotIndex] = scale end
end

local function GetCooldownTextColor(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.cooldownTextColor[slotIndex] or {1, 1, 1, 1}  -- Default white
end

local function SetCooldownTextColor(trackerKey, slotIndex, color)
    local db = GetDB(trackerKey)
    if db then db.cooldownTextColor[slotIndex] = color end
end

local function GetCountTextColor(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.countTextColor[slotIndex] or {1, 1, 1, 1}  -- Default white
end

local function SetCountTextColor(trackerKey, slotIndex, color)
    local db = GetDB(trackerKey)
    if db then db.countTextColor[slotIndex] = color end
end

local function GetCooldownTextOffsetX(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.cooldownTextOffsetX[slotIndex] or 0
end

local function SetCooldownTextOffsetX(trackerKey, slotIndex, offset)
    local db = GetDB(trackerKey)
    if db then db.cooldownTextOffsetX[slotIndex] = offset end
end

local function GetCooldownTextOffsetY(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.cooldownTextOffsetY[slotIndex] or 0
end

local function SetCooldownTextOffsetY(trackerKey, slotIndex, offset)
    local db = GetDB(trackerKey)
    if db then db.cooldownTextOffsetY[slotIndex] = offset end
end

local function GetCountTextOffsetX(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.countTextOffsetX[slotIndex] or 0
end

local function SetCountTextOffsetX(trackerKey, slotIndex, offset)
    local db = GetDB(trackerKey)
    if db then db.countTextOffsetX[slotIndex] = offset end
end

local function GetCountTextOffsetY(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.countTextOffsetY[slotIndex] or 0
end

local function SetCountTextOffsetY(trackerKey, slotIndex, offset)
    local db = GetDB(trackerKey)
    if db then db.countTextOffsetY[slotIndex] = offset end
end

local function GetCooldownTextAnchor(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.cooldownTextAnchor[slotIndex] or "CENTER"
end

local function SetCooldownTextAnchor(trackerKey, slotIndex, anchor)
    local db = GetDB(trackerKey)
    if db then db.cooldownTextAnchor[slotIndex] = anchor end
end

local function GetCountTextAnchor(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.countTextAnchor[slotIndex] or "BOTTOMRIGHT"
end

local function SetCountTextAnchor(trackerKey, slotIndex, anchor)
    local db = GetDB(trackerKey)
    if db then db.countTextAnchor[slotIndex] = anchor end
end

local function GetLabelAnchor(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.labelAnchor[slotIndex] or "CENTER"
end

local function SetLabelAnchor(trackerKey, slotIndex, anchor)
    local db = GetDB(trackerKey)
    if db then db.labelAnchor[slotIndex] = anchor end
end

-- Per-icon sweep visibility (nil = use tracker default)
local function GetShowSweep(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.showSweep[slotIndex]  -- Returns nil if not set (use tracker default)
end

local function SetShowSweep(trackerKey, slotIndex, show)
    local db = GetDB(trackerKey)
    if db then db.showSweep[slotIndex] = show end
end

-- Per-icon countdown text visibility (nil = use tracker default)
local function GetShowCountdownText(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.showCountdownText[slotIndex]  -- Returns nil if not set (use tracker default)
end

local function SetShowCountdownText(trackerKey, slotIndex, show)
    local db = GetDB(trackerKey)
    if db then db.showCountdownText[slotIndex] = show end
end

-- Per-icon proc glow visibility (nil = show proc glow, default true)
local function GetShowProcGlow(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.showProcGlow and db.showProcGlow[slotIndex]  -- Returns nil if not set (default true)
end

local function SetShowProcGlow(trackerKey, slotIndex, show)
    local db = GetDB(trackerKey)
    if db then
        db.showProcGlow = db.showProcGlow or {}
        db.showProcGlow[slotIndex] = show
    end
end

-- ============================================================================
-- ICON COLLECTION
-- ============================================================================

local function IsIcon(frame)
    if not frame then return false end
    if frame.Cooldown or frame.cooldown then return true end
    if frame.Icon or frame.icon then return true end
    return false
end

local function GetViewer(trackerKey)
    local trackerType = TRACKER_TYPES[trackerKey]
    if not trackerType then return nil end
    return _G[trackerType.viewerName]
end

local function CollectIcons(trackerKey)
    local icons = {}
    local viewer = GetViewer(trackerKey)
    
    if not viewer or not viewer.GetChildren then return icons end
    
    local numChildren = viewer:GetNumChildren() or 0
    
    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        -- Don't check IsShown - icons might briefly hide during GCD/updates
        if child and IsIcon(child) then
            icons[#icons + 1] = child
        elseif child and child.GetNumChildren then
            local numNested = child:GetNumChildren() or 0
            for j = 1, numNested do
                local nested = select(j, child:GetChildren())
                if nested and IsIcon(nested) then
                    icons[#icons + 1] = nested
                end
            end
        end
    end
    
    -- Sort by visual position (top-to-bottom, left-to-right)
    table.sort(icons, function(a, b)
        local at, bt = a:GetTop() or 0, b:GetTop() or 0
        local al, bl = a:GetLeft() or 0, b:GetLeft() or 0
        if math.abs(at - bt) > 5 then return at > bt end
        return al < bl
    end)
    
    return icons
end

-- ============================================================================
-- SPELL ID CACHE SYSTEM
-- Cache spellIDs outside of combat so we can use them during combat
-- Critical for Midnight compatibility - CDM icons have secret spellIDs in combat
-- ============================================================================

-- Extract spellID from an icon (only works reliably outside combat)
local function ExtractSpellID(icon)
    if not icon then return nil end
    
    -- Direct property access
    local spellID = icon.spellID or icon.SpellID or icon.spellId
    
    -- Try GetSpellID method
    if not spellID and icon.GetSpellID then
        pcall(function() spellID = icon:GetSpellID() end)
    end
    
    -- Custom tracker stores as trackID
    if not spellID and icon.trackType == "spell" and icon.trackID then
        spellID = icon.trackID
    end
    
    -- Check if the value is a secret (can't be used in comparisons)
    if spellID and issecretvalue and issecretvalue(spellID) then
        return nil  -- Return nil for secret values - can't cache them
    end
    
    return spellID
end

-- Cache spellIDs for a tracker (ONLY call outside combat)
local function CacheSpellIDs(trackerKey)
    if InCombatLockdown() then
        dprint("CacheSpellIDs: Skipped (in combat)", trackerKey)
        return
    end
    
    -- Use the ordered icons from Cooldowns module if available
    local icons
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = GetViewer(trackerKey)
        if viewer then
            icons = Cooldowns.GetOrderedIcons(viewer, trackerKey)
        else
            icons = {}
        end
    else
        icons = CollectIcons(trackerKey)
    end
    
    local cacheUpdated = false
    for slotIndex, icon in ipairs(icons) do
        local spellID = ExtractSpellID(icon)
        if spellID then
            -- Only update if changed (or new)
            if spellIDCache[trackerKey][slotIndex] ~= spellID then
                spellIDCache[trackerKey][slotIndex] = spellID
                cacheUpdated = true
            end
        end
    end
    
    if cacheUpdated then
        cacheLastUpdated[trackerKey] = GetTime()
        dprint("CacheSpellIDs: Updated cache for", trackerKey, "icons:", #icons)
    end
end

-- Get cached spellID for a slot (safe to call during combat)
local function GetCachedSpellID(trackerKey, slotIndex)
    return spellIDCache[trackerKey] and spellIDCache[trackerKey][slotIndex]
end

-- Clear cache for a tracker (call when icons might have changed)
local function ClearSpellIDCache(trackerKey)
    if trackerKey then
        wipe(spellIDCache[trackerKey])
        cacheLastUpdated[trackerKey] = 0
        dprint("ClearSpellIDCache:", trackerKey)
    else
        -- Clear all
        for key, cache in pairs(spellIDCache) do
            wipe(cache)
            cacheLastUpdated[key] = 0
        end
        dprint("ClearSpellIDCache: All cleared")
    end
end

-- Refresh cache for all trackers (call on PLAYER_REGEN_ENABLED)
local function RefreshAllSpellIDCaches()
    if InCombatLockdown() then return end
    
    for trackerKey in pairs(TRACKER_TYPES) do
        CacheSpellIDs(trackerKey)
    end
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
        isMounted = IsMounted(),
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
-- trackerKey: "essential", "utility", or "custom"
local function ShouldHighlightBeVisible(trackerKey)
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
    
    -- Map "custom" to "customTrackers" for database access
    local dbTrackerKey = (trackerKey == "custom") and "customTrackers" or trackerKey
    
    local visibilityEnabled = TUICD.Database:GetTrackerSetting(dbTrackerKey, "visibilityEnabled")
    if not visibilityEnabled then
        return true  -- Visibility system disabled = always show
    end
    
    local state = GetPlayerState()
    
    -- OR logic: if ANY checked condition is true, show the highlight
    if state.inCombat and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInCombat") then return true end
    if not state.inCombat and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showOutOfCombat") then return true end
    if state.isSolo and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showSolo") then return true end
    if state.inGroup and not state.inRaid and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInParty") then return true end
    if state.inRaid and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInRaid") then return true end
    if state.inInstance and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInInstance") then return true end
    if state.inArena and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInArena") then return true end
    if state.inBattleground and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInBattleground") then return true end
    if state.hasTarget and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showHasTarget") then return true end
    if not state.hasTarget and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showNoTarget") then return true end
    if state.isMounted and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showMounted") then return true end
    if not state.isMounted and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showNotMounted") then return true end
    
    -- No conditions matched
    return false
end

-- ============================================================================
-- VISUAL STATE DETECTION
-- ============================================================================

-- Cooldowns longer than 3000ms (3 sec) are "real" cooldowns, not GCD (~1500ms)
local GCD_THRESHOLD = 3000

-- Detect visual state by checking if source icon has a REAL cooldown (not GCD)
-- We check actual cooldown duration to avoid GCD false positives
-- NOTE: GetCooldownTimes returns MILLISECONDS
local function GetIconVisualState(icon)
    if not icon then return true end  -- Default to "ready" if no icon
    
    local isReady = true
    
    -- Check cooldown frame times - only count as "on cooldown" if duration > GCD threshold
    -- NOTE: GetCooldownTimes returns MILLISECONDS
    pcall(function()
        local cooldown = icon.Cooldown or icon.cooldown
        if cooldown and cooldown.GetCooldownTimes then
            local start, duration = cooldown:GetCooldownTimes()
            if start and duration and type(start) == "number" and type(duration) == "number" and duration > 0 then
                -- Only count as "on cooldown" if duration > 3000ms (3 sec)
                if duration > GCD_THRESHOLD then
                    -- Convert to seconds for remaining time check
                    local startSec = start / 1000
                    local durationSec = duration / 1000
                    local remaining = (startSec + durationSec) - GetTime()
                    if remaining > 0.1 then
                        isReady = false
                    end
                end
            end
        end
    end)
    
    return isReady
end

local function GetSlotInfo(trackerKey, slotIndex)
    -- Use TUICD.Cooldowns.GetOrderedIcons if available (same order as layout/list)
    local icons
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = GetViewer(trackerKey)
        if viewer then
            icons = Cooldowns.GetOrderedIcons(viewer, trackerKey)
        else
            icons = {}
        end
    else
        -- Fallback to local CollectIcons
        icons = CollectIcons(trackerKey)
    end
    
    local icon = icons[slotIndex]
    
    if not icon then return nil end
    
    local info = {
        icon = icon,
        isActive = true,  -- Will be set by visual state check
        texture = nil,
        name = "Slot " .. slotIndex,
    }
    
    -- Get visual state (ready vs on cooldown) without doing cooldown math
    info.isActive = GetIconVisualState(icon)
    
    -- Get texture safely
    local textureObj = icon.Icon or icon.icon
    if textureObj then
        pcall(function()
            info.texture = textureObj:GetTexture()
        end)
    end
    
    return info
end

local function GetSlotCount(trackerKey)
    -- Use TUICD.Cooldowns.GetOrderedIcons if available (same order as layout/list)
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = GetViewer(trackerKey)
        if viewer then
            return #Cooldowns.GetOrderedIcons(viewer, trackerKey)
        end
    end
    -- Fallback
    return #CollectIcons(trackerKey)
end

-- ============================================================================
-- HIGHLIGHT FRAME CREATION
-- ============================================================================

local function CreateHighlightFrame(trackerKey, slotIndex)
    if highlightFrames[trackerKey][slotIndex] then
        return highlightFrames[trackerKey][slotIndex]
    end
    
    local trackerType = TRACKER_TYPES[trackerKey]
    local frameName = trackerType.framePrefix .. slotIndex
    local size = GetHighlightSize(trackerKey, slotIndex)
    
    -- Check if Masque is enabled for this tracker
    -- For custom highlights, use customTrackers setting
    local masqueTrackerKey = (trackerKey == "custom") and "customTrackers" or trackerKey
    local useMasque = TUICD.Cooldowns and TUICD.Cooldowns.IsMasqueAvailable and TUICD.Cooldowns:IsMasqueAvailable()
    local masqueEnabled = useMasque and TUICD.Database and TUICD.Database:GetTrackerSetting(masqueTrackerKey, "useMasque")
    
    local frame = CreateFrame("Button", frameName, UIParent, "BackdropTemplate")
    frame:SetSize(size, size)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    
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
    
    -- Cooldown spiral (uses CooldownFrameTemplate which includes countdown text)
    frame.cooldown = CreateFrame("Cooldown", frameName .. "_Cooldown", frame, "CooldownFrameTemplate")
    frame.Cooldown = frame.cooldown  -- Masque expects .Cooldown
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetDrawEdge(not masqueEnabled)  -- Masque handles edge
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    
    -- Apply sweep and countdown text settings (per-icon overrides tracker-level)
    local showSweep = GetShowSweep(trackerKey, slotIndex)  -- Per-icon setting
    local showCountdownText = GetShowCountdownText(trackerKey, slotIndex)  -- Per-icon setting
    
    -- Fall back to tracker-level settings if per-icon not set
    if showSweep == nil and TUICD.Database then
        local sweepSetting = TUICD.Database:GetTrackerSetting(trackerKey, "showSweep")
        showSweep = (sweepSetting ~= nil) and sweepSetting or true
    end
    if showCountdownText == nil and TUICD.Database then
        local countdownSetting = TUICD.Database:GetTrackerSetting(trackerKey, "showCountdownText")
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
    frame.cooldown._TUI_trackerKey = trackerKey
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
    
    -- Charge/stack count text (bottom right corner, explicitly above cooldown)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    frame.Count = frame.count  -- Masque expects .Count
    frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.count:SetJustifyH("RIGHT")
    frame.count:SetDrawLayer("OVERLAY", 7)  -- High sublayer to ensure above cooldown text
    
    -- Border texture for Masque
    frame.Border = frame:CreateTexture(nil, "OVERLAY")
    frame.Border:SetAllPoints(frame)
    frame.Border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.Border:SetBlendMode("ADD")
    frame.Border:SetAlpha(0)  -- Hidden, Masque controls this
    
    -- Proc glow overlay (using Blizzard's built-in glow)
    -- We'll use ActionButton overlay glow system if available
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
    
    -- Custom accessibility label (user-defined text overlay)
    frame.customLabel = frame:CreateFontString(nil, "OVERLAY")
    frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    frame.customLabel:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.customLabel:SetTextColor(1, 1, 1, 1)
    frame.customLabel:SetShadowOffset(1, -1)
    frame.customLabel:SetShadowColor(0, 0, 0, 1)
    frame.customLabel:SetDrawLayer("OVERLAY", 7)
    frame.customLabel:Hide()
    
    -- Store references
    frame.trackerKey = trackerKey
    frame.slotIndex = slotIndex
    frame._TUI_useMasque = masqueEnabled
    
    -- Set initial position
    local pos = GetHighlightPosition(trackerKey, slotIndex)
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -200 + (slotIndex * 60), -150)
    end
    
    frame:Hide()
    highlightFrames[trackerKey][slotIndex] = frame
    
    -- Register with LayoutMode for drag support
    if TUICD.LayoutMode and TUICD.LayoutMode.RegisterPerIconFrame then
        local trackerType = TRACKER_TYPES[trackerKey]
        local displayName = (trackerType and trackerType.displayName or trackerKey) .. " Icon " .. slotIndex
        TUICD.LayoutMode:RegisterPerIconFrame(frame, trackerKey, slotIndex, displayName)
    end
    
    -- Add to Masque group if enabled
    if masqueEnabled then
        local masqueGroup = TUICD.Cooldowns:GetMasqueGroup(masqueTrackerKey)
        if masqueGroup then
            masqueGroup:AddButton(frame, {
                Icon = frame.icon,
                Cooldown = frame.cooldown,
                Count = frame.count,
                Border = frame.Border,
            })
            frame._TUI_MasqueGroup = masqueTrackerKey
            dprint("Added highlight frame to Masque group:", trackerKey, slotIndex)
        end
    end
    
    dprint("Created highlight frame:", trackerKey, slotIndex)
    return frame
end

-- ============================================================================
-- ASPECT RATIO
-- ============================================================================

local function ParseAspectRatio(aspectStr, trackerKey, slotIndex, state)
    if aspectStr == "custom" then
        local db = GetDB(trackerKey)
        local w = db and db[state].customAspectW[slotIndex] or 1
        local h = db and db[state].customAspectH[slotIndex] or 1
        return w, h
    end
    
    local w, h = aspectStr:match("(%d+):(%d+)")
    if w and h then
        return tonumber(w), tonumber(h)
    end
    return 1, 1
end

local function ApplyAspectRatio(frame, size, aspectStr, trackerKey, slotIndex, state)
    local ratioW, ratioH = ParseAspectRatio(aspectStr, trackerKey, slotIndex, state)
    local width, height
    
    if ratioW >= ratioH then
        width = size
        height = size * (ratioH / ratioW)
    else
        height = size
        width = size * (ratioW / ratioH)
    end
    
    frame:SetSize(width, height)
    
    -- Adjust texture coordinates to crop/zoom icon instead of stretching
    -- This makes non-square frames show a cropped portion of the icon
    if frame.icon and not frame._TUI_useMasque then
        local baseInset = 0.08  -- Standard WoW icon inset
        local texRange = 1 - (baseInset * 2)  -- 0.84
        
        local left, right, top, bottom = baseInset, 1 - baseInset, baseInset, 1 - baseInset
        
        if ratioW > ratioH then
            -- Wider than tall - crop top/bottom
            local cropFactor = ratioH / ratioW
            local vertRange = texRange * cropFactor
            local vertOffset = (texRange - vertRange) / 2
            top = baseInset + vertOffset
            bottom = 1 - baseInset - vertOffset
        elseif ratioH > ratioW then
            -- Taller than wide - crop left/right  
            local cropFactor = ratioW / ratioH
            local horizRange = texRange * cropFactor
            local horizOffset = (texRange - horizRange) / 2
            left = baseInset + horizOffset
            right = 1 - baseInset - horizOffset
        end
        
        frame.icon:SetTexCoord(left, right, top, bottom)
    end
end

-- ============================================================================
-- UPDATE LOGIC
-- ============================================================================

local function UpdateHighlightFrame(trackerKey, slotIndex)
    local frame = highlightFrames[trackerKey][slotIndex]
    if not frame then return end
    
    -- Update sweep and countdown text settings (per-icon overrides tracker-level)
    if frame.cooldown then
        local showSweep = GetShowSweep(trackerKey, slotIndex)  -- Per-icon setting
        local showCountdownText = GetShowCountdownText(trackerKey, slotIndex)  -- Per-icon setting
        
        -- Fall back to tracker-level settings if per-icon not set
        if showSweep == nil and TUICD.Database then
            local sweepSetting = TUICD.Database:GetTrackerSetting(trackerKey, "showSweep")
            showSweep = (sweepSetting ~= nil) and sweepSetting or true
        end
        if showCountdownText == nil and TUICD.Database then
            local countdownSetting = TUICD.Database:GetTrackerSetting(trackerKey, "showCountdownText")
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
    
    if not IsHighlightEnabled(trackerKey, slotIndex) then
        frame:Hide()
        return
    end
    
    local slotInfo = GetSlotInfo(trackerKey, slotIndex)
    
    -- Check if Layout mode is active
    local isLayoutMode = false
    local layoutContainer = _G["TweaksUI_LayoutContainer"]
    if layoutContainer and layoutContainer:IsShown() then
        isLayoutMode = true
    end
    
    if not slotInfo then
        if isLayoutMode then
            local size = GetHighlightSize(trackerKey, slotIndex, "active")
            local aspectRatio = GetHighlightAspectRatio(trackerKey, slotIndex, "active")
            ApplyAspectRatio(frame, size, aspectRatio, trackerKey, slotIndex, "active")
            frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            frame.icon:SetDesaturated(true)
            frame.cooldown:Clear()
            if frame.count then frame.count:Hide() end
            if frame.glowFrame then frame.glowFrame:Hide() end
            frame:SetAlpha(0.5)
            frame:Show()
        else
            frame:Hide()
        end
        return
    end
    
    -- Determine current state based on cooldown
    local currentState = slotInfo.isActive and "active" or "inactive"
    local showThisState = GetShowState(trackerKey, slotIndex, currentState)
    
    -- During layout mode, always show
    if isLayoutMode then
        local size = GetHighlightSize(trackerKey, slotIndex, "active")
        local aspectRatio = GetHighlightAspectRatio(trackerKey, slotIndex, "active")
        ApplyAspectRatio(frame, size, aspectRatio, trackerKey, slotIndex, "active")
        
        if slotInfo.texture then
            frame.icon:SetTexture(slotInfo.texture)
        else
            frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        
        if not showThisState then
            frame.icon:SetDesaturated(true)
            frame:SetAlpha(0.4)
        else
            local saturated = GetHighlightSaturation(trackerKey, slotIndex, currentState)
            local opacity = GetHighlightOpacity(trackerKey, slotIndex, currentState)
            frame.icon:SetDesaturated(not saturated)
            frame:SetAlpha(opacity)
        end
        
        frame.cooldown:Clear()
        if frame.count then frame.count:Hide() end
        if frame.glowFrame then frame.glowFrame:Hide() end
        frame:Show()
        return
    end
    
    -- NOTE: Don't hide early based on showThisState - we'll do final visibility check at the end
    -- after confirming cooldown state with GCD threshold
    
    -- Get state-specific settings
    local size = GetHighlightSize(trackerKey, slotIndex, currentState)
    local opacity = GetHighlightOpacity(trackerKey, slotIndex, currentState)
    local saturated = GetHighlightSaturation(trackerKey, slotIndex, currentState)
    local aspectRatio = GetHighlightAspectRatio(trackerKey, slotIndex, currentState)
    
    -- Apply size and aspect ratio
    ApplyAspectRatio(frame, size, aspectRatio, trackerKey, slotIndex, currentState)
    
    -- Update icon texture
    if slotInfo.texture then
        frame.icon:SetTexture(slotInfo.texture)
    else
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    -- Apply saturation and opacity
    frame.icon:SetDesaturated(not saturated)
    frame:SetAlpha(opacity)
    
    -- =========================================================================
    -- COOLDOWN AND CHARGE UPDATES: Use cached spellID for API calls
    -- The spellID cache is populated outside combat, so we can safely use
    -- C_Spell APIs during combat without reading from the (secret) source icon
    -- =========================================================================
    local sourceIcon = slotInfo.icon
    local sourceCooldown = sourceIcon.Cooldown or sourceIcon.cooldown
    
    -- Get spellID from cache first (populated outside combat)
    -- This is critical for Midnight compatibility
    local spellID = GetCachedSpellID(trackerKey, slotIndex)
    
    -- If cache miss (shouldn't happen normally), try direct read (only works outside combat)
    if not spellID and not InCombatLockdown() then
        spellID = ExtractSpellID(sourceIcon)
        -- Update cache while we're at it
        if spellID then
            spellIDCache[trackerKey][slotIndex] = spellID
        end
    end
    
    -- For spells: Use C_Spell API (charges first, then regular cooldown)
    -- Pass directly to SetCooldownFromDurationObject - NO conditionals on Duration objects
    if spellID and C_Spell then
        -- Try charges cooldown first (for spells with charges like Fire Blast, Roll)
        if C_Spell.GetSpellChargesCooldownDuration and frame.cooldown.SetCooldownFromDurationObject then
            pcall(function()
                frame.cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellChargesCooldownDuration(spellID), true)
            end)
        -- Fallback to regular cooldown duration
        elseif C_Spell.GetSpellCooldownDuration and frame.cooldown.SetCooldownFromDurationObject then
            pcall(function()
                frame.cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(spellID), true)
            end)
        end
    -- For non-spells (items/equipment): Pass through from source cooldown frame
    elseif sourceCooldown and sourceCooldown.GetCooldownDuration and frame.cooldown.SetCooldownFromDurationObject then
        pcall(function()
            frame.cooldown:SetCooldownFromDurationObject(sourceCooldown:GetCooldownDuration(), true)
        end)
    end
    
    -- =========================================================================
    -- CHARGE/COUNT DISPLAY: Copy count/charge text
    -- CRITICAL: No conditionals on returned values - they may be secret
    -- Just pass directly to SetText and let Blizzard handle it
    -- =========================================================================
    
    -- Method 1: Use C_Spell.GetSpellDisplayCount API for spells
    -- Pass directly to SetText - NO conditionals on the result
    if spellID and C_Spell and C_Spell.GetSpellDisplayCount then
        pcall(function()
            frame.count:SetText(C_Spell.GetSpellDisplayCount(spellID))
            frame.count:Show()
        end)
    else
        -- Method 2: Source icon's Count FontString pass-through (for items/equipment)
        local sourceCountFS = sourceIcon.Count or sourceIcon.count or sourceIcon.CountText or sourceIcon.countText
        
        -- Try cooldown frame's count if not found on icon
        if not sourceCountFS and sourceCooldown then
            sourceCountFS = sourceCooldown.Count or sourceCooldown.count or sourceCooldown.Charges or sourceCooldown.charges
        end
        
        -- Try icon's children if still not found
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
            if sourceCountFS.IsShown then
                pcall(function()
                    frame.count:SetAlphaFromBoolean(sourceCountFS:IsShown(), 1, 0)
                end)
            end
            frame.count:Show()
        else
            frame.count:SetText("")
            frame.count:Hide()
        end
    end
    
    -- =========================================================================
    -- Copy glow state from source icon (proc/spell activation glow)
    -- =========================================================================
    local showGlow = false
    
    -- First, check if per-icon proc glow is enabled (default true)
    local procGlowEnabled = GetShowProcGlow(trackerKey, slotIndex)
    if procGlowEnabled == nil then procGlowEnabled = true end
    
    if procGlowEnabled then
        -- Method 1: Direct API check using IsSpellOverlayed (most reliable)
        if spellID and IsSpellOverlayed then
            pcall(function()
                if IsSpellOverlayed(spellID) then
                    showGlow = true
                end
            end)
        end
        
        -- Method 2: Check source icon's overlay frames (fallback)
        if not showGlow then
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
    local cooldownTextScale = GetCooldownTextScale(trackerKey, slotIndex)
    local cooldownTextColor = GetCooldownTextColor(trackerKey, slotIndex)
    local cooldownTextOffsetX = GetCooldownTextOffsetX(trackerKey, slotIndex)
    local cooldownTextOffsetY = GetCooldownTextOffsetY(trackerKey, slotIndex)
    local cooldownTextAnchor = GetCooldownTextAnchor(trackerKey, slotIndex)
    local countTextScale = GetCountTextScale(trackerKey, slotIndex)
    local countTextColor = GetCountTextColor(trackerKey, slotIndex)
    local countTextOffsetX = GetCountTextOffsetX(trackerKey, slotIndex)
    local countTextOffsetY = GetCountTextOffsetY(trackerKey, slotIndex)
    local countTextAnchor = GetCountTextAnchor(trackerKey, slotIndex)
    
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
    
    -- Custom accessibility label
    if frame.customLabel then
        if GetLabelEnabled(trackerKey, slotIndex) then
            local labelText = GetLabelText(trackerKey, slotIndex)
            local fontSize = GetLabelFontSize(trackerKey, slotIndex)
            local labelColor = GetLabelColor(trackerKey, slotIndex)
            local offsetX = GetLabelOffsetX(trackerKey, slotIndex)
            local offsetY = GetLabelOffsetY(trackerKey, slotIndex)
            local labelAnchor = GetLabelAnchor(trackerKey, slotIndex)
            
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
    
    -- =========================================================================
    -- FINAL VISIBILITY: Check cooldown state per-icon and hide/show accordingly
    -- Only hide if we can CONFIRM this specific icon has a real cooldown > GCD
    -- Default to SHOWING if we can't determine cooldown state
    -- =========================================================================
    local showInactive = GetShowState(trackerKey, slotIndex, "inactive")
    local showActive = GetShowState(trackerKey, slotIndex, "active")
    
    -- Default to "ready" (not on cooldown) - only set to true if we CONFIRM a real cooldown
    local thisIconOnCooldown = false
    
    -- Check actual cooldown duration from source cooldown
    -- NOTE: GetCooldownTimes returns MILLISECONDS
    pcall(function()
        if sourceCooldown and sourceCooldown.GetCooldownTimes then
            local start, duration = sourceCooldown:GetCooldownTimes()
            
            if start and duration and type(start) == "number" and type(duration) == "number" and duration > 0 then
                -- Only count as "on cooldown" if duration > 3000ms (3 sec) - ignore GCD (~1500ms)
                if duration > GCD_THRESHOLD then
                    -- Convert ms to seconds for comparison with GetTime()
                    local startSec = start / 1000
                    local durationSec = duration / 1000
                    local remaining = (startSec + durationSec) - GetTime()
                    if remaining > 0.1 then
                        thisIconOnCooldown = true
                    end
                end
            end
        end
    end)
    
    -- Fallback: Try frame's own cooldown
    if not thisIconOnCooldown then
        pcall(function()
            if frame.cooldown and frame.cooldown.GetCooldownTimes then
                local start, duration = frame.cooldown:GetCooldownTimes()
                
                if start and duration and type(start) == "number" and type(duration) == "number" and duration > 0 then
                    if duration > GCD_THRESHOLD then
                        local startSec = start / 1000
                        local durationSec = duration / 1000
                        local remaining = (startSec + durationSec) - GetTime()
                        if remaining > 0.1 then
                            thisIconOnCooldown = true
                        end
                    end
                end
            end
        end)
    end
    
    -- Store state for debugging/tracking
    iconCooldownState[trackerKey][slotIndex] = thisIconOnCooldown
    
    -- Check tracker visibility conditions (combat, group, instance, etc.)
    local trackerVisible = ShouldHighlightBeVisible(trackerKey)
    
    -- Notify dock if this icon is docked
    local dockAssignment = GetDockAssignment(trackerKey, slotIndex)
    if dockAssignment and TUICD.Docks then
        TUICD.Docks:NotifyIconUpdate(trackerKey, slotIndex)
    end
    
    -- Determine visibility based on confirmed cooldown state AND tracker visibility
    local shouldShow = trackerVisible
    if shouldShow then
        if thisIconOnCooldown then
            -- CONFIRMED on a real cooldown (> GCD) - check if user wants inactive state shown
            if not showInactive then
                shouldShow = false
            end
        else
            -- Either ready OR couldn't confirm cooldown - treat as ready
            -- Check if user wants active state shown
            if not showActive then
                shouldShow = false
            end
        end
    end
    
    if shouldShow then
        -- Apply correct state's visual settings
        local actualState = thisIconOnCooldown and "inactive" or "active"
        local actualOpacity = GetHighlightOpacity(trackerKey, slotIndex, actualState)
        local actualSaturated = GetHighlightSaturation(trackerKey, slotIndex, actualState)
        frame:SetAlpha(actualOpacity)
        frame.icon:SetDesaturated(not actualSaturated)
        frame:Show()
    else
        frame:Hide()
    end
end

local function UpdateAllHighlights(trackerKey)
    local db = GetDB(trackerKey)
    if not db then return end
    
    local inCombat = InCombatLockdown()
    
    for slotIndex, enabled in pairs(db.enabled) do
        if enabled then
            -- Only create frames outside of combat to avoid taint
            if not highlightFrames[trackerKey][slotIndex] then
                if not inCombat then
                    pcall(CreateHighlightFrame, trackerKey, slotIndex)
                end
            end
            -- Only update if frame exists
            if highlightFrames[trackerKey][slotIndex] then
                local success, err = pcall(UpdateHighlightFrame, trackerKey, slotIndex)
                if not success and debugMode then
                    dprint("UpdateHighlightFrame error:", trackerKey, slotIndex, tostring(err))
                end
            end
        end
    end
end

-- ============================================================================
-- LAYOUT INTEGRATION
-- ============================================================================

local function CreateLayoutWrapper(trackerKey, slotIndex)
    local frame = highlightFrames[trackerKey][slotIndex]
    if not frame then return nil end
    
    local trackerType = TRACKER_TYPES[trackerKey]
    local wrapperId = trackerType.framePrefix .. slotIndex
    
    local wrapper = {
        id = wrapperId,
        name = trackerType.displayName .. " #" .. slotIndex,
        category = "Cooldowns",
        frame = frame,
        hideSizeMatching = true,
        defaultPosition = {
            point = "CENTER",
            x = -200 + (slotIndex * 60),
            y = -150,
        },
        contentFrames = {},
        
        onPositionChanged = function(self, point, relFrame, relPoint, x, y)
            -- Skip if docked - dock controls position
            if GetDockAssignment(trackerKey, slotIndex) then return end
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point, x, y)
            SetHighlightPosition(trackerKey, slotIndex, point, point, x, y)
        end,
        
        GetPosition = function(self)
            local point, relTo, relPoint, x, y = frame:GetPoint(1)
            return { point = point, relFrame = relTo, relPoint = relPoint, x = x, y = y }
        end,
        
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            -- Skip if docked - dock controls position
            if GetDockAssignment(trackerKey, slotIndex) then return end
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
            if frame and width and height then
                frame:SetSize(width, height)
            end
        end,
        
        IsShown = function(self)
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
        
        sizeLocked = false,
        SetSizeLocked = function(self, locked)
            self.sizeLocked = locked
        end,
        IsSizeLocked = function(self)
            return self.sizeLocked
        end,
        
        ForceSetSize = function(self, width, height)
            if frame and width and height then
                frame:SetSize(width, height)
            end
        end,
        
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
    
    return wrapper
end

local function RegisterWithLayout(trackerKey, slotIndex)
    local frame = highlightFrames[trackerKey][slotIndex]
    if not frame then return end
    
    local trackerType = TRACKER_TYPES[trackerKey]
    local wrapperId = trackerType.framePrefix .. slotIndex
    
    if layoutWrappers[trackerKey][slotIndex] then
        return layoutWrappers[trackerKey][slotIndex]
    end
    
    local wrapper = CreateLayoutWrapper(trackerKey, slotIndex)
    if not wrapper then return nil end
    
    layoutWrappers[trackerKey][slotIndex] = wrapper
    
    local Layout = TUICD.Layout
    if Layout and Layout.RegisterElement then
        Layout:RegisterElement(wrapperId, {
            name = wrapper.name,
            category = "Cooldowns",
            tuiFrame = wrapper,
            defaultPosition = wrapper.defaultPosition,
            onPositionChanged = function(id, pos)
                if wrapper.onPositionChanged then
                    wrapper:onPositionChanged(pos.point, pos.relFrame, pos.relPoint, pos.x, pos.y)
                end
            end,
        })
        dprint("Registered with Layout:", trackerKey, slotIndex)
    end
    
    return wrapper
end

local function UnregisterFromLayout(trackerKey, slotIndex)
    local trackerType = TRACKER_TYPES[trackerKey]
    local wrapperId = trackerType.framePrefix .. slotIndex
    
    local Layout = TUICD.Layout
    if Layout and Layout.UnregisterElement then
        Layout:UnregisterElement(wrapperId)
    end
    
    layoutWrappers[trackerKey][slotIndex] = nil
    dprint("Unregistered from Layout:", trackerKey, slotIndex)
end

local function RegisterAllWithLayout(trackerKey)
    local db = GetDB(trackerKey)
    if not db then return end
    
    for slotIndex, enabled in pairs(db.enabled) do
        if enabled then
            if highlightFrames[trackerKey][slotIndex] then
                RegisterWithLayout(trackerKey, slotIndex)
            end
        end
    end
end

-- ============================================================================
-- UPDATE SYSTEM - Simple OnUpdate for reliable updates
-- ============================================================================

local updateFrames = {}  -- [trackerKey] = frame

local function StartUpdateTicker(trackerKey)
    if updateFrames[trackerKey] then return end
    
    local updateFrame = CreateFrame("Frame")
    
    updateFrame:SetScript("OnUpdate", function(self, elapsed)
        pcall(UpdateAllHighlights, trackerKey)
    end)
    
    updateFrames[trackerKey] = updateFrame
    dprint("Started OnUpdate:", trackerKey)
end

local function StopUpdateTicker(trackerKey)
    if updateFrames[trackerKey] then
        updateFrames[trackerKey]:SetScript("OnUpdate", nil)
        updateFrames[trackerKey] = nil
        dprint("Stopped OnUpdate:", trackerKey)
    end
end

-- ============================================================================
-- TRACKER HIDE ENFORCEMENT
-- ============================================================================

local hideEnforcementTickers = {}

local function StartHideEnforcement(trackerKey)
    if hideEnforcementTickers[trackerKey] then return end
    
    hideEnforcementTickers[trackerKey] = C_Timer.NewTicker(0.2, function()
        if not IsTrackerHidden(trackerKey) then
            StopHideEnforcement(trackerKey)
            return
        end
        
        local viewer = GetViewer(trackerKey)
        if viewer then
            -- Use alpha instead of Hide to avoid secret value issues on re-show
            if viewer:GetAlpha() > 0 then
                viewer:SetAlpha(0)
                viewer:EnableMouse(false)
            end
        end
    end)
end

local function StopHideEnforcement(trackerKey)
    if hideEnforcementTickers[trackerKey] then
        hideEnforcementTickers[trackerKey]:Cancel()
        hideEnforcementTickers[trackerKey] = nil
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function CooldownHighlights:EnableHighlight(trackerKey, slotIndex, enabled)
    SetHighlightEnabled(trackerKey, slotIndex, enabled)
    
    if enabled then
        -- Only create frames outside combat to avoid taint
        if not highlightFrames[trackerKey][slotIndex] and not InCombatLockdown() then
            CreateHighlightFrame(trackerKey, slotIndex)
        end
        if highlightFrames[trackerKey][slotIndex] then
            RegisterWithLayout(trackerKey, slotIndex)
            
            -- If this icon has a dock assignment, reparent to dock
            local dockAssignment = GetDockAssignment(trackerKey, slotIndex)
            if dockAssignment and TUICD.Docks then
                TUICD.Docks:AssignIcon(dockAssignment, trackerKey, slotIndex)
            end
        end
        
        -- Start ticker if needed
        local db = GetDB(trackerKey)
        local hasEnabled = false
        for _, e in pairs(db.enabled) do
            if e then hasEnabled = true break end
        end
        if hasEnabled then
            StartUpdateTicker(trackerKey)
        end
    else
        if highlightFrames[trackerKey][slotIndex] then
            highlightFrames[trackerKey][slotIndex]:Hide()
        end
        UnregisterFromLayout(trackerKey, slotIndex)
        
        -- Stop ticker if no highlights enabled
        local db = GetDB(trackerKey)
        local hasEnabled = false
        for _, e in pairs(db.enabled) do
            if e then hasEnabled = true break end
        end
        if not hasEnabled then
            StopUpdateTicker(trackerKey)
        end
    end
    
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:SetShowState(trackerKey, slotIndex, state, show)
    SetShowState(trackerKey, slotIndex, state, show)
end

function CooldownHighlights:GetShowState(trackerKey, slotIndex, state)
    return GetShowState(trackerKey, slotIndex, state)
end

function CooldownHighlights:SetSize(trackerKey, slotIndex, state, size)
    SetHighlightSize(trackerKey, slotIndex, state, size)
end

function CooldownHighlights:GetSize(trackerKey, slotIndex, state)
    return GetHighlightSize(trackerKey, slotIndex, state)
end

function CooldownHighlights:SetOpacity(trackerKey, slotIndex, state, opacity)
    SetHighlightOpacity(trackerKey, slotIndex, state, opacity)
end

function CooldownHighlights:GetOpacity(trackerKey, slotIndex, state)
    return GetHighlightOpacity(trackerKey, slotIndex, state)
end

function CooldownHighlights:SetSaturation(trackerKey, slotIndex, state, saturated)
    SetHighlightSaturation(trackerKey, slotIndex, state, saturated)
end

function CooldownHighlights:GetSaturation(trackerKey, slotIndex, state)
    return GetHighlightSaturation(trackerKey, slotIndex, state)
end

function CooldownHighlights:SetAspectRatio(trackerKey, slotIndex, state, ratio)
    SetHighlightAspectRatio(trackerKey, slotIndex, state, ratio)
end

function CooldownHighlights:GetAspectRatio(trackerKey, slotIndex, state)
    return GetHighlightAspectRatio(trackerKey, slotIndex, state)
end

function CooldownHighlights:SetCustomAspectRatio(trackerKey, slotIndex, state, width, height)
    local db = GetDB(trackerKey)
    if db then
        db[state].customAspectW[slotIndex] = width
        db[state].customAspectH[slotIndex] = height
    end
    SetHighlightAspectRatio(trackerKey, slotIndex, state, "custom")
end

function CooldownHighlights:GetCustomAspectRatio(trackerKey, slotIndex, state)
    local db = GetDB(trackerKey)
    return db and db[state].customAspectW[slotIndex] or 1, db and db[state].customAspectH[slotIndex] or 1
end

function CooldownHighlights:IsTrackerHidden(trackerKey)
    return IsTrackerHidden(trackerKey)
end

function CooldownHighlights:SetTrackerHidden(trackerKey, hidden)
    SetTrackerHidden(trackerKey, hidden)
    self:ApplyTrackerVisibility(trackerKey)
end

-- Per-icon hidden API (hides icon completely from tracker)
function CooldownHighlights:IsIconHidden(trackerKey, slotIndex)
    return IsIconHidden(trackerKey, slotIndex)
end

function CooldownHighlights:SetIconHidden(trackerKey, slotIndex, hidden)
    SetIconHidden(trackerKey, slotIndex, hidden)
    UpdateHighlightFrame(trackerKey, slotIndex)
    -- Refresh the tracker layout to apply alpha=0 on hidden icons
    if TUICD.Cooldowns and TUICD.Cooldowns.RefreshTrackerLayout then
        TUICD.Cooldowns.RefreshTrackerLayout(trackerKey)
    end
end

-- Dock assignment API
function CooldownHighlights:GetDockAssignment(trackerKey, slotIndex)
    return GetDockAssignment(trackerKey, slotIndex)
end

function CooldownHighlights:SetDockAssignment(trackerKey, slotIndex, dockIndex)
    SetDockAssignment(trackerKey, slotIndex, dockIndex)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

-- Custom label API
function CooldownHighlights:SetLabelEnabled(trackerKey, slotIndex, enabled)
    SetLabelEnabled(trackerKey, slotIndex, enabled)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetLabelEnabled(trackerKey, slotIndex)
    return GetLabelEnabled(trackerKey, slotIndex)
end

function CooldownHighlights:SetLabelText(trackerKey, slotIndex, text)
    SetLabelText(trackerKey, slotIndex, text)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetLabelText(trackerKey, slotIndex)
    return GetLabelText(trackerKey, slotIndex)
end

function CooldownHighlights:SetLabelFontSize(trackerKey, slotIndex, size)
    SetLabelFontSize(trackerKey, slotIndex, size)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetLabelFontSize(trackerKey, slotIndex)
    return GetLabelFontSize(trackerKey, slotIndex)
end

function CooldownHighlights:SetLabelColor(trackerKey, slotIndex, color)
    SetLabelColor(trackerKey, slotIndex, color)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetLabelColor(trackerKey, slotIndex)
    return GetLabelColor(trackerKey, slotIndex)
end

function CooldownHighlights:SetLabelOffsetX(trackerKey, slotIndex, offset)
    SetLabelOffsetX(trackerKey, slotIndex, offset)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetLabelOffsetX(trackerKey, slotIndex)
    return GetLabelOffsetX(trackerKey, slotIndex)
end

function CooldownHighlights:SetLabelOffsetY(trackerKey, slotIndex, offset)
    SetLabelOffsetY(trackerKey, slotIndex, offset)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetLabelOffsetY(trackerKey, slotIndex)
    return GetLabelOffsetY(trackerKey, slotIndex)
end

-- Text scale API
function CooldownHighlights:SetCooldownTextScale(trackerKey, slotIndex, scale)
    SetCooldownTextScale(trackerKey, slotIndex, scale)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCooldownTextScale(trackerKey, slotIndex)
    return GetCooldownTextScale(trackerKey, slotIndex)
end

function CooldownHighlights:SetCountTextScale(trackerKey, slotIndex, scale)
    SetCountTextScale(trackerKey, slotIndex, scale)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCountTextScale(trackerKey, slotIndex)
    return GetCountTextScale(trackerKey, slotIndex)
end

function CooldownHighlights:SetCooldownTextColor(trackerKey, slotIndex, color)
    SetCooldownTextColor(trackerKey, slotIndex, color)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCooldownTextColor(trackerKey, slotIndex)
    return GetCooldownTextColor(trackerKey, slotIndex)
end

function CooldownHighlights:SetCountTextColor(trackerKey, slotIndex, color)
    SetCountTextColor(trackerKey, slotIndex, color)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCountTextColor(trackerKey, slotIndex)
    return GetCountTextColor(trackerKey, slotIndex)
end

function CooldownHighlights:SetCooldownTextOffsetX(trackerKey, slotIndex, offset)
    SetCooldownTextOffsetX(trackerKey, slotIndex, offset)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCooldownTextOffsetX(trackerKey, slotIndex)
    return GetCooldownTextOffsetX(trackerKey, slotIndex)
end

function CooldownHighlights:SetCooldownTextOffsetY(trackerKey, slotIndex, offset)
    SetCooldownTextOffsetY(trackerKey, slotIndex, offset)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCooldownTextOffsetY(trackerKey, slotIndex)
    return GetCooldownTextOffsetY(trackerKey, slotIndex)
end

function CooldownHighlights:SetCountTextOffsetX(trackerKey, slotIndex, offset)
    SetCountTextOffsetX(trackerKey, slotIndex, offset)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCountTextOffsetX(trackerKey, slotIndex)
    return GetCountTextOffsetX(trackerKey, slotIndex)
end

function CooldownHighlights:SetCountTextOffsetY(trackerKey, slotIndex, offset)
    SetCountTextOffsetY(trackerKey, slotIndex, offset)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCountTextOffsetY(trackerKey, slotIndex)
    return GetCountTextOffsetY(trackerKey, slotIndex)
end

function CooldownHighlights:SetCooldownTextAnchor(trackerKey, slotIndex, anchor)
    SetCooldownTextAnchor(trackerKey, slotIndex, anchor)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCooldownTextAnchor(trackerKey, slotIndex)
    return GetCooldownTextAnchor(trackerKey, slotIndex)
end

function CooldownHighlights:SetCountTextAnchor(trackerKey, slotIndex, anchor)
    SetCountTextAnchor(trackerKey, slotIndex, anchor)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetCountTextAnchor(trackerKey, slotIndex)
    return GetCountTextAnchor(trackerKey, slotIndex)
end

function CooldownHighlights:SetLabelAnchor(trackerKey, slotIndex, anchor)
    SetLabelAnchor(trackerKey, slotIndex, anchor)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetLabelAnchor(trackerKey, slotIndex)
    return GetLabelAnchor(trackerKey, slotIndex)
end

-- Per-icon sweep visibility (overrides tracker-level setting when set)
function CooldownHighlights:SetShowSweep(trackerKey, slotIndex, show)
    SetShowSweep(trackerKey, slotIndex, show)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetShowSweep(trackerKey, slotIndex)
    return GetShowSweep(trackerKey, slotIndex)
end

-- Per-icon countdown text visibility (overrides tracker-level setting when set)
function CooldownHighlights:SetShowCountdownText(trackerKey, slotIndex, show)
    SetShowCountdownText(trackerKey, slotIndex, show)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetShowCountdownText(trackerKey, slotIndex)
    return GetShowCountdownText(trackerKey, slotIndex)
end

-- Per-icon proc glow visibility (nil = show, default true)
function CooldownHighlights:SetShowProcGlow(trackerKey, slotIndex, show)
    SetShowProcGlow(trackerKey, slotIndex, show)
    UpdateHighlightFrame(trackerKey, slotIndex)
end

function CooldownHighlights:GetShowProcGlow(trackerKey, slotIndex)
    return GetShowProcGlow(trackerKey, slotIndex)
end

function CooldownHighlights:RefreshAllHighlights(trackerKey)
    -- Refresh all highlight frames for a tracker (used when tracker-level settings change)
    UpdateAllHighlights(trackerKey)
end

-- Helper to check for CDM viewer layout issues (duplicate icons, stale state)
local function HasViewerLayoutIssue(viewer)
    local hasIssue = false
    local iconCount = 0
    
    pcall(function()
        local seenIndices = {}
        local children = {viewer:GetChildren()}
        
        for _, child in ipairs(children) do
            -- Check if this looks like a CDM icon (has layoutIndex and cooldownID)
            if child.layoutIndex then
                -- Check for duplicate layoutIndex (Blizzard bug with stale icons between characters)
                if seenIndices[child.layoutIndex] then
                    hasIssue = true
                    dprint("Duplicate layoutIndex found:", child.layoutIndex)
                    return  -- Exit early, no need to check more
                end
                seenIndices[child.layoutIndex] = true
                
                -- Count valid icons
                if child.cooldownID then
                    iconCount = iconCount + 1
                end
            end
        end
    end)
    
    return hasIssue, iconCount
end

function CooldownHighlights:ApplyTrackerVisibility(trackerKey)
    local viewer = GetViewer(trackerKey)
    if not viewer then return end
    
    if IsTrackerHidden(trackerKey) then
        -- Use alpha + mouse disable instead of Hide() to avoid OnShow issues when unhiding
        viewer:SetAlpha(0)
        viewer:EnableMouse(false)
        StartHideEnforcement(trackerKey)
    else
        StopHideEnforcement(trackerKey)
        viewer:SetAlpha(1)
        viewer:EnableMouse(true)
        
        -- Only call Show() if viewer is actually hidden, and protect against secret value errors
        if not viewer:IsShown() then
            -- Check for layout issues before showing (Blizzard CDM bug with stale icons)
            local hasLayoutIssue, iconCount = HasViewerLayoutIssue(viewer)
            
            if hasLayoutIssue then
                -- Don't try to Show() - it will trigger RefreshLayout which errors on duplicates
                -- Alpha is already 1, so the viewer content is visible anyway
                dprint("Skipping Show() for " .. trackerKey .. " due to duplicate layoutIndex (Blizzard CDM stale icon bug)")
                return
            end
            
            -- Fix Midnight Beta secret value issue before showing
            pcall(function()
                for _, child in ipairs({viewer:GetChildren()}) do
                    -- Clear secret values by setting to false using rawset
                    rawset(child, "allowAvailableAlert", false)
                    rawset(child, "allowOnCooldownAlert", false)
                end
            end)
            
            -- Wrap Show() in pcall - if it fails, the viewer is at least visible via alpha
            pcall(viewer.Show, viewer)
        end
    end
end

function CooldownHighlights:GetSlotCount(trackerKey)
    return GetSlotCount(trackerKey)
end

function CooldownHighlights:GetSlotInfo(trackerKey, slotIndex)
    return GetSlotInfo(trackerKey, slotIndex)
end

function CooldownHighlights:GetFrame(trackerKey, slotIndex)
    if highlightFrames[trackerKey] then
        return highlightFrames[trackerKey][slotIndex]
    end
    return nil
end

function CooldownHighlights:IsEnabled(trackerKey, slotIndex)
    return IsHighlightEnabled(trackerKey, slotIndex)
end

function CooldownHighlights:GetTrackerTypes()
    return TRACKER_TYPES
end

-- Public API to refresh spellID cache (call when outside combat)
function CooldownHighlights:RefreshSpellIDCache(trackerKey)
    if InCombatLockdown() then
        print("|cff00ff00TweaksUI:|r Cannot refresh spellID cache during combat")
        return false
    end
    
    if trackerKey then
        CacheSpellIDs(trackerKey)
        print("|cff00ff00TweaksUI:|r Refreshed spellID cache for", trackerKey)
    else
        RefreshAllSpellIDCaches()
        print("|cff00ff00TweaksUI:|r Refreshed all spellID caches")
    end
    return true
end

-- Public API to get cached spellID (for debugging)
function CooldownHighlights:GetCachedSpellID(trackerKey, slotIndex)
    return GetCachedSpellID(trackerKey, slotIndex)
end

-- Public API to dump cache state (for debugging)
function CooldownHighlights:DumpSpellIDCache(trackerKey)
    print("|cff00ff00TweaksUI SpellID Cache:|r")
    if trackerKey then
        print("  Tracker:", trackerKey)
        local cache = spellIDCache[trackerKey]
        if cache then
            local count = 0
            for slotIndex, spellID in pairs(cache) do
                local spellName = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                spellName = spellName and spellName.name or "Unknown"
                print(string.format("    Slot %d: %d (%s)", slotIndex, spellID, spellName))
                count = count + 1
            end
            print("  Total:", count, "cached spellIDs")
        else
            print("  (no cache)")
        end
    else
        for key, cache in pairs(spellIDCache) do
            local count = 0
            for _ in pairs(cache) do count = count + 1 end
            print(string.format("  %s: %d cached spellIDs (last updated: %.1f sec ago)", 
                key, count, GetTime() - (cacheLastUpdated[key] or 0)))
        end
    end
end

function CooldownHighlights:ToggleDebug()
    debugMode = not debugMode
    print("|cff00ff00TweaksUI CooldownHighlights:|r Debug mode", debugMode and "ENABLED" or "DISABLED")
end

function CooldownHighlights:SetPosition(trackerKey, slotIndex, point, relPoint, x, y)
    SetHighlightPosition(trackerKey, slotIndex, point, relPoint, x, y)
end

function CooldownHighlights:DumpCooldownInfo(trackerKey, slotIndex)
    -- Use TUICD.Cooldowns.GetOrderedIcons if available (same order as layout/list)
    local icons
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = GetViewer(trackerKey)
        if viewer then
            icons = Cooldowns.GetOrderedIcons(viewer, trackerKey)
        else
            icons = {}
        end
    else
        icons = CollectIcons(trackerKey)
    end
    local icon = icons[slotIndex or 1]
    
    if not icon then
        print("|cffff0000[CooldownHighlights]|r No icon found at slot", slotIndex or 1)
        return
    end
    
    print("|cff00ff00[CooldownHighlights]|r Dumping info for", trackerKey, "slot", slotIndex or 1)
    print("  Icon:", icon:GetName() or "unnamed")
    
    -- Check spellID
    local spellID = icon.spellID or icon.SpellID or icon.spellId
    if not spellID and icon.GetSpellID then
        pcall(function() spellID = icon:GetSpellID() end)
    end
    print("  SpellID:", spellID or "(not found)")
    
    -- Try C_Spell.GetSpellDisplayCount if we have spellID
    if spellID and C_Spell and C_Spell.GetSpellDisplayCount then
        local success, result = pcall(function()
            return C_Spell.GetSpellDisplayCount(spellID)
        end)
        print("  C_Spell.GetSpellDisplayCount:", success and (result or "(nil)") or ("ERROR: " .. tostring(result)))
    end
    
    -- Check C_Spell cooldown APIs
    print("  C_Spell cooldown APIs:")
    print("    C_Spell.GetSpellCooldown:", (C_Spell and C_Spell.GetSpellCooldown) and "YES" or "no")
    print("    C_Spell.GetSpellCooldownDuration:", (C_Spell and C_Spell.GetSpellCooldownDuration) and "YES" or "no")
    
    -- Try C_Spell.GetSpellCooldown if we have spellID
    if spellID and C_Spell and C_Spell.GetSpellCooldown then
        local success, result = pcall(function()
            return C_Spell.GetSpellCooldown(spellID)
        end)
        if success and result then
            print("    GetSpellCooldown result:")
            print("      startTime:", result.startTime)
            print("      duration:", result.duration)
            print("      isEnabled:", result.isEnabled)
            print("      modRate:", result.modRate)
        else
            print("    GetSpellCooldown:", success and "(nil)" or ("ERROR: " .. tostring(result)))
        end
    end
    
    -- Try C_Spell.GetSpellCooldownDuration if it exists
    if spellID and C_Spell and C_Spell.GetSpellCooldownDuration then
        local success, result = pcall(function()
            return C_Spell.GetSpellCooldownDuration(spellID)
        end)
        print("    GetSpellCooldownDuration:", success and (result and "Duration Object" or "(nil)") or ("ERROR: " .. tostring(result)))
    end
    
    -- Try C_Spell.GetSpellCharges if we have spellID
    if spellID and C_Spell and C_Spell.GetSpellCharges then
        local success, result = pcall(function()
            return C_Spell.GetSpellCharges(spellID)
        end)
        if success and result then
            print("  C_Spell.GetSpellCharges: currentCharges=", result.currentCharges, "maxCharges=", result.maxCharges)
        else
            print("  C_Spell.GetSpellCharges:", success and "(nil)" or ("ERROR: " .. tostring(result)))
        end
    end
    
    -- Try GetSpellCharges global function
    if spellID and GetSpellCharges then
        local success, current, max = pcall(function()
            return GetSpellCharges(spellID)
        end)
        if success then
            print("  GetSpellCharges:", current or "(nil)", "/", max or "(nil)")
        end
    end
    
    -- Check direct fields
    local fields = {}
    if icon.Count then table.insert(fields, "Count") end
    if icon.count then table.insert(fields, "count") end
    if icon.Icon then table.insert(fields, "Icon") end
    if icon.icon then table.insert(fields, "icon") end
    if icon.Cooldown then table.insert(fields, "Cooldown") end
    if icon.cooldown then table.insert(fields, "cooldown") end
    if icon.spellID then table.insert(fields, "spellID") end
    if icon.SpellID then table.insert(fields, "SpellID") end
    if icon.charges then table.insert(fields, "charges") end
    if icon.Charges then table.insert(fields, "Charges") end
    print("  Direct fields:", #fields > 0 and table.concat(fields, ", ") or "(none)")
    
    -- Check for numeric charges value
    if type(icon.charges) == "number" then
        print("  icon.charges (number):", icon.charges)
    end
    if type(icon.Charges) == "number" then
        print("  icon.Charges (number):", icon.Charges)
    end
    if type(icon.currentCharges) == "number" then
        print("  icon.currentCharges:", icon.currentCharges)
    end
    if type(icon.maxCharges) == "number" then
        print("  icon.maxCharges:", icon.maxCharges)
    end
    
    -- Check direct Count field
    local directCount = icon.Count or icon.count
    if directCount then
        print("  icon.Count text:", directCount:GetText() or "(nil)", "visible:", directCount:IsShown())
    end
    
    -- Check cooldown frame
    local cooldown = icon.Cooldown or icon.cooldown
    if cooldown then
        print("  Cooldown frame:", cooldown:GetName() or "unnamed")
        
        -- Check for Midnight Duration Object API
        print("  Cooldown APIs available:")
        print("    GetCooldownDuration:", cooldown.GetCooldownDuration and "YES" or "no")
        print("    GetCooldownTimes:", cooldown.GetCooldownTimes and "YES" or "no")
        print("    SetCooldownFromDurationObject:", cooldown.SetCooldownFromDurationObject and "YES" or "no")
        
        -- Try GetCooldownDuration if available
        if cooldown.GetCooldownDuration then
            local success, result = pcall(function()
                return cooldown:GetCooldownDuration()
            end)
            print("    GetCooldownDuration result:", success and (result and "Duration Object" or "(nil)") or ("ERROR: " .. tostring(result)))
        end
        
        -- Try GetCooldownTimes if available
        if cooldown.GetCooldownTimes then
            local success, start, duration = pcall(function()
                return cooldown:GetCooldownTimes()
            end)
            if success then
                print("    GetCooldownTimes: start=", start, "duration=", duration)
            else
                print("    GetCooldownTimes: ERROR:", start)
            end
        end
        
        -- Check cooldown's count fields
        local cdCount = cooldown.Count or cooldown.count or cooldown.Charges or cooldown.charges
        if cdCount then
            print("  cooldown.Count text:", cdCount:GetText() or "(nil)", "visible:", cdCount:IsShown())
        end
        
        -- Check cooldown children
        if cooldown.GetChildren then
            print("  Cooldown children:", cooldown:GetNumChildren())
            for i = 1, cooldown:GetNumChildren() do
                local child = select(i, cooldown:GetChildren())
                local childName = child:GetName() or child:GetObjectType()
                print("    Child:", childName)
                if child.GetRegions then
                    for j = 1, child:GetNumRegions() do
                        local region = select(j, child:GetRegions())
                        if region:GetObjectType() == "FontString" then
                            print("      FontString:", region:GetName() or "unnamed", "text:", region:GetText() or "(nil)")
                        end
                    end
                end
            end
        end
    end
    
    -- Check icon's regions
    print("  Icon regions:")
    if icon.GetRegions then
        for i = 1, icon:GetNumRegions() do
            local region = select(i, icon:GetRegions())
            if region:GetObjectType() == "FontString" then
                print("    FontString:", region:GetName() or "unnamed", "text:", region:GetText() or "(nil)", "visible:", region:IsShown())
            end
        end
    end
    
    -- Check icon's children
    print("  Icon children:", icon:GetNumChildren())
    if icon.GetChildren then
        for i = 1, icon:GetNumChildren() do
            local child = select(i, icon:GetChildren())
            local childName = child:GetName() or child:GetObjectType()
            print("    Child:", childName)
            
            -- Check child's count field
            local childCount = child.Count or child.count
            if childCount then
                print("      Count field:", childCount:GetText() or "(nil)")
            end
            
            -- Check child's regions
            if child.GetRegions then
                for j = 1, child:GetNumRegions() do
                    local region = select(j, child:GetRegions())
                    if region:GetObjectType() == "FontString" then
                        print("      FontString:", region:GetName() or "unnamed", "text:", region:GetText() or "(nil)")
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function CooldownHighlights:Initialize(trackerKey)
    -- If no trackerKey provided, initialize for all trackers
    if not trackerKey then
        for _, key in ipairs({"essential", "utility", "buffs", "customTrackers"}) do
            self:Initialize(key)
        end
        return
    end
    
    if isInitialized[trackerKey] then return end
    isInitialized[trackerKey] = true
    
    dprint("Initializing CooldownHighlights:", trackerKey)
    
    -- Create frames for any enabled highlights (only outside combat)
    local db = GetDB(trackerKey)
    if not db then return end
    
    if not InCombatLockdown() then
        for slotIndex, enabled in pairs(db.enabled) do
            if enabled then
                CreateHighlightFrame(trackerKey, slotIndex)
            end
        end
        
        -- Cache spellIDs for this tracker (only outside combat)
        CacheSpellIDs(trackerKey)
    end
    
    -- Restore dock assignments after frames exist
    -- Use longer delay and iterate over dock assignments directly
    local function RestoreDockAssignments()
        if not TUICD.Docks or not db or not db.dockAssignment then return end
        
        for slotIndex, dockIndex in pairs(db.dockAssignment) do
            if dockIndex and highlightFrames[trackerKey] and highlightFrames[trackerKey][slotIndex] then
                dprint("Restoring dock assignment for", trackerKey, slotIndex, "-> dock", dockIndex)
                TUICD.Docks:AssignIcon(dockIndex, trackerKey, slotIndex)
            end
        end
    end
    
    -- Try restoration at multiple times to handle varying load orders
    C_Timer.After(1, RestoreDockAssignments)
    C_Timer.After(3, RestoreDockAssignments)
    
    -- Start update ticker if we have any enabled
    local hasEnabled = false
    for _, enabled in pairs(db.enabled) do
        if enabled then hasEnabled = true break end
    end
    
    if hasEnabled then
        StartUpdateTicker(trackerKey)
    end
    
    -- Apply tracker visibility
    self:ApplyTrackerVisibility(trackerKey)
    
    -- Register callbacks
    local Layout = TUICD.Layout
    if Layout then
        Layout:RegisterCallback("OnLayoutModeEnter", function()
            RegisterAllWithLayout(trackerKey)
            UpdateAllHighlights(trackerKey)
        end)
        
        Layout:RegisterCallback("OnLayoutModeExit", function()
            UpdateAllHighlights(trackerKey)
        end)
    end
end

function CooldownHighlights:InitializeAll()
    for trackerKey, _ in pairs(TRACKER_TYPES) do
        self:Initialize(trackerKey)
    end
end

-- ============================================================================
-- EVENT HANDLING: Refresh spellID cache after combat ends
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended - refresh all spellID caches
        -- Small delay to let CDM icons settle
        C_Timer.After(0.5, function()
            -- Double-check we're still out of combat (could have re-engaged)
            if not InCombatLockdown() then
                RefreshAllSpellIDCaches()
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zone change or login - refresh caches after things settle
        C_Timer.After(2, function()
            if not InCombatLockdown() then
                RefreshAllSpellIDCaches()
            end
        end)
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        -- Spell data loaded - might have new spellIDs available
        if not InCombatLockdown() then
            C_Timer.After(0.5, function()
                if not InCombatLockdown() then
                    RefreshAllSpellIDCaches()
                end
            end)
        end
    end
end)

-- Auto-initialize after a delay
C_Timer.After(2, function()
    CooldownHighlights:InitializeAll()
    -- Also cache spellIDs after initialization
    if not InCombatLockdown() then
        C_Timer.After(1, RefreshAllSpellIDCaches)
    end
end)