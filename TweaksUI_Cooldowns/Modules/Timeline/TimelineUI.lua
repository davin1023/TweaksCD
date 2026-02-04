-- ============================================================================
-- TUI:CD Timeline - Settings UI Panel
-- Phase 4: Spell list + settings panel (like BarsUI pattern)
-- Left side: spell list with checkboxes
-- Right side: settings panel with appearance controls
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.TimelineUI = TUICD.TimelineUI or {}
local TimelineUI = TUICD.TimelineUI

local Timeline  -- Set after load
local TimelineFrames  -- Set after load
local TimelineData  -- Set after load
local DB = TUICD.Database

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH = 540
local PANEL_HEIGHT = 580
local LIST_WIDTH = 180
local CONFIG_WIDTH = 330
local BUTTON_HEIGHT = 26
local BUTTON_SPACING = 2
local SECTION_SPACING = 12
local CONTROL_WIDTH = CONFIG_WIDTH - 40

-- Dark backdrop
local BACKDROP_DARK = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

-- Aspect ratio options
local ASPECT_OPTIONS = {
    { label = "1:1 (Square)", value = "1:1" },
    { label = "4:3", value = "4:3" },
    { label = "3:4", value = "3:4" },
    { label = "16:9 (Wide)", value = "16:9" },
    { label = "9:16 (Tall)", value = "9:16" },
    { label = "2:1", value = "2:1" },
    { label = "1:2", value = "1:2" },
}

-- Safe spell info lookup (Midnight API returns table, not individual values)
local function SafeGetSpellInfo(spellID)
    if not spellID then return nil, nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            return info.name, info.iconID
        end
    end
    return nil, nil
end

-- ============================================================================
-- STATE
-- ============================================================================

local panel = nil
local listScrollChild = nil
local configScrollChild = nil
local visibilityScrollChild = nil
local configFrame = nil  -- The scroll frame (needed for tab switching)
local spellButtons = {}
local controls = {}
local initialized = false
local activeTab = "settings"  -- "settings" or "visibility"
local tabButtons = {}

-- ============================================================================
-- DATABASE DEFAULTS (for Timeline module)
-- ============================================================================

local TIMELINE_DEFAULTS = {
    enabled = false,
    
    -- Bar dimensions
    barWidth = 400,
    barHeight = 4,
    
    -- Bar appearance (the line)
    barColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.9 },
    
    -- Background (encompasses line + icons)
    showBackground = false,
    backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 },
    backgroundPadding = 4,
    
    -- Icon settings
    iconSize = 36,
    iconAspectRatio = "1:1",
    iconSpacing = 2,
    iconVerticalOffset = 0,
    staggerOverlaps = true,  -- Stack icons vertically when they overlap
    
    -- Timeline range
    maxDuration = 30,
    showOverflowStack = true,
    
    -- Cooldown display
    showCooldownSweep = true,
    cooldownTextSize = 10,
    showCooldownText = true,
    cooldownTextOffset = 0,
    
    -- Animation
    updateInterval = 0.033,
    
    -- Position (saved when frame is moved)
    position = nil,
    
    -- Spell tracking
    customSpells = {},      -- { spellID = true, ... }
    disabledSpells = {},    -- { spellID = true, ... }
    
    -- Visibility settings
    visibilityEnabled = false,  -- Master toggle (false = always show)
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

-- ============================================================================
-- DATABASE ACCESS
-- ============================================================================

local function IsDatabaseReady()
    return DB and DB.charDb and DB.GetModuleSetting
end

local function GetSetting(key)
    if not IsDatabaseReady() then
        return TIMELINE_DEFAULTS[key]
    end
    local val = DB:GetModuleSetting("timeline", key)
    if val == nil then
        return TIMELINE_DEFAULTS[key]
    end
    return val
end

local function SetSetting(key, value)
    if not IsDatabaseReady() then return end
    DB:SetModuleSetting("timeline", key, value)
    
    -- Update TimelineFrames if available
    if TimelineFrames and TimelineFrames.Refresh then
        TimelineFrames:Refresh()
    end
end

local function GetAllSettings()
    local settings = {}
    for key, defaultVal in pairs(TIMELINE_DEFAULTS) do
        settings[key] = GetSetting(key)
    end
    return settings
end

-- ============================================================================
-- SPELL ENABLE/DISABLE
-- ============================================================================

local function IsSpellEnabled(spellID)
    local disabled = GetSetting("disabledSpells") or {}
    -- Check both numeric and string key (SavedVariables can convert)
    return not (disabled[spellID] or disabled[tostring(spellID)])
end

local function SetSpellEnabled(spellID, enabled)
    local disabled = GetSetting("disabledSpells") or {}
    -- Always use numeric keys when setting
    spellID = tonumber(spellID) or spellID
    if enabled then
        disabled[spellID] = nil
        disabled[tostring(spellID)] = nil  -- Clean up any string keys too
    else
        disabled[spellID] = true
    end
    SetSetting("disabledSpells", disabled)
    
    -- Refresh the frames
    if TimelineFrames and TimelineFrames.Refresh then
        TimelineFrames:Refresh()
    end
end

local function IsCustomSpell(spellID)
    local custom = GetSetting("customSpells") or {}
    -- Check both numeric and string key (SavedVariables can convert)
    return custom[spellID] == true or custom[tostring(spellID)] == true
