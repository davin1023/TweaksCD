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
    showHashMarks = true,       -- Show time marker lines on the bar
    hashMarkColor = { r = 0.6, g = 0.6, b = 0.6, a = 0.5 },
    
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
    
    -- On-Ready Glow
    onReadyGlowEnabled = false,
    onReadyGlowStyle = "pixel",
    onReadyGlowColorR = 1.0,
    onReadyGlowColorG = 0.82,
    onReadyGlowColorB = 0.0,
    onReadyGlowSpeed = 0.6,
    onReadyGlowIntensity = 0.8,
    onReadyGlowThickness = 2,
    onReadyGlowScale = 1.0,
    onReadyGlowDuration = 3.0,
    onReadyGlowTiming = 0,
    
    -- On-Ready Pulse
    onReadyPulseEnabled = false,
    onReadyPulseScale = 1.3,
    onReadyPulseDuration = 0.4,
    onReadyPulseCount = 3,
    onReadyPulseTiming = 0,
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

-- On-Ready effect state
local wasOnCooldown = {}      -- { [spellID] = true } tracks spells that were on CD
local onReadyHolding = {}     -- { [spellID] = { holdUntil, icon, data, glowActive, pulseActive, pulsesPlayed } }

-- Sticky CD state: once a spell is confirmed on CD, it stays "on CD" until
-- the Duration Object says remaining is 0 (via Format returning non-secret).
-- This prevents the debounce in IsRealCooldownActive from flickering icons
-- on every GCD pulse. Same pattern as bars (event-driven state, frame-driven render).
local spellOnCD = {}          -- { [spellID] = true } sticky "is on real cooldown" flag

-- Forward declarations for on-ready effect helpers (defined later, called from ReleaseIcon)
local CleanupOnReadyEffects

-- Debug
local debugMode = false
local function dprint(...)
    if debugMode then
        print("|cff00ccff[TL-Frames]|r", ...)
    end
end

-- Secret value detection
local IsSecret = issecretvalue or function() return false end

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
    
    -- Position StatusBar: invisible bar spanning timeline width.
    -- SetValue(remaining) positions the fill edge, icon follows it.
    -- This accepts secret values from Duration Objects (same tech as timer bars).
    if timelineFrame and timelineFrame.bar then
        local baseY = 2 + (s.iconVerticalOffset or 0)
        icon.posBar = CreateFrame("StatusBar", nil, timelineFrame)
        icon.posBar:SetPoint("LEFT", timelineFrame.bar, "TOPLEFT", 0, baseY + iconH / 2)
        icon.posBar:SetPoint("RIGHT", timelineFrame.bar, "TOPRIGHT", 0, baseY + iconH / 2)
        icon.posBar:SetHeight(20)  -- DEBUG: tall enough to see
        icon.posBar:SetMinMaxValues(0, s.maxDuration or 120)
        icon.posBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        icon.posBar:SetStatusBarColor(1, 0, 0, 0.5)  -- DEBUG: visible red
        icon.posBar:SetValue(0)
        icon.posBar:SetFrameLevel(timelineFrame.bar:GetFrameLevel() + 1)
        
        -- For reversed direction (ready on right), reverse the fill
        if s.direction == "leftToRight" then
            pcall(function()
                if icon.posBar.SetReverseFill then
                    icon.posBar:SetReverseFill(true)
                elseif icon.posBar.SetFillStyle then
                    if Enum and Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Reverse then
                        icon.posBar:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
                    else
                        icon.posBar:SetFillStyle("REVERSE")
                    end
                end
            end)
        end
        
        -- DEBUG: Do NOT anchor icon to fill texture (testing secret anchor theory)
        -- Instead anchor icon to a fixed spot on the bar so we can see if it renders
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", timelineFrame.bar, "CENTER", 0, baseY + iconH / 2)
        
        icon.posBarActive = true
    end

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
    CleanupOnReadyEffects(icon)
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

-- ============================================================================
-- ON-READY EFFECTS: Glow and Pulse helpers
-- ============================================================================

