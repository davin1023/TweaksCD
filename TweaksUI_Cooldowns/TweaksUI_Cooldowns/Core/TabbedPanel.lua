-- ============================================================================
-- TweaksUI: TabbedPanel
-- Shared tabbed settings panel factory for consistent UX across all modules
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.TabbedPanel = {}
local TabbedPanel = TUICD.TabbedPanel

-- Local references for performance
local UI = nil  -- Set after Constants loads

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

-- Ensure UI constants are loaded
local function EnsureUI()
    if not UI then
        UI = TUICD.UI
    end
    return UI
end

-- Create a tab button with standard styling
local function CreateTabButton(parent, tabKey, tabLabel, onClick)
    local UI = EnsureUI()
    
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(UI.TAB_HEIGHT or 24)
    btn.tabKey = tabKey
    
    -- Background texture
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    btn.bg = bg
    
    -- Label text
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(tabLabel)
    btn:SetFontString(text)
    btn:SetWidth(text:GetStringWidth() + 24)
    
    -- Click handler
    btn:SetScript("OnClick", function(self)
        if onClick then onClick(tabKey) end
    end)
    
    -- Hover effects
    btn:SetScript("OnEnter", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.7)
        end
    end)
    
    btn:SetScript("OnLeave", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        end
    end)
    
    return btn
end

-- Set tab button active/inactive state
local function SetTabActive(btn, isActive)
    btn.isActive = isActive
    if isActive then
        btn:GetFontString():SetTextColor(1, 0.82, 0)  -- Gold
        btn.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    else
        btn:GetFontString():SetTextColor(0.6, 0.6, 0.6)  -- Grey
        btn.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    end
end

