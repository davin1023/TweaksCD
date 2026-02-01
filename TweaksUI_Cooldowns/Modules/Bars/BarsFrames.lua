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

-- ============================================================================
-- STATE
-- ============================================================================

-- Active bar frames: [barKey] = barFrame
local barFrames = {}

-- Layout mode state
local isLayoutMode = false

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DEFAULT_WIDTH = 200
local DEFAULT_HEIGHT = 20
local ICON_PADDING = 2
local BAR_BORDER_SIZE = 1
local DEFAULT_STRATA = "MEDIUM"
local DEFAULT_LEVEL = 50

-- ============================================================================
-- BAR FRAME CREATION
-- ============================================================================

local function CreateBarFrame(barKey)
    if barFrames[barKey] then return barFrames[barKey] end

    local config = BarsData:GetSpellConfig(barKey)
    if not config then return nil end

    local spellID = BarsData.ParseBarKey(barKey)
    local safeKey = BarsData.SanitizeKey(barKey)
    local frameName = "TUICD_Bar_" .. safeKey
    local width = config.width or DEFAULT_WIDTH
    local height = config.height or DEFAULT_HEIGHT
    local iconSize = config.showIcon and height or 0
    local totalWidth = width + (config.showIcon and (iconSize + ICON_PADDING) or 0)

    -- ========================================
    -- Main container frame
    -- ========================================
    local frame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    frame:SetSize(totalWidth, height)
    frame:SetFrameStrata(DEFAULT_STRATA)
    frame:SetFrameLevel(DEFAULT_LEVEL)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)  -- Only enable in layout mode
    frame.barKey = barKey
    frame.spellID = spellID  -- Keep for convenience

    -- ========================================
    -- Icon (optional, on left or right)
    -- ========================================
    local icon = frame:CreateTexture(frameName .. "_Icon", "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    frame.icon = icon

    if config.showIcon then
        if config.iconPosition == "RIGHT" then
            icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        else
            icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        end
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(config.iconID or (spellID and SpellAPI:GetSpellTexture(spellID)) or 134400)
    else
        icon:Hide()
    end

    -- Icon border
    local iconBorder = frame:CreateTexture(frameName .. "_IconBorder", "BACKGROUND")
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -BAR_BORDER_SIZE, BAR_BORDER_SIZE)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", BAR_BORDER_SIZE, -BAR_BORDER_SIZE)
    iconBorder:SetColorTexture(0, 0, 0, 1)
    iconBorder:SetShown(config.showIcon ~= false)
    frame.iconBorder = iconBorder

    -- ========================================
    -- Status bar
    -- ========================================
    local barOffsetL = 0
    local barOffsetR = 0

    if config.showIcon then
        if config.iconPosition == "RIGHT" then
            barOffsetR = -(iconSize + ICON_PADDING)
        else
            barOffsetL = iconSize + ICON_PADDING
        end
    end

    -- Background bar
    local bgBar = CreateFrame("StatusBar", frameName .. "_BG", frame)
    bgBar:SetPoint("TOPLEFT", frame, "TOPLEFT", barOffsetL, 0)
    bgBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", barOffsetR, 0)
    bgBar:SetMinMaxValues(0, 1)
    bgBar:SetValue(1)
    frame.bgBar = bgBar

    local bgTex = Media and Media:GetStatusBarTexture(config.barTexture) or "Interface\\TargetingFrame\\UI-StatusBar"
    bgBar:SetStatusBarTexture(bgTex)

    local bgColor = config.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
    bgBar:SetStatusBarColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)

    -- Bar border
    local barBorder = frame:CreateTexture(frameName .. "_BarBorder", "BACKGROUND")
    barBorder:SetPoint("TOPLEFT", bgBar, "TOPLEFT", -BAR_BORDER_SIZE, BAR_BORDER_SIZE)
    barBorder:SetPoint("BOTTOMRIGHT", bgBar, "BOTTOMRIGHT", BAR_BORDER_SIZE, -BAR_BORDER_SIZE)
    local bc = config.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    barBorder:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
    frame.barBorder = barBorder

    -- Fill bar
    local bar = CreateFrame("StatusBar", frameName .. "_Fill", bgBar)
    bar:SetAllPoints()
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    frame.bar = bar

    bar:SetStatusBarTexture(bgTex)

    local barColor = config.barColor or { r = 0.26, g = 0.65, b = 1.0, a = 1.0 }
    bar:SetStatusBarColor(barColor.r, barColor.g, barColor.b, barColor.a)

    if config.fillDirection == "REVERSE" then
        StatusBarAPI:SetFillStyle(bar, "REVERSE")
    end

    -- ========================================
    -- Text overlays
    -- ========================================
    local nameText = bar:CreateFontString(frameName .. "_Name", "OVERLAY")
    nameText:SetFont(STANDARD_TEXT_FONT, config.nameFontSize or 11, "OUTLINE")
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(config.name or "")
    nameText:SetShown(config.showName ~= false)
    frame.nameText = nameText

    local timeText = bar:CreateFontString(frameName .. "_Time", "OVERLAY")
    timeText:SetFont(STANDARD_TEXT_FONT, config.timeFontSize or 11, "OUTLINE")
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

    local config = BarsData:GetSpellConfig(barKey)
    if not config then return end

    local spellID = BarsData.ParseBarKey(barKey)
    local height = config.height or DEFAULT_HEIGHT
    local width = config.width or DEFAULT_WIDTH
    local iconSize = config.showIcon and height or 0
    local totalWidth = width + (config.showIcon and (iconSize + ICON_PADDING) or 0)

    frame:SetSize(totalWidth, height)

    -- Icon
    frame.icon:SetSize(iconSize, iconSize)
    if config.showIcon then
        frame.icon:ClearAllPoints()
        if config.iconPosition == "RIGHT" then
            frame.icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        else
            frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        end
        frame.icon:SetTexture(config.iconID or (spellID and SpellAPI:GetSpellTexture(spellID)) or 134400)
        frame.icon:Show()
        frame.iconBorder:Show()
    else
        frame.icon:Hide()
        frame.iconBorder:Hide()
    end

    -- Reanchor bar area
    local barOffsetL = 0
    local barOffsetR = 0
    if config.showIcon then
        if config.iconPosition == "RIGHT" then
            barOffsetR = -(iconSize + ICON_PADDING)
        else
            barOffsetL = iconSize + ICON_PADDING
        end
    end

    frame.bgBar:ClearAllPoints()
    frame.bgBar:SetPoint("TOPLEFT", frame, "TOPLEFT", barOffsetL, 0)
    frame.bgBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", barOffsetR, 0)

    -- Textures
    local texPath = Media and Media:GetStatusBarTexture(config.barTexture) or "Interface\\TargetingFrame\\UI-StatusBar"
    frame.bgBar:SetStatusBarTexture(texPath)
    frame.bar:SetStatusBarTexture(texPath)

    -- Colors
    local bgc = config.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
    frame.bgBar:SetStatusBarColor(bgc.r, bgc.g, bgc.b, bgc.a)

    local bc = config.barColor or { r = 0.26, g = 0.65, b = 1.0, a = 1.0 }
    frame.bar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)

    local bdc = config.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    frame.barBorder:SetColorTexture(bdc.r, bdc.g, bdc.b, bdc.a)

    -- Fill direction
    if config.fillDirection == "REVERSE" then
        StatusBarAPI:SetFillStyle(frame.bar, "REVERSE")
    else
        StatusBarAPI:SetFillStyle(frame.bar, "STANDARD")
    end

    -- Text
    frame.nameText:SetFont(STANDARD_TEXT_FONT, config.nameFontSize or 11, "OUTLINE")
    frame.nameText:SetText(config.name or "")
    frame.nameText:SetShown(config.showName ~= false)

    frame.timeText:SetFont(STANDARD_TEXT_FONT, config.timeFontSize or 11, "OUTLINE")
    frame.timeText:SetShown(config.showTime ~= false)

    -- Layout overlay label
    local overlayLabel = (config.name or ("Spell " .. (spellID or "?"))) .. " " .. BarsData.TypeLabel(config.type)
    frame.layoutOverlayText:SetText(overlayLabel)