-- Pixel glow: animated colored border
local function ShowPixelGlow(icon, r, g, b, thickness, intensity, speed)
    if not icon._pixelGlow then
        local gf = CreateFrame("Frame", nil, icon, "BackdropTemplate")
        gf:SetFrameLevel(icon:GetFrameLevel() + 5)
        
        local ag = gf:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local alpha = ag:CreateAnimation("Alpha")
        alpha:SetSmoothing("IN_OUT")
        gf._pulseAG = ag
        gf._pulseAlpha = alpha
        
        icon._pixelGlow = gf
    end
    
    local t = math.max(1, math.floor(thickness or 2))
    local gf = icon._pixelGlow
    gf:ClearAllPoints()
    gf:SetPoint("TOPLEFT", -t, t)
    gf:SetPoint("BOTTOMRIGHT", t, -t)
    gf:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = t })
    gf:SetBackdropBorderColor(r, g, b, intensity)
    
    gf._pulseAlpha:SetFromAlpha(intensity)
    gf._pulseAlpha:SetToAlpha(math.max(0.05, intensity * 0.2))
    gf._pulseAlpha:SetDuration(speed or 0.6)
    
    gf:Show()
    gf._pulseAG:Stop()
    gf._pulseAG:Play()
end

-- Shine glow: colored flash overlay
local function ShowShineGlow(icon, r, g, b, intensity, speed)
    if not icon._shineGlow then
        local shine = icon:CreateTexture(nil, "OVERLAY")
        shine:SetAllPoints()
        shine:SetBlendMode("ADD")
        shine:SetDrawLayer("OVERLAY", 6)
        
        local ag = shine:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local alpha = ag:CreateAnimation("Alpha")
        alpha:SetSmoothing("IN_OUT")
        shine._pulseAG = ag
        shine._pulseAlpha = alpha
        
        icon._shineGlow = shine
    end
    
    icon._shineGlow:SetColorTexture(r, g, b, intensity)
    icon._shineGlow._pulseAlpha:SetFromAlpha(intensity)
    icon._shineGlow._pulseAlpha:SetToAlpha(math.max(0.02, intensity * 0.1))
    icon._shineGlow._pulseAlpha:SetDuration(speed or 0.6)
    
    icon._shineGlow:Show()
    icon._shineGlow._pulseAG:Stop()
    icon._shineGlow._pulseAG:Play()
end

-- Spell activation glow: radiant edges + spinning ants
local function ShowSpellGlow(icon, r, g, b, glowScale, speed)
    if not icon._spellGlow then
        local glow = CreateFrame("Frame", nil, icon)
        glow:SetFrameLevel(icon:GetFrameLevel() + 5)
        
        local inner = glow:CreateTexture(nil, "ARTWORK")
        inner:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        inner:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
        inner:SetBlendMode("ADD")
        inner:SetDrawLayer("ARTWORK", 1)
        glow._inner = inner
        
        local outer = glow:CreateTexture(nil, "ARTWORK")
        outer:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        outer:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
        outer:SetBlendMode("ADD")
        outer:SetDrawLayer("ARTWORK", 0)
        glow._outer = outer
        
        local ants = glow:CreateTexture(nil, "OVERLAY")
        ants:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
        ants:SetBlendMode("ADD")
        ants:SetDrawLayer("OVERLAY", 5)
        glow._ants = ants
        
        local antsAG = ants:CreateAnimationGroup()
        antsAG:SetLooping("REPEAT")
        local rot = antsAG:CreateAnimation("Rotation")
        rot:SetDegrees(-360)
        rot:SetDuration(12)
        glow._antsAG = antsAG
        
        local pulseAG = glow:CreateAnimationGroup()
        pulseAG:SetLooping("BOUNCE")
        local alpha = pulseAG:CreateAnimation("Alpha")
        alpha:SetFromAlpha(1)
        alpha:SetToAlpha(0.5)
        alpha:SetSmoothing("IN_OUT")
        glow._pulseAG = pulseAG
        glow._pulseAlpha = alpha
        
        icon._spellGlow = glow
    end
    
    local glow = icon._spellGlow
    local scale = glowScale or 1.0
    -- Don't use icon:GetSize() — returns secrets due to secret anchors from posBar
    local w, h = GetIconDimensions()
    local pad = (w * 0.4) * scale
    
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    
    glow._inner:SetAllPoints(glow)
    glow._outer:SetAllPoints(glow)
    glow._ants:SetAllPoints(glow)
    
    glow._inner:SetVertexColor(r, g, b, 1)
    glow._outer:SetVertexColor(r, g, b, 0.6)
    glow._ants:SetVertexColor(r, g, b, 0.7)
    
    glow._pulseAlpha:SetDuration(speed or 0.8)
    
    glow:Show()
    glow._antsAG:Play()
    glow._pulseAG:Stop()
    glow._pulseAG:Play()
