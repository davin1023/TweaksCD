-- TweaksUI: Cooldowns - Utilities
-- Common utility functions used across modules

local ADDON_NAME, TUICD = ...

TUICD.Utilities = {}
local Utils = TUICD.Utilities

-- Safe call wrapper (handles combat lockdown and errors)
function Utils:SafeCall(func, ...)
    local success, err = pcall(func, ...)
    if not success then
        TUICD:PrintError("Error: " .. tostring(err))
    end
    return success, err
end

-- Defer execution until out of combat
local combatQueue = {}
local combatFrame = CreateFrame("Frame")

function Utils:AfterCombat(func)
    if InCombatLockdown() then
        table.insert(combatQueue, func)
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        func()
    end
end

combatFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        for _, func in ipairs(combatQueue) do
            Utils:SafeCall(func)
        end
        wipe(combatQueue)
    end
end)

-- Throttle function execution
function Utils:Throttle(func, delay)
    local lastCall = 0
    return function(...)
        local now = GetTime()
        if now - lastCall >= delay then
            lastCall = now
            return func(...)
        end
    end
end

-- Debounce function execution
function Utils:Debounce(func, delay)
    local timer = nil
    return function(...)
        local args = {...}
        if timer then
            timer:Cancel()
        end
        timer = C_Timer.NewTimer(delay, function()
            func(unpack(args))
            timer = nil
        end)
    end
end

