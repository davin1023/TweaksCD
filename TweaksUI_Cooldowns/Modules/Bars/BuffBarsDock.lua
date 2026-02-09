-- ============================================================================
-- TUICD: Buff Timer Bars - Dock Container
-- Groups bars into a single movable container with automatic layout.
-- Uses the same FIFO / center-out placement logic as icon docks.
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BuffBarsDock = TUICD.BuffBarsDock or {}
local BuffBarsDock = TUICD.BuffBarsDock

local BuffBarsData = TUICD.BuffBarsData
local BuffBarsFrames -- forward ref, resolved on init

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DOCK_PADDING = 4          -- px padding inside dock border
local LAYOUT_THROTTLE = 0.02    -- seconds between layout passes
local DEFAULT_STRATA = "MEDIUM"
local DEFAULT_LEVEL = 10

-- ============================================================================
-- HELPER: Get anchor point based on justify and orientation
-- ============================================================================

local function GetJustifyAnchor(justify, orientation)
    local isVert = (orientation == "VERTICAL" or orientation == "DOWN" or orientation == "UP")
    if justify == "CENTER" then
        return "CENTER"
    elseif justify == "END" then
        -- Bottom for vertical, Right for horizontal
        return isVert and "BOTTOM" or "RIGHT"
    else  -- START
        -- Top for vertical, Left for horizontal
        return isVert and "TOP" or "LEFT"
    end
end

-- ============================================================================
-- STATE
-- ============================================================================

local dockFrame = nil           -- The single dock container frame
local layoutQueued = false
local arrivalOrder = {}         -- barKeys in order they became visible (FIFO)
local arrivalCounter = 0        -- monotonic counter for stable ordering
local layoutWrapper = nil       -- TUIFrame-compatible wrapper for Layout system

-- ============================================================================
-- CENTER-OUT POSITIONING
-- Maps arrival index to visual position (first arrival = center slot)
-- ============================================================================

-- Build center-out slot map: arrival index -> visual slot
-- First arrival = center, then alternate left/right, guaranteed unique
local function BuildCenterOutSlots(totalCount)
    if totalCount <= 0 then return {} end
    if totalCount == 1 then return { [1] = 1 } end

    local slots = {}
    local center = math.ceil(totalCount / 2)
    slots[1] = center  -- First arrival goes center

    local left = center - 1
    local right = center + 1

    for i = 2, totalCount do
        if i % 2 == 0 then
            -- Even arrivals go left first
            if left >= 1 then
                slots[i] = left
                left = left - 1
            elseif right <= totalCount then
                slots[i] = right
                right = right + 1
            end
        else
            -- Odd arrivals go right first
            if right <= totalCount then
                slots[i] = right
                right = right + 1
            elseif left >= 1 then
                slots[i] = left
                left = left - 1
            end
        end
    end

    return slots
end

-- ============================================================================
-- DOCK FRAME
-- ============================================================================

function BuffBarsDock:GetDock()
    return dockFrame
end

function BuffBarsDock:CreateDock()
    if dockFrame then return dockFrame end

    BuffBarsFrames = TUICD.BuffBarsFrames  -- resolve forward ref

    dockFrame = CreateFrame("Frame", "TUICD_BuffBarsDock", UIParent, "BackdropTemplate")
    dockFrame:SetSize(200, 50)
    dockFrame:SetFrameStrata(DEFAULT_STRATA)
    dockFrame:SetFrameLevel(DEFAULT_LEVEL)
    dockFrame:SetClampedToScreen(true)
    dockFrame:SetMovable(true)
    dockFrame:EnableMouse(false)  -- Only in layout mode
    dockFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dockFrame:SetBackdropColor(0, 0, 0, 0)
    dockFrame:SetBackdropBorderColor(0, 0, 0, 0)

    -- Label (shown in layout mode)
    dockFrame.label = dockFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dockFrame.label:SetPoint("TOP", dockFrame, "BOTTOM", 0, -2)
    dockFrame.label:SetText("|cff00ccffBuff Bars|r")
    dockFrame.label:Hide()

    -- Empty placeholder (layout mode)
    dockFrame.emptyText = dockFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dockFrame.emptyText:SetPoint("CENTER")
    dockFrame.emptyText:SetText("|cff555555(No Active Buff Bars)|r")
    dockFrame.emptyText:Hide()

    -- Layout mode dragging (registered from BuffBarsFrames layout mode)
    dockFrame:RegisterForDrag("LeftButton")
    dockFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dockFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Re-anchor to the correct justify point after drag
        BuffBarsDock:ReanchorAfterDrag()
    end)

    -- Load saved position
    self:LoadPosition()

    -- Register with Layout system for snapping/nudging/locking
    self:RegisterWithLayout()

    -- Start hidden; DoLayout will Show() when bars are visible
    dockFrame:Hide()

    return dockFrame