end

-- Show the appropriate glow style based on settings
local function ShowOnReadyGlow(icon, s)
    local style = s.onReadyGlowStyle or "pixel"
    local r = s.onReadyGlowColorR or 1.0
    local g = s.onReadyGlowColorG or 0.82
    local b = s.onReadyGlowColorB or 0.0
    local speed = s.onReadyGlowSpeed or 0.6
    local intensity = s.onReadyGlowIntensity or 0.8
    local thickness = s.onReadyGlowThickness or 2
    local glowScale = s.onReadyGlowScale or 1.0
    
    -- Hide other glow types first
    if style ~= "pixel" and icon._pixelGlow then icon._pixelGlow:Hide() end
    if style ~= "shine" and icon._shineGlow then icon._shineGlow:Hide() end
    if style ~= "glow" and icon._spellGlow then icon._spellGlow:Hide() end
    
    if style == "pixel" then
        ShowPixelGlow(icon, r, g, b, thickness, intensity, speed)
    elseif style == "shine" then
        ShowShineGlow(icon, r, g, b, intensity, speed)
    else
        ShowSpellGlow(icon, r, g, b, glowScale, speed)
    end
end

-- Hide all glow types from an icon
local function HideOnReadyGlow(icon)
    if icon._pixelGlow then
        if icon._pixelGlow._pulseAG then icon._pixelGlow._pulseAG:Stop() end
        icon._pixelGlow:Hide()
    end
    if icon._shineGlow then
        if icon._shineGlow._pulseAG then icon._shineGlow._pulseAG:Stop() end
        icon._shineGlow:Hide()
    end
    if icon._spellGlow then
        if icon._spellGlow._pulseAG then icon._spellGlow._pulseAG:Stop() end
        if icon._spellGlow._antsAG then icon._spellGlow._antsAG:Stop() end
        icon._spellGlow:Hide()
    end
end

-- Play a scale-bounce pulse animation on an icon
local function PlayPulseAnimation(icon, pulseScale, pulseDuration, onFinish)
    if not icon._pulseAG then
        local ag = icon:CreateAnimationGroup()
        
        local scaleUp = ag:CreateAnimation("Scale")
        scaleUp:SetOrigin("CENTER", 0, 0)
        scaleUp:SetOrder(1)
        scaleUp:SetSmoothing("OUT")
        ag._scaleUp = scaleUp
        
        local scaleDown = ag:CreateAnimation("Scale")
        scaleDown:SetOrigin("CENTER", 0, 0)
        scaleDown:SetOrder(2)
        scaleDown:SetSmoothing("IN")
        ag._scaleDown = scaleDown
        
        icon._pulseAG = ag
    end
    
    local halfDur = (pulseDuration or 0.4) / 2
    local s = pulseScale or 1.3
    
    icon._pulseAG._scaleUp:SetScaleFrom(1, 1)
    icon._pulseAG._scaleUp:SetScaleTo(s, s)
    icon._pulseAG._scaleUp:SetDuration(halfDur)
    
    icon._pulseAG._scaleDown:SetScaleFrom(s, s)
    icon._pulseAG._scaleDown:SetScaleTo(1, 1)
    icon._pulseAG._scaleDown:SetDuration(halfDur)
    
    if onFinish then
        icon._pulseAG:SetScript("OnFinished", onFinish)
    end
    
    icon._pulseAG:Stop()
    icon._pulseAG:Play()
