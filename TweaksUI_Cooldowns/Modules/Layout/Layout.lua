-- ============================================================================
-- TUICD: Layout Module
-- Custom positioning system using LibFlyPaper - replaces Edit Mode dependency
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- ============================================================================
-- MODULE SETUP
-- ============================================================================

local Layout = TUICD.ModuleManager:NewModule(
    "layout",
    "Layout",
    "Custom positioning system for TUICD elements"
)
TUICD.Layout = Layout

local TUIFrame = TUICD.TUIFrame
local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local ELEMENT_CATEGORIES = {
    -- TUI:CD categories
    COOLDOWNS = "Cooldowns",
    RESOURCE_BARS = "Resource Bars",
}
Layout.CATEGORIES = ELEMENT_CATEGORIES

-- ============================================================================
-- STATE
-- ============================================================================

local elementRegistry = {}  -- All registered positionable elements
local isLayoutModeActive = false
local selectedElementId = nil

-- ============================================================================
-- DEFAULT SETTINGS
-- ============================================================================

local DEFAULT_SETTINGS = {
    -- Data version - increment when coordinate system changes
    -- v1: Original coordinate system
    -- v2: CENTER-relative coordinates (1.6.2+)
    -- v3: Fixed cooldown tracker coords to CENTER (was still BOTTOMLEFT in v2)
    -- v4: Back to BOTTOMLEFT absolute (working)
    dataVersion = 4,
    -- Grid settings
    grid = {
        enabled = true,
        size = 32,
        showLines = true,
        snapToGrid = false,  -- If true, snap to grid instead of frames
    },
    -- Snapping settings
    snapping = {
        enabled = true,
        tolerance = 50,
        showIndicator = true,
    },
    -- Element positions (keyed by element ID)
    elements = {},
}

-- Deep copy utility
local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[DeepCopy(k)] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Merge defaults into settings (only adds missing keys)
local function EnsureDefaults(settings, defaults)
    for key, defaultValue in pairs(defaults) do
        if settings[key] == nil then
            if type(defaultValue) == "table" then
                settings[key] = DeepCopy(defaultValue)
            else
                settings[key] = defaultValue
            end
        elseif type(defaultValue) == "table" and type(settings[key]) == "table" then
            EnsureDefaults(settings[key], defaultValue)
        end
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Current data version - increment when coordinate system changes
-- v1: Original format
-- v2: CENTER-relative (broken, 1.6.2-beta)
-- v3: CENTER-relative attempt 2 (still broken)
-- v4: Back to BOTTOMLEFT absolute (working)
local CURRENT_DATA_VERSION = 4

function Layout:OnInitialize()
    -- Ensure default settings exist
    local settings = self:GetSettings()
    
    -- Check data version and migrate if needed
    local savedVersion = settings.dataVersion or 1
    
    if savedVersion < CURRENT_DATA_VERSION then
        -- Old data version - coordinate system was broken
        -- Clear Layout-managed positions to prevent frames appearing in wrong places
        print("|cffFFFF00TweaksUI:|r Layout data format updated. Resetting frame positions to defaults.")
        print("|cffFFFF00TweaksUI:|r Use /tui layout to reposition your frames.")
        
        -- Clear Layout element positions (this is the main thing that needs clearing)
        settings.elements = {}
        
        -- Clear related position data that uses the old coordinate system
        if TweaksUI_Cooldowns_CharDB then
            TweaksUI_Cooldowns_CharDB.cooldownContainerPositions = nil
            TweaksUI_Cooldowns_CharDB.actionBarContainerPositions = nil
            TweaksUI_Cooldowns_CharDB.uiFrameContainerPositions = nil
            TweaksUI_Cooldowns_CharDB.snapLocks = nil
            
            -- Clear minimap custom position (stored separately in General settings)
            if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.general then
                if TweaksUI_Cooldowns_CharDB.settings.general.minimap then
                    TweaksUI_Cooldowns_CharDB.settings.general.minimap.customPosition = nil
                end
            end
        end
        
        -- Update to current version
        settings.dataVersion = CURRENT_DATA_VERSION
        
        if TUICD.PrintDebug then
            TUICD:PrintDebug("Layout: Migrated from v" .. savedVersion .. " to v" .. CURRENT_DATA_VERSION)
        end
    end
    
    EnsureDefaults(settings, DEFAULT_SETTINGS)
end