end

-- ============================================================================
-- LAYOUT SYSTEM INTEGRATION
-- Creates a TUIFrame-compatible wrapper for snapping, nudging, locking
-- ============================================================================

function BuffBarsDock:CreateLayoutWrapper()
    if not dockFrame then return nil end
    if layoutWrapper then return layoutWrapper end
    
    local wrapperId = "BuffBarsDock"
    
    -- Create TUIFrame-compatible wrapper object
    layoutWrapper = {
        id = wrapperId,
        frame = dockFrame,
        name = "Buff Bars Dock",
        category = "Timer Bar",
        
        -- Default position
        defaultPosition = {
            point = "CENTER",
            x = 0,
            y = 50,
        },
        
        -- Get the anchor point (always CENTER for consistent positioning)
        GetAnchorPoint = function(self)
            return "CENTER"
        end,
        
        -- Position management
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            if InCombatLockdown() then return end
            
            x = x or 0
            y = y or 0
            
            dockFrame:ClearAllPoints()
            dockFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
            
            -- Save to dock settings
            BuffBarsDock:SavePosition()
        end,
        
        GetSaveData = function(self)
            local left, bottom, width, height = dockFrame:GetRect()
            if not left or not width then
                return { point = "CENTER", x = 0, y = 0 }
            end
            
            local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
            local dockCenterX = left + width / 2
            local dockCenterY = bottom + height / 2
            local x = dockCenterX - screenWidth / 2
            local y = dockCenterY - screenHeight / 2
            
            return { point = "CENTER", x = x, y = y }
        end,
        
        LoadSaveData = function(self, data)
            if not data then return end
            if InCombatLockdown() then return end
            
            local x = data.x or 0
            local y = data.y or 0
            
            dockFrame:ClearAllPoints()
            dockFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
            BuffBarsDock:SavePosition()
        end,
        
        -- Size management
        GetSize = function(self)
            return dockFrame:GetSize()
        end,
        
        GetWidth = function(self)
            return dockFrame:GetWidth()
        end,
        
        GetHeight = function(self)
            return dockFrame:GetHeight()
        end,
        
        -- Scale
        GetScale = function(self)
            return dockFrame:GetScale() or 1
        end,
        
        SetScale = function(self, scale)
            dockFrame:SetScale(scale)
        end,
        
        -- Visibility
        Show = function(self)
            dockFrame:Show()
        end,
        
        Hide = function(self)
            dockFrame:Hide()
        end,
        
        IsShown = function(self)
            return dockFrame:IsShown()
        end,
        
        -- FlyPaper snap detection - docks are snap TARGETS, not snappers
        GetSnapPoints = function(self, tolerance)
            return nil
        end,
        
        GetSnapTarget = function(self, tolerance)
            return nil
        end,
        
        -- Position changed callback
        onPositionChanged = function(self, point, relFrame, relPoint, x, y)
            BuffBarsDock:SavePosition()
        end,
        
        -- Size locking for SnapLocking compatibility
        sizeLocked = false,
        SetSizeLocked = function(self, locked)
            self.sizeLocked = locked
        end,
        IsSizeLocked = function(self)
            return self.sizeLocked
        end,
        
        -- Force set size (docks manage their own size)
        ForceSetSize = function(self, width, height)
            -- Docks manage their own size based on content
        end,
        
        SetWidth = function(self, width)
            -- Docks manage their own width
        end,
        SetHeight = function(self, height)
            -- Docks manage their own height
        end,
    }
    
    dockFrame.tuiFrame = layoutWrapper
    
    -- Register with FlyPaper for snap highlighting
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    if FlyPaper and FlyPaper.AddFrame then
        FlyPaper.AddFrame("TUICD", wrapperId, dockFrame)
    end
    
    return layoutWrapper