end

-- Stop pulse animation
local function StopPulseAnimation(icon)
    if icon._pulseAG then
        icon._pulseAG:Stop()
        icon._pulseAG:SetScript("OnFinished", nil)
    end
end

-- Clean up all on-ready effects from an icon before release
CleanupOnReadyEffects = function(icon)
    HideOnReadyGlow(icon)
    StopPulseAnimation(icon)
end

-- ============================================================================
-- PASS-THROUGH RENDERING (no event-driven state, no debounce)
-- 
-- Problem solved: Event-driven + debounce fails because SPELL_UPDATE_COOLDOWN
-- fires at GCD start when ALL Duration Objects ARE active. After 2s debounce,
-- everything gets permanently marked as real CD.
--
-- Solution: Poll every frame. Use Midnight's native APIs:
--   1. TruncateWhenZero(remaining) → "" means idle (remaining=0), secret means ticking
--   2. SetAlphaFromBoolean(isOnGCD, 0, 1) → hides GCD-only, shows real CDs
--   3. posBar:SetValue(remaining) → positions icon (secret-safe)
-- No detection, no debounce, no cache, no event frame.
-- ============================================================================

local function OnUpdate(self, elapsed)
    if not isEnabled then return end
    
    lastUpdate = lastUpdate + elapsed
    local s = settings
    if not s or not s.updateInterval then
        settings = GetSettings()
        s = settings
    end
    if lastUpdate < (s.updateInterval or 0.033) then return end
    lastUpdate = 0
    
    local trackedSpells = TimelineData and TimelineData:GetTrackedSpells()
    if not trackedSpells then return end
    
    local maxDur = s.maxDuration or 120
    local now = GetTime()
    local inCombat = InCombatLockdown()
    local processed = {}
    
    -- On-ready settings
    local glowEnabled = s.onReadyGlowEnabled
    local pulseEnabled = s.onReadyPulseEnabled
    local anyOnReadyEnabled = glowEnabled or pulseEnabled
    
    for spellID, spellData in pairs(trackedSpells) do
        processed[spellID] = true
        
        -- Acquire/reuse icon
        local icon = activeIcons[spellID]
        if not icon then
            icon = AcquireIcon()
            activeIcons[spellID] = icon
        end
        
        -- Set texture if needed
        if icon.spellID ~= spellID then
            icon.spellID = spellID
            icon.texture:SetTexture(spellData.icon)
            UpdateIconAppearance(icon)
        end
        
        -- Get Duration Object + cooldown info
        local dObj, cdInfo
        pcall(function()
            if C_Spell then
                if C_Spell.GetSpellCooldownDuration then
                    dObj = C_Spell.GetSpellCooldownDuration(spellID)
                end
                if C_Spell.GetSpellCooldown then
                    cdInfo = C_Spell.GetSpellCooldown(spellID)
                end
            end
        end)
        
        if not dObj or not icon.posBar then
            -- No data available
            if not onReadyHolding[spellID] then
                icon:Hide()
            end
            wasOnCooldown[spellID] = nil
        else
            -- Step 1: Check if anything is ticking (idle filter)
            -- TruncateWhenZero returns "" for 0, secret string for > 0
            local isTicking = false
            pcall(function()
                local remaining = dObj:GetRemainingDuration()
                if C_StringUtil and C_StringUtil.TruncateWhenZero then
                    local str = C_StringUtil.TruncateWhenZero(remaining)
                    -- If result is secret → remaining > 0 → something is ticking
                    -- If result is non-secret → remaining was 0 → idle
                    if issecretvalue and issecretvalue(str) then
                        isTicking = true
                    elseif str ~= "" then
                        -- Non-secret non-empty string (out of combat, remaining > 0)
                        isTicking = true
                    end
                else
                    -- Fallback: if remaining is non-nil and non-zero
                    if remaining and remaining ~= 0 then
                        isTicking = true
                    end
                end
            end)
            
            if not isTicking then
                -- IDLE: nothing on cooldown
                -- On-ready effects
                if wasOnCooldown[spellID] and anyOnReadyEnabled and not onReadyHolding[spellID] and not inCombat then
                    local holdDuration = 0
                    if glowEnabled then
                        holdDuration = math.max(holdDuration, (s.onReadyGlowDuration or 3.0) + math.max(0, s.onReadyGlowTiming or 0))
                    end
                    if pulseEnabled then
                        holdDuration = math.max(holdDuration, (s.onReadyPulseCount or 3) * (s.onReadyPulseDuration or 0.4) + math.max(0, s.onReadyPulseTiming or 0))
                    end
                    onReadyHolding[spellID] = {
                        holdUntil = now + holdDuration, startTime = now, icon = icon, data = spellData,
                        glowStarted = false, pulseStarted = false, pulsesPlayed = 0,
                    }
                    icon:SetAlpha(1)
                    icon:Show()
                elseif onReadyHolding[spellID] then
                    icon:SetAlpha(1)
                    icon:Show()
                else
                    icon:Hide()
                end
                wasOnCooldown[spellID] = nil
            else
                -- TICKING: something is on cooldown (real CD or GCD)
                
                -- Step 2: GCD filter via SetAlphaFromBoolean
                -- isOnGCD is secret bool in combat. SetAlphaFromBoolean handles it natively.
                -- isOnGCD=true → alpha=0 (hide GCD-only), isOnGCD=false → alpha=1 (show real CD)
                -- CRITICAL: Do NOT check "isOnGCD ~= nil" — secret_bool ~= nil returns false
                -- in Midnight (different types comparison). Just try SetAlphaFromBoolean directly.
                local gcdFiltered = false
                if cdInfo then
                    -- Try SetAlphaFromBoolean first (handles secret booleans natively)
                    pcall(function()
                        if icon.SetAlphaFromBoolean and cdInfo.isOnGCD then
                            icon:SetAlphaFromBoolean(cdInfo.isOnGCD, 0, 1)
                            gcdFiltered = true
                        end
                    end)
                    
                    -- Fallback: non-secret check
                    if not gcdFiltered and cdInfo.isOnGCD then
                        if not (issecretvalue and issecretvalue(cdInfo.isOnGCD)) then
                            if cdInfo.isOnGCD == true then
                                icon:SetAlpha(0)
                                gcdFiltered = true
                            else
                                icon:SetAlpha(1)
                                gcdFiltered = true
                            end
                        end
                    end
                end
                
                if not gcdFiltered then
                    -- No GCD filter available — show everything
                    icon:SetAlpha(1)
                end
                
                -- Step 3: Position via posBar (secret-safe)
                pcall(function()
                    icon.posBar:SetMinMaxValues(0, maxDur)
                    icon.posBar:SetValue(dObj:GetRemainingDuration())
                end)
                
                -- Step 4: Cooldown swipe (secret-safe)
                pcall(function()
                    if icon.cooldown and icon.cooldown.SetCooldownFromDurationObject then
                        icon.cooldown:SetCooldownFromDurationObject(dObj)
                    end
                end)
                
                -- Step 5: Duration text (secret-safe via TruncateWhenZero)
                if s.showCooldownText then
                    pcall(function()
                        local remaining = dObj:GetRemainingDuration()
                        if C_StringUtil and C_StringUtil.TruncateWhenZero then
                            pcall(icon.durationText.SetText, icon.durationText,
                                C_StringUtil.TruncateWhenZero(remaining))
                        end
                    end)
                else
                    icon.durationText:SetText("")
                end
                
                wasOnCooldown[spellID] = true
                icon:Show()
            end
        end
    end
    
    -- Handle on-ready holding icons
    for spellID, hold in pairs(onReadyHolding) do
        if now >= hold.holdUntil then
            CleanupOnReadyEffects(hold.icon)
            hold.icon:Hide()
            onReadyHolding[spellID] = nil
        else
            local icon = hold.icon
            if glowEnabled and not hold.glowStarted then
                local glowDelay = math.max(0, s.onReadyGlowTiming or 0)
                if now >= hold.startTime + glowDelay then
                    hold.glowStarted = true
                    ShowOnReadyGlow(icon, s.onReadyGlowDuration or 3.0, s)
                end
            end
            if pulseEnabled and not hold.pulseStarted then
                local pulseDelay = math.max(0, s.onReadyPulseTiming or 0)
                if now >= hold.startTime + pulseDelay then
                    hold.pulseStarted = true
                    StartPulseAnimation(icon, s.onReadyPulseCount or 3, s.onReadyPulseDuration or 0.4)
                end
            end
        end
    end
    
    -- Release icons for spells no longer tracked
    for spellID, icon in pairs(activeIcons) do
        if not processed[spellID] then
            ReleaseIcon(icon)
            activeIcons[spellID] = nil
            wasOnCooldown[spellID] = nil
        end
    end
