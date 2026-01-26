-- ============================================================================
-- TUICD: TUIFrame - Base Wrapper Frame Class
-- Creates positionable wrapper frames with LibFlyPaper integration
-- ============================================================================

local ADDON_NAME, TUICD = ...

local FLYPAPER_GROUP = "TUICD"
local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)

local TUIFrame = {}
TUIFrame.__index = TUIFrame
TUICD.TUIFrame = TUIFrame

-- Registry of all TUIFrames
local frameRegistry = {}
TUIFrame.registry = frameRegistry

-- ============================================================================
-- GLOBAL INITIALIZATION CONTROL
-- All frames start hidden and are revealed together after positioning completes
-- ============================================================================

local initializationComplete = false
local pendingFrames = {}  -- Frames waiting to be revealed

-- Check if initialization is complete
function TUIFrame.IsInitializationComplete()
    return initializationComplete
end

-- Register a non-TUIFrame for batch reveal (used by modules that create raw frames)
function TUIFrame.RegisterPendingFrame(frame)
    if initializationComplete then
        -- Already past init phase, show immediately
        if frame and frame.SetAlpha then
            frame:SetAlpha(1)
        end
    else
        -- Queue for batch reveal
        pendingFrames[frame] = true
    end
end

-- Reveal all pending frames at once
function TUIFrame.RevealAllFrames()
    initializationComplete = true
    
    -- FIRST: Apply action bar visibility BEFORE revealing frames
    -- This sets tweaksTargetAlpha on frames that should stay hidden
    if TUICD.ActionBars and TUICD.ActionBars.ApplyAllVisibility then
        TUICD.ActionBars:ApplyAllVisibility()
    end
    
    -- Reveal TUIFrame containers, but respect visibility-managed frames
    for frame, _ in pairs(pendingFrames) do
        if frame and frame.SetAlpha then
            -- If this frame has visibility management (tweaksTargetAlpha is set),
            -- use that alpha instead of forcing to 1
            if frame.tweaksTargetAlpha ~= nil then
                frame:SetAlpha(frame.tweaksTargetAlpha)
            else
                frame:SetAlpha(1)
            end
        end
    end
    wipe(pendingFrames)
    
    -- Also ensure all Blizzard cooldown viewers and their containers are visible
    local viewerNames = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer", 
        "BuffIconCooldownViewer",
    }
    for _, name in ipairs(viewerNames) do
        local viewer = _G[name]
        if viewer then
            -- Show the container
            local container = viewer._TUI_Container
            if container then
                container:SetAlpha(1)
            end
            -- Viewer alpha will be set by UpdateAllTrackerVisibility below
        end
    end
    
    -- IMMEDIATELY apply tracker visibility (no delay - positions are already set)
    if TUICD.Cooldowns and TUICD.Cooldowns.UpdateAllTrackerVisibility then
        TUICD.Cooldowns:UpdateAllTrackerVisibility()
    else
        -- Fallback: set viewers to visible 
        for _, name in ipairs(viewerNames) do
            local viewer = _G[name]
            if viewer then
                viewer:SetAlpha(1)
            end
        end
    end
    
    if TUICD and TUICD.PrintDebug then
        TUICD:PrintDebug("TUIFrame: All frames revealed - initialization complete")
    end
end

-- Mark a frame as ready (called after position is set)
local function MarkFrameReady(frame)
    if initializationComplete then
        -- Already past init phase, show immediately
        frame:SetAlpha(1)
    else
        -- Queue for batch reveal
        pendingFrames[frame] = true
    end
end

-- ============================================================================
-- COORDINATE CONVERSION UTILITIES
-- Store positions relative to screen center for resolution independence
-- ============================================================================

-- Convert screen coordinates (BOTTOMLEFT) to center-relative coordinates
local function ScreenToCenter(screenX, screenY)
    local screenWidth, screenHeight = GetPhysicalScreenSize()
    local uiScale = UIParent:GetEffectiveScale()
    local centerX = (screenWidth / uiScale) / 2
    local centerY = (screenHeight / uiScale) / 2
    return screenX - centerX, screenY - centerY
