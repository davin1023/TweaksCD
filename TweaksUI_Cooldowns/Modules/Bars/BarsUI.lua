-- ============================================================================
-- TUICD: Timer Bars - Settings UI
-- Spell list + per-spell bar configuration panel
-- Pattern: list on left, config on right (like Per-Icon Highlights)
-- Uses compound barKeys for selection (e.g. "258920:cd")
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BarsUI = TUICD.BarsUI or {}
local BarsUI = TUICD.BarsUI

local BarsData = TUICD.BarsData
local BarsFrames = TUICD.BarsFrames
local SpellAPI = TUICD.SpellAPI
local Media = TUICD.Media

-- ============================================================================
-- STATE
-- ============================================================================

local mainPanel = nil
local selectedBarKey = nil  -- Compound key e.g. "258920:cd"
local spellButtons = {}
local configFrame = nil

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH = 520
local PANEL_HEIGHT = 600
local LIST_WIDTH = 170
local CONFIG_WIDTH = 330
local BUTTON_HEIGHT = 28
local BUTTON_SPACING = 2
local SECTION_SPACING = 12

-- ============================================================================
-- HELPERS
-- ============================================================================

local function CreateSectionLabel(parent, text, anchor, xOff, yOff)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOff or 0, yOff or -SECTION_SPACING)
    label:SetText("|cffaaaaaa\226\128\148 " .. text .. " \226\128\148|r")
    return label
end

local function CreateSlider(parent, label, min, max, step, width, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or 280, 36)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -14)
    slider:SetWidth(width - 60)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText("")
    slider.High:SetText("")

    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)

    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        valueText:SetText(tostring(val))
        if onChange then onChange(val) end
    end)

    container.slider = slider
    container.valueText = valueText
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

local function CreateColorSwatch(parent, color, onChange)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(20, 20)

    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.5, 0.5, 0.5, 1)

    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(color.r, color.g, color.b, 1)
    swatch.tex = tex

    swatch:SetScript("OnClick", function(self)
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color.r, g = color.g, b = color.b,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                color.r, color.g, color.b = r, g, b
                self.tex:SetColorTexture(r, g, b, 1)
                if onChange then onChange(r, g, b) end
            end,
            cancelFunc = function(prev)
                color.r, color.g, color.b = prev.r, prev.g, prev.b
                self.tex:SetColorTexture(prev.r, prev.g, prev.b, 1)
                if onChange then onChange(prev.r, prev.g, prev.b) end
            end,
        })
    end)

    return swatch
end

-- ============================================================================
-- SPELL LIST (left side)
-- ============================================================================

local scrollFrame, scrollChild

local function RefreshSpellList()
    if not scrollChild then return end

    for _, btn in ipairs(spellButtons) do btn:Hide() end
    wipe(spellButtons)

    local spellList = BarsData:GetSpellList()
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
        icon:SetTexture(entry.iconID or 134400)

        -- Display name with type tag: "Immolation Aura (CD)"
        local name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        name:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        name:SetJustifyH("LEFT")
        name:SetText(entry.displayName)
        name:SetWordWrap(false)

        if not entry.enabled then
            name:SetTextColor(0.5, 0.5, 0.5)
            icon:SetDesaturated(true)
        end

        btn:SetScript("OnClick", function()
            selectedBarKey = entry.barKey
            RefreshSpellList()
            BarsUI:RefreshConfigPanel()
        end)

        table.insert(spellButtons, btn)
        yOffset = yOffset + BUTTON_HEIGHT + BUTTON_SPACING
    end

    scrollChild:SetHeight(math.max(1, yOffset))
end

-- ============================================================================
-- CONFIG PANEL (right side)
-- ============================================================================

