-- ============================================================================
-- TUICD: Cooldowns - Docks Settings UI
-- Configuration panel for dock containers
-- Migrated from TUICD: Cooldowns (standalone) to TUICD suite
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.DocksUI = {}
local DocksUI = TUICD.DocksUI

-- ============================================================================
-- LOCAL STATE
-- ============================================================================

local panel = nil
local selectedDock = 1
local dockTabs = {}
local contentFrame = nil
local scrollChild = nil
local initialized = false

-- Panel dimensions
local PANEL_WIDTH = 420
local PANEL_HEIGHT = 700

-- Standard dark backdrop (matching TUICD style)
local BACKDROP_DARK = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

-- Helper: Set a VO setting and apply immediately if VO is enabled
local function SetVOSettingAndApply(settingKey, value)
    if not TUICD.Docks then return end
    TUICD.Docks:SetDockSetting(selectedDock, settingKey, value)
    -- Apply immediately if visual override is enabled
    local settings = TUICD.Docks:GetDockSettings(selectedDock)
    if settings and settings.visualOverrideEnabled then
        TUICD.Docks:ApplyVisualOverride(selectedDock)
    end
end

-- Anchor point options for dropdowns
local ANCHOR_OPTIONS = {
    { label = "Top Left", value = "TOPLEFT" },
    { label = "Top", value = "TOP" },
    { label = "Top Right", value = "TOPRIGHT" },
    { label = "Left", value = "LEFT" },
    { label = "Center", value = "CENTER" },
    { label = "Right", value = "RIGHT" },
    { label = "Bottom Left", value = "BOTTOMLEFT" },
    { label = "Bottom", value = "BOTTOM" },
    { label = "Bottom Right", value = "BOTTOMRIGHT" },
}

local ASPECT_OPTIONS = {
    { label = "1:1 (Square)", value = "1:1" },
    { label = "4:3", value = "4:3" },
    { label = "3:4", value = "3:4" },
    { label = "16:9 (Wide)", value = "16:9" },
    { label = "9:16 (Tall)", value = "9:16" },
    { label = "2:1", value = "2:1" },
    { label = "1:2", value = "1:2" },
}

-- ============================================================================
-- UI HELPERS
-- ============================================================================

local function CreateBackdrop(frame)
    if frame.SetBackdrop then
        frame:SetBackdrop(BACKDROP_DARK)
    elseif BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
        frame:SetBackdrop(BACKDROP_DARK)
    end
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, height or 24)
    button:SetText(text)
    return button
end

local function CreateCheckbox(parent, text, tooltip)
    local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    check.Text:SetText(text)
    if tooltip then
        check.tooltipText = tooltip
    end
    return check
end

local function CreateSlider(parent, label, min, max, step, width)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or 200, 45)
    
    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOP", 0, -15)
    slider:SetSize((width or 200) - 20, 17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    
    slider.Low:SetText(tostring(min))
    slider.High:SetText(tostring(max))
    
    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("BOTTOM", slider, "TOP", 0, 3)
    title:SetText(label)
    
    local value = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOP", slider, "BOTTOM", 0, -2)
    
    slider:SetScript("OnValueChanged", function(self, val)
        value:SetText(string.format("%.1f", val))
    end)
    
    container.slider = slider
    container.value = value
    container.label = title
    
    return container
end

local function CreateCompactSlider(parent, label, min, max, step, width)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or 140, 30)
    
    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 0, 0)
    title:SetText(label)
    title:SetWidth(60)
    title:SetJustifyH("LEFT")
    
    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", 65, 0)
    slider:SetSize(50, 14)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText("")
    slider.High:SetText("")
    
    local value = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("LEFT", slider, "RIGHT", 5, 0)
    
    slider:SetScript("OnValueChanged", function(self, val)
        value:SetText(string.format("%.1f", val))
    end)
    
    container.slider = slider
    container.value = value
    container.label = title
    
    return container
end

-- Slider with editable input box for Visual Override section
local function CreateVOSlider(parent, label, min, max, step, isPercent, decimals)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(320, 28)
    
    -- Label on left
    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 0, 0)
    title:SetText(label)
    title:SetWidth(90)
    title:SetJustifyH("LEFT")
    
    -- Slider in middle
    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", 95, 0)
    slider:SetSize(140, 17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    -- Safely hide min/max text (might not exist in all templates)
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end
    
    -- Edit box on right
    local editBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    editBox:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    editBox:SetSize(50, 20)
    editBox:SetAutoFocus(false)
    editBox:SetJustifyH("CENTER")
    
    local decPlaces = decimals or (step < 1 and 1 or 0)
    local formatStr = "%." .. decPlaces .. "f"
    if isPercent then formatStr = formatStr .. "%%" end
    
    -- Update edit box when slider changes
    slider:SetScript("OnValueChanged", function(self, val)
        local displayVal = isPercent and (val * 100) or val
        editBox:SetText(string.format(formatStr, displayVal))
        if container.onValueChanged then
            container.onValueChanged(val)
        end
    end)
    
    -- Update slider when edit box changes
    editBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText():gsub("%%", "")
        local val = tonumber(text)
        if val then
            if isPercent then val = val / 100 end
            val = math.max(min, math.min(max, val))
            slider:SetValue(val)
        end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        local displayVal = isPercent and (slider:GetValue() * 100) or slider:GetValue()
        self:SetText(string.format(formatStr, displayVal))
        self:ClearFocus()
    end)
    
    container.slider = slider
    container.editBox = editBox
    container.label = title
    
    -- Helper to set value
    function container:SetValue(val)
        slider:SetValue(val)
    end
    
    -- Helper to get value
    function container:GetValue()
        return slider:GetValue()
    end
    
    return container
end

local function CreateDropdown(parent, label, width)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or 180, 45)
    
    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    
    local dropdown = CreateFrame("Frame", nil, container, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", -16, -15)
    UIDropDownMenu_SetWidth(dropdown, (width or 180) - 40)
    
    container.dropdown = dropdown
    
    return container
end

local function CreateCompactDropdown(parent, label, width)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or 180, 30)
    
    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 0, 0)
    title:SetText(label)
    title:SetWidth(50)
    title:SetJustifyH("LEFT")
    
    local dropdown = CreateFrame("Frame", nil, container, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", 45, 0)
    UIDropDownMenu_SetWidth(dropdown, (width or 180) - 70)
    
    container.dropdown = dropdown
    
    return container
end

local function CreateSectionHeader(parent, text)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetText("|cffaaaaaa— " .. text .. " —|r")
    return header
end

local function CreateColorSwatch(parent, defaultColor)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(20, 20)
    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.5, 0.5, 0.5, 1)
    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    local c = defaultColor or {1, 1, 1, 1}
    tex:SetColorTexture(c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1, 1)
    swatch.tex = tex
    return swatch
end

-- ============================================================================
-- DOCK TAB SELECTION
-- ============================================================================

local function SelectDockTab(dockIndex)
    selectedDock = dockIndex
    
    -- Update tab visuals
    for i, tab in ipairs(dockTabs) do
        if i == dockIndex then
            tab:GetFontString():SetTextColor(1, 0.82, 0)  -- Gold
        else
            tab:GetFontString():SetTextColor(0.6, 0.6, 0.6)  -- Grey
        end
    end
    
    -- Refresh content
    DocksUI:RefreshContent()
end

-- ============================================================================
-- VISUAL OVERRIDE GREYOUT HELPER
-- ============================================================================

local function SetControlsGreyedOut(controls, greyed)
    local alpha = greyed and 0.4 or 1.0
    for _, ctrl in ipairs(controls) do
        if ctrl then
            if ctrl.SetAlpha then ctrl:SetAlpha(alpha) end
            if ctrl.Disable and greyed then ctrl:Disable()
            elseif ctrl.Enable and not greyed then ctrl:Enable() end
            -- For sliders
            if ctrl.slider then
                if greyed then ctrl.slider:Disable() else ctrl.slider:Enable() end
            end
            -- For edit boxes in slider combos
            if ctrl.editBox then
                if greyed then ctrl.editBox:Disable() else ctrl.editBox:Enable() end
            end
            -- For dropdowns
            if ctrl.dropdown then
                if greyed then UIDropDownMenu_DisableDropDown(ctrl.dropdown)
                else UIDropDownMenu_EnableDropDown(ctrl.dropdown) end
            end
        end
    end
end

-- ============================================================================
-- CONTENT CREATION
-- ============================================================================