function Layout:OnEnable()
    -- Note: Positions are loaded automatically when elements are registered via RegisterElement()
    -- But Blizzard EditMode and other systems may re-anchor frames AFTER we load.
    -- So we need to re-apply positions multiple times to "win last".
    
    -- STEP 1: Apply positions first (frames still hidden at alpha=0)
    -- This ensures frames are in correct position BEFORE they become visible
    C_Timer.After(3.0, function()
        self:ApplyAllPositions()
        if TUICD.debugMode then
            print("|cff00ff00TweaksUI:|r Layout positions applied (3.0s - pre-reveal)")
        end
    end)
    
    -- STEP 2: Reveal all TUIFrames AFTER positions are applied
    -- Small delay after position apply to ensure they've taken effect
    C_Timer.After(3.5, function()
        -- Apply positions one more time right before reveal
        self:ApplyAllPositions()
        
        -- Now reveal frames (this also applies visibility BEFORE revealing)
        if TUICD.TUIFrame and TUICD.TUIFrame.RevealAllFrames then
            TUICD.TUIFrame.RevealAllFrames()
        end
    end)
    
    -- STEP 3: Re-apply positions one more time for stubborn frames
    C_Timer.After(4.0, function()
        self:ApplyAllPositions()
        if TUICD.debugMode then
            print("|cff00ff00TweaksUI:|r Layout positions applied (4.0s - post-reveal)")
        end
    end)
    
    -- Also re-apply after a longer delay for stubborn frames
    C_Timer.After(5.0, function()
        self:ApplyAllPositions()
    end)
    
    -- Register for events that can cause Blizzard to reshuffle anchors
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UI_SCALE_CHANGED")
    eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    
    eventFrame:SetScript("OnEvent", function(self, event)
        -- Delay to let Blizzard finish its work first
        C_Timer.After(0.5, function()
            -- CRITICAL: Skip position updates if Edit Mode is still active
            -- This prevents taint during Edit Mode operations
            if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
                if TUICD.debugMode then
                    print("|cffFFFF00TweaksUI:|r Layout position update deferred - Edit Mode active")
                end
                return
            end
            
            Layout:ApplyAllPositions()
            if TUICD.debugMode then
                print("|cff00ff00TweaksUI:|r Layout positions re-applied after " .. event)
            end
        end)
    end)
    
    -- Register for combat event to auto-exit layout mode
    local combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" and isLayoutModeActive then
            print("|cffff0000TweaksUI:|r Exiting Layout Mode due to combat")
            Layout:Exit()
        end
    end)
end

function Layout:OnDisable()
    -- Exit layout mode if active
    if isLayoutModeActive then
        self:Exit()
    end
end

-- ============================================================================
-- ANCHOR MODE (Per-Element)
-- Allows switching between BOTTOMLEFT (default) and CENTER anchoring
-- CENTER mode makes frames expand/contract from their center when size changes
-- ============================================================================

function Layout:SetElementAnchorMode(id, mode)
    local element = elementRegistry[id]
    if not element or not element.tuiFrame then return end
    
    mode = mode or "BOTTOMLEFT"
    
    -- Try calling the method if it exists
    if element.tuiFrame.SetAnchorMode then
        element.tuiFrame:SetAnchorMode(mode)
    else
        -- Set the property directly if method doesn't exist
        element.tuiFrame.anchorMode = mode
    end
    
    -- Update saved data with anchor mode
    local settings = self:GetSettings()
    if not settings.elements[id] then
        settings.elements[id] = {}
    end
    settings.elements[id].anchorMode = mode
    
    if TUICD.debugMode then
        print("|cff00ff00TweaksUI:|r Set anchor mode for " .. id .. " to " .. mode)
    end
end

function Layout:GetElementAnchorMode(id)
    local element = elementRegistry[id]
    if not element or not element.tuiFrame then return "BOTTOMLEFT" end
    
    -- Try calling the method if it exists
    if element.tuiFrame.GetAnchorMode then
        return element.tuiFrame:GetAnchorMode()
    end
    
    -- Fall back to checking the tuiFrame's anchorMode property directly
    if element.tuiFrame.anchorMode then
        return element.tuiFrame.anchorMode
    end
    
    -- Fall back to saved data
    local settings = self:GetSettings()
    if settings.elements[id] and settings.elements[id].anchorMode then
        return settings.elements[id].anchorMode
    end
    
    return "BOTTOMLEFT"
end

