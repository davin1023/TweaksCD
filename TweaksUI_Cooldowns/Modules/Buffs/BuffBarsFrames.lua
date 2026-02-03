-- ============================================================================
-- TUICD: Buff Timer Bars - Frame Layer
-- Creates and manages visual timer bar frames for tracked buff slots
-- Each bar: [Icon] [StatusBar Fill] [NameText] [TimeText]
--
-- Uses BuffBarsData for state (duration/expirationTime in seconds)
-- Manual OnUpdate drain: remaining = expirationTime - GetTime()
-- No DurationObject dependency (API not available on current Midnight build)
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BuffBarsFrames = TUICD.BuffBarsFrames or {}
local BuffBarsFrames = TUICD.BuffBarsFrames

local BuffBarsData  -- resolved lazily (load order)
local SpellAPI      -- resolved lazily
local Media         -- resolved lazily

local function GetData()
    if not BuffBarsData then BuffBarsData = TUICD.BuffBarsData end
    return BuffBarsData
end

local function GetSpellAPI()
    if not SpellAPI then SpellAPI = TUICD.SpellAPI end
    return SpellAPI
end

local function GetMedia()
    if not Media then Media = TUICD.Media end
    return Media
end

-- Forward ref for dock integration
local function GetDock()
    return TUICD.BuffBarsDock
end

-- ============================================================================
-- COLOR-BY-TIME SUPPORT
-- Uses cached non-secret milliseconds + GetTime() math (same as Bars module)
-- This pattern works reliably in combat - no secret value issues
-- ============================================================================

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DEFAULT_WIDTH     = 200
local DEFAULT_HEIGHT    = 20
local ICON_PADDING      = 2
local BAR_BORDER_SIZE   = 1
local DEFAULT_STRATA    = "MEDIUM"
local DEFAULT_LEVEL     = 50
local TEXT_UPDATE_HZ    = 0.05  -- 20Hz for smooth countdown + drain

-- ============================================================================
-- STATE
-- ============================================================================

local barFrames = {}    -- [barKey] = frame
local isLayoutMode = false

-- ============================================================================
-- HELPERS
-- ============================================================================

-- Format seconds into readable time string
local function FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = math.floor(seconds % 60)
        return string.format("%d:%02d", m, s)
    elseif seconds >= 10 then
        return string.format("%d", math.floor(seconds))
    else
        return string.format("%.1f", seconds)
    end
end

-- Secret-safe time formatting for Midnight combat
-- Uses string.format which accepts secrets (returns secret string)
-- No comparisons or arithmetic - just pass through with basic format
local function FormatTimeSecret(seconds)
    if seconds == nil then return "" end
    -- string.format works with secrets per Midnight API
    -- Use simple decimal format - can't do mm:ss without comparisons
    local success, result = pcall(string.format, "%.0f", seconds)
    if success then
        return result
    end
    return ""
end

-- Resolve font path from config or fallback
local function ResolveFontPath(config)
    if config.fontPath then return config.fontPath end
    local media = GetMedia()
    if media and config.fontName then
        local path = media:GetFontPath(config.fontName)
        if path then return path end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- Compute icon dimensions (icons are always square, sized to bar height)
local function ComputeIconSize(config, barHeight)
    if not config.showIcon then return 0 end
    if config.iconSize and config.iconSize > 0 then
        return config.iconSize
    end
    return barHeight  -- Match bar height by default
end

-- Color-by-time: lerp between 3 colors based on remaining seconds
local function LerpValue(a, b, t)
    return a + (b - a) * t
end

local function GetTimeBasedColor(remaining, config)
    local highSec = config.colorHighSeconds or 10
    local medSec  = config.colorMedSeconds or 5
    local cHigh = config.colorHigh or { r = 0.2, g = 0.8, b = 0.2 }  -- Green (lots of time)
    local cMed  = config.colorMed  or { r = 1.0, g = 0.8, b = 0.0 }  -- Yellow (some time)
    local cLow  = config.colorLow  or { r = 1.0, g = 0.2, b = 0.2 }  -- Red (expiring)

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

