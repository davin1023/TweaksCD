-- ============================================================================
-- TUICD: Timer Bars - Data Layer
-- Per-spell cooldown state tracking (cooldown-only, no buff tracking)
-- Each tracked spell maintains its own state independently
--
-- KEY SYSTEM: Compound barKeys in format "spellID:cd"
--
-- COOLDOWN DETECTION: Uses Midnight Curve objects for secret-safe CD checks.
-- A Step curve maps remaining duration to 0 (off CD) or 1 (on CD) natively
-- inside the engine, avoiding arithmetic on secret values entirely.
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BarsData = TUICD.BarsData or {}
local BarsData = TUICD.BarsData

local SpellAPI = TUICD.SpellAPI
local DurationAPI = TUICD.DurationAPI

-- ============================================================================
-- STATE
-- ============================================================================

-- Per-bar runtime state: [barKey] = { type, isActive, durationObj, ... }
local spellStates = {}

-- Callbacks for frame updates
local updateCallbacks = {}

-- ============================================================================
-- TRACKING TYPES
-- ============================================================================

BarsData.TYPE_COOLDOWN = "cooldown"

-- ============================================================================
-- COMPOUND KEY SYSTEM
-- ============================================================================

-- Create compound key: "spellID:cd"
function BarsData.MakeBarKey(spellID, trackingType)
    return tostring(spellID) .. ":cd"
end

-- Parse compound key -> spellID (number), trackingType (string)
function BarsData.ParseBarKey(barKey)
    local idStr, typeStr = string.match(tostring(barKey), "^(%d+):(%a+)$")
    if idStr then
        return tonumber(idStr), BarsData.TYPE_COOLDOWN
    end
    -- Legacy numeric key fallback (migration)
    local num = tonumber(barKey)
    if num then return num, BarsData.TYPE_COOLDOWN end
    return nil, nil
end

-- Sanitize barKey for use in frame names (replace : with _)
function BarsData.SanitizeKey(barKey)
    return tostring(barKey):gsub(":", "_")
end

-- Get display suffix for type
function BarsData.TypeLabel(trackingType)
    return "(CD)"
end

-- ============================================================================
-- DEFAULT BAR CONFIG
-- ============================================================================

local BAR_DEFAULTS = {
    enabled = true,
    type = "cooldown",
    name = "",
    iconID = nil,
    -- Bar dimensions (bar area only, icon is separate)
    width = 200,
    height = 20,
    -- Bar appearance
    barTexture = "Blizzard",
    barColor = { r = 0.26, g = 0.65, b = 1.0, a = 1.0 },
    backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
    borderColor = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },
    -- Icon (independent sizing)
    showIcon = true,
    iconPosition = "LEFT",
    iconSizeMode = "auto",      -- "auto" = match bar thickness, "manual" = use iconSize
    iconSize = 0,               -- manual override size (only used when iconSizeMode = "manual")
    iconAspect = "1:1",         -- width:height ratio key
    -- Text
    showName = true,
    showTime = true,
    font = "",                  -- empty = default (STANDARD_TEXT_FONT)
    nameFontSize = 11,
    timeFontSize = 11,
    nameOffsetX = 0,
    nameOffsetY = 0,
    timeOffsetX = 0,
    timeOffsetY = 0,
    -- Behavior
    showWhenReady = false,
    fillMode = "drain",         -- "drain" = full->empty (remaining), "fill" = empty->full (elapsed)
    barDirection = "RIGHT",     -- "RIGHT", "LEFT", "UP", "DOWN" (bar fill/growth direction)
    -- Time-based color
    colorByTime = false,        -- Change bar color based on remaining seconds
    colorHighSeconds = 10,      -- Above this = high color (lots of time left)
    colorMedSeconds = 5,        -- Above this = med color (getting low)
    colorHigh = { r = 1.0, g = 0.2, b = 0.2 },   -- Red (far out)
    colorMed  = { r = 1.0, g = 0.8, b = 0.0 },   -- Yellow (mid)
    colorLow  = { r = 0.2, g = 0.8, b = 0.2 },   -- Green (almost ready)
}

