-- ============================================================================
-- TUICD: LayoutUI
-- Visual components for Layout Mode - overlays, grid, snap indicators
-- ============================================================================

local ADDON_NAME, TUICD = ...

local LayoutUI = {}
TUICD.LayoutUI = LayoutUI

local Layout  -- Set after Layout module loads

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local COLORS = {
    -- Overlay colors
    overlayBorder = { 0.4, 0.4, 0.4, 0.9 },
    overlayBorderHover = { 0.6, 0.8, 1.0, 1.0 },
    overlayBorderSelected = { 0.2, 1.0, 0.4, 1.0 },       -- Green - selected frame
    overlayBorderDragging = { 1.0, 0.8, 0.2, 1.0 },
    overlayBackground = { 0.1, 0.1, 0.1, 0.3 },
    overlayBackgroundSelected = { 0.2, 0.4, 0.2, 0.4 },
    
    -- Attachment visualization colors (1.7.5+)
    overlayBorderRoot = { 1.0, 0.5, 0.0, 1.0 },           -- Orange - root/mother frame
    overlayBackgroundRoot = { 0.4, 0.2, 0.0, 0.3 },
    overlayBorderParent = { 1.0, 0.7, 0.2, 1.0 },         -- Yellow-orange - parent in chain
    overlayBackgroundParent = { 0.3, 0.25, 0.1, 0.3 },
    overlayBorderChild = { 0.0, 0.8, 1.0, 1.0 },          -- Cyan - child frames
    overlayBackgroundChild = { 0.0, 0.2, 0.3, 0.3 },
    
    -- Label colors
    labelText = { 1, 1, 1, 1 },
    labelBackground = { 0, 0, 0, 0.7 },
    
    -- Grid colors
    gridLine = { 0.4, 0.4, 0.4, 0.5 },
    gridLineCenter = { 0.8, 0.8, 0.2, 0.8 },
    
    -- Snap indicator
    snapIndicator = { 0.2, 1.0, 0.4, 0.8 },
}

local OVERLAY_BORDER_SIZE = 2
local LABEL_PADDING = 4

-- ============================================================================
-- STATE
-- ============================================================================

local overlays = {}  -- Keyed by element ID
local gridFrame = nil
local snapIndicator = nil
local containerFrame = nil  -- Parent for all layout UI
local nearbyHighlightId = nil  -- Currently highlighted nearby element during drag
LayoutUI.autoSnapEnabled = false  -- Auto-snap toggle state

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function LayoutUI:Initialize()
    Layout = TUICD.Layout
    
    -- Create container frame for all layout UI elements
    containerFrame = CreateFrame("Frame", "TweaksUI_LayoutContainer", UIParent)
    containerFrame:SetFrameStrata("TOOLTIP")  -- Highest strata for layout mode
    containerFrame:SetAllPoints()
    containerFrame:EnableMouse(false)  -- CRITICAL: Prevent mouse blocking when hidden
    containerFrame:Hide()
    
    -- CRITICAL: Hook OnShow/OnHide to handle addon conflicts (e.g., DialogueUI)
    -- When UIParent is hidden/shown by other addons, frames can get into bad states
    containerFrame:HookScript("OnShow", function(self)
        -- Only enable mouse when Layout mode is actually active
        if not Layout or not Layout:IsActive() then
            self:EnableMouse(false)
            self:Hide()
        end
    end)
    
    containerFrame:HookScript("OnHide", function(self)
        -- Always ensure mouse is disabled when hidden
        self:EnableMouse(false)
    end)
    
    -- Enable keyboard input for arrow key nudging
    containerFrame:EnableKeyboard(true)
    
    containerFrame:SetScript("OnKeyDown", function(self, key)
        -- Arrow key nudging - only handle if we have a selection
        local selectedId = Layout:GetSelectedElement()
        if selectedId then
            local amount = IsShiftKeyDown() and 10 or 1
            if key == "UP" then
                LayoutUI:NudgeSelected(0, amount)
                self:SetPropagateKeyboardInput(false)
                return
            elseif key == "DOWN" then
                LayoutUI:NudgeSelected(0, -amount)
                self:SetPropagateKeyboardInput(false)
                return
            elseif key == "LEFT" then
                LayoutUI:NudgeSelected(-amount, 0)
                self:SetPropagateKeyboardInput(false)
                return
            elseif key == "RIGHT" then
                LayoutUI:NudgeSelected(amount, 0)
                self:SetPropagateKeyboardInput(false)
                return
            end
        end
        -- Let all other keys through (including Escape to exit)
        self:SetPropagateKeyboardInput(true)
    end)
    
    -- Create grid
    self:CreateGrid()
    
    -- Create snap indicator
    self:CreateSnapIndicator()
end

-- ============================================================================
-- KEYBINDING OVERRIDES (prevent character movement in Layout mode)
-- ============================================================================

local savedBindings = {}

function LayoutUI:OverrideMovementBindings()
    -- Save and clear movement keybindings
    local keysToOverride = { "UP", "DOWN", "LEFT", "RIGHT" }
    
    for _, key in ipairs(keysToOverride) do
        -- Save current binding
        local action = GetBindingAction(key)
        if action and action ~= "" then
            savedBindings[key] = action
        end
        -- Clear the binding temporarily
        SetOverrideBinding(containerFrame, true, key, nil)
    end
end

function LayoutUI:RestoreMovementBindings()
    -- Restore movement keybindings
    ClearOverrideBindings(containerFrame)
    savedBindings = {}
end

-- ============================================================================
-- CONTAINER MANAGEMENT
-- ============================================================================

function LayoutUI:ShowOverlays()
    if not containerFrame then
        self:Initialize()
    end
    
    -- Re-enable keyboard input (may have been disabled on hide)
    containerFrame:EnableKeyboard(true)
    containerFrame:Show()
    
    -- Override movement keybindings so arrows don't move character
    self:OverrideMovementBindings()
    
    -- Create overlays for all registered elements
    local elements = Layout:GetAllElements()
    
    for id, element in pairs(elements) do
        self:CreateOverlay(element)
    end
    
    -- Update grid
    self:UpdateGrid()
    
    -- Show coordinate panel
    self:ShowCoordPanel()
    
    -- Delayed overlay position update to catch frames that need time to settle
    -- (e.g., cooldown trackers that update size after icons populate)
    C_Timer.After(0.2, function()
        self:UpdateAllOverlays()
    end)
end

function LayoutUI:HideOverlays()
    if not containerFrame then return end
    
    -- Explicitly disable keyboard to ensure it's released
    containerFrame:EnableKeyboard(false)
    containerFrame:EnableMouse(false)  -- CRITICAL: Ensure mouse is disabled
    containerFrame:Hide()
    
    -- Restore movement keybindings
    self:RestoreMovementBindings()
    
    -- Hide all overlays and disable their mouse (don't destroy, reuse them)
    for id, overlay in pairs(overlays) do
        overlay:EnableMouse(false)  -- CRITICAL: Prevent mouse blocking
        overlay:Hide()
    end
    
    -- Hide snap indicator
    if snapIndicator then
        snapIndicator:EnableMouse(false)
        snapIndicator:Hide()
    end
    
    -- Hide element selection list directly (it's parented to UIParent, not coordPanel)
    if TweaksUI_ElementList then
        TweaksUI_ElementList:Hide()
    end
    
    -- Hide coordinate panel
    self:HideCoordPanel()
end

function LayoutUI:UpdateAllOverlays()
    for id, element in pairs(Layout:GetAllElements()) do
        self:UpdateOverlayPosition(element)
    end
end

-- ============================================================================
-- OVERLAY CREATION
-- ============================================================================

-- Check if an element ID corresponds to a docked cooldown icon
local function IsElementDocked(elementId)
    if not elementId then return false end
    
    local Docks = TUICD.Docks
    if not Docks or not Docks.IsIconDocked then return false end
    
    -- Parse element ID to extract tracker type and slot index
    -- Patterns: TweaksUI_EssentialHighlight_N, TweaksUI_UtilityHighlight_N, 
    --           TweaksUI_CustomHighlight_N, BuffHighlight_N
    local trackerKey, slotIndex
    
    slotIndex = elementId:match("^TweaksUI_EssentialHighlight_(%d+)$")
    if slotIndex then
        trackerKey = "essential"
    end
    
    if not trackerKey then
        slotIndex = elementId:match("^TweaksUI_UtilityHighlight_(%d+)$")
        if slotIndex then
            trackerKey = "utility"
        end
    end
    
    if not trackerKey then
        slotIndex = elementId:match("^TweaksUI_CustomHighlight_(%d+)$")
        if slotIndex then
            trackerKey = "customTrackers"
        end
    end
    
    if not trackerKey then
        slotIndex = elementId:match("^BuffHighlight_(%d+)$")
        if slotIndex then
            trackerKey = "buffs"
        end
    end
    
    if trackerKey and slotIndex then
        return Docks:IsIconDocked(trackerKey, tonumber(slotIndex))
    end
    
    return false
end

function LayoutUI:CreateOverlay(element)
    if not element or not element.tuiFrame then return end
    
    local id = element.id
    
    -- Skip overlay for icons that are docked (dock itself handles positioning)
    local dockIndex = IsElementDocked(id)
    if dockIndex then
        -- If there's an existing overlay, hide it
        if overlays[id] then
            overlays[id]:EnableMouse(false)
            overlays[id]:Hide()
        end
        return nil
    end
    
    -- Reuse existing overlay if available
    local overlay = overlays[id]
    if not overlay then
        overlay = self:BuildOverlayFrame(element)
        overlays[id] = overlay
    else
        -- Re-enable mouse on reused overlay (may have been disabled by HideOverlays)
        overlay:EnableMouse(true)
    end
    
    -- Update overlay to match current element state
    self:UpdateOverlayPosition(element)
    overlay.elementId = id
    overlay.label:SetText(element.name)
    
    -- Show if element's TUIFrame is shown
    local isShown = element.tuiFrame:IsShown()
    if isShown then
        overlay:Show()
    else
        overlay:Hide()
    end
    
    return overlay
end

function LayoutUI:BuildOverlayFrame(element)
    local overlay = CreateFrame("Frame", nil, containerFrame, "BackdropTemplate")
    overlay:SetFrameStrata("TOOLTIP")  -- Highest strata to ensure it's always on top
    overlay:SetFrameLevel(1000)
    overlay:SetToplevel(true)  -- Ensure this is always on top of other frames at same strata
    
    -- Backdrop for border and background
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = OVERLAY_BORDER_SIZE,
    })
    overlay:SetBackdropColor(unpack(COLORS.overlayBackground))
    overlay:SetBackdropBorderColor(unpack(COLORS.overlayBorder))
    
    -- Label background
    local labelBg = overlay:CreateTexture(nil, "BACKGROUND")
    labelBg:SetColorTexture(unpack(COLORS.labelBackground))
    overlay.labelBg = labelBg
    
    -- Label text
    local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetTextColor(unpack(COLORS.labelText))
    label:SetPoint("BOTTOM", overlay, "TOP", 0, 4)
    overlay.label = label
    
    -- Position label background around text
    labelBg:SetPoint("TOPLEFT", label, "TOPLEFT", -LABEL_PADDING, LABEL_PADDING)
    labelBg:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", LABEL_PADDING, -LABEL_PADDING)
    
    -- Make interactive
    overlay:EnableMouse(true)
    overlay:SetMovable(true)
    overlay:RegisterForDrag("LeftButton")
    
    -- State tracking
    overlay.isDragging = false
    overlay.isHovered = false
    overlay.isSelected = false
    
    -- Event handlers
    overlay:SetScript("OnEnter", function(self)
        self.isHovered = true
        LayoutUI:UpdateOverlayAppearance(self)
    end)
    
    overlay:SetScript("OnLeave", function(self)
        self.isHovered = false
        LayoutUI:UpdateOverlayAppearance(self)
    end)
    
    overlay:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            Layout:SelectElement(self.elementId)
        elseif button == "RightButton" then
            -- Could show context menu in future
        end
    end)
    
    overlay:SetScript("OnDragStart", function(self)
        self.isDragging = true
        LayoutUI:UpdateOverlayAppearance(self)
        LayoutUI:StartDrag(self.elementId)
    end)
    
    overlay:SetScript("OnDragStop", function(self)
        self.isDragging = false
        LayoutUI:UpdateOverlayAppearance(self)
        LayoutUI:StopDrag(self.elementId)
    end)
    
    return overlay
end

function LayoutUI:UpdateOverlayPosition(element)
    if not element or not element.tuiFrame then return end
    
    local overlay = overlays[element.id]
    if not overlay then return end
    
    local frame = element.tuiFrame.frame
    
    -- Match position and size of the TUIFrame
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
end

function LayoutUI:UpdateOverlayAppearance(overlay)
    if not overlay then return end
    
    local borderColor
    local bgColor
    
    if overlay.isDragging then
        borderColor = COLORS.overlayBorderDragging
        bgColor = COLORS.overlayBackgroundSelected
    elseif overlay.isSelected then
        borderColor = COLORS.overlayBorderSelected
        bgColor = COLORS.overlayBackgroundSelected
    elseif overlay.isNearbyTarget then
        -- Nearby target for potential locking (bright yellow/gold pulse effect)
        borderColor = {1.0, 0.9, 0.0, 1.0}  -- Bright yellow border
        bgColor = {1.0, 0.8, 0.0, 0.35}  -- Yellow-gold background
    elseif overlay.isRoot then
        -- Root/mother frame of the attachment chain (orange)
        borderColor = COLORS.overlayBorderRoot
        bgColor = COLORS.overlayBackgroundRoot
    elseif overlay.isParentInChain then
        -- Parent frame in the chain between selected and root (yellow-orange)
        borderColor = COLORS.overlayBorderParent
        bgColor = COLORS.overlayBackgroundParent
    elseif overlay.isChild then
        -- Child frame attached to selected frame (cyan)
        borderColor = COLORS.overlayBorderChild
        bgColor = COLORS.overlayBackgroundChild
    elseif overlay.isHovered then
        borderColor = COLORS.overlayBorderHover
        bgColor = COLORS.overlayBackground
    else
        borderColor = COLORS.overlayBorder
        bgColor = COLORS.overlayBackground
    end
    
    overlay:SetBackdropBorderColor(unpack(borderColor))
    overlay:SetBackdropColor(unpack(bgColor))
end

function LayoutUI:SetElementSelected(id, selected)
    local overlay = overlays[id]
    if overlay then
        overlay.isSelected = selected
        self:UpdateOverlayAppearance(overlay)
    end
    
    -- Update attachment visualization when selection changes
    if selected then
        -- Clear dropdown selection when selecting a new element
        if coordPanel then
            coordPanel.selectedParentId = nil
            coordPanel.useCustomParent = false
        end
        self:UpdateAttachmentVisualization(id)
    else
        -- Clear attachment visualization when deselecting
        self:ClearAttachmentVisualization()
    end
end

-- Clear all attachment visualization states
function LayoutUI:ClearAttachmentVisualization()
    for elementId, overlay in pairs(overlays) do
        if overlay.isRoot or overlay.isParentInChain or overlay.isChild then
            overlay.isRoot = false
            overlay.isParentInChain = false
            overlay.isChild = false
            self:UpdateOverlayAppearance(overlay)
        end
    end
end

-- Highlight a nearby element that could be locked to
function LayoutUI:HighlightNearbyElement(elementId)
    -- Clear previous highlight if different
    if nearbyHighlightId and nearbyHighlightId ~= elementId then
        self:ClearNearbyHighlight()
    end
    
    local overlay = overlays[elementId]
    if overlay then
        nearbyHighlightId = elementId
        overlay.isNearbyTarget = true
        self:UpdateOverlayAppearance(overlay)
    end
