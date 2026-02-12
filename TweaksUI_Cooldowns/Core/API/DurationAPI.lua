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

-- Check if duration is active (has remaining time > 0)
-- Uses TruncateWhenZero for secret-safe detection:
-- returns secret string when > 0, non-secret "" when = 0
function DurationAPI:IsActive(durationObj)
    if not durationObj then return false end
    local ok, remaining = pcall(durationObj.GetRemainingDuration, durationObj)
    if not ok or remaining == nil then return false end
    
    if IsSecret(remaining) then
        -- Use TruncateWhenZero for secret-safe > 0 check
        if C_StringUtil and C_StringUtil.TruncateWhenZero then
            local ok2, str = pcall(C_StringUtil.TruncateWhenZero, remaining)
            if ok2 and str ~= nil then
                -- Secret result = value > 0 (active). Non-secret = value = 0 (expired).
                return IsSecret(str)
            end
        end
        return true  -- Conservative fallback
    end
    return type(remaining) == "number" and remaining > 0
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

-- Get remaining seconds from a spell's Duration Object as a plain number.
-- Returns nil when value is secret (caller should treat as "unknown" / fire immediately).
function DurationAPI:GetSpellRemainingSeconds(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellCooldownDuration then return nil end
    local ok, dObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    if not ok or not dObj then return nil end
    local rok, remaining = pcall(dObj.GetRemainingDuration, dObj)
    if not rok or not remaining then return nil end
    if type(remaining) ~= "number" then return nil end
    if IsSecret(remaining) then return nil end
    return remaining
end

-- ============================================================================
-- REAL COOLDOWN DETECTION (GCD-safe, secret-safe)
--
-- Multi-path GCD filtering:
--   Path 1: isOnGCD field (if non-secret — secret bools can't be branched)
--   Path 2: GetTotalDuration (if non-secret and ≤ 2s → GCD)
--   Path 3: Known-real-CD cache + debounce (wait > 2s to confirm not GCD)
--   Path 4: Unknown spell + all-secret → assume GCD (safe, prevents flashing)
--
-- IMPORTANT: Midnight's "if x then" on a secret value tests non-nil, not truthiness.
-- So "if secretFalse then" → true! We MUST check issecretvalue before branching.
--
-- GCD BUG: When all values are secret, EVERY GCD cycle makes every spell's
-- Duration Object briefly active. Without debounce, known spells would flash
-- true→false→true on every GCD (~1.5s), triggering false on-ready alerts.
-- ============================================================================

-- Spells confirmed to have real CDs, learned from non-secret reads
-- Persists across GCD cycles so combat reads can trust the cache
DurationAPI._knownRealCDs = DurationAPI._knownRealCDs or {}

-- Debounce timers: { [spellID] = GetTime() when first detected active }
-- If spell stays active > 2s, it's a real CD (GCD is always < 2s)
DurationAPI._activeTimers = DurationAPI._activeTimers or {}

local GCD_DEBOUNCE_SEC = 2.0

-- Check if a spell is on a REAL cooldown (not GCD), handling secret values.
-- @param spellID: numeric spell ID
-- @return isOnRealCD (bool), durationObj (or nil)
function DurationAPI:IsRealCooldownActive(spellID)
    if not spellID or not C_Spell then return false, nil end

    -- Get Duration Object first (needed for all paths)
    if not C_Spell.GetSpellCooldownDuration then return false, nil end
    local ok, dObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    if not ok or not dObj then return false, nil end

    -- Is anything active at all? (secret-safe)
    if not self:IsActive(dObj) then
        self._activeTimers[spellID] = nil  -- Reset debounce when CD fully expires
        return false, nil
    end

    -- Path 1: isOnGCD from C_Spell.GetSpellCooldown
    -- ONLY trust if the value is non-secret (secret bools can't be branched)
    local gcdKnown = false  -- did we get a definitive answer?
    local gcdResult = false -- true = is GCD, false = is real CD
    if C_Spell.GetSpellCooldown then
        pcall(function()
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo then
                local gcd = cdInfo.isOnGCD
                if gcd ~= nil then
                    if issecretvalue and issecretvalue(gcd) then
                        -- Secret boolean — can't branch on it, skip
                    else
                        gcdKnown = true
                        gcdResult = (gcd == true)
                    end
                end
            end
        end)
    end

    if gcdKnown then
        if gcdResult then
            self._activeTimers[spellID] = nil
            return false, nil  -- confirmed GCD
        else
            self._knownRealCDs[spellID] = true
            self._activeTimers[spellID] = nil
            return true, dObj  -- confirmed real CD
        end
    end

    -- Path 2: Check total duration (if non-secret and ≤ 2s → GCD)
    local totalSec = nil
    pcall(function()
        local total = dObj:GetTotalDuration()
        if total and type(total) == "number" then
            if not (issecretvalue and issecretvalue(total)) then
                totalSec = total
            end
        end
    end)

    if totalSec then
        if totalSec <= 2.0 then
            self._activeTimers[spellID] = nil
            return false, nil  -- GCD (≤ 2s)
        else
            self._knownRealCDs[spellID] = true
            self._activeTimers[spellID] = nil
            return true, dObj  -- real CD (> 2s)
        end
    end

    -- Path 3: All values secret — debounce for GCD filtering
    -- Even for known spells, we MUST debounce because every GCD cycle
    -- makes all spell Duration Objects briefly active (~1.5s).
    -- Only confirm real CD after the activation persists > 2s.
    if not self._activeTimers[spellID] then
        self._activeTimers[spellID] = GetTime()
    end

    local elapsed = GetTime() - self._activeTimers[spellID]
    if elapsed >= GCD_DEBOUNCE_SEC then
        -- Active for > 2s → definitely a real CD
        return true, dObj
    end

    -- Path 4: Still in debounce window → assume GCD (safe default)
    -- Prevents flashing every icon on each GCD pulse
    return false, nil
end

-- ============================================================================
-- COLOR CURVES (for secret-safe color-by-time)
--
-- Creates Curve objects that can be evaluated against Duration Objects:
--   durObj:EvaluateRemainingPercent(curve)
-- Returns secret values passable to SetVertexColor/SetStatusBarColor.
-- Pattern proven by TellMeWhen addon.
-- ============================================================================

-- Create a pair of Curve objects for one color channel (normal + inverted)
-- @param lowValue: value when remaining ≈ 0% (near expiry)
-- @param midValue: value at 50% remaining
-- @param highValue: value at 100% remaining (just started)
-- @return curve, curveInverted (or nil, nil if all values equal)
function DurationAPI:CreateChannelCurves(lowValue, midValue, highValue)
    if not C_CurveUtil or not C_CurveUtil.CreateCurve then return nil, nil end
    if not Enum or not Enum.LuaCurveType or not Enum.LuaCurveType.Linear then return nil, nil end
    if lowValue == midValue and midValue == highValue then return nil, nil end

    local ok, curve, inv = pcall(function()
        -- Normal: 0% remaining = low, 50% = mid, 100% = high
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Linear)
        c:AddPoint(0, lowValue)    -- expired / near expiry
        c:AddPoint(0.5, midValue)  -- halfway
        c:AddPoint(1, highValue)   -- just started

        -- Inverted: for drain bars
        local i = C_CurveUtil.CreateCurve()
        i:SetType(Enum.LuaCurveType.Linear)
        i:AddPoint(0, highValue)
        i:AddPoint(0.5, midValue)
        i:AddPoint(1, lowValue)

        return c, i
    end)

    if ok then return curve, inv end
    return nil, nil
end

-- Create RGB Curve set from 3 color tables { r, g, b }
-- @return { r, g, b } of Curve objects (nil channels where no change)
function DurationAPI:CreateColorCurves(lowColor, midColor, highColor)
    if not C_CurveUtil then return nil end
    local rC = self:CreateChannelCurves(lowColor.r, midColor.r, highColor.r)
    local gC = self:CreateChannelCurves(lowColor.g, midColor.g, highColor.g)
    local bC = self:CreateChannelCurves(lowColor.b, midColor.b, highColor.b)
    return { r = rC, g = gC, b = bC }
end

-- Evaluate color curves against a Duration Object
-- @return r, g, b (secret values passable to SetVertexColor/SetStatusBarColor)
function DurationAPI:EvaluateColorCurves(dObj, curves, defaultColor)
    if not dObj or not curves then
        return defaultColor.r, defaultColor.g, defaultColor.b
    end
    local ok, r, g, b = pcall(function()
        local cr = curves.r and dObj:EvaluateRemainingPercent(curves.r) or defaultColor.r
        local cg = curves.g and dObj:EvaluateRemainingPercent(curves.g) or defaultColor.g
        local cb = curves.b and dObj:EvaluateRemainingPercent(curves.b) or defaultColor.b
        return cr, cg, cb
    end)
    if ok then return r, g, b end
    return defaultColor.r, defaultColor.g, defaultColor.b
end

return DurationAPI