-- Calculate remaining seconds from cached non-secret milliseconds
-- This matches the pattern from working Bars module - works in combat!
local function GetRemainingFromState(state)
    if state.startMs and state.durationMs then
        local endSec = (state.startMs + state.durationMs) / 1000
        return endSec - GetTime()
    elseif state.expirationTime and type(state.expirationTime) == "number" then
        return state.expirationTime - GetTime()
    end
    return nil
end

-- Border helpers (4-texture border)
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
-- EFFECTIVE CONFIG
-- Build a merged config from global bar defaults + per-spell overrides
-- ============================================================================

local GLOBAL_DEFAULTS = {
    width           = 200,
    height          = 20,
    barColor        = { r = 0.26, g = 0.65, b = 1.0, a = 1.0 },
    backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
    borderColor     = { r = 0, g = 0, b = 0, a = 1 },
    barTexture      = "Blizzard",
    showBorder      = true,
    showIcon        = true,
    iconPosition    = "LEFT",
    iconAspect      = "1:1",
    iconSizeMode    = "auto",
    iconSize        = 0,       -- 0 = auto (match bar height)
    showName        = true,
    showTime        = true,
    nameFontSize    = 11,
    timeFontSize    = 11,
    font            = nil,
    barDirection    = "RIGHT",
    fillMode        = "drain",
    showWhenInactive = false,
    colorByTime     = false,
    colorHighSeconds = 10,
    colorMedSeconds  = 5,
    colorHigh       = { r = 0.2, g = 0.8, b = 0.2 },
    colorMed        = { r = 1.0, g = 0.8, b = 0.0 },
    colorLow        = { r = 1.0, g = 0.2, b = 0.2 },
    nameOffsetX     = 0,
    nameOffsetY     = 0,
    timeOffsetX     = 0,
    timeOffsetY     = 0,
}

local function GetEffectiveConfig(barKey)
    local data = GetData()
    if not data then return GLOBAL_DEFAULTS end

    local spellConfig = data:GetSpellConfig(barKey)
    if not spellConfig then return GLOBAL_DEFAULTS end

    -- Read global overrides from DB (dockSettings contains shared bar settings)
    local db = data:GetDB()
    local globals = db and db.dockSettings or {}

    -- Merge: spell overrides > global overrides > hardcoded defaults
    local cfg = {}
    for k, v in pairs(GLOBAL_DEFAULTS) do
        local spellVal = spellConfig[k]
        if spellVal ~= nil then
            cfg[k] = spellVal
        else
            local globalVal = globals[k]
            if globalVal ~= nil then
                cfg[k] = globalVal
            else
                cfg[k] = v
            end
        end
    end

    -- Always pull these from spell config directly
    cfg.name      = spellConfig.name
    cfg.texture   = spellConfig.texture
    cfg.iconID    = spellConfig.iconID or spellConfig.texture
    cfg.enabled   = spellConfig.enabled
    cfg.type      = spellConfig.type
    cfg.slotIndex = spellConfig.slotIndex

    return cfg
end

-- ============================================================================
-- BAR FRAME CREATION
-- ============================================================================

