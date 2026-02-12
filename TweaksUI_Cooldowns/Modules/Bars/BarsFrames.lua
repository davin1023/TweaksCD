-- ============================================================================
-- TUICD: Timer Bars - Frame Layer
-- Each tracked spell gets its own independent timer bar frame
-- Bars are standalone, draggable, and persist position per-bar
-- Uses compound barKeys (e.g. "258920:cd")
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BarsFrames = TUICD.BarsFrames or {}
local BarsFrames = TUICD.BarsFrames

local BarsData = TUICD.BarsData
local SpellAPI = TUICD.SpellAPI
local StatusBarAPI = TUICD.StatusBarAPI
local DurationAPI = TUICD.DurationAPI
local Media = TUICD.Media

-- Forward ref, resolved lazily (BarsDock loads after BarsFrames)
local function GetDock()
    return TUICD.BarsDock
end

-- ============================================================================
-- STATE
-- ============================================================================

-- Active bar frames: [barKey] = barFrame
local barFrames = {}

-- Layout mode state
local isLayoutMode = false

-- Config preview: force-show this bar even if disabled/inactive
local previewBarKey = nil

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DEFAULT_WIDTH = 200
local DEFAULT_HEIGHT = 20
local ICON_PADDING = 2
local BAR_BORDER_SIZE = 1
local DEFAULT_STRATA = "MEDIUM"
local DEFAULT_LEVEL = 50

-- Timer direction: detect Remaining direction for drain mode
-- Midnight uses RemainingTime/ElapsedTime (not Remaining/Elapsed)
local function GetTimerDirectionRemaining()
    if Enum and Enum.StatusBarTimerDirection then
        -- Try exact keys (discovered: RemainingTime=1, ElapsedTime=0)
        if Enum.StatusBarTimerDirection.RemainingTime ~= nil then
            return Enum.StatusBarTimerDirection.RemainingTime
        end
        if Enum.StatusBarTimerDirection.Remaining ~= nil then
            return Enum.StatusBarTimerDirection.Remaining
        end
        -- Fallback: iterate for any key containing "remaining" (case-insensitive)
        for k, v in pairs(Enum.StatusBarTimerDirection) do
            if type(k) == "string" and k:lower():find("remaining") then
                return v
            end
        end
    end
    return nil
end

local TIMER_DIR_REMAINING = GetTimerDirectionRemaining()
local HAS_TIMER_DIRECTION = (TIMER_DIR_REMAINING ~= nil)

-- ============================================================================
-- ICON ZOOM-CROP HELPERS
-- Non-square display of square textures: zoom to fill, never squash
-- ============================================================================

-- Compute pixel dimensions of icon from config
-- barThickness = the bar dimension the icon should match in auto mode
local function ComputeIconDimensions(config, barThickness)
    if not config.showIcon then return 0, 0 end

    local baseSize
    if config.iconSizeMode == "manual" and config.iconSize and config.iconSize > 0 then
        baseSize = config.iconSize
    else
        -- Auto: match bar thickness (height for horizontal, width for vertical)
        baseSize = barThickness
    end

    local aspect = BarsData.ICON_ASPECTS[config.iconAspect or "1:1"]
    if not aspect then aspect = BarsData.ICON_ASPECTS["1:1"] end

    local iconH = baseSize
    local iconW = baseSize * (aspect.w / aspect.h)
    return math.floor(iconW + 0.5), math.floor(iconH + 0.5)
end

-- Compute TexCoord that zoom-crops a square texture into a w×h rectangle
-- Standard icon trim is 0.08 inset on each edge
local function ComputeIconTexCoord(iconW, iconH)
    local TRIM = 0.08
    local L, R, T, B = TRIM, 1 - TRIM, TRIM, 1 - TRIM
    local range = R - L  -- 0.84

    if iconW == iconH or iconW <= 0 or iconH <= 0 then
        return L, R, T, B
    end

    if iconW > iconH then
        -- Wider than tall: crop top/bottom of texture
        local visibleFrac = iconH / iconW
        local inset = range * (1 - visibleFrac) / 2
        return L, R, T + inset, B - inset
    else
        -- Taller than wide: crop left/right of texture
        local visibleFrac = iconW / iconH
        local inset = range * (1 - visibleFrac) / 2
        return L + inset, R - inset, T, B
    end
end

-- Resolve font path from config
local function ResolveFontPath(config)
    local fontName = config.font
    if not fontName or fontName == "" then
        return STANDARD_TEXT_FONT
    end
    if Media and Media.GetFont then
        return Media:GetFont(fontName) or STANDARD_TEXT_FONT
    end
    return STANDARD_TEXT_FONT
end

-- Direction helpers
local function IsVertical(dir)
    return dir == "UP" or dir == "DOWN"
end

local function GetOrientation(dir)
    return IsVertical(dir) and "VERTICAL" or "HORIZONTAL"
end

local function GetFillStyle(dir)
    -- RIGHT/UP = STANDARD,  LEFT/DOWN = REVERSE
    return (dir == "LEFT" or dir == "DOWN") and "REVERSE" or "STANDARD"
end

-- Border helpers (barBorder is a table of 4 edge textures)
local function ShowBorder(border)
    if not border then return end
    for _, tex in ipairs(border) do tex:Show() end