-- Deep copy a table
function Utils:DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[Utils:DeepCopy(k)] = Utils:DeepCopy(v)
        end
        setmetatable(copy, Utils:DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Merge tables (source into target)
function Utils:MergeTables(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            Utils:MergeTables(target[k], v)
        else
            target[k] = v
        end
    end
    return target
end

-- Format number with commas
function Utils:FormatNumber(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(num)
    end
end

-- Format time (seconds to MM:SS or SS)
function Utils:FormatTime(seconds)
    if seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
    elseif seconds >= 10 then
        return string.format("%d", seconds)
    else
        return string.format("%.1f", seconds)
    end
end

-- Get class color
function Utils:GetClassColor(class)
    local color = RAID_CLASS_COLORS[class]
    if color then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

-- Get unit class color
function Utils:GetUnitClassColor(unit)
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class then
            return Utils:GetClassColor(class)
        end
    end
    return 1, 1, 1
end

-- Get reaction color
function Utils:GetReactionColor(unit)
    local reaction = UnitReaction(unit, "player")
    if reaction then
        if reaction >= 5 then
            return 0, 1, 0 -- Friendly
        elseif reaction == 4 then
            return 1, 1, 0 -- Neutral
        else
            return 1, 0, 0 -- Hostile
        end
    end
    return 1, 1, 1
end

-- Create a color string
function Utils:ColorText(text, r, g, b)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

-- RGB hex to color values
function Utils:HexToRGB(hex)
    hex = hex:gsub("#", "")
    return tonumber("0x" .. hex:sub(1, 2)) / 255,
           tonumber("0x" .. hex:sub(3, 4)) / 255,
           tonumber("0x" .. hex:sub(5, 6)) / 255
end

-- RGB to hex
function Utils:RGBToHex(r, g, b)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- ============================================================================
-- UI HELPER: SLIDER WITH NUMERIC INPUT
-- ============================================================================

-- Create a slider with an editable numeric input field
-- This replaces the standard value display with an EditBox that allows direct input
-- Parameters:
--   parent: Parent frame to attach to
--   options: {
--       label = "Label Text",         -- Optional label text
--       min = 0,                       -- Minimum value
--       max = 100,                     -- Maximum value
--       step = 1,                      -- Step increment
--       value = 50,                    -- Initial value
--       isFloat = false,               -- If true, shows decimals
--       decimals = 2,                  -- Number of decimal places (if isFloat)
--       width = 140,                   -- Slider width
--       labelWidth = 85,               -- Label width (if label provided)
--       valueWidth = 45,               -- Value input width
--       onValueChanged = function(value) end,  -- Callback when value changes
--   }
-- Returns: container frame, slider, valueBox
function Utils:CreateSliderWithInput(parent, options)
    options = options or {}
    
    local min = options.min or 0
    local max = options.max or 100
    local step = options.step or 1
    local initialValue = options.value or min
    local isFloat = options.isFloat or false
    local decimals = options.decimals or 2
    local sliderWidth = options.width or 140
    local labelWidth = options.labelWidth or 85
    local valueWidth = options.valueWidth or 45
    local callback = options.onValueChanged
    
    -- Create container
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(20)
    
    local currentX = 0
    
    -- Create label if provided
    if options.label then
        local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 0, 0)
        label:SetText(options.label)
        label:SetWidth(labelWidth)
        label:SetJustifyH("LEFT")
        container.label = label
        currentX = labelWidth + 3
    end
    
    -- Create slider
    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", currentX, 0)
    slider:SetSize(sliderWidth, 16)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(initialValue)
    slider.Low:SetText("")
    slider.High:SetText("")
    slider.Text:SetText("")  -- Hide default text
    
    currentX = currentX + sliderWidth + 6
    
    -- Create value EditBox
    local valueBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    valueBox:SetPoint("LEFT", currentX, 0)
    valueBox:SetSize(valueWidth, 18)
    valueBox:SetAutoFocus(false)
    valueBox:SetJustifyH("CENTER")
    valueBox:SetFontObject("GameFontHighlightSmall")
    
    -- Format function
    local function FormatValue(value)
        if isFloat then
            return string.format("%." .. decimals .. "f", value)
        else
            return string.format("%.0f", value)
        end
    end
    
    -- Set initial value text
    valueBox:SetText(FormatValue(initialValue))
    
    -- Calculate container width
    container:SetWidth(currentX + valueWidth)
    
    -- Flag to prevent recursive updates
    local isUpdating = false
    
    -- Slider updates EditBox
    slider:SetScript("OnValueChanged", function(self, value)
        if isUpdating then return end
        isUpdating = true
        
        -- Snap to step
        value = math.floor(value / step + 0.5) * step
        
        -- Clamp
        value = math.max(min, math.min(max, value))
        
        valueBox:SetText(FormatValue(value))
        
        if callback then
            callback(value)
        end
        
        isUpdating = false
    end)
    
    -- EditBox updates Slider on Enter
    valueBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        local value = tonumber(text)
        
        if value then
            -- Clamp to range
            value = math.max(min, math.min(max, value))
            
            -- Snap to step
            value = math.floor(value / step + 0.5) * step
            
            isUpdating = true
            slider:SetValue(value)
            self:SetText(FormatValue(value))
            isUpdating = false
            
            if callback then
                callback(value)
            end
        else
            -- Invalid input, revert to slider value
            self:SetText(FormatValue(slider:GetValue()))
        end
        
        self:ClearFocus()
    end)
    
    -- Revert on Escape
    valueBox:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(slider:GetValue()))
        self:ClearFocus()
    end)
    
    -- Also update on focus lost (tab away)
    valueBox:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText()
        local value = tonumber(text)
        
        if value then
            value = math.max(min, math.min(max, value))
            value = math.floor(value / step + 0.5) * step
            
            if math.abs(value - slider:GetValue()) > 0.001 then
                isUpdating = true
                slider:SetValue(value)
                isUpdating = false
                
                if callback then
                    callback(value)
                end
            end
            
            self:SetText(FormatValue(value))
        else
            self:SetText(FormatValue(slider:GetValue()))
        end
    end)
    
    -- Store references
    container.slider = slider
    container.valueBox = valueBox
    
    -- Helper to update value programmatically
    function container:SetValue(value)
        isUpdating = true
        slider:SetValue(value)
        valueBox:SetText(FormatValue(value))
        isUpdating = false
    end
    
    function container:GetValue()
        return slider:GetValue()
    end
    
    function container:SetEnabled(enabled)
        if enabled then
            slider:Enable()
            valueBox:Enable()
            if container.label then
                container.label:SetTextColor(1, 1, 1)
            end
        else
            slider:Disable()
            valueBox:Disable()
            if container.label then
                container.label:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end
    
    return container, slider, valueBox
end

-- Check if in combat
function Utils:InCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

-- Get current spec ID
function Utils:GetSpecID()
    local specIndex = GetSpecialization()
    if specIndex then
        return GetSpecializationInfo(specIndex)
    end
    return nil
end

-- Round number
function Utils:Round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Clamp number
function Utils:Clamp(num, min, max)
    return math.max(min, math.min(max, num))
end

-- Linear interpolation
function Utils:Lerp(a, b, t)
    return a + (b - a) * t
end