-- ============================================================================
-- ICON ASPECT RATIOS (zoom-crop, never squash)
-- ============================================================================

BarsData.ICON_ASPECTS = {
    ["1:1"]  = { label = "1:1 (Square)", w = 1, h = 1 },
    ["4:3"]  = { label = "4:3",          w = 4, h = 3 },
    ["3:4"]  = { label = "3:4",          w = 3, h = 4 },
    ["3:2"]  = { label = "3:2",          w = 3, h = 2 },
    ["2:3"]  = { label = "2:3",          w = 2, h = 3 },
    ["2:1"]  = { label = "2:1 (Wide)",   w = 2, h = 1 },
    ["1:2"]  = { label = "1:2 (Tall)",   w = 1, h = 2 },
}

-- Ordered keys for UI dropdowns
BarsData.ICON_ASPECT_ORDER = { "1:1", "4:3", "3:4", "3:2", "2:3", "2:1", "1:2" }

-- ============================================================================
-- DOCK DEFAULTS (group container settings, not per-bar)
-- ============================================================================

local DOCK_DEFAULTS = {
    enabled = false,            -- false = standalone mode (each bar is independent)
    orientation = "VERTICAL",   -- "VERTICAL" or "HORIZONTAL"
    spacing = 2,                -- px between bars in dock
    justify = "CENTER",         -- "START", "CENTER", "END" (arrival order placement)
    sortMode = "arrival",       -- "arrival" (FIFO center-out) or "list" (spell list order)
    overrideBarSettings = false, -- When true, dock overrides individual bar visual settings
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
    barOverrides = {
        -- Bar dimensions
        width = 200,
        height = 20,
        -- Appearance
        barTexture = "Blizzard",
        barColor = { r = 0.26, g = 0.65, b = 1.0, a = 1.0 },
        backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
        borderColor = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },
        -- Icon
        showIcon = true,
        iconPosition = "LEFT",
        iconSizeMode = "auto",
        iconSize = 0,
        iconAspect = "1:1",
        -- Text
        showName = true,
        showTime = true,
        font = "",
        nameFontSize = 11,
        timeFontSize = 11,
        nameOffsetX = 0,
        nameOffsetY = 0,
        timeOffsetX = 0,
        timeOffsetY = 0,
        -- Behavior
        showWhenReady = false,
        fillMode = "drain",
        barDirection = "RIGHT",
        -- Color by time
        colorByTime = false,
        colorHighSeconds = 10,
        colorMedSeconds = 5,
        colorHigh = { r = 1.0, g = 0.2, b = 0.2 },
        colorMed  = { r = 1.0, g = 0.8, b = 0.0 },
        colorLow  = { r = 0.2, g = 0.8, b = 0.2 },
    },
}

BarsData.DOCK_DEFAULTS = DOCK_DEFAULTS

-- ============================================================================
-- DB ACCESS
-- ============================================================================

local migrationDone = false