local function CreateBarFrame(barKey)
    if barFrames[barKey] then return barFrames[barKey] end

    local config = GetEffectiveConfig(barKey)
    if not config then return nil end

    local data = GetData()
    local slotIndex = data and data.ParseBarKey(barKey)
    local safeKey = barKey:gsub("[^%w]", "_")
    local frameName = "TUICD_BuffBar_" .. safeKey

    local width  = config.width or DEFAULT_WIDTH
    local height = config.height or DEFAULT_HEIGHT
    local iconSize = ComputeIconSize(config, height)
    local showIcon = config.showIcon and iconSize > 0
    local totalWidth = width + (showIcon and (iconSize + ICON_PADDING) or 0)

    -- ========================================
    -- Main container
    -- ========================================
    local frame = CreateFrame("Frame", frameName, UIParent)
    frame:SetSize(totalWidth, height)
    frame:SetFrameStrata(DEFAULT_STRATA)
    frame:SetFrameLevel(DEFAULT_LEVEL)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame.barKey = barKey
    frame.slotIndex = slotIndex

    -- ========================================
    -- Icon
    -- ========================================
    local icon = frame:CreateTexture(frameName .. "_Icon", "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    frame.icon = icon

    if showIcon then
        if config.iconPosition == "RIGHT" then
            icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        else
            icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        end
        -- Zoom crop for square icon in potentially non-square display
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(config.iconID or 134400)
    else
        icon:Hide()
    end

    -- Icon border
    local iconBorder = frame:CreateTexture(frameName .. "_IconBdr", "BACKGROUND")
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -BAR_BORDER_SIZE, BAR_BORDER_SIZE)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", BAR_BORDER_SIZE, -BAR_BORDER_SIZE)
    iconBorder:SetColorTexture(0, 0, 0, 1)
    iconBorder:SetShown(showIcon)
    frame.iconBorder = iconBorder

    -- ========================================
    -- Status bar region
    -- ========================================
    local barOffsetL = showIcon and (config.iconPosition ~= "RIGHT") and (iconSize + ICON_PADDING) or 0

    -- Background frame
    local bgBar = CreateFrame("Frame", frameName .. "_BG", frame)
    bgBar:SetPoint("LEFT", frame, "LEFT", barOffsetL, 0)
    bgBar:SetSize(width, height)
    frame.bgBar = bgBar

    local bgColorTex = bgBar:CreateTexture(nil, "BACKGROUND")
    bgColorTex:SetAllPoints()
    local bgc = config.backgroundColor
    bgColorTex:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 0.8)
    bgBar.colorTex = bgColorTex

    -- 4-edge border
    local bc = config.borderColor
    local borderTop = frame:CreateTexture(nil, "BACKGROUND")
    borderTop:SetPoint("TOPLEFT", bgBar, "TOPLEFT", -BAR_BORDER_SIZE, BAR_BORDER_SIZE)
    borderTop:SetPoint("TOPRIGHT", bgBar, "TOPRIGHT", BAR_BORDER_SIZE, BAR_BORDER_SIZE)
    borderTop:SetHeight(BAR_BORDER_SIZE)
    borderTop:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    local borderBot = frame:CreateTexture(nil, "BACKGROUND")
    borderBot:SetPoint("BOTTOMLEFT", bgBar, "BOTTOMLEFT", -BAR_BORDER_SIZE, -BAR_BORDER_SIZE)
    borderBot:SetPoint("BOTTOMRIGHT", bgBar, "BOTTOMRIGHT", BAR_BORDER_SIZE, -BAR_BORDER_SIZE)
    borderBot:SetHeight(BAR_BORDER_SIZE)
    borderBot:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    local borderL = frame:CreateTexture(nil, "BACKGROUND")
    borderL:SetPoint("TOPLEFT", bgBar, "TOPLEFT", -BAR_BORDER_SIZE, 0)
    borderL:SetPoint("BOTTOMLEFT", bgBar, "BOTTOMLEFT", -BAR_BORDER_SIZE, 0)
    borderL:SetWidth(BAR_BORDER_SIZE)
    borderL:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    local borderR = frame:CreateTexture(nil, "BACKGROUND")
    borderR:SetPoint("TOPRIGHT", bgBar, "TOPRIGHT", BAR_BORDER_SIZE, 0)
    borderR:SetPoint("BOTTOMRIGHT", bgBar, "BOTTOMRIGHT", BAR_BORDER_SIZE, 0)
    borderR:SetWidth(BAR_BORDER_SIZE)
    borderR:SetColorTexture(bc.r, bc.g, bc.b, bc.a)

    frame.barBorder = { borderTop, borderBot, borderL, borderR }

    -- Fill bar (StatusBar)
    local bar = CreateFrame("StatusBar", frameName .. "_Fill", bgBar)
    bar:SetAllPoints()
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    frame.bar = bar

    local media = GetMedia()
    local texPath = (media and media.GetStatusBarTexture and media:GetStatusBarTexture(config.barTexture))
        or "Interface\\TargetingFrame\\UI-StatusBar"
    bar:SetStatusBarTexture(texPath)
    bar:SetStatusBarColor(config.barColor.r, config.barColor.g, config.barColor.b, config.barColor.a)

    -- ========================================
    -- Text overlays (on separate high-level frame to ensure visibility)
    -- ========================================
    local fontPath = ResolveFontPath(config)
    
    -- Create a text container frame at higher level than the bars
    local textFrame = CreateFrame("Frame", frameName .. "_TextFrame", frame)
    textFrame:SetAllPoints(bar)
    textFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
    frame.textFrame = textFrame

    local nameText = textFrame:CreateFontString(frameName .. "_Name", "OVERLAY")
    nameText:SetFontObject(GameFontNormal)
    nameText:SetFont(fontPath, config.nameFontSize or 11, "OUTLINE")
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetJustifyV("MIDDLE")
    nameText:SetWordWrap(false)
    nameText:SetText(config.name or "")
    if config.showName ~= false then
        nameText:Show()
    else
        nameText:Hide()
    end
    frame.nameText = nameText

    local timeText = textFrame:CreateFontString(frameName .. "_Time", "OVERLAY")
    timeText:SetFontObject(GameFontNormal)
    timeText:SetFont(fontPath, config.timeFontSize or 11, "OUTLINE")
    timeText:SetTextColor(1, 1, 1, 1)
    timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timeText:SetJustifyH("RIGHT")
    timeText:SetJustifyV("MIDDLE")
    timeText:SetWordWrap(false)
    timeText:SetText("")
    if config.showTime ~= false then
        timeText:Show()
    else
        timeText:Hide()
    end
    frame.timeText = timeText

    -- ========================================
    -- Layout mode overlay
    -- ========================================
    local overlay = CreateFrame("Frame", frameName .. "_LO", frame)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
    overlay:Hide()

    local overlayTex = overlay:CreateTexture(nil, "OVERLAY")
    overlayTex:SetAllPoints()
    overlayTex:SetColorTexture(0, 0.5, 1, 0.3)

    local overlayLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlayLabel:SetPoint("CENTER")
    overlayLabel:SetText((config.name or barKey) .. " (buff)")
    overlayLabel:SetTextColor(1, 1, 1, 1)

    frame.layoutOverlay = overlay
    frame.layoutOverlayText = overlayLabel

    -- ========================================
    -- Drag handling
    -- ========================================
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if isLayoutMode then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        local data = GetData()
        if data then data:SetSpellPosition(self.barKey, point, x, y) end
    end)

    -- ========================================
    -- Initial state: hidden
    -- ========================================
    frame:Hide()

    barFrames[barKey] = frame
    return frame
