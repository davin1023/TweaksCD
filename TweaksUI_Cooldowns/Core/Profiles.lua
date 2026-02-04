-- TUICD Profiles
-- Profile save/load/switch/dirty tracking system (1.5.0+)

local ADDON_NAME, TUICD = ...

TUICD.Profiles = {}
local Profiles = TUICD.Profiles

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PROFILE_VERSION = "1.5.0"

-- Settings that can be hot-applied vs require reload
-- Modules register their capabilities here
local HOT_APPLY_REGISTRY = {}

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

local profileLoadedHash = nil
local lastLoadedProfile = nil
local isDirty = false
local lastLoadedIsBuiltIn = false

-- ============================================================================
-- BUILT-IN PROFILE HELPERS
-- ============================================================================

-- Check if a profile name is a built-in default profile
local function IsBuiltInProfile(name)
    local DefaultProfiles = TUICD.DefaultProfiles
    if DefaultProfiles and DefaultProfiles.IsDefaultProfile then
        return DefaultProfiles:IsDefaultProfile(name)
    end
    return false
end

-- Public version
function Profiles:IsBuiltInProfile(name)
    return IsBuiltInProfile(name)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Deep copy a table
local function DeepCopy(orig)
    if type(orig) ~= "table" then
        return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
        copy[DeepCopy(k)] = DeepCopy(v)
    end
    return copy
end

-- Keys that represent scale values that should be adjusted for resolution
local SCALE_KEYS = {
    ["scale"] = true,
    ["globalScale"] = true,
}

-- Keys that represent sizes that should be adjusted for resolution
-- Note: We're conservative here - only adjust explicit size settings, not things like borderWidth
local SIZE_KEYS = {
    ["iconSize"] = true,
    ["buttonSize"] = true,
}

-- Recursively adjust scale values in a settings table
-- scaleAdjustment: multiplier (e.g., 1.5 means target screen is 50% larger)
local function AdjustScalesInTable(tbl, scaleAdjustment, depth)
    if type(tbl) ~= "table" then return tbl end
    depth = depth or 0
    if depth > 20 then return tbl end  -- Prevent infinite recursion
    
    for key, value in pairs(tbl) do
        if type(value) == "table" then
            AdjustScalesInTable(value, scaleAdjustment, depth + 1)
        elseif type(value) == "number" then
            -- Adjust scale keys
            if SCALE_KEYS[key] then
                tbl[key] = value * scaleAdjustment
            -- Adjust size keys (icon sizes, button sizes)
            elseif SIZE_KEYS[key] then
                tbl[key] = math.floor(value * scaleAdjustment + 0.5)  -- Round to nearest integer
            end
        end
    end
    
    return tbl
end

-- Calculate scale adjustment factor between source and target resolution
-- Returns a multiplier to apply to scale values
local function CalculateScaleAdjustment(sourceWidth, sourceHeight, sourceUIScale)
    if not sourceWidth or not sourceHeight then
        return 1.0
    end
    
    local targetWidth, targetHeight = GetPhysicalScreenSize()
    local targetUIScale = UIParent:GetEffectiveScale()
    
    -- Use height as the primary scaling reference (more consistent for UI)
    -- Calculate "effective" height (pixels / UI scale)
    local sourceEffective = sourceHeight / (sourceUIScale or 1)
    local targetEffective = targetHeight / targetUIScale
    
    -- Scale factor: how much bigger/smaller the target screen is
    local scaleAdjustment = targetEffective / sourceEffective
    
    -- Clamp to reasonable range (0.5x to 2x)
    scaleAdjustment = math.max(0.5, math.min(2.0, scaleAdjustment))
    
    -- Only adjust if difference is significant (more than 10%)
    if math.abs(scaleAdjustment - 1.0) < 0.1 then
        return 1.0
    end
    
    return scaleAdjustment
end

-- Simple hash function for dirty detection
-- Uses string serialization + checksum
-- IMPORTANT: Rounds floats to avoid floating-point precision issues
local function SerializeForHash(tbl, depth)
    depth = depth or 0
    if depth > 50 then return "MAX_DEPTH" end
    
    if type(tbl) ~= "table" then
        if type(tbl) == "number" then
            -- Round to 2 decimal places to avoid floating point precision issues
            return string.format("%.2f", tbl)
        end
        return tostring(tbl)
    end
    
    -- Sort keys for consistent hashing
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    
    local parts = {}
    for _, k in ipairs(keys) do
        local v = tbl[k]
        table.insert(parts, tostring(k) .. "=" .. SerializeForHash(v, depth + 1))
    end
    
    return "{" .. table.concat(parts, ",") .. "}"
end

local function HashSettings(settings)
    local str = SerializeForHash(settings)
    local hash = 0
    for i = 1, #str do
        hash = (hash * 31 + string.byte(str, i)) % 2147483647
    end
    return tostring(hash)
end

-- ============================================================================
-- DATABASE HELPERS
-- ============================================================================

-- Ensure profile storage exists
local function EnsureProfileStorage()
    if not TweaksUI_Cooldowns_DB then
        TweaksUI_Cooldowns_DB = {}
    end
    if not TweaksUI_Cooldowns_DB.profiles then
        TweaksUI_Cooldowns_DB.profiles = {}
    end
    if not TweaksUI_Cooldowns_DB.global then
        TweaksUI_Cooldowns_DB.global = {}
    end
    if not TweaksUI_Cooldowns_DB.global.presetSettings then
        TweaksUI_Cooldowns_DB.global.presetSettings = {
            autoBackup = true,
            maxBackupsPerModule = 3,
        }
    end
end

-- Ensure character profile tracking exists
local function EnsureCharProfileInfo()
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = {}
    end
    if not TweaksUI_Cooldowns_CharDB.profileInfo then
        TweaksUI_Cooldowns_CharDB.profileInfo = {}
    end
    if not TweaksUI_Cooldowns_CharDB.specProfiles then
        TweaksUI_Cooldowns_CharDB.specProfiles = {
            enabled = false,
        }
    end
