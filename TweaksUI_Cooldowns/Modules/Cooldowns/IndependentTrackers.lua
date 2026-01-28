-- ============================================================================
-- TUI:CD Independent Trackers
-- Creates independent tracker frames that don't rely on Blizzard's CDM viewers
-- Uses Midnight-native Duration Objects for combat-safe cooldown updates
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.IndependentTrackers = TUICD.IndependentTrackers or {}
local IT = TUICD.IndependentTrackers

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local TRACKER_TYPES = {
    essential = {
        key = "essential",
        viewerName = "EssentialCooldownViewer",
        frameName = "TUICD_IndependentEssential",
        label = "Essential",
        source = "cdm",  -- From Blizzard Cooldown Manager
    },
    utility = {
        key = "utility", 
        viewerName = "UtilityCooldownViewer",
        frameName = "TUICD_IndependentUtility",
        label = "Utility",
        source = "cdm",  -- From Blizzard Cooldown Manager
    },
    -- NOTE: Custom Tracker is NOT included here - it's already fully independent
    -- and has its own implementation in Cooldowns.lua
}

-- ============================================================================
-- STATE
-- ============================================================================

local initialized = false
local enabled = false
local enabling = false               -- Flag to prevent re-entry during enable
local pendingEnableTicker = nil      -- Track pending enable timer for cancellation
local layoutCallbackRegistered = false  -- Track if we've registered the Layout callback
local cachedSpells = {}      -- [trackerKey] = { {spellID, texture, name}, ... }
local trackerFrames = {}     -- [trackerKey] = frame
local iconFrames = {}        -- [trackerKey] = { [spellID] = iconFrame, ... }
local updateTicker = nil     -- Continuous update ticker for range/usability (only when needed)

-- Update interval for range/usability checks (5x per second is plenty for range)
local RANGE_UPDATE_INTERVAL = 0.2

-- Debug mode (independent of main module)
IT.debugMode = false

-- ============================================================================
-- DEBUG HELPERS
-- ============================================================================

local function dprint(...)
    if IT.debugMode then
        print("|cff00ccff[IT]|r", ...)
    end
end

-- ============================================================================
-- SETTINGS ACCESS (Phase 1: Full Settings Integration)
-- ============================================================================

-- Default settings for IT trackers (mirrors Cooldowns.lua TRACKER_DEFAULTS)
local IT_DEFAULTS = {
    -- Layout
    iconSize = 36,              -- Base size (used with aspect ratio)
    iconWidth = nil,            -- Custom width (nil = use iconSize + aspect)
    iconHeight = nil,           -- Custom height (nil = use iconSize + aspect)
    aspectRatio = "1:1",        -- Preset or "custom"
    columns = 8,
    rows = 0,                   -- 0 = unlimited
    spacingH = 2,               -- Horizontal spacing between icons
    spacingV = 2,               -- Vertical spacing between rows
    growDirection = "RIGHT",    -- PRIMARY: LEFT, RIGHT, UP, or DOWN
    growSecondary = "DOWN",     -- SECONDARY: LEFT, RIGHT, UP, or DOWN
    alignment = "LEFT",         -- LEFT, CENTER, or RIGHT
    reverseOrder = false,
    
    -- Position (fallback - Layout module handles this normally)
    point = "CENTER",
    x = 0,
    y = 0,
    scale = 1.0,
    
    -- Appearance
    zoom = 0.08,                -- Texture inset (0 = full, higher = more zoom)
    borderAlpha = 1.0,
    iconOpacity = 1.0,          -- Out of combat opacity
    iconOpacityCombat = 1.0,    -- In combat opacity
    iconEdgeStyle = "sharp",    -- "sharp", "rounded", "square"
    useMasque = false,
    showBorder = true,
    borderStyle = "default",
    borderColorR = 0.3,
    borderColorG = 0.3,
    borderColorB = 0.3,
    borderColorA = 0.8,
    desaturateOnCD = false,     -- Desaturate icon when on cooldown
    
    -- Cooldown Display
    showSweep = true,           -- Show cooldown sweep/spiral animation
    showCountdownText = true,   -- Show countdown numbers
    cooldownTextScale = 1.0,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownTextColorR = 1.0,
    cooldownTextColorG = 0.82,
    cooldownTextColorB = 0.0,
    
    -- Count/Stack Text
    countTextScale = 1.0,
    countTextOffsetX = 0,
    countTextOffsetY = 0,
    countTextColorR = 1.0,
    countTextColorG = 1.0,
    countTextColorB = 1.0,
    
    -- Visibility
    visibilityEnabled = false,  -- Master toggle for visibility conditions
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
    
    -- Range & Usability Indicators (Phase 2)
    showRangeIndicator = false,      -- Show red tint when out of range
    rangeIndicatorR = 0.8,           -- Range indicator red component
    rangeIndicatorG = 0.1,           -- Range indicator green component
    rangeIndicatorB = 0.1,           -- Range indicator blue component
    showUsabilityIndicator = false,  -- Desaturate when spell not usable
    
    -- Interaction
    clickthrough = false,
    showTooltip = true,
}

-- Aspect ratio width/height multipliers
local ASPECT_MULTIPLIERS = {
    ["1:1"] = { w = 1, h = 1 },
    ["4:3"] = { w = 4/3, h = 1 },
    ["3:4"] = { w = 1, h = 4/3 },
    ["16:9"] = { w = 16/9, h = 1 },
    ["9:16"] = { w = 1, h = 16/9 },
    ["2:1"] = { w = 2, h = 1 },
    ["1:2"] = { w = 1, h = 2 },
}

-- Forward declarations for functions used before definition
local RefreshTickerState

-- ============================================================================
-- PER-ICON INTEGRATION
-- IT per-icon frames are managed by CooldownHighlights, not here.
-- When IT is enabled, CooldownHighlights uses IT's icons as the source.
-- This allows IT to share the same per-icon system as Essential/Utility CDM.
-- ============================================================================

-- Per-icon settings helpers - kept for API compatibility but CooldownHighlights
-- uses slot-index based settings stored in essentialHighlights/utilityHighlights
local function GetPerIconSetting(trackerKey, spellID, key)
    -- For now, return nil - actual per-icon is handled by CooldownHighlights
    return nil
end

local function SetPerIconSetting(trackerKey, spellID, key, value)
    -- For now, no-op - actual per-icon is handled by CooldownHighlights
end

local function IsIconHidden(trackerKey, spellID)
    return GetPerIconSetting(trackerKey, spellID, "hidden") == true
end

-- Get a setting value with fallback to defaults
local function GetSetting(trackerKey, setting)
    local db = TUICD.Database
    if db and db.GetTrackerSetting then
        local value = db:GetTrackerSetting(trackerKey, setting)
        if value ~= nil then
            return value
        end
    end
    -- Return default if not set
    return IT_DEFAULTS[setting]
end

-- Set a setting value (wrapper for Database access)
local function SetSetting(trackerKey, setting, value)
    local db = TUICD.Database
    if db and db.SetTrackerSetting then
        db:SetTrackerSetting(trackerKey, setting, value)
    end
end

-- Calculate actual icon dimensions based on settings
local function GetIconDimensions(trackerKey)
    local iconSize = GetSetting(trackerKey, "iconSize") or 36
    local aspectRatio = GetSetting(trackerKey, "aspectRatio") or "1:1"
    local customWidth = GetSetting(trackerKey, "iconWidth")
    local customHeight = GetSetting(trackerKey, "iconHeight")
    
    -- If custom dimensions are explicitly set, use them
    if customWidth and customHeight then
        return customWidth, customHeight
    end
    
    -- Otherwise calculate from aspect ratio
    local mult = ASPECT_MULTIPLIERS[aspectRatio]
    if not mult then
        mult = ASPECT_MULTIPLIERS["1:1"]
    end
    
    local width = iconSize * mult.w
    local height = iconSize * mult.h
    
    return math.floor(width + 0.5), math.floor(height + 0.5)
end

-- Get border color as table
local function GetBorderColor(trackerKey)
    return {
        r = GetSetting(trackerKey, "borderColorR") or 0.3,
        g = GetSetting(trackerKey, "borderColorG") or 0.3,
        b = GetSetting(trackerKey, "borderColorB") or 0.3,
        a = GetSetting(trackerKey, "borderColorA") or 0.8,
    }
end

-- Get cooldown text color
local function GetCooldownTextColor(trackerKey)
    return {
        r = GetSetting(trackerKey, "cooldownTextColorR") or 1.0,
        g = GetSetting(trackerKey, "cooldownTextColorG") or 0.82,
        b = GetSetting(trackerKey, "cooldownTextColorB") or 0.0,
    }
end

-- Get count text color
local function GetCountTextColor(trackerKey)
    return {
        r = GetSetting(trackerKey, "countTextColorR") or 1.0,
        g = GetSetting(trackerKey, "countTextColorG") or 1.0,
        b = GetSetting(trackerKey, "countTextColorB") or 1.0,
    }
end

-- ============================================================================
-- VISIBILITY HANDLING
-- ============================================================================

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
        isMounted = IsMounted(),
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

-- Check if tracker should be visible based on conditions
local function ShouldBeVisible(trackerKey)
    -- Force all visible mode bypasses all visibility conditions
    if TUICD.forceAllVisible then
        return true
    end
    
    -- Always show in Edit Mode / Layout Mode for positioning
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return true
    end
    
    -- Check if Layout container is shown
    local layoutContainer = _G["TweaksUI_LayoutContainer"]
    if layoutContainer and layoutContainer:IsShown() then
        return true
    end
    
    -- Check if visibility conditions are enabled
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

-- Update visibility for a single tracker
local function UpdateTrackerVisibility(trackerKey)
    local frame = trackerFrames[trackerKey]
    if not frame then return end
    
    local shouldShow = ShouldBeVisible(trackerKey)
    
    -- Use alpha for smooth transitions and to preserve layout mode positioning
    if shouldShow then
        local opacity = GetSetting(trackerKey, "iconOpacity") or 1.0
        frame:SetAlpha(opacity)
    else
        frame:SetAlpha(0)
    end
end

-- Update visibility for all trackers
local function UpdateAllVisibility()
    for trackerKey, _ in pairs(TRACKER_TYPES) do
        UpdateTrackerVisibility(trackerKey)
    end
end

-- ============================================================================
-- SPELL EXTRACTION FROM BLIZZARD CDM
-- ============================================================================