end

-- Clear the nearby element highlight
function LayoutUI:ClearNearbyHighlight()
    if nearbyHighlightId then
        local overlay = overlays[nearbyHighlightId]
        if overlay then
            overlay.isNearbyTarget = false
            self:UpdateOverlayAppearance(overlay)
        end
        nearbyHighlightId = nil
    end
end

-- Update attachment visualization for selected frame
function LayoutUI:UpdateAttachmentVisualization(selectedId)
    -- First clear all existing visualization
    self:ClearAttachmentVisualization()
    
    local SnapLocking = TUICD.SnapLocking
    if not SnapLocking then return end
    
    -- Don't highlight if the selected frame isn't in a locked group
    if not SnapLocking:IsInLockedGroup(selectedId) then return end
    
    -- Get the ENTIRE connected group (all frames in the tree)
    local allGroupIds = SnapLocking:GetConnectedGroup(selectedId)
    if not allGroupIds or #allGroupIds <= 1 then return end
    
    -- Get the root of the chain
    local rootId = SnapLocking:GetChainRoot(selectedId)
    
    -- Build the parent chain from selected to root (ancestors)
    local parentChain = {}
    local currentId = selectedId
    while currentId do
        local parentId = SnapLocking:GetParentId(currentId)
        if parentId and parentId ~= currentId then
            parentChain[parentId] = true
            currentId = parentId
        else
            break
        end
    end
    
    -- Get direct descendants of selected frame
    local descendants = {}
    local descendantList = SnapLocking:GetDescendants(selectedId) or {}
    for _, descId in ipairs(descendantList) do
        descendants[descId] = true
    end
    
    -- Now highlight ALL frames in the group with appropriate colors
    for _, frameId in ipairs(allGroupIds) do
        if frameId ~= selectedId then  -- Skip selected frame (already green)
            local overlay = overlays[frameId]
            if overlay then
                if frameId == rootId then
                    -- Root/mother frame (orange)
                    overlay.isRoot = true
                    overlay.isParentInChain = false
                    overlay.isChild = false
                elseif parentChain[frameId] then
                    -- Parent in chain between selected and root (yellow-orange)
                    overlay.isRoot = false
                    overlay.isParentInChain = true
                    overlay.isChild = false
                else
                    -- Everything else: descendants, siblings, other branches (cyan)
                    overlay.isRoot = false
                    overlay.isParentInChain = false
                    overlay.isChild = true
                end
                self:UpdateOverlayAppearance(overlay)
            end
        end
    end
    
    -- Debug output
    if TUICD.debugMode then
        local parentCount = 0
        for _ in pairs(parentChain) do parentCount = parentCount + 1 end
        TUICD:PrintDebug("LayoutUI: Attachment visualization for " .. selectedId)
        TUICD:PrintDebug("  Total group size: " .. #allGroupIds)
        TUICD:PrintDebug("  Root: " .. (rootId or "none"))
        TUICD:PrintDebug("  Parents in chain: " .. parentCount)
        TUICD:PrintDebug("  Descendants: " .. #descendantList)
    end
end

-- ============================================================================
-- DRAG HANDLING
-- ============================================================================

function LayoutUI:StartDrag(elementId)
    local element = Layout:GetElement(elementId)
    if not element or not element.tuiFrame then return end
    
    local frame = element.tuiFrame.frame
    local overlay = overlays[elementId]
    
    -- Check if this frame is part of a locked group
    -- IMPORTANT: Docks are excluded from locked group movement - they always drag independently
    local SnapLocking = TUICD.SnapLocking
    local isInLockedGroup = SnapLocking and SnapLocking:IsInLockedGroup(elementId)
    
    -- Docks should NEVER be treated as part of a locked group
    local isDock = elementId and elementId:match("Dock")
    if isDock then
        isInLockedGroup = false
    end
    
    if isInLockedGroup then
        -- Get the entire connected group (ALL frames in the chain)
        local groupIds = SnapLocking:GetConnectedGroup(elementId)
        
        -- Debug output
        if TUICD.PrintDebug then
            TUICD:PrintDebug("LayoutUI: Starting drag on locked group")
            TUICD:PrintDebug("  Dragged frame: " .. elementId)
            TUICD:PrintDebug("  Group members: " .. table.concat(groupIds, ", "))
        end
        
        -- Verify all frames exist and warn about missing ones
        local validGroupIds = {}
        for _, frameId in ipairs(groupIds) do
            local tui = SnapLocking:GetTUIFrame(frameId)
            if tui and tui.frame then
                table.insert(validGroupIds, frameId)
            else
                if TUICD.PrintDebug then
                    TUICD:PrintDebug("  WARNING: Frame not found: " .. frameId)
                end
            end
        end
        
        overlay.lockedGroup = validGroupIds
        overlay.groupOffsets = SnapLocking:GetGroupOffsets(validGroupIds, elementId)
        overlay.isDraggingLockedGroup = true
        
        if TUICD.PrintDebug then
            local offsetCount = 0
            for _ in pairs(overlay.groupOffsets) do offsetCount = offsetCount + 1 end
            TUICD:PrintDebug("  Valid frames: " .. #validGroupIds .. ", Offsets calculated: " .. offsetCount)
        end
    else
        overlay.lockedGroup = nil
        overlay.groupOffsets = nil
        overlay.isDraggingLockedGroup = false
    end
    
    -- Start moving the actual TUIFrame
    frame:StartMoving()
    
    -- Start update ticker for snap detection
    overlay.dragTicker = C_Timer.NewTicker(0.016, function()
        self:OnDragUpdate(elementId)
    end)
end

function LayoutUI:StopDrag(elementId)
    local element = Layout:GetElement(elementId)
    if not element or not element.tuiFrame then return end
    
    local frame = element.tuiFrame.frame
    local overlay = overlays[elementId]
    
    -- Stop the ticker
    if overlay.dragTicker then
        overlay.dragTicker:Cancel()
        overlay.dragTicker = nil
    end
    
    -- Stop moving
    frame:StopMovingOrSizing()
    
    -- Check if we were dragging a locked group
    local wasDraggingLockedGroup = overlay.isDraggingLockedGroup
    local lockedGroup = overlay.lockedGroup
    
    -- Clear drag state
    overlay.lockedGroup = nil
    overlay.groupOffsets = nil
    overlay.isDraggingLockedGroup = false
    
    if wasDraggingLockedGroup and lockedGroup then
        -- Save positions for ALL frames in the group
        for _, frameId in ipairs(lockedGroup) do
            Layout:SaveElementPosition(frameId)
            
            -- Update overlay position
            local groupElement = Layout:GetElement(frameId)
            if groupElement then
                self:UpdateOverlayPosition(groupElement)
            end
        end
        
        -- Re-apply attachment relationships so relative positions are maintained
        local SnapLocking = TUICD.SnapLocking
        if SnapLocking then
            -- Update the stored offsets in attachments based on new positions
            for _, frameId in ipairs(lockedGroup) do
                local attachment = SnapLocking:GetAttachment(frameId)
                if attachment then
                    local childTUI = SnapLocking:GetTUIFrame(frameId)
                    local parentTUI = SnapLocking:GetTUIFrame(attachment.parentId)
                    if childTUI and parentTUI then
                        local childFrame = childTUI.frame
                        local parentFrame = parentTUI.frame
                        local childLeft, childBottom = childFrame:GetLeft(), childFrame:GetBottom()
                        local parentLeft, parentBottom = parentFrame:GetLeft(), parentFrame:GetBottom()
                        if childLeft and childBottom and parentLeft and parentBottom then
                            -- Update the offset in the attachment
                            attachment.offsetX = childLeft - parentLeft
                            attachment.offsetY = childBottom - parentBottom
                        end
                    end
                end
            end
            SnapLocking:SaveAttachments()
            
            -- Check for snap target for the ROOT of the group
            -- This allows locking the entire group to a new parent
            local rootId = SnapLocking:GetChainRoot(elementId)
            if rootId then
                self:CheckForSnapTarget(rootId)
            end
        end
    else
        -- Not a locked group - normal behavior
        
        -- Check if auto-snap is enabled and we have a nearby target
        if LayoutUI.autoSnapEnabled and nearbyHighlightId then
            -- Perform auto-snap: align nearest anchor points
            local success = self:PerformAutoSnap(elementId, nearbyHighlightId)
            if success then
                -- Auto-snap handled position saving and pending snap creation
                -- Update overlay position
                self:UpdateOverlayPosition(element)
            else
                -- Auto-snap failed, fall back to normal behavior
                self:CheckForSnapTarget(elementId)
                self:UpdateOverlayPosition(element)
                Layout:SaveElementPosition(elementId)
            end
        else
            -- Normal behavior without auto-snap
            -- Check for snap target and update pending snap for SnapLocking
            self:CheckForSnapTarget(elementId)
            
            -- Update overlay position
            self:UpdateOverlayPosition(element)
            
            -- Save position
            Layout:SaveElementPosition(elementId)
        end
    end
    
    -- Hide snap indicator and clear nearby highlight
    if snapIndicator then
        snapIndicator:Hide()
    end
    self:ClearNearbyHighlight()
    
    -- Update coordinate panel
    self:UpdateCoordDisplay()
    self:UpdateAttachmentDisplay()
end

function LayoutUI:OnDragUpdate(elementId)
    local element = Layout:GetElement(elementId)
    if not element then return end
    
    local overlay = overlays[elementId]
    if not overlay then return end
    
    -- If dragging a locked group, move all connected frames together
    if overlay.isDraggingLockedGroup and overlay.groupOffsets then
        local SnapLocking = TUICD.SnapLocking
        if SnapLocking then
            SnapLocking:MoveGroupWithReference(elementId, overlay.groupOffsets)
            
            -- Update overlays for all frames in the group
            for _, frameId in ipairs(overlay.lockedGroup or {}) do
                local groupElement = Layout:GetElement(frameId)
                if groupElement then
                    self:UpdateOverlayPosition(groupElement)
                end
            end
        end
    end
    
    -- Update overlay position to follow frame
    self:UpdateOverlayPosition(element)
    
    -- Update coordinate panel in real-time
    self:UpdateCoordDisplay()
    
    -- Call element's onDragUpdate callback if it exists (for real-time sync)
    if element.onDragUpdate then
        local frame = element.tuiFrame.frame
        local point, _, relPoint, x, y = frame:GetPoint(1)
        element.onDragUpdate(elementId, {
            point = point,
            relPoint = relPoint,
            x = x,
            y = y,
        })
    end
    
    -- Only check for snap targets if NOT in a locked group
    if not overlay.isDraggingLockedGroup then
        -- Detect nearby elements during drag for visual feedback
        local tolerance = 75  -- 75 pixel tolerance for snap detection
        
        -- Use our custom real-time detection during drag
        local nearbyElementId, nearbyFrame, distance, dragAnchor, targetAnchor = self:FindNearbyElementDuringDrag(elementId, tolerance)
        
        if nearbyElementId and nearbyFrame then
            -- Show snap indicator between dragged frame and nearby frame
            local settings = Layout:GetSnappingSettings()
            if settings and settings.showIndicator then
                self:ShowSnapIndicator(element.tuiFrame.frame, nearbyFrame)
            end
            
            -- Highlight the nearby element's overlay
            self:HighlightNearbyElement(nearbyElementId)
        else
            self:HideSnapIndicator()
            self:ClearNearbyHighlight()
        end
    else
        -- Hide snap indicator when dragging locked group
        self:HideSnapIndicator()
        self:ClearNearbyHighlight()
    end
end

-- Find the element under the mouse cursor and set up pending snap
-- Track last highlighted element to avoid spam
local lastHighlightedElement = nil

function LayoutUI:CheckForSnapTargetAtMouse(draggingElementId)
    local SnapLocking = TUICD.SnapLocking
    if not SnapLocking then return end
    
    -- Skip if already attached AND the attachment is valid
    if SnapLocking:IsAttached(draggingElementId) and SnapLocking:IsAttachmentValid(draggingElementId) then
        return
    end
    
    -- Get mouse position
    local mouseX, mouseY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    mouseX = mouseX / scale
    mouseY = mouseY / scale
    
    local tolerance = 75  -- 75 pixel detection radius
    
    -- Find the closest element to the mouse (excluding the one being dragged)
    local closestElementId = nil
    local closestDistance = tolerance
    
    local allElements = Layout:GetAllElements()
    
    for id, elem in pairs(allElements) do
        if id ~= draggingElementId and elem.tuiFrame and elem.tuiFrame.frame then
            local frame = elem.tuiFrame.frame
            if frame:IsVisible() then
                local left, bottom, width, height = frame:GetRect()
                if left and bottom and width and height then
                    local right = left + width
                    local top = bottom + height
                    local centerX = left + width / 2
                    local centerY = bottom + height / 2
                    
                    -- Check anchor points (corners, edge centers, center)
                    local points = {
                        {left, top}, {right, top}, {left, bottom}, {right, bottom},
                        {centerX, top}, {centerX, bottom}, {left, centerY}, {right, centerY},
                        {centerX, centerY}
                    }
                    
                    local minDist = math.huge
                    for _, pt in ipairs(points) do
                        local dist = math.sqrt((mouseX - pt[1])^2 + (mouseY - pt[2])^2)
                        if dist < minDist then
                            minDist = dist
                        end
                    end
                    
                    if minDist < closestDistance then
                        closestDistance = minDist
                        closestElementId = id
                    end
                end
            end
        end
    end
    
    if closestElementId then
        -- Only print when element changes
        if closestElementId ~= lastHighlightedElement then
            lastHighlightedElement = closestElementId
            TUICD:Print("Near: " .. closestElementId)
        end
        
        -- Found a nearby element - highlight it directly
        local overlay = overlays[closestElementId]
        if overlay then
            -- Clear previous highlight
            if nearbyHighlightId and nearbyHighlightId ~= closestElementId then
                local oldOverlay = overlays[nearbyHighlightId]
                if oldOverlay then
                    oldOverlay.isNearbyTarget = false
                    self:UpdateOverlayAppearance(oldOverlay)
                end
            end
            
            -- Set new highlight
            nearbyHighlightId = closestElementId
            overlay.isNearbyTarget = true
            self:UpdateOverlayAppearance(overlay)
            
            -- Also set pending snap for when drag stops
            local draggingElement = Layout:GetElement(draggingElementId)
            local targetElement = Layout:GetElement(closestElementId)
            if draggingElement and draggingElement.tuiFrame and targetElement and targetElement.tuiFrame then
                local childFrame = draggingElement.tuiFrame.frame
                local parentFrame = targetElement.tuiFrame.frame
                local childLeft, childBottom = childFrame:GetLeft(), childFrame:GetBottom()
                local parentLeft, parentBottom = parentFrame:GetLeft(), parentFrame:GetBottom()
                if childLeft and parentLeft then
                    local offsetX = childLeft - parentLeft
                    local offsetY = childBottom - parentBottom
                    SnapLocking:SetPendingSnap(draggingElementId, closestElementId, "BOTTOMLEFT", "BOTTOMLEFT", offsetX, offsetY)
                end
            end
        end
        return
    end
    
    -- No snap target found - clear highlight
    if nearbyHighlightId then
        local oldOverlay = overlays[nearbyHighlightId]
        if oldOverlay then
            oldOverlay.isNearbyTarget = false
            self:UpdateOverlayAppearance(oldOverlay)
        end
        nearbyHighlightId = nil
        lastHighlightedElement = nil
    end
    
    local pendingSnap = SnapLocking:GetPendingSnap()
    if pendingSnap and pendingSnap.childId == draggingElementId then
        SnapLocking:ClearPendingSnap()
    end
end

-- ============================================================================
-- GRID
-- ============================================================================

function LayoutUI:CreateGrid()
    if gridFrame then return end
    
    gridFrame = CreateFrame("Frame", "TweaksUI_LayoutGrid", containerFrame)
    gridFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    gridFrame:SetFrameLevel(1)  -- Behind overlays
    gridFrame:SetAllPoints()
    gridFrame:EnableMouse(false)  -- Grid should never block mouse
    gridFrame:Hide()
    
    gridFrame.lines = {}
end

function LayoutUI:UpdateGrid()
    if not gridFrame then return end
    
    local settings = Layout:GetGridSettings()
    
    if not settings.enabled or not settings.showLines then
        gridFrame:Hide()
        return
    end
    
    -- Clear existing lines
    for _, line in ipairs(gridFrame.lines) do
        line:Hide()
    end
    
    -- Use UIParent dimensions to match coordinate system
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    local gridSize = settings.size
    local lineIndex = 1
    
    -- Center point is 0,0 in our coordinate system
    local centerX = screenWidth / 2
    local centerY = screenHeight / 2
    
    -- Draw vertical center line (the Y axis - at x=0)
    local line = gridFrame.lines[lineIndex]
    if not line then
        line = gridFrame:CreateLine(nil, "BACKGROUND")
        gridFrame.lines[lineIndex] = line
    end
    line:SetThickness(2)
    line:SetColorTexture(unpack(COLORS.gridLineCenter))
    line:SetStartPoint("BOTTOMLEFT", gridFrame, centerX, 0)
    line:SetEndPoint("TOPLEFT", gridFrame, centerX, screenHeight)
    line:Show()
    lineIndex = lineIndex + 1
    
    -- Draw horizontal center line (the X axis - at y=0)
    line = gridFrame.lines[lineIndex]
    if not line then
        line = gridFrame:CreateLine(nil, "BACKGROUND")
        gridFrame.lines[lineIndex] = line
    end
    line:SetThickness(2)
    line:SetColorTexture(unpack(COLORS.gridLineCenter))
    line:SetStartPoint("BOTTOMLEFT", gridFrame, 0, centerY)
    line:SetEndPoint("BOTTOMRIGHT", gridFrame, screenWidth, centerY)
    line:Show()
    lineIndex = lineIndex + 1
    
    -- Draw vertical lines from center outward (positive X direction)
    for offset = gridSize, centerX, gridSize do
        line = gridFrame.lines[lineIndex]
        if not line then
            line = gridFrame:CreateLine(nil, "BACKGROUND")
            gridFrame.lines[lineIndex] = line
        end
        line:SetThickness(1)
        line:SetColorTexture(unpack(COLORS.gridLine))
        line:SetStartPoint("BOTTOMLEFT", gridFrame, centerX + offset, 0)
        line:SetEndPoint("TOPLEFT", gridFrame, centerX + offset, screenHeight)
        line:Show()
        lineIndex = lineIndex + 1
    end
    
    -- Draw vertical lines from center outward (negative X direction)
    for offset = gridSize, centerX, gridSize do
        line = gridFrame.lines[lineIndex]
        if not line then
            line = gridFrame:CreateLine(nil, "BACKGROUND")
            gridFrame.lines[lineIndex] = line
        end
        line:SetThickness(1)
        line:SetColorTexture(unpack(COLORS.gridLine))
        line:SetStartPoint("BOTTOMLEFT", gridFrame, centerX - offset, 0)
        line:SetEndPoint("TOPLEFT", gridFrame, centerX - offset, screenHeight)
        line:Show()
        lineIndex = lineIndex + 1
    end
    
    -- Draw horizontal lines from center outward (positive Y direction)
    for offset = gridSize, centerY, gridSize do
        line = gridFrame.lines[lineIndex]
        if not line then
            line = gridFrame:CreateLine(nil, "BACKGROUND")
            gridFrame.lines[lineIndex] = line
        end
        line:SetThickness(1)
        line:SetColorTexture(unpack(COLORS.gridLine))
        line:SetStartPoint("BOTTOMLEFT", gridFrame, 0, centerY + offset)
        line:SetEndPoint("BOTTOMRIGHT", gridFrame, screenWidth, centerY + offset)
        line:Show()
        lineIndex = lineIndex + 1
    end
    
    -- Draw horizontal lines from center outward (negative Y direction)
    for offset = gridSize, centerY, gridSize do
        line = gridFrame.lines[lineIndex]
        if not line then
            line = gridFrame:CreateLine(nil, "BACKGROUND")
            gridFrame.lines[lineIndex] = line
        end
        line:SetThickness(1)
        line:SetColorTexture(unpack(COLORS.gridLine))
        line:SetStartPoint("BOTTOMLEFT", gridFrame, 0, centerY - offset)
        line:SetEndPoint("BOTTOMRIGHT", gridFrame, screenWidth, centerY - offset)
        line:Show()
        lineIndex = lineIndex + 1
    end
    
    gridFrame:Show()
end

-- ============================================================================
-- SNAP INDICATOR
-- ============================================================================

function LayoutUI:CreateSnapIndicator()
    if snapIndicator then return end
    
    snapIndicator = CreateFrame("Frame", "TweaksUI_SnapIndicator", containerFrame)
    snapIndicator:SetFrameStrata("FULLSCREEN_DIALOG")
    snapIndicator:SetFrameLevel(200)
    snapIndicator:EnableMouse(false)  -- Snap indicator should never block mouse
    snapIndicator:Hide()
    
    -- Create line to show connection
    local line = snapIndicator:CreateLine(nil, "OVERLAY")
    line:SetThickness(2)
    line:SetColorTexture(unpack(COLORS.snapIndicator))
    snapIndicator.line = line
    
    -- Create glow around target
    local glow = CreateFrame("Frame", nil, snapIndicator, "BackdropTemplate")
    glow:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 3,
    })
    glow:SetBackdropBorderColor(unpack(COLORS.snapIndicator))
    snapIndicator.glow = glow
end

function LayoutUI:ShowSnapIndicator(sourceFrame, targetFrame)
    if not snapIndicator or not sourceFrame or not targetFrame then return end
    
    -- Position glow around target
    snapIndicator.glow:ClearAllPoints()
    snapIndicator.glow:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -3, 3)
    snapIndicator.glow:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", 3, -3)
    snapIndicator.glow:Show()
    
    -- Draw line between centers
    local sx = sourceFrame:GetCenter()
    local sy = select(2, sourceFrame:GetCenter())
    local tx = targetFrame:GetCenter()
    local ty = select(2, targetFrame:GetCenter())
    
    if sx and sy and tx and ty then
        snapIndicator.line:SetStartPoint("CENTER", UIParent, sx - GetScreenWidth()/2, sy - GetScreenHeight()/2)
        snapIndicator.line:SetEndPoint("CENTER", UIParent, tx - GetScreenWidth()/2, ty - GetScreenHeight()/2)
        snapIndicator.line:Show()
    else
        snapIndicator.line:Hide()
    end
    
    snapIndicator:Show()