function Layout:ToggleElementAnchorMode(id)
    local currentMode = self:GetElementAnchorMode(id)
    local newMode = (currentMode == "CENTER") and "BOTTOMLEFT" or "CENTER"
    
    -- Warn user that position will need adjustment
    if newMode == "CENTER" then
        print("|cffFFFF00TweaksUI:|r Switched " .. id .. " to CENTER anchor mode.")
        print("|cffFFFF00TweaksUI:|r The frame will now expand/contract from its center when icon count changes.")
        print("|cffFFFF00TweaksUI:|r You may need to reposition this element.")
    else
        print("|cffFFFF00TweaksUI:|r Switched " .. id .. " to BOTTOMLEFT anchor mode (default).")
    end
    
    self:SetElementAnchorMode(id, newMode)
    
    -- Re-save position with new anchor mode
    self:SaveElementPosition(id)
    
    return newMode
end

-- ============================================================================
-- ELEMENT REGISTRATION API
-- ============================================================================

--[[
    Register an element for positioning via Layout Mode
    
    @param id: Unique identifier (e.g., "actionbar_1", "player_castbar")
    @param options: {
        name: Display name shown in Layout Mode
        category: One of ELEMENT_CATEGORIES
        tuiFrame: TUIFrame instance (required)
        defaultPosition: { point, x, y } - fallback position
        onPositionChanged: callback(id, position)
        onSizeChanged: callback(id, width, height) - called when size matching changes frame size
    }
]]
function Layout:RegisterElement(id, options)
    if not id then
        error("Layout:RegisterElement requires an id")
        return
    end
    
    if not options.tuiFrame then
        error("Layout:RegisterElement requires a tuiFrame")
        return
    end
    
    options = options or {}
    
    local element = {
        id = id,
        name = options.name or id,
        category = options.category or ELEMENT_CATEGORIES.GENERAL,
        tuiFrame = options.tuiFrame,
        defaultPosition = options.defaultPosition or { point = "CENTER", x = 0, y = 0 },
        onPositionChanged = options.onPositionChanged,
        onSizeChanged = options.onSizeChanged,  -- NEW: callback for size matching changes
        overlay = nil,  -- Created when Layout Mode enters
    }
    
    elementRegistry[id] = element
    
    -- Load saved position if exists
    self:LoadElementPosition(id)
    
    return element
end

function Layout:UnregisterElement(id)
    local element = elementRegistry[id]
    if element then
        -- Destroy overlay if exists
        if element.overlay then
            element.overlay:Hide()
            element.overlay = nil
        end
        elementRegistry[id] = nil
    end
end

function Layout:GetElement(id)
    return elementRegistry[id]
end

function Layout:GetAllElements()
    return elementRegistry
end

function Layout:GetElementsByCategory(category)
    local result = {}
    for id, element in pairs(elementRegistry) do
        if element.category == category then
            result[id] = element
        end
    end
    return result
end

-- ============================================================================
-- POSITION MANAGEMENT
-- ============================================================================

function Layout:SaveElementPosition(id)
    local element = elementRegistry[id]
    if not element or not element.tuiFrame then return end
    
    local settings = self:GetSettings()
    local saveData
    
    -- Try calling GetSaveData method if it exists
    if element.tuiFrame.GetSaveData then
        saveData = element.tuiFrame:GetSaveData()
    else
        -- Fallback: manually construct save data from frame
        local frame = element.tuiFrame.frame or element.tuiFrame
        if frame and frame.GetLeft then
            local left = frame:GetLeft()
            local bottom = frame:GetBottom()
            local width = frame:GetWidth()
            local height = frame:GetHeight()
            local anchorMode = element.tuiFrame.anchorMode or "BOTTOMLEFT"
            
            if left and bottom then
                if anchorMode == "CENTER" and width and height then
                    saveData = {
                        point = "CENTER",
                        x = left + (width / 2),
                        y = bottom + (height / 2),
                        scale = frame:GetScale() or 1,
                        anchorMode = "CENTER",
                    }
                else
                    saveData = {
                        point = "BOTTOMLEFT",
                        x = left,
                        y = bottom,
                        scale = frame:GetScale() or 1,
                        anchorMode = "BOTTOMLEFT",
                    }
                end
            end
        end
    end
    
    if not saveData then return end
    
    settings.elements[id] = saveData
    
    -- Debug output (only if debug mode is on)
    if TUICD.debugMode then
        print("|cff00ff00TweaksUI Layout:|r Saved " .. id .. 
            " point=" .. tostring(saveData.point) ..
            " x=" .. string.format("%.1f", saveData.x or 0) .. 
            " y=" .. string.format("%.1f", saveData.y or 0))
    end
    
    -- Fire callback if registered
    if element.onPositionChanged then
        element.onPositionChanged(id, saveData)
    end
