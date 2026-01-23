-- ============================================================================
-- TUICD: Aura API Wrapper
-- Midnight-native aura API functions
-- All functions use C_UnitAuras namespace directly - no fallbacks
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.AuraAPI = TUICD.AuraAPI or {}
local AuraAPI = TUICD.AuraAPI

-- Import sort constants from main API
local function GetSortConstants()
    return TUICD.API.AURA_SORT, TUICD.API.AURA_SORT_DIRECTION
end

-- ============================================================================
-- AURA RETRIEVAL - Instance ID Based (Preferred)
-- ============================================================================

-- Get aura instance IDs with sorting
-- Returns: table of auraInstanceIDs
function AuraAPI:GetAuraInstanceIDs(unit, filter, maxAuras, sortRule, sortDirection)
    if not unit then return {} end
    
    local SORT, SORT_DIR = GetSortConstants()
    sortRule = sortRule or SORT.DEFAULT
    sortDirection = sortDirection or SORT_DIR.NORMAL
    
    local success, result = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, 
        unit, filter, maxAuras, sortRule, sortDirection)
    
    if success and result then
        return result
    end
    return {}
end

-- Get full aura data by instance ID
function AuraAPI:GetAuraDataByInstanceID(unit, auraInstanceID)
    if not unit or not auraInstanceID then return nil end
    return C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
end

-- Get aura data by index (legacy method, still works)
function AuraAPI:GetAuraDataByIndex(unit, index, filter)
    if not unit or not index then return nil end
    return C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
end

-- Get player aura by spell ID (convenience method)
function AuraAPI:GetPlayerAuraBySpellID(spellID)
    if not spellID then return nil end
    return C_UnitAuras.GetPlayerAuraBySpellID(spellID)
end

-- ============================================================================
-- AURA RETRIEVAL - Full Data Tables
-- ============================================================================

-- Get all auras with full data and sorting
-- Returns: table of AuraData structs
function AuraAPI:GetUnitAuras(unit, filter, sortRule, sortDirection, maxAuras)
    if not unit then return {} end
    
    local SORT, SORT_DIR = GetSortConstants()
    sortRule = sortRule or SORT.DEFAULT
    sortDirection = sortDirection or SORT_DIR.NORMAL
    
    -- Get instance IDs first
    local instanceIDs = self:GetAuraInstanceIDs(unit, filter, maxAuras, sortRule, sortDirection)
    
    -- Convert to full aura data
    local auras = {}
    for i, auraID in ipairs(instanceIDs) do
        local auraData = self:GetAuraDataByInstanceID(unit, auraID)
        if auraData then
            table.insert(auras, auraData)
        end
    end
    
    return auras
end

-- Get buffs (helpful auras)
function AuraAPI:GetBuffs(unit, sortRule, sortDirection, maxAuras)
    return self:GetUnitAuras(unit, "HELPFUL", sortRule, sortDirection, maxAuras)
end

-- Get debuffs (harmful auras)
function AuraAPI:GetDebuffs(unit, sortRule, sortDirection, maxAuras)
    return self:GetUnitAuras(unit, "HARMFUL", sortRule, sortDirection, maxAuras)
end

-- ============================================================================
-- DURATION OBJECTS
-- ============================================================================

-- Get aura duration as Duration Object
function AuraAPI:GetAuraDuration(unit, auraInstanceID)
    if not unit or not auraInstanceID then return nil end
    return C_UnitAuras.GetUnitAuraDuration(unit, auraInstanceID)
end

-- Apply aura duration to a cooldown frame
function AuraAPI:ApplyDurationToFrame(cooldownFrame, unit, auraInstanceID, clearIfZero)
    if not cooldownFrame or not unit or not auraInstanceID then return false end
    
    local duration = self:GetAuraDuration(unit, auraInstanceID)
    if duration then
        cooldownFrame:SetCooldownFromDurationObject(duration, clearIfZero ~= false)
        return true
    end
    return false
end

-- ============================================================================
-- AURA PROPERTIES
-- ============================================================================

-- Check if aura has an expiration time (not permanent)
function AuraAPI:HasExpirationTime(unit, auraInstanceID)
    if not unit or not auraInstanceID then return false end
    local success, result = pcall(C_UnitAuras.DoesAuraHaveExpirationTime, unit, auraInstanceID)
    return success and result
end

-- Get application/stack count display string
-- minDisplay: minimum count to display (default 2, so stacks of 1 show nothing)
function AuraAPI:GetApplicationDisplayCount(unit, auraInstanceID, minDisplay)
    if not unit or not auraInstanceID then return "" end
    minDisplay = minDisplay or 2
    
    local success, result = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, 
        unit, auraInstanceID, minDisplay)
    
    if success and result then
        return result
    end
    return ""
end

-- Get dispel type color via color curve
-- Takes unit and auraInstanceID (dispelType is secret in Midnight)
function AuraAPI:GetDispelTypeColor(unit, auraInstanceID, colorCurve)
    if not unit or not auraInstanceID then return nil end
    return C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, colorCurve)
end

