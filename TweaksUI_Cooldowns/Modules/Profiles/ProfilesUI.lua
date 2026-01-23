-- TUICD Profiles UI
-- Profile management panels: profiles list, export, import, quick setup (1.5.0+)

local ADDON_NAME, TUICD = ...

TUICD.ProfilesUI = {}
local ProfilesUI = TUICD.ProfilesUI

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH = 500
local PANEL_HEIGHT = 680
local BUTTON_HEIGHT = 26
local LIST_ROW_HEIGHT = 28
local PADDING = 15

-- Colors matching TUICD design standards
local COLORS = {
    gold = { 1, 0.82, 0 },
    green = { 0.3, 0.8, 0.3 },
    red = { 0.8, 0.3, 0.3 },
    orange = { 0.9, 0.7, 0.2 },
    blue = { 0.3, 0.6, 0.9 },
    white = { 1, 1, 1 },
    gray = { 0.6, 0.6, 0.6 },
    dimGray = { 0.4, 0.4, 0.4 },
}

local darkBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

local flatBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = false, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
}

-- ============================================================================
-- LOCAL STATE
-- ============================================================================

local profilesPanel = nil
local exportPanel = nil
local importPanel = nil
local quickSetupPanel = nil
local parentHub = nil

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function CreateSeparator(parent, yOffset)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", PADDING, yOffset)
    sep:SetPoint("TOPRIGHT", -PADDING, yOffset)
    sep:SetHeight(1)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    return sep
end

local function CreateSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", PADDING, yOffset)
    header:SetText(text)
    header:SetTextColor(unpack(COLORS.gold))
    return header
end

local function CreateButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 100, height or BUTTON_HEIGHT)
    btn:SetText(text)
    return btn
end

