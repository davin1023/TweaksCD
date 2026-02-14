-- ============================================================================
-- TUICD: Buff Bars - Settings UI
-- Spell list + per-spell bar configuration panel
-- Pattern: list on left, scrollable config on right with tabs
-- Mirrors BarsUI.lua structure for cooldown bars
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BuffBarsUI = TUICD.BuffBarsUI or {}
local BuffBarsUI = TUICD.BuffBarsUI

local BuffBarsData   = TUICD.BuffBarsData
local BuffBarsFrames = TUICD.BuffBarsFrames
local Media          = TUICD.Media

-- ============================================================================
-- STATE
-- ============================================================================

local mainPanel       = nil
local selectedBarKey  = nil
local spellButtons    = {}
local configFrame     = nil
local configScrollChild = nil
local dockScrollChild = nil
local activePopup     = nil
local activeTab       = "spell"   -- "spell" or "dock"
local tabButtons      = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH     = 540
local PANEL_HEIGHT    = 665
local LIST_WIDTH      = 170
local CONFIG_WIDTH    = 340
local BUTTON_HEIGHT   = 28
local BUTTON_SPACING  = 2
local SECTION_SPACING = 12
local CONTROL_WIDTH   = CONFIG_WIDTH - 50

-- Icon aspect labels (BuffBarsData only stores {w,h})
local ICON_ASPECT_ORDER = { "1:1", "4:3", "3:4", "16:9", "9:16", "2:1", "1:2" }
local ICON_ASPECT_LABELS = {
    ["1:1"]  = "1:1 (Square)",
    ["4:3"]  = "4:3",
    ["3:4"]  = "3:4",
    ["16:9"] = "16:9 (Wide)",
    ["9:16"] = "9:16 (Tall)",
    ["2:1"]  = "2:1",
    ["1:2"]  = "1:2",
}

-- ============================================================================
-- WIDGET HELPERS
-- (Identical to BarsUI.lua — self-contained for modularity)
-- ============================================================================

local function CreateSectionLabel(parent, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(CONTROL_WIDTH, 16)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText("|cffaaaaaa-- " .. text .. " --|r")
    frame._label = label
    return frame
end

-- Module-level drag state: survives panel rebuilds that destroy/recreate overlays
local activeDrag = {
    sliderLabel = nil,
    min = 0,
    max = 1,
    step = 1,
    onChange = nil,
    slider = nil,
    overlay = nil,
}

local function CreateSlider(parent, label, min, max, step, width, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or CONTROL_WIDTH, 40)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -15)
    slider:SetSize((width or CONTROL_WIDTH) - 60, 17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText("")
    slider.High:SetText("")
    slider:EnableMouse(false)

    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)

    slider._suppress = false

    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        valueText:SetText(tostring(val))
        if not self._suppress and onChange then onChange(val) end
    end)

    -- Overlay handles all mouse for this slider
    local overlay = CreateFrame("Frame", nil, container)
    overlay:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, 8)
    overlay:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, -8)
    overlay:SetFrameLevel(slider:GetFrameLevel() + 10)
    overlay:EnableMouse(true)

    local function UpdateFromCursor()
        local targetSlider = activeDrag.slider or slider
        local cx = GetCursorPosition()
        local scale = targetSlider:GetEffectiveScale()
        local left = targetSlider:GetLeft()
        local w = targetSlider:GetWidth()
        if not left or not w or w == 0 then return end
        local pct = (cx / scale - left) / w
        pct = math.max(0, math.min(1, pct))
        local lo, hi = targetSlider:GetMinMaxValues()
        local s = activeDrag.step or step
        local raw = lo + (hi - lo) * pct
        raw = math.floor(raw / s + 0.5) * s
        raw = math.max(lo, math.min(hi, raw))
        targetSlider:SetValue(raw)
    end

    overlay:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            activeDrag.sliderLabel = label
            activeDrag.min = min
            activeDrag.max = max
            activeDrag.step = step
            activeDrag.onChange = onChange
            activeDrag.slider = slider
            activeDrag.overlay = overlay
            UpdateFromCursor()
        end
    end)

    overlay:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and activeDrag.sliderLabel == label then
            activeDrag.sliderLabel = nil
        end
    end)

    overlay:SetScript("OnUpdate", function(self)
        if activeDrag.sliderLabel == label then
            if not IsMouseButtonDown("LeftButton") then
                activeDrag.sliderLabel = nil
                return
            end
            activeDrag.slider = slider
            activeDrag.overlay = overlay
            UpdateFromCursor()
        end
    end)

    -- Reconnect if rebuilt during active drag
    if activeDrag.sliderLabel == label then
        activeDrag.slider = slider
        activeDrag.overlay = overlay
    end

    -- Pass scroll wheel through to parent scroll frame
    overlay:SetScript("OnMouseWheel", function(self, delta)
        local sf = self:GetParent()
        while sf and not sf.SetVerticalScroll do
            sf = sf:GetParent()
        end
        if sf and sf.SetVerticalScroll then
            local cur = sf:GetVerticalScroll()
            local mx = sf:GetVerticalScrollRange()
            sf:SetVerticalScroll(math.max(0, math.min(mx, cur - delta * 40)))
        end
    end)
    overlay:EnableMouseWheel(true)

    container.slider = slider
    container.valueText = valueText

    function container:SetInitialValue(val)
        slider._suppress = true
        slider:SetValue(val)
        slider._suppress = false
    end

    return container
end

local function CreateCheckbox(parent, text, onChange)
    local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    check.Text:SetText(text)
    check:SetScript("OnClick", function(self)
        if onChange then onChange(self:GetChecked()) end
    end)
    return check
end

local function CreateColorSwatch(parent, color, onChange, hasAlpha)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(20, 20)

    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.5, 0.5, 0.5, 1)

    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    local initA = hasAlpha and (color.a or 1) or 1
    tex:SetColorTexture(color.r, color.g, color.b, initA)
    swatch.tex = tex

    swatch:SetScript("OnClick", function(self)
        local settings = {
            r = color.r, g = color.g, b = color.b,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = 1
                if hasAlpha and ColorPickerFrame.GetColorAlpha then
                    a = ColorPickerFrame:GetColorAlpha()
                end
                color.r, color.g, color.b = r, g, b
                if hasAlpha then color.a = a end
                self.tex:SetColorTexture(r, g, b, hasAlpha and a or 1)
                if onChange then onChange(r, g, b, a) end
            end,
            cancelFunc = function(prev)
                color.r, color.g, color.b = prev.r, prev.g, prev.b
                local a = 1
                if hasAlpha then
                    a = prev.a or color.a or 1
                    color.a = a
                end
                self.tex:SetColorTexture(prev.r, prev.g, prev.b, hasAlpha and a or 1)
                if onChange then onChange(prev.r, prev.g, prev.b, a) end
            end,
        }
        if hasAlpha then
            settings.hasOpacity = true
            settings.opacity = color.a or 1
            settings.opacityFunc = function()
                if ColorPickerFrame.GetColorAlpha then
                    local a = ColorPickerFrame:GetColorAlpha()
                    color.a = a
                    self.tex:SetColorTexture(color.r, color.g, color.b, a)
                    if onChange then onChange(color.r, color.g, color.b, a) end
                end
            end
        end
        ColorPickerFrame:SetupColorPickerAndShow(settings)
    end)

    return swatch
end

-- ============================================================================
-- SCROLLABLE DROPDOWN WIDGET
-- ============================================================================

local function CloseActivePopup()
    if activePopup then
        activePopup:Hide()
        activePopup = nil
    end
end

local function CreateScrollDropdown(parent, label, width, getOptions, getCurrent, onSelect)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 38)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("TOPLEFT", 0, 0)
    labelFS:SetText(label)

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", 0, -14)
    btn:SetSize(width, 20)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("LEFT", 4, 0)
    btnText:SetPoint("RIGHT", -16, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetWordWrap(false)

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -2, 0)
    arrow:SetText("v")

    -- Popup (anchored to UIParent so it can overlap settings panel)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(width, 160)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    popup:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
    popup:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(500)
    popup:SetClampedToScreen(true)
    popup:Hide()

    local popupScroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    popupScroll:SetPoint("TOPLEFT", 4, -4)
    popupScroll:SetPoint("BOTTOMRIGHT", -24, 4)

    local popupChild = CreateFrame("Frame")
    popupChild:SetSize(width - 30, 1)
    popupScroll:SetScrollChild(popupChild)

    local popupItems = {}

    local function RebuildPopup()
        for _, item in ipairs(popupItems) do item:Hide() end
        wipe(popupItems)

        local options = getOptions()
        local current = getCurrent()
        local yy = 0

        for i, opt in ipairs(options) do
            local item = CreateFrame("Button", nil, popupChild)
            item:SetSize(width - 30, 18)
            item:SetPoint("TOPLEFT", 0, -yy)

            local hl = item:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.15)

            local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itemText:SetPoint("LEFT", 4, 0)
            itemText:SetPoint("RIGHT", -4, 0)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(opt)
            itemText:SetWordWrap(false)

            if opt == current then
                itemText:SetTextColor(1, 0.82, 0)
            end

            item:SetScript("OnClick", function()
                onSelect(opt)
                btnText:SetText(opt)
                popup:Hide()
                activePopup = nil
            end)

            item:Show()
            table.insert(popupItems, item)
            yy = yy + 18
        end

        popupChild:SetHeight(math.max(1, yy))
        popup:SetHeight(math.min(200, yy + 8))
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
            activePopup = nil
        else
            CloseActivePopup()
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
            RebuildPopup()
            popup:Show()
            activePopup = popup
        end
    end)

    container:SetScript("OnHide", function()
        if activePopup == popup then
            popup:Hide()
            activePopup = nil
        end
    end)

    container.SetValue = function(_, val)
        btnText:SetText(val or "")
    end

    container.btn = btn
    return container
