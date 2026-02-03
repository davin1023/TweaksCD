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
local PANEL_HEIGHT    = 650
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

    -- Hide ALL children from both scroll containers
    for _, child in ipairs({configScrollChild:GetChildren()}) do child:Hide() end
    if dockScrollChild then
        for _, child in ipairs({dockScrollChild:GetChildren()}) do child:Hide() end
    end
    CloseActivePopup()

    if activeTab == "dock" then
        configFrame:SetScrollChild(dockScrollChild)
        self:BuildDockSettingsUI(dockScrollChild)
        return
    end

    -- Spell tab
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

    local slotIndex = BuffBarsData.ParseBarKey(selectedBarKey)
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
        local si = BuffBarsData.ParseBarKey(selectedBarKey)
        if si then
            BuffBarsData:EnableSlot(si, checked)
            BuffBarsFrames:OnConfigChanged(selectedBarKey)
            RefreshSpellList()
        end
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
        SetAndApply("colorByTime", checked, true)
    end)
    cbtCheck:SetPoint("TOPLEFT", 0, -y)
    cbtCheck:SetChecked(config.colorByTime == true)
    cbtCheck:Show()
    y = y + 26

    if config.colorByTime then
        local highSlider = CreateSlider(configScrollChild, "High (sec)", 2, 120, 1, CONTROL_WIDTH, function(val)
            SetAndApply("colorHighSeconds", val)
        end)
        highSlider:SetPoint("TOPLEFT", 0, -y)
        highSlider:SetInitialValue(config.colorHighSeconds or 10)
        highSlider:Show()
        y = y + 38

        local medSlider = CreateSlider(configScrollChild, "Medium (sec)", 1, 60, 1, CONTROL_WIDTH, function(val)
            SetAndApply("colorMedSeconds", val)
        end)
        medSlider:SetPoint("TOPLEFT", 0, -y)
        medSlider:SetInitialValue(config.colorMedSeconds or 5)
        medSlider:Show()
        y = y + 38

        -- Color swatches row
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

        local resetBtn = CreateFrame("Button", nil, cbtRow, "UIPanelButtonTemplate")
        resetBtn:SetSize(60, 20)
        resetBtn:SetPoint("LEFT", cbtLowSwatch, "RIGHT", 14, 0)
        resetBtn:SetText("Reset")
        resetBtn:SetScript("OnClick", function()
            SetAndApply("colorHighSeconds", 10)
            SetAndApply("colorMedSeconds", 5)
            SetAndApply("colorHigh", { r = 0.2, g = 0.8, b = 0.2 })
            SetAndApply("colorMed", { r = 1.0, g = 0.8, b = 0.0 })
            SetAndApply("colorLow", { r = 1.0, g = 0.2, b = 0.2 }, true)
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
        if dock then dock:QueueLayout() end
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
    end)
    y = y + 34

    -- Spacing slider
    local spacingSlider = CreateSlider(parent, "Spacing (px)", 0, 20, 1, CONTROL_WIDTH - 20, function(val)
        DockSet("spacing", val)
    end)
    spacingSlider:SetPoint("TOPLEFT", 0, -y)
    spacingSlider:SetInitialValue(BuffBarsData:GetDockSetting("spacing") or 2)
    spacingSlider:Show()
    y = y + 44

    -- Section: Tips
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
end

-- ============================================================================
-- MAIN PANEL CREATION
-- ============================================================================

function BuffBarsUI:CreatePanel()
    if mainPanel then return mainPanel end

    -- Get dock target (Settings hub)
    local dockTo = nil
    if TUICD.Settings then
        if TUICD.Settings.GetHubPanel then
            dockTo = TUICD.Settings:GetHubPanel()
        elseif TUICD.Settings.hubPanel then
            dockTo = TUICD.Settings.hubPanel
        end
    end

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
    listBg:SetSize(LIST_WIDTH, PANEL_HEIGHT - 130)
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
    infoArea:SetSize(LIST_WIDTH, 60)

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

    configScrollChild = CreateFrame("Frame")
    configScrollChild:SetSize(CONTROL_WIDTH, 1)

    dockScrollChild = CreateFrame("Frame")
    dockScrollChild:SetSize(CONTROL_WIDTH, 1)

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

    -- Dock to Settings Hub
    local dockTo = nil
    if TUICD.Settings and TUICD.Settings.GetHubPanel then
        dockTo = TUICD.Settings:GetHubPanel()
    end
    if dockTo and mainPanel then
        mainPanel:ClearAllPoints()
        mainPanel:SetPoint("TOPLEFT", dockTo, "TOPRIGHT", 0, 0)
    end

    RefreshSpellList()
    self:RefreshConfigPanel()
    mainPanel:Show()
end

function BuffBarsUI:Hide()
    if mainPanel then
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
