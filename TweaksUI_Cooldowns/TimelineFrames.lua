-- ============================================================================
-- TUI:CD Timeline - Visual Frames
-- Phase 2: Basic frame + icon positioning with smooth animation
-- Phase 3: Database integration for persistent settings
--
-- Icons slide along the bar based on remaining cooldown time.
-- Default (rightToLeft): ready on left, longest on right.
-- Reversed (leftToRight): ready on right, longest on left.
-- Position formula: xPos = (remaining / maxDuration) * barWidth
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.TimelineFrames = TUICD.TimelineFrames or {}
local TimelineFrames = TUICD.TimelineFrames
local TimelineData = TUICD.TimelineData

-- ============================================================================
-- CONSTANTS & DEFAULTS (fallbacks if database not available)
-- ============================================================================

local DEFAULTS = {
    -- Bar dimensions
    barWidth = 400,
    barHeight = 4,
    barColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.9 },
    
    -- Frame background (encompasses line and icons)
    showBackground = false,
    backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 },
    backgroundPadding = 4,
    
    -- Icon settings
    iconSize = 36,
    iconAspectRatio = "1:1",
    iconSpacing = 2,
    iconVerticalOffset = 0,   -- Positive = above bar, negative = below bar
    staggerOverlaps = true,   -- Stack icons vertically when they overlap
    
    -- Timeline range
    maxDuration = 30,
    direction = "rightToLeft",  -- "rightToLeft" = ready on left, "leftToRight" = ready on right
    showOverflowStack = true,
    
    -- Cooldown display
    showCooldownSweep = true,
    cooldownTextSize = 10,
    showCooldownText = true,
    cooldownTextOffset = 0,   -- Positive = above icon, negative = below icon, 0 = bottom of icon
    
    -- Animation
    updateInterval = 0.033,
    
    -- Visibility settings
    visibilityEnabled = false,
    showInCombat = true,
    showOutOfCombat = true,
    showSolo = true,
    showInParty = true,
    showInRaid = true,
    showInDungeon = true,
    showInDelve = true,
    showInArena = true,
    showInBattleground = true,
    showHasTarget = true,
    showNoTarget = true,
    showMounted = true,
    showNotMounted = true,
}

-- Aspect ratio lookup table
local ASPECT_RATIOS = {
    ["1:1"]  = { w = 1,  h = 1 },
    ["4:3"]  = { w = 4,  h = 3 },
    ["3:4"]  = { w = 3,  h = 4 },
    ["16:9"] = { w = 16, h = 9 },
    ["9:16"] = { w = 9,  h = 16 },
    ["2:1"]  = { w = 2,  h = 1 },
    ["1:2"]  = { w = 1,  h = 2 },
}

-- ============================================================================
-- STATE
-- ============================================================================

local timelineFrame = nil
local iconPool = {}           -- Reusable icon frames
local activeIcons = {}        -- { [spellID] = iconFrame }
local readyIcons = {}         -- { [spellID] = iconFrame } - icons at 0 remaining
local settings = {}           -- Current settings (merged with defaults)
local lastUpdate = 0
local isEnabled = false

-- Debug
local debugMode = false
local function dprint(...)
    if debugMode then
        print("|cff00ccff[TL-Frames]|r", ...)
    end
end

function TimelineFrames:SetDebug(enabled)
    debugMode = enabled
end

-- ============================================================================
-- SETTINGS
-- ============================================================================

-- Get setting from database or default
local function GetSettingValue(key)
    -- Try to get from TimelineUI (which reads from database)
    if TUICD.TimelineUI and TUICD.TimelineUI.GetSetting then
        local val = TUICD.TimelineUI:GetSetting(key)
        if val ~= nil then
            return val
        end
    end
    -- Fallback to defaults
    return DEFAULTS[key]
end

-- Build settings table from individual settings
local function GetSettings()
    local s = {}
    for key, defaultVal in pairs(DEFAULTS) do
        s[key] = GetSettingValue(key)
    end
    return s
end

function TimelineFrames:GetSetting(key)
    return GetSettingValue(key)
end

