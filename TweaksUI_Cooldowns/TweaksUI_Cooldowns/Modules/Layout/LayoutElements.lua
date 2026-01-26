-- ============================================================================
-- TUICD: LayoutElements
-- Keyboard controls and additional element interaction for Layout Mode
-- ============================================================================

local ADDON_NAME, TUICD = ...

local LayoutElements = {}
TUICD.LayoutElements = LayoutElements

local Layout  -- Set after Layout module loads

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local NUDGE_AMOUNT = 1  -- Pixels per arrow key press
local NUDGE_AMOUNT_SHIFT = 10  -- Pixels when holding shift

-- ============================================================================
-- STATE
-- ============================================================================

local keyboardFrame = nil
local isKeyboardEnabled = false
local initializePending = false  -- Track if we need to init after combat

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function LayoutElements:Initialize()
    -- COMBAT SAFETY: Don't initialize during combat lockdown
    if InCombatLockdown() then
        if not initializePending then
            initializePending = true
            -- Queue initialization for after combat
            local combatWatcher = CreateFrame("Frame")
            combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
            combatWatcher:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                initializePending = false
                LayoutElements:Initialize()
            end)
        end
        return
    end
    
    Layout = TUICD.Layout
    
    -- Create invisible frame for keyboard input
    keyboardFrame = CreateFrame("Frame", "TweaksUI_LayoutKeyboard", UIParent)
    keyboardFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    keyboardFrame:SetFrameLevel(500)
    keyboardFrame:SetSize(1, 1)
    keyboardFrame:SetPoint("CENTER")
    keyboardFrame:EnableMouse(false)  -- Never block mouse
    keyboardFrame:EnableKeyboard(false)
    keyboardFrame:SetPropagateKeyboardInput(true)
    
    keyboardFrame:SetScript("OnKeyDown", function(self, key)
        LayoutElements:OnKeyDown(key)
    end)
    
    -- Register for layout mode callbacks
    Layout:RegisterCallback("OnLayoutModeEnter", function()
        LayoutElements:EnableKeyboard()
    end)
    
    Layout:RegisterCallback("OnLayoutModeExit", function()
        LayoutElements:DisableKeyboard()
    end)
end

-- ============================================================================
-- KEYBOARD HANDLING
-- ============================================================================

function LayoutElements:EnableKeyboard()
    -- COMBAT SAFETY: Can't modify keyboard input during combat
    if InCombatLockdown() then
        return
    end
    
    if not keyboardFrame then
        self:Initialize()
        -- If Initialize was deferred due to combat, bail out
        if not keyboardFrame then return end
    end
    
    keyboardFrame:EnableKeyboard(true)
    keyboardFrame:SetPropagateKeyboardInput(true)
    isKeyboardEnabled = true
end

function LayoutElements:DisableKeyboard()
    -- COMBAT SAFETY: Can't modify keyboard input during combat
    if InCombatLockdown() then
        return
    end
    
    if keyboardFrame then
        keyboardFrame:EnableKeyboard(false)
    end
    isKeyboardEnabled = false
end

function LayoutElements:OnKeyDown(key)
    if not Layout:IsActive() then return end
    
    local selectedId, selectedElement = Layout:GetSelectedElement()
    
    -- Escape - deselect or exit layout mode
    if key == "ESCAPE" then
        if selectedId then
            Layout:ClearSelection()
        else
            Layout:Exit()
        end
        return
    end
    
    -- Arrow keys - nudge selected element
    if selectedId and selectedElement then
        local nudgeAmount = IsShiftKeyDown() and NUDGE_AMOUNT_SHIFT or NUDGE_AMOUNT
        local nudged = false
        
        if key == "UP" then
            self:NudgeElement(selectedId, 0, nudgeAmount)
            nudged = true
        elseif key == "DOWN" then
            self:NudgeElement(selectedId, 0, -nudgeAmount)
            nudged = true
        elseif key == "LEFT" then
            self:NudgeElement(selectedId, -nudgeAmount, 0)
            nudged = true
        elseif key == "RIGHT" then
            self:NudgeElement(selectedId, nudgeAmount, 0)
            nudged = true
        end
        
        if nudged then
            -- Save after nudge
            Layout:SaveElementPosition(selectedId)
            return
        end
    end
    
    -- R - reset selected element position
    if key == "R" and selectedId then
        Layout:ResetElementPosition(selectedId)
        return
    end
    
    -- G - toggle grid
    if key == "G" then
        local settings = Layout:GetGridSettings()
        Layout:SetGridEnabled(not settings.enabled)
        return
    end
    
    -- S - toggle snapping
    if key == "S" then
        local settings = Layout:GetSnappingSettings()
        Layout:SetSnappingEnabled(not settings.enabled)
        local status = settings.enabled and "disabled" or "enabled"  -- Inverted because we just toggled
        print("|cff00ff00TweaksUI:|r Snapping " .. status)
        return
    end
end