end

local function AddCustomSpell(spellID)
    -- Ensure numeric spellID
    spellID = tonumber(spellID)
    if not spellID then return end
    
    local custom = GetSetting("customSpells") or {}
    custom[spellID] = true
    SetSetting("customSpells", custom)
    
    -- Rebuild spell list
    if TimelineData and TimelineData.RebuildSpellList then
        TimelineData:RebuildSpellList()
    end
end

local function RemoveCustomSpell(spellID)
    -- Ensure numeric spellID
    spellID = tonumber(spellID)
    if not spellID then return end
    
    local custom = GetSetting("customSpells") or {}
    custom[spellID] = nil
    custom[tostring(spellID)] = nil  -- Also clear any string key
    SetSetting("customSpells", custom)
    
    -- Also remove from disabled list
    local disabled = GetSetting("disabledSpells") or {}
    disabled[spellID] = nil
    disabled[tostring(spellID)] = nil
    SetSetting("disabledSpells", disabled)
    
    -- Rebuild spell list
    if TimelineData and TimelineData.RebuildSpellList then
        TimelineData:RebuildSpellList()
    end
end

-- ============================================================================
-- WIDGET HELPERS
-- ============================================================================

local function CreateSectionLabel(parent, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(CONTROL_WIDTH, 16)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText("|cffaaaaaa— " .. text .. " —|r")
    frame._label = label
    return frame
end

local function CreateCheckbox(parent, text, tooltip)
    local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    check.Text:SetText(text)
    check.Text:SetFontObject("GameFontNormalSmall")
    if tooltip then
        check.tooltipText = tooltip
    end
    return check
end

local function CreateSlider(parent, label, min, max, step, width)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or CONTROL_WIDTH, 40)
    
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    
    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -15)
    slider:SetSize((width or CONTROL_WIDTH) - 50, 17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    
    slider.Low:SetText("")
    slider.High:SetText("")
    
    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valueText:SetWidth(40)
    
    container.slider = slider
    container.valueText = valueText
    
    function container:SetValue(val)
        slider:SetValue(val)
        valueText:SetText(tostring(math.floor(val + 0.5)))
    end
    
    function container:SetOnChange(callback)
        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            valueText:SetText(tostring(value))
            if callback then callback(value) end
        end)
    end
    
    return container
end

local function CreateDropdown(parent, label, width, options)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or CONTROL_WIDTH, 45)
    
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    
    local dropdown = CreateFrame("Frame", nil, container, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", -16, -12)
    UIDropDownMenu_SetWidth(dropdown, (width or CONTROL_WIDTH) - 40)
    
    container.dropdown = dropdown
    container.options = options
    
    function container:SetValue(value)
        for _, opt in ipairs(options) do
            if opt.value == value then
                UIDropDownMenu_SetText(dropdown, opt.label)
                break
            end
        end
    end
    
    function container:SetOnChange(callback)
        UIDropDownMenu_Initialize(dropdown, function(self, level)
            for _, opt in ipairs(options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.func = function()
                    UIDropDownMenu_SetText(dropdown, opt.label)
                    if callback then callback(opt.value) end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end
    
    return container
end

-- Color picker with opacity (uses ColorPickerFrame's built-in opacity)
local function CreateColorPicker(parent, label, width)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or CONTROL_WIDTH, 26)
    
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)
    
    -- Color swatch button
    local swatch = CreateFrame("Button", nil, container)
    swatch:SetSize(24, 24)
    swatch:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    
    -- Border (BACKGROUND layer)
    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.5, 0.5, 0.5, 1)
    
    -- Color texture (ARTWORK layer) - shows color WITH alpha
    local colorTex = swatch:CreateTexture(nil, "ARTWORK")
    colorTex:SetAllPoints()
    colorTex:SetColorTexture(1, 1, 1, 1)
    swatch.colorTex = colorTex
    
    container.swatch = swatch
    container.currentColor = { r = 1, g = 1, b = 1, a = 1 }
    
    function container:SetColor(color)
        if not color then color = { r = 1, g = 1, b = 1, a = 1 } end
        self.currentColor = { r = color.r or 1, g = color.g or 1, b = color.b or 1, a = color.a or 1 }
        -- Show the color with its alpha on the swatch
        colorTex:SetColorTexture(self.currentColor.r, self.currentColor.g, self.currentColor.b, self.currentColor.a)
    end
    
    function container:SetOnChange(callback)
        self.callback = callback
        
        swatch:SetScript("OnClick", function()
            local c = self.currentColor
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c.r, g = c.g, b = c.b,
                hasOpacity = true,
                opacity = c.a,
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local a = ColorPickerFrame:GetColorAlpha() or 1
                    c.r, c.g, c.b, c.a = r, g, b, a
                    colorTex:SetColorTexture(r, g, b, a)
                    if callback then callback(c) end
                end,
                opacityFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local a = ColorPickerFrame:GetColorAlpha() or 1
                    c.r, c.g, c.b, c.a = r, g, b, a
                    colorTex:SetColorTexture(r, g, b, a)
                    if callback then callback(c) end
                end,
                cancelFunc = function(prev)
                    c.r, c.g, c.b, c.a = prev.r, prev.g, prev.b, prev.a or 1
                    colorTex:SetColorTexture(c.r, c.g, c.b, c.a)
                    if callback then callback(c) end
                end,
            })
        end)
    end
    
    return container