-- Create scrollable content area for a tab
local function CreateTabContent(parent, panelWidth, scrollChildHeight)
    local UI = EnsureUI()
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, UI.TAB_CONTENT_Y or -72)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 12)
    scrollFrame:Hide()
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize((panelWidth or 420) - 50, scrollChildHeight or 800)
    scrollFrame:SetScrollChild(scrollChild)
    
    return scrollFrame, scrollChild
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Create a standard tabbed settings panel
    
    @param options table {
        name = "UniquePanelName",           -- Required: Unique frame name
        title = "Panel Title",              -- Required: Display title (gold colored)
        width = 420,                        -- Optional: Panel width (default: UI.PANEL_WIDTH)
        height = 600,                       -- Optional: Panel height (default: UI.PANEL_HEIGHT)
        scrollChildHeight = 800,            -- Optional: Scroll content height (default: UI.SCROLL_CHILD_HEIGHT)
        tabs = {                            -- Required: Tab definitions
            { key = "layout", label = "Layout", builder = function(scrollChild) ... end },
            { key = "appearance", label = "Appearance", builder = function(scrollChild) ... end },
            ...
        },
        onShow = function(panel) end,       -- Optional: Called when panel shows
        onHide = function(panel) end,       -- Optional: Called when panel hides
    }
    
    @return panel frame with helper methods:
        - panel:SelectTab(tabKey)           -- Switch to a specific tab
        - panel:GetActiveTab()              -- Get current tab key
        - panel:GetTabContent(tabKey)       -- Get scrollChild for a tab
        - panel:RefreshTab(tabKey)          -- Re-run builder for a tab
        - panel.tabButtons[tabKey]          -- Access tab buttons
        - panel.tabContents[tabKey]         -- Access tab content {scrollFrame, scrollChild}
]]
function TabbedPanel:Create(options)
    local UI = EnsureUI()
    
    if not options or not options.name or not options.tabs then
        error("TabbedPanel:Create requires options.name and options.tabs")
    end
    
    local panelWidth = options.width or UI.PANEL_WIDTH or 420
    local panelHeight = options.height or UI.PANEL_HEIGHT or 600
    local scrollChildHeight = options.scrollChildHeight or UI.SCROLL_CHILD_HEIGHT or 800
    
    -- Create main panel frame
    local panel = CreateFrame("Frame", "TweaksUI_" .. options.name, UIParent, "BackdropTemplate")
    panel:SetSize(panelWidth, panelHeight)
    panel:SetBackdrop(UI.DARK_BACKDROP)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:Hide()
    
    -- Title (gold)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(options.title or options.name)
    title:SetTextColor(1, 0.82, 0)
    panel.title = title
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    -- Tab bar container
    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT", 12, UI.TAB_BAR_Y or -40)
    tabBar:SetPoint("TOPRIGHT", -12, UI.TAB_BAR_Y or -40)
    tabBar:SetHeight(UI.TAB_HEIGHT or 24)
    panel.tabBar = tabBar
    
    -- Storage for tabs
    panel.tabButtons = {}
    panel.tabContents = {}
    panel.tabBuilders = {}
    panel.activeTab = nil
    
    -- Tab selection function
    local function SelectTab(tabKey)
        -- Update button states
        for key, btn in pairs(panel.tabButtons) do
            SetTabActive(btn, key == tabKey)
        end
        
        -- Show/hide content
        for key, content in pairs(panel.tabContents) do
            content.scrollFrame:SetShown(key == tabKey)
        end
        
        panel.activeTab = tabKey
    end
    
    -- Create tabs
    local xOffset = 0
    for i, tab in ipairs(options.tabs) do
        -- Create tab button
        local btn = CreateTabButton(tabBar, tab.key, tab.label, SelectTab)
        btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
        panel.tabButtons[tab.key] = btn
        xOffset = xOffset + btn:GetWidth() + (UI.TAB_SPACING or 4)
        
        -- Create tab content (scroll frame + scroll child)
        local scrollFrame, scrollChild = CreateTabContent(panel, panelWidth, scrollChildHeight)
        panel.tabContents[tab.key] = {
            scrollFrame = scrollFrame,
            scrollChild = scrollChild,
        }
        
        -- Store builder for potential refresh
        panel.tabBuilders[tab.key] = tab.builder
        
        -- Call builder if provided
        if tab.builder then
            tab.builder(scrollChild, panel)
        end
    end
    
    -- Select first tab by default
    if options.tabs[1] then
        SelectTab(options.tabs[1].key)
    end
    
    -- Panel methods
    function panel:SelectTab(tabKey)
        if panel.tabContents[tabKey] then
            SelectTab(tabKey)
        end
    end
    
    function panel:GetActiveTab()
        return panel.activeTab
    end
    
    function panel:GetTabContent(tabKey)
        local content = panel.tabContents[tabKey]
        return content and content.scrollChild or nil
    end
    
    function panel:RefreshTab(tabKey)
        local content = panel.tabContents[tabKey]
        local builder = panel.tabBuilders[tabKey]
        if content and builder then
            -- Clear existing children (except scroll child itself)
            for _, child in pairs({content.scrollChild:GetChildren()}) do
                child:Hide()
                child:SetParent(nil)
            end
            -- Rebuild
            builder(content.scrollChild, panel)
        end
    end
    
    function panel:RefreshAllTabs()
        for tabKey, _ in pairs(panel.tabContents) do
            panel:RefreshTab(tabKey)
        end
    end
    
    -- Show/Hide callbacks
    panel:SetScript("OnShow", function(self)
        if options.onShow then options.onShow(self) end
    end)
    
    panel:SetScript("OnHide", function(self)
        if options.onHide then options.onHide(self) end
    end)
    
    return panel
end

-- ============================================================================
-- CONTROL BUILDERS (for use inside tab builders)
-- ============================================================================

--[[
    Create a gold section header
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param text string - Header text
    @return number - New Y offset after header
]]
function TabbedPanel:CreateHeader(parent, y, text)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 10, y)
    header:SetText("|cffffcc00" .. text .. "|r")
    return y - 20
end

--[[
    Create a separator line
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param width number - Optional width (default: parent width - 20)
    @return number - New Y offset after separator
]]
function TabbedPanel:CreateSeparator(parent, y, width)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 10, y)
    sep:SetSize(width or (parent:GetWidth() - 20), 1)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    return y - 15
end

--[[
    Create a checkbox with label
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param options table {
        label = "Checkbox Label",
        tooltip = "Optional tooltip text",
        get = function() return boolValue end,
        set = function(value) ... end,
        indent = false,  -- Optional: indent 20px
    }
    @return number - New Y offset after checkbox
    @return CheckButton - The checkbox frame
]]
function TabbedPanel:CreateCheckbox(parent, y, options)
    local UI = EnsureUI()
    local xOffset = options.indent and (UI.INDENT or 20) or 0
    
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 10 + xOffset, y)
    cb:SetSize(24, 24)
    
    if options.get then
        cb:SetChecked(options.get())
    end
    
    -- Label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(options.label or "")
    cb.label = label
    
    -- Tooltip
    if options.tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(options.tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    
    -- Click handler
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if options.set then
            options.set(checked)
        end
    end)
    
    return y - (UI.CHECKBOX_SPACING or 26), cb