end

function LayoutUI:HideSnapIndicator()
    if snapIndicator then
        snapIndicator:Hide()
    end
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

function LayoutUI:DestroyOverlay(id)
    local overlay = overlays[id]
    if overlay then
        overlay:Hide()
        overlays[id] = nil
    end
end

function LayoutUI:DestroyAllOverlays()
    for id in pairs(overlays) do
        self:DestroyOverlay(id)
    end
end

-- ============================================================================
-- COORDINATE PANEL
-- ============================================================================

local coordPanel = nil
local coordPanelSelectedAnchor = "CENTER"

-- Convert from frame screen coordinates to CENTER-based (screen center = 0,0)
local function ToCenterCoords(left, bottom, width, height, anchor)
    -- UIParent dimensions are what frame positions are relative to
    local screenW = UIParent:GetWidth()
    local screenH = UIParent:GetHeight()
    local centerX, centerY = screenW / 2, screenH / 2
    
    -- Get the position of the specified anchor point in UI coords
    local anchorX, anchorY
    if anchor == "BOTTOMLEFT" then
        anchorX, anchorY = left, bottom
    elseif anchor == "BOTTOMRIGHT" then
        anchorX, anchorY = left + width, bottom
    elseif anchor == "TOPLEFT" then
        anchorX, anchorY = left, bottom + height
    elseif anchor == "TOPRIGHT" then
        anchorX, anchorY = left + width, bottom + height
    elseif anchor == "CENTER" then
        anchorX, anchorY = left + width/2, bottom + height/2
    else
        anchorX, anchorY = left + width/2, bottom + height/2
    end
    
    -- Convert to center-based coords (positive right/up, negative left/down)
    return anchorX - centerX, anchorY - centerY
end

-- Convert from CENTER-based coordinates back to frame BOTTOMLEFT position
local function FromCenterCoords(cx, cy, width, height, anchor)
    local screenW = UIParent:GetWidth()
    local screenH = UIParent:GetHeight()
    local centerX, centerY = screenW / 2, screenH / 2
    
    -- Convert center coords to UI coords for the anchor point
    local anchorX, anchorY = cx + centerX, cy + centerY
    
    -- Calculate BOTTOMLEFT position from anchor position
    local blX, blY
    if anchor == "BOTTOMLEFT" then
        blX, blY = anchorX, anchorY
    elseif anchor == "BOTTOMRIGHT" then
        blX, blY = anchorX - width, anchorY
    elseif anchor == "TOPLEFT" then
        blX, blY = anchorX, anchorY - height
    elseif anchor == "TOPRIGHT" then
        blX, blY = anchorX - width, anchorY - height
    elseif anchor == "CENTER" then
        blX, blY = anchorX - width/2, anchorY - height/2
    else
        blX, blY = anchorX - width/2, anchorY - height/2
    end
    
    return blX, blY
end

-- Nudge selected element by pixels
function LayoutUI:NudgeSelected(dx, dy)
    local selectedId, element = Layout:GetSelectedElement()
    if not selectedId or not element or not element.tuiFrame then return end
    
    local frame = element.tuiFrame.frame
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    
    if not left or not bottom then return end
    
    local SnapLocking = TUICD.SnapLocking
    
    -- Check if this frame is a CHILD (attached to something)
    local attachment = SnapLocking and SnapLocking:GetAttachment(selectedId)
    
    if TUICD.debugMode then
        TUICD:PrintDebug("NudgeSelected: " .. selectedId)
        TUICD:PrintDebug("  Has attachment (is child): " .. tostring(attachment ~= nil))
        if SnapLocking then
            TUICD:PrintDebug("  IsInLockedGroup: " .. tostring(SnapLocking:IsInLockedGroup(selectedId)))
        end
    end
    
    if attachment then
        -- This is a locked child - adjust its offset relative to parent
        -- Move this frame
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + dx, bottom + dy)
        
        -- Update the offset in the attachment
        local parentTUI = SnapLocking:GetTUIFrame(attachment.parentId)
        if parentTUI then
            local parentFrame = parentTUI.frame
            local parentLeft, parentBottom = parentFrame:GetLeft(), parentFrame:GetBottom()
            if parentLeft and parentBottom then
                attachment.offsetX = (left + dx) - parentLeft
                attachment.offsetY = (bottom + dy) - parentBottom
                SnapLocking:SaveAttachments()
            end
        end
        
        -- Also move any descendants of this frame (children attached to this frame)
        local descendants = SnapLocking:GetDescendants(selectedId) or {}
        for _, descId in ipairs(descendants) do
            local descTUI = SnapLocking:GetTUIFrame(descId)
            if descTUI then
                local descFrame = descTUI.frame
                local descLeft, descBottom = descFrame:GetLeft(), descFrame:GetBottom()
                if descLeft and descBottom then
                    descFrame:ClearAllPoints()
                    descFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", descLeft + dx, descBottom + dy)
                end
            end
            
            -- Update overlay for descendant
            local descElement = Layout:GetElement(descId)
            if descElement then
                self:UpdateOverlayPosition(descElement)
            end
            
            -- Save position for descendant
            Layout:SaveElementPosition(descId)
        end
        
        -- Update overlay
        self:UpdateOverlayPosition(element)
        Layout:SaveElementPosition(selectedId)
        self:UpdateCoordDisplay()
        self:UpdateAttachmentDisplay()
        return
    end
    
    -- Check if this frame is a mother/root with children attached
    if SnapLocking and SnapLocking:IsInLockedGroup(selectedId) then
        -- This is a mother frame - move the entire group
        local groupIds = SnapLocking:GetConnectedGroup(selectedId)
        
        if TUICD.debugMode then
            TUICD:PrintDebug("NudgeSelected: Moving mother frame " .. selectedId)
            TUICD:PrintDebug("  Group contains " .. #groupIds .. " frames: " .. table.concat(groupIds, ", "))
        end
        
        -- Move all frames in the group by the same delta
        for _, frameId in ipairs(groupIds) do
            local tui = SnapLocking:GetTUIFrame(frameId)
            if tui then
                local f = tui.frame
                local fLeft, fBottom = f:GetLeft(), f:GetBottom()
                if fLeft and fBottom then
                    f:ClearAllPoints()
                    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", fLeft + dx, fBottom + dy)
                    
                    if TUICD.debugMode then
                        TUICD:PrintDebug("  Moved " .. frameId .. " by (" .. dx .. ", " .. dy .. ")")
                    end
                end
            else
                if TUICD.debugMode then
                    TUICD:PrintDebug("  WARNING: Could not get TUIFrame for " .. frameId)
                end
            end
            
            -- Update overlay
            local groupElement = Layout:GetElement(frameId)
            if groupElement then
                self:UpdateOverlayPosition(groupElement)
            end
            
            -- Save position
            Layout:SaveElementPosition(frameId)
        end
    else
        -- Not locked at all - move just this frame
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + dx, bottom + dy)
        
        -- Update overlay and save
        self:UpdateOverlayPosition(element)
        Layout:SaveElementPosition(selectedId)
    end
    
    self:UpdateCoordDisplay()
    self:UpdateAttachmentDisplay()
end

