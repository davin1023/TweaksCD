-- ============================================================================
-- TUICD: Curve API Wrapper
-- Midnight curve and color curve utilities
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.CurveAPI = TUICD.CurveAPI or {}
local CurveAPI = TUICD.CurveAPI

-- ============================================================================
-- CURVE CREATION
-- ============================================================================

-- Create a numeric curve
function CurveAPI:Create()
    return C_CurveUtil.CreateCurve()
end

-- Create a color curve
function CurveAPI:CreateColorCurve()
    return C_CurveUtil.CreateColorCurve()
end

-- ============================================================================
-- PRESET CURVES (from CurveConstants.lua)
-- ============================================================================

-- These will be populated after the game loads CurveConstants
CurveAPI.PRESETS = {
    ScaleTo100 = nil,    -- Scales 0-1 to 0-100
    Reverse = nil,       -- Reverses 0-1 to 1-0
    ReverseTo100 = nil,  -- Reverses and scales to 100
}

-- Initialize presets when available
local function InitializePresets()
    if CurveConstants then
        CurveAPI.PRESETS.ScaleTo100 = CurveConstants.ScaleTo100
        CurveAPI.PRESETS.Reverse = CurveConstants.Reverse
        CurveAPI.PRESETS.ReverseTo100 = CurveConstants.ReverseTo100
    end
end

-- Try to initialize immediately
InitializePresets()

-- Also try after ADDON_LOADED
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if addon == "Blizzard_UIParent" or addon == ADDON_NAME then
        InitializePresets()
    end
end)

-- ============================================================================
-- CURVE BUILDING HELPERS
-- ============================================================================

-- Build a simple linear curve from min to max
function CurveAPI:CreateLinear(minValue, maxValue)
    local curve = self:Create()
    curve:AddPoint(0, minValue)
    curve:AddPoint(1, maxValue)
    return curve
end

-- Build a curve that scales to percentage (0-100)
function CurveAPI:CreatePercentCurve()
    local curve = self:Create()
    curve:AddPoint(0, 0)
    curve:AddPoint(1, 100)
    return curve
end

-- Build a reverse curve (1 -> 0)
function CurveAPI:CreateReverseCurve()
    local curve = self:Create()
    curve:AddPoint(0, 1)
    curve:AddPoint(1, 0)
    return curve
end

-- ============================================================================
-- COLOR CURVE BUILDING HELPERS
-- ============================================================================

-- Build a health color curve (red -> yellow -> green)
function CurveAPI:CreateHealthColorCurve(lowColor, midColor, highColor)
    lowColor = lowColor or CreateColor(1, 0, 0, 1)      -- Red
    midColor = midColor or CreateColor(1, 1, 0, 1)      -- Yellow
    highColor = highColor or CreateColor(0, 1, 0, 1)    -- Green
    
    local curve = self:CreateColorCurve()
    curve:AddColorStop(0, lowColor)
    curve:AddColorStop(0.5, midColor)
    curve:AddColorStop(1, highColor)
    return curve
end

-- Build a mana/power color curve (empty -> full)
function CurveAPI:CreatePowerColorCurve(emptyColor, fullColor)
    emptyColor = emptyColor or CreateColor(0.2, 0.2, 0.8, 1)  -- Dark blue
    fullColor = fullColor or CreateColor(0, 0.5, 1, 1)        -- Bright blue
    
    local curve = self:CreateColorCurve()
    curve:AddColorStop(0, emptyColor)
    curve:AddColorStop(1, fullColor)
    return curve
end

-- Build a cooldown color curve (ready -> on cooldown)
function CurveAPI:CreateCooldownColorCurve(readyColor, almostReadyColor, cooldownColor)
    readyColor = readyColor or CreateColor(1, 1, 1, 1)           -- White (ready)
    almostReadyColor = almostReadyColor or CreateColor(0, 1, 0, 1) -- Green (almost ready)
    cooldownColor = cooldownColor or CreateColor(1, 0, 0, 1)      -- Red (on CD)
    
    local curve = self:CreateColorCurve()
    curve:AddColorStop(0, readyColor)
    curve:AddColorStop(0.1, almostReadyColor)
    curve:AddColorStop(1, cooldownColor)
    return curve
end

-- Build an urgency color curve (safe -> danger)
function CurveAPI:CreateUrgencyColorCurve()
    local curve = self:CreateColorCurve()
    curve:AddColorStop(0, CreateColor(0.5, 0.5, 0.5, 1))  -- Grey (safe)
    curve:AddColorStop(0.5, CreateColor(1, 1, 0, 1))       -- Yellow (caution)
    curve:AddColorStop(0.8, CreateColor(1, 0.5, 0, 1))     -- Orange (warning)
    curve:AddColorStop(1, CreateColor(1, 0, 0, 1))         -- Red (danger)
    return curve
end

-- Build a simple two-color curve
function CurveAPI:CreateTwoColorCurve(color1, color2)
    local curve = self:CreateColorCurve()
    curve:AddColorStop(0, color1)
    curve:AddColorStop(1, color2)
    return curve
end

-- ============================================================================
-- DISPEL TYPE COLOR CURVES
-- ============================================================================

-- Cache for dispel type color curves
local dispelColorCurves = {}

