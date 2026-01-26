-- ============================================================================
-- TUICD: Cooldowns - Docks Module
-- Dynamic icon grouping system with temporal ordering and flexible alignment
-- Icons from any tracker can be assigned to docks via per-icon settings
-- 
-- Key concepts:
-- - 4 dock containers (configurable: horizontal/vertical, alignment)
-- - Temporal ordering: first icon visible gets "prime" position
-- - Reparenting approach: actual per-icon frames move into docks
-- - Frames retain all their existing show/hide logic
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.Docks = TUICD.Docks or {}
local Docks = TUICD.Docks

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local NUM_DOCKS = 4
local DEFAULT_SPACING = 4
local DEFAULT_ICON_SIZE = 36
local LAYOUT_THROTTLE_TIME = 0  -- No throttle - instant updates

local ORIENTATION = {
    HORIZONTAL = "horizontal",
    VERTICAL = "vertical",
}

local JUSTIFY = {
    LEFT = "left",
    CENTER = "center",
    RIGHT = "right",
    TOP = "top",
    MIDDLE = "middle",
    BOTTOM = "bottom",
}

-- Helper: Get the appropriate WoW anchor point based on justify and orientation
local function GetJustifyAnchorPoint(justify, orientation)
    if orientation == ORIENTATION.HORIZONTAL then
        if justify == JUSTIFY.LEFT then
            return "LEFT"
        elseif justify == JUSTIFY.RIGHT then
            return "RIGHT"
        else
            return "CENTER"
        end
    else -- VERTICAL
        if justify == JUSTIFY.TOP then
            return "TOP"
        elseif justify == JUSTIFY.BOTTOM then
            return "BOTTOM"
        else
            return "CENTER"
        end
    end
end

-- ============================================================================
-- STATE
-- ============================================================================

local docks = {}  -- [dockIndex] = dock frame
local dockedIcons = {}  -- [dockIndex] = { [iconKey] = { frame, originalParent, originalPoint, ... } }
local iconArrivalOrder = {}  -- [dockIndex] = { iconKey1, iconKey2, ... }
local isInitialized = false
local layoutQueued = {}
local dockLayoutWrappers = {}  -- [dockIndex] = TUIFrame-compatible wrapper for Layout Mode

-- Debug helper
local function dprint(...)
    if TUICD.Database and TUICD.Database:GetGlobal("debugMode") == true then
        print("|cff00ccffTweaksUI Docks:|r", ...)
    end
end

-- ============================================================================
-- DOCK DEFAULTS
-- ============================================================================

local DOCK_DEFAULTS = {
    enabled = false,
    name = "",
    orientation = ORIENTATION.HORIZONTAL,
    justify = JUSTIFY.CENTER,
    spacing = DEFAULT_SPACING,
    -- Note: iconSize removed - per-icon settings control size
    dockAlpha = 1.0,  -- Alpha multiplier for entire dock
    aspectRatio = "1:1",
    customAspectW = 1,
    customAspectH = 1,
    -- Background settings
    showBackground = true,
    bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.5 },
    -- Border settings
    showBorder = true,
    borderColor = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 },
    -- Visibility
    visibilityEnabled = false,
    showInCombat = true,
    showOutOfCombat = true,
    showSolo = true,
    showInParty = true,
    showInRaid = true,
    showInInstance = true,
    showInArena = true,
    showInBattleground = true,
    showHasTarget = true,
    showNoTarget = true,
    showMounted = true,
    showNotMounted = true,
    fadeAlpha = 0.3,
    point = "CENTER",
    x = 0,
    y = -100,
    -- Visual Override Settings (applies to all icons in dock)
    visualOverrideEnabled = false,
    vo_iconSize = 36,
    vo_opacity = 1.0,
    vo_aspectRatio = "1:1",
    vo_customAspectW = 1,
    vo_customAspectH = 1,
    vo_showSweep = true,
    vo_showCountdownText = true,
    vo_showProcGlow = true,
    -- Cooldown text settings
    vo_cooldownTextScale = 1.0,
    vo_cooldownTextColor = { 1, 1, 1, 1 },
    vo_cooldownTextOffsetX = 0,
    vo_cooldownTextOffsetY = 0,
    vo_cooldownTextAnchor = "CENTER",
    -- Count text settings
    vo_countTextScale = 1.0,
    vo_countTextColor = { 1, 1, 1, 1 },
    vo_countTextOffsetX = 0,
    vo_countTextOffsetY = -2,
    vo_countTextAnchor = "BOTTOMRIGHT",
    -- Custom label settings
    vo_labelEnabled = false,
    vo_labelFontSize = 14,
    vo_labelColor = { 1, 1, 1, 1 },
    vo_labelOffsetX = 0,
    vo_labelOffsetY = 0,
    vo_labelAnchor = "CENTER",
}

-- ============================================================================
-- DATABASE ACCESS
-- ============================================================================

local function GetDocksDB()
    if not TweaksUI_Cooldowns_CharDB then TweaksUI_Cooldowns_CharDB = {} end
    if not TweaksUI_Cooldowns_CharDB.docks then
        TweaksUI_Cooldowns_CharDB.docks = {}
        for i = 1, NUM_DOCKS do
            TweaksUI_Cooldowns_CharDB.docks[i] = TUICD.DeepCopy and TUICD.DeepCopy(DOCK_DEFAULTS) or {}
            for k, v in pairs(DOCK_DEFAULTS) do
                if TweaksUI_Cooldowns_CharDB.docks[i][k] == nil then
                    TweaksUI_Cooldowns_CharDB.docks[i][k] = v
                end
            end
        end
    end
    return TweaksUI_Cooldowns_CharDB.docks
end

local function GetDockSettings(dockIndex)
    local db = GetDocksDB()
    if not db[dockIndex] then
        db[dockIndex] = TUICD.DeepCopy and TUICD.DeepCopy(DOCK_DEFAULTS) or {}
        for k, v in pairs(DOCK_DEFAULTS) do
            if db[dockIndex][k] == nil then
                db[dockIndex][k] = v
            end
        end
    end
    for k, v in pairs(DOCK_DEFAULTS) do
        if db[dockIndex][k] == nil then
            db[dockIndex][k] = v
        end
    end
    return db[dockIndex]
end

local function SetDockSetting(dockIndex, key, value)
    local settings = GetDockSettings(dockIndex)
    settings[key] = value
end

-- ============================================================================
-- ICON KEY HELPERS
-- ============================================================================

local function MakeIconKey(trackerType, slotIndex)
    return trackerType .. ":" .. slotIndex
end

local function ParseIconKey(iconKey)
    local trackerType, slotIndex = iconKey:match("^(.+):(%d+)$")
    return trackerType, tonumber(slotIndex)
end

-- ============================================================================
-- GET FRAME FROM HIGHLIGHT MODULES
-- ============================================================================

local function GetHighlightFrame(trackerType, slotIndex)
    if trackerType == "buffs" then
        return TUICD.BuffHighlights and TUICD.BuffHighlights:GetFrame(slotIndex)
    else
        return TUICD.CooldownHighlights and TUICD.CooldownHighlights:GetFrame(trackerType, slotIndex)
    end
end

-- Check if a docked icon should actually be visible (has active buff/cooldown)
-- This is more reliable than IsShown() since layout mode can force-show frames
local function IsDockedIconActive(trackerType, slotIndex, frame)
    if not frame then return false end
    
    -- Check if layout mode is active - if so, show all docked icons
    local isLayoutMode = TUICD.Layout and TUICD.Layout:IsActive()
    if isLayoutMode then
        return true
    end
    
    -- First check if the frame is hidden by the highlight module
    -- (BuffHighlights/CooldownHighlights may hide inactive frames)
    local isShown = frame:IsShown()
    if not isShown then
        if TUICD.debugMode and trackerType == "custom" then
            print(string.format("[TUI:CD Dock] IsDockedIconActive: %s:%d IsShown=false, returning false", trackerType, slotIndex))
        end
        return false
    end
    
    -- For buffs, check if the icon has a valid texture and is not desaturated
    if trackerType == "buffs" then
        local icon = frame.icon or frame.Icon
        if icon then
            local texture = nil
            pcall(function() texture = icon:GetTexture() end)
            if texture and texture ~= 134400 and texture ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
                -- Has a real texture - check desaturated state
                -- Not desaturated = buff is active
                local desaturated = icon:IsDesaturated()
                if not desaturated then
                    return true
                end
            end
        end
        return false
    else
        -- For cooldowns (essential, utility, customTrackers)
        -- Check if the icon is desaturated (inactive) or not (active/on cooldown)
        local icon = frame.icon or frame.Icon
        if icon then
            local desaturated = icon:IsDesaturated()
            -- If not desaturated, it's ready (should show)
            if not desaturated then
                if TUICD.debugMode and trackerType == "custom" then
                    print(string.format("[TUI:CD Dock] IsDockedIconActive: %s:%d IsShown=true, desaturated=false -> VISIBLE", trackerType, slotIndex))
                end
                return true
            else
                if TUICD.debugMode and trackerType == "custom" then
                    print(string.format("[TUI:CD Dock] IsDockedIconActive: %s:%d IsShown=true, desaturated=true -> HIDDEN (on cooldown)", trackerType, slotIndex))
                end
            end
        else
            if TUICD.debugMode and trackerType == "custom" then
                print(string.format("[TUI:CD Dock] IsDockedIconActive: %s:%d no icon found", trackerType, slotIndex))
            end
        end
        return false
    end