function BarsData:GetDB()
    local settings = TUICD.Database:GetModuleSettings("bars")
    if not settings.spells then settings.spells = {} end
    if not settings.positions then settings.positions = {} end
    if not settings.dock then
        settings.dock = {}
        for k, v in pairs(DOCK_DEFAULTS) do
            if type(v) == "table" then
                settings.dock[k] = {}
                for k2, v2 in pairs(v) do
                    if type(v2) == "table" then
                        settings.dock[k][k2] = {}
                        for k3, v3 in pairs(v2) do settings.dock[k][k2][k3] = v3 end
                    else
                        settings.dock[k][k2] = v2
                    end
                end
            else
                settings.dock[k] = v
            end
        end
    end
    -- Ensure barOverrides sub-table exists and has all default keys
    if not settings.dock.barOverrides then
        settings.dock.barOverrides = {}
    end
    local bo = settings.dock.barOverrides
    local dbo = DOCK_DEFAULTS.barOverrides
    for k, v in pairs(dbo) do
        if bo[k] == nil then
            if type(v) == "table" then
                bo[k] = {}
                for k2, v2 in pairs(v) do bo[k][k2] = v2 end
            else
                bo[k] = v
            end
        end
    end

    -- One-time migration: convert any numeric keys to compound keys
    if not migrationDone then
        migrationDone = true
        local needsMigration = false
        for key in pairs(settings.spells) do
            if type(key) == "number" then
                needsMigration = true
                break
            end
        end
        if needsMigration then
            local newSpells = {}
            local newPositions = {}
            local count = 0
            for key, config in pairs(settings.spells) do
                if type(key) == "number" then
                    local barKey = BarsData.MakeBarKey(key, config.type or BarsData.TYPE_COOLDOWN)
                    newSpells[barKey] = config
                    if settings.positions[key] then
                        newPositions[barKey] = settings.positions[key]
                    end
                    count = count + 1
                else
                    newSpells[key] = config
                    if settings.positions[key] then
                        newPositions[key] = settings.positions[key]
                    end
                end
            end
            settings.spells = newSpells
            settings.positions = newPositions
            TUICD:Print("Bars: migrated " .. count .. " spell entries to new key format.")
        end
    end

    return settings
end

-- Dock settings accessors
function BarsData:GetDockSettings()
    return self:GetDB().dock
end

function BarsData:SetDockSetting(key, value)
    local dock = self:GetDB().dock
    dock[key] = value
    TUICD.Events:Fire(TUICD.EVENTS.BARS_DATA_UPDATED, nil, "dock")
end

function BarsData:IsDockEnabled()
    return self:GetDB().dock.enabled == true
end

function BarsData:GetTrackedSpells()
    return self:GetDB().spells
end

function BarsData:GetSpellConfig(barKey)
    return self:GetDB().spells[barKey]
end

-- Visual keys that dock overrides can replace (excludes identity: enabled, type, name, iconID)
BarsData.VISUAL_KEYS = {
    "width", "height", "barTexture", "barColor", "backgroundColor", "borderColor",
    "showIcon", "iconPosition", "iconSizeMode", "iconSize", "iconAspect",
    "showName", "showTime", "font", "nameFontSize", "timeFontSize",
    "nameOffsetX", "nameOffsetY", "timeOffsetX", "timeOffsetY",
    "showWhenReady", "fillMode", "barDirection",
    "colorByTime", "colorHighSeconds", "colorMedSeconds", "colorHigh", "colorMed", "colorLow",
}

-- Returns effective config: dock overrides merged on top when active, else raw spell config
function BarsData:GetEffectiveConfig(barKey)
    local config = self:GetSpellConfig(barKey)
    if not config then return nil end

    local dock = self:GetDockSettings()
    if not dock or not dock.enabled or not dock.overrideBarSettings then
        return config
    end

    local overrides = dock.barOverrides
    if not overrides then return config end

    -- Shallow merge: override visual keys, keep identity from spell config
    local effective = {}
    for k, v in pairs(config) do effective[k] = v end
    for _, k in ipairs(BarsData.VISUAL_KEYS) do
        if overrides[k] ~= nil then
            effective[k] = overrides[k]
        end
    end
    return effective
end

-- Dock bar override accessors
function BarsData:GetDockOverrides()
    return self:GetDB().dock.barOverrides
end

function BarsData:SetDockOverride(key, value)
    local bo = self:GetDB().dock.barOverrides
    bo[key] = value
    -- Refresh all bars when a dock override changes
    TUICD.Events:Fire(TUICD.EVENTS.BARS_DATA_UPDATED, nil, "dock_override")
end

function BarsData:GetSpellList()
    local list = {}
    for barKey, config in pairs(self:GetTrackedSpells()) do
        local spellID = BarsData.ParseBarKey(barKey)
        table.insert(list, {
            barKey = barKey,
            spellID = spellID,
            name = config.name or ("Spell " .. (spellID or "?")),
            displayName = (config.name or ("Spell " .. (spellID or "?"))) .. " " .. BarsData.TypeLabel(config.type),
            iconID = config.iconID,
            type = config.type,
            enabled = config.enabled,
        })
    end
    table.sort(list, function(a, b) return (a.displayName or "") < (b.displayName or "") end)
    return list