-- ============================================================================
-- NUDGING
-- ============================================================================

function LayoutElements:NudgeElement(id, deltaX, deltaY)
    local element = Layout:GetElement(id)
    if not element or not element.tuiFrame then return end
    
    local frame = element.tuiFrame.frame
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    
    if not left or not bottom then return end
    
    local SnapLocking = TUICD.SnapLocking
    
    -- Check if this frame is a CHILD (attached to something)
    local attachment = SnapLocking and SnapLocking:GetAttachment(id)
    if attachment then
        -- This is a locked child - adjust its offset relative to parent
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + deltaX, bottom + deltaY)
        
        -- Update the offset in the attachment
        local parentTUI = SnapLocking:GetTUIFrame(attachment.parentId)
        if parentTUI then
            local parentFrame = parentTUI.frame
            local parentLeft, parentBottom = parentFrame:GetLeft(), parentFrame:GetBottom()
            if parentLeft and parentBottom then
                attachment.offsetX = (left + deltaX) - parentLeft
                attachment.offsetY = (bottom + deltaY) - parentBottom
                SnapLocking:SaveAttachments()
            end
        end
        
        -- Update overlay
        if TUICD.LayoutUI then
            TUICD.LayoutUI:UpdateOverlayPosition(element)
            TUICD.LayoutUI:UpdateCoordDisplay()
            TUICD.LayoutUI:UpdateAttachmentDisplay()
        end
        return
    end
    
    -- Check if this frame is a mother/root with children attached
    if SnapLocking and SnapLocking:IsInLockedGroup(id) then
        -- This is a mother frame - move the entire group
        local groupIds = SnapLocking:GetConnectedGroup(id)
        
        -- Move all frames in the group by the same delta
        for _, frameId in ipairs(groupIds) do
            local tui = SnapLocking:GetTUIFrame(frameId)
            if tui then
                local f = tui.frame
                local fLeft, fBottom = f:GetLeft(), f:GetBottom()
                if fLeft and fBottom then
                    f:ClearAllPoints()
                    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", fLeft + deltaX, fBottom + deltaY)
                end
            end
            
            -- Update overlay
            local groupElement = Layout:GetElement(frameId)
            if groupElement and TUICD.LayoutUI then
                TUICD.LayoutUI:UpdateOverlayPosition(groupElement)
            end
            
            -- Save position
            Layout:SaveElementPosition(frameId)
        end
    else
        -- Not locked at all - move just this frame
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + deltaX, bottom + deltaY)
        
        -- Update overlay
        if TUICD.LayoutUI then
            TUICD.LayoutUI:UpdateOverlayPosition(element)
        end
        
        -- Save position
        Layout:SaveElementPosition(id)
    end
    
    -- Update coordinate panel
    if TUICD.LayoutUI then
        TUICD.LayoutUI:UpdateCoordDisplay()
    end
end

-- ============================================================================
-- ELEMENT UTILITIES
-- ============================================================================

function LayoutElements:CenterElement(id)
    local element = Layout:GetElement(id)
    if not element or not element.tuiFrame then return end
    
    element.tuiFrame:SetPosition("CENTER", UIParent, "CENTER", 0, 0)
    
    if TUICD.LayoutUI then
        TUICD.LayoutUI:UpdateOverlayPosition(element)
    end
    
    Layout:SaveElementPosition(id)
end

function LayoutElements:AlignElements(ids, alignType)
    -- alignType: "left", "right", "top", "bottom", "centerH", "centerV"
    if not ids or #ids < 2 then return end
    
    -- Get reference (first selected) element position
    local refElement = Layout:GetElement(ids[1])
    if not refElement or not refElement.tuiFrame then return end
    
    local refFrame = refElement.tuiFrame.frame
    local refLeft = refFrame:GetLeft()
    local refRight = refFrame:GetRight()
    local refTop = refFrame:GetTop()
    local refBottom = refFrame:GetBottom()
    local refCenterX = (refLeft + refRight) / 2
    local refCenterY = (refTop + refBottom) / 2
    
    for i = 2, #ids do
        local element = Layout:GetElement(ids[i])
        if element and element.tuiFrame then
            local frame = element.tuiFrame.frame
            local width = frame:GetWidth()
            local height = frame:GetHeight()
            local scale = frame:GetEffectiveScale()
            
            local newX, newY
            local point = "BOTTOMLEFT"
            
            if alignType == "left" then
                newX = refLeft
                newY = frame:GetBottom()
            elseif alignType == "right" then
                newX = refRight - width
                newY = frame:GetBottom()
            elseif alignType == "top" then
                newX = frame:GetLeft()
                newY = refTop - height
            elseif alignType == "bottom" then
                newX = frame:GetLeft()
                newY = refBottom
            elseif alignType == "centerH" then
                newX = refCenterX - width / 2
                newY = frame:GetBottom()
            elseif alignType == "centerV" then
                newX = frame:GetLeft()
                newY = refCenterY - height / 2
            end
            
            if newX and newY then
                frame:ClearAllPoints()
                frame:SetPoint(point, UIParent, "BOTTOMLEFT", newX / scale, newY / scale)
                
                element.tuiFrame.anchor = {
                    point = point,
                    relPoint = "BOTTOMLEFT",
                    x = newX / scale,
                    y = newY / scale,
                }
                
                if TUICD.LayoutUI then
                    TUICD.LayoutUI:UpdateOverlayPosition(element)
                end
                
                Layout:SaveElementPosition(ids[i])
            end
        end
    end