end

-- ============================================================================
-- OLD PROFILE FORMAT CONVERSION
-- ============================================================================

-- Convert old TUI:CD 2.x profile format to 3.0 format
-- Old format:
--   trackers = { essential = {...}, utility = {...}, buffs = {...}, customTrackers = {...} }
--   containerPositions = { essential = {point, x, y}, ... }
--   buffHighlights, essentialHighlights, utilityHighlights, customHighlights
--   customEntries = {...}
-- New format:
--   modules = { cooldowns = {...}, layout = { elements = {...} } }
--   enabled = { cooldowns = true }
--   buffHighlights, essentialHighlights, utilityHighlights, customHighlights
--   cooldowns = { customEntries = {...} }
local function ConvertOldProfileFormat(profileData)
    if not profileData then return profileData end
    
    -- Check if this is old format (has trackers but no modules)
    local isOldFormat = profileData.trackers ~= nil and profileData.modules == nil
    
    if not isOldFormat then
        return profileData  -- Already new format
    end
    
    TUICD:PrintDebug("Converting old profile format to 3.0 format...")
    
    local converted = {
        modules = {
            cooldowns = {},
            layout = {
                elements = {},
                dataVersion = 4,  -- BOTTOMLEFT absolute format
            },
        },
        enabled = {
            cooldowns = true,
        },
    }
    
    -- Convert tracker settings
    if profileData.trackers then
        for trackerKey, trackerSettings in pairs(profileData.trackers) do
            converted.modules.cooldowns[trackerKey] = DeepCopy(trackerSettings)
        end
    end
    
    -- Convert container positions to layout elements
    local containerToElementId = {
        essential = "EssentialCooldownViewer_TUIWrapper",
        utility = "UtilityCooldownViewer_TUIWrapper",
        buffs = "BuffIconCooldownViewer_TUIWrapper",
        customTrackers = "CustomTracker_TUIWrapper",
    }
    
    if profileData.containerPositions then
        for key, pos in pairs(profileData.containerPositions) do
            local elementId = containerToElementId[key]
            if elementId and pos then
                converted.modules.layout.elements[elementId] = {
                    point = pos.point or "CENTER",
                    x = pos.x or 0,
                    y = pos.y or 0,
                    scale = pos.scale or 1,
                }
            end
        end
    end
    
    -- Copy highlight settings (these are the same format)
    if profileData.buffHighlights then
        converted.buffHighlights = DeepCopy(profileData.buffHighlights)
    end
    if profileData.essentialHighlights then
        converted.essentialHighlights = DeepCopy(profileData.essentialHighlights)
    end
    if profileData.utilityHighlights then
        converted.utilityHighlights = DeepCopy(profileData.utilityHighlights)
    end
    if profileData.customHighlights then
        converted.customHighlights = DeepCopy(profileData.customHighlights)
    end
    
    -- Convert custom entries
    if profileData.customEntries then
        converted.cooldowns = {
            customEntries = DeepCopy(profileData.customEntries),
        }
    end
    
    -- Copy docks if present (may not exist in very old profiles)
    if profileData.docks then
        converted.docks = DeepCopy(profileData.docks)
    end
    
    -- Copy metadata if present
    if profileData.savedAt then
        converted.savedAt = profileData.savedAt
    end
    if profileData.addonVersion then
        converted.addonVersion = profileData.addonVersion
    end
    if profileData.importedFrom then
        converted.importedFrom = profileData.importedFrom
    end
    
    TUICD:PrintDebug("Profile format conversion complete.")
    return converted
end

-- Migrate all stored profiles from old format to new format (one-time at load)
local function MigrateStoredProfiles()
    EnsureProfileStorage()
    
    if not TweaksUI_Cooldowns_DB.profiles then return end
    
    local migratedCount = 0
    for name, profileData in pairs(TweaksUI_Cooldowns_DB.profiles) do
        -- Check if this is old format
        if profileData.trackers ~= nil and profileData.modules == nil then
            TUICD:PrintDebug("Migrating stored profile: " .. name)
            TweaksUI_Cooldowns_DB.profiles[name] = ConvertOldProfileFormat(profileData)
            migratedCount = migratedCount + 1
        end
    end
    
    if migratedCount > 0 then
        TUICD:Print("Migrated " .. migratedCount .. " profile(s) to 3.0 format.")
    end
end

-- ============================================================================
-- CURRENT SETTINGS GATHERING
-- ============================================================================