end

-- ============================================================================
-- VISIBILITY EVALUATION
-- ============================================================================

-- Get current player state for visibility checks (same pattern as Cooldowns module)
local function GetPlayerState()
    local state = {
        inCombat = InCombatLockdown() or UnitAffectingCombat("player"),
        inGroup = IsInGroup(),
        inRaid = IsInRaid(),
        inInstance = false,
        inArena = false,
        inBattleground = false,
        isSolo = not IsInGroup(),
        hasTarget = UnitExists("target"),
        isMounted = TUICD.UnitAPI:IsMountedOrTravelForm(),
    }
    
    -- Check instance type
    local _, instanceType = IsInInstance()
    if instanceType == "party" or instanceType == "raid" then
        state.inInstance = true
    elseif instanceType == "arena" then
        state.inArena = true
    elseif instanceType == "pvp" then
        state.inBattleground = true
    end
    
    return state
end

local function EvaluateDockVisibility(dockIndex)
    local settings = GetDockSettings(dockIndex)
    
    -- Always show in TUICD Layout Mode for positioning (even if disabled)
    if TUICD.Layout and TUICD.Layout:IsActive() then
        return true
    end
    
    if not settings.enabled then
        return false
    end
    
    -- Always show in Edit Mode for positioning
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return true
    end
    
    if not settings.visibilityEnabled then
        return true  -- Visibility system disabled = always show
    end
    
    local state = GetPlayerState()
    
    -- OR logic: if ANY checked condition is true, show the dock
    if state.inCombat and settings.showInCombat then return true end
    if not state.inCombat and settings.showOutOfCombat then return true end
    if state.isSolo and settings.showSolo then return true end
    if state.inGroup and not state.inRaid and settings.showInParty then return true end
    if state.inRaid and settings.showInRaid then return true end
    if state.inInstance and settings.showInInstance then return true end
    if state.inArena and settings.showInArena then return true end
    if state.inBattleground and settings.showInBattleground then return true end
    if state.hasTarget and settings.showHasTarget then return true end
    if not state.hasTarget and settings.showNoTarget then return true end
    if state.isMounted and settings.showMounted then return true end
    if not state.isMounted and settings.showNotMounted then return true end
    
    -- No conditions matched
    return false
end

-- ============================================================================
-- DOCK FRAME CREATION
-- ============================================================================

local function CreateDockFrame(dockIndex)
    local frameName = "TweaksUI_Dock_" .. dockIndex
    
    if _G[frameName] then
        return _G[frameName]
    end
    
    local dock = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    dock:SetSize(100, 50)
    dock:SetFrameStrata("LOW")
    dock:SetFrameLevel(20)
    dock:SetClampedToScreen(true)
    dock:SetMovable(true)
    dock:EnableMouse(false)
    
    dock:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    
    dock.label = dock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dock.label:SetPoint("TOP", dock, "BOTTOM", 0, -2)
    dock.label:SetText("Dock " .. dockIndex)
    dock.label:SetTextColor(0.6, 0.6, 0.6, 0.8)
    dock.label:Hide()
    
    dock.emptyText = dock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dock.emptyText:SetPoint("CENTER")
    dock.emptyText:SetText("|cff555555Drop Icons Here|r")
    dock.emptyText:Hide()
    
    dock.dockIndex = dockIndex
    
    docks[dockIndex] = dock
    dockedIcons[dockIndex] = {}
    iconArrivalOrder[dockIndex] = {}
    layoutQueued[dockIndex] = false
    
    -- Position dock using justify-appropriate anchor point
    local settings = GetDockSettings(dockIndex)
    local anchorPoint = GetJustifyAnchorPoint(settings.justify or JUSTIFY.CENTER, settings.orientation or ORIENTATION.HORIZONTAL)
    local savedPoint = settings.point or "CENTER"
    local x = settings.x or 0
    local y = settings.y or 0
    
    dock:ClearAllPoints()
    dock:SetPoint(anchorPoint, UIParent, savedPoint, x, y)
    
    -- Apply background/border settings
    Docks:ApplyDockAppearance(dockIndex)
    
    dock:Hide()
    
    dprint("Created dock frame:", dockIndex, "with anchor:", anchorPoint)
    
    return dock
end

-- Update the dock's anchor point based on current justify setting
-- When savePosition=true, recalculates and saves from current screen position
-- When savePosition=false, just repositions using saved coordinates at the correct anchor
local function UpdateDockAnchor(dockIndex, savePosition)
    local dock = docks[dockIndex]
    if not dock then return end
    
    local settings = GetDockSettings(dockIndex)
    local newAnchor = GetJustifyAnchorPoint(settings.justify or JUSTIFY.CENTER, settings.orientation or ORIENTATION.HORIZONTAL)
    
    if savePosition then
        -- Recalculate position from current screen location (used when justify changes)
        local left, bottom, width, height = dock:GetRect()
        if not left or not width then return end
        
        local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
        local centerX = left + width / 2
        local centerY = bottom + height / 2
        
        -- Calculate the position of the new anchor point relative to UIParent CENTER
        local anchorX, anchorY
        if newAnchor == "LEFT" then
            anchorX = left - screenWidth / 2
            anchorY = centerY - screenHeight / 2
        elseif newAnchor == "RIGHT" then
            anchorX = (left + width) - screenWidth / 2
            anchorY = centerY - screenHeight / 2
        elseif newAnchor == "TOP" then
            anchorX = centerX - screenWidth / 2
            anchorY = (bottom + height) - screenHeight / 2
        elseif newAnchor == "BOTTOM" then
            anchorX = centerX - screenWidth / 2
            anchorY = bottom - screenHeight / 2
        else -- CENTER
            anchorX = centerX - screenWidth / 2
            anchorY = centerY - screenHeight / 2
        end
        
        dock:ClearAllPoints()
        dock:SetPoint(newAnchor, UIParent, "CENTER", anchorX, anchorY)
        
        -- Save the new position data
        SetDockSetting(dockIndex, "point", "CENTER")
        SetDockSetting(dockIndex, "x", anchorX)
        SetDockSetting(dockIndex, "y", anchorY)
        
        dprint("Updated dock", dockIndex, "anchor to", newAnchor, "and saved position")
    else
        -- Just reposition using saved x/y at the correct anchor point (used during layout)
        local savedPoint = settings.point or "CENTER"
        local savedX = settings.x or 0
        local savedY = settings.y or 0
        
        dock:ClearAllPoints()
        dock:SetPoint(newAnchor, UIParent, savedPoint, savedX, savedY)
        
        dprint("Repositioned dock", dockIndex, "at anchor", newAnchor, "using saved position")
    end
end

-- Apply background/border/alpha settings to a dock
function Docks:ApplyDockAppearance(dockIndex)
    local dock = docks[dockIndex]
    if not dock then return end
    
    local settings = GetDockSettings(dockIndex)
    
    -- Background
    if settings.showBackground then
        local bg = settings.bgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.5 }
        dock:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
    else
        dock:SetBackdropColor(0, 0, 0, 0)
    end
    
    -- Border
    if settings.showBorder then
        local border = settings.borderColor or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
        dock:SetBackdropBorderColor(border.r, border.g, border.b, border.a)
    else
        dock:SetBackdropBorderColor(0, 0, 0, 0)
    end
    
    -- Dock alpha (multiplier for entire dock)
    local alpha = settings.dockAlpha or 1.0
    dock:SetAlpha(alpha)
end

-- ============================================================================
-- LAYOUT MODE INTEGRATION
-- Creates TUIFrame-compatible wrappers for docks so they appear in Layout Mode
-- ============================================================================