end

function Layout:LoadElementPosition(id)
    local element = elementRegistry[id]
    if not element or not element.tuiFrame then return end
    
    -- Don't load positions during combat
    if InCombatLockdown() then return end
    
    local settings = self:GetSettings()
    local savedData = settings.elements[id]
    
    if savedData then
        -- Debug output (only if debug mode is on)
        if TUICD.debugMode then
            print("|cff00ff00TweaksUI Layout:|r Loading " .. id .. 
                " point=" .. tostring(savedData.point) ..
                " x=" .. string.format("%.1f", savedData.x or 0) .. 
                " y=" .. string.format("%.1f", savedData.y or 0))
        end
        element.tuiFrame:LoadSaveData(savedData)
    else
        if TUICD.debugMode then
            print("|cffFFFF00TweaksUI Layout:|r No saved position for " .. id .. ", using default")
        end
        -- Use default position
        local def = element.defaultPosition
        element.tuiFrame:SetPosition(def.point, UIParent, def.point, def.x, def.y)
    end
end

function Layout:ApplyAllPositions()
    -- Don't apply positions during combat
    if InCombatLockdown() then
        return
    end
    
    -- Don't apply positions during Edit Mode to prevent conflicts
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return
    end
    
    for id in pairs(elementRegistry) do
        self:LoadElementPosition(id)
    end
end

function Layout:ResetElementPosition(id)
    local element = elementRegistry[id]
    if not element or not element.tuiFrame then return end
    
    -- Clear saved position
    local settings = self:GetSettings()
    settings.elements[id] = nil
    
    -- Apply default
    local def = element.defaultPosition
    element.tuiFrame:SetPosition(def.point, UIParent, def.point, def.x, def.y)
    
    -- Update overlay if in layout mode
    if isLayoutModeActive and element.overlay then
        TUICD.LayoutUI:UpdateOverlayPosition(element)
    end
end

function Layout:ResetAllPositions()
    local settings = self:GetSettings()
    settings.elements = {}
    
    for id, element in pairs(elementRegistry) do
        local def = element.defaultPosition
        element.tuiFrame:SetPosition(def.point, UIParent, def.point, def.x, def.y)
    end
    
    -- Update overlays if in layout mode
    if isLayoutModeActive then
        TUICD.LayoutUI:UpdateAllOverlays()
    end
end

-- ============================================================================
-- LAYOUT MODE CONTROL
-- ============================================================================

function Layout:Enter()
    if isLayoutModeActive then return end
    
    -- Prevent entering Layout mode during combat
    if InCombatLockdown() then
        print("|cffff0000TweaksUI:|r Cannot enter Layout Mode during combat")
        return
    end
    
    isLayoutModeActive = true
    
    -- Fire callback FIRST so modules can register elements
    self:FireCallback("OnLayoutModeEnter")
    
    -- THEN create/show overlays for all registered elements
    if TUICD.LayoutUI then
        TUICD.LayoutUI:ShowOverlays()
        
        -- Delayed refresh to catch any late-registered elements (like docks)
        -- Some modules may use C_Timer.After in their callbacks
        C_Timer.After(0.1, function()
            if isLayoutModeActive and TUICD.LayoutUI then
                -- Create overlays for any elements registered after initial ShowOverlays
                local elements = self:GetAllElements()
                for id, element in pairs(elements) do
                    TUICD.LayoutUI:CreateOverlay(element)
                end
                TUICD.LayoutUI:UpdateAllOverlays()
            end
        end)
    end
    
    print("|cff00ff00TweaksUI:|r Layout Mode |cff00ff00ENABLED|r - Drag elements to reposition")
end

function Layout:Exit()
    if not isLayoutModeActive then return end
    isLayoutModeActive = false
    
    -- Save sizes and absolute positions for all attached frames BEFORE module callbacks
    -- This captures exact state before modules can mess with them
    if TUICD.SnapLocking then
        TUICD.SnapLocking:SaveCurrentSizes()
        TUICD.SnapLocking:SaveAbsolutePositions()
    end
    
    -- Save all positions
    for id in pairs(elementRegistry) do
        self:SaveElementPosition(id)
    end
    
    -- Hide overlays
    if TUICD.LayoutUI then
        TUICD.LayoutUI:HideOverlays()
    end
    
    -- Clear selection
    selectedElementId = nil
    
    -- Fire callback (modules may refresh their layouts here)
    self:FireCallback("OnLayoutModeExit")
    
    -- Re-apply snap attachments AFTER module callbacks complete
    -- This ensures attachments override any module position/size resets
    if TUICD.SnapLocking then
        C_Timer.After(0.2, function()
            TUICD.SnapLocking:ApplyAllAttachments()
        end)
    end
    
    print("|cff00ff00TweaksUI:|r Layout Mode |cffff0000DISABLED|r - Positions saved")