-- Internal function to gather settings from database
-- skipSync: if true, don't call SyncAllModulesToDatabase (used for dirty checking)
local function GatherCurrentSettings(skipSync)
    EnsureCharProfileInfo()
    
    -- Sync all in-memory settings to database before gathering (unless skipped)
    -- This ensures attachments and other runtime state is persisted
    if not skipSync then
        if TUICD.ProfileImportExport and TUICD.ProfileImportExport.SyncAllModulesToDatabase then
            TUICD.ProfileImportExport:SyncAllModulesToDatabase()
        end
    end
    
    -- Only include cooldowns.customEntries, not runtime data like trackerCache
    local cooldownsData = {}
    if TweaksUI_Cooldowns_CharDB.cooldowns and TweaksUI_Cooldowns_CharDB.cooldowns.customEntries then
        cooldownsData.customEntries = DeepCopy(TweaksUI_Cooldowns_CharDB.cooldowns.customEntries)
    end
    
    -- Gather multiCustom highlight databases dynamically
    -- These are stored as multiCustom1Highlights, multiCustom2Highlights, etc.
    local multiCustomHighlights = {}
    for dbKey, dbData in pairs(TweaksUI_Cooldowns_CharDB) do
        if type(dbKey) == "string" and dbKey:match("^multiCustom%d+Highlights$") then
            multiCustomHighlights[dbKey] = DeepCopy(dbData)
        end
    end
    
    return {
        modules = DeepCopy(TweaksUI_Cooldowns_CharDB.settings or {}),
        enabled = DeepCopy(TweaksUI_Cooldowns_CharDB.modules or {}),
        -- Container positions (UI Frame and Action Bar containers)
        uiFrameContainerPositions = DeepCopy(TweaksUI_Cooldowns_CharDB.uiFrameContainerPositions or {}),
        actionBarContainerPositions = DeepCopy(TweaksUI_Cooldowns_CharDB.actionBarContainerPositions or {}),
        -- Cooldowns custom entries ONLY (tracked abilities per spec) - excludes trackerCache
        cooldowns = cooldownsData,
        -- Per-Icon Highlight settings (standard tracker types)
        buffHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.buffHighlights or {}),
        essentialHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.essentialHighlights or {}),
        utilityHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.utilityHighlights or {}),
        customHighlights = DeepCopy(TweaksUI_Cooldowns_CharDB.customHighlights or {}),
        -- MultiTracker system (Custom Trackers including Essential/Utility scraped from CDM)
        -- Includes: registry (tracker definitions), settings (per-tracker), entries (per-tracker per-spec)
        multiTrackers = DeepCopy(TweaksUI_Cooldowns_CharDB.multiTrackers or {}),
        -- Per-Icon highlights for multiCustom trackers (keyed by dbKey like multiCustom1Highlights)
        multiCustomHighlights = multiCustomHighlights,
        -- Docks settings (Dynamic Docks feature)
        docks = DeepCopy(TweaksUI_Cooldowns_CharDB.docks or {}),
        -- Buff Bars module (stores settings, spells, dock, positions)
        buffBars = DeepCopy(TweaksUI_Cooldowns_CharDB.buffBars or {}),
    }
end

-- Get all current settings as a profile-ready table (with sync)
-- NOTE: Layout positions and snap attachments are stored in modules.layout
-- (via TweaksUI_Cooldowns_CharDB.settings.layout.elements and .attachments)
-- IMPORTANT: Only include data that gets saved/restored in profiles, not runtime data
function Profiles:GetCurrentSettings()
    return GatherCurrentSettings(false)
end

-- Get current settings WITHOUT syncing (for dirty checking only)
-- This prevents the sync from modifying data and causing false dirty detection
function Profiles:GetCurrentSettingsForComparison()
    return GatherCurrentSettings(true)
end