end

--[[
    Create a dropdown menu
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param options table {
        label = "Dropdown Label",
        width = 150,
        items = {
            { value = "id1", text = "Display Text 1" },
            { value = "id2", text = "Display Text 2" },
        },
        get = function() return currentValue end,
        set = function(value) ... end,
    }
    @return number - New Y offset after dropdown
    @return Frame - The dropdown frame
]]
function TabbedPanel:CreateDropdown(parent, y, options)
    local UI = EnsureUI()
    
    -- Label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 10, y)
    label:SetText(options.label or "")
    
    -- Dropdown frame
    local dropdownName = "TweaksUI_DD_" .. (options.label or ""):gsub(" ", "") .. GetTime()
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", -6, y - 18)
    UIDropDownMenu_SetWidth(dropdown, options.width or 150)
    
    -- Get current display text
    local currentValue = options.get and options.get() or nil
    local currentText = currentValue
    if options.items then
        for _, item in ipairs(options.items) do
            if item.value == currentValue then
                currentText = item.text
                break
            end
        end
    end
    UIDropDownMenu_SetText(dropdown, currentText or "")
    
    -- Initialize
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        if not options.items then return end
        for _, item in ipairs(options.items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.checked = (options.get and options.get() == item.value)
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, item.value)
                UIDropDownMenu_SetText(dropdown, item.text)
                if options.set then
                    options.set(item.value)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    return y - (UI.DROPDOWN_SPACING or 50), dropdown
end

--[[
    Create the standard visibility section used across all modules
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param options table {
        get = function(key) return settings[key] end,  -- Get a visibility setting
        set = function(key, value) settings[key] = value end,  -- Set a visibility setting
        keys = {  -- Optional: customize which keys to use (defaults below)
            enabled = "visibilityEnabled",
            inCombat = "showInCombat",
            outOfCombat = "showOutOfCombat",
            hasTarget = "showHasTarget",
            noTarget = "showNoTarget",
            solo = "showSolo",
            inParty = "showInParty",
            inRaid = "showInRaid",
            inInstance = "showInInstance",
            inArena = "showInArena",
            inBattleground = "showInBattleground",
        },
        showFade = true,  -- Include fade settings
        fadeKeys = {
            enabled = "fadeEnabled",
            delay = "fadeDelay",
            alpha = "fadeAlpha",
        },
        onChange = function() end,  -- Called after any change
    }
    @return number - New Y offset after section
]]
function TabbedPanel:CreateVisibilitySection(parent, y, options)
    local UI = EnsureUI()
    
    -- Default key names
    local keys = options.keys or {
        enabled = "visibilityEnabled",
        inCombat = "showInCombat",
        outOfCombat = "showOutOfCombat",
        hasTarget = "showHasTarget",
        noTarget = "showNoTarget",
        solo = "showSolo",
        inParty = "showInParty",
        inRaid = "showInRaid",
        inInstance = "showInInstance",
        inArena = "showInArena",
        inBattleground = "showInBattleground",
    }
    
    local function makeSet(key)
        return function(value)
            if options.set then options.set(key, value) end
            if options.onChange then options.onChange() end
        end
    end
    
    local function makeGet(key)
        return function()
            return options.get and options.get(key)
        end
    end
    
    -- Header
    y = self:CreateHeader(parent, y, "Visibility Conditions")
    
    -- Enable toggle
    y = self:CreateCheckbox(parent, y, {
        label = "Enable Visibility Conditions",
        get = makeGet(keys.enabled),
        set = makeSet(keys.enabled),
    })
    
    -- Condition checkboxes (indented)
    local conditions = {
        { key = keys.inCombat, label = "In Combat" },
        { key = keys.outOfCombat, label = "Out of Combat" },
        { key = keys.hasTarget, label = "Has Target" },
        { key = keys.noTarget, label = "No Target" },
        { key = keys.solo, label = "Solo" },
        { key = keys.inParty, label = "In Party" },
        { key = keys.inRaid, label = "In Raid" },
        { key = keys.inInstance, label = "In Instance" },
    }
    
    -- Add Arena/BG if keys provided
    if keys.inArena then
        table.insert(conditions, { key = keys.inArena, label = "In Arena" })
    end
    if keys.inBattleground then
        table.insert(conditions, { key = keys.inBattleground, label = "In Battleground" })
    end
    
    -- OR logic note
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", 30, y)
    note:SetText("|cff888888(OR logic - shows if ANY condition is met)|r")
    y = y - 16
    
    for _, cond in ipairs(conditions) do
        y = self:CreateCheckbox(parent, y, {
            label = cond.label,
            get = makeGet(cond.key),
            set = makeSet(cond.key),
            indent = true,
        })
    end
    
    -- Fade settings (if enabled)
    if options.showFade then
        local fadeKeys = options.fadeKeys or {
            enabled = "fadeEnabled",
            delay = "fadeDelay",
            alpha = "fadeAlpha",
        }
        
        y = y - 10
        y = self:CreateHeader(parent, y, "Fade Settings")
        
        y = self:CreateCheckbox(parent, y, {
            label = "Enable Fade",
            get = makeGet(fadeKeys.enabled),
            set = makeSet(fadeKeys.enabled),
        })
        
        -- Fade Delay slider
        if TUICD.Utilities and TUICD.Utilities.CreateSliderWithInput then
            local delaySlider = TUICD.Utilities:CreateSliderWithInput(parent, {
                label = "Fade Delay (sec):",
                min = 0,
                max = 10,
                step = 0.5,
                value = options.get(fadeKeys.delay) or 2,
                isFloat = true,
                decimals = 1,
                width = 120,
                labelWidth = 110,
                valueWidth = 40,
                onValueChanged = function(value)
                    if options.set then options.set(fadeKeys.delay, value) end
                    if options.onChange then options.onChange() end
                end,
            })
            delaySlider:SetPoint("TOPLEFT", 10, y)
            y = y - 30
            
            -- Fade Alpha slider
            local alphaSlider = TUICD.Utilities:CreateSliderWithInput(parent, {
                label = "Fade Alpha:",
                min = 0,
                max = 1,
                step = 0.05,
                value = options.get(fadeKeys.alpha) or 0.3,
                isFloat = true,
                decimals = 2,
                width = 120,
                labelWidth = 110,
                valueWidth = 40,
                onValueChanged = function(value)
                    if options.set then options.set(fadeKeys.alpha, value) end
                    if options.onChange then options.onChange() end
                end,
            })
            alphaSlider:SetPoint("TOPLEFT", 10, y)
            y = y - 30
        end
    end
    
    return y
