-- ============================================================================
-- TUICD: Secret Value API Wrapper
-- Utilities for handling Midnight's secret value system
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.SecretAPI = TUICD.SecretAPI or {}
local SecretAPI = TUICD.SecretAPI

-- ============================================================================
-- SECRET VALUE DETECTION
-- ============================================================================

-- Check if a value is secret
function SecretAPI:IsSecret(value)
    return issecretvalue(value)
end

-- Check if ANY value in a table is secret
function SecretAPI:HasSecretValues(tbl)
    if type(tbl) ~= "table" then
        return self:IsSecret(tbl)
    end
    
    for _, v in pairs(tbl) do
        if self:IsSecret(v) then
            return true
        end
        if type(v) == "table" and self:HasSecretValues(v) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- STRING UTILITIES
-- ============================================================================

-- Truncate number to empty string if zero (handles secrets)
function SecretAPI:TruncateWhenZero(number)
    return C_StringUtil.TruncateWhenZero(number)
end

-- Wrap string with prefix/suffix (only if infix not empty)
function SecretAPI:WrapString(infix, prefix, suffix)
    return C_StringUtil.WrapString(infix, prefix, suffix)
end

-- Remove contiguous spaces from string (handles secrets)
function SecretAPI:RemoveContiguousSpaces(str)
    return C_StringUtil.RemoveContiguousSpaces(str)
end

-- Escape Lua pattern characters (handles secrets)
function SecretAPI:EscapeLuaPatterns(str)
    return C_StringUtil.EscapeLuaPatterns(str)
end

-- Escape format string (replace % with %%)
function SecretAPI:EscapeLuaFormatString(str)
    return C_StringUtil.EscapeLuaFormatString(str)
end

-- ============================================================================
-- COLOR UTILITIES
-- ============================================================================

-- Wrap text in color code (handles secret strings)
function SecretAPI:WrapTextInColor(text, colorHex)
    return WrapTextInColorCode(text, colorHex)
end

-- Create colored text from RGB values
function SecretAPI:ColorText(text, r, g, b)
    local colorHex = string.format("ff%02x%02x%02x", 
        math.floor(r * 255), 
        math.floor(g * 255), 
        math.floor(b * 255))
    return WrapTextInColorCode(text, colorHex)
end

-- ============================================================================
-- NUMBER FORMATTING
-- ============================================================================

-- Abbreviate numbers (handles secrets)
function SecretAPI:AbbreviateNumbers(value)
    return AbbreviateNumbers(value)
end

-- Abbreviate large numbers (handles secrets)  
function SecretAPI:AbbreviateLargeNumbers(value)
    return AbbreviateLargeNumbers(value)
end

-- ============================================================================
-- BOOLEAN HELPERS
-- ============================================================================

-- Apply secret boolean to region alpha
function SecretAPI:ApplyBooleanAlpha(region, boolValue, alphaIfTrue, alphaIfFalse)
    if not region then return end
    alphaIfTrue = alphaIfTrue or 1.0
    alphaIfFalse = alphaIfFalse or 0.0
    region:SetAlphaFromBoolean(boolValue, alphaIfTrue, alphaIfFalse)
end

-- Apply secret boolean to cooldown shown state
function SecretAPI:ApplyBooleanShown(cooldownFrame, boolValue)
    if not cooldownFrame then return end
    if cooldownFrame.SetShownFromBoolean then
        cooldownFrame:SetShownFromBoolean(boolValue)
    end
end

-- Apply secret boolean to texture/fontstring vertex color
function SecretAPI:ApplyBooleanVertexColor(object, boolValue, trueColor, falseColor)
    if not object or not object.SetVertexColorFromBoolean then return end
    
    trueColor = trueColor or {r = 1, g = 1, b = 1}
    falseColor = falseColor or {r = 0.5, g = 0.5, b = 0.5}
    
    -- Create a color curve for the boolean
    local colorCurve = C_CurveUtil.CreateColorCurve()
    colorCurve:AddColorStop(0, CreateColor(falseColor.r, falseColor.g, falseColor.b, 1))
    colorCurve:AddColorStop(1, CreateColor(trueColor.r, trueColor.g, trueColor.b, 1))
    
    object:SetVertexColorFromBoolean(boolValue, colorCurve)
end

-- ============================================================================
-- COLOR CURVE BOOLEAN CONVERSION
-- ============================================================================

-- Evaluate boolean with color curve
function SecretAPI:EvaluateColorFromBoolean(boolValue, colorCurve)
    return C_CurveUtil.EvaluateColorFromBoolean(boolValue, colorCurve)
end

-- Evaluate boolean with color curve, return single value
function SecretAPI:EvaluateColorValueFromBoolean(boolValue, colorCurve)
    return C_CurveUtil.EvaluateColorValueFromBoolean(boolValue, colorCurve)
end

-- ============================================================================
-- SAFE VALUE ACCESS
-- ============================================================================

-- Get value with fallback if secret
function SecretAPI:GetValueOrFallback(value, fallback)
    if self:IsSecret(value) then
        return fallback
    end
    return value
end

-- Format a potentially secret number for display
function SecretAPI:FormatSecretNumber(value, fallback)
    if self:IsSecret(value) then
        return fallback or "?"
    end
    return tostring(value)
end

-- Format secret time value
function SecretAPI:FormatSecretTime(seconds, fallback)
    if self:IsSecret(seconds) then
        return self:TruncateWhenZero(seconds)
    end
    
    if not seconds or seconds <= 0 then
        return fallback or ""
    elseif seconds < 2 then
        return string.format("%.1f", seconds)
    elseif seconds < 60 then
        return string.format("%d", math.floor(seconds))
    elseif seconds < 3600 then
        return string.format("%dm", math.floor(seconds / 60))
    else
        return string.format("%dh", math.floor(seconds / 3600))
    end
end

-- ============================================================================
-- TABLE UTILITIES FOR SECRETS
-- ============================================================================

-- Safely iterate a table that might contain secrets
-- Returns key, value, isSecret for each item
function SecretAPI:SafePairs(tbl)
    if type(tbl) ~= "table" then
        return function() return nil end
    end
    
    local key = nil
    return function()
        local value
        key, value = next(tbl, key)
        if key ~= nil then
            return key, value, self:IsSecret(value)
        end
        return nil
    end
end

-- Count items in a table, handling potential secret length
function SecretAPI:SafeCount(tbl)
    if type(tbl) ~= "table" then return 0 end
    
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- ============================================================================
-- DEBUG
-- ============================================================================

-- Print secret status of a value
function SecretAPI:DebugValue(name, value)
    local isSecret = self:IsSecret(value)
    local typeStr = type(value)
    
    if isSecret then
        print(string.format("|cff888888[Secret Debug]|r %s: |cffff0000SECRET|r (%s)", name, typeStr))
    else
        print(string.format("|cff888888[Secret Debug]|r %s: |cff00ff00%s|r (%s)", name, tostring(value), typeStr))
    end
end

return SecretAPI