end

function BuffBarsDock:RegisterWithLayout()
    local Layout = TUICD.Layout
    if not Layout or not Layout.RegisterElement then return false end
    if not dockFrame then return false end
    
    -- Create wrapper
    local wrapper = self:CreateLayoutWrapper()
    if not wrapper then return false end
    
    local wrapperId = "BuffBarsDock"
    
    -- Register with Layout
    Layout:RegisterElement(wrapperId, {
        name = "Buff Bars Dock",
        category = Layout.CATEGORIES and Layout.CATEGORIES.BARS or "Timer Bar",
        tuiFrame = wrapper,
        defaultPosition = wrapper.defaultPosition,
        onPositionChanged = function(id, pos)
            if wrapper.onPositionChanged then
                wrapper:onPositionChanged(pos.point, pos.relFrame, pos.relPoint, pos.x, pos.y)
            end
        end,
    })
    
    return true
end

function BuffBarsDock:UnregisterFromLayout()
    local Layout = TUICD.Layout
    if not Layout or not Layout.UnregisterElement then return end
    
    Layout:UnregisterElement("BuffBarsDock")
    layoutWrapper = nil
end

function BuffBarsDock:DestroyDock()
    self:UnregisterFromLayout()
    if dockFrame then
        dockFrame:Hide()
        dockFrame:SetParent(nil)
        dockFrame = nil
    end
    wipe(arrivalOrder)
    arrivalCounter = 0
end

-- ============================================================================
-- POSITION PERSISTENCE
-- ============================================================================

function BuffBarsDock:SavePosition()
    if not dockFrame then return end
    local point, _, relPoint, x, y = dockFrame:GetPoint()
    local db = BuffBarsData:GetDB()
    db.dockPosition = { point = point, relPoint = relPoint, x = x, y = y }
end

-- Re-anchor dock after drag to maintain justify anchor point
function BuffBarsDock:ReanchorAfterDrag()
    if not dockFrame then return end
    
    local dockSettings = BuffBarsData:GetDockSettings()
    local direction = dockSettings.direction or "DOWN"
    local orientation = (direction == "DOWN" or direction == "UP") and "VERTICAL" or "HORIZONTAL"
    local justify = dockSettings.justify or "CENTER"
    local anchor = GetJustifyAnchor(justify, orientation)
    
    -- Get current frame position
    local left, bottom, width, height = dockFrame:GetRect()
    if not left then return end
    
    -- Calculate the screen position of the justify edge
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local edgeX, edgeY
    
    if anchor == "TOP" then
        edgeX = left + width / 2
        edgeY = bottom + height  -- Top edge
    elseif anchor == "BOTTOM" then
        edgeX = left + width / 2
        edgeY = bottom  -- Bottom edge
    elseif anchor == "LEFT" then
        edgeX = left  -- Left edge
        edgeY = bottom + height / 2
    elseif anchor == "RIGHT" then
        edgeX = left + width  -- Right edge
        edgeY = bottom + height / 2
    else  -- CENTER
        edgeX = left + width / 2
        edgeY = bottom + height / 2
    end
    
    -- Convert to offset from UIParent CENTER
    local offsetX = edgeX - screenWidth / 2
    local offsetY = edgeY - screenHeight / 2
    
    -- Re-anchor with the justify anchor point
    dockFrame:ClearAllPoints()
    dockFrame:SetPoint(anchor, UIParent, "CENTER", offsetX, offsetY)
    
    self:SavePosition()
end