end

--[[
    Create a hint/info text line
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param text string - Hint text (will be grey)
    @param width number - Optional text width
    @return number - New Y offset after hint
]]
function TabbedPanel:CreateHint(parent, y, text, width)
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 10, y)
    hint:SetWidth(width or (parent:GetWidth() - 20))
    hint:SetJustifyH("LEFT")
    hint:SetText("|cff888888" .. text .. "|r")
    
    -- Calculate height based on text wrapping
    local textHeight = hint:GetStringHeight() or 14
    return y - textHeight - 8
end

--[[
    Create a standard button
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param options table {
        text = "Button Text",
        width = 140,
        onClick = function() end,
    }
    @return number - New Y offset after button
    @return Button - The button frame
]]
function TabbedPanel:CreateButton(parent, y, options)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", 10, y)
    btn:SetSize(options.width or 140, 26)
    btn:SetText(options.text or "Button")
    
    if options.onClick then
        btn:SetScript("OnClick", options.onClick)
    end
    
    return y - 32, btn
end

-- ============================================================================
-- UTILITY: Position panel next to hub
-- ============================================================================

function TabbedPanel:PositionNextToHub(panel, hubPanel)
    if not panel or not hubPanel then return end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", hubPanel, "TOPRIGHT", 0, 0)
end

--[[
    Create a slider with numeric input (wrapper for Utilities)
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param options table {
        label = "Slider Label:",
        min = 0,
        max = 100,
        step = 1,
        get = function() return value end,
        set = function(value) ... end,
        isFloat = false,
        decimals = 2,
        width = 140,
        labelWidth = 110,
        valueWidth = 45,
    }
    @return number - New Y offset after slider
    @return Frame - The slider container
]]
function TabbedPanel:CreateSlider(parent, y, options)
    if not TUICD.Utilities or not TUICD.Utilities.CreateSliderWithInput then
        -- Fallback if Utilities not loaded yet
        return y - 30, nil
    end
    
    local xOffset = options.indent or 0
    
    local container = TUICD.Utilities:CreateSliderWithInput(parent, {
        label = options.label,
        min = options.min or 0,
        max = options.max or 100,
        step = options.step or 1,
        value = options.get and options.get() or options.min or 0,
        isFloat = options.isFloat or false,
        decimals = options.decimals or 2,
        width = options.width or 140,
        labelWidth = options.labelWidth or 110,
        valueWidth = options.valueWidth or 45,
        onValueChanged = function(value)
            if options.set then options.set(value) end
        end,
    })
    container:SetPoint("TOPLEFT", 10 + xOffset, y)
    
    return y - 30, container
