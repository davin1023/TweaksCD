-- ============================================================================
-- TweaksUI: Cooldowns - Multi-Tracker Settings Panel
-- Unified settings panel for managing multiple custom trackers
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Wait for MultiTracker to be loaded
if not TUICD.MultiTracker then
    TUICD.MultiTracker = {}
end

local MultiTrackerUI = {}
TUICD.MultiTrackerUI = MultiTrackerUI

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH = 520
local PANEL_HEIGHT = 700  -- Increased to fit second row of buttons

local darkBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

-- ============================================================================
-- LOCAL VARIABLES
-- ============================================================================

local mainPanel = nil
local selectedTrackerKey = "customTrackers"  -- Default to original custom tracker
local trackerDropdown = nil
local contentContainer = nil
local tabContainer = nil
local tabButtons = {}
local contentFrames = {}
local currentTab = 1

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Deep copy utility
local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[DeepCopy(k)] = DeepCopy(v)
        end
        setmetatable(copy, DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Get setting for currently selected tracker
local function GetSetting(key)
    if selectedTrackerKey == "customTrackers" then
        -- Use original custom tracker settings
        local settings = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
        return settings and settings.customTrackers and settings.customTrackers[key]
    else
        -- Use multi-tracker settings
        return TUICD.MultiTracker:GetSetting(selectedTrackerKey, key)
    end
end

-- Set setting for currently selected tracker
local function SetSetting(key, value)
    if selectedTrackerKey == "customTrackers" then
        -- Use original custom tracker settings
        local settings = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
        if settings and settings.customTrackers then
            settings.customTrackers[key] = value
            TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, settings)
        end
    else
        -- Use multi-tracker settings
        TUICD.MultiTracker:SetSetting(selectedTrackerKey, key, value)
    end
end

-- Get entries for currently selected tracker
local function GetCurrentEntries()
    if selectedTrackerKey == "customTrackers" then
        -- Get from original custom tracker
        local specID = GetSpecializationInfo(GetSpecialization() or 1)
        if not specID then return {} end
        
        if not TweaksUI_Cooldowns_CharDB then return {} end
        if not TweaksUI_Cooldowns_CharDB.cooldowns then return {} end
        if not TweaksUI_Cooldowns_CharDB.cooldowns.customEntries then return {} end
        
        return TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] or {}
    else
        return TUICD.MultiTracker:GetEntries(selectedTrackerKey)
    end
end

-- Add entry to currently selected tracker
local function AddEntry(entryType, idOrName)
    if selectedTrackerKey == "customTrackers" then
        -- Use original AddCustomEntry (from Cooldowns.lua)
        -- This function should be exposed by the Cooldowns module
        if TUICD.Cooldowns and TUICD.Cooldowns.AddCustomEntry then
            return TUICD.Cooldowns.AddCustomEntry(entryType, idOrName)
        end
        return false, "Custom tracker API not available"
    else
        return TUICD.MultiTracker:AddEntry(selectedTrackerKey, entryType, idOrName)
    end
end

-- Remove entry from currently selected tracker
local function RemoveEntry(index)
    if selectedTrackerKey == "customTrackers" then
        -- Use original RemoveCustomEntry
        if TUICD.Cooldowns and TUICD.Cooldowns.RemoveCustomEntry then
            return TUICD.Cooldowns.RemoveCustomEntry(index)
        end
        return false, "Custom tracker API not available"
    else
        return TUICD.MultiTracker:RemoveEntry(selectedTrackerKey, index)
    end
end

-- Toggle entry enabled state
local function ToggleEntryEnabled(index, enabled)
    if selectedTrackerKey == "customTrackers" then
        if TUICD.Cooldowns and TUICD.Cooldowns.SetCustomEntryEnabled then
            TUICD.Cooldowns.SetCustomEntryEnabled(index, enabled)
            return true
        end
        return false
    else
        local entries = TUICD.MultiTracker:GetEntries(selectedTrackerKey)
        if entries[index] then
            entries[index].enabled = enabled
            TUICD.MultiTracker:RebuildTracker(selectedTrackerKey)
            return true
        end
        return false
    end
end

-- Move entry up/down
local function MoveEntry(fromIndex, toIndex)
    if selectedTrackerKey == "customTrackers" then
        if TUICD.Cooldowns and TUICD.Cooldowns.MoveCustomEntry then
            TUICD.Cooldowns.MoveCustomEntry(fromIndex, toIndex)
            return true
        end
        return false
    else
        local entries = TUICD.MultiTracker:GetEntries(selectedTrackerKey)
        if fromIndex >= 1 and fromIndex <= #entries and toIndex >= 1 and toIndex <= #entries then
            local entry = table.remove(entries, fromIndex)
            table.insert(entries, toIndex, entry)
            TUICD.MultiTracker:RebuildTracker(selectedTrackerKey)
            return true
        end
        return false
    end
end

-- Refresh tracker display
local function RefreshTrackerDisplay()
    if selectedTrackerKey == "customTrackers" then
        if TUICD.Cooldowns and TUICD.Cooldowns.RebuildCustomTrackerIcons then
            TUICD.Cooldowns:RebuildCustomTrackerIcons()
        end
    else
        TUICD.MultiTracker:RebuildTracker(selectedTrackerKey)
    end
end

-- Get display name for selected tracker
local function GetSelectedTrackerName()
    if selectedTrackerKey == "customTrackers" then
        return "Custom Trackers (Original)"
    else
        local info = TUICD.MultiTracker:GetTrackerInfo(selectedTrackerKey)
        return info and info.name or selectedTrackerKey
    end
end

-- Build tracker dropdown options
local function GetTrackerOptions()
    local options = {
        { label = "Custom Trackers (Original)", value = "customTrackers" }
    }
    
    local trackers = TUICD.MultiTracker:GetTrackerList()
    for _, tracker in ipairs(trackers) do
        table.insert(options, {
            label = tracker.name,
            value = tracker.key,
        })
    end
    
    return options
end

-- ============================================================================
-- TAB CONTENT BUILDERS
-- ============================================================================

-- Create scroll frame for tab content
local function CreateTabContent(parent)
    local content = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    content:SetAllPoints()
    content:Hide()
    
    local scrollChild = CreateFrame("Frame", nil, content)
    scrollChild:SetSize(PANEL_WIDTH - 70, 800)
    content:SetScrollChild(scrollChild)
    content.scrollChild = scrollChild
    
    return content
end

-- Shared UI creation helpers
local function CreateHeader(parent, yOffset, text)
    yOffset = yOffset - 8
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 5, yOffset)
    header:SetText(text)
    header:SetTextColor(1, 0.82, 0)
    return yOffset - 18
end