-- Apply settings from a profile table to current character
function Profiles:ApplySettings(profileData, skipReloadCheck)
    if not profileData then return false, "No profile data" end
    
    -- Convert old profile format to 3.0 format if needed
    profileData = ConvertOldProfileFormat(profileData)
    
    EnsureCharProfileInfo()
    
    -- Track what needs reload vs what can hot-apply
    local needsReload = false
    local hotApplied = {}
    
    -- Calculate scale adjustment factor if source resolution is available
    local scaleAdjustment = 1.0
    if profileData.importedFrom then
        scaleAdjustment = CalculateScaleAdjustment(
            profileData.importedFrom.screenWidth,
            profileData.importedFrom.screenHeight,
            profileData.importedFrom.uiScale
        )
        
        if scaleAdjustment ~= 1.0 then
            TUICD:Print(string.format("Adjusting scales by %.0f%% for resolution difference", (scaleAdjustment - 1) * 100))
        end
    end
    
    -- Apply module settings
    if profileData.modules then
        -- Ensure settings table exists
        TweaksUI_Cooldowns_CharDB.settings = TweaksUI_Cooldowns_CharDB.settings or {}
        
        for moduleId, moduleSettings in pairs(profileData.modules) do
            -- Check if this module can hot-apply
            local canHotApply = self:CanModuleHotApply(moduleId)
            
            -- Deep copy settings first
            local processedSettings = DeepCopy(moduleSettings)
            
            -- Special handling for layout module
            -- New exports use BOTTOMLEFT directly, but handle legacy CENTER_REL for backwards compatibility
            if moduleId == "layout" and processedSettings.elements then
                local CenterToScreen = TUICD.CenterToScreen
                for id, pos in pairs(processedSettings.elements) do
                    -- Legacy: convert CENTER_REL to BOTTOMLEFT if present
                    if pos.point == "CENTER_REL" and pos.x and pos.y and CenterToScreen then
                        local absX, absY = CenterToScreen(pos.x, pos.y)
                        local halfWidth, halfHeight = 50, 25
                        local element = TUICD.Layout and TUICD.Layout:GetElement(id)
                        if element and element.tuiFrame and element.tuiFrame.frame then
                            local frame = element.tuiFrame.frame
                            halfWidth = (frame:GetWidth() or 100) / 2
                            halfHeight = (frame:GetHeight() or 50) / 2
                        end
                        processedSettings.elements[id] = {
                            point = "BOTTOMLEFT",
                            x = absX - halfWidth,
                            y = absY - halfHeight,
                            scale = pos.scale,
                        }
                    end
                    -- BOTTOMLEFT positions pass through unchanged
                end
            end
            
            -- Apply scale adjustment to all scale values in the module settings
            if scaleAdjustment ~= 1.0 then
                AdjustScalesInTable(processedSettings, scaleAdjustment)
            end
            
            TweaksUI_Cooldowns_CharDB.settings[moduleId] = processedSettings
            
            -- Notify the module that its settings were changed externally
            -- This invalidates any in-memory settings cache
            local moduleObj = TUICD.ModuleManager and TUICD.ModuleManager:GetModule(moduleId)
            if moduleObj and moduleObj.OnProfileChanged then
                pcall(function() moduleObj:OnProfileChanged("profile_load") end)
            elseif moduleObj and moduleObj.InvalidateSettingsCache then
                pcall(function() moduleObj:InvalidateSettingsCache() end)
            end
            
            if canHotApply and not skipReloadCheck then
                -- Try to hot-apply
                local success = self:TryHotApplyModule(moduleId)
                if success then
                    table.insert(hotApplied, moduleId)
                else
                    needsReload = true
                end
            else
                needsReload = true
            end
        end
    end
    
    -- Apply module enabled states
    if profileData.enabled then
        -- Ensure modules table exists
        TweaksUI_Cooldowns_CharDB.modules = TweaksUI_Cooldowns_CharDB.modules or {}
        
        for moduleId, enabled in pairs(profileData.enabled) do
            TweaksUI_Cooldowns_CharDB.modules[moduleId] = enabled
        end
        needsReload = true  -- Module enable/disable always needs reload
    end
    
    -- Layout positions are stored in modules.layout, so after applying modules
    -- we should try to refresh positions if the Layout module exists
    if profileData.modules and profileData.modules.layout then
        if TUICD.Layout and TUICD.Layout.RefreshAllPositions then
            pcall(function() TUICD.Layout:RefreshAllPositions() end)
        end
        
        -- Reload and apply snap attachments from the new layout settings
        if TUICD.SnapLocking then
            pcall(function() 
                TUICD.SnapLocking:LoadAttachments()
                -- Apply after a short delay to let frames initialize
                C_Timer.After(0.5, function()
                    if TUICD.SnapLocking.ApplyAllAttachments then
                        TUICD.SnapLocking:ApplyAllAttachments()
                    end
                end)
            end)
        end
        
        -- Always need reload for layout changes to fully apply
        needsReload = true
    end
    
    -- Apply container positions (UI Frame Containers)
    if profileData.uiFrameContainerPositions then
        TweaksUI_Cooldowns_CharDB.uiFrameContainerPositions = DeepCopy(profileData.uiFrameContainerPositions)
        -- These require reload to reposition
        needsReload = true
    end
    
    -- Apply container positions (Action Bar Containers)
    if profileData.actionBarContainerPositions then
        TweaksUI_Cooldowns_CharDB.actionBarContainerPositions = DeepCopy(profileData.actionBarContainerPositions)
        -- These require reload to reposition
        needsReload = true
    end
    
    -- Apply cooldowns custom entries
    if profileData.cooldowns then
        TweaksUI_Cooldowns_CharDB.cooldowns = TweaksUI_Cooldowns_CharDB.cooldowns or {}
        -- Only copy customEntries, preserve trackerCache (it's regenerated)
        if profileData.cooldowns.customEntries then
            TweaksUI_Cooldowns_CharDB.cooldowns.customEntries = DeepCopy(profileData.cooldowns.customEntries)
        end
        needsReload = true
    end
    
    -- Apply buff highlights settings
    if profileData.buffHighlights then
        TweaksUI_Cooldowns_CharDB.buffHighlights = DeepCopy(profileData.buffHighlights)
        needsReload = true
    end
    
    -- Apply cooldown tracker per-icon highlight settings
    if profileData.essentialHighlights then
        TweaksUI_Cooldowns_CharDB.essentialHighlights = DeepCopy(profileData.essentialHighlights)
        needsReload = true
    end
    
    if profileData.utilityHighlights then
        TweaksUI_Cooldowns_CharDB.utilityHighlights = DeepCopy(profileData.utilityHighlights)
        needsReload = true
    end
    
    if profileData.customHighlights then
        TweaksUI_Cooldowns_CharDB.customHighlights = DeepCopy(profileData.customHighlights)
        needsReload = true
    end
    
    -- Apply Docks settings (Dynamic Docks feature)
    if profileData.docks then
        -- Debug: show what we're importing
        if TUICD.PrintDebug then
            TUICD:PrintDebug("Profile docks data found, applying...")
            for k, v in pairs(profileData.docks) do
                if type(v) == "table" then
                    TUICD:PrintDebug(string.format("  Dock key=%s (type=%s): enabled=%s, showBg=%s, showBorder=%s",
                        tostring(k), type(k), tostring(v.enabled), tostring(v.showBackground), tostring(v.showBorder)))
                end
            end
        end
        TweaksUI_Cooldowns_CharDB.docks = DeepCopy(profileData.docks)
        needsReload = true
    else
        if TUICD.PrintDebug then
            TUICD:PrintDebug("Profile has NO docks data!")
        end
    end
    
    -- Apply MultiTracker system data (Custom Trackers including Essential/Utility from CDM)
    -- This includes registry, settings, and per-tracker per-spec entries
    if profileData.multiTrackers then
        if TUICD.PrintDebug then
            TUICD:PrintDebug("Profile multiTrackers data found, applying...")
            if profileData.multiTrackers.registry then
                TUICD:PrintDebug(string.format("  Registry has %d trackers", #profileData.multiTrackers.registry))
            end
        end
        TweaksUI_Cooldowns_CharDB.multiTrackers = DeepCopy(profileData.multiTrackers)
        needsReload = true
    end
    
    -- Apply multiCustom per-icon highlight settings (keyed by dbKey like multiCustom1Highlights)
    if profileData.multiCustomHighlights then
        if TUICD.PrintDebug then
            TUICD:PrintDebug("Profile multiCustomHighlights data found, applying...")
        end
        -- Restore each highlight database to its proper CharDB key
        for dbKey, highlightData in pairs(profileData.multiCustomHighlights) do
            if dbKey:match("^multiCustom%d+Highlights$") then
                TweaksUI_Cooldowns_CharDB[dbKey] = DeepCopy(highlightData)
                if TUICD.PrintDebug then
                    TUICD:PrintDebug(string.format("  Restored %s", dbKey))
                end
            end
        end
        needsReload = true
    end
    
    -- Apply Buff Bars settings (spells, dock settings, positions)
    if profileData.buffBars then
        if TUICD.PrintDebug then
            TUICD:PrintDebug("Profile buffBars data found, applying...")
        end
        TweaksUI_Cooldowns_CharDB.buffBars = DeepCopy(profileData.buffBars)
        needsReload = true
    end
    
    -- Fire settings changed event
    if TUICD.Events then
        TUICD.Events:Fire(TUICD.EVENTS.SETTINGS_CHANGED, nil, nil, nil)
    end
    
    return true, needsReload, hotApplied
end

-- ============================================================================
-- HOT-APPLY SYSTEM
-- ============================================================================

-- Register a module's hot-apply capability
function Profiles:RegisterHotApply(moduleId, config)
    HOT_APPLY_REGISTRY[moduleId] = config or {
        canHotApply = false,
        refreshFunc = nil,
    }
end

-- Check if a module can hot-apply its settings
function Profiles:CanModuleHotApply(moduleId)
    local reg = HOT_APPLY_REGISTRY[moduleId]
    if not reg then return false end
    return reg.canHotApply == true
end

-- Attempt to hot-apply a module's settings
function Profiles:TryHotApplyModule(moduleId)
    local reg = HOT_APPLY_REGISTRY[moduleId]
    if not reg or not reg.canHotApply then
        return false
    end
    
    -- Try the registered refresh function
    if reg.refreshFunc then
        local success = pcall(reg.refreshFunc)
        return success
    end
    
    -- Try to find the module and call RefreshFromSettings
    local moduleObj = TUICD.ModuleManager and TUICD.ModuleManager:GetModule(moduleId)
    if moduleObj and moduleObj.RefreshFromSettings then
        local success = pcall(function() moduleObj:RefreshFromSettings() end)
        return success
    end
    
    return false
end

-- ============================================================================
-- PROFILE OPERATIONS
-- ============================================================================

-- Save current settings as a named profile
function Profiles:SaveProfile(name)
    if not name or name == "" then
        return false, "Profile name is required"
    end
    
    -- Cannot overwrite built-in profiles
    if IsBuiltInProfile(name) then
        return false, "Cannot overwrite built-in profile: " .. name
    end
    
    EnsureProfileStorage()
    
    -- Get current settings WITH sync for saving (captures in-memory state)
    local currentSettings = self:GetCurrentSettings()
    
    TweaksUI_Cooldowns_DB.profiles[name] = {
        version = PROFILE_VERSION,
        created = TweaksUI_Cooldowns_DB.profiles[name] and TweaksUI_Cooldowns_DB.profiles[name].created or time(),
        modified = time(),
        modules = currentSettings.modules,
        enabled = currentSettings.enabled,
        -- Container positions
        uiFrameContainerPositions = currentSettings.uiFrameContainerPositions,
        actionBarContainerPositions = currentSettings.actionBarContainerPositions,
        -- Cooldowns custom entries
        cooldowns = currentSettings.cooldowns,
        -- Per-Icon highlight settings (all tracker types)
        buffHighlights = currentSettings.buffHighlights,
        essentialHighlights = currentSettings.essentialHighlights,
        utilityHighlights = currentSettings.utilityHighlights,
        customHighlights = currentSettings.customHighlights,
        -- MultiTracker system (Custom Trackers including Essential/Utility)
        multiTrackers = currentSettings.multiTrackers,
        -- Per-Icon highlights for multiCustom trackers
        multiCustomHighlights = currentSettings.multiCustomHighlights,
        -- Docks settings (Dynamic Docks feature)
        docks = currentSettings.docks,
    }
    
    -- Update tracking - use comparison function (no sync) for consistent hash baseline
    -- The sync already happened above, so DB is current
    self:SetLoadedProfile(name, self:GetCurrentSettingsForComparison())
    
    TUICD:Print("Profile saved: |cff00ff00" .. name .. "|r")
    return true
end

-- Load a named profile
function Profiles:LoadProfile(name, skipWarning)
    EnsureProfileStorage()
    
    -- Check for built-in default profile first
    local isBuiltIn = IsBuiltInProfile(name)
    local profile
    
    if isBuiltIn then
        local DefaultProfiles = TUICD.DefaultProfiles
        profile = DefaultProfiles:GetProfile(name)
        if not profile then
            return false, "Built-in profile not available: " .. name
        end
    else
        profile = TweaksUI_Cooldowns_DB.profiles[name]
        if not profile then
            return false, "Profile not found: " .. name
        end
    end
    
    -- Check for unsaved changes
    if not skipWarning and self:IsDirty() then
        return false, "DIRTY_WARNING", lastLoadedProfile
    end
    
    -- Apply the profile
    local success, needsReload, hotApplied = self:ApplySettings(profile)
    if not success then
        return false, needsReload  -- needsReload is error message here
    end
    
    -- Mark that a TUI profile has been applied (skip Modern preset check from now on)
    if TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB.tuiProfileApplied = true
    end
    
    -- Update tracking - use comparison function for consistent hash baseline
    lastLoadedIsBuiltIn = isBuiltIn
    self:SetLoadedProfile(name, self:GetCurrentSettingsForComparison())
    
    TUICD:Print("Profile loaded: |cff00ff00" .. name .. "|r" .. (isBuiltIn and " (built-in)" or ""))
    
    if needsReload then
        return true, "NEEDS_RELOAD", hotApplied
    end
    
    return true
end

-- Delete a profile
function Profiles:DeleteProfile(name)
    EnsureProfileStorage()
    
    -- Cannot delete built-in profiles
    if IsBuiltInProfile(name) then
        return false, "Cannot delete built-in profile"
    end
    
    if not TweaksUI_Cooldowns_DB.profiles[name] then
        return false, "Profile not found"
    end
    
    -- Don't allow deleting the currently loaded profile
    if name == lastLoadedProfile then
        return false, "Cannot delete the currently loaded profile"
    end
    
    TweaksUI_Cooldowns_DB.profiles[name] = nil
    TUICD:Print("Profile deleted: |cffff8800" .. name .. "|r")
    return true
end

-- Duplicate a profile
function Profiles:DuplicateProfile(sourceName, newName)
    EnsureProfileStorage()
    
    -- Cannot use a built-in name as the destination
    if IsBuiltInProfile(newName) then
        return false, "Cannot use built-in profile name: " .. newName
    end
    
    if TweaksUI_Cooldowns_DB.profiles[newName] then
        return false, "A profile with that name already exists"
    end
    
    -- Get source from built-in or user profiles
    local source
    if IsBuiltInProfile(sourceName) then
        local DefaultProfiles = TUICD.DefaultProfiles
        source = DefaultProfiles:GetProfile(sourceName)
    else
        source = TweaksUI_Cooldowns_DB.profiles[sourceName]
    end
    
    if not source then
        return false, "Source profile not found"
    end
    
    TweaksUI_Cooldowns_DB.profiles[newName] = {
        version = PROFILE_VERSION,
        created = time(),
        modified = time(),
        modules = DeepCopy(source.modules),
        enabled = DeepCopy(source.enabled),
        uiFrameContainerPositions = DeepCopy(source.uiFrameContainerPositions or {}),
        actionBarContainerPositions = DeepCopy(source.actionBarContainerPositions or {}),
        cooldowns = DeepCopy(source.cooldowns or {}),
        buffHighlights = DeepCopy(source.buffHighlights or {}),
        essentialHighlights = DeepCopy(source.essentialHighlights or {}),
        utilityHighlights = DeepCopy(source.utilityHighlights or {}),
        customHighlights = DeepCopy(source.customHighlights or {}),
        docks = DeepCopy(source.docks or {}),
    }
    
    TUICD:Print("Profile duplicated: |cff00ff00" .. newName .. "|r")
    return true
end

-- Rename a profile
function Profiles:RenameProfile(oldName, newName)
    EnsureProfileStorage()
    
    -- Cannot rename built-in profiles
    if IsBuiltInProfile(oldName) then
        return false, "Cannot rename built-in profile"
    end
    
    -- Cannot rename to a built-in profile name
    if IsBuiltInProfile(newName) then
        return false, "Cannot use built-in profile name: " .. newName
    end
    
    if not TweaksUI_Cooldowns_DB.profiles[oldName] then
        return false, "Profile not found"
    end
    
    if TweaksUI_Cooldowns_DB.profiles[newName] then
        return false, "A profile with that name already exists"
    end
    
    if oldName == newName then
        return true  -- Nothing to do
    end
    
    -- Copy and delete
    TweaksUI_Cooldowns_DB.profiles[newName] = TweaksUI_Cooldowns_DB.profiles[oldName]
    TweaksUI_Cooldowns_DB.profiles[newName].modified = time()
    TweaksUI_Cooldowns_DB.profiles[oldName] = nil
    
    -- Update tracking if this was the loaded profile
    if lastLoadedProfile == oldName then
        lastLoadedProfile = newName
        EnsureCharProfileInfo()
        TweaksUI_Cooldowns_CharDB.profileInfo.basedOn = newName
    end
    
    TUICD:Print("Profile renamed: |cff00ff00" .. newName .. "|r")
    return true
end

-- Get list of all profiles
function Profiles:GetProfileList()
    EnsureProfileStorage()
    
    local list = {}
    
    -- Add built-in profiles first
    local DefaultProfiles = TUICD.DefaultProfiles
    if DefaultProfiles and DefaultProfiles.GetProfileList then
        for _, profile in ipairs(DefaultProfiles:GetProfileList()) do
            table.insert(list, profile)
        end
    end
    
    -- Add user profiles
    for name, data in pairs(TweaksUI_Cooldowns_DB.profiles) do
        table.insert(list, {
            name = name,
            created = data.created,
            modified = data.modified,
            version = data.version,
            isBuiltIn = false,
        })
    end
    
    -- Sort: built-in first (by order), then user profiles alphabetically
    table.sort(list, function(a, b)
        -- Built-in before user
        if a.isBuiltIn and not b.isBuiltIn then
            return true
        elseif not a.isBuiltIn and b.isBuiltIn then
            return false
        end
        -- Both built-in: sort by order
        if a.isBuiltIn and b.isBuiltIn then
            return (a.order or 999) < (b.order or 999)
        end
        -- Both user: sort by name
        return a.name < b.name
    end)
    
    return list
end

-- Check if a profile exists
function Profiles:ProfileExists(name)
    -- Check built-in profiles first
    if IsBuiltInProfile(name) then
        return true
    end
    
    EnsureProfileStorage()
    return TweaksUI_Cooldowns_DB.profiles[name] ~= nil
end

-- ============================================================================
-- DIRTY STATE TRACKING
-- ============================================================================

-- Set the currently loaded profile (called after save/load)
-- Uses GetCurrentSettingsForComparison to avoid sync side effects
function Profiles:SetLoadedProfile(name, settingsSnapshot)
    lastLoadedProfile = name
    -- Use the provided snapshot, or get current settings WITHOUT sync
    profileLoadedHash = HashSettings(settingsSnapshot or self:GetCurrentSettingsForComparison())
    isDirty = false
    
    EnsureCharProfileInfo()
    TweaksUI_Cooldowns_CharDB.profileInfo.basedOn = name
    TweaksUI_Cooldowns_CharDB.profileInfo.loadedAt = time()
    TweaksUI_Cooldowns_CharDB.profileInfo.loadedHash = profileLoadedHash
end

-- Mark settings as potentially dirty (call when any setting changes)
function Profiles:MarkDirty()
    if not profileLoadedHash then
        -- No profile loaded yet, nothing to compare against
        return
    end
    
    -- Use non-syncing version to avoid false positives from sync side effects
    local currentHash = HashSettings(self:GetCurrentSettingsForComparison())
    isDirty = (currentHash ~= profileLoadedHash)
end

-- Mark as clean (after saving)
function Profiles:MarkClean()
    -- Use non-syncing version for consistent comparison baseline
    profileLoadedHash = HashSettings(self:GetCurrentSettingsForComparison())
    isDirty = false
    
    EnsureCharProfileInfo()
    TweaksUI_Cooldowns_CharDB.profileInfo.loadedHash = profileLoadedHash
end

-- Check if there are unsaved changes
function Profiles:IsDirty()
    -- Recalculate to be sure, using non-syncing version
    if profileLoadedHash then
        local currentHash = HashSettings(self:GetCurrentSettingsForComparison())
        isDirty = (currentHash ~= profileLoadedHash)
    end
    return isDirty
end

-- Get dirty state info
function Profiles:GetDirtyState()
    return {
        isDirty = self:IsDirty(),
        basedOn = lastLoadedProfile,
    }
end

-- Get the currently loaded profile name
function Profiles:GetLoadedProfileName()
    return lastLoadedProfile
end

-- ============================================================================
-- SPEC AUTO-SWITCH
-- ============================================================================

-- Get spec profile mapping for current character
function Profiles:GetSpecProfile(specIndex)
    EnsureCharProfileInfo()
    return TweaksUI_Cooldowns_CharDB.specProfiles[specIndex]
end

-- Set spec profile mapping
function Profiles:SetSpecProfile(specIndex, profileName)
    EnsureCharProfileInfo()
    TweaksUI_Cooldowns_CharDB.specProfiles[specIndex] = profileName
end

-- Check if spec auto-switch is enabled
function Profiles:IsSpecAutoSwitchEnabled()
    EnsureCharProfileInfo()
    return TweaksUI_Cooldowns_CharDB.specProfiles.enabled == true
end

-- Set spec auto-switch enabled
function Profiles:SetSpecAutoSwitchEnabled(enabled)
    EnsureCharProfileInfo()
    TweaksUI_Cooldowns_CharDB.specProfiles.enabled = enabled
end

-- Handle spec change event
function Profiles:OnSpecChanged()
    if not self:IsSpecAutoSwitchEnabled() then
        return
    end
    
    local specIndex = GetSpecialization()
    if not specIndex then return end
    
    local profileName = self:GetSpecProfile(specIndex)
    if not profileName then return end
    
    -- Debug output
    TUICD:PrintDebug("OnSpecChanged: specIndex=" .. tostring(specIndex) .. 
        ", profileName=" .. tostring(profileName) .. 
        ", lastLoadedProfile=" .. tostring(lastLoadedProfile) ..
        ", basedOn=" .. tostring(TweaksUI_Cooldowns_CharDB.profileInfo and TweaksUI_Cooldowns_CharDB.profileInfo.basedOn) ..
        ", lastSpecIndex=" .. tostring(TweaksUI_Cooldowns_CharDB.profileInfo and TweaksUI_Cooldowns_CharDB.profileInfo.lastSpecIndex))
    
    -- Check if we're already on this profile
    if profileName == lastLoadedProfile then
        TUICD:PrintDebug("OnSpecChanged: Skipping - already on profile " .. profileName)
        return
    end
    
    -- Also check if this is the same spec we were on at login
    -- This prevents unnecessary reloads when logging in
    if TweaksUI_Cooldowns_CharDB.profileInfo.lastSpecIndex == specIndex then
        -- Same spec as login - check if basedOn matches the spec's assigned profile
        if TweaksUI_Cooldowns_CharDB.profileInfo.basedOn == profileName then
            TUICD:PrintDebug("OnSpecChanged: Skipping - same spec as login with matching profile")
            -- Update lastLoadedProfile to stay in sync
            lastLoadedProfile = profileName
            return
        end
    end
    
    -- Check for dirty state
    if self:IsDirty() then
        -- Show dirty warning dialog for spec switch
        local dialog = StaticPopup_Show("TWEAKSUI_SPEC_SWITCH_DIRTY", profileName)
        if dialog then
            dialog.data = { 
                targetProfile = profileName,
                specIndex = specIndex,
                currentProfile = lastLoadedProfile,
            }
        end
        return
    end
    
    -- Load the profile
    local success, result = self:LoadProfile(profileName, true)  -- skipWarning = true
    if success then
        TUICD:Print("Auto-switched to profile: |cff00ff00" .. profileName .. "|r (spec change)")
        -- Update lastSpecIndex after successful spec change
        TweaksUI_Cooldowns_CharDB.profileInfo.lastSpecIndex = specIndex
        if result == "NEEDS_RELOAD" then
            -- Show reload prompt
            StaticPopup_Show("TWEAKSUI_RELOAD_AFTER_PROFILE")
        end
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function Profiles:Initialize()
    EnsureProfileStorage()
    EnsureCharProfileInfo()
    
    -- Migrate any old-format profiles to 3.0 format (one-time)
    MigrateStoredProfiles()
    
    -- Restore tracking state from character DB
    if TweaksUI_Cooldowns_CharDB.profileInfo.basedOn then
        lastLoadedProfile = TweaksUI_Cooldowns_CharDB.profileInfo.basedOn
        -- IMPORTANT: Recalculate the hash instead of using stored one
        -- This ensures consistency with the current GetCurrentSettingsForComparison method
        -- The stored hash may have been generated with different settings gathering logic
        profileLoadedHash = HashSettings(self:GetCurrentSettingsForComparison())
        -- Update the stored hash to the new value
        TweaksUI_Cooldowns_CharDB.profileInfo.loadedHash = profileLoadedHash
    end
    
    -- Store current spec index at login to prevent unnecessary spec-switch reloads
    local currentSpec = GetSpecialization()
    if currentSpec then
        TweaksUI_Cooldowns_CharDB.profileInfo.lastSpecIndex = currentSpec
        
        -- If spec auto-switch is enabled and this spec has a profile assigned,
        -- ensure lastLoadedProfile matches (to prevent reload on login)
        if self:IsSpecAutoSwitchEnabled() then
            local specProfile = self:GetSpecProfile(currentSpec)
            if specProfile and specProfile == TweaksUI_Cooldowns_CharDB.profileInfo.basedOn then
                -- Already matches, good
                lastLoadedProfile = specProfile
                TUICD:PrintDebug("Profiles: Login spec " .. currentSpec .. " matches basedOn profile: " .. specProfile)
            end
        end
    end
    
    -- Register for spec change events
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- Delay slightly to let game settle
            C_Timer.After(0.5, function()
                Profiles:OnSpecChanged()
            end)
        end
    end)
    
    TUICD:PrintDebug("Profiles system initialized")
end

-- ============================================================================
-- MIGRATION (from 1.4.0 to 1.5.0)
-- ============================================================================

function Profiles:MigrateFrom_1_4_0()
    EnsureProfileStorage()
    EnsureCharProfileInfo()
    
    -- Check if already migrated
    if TweaksUI_Cooldowns_CharDB.profileInfo.migrated_1_5_0 then
        return false
    end
    
    -- Check if this character has settings but no profile
    if TweaksUI_Cooldowns_CharDB.settings and next(TweaksUI_Cooldowns_CharDB.settings) then
        local charName = UnitName("player")
        local defaultProfileName = charName .. " - Default"
        
        -- Create default profile from current settings if one doesn't exist
        if not TweaksUI_Cooldowns_DB.profiles[defaultProfileName] then
            local success = self:SaveProfile(defaultProfileName)
            if success then
                TUICD:Print("|cff00ff80TweaksUI 1.5.0:|r Your settings have been saved as profile: |cffffd700" .. defaultProfileName .. "|r")
            end
        end
        
        -- Set as loaded profile - use comparison function for consistent hash
        self:SetLoadedProfile(defaultProfileName, self:GetCurrentSettingsForComparison())
    end
    
    -- Mark migration complete
    TweaksUI_Cooldowns_CharDB.profileInfo.migrated_1_5_0 = true
    
    return true
end

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

-- Debug function to check why dirty state might be incorrect
function Profiles:DebugDirtyState()
    print("|cff00ff00=== TUICD Profile Dirty State Debug ===|r")
    print("Loaded profile: " .. tostring(lastLoadedProfile))
    print("Stored hash: " .. tostring(profileLoadedHash))
    
    -- Use the same function that IsDirty uses
    local currentSettings = self:GetCurrentSettingsForComparison()
    local currentHash = HashSettings(currentSettings)
    print("Current hash (no sync): " .. tostring(currentHash))
    
    print("Hashes match: " .. tostring(currentHash == profileLoadedHash))
    print("isDirty: " .. tostring(self:IsDirty()))
    
    -- Show what's in current settings (keys only)
    print("|cffFFFF00Current settings keys:|r")
    for k, v in pairs(currentSettings) do
        if type(v) == "table" then
            local count = 0
            for _ in pairs(v) do count = count + 1 end
            print("  " .. k .. " (table with " .. count .. " keys)")
        else
            print("  " .. k .. " = " .. tostring(v))
        end
    end
    
    -- Show cooldowns structure specifically
    print("|cffFFFF00Cooldowns structure:|r")
    if currentSettings.cooldowns then
        for k, v in pairs(currentSettings.cooldowns) do
            if type(v) == "table" then
                local count = 0
                for _ in pairs(v) do count = count + 1 end
                print("  cooldowns." .. k .. " (table with " .. count .. " keys)")
            else
                print("  cooldowns." .. k .. " = " .. tostring(v))
            end
        end
    else
        print("  (empty)")
    end
    
    print("|cff00ff00=== End Debug ===|r")
end

-- Slash command for debugging profile dirty state
SLASH_TUIDIRTY1 = "/tuidirty"
SlashCmdList["TUIDIRTY"] = function()
    TUICD.Profiles:DebugDirtyState()
end

-- Debug command to show docks in a saved profile
SLASH_TUIPROFILEDOCKS1 = "/tuiprofiledocks"
SlashCmdList["TUIPROFILEDOCKS"] = function(profileName)
    if not profileName or profileName == "" then
        print("|cff00ff00TUI Profile Docks:|r Usage: /tuiprofiledocks <profilename>")
        print("Available profiles:")
        if TweaksUI_Cooldowns_DB and TweaksUI_Cooldowns_DB.profiles then
            for name in pairs(TweaksUI_Cooldowns_DB.profiles) do
                print("  - " .. name)
            end
        end
        return
    end
    
    if not TweaksUI_Cooldowns_DB or not TweaksUI_Cooldowns_DB.profiles or not TweaksUI_Cooldowns_DB.profiles[profileName] then
        print("|cffff0000Profile not found: " .. profileName .. "|r")
        return
    end
    
    local profile = TweaksUI_Cooldowns_DB.profiles[profileName]
    print("|cff00ff00=== Docks in Profile: " .. profileName .. " ===|r")
    
    if not profile.docks then
        print("|cffff8800Profile has NO docks data!|r")
        return
    end
    
    for k, v in pairs(profile.docks) do
        print(string.format("Key: %s (type=%s)", tostring(k), type(k)))
        if type(v) == "table" then
            print(string.format("  enabled=%s, showBackground=%s, showBorder=%s",
                tostring(v.enabled), tostring(v.showBackground), tostring(v.showBorder)))
            if v.bgColor then
                print(string.format("  bgColor: r=%.2f, g=%.2f, b=%.2f, a=%.2f",
                    v.bgColor.r or 0, v.bgColor.g or 0, v.bgColor.b or 0, v.bgColor.a or 0))
            else
                print("  bgColor: nil")
            end
        end
    end
    print("|cff00ff00=== End Profile Docks ===|r")
end