end

-- ============================================================================
-- APPLY CONFIG (rebuild visuals from settings without recreating frame)
-- ============================================================================

function BuffBarsFrames:ApplyConfig(barKey)
    local frame = barFrames[barKey]
    if not frame then return end

    local config = GetEffectiveConfig(barKey)
    if not config then return end

    local width  = config.width or DEFAULT_WIDTH
    local height = config.height or DEFAULT_HEIGHT
    local iconSize = ComputeIconSize(config, height)
    local showIcon = config.showIcon and iconSize > 0
    local totalWidth = width + (showIcon and (iconSize + ICON_PADDING) or 0)

    frame:SetSize(totalWidth, height)

    -- Icon
    frame.icon:SetSize(iconSize, iconSize)
    if showIcon then
        frame.icon:ClearAllPoints()
        if config.iconPosition == "RIGHT" then
            frame.icon:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        else
            frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        end
        frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        frame.icon:SetTexture(config.iconID or 134400)
        frame.icon:Show()
        frame.iconBorder:Show()
    else
        frame.icon:Hide()
        frame.iconBorder:Hide()
    end

    -- Bar region
    local barOffsetL = showIcon and (config.iconPosition ~= "RIGHT") and (iconSize + ICON_PADDING) or 0
    frame.bgBar:ClearAllPoints()
    frame.bgBar:SetPoint("LEFT", frame, "LEFT", barOffsetL, 0)
    frame.bgBar:SetSize(width, height)

    -- Textures & colors
    local media = GetMedia()
    local texPath = (media and media.GetStatusBarTexture and media:GetStatusBarTexture(config.barTexture))
        or "Interface\\TargetingFrame\\UI-StatusBar"
    frame.bar:SetStatusBarTexture(texPath)
    frame.bar:SetStatusBarColor(config.barColor.r, config.barColor.g, config.barColor.b, config.barColor.a or 1)

    local bgc = config.backgroundColor
    if frame.bgBar.colorTex then
        frame.bgBar.colorTex:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 0.8)
    end

    local bdc = config.borderColor
    SetBorderColor(frame.barBorder, bdc.r, bdc.g, bdc.b, bdc.a or 1)

    -- Text
    local fontPath = ResolveFontPath(config)
    frame.nameText:SetFont(fontPath, config.nameFontSize or 11, "OUTLINE")
    frame.nameText:SetText(config.name or "")
    frame.nameText:SetShown(config.showName ~= false)

    frame.timeText:SetFont(fontPath, config.timeFontSize or 11, "OUTLINE")
    frame.timeText:SetShown(config.showTime ~= false)