function LayoutUI:CreateCoordPanel()
    if coordPanel then return coordPanel end
    
    coordPanel = CreateFrame("Frame", "TweaksUI_LayoutCoordPanel", containerFrame, "BackdropTemplate")
    coordPanel:SetSize(220, 750)  -- Increased height for auto-snap section
    coordPanel:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
    coordPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    coordPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    coordPanel:SetMovable(true)
    coordPanel:EnableMouse(true)
    coordPanel:RegisterForDrag("LeftButton")
    coordPanel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    coordPanel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    coordPanel:SetFrameStrata("TOOLTIP")
    coordPanel:SetFrameLevel(9999)  -- Maximum level to always be on top
    coordPanel:SetToplevel(true)  -- Ensure panel stays on top when clicked
    
    -- Raise panel when shown or clicked to stay above overlays
    coordPanel:SetScript("OnShow", function(self)
        self:Raise()
    end)
    coordPanel:HookScript("OnMouseDown", function(self)
        self:Raise()
    end)
    
    -- Title
    local title = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Position")
    title:SetTextColor(0, 1, 0.5)
    coordPanel.title = title
    
    -- Selected element name
    local elementName = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    elementName:SetPoint("TOP", title, "BOTTOM", 0, -4)
    elementName:SetText("No Selection")
    elementName:SetTextColor(0.8, 0.8, 0.8)
    coordPanel.elementName = elementName
    coordPanel.elementName = elementName
    
    -- Anchor selection (radio buttons in a grid pattern)
    local anchorFrame = CreateFrame("Frame", nil, coordPanel)
    anchorFrame:SetSize(90, 60)
    anchorFrame:SetPoint("TOP", elementName, "BOTTOM", 0, -10)
    
    local anchors = {
        { point = "TOPLEFT", x = 0, y = 0 },
        { point = "TOP", x = 35, y = 0 },  -- We'll skip this, using CENTER instead
        { point = "TOPRIGHT", x = 70, y = 0 },
        { point = "LEFT", x = 0, y = -25 },  -- Skip
        { point = "CENTER", x = 35, y = -25 },
        { point = "RIGHT", x = 70, y = -25 },  -- Skip
        { point = "BOTTOMLEFT", x = 0, y = -50 },
        { point = "BOTTOM", x = 35, y = -50 },  -- Skip
        { point = "BOTTOMRIGHT", x = 70, y = -50 },
    }
    
    local anchorButtons = {}
    local usedAnchors = { "TOPLEFT", "TOPRIGHT", "CENTER", "BOTTOMLEFT", "BOTTOMRIGHT" }
    local anchorPositions = {
        TOPLEFT = { x = 0, y = 0 },
        TOPRIGHT = { x = 70, y = 0 },
        CENTER = { x = 35, y = -25 },
        BOTTOMLEFT = { x = 0, y = -50 },
        BOTTOMRIGHT = { x = 70, y = -50 },
    }
    
    for _, anchor in ipairs(usedAnchors) do
        local pos = anchorPositions[anchor]
        local btn = CreateFrame("CheckButton", nil, anchorFrame, "UIRadioButtonTemplate")
        btn:SetPoint("TOPLEFT", pos.x, pos.y)
        btn:SetSize(20, 20)
        btn.anchor = anchor
        
        btn:SetScript("OnClick", function(self)
            coordPanelSelectedAnchor = self.anchor
            LayoutUI:UpdateAnchorButtons()
            LayoutUI:UpdateCoordDisplay()
        end)
        
        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.anchor)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        anchorButtons[anchor] = btn
    end
    
    coordPanel.anchorButtons = anchorButtons
    
    -- Anchor label
    local anchorLabel = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    anchorLabel:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -12)  -- More space after anchor buttons
    anchorLabel:SetText("Anchor Point")
    anchorLabel:SetTextColor(0.6, 0.6, 0.6)
    
    -- X coordinate (centered)
    local xLabel = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xLabel:SetPoint("TOP", anchorLabel, "BOTTOM", -40, -15)
    xLabel:SetText("X:")
    
    local xEdit = CreateFrame("EditBox", nil, coordPanel, "InputBoxTemplate")
    xEdit:SetSize(80, 20)
    xEdit:SetPoint("LEFT", xLabel, "RIGHT", 8, 0)
    xEdit:SetAutoFocus(false)
    xEdit:SetNumeric(false)  -- Allow negative numbers
    xEdit:SetScript("OnEnterPressed", function(self)
        LayoutUI:ApplyCoordInput()
        self:ClearFocus()
    end)
    xEdit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        LayoutUI:UpdateCoordDisplay()
    end)
    coordPanel.xEdit = xEdit
    
    -- Y coordinate (centered, same alignment as X)
    local yLabel = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    yLabel:SetPoint("TOP", xLabel, "BOTTOM", 0, -10)
    yLabel:SetText("Y:")
    
    local yEdit = CreateFrame("EditBox", nil, coordPanel, "InputBoxTemplate")
    yEdit:SetSize(80, 20)
    yEdit:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)
    yEdit:SetAutoFocus(false)
    yEdit:SetNumeric(false)
    yEdit:SetScript("OnEnterPressed", function(self)
        LayoutUI:ApplyCoordInput()
        self:ClearFocus()
    end)
    yEdit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        LayoutUI:UpdateCoordDisplay()
    end)
    coordPanel.yEdit = yEdit
    
    -- Apply button (centered)
    local applyBtn = CreateFrame("Button", nil, coordPanel, "UIPanelButtonTemplate")
    applyBtn:SetSize(80, 22)
    applyBtn:SetPoint("TOP", yLabel, "BOTTOM", 45, -12)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function()
        LayoutUI:ApplyCoordInput()
    end)
    coordPanel.applyBtn = applyBtn
    
    -- ========================================================================
    -- AUTO-SNAP SECTION
    -- ========================================================================
    
    -- Auto-snap separator
    local autoSnapSeparator = coordPanel:CreateTexture(nil, "ARTWORK")
    autoSnapSeparator:SetSize(190, 1)
    autoSnapSeparator:SetPoint("TOP", applyBtn, "BOTTOM", 0, -12)
    autoSnapSeparator:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    
    -- Auto-snap checkbox
    local autoSnapCheck = CreateFrame("CheckButton", nil, coordPanel, "UICheckButtonTemplate")
    autoSnapCheck:SetPoint("TOPLEFT", autoSnapSeparator, "BOTTOMLEFT", 0, -6)
    autoSnapCheck:SetSize(24, 24)
    autoSnapCheck:SetChecked(false)
    autoSnapCheck:SetScript("OnClick", function(self)
        LayoutUI.autoSnapEnabled = self:GetChecked()
    end)
    coordPanel.autoSnapCheck = autoSnapCheck
    
    local autoSnapLabel = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoSnapLabel:SetPoint("LEFT", autoSnapCheck, "RIGHT", 2, 0)
    autoSnapLabel:SetText("Auto-Snap to Nearest")
    autoSnapLabel:SetTextColor(1.0, 0.82, 0.0)  -- Gold
    
    -- Auto-snap help text
    local autoSnapHelp = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoSnapHelp:SetPoint("TOPLEFT", autoSnapCheck, "BOTTOMLEFT", 24, -2)
    autoSnapHelp:SetText("|cff888888Snaps anchor points when|nyou release the mouse|r")
    autoSnapHelp:SetWidth(160)
    autoSnapHelp:SetJustifyH("LEFT")
    
    -- ========================================================================
    -- ATTACHMENT SECTION
    -- ========================================================================
    
    -- Separator line
    local attachSeparator = coordPanel:CreateTexture(nil, "ARTWORK")
    attachSeparator:SetSize(190, 1)
    attachSeparator:SetPoint("TOP", autoSnapHelp, "BOTTOM", -12, -10)
    attachSeparator:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    coordPanel.attachSeparator = attachSeparator
    
    -- Attachment section title
    local attachTitle = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    attachTitle:SetPoint("TOP", attachSeparator, "BOTTOM", 0, -8)
    attachTitle:SetText("Attachment")
    attachTitle:SetTextColor(0.2, 0.8, 1.0)
    coordPanel.attachTitle = attachTitle
    
    -- Attachment status (changes based on state)
    local attachStatus = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    attachStatus:SetPoint("TOP", attachTitle, "BOTTOM", 0, -4)
    attachStatus:SetText("Not attached")
    attachStatus:SetTextColor(0.6, 0.6, 0.6)
    attachStatus:SetWidth(190)
    attachStatus:SetWordWrap(true)
    coordPanel.attachStatus = attachStatus
    
    -- Parent name label (shows nearest or selected parent)
    local attachParentLabel = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    attachParentLabel:SetPoint("TOP", attachStatus, "BOTTOM", 0, -8)
    attachParentLabel:SetText("")
    attachParentLabel:SetTextColor(0.8, 0.8, 0.2)
    attachParentLabel:SetWidth(190)
    coordPanel.attachParentLabel = attachParentLabel
    
    -- "Lock to Custom Frame" button to open dropdown
    local changeBtn = CreateFrame("Button", nil, coordPanel)
    changeBtn:SetSize(140, 16)
    changeBtn:SetPoint("TOP", attachParentLabel, "BOTTOM", 0, -2)
    local changeBtnText = changeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    changeBtnText:SetPoint("CENTER")
    changeBtnText:SetText("|cff88ccff[Lock to Custom Frame]|r")
    changeBtn:SetScript("OnEnter", function(self)
        changeBtnText:SetText("|cffaaddff[Lock to Custom Frame]|r")
    end)
    changeBtn:SetScript("OnLeave", function(self)
        changeBtnText:SetText("|cff88ccff[Lock to Custom Frame]|r")
    end)
    changeBtn:SetScript("OnClick", function(self)
        -- Show/hide custom element list
        if coordPanel.elementList and coordPanel.elementList:IsShown() then
            coordPanel.elementList:Hide()
        else
            LayoutUI:ShowElementList()
        end
    end)
    changeBtn:Hide()
    coordPanel.changeBtn = changeBtn
    
    -- Create custom element selection list with proper scroll
    local elementList = CreateFrame("Frame", "TweaksUI_ElementList", UIParent)
    elementList:SetSize(180, 400)
    elementList:SetPoint("TOPRIGHT", coordPanel, "TOPLEFT", -5, 0)
    elementList:SetFrameStrata("TOOLTIP")  -- Same as overlays
    elementList:SetFrameLevel(5000)  -- Higher than overlay level (1000)
    elementList:EnableMouse(true)
    elementList:SetClampedToScreen(true)
    elementList:Hide()
    
    -- Background texture (not BackdropTemplate)
    local bg = elementList:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.98)
    
    -- Border textures
    local borderTop = elementList:CreateTexture(nil, "BORDER")
    borderTop:SetHeight(1)
    borderTop:SetPoint("TOPLEFT")
    borderTop:SetPoint("TOPRIGHT")
    borderTop:SetColorTexture(0.6, 0.6, 0.6, 1)
    
    local borderBottom = elementList:CreateTexture(nil, "BORDER")
    borderBottom:SetHeight(1)
    borderBottom:SetPoint("BOTTOMLEFT")
    borderBottom:SetPoint("BOTTOMRIGHT")
    borderBottom:SetColorTexture(0.6, 0.6, 0.6, 1)
    
    local borderLeft = elementList:CreateTexture(nil, "BORDER")
    borderLeft:SetWidth(1)
    borderLeft:SetPoint("TOPLEFT")
    borderLeft:SetPoint("BOTTOMLEFT")
    borderLeft:SetColorTexture(0.6, 0.6, 0.6, 1)
    
    local borderRight = elementList:CreateTexture(nil, "BORDER")
    borderRight:SetWidth(1)
    borderRight:SetPoint("TOPRIGHT")
    borderRight:SetPoint("BOTTOMRIGHT")
    borderRight:SetColorTexture(0.6, 0.6, 0.6, 1)
    
    -- Scroll frame - higher level for content
    local scrollFrame = CreateFrame("ScrollFrame", "TweaksUI_ElementListScroll", elementList, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 5)
    scrollFrame:SetFrameLevel(5001)
    
    -- Scroll child (content container)
    local scrollChild = CreateFrame("Frame", "TweaksUI_ElementListContent", scrollFrame)
    scrollChild:SetWidth(145)
    scrollChild:SetHeight(1)  -- Will be set dynamically
    scrollChild:SetFrameLevel(5002)
    scrollFrame:SetScrollChild(scrollChild)
    
    elementList.scrollFrame = scrollFrame
    elementList.scrollChild = scrollChild
    coordPanel.elementList = elementList
    
    -- Content will be created dynamically in ShowElementList
    elementList.buttons = {}
    elementList.labels = {}
    
    coordPanel.selectedParentId = nil  -- Track selected parent
    coordPanel.useCustomParent = false  -- Track if user selected custom
    
    -- Offset display (shown when near/attached)
    local attachOffsetLabel = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    attachOffsetLabel:SetPoint("TOP", changeBtn, "BOTTOM", 0, -2)
    attachOffsetLabel:SetText("")
    attachOffsetLabel:SetTextColor(0.6, 0.6, 0.6)
    coordPanel.attachOffsetLabel = attachOffsetLabel
    
    -- Lock checkbox (for pending snaps)
    local lockCheck = CreateFrame("CheckButton", nil, coordPanel, "UICheckButtonTemplate")
    lockCheck:SetPoint("TOP", attachOffsetLabel, "BOTTOM", -60, -4)
    lockCheck:SetSize(24, 24)
    lockCheck:Hide()  -- Hidden until a snap is detected
    lockCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            LayoutUI:ConfirmAttachment()
        else
            LayoutUI:RemoveAttachment()
        end
    end)
    coordPanel.lockCheck = lockCheck
    
    local lockLabel = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockLabel:SetPoint("LEFT", lockCheck, "RIGHT", 2, 0)
    lockLabel:SetText("Lock attachment")
    lockLabel:SetTextColor(0.2, 1.0, 0.4)
    coordPanel.lockLabel = lockLabel
    
    -- Size matching section (only shown when locked)
    local sizeMatchFrame = CreateFrame("Frame", nil, coordPanel)
    sizeMatchFrame:SetSize(190, 50)
    sizeMatchFrame:SetPoint("TOP", lockCheck, "BOTTOM", 60, -4)
    sizeMatchFrame:Hide()
    coordPanel.sizeMatchFrame = sizeMatchFrame
    
    -- Match Width checkbox
    local matchWidthCheck = CreateFrame("CheckButton", nil, sizeMatchFrame, "UICheckButtonTemplate")
    matchWidthCheck:SetPoint("TOPLEFT", 0, 0)
    matchWidthCheck:SetSize(24, 24)
    matchWidthCheck:SetScript("OnClick", function(self)
        local selectedId = Layout:GetSelectedElement()
        local isChecked = self:GetChecked()
        
        -- If enabling and selected element is a unit frame, show mode popup
        if isChecked and LayoutUI:IsUnitFrameElement(selectedId) then
            LayoutUI:ShowSizeMatchModePopup("width", function(mode)
                -- Store the mode and apply
                LayoutUI:SetSizeMatchMode(selectedId, "width", mode)
                LayoutUI:UpdateSizeMatching()
            end, function()
                -- Cancel - uncheck the box
                self:SetChecked(false)
            end)
        else
            -- Clear mode if unchecking or not a unit frame
            if not isChecked then
                LayoutUI:SetSizeMatchMode(selectedId, "width", nil)
            end
            LayoutUI:UpdateSizeMatching()
        end
    end)
    coordPanel.matchWidthCheck = matchWidthCheck
    
    local matchWidthLabel = sizeMatchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    matchWidthLabel:SetPoint("LEFT", matchWidthCheck, "RIGHT", 2, 0)
    matchWidthLabel:SetText("Match parent width")
    matchWidthLabel:SetTextColor(0.8, 0.8, 0.8)
    
    -- Match Height checkbox
    local matchHeightCheck = CreateFrame("CheckButton", nil, sizeMatchFrame, "UICheckButtonTemplate")
    matchHeightCheck:SetPoint("TOPLEFT", 0, -24)
    matchHeightCheck:SetSize(24, 24)
    matchHeightCheck:SetScript("OnClick", function(self)
        local selectedId = Layout:GetSelectedElement()
        local isChecked = self:GetChecked()
        
        -- If enabling and selected element is a unit frame, show mode popup
        if isChecked and LayoutUI:IsUnitFrameElement(selectedId) then
            LayoutUI:ShowSizeMatchModePopup("height", function(mode)
                -- Store the mode and apply
                LayoutUI:SetSizeMatchMode(selectedId, "height", mode)
                LayoutUI:UpdateSizeMatching()
            end, function()
                -- Cancel - uncheck the box
                self:SetChecked(false)
            end)
        else
            -- Clear mode if unchecking or not a unit frame
            if not isChecked then
                LayoutUI:SetSizeMatchMode(selectedId, "height", nil)
            end
            LayoutUI:UpdateSizeMatching()
        end
    end)
    coordPanel.matchHeightCheck = matchHeightCheck
    
    local matchHeightLabel = sizeMatchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    matchHeightLabel:SetPoint("LEFT", matchHeightCheck, "RIGHT", 2, 0)
    matchHeightLabel:SetText("Match parent height")
    matchHeightLabel:SetTextColor(0.8, 0.8, 0.8)
    
    -- Clear locks link for selected element
    local clearElementLocksLink = CreateFrame("Button", nil, coordPanel)
    clearElementLocksLink:SetSize(160, 14)
    clearElementLocksLink:SetPoint("TOP", sizeMatchFrame, "BOTTOM", 0, -4)
    local clearElementLocksText = clearElementLocksLink:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearElementLocksText:SetPoint("CENTER")
    clearElementLocksText:SetText("|cffff8866[Clear locks from this element]|r")
    clearElementLocksLink:SetScript("OnEnter", function(self)
        clearElementLocksText:SetText("|cffffaa88[Clear locks from this element]|r")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Clear Element Locks", 1, 0.7, 0.3)
        GameTooltip:AddLine("Removes lock from this element.", 1, 1, 1, true)
        GameTooltip:AddLine("If this is a mother frame, clears all children.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Positions are preserved.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    clearElementLocksLink:SetScript("OnLeave", function(self)
        clearElementLocksText:SetText("|cffff8866[Clear locks from this element]|r")
        GameTooltip:Hide()
    end)
    clearElementLocksLink:SetScript("OnClick", function(self)
        local SnapLocking = TUICD.SnapLocking
        if not SnapLocking then return end
        
        local selectedId = Layout:GetSelectedElement()
        if not selectedId then return end
        
        local clearedCount = 0
        
        -- If this element is attached to something, remove that attachment
        if SnapLocking:IsAttached(selectedId) then
            SnapLocking:RemoveAttachment(selectedId)
            clearedCount = clearedCount + 1
        end
        
        -- If this element has children, remove all their attachments
        local children = SnapLocking:GetChildren(selectedId)
        for _, childId in ipairs(children) do
            if SnapLocking:RemoveAttachment(childId) then
                clearedCount = clearedCount + 1
            end
        end
        
        if clearedCount > 0 then
            TUICD:Print("Cleared " .. clearedCount .. " lock(s) from element")
            LayoutUI:UpdateAttachmentDisplay()
            LayoutUI:ClearAttachmentVisualization()
        else
            TUICD:Print("No locks to clear from this element")
        end
    end)
    clearElementLocksLink:Hide()  -- Only show when element has locks
    coordPanel.clearElementLocksLink = clearElementLocksLink
    
    -- ========================================================================
    -- END ATTACHMENT SECTION
    -- ========================================================================
    
    -- ========================================================================
    -- COLOR LEGEND SECTION
    -- ========================================================================
    
    -- Separator line - anchor to clearElementLocksLink
    local legendSeparator = coordPanel:CreateTexture(nil, "ARTWORK")
    legendSeparator:SetSize(190, 1)
    legendSeparator:SetPoint("TOP", clearElementLocksLink, "BOTTOM", 0, -6)
    legendSeparator:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    coordPanel.legendSeparator = legendSeparator
    
    -- Legend title
    local legendTitle = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    legendTitle:SetPoint("TOP", legendSeparator, "BOTTOM", 0, -6)
    legendTitle:SetText("Attachment Colors")
    legendTitle:SetTextColor(0.8, 0.8, 0.8)
    coordPanel.legendTitle = legendTitle
    
    -- Legend description
    local legendDesc = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legendDesc:SetPoint("TOP", legendTitle, "BOTTOM", 0, -4)
    legendDesc:SetText("Shows relationships when selecting\na frame that's part of a group:")
    legendDesc:SetTextColor(0.5, 0.5, 0.5)
    legendDesc:SetWidth(190)
    legendDesc:SetJustifyH("CENTER")
    coordPanel.legendDesc = legendDesc
    
    -- Color legend entries (matching COLORS table)
    local legendY = -8
    
    -- Selected (Green)
    local selectedLegend = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectedLegend:SetPoint("TOP", legendDesc, "BOTTOM", 0, legendY)
    selectedLegend:SetText("* Selected frame")
    selectedLegend:SetTextColor(0.2, 1.0, 0.4)  -- overlayBorderSelected
    coordPanel.selectedLegend = selectedLegend
    
    -- Root (Orange)
    local rootLegend = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rootLegend:SetPoint("TOP", selectedLegend, "BOTTOM", 0, -2)
    rootLegend:SetText("* Root/mother frame")
    rootLegend:SetTextColor(1.0, 0.5, 0.0)  -- overlayBorderRoot
    coordPanel.rootLegend = rootLegend
    
    -- Parent (Yellow-orange)
    local parentLegend = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parentLegend:SetPoint("TOP", rootLegend, "BOTTOM", 0, -2)
    parentLegend:SetText("* Parent in chain")
    parentLegend:SetTextColor(1.0, 0.7, 0.2)  -- overlayBorderParent
    coordPanel.parentLegend = parentLegend
    
    -- Child/Other connected (Cyan)
    local childLegend = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    childLegend:SetPoint("TOP", parentLegend, "BOTTOM", 0, -2)
    childLegend:SetText("* Other connected frames")
    childLegend:SetTextColor(0.0, 0.8, 1.0)  -- overlayBorderChild
    coordPanel.childLegend = childLegend
    
    -- ========================================================================
    -- END COLOR LEGEND SECTION
    -- ========================================================================
    
    -- Size display
    local sizeLabel = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel:SetPoint("BOTTOM", coordPanel, "BOTTOM", 0, 100)
    sizeLabel:SetText("Size: -- x --")
    sizeLabel:SetTextColor(0.6, 0.6, 0.6)
    coordPanel.sizeLabel = sizeLabel
    
    -- Arrow key hints (two lines)
    local arrowHint1 = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrowHint1:SetPoint("BOTTOM", coordPanel, "BOTTOM", 0, 130)
    arrowHint1:SetText("Arrow Keys: Nudge 1px")
    arrowHint1:SetTextColor(0.5, 0.7, 0.5)
    coordPanel.arrowHint1 = arrowHint1
    
    local arrowHint2 = coordPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrowHint2:SetPoint("BOTTOM", coordPanel, "BOTTOM", 0, 115)
    arrowHint2:SetText("Shift+Arrows: Nudge 10px")
    arrowHint2:SetTextColor(0.5, 0.7, 0.5)
    coordPanel.arrowHint2 = arrowHint2
    
    -- Clear All Locks button (removes attachments but keeps positions)
    local clearLocksBtn = CreateFrame("Button", nil, coordPanel, "UIPanelButtonTemplate")
    clearLocksBtn:SetSize(180, 22)
    clearLocksBtn:SetPoint("BOTTOM", coordPanel, "BOTTOM", 0, 70)
    clearLocksBtn:SetText("Clear All Locks")
    clearLocksBtn:GetFontString():SetTextColor(1, 0.7, 0.3)
    clearLocksBtn:SetScript("OnClick", function()
        StaticPopupDialogs["TWEAKSUI_CLEAR_ALL_LOCKS"] = {
            text = "Clear ALL element locks?\n\nThis will detach all locked elements from their parents but keep their current positions.\n\nThis cannot be undone.",
            button1 = "Clear Locks",
            button2 = "Cancel",
            OnAccept = function()
                local count = TUICD.SnapLocking:ClearAllAttachments()
                print("|cff00ff00TweaksUI:|r Cleared " .. count .. " element locks.")
                -- Refresh the coord panel display
                LayoutUI:UpdateCoordDisplay()
                -- Clear overlay colors since no more attachments
                LayoutUI:ClearAttachmentVisualization()
            end,
            OnShow = function(self)
                self:SetFrameStrata("TOOLTIP")
                self:Raise()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("TWEAKSUI_CLEAR_ALL_LOCKS")
    end)
    clearLocksBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Clear All Locks", 1, 1, 1)
        GameTooltip:AddLine("Removes all element-to-element locks.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Positions are preserved.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clearLocksBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    coordPanel.clearLocksBtn = clearLocksBtn
    
    -- Clear All Positions button (for debugging position issues)
    local clearPosBtn = CreateFrame("Button", nil, coordPanel, "UIPanelButtonTemplate")
    clearPosBtn:SetSize(180, 22)
    clearPosBtn:SetPoint("BOTTOM", coordPanel, "BOTTOM", 0, 40)
    clearPosBtn:SetText("Clear All Positions")
    clearPosBtn:GetFontString():SetTextColor(1, 0.5, 0.5)
    clearPosBtn:SetScript("OnClick", function()
        StaticPopupDialogs["TWEAKSUI_CLEAR_ALL_POSITIONS"] = {
            text = "Clear ALL saved element positions?\n\nThis will reset all frames to their default positions on reload.\n\nThis cannot be undone.",
            button1 = "Clear & Reload",
            button2 = "Cancel",
            OnAccept = function()
                -- Clear layout positions
                if TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.settings then
                    TweaksUI_Cooldowns_CharDB.settings.layout = nil
                end
                -- Clear cooldown container positions
                if TweaksUI_Cooldowns_CharDB then
                    TweaksUI_Cooldowns_CharDB.cooldownContainerPositions = nil
                end
                -- Clear any snap lock data
                if TweaksUI_Cooldowns_CharDB then
                    TweaksUI_Cooldowns_CharDB.snapLocks = nil
                end
                print("|cff00ff00TweaksUI:|r All saved positions cleared. Reloading...")
                ReloadUI()
            end,
            OnShow = function(self)
                self:SetFrameStrata("TOOLTIP")
                self:Raise()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("TWEAKSUI_CLEAR_ALL_POSITIONS")
    end)
    clearPosBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Clear All Positions", 1, 1, 1)
        GameTooltip:AddLine("Resets ALL element positions to defaults.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Use this if frames are stuck or misbehaving.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clearPosBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    coordPanel.clearPosBtn = clearPosBtn
    
    -- Exit Layout Mode button
    local exitBtn = CreateFrame("Button", nil, coordPanel, "UIPanelButtonTemplate")
    exitBtn:SetSize(180, 26)
    exitBtn:SetPoint("BOTTOM", coordPanel, "BOTTOM", 0, 12)
    exitBtn:SetText("Exit Layout Mode")
    exitBtn:SetScript("OnClick", function()
        if TUICD.Layout then
            TUICD.Layout:Exit()
        end
    end)
    -- Make it stand out a bit
    exitBtn:GetFontString():SetTextColor(1, 0.8, 0)
    coordPanel.exitBtn = exitBtn
    
    -- Initialize
    self:UpdateAnchorButtons()
    coordPanel:Hide()
    
    return coordPanel
end

function LayoutUI:UpdateAnchorButtons()
    if not coordPanel then return end
    
    for anchor, btn in pairs(coordPanel.anchorButtons) do
        btn:SetChecked(anchor == coordPanelSelectedAnchor)
    end
end

function LayoutUI:UpdateCoordDisplay()
    if not coordPanel then return end
    
    local selectedId, element = Layout:GetSelectedElement()
    if not selectedId or not element or not element.tuiFrame then
        coordPanel.elementName:SetText("No Selection")
        coordPanel.xEdit:SetText("")
        coordPanel.yEdit:SetText("")
        coordPanel.sizeLabel:SetText("Size: -- x --")
        return
    end
    
    coordPanel.elementName:SetText(element.name or selectedId)
    
    local frame = element.tuiFrame.frame
    local width, height = frame:GetWidth(), frame:GetHeight()
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    
    if left and bottom then
        local cx, cy = ToCenterCoords(left, bottom, width, height, coordPanelSelectedAnchor)
        coordPanel.xEdit:SetText(string.format("%.0f", cx))
        coordPanel.yEdit:SetText(string.format("%.0f", cy))
    end
    
    coordPanel.sizeLabel:SetText(string.format("Size: %.0f x %.0f", width, height))
end

function LayoutUI:ApplyCoordInput()
    if not coordPanel then return end
    
    local selectedId, element = Layout:GetSelectedElement()
    if not selectedId or not element or not element.tuiFrame then return end
    
    local xText = coordPanel.xEdit:GetText()
    local yText = coordPanel.yEdit:GetText()
    
    local cx = tonumber(xText)
    local cy = tonumber(yText)
    
    if not cx or not cy then
        TUICD:PrintError("Invalid coordinates")
        return
    end
    
    local frame = element.tuiFrame.frame
    local width, height = frame:GetWidth(), frame:GetHeight()
    local oldLeft, oldBottom = frame:GetLeft(), frame:GetBottom()
    
    -- Convert center-based coords back to BOTTOMLEFT screen coords
    local blX, blY = FromCenterCoords(cx, cy, width, height, coordPanelSelectedAnchor)
    
    -- Calculate the delta from old position
    local dx = blX - (oldLeft or 0)
    local dy = blY - (oldBottom or 0)
    
    local SnapLocking = TUICD.SnapLocking
    
    -- Check if this frame is a CHILD (attached to something)
    local attachment = SnapLocking and SnapLocking:GetAttachment(selectedId)
    if attachment then
        -- This is a locked child - adjust its offset relative to parent
        -- Move just this frame
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", blX, blY)
        
        -- Update the offset in the attachment
        local parentTUI = TUICD.TUIFrame.Get(attachment.parentId)
        if parentTUI then
            local parentFrame = parentTUI.frame
            local parentLeft, parentBottom = parentFrame:GetLeft(), parentFrame:GetBottom()
            if parentLeft and parentBottom then
                attachment.offsetX = blX - parentLeft
                attachment.offsetY = blY - parentBottom
                SnapLocking:SaveAttachments()
            end
        end
        
        -- Update overlay
        self:UpdateOverlayPosition(element)
        Layout:SaveElementPosition(selectedId)
        self:UpdateAttachmentDisplay()
        
        TUICD:PrintDebug(string.format("Adjusted %s offset to %.0f, %.0f", element.name, attachment.offsetX, attachment.offsetY))
        return
    end
    
    -- Check if this frame is a mother/root with children attached
    if SnapLocking and SnapLocking:IsInLockedGroup(selectedId) then
        -- This is a mother frame - move the entire group
        local groupIds = SnapLocking:GetConnectedGroup(selectedId)
        
        -- Move all frames in the group by the same delta
        for _, frameId in ipairs(groupIds) do
            local tui = TUICD.TUIFrame.Get(frameId)
            if tui then
                local f = tui.frame
                local fLeft, fBottom = f:GetLeft(), f:GetBottom()
                if fLeft and fBottom then
                    f:ClearAllPoints()
                    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", fLeft + dx, fBottom + dy)
                end
            end
            
            -- Update overlay
            local groupElement = Layout:GetElement(frameId)
            if groupElement then
                self:UpdateOverlayPosition(groupElement)
            end
            
            -- Save position
            Layout:SaveElementPosition(frameId)
        end
    else
        -- Not locked - move just this frame
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", blX, blY)
        
        -- Save position
        Layout:SaveElementPosition(selectedId)
        
        -- Update overlay
        self:UpdateOverlayPosition(element)
    end
    
    TUICD:PrintDebug(string.format("Positioned %s at %s: %.0f, %.0f", element.name, coordPanelSelectedAnchor, cx, cy))
end

function LayoutUI:ShowCoordPanel()
    if not coordPanel then
        self:CreateCoordPanel()
    end
    coordPanel:Show()
    self:UpdateCoordDisplay()
end

function LayoutUI:HideCoordPanel()
    if coordPanel then
        -- Hide the element selection list if open
        if coordPanel.elementList then
            coordPanel.elementList:Hide()
        end
        coordPanel:Hide()
    end
end

function LayoutUI:OnElementSelected(id)
    if id then
        -- Hide element list when selecting a different element
        if coordPanel and coordPanel.elementList then
            coordPanel.elementList:Hide()
        end
        self:UpdateCoordDisplay()
        self:UpdateAttachmentDisplay()
    end
end

-- ============================================================================
-- ATTACHMENT UI FUNCTIONS
-- ============================================================================

function LayoutUI:UpdateAttachmentDisplay()
    if not coordPanel then return end
    
    -- Debug: Log state at start
    if TUICD.PrintDebug then
        TUICD:PrintDebug("UpdateAttachmentDisplay: useCustomParent=" .. tostring(coordPanel.useCustomParent) .. ", selectedParentId=" .. tostring(coordPanel.selectedParentId))
    end
    
    local selectedId, element = Layout:GetSelectedElement()
    if not selectedId then
        -- No selection - hide attachment UI
        coordPanel.attachStatus:SetText("No element selected")
        coordPanel.attachStatus:SetTextColor(0.6, 0.6, 0.6)
        coordPanel.attachParentLabel:SetText("")
        coordPanel.attachOffsetLabel:SetText("")
        coordPanel.lockCheck:Hide()
        coordPanel.sizeMatchFrame:Hide()
        coordPanel.changeBtn:Hide()
        coordPanel.elementList:Hide()
        coordPanel.clearElementLocksLink:Hide()
        self:ClearNearbyHighlight()
        return
    end
    
    local SnapLocking = TUICD.SnapLocking
    if not SnapLocking then
        coordPanel.attachStatus:SetText("SnapLocking not loaded")
        coordPanel.changeBtn:Hide()
        coordPanel.elementList:Hide()
        coordPanel.clearElementLocksLink:Hide()
        self:ClearNearbyHighlight()
        return
    end
    
    -- Check if this element is attached TO something (is a child)
    local attachment = SnapLocking:GetAttachment(selectedId)
    if attachment then
        -- Check if parent actually exists
        local parentTUI = SnapLocking:GetTUIFrame(attachment.parentId)
        
        if parentTUI then
            -- LOCKED as child - valid attachment
            local parentName = SnapLocking:GetParentDisplayName(selectedId) or attachment.parentId
            coordPanel.attachStatus:SetText("Locked to:")
            coordPanel.attachStatus:SetTextColor(0.6, 0.6, 0.6)
            
            -- Clear nearby highlight when locked
            self:ClearNearbyHighlight()
            
            -- Hide dropdown and change button, show static label
            coordPanel.elementList:Hide()
            coordPanel.changeBtn:Hide()
            coordPanel.attachParentLabel:Show()
            
            -- Color parent name in ORANGE (root/parent color)
            coordPanel.attachParentLabel:SetText(parentName)
            coordPanel.attachParentLabel:SetTextColor(1.0, 0.5, 0.0)  -- Orange - overlayBorderRoot
            
            coordPanel.attachOffsetLabel:SetText(string.format("Offset: %.0f, %.0f", attachment.offsetX, attachment.offsetY))
            
            coordPanel.lockCheck:Show()
            coordPanel.lockCheck:SetChecked(true)
            coordPanel.lockLabel:SetText("Locked")
            coordPanel.lockLabel:SetTextColor(0.2, 1.0, 0.4)
            
            -- Show size matching options for bar-type frames (Action Bars, System Bars, Resource Bars, Cast Bars)
            -- and Unit Frames. Other frame types (Cooldowns, General, etc.) don't support size matching.
            local tuiFrame = SnapLocking:GetTUIFrame(selectedId)
            local showSizeMatch = false
            if tuiFrame then
                -- Get category from Layout element (more reliable than tuiFrame.category)
                local layoutElement = TUICD.Layout:GetElement(selectedId)
                local category = (layoutElement and layoutElement.category) or tuiFrame.category or ""
                -- Show size matching for bar-type categories and unit frames
                if category:find("Bar") or category:find("bar") or category:find("BAR") 
                   or category:find("Unit") or category:find("Frame") then
                    showSizeMatch = true
                end
                -- Override with explicit flag if set
                if tuiFrame.hideSizeMatching then
                    showSizeMatch = false
                elseif tuiFrame.supportsSizeMatching then
                    showSizeMatch = true
                end
            end
            
            if showSizeMatch then
                coordPanel.sizeMatchFrame:Show()
                coordPanel.matchWidthCheck:SetChecked(attachment.matchWidth or false)
                coordPanel.matchHeightCheck:SetChecked(attachment.matchHeight or false)
            else
                coordPanel.sizeMatchFrame:Hide()
            end
            
            -- Show clear locks link for locked elements
            coordPanel.clearElementLocksLink:Show()
        else
            -- BROKEN attachment - parent doesn't exist
            coordPanel.attachStatus:SetText("|cffff4444Broken link:|r")
            coordPanel.attachStatus:SetTextColor(1, 1, 1)
            
            -- Clear nearby highlight
            self:ClearNearbyHighlight()
            
            -- Hide dropdown and change button, show static label
            coordPanel.elementList:Hide()
            coordPanel.changeBtn:Hide()
            coordPanel.attachParentLabel:Show()
            
            coordPanel.attachParentLabel:SetText(attachment.parentId .. " (missing)")
            coordPanel.attachParentLabel:SetTextColor(1.0, 0.3, 0.3)
            coordPanel.attachOffsetLabel:SetText("Drag to reconnect or uncheck to clear")
            
            coordPanel.lockCheck:Show()
            coordPanel.lockCheck:SetChecked(true)  -- Show as checked so user can uncheck to clear
            coordPanel.lockLabel:SetText("Clear broken link")
            coordPanel.lockLabel:SetTextColor(1.0, 0.4, 0.4)
            
            coordPanel.sizeMatchFrame:Hide()
            
            -- Show clear locks link for broken attachments
            coordPanel.clearElementLocksLink:Show()
        end
        
        -- Keep coordinate inputs ENABLED
        coordPanel.xEdit:SetEnabled(true)
        coordPanel.yEdit:SetEnabled(true)
        coordPanel.applyBtn:SetEnabled(true)
        return
    end
    
    -- Check if this element has children attached to it (is a parent/mother)
    local children = SnapLocking:GetChildren(selectedId)
    if #children > 0 then
        -- This is a mother frame with children attached
        local childNames = {}
        for _, childId in ipairs(children) do
            local childTUI = SnapLocking:GetTUIFrame(childId)
            table.insert(childNames, childTUI and childTUI.name or childId)
        end
        
        -- Clear nearby highlight
        self:ClearNearbyHighlight()
        
        -- Hide dropdown and change button, show static label
        coordPanel.elementList:Hide()
        coordPanel.changeBtn:Hide()
        coordPanel.attachParentLabel:Show()
        
        -- Color status in ORANGE since this is a root/mother
        coordPanel.attachStatus:SetText("Mother frame")
        coordPanel.attachStatus:SetTextColor(1.0, 0.5, 0.0)  -- Orange - overlayBorderRoot
        
        -- Color children list in CYAN
        coordPanel.attachParentLabel:SetText("Children: " .. table.concat(childNames, ", "))
        coordPanel.attachParentLabel:SetTextColor(0.0, 0.8, 1.0)  -- Cyan - overlayBorderChild
        
        coordPanel.attachOffsetLabel:SetText("Moving this moves all children")
        coordPanel.attachOffsetLabel:SetTextColor(0.6, 0.6, 0.6)
        
        coordPanel.lockCheck:Hide()  -- Can't unlock from parent side
        coordPanel.sizeMatchFrame:Hide()
        
        -- Show clear locks link for mother frames (can clear children)
        coordPanel.clearElementLocksLink:Show()
        
        -- Keep coordinate inputs enabled
        coordPanel.xEdit:SetEnabled(true)
        coordPanel.yEdit:SetEnabled(true)
        coordPanel.applyBtn:SetEnabled(true)
        return
    end
    
    -- Check for pending snap (near but not locked)
    local pendingSnap = SnapLocking:GetPendingSnap()
    
    -- Show pending snap if:
    -- 1. The pending snap is for the selected element, OR
    -- 2. The selected element is in a locked group and the pending snap is for the root of that group
    local showPendingSnap = false
    if pendingSnap then
        if pendingSnap.childId == selectedId then
            showPendingSnap = true
        elseif SnapLocking:IsInLockedGroup(selectedId) then
            local rootId = SnapLocking:GetChainRoot(selectedId)
            if rootId and pendingSnap.childId == rootId then
                showPendingSnap = true
            end
        end
    end
    
    -- Determine which parent to display
    -- If user selected a custom parent, use that; otherwise use nearest (pending snap)
    local displayParentId = nil
    local displayParentName = nil
    local displayOffset = nil
    
    if coordPanel.useCustomParent and coordPanel.selectedParentId then
        -- User selected a custom parent from dropdown
        displayParentId = coordPanel.selectedParentId
        local parentTUI = SnapLocking:GetTUIFrame(displayParentId)
        displayParentName = parentTUI and parentTUI.name or displayParentId
        
        -- Calculate offset directly between the two elements
        local childElement = Layout:GetElement(selectedId)
        local parentElement = Layout:GetElement(displayParentId)
        if childElement and childElement.tuiFrame and parentElement and parentElement.tuiFrame then
            local childFrame = childElement.tuiFrame.frame
            local parentFrame = parentElement.tuiFrame.frame
            local childLeft, childBottom = childFrame:GetLeft(), childFrame:GetBottom()
            local parentLeft, parentBottom = parentFrame:GetLeft(), parentFrame:GetBottom()
            if childLeft and parentLeft then
                local offsetX = childLeft - parentLeft
                local offsetY = childBottom - parentBottom
                displayOffset = string.format("Offset: %.0f, %.0f", offsetX, offsetY)
            end
        end
    elseif showPendingSnap then
        -- Use nearest detected element
        displayParentId = pendingSnap.parentId
        local parentTUI = SnapLocking:GetTUIFrame(displayParentId)
        displayParentName = parentTUI and parentTUI.name or displayParentId
        displayOffset = string.format("Offset: %.0f, %.0f", pendingSnap.offsetX, pendingSnap.offsetY)
    end
    
    if displayParentId then
        -- PENDING state - have a parent to lock to
        -- Different label for custom vs nearby
        if coordPanel.useCustomParent then
            coordPanel.attachStatus:SetText("Lock to Custom:")
            coordPanel.attachStatus:SetTextColor(0.5, 0.8, 1.0)  -- Light blue for custom
        else
            coordPanel.attachStatus:SetText("Lock to Nearby:")
            coordPanel.attachStatus:SetTextColor(0.8, 0.8, 0.2)  -- Yellow for nearby
        end
        
        -- Highlight the target element overlay
        self:HighlightNearbyElement(displayParentId)
        
        -- Show parent name and change button
        coordPanel.attachParentLabel:SetText(displayParentName)
        if coordPanel.useCustomParent then
            coordPanel.attachParentLabel:SetTextColor(0.5, 0.8, 1.0)  -- Light blue
        else
            coordPanel.attachParentLabel:SetTextColor(0.8, 0.8, 0.2)  -- Yellow
        end
        coordPanel.attachParentLabel:Show()
        coordPanel.changeBtn:Show()
        coordPanel.elementList:Hide()
        
        coordPanel.attachOffsetLabel:SetText(displayOffset or "")
        
        coordPanel.lockCheck:Show()
        coordPanel.lockCheck:SetChecked(false)
        coordPanel.lockLabel:SetText("Lock attachment")
        coordPanel.lockLabel:SetTextColor(0.8, 0.8, 0.2)
        
        -- IMPORTANT: Reset size matching checkboxes for NEW attachments
        coordPanel.matchWidthCheck:SetChecked(false)
        coordPanel.matchHeightCheck:SetChecked(false)
        coordPanel.sizeMatchFrame:Hide()
        
        -- Hide clear locks link when not yet locked
        coordPanel.clearElementLocksLink:Hide()
        
        -- Keep coordinate inputs enabled for nudging before locking
        coordPanel.xEdit:SetEnabled(true)
        coordPanel.yEdit:SetEnabled(true)
        coordPanel.applyBtn:SetEnabled(true)
        return
    end
    
    -- NOT ATTACHED state - no nearby element
    coordPanel.attachStatus:SetText("Not attached")
    coordPanel.attachStatus:SetTextColor(0.6, 0.6, 0.6)
    
    -- Clear any nearby highlight
    self:ClearNearbyHighlight()
    
    -- Show instruction and change button
    coordPanel.attachParentLabel:SetText("Drag near element or")
    coordPanel.attachParentLabel:SetTextColor(0.5, 0.5, 0.5)
    coordPanel.attachParentLabel:Show()
    coordPanel.changeBtn:Show()
    coordPanel.elementList:Hide()
    
    coordPanel.attachOffsetLabel:SetText("")
    coordPanel.lockCheck:Hide()
    
    -- Reset size matching checkboxes when not attached
    coordPanel.matchWidthCheck:SetChecked(false)
    coordPanel.matchHeightCheck:SetChecked(false)
    coordPanel.sizeMatchFrame:Hide()
    
    -- Hide clear locks link when not attached
    coordPanel.clearElementLocksLink:Hide()
    
    -- Enable coordinate inputs
    coordPanel.xEdit:SetEnabled(true)
    coordPanel.yEdit:SetEnabled(true)
    coordPanel.applyBtn:SetEnabled(true)
end

function LayoutUI:ConfirmAttachment()
    local SnapLocking = TUICD.SnapLocking
    if not SnapLocking then return end
    
    local selectedId = Layout:GetSelectedElement()
    if not selectedId then return end
    
    -- Check if already attached (this is an unlock toggle)
    if SnapLocking:IsAttached(selectedId) then
        return
    end
    
    local success = false
    
    -- If using custom parent, create attachment directly
    if coordPanel.useCustomParent and coordPanel.selectedParentId then
        local childElement = Layout:GetElement(selectedId)
        local parentElement = Layout:GetElement(coordPanel.selectedParentId)
        
        if childElement and childElement.tuiFrame and parentElement and parentElement.tuiFrame then
            local childFrame = childElement.tuiFrame.frame
            local parentFrame = parentElement.tuiFrame.frame
            
            -- Calculate offset
            local childLeft, childBottom = childFrame:GetLeft(), childFrame:GetBottom()
            local parentLeft, parentBottom = parentFrame:GetLeft(), parentFrame:GetBottom()
            
            if childLeft and parentLeft then
                local offsetX = childLeft - parentLeft
                local offsetY = childBottom - parentBottom
                
                -- Create attachment directly using options table
                success = SnapLocking:CreateAttachment(selectedId, coordPanel.selectedParentId, {
                    point = "BOTTOMLEFT",
                    relPoint = "BOTTOMLEFT",
                    offsetX = offsetX,
                    offsetY = offsetY,
                    matchWidth = coordPanel.matchWidthCheck:GetChecked(),
                    matchHeight = coordPanel.matchHeightCheck:GetChecked(),
                })
            end
        end
    else
        -- Use pending snap system for nearby detection
        success = SnapLocking:ConfirmPendingSnap({
            matchWidth = coordPanel.matchWidthCheck:GetChecked(),
            matchHeight = coordPanel.matchHeightCheck:GetChecked(),
        })
    end
    
    if success then
        -- Clear custom parent state
        coordPanel.useCustomParent = false
        coordPanel.selectedParentId = nil
        self:ClearNearbyHighlight()
        self:UpdateAttachmentDisplay()
        self:UpdateAttachmentVisualization(selectedId)
        TUICD:Print("Attachment locked")
    end
end

function LayoutUI:RemoveAttachment()
    local SnapLocking = TUICD.SnapLocking
    if not SnapLocking then return end
    
    local selectedId = Layout:GetSelectedElement()
    if not selectedId then return end
    
    local success = SnapLocking:RemoveAttachment(selectedId)
    
    if success then
        self:UpdateAttachmentDisplay()
    end
end

function LayoutUI:UpdateSizeMatching()
    local SnapLocking = TUICD.SnapLocking
    if not SnapLocking then return end
    
    local selectedId = Layout:GetSelectedElement()
    if not selectedId then return end
    
    if not SnapLocking:IsAttached(selectedId) then return end
    
    local matchWidth = coordPanel.matchWidthCheck:GetChecked()
    local matchHeight = coordPanel.matchHeightCheck:GetChecked()
    
    -- Get targets for unit frames (healthBar vs frame)
    local widthTarget = self:GetSizeMatchMode(selectedId, "width")
    local heightTarget = self:GetSizeMatchMode(selectedId, "height")
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("UpdateSizeMatching: " .. selectedId .. 
            " matchW=" .. tostring(matchWidth) .. " (" .. tostring(widthTarget) .. ")" ..
            " matchH=" .. tostring(matchHeight) .. " (" .. tostring(heightTarget) .. ")")
    end
    
    SnapLocking:UpdateSizeMatching(selectedId, {
        matchWidth = matchWidth,
        matchHeight = matchHeight,
        widthTarget = widthTarget,
        heightTarget = heightTarget,
    })
end

-- ============================================================================
-- SIZE MATCH MODE STORAGE
-- ============================================================================
-- Stores the mode choice (healthBar vs frame) for unit frame elements

local sizeMatchModes = {}  -- [elementId] = { width = "healthBar"|"frame", height = "healthBar"|"frame" }

function LayoutUI:SetSizeMatchMode(elementId, dimension, mode)
    if not elementId then return end
    
    if not sizeMatchModes[elementId] then
        sizeMatchModes[elementId] = {}
    end
    
    sizeMatchModes[elementId][dimension] = mode
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("SetSizeMatchMode: " .. elementId .. " " .. dimension .. " = " .. tostring(mode))
    end
end

function LayoutUI:GetSizeMatchMode(elementId, dimension)
    if not elementId or not sizeMatchModes[elementId] then
        return nil
    end
    return sizeMatchModes[elementId][dimension]
end

function LayoutUI:ClearSizeMatchModes(elementId)
    if elementId then
        sizeMatchModes[elementId] = nil
    end
end

-- ============================================================================
-- REAL-TIME SNAP DETECTION (During Drag)
-- ============================================================================

-- Find the nearest element during drag by calculating anchor point distances
-- Returns the element with the closest anchor point within tolerance
-- Uses preference multipliers to favor edge midpoints over corners
function LayoutUI:FindNearbyElementDuringDrag(draggingElementId, tolerance)
    local element = Layout:GetElement(draggingElementId)
    if not element or not element.tuiFrame then 
        return nil 
    end
    
    local draggedFrame = element.tuiFrame.frame
    if not draggedFrame then 
        return nil 
    end
    
    -- Get the dragged frame's current rect
    local dragL, dragB, dragW, dragH = draggedFrame:GetRect()
    if not dragL or not dragB then 
        return nil 
    end
    
    -- Calculate anchor points for dragged frame (9 points: corners + edge midpoints + center)
    local dragR = dragL + dragW
    local dragT = dragB + dragH
    local dragCX = dragL + dragW / 2
    local dragCY = dragB + dragH / 2
    
    -- Anchor type: "center", "edge", or "corner"
    local dragPoints = {
        { dragL, dragT, "TOPLEFT", "corner" },
        { dragCX, dragT, "TOP", "edge" },
        { dragR, dragT, "TOPRIGHT", "corner" },
        { dragL, dragCY, "LEFT", "edge" },
        { dragCX, dragCY, "CENTER", "center" },
        { dragR, dragCY, "RIGHT", "edge" },
        { dragL, dragB, "BOTTOMLEFT", "corner" },
        { dragCX, dragB, "BOTTOM", "edge" },
        { dragR, dragB, "BOTTOMRIGHT", "corner" },
    }
    
    -- Preference PENALTIES (added to raw distance)
    -- center-to-center: -15 (bonus), edge-to-edge: -10 (bonus), mixed: 0, corner-to-corner: +40 (penalty)
    local function GetPreferencePenalty(type1, type2)
        if type1 == "center" and type2 == "center" then
            return -15  -- Bonus for center-to-center
        elseif type1 == "edge" and type2 == "edge" then
            return -10  -- Bonus for edge-to-edge
        elseif type1 == "corner" and type2 == "corner" then
            return 40   -- Heavy penalty for corner-to-corner
        else
            return 0    -- Normal for mixed
        end
    end
    
    local allElements = Layout:GetAllElements()
    tolerance = tolerance or 75
    
    -- Find the frame with the closest WEIGHTED anchor point distance
    local closestElementId = nil
    local closestFrame = nil
    local closestWeightedDist = tolerance + 1  -- Start just above tolerance
    local closestRawDist = 9999
    local closestDragAnchor = nil
    local closestTargetAnchor = nil
    
    for id, elem in pairs(allElements) do
        if id ~= draggingElementId and elem.tuiFrame and elem.tuiFrame.frame then
            local frame = elem.tuiFrame.frame
            if frame:IsVisible() then
                local l, b, w, h = frame:GetRect()
                if l and b and w and h then
                    local r = l + w
                    local t = b + h
                    local cx = l + w / 2
                    local cy = b + h / 2
                    
                    -- Anchor points on this target frame (9 points)
                    local targetPoints = {
                        { l, t, "TOPLEFT", "corner" },
                        { cx, t, "TOP", "edge" },
                        { r, t, "TOPRIGHT", "corner" },
                        { l, cy, "LEFT", "edge" },
                        { cx, cy, "CENTER", "center" },
                        { r, cy, "RIGHT", "edge" },
                        { l, b, "BOTTOMLEFT", "corner" },
                        { cx, b, "BOTTOM", "edge" },
                        { r, b, "BOTTOMRIGHT", "corner" },
                    }
                    
                    -- Find minimum weighted anchor distance for this frame
                    for _, dp in ipairs(dragPoints) do
                        for _, tp in ipairs(targetPoints) do
                            local rawDist = math.sqrt((dp[1] - tp[1])^2 + (dp[2] - tp[2])^2)
                            local penalty = GetPreferencePenalty(dp[4], tp[4])
                            local weightedDist = rawDist + penalty
                            
                            if weightedDist < closestWeightedDist then
                                closestWeightedDist = weightedDist
                                closestRawDist = rawDist
                                closestElementId = id
                                closestFrame = frame
                                closestDragAnchor = dp[3]
                                closestTargetAnchor = tp[3]
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Only return if RAW distance is within tolerance (weighted is just for selection)
    if closestElementId and closestRawDist <= tolerance then
        return closestElementId, closestFrame, closestRawDist, closestDragAnchor, closestTargetAnchor
    end
    
    return nil, nil, 9999
end

-- ============================================================================
-- AUTO-SNAP FUNCTIONALITY
-- ============================================================================

-- Anchor point names for reference
local ANCHOR_NAMES = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"
}

-- Calculate anchor point coordinates for a frame
local function GetFrameAnchorPoints(frame)
    local l, b, w, h = frame:GetRect()
    if not l or not b then return nil end
    
    local r = l + w
    local t = b + h
    local cx = l + w / 2
    local cy = b + h / 2
    
    return {
        TOPLEFT     = { x = l,  y = t },
        TOP         = { x = cx, y = t },
        TOPRIGHT    = { x = r,  y = t },
        LEFT        = { x = l,  y = cy },
        CENTER      = { x = cx, y = cy },
        RIGHT       = { x = r,  y = cy },
        BOTTOMLEFT  = { x = l,  y = b },
        BOTTOM      = { x = cx, y = b },
        BOTTOMRIGHT = { x = r,  y = b },
    }
end

-- Find the nearest anchor points between two frames for ADJACENT placement
-- Returns: draggedAnchor, targetAnchor, distance
-- Prefers OPPOSITE edge pairs (RIGHT-LEFT, TOP-BOTTOM) for clean adjacent snapping
function LayoutUI:FindNearestAnchorPoints(draggedFrame, targetFrame)
    local dragPoints = GetFrameAnchorPoints(draggedFrame)
    local targetPoints = GetFrameAnchorPoints(targetFrame)
    
    if not dragPoints or not targetPoints then
        return nil, nil, 9999
    end
    
    -- Get frame centers
    local dragCX = dragPoints.CENTER.x
    local dragCY = dragPoints.CENTER.y
    local targetCX = targetPoints.CENTER.x
    local targetCY = targetPoints.CENTER.y
    
    -- Calculate relative position
    local dx = targetCX - dragCX  -- positive = target is to the right
    local dy = targetCY - dragCY  -- positive = target is above
    
    -- Determine which edge pair to use based on relative position
    -- For ADJACENT placement (edges touch, not overlap)
    local edgePairs = {}
    
    -- Horizontal adjacency (target is to left or right)
    if math.abs(dx) > math.abs(dy) * 0.5 then  -- More horizontal than vertical
        if dx > 0 then
            -- Target is to the RIGHT: our RIGHT edge to their LEFT edge
            table.insert(edgePairs, { drag = "RIGHT", target = "LEFT", priority = 1 })
        else
            -- Target is to the LEFT: our LEFT edge to their RIGHT edge
            table.insert(edgePairs, { drag = "LEFT", target = "RIGHT", priority = 1 })
        end
    end
    
    -- Vertical adjacency (target is above or below)
    if math.abs(dy) > math.abs(dx) * 0.5 then  -- More vertical than horizontal
        if dy > 0 then
            -- Target is ABOVE: our TOP edge to their BOTTOM edge
            table.insert(edgePairs, { drag = "TOP", target = "BOTTOM", priority = 1 })
        else
            -- Target is BELOW: our BOTTOM edge to their TOP edge
            table.insert(edgePairs, { drag = "BOTTOM", target = "TOP", priority = 1 })
        end
    end
    
    -- Always allow CENTER-CENTER for overlapping alignment
    table.insert(edgePairs, { drag = "CENTER", target = "CENTER", priority = 2 })
    
    -- Find the best edge pair by distance
    local closestDragAnchor = nil
    local closestTargetAnchor = nil
    local closestDist = 9999
    
    for _, pair in ipairs(edgePairs) do
        local dp = dragPoints[pair.drag]
        local tp = targetPoints[pair.target]
        if dp and tp then
            local dist = math.sqrt((dp.x - tp.x)^2 + (dp.y - tp.y)^2)
            -- Priority 1 pairs get a bonus
            if pair.priority == 1 then
                dist = dist - 20
            end
            if dist < closestDist then
                closestDist = dist
                closestDragAnchor = pair.drag
                closestTargetAnchor = pair.target
            end
        end
    end
    
    -- Restore original distance for return (without bonus)
    if closestDragAnchor and closestTargetAnchor then
        local dp = dragPoints[closestDragAnchor]
        local tp = targetPoints[closestTargetAnchor]
        closestDist = math.sqrt((dp.x - tp.x)^2 + (dp.y - tp.y)^2)
    end
    
    return closestDragAnchor, closestTargetAnchor, closestDist
end

-- Perform auto-snap: move the dragged frame so its nearest anchor OVERLAPS target's nearest anchor, then LOCK
function LayoutUI:PerformAutoSnap(draggedElementId, targetElementId)
    local dragElement = Layout:GetElement(draggedElementId)
    local targetElement = Layout:GetElement(targetElementId)
    
    if not dragElement or not dragElement.tuiFrame then return false end
    if not targetElement or not targetElement.tuiFrame then return false end
    
    local dragFrame = dragElement.tuiFrame.frame
    local targetFrame = targetElement.tuiFrame.frame
    
    if not dragFrame or not targetFrame then return false end
    
    -- Find nearest anchor points
    local dragAnchor, targetAnchor, distance = self:FindNearestAnchorPoints(dragFrame, targetFrame)
    
    if not dragAnchor or not targetAnchor then return false end
    
    -- Get the target anchor position in screen coordinates
    local targetPoints = GetFrameAnchorPoints(targetFrame)
    local targetPos = targetPoints[targetAnchor]
    
    if not targetPos then return false end
    
    -- Calculate where to position the dragged frame so anchors OVERLAP
    local dragL, dragB, dragW, dragH = dragFrame:GetRect()
    if not dragL or not dragB then return false end
    
    -- Calculate offset from BOTTOMLEFT to the drag anchor
    local anchorOffsets = {
        TOPLEFT     = { x = 0,           y = dragH },
        TOP         = { x = dragW / 2,   y = dragH },
        TOPRIGHT    = { x = dragW,       y = dragH },
        LEFT        = { x = 0,           y = dragH / 2 },
        CENTER      = { x = dragW / 2,   y = dragH / 2 },
        RIGHT       = { x = dragW,       y = dragH / 2 },
        BOTTOMLEFT  = { x = 0,           y = 0 },
        BOTTOM      = { x = dragW / 2,   y = 0 },
        BOTTOMRIGHT = { x = dragW,       y = 0 },
    }
    
    local offset = anchorOffsets[dragAnchor]
    if not offset then return false end
    
    -- New BOTTOMLEFT position for the frame (so dragAnchor sits on targetPos)
    local newL = targetPos.x - offset.x
    local newB = targetPos.y - offset.y
    
    -- Apply the new position
    dragFrame:ClearAllPoints()
    dragFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newL, newB)
    
    -- Save the position
    Layout:SaveElementPosition(draggedElementId)
    
    -- Update overlay
    self:UpdateOverlayPosition(dragElement)
    
    -- Now create the LOCKED attachment
    local SnapLocking = TUICD.SnapLocking
    if SnapLocking then
        -- Calculate the offset from target frame's position (for storage)
        local targetL, targetB = targetFrame:GetRect()
        if targetL and targetB then
            local offsetX = newL - targetL
            local offsetY = newB - targetB
            
            -- Create the attachment directly (locked, not pending)
            local success = SnapLocking:CreateAttachment(draggedElementId, targetElementId, {
                point = "BOTTOMLEFT",
                relPoint = "BOTTOMLEFT",
                offsetX = offsetX,
                offsetY = offsetY,
                matchWidth = false,
                matchHeight = false,
            })
            
            if success then
                -- Update UI
                self:UpdateAttachmentDisplay()
                self:UpdateAttachmentVisualization(draggedElementId)
            end
        end
    end
    
    return true
end

-- ============================================================================
-- SNAP DETECTION INTEGRATION
-- ============================================================================

-- Called when drag stops to check for snap and update pending snap
function LayoutUI:CheckForSnapTarget(elementId)
    local SnapLocking = TUICD.SnapLocking
    if not SnapLocking then return end
    
    local element = Layout:GetElement(elementId)
    if not element or not element.tuiFrame then return end
    
    -- Skip if already attached AND the attachment is valid (parent exists)
    -- If attachment is broken (parent missing), allow re-snapping
    if SnapLocking:IsAttached(elementId) and SnapLocking:IsAttachmentValid(elementId) then
        return
    end
    
    -- If we have a broken attachment, clear it so we can re-attach
    if SnapLocking:IsAttached(elementId) and not SnapLocking:IsAttachmentValid(elementId) then
        if TUICD.PrintDebug then
            TUICD:PrintDebug("CheckForSnapTarget: Clearing broken attachment for " .. elementId)
        end
        SnapLocking:RemoveAttachment(elementId)
    end
    
    -- Check for snap target using settings tolerance
    local settings = Layout:GetSnappingSettings()
    local tolerance = settings.tolerance or 50
    
    -- Safety check: ensure tuiFrame has GetSnapTarget method
    if not element.tuiFrame.GetSnapTarget then
        if TUICD.PrintDebug then
            TUICD:PrintDebug("CheckForSnapTarget: tuiFrame for " .. elementId .. " has no GetSnapTarget method")
        end
        return
    end
    
    local relFrame, point, relPoint, x, y = element.tuiFrame:GetSnapTarget(tolerance)
    
    -- Debug: Show when snap target is found
    if TUICD.PrintDebug and relFrame then
        TUICD:PrintDebug("CheckForSnapTarget: Found potential target for " .. elementId)
    end
    
    if relFrame and relFrame.tuiFrame then
        local targetTUIFrameId = relFrame.tuiFrame.id
        
        -- IMPORTANT: Find the Layout element ID that owns this TUIFrame
        -- The Layout element ID may differ from the TUIFrame ID
        local parentId = nil
        for id, elem in pairs(Layout:GetAllElements()) do
            if elem.tuiFrame and elem.tuiFrame.id == targetTUIFrameId then
                parentId = id
                break
            end
        end
        
        -- Fallback to TUIFrame ID if no Layout element found
        if not parentId then
            parentId = targetTUIFrameId
            if TUICD.PrintDebug then
                TUICD:PrintDebug("CheckForSnapTarget: No Layout element found for TUIFrame " .. targetTUIFrameId .. ", using TUIFrame ID")
            end
        end
        
        -- Don't snap to self
        if parentId ~= elementId then
            if TUICD.PrintDebug then
                TUICD:PrintDebug("CheckForSnapTarget: " .. elementId .. " snapped near " .. parentId)
            end
            SnapLocking:SetPendingSnap(elementId, parentId, point, relPoint, x, y)
            self:UpdateAttachmentDisplay()
            return
        end
    end
    
    -- No snap target found - clear any pending snap for this element
    local pendingSnap = SnapLocking:GetPendingSnap()
    if pendingSnap and pendingSnap.childId == elementId then
        SnapLocking:ClearPendingSnap()
        self:UpdateAttachmentDisplay()
    end
end

-- Create a pending snap manually (when user selects from dropdown)
function LayoutUI:CreateManualPendingSnap(childId, parentId)
    local SnapLocking = TUICD.SnapLocking
    if not SnapLocking then return end
    
    local childElement = Layout:GetElement(childId)
    local parentElement = Layout:GetElement(parentId)
    
    if not childElement or not childElement.tuiFrame then return end
    if not parentElement or not parentElement.tuiFrame then return end
    
    local childFrame = childElement.tuiFrame.frame
    local parentFrame = parentElement.tuiFrame.frame
    
    -- Calculate current offset between frames
    local childLeft, childBottom = childFrame:GetLeft(), childFrame:GetBottom()
    local parentLeft, parentBottom = parentFrame:GetLeft(), parentFrame:GetBottom()
    
    if not childLeft or not parentLeft then return end
    
    local offsetX = childLeft - parentLeft
    local offsetY = childBottom - parentBottom
    
    -- Create pending snap with BOTTOMLEFT anchoring (most reliable)
    SnapLocking:SetPendingSnap(childId, parentId, "BOTTOMLEFT", "BOTTOMLEFT", offsetX, offsetY)
    
    -- Update offset display
    if coordPanel then
        coordPanel.attachOffsetLabel:SetText(string.format("Offset: %.0f, %.0f", offsetX, offsetY))
    end
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("CreateManualPendingSnap: " .. childId .. " -> " .. parentId .. " offset " .. offsetX .. ", " .. offsetY)
    end
end

-- Show the custom element selection list
function LayoutUI:ShowElementList()
    if not coordPanel or not coordPanel.elementList then return end
    
    local selectedId = Layout:GetSelectedElement()
    if not selectedId then return end
    
    local elementList = coordPanel.elementList
    local scrollChild = elementList.scrollChild
    
    -- Clear existing buttons and labels
    for _, btn in ipairs(elementList.buttons or {}) do
        btn:Hide()
        btn:SetParent(nil)
    end
    for _, lbl in ipairs(elementList.labels or {}) do
        lbl:Hide()
    end
    wipe(elementList.buttons)
    wipe(elementList.labels)
    
    -- Get all elements and sort them
    local elements = Layout:GetAllElements()
    local sortedElements = {}
    for id, element in pairs(elements) do
        if id ~= selectedId then
            table.insert(sortedElements, { 
                id = id, 
                name = element.name or id, 
                category = element.category or "General" 
            })
        end
    end
    table.sort(sortedElements, function(a, b)
        if a.category ~= b.category then
            return a.category < b.category
        end
        return a.name < b.name
    end)
    
    local yOffset = 5
    local buttonHeight = 18
    
    -- Add "Use Nearest (auto)" at top
    local nearestBtn = CreateFrame("Button", nil, scrollChild)
    nearestBtn:SetSize(140, buttonHeight)
    nearestBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, -yOffset)
    nearestBtn:SetFrameLevel(5003)
    local nearestText = nearestBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nearestText:SetPoint("LEFT", 5, 0)
    nearestText:SetText("|cff00ff00Use Nearest (auto)|r")
    nearestBtn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
    nearestBtn:SetScript("OnClick", function()
        TUICD:Print("Use Nearest selected")
        coordPanel.useCustomParent = false
        coordPanel.selectedParentId = nil
        elementList:Hide()
        self:ClearNearbyHighlight()
        self:UpdateAttachmentDisplay()
    end)
    table.insert(elementList.buttons, nearestBtn)
    yOffset = yOffset + buttonHeight + 5
    
    -- Add elements grouped by category
    local currentCategory = nil
    for _, elem in ipairs(sortedElements) do
        -- Add category header if changed
        if elem.category ~= currentCategory then
            currentCategory = elem.category
            local catLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            catLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, -yOffset)
            catLabel:SetText("|cff00ccff" .. currentCategory .. "|r")
            table.insert(elementList.labels, catLabel)
            yOffset = yOffset + buttonHeight
        end
        
        -- Add element button
        local btn = CreateFrame("Button", nil, scrollChild)
        btn:SetSize(135, buttonHeight)
        btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset)
        btn:SetFrameLevel(5003)
        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnText:SetPoint("LEFT", 5, 0)
        btnText:SetText(elem.name)
        btn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
        
        local targetId = elem.id
        local targetName = elem.name
        btn:SetScript("OnClick", function()
            TUICD:Print("Selected: " .. targetName)
            
            local currentSelectedId = Layout:GetSelectedElement()
            if not currentSelectedId then return end
            
            -- Set custom parent state
            coordPanel.useCustomParent = true
            coordPanel.selectedParentId = targetId
            
            -- Create pending snap
            self:CreateManualPendingSnap(currentSelectedId, targetId)
            
            -- Highlight the target element
            self:HighlightNearbyElement(targetId)
            
            -- Hide the list and update display
            elementList:Hide()
            self:UpdateAttachmentDisplay()
        end)
        
        -- Highlight on hover
        btn:SetScript("OnEnter", function()
            self:HighlightNearbyElement(targetId)
        end)
        btn:SetScript("OnLeave", function()
            if not coordPanel.useCustomParent or coordPanel.selectedParentId ~= targetId then
                self:ClearNearbyHighlight()
            end
        end)
        
        table.insert(elementList.buttons, btn)
        yOffset = yOffset + buttonHeight
    end
    
    -- Set scroll child height
    scrollChild:SetHeight(yOffset + 10)
    
    -- Show the list
    elementList:Show()
    elementList:Raise()