end

function Layout:Toggle()
    if isLayoutModeActive then
        self:Exit()
    else
        self:Enter()
    end
end

function Layout:IsActive()
    return isLayoutModeActive
end

-- ============================================================================
-- SELECTION
-- ============================================================================

function Layout:SelectElement(id)
    local oldSelection = selectedElementId
    selectedElementId = id
    
    -- Update visual selection
    if TUICD.LayoutUI then
        if oldSelection then
            TUICD.LayoutUI:SetElementSelected(oldSelection, false)
        end
        if id then
            TUICD.LayoutUI:SetElementSelected(id, true)
        end
        -- Update coordinate panel
        TUICD.LayoutUI:OnElementSelected(id)
    end
    
    self:FireCallback("OnElementSelected", id, oldSelection)
end

function Layout:GetSelectedElement()
    return selectedElementId, elementRegistry[selectedElementId]
end

function Layout:ClearSelection()
    self:SelectElement(nil)
end

-- ============================================================================
-- SNAPPING
-- ============================================================================

-- DEPRECATED: This no longer auto-snaps frames
-- SnapLocking now handles all attachments - user must check "Lock" checkbox
-- Keeping for backwards compatibility - just returns snap target info
function Layout:TrySnapElement(id)
    return self:GetSnapTarget(id)
end

function Layout:GetSnapTarget(id)
    local element = elementRegistry[id]
    if not element or not element.tuiFrame then return end
    
    local settings = self:GetSettings()
    if not settings.snapping.enabled then return end
    
    return element.tuiFrame:GetSnapTarget(settings.snapping.tolerance)
end

-- ============================================================================
-- SETTINGS ACCESS
-- ============================================================================

function Layout:GetGridSettings()
    local settings = self:GetSettings()
    return settings.grid
end

function Layout:SetGridEnabled(enabled)
    local settings = self:GetSettings()
    settings.grid.enabled = enabled
    
    if isLayoutModeActive and TUICD.LayoutUI then
        TUICD.LayoutUI:UpdateGrid()
    end
end

function Layout:SetGridSize(size)
    local settings = self:GetSettings()
    settings.grid.size = size
    
    if isLayoutModeActive and TUICD.LayoutUI then
        TUICD.LayoutUI:UpdateGrid()
    end
end

function Layout:GetSnappingSettings()
    local settings = self:GetSettings()
    return settings.snapping
end

function Layout:SetSnappingEnabled(enabled)
    local settings = self:GetSettings()
    settings.snapping.enabled = enabled
end

function Layout:SetSnappingTolerance(tolerance)
    local settings = self:GetSettings()
    settings.snapping.tolerance = tolerance
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

local callbacks = {}

function Layout:RegisterCallback(event, callback)
    if not callbacks[event] then
        callbacks[event] = {}
    end
    table.insert(callbacks[event], callback)
end

