-- ============================================================================
-- TUICD: API Wrapper System
-- Midnight-native API wrappers for consistent usage across all modules
-- Version 2.0.0 - No TWW fallbacks, direct Midnight API usage
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Initialize API namespace
TUICD.API = TUICD.API or {}
local API = TUICD.API

-- ============================================================================
-- VERSION CHECK
-- ============================================================================

-- Verify we're running on Midnight (12.0.0+)
local function CheckMidnightVersion()
    local _, _, _, tocVersion = GetBuildInfo()
    if tocVersion < TUICD.MIN_WOW_VERSION then
        -- This shouldn't happen since TOC enforces it, but just in case
        print("|cffff0000TweaksUI Error:|r This version requires World of Warcraft: Midnight (12.0.0+)")
        print("|cffff0000TweaksUI Error:|r Current version: " .. tocVersion .. ", Required: " .. TUICD.MIN_WOW_VERSION)
        return false
    end
    return true
end

API.IsMidnightVerified = CheckMidnightVersion()

-- ============================================================================
-- API AVAILABILITY FLAGS
-- These are all TRUE in Midnight - kept for documentation and potential
-- future expansion compatibility
-- ============================================================================

-- Spell APIs (C_Spell namespace)
API.HAS_SPELL_INFO = true                    -- C_Spell.GetSpellInfo
API.HAS_SPELL_COOLDOWN = true                -- C_Spell.GetSpellCooldown
API.HAS_SPELL_COOLDOWN_DURATION = true       -- C_Spell.GetSpellCooldownDuration (Duration Objects)
API.HAS_SPELL_CHARGES_DURATION = true        -- C_Spell.GetSpellChargesCooldownDuration
API.HAS_SPELL_DISPLAY_COUNT = true           -- C_Spell.GetSpellDisplayCount

-- Aura APIs (C_UnitAuras namespace)
API.HAS_AURA_DATA = true                     -- C_UnitAuras.GetAuraDataByIndex/ByAuraInstanceID
API.HAS_AURA_INSTANCE_IDS = true             -- C_UnitAuras.GetUnitAuraInstanceIDs
API.HAS_AURA_DURATION_OBJECTS = true         -- C_UnitAuras.GetUnitAuraDuration (Duration Objects)
API.HAS_AURA_SORTING = true                  -- Enum.UnitAuraSortRule
API.HAS_AURA_DISPLAY_COUNT = true            -- C_UnitAuras.GetAuraApplicationDisplayCount
API.HAS_AURA_EXPIRATION_CHECK = true         -- C_UnitAuras.DoesAuraHaveExpirationTime
API.HAS_AURA_DISPEL_COLOR = true             -- C_UnitAuras.GetAuraDispelTypeColor

-- Action Bar APIs (C_ActionBar namespace)
API.HAS_ACTION_COOLDOWN_DURATION = true      -- C_ActionBar.GetActionCooldownDuration
API.HAS_ACTION_CHARGES_DURATION = true       -- C_ActionBar.GetActionChargesCooldownDuration
API.HAS_ACTION_DISPLAY_COUNT = true          -- C_ActionBar.GetActionDisplayCount

-- Cast Bar APIs
API.HAS_CAST_DURATION = true                 -- UnitCastingDuration (Duration Objects)
API.HAS_CHANNEL_DURATION = true              -- UnitChannelDuration (Duration Objects)
API.HAS_EMPOWERED_DURATION = true            -- UnitEmpoweredChannelDuration
API.HAS_EMPOWERED_STAGES = true              -- UnitEmpoweredStageDurations/Percentages

-- Status Bar APIs
API.HAS_SMOOTH_BARS = true                   -- Enum.StatusBarInterpolation
API.HAS_TIMER_BARS = true                    -- StatusBar:SetTimerDuration

-- Duration Objects
API.HAS_DURATION_OBJECTS = true              -- C_DurationUtil.CreateDuration
API.HAS_COOLDOWN_FROM_DURATION = true        -- Cooldown:SetCooldownFromDurationObject

-- Curve System
API.HAS_CURVES = true                        -- C_CurveUtil, CreateColorCurve, etc.
API.HAS_COLOR_CURVES = true                  -- ColorCurve objects

-- Unit APIs
API.HAS_UNIT_HEALTH_PERCENT = true           -- UnitHealthPercent with curve support
API.HAS_UNIT_POWER_PERCENT = true            -- UnitPowerPercent with curve support
API.HAS_HEAL_PREDICTION_CALC = true          -- CreateUnitHealPredictionCalculator

-- Secret Value System
API.HAS_SECRET_VALUES = true                 -- issecretvalue()
API.HAS_RESTRICTION_STATES = true            -- C_RestrictedActions, Enum.AddOnRestrictionType
API.HAS_SECRETS_API = true                   -- C_Secrets namespace

-- Boolean Secret Helpers
API.HAS_ALPHA_FROM_BOOLEAN = true            -- Region:SetAlphaFromBoolean
API.HAS_SHOWN_FROM_BOOLEAN = true            -- Cooldown:SetShownFromBoolean