end

-- ============================================================================
-- POSITION MANAGEMENT
-- ============================================================================

local function RestorePosition(barKey, frame)
    local data = GetData()
    if not data then return end

    local pos = data:GetSpellPosition(barKey)
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    else
        -- Default position: stagger bars vertically
        local slotIndex = data.ParseBarKey(barKey) or 1
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100 - (slotIndex - 1) * 28)
    end
end

-- ============================================================================
-- OnUpdate TIMER: Drain bar fill + update time text + color-by-time
-- Runs at 20Hz, auto-stops when no active bars
-- ============================================================================

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
local timerElapsed = 0

timerFrame:SetScript("OnUpdate", function(self, elapsed)
    timerElapsed = timerElapsed + elapsed
    if timerElapsed < TEXT_UPDATE_HZ then return end
    timerElapsed = 0

    local anyActive = false

    for barKey, frame in pairs(barFrames) do
        if frame:IsShown() and not isLayoutMode then
            local data = GetData()
            local state = data and data:GetSpellState(barKey)

            -- Check if buff is still active via auraInstanceID (non-secret)
            if state and state.isActive and state.auraInstanceID then
                anyActive = true
                local config = GetEffectiveConfig(barKey)

                -- BAR FILL UPDATE:
                -- - If using SetTimerDuration, bar auto-animates (nothing to do)
                -- - If manual mode, we need to update SetValue (outside combat only)
                if frame._manualBarUpdate and not InCombatLockdown() then
                    if state.expirationTime and state.duration and state.duration > 0 then
                        local remaining = state.expirationTime - GetTime()
                        if remaining > 0 then
                            local pct = math.min(1, math.max(0, remaining / state.duration))
                            frame.bar:SetValue(pct)
                        else
                            -- Buff expired
                            frame:Hide()
                            frame._usingTimerDuration = false
                            frame._manualBarUpdate = false
                            local dock = GetDock()
                            if dock then dock:OnBarHidden(barKey) end
                        end
                    end
                end

                -- TIME TEXT UPDATE: Use Duration Object + SetFormattedText (works with secrets)
                if config and config.showTime ~= false then
                    if C_UnitAuras then
                        local getAuraDurationFunc = C_UnitAuras.GetAuraDuration or C_UnitAuras.GetUnitAuraDuration
                        if getAuraDurationFunc and state.auraInstanceID then
                            pcall(function()
                                local durationObj = getAuraDurationFunc("player", state.auraInstanceID)
                                if durationObj and durationObj.GetRemainingDuration then
                                    local remaining = durationObj:GetRemainingDuration()
                                    frame.timeText:SetFormattedText("%.1f", remaining)
                                end
                            end)
                        end
                    end
                end
                
                -- COLOR-BY-TIME UPDATE: Uses cached non-secret milliseconds
                -- Same pattern as working Bars module - works in combat!
                if config and config.colorByTime then
                    local rem = GetRemainingFromState(state)
                    if rem and rem > 0 then
                        local r, g, b = GetTimeBasedColor(rem, config)
                        frame.bar:SetStatusBarColor(r, g, b)
                    end
                end
            elseif frame:IsShown() then
                -- Buff no longer active but frame still shown - data poll will handle hiding
                -- Just keep tracking for now
                anyActive = true
            end
        end
    end

    if not anyActive then
        self:Hide()
    end
end)