local function CreateDockLayoutWrapper(dockIndex)
    local dock = docks[dockIndex]
    if not dock then return nil end
    
    local settings = GetDockSettings(dockIndex)
    local wrapperId = "Dock_" .. dockIndex
    
    -- Already has a wrapper
    if dockLayoutWrappers[dockIndex] then
        return dockLayoutWrappers[dockIndex]
    end
    
    -- Helper to get current justify-based anchor
    local function GetCurrentAnchor()
        local s = GetDockSettings(dockIndex)
        return GetJustifyAnchorPoint(s.justify or JUSTIFY.CENTER, s.orientation or ORIENTATION.HORIZONTAL)
    end
    
    -- Create TUIFrame-compatible wrapper object
    local wrapper = {
        id = wrapperId,
        frame = dock,
        name = Docks:GetDockName(dockIndex),
        category = "Cooldowns",
        
        -- Default position - uses justify-based anchor
        defaultPosition = {
            point = GetCurrentAnchor(),
            x = 0,
            y = -100 * dockIndex,  -- Stack docks vertically by default
        },
        
        -- Get the anchor point this dock uses (based on justify setting)
        GetAnchorPoint = function(self)
            return GetCurrentAnchor()
        end,
        
        -- Position management - always uses justify-based anchor
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            if InCombatLockdown() then return end
            
            local anchor = GetCurrentAnchor()
            relFrame = relFrame or UIParent
            relPoint = relPoint or point or "CENTER"
            x = x or 0
            y = y or 0
            
            dock:ClearAllPoints()
            dock:SetPoint(anchor, relFrame, relPoint, x, y)
            
            -- Save to dock settings (store the relative point and offsets)
            SetDockSetting(dockIndex, "point", relPoint)
            SetDockSetting(dockIndex, "x", x)
            SetDockSetting(dockIndex, "y", y)
        end,
        
        GetSaveData = function(self)
            local anchor = GetCurrentAnchor()
            local point, relTo, relPoint, x, y = dock:GetPoint(1)
            
            if point then
                return {
                    point = relPoint or "CENTER",
                    x = x or 0,
                    y = y or 0,
                }
            end
            
            return {
                point = "CENTER",
                x = 0,
                y = 0,
            }
        end,
        
        LoadSaveData = function(self, data)
            if not data then return end
            if InCombatLockdown() then return end
            
            local anchor = GetCurrentAnchor()
            local relPoint = data.point or "CENTER"
            local x = data.x or 0
            local y = data.y or 0
            
            dock:ClearAllPoints()
            dock:SetPoint(anchor, UIParent, relPoint, x, y)
            
            -- Save to dock settings
            SetDockSetting(dockIndex, "point", relPoint)
            SetDockSetting(dockIndex, "x", x)
            SetDockSetting(dockIndex, "y", y)
        end,
        
        -- Size management
        GetSize = function(self)
            return dock:GetSize()
        end,
        
        GetWidth = function(self)
            return dock:GetWidth()
        end,
        
        GetHeight = function(self)
            return dock:GetHeight()
        end,
        
        -- Scale (docks typically don't use scale, but provide the interface)
        GetScale = function(self)
            return dock:GetScale() or 1
        end,
        
        SetScale = function(self, scale)
            dock:SetScale(scale)
        end,
        
        -- Visibility
        Show = function(self)
            dock:Show()
        end,
        
        Hide = function(self)
            dock:Hide()
        end,
        
        IsShown = function(self)
            return dock:IsShown()
        end,
        
        -- Size locking (used by SnapLocking for size matching)
        SetSizeLocked = function(self, locked)
            self.sizeLocked = locked
        end,
        
        IsSizeLocked = function(self)
            return self.sizeLocked
        end,
        
        -- Get outer size (for snap size matching)
        GetOuterSize = function(self)
            local left, bottom, width, height = dock:GetRect()
            if width and height then
                return width, height
            end
            return dock:GetSize()
        end,
        
        -- FlyPaper snap detection
        GetSnapPoints = function(self, tolerance)
            local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
            if not FlyPaper or not FlyPaper.Stick then return nil end
            
            local point, relFrame, relPoint, x, y = FlyPaper.Stick(
                dock,
                "TUICD",
                tolerance
            )
            if point and relFrame then
                return relFrame, point, relPoint, x, y
            end
            return nil
        end,
        
        -- GetSnapTarget (alias for GetSnapPoints, used by LayoutUI)
        GetSnapTarget = function(self, tolerance)
            local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
            if not FlyPaper or not FlyPaper.Stick then return nil end
            
            local point, relFrame, relPoint, x, y = FlyPaper.Stick(
                dock,
                "TUICD",
                tolerance
            )
            if point and relFrame then
                return relFrame, point, relPoint, x, y
            end
            return nil
        end,
        
        -- Position changed callback
        onPositionChanged = function(self, point, relFrame, relPoint, x, y)
            SetDockSetting(dockIndex, "point", point)
            SetDockSetting(dockIndex, "x", x)
            SetDockSetting(dockIndex, "y", y)
            dprint("Dock", dockIndex, "position saved via Layout Mode")
        end,
    }
    
    dock.tuiFrame = wrapper
    dockLayoutWrappers[dockIndex] = wrapper
    
    -- Register with FlyPaper for snap highlighting
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    if FlyPaper and FlyPaper.AddFrame then
        FlyPaper.AddFrame("TUICD", wrapperId, dock)
    end
    
    dprint("Created Layout wrapper for dock", dockIndex)
    return wrapper
end

local function RegisterDockWithLayout(dockIndex)
    local Layout = TUICD.Layout
    if not Layout or not Layout.RegisterElement then
        dprint("Layout module not available for dock", dockIndex)
        return false
    end
    
    -- Ensure dock frame exists
    local dock = docks[dockIndex]
    if not dock then
        dock = CreateDockFrame(dockIndex)
    end
    
    if not dock then
        dprint("Failed to create dock frame for", dockIndex)
        return false
    end
    
    -- Create wrapper
    local wrapper = dockLayoutWrappers[dockIndex]
    if not wrapper then
        wrapper = CreateDockLayoutWrapper(dockIndex)
    end
    
    if not wrapper then
        dprint("Failed to create wrapper for dock", dockIndex)
        return false
    end
    
    local wrapperId = "Dock_" .. dockIndex
    
    -- Register with Layout
    Layout:RegisterElement(wrapperId, {
        name = Docks:GetDockName(dockIndex),
        category = Layout.CATEGORIES and Layout.CATEGORIES.COOLDOWNS or "Cooldowns",
        tuiFrame = wrapper,
        defaultPosition = wrapper.defaultPosition,
        onPositionChanged = function(id, pos)
            if wrapper.onPositionChanged then
                wrapper:onPositionChanged(pos.point, pos.relFrame, pos.relPoint, pos.x, pos.y)
            end
        end,
    })
    
    dprint("Registered dock", dockIndex, "with Layout Mode as", wrapperId)
    return true
end

local function UnregisterDockFromLayout(dockIndex)
    local Layout = TUICD.Layout
    if not Layout or not Layout.UnregisterElement then return end
    
    local wrapperId = "Dock_" .. dockIndex
    Layout:UnregisterElement(wrapperId)
    
    dockLayoutWrappers[dockIndex] = nil
    dprint("Unregistered dock", dockIndex, "from Layout Mode")
end

-- Register all docks with Layout Mode
local function RegisterAllDocksWithLayout()
    for i = 1, NUM_DOCKS do
        RegisterDockWithLayout(i)
    end
end

-- ============================================================================
-- LAYOUT SYSTEM
-- ============================================================================

local function QueueLayout(dockIndex)
    if layoutQueued[dockIndex] then return end
    layoutQueued[dockIndex] = true
    
    C_Timer.After(LAYOUT_THROTTLE_TIME, function()
        layoutQueued[dockIndex] = false
        Docks:LayoutDock(dockIndex)
    end)
end

-- Get visible icons sorted by arrival order
local function GetSortedVisibleIcons(dockIndex)
    local icons = dockedIcons[dockIndex] or {}
    local arrivalOrder = iconArrivalOrder[dockIndex] or {}
    local visible = {}
    
    for _, iconKey in ipairs(arrivalOrder) do
        local iconInfo = icons[iconKey]
        if iconInfo and iconInfo.frame then
            -- Use IsDockedIconActive instead of just IsShown()
            -- This properly handles layout mode exit by checking actual icon state
            local isActive = IsDockedIconActive(iconInfo.trackerType, iconInfo.slotIndex, iconInfo.frame)
            if isActive then
                table.insert(visible, iconInfo)
                if TUICD.debugMode then
                    print(string.format("[TUI:CD Dock] Dock %d visible: %s", dockIndex, iconKey))
                end
            end
        end
    end
    
    return visible
end

-- Calculate center-out position
local function GetCenterOutPosition(arrivalIndex, totalCount)
    if totalCount <= 1 then return 1 end
    
    local center = math.ceil(totalCount / 2)
    
    if arrivalIndex == 1 then
        return center
    end
    
    local offset = math.ceil((arrivalIndex - 1) / 2)
    local goLeft = (arrivalIndex % 2) == 0
    
    if goLeft then
        return math.max(1, center - offset)
    else
        return math.min(totalCount, center + offset)
    end
end

-- Main layout function
function Docks:LayoutDock(dockIndex)
    local dock = docks[dockIndex]
    local settings = GetDockSettings(dockIndex)
    local isLayoutMode = TUICD.Layout and TUICD.Layout:IsActive()
    
    -- DEBUG: Trace LayoutDock calls
    if TUICD.debugMode then
        print(string.format("[TUI:CD] LayoutDock(%d) called - dock=%s, enabled=%s, layoutMode=%s", 
            dockIndex, dock and "exists" or "nil", tostring(settings.enabled), tostring(isLayoutMode)))
    end
    
    -- Create dock frame on demand if enabled OR if in layout mode
    if not dock and (settings.enabled or isLayoutMode) then
        dock = CreateDockFrame(dockIndex)
        -- Also ensure Layout wrapper exists
        if dock and not dockLayoutWrappers[dockIndex] then
            RegisterDockWithLayout(dockIndex)
        end
    end
    
    if not dock then return end
    
    local dockVisible = EvaluateDockVisibility(dockIndex)
    
    -- In layout mode, always show ALL docks (enabled or disabled) for positioning
    if isLayoutMode then
        dockVisible = true
    end
    
    if not dockVisible then
        dock:Hide()
        return
    end
    
    -- Get visible icons
    local visible = GetSortedVisibleIcons(dockIndex)
    local n = #visible
    
    -- DEBUG: Show visible icon count
    if TUICD.debugMode then
        print(string.format("[TUI:CD] Dock %d: %d visible icons", dockIndex, n))
    end
    
    -- Hide inactive icons (not in layout mode)
    -- This ensures icons that were shown during layout mode get hidden when exiting
    if not isLayoutMode then
        local allIcons = dockedIcons[dockIndex] or {}
        local visibleKeys = {}
        for _, iconInfo in ipairs(visible) do
            local key = MakeIconKey(iconInfo.trackerType, iconInfo.slotIndex)
            visibleKeys[key] = true
        end
        
        for iconKey, iconInfo in pairs(allIcons) do
            if not visibleKeys[iconKey] and iconInfo.frame then
                -- This icon is not active - hide it using alpha to avoid taint
                iconInfo.frame:SetAlpha(0)
            end
        end
        
        -- Restore alpha for visible icons
        for _, iconInfo in ipairs(visible) do
            if iconInfo.frame then
                iconInfo.frame:SetAlpha(1)
            end
        end
    else
        -- In layout mode, show all icons
        local allIcons = dockedIcons[dockIndex] or {}
        for _, iconInfo in pairs(allIcons) do
            if iconInfo.frame then
                iconInfo.frame:SetAlpha(1)
            end
        end
    end
    
    -- Settings
    local size = settings.iconSize or DEFAULT_ICON_SIZE
    local spacing = settings.spacing or DEFAULT_SPACING
    local orientation = settings.orientation or ORIENTATION.HORIZONTAL
    local justify = settings.justify or JUSTIFY.CENTER
    
    -- Handle empty dock
    if n == 0 then
        -- If not in layout mode, hide empty docks completely
        if not isLayoutMode then
            dock:Hide()
            return
        end
        
        -- Layout mode: show empty dock for positioning
        local minW, minH
        if orientation == ORIENTATION.HORIZONTAL then
            minW = size * 3 + spacing * 2
            minH = size + 10
        else
            minW = size + 10
            minH = size * 3 + spacing * 2
        end
        
        -- Set anchor point before sizing (same as with icons)
        local anchorPoint = GetJustifyAnchorPoint(justify, orientation)
        local savedPoint = settings.point or "CENTER"
        local savedX = settings.x or 0
        local savedY = settings.y or 0
        
        -- Check if this dock is snap-locked
        local wrapperId = "Dock_" .. dockIndex
        local SnapLocking = TUICD.SnapLocking
        local isSnapLocked = SnapLocking and SnapLocking:IsAttached(wrapperId)
        
        if isSnapLocked then
            -- For snap-locked docks: clear points, apply attachment (sets anchor), then resize
            dock:ClearAllPoints()
            SnapLocking:ApplyAttachment(wrapperId)
            dock:SetSize(minW, minH)
        else
            -- Free positioning
            dock:ClearAllPoints()
            dock:SetPoint(anchorPoint, UIParent, savedPoint, savedX, savedY)
            dock:SetSize(minW, minH)
        end
        
        local dockName = Docks:GetDockName(dockIndex)
        if settings.enabled then
            if dock.emptyText then
                dock.emptyText:SetText("|cff00ccff" .. dockName .. " - Empty|r")
                dock.emptyText:Show()
            end
            dock:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
            dock:SetBackdropBorderColor(0, 0.8, 1.0, 1.0)
        else
            if dock.emptyText then
                dock.emptyText:SetText("|cff666666" .. dockName .. " (Disabled)|r")
                dock.emptyText:Show()
            end
            dock:SetBackdropColor(0.08, 0.08, 0.08, 0.4)
            dock:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.5)
        end
        if dock.label then
            dock.label:SetText(dockName)
            dock.label:Show()
        end
        
        dock:Show()
        return
    end
    
    -- Has icons - hide empty indicator
    if dock.emptyText then dock.emptyText:Hide() end
    if dock.label then 
        if isLayoutMode then
            dock.label:SetText(Docks:GetDockName(dockIndex))
            dock.label:Show()
        else
            dock.label:Hide()
        end
    end
    
    -- Calculate dock size based on actual frame sizes
    local totalW, totalH = 0, 0
    local maxW, maxH = 0, 0
    for _, iconInfo in ipairs(visible) do
        if iconInfo.frame then
            local w, h = iconInfo.frame:GetSize()
            -- Safety: ensure valid size
            if w < 1 then w = 40 end
            if h < 1 then h = 40 end
            totalW = totalW + w
            totalH = totalH + h
            if w > maxW then maxW = w end
            if h > maxH then maxH = h end
        end
    end
    
    local dockW, dockH
    if orientation == ORIENTATION.HORIZONTAL then
        dockW = totalW + (n - 1) * spacing + 8
        dockH = maxH + 8
    else
        dockW = maxW + 8
        dockH = totalH + (n - 1) * spacing + 8
    end
    
    -- CRITICAL: Set anchor point BEFORE changing size
    -- This ensures the dock expands/contracts around the correct point
    local anchorPoint = GetJustifyAnchorPoint(justify, orientation)
    local savedPoint = settings.point or "CENTER"
    local savedX = settings.x or 0
    local savedY = settings.y or 0
    
    -- Check if this dock is snap-locked - if so, let SnapLocking handle position
    local wrapperId = "Dock_" .. dockIndex
    local SnapLocking = TUICD.SnapLocking
    local isSnapLocked = SnapLocking and SnapLocking:IsAttached(wrapperId)
    
    -- DEBUG: Show snap state
    if TUICD.debugMode then
        local att = SnapLocking and SnapLocking:GetAttachment(wrapperId)
        if att then
            print(string.format("[TUI:CD] Dock %d: snap-locked=%s, point=%s->%s, offset=%.1f,%.1f", 
                dockIndex, tostring(isSnapLocked), att.point, att.relPoint, att.offsetX or 0, att.offsetY or 0))
        else
            print(string.format("[TUI:CD] Dock %d: snap-locked=%s (no attachment data)", dockIndex, tostring(isSnapLocked)))
        end
    end
    
    if isSnapLocked then
        -- For snap-locked docks: we need special handling to keep the dock centered
        -- when the attachment is NOT CENTER-to-CENTER
        local att = SnapLocking:GetAttachment(wrapperId)
        local parentTUI = att and SnapLocking:GetTUIFrame(att.parentId)
        local parentFrame = parentTUI and parentTUI.frame
        
        -- If we have the parent frame and attachment, calculate CENTER position
        if parentFrame and att then
            -- Size dock first (needed for center calculations)
            dock:SetSize(dockW, dockH)
            
            -- Calculate where the dock's CENTER should be relative to parent's CENTER
            -- The attachment might be BOTTOMLEFT->BOTTOMLEFT, but we want the dock to
            -- visually stay centered relative to the parent
            
            -- Get the saved center offset (calculated at snap time)
            local centerOffsetX = att.centerOffsetX
            local centerOffsetY = att.centerOffsetY
            
            if centerOffsetX and centerOffsetY then
                -- Use saved CENTER offset for proper centering during resize
                dock:ClearAllPoints()
                dock:SetPoint("CENTER", parentFrame, "CENTER", centerOffsetX, centerOffsetY)
                
                if TUICD.debugMode then
                    print(string.format("[TUI:CD] Dock %d: Using saved CENTER offset %.1f,%.1f", 
                        dockIndex, centerOffsetX, centerOffsetY))
                end
            else
                -- No saved center offset - calculate it from the original attachment
                -- First, temporarily apply the original attachment to get the intended position
                dock:ClearAllPoints()
                dock:SetPoint(
                    att.point or "BOTTOMLEFT",
                    parentFrame,
                    att.relPoint or "BOTTOMLEFT",
                    att.offsetX or 0,
                    att.offsetY or 0
                )
                
                -- Now calculate where the center SHOULD be (for proper centering)
                -- Get current dock center position
                local dockCenterX = dock:GetLeft() + dockW / 2
                local dockCenterY = dock:GetBottom() + dockH / 2
                
                -- Get parent center position
                local parentCenterX = parentFrame:GetLeft() + parentFrame:GetWidth() / 2
                local parentCenterY = parentFrame:GetBottom() + parentFrame:GetHeight() / 2
                
                -- Calculate center offset
                centerOffsetX = dockCenterX - parentCenterX
                centerOffsetY = dockCenterY - parentCenterY
                
                -- Save it for future use
                att.centerOffsetX = centerOffsetX
                att.centerOffsetY = centerOffsetY
                SnapLocking:SaveAttachments()
                
                -- Re-apply with CENTER anchor for proper resize behavior
                dock:ClearAllPoints()
                dock:SetPoint("CENTER", parentFrame, "CENTER", centerOffsetX, centerOffsetY)
                
                if TUICD.debugMode then
                    print(string.format("[TUI:CD] Dock %d: Calculated CENTER offset %.1f,%.1f (saved for future)", 
                        dockIndex, centerOffsetX, centerOffsetY))
                end
            end
        else
            -- Fallback: just apply attachment normally
            dock:ClearAllPoints()
            SnapLocking:ApplyAttachment(wrapperId)
            dock:SetSize(dockW, dockH)
        end
    else
        -- Free positioning - set anchor first, then size
        dock:ClearAllPoints()
        dock:SetPoint(anchorPoint, UIParent, savedPoint, savedX, savedY)
        dock:SetSize(dockW, dockH)
    end
    
    -- Position each icon (DO NOT resize - let per-icon settings control size)
    -- Icons are always placed linearly (left-to-right for horizontal, top-to-bottom for vertical)
    -- Icons are CENTERED on the main axis within the dock
    -- Justify affects CROSS-AXIS alignment only:
    --   Horizontal dock: justify affects vertical alignment (TOP/BOTTOM/CENTER)
    --   Vertical dock: justify affects horizontal alignment (LEFT/RIGHT/CENTER)
    
    -- Calculate total size of icons for centering on main axis
    local totalIconsW = 0
    local totalIconsH = 0
    for _, iconInfo in ipairs(visible) do
        if iconInfo.frame then
            local w, h = iconInfo.frame:GetSize()
            if w < 1 then w = 40 end
            if h < 1 then h = 40 end
            totalIconsW = totalIconsW + w
            totalIconsH = totalIconsH + h
        end
    end
    
    -- Add spacing between icons
    if n > 1 then
        totalIconsW = totalIconsW + (n - 1) * spacing
        totalIconsH = totalIconsH + (n - 1) * spacing
    end
    
    -- Calculate starting offset to center icons on main axis
    local xOffset, yOffset
    if orientation == ORIENTATION.HORIZONTAL then
        -- Center horizontally: start offset = (dockW - totalIconsW) / 2
        xOffset = (dockW - totalIconsW) / 2
        yOffset = -4  -- Will be calculated per-icon based on justify
    else
        -- Center vertically: start offset = -(dockH - totalIconsH) / 2
        xOffset = 4  -- Will be calculated per-icon based on justify
        yOffset = -(dockH - totalIconsH) / 2
    end
    
    for i, iconInfo in ipairs(visible) do
        if iconInfo and iconInfo.frame then
            local frame = iconInfo.frame
            local frameW, frameH = frame:GetSize()
            
            -- Safety: ensure valid size
            if frameW < 1 then frameW = 40 end
            if frameH < 1 then frameH = 40 end
            
            -- Position within dock (respect frame's own size)
            frame:ClearAllPoints()
            
            if orientation == ORIENTATION.HORIZONTAL then
                -- Horizontal dock: place left-to-right, justify affects vertical position
                local y
                if justify == JUSTIFY.TOP or justify == JUSTIFY.LEFT then
                    y = -4
                elseif justify == JUSTIFY.BOTTOM or justify == JUSTIFY.RIGHT then
                    y = -(dockH - frameH - 4)
                else
                    -- CENTER
                    y = -(dockH - frameH) / 2
                end
                frame:SetPoint("TOPLEFT", dock, "TOPLEFT", xOffset, y)
                xOffset = xOffset + frameW + spacing
            else
                -- Vertical dock: place top-to-bottom, justify affects horizontal position
                local x
                if justify == JUSTIFY.LEFT or justify == JUSTIFY.TOP then
                    x = 4
                elseif justify == JUSTIFY.RIGHT or justify == JUSTIFY.BOTTOM then
                    x = dockW - frameW - 4
                else
                    -- CENTER
                    x = (dockW - frameW) / 2
                end
                frame:SetPoint("TOPLEFT", dock, "TOPLEFT", x, yOffset)
                yOffset = yOffset - frameH - spacing
            end
        end
    end
    
    -- Update background colors based on layout mode
    if isLayoutMode then
        -- Highlight colors for layout mode
        dock:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
        dock:SetBackdropBorderColor(0, 0.8, 1.0, 0.9)
    else
        -- Use saved appearance settings
        Docks:ApplyDockAppearance(dockIndex)
    end
    
    dock:Show()
end

-- ============================================================================
-- ICON ASSIGNMENT (Reparenting approach)
-- ============================================================================

function Docks:AssignIcon(dockIndex, trackerType, slotIndex)
    if not dockIndex or dockIndex < 1 or dockIndex > NUM_DOCKS then
        -- Unassign from all docks
        for i = 1, NUM_DOCKS do
            self:UnassignIcon(i, trackerType, slotIndex)
        end
        return
    end
    
    -- First unassign from any other dock
    for i = 1, NUM_DOCKS do
        if i ~= dockIndex then
            self:UnassignIcon(i, trackerType, slotIndex)
        end
    end
    
    local frame = GetHighlightFrame(trackerType, slotIndex)
    if not frame then
        dprint("AssignIcon: No frame found for", trackerType, slotIndex)
        return
    end
    
    -- Create dock if needed
    local dock = docks[dockIndex]
    if not dock then
        dock = CreateDockFrame(dockIndex)
    end
    
    local iconKey = MakeIconKey(trackerType, slotIndex)
    local icons = dockedIcons[dockIndex]
    
    -- If already docked here, skip
    if icons[iconKey] then
        dprint("Icon already docked:", iconKey)
        return
    end
    
    -- Save original state
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local origW, origH = frame:GetSize()
    
    icons[iconKey] = {
        frame = frame,
        originalParent = frame:GetParent(),
        originalPoint = point,
        originalRelativeTo = relativeTo,
        originalRelativePoint = relativePoint,
        originalX = x,
        originalY = y,
        originalW = origW,
        originalH = origH,
        trackerType = trackerType,
        slotIndex = slotIndex,
    }
    
    -- Reparent to dock
    frame:SetParent(dock)
    
    -- Add to arrival order
    local arrivalOrder = iconArrivalOrder[dockIndex]
    local found = false
    for _, key in ipairs(arrivalOrder) do
        if key == iconKey then
            found = true
            break
        end
    end
    if not found then
        table.insert(arrivalOrder, iconKey)
    end
    
    if TUICD.Events then
        TUICD.Events:Fire("TweaksUI_DockAssignmentChanged", dockIndex, trackerType, slotIndex, true)
    end
    
    QueueLayout(dockIndex)
    dprint("Assigned icon", iconKey, "to dock", dockIndex)
end

function Docks:UnassignIcon(dockIndex, trackerType, slotIndex)
    if not dockIndex or dockIndex < 1 or dockIndex > NUM_DOCKS then return end
    
    local iconKey = MakeIconKey(trackerType, slotIndex)
    local icons = dockedIcons[dockIndex]
    
    if not icons or not icons[iconKey] then return end
    
    local iconInfo = icons[iconKey]
    local frame = iconInfo.frame
    
    if frame then
        -- Restore original parent and position
        frame:SetParent(iconInfo.originalParent or UIParent)
        frame:ClearAllPoints()
        frame:SetPoint(
            iconInfo.originalPoint or "CENTER",
            iconInfo.originalRelativeTo or UIParent,
            iconInfo.originalRelativePoint or "CENTER",
            iconInfo.originalX or 0,
            iconInfo.originalY or 0
        )
        -- Restore original size
        if iconInfo.originalW and iconInfo.originalH then
            frame:SetSize(iconInfo.originalW, iconInfo.originalH)
        end
    end
    
    -- Remove from tracking
    icons[iconKey] = nil
    
    -- Remove from arrival order
    local arrivalOrder = iconArrivalOrder[dockIndex]
    if arrivalOrder then
        for i = #arrivalOrder, 1, -1 do
            if arrivalOrder[i] == iconKey then
                table.remove(arrivalOrder, i)
                break
            end
        end
    end
    
    if TUICD.Events then
        TUICD.Events:Fire("TweaksUI_DockAssignmentChanged", dockIndex, trackerType, slotIndex, false)
    end
    
    QueueLayout(dockIndex)
    dprint("Unassigned icon", iconKey, "from dock", dockIndex)
end

-- Notify docks that a frame needs relayout
function Docks:NotifyIconUpdate(trackerType, slotIndex)
    for dockIndex = 1, NUM_DOCKS do
        local iconKey = MakeIconKey(trackerType, slotIndex)
        if dockedIcons[dockIndex] and dockedIcons[dockIndex][iconKey] then
            QueueLayout(dockIndex)
            break
        end
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Restore all docked icons to their original positions (for PLAYER_LOGOUT cleanup)
function Docks:RestoreAllDockedIcons()
    dprint("RestoreAllDockedIcons called")
    
    for dockIndex = 1, NUM_DOCKS do
        local icons = dockedIcons[dockIndex]
        if icons then
            -- Collect keys first to avoid modifying table during iteration
            local keysToUnassign = {}
            for iconKey, iconInfo in pairs(icons) do
                -- Parse iconKey back to trackerType and slotIndex
                local trackerType, slotIndex = iconKey:match("^(.+):(%d+)$")
                if trackerType and slotIndex then
                    table.insert(keysToUnassign, {
                        trackerType = trackerType,
                        slotIndex = tonumber(slotIndex),
                    })
                end
            end
            
            -- Now unassign each icon
            for _, info in ipairs(keysToUnassign) do
                self:UnassignIcon(dockIndex, info.trackerType, info.slotIndex)
            end
        end
    end
    
    dprint("All docked icons restored to original positions")
end

function Docks:GetDockSettings(dockIndex)
    return GetDockSettings(dockIndex)
end

function Docks:SetDockSetting(dockIndex, key, value)
    SetDockSetting(dockIndex, key, value)
    
    local layoutKeys = {
        orientation = true, justify = true, spacing = true,
        aspectRatio = true, customAspectW = true,
        customAspectH = true, enabled = true,
    }
    if layoutKeys[key] then
        QueueLayout(dockIndex)
    end
    
    -- When justify or orientation changes, update the dock's anchor point
    -- Pass true to save the position (recalculate from current screen location)
    if key == "justify" or key == "orientation" then
        UpdateDockAnchor(dockIndex, true)
    end
    
    -- Appearance keys trigger ApplyDockAppearance
    local appearanceKeys = {
        showBackground = true, bgColor = true,
        showBorder = true, borderColor = true,
        dockAlpha = true,
    }
    if appearanceKeys[key] then
        self:ApplyDockAppearance(dockIndex)
    end
    
    -- Visibility keys trigger a layout refresh (to show/hide dock)
    local visibilityKeys = {
        visibilityEnabled = true,
        showInCombat = true, showOutOfCombat = true,
        showSolo = true, showInParty = true, showInRaid = true,
        showInInstance = true, showInArena = true, showInBattleground = true,
        showHasTarget = true, showNoTarget = true,
        showMounted = true, showNotMounted = true,
    }
    if visibilityKeys[key] then
        QueueLayout(dockIndex)
    end
    
    -- Visual override keys trigger ApplyVisualOverride
    local visualOverrideKeys = {
        visualOverrideEnabled = true,
        vo_iconSize = true, vo_opacity = true,
        vo_aspectRatio = true, vo_customAspectW = true, vo_customAspectH = true,
        vo_showSweep = true, vo_showCountdownText = true, vo_showProcGlow = true,
        vo_cooldownTextScale = true, vo_cooldownTextColor = true,
        vo_cooldownTextOffsetX = true, vo_cooldownTextOffsetY = true, vo_cooldownTextAnchor = true,
        vo_countTextScale = true, vo_countTextColor = true,
        vo_countTextOffsetX = true, vo_countTextOffsetY = true, vo_countTextAnchor = true,
        vo_labelEnabled = true, vo_labelFontSize = true, vo_labelColor = true,
        vo_labelOffsetX = true, vo_labelOffsetY = true, vo_labelAnchor = true,
    }
    if visualOverrideKeys[key] then
        self:ApplyVisualOverride(dockIndex)
        -- Also need layout refresh for size/aspect changes
        if key == "vo_iconSize" or key:find("Aspect") then
            QueueLayout(dockIndex)
        end
    end
end

function Docks:GetDockCount()
    return NUM_DOCKS
end

-- Get the anchor point for a dock based on its justify and orientation settings
function Docks:GetDockAnchorPoint(dockIndex)
    local settings = GetDockSettings(dockIndex)
    return GetJustifyAnchorPoint(settings.justify or JUSTIFY.CENTER, settings.orientation or ORIENTATION.HORIZONTAL)
end

-- Update a dock's anchor point
-- savePosition: if true (default), recalculates from current position and saves
--               if false, just repositions using saved coordinates
function Docks:UpdateDockAnchor(dockIndex, savePosition)
    -- Default to false for the common case of just repositioning
    if savePosition == nil then savePosition = false end
    UpdateDockAnchor(dockIndex, savePosition)
end

-- Apply visual override settings to all icons in a dock
function Docks:ApplyVisualOverride(dockIndex)
    local settings = GetDockSettings(dockIndex)
    if not settings.visualOverrideEnabled then
        dprint("Visual override disabled for dock", dockIndex)
        return
    end
    
    local docked = dockedIcons[dockIndex]
    if not docked then
        dprint("No icons in dock", dockIndex)
        return
    end
    
    dprint("Applying visual override to dock", dockIndex)
    
    -- Get the visual override settings
    local vo = {
        iconSize = settings.vo_iconSize or 36,
        opacity = settings.vo_opacity or 1.0,
        aspectRatio = settings.vo_aspectRatio or "1:1",
        customAspectW = settings.vo_customAspectW or 1,
        customAspectH = settings.vo_customAspectH or 1,
        showSweep = settings.vo_showSweep ~= false,
        showCountdownText = settings.vo_showCountdownText ~= false,
        showProcGlow = settings.vo_showProcGlow ~= false,
        cooldownTextScale = settings.vo_cooldownTextScale or 1.0,
        cooldownTextColor = settings.vo_cooldownTextColor or {1, 1, 1, 1},
        cooldownTextOffsetX = settings.vo_cooldownTextOffsetX or 0,
        cooldownTextOffsetY = settings.vo_cooldownTextOffsetY or 0,
        cooldownTextAnchor = settings.vo_cooldownTextAnchor or "CENTER",
        countTextScale = settings.vo_countTextScale or 1.0,
        countTextColor = settings.vo_countTextColor or {1, 1, 1, 1},
        countTextOffsetX = settings.vo_countTextOffsetX or 0,
        countTextOffsetY = settings.vo_countTextOffsetY or -2,
        countTextAnchor = settings.vo_countTextAnchor or "BOTTOMRIGHT",
        labelEnabled = settings.vo_labelEnabled or false,
        labelFontSize = settings.vo_labelFontSize or 14,
        labelColor = settings.vo_labelColor or {1, 1, 1, 1},
        labelOffsetX = settings.vo_labelOffsetX or 0,
        labelOffsetY = settings.vo_labelOffsetY or 0,
        labelAnchor = settings.vo_labelAnchor or "CENTER",
    }
    
    -- Apply to each icon in the dock
    for iconKey, iconData in pairs(docked) do
        local trackerType, slotIndex = ParseIconKey(iconKey)
        
        if trackerType and slotIndex then
            if trackerType == "buffs" then
                -- Apply to BuffHighlights
                if TUICD.BuffHighlights then
                    local BH = TUICD.BuffHighlights
                    -- Size and appearance (apply to both states)
                    for _, state in ipairs({"active", "inactive"}) do
                        BH:SetSize(slotIndex, state, vo.iconSize)
                        BH:SetOpacity(slotIndex, state, vo.opacity)
                        BH:SetAspectRatio(slotIndex, state, vo.aspectRatio)
                        if vo.aspectRatio == "custom" then
                            BH:SetCustomAspectRatio(slotIndex, state, vo.customAspectW, vo.customAspectH)
                        end
                    end
                    -- Sweep and countdown text visibility (per-icon override)
                    BH:SetShowSweep(slotIndex, vo.showSweep)
                    BH:SetShowCountdownText(slotIndex, vo.showCountdownText)
                    BH:SetShowProcGlow(slotIndex, vo.showProcGlow)
                    -- Text settings (state-independent)
                    BH:SetCooldownTextScale(slotIndex, vo.cooldownTextScale)
                    BH:SetCooldownTextColor(slotIndex, vo.cooldownTextColor)
                    BH:SetCooldownTextOffsetX(slotIndex, vo.cooldownTextOffsetX)
                    BH:SetCooldownTextOffsetY(slotIndex, vo.cooldownTextOffsetY)
                    BH:SetCooldownTextAnchor(slotIndex, vo.cooldownTextAnchor)
                    BH:SetCountTextScale(slotIndex, vo.countTextScale)
                    BH:SetCountTextColor(slotIndex, vo.countTextColor)
                    BH:SetCountTextOffsetX(slotIndex, vo.countTextOffsetX)
                    BH:SetCountTextOffsetY(slotIndex, vo.countTextOffsetY)
                    BH:SetCountTextAnchor(slotIndex, vo.countTextAnchor)
                    -- Label settings
                    BH:SetLabelEnabled(slotIndex, vo.labelEnabled)
                    BH:SetLabelFontSize(slotIndex, vo.labelFontSize)
                    BH:SetLabelColor(slotIndex, vo.labelColor)
                    BH:SetLabelOffsetX(slotIndex, vo.labelOffsetX)
                    BH:SetLabelOffsetY(slotIndex, vo.labelOffsetY)
                    BH:SetLabelAnchor(slotIndex, vo.labelAnchor)
                end
            else
                -- Apply to CooldownHighlights (essential, utility, customTrackers)
                if TUICD.CooldownHighlights then
                    local CH = TUICD.CooldownHighlights
                    -- Size and appearance (apply to both states)
                    for _, state in ipairs({"active", "inactive"}) do
                        CH:SetSize(trackerType, slotIndex, state, vo.iconSize)
                        CH:SetOpacity(trackerType, slotIndex, state, vo.opacity)
                        CH:SetAspectRatio(trackerType, slotIndex, state, vo.aspectRatio)
                        if vo.aspectRatio == "custom" then
                            CH:SetCustomAspectRatio(trackerType, slotIndex, state, vo.customAspectW, vo.customAspectH)
                        end
                    end
                    -- Sweep and countdown text visibility (per-icon override)
                    CH:SetShowSweep(trackerType, slotIndex, vo.showSweep)
                    CH:SetShowCountdownText(trackerType, slotIndex, vo.showCountdownText)
                    CH:SetShowProcGlow(trackerType, slotIndex, vo.showProcGlow)
                    -- Text settings (state-independent)
                    CH:SetCooldownTextScale(trackerType, slotIndex, vo.cooldownTextScale)
                    CH:SetCooldownTextColor(trackerType, slotIndex, vo.cooldownTextColor)
                    CH:SetCooldownTextOffsetX(trackerType, slotIndex, vo.cooldownTextOffsetX)
                    CH:SetCooldownTextOffsetY(trackerType, slotIndex, vo.cooldownTextOffsetY)
                    CH:SetCooldownTextAnchor(trackerType, slotIndex, vo.cooldownTextAnchor)
                    CH:SetCountTextScale(trackerType, slotIndex, vo.countTextScale)
                    CH:SetCountTextColor(trackerType, slotIndex, vo.countTextColor)
                    CH:SetCountTextOffsetX(trackerType, slotIndex, vo.countTextOffsetX)
                    CH:SetCountTextOffsetY(trackerType, slotIndex, vo.countTextOffsetY)
                    CH:SetCountTextAnchor(trackerType, slotIndex, vo.countTextAnchor)
                    -- Label settings
                    CH:SetLabelEnabled(trackerType, slotIndex, vo.labelEnabled)
                    CH:SetLabelFontSize(trackerType, slotIndex, vo.labelFontSize)
                    CH:SetLabelColor(trackerType, slotIndex, vo.labelColor)
                    CH:SetLabelOffsetX(trackerType, slotIndex, vo.labelOffsetX)
                    CH:SetLabelOffsetY(trackerType, slotIndex, vo.labelOffsetY)
                    CH:SetLabelAnchor(trackerType, slotIndex, vo.labelAnchor)
                end
            end
            
            dprint("Applied override to", iconKey)
        end
    end
    
    -- Refresh all highlight frames to apply the visual changes
    -- Track which tracker types need refreshing
    local trackersToRefresh = {}
    local refreshBuffs = false
    
    for iconKey, _ in pairs(docked) do
        local trackerType, _ = ParseIconKey(iconKey)
        if trackerType == "buffs" then
            refreshBuffs = true
        elseif trackerType then
            trackersToRefresh[trackerType] = true
        end
    end
    
    -- Refresh CooldownHighlights for each tracker type
    if TUICD.CooldownHighlights then
        for trackerType in pairs(trackersToRefresh) do
            pcall(TUICD.CooldownHighlights.RefreshAllHighlights, TUICD.CooldownHighlights, trackerType)
        end
    end
    
    -- Refresh BuffHighlights if needed
    if refreshBuffs and TUICD.BuffHighlights then
        pcall(TUICD.BuffHighlights.RefreshAllHighlights, TUICD.BuffHighlights)
    end
    
    -- Trigger layout refresh to apply size changes
    QueueLayout(dockIndex)
end

-- Get list of icons assigned to a dock (for UI display)
function Docks:GetDockedIcons(dockIndex)
    local result = {}
    local docked = dockedIcons[dockIndex]
    if docked then
        for iconKey, iconData in pairs(docked) do
            local trackerType, slotIndex = ParseIconKey(iconKey)
            table.insert(result, {
                key = iconKey,
                trackerType = trackerType,
                slotIndex = slotIndex,
            })
        end
    end
    return result
end

function Docks:RefreshAllDocks()
    for i = 1, NUM_DOCKS do
        QueueLayout(i)
    end
end

function Docks:GetDockName(dockIndex)
    local settings = GetDockSettings(dockIndex)
    if settings.name and settings.name ~= "" then
        return settings.name
    end
    return "Dock " .. dockIndex
end

function Docks:GetDock(dockIndex)
    return docks[dockIndex]
end

-- Get the Layout Mode wrapper for a dock
function Docks:GetDockLayoutWrapper(dockIndex)
    return dockLayoutWrappers[dockIndex]
end

-- Force-create a dock frame even if disabled (used by Layout Mode)
function Docks:EnsureDockExists(dockIndex)
    if docks[dockIndex] then 
        -- Dock already exists, just make sure it's shown for layout mode
        local isLayoutMode = TUICD.Layout and TUICD.Layout:IsActive()
        if isLayoutMode then
            docks[dockIndex]:Show()
        end
        
        -- Ensure Layout wrapper exists
        if not dockLayoutWrappers[dockIndex] then
            RegisterDockWithLayout(dockIndex)
        end
        
        return docks[dockIndex] 
    end
    
    -- Create the dock frame
    local dock = CreateDockFrame(dockIndex)
    
    -- Show it for overlay positioning in layout mode
    if dock then
        local isLayoutMode = TUICD.Layout and TUICD.Layout:IsActive()
        if isLayoutMode then
            dock:Show()
        end
        
        -- Create Layout wrapper and register
        RegisterDockWithLayout(dockIndex)
    end
    
    return dock
end

function Docks:SaveDockPosition(dockIndex)
    local dock = docks[dockIndex]
    if not dock then return end
    
    local point, relativeTo, relPoint, x, y = dock:GetPoint(1)
    SetDockSetting(dockIndex, "point", point)           -- The dock's anchor point
    SetDockSetting(dockIndex, "relPoint", relPoint)     -- The parent's anchor point
    SetDockSetting(dockIndex, "x", x)
    SetDockSetting(dockIndex, "y", y)
    
    dprint("Saved position for dock", dockIndex, ":", point, "->", relPoint, "at", x, y)
end

function Docks:IsIconDocked(trackerType, slotIndex)
    local iconKey = MakeIconKey(trackerType, slotIndex)
    for dockIndex = 1, NUM_DOCKS do
        if dockedIcons[dockIndex] and dockedIcons[dockIndex][iconKey] then
            return dockIndex
        end
    end
    return nil
end

-- Legacy API for compatibility - no longer needed with reparenting
function Docks:UpdateIconState(dockIndex, trackerType, slotIndex, iconData)
    -- The per-icon frame handles its own state now
    -- Just trigger a relayout in case visibility changed
    if dockIndex then
        QueueLayout(dockIndex)
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function Docks:Initialize()
    if isInitialized then return end
    
    dprint("Initializing Docks module")
    
    -- Create dock frames for enabled docks
    for i = 1, NUM_DOCKS do
        local settings = GetDockSettings(i)
        if settings.enabled then
            CreateDockFrame(i)
        end
        dockedIcons[i] = dockedIcons[i] or {}
        iconArrivalOrder[i] = iconArrivalOrder[i] or {}
    end
    
    -- Register ALL docks with Layout Mode (even disabled ones, for positioning)
    -- Delay slightly to ensure Layout module is ready
    C_Timer.After(0.5, function()
        RegisterAllDocksWithLayout()
    end)
    
    -- Register for visibility events
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")  -- For druid travel form
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    eventFrame:SetScript("OnEvent", function(self, event)
        Docks:RefreshAllDocks()
    end)
    
    -- Register for aura/cooldown events (throttled and deferred to allow highlight modules to update first)
    local auraEventFrame = CreateFrame("Frame")
    local pendingAuraRefresh = false
    local AURA_REFRESH_DELAY = 0.1  -- Delay to let highlight modules update icon states first
    
    auraEventFrame:RegisterEvent("UNIT_AURA")
    auraEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    auraEventFrame:SetScript("OnEvent", function(self, event, unit)
        -- Only care about player auras
        if event == "UNIT_AURA" and unit ~= "player" then return end
        
        -- Always defer refresh slightly so highlight modules can update icon states first
        if not pendingAuraRefresh then
            pendingAuraRefresh = true
            C_Timer.After(AURA_REFRESH_DELAY, function()
                pendingAuraRefresh = false
                Docks:RefreshAllDocks()
            end)
        end
    end)
    
    -- Register for layout mode events (TUICD.Events system)
    if TUICD.Events then
        TUICD.Events:Register("LAYOUT_MODE_ENTER", function()
            -- Ensure all docks exist and are shown for Layout Mode
            for i = 1, NUM_DOCKS do
                Docks:EnsureDockExists(i)
                local dock = docks[i]
                if dock then
                    dock:Show()
                end
            end
            Docks:RefreshAllDocks()
        end, Docks)
        
        TUICD.Events:Register("LAYOUT_MODE_EXIT", function()
            Docks:RefreshAllDocks()
        end, Docks)
    end
    
    -- Also register with Layout module's callback system
    if TUICD.Layout then
        TUICD.Layout:RegisterCallback("OnLayoutModeEnter", function()
            -- Ensure all docks exist and are shown for Layout Mode
            for i = 1, NUM_DOCKS do
                Docks:EnsureDockExists(i)
                local dock = docks[i]
                if dock then
                    dock:Show()
                end
            end
            Docks:RefreshAllDocks()
        end)
        
        TUICD.Layout:RegisterCallback("OnLayoutModeExit", function()
            Docks:RefreshAllDocks()
        end)
    end
    
    -- Initial layout
    C_Timer.After(0.2, function()
        Docks:RefreshAllDocks()
    end)
    
    isInitialized = true
    dprint("Docks module initialized")
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

function Docks:Cleanup()
    for i = 1, NUM_DOCKS do
        local dock = docks[i]
        if dock then
            dock:Hide()
        end
        
        -- Restore all docked icons to original parents
        local icons = dockedIcons[i]
        if icons then
            for iconKey, iconInfo in pairs(icons) do
                if iconInfo.frame then
                    iconInfo.frame:SetParent(iconInfo.originalParent or UIParent)
                    iconInfo.frame:ClearAllPoints()
                    iconInfo.frame:SetPoint(
                        iconInfo.originalPoint or "CENTER",
                        iconInfo.originalRelativeTo or UIParent,
                        iconInfo.originalRelativePoint or "CENTER",
                        iconInfo.originalX or 0,
                        iconInfo.originalY or 0
                    )
                    if iconInfo.originalW and iconInfo.originalH then
                        iconInfo.frame:SetSize(iconInfo.originalW, iconInfo.originalH)
                    end
                end
            end
            wipe(icons)
        end
        
        if iconArrivalOrder[i] then
            wipe(iconArrivalOrder[i])
        end
    end
end

-- ============================================================================
-- ORPHAN CLEANUP
-- ============================================================================

-- Clean up orphaned dock assignments (icons that no longer exist)
function Docks:CleanupOrphans(specificDock)
    local cleanedCount = 0
    local checkedCount = 0
    
    print("|cff00ccff[TUI:CD Docks]|r Scanning for orphaned dock assignments...")
    
    -- Helper to check if a frame exists and has valid texture
    local function IsValidDockedIcon(trackerType, slotIndex)
        local frame = GetHighlightFrame(trackerType, slotIndex)
        if not frame then return false end
        
        -- Check if frame has a valid icon texture
        local icon = frame.icon or frame.Icon
        if not icon then return false end
        
        local texture = nil
        pcall(function() texture = icon:GetTexture() end)
        
        -- Consider it orphaned if no texture or it's the question mark
        if not texture then return false end
        if texture == "Interface\\Icons\\INV_Misc_QuestionMark" then return false end
        if type(texture) == "number" and texture == 134400 then return false end  -- Question mark fileID
        
        return true
    end
    
    -- Clean BuffHighlights dock assignments
    local buffDB = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.buffHighlights
    if buffDB and buffDB.dockAssignment then
        local toRemove = {}
        for slotIndex, dockIndex in pairs(buffDB.dockAssignment) do
            if dockIndex and (not specificDock or dockIndex == specificDock) then
                checkedCount = checkedCount + 1
                if not IsValidDockedIcon("buffs", slotIndex) then
                    table.insert(toRemove, slotIndex)
                    print(string.format("  |cffff8888Orphan found:|r buffs slot %d in dock %d", slotIndex, dockIndex))
                end
            end
        end
        for _, slotIndex in ipairs(toRemove) do
            local dockIndex = buffDB.dockAssignment[slotIndex]
            buffDB.dockAssignment[slotIndex] = nil
            -- Also remove from runtime state
            if dockIndex then
                local iconKey = MakeIconKey("buffs", slotIndex)
                if dockedIcons[dockIndex] then
                    dockedIcons[dockIndex][iconKey] = nil
                end
                if iconArrivalOrder[dockIndex] then
                    for i = #iconArrivalOrder[dockIndex], 1, -1 do
                        if iconArrivalOrder[dockIndex][i] == iconKey then
                            table.remove(iconArrivalOrder[dockIndex], i)
                            break
                        end
                    end
                end
            end
            cleanedCount = cleanedCount + 1
        end
    end
    
    -- Clean CooldownHighlights dock assignments for each tracker
    for _, trackerKey in ipairs({"essential", "utility", "customTrackers"}) do
        local db = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB[trackerKey .. "Highlights"]
        if db and db.dockAssignment then
            local toRemove = {}
            for slotIndex, dockIndex in pairs(db.dockAssignment) do
                if dockIndex and (not specificDock or dockIndex == specificDock) then
                    checkedCount = checkedCount + 1
                    if not IsValidDockedIcon(trackerKey, slotIndex) then
                        table.insert(toRemove, slotIndex)
                        print(string.format("  |cffff8888Orphan found:|r %s slot %d in dock %d", trackerKey, slotIndex, dockIndex))
                    end
                end
            end
            for _, slotIndex in ipairs(toRemove) do
                local dockIndex = db.dockAssignment[slotIndex]
                db.dockAssignment[slotIndex] = nil
                -- Also remove from runtime state
                if dockIndex then
                    local iconKey = MakeIconKey(trackerKey, slotIndex)
                    if dockedIcons[dockIndex] then
                        dockedIcons[dockIndex][iconKey] = nil
                    end
                    if iconArrivalOrder[dockIndex] then
                        for i = #iconArrivalOrder[dockIndex], 1, -1 do
                            if iconArrivalOrder[dockIndex][i] == iconKey then
                                table.remove(iconArrivalOrder[dockIndex], i)
                                break
                            end
                        end
                    end
                end
                cleanedCount = cleanedCount + 1
            end
        end
    end
    
    -- Refresh dock layouts
    if cleanedCount > 0 then
        self:RefreshAllDocks()
        print(string.format("|cff00ccff[TUI:CD Docks]|r Cleaned %d orphaned assignment(s) (checked %d total)", cleanedCount, checkedCount))
    else
        print(string.format("|cff00ccff[TUI:CD Docks]|r No orphans found (checked %d assignments)", checkedCount))
    end
    
    return cleanedCount
end

-- Clear all assignments from a specific dock
function Docks:ClearDock(dockIndex)
    if not dockIndex or dockIndex < 1 or dockIndex > NUM_DOCKS then
        print("|cff00ccff[TUI:CD Docks]|r Invalid dock number. Use 1-4.")
        return 0
    end
    
    local clearedCount = 0
    
    -- Clear from BuffHighlights
    local buffDB = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.buffHighlights
    if buffDB and buffDB.dockAssignment then
        for slotIndex, assignedDock in pairs(buffDB.dockAssignment) do
            if assignedDock == dockIndex then
                buffDB.dockAssignment[slotIndex] = nil
                clearedCount = clearedCount + 1
            end
        end
    end
    
    -- Clear from CooldownHighlights
    for _, trackerKey in ipairs({"essential", "utility", "customTrackers"}) do
        local db = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB[trackerKey .. "Highlights"]
        if db and db.dockAssignment then
            for slotIndex, assignedDock in pairs(db.dockAssignment) do
                if assignedDock == dockIndex then
                    db.dockAssignment[slotIndex] = nil
                    clearedCount = clearedCount + 1
                end
            end
        end
    end
    
    -- Clear runtime state
    if dockedIcons[dockIndex] then
        wipe(dockedIcons[dockIndex])
    end
    if iconArrivalOrder[dockIndex] then
        wipe(iconArrivalOrder[dockIndex])
    end
    
    -- Refresh
    self:RefreshAllDocks()
    
    print(string.format("|cff00ccff[TUI:CD Docks]|r Cleared %d assignment(s) from Dock %d", clearedCount, dockIndex))
    return clearedCount
end

-- Restore all dock assignments from saved variables
function Docks:RestoreAllAssignments()
    dprint("RestoreAllAssignments called")
    
    -- Restore BuffHighlights dock assignments
    if TUICD.Modules and TUICD.Modules.BuffHighlights then
        local db = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.buffHighlights
        if db and db.dockAssignment then
            for slotIndex, dockIndex in pairs(db.dockAssignment) do
                if dockIndex then
                    local frame = TUICD.Modules.BuffHighlights:GetFrame(slotIndex)
                    if frame then
                        dprint("Restoring buff slot", slotIndex, "-> dock", dockIndex)
                        self:AssignIcon(dockIndex, "buffs", slotIndex)
                    end
                end
            end
        end
    end
    
    -- Restore CooldownHighlights dock assignments for each tracker
    if TUICD.Modules and TUICD.Modules.CooldownHighlights then
        for _, trackerKey in ipairs({"essential", "utility", "customTrackers"}) do
            local db = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB[trackerKey .. "Highlights"]
            if db and db.dockAssignment then
                for slotIndex, dockIndex in pairs(db.dockAssignment) do
                    if dockIndex then
                        local frame = TUICD.Modules.CooldownHighlights:GetFrame(trackerKey, slotIndex)
                        if frame then
                            dprint("Restoring", trackerKey, slotIndex, "-> dock", dockIndex)
                            self:AssignIcon(dockIndex, trackerKey, slotIndex)
                        end
                    end
                end
            end
        end
    end
    
    -- Refresh all dock layouts
    self:RefreshAllDocks()
end

-- ============================================================================
-- AUTO-INITIALIZE
-- ============================================================================

-- Initialize on PLAYER_LOGIN (most reliable timing)
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    C_Timer.After(0.1, function()
        Docks:Initialize()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)

-- Also restore on PLAYER_ENTERING_WORLD as backup
local pewFrame = CreateFrame("Frame")
pewFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
pewFrame:SetScript("OnEvent", function(self, event)
    C_Timer.After(2, function()
        if TUICD.Docks and TUICD.Docks.RestoreAllAssignments then
            TUICD.Docks:RestoreAllAssignments()
        end
    end)
end)
