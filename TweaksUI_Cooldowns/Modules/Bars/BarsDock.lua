-- ============================================================================
-- TUICD: Timer Bars - Dock Container
-- Groups bars into a single movable container with automatic layout.
-- Uses the same FIFO / center-out placement logic as icon docks.
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BarsDock = TUICD.BarsDock or {}
local BarsDock = TUICD.BarsDock

local BarsData = TUICD.BarsData
local BarsFrames -- forward ref, resolved on init

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DOCK_PADDING = 4          -- px padding inside dock border
local LAYOUT_THROTTLE = 0.02    -- seconds between layout passes
local DEFAULT_STRATA = "MEDIUM"
local DEFAULT_LEVEL = 10

-- ============================================================================
-- STATE
-- ============================================================================

local dockFrame = nil           -- The single dock container frame
local layoutQueued = false
local arrivalOrder = {}         -- barKeys in order they became visible (FIFO)
local arrivalCounter = 0        -- monotonic counter for stable ordering

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

function BarsDock:GetDock()
    return dockFrame
end

function BarsDock:CreateDock()
    if dockFrame then return dockFrame end

    BarsFrames = TUICD.BarsFrames  -- resolve forward ref

    dockFrame = CreateFrame("Frame", "TUICD_BarsDock", UIParent, "BackdropTemplate")
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
    dockFrame.label:SetText("|cff00ccffTimer Bars|r")
    dockFrame.label:Hide()

    -- Empty placeholder (layout mode)
    dockFrame.emptyText = dockFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dockFrame.emptyText:SetPoint("CENTER")
    dockFrame.emptyText:SetText("|cff555555(No Active Bars)|r")
    dockFrame.emptyText:Hide()

    -- Layout mode dragging (registered from BarsFrames layout mode)
    dockFrame:RegisterForDrag("LeftButton")
    dockFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dockFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        BarsDock:SavePosition()
    end)

    -- Load saved position
    self:LoadPosition()

    -- Start hidden; DoLayout will Show() when bars are visible
    dockFrame:Hide()

    return dockFrame
end

function BarsDock:DestroyDock()
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

function BarsDock:SavePosition()
    if not dockFrame then return end
    local point, _, relPoint, x, y = dockFrame:GetPoint()
    local db = BarsData:GetDB()
    db.dockPosition = { point = point, relPoint = relPoint, x = x, y = y }
end

function BarsDock:LoadPosition()
    if not dockFrame then return end
    local db = BarsData:GetDB()
    local pos = db.dockPosition
    dockFrame:ClearAllPoints()
    if pos then
        dockFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER",
            pos.x or 0, pos.y or 0)
    else
        dockFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    end
end

-- ============================================================================
-- ARRIVAL ORDER TRACKING
-- ============================================================================

-- Record a bar becoming visible (adds to arrival order if not already there)
function BarsDock:RecordArrival(barKey)
    for _, key in ipairs(arrivalOrder) do
        if key == barKey then return end  -- Already tracked
    end
    table.insert(arrivalOrder, barKey)
    arrivalCounter = arrivalCounter + 1
end

-- Remove a bar from arrival order (when it hides)
function BarsDock:RemoveArrival(barKey)
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

function BarsDock:QueueLayout()
    if layoutQueued then return end
    layoutQueued = true

    C_Timer.After(LAYOUT_THROTTLE, function()
        layoutQueued = false
        BarsDock:DoLayout()
    end)
end

-- Get visible bars in the correct order
local function GetVisibleBars()
    BarsFrames = BarsFrames or TUICD.BarsFrames
    if not BarsFrames then return {} end

    local allBars = BarsFrames:GetAllBars()
    local dockSettings = BarsData:GetDockSettings()
    local isLayout = TUICD.BarsDock._isLayoutMode

    if dockSettings.sortMode == "list" then
        -- Spell list order (alphabetical by display name)
        local sorted = {}
        for barKey, frame in pairs(allBars) do
            if frame:IsShown() or isLayout then
                local config = BarsData:GetSpellConfig(barKey)
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
                    BarsDock:RecordArrival(barKey)
                    table.insert(visible, frame)
                end
            end
        end
        return visible
    end
end

