-- ============================================================================
-- TUICD Cooldown Containers
-- Reparents Blizzard's cooldown viewers into our own container frames
-- This allows positioning via TUICD Layout Mode instead of Edit Mode
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- ============================================================================
-- MODULE SETUP
-- ============================================================================

local CooldownContainers = {}
TUICD.CooldownContainers = CooldownContainers

-- State
local initialized = false
local enabled = false

-- Our container frames
local containers = {}  -- [trackerKey] = containerFrame

-- Original viewer data for restoration
local originalViewerData = {}  -- [trackerKey] = { parent, points }

-- Layout integration
local layoutWrappers = {}

-- Blizzard viewer references
local BLIZZARD_VIEWERS = {
    essential = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    buffs = "BuffIconCooldownViewer",
}

-- Display names
local DISPLAY_NAMES = {
    essential = "Essential Cooldowns",
    utility = "Utility Cooldowns",
    buffs = "Buff Tracker",
}

local CUSTOM_TRACKER_KEY = "customTrackers"

-- ============================================================================
-- POSITION SAVE/RESTORE
-- ============================================================================

local function GetSavedPosition(trackerKey)
    if not TUICD.Database or not TUICD.Database.charDb then
        return nil
    end
    
    if not TUICD.Database.charDb.cooldownContainerPositions then
        return nil
    end
    
    return TUICD.Database.charDb.cooldownContainerPositions[trackerKey]
end

local function SavePosition(trackerKey, point, x, y)
    if not TUICD.Database or not TUICD.Database.charDb then
        return
    end
    
    if not TUICD.Database.charDb.cooldownContainerPositions then
        TUICD.Database.charDb.cooldownContainerPositions = {}
    end
    
    TUICD.Database.charDb.cooldownContainerPositions[trackerKey] = {
        point = point,
        x = x,
        y = y,
    }
end

-- ============================================================================
-- CONTAINER FRAME CREATION
-- ============================================================================

local function CreateContainer(trackerKey)
    if containers[trackerKey] then return containers[trackerKey] end
    
    local displayName = DISPLAY_NAMES[trackerKey] or trackerKey
    
    local container = CreateFrame("Frame", "TweaksUI_CDContainer_" .. trackerKey, UIParent)
    container:SetSize(200, 50)
    container:SetFrameStrata("LOW")
    container:SetFrameLevel(10)
    container:SetClampedToScreen(true)
    container:SetMovable(true)
    container:EnableMouse(false)
    
    -- Start hidden to prevent visible position jumps during load
    -- Will be revealed by TUIFrame.RevealAllFrames() after all positions set
    container:SetAlpha(0)
    
    -- Register with global reveal system
    if TUICD.TUIFrame and TUICD.TUIFrame.registry then
        -- Add to pending frames for batch reveal
        local TUIFrame = TUICD.TUIFrame
        if TUIFrame.RegisterPendingFrame then
            TUIFrame.RegisterPendingFrame(container)
        end
    end
    
    -- Default positions
    local defaultPositions = {
        essential = { point = "CENTER", x = 0, y = -100 },
        utility = { point = "CENTER", x = 0, y = -160 },
        buffs = { point = "CENTER", x = 0, y = -220 },
    }
    
    -- Try to load saved position first
    local saved = GetSavedPosition(trackerKey)
    local pos = saved or defaultPositions[trackerKey] or { point = "CENTER", x = 0, y = -100 }
    
    container:ClearAllPoints()
    container:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    
    container.trackerKey = trackerKey
    container.displayName = displayName
    containers[trackerKey] = container
    
    TUICD:PrintDebug("CooldownContainers: Created container for " .. trackerKey)
    return container
end

-- ============================================================================
-- UPDATE CONTAINER SIZE BASED ON ICON LAYOUT
-- ============================================================================