end

-- Convert center-relative coordinates back to screen coordinates (BOTTOMLEFT)
local function CenterToScreen(centerX, centerY)
    local screenWidth, screenHeight = GetPhysicalScreenSize()
    local uiScale = UIParent:GetEffectiveScale()
    local halfWidth = (screenWidth / uiScale) / 2
    local halfHeight = (screenHeight / uiScale) / 2
    return centerX + halfWidth, centerY + halfHeight
end

-- Export for use by other modules
TUIFrame.ScreenToCenter = ScreenToCenter
TUIFrame.CenterToScreen = CenterToScreen

-- Also export at TUICD level for convenience
TUICD.ScreenToCenter = ScreenToCenter
TUICD.CenterToScreen = CenterToScreen

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

function TUIFrame:New(id, options)
    if not id then
        error("TUIFrame:New requires an id")
        return nil
    end
    
    -- Return existing if already created
    if frameRegistry[id] then
        return frameRegistry[id]
    end
    
    options = options or {}
    
    local instance = setmetatable({}, TUIFrame)
    
    -- Core properties
    instance.id = id
    instance.name = options.name or id
    instance.category = options.category or "General"
    
    -- Default position
    instance.defaultPosition = {
        point = options.defaultPoint or "CENTER",
        x = options.defaultX or 0,
        y = options.defaultY or 0,
    }
    
    -- Docking config (for future use)
    instance.docking = options.docking or {
        top = { enabled = true, isMother = false },
        bottom = { enabled = true, isMother = false },
        left = { enabled = true, isMother = false },
        right = { enabled = true, isMother = false },
    }
    
    -- Callbacks
    instance.onPositionChanged = options.onPositionChanged
    
    -- Create the wrapper frame
    local frameName = "TUIFrame_" .. id:gsub("[^%w]", "_")
    local frame = CreateFrame("Frame", frameName, UIParent)
    frame:SetSize(options.width or 100, options.height or 100)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)  -- Don't capture mouse by default
    frame.tuiFrame = instance  -- Back-reference
    
    -- Handle visibility based on initialization state
    if initializationComplete then
        -- Initialization already done, show immediately
        frame:SetAlpha(1)
    else
        -- Start hidden - will be revealed by TUIFrame.RevealAllFrames()
        frame:SetAlpha(0)
        pendingFrames[frame] = true
    end
    
    instance.frame = frame
    
    -- Content tracking
    instance.contentFrames = {}
    
    -- Position state
    instance.anchor = nil
    instance.relativeToId = nil
    
    -- Set default position
    instance:ResetPosition()
    
    -- Register with FlyPaper
    if FlyPaper then
        local success = FlyPaper.AddFrame(FLYPAPER_GROUP, id, frame)
        if TUICD.PrintDebug then
            TUICD:PrintDebug("TUIFrame: Added " .. id .. " to FlyPaper group '" .. FLYPAPER_GROUP .. "' - success: " .. tostring(success))
        end
    else
        if TUICD.PrintDebug then
            TUICD:PrintDebug("TUIFrame: FlyPaper not available for " .. id)
        end
    end
    
    -- Store in registry
    frameRegistry[id] = instance
    
    return instance
end

-- ============================================================================
-- POSITION MANAGEMENT
-- ============================================================================

function TUIFrame:SetPosition(point, relFrame, relPoint, x, y)
    -- Don't modify protected frames during combat
    if InCombatLockdown() then
        return
    end
    
    point = point or "CENTER"
    relFrame = relFrame or UIParent
    relPoint = relPoint or point
    x = x or 0
    y = y or 0
    
    self.frame:ClearAllPoints()
    self.frame:SetPoint(point, relFrame, relPoint, x, y)
    
    -- Store anchor info
    self.anchor = {
        point = point,
        relPoint = relPoint,
        x = x,
        y = y,
    }
    
    -- Track relative frame if it's another TUIFrame
    if relFrame and relFrame.tuiFrame then
        self.relativeToId = relFrame.tuiFrame.id
    else
        self.relativeToId = nil
    end
    
    -- Fire callback
    if self.onPositionChanged then
        self.onPositionChanged(self, point, relFrame, relPoint, x, y)
    end
    
    -- Frame will be revealed by TUIFrame.RevealAllFrames() after all positions are set