end
local function HideBorder(border)
    if not border then return end
    for _, tex in ipairs(border) do tex:Hide() end
end
local function SetBorderColor(border, r, g, b, a)
    if not border then return end
    for _, tex in ipairs(border) do tex:SetColorTexture(r, g, b, a) end
end

-- ============================================================================
-- BAR FRAME CREATION
-- ============================================================================

local function CreateBarFrame(barKey)
    if barFrames[barKey] then return barFrames[barKey] end

    local config = BarsData:GetEffectiveConfig(barKey)
    if not config then return nil end

    local spellID = BarsData.ParseBarKey(barKey)
    local safeKey = BarsData.SanitizeKey(barKey)
    local frameName = "TUICD_Bar_" .. safeKey
    local width = config.width or DEFAULT_WIDTH
    local height = config.height or DEFAULT_HEIGHT
    local iconW, iconH = ComputeIconDimensions(config, height)
    local showIcon = config.showIcon and iconW > 0
    local totalWidth = width + (showIcon and (iconW + ICON_PADDING) or 0)
    local totalHeight = math.max(height, iconH)

    -- ========================================
    -- Main container frame
    -- ========================================
    local frame = CreateFrame("Frame", frameName, UIParent)
    frame:SetSize(totalWidth, totalHeight)
    frame:SetFrameStrata(DEFAULT_STRATA)
    frame:SetFrameLevel(DEFAULT_LEVEL)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)  -- Only enable in layout mode
    frame.barKey = barKey
    frame.spellID = spellID

    -- ========================================
    -- Icon (independent size, zoom-cropped)
    -- ========================================
    local icon = frame:CreateTexture(frameName .. "_Icon", "ARTWORK")
    icon:SetSize(iconW, iconH)
    frame.icon = icon

    if showIcon then
        if config.iconPosition == "RIGHT" then
            icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        else
            icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        end
        local l, r, t, b = ComputeIconTexCoord(iconW, iconH)
        icon:SetTexCoord(l, r, t, b)
        icon:SetTexture(config.iconID or (spellID and SpellAPI:GetSpellTexture(spellID)) or 134400)
    else
        icon:Hide()
    end

    -- Icon border
    local iconBorder = frame:CreateTexture(frameName .. "_IconBorder", "BACKGROUND")
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -BAR_BORDER_SIZE, BAR_BORDER_SIZE)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", BAR_BORDER_SIZE, -BAR_BORDER_SIZE)
    iconBorder:SetColorTexture(0, 0, 0, 1)
    iconBorder:SetShown(showIcon)
    frame.iconBorder = iconBorder

    -- ========================================
    -- Status bar (anchored relative to icon)
    -- ========================================
    local barOffsetL = 0
    local barOffsetR = 0

    if showIcon then
        if config.iconPosition == "RIGHT" then
            barOffsetR = -(iconW + ICON_PADDING)
        else
            barOffsetL = iconW + ICON_PADDING
        end
    end

    -- Background bar (plain Frame with ColorTexture - always renders solid color)
    local bgBar = CreateFrame("Frame", frameName .. "_BG", frame)
    bgBar:SetPoint("LEFT", frame, "LEFT", barOffsetL, 0)
    bgBar:SetSize(width, height)
    frame.bgBar = bgBar

    -- Background color texture (BACKGROUND layer, always visible when bgBar is shown)
    local bgColorTex = bgBar:CreateTexture(nil, "BACKGROUND")
    bgColorTex:SetAllPoints()
    local bgColor = config.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
    bgColorTex:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 0.8)
    bgBar.colorTex = bgColorTex

    -- Bar border (4 edge textures so nothing black sits behind bgBar interior)
    local bc = config.borderColor or { r = 0, g = 0, b = 0, a = 1 }

    local borderTop = frame:CreateTexture(nil, "BACKGROUND")
    borderTop:SetPoint("TOPLEFT", bgBar, "TOPLEFT", -BAR_BORDER_SIZE, BAR_BORDER_SIZE)
    borderTop:SetPoint("TOPRIGHT", bgBar, "TOPRIGHT", BAR_BORDER_SIZE, BAR_BORDER_SIZE)
    borderTop:SetHeight(BAR_BORDER_SIZE)
    borderTop:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    local borderBottom = frame:CreateTexture(nil, "BACKGROUND")
    borderBottom:SetPoint("BOTTOMLEFT", bgBar, "BOTTOMLEFT", -BAR_BORDER_SIZE, -BAR_BORDER_SIZE)
    borderBottom:SetPoint("BOTTOMRIGHT", bgBar, "BOTTOMRIGHT", BAR_BORDER_SIZE, -BAR_BORDER_SIZE)
    borderBottom:SetHeight(BAR_BORDER_SIZE)
    borderBottom:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    local borderLeft = frame:CreateTexture(nil, "BACKGROUND")
    borderLeft:SetPoint("TOPLEFT", bgBar, "TOPLEFT", -BAR_BORDER_SIZE, 0)
    borderLeft:SetPoint("BOTTOMLEFT", bgBar, "BOTTOMLEFT", -BAR_BORDER_SIZE, 0)
    borderLeft:SetWidth(BAR_BORDER_SIZE)
    borderLeft:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    local borderRight = frame:CreateTexture(nil, "BACKGROUND")
    borderRight:SetPoint("TOPRIGHT", bgBar, "TOPRIGHT", BAR_BORDER_SIZE, 0)
    borderRight:SetPoint("BOTTOMRIGHT", bgBar, "BOTTOMRIGHT", BAR_BORDER_SIZE, 0)
    borderRight:SetWidth(BAR_BORDER_SIZE)
    borderRight:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    frame.barBorder = { borderTop, borderBottom, borderLeft, borderRight }

    -- Fill bar
    local bar = CreateFrame("StatusBar", frameName .. "_Fill", bgBar)
    bar:SetAllPoints()
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    frame.bar = bar

    local barTexPath = Media and Media:GetStatusBarTexture(config.barTexture) or "Interface\\TargetingFrame\\UI-StatusBar"
    bar:SetStatusBarTexture(barTexPath)

    local barColor = config.barColor or { r = 0.26, g = 0.65, b = 1.0, a = 1.0 }
    bar:SetStatusBarColor(barColor.r, barColor.g, barColor.b, barColor.a)

    -- Initial orientation + fill style from barDirection
    local initDir = config.barDirection or "RIGHT"
    pcall(function() bar:SetOrientation(GetOrientation(initDir)) end)
    StatusBarAPI:SetFillStyle(bar, GetFillStyle(initDir))

    -- Rotate texture for vertical bars
    if IsVertical(initDir) then
        local bt = bar:GetStatusBarTexture()
        if bt then bt:SetTexCoord(0, 1, 0, 0, 1, 1, 1, 0) end
    end

    -- ========================================
    -- Text overlays
    -- ========================================
    local fontPath = ResolveFontPath(config)

    local nameText = bar:CreateFontString(frameName .. "_Name", "OVERLAY")
    nameText:SetFont(fontPath, config.nameFontSize or 11, "OUTLINE")
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(config.name or "")
    nameText:SetShown(config.showName ~= false)
    frame.nameText = nameText

    local timeText = bar:CreateFontString(frameName .. "_Time", "OVERLAY")
    timeText:SetFont(fontPath, config.timeFontSize or 11, "OUTLINE")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timeText:SetJustifyH("RIGHT")
    timeText:SetText("")
    timeText:SetShown(config.showTime ~= false)
    frame.timeText = timeText

    -- ========================================
    -- Layout Mode overlay
    -- ========================================
    local overlay = CreateFrame("Frame", frameName .. "_Overlay", frame)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
    overlay:Hide()

    local overlayTex = overlay:CreateTexture(nil, "OVERLAY")
    overlayTex:SetAllPoints()
    overlayTex:SetColorTexture(0, 0.5, 1, 0.3)

    local overlayText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlayText:SetPoint("CENTER")
    local overlayLabel = (config.name or ("Spell " .. (spellID or "?"))) .. " " .. BarsData.TypeLabel(config.type)
    overlayText:SetText(overlayLabel)
    overlayText:SetTextColor(1, 1, 1, 1)

    frame.layoutOverlay = overlay
    frame.layoutOverlayText = overlayText

    -- ========================================
    -- Drag handling
    -- ========================================
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if isLayoutMode then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        BarsData:SetSpellPosition(self.barKey, point, x, y)
    end)

    -- ========================================
    -- Initial state: hidden
    -- ========================================
    frame:Hide()

    barFrames[barKey] = frame
    return frame