local function CalculateIconBounds(viewer)
    if not viewer or not viewer.GetChildren then return 0, 0, 0, 0 end
    
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    local hasIcons = false
    
    for _, child in ipairs({viewer:GetChildren()}) do
        -- Check if it's an icon (has Icon texture or Cooldown)
        if child and (child.Icon or child.icon or child.Cooldown or child.cooldown) then
            if child:IsShown() then
                local left = child:GetLeft()
                local right = child:GetRight()
                local top = child:GetTop()
                local bottom = child:GetBottom()
                
                if left and right and top and bottom then
                    -- Get position relative to viewer
                    local viewerLeft = viewer:GetLeft() or 0
                    local viewerTop = viewer:GetTop() or 0
                    
                    local relLeft = left - viewerLeft
                    local relRight = right - viewerLeft
                    local relTop = viewerTop - top
                    local relBottom = viewerTop - bottom
                    
                    minX = math.min(minX, relLeft)
                    maxX = math.max(maxX, relRight)
                    minY = math.min(minY, relTop)
                    maxY = math.max(maxY, relBottom)
                    hasIcons = true
                end
            end
        end
    end
    
    if hasIcons then
        local width = maxX - minX
        local height = maxY - minY
        return math.max(width, 1), math.max(height, 1), minX, minY
    end
    
    return 50, 50, 0, 0  -- Default minimum size
end

local function UpdateContainerSize(trackerKey)
    local container = containers[trackerKey]
    if not container then return end
    
    local viewerName = BLIZZARD_VIEWERS[trackerKey]
    local viewer = viewerName and _G[viewerName]
    if not viewer then return end
    
    local width, height, offsetX, offsetY = CalculateIconBounds(viewer)
    
    -- Only update if size changed significantly
    local currentWidth, currentHeight = container:GetSize()
    local sizeChanged = math.abs(currentWidth - width) > 2 or math.abs(currentHeight - height) > 2
    
    if sizeChanged then
        container:SetSize(width, height)
        
        -- Update Layout overlay if in Layout mode (so mover matches container size)
        local wrapperId = viewerName .. "_TUIWrapper"
        if TUICD.Layout and TUICD.LayoutUI then
            local element = TUICD.Layout:GetElement(wrapperId)
            if element then
                TUICD.LayoutUI:UpdateOverlayPosition(element)
            end
        end
    end
    
    -- Adjust viewer position within container to align icons with container bounds
    -- This compensates for Blizzard's viewer having icons offset from TOPLEFT
    if viewer._TUI_Controlled and (math.abs(offsetX) > 1 or math.abs(offsetY) > 1) then
        -- Temporarily allow SetPoint
        viewer._TUI_Controlled = false
        viewer:ClearAllPoints()
        viewer:SetPoint("TOPLEFT", container, "TOPLEFT", -offsetX, offsetY)
        viewer._TUI_Controlled = true
    end
end

-- ============================================================================
-- REPARENT VIEWER TO CONTAINER
-- ============================================================================

