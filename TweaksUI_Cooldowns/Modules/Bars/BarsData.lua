-- ============================================================================
-- TUICD: Timer Bars - Data Layer
-- Per-spell cooldown state tracking (cooldown-only, no buff tracking)
-- Each tracked spell maintains its own state independently
--
-- KEY SYSTEM: Compound barKeys in format "spellID:cd"
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
    -- Bar dimensions
    width = 200,
    height = 20,
    -- Bar appearance
    barTexture = "Blizzard",
    barColor = { r = 0.26, g = 0.65, b = 1.0, a = 1.0 },
    backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
    borderColor = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },
    -- Icon
    showIcon = true,
    iconPosition = "LEFT",
    -- Text
    showName = true,
    showTime = true,
    nameFontSize = 11,
    timeFontSize = 11,
    -- Behavior
    showWhenReady = false,
    fillDirection = "STANDARD",
}

-- ============================================================================
-- DB ACCESS
-- ============================================================================

local migrationDone = false

function BarsData:GetDB()
    local settings = TUICD.Database:GetModuleSettings("bars")
    if not settings.spells then settings.spells = {} end
    if not settings.positions then settings.positions = {} end

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

function BarsData:GetTrackedSpells()
    return self:GetDB().spells
end

function BarsData:GetSpellConfig(barKey)
    return self:GetDB().spells[barKey]
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

-- Helper: secret-safe check if value > 0
local function IsSecretNonZero(secretValue)
    if not (issecretvalue and issecretvalue(secretValue)) then
        return false
    end
    if not (C_StringUtil and C_StringUtil.TruncateWhenZero) then
        return true  -- Conservative: assume non-zero
    end
    local ok, str = pcall(C_StringUtil.TruncateWhenZero, secretValue)
    if not ok or str == nil then return true end
    return issecretvalue(str)
end

-- One-time API availability log
local apiCheckDone = false
local function LogAPIAvailability()
    if apiCheckDone then return end
    apiCheckDone = true
    local hasGetCD = C_Spell and C_Spell.GetSpellCooldown and true or false
    local hasDurObj = C_Spell and C_Spell.GetSpellCooldownDuration and true or false
    local hasSecret = issecretvalue and true or false
    local hasTWZ = C_StringUtil and C_StringUtil.TruncateWhenZero and true or false
    TUICD:Print("Bars API check: GetSpellCooldown=" .. tostring(hasGetCD) ..
        " DurationObj=" .. tostring(hasDurObj) ..
        " issecretvalue=" .. tostring(hasSecret) ..
        " TruncateWhenZero=" .. tostring(hasTWZ))
end

-- ============================================================================
-- GCD FILTERING
-- Uses cdInfo.isOnGCD from C_Spell.GetSpellCooldown()
-- ============================================================================

function BarsData:UpdateCooldownState(barKey)
    LogAPIAvailability()

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
    local isGCD = false
    local durationObj = nil

    -- Step 1: Check GetSpellCooldown struct for isOnGCD flag
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, numID)
        if ok and cdInfo then
            if cdInfo.isOnGCD ~= nil then
                if issecretvalue and issecretvalue(cdInfo.isOnGCD) then
                    -- isOnGCD is secret, fall through
                else
                    isGCD = cdInfo.isOnGCD == true
                end
            end
            local dur = cdInfo.duration
            if dur ~= nil then
                if issecretvalue and issecretvalue(dur) then
                    if IsSecretNonZero(dur) then isOnCD = true end
                elseif type(dur) == "number" and dur > 0 then
                    isOnCD = true
                end
            end
        end
    end

    -- Step 2: If only the GCD, skip it
    if isGCD then
        state.isActive = false
        state.durationObj = nil
        if wasActive then self:FireUpdate(barKey) end
        return
    end

    -- Step 3: Get Duration Object for timer bar animation
    if isOnCD and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, dObj = pcall(C_Spell.GetSpellCooldownDuration, numID)
        if ok and dObj then durationObj = dObj end
    end

    -- Step 4: Fallback Duration Object path
    if not isOnCD and C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, dObj = pcall(C_Spell.GetSpellCooldownDuration, numID)
        if ok and dObj then
            local ok2, remaining = pcall(dObj.GetRemainingDuration, dObj)
            if ok2 and remaining ~= nil then
                if issecretvalue and issecretvalue(remaining) then
                    if IsSecretNonZero(remaining) then
                        isOnCD = true
                        durationObj = dObj
                    end
                elseif type(remaining) == "number" and remaining > 0 then
                    isOnCD = true
                    durationObj = dObj
                end
            end
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
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    if C_RestrictedActions then
        eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end

    local self_ref = self
    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "SPELL_UPDATE_COOLDOWN" then
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