-- String Utilities
API.HAS_SECRET_STRING_UTILS = true           -- C_StringUtil.TruncateWhenZero, WrapString, etc.
API.HAS_SECRET_COLOR_WRAP = true             -- WrapTextInColorCode with secrets

-- ============================================================================
-- INTERPOLATION CONSTANTS
-- ============================================================================

-- Status bar interpolation (always available in Midnight)
API.BAR_INTERPOLATION = Enum.StatusBarInterpolation.ExponentialEaseOut

-- Timer bar directions
API.TIMER_DIRECTION = {
    ELAPSED = nil,  -- Default
    REMAINING = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.Remaining or nil,
}

-- ============================================================================
-- AURA SORTING CONSTANTS
-- ============================================================================

API.AURA_SORT = {
    UNSORTED = Enum.UnitAuraSortRule.Unsorted,
    DEFAULT = Enum.UnitAuraSortRule.Default,
    BIG_DEFENSIVE = Enum.UnitAuraSortRule.BigDefensive,
    EXPIRATION = Enum.UnitAuraSortRule.Expiration,
    EXPIRATION_ONLY = Enum.UnitAuraSortRule.ExpirationOnly,
    NAME = Enum.UnitAuraSortRule.Name,
    NAME_ONLY = Enum.UnitAuraSortRule.NameOnly,
}

API.AURA_SORT_DIRECTION = {
    NORMAL = Enum.UnitAuraSortDirection.Normal,
    REVERSE = Enum.UnitAuraSortDirection.Reverse,
}

-- ============================================================================
-- RESTRICTION TYPE CONSTANTS
-- ============================================================================

API.RESTRICTION_TYPE = {
    COMBAT = Enum.AddOnRestrictionType.Combat,
    ENCOUNTER = Enum.AddOnRestrictionType.Encounter,
    CHALLENGE_MODE = Enum.AddOnRestrictionType.ChallengeMode,
    PVP_MATCH = Enum.AddOnRestrictionType.PvPMatch,
    MAP = Enum.AddOnRestrictionType.Map,
}

API.RESTRICTION_STATE = {
    INACTIVE = Enum.AddOnRestrictionState.Inactive,
    ACTIVATING = Enum.AddOnRestrictionState.Activating,
    ACTIVE = Enum.AddOnRestrictionState.Active,
}

-- ============================================================================
-- SECRECY LEVEL CONSTANTS
-- ============================================================================

API.SECRECY_LEVEL = {
    NEVER = Enum.SecrecyLevel.NeverSecret,
    ALWAYS = Enum.SecrecyLevel.AlwaysSecret,
    CONTEXTUAL = Enum.SecrecyLevel.Contextual,
}

-- ============================================================================
-- DEBUG / STATUS
-- ============================================================================

-- Helper: Set cooldown frame from aura data (used by PersonalResources and other modules)
-- Returns true if cooldown was set successfully
function API.SetCooldownFromAura(cooldownFrame, unit, auraInstanceID)
    if not cooldownFrame or not unit or not auraInstanceID then return false end
    
    -- Delegate to DurationAPI if available
    if TUICD.DurationAPI and TUICD.DurationAPI.ApplyAuraDurationToFrame then
        return TUICD.DurationAPI:ApplyAuraDurationToFrame(cooldownFrame, unit, auraInstanceID, true)
    end
    
    -- Fallback: direct implementation
    local auraData = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if not auraData then
        cooldownFrame:Clear()
        return false
    end
    
    -- Try Duration Object API first
    if cooldownFrame.SetCooldownFromDurationObject and C_UnitAuras.GetUnitAuraDuration then
        local duration = C_UnitAuras.GetUnitAuraDuration(unit, auraInstanceID)
        if duration then
            cooldownFrame:SetCooldownFromDurationObject(duration, true)
            return true
        end
    end
    
    -- Fallback: traditional SetCooldown (wrap in pcall for secret values)
    local success = pcall(function()
        if auraData.expirationTime and auraData.duration and auraData.duration > 0 then
            local startTime = auraData.expirationTime - auraData.duration
            cooldownFrame:SetCooldown(startTime, auraData.duration)
        else
            cooldownFrame:Clear()
        end
    end)
    
    return success
end

function API:PrintStatus()
    TUICD:Print("=== TUICD 2.0 API Status ===")
    TUICD:Print("Midnight Verified: " .. (self.IsMidnightVerified and "|cff00ff00YES|r" or "|cffff0000NO|r"))
    TUICD:Print("Build Version: " .. TUICD.BUILD_VERSION)
    TUICD:Print("Duration Objects: |cff00ff00Available|r")
    TUICD:Print("Smooth Status Bars: |cff00ff00Available|r")
    TUICD:Print("Secret Value System: |cff00ff00Available|r")
    TUICD:Print("Aura Sorting: |cff00ff00Available|r")
    TUICD:Print("Heal Prediction Calculator: |cff00ff00Available|r")
end

-- Slash command to check API status
SLASH_TUIAPI1 = "/tuiapi"
SlashCmdList["TUIAPI"] = function()
    API:PrintStatus()
end

return API
