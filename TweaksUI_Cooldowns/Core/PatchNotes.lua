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
|cffffcc00Version 3.1.5|r - On Ready Effects, Timeline & More


|cffff8000NEW:|r |cff00ff00On Ready Effects|r

Cooldown icons can now glow and pulse when they come
off cooldown, giving you instant visual feedback that
an ability is available again.

|cff87CEEBWhere to Find It:|r
  Cooldown Trackers > Per-Icon tab > On Ready section
  Timer Bars > Cooldowns/Buffs > On Ready tab
  Timeline > On Ready tab

|cff87CEEBFeatures:|r
  - Glow effect when a spell becomes ready
  - Three glow styles: Pixel Border, Shine Flash, Spell Glow
  - Customizable glow color, speed, intensity, thickness
  - Configurable glow duration and timing offset
  - Pulse animation with adjustable scale and count
  - Independent timing controls for glow and pulse
  - Available across all tracker types and Timeline


|cffff8000NEW:|r |cff00ff00Timeline Direction|r

The Timeline module now supports right-to-left mode.
Icons can slide from the right edge toward a ready zone
on the left, or from the left edge toward a ready zone
on the right.

|cff87CEEBWhere to Find It:|r
  Settings Hub > Timer Bars > Timeline > Layout tab

|cff87CEEBFeatures:|r
  - Right to Left: ready zone on left, icons slide left
  - Left to Right: ready zone on right, icons slide right
  - Tick marks and labels adjust to match direction


|cffff8000UPDATED:|r |cff00ff00Personal Resources - Extended Ranges|r

All Personal Resources sliders now support double the
previous maximum values, making it easy to create larger
health bars, power bars, and class power displays.

|cff87CEEBDetails:|r
  - Bar widths up to 800-1000 (was 400-500)
  - Bar heights up to 60-100 (was 30-50)
  - Font sizes up to 32-48 (was 16-24)
  - Scales up to 4x (was 2x)
  - All offset, spacing, and aura ranges doubled
  - Manual entry allows any value beyond slider range


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
