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
|cffffcc00Version 3.3.0|r - Midnight Pre-Patch Survival Update


|cffff0000A Note From the Developer|r

We are two weeks from early access, and this past Tuesday
Blizzard broke a lot of the addon. I've spent all week
trying to get full functionality back, and it's not going
to happen. I'd apologize for that, but honestly I'm just
too tired of fighting the code.

Here's where things stand:


|cffff8000REMOVED:|r |cffff4444Cooldown Bars|r

Unfortunately gone. Blizzard has made all cooldown info
completely secret during combat. I couldn't get bars
working without them flickering on every GCD, which
made them unusable.


|cffff8000REMOVED:|r |cffff4444Cooldown Timeline|r

Gone for the same reasons as Cooldown Bars. Secret
values prevent the positioning and timing logic the
timeline needs to function.


|cffff8000REMOVED:|r |cffff4444Radial Sweep|r

Also gone for the same secret value reasons.


|cff00ff00WORKING:|r |cff87CEEBAlerts|r

Alerts still work, but they're more limited now. I can't
get offset timing to work, so no alerts 3 seconds before
something comes off cooldown. You can still get alerts
when things go on or come off cooldown. This includes
buff alerts and custom sound alerts, as long as the buff
is on the Cooldown Manager.


|cff00ff00WORKING:|r |cff87CEEBCustom / Multi Trackers|r

These work fine. All the info is secret, but I'm just
passing it through to the icons without any comparisons,
so they should continue to work. Fixed a bug where
toggling individual icons didn't take effect until reload.


|cff00ff00WORKING:|r |cff87CEEBOriginal Trackers|r

Switched some things around under the hood and these
should work better now.


|cff00ff00IMPROVED:|r |cff87CEEBBuff Bars|r

These actually work better than before. Got color-by-time-
remaining working, and bars are now keyed by spell ID
rather than slot index, which makes them more reliable.
Buff Bars now open directly from the main settings hub.


|cff00ff00WORKING:|r |cff87CEEBPer-Icon Settings|r

Should work as before.


|cffff8000Going Forward|r

This week's changes were just one more time Blizzard
moved the goal posts. The core of the addon still works
and hopefully should continue to work, but if Blizzard
decides to change even more this late, I probably won't
be chasing it.

After fighting with these changes all week, I'm pretty
tired and pretty frustrated. I plan to keep the addon
working in its current state, but unless I can find some
joy in it again, new features are unlikely. Development
is definitely going to slow down.

I plan to spend some time with my family over the next
couple of weeks, and then I plan on playing some Midnight.

Thanks to everyone who has used the addon and to those
who plan to keep using it. I'm not deleting it and I'm
not abandoning it. Just taking a breather.


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