end

-- ============================================================================
-- BUTTON GROUP (small fixed option sets like icon position)
-- ============================================================================

local function CreateButtonGroup(parent, label, options, getCurrent, onSelect)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(CONTROL_WIDTH, 26)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("LEFT", 0, 0)
    labelFS:SetText(label)

    local buttons = {}
    local xOff = 80

    local function UpdateHighlights()
        local cur = getCurrent()
        for _, b in ipairs(buttons) do
            b:SetEnabled(b.value ~= cur)
        end
    end

    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        b:SetSize(55, 22)
        b:SetPoint("LEFT", xOff, 0)
        b:SetText(opt.label)
        b.value = opt.value

        b:SetScript("OnClick", function()
            onSelect(opt.value)
            UpdateHighlights()
        end)

        if opt.tooltip then
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(opt.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        table.insert(buttons, b)
        xOff = xOff + 59
    end

    container.UpdateHighlights = UpdateHighlights
    C_Timer.After(0, UpdateHighlights)

    return container
end

-- ============================================================================
-- TOGGLE ROW (dock tab custom toggle buttons)
-- ============================================================================

local function CreateToggleRow(parent, label, options, currentValue, yOffset, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(CONTROL_WIDTH, 28)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:Show()

    local labelFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFS:SetPoint("LEFT", 0, 0)
    labelFS:SetText(label)

    local btns = {}
    local x = 90
    for _, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(opt.width or 75, 22)
        btn:SetPoint("LEFT", x, 0)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.6)
        btn._bg = bg

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(opt.label)
        btn:SetFontString(text)

        local isActive = (currentValue == opt.value)
        if isActive then
            bg:SetColorTexture(0.0, 0.5, 0.8, 0.5)
            text:SetTextColor(1, 1, 1)
        else
            text:SetTextColor(0.6, 0.6, 0.6)
        end

        btn:SetScript("OnClick", function()
            for _, b in ipairs(btns) do
                b._bg:SetColorTexture(0.2, 0.2, 0.2, 0.6)
                b:GetFontString():SetTextColor(0.6, 0.6, 0.6)
            end
            btn._bg:SetColorTexture(0.0, 0.5, 0.8, 0.5)
            btn:GetFontString():SetTextColor(1, 1, 1)
            if onChange then onChange(opt.value) end
        end)

        if opt.tooltip then
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(opt.label)
                GameTooltip:AddLine(opt.tooltip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", GameTooltip_Hide)
        end

        table.insert(btns, btn)
        x = x + (opt.width or 75) + 6
    end

    return row
end

-- ============================================================================
-- SPELL LIST (left side)
-- ============================================================================

local scrollFrame, scrollChild

local function RefreshSpellList()
    if not scrollChild then return end

    for _, btn in ipairs(spellButtons) do btn:Hide() end
    wipe(spellButtons)

    local spellList = BuffBarsData:GetSpellList()
    local yOffset = 0

    for i, entry in ipairs(spellList) do
        local btn = CreateFrame("Button", nil, scrollChild)
        btn:SetSize(LIST_WIDTH - 10, BUTTON_HEIGHT)
        btn:SetPoint("TOPLEFT", 0, -yOffset)

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.82, 0, 0.15)

        local selected = btn:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetColorTexture(1, 0.82, 0, 0.25)
        selected:SetShown(selectedBarKey == entry.barKey)
        btn.selectedTex = selected

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BUTTON_HEIGHT - 4, BUTTON_HEIGHT - 4)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(entry.texture or 134400)

        local name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        name:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        name:SetJustifyH("LEFT")
        name:SetText(entry.name or entry.displayName)
        name:SetWordWrap(false)

        if not entry.enabled then
            name:SetTextColor(0.5, 0.5, 0.5)
            icon:SetDesaturated(true)
        end

        btn:SetScript("OnClick", function()
            selectedBarKey = entry.barKey
            BuffBarsFrames:SetPreviewBar(selectedBarKey)
            RefreshSpellList()
            BuffBarsUI:RefreshConfigPanel()
        end)

        table.insert(spellButtons, btn)
        yOffset = yOffset + BUTTON_HEIGHT + BUTTON_SPACING
    end

    scrollChild:SetHeight(math.max(1, yOffset))
end

-- ============================================================================
-- CONFIG PANEL (right side, scrollable) — Spell Config Tab
-- ============================================================================

local function SetAndApply(key, value, refreshPanel)
    if not selectedBarKey then return end
    BuffBarsData:SetSpellSetting(selectedBarKey, key, value)
    BuffBarsFrames:OnConfigChanged(selectedBarKey)
    if refreshPanel then
        BuffBarsUI:RefreshConfigPanel()
    end
end