end

-- ============================================================================
-- SIZE MATCH MODE POPUP
-- ============================================================================
-- Popup dialog for choosing which component to match when working with unit frames

local sizeMatchModePopup = nil

function LayoutUI:CreateSizeMatchModePopup()
    if sizeMatchModePopup then return sizeMatchModePopup end
    
    -- Parent to containerFrame like coordPanel does
    local popup = CreateFrame("Frame", "TweaksUI_SizeMatchModePopup", containerFrame, "BackdropTemplate")
    popup:SetSize(280, 150)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self) self:StartMoving() end)
    popup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(9999)  -- Same as coordPanel
    popup:SetToplevel(true)  -- Ensure it stays on top when clicked
    popup:Hide()
    
    -- Raise panel when shown or clicked to stay above overlays
    popup:SetScript("OnShow", function(self)
        self:Raise()
    end)
    popup:HookScript("OnMouseDown", function(self)
        self:Raise()
    end)
    
    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffffd100Match Size To...|r")
    popup.title = title
    
    -- Description
    local desc = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOP", title, "BOTTOM", 0, -8)
    desc:SetWidth(250)
    desc:SetText("Which component should be matched?")
    desc:SetTextColor(0.8, 0.8, 0.8)
    popup.desc = desc
    
    -- Health Bar button
    local healthBarBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    healthBarBtn:SetSize(120, 28)
    healthBarBtn:SetPoint("TOPLEFT", desc, "BOTTOM", -125, -15)
    healthBarBtn:SetText("Health Bar")
    healthBarBtn:SetScript("OnClick", function()
        if popup.callback then
            popup.callback("healthBar")
        end
        popup:Hide()
    end)
    popup.healthBarBtn = healthBarBtn
    
    -- Frame button
    local frameBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    frameBtn:SetSize(120, 28)
    frameBtn:SetPoint("LEFT", healthBarBtn, "RIGHT", 10, 0)
    frameBtn:SetText("Entire Frame")
    frameBtn:SetScript("OnClick", function()
        if popup.callback then
            popup.callback("frame")
        end
        popup:Hide()
    end)
    popup.frameBtn = frameBtn
    
    -- Close button
    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 22)
    cancelBtn:SetPoint("BOTTOM", 0, 12)
    cancelBtn:SetText("Close")
    cancelBtn:SetScript("OnClick", function()
        if popup.cancelCallback then
            popup.cancelCallback()
        end
        popup:Hide()
    end)
    popup.cancelBtn = cancelBtn
    
    sizeMatchModePopup = popup
    return popup