function BuffBarsDock:LoadPosition()
    if not dockFrame then return end
    local db = BuffBarsData:GetDB()
    local pos = db.dockPosition
    local dockSettings = BuffBarsData:GetDockSettings()
    local direction = dockSettings.direction or "DOWN"
    local orientation = (direction == "DOWN" or direction == "UP") and "VERTICAL" or "HORIZONTAL"
    local currentAnchor = GetJustifyAnchor(dockSettings.justify or "CENTER", orientation)
    
    dockFrame:ClearAllPoints()
    if pos then
        local savedAnchor = pos.point
        -- If saved anchor matches current justify, use saved position directly
        if savedAnchor == currentAnchor then
            dockFrame:SetPoint(savedAnchor, UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
        else
            -- Anchor mismatch - use saved offset with current anchor
            -- This will shift the dock position, but it's better than using wrong anchor
            -- User should re-drag to correct position, which will save correct anchor
            dockFrame:SetPoint(currentAnchor, UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
        end
    else
        dockFrame:SetPoint(currentAnchor, UIParent, "CENTER", 0, 50)
    end
end

-- Re-anchor dock based on current justify (call when justify changes)
function BuffBarsDock:ReanchorForJustify()
    if not dockFrame then return end
    local dockSettings = BuffBarsData:GetDockSettings()
    local direction = dockSettings.direction or "DOWN"
    local orientation = (direction == "DOWN" or direction == "UP") and "VERTICAL" or "HORIZONTAL"
    local anchor = GetJustifyAnchor(dockSettings.justify or "CENTER", orientation)
    
    -- Get current visual center position
    local cx, cy = dockFrame:GetCenter()
    local w, h = dockFrame:GetSize()
    local scale = dockFrame:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    
    -- Calculate new offset based on anchor point
    local uiCenterX, uiCenterY = UIParent:GetCenter()
    local relX = (cx * scale / uiScale) - uiCenterX
    local relY = (cy * scale / uiScale) - uiCenterY
    
    -- Adjust offset for anchor position
    local offsetX, offsetY = relX, relY
    if anchor == "TOP" then
        offsetY = relY + h/2
    elseif anchor == "BOTTOM" then
        offsetY = relY - h/2
    elseif anchor == "LEFT" then
        offsetX = relX - w/2
    elseif anchor == "RIGHT" then
        offsetX = relX + w/2
    end
    
    dockFrame:ClearAllPoints()
    dockFrame:SetPoint(anchor, UIParent, "CENTER", offsetX, offsetY)
    self:SavePosition()
end

-- ============================================================================
-- ARRIVAL ORDER TRACKING
-- ============================================================================

-- Record a bar becoming visible (adds to arrival order if not already there)
function BuffBarsDock:RecordArrival(barKey)
    for _, key in ipairs(arrivalOrder) do
        if key == barKey then return end  -- Already tracked
    end
    table.insert(arrivalOrder, barKey)
    arrivalCounter = arrivalCounter + 1
end

-- Remove a bar from arrival order (when it hides)
function BuffBarsDock:RemoveArrival(barKey)
    for i, key in ipairs(arrivalOrder) do
        if key == barKey then
            table.remove(arrivalOrder, i)
            return
        end
    end
end

-- ============================================================================
-- LAYOUT
-- ============================================================================

function BuffBarsDock:QueueLayout()
    if layoutQueued then return end
    layoutQueued = true

    C_Timer.After(LAYOUT_THROTTLE, function()
        layoutQueued = false
        BuffBarsDock:DoLayout()
    end)
end

-- Get visible bars in the correct order
local function GetVisibleBars()
    BuffBarsFrames = BuffBarsFrames or TUICD.BuffBarsFrames
    if not BuffBarsFrames then return {} end

    local allBars = BuffBarsFrames:GetAllBarFrames()
    local dockSettings = BuffBarsData:GetDockSettings()
    local isLayout = TUICD.BuffBarsDock._isLayoutMode

    if dockSettings.sortMode == "list" then
        -- Spell list order (alphabetical by display name)
        local sorted = {}
        for barKey, frame in pairs(allBars) do
            if frame:IsShown() or isLayout then
                local config = BuffBarsData:GetSpellConfig(barKey)
                table.insert(sorted, {
                    barKey = barKey,
                    frame = frame,
                    name = config and config.name or "",
                })
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        local result = {}
        for _, entry in ipairs(sorted) do
            table.insert(result, entry.frame)
        end
        return result
    else
        -- Arrival order (FIFO)
        local visible = {}
        for _, barKey in ipairs(arrivalOrder) do
            local frame = allBars[barKey]
            if frame and (frame:IsShown() or isLayout) then
                table.insert(visible, frame)
            end
        end
        -- Also catch any bars not yet in arrival order (e.g. showWhenReady)
        for barKey, frame in pairs(allBars) do
            if frame:IsShown() or isLayout then
                local found = false
                for _, key in ipairs(arrivalOrder) do
                    if key == barKey then found = true; break end
                end
                if not found then
                    BuffBarsDock:RecordArrival(barKey)
                    table.insert(visible, frame)
                end
            end
        end
        return visible
    end
end

function BuffBarsDock:DoLayout()
    if not dockFrame then return end

    local dockSettings = BuffBarsData:GetDockSettings()
    local isLayout = self._isLayoutMode
    local visible = GetVisibleBars()
    local n = #visible

    local direction = dockSettings.direction or "DOWN"
    local spacing = dockSettings.spacing or 2
    local justify = dockSettings.justify or "CENTER"
    local isVert = (direction == "DOWN" or direction == "UP")

    -- Handle empty dock
    if n == 0 then
        if isLayout then
            dockFrame:SetSize(220, 50)
            dockFrame.emptyText:Show()
            dockFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            dockFrame:SetBackdropBorderColor(0.4, 0.8, 1.0, 0.8)
            dockFrame:Show()
        else
            dockFrame.emptyText:Hide()
            dockFrame:Hide()
        end
        return
    end

    dockFrame.emptyText:Hide()

    -- Calculate total dock size from bar dimensions
    local totalLength = 0   -- along stacking axis
    local maxThickness = 0  -- across stacking axis

    local barSizes = {}     -- cache each bar's contribution
    for i, frame in ipairs(visible) do
        local w, h = frame:GetWidth(), frame:GetHeight()
        barSizes[i] = { w = w, h = h }
        if isVert then
            totalLength = totalLength + h
            if w > maxThickness then maxThickness = w end
        else
            totalLength = totalLength + w
            if h > maxThickness then maxThickness = h end
        end
    end
    totalLength = totalLength + (n - 1) * spacing

    local dockW = isVert and (maxThickness + DOCK_PADDING * 2) or (totalLength + DOCK_PADDING * 2)
    local dockH = isVert and (totalLength + DOCK_PADDING * 2) or (maxThickness + DOCK_PADDING * 2)
    dockFrame:SetSize(dockW, dockH)

    -- Layout appearance
    if isLayout then
        dockFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
        dockFrame:SetBackdropBorderColor(0.4, 0.8, 1.0, 0.8)
    else
        dockFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.0)
        dockFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.0)
    end

    -- Position each bar inside the dock
    -- Justify determines WHERE bars anchor and grow FROM:
    --   START (Top/Left): First bar at top/left edge, grow down/right
    --   END (Bottom/Right): First bar at bottom/right edge, grow up/left  
    --   CENTER: Center-out placement
    
    -- Apply positions - anchor from the correct edge based on justify
    for i, frame in ipairs(visible) do
        frame:ClearAllPoints()
        frame:SetParent(dockFrame)
        local size = barSizes[i]
    end
    
    if justify == "CENTER" then
        -- Center-out: use slot mapping
        local arrivalToSlot = BuildCenterOutSlots(n)
        local slotToArrival = {}
        for arrival, slot in pairs(arrivalToSlot) do
            slotToArrival[slot] = arrival
        end
        
        -- Calculate cumulative offset for each visual slot
        local cursor = 0
        local slotOffsets = {}
        for slot = 1, n do
            local arrival = slotToArrival[slot]
            if arrival then
                local size = barSizes[arrival]
                local length = isVert and size.h or size.w
                slotOffsets[arrival] = cursor
                cursor = cursor + length + spacing
            end
        end
        
        -- Position from top/left
        for i, frame in ipairs(visible) do
            local offset = slotOffsets[i] or 0
            if isVert then
                frame:SetPoint("TOP", dockFrame, "TOP", 0, -(DOCK_PADDING + offset))
            else
                frame:SetPoint("LEFT", dockFrame, "LEFT", DOCK_PADDING + offset, 0)
            end
        end
        
    elseif justify == "END" then
        -- END (Bottom/Right): First bar at bottom/right, grow up/left
        local cursor = DOCK_PADDING
        for i, frame in ipairs(visible) do
            local size = barSizes[i]
            if isVert then
                frame:SetPoint("BOTTOM", dockFrame, "BOTTOM", 0, cursor)
                cursor = cursor + size.h + spacing
            else
                frame:SetPoint("RIGHT", dockFrame, "RIGHT", -cursor, 0)
                cursor = cursor + size.w + spacing
            end
        end
        
    else  -- START (Top/Left)
        -- START: First bar at top/left, grow down/right
        local cursor = DOCK_PADDING
        for i, frame in ipairs(visible) do
            local size = barSizes[i]
            if isVert then
                frame:SetPoint("TOP", dockFrame, "TOP", 0, -cursor)
                cursor = cursor + size.h + spacing
            else
                frame:SetPoint("LEFT", dockFrame, "LEFT", cursor, 0)
                cursor = cursor + size.w + spacing
            end
        end
    end

    -- Only show if visibility conditions are met
    if self:ShouldBeVisible() then
        dockFrame:Show()
    else
        dockFrame:Hide()
    end