function BuffBarsUI:RefreshConfigPanel()
    if not configScrollChild then return end

    -- Hide ALL children from all scroll containers
    for _, child in ipairs({configScrollChild:GetChildren()}) do child:Hide() end
    if dockScrollChild then
        for _, child in ipairs({dockScrollChild:GetChildren()}) do child:Hide() end
    end
    if self._visibilityScrollChild then
        for _, child in ipairs({self._visibilityScrollChild:GetChildren()}) do child:Hide() end
    end
    CloseActivePopup()

    if activeTab == "dock" then
        -- Hide other scroll children, show dock
        if configScrollChild then configScrollChild:Hide() end
        if self._visibilityScrollChild then self._visibilityScrollChild:Hide() end
        if dockScrollChild then dockScrollChild:Show() end
        configFrame:SetScrollChild(dockScrollChild)
        self:BuildDockSettingsUI(dockScrollChild)
        return
    end

    if activeTab == "visibility" then
        -- Hide other scroll children, show visibility
        if configScrollChild then configScrollChild:Hide() end
        if dockScrollChild then dockScrollChild:Hide() end
        if self._visibilityScrollChild then self._visibilityScrollChild:Show() end
        configFrame:SetScrollChild(self._visibilityScrollChild)
        self:BuildVisibilityUI(self._visibilityScrollChild)
        return
    end

    -- Spell tab: hide other scroll children, show config
    if dockScrollChild then dockScrollChild:Hide() end
    if self._visibilityScrollChild then self._visibilityScrollChild:Hide() end
    if configScrollChild then configScrollChild:Show() end
    configFrame:SetScrollChild(configScrollChild)

    if not selectedBarKey then
        -- Show a hint when nothing is selected
        local hintFrame = CreateFrame("Frame", nil, configScrollChild)
        hintFrame:SetSize(CONTROL_WIDTH, 40)
        hintFrame:SetPoint("TOPLEFT", 0, -20)
        hintFrame:Show()
        local hintFS = hintFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintFS:SetPoint("TOPLEFT", 0, 0)
        hintFS:SetWidth(CONTROL_WIDTH)
        hintFS:SetText("|cff888888Select a buff from the list on the left\nto configure its bar settings.|r")
        configScrollChild:SetHeight(80)
        return
    end

    local config = BuffBarsData:GetSpellConfig(selectedBarKey)
    if not config then return end

    local slotIndex = BuffBarsData.GetSlotIndexForBarKey(selectedBarKey)
    local y = 0

    -- ========================================
    -- Header
    -- ========================================
    local header = CreateFrame("Frame", nil, configScrollChild)
    header:SetSize(CONTROL_WIDTH, 30)
    header:SetPoint("TOPLEFT", 0, -y)
    header:Show()

    local hIcon = header:CreateTexture(nil, "ARTWORK")
    hIcon:SetSize(24, 24)
    hIcon:SetPoint("LEFT", 0, 0)
    hIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    hIcon:SetTexture(config.iconID or config.texture or 134400)

    local hName = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hName:SetPoint("LEFT", hIcon, "RIGHT", 8, 0)
    hName:SetText(config.name or ("Buff Slot " .. (slotIndex or "?")))
    hName:SetTextColor(1, 0.82, 0)

    local hType = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hType:SetPoint("LEFT", hName, "RIGHT", 8, 0)
    hType:SetText("|cff888888" .. BuffBarsData.TypeLabel() .. "|r")

    y = y + 35

    -- Enable
    local enableCheck = CreateCheckbox(configScrollChild, "Enabled", function(checked)
        BuffBarsData:EnableByBarKey(selectedBarKey, nil, checked)
        BuffBarsFrames:OnConfigChanged(selectedBarKey)
        RefreshSpellList()
    end)
    enableCheck:SetPoint("TOPLEFT", 0, -y)
    enableCheck:SetChecked(config.enabled ~= false)
    enableCheck:Show()
    y = y + 28

    -- ========================================
    -- Bar Dimensions
    -- ========================================
    local dimLabel = CreateSectionLabel(configScrollChild, "Bar Dimensions")
    dimLabel:SetPoint("TOPLEFT", 0, -y)
    dimLabel:Show()
    y = y + 16

    local isVert = (config.barDirection == "UP" or config.barDirection == "DOWN")
    local widthMin, widthMax, widthStep = 60, 500, 5
    local heightMin, heightMax, heightStep = 8, 60, 1
    if isVert then
        widthMin, widthMax, widthStep = 8, 60, 1
        heightMin, heightMax, heightStep = 60, 500, 5
    end

    local widthSlider = CreateSlider(configScrollChild, "Bar Width", widthMin, widthMax, widthStep, CONTROL_WIDTH, function(val)
        SetAndApply("width", val)
    end)
    widthSlider:SetPoint("TOPLEFT", 0, -y)
    widthSlider:SetInitialValue(config.width or (isVert and 20 or 200))
    widthSlider:Show()
    y = y + 38

    local heightSlider = CreateSlider(configScrollChild, "Bar Height", heightMin, heightMax, heightStep, CONTROL_WIDTH, function(val)
        SetAndApply("height", val)
    end)
    heightSlider:SetPoint("TOPLEFT", 0, -y)
    heightSlider:SetInitialValue(config.height or (isVert and 200 or 20))
    heightSlider:Show()
    y = y + 38

    -- ========================================
    -- Appearance
    -- ========================================
    local appLabel = CreateSectionLabel(configScrollChild, "Appearance")
    appLabel:SetPoint("TOPLEFT", 0, -y)
    appLabel:Show()
    y = y + 16

    local texDD = CreateScrollDropdown(configScrollChild, "Bar Texture", CONTROL_WIDTH,
        function()
            return Media and Media:GetStatusBarList() or { "Blizzard" }
        end,
        function()
            return config.barTexture or "Blizzard"
        end,
        function(val)
            SetAndApply("barTexture", val)
        end
    )
    texDD:SetPoint("TOPLEFT", 0, -y)
    texDD:SetValue(config.barTexture or "Blizzard")
    texDD:Show()
    y = y + 40

    -- Colors inline
    local colorRow = CreateFrame("Frame", nil, configScrollChild)
    colorRow:SetSize(CONTROL_WIDTH, 24)
    colorRow:SetPoint("TOPLEFT", 0, -y)
    colorRow:Show()

    local bcLabel = colorRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bcLabel:SetPoint("LEFT", 0, 0)
    bcLabel:SetText("Bar Color")

    local barColor = config.barColor or { r = 0.2, g = 0.8, b = 0.2, a = 1.0 }
    local barSwatch = CreateColorSwatch(colorRow, barColor, function(r, g, b)
        SetAndApply("barColor", { r = r, g = g, b = b, a = 1.0 })
    end)
    barSwatch:SetPoint("LEFT", bcLabel, "RIGHT", 8, 0)
    barSwatch:Show()

    local bgcLabel = colorRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bgcLabel:SetPoint("LEFT", barSwatch, "RIGHT", 16, 0)
    bgcLabel:SetText("Background")

    local bgColor = config.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
    local bgSwatch = CreateColorSwatch(colorRow, bgColor, function(r, g, b, a)
        SetAndApply("backgroundColor", { r = r, g = g, b = b, a = a })
    end, true)
    bgSwatch:SetPoint("LEFT", bgcLabel, "RIGHT", 8, 0)
    bgSwatch:Show()
    y = y + 28

    -- Color by Time toggle
    local cbtCheck = CreateCheckbox(configScrollChild, "Color by Time Remaining", function(checked)
        SetAndApply("colorByTime", checked, true)  -- refreshPanel to show/hide swatches
    end)
    cbtCheck:SetPoint("TOPLEFT", 0, -y)
    cbtCheck:SetChecked(config.colorByTime == true)
    cbtCheck:Show()
    y = y + 26

    if config.colorByTime then
        -- Color swatches row: High / Med / Low
        local cbtRow = CreateFrame("Frame", nil, configScrollChild)
        cbtRow:SetSize(CONTROL_WIDTH, 24)
        cbtRow:SetPoint("TOPLEFT", 0, -y)
        cbtRow:Show()

        local cbtHighLabel = cbtRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cbtHighLabel:SetPoint("LEFT", 0, 0)
        cbtHighLabel:SetText("High")
        local cbtHighColor = config.colorHigh or { r = 0.2, g = 0.8, b = 0.2 }
        local cbtHighSwatch = CreateColorSwatch(cbtRow, cbtHighColor, function(r, g, b)
            SetAndApply("colorHigh", { r = r, g = g, b = b })
        end)
        cbtHighSwatch:SetPoint("LEFT", cbtHighLabel, "RIGHT", 6, 0)
        cbtHighSwatch:Show()

        local cbtMedLabel = cbtRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cbtMedLabel:SetPoint("LEFT", cbtHighSwatch, "RIGHT", 14, 0)
        cbtMedLabel:SetText("Med")
        local cbtMedColor = config.colorMed or { r = 1.0, g = 0.8, b = 0.0 }
        local cbtMedSwatch = CreateColorSwatch(cbtRow, cbtMedColor, function(r, g, b)
            SetAndApply("colorMed", { r = r, g = g, b = b })
        end)
        cbtMedSwatch:SetPoint("LEFT", cbtMedLabel, "RIGHT", 6, 0)
        cbtMedSwatch:Show()

        local cbtLowLabel = cbtRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cbtLowLabel:SetPoint("LEFT", cbtMedSwatch, "RIGHT", 14, 0)
        cbtLowLabel:SetText("Low")
        local cbtLowColor = config.colorLow or { r = 1.0, g = 0.2, b = 0.2 }
        local cbtLowSwatch = CreateColorSwatch(cbtRow, cbtLowColor, function(r, g, b)
            SetAndApply("colorLow", { r = r, g = g, b = b })
        end)
        cbtLowSwatch:SetPoint("LEFT", cbtLowLabel, "RIGHT", 6, 0)
        cbtLowSwatch:Show()

        -- Reset Defaults button
        local resetBtn = CreateFrame("Button", nil, cbtRow, "UIPanelButtonTemplate")
        resetBtn:SetSize(60, 20)
        resetBtn:SetPoint("LEFT", cbtLowSwatch, "RIGHT", 14, 0)
        resetBtn:SetText("Reset")
        resetBtn:SetScript("OnClick", function()
            SetAndApply("colorHigh", { r = 0.2, g = 0.8, b = 0.2 })
            SetAndApply("colorMed", { r = 1.0, g = 0.8, b = 0.0 })
            SetAndApply("colorLow", { r = 1.0, g = 0.2, b = 0.2 }, true)  -- refresh panel
        end)
        resetBtn:Show()
        y = y + 28
    end

    -- ========================================
    -- Icon
    -- ========================================
    local iconSec = CreateSectionLabel(configScrollChild, "Icon")
    iconSec:SetPoint("TOPLEFT", 0, -y)
    iconSec:Show()
    y = y + 16

    local showIconCheck = CreateCheckbox(configScrollChild, "Show Icon", function(checked)
        SetAndApply("showIcon", checked)
    end)
    showIconCheck:SetPoint("TOPLEFT", 0, -y)
    showIconCheck:SetChecked(config.showIcon ~= false)
    showIconCheck:Show()
    y = y + 26

    local curSizeMode = config.iconSizeMode or "auto"
    local sizeModeGroup = CreateButtonGroup(configScrollChild, "Icon Size",
        { { label = "Auto", value = "auto" }, { label = "Manual", value = "manual" } },
        function() return config.iconSizeMode or "auto" end,
        function(val)
            SetAndApply("iconSizeMode", val, true)
        end
    )
    sizeModeGroup:SetPoint("TOPLEFT", 0, -y)
    sizeModeGroup:Show()
    y = y + 28

    if curSizeMode == "manual" then
        local iconSizeSlider = CreateSlider(configScrollChild, "Icon Size (px)", 8, 120, 1, CONTROL_WIDTH, function(val)
            SetAndApply("iconSize", val)
        end)
        iconSizeSlider:SetPoint("TOPLEFT", 0, -y)
        iconSizeSlider:SetInitialValue(config.iconSize or 20)
        iconSizeSlider:Show()
        y = y + 38
    end

    -- Aspect + Position
    local aspectDD = CreateScrollDropdown(configScrollChild, "Aspect", CONTROL_WIDTH / 2 - 5,
        function()
            local opts = {}
            for _, key in ipairs(ICON_ASPECT_ORDER) do
                table.insert(opts, ICON_ASPECT_LABELS[key] or key)
            end
            return opts
        end,
        function()
            local cur = config.iconAspect or "1:1"
            return ICON_ASPECT_LABELS[cur] or cur
        end,
        function(labelVal)
            for _, key in ipairs(ICON_ASPECT_ORDER) do
                if ICON_ASPECT_LABELS[key] == labelVal then
                    SetAndApply("iconAspect", key)
                    return
                end
            end
        end
    )
    aspectDD:SetPoint("TOPLEFT", 0, -y)
    aspectDD:SetValue(ICON_ASPECT_LABELS[config.iconAspect or "1:1"] or "1:1 (Square)")
    aspectDD:Show()

    local posGroup = CreateButtonGroup(configScrollChild, "Position",
        { { label = "Left", value = "LEFT" }, { label = "Right", value = "RIGHT" } },
        function() return config.iconPosition or "LEFT" end,
        function(val)
            SetAndApply("iconPosition", val)
        end
    )
    posGroup:SetPoint("TOPLEFT", CONTROL_WIDTH / 2 + 5, -y - 10)
    posGroup:Show()
    y = y + 42

    -- ========================================
    -- Text
    -- ========================================
    local txtSec = CreateSectionLabel(configScrollChild, "Text")
    txtSec:SetPoint("TOPLEFT", 0, -y)
    txtSec:Show()
    y = y + 16

    local fontDD = CreateScrollDropdown(configScrollChild, "Font", CONTROL_WIDTH,
        function()
            local list = Media and Media:GetFontList() or { "Friz Quadrata TT" }
            local opts = { "(Default)" }
            for _, name in ipairs(list) do
                table.insert(opts, name)
            end
            return opts
        end,
        function()
            local f = config.font
            if not f or f == "" then return "(Default)" end
            return f
        end,
        function(val)
            if val == "(Default)" then val = "" end
            SetAndApply("font", val)
        end
    )
    fontDD:SetPoint("TOPLEFT", 0, -y)
    local fontDisplay = config.font
    if not fontDisplay or fontDisplay == "" then fontDisplay = "(Default)" end
    fontDD:SetValue(fontDisplay)
    fontDD:Show()
    y = y + 40

    local nameSizeSlider = CreateSlider(configScrollChild, "Name Font Size", 6, 24, 1, CONTROL_WIDTH, function(val)
        SetAndApply("nameFontSize", val)
    end)
    nameSizeSlider:SetPoint("TOPLEFT", 0, -y)
    nameSizeSlider:SetInitialValue(config.nameFontSize or 11)
    nameSizeSlider:Show()
    y = y + 36

    local timeSizeSlider = CreateSlider(configScrollChild, "Time Font Size", 6, 24, 1, CONTROL_WIDTH, function(val)
        SetAndApply("timeFontSize", val)
    end)
    timeSizeSlider:SetPoint("TOPLEFT", 0, -y)
    timeSizeSlider:SetInitialValue(config.timeFontSize or 11)
    timeSizeSlider:Show()
    y = y + 36

    local showNameCheck = CreateCheckbox(configScrollChild, "Show Spell Name", function(checked)
        SetAndApply("showName", checked)
    end)
    showNameCheck:SetPoint("TOPLEFT", 0, -y)
    showNameCheck:SetChecked(config.showName ~= false)
    showNameCheck:Show()

    local showTimeCheck = CreateCheckbox(configScrollChild, "Show Time", function(checked)
        SetAndApply("showTime", checked)
    end)
    showTimeCheck:SetPoint("TOPLEFT", 155, -y)
    showTimeCheck:SetChecked(config.showTime ~= false)
    showTimeCheck:Show()
    y = y + 28

    -- Text offset sliders (paired X/Y on same row)
    local halfW = CONTROL_WIDTH / 2 - 5

    local nameOxSlider = CreateSlider(configScrollChild, "Name Offset X", -100, 100, 1, halfW, function(val)
        SetAndApply("nameOffsetX", val)
    end)
    nameOxSlider:SetPoint("TOPLEFT", 0, -y)
    nameOxSlider:SetInitialValue(config.nameOffsetX or 0)
    nameOxSlider:Show()

    local nameOySlider = CreateSlider(configScrollChild, "Name Offset Y", -100, 100, 1, halfW, function(val)
        SetAndApply("nameOffsetY", val)
    end)
    nameOySlider:SetPoint("TOPLEFT", halfW + 10, -y)
    nameOySlider:SetInitialValue(config.nameOffsetY or 0)
    nameOySlider:Show()
    y = y + 36

    local timeOxSlider = CreateSlider(configScrollChild, "Time Offset X", -100, 100, 1, halfW, function(val)
        SetAndApply("timeOffsetX", val)
    end)
    timeOxSlider:SetPoint("TOPLEFT", 0, -y)
    timeOxSlider:SetInitialValue(config.timeOffsetX or 0)
    timeOxSlider:Show()

    local timeOySlider = CreateSlider(configScrollChild, "Time Offset Y", -100, 100, 1, halfW, function(val)
        SetAndApply("timeOffsetY", val)
    end)
    timeOySlider:SetPoint("TOPLEFT", halfW + 10, -y)
    timeOySlider:SetInitialValue(config.timeOffsetY or 0)
    timeOySlider:Show()
    y = y + 36

    -- ========================================
    -- Behavior
    -- ========================================
    local behSec = CreateSectionLabel(configScrollChild, "Behavior")
    behSec:SetPoint("TOPLEFT", 0, -y)
    behSec:Show()
    y = y + 16

    local inactiveCheck = CreateCheckbox(configScrollChild, "Show When Inactive (buff not active)", function(checked)
        SetAndApply("showWhenInactive", checked)
    end)
    inactiveCheck:SetPoint("TOPLEFT", 0, -y)
    inactiveCheck:SetChecked(config.showWhenInactive == true)
    inactiveCheck:Show()
    y = y + 30

    -- Fill Mode (drain vs fill)
    local fillModeGroup = CreateButtonGroup(configScrollChild, "Fill Mode",
        {
            { label = "Drain", value = "drain", tooltip = "Bar starts full, empties as buff ticks down" },
            { label = "Fill",  value = "fill",  tooltip = "Bar starts empty, fills as buff expires" },
        },
        function() return config.fillMode or "drain" end,
        function(val) SetAndApply("fillMode", val) end
    )
    fillModeGroup:SetPoint("TOPLEFT", 0, -y)
    fillModeGroup:Show()
    y = y + 30

    -- Bar Direction (RIGHT, LEFT, UP, DOWN)
    local dirGroup = CreateButtonGroup(configScrollChild, "Direction",
        {
            { label = "R", value = "RIGHT", tooltip = "Fill left to right (horizontal)" },
            { label = "L", value = "LEFT",  tooltip = "Fill right to left (horizontal)" },
            { label = "U", value = "UP",    tooltip = "Fill bottom to top (vertical)" },
            { label = "D", value = "DOWN",  tooltip = "Fill top to bottom (vertical)" },
        },
        function() return config.barDirection or "RIGHT" end,
        function(newDir)
            local oldDir = config.barDirection or "RIGHT"
            local wasVert = (oldDir == "UP" or oldDir == "DOWN")
            local nowVert = (newDir == "UP" or newDir == "DOWN")

            if wasVert ~= nowVert then
                local w = config.width or 200
                local h = config.height or 20
                BuffBarsData:SetSpellSetting(selectedBarKey, "width", h)
                BuffBarsData:SetSpellSetting(selectedBarKey, "height", w)
                config.width = h
                config.height = w
            end

            SetAndApply("barDirection", newDir, true)
        end
    )
    local dirBtnIdx = 0
    for _, child in ipairs({dirGroup:GetChildren()}) do
        if child.GetObjectType and child:GetObjectType() == "Button" then
            child:SetSize(34, 22)
            child:ClearAllPoints()
            child:SetPoint("LEFT", 80 + (dirBtnIdx * 38), 0)
            dirBtnIdx = dirBtnIdx + 1
        end
    end
    dirGroup:SetPoint("TOPLEFT", 0, -y)
    dirGroup:Show()
    y = y + 30

    -- ========================================
    -- Remove
    -- ========================================
    local removeBtn = CreateFrame("Button", nil, configScrollChild, "UIPanelButtonTemplate")
    removeBtn:SetSize(120, 24)
    removeBtn:SetPoint("TOPLEFT", 0, -y)
    removeBtn:SetText("|cffff4444Remove Buff|r")
    removeBtn:Show()
    removeBtn:SetScript("OnClick", function()
        BuffBarsFrames:ClearPreviewBar()
        BuffBarsData:RemoveSlot(selectedBarKey)
        BuffBarsFrames:DestroyBar(selectedBarKey)
        selectedBarKey = nil
        RefreshSpellList()
        BuffBarsUI:RefreshConfigPanel()
    end)
    y = y + 30

    configScrollChild:SetHeight(y + 10)