end

-- ============================================================================
-- SPELL LIST (left side)
-- ============================================================================

local function RefreshSpellList()
    if not listScrollChild then return end
    
    -- Hide existing buttons
    for _, btn in ipairs(spellButtons) do
        btn:Hide()
    end
    wipe(spellButtons)
    
    -- Get tracked spells from TimelineData (already has name/icon cached)
    if not TimelineData then return end
    
    -- Ensure spell list is built (pulls from database and caches spell info)
    local trackedSpells = TimelineData:GetTrackedSpells() or {}
    if not next(trackedSpells) then
        -- Spell list is empty, trigger a rebuild
        TimelineData:RebuildSpellList()
        trackedSpells = TimelineData:GetTrackedSpells() or {}
    end
    
    -- Build sorted list directly from cached data (no API lookups here)
    local spellList = {}
    for spellID, data in pairs(trackedSpells) do
        table.insert(spellList, {
            spellID = spellID,
            name = data.name or ("Spell " .. spellID),
            icon = data.icon,
            source = data.source,
            isCustom = data.isCustom or IsCustomSpell(spellID),
            enabled = IsSpellEnabled(spellID),
        })
    end
    
    -- Sort by name
    table.sort(spellList, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    
    local yOffset = 0
    
    for i, entry in ipairs(spellList) do
        local btn = CreateFrame("Button", nil, listScrollChild)
        btn:SetSize(LIST_WIDTH - 10, BUTTON_HEIGHT)
        btn:SetPoint("TOPLEFT", 0, -yOffset)
        
        -- Highlight
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.82, 0, 0.15)
        
        -- Checkbox for enable/disable
        local check = CreateFrame("CheckButton", nil, btn, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("LEFT", 2, 0)
        check:SetChecked(entry.enabled)
        check:SetScript("OnClick", function(self)
            SetSpellEnabled(entry.spellID, self:GetChecked())
            RefreshSpellList()
        end)
        
        -- Icon
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BUTTON_HEIGHT - 6, BUTTON_HEIGHT - 6)
        icon:SetPoint("LEFT", check, "RIGHT", 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(entry.icon or 134400)
        
        if not entry.enabled then
            icon:SetDesaturated(true)
        end
        
        -- Name
        local name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        name:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        name:SetJustifyH("LEFT")
        name:SetText(entry.name)
        name:SetWordWrap(false)
        
        if not entry.enabled then
            name:SetTextColor(0.5, 0.5, 0.5)
        end
        
        -- Custom indicator
        if entry.isCustom then
            local customTag = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            customTag:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            customTag:SetText("|cff888888*|r")
        end
        
        -- Right-click to remove custom spells
        if entry.isCustom then
            btn:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" then
                    RemoveCustomSpell(entry.spellID)
                    RefreshSpellList()
                end
            end)
        end
        
        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(entry.spellID)
            if entry.isCustom then
                GameTooltip:AddLine("|cff888888Custom spell - right-click to remove|r")
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        table.insert(spellButtons, btn)
        yOffset = yOffset + BUTTON_HEIGHT + BUTTON_SPACING
    end
    
    listScrollChild:SetHeight(math.max(yOffset + 20, 300))
end

-- ============================================================================
-- SETTINGS PANEL (right side)
-- ============================================================================