end

-- ============================================================================
-- FRAME UPDATES
-- ============================================================================

function BarsFrames:ApplyConfig(barKey)
    local frame = barFrames[barKey]
    if not frame then return end

    local config = BarsData:GetEffectiveConfig(barKey)
    if not config then return end
    local dir = config.barDirection or "RIGHT"
    local isVert = IsVertical(dir)
    local height = config.height or DEFAULT_HEIGHT
    local width = config.width or DEFAULT_WIDTH

    -- For vertical bars, icon auto-size matches bar width (the "thickness")
    local iconMatchDim = isVert and width or height
    local iconW, iconH = ComputeIconDimensions(config, iconMatchDim)
    local showIcon = config.showIcon and iconW > 0

    -- ========================================
    -- Frame dimensions
    -- ========================================
    local totalWidth, totalHeight
    if isVert then
        totalWidth = math.max(width, showIcon and iconW or 0)
        totalHeight = height + (showIcon and (iconH + ICON_PADDING) or 0)
    else
        totalWidth = width + (showIcon and (iconW + ICON_PADDING) or 0)
        totalHeight = math.max(height, iconH)
    end

    frame:SetSize(totalWidth, totalHeight)

    -- Resize TUIFrame parent if registered with layout system
    if frame._tuiFrame and frame._tuiFrame.frame then
        frame._tuiFrame.frame:SetSize(totalWidth, totalHeight)
    end

    -- ========================================
    -- Icon placement
    -- ========================================
    frame.icon:SetSize(iconW, iconH)
    if showIcon then
        frame.icon:ClearAllPoints()
        if isVert then
            -- Vertical: LEFT config → TOP, RIGHT config → BOTTOM
            if config.iconPosition == "RIGHT" then
                frame.icon:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
            else
                frame.icon:SetPoint("TOP", frame, "TOP", 0, 0)
            end
        else
            -- Horizontal: standard left/right
            if config.iconPosition == "RIGHT" then
                frame.icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            else
                frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
            end
        end
        local l, r, t, b = ComputeIconTexCoord(iconW, iconH)
        frame.icon:SetTexCoord(l, r, t, b)
        frame.icon:SetTexture(config.iconID or (spellID and SpellAPI:GetSpellTexture(spellID)) or 134400)
        frame.icon:Show()
        frame.iconBorder:Show()
    else
        frame.icon:Hide()
        frame.iconBorder:Hide()
    end

    -- ========================================
    -- Status bar placement
    -- ========================================
    frame.bgBar:ClearAllPoints()
    if isVert then
        local barOffsetT = 0
        if showIcon and config.iconPosition ~= "RIGHT" then
            barOffsetT = -(iconH + ICON_PADDING)
        end
        frame.bgBar:SetPoint("TOP", frame, "TOP", 0, barOffsetT)
        frame.bgBar:SetSize(width, height)
    else
        local barOffsetL = 0
        if showIcon and config.iconPosition ~= "RIGHT" then
            barOffsetL = iconW + ICON_PADDING
        end
        frame.bgBar:SetPoint("LEFT", frame, "LEFT", barOffsetL, 0)
        frame.bgBar:SetSize(width, height)
    end

    -- ========================================
    -- Orientation + fill style
    -- ========================================
    local orientation = GetOrientation(dir)
    local fillStyle = GetFillStyle(dir)

    pcall(function() frame.bar:SetOrientation(orientation) end)
    StatusBarAPI:SetFillStyle(frame.bar, fillStyle)

    -- Cache on frame so UpdateBarDisplay can re-assert after SetTimerDuration
    frame._barOrientation = orientation
    frame._barFillStyle = fillStyle
    frame._barIsVert = isVert

    -- ========================================
    -- Textures (fill bar only; bgBar is a plain Frame with ColorTexture)
    -- ========================================
    local texPath = Media and Media:GetStatusBarTexture(config.barTexture) or "Interface\\TargetingFrame\\UI-StatusBar"
    frame.bar:SetStatusBarTexture(texPath)

    -- Rotate texture 90° for vertical bars so the gradient follows the fill direction
    local barTex = frame.bar:GetStatusBarTexture()
    if barTex then
        if isVert then
            barTex:SetTexCoord(0, 1, 0, 0, 1, 1, 1, 0)
        else
            barTex:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
        end
    end

    -- Colors
    local bgc = config.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
    if frame.bgBar.colorTex then
        frame.bgBar.colorTex:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 0.8)
    end

    local bc = config.barColor or { r = 0.26, g = 0.65, b = 1.0, a = 1.0 }
    frame.bar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)

    local bdc = config.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    SetBorderColor(frame.barBorder, bdc.r, bdc.g, bdc.b, bdc.a)

    -- ========================================
    -- Text anchoring (direction-aware + user offsets)
    -- ========================================
    local fontPath = ResolveFontPath(config)
    frame.nameText:SetFont(fontPath, config.nameFontSize or 11, "OUTLINE")
    frame.nameText:SetText(config.name or "")
    frame.nameText:SetShown(config.showName ~= false)

    frame.timeText:SetFont(fontPath, config.timeFontSize or 11, "OUTLINE")
    frame.timeText:SetShown(config.showTime ~= false)

    local nox = config.nameOffsetX or 0
    local noy = config.nameOffsetY or 0
    local tox = config.timeOffsetX or 0
    local toy = config.timeOffsetY or 0

    frame.nameText:ClearAllPoints()
    frame.timeText:ClearAllPoints()

    if isVert then
        -- Vertical: center text horizontally, name at start end, time at fill end
        if dir == "UP" then
            frame.nameText:SetPoint("BOTTOM", frame.bar, "BOTTOM", nox, 3 + noy)
            frame.timeText:SetPoint("TOP", frame.bar, "TOP", tox, -3 + toy)
        else  -- DOWN
            frame.nameText:SetPoint("TOP", frame.bar, "TOP", nox, -3 + noy)
            frame.timeText:SetPoint("BOTTOM", frame.bar, "BOTTOM", tox, 3 + toy)
        end
        frame.nameText:SetJustifyH("CENTER")
        frame.timeText:SetJustifyH("CENTER")
    else
        -- Horizontal: name at leading edge, time at trailing edge
        if dir == "LEFT" then
            frame.nameText:SetPoint("RIGHT", frame.bar, "RIGHT", -4 + nox, noy)
            frame.nameText:SetJustifyH("RIGHT")
            frame.timeText:SetPoint("LEFT", frame.bar, "LEFT", 4 + tox, toy)
            frame.timeText:SetJustifyH("LEFT")
        else  -- RIGHT (default)
            frame.nameText:SetPoint("LEFT", frame.bar, "LEFT", 4 + nox, noy)
            frame.nameText:SetJustifyH("LEFT")
            frame.timeText:SetPoint("RIGHT", frame.bar, "RIGHT", -4 + tox, toy)
            frame.timeText:SetJustifyH("RIGHT")
        end
    end

    -- Layout overlay label
    local overlayLabel = (config.name or ("Spell " .. (spellID or "?"))) .. " " .. BarsData.TypeLabel(config.type)
    frame.layoutOverlayText:SetText(overlayLabel)