end

-- ============================================================================
-- DOCK SETTINGS TAB
-- ============================================================================

function BuffBarsUI:BuildDockSettingsUI(parent)
    for _, child in ipairs({parent:GetChildren()}) do child:Hide() end

    local y = 0

    -- Header
    local headerFrame = CreateFrame("Frame", nil, parent)
    headerFrame:SetSize(CONTROL_WIDTH, 28)
    headerFrame:SetPoint("TOPLEFT", 0, -y)
    headerFrame:Show()
    local headerFS = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headerFS:SetPoint("LEFT", 0, 0)
    headerFS:SetText("|cffffd100Dock Settings|r")
    y = y + 30

    -- Description
    local descFrame = CreateFrame("Frame", nil, parent)
    descFrame:SetSize(CONTROL_WIDTH, 30)
    descFrame:SetPoint("TOPLEFT", 0, -y)
    descFrame:Show()
    local descFS = descFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descFS:SetPoint("TOPLEFT", 0, 0)
    descFS:SetWidth(CONTROL_WIDTH)
    descFS:SetJustifyH("LEFT")
    descFS:SetText("|cff888888Dock groups all buff bars into a single\nmovable container instead of individual frames.|r")
    y = y + 38

    -- Enable checkbox
    local dockEnabled = BuffBarsData:IsDockEnabled()
    local dockCheck = CreateCheckbox(parent, "Enable Dock", function(checked)
        BuffBarsData:SetDockEnabled(checked)
        local dock = TUICD.BuffBarsDock
        if dock then
            if checked then dock:Enable() else dock:Disable() end
        end
        BuffBarsUI:RefreshConfigPanel()
    end)
    dockCheck:SetPoint("TOPLEFT", 0, -y)
    dockCheck:SetChecked(dockEnabled)
    dockCheck:Show()
    y = y + 32

    if not dockEnabled then
        local hintFrame = CreateFrame("Frame", nil, parent)
        hintFrame:SetSize(CONTROL_WIDTH, 20)
        hintFrame:SetPoint("TOPLEFT", 0, -y)
        hintFrame:Show()
        local hintFS = hintFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintFS:SetPoint("TOPLEFT", 10, 0)
        hintFS:SetText("|cff666666Standalone mode: each bar is individually draggable.|r")
        y = y + 30
        parent:SetHeight(y + 10)
        return
    end

    -- Helper for dock setting changes
    local function DockSet(key, value)
        BuffBarsData:SetDockSetting(key, value)
        local dock = TUICD.BuffBarsDock
        if dock then 
            if key == "justify" or key == "direction" then
                -- Re-anchor dock when justify or orientation changes
                if dock.ReanchorForJustify then
                    dock:ReanchorForJustify()
                end
            end
            dock:QueueLayout() 
        end
    end

    -- Section: Layout
    local secLayout = CreateSectionLabel(parent, "Layout")
    secLayout:SetPoint("TOPLEFT", 0, -y)
    secLayout:Show()
    y = y + 22

    -- Orientation
    local curDirection = BuffBarsData:GetDockSetting("direction") or "DOWN"
    local orientValue = (curDirection == "RIGHT" or curDirection == "LEFT") and "HORIZONTAL" or "VERTICAL"
    local oriRow = CreateToggleRow(parent, "Orientation:", {
        { label = "Vertical",   value = "VERTICAL",   width = 72, tooltip = "Stack bars top-to-bottom" },
        { label = "Horizontal", value = "HORIZONTAL", width = 80, tooltip = "Stack bars left-to-right" },
    }, orientValue, y, function(val)
        DockSet("direction", val == "HORIZONTAL" and "RIGHT" or "DOWN")
        -- Update justify labels based on new orientation
        if parent._justifyRow then
            local isVert = (val == "VERTICAL")
            local btns = parent._justifyRow._buttons
            if btns and #btns >= 3 then
                btns[1]:GetFontString():SetText(isVert and "Top" or "Left")
                btns[2]:GetFontString():SetText(isVert and "Middle" or "Center")
                btns[3]:GetFontString():SetText(isVert and "Bottom" or "Right")
            end
        end
    end)
    y = y + 34

    -- Justify - labels change based on orientation
    local isVert = (orientValue == "VERTICAL")
    local justifyValue = BuffBarsData:GetDockSetting("justify") or "CENTER"
    local justRow = CreateToggleRow(parent, "Justify:", {
        { label = isVert and "Top" or "Left",      value = "START",  width = 55, tooltip = "Bars grow from " .. (isVert and "top" or "left") .. " edge" },
        { label = isVert and "Middle" or "Center", value = "CENTER", width = 55, tooltip = "Center-out placement" },
        { label = isVert and "Bottom" or "Right",  value = "END",    width = 55, tooltip = "Bars grow from " .. (isVert and "bottom" or "right") .. " edge" },
    }, justifyValue, y, function(val) DockSet("justify", val) end)
    -- Store reference for dynamic label updates
    parent._justifyRow = justRow
    -- Store button references
    justRow._buttons = {}
    local btns = {justRow:GetChildren()}
    for _, child in ipairs(btns) do
        if child:GetObjectType() == "Button" then
            table.insert(justRow._buttons, child)
        end
    end
    y = y + 34

    -- Spacing slider
    local spacingSlider = CreateSlider(parent, "Spacing (px)", 0, 20, 1, CONTROL_WIDTH - 20, function(val)
        DockSet("spacing", val)
    end)
    spacingSlider:SetPoint("TOPLEFT", 0, -y)
    spacingSlider:SetInitialValue(BuffBarsData:GetDockSetting("spacing") or 2)
    spacingSlider:Show()
    y = y + 44

    -- Section: Override Bar Settings
    local secOverride = CreateSectionLabel(parent, "Visual Override")
    secOverride:SetPoint("TOPLEFT", 0, -y)
    secOverride:Show()
    y = y + 22

    -- Enable Override checkbox
    local overrideEnabled = BuffBarsData:IsOverrideEnabled()
    local overrideCheck = CreateCheckbox(parent, "Override all bar visuals", function(checked)
        BuffBarsData:SetOverrideEnabled(checked)
        BuffBarsUI:RefreshConfigPanel()
    end)
    overrideCheck:SetPoint("TOPLEFT", 0, -y)
    overrideCheck:SetChecked(overrideEnabled)
    overrideCheck:Show()
    y = y + 26

    -- Override description
    local overrideDescFrame = CreateFrame("Frame", nil, parent)
    overrideDescFrame:SetSize(CONTROL_WIDTH, 24)
    overrideDescFrame:SetPoint("TOPLEFT", 0, -y)
    overrideDescFrame:Show()
    local overrideDescFS = overrideDescFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overrideDescFS:SetPoint("TOPLEFT", 22, 0)
    overrideDescFS:SetWidth(CONTROL_WIDTH - 30)
    overrideDescFS:SetJustifyH("LEFT")
    overrideDescFS:SetText("|cff888888When enabled, dock settings apply to all bars,\noverriding individual bar configurations.|r")
    y = y + 36

    if not overrideEnabled then
        -- Section: Tips (shown when override disabled)
        local secInfo = CreateSectionLabel(parent, "Tips")
        secInfo:SetPoint("TOPLEFT", 0, -y)
        secInfo:Show()
        y = y + 22

        local infoFrame = CreateFrame("Frame", nil, parent)
        infoFrame:SetSize(CONTROL_WIDTH, 80)
        infoFrame:SetPoint("TOPLEFT", 0, -y)
        infoFrame:Show()
        local infoFS = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        infoFS:SetPoint("TOPLEFT", 8, 0)
        infoFS:SetWidth(CONTROL_WIDTH - 16)
        infoFS:SetJustifyH("LEFT")
        infoFS:SetText("|cff666666Use |cff00ccff/tuicd buffbars layout|cff666666 to move the dock.\n\nBuff bars appear when the tracked buff is active\nand drain down as the buff expires. Enable\n\"Show When Inactive\" on individual bars to keep\nthem visible at all times.|r")
        y = y + 90

        parent:SetHeight(y + 10)
        return
    end

    -- =====================================================
    -- OVERRIDE ENABLED: Full visual settings
    -- =====================================================
    local function OverrideSet(key, value, refreshPanel)
        BuffBarsData:SetDockOverride(key, value)
        -- Invalidate color caches when color-related settings change
        if key == "colorByTime" or key == "colorHigh" or key == "colorMed" or key == "colorLow" or key == "barColor" then
            BuffBarsFrames:InvalidateAllColorCurves()
        end
        if refreshPanel then
            BuffBarsUI:RefreshConfigPanel()
        end
    end

    local bo = BuffBarsData:GetDockOverrides()
    if not bo then
        parent:SetHeight(y + 10)
        return
    end

    -- ---- Bar Dimensions ----
    local dimSec = CreateSectionLabel(parent, "Bar Dimensions")
    dimSec:SetPoint("TOPLEFT", 0, -y)
    dimSec:Show()
    y = y + 16

    local oIsVert = (bo.barDirection == "UP" or bo.barDirection == "DOWN")
    local oWMin, oWMax, oWStep = 60, 500, 5
    local oHMin, oHMax, oHStep = 8, 60, 1
    if oIsVert then
        oWMin, oWMax, oWStep = 8, 60, 1
        oHMin, oHMax, oHStep = 60, 500, 5
    end

    local oWidthSlider = CreateSlider(parent, "Bar Width", oWMin, oWMax, oWStep, CONTROL_WIDTH - 20, function(val)
        OverrideSet("width", val)
    end)
    oWidthSlider:SetPoint("TOPLEFT", 0, -y)
    oWidthSlider:SetInitialValue(bo.width or (oIsVert and 20 or 200))
    oWidthSlider:Show()
    y = y + 38

    local oHeightSlider = CreateSlider(parent, "Bar Height", oHMin, oHMax, oHStep, CONTROL_WIDTH - 20, function(val)
        OverrideSet("height", val)
    end)
    oHeightSlider:SetPoint("TOPLEFT", 0, -y)
    oHeightSlider:SetInitialValue(bo.height or (oIsVert and 200 or 20))
    oHeightSlider:Show()
    y = y + 38

    -- ---- Appearance ----
    local oAppSec = CreateSectionLabel(parent, "Appearance")
    oAppSec:SetPoint("TOPLEFT", 0, -y)
    oAppSec:Show()
    y = y + 16

    local oTexDD = CreateScrollDropdown(parent, "Bar Texture", CONTROL_WIDTH - 20,
        function() return Media and Media:GetStatusBarList() or { "Blizzard" } end,
        function() return bo.barTexture or "Blizzard" end,
        function(val) OverrideSet("barTexture", val) end
    )
    oTexDD:SetPoint("TOPLEFT", 0, -y)
    oTexDD:SetValue(bo.barTexture or "Blizzard")
    oTexDD:Show()
    y = y + 40

    -- Colors row
    local oColorRow = CreateFrame("Frame", nil, parent)
    oColorRow:SetSize(CONTROL_WIDTH, 24)
    oColorRow:SetPoint("TOPLEFT", 0, -y)
    oColorRow:Show()

    local oBcLabel = oColorRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    oBcLabel:SetPoint("LEFT", 0, 0)
    oBcLabel:SetText("Bar Color")

    local oBarColor = bo.barColor or { r = 0.2, g = 0.8, b = 0.2, a = 1.0 }
    local oBarSwatch = CreateColorSwatch(oColorRow, oBarColor, function(r, g, b)
        OverrideSet("barColor", { r = r, g = g, b = b, a = 1.0 })
    end)
    oBarSwatch:SetPoint("LEFT", oBcLabel, "RIGHT", 8, 0)
    oBarSwatch:Show()

    local oBgcLabel = oColorRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    oBgcLabel:SetPoint("LEFT", oBarSwatch, "RIGHT", 16, 0)
    oBgcLabel:SetText("Background")

    local oBgColor = bo.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
    local oBgSwatch = CreateColorSwatch(oColorRow, oBgColor, function(r, g, b, a)
        OverrideSet("backgroundColor", { r = r, g = g, b = b, a = a })
    end, true)
    oBgSwatch:SetPoint("LEFT", oBgcLabel, "RIGHT", 8, 0)
    oBgSwatch:Show()
    y = y + 28

    -- Color by Time toggle
    local oCbtCheck = CreateCheckbox(parent, "Color by Time Remaining", function(checked)
        OverrideSet("colorByTime", checked, true)
    end)
    oCbtCheck:SetPoint("TOPLEFT", 0, -y)
    oCbtCheck:SetChecked(bo.colorByTime == true)
    oCbtCheck:Show()
    y = y + 26

    if bo.colorByTime then
        -- Color swatches row: High / Med / Low
        local oCbtRow = CreateFrame("Frame", nil, parent)
        oCbtRow:SetSize(CONTROL_WIDTH, 24)
        oCbtRow:SetPoint("TOPLEFT", 0, -y)
        oCbtRow:Show()

        local oChLabel = oCbtRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        oChLabel:SetPoint("LEFT", 0, 0)
        oChLabel:SetText("High")
        local oChColor = bo.colorHigh or { r = 0.2, g = 0.8, b = 0.2 }
        local oChSwatch = CreateColorSwatch(oCbtRow, oChColor, function(r, g, b)
            OverrideSet("colorHigh", { r = r, g = g, b = b })
        end)
        oChSwatch:SetPoint("LEFT", oChLabel, "RIGHT", 6, 0)
        oChSwatch:Show()

        local oCmLabel = oCbtRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        oCmLabel:SetPoint("LEFT", oChSwatch, "RIGHT", 14, 0)
        oCmLabel:SetText("Med")
        local oCmColor = bo.colorMed or { r = 1.0, g = 0.8, b = 0.0 }
        local oCmSwatch = CreateColorSwatch(oCbtRow, oCmColor, function(r, g, b)
            OverrideSet("colorMed", { r = r, g = g, b = b })
        end)
        oCmSwatch:SetPoint("LEFT", oCmLabel, "RIGHT", 6, 0)
        oCmSwatch:Show()

        local oClLabel = oCbtRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        oClLabel:SetPoint("LEFT", oCmSwatch, "RIGHT", 14, 0)
        oClLabel:SetText("Low")
        local oClColor = bo.colorLow or { r = 1.0, g = 0.2, b = 0.2 }
        local oClSwatch = CreateColorSwatch(oCbtRow, oClColor, function(r, g, b)
            OverrideSet("colorLow", { r = r, g = g, b = b })
        end)
        oClSwatch:SetPoint("LEFT", oClLabel, "RIGHT", 6, 0)
        oClSwatch:Show()

        -- Reset Defaults button
        local oResetBtn = CreateFrame("Button", nil, oCbtRow, "UIPanelButtonTemplate")
        oResetBtn:SetSize(60, 20)
        oResetBtn:SetPoint("LEFT", oClSwatch, "RIGHT", 14, 0)
        oResetBtn:SetText("Reset")
        oResetBtn:SetScript("OnClick", function()
            OverrideSet("colorHigh", { r = 0.2, g = 0.8, b = 0.2 })
            OverrideSet("colorMed", { r = 1.0, g = 0.8, b = 0.0 })
            OverrideSet("colorLow", { r = 1.0, g = 0.2, b = 0.2 }, true)
        end)
        oResetBtn:Show()
        y = y + 28
    end

    -- ---- Icon ----
    local oIconSec = CreateSectionLabel(parent, "Icon")
    oIconSec:SetPoint("TOPLEFT", 0, -y)
    oIconSec:Show()
    y = y + 16

    local oShowIconCheck = CreateCheckbox(parent, "Show Icon", function(checked)
        OverrideSet("showIcon", checked)
    end)
    oShowIconCheck:SetPoint("TOPLEFT", 0, -y)
    oShowIconCheck:SetChecked(bo.showIcon ~= false)
    oShowIconCheck:Show()
    y = y + 26

    local oCurSizeMode = bo.iconSizeMode or "auto"
    local oSizeModeGroup = CreateButtonGroup(parent, "Icon Size",
        { { label = "Auto", value = "auto" }, { label = "Manual", value = "manual" } },
        function() return bo.iconSizeMode or "auto" end,
        function(val) OverrideSet("iconSizeMode", val, true) end
    )
    oSizeModeGroup:SetPoint("TOPLEFT", 0, -y)
    oSizeModeGroup:Show()
    y = y + 28

    if oCurSizeMode == "manual" then
        local oIconSzSlider = CreateSlider(parent, "Icon Size (px)", 8, 120, 1, CONTROL_WIDTH - 20, function(val)
            OverrideSet("iconSize", val)
        end)
        oIconSzSlider:SetPoint("TOPLEFT", 0, -y)
        oIconSzSlider:SetInitialValue(bo.iconSize or 20)
        oIconSzSlider:Show()
        y = y + 38
    end

    local oAspectDD = CreateScrollDropdown(parent, "Aspect", (CONTROL_WIDTH - 20) / 2 - 5,
        function()
            local opts = {}
            for _, key in ipairs(ICON_ASPECT_ORDER) do
                table.insert(opts, ICON_ASPECT_LABELS[key] or key)
            end
            return opts
        end,
        function()
            local cur = bo.iconAspect or "1:1"
            return ICON_ASPECT_LABELS[cur] or cur
        end,
        function(labelVal)
            for _, key in ipairs(ICON_ASPECT_ORDER) do
                if ICON_ASPECT_LABELS[key] == labelVal then
                    OverrideSet("iconAspect", key)
                    return
                end
            end
        end
    )
    oAspectDD:SetPoint("TOPLEFT", 0, -y)
    oAspectDD:SetValue(ICON_ASPECT_LABELS[bo.iconAspect or "1:1"] or "1:1 (Square)")
    oAspectDD:Show()

    local oPosGroup = CreateButtonGroup(parent, "Position",
        { { label = "Left", value = "LEFT" }, { label = "Right", value = "RIGHT" } },
        function() return bo.iconPosition or "LEFT" end,
        function(val) OverrideSet("iconPosition", val) end
    )
    oPosGroup:SetPoint("TOPLEFT", (CONTROL_WIDTH - 20) / 2 + 5, -y - 10)
    oPosGroup:Show()
    y = y + 42

    -- ---- Text ----
    local oTxtSec = CreateSectionLabel(parent, "Text")
    oTxtSec:SetPoint("TOPLEFT", 0, -y)
    oTxtSec:Show()
    y = y + 16

    local oFontDD = CreateScrollDropdown(parent, "Font", CONTROL_WIDTH - 20,
        function()
            local list = Media and Media:GetFontList() or { "Friz Quadrata TT" }
            local opts = { "(Default)" }
            for _, name in ipairs(list) do table.insert(opts, name) end
            return opts
        end,
        function()
            local f = bo.font
            if not f or f == "" then return "(Default)" end
            return f
        end,
        function(val)
            if val == "(Default)" then val = "" end
            OverrideSet("font", val)
        end
    )
    oFontDD:SetPoint("TOPLEFT", 0, -y)
    local oFontDisplay = bo.font
    if not oFontDisplay or oFontDisplay == "" then oFontDisplay = "(Default)" end
    oFontDD:SetValue(oFontDisplay)
    oFontDD:Show()
    y = y + 40

    local oNameSzSlider = CreateSlider(parent, "Name Font Size", 6, 24, 1, CONTROL_WIDTH - 20, function(val)
        OverrideSet("nameFontSize", val)
    end)
    oNameSzSlider:SetPoint("TOPLEFT", 0, -y)
    oNameSzSlider:SetInitialValue(bo.nameFontSize or 11)
    oNameSzSlider:Show()
    y = y + 36

    local oTimeSzSlider = CreateSlider(parent, "Time Font Size", 6, 24, 1, CONTROL_WIDTH - 20, function(val)
        OverrideSet("timeFontSize", val)
    end)
    oTimeSzSlider:SetPoint("TOPLEFT", 0, -y)
    oTimeSzSlider:SetInitialValue(bo.timeFontSize or 11)
    oTimeSzSlider:Show()
    y = y + 36

    local oShowNameCheck = CreateCheckbox(parent, "Show Spell Name", function(checked)
        OverrideSet("showName", checked)
    end)
    oShowNameCheck:SetPoint("TOPLEFT", 0, -y)
    oShowNameCheck:SetChecked(bo.showName ~= false)
    oShowNameCheck:Show()

    local oShowTimeCheck = CreateCheckbox(parent, "Show Time", function(checked)
        OverrideSet("showTime", checked)
    end)
    oShowTimeCheck:SetPoint("TOPLEFT", 155, -y)
    oShowTimeCheck:SetChecked(bo.showTime ~= false)
    oShowTimeCheck:Show()
    y = y + 28

    -- Text offset sliders
    local oHalfW = (CONTROL_WIDTH - 20) / 2 - 5

    local oNxSlider = CreateSlider(parent, "Name Offset X", -100, 100, 1, oHalfW, function(val)
        OverrideSet("nameOffsetX", val)
    end)
    oNxSlider:SetPoint("TOPLEFT", 0, -y)
    oNxSlider:SetInitialValue(bo.nameOffsetX or 0)
    oNxSlider:Show()

    local oNySlider = CreateSlider(parent, "Name Offset Y", -100, 100, 1, oHalfW, function(val)
        OverrideSet("nameOffsetY", val)
    end)
    oNySlider:SetPoint("TOPLEFT", oHalfW + 10, -y)
    oNySlider:SetInitialValue(bo.nameOffsetY or 0)
    oNySlider:Show()
    y = y + 36

    local oTxSlider = CreateSlider(parent, "Time Offset X", -100, 100, 1, oHalfW, function(val)
        OverrideSet("timeOffsetX", val)
    end)
    oTxSlider:SetPoint("TOPLEFT", 0, -y)
    oTxSlider:SetInitialValue(bo.timeOffsetX or 0)
    oTxSlider:Show()

    local oTySlider = CreateSlider(parent, "Time Offset Y", -100, 100, 1, oHalfW, function(val)
        OverrideSet("timeOffsetY", val)
    end)
    oTySlider:SetPoint("TOPLEFT", oHalfW + 10, -y)
    oTySlider:SetInitialValue(bo.timeOffsetY or 0)
    oTySlider:Show()
    y = y + 36

    -- ---- Behavior ----
    local oBehSec = CreateSectionLabel(parent, "Behavior")
    oBehSec:SetPoint("TOPLEFT", 0, -y)
    oBehSec:Show()
    y = y + 16

    local oInactiveCheck = CreateCheckbox(parent, "Show When Inactive (buff not active)", function(checked)
        OverrideSet("showWhenInactive", checked)
    end)
    oInactiveCheck:SetPoint("TOPLEFT", 0, -y)
    oInactiveCheck:SetChecked(bo.showWhenInactive == true)
    oInactiveCheck:Show()
    y = y + 30

    local oFillGroup = CreateButtonGroup(parent, "Fill Mode",
        {
            { label = "Drain", value = "drain", tooltip = "Bar starts full, empties as buff ticks" },
            { label = "Fill",  value = "fill",  tooltip = "Bar starts empty, fills as buff expires" },
        },
        function() return bo.fillMode or "drain" end,
        function(val) OverrideSet("fillMode", val) end
    )
    oFillGroup:SetPoint("TOPLEFT", 0, -y)
    oFillGroup:Show()
    y = y + 30

    local oDirGroup = CreateButtonGroup(parent, "Direction",
        {
            { label = "R", value = "RIGHT", tooltip = "Fill left to right (horizontal)" },
            { label = "L", value = "LEFT",  tooltip = "Fill right to left (horizontal)" },
            { label = "U", value = "UP",    tooltip = "Fill bottom to top (vertical)" },
            { label = "D", value = "DOWN",  tooltip = "Fill top to bottom (vertical)" },
        },
        function() return bo.barDirection or "RIGHT" end,
        function(newDir)
            local oldDir = bo.barDirection or "RIGHT"
            local wasVert = (oldDir == "UP" or oldDir == "DOWN")
            local nowVert = (newDir == "UP" or newDir == "DOWN")

            if wasVert ~= nowVert then
                local w = bo.width or 200
                local h = bo.height or 20
                OverrideSet("width", h)
                OverrideSet("height", w)
            end

            OverrideSet("barDirection", newDir, true)
        end
    )
    local oDirBtnIdx = 0
    for _, child in ipairs({oDirGroup:GetChildren()}) do
        if child.GetObjectType and child:GetObjectType() == "Button" then
            child:SetSize(34, 22)
            child:ClearAllPoints()
            child:SetPoint("LEFT", 80 + (oDirBtnIdx * 38), 0)
            oDirBtnIdx = oDirBtnIdx + 1
        end
    end
    oDirGroup:SetPoint("TOPLEFT", 0, -y)
    oDirGroup:Show()
    y = y + 36

    -- Section: Tips
    local secInfo = CreateSectionLabel(parent, "Tips")
    secInfo:SetPoint("TOPLEFT", 0, -y)
    secInfo:Show()
    y = y + 22

    local infoFrame = CreateFrame("Frame", nil, parent)
    infoFrame:SetSize(CONTROL_WIDTH, 60)
    infoFrame:SetPoint("TOPLEFT", 0, -y)
    infoFrame:Show()
    local infoFS = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFS:SetPoint("TOPLEFT", 8, 0)
    infoFS:SetWidth(CONTROL_WIDTH - 16)
    infoFS:SetJustifyH("LEFT")
    infoFS:SetText("|cff666666Use |cff00ccff/tuicd buffbars layout|cff666666 to move the dock.\n\nAll docked bars now use these visual settings.|r")
    y = y + 70

    parent:SetHeight(y + 10)