function BarsDock:DoLayout()
    if not dockFrame then return end

    local dockSettings = BarsData:GetDockSettings()
    local isLayout = self._isLayoutMode
    local visible = GetVisibleBars()
    local n = #visible

    local orientation = dockSettings.orientation or "VERTICAL"
    local spacing = dockSettings.spacing or 2
    local justify = dockSettings.justify or "CENTER"
    local isVert = (orientation == "VERTICAL")

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
    -- Build arrival-to-slot map
    local arrivalToSlot = {}  -- [arrivalIndex] = visualSlot
    if justify == "CENTER" then
        arrivalToSlot = BuildCenterOutSlots(n)
    elseif justify == "END" then
        for i = 1, n do arrivalToSlot[i] = n - i + 1 end
    else  -- START
        for i = 1, n do arrivalToSlot[i] = i end
    end

    -- Invert: slotToArrival[visualSlot] = arrivalIndex
    local slotToArrival = {}
    for arrival, slot in pairs(arrivalToSlot) do
        slotToArrival[slot] = arrival
    end

    -- Calculate cumulative offset for each visual slot (in order)
    local cursor = 0
    local slotOffsets = {}  -- [arrivalIndex] = pixel offset
    for slot = 1, n do
        local arrival = slotToArrival[slot]
        if arrival then
            local size = barSizes[arrival]
            local length = isVert and size.h or size.w
            slotOffsets[arrival] = cursor
            cursor = cursor + length + spacing
        end
    end

    -- Apply positions
    for i, frame in ipairs(visible) do
        frame:ClearAllPoints()
        frame:SetParent(dockFrame)
        local offset = slotOffsets[i] or 0
        local size = barSizes[i]

        if isVert then
            -- Vertical stack: top-to-bottom, center horizontally
            frame:SetPoint("TOP", dockFrame, "TOP", 0, -(DOCK_PADDING + offset))
        else
            -- Horizontal stack: left-to-right, center vertically
            frame:SetPoint("LEFT", dockFrame, "LEFT", DOCK_PADDING + offset, 0)
        end
    end

    dockFrame:Show()
end

-- ============================================================================
-- VISIBILITY HOOKS (called from BarsFrames)
-- ============================================================================

-- Called when a bar becomes visible
function BarsDock:OnBarShown(barKey)
    if not BarsData:IsDockEnabled() then return end
    self:RecordArrival(barKey)
    self:QueueLayout()
end

-- Called when a bar hides
function BarsDock:OnBarHidden(barKey)
    if not BarsData:IsDockEnabled() then return end
    self:RemoveArrival(barKey)
    self:QueueLayout()
end

-- Called when bar config changes (size, direction, etc.)
function BarsDock:OnBarConfigChanged(barKey)
    if not BarsData:IsDockEnabled() then return end
    self:QueueLayout()
end

-- ============================================================================
-- LAYOUT MODE
-- ============================================================================

function BarsDock:EnterLayoutMode()
    self._isLayoutMode = true
    if not dockFrame then self:CreateDock() end

    dockFrame:EnableMouse(true)
    dockFrame.label:Show()

    -- Show all enabled bars in dock for positioning
    self:DoLayout()
end

function BarsDock:ExitLayoutMode()
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

function BarsDock:Init()
    BarsFrames = TUICD.BarsFrames
    if BarsData:IsDockEnabled() then
        self:CreateDock()
    end
end

function BarsDock:Enable()
    if not dockFrame then self:CreateDock() end
    -- Re-parent all existing bars into dock
    BarsFrames = BarsFrames or TUICD.BarsFrames
    if BarsFrames then
        local allBars = BarsFrames:GetAllBars()
        for barKey, frame in pairs(allBars) do
            frame:SetParent(dockFrame)
            -- Unregister individual TUIFrames (dock owns positioning now)
            if frame._tuiFrame then
                local safeKey = BarsData.SanitizeKey(barKey)
                if TUICD.Layout and TUICD.Layout.UnregisterElement then
                    TUICD.Layout:UnregisterElement("bar_" .. safeKey)
                end
                frame._tuiFrame:Destroy()
                frame._tuiFrame = nil
            end
        end
    end
    self:DoLayout()
end

function BarsDock:Disable()
    -- Re-parent bars back to UIParent as standalone
    BarsFrames = BarsFrames or TUICD.BarsFrames
    if BarsFrames then
        local allBars = BarsFrames:GetAllBars()
        for barKey, frame in pairs(allBars) do
            frame:SetParent(UIParent)
            -- Recreate individual positioning
            local pos = BarsData:GetSpellPosition(barKey)
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
    wipe(arrivalOrder)
end

return BarsDock