local function EnsureTimerRunning()
    if not timerFrame:IsShown() then
        timerElapsed = 0
        timerFrame:Show()
    end
end

function BuffBarsFrames:StopTimer()
    timerFrame:Hide()
end

-- Called by UI when a setting changes - reapply config and update display
function BuffBarsFrames:OnConfigChanged(barKey)
    self:ApplyConfig(barKey)
    self:UpdateBarDisplay(barKey)
end

-- ============================================================================
-- DISPLAY UPDATE (called from data callbacks)
-- ============================================================================

function BuffBarsFrames:UpdateBarDisplay(barKey)
    local frame = barFrames[barKey]
    local data = GetData()
    if not data then return end

    local config = GetEffectiveConfig(barKey)
    if not config or not config.enabled then
        if frame and frame:IsShown() then
            frame:Hide()
            local dock = GetDock()
            if dock then dock:OnBarHidden(barKey) end
        end
        return
    end

    -- Create frame on demand
    if not frame then
        frame = CreateBarFrame(barKey)
        if not frame then return end
        RestorePosition(barKey, frame)
    end

    local state = data:GetSpellState(barKey)

    -- Layout mode: always show with placeholder
    if isLayoutMode then
        frame:Show()
        frame.bgBar:Show()
        ShowBorder(frame.barBorder)
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(0.65)
        frame.nameText:SetText(config.name or barKey)
        frame.timeText:SetText("12s")
        frame.layoutOverlay:Show()
        frame:EnableMouse(true)
        return
    end

    -- Normal mode
    frame.layoutOverlay:Hide()
    frame:EnableMouse(false)

    if state and state.isActive and state.auraInstanceID then
        -- Active buff: use Duration Object for combat-safe display
        local wasShown = frame:IsShown()
        
        frame:Show()
        frame.bgBar:Show()
        ShowBorder(frame.barBorder)

        if not wasShown then
            local dock = GetDock()
            if dock then dock:OnBarShown(barKey) end
        end

        -- Restore background + border from possible inactive dimming
        local bgc = config.backgroundColor
        if frame.bgBar.colorTex and bgc then
            frame.bgBar.colorTex:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 0.8)
        end
        local bdc = config.borderColor
        if bdc then
            SetBorderColor(frame.barBorder, bdc.r, bdc.g, bdc.b, bdc.a or 1)
        end

        -- ALWAYS update timer bar from current Duration Object on every poll
        -- ElkBuffBars does this on every OnUpdate - SetTimerDuration handles refresh internally
        if C_UnitAuras then
            local getAuraDurationFunc = C_UnitAuras.GetAuraDuration or C_UnitAuras.GetUnitAuraDuration
            if getAuraDurationFunc then
                pcall(function()
                    local durationObj = getAuraDurationFunc("player", state.auraInstanceID)
                    if durationObj and frame.bar.SetTimerDuration then
                        frame.bar:SetTimerDuration(durationObj, nil, Enum.StatusBarTimerDirection.RemainingTime)
                        frame._usingTimerDuration = true
                        frame._manualBarUpdate = false
                    end
                end)
            end
        end
        
        -- FALLBACK: Manual bar updates (pre-Midnight or API failure)
        if not frame._usingTimerDuration then
            frame.bar:SetMinMaxValues(0, 1)
            frame._manualBarUpdate = true
            
            -- Set initial value if possible (outside combat only)
            if not InCombatLockdown() and state.expirationTime and state.duration and state.duration > 0 then
                local remaining = state.expirationTime - GetTime()
                local pct = math.min(1, math.max(0, remaining / state.duration))
                frame.bar:SetValue(pct)
            else
                frame.bar:SetValue(1)
            end
        end
        
        -- For manual mode: update bar on every poll (handled by OnUpdate timer)

        -- Update icon texture (may have been resolved lazily)
        if config.showIcon and config.iconID then
            frame.icon:SetTexture(config.iconID)
            frame.icon:SetDesaturated(false)
            frame.icon:SetAlpha(1)
        end

        -- Update name text (may have been resolved from "Buff Slot N")
        if config.showName ~= false then
            frame.nameText:SetText(config.name or "")
            frame.nameText:SetAlpha(1)
        end

        -- Time text: update every cycle using Duration Object + SetFormattedText
        if config.showTime ~= false then
            if C_UnitAuras and state.auraInstanceID then
                local getAuraDurationFunc = C_UnitAuras.GetAuraDuration or C_UnitAuras.GetUnitAuraDuration
                if getAuraDurationFunc then
                    pcall(function()
                        local durationObj = getAuraDurationFunc("player", state.auraInstanceID)
                        if durationObj and durationObj.GetRemainingDuration then
                            local remaining = durationObj:GetRemainingDuration()
                            frame.timeText:SetFormattedText("%.1f", remaining)
                        end
                    end)
                end
            end
        end

        -- Bar color: colorByTime uses cached milliseconds for combat-safe calculations
        -- Same pattern as working Bars module - no secret value issues
        if config.colorByTime then
            local rem = GetRemainingFromState(state)
            if rem and rem > 0 then
                local r, g, b = GetTimeBasedColor(rem, config)
                frame.bar:SetStatusBarColor(r, g, b)
            else
                -- Fallback to static color if no timing data
                frame.bar:SetStatusBarColor(config.barColor.r, config.barColor.g, config.barColor.b)
            end
        else
            -- Static color
            frame.bar:SetStatusBarColor(config.barColor.r, config.barColor.g, config.barColor.b)
        end

        -- Start timer for time text updates
        EnsureTimerRunning()
    else
        -- Inactive
        if config.showWhenInactive then
            -- Show frame in inactive/ready state (like cooldown bars showWhenReady)
            local wasShown = frame:IsShown()
            frame:Show()

            if not wasShown then
                local dock = GetDock()
                if dock then dock:OnBarShown(barKey) end
            end

            -- Keep bgBar VISIBLE (bar/text are children of it!)
            -- Just dim everything to show "not active" state
            frame.bgBar:Show()
            ShowBorder(frame.barBorder)
            SetBorderColor(frame.barBorder, 0.15, 0.15, 0.15, 0.6)

            -- Empty/full bar in muted color
            frame.bar:SetMinMaxValues(0, 1)
            frame.bar:SetValue(0)
            frame.bar:SetStatusBarColor(0.3, 0.3, 0.3, 0.5)
            frame._usingTimerDuration = false
            frame._manualBarUpdate = false

            -- Dim the background
            if frame.bgBar.colorTex then
                frame.bgBar.colorTex:SetColorTexture(0.05, 0.05, 0.05, 0.5)
            end

            -- Show icon dimmed
            if config.showIcon and config.iconID then
                frame.icon:SetTexture(config.iconID)
                frame.icon:SetDesaturated(true)
                frame.icon:SetAlpha(0.5)
            end

            -- Show name dimmed
            if config.showName ~= false then
                frame.nameText:SetText(config.name or "")
                frame.nameText:SetAlpha(0.5)
            end

            -- Clear time text
            frame.timeText:SetText("")

        else
            -- Hide completely
            if frame:IsShown() then
                frame:Hide()
                frame._usingTimerDuration = false
                frame._manualBarUpdate = false
                local dock = GetDock()
                if dock then dock:OnBarHidden(barKey) end
            end
        end
    end