end

-- ============================================================================
-- VISIBILITY TAB
-- ============================================================================

function BuffBarsUI:BuildVisibilityUI(parent)
    local y = 10
    
    local BuffBarsDock = TUICD.BuffBarsDock
    local BuffBarsData = TUICD.BuffBarsData
    
    -- Helper to get/set dock settings
    local function GetSetting(key)
        local settings = BuffBarsData:GetDockSettings()
        return settings[key]
    end
    
    local function SetSetting(key, value)
        BuffBarsData:SetDockSetting(key, value)
        -- Update dock visibility
        if BuffBarsDock and BuffBarsDock.UpdateVisibility then
            BuffBarsDock:UpdateVisibility()
        end
    end
    
    -- Section header helper
    local function CreateHeader(text)
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", 0, -y)
        header:SetText("|cffaaaaaa— " .. text .. " —|r")
        header:Show()
        y = y + 18
        return header
    end
    
    -- Checkbox helper
    local function CreateVisCheckbox(text, key)
        local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", 20, -y)
        check.Text:SetText(text)
        check:SetChecked(GetSetting(key))
        check:SetScript("OnClick", function(self)
            SetSetting(key, self:GetChecked())
        end)
        check:Show()
        y = y + 24
        return check
    end
    
    -- Title
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, -y)
    title:SetText("|cffffd100Visibility Conditions|r")
    title:Show()
    y = y + 25
    
    -- Master toggle
    local enableCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", 0, -y)
    enableCheck.Text:SetText("Enable Visibility Rules")
    enableCheck:SetChecked(GetSetting("visibilityEnabled"))
    enableCheck:SetScript("OnClick", function(self)
        SetSetting("visibilityEnabled", self:GetChecked())
    end)
    enableCheck:Show()
    y = y + 24
    
    -- Hint text
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 20, -y)
    hint:SetText("|cff888888When enabled, bars only show in checked situations:|r")
    hint:Show()
    y = y + 18
    
    -- Combat section
    CreateHeader("Combat State")
    CreateVisCheckbox("Show In Combat", "showInCombat")
    CreateVisCheckbox("Show Out of Combat", "showOutOfCombat")
    
    y = y + 5
    
    -- Group section
    CreateHeader("Group Type")
    CreateVisCheckbox("Show Solo", "showSolo")
    CreateVisCheckbox("Show in Party", "showInParty")
    CreateVisCheckbox("Show in Raid", "showInRaid")
    
    y = y + 5
    
    -- Instance section
    CreateHeader("Instance Type")
    CreateVisCheckbox("Show in Arena", "showInArena")
    CreateVisCheckbox("Show in Battleground", "showInBattleground")
    CreateVisCheckbox("Show in Dungeon", "showInDungeon")
    CreateVisCheckbox("Show in Delve", "showInDelve")
    
    y = y + 5
    
    -- Target / Mount section
    CreateHeader("Target / Mount")
    CreateVisCheckbox("Has Target", "showHasTarget")
    CreateVisCheckbox("No Target", "showNoTarget")
    CreateVisCheckbox("Mounted", "showMounted")
    CreateVisCheckbox("Not Mounted", "showNotMounted")
    
    parent:SetHeight(y + 20)