local function BuildSettingsPanel()
    if not configScrollChild then return end
    
    -- Clear existing controls
    for _, child in ipairs({configScrollChild:GetChildren()}) do
        child:Hide()
    end
    wipe(controls)
    
    local y = 0
    
    -- === Enable Toggle ===
    controls.enabled = CreateCheckbox(configScrollChild, "Enable Timeline", "Show the cooldown timeline display")
    controls.enabled:SetPoint("TOPLEFT", 0, -y)
    controls.enabled:SetScript("OnClick", function(self)
        local enabled = self:GetChecked()
        SetSetting("enabled", enabled)
        if enabled then
            if Timeline then Timeline:Enable() end
        else
            if Timeline then Timeline:Disable() end
        end
    end)
    controls.enabled:Show()
    y = y + 30
    
    -- === Timeline Range Section ===
    local rangeSection = CreateSectionLabel(configScrollChild, "Timeline Range")
    rangeSection:SetPoint("TOPLEFT", 0, -y)
    rangeSection:Show()
    y = y + 20
    
    controls.maxDuration = CreateSlider(configScrollChild, "Timeline Length (seconds)", 10, 180, 5, CONTROL_WIDTH)
    controls.maxDuration:SetPoint("TOPLEFT", 0, -y)
    controls.maxDuration:SetOnChange(function(val) SetSetting("maxDuration", val) end)
    controls.maxDuration:Show()
    y = y + 45
    
    controls.barWidth = CreateSlider(configScrollChild, "Bar Width", 200, 800, 10, CONTROL_WIDTH)
    controls.barWidth:SetPoint("TOPLEFT", 0, -y)
    controls.barWidth:SetOnChange(function(val) SetSetting("barWidth", val) end)
    controls.barWidth:Show()
    y = y + 45
    
    -- === Bar Appearance Section ===
    local barSection = CreateSectionLabel(configScrollChild, "Bar & Background")
    barSection:SetPoint("TOPLEFT", 0, -y)
    barSection:Show()
    y = y + 20
    
    controls.barHeight = CreateSlider(configScrollChild, "Line Height", 1, 20, 1, CONTROL_WIDTH)
    controls.barHeight:SetPoint("TOPLEFT", 0, -y)
    controls.barHeight:SetOnChange(function(val) SetSetting("barHeight", val) end)
    controls.barHeight:Show()
    y = y + 45
    
    controls.barColor = CreateColorPicker(configScrollChild, "Line Color", CONTROL_WIDTH)
    controls.barColor:SetPoint("TOPLEFT", 0, -y)
    controls.barColor:SetOnChange(function(color)
        SetSetting("barColor", { r = color.r, g = color.g, b = color.b, a = color.a })
    end)
    controls.barColor:Show()
    y = y + 30
    
    controls.showBackground = CreateCheckbox(configScrollChild, "Show Background", "Display a background panel behind the timeline")
    controls.showBackground:SetPoint("TOPLEFT", 0, -y)
    controls.showBackground:SetScript("OnClick", function(self)
        SetSetting("showBackground", self:GetChecked())
    end)
    controls.showBackground:Show()
    y = y + 26
    
    controls.backgroundColor = CreateColorPicker(configScrollChild, "Background Color", CONTROL_WIDTH)
    controls.backgroundColor:SetPoint("TOPLEFT", 0, -y)
    controls.backgroundColor:SetOnChange(function(color)
        SetSetting("backgroundColor", { r = color.r, g = color.g, b = color.b, a = color.a })
    end)
    controls.backgroundColor:Show()
    y = y + 30
    
    controls.backgroundPadding = CreateSlider(configScrollChild, "Background Padding", 0, 20, 1, CONTROL_WIDTH)
    controls.backgroundPadding:SetPoint("TOPLEFT", 0, -y)
    controls.backgroundPadding:SetOnChange(function(val) SetSetting("backgroundPadding", val) end)
    controls.backgroundPadding:Show()
    y = y + 45
    
    -- === Icon Settings Section ===
    local iconSection = CreateSectionLabel(configScrollChild, "Icon Settings")
    iconSection:SetPoint("TOPLEFT", 0, -y)
    iconSection:Show()
    y = y + 20
    
    controls.iconSize = CreateSlider(configScrollChild, "Icon Size", 16, 64, 2, CONTROL_WIDTH)
    controls.iconSize:SetPoint("TOPLEFT", 0, -y)
    controls.iconSize:SetOnChange(function(val) SetSetting("iconSize", val) end)
    controls.iconSize:Show()
    y = y + 45
    
    controls.iconAspectRatio = CreateDropdown(configScrollChild, "Icon Aspect Ratio", CONTROL_WIDTH, ASPECT_OPTIONS)
    controls.iconAspectRatio:SetPoint("TOPLEFT", 0, -y)
    controls.iconAspectRatio:SetOnChange(function(val) SetSetting("iconAspectRatio", val) end)
    controls.iconAspectRatio:Show()
    y = y + 50
    
    controls.iconVerticalOffset = CreateSlider(configScrollChild, "Vertical Offset", -50, 50, 1, CONTROL_WIDTH)
    controls.iconVerticalOffset:SetPoint("TOPLEFT", 0, -y)
    controls.iconVerticalOffset:SetOnChange(function(val) SetSetting("iconVerticalOffset", val) end)
    controls.iconVerticalOffset:Show()
    y = y + 45
    
    controls.staggerOverlaps = CreateCheckbox(configScrollChild, "Stagger Overlapping Icons", "Stack icons vertically when they overlap on the timeline")
    controls.staggerOverlaps:SetPoint("TOPLEFT", 0, -y)
    controls.staggerOverlaps:SetScript("OnClick", function(self)
        SetSetting("staggerOverlaps", self:GetChecked())
    end)
    controls.staggerOverlaps:Show()
    y = y + 26
    
    -- === Cooldown Display Section ===
    local displaySection = CreateSectionLabel(configScrollChild, "Cooldown Display")
    displaySection:SetPoint("TOPLEFT", 0, -y)
    displaySection:Show()
    y = y + 20
    
    controls.showCooldownSweep = CreateCheckbox(configScrollChild, "Show Cooldown Sweep", "Display radial cooldown animation")
    controls.showCooldownSweep:SetPoint("TOPLEFT", 0, -y)
    controls.showCooldownSweep:SetScript("OnClick", function(self)
        SetSetting("showCooldownSweep", self:GetChecked())
    end)
    controls.showCooldownSweep:Show()
    y = y + 26
    
    controls.showCooldownText = CreateCheckbox(configScrollChild, "Show Duration Text", "Display remaining time on icons")
    controls.showCooldownText:SetPoint("TOPLEFT", 0, -y)
    controls.showCooldownText:SetScript("OnClick", function(self)
        SetSetting("showCooldownText", self:GetChecked())
    end)
    controls.showCooldownText:Show()
    y = y + 26
    
    controls.cooldownTextSize = CreateSlider(configScrollChild, "Text Size", 6, 24, 1, CONTROL_WIDTH)
    controls.cooldownTextSize:SetPoint("TOPLEFT", 0, -y)
    controls.cooldownTextSize:SetOnChange(function(val) SetSetting("cooldownTextSize", val) end)
    controls.cooldownTextSize:Show()
    y = y + 45
    
    controls.cooldownTextOffset = CreateSlider(configScrollChild, "Text Offset (+ above, - below)", -30, 30, 1, CONTROL_WIDTH)
    controls.cooldownTextOffset:SetPoint("TOPLEFT", 0, -y)
    controls.cooldownTextOffset:SetOnChange(function(val) SetSetting("cooldownTextOffset", val) end)
    controls.cooldownTextOffset:Show()
    y = y + 45
    
    -- === Long Cooldowns Section ===
    local overflowSection = CreateSectionLabel(configScrollChild, "Long Cooldowns")
    overflowSection:SetPoint("TOPLEFT", 0, -y)
    overflowSection:Show()
    y = y + 20
    
    controls.showOverflowStack = CreateCheckbox(configScrollChild, "Stack Overflow Icons", "Stack icons beyond range on the right")
    controls.showOverflowStack:SetPoint("TOPLEFT", 0, -y)
    controls.showOverflowStack:SetScript("OnClick", function(self)
        SetSetting("showOverflowStack", self:GetChecked())
    end)
    controls.showOverflowStack:Show()
    y = y + 30
    
    configScrollChild:SetHeight(y + 20)
