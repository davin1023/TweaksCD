-- ============================================================================
-- TUICD: Cooldowns - Spellbook Helper Panel
-- Docks to the spellbook to allow easy drag-and-drop of spells to Custom Tracker
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Module reference (will be set after Cooldowns module loads)
local SpellbookHelper = {}
TUICD.SpellbookHelper = SpellbookHelper

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH = 200
local PANEL_HEIGHT = 350
local ENTRY_HEIGHT = 24
local MAX_VISIBLE_ENTRIES = 10

-- ============================================================================
-- LOCALS
-- ============================================================================

local helperPanel = nil
local entryRows = {}
local isInitialized = false

-- Forward declarations
local AddCustomEntry, RemoveCustomEntry, GetCurrentSpecEntries, RebuildCustomTrackerIcons

-- ============================================================================
-- PANEL CREATION
-- ============================================================================

local function CreateHelperPanel()
    if helperPanel then return helperPanel end
    
    -- Create main frame
    helperPanel = CreateFrame("Frame", "TweaksUI_SpellbookHelper", UIParent, "BackdropTemplate")
    helperPanel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    helperPanel:SetFrameStrata("HIGH")
    helperPanel:SetFrameLevel(100)
    helperPanel:SetClampedToScreen(true)
    
    -- Dark backdrop matching TUICD style
    helperPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    helperPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    helperPanel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Title
    local title = helperPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cffffd100Quick Add|r")
    
    -- Subtitle
    local subtitle = helperPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -2)
    subtitle:SetText("|cff888888Custom Tracker|r")
    
    -- Drop zone frame
    local dropZone = CreateFrame("Button", nil, helperPanel, "BackdropTemplate")
    dropZone:SetPoint("TOPLEFT", 12, -45)
    dropZone:SetPoint("TOPRIGHT", -12, -45)
    dropZone:SetHeight(50)
    dropZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dropZone:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    dropZone:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Drop zone icon
    local dropIcon = dropZone:CreateTexture(nil, "ARTWORK")
    dropIcon:SetPoint("LEFT", 10, 0)
    dropIcon:SetSize(32, 32)
    dropIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    dropIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dropIcon:SetDesaturated(true)
    dropIcon:SetAlpha(0.5)
    dropZone.icon = dropIcon
    
    -- Drop zone text
    local dropText = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dropText:SetPoint("LEFT", dropIcon, "RIGHT", 8, 0)
    dropText:SetPoint("RIGHT", -8, 0)
    dropText:SetJustifyH("LEFT")
    dropText:SetText("|cff888888Drag spell here|r")
    dropText:SetWordWrap(true)
    dropZone.text = dropText
    
    -- Drop zone hover effect
    dropZone:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)  -- Gold
        self.icon:SetDesaturated(false)
        self.icon:SetAlpha(1)
    end)
    
    dropZone:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        self.icon:SetDesaturated(true)
        self.icon:SetAlpha(0.5)
    end)
    
    -- Drop handler
    dropZone:SetScript("OnReceiveDrag", function(self)
        SpellbookHelper:ProcessDrop()
    end)
    
    dropZone:SetScript("OnClick", function(self)
        SpellbookHelper:ProcessDrop()
    end)
    
    helperPanel.dropZone = dropZone
    helperPanel.dropText = dropText
    helperPanel.dropIcon = dropIcon
    
    -- Current entries header
    local entriesHeader = helperPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    entriesHeader:SetPoint("TOPLEFT", dropZone, "BOTTOMLEFT", 0, -12)
    entriesHeader:SetText("|cffaaaaaaCurrent Entries|r")
    
    -- Scroll frame for entries
    local scrollFrame = CreateFrame("ScrollFrame", nil, helperPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", entriesHeader, "BOTTOMLEFT", 0, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", helperPanel, "BOTTOMRIGHT", -28, 12)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(PANEL_WIDTH - 40, 1)  -- Height will be set dynamically
    scrollFrame:SetScrollChild(scrollChild)
    
    helperPanel.scrollFrame = scrollFrame
    helperPanel.scrollChild = scrollChild
    helperPanel.entriesHeader = entriesHeader
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, helperPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetSize(20, 20)
    
    helperPanel:Hide()
    
    return helperPanel
end

-- ============================================================================
-- ENTRY LIST MANAGEMENT
-- ============================================================================