end

-- Update a single bar's timer display from data state
function BarsFrames:UpdateBarDisplay(barKey)
    local frame = barFrames[barKey]
    if not frame then return end

    local config = BarsData:GetSpellConfig(barKey)
    if not config or not config.enabled then
        frame:Hide()
        return
    end

    local state = BarsData:GetSpellState(barKey)

    -- Layout mode: always show with placeholder fill
    if isLayoutMode then
        frame:Show()
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(0.65)
        frame.timeText:SetText("12s")
        return
    end

    -- Determine visibility
    local shouldShow = false
    if state and state.isActive then
        shouldShow = true
    elseif config.showWhenReady then
        shouldShow = true
    end

    if not shouldShow then
        frame:Hide()
        return
    end

    frame:Show()

    -- Apply timer from duration object
    if state and state.isActive and state.durationObj then
        local timerDirection = StatusBarAPI.TIMER_DIRECTION.REMAINING
        if config.fillDirection == "ELAPSED" then
            timerDirection = nil
        end

        pcall(function()
            StatusBarAPI:SetTimerDuration(frame.bar, state.durationObj, nil, timerDirection)
        end)

        if config.showTime ~= false then
            pcall(function()
                local timeStr = DurationAPI:Format(state.durationObj)
                frame.timeText:SetText(timeStr or "")
            end)
        end
    else
        -- Ready state
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(1)
        frame.timeText:SetText("Ready")
    end