end

-- ============================================================================
-- VISIBILITY TAB
-- ============================================================================

local function RefreshVisibilityControls()
    if not controls.visibilityEnabled then return end
    
    controls.visibilityEnabled:SetChecked(GetSetting("visibilityEnabled"))
    if controls.showInCombat then controls.showInCombat:SetChecked(GetSetting("showInCombat")) end
    if controls.showOutOfCombat then controls.showOutOfCombat:SetChecked(GetSetting("showOutOfCombat")) end
    if controls.showSolo then controls.showSolo:SetChecked(GetSetting("showSolo")) end
    if controls.showInParty then controls.showInParty:SetChecked(GetSetting("showInParty")) end
    if controls.showInRaid then controls.showInRaid:SetChecked(GetSetting("showInRaid")) end
    if controls.showInDungeon then controls.showInDungeon:SetChecked(GetSetting("showInDungeon")) end
    if controls.showInDelve then controls.showInDelve:SetChecked(GetSetting("showInDelve")) end
    if controls.showInArena then controls.showInArena:SetChecked(GetSetting("showInArena")) end
    if controls.showInBattleground then controls.showInBattleground:SetChecked(GetSetting("showInBattleground")) end
    if controls.showHasTarget then controls.showHasTarget:SetChecked(GetSetting("showHasTarget")) end
    if controls.showNoTarget then controls.showNoTarget:SetChecked(GetSetting("showNoTarget")) end
    if controls.showMounted then controls.showMounted:SetChecked(GetSetting("showMounted")) end
    if controls.showNotMounted then controls.showNotMounted:SetChecked(GetSetting("showNotMounted")) end
end