end

-- ============================================================================
-- DEMAND-DRIVEN TEXT UPDATER
-- OnUpdate frame that only runs when ≥1 bar is actively on cooldown.
-- Auto-hides (stops OnUpdate) when no active bars remain.
-- ============================================================================

local function IsTimeStringEmpty(timeStr)
    if timeStr == nil then return true end
    if issecretvalue and issecretvalue(timeStr) then
        return false
    end
    return timeStr == ""
end

-- ============================================================================
-- COLOR-BY-TIME HELPERS
-- Uses cached non-secret ms from CooldownFrame sensor for smooth gradients
-- ============================================================================

local function LerpValue(a, b, t)
    return a + (b - a) * t
end

-- Returns r, g, b for the bar based on remaining seconds and config thresholds
-- Smoothly interpolates between colorHigh -> colorMed -> colorLow
-- Curve-based color-by-time: works with secret values via EvaluateRemainingPercent
-- Cache curves per config hash to avoid recreating every frame
local colorCurveCache = {}  -- { [cacheKey] = { r = curve, g = curve, b = curve } }

local function GetOrCreateColorCurves(config)
    local cHigh = config.colorHigh or { r = 1.0, g = 0.2, b = 0.2 }
    local cMed  = config.colorMed  or { r = 1.0, g = 0.8, b = 0.0 }
    local cLow  = config.colorLow  or { r = 0.2, g = 0.8, b = 0.2 }
    
    -- Simple cache key from color values
    local key = string.format("%.2f%.2f%.2f%.2f%.2f%.2f%.2f%.2f%.2f",
        cHigh.r, cHigh.g, cHigh.b, cMed.r, cMed.g, cMed.b, cLow.r, cLow.g, cLow.b)
    
    if colorCurveCache[key] then return colorCurveCache[key] end
    
    if DurationAPI and DurationAPI.CreateColorCurves then
        local curves = DurationAPI:CreateColorCurves(cLow, cMed, cHigh)
        if curves then
            colorCurveCache[key] = curves
            return curves
        end
    end
    return nil