end

-- ============================================================================
-- LAYOUT MODE
-- ============================================================================

function BuffBarsFrames:SetLayoutMode(enabled)
    isLayoutMode = enabled

    local data = GetData()
    if not data then return end

    for barKey, config in pairs(data:GetTrackedSpells()) do
        if config.enabled then
            if enabled then
                -- Show all bars in layout mode
                self:UpdateBarDisplay(barKey)
            else
                -- Return to normal display
                local frame = barFrames[barKey]
                if frame then
                    frame.layoutOverlay:Hide()
                    frame:EnableMouse(false)
                end
                self:UpdateBarDisplay(barKey)
            end
        end
    end
end

function BuffBarsFrames:IsLayoutMode()
    return isLayoutMode
end

-- ============================================================================
-- FRAME ACCESS
-- ============================================================================

function BuffBarsFrames:GetBarFrame(barKey)
    return barFrames[barKey]
end

function BuffBarsFrames:GetAllBarFrames()
    return barFrames
end

-- Destroy a bar frame (used when removing a slot)
function BuffBarsFrames:DestroyBar(barKey)
    local frame = barFrames[barKey]
    if frame then
        frame:Hide()
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        barFrames[barKey] = nil
    end
end

-- Destroy all bar frames (used on disable)
function BuffBarsFrames:DestroyAll()
    for barKey, frame in pairs(barFrames) do
        frame:Hide()
    end
    wipe(barFrames)
    timerFrame:Hide()
