-- ============================================================================
-- TUICD: SnapLocking
-- Frame attachment and locking system - locked frames move together
-- Supports chains (A→B→C) and size inheritance
-- ============================================================================

local ADDON_NAME, TUICD = ...

local SnapLocking = {}
TUICD.SnapLocking = SnapLocking

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Size matching modes
SnapLocking.SIZE_MODE = {
    NONE = "none",           -- No size matching
    STRETCH = "stretch",     -- Simple SetWidth/SetHeight
    CROP = "crop",           -- For icon bars - crop icons to fit
}

-- ============================================================================
-- STATE
-- ============================================================================

-- Attachment registry: childId -> attachment data
local attachments = {}

-- Pending snap detection (before user confirms lock)
local pendingSnap = nil

-- Callback registry
local callbacks = {}

-- ============================================================================
-- ATTACHMENT DATA STRUCTURE
-- ============================================================================

--[[
    Attachment data structure:
    {
        childId = "string",           -- ID of the child frame
        parentId = "string",          -- ID of the parent frame
        point = "TOPLEFT",            -- Child's anchor point
        relPoint = "BOTTOMLEFT",      -- Parent's anchor point
        offsetX = 0,                  -- X offset from parent
        offsetY = -5,                 -- Y offset from parent
        matchWidth = false,           -- Whether to match parent's width
        matchHeight = false,          -- Whether to match parent's height
        widthOffset = 0,              -- Added to parent width (can be negative)
        heightOffset = 0,             -- Added to parent height (can be negative)
        widthMode = "stretch",        -- How to apply width: "stretch" or "crop"
        heightMode = "stretch",       -- How to apply height: "stretch" or "crop"
    }
]]

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function SnapLocking:Initialize()
    if TUICD.PrintDebug then
        TUICD:PrintDebug("SnapLocking: Initializing...")
        -- Check raw saved variables
        if TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.layout then
            local attData = TweaksUI_Cooldowns_CharDB.settings.layout.attachments
            if attData then
                local count = 0
                for _ in pairs(attData) do count = count + 1 end
                TUICD:PrintDebug("SnapLocking: Found " .. count .. " attachments in raw saved variables")
            else
                TUICD:PrintDebug("SnapLocking: No attachments in raw saved variables")
            end
        else
            TUICD:PrintDebug("SnapLocking: layout settings not yet created")
        end
    end
    
    -- Load saved attachments from Layout settings
    self:LoadAttachments()
end

-- ============================================================================
-- ATTACHMENT MANAGEMENT
-- ============================================================================

--[[
    Create an attachment between two frames
    
    @param childId string - ID of the child frame (the one being attached)
    @param parentId string - ID of the parent frame (the one to attach to)
    @param options table - Attachment options
    @return boolean - Success
]]
function SnapLocking:CreateAttachment(childId, parentId, options)
    if not childId or not parentId then
        return false
    end
    
    -- Prevent self-attachment
    if childId == parentId then
        TUICD:PrintError("Cannot attach a frame to itself")
        return false
    end
    
    -- Prevent circular attachments
    if self:WouldCreateCycle(childId, parentId) then
        TUICD:PrintError("Cannot create circular attachment")
        return false
    end
    
    options = options or {}
    
    local attachment = {
        childId = childId,
        parentId = parentId,
        point = options.point or "TOPLEFT",
        relPoint = options.relPoint or "BOTTOMLEFT",
        offsetX = options.offsetX or 0,
        offsetY = options.offsetY or 0,
        matchWidth = options.matchWidth or false,
        matchHeight = options.matchHeight or false,
        widthOffset = options.widthOffset or 0,
        heightOffset = options.heightOffset or 0,
        widthMode = options.widthMode or SnapLocking.SIZE_MODE.STRETCH,
        heightMode = options.heightMode or SnapLocking.SIZE_MODE.STRETCH,
    }
    
    -- Store attachment
    attachments[childId] = attachment
    
    -- Apply the attachment immediately
    self:ApplyAttachment(childId)
    
    -- Save to persistent storage
    self:SaveAttachments()
    
    -- Fire callback
    self:FireCallback("OnAttachmentCreated", childId, parentId, attachment)
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("SnapLocking: Created attachment " .. childId .. " -> " .. parentId)
    end
    
    return true
end

--[[
    Remove an attachment
    
    @param childId string - ID of the child frame to detach
    @return boolean - Success
]]
function SnapLocking:RemoveAttachment(childId)
    if not childId or not attachments[childId] then
        return false
    end
    
    local oldParentId = attachments[childId].parentId
    local attachment = attachments[childId]
    
    -- Get the TUIFrame
    local childTUI = self:GetTUIFrame(childId)
    
    -- If there was size matching, preserve the current size before unlocking
    -- This ensures the frame keeps its matched size when detached
    if childTUI and (attachment.matchWidth or attachment.matchHeight) then
        local currentWidth, currentHeight = childTUI:GetSize()
        
        -- Save the size to the Layout module's element data so it persists
        if TUICD.Layout then
            local settings = TUICD.Layout:GetSettings()
            if settings and settings.elements then
                if not settings.elements[childId] then
                    settings.elements[childId] = {}
                end
                -- Save the matched dimensions
                if attachment.matchWidth then
                    settings.elements[childId].matchedWidth = currentWidth
                end
                if attachment.matchHeight then
                    settings.elements[childId].matchedHeight = currentHeight
                end
            end
        end
        
        if TUICD.PrintDebug then
            TUICD:PrintDebug(string.format("RemoveAttachment: Preserving size %.0fx%.0f for %s",
                currentWidth, currentHeight, childId))
        end
    end
    
    -- Unlock size
    if childTUI then
        childTUI:SetSizeLocked(false)
    end
    
    -- Remove from registry
    attachments[childId] = nil
    
    -- Save to persistent storage
    self:SaveAttachments()
    
    -- Fire callback
    self:FireCallback("OnAttachmentRemoved", childId, oldParentId)
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("SnapLocking: Removed attachment for " .. childId)
    end
    
    return true