-- Legacy: Get color from non-secret dispelType number (for static/cached values only)
function AuraAPI:GetDispelTypeColorByID(dispelTypeID, colorCurve)
    if not dispelTypeID or not colorCurve then return nil end
    -- Note: This only works with non-secret numeric dispel type IDs
    -- For secret values, use GetDispelTypeColor with unit/auraInstanceID
    return colorCurve:Evaluate(dispelTypeID)
end

-- ============================================================================
-- DURATION HELPERS
-- ============================================================================

-- Get remaining duration as percentage (can accept curve)
function AuraAPI:GetDurationRemainingPercent(unit, auraInstanceID, curve)
    if not unit or not auraInstanceID then return 0 end
    return C_UnitAuras.GetAuraDurationRemainingPercent(unit, auraInstanceID, curve)
end

-- Get remaining duration color (requires color curve)
function AuraAPI:GetDurationRemainingColor(unit, auraInstanceID, colorCurve)
    if not unit or not auraInstanceID or not colorCurve then return nil end
    return C_UnitAuras.GetAuraDurationRemainingColor(unit, auraInstanceID, colorCurve)
end

-- ============================================================================
-- DISPEL TYPE CONSTANTS
-- ============================================================================

AuraAPI.DISPEL_TYPES = {
    NONE = 0,
    MAGIC = 1,
    CURSE = 2,
    DISEASE = 3,
    POISON = 4,
    -- Bleed is typically 5 but not always dispellable
}

-- Convert dispel name string to numeric type
function AuraAPI:GetDispelTypeID(dispelName)
    if not dispelName then return 0 end
    
    local lookup = {
        ["Magic"] = 1,
        ["Curse"] = 2,
        ["Disease"] = 3,
        ["Poison"] = 4,
    }
    
    return lookup[dispelName] or 0
end

-- ============================================================================
-- AURA FILTERING HELPERS
-- ============================================================================

-- Filter auras by custom criteria
function AuraAPI:FilterAuras(auras, filterFunc)
    if not auras or not filterFunc then return {} end
    
    local filtered = {}
    for _, aura in ipairs(auras) do
        if filterFunc(aura) then
            table.insert(filtered, aura)
        end
    end
    return filtered
end

-- Get only auras cast by player
function AuraAPI:GetPlayerCastAuras(unit, filter, sortRule, sortDirection, maxAuras)
    local auras = self:GetUnitAuras(unit, filter, sortRule, sortDirection, maxAuras)
    return self:FilterAuras(auras, function(aura)
        return aura.sourceUnit == "player"
    end)
end

-- Get only dispellable auras
function AuraAPI:GetDispellableAuras(unit, sortRule, sortDirection, maxAuras)
    local auras = self:GetDebuffs(unit, sortRule, sortDirection, maxAuras)
    return self:FilterAuras(auras, function(aura)
        return aura.dispelName and aura.dispelName ~= ""
    end)
end

-- Get only stealable auras
function AuraAPI:GetStealableAuras(unit, sortRule, sortDirection, maxAuras)
    local auras = self:GetBuffs(unit, sortRule, sortDirection, maxAuras)
    return self:FilterAuras(auras, function(aura)
        return aura.isStealable
    end)
end

-- ============================================================================
-- TOOLTIP INTEGRATION
-- ============================================================================

-- Set tooltip for buff by aura instance ID
function AuraAPI:SetTooltipBuff(tooltip, unit, auraInstanceID)
    if not tooltip or not unit or not auraInstanceID then return false end
    
    if tooltip.SetUnitBuffByAuraInstanceID then
        tooltip:SetUnitBuffByAuraInstanceID(unit, auraInstanceID)
        return true
    end
    return false
end

-- Set tooltip for debuff by aura instance ID
function AuraAPI:SetTooltipDebuff(tooltip, unit, auraInstanceID)
    if not tooltip or not unit or not auraInstanceID then return false end
    
    if tooltip.SetUnitDebuffByAuraInstanceID then
        tooltip:SetUnitDebuffByAuraInstanceID(unit, auraInstanceID)
        return true
    end
    return false
end

-- Set tooltip for aura (auto-detect buff/debuff)
function AuraAPI:SetTooltipAura(tooltip, unit, auraInstanceID, isHarmful)
    if isHarmful then
        return self:SetTooltipDebuff(tooltip, unit, auraInstanceID)
    else
        return self:SetTooltipBuff(tooltip, unit, auraInstanceID)
    end
end

-- ============================================================================
-- SECRECY CHECKS
-- ============================================================================

-- Check if aura data for a spell is secret
function AuraAPI:GetAuraSecrecy(spellID)
    if not spellID then return nil end
    return C_Secrets.GetSpellAuraSecrecy(spellID)
end

-- Check if aura is never secret (whitelisted)
function AuraAPI:IsAuraNeverSecret(spellID)
    if not spellID then return false end
    local secrecy = C_Secrets.GetSpellAuraSecrecy(spellID)
    return secrecy == Enum.SecrecyLevel.NeverSecret
end

return AuraAPI