function Layout:FireCallback(event, ...)
    if callbacks[event] then
        for _, callback in ipairs(callbacks[event]) do
            callback(...)
        end
    end
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_TUILAYOUT1 = "/tuil"
SLASH_TUILAYOUT2 = "/tuilayout"
SlashCmdList["TUILAYOUT"] = function(msg)
    local cmd = msg:lower():trim()
    
    if cmd == "" or cmd == "toggle" then
        Layout:Toggle()
    elseif cmd == "on" or cmd == "enter" then
        Layout:Enter()
    elseif cmd == "off" or cmd == "exit" then
        Layout:Exit()
    elseif cmd == "reset" then
        local selectedId = Layout:GetSelectedElement()
        if selectedId then
            Layout:ResetElementPosition(selectedId)
            print("|cff00ff00TweaksUI:|r Reset position for " .. selectedId)
        else
            print("|cff00ff00TweaksUI:|r No element selected. Select an element first or use '/tuil resetall'")
        end
    elseif cmd == "resetall" then
        Layout:ResetAllPositions()
        print("|cff00ff00TweaksUI:|r All positions reset to defaults")
    elseif cmd == "list" then
        print("|cff00ff00TweaksUI:|r Registered Layout Elements:")
        local count = 0
        for id, element in pairs(elementRegistry) do
            local shown = element.tuiFrame:IsShown() and "|cff00ff00shown|r" or "|cff888888hidden|r"
            print(string.format("  %s [%s] - %s", element.name, element.category, shown))
            count = count + 1
        end
        if count == 0 then
            print("  (no elements registered)")
        end
        print(string.format("Total: %d elements", count))
    elseif cmd == "grid" then
        local settings = Layout:GetSettings()
        settings.grid.enabled = not settings.grid.enabled
        print("|cff00ff00TweaksUI:|r Grid " .. (settings.grid.enabled and "enabled" or "disabled"))
        if isLayoutModeActive and TUICD.LayoutUI then
            TUICD.LayoutUI:UpdateGrid()
        end
    elseif cmd == "snap" then
        local settings = Layout:GetSettings()
        settings.snapping.enabled = not settings.snapping.enabled
        print("|cff00ff00TweaksUI:|r Snapping " .. (settings.snapping.enabled and "enabled" or "disabled"))
    elseif cmd == "help" then
        print("|cff00ff00TweaksUI Layout Commands:|r")
        print("  /tuil - Toggle Layout Mode")
        print("  /tuil on/off - Enter/exit Layout Mode")
        print("  /tuil reset - Reset selected element position")
        print("  /tuil resetall - Reset all positions")
        print("  /tuil list - List registered elements")
        print("  /tuil grid - Toggle grid display")
        print("  /tuil snap - Toggle snapping")
    else
        print("|cff00ff00TweaksUI:|r Unknown command. Use '/tuil help' for options.")
    end
end

-- Called when a profile is loaded - reload attachments from new settings
function Layout:OnProfileChanged(reason)
    if TUICD.PrintDebug then
        TUICD:PrintDebug("Layout: OnProfileChanged called, reason: " .. tostring(reason))
    end
    
    -- Reload attachments from the new profile settings
    if TUICD.SnapLocking then
        TUICD.SnapLocking:LoadAttachments()
        
        -- Apply after a short delay to let other modules initialize
        C_Timer.After(0.5, function()
            TUICD.SnapLocking:ApplyAllAttachments()
        end)
    end
end

-- ============================================================================
-- EXPORT/IMPORT/DEBUG FUNCTIONS
-- ============================================================================

-- Convert all current positions to CENTER-relative format for export/sharing
-- Returns a table: { elementId = { x = centerRelX, y = centerRelY }, ... }
function Layout:GetPositionsForExport()
    local positions = {}
    
    -- Get conversion function
    local ScreenToCenter = TUICD.ScreenToCenter
    if not ScreenToCenter then return positions end
    
    -- Convert each element's position
    for id, element in pairs(elementRegistry) do
        if element.tuiFrame and element.tuiFrame.frame then
            local frame = element.tuiFrame.frame
            local left = frame:GetLeft()
            local bottom = frame:GetBottom()
            local width = frame:GetWidth()
            local height = frame:GetHeight()
            
            if left and bottom and width and height then
                -- Calculate frame center position, then convert to center-relative
                local frameCenterX = left + (width / 2)
                local frameCenterY = bottom + (height / 2)
                local centerX, centerY = ScreenToCenter(frameCenterX, frameCenterY)
                
                positions[id] = {
                    x = math.floor(centerX * 10) / 10,  -- Round to 1 decimal
                    y = math.floor(centerY * 10) / 10,
                }
            end
        end
    end
    
    return positions
end