end

--[[
    Remove all attachments (locks) but preserve element positions
    
    @return number - Count of attachments removed
]]
function SnapLocking:ClearAllAttachments()
    local count = 0
    local idsToRemove = {}
    
    -- Collect all attachment IDs first (can't modify during iteration)
    for childId, _ in pairs(attachments) do
        table.insert(idsToRemove, childId)
    end
    
    -- Remove each attachment
    for _, childId in ipairs(idsToRemove) do
        if self:RemoveAttachment(childId) then
            count = count + 1
        end
    end
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("SnapLocking: Cleared " .. count .. " attachments")
    end
    
    return count
end

--[[
    Get attachment data for a frame
    
    @param childId string - ID of the child frame
    @return table|nil - Attachment data or nil if not attached
]]
function SnapLocking:GetAttachment(childId)
    return attachments[childId]
end

--[[
    Check if a frame is attached to something
    
    @param childId string - ID of the frame to check
    @return boolean
]]
function SnapLocking:IsAttached(childId)
    return attachments[childId] ~= nil
end

--[[
    Check if an attachment is valid (both child and parent frames exist)
    
    @param childId string - ID of the child frame
    @return boolean - True if attachment exists AND parent frame exists
]]
function SnapLocking:IsAttachmentValid(childId)
    local attachment = attachments[childId]
    if not attachment then return false end
    
    -- Check if parent frame exists
    local parentTUI = self:GetTUIFrame(attachment.parentId)
    return parentTUI ~= nil
end

--[[
    Get the parent ID that a frame is attached to
    
    @param childId string - ID of the child frame
    @return string|nil - Parent ID or nil
]]
function SnapLocking:GetParentId(childId)
    local attachment = attachments[childId]
    return attachment and attachment.parentId or nil
end

--[[
    Get all children attached to a parent
    
    @param parentId string - ID of the parent frame
    @return table - Array of child IDs
]]
function SnapLocking:GetChildren(parentId)
    local children = {}
    for childId, attachment in pairs(attachments) do
        if attachment.parentId == parentId then
            table.insert(children, childId)
        end
    end
    return children
end

--[[
    Get all descendants (children, grandchildren, etc.) of a frame
    
    @param parentId string - ID of the parent frame
    @return table - Array of descendant IDs
]]
function SnapLocking:GetDescendants(parentId)
    local descendants = {}
    local visited = {}
    
    local function collectDescendants(id, depth)
        if visited[id] then return end
        visited[id] = true
        
        local children = self:GetChildren(id)
        
        if TUICD.PrintDebug and #children > 0 then
            local indent = string.rep("  ", depth)
            TUICD:PrintDebug("GetDescendants: " .. indent .. id .. " has children: " .. table.concat(children, ", "))
        end
        
        for _, childId in ipairs(children) do
            table.insert(descendants, childId)
            collectDescendants(childId, depth + 1)
        end
    end
    
    collectDescendants(parentId, 0)
    return descendants
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    Get TUIFrame for a frame ID (tries Layout element first, then direct TUIFrame lookup)
    
    @param frameId string - Either a Layout element ID or TUIFrame ID
    @return TUIFrame|nil
]]
function SnapLocking:GetTUIFrame(frameId)
    -- First try to get via Layout element (preferred)
    if TUICD.Layout then
        local element = TUICD.Layout:GetElement(frameId)
        if element and element.tuiFrame then
            return element.tuiFrame
        end
    end
    
    -- Fallback to direct TUIFrame lookup
    return TUICD.TUIFrame.Get(frameId)
end

-- ============================================================================
-- CYCLE DETECTION
-- ============================================================================

--[[
    Check if attaching childId to parentId would create a cycle
    
    @param childId string
    @param parentId string
    @return boolean - True if it would create a cycle
]]
function SnapLocking:WouldCreateCycle(childId, parentId)
    -- Check if parentId is already a descendant of childId
    local descendants = self:GetDescendants(childId)
    for _, descId in ipairs(descendants) do
        if descId == parentId then
            return true
        end
    end
    return false
end

-- ============================================================================
-- CONNECTED GROUP (for unified movement)
-- ============================================================================