end

-- ============================================================================
-- SPELL MANAGEMENT
-- ============================================================================

function BarsData:AddSpell(spellID, trackingType)
    if not spellID then return nil end
    trackingType = trackingType or BarsData.TYPE_COOLDOWN
    local barKey = BarsData.MakeBarKey(spellID, trackingType)

    local db = self:GetDB()
    if db.spells[barKey] then return nil end  -- Already tracked with this type

    local spellInfo = SpellAPI:GetSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name or ("Spell " .. spellID)
    local iconID = SpellAPI:GetSpellTexture(spellID)

    -- Copy defaults and set spell-specific values
    local config = {}
    for k, v in pairs(BAR_DEFAULTS) do
        if type(v) == "table" then
            config[k] = {}
            for k2, v2 in pairs(v) do config[k][k2] = v2 end
        else
            config[k] = v
        end
    end
    config.type = trackingType
    config.name = spellName
    config.iconID = iconID

    db.spells[barKey] = config
    TUICD.Events:Fire(TUICD.EVENTS.BARS_DATA_UPDATED, barKey, "added")
    return barKey
end

function BarsData:RemoveSpell(barKey)
    if not barKey then return false end
    local db = self:GetDB()
    if not db.spells[barKey] then return false end

    db.positions[barKey] = nil
    db.spells[barKey] = nil
    spellStates[barKey] = nil

    TUICD.Events:Fire(TUICD.EVENTS.BARS_DATA_UPDATED, barKey, "removed")
    return true
end

function BarsData:RemoveAllSpells()
    local db = self:GetDB()
    local count = 0
    for barKey in pairs(db.spells) do
        db.positions[barKey] = nil
        spellStates[barKey] = nil
        count = count + 1
    end
    wipe(db.spells)
    if count > 0 then
        TUICD.Events:Fire(TUICD.EVENTS.BARS_DATA_UPDATED, nil, "clear_all")
    end
    return count
end

function BarsData:SetSpellSetting(barKey, key, value)
    local db = self:GetDB()
    if not db.spells[barKey] then return end
    db.spells[barKey][key] = value
    TUICD.Events:Fire(TUICD.EVENTS.BARS_SETTINGS_CHANGED, barKey, key, value)
end

function BarsData:GetSpellSetting(barKey, key)
    local db = self:GetDB()
    if not db.spells[barKey] then return nil end
    return db.spells[barKey][key]
end

-- ============================================================================
-- POSITION PERSISTENCE
-- ============================================================================

function BarsData:GetSpellPosition(barKey)
    return self:GetDB().positions[barKey]
end

function BarsData:SetSpellPosition(barKey, point, x, y)
    self:GetDB().positions[barKey] = { point = point, x = x, y = y }
end

-- ============================================================================
-- RUNTIME STATE
-- ============================================================================

function BarsData:GetSpellState(barKey)
    return spellStates[barKey]
end

-- ============================================================================
-- COOLDOWN DETECTION: isOnGCD + Duration Object pass-through
--
-- Uses C_Spell.GetSpellCooldown().isOnGCD (non-secret boolean) for GCD filter.
-- Duration Object passed straight to frames for display.
-- No sensor, no arithmetic on secret values.
-- ============================================================================