end

-- Fallback color-by-time using non-secret remaining (only works outside combat)
local function GetTimeBasedColor(remaining, config)
    local highSec = config.colorHighSeconds or 10
    local medSec  = config.colorMedSeconds or 5
    local cHigh = config.colorHigh or { r = 1.0, g = 0.2, b = 0.2 }
    local cMed  = config.colorMed  or { r = 1.0, g = 0.8, b = 0.0 }
    local cLow  = config.colorLow  or { r = 0.2, g = 0.8, b = 0.2 }

    if remaining >= highSec then
        return cHigh.r, cHigh.g, cHigh.b
    elseif remaining >= medSec then
        local t = (remaining - medSec) / (highSec - medSec)
        return LerpValue(cMed.r, cHigh.r, t),
               LerpValue(cMed.g, cHigh.g, t),
               LerpValue(cMed.b, cHigh.b, t)
    elseif remaining > 0 then
        local t = remaining / medSec
        return LerpValue(cLow.r, cMed.r, t),
               LerpValue(cLow.g, cMed.g, t),
               LerpValue(cLow.b, cMed.b, t)
    else
        return cLow.r, cLow.g, cLow.b
    end
end

local textUpdateFrame = CreateFrame("Frame")
textUpdateFrame:Hide()

local TEXT_UPDATE_INTERVAL = 0.1  -- 10Hz for smooth countdown text
local textUpdateElapsed = 0