-- Get or create dispel type color curve
function CurveAPI:GetDispelTypeColorCurve()
    if not dispelColorCurves.dispel then
        local curve = self:CreateColorCurve()
        -- Map dispel types to colors
        -- 0 = none (grey)
        -- 1 = magic (blue)
        -- 2 = curse (purple)
        -- 3 = disease (brown)
        -- 4 = poison (green)
        curve:AddColorStop(0, CreateColor(0.5, 0.5, 0.5, 1))   -- None
        curve:AddColorStop(0.25, CreateColor(0.2, 0.6, 1, 1))   -- Magic
        curve:AddColorStop(0.5, CreateColor(0.6, 0.2, 0.8, 1))  -- Curse
        curve:AddColorStop(0.75, CreateColor(0.6, 0.4, 0.2, 1)) -- Disease
        curve:AddColorStop(1, CreateColor(0, 0.8, 0.2, 1))      -- Poison
        dispelColorCurves.dispel = curve
    end
    return dispelColorCurves.dispel
end

-- ============================================================================
-- CURVE EVALUATION
-- ============================================================================

-- Evaluate a curve at a specific point
function CurveAPI:Evaluate(curve, value)
    if not curve then return value end
    return curve:Evaluate(value)
end

-- Evaluate a color curve at a specific point
function CurveAPI:EvaluateColor(colorCurve, value)
    if not colorCurve then return nil end
    return colorCurve:Evaluate(value)
end

-- ============================================================================
-- BOOLEAN TO COLOR CONVERSION
-- ============================================================================

-- Evaluate color from boolean
function CurveAPI:EvaluateColorFromBoolean(boolValue, colorCurve)
    return C_CurveUtil.EvaluateColorFromBoolean(boolValue, colorCurve)
end

-- Evaluate single color value from boolean
function CurveAPI:EvaluateColorValueFromBoolean(boolValue, colorCurve)
    return C_CurveUtil.EvaluateColorValueFromBoolean(boolValue, colorCurve)
end

-- Create a boolean color curve (false = color1, true = color2)
function CurveAPI:CreateBooleanColorCurve(falseColor, trueColor)
    falseColor = falseColor or CreateColor(0.5, 0.5, 0.5, 1)
    trueColor = trueColor or CreateColor(1, 1, 1, 1)
    
    local curve = self:CreateColorCurve()
    curve:AddColorStop(0, falseColor)
    curve:AddColorStop(1, trueColor)
    return curve
end

-- ============================================================================
-- CACHED CURVES
-- ============================================================================

-- Pre-built curves for common use cases
CurveAPI.COMMON = {
    healthColor = nil,
    cooldownColor = nil,
    urgencyColor = nil,
}

-- Get or create common health color curve
function CurveAPI:GetHealthColorCurve()
    if not self.COMMON.healthColor then
        self.COMMON.healthColor = self:CreateHealthColorCurve()
    end
    return self.COMMON.healthColor
end

-- Get or create common cooldown color curve
function CurveAPI:GetCooldownColorCurve()
    if not self.COMMON.cooldownColor then
        self.COMMON.cooldownColor = self:CreateCooldownColorCurve()
    end
    return self.COMMON.cooldownColor
end

-- Get or create common urgency color curve
function CurveAPI:GetUrgencyColorCurve()
    if not self.COMMON.urgencyColor then
        self.COMMON.urgencyColor = self:CreateUrgencyColorCurve()
    end
    return self.COMMON.urgencyColor
end

-- ============================================================================
-- CLASS POWER COLORS
-- ============================================================================

-- Create curve for class power colors
function CurveAPI:CreateClassPowerColorCurve(powerType)
    local colors = {
        [Enum.PowerType.Mana] = CreateColor(0, 0.5, 1, 1),
        [Enum.PowerType.Rage] = CreateColor(1, 0, 0, 1),
        [Enum.PowerType.Focus] = CreateColor(1, 0.5, 0.25, 1),
        [Enum.PowerType.Energy] = CreateColor(1, 1, 0, 1),
        [Enum.PowerType.ComboPoints] = CreateColor(1, 0.96, 0.41, 1),
        [Enum.PowerType.Runes] = CreateColor(0.5, 0.5, 0.5, 1),
        [Enum.PowerType.RunicPower] = CreateColor(0, 0.82, 1, 1),
        [Enum.PowerType.SoulShards] = CreateColor(0.5, 0.32, 0.55, 1),
        [Enum.PowerType.LunarPower] = CreateColor(0.3, 0.52, 0.9, 1),
        [Enum.PowerType.HolyPower] = CreateColor(0.95, 0.9, 0.6, 1),
        [Enum.PowerType.Maelstrom] = CreateColor(0, 0.5, 1, 1),
        [Enum.PowerType.Chi] = CreateColor(0.71, 1, 0.92, 1),
        [Enum.PowerType.Insanity] = CreateColor(0.4, 0, 0.8, 1),
        [Enum.PowerType.ArcaneCharges] = CreateColor(0.1, 0.1, 0.98, 1),
        [Enum.PowerType.Fury] = CreateColor(0.788, 0.259, 0.992, 1),
        [Enum.PowerType.Pain] = CreateColor(1, 0.612, 0, 1),
        [Enum.PowerType.Essence] = CreateColor(0.13, 0.55, 0.13, 1),
    }
    
    local color = colors[powerType] or CreateColor(1, 1, 1, 1)
    local darkColor = CreateColor(color.r * 0.3, color.g * 0.3, color.b * 0.3, 1)
    
    return self:CreateTwoColorCurve(darkColor, color)
end

return CurveAPI