local function ReparentViewerToContainer(trackerKey)
    local container = containers[trackerKey]
    if not container then return false end
    
    local viewerName = BLIZZARD_VIEWERS[trackerKey]
    local viewer = viewerName and _G[viewerName]
    if not viewer then 
        return false 
    end
    
    -- Store original data for restoration (only once)
    if not originalViewerData[trackerKey] then
        originalViewerData[trackerKey] = {
            parent = viewer:GetParent(),
            points = {},
            originalSetPoint = viewer.SetPoint,
            originalClearAllPoints = viewer.ClearAllPoints,
        }
        for i = 1, viewer:GetNumPoints() do
            local point, relativeTo, relativePoint, xOfs, yOfs = viewer:GetPoint(i)
            table.insert(originalViewerData[trackerKey].points, {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                x = xOfs,
                y = yOfs
            })
        end
    end
    
    -- Reparent viewer to our container
    viewer:SetParent(container)
    viewer:ClearAllPoints()
    viewer:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    
    -- Mark viewer as controlled by us
    viewer._TUI_Container = container
    viewer._TUI_Controlled = true
    
    -- Hook SetPoint to prevent Edit Mode from moving the viewer
    local origSetPoint = originalViewerData[trackerKey].originalSetPoint
    viewer.SetPoint = function(self, ...)
        if self._TUI_Controlled then
            -- Ignore external SetPoint calls
            return
        end
        return origSetPoint(self, ...)
    end
    
    -- Hook ClearAllPoints similarly
    local origClearAllPoints = originalViewerData[trackerKey].originalClearAllPoints
    viewer.ClearAllPoints = function(self, ...)
        if self._TUI_Controlled then
            return
        end
        return origClearAllPoints(self, ...)
    end
    
    -- Setup drag detection on container
    if not container._TUI_DragCheckHooked then
        local dragCheckFrame = CreateFrame("Frame", nil, container)
        dragCheckFrame:SetScript("OnUpdate", function(self, elapsed)
            if IsShiftKeyDown() and IsControlKeyDown() and IsMouseButtonDown("LeftButton") then
                if not container.isMoving and MouseIsOver(container) then
                    container:StartMoving()
                    container.isMoving = true
                end
            elseif container.isMoving and not IsMouseButtonDown("LeftButton") then
                container:StopMovingOrSizing()
                container.isMoving = false
                -- Save position
                local point, _, _, x, y = container:GetPoint(1)
                SavePosition(trackerKey, point, x, y)
            end
        end)
        container._TUI_DragCheckHooked = true
    end
    
    -- Update container size after a short delay to let icons settle
    C_Timer.After(0.2, function()
        UpdateContainerSize(trackerKey)
    end)
    
    -- During initialization, keep viewer hidden (container already has alpha=0)
    -- After init, set viewer alpha to 1 (container visibility will control overall visibility)
    local TUIFrame = TUICD.TUIFrame
    if TUIFrame and TUIFrame.IsInitializationComplete and TUIFrame.IsInitializationComplete() then
        -- Init complete - show normally
        viewer:SetAlpha(1)
    else
        -- During init - keep hidden
        viewer:SetAlpha(0)
    end
    
    -- Fix potential duplicate layoutIndex values before showing (Blizzard CDM stale icon bug)
    pcall(function()
        local children = {viewer:GetChildren()}
        local seenIndices = {}
        local hasDuplicates = false
        
        -- Check for duplicates
        for _, child in ipairs(children) do
            if child.layoutIndex then
                if seenIndices[child.layoutIndex] then
                    hasDuplicates = true
                    break
                end
                seenIndices[child.layoutIndex] = true
            end
        end
        
        -- Fix duplicates by reassigning sequential indices
        if hasDuplicates then
            local iconsWithIndex = {}
            for _, child in ipairs(children) do
                if child.layoutIndex then
                    table.insert(iconsWithIndex, child)
                end
            end
            table.sort(iconsWithIndex, function(a, b)
                return (a.layoutIndex or 0) < (b.layoutIndex or 0)
            end)
            for i, icon in ipairs(iconsWithIndex) do
                icon.layoutIndex = i
            end
            TUICD:PrintDebug("CooldownContainers: Fixed duplicate layoutIndex for " .. trackerKey)
        end
    end)
    
    -- Wrap Show() in pcall - Blizzard's CooldownViewer has internal bugs with secret values
    -- that can trigger when their frame is shown (previousCooldownChargesCount comparison)
    pcall(function() viewer:Show() end)
    container:Show()
    
    TUICD:PrintDebug("CooldownContainers: Reparented " .. viewerName .. " to container (SetPoint hooked)")
    return true
end

-- ============================================================================
-- CUSTOM TRACKER DRAG
-- ============================================================================

local function SetupCustomTrackerDrag()
    local customFrame = _G["TweaksUI_CustomTrackerFrame"]
    if not customFrame then return end
    if customFrame._TUI_DragSetup then return end
    
    customFrame:SetMovable(true)
    customFrame:SetClampedToScreen(true)
    
    local dragFrame = CreateFrame("Frame", nil, customFrame)
    dragFrame:SetAllPoints(customFrame)
    dragFrame:SetFrameLevel(customFrame:GetFrameLevel() + 10)
    
    dragFrame:SetScript("OnUpdate", function(self, elapsed)
        if IsShiftKeyDown() and IsControlKeyDown() and IsMouseButtonDown("LeftButton") then
            if not customFrame.isMoving and MouseIsOver(customFrame) then
                customFrame:StartMoving()
                customFrame.isMoving = true
            end
        elseif customFrame.isMoving and not IsMouseButtonDown("LeftButton") then
            customFrame:StopMovingOrSizing()
            customFrame.isMoving = false
            
            local point, _, _, x, y = customFrame:GetPoint(1)
            if TUICD.Database then
                local settings = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
                if settings and settings.customTrackers then
                    settings.customTrackers.point = point
                    settings.customTrackers.x = x
                    settings.customTrackers.y = y
                    TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, settings)
                end
            end
        end
    end)
    
    customFrame._TUI_DragSetup = true
    TUICD:PrintDebug("CooldownContainers: Custom tracker drag enabled")