textUpdateFrame:SetScript("OnUpdate", function(self, elapsed)
    textUpdateElapsed = textUpdateElapsed + elapsed
    if textUpdateElapsed < TEXT_UPDATE_INTERVAL then return end
    textUpdateElapsed = 0

    local anyActive = false

    for barKey, frame in pairs(barFrames) do
        if frame:IsShown() and not isLayoutMode then
            local config = BarsData:GetEffectiveConfig(barKey)
            local state = BarsData:GetSpellState(barKey)
            if config and state then
                if state.isActive and state.durationObj then
                    anyActive = true

                    local dObj = state.durationObj

                    -- TMW approach: SetValue with secret-safe Duration Object methods
                    -- SetMinMaxValues and SetValue both accept secret numbers
                    pcall(function()
                        local totalDuration = dObj:GetTotalDuration()
                        local remaining = dObj:GetRemainingDuration()
                        frame.bar:SetMinMaxValues(0, totalDuration)
                        if config.fillMode ~= "fill" then
                            -- Drain: value = remaining (full → empty)
                            frame.bar:SetValue(remaining)
                        else
                            -- Fill: value = elapsed (empty → full)
                            frame.bar:SetValue(dObj:GetElapsedDuration())
                        end
                    end)

                    -- Color-by-time: Curve approach (works with secrets)
                    if config.colorByTime then
                        local curves = GetOrCreateColorCurves(config)
                        if curves and DurationAPI then
                            local bc = config.barColor or { r = 0.26, g = 0.65, b = 1.0 }
                            local r, g, b = DurationAPI:EvaluateColorCurves(dObj, curves, bc)
                            pcall(function() frame.bar:SetStatusBarColor(r, g, b) end)
                        end
                    end

                    if config.showTime ~= false then
                        local ok, timeStr = pcall(function()
                            return DurationAPI:Format(state.durationObj)
                        end)
                        if ok then
                            frame.timeText:SetText(timeStr or "")
                            -- Safety net: detect expiration via empty time string
                            -- (primary expiration detection is event-driven)
                            if IsTimeStringEmpty(timeStr) then
                                state.isActive = false
                                state.durationObj = nil
                                if config.showWhenReady then
                                    frame.bgBar:Hide()
                                    HideBorder(frame.barBorder)
                                    frame.bar:SetMinMaxValues(0, 1)
                                    frame.bar:SetValue(0)
                                    frame.timeText:SetText("")
                                else
                                    frame:Hide()
                                    local dock = GetDock()
                                    if dock then dock:OnBarHidden(barKey) end
                                end
                            end
                        end
                    else
                        -- showTime is false: still need expiration detection
                        local expired = false
                        pcall(function()
                            local timeStr = DurationAPI:Format(state.durationObj)
                            if IsTimeStringEmpty(timeStr) then expired = true end
                        end)
                        if expired then
                            state.isActive = false
                            state.durationObj = nil
                            if not config.showWhenReady then
                                frame:Hide()
                                local dock = GetDock()
                                if dock then dock:OnBarHidden(barKey) end
                            else
                                frame.bgBar:Hide()
                                HideBorder(frame.barBorder)
                                frame.bar:SetMinMaxValues(0, 1)
                                frame.bar:SetValue(0)
                            end
                        else
                            anyActive = true
                        end
                    end
                elseif not state.isActive and not config.showWhenReady then
                    frame:Hide()
                end
            end
        end
    end

    -- Auto-stop when no active bars
    if not anyActive then
        self:Hide()
    end
end)

-- Start the text updater (called when a bar becomes active)
local function EnsureTextUpdaterRunning()
    if not textUpdateFrame:IsShown() then
        textUpdateElapsed = 0
        textUpdateFrame:Show()
    end
end

-- Stop the text updater (called on module disable)
function BarsFrames:StopTextUpdater()
    textUpdateFrame:Hide()
end

-- ============================================================================
-- DISPLAY UPDATE (called from data callbacks)
-- ============================================================================

-- Update a single bar's timer display from data state
function BarsFrames:UpdateBarDisplay(barKey)
    local frame = barFrames[barKey]
    if not frame then return end

    local config = BarsData:GetEffectiveConfig(barKey)
    local isPreview = (barKey == previewBarKey)
    if not config or (not config.enabled and not isPreview) then
        local wasShown = frame:IsShown()
        frame:Hide()
        if wasShown then
            local dock = GetDock()
            if dock then dock:OnBarHidden(barKey) end
        end
        return
    end

    local state = BarsData:GetSpellState(barKey)

    -- Layout mode: always show with placeholder fill
    if isLayoutMode then
        frame:Show()
        frame.bgBar:Show()
        local bgc = config.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
        if frame.bgBar.colorTex then
            frame.bgBar.colorTex:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 0.8)
        end
        ShowBorder(frame.barBorder)
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(0.65)
        frame.timeText:SetText("12s")
        return
    end

    -- Config preview: show selected bar with placeholder even if disabled/inactive
    if isPreview then
        local wouldNormallyShow = config.enabled and
            ((state and state.isActive) or config.showWhenReady)
        if not wouldNormallyShow then
            local wasHidden = not frame:IsShown()
            frame:Show()
            frame.bgBar:Show()
            local bgc = config.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
            if frame.bgBar.colorTex then
                frame.bgBar.colorTex:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 0.8)
            end
            ShowBorder(frame.barBorder)
            frame.bar:SetMinMaxValues(0, 1)
            frame.bar:SetValue(0.65)
            frame.timeText:SetText("12s")
            if wasHidden then
                local dock = GetDock()
                if dock then dock:OnBarShown(barKey) end
            end
            return
        end
        -- Bar would show normally, fall through to real display
    end

    -- Determine visibility
    local shouldShow = false
    if state and state.isActive then
        shouldShow = true
    elseif config.showWhenReady then
        shouldShow = true
    end

    local wasShown = frame:IsShown()

    if not shouldShow then
        frame:Hide()
        if wasShown then
            local dock = GetDock()
            if dock then dock:OnBarHidden(barKey) end
        end
        return
    end

    frame:Show()
    if not wasShown then
        local dock = GetDock()
        if dock then dock:OnBarShown(barKey) end
    end

    -- Apply Duration Object (TMW-proven approach: SetMinMaxValues + SetValue per tick)
    -- SetValue and SetMinMaxValues both accept secret numbers from Duration Objects
    if state and state.isActive and state.durationObj then
        -- Show background + border while on cooldown
        frame.bgBar:Show()
        local bgc = config.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
        if frame.bgBar.colorTex then
            frame.bgBar.colorTex:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 0.8)
        end
        ShowBorder(frame.barBorder)

        -- Set up min/max from Duration Object's total duration (accepts secrets)
        pcall(function()
            local totalDuration = state.durationObj:GetTotalDuration()
            frame.bar:SetMinMaxValues(0, totalDuration)
            -- Initial fill value
            if config.fillMode ~= "fill" then
                frame.bar:SetValue(state.durationObj:GetRemainingDuration())
            else
                frame.bar:SetValue(state.durationObj:GetElapsedDuration())
            end
        end)

        frame._manualDrain = false

        -- Re-assert orientation
        if frame._barOrientation then
            pcall(function() frame.bar:SetOrientation(frame._barOrientation) end)
            StatusBarAPI:SetFillStyle(frame.bar, frame._barFillStyle)
            if frame._barIsVert then
                local barTex = frame.bar:GetStatusBarTexture()
                if barTex then barTex:SetTexCoord(0, 1, 0, 0, 1, 1, 1, 0) end
            end
        end

        -- Set initial bar color
        if config.colorByTime then
            local curves = GetOrCreateColorCurves(config)
            if curves and DurationAPI then
                local bc = config.barColor or { r = 0.26, g = 0.65, b = 1.0 }
                local r, g, b = DurationAPI:EvaluateColorCurves(state.durationObj, curves, bc)
                pcall(function() frame.bar:SetStatusBarColor(r, g, b) end)
            end
        else
            local bc = config.barColor or { r = 0.26, g = 0.65, b = 1.0 }
            frame.bar:SetStatusBarColor(bc.r, bc.g, bc.b)
        end

        if config.showTime ~= false then
            pcall(function()
                local timeStr = DurationAPI:Format(state.durationObj)
                frame.timeText:SetText(timeStr or "")
            end)
        end

        -- Kick the demand-driven text updater (only runs while bars are active)
        EnsureTextUpdaterRunning()
    else
        -- Ready state (off cooldown): empty bar, no background
        frame.bgBar:Hide()
        HideBorder(frame.barBorder)
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(0)
        frame.timeText:SetText("")
        frame._manualDrain = false
        -- Reset to static color
        local bc = config.barColor or { r = 0.26, g = 0.65, b = 1.0 }
        frame.bar:SetStatusBarColor(bc.r, bc.g, bc.b)
    end