-- Set a setting (goes through TimelineUI to database)
function TimelineFrames:SetSetting(key, value)
    if TUICD.TimelineUI and TUICD.TimelineUI.SetSetting then
        TUICD.TimelineUI:SetSetting(key, value)
    else
        -- Fallback: update DEFAULTS directly (won't persist)
        if DEFAULTS[key] ~= nil then
            DEFAULTS[key] = value
        end
    end
    dprint(string.format("Setting %s = %s", key, tostring(value)))
    self:Refresh()
    return true
end

-- ============================================================================
-- ICON POOL
-- ============================================================================

-- Calculate icon dimensions based on size and aspect ratio
local function GetIconDimensions()
    local s = GetSettings()
    local size = s.iconSize
    local ratio = ASPECT_RATIOS[s.iconAspectRatio] or ASPECT_RATIOS["1:1"]
    
    local width, height
    if ratio.w >= ratio.h then
        width = size
        height = size * (ratio.h / ratio.w)
    else
        height = size
        width = size * (ratio.w / ratio.h)
    end
    
    return width, height
end

-- Calculate texture coordinates for aspect ratio cropping (zoom, don't stretch)
-- This crops into the center of the texture rather than distorting it
local function GetAspectRatioTexCoords(iconWidth, iconHeight)
    local zoom = 0.08  -- Standard edge trim
    local left, right, top, bottom = zoom, 1 - zoom, zoom, 1 - zoom
    
    if iconWidth and iconHeight and iconWidth ~= iconHeight then
        if iconWidth > iconHeight then
            -- Wide icon: crop top and bottom of texture
            local cropAmount = (1 - iconHeight / iconWidth) / 2
            top = top + cropAmount * (1 - 2 * zoom)
            bottom = bottom - cropAmount * (1 - 2 * zoom)
        else
            -- Tall icon: crop left and right of texture
            local cropAmount = (1 - iconWidth / iconHeight) / 2
            left = left + cropAmount * (1 - 2 * zoom)
            right = right - cropAmount * (1 - 2 * zoom)
        end
    end
    
    return left, right, top, bottom
end

local function CreateIcon(parent)
    local iconW, iconH = GetIconDimensions()
    local s = GetSettings()
    
    -- Container frame
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(iconW, iconH)
    
    -- NO backdrop on the icon frame
    if icon.SetBackdrop then
        icon:SetBackdrop(nil)
    end
    
    -- Icon texture - zoom into center for non-square aspects
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    
    -- Apply aspect ratio cropping (zoom into center)
    local left, right, top, bottom = GetAspectRatioTexCoords(iconW, iconH)
    icon.texture:SetTexCoord(left, right, top, bottom)
    
    -- Cooldown swipe - use minimal frame with NO template
    -- The key to avoiding dark box is NOT using CooldownFrameTemplate
    icon.cooldown = CreateFrame("Cooldown", nil, icon)
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetDrawBling(false)
    icon.cooldown:SetHideCountdownNumbers(true)
    icon.cooldown:SetFrameLevel(icon:GetFrameLevel() + 1)
    
    -- CRITICAL: Set reverse to false (prevents dark background on some cooldowns)
    icon.cooldown:SetReverse(false)
    
    -- Configure swipe to be just the dark overlay, no background
    if s.showCooldownSweep then
        icon.cooldown:SetDrawSwipe(true)
        icon.cooldown:SetSwipeColor(0, 0, 0, 0.6)
        -- Use a simple swipe texture without background
        icon.cooldown:SetSwipeTexture("Interface\\Cooldown\\edge")
    else
        icon.cooldown:SetDrawSwipe(false)
    end
    
    -- CRITICAL: Remove ANY background textures from cooldown
    -- The Cooldown frame can have built-in backgrounds we need to hide
    C_Timer.After(0, function()
        if icon.cooldown then
            -- Hide all child regions
            local regions = {icon.cooldown:GetRegions()}
            for _, region in ipairs(regions) do
                if region then
                    if region.GetDrawLayer then
                        local layer = region:GetDrawLayer()
                        -- Hide EVERYTHING except OVERLAY (where swipe is drawn)
                        if layer == "BACKGROUND" or layer == "BORDER" or layer == "ARTWORK" then
                            if region.SetTexture then
                                region:SetTexture(nil)
                            end
                            region:Hide()
                            region:SetAlpha(0)
                        end
                    end
                end
            end
            -- Remove backdrop completely
            if icon.cooldown.SetBackdrop then
                icon.cooldown:SetBackdrop(nil)
            end
        end
    end)
    
    -- Duration text
    local fontName, _, fontFlags = GameFontNormalSmall:GetFont()
    icon.durationText = icon:CreateFontString(nil, "OVERLAY")
    icon.durationText:SetFont(fontName, s.cooldownTextSize, fontFlags)
    icon.durationText:SetTextColor(1, 1, 1, 1)
    icon.durationText:SetShadowOffset(1, -1)
    icon.durationText:SetShown(s.showCooldownText)
    
    -- Position text based on offset
    local textOffset = s.cooldownTextOffset or 0
    if textOffset >= 0 then
        icon.durationText:SetPoint("BOTTOM", icon, "BOTTOM", 0, 2 + textOffset)
    else
        icon.durationText:SetPoint("TOP", icon, "BOTTOM", 0, textOffset)
    end
    
    -- State tracking
    icon.spellID = nil
    icon.isReady = false
    icon.isOverflow = false
    icon.targetX = 0
    icon.verticalOffset = 0
    
    icon:Hide()
    return icon
end

local function AcquireIcon()
    for _, icon in ipairs(iconPool) do
        if not icon:IsShown() then
            return icon
        end
    end
    
    -- Create new icon if pool exhausted
    local icon = CreateIcon(timelineFrame)
    table.insert(iconPool, icon)
    return icon
end

local function ReleaseIcon(icon)
    icon:Hide()
    icon.spellID = nil
    icon.isReady = false
    icon.isOverflow = false
    icon.cooldown:Clear()
    icon.texture:SetTexture(nil)
    icon.durationText:SetText("")
end

-- Update icon appearance based on current settings
local function UpdateIconAppearance(icon)
    local s = GetSettings()
    local iconW, iconH = GetIconDimensions()
    
    icon:SetSize(iconW, iconH)
    
    -- Update cooldown swipe visibility
    icon.cooldown:SetReverse(false)
    if s.showCooldownSweep then
        icon.cooldown:SetDrawSwipe(true)
        icon.cooldown:SetSwipeColor(0, 0, 0, 0.6)
        icon.cooldown:SetSwipeTexture("Interface\\Cooldown\\edge")
    else
        icon.cooldown:SetDrawSwipe(false)
    end
    
    -- Ensure cooldown frame background elements stay hidden
    local regions = {icon.cooldown:GetRegions()}
    for _, region in ipairs(regions) do
        if region then
            if region.GetDrawLayer then
                local layer = region:GetDrawLayer()
                if layer == "BACKGROUND" or layer == "BORDER" or layer == "ARTWORK" then
                    if region.SetTexture then
                        region:SetTexture(nil)
                    end
                    region:SetAlpha(0)
                    region:Hide()
                end
            end
        end
    end
    
    icon.durationText:SetShown(s.showCooldownText)
    
    -- Update texture coordinates for aspect ratio (zoom, not stretch)
    local left, right, top, bottom = GetAspectRatioTexCoords(iconW, iconH)
    icon.texture:SetTexCoord(left, right, top, bottom)
    
    -- Update font size
    local fontName, _, fontFlags = GameFontNormalSmall:GetFont()
    icon.durationText:SetFont(fontName, s.cooldownTextSize, fontFlags)
    
    -- Update text position based on offset
    icon.durationText:ClearAllPoints()
    local textOffset = s.cooldownTextOffset or 0
    if textOffset >= 0 then
        icon.durationText:SetPoint("BOTTOM", icon, "BOTTOM", 0, 2 + textOffset)
    else
        icon.durationText:SetPoint("TOP", icon, "BOTTOM", 0, textOffset)
    end
end

-- ============================================================================
-- POSITION CALCULATION
-- ============================================================================

-- Track overflow icons for stacking
local overflowIcons = {}  -- { iconFrame, ... } in order of remaining time

-- Calculate X position for an icon based on remaining time
-- Right edge = max duration, Left edge = 0 (ready)
-- Returns xPos, isOverflow
local function CalculateIconX(remaining, duration)
    local s = GetSettings()
    local barWidth = s.barWidth
    local maxDur = s.maxDuration
    local iconW, iconH = GetIconDimensions()
    local reversed = (s.direction == "leftToRight")
    
    -- Check if beyond max duration (overflow)
    if remaining > maxDur then
        -- Overflow: position at the far-cooldown edge
        if reversed then
            return 0, true  -- Left edge when reversed
        else
            return barWidth - iconW, true  -- Right edge normally
        end
    end
    
    -- Usable width (bar width minus icon width so icon stays within bounds)
    local usableWidth = barWidth - iconW
    
    -- Calculate position ratio (0 = ready, 1 = max duration)
    local ratio = remaining / maxDur
    
    -- Default: ready on left (0), longest on right (usableWidth)
    -- Reversed: ready on right (usableWidth), longest on left (0)
    local xPos
    if reversed then
        xPos = (1 - ratio) * usableWidth
    else
        xPos = ratio * usableWidth
    end
    
    return xPos, false
end

-- Format duration for display
local function FormatDuration(seconds)
    if seconds <= 0 then
        return ""
    elseif seconds < 10 then
        return string.format("%.1f", seconds)
    elseif seconds < 60 then
        return string.format("%d", math.floor(seconds))
    else
        local mins = math.floor(seconds / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%d:%02d", mins, secs)
    end
end

-- ============================================================================
-- ICON UPDATE
-- ============================================================================

local function UpdateIcon(icon, spellID, spellData, remaining, duration)
    if not icon or not spellID then return end
    
    local s = GetSettings()
    local iconW, iconH = GetIconDimensions()
    
    -- Set texture if needed
    if icon.spellID ~= spellID then
        icon.spellID = spellID
        icon.texture:SetTexture(spellData.icon)
        UpdateIconAppearance(icon)
    end
    
    -- Calculate position
    local targetX, isOverflow = CalculateIconX(remaining, duration)
    icon.targetX = targetX
    icon.isOverflow = isOverflow
    
    -- Calculate Y position with vertical offset
    -- Base: icons sit with their bottom edge on the bar
    -- iconVerticalOffset: 0 = on bar, positive = above, negative = below
    local baseY = s.barHeight + 2  -- Just above the bar
    local yOffset = baseY + s.iconVerticalOffset
    
    -- Position icon
    icon:ClearAllPoints()
    icon:SetPoint("BOTTOMLEFT", timelineFrame.bar, "BOTTOMLEFT", targetX, yOffset)
    
    -- Update duration text
    if s.showCooldownText then
        icon.durationText:SetText(FormatDuration(remaining))
    else
        icon.durationText:SetText("")
    end
    
    -- Update cooldown swipe
    if remaining > 0 and duration > 0 then
        local startTime = GetTime() - (duration - remaining)
        icon.cooldown:SetCooldown(startTime, duration)
        icon.isReady = false
    else
        icon.cooldown:Clear()
        icon.isReady = true
    end
    
    icon:Show()
    
    return isOverflow
end

-- ============================================================================
-- FRAME UPDATE (OnUpdate handler)
-- ============================================================================

-- Calculate vertical offsets for overlapping icons
local function CalculateAntiOverlapOffsets(iconList, iconW, iconSpacing)
    -- Sort icons by X position
    table.sort(iconList, function(a, b)
        return a.xPos < b.xPos
    end)
    
    -- Calculate overlaps and assign vertical offsets
    local overlapThreshold = iconW + iconSpacing
    local maxRow = 0
    
    for i, data in ipairs(iconList) do
        data.row = 0  -- Start at row 0
        
        -- Check against all previous icons
        for j = i - 1, 1, -1 do
            local prevData = iconList[j]
            local xDiff = data.xPos - prevData.xPos
            
            -- If this icon overlaps with the previous one
            if xDiff < overlapThreshold then
                -- Assign to a higher row than the previous icon
                if prevData.row >= data.row then
                    data.row = prevData.row + 1
                end
            else
                -- No more overlaps possible (icons are sorted by X)
                break
            end
        end
        
        if data.row > maxRow then
            maxRow = data.row
        end
    end
    
    return maxRow
end

local function OnUpdate(self, elapsed)
    if not isEnabled then return end
    
    lastUpdate = lastUpdate + elapsed
    
    -- Use cached settings - only update when Refresh() is called
    local s = settings
    if not s or not s.updateInterval then
        -- Settings not loaded yet, try to get them
        settings = GetSettings()
        s = settings
    end
    
    if lastUpdate < (s.updateInterval or 0.033) then
        return
    end
    lastUpdate = 0
    
    -- Get current cooldown states from TimelineData
    local activeCooldowns = TimelineData:GetActiveCooldowns()
    local readySpells = TimelineData:GetReadySpells()
    
    -- Track which spells we've processed
    local processed = {}
    local iconPositions = {}  -- For anti-overlap calculation
    wipe(overflowIcons)
    
    local iconW, iconH = GetIconDimensions()
    
    -- First pass: calculate positions and acquire icons
    for spellID, data in pairs(activeCooldowns) do
        processed[spellID] = true
        
        local icon = activeIcons[spellID]
        if not icon then
            icon = AcquireIcon()
            activeIcons[spellID] = icon
        end
        
        -- Calculate position
        local targetX, isOverflow = CalculateIconX(data.remaining, data.duration)
        icon.spellID = spellID
        icon.targetX = targetX
        icon.isOverflow = isOverflow
        
        -- Set texture if needed
        if icon.texture:GetTexture() ~= data.icon then
            icon.texture:SetTexture(data.icon)
            UpdateIconAppearance(icon)
        end
        
        -- Track position for anti-overlap (exclude overflow icons)
        if not isOverflow then
            table.insert(iconPositions, {
                icon = icon,
                spellID = spellID,
                xPos = targetX,
                remaining = data.remaining,
                duration = data.duration,
                data = data,
                row = 0,
            })
        else
            -- Track overflow icons for stacking
            if s.showOverflowStack then
                table.insert(overflowIcons, { icon = icon, remaining = data.remaining, data = data })
            end
        end
        
        -- Remove from ready list if it was there
        if readyIcons[spellID] then
            readyIcons[spellID] = nil
        end
    end
    
    -- Ready spells should NOT be shown - release their icons
    for spellID, data in pairs(readySpells) do
        processed[spellID] = true
        
        local icon = activeIcons[spellID]
        if icon then
            ReleaseIcon(icon)
            activeIcons[spellID] = nil
        end
        readyIcons[spellID] = nil
    end
    
    -- Calculate anti-overlap offsets (only if enabled)
    if s.staggerOverlaps ~= false then
        CalculateAntiOverlapOffsets(iconPositions, iconW, s.iconSpacing)
    end
    
    -- Second pass: position icons with anti-overlap offsets
    -- Icons sit ABOVE the bar (anchored to TOP of bar)
    local baseY = 2 + s.iconVerticalOffset  -- Small gap above bar
    
    for _, posData in ipairs(iconPositions) do
        local icon = posData.icon
        local verticalOffset = (s.staggerOverlaps ~= false) and (posData.row * (iconH + s.iconSpacing)) or 0
        
        icon:ClearAllPoints()
        icon:SetPoint("BOTTOMLEFT", timelineFrame.bar, "TOPLEFT", posData.xPos, baseY + verticalOffset)
        
        -- Update duration text
        if s.showCooldownText then
            icon.durationText:SetText(FormatDuration(posData.remaining))
        else
            icon.durationText:SetText("")
        end
        
        -- Update cooldown swipe
        if posData.remaining > 0 and posData.duration > 0 then
            local startTime = GetTime() - (posData.duration - posData.remaining)
            icon.cooldown:SetCooldown(startTime, posData.duration)
            icon.isReady = false
        else
            icon.cooldown:Clear()
            icon.isReady = true
        end
        
        icon:Show()
    end
    
    -- Release icons for spells no longer tracked
    for spellID, icon in pairs(activeIcons) do
        if not processed[spellID] then
            ReleaseIcon(icon)
            activeIcons[spellID] = nil
            readyIcons[spellID] = nil
        end
    end
    
    -- Stack overflow icons (sorted by remaining time, stacked vertically)
    if #overflowIcons > 0 then
        -- Sort by remaining time (shortest first = bottom of stack)
        table.sort(overflowIcons, function(a, b)
            return a.remaining < b.remaining
        end)
        
        local barWidth = s.barWidth
        local reversed = (s.direction == "leftToRight")
        local baseX = reversed and 0 or (barWidth - iconW)
        
        for i, data in ipairs(overflowIcons) do
            local icon = data.icon
            local stackOffset = (i - 1) * (iconH + s.iconSpacing)
            
            icon:ClearAllPoints()
            icon:SetPoint("BOTTOMLEFT", timelineFrame.bar, "TOPLEFT", baseX, baseY + stackOffset)
            
            -- Update duration text
            if s.showCooldownText then
                icon.durationText:SetText(FormatDuration(data.remaining))
            else
                icon.durationText:SetText("")
            end
            
            -- Update cooldown swipe
            if data.remaining > 0 then
                local startTime = GetTime() - (data.data.duration - data.remaining)
                icon.cooldown:SetCooldown(startTime, data.data.duration)
            end
            
            icon:Show()
        end
    end
end

-- ============================================================================
-- MAIN FRAME CREATION
-- ============================================================================

-- Save position to database
local function SavePosition()
    if not timelineFrame then return end
    
    local point, _, relPoint, x, y = timelineFrame:GetPoint(1)
    local position = {
        point = point,
        relPoint = relPoint,
        x = x,
        y = y,
    }
    
    if TUICD.TimelineUI and TUICD.TimelineUI.SetSetting then
        TUICD.TimelineUI:SetSetting("position", position)
    end
    
    dprint(string.format("Position saved: %s, %d, %d", point, math.floor(x), math.floor(y)))
end

-- Restore position from database
local function RestorePosition()
    if not timelineFrame then return end
    
    local position = GetSettingValue("position")
    if position and position.point then
        timelineFrame:ClearAllPoints()
        timelineFrame:SetPoint(position.point, UIParent, position.relPoint or position.point, position.x or 0, position.y or 0)
        dprint(string.format("Position restored: %s, %d, %d", position.point, math.floor(position.x or 0), math.floor(position.y or 0)))
    end
end

local function CreateTimelineFrame()
    if timelineFrame then 
        return timelineFrame 
    end
    
    local s = GetSettings()
    local iconW, iconH = GetIconDimensions()
    local padding = s.backgroundPadding or 4
    
    -- Frame layout: icons above bar, bar at bottom
    -- Content height = icons + small gap + bar
    local contentHeight = iconH + 4 + s.barHeight
    local frameHeight = contentHeight + padding * 2
    
    -- Main container
    timelineFrame = CreateFrame("Frame", "TUICD_TimelineFrame", UIParent, "BackdropTemplate")
    timelineFrame:SetSize(s.barWidth + padding * 2, frameHeight)
    timelineFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    timelineFrame:SetFrameStrata("MEDIUM")
    timelineFrame:SetFrameLevel(10)
    
    -- Background fills the entire frame
    timelineFrame.background = timelineFrame:CreateTexture(nil, "BACKGROUND")
    timelineFrame.background:SetAllPoints()
    
    local bgColor = s.backgroundColor or { r = 0, g = 0, b = 0, a = 0.5 }
    timelineFrame.background:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    timelineFrame.background:SetShown(s.showBackground)
    
    -- Make frame setup (movement handled by Layout Mode only)
    timelineFrame:SetMovable(true)
    timelineFrame:EnableMouse(false)  -- Disabled by default, Layout Mode enables it
    timelineFrame:SetClampedToScreen(true)
    -- Note: Drag scripts removed - movement only through Layout Mode
    
    -- Timeline bar - centered both horizontally and vertically in frame
    timelineFrame.bar = CreateFrame("Frame", nil, timelineFrame, "BackdropTemplate")
    timelineFrame.bar:SetSize(s.barWidth, s.barHeight)
    timelineFrame.bar:ClearAllPoints()
    timelineFrame.bar:SetPoint("CENTER", timelineFrame, "CENTER", 0, 0)
    
    -- Simple line style
    local barColor = s.barColor or { r = 0.4, g = 0.4, b = 0.4, a = 0.9 }
    timelineFrame.bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    timelineFrame.bar:SetBackdropColor(barColor.r, barColor.g, barColor.b, barColor.a)
    
    -- OnUpdate for animation
    timelineFrame:SetScript("OnUpdate", OnUpdate)
    
    -- Restore saved position
    RestorePosition()
    
    dprint("Timeline frame created")
    return timelineFrame
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function TimelineFrames:Initialize()
    -- Get settings from database (should have user's saved values)
    settings = GetSettings()
    
    -- Create the frame with these settings
    CreateTimelineFrame()
    
    -- Frame should be hidden by default - only shown when Enable() is called
    if timelineFrame then
        timelineFrame:Hide()
    end
    
    -- Register with Layout system (deferred to ensure Layout is ready)
    C_Timer.After(0.1, function()
        self:RegisterWithLayout()
    end)
end

function TimelineFrames:Enable()
    if not timelineFrame then
        self:Initialize()
    end
    
    -- Refresh settings before showing (ensures we have latest from database)
    settings = GetSettings()
    self:Refresh()
    
    isEnabled = true
    
    -- Register visibility events
    self:RegisterVisibilityEvents()
    
    -- Check visibility before showing
    self:UpdateVisibility()
end

function TimelineFrames:Disable()
    isEnabled = false
    
    -- Unregister visibility events
    self:UnregisterVisibilityEvents()
    
    -- Release all icons
    for spellID, icon in pairs(activeIcons) do
        ReleaseIcon(icon)
    end
    wipe(activeIcons)
    wipe(readyIcons)
    wipe(overflowIcons)
    
    if timelineFrame then
        timelineFrame:Hide()
    end
    dprint("TimelineFrames disabled")
end

function TimelineFrames:IsEnabled()
    return isEnabled
end

function TimelineFrames:Toggle()
    if isEnabled then
        self:Disable()
    else
        self:Enable()
    end
end

function TimelineFrames:GetFrame()
    return timelineFrame
end

-- Refresh icon sizes/positions (call after settings change)
function TimelineFrames:Refresh()
    settings = GetSettings()
    
    if timelineFrame then
        local s = settings
        local iconW, iconH = GetIconDimensions()
        local padding = s.backgroundPadding or 4
        
        -- Frame layout: icons above bar, bar at bottom
        local contentHeight = iconH + 4 + s.barHeight
        local frameHeight = contentHeight + padding * 2
        
        -- Update main frame size (includes padding for background)
        timelineFrame:SetSize(s.barWidth + padding * 2, frameHeight)
        
        -- Update bar size and position (centered both horizontally and vertically)
        timelineFrame.bar:SetSize(s.barWidth, s.barHeight)
        timelineFrame.bar:ClearAllPoints()
        timelineFrame.bar:SetPoint("CENTER", timelineFrame, "CENTER", 0, 0)
        
        -- Update background (fills entire frame)
        if timelineFrame.background then
            local bgColor = s.backgroundColor or { r = 0, g = 0, b = 0, a = 0.5 }
            timelineFrame.background:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
            timelineFrame.background:ClearAllPoints()
            timelineFrame.background:SetAllPoints()
            timelineFrame.background:SetShown(s.showBackground)
        end
        
        -- Update bar color
        local barColor = s.barColor or { r = 0.4, g = 0.4, b = 0.4, a = 0.9 }
        timelineFrame.bar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        timelineFrame.bar:SetBackdropColor(barColor.r, barColor.g, barColor.b, barColor.a)
        
        -- Update all icons in pool
        for _, icon in ipairs(iconPool) do
            UpdateIconAppearance(icon)
        end
        
        -- Force immediate position update
        lastUpdate = 999
    end
end

-- Force update (for testing)
function TimelineFrames:ForceUpdate()
    if timelineFrame and isEnabled then
        lastUpdate = 999  -- Force immediate update
        OnUpdate(timelineFrame, 0)
    end
end

-- ============================================================================
-- LAYOUT MODE INTEGRATION
-- ============================================================================

local layoutWrapper = nil
local isRegisteredWithLayout = false

-- Create a TUIFrame-compatible wrapper for Layout Mode
local function CreateLayoutWrapper()
    if not timelineFrame then return nil end
    
    local wrapper = {
        id = "Timeline",
        name = "Cooldown Timeline",
        category = "Cooldowns",
        frame = timelineFrame,
        defaultPosition = {
            point = "CENTER",
            x = 0,
            y = -150,
        },
        
        onPositionChanged = function(self, point, relFrame, relPoint, x, y)
            if not timelineFrame then return end
            timelineFrame:ClearAllPoints()
            timelineFrame:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
            -- Save to database
            SavePosition()
        end,
        
        -- TUIFrame API
        GetPosition = function(self)
            if not timelineFrame then return nil end
            local point, relTo, relPoint, x, y = timelineFrame:GetPoint(1)
            return { point = point, relFrame = relTo, relPoint = relPoint, x = x, y = y }
        end,
        
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            if not timelineFrame then return end
            timelineFrame:ClearAllPoints()
            timelineFrame:SetPoint(point, relFrame or UIParent, relPoint or point, x or 0, y or 0)
            if self.onPositionChanged then
                self:onPositionChanged(point, relFrame, relPoint, x, y)
            end
        end,
        
        ResetPosition = function(self)
            if not timelineFrame then return end
            local def = self.defaultPosition
            timelineFrame:ClearAllPoints()
            timelineFrame:SetPoint(def.point, UIParent, def.point, def.x, def.y)
            SavePosition()
        end,
        
        -- Layout system required methods
        GetSaveData = function(self)
            if not timelineFrame then
                return { point = "CENTER", x = 0, y = -150, scale = 1 }
            end
            local left = timelineFrame:GetLeft()
            local bottom = timelineFrame:GetBottom()
            if not left or not bottom then
                local point, _, _, x, y = timelineFrame:GetPoint(1)
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
        
        LoadSaveData = function(self, data)
            if not data or not timelineFrame then return end
            local point = data.point or "CENTER"
            self:SetPosition(point, UIParent, point, data.x, data.y)
            if data.scale then
                self:SetScale(data.scale)
            end
        end,
        
        SetScale = function(self, scale)
            if timelineFrame and scale then
                timelineFrame:SetScale(scale)
            end
        end,
        
        GetScale = function(self)
            return timelineFrame and timelineFrame:GetScale() or 1
        end,
        
        GetSize = function(self)
            if timelineFrame then
                return timelineFrame:GetSize()
            end
            return 0, 0
        end,
        
        Show = function(self)
            if timelineFrame then timelineFrame:Show() end
        end,
        
        Hide = function(self)
            if timelineFrame then timelineFrame:Hide() end
        end,
        
        IsShown = function(self)
            return timelineFrame and timelineFrame:IsShown()
        end,
        
        GetFrame = function(self)
            return timelineFrame
        end,
    }
    
    return wrapper
end

-- Register with Layout system
function TimelineFrames:RegisterWithLayout()
    local Layout = TUICD.Layout
    if not Layout or not Layout.RegisterElement then
        dprint("Layout system not available")
        return false
    end
    
    if isRegisteredWithLayout then
        dprint("Already registered with Layout")
        return true
    end
    
    if not timelineFrame then
        dprint("Timeline frame not created yet")
        return false
    end
    
    layoutWrapper = CreateLayoutWrapper()
    if not layoutWrapper then
        dprint("Failed to create layout wrapper")
        return false
    end
    
    -- Register with FlyPaper if available
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    if FlyPaper then
        FlyPaper.AddFrame("TUICD", "Timeline", timelineFrame)
    end
    
    -- Register with Layout
    Layout:RegisterElement("Timeline", {
        name = "Cooldown Timeline",
        category = "Cooldowns",
        tuiFrame = layoutWrapper,
        defaultPosition = layoutWrapper.defaultPosition,
    })
    
    isRegisteredWithLayout = true
    dprint("Registered Timeline with Layout system")
    return true
end

-- Unregister from Layout system
function TimelineFrames:UnregisterFromLayout()
    if not isRegisteredWithLayout then return end
    
    local Layout = TUICD.Layout
    if Layout and Layout.UnregisterElement then
        Layout:UnregisterElement("Timeline")
    end
    
    -- Remove from FlyPaper
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    if FlyPaper and FlyPaper.RemoveFrame then
        FlyPaper.RemoveFrame("TUICD", "Timeline")
    end
    
    layoutWrapper = nil
    isRegisteredWithLayout = false
    dprint("Unregistered Timeline from Layout system")
end

-- Get the layout wrapper (for external use)
function TimelineFrames:GetLayoutWrapper()
    return layoutWrapper
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

-- Check if timeline should be visible based on visibility conditions
function TimelineFrames:ShouldBeVisible()
    -- Must be enabled first
    if not isEnabled then
        return false
    end
    
    -- Force all visible mode bypasses all visibility conditions
    if TUICD.forceAllVisible then
        return true
    end
    
    -- Always show in Edit Mode / Layout Mode for positioning
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return true
    end
    
    -- Check layout mode
    local Layout = TUICD.Layout
    if Layout and Layout.IsUnlocked and Layout:IsUnlocked() then
        return true
    end
    
    local s = settings or GetSettings()
    local enabled = s.visibilityEnabled
    if not enabled then
        return true  -- Visibility system disabled = always show
    end
    
    local state = GetPlayerState()
    
    -- OR logic: if ANY checked condition is true, show
    if state.inCombat and s.showInCombat then return true end
    if not state.inCombat and s.showOutOfCombat then return true end
    if state.isSolo and s.showSolo then return true end
    if state.inGroup and not state.inRaid and s.showInParty then return true end
    if state.inRaid and s.showInRaid then return true end
    if state.inDungeon and s.showInDungeon then return true end
    if state.inDelve and s.showInDelve then return true end
    if state.inArena and s.showInArena then return true end
    if state.inBattleground and s.showInBattleground then return true end
    if state.hasTarget and s.showHasTarget then return true end
    if not state.hasTarget and s.showNoTarget then return true end
    if state.isMounted and s.showMounted then return true end
    if not state.isMounted and s.showNotMounted then return true end
    
    -- No conditions matched
    return false
end

-- Update timeline visibility based on current conditions
function TimelineFrames:UpdateVisibility()
    if not timelineFrame then return end
    
    -- Refresh settings
    settings = GetSettings()
    
    local shouldShow = self:ShouldBeVisible()
    
    if shouldShow then
        timelineFrame:Show()
    else
        timelineFrame:Hide()
    end
end

-- Register for visibility-related events
function TimelineFrames:RegisterVisibilityEvents()
    if not visibilityEventFrame then
        visibilityEventFrame = CreateFrame("Frame")
        visibilityEventFrame:SetScript("OnEvent", function(_, event, ...)
            -- Throttle updates slightly
            C_Timer.After(0.05, function()
                TimelineFrames:UpdateVisibility()
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
function TimelineFrames:UnregisterVisibilityEvents()
    if visibilityEventFrame then
        visibilityEventFrame:UnregisterAllEvents()
    end
end

-- ============================================================================
-- RETURN
-- ============================================================================

return TimelineFrames