end

function TUIFrame:GetPosition()
    local point, relTo, relPoint, x, y = self.frame:GetPoint(1)
    return {
        point = point,
        relFrame = relTo,
        relPoint = relPoint,
        x = x,
        y = y,
    }
end

function TUIFrame:ResetPosition()
    local def = self.defaultPosition
    self:SetPosition(def.point, UIParent, def.point, def.x, def.y)
end

-- ============================================================================
-- FLYPAPER INTEGRATION
-- ============================================================================

-- DEPRECATED: Use GetSnapTarget() instead
-- This function used to physically snap frames, but now SnapLocking handles all attachments
-- Keeping for backwards compatibility but it just calls GetSnapTarget now
function TUIFrame:TrySnap(tolerance)
    return self:GetSnapTarget(tolerance)
end

function TUIFrame:GetSnapTarget(tolerance)
    if not FlyPaper then return nil end
    tolerance = tolerance or 15
    
    -- Just check, don't actually snap
    local point, relFrame, relPoint, x, y = FlyPaper.GetBestAnchorForGroup(
        self.frame, 
        FLYPAPER_GROUP, 
        tolerance
    )
    
    if point and relFrame then
        return relFrame, point, relPoint, x, y
    end
    
    return nil
end

-- DEPRECATED: Grid snapping removed to avoid conflicts with SnapLocking system
-- If grid snapping is needed, it should be implemented in SnapLocking
function TUIFrame:TrySnapToGrid(gridSize, tolerance)
    -- No longer auto-snaps - SnapLocking handles all positioning
    return nil
end

-- ============================================================================
-- CONTENT MANAGEMENT
-- ============================================================================

function TUIFrame:WrapContent(contentFrame, anchor)
    if not contentFrame then return end
    
    anchor = anchor or "TOPLEFT"
    
    -- Store original parent for restoration
    if not contentFrame._tuiOriginalParent then
        contentFrame._tuiOriginalParent = contentFrame:GetParent()
    end
    
    -- Reparent to our wrapper
    contentFrame:SetParent(self.frame)
    contentFrame:ClearAllPoints()
    contentFrame:SetPoint(anchor, self.frame, anchor, 0, 0)
    
    table.insert(self.contentFrames, contentFrame)
end

function TUIFrame:AddContent(contentFrame)
    -- Add without reparenting (just track)
    if not contentFrame then return end
    table.insert(self.contentFrames, contentFrame)
end

function TUIFrame:RestoreContent()
    for _, content in ipairs(self.contentFrames) do
        if content._tuiOriginalParent then
            content:SetParent(content._tuiOriginalParent)
            content._tuiOriginalParent = nil
        end
    end
    self.contentFrames = {}
end

function TUIFrame:UpdateSizeFromContent()
    local maxW, maxH = 0, 0
    for _, content in ipairs(self.contentFrames) do
        local w, h = content:GetSize()
        if w > maxW then maxW = w end
        if h > maxH then maxH = h end
    end
    if maxW > 0 and maxH > 0 then
        self.frame:SetSize(maxW, maxH)
    end
end

-- ============================================================================
-- SIZE AND SCALE
-- ============================================================================

function TUIFrame:SetSize(width, height)
    -- If size is locked by SnapLocking, ignore external size changes
    if self.sizeLocked then
        if TUICD.PrintDebug then
            TUICD:PrintDebug("TUIFrame: Size change ignored for " .. self.id .. " (size locked by SnapLocking)")
        end
        return
    end
    self.frame:SetSize(width, height)
end

-- Force set size even if locked (used by SnapLocking)
function TUIFrame:ForceSetSize(width, height)
    self.frame:SetSize(width, height)
end