end


-- ============================================================================
-- POSITION SAVE/RESTORE
-- ============================================================================

local function SavePosition()
    if not timelineFrame then return end
    local point, _, relPoint, x, y = timelineFrame:GetPoint()
    if point then
        local db = TUICD.Database and TUICD.Database:GetTrackerSetting("timeline", "containerPosition")
        if not db then
            -- Save directly
            local charDB = TweaksUI_Cooldowns_CharDB
            if charDB then
                charDB.containerPositions = charDB.containerPositions or {}
                charDB.containerPositions.timeline = { point = point, x = x, y = y }
            end
        end
    end
end

local function RestorePosition()
    if not timelineFrame then return end
    local pos = nil
    if TUICD.Database and TUICD.Database.GetTrackerSetting then
        pos = TUICD.Database:GetTrackerSetting("timeline", "containerPosition")
    end
    if not pos then
        local charDB = TweaksUI_Cooldowns_CharDB
        if charDB and charDB.containerPositions and charDB.containerPositions.timeline then
            pos = charDB.containerPositions.timeline
        end
    end
    if pos and pos.point then
        timelineFrame:ClearAllPoints()
        timelineFrame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    end
end

-- ============================================================================
-- HASH MARKS (time interval tick marks on the timeline bar)
-- ============================================================================