end

function LayoutElements:DistributeElements(ids, direction)
    -- direction: "horizontal" or "vertical"
    if not ids or #ids < 3 then return end
    
    -- Sort elements by position
    local elements = {}
    for _, id in ipairs(ids) do
        local element = Layout:GetElement(id)
        if element and element.tuiFrame then
            local frame = element.tuiFrame.frame
            table.insert(elements, {
                id = id,
                element = element,
                frame = frame,
                x = frame:GetLeft(),
                y = frame:GetBottom(),
                width = frame:GetWidth(),
                height = frame:GetHeight(),
            })
        end
    end
    
    if #elements < 3 then return end
    
    -- Sort by position
    if direction == "horizontal" then
        table.sort(elements, function(a, b) return a.x < b.x end)
    else
        table.sort(elements, function(a, b) return a.y < b.y end)
    end
    
    -- Calculate total span and spacing
    local first = elements[1]
    local last = elements[#elements]
    
    if direction == "horizontal" then
        local totalSpan = last.x + last.width - first.x
        local totalElementWidth = 0
        for _, e in ipairs(elements) do
            totalElementWidth = totalElementWidth + e.width
        end
        local spacing = (totalSpan - totalElementWidth) / (#elements - 1)
        
        local currentX = first.x + first.width + spacing
        for i = 2, #elements - 1 do
            local e = elements[i]
            local scale = e.frame:GetEffectiveScale()
            
            e.frame:ClearAllPoints()
            e.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", currentX / scale, e.y / scale)
            
            e.element.tuiFrame.anchor = {
                point = "BOTTOMLEFT",
                relPoint = "BOTTOMLEFT",
                x = currentX / scale,
                y = e.y / scale,
            }
            
            if TUICD.LayoutUI then
                TUICD.LayoutUI:UpdateOverlayPosition(e.element)
            end
            
            Layout:SaveElementPosition(e.id)
            
            currentX = currentX + e.width + spacing
        end
    else
        local totalSpan = last.y + last.height - first.y
        local totalElementHeight = 0
        for _, e in ipairs(elements) do
            totalElementHeight = totalElementHeight + e.height
        end
        local spacing = (totalSpan - totalElementHeight) / (#elements - 1)
        
        local currentY = first.y + first.height + spacing
        for i = 2, #elements - 1 do
            local e = elements[i]
            local scale = e.frame:GetEffectiveScale()
            
            e.frame:ClearAllPoints()
            e.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", e.x / scale, currentY / scale)
            
            e.element.tuiFrame.anchor = {
                point = "BOTTOMLEFT",
                relPoint = "BOTTOMLEFT",
                x = e.x / scale,
                y = currentY / scale,
            }
            
            if TUICD.LayoutUI then
                TUICD.LayoutUI:UpdateOverlayPosition(e.element)
            end
            
            Layout:SaveElementPosition(e.id)
            
            currentY = currentY + e.height + spacing
        end
    end
end

-- ============================================================================
-- COPY/PASTE POSITION
-- ============================================================================

local copiedPosition = nil

function LayoutElements:CopyPosition(id)
    local element = Layout:GetElement(id)
    if not element or not element.tuiFrame then return end
    
    copiedPosition = element.tuiFrame:GetSaveData()
    print("|cff00ff00TweaksUI:|r Position copied")
end

function LayoutElements:PastePosition(id)
    if not copiedPosition then
        print("|cff00ff00TweaksUI:|r No position copied")
        return
    end
    
    local element = Layout:GetElement(id)
    if not element or not element.tuiFrame then return end
    
    -- Apply position (without relative anchoring, just absolute)
    element.tuiFrame:SetPosition(
        copiedPosition.point,
        UIParent,
        copiedPosition.point,
        copiedPosition.x,
        copiedPosition.y
    )
    
    if copiedPosition.scale then
        element.tuiFrame:SetScale(copiedPosition.scale)
    end
    
    if TUICD.LayoutUI then
        TUICD.LayoutUI:UpdateOverlayPosition(element)
    end
    
    Layout:SaveElementPosition(id)
    print("|cff00ff00TweaksUI:|r Position pasted")
end

-- ============================================================================
-- DELAYED INITIALIZATION
-- ============================================================================

-- Initialize when Layout module is ready
C_Timer.After(0.1, function()
    if TUICD.Layout then
        LayoutElements:Initialize()
    end
end)