-- Lock/unlock size (used by SnapLocking)
function TUIFrame:SetSizeLocked(locked)
    self.sizeLocked = locked
end

function TUIFrame:IsSizeLocked()
    return self.sizeLocked
end

function TUIFrame:GetSize()
    return self.frame:GetSize()
end

-- Get the full outer size including any visual elements (borders, etc.)
-- This uses GetRect() to get the actual rendered bounds
function TUIFrame:GetOuterSize()
    local frame = self.frame
    local left, bottom, width, height = frame:GetRect()
    
    if width and height then
        return width, height
    end
    
    -- Fallback to standard GetSize
    return frame:GetSize()
end

-- Get outer size by checking all children for border overlays
-- This is more accurate for frames with backdrop borders
function TUIFrame:GetVisualBounds()
    local frame = self.frame
    local frameWidth, frameHeight = frame:GetSize()
    
    -- Check if this frame has a backdrop with edge insets
    -- Many frames use backdrops with edgeSize for borders
    local backdrop = frame.GetBackdrop and frame:GetBackdrop()
    if backdrop and backdrop.edgeSize then
        -- The edgeSize is the border thickness
        local borderSize = backdrop.edgeSize or 0
        return frameWidth + (borderSize * 2), frameHeight + (borderSize * 2)
    end
    
    -- Check children for border frames that extend beyond the wrapper
    local maxWidth, maxHeight = frameWidth, frameHeight
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        local childLeft, childBottom, childWidth, childHeight = child:GetRect()
        local frameLeft, frameBottom = frame:GetLeft(), frame:GetBottom()
        
        if childLeft and frameLeft and childWidth and childHeight then
            -- Calculate how much the child extends beyond the frame
            local leftExtend = math.max(0, frameLeft - childLeft)
            local rightExtend = math.max(0, (childLeft + childWidth) - (frameLeft + frameWidth))
            local bottomExtend = math.max(0, frameBottom - childBottom)
            local topExtend = math.max(0, (childBottom + childHeight) - (frameBottom + frameHeight))
            
            maxWidth = math.max(maxWidth, frameWidth + leftExtend + rightExtend)
            maxHeight = math.max(maxHeight, frameHeight + bottomExtend + topExtend)
        end
    end
    
    return maxWidth, maxHeight
end

function TUIFrame:SetScale(scale)
    -- FlyPaper-aware scale setting
    if FlyPaper and FlyPaper.SetScale then
        FlyPaper.SetScale(self.frame, scale)
    else
        self.frame:SetScale(scale)
    end
end

function TUIFrame:GetScale()
    return self.frame:GetScale() or 1
end

-- ============================================================================
-- ANCHOR MODE
-- Controls how position is saved: BOTTOMLEFT (default) or CENTER
-- CENTER mode makes frames expand/contract from their center when size changes
-- ============================================================================

function TUIFrame:SetAnchorMode(mode)
    self.anchorMode = mode or "BOTTOMLEFT"
end

function TUIFrame:GetAnchorMode()
    return self.anchorMode or "BOTTOMLEFT"
end

-- ============================================================================
-- VISIBILITY
-- ============================================================================

function TUIFrame:Show()
    self.frame:Show()
end

function TUIFrame:Hide()
    self.frame:Hide()
end

function TUIFrame:IsShown()
    return self.frame:IsShown()
end

function TUIFrame:SetAlpha(alpha)
    self.frame:SetAlpha(alpha)
end

function TUIFrame:GetAlpha()
    return self.frame:GetAlpha()
end

-- ============================================================================
-- SERIALIZATION
-- ============================================================================

