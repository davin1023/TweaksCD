-- ============================================================================
-- TweaksUI: Cooldowns - Timer Bars Hub
-- Sub-hub for Timer Bars: Cooldowns, Timeline (future), Buffs
-- Docks to the main Settings hub; sub-panels dock to this hub.
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BarsHub = {}
local BarsHub = TUICD.BarsHub

-- ============================================================
-- CONSTANTS
-- ============================================================
local HUB_WIDTH    = 160
local HUB_HEIGHT   = 180
local BUTTON_WIDTH = 130
local BUTTON_HEIGHT = 28
local BUTTON_SPACING = 6

-- ============================================================
-- STATE
-- ============================================================
local hubPanel      -- the Frame
local activePanel   -- "cooldowns" | "buffs" | nil
local buttons = {}  -- keyed by panel name

-- ============================================================
-- HELPERS
-- ============================================================

local function DockToMainHub()
    local mainHub = TUICD.Settings and TUICD.Settings.hubPanel
    if mainHub and hubPanel then
        hubPanel:ClearAllPoints()
        hubPanel:SetPoint("TOPLEFT", mainHub, "TOPRIGHT", 0, 0)
    end
end

local function HideActiveSubPanel()
    if activePanel == "cooldowns" then
        local BarsUI = TUICD.BarsUI
        if BarsUI and BarsUI:IsShown() then BarsUI:Hide() end
    elseif activePanel == "buffs" then
        local BuffBarsUI = TUICD.BuffBarsUI
        if BuffBarsUI and BuffBarsUI:IsShown() then BuffBarsUI:Hide() end
    elseif activePanel == "timeline" then
        local TimelineUI = TUICD.TimelineUI
        if TimelineUI and TimelineUI:IsShown() then TimelineUI:Hide() end
    end
    activePanel = nil
end

local function HighlightButton(name)
    for key, btn in pairs(buttons) do
        if key == name then
            btn:GetFontString():SetTextColor(1, 0.82, 0)  -- Gold
        else
            btn:GetFontString():SetTextColor(0.8, 0.8, 0.8)  -- Light grey
        end
    end
end

-- ============================================================
-- SUB-PANEL OPENERS
-- ============================================================

local function OpenCooldowns()
    if activePanel == "cooldowns" then
        -- Toggle off
        HideActiveSubPanel()
        HighlightButton(nil)
        return
    end
    HideActiveSubPanel()
    activePanel = "cooldowns"
    HighlightButton("cooldowns")

    local BarsUI = TUICD.BarsUI
    if BarsUI then BarsUI:Show() end
end

local function OpenBuffs()
    if activePanel == "buffs" then
        HideActiveSubPanel()
        HighlightButton(nil)
        return
    end
    HideActiveSubPanel()
    activePanel = "buffs"
    HighlightButton("buffs")

    local BuffBarsUI = TUICD.BuffBarsUI
    if BuffBarsUI then BuffBarsUI:Show() end
end

local function OpenTimeline()
    if activePanel == "timeline" then
        HideActiveSubPanel()
        HighlightButton(nil)
        return
    end
    HideActiveSubPanel()
    activePanel = "timeline"
    HighlightButton("timeline")

    local TimelineUI = TUICD.TimelineUI
    if TimelineUI then TimelineUI:Show() end
end

-- ============================================================
-- CREATE HUB PANEL
-- ============================================================

local function CreateHubPanel()
    if hubPanel then return hubPanel end

    hubPanel = CreateFrame("Frame", "TUICD_BarsHub", UIParent, "BackdropTemplate")
    hubPanel:SetSize(HUB_WIDTH, HUB_HEIGHT)
    hubPanel:SetFrameStrata("HIGH")
    hubPanel:SetFrameLevel(100)
    hubPanel:SetClampedToScreen(true)
    hubPanel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    hubPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    hubPanel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    hubPanel:Hide()

    -- Close button
    local closeBtn = CreateFrame("Button", nil, hubPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() hubPanel:Hide() end)

    -- Title
    local title = hubPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cffffd100Timer Bars|r")

    -- Button layout
    local yOffset = -44

    -- Cooldowns
    local cdBtn = CreateFrame("Button", nil, hubPanel, "UIPanelButtonTemplate")
    cdBtn:SetPoint("TOP", 0, yOffset)
    cdBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    cdBtn:SetText("Cooldowns")
    cdBtn:GetFontString():SetTextColor(1, 0.82, 0)  -- Gold to match main hub
    cdBtn:SetScript("OnClick", OpenCooldowns)
    buttons.cooldowns = cdBtn
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING

    -- Timeline (now enabled!)
    local tlBtn = CreateFrame("Button", nil, hubPanel, "UIPanelButtonTemplate")
    tlBtn:SetPoint("TOP", 0, yOffset)
    tlBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    tlBtn:SetText("Timeline")
    tlBtn:GetFontString():SetTextColor(0.8, 0.8, 0.8)  -- Light grey (inactive)
    tlBtn:SetScript("OnClick", OpenTimeline)
    tlBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Timeline", 1, 0.82, 0)
        GameTooltip:AddLine("Horizontal cooldown timeline display.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tlBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons.timeline = tlBtn
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING

    -- Buffs
    local buffBtn = CreateFrame("Button", nil, hubPanel, "UIPanelButtonTemplate")
    buffBtn:SetPoint("TOP", 0, yOffset)
    buffBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    buffBtn:SetText("Buffs")
    buffBtn:GetFontString():SetTextColor(1, 0.82, 0)  -- Gold to match main hub
    buffBtn:SetScript("OnClick", OpenBuffs)
    buttons.buffs = buffBtn

    -- On hide: close any active sub-panel
    hubPanel:SetScript("OnHide", function()
        HideActiveSubPanel()
        HighlightButton(nil)
    end)

    -- Register for GlobalScale if available
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(hubPanel, 1.0)
    end

    BarsHub.hubPanel = hubPanel
    return hubPanel
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function BarsHub:Show()
    if not hubPanel then CreateHubPanel() end
    DockToMainHub()
    hubPanel:Show()
end

function BarsHub:Hide()
    if hubPanel then hubPanel:Hide() end
end

function BarsHub:IsShown()
    return hubPanel and hubPanel:IsShown()
end

function BarsHub:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--- Get the hub frame (for sub-panels to dock to)
function BarsHub:GetPanel()
    if not hubPanel then CreateHubPanel() end
    return hubPanel
end

return BarsHub
