-- ============================================================================
-- TUICD: Status Bar API Wrapper
-- Midnight smooth status bar and timer bar utilities
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.StatusBarAPI = TUICD.StatusBarAPI or {}
local StatusBarAPI = TUICD.StatusBarAPI

-- ============================================================================
-- INTERPOLATION CONSTANTS
-- ============================================================================

StatusBarAPI.INTERPOLATION = {
    NONE = nil,
    EXPONENTIAL = Enum.StatusBarInterpolation.ExponentialEaseOut,
}

-- Default interpolation for smooth transitions
StatusBarAPI.DEFAULT_INTERPOLATION = Enum.StatusBarInterpolation.ExponentialEaseOut

-- ============================================================================
-- FILL STYLE CONSTANTS
-- ============================================================================

StatusBarAPI.FILL_STYLE = {
    STANDARD = Enum.StatusBarFillStyle.Standard,
    REVERSE = Enum.StatusBarFillStyle.Reverse,
    CENTER = Enum.StatusBarFillStyle.Center,
    REVERSE_CENTER = Enum.StatusBarFillStyle.ReverseCenter,
}

-- ============================================================================
-- TIMER DIRECTION CONSTANTS
-- ============================================================================

StatusBarAPI.TIMER_DIRECTION = {
    ELAPSED = nil,  -- Default - bar fills as time passes
    REMAINING = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.Remaining or nil,
}

-- ============================================================================
-- VALUE SETTING
-- ============================================================================

-- Set status bar value with optional smooth interpolation
function StatusBarAPI:SetValue(statusBar, value, smooth)
    if not statusBar then return end
    
    if smooth then
        statusBar:SetValue(value, self.DEFAULT_INTERPOLATION)
    else
        statusBar:SetValue(value)
    end
end

-- Set status bar value with specific interpolation
function StatusBarAPI:SetValueInterpolated(statusBar, value, interpolation)
    if not statusBar then return end
    statusBar:SetValue(value, interpolation)
end

-- Set min/max values with optional smooth interpolation
function StatusBarAPI:SetMinMaxValues(statusBar, minValue, maxValue, smooth)
    if not statusBar then return end
    
    if smooth then
        statusBar:SetMinMaxValues(minValue, maxValue, self.DEFAULT_INTERPOLATION)
    else
        statusBar:SetMinMaxValues(minValue, maxValue)
    end
end

-- ============================================================================
-- FILL STYLE
-- ============================================================================

-- Set fill style using enum (Midnight uses enum instead of string)
function StatusBarAPI:SetFillStyle(statusBar, fillStyle)
    if not statusBar then return end
    
    -- Accept both string and enum
    if type(fillStyle) == "string" then
        local styleMap = {
            ["STANDARD"] = Enum.StatusBarFillStyle.Standard,
            ["REVERSE"] = Enum.StatusBarFillStyle.Reverse,
            ["CENTER"] = Enum.StatusBarFillStyle.Center,
            ["REVERSE_CENTER"] = Enum.StatusBarFillStyle.ReverseCenter,
        }
        fillStyle = styleMap[fillStyle] or Enum.StatusBarFillStyle.Standard
    end
    
    statusBar:SetFillStyle(fillStyle)
end

-- ============================================================================
-- TIMER STATUS BARS
-- ============================================================================

-- Set up a timer status bar from duration object
function StatusBarAPI:SetTimerDuration(statusBar, durationObject, interpolation, direction)
    if not statusBar or not durationObject then return end
    
    interpolation = interpolation or self.DEFAULT_INTERPOLATION
    statusBar:SetTimerDuration(durationObject, interpolation, direction)
end

-- Set up timer bar for elapsed time display
function StatusBarAPI:SetTimerElapsed(statusBar, durationObject, interpolation)
    self:SetTimerDuration(statusBar, durationObject, interpolation, nil)
end

-- Set up timer bar for remaining time display
function StatusBarAPI:SetTimerRemaining(statusBar, durationObject, interpolation)
    self:SetTimerDuration(statusBar, durationObject, interpolation, self.TIMER_DIRECTION.REMAINING)
end

-- ============================================================================
-- TIMER QUERIES
-- ============================================================================

-- Get timer bar duration
function StatusBarAPI:GetDuration(statusBar)
    if not statusBar then return 0 end
    return statusBar:GetDuration()
end

-- Get timer bar start time
function StatusBarAPI:GetStartTime(statusBar)
    if not statusBar then return 0 end
    return statusBar:GetStartTime()
end

-- Get timer bar end time
function StatusBarAPI:GetEndTime(statusBar)
    if not statusBar then return 0 end
    return statusBar:GetEndTime()
end

-- Get timer bar elapsed time
function StatusBarAPI:GetElapsedTime(statusBar)
    if not statusBar then return 0 end
    return statusBar:GetElapsedTime()
end