end

--[[
    Create a color picker swatch
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param options table {
        label = "Color Label",
        get = function() return {r, g, b, a} end,  -- Returns color table
        set = function(r, g, b, a) ... end,
        hasAlpha = false,  -- Include alpha channel
    }
    @return number - New Y offset after color picker
    @return Button - The color swatch button
]]
function TabbedPanel:CreateColorPicker(parent, y, options)
    -- Label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 34, y)
    label:SetText(options.label or "")
    
    -- Color swatch button
    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetPoint("TOPLEFT", 10, y - 2)
    swatch:SetSize(22, 22)
    swatch:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    
    -- Get initial color
    local color = options.get and options.get() or { r = 1, g = 1, b = 1, a = 1 }
    if type(color) == "table" then
        if color[1] then
            -- Array format {r, g, b, a}
            swatch:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
        else
            -- Table format {r=, g=, b=, a=}
            swatch:SetBackdropColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
        end
    end
    swatch:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Click to open color picker
    swatch:SetScript("OnClick", function(self)
        local currentColor = options.get and options.get() or { r = 1, g = 1, b = 1, a = 1 }
        local r, g, b, a
        if type(currentColor) == "table" then
            if currentColor[1] then
                r, g, b, a = currentColor[1], currentColor[2], currentColor[3], currentColor[4] or 1
            else
                r, g, b, a = currentColor.r or 1, currentColor.g or 1, currentColor.b or 1, currentColor.a or 1
            end
        else
            r, g, b, a = 1, 1, 1, 1
        end
        
        local info = {
            r = r, g = g, b = b,
            hasOpacity = options.hasAlpha,
            opacity = 1 - (a or 1),
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = options.hasAlpha and (1 - (ColorPickerFrame:GetColorAlpha() or 0)) or 1
                self:SetBackdropColor(nr, ng, nb, na)
                if options.set then
                    options.set(nr, ng, nb, na)
                end
            end,
            opacityFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = 1 - (ColorPickerFrame:GetColorAlpha() or 0)
                self:SetBackdropColor(nr, ng, nb, na)
                if options.set then
                    options.set(nr, ng, nb, na)
                end
            end,
            cancelFunc = function(prev)
                self:SetBackdropColor(prev.r, prev.g, prev.b, 1 - (prev.a or 0))
                -- Don't call set on cancel - revert
            end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    
    -- Update method for external changes
    function swatch:UpdateColor()
        local c = options.get and options.get() or { r = 1, g = 1, b = 1, a = 1 }
        if type(c) == "table" then
            if c[1] then
                self:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
            else
                self:SetBackdropColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
            end
        end
    end
    
    return y - 28, swatch
end

--[[
    Create a texture dropdown (using LibSharedMedia)
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param options table {
        label = "Texture Label",
        width = 150,
        get = function() return textureName end,
        set = function(textureName) ... end,
        showPreview = true,  -- Show preview bar
    }
    @return number - New Y offset after dropdown
]]
function TabbedPanel:CreateTextureDropdown(parent, y, options)
    local UI = EnsureUI()
    
    -- Label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 10, y)
    label:SetText(options.label or "")
    
    -- Dropdown
    local dropdownName = "TweaksUI_TexDD_" .. (options.label or ""):gsub(" ", "") .. GetTime()
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", -6, y - 18)
    UIDropDownMenu_SetWidth(dropdown, options.width or 150)
    UIDropDownMenu_SetText(dropdown, options.get and options.get() or "Blizzard")
    
    -- Preview bar (optional)
    local previewBar
    if options.showPreview ~= false and TUICD.Media then
        previewBar = CreateFrame("StatusBar", nil, parent)
        previewBar:SetPoint("TOPLEFT", (options.width or 150) + 30, y - 4)
        previewBar:SetSize(80, 14)
        previewBar:SetMinMaxValues(0, 1)
        previewBar:SetValue(0.7)
        local texPath = TUICD.Media:GetStatusBarTexture(options.get and options.get())
        if texPath then
            previewBar:SetStatusBarTexture(texPath)
        end
        previewBar:SetStatusBarColor(0, 0.8, 0, 1)
        
        local previewBg = previewBar:CreateTexture(nil, "BACKGROUND")
        previewBg:SetAllPoints()
        previewBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    end
    
    -- Initialize
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local textures = TUICD.Media and TUICD.Media:GetStatusBarList() or {"Blizzard"}
        for _, texName in ipairs(textures) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = texName
            info.checked = (options.get and options.get() == texName)
            info.func = function()
                UIDropDownMenu_SetText(dropdown, texName)
                if options.set then
                    options.set(texName)
                end
                -- Update preview
                if previewBar and TUICD.Media then
                    local texPath = TUICD.Media:GetStatusBarTexture(texName)
                    if texPath then
                        previewBar:SetStatusBarTexture(texPath)
                    end
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    return y - (UI.DROPDOWN_SPACING or 50), dropdown
end

--[[
    Create a font dropdown (using LibSharedMedia)
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param options table {
        label = "Font Label",
        width = 150,
        get = function() return fontName end,
        set = function(fontName) ... end,
        showPreview = true,  -- Show preview text
    }
    @return number - New Y offset after dropdown
]]
function TabbedPanel:CreateFontDropdown(parent, y, options)
    local UI = EnsureUI()
    
    -- Label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 10, y)
    label:SetText(options.label or "")
    
    -- Dropdown
    local dropdownName = "TweaksUI_FontDD_" .. (options.label or ""):gsub(" ", "") .. GetTime()
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", -6, y - 18)
    UIDropDownMenu_SetWidth(dropdown, options.width or 150)
    UIDropDownMenu_SetText(dropdown, options.get and options.get() or "Friz Quadrata TT")
    
    -- Preview text (optional)
    local previewText
    if options.showPreview ~= false and TUICD.Media then
        previewText = parent:CreateFontString(nil, "OVERLAY")
        previewText:SetPoint("TOPLEFT", (options.width or 150) + 30, y - 4)
        local fontPath = TUICD.Media:GetFont(options.get and options.get())
        if fontPath then
            previewText:SetFont(fontPath, 12, "OUTLINE")
        end
        previewText:SetText("Preview 123")
        previewText:SetTextColor(1, 1, 1, 1)
    end
    
    -- Initialize
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local fonts = TUICD.Media and TUICD.Media:GetFontList() or {"Friz Quadrata TT"}
        for _, fontName in ipairs(fonts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = fontName
            info.checked = (options.get and options.get() == fontName)
            info.func = function()
                UIDropDownMenu_SetText(dropdown, fontName)
                if options.set then
                    options.set(fontName)
                end
                -- Update preview
                if previewText and TUICD.Media then
                    local fontPath = TUICD.Media:GetFont(fontName)
                    if fontPath then
                        previewText:SetFont(fontPath, 12, "OUTLINE")
                    end
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    return y - (UI.DROPDOWN_SPACING or 50), dropdown
end

--[[
    Create an edit box for text input
    @param parent frame - Parent scroll child
    @param y number - Current Y offset
    @param options table {
        label = "EditBox Label",
        width = 150,
        get = function() return text end,
        set = function(text) ... end,
        placeholder = "Enter text...",
    }
    @return number - New Y offset after edit box
    @return EditBox - The edit box frame
]]
function TabbedPanel:CreateEditBox(parent, y, options)
    -- Label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 10, y)
    label:SetText(options.label or "")
    
    -- Edit box
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", 14, y - 18)
    editBox:SetSize(options.width or 150, 20)
    editBox:SetAutoFocus(false)
    editBox:SetText(options.get and options.get() or "")
    editBox:SetCursorPosition(0)
    
    -- Handlers
    editBox:SetScript("OnEnterPressed", function(self)
        if options.set then
            options.set(self:GetText())
        end
        self:ClearFocus()
    end)
    
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(options.get and options.get() or "")
        self:ClearFocus()
    end)
    
    editBox:SetScript("OnEditFocusLost", function(self)
        local newText = self:GetText()
        local oldText = options.get and options.get() or ""
        if newText ~= oldText then
            if options.set then
                options.set(newText)
            end
        end
    end)
    
    return y - 45, editBox
end