end

-- ============================================================================
-- LAYOUT INTEGRATION
-- ============================================================================

function CooldownContainers:RegisterWithLayout()
    local Layout = TUICD.Layout
    local TUIFrame = TUICD.TUIFrame
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    
    if not Layout then
        return
    end
    
    -- Register Blizzard viewer containers with Layout
    -- We create minimal TUIFrame-like objects without using TUIFrame:New
    -- to avoid creating duplicate frames
    for trackerKey, viewerName in pairs(BLIZZARD_VIEWERS) do
        local container = containers[trackerKey]
        if container then
            local wrapperId = viewerName .. "_TUIWrapper"
            
            -- Create a minimal tuiFrame-compatible object using our container directly
            local wrapper = {
                id = wrapperId,
                name = DISPLAY_NAMES[trackerKey] or viewerName,
                category = "Cooldowns",
                frame = container,
                defaultPosition = {
                    point = "CENTER",
                    x = 0,
                    y = -100 - (trackerKey == "utility" and 60 or (trackerKey == "buffs" and 120 or 0)),
                },
                contentFrames = {},
                
                onPositionChanged = function(self, point, relFrame, relPoint, x, y)
                    container:ClearAllPoints()
                    container:SetPoint(point, UIParent, point, x, y)
                    SavePosition(trackerKey, point, x, y)
                end,
                
                -- Minimal TUIFrame API
                GetPosition = function(self)
                    local point, relTo, relPoint, x, y = container:GetPoint(1)
                    return { point = point, relFrame = relTo, relPoint = relPoint, x = x, y = y }
                end,
                
                SetPosition = function(self, point, relFrame, relPoint, x, y)
                    container:ClearAllPoints()
                    container:SetPoint(point, relFrame or UIParent, relPoint or point, x or 0, y or 0)
                    if self.onPositionChanged then
                        self:onPositionChanged(point, relFrame, relPoint, x, y)
                    end
                end,
                
                LoadSaveData = function(self, data)
                    if not data then return end
                    local point = data.point or "BOTTOMLEFT"
                    self:SetPosition(point, UIParent, point, data.x, data.y)
                    if data.scale then
                        self:SetScale(data.scale)
                    end
                end,
                
                SetScale = function(self, scale)
                    if container and scale then
                        container:SetScale(scale)
                    end
                end,
                
                GetScale = function(self)
                    return container:GetScale() or 1
                end,
                
                IsShown = function(self)
                    return container and container:IsShown()
                end,
                
                GetSnapTarget = function(self, tolerance)
                    if not FlyPaper then return nil end
                    tolerance = tolerance or 15
                    local point, relFrame, relPoint, x, y = FlyPaper.GetBestAnchorForGroup(
                        container,
                        "TUICD",
                        tolerance
                    )
                    if point and relFrame then
                        return relFrame, point, relPoint, x, y
                    end
                    return nil
                end,
                
                GetSaveData = function(self)
                    local left = container:GetLeft()
                    local bottom = container:GetBottom()
                    if not left or not bottom then
                        local point, _, _, x, y = container:GetPoint(1)
                        return {
                            point = point or "CENTER",
                            x = x or 0,
                            y = y or 0,
                            scale = self:GetScale(),
                        }
                    end
                    return {
                        point = "BOTTOMLEFT",
                        x = left,
                        y = bottom,
                        scale = self:GetScale(),
                    }
                end,
                
                -- Size locking (used by SnapLocking)
                sizeLocked = false,
                SetSizeLocked = function(self, locked)
                    self.sizeLocked = locked
                end,
                IsSizeLocked = function(self)
                    return self.sizeLocked
                end,
                
                -- Size methods (used by SnapLocking for size matching)
                GetSize = function(self)
                    return container:GetSize()
                end,
                ForceSetSize = function(self, width, height)
                    container:SetSize(width, height)
                end,
            }
            
            container.tuiFrame = wrapper
            layoutWrappers[trackerKey] = wrapper
            
            -- Register with FlyPaper using container directly
            if FlyPaper then
                FlyPaper.AddFrame("TUICD", wrapperId, container)
            end
            
            -- Register with Layout
            Layout:RegisterElement(wrapperId, {
                name = DISPLAY_NAMES[trackerKey] or viewerName,
                category = "Cooldowns",
                tuiFrame = wrapper,
                defaultPosition = wrapper.defaultPosition,
            })
            
            TUICD:PrintDebug("CooldownContainers: Registered " .. viewerName .. " container with Layout")
        end
    end
    
    -- Register custom tracker frame with Layout (same approach)
    local customFrame = _G["TweaksUI_CustomTrackerFrame"]
    if customFrame then
        local wrapperId = "CustomTracker_TUIWrapper"
        
        local wrapper = {
            id = wrapperId,
            name = "Custom Cooldown Tracker",
            category = "Cooldowns",
            frame = customFrame,
            defaultPosition = {
                point = "CENTER",
                x = 0,
                y = -200,
            },
            contentFrames = {},
            
            onPositionChanged = function(self, point, relFrame, relPoint, x, y)
                customFrame:ClearAllPoints()
                customFrame:SetPoint(point, UIParent, point, x, y)
                
                if TUICD.Database then
                    local settings = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
                    if settings and settings.customTrackers then
                        settings.customTrackers.point = point
                        settings.customTrackers.x = x
                        settings.customTrackers.y = y
                        TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, settings)
                    end
                end
            end,
            
            GetPosition = function(self)
                local point, relTo, relPoint, x, y = customFrame:GetPoint(1)
                return { point = point, relFrame = relTo, relPoint = relPoint, x = x, y = y }
            end,
            
            SetPosition = function(self, point, relFrame, relPoint, x, y)
                customFrame:ClearAllPoints()
                customFrame:SetPoint(point, relFrame or UIParent, relPoint or point, x or 0, y or 0)
                if self.onPositionChanged then
                    self:onPositionChanged(point, relFrame, relPoint, x, y)
                end
            end,
            
            LoadSaveData = function(self, data)
                if not data then return end
                local point = data.point or "BOTTOMLEFT"
                self:SetPosition(point, UIParent, point, data.x, data.y)
                if data.scale then
                    self:SetScale(data.scale)
                end
            end,
            
            SetScale = function(self, scale)
                if customFrame and scale then
                    customFrame:SetScale(scale)
                end
            end,
            
            GetScale = function(self)
                return customFrame:GetScale() or 1
            end,
            
            IsShown = function(self)
                return customFrame and customFrame:IsShown()
            end,
            
            GetSnapTarget = function(self, tolerance)
                if not FlyPaper then return nil end
                tolerance = tolerance or 15
                local point, relFrame, relPoint, x, y = FlyPaper.GetBestAnchorForGroup(
                    customFrame,
                    "TUICD",
                    tolerance
                )
                if point and relFrame then
                    return relFrame, point, relPoint, x, y
                end
                return nil
            end,
            
            GetSaveData = function(self)
                local left = customFrame:GetLeft()
                local bottom = customFrame:GetBottom()
                if not left or not bottom then
                    local point, _, _, x, y = customFrame:GetPoint(1)
                    return {
                        point = point or "CENTER",
                        x = x or 0,
                        y = y or 0,
                        scale = self:GetScale(),
                    }
                end
                return {
                    point = "BOTTOMLEFT",
                    x = left,
                    y = bottom,
                    scale = self:GetScale(),
                }
            end,
            
            -- Size locking (used by SnapLocking)
            sizeLocked = false,
            SetSizeLocked = function(self, locked)
                self.sizeLocked = locked
            end,
            IsSizeLocked = function(self)
                return self.sizeLocked
            end,
            
            -- Size methods (used by SnapLocking for size matching)
            GetSize = function(self)
                return customFrame:GetSize()
            end,
            ForceSetSize = function(self, width, height)
                customFrame:SetSize(width, height)
            end,
        }
        
        customFrame.tuiFrame = wrapper
        layoutWrappers[CUSTOM_TRACKER_KEY] = wrapper
        
        -- Register with FlyPaper
        if FlyPaper then
            FlyPaper.AddFrame("TUICD", wrapperId, customFrame)
        end
        
        -- Register with Layout
        Layout:RegisterElement(wrapperId, {
            name = "Custom Cooldown Tracker",
            category = "Cooldowns",
            tuiFrame = wrapper,
            defaultPosition = wrapper.defaultPosition,
        })
        
        TUICD:PrintDebug("CooldownContainers: Registered Custom Tracker with Layout")
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function CooldownContainers:IsEnabled()
    return enabled