end

-- ============================================================================
-- VISIBILITY HOOKS (called from BuffBarsFrames)
-- ============================================================================

-- Called when a bar becomes visible
function BuffBarsDock:OnBarShown(barKey)
    if not BuffBarsData:IsDockEnabled() then return end
    self:RecordArrival(barKey)
    self:QueueLayout()
end

-- Called when a bar hides
function BuffBarsDock:OnBarHidden(barKey)
    if not BuffBarsData:IsDockEnabled() then return end
    self:RemoveArrival(barKey)
    self:QueueLayout()
end

-- Called when bar config changes (size, direction, etc.)
function BuffBarsDock:OnBarConfigChanged(barKey)
    if not BuffBarsData:IsDockEnabled() then return end
    self:QueueLayout()
end

-- ============================================================================
-- LAYOUT MODE
-- ============================================================================

function BuffBarsDock:EnterLayoutMode()
    self._isLayoutMode = true
    if not dockFrame then self:CreateDock() end

    dockFrame:EnableMouse(true)
    dockFrame.label:Show()

    -- Show all enabled bars in dock for positioning
    self:DoLayout()
end

function BuffBarsDock:ExitLayoutMode()
    self._isLayoutMode = false
    if not dockFrame then return end

    dockFrame:EnableMouse(false)
    dockFrame.label:Hide()

    self:SavePosition()
    self:DoLayout()