local function CreateCheckbox(parent, text, initialValue, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.text:SetText(text)
    cb:SetChecked(initialValue)
    if onChange then
        cb:SetScript("OnClick", function(self)
            onChange(self:GetChecked())
        end)
    end
    return cb
end

-- ============================================================================
-- STATIC POPUPS
-- ============================================================================

StaticPopupDialogs["TWEAKSUI_SAVE_PROFILE"] = {
    text = "Enter a name for this profile:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 50,
    OnAccept = function(self)
        local text = self.EditBox:GetText()
        if text and text ~= "" then
            local success, err = TUICD.Profiles:SaveProfile(text)
            if success then
                ProfilesUI:RefreshProfilesList()
            else
                TUICD:PrintError(err or "Failed to save profile")
            end
        end
    end,
    OnShow = function(self)
        self.EditBox:SetText(UnitName("player") .. " - ")
        self.EditBox:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local text = self:GetText()
        if text and text ~= "" then
            local success, err = TUICD.Profiles:SaveProfile(text)
            if success then
                ProfilesUI:RefreshProfilesList()
            else
                TUICD:PrintError(err or "Failed to save profile")
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TWEAKSUI_DELETE_PROFILE"] = {
    text = "Delete profile \"%s\"?\n\nThis cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        local success, err = TUICD.Profiles:DeleteProfile(data)
        if success then
            ProfilesUI:RefreshProfilesList()
        else
            TUICD:PrintError(err or "Failed to delete profile")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TWEAKSUI_DUPLICATE_PROFILE"] = {
    text = "Enter name for the copy:",
    button1 = "Duplicate",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 50,
    OnAccept = function(self, data)
        local text = self.EditBox:GetText()
        if text and text ~= "" then
            local success, err = TUICD.Profiles:DuplicateProfile(data, text)
            if success then
                ProfilesUI:RefreshProfilesList()
            else
                TUICD:PrintError(err or "Failed to duplicate profile")
            end
        end
    end,
    OnShow = function(self, data)
        self.EditBox:SetText(data .. " (Copy)")
        self.EditBox:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local text = self:GetText()
        if text and text ~= "" then
            local success, err = TUICD.Profiles:DuplicateProfile(parent.data, text)
            if success then
                ProfilesUI:RefreshProfilesList()
            else
                TUICD:PrintError(err or "Failed to duplicate profile")
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TWEAKSUI_LOAD_PROFILE_DIRTY"] = {
    text = "You have unsaved changes.\n\nWhat would you like to do?",
    button1 = "Save & Load",
    button2 = "Discard & Load",
    button3 = "Cancel",
    OnAccept = function(self, data)
        -- Save current to existing profile, then load
        local currentProfile = TUICD.Profiles:GetLoadedProfileName()
        if currentProfile and not TUICD.Profiles:IsBuiltInProfile(currentProfile) then
            TUICD.Profiles:SaveProfile(currentProfile)
            TUICD:Print("Saved profile: |cff00ff00" .. currentProfile .. "|r")
        elseif currentProfile then
            TUICD:Print("|cffff8800Cannot save changes to built-in profile. Use 'Save As' to create a copy.|r")
        end
        local success, result = TUICD.Profiles:LoadProfile(data.profileName, true)
        if success then
            ProfilesUI:RefreshProfilesList()
            if result == "NEEDS_RELOAD" then
                StaticPopup_Show("TWEAKSUI_RELOAD_AFTER_PROFILE")
            end
        end
    end,
    OnCancel = function(self, data)
        -- Discard and load
        local success, result = TUICD.Profiles:LoadProfile(data.profileName, true)
        if success then
            ProfilesUI:RefreshProfilesList()
            if result == "NEEDS_RELOAD" then
                StaticPopup_Show("TWEAKSUI_RELOAD_AFTER_PROFILE")
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TWEAKSUI_RELOAD_AFTER_PROFILE"] = {
    text = "Profile loaded. Some settings require a UI reload to take effect.\n\nReload now?",
    button1 = "Reload Now",
    button2 = "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TWEAKSUI_SPEC_SWITCH_DIRTY"] = {
    text = "You changed spec but have unsaved settings changes.\n\nWhat would you like to do before switching to profile \"%s\"?",
    button1 = "Save & Switch",
    button2 = "Discard & Switch",
    button3 = "Cancel",
    OnAccept = function(self, data)
        -- Save current to existing profile, then load spec profile
        local currentProfile = TUICD.Profiles:GetLoadedProfileName()
        if currentProfile and not TUICD.Profiles:IsBuiltInProfile(currentProfile) then
            TUICD.Profiles:SaveProfile(currentProfile)
            TUICD:Print("Saved profile: |cff00ff00" .. currentProfile .. "|r")
        end
        local success, result = TUICD.Profiles:LoadProfile(data.targetProfile, true)
        if success then
            ProfilesUI:RefreshProfilesList()
            if result == "NEEDS_RELOAD" then
                StaticPopup_Show("TWEAKSUI_RELOAD_AFTER_PROFILE")
            end
        end
    end,
    OnCancel = function(self, data)
        -- Discard and load spec profile
        local success, result = TUICD.Profiles:LoadProfile(data.targetProfile, true)
        if success then
            ProfilesUI:RefreshProfilesList()
            if result == "NEEDS_RELOAD" then
                StaticPopup_Show("TWEAKSUI_RELOAD_AFTER_PROFILE")
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TWEAKSUI_IMPORT_SUCCESS"] = {
    text = "Profile \"%s\" imported successfully!\n\nWould you like to load it now?",
    button1 = "Load Now",
    button2 = "Later",
    OnAccept = function(self, data)
        local success, result = TUICD.Profiles:LoadProfile(data, true)
        if success then
            ProfilesUI:RefreshProfilesList()
            if result == "NEEDS_RELOAD" then
                StaticPopup_Show("TWEAKSUI_RELOAD_AFTER_PROFILE")
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================================
-- PROFILES PANEL
-- ============================================================================

local function CreateProfileRow(parent, profileData, yOffset, isLoaded)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", 0, yOffset)
    row:SetHeight(LIST_ROW_HEIGHT)
    
    local isBuiltIn = profileData.isBuiltIn
    
    -- Background (different colors for built-in, loaded, normal)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if isLoaded then
        bg:SetColorTexture(0.2, 0.4, 0.2, 0.3)
    elseif isBuiltIn then
        bg:SetColorTexture(0.12, 0.12, 0.18, 0.4)
    else
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.3)
    end
    
    -- Loaded indicator
    if isLoaded then
        local indicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        indicator:SetPoint("LEFT", 5, 0)
        indicator:SetText(">")
        indicator:SetTextColor(unpack(COLORS.gold))
    end
    
    -- Profile name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", isLoaded and 22 or 8, 0)
    
    -- Add "(built-in)" label for default profiles
    if isBuiltIn then
        nameText:SetText(profileData.name .. " |cff888888(built-in)|r")
    else
        nameText:SetText(profileData.name)
    end
    nameText:SetTextColor(unpack(COLORS.white))
    
    -- Buttons on right
    local btnWidth = 50
    local btnSpacing = 4
    
    if isBuiltIn then
        -- Built-in profiles: only Copy and Load buttons
        
        -- Copy button (duplicate to user profile)
        local dupeBtn = CreateButton(row, "Copy", btnWidth, 22)
        dupeBtn:SetPoint("RIGHT", -5, 0)
        dupeBtn:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("TWEAKSUI_DUPLICATE_PROFILE", profileData.name)
            if dialog then
                dialog.data = profileData.name
            end
        end)
        
        -- Load button (unless already loaded)
        if not isLoaded then
            local loadBtn = CreateButton(row, "Load", btnWidth, 22)
            loadBtn:SetPoint("RIGHT", dupeBtn, "LEFT", -btnSpacing, 0)
            loadBtn:SetScript("OnClick", function()
                -- Check dirty state
                if TUICD.Profiles:IsDirty() then
                    local dialog = StaticPopup_Show("TWEAKSUI_LOAD_PROFILE_DIRTY")
                    if dialog then
                        dialog.data = { profileName = profileData.name }
                    end
                else
                    local success, result = TUICD.Profiles:LoadProfile(profileData.name, true)
                    if success then
                        ProfilesUI:RefreshProfilesList()
                        if result == "NEEDS_RELOAD" then
                            StaticPopup_Show("TWEAKSUI_RELOAD_AFTER_PROFILE")
                        end
                    else
                        TUICD:PrintError(result or "Failed to load profile")
                    end
                end
            end)
        end
    else
        -- User profiles: full button set
        
        -- Delete button
        local deleteBtn = CreateButton(row, "Del", btnWidth, 22)
        deleteBtn:SetPoint("RIGHT", -5, 0)
        deleteBtn:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("TWEAKSUI_DELETE_PROFILE", profileData.name)
            if dialog then
                dialog.data = profileData.name
            end
        end)
        -- Can't delete loaded profile
        if isLoaded then
            deleteBtn:Disable()
            deleteBtn:SetAlpha(0.5)
        end
        
        -- Duplicate button
        local dupeBtn = CreateButton(row, "Copy", btnWidth, 22)
        dupeBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -btnSpacing, 0)
        dupeBtn:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("TWEAKSUI_DUPLICATE_PROFILE", profileData.name)
            if dialog then
                dialog.data = profileData.name
            end
        end)
        
        -- Update button (only for loaded profile)
        if isLoaded then
            local updateBtn = CreateButton(row, "Update", btnWidth + 10, 22)
            updateBtn:SetPoint("RIGHT", dupeBtn, "LEFT", -btnSpacing, 0)
            updateBtn:SetScript("OnClick", function()
                TUICD.Profiles:SaveProfile(profileData.name)
                ProfilesUI:RefreshProfilesList()
            end)
        else
            -- Load button
            local loadBtn = CreateButton(row, "Load", btnWidth, 22)
            loadBtn:SetPoint("RIGHT", dupeBtn, "LEFT", -btnSpacing, 0)
            loadBtn:SetScript("OnClick", function()
                -- Check dirty state
                if TUICD.Profiles:IsDirty() then
                    local dialog = StaticPopup_Show("TWEAKSUI_LOAD_PROFILE_DIRTY")
                    if dialog then
                        dialog.data = { profileName = profileData.name }
                    end
                else
                    local success, result = TUICD.Profiles:LoadProfile(profileData.name, true)
                    if success then
                        ProfilesUI:RefreshProfilesList()
                        if result == "NEEDS_RELOAD" then
                            StaticPopup_Show("TWEAKSUI_RELOAD_AFTER_PROFILE")
                        end
                    else
                        TUICD:PrintError(result or "Failed to load profile")
                    end
                end
            end)
        end
    end
    
    return row