local function CreateDockContent(parent)
    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth() - 10, 1600)  -- Tall enough for all content
    scrollFrame:SetScrollChild(scrollChild)
    
    local content = scrollChild
    local yOffset = -10
    local leftMargin = 5
    
    -- Enable checkbox
    local enableCB = CreateCheckbox(content, "Enable Dock")
    enableCB:SetPoint("TOPLEFT", leftMargin, yOffset)
    enableCB:SetScript("OnClick", function(self)
        local enabled = self:GetChecked()
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "enabled", enabled)
            -- Dock visibility is managed by Docks module
            -- LayoutUI will automatically update overlay on next refresh
        end
    end)
    content.enableCB = enableCB
    yOffset = yOffset - 30
    
    -- Custom name
    local nameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", leftMargin, yOffset)
    nameLabel:SetText("Custom Name:")
    
    local nameEdit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    nameEdit:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
    nameEdit:SetSize(150, 20)
    nameEdit:SetAutoFocus(false)
    nameEdit:SetScript("OnEnterPressed", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "name", self:GetText())
            -- Name update will be reflected when Layout Mode refreshes
        end
        self:ClearFocus()
    end)
    nameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    content.nameEdit = nameEdit
    yOffset = yOffset - 30
    
    -- ========================================================================
    -- REAPPEARANCE SETTINGS SECTION
    -- ========================================================================
    local reappearHeader = CreateSectionHeader(content, "Reappearance Settings")
    reappearHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
    content.reappearHeader = reappearHeader
    yOffset = yOffset - 25
    
    -- Early Show slider + edit box
    local earlyShowContainer = CreateFrame("Frame", nil, content)
    earlyShowContainer:SetSize(380, 30)
    earlyShowContainer:SetPoint("TOPLEFT", leftMargin, yOffset)
    
    local esLabel = earlyShowContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    esLabel:SetPoint("LEFT", 0, 0)
    esLabel:SetText("Early Show")
    esLabel:SetWidth(70)
    esLabel:SetJustifyH("LEFT")
    
    local esSlider = CreateFrame("Slider", nil, earlyShowContainer, "OptionsSliderTemplate")
    esSlider:SetPoint("LEFT", 75, 0)
    esSlider:SetSize(160, 17)
    esSlider:SetMinMaxValues(0, 120)
    esSlider:SetValueStep(1)
    esSlider:SetObeyStepOnDrag(true)
    if esSlider.Low then esSlider.Low:SetText(""); esSlider.Low:Hide() end
    if esSlider.High then esSlider.High:SetText(""); esSlider.High:Hide() end
    if esSlider.Text then esSlider.Text:SetText(""); esSlider.Text:Hide() end
    
    local esEditBox = CreateFrame("EditBox", nil, earlyShowContainer, "InputBoxTemplate")
    esEditBox:SetPoint("LEFT", esSlider, "RIGHT", 10, 0)
    esEditBox:SetSize(45, 20)
    esEditBox:SetAutoFocus(false)
    esEditBox:SetJustifyH("CENTER")
    esEditBox:SetMaxLetters(5)
    
    local esUnit = earlyShowContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    esUnit:SetPoint("LEFT", esEditBox, "RIGHT", 4, 0)
    esUnit:SetText("|cff888888sec|r")
    
    local esUpdating = false
    esSlider:SetScript("OnValueChanged", function(self, val)
        if esUpdating then return end
        esUpdating = true
        val = math.floor(val + 0.5)
        if val == 0 then
            esEditBox:SetText("Off")
        else
            esEditBox:SetText(tostring(val))
        end
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "earlyShowSeconds", val)
        end
        esUpdating = false
    end)
    
    esEditBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text == "Off" or text == "off" or text == "0" then
            esSlider:SetValue(0)
        else
            local val = tonumber(text)
            if val and val >= 0 then
                val = math.floor(val + 0.5)
                esSlider:SetValue(math.min(val, 120))
                if val > 120 then
                    esEditBox:SetText(tostring(val))
                end
                if TUICD.Docks then
                    TUICD.Docks:SetDockSetting(selectedDock, "earlyShowSeconds", val)
                end
            end
        end
        self:ClearFocus()
    end)
    esEditBox:SetScript("OnEscapePressed", function(self)
        local val = math.floor(esSlider:GetValue() + 0.5)
        self:SetText(val == 0 and "Off" or tostring(val))
        self:ClearFocus()
    end)
    
    earlyShowContainer.slider = esSlider
    earlyShowContainer.editBox = esEditBox
    content.earlyShowSlider = earlyShowContainer
    yOffset = yOffset - 28
    
    local earlyShowHint = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    earlyShowHint:SetPoint("TOPLEFT", leftMargin + 5, yOffset)
    earlyShowHint:SetWidth(380)
    earlyShowHint:SetJustifyH("LEFT")
    earlyShowHint:SetText("|cff888888Show hidden-on-cooldown icons early, X seconds before ready. (0 = Off)|r")
    content.earlyShowHint = earlyShowHint
    yOffset = yOffset - 22
    
    -- ── Flash on Reappearance ──
    local flashEnableCB = CreateCheckbox(content, "Flash on Reappearance")
    flashEnableCB:SetPoint("TOPLEFT", leftMargin, yOffset)
    flashEnableCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "flashEnabled", self:GetChecked())
        end
        DocksUI:RefreshContent()
    end)
    content.flashEnableCB = flashEnableCB
    yOffset = yOffset - 28
    
    -- Flash Trigger dropdown
    local flashTriggerLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    flashTriggerLabel:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    flashTriggerLabel:SetText("Trigger:")
    flashTriggerLabel:SetTextColor(0.8, 0.8, 0.8)
    content.flashTriggerLabel = flashTriggerLabel
    
    local flashTriggerDropdown = CreateFrame("Frame", "TweaksCD_FlashTriggerDropdown", content, "UIDropDownMenuTemplate")
    flashTriggerDropdown:SetPoint("LEFT", flashTriggerLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(flashTriggerDropdown, 120)
    content.flashTriggerDropdown = flashTriggerDropdown
    yOffset = yOffset - 30
    
    -- Flash Type dropdown (pixel/shine/glow - matches multi-tracker styles)
    local flashTypeLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    flashTypeLabel:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    flashTypeLabel:SetText("Glow Style:")
    flashTypeLabel:SetTextColor(0.8, 0.8, 0.8)
    content.flashTypeLabel = flashTypeLabel
    
    local flashTypeDropdown = CreateFrame("Frame", "TweaksCD_FlashTypeDropdown", content, "UIDropDownMenuTemplate")
    flashTypeDropdown:SetPoint("LEFT", flashTypeLabel, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(flashTypeDropdown, 120)
    content.flashTypeDropdown = flashTypeDropdown
    yOffset = yOffset - 30
    
    -- Glow Color swatch
    local flashColorLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    flashColorLabel:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    flashColorLabel:SetText("Glow Color:")
    flashColorLabel:SetTextColor(0.8, 0.8, 0.8)
    content.flashColorLabel = flashColorLabel
    
    local flashColorSwatch = CreateFrame("Button", nil, content)
    flashColorSwatch:SetSize(20, 20)
    flashColorSwatch:SetPoint("LEFT", flashColorLabel, "RIGHT", 10, 0)
    local flashColorBorder = flashColorSwatch:CreateTexture(nil, "BACKGROUND")
    flashColorBorder:SetPoint("TOPLEFT", -2, 2)
    flashColorBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    flashColorBorder:SetColorTexture(0.5, 0.5, 0.5, 1)
    local flashColorTex = flashColorSwatch:CreateTexture(nil, "ARTWORK")
    flashColorTex:SetAllPoints()
    flashColorTex:SetColorTexture(1, 1, 1, 1)
    flashColorSwatch.tex = flashColorTex
    flashColorSwatch:SetScript("OnClick", function(self)
        local settings = TUICD.Docks and TUICD.Docks:GetDockSettings(selectedDock)
        local c = settings and settings.flashColor or { r = 1, g = 0.82, b = 0, a = 1 }
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c.r, g = c.g, b = c.b,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                if TUICD.Docks then
                    TUICD.Docks:SetDockSetting(selectedDock, "flashColor", { r = r, g = g, b = b, a = 1 })
                end
                self.tex:SetColorTexture(r, g, b, 1)
            end,
            cancelFunc = function(prev)
                if TUICD.Docks then
                    TUICD.Docks:SetDockSetting(selectedDock, "flashColor", { r = prev.r, g = prev.g, b = prev.b, a = 1 })
                end
                self.tex:SetColorTexture(prev.r, prev.g, prev.b, 1)
            end,
        })
    end)
    content.flashColorSwatch = flashColorSwatch
    yOffset = yOffset - 28
    
    -- Thickness slider (for Pixel Border style)
    local flashThicknessSlider = CreateVOSlider(content, "Thickness:", 1, 6, 1, false, 0)
    flashThicknessSlider:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    flashThicknessSlider.onValueChanged = function(val)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "flashThickness", val)
        end
    end
    content.flashThicknessSlider = flashThicknessSlider
    yOffset = yOffset - 28
    
    -- Scale slider (for Spell Glow style)
    local flashScaleSlider = CreateVOSlider(content, "Scale:", 0.5, 2.0, 0.1, true, 1)
    flashScaleSlider:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    flashScaleSlider.onValueChanged = function(val)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "flashScale", val)
        end
    end
    content.flashScaleSlider = flashScaleSlider
    yOffset = yOffset - 28
    
    -- Speed slider (pulse speed for all styles)
    local flashSpeedSlider = CreateVOSlider(content, "Speed:", 0.1, 2.0, 0.1, true, 1)
    flashSpeedSlider:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    flashSpeedSlider.onValueChanged = function(val)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "flashSpeed", val)
        end
    end
    content.flashSpeedSlider = flashSpeedSlider
    yOffset = yOffset - 28
    
    -- Intensity slider (brightness)
    local flashIntensitySlider = CreateVOSlider(content, "Intensity:", 0.1, 1.0, 0.05, true, 2)
    flashIntensitySlider:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    flashIntensitySlider.onValueChanged = function(val)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "flashIntensity", val)
        end
    end
    content.flashIntensitySlider = flashIntensitySlider
    yOffset = yOffset - 28
    
    -- Duration slider (auto-hide timer)
    local flashDurSlider = CreateVOSlider(content, "Duration:", 0.5, 10.0, 0.5, true, 1)
    flashDurSlider:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    flashDurSlider.onValueChanged = function(val)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "flashDuration", val)
        end
    end
    content.flashDurSlider = flashDurSlider
    
    -- Hint text
    local flashHint = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    flashHint:SetPoint("TOPLEFT", flashDurSlider, "BOTTOMLEFT", 0, -2)
    flashHint:SetText("|cff888888Thickness → Pixel Border  |  Scale → Spell Glow|r")
    flashHint:SetJustifyH("LEFT")
    content.flashHint = flashHint
    yOffset = yOffset - 42
    
    -- ── Pulse on Reappearance ──
    local pulseEnableCB = CreateCheckbox(content, "Pulse on Reappearance")
    pulseEnableCB:SetPoint("TOPLEFT", leftMargin, yOffset)
    pulseEnableCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "pulseEnabled", self:GetChecked())
        end
        DocksUI:RefreshContent()
    end)
    content.pulseEnableCB = pulseEnableCB
    yOffset = yOffset - 28
    
    -- Pulse Trigger dropdown
    local pulseTriggerLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pulseTriggerLabel:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    pulseTriggerLabel:SetText("Trigger:")
    pulseTriggerLabel:SetTextColor(0.8, 0.8, 0.8)
    content.pulseTriggerLabel = pulseTriggerLabel
    
    local pulseTriggerDropdown = CreateFrame("Frame", "TweaksCD_PulseTriggerDropdown", content, "UIDropDownMenuTemplate")
    pulseTriggerDropdown:SetPoint("LEFT", pulseTriggerLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(pulseTriggerDropdown, 120)
    content.pulseTriggerDropdown = pulseTriggerDropdown
    yOffset = yOffset - 30
    
    -- Pulse Scale slider
    local pulseScaleSlider = CreateVOSlider(content, "Scale:", 1.1, 2.0, 0.1, false, 1)
    pulseScaleSlider:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    pulseScaleSlider.onValueChanged = function(val)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "pulseScale", val)
        end
    end
    content.pulseScaleSlider = pulseScaleSlider
    yOffset = yOffset - 28
    
    -- Pulse Duration slider
    local pulseDurSlider = CreateVOSlider(content, "Duration:", 0.1, 2.0, 0.1, false, 1)
    pulseDurSlider:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    pulseDurSlider.onValueChanged = function(val)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "pulseDuration", val)
        end
    end
    content.pulseDurSlider = pulseDurSlider
    yOffset = yOffset - 28
    
    -- Pulse Count slider
    local pulseCountSlider = CreateVOSlider(content, "Pulses:", 1, 10, 1, false, 0)
    pulseCountSlider:SetPoint("TOPLEFT", leftMargin + 15, yOffset)
    pulseCountSlider.onValueChanged = function(val)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "pulseCount", val)
        end
    end
    content.pulseCountSlider = pulseCountSlider
    yOffset = yOffset - 35
    
    -- ========================================================================
    -- VISUAL OVERRIDE SECTION
    -- ========================================================================
    local voHeader = CreateSectionHeader(content, "Visual Override")
    voHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
    yOffset = yOffset - 25
    
    -- Enable Visual Override checkbox
    local voEnableCB = CreateCheckbox(content, "Enable Visual Override (applies to all icons in dock)")
    voEnableCB:SetPoint("TOPLEFT", leftMargin, yOffset)
    voEnableCB:SetScript("OnClick", function(self)
        local enabled = self:GetChecked()
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "visualOverrideEnabled", enabled)
        end
        DocksUI:RefreshContent()  -- Update greyed out state
    end)
    content.voEnableCB = voEnableCB
    yOffset = yOffset - 32
    
    -- Apply button
    local voApplyBtn = CreateButton(content, "Apply to Icons", 140, 24)
    voApplyBtn:SetPoint("TOPLEFT", leftMargin, yOffset)
    voApplyBtn:SetScript("OnClick", function()
        if TUICD.Docks then
            TUICD.Docks:ApplyVisualOverride(selectedDock)
            if TUICD.Print then
                TUICD:Print("Visual override applied to Dock " .. selectedDock)
            end
        end
    end)
    content.voApplyBtn = voApplyBtn
    yOffset = yOffset - 38
    
    -- Icon Size slider with edit box
    local voIconSizeSlider = CreateVOSlider(content, "Icon Size", 16, 80, 1, false, 0)
    voIconSizeSlider:SetPoint("TOPLEFT", leftMargin, yOffset)
    voIconSizeSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_iconSize", val)
    end
    content.voIconSizeSlider = voIconSizeSlider
    yOffset = yOffset - 35
    
    -- Opacity slider with edit box (percentage)
    local voOpacitySlider = CreateVOSlider(content, "Opacity", 0, 1, 0.05, true, 0)
    voOpacitySlider:SetPoint("TOPLEFT", leftMargin, yOffset)
    voOpacitySlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_opacity", val)
    end
    content.voOpacitySlider = voOpacitySlider
    yOffset = yOffset - 35
    
    -- Aspect Ratio dropdown
    local voAspectLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voAspectLabel:SetPoint("TOPLEFT", leftMargin, yOffset + 4)
    voAspectLabel:SetText("Aspect Ratio")
    voAspectLabel:SetWidth(90)
    voAspectLabel:SetJustifyH("LEFT")
    
    local voAspectDropdown = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate")
    voAspectDropdown:SetPoint("LEFT", voAspectLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(voAspectDropdown, 140)
    UIDropDownMenu_Initialize(voAspectDropdown, function(self, level)
        for _, opt in ipairs(ASPECT_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(voAspectDropdown, opt.value)
                SetVOSettingAndApply("vo_aspectRatio", opt.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    content.voAspectDropdown = { dropdown = voAspectDropdown }
    yOffset = yOffset - 35
    
    -- Show Sweep checkbox
    local voShowSweepCB = CreateCheckbox(content, "Show Sweep Animation")
    voShowSweepCB:SetPoint("TOPLEFT", leftMargin, yOffset)
    voShowSweepCB:SetScript("OnClick", function(self)
        SetVOSettingAndApply("vo_showSweep", self:GetChecked())
    end)
    content.voShowSweepCB = voShowSweepCB
    yOffset = yOffset - 28
    
    -- Show Countdown Text checkbox
    local voShowCDTextCB = CreateCheckbox(content, "Show Countdown Text")
    voShowCDTextCB:SetPoint("TOPLEFT", leftMargin, yOffset)
    voShowCDTextCB:SetScript("OnClick", function(self)
        SetVOSettingAndApply("vo_showCountdownText", self:GetChecked())
    end)
    content.voShowCDTextCB = voShowCDTextCB
    yOffset = yOffset - 28
    
    -- Show Proc Glow checkbox
    local voShowProcGlowCB = CreateCheckbox(content, "Show Proc Glow")
    voShowProcGlowCB:SetPoint("TOPLEFT", leftMargin, yOffset)
    voShowProcGlowCB:SetScript("OnClick", function(self)
        SetVOSettingAndApply("vo_showProcGlow", self:GetChecked())
    end)
    content.voShowProcGlowCB = voShowProcGlowCB
    yOffset = yOffset - 38
    
    -- Cooldown Text subsection header
    local voCDTextLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    voCDTextLabel:SetPoint("TOPLEFT", leftMargin, yOffset)
    voCDTextLabel:SetText("|cffaaaaaa- Cooldown Text -|r")
    yOffset = yOffset - 22
    
    -- CD Text Scale
    local voCDScaleSlider = CreateVOSlider(content, "Scale", 0.5, 2.0, 0.1, false, 1)
    voCDScaleSlider:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voCDScaleSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_cooldownTextScale", val)
    end
    content.voCDScaleSlider = voCDScaleSlider
    yOffset = yOffset - 35
    
    -- CD Text Color row
    local voCDColorLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voCDColorLabel:SetPoint("TOPLEFT", leftMargin + 10, yOffset + 4)
    voCDColorLabel:SetText("Color")
    voCDColorLabel:SetWidth(90)
    voCDColorLabel:SetJustifyH("LEFT")
    
    local voCDColorSwatch = CreateColorSwatch(content, {1, 1, 1, 1})
    voCDColorSwatch:SetPoint("LEFT", voCDColorLabel, "RIGHT", 5, 0)
    voCDColorSwatch:SetScript("OnClick", function(self)
        local settings = TUICD.Docks and TUICD.Docks:GetDockSettings(selectedDock) or {}
        local color = settings.vo_cooldownTextColor or {1, 1, 1, 1}
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color[1], g = color[2], b = color[3],
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                self.tex:SetColorTexture(r, g, b, 1)
                SetVOSettingAndApply("vo_cooldownTextColor", {r, g, b, 1})
            end,
            cancelFunc = function(prev)
                self.tex:SetColorTexture(prev.r, prev.g, prev.b, 1)
                SetVOSettingAndApply("vo_cooldownTextColor", {prev.r, prev.g, prev.b, 1})
            end,
        })
    end)
    content.voCDColorSwatch = voCDColorSwatch
    yOffset = yOffset - 30
    
    -- CD Text Anchor row
    local voCDAnchorLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voCDAnchorLabel:SetPoint("TOPLEFT", leftMargin + 10, yOffset + 4)
    voCDAnchorLabel:SetText("Anchor")
    voCDAnchorLabel:SetWidth(90)
    voCDAnchorLabel:SetJustifyH("LEFT")
    
    local voCDAnchorDropdown = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate")
    voCDAnchorDropdown:SetPoint("LEFT", voCDAnchorLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(voCDAnchorDropdown, 110)
    UIDropDownMenu_Initialize(voCDAnchorDropdown, function(self, level)
        for _, opt in ipairs(ANCHOR_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(voCDAnchorDropdown, opt.value)
                SetVOSettingAndApply("vo_cooldownTextAnchor", opt.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    content.voCDAnchorDropdown = { dropdown = voCDAnchorDropdown }
    yOffset = yOffset - 35
    
    -- CD Text Offset X
    local voCDOffsetXSlider = CreateVOSlider(content, "Offset X", -20, 20, 1, false, 0)
    voCDOffsetXSlider:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voCDOffsetXSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_cooldownTextOffsetX", val)
    end
    content.voCDOffsetXSlider = voCDOffsetXSlider
    yOffset = yOffset - 35
    
    -- CD Text Offset Y
    local voCDOffsetYSlider = CreateVOSlider(content, "Offset Y", -20, 20, 1, false, 0)
    voCDOffsetYSlider:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voCDOffsetYSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_cooldownTextOffsetY", val)
    end
    content.voCDOffsetYSlider = voCDOffsetYSlider
    yOffset = yOffset - 45
    
    -- Count Text subsection header
    local voCountTextLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    voCountTextLabel:SetPoint("TOPLEFT", leftMargin, yOffset)
    voCountTextLabel:SetText("|cffaaaaaa- Count Text -|r")
    yOffset = yOffset - 22
    
    -- Count Text Scale
    local voCountScaleSlider = CreateVOSlider(content, "Scale", 0.5, 2.0, 0.1, false, 1)
    voCountScaleSlider:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voCountScaleSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_countTextScale", val)
    end
    content.voCountScaleSlider = voCountScaleSlider
    yOffset = yOffset - 35
    
    -- Count Text Color row
    local voCountColorLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voCountColorLabel:SetPoint("TOPLEFT", leftMargin + 10, yOffset + 4)
    voCountColorLabel:SetText("Color")
    voCountColorLabel:SetWidth(90)
    voCountColorLabel:SetJustifyH("LEFT")
    
    local voCountColorSwatch = CreateColorSwatch(content, {1, 1, 1, 1})
    voCountColorSwatch:SetPoint("LEFT", voCountColorLabel, "RIGHT", 5, 0)
    voCountColorSwatch:SetScript("OnClick", function(self)
        local settings = TUICD.Docks and TUICD.Docks:GetDockSettings(selectedDock) or {}
        local color = settings.vo_countTextColor or {1, 1, 1, 1}
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color[1], g = color[2], b = color[3],
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                self.tex:SetColorTexture(r, g, b, 1)
                SetVOSettingAndApply("vo_countTextColor", {r, g, b, 1})
            end,
            cancelFunc = function(prev)
                self.tex:SetColorTexture(prev.r, prev.g, prev.b, 1)
                SetVOSettingAndApply("vo_countTextColor", {prev.r, prev.g, prev.b, 1})
            end,
        })
    end)
    content.voCountColorSwatch = voCountColorSwatch
    yOffset = yOffset - 30
    
    -- Count Text Anchor row
    local voCountAnchorLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voCountAnchorLabel:SetPoint("TOPLEFT", leftMargin + 10, yOffset + 4)
    voCountAnchorLabel:SetText("Anchor")
    voCountAnchorLabel:SetWidth(90)
    voCountAnchorLabel:SetJustifyH("LEFT")
    
    local voCountAnchorDropdown = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate")
    voCountAnchorDropdown:SetPoint("LEFT", voCountAnchorLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(voCountAnchorDropdown, 110)
    UIDropDownMenu_Initialize(voCountAnchorDropdown, function(self, level)
        for _, opt in ipairs(ANCHOR_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(voCountAnchorDropdown, opt.value)
                SetVOSettingAndApply("vo_countTextAnchor", opt.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    content.voCountAnchorDropdown = { dropdown = voCountAnchorDropdown }
    yOffset = yOffset - 35
    
    -- Count Text Offset X
    local voCountOffsetXSlider = CreateVOSlider(content, "Offset X", -20, 20, 1, false, 0)
    voCountOffsetXSlider:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voCountOffsetXSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_countTextOffsetX", val)
    end
    content.voCountOffsetXSlider = voCountOffsetXSlider
    yOffset = yOffset - 35
    
    -- Count Text Offset Y
    local voCountOffsetYSlider = CreateVOSlider(content, "Offset Y", -20, 20, 1, false, 0)
    voCountOffsetYSlider:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voCountOffsetYSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_countTextOffsetY", val)
    end
    content.voCountOffsetYSlider = voCountOffsetYSlider
    yOffset = yOffset - 45
    
    -- Custom Label subsection header
    local voLabelHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    voLabelHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
    voLabelHeader:SetText("|cffaaaaaa- Custom Label -|r")
    yOffset = yOffset - 22
    
    -- Label Enable checkbox
    local voLabelEnableCB = CreateCheckbox(content, "Enable Custom Label")
    voLabelEnableCB:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voLabelEnableCB:SetScript("OnClick", function(self)
        SetVOSettingAndApply("vo_labelEnabled", self:GetChecked())
    end)
    content.voLabelEnableCB = voLabelEnableCB
    yOffset = yOffset - 32
    
    -- Label Font Size
    local voLabelSizeSlider = CreateVOSlider(content, "Font Size", 8, 24, 1, false, 0)
    voLabelSizeSlider:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voLabelSizeSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_labelFontSize", val)
    end
    content.voLabelSizeSlider = voLabelSizeSlider
    yOffset = yOffset - 35
    
    -- Label Color row
    local voLabelColorLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voLabelColorLabel:SetPoint("TOPLEFT", leftMargin + 10, yOffset + 4)
    voLabelColorLabel:SetText("Color")
    voLabelColorLabel:SetWidth(90)
    voLabelColorLabel:SetJustifyH("LEFT")
    
    local voLabelColorSwatch = CreateColorSwatch(content, {1, 1, 1, 1})
    voLabelColorSwatch:SetPoint("LEFT", voLabelColorLabel, "RIGHT", 5, 0)
    voLabelColorSwatch:SetScript("OnClick", function(self)
        local settings = TUICD.Docks and TUICD.Docks:GetDockSettings(selectedDock) or {}
        local color = settings.vo_labelColor or {1, 1, 1, 1}
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color[1], g = color[2], b = color[3],
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                self.tex:SetColorTexture(r, g, b, 1)
                SetVOSettingAndApply("vo_labelColor", {r, g, b, 1})
            end,
            cancelFunc = function(prev)
                self.tex:SetColorTexture(prev.r, prev.g, prev.b, 1)
                SetVOSettingAndApply("vo_labelColor", {prev.r, prev.g, prev.b, 1})
            end,
        })
    end)
    content.voLabelColorSwatch = voLabelColorSwatch
    yOffset = yOffset - 30
    
    -- Label Anchor row
    local voLabelAnchorLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    voLabelAnchorLabel:SetPoint("TOPLEFT", leftMargin + 10, yOffset + 4)
    voLabelAnchorLabel:SetText("Anchor")
    voLabelAnchorLabel:SetWidth(90)
    voLabelAnchorLabel:SetJustifyH("LEFT")
    
    local voLabelAnchorDropdown = CreateFrame("Frame", nil, content, "UIDropDownMenuTemplate")
    voLabelAnchorDropdown:SetPoint("LEFT", voLabelAnchorLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(voLabelAnchorDropdown, 110)
    UIDropDownMenu_Initialize(voLabelAnchorDropdown, function(self, level)
        for _, opt in ipairs(ANCHOR_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(voLabelAnchorDropdown, opt.value)
                SetVOSettingAndApply("vo_labelAnchor", opt.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    content.voLabelAnchorDropdown = { dropdown = voLabelAnchorDropdown }
    yOffset = yOffset - 35
    
    -- Label Offset X
    local voLabelOffsetXSlider = CreateVOSlider(content, "Offset X", -20, 20, 1, false, 0)
    voLabelOffsetXSlider:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voLabelOffsetXSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_labelOffsetX", val)
    end
    content.voLabelOffsetXSlider = voLabelOffsetXSlider
    yOffset = yOffset - 35
    
    -- Label Offset Y
    local voLabelOffsetYSlider = CreateVOSlider(content, "Offset Y", -20, 20, 1, false, 0)
    voLabelOffsetYSlider:SetPoint("TOPLEFT", leftMargin + 10, yOffset)
    voLabelOffsetYSlider.onValueChanged = function(val)
        SetVOSettingAndApply("vo_labelOffsetY", val)
    end
    content.voLabelOffsetYSlider = voLabelOffsetYSlider
    yOffset = yOffset - 50
    
    -- Store all VO controls for grey-out
    content.voControls = {
        content.voApplyBtn,
        content.voIconSizeSlider, content.voOpacitySlider, content.voAspectDropdown,
        content.voShowSweepCB, content.voShowCDTextCB,
        content.voCDScaleSlider, content.voCDColorSwatch, content.voCDAnchorDropdown,
        content.voCDOffsetXSlider, content.voCDOffsetYSlider,
        content.voCountScaleSlider, content.voCountColorSwatch, content.voCountAnchorDropdown,
        content.voCountOffsetXSlider, content.voCountOffsetYSlider,
        content.voLabelEnableCB, content.voLabelSizeSlider, content.voLabelColorSwatch,
        content.voLabelAnchorDropdown, content.voLabelOffsetXSlider, content.voLabelOffsetYSlider,
    }
    
    -- ========================================================================
    -- LAYOUT SECTION
    -- ========================================================================
    local layoutHeader = CreateSectionHeader(content, "Layout")
    layoutHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
    yOffset = yOffset - 25
    
    -- Orientation dropdown
    local orientDropdown = CreateDropdown(content, "Orientation", 180)
    orientDropdown:SetPoint("TOPLEFT", leftMargin, yOffset)
    UIDropDownMenu_Initialize(orientDropdown.dropdown, function(self, level)
        local options = {
            { label = "Horizontal", value = "horizontal" },
            { label = "Vertical", value = "vertical" },
        }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(orientDropdown.dropdown, opt.value)
                if TUICD.Docks then
                    TUICD.Docks:SetDockSetting(selectedDock, "orientation", opt.value)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    content.orientDropdown = orientDropdown
    
    -- Justify dropdown
    local justifyDropdown = CreateDropdown(content, "Alignment", 180)
    justifyDropdown:SetPoint("LEFT", orientDropdown, "RIGHT", 20, 0)
    UIDropDownMenu_Initialize(justifyDropdown.dropdown, function(self, level)
        local settings = TUICD.Docks and TUICD.Docks:GetDockSettings(selectedDock) or {}
        local isHorizontal = settings.orientation == "horizontal"
        local options
        if isHorizontal then
            options = {{ label = "Left", value = "left" }, { label = "Center", value = "center" }, { label = "Right", value = "right" }}
        else
            options = {{ label = "Top", value = "top" }, { label = "Middle", value = "middle" }, { label = "Bottom", value = "bottom" }}
        end
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.checked = (settings.justify == opt.value)
            info.func = function()
                UIDropDownMenu_SetSelectedValue(justifyDropdown.dropdown, opt.value)
                if TUICD.Docks then
                    TUICD.Docks:SetDockSetting(selectedDock, "justify", opt.value)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    content.justifyDropdown = justifyDropdown
    yOffset = yOffset - 55
    
    -- Spacing slider
    local spacingSlider = CreateSlider(content, "Spacing", 0, 20, 1, 180)
    spacingSlider:SetPoint("TOPLEFT", leftMargin, yOffset)
    spacingSlider.slider:SetScript("OnValueChanged", function(self, val)
        spacingSlider.value:SetText(string.format("%.0f", val))
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "spacing", val)
        end
    end)
    content.spacingSlider = spacingSlider
    
    -- Dock Alpha slider
    local alphaSlider = CreateSlider(content, "Dock Alpha", 0, 1, 0.05, 180)
    alphaSlider:SetPoint("LEFT", spacingSlider, "RIGHT", 20, 0)
    alphaSlider.slider:SetScript("OnValueChanged", function(self, val)
        alphaSlider.value:SetText(string.format("%.0f%%", val * 100))
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "dockAlpha", val)
        end
    end)
    content.alphaSlider = alphaSlider
    yOffset = yOffset - 55
    
    -- ========================================================================
    -- APPEARANCE SECTION
    -- ========================================================================
    local appearHeader = CreateSectionHeader(content, "Appearance")
    appearHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
    yOffset = yOffset - 25
    
    -- Background row
    local bgRow = CreateFrame("Frame", nil, content)
    bgRow:SetPoint("TOPLEFT", leftMargin, yOffset)
    bgRow:SetSize(380, 25)
    
    local showBgCB = CreateCheckbox(bgRow, "Show Background")
    showBgCB:SetPoint("LEFT", 0, 0)
    showBgCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showBackground", self:GetChecked())
        end
    end)
    content.showBgCB = showBgCB
    
    local bgColorLabel = bgRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bgColorLabel:SetPoint("LEFT", showBgCB, "RIGHT", 100, 0)
    bgColorLabel:SetText("Color:")
    
    local bgColorSwatch = CreateColorSwatch(bgRow, {0.05, 0.05, 0.05, 0.5})
    bgColorSwatch:SetPoint("LEFT", bgColorLabel, "RIGHT", 5, 0)
    bgColorSwatch:SetScript("OnClick", function(self)
        local settings = TUICD.Docks and TUICD.Docks:GetDockSettings(selectedDock) or {}
        local color = settings.bgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.5 }
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color.r, g = color.g, b = color.b, opacity = color.a,
            hasOpacity = true,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                self.tex:SetColorTexture(r, g, b, 1)
                if TUICD.Docks then
                    TUICD.Docks:SetDockSetting(selectedDock, "bgColor", { r = r, g = g, b = b, a = a })
                end
            end,
            cancelFunc = function(prev)
                self.tex:SetColorTexture(prev.r, prev.g, prev.b, 1)
                if TUICD.Docks then
                    TUICD.Docks:SetDockSetting(selectedDock, "bgColor", { r = prev.r, g = prev.g, b = prev.b, a = 1 - prev.opacity })
                end
            end,
        })
    end)
    content.bgColorSwatch = bgColorSwatch
    yOffset = yOffset - 30
    
    -- Border row
    local borderRow = CreateFrame("Frame", nil, content)
    borderRow:SetPoint("TOPLEFT", leftMargin, yOffset)
    borderRow:SetSize(380, 25)
    
    local showBorderCB = CreateCheckbox(borderRow, "Show Border")
    showBorderCB:SetPoint("LEFT", 0, 0)
    showBorderCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showBorder", self:GetChecked())
        end
    end)
    content.showBorderCB = showBorderCB
    
    local borderColorLabel = borderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    borderColorLabel:SetPoint("LEFT", showBorderCB, "RIGHT", 100, 0)
    borderColorLabel:SetText("Color:")
    
    local borderColorSwatch = CreateColorSwatch(borderRow, {0.3, 0.3, 0.3, 0.8})
    borderColorSwatch:SetPoint("LEFT", borderColorLabel, "RIGHT", 5, 0)
    borderColorSwatch:SetScript("OnClick", function(self)
        local settings = TUICD.Docks and TUICD.Docks:GetDockSettings(selectedDock) or {}
        local color = settings.borderColor or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color.r, g = color.g, b = color.b, opacity = color.a,
            hasOpacity = true,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                self.tex:SetColorTexture(r, g, b, 1)
                if TUICD.Docks then
                    TUICD.Docks:SetDockSetting(selectedDock, "borderColor", { r = r, g = g, b = b, a = a })
                end
            end,
            cancelFunc = function(prev)
                self.tex:SetColorTexture(prev.r, prev.g, prev.b, 1)
                if TUICD.Docks then
                    TUICD.Docks:SetDockSetting(selectedDock, "borderColor", { r = prev.r, g = prev.g, b = prev.b, a = 1 - prev.opacity })
                end
            end,
        })
    end)
    content.borderColorSwatch = borderColorSwatch
    yOffset = yOffset - 35
    
    -- ========================================================================
    -- VISIBILITY SECTION
    -- ========================================================================
    local visHeader = CreateSectionHeader(content, "Visibility")
    visHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
    yOffset = yOffset - 25
    
    local visEnabledCB = CreateCheckbox(content, "Enable Visibility Rules")
    visEnabledCB:SetPoint("TOPLEFT", leftMargin, yOffset)
    visEnabledCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "visibilityEnabled", self:GetChecked())
        end
    end)
    content.visEnabledCB = visEnabledCB
    yOffset = yOffset - 30
    
    -- Combat visibility
    local combatRow = CreateFrame("Frame", nil, content)
    combatRow:SetPoint("TOPLEFT", leftMargin, yOffset)
    combatRow:SetSize(380, 25)
    
    local showInCombatCB = CreateCheckbox(combatRow, "In Combat")
    showInCombatCB:SetPoint("LEFT", 0, 0)
    showInCombatCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showInCombat", self:GetChecked())
        end
    end)
    content.showInCombatCB = showInCombatCB
    
    local showOutOfCombatCB = CreateCheckbox(combatRow, "Out of Combat")
    showOutOfCombatCB:SetPoint("LEFT", showInCombatCB, "RIGHT", 100, 0)
    showOutOfCombatCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showOutOfCombat", self:GetChecked())
        end
    end)
    content.showOutOfCombatCB = showOutOfCombatCB
    yOffset = yOffset - 30
    
    -- Group visibility
    local groupRow = CreateFrame("Frame", nil, content)
    groupRow:SetPoint("TOPLEFT", leftMargin, yOffset)
    groupRow:SetSize(380, 25)
    
    local showSoloCB = CreateCheckbox(groupRow, "Solo")
    showSoloCB:SetPoint("LEFT", 0, 0)
    showSoloCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showSolo", self:GetChecked())
        end
    end)
    content.showSoloCB = showSoloCB
    
    local showInPartyCB = CreateCheckbox(groupRow, "Party")
    showInPartyCB:SetPoint("LEFT", showSoloCB, "RIGHT", 60, 0)
    showInPartyCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showInParty", self:GetChecked())
        end
    end)
    content.showInPartyCB = showInPartyCB
    
    local showInRaidCB = CreateCheckbox(groupRow, "Raid")
    showInRaidCB:SetPoint("LEFT", showInPartyCB, "RIGHT", 60, 0)
    showInRaidCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showInRaid", self:GetChecked())
        end
    end)
    content.showInRaidCB = showInRaidCB
    yOffset = yOffset - 30
    
    -- Target visibility
    local targetRow = CreateFrame("Frame", nil, content)
    targetRow:SetPoint("TOPLEFT", leftMargin, yOffset)
    targetRow:SetSize(380, 25)
    
    local showHasTargetCB = CreateCheckbox(targetRow, "Has Target")
    showHasTargetCB:SetPoint("LEFT", 0, 0)
    showHasTargetCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showHasTarget", self:GetChecked())
        end
    end)
    content.showHasTargetCB = showHasTargetCB
    
    local showNoTargetCB = CreateCheckbox(targetRow, "No Target")
    showNoTargetCB:SetPoint("LEFT", showHasTargetCB, "RIGHT", 70, 0)
    showNoTargetCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showNoTarget", self:GetChecked())
        end
    end)
    content.showNoTargetCB = showNoTargetCB
    yOffset = yOffset - 30
    
    -- Mounted visibility
    local mountedRow = CreateFrame("Frame", nil, content)
    mountedRow:SetPoint("TOPLEFT", leftMargin, yOffset)
    mountedRow:SetSize(380, 25)
    
    local showMountedCB = CreateCheckbox(mountedRow, "Mounted")
    showMountedCB:SetPoint("LEFT", 0, 0)
    showMountedCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showMounted", self:GetChecked())
        end
    end)
    content.showMountedCB = showMountedCB
    
    local showNotMountedCB = CreateCheckbox(mountedRow, "Not Mounted")
    showNotMountedCB:SetPoint("LEFT", showMountedCB, "RIGHT", 70, 0)
    showNotMountedCB:SetScript("OnClick", function(self)
        if TUICD.Docks then
            TUICD.Docks:SetDockSetting(selectedDock, "showNotMounted", self:GetChecked())
        end
    end)
    content.showNotMountedCB = showNotMountedCB
    yOffset = yOffset - 35
    
    -- Info text
    local infoText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", leftMargin, yOffset)
    infoText:SetWidth(380)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("|cff888888Assign icons to this dock via Individual Icons settings in each tracker.|r")
    
    return content