end

-- Show the popup for choosing match mode
-- @param matchType "width" or "height"
-- @param callback function(mode) - called with "healthBar" or "frame"
-- @param cancelCallback function() - called if user cancels
function LayoutUI:ShowSizeMatchModePopup(matchType, callback, cancelCallback)
    local popup = self:CreateSizeMatchModePopup()
    
    -- Update title based on match type
    if matchType == "width" then
        popup.title:SetText("|cffffd100Match Width To...|r")
    elseif matchType == "height" then
        popup.title:SetText("|cffffd100Match Height To...|r")
    else
        popup.title:SetText("|cffffd100Match Size To...|r")
    end
    
    popup.callback = callback
    popup.cancelCallback = cancelCallback
    popup:Show()
    popup:Raise()
end

-- Check if an element ID is a unit frame
function LayoutUI:IsUnitFrameElement(elementId)
    if not elementId then return false end
    return elementId:match("^unitframe_") ~= nil
end

-- Get the unit type from a unit frame element ID
function LayoutUI:GetUnitFromElementId(elementId)
    if not elementId then return nil end
    local unit = elementId:match("^unitframe_(.+)$")
    return unit
end

-- ============================================================================
-- PER-ICON REGISTRATION (for individual highlight frames)
-- ============================================================================

-- Per-icon frames registered for layout mode
local perIconFrames = {}  -- [elementId] = { frame, trackerKey, slotIndex, displayName }