end

function CooldownContainers:Enable()
    if enabled then return end
    
    -- Create containers and reparent viewers
    for trackerKey, viewerName in pairs(BLIZZARD_VIEWERS) do
        local container = CreateContainer(trackerKey)
        if container then
            -- Delay reparenting to ensure viewers exist
            C_Timer.After(0.5, function()
                ReparentViewerToContainer(trackerKey)
                UpdateContainerSize(trackerKey)
            end)
        end
    end
    
    -- Setup custom tracker drag
    C_Timer.After(0.5, SetupCustomTrackerDrag)
    
    -- Periodic maintenance: retry reparenting if needed, update sizes
    C_Timer.NewTicker(2.0, function()
        if enabled then
            for trackerKey, viewerName in pairs(BLIZZARD_VIEWERS) do
                local viewer = _G[viewerName]
                local container = containers[trackerKey]
                -- Retry reparenting if viewer got un-reparented
                if viewer and container and viewer:GetParent() ~= container then
                    ReparentViewerToContainer(trackerKey)
                end
                UpdateContainerSize(trackerKey)
            end
            
            -- Retry custom tracker setup
            local customFrame = _G["TweaksUI_CustomTrackerFrame"]
            if customFrame and not customFrame._TUI_DragSetup then
                SetupCustomTrackerDrag()
            end
        end
    end)
    
    enabled = true
    
    -- Register with Layout quickly so positions can be loaded before reveal
    -- This needs to happen BEFORE Layout:ApplyAllPositions() at 3.0s
    C_Timer.After(0.8, function()
        self:RegisterWithLayout()
    end)
    
    TUICD:PrintDebug("CooldownContainers: Enabled")