local function CreateCheckbox(parent, yOffset, text, getValue, setValue, refreshFunc)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 10, yOffset)
    cb:SetSize(24, 24)
    cb:SetChecked(getValue() or false)
    cb:SetScript("OnClick", function(self)
        setValue(self:GetChecked())
        if refreshFunc then refreshFunc() end
    end)
    
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(text)
    label:SetTextColor(0.8, 0.8, 0.8)
    
    return yOffset - 26, cb
end

local function CreateSlider(parent, yOffset, labelText, min, max, step, getValue, setValue, refreshFunc)
    local isFloat = step < 1
    local decimals = isFloat and 2 or 0
    
    if TUICD.Utilities and TUICD.Utilities.CreateSliderWithInput then
        local container = TUICD.Utilities:CreateSliderWithInput(parent, {
            label = labelText,
            min = min,
            max = max,
            step = step,
            value = getValue() or min,
            isFloat = isFloat,
            decimals = decimals,
            width = 140,
            labelWidth = 130,
            valueWidth = 45,
            onValueChanged = function(value)
                setValue(value)
                if refreshFunc then refreshFunc() end
            end,
        })
        container:SetPoint("TOPLEFT", 10, yOffset)
        return yOffset - 30, container
    else
        -- Fallback simple slider
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 10, yOffset)
        label:SetText(labelText)
        return yOffset - 30
    end
end

local function CreateDropdownControl(parent, yOffset, labelText, options, getValue, setValue, refreshFunc)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 10, yOffset)
    label:SetText(labelText)
    label:SetTextColor(0.8, 0.8, 0.8)
    
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", label, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(dropdown, 120)
    
    local function OnSelect(self, arg1)
        setValue(arg1)
        UIDropDownMenu_SetText(dropdown, self:GetText())
        if refreshFunc then refreshFunc() end
    end
    
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.func = OnSelect
            info.arg1 = opt.value
            info.checked = (getValue() == opt.value)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    local currentVal = getValue()
    for _, opt in ipairs(options) do
        if opt.value == currentVal then
            UIDropDownMenu_SetText(dropdown, opt.label)
            break
        end
    end
    
    return yOffset - 30, dropdown
end