end

-- ============================================================================
-- PANEL CREATION
-- ============================================================================

local function CreatePanel()
    if panel then return panel end
    
    local frame = CreateFrame("Frame", "TweaksUI_DocksPanel", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:SetBackdrop(BACKDROP_DARK)
    frame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    
    -- Position next to Cooldowns hub (not main TUICD hub)
    if _G["TweaksUI_Cooldowns_Hub"] then
        frame:SetPoint("TOPLEFT", _G["TweaksUI_Cooldowns_Hub"], "TOPRIGHT", 0, 0)
    elseif _G["TweaksUI_HubPanel"] then
        frame:SetPoint("TOPLEFT", _G["TweaksUI_HubPanel"], "TOPRIGHT", 0, 0)
    else
        frame:SetPoint("CENTER", 100, 0)
    end
    
    -- Title (gold, matching other panels)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Dynamic Docks")
    title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- Dock tabs (1-4)
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetPoint("TOPLEFT", 15, -40)
    tabBar:SetPoint("TOPRIGHT", -15, -40)
    tabBar:SetHeight(30)
    
    local tabWidth = 80
    for i = 1, 4 do
        local tab = CreateFrame("Button", nil, tabBar)
        tab:SetSize(tabWidth, 25)
        tab:SetPoint("LEFT", (i - 1) * (tabWidth + 5), 0)
        
        local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText("Dock " .. i)
        tab:SetFontString(text)
        
        tab.dockIndex = i
        tab:SetScript("OnClick", function()
            SelectDockTab(i)
        end)
        
        -- Highlight on hover
        tab:SetScript("OnEnter", function(self)
            if selectedDock ~= i then
                text:SetTextColor(0.8, 0.8, 0.8)
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if selectedDock ~= i then
                text:SetTextColor(0.6, 0.6, 0.6)
            end
        end)
        
        dockTabs[i] = tab
    end
    
    -- Content area
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", 15, -75)
    contentArea:SetPoint("BOTTOMRIGHT", -15, 15)
    contentFrame = CreateDockContent(contentArea)
    
    -- Close button behavior
    frame:SetScript("OnHide", function()
        -- Nothing special needed
    end)
    
    panel = frame
    
    -- Initialize first tab
    SelectDockTab(1)
    
    return frame
end

-- ============================================================================
-- REFRESH CONTENT
-- ============================================================================

function DocksUI:RefreshContent()
    if not contentFrame then return end
    if not TUICD.Docks then return end
    
    local settings = TUICD.Docks:GetDockSettings(selectedDock)
    if not settings then return end
    
    -- Enable checkbox
    if contentFrame.enableCB then
        contentFrame.enableCB:SetChecked(settings.enabled)
    end
    
    -- Name edit
    if contentFrame.nameEdit then
        contentFrame.nameEdit:SetText(settings.name or "")
    end
    
    -- ========================================================================
    -- VISUAL OVERRIDE SECTION
    -- ========================================================================
    local voEnabled = settings.visualOverrideEnabled
    
    if contentFrame.voEnableCB then
        contentFrame.voEnableCB:SetChecked(voEnabled)
    end
    
    -- Grey out VO controls when disabled
    if contentFrame.voControls then
        SetControlsGreyedOut(contentFrame.voControls, not voEnabled)
    end
    
    -- Icon Size
    if contentFrame.voIconSizeSlider then
        contentFrame.voIconSizeSlider.slider:SetValue(settings.vo_iconSize or 36)
    end
    
    -- Opacity
    if contentFrame.voOpacitySlider then
        contentFrame.voOpacitySlider.slider:SetValue(settings.vo_opacity or 1.0)
    end
    
    -- Aspect Ratio
    if contentFrame.voAspectDropdown then
        local aspect = settings.vo_aspectRatio or "1:1"
        UIDropDownMenu_SetSelectedValue(contentFrame.voAspectDropdown.dropdown, aspect)
        for _, opt in ipairs(ASPECT_OPTIONS) do
            if opt.value == aspect then
                UIDropDownMenu_SetText(contentFrame.voAspectDropdown.dropdown, opt.label)
                break
            end
        end
    end
    
    -- Sweep and Countdown
    if contentFrame.voShowSweepCB then
        contentFrame.voShowSweepCB:SetChecked(settings.vo_showSweep ~= false)
    end
    if contentFrame.voShowCDTextCB then
        contentFrame.voShowCDTextCB:SetChecked(settings.vo_showCountdownText ~= false)
    end
    if contentFrame.voShowProcGlowCB then
        contentFrame.voShowProcGlowCB:SetChecked(settings.vo_showProcGlow ~= false)
    end
    
    -- Cooldown Text settings
    if contentFrame.voCDScaleSlider then
        contentFrame.voCDScaleSlider.slider:SetValue(settings.vo_cooldownTextScale or 1.0)
    end
    if contentFrame.voCDColorSwatch then
        local c = settings.vo_cooldownTextColor or {1, 1, 1, 1}
        contentFrame.voCDColorSwatch.tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
    end
    if contentFrame.voCDAnchorDropdown then
        local anchor = settings.vo_cooldownTextAnchor or "CENTER"
        UIDropDownMenu_SetSelectedValue(contentFrame.voCDAnchorDropdown.dropdown, anchor)
        for _, opt in ipairs(ANCHOR_OPTIONS) do
            if opt.value == anchor then
                UIDropDownMenu_SetText(contentFrame.voCDAnchorDropdown.dropdown, opt.label)
                break
            end
        end
    end
    if contentFrame.voCDOffsetXSlider then
        contentFrame.voCDOffsetXSlider.slider:SetValue(settings.vo_cooldownTextOffsetX or 0)
    end
    if contentFrame.voCDOffsetYSlider then
        contentFrame.voCDOffsetYSlider.slider:SetValue(settings.vo_cooldownTextOffsetY or 0)
    end
    
    -- Count Text settings
    if contentFrame.voCountScaleSlider then
        contentFrame.voCountScaleSlider.slider:SetValue(settings.vo_countTextScale or 1.0)
    end
    if contentFrame.voCountColorSwatch then
        local c = settings.vo_countTextColor or {1, 1, 1, 1}
        contentFrame.voCountColorSwatch.tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
    end
    if contentFrame.voCountAnchorDropdown then
        local anchor = settings.vo_countTextAnchor or "BOTTOMRIGHT"
        UIDropDownMenu_SetSelectedValue(contentFrame.voCountAnchorDropdown.dropdown, anchor)
        for _, opt in ipairs(ANCHOR_OPTIONS) do
            if opt.value == anchor then
                UIDropDownMenu_SetText(contentFrame.voCountAnchorDropdown.dropdown, opt.label)
                break
            end
        end
    end
    if contentFrame.voCountOffsetXSlider then
        contentFrame.voCountOffsetXSlider.slider:SetValue(settings.vo_countTextOffsetX or 0)
    end
    if contentFrame.voCountOffsetYSlider then
        contentFrame.voCountOffsetYSlider.slider:SetValue(settings.vo_countTextOffsetY or -2)
    end
    
    -- Label settings
    if contentFrame.voLabelEnableCB then
        contentFrame.voLabelEnableCB:SetChecked(settings.vo_labelEnabled)
    end
    if contentFrame.voLabelSizeSlider then
        contentFrame.voLabelSizeSlider.slider:SetValue(settings.vo_labelFontSize or 14)
    end
    if contentFrame.voLabelColorSwatch then
        local c = settings.vo_labelColor or {1, 1, 1, 1}
        contentFrame.voLabelColorSwatch.tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
    end
    if contentFrame.voLabelAnchorDropdown then
        local anchor = settings.vo_labelAnchor or "CENTER"
        UIDropDownMenu_SetSelectedValue(contentFrame.voLabelAnchorDropdown.dropdown, anchor)
        for _, opt in ipairs(ANCHOR_OPTIONS) do
            if opt.value == anchor then
                UIDropDownMenu_SetText(contentFrame.voLabelAnchorDropdown.dropdown, opt.label)
                break
            end
        end
    end
    if contentFrame.voLabelOffsetXSlider then
        contentFrame.voLabelOffsetXSlider.slider:SetValue(settings.vo_labelOffsetX or 0)
    end
    if contentFrame.voLabelOffsetYSlider then
        contentFrame.voLabelOffsetYSlider.slider:SetValue(settings.vo_labelOffsetY or 0)
    end
    
    -- ========================================================================
    -- LAYOUT SECTION
    -- ========================================================================
    
    -- Orientation dropdown
    if contentFrame.orientDropdown then
        local orientLabel = settings.orientation == "vertical" and "Vertical" or "Horizontal"
        UIDropDownMenu_SetSelectedValue(contentFrame.orientDropdown.dropdown, settings.orientation or "horizontal")
        UIDropDownMenu_SetText(contentFrame.orientDropdown.dropdown, orientLabel)
    end
    
    -- Justify dropdown (reinitialize to get correct options based on orientation)
    if contentFrame.justifyDropdown then
        UIDropDownMenu_Initialize(contentFrame.justifyDropdown.dropdown, function(self, level)
            local isHorizontal = settings.orientation == "horizontal"
            local options
            if isHorizontal then
                options = {{ label = "Left", value = "left" }, { label = "Center", value = "center" }, { label = "Right", value = "right" }}
            else
                options = {{ label = "Top", value = "top" }, { label = "Middle", value = "middle" }, { label = "Bottom", value = "bottom" }}
            end
            for _, opt in ipairs(options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.checked = (settings.justify == opt.value)
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(contentFrame.justifyDropdown.dropdown, opt.value)
                    if TUICD.Docks then
                        TUICD.Docks:SetDockSetting(selectedDock, "justify", opt.value)
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        local justifyLabels = { left = "Left", center = "Center", right = "Right", top = "Top", middle = "Middle", bottom = "Bottom" }
        UIDropDownMenu_SetText(contentFrame.justifyDropdown.dropdown, justifyLabels[settings.justify] or "Center")
    end
    
    -- Spacing slider
    if contentFrame.spacingSlider then
        contentFrame.spacingSlider.slider:SetValue(settings.spacing or 4)
    end
    
    -- Dock Alpha slider
    if contentFrame.alphaSlider then
        contentFrame.alphaSlider.slider:SetValue(settings.dockAlpha or 1.0)
    end
    
    -- Background settings
    if contentFrame.showBgCB then
        contentFrame.showBgCB:SetChecked(settings.showBackground ~= false)
    end
    if contentFrame.bgColorSwatch then
        local bgColor = settings.bgColor or { r = 0.05, g = 0.05, b = 0.05, a = 0.5 }
        contentFrame.bgColorSwatch.tex:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, 1)
    end
    
    -- Border settings
    if contentFrame.showBorderCB then
        contentFrame.showBorderCB:SetChecked(settings.showBorder ~= false)
    end
    if contentFrame.borderColorSwatch then
        local borderColor = settings.borderColor or { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
        contentFrame.borderColorSwatch.tex:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
    end
    
    -- Visibility checkboxes
    if contentFrame.visEnabledCB then
        contentFrame.visEnabledCB:SetChecked(settings.visibilityEnabled)
    end
    if contentFrame.showInCombatCB then
        contentFrame.showInCombatCB:SetChecked(settings.showInCombat ~= false)
    end
    if contentFrame.showOutOfCombatCB then
        contentFrame.showOutOfCombatCB:SetChecked(settings.showOutOfCombat ~= false)
    end
    if contentFrame.showSoloCB then
        contentFrame.showSoloCB:SetChecked(settings.showSolo ~= false)
    end
    if contentFrame.showInPartyCB then
        contentFrame.showInPartyCB:SetChecked(settings.showInParty ~= false)
    end
    if contentFrame.showInRaidCB then
        contentFrame.showInRaidCB:SetChecked(settings.showInRaid ~= false)
    end
    if contentFrame.showHasTargetCB then
        contentFrame.showHasTargetCB:SetChecked(settings.showHasTarget ~= false)
    end
    if contentFrame.showNoTargetCB then
        contentFrame.showNoTargetCB:SetChecked(settings.showNoTarget ~= false)
    end
    if contentFrame.showMountedCB then
        contentFrame.showMountedCB:SetChecked(settings.showMounted ~= false)
    end
    if contentFrame.showNotMountedCB then
        contentFrame.showNotMountedCB:SetChecked(settings.showNotMounted ~= false)
    end
    if contentFrame.earlyShowSlider then
        local val = settings.earlyShowSeconds or 0
        contentFrame.earlyShowSlider.slider:SetValue(math.min(val, 120))
        contentFrame.earlyShowSlider.editBox:SetText(val == 0 and "Off" or tostring(val))
    end
    
    -- ========================================================================
    -- REAPPEARANCE EFFECTS
    -- ========================================================================
    local TRIGGER_OPTIONS = {
        { label = "On Early Show", value = "onEarlyShow" },
        { label = "On Ready",      value = "onReady" },
        { label = "Both",          value = "both" },
    }
    local FLASH_TYPE_OPTIONS = {
        { label = "Pixel Border",  value = "pixel" },
        { label = "Shine Flash",   value = "shine" },
        { label = "Spell Glow",    value = "glow" },
    }
    
    local flashEnabled = settings.flashEnabled
    local pulseEnabled = settings.pulseEnabled
    
    -- Flash enable
    if contentFrame.flashEnableCB then
        contentFrame.flashEnableCB:SetChecked(flashEnabled)
    end
    
    -- Flash sub-controls enable/disable
    local flashSubControls = {
        contentFrame.flashTriggerLabel, contentFrame.flashTriggerDropdown,
        contentFrame.flashTypeLabel, contentFrame.flashTypeDropdown,
        contentFrame.flashColorLabel, contentFrame.flashColorSwatch,
        contentFrame.flashThicknessSlider, contentFrame.flashScaleSlider,
        contentFrame.flashSpeedSlider, contentFrame.flashIntensitySlider,
        contentFrame.flashDurSlider, contentFrame.flashHint,
    }
    for _, ctrl in ipairs(flashSubControls) do
        if ctrl then
            if ctrl.SetAlpha then ctrl:SetAlpha(flashEnabled and 1 or 0.4) end
            if ctrl.EnableMouse then ctrl:EnableMouse(flashEnabled) end
            if ctrl.slider then ctrl.slider:EnableMouse(flashEnabled) end
            if ctrl.editBox then ctrl.editBox:EnableMouse(flashEnabled) end
        end
    end
    
    -- Flash trigger dropdown
    if contentFrame.flashTriggerDropdown then
        local currentTrigger = settings.flashTrigger or "onReady"
        UIDropDownMenu_Initialize(contentFrame.flashTriggerDropdown, function(self, level)
            for _, opt in ipairs(TRIGGER_OPTIONS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.checked = (currentTrigger == opt.value)
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(contentFrame.flashTriggerDropdown, opt.value)
                    UIDropDownMenu_SetText(contentFrame.flashTriggerDropdown, opt.label)
                    if TUICD.Docks then
                        TUICD.Docks:SetDockSetting(selectedDock, "flashTrigger", opt.value)
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        for _, opt in ipairs(TRIGGER_OPTIONS) do
            if opt.value == currentTrigger then
                UIDropDownMenu_SetText(contentFrame.flashTriggerDropdown, opt.label)
                break
            end
        end
    end
    
    -- Flash type dropdown
    if contentFrame.flashTypeDropdown then
        local currentType = settings.flashType or "pixel"
        UIDropDownMenu_Initialize(contentFrame.flashTypeDropdown, function(self, level)
            for _, opt in ipairs(FLASH_TYPE_OPTIONS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.checked = (currentType == opt.value)
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(contentFrame.flashTypeDropdown, opt.value)
                    UIDropDownMenu_SetText(contentFrame.flashTypeDropdown, opt.label)
                    if TUICD.Docks then
                        TUICD.Docks:SetDockSetting(selectedDock, "flashType", opt.value)
                    end
                    DocksUI:RefreshContent()  -- Toggle style-specific controls
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        for _, opt in ipairs(FLASH_TYPE_OPTIONS) do
            if opt.value == currentType then
                UIDropDownMenu_SetText(contentFrame.flashTypeDropdown, opt.label)
                break
            end
        end
        -- Show/hide style-specific controls
        local isPixel = (currentType == "pixel")
        local isGlow = (currentType == "glow")
        if contentFrame.flashThicknessSlider then
            contentFrame.flashThicknessSlider:SetShown(flashEnabled and isPixel)
        end
        if contentFrame.flashScaleSlider then
            contentFrame.flashScaleSlider:SetShown(flashEnabled and isGlow)
        end
    end
    
    -- Flash color swatch
    if contentFrame.flashColorSwatch then
        local c = settings.flashColor or { r = 1, g = 0.82, b = 0, a = 1 }
        contentFrame.flashColorSwatch.tex:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, 1)
    end
    
    -- Flash sliders
    if contentFrame.flashThicknessSlider then
        contentFrame.flashThicknessSlider:SetValue(settings.flashThickness or 2)
    end
    if contentFrame.flashScaleSlider then
        contentFrame.flashScaleSlider:SetValue(settings.flashScale or 1.0)
    end
    if contentFrame.flashSpeedSlider then
        contentFrame.flashSpeedSlider:SetValue(settings.flashSpeed or 0.6)
    end
    if contentFrame.flashIntensitySlider then
        contentFrame.flashIntensitySlider:SetValue(settings.flashIntensity or 0.8)
    end
    if contentFrame.flashDurSlider then
        contentFrame.flashDurSlider:SetValue(settings.flashDuration or 0.6)
    end
    
    -- Pulse enable
    if contentFrame.pulseEnableCB then
        contentFrame.pulseEnableCB:SetChecked(pulseEnabled)
    end
    
    -- Pulse sub-controls enable/disable
    local pulseSubControls = {
        contentFrame.pulseTriggerLabel, contentFrame.pulseTriggerDropdown,
        contentFrame.pulseScaleSlider, contentFrame.pulseDurSlider,
        contentFrame.pulseCountSlider,
    }
    for _, ctrl in ipairs(pulseSubControls) do
        if ctrl then
            if ctrl.SetAlpha then ctrl:SetAlpha(pulseEnabled and 1 or 0.4) end
            if ctrl.EnableMouse then ctrl:EnableMouse(pulseEnabled) end
            if ctrl.slider then ctrl.slider:EnableMouse(pulseEnabled) end
            if ctrl.editBox then ctrl.editBox:EnableMouse(pulseEnabled) end
        end
    end
    
    -- Pulse trigger dropdown
    if contentFrame.pulseTriggerDropdown then
        local currentTrigger = settings.pulseTrigger or "onReady"
        UIDropDownMenu_Initialize(contentFrame.pulseTriggerDropdown, function(self, level)
            for _, opt in ipairs(TRIGGER_OPTIONS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.checked = (currentTrigger == opt.value)
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(contentFrame.pulseTriggerDropdown, opt.value)
                    UIDropDownMenu_SetText(contentFrame.pulseTriggerDropdown, opt.label)
                    if TUICD.Docks then
                        TUICD.Docks:SetDockSetting(selectedDock, "pulseTrigger", opt.value)
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        for _, opt in ipairs(TRIGGER_OPTIONS) do
            if opt.value == currentTrigger then
                UIDropDownMenu_SetText(contentFrame.pulseTriggerDropdown, opt.label)
                break
            end
        end
    end
    
    -- Pulse scale
    if contentFrame.pulseScaleSlider then
        contentFrame.pulseScaleSlider:SetValue(settings.pulseScale or 1.3)
    end
    
    -- Pulse duration
    if contentFrame.pulseDurSlider then
        contentFrame.pulseDurSlider:SetValue(settings.pulseDuration or 0.4)
    end
    
    -- Pulse count
    if contentFrame.pulseCountSlider then
        contentFrame.pulseCountSlider:SetValue(settings.pulseCount or 3)
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function DocksUI:Toggle()
    if not panel then
        CreatePanel()
    end
    
    if panel:IsShown() then
        panel:Hide()
    else
        -- Close ALL other Cooldowns module panels first
        if TUICD.Cooldowns and TUICD.Cooldowns.HideTrackerPanels then
            TUICD.Cooldowns:HideTrackerPanels()
        end
        
        -- Hide profiles panel if it exists
        if _G["TweaksUI_ProfilesPanel"] and _G["TweaksUI_ProfilesPanel"]:IsShown() then
            _G["TweaksUI_ProfilesPanel"]:Hide()
        end
        
        -- Position next to Cooldowns hub
        if _G["TweaksUI_Cooldowns_Hub"] and _G["TweaksUI_Cooldowns_Hub"]:IsShown() then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", _G["TweaksUI_Cooldowns_Hub"], "TOPRIGHT", 0, 0)
        elseif _G["TweaksUI_HubPanel"] and _G["TweaksUI_HubPanel"]:IsShown() then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", _G["TweaksUI_HubPanel"], "TOPRIGHT", 0, 0)
        end
        
        self:RefreshContent()
        panel:Show()
    end
end

function DocksUI:Show()
    -- Close other module panels when opening Docks
    if TUICD.Cooldowns and TUICD.Cooldowns.HideTrackerPanels then
        TUICD.Cooldowns:HideTrackerPanels()
    end
    if TUICD.PersonalResources and TUICD.PersonalResources.HideAllPanels then
        TUICD.PersonalResources:HideAllPanels()
    end
    if TUICD.MultiTrackerUI and TUICD.MultiTrackerUI.HideAllPanels then
        TUICD.MultiTrackerUI:HideAllPanels()
    end
    if TUICD.BuffBarsUI and TUICD.BuffBarsUI:IsShown() then
        TUICD.BuffBarsUI:Hide()
    end
    
    if not panel then
        CreatePanel()
    end
    
    -- Position next to Cooldowns hub
    if _G["TweaksUI_Cooldowns_Hub"] and _G["TweaksUI_Cooldowns_Hub"]:IsShown() then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", _G["TweaksUI_Cooldowns_Hub"], "TOPRIGHT", 0, 0)
    end
    
    self:RefreshContent()
    panel:Show()
end

function DocksUI:Hide()
    if panel then
        panel:Hide()
    end
end

function DocksUI:IsShown()
    return panel and panel:IsShown()
end

function DocksUI:Initialize()
    initialized = true
    if TUICD.PrintDebug then
        TUICD:PrintDebug("DocksUI initialized")
    end
end