end

-- ============================================================================
-- INIT / TEARDOWN
-- ============================================================================

function BuffBarsDock:Init()
    BuffBarsFrames = TUICD.BuffBarsFrames
    if BuffBarsData:IsDockEnabled() then
        self:CreateDock()
    end
end

function BuffBarsDock:Enable()
    if not dockFrame then self:CreateDock() end
    -- Re-parent all existing bars into dock
    BuffBarsFrames = BuffBarsFrames or TUICD.BuffBarsFrames
    if BuffBarsFrames then
        local allBars = BuffBarsFrames:GetAllBarFrames()
        for barKey, frame in pairs(allBars) do
            frame:SetParent(dockFrame)
            -- Unregister individual TUIFrames (dock owns positioning now)
            if frame._tuiFrame then
                local safeKey = BuffBarsData.SanitizeKey(barKey)
                if TUICD.Layout and TUICD.Layout.UnregisterElement then
                    TUICD.Layout:UnregisterElement("bar_" .. safeKey)
                end
                frame._tuiFrame:Destroy()
                frame._tuiFrame = nil
            end
        end
    end
    -- Register visibility events
    self:RegisterVisibilityEvents()
    self:DoLayout()
end

function BuffBarsDock:Disable()
    -- Re-parent bars back to UIParent as standalone
    BuffBarsFrames = BuffBarsFrames or TUICD.BuffBarsFrames
    if BuffBarsFrames then
        local allBars = BuffBarsFrames:GetAllBarFrames()
        for barKey, frame in pairs(allBars) do
            frame:SetParent(UIParent)
            -- Recreate individual positioning
            local pos = BuffBarsData:GetSpellPosition(barKey)
            frame:ClearAllPoints()
            if pos then
                frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER",
                    pos.x or 0, pos.y or 0)
            else
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    end
    if dockFrame then
        dockFrame:Hide()
    end
    -- Unregister visibility events
    self:UnregisterVisibilityEvents()
    wipe(arrivalOrder)
end

-- ============================================================================
-- VISIBILITY SYSTEM
-- ============================================================================

local visibilityEventFrame = nil