-- Create frame with backdrop
function Utils:CreateBackdropFrame(parent, name, template)
    local frame = CreateFrame("Frame", name, parent, template or "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    return frame
end

-- Hook function safely
function Utils:SecureHook(object, method, hookFunc)
    if type(object) == "string" then
        -- Global function
        hooksecurefunc(object, method)
    else
        -- Object method
        hooksecurefunc(object, method, hookFunc)
    end
end

-- ============================================================================
-- MIDNIGHT API COMPATIBILITY LAYER
-- ============================================================================
-- Provides wrapper functions for Duration Object APIs introduced in Midnight.
-- These helpers detect API availability at runtime and use the correct method,
-- ensuring TweaksUI works on both Live (11.x) and Midnight without Lua errors.
--
-- REMOVED APIs (will cause errors in Midnight):
--   C_Spell.GetSpellCooldownRemaining / GetSpellCooldownRemainingPercent
--   C_ActionBar.GetActionCooldownRemaining / GetActionCooldownRemainingPercent
--   C_UnitAuras.GetAuraDurationRemaining / GetAuraDurationRemainingPercent
--
-- REPLACEMENT APIs (Duration Objects):
--   C_Spell.GetSpellCooldownDuration() -> duration:EvaluateRemainingDuration()
--   C_ActionBar.GetActionCooldownDuration() -> duration:EvaluateRemainingDuration()
--   C_UnitAuras.GetUnitAuraDuration() -> duration:GetRemainingDuration()
-- ============================================================================

TUICD.API = TUICD.API or {}

-- -----------------------------------------------------------------------------
-- Feature Detection Flags
-- -----------------------------------------------------------------------------
-- These flags are evaluated once at load time to determine which API set is available
-- Based on Midnight PTR 2 (December 2025) API structure

-- Spell/Action cooldown Duration Objects (Midnight+)
-- Returns Duration Object with :GetRemainingDuration(), :GetElapsedDuration(), etc.
TUICD.API.HAS_DURATION_OBJECTS = C_Spell and C_Spell.GetSpellCooldownDuration ~= nil

-- Aura Duration Objects (Midnight+)
-- NOTE: The API is C_UnitAuras.GetAuraDuration (NOT GetUnitAuraDuration)
TUICD.API.HAS_AURA_DURATION_OBJECTS = C_UnitAuras and C_UnitAuras.GetAuraDuration ~= nil

-- Duration Object creation utility (Midnight+)
TUICD.API.HAS_DURATION_UTIL = C_DurationUtil and C_DurationUtil.CreateDuration ~= nil

-- CastBarID in UnitCastingInfo/UnitChannelInfo return values (Midnight PTR 2+)
-- Can't reliably test at load time (player may not be casting), so use proxy detection
-- If we have Duration Objects, we're on Midnight and castBarID should be available
TUICD.API.HAS_CASTBAR_ID = TUICD.API.HAS_DURATION_OBJECTS

-- Empowered cast stage APIs (non-secret in Midnight PTR 2+)
-- UnitEmpoweredStagePercentages returns non-secret percentages for each stage
TUICD.API.HAS_EMPOWERED_APIS = UnitEmpoweredStagePercentages ~= nil

-- Self-updating timer bars (StatusBar:SetTimerDuration)
-- NOTE: The API is SetTimerDuration (NOT SetTimer)
TUICD.API.HAS_TIMER_BARS = (function()
    local testBar = CreateFrame("StatusBar")
    local hasAPI = testBar.SetTimerDuration ~= nil
    return hasAPI
end)()

-- Secrecy testing APIs (Midnight PTR 2+)
-- GetSpellAuraSecrecy, GetSpellCooldownSecrecy, GetSpellCastSecrecy, GetPowerTypeSecrecy
TUICD.API.HAS_SECRECY_APIS = GetSpellAuraSecrecy ~= nil

-- -----------------------------------------------------------------------------
-- Spell Cooldown Helpers
-- -----------------------------------------------------------------------------

-- Get remaining cooldown time for a spell
-- @param spellID number - The spell ID to check
-- @return number - Remaining cooldown in seconds (0 if not on cooldown)
function TUICD.API.GetSpellCooldownRemaining(spellID)
    if not spellID then return 0 end
    
    -- New API (Midnight+): Duration Objects
    if TUICD.API.HAS_DURATION_OBJECTS then
        local duration = C_Spell.GetSpellCooldownDuration(spellID)
        if duration and duration.GetRemainingDuration then
            return duration:GetRemainingDuration() or 0
        end
        return 0
    end
    
    -- Fallback (Live 11.x): Calculate from cooldown info
    local info = C_Spell.GetSpellCooldown(spellID)
    if info and info.startTime and info.duration and info.duration > 0 then
        local remaining = (info.startTime + info.duration) - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 0
end

-- Set a cooldown frame from a spell's cooldown
-- @param cooldown CooldownFrame - The cooldown frame to update
-- @param spellID number - The spell ID
-- @return boolean - True if cooldown was set successfully
function TUICD.API.SetCooldownFromSpell(cooldown, spellID)
    if not cooldown or not spellID then return false end
    
    -- New API (Midnight+): Use Duration Object directly
    if TUICD.API.HAS_DURATION_OBJECTS then
        local duration = C_Spell.GetSpellCooldownDuration(spellID)
        if duration then
            cooldown:SetCooldownFromDurationObject(duration)
            return true
        end
        return false
    end
    
    -- Fallback (Live 11.x): Use start time and duration
    local info = C_Spell.GetSpellCooldown(spellID)
    if info and info.startTime and info.duration then
        cooldown:SetCooldown(info.startTime, info.duration)
        return true
    end
    return false
end

-- -----------------------------------------------------------------------------
-- Aura Duration Helpers
-- -----------------------------------------------------------------------------

-- Get remaining duration for an aura
-- @param unit string - Unit token (e.g., "player", "target")
-- @param auraInstanceID number - The aura instance ID
-- @return number - Remaining duration in seconds (0 if expired or no duration)
function TUICD.API.GetAuraDurationRemaining(unit, auraInstanceID)
    if not unit or not auraInstanceID then return 0 end
    
    -- New API (Midnight+): Duration Objects
    -- NOTE: API is C_UnitAuras.GetAuraDuration (NOT GetUnitAuraDuration)
    if TUICD.API.HAS_AURA_DURATION_OBJECTS then
        local duration = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
        if duration and duration.GetRemainingDuration then
            return duration:GetRemainingDuration() or 0
        end
        return 0
    end
    
    -- Fallback (Live 11.x): Calculate from aura data
    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if aura and aura.expirationTime and aura.expirationTime > 0 then
        local remaining = aura.expirationTime - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 0
end

-- Set a cooldown frame from an aura's duration
-- @param cooldown CooldownFrame - The cooldown frame to update
-- @param unit string - Unit token
-- @param auraInstanceID number - The aura instance ID
-- @return boolean - True if cooldown was set successfully
function TUICD.API.SetCooldownFromAura(cooldown, unit, auraInstanceID)
    if not cooldown or not unit or not auraInstanceID then return false end
    
    -- New API (Midnight+): Use Duration Object directly
    -- NOTE: API is C_UnitAuras.GetAuraDuration (NOT GetUnitAuraDuration)
    if TUICD.API.HAS_AURA_DURATION_OBJECTS then
        local duration = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
        if duration then
            -- Second param = true indicates this is an aura (counts down)
            cooldown:SetCooldownFromDurationObject(duration, true)
            return true
        end
        return false
    end
    
    -- Fallback (Live 11.x): Calculate start time from expiration
    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if aura and aura.duration and aura.duration > 0 and aura.expirationTime then
        local startTime = aura.expirationTime - aura.duration
        cooldown:SetCooldown(startTime, aura.duration)
        return true
    end
    return false
end

-- Get aura duration remaining using AuraData directly (alternative method)
-- Useful when you already have the aura data table
-- @param auraData table - AuraData from GetAuraDataByAuraInstanceID or similar
-- @return number - Remaining duration in seconds
function TUICD.API.GetAuraDurationFromData(auraData)
    if not auraData then return 0 end
    
    -- If the aura has no duration (permanent), return 0
    if not auraData.duration or auraData.duration == 0 then
        return 0
    end
    
    -- Calculate remaining from expiration time
    if auraData.expirationTime and auraData.expirationTime > 0 then
        local remaining = auraData.expirationTime - GetTime()
        return remaining > 0 and remaining or 0
    end
    
    return 0
end

-- -----------------------------------------------------------------------------
-- Action Bar Cooldown Helpers
-- -----------------------------------------------------------------------------

-- Get remaining cooldown for an action bar slot
-- @param slot number - Action bar slot (1-120)
-- @return number - Remaining cooldown in seconds (0 if not on cooldown)
function TUICD.API.GetActionCooldownRemaining(slot)
    if not slot then return 0 end
    
    -- New API (Midnight+): Duration Objects
    if TUICD.API.HAS_DURATION_OBJECTS then
        local duration = C_ActionBar.GetActionCooldownDuration(slot)
        if duration and duration.GetRemainingDuration then
            return duration:GetRemainingDuration() or 0
        end
        return 0
    end
    
    -- Fallback (Live 11.x): Use GetActionCooldown
    local start, duration = GetActionCooldown(slot)
    if start and duration and duration > 0 then
        local remaining = (start + duration) - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 0
end

-- Set a cooldown frame from an action slot's cooldown
-- @param cooldown CooldownFrame - The cooldown frame to update
-- @param slot number - Action bar slot
-- @return boolean - True if cooldown was set successfully
function TUICD.API.SetCooldownFromAction(cooldown, slot)
    if not cooldown or not slot then return false end
    
    -- New API (Midnight+): Use Duration Object directly
    if TUICD.API.HAS_DURATION_OBJECTS then
        local duration = C_ActionBar.GetActionCooldownDuration(slot)
        if duration then
            cooldown:SetCooldownFromDurationObject(duration)
            return true
        end
        return false
    end
    
    -- Fallback (Live 11.x): Use start time and duration
    local start, duration = GetActionCooldown(slot)
    if start and duration then
        cooldown:SetCooldown(start, duration)
        return true
    end
    return false
end

-- -----------------------------------------------------------------------------
-- Secrecy API Helpers (Midnight+)
-- -----------------------------------------------------------------------------

-- Check if an aura's timing data is secret
-- @param spellID number - The spell ID to check
-- @return string|nil - "AlwaysSecret", "NeverSecret", "ContextuallySecret", or nil if API unavailable
function TUICD.API.GetAuraSecrecy(spellID)
    if not TUICD.API.HAS_SECRECY_APIS or not spellID then
        return nil
    end
    return GetSpellAuraSecrecy(spellID)
end

-- Check if a cooldown's timing data is secret
-- @param spellID number - The spell ID to check
-- @return string|nil - "AlwaysSecret", "NeverSecret", "ContextuallySecret", or nil if API unavailable
function TUICD.API.GetCooldownSecrecy(spellID)
    if not TUICD.API.HAS_SECRECY_APIS or not spellID then
        return nil
    end
    return GetSpellCooldownSecrecy(spellID)
end

-- Check if timing data might be restricted in the current context
-- @param spellID number - The spell ID to check
-- @return boolean - True if data might be secret, false if definitely available
function TUICD.API.MightBeSecret(spellID)
    if not TUICD.API.HAS_SECRECY_APIS then
        return false -- Pre-Midnight, nothing is secret
    end
    
    local auraSecrecy = GetSpellAuraSecrecy(spellID)
    local cdSecrecy = GetSpellCooldownSecrecy(spellID)
    
    -- If either is not "NeverSecret", it might be restricted
    return (auraSecrecy and auraSecrecy ~= "NeverSecret") or 
           (cdSecrecy and cdSecrecy ~= "NeverSecret")
end

-- -----------------------------------------------------------------------------
-- Debug/Diagnostic Helpers
-- -----------------------------------------------------------------------------

-- Print API availability status (useful for debugging)
function TUICD.API.PrintStatus()
    local status = {
        "TweaksUI API Compatibility Status:",
        "  Duration Objects (Cooldowns): " .. (TUICD.API.HAS_DURATION_OBJECTS and "YES" or "NO"),
        "  Duration Objects (Auras): " .. (TUICD.API.HAS_AURA_DURATION_OBJECTS and "YES" or "NO"),
        "  Duration Util (CreateDuration): " .. (TUICD.API.HAS_DURATION_UTIL and "YES" or "NO"),
        "  CastBarID Available: " .. (TUICD.API.HAS_CASTBAR_ID and "YES" or "NO"),
        "  Empowered Stage APIs: " .. (TUICD.API.HAS_EMPOWERED_APIS and "YES" or "NO"),
        "  Timer Bar APIs (SetTimerDuration): " .. (TUICD.API.HAS_TIMER_BARS and "YES" or "NO"),
        "  Secrecy APIs: " .. (TUICD.API.HAS_SECRECY_APIS and "YES" or "NO"),
    }
    
    for _, line in ipairs(status) do
        print(line)
    end
end