function TUIFrame:GetSaveData()
    -- Check if this element uses CENTER anchoring (opt-in per element)
    local useCenter = self.anchorMode == "CENTER"
    
    local left = self.frame:GetLeft()
    local bottom = self.frame:GetBottom()
    local width = self.frame:GetWidth()
    local height = self.frame:GetHeight()
    
    -- Handle case where frame position isn't valid yet
    if not left or not bottom then
        local point, _, _, x, y = self.frame:GetPoint(1)
        return {
            point = point or "CENTER",
            x = x or 0,
            y = y or 0,
            scale = self:GetScale(),
            anchorMode = self.anchorMode,
        }
    end
    
    if useCenter and width and height then
        -- Save CENTER position (frame expands from center when size changes)
        local centerX = left + (width / 2)
        local centerY = bottom + (height / 2)
        
        return {
            point = "CENTER",
            x = centerX,
            y = centerY,
            scale = self:GetScale(),
            anchorMode = "CENTER",
        }
    else
        -- Default: Save BOTTOMLEFT position (original behavior)
        return {
            point = "BOTTOMLEFT",
            x = left,
            y = bottom,
            scale = self:GetScale(),
            anchorMode = "BOTTOMLEFT",
        }
    end
end

function TUIFrame:LoadSaveData(data)
    if not data then return end
    
    -- Don't modify protected frames during combat
    if InCombatLockdown() then return end
    
    -- Restore anchor mode preference
    self.anchorMode = data.anchorMode or "BOTTOMLEFT"
    
    -- Handle case where we have x/y coordinates but no point
    local point = data.point
    if not point then
        if data.x and data.y then
            point = "BOTTOMLEFT"
        else
            return
        end
    end
    
    -- Always position relative to UIParent (absolute positioning)
    self:SetPosition(point, UIParent, point, data.x, data.y)
    
    if data.scale then
        self:SetScale(data.scale)
    end
    
    -- Apply matched sizes if present (from previous size-matched attachment)
    if data.matchedWidth or data.matchedHeight then
        local currentWidth, currentHeight = self:GetSize()
        local newWidth = data.matchedWidth or currentWidth
        local newHeight = data.matchedHeight or currentHeight
        self:ForceSetSize(newWidth, newHeight)
        
        -- Re-anchor children for bar-type frames to stretch with new size
        if self.category and (self.category:find("Bar") or self.category:find("bar")) then
            local children = { self.frame:GetChildren() }
            for _, child in ipairs(children) do
                child:ClearAllPoints()
                child:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
                child:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
            end
        end
    end
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

function TUIFrame:Destroy()
    -- Unregister from FlyPaper
    if FlyPaper then
        FlyPaper.RemoveFrame(FLYPAPER_GROUP, self.id)
    end
    
    -- Restore content
    self:RestoreContent()
    
    -- Remove from registry
    frameRegistry[self.id] = nil
    
    -- Hide frame
    self.frame:Hide()
end

-- ============================================================================
-- STATIC METHODS
-- ============================================================================

function TUIFrame.Get(id)
    return frameRegistry[id]
end

function TUIFrame.GetAll()
    return frameRegistry
end

function TUIFrame.GetByCategory(category)
    local result = {}
    for id, tuiFrame in pairs(frameRegistry) do
        if tuiFrame.category == category then
            result[id] = tuiFrame
        end
    end
    return result
end

function TUIFrame.Exists(id)
    return frameRegistry[id] ~= nil
end

function TUIFrame.GetFlyPaperGroup()
    return FLYPAPER_GROUP
end

-- ============================================================================
-- DEBUG
-- ============================================================================

function TUIFrame.DebugDump()
    print("=== TUIFrame Registry ===")
    print(string.format("FlyPaper loaded: %s", FlyPaper and "yes" or "NO"))
    
    local count = 0
    for id, tuiFrame in pairs(frameRegistry) do
        local point, _, _, x, y = tuiFrame.frame:GetPoint(1)
        print(string.format("  %s [%s]: %s %.0f,%.0f shown=%s",
            id,
            tuiFrame.category,
            point or "?",
            x or 0,
            y or 0,
            tuiFrame:IsShown() and "yes" or "no"
        ))
        count = count + 1
    end
    
    if count == 0 then
        print("  (no frames registered)")
    end
    print(string.format("Total: %d frames", count))
end

SLASH_TUIFRAMEDEBUG1 = "/tuiframedebug"
SlashCmdList["TUIFRAMEDEBUG"] = TUIFrame.DebugDump