-- Generate element ID for per-icon frame
local function GetPerIconElementId(trackerKey, slotIndex)
    -- Match the patterns used in IsElementDocked():
    -- buffs -> BuffHighlight_N
    -- essential -> TweaksUI_EssentialHighlight_N
    -- utility -> TweaksUI_UtilityHighlight_N
    -- customTrackers -> TweaksUI_CustomHighlight_N
    if trackerKey == "buffs" then
        return "BuffHighlight_" .. slotIndex
    elseif trackerKey == "essential" then
        return "TweaksUI_EssentialHighlight_" .. slotIndex
    elseif trackerKey == "utility" then
        return "TweaksUI_UtilityHighlight_" .. slotIndex
    elseif trackerKey == "customTrackers" then
        return "TweaksUI_CustomHighlight_" .. slotIndex
    else
        return trackerKey .. "_Highlight_" .. slotIndex
    end
end

-- Register an individual icon frame for Layout Mode dragging
function LayoutUI:RegisterPerIconFrame(frame, trackerKey, slotIndex, displayName)
    if not frame or not trackerKey or not slotIndex then return end
    if not Layout then return end
    
    local elementId = GetPerIconElementId(trackerKey, slotIndex)
    displayName = displayName or (trackerKey .. " Icon " .. slotIndex)
    
    -- Store reference
    perIconFrames[elementId] = {
        frame = frame,
        trackerKey = trackerKey,
        slotIndex = slotIndex,
        displayName = displayName,
    }
    
    -- Create a TUIFrame-compatible wrapper for the icon
    local wrapper = {
        id = elementId,
        frame = frame,
        name = displayName,
        
        -- Position management (icons use relative positioning to tracker container)
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            if InCombatLockdown() then return end
            -- Per-icon frames generally don't support independent positioning
            -- They're positioned by their parent container or dock
        end,
        
        GetSaveData = function(self)
            local left = frame:GetLeft()
            local bottom = frame:GetBottom()
            if left and bottom then
                return { point = "BOTTOMLEFT", x = left, y = bottom }
            end
            return { point = "CENTER", x = 0, y = 0 }
        end,
        
        LoadSaveData = function(self, data)
            -- Per-icon frames don't load position data directly
        end,
        
        GetSize = function(self)
            return frame:GetSize()
        end,
        
        GetWidth = function(self)
            return frame:GetWidth()
        end,
        
        GetHeight = function(self)
            return frame:GetHeight()
        end,
        
        GetScale = function(self)
            return frame:GetScale() or 1
        end,
        
        Show = function(self)
            frame:Show()
        end,
        
        Hide = function(self)
            frame:Hide()
        end,
        
        IsShown = function(self)
            return frame:IsShown()
        end,
        
        -- No snap target for individual icons (they snap via their container)
        GetSnapTarget = function(self, tolerance)
            return nil
        end,
    }
    
    -- Register with Layout module
    Layout:RegisterElement(elementId, {
        name = displayName,
        category = Layout.CATEGORIES and Layout.CATEGORIES.COOLDOWNS or "Cooldowns",
        tuiFrame = wrapper,
        defaultPosition = { point = "CENTER", x = 0, y = 0 },
    })
    
    return elementId