-- Get timer bar remaining time
function StatusBarAPI:GetRemainingTime(statusBar)
    if not statusBar then return 0 end
    return statusBar:GetRemainingTime()
end

-- Get all timer info as table
function StatusBarAPI:GetTimerInfo(statusBar)
    if not statusBar then return nil end
    
    return {
        duration = statusBar:GetDuration(),
        startTime = statusBar:GetStartTime(),
        endTime = statusBar:GetEndTime(),
        elapsed = statusBar:GetElapsedTime(),
        remaining = statusBar:GetRemainingTime(),
    }
end

-- ============================================================================
-- HEALTH BAR HELPERS
-- ============================================================================

-- Set health bar value with smooth transition
function StatusBarAPI:SetHealthValue(statusBar, currentHealth, maxHealth, smooth)
    if not statusBar then return end
    
    -- Set max first
    self:SetMinMaxValues(statusBar, 0, maxHealth, smooth)
    
    -- Then set current
    self:SetValue(statusBar, currentHealth, smooth)
end

-- Set health bar from unit with smooth transition
function StatusBarAPI:SetHealthFromUnit(statusBar, unit, smooth)
    if not statusBar or not unit then return end
    
    local current = UnitHealth(unit)
    local max = UnitHealthMax(unit)
    
    self:SetHealthValue(statusBar, current, max, smooth)
end

-- ============================================================================
-- POWER BAR HELPERS
-- ============================================================================

-- Set power bar value with smooth transition
function StatusBarAPI:SetPowerValue(statusBar, currentPower, maxPower, smooth)
    if not statusBar then return end
    
    self:SetMinMaxValues(statusBar, 0, maxPower, smooth)
    self:SetValue(statusBar, currentPower, smooth)
end

-- Set power bar from unit with smooth transition
function StatusBarAPI:SetPowerFromUnit(statusBar, unit, powerType, smooth)
    if not statusBar or not unit then return end
    
    local current = UnitPower(unit, powerType)
    local max = UnitPowerMax(unit, powerType)
    
    self:SetPowerValue(statusBar, current, max, smooth)
end

-- ============================================================================
-- CAST BAR HELPERS
-- ============================================================================

-- Set up cast bar from unit casting
function StatusBarAPI:SetupCastBar(statusBar, unit, smooth)
    if not statusBar or not unit then return false end
    
    local durationObj = UnitCastingDuration(unit)
    if durationObj then
        self:SetTimerElapsed(statusBar, durationObj, smooth and self.DEFAULT_INTERPOLATION or nil)
        return true
    end
    return false
end

-- Set up channel bar from unit channeling
function StatusBarAPI:SetupChannelBar(statusBar, unit, smooth)
    if not statusBar or not unit then return false end
    
    local durationObj = UnitChannelDuration(unit)
    if durationObj then
        self:SetTimerRemaining(statusBar, durationObj, smooth and self.DEFAULT_INTERPOLATION or nil)
        return true
    end
    return false
end

-- Set up empowered cast bar
function StatusBarAPI:SetupEmpoweredBar(statusBar, unit, includeHoldTime, smooth)
    if not statusBar or not unit then return false end
    
    local durationObj = UnitEmpoweredChannelDuration(unit, includeHoldTime ~= false)
    if durationObj then
        self:SetTimerElapsed(statusBar, durationObj, smooth and self.DEFAULT_INTERPOLATION or nil)
        return true
    end
    return false
end

-- ============================================================================
-- COOLDOWN BAR HELPERS
-- ============================================================================

-- Set up cooldown bar from spell
function StatusBarAPI:SetupSpellCooldownBar(statusBar, spellID, smooth)
    if not statusBar or not spellID then return false end
    
    local durationObj = C_Spell.GetSpellCooldownDuration(spellID)
    if durationObj then
        self:SetTimerRemaining(statusBar, durationObj, smooth and self.DEFAULT_INTERPOLATION or nil)
        return true
    end
    return false
end

-- Set up cooldown bar from action
function StatusBarAPI:SetupActionCooldownBar(statusBar, slot, smooth)
    if not statusBar or not slot then return false end
    
    local durationObj = C_ActionBar.GetActionCooldownDuration(slot)
    if durationObj then
        self:SetTimerRemaining(statusBar, durationObj, smooth and self.DEFAULT_INTERPOLATION or nil)
        return true
    end
    return false
end

-- ============================================================================
-- AURA TIMER BAR HELPERS
-- ============================================================================

-- Set up aura timer bar
function StatusBarAPI:SetupAuraBar(statusBar, unit, auraInstanceID, smooth)
    if not statusBar or not unit or not auraInstanceID then return false end
    
    local durationObj = C_UnitAuras.GetUnitAuraDuration(unit, auraInstanceID)
    if durationObj then
        self:SetTimerRemaining(statusBar, durationObj, smooth and self.DEFAULT_INTERPOLATION or nil)
        return true
    end
    return false
end

return StatusBarAPI