function BarsData:UpdateCooldownState(barKey)
    local config = self:GetSpellConfig(barKey)
    if not config or not config.enabled or config.type ~= BarsData.TYPE_COOLDOWN then return end

    local numID = BarsData.ParseBarKey(barKey)
    if not numID then return end

    local state = spellStates[barKey]
    if not state then
        state = { type = BarsData.TYPE_COOLDOWN, isActive = false }
        spellStates[barKey] = state
    end

    local wasActive = state.isActive
    local isOnCD = false
    local durationObj = nil

    local DurationAPI = TUICD.DurationAPI
    if DurationAPI and DurationAPI.IsRealCooldownActive then
        local onCD, dObj = DurationAPI:IsRealCooldownActive(numID)
        if onCD and dObj then
            isOnCD = true
            durationObj = dObj
        end
    end

    state.isActive = isOnCD
    state.durationObj = durationObj
    if wasActive ~= isOnCD then self:FireUpdate(barKey) end
end

function BarsData:UpdateAll()
    for barKey, config in pairs(self:GetTrackedSpells()) do
        if config.enabled then
            self:UpdateCooldownState(barKey)
        end
    end
end

-- ============================================================================
-- IMPORT: MultiTracker Spells (Essential + Utility + Custom)
-- ============================================================================

function BarsData:GetImportableMultiTrackerSpells()
    local results = {}
    local seen = {}
    local already = self:GetTrackedSpells()

    if not TUICD.CooldownHighlights then return results end

    for _, trackerKey in ipairs({"essential", "utility", "custom"}) do
        local count = TUICD.CooldownHighlights:GetSlotCount(trackerKey) or 0
        for i = 1, count do
            local spellID = TUICD.CooldownHighlights:GetCachedSpellID(trackerKey, i)
            if spellID and spellID > 0 then
                local barKey = BarsData.MakeBarKey(spellID, BarsData.TYPE_COOLDOWN)
                if not seen[barKey] and not already[barKey] then
                    seen[barKey] = true
                    local name = SpellAPI:GetSpellName(spellID) or ("Spell " .. spellID)
                    local icon = SpellAPI:GetSpellTexture(spellID)
                    table.insert(results, {
                        barKey = barKey, spellID = spellID,
                        name = name, icon = icon,
                        type = BarsData.TYPE_COOLDOWN, source = trackerKey,
                    })
                end
            end
        end
    end

    table.sort(results, function(a, b) return (a.name or "") < (b.name or "") end)
    return results
end

function BarsData:ImportMultiTrackerSpells()
    local spells = self:GetImportableMultiTrackerSpells()
    local imported = 0
    local db = self:GetDB()
    for _, spell in ipairs(spells) do
        local config = {}
        for k, v in pairs(BAR_DEFAULTS) do
            if type(v) == "table" then
                config[k] = {}
                for k2, v2 in pairs(v) do config[k][k2] = v2 end
            else config[k] = v end
        end
        config.enabled = false
        config.type = BarsData.TYPE_COOLDOWN
        config.name = spell.name
        config.iconID = spell.icon
        db.spells[spell.barKey] = config
        imported = imported + 1
    end
    if imported > 0 then
        TUICD.Events:Fire(TUICD.EVENTS.BARS_DATA_UPDATED, nil, "bulk_import")
    end
    return imported
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

function BarsData:RegisterUpdateCallback(id, callback)
    updateCallbacks[id] = callback
end

function BarsData:UnregisterUpdateCallback(id)
    updateCallbacks[id] = nil
end

function BarsData:FireUpdate(barKey)
    for _, callback in pairs(updateCallbacks) do
        pcall(callback, barKey)
    end
end

-- ============================================================================
-- EVENTS
-- ============================================================================

local eventFrame = CreateFrame("Frame")

function BarsData:RegisterEvents()
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    if C_RestrictedActions then
        eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end

    local self_ref = self
    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
            for barKey, config in pairs(self_ref:GetTrackedSpells()) do
                if config.enabled then
                    self_ref:UpdateCooldownState(barKey)
                end
            end

        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.5, function() self_ref:UpdateAll() end)

        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            self_ref:UpdateAll()

        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            C_Timer.After(0, function() self_ref:UpdateAll() end)
        end
    end)
end

function BarsData:GetSpellCount()
    local count = 0
    for _ in pairs(self:GetTrackedSpells()) do count = count + 1 end
    return count
end

function BarsData:UnregisterEvents()
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
end

return BarsData
