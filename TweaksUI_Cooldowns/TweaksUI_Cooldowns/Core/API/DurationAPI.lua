-- ============================================================================
-- TUICD: Duration API Wrapper
-- Midnight Duration Object utilities and helpers
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.DurationAPI = TUICD.DurationAPI or {}
local DurationAPI = TUICD.DurationAPI

-- ============================================================================
-- DURATION OBJECT CREATION
-- ============================================================================

-- Create an empty duration object
function DurationAPI:Create()
    return C_DurationUtil.CreateDuration()
end

-- Create a duration from start time and length
function DurationAPI:CreateFromStart(startTime, duration, modRate)
    local durationObj = C_DurationUtil.CreateDuration()
    durationObj:SetTimeFromStart(startTime, duration, modRate)
    return durationObj
end

-- Create a duration from end time and length
function DurationAPI:CreateFromEnd(endTime, duration, modRate)
    local durationObj = C_DurationUtil.CreateDuration()
    durationObj:SetTimeFromEnd(endTime, duration, modRate)
    return durationObj
end

-- Create a duration from time span
function DurationAPI:CreateFromSpan(startTime, endTime)
    local durationObj = C_DurationUtil.CreateDuration()
    durationObj:SetTimeSpan(startTime, endTime)
    return durationObj
end

-- ============================================================================
-- DURATION OBJECT QUERIES
-- ============================================================================

-- Get elapsed duration from object (may return secret)
function DurationAPI:GetElapsed(durationObj)
    if not durationObj then return 0 end
    return durationObj:GetElapsedDuration()
end

-- Get remaining duration from object (may return secret)
function DurationAPI:GetRemaining(durationObj)
    if not durationObj then return 0 end
    return durationObj:GetRemainingDuration()
end

-- Evaluate elapsed progress with curve
function DurationAPI:EvaluateElapsed(durationObj, curve, modifier)
    if not durationObj then return 0 end
    return durationObj:EvaluateElapsedDuration(curve, modifier)
end

-- Evaluate remaining progress with curve
function DurationAPI:EvaluateRemaining(durationObj, curve, modifier)
    if not durationObj then return 0 end
    return durationObj:EvaluateRemainingDuration(curve, modifier)
end

-- ============================================================================
-- APPLYING TO UI ELEMENTS
-- ============================================================================

-- Apply duration to cooldown frame
function DurationAPI:ApplyToCooldown(cooldownFrame, durationObj, clearIfZero)
    if not cooldownFrame or not durationObj then return false end
    cooldownFrame:SetCooldownFromDurationObject(durationObj, clearIfZero ~= false)
    return true
end

-- Apply duration to status bar (timer bar)
function DurationAPI:ApplyToStatusBar(statusBar, durationObj, interpolation, direction)
    if not statusBar or not durationObj then return false end
    
    interpolation = interpolation or TUICD.API.BAR_INTERPOLATION
    statusBar:SetTimerDuration(durationObj, interpolation, direction)
    return true
end

-- Apply duration to status bar for elapsed time display
function DurationAPI:ApplyToStatusBarElapsed(statusBar, durationObj, interpolation)
    return self:ApplyToStatusBar(statusBar, durationObj, interpolation, nil)
end

-- Apply duration to status bar for remaining time display
function DurationAPI:ApplyToStatusBarRemaining(statusBar, durationObj, interpolation)
    return self:ApplyToStatusBar(statusBar, durationObj, interpolation, 
        TUICD.API.TIMER_DIRECTION.REMAINING)
end

-- ============================================================================
-- COOLDOWN FRAME HELPERS
-- ============================================================================

-- Set cooldown from expiration time (convenience wrapper)
function DurationAPI:SetCooldownFromExpiration(cooldownFrame, expirationTime, duration, modRate)
    if not cooldownFrame then return false end
    cooldownFrame:SetCooldownFromExpirationTime(expirationTime, duration, modRate)
    return true
end

-- ============================================================================
-- SPELL DURATION GETTERS
-- ============================================================================