end

-- Unregister a per-icon frame
function LayoutUI:UnregisterPerIconFrame(trackerKey, slotIndex)
    if not Layout then return end
    
    local elementId = GetPerIconElementId(trackerKey, slotIndex)
    
    if perIconFrames[elementId] then
        Layout:UnregisterElement(elementId)
        perIconFrames[elementId] = nil
    end
end

-- Refresh a specific per-icon overlay (update position/visibility)
function LayoutUI:RefreshPerIconOverlay(trackerKey, slotIndex)
    if not Layout then return end
    
    local elementId = GetPerIconElementId(trackerKey, slotIndex)
    local element = Layout:GetElement(elementId)
    
    if element then
        self:UpdateOverlayPosition(element)
        
        -- Also update visibility based on current frame state
        local overlay = overlays[elementId]
        if overlay and element.tuiFrame then
            if element.tuiFrame:IsShown() then
                overlay:Show()
            else
                overlay:Hide()
            end
        end
    end
end

-- Get all per-icon frames for a tracker type
function LayoutUI:GetPerIconFrames(trackerKey)
    local result = {}
    for elementId, data in pairs(perIconFrames) do
        if data.trackerKey == trackerKey then
            result[data.slotIndex] = data
        end
    end
    return result
end

-- Create TUICD.LayoutMode alias for backward compatibility
-- (BuffHighlights and other modules check for TUICD.LayoutMode)
TUICD.LayoutMode = LayoutUI