end

-- ============================================================================
-- TIME TEXT UPDATE TICKER
-- ============================================================================

local textTicker = nil

local function IsTimeStringEmpty(timeStr)
    if timeStr == nil then return true end
    if issecretvalue and issecretvalue(timeStr) then
        return false
    end
    return timeStr == ""
end

local function UpdateAllTimeText()
    for barKey, frame in pairs(barFrames) do
        if frame:IsShown() and not isLayoutMode then
            local config = BarsData:GetSpellConfig(barKey)
            local state = BarsData:GetSpellState(barKey)
            if config and state then
                if state.isActive and state.durationObj then
                    if config.showTime ~= false then
                        local ok, timeStr = pcall(function()
                            return DurationAPI:Format(state.durationObj)
                        end)
                        if ok then
                            frame.timeText:SetText(timeStr or "")
                            -- Detect expiration via time string
                            -- (SPELL_UPDATE_COOLDOWN may lag slightly)
                            if IsTimeStringEmpty(timeStr) then
                                state.isActive = false
                                state.durationObj = nil
                                if config.showWhenReady then
                                    frame.bar:SetMinMaxValues(0, 1)
                                    frame.bar:SetValue(1)
                                    frame.timeText:SetText("Ready")
                                else
                                    frame:Hide()
                                end
                            end
                        end
                    end
                elseif not state.isActive and not config.showWhenReady then
                    frame:Hide()
                end
            end
        end
    end
end

function BarsFrames:StartTextTicker()
    if textTicker then return end
    textTicker = C_Timer.NewTicker(0.1, UpdateAllTimeText)
end

function BarsFrames:StopTextTicker()
    if textTicker then
        textTicker:Cancel()
        textTicker = nil
    end
end

-- ============================================================================
-- CREATE/DESTROY LIFECYCLE
-- ============================================================================

function BarsFrames:CreateBar(barKey)
    local frame = CreateBarFrame(barKey)
    if not frame then return nil end

    -- Load saved position or set default
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

    -- Register with Layout system
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

    return frame
end

function BarsFrames:DestroyBar(barKey)
    local frame = barFrames[barKey]
    if not frame then return end

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
    for barKey, frame in pairs(barFrames) do
        frame:EnableMouse(true)
        frame:Show()
        frame.layoutOverlay:Show()
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(0.65)
        frame.timeText:SetText("12s")
    end
end

function BarsFrames:ExitLayoutMode()
    isLayoutMode = false
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

    if config.enabled then
        if not barFrames[barKey] then
            self:CreateBar(barKey)
        end
        if barFrames[barKey] then
            self:ApplyConfig(barKey)
            self:UpdateBarDisplay(barKey)
            BarsData:UpdateCooldownState(barKey)
        end
    else
        if barFrames[barKey] then
            self:DestroyBar(barKey)
        end
    end
end

return BarsFrames