local function ExtractSpellsFromViewer(viewer, trackerKey)
    if not viewer then return {} end
    
    local spells = {}
    
    -- Use viewer.icons if available (Blizzard's ordered array)
    local iconList = viewer.icons
    if not iconList or #iconList == 0 then
        -- Fallback to GetChildren if .icons not available
        iconList = {viewer:GetChildren()}
        dprint("Using GetChildren fallback for " .. trackerKey)
    else
        dprint("Using viewer.icons: " .. #iconList .. " icons")
    end
    
    -- First pass: collect all valid icons with their positions
    local iconData = {}
    
    for idx, child in ipairs(iconList) do
        -- Check if this is a cooldown icon (has Icon texture and Cooldown)
        if child and (child.Icon or child.icon) and (child.Cooldown or child.cooldown) then
            local spellID = nil
            local texture = nil
            local name = nil
            
            -- Get spell ID using GetSpellID method (correct for Midnight)
            if child.GetSpellID then
                local ok, result = pcall(child.GetSpellID, child)
                if ok and result then
                    spellID = result
                end
            end
            
            -- Fallback to cooldownInfo table
            if not spellID and child.cooldownInfo and child.cooldownInfo.spellID then
                spellID = child.cooldownInfo.spellID
            end
            
            if spellID then
                -- Get texture using GetSpellTexture method
                if child.GetSpellTexture then
                    local ok, result = pcall(child.GetSpellTexture, child)
                    if ok and result then
                        texture = result
                    end
                end
                
                -- Get name using GetNameText method
                if child.GetNameText then
                    local ok, result = pcall(child.GetNameText, child)
                    if ok and result then
                        name = result
                    end
                end
                
                -- Fallback to C_Spell API
                if not texture or not name then
                    local info = C_Spell.GetSpellInfo(spellID)
                    if info then
                        texture = texture or info.iconID
                        name = name or info.name
                    end
                end
                
                if texture then
                    -- Get icon's position for sorting
                    local x, y = 0, 0
                    if child:GetLeft() and child:GetTop() then
                        x = child:GetLeft() or 0
                        y = -(child:GetTop() or 0)  -- Negate so higher Y = lower in sort
                    end
                    
                    table.insert(iconData, {
                        spellID = spellID,
                        texture = texture,
                        name = name or ("Spell " .. spellID),
                        x = x,
                        y = y,
                        arrIdx = idx,
                    })
                end
            end
        end
    end
    
    -- Sort by visual position: top-to-bottom (y), then left-to-right (x)
    -- This gives us the visual reading order
    table.sort(iconData, function(a, b)
        if math.abs(a.y - b.y) > 5 then  -- Different rows (5px tolerance)
            return a.y < b.y
        end
        return a.x < b.x  -- Same row, sort by x
    end)
    
    -- Now assign cdmIndex based on sorted visual order
    for i, data in ipairs(iconData) do
        table.insert(spells, {
            spellID = data.spellID,
            texture = data.texture,
            name = data.name,
            cdmIndex = i,
        })
        dprint(string.format("Extracted [%d]: %s (%d) pos=(%.0f,%.0f)", i, data.name or "?", data.spellID, data.x, data.y))
    end
    
    dprint(string.format("Extracted %d spells from %s (sorted by position)", #spells, trackerKey))
    return spells
end

function IT:ExtractCurrentSpecSpells()
    local specID = GetSpecialization() and GetSpecializationInfo(GetSpecialization()) or 0
    dprint("Extracting spells for spec:", specID)
    
    cachedSpells = {}
    local totalExtracted = 0
    
    for trackerKey, config in pairs(TRACKER_TYPES) do
        if config.source == "cdm" then
            -- CDM-based tracker (essential, utility)
            local viewer = _G[config.viewerName]
            if viewer then
                cachedSpells[trackerKey] = ExtractSpellsFromViewer(viewer, trackerKey)
                totalExtracted = totalExtracted + #cachedSpells[trackerKey]
            else
                dprint("Viewer not found:", config.viewerName)
                cachedSpells[trackerKey] = {}
            end
        end
    end
    
    dprint("Total extracted:", totalExtracted)
    return totalExtracted > 0
end

-- ============================================================================
-- ICON TEXTURE COORDINATE HELPER (aspect ratio cropping)
-- ============================================================================

-- Apply texture coordinates with zoom and aspect ratio cropping
-- This prevents squashing by cropping the texture to match the frame's aspect ratio
local function ApplyIconTexCoord(iconTexture, trackerKey, iconWidth, iconHeight)
    if not iconTexture or not iconTexture.SetTexCoord then return end
    
    local zoom = GetSetting(trackerKey, "zoom") or 0.08
    local edgeStyle = GetSetting(trackerKey, "iconEdgeStyle") or "sharp"
    
    -- Calculate texture coordinates
    local left = zoom
    local right = 1 - zoom
    local top = zoom
    local bottom = 1 - zoom
    
    -- Apply aspect ratio cropping if non-square
    if iconWidth and iconHeight and iconWidth ~= iconHeight then
        if iconWidth > iconHeight then
            -- Wider than tall: crop top and bottom
            local cropAmount = (1 - iconHeight / iconWidth) / 2
            top = top + cropAmount * (1 - 2 * zoom)
            bottom = bottom - cropAmount * (1 - 2 * zoom)
        else
            -- Taller than wide: crop left and right
            local cropAmount = (1 - iconWidth / iconHeight) / 2
            left = left + cropAmount * (1 - 2 * zoom)
            right = right - cropAmount * (1 - 2 * zoom)
        end
    end
    
    iconTexture:SetTexCoord(left, right, top, bottom)
end

-- ============================================================================
-- ICON FRAME CREATION (Phase 1: Full Appearance Settings)
-- ============================================================================

local function CreateIconFrame(parent, spellID, texture, name, index, trackerKey)
    local frame = CreateFrame("Frame", nil, parent)
    
    -- Get icon dimensions from settings
    local iconWidth, iconHeight = GetIconDimensions(trackerKey)
    frame:SetSize(iconWidth, iconHeight)
    
    -- Store spell info and tracker reference
    frame.spellID = spellID
    frame.spellName = name
    frame.index = index
    frame.trackerKey = trackerKey
    
    -- CooldownHighlights compatibility (same properties as Custom Tracker icons)
    frame.trackType = "spell"
    frame.trackID = spellID
    frame.entryName = name
    
    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexture(texture)
    
    -- Apply zoom/texture inset with aspect ratio cropping
    ApplyIconTexCoord(frame.icon, trackerKey, iconWidth, iconHeight)
    
    -- Cooldown frame (uses Blizzard template for sweep/text)
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints()
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetDrawBling(false)
    
    -- Apply sweep visibility setting
    local showSweep = GetSetting(trackerKey, "showSweep")
    if showSweep == nil then showSweep = true end
    frame.cooldown:SetDrawSwipe(showSweep)
    
    -- Apply countdown text visibility
    local showCountdown = GetSetting(trackerKey, "showCountdownText")
    if showCountdown == nil then showCountdown = true end
    frame.cooldown:SetHideCountdownNumbers(not showCountdown)
    
    -- Border
    frame.border = frame:CreateTexture(nil, "OVERLAY")
    frame.border:SetPoint("TOPLEFT", -1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    
    -- Apply border settings
    local showBorder = GetSetting(trackerKey, "showBorder")
    if showBorder == nil then showBorder = true end
    local borderColor = GetBorderColor(trackerKey)
    local borderAlpha = GetSetting(trackerKey, "borderAlpha") or 1.0
    frame.border:SetVertexColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a * borderAlpha)
    frame.border:SetShown(showBorder)
    
    -- Charge/stack count
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    
    -- Apply count text settings
    local countScale = GetSetting(trackerKey, "countTextScale") or 1.0
    local countOffsetX = GetSetting(trackerKey, "countTextOffsetX") or 0
    local countOffsetY = GetSetting(trackerKey, "countTextOffsetY") or 0
    frame.count:SetPoint("BOTTOMRIGHT", -2 + countOffsetX, 2 + countOffsetY)
    
    local countColor = GetCountTextColor(trackerKey)
    frame.count:SetTextColor(countColor.r, countColor.g, countColor.b)
    
    if countScale ~= 1.0 then
        local fontName, fontSize, fontFlags = frame.count:GetFont()
        if fontName and fontSize then
            frame.count:SetFont(fontName, fontSize * countScale, fontFlags)
        end
    end
    frame.count:Hide()
    
    -- Apply opacity
    local opacity = GetSetting(trackerKey, "iconOpacity") or 1.0
    frame:SetAlpha(opacity)
    
    -- Track out-of-range state for vertex color management
    frame.outOfRange = false
    
    -- Clickthrough setting
    local clickthrough = GetSetting(trackerKey, "clickthrough") or false
    frame:EnableMouse(not clickthrough)
    
    -- Tooltip (only if enabled)
    local showTooltip = GetSetting(trackerKey, "showTooltip")
    if showTooltip == nil then showTooltip = true end
    
    if showTooltip and not clickthrough then
        frame:SetScript("OnEnter", function(self)
            if InCombatLockdown() then return end
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spellID)
                GameTooltip:Show()
            end)
        end)
        
        frame:SetScript("OnLeave", function()
            if not InCombatLockdown() then
                GameTooltip:Hide()
            end
        end)
    else
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
    end
    
    frame:Show()
    
    dprint(string.format("Created icon: %s (%d) - %dx%d", name, spellID, iconWidth, iconHeight))
    return frame
end

-- ============================================================================
-- COOLDOWN UPDATES (Midnight-safe using Duration Objects)
-- Mirrors CustomTracker pattern with spellID-keyed per-icon settings
-- ============================================================================

local function UpdateIconCooldown(iconFrame)
    if not iconFrame or not iconFrame.cooldown then return end
    
    local spellID = iconFrame.spellID
    local trackerKey = iconFrame.trackerKey
    if not spellID then return end
    
    -- Track if we're actually on cooldown (for desaturation and per-icon settings)
    local isOnCooldown = false
    local GCD_THRESHOLD = 2.0  -- Filter out GCD (typically 1.5s)
    
    -- Check if we're in a restricted state (combat, encounter, M+, etc.)
    local isRestricted = InCombatLockdown()
    
    local cooldownSet = false
    
    -- =====================================================================
    -- COOLDOWN UPDATE - Use Duration Objects (Midnight API compatible)
    -- Duration Objects handle secret values internally
    -- =====================================================================
    
    -- Try charges cooldown first (C_Spell.GetSpellChargesCooldownDuration)
    if C_Spell.GetSpellChargesCooldownDuration then
        pcall(function()
            local chargeDuration = C_Spell.GetSpellChargesCooldownDuration(spellID)
            if chargeDuration then
                iconFrame.cooldown:SetCooldownFromDurationObject(chargeDuration, true)
                cooldownSet = true
            end
        end)
    end
    
    -- If no charge cooldown, try regular cooldown Duration Object
    if not cooldownSet and C_Spell.GetSpellCooldownDuration then
        pcall(function()
            local duration = C_Spell.GetSpellCooldownDuration(spellID)
            if duration then
                iconFrame.cooldown:SetCooldownFromDurationObject(duration, true)
                cooldownSet = true
            end
        end)
    end
    
    -- Traditional API fallback - ONLY when not in combat
    -- During combat, info.startTime and info.duration are SECRET values
    if not cooldownSet and not isRestricted then
        pcall(function()
            local info = C_Spell.GetSpellCooldown(spellID)
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
    
    -- =====================================================================
    -- COOLDOWN STATE DETECTION - ONLY when not in combat
    -- During combat, we cannot read cooldown values (they're secret)
    -- so we skip state detection - the visual cooldown swipe is enough
    -- =====================================================================
    if not isRestricted then
        pcall(function()
            local info = C_Spell.GetSpellCooldown(spellID)
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
    
    if C_Spell and C_Spell.GetSpellDisplayCount then
        -- Just pass through - SetText handles secret strings
        local ok, err = pcall(function()
            local displayCount = C_Spell.GetSpellDisplayCount(spellID)
            iconFrame.count:SetText(displayCount or "")
            iconFrame.count:Show()
            countSet = true
        end)
        if not ok and IT.debugMode then
            dprint("Charge display error for", spellID, ":", err)
        end
    end
    
    -- Fallback: Try GetSpellCharges (only when not in combat)
    if not countSet and not isRestricted then
        pcall(function()
            local chargesInfo = C_Spell.GetSpellCharges(spellID)
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
    
    -- =====================================================================
    -- RANGE INDICATOR - Tint icon when spell is out of range
    -- Uses SetVertexColor for proper color tinting (like Blizzard action bars)
    -- =====================================================================
    local showRangeIndicator = GetSetting(trackerKey, "showRangeIndicator")
    if showRangeIndicator and iconFrame.icon then
        local outOfRange = false
        
        -- Only check range if we have a target
        if UnitExists("target") and not UnitIsDead("target") then
            pcall(function()
                -- C_Spell.IsSpellInRange returns true/false/nil
                -- true = in range, false = out of range, nil = no range requirement or can't determine
                local inRange = C_Spell.IsSpellInRange(spellID, "target")
                if inRange == false then
                    outOfRange = true
                end
            end)
        end
        
        -- Apply vertex color tint (red when out of range, white when in range)
        if outOfRange then
            local r = GetSetting(trackerKey, "rangeIndicatorR") or 0.8
            local g = GetSetting(trackerKey, "rangeIndicatorG") or 0.1
            local b = GetSetting(trackerKey, "rangeIndicatorB") or 0.1
            iconFrame.icon:SetVertexColor(r, g, b)
            iconFrame.outOfRange = true
        else
            -- Only reset if we were previously out of range
            if iconFrame.outOfRange then
                iconFrame.icon:SetVertexColor(1, 1, 1)
                iconFrame.outOfRange = false
            end
        end
    elseif iconFrame.icon and iconFrame.outOfRange then
        -- Range indicator disabled but icon was tinted - reset it
        iconFrame.icon:SetVertexColor(1, 1, 1)
        iconFrame.outOfRange = false
    end
    
    -- =====================================================================
    -- TRACKER ICON APPEARANCE - Apply standard desaturation and opacity
    -- Note: Per-icon settings now create STANDALONE frames, not modify tracker icons
    -- Tracker icons always use tracker-level settings
    -- =====================================================================
    
    -- Apply tracker-level opacity
    local opacity = GetSetting(trackerKey, "iconOpacity") or 1.0
    iconFrame:SetAlpha(opacity)
    
    -- Usability indicator takes precedence over basic desaturation
    local showUsability = GetSetting(trackerKey, "showUsabilityIndicator")
    if showUsability and iconFrame.icon then
        local isUsable = true
        pcall(function()
            local usable = C_Spell.IsSpellUsable(spellID)
            isUsable = usable
        end)
        pcall(function()
            iconFrame.icon:SetDesaturated(not isUsable)
        end)
    else
        -- Basic desaturation based on cooldown state (matches custom tracker)
        pcall(function()
            if iconFrame.icon and iconFrame.icon.SetDesaturated then
                iconFrame.icon:SetDesaturated(isOnCooldown)
            end
        end)
    end
end

local function UpdateAllCooldowns()
    for trackerKey, icons in pairs(iconFrames) do
        for spellID, iconFrame in pairs(icons) do
            pcall(UpdateIconCooldown, iconFrame)
        end
    end
end

-- ============================================================================
-- TRACKER FRAME MANAGEMENT
-- ============================================================================

local function CreateTrackerFrame(trackerKey)
    local config = TRACKER_TYPES[trackerKey]
    if not config then return nil end
    
    -- Load position from existing settings
    local savedPoint = GetSetting(trackerKey, "point") or "CENTER"
    local savedX = GetSetting(trackerKey, "x") or 0
    local savedY = GetSetting(trackerKey, "y") or 0
    
    local frame = CreateFrame("Frame", config.frameName, UIParent)
    frame:SetSize(200, 50)
    frame:SetPoint(savedPoint, UIParent, savedPoint, savedX, savedY)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    
    -- Ignore UIParent alpha changes (for DialogueUI compatibility)
    -- This prevents our frames from fading when DialogueUI fades UIParent
    frame:SetIgnoreParentAlpha(true)
    
    -- Make movable in layout mode
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if TUICD.Layout and TUICD.Layout:IsUnlocked() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, _, x, y = self:GetPoint()
        if TUICD.Database then
            TUICD.Database:SetTrackerSetting(trackerKey, "point", point)
            TUICD.Database:SetTrackerSetting(trackerKey, "x", x)
            TUICD.Database:SetTrackerSetting(trackerKey, "y", y)
        end
    end)
    
    frame.trackerKey = trackerKey
    
    -- Protection against external addons hiding our frames
    -- Some dialog addons (like DialogUI) may trigger hide on UIParent children
    frame:SetScript("OnHide", function(self)
        -- If we're supposed to be visible, re-show after a brief delay
        -- This handles cases where external addons hide UIParent children
        if enabled and ShouldBeVisible(trackerKey) then
            C_Timer.After(0.1, function()
                if enabled and ShouldBeVisible(trackerKey) and not self:IsShown() then
                    dprint("Re-showing frame hidden externally:", trackerKey)
                    self:Show()
                    UpdateTrackerVisibility(trackerKey)
                end
            end)
        end
    end)
    
    frame:Show()
    
    dprint("Created tracker frame:", config.frameName)
    return frame
end

local function LayoutIcons(frame, trackerKey)
    local icons = iconFrames[trackerKey]
    if not icons or not frame then return end
    
    -- Build ordered list of visible icons
    local orderedIcons = {}
    for spellID, iconFrame in pairs(icons) do
        if iconFrame:IsShown() then
            table.insert(orderedIcons, iconFrame)
        end
    end
    
    -- Sort by index (ascending = original CDM order)
    table.sort(orderedIcons, function(a, b) 
        return (a.index or 0) < (b.index or 0) 
    end)
    
    if #orderedIcons == 0 then
        frame:SetSize(36, 36)
        return
    end
    
    -- Get all layout settings
    local iconSize = GetSetting(trackerKey, "iconSize") or 36
    local customWidth = GetSetting(trackerKey, "iconWidth")
    local customHeight = GetSetting(trackerKey, "iconHeight")
    local aspectRatio = GetSetting(trackerKey, "aspectRatio") or "1:1"
    
    local columns = GetSetting(trackerKey, "columns") or 4
    local spacingH = GetSetting(trackerKey, "spacingH") or 2
    local spacingV = GetSetting(trackerKey, "spacingV") or 2
    local reverseOrder = GetSetting(trackerKey, "reverseOrder") or false
    
    -- Custom grid settings
    local useCustomGrid = GetSetting(trackerKey, "useCustomGrid") or false
    local customLayout = GetSetting(trackerKey, "customLayout") or ""
    local customGridMode = GetSetting(trackerKey, "customGridMode") or "ROW"
    local customGridAlign = GetSetting(trackerKey, "customGridAlign") or (customGridMode == "COLUMN" and "TOP" or "LEFT")
    
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
    
    -- Reverse order if needed
    if reverseOrder then
        local reversed = {}
        for i = #orderedIcons, 1, -1 do
            reversed[#reversed + 1] = orderedIcons[i]
        end
        orderedIcons = reversed
    end
    
    dprint(string.format("LayoutIcons [%s]: %d icons, size=%.0fx%.0f, useCustomGrid=%s, pattern='%s'", 
        trackerKey, #orderedIcons, iconWidth, iconHeight, tostring(useCustomGrid), customLayout))
    
    -- Parse custom row/column pattern if custom grid is enabled
    local customRowSizes = {}
    local useCustomLayout = false
    
    if useCustomGrid then
        -- Custom grid is enabled - parse pattern or default to all icons on one row/col
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
        
        -- If no valid pattern, default to all icons
        if #customRowSizes == 0 then
            customRowSizes = { #orderedIcons }
        end
        useCustomLayout = true
    end
    
    -- CUSTOM GRID MODE: Row or Column based pattern with alignment
    if useCustomLayout and #customRowSizes > 0 then
        local iconIdx = 1
        local iconCount = 0
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
                        if iconIdx <= #orderedIcons then
                            local icon = orderedIcons[iconIdx]
                            iconIdx = iconIdx + 1
                            iconCount = iconCount + 1
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
            while iconIdx <= #orderedIcons do
                local iconsInThisCol = 0
                local overflowStartIdx = #placedIcons + 1
                for rowIdx = 1, overflowSize do
                    if iconIdx <= #orderedIcons then
                        local icon = orderedIcons[iconIdx]
                        iconIdx = iconIdx + 1
                        iconCount = iconCount + 1
                        table.insert(placedIcons, {icon = icon, col = currentCol, row = rowIdx - 1, groupSize = 0})
                        iconsInThisCol = iconsInThisCol + 1
                    end
                end
                -- Update groupSize for overflow icons
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
                placed.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", xOffset, yOffset)
                placed.icon:SetSize(iconWidth, iconHeight)
            end
            
            frame:SetSize(totalWidth, totalHeight)
            dprint(string.format("LayoutIcons [%s]: Custom COLUMN grid - %d icons, %d cols, maxHeight=%d, size=%.0fx%.0f, align=%s", 
                trackerKey, iconCount, totalSecondary, maxPrimary, totalWidth, totalHeight, customGridAlign))
            
        else
            -- ROW MODE: Fill right (primary), then wrap down (secondary)
            local currentRow = 0
            
            for _, rowSize in ipairs(customRowSizes) do
                if rowSize == 0 then
                    currentRow = currentRow + 1
                else
                    local iconsInThisRow = 0
                    for colIdx = 1, rowSize do
                        if iconIdx <= #orderedIcons then
                            local icon = orderedIcons[iconIdx]
                            iconIdx = iconIdx + 1
                            iconCount = iconCount + 1
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
            while iconIdx <= #orderedIcons do
                local iconsInThisRow = 0
                local overflowStartIdx = #placedIcons + 1
                for colIdx = 1, overflowSize do
                    if iconIdx <= #orderedIcons then
                        local icon = orderedIcons[iconIdx]
                        iconIdx = iconIdx + 1
                        iconCount = iconCount + 1
                        table.insert(placedIcons, {icon = icon, col = colIdx - 1, row = currentRow, groupSize = 0})
                        iconsInThisRow = iconsInThisRow + 1
                    end
                end
                -- Update groupSize for overflow icons
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
                placed.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", xOffset, yOffset)
                placed.icon:SetSize(iconWidth, iconHeight)
            end
            
            frame:SetSize(totalWidth, totalHeight)
            dprint(string.format("LayoutIcons [%s]: Custom ROW grid - %d icons, %d rows, maxWidth=%d, size=%.0fx%.0f, align=%s", 
                trackerKey, iconCount, totalSecondary, maxPrimary, totalWidth, totalHeight, customGridAlign))
        end
        
        return  -- Early return for custom grid
    end
    
    -- STANDARD GRID LAYOUT (when custom grid is disabled)
    local iconCount = 0
    
    for i, icon in ipairs(orderedIcons) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        
        iconCount = iconCount + 1
        
        local xOffset = col * (iconWidth + spacingH)
        local yOffset = -row * (iconHeight + spacingV)
        
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", frame, "TOPLEFT", xOffset, yOffset)
        icon:SetSize(iconWidth, iconHeight)
    end
    
    -- Calculate frame size
    local numRows = math.ceil(#orderedIcons / columns)
    local totalWidth = math.min(#orderedIcons, columns) * iconWidth + (math.min(#orderedIcons, columns) - 1) * spacingH
    local totalHeight = numRows * iconHeight + (numRows - 1) * spacingV
    totalWidth = math.max(totalWidth, 1)
    totalHeight = math.max(totalHeight, 1)
    frame:SetSize(totalWidth, totalHeight)
    
    dprint(string.format("LayoutIcons [%s]: Standard grid - %d visible, %.0fx%.0f size", 
        trackerKey, iconCount, totalWidth, totalHeight))
end

-- ============================================================================
-- BUILD TRACKERS
-- ============================================================================

function IT:BuildTracker(trackerKey)
    local config = TRACKER_TYPES[trackerKey]
    if not config then return end
    
    local spells = cachedSpells[trackerKey]
    if not spells or #spells == 0 then
        dprint("No spells for tracker:", trackerKey)
        return
    end
    
    -- Create or get tracker frame
    if not trackerFrames[trackerKey] then
        trackerFrames[trackerKey] = CreateTrackerFrame(trackerKey)
    else
        -- Reusing existing frame - make sure it's visible and properly parented
        local frame = trackerFrames[trackerKey]
        if not frame:GetParent() then
            frame:SetParent(UIParent)
        end
    end
    local frame = trackerFrames[trackerKey]
    
    -- Clear existing icons (just hide, don't destroy)
    if iconFrames[trackerKey] then
        for _, icon in pairs(iconFrames[trackerKey]) do
            if icon then
                icon:Hide()
                icon:ClearAllPoints()
            end
        end
    end
    iconFrames[trackerKey] = {}
    
    -- Create icons for each spell (using cdmIndex to preserve Blizzard's CDM order)
    -- Skip icons that are marked as hidden (per-icon setting keyed by spellID)
    local visibleCount = 0
    for i, spellData in ipairs(spells) do
        -- Check if this icon is hidden via per-icon settings
        if not IsIconHidden(trackerKey, spellData.spellID) then
            local orderIndex = spellData.cdmIndex or i  -- Use CDM index if available
            local iconFrame = CreateIconFrame(frame, spellData.spellID, spellData.texture, spellData.name, orderIndex, trackerKey)
            iconFrames[trackerKey][spellData.spellID] = iconFrame
            visibleCount = visibleCount + 1
        else
            dprint("Skipping hidden icon:", spellData.name, spellData.spellID)
        end
    end
    
    -- Layout the icons
    LayoutIcons(frame, trackerKey)
    
    dprint(string.format("Built %s tracker: %d visible icons (%d total)", trackerKey, visibleCount, #spells))
end

function IT:BuildAllTrackers()
    for trackerKey, config in pairs(TRACKER_TYPES) do
        self:BuildTracker(trackerKey)
    end
end

-- Storage for Layout mode wrappers
local layoutWrappers = {}  -- [trackerKey] = TUIFrame-compatible wrapper

-- Create TUIFrame-compatible wrapper for an IT tracker (like Docks does)
local function CreateLayoutWrapper(trackerKey)
    local frame = trackerFrames[trackerKey]
    if not frame then return nil end
    
    local config = TRACKER_TYPES[trackerKey]
    if not config then return nil end
    
    local elementID = "IT_" .. trackerKey
    
    -- Create TUIFrame-compatible wrapper object
    local wrapper = {
        id = elementID,
        frame = frame,
        name = config.label .. " (IT)",
        category = "Cooldowns",
        
        -- Default position
        defaultPosition = {
            point = GetSetting(trackerKey, "point") or "CENTER",
            x = GetSetting(trackerKey, "x") or 0,
            y = GetSetting(trackerKey, "y") or 0,
        },
        
        -- Position management
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            if InCombatLockdown() then return end
            
            point = point or "CENTER"
            relFrame = relFrame or UIParent
            relPoint = relPoint or point
            x = x or 0
            y = y or 0
            
            frame:ClearAllPoints()
            frame:SetPoint(point, relFrame, relPoint, x, y)
            
            -- Save to IT settings
            SetSetting(trackerKey, "point", point)
            SetSetting(trackerKey, "x", x)
            SetSetting(trackerKey, "y", y)
        end,
        
        GetSaveData = function(self)
            local left = frame:GetLeft()
            local bottom = frame:GetBottom()
            
            if not left or not bottom then
                local point, _, _, x, y = frame:GetPoint(1)
                return {
                    point = point or "CENTER",
                    x = x or 0,
                    y = y or 0,
                }
            end
            
            return {
                point = "BOTTOMLEFT",
                x = left,
                y = bottom,
            }
        end,
        
        LoadSaveData = function(self, data)
            if not data then return end
            if InCombatLockdown() then return end
            
            local point = data.point or "CENTER"
            local x = data.x or 0
            local y = data.y or 0
            
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point, x, y)
            
            -- Save to IT settings
            SetSetting(trackerKey, "point", point)
            SetSetting(trackerKey, "x", x)
            SetSetting(trackerKey, "y", y)
        end,
        
        -- Size management
        GetSize = function(self)
            return frame:GetSize()
        end,
        
        GetWidth = function(self)
            return frame:GetWidth()
        end,
        
        GetHeight = function(self)
            return frame:GetHeight()
        end,
        
        GetScale = function(self)
            return frame:GetScale() or 1
        end,
        
        SetScale = function(self, scale)
            frame:SetScale(scale)
        end,
        
        -- Visibility
        Show = function(self)
            frame:Show()
        end,
        
        Hide = function(self)
            frame:Hide()
        end,
        
        IsShown = function(self)
            return frame:IsShown()
        end,
        
        -- Size locking
        SetSizeLocked = function(self, locked)
            self.sizeLocked = locked
        end,
        
        IsSizeLocked = function(self)
            return self.sizeLocked
        end,
        
        GetOuterSize = function(self)
            local left, bottom, width, height = frame:GetRect()
            if width and height then
                return width, height
            end
            return frame:GetSize()
        end,
        
        -- FlyPaper snap detection
        GetSnapTarget = function(self, tolerance)
            local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
            if not FlyPaper or not FlyPaper.Stick then return nil end
            
            local point, relFrame, relPoint, x, y = FlyPaper.Stick(
                frame,
                "TUICD",
                tolerance
            )
            if point and relFrame then
                return relFrame, point, relPoint, x, y
            end
            return nil
        end,
        
        -- Position changed callback
        onPositionChanged = function(self, point, relFrame, relPoint, x, y)
            SetSetting(trackerKey, "point", point)
            SetSetting(trackerKey, "x", x)
            SetSetting(trackerKey, "y", y)
            dprint("IT", trackerKey, "position saved via Layout Mode")
        end,
    }
    
    -- Store reference on frame
    frame.tuiFrame = wrapper
    layoutWrappers[trackerKey] = wrapper
    
    -- Register with FlyPaper for snap highlighting
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    if FlyPaper and FlyPaper.AddFrame then
        FlyPaper.AddFrame("TUICD", elementID, frame)
    end
    
    dprint("Created Layout wrapper for IT tracker:", trackerKey)
    return wrapper
end

-- Mapping from IT element IDs to old Blizzard viewer element IDs
local LEGACY_ELEMENT_IDS = {
    IT_essential = "EssentialCooldownViewer_TUIWrapper",
    IT_utility = "UtilityCooldownViewer_TUIWrapper",
    IT_buffs = "BuffIconCooldownViewer_TUIWrapper",
    IT_customTrackers = "CustomTracker_TUIWrapper",
}

-- Inherit position from old Blizzard viewer if no IT position exists
local function InheritLegacyPosition(Layout, itElementID)
    local legacyID = LEGACY_ELEMENT_IDS[itElementID]
    if not legacyID then return false end
    
    local settings = Layout:GetSettings()
    if not settings or not settings.elements then return false end
    
    -- Check if IT already has a position saved
    if settings.elements[itElementID] then
        dprint("IT element already has position:", itElementID)
        return false
    end
    
    -- Check if legacy position exists
    local legacyPos = settings.elements[legacyID]
    if legacyPos then
        -- Copy legacy position to IT element
        settings.elements[itElementID] = {
            point = legacyPos.point,
            x = legacyPos.x,
            y = legacyPos.y,
            scale = legacyPos.scale,
        }
        dprint(string.format("Inherited position from %s to %s (point=%s, x=%.1f, y=%.1f)", 
            legacyID, itElementID, legacyPos.point or "nil", legacyPos.x or 0, legacyPos.y or 0))
        return true
    end
    
    return false
end

-- Register trackers with Layout mode for dragging
function IT:RegisterWithLayoutMode()
    local Layout = TUICD.Layout
    if not Layout then
        dprint("Layout module not available (TUICD.Layout is nil)")
        return
    end
    
    if not Layout.RegisterElement then
        dprint("Layout:RegisterElement not available")
        return
    end
    
    local categoryValue = (Layout.CATEGORIES and Layout.CATEGORIES.COOLDOWNS) or "Cooldowns"
    dprint("Using category:", categoryValue)
    
    local inheritedCount = 0
    
    for trackerKey, config in pairs(TRACKER_TYPES) do
        local frame = trackerFrames[trackerKey]
        if frame then
            local elementID = "IT_" .. trackerKey
            
            -- Unregister first if already registered
            if Layout.GetElement and Layout:GetElement(elementID) then
                Layout:UnregisterElement(elementID)
                dprint("Unregistered existing element:", elementID)
            end
            
            -- Inherit position from old Blizzard viewer if available
            if InheritLegacyPosition(Layout, elementID) then
                inheritedCount = inheritedCount + 1
            end
            
            -- Create TUIFrame-compatible wrapper
            local wrapper = layoutWrappers[trackerKey]
            if not wrapper then
                wrapper = CreateLayoutWrapper(trackerKey)
            end
            
            if not wrapper then
                dprint("Failed to create wrapper for:", trackerKey)
            else
                -- Register with Layout module
                local success, err = pcall(function()
                    Layout:RegisterElement(elementID, {
                        name = config.label .. " (IT)",
                        category = categoryValue,
                        tuiFrame = wrapper,  -- Pass the wrapper, not the raw frame
                        defaultPosition = wrapper.defaultPosition,
                        onPositionChanged = function(id, pos)
                            if pos and wrapper.onPositionChanged then
                                wrapper:onPositionChanged(pos.point, nil, nil, pos.x, pos.y)
                            end
                        end,
                    })
                end)
                
                if success then
                    dprint(string.format("Registered %s with Layout mode as %s", trackerKey, elementID))
                else
                    dprint(string.format("Failed to register %s: %s", trackerKey, tostring(err)))
                end
            end
        else
            dprint("No frame for tracker:", trackerKey)
        end
    end
    
    if inheritedCount > 0 then
        TUICD:Print(string.format("|cff00ff00IT trackers registered - inherited %d position(s) from Blizzard viewers|r", inheritedCount))
    else
        TUICD:Print("|cff00ff00IT trackers registered with Layout mode|r")
    end
end

-- Unregister from Layout mode
function IT:UnregisterFromLayoutMode()
    local Layout = TUICD.Layout
    if not Layout or not Layout.UnregisterElement then return end
    
    for trackerKey, _ in pairs(TRACKER_TYPES) do
        local elementID = "IT_" .. trackerKey
        if Layout.GetElement and Layout:GetElement(elementID) then
            Layout:UnregisterElement(elementID)
            dprint(string.format("Unregistered %s from Layout mode", elementID))
        end
        
        -- Remove FlyPaper registration
        local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
        if FlyPaper and FlyPaper.RemoveFrame then
            FlyPaper.RemoveFrame("TUICD", elementID)
        end
        
        layoutWrappers[trackerKey] = nil
    end
end

-- ============================================================================
-- SETTINGS REFRESH (Phase 1: Real-time settings updates)
-- ============================================================================

-- Refresh appearance settings on a single icon without rebuilding
local function RefreshIconAppearance(iconFrame, trackerKey)
    if not iconFrame then return end
    
    -- Update size
    local iconWidth, iconHeight = GetIconDimensions(trackerKey)
    iconFrame:SetSize(iconWidth, iconHeight)
    
    -- Update texture zoom/coords with aspect ratio cropping
    if iconFrame.icon then
        ApplyIconTexCoord(iconFrame.icon, trackerKey, iconWidth, iconHeight)
    end
    
    -- Update cooldown display settings
    if iconFrame.cooldown then
        local showSweep = GetSetting(trackerKey, "showSweep")
        if showSweep == nil then showSweep = true end
        iconFrame.cooldown:SetDrawSwipe(showSweep)
        
        local showCountdown = GetSetting(trackerKey, "showCountdownText")
        if showCountdown == nil then showCountdown = true end
        iconFrame.cooldown:SetHideCountdownNumbers(not showCountdown)
    end
    
    -- Update border
    if iconFrame.border then
        local showBorder = GetSetting(trackerKey, "showBorder")
        if showBorder == nil then showBorder = true end
        local borderColor = GetBorderColor(trackerKey)
        local borderAlpha = GetSetting(trackerKey, "borderAlpha") or 1.0
        iconFrame.border:SetVertexColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a * borderAlpha)
        iconFrame.border:SetShown(showBorder)
    end
    
    -- Update count text
    if iconFrame.count then
        local countColor = GetCountTextColor(trackerKey)
        iconFrame.count:SetTextColor(countColor.r, countColor.g, countColor.b)
    end
    
    -- Update opacity
    local opacity = GetSetting(trackerKey, "iconOpacity") or 1.0
    iconFrame:SetAlpha(opacity)
    
    -- Update clickthrough
    local clickthrough = GetSetting(trackerKey, "clickthrough") or false
    iconFrame:EnableMouse(not clickthrough)
    
    -- Update tooltip scripts
    local showTooltip = GetSetting(trackerKey, "showTooltip")
    if showTooltip == nil then showTooltip = true end
    
    if showTooltip and not clickthrough then
        iconFrame:SetScript("OnEnter", function(self)
            if InCombatLockdown() then return end
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spellID)
                GameTooltip:Show()
            end)
        end)
        iconFrame:SetScript("OnLeave", function()
            if not InCombatLockdown() then
                GameTooltip:Hide()
            end
        end)
    else
        iconFrame:SetScript("OnEnter", nil)
        iconFrame:SetScript("OnLeave", nil)
    end
end

-- Refresh all icons for a tracker without rebuilding
function IT:RefreshTrackerAppearance(trackerKey)
    local icons = iconFrames[trackerKey]
    if not icons then return end
    
    for spellID, iconFrame in pairs(icons) do
        RefreshIconAppearance(iconFrame, trackerKey)
    end
    
    -- Re-layout after appearance changes (size may have changed)
    local frame = trackerFrames[trackerKey]
    if frame then
        LayoutIcons(frame, trackerKey)
    end
    
    -- Update visibility based on current conditions
    UpdateTrackerVisibility(trackerKey)
    
    dprint("Refreshed appearance for:", trackerKey)
end

-- Refresh all trackers
function IT:RefreshAllTrackers()
    for trackerKey, _ in pairs(TRACKER_TYPES) do
        self:RefreshTrackerAppearance(trackerKey)
    end
    -- Also update all visibility after refresh
    UpdateAllVisibility()
end

-- Update just the layout (no appearance changes)
function IT:RefreshTrackerLayout(trackerKey)
    local frame = trackerFrames[trackerKey]
    if not frame then return end
    
    LayoutIcons(frame, trackerKey)
    dprint("Refreshed layout for:", trackerKey)
end

-- Update position from settings
function IT:RefreshTrackerPosition(trackerKey)
    local frame = trackerFrames[trackerKey]
    if not frame then return end
    
    local point = GetSetting(trackerKey, "point") or "CENTER"
    local x = GetSetting(trackerKey, "x") or 0
    local y = GetSetting(trackerKey, "y") or 0
    local scale = GetSetting(trackerKey, "scale") or 1.0
    
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
    frame:SetScale(scale)
    
    dprint("Refreshed position for:", trackerKey)
end

-- Handle settings change event
local function OnSettingsChanged(moduleId, key, value)
    if not enabled then return end
    if moduleId ~= "cooldowns" then return end
    
    -- Determine which tracker was affected (if any)
    -- Key format might be trackerKey.setting or just setting
    local trackerKey = nil
    
    if key then
        for tKey, _ in pairs(TRACKER_TYPES) do
            if key:find("^" .. tKey) then
                trackerKey = tKey
                break
            end
        end
    end
    
    -- For now, refresh all trackers on any cooldowns setting change
    -- This is simple and reliable; can optimize later
    dprint("Settings changed:", moduleId, key or "bulk", "- refreshing all")
    IT:RefreshAllTrackers()
    
    -- Check if range/usability settings changed - refresh ticker state
    -- key=nil means bulk change, so always refresh ticker in that case
    if not key or (key:find("showRangeIndicator") or key:find("showUsabilityIndicator")) then
        RefreshTickerState()
    end
end

-- Register for settings events
local function RegisterSettingsEvents()
    if TUICD.Events and TUICD.EVENTS then
        TUICD.Events:Register(TUICD.EVENTS.SETTINGS_CHANGED, OnSettingsChanged, "IndependentTrackers")
        dprint("Registered for settings change events")
    end
end

local function UnregisterSettingsEvents()
    if TUICD.Events then
        TUICD.Events:UnregisterAll("IndependentTrackers")
    end
end

-- ============================================================================
-- BLIZZARD VIEWER MANAGEMENT
-- ============================================================================

-- Check if Blizzard CDM viewers are enabled (visible on screen with icons)
-- Check if Blizzard Essential/Utility viewers exist and have content
-- NOTE: We no longer require CDM to be DISABLED - we need it enabled for Buff Tracker
-- IT now hides Essential/Utility visually while keeping them alive for spell extraction
function IT:AreBlizzardViewersAvailable()
    local viewerNames = {"EssentialCooldownViewer", "UtilityCooldownViewer"}
    for _, viewerName in ipairs(viewerNames) do
        local viewer = _G[viewerName]
        if viewer then
            return true  -- At least one viewer exists
        end
    end
    return false
end

-- Hide Essential/Utility viewers visually (but keep them running for extraction)
-- BuffIconCooldownViewer is NOT touched - it continues working for buff tracking
function IT:HideBlizzardEssentialUtility()
    local viewerNames = {"EssentialCooldownViewer", "UtilityCooldownViewer"}
    for _, viewerName in ipairs(viewerNames) do
        local viewer = _G[viewerName]
        if viewer then
            dprint("Hiding Blizzard viewer:", viewerName)
            -- Store original alpha for restoration
            if not viewer._TUICD_originalAlpha then
                viewer._TUICD_originalAlpha = viewer:GetAlpha()
            end
            -- Hide with alpha 0 (keeps frame alive for spell extraction)
            viewer:SetAlpha(0)
            -- Also hide children to prevent any click interaction
            for i = 1, viewer:GetNumChildren() do
                local child = select(i, viewer:GetChildren())
                if child and child.SetAlpha then
                    pcall(function() child:SetAlpha(0) end)
                end
            end
        end
    end
end

-- Restore Essential/Utility viewers when IT is disabled
function IT:RestoreBlizzardEssentialUtility()
    local viewerNames = {"EssentialCooldownViewer", "UtilityCooldownViewer"}
    for _, viewerName in ipairs(viewerNames) do
        local viewer = _G[viewerName]
        if viewer then
            dprint("Restoring Blizzard viewer:", viewerName)
            local originalAlpha = viewer._TUICD_originalAlpha or 1.0
            viewer:SetAlpha(originalAlpha)
            viewer._TUICD_originalAlpha = nil
            -- Restore children
            for i = 1, viewer:GetNumChildren() do
                local child = select(i, viewer:GetChildren())
                if child and child.SetAlpha then
                    pcall(function() child:SetAlpha(1) end)
                end
            end
        end
    end
end

-- Legacy compatibility - redirect to new functions
function IT:AreBlizzardViewersEnabled()
    return self:AreBlizzardViewersAvailable()
end

-- Placeholder for warning popup (no longer needed but keep for API compat)
local cdmWarningPopup = nil

function IT:ShowCDMWarningPopup()
    -- No longer needed - IT works with CDM enabled
    TUICD:Print("|cff00ccffIndependent Trackers now works with CDM enabled.|r")
    TUICD:Print("|cff00ccffBuffs continue using Blizzard's Buff Tracker.|r")
end

function IT:ShowLegacyCDMWarningPopup()
    -- Keep the old popup creation for reference but don't show it
    if cdmWarningPopup and cdmWarningPopup:IsShown() then return end
    
    if not cdmWarningPopup then
        cdmWarningPopup = CreateFrame("Frame", "TUICD_CDMWarningPopup", UIParent, "BackdropTemplate")
        cdmWarningPopup:SetSize(500, 320)
        cdmWarningPopup:SetPoint("CENTER", 0, 100)
        cdmWarningPopup:SetFrameStrata("DIALOG")
        cdmWarningPopup:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 }
        })
        cdmWarningPopup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        cdmWarningPopup:EnableMouse(true)
        cdmWarningPopup:SetMovable(true)
        cdmWarningPopup:RegisterForDrag("LeftButton")
        cdmWarningPopup:SetScript("OnDragStart", cdmWarningPopup.StartMoving)
        cdmWarningPopup:SetScript("OnDragStop", cdmWarningPopup.StopMovingOrSizing)
        
        -- Title
        local title = cdmWarningPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText("|cffff8800TUI: Cooldowns - Setup Required|r")
        
        -- Step 1 Header
        local step1Header = cdmWarningPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        step1Header:SetPoint("TOPLEFT", 25, -45)
        step1Header:SetText("|cffffd100Step 1:|r Configure Tracked Buffs First!")
        
        -- Step 1 Instructions
        local step1Text = cdmWarningPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        step1Text:SetPoint("TOPLEFT", step1Header, "BOTTOMLEFT", 0, -5)
        step1Text:SetWidth(450)
        step1Text:SetJustifyH("LEFT")
        step1Text:SetText("|cffffffffBEFORE disabling CDM:|r Right-click on the Blizzard cooldown bars and configure your |cff00ff00Tracked Buffs|r settings (orientation, icon size, visibility, etc). These settings will be lost if you disable CDM first!")
        
        -- Step 2 Header
        local step2Header = cdmWarningPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        step2Header:SetPoint("TOPLEFT", step1Text, "BOTTOMLEFT", 0, -15)
        step2Header:SetText("|cffffd100Step 2:|r Disable Cooldown Manager in Edit Mode")
        
        -- Step 2 Instructions
        local step2Text = cdmWarningPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        step2Text:SetPoint("TOPLEFT", step2Header, "BOTTOMLEFT", 0, -5)
        step2Text:SetWidth(450)
        step2Text:SetJustifyH("LEFT")
        step2Text:SetText("Open Edit Mode (Esc > Edit Mode), scroll down to |cffffffffCombat|r section, and |cffff0000uncheck|r '|cffffffffCooldown Manager|r'. Click Save.")
        
        -- Step 3 Header
        local step3Header = cdmWarningPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        step3Header:SetPoint("TOPLEFT", step2Text, "BOTTOMLEFT", 0, -15)
        step3Header:SetText("|cffffd100Step 3:|r Click 'Check Again' below")
        
        -- Step 3 Instructions
        local step3Text = cdmWarningPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        step3Text:SetPoint("TOPLEFT", step3Header, "BOTTOMLEFT", 0, -5)
        step3Text:SetWidth(450)
        step3Text:SetJustifyH("LEFT")
        step3Text:SetText("Once CDM is disabled, click the button below to enable Independent Trackers.")
        
        -- Note about why
        local noteText = cdmWarningPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noteText:SetPoint("TOPLEFT", step3Text, "BOTTOMLEFT", 0, -15)
        noteText:SetWidth(450)
        noteText:SetJustifyH("LEFT")
        noteText:SetTextColor(0.6, 0.6, 0.6)
        noteText:SetText("Why? Running both systems causes UI conflicts and errors. TUI:CD's Independent Trackers fully replace Blizzard's Cooldown Manager with more features.")
        
        -- Open Edit Mode button
        local editBtn = CreateFrame("Button", nil, cdmWarningPopup, "UIPanelButtonTemplate")
        editBtn:SetSize(150, 28)
        editBtn:SetPoint("BOTTOMLEFT", 30, 20)
        editBtn:SetText("Open Edit Mode")
        editBtn:SetScript("OnClick", function()
            -- Open Edit Mode
            if EditModeManagerFrame and EditModeManagerFrame.Show then
                EditModeManagerFrame:Show()
            elseif C_EditMode and C_EditMode.Enter then
                C_EditMode.Enter()
            end
        end)
        
        -- Check Again button
        local checkBtn = CreateFrame("Button", nil, cdmWarningPopup, "UIPanelButtonTemplate")
        checkBtn:SetSize(120, 28)
        checkBtn:SetPoint("BOTTOM", 0, 20)
        checkBtn:SetText("Check Again")
        checkBtn:SetScript("OnClick", function()
            if not IT:AreBlizzardViewersEnabled() then
                cdmWarningPopup:Hide()
                TUICD:Print("|cff00ff00Cooldown Manager disabled! Enabling Independent Trackers...|r")
                IT:Enable()
            else
                TUICD:Print("|cffff0000Cooldown Manager is still enabled. Please disable it in Edit Mode.|r")
            end
        end)
        
        -- Close button (disables IT)
        local closeBtn = CreateFrame("Button", nil, cdmWarningPopup, "UIPanelButtonTemplate")
        closeBtn:SetSize(100, 28)
        closeBtn:SetPoint("BOTTOMRIGHT", -30, 20)
        closeBtn:SetText("Cancel")
        closeBtn:SetScript("OnClick", function()
            cdmWarningPopup:Hide()
            -- Disable IT setting
            if TUICD.Database then
                TUICD.Database:SetUseIndependentTrackers(false)
            end
            TUICD:Print("|cffff8800Independent Trackers disabled. Using standard mode.|r")
        end)
    end
    
    cdmWarningPopup:Show()
end

function IT:HideCDMWarningPopup()
    if cdmWarningPopup then
        cdmWarningPopup:Hide()
    end
end

-- Legacy API compatibility - redirect to new functions that actually hide/restore
function IT:HideBlizzardViewers()
    -- Redirect to new function that hides Essential/Utility (not Buffs)
    self:HideBlizzardEssentialUtility()
end

function IT:RestoreBlizzardViewers()
    -- Redirect to new function that restores Essential/Utility
    self:RestoreBlizzardEssentialUtility()
end

-- No longer needed - we're not doing complex modifications
function IT:RestoreBlizzardViewersToDefault()
    -- Just call RestoreBlizzardViewers
    self:RestoreBlizzardViewers()
end

-- ============================================================================
-- EVENT-BASED UPDATE SYSTEM
-- ============================================================================

-- Helper frame to detect UIParent show/hide (for DialogueUI compatibility)
local uiParentWatcher = nil

local function SetupUIParentWatcher()
    if uiParentWatcher then return end
    
    uiParentWatcher = CreateFrame("Frame", nil, UIParent)
    uiParentWatcher:SetSize(1, 1)
    uiParentWatcher:SetPoint("TOPLEFT", 0, 0)
    
    -- When UIParent is shown (e.g., after DialogueUI closes), restore our frames
    uiParentWatcher:SetScript("OnShow", function()
        if enabled then
            dprint("UIParent shown - restoring IT visibility")
            -- Small delay to ensure other addons have finished their work
            C_Timer.After(0.05, function()
                if enabled then
                    UpdateAllVisibility()
                    -- Also ensure frames are shown
                    for trackerKey, frame in pairs(trackerFrames) do
                        if frame and ShouldBeVisible(trackerKey) then
                            frame:Show()
                        end
                    end
                end
            end)
        end
    end)
    
    dprint("UIParent watcher created for DialogueUI compatibility")
end

-- Check if any tracker has range or usability indicators enabled
local function NeedsRangeTicker()
    for trackerKey, _ in pairs(TRACKER_TYPES) do
        if GetSetting(trackerKey, "showRangeIndicator") or GetSetting(trackerKey, "showUsabilityIndicator") then
            return true
        end
    end
    return false
end

-- Start the continuous update ticker (only for range/usability indicators)
local function StartUpdateTicker()
    if updateTicker then return end  -- Already running
    if not NeedsRangeTicker() then return end  -- Not needed
    
    updateTicker = C_Timer.NewTicker(RANGE_UPDATE_INTERVAL, function()
        -- Skip while Edit Mode is open
        if TUICD._editModePaused then return end
        if not enabled then return end
        -- Only do range checks if we have a target (skip expensive checks otherwise)
        if UnitExists("target") then
            pcall(UpdateAllCooldowns)
        end
    end)
    
    dprint("Started range update ticker")
end

-- Stop the continuous update ticker
local function StopUpdateTicker()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
        dprint("Stopped range update ticker")
    end
end

-- Refresh ticker state (call when settings change)
RefreshTickerState = function()
    if not enabled then return end
    
    if NeedsRangeTicker() then
        if not updateTicker then
            StartUpdateTicker()
        end
    else
        StopUpdateTicker()
    end
end

-- Export for settings refresh
IT.RefreshTickerState = RefreshTickerState

local function RegisterCooldownEvents()
    if not IT.eventFrame then
        IT.eventFrame = CreateFrame("Frame")
    end
    
    -- Setup UIParent watcher for DialogueUI compatibility
    SetupUIParentWatcher()
    
    -- Cooldown events
    IT.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    IT.eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    IT.eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    IT.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    IT.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    -- Combat events (for visibility and cooldown updates)
    IT.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    IT.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    
    -- Visibility events
    IT.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    IT.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    IT.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    IT.eventFrame:RegisterUnitEvent("UNIT_AURA", "player")  -- For mount detection
    
    IT.eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
            if enabled then
                pcall(UpdateAllCooldowns)
            end
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            -- Update both cooldowns and visibility on combat state change
            if enabled then
                pcall(UpdateAllCooldowns)
                pcall(UpdateAllVisibility)
            end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" or event == "UNIT_AURA" then
            -- Update visibility when conditions change
            if enabled then
                pcall(UpdateAllVisibility)
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            -- Update both visibility AND cooldowns (for immediate range indicator update)
            if enabled then
                pcall(UpdateAllCooldowns)  -- Immediate range check on target change
                pcall(UpdateAllVisibility)
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            if enabled then
                dprint("Spec changed, rebuilding...")
                C_Timer.After(1.0, function()
                    IT:ExtractCurrentSpecSpells()
                    IT:BuildAllTrackers()
                    UpdateAllVisibility()
                end)
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            if enabled then
                pcall(UpdateAllCooldowns)
                pcall(UpdateAllVisibility)
            end
        end
    end)
    
    dprint("Registered cooldown and visibility events")
    
    -- Start continuous update ticker for range/usability
    StartUpdateTicker()
end

local function UnregisterCooldownEvents()
    -- Stop the update ticker
    StopUpdateTicker()
    
    if IT.eventFrame then
        IT.eventFrame:UnregisterAllEvents()
        IT.eventFrame:SetScript("OnEvent", nil)
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function IT:Enable()
    if enabled then
        TUICD:Print("Independent Trackers already enabled")
        return
    end
    
    if enabling then
        TUICD:Print("Enable already in progress...")
        return
    end
    
    if InCombatLockdown() then
        TUICD:Print("|cffff0000Cannot enable in combat - try after combat|r")
        return
    end
    
    -- NOTE: We no longer block on CDM being enabled!
    -- CDM must stay enabled for Buff Tracker to work (aura secret values)
    -- IT will hide Essential/Utility viewers visually while building its own frames
    
    enabling = true
    TUICD:Print("Enabling Independent Trackers...")
    TUICD:Print("|cff888888(Buff Tracker continues using Blizzard CDM)|r")
    
    -- Hide the legacy warning popup if it's showing
    self:HideCDMWarningPopup()
    
    -- Check if CDM viewers exist (only for CDM-based trackers, not custom)
    local viewersExist = true
    for trackerKey, config in pairs(TRACKER_TYPES) do
        if config.source == "cdm" and config.viewerName then
            local viewer = _G[config.viewerName]
            if not viewer then
                viewersExist = false
                dprint("Viewer not found:", config.viewerName)
                break
            end
        end
    end
    
    if not viewersExist then
        TUICD:Print("|cffff8800Waiting for CDM viewers to be ready...|r")
    end
    
    local retryCount = 0
    local maxRetries = 20  -- Max 10 seconds of retrying
    
    local function TryExtract()
        -- Check if we were disabled while waiting
        if not enabling then
            dprint("Enable cancelled, aborting TryExtract")
            return
        end
        
        retryCount = retryCount + 1
        if retryCount > maxRetries then
            enabling = false
            TUICD:Print("|cffff0000Enable timed out - CDM viewers not available|r")
            return
        end
        
        local viewersExist = true
        for trackerKey, config in pairs(TRACKER_TYPES) do
            -- Only check CDM-based trackers (not custom)
            if config.source == "cdm" and config.viewerName then
                local viewer = _G[config.viewerName]
                if not viewer then
                    viewersExist = false
                    break
                end
            end
        end
        
        if viewersExist then
            if IT:ExtractCurrentSpecSpells() then
                IT:BuildAllTrackers()
                
                -- Hide Blizzard Essential/Utility viewers (IT replaces them visually)
                -- BuffIconCooldownViewer is NOT touched - continues working for buffs
                IT:HideBlizzardEssentialUtility()
                
                -- Note: CooldownContainers still runs for buffs (secret aura values)
                -- It now skips essential/utility when IT setting is enabled
                
                IT:RegisterWithLayoutMode()  -- Register with Layout mode for dragging
                
                -- Apply saved/inherited positions from Layout
                if TUICD.Layout and TUICD.Layout.LoadElementPosition then
                    for trackerKey, _ in pairs(TRACKER_TYPES) do
                        local elementID = "IT_" .. trackerKey
                        TUICD.Layout:LoadElementPosition(elementID)
                    end
                    dprint("Applied Layout positions to IT trackers")
                end
                
                -- Register callback for profile changes (only once)
                if not layoutCallbackRegistered and TUICD.Layout and TUICD.Layout.RegisterCallback then
                    TUICD.Layout:RegisterCallback("OnPositionsRefreshed", function()
                        if not enabled then return end
                        dprint("Layout positions refreshed (profile load?), checking for legacy inheritance")
                        -- Re-check for legacy position inheritance (in case loaded profile doesn't have IT positions)
                        for trackerKey, _ in pairs(TRACKER_TYPES) do
                            local elementID = "IT_" .. trackerKey
                            InheritLegacyPosition(TUICD.Layout, elementID)
                        end
                        -- Apply positions to IT trackers
                        for trackerKey, _ in pairs(TRACKER_TYPES) do
                            local elementID = "IT_" .. trackerKey
                            TUICD.Layout:LoadElementPosition(elementID)
                        end
                        dprint("Applied refreshed positions to IT trackers")
                    end)
                    layoutCallbackRegistered = true
                end
                
                RegisterCooldownEvents()
                RegisterSettingsEvents()  -- Phase 1: Listen for settings changes
                pcall(UpdateAllCooldowns)
                pcall(UpdateAllVisibility)  -- Initial visibility check
                enabled = true
                enabling = false
                pendingEnableTicker = nil
                TUICD.IndependentTrackersActive = true
                TUICD:Print("|cff00ff00Independent Trackers enabled!|r")
            else
                enabling = false
                pendingEnableTicker = nil
                TUICD:Print("|cffff0000Extraction failed - try out of combat|r")
            end
        else
            dprint("Viewers not ready, retrying... (attempt", retryCount, ")")
            pendingEnableTicker = C_Timer.NewTimer(0.5, TryExtract)
        end
    end
    
    pendingEnableTicker = C_Timer.NewTimer(1.0, TryExtract)
    initialized = true
end

function IT:Disable()
    -- Cancel any pending enable operation
    if pendingEnableTicker then
        pendingEnableTicker:Cancel()
        pendingEnableTicker = nil
    end
    enabling = false
    
    if not enabled then
        dprint("Independent Trackers already disabled")
        return
    end
    
    -- Stop events and ticker first
    UnregisterCooldownEvents()
    UnregisterSettingsEvents()
    self:UnregisterFromLayoutMode()
    
    -- Properly destroy icon frames (not just hide)
    for trackerKey, icons in pairs(iconFrames) do
        if icons then
            for spellID, iconFrame in pairs(icons) do
                if iconFrame then
                    iconFrame:Hide()
                    iconFrame:ClearAllPoints()
                    -- Don't set parent to nil - just hide and clear points
                end
            end
        end
    end
    wipe(iconFrames)
    
    -- Hide tracker frames but DON'T destroy them
    -- WoW crashes if we try to reuse frames that had SetParent(nil) called
    for trackerKey, frame in pairs(trackerFrames) do
        if frame then
            frame:Hide()
            frame:ClearAllPoints()
        end
    end
    -- Don't wipe trackerFrames - reuse them on re-enable
    
    -- Clear layout wrappers since they reference the frames
    wipe(layoutWrappers)
    
    -- Clear cached spells so we re-extract on next enable
    wipe(cachedSpells)
    
    -- Restore Blizzard viewers (Essential/Utility become visible again)
    self:RestoreBlizzardViewers()
    
    -- Re-register CooldownContainers with Layout if needed
    -- Since CDM stays enabled, containers already exist - we just restored visibility
    if TUICD.CooldownContainers and TUICD.CooldownContainers:IsEnabled() then
        C_Timer.After(0.3, function()
            pcall(function()
                TUICD.CooldownContainers:RegisterWithLayout()
            end)
        end)
    end
    
    enabled = false
    TUICD.IndependentTrackersActive = false
    TUICD:Print("Independent Trackers disabled")
end

function IT:IsEnabled()
    return enabled
end

-- Get the tracker frame for CooldownHighlights integration
function IT:GetTrackerFrame(trackerKey)
    return trackerFrames[trackerKey]
end

-- Get all icon frames for a tracker (for CooldownHighlights)
function IT:GetIcons(trackerKey)
    return iconFrames[trackerKey]
end

-- Get icon frame by slot index (for CooldownHighlights)
-- Returns the same data format as Cooldowns.GetCustomTrackerEntryBySlot:
-- entry (nil for IT), displayName, displayTexture, trackType, trackID
function IT:GetTrackerEntryBySlot(trackerKey, slotIndex)
    local spells = cachedSpells[trackerKey]
    if not spells or not spells[slotIndex] then
        return nil
    end
    
    local spell = spells[slotIndex]
    
    -- Return same format as Custom Tracker
    return nil,                 -- entry (not used for IT)
           spell.name,          -- displayName
           spell.icon,          -- displayTexture
           "spell",             -- trackType
           spell.spellID        -- trackID
end

-- Get cooldown info for a spell (for CooldownHighlights)
-- Returns: startTime, duration (same as Cooldowns.GetCustomTrackerCooldownInfo)
function IT:GetCooldownInfo(trackType, trackID)
    if trackType ~= "spell" or not trackID then
        return 0, 0
    end
    
    local startTime, duration = 0, 0
    
    -- Try Duration Object API first (Midnight)
    if C_Spell.GetSpellCooldownDuration then
        pcall(function()
            local durationObj = C_Spell.GetSpellCooldownDuration(trackID)
            if durationObj then
                local remaining = durationObj:GetRemainingDuration()
                local total = durationObj:GetDuration()
                if remaining and total and remaining > 0 then
                    duration = total
                    startTime = GetTime() - (total - remaining)
                end
            end
        end)
    end
    
    -- Fallback to traditional API
    if duration == 0 then
        pcall(function()
            local info = C_Spell.GetSpellCooldown(trackID)
            if info and info.startTime and info.duration then
                startTime = info.startTime
                duration = info.duration
            end
        end)
    end
    
    return startTime, duration
end

function IT:Reset()
    self:Disable()
    initialized = false
    enabled = false
    enabling = false
    wipe(cachedSpells)
    wipe(trackerFrames)
    wipe(iconFrames)
    wipe(layoutWrappers)
    TUICD:Print("Independent Trackers reset. Run '/tuicd it enable' to restart.")
end

function IT:Toggle()
    if enabled then
        self:Disable()
    else
        self:Enable()
    end
end

-- Print user-friendly status
function IT:PrintStatus()
    TUICD:Print("|cff00ccff=== Independent Trackers Status ===|r")
    
    if enabled then
        TUICD:Print("Status: |cff00ff00ENABLED|r")
    else
        TUICD:Print("Status: |cffff0000DISABLED|r")
    end
    
    TUICD:Print("Debug Mode: " .. (self.debugMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    
    local specID = GetSpecialization() and GetSpecializationInfo(GetSpecialization()) or 0
    TUICD:Print("Current Spec: " .. tostring(specID))
    
    if enabled then
        TUICD:Print("|cffffd100Cached Spells:|r")
        for trackerKey, spells in pairs(cachedSpells) do
            local count = spells and #spells or 0
            if count > 0 then
                local names = {}
                for i, spell in ipairs(spells) do
                    table.insert(names, spell.name)
                end
                TUICD:Print(string.format("  %s (%d): %s", trackerKey, count, table.concat(names, ", ")))
            else
                TUICD:Print(string.format("  %s: (empty)", trackerKey))
            end
        end
    end
end

-- ============================================================================
-- DEBUG / DIAGNOSTIC
-- ============================================================================

-- Force update all cooldowns (useful for testing per-icon changes)
function IT:ForceUpdate()
    if not enabled then
        TUICD:Print("IT not enabled")
        return
    end
    
    TUICD:Print("Forcing cooldown update for all IT icons...")
    
    local count = 0
    for trackerKey, icons in pairs(iconFrames) do
        for spellID, iconFrame in pairs(icons) do
            -- Reset the last state so debug will print
            iconFrame._lastHasPerIcon = nil
            iconFrame._lastPerIconState = nil
            
            pcall(UpdateIconCooldown, iconFrame)
            count = count + 1
        end
    end
    
    TUICD:Print(string.format("Updated %d icons", count))
end

function IT:DumpState()
    print("|cffffd100=== Independent Trackers State ===|r")
    print("Initialized:", initialized)
    print("Enabled:", enabled)
    
    local specID = GetSpecialization() and GetSpecializationInfo(GetSpecialization()) or 0
    print("Current Spec:", specID)
    
    print("|cffffd100Cached Spells:|r")
    for trackerKey, spells in pairs(cachedSpells) do
        print(string.format("  %s: %d spells", trackerKey, #spells))
        for i, spell in ipairs(spells) do
            print(string.format("    %d. %s (%d)", i, spell.name, spell.spellID))
        end
    end
    
    print("|cffffd100Tracker Frames:|r")
    for trackerKey, frame in pairs(trackerFrames) do
        local shown = frame:IsShown() and "shown" or "hidden"
        local scale = frame:GetScale()
        local w, h = frame:GetSize()
        print(string.format("  %s: %s, size=%.0fx%.0f, scale=%.2f", trackerKey, shown, w, h, scale))
    end
    
    print("|cffffd100Icon Frames:|r")
    for trackerKey, icons in pairs(iconFrames) do
        local count = 0
        local sampleW, sampleH = 0, 0
        for _, icon in pairs(icons) do 
            count = count + 1 
            if sampleW == 0 then
                sampleW, sampleH = icon:GetSize()
            end
        end
        print(string.format("  %s: %d icons, size=%.0fx%.0f", trackerKey, count, sampleW, sampleH))
    end
end

-- Toggle debug mode
function IT:ToggleDebug()
    IT.debugMode = not IT.debugMode
    TUICD:Print("IT Debug mode: " .. (IT.debugMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

-- Manual layout registration command
function IT:ForceLayoutRegister()
    IT.debugMode = true  -- Enable debug for this
    TUICD:Print("Forcing Layout registration...")
    self:RegisterWithLayoutMode()
    IT.debugMode = false
end

-- Phase 1: Dump settings for debugging
function IT:DumpSettings(trackerKey)
    trackerKey = trackerKey or "essential"
    
    print("|cffffd100=== IT Settings: " .. trackerKey .. " ===|r")
    
    -- Layout settings
    print("|cff00ccffLayout:|r")
    local iconW, iconH = GetIconDimensions(trackerKey)
    print(string.format("  Icon Size: %d (calculated: %dx%d)", 
        GetSetting(trackerKey, "iconSize") or 36, iconW, iconH))
    print(string.format("  Aspect Ratio: %s", GetSetting(trackerKey, "aspectRatio") or "1:1"))
    print(string.format("  Columns: %d", GetSetting(trackerKey, "columns") or 8))
    print(string.format("  Spacing: H=%d V=%d", 
        GetSetting(trackerKey, "spacingH") or 2, 
        GetSetting(trackerKey, "spacingV") or 2))
    print(string.format("  Growth: %s / %s", 
        GetSetting(trackerKey, "growDirection") or "RIGHT",
        GetSetting(trackerKey, "growSecondary") or "DOWN"))
    print(string.format("  Alignment: %s", GetSetting(trackerKey, "alignment") or "LEFT"))
    print(string.format("  Reverse Order: %s", tostring(GetSetting(trackerKey, "reverseOrder") or false)))
    print(string.format("  Scale: %.2f", GetSetting(trackerKey, "scale") or 1.0))
    
    -- Custom Grid settings
    print("|cff00ccffCustom Grid:|r")
    print(string.format("  Enabled: %s", tostring(GetSetting(trackerKey, "useCustomGrid") or false)))
    print(string.format("  Pattern: '%s'", GetSetting(trackerKey, "customLayout") or ""))
    print(string.format("  Mode: %s", GetSetting(trackerKey, "customGridMode") or "ROW"))
    print(string.format("  Align: %s", GetSetting(trackerKey, "customGridAlign") or "START"))
    
    -- Position settings
    print("|cff00ccffPosition:|r")
    print(string.format("  Point: %s", GetSetting(trackerKey, "point") or "CENTER"))
    print(string.format("  X: %.1f, Y: %.1f", 
        GetSetting(trackerKey, "x") or 0, 
        GetSetting(trackerKey, "y") or 0))
    
    -- Appearance settings
    print("|cff00ccffAppearance:|r")
    print(string.format("  Zoom: %.2f", GetSetting(trackerKey, "zoom") or 0.08))
    print(string.format("  Opacity: %.2f", GetSetting(trackerKey, "iconOpacity") or 1.0))
    print(string.format("  Show Border: %s", tostring(GetSetting(trackerKey, "showBorder"))))
    print(string.format("  Border Alpha: %.2f", GetSetting(trackerKey, "borderAlpha") or 1.0))
    
    -- Cooldown display settings
    print("|cff00ccffCooldown Display:|r")
    print(string.format("  Show Sweep: %s", tostring(GetSetting(trackerKey, "showSweep"))))
    print(string.format("  Show Countdown: %s", tostring(GetSetting(trackerKey, "showCountdownText"))))
    
    -- Interaction settings
    print("|cff00ccffInteraction:|r")
    print(string.format("  Clickthrough: %s", tostring(GetSetting(trackerKey, "clickthrough") or false)))
    print(string.format("  Show Tooltip: %s", tostring(GetSetting(trackerKey, "showTooltip"))))
    
    -- Visibility settings
    print("|cff00ccffVisibility:|r")
    print(string.format("  Enabled: %s", tostring(GetSetting(trackerKey, "visibilityEnabled") or false)))
    print(string.format("  Show In Combat: %s", tostring(GetSetting(trackerKey, "showInCombat"))))
    print(string.format("  Show Out of Combat: %s", tostring(GetSetting(trackerKey, "showOutOfCombat"))))
    print(string.format("  Show Solo: %s", tostring(GetSetting(trackerKey, "showSolo"))))
    print(string.format("  Show In Party: %s", tostring(GetSetting(trackerKey, "showInParty"))))
    print(string.format("  Show In Raid: %s", tostring(GetSetting(trackerKey, "showInRaid"))))
    print(string.format("  Show In Instance: %s", tostring(GetSetting(trackerKey, "showInInstance"))))
    print(string.format("  Show Has Target: %s", tostring(GetSetting(trackerKey, "showHasTarget"))))
end

-- Test visibility calculation
function IT:TestVisibility(trackerKey)
    trackerKey = trackerKey or "essential"
    
    print("|cffffd100=== IT Visibility Test: " .. trackerKey .. " ===|r")
    
    -- Current player state
    local state = GetPlayerState()
    print("|cff00ccffCurrent State:|r")
    print(string.format("  In Combat: %s", tostring(state.inCombat)))
    print(string.format("  In Group: %s", tostring(state.inGroup)))
    print(string.format("  In Raid: %s", tostring(state.inRaid)))
    print(string.format("  In Instance: %s", tostring(state.inInstance)))
    print(string.format("  Is Solo: %s", tostring(state.isSolo)))
    print(string.format("  Has Target: %s", tostring(state.hasTarget)))
    print(string.format("  Is Mounted: %s", tostring(state.isMounted)))
    
    -- Settings
    print("|cff00ccffSettings:|r")
    local visEnabled = GetSetting(trackerKey, "visibilityEnabled")
    print(string.format("  Visibility Enabled: %s", tostring(visEnabled)))
    
    -- Result
    local shouldShow = ShouldBeVisible(trackerKey)
    print("|cff00ccffResult:|r")
    print(string.format("  ShouldBeVisible: %s", tostring(shouldShow)))
    
    -- Actual frame state
    local frame = trackerFrames[trackerKey]
    if frame then
        print(string.format("  Frame Alpha: %.2f", frame:GetAlpha()))
        print(string.format("  Frame IsShown: %s", tostring(frame:IsShown())))
    end
    
    -- Force update
    print("|cff00ff00Forcing visibility update...|r")
    UpdateTrackerVisibility(trackerKey)
    if frame then
        print(string.format("  New Frame Alpha: %.2f", frame:GetAlpha()))
    end
end

-- Debug: Dump spell order for a tracker
function IT:DumpSpellOrder(trackerKey)
    trackerKey = trackerKey or "essential"
    
    print("|cffffd100=== IT Spell Order: " .. trackerKey .. " ===|r")
    
    local spells = cachedSpells[trackerKey]
    if not spells or #spells == 0 then
        print("|cffff0000No spells cached for " .. trackerKey .. "|r")
        return
    end
    
    print(string.format("Cached %d spells:", #spells))
    for i, spell in ipairs(spells) do
        print(string.format("  [%d] cdmIdx=%s: %s (%d)", 
            i, 
            tostring(spell.cdmIndex or "?"), 
            spell.name or "?", 
            spell.spellID or 0))
    end
    
    -- Also show icon frame order
    local icons = iconFrames[trackerKey]
    if icons then
        print("|cff00ccffIcon Frame Order:|r")
        local ordered = {}
        for spellID, iconFrame in pairs(icons) do
            table.insert(ordered, iconFrame)
        end
        table.sort(ordered, function(a, b) return (a.index or 0) < (b.index or 0) end)
        for i, icon in ipairs(ordered) do
            print(string.format("  [%d] index=%d: %s (%d)", 
                i, icon.index or 0, icon.name or "?", icon.spellID or 0))
        end
    end
end

-- Phase 1: Test settings application
function IT:TestSettings(trackerKey, setting, value)
    trackerKey = trackerKey or "essential"
    
    if not setting then
        print("|cffffd100Usage: IT:TestSettings('trackerKey', 'setting', value)|r")
        print("Example: IT:TestSettings('essential', 'iconSize', 48)")
        print("         IT:TestSettings('utility', 'columns', 6)")
        return
    end
    
    print(string.format("|cff00ccff[IT]|r Testing: %s.%s = %s", trackerKey, setting, tostring(value)))
    
    -- Set the value
    SetSetting(trackerKey, setting, value)
    
    -- Force refresh
    if enabled then
        self:RefreshTrackerAppearance(trackerKey)
        print("|cff00ff00Refreshed " .. trackerKey .. " tracker|r")
    else
        print("|cffff8800IT not enabled - setting saved but not applied|r")
    end
end

function IT:SetDebugMode(enable)
    IT.debugMode = enable
    TUICD:Print("IT Debug mode: " .. (enable and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end
-- ============================================================================
-- PER-ICON SETTINGS API
-- Delegates to CooldownHighlights which manages standalone per-icon frames.
-- IT icons use slot-index based settings, same as Essential/Utility CDM.
-- ============================================================================

-- Helper: Find slot index for a spellID
local function SpellIDToSlotIndex(trackerKey, spellID)
    local spells = cachedSpells[trackerKey]
    if not spells then return nil end
    for i, spell in ipairs(spells) do
        if spell.spellID == spellID then
            return i
        end
    end
    return nil
end

-- Helper: Find spellID for a slot index
local function SlotIndexToSpellID(trackerKey, slotIndex)
    local spells = cachedSpells[trackerKey]
    if not spells or not spells[slotIndex] then return nil end
    return spells[slotIndex].spellID
end

-- Get CooldownHighlights module
local function GetHighlights()
    return TUICD.CooldownHighlights
end

-- Check if per-icon is enabled for a spell (via CooldownHighlights)
function IT:IsPerIconEnabled(trackerKey, spellID)
    local highlights = GetHighlights()
    if not highlights then return false end
    
    local slotIndex = SpellIDToSlotIndex(trackerKey, spellID)
    if not slotIndex then return false end
    
    return highlights:IsEnabled(trackerKey, slotIndex)
end

-- Enable/disable per-icon for a spell (via CooldownHighlights)
function IT:SetPerIconEnabled(trackerKey, spellID, enable)
    local highlights = GetHighlights()
    if not highlights then
        TUICD:PrintError("CooldownHighlights not available")
        return
    end
    
    -- Find slot index
    local slotIndex = SpellIDToSlotIndex(trackerKey, spellID)
    if not slotIndex then
        TUICD:PrintError("Spell not found in tracker")
        return
    end
    
    -- Get spell name for feedback
    local spellName = "Unknown"
    local spells = cachedSpells[trackerKey] or {}
    if spells[slotIndex] then
        spellName = spells[slotIndex].name
    end
    
    -- Delegate to CooldownHighlights (use EnableHighlight, not SetPerIconEnabled)
    highlights:EnableHighlight(trackerKey, slotIndex, enable)
    
    if enable then
        TUICD:Print(string.format("Per-icon |cff00ff00ENABLED|r: %s (slot %d)", spellName, slotIndex))
        TUICD:Print("  Use |cffffff00/tuicd layout|r to position the icon")
    else
        TUICD:Print(string.format("Per-icon |cffff0000DISABLED|r: %s (slot %d)", spellName, slotIndex))
    end
end

-- These are placeholders - actual functionality through CooldownHighlights settings panel
function IT:GetPerIconSetting(trackerKey, spellID, key)
    -- Placeholder - CooldownHighlights manages actual settings
    return nil
end

function IT:SetPerIconSetting(trackerKey, spellID, key, value)
    -- Placeholder - CooldownHighlights manages actual settings
end

-- Convenience: Show/Hide icon completely (hidden icons aren't built at all)
function IT:IsIconHidden(trackerKey, spellID)
    return IsIconHidden(trackerKey, spellID)
end

function IT:SetIconHidden(trackerKey, spellID, hidden)
    SetPerIconSetting(trackerKey, spellID, "hidden", hidden)
    -- Rebuild tracker to reflect change
    if enabled then
        self:BuildTracker(trackerKey)
    end
end

-- Convenience: Get/Set show state per active/inactive state
function IT:GetShowState(trackerKey, spellID, state)
    local key = state == "active" and "showActive" or "showInactive"
    local value = GetPerIconSetting(trackerKey, spellID, key)
    if value == nil then return true end  -- Default: show both states
    return value
end

function IT:SetShowState(trackerKey, spellID, state, show)
    local key = state == "active" and "showActive" or "showInactive"
    SetPerIconSetting(trackerKey, spellID, key, show)
    
    -- Provide feedback
    local spellName = "Unknown"
    local spells = cachedSpells[trackerKey] or {}
    for _, spell in ipairs(spells) do
        if spell.spellID == spellID then
            spellName = spell.name
            break
        end
    end
    
    local showStr = show and "|cff00ff00SHOW|r" or "|cffff0000HIDE|r"
    TUICD:Print(string.format("Per-icon %s when %s: %s", spellName, state, showStr))
end

-- Convenience: Get/Set opacity per active/inactive state
function IT:GetOpacity(trackerKey, spellID, state)
    local key = state == "active" and "activeOpacity" or "inactiveOpacity"
    return GetPerIconSetting(trackerKey, spellID, key) or 1.0
end

function IT:SetOpacity(trackerKey, spellID, state, opacity)
    local key = state == "active" and "activeOpacity" or "inactiveOpacity"
    SetPerIconSetting(trackerKey, spellID, key, opacity)
end

-- Convenience: Get/Set saturation per active/inactive state
function IT:GetSaturation(trackerKey, spellID, state)
    local key = state == "active" and "activeSaturated" or "inactiveSaturated"
    local value = GetPerIconSetting(trackerKey, spellID, key)
    if value == nil then
        -- Default: saturated when active, desaturated when inactive
        return state == "active"
    end
    return value
end

function IT:SetSaturation(trackerKey, spellID, state, saturated)
    local key = state == "active" and "activeSaturated" or "inactiveSaturated"
    SetPerIconSetting(trackerKey, spellID, key, saturated)
end

-- Get list of all spells for a tracker (for UI enumeration)
function IT:GetTrackerSpells(trackerKey)
    return cachedSpells[trackerKey] or {}
end

-- ============================================================================
-- SETTINGS MIGRATION: CDM Highlights -> IT Per-Icon Settings
-- Migrates per-icon settings from CooldownHighlights (slot-indexed) to
-- IT system (spellID-keyed) so settings follow the ability
-- ============================================================================

-- Migrate settings from CooldownHighlights for a single tracker
function IT:MigrateHighlightsToIT(trackerKey)
    local CooldownHighlights = TUICD.CooldownHighlights
    if not CooldownHighlights then
        TUICD:Print("|cffff0000CooldownHighlights module not found|r")
        return false
    end
    
    local spells = cachedSpells[trackerKey]
    if not spells or #spells == 0 then
        TUICD:Print("|cffff0000No spells cached for " .. trackerKey .. ". Enable IT first.|r")
        return false
    end
    
    local migratedCount = 0
    
    for i, spellData in ipairs(spells) do
        local slotIndex = spellData.cdmIndex or i
        local spellID = spellData.spellID
        
        -- Check if slot has any per-icon settings in CooldownHighlights
        if CooldownHighlights:IsEnabled(trackerKey, slotIndex) then
            -- Enable per-icon for this spell
            SetPerIconSetting(trackerKey, spellID, "enabled", true)
            
            -- Migrate show states
            local showActive = CooldownHighlights:GetShowState(trackerKey, slotIndex, "active")
            local showInactive = CooldownHighlights:GetShowState(trackerKey, slotIndex, "inactive")
            SetPerIconSetting(trackerKey, spellID, "showActive", showActive)
            SetPerIconSetting(trackerKey, spellID, "showInactive", showInactive)
            
            -- Migrate opacity
            local activeOpacity = CooldownHighlights:GetOpacity(trackerKey, slotIndex, "active")
            local inactiveOpacity = CooldownHighlights:GetOpacity(trackerKey, slotIndex, "inactive")
            SetPerIconSetting(trackerKey, spellID, "activeOpacity", activeOpacity)
            SetPerIconSetting(trackerKey, spellID, "inactiveOpacity", inactiveOpacity)
            
            -- Migrate saturation
            local activeSaturated = CooldownHighlights:GetSaturation(trackerKey, slotIndex, "active")
            local inactiveSaturated = CooldownHighlights:GetSaturation(trackerKey, slotIndex, "inactive")
            SetPerIconSetting(trackerKey, spellID, "activeSaturated", activeSaturated)
            SetPerIconSetting(trackerKey, spellID, "inactiveSaturated", inactiveSaturated)
            
            -- Migrate hidden state
            local isHidden = CooldownHighlights:IsIconHidden(trackerKey, slotIndex)
            SetPerIconSetting(trackerKey, spellID, "hidden", isHidden)
            
            migratedCount = migratedCount + 1
            dprint(string.format("Migrated per-icon settings for %s (%d) from slot %d", spellData.name, spellID, slotIndex))
        end
    end
    
    TUICD:Print(string.format("|cff00ff00Migrated %d per-icon settings from %s highlights to IT|r", migratedCount, trackerKey))
    
    -- Rebuild tracker to apply migrated hidden icons
    if enabled then
        self:BuildTracker(trackerKey)
    end
    
    return true
end

-- Migrate all Essential/Utility highlights to IT
function IT:MigrateAllHighlightsToIT()
    local success = true
    for trackerKey, config in pairs(TRACKER_TYPES) do
        if config.source == "cdm" then
            if not self:MigrateHighlightsToIT(trackerKey) then
                success = false
            end
        end
    end
    return success
end

-- ============================================================================
-- DEBUG/TEST FUNCTIONS
-- ============================================================================

-- List all spells in a tracker with their current per-icon settings
function IT:ListSpells(trackerKey)
    trackerKey = trackerKey or "essential"
    local spells = cachedSpells[trackerKey]
    
    if not spells or #spells == 0 then
        TUICD:Print("No spells for " .. trackerKey .. " - is IT enabled?")
        return
    end
    
    TUICD:Print("|cffffd100" .. trackerKey .. " spells:|r")
    for i, spellData in ipairs(spells) do
        local spellID = spellData.spellID
        local hasPerIcon = GetPerIconSetting(trackerKey, spellID, "enabled") == true
        local isHidden = IsIconHidden(trackerKey, spellID)
        
        local status = ""
        if isHidden then
            status = " |cffff0000[HIDDEN]|r"
        elseif hasPerIcon then
            status = " |cff00ff00[PER-ICON]|r"
        end
        
        TUICD:Print(string.format("  %d. |cffffffff%s|r (%d)%s", i, spellData.name or "???", spellID, status))
    end
end

-- Test per-icon settings on a specific spell
function IT:TestPerIcon(trackerKey, spellIndex, setting, value)
    trackerKey = trackerKey or "essential"
    local spells = cachedSpells[trackerKey]
    
    if not spells or #spells == 0 then
        TUICD:Print("No spells - run '/tuicd it enable' first")
        return
    end
    
    if not spellIndex then
        TUICD:Print("Usage: /run TUICD.IndependentTrackers:TestPerIcon('essential', 1, 'enabled', true)")
        TUICD:Print("Settings: enabled, showActive, showInactive, activeOpacity, inactiveOpacity, activeSaturated, inactiveSaturated, size")
        self:ListSpells(trackerKey)
        return
    end
    
    local spellData = spells[tonumber(spellIndex)]
    if not spellData then
        TUICD:Print("Invalid spell index: " .. tostring(spellIndex))
        return
    end
    
    local slotIndex = tonumber(spellIndex)
    local spellName = spellData.name
    
    -- Use CooldownHighlights API (same as Custom Tracker per-icon)
    local highlights = GetHighlights()
    if not highlights then
        TUICD:PrintError("CooldownHighlights not available")
        return
    end
    
    if not setting then
        -- Show current settings
        TUICD:Print("|cffffd100Per-icon settings for " .. spellName .. " (slot " .. slotIndex .. "):|r")
        TUICD:Print("  enabled: " .. tostring(highlights:IsEnabled(trackerKey, slotIndex)))
        TUICD:Print("  showActive: " .. tostring(highlights:GetShowState(trackerKey, slotIndex, "active")))
        TUICD:Print("  showInactive: " .. tostring(highlights:GetShowState(trackerKey, slotIndex, "inactive")))
        TUICD:Print("  activeOpacity: " .. tostring(highlights:GetOpacity(trackerKey, slotIndex, "active")))
        TUICD:Print("  inactiveOpacity: " .. tostring(highlights:GetOpacity(trackerKey, slotIndex, "inactive")))
        TUICD:Print("  activeSaturated: " .. tostring(highlights:GetSaturation(trackerKey, slotIndex, "active")))
        TUICD:Print("  inactiveSaturated: " .. tostring(highlights:GetSaturation(trackerKey, slotIndex, "inactive")))
        TUICD:Print("  activeSize: " .. tostring(highlights:GetSize(trackerKey, slotIndex, "active")))
        TUICD:Print("  inactiveSize: " .. tostring(highlights:GetSize(trackerKey, slotIndex, "inactive")))
        return
    end
    
    -- Set the value using appropriate CooldownHighlights method
    if setting == "enabled" then
        highlights:EnableHighlight(trackerKey, slotIndex, value)
    elseif setting == "showActive" then
        highlights:SetShowState(trackerKey, slotIndex, "active", value)
    elseif setting == "showInactive" then
        highlights:SetShowState(trackerKey, slotIndex, "inactive", value)
    elseif setting == "activeOpacity" then
        highlights:SetOpacity(trackerKey, slotIndex, "active", value)
    elseif setting == "inactiveOpacity" then
        highlights:SetOpacity(trackerKey, slotIndex, "inactive", value)
    elseif setting == "activeSaturated" then
        highlights:SetSaturation(trackerKey, slotIndex, "active", value)
    elseif setting == "inactiveSaturated" then
        highlights:SetSaturation(trackerKey, slotIndex, "inactive", value)
    elseif setting == "size" or setting == "activeSize" then
        highlights:SetSize(trackerKey, slotIndex, "active", value)
        highlights:SetSize(trackerKey, slotIndex, "inactive", value)
    else
        TUICD:Print("Unknown setting: " .. tostring(setting))
        return
    end
    
    TUICD:Print(string.format("Set %s.%s = %s for %s (slot %d)", trackerKey, setting, tostring(value), spellName, slotIndex))
end

-- Quick test: Enable per-icon on first spell and hide it when ready
function IT:QuickTest(trackerKey)
    trackerKey = trackerKey or "essential"
    local spells = cachedSpells[trackerKey]
    
    if not spells or #spells == 0 then
        TUICD:Print("No spells - run '/tuicd it enable' first")
        return
    end
    
    local spellID = spells[1].spellID
    local spellName = spells[1].name
    local slotIndex = 1  -- First spell is always slot 1
    
    -- Use CooldownHighlights API directly (same as Custom Tracker per-icon)
    local highlights = GetHighlights()
    if not highlights then
        TUICD:PrintError("CooldownHighlights not available")
        return
    end
    
    -- Enable the per-icon frame first
    highlights:EnableHighlight(trackerKey, slotIndex, true)
    
    -- Configure settings using CooldownHighlights API
    -- showActive=false (hide when ready), showInactive=true (show on cooldown)
    highlights:SetShowState(trackerKey, slotIndex, "active", false)
    highlights:SetShowState(trackerKey, slotIndex, "inactive", true)
    highlights:SetOpacity(trackerKey, slotIndex, "inactive", 0.7)
    highlights:SetSaturation(trackerKey, slotIndex, "inactive", false)
    
    TUICD:Print("|cffffd100Quick test on " .. spellName .. ":|r")
    TUICD:Print("  - Hidden when ready (showActive=false)")
    TUICD:Print("  - Shows at 70% opacity when on cooldown")
    TUICD:Print("  - Desaturated when on cooldown")
    TUICD:Print("Use |cffffff00/tuicd layout|r to move the standalone icon")
    local displayNames = { essential = "Essential Cooldowns", utility = "Utility Cooldowns" }
    TUICD:Print("Find it as |cffffff00" .. (displayNames[trackerKey] or trackerKey) .. " Icon 1|r")
    TUICD:Print("Run '/run TUICD.IndependentTrackers:ResetPerIcon(\"" .. trackerKey .. "\", 1)' to remove")
end

-- Reset per-icon settings for a spell
function IT:ResetPerIcon(trackerKey, spellIndex)
    trackerKey = trackerKey or "essential"
    local spells = cachedSpells[trackerKey]
    
    if not spells or not spellIndex then
        TUICD:Print("Usage: /run TUICD.IndependentTrackers:ResetPerIcon('essential', 1)")
        return
    end
    
    local spellData = spells[tonumber(spellIndex)]
    if not spellData then
        TUICD:Print("Invalid spell index")
        return
    end
    
    local slotIndex = tonumber(spellIndex)
    
    -- Use CooldownHighlights API to disable
    local highlights = GetHighlights()
    if highlights then
        -- Disable the per-icon (hides/destroys frame)
        highlights:EnableHighlight(trackerKey, slotIndex, false)
        
        -- Reset state settings to defaults
        highlights:SetShowState(trackerKey, slotIndex, "active", nil)
        highlights:SetShowState(trackerKey, slotIndex, "inactive", nil)
        highlights:SetOpacity(trackerKey, slotIndex, "active", nil)
        highlights:SetOpacity(trackerKey, slotIndex, "inactive", nil)
        highlights:SetSaturation(trackerKey, slotIndex, "active", nil)
        highlights:SetSaturation(trackerKey, slotIndex, "inactive", nil)
        highlights:SetSize(trackerKey, slotIndex, "active", nil)
        highlights:SetSize(trackerKey, slotIndex, "inactive", nil)
    end
    
    TUICD:Print("Reset per-icon settings for " .. spellData.name)
end

-- Dump all per-icon settings for a specific spell
function IT:DumpPerIcon(trackerKey, spellIndex)
    trackerKey = trackerKey or "essential"
    local spells = cachedSpells[trackerKey]
    
    if not spells or #spells == 0 then
        TUICD:Print("No spells - run '/tuicd it enable' first")
        return
    end
    
    if not spellIndex then
        self:ListSpells(trackerKey)
        TUICD:Print("Usage: /run TUICD.IndependentTrackers:DumpPerIcon('essential', 1)")
        return
    end
    
    local spellData = spells[tonumber(spellIndex)]
    if not spellData then
        TUICD:Print("Invalid spell index")
        return
    end
    
    local slotIndex = tonumber(spellIndex)
    local highlights = GetHighlights()
    
    TUICD:Print("|cffffd100Per-icon settings for " .. spellData.name .. " (slot " .. slotIndex .. "):|r")
    
    if not highlights then
        TUICD:Print("  CooldownHighlights not available")
        return
    end
    
    -- Show storage key (spellID for IT, slotIndex for others)
    local storageKey = highlights:GetStorageKey(trackerKey, slotIndex)
    TUICD:Print(string.format("  |cff888888Storage key: %s (settings persist across slot changes)|r", tostring(storageKey)))
    
    TUICD:Print(string.format("  enabled = %s", tostring(highlights:IsEnabled(trackerKey, slotIndex))))
    TUICD:Print(string.format("  showActive = %s", tostring(highlights:GetShowState(trackerKey, slotIndex, "active"))))
    TUICD:Print(string.format("  showInactive = %s", tostring(highlights:GetShowState(trackerKey, slotIndex, "inactive"))))
    TUICD:Print(string.format("  activeOpacity = %s", tostring(highlights:GetOpacity(trackerKey, slotIndex, "active"))))
    TUICD:Print(string.format("  inactiveOpacity = %s", tostring(highlights:GetOpacity(trackerKey, slotIndex, "inactive"))))
    TUICD:Print(string.format("  activeSaturated = %s", tostring(highlights:GetSaturation(trackerKey, slotIndex, "active"))))
    TUICD:Print(string.format("  inactiveSaturated = %s", tostring(highlights:GetSaturation(trackerKey, slotIndex, "inactive"))))
    TUICD:Print(string.format("  activeSize = %s", tostring(highlights:GetSize(trackerKey, slotIndex, "active"))))
    TUICD:Print(string.format("  inactiveSize = %s", tostring(highlights:GetSize(trackerKey, slotIndex, "inactive"))))
end

-- Export
TUICD.IndependentTrackers = IT