function BarsUI:RefreshConfigPanel()
    if not configFrame then return end

    for _, child in ipairs({configFrame:GetChildren()}) do child:Hide() end

    if not selectedBarKey then
        local hint = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hint:SetPoint("CENTER")
        hint:SetText("|cff888888Select a spell to configure|r")
        hint:Show()
        return
    end

    local config = BarsData:GetSpellConfig(selectedBarKey)
    if not config then return end

    local spellID = BarsData.ParseBarKey(selectedBarKey)
    local yOffset = 0

    -- ========================================
    -- Header: Spell name + icon + type
    -- ========================================
    local header = CreateFrame("Frame", nil, configFrame)
    header:SetSize(CONFIG_WIDTH - 20, 30)
    header:SetPoint("TOPLEFT", 0, -yOffset)
    header:Show()

    local hIcon = header:CreateTexture(nil, "ARTWORK")
    hIcon:SetSize(24, 24)
    hIcon:SetPoint("LEFT", 0, 0)
    hIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    hIcon:SetTexture(config.iconID or (spellID and SpellAPI:GetSpellTexture(spellID)) or 134400)

    local hName = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hName:SetPoint("LEFT", hIcon, "RIGHT", 8, 0)
    hName:SetText(config.name or ("Spell " .. (spellID or "?")))
    hName:SetTextColor(1, 0.82, 0)

    local hType = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hType:SetPoint("LEFT", hName, "RIGHT", 8, 0)
    local typeColor = "|cff888888"
    hType:SetText(typeColor .. BarsData.TypeLabel(config.type) .. "|r")

    yOffset = yOffset + 35

    -- ========================================
    -- Enable toggle
    -- ========================================
    local enableCheck = CreateCheckbox(configFrame, "Enabled", function(checked)
        BarsData:SetSpellSetting(selectedBarKey, "enabled", checked)
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    enableCheck:SetPoint("TOPLEFT", 0, -yOffset)
    enableCheck:SetChecked(config.enabled ~= false)
    enableCheck:Show()
    yOffset = yOffset + 28

    -- ========================================
    -- Section: Dimensions
    -- ========================================
    local dimLabel = CreateSectionLabel(configFrame, "Dimensions", configFrame, 0, -yOffset)
    dimLabel:ClearAllPoints()
    dimLabel:SetPoint("TOPLEFT", 0, -yOffset)
    yOffset = yOffset + 18

    local widthSlider = CreateSlider(configFrame, "Width", 80, 400, 5, CONFIG_WIDTH - 20, function(val)
        BarsData:SetSpellSetting(selectedBarKey, "width", val)
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    widthSlider:SetPoint("TOPLEFT", 0, -yOffset)
    widthSlider.slider:SetValue(config.width or 200)
    widthSlider:Show()
    yOffset = yOffset + 38

    local heightSlider = CreateSlider(configFrame, "Height", 10, 40, 1, CONFIG_WIDTH - 20, function(val)
        BarsData:SetSpellSetting(selectedBarKey, "height", val)
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    heightSlider:SetPoint("TOPLEFT", 0, -yOffset)
    heightSlider.slider:SetValue(config.height or 20)
    heightSlider:Show()
    yOffset = yOffset + 38

    -- ========================================
    -- Section: Appearance
    -- ========================================
    local appLabel = CreateSectionLabel(configFrame, "Appearance", configFrame, 0, -yOffset)
    appLabel:ClearAllPoints()
    appLabel:SetPoint("TOPLEFT", 0, -yOffset)
    yOffset = yOffset + 18

    local colorLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colorLabel:SetPoint("TOPLEFT", 0, -yOffset)
    colorLabel:SetText("Bar Color")
    colorLabel:Show()

    local barColor = config.barColor or { r = 0.26, g = 0.65, b = 1.0, a = 1.0 }
    local colorSwatch = CreateColorSwatch(configFrame, barColor, function(r, g, b)
        BarsData:SetSpellSetting(selectedBarKey, "barColor", { r = r, g = g, b = b, a = 1.0 })
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    colorSwatch:SetPoint("LEFT", colorLabel, "RIGHT", 8, 0)
    colorSwatch:Show()
    yOffset = yOffset + 24

    local bgLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bgLabel:SetPoint("TOPLEFT", 0, -yOffset)
    bgLabel:SetText("Background Color")
    bgLabel:Show()

    local bgColor = config.backgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
    local bgSwatch = CreateColorSwatch(configFrame, bgColor, function(r, g, b)
        BarsData:SetSpellSetting(selectedBarKey, "backgroundColor", { r = r, g = g, b = b, a = 0.8 })
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    bgSwatch:SetPoint("LEFT", bgLabel, "RIGHT", 8, 0)
    bgSwatch:Show()
    yOffset = yOffset + 28

    -- ========================================
    -- Section: Icon
    -- ========================================
    local iconLabel = CreateSectionLabel(configFrame, "Icon", configFrame, 0, -yOffset)
    iconLabel:ClearAllPoints()
    iconLabel:SetPoint("TOPLEFT", 0, -yOffset)
    yOffset = yOffset + 18

    local showIconCheck = CreateCheckbox(configFrame, "Show Icon", function(checked)
        BarsData:SetSpellSetting(selectedBarKey, "showIcon", checked)
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    showIconCheck:SetPoint("TOPLEFT", 0, -yOffset)
    showIconCheck:SetChecked(config.showIcon ~= false)
    showIconCheck:Show()
    yOffset = yOffset + 28

    local posLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    posLabel:SetPoint("TOPLEFT", 0, -yOffset)
    posLabel:SetText("Icon Position")
    posLabel:Show()

    local leftBtn = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    leftBtn:SetSize(55, 22)
    leftBtn:SetPoint("LEFT", posLabel, "RIGHT", 8, 0)
    leftBtn:SetText("Left")
    leftBtn:Show()

    local rightBtn = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    rightBtn:SetSize(55, 22)
    rightBtn:SetPoint("LEFT", leftBtn, "RIGHT", 4, 0)
    rightBtn:SetText("Right")
    rightBtn:Show()

    local function UpdateIconPosButtons()
        local pos = config.iconPosition or "LEFT"
        leftBtn:SetEnabled(pos ~= "LEFT")
        rightBtn:SetEnabled(pos ~= "RIGHT")
    end

    leftBtn:SetScript("OnClick", function()
        BarsData:SetSpellSetting(selectedBarKey, "iconPosition", "LEFT")
        config.iconPosition = "LEFT"
        UpdateIconPosButtons()
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    rightBtn:SetScript("OnClick", function()
        BarsData:SetSpellSetting(selectedBarKey, "iconPosition", "RIGHT")
        config.iconPosition = "RIGHT"
        UpdateIconPosButtons()
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    UpdateIconPosButtons()
    yOffset = yOffset + 28

    -- ========================================
    -- Section: Text
    -- ========================================
    local txtLabel = CreateSectionLabel(configFrame, "Text", configFrame, 0, -yOffset)
    txtLabel:ClearAllPoints()
    txtLabel:SetPoint("TOPLEFT", 0, -yOffset)
    yOffset = yOffset + 18

    local showNameCheck = CreateCheckbox(configFrame, "Show Spell Name", function(checked)
        BarsData:SetSpellSetting(selectedBarKey, "showName", checked)
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    showNameCheck:SetPoint("TOPLEFT", 0, -yOffset)
    showNameCheck:SetChecked(config.showName ~= false)
    showNameCheck:Show()
    yOffset = yOffset + 24

    local showTimeCheck = CreateCheckbox(configFrame, "Show Time Remaining", function(checked)
        BarsData:SetSpellSetting(selectedBarKey, "showTime", checked)
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    showTimeCheck:SetPoint("TOPLEFT", 0, -yOffset)
    showTimeCheck:SetChecked(config.showTime ~= false)
    showTimeCheck:Show()
    yOffset = yOffset + 28

    -- ========================================
    -- Section: Behavior
    -- ========================================
    local behLabel = CreateSectionLabel(configFrame, "Behavior", configFrame, 0, -yOffset)
    behLabel:ClearAllPoints()
    behLabel:SetPoint("TOPLEFT", 0, -yOffset)
    yOffset = yOffset + 18

    local readyCheck = CreateCheckbox(configFrame, "Show When Ready (not on CD)", function(checked)
        BarsData:SetSpellSetting(selectedBarKey, "showWhenReady", checked)
        BarsFrames:OnConfigChanged(selectedBarKey)
    end)
    readyCheck:SetPoint("TOPLEFT", 0, -yOffset)
    readyCheck:SetChecked(config.showWhenReady == true)
    readyCheck:Show()
    yOffset = yOffset + 28

    -- ========================================
    -- Remove button
    -- ========================================
    local removeBtn = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    removeBtn:SetSize(120, 24)
    removeBtn:SetPoint("TOPLEFT", 0, -yOffset)
    removeBtn:SetText("|cffff4444Remove Spell|r")
    removeBtn:Show()
    removeBtn:SetScript("OnClick", function()
        BarsData:RemoveSpell(selectedBarKey)
        BarsFrames:OnSpellRemoved(selectedBarKey)
        selectedBarKey = nil
        RefreshSpellList()
        BarsUI:RefreshConfigPanel()
    end)
end

-- ============================================================================
-- MAIN PANEL CREATION
-- ============================================================================

function BarsUI:CreatePanel()
    if mainPanel then return mainPanel end

    local hubPanel = TUICD.Settings and TUICD.Settings.hubPanel

    mainPanel = CreateFrame("Frame", "TUICD_BarsPanel", UIParent, "BackdropTemplate")
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

    if hubPanel then
        mainPanel:SetPoint("TOPLEFT", hubPanel, "TOPRIGHT", 0, 0)
    else
        mainPanel:SetPoint("CENTER", 0, 0)
    end

    -- Title
    local title = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd100Timer Bars|r")

    -- ========================================
    -- Left side: Spell list
    -- ========================================
    local listBg = CreateFrame("Frame", nil, mainPanel, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 15, -40)
    listBg:SetSize(LIST_WIDTH, PANEL_HEIGHT - 220)
    listBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    listBg:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    listBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    scrollFrame = CreateFrame("ScrollFrame", "TUICD_BarsSpellScroll", listBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 4)

    scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(LIST_WIDTH - 30, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- ========================================
    -- Add spell controls (below list)
    -- ========================================
    local addArea = CreateFrame("Frame", nil, mainPanel)
    addArea:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 0, -6)
    addArea:SetSize(LIST_WIDTH, 160)

    -- Spell ID input
    local addLabel = addArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 0, 0)
    addLabel:SetText("Add Spell ID:")

    local addBox = CreateFrame("EditBox", nil, addArea, "InputBoxTemplate")
    addBox:SetSize(60, 20)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 4, 0)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)

    -- Add button: +CD
    local addCDBtn = CreateFrame("Button", nil, addArea, "UIPanelButtonTemplate")
    addCDBtn:SetSize(50, 22)
    addCDBtn:SetPoint("TOPLEFT", 0, -22)
    addCDBtn:SetText("+CD")
    addCDBtn:SetScript("OnClick", function()
        local spellID = tonumber(addBox:GetText())
        if spellID and spellID > 0 then
            local barKey = BarsData:AddSpell(spellID, BarsData.TYPE_COOLDOWN)
            if barKey then
                BarsFrames:OnSpellAdded(barKey)
                selectedBarKey = barKey
                RefreshSpellList()
                BarsUI:RefreshConfigPanel()
                addBox:SetText("")
            else
                TUICD:Print("Spell " .. spellID .. " is already tracked as a cooldown.")
            end
        end
        addBox:ClearFocus()
    end)

    addBox:SetScript("OnEnterPressed", function() addCDBtn:Click() end)

    -- Import buttons
    local importCDBtn = CreateFrame("Button", nil, addArea, "UIPanelButtonTemplate")
    importCDBtn:SetSize(LIST_WIDTH, 22)
    importCDBtn:SetPoint("TOPLEFT", 0, -50)
    importCDBtn:SetText("Import Cooldowns")
    importCDBtn:SetScript("OnClick", function()
        local count = BarsData:ImportMultiTrackerSpells()
        if count > 0 then
            TUICD:Print("Imported " .. count .. " cooldown(s) from trackers (disabled).")
            RefreshSpellList()
            BarsUI:RefreshConfigPanel()
        else
            TUICD:Print("No new cooldowns to import.")
        end
    end)
    importCDBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Import Cooldowns")
        local available = #BarsData:GetImportableMultiTrackerSpells()
        if available > 0 then
            GameTooltip:AddLine(available .. " new spell(s) available from your\nEssential, Utility, and Custom trackers.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("All tracker spells already imported.\n|cffff8888Open CDM if trackers aren't populated yet.|r", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    importCDBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Clear All
    local clearAllBtn = CreateFrame("Button", nil, addArea, "UIPanelButtonTemplate")
    clearAllBtn:SetSize(LIST_WIDTH, 22)
    clearAllBtn:SetPoint("TOPLEFT", importCDBtn, "BOTTOMLEFT", 0, -4)
    clearAllBtn:SetText("|cffff4444Clear All|r")
    clearAllBtn:SetScript("OnClick", function()
        if not IsShiftKeyDown() then
            TUICD:Print("Hold Shift and click to clear all bars.")
            return
        end
        BarsFrames:DestroyAllBars()
        local count = BarsData:RemoveAllSpells()
        selectedBarKey = nil
        RefreshSpellList()
        BarsUI:RefreshConfigPanel()
        TUICD:Print("Cleared " .. count .. " bar(s).")
    end)
    clearAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clear All Bars")
        GameTooltip:AddLine("Removes every spell from the bars list.\n|cffff8888Shift-click to confirm.|r", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    clearAllBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- ========================================
    -- Right side: Config panel
    -- ========================================
    configFrame = CreateFrame("Frame", nil, mainPanel)
    configFrame:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 12, 0)
    configFrame:SetSize(CONFIG_WIDTH - 20, PANEL_HEIGHT - 80)

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

function BarsUI:Show()
    if not mainPanel then
        self:CreatePanel()
    end

    local hubPanel = TUICD.Settings and TUICD.Settings.hubPanel
    if hubPanel and mainPanel then
        mainPanel:ClearAllPoints()
        mainPanel:SetPoint("TOPLEFT", hubPanel, "TOPRIGHT", 0, 0)
    end

    RefreshSpellList()
    self:RefreshConfigPanel()
    mainPanel:Show()
end

function BarsUI:Hide()
    if mainPanel then mainPanel:Hide() end
end

function BarsUI:IsShown()
    return mainPanel and mainPanel:IsShown()
end

function BarsUI:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function BarsUI:HideAllPanels()
    self:Hide()
end

function BarsUI:Refresh()
    if mainPanel and mainPanel:IsShown() then
        RefreshSpellList()
        self:RefreshConfigPanel()
    end
end

return BarsUI
