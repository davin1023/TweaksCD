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
-- Follows TMW's proven pattern: uses C_Spell.GetSpellCooldown() as the
-- PRIMARY detection mechanism. The SpellCooldownInfo struct contains
-- isOnGCD, startTime, duration — everything needed to distinguish
-- GCD from real cooldowns.
--
-- Duration Objects from C_Spell.GetSpellCooldownDuration are used ONLY
-- for display (feeding SetTimerDuration, time text, etc).
--
-- Detection paths (ordered by reliability):
--   Path 1: isOnGCD from SpellCooldownInfo (non-secret → definitive)
--   Path 2: duration from SpellCooldownInfo (non-secret → check for zero,
--           compare against GCD spell duration)
--   Path 3: Duration Object curve check (secret-safe, remaining > 2s)
--   Path 4: Conservative default → assume GCD (safe, prevents flashing)
--
-- IMPORTANT: Midnight's "if x then" on a secret value tests non-nil,
-- not truthiness. So "if secretFalse then" → true! We MUST check
-- issecretvalue before branching on potentially secret values.
-- ============================================================================

-- GCD spell ID (61304) for duration comparison
local GCD_SPELL_ID = 61304

-- Get the current GCD duration as a plain number (non-secret).
-- Returns nil if the value is secret or unavailable.
-- Used by IsRealCooldownActive to compare a spell's duration against the
-- actual GCD duration (TMW pattern: if duration == GCD → it's a GCD).
function DurationAPI:GetGCDDuration()
    if not C_Spell or not C_Spell.GetSpellCooldown then return nil end
    local ok, gcdInfo = pcall(C_Spell.GetSpellCooldown, GCD_SPELL_ID)
    if not ok or not gcdInfo then return nil end
    local d = gcdInfo.duration
    if d and type(d) == "number" and not (issecretvalue and issecretvalue(d)) then
        return d
    end
    return nil
end

-- ============================================================================
-- GCD FILTER CURVE
-- A step curve that maps remaining duration in seconds to:
--   0.0  if remaining ≤ 2.0s  (GCD range)
--   1.0  if remaining > 2.0s  (real CD range)
-- Used with EvaluateRemainingDuration to secret-safely distinguish GCD from
-- real cooldowns.  Combined with TruncateWhenZero:
--   result = 0 → TruncateWhenZero returns "" (non-secret) → GCD
--   result = 1 → TruncateWhenZero returns secret "1"     → real CD
-- ============================================================================
local gcdFilterCurve = nil

local function GetGCDFilterCurve()
    if gcdFilterCurve then return gcdFilterCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateCurve then return nil end
    if not Enum or not Enum.LuaCurveType then return nil end

    local ok, curve = pcall(function()
        local c = C_CurveUtil.CreateCurve()
        -- Use Linear with a sharp transition at 2.0s
        c:SetType(Enum.LuaCurveType.Linear)
        c:AddPoint(0, 0)       -- 0s remaining → 0
        c:AddPoint(2.0, 0)     -- 2.0s remaining → 0 (still GCD range)
        c:AddPoint(2.01, 1)    -- 2.01s remaining → 1 (real CD)
        c:AddPoint(600, 1)     -- 10min remaining → 1
        return c
    end)
    if ok and curve then
        gcdFilterCurve = curve
    end
    return gcdFilterCurve
end

-- Secret-safe check: is Duration Object's remaining > 2s?
-- Returns true (real CD), false (GCD/expired), or nil (can't determine)
local function IsDurationLongerThanGCD(dObj)
    local curve = GetGCDFilterCurve()
    if not curve then return nil end
    if not C_StringUtil or not C_StringUtil.TruncateWhenZero then return nil end

    local ok, result = pcall(dObj.EvaluateRemainingDuration, dObj, curve)
    if not ok or result == nil then return nil end

    -- TruncateWhenZero: returns "" if value ≤ 0, secret string if > 0
    local ok2, str = pcall(C_StringUtil.TruncateWhenZero, result)
    if not ok2 then return nil end

    -- If str is secret → curve output was 1 → remaining > 2s → real CD
    -- If str is "" → curve output was 0 → remaining ≤ 2s → GCD
    if issecretvalue and issecretvalue(str) then
        return true   -- Real CD (remaining > 2s)
    end
    return false      -- GCD or expired (remaining ≤ 2s)
end

-- Public wrapper for bars/other consumers
function DurationAPI:IsDurationLongerThanGCD(dObj)
    return IsDurationLongerThanGCD(dObj)
end

-- ============================================================================
-- BAR ACTIVITY CURVE
-- Step curve for bar alpha: remaining > 0.0001 → 1 (on CD), remaining ≈ 0 → 0 (off CD)
-- Combined with isOnGCD via SetAlphaFromBoolean for complete GCD filtering.
-- Matches the community-proven "CD Ready texture" pattern but inverted for bars.
-- ============================================================================
local barActivityCurve = nil

local function GetBarActivityCurve()
    if barActivityCurve then return barActivityCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateCurve then return nil end
    if not Enum or not Enum.LuaCurveType then return nil end

    local ok, curve = pcall(function()
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, 0)        -- remaining = 0 → 0 (off CD)
        c:AddPoint(0.0001, 1)   -- remaining > 0 → 1 (on CD)
        return c
    end)
    if ok and curve then
        barActivityCurve = curve
    end
    return barActivityCurve
end

-- Get bar visibility data for a spell.  Returns all three values needed by
-- the frame layer to drive alpha-based GCD filtering:
--   dObj       - fresh Duration Object (or nil if API unavailable)
--   curveAlpha - secret number: 1 when any CD active, 0 when off CD
--   isOnGCD    - secret boolean from SpellCooldownInfo.isOnGCD
--
-- Frame layer combines them:  SetAlphaFromBoolean(isOnGCD, 0, curveAlpha)
--   isOnGCD true  → alpha = 0 (GCD only → hide)
--   isOnGCD false, remaining > 0 → alpha = 1 (real CD → show)
--   isOnGCD false, remaining = 0 → alpha = 0 (off CD → hide)
function DurationAPI:GetBarVisibility(spellID)
    if not spellID or not C_Spell then return nil, 0, false end

    -- Fresh Duration Object
    local dObj = nil
    if C_Spell.GetSpellCooldownDuration then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok then dObj = d end
    end

    -- Activity alpha from step curve
    local curveAlpha = 0
    local curve = GetBarActivityCurve()
    if dObj and curve then
        local ok, alpha = pcall(dObj.EvaluateRemainingDuration, dObj, curve)
        if ok and alpha ~= nil then
            curveAlpha = alpha
        end
    end

    -- isOnGCD from SpellCooldownInfo (may be secret boolean)
    local isOnGCD = false
    if C_Spell.GetSpellCooldown then
        pcall(function()
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo then
                isOnGCD = cdInfo.isOnGCD
            end
        end)
    end

    return dObj, curveAlpha, isOnGCD
end

-- Check if a spell is on a REAL cooldown (not GCD), handling secret values.
--
-- APPROACH (matches TMW's proven pattern):
--   PRIMARY detection via C_Spell.GetSpellCooldown → SpellCooldownInfo
--   (struct containing isOnGCD, startTime, duration, endTime).
--   Duration Object from GetSpellCooldownDuration is ONLY for display.
--
-- @param spellID: numeric spell ID
-- @return isOnRealCD (bool), durationObj (or nil)
function DurationAPI:IsRealCooldownActive(spellID)
    if not spellID or not C_Spell then return false, nil end

    -- ====================================================================
    -- STEP 1: Get SpellCooldownInfo — PRIMARY detection source.
    -- ====================================================================
    local cdInfo = nil
    if C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and info then cdInfo = info end
    end

    -- ====================================================================
    -- STEP 2: Get Duration Object — needed for display and secret fallback.
    -- Always fetch fresh; don't rely on stored objects.
    -- ====================================================================
    local dObj = nil
    if C_Spell.GetSpellCooldownDuration then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok and d then dObj = d end
    end

    -- ====================================================================
    -- STEP 3: Non-secret detection via SpellCooldownInfo struct fields.
    -- ====================================================================
    if cdInfo then
        local duration = cdInfo.duration
        local isOnGCD = cdInfo.isOnGCD

        -- Check if duration is a non-secret number we can branch on
        local durIsNumber = duration ~= nil
            and type(duration) == "number"
            and not (issecretvalue and issecretvalue(duration))

        -- Check if isOnGCD is a non-secret value we can branch on
        local gcdIsReadable = isOnGCD ~= nil
            and not (issecretvalue and issecretvalue(isOnGCD))

        if durIsNumber then
            -- No cooldown at all (includes Blizzard's tiny "pending" durations)
            if duration < 0.5 then
                return false, nil
            end

            -- isOnGCD readable and explicitly true → GCD only, not a real CD
            if gcdIsReadable and isOnGCD == true then
                return false, nil
            end

            -- isOnGCD readable and NOT true (false or nil) → real CD
            -- isOnGCD nil means the spell doesn't interact with GCD at all
            -- (like interrupts, defensives, trinkets) — definitely real CD
            if gcdIsReadable and not isOnGCD then
                if dObj then return true, dObj end
                -- No Duration Object available, create one from struct data
                local startTime = cdInfo.startTime
                if startTime and type(startTime) == "number"
                   and not (issecretvalue and issecretvalue(startTime)) then
                    dObj = self:CreateFromStart(startTime, duration, cdInfo.modRate)
                    return true, dObj
                end
                return false, nil
            end

            -- isOnGCD not readable (secret) but duration IS readable:
            -- Use TMW's OnGCD heuristic to determine if this is GCD
            if duration <= 1.0 then
                -- Any CD ≤ 1s is effectively a GCD in WoW
                return false, nil
            end
            -- Compare to GCD spell duration
            local gcdDur = self:GetGCDDuration()
            if gcdDur and gcdDur > 0 and math.abs(duration - gcdDur) < 0.01 then
                return false, nil  -- Duration matches GCD exactly
            end
            -- Duration is longer than GCD → real cooldown
            if dObj then return true, dObj end
            -- Fallback: create Duration Object from struct
            local startTime = cdInfo.startTime
            if startTime and type(startTime) == "number"
               and not (issecretvalue and issecretvalue(startTime)) then
                dObj = self:CreateFromStart(startTime, duration, cdInfo.modRate)
                return true, dObj
            end
            return false, nil
        end

        -- Duration is secret or nil. Check isOnGCD if readable.
        if gcdIsReadable and isOnGCD == true then
            return false, nil  -- Definitively GCD
        end
    end

    -- ====================================================================
    -- STEP 4: Secret fallback — all struct values are secret or struct
    -- is nil. Use Duration Object curve to check remaining > 2s.
    -- ====================================================================
    if dObj then
        -- First check if anything is active at all
        if not self:IsActive(dObj) then
            return false, nil
        end

        -- Use curve to check if remaining > 2s (secret-safe GCD filter)
        local curveResult = IsDurationLongerThanGCD(dObj)
        if curveResult == true then
            return true, dObj   -- Remaining > 2s → real CD
        elseif curveResult == false then
            return false, nil   -- Remaining ≤ 2s → GCD or expired
        end
    end

    -- ====================================================================
    -- STEP 5: Can't determine → conservative default (no bar).
    -- ====================================================================
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