--[[
    Get the root frame of a chain (the topmost parent that isn't attached to anything)
    
    @param frameId string - Any frame in the chain
    @return string - The root frame ID
]]
function SnapLocking:GetChainRoot(frameId)
    local currentId = frameId
    local visited = {}
    local path = { frameId }
    
    while true do
        -- Prevent infinite loops
        if visited[currentId] then
            break
        end
        visited[currentId] = true
        
        local attachment = attachments[currentId]
        if not attachment then
            -- This frame has no parent, it's the root
            if TUICD.PrintDebug then
                TUICD:PrintDebug("GetChainRoot: Path to root: " .. table.concat(path, " -> "))
            end
            return currentId
        end
        
        currentId = attachment.parentId
        table.insert(path, currentId)
    end
    
    return currentId
end

--[[
    Get ALL frames connected to a given frame (entire group)
    This includes the chain root, all its descendants, and any frame connected anywhere
    
    @param frameId string - Any frame in the connected group
    @return table - Array of all connected frame IDs (including the input frame)
]]
function SnapLocking:GetConnectedGroup(frameId)
    -- First, find the root of this chain
    local rootId = self:GetChainRoot(frameId)
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("GetConnectedGroup: Input=" .. frameId .. ", Root=" .. rootId)
    end
    
    -- Then get the root + all its descendants
    local group = { rootId }
    local descendants = self:GetDescendants(rootId)
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("GetConnectedGroup: Descendants of " .. rootId .. ": " .. (#descendants > 0 and table.concat(descendants, ", ") or "(none)"))
    end
    
    for _, descId in ipairs(descendants) do
        table.insert(group, descId)
    end
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("GetConnectedGroup: Final group: " .. table.concat(group, ", "))
    end
    
    return group
end

--[[
    Check if a frame is part of any locked group
    
    @param frameId string
    @return boolean
]]
function SnapLocking:IsInLockedGroup(frameId)
    -- Check if this frame is attached to something
    if attachments[frameId] then
        return true
    end
    
    -- Check if any frame is attached to this one
    for _, attachment in pairs(attachments) do
        if attachment.parentId == frameId then
            return true
        end
    end
    
    return false
end

--[[
    Get the position offsets of all frames in a group relative to a reference frame
    Used for unified movement
    
    @param groupFrameIds table - Array of frame IDs in the group
    @param referenceId string - The frame being dragged (reference point)
    @return table - Map of frameId -> {offsetX, offsetY} relative to reference
]]
function SnapLocking:GetGroupOffsets(groupFrameIds, referenceId)
    local offsets = {}
    
    local refTUI = self:GetTUIFrame(referenceId)
    if not refTUI then return offsets end
    
    local refFrame = refTUI.frame
    local refLeft, refBottom = refFrame:GetLeft(), refFrame:GetBottom()
    
    if not refLeft or not refBottom then return offsets end
    
    for _, frameId in ipairs(groupFrameIds) do
        if frameId ~= referenceId then
            local tui = self:GetTUIFrame(frameId)
            if tui then
                local frame = tui.frame
                local left, bottom = frame:GetLeft(), frame:GetBottom()
                if left and bottom then
                    offsets[frameId] = {
                        offsetX = left - refLeft,
                        offsetY = bottom - refBottom,
                    }
                end
            end
        end
    end
    
    return offsets
end

--[[
    Move all frames in a group based on reference frame's new position
    
    @param referenceId string - The frame being dragged
    @param groupOffsets table - Offsets from GetGroupOffsets()
]]
function SnapLocking:MoveGroupWithReference(referenceId, groupOffsets)
    local refTUI = self:GetTUIFrame(referenceId)
    if not refTUI then return end
    
    local refFrame = refTUI.frame
    local refLeft, refBottom = refFrame:GetLeft(), refFrame:GetBottom()
    
    if not refLeft or not refBottom then return end
    
    for frameId, offset in pairs(groupOffsets) do
        local tui = self:GetTUIFrame(frameId)
        if tui then
            local frame = tui.frame
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 
                refLeft + offset.offsetX, 
                refBottom + offset.offsetY)
        end
    end
end

-- ============================================================================
-- ATTACHMENT APPLICATION
-- ============================================================================

--[[
    Apply an attachment - position child relative to parent
    
    @param childId string - ID of the child frame
]]
function SnapLocking:ApplyAttachment(childId)
    local attachment = attachments[childId]
    if not attachment then return end
    
    -- Get TUIFrame instances using the helper (handles Layout element IDs)
    local childTUI = self:GetTUIFrame(childId)
    local parentTUI = self:GetTUIFrame(attachment.parentId)
    
    if not childTUI or not parentTUI then
        if TUICD.PrintDebug then
            TUICD:PrintDebug("SnapLocking: Cannot apply attachment - missing frame(s) for " .. childId)
            TUICD:PrintDebug("  childTUI: " .. (childTUI and "found" or "MISSING"))
            TUICD:PrintDebug("  parentTUI (" .. attachment.parentId .. "): " .. (parentTUI and "found" or "MISSING"))
        end
        return
    end
    
    local childFrame = childTUI.frame
    
    -- Check if frame is protected and we're in combat - skip if so
    if InCombatLockdown() then
        local isProtected = childFrame:IsProtected()
        if isProtected then
            if TUICD.PrintDebug then
                TUICD:PrintDebug("SnapLocking: Skipping protected frame " .. childId .. " during combat")
            end
            return
        end
    end
    
    -- Use saved absolute position if available (most reliable)
    if attachment.absoluteX and attachment.absoluteY then
        childFrame:ClearAllPoints()
        childFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", attachment.absoluteX, attachment.absoluteY)
        
        if TUICD.PrintDebug then
            TUICD:PrintDebug(string.format("SnapLocking: Applied absolute position for %s: %.1f, %.1f",
                childId, attachment.absoluteX, attachment.absoluteY))
        end
    else
        -- Fallback to relative positioning
        local parentFrame = parentTUI.frame
        childFrame:ClearAllPoints()
        childFrame:SetPoint(
            attachment.point,
            parentFrame,
            attachment.relPoint,
            attachment.offsetX,
            attachment.offsetY
        )
    end
    
    -- Apply size matching if enabled
    self:ApplySizeMatching(childId)
end

--[[
    Save absolute positions for all attached frames
    Called when exiting layout mode to capture exact screen positions
]]
function SnapLocking:SaveAbsolutePositions()
    for childId, attachment in pairs(attachments) do
        local childTUI = self:GetTUIFrame(childId)
        if childTUI and childTUI.frame then
            local frame = childTUI.frame
            local left, bottom = frame:GetLeft(), frame:GetBottom()
            if left and bottom then
                attachment.absoluteX = left
                attachment.absoluteY = bottom
                
                if TUICD.PrintDebug then
                    TUICD:PrintDebug(string.format("SnapLocking: Saved absolute position for %s: %.1f, %.1f",
                        childId, left, bottom))
                end
            end
        end
    end
    
    -- Save to persistent storage
    self:SaveAttachments()
end

--[[
    Apply size matching from parent to child
    Maintains the child's center position relative to the attachment point
    Also fires onSizeChanged callback so modules can update their settings
    
    @param childId string - ID of the child frame
    @param options table - Optional: { skipCallback = true } to skip firing callback
]]
function SnapLocking:ApplySizeMatching(childId, options)
    options = options or {}
    local attachment = attachments[childId]
    if not attachment then return end
    
    local childTUI = self:GetTUIFrame(childId)
    if not childTUI then return end
    
    -- If no size matching, unlock the frame's size
    if not attachment.matchWidth and not attachment.matchHeight then
        childTUI:SetSizeLocked(false)
        return
    end
    
    local childWidth, childHeight = childTUI:GetSize()
    local newWidth = childWidth
    local newHeight = childHeight
    
    -- Use saved size if available (from previous session or profile import)
    -- Otherwise calculate from parent using GetOuterSize for full visual bounds
    if attachment.savedWidth and attachment.matchWidth then
        newWidth = attachment.savedWidth
    elseif attachment.matchWidth then
        local parentTUI = self:GetTUIFrame(attachment.parentId)
        if parentTUI then
            -- Use GetOuterSize to include borders in the measurement
            local parentWidth, _ = parentTUI:GetOuterSize()
            newWidth = parentWidth + (attachment.widthOffset or 0)
        end
    end
    
    if attachment.savedHeight and attachment.matchHeight then
        newHeight = attachment.savedHeight
    elseif attachment.matchHeight then
        local parentTUI = self:GetTUIFrame(attachment.parentId)
        if parentTUI then
            -- Use GetOuterSize to include borders in the measurement
            local _, parentHeight = parentTUI:GetOuterSize()
            newHeight = parentHeight + (attachment.heightOffset or 0)
        end
    end
    
    -- Store the new size in the attachment for persistence
    if attachment.matchWidth then
        attachment.savedWidth = newWidth
    end
    if attachment.matchHeight then
        attachment.savedHeight = newHeight
    end
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug(string.format("ApplySizeMatching: %s from %.0fx%.0f to %.0fx%.0f (wTarget=%s, hTarget=%s)",
            childId, childWidth, childHeight, newWidth, newHeight, 
            tostring(attachment.widthTarget), tostring(attachment.heightTarget)))
    end
    
    -- Fire onSizeChanged callback FIRST so module can update its settings
    -- This allows the module to decide what to do based on the mode
    -- For unit frames with healthBar mode, the frame won't be resized by us
    -- - the module will resize the health bar and trigger its own re-layout
    if not options.skipCallback and TUICD.Layout then
        local element = TUICD.Layout:GetElement(childId)
        if element and element.onSizeChanged then
            local sizeOptions = {
                widthTarget = attachment.widthTarget,
                heightTarget = attachment.heightTarget,
            }
            -- Pass width and height that should be matched to
            element.onSizeChanged(childId, newWidth, newHeight, sizeOptions)
            if TUICD.PrintDebug then
                TUICD:PrintDebug(string.format("ApplySizeMatching: Fired onSizeChanged for %s (%.0fx%.0f, wTarget=%s, hTarget=%s)",
                    childId, newWidth, newHeight, tostring(attachment.widthTarget), tostring(attachment.heightTarget)))
            end
        end
    end
    
    -- Only resize wrapper if NOT using healthBar mode for both dimensions
    -- If using healthBar mode, the module handles resizing the health bar internally
    local isHealthBarMode = (attachment.widthTarget == "healthBar" or attachment.heightTarget == "healthBar")
    
    if not isHealthBarMode then
        -- Resize the wrapper
        childTUI:ForceSetSize(newWidth, newHeight)
        
        -- Lock the wrapper size so TUIFrame:SetSize() is blocked
        childTUI:SetSizeLocked(true)
        
        -- Re-anchor child frames to stretch with wrapper
        local wrapperFrame = childTUI.frame
        local children = { wrapperFrame:GetChildren() }
        for _, child in ipairs(children) do
            child:ClearAllPoints()
            child:SetPoint("TOPLEFT", wrapperFrame, "TOPLEFT", 0, 0)
            child:SetPoint("BOTTOMRIGHT", wrapperFrame, "BOTTOMRIGHT", 0, 0)
        end
    else
        -- Health bar mode - don't lock the wrapper size, let module manage it
        childTUI:SetSizeLocked(false)
    end
    
    -- Save attachments to persist the size
    self:SaveAttachments()
end

--[[
    Save current sizes for all attached frames with size matching
    Called when exiting layout mode to capture actual sizes
]]
function SnapLocking:SaveCurrentSizes()
    for childId, attachment in pairs(attachments) do
        if attachment.matchWidth or attachment.matchHeight then
            local childTUI = self:GetTUIFrame(childId)
            if childTUI then
                local width, height = childTUI:GetSize()
                if attachment.matchWidth then
                    attachment.savedWidth = width
                end
                if attachment.matchHeight then
                    attachment.savedHeight = height
                end
                
                if TUICD.PrintDebug then
                    TUICD:PrintDebug(string.format("SaveCurrentSizes: %s = %.0fx%.0f",
                        childId, width, height))
                end
            end
        end
    end
end

--[[
    Propagate movement from a parent to all its descendants
    Called when a parent frame is moved
    
    @param parentId string - ID of the parent frame that moved
]]
function SnapLocking:PropagateMovement(parentId)
    local descendants = self:GetDescendants(parentId)
    
    for _, childId in ipairs(descendants) do
        self:ApplyAttachment(childId)
    end
end

--[[
    Propagate size change from a parent to all its descendants
    Called when a parent frame is resized
    
    @param parentId string - ID of the parent frame that was resized
]]
function SnapLocking:PropagateSize(parentId)
    local children = self:GetChildren(parentId)
    
    for _, childId in ipairs(children) do
        self:ApplySizeMatching(childId)
        -- Recurse for grandchildren
        self:PropagateSize(childId)
    end
end

-- ============================================================================
-- PENDING SNAP (for confirmation UI)
-- ============================================================================

--[[
    Set a pending snap (detected but not yet locked)
    Called by Layout system when FlyPaper detects a snap
    
    @param childId string - ID of the child frame
    @param parentId string - ID of the parent frame
    @param point string - Child's anchor point
    @param relPoint string - Parent's anchor point
    @param offsetX number
    @param offsetY number
]]
function SnapLocking:SetPendingSnap(childId, parentId, point, relPoint, offsetX, offsetY)
    pendingSnap = {
        childId = childId,
        parentId = parentId,
        point = point,
        relPoint = relPoint,
        offsetX = offsetX,
        offsetY = offsetY,
    }
    
    self:FireCallback("OnPendingSnapDetected", pendingSnap)
end

--[[
    Clear pending snap
]]
function SnapLocking:ClearPendingSnap()
    pendingSnap = nil
    self:FireCallback("OnPendingSnapCleared")
end

--[[
    Get pending snap data
    
    @return table|nil
]]
function SnapLocking:GetPendingSnap()
    return pendingSnap
end

--[[
    Confirm pending snap - convert to locked attachment
    
    @param options table - Additional options (matchWidth, matchHeight, etc.)
    @return boolean - Success
]]
function SnapLocking:ConfirmPendingSnap(options)
    if not pendingSnap then
        return false
    end
    
    options = options or {}
    
    -- Merge pending snap data with options
    local fullOptions = {
        point = pendingSnap.point,
        relPoint = pendingSnap.relPoint,
        offsetX = pendingSnap.offsetX,
        offsetY = pendingSnap.offsetY,
        matchWidth = options.matchWidth or false,
        matchHeight = options.matchHeight or false,
        widthOffset = options.widthOffset or 0,
        heightOffset = options.heightOffset or 0,
        widthMode = options.widthMode or SnapLocking.SIZE_MODE.STRETCH,
        heightMode = options.heightMode or SnapLocking.SIZE_MODE.STRETCH,
    }
    
    local success = self:CreateAttachment(pendingSnap.childId, pendingSnap.parentId, fullOptions)
    
    if success then
        self:ClearPendingSnap()
    end
    
    return success
end

-- ============================================================================
-- UPDATE ATTACHMENT (for nudging after lock)
-- ============================================================================

--[[
    Update offset for an existing attachment
    
    @param childId string
    @param offsetX number
    @param offsetY number
]]
function SnapLocking:UpdateOffset(childId, offsetX, offsetY)
    local attachment = attachments[childId]
    if not attachment then return end
    
    attachment.offsetX = offsetX
    attachment.offsetY = offsetY
    
    -- Re-apply
    self:ApplyAttachment(childId)
    
    -- Save
    self:SaveAttachments()
end

--[[
    Update size matching options for an attachment
    
    @param childId string
    @param options table - matchWidth, matchHeight, widthOffset, heightOffset, widthMode, heightMode, widthTarget, heightTarget
]]
function SnapLocking:UpdateSizeMatching(childId, options)
    local attachment = attachments[childId]
    if not attachment then 
        if TUICD.PrintDebug then
            TUICD:PrintDebug("SnapLocking:UpdateSizeMatching - no attachment for " .. childId)
        end
        return 
    end
    
    if options.matchWidth ~= nil then
        attachment.matchWidth = options.matchWidth
    end
    if options.matchHeight ~= nil then
        attachment.matchHeight = options.matchHeight
    end
    if options.widthOffset ~= nil then
        attachment.widthOffset = options.widthOffset
    end
    if options.heightOffset ~= nil then
        attachment.heightOffset = options.heightOffset
    end
    if options.widthMode ~= nil then
        attachment.widthMode = options.widthMode
    end
    if options.heightMode ~= nil then
        attachment.heightMode = options.heightMode
    end
    -- Target specifies which component to match (healthBar vs frame)
    if options.widthTarget ~= nil then
        attachment.widthTarget = options.widthTarget
    end
    if options.heightTarget ~= nil then
        attachment.heightTarget = options.heightTarget
    end
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("SnapLocking:UpdateSizeMatching - " .. childId .. 
            " now has matchW=" .. tostring(attachment.matchWidth) .. 
            " matchH=" .. tostring(attachment.matchHeight) ..
            " wTarget=" .. tostring(attachment.widthTarget) ..
            " hTarget=" .. tostring(attachment.heightTarget))
    end
    
    -- Re-apply
    self:ApplySizeMatching(childId)
    
    -- Save
    self:SaveAttachments()
end

-- ============================================================================
-- PERSISTENCE
-- ============================================================================

function SnapLocking:SaveAttachments()
    if not TUICD.Layout then 
        if TUICD.PrintDebug then
            TUICD:PrintDebug("SaveAttachments: Layout not available")
        end
        return 
    end
    
    local settings = TUICD.Layout:GetSettings()
    if not settings then 
        if TUICD.PrintDebug then
            TUICD:PrintDebug("SaveAttachments: settings table is nil")
        end
        return 
    end
    
    -- Store in layout settings
    settings.attachments = {}
    for childId, attachment in pairs(attachments) do
        settings.attachments[childId] = {
            parentId = attachment.parentId,
            point = attachment.point,
            relPoint = attachment.relPoint,
            offsetX = attachment.offsetX,
            offsetY = attachment.offsetY,
            matchWidth = attachment.matchWidth,
            matchHeight = attachment.matchHeight,
            widthOffset = attachment.widthOffset,
            heightOffset = attachment.heightOffset,
            widthMode = attachment.widthMode,
            heightMode = attachment.heightMode,
            -- Target component (healthBar vs frame for unit frames)
            widthTarget = attachment.widthTarget,
            heightTarget = attachment.heightTarget,
            -- Absolute position (most reliable for restoring)
            absoluteX = attachment.absoluteX,
            absoluteY = attachment.absoluteY,
            -- Saved sizes (for size matching persistence)
            savedWidth = attachment.savedWidth,
            savedHeight = attachment.savedHeight,
        }
        
        if TUICD.PrintDebug then
            local sizeInfo = ""
            if attachment.savedWidth or attachment.savedHeight then
                sizeInfo = string.format(" size=%.0fx%.0f", attachment.savedWidth or 0, attachment.savedHeight or 0)
            end
            TUICD:PrintDebug(string.format("SaveAttachments: Saved %s -> %s (matchW=%s, matchH=%s)%s", 
                childId, attachment.parentId, 
                tostring(attachment.matchWidth), 
                tostring(attachment.matchHeight),
                sizeInfo))
        end
    end
    
    if TUICD.PrintDebug then
        local count = 0
        for _ in pairs(settings.attachments) do count = count + 1 end
        TUICD:PrintDebug("SaveAttachments: Saved " .. count .. " attachments to settings")
    end
end

function SnapLocking:LoadAttachments()
    if TUICD.PrintDebug then
        TUICD:PrintDebug("LoadAttachments: Starting...")
    end
    
    if not TUICD.Layout then 
        if TUICD.PrintDebug then
            TUICD:PrintDebug("LoadAttachments: Layout not available")
        end
        return 
    end
    
    local settings = TUICD.Layout:GetSettings()
    if not settings then
        if TUICD.PrintDebug then
            TUICD:PrintDebug("LoadAttachments: settings table is nil")
        end
        return
    end
    
    if not settings.attachments then
        if TUICD.PrintDebug then
            TUICD:PrintDebug("LoadAttachments: no attachments table in settings")
        end
        -- Check raw DB directly
        if TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.settings and TweaksUI_Cooldowns_CharDB.settings.layout and TweaksUI_Cooldowns_CharDB.settings.layout.attachments then
            local rawCount = 0
            for _ in pairs(TweaksUI_Cooldowns_CharDB.settings.layout.attachments) do rawCount = rawCount + 1 end
            if rawCount > 0 then
                TUICD:PrintDebug("LoadAttachments: BUT raw DB has " .. rawCount .. " attachments!")
                TUICD:PrintDebug("LoadAttachments: settings.attachments is different from raw DB!")
            end
        end
        return
    end
    
    -- Rebuild attachments from saved data
    attachments = {}
    for childId, savedData in pairs(settings.attachments) do
        attachments[childId] = {
            childId = childId,
            parentId = savedData.parentId,
            point = savedData.point or "TOPLEFT",
            relPoint = savedData.relPoint or "BOTTOMLEFT",
            offsetX = savedData.offsetX or 0,
            offsetY = savedData.offsetY or 0,
            matchWidth = savedData.matchWidth or false,
            matchHeight = savedData.matchHeight or false,
            widthOffset = savedData.widthOffset or 0,
            heightOffset = savedData.heightOffset or 0,
            widthMode = savedData.widthMode or SnapLocking.SIZE_MODE.STRETCH,
            heightMode = savedData.heightMode or SnapLocking.SIZE_MODE.STRETCH,
            -- Target component (healthBar vs frame for unit frames)
            widthTarget = savedData.widthTarget,
            heightTarget = savedData.heightTarget,
            -- Absolute position
            absoluteX = savedData.absoluteX,
            absoluteY = savedData.absoluteY,
            -- Saved sizes
            savedWidth = savedData.savedWidth,
            savedHeight = savedData.savedHeight,
        }
        
        if TUICD.PrintDebug then
            local sizeInfo = ""
            if savedData.savedWidth or savedData.savedHeight then
                sizeInfo = string.format(" size=%.0fx%.0f", savedData.savedWidth or 0, savedData.savedHeight or 0)
            end
            TUICD:PrintDebug(string.format("LoadAttachments: Loaded %s -> %s (matchW=%s, matchH=%s)%s", 
                childId, savedData.parentId, 
                tostring(savedData.matchWidth), 
                tostring(savedData.matchHeight),
                sizeInfo))
        end
    end
    
    if TUICD.PrintDebug then
        local count = 0
        for _ in pairs(attachments) do count = count + 1 end
        TUICD:PrintDebug("LoadAttachments: Loaded " .. count .. " attachments total")
    end
end

--[[
    Validate all attachments and remove orphaned ones
    Called after all TUIFrames are registered
    
    @return number - Count of removed orphaned attachments
]]
function SnapLocking:ValidateAttachments()
    local orphaned = {}
    
    for childId, attachment in pairs(attachments) do
        local childTUI = self:GetTUIFrame(childId)
        local parentTUI = self:GetTUIFrame(attachment.parentId)
        
        -- Check if either frame is missing
        if not childTUI then
            table.insert(orphaned, { id = childId, reason = "child missing" })
        elseif not parentTUI then
            table.insert(orphaned, { id = childId, reason = "parent missing: " .. attachment.parentId })
        end
    end
    
    -- Remove orphaned attachments
    for _, orphan in ipairs(orphaned) do
        if TUICD.PrintDebug then
            TUICD:PrintDebug("SnapLocking: Removing orphaned attachment: " .. orphan.id .. " (" .. orphan.reason .. ")")
        end
        attachments[orphan.id] = nil
    end
    
    -- Save cleaned up attachments if any were removed
    if #orphaned > 0 then
        self:SaveAttachments()
        TUICD:Print("|cffff8800SnapLocking:|r Removed " .. #orphaned .. " broken attachment(s)")
    end
    
    return #orphaned
end

function SnapLocking:ApplyAllAttachments()
    if TUICD.PrintDebug then
        TUICD:PrintDebug("SnapLocking: ApplyAllAttachments starting...")
    end
    
    -- DON'T validate here - frames may not be registered yet
    -- Just try to apply each attachment, skipping any that can't be applied yet
    
    local applied = 0
    local skipped = 0
    for childId, att in pairs(attachments) do
        local childTUI = self:GetTUIFrame(childId)
        local parentTUI = self:GetTUIFrame(att.parentId)
        
        if childTUI and parentTUI then
            if TUICD.PrintDebug then
                TUICD:PrintDebug(string.format("  Applying: %s -> %s (matchW=%s, matchH=%s)",
                    childId, att.parentId,
                    tostring(att.matchWidth),
                    tostring(att.matchHeight)))
            end
            self:ApplyAttachment(childId)
            applied = applied + 1
        else
            skipped = skipped + 1
            if TUICD.PrintDebug then
                TUICD:PrintDebug(string.format("  Skipped: %s (frames not ready yet)", childId))
            end
        end
    end
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("SnapLocking: ApplyAllAttachments done - applied " .. applied .. ", skipped " .. skipped)
    end
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================

function SnapLocking:RegisterCallback(event, callback)
    if not callbacks[event] then
        callbacks[event] = {}
    end
    table.insert(callbacks[event], callback)
end

function SnapLocking:FireCallback(event, ...)
    if callbacks[event] then
        for _, callback in ipairs(callbacks[event]) do
            callback(...)
        end
    end
end

-- ============================================================================
-- UTILITY
-- ============================================================================

-- Get all attachments (for debugging/UI)
function SnapLocking:GetAllAttachments()
    return attachments
end

-- Get parent display name for UI
function SnapLocking:GetParentDisplayName(childId)
    local attachment = attachments[childId]
    if not attachment then return nil end
    
    local parentTUI = self:GetTUIFrame(attachment.parentId)
    if parentTUI then
        return parentTUI.name or attachment.parentId
    end
    
    return attachment.parentId
end

-- ============================================================================
-- DEBUG
-- ============================================================================

function SnapLocking:DebugDump()
    print("|cff00ff00TweaksUI SnapLocking:|r Attachments:")
    
    local count = 0
    for childId, attachment in pairs(attachments) do
        local parentName = self:GetParentDisplayName(childId) or attachment.parentId
        local sizeInfo = ""
        if attachment.matchWidth or attachment.matchHeight then
            sizeInfo = string.format(" [size: W=%s H=%s]",
                attachment.matchWidth and "match" or "own",
                attachment.matchHeight and "match" or "own"
            )
        end
        
        -- Check if frames exist
        local childTUI = self:GetTUIFrame(childId)
        local parentTUI = self:GetTUIFrame(attachment.parentId)
        local childStatus = childTUI and "|cff00ff00OK|r" or "|cffff0000MISSING|r"
        local parentStatus = parentTUI and "|cff00ff00OK|r" or "|cffff0000MISSING|r"
        
        local extraInfo = ""
        if attachment.absoluteX and attachment.absoluteY then
            extraInfo = extraInfo .. string.format(" |cff888888pos=%.0f,%.0f|r", attachment.absoluteX, attachment.absoluteY)
        end
        if attachment.savedWidth or attachment.savedHeight then
            extraInfo = extraInfo .. string.format(" |cff88ff88size=%.0fx%.0f|r", attachment.savedWidth or 0, attachment.savedHeight or 0)
        end
        
        print(string.format("  %s [%s] -> %s [%s] (offset %.0f,%.0f)%s%s",
            childId, childStatus,
            parentName, parentStatus,
            attachment.offsetX,
            attachment.offsetY,
            sizeInfo,
            extraInfo
        ))
        count = count + 1
    end
    
    if count == 0 then
        print("  (no attachments)")
    end
    
    print(string.format("Total: %d attachments", count))
    
    -- Show chain structure
    print("")
    print("|cff00ff00Chain Structure:|r")
    
    -- Find all root frames (frames that have children but no parent)
    local roots = {}
    local hasChildren = {}
    
    for childId, attachment in pairs(attachments) do
        hasChildren[attachment.parentId] = true
    end
    
    for parentId in pairs(hasChildren) do
        if not attachments[parentId] then
            -- This is a root (has children but no parent)
            table.insert(roots, parentId)
        end
    end
    
    -- Also check for standalone attached frames (child with no children)
    for childId in pairs(attachments) do
        local isRoot = true
        for _, att in pairs(attachments) do
            if att.parentId == childId then
                isRoot = false
                break
            end
        end
    end
    
    if #roots == 0 then
        print("  (no chain roots found)")
    else
        for _, rootId in ipairs(roots) do
            local rootTUI = self:GetTUIFrame(rootId)
            local rootName = rootTUI and rootTUI.name or rootId
            local rootStatus = rootTUI and "" or " |cffff0000[MISSING]|r"
            print(string.format("  ROOT: %s%s", rootName, rootStatus))
            
            -- Print descendants
            local function printDescendants(parentId, indent)
                local children = self:GetChildren(parentId)
                for _, childId in ipairs(children) do
                    local childTUI = self:GetTUIFrame(childId)
                    local childName = childTUI and childTUI.name or childId
                    local childStatus = childTUI and "" or " |cffff0000[MISSING]|r"
                    local att = attachments[childId]
                    local sizeInfo = ""
                    if att.matchWidth or att.matchHeight then
                        sizeInfo = string.format(" |cff00ff00[matchW=%s matchH=%s]|r",
                            att.matchWidth and "YES" or "no",
                            att.matchHeight and "YES" or "no")
                    end
                    print(string.format("%s└─ %s%s (offset %.0f,%.0f)%s", 
                        indent, childName, childStatus, att.offsetX, att.offsetY, sizeInfo))
                    printDescendants(childId, indent .. "   ")
                end
            end
            
            printDescendants(rootId, "  ")
        end
    end
    
    if pendingSnap then
        print("")
        print("|cffff8800Pending snap:|r " .. pendingSnap.childId .. " near " .. pendingSnap.parentId)
    end
end

SLASH_TUISNAP1 = "/tuisnap"
SlashCmdList["TUISNAP"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()
    
    if cmd == "debug" or cmd == "" then
        SnapLocking:DebugDump()
    elseif cmd == "clear" then
        attachments = {}
        SnapLocking:SaveAttachments()
        print("|cff00ff00TweaksUI:|r Cleared all attachments")
    elseif cmd == "apply" then
        SnapLocking:ApplyAllAttachments()
        print("|cff00ff00TweaksUI:|r Applied all attachments")
    elseif cmd == "validate" then
        local removed = SnapLocking:ValidateAttachments()
        print("|cff00ff00TweaksUI:|r Validated attachments, removed " .. removed .. " orphaned")
    elseif cmd == "saved" then
        -- Show what's actually in the saved settings
        print("|cff00ff00TweaksUI:|r Saved attachment data:")
        if TUICD.Layout then
            local settings = TUICD.Layout:GetSettings()
            if settings and settings.attachments then
                local count = 0
                for childId, data in pairs(settings.attachments) do
                    count = count + 1
                    print(string.format("  %s -> %s [matchW=%s matchH=%s]", 
                        childId, data.parentId,
                        tostring(data.matchWidth),
                        tostring(data.matchHeight)))
                end
                if count == 0 then
                    print("  (attachments table exists but is empty)")
                end
            else
                print("  (settings.attachments is nil)")
            end
        else
            print("  (Layout not available)")
        end
    elseif cmd == "group" and arg ~= "" then
        -- Test GetConnectedGroup for a specific element
        print("|cff00ff00TweaksUI:|r Testing GetConnectedGroup for: " .. arg)
        local groupIds = SnapLocking:GetConnectedGroup(arg)
        print("  Group members (" .. #groupIds .. "):")
        for _, frameId in ipairs(groupIds) do
            local tui = SnapLocking:GetTUIFrame(frameId)
            local name = tui and tui.name or frameId
            local status = tui and "|cff00ff00OK|r" or "|cffff0000MISSING|r"
            local isRoot = not attachments[frameId]
            local rootLabel = isRoot and " (ROOT)" or ""
            print(string.format("    %s [%s]%s", name, status, rootLabel))
        end
    elseif cmd == "list" then
        -- List all TUIFrames
        print("|cff00ff00TweaksUI:|r Registered TUIFrames:")
        local frames = TUICD.TUIFrame.GetAll()
        local count = 0
        for id, tuiFrame in pairs(frames) do
            print(string.format("  %s (%s)", tuiFrame.name or id, id))
            count = count + 1
        end
        print(string.format("Total: %d frames", count))
    elseif cmd == "load" then
        -- Force reload attachments from saved settings
        print("|cff00ff00TweaksUI:|r Force loading attachments from saved settings...")
        SnapLocking:LoadAttachments()
        local count = 0
        for childId, att in pairs(attachments) do
            count = count + 1
            print(string.format("  Loaded: %s -> %s [matchW=%s matchH=%s]",
                childId, att.parentId,
                tostring(att.matchWidth),
                tostring(att.matchHeight)))
        end
        print(string.format("Total: %d attachments loaded", count))
    elseif cmd == "rawdb" then
        -- Check raw saved variables (what WoW has on disk)
        print("|cff00ff00TweaksUI:|r Raw saved variable check:")
        if TweaksUI_Cooldowns_CharDB then
            print("  TweaksUI_Cooldowns_CharDB exists: YES")
            if TweaksUI_Cooldowns_CharDB.settings then
                print("  TweaksUI_Cooldowns_CharDB.settings exists: YES")
                if TweaksUI_Cooldowns_CharDB.settings.layout then
                    print("  TweaksUI_Cooldowns_CharDB.settings.layout exists: YES")
                    if TweaksUI_Cooldowns_CharDB.settings.layout.attachments then
                        print("  TweaksUI_Cooldowns_CharDB.settings.layout.attachments exists: YES")
                        local count = 0
                        for childId, data in pairs(TweaksUI_Cooldowns_CharDB.settings.layout.attachments) do
                            count = count + 1
                            print(string.format("    %s -> %s [matchW=%s matchH=%s]",
                                childId, data.parentId,
                                tostring(data.matchWidth),
                                tostring(data.matchHeight)))
                        end
                        print(string.format("  Total: %d attachments in raw DB", count))
                    else
                        print("  TweaksUI_Cooldowns_CharDB.settings.layout.attachments: NIL")
                    end
                else
                    print("  TweaksUI_Cooldowns_CharDB.settings.layout: NIL")
                end
            else
                print("  TweaksUI_Cooldowns_CharDB.settings: NIL")
            end
        else
            print("  TweaksUI_Cooldowns_CharDB: NIL")
        end
    else
        print("|cff00ff00TweaksUI SnapLocking:|r")
        print("  /tuisnap - Show all attachments and chain structure")
        print("  /tuisnap clear - Clear all attachments")
        print("  /tuisnap apply - Re-apply all attachments")
        print("  /tuisnap validate - Check and remove broken attachments")
        print("  /tuisnap saved - Show Layout module's attachment data")
        print("  /tuisnap rawdb - Show raw WoW saved variable data")
        print("  /tuisnap load - Force reload attachments from settings")
        print("  /tuisnap list - List all registered TUIFrames")
        print("  /tuisnap group <id> - Test group detection for element ID")
    end
end
