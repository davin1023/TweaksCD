-- ============================================================================
-- TweaksUI: GlobalScale
-- Handles scaling of settings panels for different monitor sizes
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.GlobalScale = TUICD.GlobalScale or {}
local GS = TUICD.GlobalScale

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local MIN_SCALE = 0.5
local MAX_SCALE = 2.0
local DEFAULT_SCALE = 1.0

-- ============================================================================
-- STATE
-- ============================================================================

local registeredSettingsPanels = {}
local globalSettingsScale = DEFAULT_SCALE

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function GS:Initialize()
    -- Load saved settings scale
    if TUICD.Database and TUICD.Database.charDb then
        globalSettingsScale = TUICD.Database.charDb.globalSettingsScale or DEFAULT_SCALE
    end
end

-- ============================================================================
-- SETTINGS PANEL SCALING
-- ============================================================================

function GS:RegisterSettingsPanel(panel, baseScale)
    if not panel then return end
    
    baseScale = baseScale or 1.0
    registeredSettingsPanels[panel] = {
        baseScale = baseScale,
    }
    
    -- Apply current settings scale
    panel:SetScale(baseScale * globalSettingsScale)
end

function GS:UnregisterSettingsPanel(panel)
    if panel then
        registeredSettingsPanels[panel] = nil
    end
end

function GS:GetSettingsScale()
    return globalSettingsScale
end

function GS:SetSettingsScale(scale)
    scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
    globalSettingsScale = scale
    
    -- Save to database
    if TUICD.Database and TUICD.Database.charDb then
        TUICD.Database.charDb.globalSettingsScale = scale
    end
    
    -- Apply to all registered panels
    for panel, info in pairs(registeredSettingsPanels) do
        if panel and panel.SetScale then
            panel:SetScale(info.baseScale * scale)
        end
    end
    
    return scale
end

function GS:ApplySettingsScale()
    for panel, info in pairs(registeredSettingsPanels) do
        if panel and panel.SetScale then
            panel:SetScale(info.baseScale * globalSettingsScale)
        end
    end
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_TUISCALE1 = "/tuiscale"
SlashCmdList["TUISCALE"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word:lower())
    end
    
    local cmd = args[1]
    local value = tonumber(args[2])
    
    if cmd == "settings" or cmd == "s" then
        if value then
            local newScale = GS:SetSettingsScale(value)
            TUICD:Print(string.format("Settings scale set to: %.0f%%", newScale * 100))
        else
            TUICD:Print(string.format("Current settings scale: %.0f%%", GS:GetSettingsScale() * 100))
        end
    elseif cmd == "reset" then
        GS:SetSettingsScale(1.0)
        TUICD:Print("Settings scale reset to 100%")
    else
        print("|cffffd100TweaksUI Scale Commands:|r")
        print("  /tuiscale settings [value] - Get/set settings panel scale (0.5-2.0)")
        print("  /tuiscale reset - Reset settings scale to 100%")
    end
end

return GS