end

-- ============================================================================
-- CREATE/DESTROY LIFECYCLE
-- ============================================================================

function BarsFrames:CreateBar(barKey)
    local frame = CreateBarFrame(barKey)
    if not frame then return nil end

    local dockEnabled = BarsData:IsDockEnabled()

    if dockEnabled then
        -- DOCK MODE: parent to dock container, dock handles positioning
        local dock = GetDock()
        if dock then
            local dockFrame = dock:GetDock()
            if not dockFrame then
                dock:CreateDock()
                dockFrame = dock:GetDock()
            end
            if dockFrame then
                frame:SetParent(dockFrame)
            end
        end
    else
        -- STANDALONE MODE: each bar is individually positioned
        local pos = BarsData:GetSpellPosition(barKey)
        if pos then
            frame:ClearAllPoints()
            frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
        else
            local count = 0
            for _ in pairs(barFrames) do count = count + 1 end
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100 - (count * 28))
        end

        -- Register with Layout system (TUIFrame per bar)
        local safeKey = BarsData.SanitizeKey(barKey)
        if TUICD.Layout and TUICD.Layout.RegisterElement then
            local config = BarsData:GetSpellConfig(barKey)
            local spellID = BarsData.ParseBarKey(barKey)
            local name = config and config.name or ("Spell " .. (spellID or "?"))
            local displayName = name .. " " .. BarsData.TypeLabel(config and config.type)
            local tuiFrame = TUICD.TUIFrame:New("bar_" .. safeKey, {
                name = "Bar: " .. displayName,
                category = "Timer Bar",
                width = frame:GetWidth(),
                height = frame:GetHeight(),
                defaultX = 0,
                defaultY = 100 - (count or 0) * 28,
            })
            if tuiFrame then
                frame:SetParent(tuiFrame.frame)
                frame:ClearAllPoints()
                frame:SetAllPoints(tuiFrame.frame)
                frame._tuiFrame = tuiFrame

                TUICD.Layout:RegisterElement("bar_" .. safeKey, {
                    name = "Bar: " .. displayName,
                    category = "Timer Bar",
                    tuiFrame = tuiFrame,
                })
            end
        end
    end

    return frame
end

function BarsFrames:DestroyBar(barKey)
    local frame = barFrames[barKey]
    if not frame then return end

    -- Notify dock of removal
    local dock = GetDock()
    if dock then dock:OnBarHidden(barKey) end

    local safeKey = BarsData.SanitizeKey(barKey)
    if TUICD.Layout and TUICD.Layout.UnregisterElement then
        TUICD.Layout:UnregisterElement("bar_" .. safeKey)
    end

    if frame._tuiFrame then
        frame._tuiFrame:Destroy()
        frame._tuiFrame = nil
    end

    frame:Hide()
    frame:SetParent(nil)
    barFrames[barKey] = nil
end