-- ========================================
-- TAB: ENTRIES
-- ========================================
local function BuildEntriesTab(parent)
    local y = -10
    
    -- Master enable
    y = CreateHeader(parent, y, "Master Enable")
    y = CreateCheckbox(parent, y, "Enable This Tracker",
        function() return GetSetting("enabled") end,
        function(v) 
            SetSetting("enabled", v)
            RefreshTrackerDisplay()
        end,
        RefreshTrackerDisplay)
    
    -- Drop zone for adding entries
    y = y - 10
    y = CreateHeader(parent, y, "Add Entry")
    
    local dropZone = CreateFrame("Button", nil, parent, "BackdropTemplate")
    dropZone:SetPoint("TOPLEFT", 10, y)
    dropZone:SetSize(PANEL_WIDTH - 80, 45)
    dropZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    dropZone:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    dropZone:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local dropText = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dropText:SetPoint("CENTER")
    dropText:SetText("|cff888888Drop spell or item here|r")
    
    local function ProcessDrop()
        local cursorType, id, subType, spellID = GetCursorInfo()
        
        if cursorType == "spell" then
            local actualSpellID = spellID or id
            if actualSpellID then
                local success, msg = AddEntry("spell", actualSpellID)
                ClearCursor()
                if success then
                    RefreshTrackerDisplay()
                    if mainPanel.RefreshEntriesList then
                        mainPanel:RefreshEntriesList()
                    end
                    dropText:SetText("|cff00ff00Added!|r")
                    C_Timer.After(1.5, function()
                        dropText:SetText("|cff888888Drop spell or item here|r")
                    end)
                end
                return true
            end
        elseif cursorType == "item" then
            local itemID = id
            if itemID then
                local success, msg = AddEntry("item", itemID)
                ClearCursor()
                if success then
                    RefreshTrackerDisplay()
                    if mainPanel.RefreshEntriesList then
                        mainPanel:RefreshEntriesList()
                    end
                    dropText:SetText("|cff00ff00Added!|r")
                    C_Timer.After(1.5, function()
                        dropText:SetText("|cff888888Drop spell or item here|r")
                    end)
                end
                return true
            end
        end
        ClearCursor()
        return false
    end
    
    dropZone:SetScript("OnReceiveDrag", ProcessDrop)
    dropZone:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and GetCursorInfo() then
            ProcessDrop()
        end
    end)
    
    dropZone:SetScript("OnEnter", function(self)
        if GetCursorInfo() then
            self:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
            dropText:SetText("|cff00ff00Release to add!|r")
        else
            self:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        end
    end)
    
    dropZone:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        dropText:SetText("|cff888888Drop spell or item here|r")
    end)
    
    y = y - 55
    
    -- Manual entry
    local typeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLabel:SetPoint("TOPLEFT", 10, y)
    typeLabel:SetText("Manual:")
    typeLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local typeDropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    typeDropdown:SetPoint("LEFT", typeLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(typeDropdown, 65)
    
    local selectedType = "spell"
    UIDropDownMenu_Initialize(typeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Spell"
        info.value = "spell"
        info.func = function() selectedType = "spell"; UIDropDownMenu_SetText(typeDropdown, "Spell") end
        info.checked = (selectedType == "spell")
        UIDropDownMenu_AddButton(info, level)
        
        info = UIDropDownMenu_CreateInfo()
        info.text = "Item"
        info.value = "item"
        info.func = function() selectedType = "item"; UIDropDownMenu_SetText(typeDropdown, "Item") end
        info.checked = (selectedType == "item")
        UIDropDownMenu_AddButton(info, level)
    end)
    UIDropDownMenu_SetText(typeDropdown, "Spell")
    
    local idInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    idInput:SetPoint("LEFT", typeDropdown, "RIGHT", 0, 2)
    idInput:SetSize(70, 20)
    idInput:SetAutoFocus(false)
    idInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    
    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetPoint("LEFT", idInput, "RIGHT", 3, 0)
    addBtn:SetSize(45, 20)
    addBtn:SetText("Add")
    
    addBtn:SetScript("OnClick", function()
        local input = idInput:GetText():trim()
        if input == "" then return end
        
        local success, msg = AddEntry(selectedType, input)
        if success then
            idInput:SetText("")
            RefreshTrackerDisplay()
            if mainPanel.RefreshEntriesList then
                mainPanel:RefreshEntriesList()
            end
        end
    end)
    
    idInput:SetScript("OnEnterPressed", function(self)
        addBtn:Click()
        self:ClearFocus()
    end)
    
    y = y - 35
    
    -- Entries list
    y = y - 10
    y = CreateHeader(parent, y, "Tracked Entries (This Spec)")
    
    local helpText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpText:SetPoint("TOPLEFT", 10, y)
    helpText:SetText("|cff888888Check to enable, X to remove|r")
    y = y - 14
    
    local entriesContainer = CreateFrame("Frame", nil, parent)
    entriesContainer:SetPoint("TOPLEFT", 10, y)
    entriesContainer:SetSize(PANEL_WIDTH - 80, 300)
    
    local entryElements = {}
    
    -- Refresh entries list
    function mainPanel:RefreshEntriesList()
        for _, elem in ipairs(entryElements) do
            if elem.Hide then elem:Hide() end
            if elem.SetParent then elem:SetParent(nil) end
        end
        wipe(entryElements)
        
        local entryY = 0
        local entries = GetCurrentEntries()
        
        if #entries == 0 then
            local noEntries = entriesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noEntries:SetPoint("TOPLEFT", 0, 0)
            noEntries:SetText("|cff666666No entries. Drop spells or items above to add.|r")
            table.insert(entryElements, noEntries)
            return
        end
        
        for i, entry in ipairs(entries) do
            local displayName = "Unknown"
            local displayTexture = nil
            local typeColor = "|cff888888"
            
            if entry.type == "spell" then
                local spellInfo = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellInfo(entry.id)
                displayName = spellInfo and spellInfo.name or ("Spell " .. entry.id)
                displayTexture = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellTexture(entry.id)
                typeColor = "|cff71d5ff"  -- Blue for spells
            elseif entry.type == "item" then
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(entry.id)
                displayName = itemName or ("Item " .. entry.id)
                displayTexture = itemTexture
                typeColor = "|cff00ff00"  -- Green for items
            elseif entry.type == "equipped" then
                -- Equipment slot
                local slotID = entry.id
                local itemID = GetInventoryItemID("player", slotID)
                if itemID then
                    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                    displayName = itemName or ("Slot " .. slotID)
                    displayTexture = itemTexture or GetInventoryItemTexture("player", slotID)
                else
                    displayName = "Empty Slot " .. slotID
                    displayTexture = GetInventoryItemTexture("player", slotID)
                end
                typeColor = "|cffa335ee"  -- Purple for equipped
            end
            
            local isEnabled = entry.enabled ~= false
            
            local row = CreateFrame("Frame", nil, entriesContainer)
            row:SetPoint("TOPLEFT", 0, entryY)
            row:SetSize(PANEL_WIDTH - 100, 24)
            table.insert(entryElements, row)
            
            -- Enable checkbox
            local enableCB = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            enableCB:SetPoint("LEFT", 0, 0)
            enableCB:SetSize(18, 18)
            enableCB:SetChecked(isEnabled)
            enableCB:SetScript("OnClick", function(self)
                ToggleEntryEnabled(i, self:GetChecked())
                RefreshTrackerDisplay()
            end)
            
            -- Icon
            if displayTexture then
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("LEFT", enableCB, "RIGHT", 4, 0)
                icon:SetSize(18, 18)
                icon:SetTexture(displayTexture)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            
            -- Name
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", enableCB, "RIGHT", displayTexture and 26 or 4, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -60, 0)
            label:SetJustifyH("LEFT")
            label:SetText(string.format("%s[%s]|r %s", typeColor, entry.type, displayName))
            label:SetWordWrap(false)
            
            -- Move up
            local upBtn = CreateFrame("Button", nil, row)
            upBtn:SetPoint("RIGHT", row, "RIGHT", -30, 0)
            upBtn:SetSize(14, 14)
            upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
            upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
            upBtn:SetEnabled(i > 1)
            upBtn:SetAlpha(i > 1 and 1 or 0.3)
            upBtn:SetScript("OnClick", function()
                MoveEntry(i, i - 1)
                mainPanel:RefreshEntriesList()
            end)
            
            -- Move down
            local downBtn = CreateFrame("Button", nil, row)
            downBtn:SetPoint("RIGHT", row, "RIGHT", -15, 0)
            downBtn:SetSize(14, 14)
            downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
            downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
            downBtn:SetEnabled(i < #entries)
            downBtn:SetAlpha(i < #entries and 1 or 0.3)
            downBtn:SetScript("OnClick", function()
                MoveEntry(i, i + 1)
                mainPanel:RefreshEntriesList()
            end)
            
            -- Remove button
            local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            removeBtn:SetSize(20, 18)
            removeBtn:SetText("X")
            removeBtn:SetScript("OnClick", function()
                RemoveEntry(i)
                RefreshTrackerDisplay()
                mainPanel:RefreshEntriesList()
            end)
            
            entryY = entryY - 26
        end
    end
    
    parent:SetHeight(math.abs(y) + 350)
end

-- ========================================
-- TAB: LAYOUT
-- ========================================
local function BuildLayoutTab(parent)
    local y = -10
    
    y = CreateHeader(parent, y, "Icon Size")
    y = CreateSlider(parent, y, "Base Size", 16, 80, 1,
        function() return GetSetting("iconSize") end,
        function(v) SetSetting("iconSize", v) end,
        RefreshTrackerDisplay)
    
    local aspectOptions = {
        { label = "1:1 (Square)", value = "1:1" },
        { label = "4:3", value = "4:3" },
        { label = "3:4", value = "3:4" },
        { label = "16:9 (Wide)", value = "16:9" },
        { label = "9:16 (Tall)", value = "9:16" },
    }
    y = CreateDropdownControl(parent, y, "Aspect Ratio", aspectOptions,
        function() return GetSetting("aspectRatio") or "1:1" end,
        function(v) SetSetting("aspectRatio", v) end,
        RefreshTrackerDisplay)
    
    y = y - 10
    y = CreateHeader(parent, y, "Grid Layout")
    y = CreateSlider(parent, y, "Columns", 1, 20, 1,
        function() return GetSetting("columns") end,
        function(v) SetSetting("columns", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "Rows (0=auto)", 0, 20, 1,
        function() return GetSetting("rows") end,
        function(v) SetSetting("rows", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "H Spacing", 0, 20, 1,
        function() return GetSetting("spacingH") end,
        function(v) SetSetting("spacingH", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "V Spacing", 0, 20, 1,
        function() return GetSetting("spacingV") end,
        function(v) SetSetting("spacingV", v) end,
        RefreshTrackerDisplay)
    
    local growOptions = {
        { label = "Right", value = "RIGHT" },
        { label = "Left", value = "LEFT" },
        { label = "Up", value = "UP" },
        { label = "Down", value = "DOWN" },
    }
    y = y - 5
    y = CreateDropdownControl(parent, y, "Grow Direction", growOptions,
        function() return GetSetting("growDirection") or "RIGHT" end,
        function(v) SetSetting("growDirection", v) end,
        RefreshTrackerDisplay)
    
    y = CreateDropdownControl(parent, y, "Secondary", growOptions,
        function() return GetSetting("growSecondary") or "DOWN" end,
        function(v) SetSetting("growSecondary", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Reverse Order",
        function() return GetSetting("reverseOrder") end,
        function(v) SetSetting("reverseOrder", v) end,
        RefreshTrackerDisplay)
    
    parent:SetHeight(math.abs(y) + 20)
end

-- ========================================
-- TAB: APPEARANCE
-- ========================================
local function BuildAppearanceTab(parent)
    local y = -10
    
    y = CreateHeader(parent, y, "Icon Appearance")
    y = CreateSlider(parent, y, "Zoom", 0, 0.3, 0.01,
        function() return GetSetting("zoom") end,
        function(v) SetSetting("zoom", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "Border Alpha", 0, 1, 0.1,
        function() return GetSetting("borderAlpha") end,
        function(v) SetSetting("borderAlpha", v) end,
        RefreshTrackerDisplay)
    
    local edgeOptions = {
        { label = "Sharp", value = "sharp" },
        { label = "Rounded", value = "rounded" },
        { label = "Square", value = "square" },
    }
    y = CreateDropdownControl(parent, y, "Edge Style", edgeOptions,
        function() return GetSetting("iconEdgeStyle") or "sharp" end,
        function(v) SetSetting("iconEdgeStyle", v) end,
        RefreshTrackerDisplay)
    
    y = y - 10
    y = CreateHeader(parent, y, "Opacity")
    y = CreateSlider(parent, y, "Out of Combat", 0, 1, 0.05,
        function() return GetSetting("iconOpacity") end,
        function(v) SetSetting("iconOpacity", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "In Combat", 0, 1, 0.05,
        function() return GetSetting("iconOpacityCombat") end,
        function(v) SetSetting("iconOpacityCombat", v) end,
        RefreshTrackerDisplay)
    
    y = y - 10
    y = CreateHeader(parent, y, "Usability States")
    
    y = CreateCheckbox(parent, y, "Tint When Unusable  |cff888888(not enough resources)|r",
        function() return GetSetting("showUnusableState") end,
        function(v) SetSetting("showUnusableState", v) end,
        RefreshTrackerDisplay)
    
    -- Unusable color picker
    local unusableColorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unusableColorLabel:SetPoint("TOPLEFT", 35, y)
    unusableColorLabel:SetText("Unusable Tint Color:")
    
    local unusableColorSwatch = CreateFrame("Button", nil, parent)
    unusableColorSwatch:SetPoint("LEFT", unusableColorLabel, "RIGHT", 10, 0)
    unusableColorSwatch:SetSize(24, 24)
    
    local unusableBorder = unusableColorSwatch:CreateTexture(nil, "BACKGROUND")
    unusableBorder:SetPoint("TOPLEFT", -2, 2)
    unusableBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    unusableBorder:SetColorTexture(0.5, 0.5, 0.5, 1)
    
    local unusableTex = unusableColorSwatch:CreateTexture(nil, "ARTWORK")
    unusableTex:SetAllPoints()
    unusableColorSwatch.tex = unusableTex
    
    local function UpdateUnusableSwatchColor()
        local r = GetSetting("unusableColorR") or 0.0
        local g = GetSetting("unusableColorG") or 0.0
        local b = GetSetting("unusableColorB") or 0.0
        unusableTex:SetColorTexture(r, g, b, 1)
    end
    UpdateUnusableSwatchColor()
    
    unusableColorSwatch:SetScript("OnClick", function()
        local r = GetSetting("unusableColorR") or 0.0
        local g = GetSetting("unusableColorG") or 0.0
        local b = GetSetting("unusableColorB") or 0.0
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                SetSetting("unusableColorR", nr)
                SetSetting("unusableColorG", ng)
                SetSetting("unusableColorB", nb)
                UpdateUnusableSwatchColor()
                -- Rebuild icons to apply new overlay color
                if TUICD.MultiTrackerFrames then
                    TUICD.MultiTrackerFrames:BuildTrackerDisplay(selectedTrackerKey)
                end
            end,
            cancelFunc = function(prev)
                SetSetting("unusableColorR", prev.r)
                SetSetting("unusableColorG", prev.g)
                SetSetting("unusableColorB", prev.b)
                UpdateUnusableSwatchColor()
                if TUICD.MultiTrackerFrames then
                    TUICD.MultiTrackerFrames:BuildTrackerDisplay(selectedTrackerKey)
                end
            end,
        })
    end)
    
    y = y - 30
    
    y = CreateCheckbox(parent, y, "Tint When Out of Range  |cff888888(target out of range)|r",
        function() return GetSetting("showOutOfRange") end,
        function(v) SetSetting("showOutOfRange", v) end,
        RefreshTrackerDisplay)
    
    -- Range color picker (only show if showOutOfRange is enabled)
    local rangeColorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rangeColorLabel:SetPoint("TOPLEFT", 35, y)
    rangeColorLabel:SetText("Range Tint Color:")
    
    local rangeColorSwatch = CreateFrame("Button", nil, parent)
    rangeColorSwatch:SetPoint("LEFT", rangeColorLabel, "RIGHT", 10, 0)
    rangeColorSwatch:SetSize(24, 24)
    
    local rangeBorder = rangeColorSwatch:CreateTexture(nil, "BACKGROUND")
    rangeBorder:SetPoint("TOPLEFT", -2, 2)
    rangeBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    rangeBorder:SetColorTexture(0.5, 0.5, 0.5, 1)
    
    local rangeTex = rangeColorSwatch:CreateTexture(nil, "ARTWORK")
    rangeTex:SetAllPoints()
    rangeColorSwatch.tex = rangeTex
    
    local function UpdateRangeSwatchColor()
        local r = GetSetting("outOfRangeColorR") or 1.0
        local g = GetSetting("outOfRangeColorG") or 0.3
        local b = GetSetting("outOfRangeColorB") or 0.3
        rangeTex:SetColorTexture(r, g, b, 1)
    end
    UpdateRangeSwatchColor()
    
    rangeColorSwatch:SetScript("OnClick", function()
        local r = GetSetting("outOfRangeColorR") or 1.0
        local g = GetSetting("outOfRangeColorG") or 0.3
        local b = GetSetting("outOfRangeColorB") or 0.3
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                SetSetting("outOfRangeColorR", nr)
                SetSetting("outOfRangeColorG", ng)
                SetSetting("outOfRangeColorB", nb)
                UpdateRangeSwatchColor()
                -- Rebuild icons to apply new overlay color
                if TUICD.MultiTrackerFrames then
                    TUICD.MultiTrackerFrames:BuildTrackerDisplay(selectedTrackerKey)
                end
            end,
            cancelFunc = function(prev)
                SetSetting("outOfRangeColorR", prev.r)
                SetSetting("outOfRangeColorG", prev.g)
                SetSetting("outOfRangeColorB", prev.b)
                UpdateRangeSwatchColor()
                if TUICD.MultiTrackerFrames then
                    TUICD.MultiTrackerFrames:BuildTrackerDisplay(selectedTrackerKey)
                end
            end,
        })
    end)
    
    y = y - 30
    
    y = y - 10
    y = CreateHeader(parent, y, "Cooldown Display")
    y = CreateCheckbox(parent, y, "Hide Cooldown Sweep",
        function() return GetSetting("hideSweep") end,
        function(v) SetSetting("hideSweep", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Show Tooltips",
        function() return GetSetting("showTooltip") end,
        function(v) SetSetting("showTooltip", v) end,
        RefreshTrackerDisplay)
    
    y = y - 10
    y = CreateHeader(parent, y, "Charge Display")
    
    y = CreateCheckbox(parent, y, "Show Charge Count  |cff888888(charge-based spells)|r",
        function() return GetSetting("showChargeCount") ~= false end,
        function(v) SetSetting("showChargeCount", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "Charge Font Size", 8, 20, 1,
        function() return GetSetting("chargeCountFontSize") or 12 end,
        function(v) SetSetting("chargeCountFontSize", v) end,
        RefreshTrackerDisplay)
    
    -- Charge count color picker
    local chargeColorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chargeColorLabel:SetPoint("TOPLEFT", 35, y)
    chargeColorLabel:SetText("Count Color:")
    
    local chargeColorSwatch = CreateFrame("Button", nil, parent)
    chargeColorSwatch:SetPoint("LEFT", chargeColorLabel, "RIGHT", 10, 0)
    chargeColorSwatch:SetSize(24, 24)
    
    local chargeBorder = chargeColorSwatch:CreateTexture(nil, "BACKGROUND")
    chargeBorder:SetPoint("TOPLEFT", -2, 2)
    chargeBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    chargeBorder:SetColorTexture(0.5, 0.5, 0.5, 1)
    
    local chargeTex = chargeColorSwatch:CreateTexture(nil, "ARTWORK")
    chargeTex:SetAllPoints()
    chargeColorSwatch.tex = chargeTex
    
    local function UpdateChargeSwatchColor()
        local r = GetSetting("chargeCountColorR") or 1.0
        local g = GetSetting("chargeCountColorG") or 1.0
        local b = GetSetting("chargeCountColorB") or 1.0
        chargeTex:SetColorTexture(r, g, b, 1)
    end
    UpdateChargeSwatchColor()
    
    chargeColorSwatch:SetScript("OnClick", function()
        local r = GetSetting("chargeCountColorR") or 1.0
        local g = GetSetting("chargeCountColorG") or 1.0
        local b = GetSetting("chargeCountColorB") or 1.0
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                SetSetting("chargeCountColorR", nr)
                SetSetting("chargeCountColorG", ng)
                SetSetting("chargeCountColorB", nb)
                UpdateChargeSwatchColor()
                RefreshTrackerDisplay()
            end,
            cancelFunc = function(prev)
                SetSetting("chargeCountColorR", prev.r)
                SetSetting("chargeCountColorG", prev.g)
                SetSetting("chargeCountColorB", prev.b)
                UpdateChargeSwatchColor()
                RefreshTrackerDisplay()
            end,
        })
    end)
    y = y - 30
    
    y = CreateCheckbox(parent, y, "Desaturate at Zero Charges  |cff888888(grey out when spent)|r",
        function() return GetSetting("desaturateAtZeroCharges") ~= false end,
        function(v) SetSetting("desaturateAtZeroCharges", v) end,
        RefreshTrackerDisplay)
    
    y = y - 10
    y = CreateHeader(parent, y, "Proc Glow")
    
    y = CreateCheckbox(parent, y, "Show Proc Glow  |cff888888(highlight on proc)|r",
        function() return GetSetting("showProcGlow") ~= false end,
        function(v) SetSetting("showProcGlow", v) end,
        RefreshTrackerDisplay)
    
    local glowStyleOptions = {
        { label = "Blizzard Glow", value = "blizzard" },
        { label = "Pixel Border", value = "pixel" },
        { label = "Shine Flash", value = "shine" },
    }
    y = CreateDropdownControl(parent, y, "Glow Style", glowStyleOptions,
        function() return GetSetting("procGlowStyle") or "blizzard" end,
        function(v) SetSetting("procGlowStyle", v) end,
        RefreshTrackerDisplay)
    
    -- Proc glow color picker (primarily for pixel/shine styles)
    local procColorLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    procColorLabel:SetPoint("TOPLEFT", 35, y)
    procColorLabel:SetText("Glow Color:")
    
    local procColorSwatch = CreateFrame("Button", nil, parent)
    procColorSwatch:SetPoint("LEFT", procColorLabel, "RIGHT", 10, 0)
    procColorSwatch:SetSize(24, 24)
    
    local procBorder = procColorSwatch:CreateTexture(nil, "BACKGROUND")
    procBorder:SetPoint("TOPLEFT", -2, 2)
    procBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    procBorder:SetColorTexture(0.5, 0.5, 0.5, 1)
    
    local procTex = procColorSwatch:CreateTexture(nil, "ARTWORK")
    procTex:SetAllPoints()
    procColorSwatch.tex = procTex
    
    local function UpdateProcSwatchColor()
        local r = GetSetting("procGlowColorR") or 1.0
        local g = GetSetting("procGlowColorG") or 0.82
        local b = GetSetting("procGlowColorB") or 0.0
        procTex:SetColorTexture(r, g, b, 1)
    end
    UpdateProcSwatchColor()
    
    procColorSwatch:SetScript("OnClick", function()
        local r = GetSetting("procGlowColorR") or 1.0
        local g = GetSetting("procGlowColorG") or 0.82
        local b = GetSetting("procGlowColorB") or 0.0
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                SetSetting("procGlowColorR", nr)
                SetSetting("procGlowColorG", ng)
                SetSetting("procGlowColorB", nb)
                UpdateProcSwatchColor()
                RefreshTrackerDisplay()
            end,
            cancelFunc = function(prev)
                SetSetting("procGlowColorR", prev.r)
                SetSetting("procGlowColorG", prev.g)
                SetSetting("procGlowColorB", prev.b)
                UpdateProcSwatchColor()
                RefreshTrackerDisplay()
            end,
        })
    end)
    
    local procColorHint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    procColorHint:SetPoint("LEFT", procColorSwatch, "RIGHT", 10, 0)
    procColorHint:SetText("|cff888888(for Pixel / Shine styles)|r")
    y = y - 30
    
    y = y - 10
    y = CreateHeader(parent, y, "Interaction")
    
    y = CreateCheckbox(parent, y, "Clickthrough (ignore mouse)",
        function() return GetSetting("clickthrough") or false end,
        function(v) 
            SetSetting("clickthrough", v)
            -- Apply immediately to all icons
            if TUICD.MultiTrackerFrames and TUICD.MultiTrackerFrames.ApplyClickthrough then
                TUICD.MultiTrackerFrames:ApplyClickthrough(currentTrackerKey)
            end
        end,
        RefreshTrackerDisplay)
    
    parent:SetHeight(math.abs(y) + 20)
end

-- ========================================
-- TAB: TEXT
-- ========================================
local function BuildTextTab(parent)
    local y = -10
    
    y = CreateHeader(parent, y, "Cooldown Text")
    y = CreateCheckbox(parent, y, "Show Countdown",
        function() return GetSetting("showCountdownText") end,
        function(v) SetSetting("showCountdownText", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "Text Scale", 0.5, 2, 0.1,
        function() return GetSetting("cooldownTextScale") end,
        function(v) SetSetting("cooldownTextScale", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "X Offset", -20, 20, 1,
        function() return GetSetting("cooldownTextOffsetX") end,
        function(v) SetSetting("cooldownTextOffsetX", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "Y Offset", -20, 20, 1,
        function() return GetSetting("cooldownTextOffsetY") end,
        function(v) SetSetting("cooldownTextOffsetY", v) end,
        RefreshTrackerDisplay)
    
    y = y - 10
    y = CreateHeader(parent, y, "Stack Count Text")
    y = CreateSlider(parent, y, "Count Scale", 0.5, 2, 0.1,
        function() return GetSetting("countTextScale") end,
        function(v) SetSetting("countTextScale", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "Count X Offset", -20, 20, 1,
        function() return GetSetting("countTextOffsetX") end,
        function(v) SetSetting("countTextOffsetX", v) end,
        RefreshTrackerDisplay)
    
    y = CreateSlider(parent, y, "Count Y Offset", -20, 20, 1,
        function() return GetSetting("countTextOffsetY") end,
        function(v) SetSetting("countTextOffsetY", v) end,
        RefreshTrackerDisplay)
    
    parent:SetHeight(math.abs(y) + 20)
end

-- ========================================
-- TAB: VISIBILITY
-- ========================================
local function BuildVisibilityTab(parent)
    local y = -10
    
    y = CreateHeader(parent, y, "Visibility Conditions")
    y = CreateCheckbox(parent, y, "Enable Visibility Rules",
        function() return GetSetting("visibilityEnabled") end,
        function(v) SetSetting("visibilityEnabled", v) end,
        RefreshTrackerDisplay)
    
    y = y - 5
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 35, y)
    hint:SetText("|cff888888When enabled, tracker only shows in checked situations:|r")
    y = y - 18
    
    y = CreateCheckbox(parent, y, "Show In Combat",
        function() return GetSetting("showInCombat") end,
        function(v) SetSetting("showInCombat", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Show Out of Combat",
        function() return GetSetting("showOutOfCombat") end,
        function(v) SetSetting("showOutOfCombat", v) end,
        RefreshTrackerDisplay)
    
    y = y - 10
    y = CreateHeader(parent, y, "Group Type")
    y = CreateCheckbox(parent, y, "Show Solo",
        function() return GetSetting("showSolo") end,
        function(v) SetSetting("showSolo", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Show in Party",
        function() return GetSetting("showInParty") end,
        function(v) SetSetting("showInParty", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Show in Raid",
        function() return GetSetting("showInRaid") end,
        function(v) SetSetting("showInRaid", v) end,
        RefreshTrackerDisplay)
    
    y = y - 10
    y = CreateHeader(parent, y, "Instance Type")
    y = CreateCheckbox(parent, y, "Show in Arena",
        function() return GetSetting("showInArena") end,
        function(v) SetSetting("showInArena", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Show in Battleground",
        function() return GetSetting("showInBattleground") end,
        function(v) SetSetting("showInBattleground", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Show in Dungeon",
        function() return GetSetting("showInDungeon") end,
        function(v) SetSetting("showInDungeon", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Show in Delve",
        function() return GetSetting("showInDelve") end,
        function(v) SetSetting("showInDelve", v) end,
        RefreshTrackerDisplay)
    
    y = y - 10
    y = CreateHeader(parent, y, "Target / Mount")
    y = CreateCheckbox(parent, y, "Has Target",
        function() return GetSetting("showHasTarget") end,
        function(v) SetSetting("showHasTarget", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "No Target",
        function() return GetSetting("showNoTarget") end,
        function(v) SetSetting("showNoTarget", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Mounted",
        function() return GetSetting("showMounted") end,
        function(v) SetSetting("showMounted", v) end,
        RefreshTrackerDisplay)
    
    y = CreateCheckbox(parent, y, "Not Mounted",
        function() return GetSetting("showNotMounted") end,
        function(v) SetSetting("showNotMounted", v) end,
        RefreshTrackerDisplay)
    
    parent:SetHeight(math.abs(y) + 20)
end

-- ========================================
-- TAB: PER-ICON (Placeholder)
-- ========================================
local function BuildPerIconTab(parent)
    -- The main Cooldowns module's Per-Icon tab now shows icons from ALL custom trackers
    -- (both original and multi-trackers), so we always delegate to it
    if TUICD.Cooldowns and TUICD.Cooldowns.BuildPerIconTab then
        TUICD.Cooldowns:BuildPerIconTab(parent, "custom")
        return
    else
        local y = -10
        y = CreateHeader(parent, y, "Individual Icon Settings")
        local note = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        note:SetPoint("TOPLEFT", 10, y)
        note:SetWidth(PANEL_WIDTH - 100)
        note:SetText("|cffff8888Per-icon settings require the Cooldowns module to be loaded.|r")
        note:SetJustifyH("LEFT")
        note:SetWordWrap(true)
        parent:SetHeight(100)
        return
    end
end

-- ============================================================================
-- MAIN PANEL CREATION
-- ============================================================================

local PANEL_VERSION = "3.0.39"  -- Increment this to force panel rebuild

function MultiTrackerUI:CreatePanel()
    -- Check if panel needs rebuild due to version change
    if mainPanel then
        if mainPanel.panelVersion == PANEL_VERSION then
            return mainPanel
        else
            -- Version changed, destroy old panel
            print("|cff00ccff[TUI:CD]|r Rebuilding Custom Tracker panel for version " .. PANEL_VERSION)
            mainPanel:Hide()
            mainPanel:SetParent(nil)
            mainPanel = nil
            contentFrames = {}
            tabButtons = {}
        end
    end
    
    print("|cff00ccff[TUI:CD]|r Creating Custom Tracker panel v" .. PANEL_VERSION)
    
    -- Create main frame
    mainPanel = CreateFrame("Frame", "TweaksUI_MultiTrackerPanel", UIParent, "BackdropTemplate")
    mainPanel.panelVersion = PANEL_VERSION
    mainPanel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    mainPanel:SetPoint("CENTER", 0, 0)
    mainPanel:SetBackdrop(darkBackdrop)
    mainPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    mainPanel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    mainPanel:SetFrameStrata("DIALOG")
    mainPanel:SetMovable(true)
    mainPanel:SetClampedToScreen(true)
    mainPanel:EnableMouse(true)
    mainPanel:RegisterForDrag("LeftButton")
    mainPanel:SetScript("OnDragStart", mainPanel.StartMoving)
    mainPanel:SetScript("OnDragStop", mainPanel.StopMovingOrSizing)
    mainPanel:Hide()
    
    tinsert(UISpecialFrames, "TweaksUI_MultiTrackerPanel")
    
    -- Title
    local title = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Multi-Tracker Settings")
    title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, mainPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() mainPanel:Hide() end)
    
    -- ========================================
    -- TRACKER SELECTION HEADER
    -- ========================================
    
    local headerFrame = CreateFrame("Frame", nil, mainPanel)
    headerFrame:SetPoint("TOPLEFT", 15, -40)
    headerFrame:SetPoint("TOPRIGHT", -15, -40)
    headerFrame:SetHeight(80)  -- Increased to fit two rows of buttons
    
    -- Tracker dropdown label
    local selectLabel = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectLabel:SetPoint("TOPLEFT", 0, 0)
    selectLabel:SetText("Select Tracker:")
    selectLabel:SetTextColor(0.8, 0.8, 0.8)
    
    -- Tracker dropdown
    trackerDropdown = CreateFrame("Frame", "TweaksUI_MultiTrackerDropdown", headerFrame, "UIDropDownMenuTemplate")
    trackerDropdown:SetPoint("LEFT", selectLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(trackerDropdown, 180)
    
    local function RefreshDropdown()
        UIDropDownMenu_Initialize(trackerDropdown, function(self, level)
            local options = GetTrackerOptions()
            for _, opt in ipairs(options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.func = function(self)
                    selectedTrackerKey = self.value
                    UIDropDownMenu_SetText(trackerDropdown, opt.label)
                    MultiTrackerUI:RefreshContent()
                end
                info.checked = (selectedTrackerKey == opt.value)
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        UIDropDownMenu_SetText(trackerDropdown, GetSelectedTrackerName())
    end
    
    mainPanel.RefreshDropdown = RefreshDropdown
    
    -- Create New button
    local newBtn = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    newBtn:SetPoint("LEFT", trackerDropdown, "RIGHT", 5, 2)
    newBtn:SetSize(60, 22)
    newBtn:SetText("New")
    newBtn:SetScript("OnClick", function()
        if not TUICD.MultiTracker:CanCreateTracker() then
            TUICD:Print("Maximum number of trackers reached (10)")
            return
        end
        
        -- Simple popup for name
        StaticPopupDialogs["TUICD_NEW_TRACKER"] = {
            text = "Enter name for new tracker:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            editBoxWidth = 200,
            OnAccept = function(self)
                local name = self.EditBox:GetText():trim()
                if name == "" then name = nil end
                local key = TUICD.MultiTracker:CreateTracker(name)
                if key then
                    selectedTrackerKey = key
                    RefreshDropdown()
                    MultiTrackerUI:RefreshContent()
                end
            end,
            OnShow = function(self)
                self.EditBox:SetText("")
                self.EditBox:SetFocus()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("TUICD_NEW_TRACKER")
    end)
    newBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Create New Tracker")
        GameTooltip:AddLine(string.format("You can have up to 10 custom trackers.\nCurrently: %d/10", TUICD.MultiTracker:GetTrackerCount()), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    newBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Delete button
    local deleteBtn = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    deleteBtn:SetPoint("LEFT", newBtn, "RIGHT", 5, 0)
    deleteBtn:SetSize(60, 22)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        if selectedTrackerKey == "customTrackers" then
            TUICD:Print("Cannot delete the original Custom Tracker")
            return
        end
        
        local name = GetSelectedTrackerName()
        StaticPopupDialogs["TUICD_DELETE_TRACKER"] = {
            text = string.format("Delete tracker '%s'?\n\nThis cannot be undone.", name),
            button1 = "Delete",
            button2 = "Cancel",
            OnAccept = function()
                TUICD.MultiTracker:DeleteTracker(selectedTrackerKey)
                selectedTrackerKey = "customTrackers"
                RefreshDropdown()
                MultiTrackerUI:RefreshContent()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("TUICD_DELETE_TRACKER")
    end)
    
    -- Rename button (second row)
    local renameBtn = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    renameBtn:SetPoint("TOPLEFT", trackerDropdown, "BOTTOMLEFT", 16, -5)
    renameBtn:SetSize(70, 22)
    renameBtn:SetText("Rename")
    renameBtn:SetScript("OnClick", function()
        if selectedTrackerKey == "customTrackers" then
            TUICD:Print("Cannot rename the original Custom Tracker")
            return
        end
        
        local currentName = GetSelectedTrackerName()
        StaticPopupDialogs["TUICD_RENAME_TRACKER"] = {
            text = "Enter new name:",
            button1 = "Rename",
            button2 = "Cancel",
            hasEditBox = true,
            editBoxWidth = 200,
            OnAccept = function(self)
                local newName = self.EditBox:GetText():trim()
                if newName ~= "" then
                    TUICD.MultiTracker:RenameTracker(selectedTrackerKey, newName)
                    RefreshDropdown()
                end
            end,
            OnShow = function(self)
                self.EditBox:SetText(currentName)
                self.EditBox:HighlightText()
                self.EditBox:SetFocus()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("TUICD_RENAME_TRACKER")
    end)
    
    -- Scan CDM button (rescan Essential and Utility cooldowns from Blizzard's Cooldown Manager)
    local scanCDMBtn = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    scanCDMBtn:SetPoint("LEFT", renameBtn, "RIGHT", 10, 0)
    scanCDMBtn:SetSize(85, 22)
    scanCDMBtn:SetText("Scan CDM")
    scanCDMBtn:SetScript("OnClick", function()
        if TUICD.CDMScraper and TUICD.CDMScraper.ScrapeAndAdd then
            local added = TUICD.CDMScraper:ScrapeAndAdd()
            
            if added > 0 then
                TUICD:Print(string.format("CDM Scraper: Added %d spell(s) to Essential/Utility trackers", added))
                
                -- Refresh tracker displays
                if TUICD.MultiTracker and TUICD.MultiTracker.RebuildTracker then
                    TUICD.MultiTracker:RebuildTracker("multiCustom2")  -- Essential
                    TUICD.MultiTracker:RebuildTracker("multiCustom3")  -- Utility
                end
                
                -- Refresh the entries list if we're viewing Essential or Utility
                if selectedTrackerKey == "multiCustom2" or selectedTrackerKey == "multiCustom3" then
                    MultiTrackerUI:RefreshContent()
                end
            else
                TUICD:Print("CDM Scraper: No new spells found (all CDM spells already tracked)")
            end
        else
            TUICD:Print("CDM Scraper not available")
        end
    end)
    scanCDMBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Scan Cooldown Manager")
        GameTooltip:AddLine("Re-scan Blizzard's Cooldown Manager to find new\nEssential and Utility cooldowns for the current spec.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Use this after changing specs or when cooldowns\nare missing from your Essential/Utility trackers.", 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    scanCDMBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- ========================================
    -- TAB SYSTEM
    -- ========================================
    
    local tabs = {
        { name = "Entries", key = "entries" },
        { name = "Layout", key = "layout" },
        { name = "Appearance", key = "appearance" },
        { name = "Text", key = "text" },
        { name = "Visibility", key = "visibility" },
        { name = "Per-Icon", key = "pericon" },
    }
    
    tabContainer = CreateFrame("Frame", nil, mainPanel)
    tabContainer:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -10)
    tabContainer:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -10)
    tabContainer:SetHeight(28)
    
    contentContainer = CreateFrame("Frame", nil, mainPanel)
    contentContainer:SetPoint("TOPLEFT", tabContainer, "BOTTOMLEFT", 0, -4)
    contentContainer:SetPoint("BOTTOMRIGHT", mainPanel, "BOTTOMRIGHT", -30, 10)
    
    local tabBuilders = {
        entries = BuildEntriesTab,
        layout = BuildLayoutTab,
        appearance = BuildAppearanceTab,
        text = BuildTextTab,
        visibility = BuildVisibilityTab,
        pericon = BuildPerIconTab,
    }
    
    local tabWidth = (PANEL_WIDTH - 30) / #tabs
    
    for i, tab in ipairs(tabs) do
        local content = CreateTabContent(contentContainer)
        contentFrames[tab.key] = content
        
        if tabBuilders[tab.key] then
            tabBuilders[tab.key](content.scrollChild)
        end
        
        local tabBtn = CreateFrame("Button", nil, tabContainer)
        tabBtn:SetSize(tabWidth - 2, 26)
        tabBtn:SetPoint("LEFT", (i - 1) * tabWidth, 0)
        
        tabBtn.bg = tabBtn:CreateTexture(nil, "BACKGROUND")
        tabBtn.bg:SetAllPoints()
        tabBtn.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
        
        tabBtn.text = tabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabBtn.text:SetPoint("CENTER")
        tabBtn.text:SetText(tab.name)
        
        tabBtn:SetScript("OnClick", function()
            for _, cf in pairs(contentFrames) do
                cf:Hide()
            end
            contentFrames[tab.key]:Show()
            
            for _, btn in ipairs(tabButtons) do
                btn.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                btn.text:SetTextColor(0.7, 0.7, 0.7)
            end
            tabBtn.bg:SetColorTexture(0.3, 0.3, 0.5, 1)
            tabBtn.text:SetTextColor(1, 1, 1)
            currentTab = i
            
            if tab.key == "entries" then
                if mainPanel.RefreshEntriesList then
                    mainPanel:RefreshEntriesList()
                end
            end
        end)
        
        tabBtn:SetScript("OnEnter", function(self)
            if currentTab ~= i then
                self.bg:SetColorTexture(0.25, 0.25, 0.35, 0.9)
            end
        end)
        
        tabBtn:SetScript("OnLeave", function(self)
            if currentTab ~= i then
                self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            end
        end)
        
        tabButtons[i] = tabBtn
    end
    
    -- Select first tab
    if tabButtons[1] then
        tabButtons[1]:Click()
    end
    
    RefreshDropdown()
    
    return mainPanel
end

function MultiTrackerUI:RefreshContent()
    -- Rebuild all tab content for new tracker
    local tabBuilders = {
        entries = BuildEntriesTab,
        layout = BuildLayoutTab,
        appearance = BuildAppearanceTab,
        text = BuildTextTab,
        visibility = BuildVisibilityTab,
        pericon = BuildPerIconTab,
    }
    
    for key, content in pairs(contentFrames) do
        -- Clear existing content
        local scrollChild = content.scrollChild
        for _, child in ipairs({scrollChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
        for _, region in ipairs({scrollChild:GetRegions()}) do
            region:Hide()
            region:SetParent(nil)
        end
        
        -- Rebuild
        if tabBuilders[key] then
            tabBuilders[key](scrollChild)
        end
    end
    
    -- Refresh entries list if on that tab
    if mainPanel.RefreshEntriesList then
        mainPanel:RefreshEntriesList()
    end
end

function MultiTrackerUI:Show(hub)
    -- Close other module panels when opening Multi-Tracker
    if TUICD.Cooldowns and TUICD.Cooldowns.HideTrackerPanels then
        TUICD.Cooldowns:HideTrackerPanels()
    end
    if TUICD.DocksUI then TUICD.DocksUI:Hide() end
    if TUICD.PersonalResources and TUICD.PersonalResources.HideAllPanels then
        TUICD.PersonalResources:HideAllPanels()
    end
    if TUICD.Bars and TUICD.Bars.HideAllPanels then
        TUICD.Bars:HideAllPanels()
    end
    
    if not mainPanel then
        self:CreatePanel()
    end
    
    -- Position relative to hub if provided
    if hub then
        mainPanel:ClearAllPoints()
        mainPanel:SetPoint("TOPLEFT", hub, "TOPRIGHT", 0, 0)
    end
    
    mainPanel:Show()
    
    -- Refresh content when shown
    if mainPanel.RefreshDropdown then
        mainPanel.RefreshDropdown()
    end
    if mainPanel.RefreshEntriesList then
        mainPanel:RefreshEntriesList()
    end
end

function MultiTrackerUI:Hide()
    if mainPanel then
        mainPanel:Hide()
    end
end

-- Alias for consistency with other modules
function MultiTrackerUI:HideAllPanels()
    self:Hide()
end

function MultiTrackerUI:IsShown()
    return mainPanel and mainPanel:IsShown()
end

function MultiTrackerUI:Toggle(hub)
    if mainPanel and mainPanel:IsShown() then
        self:Hide()
    else
        self:Show(hub)
    end
end

-- ============================================================================
-- SLASH COMMAND
-- ============================================================================

SLASH_TUICDMULTIUI1 = "/tuicdmultiui"
SlashCmdList["TUICDMULTIUI"] = function(msg)
    -- Try to position relative to the hub if it exists and is shown
    local hub = _G["TweaksUI_Cooldowns_Hub"]
    if hub and hub:IsShown() then
        MultiTrackerUI:Toggle(hub)
    else
        MultiTrackerUI:Toggle(nil)
    end
end

-- Also add to the main /tuicdmulti command
local origSlashHandler = SlashCmdList["TUICDMULTI"]
SlashCmdList["TUICDMULTI"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    
    local cmd = args[1] and args[1]:lower() or ""
    
    if cmd == "ui" or cmd == "settings" or cmd == "config" or cmd == "" then
        -- Default action - open UI
        local hub = _G["TweaksUI_Cooldowns_Hub"]
        if hub and hub:IsShown() then
            MultiTrackerUI:Toggle(hub)
        else
            MultiTrackerUI:Toggle(nil)
        end
        return
    end
    
    -- Fall through to original handler for other commands
    if origSlashHandler then
        origSlashHandler(msg)
    end
end