end

function ProfilesUI:CreateProfilesPanel()
    if profilesPanel then return profilesPanel end
    
    local panel = CreateFrame("Frame", "TweaksUI_ProfilesPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("HIGH")
    panel:Hide()
    
    -- Header
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", 0, -12)
    header:SetText("Profiles")
    header:SetTextColor(unpack(COLORS.gold))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    local yOffset = -40
    
    -- Current Settings Section
    local currentHeader = CreateSectionHeader(panel, "Current Settings", yOffset)
    yOffset = yOffset - 22
    
    -- Dirty indicator
    panel.dirtyIndicator = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.dirtyIndicator:SetPoint("TOPLEFT", PADDING, yOffset)
    panel.dirtyIndicator:SetText("")
    yOffset = yOffset - 18
    
    -- Based on text
    panel.basedOnText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.basedOnText:SetPoint("TOPLEFT", PADDING, yOffset)
    panel.basedOnText:SetTextColor(unpack(COLORS.gray))
    yOffset = yOffset - 25
    
    CreateSeparator(panel, yOffset)
    yOffset = yOffset - 15
    
    -- Saved Profiles Section
    CreateSectionHeader(panel, "Saved Profiles", yOffset)
    yOffset = yOffset - 25
    
    -- Scroll frame for profile list
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", PADDING, yOffset)
    scrollFrame:SetPoint("TOPRIGHT", -PADDING - 25, yOffset)
    scrollFrame:SetHeight(180)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(PANEL_WIDTH - 60, 400)
    scrollFrame:SetScrollChild(scrollChild)
    panel.profileListContent = scrollChild
    
    yOffset = yOffset - 190
    
    -- Save New Profile button
    local saveNewBtn = CreateButton(panel, "Save Current as New Profile...", 200, BUTTON_HEIGHT)
    saveNewBtn:SetPoint("TOPLEFT", PADDING, yOffset)
    saveNewBtn:SetScript("OnClick", function()
        StaticPopup_Show("TWEAKSUI_SAVE_PROFILE")
    end)
    
    yOffset = yOffset - 40
    CreateSeparator(panel, yOffset)
    yOffset = yOffset - 15
    
    -- Spec Auto-Switch Section
    CreateSectionHeader(panel, "Spec Auto-Switch", yOffset)
    yOffset = yOffset - 25
    
    -- Enable checkbox
    panel.specAutoSwitchCB = CreateCheckbox(panel, "Enable automatic profile switching on spec change", 
        TUICD.Profiles:IsSpecAutoSwitchEnabled(),
        function(checked)
            TUICD.Profiles:SetSpecAutoSwitchEnabled(checked)
            ProfilesUI:UpdateSpecDropdowns()
        end)
    panel.specAutoSwitchCB:SetPoint("TOPLEFT", PADDING, yOffset)
    yOffset = yOffset - 30
    
    -- Spec dropdowns container (enough for 4 specs at 28px each)
    panel.specDropdownsContainer = CreateFrame("Frame", nil, panel)
    panel.specDropdownsContainer:SetPoint("TOPLEFT", PADDING, yOffset)
    panel.specDropdownsContainer:SetPoint("TOPRIGHT", -PADDING, yOffset)
    panel.specDropdownsContainer:SetHeight(115)  -- 4 specs * 28px + padding
    panel.specDropdowns = {}
    
    yOffset = yOffset - 120
    CreateSeparator(panel, yOffset)
    yOffset = yOffset - 15
    
    -- Quick Actions Section
    CreateSectionHeader(panel, "Quick Actions", yOffset)
    yOffset = yOffset - 30
    
    -- Export button
    local exportBtn = CreateButton(panel, "Export...", 100, BUTTON_HEIGHT)
    exportBtn:SetPoint("TOPLEFT", PADDING, yOffset)
    exportBtn:SetScript("OnClick", function()
        panel:Hide()
        ProfilesUI:ShowExportPanel()
    end)
    
    -- Import button
    local importBtn = CreateButton(panel, "Import...", 100, BUTTON_HEIGHT)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
    importBtn:SetScript("OnClick", function()
        panel:Hide()
        ProfilesUI:ShowImportPanel()
    end)
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    profilesPanel = panel
    return panel
end

function ProfilesUI:RefreshProfilesList()
    if not profilesPanel or not profilesPanel.profileListContent then return end
    
    local content = profilesPanel.profileListContent
    
    -- Clear existing rows
    for _, child in ipairs({content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- Get profiles
    local profiles = TUICD.Profiles:GetProfileList()
    local loadedProfile = TUICD.Profiles:GetLoadedProfileName()
    
    -- Create rows
    local yOffset = 0
    for _, profileData in ipairs(profiles) do
        local isLoaded = (profileData.name == loadedProfile)
        CreateProfileRow(content, profileData, yOffset, isLoaded)
        yOffset = yOffset - LIST_ROW_HEIGHT - 2
    end
    
    -- Adjust content height
    content:SetHeight(math.max(100, math.abs(yOffset) + 20))
    
    -- Update dirty indicator
    self:UpdateDirtyIndicator()
end

function ProfilesUI:UpdateDirtyIndicator()
    if not profilesPanel then return end
    
    local dirtyState = TUICD.Profiles:GetDirtyState()
    local loadedProfile = TUICD.Profiles:GetLoadedProfileName()
    
    if dirtyState.isDirty then
        profilesPanel.dirtyIndicator:SetText("|cffff8800*|r Unsaved changes")
    else
        profilesPanel.dirtyIndicator:SetText("|cff00ff00*|r No unsaved changes")
    end
    
    if loadedProfile then
        profilesPanel.basedOnText:SetText("Based on: " .. loadedProfile)
    else
        profilesPanel.basedOnText:SetText("Based on: (no profile loaded)")
    end
end

function ProfilesUI:UpdateSpecDropdowns()
    if not profilesPanel or not profilesPanel.specDropdownsContainer then return end
    
    local container = profilesPanel.specDropdownsContainer
    local enabled = TUICD.Profiles:IsSpecAutoSwitchEnabled()
    
    -- Clear existing
    for _, child in ipairs({container:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    if not enabled then
        container:SetAlpha(0.5)
        return
    end
    container:SetAlpha(1.0)
    
    -- Get spec info
    local numSpecs = GetNumSpecializations()
    local profiles = TUICD.Profiles:GetProfileList()
    
    local yOffset = 0
    for i = 1, numSpecs do
        local _, specName = GetSpecializationInfo(i)
        if specName then
            -- Label
            local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", 0, yOffset)
            label:SetText("Spec " .. i .. " (" .. specName .. "):")
            label:SetTextColor(unpack(COLORS.white))
            
            -- Dropdown
            local dropdown = CreateFrame("Frame", "TweaksUI_SpecDropdown" .. i, container, "UIDropDownMenuTemplate")
            dropdown:SetPoint("TOPLEFT", 150, yOffset + 5)
            UIDropDownMenu_SetWidth(dropdown, 180)
            
            local currentProfile = TUICD.Profiles:GetSpecProfile(i)
            UIDropDownMenu_SetText(dropdown, currentProfile or "None")
            
            UIDropDownMenu_Initialize(dropdown, function(self, level)
                local info = UIDropDownMenu_CreateInfo()
                
                -- None option
                info.text = "None"
                info.value = nil
                info.checked = (currentProfile == nil)
                info.func = function()
                    TUICD.Profiles:SetSpecProfile(i, nil)
                    UIDropDownMenu_SetText(dropdown, "None")
                end
                UIDropDownMenu_AddButton(info)
                
                -- Profile options
                for _, profileData in ipairs(profiles) do
                    info.text = profileData.name
                    info.value = profileData.name
                    info.checked = (currentProfile == profileData.name)
                    info.func = function()
                        TUICD.Profiles:SetSpecProfile(i, profileData.name)
                        UIDropDownMenu_SetText(dropdown, profileData.name)
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
            
            yOffset = yOffset - 28
        end
    end
end

-- ============================================================================
-- EXPORT PANEL
-- ============================================================================

function ProfilesUI:CreateExportPanel()
    if exportPanel then return exportPanel end
    
    local panel = CreateFrame("Frame", "TweaksUI_ExportPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, 520)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("HIGH")
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()
    
    tinsert(UISpecialFrames, "TweaksUI_ExportPanel")
    
    -- Header
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", 0, -12)
    header:SetText("Export Settings")
    header:SetTextColor(unpack(COLORS.gold))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    local yOffset = -40
    
    CreateSectionHeader(panel, "Select what to export:", yOffset)
    yOffset = yOffset - 25
    
    -- Select All checkbox
    panel.selectAllCB = CreateCheckbox(panel, "Select All", true, function(checked)
        for _, cb in pairs(panel.moduleCheckboxes or {}) do
            cb:SetChecked(checked)
        end
        panel.layoutCB:SetChecked(checked)
        panel.enabledCB:SetChecked(checked)
    end)
    panel.selectAllCB:SetPoint("TOPLEFT", PADDING, yOffset)
    yOffset = yOffset - 28
    
    -- Module checkboxes
    panel.moduleCheckboxes = {}
    local modules = {
        { id = "cooldowns", name = "Cooldowns" },
        { id = "unitFrames", name = "Unit Frames" },
        { id = "actionBars", name = "Action Bars" },
        { id = "castBars", name = "Cast Bars" },
        { id = "chat", name = "Chat" },
        { id = "personalResources", name = "Personal Resources" },
        { id = "nameplates", name = "Nameplates" },
        { id = "general", name = "General" },
        { id = "layout", name = "Layout (positions)" },
    }
    
    for _, mod in ipairs(modules) do
        local cb = CreateCheckbox(panel, mod.name, true)
        cb:SetPoint("TOPLEFT", PADDING + 20, yOffset)
        panel.moduleCheckboxes[mod.id] = cb
        yOffset = yOffset - 24
    end
    
    yOffset = yOffset - 5
    
    -- Container positions (ActionBar containers, UI Frame containers)
    panel.layoutCB = CreateCheckbox(panel, "Container Positions (ActionBars, etc.)", true)
    panel.layoutCB:SetPoint("TOPLEFT", PADDING + 20, yOffset)
    yOffset = yOffset - 24
    
    yOffset = yOffset - 5
    
    -- Other options
    panel.enabledCB = CreateCheckbox(panel, "Module Enable States", true)
    panel.enabledCB:SetPoint("TOPLEFT", PADDING + 20, yOffset)
    yOffset = yOffset - 30
    
    -- Generate button
    local generateBtn = CreateButton(panel, "Generate Export String", 180, BUTTON_HEIGHT)
    generateBtn:SetPoint("TOPLEFT", PADDING, yOffset)
    generateBtn:SetScript("OnClick", function()
        ProfilesUI:GenerateExportString()
    end)
    
    yOffset = yOffset - 40
    CreateSeparator(panel, yOffset)
    yOffset = yOffset - 15
    
    -- Output editbox
    local outputLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    outputLabel:SetPoint("TOPLEFT", PADDING, yOffset)
    outputLabel:SetText("Export String:")
    outputLabel:SetTextColor(unpack(COLORS.gray))
    yOffset = yOffset - 20
    
    -- Use InputScrollFrameTemplate for export output
    local scrollFrame = CreateFrame("ScrollFrame", "TweaksUI_ExportScrollFrame", panel, "InputScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", PADDING, yOffset)
    scrollFrame:SetPoint("BOTTOMRIGHT", -PADDING, 50)
    scrollFrame.CharCount:Hide()  -- Hide character count
    
    local editBox = scrollFrame.EditBox
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(PANEL_WIDTH - 50)
    editBox:SetAutoFocus(false)
    panel.outputEditBox = editBox
    
    -- Copy button
    local copyBtn = CreateButton(panel, "Select All Text", 120, BUTTON_HEIGHT)
    copyBtn:SetPoint("BOTTOMLEFT", PADDING, 15)
    copyBtn:SetScript("OnClick", function()
        panel.outputEditBox:SetFocus()
        panel.outputEditBox:HighlightText()
        TUICD:Print("Text selected - press Ctrl+C to copy")
    end)
    
    -- Back button
    local backBtn = CreateButton(panel, "Back to Profiles", 120, BUTTON_HEIGHT)
    backBtn:SetPoint("BOTTOMRIGHT", -PADDING, 15)
    backBtn:SetScript("OnClick", function()
        panel:Hide()
        ProfilesUI:ShowProfilesPanel()
    end)
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    exportPanel = panel
    return panel
end

function ProfilesUI:GenerateExportString()
    if not exportPanel then return end
    
    -- Gather selected modules
    local selectedModules = {}
    for moduleId, cb in pairs(exportPanel.moduleCheckboxes) do
        if cb:GetChecked() then
            table.insert(selectedModules, moduleId)
        end
    end
    
    local options = {
        modules = #selectedModules > 0 and selectedModules or nil,
        includeLayout = exportPanel.layoutCB and exportPanel.layoutCB:GetChecked(),
        includeEnabled = exportPanel.enabledCB:GetChecked(),
        useDeltaEncoding = true,
    }
    
    local exportString, err = TUICD.ProfileImportExport:Export(options)
    
    if exportString then
        exportPanel.outputEditBox:SetText(exportString)
        exportPanel.outputEditBox:SetFocus()
        exportPanel.outputEditBox:HighlightText()
        TUICD:Print("Export string generated (" .. #exportString .. " characters)")
    else
        exportPanel.outputEditBox:SetText("Error: " .. (err or "Unknown error"))
        TUICD:PrintError("Export failed: " .. (err or "Unknown error"))
    end
end

-- ============================================================================
-- IMPORT PANEL
-- ============================================================================

function ProfilesUI:CreateImportPanel()
    if importPanel then return importPanel end
    
    local panel = CreateFrame("Frame", "TweaksUI_ImportPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, 580)  -- Increased to fit all validation results
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("HIGH")
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()
    
    tinsert(UISpecialFrames, "TweaksUI_ImportPanel")
    
    -- Header
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", 0, -12)
    header:SetText("Import Settings")
    header:SetTextColor(unpack(COLORS.gold))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    local yOffset = -40
    
    CreateSectionHeader(panel, "Paste export string:", yOffset)
    yOffset = yOffset - 20
    
    -- Use InputScrollFrameTemplate which has a working editbox built in
    local scrollFrame = CreateFrame("ScrollFrame", "TweaksUI_ImportScrollFrame", panel, "InputScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", PADDING, yOffset)
    scrollFrame:SetPoint("TOPRIGHT", -PADDING, yOffset)
    scrollFrame:SetHeight(100)
    scrollFrame.CharCount:Hide()  -- Hide character count
    
    local editBox = scrollFrame.EditBox
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(PANEL_WIDTH - 50)
    editBox:SetAutoFocus(false)
    panel.inputEditBox = editBox
    
    yOffset = yOffset - 115
    
    -- Validate button
    local validateBtn = CreateButton(panel, "Validate String", 120, BUTTON_HEIGHT)
    validateBtn:SetPoint("TOPLEFT", PADDING, yOffset)
    validateBtn:SetScript("OnClick", function()
        ProfilesUI:ValidateImportString()
    end)
    
    yOffset = yOffset - 35
    CreateSeparator(panel, yOffset)
    yOffset = yOffset - 15
    
    -- Validation results section
    CreateSectionHeader(panel, "String Contents:", yOffset)
    yOffset = yOffset - 25
    
    panel.validationResults = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.validationResults:SetPoint("TOPLEFT", PADDING, yOffset)
    panel.validationResults:SetPoint("TOPRIGHT", -PADDING, yOffset)
    panel.validationResults:SetJustifyH("LEFT")
    panel.validationResults:SetJustifyV("TOP")
    panel.validationResults:SetHeight(180)  -- Increased to fit all modules
    panel.validationResults:SetText("|cff888888Paste a string and click Validate|r")
    
    yOffset = yOffset - 190
    CreateSeparator(panel, yOffset)
    yOffset = yOffset - 15
    
    -- Profile name input
    CreateSectionHeader(panel, "Save as profile named:", yOffset)
    yOffset = yOffset - 25
    
    local nameEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    nameEditBox:SetPoint("TOPLEFT", PADDING, yOffset)
    nameEditBox:SetSize(PANEL_WIDTH - 40, 24)
    nameEditBox:SetAutoFocus(false)
    nameEditBox:SetText("Imported Profile")
    panel.profileNameEditBox = nameEditBox
    
    yOffset = yOffset - 40
    
    -- Import button
    panel.importBtn = CreateButton(panel, "Import as New Profile", 160, BUTTON_HEIGHT)
    panel.importBtn:SetPoint("TOPLEFT", PADDING, yOffset)
    panel.importBtn:Disable()
    panel.importBtn:SetScript("OnClick", function()
        ProfilesUI:DoImport()
    end)
    
    -- Back button
    local backBtn = CreateButton(panel, "Back to Profiles", 120, BUTTON_HEIGHT)
    backBtn:SetPoint("BOTTOMRIGHT", -PADDING, 15)
    backBtn:SetScript("OnClick", function()
        panel:Hide()
        ProfilesUI:ShowProfilesPanel()
    end)
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    importPanel = panel
    return panel
end

function ProfilesUI:ValidateImportString()
    if not importPanel then return end
    
    local inputString = importPanel.inputEditBox:GetText()
    if not inputString or inputString == "" then
        importPanel.validationResults:SetText("|cffff0000No string entered|r")
        importPanel.importBtn:Disable()
        return
    end
    
    local valid, info = TUICD.ProfileImportExport:Validate(inputString)
    
    if valid then
        -- Build results text
        local lines = {}
        table.insert(lines, "|cff00ff00[OK] Valid TUICD export string|r")
        table.insert(lines, "")
        table.insert(lines, "Version: " .. (info.version or "?"))
        if info.charName then
            table.insert(lines, "From: " .. info.charName .. (info.realm and ("-" .. info.realm) or ""))
        end
        table.insert(lines, "")
        table.insert(lines, "Modules included:")
        for _, moduleId in ipairs(info.modules or {}) do
            local moduleName = TUICD.MODULE_NAMES[moduleId] or moduleId
            table.insert(lines, "  |cff00ff00+|r " .. moduleName)
        end
        if info.hasLayout then
            table.insert(lines, "  |cff00ff00+|r Layout Positions")
        end
        if info.hasEnabled then
            table.insert(lines, "  |cff00ff00+|r Module Enable States")
        end
        
        importPanel.validationResults:SetText(table.concat(lines, "\n"))
        importPanel.importBtn:Enable()
        importPanel._validatedData = inputString
    else
        importPanel.validationResults:SetText("|cffff0000[X] Invalid string:|r " .. (info or "Unknown error"))
        importPanel.importBtn:Disable()
        importPanel._validatedData = nil
    end
end

function ProfilesUI:DoImport()
    if not importPanel or not importPanel._validatedData then return end
    
    local profileName = importPanel.profileNameEditBox:GetText()
    if not profileName or profileName == "" then
        TUICD:PrintError("Please enter a profile name")
        return
    end
    
    local success, result = TUICD.ProfileImportExport:Import(importPanel._validatedData, profileName)
    
    if success then
        importPanel:Hide()
        local dialog = StaticPopup_Show("TWEAKSUI_IMPORT_SUCCESS", profileName)
        if dialog then
            dialog.data = profileName
        end
        ProfilesUI:RefreshProfilesList()
    else
        TUICD:PrintError("Import failed: " .. (result or "Unknown error"))
    end
end

-- ============================================================================
-- QUICK SETUP PANEL
-- ============================================================================

function ProfilesUI:CreateQuickSetupPanel()
    if quickSetupPanel then return quickSetupPanel end
    
    local panel = CreateFrame("Frame", "TweaksUI_QuickSetupPanel", UIParent, "BackdropTemplate")
    panel:SetSize(450, 400)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("HIGH")
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()
    
    tinsert(UISpecialFrames, "TweaksUI_QuickSetupPanel")
    
    -- Header
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", 0, -12)
    header:SetText("Quick Setup")
    header:SetTextColor(unpack(COLORS.gold))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    -- Content area (will be populated dynamically)
    panel.contentFrame = CreateFrame("Frame", nil, panel)
    panel.contentFrame:SetPoint("TOPLEFT", PADDING, -40)
    panel.contentFrame:SetPoint("BOTTOMRIGHT", -PADDING, 60)
    
    -- Backup checkbox at bottom
    panel.backupCB = CreateCheckbox(panel, "Save current settings as backup before applying", true)
    panel.backupCB:SetPoint("BOTTOMLEFT", PADDING, 35)
    
    -- Back button
    local backBtn = CreateButton(panel, "Back to Profiles", 120, BUTTON_HEIGHT)
    backBtn:SetPoint("BOTTOMRIGHT", -PADDING, 10)
    backBtn:SetScript("OnClick", function()
        panel:Hide()
        ProfilesUI:ShowProfilesPanel()
    end)
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    quickSetupPanel = panel
    return panel
end

function ProfilesUI:RefreshQuickSetupContent()
    if not quickSetupPanel then return end
    
    local content = quickSetupPanel.contentFrame
    
    -- Clear existing content
    for _, child in pairs({content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in pairs({content:GetRegions()}) do
        region:Hide()
    end
    
    local DefaultProfiles = TUICD.DefaultProfiles
    if not DefaultProfiles then
        local noProfiles = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noProfiles:SetPoint("CENTER")
        noProfiles:SetText("|cffff8800Default Profiles system not loaded|r")
        return
    end
    
    local profileCount = DefaultProfiles:GetCount()
    if profileCount == 0 then
        local noProfiles = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noProfiles:SetPoint("TOP", 0, -20)
        noProfiles:SetText("|cff888888No default profiles available yet.|r")
        noProfiles:Show()
        
        local instructions = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        instructions:SetPoint("TOP", noProfiles, "BOTTOM", 0, -20)
        instructions:SetWidth(400)
        instructions:SetJustifyH("LEFT")
        instructions:SetText("Default profiles need to have their export strings added to\nCore/DefaultProfiles.lua before they appear here.\n\nYou can still create and manage profiles manually using\nthe Profiles panel.")
        instructions:Show()
        return
    end
    
    local yOffset = 0
    
    -- Role Profiles Section
    local roleProfiles = DefaultProfiles:GetProfilesByCategory("role")
    if #roleProfiles > 0 then
        local roleHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        roleHeader:SetPoint("TOPLEFT", 0, yOffset)
        roleHeader:SetText("Role-Based Profiles:")
        roleHeader:SetTextColor(unpack(COLORS.gold))
        roleHeader:Show()
        yOffset = yOffset - 25
        
        local btnWidth = 90
        local btnHeight = 60
        local btnSpacing = 10
        local totalWidth = (#roleProfiles * btnWidth) + ((#roleProfiles - 1) * btnSpacing)
        local startX = (content:GetWidth() - totalWidth) / 2
        
        for i, profileInfo in ipairs(roleProfiles) do
            local btn = CreateFrame("Button", nil, content, "BackdropTemplate")
            btn:SetSize(btnWidth, btnHeight)
            btn:SetPoint("TOPLEFT", startX + (i - 1) * (btnWidth + btnSpacing), yOffset)
            btn:SetBackdrop(flatBackdrop)
            btn:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            
            -- Icon
            if profileInfo.icon then
                local icon = btn:CreateTexture(nil, "ARTWORK")
                icon:SetSize(24, 24)
                icon:SetPoint("TOP", 0, -8)
                icon:SetTexture(profileInfo.icon)
                if profileInfo.iconCoords then
                    icon:SetTexCoord(unpack(profileInfo.iconCoords))
                end
            end
            
            local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameText:SetPoint("BOTTOM", 0, 8)
            nameText:SetText(profileInfo.name)
            
            btn:SetScript("OnClick", function()
                ProfilesUI:ApplyQuickSetup(profileInfo.name)
            end)
            
            btn:SetScript("OnEnter", function()
                btn:SetBackdropBorderColor(unpack(COLORS.gold))
                GameTooltip:SetOwner(btn, "ANCHOR_TOP")
                GameTooltip:SetText(profileInfo.name, 1, 1, 1)
                if profileInfo.description then
                    GameTooltip:AddLine(profileInfo.description, 0.8, 0.8, 0.8, true)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
                GameTooltip:Hide()
            end)
            
            btn:Show()
        end
        
        yOffset = yOffset - btnHeight - 20
    end
    
    -- Style Profiles Section
    local styleProfiles = DefaultProfiles:GetProfilesByCategory("style")
    if #styleProfiles > 0 then
        local styleHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        styleHeader:SetPoint("TOPLEFT", 0, yOffset)
        styleHeader:SetText("Style Profiles:")
        styleHeader:SetTextColor(unpack(COLORS.gold))
        styleHeader:Show()
        yOffset = yOffset - 25
        
        for _, profileInfo in ipairs(styleProfiles) do
            local btn = CreateButton(content, profileInfo.name, 100, 24)
            btn:SetPoint("TOPLEFT", 10, yOffset)
            btn:SetScript("OnClick", function()
                ProfilesUI:ApplyQuickSetup(profileInfo.name)
            end)
            
            local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            desc:SetPoint("LEFT", btn, "RIGHT", 10, 0)
            desc:SetText("|cff888888" .. (profileInfo.description or "") .. "|r")
            desc:Show()
            
            btn:Show()
            yOffset = yOffset - 30
        end
    end
end

function ProfilesUI:ApplyQuickSetup(profileName)
    if not quickSetupPanel then return end
    
    -- Create backup if requested
    if quickSetupPanel.backupCB:GetChecked() then
        local backupName = UnitName("player") .. " - Pre-QuickSetup Backup"
        TUICD.Profiles:SaveProfile(backupName)
        TUICD:Print("Saved backup: |cff00ff00" .. backupName .. "|r")
    end
    
    -- Load the selected default profile
    local success, result = TUICD.Profiles:LoadProfile(profileName, true)
    
    if success then
        quickSetupPanel:Hide()
        TUICD:Print("Applied profile: |cff00ff00" .. profileName .. "|r")
        
        if result == "NEEDS_RELOAD" then
            StaticPopup_Show("TWEAKSUI_RELOAD_AFTER_PROFILE")
        end
        
        -- Refresh profiles list if open
        ProfilesUI:RefreshProfilesList()
    else
        TUICD:PrintError("Failed to apply profile: " .. (result or "Unknown error"))
    end
end

-- ============================================================================
-- SHOW FUNCTIONS
-- ============================================================================

function ProfilesUI:ShowProfilesPanel(hub)
    parentHub = hub
    
    if not profilesPanel then
        self:CreateProfilesPanel()
    end
    
    -- Position next to hub if provided
    if hub then
        profilesPanel:ClearAllPoints()
        profilesPanel:SetPoint("TOPLEFT", hub, "TOPRIGHT", 0, 0)
    else
        profilesPanel:ClearAllPoints()
        profilesPanel:SetPoint("CENTER")
    end
    
    self:RefreshProfilesList()
    self:UpdateSpecDropdowns()
    profilesPanel:Show()
end

function ProfilesUI:ShowExportPanel()
    if not exportPanel then
        self:CreateExportPanel()
    end
    exportPanel.outputEditBox:SetText("")
    exportPanel:Show()
end

function ProfilesUI:ShowImportPanel()
    if not importPanel then
        self:CreateImportPanel()
    end
    importPanel.inputEditBox:SetText("")
    importPanel.validationResults:SetText("|cff888888Paste a string and click Validate|r")
    importPanel.profileNameEditBox:SetText("Imported Profile")
    importPanel.importBtn:Disable()
    importPanel._validatedData = nil
    importPanel:Show()
end

function ProfilesUI:ShowQuickSetupPanel()
    if not quickSetupPanel then
        self:CreateQuickSetupPanel()
    end
    self:RefreshQuickSetupContent()
    quickSetupPanel:Show()
end

function ProfilesUI:HideAll()
    if profilesPanel then profilesPanel:Hide() end
    if exportPanel then exportPanel:Hide() end
    if importPanel then importPanel:Hide() end
    if quickSetupPanel then quickSetupPanel:Hide() end
end
