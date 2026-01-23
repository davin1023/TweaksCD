-- ============================================================================
-- TUICD: UIElements
-- Registers misc UI elements with the Layout system for custom positioning
-- NOTE: UnitFrames have their own position system - they are NOT handled here
-- ============================================================================

local ADDON_NAME, TUICD = ...

local UIElements = {}
TUICD.UIElements = UIElements

-- Module references (set after modules load)
local Layout
local TUIFrame

-- ============================================================================
-- STATE
-- ============================================================================

local elementWrappers = {}  -- TUIFrame wrappers for Blizzard frames
local initialized = false

-- ============================================================================
-- ELEMENT DEFINITIONS
-- Only misc UI elements - UnitFrames have their own positioning system
-- ============================================================================

local ELEMENT_DEFINITIONS = {
    -- TUI:CD only manages cooldown-related elements through the Cooldowns module
    -- Buffs, debuffs, XP bars, etc. are handled by the full TweaksUI suite
    -- This file is kept for future expansion (e.g., Personal Resources)
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function GetBlizzardFrame(def)
    -- Check for TUICD custom frame first
    if def.customFrame then
        local customFrame = _G[def.customFrame]
        if customFrame and customFrame:IsShown() then
            return customFrame, true  -- Return frame and flag that it's custom
        end
    end
    
    -- Fall back to Blizzard frame
    local frame = _G[def.blizzFrame]
    
    -- Try alternate frame names if primary not found
    if not frame and def.alternateFrames then
        for _, altName in ipairs(def.alternateFrames) do
            frame = _G[altName]
            if frame then break end
        end
    end
    
    return frame, false  -- Return frame and flag that it's not custom
end

local function GetOriginalPosition(frame)
    if not frame then return nil end
    
    local numPoints = frame:GetNumPoints()
    if numPoints > 0 then
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        return {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end
    return nil
end

local function FrameHasValidBounds(frame)
    if not frame then return false end
    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    local width = frame:GetWidth()
    local height = frame:GetHeight()
    return left and bottom and width and height and width > 0 and height > 0
end

-- Get size for an element
local function GetElementSize(def, frame)
    -- Use dynamic size from frame if specified
    if def.useDynamicSize and frame then
        local width = frame:GetWidth()
        local height = frame:GetHeight()
        if width and width > 0 and height and height > 0 then
            return width, height
        end
    end
    return def.defaultWidth or 100, def.defaultHeight or 100
end

-- ============================================================================
-- WRAPPER CREATION
-- ============================================================================

local function CreateElementWrapper(elementId, def)
    local trackingFrame, isCustomFrame
    
    -- For unit frames, check if TUI custom frame should be used
    if def.unitType then
        trackingFrame, isCustomFrame = GetTrackingFrame(def)
    else
        trackingFrame, isCustomFrame = GetBlizzardFrame(def)
    end
    
    -- Skip frames that don't exist
    if not trackingFrame then
        TUICD:PrintDebug("UIElements: Frame not found for " .. elementId)
        return nil
    end
    
    -- Skip frames without valid bounds (not shown yet)
    if not FrameHasValidBounds(trackingFrame) then
        TUICD:PrintDebug("UIElements: Frame has no valid bounds: " .. elementId)
        return nil
    end
    
    -- Get size (dynamic from frame if specified, otherwise defaults)
    local width, height = GetElementSize(def, trackingFrame)
    
    -- Store original position for restoration
    local originalPos = GetOriginalPosition(trackingFrame)
    
    -- Create TUIFrame wrapper
    local wrapper = TUIFrame:New("layout_" .. elementId, {
        width = width,
        height = height,
    })
    
    if not wrapper then
        TUICD:PrintDebug("UIElements: Failed to create wrapper for " .. elementId)
        return nil
    end
    
    -- Store references
    wrapper.elementId = elementId
    wrapper.blizzFrame = trackingFrame  -- The frame we're tracking (TUI custom or Blizzard)
    wrapper.isCustomFrame = isCustomFrame
    wrapper.originalPosition = originalPos
    wrapper.definition = def
    
    -- Position wrapper at current frame position
    local point, relativeTo, relativePoint, x, y = trackingFrame:GetPoint(1)
    if point then
        wrapper.frame:ClearAllPoints()
        wrapper.frame:SetPoint(point, relativeTo or UIParent, relativePoint or point, x or 0, y or 0)
    else
        wrapper.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    
    -- Don't block mouse
    wrapper.frame:EnableMouse(false)
    
    TUICD:PrintDebug("UIElements: Created wrapper for " .. elementId .. 
        " (custom=" .. tostring(isCustomFrame) .. ", size=" .. width .. "x" .. height .. ")")
    
    return wrapper
end

-- ============================================================================
-- REGISTRATION WITH LAYOUT
-- ============================================================================

local function RegisterElementWithLayout(elementId, wrapper, def)
    if not Layout then return end
    
    local categoryKey = def.category or "GENERAL"
    local category = Layout.CATEGORIES[categoryKey] or Layout.CATEGORIES.GENERAL
    
    Layout:RegisterElement(elementId, {
        name = def.name,
        category = category,
        tuiFrame = wrapper,
        defaultPosition = wrapper.originalPosition or { point = "CENTER", x = 0, y = 0 },
        onPositionChanged = function(id, saveData)
            -- When Layout position changes, move Blizzard frame to match
            local blizzFrame = wrapper.blizzFrame
            if blizzFrame and not InCombatLockdown() and saveData and saveData.x and saveData.y then
                blizzFrame:ClearAllPoints()
                blizzFrame:SetPoint(
                    saveData.point or "BOTTOMLEFT",
                    UIParent,
                    saveData.point or "BOTTOMLEFT",
                    saveData.x,
                    saveData.y
                )
            end
        end,
    })
end

-- ============================================================================
-- POSITION MANAGEMENT
-- ============================================================================

local function RestoreBlizzardFramePosition(wrapper)
    if not wrapper or not wrapper.blizzFrame or not wrapper.originalPosition then return end
    if InCombatLockdown() then return end
    
    local blizzFrame = wrapper.blizzFrame
    local orig = wrapper.originalPosition
    
    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint(
        orig.point or "CENTER",
        orig.relativeTo or UIParent,
        orig.relativePoint or orig.point or "CENTER",
        orig.x or 0,
        orig.y or 0
    )
end

-- ============================================================================
-- SIZE UPDATE - Refreshes sizes from current frame state
-- ============================================================================

function UIElements:UpdateElementSize(elementId)
    local wrapper = elementWrappers[elementId]
    if not wrapper or not wrapper.definition then return end
    
    local def = wrapper.definition
    local width, height = GetElementSize(def, wrapper.blizzFrame)
    wrapper:SetSize(width, height)
end

function UIElements:UpdateAllSizes()
    for elementId, wrapper in pairs(elementWrappers) do
        self:UpdateElementSize(elementId)
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function UIElements:Initialize()
    if initialized then return end
    
    Layout = TUICD.Layout
    TUIFrame = TUICD.TUIFrame
    
    if not Layout or not TUIFrame then
        TUICD:PrintDebug("UIElements: Layout or TUIFrame not available")
        return
    end
    
    -- Delay initialization to ensure frames exist
    C_Timer.After(1.0, function()
        self:RegisterAllElements()
    end)
    
    initialized = true
end

function UIElements:RegisterAllElements()
    TUICD:PrintDebug("UIElements: Registering all elements...")
    
    local registered = 0
    local skipped = 0
    
    for elementId, def in pairs(ELEMENT_DEFINITIONS) do
        local wrapper = CreateElementWrapper(elementId, def)
        
        if wrapper then
            elementWrappers[elementId] = wrapper
            RegisterElementWithLayout(elementId, wrapper, def)
            registered = registered + 1
            TUICD:PrintDebug("  Registered: " .. def.name)
        else
            skipped = skipped + 1
        end
    end
    
    TUICD:PrintDebug("UIElements: Registered " .. registered .. " elements, skipped " .. skipped)
    
    -- Apply saved positions after a brief delay
    C_Timer.After(0.5, function()
        self:ApplyAllLayoutPositions()
    end)
end

function UIElements:GetWrapper(elementId)
    return elementWrappers[elementId]
end

function UIElements:GetAllWrappers()
    return elementWrappers
end

function UIElements:ApplyLayoutPosition(elementId)
    local wrapper = elementWrappers[elementId]
    if not wrapper or not wrapper.blizzFrame then return end
    if InCombatLockdown() then return end
    
    -- Get saved position from Layout module
    local element = Layout:GetElement(elementId)
    if element and element.tuiFrame then
        local saveData = element.tuiFrame:GetSaveData()
        if saveData and saveData.x and saveData.y then
            wrapper.blizzFrame:ClearAllPoints()
            wrapper.blizzFrame:SetPoint(
                saveData.point or "BOTTOMLEFT",
                UIParent,
                saveData.point or "BOTTOMLEFT",
                saveData.x,
                saveData.y
            )
        end
    end
end

function UIElements:ApplyAllLayoutPositions()
    if InCombatLockdown() then return end
    
    for elementId, wrapper in pairs(elementWrappers) do
        self:ApplyLayoutPosition(elementId)
    end
end

function UIElements:RestorePosition(elementId)
    local wrapper = elementWrappers[elementId]
    if wrapper then
        RestoreBlizzardFramePosition(wrapper)
    end
end

function UIElements:RestoreAllPositions()
    for elementId, wrapper in pairs(elementWrappers) do
        RestoreBlizzardFramePosition(wrapper)
    end
end

function UIElements:RefreshElement(elementId)
    local wrapper = elementWrappers[elementId]
    if not wrapper then return end
    
    local def = wrapper.definition
    if not def then return end
    
    -- Re-get the Blizzard frame (might have been recreated)
    local blizzFrame = GetBlizzardFrame(def)
    if blizzFrame then
        wrapper.blizzFrame = blizzFrame
        self:UpdateElementSize(elementId)
    end
end

-- ============================================================================
-- LAYOUT MODE CALLBACKS
-- ============================================================================

function UIElements:OnLayoutModeEnter()
    -- Update all wrapper sizes
    self:UpdateAllSizes()
end

function UIElements:OnLayoutModeExit()
    -- Apply final positions to tracked frames
    self:ApplyAllLayoutPositions()
end

-- ============================================================================
-- INITIALIZATION HOOK
-- ============================================================================

local function HookLayoutModule()
    local Layout = TUICD.Layout
    if not Layout then
        C_Timer.After(0.5, HookLayoutModule)
        return
    end
    
    -- Wait for Layout callbacks
    if Layout.RegisterCallback then
        Layout:RegisterCallback("OnLayoutModeEnter", function()
            UIElements:OnLayoutModeEnter()
        end)
        
        Layout:RegisterCallback("OnLayoutModeExit", function()
            UIElements:OnLayoutModeExit()
        end)
    end
    
    -- Initialize after a delay to ensure all frames exist
    C_Timer.After(2.0, function()
        UIElements:Initialize()
    end)
end

-- Start initialization chain
C_Timer.After(0.1, HookLayoutModule)