end

-- ============================================================================
-- INITIALIZATION (connects to BuffBarsData callbacks)
-- ============================================================================

function BuffBarsFrames:Initialize()
    local data = GetData()
    if not data then
        -- Retry after a short delay (load order)
        C_Timer.After(0.5, function() self:Initialize() end)
        return
    end

    -- Register for data updates
    data:RegisterUpdateCallback("BuffBarsFrames", function(barKey)
        self:UpdateBarDisplay(barKey)
    end)

    -- Create frames for any already-enabled bars
    for barKey, config in pairs(data:GetTrackedSpells()) do
        if config.enabled then
            if not barFrames[barKey] then
                local frame = CreateBarFrame(barKey)
                if frame then
                    RestorePosition(barKey, frame)
                end
            end
            self:UpdateBarDisplay(barKey)
        end
    end
end

-- ============================================================================
-- SLASH COMMAND EXTENSION
-- ============================================================================

function BuffBarsFrames:HandleSlashCommand(args)
    local cmd = args and args:lower() or ""

    if cmd == "layout" then
        isLayoutMode = not isLayoutMode
        self:SetLayoutMode(isLayoutMode)
        TUICD:Print("Buff bars layout mode: " .. (isLayoutMode and "|cff00ff00ON|r" or "|cff888888OFF|r"))

    elseif cmd == "show" then
        -- Force show all enabled bars (debug)
        local data = GetData()
        if data then
            for barKey, config in pairs(data:GetTrackedSpells()) do
                if config.enabled then
                    local frame = barFrames[barKey] or CreateBarFrame(barKey)
                    if frame then
                        RestorePosition(barKey, frame)
                        frame:Show()
                        frame.bgBar:Show()
                        ShowBorder(frame.barBorder)
                        frame.bar:SetMinMaxValues(0, 1)
                        frame.bar:SetValue(0.75)
                        frame.nameText:SetText(config.name or barKey)
                        frame.timeText:SetText("8.5")
                    end
                end
            end
        end
        TUICD:Print("Showing all enabled buff bars (debug)")

    elseif cmd == "hide" then
        for _, frame in pairs(barFrames) do
            frame:Hide()
        end
        TUICD:Print("Hidden all buff bars")

    else
        return false  -- Not handled
    end
    return true
end

return BuffBarsFrames