-- Get spell cooldown duration object
function DurationAPI:GetSpellCooldown(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellCooldownDuration(spellID)
end

-- Get spell charges cooldown duration object
function DurationAPI:GetSpellCharges(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellChargesCooldownDuration(spellID)
end

-- Get spell loss of control duration object
function DurationAPI:GetSpellLossOfControl(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellLossOfControlCooldownDuration(spellID)
end

-- ============================================================================
-- ACTION BAR DURATION GETTERS
-- ============================================================================

-- Get action cooldown duration object
function DurationAPI:GetActionCooldown(slot)
    if not slot then return nil end
    return C_ActionBar.GetActionCooldownDuration(slot)
end

-- Get action charges cooldown duration object
function DurationAPI:GetActionCharges(slot)
    if not slot then return nil end
    return C_ActionBar.GetActionChargesCooldownDuration(slot)
end

-- Get action loss of control duration object
function DurationAPI:GetActionLossOfControl(slot)
    if not slot then return nil end
    return C_ActionBar.GetActionLossOfControlCooldownDuration(slot)
end

-- ============================================================================
-- AURA DURATION GETTERS
-- ============================================================================

-- Get aura duration object (or create one from aura data)
function DurationAPI:GetAuraDuration(unit, auraInstanceID)
    if not unit or not auraInstanceID then return nil end
    
    -- Try native API first (added in Beta 4)
    if C_UnitAuras and C_UnitAuras.GetUnitAuraDuration then
        return C_UnitAuras.GetUnitAuraDuration(unit, auraInstanceID)
    end
    
    -- Fallback: create duration object from aura data (if C_DurationUtil available)
    -- Note: ALL aura data fields are SECRET - wrap everything in pcall
    if C_DurationUtil and C_DurationUtil.CreateDuration then
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
        if auraData then
            local duration = C_DurationUtil.CreateDuration()
            if duration then
                -- SetTimeFromEnd can handle secret values - wrap in pcall
                local success = pcall(function()
                    duration:SetTimeFromEnd(auraData.expirationTime, auraData.duration)
                end)
                if success then
                    return duration
                end
            end
        end
    end
    
    return nil
end

-- Apply aura duration to a cooldown frame
function DurationAPI:ApplyAuraDurationToFrame(cooldownFrame, unit, auraInstanceID, clearIfZero)
    if not cooldownFrame or not unit or not auraInstanceID then return false end
    
    -- Get aura data for duration info
    local auraData = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if not auraData then
        if clearIfZero ~= false then
            cooldownFrame:Clear()
        end
        return false
    end
    
    -- Try Duration Object API first (cleanest approach)
    if cooldownFrame.SetCooldownFromDurationObject then
        local duration = self:GetAuraDuration(unit, auraInstanceID)
        if duration then
            cooldownFrame:SetCooldownFromDurationObject(duration, clearIfZero ~= false)
            return true
        end
    end
    
    -- Fallback: use traditional SetCooldown
    -- Note: duration/expirationTime are SECRET - wrap in pcall
    local success = pcall(function()
        if auraData.expirationTime and auraData.duration then
            local startTime = auraData.expirationTime - auraData.duration
            cooldownFrame:SetCooldown(startTime, auraData.duration)
        end
    end)
    
    if success then
        return true
    end
    
    if clearIfZero ~= false then
        cooldownFrame:Clear()
    end
    return false
end

-- ============================================================================
-- CAST DURATION GETTERS
-- ============================================================================

-- Get unit casting duration object
function DurationAPI:GetCastingDuration(unit)
    if not unit then return nil end
    return UnitCastingDuration(unit)
end

-- Get unit channel duration object
function DurationAPI:GetChannelDuration(unit)
    if not unit then return nil end
    return UnitChannelDuration(unit)
end

-- Get empowered channel duration object
function DurationAPI:GetEmpoweredDuration(unit, includeHoldTime)
    if not unit then return nil end
    if not UnitEmpoweredChannelDuration then return nil end
    local success, result = pcall(function()
        return UnitEmpoweredChannelDuration(unit, includeHoldTime ~= false)
    end)
    if success then return result end
    return nil
end

-- Get empowered stage durations (returns table of duration objects)
function DurationAPI:GetEmpoweredStageDurations(unit)
    if not unit then return nil end
    if not UnitEmpoweredStageDurations then return nil end
    local success, result = pcall(function()
        return UnitEmpoweredStageDurations(unit)
    end)
    if success then return result end
    return nil
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Safe check if a value is secret
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

-- Check if duration is active (has remaining time)
function DurationAPI:IsActive(durationObj)
    if not durationObj then return false end
    local remaining = durationObj:GetRemainingDuration()
    -- Note: remaining might be a secret value, so we can't compare directly
    -- This is a best-effort check
    if IsSecret(remaining) then
        return true  -- Assume active if we can't tell
    end
    return remaining and remaining > 0
end

-- Format duration for display (handles secret values)
function DurationAPI:Format(durationObj)
    if not durationObj then return "" end
    
    local remaining = durationObj:GetRemainingDuration()
    
    -- Handle secret values
    if IsSecret(remaining) then
        if C_StringUtil and C_StringUtil.TruncateWhenZero then
            return C_StringUtil.TruncateWhenZero(remaining)
        end
        return ""
    end
    
    -- Non-secret formatting
    if not remaining or remaining <= 0 then
        return ""
    elseif remaining < 2 then
        return string.format("%.1f", remaining)
    elseif remaining < 60 then
        return string.format("%d", math.floor(remaining))
    elseif remaining < 3600 then
        return string.format("%dm", math.floor(remaining / 60))
    else
        return string.format("%dh", math.floor(remaining / 3600))
    end
end

-- Get empowered stage percentages (non-secret values describing stage positions)
function DurationAPI:GetEmpoweredStagePercentages(unit, includeHoldTime)
    if not unit then return nil end
    if not UnitEmpoweredStagePercentages then return nil end
    local success, result = pcall(function()
        return UnitEmpoweredStagePercentages(unit, includeHoldTime ~= false)
    end)
    if success then return result end
    return nil
end

-- Check if a unit is currently casting an empowered spell
function DurationAPI:IsEmpoweredCast(unit)
    if not unit then return false, 0 end
    
    -- UnitChannelInfo returns isEmpowered and numEmpowerStages in Midnight
    local _, _, _, _, _, _, _, _, _, _, _, isEmpowered, numEmpowerStages = UnitChannelInfo(unit)
    return isEmpowered == true, numEmpowerStages or 0
end

return DurationAPI