-- Get current player state for visibility checks
local function GetPlayerState()
    local state = {
        inCombat = InCombatLockdown() or UnitAffectingCombat("player"),
        inGroup = IsInGroup(),
        inRaid = IsInRaid(),
        inDungeon = false,
        inDelve = false,
        inArena = false,
        inBattleground = false,
        isSolo = not IsInGroup(),
        hasTarget = UnitExists("target"),
        isMounted = TUICD.UnitAPI and TUICD.UnitAPI:IsMountedOrTravelForm() or IsMounted(),
    }
    
    -- Check instance type
    local _, instanceType = IsInInstance()
    if instanceType == "party" then
        state.inDungeon = true
    elseif instanceType == "raid" then
        -- raids are covered by inRaid
    elseif instanceType == "arena" then
        state.inArena = true
    elseif instanceType == "pvp" then
        state.inBattleground = true
    elseif instanceType == "scenario" then
        -- Delves are scenario type - check for delve map
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local mapInfo = C_Map.GetMapInfo(mapID)
            if mapInfo and mapInfo.mapType == Enum.UIMapType.Delve then
                state.inDelve = true
            end
        end
    end
    
    return state
end

-- Check if dock should be visible based on visibility conditions
function BuffBarsDock:ShouldBeVisible()
    -- Force all visible mode bypasses all visibility conditions
    if TUICD.forceAllVisible then
        return true
    end
    
    -- Always show in Edit Mode / Layout Mode for positioning
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return true
    end
    if self._isLayoutMode then
        return true
    end

    -- Config preview: force dock visible while a bar is being previewed
    if BuffBarsFrames and BuffBarsFrames.GetPreviewBarKey and BuffBarsFrames:GetPreviewBarKey() then
        return true
    end
    
    local dockSettings = BuffBarsData:GetDockSettings()
    local enabled = dockSettings.visibilityEnabled
    if not enabled then
        return true  -- Visibility system disabled = always show
    end
    
    local state = GetPlayerState()
    
    -- OR logic: if ANY checked condition is true, show
    if state.inCombat and dockSettings.showInCombat then return true end
    if not state.inCombat and dockSettings.showOutOfCombat then return true end
    if state.isSolo and dockSettings.showSolo then return true end
    if state.inGroup and not state.inRaid and dockSettings.showInParty then return true end
    if state.inRaid and dockSettings.showInRaid then return true end
    if state.inDungeon and dockSettings.showInDungeon then return true end
    if state.inDelve and dockSettings.showInDelve then return true end
    if state.inArena and dockSettings.showInArena then return true end
    if state.inBattleground and dockSettings.showInBattleground then return true end
    if state.hasTarget and dockSettings.showHasTarget then return true end
    if not state.hasTarget and dockSettings.showNoTarget then return true end
    if state.isMounted and dockSettings.showMounted then return true end
    if not state.isMounted and dockSettings.showNotMounted then return true end
    
    -- No conditions matched
    return false
end

-- Update dock visibility based on current conditions
function BuffBarsDock:UpdateVisibility()
    if not dockFrame then return end
    
    local shouldShow = self:ShouldBeVisible()
    
    if shouldShow then
        -- Check if we have visible bars before showing
        local visible = GetVisibleBars()
        local hasPreview = BuffBarsFrames and BuffBarsFrames.GetPreviewBarKey and BuffBarsFrames:GetPreviewBarKey()
        if #visible > 0 or self._isLayoutMode or hasPreview then
            dockFrame:Show()
        end
    else
        dockFrame:Hide()
    end
end

-- Register for visibility-related events
function BuffBarsDock:RegisterVisibilityEvents()
    if not visibilityEventFrame then
        visibilityEventFrame = CreateFrame("Frame")
        visibilityEventFrame:SetScript("OnEvent", function(_, event, ...)
            -- Throttle updates slightly
            C_Timer.After(0.05, function()
                BuffBarsDock:UpdateVisibility()
            end)
        end)
    end
    
    visibilityEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    visibilityEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    visibilityEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    visibilityEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    visibilityEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    visibilityEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    
    -- Mount events
    if C_MountJournal then
        visibilityEventFrame:RegisterEvent("MOUNT_EQUIPMENT_APPLY_RESULT")
    end
    visibilityEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
end

-- Unregister visibility events
function BuffBarsDock:UnregisterVisibilityEvents()
    if visibilityEventFrame then
        visibilityEventFrame:UnregisterAllEvents()
    end
end

return BuffBarsDock