local function BuildVisibilityTab()
    if not visibilityScrollChild then return end
    
    -- Clear existing children
    for _, child in ipairs({visibilityScrollChild:GetChildren()}) do
        child:Hide()
    end
    
    local y = 10
    
    -- Title
    local title = visibilityScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, -y)
    title:SetText("|cffffd100Visibility Conditions|r")
    title:Show()
    y = y + 25
    
    -- Master toggle
    controls.visibilityEnabled = CreateCheckbox(visibilityScrollChild, "Enable Visibility Rules", "When enabled, timeline only shows in checked situations")
    controls.visibilityEnabled:SetPoint("TOPLEFT", 0, -y)
    controls.visibilityEnabled:SetScript("OnClick", function(self)
        SetSetting("visibilityEnabled", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.visibilityEnabled:Show()
    y = y + 26
    
    -- Hint text
    local hint = visibilityScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 20, -y)
    hint:SetText("|cff888888When enabled, timeline only shows in checked situations:|r")
    hint:Show()
    y = y + 18
    
    -- Combat section
    local combatSection = CreateSectionLabel(visibilityScrollChild, "Combat State")
    combatSection:SetPoint("TOPLEFT", 0, -y)
    combatSection:Show()
    y = y + 18
    
    controls.showInCombat = CreateCheckbox(visibilityScrollChild, "Show In Combat", nil)
    controls.showInCombat:SetPoint("TOPLEFT", 20, -y)
    controls.showInCombat:SetScript("OnClick", function(self)
        SetSetting("showInCombat", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showInCombat:Show()
    y = y + 24
    
    controls.showOutOfCombat = CreateCheckbox(visibilityScrollChild, "Show Out of Combat", nil)
    controls.showOutOfCombat:SetPoint("TOPLEFT", 20, -y)
    controls.showOutOfCombat:SetScript("OnClick", function(self)
        SetSetting("showOutOfCombat", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showOutOfCombat:Show()
    y = y + 28
    
    -- Group section
    local groupSection = CreateSectionLabel(visibilityScrollChild, "Group Type")
    groupSection:SetPoint("TOPLEFT", 0, -y)
    groupSection:Show()
    y = y + 18
    
    controls.showSolo = CreateCheckbox(visibilityScrollChild, "Show Solo", nil)
    controls.showSolo:SetPoint("TOPLEFT", 20, -y)
    controls.showSolo:SetScript("OnClick", function(self)
        SetSetting("showSolo", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showSolo:Show()
    y = y + 24
    
    controls.showInParty = CreateCheckbox(visibilityScrollChild, "Show in Party", nil)
    controls.showInParty:SetPoint("TOPLEFT", 20, -y)
    controls.showInParty:SetScript("OnClick", function(self)
        SetSetting("showInParty", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showInParty:Show()
    y = y + 24
    
    controls.showInRaid = CreateCheckbox(visibilityScrollChild, "Show in Raid", nil)
    controls.showInRaid:SetPoint("TOPLEFT", 20, -y)
    controls.showInRaid:SetScript("OnClick", function(self)
        SetSetting("showInRaid", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showInRaid:Show()
    y = y + 28
    
    -- Instance section
    local instanceSection = CreateSectionLabel(visibilityScrollChild, "Instance Type")
    instanceSection:SetPoint("TOPLEFT", 0, -y)
    instanceSection:Show()
    y = y + 18
    
    controls.showInArena = CreateCheckbox(visibilityScrollChild, "Show in Arena", nil)
    controls.showInArena:SetPoint("TOPLEFT", 20, -y)
    controls.showInArena:SetScript("OnClick", function(self)
        SetSetting("showInArena", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showInArena:Show()
    y = y + 24
    
    controls.showInBattleground = CreateCheckbox(visibilityScrollChild, "Show in Battleground", nil)
    controls.showInBattleground:SetPoint("TOPLEFT", 20, -y)
    controls.showInBattleground:SetScript("OnClick", function(self)
        SetSetting("showInBattleground", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showInBattleground:Show()
    y = y + 24
    
    controls.showInDungeon = CreateCheckbox(visibilityScrollChild, "Show in Dungeon", nil)
    controls.showInDungeon:SetPoint("TOPLEFT", 20, -y)
    controls.showInDungeon:SetScript("OnClick", function(self)
        SetSetting("showInDungeon", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showInDungeon:Show()
    y = y + 24
    
    controls.showInDelve = CreateCheckbox(visibilityScrollChild, "Show in Delve", nil)
    controls.showInDelve:SetPoint("TOPLEFT", 20, -y)
    controls.showInDelve:SetScript("OnClick", function(self)
        SetSetting("showInDelve", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showInDelve:Show()
    y = y + 28
    
    -- Target / Mount section
    local targetSection = CreateSectionLabel(visibilityScrollChild, "Target / Mount")
    targetSection:SetPoint("TOPLEFT", 0, -y)
    targetSection:Show()
    y = y + 18
    
    controls.showHasTarget = CreateCheckbox(visibilityScrollChild, "Has Target", nil)
    controls.showHasTarget:SetPoint("TOPLEFT", 20, -y)
    controls.showHasTarget:SetScript("OnClick", function(self)
        SetSetting("showHasTarget", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showHasTarget:Show()
    y = y + 24
    
    controls.showNoTarget = CreateCheckbox(visibilityScrollChild, "No Target", nil)
    controls.showNoTarget:SetPoint("TOPLEFT", 20, -y)
    controls.showNoTarget:SetScript("OnClick", function(self)
        SetSetting("showNoTarget", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showNoTarget:Show()
    y = y + 24
    
    controls.showMounted = CreateCheckbox(visibilityScrollChild, "Mounted", nil)
    controls.showMounted:SetPoint("TOPLEFT", 20, -y)
    controls.showMounted:SetScript("OnClick", function(self)
        SetSetting("showMounted", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showMounted:Show()
    y = y + 24
    
    controls.showNotMounted = CreateCheckbox(visibilityScrollChild, "Not Mounted", nil)
    controls.showNotMounted:SetPoint("TOPLEFT", 20, -y)
    controls.showNotMounted:SetScript("OnClick", function(self)
        SetSetting("showNotMounted", self:GetChecked())
        if TimelineFrames and TimelineFrames.UpdateVisibility then
            TimelineFrames:UpdateVisibility()
        end
    end)
    controls.showNotMounted:Show()
    y = y + 30
    
    visibilityScrollChild:SetHeight(y + 20)
    
    -- Refresh the visibility control values
    RefreshVisibilityControls()
end

-- ============================================================================
-- TAB SWITCHING
-- ============================================================================

local function RefreshControls()
    if not controls.enabled then return end
    
    controls.enabled:SetChecked(GetSetting("enabled"))
    controls.maxDuration:SetValue(GetSetting("maxDuration"))
    controls.barWidth:SetValue(GetSetting("barWidth"))
    controls.barHeight:SetValue(GetSetting("barHeight"))
    
    -- Color pickers
    local barColor = GetSetting("barColor") or { r = 0.4, g = 0.4, b = 0.4, a = 0.9 }
    controls.barColor:SetColor(barColor)
    
    controls.showBackground:SetChecked(GetSetting("showBackground"))
    
    local bgColor = GetSetting("backgroundColor") or { r = 0, g = 0, b = 0, a = 0.5 }
    controls.backgroundColor:SetColor(bgColor)
    
    controls.backgroundPadding:SetValue(GetSetting("backgroundPadding") or 4)
    controls.iconSize:SetValue(GetSetting("iconSize"))
    controls.iconAspectRatio:SetValue(GetSetting("iconAspectRatio"))
    controls.iconVerticalOffset:SetValue(GetSetting("iconVerticalOffset"))
    controls.staggerOverlaps:SetChecked(GetSetting("staggerOverlaps") ~= false)
    controls.showCooldownSweep:SetChecked(GetSetting("showCooldownSweep"))
    controls.showCooldownText:SetChecked(GetSetting("showCooldownText"))
    controls.cooldownTextSize:SetValue(GetSetting("cooldownTextSize"))
    controls.cooldownTextOffset:SetValue(GetSetting("cooldownTextOffset") or 0)
    controls.showOverflowStack:SetChecked(GetSetting("showOverflowStack"))
end

local function SelectTab(tabKey)
    activeTab = tabKey
    for key, btn in pairs(tabButtons) do
        if key == tabKey then
            btn:GetFontString():SetTextColor(1, 0.82, 0)  -- Gold active
            btn._underline:Show()
        else
            btn:GetFontString():SetTextColor(0.5, 0.5, 0.5)  -- Grey inactive
            btn._underline:Hide()
        end
    end
    
    -- Hide all children from both scroll containers first
    if configScrollChild then
        for _, child in ipairs({configScrollChild:GetChildren()}) do
            child:Hide()
        end
    end
    if visibilityScrollChild then
        for _, child in ipairs({visibilityScrollChild:GetChildren()}) do
            child:Hide()
        end
    end
    
    if tabKey == "visibility" then
        -- Hide settings scroll child, show visibility scroll child
        if configScrollChild then configScrollChild:Hide() end
        if visibilityScrollChild then visibilityScrollChild:Show() end
        configFrame:SetScrollChild(visibilityScrollChild)
        BuildVisibilityTab()
    else
        -- Hide visibility scroll child, show settings scroll child
        if visibilityScrollChild then visibilityScrollChild:Hide() end
        if configScrollChild then configScrollChild:Show() end
        configFrame:SetScrollChild(configScrollChild)
        -- Re-show settings content and refresh
        for _, child in ipairs({configScrollChild:GetChildren()}) do
            child:Show()
        end
        RefreshControls()
    end
end

-- ============================================================================
-- MAIN PANEL CREATION
-- ============================================================================

local function CreatePanel()
    if panel then return panel end
    
    -- Get BarsHub panel to dock to
    local dockTo = TUICD.BarsHub and TUICD.BarsHub:GetPanel()
    
    -- Main panel
    panel = CreateFrame("Frame", "TUICD_TimelineSettingsPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetBackdrop(BACKDROP_DARK)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("HIGH")
    panel:SetFrameLevel(100)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:Hide()
    
    -- Position: dock to BarsHub if available
    if dockTo then
        panel:SetPoint("TOPLEFT", dockTo, "TOPRIGHT", 0, 0)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    
    tinsert(UISpecialFrames, "TUICD_TimelineSettingsPanel")
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cff00ccffTimeline Settings|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    -- ========================================
    -- LEFT SIDE: Spell List
    -- ========================================
    local listBg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 15, -40)
    listBg:SetSize(LIST_WIDTH, PANEL_HEIGHT - 160)
    listBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    listBg:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    listBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    local listTitle = listBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listTitle:SetPoint("TOP", 0, 8)
    listTitle:SetText("|cffffd100Tracked Spells|r")
    
    -- Scroll frame for spell list
    local listScrollFrame = CreateFrame("ScrollFrame", nil, listBg, "UIPanelScrollFrameTemplate")
    listScrollFrame:SetPoint("TOPLEFT", 5, -5)
    listScrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
    
    listScrollChild = CreateFrame("Frame", nil, listScrollFrame)
    listScrollChild:SetSize(LIST_WIDTH - 30, 400)
    listScrollFrame:SetScrollChild(listScrollChild)
    
    -- ========================================
    -- Add spell controls (below list)
    -- ========================================
    local addArea = CreateFrame("Frame", nil, panel)
    addArea:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 0, -6)
    addArea:SetSize(LIST_WIDTH, 80)
    
    local addLabel = addArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 0, 0)
    addLabel:SetText("Add Spell ID:")
    
    local addBox = CreateFrame("EditBox", nil, addArea, "InputBoxTemplate")
    addBox:SetSize(70, 20)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 4, 0)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)
    
    local addBtn = CreateFrame("Button", nil, addArea, "UIPanelButtonTemplate")
    addBtn:SetSize(LIST_WIDTH, 22)
    addBtn:SetPoint("TOPLEFT", 0, -22)
    addBtn:SetText("Add Spell")
    addBtn:SetScript("OnClick", function()
        local sid = tonumber(addBox:GetText())
        if sid and sid > 0 then
            local name = SafeGetSpellInfo(sid)
            if name then
                AddCustomSpell(sid)
                RefreshSpellList()
                addBox:SetText("")
                TUICD:Print("Added spell: " .. name .. " (" .. sid .. ")")
            else
                TUICD:Print("Invalid spell ID: " .. sid)
            end
        end
        addBox:ClearFocus()
    end)
    
    addBox:SetScript("OnEnterPressed", function() addBtn:Click() end)
    
    local importBtn = CreateFrame("Button", nil, addArea, "UIPanelButtonTemplate")
    importBtn:SetSize(LIST_WIDTH, 22)
    importBtn:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -4)
    importBtn:SetText("Import from Trackers")
    importBtn:SetScript("OnClick", function()
        if TimelineData and TimelineData.RebuildSpellList then
            TimelineData:RebuildSpellList()
            
            -- Save all tracker spells to customSpells for persistence
            local trackedSpells = TimelineData:GetTrackedSpells() or {}
            local custom = GetSetting("customSpells") or {}
            local addedCount = 0
            
            for spellID, data in pairs(trackedSpells) do
                if not custom[spellID] then
                    custom[spellID] = true
                    addedCount = addedCount + 1
                end
            end
            
            SetSetting("customSpells", custom)
            RefreshSpellList()
            TUICD:Print(string.format("Imported %d spells from trackers", addedCount))
        end
    end)
    importBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Import from Trackers")
        GameTooltip:AddLine("Import spells from Essential, Utility, and Custom trackers and save them.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    importBtn:SetScript("OnLeave", GameTooltip_Hide)
    
    -- ========================================
    -- RIGHT SIDE: Settings with Tab Bar
    -- ========================================
    local configBg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    configBg:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 10, 0)
    configBg:SetSize(CONFIG_WIDTH, PANEL_HEIGHT - 55)
    configBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    configBg:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    configBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, configBg)
    tabBar:SetPoint("TOPLEFT", 10, -5)
    tabBar:SetSize(CONFIG_WIDTH - 40, 25)
    
    local tabDefs = {
        { key = "settings", label = "Settings" },
        { key = "visibility", label = "Visibility" },
    }
    
    local tabX = 0
    for _, tabDef in ipairs(tabDefs) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetHeight(20)
        
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", 0, 0)
        fs:SetText(tabDef.label)
        btn:SetFontString(fs)
        btn:SetWidth(fs:GetStringWidth() + 10)
        btn:SetPoint("LEFT", tabX, 0)
        
        local underline = btn:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(2)
        underline:SetPoint("BOTTOMLEFT", fs, "BOTTOMLEFT", 0, -2)
        underline:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, -2)
        underline:SetColorTexture(1, 0.82, 0, 1)
        underline:Hide()
        btn._underline = underline
        
        btn:SetScript("OnClick", function()
            SelectTab(tabDef.key)
        end)
        
        tabButtons[tabDef.key] = btn
        tabX = tabX + btn:GetWidth() + 15
    end
    
    -- Scroll frame for settings (below tab bar)
    local configScrollFrame = CreateFrame("ScrollFrame", nil, configBg, "UIPanelScrollFrameTemplate")
    configScrollFrame:SetPoint("TOPLEFT", 10, -30)
    configScrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    configFrame = configScrollFrame  -- Store reference for tab switching
    
    configScrollChild = CreateFrame("Frame", nil, configScrollFrame)
    configScrollChild:SetSize(CONFIG_WIDTH - 50, 800)
    configScrollFrame:SetScrollChild(configScrollChild)
    
    -- Create visibility scroll child (parented to configScrollFrame so it's not orphaned)
    visibilityScrollChild = CreateFrame("Frame", nil, configScrollFrame)
    visibilityScrollChild:SetSize(CONFIG_WIDTH - 50, 800)
    visibilityScrollChild:Hide()  -- Hide initially
    
    -- Build the settings UI
    BuildSettingsPanel()
    
    -- Select default tab
    SelectTab("settings")
    
    return panel
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function TimelineUI:Initialize()
    if initialized then return end
    
    -- Get references
    Timeline = TUICD.Timeline
    TimelineFrames = TUICD.TimelineFrames
    TimelineData = TUICD.TimelineData
    
    -- Ensure defaults exist in database (only if database is ready)
    if IsDatabaseReady() then
        local settings = DB:GetModuleSettings("timeline")
        if settings then
            for key, defaultVal in pairs(TIMELINE_DEFAULTS) do
                if settings[key] == nil then
                    settings[key] = defaultVal
                end
            end
        end
        
        -- Auto-enable is handled by Timeline.lua's TUICD_INITIALIZED callback
        -- Don't duplicate it here
    end
    
    initialized = true
end

function TimelineUI:Show()
    self:Initialize()
    
    if not panel then
        CreatePanel()
    end
    
    RefreshControls()
    RefreshSpellList()
    
    -- Refresh TimelineFrames with current settings
    if TimelineFrames and TimelineFrames.Refresh then
        TimelineFrames:Refresh()
    end
    
    panel:Show()
end

function TimelineUI:Hide()
    if panel then
        panel:Hide()
    end
end

function TimelineUI:Toggle()
    if panel and panel:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function TimelineUI:IsShown()
    return panel and panel:IsShown()
end

function TimelineUI:GetPanel()
    return panel
end

-- Expose for TimelineFrames
function TimelineUI:GetSetting(key)
    return GetSetting(key)
end

function TimelineUI:SetSetting(key, value)
    SetSetting(key, value)
end

function TimelineUI:GetDefaults()
    return TIMELINE_DEFAULTS
end

function TimelineUI:IsSpellEnabled(spellID)
    return IsSpellEnabled(spellID)
end

function TimelineUI:RefreshSpellList()
    RefreshSpellList()
end

-- ============================================================================
-- RETURN
-- ============================================================================

return TimelineUI
