-- ============================================================================
-- TUICD Cooldowns Module
-- Hooks Blizzard's Cooldown Manager viewers and applies custom layouts
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Ensure module IDs exist
if not TUICD.MODULE_IDS then return end
if not TUICD.MODULE_IDS.COOLDOWNS then
    TUICD.MODULE_IDS.COOLDOWNS = "cooldowns"
    TUICD.MODULE_NAMES[TUICD.MODULE_IDS.COOLDOWNS] = "Cooldown Trackers"
    table.insert(TUICD.MODULE_LOAD_ORDER, 1, TUICD.MODULE_IDS.COOLDOWNS)
end

-- Create the module
local Cooldowns = TUICD.ModuleManager:NewModule(TUICD.MODULE_IDS.COOLDOWNS)

-- ============================================================================
-- MIDNIGHT API WRAPPERS (v2.0.0)
-- ============================================================================

-- Use centralized API wrappers - no more feature detection needed
local SpellAPI = TUICD.SpellAPI
local DurationAPI = TUICD.DurationAPI
local SecretAPI = TUICD.SecretAPI

-- ============================================================================
-- BLIZZARD VIEWER DEFINITIONS
-- ============================================================================

-- These are the frames Blizzard creates for the Cooldown Manager system
local TRACKERS = {
    { 
        name = "EssentialCooldownViewer", 
        displayName = "Essential Cooldowns", 
        key = "essential",
        isBarType = false 
    },
    { 
        name = "UtilityCooldownViewer", 
        displayName = "Utility Cooldowns", 
        key = "utility",
        isBarType = false 
    },
    { 
        name = "BuffIconCooldownViewer", 
        displayName = "Buff Tracker", 
        key = "buffs",
        isBarType = false 
    },
}

-- ============================================================================
-- VERY EARLY HIDING: Start hiding trackers at FILE LOAD TIME
-- This runs before OnEnable and catches trackers the moment they're created
-- ============================================================================
do
    local earlyHideFrame = CreateFrame("Frame")
    earlyHideFrame.elapsed = 0
    earlyHideFrame:SetScript("OnUpdate", function(self, elapsed)
        -- Check if TUIFrame init is complete
        if TUICD.TUIFrame and TUICD.TUIFrame.IsInitializationComplete 
           and TUICD.TUIFrame.IsInitializationComplete() then
            self:SetScript("OnUpdate", nil)
            return
        end
        
        -- Hide all Blizzard viewers every single frame
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer and viewer:GetAlpha() > 0 then
                viewer:SetAlpha(0)
            end
        end
        
        -- Safety timeout after 10 seconds
        self.elapsed = self.elapsed + elapsed
        if self.elapsed > 10.0 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local HUB_WIDTH = 220
local HUB_HEIGHT = 480
local PANEL_WIDTH = 500
local PANEL_HEIGHT = 600
local BUTTON_HEIGHT = 28
local BUTTON_SPACING = 6

-- Dark backdrop
local darkBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

-- ============================================================================
-- DEFAULT SETTINGS
-- ============================================================================

-- Aspect ratio presets
local ASPECT_PRESETS = {
    { label = "1:1 (Square)", value = "1:1" },
    { label = "4:3", value = "4:3" },
    { label = "3:4", value = "3:4" },
    { label = "16:9 (Wide)", value = "16:9" },
    { label = "9:16 (Tall)", value = "9:16" },
    { label = "2:1", value = "2:1" },
    { label = "1:2", value = "1:2" },
    { label = "Custom", value = "custom" },
}

-- Shared tracker defaults (used by all trackers)
local TRACKER_DEFAULTS = {
    enabled = true,  -- Enable trackers by default so they show when module is enabled
    -- Icon size
    iconSize = 36,              -- Base size (used with aspect ratio)
    iconWidth = nil,            -- Custom width (nil = use iconSize + aspect)
    iconHeight = nil,           -- Custom height (nil = use iconSize + aspect)
    aspectRatio = "1:1",        -- Preset or "custom"
    -- Layout
    columns = 8,
    rows = 0,                   -- 0 = unlimited
    spacingH = 2,               -- Horizontal spacing between icons
    spacingV = 2,               -- Vertical spacing between rows
    growDirection = "RIGHT",    -- PRIMARY: LEFT, RIGHT, UP, or DOWN
    growSecondary = "DOWN",     -- SECONDARY: LEFT, RIGHT, UP, or DOWN
    alignment = "LEFT",         -- LEFT, CENTER, or RIGHT
    reverseOrder = false,
    -- Custom Grid (overrides standard layout when enabled)
    -- useCustomGrid intentionally NOT in defaults - nil allows migration from old customLayout
    customLayout = "",          -- Row pattern like "4,4,2" or "1,0,3" for blank rows
    -- Appearance
    zoom = 0.08,                -- Texture inset (0 = full, higher = more zoom)
    borderAlpha = 1.0,
    iconOpacity = 1.0,          -- Out of combat opacity
    iconOpacityCombat = 1.0,    -- In combat opacity
    iconEdgeStyle = "sharp",    -- "sharp" (zoomed square), "rounded" (masked corners), "square" (no zoom)
    useMasque = false,          -- Use Masque skinning (requires Masque addon)
    -- Behavior
    showTooltip = true,         -- Show tooltips on mouseover
    -- Text - Cooldown numbers
    cooldownTextScale = 1.0,    -- Scale of countdown numbers
    cooldownTextOffsetX = 0,    -- Horizontal offset
    cooldownTextOffsetY = 0,    -- Vertical offset
    cooldownTextColorR = 1.0,   -- Red component
    cooldownTextColorG = 0.82,  -- Green component (default gold color)
    cooldownTextColorB = 0.0,   -- Blue component
    cooldownTextFont = "Default", -- Font name from LibSharedMedia
    -- Text - Stack counts
    countTextScale = 1.0,       -- Scale of stack counts
    countTextOffsetX = 0,       -- Horizontal offset (from default position)
    countTextOffsetY = 0,       -- Vertical offset (from default position)
    countTextColorR = 1.0,      -- Red component
    countTextColorG = 1.0,      -- Green component
    countTextColorB = 1.0,      -- Blue component
    countTextFont = "Default",  -- Font name from LibSharedMedia
    -- Cooldown sweep visibility
    showSweep = true,           -- Show cooldown sweep/spiral animation
    
    showCountdownText = true,   -- Show/hide countdown numbers
    -- Visibility
    visibilityEnabled = false,  -- Master toggle for visibility conditions (false = always show)
    showInCombat = true,
    showOutOfCombat = true,
    showSolo = true,
    showInParty = true,
    showInRaid = true,
    showInInstance = true,
    showInArena = true,
    showInBattleground = true,
    showHasTarget = true,       -- Has a target selected
    showNoTarget = true,        -- No target selected
    showMounted = true,         -- Mounted
    showNotMounted = true,      -- Not mounted
    clickthrough = false,       -- Allow clicks to pass through tracker
    -- Persistent icon order (saved by texture fileID)
    savedIconOrder = {},        -- Array of texture fileIDs in desired order
}

-- Copy defaults for each tracker
local function CreateTrackerDefaults()
    local t = {}
    for k, v in pairs(TRACKER_DEFAULTS) do
        t[k] = v
    end
    return t
end

local DEFAULTS = {
    -- Per-tracker settings (copy shared defaults)
    essential = CreateTrackerDefaults(),
    utility = CreateTrackerDefaults(),
    buffs = CreateTrackerDefaults(),
    -- Global settings
    global = {
        debugMode = false,
    },
    -- Dock settings (4 docks available)
    docks = {},  -- Will be populated with DOCK_DEFAULTS below
}

-- Dock default settings (for Dynamic Docks feature)
local DOCK_DEFAULTS = {
    enabled = false,
    name = "",
    orientation = "horizontal",  -- horizontal or vertical
    justify = "center",          -- left/center/right for horizontal, top/middle/bottom for vertical
    spacing = 4,
    dockAlpha = 1.0,
    -- Background settings
    showBackground = true,
    bgColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.5 },
    -- Border settings
    showBorder = true,
    borderColor = { r = 0.3, g = 0.3, b = 0.3, a = 0.8 },
    -- Visibility
    visibilityEnabled = false,
    showInCombat = true,
    showOutOfCombat = true,
    showSolo = true,
    showInParty = true,
    showInRaid = true,
    showInInstance = true,
    showInArena = true,
    showInBattleground = true,
    showHasTarget = true,
    showNoTarget = true,
    showMounted = true,
    showNotMounted = true,
    fadeAlpha = 0.3,
    -- Position
    point = "CENTER",
    x = 0,
    y = -100,
    -- Visual Override Settings (applies to all icons in dock)
    visualOverrideEnabled = false,
    vo_iconSize = 36,
    vo_opacity = 1.0,
    vo_aspectRatio = "1:1",
    vo_customAspectW = 1,
    vo_customAspectH = 1,
    vo_showSweep = true,
    vo_showCountdownText = true,
    vo_showProcGlow = true,
    -- Cooldown text settings
    vo_cooldownTextScale = 1.0,
    vo_cooldownTextColor = { 1, 1, 1, 1 },
    vo_cooldownTextOffsetX = 0,
    vo_cooldownTextOffsetY = 0,
    vo_cooldownTextAnchor = "CENTER",
    -- Count text settings
    vo_countTextScale = 1.0,
    vo_countTextColor = { 1, 1, 1, 1 },
    vo_countTextOffsetX = 0,
    vo_countTextOffsetY = -2,
    vo_countTextAnchor = "BOTTOMRIGHT",
    -- Custom label settings
    vo_labelEnabled = false,
    vo_labelFontSize = 14,
    vo_labelColor = { 1, 1, 1, 1 },
    vo_labelOffsetX = 0,
    vo_labelOffsetY = 0,
    vo_labelAnchor = "CENTER",
}

-- Initialize dock defaults (4 docks)
local NUM_DOCKS = 4
for i = 1, NUM_DOCKS do
    DEFAULTS.docks[i] = {}
    for k, v in pairs(DOCK_DEFAULTS) do
        if type(v) == "table" then
            DEFAULTS.docks[i][k] = {}
            for kk, vv in pairs(v) do
                DEFAULTS.docks[i][k][kk] = vv
            end
        else
            DEFAULTS.docks[i][k] = v
        end
    end
    -- Set default positions spread out
    DEFAULTS.docks[i].y = -100 - (i - 1) * 60
end

-- Add buff-specific settings
DEFAULTS.buffs.greyscaleInactive = true
DEFAULTS.buffs.inactiveAlpha = 0.5

-- Add customTrackers settings
DEFAULTS.customTrackers = CreateTrackerDefaults()
DEFAULTS.customTrackers.enabled = false  -- Default to disabled for new installs
DEFAULTS.customTrackers.columns = 4  -- Smaller default for custom trackers
DEFAULTS.customTrackers.point = "CENTER"  -- Edit Mode position
DEFAULTS.customTrackers.x = 0
DEFAULTS.customTrackers.y = -200

-- Equipment slots that can have on-use abilities
local TRACKABLE_EQUIPMENT_SLOTS = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
}

-- ============================================================================
-- LOCAL VARIABLES
-- ============================================================================

local settings = nil
local cooldownHub = nil
local settingsPanels = {}
local currentOpenPanel = nil

-- Tracker state
local hookedViewers = {}  -- [viewerFrame] = trackerKey
local baselineOrders = {} -- [viewerFrame] = { icon1, icon2, ... }

-- Update flags (combat-safe pattern)
local needsLayoutUpdate = {}  -- [trackerKey] = true

-- Custom Tracker system
local customTrackerFrame = nil      -- The display frame for custom trackers
local customTrackerIcons = {}       -- [entryKey] = iconFrame (entryKey = "spell_123" or "item_456")
local equippedOnUseItems = {}       -- [slotID] = { itemID, spellID, spellName, texture }
local customTrackerUpdateTicker = nil
local CUSTOM_TRACKER_UPDATE_INTERVAL = 0.1  -- Update cooldowns 10x per second
local trackerIconMasks = {}         -- [icon] = maskTexture for Essential/Utility/Buffs trackers

-- ============================================================================
-- MASQUE SUPPORT
-- ============================================================================

local Masque = nil  -- Deferred lookup - set in InitializeMasque
local MasqueGroups = {}  -- [trackerKey] = MasqueGroup

-- Forward declarations (functions defined after utility functions)
local InitializeMasque
local AddToMasque
local RemoveFromMasque
local ReskinMasqueGroup
local IsMasqueEnabled

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

local function dprint(...)
    if not settings then
        -- Don't initialize settings just for debug output - check database directly
        local dbSettings = TUICD.Database and TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
        if dbSettings and dbSettings.global and dbSettings.global.debugMode then
            print("|cff00ff00[TUICD CD]|r", ...)
        end
        return
    end
    if settings.global and settings.global.debugMode then
        print("|cff00ff00[TUICD CD]|r", ...)
    end
end

local function GetSetting(trackerKey, settingName)
    -- Auto-initialize settings if needed (like TUI:CD does with Database)
    if not settings then
        Cooldowns:GetSettings()  -- This initializes settings from database
    end
    if not settings or not settings[trackerKey] then return nil end
    return settings[trackerKey][settingName]
end

local function SetSetting(trackerKey, settingName, value)
    -- Auto-initialize settings if needed
    if not settings then
        Cooldowns:GetSettings()  -- This initializes settings from database
    end
    if not settings then return end
    settings[trackerKey] = settings[trackerKey] or {}
    settings[trackerKey][settingName] = value
    
    -- Also immediately persist to database
    if TUICD and TUICD.Database and TUICD.Database.SetModuleSettings then
        TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, settings)
    end
end

-- Public function to get all settings (used by Export All)
function Cooldowns:GetSettings()
    -- Ensure settings are initialized with proper merge logic
    if not settings then
        -- Start with defaults
        settings = DeepCopy(DEFAULTS)
        
        -- Merge any saved settings from database (deep copy nested tables)
        local dbSettings = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
        
        if dbSettings then
            for key, trackerSettings in pairs(dbSettings) do
                if settings[key] and type(trackerSettings) == "table" then
                    for k, v in pairs(trackerSettings) do
                        if type(v) == "table" then
                            -- Deep copy nested tables to avoid reference sharing between profiles
                            settings[key][k] = DeepCopy(v)
                        else
                            settings[key][k] = v
                        end
                    end
                elseif key == "global" and type(trackerSettings) == "table" then
                    for k, v in pairs(trackerSettings) do
                        if type(v) == "table" then
                            settings.global[k] = DeepCopy(v)
                        else
                            settings.global[k] = v
                        end
                    end
                end
            end
        end
    end
    
    -- NOTE: Removed automatic write-back to database here.
    -- Writing should only happen explicitly when settings are changed,
    -- not every time they're read. This was causing profile loads to be
    -- overwritten by stale cached settings.
    
    return settings
end

-- Get default settings (used by export/import delta encoding)
function Cooldowns:GetDefaults()
    return DeepCopy(DEFAULTS)
end

-- Refresh settings from database (used when presets are applied)
-- Clears cached settings and reloads from database
function Cooldowns:RefreshFromDatabase()
    -- Clear cached settings to force re-read from database
    settings = nil
    
    -- Re-get settings (this will load fresh from database)
    self:GetSettings()
    
    -- Flag all trackers for layout update
    for _, tracker in ipairs(TRACKERS) do
        needsLayoutUpdate[tracker.key] = true
    end
    needsLayoutUpdate["customTrackers"] = true
    
    -- Update custom tracker frame if it exists
    if customTrackerFrame then
        -- Will be handled by the OnUpdate loop
    end
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("Cooldowns: Refreshed settings from database")
    end
    
    return true
end

local function GetTrackerInfo(key)
    for _, t in ipairs(TRACKERS) do
        if t.key == key then return t end
    end
    return nil
end

-- ============================================================================
-- MASQUE SUPPORT (function implementations)
-- ============================================================================

-- Initialize Masque groups for each tracker
InitializeMasque = function()
    -- Deferred lookup - Masque may not be loaded at file parse time
    if not Masque then
        Masque = LibStub and LibStub("Masque", true)
    end
    
    if not Masque then 
        dprint("Masque not found")
        return false 
    end
    
    -- Create Masque group for each tracker
    local trackerNames = {
        essential = "Essential Cooldowns",
        utility = "Utility Cooldowns", 
        buffs = "Buff Tracker",
        customTrackers = "Custom Trackers",
    }
    
    for key, displayName in pairs(trackerNames) do
        if not MasqueGroups[key] then
            MasqueGroups[key] = Masque:Group("TUICD", displayName)
            dprint(string.format("Masque: Created group for %s", displayName))
        end
    end
    
    -- Register callback for skin changes
    if Masque.RegisterCallback then
        Masque:RegisterCallback("TweaksUI_Cooldowns", function(_, group, skinID)
            dprint(string.format("Masque: Skin changed to %s", skinID or "default"))
            -- Force refresh all layouts when skin changes
            C_Timer.After(0.1, function()
                for _, tracker in ipairs(TRACKERS) do
                    local viewer = _G[tracker.name]
                    if viewer and viewer:IsShown() then
                        needsLayoutUpdate[tracker.key] = true
                    end
                end
                needsLayoutUpdate["customTrackers"] = true
            end)
        end)
    end
    
    dprint("Masque: Initialized successfully")
    return true
end

-- Add a button to a Masque group
AddToMasque = function(trackerKey, button, buttonData)
    if not Masque then return end
    if not GetSetting(trackerKey, "useMasque") then return end
    
    local group = MasqueGroups[trackerKey]
    if not group then return end
    
    -- Build button data for Masque
    -- Masque expects specific texture references
    local data = buttonData or {}
    
    -- Extract standard button elements
    data.Icon = data.Icon or button.Icon or button.icon
    data.Cooldown = data.Cooldown or button.Cooldown or button.cooldown
    data.Normal = data.Normal or (button.GetNormalTexture and button:GetNormalTexture())
    data.Pushed = data.Pushed or (button.GetPushedTexture and button:GetPushedTexture())
    data.Highlight = data.Highlight or (button.GetHighlightTexture and button:GetHighlightTexture())
    data.Border = data.Border or button.Border or button.IconBorder
    data.Count = data.Count or button.Count or button.count
    
    -- Hide existing visual elements that Masque will replace
    pcall(function()
        button._TUI_HiddenElements = button._TUI_HiddenElements or {}
        
        -- Hide backdrop if present
        if button.SetBackdrop then
            button._TUI_OldBackdrop = button:GetBackdrop()
            button:SetBackdrop(nil)
        end
        if button.SetBackdropColor then
            button:SetBackdropColor(0, 0, 0, 0)
        end
        if button.SetBackdropBorderColor then
            button:SetBackdropBorderColor(0, 0, 0, 0)
        end
        
        -- Hide common border elements
        if button.Border then 
            button._TUI_HiddenElements.Border = button.Border:GetAlpha()
            button.Border:SetAlpha(0) 
        end
        if button.border then 
            button._TUI_HiddenElements.border = button.border:GetAlpha()
            button.border:SetAlpha(0) 
        end
        if button.IconBorder then 
            button._TUI_HiddenElements.IconBorder = button.IconBorder:GetAlpha()
            button.IconBorder:SetAlpha(0) 
        end
        if button.iconBorder then 
            button._TUI_HiddenElements.iconBorder = button.iconBorder:GetAlpha()
            button.iconBorder:SetAlpha(0) 
        end
        if button.FloatingBG then 
            button._TUI_HiddenElements.FloatingBG = button.FloatingBG:GetAlpha()
            button.FloatingBG:SetAlpha(0) 
        end
        
        -- Hide NormalTexture if present
        if button.GetNormalTexture then
            local normalTex = button:GetNormalTexture()
            if normalTex then
                button._TUI_HiddenElements.NormalTexture = normalTex:GetAlpha()
                normalTex:SetAlpha(0)
            end
        end
        
        -- AGGRESSIVE: Hide ALL textures except the icon texture
        -- Masque will provide its own border/background
        if button.GetRegions then
            local iconTexture = data.Icon
            button._TUI_HiddenRegions = button._TUI_HiddenRegions or {}
            
            for _, region in ipairs({button:GetRegions()}) do
                if region and region:GetObjectType() == "Texture" then
                    -- Don't hide the main icon texture
                    if region ~= iconTexture then
                        local oldAlpha = region:GetAlpha()
                        if oldAlpha > 0 then
                            button._TUI_HiddenRegions[region] = oldAlpha
                            region:SetAlpha(0)
                        end
                    end
                end
            end
        end
        
        -- Also check children frames for backgrounds
        if button.GetChildren then
            for _, child in ipairs({button:GetChildren()}) do
                -- Skip cooldown frame
                local cd = data.Cooldown
                if child ~= cd and child.GetRegions then
                    for _, region in ipairs({child:GetRegions()}) do
                        if region and region:GetObjectType() == "Texture" then
                            local oldAlpha = region:GetAlpha()
                            if oldAlpha > 0 then
                                button._TUI_HiddenRegions = button._TUI_HiddenRegions or {}
                                button._TUI_HiddenRegions[region] = oldAlpha
                                region:SetAlpha(0)
                            end
                        end
                    end
                end
            end
        end
    end)
    
    -- Add to group
    group:AddButton(button, data)
    button._TUI_MasqueGroup = trackerKey
    
    dprint(string.format("Masque: Added button to %s group", trackerKey))
end

-- Remove a button from its Masque group
RemoveFromMasque = function(button)
    if not Masque then return end
    if not button._TUI_MasqueGroup then return end
    
    local group = MasqueGroups[button._TUI_MasqueGroup]
    if group then
        group:RemoveButton(button)
        dprint(string.format("Masque: Removed button from %s group", button._TUI_MasqueGroup))
    end
    button._TUI_MasqueGroup = nil
    
    -- Restore hidden elements
    pcall(function()
        -- Restore backdrop
        if button._TUI_OldBackdrop and button.SetBackdrop then
            button:SetBackdrop(button._TUI_OldBackdrop)
            button._TUI_OldBackdrop = nil
        end
        
        -- Restore hidden regions
        if button._TUI_HiddenRegions then
            for region, oldAlpha in pairs(button._TUI_HiddenRegions) do
                if region and region.SetAlpha then
                    region:SetAlpha(oldAlpha)
                end
            end
            button._TUI_HiddenRegions = nil
        end
        
        -- Restore common elements
        if button._TUI_HiddenElements then
            if button.Border and button._TUI_HiddenElements.Border then 
                button.Border:SetAlpha(button._TUI_HiddenElements.Border) 
            end
            if button.border and button._TUI_HiddenElements.border then 
                button.border:SetAlpha(button._TUI_HiddenElements.border) 
            end
            if button.IconBorder and button._TUI_HiddenElements.IconBorder then 
                button.IconBorder:SetAlpha(button._TUI_HiddenElements.IconBorder) 
            end
            if button.iconBorder and button._TUI_HiddenElements.iconBorder then 
                button.iconBorder:SetAlpha(button._TUI_HiddenElements.iconBorder) 
            end
            if button.FloatingBG and button._TUI_HiddenElements.FloatingBG then 
                button.FloatingBG:SetAlpha(button._TUI_HiddenElements.FloatingBG) 
            end
            
            if button.GetNormalTexture and button._TUI_HiddenElements.NormalTexture then
                local normalTex = button:GetNormalTexture()
                if normalTex then normalTex:SetAlpha(button._TUI_HiddenElements.NormalTexture) end
            end
            
            button._TUI_HiddenElements = nil
        end
    end)
end

-- Reskin all buttons in a group (call after settings change)
ReskinMasqueGroup = function(trackerKey)
    if not Masque then return end
    local group = MasqueGroups[trackerKey]
    if group then
        group:ReSkin()
        dprint(string.format("Masque: Reskinned %s group", trackerKey))
    end
end

-- Check if Masque is available and enabled for a tracker
IsMasqueEnabled = function(trackerKey)
    return Masque ~= nil and GetSetting(trackerKey, "useMasque") == true
end

-- Public Masque interface
function Cooldowns:IsMasqueAvailable()
    return Masque ~= nil
end

function Cooldowns:GetMasqueGroup(trackerKey)
    return MasqueGroups[trackerKey]
end

function Cooldowns:RefreshMasqueGroup(trackerKey)
    if MasqueGroups[trackerKey] then
        MasqueGroups[trackerKey]:ReSkin()
    end
end

-- ============================================================================
-- ICON COLLECTION
-- ============================================================================

-- Check if a frame is an icon (has Icon texture and typical icon properties)
local function IsIcon(frame)
    if not frame then return false end
    if not frame.GetWidth then return false end
    
    local w, h = frame:GetWidth(), frame:GetHeight()
    if not w or not h or w < 10 or h < 10 then return false end
    
    -- Check for Icon texture (Blizzard's cooldown icons have this)
    if frame.Icon then return true end
    if frame.icon then return true end
    
    -- Check for cooldown element
    if frame.Cooldown then return true end
    if frame.cooldown then return true end
    
    return false
end

-- Collect all icon children from a viewer frame
local function CollectIcons(viewer)
    local icons = {}
    if not viewer or not viewer.GetNumChildren then return icons end
    
    local numChildren = viewer:GetNumChildren() or 0
    
    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        if child and IsIcon(child) then
            icons[#icons + 1] = child
        elseif child and child.GetNumChildren then
            -- Check nested children (some viewers have container frames)
            local numNested = child:GetNumChildren() or 0
            for j = 1, numNested do
                local nested = select(j, child:GetChildren())
                if nested and IsIcon(nested) then
                    icons[#icons + 1] = nested
                end
            end
        end
    end
    
    -- Sort by visual position (top-to-bottom, left-to-right) to match tracker display order
    table.sort(icons, function(a, b)
        local at, bt = a:GetTop() or 0, b:GetTop() or 0
        local al, bl = a:GetLeft() or 0, b:GetLeft() or 0
        -- If roughly same row (within 5 pixels), sort left-to-right
        if math.abs(at - bt) > 5 then
            return at > bt  -- Higher top = earlier in list
        end
        return al < bl  -- Left-most = earlier in list
    end)
    
    return icons
end

-- Get icons in Blizzard's natural child order (no sorting)
-- This is the consistent order used for per-icon settings
local function GetIconsInBlizzardOrder(viewer)
    local icons = {}
    if not viewer or not viewer.GetNumChildren then return icons end
    
    local numChildren = viewer:GetNumChildren() or 0
    
    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        if child and IsIcon(child) and child:IsShown() then
            icons[#icons + 1] = child
        elseif child and child.GetNumChildren then
            local numNested = child:GetNumChildren() or 0
            for j = 1, numNested do
                local nested = select(j, child:GetChildren())
                if nested and IsIcon(nested) and nested:IsShown() then
                    icons[#icons + 1] = nested
                end
            end
        end
    end
    
    return icons
end


-- Get texture fileID from an icon (stable identifier across sessions)
-- Uses pcall to safely handle "secret values" during combat/targeting
local function GetIconTextureID(icon)
    if not icon then return 0 end
    local textureObj = icon.Icon or icon.icon
    if textureObj then
        if textureObj.GetTextureFileID then
            local ok, fileID = pcall(function()
                local id = textureObj:GetTextureFileID()
                if id and id > 0 then return id end
                return nil
            end)
            if ok and fileID then return fileID end
        end
        if textureObj.GetTexture then
            local ok, tex = pcall(function()
                local t = textureObj:GetTexture()
                if type(t) == "number" and t > 0 then return t end
                return nil
            end)
            if ok and tex then return tex end
        end
    end
    return 0
end

-- Session cache for stable icon ordering per tracker
-- Once we establish an order, we keep it stable to prevent icons jumping around
local iconOrderCache = {}  -- [trackerKey] = { icon1, icon2, ... }

-- Original Blizzard child order - captured ONCE per tracker, used for per-icon settings
-- This never changes regardless of layout mode or sorting
local originalBlizzardOrder = {}  -- [trackerKey] = { icon1, icon2, ... }

-- Capture original Blizzard order if not already captured
local function CaptureOriginalOrder(viewer, trackerKey)
    if originalBlizzardOrder[trackerKey] then
        return originalBlizzardOrder[trackerKey]
    end
    
    local icons = {}
    if not viewer or not viewer.GetNumChildren then return icons end
    
    local numChildren = viewer:GetNumChildren() or 0
    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        if child and IsIcon(child) then
            icons[#icons + 1] = child
        elseif child and child.GetNumChildren then
            local numNested = child:GetNumChildren() or 0
            for j = 1, numNested do
                local nested = select(j, child:GetChildren())
                if nested and IsIcon(nested) then
                    icons[#icons + 1] = nested
                end
            end
        end
    end
    
    originalBlizzardOrder[trackerKey] = icons
    dprint(string.format("CaptureOriginalOrder [%s]: Captured %d icons", trackerKey, #icons))
    return icons
end

-- Get original order (captures if needed)
local function GetOriginalOrder(viewer, trackerKey)
    if not originalBlizzardOrder[trackerKey] then
        CaptureOriginalOrder(viewer, trackerKey)
    end
    return originalBlizzardOrder[trackerKey] or {}
end

-- Clear original order cache (call when icons are added/removed)
local function ClearOriginalOrderCache(trackerKey)
    if trackerKey then
        originalBlizzardOrder[trackerKey] = nil
    else
        originalBlizzardOrder = {}
    end
end


-- Sort icons by visual position (reading order: top-to-bottom, left-to-right)
local function SortVisual(a, b)
    local at, bt = a:GetTop() or 0, b:GetTop() or 0
    local al, bl = a:GetLeft() or 0, b:GetLeft() or 0
    
    -- Sort top-to-bottom first (higher Y = higher on screen)
    if math.abs(at - bt) > 5 then return at > bt end
    
    -- Then left-to-right for icons in same row
    return al < bl
end

-- Get icons in stable order
-- Uses session cache for all trackers + persistent savedIconOrder
local function GetOrderedIcons(viewer, trackerKey)
    local all = CollectIcons(viewer)
    local shown = {}
    local shownSet = {}  -- For quick lookup
    
    -- Filter to only shown icons and create lookup set
    for _, icon in ipairs(all) do
        if icon:IsShown() then
            shown[#shown + 1] = icon
            shownSet[icon] = true
        end
    end
    
    if #shown == 0 then
        dprint(string.format("GetOrderedIcons [%s]: 0 shown", trackerKey))
        return shown
    end
    
    dprint(string.format("GetOrderedIcons [%s]: %d total, %d shown", trackerKey, #all, #shown))
    
    -- If no session cache exists, create initial order
    if not iconOrderCache[trackerKey] then
        -- Try to restore from persistent savedIconOrder first (all trackers)
        local savedOrder = GetSetting(trackerKey, "savedIconOrder")
        if savedOrder and #savedOrder > 0 then
            -- Build lookup: fileID -> desired position
            local orderLookup = {}
            for i, fileID in ipairs(savedOrder) do
                orderLookup[fileID] = i
            end
            
            -- Sort by saved position, unknowns go to end sorted by fileID
            table.sort(shown, function(a, b)
                local idA = GetIconTextureID(a)
                local idB = GetIconTextureID(b)
                local posA = orderLookup[idA]
                local posB = orderLookup[idB]
                
                if posA and posB then return posA < posB end
                if posA then return true end
                if posB then return false end
                return idA < idB
            end)
            
            dprint(string.format("GetOrderedIcons [%s]: Restored from saved order (%d entries)", trackerKey, #savedOrder))
        else
            -- No saved order - use visual position for initial capture
            -- This preserves Blizzard's default ordering from Cooldown Manager
            table.sort(shown, SortVisual)
            dprint(string.format("GetOrderedIcons [%s]: No saved order, sorted by visual position", trackerKey))
        end
        
        -- Store in session cache
        iconOrderCache[trackerKey] = {}
        for i, icon in ipairs(shown) do
            iconOrderCache[trackerKey][i] = icon
        end
        
        return shown
    end
    
    -- Session cache exists - use cached order, filter to currently shown icons
    local cached = iconOrderCache[trackerKey]
    local result = {}
    local usedIcons = {}
    
    -- First, add icons from cache that are still shown (preserves order)
    for _, cachedIcon in ipairs(cached) do
        if shownSet[cachedIcon] then
            result[#result + 1] = cachedIcon
            usedIcons[cachedIcon] = true
        end
    end
    
    -- Then add any new icons that weren't in cache (at the end)
    for _, icon in ipairs(shown) do
        if not usedIcons[icon] then
            result[#result + 1] = icon
        end
    end
    
    -- Update session cache with current set
    iconOrderCache[trackerKey] = {}
    for i, icon in ipairs(result) do
        iconOrderCache[trackerKey][i] = icon
    end
    
    return result
end

-- Export GetOrderedIcons for use by CooldownHighlights
Cooldowns.GetOrderedIcons = GetOrderedIcons

-- Clear icon order cache (session cache and optionally persistent savedIconOrder)
local function ClearIconOrderCache(trackerKey, clearPersistent)
    if trackerKey then
        iconOrderCache[trackerKey] = nil
        if clearPersistent then
            SetSetting(trackerKey, "savedIconOrder", {})
        end
        dprint(string.format("Cleared icon order cache for [%s]%s", trackerKey, clearPersistent and " (including persistent)" or ""))
    else
        iconOrderCache = {}
        if clearPersistent then
            -- Clear persistent order for all trackers
            for _, tracker in ipairs(TRACKERS) do
                SetSetting(tracker.key, "savedIconOrder", {})
            end
        end
        dprint(string.format("Cleared all icon order caches%s", clearPersistent and " (including persistent)" or ""))
    end
end

-- ============================================================================
-- LAYOUT SYSTEM
-- ============================================================================

-- Apply border alpha to an icon
local function ApplyBorderAlpha(icon, alpha)
    if not icon then return end
    alpha = alpha or 1.0
    
    pcall(function()
        -- Try common border texture names
        if icon.Border then icon.Border:SetAlpha(alpha) end
        if icon.border then icon.border:SetAlpha(alpha) end
        if icon.IconBorder then icon.IconBorder:SetAlpha(alpha) end
        if icon.iconBorder then icon.iconBorder:SetAlpha(alpha) end
        
        -- Some icons use NormalTexture for the border
        if icon.GetNormalTexture then
            local normalTexture = icon:GetNormalTexture()
            if normalTexture then normalTexture:SetAlpha(alpha) end
        end
        
        -- Search through regions for border textures
        if icon.GetRegions then
            local iconTexture = icon.Icon or icon.icon
            for _, region in ipairs({icon:GetRegions()}) do
                if region and region:GetObjectType() == "Texture" and region ~= iconTexture then
                    local texturePath = region:GetTexture()
                    if texturePath then
                        if type(texturePath) == "string" then
                            -- String path - check for border keywords
                            if texturePath:find("Border") or texturePath:find("border") or 
                               texturePath:find("Highlight") or texturePath:find("Normal") or
                               texturePath:find("Edge") or texturePath:find("Frame") then
                                region:SetAlpha(alpha)
                            end
                        elseif type(texturePath) == "number" then
                            -- Numeric file ID - assume non-icon textures are borders
                            region:SetAlpha(alpha)
                        end
                    end
                end
            end
        end
        
        -- Check children frames for borders
        if icon.GetChildren then
            for _, child in ipairs({icon:GetChildren()}) do
                if child and child:GetObjectType() == "Frame" then
                    local name = child:GetName()
                    if name and (name:find("Border") or name:find("border")) then
                        child:SetAlpha(alpha)
                    end
                end
            end
        end
    end)
end

-- Apply cooldown text scale to an icon
local function ApplyCooldownTextScale(icon, scale, offsetX, offsetY, r, g, b, fontName)
    if not icon then return end
    scale = scale or 1.0
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    
    local cd = icon.Cooldown or icon.cooldown
    if not cd then return end
    
    -- Get font path from LibSharedMedia if specified
    local fontPath = nil
    if fontName and fontName ~= "Default" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            fontPath = LSM:Fetch("font", fontName)
        end
    end
    
    pcall(function()
        -- Helper to apply settings to a fontstring
        local function ApplyToFontString(fs)
            if not fs then return end
            
            -- Mark this as cooldown text so ApplyCountTextScale skips it
            fs._TUI_isCooldownText = true
            
            -- Store original values
            if not fs._TUI_origFontSize then
                local font, size, flags = fs:GetFont()
                if font and size then
                    fs._TUI_origFontSize = size
                    fs._TUI_origFont = font
                    fs._TUI_origFlags = flags or ""
                end
            end
            
            -- Store original position
            if not fs._TUI_origPoint then
                local point, relativeTo, relativePoint, x, y = fs:GetPoint()
                if point then
                    fs._TUI_origPoint = point
                    fs._TUI_origRelativeTo = relativeTo
                    fs._TUI_origRelativePoint = relativePoint
                    fs._TUI_origX = x or 0
                    fs._TUI_origY = y or 0
                end
            end
            
            -- Apply font and scale
            if fs._TUI_origFontSize then
                local useFont = fontPath or fs._TUI_origFont
                fs:SetFont(useFont, fs._TUI_origFontSize * scale, fs._TUI_origFlags)
            end
            
            -- Apply color if specified
            if r and g and b then
                fs:SetTextColor(r, g, b, 1)
            end
            
            -- Apply offset
            if fs._TUI_origPoint and (offsetX ~= 0 or offsetY ~= 0) then
                fs:ClearAllPoints()
                fs:SetPoint(fs._TUI_origPoint, fs._TUI_origRelativeTo, fs._TUI_origRelativePoint, 
                    fs._TUI_origX + offsetX, fs._TUI_origY + offsetY)
            end
        end
        
        -- Method 1: Direct cooldown.text (OmniCC style)
        if cd.text then
            ApplyToFontString(cd.text)
        end
        
        -- Method 2: Check for Text fontstring in cooldown frame
        if cd.Text then
            ApplyToFontString(cd.Text)
        end
        
        -- Method 3: Search cooldown frame regions for fontstrings
        if cd.GetRegions then
            for _, region in ipairs({cd:GetRegions()}) do
                if region and region:GetObjectType() == "FontString" then
                    ApplyToFontString(region)
                end
            end
        end
    end)
end

-- Apply count/charge text scale to an icon
local function ApplyCountTextScale(icon, scale, offsetX, offsetY, r, g, b, fontName)
    if not icon then return end
    scale = scale or 1.0
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    
    -- Get custom font path if specified
    local customFontPath = nil
    if fontName and fontName ~= "Default" and TUICD.Media then
        customFontPath = TUICD.Media:GetFontPath(fontName)
    end
    
    -- Helper to apply all text properties to a fontstring
    local function ApplyTextProperties(fs)
        if not fs or not fs.GetFont then return end
        
        -- Store original values
        if not fs._TUI_origFontSize then
            local font, size, flags = fs:GetFont()
            if font and size then
                fs._TUI_origFontSize = size
                fs._TUI_origFont = font
                fs._TUI_origFlags = flags or ""
            end
        end
        
        -- Apply scale and font
        if fs._TUI_origFontSize then
            local fontToUse = customFontPath or fs._TUI_origFont
            fs:SetFont(fontToUse, fs._TUI_origFontSize * scale, fs._TUI_origFlags)
        end
        
        -- Apply offset
        if (offsetX ~= 0 or offsetY ~= 0) and fs.ClearAllPoints and fs.SetPoint then
            if not fs._TUI_origPoint then
                local point, relativeTo, relPoint, x, y = fs:GetPoint(1)
                if point then
                    fs._TUI_origPoint = point
                    fs._TUI_origRelativeTo = relativeTo
                    fs._TUI_origRelPoint = relPoint or point
                    fs._TUI_origX = x or 0
                    fs._TUI_origY = y or 0
                end
            end
            if fs._TUI_origPoint then
                fs:ClearAllPoints()
                fs:SetPoint(fs._TUI_origPoint, fs._TUI_origRelativeTo, fs._TUI_origRelPoint, 
                           fs._TUI_origX + offsetX, fs._TUI_origY + offsetY)
            end
        end
        
        -- Apply color
        if r and g and b and fs.SetTextColor then
            fs:SetTextColor(r, g, b)
        end
    end
    
    -- Helper to recursively search a frame for FontStrings
    local function SearchFrame(frame, depth)
        if not frame or depth > 5 then return end  -- Limit recursion depth
        
        -- Search regions (direct children textures/fontstrings)
        if frame.GetRegions then
            for _, region in ipairs({frame:GetRegions()}) do
                if region and region:GetObjectType() == "FontString" then
                    -- Check if this looks like a count (small text, usually at corner)
                    local text = region:GetText()
                    local name = region:GetName() or ""
                    -- Scale any fontstring that:
                    -- 1. Has a name containing count/charge/stack
                    -- 2. Or displays a number (but NOT if it's cooldown text)
                    -- 3. Or is positioned at bottom-right (typical count position)
                    if name:lower():find("count") or name:lower():find("charge") or name:lower():find("stack") then
                        ApplyTextProperties(region)
                    elseif text and text:match("^%d+$") then
                        -- Pure number text - but skip if already marked as cooldown text
                        -- or if parent is a Cooldown frame
                        local parent = region:GetParent()
                        local parentType = parent and parent:GetObjectType() or ""
                        local isCooldownText = region._TUI_isCooldownText or 
                                               parentType == "Cooldown" or
                                               (parent and (parent:GetName() or ""):lower():find("cooldown"))
                        if not isCooldownText then
                            ApplyTextProperties(region)
                        end
                    end
                end
            end
        end
        
        -- Search child frames recursively
        if frame.GetChildren then
            for _, child in ipairs({frame:GetChildren()}) do
                if child then
                    local childName = child:GetName() or ""
                    local childType = child:GetObjectType()
                    
                    -- Skip Cooldown frames entirely - their text is handled by ApplyCooldownTextScale
                    if childType == "Cooldown" then
                        -- Don't recurse into cooldown frames
                    elseif childName:lower():find("count") or childName:lower():find("charge") or childName:lower():find("stack") then
                        -- This frame is likely count-related, apply properties to all its fontstrings
                        if child.GetRegions then
                            for _, region in ipairs({child:GetRegions()}) do
                                if region and region:GetObjectType() == "FontString" then
                                    ApplyTextProperties(region)
                                end
                            end
                        end
                        -- Recurse into child frames (but not cooldown frames)
                        SearchFrame(child, depth + 1)
                    else
                        -- Recurse into child frames (but not cooldown frames)
                        SearchFrame(child, depth + 1)
                    end
                end
            end
        end
    end
    
    pcall(function()
        -- Method 1: Direct common count text fields
        local countText = icon.Count or icon.count or icon.CountText or icon.countText
        if countText and not countText._TUI_isCooldownText then
            ApplyTextProperties(countText)
        end
        
        -- Method 2: Check cooldown frame for charge display (but NOT cooldown text)
        local cooldown = icon.Cooldown or icon.cooldown
        if cooldown then
            -- Some cooldown frames have a charges fontstring (separate from countdown)
            if cooldown.Count and not cooldown.Count._TUI_isCooldownText then 
                ApplyTextProperties(cooldown.Count) 
            end
            if cooldown.count and not cooldown.count._TUI_isCooldownText then 
                ApplyTextProperties(cooldown.count) 
            end
            if cooldown.Charges and not cooldown.Charges._TUI_isCooldownText then 
                ApplyTextProperties(cooldown.Charges) 
            end
            if cooldown.charges and not cooldown.charges._TUI_isCooldownText then 
                ApplyTextProperties(cooldown.charges) 
            end
            -- DO NOT search inside cooldown frame - that's where countdown text lives
        end
        
        -- Method 3: Recursive search of icon frame (skips Cooldown frames)
        SearchFrame(icon, 0)
    end)
end

-- Debug helper to dump icon structure
local function DumpIconStructure(icon, trackerKey)
    if not icon then return end
    
    local info = {
        name = icon:GetName() or "unnamed",
        objectType = icon:GetObjectType(),
        fields = {},
        regions = {},
        children = {},
    }
    
    -- Check common fields
    local fieldsToCheck = {"Icon", "icon", "Cooldown", "cooldown", "Count", "count", 
                          "Border", "border", "IconBorder", "NormalTexture"}
    for _, field in ipairs(fieldsToCheck) do
        if icon[field] then
            info.fields[field] = type(icon[field])
        end
    end
    
    -- Get regions
    if icon.GetRegions then
        for i, region in ipairs({icon:GetRegions()}) do
            local regionInfo = {
                type = region:GetObjectType(),
                name = region:GetName(),
            }
            if region:GetObjectType() == "Texture" then
                local tex = region:GetTexture()
                regionInfo.texture = type(tex) == "string" and tex or ("fileID:" .. tostring(tex))
            end
            info.regions[i] = regionInfo
        end
    end
    
    -- Get children
    if icon.GetChildren then
        for i, child in ipairs({icon:GetChildren()}) do
            info.children[i] = {
                type = child:GetObjectType(),
                name = child:GetName(),
            }
        end
    end
    
    dprint(string.format("[%s] Icon structure: %s", trackerKey, info.name))
    dprint(string.format("  Fields: %s", table.concat((function()
        local t = {}
        for k, v in pairs(info.fields) do t[#t+1] = k .. "=" .. v end
        return t
    end)(), ", ")))
    dprint(string.format("  Regions: %d", #info.regions))
    for i, r in ipairs(info.regions) do
        dprint(string.format("    [%d] %s: %s %s", i, r.type, r.name or "nil", r.texture or ""))
    end
    dprint(string.format("  Children: %d", #info.children))
    for i, c in ipairs(info.children) do
        dprint(string.format("    [%d] %s: %s", i, c.type, c.name or "nil"))
    end
end

-- Get or create a mask texture for a tracker icon (Essential/Utility/Buffs)
local function GetOrCreateTrackerIconMask(icon)
    if trackerIconMasks[icon] then
        return trackerIconMasks[icon]
    end
    
    local textureObj = icon.Icon or icon.icon
    if not textureObj then return nil end
    
    -- Create mask texture
    local mask = icon:CreateMaskTexture()
    mask:SetAllPoints(textureObj)
    mask:SetTexture("Interface\\AddOns\\!TUICD\\Media\\Textures\\Masks\\Mask_Rounded", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    
    trackerIconMasks[icon] = mask
    return mask
end

-- Apply edge style to a tracker icon
local function ApplyTrackerIconEdgeStyle(icon, trackerKey, iconWidth, iconHeight)
    -- Check for global icon edge style override first
    local edgeStyle
    if TUICD.Media and TUICD.Media:IsUsingGlobalIconEdgeStyle() then
        edgeStyle = TUICD.Media:GetGlobalIconEdgeStyle() or "sharp"
    else
        edgeStyle = GetSetting(trackerKey, "iconEdgeStyle") or "sharp"
    end
    local zoom = GetSetting(trackerKey, "zoom") or 0.08
    
    local textureObj = icon.Icon or icon.icon
    if not textureObj or not textureObj.SetTexCoord then return end
    
    local mask = trackerIconMasks[icon]
    
    -- Remove existing mask first
    if mask then
        pcall(function() textureObj:RemoveMaskTexture(mask) end)
    end
    
    if edgeStyle == "rounded" then
        -- Full texture for mask-based rounding
        local left, right, top, bottom = 0, 1, 0, 1
        
        -- Still apply aspect ratio cropping if non-square
        if iconWidth and iconHeight then
            if iconWidth > iconHeight then
                local cropAmount = (1 - iconHeight / iconWidth) / 2
                top = cropAmount
                bottom = 1 - cropAmount
            elseif iconHeight > iconWidth then
                local cropAmount = (1 - iconWidth / iconHeight) / 2
                left = cropAmount
                right = 1 - cropAmount
            end
        end
        
        textureObj:SetTexCoord(left, right, top, bottom)
        
        -- Apply mask
        mask = GetOrCreateTrackerIconMask(icon)
        if mask then
            pcall(function() textureObj:AddMaskTexture(mask) end)
        end
    elseif edgeStyle == "square" then
        -- No zoom, full texture (with aspect ratio crop)
        local left, right, top, bottom = 0, 1, 0, 1
        
        if iconWidth and iconHeight then
            if iconWidth > iconHeight then
                local cropAmount = (1 - iconHeight / iconWidth) / 2
                top = cropAmount
                bottom = 1 - cropAmount
            elseif iconHeight > iconWidth then
                local cropAmount = (1 - iconWidth / iconHeight) / 2
                left = cropAmount
                right = 1 - cropAmount
            end
        end
        
        textureObj:SetTexCoord(left, right, top, bottom)
    else
        -- "sharp" (default) - zoom with aspect ratio cropping
        local left = zoom
        local right = 1 - zoom
        local top = zoom
        local bottom = 1 - zoom
        
        if iconWidth and iconHeight then
            if iconWidth > iconHeight then
                local cropAmount = (1 - iconHeight / iconWidth) / 2
                top = top + cropAmount * (1 - 2 * zoom)
                bottom = bottom - cropAmount * (1 - 2 * zoom)
            elseif iconHeight > iconWidth then
                local cropAmount = (1 - iconWidth / iconHeight) / 2
                left = left + cropAmount * (1 - 2 * zoom)
                right = right - cropAmount * (1 - 2 * zoom)
            end
        end
        
        textureObj:SetTexCoord(left, right, top, bottom)
    end
end

-- Helper function to get opacity based on combat state
local function GetCombatAwareOpacity(trackerKey)
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    if inCombat then
        return GetSetting(trackerKey, "iconOpacityCombat") or 1.0
    else
        return GetSetting(trackerKey, "iconOpacity") or 1.0
    end
end

-- Helper function to set up tooltip handling for an icon
-- Essential and Utility trackers have native Blizzard tooltip handlers
-- Buff tracker doesn't have tooltips (Blizzard doesn't provide them for BuffIconCooldownViewer)
local function SetupIconTooltip(icon, trackerKey, slotIndex)
    if not icon then return end
    
    -- Clear old TUI tooltip properties that caused taint issues
    if icon._TUI_cachedSpellId ~= nil then
        icon._TUI_cachedSpellId = nil
    end
    
    -- Buff tracker: no tooltip support (Blizzard doesn't provide handlers)
    if trackerKey == "buffs" then
        return
    end
    
    -- Essential/Utility trackers: respect showTooltip setting
    local showTooltip = GetSetting(trackerKey, "showTooltip")
    
    if showTooltip == false then
        -- User wants tooltips disabled
        if not icon._TUI_TooltipDisabled then
            icon._TUI_SavedOnEnter = icon:GetScript("OnEnter")
            icon._TUI_SavedOnLeave = icon:GetScript("OnLeave")
            icon:SetScript("OnEnter", function() end)
            icon:SetScript("OnLeave", function() end)
            icon._TUI_TooltipDisabled = true
        end
    else
        -- User wants tooltips enabled - restore if we disabled them
        if icon._TUI_TooltipDisabled then
            icon:SetScript("OnEnter", icon._TUI_SavedOnEnter)
            icon:SetScript("OnLeave", icon._TUI_SavedOnLeave)
            icon._TUI_TooltipDisabled = nil
            icon._TUI_SavedOnEnter = nil
            icon._TUI_SavedOnLeave = nil
        end
        -- Otherwise don't touch - Blizzard's native handlers work
    end
end

local function ApplyGridLayout(viewer, trackerKey)
    if not viewer or not viewer:IsShown() then return false end
    
    -- Prevent concurrent layout
    if viewer._TUI_applying then return false end
    viewer._TUI_applying = true
    
    -- Get icons in layout order - this is THE order used for everything
    local icons = GetOrderedIcons(viewer, trackerKey)
    if #icons == 0 then
        viewer._TUI_applying = false
        return false
    end
    
    -- Apply per-icon hide based on layout order
    for idx, icon in ipairs(icons) do
        local isHiddenByPerIcon = false
        if trackerKey == "buffs" then
            isHiddenByPerIcon = TUICD.BuffHighlights and TUICD.BuffHighlights:IsIconHidden(idx)
        else
            isHiddenByPerIcon = TUICD.CooldownHighlights and TUICD.CooldownHighlights:IsIconHidden(trackerKey, idx)
        end
        if isHiddenByPerIcon then
            icon:SetAlpha(0)
            icon._TUI_hiddenByPerIcon = true
        else
            icon._TUI_hiddenByPerIcon = false
        end
    end
    
    -- Get settings
    local iconSize = GetSetting(trackerKey, "iconSize") or 36
    local customWidth = GetSetting(trackerKey, "iconWidth")
    local customHeight = GetSetting(trackerKey, "iconHeight")
    local aspectRatio = GetSetting(trackerKey, "aspectRatio") or "1:1"
    
    local columns = GetSetting(trackerKey, "columns") or 8
    local maxRows = GetSetting(trackerKey, "rows") or 0  -- 0 = unlimited
    local customLayout = GetSetting(trackerKey, "customLayout") or ""
    local spacingH = GetSetting(trackerKey, "spacingH") or 2
    local spacingV = GetSetting(trackerKey, "spacingV") or 2
    
    local growDir = GetSetting(trackerKey, "growDirection") or "RIGHT"
    local growSec = GetSetting(trackerKey, "growSecondary") or "DOWN"
    local alignment = GetSetting(trackerKey, "alignment") or "LEFT"
    local reverseOrder = GetSetting(trackerKey, "reverseOrder") or false
    
    local zoom = GetSetting(trackerKey, "zoom") or 0.08
    local iconOpacity = GetCombatAwareOpacity(trackerKey)
    local borderAlpha = GetSetting(trackerKey, "borderAlpha") or 1.0
    
    local cooldownTextScale = GetSetting(trackerKey, "cooldownTextScale") or 1.0
    local cooldownTextOffsetX = GetSetting(trackerKey, "cooldownTextOffsetX") or 0
    local cooldownTextOffsetY = GetSetting(trackerKey, "cooldownTextOffsetY") or 0
    local cooldownTextColorR = GetSetting(trackerKey, "cooldownTextColorR") or 1.0
    local cooldownTextColorG = GetSetting(trackerKey, "cooldownTextColorG") or 0.82
    local cooldownTextColorB = GetSetting(trackerKey, "cooldownTextColorB") or 0.0
    local cooldownTextFont = GetSetting(trackerKey, "cooldownTextFont") or "Default"
    local countTextScale = GetSetting(trackerKey, "countTextScale") or 1.0
    local countTextOffsetX = GetSetting(trackerKey, "countTextOffsetX") or 0
    local countTextOffsetY = GetSetting(trackerKey, "countTextOffsetY") or 0
    local countTextColorR = GetSetting(trackerKey, "countTextColorR") or 1.0
    local countTextColorG = GetSetting(trackerKey, "countTextColorG") or 1.0
    local countTextColorB = GetSetting(trackerKey, "countTextColorB") or 1.0
    local countTextFont = GetSetting(trackerKey, "countTextFont") or "Default"
    
    -- Cooldown visibility settings (unified sweep)
    
    
    local showSweep = GetSetting(trackerKey, "showSweep")
    
    
    if showSweep == nil then showSweep = true end
    local showCountdownText = GetSetting(trackerKey, "showCountdownText")
    if showCountdownText == nil then showCountdownText = true end
    
    -- Reverse order if needed
    if reverseOrder then
        local reversed = {}
        for i = #icons, 1, -1 do
            reversed[#reversed + 1] = icons[i]
        end
        icons = reversed
    end
    
    -- Calculate icon dimensions
    local iconWidth, iconHeight
    
    if customWidth and customHeight and customWidth > 0 and customHeight > 0 then
        -- Custom pixel dimensions override everything
        iconWidth = customWidth
        iconHeight = customHeight
    elseif aspectRatio == "custom" and customWidth and customHeight then
        -- Custom mode but values set
        iconWidth = customWidth > 0 and customWidth or iconSize
        iconHeight = customHeight > 0 and customHeight or iconSize
    elseif aspectRatio and aspectRatio ~= "1:1" and aspectRatio ~= "custom" then
        -- Aspect ratio preset
        local w, h = aspectRatio:match("(%d+):(%d+)")
        w, h = tonumber(w), tonumber(h)
        if w and h and w > 0 and h > 0 then
            -- Base size is the larger dimension
            if w >= h then
                iconWidth = iconSize
                iconHeight = iconSize * h / w
            else
                iconHeight = iconSize
                iconWidth = iconSize * w / h
            end
        else
            iconWidth, iconHeight = iconSize, iconSize
        end
    else
        -- 1:1 square
        iconWidth, iconHeight = iconSize, iconSize
    end
    
    -- Check if custom grid is enabled
    local useCustomGrid = GetSetting(trackerKey, "useCustomGrid") or false
    local customLayout = GetSetting(trackerKey, "customLayout") or ""
    
    -- Debug: Always print custom grid status
    if settings and settings.global and settings.global.debugMode then
        print(string.format("|cff00ff00[TUI CD]|r ApplyGridLayout [%s]: useCustomGrid=%s, customLayout='%s'", 
            trackerKey, tostring(useCustomGrid), customLayout))
    end
    
    -- Parse custom row pattern if custom grid is enabled
    local customRowSizes = {}
    local useCustomLayout = false
    
    if useCustomGrid then
        -- Custom grid is enabled - parse pattern or default to all icons on one row
        if customLayout ~= "" then
            for num in customLayout:gmatch("(%d+)") do
                local n = tonumber(num)
                if n and n >= 0 then
                    table.insert(customRowSizes, n)
                    if n > 0 then
                        useCustomLayout = true
                    end
                end
            end
            -- If all values were 0, don't use custom layout
            if #customRowSizes > 0 and not useCustomLayout then
                customRowSizes = {}
            end
        end
        
        -- If no valid pattern, default to all icons on one row
        if #customRowSizes == 0 then
            customRowSizes = { #icons }  -- One row with all icons
        end
        useCustomLayout = true
    end
    
    dprint(string.format("ApplyGridLayout [%s]: %d icons, size=%.0fx%.0f, cols=%d, spacingH=%d, spacingV=%d, grow=%s/%s%s", 
        trackerKey, #icons, iconWidth, iconHeight, columns, spacingH, spacingV, growDir, growSec,
        useCustomLayout and string.format(", customGrid=%s (rows=%d)", customLayout ~= "" and customLayout or "default", #customRowSizes) or ""))
    
    -- Determine if primary direction is horizontal or vertical
    local primaryIsHorizontal = (growDir == "LEFT" or growDir == "RIGHT")
    
    -- Enhanced debug for column mode troubleshooting
    dprint(string.format("ApplyGridLayout [%s]: useCustomGrid=%s, useCustomLayout=%s, primaryIsHorizontal=%s", 
        trackerKey, tostring(useCustomGrid), tostring(useCustomLayout), tostring(primaryIsHorizontal)))
    
    -- For vertical primary, we need to know how many rows to use
    local numRows = maxRows
    if not primaryIsHorizontal and numRows == 0 then
        numRows = math.ceil(#icons / columns)
    end
    
    -- Position each icon in grid
    local iconCount = 0
    
    -- CUSTOM GRID MODE: Row or Column based pattern with alignment
    if useCustomLayout and #customRowSizes > 0 then
        -- Hide all icons first
        for _, icon in ipairs(icons) do
            icon:Hide()
        end
        
        -- Get custom grid settings
        local customGridMode = GetSetting(trackerKey, "customGridMode") or "ROW"
        local customGridAlign = GetSetting(trackerKey, "customGridAlign") or (customGridMode == "COLUMN" and "TOP" or "LEFT")
        
        local iconIdx = 1
        local maxPrimary = 0    -- Track the max size in primary direction (width for rows, height for columns)
        local totalSecondary = 0 -- Track total in secondary direction (rows for row mode, columns for column mode)
        
        -- Determine overflow size (use last non-zero pattern value)
        local overflowSize = customRowSizes[#customRowSizes]
        if overflowSize == 0 then
            for i = #customRowSizes, 1, -1 do
                if customRowSizes[i] > 0 then
                    overflowSize = customRowSizes[i]
                    break
                end
            end
        end
        if overflowSize == 0 then overflowSize = columns end
        
        -- Helper function to apply styling to an icon
        local function StyleIcon(icon, currentIconIdx)
            icon:SetSize(iconWidth, iconHeight)
            
            -- Apply opacity (skip if icon is hidden by per-icon settings)
            if not icon._TUI_hiddenByPerIcon then
                if trackerKey ~= "buffs" or not GetSetting("buffs", "greyscaleInactive") then
                    icon:SetAlpha(iconOpacity)
                end
            end
            
            local useMasque = IsMasqueEnabled(trackerKey)
            if not useMasque then
                ApplyBorderAlpha(icon, borderAlpha)
                pcall(function()
                    ApplyTrackerIconEdgeStyle(icon, trackerKey, iconWidth, iconHeight)
                end)
            end
            
            ApplyCooldownTextScale(icon, cooldownTextScale, cooldownTextOffsetX, cooldownTextOffsetY,
                               cooldownTextColorR, cooldownTextColorG, cooldownTextColorB, cooldownTextFont)
            ApplyCountTextScale(icon, countTextScale, countTextOffsetX, countTextOffsetY,
                               countTextColorR, countTextColorG, countTextColorB, countTextFont)
            
            -- Apply cooldown visibility settings (sweep and countdown text)
            local cd = icon.Cooldown or icon.cooldown
            if cd then
                -- Apply current settings
                pcall(function()
                    cd:SetDrawSwipe(showSweep)
                    cd:SetHideCountdownNumbers(not showCountdownText)
                end)
                
                -- Hook SetCooldown to reapply settings after each Blizzard update
                if not cd._TUI_CooldownHooked then
                    cd._TUI_showSweep = showSweep
                    cd._TUI_showCountdownText = showCountdownText
                    hooksecurefunc(cd, "SetCooldown", function(self)
                        pcall(function()
                            self:SetDrawSwipe(self._TUI_showSweep)
                            self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
                        end)
                    end)
                    -- Also hook SetCooldownFromDurationObject for Midnight API
                    if cd.SetCooldownFromDurationObject then
                        hooksecurefunc(cd, "SetCooldownFromDurationObject", function(self)
                            pcall(function()
                                self:SetDrawSwipe(self._TUI_showSweep)
                                self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
                            end)
                        end)
                    end
                    cd._TUI_CooldownHooked = true
                else
                    -- Update stored settings for existing hook
                    cd._TUI_showSweep = showSweep
                    cd._TUI_showCountdownText = showCountdownText
                end
            end
            
            if useMasque and not icon._TUI_MasqueGroup then
                AddToMasque(trackerKey, icon, {
                    Icon = icon.Icon or icon.icon,
                    Cooldown = icon.Cooldown or icon.cooldown,
                    Count = icon.Count or icon.count,
                    Border = icon.Border or icon.IconBorder,
                })
            elseif not useMasque and icon._TUI_MasqueGroup then
                RemoveFromMasque(icon)
            end
            
            -- Set up tooltip handling (pass slotIndex for buff tracker persistent cache)
            SetupIconTooltip(icon, trackerKey, currentIconIdx)
        end
        
        -- Track placed icons for second-pass alignment
        local placedIcons = {}  -- { {icon, primaryIdx, secondaryIdx, groupSize}, ... }
        
        if customGridMode == "COLUMN" then
            -- COLUMN MODE: Fill down (primary), then wrap right (secondary)
            -- Pattern specifies how many icons in each column
            local currentCol = 0
            
            -- Process pattern
            for _, colSize in ipairs(customRowSizes) do
                if colSize == 0 then
                    -- Blank column - just increment column counter
                    currentCol = currentCol + 1
                else
                    local iconsInThisCol = 0
                    for rowIdx = 1, colSize do
                        if iconIdx <= #icons then
                            local icon = icons[iconIdx]
                            iconIdx = iconIdx + 1
                            iconCount = iconCount + 1
                            icon:Show()
                            StyleIcon(icon, iconIdx - 1)
                            table.insert(placedIcons, {icon = icon, col = currentCol, row = rowIdx - 1, groupSize = colSize})
                            iconsInThisCol = iconsInThisCol + 1
                        end
                    end
                    if iconsInThisCol > 0 then
                        maxPrimary = math.max(maxPrimary, iconsInThisCol)
                        totalSecondary = currentCol + 1
                    end
                    currentCol = currentCol + 1
                end
            end
            
            -- Handle overflow icons
            while iconIdx <= #icons do
                local iconsInThisCol = 0
                local overflowStartIdx = #placedIcons + 1  -- Track where overflow icons start
                for rowIdx = 1, overflowSize do
                    if iconIdx <= #icons then
                        local icon = icons[iconIdx]
                        iconIdx = iconIdx + 1
                        iconCount = iconCount + 1
                        icon:Show()
                        StyleIcon(icon, iconIdx - 1)
                        table.insert(placedIcons, {icon = icon, col = currentCol, row = rowIdx - 1, groupSize = 0})  -- Will update after
                        iconsInThisCol = iconsInThisCol + 1
                    end
                end
                -- Update groupSize for all icons in this overflow column to actual count
                for i = overflowStartIdx, #placedIcons do
                    placedIcons[i].groupSize = iconsInThisCol
                end
                if iconsInThisCol > 0 then
                    maxPrimary = math.max(maxPrimary, iconsInThisCol)
                    totalSecondary = currentCol + 1
                end
                currentCol = currentCol + 1
            end
            
            -- Calculate dimensions
            local totalWidth = totalSecondary * iconWidth + math.max(0, totalSecondary - 1) * spacingH
            local totalHeight = maxPrimary * iconHeight + math.max(0, maxPrimary - 1) * spacingV
            
            -- Position icons with alignment
            for _, placed in ipairs(placedIcons) do
                local xOffset = placed.col * (iconWidth + spacingH)
                local yOffset = 0
                
                -- Apply vertical alignment within column
                local actualColSize = placed.groupSize
                local colHeight = actualColSize * iconHeight + math.max(0, actualColSize - 1) * spacingV
                
                if customGridAlign == "CENTER" then
                    yOffset = -(totalHeight - colHeight) / 2
                elseif customGridAlign == "END" then
                    yOffset = -(totalHeight - colHeight)
                end
                -- START alignment: yOffset = 0 (default)
                
                yOffset = yOffset - placed.row * (iconHeight + spacingV)
                
                placed.icon:ClearAllPoints()
                placed.icon:SetPoint("TOPLEFT", viewer, "TOPLEFT", xOffset, yOffset)
            end
            
            dprint(string.format("ApplyGridLayout [%s]: Custom COLUMN grid - %d icons, %d cols, maxHeight=%d, size=%.0fx%.0f, align=%s", 
                trackerKey, iconCount, totalSecondary, maxPrimary, totalWidth, totalHeight, customGridAlign))
            
        else
            -- ROW MODE: Fill right (primary), then wrap down (secondary)
            -- Pattern specifies how many icons in each row
            local currentRow = 0
            
            -- Process pattern
            for _, rowSize in ipairs(customRowSizes) do
                if rowSize == 0 then
                    -- Blank row - just increment row counter
                    currentRow = currentRow + 1
                else
                    local iconsInThisRow = 0
                    for colIdx = 1, rowSize do
                        if iconIdx <= #icons then
                            local icon = icons[iconIdx]
                            iconIdx = iconIdx + 1
                            iconCount = iconCount + 1
                            icon:Show()
                            StyleIcon(icon, iconIdx - 1)
                            table.insert(placedIcons, {icon = icon, col = colIdx - 1, row = currentRow, groupSize = rowSize})
                            iconsInThisRow = iconsInThisRow + 1
                        end
                    end
                    if iconsInThisRow > 0 then
                        maxPrimary = math.max(maxPrimary, iconsInThisRow)
                        totalSecondary = currentRow + 1
                    end
                    currentRow = currentRow + 1
                end
            end
            
            -- Handle overflow icons
            while iconIdx <= #icons do
                local iconsInThisRow = 0
                local overflowStartIdx = #placedIcons + 1  -- Track where overflow icons start
                for colIdx = 1, overflowSize do
                    if iconIdx <= #icons then
                        local icon = icons[iconIdx]
                        iconIdx = iconIdx + 1
                        iconCount = iconCount + 1
                        icon:Show()
                        StyleIcon(icon, iconIdx - 1)
                        table.insert(placedIcons, {icon = icon, col = colIdx - 1, row = currentRow, groupSize = 0})  -- Will update after
                        iconsInThisRow = iconsInThisRow + 1
                    end
                end
                -- Update groupSize for all icons in this overflow row to actual count
                for i = overflowStartIdx, #placedIcons do
                    placedIcons[i].groupSize = iconsInThisRow
                end
                if iconsInThisRow > 0 then
                    maxPrimary = math.max(maxPrimary, iconsInThisRow)
                    totalSecondary = currentRow + 1
                end
                currentRow = currentRow + 1
            end
            
            -- Calculate dimensions
            local totalWidth = maxPrimary * iconWidth + math.max(0, maxPrimary - 1) * spacingH
            local totalHeight = totalSecondary * iconHeight + math.max(0, totalSecondary - 1) * spacingV
            
            -- Position icons with alignment
            for _, placed in ipairs(placedIcons) do
                local yOffset = -placed.row * (iconHeight + spacingV)
                local xOffset = 0
                
                -- Apply horizontal alignment within row
                local actualRowSize = placed.groupSize
                local rowWidth = actualRowSize * iconWidth + math.max(0, actualRowSize - 1) * spacingH
                
                if customGridAlign == "CENTER" then
                    xOffset = (totalWidth - rowWidth) / 2
                elseif customGridAlign == "END" then
                    xOffset = totalWidth - rowWidth
                end
                -- START alignment: xOffset = 0 (default)
                
                xOffset = xOffset + placed.col * (iconWidth + spacingH)
                
                placed.icon:ClearAllPoints()
                placed.icon:SetPoint("TOPLEFT", viewer, "TOPLEFT", xOffset, yOffset)
            end
            
            dprint(string.format("ApplyGridLayout [%s]: Custom ROW grid - %d icons, %d rows, maxWidth=%d, size=%.0fx%.0f, align=%s", 
                trackerKey, iconCount, totalSecondary, maxPrimary, totalWidth, totalHeight, customGridAlign))
        end
        
        -- Save icon order
        if iconCount > 0 then
            local newOrder = {}
            for i, icon in ipairs(icons) do
                newOrder[i] = GetIconTextureID(icon)
            end
            local savedOrder = GetSetting(trackerKey, "savedIconOrder") or {}
            local orderChanged = #newOrder ~= #savedOrder
            if not orderChanged then
                for i, texId in ipairs(newOrder) do
                    if savedOrder[i] ~= texId then
                        orderChanged = true
                        break
                    end
                end
            end
            if orderChanged then
                SetSetting(trackerKey, "savedIconOrder", newOrder, true)
            end
        end
        
        -- Update container size to match new layout (for Layout Mode overlay)
        if TUICD.CooldownContainers and TUICD.CooldownContainers.UpdateContainerSize then
            C_Timer.After(0.05, function()
                TUICD.CooldownContainers:UpdateContainerSize(trackerKey)
            end)
        end
        
        viewer._TUI_applying = false
        dprint(string.format("ApplyGridLayout [%s]: Complete with custom grid (%d visible)", trackerKey, iconCount))
        return  -- Early return for custom grid
    end
    
    -- STANDARD GRID LAYOUT (respects direction, alignment, secondary direction)
    dprint(string.format("ApplyGridLayout [%s]: Using STANDARD grid layout, primaryIsHorizontal=%s, numRows=%d", 
        trackerKey, tostring(primaryIsHorizontal), numRows))
    
    for i, icon in ipairs(icons) do
        local col, row
        local idx = i - 1
        
        if primaryIsHorizontal then
            -- Horizontal primary (LEFT/RIGHT): fill rows first, then wrap to next row
            -- Row 1: 1,2,3 | Row 2: 4,5,6 | Row 3: 7,8,9
            col = idx % columns
            row = math.floor(idx / columns)
        else
            -- Vertical primary (UP/DOWN): fill columns first, then wrap to next column
            -- Col 1: 1,4,7 | Col 2: 2,5,8 | Col 3: 3,6,9
            local effectiveRows = numRows > 0 and numRows or math.ceil(#icons / columns)
            row = idx % effectiveRows
            col = math.floor(idx / effectiveRows)
        end
        
        -- Check row limit (0 = unlimited)
        if maxRows > 0 and row >= maxRows then
            -- Hide icons beyond row limit
            icon:Hide()
        else
            iconCount = iconCount + 1
            icon:Show()
            
            -- Calculate offset based on grow direction
            local xOffset, yOffset
            
            -- Primary direction determines the "fast" axis
            -- Secondary direction determines the "slow" axis (wrap direction)
            if growDir == "RIGHT" then
                xOffset = col * (iconWidth + spacingH)
            elseif growDir == "LEFT" then
                xOffset = -col * (iconWidth + spacingH)
            elseif growDir == "DOWN" then
                -- Vertical primary: col determines horizontal offset
                if growSec == "RIGHT" then
                    xOffset = col * (iconWidth + spacingH)
                else  -- LEFT
                    xOffset = -col * (iconWidth + spacingH)
                end
            elseif growDir == "UP" then
                -- Vertical primary: col determines horizontal offset
                if growSec == "RIGHT" then
                    xOffset = col * (iconWidth + spacingH)
                else  -- LEFT
                    xOffset = -col * (iconWidth + spacingH)
                end
            else
                xOffset = col * (iconWidth + spacingH)
            end
            
            if growDir == "DOWN" then
                yOffset = -row * (iconHeight + spacingV)
            elseif growDir == "UP" then
                yOffset = row * (iconHeight + spacingV)
            elseif growSec == "DOWN" then
                yOffset = -row * (iconHeight + spacingV)
            elseif growSec == "UP" then
                yOffset = row * (iconHeight + spacingV)
            else
                yOffset = -row * (iconHeight + spacingV)
            end
            
            -- Calculate alignment offset
            local alignOffsetX = 0
            local alignOffsetY = 0
            
            if primaryIsHorizontal then
                -- Horizontal primary: alignment affects horizontal positioning
                if alignment == "CENTER" or alignment == "RIGHT" then
                    -- Calculate actual icons in this row
                    local iconsBeforeThisRow = row * columns
                    local iconsRemaining = #icons - iconsBeforeThisRow
                    local iconsInThisRow = math.min(columns, iconsRemaining)
                    
                    local rowWidth = iconsInThisRow * iconWidth + (iconsInThisRow - 1) * spacingH
                    local viewerWidth = viewer:GetWidth() or rowWidth
                    
                    if alignment == "CENTER" then
                        alignOffsetX = (viewerWidth - rowWidth) / 2
                    else -- RIGHT
                        alignOffsetX = viewerWidth - rowWidth
                    end
                end
            else
                -- Vertical primary (column mode): alignment affects vertical positioning
                -- LEFT = Top, CENTER = Middle, RIGHT = Bottom
                if alignment == "CENTER" or alignment == "RIGHT" then
                    -- Calculate actual icons in this column
                    local effectiveRows = numRows > 0 and numRows or math.ceil(#icons / columns)
                    local iconsBeforeThisCol = col * effectiveRows
                    local iconsRemaining = #icons - iconsBeforeThisCol
                    local iconsInThisCol = math.min(effectiveRows, iconsRemaining)
                    
                    local colHeight = iconsInThisCol * iconHeight + (iconsInThisCol - 1) * spacingV
                    local viewerHeight = viewer:GetHeight() or colHeight
                    
                    if alignment == "CENTER" then
                        alignOffsetY = -(viewerHeight - colHeight) / 2
                    else -- RIGHT (means Bottom in column mode)
                        alignOffsetY = -(viewerHeight - colHeight)
                    end
                end
            end
            
            -- Apply position relative to viewer with alignment
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", viewer, "TOPLEFT", xOffset + alignOffsetX, yOffset + alignOffsetY)
            
            -- Apply size
            icon:SetSize(iconWidth, iconHeight)
            
            -- Apply opacity (per-icon hide is applied after visual slots are assigned)
            if trackerKey ~= "buffs" or not GetSetting("buffs", "greyscaleInactive") then
                -- Only set alpha here if not buffs with greyscale enabled
                -- (buff state ticker handles alpha for buffs with greyscale)
                icon:SetAlpha(iconOpacity)
            end
            
            -- Check if Masque is handling appearance
            local useMasque = IsMasqueEnabled(trackerKey)
            
            -- Apply border alpha using helper function (skip if Masque is handling it)
            if not useMasque then
                ApplyBorderAlpha(icon, borderAlpha)
            end
            
            -- Apply icon edge style (skip if Masque is handling it)
            if not useMasque then
                pcall(function()
                    ApplyTrackerIconEdgeStyle(icon, trackerKey, iconWidth, iconHeight)
                end)
            end
            
            -- Apply cooldown text settings (scale, offset, color, font)
            ApplyCooldownTextScale(icon, cooldownTextScale, cooldownTextOffsetX, cooldownTextOffsetY,
                               cooldownTextColorR, cooldownTextColorG, cooldownTextColorB, cooldownTextFont)
            
            -- Apply count text settings (scale, offset, color, font)
            ApplyCountTextScale(icon, countTextScale, countTextOffsetX, countTextOffsetY,
                               countTextColorR, countTextColorG, countTextColorB, countTextFont)
            
            -- Apply cooldown visibility settings (sweep and countdown text)
            local cd = icon.Cooldown or icon.cooldown
            if cd then
                -- Apply current settings
                pcall(function()
                    cd:SetDrawSwipe(showSweep)
                    cd:SetHideCountdownNumbers(not showCountdownText)
                end)
                
                -- Hook SetCooldown to reapply settings after each Blizzard update
                if not cd._TUI_CooldownHooked then
                    cd._TUI_showSweep = showSweep
                    cd._TUI_showCountdownText = showCountdownText
                    hooksecurefunc(cd, "SetCooldown", function(self)
                        pcall(function()
                            self:SetDrawSwipe(self._TUI_showSweep)
                            self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
                        end)
                    end)
                    -- Also hook SetCooldownFromDurationObject for Midnight API
                    if cd.SetCooldownFromDurationObject then
                        hooksecurefunc(cd, "SetCooldownFromDurationObject", function(self)
                            pcall(function()
                                self:SetDrawSwipe(self._TUI_showSweep)
                                self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
                            end)
                        end)
                    end
                    cd._TUI_CooldownHooked = true
                else
                    -- Update stored settings for existing hook
                    cd._TUI_showSweep = showSweep
                    cd._TUI_showCountdownText = showCountdownText
                end
            end
            
            -- Add to Masque if enabled and not already added
            if useMasque and not icon._TUI_MasqueGroup then
                AddToMasque(trackerKey, icon, {
                    Icon = icon.Icon or icon.icon,
                    Cooldown = icon.Cooldown or icon.cooldown,
                    Count = icon.Count or icon.count,
                    Border = icon.Border or icon.IconBorder,
                })
            -- Remove from Masque if disabled but was previously added
            elseif not useMasque and icon._TUI_MasqueGroup then
                RemoveFromMasque(icon)
            end
            
            -- Set up tooltip handling (pass slot index for buff tracker persistent cache)
            SetupIconTooltip(icon, trackerKey, i)
            
            -- Debug: dump first icon structure when debug mode enabled
            if iconCount == 1 and GetSetting("global", "debugMode") then
                DumpIconStructure(icon, trackerKey)
            end
        end
    end
    
    -- Calculate total layout dimensions for Edit Mode frame sizing
    local totalCols, totalRows
    if useCustomLayout and #customRowSizes > 0 then
        -- Custom grid: find max row width and count rows (including blank rows)
        totalCols = 0
        for _, rowSize in ipairs(customRowSizes) do
            totalCols = math.max(totalCols, rowSize)
        end
        totalRows = #customRowSizes
    elseif primaryIsHorizontal then
        -- Horizontal primary (LEFT/RIGHT): fills rows first
        totalCols = math.min(#icons, columns)
        totalRows = math.ceil(#icons / columns)
        if maxRows > 0 then
            totalRows = math.min(totalRows, maxRows)
        end
    else
        -- Vertical primary (UP/DOWN): fills columns first
        local effectiveRows = numRows > 0 and numRows or math.ceil(#icons / columns)
        totalRows = math.min(#icons, effectiveRows)
        totalCols = math.ceil(#icons / effectiveRows)
    end
    
    -- Calculate total dimensions
    local totalWidth = totalCols * iconWidth + math.max(0, totalCols - 1) * spacingH
    local totalHeight = totalRows * iconHeight + math.max(0, totalRows - 1) * spacingV
    
    -- NOTE: We don't resize Blizzard's tracker frames (essential, utility, buffs)
    -- because doing so shifts the TOPLEFT corner where icons are positioned,
    -- causing icons to jump when Edit Mode opens/closes. Blizzard's selection
    -- boxes won't perfectly match our layout, but icons stay in place.
    
    -- Save the icon order we just applied (for all trackers)
    -- This ensures the order persists across sessions and profile changes
    if iconCount > 0 then
        local newOrder = {}
        for i, icon in ipairs(icons) do
            newOrder[i] = GetIconTextureID(icon)
        end
        
        -- Only save if order actually differs from saved (avoid unnecessary writes)
        local savedOrder = GetSetting(trackerKey, "savedIconOrder") or {}
        local orderChanged = #newOrder ~= #savedOrder
        if not orderChanged then
            for i, id in ipairs(newOrder) do
                if savedOrder[i] ~= id then
                    orderChanged = true
                    break
                end
            end
        end
        
        if orderChanged then
            SetSetting(trackerKey, "savedIconOrder", newOrder)
            dprint(string.format("ApplyGridLayout [%s]: Saved icon order (%d icons)", trackerKey, #newOrder))
        end
    end
    
    viewer._TUI_applying = false
    dprint(string.format("ApplyGridLayout [%s]: Complete (%d visible)", trackerKey, iconCount))
    
    -- Update container size to match new layout (for Layout Mode overlay)
    if TUICD.CooldownContainers and TUICD.CooldownContainers.UpdateContainerSize then
        C_Timer.After(0.05, function()
            TUICD.CooldownContainers:UpdateContainerSize(trackerKey)
        end)
    end
    
    return true
end

-- Public function to refresh a tracker's layout (called from Highlights modules)
function Cooldowns.RefreshTrackerLayout(trackerKey)
    if trackerKey == "custom" or trackerKey == "customTrackers" then
        -- For custom trackers, refresh via LayoutCustomTrackerIcons
        local customTrackerFrame = _G["TweaksUI_CustomTrackerFrame"]
        if customTrackerFrame and customTrackerFrame:IsShown() then
            C_Timer.After(0, function()
                if TUICD.Cooldowns.LayoutCustomTrackerIcons then
                    TUICD.Cooldowns.LayoutCustomTrackerIcons()
                end
            end)
        end
    elseif trackerKey == "buffs" then
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer and viewer:IsShown() then
            C_Timer.After(0, function()
                pcall(ApplyGridLayout, viewer, "buffs")
            end)
        end
    else
        -- For Essential/Utility trackers
        local viewerName
        for _, tracker in ipairs(TRACKERS) do
            if tracker.key == trackerKey then
                viewerName = tracker.name
                break
            end
        end
        if viewerName then
            local viewer = _G[viewerName]
            if viewer and viewer:IsShown() then
                C_Timer.After(0, function()
                    pcall(ApplyGridLayout, viewer, trackerKey)
                end)
            end
        end
    end
end

-- Placeholder for InvalidateBuffStateCache - will be set after buffStateCache is defined
Cooldowns.InvalidateBuffStateCache = function() end

-- ============================================================================
-- BUFF STATE TRACKING (Buffs tracker only)
-- ============================================================================
-- Detects active vs inactive buffs and applies visual styling
-- Inactive buffs are desaturated and faded for better awareness
--
-- CRITICAL INSIGHT from CMT:
-- The icon's auraInstanceID tells us if the buff is active!
-- - auraInstanceID ~= nil means buff is ACTIVE
-- - auraInstanceID == nil means buff is INACTIVE
-- No need to query C_UnitAuras at all!

local buffStateCache = {}  -- [icon] = lastActiveState (boolean)
local buffUpdateTicker = nil
local BUFF_UPDATE_INTERVAL = 0.1  -- Check buff states 10 times per second

-- Now that buffStateCache is defined, set the real InvalidateBuffStateCache function
Cooldowns.InvalidateBuffStateCache = function(slotIndex)
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then return end
    
    local icons = CollectIcons(viewer)
    local icon = icons[slotIndex]
    if icon then
        buffStateCache[icon] = nil  -- Clear cache entry to force re-apply on next tick
    end
end

-- Check if a buff icon is currently active
-- Simple check: if icon has auraInstanceID, buff is active
local function IsIconBuffActive(icon)
    if not icon then return true end  -- Default to active if we can't check
    
    -- The magic: auraInstanceID is set when buff is active, nil when inactive
    return (icon.auraInstanceID ~= nil)
end

-- Apply visual state to a buff icon based on active/inactive
-- Now supports comprehensive per-icon overrides including size, offset, aspect ratio
local function ApplyBuffVisualState(icon, isActive, trackerKey, iconIndex)
    if not icon then return end
    trackerKey = trackerKey or "buffs"
    
    -- Check if this icon is hidden by per-icon settings
    if iconIndex and TUICD.BuffHighlights and TUICD.BuffHighlights:IsIconHidden(iconIndex) then
        icon:SetAlpha(0)
        return  -- Don't apply any other visual state
    end
    
    -- Get settings
    local greyscaleInactive = GetSetting(trackerKey, "greyscaleInactive")
    local inactiveAlpha = GetSetting(trackerKey, "inactiveAlpha") or 0.5
    local baseOpacity = GetCombatAwareOpacity(trackerKey)
    
    -- Skip if greyscale feature is disabled
    if not greyscaleInactive then
        pcall(function()
            local textureObj = icon.Icon or icon.icon
            if textureObj and textureObj.SetDesaturated then
                textureObj:SetDesaturated(false)
            end
            icon:SetAlpha(baseOpacity)
        end)
        return
    end
    
    -- Check if state changed (avoid unnecessary updates)
    if buffStateCache[icon] == isActive then
        return  -- No change
    end
    
    buffStateCache[icon] = isActive
    dprint(string.format("Buff state: %s (auraInstanceID: %s)", 
        isActive and "ACTIVE" or "INACTIVE",
        tostring(icon.auraInstanceID)))
    
    -- Apply visual changes
    pcall(function()
        local textureObj = icon.Icon or icon.icon
        if isActive then
            -- Active buff - normal appearance
            if textureObj and textureObj.SetDesaturated then
                textureObj:SetDesaturated(false)
            end
            icon:SetAlpha(baseOpacity)
        else
            -- Inactive buff - desaturate and fade
            if textureObj and textureObj.SetDesaturated then
                textureObj:SetDesaturated(true)
            end
            icon:SetAlpha(inactiveAlpha)
        end
    end)
end

-- Update all buff icons' visual states
local function UpdateBuffVisualStates()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer:IsShown() then return end
    
    -- Get all icons
    local icons = CollectIcons(viewer)
    
    local activeCount, inactiveCount = 0, 0
    for i, icon in ipairs(icons) do
        if icon:IsShown() then
            local isActive = IsIconBuffActive(icon)
            if isActive then
                activeCount = activeCount + 1
            else
                inactiveCount = inactiveCount + 1
            end
            ApplyBuffVisualState(icon, isActive, "buffs", i)
        end
    end
    
    dprint(string.format("Buff icons: %d active, %d inactive", activeCount, inactiveCount))
end

-- Start the buff state update ticker
local function StartBuffStateTracking()
    if buffUpdateTicker then return end  -- Already running
    
    buffUpdateTicker = C_Timer.NewTicker(BUFF_UPDATE_INTERVAL, function()
        -- Only run if greyscale feature is enabled
        if GetSetting("buffs", "greyscaleInactive") then
            pcall(UpdateBuffVisualStates)
        end
    end)
    
    dprint("Buff state tracking started")
end

-- Stop the buff state update ticker
local function StopBuffStateTracking()
    if buffUpdateTicker then
        buffUpdateTicker:Cancel()
        buffUpdateTicker = nil
        dprint("Buff state tracking stopped")
    end
end

-- ============================================================================
-- RANGE INDICATOR CONTROL (Essential/Utility trackers only)
-- ============================================================================
-- We create our own overlay and neutralize Blizzard's built-in one
-- Only applies to Essential and Utility trackers (not Buffs - those aren't abilities)

-- ============================================================================
-- CUSTOM TRACKER SYSTEM
-- ============================================================================
-- Allows users to track custom spells/items and equipped on-use items
-- All entries stored in unified array for reordering

-- Entry types:
-- { type = "spell", id = spellID }
-- { type = "item", id = itemID }
-- { type = "equipped", id = slotID }  -- Tracks whatever is in that slot

-- Initialize per-character custom tracker data
local function InitializeCustomTrackerData()
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = {}
    end
    
    TweaksUI_Cooldowns_CharDB.cooldowns = TweaksUI_Cooldowns_CharDB.cooldowns or {}
    TweaksUI_Cooldowns_CharDB.cooldowns.customEntries = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries or {}
    TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache = TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache or {}
end

-- Get current spec ID
local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return specID
end

-- Get custom entries for current spec (unified list)
local function GetCurrentSpecEntries()
    InitializeCustomTrackerData()
    
    local specID = GetCurrentSpecID()
    if not specID then return {} end
    
    TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] or {}
    return TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID]
end

-- Check if an entry already exists
local function EntryExists(entryType, entryID)
    local entries = GetCurrentSpecEntries()
    for _, entry in ipairs(entries) do
        if entry.type == entryType and entry.id == entryID then
            return true
        end
    end
    return false
end

-- Add a custom entry (spell, item, or equipped slot)
local function AddCustomEntry(entryType, idOrName)
    InitializeCustomTrackerData()
    
    local specID = GetCurrentSpecID()
    if not specID then
        return false, "Could not determine current spec"
    end
    
    TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] or {}
    local entries = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID]
    
    local entryID
    local entryName, entryTexture
    
    if entryType == "spell" then
        -- Try to parse as ID first
        local numID = tonumber(idOrName)
        if numID then
            local spellInfo = SpellAPI:GetSpellInfo(numID)
            if spellInfo then
                entryID = numID
                entryName = spellInfo.name
                entryTexture = SpellAPI:GetSpellTexture(numID)
            else
                return false, "Spell ID not found: " .. numID
            end
        else
            -- Try to find by name
            local spellInfo = SpellAPI:GetSpellInfo(idOrName)
            if spellInfo then
                entryID = spellInfo.spellID
                entryName = spellInfo.name
                entryTexture = SpellAPI:GetSpellTexture(entryID)
            else
                return false, "Spell not found: " .. idOrName
            end
        end
        
    elseif entryType == "item" then
        -- Try to parse as ID first
        local numID = tonumber(idOrName)
        if numID then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(numID)
            if itemName then
                entryID = numID
                entryName = itemName
                entryTexture = itemTexture
            else
                -- Item not cached, try to load it
                C_Item.RequestLoadItemDataByID(numID)
                entryID = numID
                entryName = "Loading..."
                entryTexture = nil
            end
        else
            -- Try to find by name - this is tricky without ID
            local itemID = C_Item.GetItemIDForItemInfo(idOrName)
            if itemID then
                entryID = itemID
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                entryName = itemName or "Loading..."
                entryTexture = itemTexture
            else
                return false, "Item not found: " .. idOrName
            end
        end
        
    elseif entryType == "equipped" then
        -- For equipped slots, idOrName should be the slot ID
        local slotID = tonumber(idOrName)
        if not slotID then
            return false, "Invalid slot ID"
        end
        if not TRACKABLE_EQUIPMENT_SLOTS[slotID] then
            return false, "Invalid equipment slot: " .. slotID
        end
        entryID = slotID
        entryName = TRACKABLE_EQUIPMENT_SLOTS[slotID]
        
    else
        return false, "Invalid entry type: " .. tostring(entryType)
    end
    
    -- Check for duplicates
    if EntryExists(entryType, entryID) then
        return false, "Already tracking this " .. entryType
    end
    
    -- Add entry with enabled flag
    table.insert(entries, {
        type = entryType,
        id = entryID,
        enabled = true,  -- Default to enabled
    })
    
    -- Cache info for spells/items
    if entryType == "spell" or entryType == "item" then
        local cacheKey = entryType .. "_" .. entryID
        TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache[cacheKey] = {
            name = entryName,
            texture = entryTexture,
        }
    end
    
    -- Auto-enable custom tracker when first entry is added
    if not GetSetting("customTrackers", "enabled") then
        SetSetting("customTrackers", "enabled", true)
        dprint("Auto-enabled custom tracker for first entry")
    end
    
    dprint(string.format("Added custom entry: %s %d (%s)", entryType, entryID, entryName or "unknown"))
    return true, "Added: " .. (entryName or entryType .. " " .. entryID)
end

-- Remove a custom entry by index
local function RemoveCustomEntry(index)
    local entries = GetCurrentSpecEntries()
    if index < 1 or index > #entries then return false end
    
    local removed = table.remove(entries, index)
    if removed then
        dprint(string.format("Removed custom entry: %s %d", removed.type, removed.id))
        return true
    end
    return false
end

-- Set entry enabled state
local function SetCustomEntryEnabled(index, enabled)
    local entries = GetCurrentSpecEntries()
    if index < 1 or index > #entries then return false end
    
    entries[index].enabled = enabled
    return true
end

-- Move entry from one position to another
local function MoveCustomEntry(fromIndex, toIndex)
    local entries = GetCurrentSpecEntries()
    if fromIndex < 1 or fromIndex > #entries then return false end
    if toIndex < 1 or toIndex > #entries then return false end
    if fromIndex == toIndex then return false end
    
    local entry = table.remove(entries, fromIndex)
    table.insert(entries, toIndex, entry)
    
    dprint(string.format("Moved entry from %d to %d", fromIndex, toIndex))
    return true
end

-- Check if an item has an on-use ability
local function HasOnUseAbility(itemID)
    if not itemID then return false end
    local spellName, spellID = GetItemSpell(itemID)
    return spellName ~= nil, spellID, spellName
end

-- Scan equipped items for on-use abilities
local function ScanEquippedOnUseItems()
    local items = {}
    
    for slotID, slotName in pairs(TRACKABLE_EQUIPMENT_SLOTS) do
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local hasOnUse, spellID, spellName = HasOnUseAbility(itemID)
            if hasOnUse then
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                items[slotID] = {
                    itemID = itemID,
                    spellID = spellID,
                    spellName = spellName,
                    itemName = itemName or "Loading...",
                    texture = itemTexture,
                    slotName = slotName,
                }
            end
        end
    end
    
    return items
end

-- Get info for an entry (handles all types)
local function GetEntryDisplayInfo(entry)
    if entry.type == "spell" then
        local cacheKey = "spell_" .. entry.id
        local cached = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.cooldowns and TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache and TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache[cacheKey]
        
        if cached and cached.name and cached.texture then
            return cached.name, cached.texture, entry.id
        end
        
        local spellInfo = SpellAPI:GetSpellInfo(entry.id)
        local texture = SpellAPI:GetSpellTexture(entry.id)
        local name = spellInfo and spellInfo.name or "Unknown Spell"
        
        -- Update cache
        if TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.cooldowns then
            TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache = TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache or {}
            TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache[cacheKey] = { name = name, texture = texture }
        end
        
        return name, texture, entry.id
        
    elseif entry.type == "item" then
        local cacheKey = "item_" .. entry.id
        local cached = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.cooldowns and TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache and TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache[cacheKey]
        
        if cached and cached.name and cached.texture then
            return cached.name, cached.texture, entry.id
        end
        
        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(entry.id)
        
        if itemName and itemTexture then
            -- Update cache
            if TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.cooldowns then
                TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache = TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache or {}
                TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache[cacheKey] = { name = itemName, texture = itemTexture }
            end
            return itemName, itemTexture, entry.id
        end
        
        -- Request load
        C_Item.RequestLoadItemDataByID(entry.id)
        return "Loading...", nil, entry.id
        
    elseif entry.type == "equipped" then
        local slotID = entry.id
        local slotName = TRACKABLE_EQUIPMENT_SLOTS[slotID] or "Slot " .. slotID
        
        -- Get current item in slot
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            local hasOnUse = HasOnUseAbility(itemID)
            
            if itemName then
                if hasOnUse then
                    return string.format("%s (%s)", itemName, slotName), itemTexture, itemID
                else
                    -- Item exists but has no on-use ability
                    return string.format("%s (%s) - No on-use", itemName, slotName), itemTexture, itemID, false
                end
            else
                C_Item.RequestLoadItemDataByID(itemID)
                return string.format("Loading... (%s)", slotName), nil, itemID
            end
        else
            return string.format("Empty (%s)", slotName), "Interface\\PaperDoll\\UI-Backpack-EmptySlot", nil
        end
    end
    
    return "Unknown", nil, nil
end

-- Get the actual item/spell ID to use for cooldown tracking
local function GetEntryTrackingID(entry)
    if entry.type == "spell" then
        return "spell", entry.id
    elseif entry.type == "item" then
        return "item", entry.id
    elseif entry.type == "equipped" then
        local itemID = GetInventoryItemID("player", entry.id)
        if itemID then
            return "item", itemID
        end
        return nil, nil
    end
    return nil, nil
end

-- Create a custom tracker icon from an entry
local function CreateCustomTrackerIcon(entry, parent)
    -- Get display info based on entry type
    local displayName, displayTexture, trackingID = GetEntryDisplayInfo(entry)
    
    if not displayTexture then
        dprint(string.format("CreateCustomTrackerIcon: No texture for %s %d", entry.type, entry.id))
        return nil
    end
    
    -- For tracking purposes, get the actual ID to track cooldowns
    local trackType, trackID = GetEntryTrackingID(entry)
    
    -- Generate unique key
    local entryKey = entry.type .. "_" .. entry.id
    
    -- Create button frame
    local frame = CreateFrame("Button", "TweaksUI_CustomTracker_" .. entryKey, parent)
    frame:SetSize(36, 36)
    
    -- Create icon texture
    local icon = frame:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(frame)
    icon:SetTexture(displayTexture)
    
    -- Create mask texture for rounded corners (hidden by default)
    local iconMask = frame:CreateMaskTexture()
    iconMask:SetAllPoints(icon)
    iconMask:SetTexture("Interface\\AddOns\\!TUICD\\Media\\Textures\\Masks\\Mask_Rounded", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    
    -- Apply initial edge style
    local trackerKey = "customTrackers"
    local edgeStyle = GetSetting(trackerKey, "iconEdgeStyle") or "sharp"
    local zoom = GetSetting(trackerKey, "zoom") or 0.08
    
    if edgeStyle == "rounded" then
        icon:SetTexCoord(0, 1, 0, 1)  -- Full texture for mask
        icon:AddMaskTexture(iconMask)
    elseif edgeStyle == "square" then
        icon:SetTexCoord(0, 1, 0, 1)  -- No zoom
    else  -- "sharp" (default)
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    end
    
    -- Create cooldown frame overlay
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints(frame)
    cd:SetDrawEdge(true)
    cd:SetDrawSwipe(true)
    cd:SetSwipeColor(0, 0, 0, 0.8)
    cd:SetHideCountdownNumbers(false)
    
    -- Count text (for items with stacks or spell charges)
    local countText = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    countText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    countText:SetJustifyH("RIGHT")
    countText:SetTextColor(1, 1, 1, 1)
    countText:SetShadowOffset(1, -1)
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetDrawLayer("OVERLAY", 7)
    countText:Hide()
    
    -- Store references
    frame.icon = icon
    frame.Icon = icon
    frame.iconMask = iconMask
    frame.cooldown = cd
    frame.Cooldown = cd
    frame.count = countText
    frame.entry = entry           -- Store the full entry
    frame.entryType = entry.type  -- For backwards compat
    frame.entryID = entry.id
    frame.entryKey = entryKey
    frame.entryName = displayName
    frame.trackType = trackType   -- Actual type for cooldown tracking
    frame.trackID = trackID       -- Actual ID for cooldown tracking
    
    -- Enable mouse for tooltips
    frame:EnableMouse(true)
    
    -- Tooltips - use simple tooltips to avoid taint from vendor price MoneyFrame
    frame:SetScript("OnEnter", function(self)
        if InCombatLockdown() then return end
        
        -- Check if tooltips are disabled for this tracker
        if GetSetting(trackerKey, "showTooltip") == false then return end
        
        pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local tType, tID = GetEntryTrackingID(self.entry)
            if tType == "item" and tID then
                -- Use SetHyperlink which is safer than SetItemByID for taint
                local itemLink = select(2, GetItemInfo(tID))
                if itemLink then
                    GameTooltip:SetHyperlink(itemLink)
                else
                    -- Fallback to simple display
                    local itemName = GetItemInfo(tID)
                    GameTooltip:AddLine(itemName or self.entryName or "Item", 1, 1, 1)
                    GameTooltip:AddLine("Item ID: " .. tID, 0.7, 0.7, 0.7)
                end
            elseif tType == "spell" and tID then
                GameTooltip:SetSpellByID(tID)
            else
                GameTooltip:AddLine(self.entryName or "Unknown")
            end
            GameTooltip:Show()
        end)
    end)
    
    frame:SetScript("OnLeave", function()
        if not InCombatLockdown() then
            GameTooltip:Hide()
        end
    end)
    
    dprint(string.format("Created custom tracker icon: %s %d (%s)", entry.type, entry.id, displayName or "?"))
    
    return frame
end

-- Update cooldown for a custom tracker icon
local function UpdateCustomTrackerCooldown(iconFrame)
    if not iconFrame or not iconFrame.cooldown then return end
    
    -- Get tracking info (may change for equipped slots)
    local trackType, trackID = GetEntryTrackingID(iconFrame.entry)
    
    -- Update icon texture if equipped item changed
    if iconFrame.entry.type == "equipped" then
        local displayName, displayTexture, newTrackID = GetEntryDisplayInfo(iconFrame.entry)
        if displayTexture and iconFrame.icon then
            iconFrame.icon:SetTexture(displayTexture)
        end
        iconFrame.trackID = newTrackID
        trackID = newTrackID
    end
    
    if not trackType or not trackID then
        pcall(function() iconFrame.cooldown:Clear() end)
        pcall(function() iconFrame.count:Hide() end)
        -- Reset desaturation when no tracking
        pcall(function() 
            if iconFrame.icon and iconFrame.icon.SetDesaturated then
                iconFrame.icon:SetDesaturated(false)
            end
        end)
        return
    end
    
    -- Track if we're actually on cooldown (for desaturation)
    local isOnCooldown = false
    local GCD_THRESHOLD = 2.0  -- Filter out GCD (typically 1.5s)
    
    if trackType == "item" then
        local start, duration, enable = C_Container.GetItemCooldown(trackID)
        if start and duration and duration > 0 then
            pcall(function() iconFrame.cooldown:SetCooldown(start, duration) end)
            -- Check if actually on cooldown (not just GCD) with remaining time
            local remaining = (start + duration) - GetTime()
            if duration > GCD_THRESHOLD and remaining > 0.1 then
                isOnCooldown = true
            end
        else
            pcall(function() iconFrame.cooldown:Clear() end)
        end
        
        -- Update count
        pcall(function()
            local count = C_Item.GetItemCount(trackID, false, false, false)
            if count and count > 1 then
                iconFrame.count:SetText(count)
                iconFrame.count:Show()
            else
                iconFrame.count:Hide()
            end
        end)
        
    elseif trackType == "spell" then
        -- =====================================================================
        -- SPELL COOLDOWN - Midnight API compatible
        -- Use Duration Objects which handle secret values internally
        -- CRITICAL: During combat, cooldown values are SECRET - don't try to
        -- read them directly or do arithmetic on them!
        -- =====================================================================
        local cooldownSet = false
        
        -- Check if we're in a restricted state (combat, encounter, M+, etc.)
        local isRestricted = InCombatLockdown()
        
        -- Try charges cooldown first (C_Spell.GetSpellChargesCooldownDuration)
        -- Duration Objects are safe to use with SetCooldownFromDurationObject
        if C_Spell.GetSpellChargesCooldownDuration then
            pcall(function()
                local chargeDuration = C_Spell.GetSpellChargesCooldownDuration(trackID)
                if chargeDuration then
                    iconFrame.cooldown:SetCooldownFromDurationObject(chargeDuration, true)
                    cooldownSet = true
                end
            end)
        end
        
        -- If no charge cooldown, try regular cooldown Duration Object
        if not cooldownSet and C_Spell.GetSpellCooldownDuration then
            pcall(function()
                local duration = C_Spell.GetSpellCooldownDuration(trackID)
                if duration then
                    iconFrame.cooldown:SetCooldownFromDurationObject(duration, true)
                    cooldownSet = true
                end
            end)
        end
        
        -- Traditional API fallback - ONLY when not in combat
        -- During combat, info.startTime and info.duration are SECRET values
        -- and cannot be passed to SetCooldown or used in arithmetic
        if not cooldownSet and not isRestricted then
            pcall(function()
                local info = C_Spell.GetSpellCooldown(trackID)
                if info and info.duration and info.startTime then
                    if info.duration > 0 then
                        iconFrame.cooldown:SetCooldown(info.startTime, info.duration)
                    else
                        iconFrame.cooldown:Clear()
                    end
                    cooldownSet = true
                end
            end)
        end
        
        -- IMPORTANT: Don't call Clear() during combat!
        -- If Duration Object APIs didn't set a cooldown, just leave it alone.
        -- Calling Clear() every tick when APIs fail causes flashing.
        if not cooldownSet and not isRestricted then
            pcall(function() iconFrame.cooldown:Clear() end)
        end
        
        -- Desaturation check - ONLY when not in combat
        -- During combat, we cannot read cooldown values (they're secret)
        -- so we skip desaturation updates - the visual cooldown swipe is enough
        if not isRestricted then
            pcall(function()
                local info = C_Spell.GetSpellCooldown(trackID)
                if info and info.duration and info.startTime then
                    local duration = info.duration
                    local remaining = (info.startTime + duration) - GetTime()
                    if duration > GCD_THRESHOLD and remaining > 0.1 then
                        isOnCooldown = true
                    end
                end
            end)
        end
        
        -- =====================================================================
        -- CHARGE/COUNT DISPLAY - Use Midnight's GetSpellDisplayCount API
        -- This handles secret values internally and returns proper display string
        -- =====================================================================
        local countSet = false
        
        -- Primary: Use C_Spell.GetSpellDisplayCount (Midnight API)
        if C_Spell.GetSpellDisplayCount then
            pcall(function()
                local displayCount = C_Spell.GetSpellDisplayCount(trackID)
                iconFrame.count:SetText(displayCount or "")
                iconFrame.count:Show()
                countSet = true
            end)
        end
        
        -- Fallback: Try GetSpellCharges (only when not in combat)
        if not countSet and not isRestricted then
            pcall(function()
                local chargesInfo = C_Spell.GetSpellCharges(trackID)
                if chargesInfo and chargesInfo.maxCharges and chargesInfo.maxCharges > 1 then
                    iconFrame.count:SetText(chargesInfo.currentCharges)
                    iconFrame.count:Show()
                else
                    iconFrame.count:Hide()
                end
            end)
        elseif not countSet then
            -- During combat without GetSpellDisplayCount, just hide count
            iconFrame.count:Hide()
        end
    end
    
    -- Apply desaturation based on cooldown state
    -- Note: During combat, isOnCooldown may be false even when on cooldown
    -- because we can't read secret values. This is acceptable - the swipe is visible.
    pcall(function()
        if iconFrame.icon and iconFrame.icon.SetDesaturated then
            iconFrame.icon:SetDesaturated(isOnCooldown)
        end
    end)
end

-- Apply edge style settings to all custom tracker icons
local function ApplyCustomTrackerEdgeStyles()
    local trackerKey = "customTrackers"
    
    -- Check for global icon edge style override first
    local edgeStyle
    if TUICD.Media and TUICD.Media:IsUsingGlobalIconEdgeStyle() then
        edgeStyle = TUICD.Media:GetGlobalIconEdgeStyle() or "sharp"
    else
        edgeStyle = GetSetting(trackerKey, "iconEdgeStyle") or "sharp"
    end
    local zoom = GetSetting(trackerKey, "zoom") or 0.08
    
    for key, iconFrame in pairs(customTrackerIcons) do
        local icon = iconFrame.icon
        local iconMask = iconFrame.iconMask
        
        if icon then
            -- Remove existing mask first
            if iconMask then
                icon:RemoveMaskTexture(iconMask)
            end
            
            if edgeStyle == "rounded" then
                icon:SetTexCoord(0, 1, 0, 1)  -- Full texture for mask
                if iconMask then
                    icon:AddMaskTexture(iconMask)
                end
            elseif edgeStyle == "square" then
                icon:SetTexCoord(0, 1, 0, 1)  -- No zoom
            else  -- "sharp" (default)
                icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            end
        end
    end
end

-- Create the custom tracker display frame
local function CreateCustomTrackerFrame()
    if customTrackerFrame then return customTrackerFrame end
    
    -- Load saved position
    local trackerKey = "customTrackers"
    local savedPoint = GetSetting(trackerKey, "point") or "CENTER"
    local savedX = GetSetting(trackerKey, "x") or 0
    local savedY = GetSetting(trackerKey, "y") or -200
    
    -- Always print this on startup so we can see what's loaded
    dprint(string.format("Creating custom tracker at: %s, %.1f, %.1f", savedPoint, savedX, savedY))
    
    local frame = CreateFrame("Frame", "TweaksUI_CustomTrackerFrame", UIParent)
    frame:SetSize(200, 50)
    frame:SetPoint(savedPoint, savedX, savedY)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    
    -- Container for icons
    frame.icons = {}
    
    -- Layout registration is done separately after frame is fully set up
    -- See RegisterCooldownsWithLayout()
    
    customTrackerFrame = frame
    
    return frame
end

-- ========================================
-- VISIBILITY SYSTEM FOR CUSTOM TRACKERS
-- ========================================

-- Check if custom tracker frame should be visible based on conditions
local function ShouldShowCustomTrackers()
    -- Force all visible mode bypasses all visibility conditions
    if TUICD.forceAllVisible then
        return true
    end
    
    -- Always show in Edit Mode for positioning
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return true
    end
    
    local trackerKey = "customTrackers"
    
    -- Check if visibility conditions are enabled
    if not GetSetting(trackerKey, "visibilityEnabled") then
        return true  -- Always show if conditions not enabled
    end
    
    local shouldShow = false
    
    -- Combat state
    local inCombat = UnitAffectingCombat("player")
    if inCombat and GetSetting(trackerKey, "showInCombat") then
        shouldShow = true
    end
    if not inCombat and GetSetting(trackerKey, "showOutOfCombat") then
        shouldShow = true
    end
    
    -- Group state
    local inRaid = IsInRaid()
    local inParty = IsInGroup() and not inRaid
    local solo = not IsInGroup()
    
    if solo and GetSetting(trackerKey, "showSolo") then
        shouldShow = true
    end
    if inParty and GetSetting(trackerKey, "showInParty") then
        shouldShow = true
    end
    if inRaid and GetSetting(trackerKey, "showInRaid") then
        shouldShow = true
    end
    
    -- Instance type
    local _, instanceType = IsInInstance()
    if instanceType == "party" and GetSetting(trackerKey, "showInInstance") then
        shouldShow = true
    end
    if instanceType == "arena" and GetSetting(trackerKey, "showInArena") then
        shouldShow = true
    end
    if instanceType == "pvp" and GetSetting(trackerKey, "showInBattleground") then
        shouldShow = true
    end
    
    -- Target state
    local hasTarget = UnitExists("target")
    if hasTarget and GetSetting(trackerKey, "showHasTarget") then
        shouldShow = true
    end
    if not hasTarget and GetSetting(trackerKey, "showNoTarget") then
        shouldShow = true
    end
    
    return shouldShow
end

-- Update custom tracker visibility
local function UpdateCustomTrackerVisibility()
    if not customTrackerFrame then return end
    
    -- Always show in Edit Mode for positioning
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        customTrackerFrame:Show()
        customTrackerFrame:SetAlpha(1.0)
        return
    end
    
    -- Check if hidden via per-icon settings
    local CooldownHighlights = TUICD.CooldownHighlights
    if CooldownHighlights and CooldownHighlights:IsTrackerHidden("custom") then
        customTrackerFrame:Hide()
        return
    end
    
    -- Check if enabled at all
    if not GetSetting("customTrackers", "enabled") then
        customTrackerFrame:Hide()
        return
    end
    
    local shouldShow = ShouldShowCustomTrackers()
    local trackerKey = "customTrackers"
    
    if shouldShow then
        customTrackerFrame:Show()
        customTrackerFrame:SetAlpha(GetCombatAwareOpacity(trackerKey))
    else
        customTrackerFrame:Hide()
    end
end

-- Helper to count table entries
local function CountTableEntries(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Layout custom tracker icons in grid (same logic as ApplyGridLayout)
local function LayoutCustomTrackerIcons()
    if not customTrackerFrame then return end
    
    -- Collect all icons (including hidden) and sort by listIndex
    local allIcons = {}
    for key, iconFrame in pairs(customTrackerIcons) do
        allIcons[#allIcons + 1] = iconFrame
    end
    
    -- Sort by listIndex to get consistent order for per-icon settings
    table.sort(allIcons, function(a, b)
        return (a.listIndex or 0) < (b.listIndex or 0)
    end)
    
    -- Apply per-icon hide BEFORE layout based on listIndex order
    for idx, icon in ipairs(allIcons) do
        local isHiddenByPerIcon = TUICD.CooldownHighlights and TUICD.CooldownHighlights:IsIconHidden("custom", idx)
        if isHiddenByPerIcon then
            icon:SetAlpha(0)
            icon._TUI_hiddenByPerIcon = true
        else
            icon._TUI_hiddenByPerIcon = false
        end
    end
    
    -- Now filter to only visible icons for layout
    local icons = {}
    for _, iconFrame in ipairs(allIcons) do
        if iconFrame:IsShown() then
            icons[#icons + 1] = iconFrame
        end
    end
    
    if #icons == 0 then
        -- Only show placeholder during Edit Mode
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            -- Create or show placeholder for empty frame (for Edit Mode visibility)
            if not customTrackerFrame.placeholder then
                local placeholder = customTrackerFrame:CreateTexture(nil, "BACKGROUND")
                placeholder:SetAllPoints()
                placeholder:SetColorTexture(0.2, 0.2, 0.2, 0.3)
                customTrackerFrame.placeholder = placeholder
                
                local placeholderText = customTrackerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                placeholderText:SetPoint("CENTER")
                placeholderText:SetText("|cff888888Custom\nTrackers|r")
                placeholderText:SetJustifyH("CENTER")
                customTrackerFrame.placeholderText = placeholderText
            end
            customTrackerFrame.placeholder:Show()
            customTrackerFrame.placeholderText:Show()
            customTrackerFrame:SetSize(50, 50)  -- Minimum size for Edit Mode visibility
            customTrackerFrame:Show()
        else
            -- Hide placeholder outside Edit Mode
            if customTrackerFrame.placeholder then
                customTrackerFrame.placeholder:Hide()
                customTrackerFrame.placeholderText:Hide()
            end
        end
        return
    else
        -- Hide placeholder when we have icons
        if customTrackerFrame.placeholder then
            customTrackerFrame.placeholder:Hide()
            customTrackerFrame.placeholderText:Hide()
        end
    end
    
    -- Get settings (same as other trackers)
    local trackerKey = "customTrackers"
    local iconSize = GetSetting(trackerKey, "iconSize") or 36
    local customWidth = GetSetting(trackerKey, "iconWidth")
    local customHeight = GetSetting(trackerKey, "iconHeight")
    local aspectRatio = GetSetting(trackerKey, "aspectRatio") or "1:1"
    
    local columns = GetSetting(trackerKey, "columns") or 4
    local maxRows = GetSetting(trackerKey, "rows") or 0
    local customLayout = GetSetting(trackerKey, "customLayout") or ""
    local spacingH = GetSetting(trackerKey, "spacingH") or 2
    local spacingV = GetSetting(trackerKey, "spacingV") or 2
    
    local growDir = GetSetting(trackerKey, "growDirection") or "RIGHT"
    local growSec = GetSetting(trackerKey, "growSecondary") or "DOWN"
    local alignment = GetSetting(trackerKey, "alignment") or "LEFT"
    local reverseOrder = GetSetting(trackerKey, "reverseOrder") or false
    
    local zoom = GetSetting(trackerKey, "zoom") or 0.08
    local iconOpacity = GetCombatAwareOpacity(trackerKey)
    local borderAlpha = GetSetting(trackerKey, "borderAlpha") or 1.0
    local cooldownTextScale = GetSetting(trackerKey, "cooldownTextScale") or 1.0
    local cooldownTextOffsetX = GetSetting(trackerKey, "cooldownTextOffsetX") or 0
    local cooldownTextOffsetY = GetSetting(trackerKey, "cooldownTextOffsetY") or 0
    local cooldownTextColorR = GetSetting(trackerKey, "cooldownTextColorR") or 1.0
    local cooldownTextColorG = GetSetting(trackerKey, "cooldownTextColorG") or 0.82
    local cooldownTextColorB = GetSetting(trackerKey, "cooldownTextColorB") or 0.0
    local cooldownTextFont = GetSetting(trackerKey, "cooldownTextFont") or "Default"
    local countTextScale = GetSetting(trackerKey, "countTextScale") or 1.0
    local countTextOffsetX = GetSetting(trackerKey, "countTextOffsetX") or 0
    local countTextOffsetY = GetSetting(trackerKey, "countTextOffsetY") or 0
    local countTextColorR = GetSetting(trackerKey, "countTextColorR") or 1.0
    local countTextColorG = GetSetting(trackerKey, "countTextColorG") or 1.0
    local countTextColorB = GetSetting(trackerKey, "countTextColorB") or 1.0
    local countTextFont = GetSetting(trackerKey, "countTextFont") or "Default"
    
    -- Cooldown visibility settings (unified sweep)
    
    
    local showSweep = GetSetting(trackerKey, "showSweep")
    
    
    if showSweep == nil then showSweep = true end
    local showCountdownText = GetSetting(trackerKey, "showCountdownText")
    if showCountdownText == nil then showCountdownText = true end
    
    -- Reverse order if needed
    if reverseOrder then
        local reversed = {}
        for i = #icons, 1, -1 do
            reversed[#reversed + 1] = icons[i]
        end
        icons = reversed
    end
    
    -- Calculate icon dimensions
    local iconWidth, iconHeight
    
    if customWidth and customHeight and customWidth > 0 and customHeight > 0 then
        iconWidth = customWidth
        iconHeight = customHeight
    elseif aspectRatio == "custom" and customWidth and customHeight then
        iconWidth = customWidth > 0 and customWidth or iconSize
        iconHeight = customHeight > 0 and customHeight or iconSize
    elseif aspectRatio and aspectRatio ~= "1:1" and aspectRatio ~= "custom" then
        local w, h = aspectRatio:match("(%d+):(%d+)")
        w, h = tonumber(w), tonumber(h)
        if w and h and w > 0 and h > 0 then
            if w >= h then
                iconWidth = iconSize
                iconHeight = iconSize * h / w
            else
                iconHeight = iconSize
                iconWidth = iconSize * w / h
            end
        else
            iconWidth, iconHeight = iconSize, iconSize
        end
    else
        iconWidth, iconHeight = iconSize, iconSize
    end
    
    -- Check if custom grid is enabled
    local useCustomGrid = GetSetting(trackerKey, "useCustomGrid") or false
    
    -- Debug: Always print custom grid status for custom trackers
    if settings and settings.global and settings.global.debugMode then
        print(string.format("|cff00ff00[TUI CD]|r LayoutCustomTrackerIcons: useCustomGrid=%s, customLayout='%s'", 
            tostring(useCustomGrid), customLayout))
    end
    
    -- Parse custom row pattern if custom grid is enabled
    local customRowSizes = {}
    local useCustomLayout = false
    
    if useCustomGrid then
        -- Custom grid is enabled - parse pattern or default to all icons on one row
        if customLayout ~= "" then
            for num in customLayout:gmatch("(%d+)") do
                local n = tonumber(num)
                if n and n >= 0 then
                    table.insert(customRowSizes, n)
                    if n > 0 then
                        useCustomLayout = true
                    end
                end
            end
            if #customRowSizes > 0 and not useCustomLayout then
                customRowSizes = {}
            end
        end
        
        -- If no valid pattern, default to all icons on one row
        if #customRowSizes == 0 then
            customRowSizes = { #icons }
        end
        useCustomLayout = true
    end
    
    -- CUSTOM GRID MODE: Row or Column based pattern with alignment
    if useCustomLayout and #customRowSizes > 0 then
        -- Hide all icons first
        for _, icon in ipairs(icons) do
            icon:Hide()
        end
        
        -- Get custom grid settings
        local customGridMode = GetSetting(trackerKey, "customGridMode") or "ROW"
        local customGridAlign = GetSetting(trackerKey, "customGridAlign") or (customGridMode == "COLUMN" and "TOP" or "LEFT")
        
        local iconCount = 0
        local iconIdx = 1
        local maxPrimary = 0    -- Track the max size in primary direction
        local totalSecondary = 0 -- Track total in secondary direction
        
        -- Determine overflow size
        local overflowSize = customRowSizes[#customRowSizes]
        if overflowSize == 0 then
            for i = #customRowSizes, 1, -1 do
                if customRowSizes[i] > 0 then
                    overflowSize = customRowSizes[i]
                    break
                end
            end
        end
        if overflowSize == 0 then overflowSize = columns end
        
        -- Helper function to apply styling to an icon
        local function StyleIcon(icon, currentIconIdx)
            icon:SetSize(iconWidth, iconHeight)
            -- Skip alpha if icon is hidden by per-icon settings
            if not icon._TUI_hiddenByPerIcon then
                icon:SetAlpha(iconOpacity)
            end
            -- Per-icon hide is applied before layout
            
            local useMasque = IsMasqueEnabled(trackerKey)
            if not useMasque then
                ApplyBorderAlpha(icon, borderAlpha)
                pcall(function()
                    ApplyTrackerIconEdgeStyle(icon, trackerKey, iconWidth, iconHeight)
                end)
            end
            
            ApplyCooldownTextScale(icon, cooldownTextScale, cooldownTextOffsetX, cooldownTextOffsetY,
                               cooldownTextColorR, cooldownTextColorG, cooldownTextColorB, cooldownTextFont)
            ApplyCountTextScale(icon, countTextScale, countTextOffsetX, countTextOffsetY,
                               countTextColorR, countTextColorG, countTextColorB, countTextFont)
            
            -- Apply cooldown visibility settings (sweep and countdown text)
            local cdFrame = icon.Cooldown or icon.cooldown
            if cdFrame then
                -- Apply current settings
                pcall(function()
                    cdFrame:SetDrawSwipe(showSweep)
                    cdFrame:SetHideCountdownNumbers(not showCountdownText)
                end)
                
                -- Hook SetCooldown to reapply settings after each Blizzard update
                if not cdFrame._TUI_CooldownHooked then
                    cdFrame._TUI_showSweep = showSweep
                    cdFrame._TUI_showCountdownText = showCountdownText
                    hooksecurefunc(cdFrame, "SetCooldown", function(self)
                        pcall(function()
                            self:SetDrawSwipe(self._TUI_showSweep)
                            self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
                        end)
                    end)
                    -- Also hook SetCooldownFromDurationObject for Midnight API
                    if cdFrame.SetCooldownFromDurationObject then
                        hooksecurefunc(cdFrame, "SetCooldownFromDurationObject", function(self)
                            pcall(function()
                                self:SetDrawSwipe(self._TUI_showSweep)
                                self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
                            end)
                        end)
                    end
                    cdFrame._TUI_CooldownHooked = true
                else
                    -- Update stored settings for existing hook
                    cdFrame._TUI_showSweep = showSweep
                    cdFrame._TUI_showCountdownText = showCountdownText
                end
            end
            
            if useMasque and not icon._TUI_MasqueGroup then
                AddToMasque(trackerKey, icon, {
                    Icon = icon.Icon or icon.icon,
                    Cooldown = icon.Cooldown or icon.cooldown,
                    Count = icon.Count or icon.count,
                    Border = icon.Border or icon.IconBorder,
                })
            elseif not useMasque and icon._TUI_MasqueGroup then
                RemoveFromMasque(icon)
            end
            
            -- Set up tooltip handling (pass slot index for buff tracker persistent cache)
            SetupIconTooltip(icon, trackerKey, currentIconIdx)
        end
        
        -- Track placed icons for second-pass alignment
        local placedIcons = {}
        
        if customGridMode == "COLUMN" then
            -- COLUMN MODE: Fill down (primary), then wrap right (secondary)
            local currentCol = 0
            
            for _, colSize in ipairs(customRowSizes) do
                if colSize == 0 then
                    currentCol = currentCol + 1
                else
                    local iconsInThisCol = 0
                    for rowIdx = 1, colSize do
                        if iconIdx <= #icons then
                            local icon = icons[iconIdx]
                            iconIdx = iconIdx + 1
                            iconCount = iconCount + 1
                            icon:Show()
                            StyleIcon(icon, iconIdx - 1)
                            table.insert(placedIcons, {icon = icon, col = currentCol, row = rowIdx - 1, groupSize = colSize})
                            iconsInThisCol = iconsInThisCol + 1
                        end
                    end
                    if iconsInThisCol > 0 then
                        maxPrimary = math.max(maxPrimary, iconsInThisCol)
                        totalSecondary = currentCol + 1
                    end
                    currentCol = currentCol + 1
                end
            end
            
            -- Handle overflow
            while iconIdx <= #icons do
                local iconsInThisCol = 0
                local overflowStartIdx = #placedIcons + 1  -- Track where overflow icons start
                for rowIdx = 1, overflowSize do
                    if iconIdx <= #icons then
                        local icon = icons[iconIdx]
                        iconIdx = iconIdx + 1
                        iconCount = iconCount + 1
                        icon:Show()
                        StyleIcon(icon, iconIdx - 1)
                        table.insert(placedIcons, {icon = icon, col = currentCol, row = rowIdx - 1, groupSize = 0})  -- Will update after
                        iconsInThisCol = iconsInThisCol + 1
                    end
                end
                -- Update groupSize for all icons in this overflow column to actual count
                for i = overflowStartIdx, #placedIcons do
                    placedIcons[i].groupSize = iconsInThisCol
                end
                if iconsInThisCol > 0 then
                    maxPrimary = math.max(maxPrimary, iconsInThisCol)
                    totalSecondary = currentCol + 1
                end
                currentCol = currentCol + 1
            end
            
            -- Calculate dimensions
            local totalWidth = totalSecondary * iconWidth + math.max(0, totalSecondary - 1) * spacingH
            local totalHeight = maxPrimary * iconHeight + math.max(0, maxPrimary - 1) * spacingV
            totalWidth = math.max(totalWidth, 1)
            totalHeight = math.max(totalHeight, 1)
            
            -- Position icons with alignment
            for _, placed in ipairs(placedIcons) do
                local xOffset = placed.col * (iconWidth + spacingH)
                local yOffset = 0
                
                local actualColSize = placed.groupSize
                local colHeight = actualColSize * iconHeight + math.max(0, actualColSize - 1) * spacingV
                
                if customGridAlign == "CENTER" then
                    yOffset = -(totalHeight - colHeight) / 2
                elseif customGridAlign == "END" then
                    yOffset = -(totalHeight - colHeight)
                end
                
                yOffset = yOffset - placed.row * (iconHeight + spacingV)
                
                placed.icon:ClearAllPoints()
                placed.icon:SetPoint("TOPLEFT", customTrackerFrame, "TOPLEFT", xOffset, yOffset)
            end
            
            customTrackerFrame:SetSize(totalWidth, totalHeight)
            dprint(string.format("LayoutCustomTrackerIcons [%s]: Custom COLUMN grid - %d/%d icons, %d cols, maxHeight=%d, size=%.0fx%.0f, align=%s", 
                trackerKey, iconCount, #icons, totalSecondary, maxPrimary, totalWidth, totalHeight, customGridAlign))
            
        else
            -- ROW MODE: Fill right (primary), then wrap down (secondary)
            local currentRow = 0
            
            for _, rowSize in ipairs(customRowSizes) do
                if rowSize == 0 then
                    currentRow = currentRow + 1
                else
                    local iconsInThisRow = 0
                    for colIdx = 1, rowSize do
                        if iconIdx <= #icons then
                            local icon = icons[iconIdx]
                            iconIdx = iconIdx + 1
                            iconCount = iconCount + 1
                            icon:Show()
                            StyleIcon(icon, iconIdx - 1)
                            table.insert(placedIcons, {icon = icon, col = colIdx - 1, row = currentRow, groupSize = rowSize})
                            iconsInThisRow = iconsInThisRow + 1
                        end
                    end
                    if iconsInThisRow > 0 then
                        maxPrimary = math.max(maxPrimary, iconsInThisRow)
                        totalSecondary = currentRow + 1
                    end
                    currentRow = currentRow + 1
                end
            end
            
            -- Handle overflow
            while iconIdx <= #icons do
                local iconsInThisRow = 0
                local overflowStartIdx = #placedIcons + 1  -- Track where overflow icons start
                for colIdx = 1, overflowSize do
                    if iconIdx <= #icons then
                        local icon = icons[iconIdx]
                        iconIdx = iconIdx + 1
                        iconCount = iconCount + 1
                        icon:Show()
                        StyleIcon(icon, iconIdx - 1)
                        table.insert(placedIcons, {icon = icon, col = colIdx - 1, row = currentRow, groupSize = 0})  -- Will update after
                        iconsInThisRow = iconsInThisRow + 1
                    end
                end
                -- Update groupSize for all icons in this overflow row to actual count
                for i = overflowStartIdx, #placedIcons do
                    placedIcons[i].groupSize = iconsInThisRow
                end
                if iconsInThisRow > 0 then
                    maxPrimary = math.max(maxPrimary, iconsInThisRow)
                    totalSecondary = currentRow + 1
                end
                currentRow = currentRow + 1
            end
            
            -- Calculate dimensions
            local totalWidth = maxPrimary * iconWidth + math.max(0, maxPrimary - 1) * spacingH
            local totalHeight = totalSecondary * iconHeight + math.max(0, totalSecondary - 1) * spacingV
            totalWidth = math.max(totalWidth, 1)
            totalHeight = math.max(totalHeight, 1)
            
            -- Position icons with alignment
            for _, placed in ipairs(placedIcons) do
                local yOffset = -placed.row * (iconHeight + spacingV)
                local xOffset = 0
                
                local actualRowSize = placed.groupSize
                local rowWidth = actualRowSize * iconWidth + math.max(0, actualRowSize - 1) * spacingH
                
                if customGridAlign == "CENTER" then
                    xOffset = (totalWidth - rowWidth) / 2
                elseif customGridAlign == "END" then
                    xOffset = totalWidth - rowWidth
                end
                
                xOffset = xOffset + placed.col * (iconWidth + spacingH)
                
                placed.icon:ClearAllPoints()
                placed.icon:SetPoint("TOPLEFT", customTrackerFrame, "TOPLEFT", xOffset, yOffset)
            end
            
            customTrackerFrame:SetSize(totalWidth, totalHeight)
            dprint(string.format("LayoutCustomTrackerIcons [%s]: Custom ROW grid - %d/%d icons, %d rows, maxWidth=%d, size=%.0fx%.0f, align=%s", 
                trackerKey, iconCount, #icons, totalSecondary, maxPrimary, totalWidth, totalHeight, customGridAlign))
        end
        
        return  -- Early return for custom grid
    end
    
    -- Standard grid layout (no custom pattern)
    
    -- Determine if primary direction is horizontal or vertical
    local primaryIsHorizontal = (growDir == "LEFT" or growDir == "RIGHT")
    
    local numRows = maxRows
    if not primaryIsHorizontal and numRows == 0 then
        numRows = math.ceil(#icons / columns)
    end
    
    -- First pass: calculate all icon positions and track bounds
    local iconPositions = {}
    local iconCount = 0
    
    -- Track bounds for all visible icons
    local boundsMinX, boundsMaxX = math.huge, -math.huge
    local boundsMinY, boundsMaxY = math.huge, -math.huge
    
    for i, icon in ipairs(icons) do
        local col, row
        local idx = i - 1
        
        if primaryIsHorizontal then
            col = idx % columns
            row = math.floor(idx / columns)
        else
            local effectiveRows = numRows > 0 and numRows or math.ceil(#icons / columns)
            row = idx % effectiveRows
            col = math.floor(idx / effectiveRows)
        end
        
        -- Check row limit
        if maxRows > 0 and row >= maxRows then
            iconPositions[i] = { hidden = true }
        else
            iconCount = iconCount + 1
            
            -- Calculate offset based on grow direction
            local xOffset, yOffset
            
            if growDir == "RIGHT" then
                xOffset = col * (iconWidth + spacingH)
            elseif growDir == "LEFT" then
                xOffset = -col * (iconWidth + spacingH)
            elseif growDir == "DOWN" or growDir == "UP" then
                if growSec == "RIGHT" then
                    xOffset = col * (iconWidth + spacingH)
                else
                    xOffset = -col * (iconWidth + spacingH)
                end
            else
                xOffset = col * (iconWidth + spacingH)
            end
            
            if growDir == "DOWN" then
                yOffset = -row * (iconHeight + spacingV)
            elseif growDir == "UP" then
                yOffset = row * (iconHeight + spacingV)
            elseif growSec == "DOWN" then
                yOffset = -row * (iconHeight + spacingV)
            elseif growSec == "UP" then
                yOffset = row * (iconHeight + spacingV)
            else
                yOffset = -row * (iconHeight + spacingV)
            end
            
            iconPositions[i] = { x = xOffset, y = yOffset, row = row, col = col }
            
            -- Track bounds: x goes from xOffset to xOffset+iconWidth
            -- y goes from yOffset (top) to yOffset-iconHeight (bottom, since negative is down)
            boundsMinX = math.min(boundsMinX, xOffset)
            boundsMaxX = math.max(boundsMaxX, xOffset + iconWidth)
            boundsMinY = math.min(boundsMinY, yOffset - iconHeight)  -- Bottom of icon
            boundsMaxY = math.max(boundsMaxY, yOffset)               -- Top of icon
        end
    end
    
    -- Handle empty case
    if iconCount == 0 then
        boundsMinX, boundsMaxX = 0, 1
        boundsMinY, boundsMaxY = -1, 0
    end
    
    -- Calculate frame dimensions from bounds
    local totalWidth = boundsMaxX - boundsMinX
    local totalHeight = boundsMaxY - boundsMinY
    
    -- Calculate shift to normalize all positions to positive coordinates
    -- Shift X so left edge is at 0
    local shiftX = -boundsMinX
    -- Shift Y so top edge is at 0 (boundsMaxY becomes 0)
    local shiftY = -boundsMaxY
    
    -- Second pass: position icons with normalized coordinates
    for i, icon in ipairs(icons) do
        local pos = iconPositions[i]
        if not pos then
            icon:Hide()
        elseif pos.hidden then
            icon:Hide()
        else
            icon:Show()
            
            -- Apply normalized position (all icons now in positive coordinate space)
            local finalX = pos.x + shiftX
            local finalY = pos.y + shiftY
            
            -- Calculate alignment offset based on primary direction
            local alignOffsetX = 0
            local alignOffsetY = 0
            
            if primaryIsHorizontal then
                -- Horizontal primary: alignment affects horizontal positioning
                if alignment == "CENTER" or alignment == "RIGHT" then
                    -- Calculate actual icons in this row
                    local iconsBeforeThisRow = pos.row * columns
                    local iconsRemaining = #icons - iconsBeforeThisRow
                    local iconsInThisRow = math.min(columns, iconsRemaining)
                    
                    local rowWidth = iconsInThisRow * iconWidth + (iconsInThisRow - 1) * spacingH
                    
                    if alignment == "CENTER" then
                        alignOffsetX = (totalWidth - rowWidth) / 2
                    else -- RIGHT
                        alignOffsetX = totalWidth - rowWidth
                    end
                end
            else
                -- Vertical primary (column mode): alignment affects vertical positioning
                -- LEFT = Top, CENTER = Middle, RIGHT = Bottom
                if alignment == "CENTER" or alignment == "RIGHT" then
                    -- Calculate actual icons in this column
                    local effectiveRows = numRows > 0 and numRows or math.ceil(#icons / columns)
                    local iconsBeforeThisCol = pos.col * effectiveRows
                    local iconsRemaining = #icons - iconsBeforeThisCol
                    local iconsInThisCol = math.min(effectiveRows, iconsRemaining)
                    
                    local colHeight = iconsInThisCol * iconHeight + (iconsInThisCol - 1) * spacingV
                    
                    if alignment == "CENTER" then
                        alignOffsetY = -(totalHeight - colHeight) / 2
                    else -- RIGHT (means Bottom in column mode)
                        alignOffsetY = -(totalHeight - colHeight)
                    end
                end
            end
            
            finalX = finalX + alignOffsetX
            finalY = finalY + alignOffsetY
            
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", customTrackerFrame, "TOPLEFT", finalX, finalY)
            icon:SetSize(iconWidth, iconHeight)
            icon:SetAlpha(iconOpacity)
            -- Per-icon hide is applied after visual slots are assigned
            
            -- Check if Masque is handling appearance
            local useMasque = IsMasqueEnabled("customTrackers")
            
            -- Apply border alpha (skip if Masque is handling it)
            if not useMasque then
                ApplyBorderAlpha(icon, borderAlpha)
            end
            
            -- Apply zoom and aspect ratio cropping (skip if Masque is handling it)
            if not useMasque then
                pcall(function()
                    local textureObj = icon.Icon or icon.icon
                    if textureObj and textureObj.SetTexCoord then
                        local left = zoom
                        local right = 1 - zoom
                        local top = zoom
                        local bottom = 1 - zoom
                        
                        if iconWidth > iconHeight then
                            local cropAmount = (1 - iconHeight / iconWidth) / 2
                            top = top + cropAmount * (1 - 2 * zoom)
                            bottom = bottom - cropAmount * (1 - 2 * zoom)
                        elseif iconHeight > iconWidth then
                            local cropAmount = (1 - iconWidth / iconHeight) / 2
                            left = left + cropAmount * (1 - 2 * zoom)
                            right = right - cropAmount * (1 - 2 * zoom)
                        end
                        
                        textureObj:SetTexCoord(left, right, top, bottom)
                    end
                end)
            end
            
            -- Apply cooldown text settings (scale, offset, color, font)
            ApplyCooldownTextScale(icon, cooldownTextScale, cooldownTextOffsetX, cooldownTextOffsetY,
                               cooldownTextColorR, cooldownTextColorG, cooldownTextColorB, cooldownTextFont)
            
            -- Apply count text settings (scale, offset, color, font)
            ApplyCountTextScale(icon, countTextScale, countTextOffsetX, countTextOffsetY,
                               countTextColorR, countTextColorG, countTextColorB, countTextFont)
            
            -- Apply cooldown visibility settings (sweep and countdown text)
            local cdFrame = icon.Cooldown or icon.cooldown
            if cdFrame then
                -- Apply current settings
                pcall(function()
                    cdFrame:SetDrawSwipe(showSweep)
                    cdFrame:SetHideCountdownNumbers(not showCountdownText)
                end)
                
                -- Hook SetCooldown to reapply settings after each Blizzard update
                if not cdFrame._TUI_CooldownHooked then
                    cdFrame._TUI_showSweep = showSweep
                    cdFrame._TUI_showCountdownText = showCountdownText
                    hooksecurefunc(cdFrame, "SetCooldown", function(self)
                        pcall(function()
                            self:SetDrawSwipe(self._TUI_showSweep)
                            self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
                        end)
                    end)
                    -- Also hook SetCooldownFromDurationObject for Midnight API
                    if cdFrame.SetCooldownFromDurationObject then
                        hooksecurefunc(cdFrame, "SetCooldownFromDurationObject", function(self)
                            pcall(function()
                                self:SetDrawSwipe(self._TUI_showSweep)
                                self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
                            end)
                        end)
                    end
                    cdFrame._TUI_CooldownHooked = true
                else
                    -- Update stored settings for existing hook
                    cdFrame._TUI_showSweep = showSweep
                    cdFrame._TUI_showCountdownText = showCountdownText
                end
            end
            
            -- Add to Masque if enabled and not already added
            if useMasque and not icon._TUI_MasqueGroup then
                AddToMasque("customTrackers", icon, {
                    Icon = icon.icon,
                    Cooldown = icon.cooldown,
                    Count = icon.count,
                    Border = icon.border,
                })
            -- Remove from Masque if disabled but was previously added
            elseif not useMasque and icon._TUI_MasqueGroup then
                RemoveFromMasque(icon)
            end
        end
    end
    
    -- Set frame size based on content
    totalWidth = math.max(totalWidth, 1)
    totalHeight = math.max(totalHeight, 1)
    customTrackerFrame:SetSize(totalWidth, totalHeight)
    
    -- Only show if not hidden via per-icon settings
    local CooldownHighlights = TUICD.CooldownHighlights
    if not (CooldownHighlights and CooldownHighlights:IsTrackerHidden("custom")) then
        customTrackerFrame:Show()
    end
    
    dprint(string.format("LayoutCustomTrackerIcons: %d visible icons (of %d total), %.0fx%.0f size", 
        iconCount, #icons, totalWidth, totalHeight))
end

-- Export for use by RefreshTrackerLayout
Cooldowns.LayoutCustomTrackerIcons = function()
    pcall(LayoutCustomTrackerIcons)
end

-- Rebuild all custom tracker icons
local function RebuildCustomTrackerIcons()
    if not customTrackerFrame then
        CreateCustomTrackerFrame()
    end
    
    -- Hide and release all existing icons
    for key, iconFrame in pairs(customTrackerIcons) do
        iconFrame:Hide()
        iconFrame:SetParent(nil)
    end
    wipe(customTrackerIcons)  -- Use wipe() to preserve table reference
    
    -- Check if custom trackers are enabled
    if not GetSetting("customTrackers", "enabled") then
        customTrackerFrame:Hide()
        return
    end
    
    -- Get all entries for current spec (unified list includes spell, item, and equipped types)
    local entries = GetCurrentSpecEntries()
    
    -- Create icons for enabled entries, tracking display order
    local displayIndex = 0
    for i, entry in ipairs(entries) do
        -- Check if entry is enabled (default to true for backwards compatibility)
        local isEnabled = entry.enabled ~= false
        
        if isEnabled then
            local entryKey = entry.type .. "_" .. entry.id
            
            -- For equipped entries, check if slot has an item with on-use ability
            if entry.type == "equipped" then
                local itemID = GetInventoryItemID("player", entry.id)
                if itemID then
                    -- Verify the item has an on-use ability
                    local hasOnUse = HasOnUseAbility(itemID)
                    if hasOnUse then
                        local iconFrame = CreateCustomTrackerIcon(entry, customTrackerFrame)
                        if iconFrame then
                            displayIndex = displayIndex + 1
                            iconFrame.listIndex = displayIndex
                            iconFrame.entryIndex = i  -- Store actual index in entries list
                            customTrackerIcons[entryKey] = iconFrame
                        end
                    else
                        dprint(string.format("Equipped slot %d: item %d has no on-use, skipping display", entry.id, itemID))
                    end
                end
                -- Empty slots or non-on-use items are skipped but entry stays in the list
            else
                local iconFrame = CreateCustomTrackerIcon(entry, customTrackerFrame)
                if iconFrame then
                    displayIndex = displayIndex + 1
                    iconFrame.listIndex = displayIndex
                    iconFrame.entryIndex = i  -- Store actual index in entries list
                    customTrackerIcons[entryKey] = iconFrame
                end
            end
        end
    end
    
    -- Layout the icons
    LayoutCustomTrackerIcons()
    
    dprint(string.format("Rebuilt custom tracker icons: %d visible of %d total entries", displayIndex, #entries))
end

-- Update all custom tracker cooldowns
local function UpdateAllCustomTrackerCooldowns()
    for _, iconFrame in pairs(customTrackerIcons) do
        UpdateCustomTrackerCooldown(iconFrame)
    end
end

-- Start custom tracker update ticker
local function StartCustomTrackerUpdates()
    if customTrackerUpdateTicker then return end
    
    customTrackerUpdateTicker = C_Timer.NewTicker(CUSTOM_TRACKER_UPDATE_INTERVAL, function()
        if GetSetting("customTrackers", "enabled") then
            pcall(UpdateAllCustomTrackerCooldowns)
            pcall(UpdateCustomTrackerVisibility)
        end
    end)
    
    dprint("Custom tracker updates started")
end

-- Stop custom tracker update ticker
local function StopCustomTrackerUpdates()
    if customTrackerUpdateTicker then
        customTrackerUpdateTicker:Cancel()
        customTrackerUpdateTicker = nil
        dprint("Custom tracker updates stopped")
    end
end

-- Handle equipment changes
local function OnEquipmentChanged(slotID, hasItem)
    if not GetSetting("customTrackers", "enabled") then return end
    
    -- Check if we have any equipped slot entries that might be affected
    local entries = GetCurrentSpecEntries()
    local hasEquippedEntries = false
    for _, entry in ipairs(entries) do
        if entry.type == "equipped" then
            hasEquippedEntries = true
            break
        end
    end
    
    if hasEquippedEntries then
        dprint(string.format("Equipment changed: slot %d, hasItem=%s - rebuilding", slotID, tostring(hasItem)))
        RebuildCustomTrackerIcons()
    end
end

-- Handle spec changes
local function OnSpecChanged()
    dprint("Spec changed, rebuilding custom tracker icons")
    RebuildCustomTrackerIcons()
end

-- ============================================================================
-- EXPORTS FOR SPELLBOOKHELPER
-- ============================================================================

Cooldowns.GetCurrentSpecEntries = GetCurrentSpecEntries
Cooldowns.AddCustomEntry = AddCustomEntry
Cooldowns.RemoveCustomEntry = RemoveCustomEntry
Cooldowns.RebuildCustomTrackerIcons = RebuildCustomTrackerIcons
Cooldowns.customTrackerIcons = customTrackerIcons

-- Export to TUICD namespace so SpellbookHelper can find it
TUICD.Cooldowns = Cooldowns

-- ============================================================================
-- VISIBILITY SYSTEM
-- ============================================================================
-- Handles show/hide based on combat, group, instance conditions
-- Also handles show/hide based on visibility conditions

-- Visibility condition defaults

-- Get current player state for visibility checks
local function GetPlayerState()
    local state = {
        inCombat = InCombatLockdown() or UnitAffectingCombat("player"),
        inGroup = IsInGroup(),
        inRaid = IsInRaid(),
        inInstance = false,
        inArena = false,
        inBattleground = false,
        isSolo = not IsInGroup(),
        hasTarget = UnitExists("target"),
        isMounted = TUICD.UnitAPI and TUICD.UnitAPI:IsMountedOrTravelForm() or IsMounted(),
    }
    
    -- Check instance type
    local _, instanceType = IsInInstance()
    if instanceType == "party" or instanceType == "raid" then
        state.inInstance = true
    elseif instanceType == "arena" then
        state.inArena = true
    elseif instanceType == "pvp" then
        state.inBattleground = true
    end
    
    return state
end

-- Check if viewer should be visible based on conditions
local function ShouldBeVisible(trackerKey)
    -- Force all visible mode bypasses all visibility conditions
    if TUICD.forceAllVisible then
        return true
    end
    
    -- Always show in Edit Mode for positioning
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return true
    end
    
    local enabled = GetSetting(trackerKey, "visibilityEnabled")
    if not enabled then
        return true  -- Visibility system disabled = always show
    end
    
    local state = GetPlayerState()
    
    -- OR logic: if ANY checked condition is true, show the tracker
    if state.inCombat and GetSetting(trackerKey, "showInCombat") then return true end
    if not state.inCombat and GetSetting(trackerKey, "showOutOfCombat") then return true end
    if state.isSolo and GetSetting(trackerKey, "showSolo") then return true end
    if state.inGroup and not state.inRaid and GetSetting(trackerKey, "showInParty") then return true end
    if state.inRaid and GetSetting(trackerKey, "showInRaid") then return true end
    if state.inInstance and GetSetting(trackerKey, "showInInstance") then return true end
    if state.inArena and GetSetting(trackerKey, "showInArena") then return true end
    if state.inBattleground and GetSetting(trackerKey, "showInBattleground") then return true end
    if state.hasTarget and GetSetting(trackerKey, "showHasTarget") then return true end
    if not state.hasTarget and GetSetting(trackerKey, "showNoTarget") then return true end
    if state.isMounted and GetSetting(trackerKey, "showMounted") then return true end
    if not state.isMounted and GetSetting(trackerKey, "showNotMounted") then return true end
    
    -- No conditions matched
    return false
end

-- Get the target alpha for a tracker based on visibility
local function GetTargetAlpha(trackerKey)
    -- Check if BuffHighlights wants to hide the buff tracker (highest priority)
    if trackerKey == "buffs" then
        local BuffHighlights = TUICD.BuffHighlights
        if BuffHighlights and BuffHighlights.IsTrackerHidden and BuffHighlights:IsTrackerHidden() then
            -- Check if we're in layout mode - show during layout mode
            local layoutContainer = _G["TweaksUI_LayoutContainer"]
            if not (layoutContainer and layoutContainer:IsShown()) then
                return 0  -- Hidden by Individual Icons settings
            end
        end
    end
    
    local shouldShow = ShouldBeVisible(trackerKey)
    
    if shouldShow then
        return 1  -- Visible
    end
    
    return 0  -- Hidden
end

-- Apply clickthrough setting to a tracker
local function ApplyClickthrough(trackerKey)
    local clickthrough = GetSetting(trackerKey, "clickthrough") or false
    local enableMouse = not clickthrough
    
    -- Helper to recursively disable/enable mouse on a frame and all its children
    local function SetMouseRecursive(frame, enable)
        if not frame then return end
        
        -- Disable mouse on this frame
        if frame.EnableMouse then
            pcall(function() frame:EnableMouse(enable) end)
        end
        
        -- Some button types use SetMouseClickEnabled
        if frame.SetMouseClickEnabled then
            pcall(function() frame:SetMouseClickEnabled(enable) end)
        end
        
        -- RegisterForClicks controls click behavior on buttons
        if frame.RegisterForClicks then
            if enable then
                pcall(function() frame:RegisterForClicks("AnyUp", "AnyDown") end)
            else
                pcall(function() frame:RegisterForClicks() end)  -- Empty = no clicks
            end
        end
        
        -- RETAIL FIX: Set hit rect insets to make the frame "unhittable"
        -- This is more reliable than EnableMouse for some Blizzard buttons
        if frame.SetHitRectInsets then
            if enable then
                pcall(function() frame:SetHitRectInsets(0, 0, 0, 0) end)
            else
                -- Set insets to be larger than the frame itself (effectively 0 hit area)
                pcall(function() frame:SetHitRectInsets(10000, 10000, 10000, 10000) end)
            end
        end
        
        -- Recursively process children
        if frame.GetNumChildren then
            local numChildren = frame:GetNumChildren() or 0
            for i = 1, numChildren do
                local child = select(i, frame:GetChildren())
                if child then
                    SetMouseRecursive(child, enable)
                end
            end
        end
    end
    
    -- Blizzard tracker
    local trackerInfo = GetTrackerInfo(trackerKey)
    if trackerInfo then
        local viewer = _G[trackerInfo.name]
        if viewer then
            -- Disable mouse on the viewer itself
            SetMouseRecursive(viewer, enableMouse)
            
            -- Also explicitly get icons and disable them
            local icons = CollectIcons(viewer)
            for _, icon in ipairs(icons) do
                SetMouseRecursive(icon, enableMouse)
            end
        end
    end
    
    dprint(string.format("[%s] Clickthrough: %s", trackerKey, tostring(clickthrough)))
end

-- Apply clickthrough settings to all trackers
local function ApplyAllClickthrough()
    for _, tracker in ipairs(TRACKERS) do
        ApplyClickthrough(tracker.key)
    end
end

-- Update visibility for a single tracker (called from ticker and events)
local function UpdateTrackerVisibility(trackerKey)
    local trackerInfo = GetTrackerInfo(trackerKey)
    if not trackerInfo then return end
    
    local viewer = _G[trackerInfo.name]
    if not viewer then return end
    
    -- During initialization, keep everything hidden
    local TUIFrame = TUICD.TUIFrame
    if TUIFrame and not TUIFrame.IsInitializationComplete() then
        -- Skip visibility updates during init - frames will be revealed later
        return
    end
    
    local targetAlpha = GetTargetAlpha(trackerKey)
    local currentAlpha = viewer:GetAlpha()
    
    -- Only update if there's a meaningful difference
    if math.abs(currentAlpha - targetAlpha) > 0.01 then
        viewer:SetAlpha(targetAlpha)
        dprint(string.format("[%s] Alpha: %.2f -> %.2f", trackerKey, currentAlpha, targetAlpha))
    end
    
    -- Handle mouse interaction for buff tracker when hidden by Individual Icons settings
    if trackerKey == "buffs" then
        local BuffHighlights = TUICD.BuffHighlights
        if BuffHighlights and BuffHighlights.IsTrackerHidden and BuffHighlights:IsTrackerHidden() then
            local layoutContainer = _G["TweaksUI_LayoutContainer"]
            local isLayoutMode = layoutContainer and layoutContainer:IsShown()
            if not isLayoutMode then
                viewer:EnableMouse(false)
                -- Also disable mouse on the container frame
                local container = _G["TweaksUI_BuffsContainer"]
                if container then
                    container:EnableMouse(false)
                    container:SetAlpha(0)
                end
            else
                viewer:EnableMouse(true)
                local container = _G["TweaksUI_BuffsContainer"]
                if container then
                    container:EnableMouse(true)
                    container:SetAlpha(1)
                end
            end
        else
            -- Restore mouse interaction when not hidden
            if targetAlpha > 0 then
                viewer:EnableMouse(true)
            end
        end
    end
end

-- Update visibility for all trackers
local function UpdateAllVisibility()
    for _, tracker in ipairs(TRACKERS) do
        UpdateTrackerVisibility(tracker.key)
    end
end

-- Start visibility update ticker
local visibilityTicker = nil
local function StartVisibilitySystem()
    if visibilityTicker then return end
    
    visibilityTicker = C_Timer.NewTicker(0.5, function()
        for _, tracker in ipairs(TRACKERS) do
            if GetSetting(tracker.key, "visibilityEnabled") then
                UpdateTrackerVisibility(tracker.key)
            end
        end
    end)
    
    dprint("Visibility system started")
end

local function StopVisibilitySystem()
    if visibilityTicker then
        visibilityTicker:Cancel()
        visibilityTicker = nil
        dprint("Visibility system stopped")
    end
end

-- Public method to update all tracker visibility (used by /tui showall)
function Cooldowns:UpdateAllTrackerVisibility()
    UpdateAllVisibility()
end

-- ============================================================================
-- VIEWER HOOKING
-- ============================================================================

local function HookViewer(viewer, trackerKey)
    if not viewer or hookedViewers[viewer] then return end
    
    hookedViewers[viewer] = trackerKey
    viewer._TUI_Key = trackerKey
    
    dprint(string.format("Hooking viewer: %s [%s]", viewer:GetName() or "unnamed", trackerKey))
    
    -- Helper to check if we're in a restricted scenario
    local function IsRestricted()
        if InCombatLockdown() then return true end
        if TUICD.RestrictionAPI and TUICD.RestrictionAPI.IsInRestrictedContent then
            return TUICD.RestrictionAPI:IsInRestrictedContent()
        end
        return false
    end
    
    -- Hook Layout function to intercept Blizzard's layout and apply ours
    if viewer.Layout then
        hooksecurefunc(viewer, "Layout", function(self)
            -- Skip if we're currently applying our layout
            if self._TUI_applying then return end
            
            -- CRITICAL: Defer all work to next frame to break taint chain
            -- This prevents our hook from propagating taint to Blizzard's subsequent code
            -- which can cause "attempt to compare secret value" errors in their code
            local viewerRef = self
            C_Timer.After(0, function()
                -- Verify viewer still exists and is shown
                if not viewerRef or not viewerRef:IsShown() then return end
                -- Skip if we started applying in the meantime
                if viewerRef._TUI_applying then return end
                
                -- Check if restricted (combat, M+, etc.)
                local restricted = IsRestricted()
                
                dprint(string.format("Layout hook fired for [%s] (deferred, restricted=%s)", trackerKey, tostring(restricted)))
                
                -- ORDER CAPTURE: Only during non-restricted periods to avoid secret value errors
                -- This detects when player uses Blizzard's Cooldown Manager to reorder icons
                if not restricted then
                    local icons = CollectIcons(viewerRef)
                    local shown = {}
                    local hasValidPositions = false
                    
                    for _, icon in ipairs(icons) do
                        if icon:IsShown() then
                            shown[#shown + 1] = icon
                            -- Wrap in pcall in case of secret anchor issues
                            local success, t, l = pcall(function()
                                return icon:GetTop(), icon:GetLeft()
                            end)
                            if success and t and l and (t ~= 0 or l ~= 0) then
                                -- Check for secret values before using
                                if not (issecretvalue and (issecretvalue(t) or issecretvalue(l))) then
                                    hasValidPositions = true
                                end
                            end
                        end
                    end
                    
                    -- Only capture order if icons have valid positions
                    if hasValidPositions and #shown > 0 then
                        -- Sort by visual position (reading order)
                        -- Wrap in pcall in case position APIs return secrets
                        local sortSuccess = pcall(function()
                            table.sort(shown, function(a, b)
                                local at, bt = a:GetTop() or 0, b:GetTop() or 0
                                local al, bl = a:GetLeft() or 0, b:GetLeft() or 0
                                -- Check for secret values
                                if issecretvalue and (issecretvalue(at) or issecretvalue(bt) or issecretvalue(al) or issecretvalue(bl)) then
                                    return false  -- Can't compare secrets, maintain order
                                end
                                if math.abs(at - bt) > 5 then return at > bt end
                                return al < bl
                            end)
                        end)
                        
                        if sortSuccess then
                            -- Build new order from texture IDs
                            local newOrder = {}
                            for i, icon in ipairs(shown) do
                                newOrder[i] = GetIconTextureID(icon)
                            end
                            
                            -- Compare to saved order
                            local savedOrder = GetSetting(trackerKey, "savedIconOrder") or {}
                            local orderChanged = #newOrder ~= #savedOrder
                            if not orderChanged then
                                for i, id in ipairs(newOrder) do
                                    if savedOrder[i] ~= id then
                                        orderChanged = true
                                        break
                                    end
                                end
                            end
                            
                            -- Save new order if it changed (player used Cooldown Manager)
                            if orderChanged then
                                SetSetting(trackerKey, "savedIconOrder", newOrder)
                                -- Also update session cache
                                iconOrderCache[trackerKey] = {}
                                for i, icon in ipairs(shown) do
                                    iconOrderCache[trackerKey][i] = icon
                                end
                                dprint(string.format("Layout hook [%s]: Order changed, saved new order: %s", 
                                    trackerKey, table.concat(newOrder, ",")))
                            end
                        end
                    end
                end
                
                -- APPLY LAYOUT: Always apply our layout to fix icon sizes
                -- This runs even during restricted periods to prevent Blizzard from
                -- leaving icons at inconsistent sizes
                pcall(ApplyGridLayout, viewerRef, trackerKey)
            end)
        end)
    end
    
    -- Hook Show to catch when viewer becomes visible
    hooksecurefunc(viewer, "Show", function(self)
        -- Defer to next frame to avoid taint propagation
        local viewerRef = self
        C_Timer.After(0, function()
            if not viewerRef then return end
            
            dprint(string.format("Show hook fired for [%s] (deferred)", trackerKey))
            -- Apply layout
            if viewerRef:IsShown() then
                pcall(ApplyGridLayout, viewerRef, trackerKey)
            end
            -- Set alpha directly based on visibility conditions
            local targetAlpha = GetTargetAlpha(trackerKey)
            viewerRef:SetAlpha(targetAlpha)
        end)
    end)
    
    -- Initial layout if already visible
    if viewer:IsShown() then
        pcall(ApplyGridLayout, viewer, trackerKey)
    end
    
    -- Set visibility based on initialization state
    -- During init, keep viewers hidden - they'll be revealed by TUIFrame.RevealAllFrames()
    -- After init, apply normal visibility rules
    local TUIFrame = TUICD.TUIFrame
    if TUIFrame and not TUIFrame.IsInitializationComplete() then
        -- Keep hidden during initialization
        viewer:SetAlpha(0)
        dprint(string.format("[%s] Init phase - keeping hidden", trackerKey))
    else
        -- Apply normal visibility
        local targetAlpha = GetTargetAlpha(trackerKey)
        viewer:SetAlpha(targetAlpha)
        dprint(string.format("[%s] Initial alpha: %.2f", trackerKey, targetAlpha))
    end
end

local function HookAllViewers()
    local hookedCount = 0
    local missingCount = 0
    
    for _, tracker in ipairs(TRACKERS) do
        local viewer = _G[tracker.name]
        if viewer then
            HookViewer(viewer, tracker.key)
            hookedCount = hookedCount + 1
            dprint(string.format("Viewer found and hooked: %s [%s]", tracker.name, tracker.key))
        else
            missingCount = missingCount + 1
            dprint(string.format("Viewer not found: %s - CDM may be disabled in Edit Mode", tracker.name))
        end
    end
    
    -- Alert user if no viewers found
    if hookedCount == 0 and missingCount > 0 then
        -- Viewers don't exist - CDM is likely disabled
        C_Timer.After(5, function()
            -- Only warn once per session
            if not TUICD._cdmWarningShown then
                TUICD._cdmWarningShown = true
                TUICD:Print("|cffFF6666Warning:|r Cooldown trackers not found. Enable them in Edit Mode → Account Settings → Cooldown Manager")
            end
        end)
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local eventFrame = CreateFrame("Frame")
local updateTimer = 0
local UPDATE_THROTTLE = 0.1
local layoutEnforceTimer = 0
local LAYOUT_ENFORCE_INTERVAL = 0.2  -- Check layout 5x per second (like CMT)
local clickthroughEnforceTimer = 0
local CLICKTHROUGH_ENFORCE_INTERVAL = 0.25  -- Enforce clickthrough 4x per second

local function OnEvent(self, event, arg1, ...)
    if event == "ADDON_LOADED" then
        -- Try to hook viewers as they become available
        C_Timer.After(0.5, HookAllViewers)
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Hide trackers immediately to prevent showing in wrong position
        -- They'll be revealed by TUIFrame.RevealAllFrames() after layout is complete
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer then
                viewer:SetAlpha(0)
            end
        end
        
        -- Hook viewers and apply initial layout (but keep hidden)
        C_Timer.After(0.5, function()
            HookAllViewers()
            -- Apply layout to all visible viewers
            for _, tracker in ipairs(TRACKERS) do
                local viewer = _G[tracker.name]
                if viewer and viewer:IsShown() then
                    ApplyGridLayout(viewer, tracker.key)
                end
            end
            -- Note: Don't restore alpha here - TUIFrame.RevealAllFrames() handles visibility
            -- after all modules have finished positioning at 3.5s
        end)
        
        -- DELAYED CACHE RESET: Clear session caches and recapture after positions are stable
        -- This fixes order issues where positions aren't valid at initial capture
        C_Timer.After(2.0, function()
            dprint("Delayed reset - clearing session caches and recapturing with stable positions")
            -- Clear session caches only (keep persistent savedIconOrder to preserve user's arrangement)
            iconOrderCache = {}
            -- Re-apply layout to all visible viewers
            for _, tracker in ipairs(TRACKERS) do
                local viewer = _G[tracker.name]
                if viewer and viewer:IsShown() then
                    ApplyGridLayout(viewer, tracker.key)
                end
            end
        end)
        
        -- Force Edit Mode to re-apply positions multiple times after load
        -- This fixes position issues after reload
        local function RefreshEditModePositions()
            if EditModeManagerFrame and not InCombatLockdown() then
                pcall(function()
                    -- Trigger layout update on each cooldown viewer
                    for _, tracker in ipairs(TRACKERS) do
                        local viewer = _G[tracker.name]
                        if viewer then
                            -- Try calling SetHasActiveChanges to trigger position refresh
                            if viewer.SetHasActiveChanges then
                                viewer:SetHasActiveChanges(false)
                            end
                            -- Try ApplySystemAnchor if available
                            if viewer.ApplySystemAnchor then
                                viewer:ApplySystemAnchor()
                            end
                        end
                    end
                end)
            end
        end
        
        -- Note: We no longer call RefreshEditModePositions as it conflicts with our
        -- Layout system. TUICD manages positions via TUIFrame/containers.
        
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        -- Icons might have changed, schedule layout update
        for key in pairs(needsLayoutUpdate) do
            needsLayoutUpdate[key] = true
        end
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat - safe to do UI updates
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer and viewer:IsShown() then
                ApplyGridLayout(viewer, tracker.key)
            end
        end
        -- Update visibility (combat state changed)
        UpdateAllVisibility()
        
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat - update visibility and opacity
        UpdateAllVisibility()
        -- Update icon opacity for combat state
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer and viewer:IsShown() then
                local opacity = GetCombatAwareOpacity(tracker.key)
                for _, child in ipairs({viewer:GetChildren()}) do
                    if child and (child.Icon or child.icon or child.Cooldown or child.cooldown) then
                        -- Don't override buff greyscale state
                        if tracker.key ~= "buffs" or not GetSetting("buffs", "greyscaleInactive") then
                            child:SetAlpha(opacity)
                        end
                    end
                end
            end
        end
        -- Update custom tracker opacity
        if customTrackerFrame and customTrackerFrame:IsShown() then
            customTrackerFrame:SetAlpha(GetCombatAwareOpacity("customTrackers"))
        end
        
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Group composition changed - update visibility
        UpdateAllVisibility()
        
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- Instance type might have changed - update visibility
        C_Timer.After(0.5, UpdateAllVisibility)
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Target changed - update visibility
        UpdateAllVisibility()
        
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        -- Mount state changed - update visibility
        UpdateAllVisibility()
        
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        -- Druid form changed - update visibility (for travel form "mounted" state)
        UpdateAllVisibility()
        
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        -- Edit Mode has applied positions - now apply our grid layouts
        dprint("EDIT_MODE_LAYOUTS_UPDATED fired")
        C_Timer.After(0.1, function()
            HookAllViewers()
            for _, tracker in ipairs(TRACKERS) do
                local viewer = _G[tracker.name]
                if viewer and viewer:IsShown() then
                    ApplyGridLayout(viewer, tracker.key)
                end
            end
        end)
        
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Gear changed - update equipped items tracker
        local slotID = arg1
        local hasItem = ...
        OnEquipmentChanged(slotID, hasItem)
        
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Spec changed - rebuild custom trackers for new spec
        C_Timer.After(0.5, OnSpecChanged)
    end
end

local function OnUpdate(self, elapsed)
    updateTimer = updateTimer + elapsed
    layoutEnforceTimer = layoutEnforceTimer + elapsed
    clickthroughEnforceTimer = clickthroughEnforceTimer + elapsed
    
    -- Process pending layout updates (throttled)
    if updateTimer >= UPDATE_THROTTLE then
        updateTimer = 0
        for key, needed in pairs(needsLayoutUpdate) do
            if needed then
                needsLayoutUpdate[key] = false
                local info = GetTrackerInfo(key)
                if info then
                    local viewer = _G[info.name]
                    if viewer and viewer:IsShown() and not viewer._TUI_applying then
                        pcall(ApplyGridLayout, viewer, key)
                    end
                end
            end
        end
    end
    
    -- Aggressive layout enforcement (5x per second like CMT)
    -- This catches Blizzard resetting layouts during combat
    -- IMPORTANT: Now enforces for ALL trackers to prevent size inconsistencies
    -- when Blizzard's Layout() resizes icons during restricted periods
    if layoutEnforceTimer >= LAYOUT_ENFORCE_INTERVAL then
        layoutEnforceTimer = 0
        -- Enforce layout on ALL visible trackers (not just custom layouts)
        -- This is necessary because the Layout hook skips during combat/restricted content,
        -- allowing Blizzard to resize icons inconsistently
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer and viewer:IsShown() and not viewer._TUI_applying then
                local trackerSettings = settings[tracker.key]
                if trackerSettings and trackerSettings.enabled then
                    pcall(ApplyGridLayout, viewer, tracker.key)
                end
            end
        end
    end
    
    -- CLICKTHROUGH ENFORCEMENT: Re-apply clickthrough periodically (4x per second)
    -- This catches Blizzard re-enabling mouse on icons during updates (especially on Retail)
    if clickthroughEnforceTimer >= CLICKTHROUGH_ENFORCE_INTERVAL then
        clickthroughEnforceTimer = 0
        for _, tracker in ipairs(TRACKERS) do
            local trackerSettings = settings[tracker.key]
            if trackerSettings and trackerSettings.clickthrough then
                pcall(ApplyClickthrough, tracker.key)
            end
        end
    end
end

-- ============================================================================
-- EXPORT / IMPORT
-- ============================================================================

local function SerializeCooldownSettings()
    -- Simple serialization for settings
    local serialized = "TweaksUI_Cooldowns:"
    
    -- Recursive function to serialize table
    local function serializeTable(tbl, prefix)
        local result = ""
        for k, v in pairs(tbl) do
            local key = prefix and (prefix .. "." .. k) or k
            if type(v) == "table" then
                result = result .. serializeTable(v, key)
            elseif type(v) == "boolean" then
                result = result .. key .. "=" .. (v and "true" or "false") .. ";"
            elseif type(v) == "number" then
                result = result .. key .. "=" .. tostring(v) .. ";"
            elseif type(v) == "string" then
                result = result .. key .. "=" .. v .. ";"
            end
        end
        return result
    end
    
    serialized = serialized .. serializeTable(settings, nil)
    return serialized
end

local function DeserializeCooldownSettings(str)
    if not str or not str:find("^TweaksUI_Cooldowns:") then
        return nil, "Invalid import string"
    end
    
    str = str:gsub("^TweaksUI_Cooldowns:", "")
    
    local newSettings = DeepCopy(DEFAULTS)
    
    for pair in str:gmatch("([^;]+)") do
        local key, value = pair:match("(.+)=(.+)")
        if key and value then
            -- Parse the key path
            local parts = {}
            for part in key:gmatch("[^%.]+") do
                table.insert(parts, part)
            end
            
            -- Navigate to the setting location
            local current = newSettings
            for i = 1, #parts - 1 do
                if current[parts[i]] then
                    current = current[parts[i]]
                end
            end
            
            -- Set the value
            local finalKey = parts[#parts]
            if value == "true" then
                current[finalKey] = true
            elseif value == "false" then
                current[finalKey] = false
            elseif tonumber(value) then
                current[finalKey] = tonumber(value)
            else
                current[finalKey] = value
            end
        end
    end
    
    return newSettings
end

function Cooldowns:ShowExportDialog()
    local dialog = CreateFrame("Frame", "TweaksUI_Cooldowns_ExportDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(450, 350)
    dialog:SetPoint("CENTER")
    dialog:SetBackdrop(darkBackdrop)
    dialog:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    dialog:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Export Cooldown Tracker Settings")
    title:SetTextColor(1, 0.82, 0)
    
    local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(390)
    editBox:SetAutoFocus(false)
    editBox:SetText(SerializeCooldownSettings())
    editBox:HighlightText()
    scrollFrame:SetScrollChild(editBox)
    
    local copyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copyLabel:SetPoint("BOTTOM", 0, 30)
    copyLabel:SetText("Press Ctrl+C to copy")
    copyLabel:SetTextColor(0.8, 0.8, 0.8)
    
    local closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    closeButton:SetPoint("BOTTOM", 0, 10)
    closeButton:SetSize(100, 24)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() dialog:Hide() end)
end

function Cooldowns:ShowImportDialog()
    local dialog = CreateFrame("Frame", "TweaksUI_Cooldowns_ImportDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(450, 350)
    dialog:SetPoint("CENTER")
    dialog:SetBackdrop(darkBackdrop)
    dialog:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    dialog:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Import Cooldown Tracker Settings")
    title:SetTextColor(1, 0.82, 0)
    
    local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 80)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(390)
    editBox:SetAutoFocus(true)
    editBox:SetText("")
    scrollFrame:SetScrollChild(editBox)
    
    local pasteLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pasteLabel:SetPoint("BOTTOM", 0, 58)
    pasteLabel:SetText("Paste import string above (Ctrl+V)")
    pasteLabel:SetTextColor(0.8, 0.8, 0.8)
    
    local module = self
    
    local importButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    importButton:SetPoint("BOTTOMLEFT", 50, 20)
    importButton:SetSize(100, 24)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        local str = editBox:GetText()
        local newSettings, err = DeserializeCooldownSettings(str)
        if newSettings then
            -- Apply new settings
            for k, v in pairs(newSettings) do
                settings[k] = v
            end
            -- Refresh all layouts
            for _, tracker in ipairs(TRACKERS) do
                local viewer = _G[tracker.name]
                if viewer and viewer:IsShown() then
                    ApplyGridLayout(viewer, tracker.key)
                end
            end
            TUICD:Print("Cooldown Tracker settings imported successfully!")
            dialog:Hide()
        else
            TUICD:Print("|cffff0000Import failed:|r " .. (err or "Unknown error"))
        end
    end)
    
    local cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelButton:SetPoint("BOTTOMRIGHT", -50, 20)
    cancelButton:SetSize(100, 24)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function() dialog:Hide() end)
end

-- ============================================================================
-- SETTINGS HUB
-- ============================================================================

function Cooldowns:CreateHub(parent)
    if cooldownHub then return cooldownHub end
    
    local hub = CreateFrame("Frame", "TweaksUI_Cooldowns_Hub", parent or UIParent, "BackdropTemplate")
    hub:SetSize(HUB_WIDTH, HUB_HEIGHT + 50)  -- Increased height for preset dropdown
    hub:SetBackdrop(darkBackdrop)
    hub:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    hub:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    hub:SetFrameStrata("DIALOG")
    hub:Hide()
    
    -- Title
    local title = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Cooldown Trackers")
    title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, hub, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        hub:Hide()
        self:HideAllPanels()
    end)
    
    -- Close all panels when hub is hidden
    hub:SetScript("OnHide", function()
        self:HideAllPanels()
    end)
    
    local yOffset = -38
    
    -- Add Preset Dropdown at the top
    if TUICD.PresetDropdown then
        local presetContainer, nextY = TUICD.PresetDropdown:Create(
            hub,
            "cooldowns",
            "Cooldowns",
            yOffset,
            {
                width = 140,
                showSaveButton = true,
                showDeleteButton = true,
            }
        )
        yOffset = nextY - 8
    end
    
    -- Section label
    local sectionLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sectionLabel:SetPoint("TOP", 0, yOffset)
    sectionLabel:SetText("|cff888888Blizzard Trackers|r")
    yOffset = yOffset - 16
    
    -- Create button for each tracker
    for _, tracker in ipairs(TRACKERS) do
        local btn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
        btn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
        btn:SetPoint("TOP", 0, yOffset)
        btn:SetText(tracker.displayName)
        btn:SetScript("OnClick", function()
            self:TogglePanel(tracker.key)
        end)
        yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    end
    
    yOffset = yOffset - 6
    
    -- Custom Trackers section label
    local customLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customLabel:SetPoint("TOP", 0, yOffset)
    customLabel:SetText("|cff888888Custom Trackers|r")
    yOffset = yOffset - 16
    
    -- Custom Trackers button
    local customBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    customBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    customBtn:SetPoint("TOP", 0, yOffset)
    customBtn:SetText("Custom Trackers")
    customBtn:SetScript("OnClick", function()
        self:TogglePanel("customTrackers")
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    yOffset = yOffset - 6
    
    -- Dynamic Docks section label
    local docksLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    docksLabel:SetPoint("TOP", 0, yOffset)
    docksLabel:SetText("|cff888888Dynamic Docks|r")
    yOffset = yOffset - 16
    
    -- Dynamic Docks button
    local docksBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    docksBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    docksBtn:SetPoint("TOP", 0, yOffset)
    docksBtn:SetText("Dock Settings")
    docksBtn:SetScript("OnClick", function()
        if TUICD.DocksUI then
            TUICD.DocksUI:Toggle()
        end
    end)
    docksBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Dynamic Docks", 1, 1, 1)
        GameTooltip:AddLine("Group icons from any tracker into custom containers", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    docksBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    yOffset = yOffset - 4
    
    -- Blizzard Cooldown Settings button
    local blizzSettingsBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    blizzSettingsBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    blizzSettingsBtn:SetPoint("TOP", 0, yOffset)
    blizzSettingsBtn:SetText("Blizzard Settings")
    blizzSettingsBtn:SetScript("OnClick", function()
        -- CooldownViewerSettings is Blizzard's Cooldown Settings frame
        local cooldownFrame = _G["CooldownViewerSettings"]
        
        if cooldownFrame then
            if cooldownFrame:IsShown() then
                cooldownFrame:Hide()
            else
                cooldownFrame:Show()
            end
        else
            print("|cff00ff00TweaksUI:|r Cooldown Settings not available.")
        end
    end)
    blizzSettingsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Blizzard Cooldown Settings", 1, 1, 1)
        GameTooltip:AddLine("Opens WoW's built-in cooldown manager", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Also accessible via /cdm", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    blizzSettingsBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    -- Separator
    local sep = hub:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOP", 0, yOffset)
    sep:SetSize(HUB_WIDTH - 20, 1)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    yOffset = yOffset - 12
    
    -- Import/Export section label
    local ieLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ieLabel:SetPoint("TOP", 0, yOffset)
    ieLabel:SetText("|cff888888Import / Export|r")
    yOffset = yOffset - 20
    
    -- Export button
    local exportBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    exportBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    exportBtn:SetPoint("TOP", 0, yOffset)
    exportBtn:SetText("Export All")
    exportBtn:SetScript("OnClick", function()
        self:ShowExportDialog()
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    -- Import button
    local importBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    importBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    importBtn:SetPoint("TOP", 0, yOffset)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        self:ShowImportDialog()
    end)
    
    -- Refresh All button at bottom
    local refreshBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    refreshBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    refreshBtn:SetPoint("BOTTOM", 0, 10)
    refreshBtn:SetText("Refresh All Layouts")
    refreshBtn:SetScript("OnClick", function()
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer and viewer:IsShown() then
                ApplyGridLayout(viewer, tracker.key)
            end
        end
        TUICD:Print("Refreshed all tracker layouts")
    end)
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(hub, 1.0)
    end
    
    cooldownHub = hub
    return hub
end

function Cooldowns:ShowHub(parent)
    if not cooldownHub then
        self:CreateHub(parent)
    end
    
    if parent then
        cooldownHub:ClearAllPoints()
        cooldownHub:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, 0)
    end
    
    cooldownHub:Show()
end

-- Toggle the cooldowns settings panel (called from main Settings hub)
function Cooldowns:ToggleSettingsPanel(parent)
    if not cooldownHub then
        self:CreateHub(parent)
    end
    
    if cooldownHub:IsShown() then
        self:HideAllPanels()
    else
        if parent then
            cooldownHub:ClearAllPoints()
            cooldownHub:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, 0)
        end
        cooldownHub:Show()
    end
end

function Cooldowns:HideAllPanels()
    for _, panel in pairs(settingsPanels) do
        if panel then panel:Hide() end
    end
    if TUICD.DocksUI then TUICD.DocksUI:Hide() end
    if cooldownHub then cooldownHub:Hide() end
    currentOpenPanel = nil
end

-- Hide just the tracker settings panels (not hub or docks)
function Cooldowns:HideTrackerPanels()
    for _, panel in pairs(settingsPanels) do
        if panel then panel:Hide() end
    end
    currentOpenPanel = nil
end

function Cooldowns:TogglePanel(trackerKey)
    -- Hide other panels
    for key, panel in pairs(settingsPanels) do
        if panel and key ~= trackerKey then
            panel:Hide()
        end
    end
    -- Also hide Docks panel when opening tracker settings
    if TUICD.DocksUI then TUICD.DocksUI:Hide() end
    
    if settingsPanels[trackerKey] then
        if settingsPanels[trackerKey]:IsShown() then
            settingsPanels[trackerKey]:Hide()
            currentOpenPanel = nil
        else
            settingsPanels[trackerKey]:Show()
            currentOpenPanel = trackerKey
        end
    else
        -- Create the appropriate panel
        if trackerKey == "customTrackers" then
            self:CreateCustomTrackersPanel()
        else
            self:CreateTrackerPanel(trackerKey)
        end
        if settingsPanels[trackerKey] then
            settingsPanels[trackerKey]:Show()
            currentOpenPanel = trackerKey
        end
    end
end

-- ============================================================================
-- TRACKER SETTINGS PANEL
-- ============================================================================

function Cooldowns:CreateTrackerPanel(trackerKey)
    local trackerInfo = GetTrackerInfo(trackerKey)
    if not trackerInfo then return end
    
    local panel = CreateFrame("Frame", "TweaksUI_Cooldowns_" .. trackerKey .. "_Panel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("TOPLEFT", cooldownHub, "TOPRIGHT", 0, 0)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    
    settingsPanels[trackerKey] = panel
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(trackerInfo.displayName)
    title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
    end)
    
    -- Handle panel hide
    panel:SetScript("OnHide", function()
        currentOpenPanel = nil
    end)
    
    -- Tab buttons container
    local tabContainer = CreateFrame("Frame", nil, panel)
    tabContainer:SetPoint("TOPLEFT", 10, -40)
    tabContainer:SetPoint("TOPRIGHT", -10, -40)
    tabContainer:SetHeight(28)
    
    -- Content frames (one per tab)
    local contentFrames = {}
    local tabButtons = {}
    local currentTab = 1
    
    -- Tab definitions
    local tabs = {
        { name = "Layout", key = "layout" },
        { name = "Appearance", key = "appearance" },
        { name = "Text", key = "text" },
        { name = "Visibility", key = "visibility" },
    }
    
    -- Add buff-specific tab
    if trackerKey == "buffs" then
        table.insert(tabs, { name = "Buff Display", key = "buffdisplay" })
        table.insert(tabs, { name = "Individual Icons", key = "highlights" })
    end
    
    -- Add Individual Icons tab for cooldown trackers (Essential, Utility)
    if trackerKey == "essential" or trackerKey == "utility" then
        table.insert(tabs, { name = "Individual Icons", key = "cooldownhighlights" })
    end
    
    -- Helper function to refresh layout
    local function RefreshLayout()
        local viewer = _G[trackerInfo.name]
        if viewer and viewer:IsShown() then
            ApplyGridLayout(viewer, trackerKey)
        end
    end
    
    -- Create tab content frame
    local function CreateTabContent()
        local content = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        content:SetPoint("TOPLEFT", 10, -72)
        content:SetPoint("BOTTOMRIGHT", -28, 10)
        
        local scrollChild = CreateFrame("Frame", nil, content)
        scrollChild:SetSize(PANEL_WIDTH - 50, 800)
        content:SetScrollChild(scrollChild)
        
        content.scrollChild = scrollChild
        content:Hide()
        return content
    end
    
    -- UI Element Helpers
    local function CreateHeader(parent, yOffset, text)
        yOffset = yOffset - 8
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 5, yOffset)
        header:SetText(text)
        header:SetTextColor(1, 0.82, 0)
        return yOffset - 20
    end
    
    local function CreateSlider(parent, yOffset, labelText, min, max, step, getValue, setValue)
        local isFloat = step < 1
        local decimals = isFloat and 2 or 0
        
        -- Use centralized slider with input
        local container = TUICD.Utilities:CreateSliderWithInput(parent, {
            label = labelText,
            min = min,
            max = max,
            step = step,
            value = getValue(),
            isFloat = isFloat,
            decimals = decimals,
            width = 140,
            labelWidth = 130,
            valueWidth = 45,
            onValueChanged = function(value)
                setValue(value)
                RefreshLayout()
            end,
        })
        container:SetPoint("TOPLEFT", 10, yOffset)
        
        return yOffset - 30
    end
    
    local function CreateCheckbox(parent, yOffset, labelText, getValue, setValue)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 5, yOffset)
        cb:SetSize(24, 24)
        cb:SetChecked(getValue())
        cb:SetScript("OnClick", function(self)
            setValue(self:GetChecked())
            RefreshLayout()
        end)
        
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(labelText)
        label:SetTextColor(0.8, 0.8, 0.8)
        
        return yOffset - 26
    end
    
    local function CreateDropdown(parent, yOffset, labelText, options, getValue, setValue)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 10, yOffset)
        label:SetText(labelText)
        label:SetTextColor(0.8, 0.8, 0.8)
        yOffset = yOffset - 18
        
        local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", -5, yOffset)
        UIDropDownMenu_SetWidth(dropdown, PANEL_WIDTH - 110)
        
        local function OnSelect(self, value)
            setValue(value)
            UIDropDownMenu_SetText(dropdown, self:GetText())
            RefreshLayout()
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
        
        return yOffset - 30
    end
    
    local function CreateEditBox(parent, yOffset, labelText, getValue, setValue, width)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 10, yOffset)
        label:SetText(labelText)
        label:SetTextColor(0.8, 0.8, 0.8)
        
        local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        box:SetPoint("LEFT", label, "RIGHT", 8, 0)
        box:SetSize(width or 60, 20)
        box:SetAutoFocus(false)
        box:SetText(getValue() or "")
        box:SetScript("OnEnterPressed", function(self)
            setValue(self:GetText())
            RefreshLayout()
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        
        return yOffset - 26, box
    end
    
    local function CreateButton(parent, yOffset, text, width, onClick)
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", 10, yOffset)
        btn:SetSize(width, 22)
        btn:SetText(text)
        btn:SetScript("OnClick", function()
            onClick()
            RefreshLayout()
        end)
        return yOffset - 28
    end
    
    -- ========================================
    -- TAB 1: Layout
    -- ========================================
    local function BuildLayoutTab(parent)
        local y = -10
        
        y = CreateHeader(parent, y, "Icon Size")
        y = CreateSlider(parent, y, "Base Size", 16, 80, 1,
            function() return GetSetting(trackerKey, "iconSize") or 36 end,
            function(v) SetSetting(trackerKey, "iconSize", v) end)
        
        y = CreateDropdown(parent, y, "Aspect Ratio", ASPECT_PRESETS,
            function() return GetSetting(trackerKey, "aspectRatio") or "1:1" end,
            function(v) 
                SetSetting(trackerKey, "aspectRatio", v)
                if v ~= "custom" then
                    SetSetting(trackerKey, "iconWidth", nil)
                    SetSetting(trackerKey, "iconHeight", nil)
                end
            end)
        
        -- Custom dimensions
        local customLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        customLabel:SetPoint("TOPLEFT", 10, y)
        customLabel:SetText("Custom: Width")
        customLabel:SetTextColor(0.6, 0.6, 0.6)
        
        local widthBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        widthBox:SetPoint("LEFT", customLabel, "RIGHT", 5, 0)
        widthBox:SetSize(40, 20)
        widthBox:SetAutoFocus(false)
        widthBox:SetNumeric(true)
        widthBox:SetNumber(GetSetting(trackerKey, "iconWidth") or 36)
        widthBox:SetScript("OnEnterPressed", function(self)
            SetSetting(trackerKey, "iconWidth", self:GetNumber())
            SetSetting(trackerKey, "aspectRatio", "custom")
            RefreshLayout()
            self:ClearFocus()
        end)
        
        local heightLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heightLabel:SetPoint("LEFT", widthBox, "RIGHT", 10, 0)
        heightLabel:SetText("Height")
        heightLabel:SetTextColor(0.6, 0.6, 0.6)
        
        local heightBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        heightBox:SetPoint("LEFT", heightLabel, "RIGHT", 5, 0)
        heightBox:SetSize(40, 20)
        heightBox:SetAutoFocus(false)
        heightBox:SetNumeric(true)
        heightBox:SetNumber(GetSetting(trackerKey, "iconHeight") or 36)
        heightBox:SetScript("OnEnterPressed", function(self)
            SetSetting(trackerKey, "iconHeight", self:GetNumber())
            SetSetting(trackerKey, "aspectRatio", "custom")
            RefreshLayout()
            self:ClearFocus()
        end)
        y = y - 28
        
        y = CreateHeader(parent, y, "Grid Layout")
        y = CreateSlider(parent, y, "Columns", 1, 20, 1,
            function() return GetSetting(trackerKey, "columns") or 8 end,
            function(v) SetSetting(trackerKey, "columns", v) end)
        
        y = CreateSlider(parent, y, "Max Rows (0=unlimited)", 0, 10, 1,
            function() return GetSetting(trackerKey, "rows") or 0 end,
            function(v) SetSetting(trackerKey, "rows", v) end)
        
        y = CreateHeader(parent, y, "Spacing")
        
        -- Horizontal spacing with edit box for custom values
        local hLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hLabel:SetPoint("TOPLEFT", 10, y)
        hLabel:SetText("Horizontal:")
        hLabel:SetTextColor(0.8, 0.8, 0.8)
        
        local hBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        hBox:SetPoint("LEFT", hLabel, "RIGHT", 8, 0)
        hBox:SetSize(60, 20)
        hBox:SetAutoFocus(false)
        hBox:SetNumeric(false)  -- Allow negative too
        hBox:SetText(tostring(GetSetting(trackerKey, "spacingH") or 2))
        hBox:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText()) or 2
            SetSetting(trackerKey, "spacingH", val)
            RefreshLayout()
            self:ClearFocus()
        end)
        hBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        y = y - 26
        
        -- Vertical spacing with edit box for custom values
        local vLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        vLabel:SetPoint("TOPLEFT", 10, y)
        vLabel:SetText("Vertical:")
        vLabel:SetTextColor(0.8, 0.8, 0.8)
        
        local vBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        vBox:SetPoint("LEFT", vLabel, "RIGHT", 8, 0)
        vBox:SetSize(60, 20)
        vBox:SetAutoFocus(false)
        vBox:SetNumeric(false)
        vBox:SetText(tostring(GetSetting(trackerKey, "spacingV") or 2))
        vBox:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText()) or 2
            SetSetting(trackerKey, "spacingV", val)
            RefreshLayout()
            self:ClearFocus()
        end)
        vBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        y = y - 26
        
        y = CreateButton(parent, y, "Compress (-5 spacing)", 140, function()
            SetSetting(trackerKey, "spacingH", -5)
            SetSetting(trackerKey, "spacingV", -5)
            hBox:SetText("-5")
            vBox:SetText("-5")
        end)
        
        y = CreateHeader(parent, y, "Direction & Alignment")
        
        -- Store references to controls for enable/disable toggling
        local standardControls = {}
        local customGridControls = {}
        
        -- Helper to set control enabled/disabled state
        local function SetControlEnabled(control, enabled)
            if not control then return end
            if control.SetEnabled then
                control:SetEnabled(enabled)
            end
            -- For dropdowns, we need to handle the UIDropDownMenu
            if control.dropdown then
                if enabled then
                    UIDropDownMenu_EnableDropDown(control.dropdown)
                else
                    UIDropDownMenu_DisableDropDown(control.dropdown)
                end
            end
            -- For sliders
            if control.slider then
                if enabled then
                    control.slider:Enable()
                    if control.slider.Text then control.slider.Text:SetTextColor(1, 1, 1) end
                else
                    control.slider:Disable()
                    if control.slider.Text then control.slider.Text:SetTextColor(0.5, 0.5, 0.5) end
                end
            end
            -- For checkboxes
            if control.checkbox then
                control.checkbox:SetEnabled(enabled)
                if control.checkbox.Text then
                    control.checkbox.Text:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5)
                end
            end
            -- For edit boxes
            if control.editbox then
                control.editbox:SetEnabled(enabled)
                if enabled then
                    control.editbox:SetTextColor(1, 1, 1)
                else
                    control.editbox:SetTextColor(0.5, 0.5, 0.5)
                end
            end
            -- For buttons
            if control.button then
                control.button:SetEnabled(enabled)
            end
            -- For labels
            if control.label then
                control.label:SetTextColor(enabled and 0.8 or 0.4, enabled and 0.8 or 0.4, enabled and 0.8 or 0.4)
            end
        end
        
        -- Function to update all control states based on useCustomGrid
        local function UpdateControlStates()
            local useCustomGrid = GetSetting(trackerKey, "useCustomGrid") or false
            -- Standard controls disabled when custom grid is on
            for _, ctrl in ipairs(standardControls) do
                SetControlEnabled(ctrl, not useCustomGrid)
            end
            -- Custom grid controls disabled when custom grid is off
            for _, ctrl in ipairs(customGridControls) do
                SetControlEnabled(ctrl, useCustomGrid)
            end
        end
        
        -- Primary direction dropdown
        local growOpts = {
            { label = "Right (Row Mode)", value = "RIGHT" }, 
            { label = "Left (Row Mode)", value = "LEFT" },
            { label = "Down (Column Mode)", value = "DOWN" },
            { label = "Up (Column Mode)", value = "UP" },
        }
        
        local primaryLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        primaryLabel:SetPoint("TOPLEFT", 10, y)
        primaryLabel:SetText("Primary")
        
        local primaryDropdown = CreateFrame("Frame", "TUI_" .. trackerKey .. "_PrimaryDropdown", parent, "UIDropDownMenuTemplate")
        primaryDropdown:SetPoint("TOPLEFT", -5, y - 14)
        UIDropDownMenu_SetWidth(primaryDropdown, 200)
        UIDropDownMenu_Initialize(primaryDropdown, function(self, level)
            for _, opt in ipairs(growOpts) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(primaryDropdown, opt.value)
                    UIDropDownMenu_SetText(primaryDropdown, opt.label)
                    SetSetting(trackerKey, "growDirection", opt.value)
                    RefreshLayout()
                end
                info.checked = (GetSetting(trackerKey, "growDirection") or "RIGHT") == opt.value
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        local currentGrow = GetSetting(trackerKey, "growDirection") or "RIGHT"
        for _, opt in ipairs(growOpts) do
            if opt.value == currentGrow then
                UIDropDownMenu_SetText(primaryDropdown, opt.label)
                break
            end
        end
        table.insert(standardControls, { dropdown = primaryDropdown, label = primaryLabel })
        y = y - 45
        
        -- Secondary direction dropdown
        local growSecOpts = {
            { label = "Down", value = "DOWN" }, 
            { label = "Up", value = "UP" },
            { label = "Right", value = "RIGHT" },
            { label = "Left", value = "LEFT" },
        }
        
        local secondaryLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        secondaryLabel:SetPoint("TOPLEFT", 10, y)
        secondaryLabel:SetText("Secondary")
        
        local secondaryDropdown = CreateFrame("Frame", "TUI_" .. trackerKey .. "_SecondaryDropdown", parent, "UIDropDownMenuTemplate")
        secondaryDropdown:SetPoint("TOPLEFT", -5, y - 14)
        UIDropDownMenu_SetWidth(secondaryDropdown, 200)
        UIDropDownMenu_Initialize(secondaryDropdown, function(self, level)
            for _, opt in ipairs(growSecOpts) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(secondaryDropdown, opt.value)
                    UIDropDownMenu_SetText(secondaryDropdown, opt.label)
                    SetSetting(trackerKey, "growSecondary", opt.value)
                    RefreshLayout()
                end
                info.checked = (GetSetting(trackerKey, "growSecondary") or "DOWN") == opt.value
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        local currentGrowSec = GetSetting(trackerKey, "growSecondary") or "DOWN"
        for _, opt in ipairs(growSecOpts) do
            if opt.value == currentGrowSec then
                UIDropDownMenu_SetText(secondaryDropdown, opt.label)
                break
            end
        end
        table.insert(standardControls, { dropdown = secondaryDropdown, label = secondaryLabel })
        y = y - 45
        
        -- Alignment dropdown
        local alignOpts = {
            { label = "Left", value = "LEFT" }, 
            { label = "Center", value = "CENTER" }, 
            { label = "Right", value = "RIGHT" }
        }
        
        local alignLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        alignLabel:SetPoint("TOPLEFT", 10, y)
        alignLabel:SetText("Alignment")
        
        local alignDropdown = CreateFrame("Frame", "TUI_" .. trackerKey .. "_AlignDropdown", parent, "UIDropDownMenuTemplate")
        alignDropdown:SetPoint("TOPLEFT", -5, y - 14)
        UIDropDownMenu_SetWidth(alignDropdown, 200)
        UIDropDownMenu_Initialize(alignDropdown, function(self, level)
            for _, opt in ipairs(alignOpts) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(alignDropdown, opt.value)
                    UIDropDownMenu_SetText(alignDropdown, opt.label)
                    SetSetting(trackerKey, "alignment", opt.value)
                    RefreshLayout()
                end
                info.checked = (GetSetting(trackerKey, "alignment") or "LEFT") == opt.value
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        local currentAlign = GetSetting(trackerKey, "alignment") or "LEFT"
        for _, opt in ipairs(alignOpts) do
            if opt.value == currentAlign then
                UIDropDownMenu_SetText(alignDropdown, opt.label)
                break
            end
        end
        table.insert(standardControls, { dropdown = alignDropdown, label = alignLabel })
        y = y - 45
        
        -- Reverse Icon Order checkbox
        local reverseCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
        reverseCheck:SetPoint("TOPLEFT", 10, y)
        reverseCheck.Text:SetText("Reverse Icon Order")
        reverseCheck:SetChecked(GetSetting(trackerKey, "reverseOrder") or false)
        reverseCheck:SetScript("OnClick", function(self)
            SetSetting(trackerKey, "reverseOrder", self:GetChecked())
            RefreshLayout()
        end)
        table.insert(standardControls, { checkbox = reverseCheck })
        y = y - 28
        
        -- ========== CUSTOM GRID SECTION ==========
        y = CreateHeader(parent, y, "Custom Grid (Advanced)")
        
        -- Enable Custom Grid checkbox - this one stays always enabled
        local customGridCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
        customGridCheck:SetPoint("TOPLEFT", 10, y)
        customGridCheck.Text:SetText("Enable Custom Grid Pattern")
        customGridCheck:SetChecked(GetSetting(trackerKey, "useCustomGrid") or false)
        customGridCheck:SetScript("OnClick", function(self)
            local enabled = self:GetChecked()
            SetSetting(trackerKey, "useCustomGrid", enabled)
            UpdateControlStates()
            -- Prompt for reload
            StaticPopupDialogs["TUI_RELOAD_CUSTOM_GRID"] = {
                text = "Custom Grid changes require a UI reload to fully apply. Reload now?",
                button1 = "Reload",
                button2 = "Later",
                OnAccept = function()
                    ReloadUI()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("TUI_RELOAD_CUSTOM_GRID")
        end)
        y = y - 28
        
        -- Custom Grid Mode dropdown
        local modeOpts = {
            { label = "Row Mode (right then down)", value = "ROW" },
            { label = "Column Mode (down then right)", value = "COLUMN" },
        }
        
        local modeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        modeLabel:SetPoint("TOPLEFT", 10, y)
        modeLabel:SetText("Mode")
        
        local modeDropdown = CreateFrame("Frame", "TUI_" .. trackerKey .. "_ModeDropdown", parent, "UIDropDownMenuTemplate")
        modeDropdown:SetPoint("TOPLEFT", -5, y - 14)
        UIDropDownMenu_SetWidth(modeDropdown, 200)
        UIDropDownMenu_Initialize(modeDropdown, function(self, level)
            for _, opt in ipairs(modeOpts) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(modeDropdown, opt.value)
                    UIDropDownMenu_SetText(modeDropdown, opt.label)
                    SetSetting(trackerKey, "customGridMode", opt.value)
                    RefreshLayout()
                end
                info.checked = (GetSetting(trackerKey, "customGridMode") or "ROW") == opt.value
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        local currentMode = GetSetting(trackerKey, "customGridMode") or "ROW"
        for _, opt in ipairs(modeOpts) do
            if opt.value == currentMode then
                UIDropDownMenu_SetText(modeDropdown, opt.label)
                break
            end
        end
        table.insert(customGridControls, { dropdown = modeDropdown, label = modeLabel })
        y = y - 45
        
        -- Custom Grid Alignment dropdown
        local customAlignOpts = {
            { label = "Start (Left/Top)", value = "START" },
            { label = "Center (Middle)", value = "CENTER" },
            { label = "End (Right/Bottom)", value = "END" },
        }
        
        local customAlignLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        customAlignLabel:SetPoint("TOPLEFT", 10, y)
        customAlignLabel:SetText("Alignment")
        
        local customAlignDropdown = CreateFrame("Frame", "TUI_" .. trackerKey .. "_CustomAlignDropdown", parent, "UIDropDownMenuTemplate")
        customAlignDropdown:SetPoint("TOPLEFT", -5, y - 14)
        UIDropDownMenu_SetWidth(customAlignDropdown, 200)
        UIDropDownMenu_Initialize(customAlignDropdown, function(self, level)
            for _, opt in ipairs(customAlignOpts) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(customAlignDropdown, opt.value)
                    UIDropDownMenu_SetText(customAlignDropdown, opt.label)
                    SetSetting(trackerKey, "customGridAlign", opt.value)
                    RefreshLayout()
                end
                info.checked = (GetSetting(trackerKey, "customGridAlign") or "START") == opt.value
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        local currentCustomAlign = GetSetting(trackerKey, "customGridAlign") or "START"
        for _, opt in ipairs(customAlignOpts) do
            if opt.value == currentCustomAlign then
                UIDropDownMenu_SetText(customAlignDropdown, opt.label)
                break
            end
        end
        table.insert(customGridControls, { dropdown = customAlignDropdown, label = customAlignLabel })
        y = y - 45
        
        -- Custom pattern edit box
        local patternLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        patternLabel:SetPoint("TOPLEFT", 10, y)
        patternLabel:SetText("Pattern (e.g. 4,4,2 or 3,0,3 for gap):")
        patternLabel:SetTextColor(0.8, 0.8, 0.8)
        y = y - 16
        
        local patternBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        patternBox:SetPoint("TOPLEFT", 10, y)
        patternBox:SetSize(120, 20)
        patternBox:SetAutoFocus(false)
        patternBox:SetText(GetSetting(trackerKey, "customLayout") or "")
        patternBox:SetScript("OnEnterPressed", function(self)
            SetSetting(trackerKey, "customLayout", self:GetText())
            RefreshLayout()
            self:ClearFocus()
        end)
        patternBox:SetScript("OnEditFocusLost", function(self)
            SetSetting(trackerKey, "customLayout", self:GetText())
            RefreshLayout()
        end)
        patternBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        
        -- Apply button
        local applyBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        applyBtn:SetPoint("LEFT", patternBox, "RIGHT", 5, 0)
        applyBtn:SetSize(50, 20)
        applyBtn:SetText("Apply")
        applyBtn:SetScript("OnClick", function()
            SetSetting(trackerKey, "customLayout", patternBox:GetText())
            RefreshLayout()
            patternBox:ClearFocus()
        end)
        
        table.insert(customGridControls, { editbox = patternBox, label = patternLabel, button = applyBtn })
        y = y - 26
        
        -- Hint text
        local hintLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintLabel:SetPoint("TOPLEFT", 10, y)
        hintLabel:SetText("Use 0 for blank rows/columns (e.g. 3,0,3 = gap)")
        hintLabel:SetTextColor(0.6, 0.6, 0.6)
        table.insert(customGridControls, { label = hintLabel })
        y = y - 18
        
        -- Initialize control states
        UpdateControlStates()
        
        -- Reset Layout Settings button
        local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        resetBtn:SetPoint("TOPLEFT", 10, y)
        resetBtn:SetSize(160, 22)
        resetBtn:SetText("Reset Layout Settings")
        resetBtn:SetScript("OnClick", function()
            -- Reset all layout-related settings to defaults
            SetSetting(trackerKey, "columns", 8)
            SetSetting(trackerKey, "rows", 0)
            SetSetting(trackerKey, "spacingH", 2)
            SetSetting(trackerKey, "spacingV", 2)
            SetSetting(trackerKey, "growDirection", "RIGHT")
            SetSetting(trackerKey, "growSecondary", "DOWN")
            SetSetting(trackerKey, "alignment", "LEFT")
            SetSetting(trackerKey, "useCustomGrid", false)
            SetSetting(trackerKey, "customLayout", "")
            SetSetting(trackerKey, "customGridMode", "ROW")
            SetSetting(trackerKey, "customGridAlign", "START")
            SetSetting(trackerKey, "customLayoutMode", nil)
            -- Refresh
            RefreshLayout()
            -- Update UI
            patternBox:SetText("")
            customGridCheck:SetChecked(false)
            UpdateControlStates()
            -- Update dropdown texts
            UIDropDownMenu_SetText(primaryDropdown, "Right (Row Mode)")
            UIDropDownMenu_SetText(secondaryDropdown, "Down")
            UIDropDownMenu_SetText(alignDropdown, "Left")
            UIDropDownMenu_SetText(modeDropdown, "Row Mode (right then down)")
            UIDropDownMenu_SetText(customAlignDropdown, "Start (Left/Top)")
            TUICD:Print("Layout settings reset for " .. trackerKey)
        end)
        y = y - 30
        
        parent:SetHeight(math.abs(y) + 20)
    end
    
    -- ========================================
    -- TAB 2: Appearance
    -- ========================================
    local function BuildAppearanceTab(parent)
        local y = -10
        
        y = CreateSlider(parent, y, "Out of Combat Opacity", 0.1, 1.0, 0.05,
            function() return GetSetting(trackerKey, "iconOpacity") or 1.0 end,
            function(v) SetSetting(trackerKey, "iconOpacity", v) end)
        
        y = CreateSlider(parent, y, "In Combat Opacity", 0.1, 1.0, 0.05,
            function() return GetSetting(trackerKey, "iconOpacityCombat") or 1.0 end,
            function(v) SetSetting(trackerKey, "iconOpacityCombat", v) end)
        
        y = CreateSlider(parent, y, "Border Alpha", 0, 1.0, 0.05,
            function() return GetSetting(trackerKey, "borderAlpha") or 1.0 end,
            function(v) SetSetting(trackerKey, "borderAlpha", v) end)
        
        y = CreateSlider(parent, y, "Zoom (texture crop)", 0, 0.2, 0.01,
            function() return GetSetting(trackerKey, "zoom") or 0.08 end,
            function(v) SetSetting(trackerKey, "zoom", v) end)
        
        y = y - 10  -- Add spacing before cooldown visibility options
        
        -- Unified sweep visibility (controls both aura and cooldown sweeps)
        y = CreateCheckbox(parent, y, "Show Cooldown Sweep",
            function() 
                local val = GetSetting(trackerKey, "showSweep")
                return val == nil or val == true  -- Default to true
            end,
            function(v) 
                SetSetting(trackerKey, "showSweep", v)
                -- Refresh layout to apply change
                local viewer = _G[GetTrackerInfo(trackerKey).name]
                if viewer then ApplyGridLayout(viewer, trackerKey) end
                -- Also refresh highlight frames
                if trackerKey == "buffs" then
                    if TUICD.BuffHighlights and TUICD.BuffHighlights.RefreshAllHighlights then
                        TUICD.BuffHighlights:RefreshAllHighlights()
                    end
                else
                    if TUICD.CooldownHighlights and TUICD.CooldownHighlights.RefreshAllHighlights then
                        TUICD.CooldownHighlights:RefreshAllHighlights(trackerKey)
                    end
                end
            end)
        
        -- Icon Edge Style dropdown
        local edgeStyleLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        edgeStyleLabel:SetPoint("TOPLEFT", 10, y - 10)
        edgeStyleLabel:SetText("Icon Edge Style")
        y = y - 25
        
        local edgeStyles = {
            {value = "sharp", label = "Sharp (Zoomed)"},
            {value = "rounded", label = "Rounded Corners"},
            {value = "square", label = "Square (Full)"},
        }
        
        local edgeDropdown = CreateFrame("Frame", "TweaksUI_" .. trackerKey .. "_EdgeStyle", parent, "UIDropDownMenuTemplate")
        edgeDropdown:SetPoint("TOPLEFT", 0, y)
        UIDropDownMenu_SetWidth(edgeDropdown, 150)
        
        local currentEdge = GetSetting(trackerKey, "iconEdgeStyle") or "sharp"
        for _, opt in ipairs(edgeStyles) do
            if opt.value == currentEdge then
                UIDropDownMenu_SetText(edgeDropdown, opt.label)
                break
            end
        end
        
        UIDropDownMenu_Initialize(edgeDropdown, function(self, level)
            for _, opt in ipairs(edgeStyles) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.func = function(self)
                    SetSetting(trackerKey, "iconEdgeStyle", self.value)
                    UIDropDownMenu_SetText(edgeDropdown, self:GetText())
                    -- Force layout refresh
                    local viewer = _G[GetTrackerInfo(trackerKey).name]
                    if viewer then ApplyGridLayout(viewer, trackerKey) end
                end
                info.checked = (GetSetting(trackerKey, "iconEdgeStyle") or "sharp") == opt.value
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        y = y - 35
        
        -- Masque checkbox (only show if Masque is available)
        if Masque then
            y = CreateCheckbox(parent, y, "Use Masque Skinning",
                function() return GetSetting(trackerKey, "useMasque") or false end,
                function(v) 
                    SetSetting(trackerKey, "useMasque", v) 
                    -- Force layout refresh
                    local viewer = _G[GetTrackerInfo(trackerKey).name]
                    if viewer then ApplyGridLayout(viewer, trackerKey) end
                    -- Reskin group if enabling
                    if v then
                        ReskinMasqueGroup(trackerKey)
                    end
                end)
        end
        
        parent:SetHeight(math.abs(y) + 20)
    end
    
    -- ========================================
    -- TAB 3: Text
    -- ========================================
    local function BuildTextTab(parent)
        local y = -10
        
        -- Local RefreshLayout helper
        local function RefreshLayout()
            local viewer = _G[GetTrackerInfo(trackerKey).name]
            if viewer then ApplyGridLayout(viewer, trackerKey) end
        end
        
        -- Helper to create a font dropdown
        local function CreateFontDropdown(yPos, labelText, settingKey)
            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", 10, yPos)
            label:SetText(labelText)
            
            local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
            dropdown:SetPoint("TOPLEFT", 0, yPos - 18)
            UIDropDownMenu_SetWidth(dropdown, 180)
            
            local function UpdateDropdownText()
                local currentFont = GetSetting(trackerKey, settingKey) or "Default"
                UIDropDownMenu_SetText(dropdown, currentFont)
            end
            
            UIDropDownMenu_Initialize(dropdown, function(self, level)
                local fonts = TUICD.Media and TUICD.Media:GetFontList() or {"Default"}
                for _, fontName in ipairs(fonts) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = fontName
                    info.checked = (GetSetting(trackerKey, settingKey) or "Default") == fontName
                    info.func = function()
                        SetSetting(trackerKey, settingKey, fontName)
                        UpdateDropdownText()
                        RefreshLayout()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            
            UpdateDropdownText()
            
            return yPos - 50
        end
        
        -- Helper to create a color picker button
        local function CreateColorButton(yPos, labelText, rKey, gKey, bKey)
            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", 10, yPos)
            label:SetText(labelText)
            
            local colorBtn = CreateFrame("Button", nil, parent)
            colorBtn:SetSize(24, 24)
            colorBtn:SetPoint("LEFT", label, "RIGHT", 10, 0)
            
            local colorTex = colorBtn:CreateTexture(nil, "ARTWORK")
            colorTex:SetPoint("TOPLEFT", 2, -2)
            colorTex:SetPoint("BOTTOMRIGHT", -2, 2)
            colorTex:SetColorTexture(
                GetSetting(trackerKey, rKey) or 1,
                GetSetting(trackerKey, gKey) or 1,
                GetSetting(trackerKey, bKey) or 1
            )
            colorBtn.colorTex = colorTex
            
            local border = colorBtn:CreateTexture(nil, "BACKGROUND")
            border:SetAllPoints()
            border:SetColorTexture(0.2, 0.2, 0.2, 1)
            
            colorBtn:SetScript("OnClick", function(self)
                local r = GetSetting(trackerKey, rKey) or 1
                local g = GetSetting(trackerKey, gKey) or 1
                local b = GetSetting(trackerKey, bKey) or 1
                
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = r, g = g, b = b,
                    swatchFunc = function()
                        local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                        SetSetting(trackerKey, rKey, newR)
                        SetSetting(trackerKey, gKey, newG)
                        SetSetting(trackerKey, bKey, newB)
                        self.colorTex:SetColorTexture(newR, newG, newB)
                        RefreshLayout()
                    end,
                    cancelFunc = function(prev)
                        SetSetting(trackerKey, rKey, prev.r)
                        SetSetting(trackerKey, gKey, prev.g)
                        SetSetting(trackerKey, bKey, prev.b)
                        self.colorTex:SetColorTexture(prev.r, prev.g, prev.b)
                        RefreshLayout()
                    end,
                })
            end)
            
            colorBtn:SetScript("OnShow", function(self)
                self.colorTex:SetColorTexture(
                    GetSetting(trackerKey, rKey) or 1,
                    GetSetting(trackerKey, gKey) or 1,
                    GetSetting(trackerKey, bKey) or 1
                )
            end)
            
            return yPos - 30
        end
        
        -- ========== COOLDOWN TEXT ==========
        y = CreateHeader(parent, y, "Cooldown Text")
        
        y = CreateFontDropdown(y, "Font:", "cooldownTextFont")
        
        y = CreateSlider(parent, y, "Scale", 0.5, 2.0, 0.1,
            function() return GetSetting(trackerKey, "cooldownTextScale") or 1.0 end,
            function(v) 
                SetSetting(trackerKey, "cooldownTextScale", v) 
                RefreshLayout()
            end)
        
        y = CreateSlider(parent, y, "Offset X", -20, 20, 1,
            function() return GetSetting(trackerKey, "cooldownTextOffsetX") or 0 end,
            function(v) 
                SetSetting(trackerKey, "cooldownTextOffsetX", v)
                RefreshLayout()
            end)
        
        y = CreateSlider(parent, y, "Offset Y", -20, 20, 1,
            function() return GetSetting(trackerKey, "cooldownTextOffsetY") or 0 end,
            function(v) 
                SetSetting(trackerKey, "cooldownTextOffsetY", v)
                RefreshLayout()
            end)
        
        y = CreateColorButton(y, "Color:", "cooldownTextColorR", "cooldownTextColorG", "cooldownTextColorB")
        
        -- ========== COUNT/CHARGE TEXT ==========
        y = CreateHeader(parent, y - 10, "Count/Charge Text")
        
        y = CreateFontDropdown(y, "Font:", "countTextFont")
        
        y = CreateSlider(parent, y, "Scale", 0.5, 2.0, 0.1,
            function() return GetSetting(trackerKey, "countTextScale") or 1.0 end,
            function(v) 
                SetSetting(trackerKey, "countTextScale", v)
                RefreshLayout()
            end)
        
        y = CreateSlider(parent, y, "Offset X", -20, 20, 1,
            function() return GetSetting(trackerKey, "countTextOffsetX") or 0 end,
            function(v) 
                SetSetting(trackerKey, "countTextOffsetX", v)
                RefreshLayout()
            end)
        
        y = CreateSlider(parent, y, "Offset Y", -20, 20, 1,
            function() return GetSetting(trackerKey, "countTextOffsetY") or 0 end,
            function(v) 
                SetSetting(trackerKey, "countTextOffsetY", v)
                RefreshLayout()
            end)
        
        y = CreateColorButton(y, "Color:", "countTextColorR", "countTextColorG", "countTextColorB")
        
        parent:SetHeight(math.abs(y) + 20)
    end
    
    -- ========================================
    -- TAB 4: Visibility
    -- ========================================
    local function BuildVisibilityTab(parent)
        local y = -10
        
        y = CreateHeader(parent, y, "Behavior")
        
        -- Tooltip option only for Essential/Utility (not buffs - no tooltip support)
        if trackerKey ~= "buffs" then
            y = CreateCheckbox(parent, y, "Show Tooltips on Mouseover",
                function() return GetSetting(trackerKey, "showTooltip") ~= false end,
                function(v) 
                    SetSetting(trackerKey, "showTooltip", v)
                    -- Re-apply layout to update tooltip hooks
                    local viewer = _G[GetTrackerInfo(trackerKey).name]
                    if viewer then
                        pcall(ApplyGridLayout, viewer, trackerKey)
                    end
                end)
        end
        
        y = CreateHeader(parent, y, "Visibility Conditions")
        
        y = CreateCheckbox(parent, y, "Enable Visibility Conditions",
            function() return GetSetting(trackerKey, "visibilityEnabled") or false end,
            function(v) SetSetting(trackerKey, "visibilityEnabled", v) end)
        
        y = CreateHeader(parent, y, "Show When (OR logic)")
        
        y = CreateCheckbox(parent, y, "In Combat",
            function() return GetSetting(trackerKey, "showInCombat") end,
            function(v) SetSetting(trackerKey, "showInCombat", v) end)
        
        y = CreateCheckbox(parent, y, "Out of Combat",
            function() return GetSetting(trackerKey, "showOutOfCombat") end,
            function(v) SetSetting(trackerKey, "showOutOfCombat", v) end)
        
        y = CreateCheckbox(parent, y, "Solo",
            function() return GetSetting(trackerKey, "showSolo") end,
            function(v) SetSetting(trackerKey, "showSolo", v) end)
        
        y = CreateCheckbox(parent, y, "In Party",
            function() return GetSetting(trackerKey, "showInParty") end,
            function(v) SetSetting(trackerKey, "showInParty", v) end)
        
        y = CreateCheckbox(parent, y, "In Raid",
            function() return GetSetting(trackerKey, "showInRaid") end,
            function(v) SetSetting(trackerKey, "showInRaid", v) end)
        
        y = CreateCheckbox(parent, y, "In Instance (Dungeon)",
            function() return GetSetting(trackerKey, "showInInstance") end,
            function(v) SetSetting(trackerKey, "showInInstance", v) end)
        
        y = CreateCheckbox(parent, y, "In Arena",
            function() return GetSetting(trackerKey, "showInArena") end,
            function(v) SetSetting(trackerKey, "showInArena", v) end)
        
        y = CreateCheckbox(parent, y, "In Battleground",
            function() return GetSetting(trackerKey, "showInBattleground") end,
            function(v) SetSetting(trackerKey, "showInBattleground", v) end)
        
        y = CreateCheckbox(parent, y, "Has Target",
            function() return GetSetting(trackerKey, "showHasTarget") end,
            function(v) SetSetting(trackerKey, "showHasTarget", v) end)
        
        y = CreateCheckbox(parent, y, "No Target",
            function() return GetSetting(trackerKey, "showNoTarget") end,
            function(v) SetSetting(trackerKey, "showNoTarget", v) end)
        
        y = CreateCheckbox(parent, y, "Mounted",
            function() return GetSetting(trackerKey, "showMounted") end,
            function(v) SetSetting(trackerKey, "showMounted", v) end)
        
        y = CreateCheckbox(parent, y, "Not Mounted",
            function() return GetSetting(trackerKey, "showNotMounted") end,
            function(v) SetSetting(trackerKey, "showNotMounted", v) end)
        
        y = CreateHeader(parent, y, "Interaction")
        
        y = CreateCheckbox(parent, y, "Clickthrough (ignore mouse)",
            function() return GetSetting(trackerKey, "clickthrough") or false end,
            function(v) 
                SetSetting(trackerKey, "clickthrough", v)
                -- Apply immediately to the viewer
                ApplyClickthrough(trackerKey)
            end)
        
        parent:SetHeight(math.abs(y) + 20)
    end
    
    -- ========================================
    -- TAB 5: Buff Display (buffs only)
    -- ========================================
    local function BuildBuffDisplayTab(parent)
        local y = -10
        
        y = CreateCheckbox(parent, y, "Greyscale Inactive Buffs",
            function() return GetSetting(trackerKey, "greyscaleInactive") end,
            function(v) 
                SetSetting(trackerKey, "greyscaleInactive", v)
                if v then
                    pcall(UpdateBuffVisualStates)
                else
                    local viewer = _G["BuffIconCooldownViewer"]
                    if viewer then
                        local icons = CollectIcons(viewer)
                        for _, icon in ipairs(icons) do
                            pcall(function()
                                local textureObj = icon.Icon or icon.icon
                                if textureObj and textureObj.SetDesaturated then
                                    textureObj:SetDesaturated(false)
                                end
                                icon:SetAlpha(GetCombatAwareOpacity("buffs"))
                            end)
                        end
                    end
                    wipe(buffStateCache)
                end
            end)
        
        y = CreateSlider(parent, y, "Inactive Buff Opacity", 0.1, 1.0, 0.05,
            function() return GetSetting(trackerKey, "inactiveAlpha") or 0.5 end,
            function(v) 
                SetSetting(trackerKey, "inactiveAlpha", v)
                -- Force update all buff visuals with new opacity
                wipe(buffStateCache)
                pcall(UpdateBuffVisualStates)
            end)
        
        parent:SetHeight(math.abs(y) + 20)
    end
    
    -- TAB 6: Individual Icons Settings (buffs only)
    -- ========================================
    local function BuildHighlightsTab(parent)
        local y = -10
        local BuffHighlights = TUICD.BuffHighlights
        local selectedSlot = nil
        local currentState = "active"  -- "active" or "inactive"
        local slotRows = {}
        
        -- Aspect ratio presets (same as other trackers)
        local ASPECT_OPTIONS = {
            { label = "1:1 (Square)", value = "1:1" },
            { label = "4:3", value = "4:3" },
            { label = "3:4", value = "3:4" },
            { label = "16:9 (Wide)", value = "16:9" },
            { label = "9:16 (Tall)", value = "9:16" },
            { label = "2:1", value = "2:1" },
            { label = "1:2", value = "1:2" },
            { label = "Custom", value = "custom" },
        }
        
        -- Header
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 5, y)
        header:SetText("Individual Icons")
        header:SetTextColor(1, 0.82, 0)
        
        -- Refresh button (at top right, script set later after RefreshSlotList is defined)
        local refreshBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        refreshBtn:SetPoint("TOPRIGHT", -5, y)
        refreshBtn:SetSize(100, 20)
        refreshBtn:SetText("Refresh List")
        y = y - 26
        
        -- Description
        local description = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        description:SetPoint("TOPLEFT", 5, y)
        description:SetPoint("TOPRIGHT", -10, y)
        description:SetJustifyH("LEFT")
        description:SetText("|cff888888Create individual icons for your abilities that can be configured and moved outside of the main trackers.|r")
        y = y - 18
        
        -- Hide Tracker checkbox
        local hideTrackerCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        hideTrackerCheck:SetPoint("TOPLEFT", 5, y)
        hideTrackerCheck:SetSize(24, 24)
        hideTrackerCheck:SetChecked(BuffHighlights and BuffHighlights:IsTrackerHidden() or false)
        hideTrackerCheck:SetScript("OnClick", function(self)
            if BuffHighlights then
                BuffHighlights:SetTrackerHidden(self:GetChecked())
                Cooldowns:SaveSettings()
            end
        end)
        
        local hideTrackerLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hideTrackerLabel:SetPoint("LEFT", hideTrackerCheck, "RIGHT", 2, 0)
        hideTrackerLabel:SetText("Hide Buff Tracker (use individual icons only)")
        hideTrackerLabel:SetTextColor(0.9, 0.9, 0.9)
        y = y - 26
        
        -- Slot list container (smaller to make room for more controls)
        local listContainer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        listContainer:SetPoint("TOPLEFT", 5, y)
        listContainer:SetSize(PANEL_WIDTH - 60, 90)
        listContainer:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        listContainer:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        listContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        
        -- Create scroll frame inside list container
        local scrollFrame = CreateFrame("ScrollFrame", nil, listContainer, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 2, -2)
        scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
        
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(PANEL_WIDTH - 84)
        scrollChild:SetHeight(1)  -- Will be updated dynamically
        scrollFrame:SetScrollChild(scrollChild)
        
        y = y - 100
        
        -- Controls container with backdrop (outer frame)
        local controlsContainer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        controlsContainer:SetPoint("TOPLEFT", 5, y)
        controlsContainer:SetSize(PANEL_WIDTH - 60, 650)
        controlsContainer:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        controlsContainer:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
        controlsContainer:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        
        -- Scroll frame inside container
        local controlsScrollFrame = CreateFrame("ScrollFrame", nil, controlsContainer, "UIPanelScrollFrameTemplate")
        controlsScrollFrame:SetPoint("TOPLEFT", 2, -2)
        controlsScrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
        
        -- Controls panel as scroll child (content area)
        local controlsPanel = CreateFrame("Frame", nil, controlsScrollFrame)
        controlsPanel:SetSize(PANEL_WIDTH - 84, 860)  -- Height for full content
        controlsScrollFrame:SetScrollChild(controlsPanel)
        
        -- "No Selection" label (on container, not scroll child, so it stays centered)
        local noSelectionLabel = controlsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noSelectionLabel:SetPoint("CENTER")
        noSelectionLabel:SetText("Select a buff slot above")
        noSelectionLabel:SetTextColor(0.5, 0.5, 0.5)
        
        -- All controls will be created here (hidden initially)
        local controls = {}
        
        -- Slot header with icon preview
        controls.header = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.header:SetPoint("TOPLEFT", 10, -8)
        controls.header:SetTextColor(1, 0.82, 0)
        controls.header:Hide()
        
        controls.iconPreview = controlsPanel:CreateTexture(nil, "ARTWORK")
        controls.iconPreview:SetPoint("LEFT", controls.header, "RIGHT", 8, 0)
        controls.iconPreview:SetSize(20, 20)
        controls.iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        controls.iconPreview:Hide()
        
        -- Enable checkbox
        controls.enableCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.enableCheck:SetPoint("TOPLEFT", 10, -30)
        controls.enableCheck:SetSize(24, 24)
        controls.enableCheck:Hide()
        
        controls.enableLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.enableLabel:SetPoint("LEFT", controls.enableCheck, "RIGHT", 2, 0)
        controls.enableLabel:SetText("Enable Individual Icon")
        controls.enableLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.enableLabel:Hide()
        
        -- Hide in tracker checkbox (hide main tracker icon, keep highlight visible)
        controls.hideCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.hideCheck:SetPoint("LEFT", controls.enableLabel, "RIGHT", 20, 0)
        controls.hideCheck:SetSize(24, 24)
        controls.hideCheck:Hide()
        
        controls.hideLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.hideLabel:SetPoint("LEFT", controls.hideCheck, "RIGHT", 2, 0)
        controls.hideLabel:SetText("Hide in Tracker")
        controls.hideLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.hideLabel:Hide()
        
        -- State tabs (Active / Inactive)
        controls.stateLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.stateLabel:SetPoint("TOPLEFT", 10, -58)
        controls.stateLabel:SetText("Configure State:")
        controls.stateLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.stateLabel:Hide()
        
        controls.activeBtn = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
        controls.activeBtn:SetPoint("LEFT", controls.stateLabel, "RIGHT", 8, 0)
        controls.activeBtn:SetSize(70, 20)
        controls.activeBtn:SetText("Active")
        controls.activeBtn:Hide()
        
        controls.inactiveBtn = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
        controls.inactiveBtn:SetPoint("LEFT", controls.activeBtn, "RIGHT", 4, 0)
        controls.inactiveBtn:SetSize(70, 20)
        controls.inactiveBtn:SetText("Inactive")
        controls.inactiveBtn:Hide()
        
        -- Show when checkbox (for current state)
        controls.showCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.showCheck:SetPoint("TOPLEFT", 10, -85)
        controls.showCheck:SetSize(24, 24)
        controls.showCheck:Hide()
        
        controls.showLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.showLabel:SetPoint("LEFT", controls.showCheck, "RIGHT", 2, 0)
        controls.showLabel:SetText("Show when Active")
        controls.showLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.showLabel:Hide()
        
        -- Size slider
        controls.sizeLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.sizeLabel:SetPoint("TOPLEFT", 10, -115)
        controls.sizeLabel:SetText("Size:")
        controls.sizeLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.sizeLabel:Hide()
        
        controls.sizeSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.sizeSlider:SetPoint("LEFT", controls.sizeLabel, "RIGHT", 15, 0)
        controls.sizeSlider:SetSize(90, 16)
        controls.sizeSlider:SetMinMaxValues(24, 128)
        controls.sizeSlider:SetValueStep(2)
        controls.sizeSlider:SetObeyStepOnDrag(true)
        controls.sizeSlider.Low:SetText("")
        controls.sizeSlider.High:SetText("")
        controls.sizeSlider.Text:SetText("")
        controls.sizeSlider:Hide()
        
        controls.sizeValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.sizeValue:SetPoint("LEFT", controls.sizeSlider, "RIGHT", 8, 0)
        controls.sizeValue:SetTextColor(1, 1, 1)
        controls.sizeValue:Hide()
        
        -- Opacity slider
        controls.opacityLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.opacityLabel:SetPoint("TOPLEFT", 10, -145)
        controls.opacityLabel:SetText("Opacity:")
        controls.opacityLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.opacityLabel:Hide()
        
        controls.opacitySlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.opacitySlider:SetPoint("LEFT", controls.opacityLabel, "RIGHT", 5, 0)
        controls.opacitySlider:SetSize(90, 16)
        controls.opacitySlider:SetMinMaxValues(0.1, 1.0)
        controls.opacitySlider:SetValueStep(0.05)
        controls.opacitySlider:SetObeyStepOnDrag(true)
        controls.opacitySlider.Low:SetText("")
        controls.opacitySlider.High:SetText("")
        controls.opacitySlider.Text:SetText("")
        controls.opacitySlider:Hide()
        
        controls.opacityValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.opacityValue:SetPoint("LEFT", controls.opacitySlider, "RIGHT", 8, 0)
        controls.opacityValue:SetTextColor(1, 1, 1)
        controls.opacityValue:Hide()
        
        -- Desaturate checkbox
        controls.desatCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.desatCheck:SetPoint("TOPLEFT", 10, -175)
        controls.desatCheck:SetSize(24, 24)
        controls.desatCheck:Hide()
        
        controls.desatLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.desatLabel:SetPoint("LEFT", controls.desatCheck, "RIGHT", 2, 0)
        controls.desatLabel:SetText("Desaturate (grayscale)")
        controls.desatLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.desatLabel:Hide()
        
        -- Proc glow checkbox
        controls.procGlowCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.procGlowCheck:SetPoint("LEFT", controls.desatLabel, "RIGHT", 20, 0)
        controls.procGlowCheck:SetSize(24, 24)
        controls.procGlowCheck:Hide()
        
        controls.procGlowLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.procGlowLabel:SetPoint("LEFT", controls.procGlowCheck, "RIGHT", 2, 0)
        controls.procGlowLabel:SetText("Show Proc Glow")
        controls.procGlowLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.procGlowLabel:Hide()
        
        -- Aspect ratio dropdown
        controls.aspectLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.aspectLabel:SetPoint("TOPLEFT", 10, -205)
        controls.aspectLabel:SetText("Aspect Ratio:")
        controls.aspectLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.aspectLabel:Hide()
        
        controls.aspectDropdown = CreateFrame("Frame", nil, controlsPanel, "UIDropDownMenuTemplate")
        controls.aspectDropdown:SetPoint("TOPLEFT", 60, -200)
        UIDropDownMenu_SetWidth(controls.aspectDropdown, 100)
        controls.aspectDropdown:Hide()
        
        -- Custom aspect ratio inputs
        controls.customLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.customLabel:SetPoint("TOPLEFT", 10, -235)
        controls.customLabel:SetText("Custom W:")
        controls.customLabel:SetTextColor(0.7, 0.7, 0.7)
        controls.customLabel:Hide()
        
        controls.customW = CreateFrame("EditBox", nil, controlsPanel, "InputBoxTemplate")
        controls.customW:SetPoint("LEFT", controls.customLabel, "RIGHT", 2, 0)
        controls.customW:SetSize(30, 18)
        controls.customW:SetAutoFocus(false)
        controls.customW:SetNumeric(true)
        controls.customW:SetMaxLetters(3)
        controls.customW:Hide()
        
        controls.customSep = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.customSep:SetPoint("LEFT", controls.customW, "RIGHT", 4, 0)
        controls.customSep:SetText("H:")
        controls.customSep:SetTextColor(0.7, 0.7, 0.7)
        controls.customSep:Hide()
        
        controls.customH = CreateFrame("EditBox", nil, controlsPanel, "InputBoxTemplate")
        controls.customH:SetPoint("LEFT", controls.customSep, "RIGHT", 2, 0)
        controls.customH:SetSize(30, 18)
        controls.customH:SetAutoFocus(false)
        controls.customH:SetNumeric(true)
        controls.customH:SetMaxLetters(3)
        controls.customH:Hide()
        
        -- =====================================================
        -- Dock Assignment
        -- =====================================================
        controls.dockHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.dockHeader:SetPoint("TOPLEFT", 10, -265)
        controls.dockHeader:SetText("Dock Assignment")
        controls.dockHeader:SetTextColor(1, 0.82, 0)
        controls.dockHeader:Hide()
        
        controls.dockLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.dockLabel:SetPoint("TOPLEFT", 10, -285)
        controls.dockLabel:SetText("Assign to Dock:")
        controls.dockLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.dockLabel:Hide()
        
        controls.dockDropdown = CreateFrame("Frame", nil, controlsPanel, "UIDropDownMenuTemplate")
        controls.dockDropdown:SetPoint("TOPLEFT", 80, -278)
        UIDropDownMenu_SetWidth(controls.dockDropdown, 120)
        controls.dockDropdown:Hide()
        
        -- =====================================================
        -- Per-Icon Text Controls (Cooldown Timer)
        -- =====================================================
        controls.cooldownTextHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.cooldownTextHeader:SetPoint("TOPLEFT", 10, -345)
        controls.cooldownTextHeader:SetText("Cooldown Text")
        controls.cooldownTextHeader:SetTextColor(1, 0.82, 0)
        controls.cooldownTextHeader:Hide()
        
        controls.cooldownTextScaleLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextScaleLabel:SetPoint("TOPLEFT", 10, -365)
        controls.cooldownTextScaleLabel:SetText("Scale:")
        controls.cooldownTextScaleLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextScaleLabel:Hide()
        
        controls.cooldownTextSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.cooldownTextSlider:SetPoint("LEFT", controls.cooldownTextScaleLabel, "RIGHT", 10, 0)
        controls.cooldownTextSlider:SetSize(80, 16)
        controls.cooldownTextSlider:SetMinMaxValues(0.5, 2.0)
        controls.cooldownTextSlider:SetValueStep(0.1)
        controls.cooldownTextSlider:SetObeyStepOnDrag(true)
        controls.cooldownTextSlider.Low:SetText("")
        controls.cooldownTextSlider.High:SetText("")
        controls.cooldownTextSlider.Text:SetText("")
        controls.cooldownTextSlider:Hide()
        
        controls.cooldownTextValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextValue:SetPoint("LEFT", controls.cooldownTextSlider, "RIGHT", 5, 0)
        controls.cooldownTextValue:SetTextColor(1, 1, 1)
        controls.cooldownTextValue:Hide()
        
        controls.cooldownTextColorLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextColorLabel:SetPoint("TOPLEFT", 10, -390)
        controls.cooldownTextColorLabel:SetText("Color:")
        controls.cooldownTextColorLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextColorLabel:Hide()
        
        controls.cooldownTextColorBtn = CreateFrame("Button", nil, controlsPanel, "BackdropTemplate")
        controls.cooldownTextColorBtn:SetPoint("LEFT", controls.cooldownTextColorLabel, "RIGHT", 10, 0)
        controls.cooldownTextColorBtn:SetSize(24, 16)
        controls.cooldownTextColorBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
        controls.cooldownTextColorBtn:SetBackdropColor(1, 1, 1, 1)
        controls.cooldownTextColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        controls.cooldownTextColorBtn:Hide()
        
        controls.cooldownTextOffsetXLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetXLabel:SetPoint("TOPLEFT", 10, -415)
        controls.cooldownTextOffsetXLabel:SetText("Offset X:")
        controls.cooldownTextOffsetXLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextOffsetXLabel:Hide()
        
        controls.cooldownTextOffsetXSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.cooldownTextOffsetXSlider:SetPoint("LEFT", controls.cooldownTextOffsetXLabel, "RIGHT", 5, 0)
        controls.cooldownTextOffsetXSlider:SetSize(100, 16)
        controls.cooldownTextOffsetXSlider:SetMinMaxValues(-100, 100)
        controls.cooldownTextOffsetXSlider:SetValueStep(1)
        controls.cooldownTextOffsetXSlider:SetObeyStepOnDrag(true)
        controls.cooldownTextOffsetXSlider.Low:SetText("")
        controls.cooldownTextOffsetXSlider.High:SetText("")
        controls.cooldownTextOffsetXSlider.Text:SetText("")
        controls.cooldownTextOffsetXSlider:Hide()
        
        controls.cooldownTextOffsetXValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetXValue:SetPoint("LEFT", controls.cooldownTextOffsetXSlider, "RIGHT", 5, 0)
        controls.cooldownTextOffsetXValue:SetTextColor(1, 1, 1)
        controls.cooldownTextOffsetXValue:Hide()
        
        controls.cooldownTextOffsetYLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetYLabel:SetPoint("TOPLEFT", 10, -440)
        controls.cooldownTextOffsetYLabel:SetText("Offset Y:")
        controls.cooldownTextOffsetYLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextOffsetYLabel:Hide()
        
        controls.cooldownTextOffsetYSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.cooldownTextOffsetYSlider:SetPoint("LEFT", controls.cooldownTextOffsetYLabel, "RIGHT", 5, 0)
        controls.cooldownTextOffsetYSlider:SetSize(100, 16)
        controls.cooldownTextOffsetYSlider:SetMinMaxValues(-100, 100)
        controls.cooldownTextOffsetYSlider:SetValueStep(1)
        controls.cooldownTextOffsetYSlider:SetObeyStepOnDrag(true)
        controls.cooldownTextOffsetYSlider.Low:SetText("")
        controls.cooldownTextOffsetYSlider.High:SetText("")
        controls.cooldownTextOffsetYSlider.Text:SetText("")
        controls.cooldownTextOffsetYSlider:Hide()
        
        controls.cooldownTextOffsetYValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetYValue:SetPoint("LEFT", controls.cooldownTextOffsetYSlider, "RIGHT", 5, 0)
        controls.cooldownTextOffsetYValue:SetTextColor(1, 1, 1)
        controls.cooldownTextOffsetYValue:Hide()
        
        -- =====================================================
        -- Per-Icon Text Controls (Count/Charge Text)
        -- =====================================================
        controls.countTextHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.countTextHeader:SetPoint("TOPLEFT", 10, -470)
        controls.countTextHeader:SetText("Count/Charge Text")
        controls.countTextHeader:SetTextColor(1, 0.82, 0)
        controls.countTextHeader:Hide()
        
        controls.countTextScaleLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextScaleLabel:SetPoint("TOPLEFT", 10, -490)
        controls.countTextScaleLabel:SetText("Scale:")
        controls.countTextScaleLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextScaleLabel:Hide()
        
        controls.countTextSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.countTextSlider:SetPoint("LEFT", controls.countTextScaleLabel, "RIGHT", 10, 0)
        controls.countTextSlider:SetSize(80, 16)
        controls.countTextSlider:SetMinMaxValues(0.5, 2.0)
        controls.countTextSlider:SetValueStep(0.1)
        controls.countTextSlider:SetObeyStepOnDrag(true)
        controls.countTextSlider.Low:SetText("")
        controls.countTextSlider.High:SetText("")
        controls.countTextSlider.Text:SetText("")
        controls.countTextSlider:Hide()
        
        controls.countTextValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextValue:SetPoint("LEFT", controls.countTextSlider, "RIGHT", 5, 0)
        controls.countTextValue:SetTextColor(1, 1, 1)
        controls.countTextValue:Hide()
        
        controls.countTextColorLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextColorLabel:SetPoint("TOPLEFT", 10, -515)
        controls.countTextColorLabel:SetText("Color:")
        controls.countTextColorLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextColorLabel:Hide()
        
        controls.countTextColorBtn = CreateFrame("Button", nil, controlsPanel, "BackdropTemplate")
        controls.countTextColorBtn:SetPoint("LEFT", controls.countTextColorLabel, "RIGHT", 10, 0)
        controls.countTextColorBtn:SetSize(24, 16)
        controls.countTextColorBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
        controls.countTextColorBtn:SetBackdropColor(1, 1, 1, 1)
        controls.countTextColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        controls.countTextColorBtn:Hide()
        
        controls.countTextOffsetXLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetXLabel:SetPoint("TOPLEFT", 10, -540)
        controls.countTextOffsetXLabel:SetText("Offset X:")
        controls.countTextOffsetXLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextOffsetXLabel:Hide()
        
        controls.countTextOffsetXSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.countTextOffsetXSlider:SetPoint("LEFT", controls.countTextOffsetXLabel, "RIGHT", 5, 0)
        controls.countTextOffsetXSlider:SetSize(100, 16)
        controls.countTextOffsetXSlider:SetMinMaxValues(-100, 100)
        controls.countTextOffsetXSlider:SetValueStep(1)
        controls.countTextOffsetXSlider:SetObeyStepOnDrag(true)
        controls.countTextOffsetXSlider.Low:SetText("")
        controls.countTextOffsetXSlider.High:SetText("")
        controls.countTextOffsetXSlider.Text:SetText("")
        controls.countTextOffsetXSlider:Hide()
        
        controls.countTextOffsetXValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetXValue:SetPoint("LEFT", controls.countTextOffsetXSlider, "RIGHT", 5, 0)
        controls.countTextOffsetXValue:SetTextColor(1, 1, 1)
        controls.countTextOffsetXValue:Hide()
        
        controls.countTextOffsetYLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetYLabel:SetPoint("TOPLEFT", 10, -565)
        controls.countTextOffsetYLabel:SetText("Offset Y:")
        controls.countTextOffsetYLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextOffsetYLabel:Hide()
        
        controls.countTextOffsetYSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.countTextOffsetYSlider:SetPoint("LEFT", controls.countTextOffsetYLabel, "RIGHT", 5, 0)
        controls.countTextOffsetYSlider:SetSize(100, 16)
        controls.countTextOffsetYSlider:SetMinMaxValues(-100, 100)
        controls.countTextOffsetYSlider:SetValueStep(1)
        controls.countTextOffsetYSlider:SetObeyStepOnDrag(true)
        controls.countTextOffsetYSlider.Low:SetText("")
        controls.countTextOffsetYSlider.High:SetText("")
        controls.countTextOffsetYSlider.Text:SetText("")
        controls.countTextOffsetYSlider:Hide()
        
        controls.countTextOffsetYValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetYValue:SetPoint("LEFT", controls.countTextOffsetYSlider, "RIGHT", 5, 0)
        controls.countTextOffsetYValue:SetTextColor(1, 1, 1)
        controls.countTextOffsetYValue:Hide()
        
        -- =====================================================
        -- Custom Label Controls (Accessibility feature)
        -- =====================================================
        controls.labelHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.labelHeader:SetPoint("TOPLEFT", 10, -635)
        controls.labelHeader:SetText("Custom Label (Accessibility)")
        controls.labelHeader:SetTextColor(1, 0.82, 0)
        controls.labelHeader:Hide()
        
        controls.labelEnableCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.labelEnableCheck:SetPoint("TOPLEFT", 10, -655)
        controls.labelEnableCheck:SetSize(24, 24)
        controls.labelEnableCheck:Hide()
        
        controls.labelEnableLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelEnableLabel:SetPoint("LEFT", controls.labelEnableCheck, "RIGHT", 2, 0)
        controls.labelEnableLabel:SetText("Show Custom Label")
        controls.labelEnableLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.labelEnableLabel:Hide()
        
        controls.labelTextLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelTextLabel:SetPoint("TOPLEFT", 10, -685)
        controls.labelTextLabel:SetText("Text:")
        controls.labelTextLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelTextLabel:Hide()
        
        controls.labelTextBox = CreateFrame("EditBox", nil, controlsPanel, "InputBoxTemplate")
        controls.labelTextBox:SetPoint("LEFT", controls.labelTextLabel, "RIGHT", 8, 0)
        controls.labelTextBox:SetSize(120, 18)
        controls.labelTextBox:SetAutoFocus(false)
        controls.labelTextBox:SetMaxLetters(20)
        controls.labelTextBox:Hide()
        
        controls.labelSizeLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelSizeLabel:SetPoint("LEFT", controls.labelTextBox, "RIGHT", 15, 0)
        controls.labelSizeLabel:SetText("Size:")
        controls.labelSizeLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelSizeLabel:Hide()
        
        controls.labelSizeSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.labelSizeSlider:SetPoint("LEFT", controls.labelSizeLabel, "RIGHT", 5, 0)
        controls.labelSizeSlider:SetSize(60, 16)
        controls.labelSizeSlider:SetMinMaxValues(8, 32)
        controls.labelSizeSlider:SetValueStep(1)
        controls.labelSizeSlider:SetObeyStepOnDrag(true)
        controls.labelSizeSlider.Low:SetText("")
        controls.labelSizeSlider.High:SetText("")
        controls.labelSizeSlider.Text:SetText("")
        controls.labelSizeSlider:Hide()
        
        controls.labelSizeValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelSizeValue:SetPoint("LEFT", controls.labelSizeSlider, "RIGHT", 5, 0)
        controls.labelSizeValue:SetTextColor(1, 1, 1)
        controls.labelSizeValue:Hide()
        
        controls.labelColorLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelColorLabel:SetPoint("TOPLEFT", 10, -710)
        controls.labelColorLabel:SetText("Color:")
        controls.labelColorLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelColorLabel:Hide()
        
        controls.labelColorBtn = CreateFrame("Button", nil, controlsPanel, "BackdropTemplate")
        controls.labelColorBtn:SetPoint("LEFT", controls.labelColorLabel, "RIGHT", 8, 0)
        controls.labelColorBtn:SetSize(20, 20)
        controls.labelColorBtn:SetBackdrop({ 
            bgFile = "Interface\\BUTTONS\\WHITE8X8", 
            edgeFile = "Interface\\BUTTONS\\WHITE8X8", 
            edgeSize = 1 
        })
        controls.labelColorBtn:SetBackdropColor(1, 1, 1, 1)
        controls.labelColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        controls.labelColorBtn:Hide()
        
        controls.labelOffsetLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetLabel:SetPoint("LEFT", controls.labelColorBtn, "RIGHT", 15, 0)
        controls.labelOffsetLabel:SetText("X:")
        controls.labelOffsetLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelOffsetLabel:Hide()
        
        controls.labelOffsetXSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.labelOffsetXSlider:SetPoint("LEFT", controls.labelOffsetLabel, "RIGHT", 3, 0)
        controls.labelOffsetXSlider:SetSize(100, 16)
        controls.labelOffsetXSlider:SetMinMaxValues(-100, 100)
        controls.labelOffsetXSlider:SetValueStep(1)
        controls.labelOffsetXSlider:SetObeyStepOnDrag(true)
        controls.labelOffsetXSlider.Low:SetText("")
        controls.labelOffsetXSlider.High:SetText("")
        controls.labelOffsetXSlider.Text:SetText("")
        controls.labelOffsetXSlider:Hide()
        
        controls.labelOffsetXValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetXValue:SetPoint("LEFT", controls.labelOffsetXSlider, "RIGHT", 3, 0)
        controls.labelOffsetXValue:SetTextColor(1, 1, 1)
        controls.labelOffsetXValue:Hide()
        
        controls.labelOffsetYLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetYLabel:SetPoint("LEFT", controls.labelOffsetXValue, "RIGHT", 8, 0)
        controls.labelOffsetYLabel:SetText("Y:")
        controls.labelOffsetYLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelOffsetYLabel:Hide()
        
        controls.labelOffsetYSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.labelOffsetYSlider:SetPoint("LEFT", controls.labelOffsetYLabel, "RIGHT", 3, 0)
        controls.labelOffsetYSlider:SetSize(100, 16)
        controls.labelOffsetYSlider:SetMinMaxValues(-100, 100)
        controls.labelOffsetYSlider:SetValueStep(1)
        controls.labelOffsetYSlider:SetObeyStepOnDrag(true)
        controls.labelOffsetYSlider.Low:SetText("")
        controls.labelOffsetYSlider.High:SetText("")
        controls.labelOffsetYSlider.Text:SetText("")
        controls.labelOffsetYSlider:Hide()
        
        controls.labelOffsetYValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetYValue:SetPoint("LEFT", controls.labelOffsetYSlider, "RIGHT", 3, 0)
        controls.labelOffsetYValue:SetTextColor(1, 1, 1)
        controls.labelOffsetYValue:Hide()
        
        -- Helper to show/hide all controls
        local function ShowControls(show)
            noSelectionLabel:SetShown(not show)
            for _, ctrl in pairs(controls) do
                if ctrl.SetShown then ctrl:SetShown(show)
                elseif ctrl.Show then
                    if show then ctrl:Show() else ctrl:Hide() end
                end
            end
        end
        
        -- Helper to update state button appearance
        local function UpdateStateButtons()
            if currentState == "active" then
                controls.activeBtn:SetNormalFontObject("GameFontHighlight")
                controls.inactiveBtn:SetNormalFontObject("GameFontNormal")
                controls.showLabel:SetText("Show when buff is Active")
            else
                controls.activeBtn:SetNormalFontObject("GameFontNormal")
                controls.inactiveBtn:SetNormalFontObject("GameFontHighlight")
                controls.showLabel:SetText("Show when buff is Missing")
            end
        end
        
        -- Helper to update custom aspect visibility
        local function UpdateCustomAspectVisibility(aspectRatio)
            local showCustom = (aspectRatio == "custom")
            controls.customLabel:SetShown(showCustom)
            controls.customW:SetShown(showCustom)
            controls.customSep:SetShown(showCustom)
            controls.customH:SetShown(showCustom)
        end
        
        -- Update controls for selected slot
        local function UpdateControlsForSlot(slotIndex)
            if not slotIndex or not BuffHighlights then
                ShowControls(false)
                return
            end
            
            ShowControls(true)
            UpdateStateButtons()
            
            -- Get slot info for icon preview - use same order as list (GetOrderedIcons)
            local viewer = _G["BuffIconCooldownViewer"]
            if viewer then
                local icons = GetOrderedIcons(viewer, "buffs")
                local icon = icons[slotIndex]
                if icon then
                    local textureObj = icon.Icon or icon.icon
                    if textureObj then
                        pcall(function()
                            controls.iconPreview:SetTexture(textureObj:GetTexture())
                        end)
                    end
                end
            end
            
            controls.header:SetText("Slot #" .. slotIndex)
            
            -- Get settings for current state
            local db = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.buffHighlights
            local isEnabled = db and db.enabled and db.enabled[slotIndex]
            local showState = BuffHighlights:GetShowState(slotIndex, currentState)
            local size = BuffHighlights:GetSize(slotIndex, currentState)
            local opacity = BuffHighlights:GetOpacity(slotIndex, currentState)
            local saturated = BuffHighlights:GetSaturation(slotIndex, currentState)
            local aspectRatio = BuffHighlights:GetAspectRatio(slotIndex, currentState)
            local customW, customH = BuffHighlights:GetCustomAspectRatio(slotIndex, currentState)
            
            -- Clear slider scripts BEFORE setting values to prevent old callbacks from firing
            controls.sizeSlider:SetScript("OnValueChanged", nil)
            controls.opacitySlider:SetScript("OnValueChanged", nil)
            controls.labelSizeSlider:SetScript("OnValueChanged", nil)
            controls.labelOffsetXSlider:SetScript("OnValueChanged", nil)
            controls.labelOffsetYSlider:SetScript("OnValueChanged", nil)
            controls.cooldownTextSlider:SetScript("OnValueChanged", nil)
            controls.cooldownTextOffsetXSlider:SetScript("OnValueChanged", nil)
            controls.cooldownTextOffsetYSlider:SetScript("OnValueChanged", nil)
            controls.countTextSlider:SetScript("OnValueChanged", nil)
            controls.countTextOffsetXSlider:SetScript("OnValueChanged", nil)
            controls.countTextOffsetYSlider:SetScript("OnValueChanged", nil)
            
            -- Update control values
            controls.enableCheck:SetChecked(isEnabled)
            controls.hideCheck:SetChecked(BuffHighlights:IsIconHidden(slotIndex))
            controls.showCheck:SetChecked(showState)
            controls.sizeSlider:SetValue(size)
            controls.sizeValue:SetText(tostring(size))
            controls.opacitySlider:SetValue(opacity)
            controls.opacityValue:SetText(math.floor(opacity * 100) .. "%")
            controls.desatCheck:SetChecked(not saturated)
            local showProcGlow = BuffHighlights:GetShowProcGlow(slotIndex)
            controls.procGlowCheck:SetChecked(showProcGlow == nil or showProcGlow == true)
            controls.customW:SetText(tostring(customW))
            controls.customH:SetText(tostring(customH))
            
            -- Per-icon text settings (state-independent)
            local cdTextScale = BuffHighlights:GetCooldownTextScale(slotIndex)
            local cdTextColor = BuffHighlights:GetCooldownTextColor(slotIndex)
            local cdTextOffsetX = BuffHighlights:GetCooldownTextOffsetX(slotIndex)
            local cdTextOffsetY = BuffHighlights:GetCooldownTextOffsetY(slotIndex)
            
            controls.cooldownTextSlider:SetValue(cdTextScale or 1.0)
            controls.cooldownTextValue:SetText(string.format("%.1f", cdTextScale or 1.0))
            controls.cooldownTextColorBtn:SetBackdropColor(cdTextColor[1] or 1, cdTextColor[2] or 1, cdTextColor[3] or 1, 1)
            controls.cooldownTextOffsetXSlider:SetValue(cdTextOffsetX or 0)
            controls.cooldownTextOffsetXValue:SetText(tostring(cdTextOffsetX or 0))
            controls.cooldownTextOffsetYSlider:SetValue(cdTextOffsetY or 0)
            controls.cooldownTextOffsetYValue:SetText(tostring(cdTextOffsetY or 0))
            
            local cntTextScale = BuffHighlights:GetCountTextScale(slotIndex)
            local cntTextColor = BuffHighlights:GetCountTextColor(slotIndex)
            local cntTextOffsetX = BuffHighlights:GetCountTextOffsetX(slotIndex)
            local cntTextOffsetY = BuffHighlights:GetCountTextOffsetY(slotIndex)
            
            controls.countTextSlider:SetValue(cntTextScale or 1.0)
            controls.countTextValue:SetText(string.format("%.1f", cntTextScale or 1.0))
            controls.countTextColorBtn:SetBackdropColor(cntTextColor[1] or 1, cntTextColor[2] or 1, cntTextColor[3] or 1, 1)
            controls.countTextOffsetXSlider:SetValue(cntTextOffsetX or 0)
            controls.countTextOffsetXValue:SetText(tostring(cntTextOffsetX or 0))
            controls.countTextOffsetYSlider:SetValue(cntTextOffsetY or 0)
            controls.countTextOffsetYValue:SetText(tostring(cntTextOffsetY or 0))
            
            -- Label settings (state-independent)
            local labelEnabled = BuffHighlights:GetLabelEnabled(slotIndex)
            local labelText = BuffHighlights:GetLabelText(slotIndex)
            local labelSize = BuffHighlights:GetLabelFontSize(slotIndex)
            local labelColor = BuffHighlights:GetLabelColor(slotIndex)
            local labelOffsetX = BuffHighlights:GetLabelOffsetX(slotIndex)
            local labelOffsetY = BuffHighlights:GetLabelOffsetY(slotIndex)
            
            controls.labelEnableCheck:SetChecked(labelEnabled)
            controls.labelTextBox:SetText(labelText or "")
            controls.labelSizeSlider:SetValue(labelSize or 14)
            controls.labelSizeValue:SetText(tostring(labelSize or 14))
            controls.labelColorBtn:SetBackdropColor(labelColor[1] or 1, labelColor[2] or 1, labelColor[3] or 1, labelColor[4] or 1)
            controls.labelOffsetXSlider:SetValue(labelOffsetX or 0)
            controls.labelOffsetXValue:SetText(tostring(labelOffsetX or 0))
            controls.labelOffsetYSlider:SetValue(labelOffsetY or 0)
            controls.labelOffsetYValue:SetText(tostring(labelOffsetY or 0))
            
            -- Initialize aspect dropdown
            UIDropDownMenu_Initialize(controls.aspectDropdown, function(self, level)
                for _, opt in ipairs(ASPECT_OPTIONS) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = opt.label
                    info.value = opt.value
                    info.func = function(self)
                        BuffHighlights:SetAspectRatio(slotIndex, currentState, self.value)
                        UIDropDownMenu_SetText(controls.aspectDropdown, self:GetText())
                        UpdateCustomAspectVisibility(self.value)
                    end
                    info.checked = (aspectRatio == opt.value)
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            
            -- Set dropdown text
            for _, opt in ipairs(ASPECT_OPTIONS) do
                if opt.value == aspectRatio then
                    UIDropDownMenu_SetText(controls.aspectDropdown, opt.label)
                    break
                end
            end
            
            UpdateCustomAspectVisibility(aspectRatio)
            
            -- Initialize dock dropdown
            local currentDock = BuffHighlights:GetDockAssignment(slotIndex) or 0
            UIDropDownMenu_Initialize(controls.dockDropdown, function(self, level)
                -- None option
                local info = UIDropDownMenu_CreateInfo()
                info.text = "None"
                info.value = 0
                info.func = function()
                    BuffHighlights:SetDockAssignment(slotIndex, nil)
                    UIDropDownMenu_SetText(controls.dockDropdown, "None")
                end
                info.checked = (currentDock == 0 or currentDock == nil)
                UIDropDownMenu_AddButton(info, level)
                
                -- Dock options (1-4)
                local numDocks = TUICD.Docks and TUICD.Docks:GetDockCount() or 4
                for i = 1, numDocks do
                    local dockName = TUICD.Docks and TUICD.Docks:GetDockName(i) or ("Dock " .. i)
                    local dockSettings = TUICD.Docks and TUICD.Docks:GetDockSettings(i) or {}
                    
                    info = UIDropDownMenu_CreateInfo()
                    if dockSettings.enabled then
                        info.text = "|cff00ff00" .. dockName .. "|r"
                    else
                        info.text = "|cff888888" .. dockName .. " (disabled)|r"
                    end
                    info.value = i
                    info.func = function()
                        BuffHighlights:SetDockAssignment(slotIndex, i)
                        UIDropDownMenu_SetText(controls.dockDropdown, dockName)
                    end
                    info.checked = (currentDock == i)
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            
            -- Set dock dropdown text
            if currentDock and currentDock > 0 then
                local dockName = TUICD.Docks and TUICD.Docks:GetDockName(currentDock) or ("Dock " .. currentDock)
                UIDropDownMenu_SetText(controls.dockDropdown, dockName)
            else
                UIDropDownMenu_SetText(controls.dockDropdown, "None")
            end
            
            -- Wire up control callbacks
            controls.enableCheck:SetScript("OnClick", function(self)
                BuffHighlights:EnableHighlight(slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.activeBtn:SetScript("OnClick", function()
                currentState = "active"
                UpdateControlsForSlot(slotIndex)
            end)
            
            controls.inactiveBtn:SetScript("OnClick", function()
                currentState = "inactive"
                UpdateControlsForSlot(slotIndex)
            end)
            
            controls.showCheck:SetScript("OnClick", function(self)
                BuffHighlights:SetShowState(slotIndex, currentState, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.sizeSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.sizeValue:SetText(tostring(value))
                BuffHighlights:SetSize(slotIndex, currentState, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.opacitySlider:SetScript("OnValueChanged", function(self, value)
                controls.opacityValue:SetText(math.floor(value * 100) .. "%")
                BuffHighlights:SetOpacity(slotIndex, currentState, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.desatCheck:SetScript("OnClick", function(self)
                BuffHighlights:SetSaturation(slotIndex, currentState, not self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.procGlowCheck:SetScript("OnClick", function(self)
                BuffHighlights:SetShowProcGlow(slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            local function ApplyCustomAspect()
                local w = tonumber(controls.customW:GetText()) or 1
                local h = tonumber(controls.customH:GetText()) or 1
                if w < 1 then w = 1 end
                if h < 1 then h = 1 end
                BuffHighlights:SetCustomAspectRatio(slotIndex, currentState, w, h)
            end
            
            controls.customW:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                ApplyCustomAspect()
            end)
            controls.customW:SetScript("OnEditFocusLost", ApplyCustomAspect)
            
            controls.customH:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                ApplyCustomAspect()
            end)
            controls.customH:SetScript("OnEditFocusLost", ApplyCustomAspect)
            
            -- Label control event handlers
            controls.labelEnableCheck:SetScript("OnClick", function(self)
                BuffHighlights:SetLabelEnabled(slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.labelTextBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                BuffHighlights:SetLabelText(slotIndex, self:GetText())
                Cooldowns:SaveSettings()
            end)
            controls.labelTextBox:SetScript("OnEditFocusLost", function(self)
                BuffHighlights:SetLabelText(slotIndex, self:GetText())
                Cooldowns:SaveSettings()
            end)
            
            controls.labelSizeSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.labelSizeValue:SetText(tostring(value))
                BuffHighlights:SetLabelFontSize(slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.labelColorBtn:SetScript("OnClick", function()
                local currentColor = BuffHighlights:GetLabelColor(slotIndex)
                local r, g, b, a = currentColor[1] or 1, currentColor[2] or 1, currentColor[3] or 1, currentColor[4] or 1
                
                local info = {
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        local na = ColorPickerFrame:GetColorAlpha() or 1
                        controls.labelColorBtn:SetBackdropColor(nr, ng, nb, na)
                        BuffHighlights:SetLabelColor(slotIndex, {nr, ng, nb, na})
                        Cooldowns:SaveSettings()
                    end,
                    opacityFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        local na = ColorPickerFrame:GetColorAlpha() or 1
                        controls.labelColorBtn:SetBackdropColor(nr, ng, nb, na)
                        BuffHighlights:SetLabelColor(slotIndex, {nr, ng, nb, na})
                        Cooldowns:SaveSettings()
                    end,
                    cancelFunc = function(prev)
                        controls.labelColorBtn:SetBackdropColor(prev.r, prev.g, prev.b, prev.a or 1)
                        BuffHighlights:SetLabelColor(slotIndex, {prev.r, prev.g, prev.b, prev.a or 1})
                        Cooldowns:SaveSettings()
                    end,
                    hasOpacity = true,
                    opacity = a,
                    r = r,
                    g = g,
                    b = b,
                }
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            
            controls.labelOffsetXSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.labelOffsetXValue:SetText(tostring(value))
                BuffHighlights:SetLabelOffsetX(slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.labelOffsetYSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.labelOffsetYValue:SetText(tostring(value))
                BuffHighlights:SetLabelOffsetY(slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            -- Hide icon checkbox handler
            controls.hideCheck:SetScript("OnClick", function(self)
                BuffHighlights:SetIconHidden(slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
                -- Invalidate buff state cache to force re-apply of visual state
                Cooldowns.InvalidateBuffStateCache(slotIndex)
                -- Refresh the buff tracker layout to show/hide the icon
                Cooldowns.RefreshTrackerLayout("buffs")
            end)
            
            -- Cooldown text control handlers
            controls.cooldownTextSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value * 10) / 10  -- Round to 1 decimal
                controls.cooldownTextValue:SetText(string.format("%.1f", value))
                BuffHighlights:SetCooldownTextScale(slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.cooldownTextColorBtn:SetScript("OnClick", function()
                local currentColor = BuffHighlights:GetCooldownTextColor(slotIndex)
                local r, g, b = currentColor[1] or 1, currentColor[2] or 1, currentColor[3] or 1
                
                local info = {
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        controls.cooldownTextColorBtn:SetBackdropColor(nr, ng, nb, 1)
                        BuffHighlights:SetCooldownTextColor(slotIndex, {nr, ng, nb})
                        Cooldowns:SaveSettings()
                    end,
                    cancelFunc = function(prev)
                        controls.cooldownTextColorBtn:SetBackdropColor(prev.r, prev.g, prev.b, 1)
                        BuffHighlights:SetCooldownTextColor(slotIndex, {prev.r, prev.g, prev.b})
                        Cooldowns:SaveSettings()
                    end,
                    hasOpacity = false,
                    r = r,
                    g = g,
                    b = b,
                }
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            
            controls.cooldownTextOffsetXSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.cooldownTextOffsetXValue:SetText(tostring(value))
                BuffHighlights:SetCooldownTextOffsetX(slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.cooldownTextOffsetYSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.cooldownTextOffsetYValue:SetText(tostring(value))
                BuffHighlights:SetCooldownTextOffsetY(slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            -- Count text control handlers
            controls.countTextSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value * 10) / 10  -- Round to 1 decimal
                controls.countTextValue:SetText(string.format("%.1f", value))
                BuffHighlights:SetCountTextScale(slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.countTextColorBtn:SetScript("OnClick", function()
                local currentColor = BuffHighlights:GetCountTextColor(slotIndex)
                local r, g, b = currentColor[1] or 1, currentColor[2] or 1, currentColor[3] or 1
                
                local info = {
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        controls.countTextColorBtn:SetBackdropColor(nr, ng, nb, 1)
                        BuffHighlights:SetCountTextColor(slotIndex, {nr, ng, nb})
                        Cooldowns:SaveSettings()
                    end,
                    cancelFunc = function(prev)
                        controls.countTextColorBtn:SetBackdropColor(prev.r, prev.g, prev.b, 1)
                        BuffHighlights:SetCountTextColor(slotIndex, {prev.r, prev.g, prev.b})
                        Cooldowns:SaveSettings()
                    end,
                    hasOpacity = false,
                    r = r,
                    g = g,
                    b = b,
                }
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            
            controls.countTextOffsetXSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.countTextOffsetXValue:SetText(tostring(value))
                BuffHighlights:SetCountTextOffsetX(slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.countTextOffsetYSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.countTextOffsetYValue:SetText(tostring(value))
                BuffHighlights:SetCountTextOffsetY(slotIndex, value)
                Cooldowns:SaveSettings()
            end)
        end
        
        -- Refresh slot list
        local function RefreshSlotList()
            for _, row in ipairs(slotRows) do
                row:Hide()
                row:SetParent(nil)
            end
            wipe(slotRows)
            
            local viewer = _G["BuffIconCooldownViewer"]
            if not viewer then
                local noBuffs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noBuffs:SetPoint("CENTER")
                noBuffs:SetText("Buff Tracker not loaded")
                noBuffs:SetTextColor(0.5, 0.5, 0.5)
                slotRows[1] = noBuffs
                scrollChild:SetHeight(90)
                ShowControls(false)
                return
            end
            
            -- Use same order as layout (GetOrderedIcons)
            local icons = GetOrderedIcons(viewer, "buffs")
            if #icons == 0 then
                local noBuffs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noBuffs:SetPoint("CENTER")
                noBuffs:SetText("No buffs tracked")
                noBuffs:SetTextColor(0.5, 0.5, 0.5)
                slotRows[1] = noBuffs
                scrollChild:SetHeight(90)
                ShowControls(false)
                return
            end
            
            local rowY = -3
            local rowHeight = 21
            local db = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.buffHighlights
            
            for slotIndex = 1, #icons do
                local icon = icons[slotIndex]
                if icon then
                    local row = CreateFrame("Button", nil, scrollChild)
                    row:SetPoint("TOPLEFT", 3, rowY)
                    row:SetPoint("TOPRIGHT", -3, rowY)
                    row:SetHeight(rowHeight - 2)
                    
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
                    
                    local slotLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    slotLabel:SetPoint("LEFT", 4, 0)
                    slotLabel:SetText("#" .. slotIndex)
                    slotLabel:SetTextColor(0.8, 0.8, 0.8)
                    
                    local iconPreview = row:CreateTexture(nil, "ARTWORK")
                    iconPreview:SetPoint("LEFT", 22, 0)
                    iconPreview:SetSize(18, 18)
                    iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local textureObj = icon.Icon or icon.icon
                    if textureObj then
                        pcall(function() iconPreview:SetTexture(textureObj:GetTexture()) end)
                    end
                    
                    local isEnabled = db and db.enabled and db.enabled[slotIndex]
                    local enabledIndicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    enabledIndicator:SetPoint("LEFT", 45, 0)
                    enabledIndicator:SetText(isEnabled and "|cff00ff00On|r" or "|cff666666Off|r")
                    
                    row.slotIndex = slotIndex
                    row:SetScript("OnClick", function(self)
                        selectedSlot = self.slotIndex
                        for _, r in ipairs(slotRows) do
                            if r.bg then r.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3) end
                        end
                        self.bg:SetColorTexture(0.3, 0.5, 0.3, 0.6)
                        currentState = "active"
                        UpdateControlsForSlot(self.slotIndex)
                    end)
                    
                    row:SetScript("OnEnter", function(self)
                        if selectedSlot ~= self.slotIndex then
                            self.bg:SetColorTexture(0.25, 0.25, 0.3, 0.5)
                        end
                    end)
                    
                    row:SetScript("OnLeave", function(self)
                        if selectedSlot ~= self.slotIndex then
                            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
                        end
                    end)
                    
                    slotRows[#slotRows + 1] = row
                    rowY = rowY - rowHeight
                end
            end
            
            
            -- Update scroll child height based on content
            local totalHeight = math.max(90, #slotRows * rowHeight + 6)
            scrollChild:SetHeight(totalHeight)
            if not selectedSlot and #slotRows > 0 and slotRows[1].slotIndex then
                slotRows[1]:Click()
            end
        end
        
        C_Timer.After(0.1, RefreshSlotList)
        
        -- Set the refresh button script (button created at top of tab)
        refreshBtn:SetScript("OnClick", function()
            selectedSlot = nil
            RefreshSlotList()
        end)
        
        parent:SetHeight(math.abs(y) + 370)
    end
    
    -- TAB: Individual Icons Settings for Cooldown Trackers (Essential, Utility)
    -- ========================================
    local function BuildCooldownHighlightsTab(parent)
        local y = -10
        local CooldownHighlights = TUICD.CooldownHighlights
        local selectedSlot = nil
        local currentState = "active"  -- "active" = ready, "inactive" = on cooldown
        local slotRows = {}
        
        -- Aspect ratio presets
        local ASPECT_OPTIONS = {
            { label = "1:1 (Square)", value = "1:1" },
            { label = "4:3", value = "4:3" },
            { label = "3:4", value = "3:4" },
            { label = "16:9 (Wide)", value = "16:9" },
            { label = "9:16 (Tall)", value = "9:16" },
            { label = "2:1", value = "2:1" },
            { label = "1:2", value = "1:2" },
            { label = "Custom", value = "custom" },
        }
        
        -- Get the viewer name for this tracker
        local viewerName = trackerInfo.name
        local trackerDisplayName = trackerInfo.displayName
        
        -- Header
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 5, y)
        header:SetText("Individual Icons")
        header:SetTextColor(1, 0.82, 0)
        
        -- Refresh button (at top right, script set later after RefreshSlotList is defined)
        local refreshBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        refreshBtn:SetPoint("TOPRIGHT", -5, y)
        refreshBtn:SetSize(100, 20)
        refreshBtn:SetText("Refresh List")
        y = y - 26
        
        -- Description
        local description = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        description:SetPoint("TOPLEFT", 5, y)
        description:SetPoint("TOPRIGHT", -10, y)
        description:SetJustifyH("LEFT")
        description:SetText("|cff888888Create individual icons for your abilities that can be configured and moved outside of the main trackers.|r")
        y = y - 18
        
        -- Hide Tracker checkbox
        local hideTrackerCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        hideTrackerCheck:SetPoint("TOPLEFT", 5, y)
        hideTrackerCheck:SetSize(24, 24)
        hideTrackerCheck:SetChecked(CooldownHighlights and CooldownHighlights:IsTrackerHidden(trackerKey) or false)
        hideTrackerCheck:SetScript("OnClick", function(self)
            if CooldownHighlights then
                CooldownHighlights:SetTrackerHidden(trackerKey, self:GetChecked())
                Cooldowns:SaveSettings()
            end
        end)
        
        local hideTrackerLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hideTrackerLabel:SetPoint("LEFT", hideTrackerCheck, "RIGHT", 2, 0)
        hideTrackerLabel:SetText("Hide " .. trackerDisplayName .. " (use individual icons only)")
        hideTrackerLabel:SetTextColor(0.9, 0.9, 0.9)
        y = y - 26
        
        -- Slot list container
        local listContainer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        listContainer:SetPoint("TOPLEFT", 5, y)
        listContainer:SetSize(PANEL_WIDTH - 60, 90)
        listContainer:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        listContainer:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        listContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        
        -- Create scroll frame inside list container
        local scrollFrame = CreateFrame("ScrollFrame", nil, listContainer, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 2, -2)
        scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
        
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(PANEL_WIDTH - 84)
        scrollChild:SetHeight(1)  -- Will be updated dynamically
        scrollFrame:SetScrollChild(scrollChild)
        
        y = y - 100
        
        -- Controls container with backdrop (outer frame)
        local controlsContainer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        controlsContainer:SetPoint("TOPLEFT", 5, y)
        controlsContainer:SetSize(PANEL_WIDTH - 60, 560)
        controlsContainer:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        controlsContainer:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
        controlsContainer:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        
        -- Scroll frame inside container
        local controlsScrollFrame = CreateFrame("ScrollFrame", nil, controlsContainer, "UIPanelScrollFrameTemplate")
        controlsScrollFrame:SetPoint("TOPLEFT", 2, -2)
        controlsScrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
        
        -- Controls panel as scroll child (content area)
        local controlsPanel = CreateFrame("Frame", nil, controlsScrollFrame)
        controlsPanel:SetSize(PANEL_WIDTH - 84, 860)  -- Height for full content
        controlsScrollFrame:SetScrollChild(controlsPanel)
        
        -- "No Selection" label (on container, not scroll child, so it stays centered)
        local noSelectionLabel = controlsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noSelectionLabel:SetPoint("CENTER")
        noSelectionLabel:SetText("Select a cooldown slot above")
        noSelectionLabel:SetTextColor(0.5, 0.5, 0.5)
        
        -- All controls
        local controls = {}
        
        -- Slot header with icon preview
        controls.header = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.header:SetPoint("TOPLEFT", 10, -8)
        controls.header:SetTextColor(1, 0.82, 0)
        controls.header:Hide()
        
        controls.iconPreview = controlsPanel:CreateTexture(nil, "ARTWORK")
        controls.iconPreview:SetPoint("LEFT", controls.header, "RIGHT", 8, 0)
        controls.iconPreview:SetSize(20, 20)
        controls.iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        controls.iconPreview:Hide()
        
        -- Enable checkbox
        controls.enableCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.enableCheck:SetPoint("TOPLEFT", 10, -30)
        controls.enableCheck:SetSize(24, 24)
        controls.enableCheck:Hide()
        
        controls.enableLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.enableLabel:SetPoint("LEFT", controls.enableCheck, "RIGHT", 2, 0)
        controls.enableLabel:SetText("Enable Individual Icon")
        controls.enableLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.enableLabel:Hide()
        
        -- Hide in tracker checkbox (hide main tracker icon, keep highlight visible)
        controls.hideCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.hideCheck:SetPoint("LEFT", controls.enableLabel, "RIGHT", 20, 0)
        controls.hideCheck:SetSize(24, 24)
        controls.hideCheck:Hide()
        
        controls.hideLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.hideLabel:SetPoint("LEFT", controls.hideCheck, "RIGHT", 2, 0)
        controls.hideLabel:SetText("Hide in Tracker")
        controls.hideLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.hideLabel:Hide()
        
        -- State tabs (Ready / On Cooldown)
        controls.stateLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.stateLabel:SetPoint("TOPLEFT", 10, -58)
        controls.stateLabel:SetText("Configure State:")
        controls.stateLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.stateLabel:Hide()
        
        controls.activeBtn = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
        controls.activeBtn:SetPoint("LEFT", controls.stateLabel, "RIGHT", 8, 0)
        controls.activeBtn:SetSize(70, 20)
        controls.activeBtn:SetText("Ready")
        controls.activeBtn:Hide()
        
        controls.inactiveBtn = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
        controls.inactiveBtn:SetPoint("LEFT", controls.activeBtn, "RIGHT", 4, 0)
        controls.inactiveBtn:SetSize(90, 20)
        controls.inactiveBtn:SetText("On Cooldown")
        controls.inactiveBtn:Hide()
        
        -- Show when checkbox
        controls.showCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.showCheck:SetPoint("TOPLEFT", 10, -85)
        controls.showCheck:SetSize(24, 24)
        controls.showCheck:Hide()
        
        controls.showLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.showLabel:SetPoint("LEFT", controls.showCheck, "RIGHT", 2, 0)
        controls.showLabel:SetText("Show when Ready")
        controls.showLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.showLabel:Hide()
        
        -- Size slider
        controls.sizeLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.sizeLabel:SetPoint("TOPLEFT", 10, -115)
        controls.sizeLabel:SetText("Size:")
        controls.sizeLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.sizeLabel:Hide()
        
        controls.sizeSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.sizeSlider:SetPoint("LEFT", controls.sizeLabel, "RIGHT", 15, 0)
        controls.sizeSlider:SetSize(90, 16)
        controls.sizeSlider:SetMinMaxValues(24, 128)
        controls.sizeSlider:SetValueStep(2)
        controls.sizeSlider:SetObeyStepOnDrag(true)
        controls.sizeSlider.Low:SetText("")
        controls.sizeSlider.High:SetText("")
        controls.sizeSlider.Text:SetText("")
        controls.sizeSlider:Hide()
        
        controls.sizeValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.sizeValue:SetPoint("LEFT", controls.sizeSlider, "RIGHT", 8, 0)
        controls.sizeValue:SetTextColor(1, 1, 1)
        controls.sizeValue:Hide()
        
        -- Opacity slider
        controls.opacityLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.opacityLabel:SetPoint("TOPLEFT", 10, -145)
        controls.opacityLabel:SetText("Opacity:")
        controls.opacityLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.opacityLabel:Hide()
        
        controls.opacitySlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.opacitySlider:SetPoint("LEFT", controls.opacityLabel, "RIGHT", 5, 0)
        controls.opacitySlider:SetSize(90, 16)
        controls.opacitySlider:SetMinMaxValues(0.1, 1.0)
        controls.opacitySlider:SetValueStep(0.05)
        controls.opacitySlider:SetObeyStepOnDrag(true)
        controls.opacitySlider.Low:SetText("")
        controls.opacitySlider.High:SetText("")
        controls.opacitySlider.Text:SetText("")
        controls.opacitySlider:Hide()
        
        controls.opacityValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.opacityValue:SetPoint("LEFT", controls.opacitySlider, "RIGHT", 8, 0)
        controls.opacityValue:SetTextColor(1, 1, 1)
        controls.opacityValue:Hide()
        
        -- Desaturate checkbox
        controls.desatCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.desatCheck:SetPoint("TOPLEFT", 10, -175)
        controls.desatCheck:SetSize(24, 24)
        controls.desatCheck:Hide()
        
        controls.desatLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.desatLabel:SetPoint("LEFT", controls.desatCheck, "RIGHT", 2, 0)
        controls.desatLabel:SetText("Desaturate (grayscale)")
        controls.desatLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.desatLabel:Hide()
        
        -- Proc glow checkbox
        controls.procGlowCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.procGlowCheck:SetPoint("LEFT", controls.desatLabel, "RIGHT", 20, 0)
        controls.procGlowCheck:SetSize(24, 24)
        controls.procGlowCheck:Hide()
        
        controls.procGlowLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.procGlowLabel:SetPoint("LEFT", controls.procGlowCheck, "RIGHT", 2, 0)
        controls.procGlowLabel:SetText("Show Proc Glow")
        controls.procGlowLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.procGlowLabel:Hide()
        
        -- Aspect ratio dropdown
        controls.aspectLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.aspectLabel:SetPoint("TOPLEFT", 10, -205)
        controls.aspectLabel:SetText("Aspect Ratio:")
        controls.aspectLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.aspectLabel:Hide()
        
        controls.aspectDropdown = CreateFrame("Frame", nil, controlsPanel, "UIDropDownMenuTemplate")
        controls.aspectDropdown:SetPoint("TOPLEFT", 60, -200)
        UIDropDownMenu_SetWidth(controls.aspectDropdown, 100)
        controls.aspectDropdown:Hide()
        
        -- Custom aspect ratio inputs
        controls.customLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.customLabel:SetPoint("TOPLEFT", 10, -235)
        controls.customLabel:SetText("Custom W:")
        controls.customLabel:SetTextColor(0.7, 0.7, 0.7)
        controls.customLabel:Hide()
        
        controls.customW = CreateFrame("EditBox", nil, controlsPanel, "InputBoxTemplate")
        controls.customW:SetPoint("LEFT", controls.customLabel, "RIGHT", 2, 0)
        controls.customW:SetSize(30, 18)
        controls.customW:SetAutoFocus(false)
        controls.customW:SetNumeric(true)
        controls.customW:SetMaxLetters(3)
        controls.customW:Hide()
        
        controls.customSep = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.customSep:SetPoint("LEFT", controls.customW, "RIGHT", 4, 0)
        controls.customSep:SetText("H:")
        controls.customSep:SetTextColor(0.7, 0.7, 0.7)
        controls.customSep:Hide()
        
        controls.customH = CreateFrame("EditBox", nil, controlsPanel, "InputBoxTemplate")
        controls.customH:SetPoint("LEFT", controls.customSep, "RIGHT", 2, 0)
        controls.customH:SetSize(30, 18)
        controls.customH:SetAutoFocus(false)
        controls.customH:SetNumeric(true)
        controls.customH:SetMaxLetters(3)
        controls.customH:Hide()
        
        -- =====================================================
        -- Dock Assignment
        -- =====================================================
        controls.dockHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.dockHeader:SetPoint("TOPLEFT", 10, -265)
        controls.dockHeader:SetText("Dock Assignment")
        controls.dockHeader:SetTextColor(1, 0.82, 0)
        controls.dockHeader:Hide()
        
        controls.dockLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.dockLabel:SetPoint("TOPLEFT", 10, -285)
        controls.dockLabel:SetText("Assign to Dock:")
        controls.dockLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.dockLabel:Hide()
        
        controls.dockDropdown = CreateFrame("Frame", nil, controlsPanel, "UIDropDownMenuTemplate")
        controls.dockDropdown:SetPoint("TOPLEFT", 80, -278)
        UIDropDownMenu_SetWidth(controls.dockDropdown, 120)
        controls.dockDropdown:Hide()
        
        -- =====================================================
        -- Custom Label Controls (Accessibility feature)
        -- =====================================================
        controls.labelHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.labelHeader:SetPoint("TOPLEFT", 10, -345)
        controls.labelHeader:SetText("Custom Label (Accessibility)")
        controls.labelHeader:SetTextColor(1, 0.82, 0)
        controls.labelHeader:Hide()
        
        controls.labelEnableCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.labelEnableCheck:SetPoint("TOPLEFT", 10, -365)
        controls.labelEnableCheck:SetSize(24, 24)
        controls.labelEnableCheck:Hide()
        
        controls.labelEnableLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelEnableLabel:SetPoint("LEFT", controls.labelEnableCheck, "RIGHT", 2, 0)
        controls.labelEnableLabel:SetText("Show Custom Label")
        controls.labelEnableLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.labelEnableLabel:Hide()
        
        controls.labelTextLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelTextLabel:SetPoint("TOPLEFT", 10, -395)
        controls.labelTextLabel:SetText("Text:")
        controls.labelTextLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelTextLabel:Hide()
        
        controls.labelTextBox = CreateFrame("EditBox", nil, controlsPanel, "InputBoxTemplate")
        controls.labelTextBox:SetPoint("LEFT", controls.labelTextLabel, "RIGHT", 8, 0)
        controls.labelTextBox:SetSize(120, 18)
        controls.labelTextBox:SetAutoFocus(false)
        controls.labelTextBox:SetMaxLetters(20)
        controls.labelTextBox:Hide()
        
        controls.labelSizeLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelSizeLabel:SetPoint("TOPLEFT", 10, -420)
        controls.labelSizeLabel:SetText("Font Size:")
        controls.labelSizeLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelSizeLabel:Hide()
        
        controls.labelSizeSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.labelSizeSlider:SetPoint("LEFT", controls.labelSizeLabel, "RIGHT", 5, 0)
        controls.labelSizeSlider:SetSize(80, 16)
        controls.labelSizeSlider:SetMinMaxValues(8, 32)
        controls.labelSizeSlider:SetValueStep(1)
        controls.labelSizeSlider:SetObeyStepOnDrag(true)
        controls.labelSizeSlider.Low:SetText("")
        controls.labelSizeSlider.High:SetText("")
        controls.labelSizeSlider.Text:SetText("")
        controls.labelSizeSlider:Hide()
        
        controls.labelSizeValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelSizeValue:SetPoint("LEFT", controls.labelSizeSlider, "RIGHT", 8, 0)
        controls.labelSizeValue:SetTextColor(1, 1, 1)
        controls.labelSizeValue:Hide()
        
        controls.labelColorLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelColorLabel:SetPoint("TOPLEFT", 10, -445)
        controls.labelColorLabel:SetText("Color:")
        controls.labelColorLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelColorLabel:Hide()
        
        controls.labelColorBtn = CreateFrame("Button", nil, controlsPanel, "BackdropTemplate")
        controls.labelColorBtn:SetPoint("LEFT", controls.labelColorLabel, "RIGHT", 8, 0)
        controls.labelColorBtn:SetSize(20, 20)
        controls.labelColorBtn:SetBackdrop({ 
            bgFile = "Interface\\BUTTONS\\WHITE8X8", 
            edgeFile = "Interface\\BUTTONS\\WHITE8X8", 
            edgeSize = 1 
        })
        controls.labelColorBtn:SetBackdropColor(1, 1, 1, 1)
        controls.labelColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        controls.labelColorBtn:Hide()
        
        controls.labelOffsetLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetLabel:SetPoint("TOPLEFT", 10, -470)
        controls.labelOffsetLabel:SetText("Offset X:")
        controls.labelOffsetLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelOffsetLabel:Hide()
        
        controls.labelOffsetXSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.labelOffsetXSlider:SetPoint("LEFT", controls.labelOffsetLabel, "RIGHT", 5, 0)
        controls.labelOffsetXSlider:SetSize(100, 16)
        controls.labelOffsetXSlider:SetMinMaxValues(-100, 100)
        controls.labelOffsetXSlider:SetValueStep(1)
        controls.labelOffsetXSlider:SetObeyStepOnDrag(true)
        controls.labelOffsetXSlider.Low:SetText("")
        controls.labelOffsetXSlider.High:SetText("")
        controls.labelOffsetXSlider.Text:SetText("")
        controls.labelOffsetXSlider:Hide()
        
        controls.labelOffsetXValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetXValue:SetPoint("LEFT", controls.labelOffsetXSlider, "RIGHT", 5, 0)
        controls.labelOffsetXValue:SetTextColor(1, 1, 1)
        controls.labelOffsetXValue:Hide()
        
        controls.labelOffsetYLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetYLabel:SetPoint("TOPLEFT", 10, -495)
        controls.labelOffsetYLabel:SetText("Offset Y:")
        controls.labelOffsetYLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelOffsetYLabel:Hide()
        
        controls.labelOffsetYSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.labelOffsetYSlider:SetPoint("LEFT", controls.labelOffsetYLabel, "RIGHT", 5, 0)
        controls.labelOffsetYSlider:SetSize(100, 16)
        controls.labelOffsetYSlider:SetMinMaxValues(-100, 100)
        controls.labelOffsetYSlider:SetValueStep(1)
        controls.labelOffsetYSlider:SetObeyStepOnDrag(true)
        controls.labelOffsetYSlider.Low:SetText("")
        controls.labelOffsetYSlider.High:SetText("")
        controls.labelOffsetYSlider.Text:SetText("")
        controls.labelOffsetYSlider:Hide()
        
        controls.labelOffsetYValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetYValue:SetPoint("LEFT", controls.labelOffsetYSlider, "RIGHT", 5, 0)
        controls.labelOffsetYValue:SetTextColor(1, 1, 1)
        controls.labelOffsetYValue:Hide()
        
        -- =====================================================
        -- Per-Icon Text Controls (Cooldown Timer)
        -- =====================================================
        controls.cooldownTextHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.cooldownTextHeader:SetPoint("TOPLEFT", 200, -345)
        controls.cooldownTextHeader:SetText("Cooldown Text")
        controls.cooldownTextHeader:SetTextColor(1, 0.82, 0)
        controls.cooldownTextHeader:Hide()
        
        controls.cooldownTextScaleLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextScaleLabel:SetPoint("TOPLEFT", 200, -365)
        controls.cooldownTextScaleLabel:SetText("Scale:")
        controls.cooldownTextScaleLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextScaleLabel:Hide()
        
        controls.cooldownTextSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.cooldownTextSlider:SetPoint("LEFT", controls.cooldownTextScaleLabel, "RIGHT", 10, 0)
        controls.cooldownTextSlider:SetSize(70, 16)
        controls.cooldownTextSlider:SetMinMaxValues(0.5, 2.0)
        controls.cooldownTextSlider:SetValueStep(0.1)
        controls.cooldownTextSlider:SetObeyStepOnDrag(true)
        controls.cooldownTextSlider.Low:SetText("")
        controls.cooldownTextSlider.High:SetText("")
        controls.cooldownTextSlider.Text:SetText("")
        controls.cooldownTextSlider:Hide()
        
        controls.cooldownTextValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextValue:SetPoint("LEFT", controls.cooldownTextSlider, "RIGHT", 5, 0)
        controls.cooldownTextValue:SetTextColor(1, 1, 1)
        controls.cooldownTextValue:Hide()
        
        controls.cooldownTextColorLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextColorLabel:SetPoint("TOPLEFT", 200, -390)
        controls.cooldownTextColorLabel:SetText("Color:")
        controls.cooldownTextColorLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextColorLabel:Hide()
        
        controls.cooldownTextColorBtn = CreateFrame("Button", nil, controlsPanel, "BackdropTemplate")
        controls.cooldownTextColorBtn:SetPoint("LEFT", controls.cooldownTextColorLabel, "RIGHT", 10, 0)
        controls.cooldownTextColorBtn:SetSize(24, 16)
        controls.cooldownTextColorBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
        controls.cooldownTextColorBtn:SetBackdropColor(1, 1, 1, 1)
        controls.cooldownTextColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        controls.cooldownTextColorBtn:Hide()
        
        controls.cooldownTextOffsetXLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetXLabel:SetPoint("TOPLEFT", 200, -415)
        controls.cooldownTextOffsetXLabel:SetText("Offset X:")
        controls.cooldownTextOffsetXLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextOffsetXLabel:Hide()
        
        controls.cooldownTextOffsetXSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.cooldownTextOffsetXSlider:SetPoint("LEFT", controls.cooldownTextOffsetXLabel, "RIGHT", 5, 0)
        controls.cooldownTextOffsetXSlider:SetSize(100, 16)
        controls.cooldownTextOffsetXSlider:SetMinMaxValues(-100, 100)
        controls.cooldownTextOffsetXSlider:SetValueStep(1)
        controls.cooldownTextOffsetXSlider:SetObeyStepOnDrag(true)
        controls.cooldownTextOffsetXSlider.Low:SetText("")
        controls.cooldownTextOffsetXSlider.High:SetText("")
        controls.cooldownTextOffsetXSlider.Text:SetText("")
        controls.cooldownTextOffsetXSlider:Hide()
        
        controls.cooldownTextOffsetXValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetXValue:SetPoint("LEFT", controls.cooldownTextOffsetXSlider, "RIGHT", 5, 0)
        controls.cooldownTextOffsetXValue:SetTextColor(1, 1, 1)
        controls.cooldownTextOffsetXValue:Hide()
        
        controls.cooldownTextOffsetYLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetYLabel:SetPoint("TOPLEFT", 200, -440)
        controls.cooldownTextOffsetYLabel:SetText("Offset Y:")
        controls.cooldownTextOffsetYLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextOffsetYLabel:Hide()
        
        controls.cooldownTextOffsetYSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.cooldownTextOffsetYSlider:SetPoint("LEFT", controls.cooldownTextOffsetYLabel, "RIGHT", 5, 0)
        controls.cooldownTextOffsetYSlider:SetSize(100, 16)
        controls.cooldownTextOffsetYSlider:SetMinMaxValues(-100, 100)
        controls.cooldownTextOffsetYSlider:SetValueStep(1)
        controls.cooldownTextOffsetYSlider:SetObeyStepOnDrag(true)
        controls.cooldownTextOffsetYSlider.Low:SetText("")
        controls.cooldownTextOffsetYSlider.High:SetText("")
        controls.cooldownTextOffsetYSlider.Text:SetText("")
        controls.cooldownTextOffsetYSlider:Hide()
        
        controls.cooldownTextOffsetYValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetYValue:SetPoint("LEFT", controls.cooldownTextOffsetYSlider, "RIGHT", 5, 0)
        controls.cooldownTextOffsetYValue:SetTextColor(1, 1, 1)
        controls.cooldownTextOffsetYValue:Hide()
        
        -- =====================================================
        -- Per-Icon Text Controls (Count/Charge Text)
        -- =====================================================
        controls.countTextHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.countTextHeader:SetPoint("TOPLEFT", 200, -470)
        controls.countTextHeader:SetText("Count/Charge Text")
        controls.countTextHeader:SetTextColor(1, 0.82, 0)
        controls.countTextHeader:Hide()
        
        controls.countTextScaleLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextScaleLabel:SetPoint("TOPLEFT", 200, -490)
        controls.countTextScaleLabel:SetText("Scale:")
        controls.countTextScaleLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextScaleLabel:Hide()
        
        controls.countTextSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.countTextSlider:SetPoint("LEFT", controls.countTextScaleLabel, "RIGHT", 10, 0)
        controls.countTextSlider:SetSize(70, 16)
        controls.countTextSlider:SetMinMaxValues(0.5, 2.0)
        controls.countTextSlider:SetValueStep(0.1)
        controls.countTextSlider:SetObeyStepOnDrag(true)
        controls.countTextSlider.Low:SetText("")
        controls.countTextSlider.High:SetText("")
        controls.countTextSlider.Text:SetText("")
        controls.countTextSlider:Hide()
        
        controls.countTextValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextValue:SetPoint("LEFT", controls.countTextSlider, "RIGHT", 5, 0)
        controls.countTextValue:SetTextColor(1, 1, 1)
        controls.countTextValue:Hide()
        
        controls.countTextColorLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextColorLabel:SetPoint("TOPLEFT", 200, -515)
        controls.countTextColorLabel:SetText("Color:")
        controls.countTextColorLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextColorLabel:Hide()
        
        controls.countTextColorBtn = CreateFrame("Button", nil, controlsPanel, "BackdropTemplate")
        controls.countTextColorBtn:SetPoint("LEFT", controls.countTextColorLabel, "RIGHT", 10, 0)
        controls.countTextColorBtn:SetSize(24, 16)
        controls.countTextColorBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
        controls.countTextColorBtn:SetBackdropColor(1, 1, 1, 1)
        controls.countTextColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        controls.countTextColorBtn:Hide()
        
        controls.countTextOffsetXLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetXLabel:SetPoint("TOPLEFT", 200, -540)
        controls.countTextOffsetXLabel:SetText("Offset X:")
        controls.countTextOffsetXLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextOffsetXLabel:Hide()
        
        controls.countTextOffsetXSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.countTextOffsetXSlider:SetPoint("LEFT", controls.countTextOffsetXLabel, "RIGHT", 5, 0)
        controls.countTextOffsetXSlider:SetSize(100, 16)
        controls.countTextOffsetXSlider:SetMinMaxValues(-100, 100)
        controls.countTextOffsetXSlider:SetValueStep(1)
        controls.countTextOffsetXSlider:SetObeyStepOnDrag(true)
        controls.countTextOffsetXSlider.Low:SetText("")
        controls.countTextOffsetXSlider.High:SetText("")
        controls.countTextOffsetXSlider.Text:SetText("")
        controls.countTextOffsetXSlider:Hide()
        
        controls.countTextOffsetXValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetXValue:SetPoint("LEFT", controls.countTextOffsetXSlider, "RIGHT", 5, 0)
        controls.countTextOffsetXValue:SetTextColor(1, 1, 1)
        controls.countTextOffsetXValue:Hide()
        
        controls.countTextOffsetYLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetYLabel:SetPoint("TOPLEFT", 200, -565)
        controls.countTextOffsetYLabel:SetText("Offset Y:")
        controls.countTextOffsetYLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextOffsetYLabel:Hide()
        
        controls.countTextOffsetYSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.countTextOffsetYSlider:SetPoint("LEFT", controls.countTextOffsetYLabel, "RIGHT", 5, 0)
        controls.countTextOffsetYSlider:SetSize(100, 16)
        controls.countTextOffsetYSlider:SetMinMaxValues(-100, 100)
        controls.countTextOffsetYSlider:SetValueStep(1)
        controls.countTextOffsetYSlider:SetObeyStepOnDrag(true)
        controls.countTextOffsetYSlider.Low:SetText("")
        controls.countTextOffsetYSlider.High:SetText("")
        controls.countTextOffsetYSlider.Text:SetText("")
        controls.countTextOffsetYSlider:Hide()
        
        controls.countTextOffsetYValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetYValue:SetPoint("LEFT", controls.countTextOffsetYSlider, "RIGHT", 5, 0)
        controls.countTextOffsetYValue:SetTextColor(1, 1, 1)
        controls.countTextOffsetYValue:Hide()
        
        -- Helper to show/hide all controls
        local function ShowControls(show)
            noSelectionLabel:SetShown(not show)
            for _, ctrl in pairs(controls) do
                if ctrl.SetShown then ctrl:SetShown(show)
                elseif ctrl.Show then
                    if show then ctrl:Show() else ctrl:Hide() end
                end
            end
        end
        
        -- Helper to update state button appearance
        local function UpdateStateButtons()
            if currentState == "active" then
                controls.activeBtn:SetNormalFontObject("GameFontHighlight")
                controls.inactiveBtn:SetNormalFontObject("GameFontNormal")
                controls.showLabel:SetText("Show when ability is Ready")
            else
                controls.activeBtn:SetNormalFontObject("GameFontNormal")
                controls.inactiveBtn:SetNormalFontObject("GameFontHighlight")
                controls.showLabel:SetText("Show when ability is On Cooldown")
            end
        end
        
        -- Helper to update custom aspect visibility
        local function UpdateCustomAspectVisibility(aspectRatio)
            local showCustom = (aspectRatio == "custom")
            controls.customLabel:SetShown(showCustom)
            controls.customW:SetShown(showCustom)
            controls.customSep:SetShown(showCustom)
            controls.customH:SetShown(showCustom)
        end
        
        -- Update controls for selected slot
        local function UpdateControlsForSlot(slotIndex)
            if not slotIndex or not CooldownHighlights then
                ShowControls(false)
                return
            end
            
            ShowControls(true)
            UpdateStateButtons()
            
            -- Get slot info for icon preview - use same order as list (GetOrderedIcons)
            local viewer = _G[viewerName]
            if viewer then
                local icons = GetOrderedIcons(viewer, trackerKey)
                local icon = icons[slotIndex]
                if icon then
                    local textureObj = icon.Icon or icon.icon
                    if textureObj then
                        pcall(function()
                            controls.iconPreview:SetTexture(textureObj:GetTexture())
                        end)
                    end
                end
            end
            
            controls.header:SetText("Slot #" .. slotIndex)
            
            -- Get settings for current state
            local isEnabled = CooldownHighlights:IsEnabled(trackerKey, slotIndex)
            local showState = CooldownHighlights:GetShowState(trackerKey, slotIndex, currentState)
            local size = CooldownHighlights:GetSize(trackerKey, slotIndex, currentState)
            local opacity = CooldownHighlights:GetOpacity(trackerKey, slotIndex, currentState)
            local saturated = CooldownHighlights:GetSaturation(trackerKey, slotIndex, currentState)
            local aspectRatio = CooldownHighlights:GetAspectRatio(trackerKey, slotIndex, currentState)
            local customW, customH = CooldownHighlights:GetCustomAspectRatio(trackerKey, slotIndex, currentState)
            
            -- Clear slider scripts BEFORE setting values to prevent old callbacks from firing
            controls.sizeSlider:SetScript("OnValueChanged", nil)
            controls.opacitySlider:SetScript("OnValueChanged", nil)
            controls.labelSizeSlider:SetScript("OnValueChanged", nil)
            controls.labelOffsetXSlider:SetScript("OnValueChanged", nil)
            controls.labelOffsetYSlider:SetScript("OnValueChanged", nil)
            controls.cooldownTextSlider:SetScript("OnValueChanged", nil)
            controls.cooldownTextOffsetXSlider:SetScript("OnValueChanged", nil)
            controls.cooldownTextOffsetYSlider:SetScript("OnValueChanged", nil)
            controls.countTextSlider:SetScript("OnValueChanged", nil)
            controls.countTextOffsetXSlider:SetScript("OnValueChanged", nil)
            controls.countTextOffsetYSlider:SetScript("OnValueChanged", nil)
            
            -- Update control values
            controls.enableCheck:SetChecked(isEnabled)
            controls.hideCheck:SetChecked(CooldownHighlights:IsIconHidden(trackerKey, slotIndex))
            controls.showCheck:SetChecked(showState)
            controls.sizeSlider:SetValue(size)
            controls.sizeValue:SetText(tostring(size))
            controls.opacitySlider:SetValue(opacity)
            controls.opacityValue:SetText(math.floor(opacity * 100) .. "%")
            controls.desatCheck:SetChecked(not saturated)
            local showProcGlow = CooldownHighlights:GetShowProcGlow(trackerKey, slotIndex)
            controls.procGlowCheck:SetChecked(showProcGlow == nil or showProcGlow == true)
            controls.customW:SetText(tostring(customW))
            controls.customH:SetText(tostring(customH))
            
            -- Per-icon text settings (state-independent)
            local cdTextScale = CooldownHighlights:GetCooldownTextScale(trackerKey, slotIndex)
            local cdTextColor = CooldownHighlights:GetCooldownTextColor(trackerKey, slotIndex)
            local cdTextOffsetX = CooldownHighlights:GetCooldownTextOffsetX(trackerKey, slotIndex)
            local cdTextOffsetY = CooldownHighlights:GetCooldownTextOffsetY(trackerKey, slotIndex)
            
            controls.cooldownTextSlider:SetValue(cdTextScale or 1.0)
            controls.cooldownTextValue:SetText(string.format("%.1f", cdTextScale or 1.0))
            controls.cooldownTextColorBtn:SetBackdropColor(cdTextColor[1] or 1, cdTextColor[2] or 1, cdTextColor[3] or 1, 1)
            controls.cooldownTextOffsetXSlider:SetValue(cdTextOffsetX or 0)
            controls.cooldownTextOffsetXValue:SetText(tostring(cdTextOffsetX or 0))
            controls.cooldownTextOffsetYSlider:SetValue(cdTextOffsetY or 0)
            controls.cooldownTextOffsetYValue:SetText(tostring(cdTextOffsetY or 0))
            
            local cntTextScale = CooldownHighlights:GetCountTextScale(trackerKey, slotIndex)
            local cntTextColor = CooldownHighlights:GetCountTextColor(trackerKey, slotIndex)
            local cntTextOffsetX = CooldownHighlights:GetCountTextOffsetX(trackerKey, slotIndex)
            local cntTextOffsetY = CooldownHighlights:GetCountTextOffsetY(trackerKey, slotIndex)
            
            controls.countTextSlider:SetValue(cntTextScale or 1.0)
            controls.countTextValue:SetText(string.format("%.1f", cntTextScale or 1.0))
            controls.countTextColorBtn:SetBackdropColor(cntTextColor[1] or 1, cntTextColor[2] or 1, cntTextColor[3] or 1, 1)
            controls.countTextOffsetXSlider:SetValue(cntTextOffsetX or 0)
            controls.countTextOffsetXValue:SetText(tostring(cntTextOffsetX or 0))
            controls.countTextOffsetYSlider:SetValue(cntTextOffsetY or 0)
            controls.countTextOffsetYValue:SetText(tostring(cntTextOffsetY or 0))
            
            -- Label settings (state-independent)
            local labelEnabled = CooldownHighlights:GetLabelEnabled(trackerKey, slotIndex)
            local labelText = CooldownHighlights:GetLabelText(trackerKey, slotIndex)
            local labelSize = CooldownHighlights:GetLabelFontSize(trackerKey, slotIndex)
            local labelColor = CooldownHighlights:GetLabelColor(trackerKey, slotIndex)
            local labelOffsetX = CooldownHighlights:GetLabelOffsetX(trackerKey, slotIndex)
            local labelOffsetY = CooldownHighlights:GetLabelOffsetY(trackerKey, slotIndex)
            
            controls.labelEnableCheck:SetChecked(labelEnabled)
            controls.labelTextBox:SetText(labelText or "")
            controls.labelSizeSlider:SetValue(labelSize or 14)
            controls.labelSizeValue:SetText(tostring(labelSize or 14))
            controls.labelColorBtn:SetBackdropColor(labelColor[1] or 1, labelColor[2] or 1, labelColor[3] or 1, labelColor[4] or 1)
            controls.labelOffsetXSlider:SetValue(labelOffsetX or 0)
            controls.labelOffsetXValue:SetText(tostring(labelOffsetX or 0))
            controls.labelOffsetYSlider:SetValue(labelOffsetY or 0)
            controls.labelOffsetYValue:SetText(tostring(labelOffsetY or 0))
            
            -- Initialize aspect dropdown
            UIDropDownMenu_Initialize(controls.aspectDropdown, function(self, level)
                for _, opt in ipairs(ASPECT_OPTIONS) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = opt.label
                    info.value = opt.value
                    info.func = function(self)
                        CooldownHighlights:SetAspectRatio(trackerKey, slotIndex, currentState, self.value)
                        UIDropDownMenu_SetText(controls.aspectDropdown, self:GetText())
                        UpdateCustomAspectVisibility(self.value)
                    end
                    info.checked = (aspectRatio == opt.value)
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            
            -- Set dropdown text
            for _, opt in ipairs(ASPECT_OPTIONS) do
                if opt.value == aspectRatio then
                    UIDropDownMenu_SetText(controls.aspectDropdown, opt.label)
                    break
                end
            end
            
            UpdateCustomAspectVisibility(aspectRatio)
            
            -- Initialize dock dropdown
            local currentDock = CooldownHighlights:GetDockAssignment(trackerKey, slotIndex) or 0
            UIDropDownMenu_Initialize(controls.dockDropdown, function(self, level)
                -- None option
                local info = UIDropDownMenu_CreateInfo()
                info.text = "None"
                info.value = 0
                info.func = function()
                    CooldownHighlights:SetDockAssignment(trackerKey, slotIndex, nil)
                    UIDropDownMenu_SetText(controls.dockDropdown, "None")
                end
                info.checked = (currentDock == 0 or currentDock == nil)
                UIDropDownMenu_AddButton(info, level)
                
                -- Dock options (1-4)
                local numDocks = TUICD.Docks and TUICD.Docks:GetDockCount() or 4
                for i = 1, numDocks do
                    local dockName = TUICD.Docks and TUICD.Docks:GetDockName(i) or ("Dock " .. i)
                    local dockSettings = TUICD.Docks and TUICD.Docks:GetDockSettings(i) or {}
                    
                    info = UIDropDownMenu_CreateInfo()
                    if dockSettings.enabled then
                        info.text = "|cff00ff00" .. dockName .. "|r"
                    else
                        info.text = "|cff888888" .. dockName .. " (disabled)|r"
                    end
                    info.value = i
                    info.func = function()
                        CooldownHighlights:SetDockAssignment(trackerKey, slotIndex, i)
                        UIDropDownMenu_SetText(controls.dockDropdown, dockName)
                    end
                    info.checked = (currentDock == i)
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            
            -- Set dock dropdown text
            if currentDock and currentDock > 0 then
                local dockName = TUICD.Docks and TUICD.Docks:GetDockName(currentDock) or ("Dock " .. currentDock)
                UIDropDownMenu_SetText(controls.dockDropdown, dockName)
            else
                UIDropDownMenu_SetText(controls.dockDropdown, "None")
            end
            
            -- Wire up control callbacks
            controls.enableCheck:SetScript("OnClick", function(self)
                CooldownHighlights:EnableHighlight(trackerKey, slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.activeBtn:SetScript("OnClick", function()
                currentState = "active"
                UpdateControlsForSlot(slotIndex)
            end)
            
            controls.inactiveBtn:SetScript("OnClick", function()
                currentState = "inactive"
                UpdateControlsForSlot(slotIndex)
            end)
            
            controls.showCheck:SetScript("OnClick", function(self)
                CooldownHighlights:SetShowState(trackerKey, slotIndex, currentState, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.sizeSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.sizeValue:SetText(tostring(value))
                CooldownHighlights:SetSize(trackerKey, slotIndex, currentState, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.opacitySlider:SetScript("OnValueChanged", function(self, value)
                controls.opacityValue:SetText(math.floor(value * 100) .. "%")
                CooldownHighlights:SetOpacity(trackerKey, slotIndex, currentState, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.desatCheck:SetScript("OnClick", function(self)
                CooldownHighlights:SetSaturation(trackerKey, slotIndex, currentState, not self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.procGlowCheck:SetScript("OnClick", function(self)
                CooldownHighlights:SetShowProcGlow(trackerKey, slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            local function ApplyCustomAspect()
                local w = tonumber(controls.customW:GetText()) or 1
                local h = tonumber(controls.customH:GetText()) or 1
                if w < 1 then w = 1 end
                if h < 1 then h = 1 end
                CooldownHighlights:SetCustomAspectRatio(trackerKey, slotIndex, currentState, w, h)
            end
            
            controls.customW:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                ApplyCustomAspect()
            end)
            controls.customW:SetScript("OnEditFocusLost", ApplyCustomAspect)
            
            controls.customH:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                ApplyCustomAspect()
            end)
            controls.customH:SetScript("OnEditFocusLost", ApplyCustomAspect)
            
            -- Label control event handlers
            controls.labelEnableCheck:SetScript("OnClick", function(self)
                CooldownHighlights:SetLabelEnabled(trackerKey, slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.labelTextBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                CooldownHighlights:SetLabelText(trackerKey, slotIndex, self:GetText())
                Cooldowns:SaveSettings()
            end)
            controls.labelTextBox:SetScript("OnEditFocusLost", function(self)
                CooldownHighlights:SetLabelText(trackerKey, slotIndex, self:GetText())
                Cooldowns:SaveSettings()
            end)
            
            controls.labelSizeSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.labelSizeValue:SetText(tostring(value))
                CooldownHighlights:SetLabelFontSize(trackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.labelColorBtn:SetScript("OnClick", function()
                local currentColor = CooldownHighlights:GetLabelColor(trackerKey, slotIndex)
                local r, g, b, a = currentColor[1] or 1, currentColor[2] or 1, currentColor[3] or 1, currentColor[4] or 1
                
                local info = {
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        local na = ColorPickerFrame:GetColorAlpha() or 1
                        controls.labelColorBtn:SetBackdropColor(nr, ng, nb, na)
                        CooldownHighlights:SetLabelColor(trackerKey, slotIndex, {nr, ng, nb, na})
                        Cooldowns:SaveSettings()
                    end,
                    opacityFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        local na = ColorPickerFrame:GetColorAlpha() or 1
                        controls.labelColorBtn:SetBackdropColor(nr, ng, nb, na)
                        CooldownHighlights:SetLabelColor(trackerKey, slotIndex, {nr, ng, nb, na})
                        Cooldowns:SaveSettings()
                    end,
                    cancelFunc = function(prev)
                        controls.labelColorBtn:SetBackdropColor(prev.r, prev.g, prev.b, prev.a or 1)
                        CooldownHighlights:SetLabelColor(trackerKey, slotIndex, {prev.r, prev.g, prev.b, prev.a or 1})
                        Cooldowns:SaveSettings()
                    end,
                    hasOpacity = true,
                    opacity = a,
                    r = r,
                    g = g,
                    b = b,
                }
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            
            controls.labelOffsetXSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.labelOffsetXValue:SetText(tostring(value))
                CooldownHighlights:SetLabelOffsetX(trackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.labelOffsetYSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.labelOffsetYValue:SetText(tostring(value))
                CooldownHighlights:SetLabelOffsetY(trackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            -- Hide icon checkbox handler
            controls.hideCheck:SetScript("OnClick", function(self)
                CooldownHighlights:SetIconHidden(trackerKey, slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
                -- Refresh the tracker layout
                Cooldowns.RefreshTrackerLayout(trackerKey)
            end)
            
            -- Cooldown text control handlers
            controls.cooldownTextSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value * 10) / 10  -- Round to 1 decimal
                controls.cooldownTextValue:SetText(string.format("%.1f", value))
                CooldownHighlights:SetCooldownTextScale(trackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.cooldownTextColorBtn:SetScript("OnClick", function()
                local currentColor = CooldownHighlights:GetCooldownTextColor(trackerKey, slotIndex)
                local r, g, b = currentColor[1] or 1, currentColor[2] or 1, currentColor[3] or 1
                
                local info = {
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        controls.cooldownTextColorBtn:SetBackdropColor(nr, ng, nb, 1)
                        CooldownHighlights:SetCooldownTextColor(trackerKey, slotIndex, {nr, ng, nb})
                        Cooldowns:SaveSettings()
                    end,
                    cancelFunc = function(prev)
                        controls.cooldownTextColorBtn:SetBackdropColor(prev.r, prev.g, prev.b, 1)
                        CooldownHighlights:SetCooldownTextColor(trackerKey, slotIndex, {prev.r, prev.g, prev.b})
                        Cooldowns:SaveSettings()
                    end,
                    hasOpacity = false,
                    r = r,
                    g = g,
                    b = b,
                }
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            
            controls.cooldownTextOffsetXSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.cooldownTextOffsetXValue:SetText(tostring(value))
                CooldownHighlights:SetCooldownTextOffsetX(trackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.cooldownTextOffsetYSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.cooldownTextOffsetYValue:SetText(tostring(value))
                CooldownHighlights:SetCooldownTextOffsetY(trackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            -- Count text control handlers
            controls.countTextSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value * 10) / 10  -- Round to 1 decimal
                controls.countTextValue:SetText(string.format("%.1f", value))
                CooldownHighlights:SetCountTextScale(trackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.countTextColorBtn:SetScript("OnClick", function()
                local currentColor = CooldownHighlights:GetCountTextColor(trackerKey, slotIndex)
                local r, g, b = currentColor[1] or 1, currentColor[2] or 1, currentColor[3] or 1
                
                local info = {
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        controls.countTextColorBtn:SetBackdropColor(nr, ng, nb, 1)
                        CooldownHighlights:SetCountTextColor(trackerKey, slotIndex, {nr, ng, nb})
                        Cooldowns:SaveSettings()
                    end,
                    cancelFunc = function(prev)
                        controls.countTextColorBtn:SetBackdropColor(prev.r, prev.g, prev.b, 1)
                        CooldownHighlights:SetCountTextColor(trackerKey, slotIndex, {prev.r, prev.g, prev.b})
                        Cooldowns:SaveSettings()
                    end,
                    hasOpacity = false,
                    r = r,
                    g = g,
                    b = b,
                }
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            
            controls.countTextOffsetXSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.countTextOffsetXValue:SetText(tostring(value))
                CooldownHighlights:SetCountTextOffsetX(trackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.countTextOffsetYSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.countTextOffsetYValue:SetText(tostring(value))
                CooldownHighlights:SetCountTextOffsetY(trackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
        end
        
        -- Refresh slot list
        local function RefreshSlotList()
            for _, row in ipairs(slotRows) do
                row:Hide()
                row:SetParent(nil)
            end
            wipe(slotRows)
            
            local viewer = _G[viewerName]
            if not viewer then
                local noItems = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noItems:SetPoint("CENTER")
                noItems:SetText(trackerDisplayName .. " not loaded")
                noItems:SetTextColor(0.5, 0.5, 0.5)
                slotRows[1] = noItems
                scrollChild:SetHeight(90)
                ShowControls(false)
                return
            end
            
            -- Use same order as layout (GetOrderedIcons)
            local icons = GetOrderedIcons(viewer, trackerKey)
            if #icons == 0 then
                local noItems = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noItems:SetPoint("CENTER")
                noItems:SetText("No cooldowns tracked")
                noItems:SetTextColor(0.5, 0.5, 0.5)
                slotRows[1] = noItems
                scrollChild:SetHeight(90)
                ShowControls(false)
                return
            end
            
            local rowY = -3
            local rowHeight = 21
            
            for slotIndex = 1, #icons do
                local icon = icons[slotIndex]
                if icon then
                    local row = CreateFrame("Button", nil, scrollChild)
                    row:SetPoint("TOPLEFT", 3, rowY)
                    row:SetPoint("TOPRIGHT", -3, rowY)
                    row:SetHeight(rowHeight - 2)
                    
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
                    
                    local slotLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    slotLabel:SetPoint("LEFT", 4, 0)
                    slotLabel:SetText("#" .. slotIndex)
                    slotLabel:SetTextColor(0.8, 0.8, 0.8)
                    
                    local iconPreview = row:CreateTexture(nil, "ARTWORK")
                    iconPreview:SetPoint("LEFT", 22, 0)
                    iconPreview:SetSize(18, 18)
                    iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local textureObj = icon.Icon or icon.icon
                    if textureObj then
                        pcall(function() iconPreview:SetTexture(textureObj:GetTexture()) end)
                    end
                    
                    local isEnabled = CooldownHighlights and CooldownHighlights:IsEnabled(trackerKey, slotIndex)
                    local enabledIndicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    enabledIndicator:SetPoint("LEFT", 45, 0)
                    enabledIndicator:SetText(isEnabled and "|cff00ff00On|r" or "|cff666666Off|r")
                    
                    row.slotIndex = slotIndex
                    row:SetScript("OnClick", function(self)
                        selectedSlot = self.slotIndex
                        for _, r in ipairs(slotRows) do
                            if r.bg then r.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3) end
                        end
                        self.bg:SetColorTexture(0.3, 0.5, 0.3, 0.6)
                        currentState = "active"
                        UpdateControlsForSlot(self.slotIndex)
                    end)
                    
                    row:SetScript("OnEnter", function(self)
                        if selectedSlot ~= self.slotIndex then
                            self.bg:SetColorTexture(0.25, 0.25, 0.3, 0.5)
                        end
                    end)
                    
                    row:SetScript("OnLeave", function(self)
                        if selectedSlot ~= self.slotIndex then
                            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
                        end
                    end)
                    
                    slotRows[#slotRows + 1] = row
                    rowY = rowY - rowHeight
                end
            end
            
            
            -- Update scroll child height based on content
            local totalHeight = math.max(90, #slotRows * rowHeight + 6)
            scrollChild:SetHeight(totalHeight)
            if not selectedSlot and #slotRows > 0 and slotRows[1].slotIndex then
                slotRows[1]:Click()
            end
        end
        
        C_Timer.After(0.1, RefreshSlotList)
        
        -- Set the refresh button script (button created at top of tab)
        refreshBtn:SetScript("OnClick", function()
            selectedSlot = nil
            RefreshSlotList()
        end)
        
        parent:SetHeight(math.abs(y) + 370)
    end
    
    -- Build tab content builders
    local tabBuilders = {
        layout = BuildLayoutTab,
        appearance = BuildAppearanceTab,
        text = BuildTextTab,
        visibility = BuildVisibilityTab,
        buffdisplay = BuildBuffDisplayTab,
        highlights = BuildHighlightsTab,
        cooldownhighlights = BuildCooldownHighlightsTab,
    }
    
    -- Create content frames and tab buttons
    local tabWidth = (PANEL_WIDTH - 20) / #tabs
    local scrollChildren = {}  -- Store scroll children for refresh
    
    for i, tab in ipairs(tabs) do
        -- Create content frame
        local content = CreateTabContent()
        contentFrames[tab.key] = content
        scrollChildren[tab.key] = content.scrollChild
        
        -- Build content
        if tabBuilders[tab.key] then
            tabBuilders[tab.key](content.scrollChild)
        end
        
        -- Create tab button
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
            -- Hide all content
            for _, cf in pairs(contentFrames) do
                cf:Hide()
            end
            -- Show selected
            contentFrames[tab.key]:Show()
            -- Update button visuals
            for _, btn in ipairs(tabButtons) do
                btn.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                btn.text:SetTextColor(0.7, 0.7, 0.7)
            end
            tabBtn.bg:SetColorTexture(0.3, 0.3, 0.5, 1)
            tabBtn.text:SetTextColor(1, 1, 1)
            currentTab = i
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
    
    -- Show first tab
    contentFrames[tabs[1].key]:Show()
    tabButtons[1].bg:SetColorTexture(0.3, 0.3, 0.5, 1)
    tabButtons[1].text:SetTextColor(1, 1, 1)
    
    panel:Show()
end

-- ============================================================================
-- CUSTOM TRACKERS SETTINGS PANEL
-- ============================================================================

function Cooldowns:CreateCustomTrackersPanel()
    local panel = CreateFrame("Frame", "TweaksUI_Cooldowns_customTrackers_Panel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT + 50)
    panel:SetPoint("TOPLEFT", cooldownHub, "TOPRIGHT", 0, 0)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    
    settingsPanels["customTrackers"] = panel
    local trackerKey = "customTrackers"
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Custom Trackers")
    title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    -- Tab system
    local tabs = {
        { name = "Entries", key = "entries" },
        { name = "Layout", key = "layout" },
        { name = "Appearance", key = "appearance" },
        { name = "Text", key = "text" },
        { name = "Visibility", key = "visibility" },
        { name = "Individual Icons", key = "pericon" },
    }
    
    local tabContainer = CreateFrame("Frame", nil, panel)
    tabContainer:SetPoint("TOPLEFT", 10, -40)
    tabContainer:SetPoint("TOPRIGHT", -10, -40)
    tabContainer:SetHeight(28)
    
    local contentContainer = CreateFrame("Frame", nil, panel)
    contentContainer:SetPoint("TOPLEFT", tabContainer, "BOTTOMLEFT", 0, -4)
    contentContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
    
    local contentFrames = {}
    local tabButtons = {}
    local currentTab = 1
    
    -- Helper to create tab content with scroll
    local function CreateTabContent()
        local content = CreateFrame("ScrollFrame", nil, contentContainer, "UIPanelScrollFrameTemplate")
        content:SetAllPoints()
        content:Hide()
        
        local scrollChild = CreateFrame("Frame", nil, content)
        scrollChild:SetSize(PANEL_WIDTH - 50, 800)
        content:SetScrollChild(scrollChild)
        content.scrollChild = scrollChild
        
        return content
    end
    
    -- Refresh layout function
    local function RefreshLayout()
        LayoutCustomTrackerIcons()
    end
    
    -- ========================================
    -- SHARED HELPER FUNCTIONS
    -- ========================================
    
    local function CreateHeader(parent, yOffset, text)
        yOffset = yOffset - 8
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 5, yOffset)
        header:SetText(text)
        header:SetTextColor(1, 0.82, 0)
        return yOffset - 18
    end
    
    local function CreateCheckbox(parent, yOffset, text, getValue, setValue)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 10, yOffset)
        cb:SetSize(24, 24)
        cb:SetChecked(getValue() or false)
        cb:SetScript("OnClick", function(self)
            setValue(self:GetChecked())
            RefreshLayout()
        end)
        
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(text)
        label:SetTextColor(0.8, 0.8, 0.8)
        
        return yOffset - 26, cb
    end
    
    local function CreateSlider(parent, yOffset, labelText, min, max, step, getValue, setValue)
        local isFloat = step < 1
        local decimals = isFloat and 2 or 0
        
        -- Use centralized slider with input
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
                RefreshLayout()
            end,
        })
        container:SetPoint("TOPLEFT", 10, yOffset)
        
        return yOffset - 30
    end
    
    local function CreateDropdown(parent, yOffset, labelText, options, getValue, setValue)
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
            RefreshLayout()
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
        
        return yOffset - 30
    end
    
    local function CreateEditBox(parent, yOffset, labelText, getValue, setValue, width)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 10, yOffset)
        label:SetText(labelText)
        label:SetTextColor(0.8, 0.8, 0.8)
        
        local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        box:SetPoint("LEFT", label, "RIGHT", 8, 0)
        box:SetSize(width or 60, 20)
        box:SetAutoFocus(false)
        box:SetText(getValue() or "")
        box:SetScript("OnEnterPressed", function(self)
            setValue(self:GetText())
            RefreshLayout()
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        
        return yOffset - 26, box
    end
    
    -- ========================================
    -- TAB 1: ENTRIES (Add/Remove Spells/Items)
    -- ========================================
    local function BuildEntriesTab(parent)
        local y = -10
        
        y = CreateHeader(parent, y, "Master Enable")
        y = CreateCheckbox(parent, y, "Enable Custom Trackers",
            function() return GetSetting(trackerKey, "enabled") end,
            function(v) 
                SetSetting(trackerKey, "enabled", v)
                RebuildCustomTrackerIcons()
            end)
        
        -- ========================================
        -- DRAG & DROP ZONE
        -- ========================================
        y = y - 10
        y = CreateHeader(parent, y, "Add Entry")
        
        -- Create drop zone frame
        local dropZone = CreateFrame("Button", nil, parent, "BackdropTemplate")
        dropZone:SetPoint("TOPLEFT", 10, y)
        dropZone:SetSize(PANEL_WIDTH - 60, 45)
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
        
        -- Drop zone handlers
        local function ProcessPanelDrop()
            local cursorType, id, subType, spellID = GetCursorInfo()
            
            if cursorType == "spell" then
                local actualSpellID = spellID or id
                if actualSpellID then
                    local success, msg = AddCustomEntry("spell", actualSpellID)
                    ClearCursor()
                    if success then
                        RebuildCustomTrackerIcons()
                        if panel.RefreshEntriesList then
                            panel:RefreshEntriesList()
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
                    local success, msg = AddCustomEntry("item", itemID)
                    ClearCursor()
                    if success then
                        RebuildCustomTrackerIcons()
                        if panel.RefreshEntriesList then
                            panel:RefreshEntriesList()
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
        
        dropZone:SetScript("OnReceiveDrag", ProcessPanelDrop)
        dropZone:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and GetCursorInfo() then
                ProcessPanelDrop()
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
        
        -- Manual entry row
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
            
            local success, msg = AddCustomEntry(selectedType, input)
            if success then
                idInput:SetText("")
                RebuildCustomTrackerIcons()
                if panel.RefreshEntriesList then
                    panel:RefreshEntriesList()
                end
            end
        end)
        
        idInput:SetScript("OnEnterPressed", function(self)
            addBtn:Click()
            self:ClearFocus()
        end)
        y = y - 30
        
        -- ========================================
        -- ADD EQUIPPED SLOTS
        -- ========================================
        y = y - 5
        y = CreateHeader(parent, y, "Add Equipped Slot")
        
        local equipHelp = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        equipHelp:SetPoint("TOPLEFT", 10, y)
        equipHelp:SetText("|cff888888Click + to track on-use equipment:|r")
        y = y - 14
        
        local equipContainer = CreateFrame("Frame", nil, parent)
        equipContainer:SetPoint("TOPLEFT", 10, y)
        equipContainer:SetSize(PANEL_WIDTH - 50, 80)
        panel.equipContainer = equipContainer
        
        local equipElements = {}
        
        -- Refresh available equipped items to add
        function panel:RefreshEquipmentList()
            for _, elem in ipairs(equipElements) do
                if elem.Hide then elem:Hide() end
                if elem.SetParent then elem:SetParent(nil) end
            end
            wipe(equipElements)
            
            local eqY = 0
            local currentEquipped = ScanEquippedOnUseItems()
            local entries = GetCurrentSpecEntries()
            
            -- Check which slots are already tracked
            local trackedSlots = {}
            for _, entry in ipairs(entries) do
                if entry.type == "equipped" then
                    trackedSlots[entry.id] = true
                end
            end
            
            local hasAny = false
            for slotID, itemInfo in pairs(currentEquipped) do
                if not trackedSlots[slotID] then
                    hasAny = true
                    local row = CreateFrame("Frame", nil, equipContainer)
                    row:SetPoint("TOPLEFT", 0, eqY)
                    row:SetSize(PANEL_WIDTH - 70, 20)
                    table.insert(equipElements, row)
                    
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetPoint("LEFT", 0, 0)
                    icon:SetSize(18, 18)
                    icon:SetTexture(itemInfo.texture)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    
                    local slotName = itemInfo.slotName or TRACKABLE_EQUIPMENT_SLOTS[slotID] or "Slot " .. slotID
                    local itemName = itemInfo.itemName or "Unknown"
                    
                    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                    label:SetPoint("RIGHT", row, "RIGHT", -40, 0)
                    label:SetJustifyH("LEFT")
                    label:SetText(string.format("|cff888888[%s]|r %s", slotName, itemName))
                    label:SetWordWrap(false)
                    
                    local addSlotBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    addSlotBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                    addSlotBtn:SetSize(30, 18)
                    addSlotBtn:SetText("+")
                    addSlotBtn:SetScript("OnClick", function()
                        AddCustomEntry("equipped", slotID)
                        RebuildCustomTrackerIcons()
                        panel:RefreshEquipmentList()
                        panel:RefreshEntriesList()
                    end)
                    
                    eqY = eqY - 22
                end
            end
            
            if not hasAny then
                local noNew = equipContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noNew:SetPoint("TOPLEFT", 0, 0)
                if CountTableEntries(currentEquipped) == 0 then
                    noNew:SetText("|cff666666No on-use equipment currently equipped|r")
                else
                    noNew:SetText("|cff666666All on-use equipment already tracked|r")
                end
                table.insert(equipElements, noNew)
            end
        end
        
        y = y - 70
        
        -- ========================================
        -- UNIFIED ENTRIES LIST
        -- ========================================
        y = y - 10
        y = CreateHeader(parent, y, "Tracked Entries (This Spec)")
        
        local reorderHelp = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        reorderHelp:SetPoint("TOPLEFT", 10, y)
        reorderHelp:SetText("|cff888888Arrows to reorder, X to remove|r")
        y = y - 14
        
        local entriesContainer = CreateFrame("Frame", nil, parent)
        entriesContainer:SetPoint("TOPLEFT", 10, y)
        entriesContainer:SetSize(PANEL_WIDTH - 50, 250)
        panel.entriesContainer = entriesContainer
        
        local entryElements = {}
        
        -- Refresh unified entries list
        function panel:RefreshEntriesList()
            for _, elem in ipairs(entryElements) do
                if elem.Hide then elem:Hide() end
                if elem.SetParent then elem:SetParent(nil) end
            end
            wipe(entryElements)
            
            local entryY = 0
            local entries = GetCurrentSpecEntries()
            
            for i, entry in ipairs(entries) do
                local displayName, displayTexture, trackID = GetEntryDisplayInfo(entry)
                local isEnabled = entry.enabled ~= false
                
                -- Check if equipped slot has on-use ability
                local hasOnUse = true
                local isEmptySlot = false
                if entry.type == "equipped" then
                    local itemID = GetInventoryItemID("player", entry.id)
                    if itemID then
                        hasOnUse = HasOnUseAbility(itemID)
                    else
                        isEmptySlot = true
                    end
                end
                
                -- Determine if entry will actually display
                local willDisplay = isEnabled and hasOnUse and not isEmptySlot
                
                local row = CreateFrame("Frame", nil, entriesContainer)
                row:SetPoint("TOPLEFT", 0, entryY)
                row:SetSize(PANEL_WIDTH - 50, 24)
                table.insert(entryElements, row)
                
                -- Enable checkbox
                local enableCB = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                enableCB:SetPoint("LEFT", 0, 0)
                enableCB:SetSize(18, 18)
                enableCB:SetChecked(isEnabled)
                enableCB:SetScript("OnClick", function(self)
                    SetCustomEntryEnabled(i, self:GetChecked())
                    Cooldowns:SaveSettings()
                    RebuildCustomTrackerIcons()
                end)
                enableCB:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Enable/Disable")
                    GameTooltip:AddLine("Uncheck to hide without removing", 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                end)
                enableCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
                
                -- Move up button
                local upBtn = CreateFrame("Button", nil, row)
                upBtn:SetPoint("LEFT", enableCB, "RIGHT", 0, 0)
                upBtn:SetSize(14, 14)
                upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
                upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
                upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
                upBtn:SetEnabled(i > 1)
                upBtn:SetScript("OnClick", function()
                    MoveCustomEntry(i, i - 1)
                    RebuildCustomTrackerIcons()
                    panel:RefreshEntriesList()
                end)
                if i == 1 then upBtn:SetAlpha(0.3) end
                
                -- Move down button
                local downBtn = CreateFrame("Button", nil, row)
                downBtn:SetPoint("LEFT", upBtn, "RIGHT", 0, 0)
                downBtn:SetSize(14, 14)
                downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
                downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
                downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
                downBtn:SetEnabled(i < #entries)
                downBtn:SetScript("OnClick", function()
                    MoveCustomEntry(i, i + 1)
                    RebuildCustomTrackerIcons()
                    panel:RefreshEntriesList()
                end)
                if i == #entries then downBtn:SetAlpha(0.3) end
                
                -- Icon
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("LEFT", downBtn, "RIGHT", 3, 0)
                icon:SetSize(18, 18)
                icon:SetTexture(displayTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if not willDisplay then
                    icon:SetDesaturated(true)
                    icon:SetAlpha(0.5)
                end
                
                -- Type indicator and name
                local typeChar
                if entry.type == "spell" then
                    typeChar = "|cff71d5ffS|r"  -- Blue for spell
                elseif entry.type == "item" then
                    typeChar = "|cffa335eeI|r"  -- Purple for item
                elseif entry.type == "equipped" then
                    typeChar = "|cff00ff00E|r"  -- Green for equipped
                end
                
                -- Build label with status indicators
                local labelText = displayName or "Loading..."
                if not isEnabled then
                    labelText = "|cff666666[" .. typeChar .. "] " .. labelText .. "|r"
                elseif isEmptySlot then
                    labelText = "|cff666666[" .. typeChar .. "] " .. labelText .. " |cffff6600(empty)|r|r"
                elseif not hasOnUse then
                    labelText = "|cff666666[" .. typeChar .. "] " .. labelText .. "|r"
                else
                    labelText = "[" .. typeChar .. "] " .. labelText
                end
                
                local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
                label:SetPoint("RIGHT", row, "RIGHT", -22, 0)
                label:SetJustifyH("LEFT")
                label:SetText(labelText)
                label:SetWordWrap(false)
                
                -- Remove button
                local removeBtn = CreateFrame("Button", nil, row)
                removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                removeBtn:SetSize(16, 16)
                removeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
                removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
                removeBtn:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3)
                removeBtn:SetScript("OnClick", function()
                    RemoveCustomEntry(i)
                    RebuildCustomTrackerIcons()
                    panel:RefreshEntriesList()
                    panel:RefreshEquipmentList()
                end)
                removeBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Remove")
                    GameTooltip:Show()
                end)
                removeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                
                entryY = entryY - 26
            end
            
            if #entries == 0 then
                local noEntries = entriesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noEntries:SetPoint("TOPLEFT", 0, 0)
                noEntries:SetText("|cff888888No entries - drop spells/items above to add|r")
                table.insert(entryElements, noEntries)
            end
        end
        
        -- Backwards compat aliases
        panel.RefreshCustomEntriesList = panel.RefreshEntriesList
        panel.RefreshEquippedItemsList = panel.RefreshEquipmentList
        
        parent:SetHeight(math.abs(y) + 300)
    end
    
    -- ========================================
    -- TAB 2: LAYOUT
    -- ========================================
    local function BuildLayoutTab(parent)
        local y = -10
        
        y = CreateHeader(parent, y, "Icon Size")
        y = CreateSlider(parent, y, "Base Size", 16, 80, 1,
            function() return GetSetting(trackerKey, "iconSize") or 36 end,
            function(v) SetSetting(trackerKey, "iconSize", v) end)
        
        y = CreateDropdown(parent, y, "Aspect Ratio", ASPECT_PRESETS,
            function() return GetSetting(trackerKey, "aspectRatio") or "1:1" end,
            function(v) 
                SetSetting(trackerKey, "aspectRatio", v)
                if v ~= "custom" then
                    SetSetting(trackerKey, "iconWidth", nil)
                    SetSetting(trackerKey, "iconHeight", nil)
                end
            end)
        
        -- Custom dimensions
        local customLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        customLabel:SetPoint("TOPLEFT", 10, y)
        customLabel:SetText("Custom: Width")
        customLabel:SetTextColor(0.6, 0.6, 0.6)
        
        local widthBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        widthBox:SetPoint("LEFT", customLabel, "RIGHT", 5, 0)
        widthBox:SetSize(40, 20)
        widthBox:SetAutoFocus(false)
        widthBox:SetNumeric(true)
        widthBox:SetNumber(GetSetting(trackerKey, "iconWidth") or 36)
        widthBox:SetScript("OnEnterPressed", function(self)
            SetSetting(trackerKey, "iconWidth", self:GetNumber())
            SetSetting(trackerKey, "aspectRatio", "custom")
            RefreshLayout()
            self:ClearFocus()
        end)
        
        local heightLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heightLabel:SetPoint("LEFT", widthBox, "RIGHT", 10, 0)
        heightLabel:SetText("Height")
        heightLabel:SetTextColor(0.6, 0.6, 0.6)
        
        local heightBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        heightBox:SetPoint("LEFT", heightLabel, "RIGHT", 5, 0)
        heightBox:SetSize(40, 20)
        heightBox:SetAutoFocus(false)
        heightBox:SetNumeric(true)
        heightBox:SetNumber(GetSetting(trackerKey, "iconHeight") or 36)
        heightBox:SetScript("OnEnterPressed", function(self)
            SetSetting(trackerKey, "iconHeight", self:GetNumber())
            SetSetting(trackerKey, "aspectRatio", "custom")
            RefreshLayout()
            self:ClearFocus()
        end)
        y = y - 28
        
        y = CreateHeader(parent, y, "Grid Layout")
        y = CreateSlider(parent, y, "Columns", 1, 20, 1,
            function() return GetSetting(trackerKey, "columns") or 4 end,
            function(v) SetSetting(trackerKey, "columns", v) end)
        
        y = CreateSlider(parent, y, "Max Rows (0=unlimited)", 0, 10, 1,
            function() return GetSetting(trackerKey, "rows") or 0 end,
            function(v) SetSetting(trackerKey, "rows", v) end)
        
        y = CreateHeader(parent, y, "Spacing")
        
        -- Horizontal spacing
        local hLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hLabel:SetPoint("TOPLEFT", 10, y)
        hLabel:SetText("Horizontal:")
        hLabel:SetTextColor(0.8, 0.8, 0.8)
        
        local hBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        hBox:SetPoint("LEFT", hLabel, "RIGHT", 8, 0)
        hBox:SetSize(60, 20)
        hBox:SetAutoFocus(false)
        hBox:SetText(tostring(GetSetting(trackerKey, "spacingH") or 2))
        hBox:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText()) or 2
            SetSetting(trackerKey, "spacingH", val)
            RefreshLayout()
            self:ClearFocus()
        end)
        hBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        y = y - 26
        
        -- Vertical spacing
        local vLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        vLabel:SetPoint("TOPLEFT", 10, y)
        vLabel:SetText("Vertical:")
        vLabel:SetTextColor(0.8, 0.8, 0.8)
        
        local vBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        vBox:SetPoint("LEFT", vLabel, "RIGHT", 8, 0)
        vBox:SetSize(60, 20)
        vBox:SetAutoFocus(false)
        vBox:SetText(tostring(GetSetting(trackerKey, "spacingV") or 2))
        vBox:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText()) or 2
            SetSetting(trackerKey, "spacingV", val)
            RefreshLayout()
            self:ClearFocus()
        end)
        vBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        y = y - 26
        
        y = CreateHeader(parent, y, "Growth Direction")
        
        local growOptions = {
            { label = "Right", value = "RIGHT" },
            { label = "Left", value = "LEFT" },
            { label = "Down", value = "DOWN" },
            { label = "Up", value = "UP" },
        }
        
        y = CreateDropdown(parent, y, "Primary:", growOptions,
            function() return GetSetting(trackerKey, "growDirection") or "RIGHT" end,
            function(v) SetSetting(trackerKey, "growDirection", v) end)
        
        y = CreateDropdown(parent, y, "Secondary:", growOptions,
            function() return GetSetting(trackerKey, "growSecondary") or "DOWN" end,
            function(v) SetSetting(trackerKey, "growSecondary", v) end)
        
        local alignOptions = {
            { label = "Left", value = "LEFT" },
            { label = "Center", value = "CENTER" },
            { label = "Right", value = "RIGHT" },
        }
        
        y = CreateDropdown(parent, y, "Alignment:", alignOptions,
            function() return GetSetting(trackerKey, "alignment") or "LEFT" end,
            function(v) SetSetting(trackerKey, "alignment", v) end)
        
        y = CreateCheckbox(parent, y, "Reverse Icon Order",
            function() return GetSetting(trackerKey, "reverseOrder") end,
            function(v) SetSetting(trackerKey, "reverseOrder", v) end)
        
        -- ========== CUSTOM GRID SECTION ==========
        y = CreateHeader(parent, y, "Custom Grid (Advanced)")
        
        y = CreateCheckbox(parent, y, "Enable Custom Grid Pattern",
            function() return GetSetting(trackerKey, "useCustomGrid") or false end,
            function(v) 
                SetSetting(trackerKey, "useCustomGrid", v)
                -- Both enabling and disabling benefit from a reload for clean state
                StaticPopupDialogs["TUI_RELOAD_CUSTOM_GRID"] = {
                    text = "Custom Grid changes require a UI reload to fully apply. Reload now?",
                    button1 = "Reload",
                    button2 = "Later",
                    OnAccept = function()
                        ReloadUI()
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("TUI_RELOAD_CUSTOM_GRID")
            end)
        
        -- Mode dropdown (Row vs Column)
        local modeOptsCustom = {
            { label = "Row Mode (right then down)", value = "ROW" },
            { label = "Column Mode (down then right)", value = "COLUMN" },
        }
        y = CreateDropdown(parent, y, "Mode", modeOptsCustom,
            function() return GetSetting(trackerKey, "customGridMode") or "ROW" end,
            function(v) 
                SetSetting(trackerKey, "customGridMode", v)
                RebuildCustomTrackerIcons()
            end)
        
        -- Alignment dropdown - uses START/CENTER/END internally
        local alignOptsCustom = {
            { label = "Start (Left/Top)", value = "START" },
            { label = "Center (Middle)", value = "CENTER" },
            { label = "End (Right/Bottom)", value = "END" },
        }
        y = CreateDropdown(parent, y, "Alignment", alignOptsCustom,
            function() return GetSetting(trackerKey, "customGridAlign") or "START" end,
            function(v) 
                SetSetting(trackerKey, "customGridAlign", v)
                RebuildCustomTrackerIcons()
            end)
        
        -- Custom pattern edit box
        local patternLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        patternLabel:SetPoint("TOPLEFT", 10, y)
        patternLabel:SetText("Pattern (e.g. 4,4,2 or 3,0,3 for gap):")
        patternLabel:SetTextColor(0.8, 0.8, 0.8)
        y = y - 16
        
        local patternBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        patternBox:SetPoint("TOPLEFT", 10, y)
        patternBox:SetSize(120, 20)
        patternBox:SetAutoFocus(false)
        patternBox:SetText(GetSetting(trackerKey, "customLayout") or "")
        patternBox:SetScript("OnEnterPressed", function(self)
            SetSetting(trackerKey, "customLayout", self:GetText())
            RebuildCustomTrackerIcons()
            self:ClearFocus()
        end)
        patternBox:SetScript("OnEditFocusLost", function(self)
            SetSetting(trackerKey, "customLayout", self:GetText())
            RebuildCustomTrackerIcons()
        end)
        patternBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        
        -- Apply button
        local applyBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        applyBtn:SetPoint("LEFT", patternBox, "RIGHT", 5, 0)
        applyBtn:SetSize(50, 20)
        applyBtn:SetText("Apply")
        applyBtn:SetScript("OnClick", function()
            SetSetting(trackerKey, "customLayout", patternBox:GetText())
            RebuildCustomTrackerIcons()
            patternBox:ClearFocus()
        end)
        y = y - 26
        
        -- Hint text
        local hintLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintLabel:SetPoint("TOPLEFT", 10, y)
        hintLabel:SetText("Use 0 for blank rows/columns (e.g. 3,0,3 = gap)")
        hintLabel:SetTextColor(0.6, 0.6, 0.6)
        y = y - 18
        
        -- Reset Layout Settings button
        local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        resetBtn:SetPoint("TOPLEFT", 10, y)
        resetBtn:SetSize(160, 22)
        resetBtn:SetText("Reset Layout Settings")
        resetBtn:SetScript("OnClick", function()
            SetSetting(trackerKey, "columns", 4)
            SetSetting(trackerKey, "rows", 0)
            SetSetting(trackerKey, "spacingH", 2)
            SetSetting(trackerKey, "spacingV", 2)
            SetSetting(trackerKey, "growDirection", "RIGHT")
            SetSetting(trackerKey, "growSecondary", "DOWN")
            SetSetting(trackerKey, "alignment", "LEFT")
            SetSetting(trackerKey, "useCustomGrid", false)
            SetSetting(trackerKey, "customLayout", "")
            SetSetting(trackerKey, "customGridMode", "ROW")
            SetSetting(trackerKey, "customGridAlign", "START")
            SetSetting(trackerKey, "customLayoutMode", nil)
            RebuildCustomTrackerIcons()
            patternBox:SetText("")
            TUICD:Print("Layout settings reset for " .. trackerKey)
        end)
        y = y - 30
        
        parent:SetHeight(math.abs(y) + 20)
    end
    
    -- ========================================
    -- TAB 3: APPEARANCE
    -- ========================================
    local function BuildAppearanceTab(parent)
        local y = -10
        
        y = CreateHeader(parent, y, "Icon Appearance")
        
        y = CreateSlider(parent, y, "Zoom (texture crop)", 0, 0.15, 0.01,
            function() return GetSetting(trackerKey, "zoom") or 0.08 end,
            function(v) 
                SetSetting(trackerKey, "zoom", v)
                ApplyCustomTrackerEdgeStyles()
            end)
        
        y = CreateSlider(parent, y, "Out of Combat Opacity", 0.1, 1.0, 0.05,
            function() return GetSetting(trackerKey, "iconOpacity") or 1.0 end,
            function(v) SetSetting(trackerKey, "iconOpacity", v) end)
        
        y = CreateSlider(parent, y, "In Combat Opacity", 0.1, 1.0, 0.05,
            function() return GetSetting(trackerKey, "iconOpacityCombat") or 1.0 end,
            function(v) SetSetting(trackerKey, "iconOpacityCombat", v) end)
        
        y = CreateSlider(parent, y, "Border Opacity", 0, 1.0, 0.05,
            function() return GetSetting(trackerKey, "borderAlpha") or 1.0 end,
            function(v) SetSetting(trackerKey, "borderAlpha", v) end)
        
        y = y - 10  -- Add spacing before cooldown visibility options
        
        -- Unified sweep visibility (controls both aura and cooldown sweeps)
        y = CreateCheckbox(parent, y, "Show Cooldown Sweep",
            function() 
                local val = GetSetting(trackerKey, "showSweep")
                return val == nil or val == true  -- Default to true
            end,
            function(v) 
                SetSetting(trackerKey, "showSweep", v)
                -- Refresh layout to apply change
                LayoutCustomTrackerIcons()
                -- Also refresh highlight frames
                if TUICD.CooldownHighlights and TUICD.CooldownHighlights.RefreshAllHighlights then
                    TUICD.CooldownHighlights:RefreshAllHighlights(trackerKey)
                end
            end)
        
        -- Icon Edge Style dropdown
        local edgeStyleLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        edgeStyleLabel:SetPoint("TOPLEFT", 10, y - 5)
        edgeStyleLabel:SetText("Icon Edge Style")
        y = y - 20
        
        local edgeStyles = {
            {value = "sharp", label = "Sharp (Zoomed)"},
            {value = "rounded", label = "Rounded Corners"},
            {value = "square", label = "Square (Full)"},
        }
        
        local edgeDropdown = CreateFrame("Frame", "TweaksUI_CustomTracker_EdgeStyle", parent, "UIDropDownMenuTemplate")
        edgeDropdown:SetPoint("TOPLEFT", 0, y)
        UIDropDownMenu_SetWidth(edgeDropdown, 150)
        
        local currentEdge = GetSetting(trackerKey, "iconEdgeStyle") or "sharp"
        for _, opt in ipairs(edgeStyles) do
            if opt.value == currentEdge then
                UIDropDownMenu_SetText(edgeDropdown, opt.label)
                break
            end
        end
        
        UIDropDownMenu_Initialize(edgeDropdown, function(self, level)
            for _, opt in ipairs(edgeStyles) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.func = function(self)
                    SetSetting(trackerKey, "iconEdgeStyle", self.value)
                    UIDropDownMenu_SetText(edgeDropdown, self:GetText())
                    ApplyCustomTrackerEdgeStyles()
                end
                info.checked = (GetSetting(trackerKey, "iconEdgeStyle") or "sharp") == opt.value
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        y = y - 35
        
        -- Masque checkbox (only show if Masque is available)
        if Masque then
            y = CreateCheckbox(parent, y, "Use Masque Skinning",
                function() return GetSetting(trackerKey, "useMasque") or false end,
                function(v) 
                    SetSetting(trackerKey, "useMasque", v) 
                    -- Rebuild custom tracker icons with new style
                    RebuildCustomTrackerIcons()
                    -- Reskin group if enabling
                    if v then
                        ReskinMasqueGroup(trackerKey)
                    end
                end)
        end
        
        parent:SetHeight(math.abs(y) + 20)
    end
    
    -- ========================================
    -- TAB 4: TEXT
    -- ========================================
    local function BuildTextTab(parent)
        local y = -10
        
        -- Local RefreshLayout helper
        local function RefreshLayout()
            UpdateCustomTrackerLayout()
        end
        
        -- Helper to create a font dropdown
        local function CreateFontDropdown(yPos, labelText, settingKey)
            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", 10, yPos)
            label:SetText(labelText)
            
            local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
            dropdown:SetPoint("TOPLEFT", 0, yPos - 18)
            UIDropDownMenu_SetWidth(dropdown, 180)
            
            local function UpdateDropdownText()
                local currentFont = GetSetting(trackerKey, settingKey) or "Default"
                UIDropDownMenu_SetText(dropdown, currentFont)
            end
            
            UIDropDownMenu_Initialize(dropdown, function(self, level)
                local fonts = TUICD.Media and TUICD.Media:GetFontList() or {"Default"}
                for _, fontName in ipairs(fonts) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = fontName
                    info.checked = (GetSetting(trackerKey, settingKey) or "Default") == fontName
                    info.func = function()
                        SetSetting(trackerKey, settingKey, fontName)
                        UpdateDropdownText()
                        RefreshLayout()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            
            UpdateDropdownText()
            
            return yPos - 50
        end
        
        -- Helper to create a color picker button
        local function CreateColorButton(yPos, labelText, rKey, gKey, bKey)
            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", 10, yPos)
            label:SetText(labelText)
            
            local colorBtn = CreateFrame("Button", nil, parent)
            colorBtn:SetSize(24, 24)
            colorBtn:SetPoint("LEFT", label, "RIGHT", 10, 0)
            
            local colorTex = colorBtn:CreateTexture(nil, "ARTWORK")
            colorTex:SetPoint("TOPLEFT", 2, -2)
            colorTex:SetPoint("BOTTOMRIGHT", -2, 2)
            colorTex:SetColorTexture(
                GetSetting(trackerKey, rKey) or 1,
                GetSetting(trackerKey, gKey) or 1,
                GetSetting(trackerKey, bKey) or 1
            )
            colorBtn.colorTex = colorTex
            
            local border = colorBtn:CreateTexture(nil, "BACKGROUND")
            border:SetAllPoints()
            border:SetColorTexture(0.2, 0.2, 0.2, 1)
            
            colorBtn:SetScript("OnClick", function(self)
                local r = GetSetting(trackerKey, rKey) or 1
                local g = GetSetting(trackerKey, gKey) or 1
                local b = GetSetting(trackerKey, bKey) or 1
                
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = r, g = g, b = b,
                    swatchFunc = function()
                        local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                        SetSetting(trackerKey, rKey, newR)
                        SetSetting(trackerKey, gKey, newG)
                        SetSetting(trackerKey, bKey, newB)
                        self.colorTex:SetColorTexture(newR, newG, newB)
                        RefreshLayout()
                    end,
                    cancelFunc = function(prev)
                        SetSetting(trackerKey, rKey, prev.r)
                        SetSetting(trackerKey, gKey, prev.g)
                        SetSetting(trackerKey, bKey, prev.b)
                        self.colorTex:SetColorTexture(prev.r, prev.g, prev.b)
                        RefreshLayout()
                    end,
                })
            end)
            
            colorBtn:SetScript("OnShow", function(self)
                self.colorTex:SetColorTexture(
                    GetSetting(trackerKey, rKey) or 1,
                    GetSetting(trackerKey, gKey) or 1,
                    GetSetting(trackerKey, bKey) or 1
                )
            end)
            
            return yPos - 30
        end
        
        -- ========== COOLDOWN TEXT ==========
        y = CreateHeader(parent, y, "Cooldown Text")
        
        y = CreateFontDropdown(y, "Font:", "cooldownTextFont")
        
        y = CreateSlider(parent, y, "Scale", 0.5, 2.0, 0.1,
            function() return GetSetting(trackerKey, "cooldownTextScale") or 1.0 end,
            function(v) 
                SetSetting(trackerKey, "cooldownTextScale", v) 
                RefreshLayout()
            end)
        
        y = CreateSlider(parent, y, "Offset X", -20, 20, 1,
            function() return GetSetting(trackerKey, "cooldownTextOffsetX") or 0 end,
            function(v) 
                SetSetting(trackerKey, "cooldownTextOffsetX", v)
                RefreshLayout()
            end)
        
        y = CreateSlider(parent, y, "Offset Y", -20, 20, 1,
            function() return GetSetting(trackerKey, "cooldownTextOffsetY") or 0 end,
            function(v) 
                SetSetting(trackerKey, "cooldownTextOffsetY", v)
                RefreshLayout()
            end)
        
        y = CreateColorButton(y, "Color:", "cooldownTextColorR", "cooldownTextColorG", "cooldownTextColorB")
        
        -- ========== COUNT/CHARGE TEXT ==========
        y = CreateHeader(parent, y - 10, "Count/Charge Text")
        
        y = CreateFontDropdown(y, "Font:", "countTextFont")
        
        y = CreateSlider(parent, y, "Scale", 0.5, 2.0, 0.1,
            function() return GetSetting(trackerKey, "countTextScale") or 1.0 end,
            function(v) 
                SetSetting(trackerKey, "countTextScale", v)
                RefreshLayout()
            end)
        
        y = CreateSlider(parent, y, "Offset X", -20, 20, 1,
            function() return GetSetting(trackerKey, "countTextOffsetX") or 0 end,
            function(v) 
                SetSetting(trackerKey, "countTextOffsetX", v)
                RefreshLayout()
            end)
        
        y = CreateSlider(parent, y, "Offset Y", -20, 20, 1,
            function() return GetSetting(trackerKey, "countTextOffsetY") or 0 end,
            function(v) 
                SetSetting(trackerKey, "countTextOffsetY", v)
                RefreshLayout()
            end)
        
        y = CreateColorButton(y, "Color:", "countTextColorR", "countTextColorG", "countTextColorB")
        
        parent:SetHeight(math.abs(y) + 20)
    end
    
    -- ========================================
    -- TAB 5: VISIBILITY
    -- ========================================
    local function BuildVisibilityTab(parent)
        local y = -10
        
        y = CreateHeader(parent, y, "Behavior")
        
        y = CreateCheckbox(parent, y, "Show Tooltips on Mouseover",
            function() return GetSetting(trackerKey, "showTooltip") ~= false end,
            function(v) 
                SetSetting(trackerKey, "showTooltip", v)
                -- Custom trackers check this in OnEnter, no rebuild needed
            end)
        
        y = CreateHeader(parent, y, "Visibility Conditions")
        
        y = CreateCheckbox(parent, y, "Enable Visibility Conditions",
            function() return GetSetting(trackerKey, "visibilityEnabled") or false end,
            function(v) SetSetting(trackerKey, "visibilityEnabled", v) end)
        
        y = CreateHeader(parent, y, "Show When (OR logic)")
        
        y = CreateCheckbox(parent, y, "In Combat",
            function() return GetSetting(trackerKey, "showInCombat") end,
            function(v) SetSetting(trackerKey, "showInCombat", v) end)
        
        y = CreateCheckbox(parent, y, "Out of Combat",
            function() return GetSetting(trackerKey, "showOutOfCombat") end,
            function(v) SetSetting(trackerKey, "showOutOfCombat", v) end)
        
        y = CreateCheckbox(parent, y, "Solo",
            function() return GetSetting(trackerKey, "showSolo") end,
            function(v) SetSetting(trackerKey, "showSolo", v) end)
        
        y = CreateCheckbox(parent, y, "In Party",
            function() return GetSetting(trackerKey, "showInParty") end,
            function(v) SetSetting(trackerKey, "showInParty", v) end)
        
        y = CreateCheckbox(parent, y, "In Raid",
            function() return GetSetting(trackerKey, "showInRaid") end,
            function(v) SetSetting(trackerKey, "showInRaid", v) end)
        
        y = CreateCheckbox(parent, y, "In Instance (Dungeon)",
            function() return GetSetting(trackerKey, "showInInstance") end,
            function(v) SetSetting(trackerKey, "showInInstance", v) end)
        
        y = CreateCheckbox(parent, y, "In Arena",
            function() return GetSetting(trackerKey, "showInArena") end,
            function(v) SetSetting(trackerKey, "showInArena", v) end)
        
        y = CreateCheckbox(parent, y, "In Battleground",
            function() return GetSetting(trackerKey, "showInBattleground") end,
            function(v) SetSetting(trackerKey, "showInBattleground", v) end)
        
        y = CreateCheckbox(parent, y, "Has Target",
            function() return GetSetting(trackerKey, "showHasTarget") end,
            function(v) SetSetting(trackerKey, "showHasTarget", v) end)
        
        y = CreateCheckbox(parent, y, "No Target",
            function() return GetSetting(trackerKey, "showNoTarget") end,
            function(v) SetSetting(trackerKey, "showNoTarget", v) end)
        
        y = CreateCheckbox(parent, y, "Mounted",
            function() return GetSetting(trackerKey, "showMounted") end,
            function(v) SetSetting(trackerKey, "showMounted", v) end)
        
        y = CreateCheckbox(parent, y, "Not Mounted",
            function() return GetSetting(trackerKey, "showNotMounted") end,
            function(v) SetSetting(trackerKey, "showNotMounted", v) end)
        
        y = CreateHeader(parent, y, "Interaction")
        
        y = CreateCheckbox(parent, y, "Clickthrough (ignore mouse)",
            function() return GetSetting(trackerKey, "clickthrough") or false end,
            function(v) 
                SetSetting(trackerKey, "clickthrough", v)
                -- Apply immediately to the viewer
                ApplyClickthrough(trackerKey)
            end)
        
        parent:SetHeight(math.abs(y) + 20)
    end
    
    -- ========================================
    -- TAB: Individual Icons Settings for Custom Trackers
    -- ========================================
    local function BuildPerIconTab(parent)
        local y = -10
        local CooldownHighlights = TUICD.CooldownHighlights
        local customTrackerKey = "custom"  -- CooldownHighlights uses "custom" for custom trackers
        local selectedSlot = nil
        local currentState = "active"
        local slotRows = {}
        
        -- Aspect ratio presets
        local ASPECT_OPTIONS = {
            { label = "1:1 (Square)", value = "1:1" },
            { label = "4:3", value = "4:3" },
            { label = "3:4", value = "3:4" },
            { label = "16:9 (Wide)", value = "16:9" },
            { label = "9:16 (Tall)", value = "9:16" },
            { label = "2:1", value = "2:1" },
            { label = "1:2", value = "1:2" },
            { label = "Custom", value = "custom" },
        }
        
        -- Header
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 5, y)
        header:SetText("Individual Icons")
        header:SetTextColor(1, 0.82, 0)
        
        -- Refresh button (at top right, script set later after RefreshSlotList is defined)
        local refreshBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        refreshBtn:SetPoint("TOPRIGHT", -5, y)
        refreshBtn:SetSize(100, 20)
        refreshBtn:SetText("Refresh List")
        y = y - 26
        
        -- Description
        local description = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        description:SetPoint("TOPLEFT", 5, y)
        description:SetPoint("TOPRIGHT", -10, y)
        description:SetJustifyH("LEFT")
        description:SetText("|cff888888Create individual icons for your abilities that can be configured and moved outside of the main trackers.|r")
        y = y - 18
        
        -- Hide Tracker checkbox
        local hideTrackerCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        hideTrackerCheck:SetPoint("TOPLEFT", 5, y)
        hideTrackerCheck:SetSize(24, 24)
        hideTrackerCheck:SetChecked(CooldownHighlights and CooldownHighlights:IsTrackerHidden(customTrackerKey) or false)
        hideTrackerCheck:SetScript("OnClick", function(self)
            if CooldownHighlights then
                CooldownHighlights:SetTrackerHidden(customTrackerKey, self:GetChecked())
                Cooldowns:SaveSettings()
            end
        end)
        
        local hideTrackerLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hideTrackerLabel:SetPoint("LEFT", hideTrackerCheck, "RIGHT", 2, 0)
        hideTrackerLabel:SetText("Hide Custom Trackers (use individual icons only)")
        hideTrackerLabel:SetTextColor(0.9, 0.9, 0.9)
        y = y - 26
        
        -- Slot list container
        local listContainer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        listContainer:SetPoint("TOPLEFT", 5, y)
        listContainer:SetSize(PANEL_WIDTH - 60, 90)
        listContainer:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        listContainer:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        listContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        
        -- Create scroll frame inside list container
        local scrollFrame = CreateFrame("ScrollFrame", nil, listContainer, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 2, -2)
        scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
        
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(PANEL_WIDTH - 84)
        scrollChild:SetHeight(1)  -- Will be updated dynamically
        scrollFrame:SetScrollChild(scrollChild)
        
        y = y - 100
        
        -- Controls container with backdrop (outer frame)
        local controlsContainer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        controlsContainer:SetPoint("TOPLEFT", 5, y)
        controlsContainer:SetSize(PANEL_WIDTH - 60, 560)
        controlsContainer:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        controlsContainer:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
        controlsContainer:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        
        -- Scroll frame inside container
        local controlsScrollFrame = CreateFrame("ScrollFrame", nil, controlsContainer, "UIPanelScrollFrameTemplate")
        controlsScrollFrame:SetPoint("TOPLEFT", 2, -2)
        controlsScrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
        
        -- Controls panel as scroll child (content area)
        local controlsPanel = CreateFrame("Frame", nil, controlsScrollFrame)
        controlsPanel:SetSize(PANEL_WIDTH - 84, 820)  -- Height for full content
        controlsScrollFrame:SetScrollChild(controlsPanel)
        
        -- "No Selection" label (on container, not scroll child, so it stays centered)
        local noSelectionLabel = controlsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noSelectionLabel:SetPoint("CENTER")
        noSelectionLabel:SetText("Select a custom tracker slot above")
        noSelectionLabel:SetTextColor(0.5, 0.5, 0.5)
        
        -- All controls
        local controls = {}
        
        controls.header = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.header:SetPoint("TOPLEFT", 10, -8)
        controls.header:SetTextColor(1, 0.82, 0)
        controls.header:Hide()
        
        controls.iconPreview = controlsPanel:CreateTexture(nil, "ARTWORK")
        controls.iconPreview:SetPoint("LEFT", controls.header, "RIGHT", 8, 0)
        controls.iconPreview:SetSize(20, 20)
        controls.iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        controls.iconPreview:Hide()
        
        controls.enableCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.enableCheck:SetPoint("TOPLEFT", 10, -30)
        controls.enableCheck:SetSize(24, 24)
        controls.enableCheck:Hide()
        
        controls.enableLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.enableLabel:SetPoint("LEFT", controls.enableCheck, "RIGHT", 2, 0)
        controls.enableLabel:SetText("Enable Individual Icon")
        controls.enableLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.enableLabel:Hide()
        
        -- Hide in tracker checkbox
        controls.hideCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.hideCheck:SetPoint("LEFT", controls.enableLabel, "RIGHT", 20, 0)
        controls.hideCheck:SetSize(24, 24)
        controls.hideCheck:Hide()
        
        controls.hideLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.hideLabel:SetPoint("LEFT", controls.hideCheck, "RIGHT", 2, 0)
        controls.hideLabel:SetText("Hide in Tracker")
        controls.hideLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.hideLabel:Hide()
        
        controls.stateLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.stateLabel:SetPoint("TOPLEFT", 10, -58)
        controls.stateLabel:SetText("Configure State:")
        controls.stateLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.stateLabel:Hide()
        
        controls.activeBtn = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
        controls.activeBtn:SetPoint("LEFT", controls.stateLabel, "RIGHT", 8, 0)
        controls.activeBtn:SetSize(70, 20)
        controls.activeBtn:SetText("Ready")
        controls.activeBtn:Hide()
        
        controls.inactiveBtn = CreateFrame("Button", nil, controlsPanel, "UIPanelButtonTemplate")
        controls.inactiveBtn:SetPoint("LEFT", controls.activeBtn, "RIGHT", 4, 0)
        controls.inactiveBtn:SetSize(90, 20)
        controls.inactiveBtn:SetText("On Cooldown")
        controls.inactiveBtn:Hide()
        
        controls.showCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.showCheck:SetPoint("TOPLEFT", 10, -85)
        controls.showCheck:SetSize(24, 24)
        controls.showCheck:Hide()
        
        controls.showLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.showLabel:SetPoint("LEFT", controls.showCheck, "RIGHT", 2, 0)
        controls.showLabel:SetText("Show when Ready")
        controls.showLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.showLabel:Hide()
        
        controls.sizeLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.sizeLabel:SetPoint("TOPLEFT", 10, -115)
        controls.sizeLabel:SetText("Size:")
        controls.sizeLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.sizeLabel:Hide()
        
        controls.sizeSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.sizeSlider:SetPoint("LEFT", controls.sizeLabel, "RIGHT", 15, 0)
        controls.sizeSlider:SetSize(90, 16)
        controls.sizeSlider:SetMinMaxValues(24, 128)
        controls.sizeSlider:SetValueStep(2)
        controls.sizeSlider:SetObeyStepOnDrag(true)
        controls.sizeSlider.Low:SetText("")
        controls.sizeSlider.High:SetText("")
        controls.sizeSlider.Text:SetText("")
        controls.sizeSlider:Hide()
        
        controls.sizeValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.sizeValue:SetPoint("LEFT", controls.sizeSlider, "RIGHT", 8, 0)
        controls.sizeValue:SetTextColor(1, 1, 1)
        controls.sizeValue:Hide()
        
        controls.opacityLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.opacityLabel:SetPoint("TOPLEFT", 10, -145)
        controls.opacityLabel:SetText("Opacity:")
        controls.opacityLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.opacityLabel:Hide()
        
        controls.opacitySlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.opacitySlider:SetPoint("LEFT", controls.opacityLabel, "RIGHT", 5, 0)
        controls.opacitySlider:SetSize(90, 16)
        controls.opacitySlider:SetMinMaxValues(0.1, 1.0)
        controls.opacitySlider:SetValueStep(0.05)
        controls.opacitySlider:SetObeyStepOnDrag(true)
        controls.opacitySlider.Low:SetText("")
        controls.opacitySlider.High:SetText("")
        controls.opacitySlider.Text:SetText("")
        controls.opacitySlider:Hide()
        
        controls.opacityValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.opacityValue:SetPoint("LEFT", controls.opacitySlider, "RIGHT", 8, 0)
        controls.opacityValue:SetTextColor(1, 1, 1)
        controls.opacityValue:Hide()
        
        controls.desatCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.desatCheck:SetPoint("TOPLEFT", 10, -175)
        controls.desatCheck:SetSize(24, 24)
        controls.desatCheck:Hide()
        
        controls.desatLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.desatLabel:SetPoint("LEFT", controls.desatCheck, "RIGHT", 2, 0)
        controls.desatLabel:SetText("Desaturate (grayscale)")
        controls.desatLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.desatLabel:Hide()
        
        controls.aspectLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.aspectLabel:SetPoint("TOPLEFT", 10, -205)
        controls.aspectLabel:SetText("Aspect Ratio:")
        controls.aspectLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.aspectLabel:Hide()
        
        controls.aspectDropdown = CreateFrame("Frame", nil, controlsPanel, "UIDropDownMenuTemplate")
        controls.aspectDropdown:SetPoint("TOPLEFT", 60, -200)
        UIDropDownMenu_SetWidth(controls.aspectDropdown, 100)
        controls.aspectDropdown:Hide()
        
        controls.customLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.customLabel:SetPoint("TOPLEFT", 10, -235)
        controls.customLabel:SetText("Custom W:")
        controls.customLabel:SetTextColor(0.7, 0.7, 0.7)
        controls.customLabel:Hide()
        
        controls.customW = CreateFrame("EditBox", nil, controlsPanel, "InputBoxTemplate")
        controls.customW:SetPoint("LEFT", controls.customLabel, "RIGHT", 2, 0)
        controls.customW:SetSize(30, 18)
        controls.customW:SetAutoFocus(false)
        controls.customW:SetNumeric(true)
        controls.customW:SetMaxLetters(3)
        controls.customW:Hide()
        
        controls.customSep = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.customSep:SetPoint("LEFT", controls.customW, "RIGHT", 4, 0)
        controls.customSep:SetText("H:")
        controls.customSep:SetTextColor(0.7, 0.7, 0.7)
        controls.customSep:Hide()
        
        controls.customH = CreateFrame("EditBox", nil, controlsPanel, "InputBoxTemplate")
        controls.customH:SetPoint("LEFT", controls.customSep, "RIGHT", 2, 0)
        controls.customH:SetSize(30, 18)
        controls.customH:SetAutoFocus(false)
        controls.customH:SetNumeric(true)
        controls.customH:SetMaxLetters(3)
        controls.customH:Hide()
        
        -- Dock Assignment
        
        controls.dockHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.dockHeader:SetPoint("TOPLEFT", 10, -265)
        controls.dockHeader:SetText("Dock Assignment")
        controls.dockHeader:SetTextColor(1, 0.82, 0)
        controls.dockHeader:Hide()
        
        controls.dockLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.dockLabel:SetPoint("TOPLEFT", 10, -285)
        controls.dockLabel:SetText("Assign to Dock:")
        controls.dockLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.dockLabel:Hide()
        
        controls.dockDropdown = CreateFrame("Frame", nil, controlsPanel, "UIDropDownMenuTemplate")
        controls.dockDropdown:SetPoint("TOPLEFT", 80, -278)
        UIDropDownMenu_SetWidth(controls.dockDropdown, 120)
        controls.dockDropdown:Hide()
        
        -- =====================================================
        -- Custom Label Controls (Accessibility feature)
        -- =====================================================
        controls.labelHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.labelHeader:SetPoint("TOPLEFT", 10, -305)
        controls.labelHeader:SetText("Custom Label (Accessibility)")
        controls.labelHeader:SetTextColor(1, 0.82, 0)
        controls.labelHeader:Hide()
        
        controls.labelEnableCheck = CreateFrame("CheckButton", nil, controlsPanel, "UICheckButtonTemplate")
        controls.labelEnableCheck:SetPoint("TOPLEFT", 10, -325)
        controls.labelEnableCheck:SetSize(24, 24)
        controls.labelEnableCheck:Hide()
        
        controls.labelEnableLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelEnableLabel:SetPoint("LEFT", controls.labelEnableCheck, "RIGHT", 2, 0)
        controls.labelEnableLabel:SetText("Show Custom Label")
        controls.labelEnableLabel:SetTextColor(0.9, 0.9, 0.9)
        controls.labelEnableLabel:Hide()
        
        controls.labelTextLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelTextLabel:SetPoint("TOPLEFT", 10, -355)
        controls.labelTextLabel:SetText("Text:")
        controls.labelTextLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelTextLabel:Hide()
        
        controls.labelTextBox = CreateFrame("EditBox", nil, controlsPanel, "InputBoxTemplate")
        controls.labelTextBox:SetPoint("LEFT", controls.labelTextLabel, "RIGHT", 8, 0)
        controls.labelTextBox:SetSize(120, 18)
        controls.labelTextBox:SetAutoFocus(false)
        controls.labelTextBox:SetMaxLetters(20)
        controls.labelTextBox:Hide()
        
        controls.labelSizeLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelSizeLabel:SetPoint("TOPLEFT", 10, -380)
        controls.labelSizeLabel:SetText("Font Size:")
        controls.labelSizeLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelSizeLabel:Hide()
        
        controls.labelSizeSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.labelSizeSlider:SetPoint("LEFT", controls.labelSizeLabel, "RIGHT", 5, 0)
        controls.labelSizeSlider:SetSize(80, 16)
        controls.labelSizeSlider:SetMinMaxValues(8, 32)
        controls.labelSizeSlider:SetValueStep(1)
        controls.labelSizeSlider:SetObeyStepOnDrag(true)
        controls.labelSizeSlider.Low:SetText("")
        controls.labelSizeSlider.High:SetText("")
        controls.labelSizeSlider.Text:SetText("")
        controls.labelSizeSlider:Hide()
        
        controls.labelSizeValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelSizeValue:SetPoint("LEFT", controls.labelSizeSlider, "RIGHT", 8, 0)
        controls.labelSizeValue:SetTextColor(1, 1, 1)
        controls.labelSizeValue:Hide()
        
        controls.labelColorLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelColorLabel:SetPoint("TOPLEFT", 10, -405)
        controls.labelColorLabel:SetText("Color:")
        controls.labelColorLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelColorLabel:Hide()
        
        controls.labelColorBtn = CreateFrame("Button", nil, controlsPanel, "BackdropTemplate")
        controls.labelColorBtn:SetPoint("LEFT", controls.labelColorLabel, "RIGHT", 8, 0)
        controls.labelColorBtn:SetSize(20, 20)
        controls.labelColorBtn:SetBackdrop({ 
            bgFile = "Interface\\BUTTONS\\WHITE8X8", 
            edgeFile = "Interface\\BUTTONS\\WHITE8X8", 
            edgeSize = 1 
        })
        controls.labelColorBtn:SetBackdropColor(1, 1, 1, 1)
        controls.labelColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        controls.labelColorBtn:Hide()
        
        controls.labelOffsetLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetLabel:SetPoint("TOPLEFT", 10, -430)
        controls.labelOffsetLabel:SetText("Offset X:")
        controls.labelOffsetLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelOffsetLabel:Hide()
        
        controls.labelOffsetXSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.labelOffsetXSlider:SetPoint("LEFT", controls.labelOffsetLabel, "RIGHT", 5, 0)
        controls.labelOffsetXSlider:SetSize(100, 16)
        controls.labelOffsetXSlider:SetMinMaxValues(-100, 100)
        controls.labelOffsetXSlider:SetValueStep(1)
        controls.labelOffsetXSlider:SetObeyStepOnDrag(true)
        controls.labelOffsetXSlider.Low:SetText("")
        controls.labelOffsetXSlider.High:SetText("")
        controls.labelOffsetXSlider.Text:SetText("")
        controls.labelOffsetXSlider:Hide()
        
        controls.labelOffsetXValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetXValue:SetPoint("LEFT", controls.labelOffsetXSlider, "RIGHT", 5, 0)
        controls.labelOffsetXValue:SetTextColor(1, 1, 1)
        controls.labelOffsetXValue:Hide()
        
        controls.labelOffsetYLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetYLabel:SetPoint("TOPLEFT", 10, -455)
        controls.labelOffsetYLabel:SetText("Offset Y:")
        controls.labelOffsetYLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.labelOffsetYLabel:Hide()
        
        controls.labelOffsetYSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.labelOffsetYSlider:SetPoint("LEFT", controls.labelOffsetYLabel, "RIGHT", 5, 0)
        controls.labelOffsetYSlider:SetSize(100, 16)
        controls.labelOffsetYSlider:SetMinMaxValues(-100, 100)
        controls.labelOffsetYSlider:SetValueStep(1)
        controls.labelOffsetYSlider:SetObeyStepOnDrag(true)
        controls.labelOffsetYSlider.Low:SetText("")
        controls.labelOffsetYSlider.High:SetText("")
        controls.labelOffsetYSlider.Text:SetText("")
        controls.labelOffsetYSlider:Hide()
        
        controls.labelOffsetYValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.labelOffsetYValue:SetPoint("LEFT", controls.labelOffsetYSlider, "RIGHT", 5, 0)
        controls.labelOffsetYValue:SetTextColor(1, 1, 1)
        controls.labelOffsetYValue:Hide()
        
        -- =====================================================
        -- Per-Icon Text Controls (Cooldown Timer)
        -- =====================================================
        controls.cooldownTextHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.cooldownTextHeader:SetPoint("TOPLEFT", 200, -305)
        controls.cooldownTextHeader:SetText("Cooldown Text")
        controls.cooldownTextHeader:SetTextColor(1, 0.82, 0)
        controls.cooldownTextHeader:Hide()
        
        controls.cooldownTextScaleLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextScaleLabel:SetPoint("TOPLEFT", 200, -325)
        controls.cooldownTextScaleLabel:SetText("Scale:")
        controls.cooldownTextScaleLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextScaleLabel:Hide()
        
        controls.cooldownTextSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.cooldownTextSlider:SetPoint("LEFT", controls.cooldownTextScaleLabel, "RIGHT", 10, 0)
        controls.cooldownTextSlider:SetSize(70, 16)
        controls.cooldownTextSlider:SetMinMaxValues(0.5, 2.0)
        controls.cooldownTextSlider:SetValueStep(0.1)
        controls.cooldownTextSlider:SetObeyStepOnDrag(true)
        controls.cooldownTextSlider.Low:SetText("")
        controls.cooldownTextSlider.High:SetText("")
        controls.cooldownTextSlider.Text:SetText("")
        controls.cooldownTextSlider:Hide()
        
        controls.cooldownTextValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextValue:SetPoint("LEFT", controls.cooldownTextSlider, "RIGHT", 5, 0)
        controls.cooldownTextValue:SetTextColor(1, 1, 1)
        controls.cooldownTextValue:Hide()
        
        controls.cooldownTextColorLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextColorLabel:SetPoint("TOPLEFT", 200, -350)
        controls.cooldownTextColorLabel:SetText("Color:")
        controls.cooldownTextColorLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextColorLabel:Hide()
        
        controls.cooldownTextColorBtn = CreateFrame("Button", nil, controlsPanel, "BackdropTemplate")
        controls.cooldownTextColorBtn:SetPoint("LEFT", controls.cooldownTextColorLabel, "RIGHT", 10, 0)
        controls.cooldownTextColorBtn:SetSize(24, 16)
        controls.cooldownTextColorBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
        controls.cooldownTextColorBtn:SetBackdropColor(1, 1, 1, 1)
        controls.cooldownTextColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        controls.cooldownTextColorBtn:Hide()
        
        controls.cooldownTextOffsetXLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetXLabel:SetPoint("TOPLEFT", 200, -375)
        controls.cooldownTextOffsetXLabel:SetText("Offset X:")
        controls.cooldownTextOffsetXLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextOffsetXLabel:Hide()
        
        controls.cooldownTextOffsetXSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.cooldownTextOffsetXSlider:SetPoint("LEFT", controls.cooldownTextOffsetXLabel, "RIGHT", 5, 0)
        controls.cooldownTextOffsetXSlider:SetSize(100, 16)
        controls.cooldownTextOffsetXSlider:SetMinMaxValues(-100, 100)
        controls.cooldownTextOffsetXSlider:SetValueStep(1)
        controls.cooldownTextOffsetXSlider:SetObeyStepOnDrag(true)
        controls.cooldownTextOffsetXSlider.Low:SetText("")
        controls.cooldownTextOffsetXSlider.High:SetText("")
        controls.cooldownTextOffsetXSlider.Text:SetText("")
        controls.cooldownTextOffsetXSlider:Hide()
        
        controls.cooldownTextOffsetXValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetXValue:SetPoint("LEFT", controls.cooldownTextOffsetXSlider, "RIGHT", 5, 0)
        controls.cooldownTextOffsetXValue:SetTextColor(1, 1, 1)
        controls.cooldownTextOffsetXValue:Hide()
        
        controls.cooldownTextOffsetYLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetYLabel:SetPoint("TOPLEFT", 200, -400)
        controls.cooldownTextOffsetYLabel:SetText("Offset Y:")
        controls.cooldownTextOffsetYLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.cooldownTextOffsetYLabel:Hide()
        
        controls.cooldownTextOffsetYSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.cooldownTextOffsetYSlider:SetPoint("LEFT", controls.cooldownTextOffsetYLabel, "RIGHT", 5, 0)
        controls.cooldownTextOffsetYSlider:SetSize(100, 16)
        controls.cooldownTextOffsetYSlider:SetMinMaxValues(-100, 100)
        controls.cooldownTextOffsetYSlider:SetValueStep(1)
        controls.cooldownTextOffsetYSlider:SetObeyStepOnDrag(true)
        controls.cooldownTextOffsetYSlider.Low:SetText("")
        controls.cooldownTextOffsetYSlider.High:SetText("")
        controls.cooldownTextOffsetYSlider.Text:SetText("")
        controls.cooldownTextOffsetYSlider:Hide()
        
        controls.cooldownTextOffsetYValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.cooldownTextOffsetYValue:SetPoint("LEFT", controls.cooldownTextOffsetYSlider, "RIGHT", 5, 0)
        controls.cooldownTextOffsetYValue:SetTextColor(1, 1, 1)
        controls.cooldownTextOffsetYValue:Hide()
        
        -- =====================================================
        -- Per-Icon Text Controls (Count/Charge Text)
        -- =====================================================
        controls.countTextHeader = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        controls.countTextHeader:SetPoint("TOPLEFT", 200, -430)
        controls.countTextHeader:SetText("Count/Charge Text")
        controls.countTextHeader:SetTextColor(1, 0.82, 0)
        controls.countTextHeader:Hide()
        
        controls.countTextScaleLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextScaleLabel:SetPoint("TOPLEFT", 200, -450)
        controls.countTextScaleLabel:SetText("Scale:")
        controls.countTextScaleLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextScaleLabel:Hide()
        
        controls.countTextSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.countTextSlider:SetPoint("LEFT", controls.countTextScaleLabel, "RIGHT", 10, 0)
        controls.countTextSlider:SetSize(70, 16)
        controls.countTextSlider:SetMinMaxValues(0.5, 2.0)
        controls.countTextSlider:SetValueStep(0.1)
        controls.countTextSlider:SetObeyStepOnDrag(true)
        controls.countTextSlider.Low:SetText("")
        controls.countTextSlider.High:SetText("")
        controls.countTextSlider.Text:SetText("")
        controls.countTextSlider:Hide()
        
        controls.countTextValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextValue:SetPoint("LEFT", controls.countTextSlider, "RIGHT", 5, 0)
        controls.countTextValue:SetTextColor(1, 1, 1)
        controls.countTextValue:Hide()
        
        controls.countTextColorLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextColorLabel:SetPoint("TOPLEFT", 200, -475)
        controls.countTextColorLabel:SetText("Color:")
        controls.countTextColorLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextColorLabel:Hide()
        
        controls.countTextColorBtn = CreateFrame("Button", nil, controlsPanel, "BackdropTemplate")
        controls.countTextColorBtn:SetPoint("LEFT", controls.countTextColorLabel, "RIGHT", 10, 0)
        controls.countTextColorBtn:SetSize(24, 16)
        controls.countTextColorBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
        controls.countTextColorBtn:SetBackdropColor(1, 1, 1, 1)
        controls.countTextColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        controls.countTextColorBtn:Hide()
        
        controls.countTextOffsetXLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetXLabel:SetPoint("TOPLEFT", 200, -500)
        controls.countTextOffsetXLabel:SetText("Offset X:")
        controls.countTextOffsetXLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextOffsetXLabel:Hide()
        
        controls.countTextOffsetXSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.countTextOffsetXSlider:SetPoint("LEFT", controls.countTextOffsetXLabel, "RIGHT", 5, 0)
        controls.countTextOffsetXSlider:SetSize(100, 16)
        controls.countTextOffsetXSlider:SetMinMaxValues(-100, 100)
        controls.countTextOffsetXSlider:SetValueStep(1)
        controls.countTextOffsetXSlider:SetObeyStepOnDrag(true)
        controls.countTextOffsetXSlider.Low:SetText("")
        controls.countTextOffsetXSlider.High:SetText("")
        controls.countTextOffsetXSlider.Text:SetText("")
        controls.countTextOffsetXSlider:Hide()
        
        controls.countTextOffsetXValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetXValue:SetPoint("LEFT", controls.countTextOffsetXSlider, "RIGHT", 5, 0)
        controls.countTextOffsetXValue:SetTextColor(1, 1, 1)
        controls.countTextOffsetXValue:Hide()
        
        controls.countTextOffsetYLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetYLabel:SetPoint("TOPLEFT", 200, -525)
        controls.countTextOffsetYLabel:SetText("Offset Y:")
        controls.countTextOffsetYLabel:SetTextColor(0.8, 0.8, 0.8)
        controls.countTextOffsetYLabel:Hide()
        
        controls.countTextOffsetYSlider = CreateFrame("Slider", nil, controlsPanel, "OptionsSliderTemplate")
        controls.countTextOffsetYSlider:SetPoint("LEFT", controls.countTextOffsetYLabel, "RIGHT", 5, 0)
        controls.countTextOffsetYSlider:SetSize(100, 16)
        controls.countTextOffsetYSlider:SetMinMaxValues(-100, 100)
        controls.countTextOffsetYSlider:SetValueStep(1)
        controls.countTextOffsetYSlider:SetObeyStepOnDrag(true)
        controls.countTextOffsetYSlider.Low:SetText("")
        controls.countTextOffsetYSlider.High:SetText("")
        controls.countTextOffsetYSlider.Text:SetText("")
        controls.countTextOffsetYSlider:Hide()
        
        controls.countTextOffsetYValue = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        controls.countTextOffsetYValue:SetPoint("LEFT", controls.countTextOffsetYSlider, "RIGHT", 5, 0)
        controls.countTextOffsetYValue:SetTextColor(1, 1, 1)
        controls.countTextOffsetYValue:Hide()
        
        local function ShowControls(show)
            noSelectionLabel:SetShown(not show)
            for _, ctrl in pairs(controls) do
                if ctrl.SetShown then ctrl:SetShown(show)
                elseif ctrl.Show then
                    if show then ctrl:Show() else ctrl:Hide() end
                end
            end
        end
        
        local function UpdateStateButtons()
            if currentState == "active" then
                controls.activeBtn:SetNormalFontObject("GameFontHighlight")
                controls.inactiveBtn:SetNormalFontObject("GameFontNormal")
                controls.showLabel:SetText("Show when Ready")
            else
                controls.activeBtn:SetNormalFontObject("GameFontNormal")
                controls.inactiveBtn:SetNormalFontObject("GameFontHighlight")
                controls.showLabel:SetText("Show when On Cooldown")
            end
        end
        
        local function UpdateCustomAspectVisibility(aspectRatio)
            local showCustom = (aspectRatio == "custom")
            controls.customLabel:SetShown(showCustom)
            controls.customW:SetShown(showCustom)
            controls.customSep:SetShown(showCustom)
            controls.customH:SetShown(showCustom)
        end
        
        local function UpdateControlsForSlot(slotIndex)
            if not slotIndex or not CooldownHighlights then
                ShowControls(false)
                return
            end
            
            ShowControls(true)
            UpdateStateButtons()
            
            -- Get slot info for icon preview - use same order as list (sorted by listIndex)
            local icons = {}
            if customTrackerIcons then
                for _, iconFrame in pairs(customTrackerIcons) do
                    if iconFrame and iconFrame:IsShown() then
                        icons[#icons + 1] = iconFrame
                    end
                end
            end
            table.sort(icons, function(a, b)
                return (a.listIndex or 0) < (b.listIndex or 0)
            end)
            
            local icon = icons[slotIndex]
            if icon and icon.icon then
                pcall(function()
                    controls.iconPreview:SetTexture(icon.icon:GetTexture())
                end)
            end
            
            controls.header:SetText("Slot #" .. slotIndex)
            
            local isEnabled = CooldownHighlights:IsEnabled(customTrackerKey, slotIndex)
            local showState = CooldownHighlights:GetShowState(customTrackerKey, slotIndex, currentState)
            local size = CooldownHighlights:GetSize(customTrackerKey, slotIndex, currentState)
            local opacity = CooldownHighlights:GetOpacity(customTrackerKey, slotIndex, currentState)
            local saturated = CooldownHighlights:GetSaturation(customTrackerKey, slotIndex, currentState)
            local aspectRatio = CooldownHighlights:GetAspectRatio(customTrackerKey, slotIndex, currentState)
            local customW, customH = CooldownHighlights:GetCustomAspectRatio(customTrackerKey, slotIndex, currentState)
            
            -- Clear slider scripts BEFORE setting values to prevent old callbacks from firing
            controls.sizeSlider:SetScript("OnValueChanged", nil)
            controls.opacitySlider:SetScript("OnValueChanged", nil)
            controls.labelSizeSlider:SetScript("OnValueChanged", nil)
            controls.labelOffsetXSlider:SetScript("OnValueChanged", nil)
            controls.labelOffsetYSlider:SetScript("OnValueChanged", nil)
            controls.cooldownTextSlider:SetScript("OnValueChanged", nil)
            controls.cooldownTextOffsetXSlider:SetScript("OnValueChanged", nil)
            controls.cooldownTextOffsetYSlider:SetScript("OnValueChanged", nil)
            controls.countTextSlider:SetScript("OnValueChanged", nil)
            controls.countTextOffsetXSlider:SetScript("OnValueChanged", nil)
            controls.countTextOffsetYSlider:SetScript("OnValueChanged", nil)
            
            controls.enableCheck:SetChecked(isEnabled)
            controls.hideCheck:SetChecked(CooldownHighlights:IsIconHidden(customTrackerKey, slotIndex))
            controls.showCheck:SetChecked(showState)
            controls.sizeSlider:SetValue(size)
            controls.sizeValue:SetText(tostring(size))
            controls.opacitySlider:SetValue(opacity)
            controls.opacityValue:SetText(math.floor(opacity * 100) .. "%")
            controls.desatCheck:SetChecked(not saturated)
            controls.customW:SetText(tostring(customW))
            controls.customH:SetText(tostring(customH))
            
            -- Per-icon text settings (state-independent)
            local cdTextScale = CooldownHighlights:GetCooldownTextScale(customTrackerKey, slotIndex)
            local cdTextColor = CooldownHighlights:GetCooldownTextColor(customTrackerKey, slotIndex)
            local cdTextOffsetX = CooldownHighlights:GetCooldownTextOffsetX(customTrackerKey, slotIndex)
            local cdTextOffsetY = CooldownHighlights:GetCooldownTextOffsetY(customTrackerKey, slotIndex)
            
            controls.cooldownTextSlider:SetValue(cdTextScale or 1.0)
            controls.cooldownTextValue:SetText(string.format("%.1f", cdTextScale or 1.0))
            controls.cooldownTextColorBtn:SetBackdropColor(cdTextColor[1] or 1, cdTextColor[2] or 1, cdTextColor[3] or 1, 1)
            controls.cooldownTextOffsetXSlider:SetValue(cdTextOffsetX or 0)
            controls.cooldownTextOffsetXValue:SetText(tostring(cdTextOffsetX or 0))
            controls.cooldownTextOffsetYSlider:SetValue(cdTextOffsetY or 0)
            controls.cooldownTextOffsetYValue:SetText(tostring(cdTextOffsetY or 0))
            
            local cntTextScale = CooldownHighlights:GetCountTextScale(customTrackerKey, slotIndex)
            local cntTextColor = CooldownHighlights:GetCountTextColor(customTrackerKey, slotIndex)
            local cntTextOffsetX = CooldownHighlights:GetCountTextOffsetX(customTrackerKey, slotIndex)
            local cntTextOffsetY = CooldownHighlights:GetCountTextOffsetY(customTrackerKey, slotIndex)
            
            controls.countTextSlider:SetValue(cntTextScale or 1.0)
            controls.countTextValue:SetText(string.format("%.1f", cntTextScale or 1.0))
            controls.countTextColorBtn:SetBackdropColor(cntTextColor[1] or 1, cntTextColor[2] or 1, cntTextColor[3] or 1, 1)
            controls.countTextOffsetXSlider:SetValue(cntTextOffsetX or 0)
            controls.countTextOffsetXValue:SetText(tostring(cntTextOffsetX or 0))
            controls.countTextOffsetYSlider:SetValue(cntTextOffsetY or 0)
            controls.countTextOffsetYValue:SetText(tostring(cntTextOffsetY or 0))
            
            -- Label settings (state-independent)
            local labelEnabled = CooldownHighlights:GetLabelEnabled(customTrackerKey, slotIndex)
            local labelText = CooldownHighlights:GetLabelText(customTrackerKey, slotIndex)
            local labelSize = CooldownHighlights:GetLabelFontSize(customTrackerKey, slotIndex)
            local labelColor = CooldownHighlights:GetLabelColor(customTrackerKey, slotIndex)
            local labelOffsetX = CooldownHighlights:GetLabelOffsetX(customTrackerKey, slotIndex)
            local labelOffsetY = CooldownHighlights:GetLabelOffsetY(customTrackerKey, slotIndex)
            
            controls.labelEnableCheck:SetChecked(labelEnabled)
            controls.labelTextBox:SetText(labelText or "")
            controls.labelSizeSlider:SetValue(labelSize or 14)
            controls.labelSizeValue:SetText(tostring(labelSize or 14))
            controls.labelColorBtn:SetBackdropColor(labelColor[1] or 1, labelColor[2] or 1, labelColor[3] or 1, labelColor[4] or 1)
            controls.labelOffsetXSlider:SetValue(labelOffsetX or 0)
            controls.labelOffsetXValue:SetText(tostring(labelOffsetX or 0))
            controls.labelOffsetYSlider:SetValue(labelOffsetY or 0)
            controls.labelOffsetYValue:SetText(tostring(labelOffsetY or 0))
            
            UIDropDownMenu_Initialize(controls.aspectDropdown, function(self, level)
                for _, opt in ipairs(ASPECT_OPTIONS) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = opt.label
                    info.value = opt.value
                    info.func = function(self)
                        CooldownHighlights:SetAspectRatio(customTrackerKey, slotIndex, currentState, self.value)
                        UIDropDownMenu_SetText(controls.aspectDropdown, self:GetText())
                        UpdateCustomAspectVisibility(self.value)
                    end
                    info.checked = (aspectRatio == opt.value)
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            
            for _, opt in ipairs(ASPECT_OPTIONS) do
                if opt.value == aspectRatio then
                    UIDropDownMenu_SetText(controls.aspectDropdown, opt.label)
                    break
                end
            end
            
            UpdateCustomAspectVisibility(aspectRatio)
            
            -- Initialize dock dropdown
            local currentDock = CooldownHighlights:GetDockAssignment(customTrackerKey, slotIndex) or 0
            UIDropDownMenu_Initialize(controls.dockDropdown, function(self, level)
                -- None option
                local info = UIDropDownMenu_CreateInfo()
                info.text = "None"
                info.value = 0
                info.func = function()
                    CooldownHighlights:SetDockAssignment(customTrackerKey, slotIndex, nil)
                    UIDropDownMenu_SetText(controls.dockDropdown, "None")
                end
                info.checked = (currentDock == 0 or currentDock == nil)
                UIDropDownMenu_AddButton(info, level)
                
                -- Dock options (1-4)
                local numDocks = TUICD.Docks and TUICD.Docks:GetDockCount() or 4
                for i = 1, numDocks do
                    local dockName = TUICD.Docks and TUICD.Docks:GetDockName(i) or ("Dock " .. i)
                    local dockSettings = TUICD.Docks and TUICD.Docks:GetDockSettings(i) or {}
                    
                    info = UIDropDownMenu_CreateInfo()
                    if dockSettings.enabled then
                        info.text = "|cff00ff00" .. dockName .. "|r"
                    else
                        info.text = "|cff888888" .. dockName .. " (disabled)|r"
                    end
                    info.value = i
                    info.func = function()
                        CooldownHighlights:SetDockAssignment(customTrackerKey, slotIndex, i)
                        UIDropDownMenu_SetText(controls.dockDropdown, dockName)
                    end
                    info.checked = (currentDock == i)
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            
            -- Set dock dropdown text
            if currentDock and currentDock > 0 then
                local dockName = TUICD.Docks and TUICD.Docks:GetDockName(currentDock) or ("Dock " .. currentDock)
                UIDropDownMenu_SetText(controls.dockDropdown, dockName)
            else
                UIDropDownMenu_SetText(controls.dockDropdown, "None")
            end
            
            controls.enableCheck:SetScript("OnClick", function(self)
                CooldownHighlights:EnableHighlight(customTrackerKey, slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.activeBtn:SetScript("OnClick", function()
                currentState = "active"
                UpdateControlsForSlot(slotIndex)
            end)
            
            controls.inactiveBtn:SetScript("OnClick", function()
                currentState = "inactive"
                UpdateControlsForSlot(slotIndex)
            end)
            
            controls.showCheck:SetScript("OnClick", function(self)
                CooldownHighlights:SetShowState(customTrackerKey, slotIndex, currentState, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.sizeSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.sizeValue:SetText(tostring(value))
                CooldownHighlights:SetSize(customTrackerKey, slotIndex, currentState, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.opacitySlider:SetScript("OnValueChanged", function(self, value)
                controls.opacityValue:SetText(math.floor(value * 100) .. "%")
                CooldownHighlights:SetOpacity(customTrackerKey, slotIndex, currentState, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.desatCheck:SetScript("OnClick", function(self)
                CooldownHighlights:SetSaturation(customTrackerKey, slotIndex, currentState, not self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            local function ApplyCustomAspect()
                local w = tonumber(controls.customW:GetText()) or 1
                local h = tonumber(controls.customH:GetText()) or 1
                if w < 1 then w = 1 end
                if h < 1 then h = 1 end
                CooldownHighlights:SetCustomAspectRatio(customTrackerKey, slotIndex, currentState, w, h)
            end
            
            controls.customW:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                ApplyCustomAspect()
            end)
            controls.customW:SetScript("OnEditFocusLost", ApplyCustomAspect)
            
            controls.customH:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                ApplyCustomAspect()
            end)
            controls.customH:SetScript("OnEditFocusLost", ApplyCustomAspect)
            
            -- Label control event handlers
            controls.labelEnableCheck:SetScript("OnClick", function(self)
                CooldownHighlights:SetLabelEnabled(customTrackerKey, slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
            end)
            
            controls.labelTextBox:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                CooldownHighlights:SetLabelText(customTrackerKey, slotIndex, self:GetText())
                Cooldowns:SaveSettings()
            end)
            controls.labelTextBox:SetScript("OnEditFocusLost", function(self)
                CooldownHighlights:SetLabelText(customTrackerKey, slotIndex, self:GetText())
                Cooldowns:SaveSettings()
            end)
            
            controls.labelSizeSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.labelSizeValue:SetText(tostring(value))
                CooldownHighlights:SetLabelFontSize(customTrackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.labelColorBtn:SetScript("OnClick", function()
                local currentColor = CooldownHighlights:GetLabelColor(customTrackerKey, slotIndex)
                local r, g, b, a = currentColor[1] or 1, currentColor[2] or 1, currentColor[3] or 1, currentColor[4] or 1
                
                local info = {
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        local na = ColorPickerFrame:GetColorAlpha() or 1
                        controls.labelColorBtn:SetBackdropColor(nr, ng, nb, na)
                        CooldownHighlights:SetLabelColor(customTrackerKey, slotIndex, {nr, ng, nb, na})
                        Cooldowns:SaveSettings()
                    end,
                    opacityFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        local na = ColorPickerFrame:GetColorAlpha() or 1
                        controls.labelColorBtn:SetBackdropColor(nr, ng, nb, na)
                        CooldownHighlights:SetLabelColor(customTrackerKey, slotIndex, {nr, ng, nb, na})
                        Cooldowns:SaveSettings()
                    end,
                    cancelFunc = function(prev)
                        controls.labelColorBtn:SetBackdropColor(prev.r, prev.g, prev.b, prev.a or 1)
                        CooldownHighlights:SetLabelColor(customTrackerKey, slotIndex, {prev.r, prev.g, prev.b, prev.a or 1})
                        Cooldowns:SaveSettings()
                    end,
                    hasOpacity = true,
                    opacity = a,
                    r = r,
                    g = g,
                    b = b,
                }
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            
            controls.labelOffsetXSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.labelOffsetXValue:SetText(tostring(value))
                CooldownHighlights:SetLabelOffsetX(customTrackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.labelOffsetYSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.labelOffsetYValue:SetText(tostring(value))
                CooldownHighlights:SetLabelOffsetY(customTrackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            -- Hide icon checkbox handler
            controls.hideCheck:SetScript("OnClick", function(self)
                CooldownHighlights:SetIconHidden(customTrackerKey, slotIndex, self:GetChecked())
                Cooldowns:SaveSettings()
                -- Refresh the custom tracker layout
                if LayoutCustomTrackerIcons then
                    LayoutCustomTrackerIcons()
                end
            end)
            
            -- Cooldown text control handlers
            controls.cooldownTextSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value * 10) / 10
                controls.cooldownTextValue:SetText(string.format("%.1f", value))
                CooldownHighlights:SetCooldownTextScale(customTrackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.cooldownTextColorBtn:SetScript("OnClick", function()
                local currentColor = CooldownHighlights:GetCooldownTextColor(customTrackerKey, slotIndex)
                local r, g, b = currentColor[1] or 1, currentColor[2] or 1, currentColor[3] or 1
                
                local info = {
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        controls.cooldownTextColorBtn:SetBackdropColor(nr, ng, nb, 1)
                        CooldownHighlights:SetCooldownTextColor(customTrackerKey, slotIndex, {nr, ng, nb})
                        Cooldowns:SaveSettings()
                    end,
                    cancelFunc = function(prev)
                        controls.cooldownTextColorBtn:SetBackdropColor(prev.r, prev.g, prev.b, 1)
                        CooldownHighlights:SetCooldownTextColor(customTrackerKey, slotIndex, {prev.r, prev.g, prev.b})
                        Cooldowns:SaveSettings()
                    end,
                    hasOpacity = false,
                    r = r,
                    g = g,
                    b = b,
                }
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            
            controls.cooldownTextOffsetXSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.cooldownTextOffsetXValue:SetText(tostring(value))
                CooldownHighlights:SetCooldownTextOffsetX(customTrackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.cooldownTextOffsetYSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.cooldownTextOffsetYValue:SetText(tostring(value))
                CooldownHighlights:SetCooldownTextOffsetY(customTrackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            -- Count text control handlers
            controls.countTextSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value * 10) / 10
                controls.countTextValue:SetText(string.format("%.1f", value))
                CooldownHighlights:SetCountTextScale(customTrackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.countTextColorBtn:SetScript("OnClick", function()
                local currentColor = CooldownHighlights:GetCountTextColor(customTrackerKey, slotIndex)
                local r, g, b = currentColor[1] or 1, currentColor[2] or 1, currentColor[3] or 1
                
                local info = {
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        controls.countTextColorBtn:SetBackdropColor(nr, ng, nb, 1)
                        CooldownHighlights:SetCountTextColor(customTrackerKey, slotIndex, {nr, ng, nb})
                        Cooldowns:SaveSettings()
                    end,
                    cancelFunc = function(prev)
                        controls.countTextColorBtn:SetBackdropColor(prev.r, prev.g, prev.b, 1)
                        CooldownHighlights:SetCountTextColor(customTrackerKey, slotIndex, {prev.r, prev.g, prev.b})
                        Cooldowns:SaveSettings()
                    end,
                    hasOpacity = false,
                    r = r,
                    g = g,
                    b = b,
                }
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)
            
            controls.countTextOffsetXSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.countTextOffsetXValue:SetText(tostring(value))
                CooldownHighlights:SetCountTextOffsetX(customTrackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
            
            controls.countTextOffsetYSlider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value)
                controls.countTextOffsetYValue:SetText(tostring(value))
                CooldownHighlights:SetCountTextOffsetY(customTrackerKey, slotIndex, value)
                Cooldowns:SaveSettings()
            end)
        end
        
        local function RefreshSlotList()
            for _, row in ipairs(slotRows) do
                row:Hide()
                row:SetParent(nil)
            end
            wipe(slotRows)
            
            local viewer = _G["TweaksUI_CustomTrackerFrame"]
            if not viewer then
                local noItems = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noItems:SetPoint("CENTER")
                noItems:SetText("Custom Trackers not loaded")
                noItems:SetTextColor(0.5, 0.5, 0.5)
                slotRows[1] = noItems
                scrollChild:SetHeight(90)
                ShowControls(false)
                return
            end
            
            local icons = {}
            if customTrackerIcons then
                for _, iconFrame in pairs(customTrackerIcons) do
                    -- Include all icons, not just shown ones (so list works when tracker hidden)
                    if iconFrame then
                        icons[#icons + 1] = iconFrame
                    end
                end
            end
            
            if #icons == 0 then
                local noItems = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noItems:SetPoint("CENTER")
                noItems:SetText("No custom trackers configured")
                noItems:SetTextColor(0.5, 0.5, 0.5)
                slotRows[1] = noItems
                scrollChild:SetHeight(90)
                ShowControls(false)
                return
            end
            
            -- Sort by listIndex to match layout order
            table.sort(icons, function(a, b)
                return (a.listIndex or 0) < (b.listIndex or 0)
            end)
            
            local rowY = -3
            local rowHeight = 21
            
            for slotIndex = 1, #icons do
                local icon = icons[slotIndex]
                if icon then
                    local row = CreateFrame("Button", nil, scrollChild)
                    row:SetPoint("TOPLEFT", 3, rowY)
                    row:SetPoint("TOPRIGHT", -3, rowY)
                    row:SetHeight(rowHeight - 2)
                    
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
                    
                    local slotLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    slotLabel:SetPoint("LEFT", 4, 0)
                    slotLabel:SetText("#" .. slotIndex)
                    slotLabel:SetTextColor(0.8, 0.8, 0.8)
                    
                    local iconPreview = row:CreateTexture(nil, "ARTWORK")
                    iconPreview:SetPoint("LEFT", 22, 0)
                    iconPreview:SetSize(18, 18)
                    iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    if icon.icon then
                        pcall(function() iconPreview:SetTexture(icon.icon:GetTexture()) end)
                    end
                    
                    local isEnabled = CooldownHighlights and CooldownHighlights:IsEnabled(customTrackerKey, slotIndex)
                    local enabledIndicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    enabledIndicator:SetPoint("LEFT", 45, 0)
                    enabledIndicator:SetText(isEnabled and "|cff00ff00On|r" or "|cff666666Off|r")
                    
                    row.slotIndex = slotIndex
                    row:SetScript("OnClick", function(self)
                        selectedSlot = self.slotIndex
                        for _, r in ipairs(slotRows) do
                            if r.bg then r.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3) end
                        end
                        self.bg:SetColorTexture(0.3, 0.5, 0.3, 0.6)
                        currentState = "active"
                        UpdateControlsForSlot(self.slotIndex)
                    end)
                    
                    row:SetScript("OnEnter", function(self)
                        if selectedSlot ~= self.slotIndex then
                            self.bg:SetColorTexture(0.25, 0.25, 0.3, 0.5)
                        end
                    end)
                    
                    row:SetScript("OnLeave", function(self)
                        if selectedSlot ~= self.slotIndex then
                            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
                        end
                    end)
                    
                    slotRows[#slotRows + 1] = row
                    rowY = rowY - rowHeight
                end
            end
            
            
            -- Update scroll child height based on content
            local totalHeight = math.max(90, #slotRows * rowHeight + 6)
            scrollChild:SetHeight(totalHeight)
            if not selectedSlot and #slotRows > 0 and slotRows[1].slotIndex then
                slotRows[1]:Click()
            end
        end
        
        C_Timer.After(0.1, RefreshSlotList)
        
        -- Set the refresh button script (button created at top of tab)
        refreshBtn:SetScript("OnClick", function()
            selectedSlot = nil
            RefreshSlotList()
        end)
        
        parent:SetHeight(math.abs(y) + 370)
    end
    
    -- Build tab content builders
    local tabBuilders = {
        entries = BuildEntriesTab,
        layout = BuildLayoutTab,
        appearance = BuildAppearanceTab,
        text = BuildTextTab,
        visibility = BuildVisibilityTab,
        pericon = BuildPerIconTab,
    }
    
    -- Create content frames and tab buttons
    local tabWidth = (PANEL_WIDTH - 20) / #tabs
    
    for i, tab in ipairs(tabs) do
        -- Create content frame
        local content = CreateTabContent()
        contentFrames[tab.key] = content
        
        -- Build content
        if tabBuilders[tab.key] then
            tabBuilders[tab.key](content.scrollChild)
        end
        
        -- Create tab button
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
            -- Hide all content
            for _, cf in pairs(contentFrames) do
                cf:Hide()
            end
            -- Show selected
            contentFrames[tab.key]:Show()
            -- Update button visuals
            for _, btn in ipairs(tabButtons) do
                btn.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                btn.text:SetTextColor(0.7, 0.7, 0.7)
            end
            tabBtn.bg:SetColorTexture(0.3, 0.3, 0.5, 1)
            tabBtn.text:SetTextColor(1, 1, 1)
            currentTab = i
            
            -- Refresh entries tab when shown
            if tab.key == "entries" then
                if panel.RefreshEquipmentList then panel:RefreshEquipmentList() end
                if panel.RefreshCustomEntriesList then panel:RefreshCustomEntriesList() end
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
    
    -- Show first tab
    if tabButtons[1] then
        tabButtons[1]:Click()
    end
    
    -- Initial refresh
    C_Timer.After(0.1, function()
        if panel.RefreshEquippedItemsList then panel:RefreshEquippedItemsList() end
        if panel.RefreshCustomEntriesList then panel:RefreshCustomEntriesList() end
    end)
    
    panel:Show()
end



-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

function Cooldowns:OnInitialize()
    -- Load settings from database
    local dbSettings = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
    
    -- Start with defaults
    settings = DeepCopy(DEFAULTS)
    
    -- Merge saved settings (deep copy nested tables to avoid reference sharing)
    if dbSettings then
        for key, trackerSettings in pairs(dbSettings) do
            if settings[key] and type(trackerSettings) == "table" then
                for k, v in pairs(trackerSettings) do
                    -- Migration: old "spacing" -> "spacingH" and "spacingV"
                    if k == "spacing" then
                        settings[key]["spacingH"] = v
                        settings[key]["spacingV"] = v
                    elseif type(v) == "table" then
                        -- Deep copy nested tables to avoid reference sharing between profiles
                        settings[key][k] = DeepCopy(v)
                    else
                        settings[key][k] = v
                    end
                end
            elseif key == "global" and type(trackerSettings) == "table" then
                for k, v in pairs(trackerSettings) do
                    if type(v) == "table" then
                        settings.global[k] = DeepCopy(v)
                    else
                        settings.global[k] = v
                    end
                end
            end
        end
    end
    
    -- Initialize layout update flags
    for _, tracker in ipairs(TRACKERS) do
        needsLayoutUpdate[tracker.key] = false
    end
    needsLayoutUpdate["customTrackers"] = false
    
    -- Initialize Masque support
    InitializeMasque()
    
    dprint("Cooldowns module initialized")
    if dbSettings then
        dprint("Loaded saved settings")
        -- Debug: show loaded custom tracker position
        if settings.customTrackers then
            dprint(string.format("Custom tracker position loaded: %s, %.1f, %.1f", 
                settings.customTrackers.point or "nil",
                settings.customTrackers.x or 0,
                settings.customTrackers.y or 0))
        end
    else
        dprint("No saved settings found, using defaults")
    end
end


function Cooldowns:OnEnable()
    -- AGGRESSIVE EARLY HIDING: Use OnUpdate for frame-by-frame hiding
    -- This is more aggressive than a ticker and catches the very first frame
    local hideFrame = CreateFrame("Frame")
    hideFrame.elapsed = 0
    hideFrame:SetScript("OnUpdate", function(self, elapsed)
        local TUIFrame = TUICD.TUIFrame
        if TUIFrame and TUIFrame.IsInitializationComplete and TUIFrame.IsInitializationComplete() then
            -- Init complete, stop hiding
            self:SetScript("OnUpdate", nil)
            return
        end
        
        -- Hide all Blizzard viewers every single frame
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer and viewer:GetAlpha() > 0 then
                viewer:SetAlpha(0)
            end
        end
        
        -- Safety timeout after 5 seconds
        self.elapsed = self.elapsed + elapsed
        if self.elapsed > 5.0 then
            self:SetScript("OnUpdate", nil)
        end
    end)
    
    -- Register events
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Combat start
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")     -- Party/raid changes
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")   -- Instance changes
    eventFrame:RegisterEvent("UNIT_AURA")               -- Buff changes (for activity)
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")   -- Target changes
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")  -- Mount changes
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")  -- Druid travel form
    eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")  -- Edit Mode positions applied
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")  -- Gear changes for equipped items tracker
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")  -- Spec changes for per-spec entries
    
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:SetScript("OnUpdate", OnUpdate)
    
    -- NOTE: We intentionally do NOT hook Blizzard's EditModeManagerFrame
    -- TUICD elements should be positioned via TUI's Layout Mode (/tui layout), not Blizzard Edit Mode
    -- Hooking EditModeManagerFrame causes taint issues with Blizzard's protected frames
    
    -- Hook TUI Layout mode for tracker visibility
    if TUICD.Layout then
        TUICD.Layout:RegisterCallback("OnLayoutModeEnter", function()
            dprint("TUI Layout Mode opened")
            
            -- Force show all trackers for Layout positioning
            for _, tracker in ipairs(TRACKERS) do
                local viewer = _G[tracker.name]
                if viewer then
                    -- Fix potential duplicate layoutIndex before showing (Blizzard CDM stale icon bug)
                    pcall(function()
                        local children = {viewer:GetChildren()}
                        local seenIndices = {}
                        local hasDuplicates = false
                        
                        for _, child in ipairs(children) do
                            if child.layoutIndex then
                                if seenIndices[child.layoutIndex] then
                                    hasDuplicates = true
                                    break
                                end
                                seenIndices[child.layoutIndex] = true
                            end
                        end
                        
                        if hasDuplicates then
                            local iconsWithIndex = {}
                            for _, child in ipairs(children) do
                                if child.layoutIndex then
                                    table.insert(iconsWithIndex, child)
                                end
                            end
                            table.sort(iconsWithIndex, function(a, b)
                                return (a.layoutIndex or 0) < (b.layoutIndex or 0)
                            end)
                            for i, icon in ipairs(iconsWithIndex) do
                                icon.layoutIndex = i
                            end
                            dprint("Fixed duplicate layoutIndex for " .. tracker.key .. " in Layout Mode")
                        end
                    end)
                    
                    -- Wrap in pcall to handle Midnight secret value errors
                    pcall(function()
                        viewer:Show()
                        viewer:SetAlpha(1.0)
                    end)
                    ApplyGridLayout(viewer, tracker.key)
                end
                
                -- Also ensure the container and wrapper are shown
                local container = _G["TweaksUI_CDContainer_" .. tracker.key]
                if container then
                    container:Show()
                    local parent = container:GetParent()
                    if parent then
                        parent:Show()
                    end
                end
            end
            
            -- Force show custom tracker
            if customTrackerFrame then
                customTrackerFrame:Show()
                for _, iconFrame in pairs(customTrackerIcons) do
                    iconFrame:EnableMouse(false)
                end
                LayoutCustomTrackerIcons()
                
                -- Also ensure wrapper is shown
                local parent = customTrackerFrame:GetParent()
                if parent then
                    parent:Show()
                end
            end
        end)
        
        TUICD.Layout:RegisterCallback("OnLayoutModeExit", function()
            dprint("TUI Layout Mode closed")
            
            -- Re-apply visibility rules
            for _, tracker in ipairs(TRACKERS) do
                UpdateTrackerVisibility(tracker.key)
            end
            
            if customTrackerFrame then
                for _, iconFrame in pairs(customTrackerIcons) do
                    iconFrame:EnableMouse(true)
                end
                UpdateCustomTrackerVisibility()
            end
        end)
    end
    
    -- Hook viewers immediately (they might already exist)
    HookAllViewers()
    
    -- Schedule additional hook attempts
    C_Timer.After(1.0, HookAllViewers)
    C_Timer.After(3.0, HookAllViewers)
    
    -- CRITICAL: Apply initial layout to all viewers (mimics PLAYER_ENTERING_WORLD handler)
    -- This is needed because that event has already fired before OnEnable runs
    C_Timer.After(0.5, function()
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer then
                ApplyGridLayout(viewer, tracker.key)
                dprint(string.format("Initial layout applied to [%s]", tracker.key))
            end
        end
    end)
    
    -- Apply clickthrough settings after viewers are hooked
    C_Timer.After(1.5, ApplyAllClickthrough)
    
    -- Start buff state tracking
    StartBuffStateTracking()
    
    -- Start visibility system
    StartVisibilitySystem()
    
    -- Initialize custom tracker system
    InitializeCustomTrackerData()
    CreateCustomTrackerFrame()
    StartCustomTrackerUpdates()
    
    -- Delay custom tracker rebuild to ensure data is loaded
    C_Timer.After(1.0, RebuildCustomTrackerIcons)
    
    -- Initialize Dynamic Docks system
    if TUICD.Docks and TUICD.Docks.Initialize then
        TUICD.Docks:Initialize()
        dprint("Dynamic Docks initialized")
    end
    
    -- Initialize Docks UI
    if TUICD.DocksUI and TUICD.DocksUI.Initialize then
        TUICD.DocksUI:Initialize()
    end
    
    dprint("Cooldowns module enabled")
end

function Cooldowns:OnDisable()
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    eventFrame:SetScript("OnUpdate", nil)
    
    -- Stop buff state tracking
    StopBuffStateTracking()
    
    -- Stop visibility system
    StopVisibilitySystem()
    
    -- Stop custom tracker updates
    StopCustomTrackerUpdates()
    
    -- Hide custom tracker frame
    if customTrackerFrame then
        customTrackerFrame:Hide()
    end
    
    -- Disable CooldownContainers (hides container frames)
    if TUICD.CooldownContainers then
        TUICD.CooldownContainers:Disable()
    end
    
    if cooldownHub then
        cooldownHub:Hide()
    end
    self:HideAllPanels()
    
    dprint("Cooldowns module disabled")
end

-- Handle profile changes
function Cooldowns:OnProfileChanged(profileName)
    dprint("OnProfileChanged:", profileName)
    
    -- Invalidate settings cache
    settings = nil
    
    -- CRITICAL: Clear the icon order cache so new profile's order is used
    -- This is a local variable that persists across profile switches
    iconOrderCache = {}
    
    -- Reload settings from new profile
    self:GetSettings()
    
    -- If module is enabled, refresh everything
    if self.enabled then
        -- Re-apply layouts to all Blizzard trackers
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer then
                ApplyGridLayout(viewer, tracker.key)
                UpdateTrackerVisibility(tracker.key)
            end
        end
        
        -- Apply clickthrough settings from new profile
        ApplyAllClickthrough()
        
        -- Rebuild custom tracker icons for new settings
        if customTrackerFrame then
            InitializeCustomTrackerData()
            RebuildCustomTrackerIcons()
            UpdateCustomTrackerVisibility()
        end
        
        dprint("Profile change applied to Cooldowns module")
    end
end

-- Save settings on logout
local saveFrame = CreateFrame("Frame")
saveFrame:RegisterEvent("PLAYER_LOGOUT")
saveFrame:SetScript("OnEvent", function()
    if settings then
        TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, settings)
    end
end)

-- ============================================================================
-- LAYOUT INTEGRATION
-- ============================================================================

-- ============================================================================
-- LAYOUT INTEGRATION
-- Delegate to CooldownContainers module which has proper container sizing
-- ============================================================================

local function RegisterCooldownsWithLayout()
    -- Use CooldownContainers module for Layout integration
    -- It creates properly-sized containers that we can move
    if TUICD.CooldownContainers then
        if not TUICD.CooldownContainers:IsEnabled() then
            TUICD.CooldownContainers:Enable()
        else
            -- Already enabled, just register with Layout
            TUICD.CooldownContainers:RegisterWithLayout()
        end
        dprint("Cooldowns: Using CooldownContainers for Layout integration")
    else
        dprint("Cooldowns: CooldownContainers not available, skipping Layout integration")
    end
end

-- Register with Layout after CooldownContainers is fully initialized and enabled
-- CooldownContainers: initializes at 3s, enables at 4s, registers Layout at 4.3s
-- We wait until 5s to ensure everything is ready
-- Only register if Cooldowns module is enabled
C_Timer.After(5, function()
    if TUICD.Database and TUICD.Database:IsModuleEnabled(TUICD.MODULE_IDS.COOLDOWNS) then
        RegisterCooldownsWithLayout()
    end
end)

-- Debug slash command
-- SLASH_TUICD1 = "/tuicd" -- Removed: handled by Main.lua
-- SlashCmdList["TUICD"] = function -- Removed: handled by Main.lua
local function OldSlashHandler(msg)
    msg = msg:lower():trim()
    
    if msg == "debug" then
        -- Toggle debug mode
        if settings and settings.global then
            settings.global.debugMode = not settings.global.debugMode
            print("|cff00ff00[TUICD CD]|r Debug mode:", settings.global.debugMode and "ON" or "OFF")
        end
    
    elseif msg == "custom" then
        -- Debug custom tracker position specifically
        print("|cff00ff00[TUICD CD]|r Custom Tracker Debug:")
        print("  Settings exists:", settings and "YES" or "NO")
        if settings then
            print("  customTrackers table:", settings.customTrackers and "YES" or "NO")
            if settings.customTrackers then
                print("  Enabled:", settings.customTrackers.enabled and "YES" or "NO")
                print("  Saved point:", tostring(settings.customTrackers.point))
                print("  Saved x:", tostring(settings.customTrackers.x))
                print("  Saved y:", tostring(settings.customTrackers.y))
            end
        end
        print("  Frame exists:", customTrackerFrame and "YES" or "NO")
        if customTrackerFrame then
            local point, relativeTo, relPoint, x, y = customTrackerFrame:GetPoint(1)
            print("  Current position:", point, x, y)
            print("  Frame shown:", customTrackerFrame:IsShown() and "YES" or "NO")
        end
        print("  TUICD.EditMode:", TUICD.EditMode and "YES" or "NO")
        
    elseif msg == "dump" then
        -- Dump icon structure
        print("|cff00ff00[TUICD CD]|r Dumping icon structures...")
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer and viewer:IsShown() then
                print("  " .. tracker.key .. ":")
                local icons = CollectIcons(viewer)
                for i, icon in ipairs(icons) do
                    if i <= 2 and icon:IsShown() then  -- Only first 2 shown icons
                        local name = icon:GetName() or "unnamed"
                        print("    Icon " .. i .. ": " .. name)
                        -- Check for fields
                        local fields = {}
                        if icon.Border then table.insert(fields, "Border") end
                        if icon.border then table.insert(fields, "border") end
                        if icon.IconBorder then table.insert(fields, "IconBorder") end
                        if icon.Icon then table.insert(fields, "Icon") end
                        if icon.icon then table.insert(fields, "icon") end
                        if icon.Cooldown then table.insert(fields, "Cooldown") end
                        if icon.cooldown then table.insert(fields, "cooldown") end
                        if icon.Count then table.insert(fields, "Count") end
                        if icon.count then table.insert(fields, "count") end
                        if icon.GetNormalTexture and icon:GetNormalTexture() then table.insert(fields, "NormalTexture") end
                        print("      Fields: " .. table.concat(fields, ", "))
                        
                        -- Check regions for FontStrings
                        if icon.GetRegions then
                            local fontStrings = {}
                            for _, region in ipairs({icon:GetRegions()}) do
                                if region:GetObjectType() == "FontString" then
                                    local fsName = region:GetName() or "unnamed"
                                    local fsText = region:GetText() or ""
                                    table.insert(fontStrings, fsName .. "='" .. fsText .. "'")
                                end
                            end
                            if #fontStrings > 0 then
                                print("      FontStrings: " .. table.concat(fontStrings, ", "))
                            end
                        end
                        
                        -- Check children
                        if icon.GetChildren then
                            for _, child in ipairs({icon:GetChildren()}) do
                                local childName = child:GetName() or child:GetObjectType()
                                print("      Child: " .. childName)
                                
                                -- Check child for FontStrings
                                if child.GetRegions then
                                    for _, region in ipairs({child:GetRegions()}) do
                                        if region:GetObjectType() == "FontString" then
                                            local fsName = region:GetName() or "unnamed"
                                            local fsText = region:GetText() or ""
                                            print("        FontString: " .. fsName .. " = '" .. fsText .. "'")
                                        end
                                    end
                                end
                                
                                -- Check grandchildren
                                if child.GetChildren then
                                    for _, grandchild in ipairs({child:GetChildren()}) do
                                        local gcName = grandchild:GetName() or grandchild:GetObjectType()
                                        if grandchild.GetRegions then
                                            for _, region in ipairs({grandchild:GetRegions()}) do
                                                if region:GetObjectType() == "FontString" then
                                                    local fsName = region:GetName() or "unnamed"
                                                    local fsText = region:GetText() or ""
                                                    print("          " .. gcName .. " FontString: " .. fsName .. " = '" .. fsText .. "'")
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
    elseif msg == "test" then
        -- Test settings persistence
        print("|cff00ff00[TUICD CD]|r Testing settings...")
        print("  settings table exists:", settings ~= nil)
        if settings then
            print("  settings.essential:", settings.essential ~= nil)
            if settings.essential then
                print("    iconSize:", settings.essential.iconSize)
                print("    columns:", settings.essential.columns)
            end
        end
        -- Check database
        local dbSettings = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
        print("  DB settings exists:", dbSettings ~= nil)
        if dbSettings and dbSettings.essential then
            print("    DB iconSize:", dbSettings.essential.iconSize)
        end
        
    elseif msg == "reset" then
        -- Clear saved order and recapture all trackers
        print("|cff00ff00[TUICD CD]|r Clearing saved icon order and recapturing...")
        ClearIconOrderCache(nil, true)  -- Clear all including persistent
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            if viewer and viewer:IsShown() then
                ApplyGridLayout(viewer, tracker.key)
            end
        end
        print("|cff00ff00[TUICD CD]|r Reset complete. Icon order saved from current positions.")
    
    elseif msg == "resetbuffs" then
        -- Clear saved order for just buffs tracker
        print("|cff00ff00[TUICD CD]|r Clearing buffs icon order and recapturing...")
        ClearIconOrderCache("buffs", true)  -- Clear including persistent
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer and viewer:IsShown() then
            ApplyGridLayout(viewer, "buffs")
            print("|cff00ff00[TUICD CD]|r Buffs tracker reset complete.")
        else
            print("|cff00ff00[TUICD CD]|r Buffs tracker not visible - show it first.")
        end
    
    elseif msg == "order" then
        -- Show current saved order for all trackers
        print("|cff00ff00[TUICD CD]|r Saved icon order:")
        for _, tracker in ipairs(TRACKERS) do
            local savedOrder = GetSetting(tracker.key, "savedIconOrder")
            if savedOrder and #savedOrder > 0 then
                print(string.format("  [%s]: %d icons - %s", tracker.key, #savedOrder, table.concat(savedOrder, ", ")))
            else
                print(string.format("  [%s]: (no saved order)", tracker.key))
            end
        end
        
    elseif msg == "cache" then
        -- Show current session cache order for all trackers
        print("|cff00ff00[TUICD CD]|r Session cache order:")
        for _, tracker in ipairs(TRACKERS) do
            local cached = iconOrderCache[tracker.key]
            if cached and #cached > 0 then
                local ids = {}
                for i, icon in ipairs(cached) do
                    ids[i] = GetIconTextureID(icon)
                end
                print(string.format("  [%s]: %d icons - %s", tracker.key, #cached, table.concat(ids, ", ")))
            else
                print(string.format("  [%s]: (no cache)", tracker.key))
            end
        end
        
    elseif msg == "resete" or msg == "resetessential" then
        -- Clear saved order for essential tracker and recapture
        print("|cff00ff00[TUICD CD]|r Clearing essential icon order and recapturing...")
        ClearIconOrderCache("essential", true)
        local viewer = _G["EssentialCooldownViewer"]
        if viewer and viewer:IsShown() then
            ApplyGridLayout(viewer, "essential")
            print("|cff00ff00[TUICD CD]|r Essential tracker reset complete.")
        else
            print("|cff00ff00[TUICD CD]|r Essential tracker not visible - show it first.")
        end
        
    elseif msg == "custom" then
        -- Rebuild custom trackers
        print("|cff00ff00[TUICD CD]|r Rebuilding custom trackers...")
        RebuildCustomTrackerIcons()
        print("|cff00ff00[TUICD CD]|r Custom trackers rebuilt.")
        
    elseif msg == "equipped" then
        -- Show equipped on-use items
        print("|cff00ff00[TUICD CD]|r Scanning equipped on-use items...")
        local items = ScanEquippedOnUseItems()
        local count = 0
        for slotID, info in pairs(items) do
            count = count + 1
            print(string.format("  Slot %d (%s): %s", slotID, info.slotName, info.itemName or "Loading..."))
        end
        if count == 0 then
            print("  No equipped items with on-use abilities found.")
        end
        
    elseif msg == "sizes" then
        -- Debug icon sizes
        print("|cff00ff00[TUICD CD]|r Icon Size Debug:")
        
        for _, tracker in ipairs(TRACKERS) do
            local viewer = _G[tracker.name]
            local trackerKey = tracker.key
            
            -- Get TUI settings
            local tuiIconSize = GetSetting(trackerKey, "iconSize") or 36
            local tuiAspect = GetSetting(trackerKey, "aspectRatio") or "1:1"
            local tuiWidth = GetSetting(trackerKey, "iconWidth")
            local tuiHeight = GetSetting(trackerKey, "iconHeight")
            
            print(string.format("  |cffffcc00%s:|r", tracker.name))
            print(string.format("    TUI Settings: iconSize=%d, aspect=%s, customW=%s, customH=%s",
                tuiIconSize, tuiAspect, tostring(tuiWidth), tostring(tuiHeight)))
            
            if viewer then
                -- Get actual icon sizes
                local icons = CollectIcons(viewer)
                local shownCount = 0
                local sizeStr = ""
                for _, icon in ipairs(icons) do
                    if icon:IsShown() then
                        shownCount = shownCount + 1
                        if shownCount <= 3 then
                            local w, h = icon:GetWidth(), icon:GetHeight()
                            sizeStr = sizeStr .. string.format("%.0fx%.0f ", w, h)
                        end
                    end
                end
                print(string.format("    Actual: %d icons shown, sizes: %s", shownCount, sizeStr))
                
                -- Try to get Edit Mode setting value
                local settingID = HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_ICON_SIZE
                if settingID and viewer.GetSettingValue then
                    local emSize = pcall(function() return viewer:GetSettingValue(settingID) end)
                    print(string.format("    Edit Mode ICON_SIZE setting: %s", tostring(emSize)))
                end
            else
                print("    (viewer not found)")
            end
        end
        
    else
        print("|cff00ff00[TUICD CD]|r Commands:")
        print("  /tuicd debug - Toggle debug mode")
        print("  /tuicd dump - Dump icon structure info")
        print("  /tuicd test - Test settings persistence")
        print("  /tuicd reset - Clear and recapture ALL tracker icon order")
        print("  /tuicd resetbuffs - Clear and recapture buffs tracker order")
        print("  /tuicd order - Show saved icon order (texture fileIDs)")
        print("  /tuicd custom - Rebuild custom trackers")
        print("  /tuicd equipped - Show equipped on-use items")
        print("  /tuicd sizes - Debug icon sizes")
    end
end

-- Save settings to database
function Cooldowns:SaveSettings()
    if settings then
        TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, settings)
    end
end
