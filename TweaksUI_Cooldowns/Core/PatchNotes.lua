-- ============================================================================
-- TweaksUI: Cooldowns - Patch Notes System
-- Shows "What's New" popup when addon is updated
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.PatchNotes = {}
local PatchNotes = TUICD.PatchNotes

-- ============================================================================
-- PATCH NOTES CONTENT
-- ============================================================================
-- Update this when releasing new versions

local PATCH_NOTES = [[
|cffffcc00Version 3.0|r - Multi-Tracker & Personal Resources


|cffff8000NEW:|r |cff00ff00Radial Swipe|r

Alternative cooldown animation that draws around the icon edge
instead of the standard darkening sweep.

Available in the Per-Icon tab for any Multi-Tracker icon.
Set the Display State to show during cooldown, then
customize texture, color, scale, and rotation.


|cffff8000NEW:|r |cff00ff00Multi-Tracker System|r

Create up to |cff00ff0010 custom trackers|r with full control!

|cff87CEEBWhere to Find It:|r
  Cooldowns > Custom Trackers

|cff87CEEBGetting Started:|r
  We automatically create copies of your Essential and
  Utility trackers as Multi-Trackers. These can be enabled
  or disabled independently.

|cff87CEEBHow to Create Your Own:|r
  1. Open settings with |cffffff00/tuicd|r
  2. Go to Cooldowns > Custom Trackers
  3. Click the |cffffff00+|r button to create a new tracker
  4. Add spells/items using the Entries tab
  5. Position with |cffffff00/tuicd layout|r

|cff87CEEBBenefits over Essential/Utility:|r
  - Choose exactly which abilities to track
  - Custom grid layouts (rows, columns, spacing)
  - Per-icon settings (size, opacity, hide source)
  - Works across all specs with the same spells

|cff87CEEBCurrent Limitations:|r
  - No stack/charge counts displayed yet
  - Cannot track passive buff auras



|cffff8000NEW:|r |cff00ff00Personal Resources|r

Track your class resources (combo points, holy power, etc.)
with customizable display options!

|cff87CEEBHow to Enable:|r
  1. Open settings with |cffffff00/tuicd|r
  2. Click |cffffff00Personal Resources|r in the hub
  3. Check |cffffff00Enable Module|r at the top


|cff888888Type /tuicd patchnotes to see this again|r
]]

-- ============================================================================
-- UI CREATION
-- ============================================================================

local patchNotesFrame = nil

local function CreatePatchNotesFrame()
    if patchNotesFrame then return patchNotesFrame end
    
    local frame = CreateFrame("Frame", "TUICD_PatchNotesFrame", UIParent, "BackdropTemplate")
    frame:SetSize(480, 550)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    
    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cff00ccffTUI: Cooldowns|r - What's New")
    
    -- Version subtitle
    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("TOP", title, "BOTTOM", 0, -2)
    version:SetText("|cff00ff00v" .. TUICD.VERSION .. "|r")
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)
    
    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(410, 1000)
    scrollFrame:SetScrollChild(content)
    
    -- Notes text
    local notesText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesText:SetPoint("TOPLEFT", 5, -5)
    notesText:SetPoint("TOPRIGHT", -5, -5)
    notesText:SetJustifyH("LEFT")
    notesText:SetJustifyV("TOP")
    notesText:SetSpacing(2)
    notesText:SetText(PATCH_NOTES)
    
    -- Adjust content height based on text
    local textHeight = notesText:GetStringHeight()
    content:SetHeight(textHeight + 20)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- OK button
    local okBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    okBtn:SetSize(100, 24)
    okBtn:SetPoint("BOTTOM", 0, 15)
    okBtn:SetText("OK")
    okBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- ESC to close
    tinsert(UISpecialFrames, "TUICD_PatchNotesFrame")
    
    frame:Hide()
    patchNotesFrame = frame
    return frame
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function PatchNotes:Show()
    local frame = CreatePatchNotesFrame()
    frame:Show()
end

function PatchNotes:Hide()
    if patchNotesFrame then
        patchNotesFrame:Hide()
    end
end

function PatchNotes:Toggle()
    if patchNotesFrame and patchNotesFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Check if we should show patch notes on login
function PatchNotes:CheckVersionAndShow()
    local db = TweaksUI_Cooldowns_DB
    if not db then return end
    
    db.global = db.global or {}
    local lastSeen = db.global.lastSeenVersion
    local current = TUICD.VERSION
    
    -- Show if version changed or first install
    if lastSeen ~= current then
        -- Save that we've seen this version
        db.global.lastSeenVersion = current
        
        -- Delay slightly to ensure UI is ready
        C_Timer.After(2, function()
            self:Show()
        end)
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Check version on PLAYER_LOGIN
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Delay check to ensure database is ready
        C_Timer.After(3, function()
            PatchNotes:CheckVersionAndShow()
        end)
    end
end)