function BarsFrames:CreateAllBars()
    local spells = BarsData:GetTrackedSpells()
    for barKey, config in pairs(spells) do
        if config.enabled then
            self:CreateBar(barKey)
            self:ApplyConfig(barKey)
            self:UpdateBarDisplay(barKey)
        end
    end
end

function BarsFrames:DestroyAllBars()
    for barKey in pairs(barFrames) do
        self:DestroyBar(barKey)
    end
end

function BarsFrames:GetBar(barKey)
    return barFrames[barKey]
end

function BarsFrames:GetAllBars()
    return barFrames
end

-- ============================================================================
-- LAYOUT MODE
-- ============================================================================

function BarsFrames:EnterLayoutMode()
    isLayoutMode = true

    local dockEnabled = BarsData:IsDockEnabled()
    local dock = GetDock()

    if dockEnabled and dock then
        -- Dock layout mode: dock handles all positioning
        dock:EnterLayoutMode()
        -- Still show overlays on individual bars for identification
        for barKey, frame in pairs(barFrames) do
            frame:Show()
            frame.layoutOverlay:Show()
            frame.bar:SetMinMaxValues(0, 1)
            frame.bar:SetValue(0.65)
            frame.timeText:SetText("12s")
        end
    else
        -- Standalone layout mode: each bar is individually draggable
        for barKey, frame in pairs(barFrames) do
            frame:EnableMouse(true)
            frame:Show()
            frame.layoutOverlay:Show()
            frame.bar:SetMinMaxValues(0, 1)
            frame.bar:SetValue(0.65)
            frame.timeText:SetText("12s")
        end
    end
end

function BarsFrames:ExitLayoutMode()
    isLayoutMode = false

    local dockEnabled = BarsData:IsDockEnabled()
    local dock = GetDock()

    if dockEnabled and dock then
        dock:ExitLayoutMode()
    end

    for barKey, frame in pairs(barFrames) do
        frame:EnableMouse(false)
        frame.layoutOverlay:Hide()
        self:UpdateBarDisplay(barKey)
    end
end

-- ============================================================================
-- DATA CALLBACKS
-- ============================================================================

function BarsFrames:OnDataUpdate(barKey)
    if barKey then
        self:UpdateBarDisplay(barKey)
    else
        for id in pairs(barFrames) do
            self:UpdateBarDisplay(id)
        end
    end
end

function BarsFrames:OnSpellAdded(barKey)
    self:CreateBar(barKey)
    self:ApplyConfig(barKey)
    self:UpdateBarDisplay(barKey)
end

function BarsFrames:OnSpellRemoved(barKey)
    self:DestroyBar(barKey)
end

function BarsFrames:OnConfigChanged(barKey)
    local config = BarsData:GetSpellConfig(barKey)
    if not config then return end

    local isPreview = (barKey == previewBarKey)

    if config.enabled or isPreview then
        if not barFrames[barKey] then
            self:CreateBar(barKey)
        end
        if barFrames[barKey] then
            self:ApplyConfig(barKey)
            self:UpdateBarDisplay(barKey)
            BarsData:UpdateCooldownState(barKey)
            -- Notify dock that bar size/config may have changed
            local dock = GetDock()
            if dock then dock:OnBarConfigChanged(barKey) end
        end
    else
        if barFrames[barKey] then
            self:DestroyBar(barKey)
        end
    end
end

-- ============================================================================
-- CONFIG PREVIEW (force-show selected bar in settings panel)
-- ============================================================================

function BarsFrames:SetPreviewBar(barKey)
    local oldKey = previewBarKey
    previewBarKey = barKey

    -- Hide old preview if it was only showing because of preview
    if oldKey and oldKey ~= barKey then
        if barFrames[oldKey] then
            self:UpdateBarDisplay(oldKey)
            -- If bar was disabled, OnConfigChanged would normally destroy it
            local config = BarsData:GetSpellConfig(oldKey)
            if config and not config.enabled and barFrames[oldKey] then
                self:DestroyBar(oldKey)
            end
        end
    end

    -- Show new preview bar
    if barKey then
        if not barFrames[barKey] then
            self:CreateBar(barKey)
        end
        if barFrames[barKey] then
            self:ApplyConfig(barKey)
            self:UpdateBarDisplay(barKey)
        end
        -- Force dock visible for preview
        local dock = GetDock()
        if dock then dock:UpdateVisibility() end
    end
end

function BarsFrames:ClearPreviewBar()
    local oldKey = previewBarKey
    previewBarKey = nil

    if oldKey and barFrames[oldKey] then
        -- Re-evaluate: hide if disabled, normal display if enabled
        local config = BarsData:GetSpellConfig(oldKey)
        if config and not config.enabled then
            local wasShown = barFrames[oldKey]:IsShown()
            barFrames[oldKey]:Hide()
            if wasShown then
                local dock = GetDock()
                if dock then dock:OnBarHidden(oldKey) end
            end
            self:DestroyBar(oldKey)
        else
            self:UpdateBarDisplay(oldKey)
        end
    end

    -- Let dock re-evaluate visibility
    local dock = GetDock()
    if dock then dock:UpdateVisibility() end
end

function BarsFrames:GetPreviewBarKey()
    return previewBarKey
end

return BarsFrames