local function ClearEntryRows()
    for _, row in ipairs(entryRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(entryRows)
end

local function RefreshEntryList()
    if not helperPanel or not helperPanel.scrollChild then return end
    
    ClearEntryRows()
    
    -- Get module functions if not yet cached
    if not GetCurrentSpecEntries then
        local Cooldowns = TUICD.Cooldowns
        if Cooldowns then
            GetCurrentSpecEntries = Cooldowns.GetCurrentSpecEntries
            AddCustomEntry = Cooldowns.AddCustomEntry
            RemoveCustomEntry = Cooldowns.RemoveCustomEntry
            RebuildCustomTrackerIcons = Cooldowns.RebuildCustomTrackerIcons
        end
    end
    
    if not GetCurrentSpecEntries then
        helperPanel.entriesHeader:SetText("|cffaaaaaaNo entries|r")
        return
    end
    
    local entries = GetCurrentSpecEntries()
    if not entries or #entries == 0 then
        helperPanel.entriesHeader:SetText("|cffaaaaaaCurrent Entries (0)|r")
        helperPanel.scrollChild:SetHeight(1)
        return
    end
    
    helperPanel.entriesHeader:SetText("|cffaaaaaaCurrent Entries (" .. #entries .. ")|r")
    
    local y = 0
    for i, entry in ipairs(entries) do
        local row = CreateFrame("Frame", nil, helperPanel.scrollChild, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        row:SetHeight(ENTRY_HEIGHT)
        
        -- Alternating background
        if i % 2 == 0 then
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
            })
            row:SetBackdropColor(0.15, 0.15, 0.15, 0.5)
        end
        
        -- Icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("LEFT", 2, 0)
        icon:SetSize(ENTRY_HEIGHT - 4, ENTRY_HEIGHT - 4)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        
        -- Get display info
        local displayName, displayTexture
        if entry.type == "spell" then
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.id)
            if spellInfo then
                displayName = spellInfo.name
                displayTexture = spellInfo.iconID
            else
                displayName = "Spell " .. entry.id
                displayTexture = GetSpellTexture and GetSpellTexture(entry.id)
            end
        elseif entry.type == "item" then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(entry.id)
            displayName = itemName or ("Item " .. entry.id)
            displayTexture = itemTexture
        elseif entry.type == "equipped" then
            local itemLink = GetInventoryItemLink("player", entry.id)
            local itemTexture = GetInventoryItemTexture("player", entry.id)
            if itemLink then
                displayName = itemLink:match("%[(.-)%]") or ("Slot " .. entry.id)
            else
                displayName = "Equipment Slot " .. entry.id
            end
            displayTexture = itemTexture
        end
        
        icon:SetTexture(displayTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        
        -- Disabled indicator
        if entry.enabled == false then
            icon:SetDesaturated(true)
            icon:SetAlpha(0.5)
        end
        
        -- Name label
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        
        local typePrefix = entry.type == "spell" and "[S]" or (entry.type == "item" and "[I]" or "[E]")
        if entry.enabled == false then
            label:SetText("|cff666666" .. typePrefix .. " " .. (displayName or "Unknown") .. "|r")
        else
            label:SetText("|cffcccccc" .. typePrefix .. "|r " .. (displayName or "Unknown"))
        end
        
        -- Delete button
        local deleteBtn = CreateFrame("Button", nil, row)
        deleteBtn:SetPoint("RIGHT", -2, 0)
        deleteBtn:SetSize(16, 16)
        deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
        deleteBtn:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3)
        
        local entryIndex = i  -- Capture for closure
        deleteBtn:SetScript("OnClick", function()
            SpellbookHelper:RemoveEntry(entryIndex)
        end)
        
        deleteBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Remove from Custom Tracker")
            GameTooltip:Show()
        end)
        deleteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        table.insert(entryRows, row)
        y = y + ENTRY_HEIGHT
    end
    
    helperPanel.scrollChild:SetHeight(math.max(y, 1))
end

-- ============================================================================
-- DROP HANDLING
-- ============================================================================

function SpellbookHelper:ProcessDrop()
    if not helperPanel then return end
    
    local cursorType, id, subType, spellID = GetCursorInfo()
    
    if not cursorType then return end
    
    -- Get module functions if not yet cached
    if not AddCustomEntry then
        local Cooldowns = TUICD.Cooldowns
        if Cooldowns then
            AddCustomEntry = Cooldowns.AddCustomEntry
            RebuildCustomTrackerIcons = Cooldowns.RebuildCustomTrackerIcons
        end
    end
    
    if not AddCustomEntry then
        helperPanel.dropText:SetText("|cffff0000Module not ready|r")
        C_Timer.After(1.5, function()
            if helperPanel then
                helperPanel.dropText:SetText("|cff888888Drag spell here|r")
            end
        end)
        return
    end
    
    local success = false
    local entryName = "Unknown"
    
    if cursorType == "spell" then
        local actualSpellID = spellID or id
        if actualSpellID then
            success = AddCustomEntry("spell", actualSpellID)
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(actualSpellID)
            entryName = spellInfo and spellInfo.name or ("Spell " .. actualSpellID)
        end
    elseif cursorType == "item" then
        local itemID = id
        if itemID then
            success = AddCustomEntry("item", itemID)
            local itemName = GetItemInfo(itemID)
            entryName = itemName or ("Item " .. itemID)
        end
    end
    
    ClearCursor()
    
    if success then
        -- Update icon briefly
        helperPanel.dropIcon:SetDesaturated(false)
        helperPanel.dropIcon:SetAlpha(1)
        helperPanel.dropText:SetText("|cff00ff00Added: " .. entryName .. "|r")
        
        -- Rebuild tracker and refresh list
        if RebuildCustomTrackerIcons then
            RebuildCustomTrackerIcons()
        end
        RefreshEntryList()
        
        -- Also refresh the main settings panel if open
        local customPanel = TUICD.Cooldowns and TUICD.Cooldowns.settingsPanels and TUICD.Cooldowns.settingsPanels["customTrackers"]
        if customPanel and customPanel.RefreshEntriesList then
            customPanel:RefreshEntriesList()
        end
        
        C_Timer.After(2, function()
            if helperPanel and helperPanel.dropText then
                helperPanel.dropText:SetText("|cff888888Drag spell here|r")
                helperPanel.dropIcon:SetDesaturated(true)
                helperPanel.dropIcon:SetAlpha(0.5)
            end
        end)
    else
        helperPanel.dropText:SetText("|cffff8888Already added or invalid|r")
        C_Timer.After(1.5, function()
            if helperPanel and helperPanel.dropText then
                helperPanel.dropText:SetText("|cff888888Drag spell here|r")
            end
        end)
    end