end

-- ============================================================================
-- MAIN PANEL CREATION
-- ============================================================================

function BuffBarsUI:CreatePanel()
    if mainPanel then return mainPanel end

    local dockTo = TUICD.Settings and TUICD.Settings.hubPanel

    mainPanel = CreateFrame("Frame", "TUICD_BuffBarsPanel", UIParent, "BackdropTemplate")
    mainPanel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    mainPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    mainPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    mainPanel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    mainPanel:SetFrameStrata("HIGH")
    mainPanel:SetMovable(true)
    mainPanel:EnableMouse(true)
    mainPanel:RegisterForDrag("LeftButton")
    mainPanel:SetScript("OnDragStart", mainPanel.StartMoving)
    mainPanel:SetScript("OnDragStop", mainPanel.StopMovingOrSizing)
    mainPanel:SetClampedToScreen(true)
    mainPanel:Hide()

    if dockTo then
        mainPanel:SetPoint("TOPLEFT", dockTo, "TOPRIGHT", 0, 0)
    else
        mainPanel:SetPoint("CENTER", 0, 0)
    end

    -- Title
    local title = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd100Buff Bars|r")

    -- ========================================
    -- Left side: Spell list
    -- ========================================
    local listBg = CreateFrame("Frame", nil, mainPanel, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 15, -40)
    listBg:SetSize(LIST_WIDTH, PANEL_HEIGHT - 210)
    listBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    listBg:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    listBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    scrollFrame = CreateFrame("ScrollFrame", "TUICD_BuffBarsSpellScroll", listBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 4)

    scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(LIST_WIDTH - 30, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- ========================================
    -- Info area below list (no manual add for buff bars)
    -- ========================================
    local infoArea = CreateFrame("Frame", nil, mainPanel)
    infoArea:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 0, -6)
    infoArea:SetSize(LIST_WIDTH, 150)

    local infoLabel = infoArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLabel:SetPoint("TOPLEFT", 2, 0)
    infoLabel:SetWidth(LIST_WIDTH - 4)
    infoLabel:SetJustifyH("LEFT")
    infoLabel:SetText("|cff888888Buff bars are discovered from\nBlizzard's Cooldown Manager.\nUse |cff00ccff/tuicd buffbars discover|cff888888\nto scan for available buffs.|r")

    -- Discover button
    local discoverBtn = CreateFrame("Button", nil, infoArea, "UIPanelButtonTemplate")
    discoverBtn:SetSize(LIST_WIDTH, 22)
    discoverBtn:SetPoint("TOPLEFT", 0, -52)
    discoverBtn:SetText("Discover Buffs")
    discoverBtn:SetScript("OnClick", function()
        BuffBarsData:DiscoverSlots()
        C_Timer.After(0.3, function()
            RefreshSpellList()
        end)
    end)
    discoverBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Discover Buffs")
        local count = BuffBarsData:GetDiscoveredSlotCount()
        GameTooltip:AddLine("Scans Cooldown Manager for buff slots.\nCurrently discovered: " .. count .. " slot(s).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    discoverBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Clear All button
    local clearAllBtn = CreateFrame("Button", nil, infoArea, "UIPanelButtonTemplate")
    clearAllBtn:SetSize(LIST_WIDTH, 22)
    clearAllBtn:SetPoint("TOPLEFT", discoverBtn, "BOTTOMLEFT", 0, -4)
    clearAllBtn:SetText("|cffff4444Clear All|r")
    clearAllBtn:SetScript("OnClick", function()
        if not IsShiftKeyDown() then
            TUICD:Print("Hold Shift and click to clear all buff bars.")
            return
        end
        BuffBarsFrames:ClearPreviewBar()
        BuffBarsFrames:DestroyAll()
        local count = BuffBarsData:RemoveAllSlots()
        selectedBarKey = nil
        RefreshSpellList()
        BuffBarsUI:RefreshConfigPanel()
        TUICD:Print("Cleared " .. count .. " buff bar(s).")
    end)
    clearAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clear All Buff Bars")
        GameTooltip:AddLine("Removes every buff from the bars list.\n|cffff8888Shift-click to confirm.|r", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    clearAllBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- ========================================
    -- Right side: Tab bar + Scrollable config
    -- ========================================
    local configBg = CreateFrame("Frame", nil, mainPanel, "BackdropTemplate")
    configBg:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 10, 0)
    configBg:SetPoint("BOTTOMRIGHT", mainPanel, "BOTTOMRIGHT", -15, 15)
    configBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    configBg:SetBackdropColor(0.09, 0.09, 0.09, 0.5)
    configBg:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, configBg)
    tabBar:SetPoint("TOPLEFT", 6, -4)
    tabBar:SetPoint("TOPRIGHT", -6, -4)
    tabBar:SetHeight(22)

    local function SelectTab(tabKey)
        activeTab = tabKey
        for key, btn in pairs(tabButtons) do
            if key == tabKey then
                btn:GetFontString():SetTextColor(1, 0.82, 0)
                btn._underline:Show()
            else
                btn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
                btn._underline:Hide()
            end
        end
        BuffBarsUI:RefreshConfigPanel()
    end

    local tabDefs = {
        { key = "spell", label = "Spell Config" },
        { key = "dock",  label = "Dock" },
        { key = "visibility", label = "Visibility" },
    }
    local tabX = 0
    for _, def in ipairs(tabDefs) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetHeight(20)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT")
        fs:SetText(def.label)
        btn:SetFontString(fs)
        btn:SetWidth(fs:GetStringWidth() + 16)
        btn:SetPoint("BOTTOMLEFT", tabX, 0)

        local underline = btn:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(2)
        underline:SetPoint("BOTTOMLEFT", 0, -2)
        underline:SetPoint("BOTTOMRIGHT", 0, -2)
        underline:SetColorTexture(1, 0.82, 0, 1)
        underline:Hide()
        btn._underline = underline

        btn:SetScript("OnClick", function() SelectTab(def.key) end)
        tabButtons[def.key] = btn
        tabX = tabX + btn:GetWidth() + 12
    end

    -- Separator line below tabs
    local tabSep = configBg:CreateTexture(nil, "ARTWORK")
    tabSep:SetPoint("TOPLEFT", 6, -28)
    tabSep:SetPoint("TOPRIGHT", -6, -28)
    tabSep:SetHeight(1)
    tabSep:SetColorTexture(0.3, 0.3, 0.3, 0.6)

    -- Scroll frame (below tab bar)
    configFrame = CreateFrame("ScrollFrame", "TUICD_BuffBarsConfigScroll", configBg, "UIPanelScrollFrameTemplate")
    configFrame:SetPoint("TOPLEFT", 6, -32)
    configFrame:SetPoint("BOTTOMRIGHT", -26, 6)

    configScrollChild = CreateFrame("Frame", nil, configFrame)
    configScrollChild:SetSize(CONTROL_WIDTH, 1)

    dockScrollChild = CreateFrame("Frame", nil, configFrame)
    dockScrollChild:SetSize(CONTROL_WIDTH, 1)
    dockScrollChild:Hide()

    local visibilityScrollChild = CreateFrame("Frame", nil, configFrame)
    visibilityScrollChild:SetSize(CONTROL_WIDTH, 1)
    visibilityScrollChild:Hide()
    BuffBarsUI._visibilityScrollChild = visibilityScrollChild

    configFrame:SetScrollChild(configScrollChild)

    -- Set initial tab
    activeTab = "spell"
    if tabButtons["spell"] then
        tabButtons["spell"]:GetFontString():SetTextColor(1, 0.82, 0)
        tabButtons["spell"]._underline:Show()
    end
    if tabButtons["dock"] then
        tabButtons["dock"]:GetFontString():SetTextColor(0.5, 0.5, 0.5)
    end

    -- Close button
    local closeBtn = CreateFrame("Button", nil, mainPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() mainPanel:Hide() end)

    RefreshSpellList()
    self:RefreshConfigPanel()

    return mainPanel
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function BuffBarsUI:Show()
    if not mainPanel then
        self:CreatePanel()
    end

    -- Dock to main hub
    local dockTo = TUICD.Settings and TUICD.Settings.hubPanel
    if dockTo and mainPanel then
        mainPanel:ClearAllPoints()
        mainPanel:SetPoint("TOPLEFT", dockTo, "TOPRIGHT", 0, 0)
    end

    RefreshSpellList()
    self:RefreshConfigPanel()
    mainPanel:Show()

    -- Restore preview for selected bar
    if selectedBarKey then
        BuffBarsFrames:SetPreviewBar(selectedBarKey)
    end
end

function BuffBarsUI:Hide()
    if mainPanel then
        BuffBarsFrames:ClearPreviewBar()
        CloseActivePopup()
        mainPanel:Hide()
    end
end

function BuffBarsUI:IsShown()
    return mainPanel and mainPanel:IsShown()
end

function BuffBarsUI:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function BuffBarsUI:HideAllPanels()
    self:Hide()
end

function BuffBarsUI:Refresh()
    if mainPanel and mainPanel:IsShown() then
        RefreshSpellList()
        self:RefreshConfigPanel()
    end
end

return BuffBarsUI