end

function CooldownContainers:Disable()
    -- Restore viewers to original parents
    for trackerKey, data in pairs(originalViewerData) do
        local viewerName = BLIZZARD_VIEWERS[trackerKey]
        local viewer = viewerName and _G[viewerName]
        if viewer and data then
            -- Clear control flag
            viewer._TUI_Controlled = false
            viewer._TUI_Container = nil
            
            -- Restore original SetPoint and ClearAllPoints
            if data.originalSetPoint then
                viewer.SetPoint = data.originalSetPoint
            end
            if data.originalClearAllPoints then
                viewer.ClearAllPoints = data.originalClearAllPoints
            end
            
            -- Restore parent and position
            viewer:SetParent(data.parent)
            viewer:ClearAllPoints()
            for _, pointData in ipairs(data.points) do
                viewer:SetPoint(pointData.point, pointData.relativeTo, pointData.relativePoint, pointData.x, pointData.y)
            end
        end
    end
    
    enabled = false
    TUICD:PrintDebug("CooldownContainers: Disabled")
end

function CooldownContainers:GetContainer(trackerKey)
    return containers[trackerKey]
end

-- Public function to update container size (call after applying grid layout)
function CooldownContainers:UpdateContainerSize(trackerKey)
    UpdateContainerSize(trackerKey)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Initialize early so containers are ready BEFORE Layout reveals frames at 3.5s
-- Timeline:
--   2.0s: CooldownContainers:Enable() - creates containers, starts reparenting
--   2.5s: Viewers reparented to containers
--   2.8s: RegisterWithLayout() - containers registered with Layout
--   3.0s: Layout:ApplyAllPositions() - positions loaded for registered elements
--   3.5s: TUIFrame.RevealAllFrames() - frames become visible in correct positions
C_Timer.After(2, function()
    if TUICD.Database and TUICD.Database:IsModuleEnabled(TUICD.MODULE_IDS.COOLDOWNS) then
        CooldownContainers:Enable()
    end
end)