end

-- ============================================================================
-- ENTRY REMOVAL
-- ============================================================================

function SpellbookHelper:RemoveEntry(index)
    -- Get module functions if not yet cached
    if not RemoveCustomEntry then
        local Cooldowns = TUICD.Cooldowns
        if Cooldowns then
            RemoveCustomEntry = Cooldowns.RemoveCustomEntry
            RebuildCustomTrackerIcons = Cooldowns.RebuildCustomTrackerIcons
            GetCurrentSpecEntries = Cooldowns.GetCurrentSpecEntries
        end
    end
    
    if not RemoveCustomEntry then return end
    
    -- Get the listIndex for per-icon settings compaction
    local customTrackerIcons = TUICD.Cooldowns and TUICD.Cooldowns.customTrackerIcons
    local listIndex = nil
    if customTrackerIcons then
        for key, iconFrame in pairs(customTrackerIcons) do
            if iconFrame.entryIndex == index then
                listIndex = iconFrame.listIndex
                break
            end
        end
    end
    
    -- Compact per-icon settings if we found the slot
    if listIndex and TUICD.CooldownHighlights and TUICD.CooldownHighlights.RemoveIconSlot then
        TUICD.CooldownHighlights:RemoveIconSlot("custom", listIndex)
    end
    
    RemoveCustomEntry(index)
    
    if RebuildCustomTrackerIcons then
        RebuildCustomTrackerIcons()
    end
    
    RefreshEntryList()
    
    -- Also refresh the main settings panel if open
    local customPanel = TUICD.Cooldowns and TUICD.Cooldowns.settingsPanels and TUICD.Cooldowns.settingsPanels["customTrackers"]
    if customPanel then
        if customPanel.RefreshEntriesList then
            customPanel:RefreshEntriesList()
        end
        if customPanel.RefreshEquipmentList then
            customPanel:RefreshEquipmentList()
        end
    end
end

-- ============================================================================
-- POSITIONING
-- ============================================================================

local function PositionNextToSpellbook()
    if not helperPanel then return end
    
    local spellbook = PlayerSpellsFrame
    if not spellbook or not spellbook:IsShown() then
        helperPanel:Hide()
        return
    end
    
    -- Position to the right of the spellbook
    helperPanel:ClearAllPoints()
    helperPanel:SetPoint("TOPLEFT", spellbook, "TOPRIGHT", 5, 0)
    helperPanel:Show()
    
    RefreshEntryList()
end

-- ============================================================================
-- SPELLBOOK HOOKS
-- ============================================================================

local function SetupSpellbookHooks()
    if isInitialized then return end
    
    -- Modern spellbook (Dragonflight+)
    if PlayerSpellsFrame then
        PlayerSpellsFrame:HookScript("OnShow", function()
            if not helperPanel then
                CreateHelperPanel()
            end
            PositionNextToSpellbook()
        end)
        
        PlayerSpellsFrame:HookScript("OnHide", function()
            if helperPanel then
                helperPanel:Hide()
            end
        end)
        
        isInitialized = true
    else
        -- Wait for spellbook to be created
        local waitFrame = CreateFrame("Frame")
        waitFrame:RegisterEvent("ADDON_LOADED")
        waitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        waitFrame:SetScript("OnEvent", function(self, event, arg1)
            if PlayerSpellsFrame then
                self:UnregisterAllEvents()
                SetupSpellbookHooks()
            end
        end)
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function SpellbookHelper:Initialize()
    SetupSpellbookHooks()
end

function SpellbookHelper:Show()
    if not helperPanel then
        CreateHelperPanel()
    end
    PositionNextToSpellbook()
end

function SpellbookHelper:Hide()
    if helperPanel then
        helperPanel:Hide()
    end
end

function SpellbookHelper:Toggle()
    if helperPanel and helperPanel:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function SpellbookHelper:Refresh()
    RefreshEntryList()
end

-- ============================================================================
-- AUTO-INITIALIZE
-- ============================================================================

-- Initialize when Cooldowns module is ready
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    C_Timer.After(1, function()
        SpellbookHelper:Initialize()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)