-- Apply positions from CENTER-relative format (from import/preset)
-- positions: { elementId = { x = centerRelX, y = centerRelY }, ... }
function Layout:ApplyPositionsFromImport(positions)
    if not positions then return end
    
    local settings = self:GetSettings()
    local CenterToScreen = TUICD.CenterToScreen
    if not CenterToScreen then
        print("|cffff0000TweaksUI:|r Coordinate conversion not available")
        return
    end
    
    local count = 0
    
    for id, pos in pairs(positions) do
        if pos.x and pos.y then
            -- Convert CENTER-relative to screen absolute
            local absX, absY = CenterToScreen(pos.x, pos.y)
            
            -- Adjust for frame size to get bottom-left corner
            local element = elementRegistry[id]
            local halfWidth, halfHeight = 50, 25  -- Default estimate
            if element and element.tuiFrame and element.tuiFrame.frame then
                local frame = element.tuiFrame.frame
                halfWidth = (frame:GetWidth() or 100) / 2
                halfHeight = (frame:GetHeight() or 50) / 2
            end
            
            -- Convert from center position to bottom-left position
            local bottomLeftX = absX - halfWidth
            local bottomLeftY = absY - halfHeight
            
            -- Save in BOTTOMLEFT format (default anchor mode)
            settings.elements[id] = {
                point = "BOTTOMLEFT",
                x = bottomLeftX,
                y = bottomLeftY,
                anchorMode = "BOTTOMLEFT",
            }
            count = count + 1
            
            -- Apply immediately if element exists
            if element and element.tuiFrame then
                element.tuiFrame:SetAnchorMode("BOTTOMLEFT")
                element.tuiFrame:SetPosition("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bottomLeftX, bottomLeftY)
            end
        end
    end
    
    return count
end

-- Get raw saved positions (CENTER format) - for internal use
function Layout:GetRawPositions()
    local settings = self:GetSettings()
    return settings.elements or {}
end

-- Set raw positions (CENTER format) - for internal use
function Layout:SetRawPositions(positions)
    if not positions then return end
    local settings = self:GetSettings()
    settings.elements = positions
end

-- Export current on-screen positions to a copyable string
function Layout:ExportPositions()
    local positions = {}
    
    -- Get screen dimensions for center calculation
    local screenWidth, screenHeight = GetPhysicalScreenSize()
    local uiScale = UIParent:GetEffectiveScale()
    local screenCenterX = (screenWidth / uiScale) / 2
    local screenCenterY = (screenHeight / uiScale) / 2
    
    -- Capture positions from all registered elements
    for id, element in pairs(elementRegistry) do
        if element.tuiFrame and element.tuiFrame.frame then
            local frame = element.tuiFrame.frame
            local left = frame:GetLeft()
            local bottom = frame:GetBottom()
            local width = frame:GetWidth()
            local height = frame:GetHeight()
            
            if left and bottom and width and height then
                -- Calculate center-relative position
                local frameCenterX = left + (width / 2)
                local frameCenterY = bottom + (height / 2)
                local x = frameCenterX - screenCenterX
                local y = frameCenterY - screenCenterY
                
                positions[id] = {
                    point = "CENTER",
                    x = math.floor(x * 10) / 10,  -- Round to 1 decimal
                    y = math.floor(y * 10) / 10,
                }
            end
        end
    end
    
    -- Serialize to string
    local parts = {}
    for id, pos in pairs(positions) do
        table.insert(parts, id .. ":" .. pos.x .. "," .. pos.y)
    end
    local exportString = table.concat(parts, ";")
    
    -- Show in a copyable edit box
    local frame = CreateFrame("Frame", "TweaksUI_ExportLayoutFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 200)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "TweaksUI_ExportLayoutFrame")
    
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText("TUICD Layout Export")
    
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    instructions:SetPoint("TOP", 0, -30)
    instructions:SetText("Copy this string (Ctrl+C). Use /tui importlayout <string> to import.")
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -55)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(540)
    editBox:SetAutoFocus(true)
    editBox:SetText(exportString)
    editBox:HighlightText()
    scrollFrame:SetScrollChild(editBox)
    
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOM", 0, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    print("|cff00ff00TweaksUI:|r Exported " .. #parts .. " element positions")
end

-- Import positions from a string (CENTER-relative format)
function Layout:ImportPositions(importString)
    if not importString or importString == "" then
        print("|cffff0000TweaksUI:|r No import string provided")
        return
    end
    
    local settings = self:GetSettings()
    local count = 0
    
    -- Get conversion function
    local CenterToScreen = TUICD.CenterToScreen
    if not CenterToScreen then
        print("|cffff0000TweaksUI:|r Coordinate conversion not available")
        return
    end
    
    -- Parse the string: "id:x,y;id:x,y;..."
    for entry in importString:gmatch("[^;]+") do
        local id, coords = entry:match("^([^:]+):(.+)$")
        if id and coords then
            local x, y = coords:match("^([%-%.%d]+),([%-%.%d]+)$")
            if x and y then
                x = tonumber(x)
                y = tonumber(y)
                if x and y then
                    -- Convert CENTER-relative to screen absolute (this gives us the frame center position)
                    local absX, absY = CenterToScreen(x, y)
                    
                    -- Save in CENTER format (absX, absY is already the center position)
                    settings.elements[id] = {
                        point = "CENTER",
                        x = absX,
                        y = absY,
                    }
                    count = count + 1
                    
                    -- Apply immediately if element exists
                    local element = elementRegistry[id]
                    if element and element.tuiFrame then
                        element.tuiFrame:SetPosition("CENTER", UIParent, "CENTER", absX, absY)
                    end
                end
            end
        end
    end
    
    print("|cff00ff00TweaksUI:|r Imported " .. count .. " positions. /reload to fully apply.")
end

-- Completely wipe all position-related saved variables
function Layout:WipeAllPositionData()
    print("|cffFFFF00TweaksUI:|r Wiping ALL position data...")
    
    -- Clear Layout element positions
    local settings = self:GetSettings()
    settings.elements = {}
    
    -- Reset data version to force migration on next load (this will clear more data)
    settings.dataVersion = 0
    
    -- Clear all the extra position storage
    if TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB.cooldownContainerPositions = nil
        TweaksUI_Cooldowns_CharDB.actionBarContainerPositions = nil
        TweaksUI_Cooldowns_CharDB.uiFrameContainerPositions = nil
        TweaksUI_Cooldowns_CharDB.snapLocks = nil
        
        -- Clear minimap position
        if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.general then
            if TweaksUI_Cooldowns_CharDB.settings.general.minimap then
                TweaksUI_Cooldowns_CharDB.settings.general.minimap.customPosition = nil
            end
        end
        
        -- Clear PersonalResources positions
        if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.personalResources then
            local pr = TweaksUI_Cooldowns_CharDB.settings.personalResources
            for _, key in ipairs({"healthBar", "powerBar", "classPower", "soulFragments", "buffs", "debuffs"}) do
                if pr[key] then
                    pr[key].positionX = nil
                    pr[key].positionY = nil
                    pr[key].anchor = nil
                end
            end
        end
        
        -- Clear CastBars positions
        if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.castBars then
            local cb = TweaksUI_Cooldowns_CharDB.settings.castBars
            for _, unit in ipairs({"player", "target", "focus"}) do
                if cb[unit] then
                    cb[unit].positionX = nil
                    cb[unit].positionY = nil
                    cb[unit].anchor = nil
                end
            end
        end
        
        -- Clear Chat positions
        if TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.chat then
            local chat = TweaksUI_Cooldowns_CharDB.settings.chat
            chat.frameX = nil
            chat.frameY = nil
            chat.framePoint = nil
        end
    end
    
    print("|cff00ff00TweaksUI:|r Position data wiped. /reload to apply defaults.")
    print("|cff00ff00TweaksUI:|r Use /tui layout to reposition frames after reload.")
end

-- Debug: show what's in saved variables
function Layout:DebugSavedPositions()
    print("|cff00ff00TweaksUI Layout Debug:|r Saved positions in settings.elements:")
    
    local settings = self:GetSettings()
    local count = 0
    
    if settings.elements then
        for id, data in pairs(settings.elements) do
            local x = data.x and string.format("%.1f", data.x) or "nil"
            local y = data.y and string.format("%.1f", data.y) or "nil"
            print("  " .. id .. ": point=" .. tostring(data.point) .. " x=" .. x .. " y=" .. y)
            count = count + 1
        end
    end
    
    print("  Total: " .. count .. " elements")
    print("")
    print("|cff00ff00TweaksUI Layout Debug:|r Data version: " .. tostring(settings.dataVersion))
    
    -- Check for other position storage
    if TweaksUI_Cooldowns_CharDB then
        if TweaksUI_Cooldowns_CharDB.cooldownContainerPositions then
            print("|cff00ff00TweaksUI Layout Debug:|r cooldownContainerPositions exists")
            for k, v in pairs(TweaksUI_Cooldowns_CharDB.cooldownContainerPositions) do
                print("  " .. k .. ": " .. tostring(v.point) .. " " .. tostring(v.x) .. "," .. tostring(v.y))
            end
        end
        if TweaksUI_Cooldowns_CharDB.actionBarContainerPositions then
            print("|cff00ff00TweaksUI Layout Debug:|r actionBarContainerPositions exists")
        end
        if TweaksUI_Cooldowns_CharDB.uiFrameContainerPositions then
            print("|cff00ff00TweaksUI Layout Debug:|r uiFrameContainerPositions exists")
        end
    end
end