local hashMarkPool = {}

local function UpdateHashMarks()
    if not timelineFrame or not timelineFrame.bar then return end
    
    -- Hide existing marks
    for _, mark in ipairs(hashMarkPool) do
        mark:Hide()
    end
    
    local s = GetSettings()
    if not s.showHashMarks then return end
    
    local maxDur = s.maxDuration or 120
    local barWidth = s.barWidth or 500
    local color = s.hashMarkColor or { r = 0.6, g = 0.6, b = 0.6, a = 0.5 }
    
    -- Determine interval based on max duration
    local interval
    if maxDur <= 15 then interval = 5
    elseif maxDur <= 30 then interval = 5
    elseif maxDur <= 60 then interval = 10
    elseif maxDur <= 120 then interval = 30
    else interval = 60
    end
    
    local markIndex = 0
    for t = interval, maxDur - 1, interval do
        markIndex = markIndex + 1
        local mark = hashMarkPool[markIndex]
        if not mark then
            mark = timelineFrame.bar:CreateTexture(nil, "OVERLAY")
            hashMarkPool[markIndex] = mark
        end
        
        local xFraction = t / maxDur
        local xOffset
        if s.direction == "leftToRight" then
            xOffset = xFraction * barWidth
        else
            xOffset = (1 - xFraction) * barWidth
        end
        
        mark:SetSize(1, s.barHeight or 2)
        mark:ClearAllPoints()
        mark:SetPoint("LEFT", timelineFrame.bar, "LEFT", xOffset, 0)
        mark:SetColorTexture(color.r, color.g, color.b, color.a)
        mark:Show()
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
    
    -- Create hash marks
    UpdateHashMarks()
    
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
    -- Clean up on-ready holding icons
    for spellID, hold in pairs(onReadyHolding) do
        if hold.icon then
            CleanupOnReadyEffects(hold.icon)
        end
    end
    wipe(activeIcons)
    wipe(readyIcons)
    wipe(overflowIcons)
    wipe(wasOnCooldown)
    wipe(onReadyHolding)
    
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
        
        -- Update hash marks
        UpdateHashMarks()
        
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
-- DEBUG: /tlfdbg - trace the render pipeline
-- ============================================================================
SLASH_TLFDBG1 = "/tlfdbg"
SlashCmdList["TLFDBG"] = function()
    local p = print
    p("|cff00ccff[TL:Frames]|r ===========================")
    p("isEnabled: " .. tostring(isEnabled))
    p("timelineFrame: " .. tostring(timelineFrame))
    if timelineFrame then
        p("  shown: " .. tostring(timelineFrame:IsShown()))
        if timelineFrame.bar then
            p("  bar size: " .. tostring(timelineFrame.bar:GetWidth()) .. "x" .. tostring(timelineFrame.bar:GetHeight()))
        end
    end
    p("inCombat: " .. tostring(InCombatLockdown()))
    p("SetAlphaFromBoolean exists: " .. tostring(type(CreateFrame("Frame").SetAlphaFromBoolean) == "function"))
    
    local tracked = TimelineData and TimelineData:GetTrackedSpells()
    local trackCount = 0
    if tracked then
        for _ in pairs(tracked) do trackCount = trackCount + 1 end
    end
    p("TrackedSpells: " .. trackCount)
    
    local iconCount, shownCount = 0, 0
    for sid, icon in pairs(activeIcons) do
        iconCount = iconCount + 1
        if icon:IsShown() then shownCount = shownCount + 1 end
    end
    p("activeIcons: " .. iconCount .. " (" .. shownCount .. " shown)")
    
    if tracked then
        for spellID, data in pairs(tracked) do
            local icon = activeIcons[spellID]
            local line = "  " .. spellID .. " " .. (data.name or "?") .. ": "
            
            -- Check isTicking
            local isTicking = false
            local isGCD = "?"
            pcall(function()
                if C_Spell and C_Spell.GetSpellCooldownDuration then
                    local dObj = C_Spell.GetSpellCooldownDuration(spellID)
                    if dObj then
                        local rem = dObj:GetRemainingDuration()
                        if C_StringUtil and C_StringUtil.TruncateWhenZero then
                            local str = C_StringUtil.TruncateWhenZero(rem)
                            if issecretvalue and issecretvalue(str) then
                                isTicking = true
                            elseif str ~= "" then
                                isTicking = true
                            end
                        end
                    end
                end
                if C_Spell and C_Spell.GetSpellCooldown then
                    local cdInfo = C_Spell.GetSpellCooldown(spellID)
                    if cdInfo then
                        local gcd = cdInfo.isOnGCD
                        if gcd == nil then
                            isGCD = "nil"
                        elseif issecretvalue and issecretvalue(gcd) then
                            isGCD = "SECRET"
                        else
                            isGCD = tostring(gcd)
                        end
                    else
                        isGCD = "noInfo"
                    end
                end
            end)
            
            line = line .. "tick=" .. tostring(isTicking) .. " gcd=" .. isGCD
            
            if icon then
                local shown = icon:IsShown() and "Y" or "N"
                local alpha = "?"
                pcall(function()
                    local a = icon:GetAlpha()
                    if issecretvalue and issecretvalue(a) then
                        alpha = "SECRET"
                    else
                        alpha = string.format("%.1f", a)
                    end
                end)
                line = line .. " shown=" .. shown .. " a=" .. alpha
                if icon.posBar then
                    local valStr = "?"
                    pcall(function()
                        local v = icon.posBar:GetValue()
                        if issecretvalue and issecretvalue(v) then
                            valStr = "SECRET"
                        else
                            valStr = string.format("%.1f", v)
                        end
                    end)
                    line = line .. " val=" .. valStr
                else
                    line = line .. " noBar!"
                end
            else
                line = line .. " (no icon)"
            end
            
            p(line)
        end
    end
    p("|cff00ccff[TL:Frames]|r ===========================")
end

-- ============================================================================
-- RETURN
-- ============================================================================

return TimelineFrames
