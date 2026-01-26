-- TweaksUI: Cooldowns - Database
-- Character-specific settings storage (1.4.0+)
-- All settings are now stored per-character in TweaksUI_Cooldowns_CharDB

local ADDON_NAME, TUICD = ...

TUICD.Database = {}
local DB = TUICD.Database

-- Default database structure for account-wide data (minimal)
local DATABASE_DEFAULTS = {
    global = {
        version = TUICD.VERSION,
        lastSeenVersion = nil,
        debugMode = false,
        skipSetupValidation = false,  -- Don't show CDM setup popup (2.0.0+)
    },
    -- Legacy profiles preserved for future 1.5.0 profile system redux
    -- These are READ-ONLY references that characters can copy from
    legacyProfiles = {},
}

-- Default character database structure
local CHAR_DATABASE_DEFAULTS = {
    -- Module enable/disable states
    -- TUI:CD modules are enabled by default
    -- Personal Resources is disabled by default (opt-in for ElvUI users)
    modules = {
        cooldowns = true,
        layout = true,
        personalResources = false,
    },
    
    -- All module settings
    settings = {},
    
    -- Cooldown-specific data
    cooldowns = {
        customEntries = {},
        trackerCache = {},
    },
    
    -- Container positions (per-character, part of profile system)
    uiFrameContainerPositions = {},
    actionBarContainerPositions = {},
    
    -- Migration flags
    migrated_1_4_0 = false,
    
    -- First run flag (for loading Basic profile on new characters)
    firstRun = true,
    
    -- Setup validation state (2.0.0+)
    setupValidated = false,   -- CDM settings have been validated
    setupDismissed = false,   -- User dismissed setup popup without fixing
    applyProfileOnReload = nil, -- Profile name to apply on next reload (from setup)
    tuiProfileApplied = false,  -- A TUI profile has been loaded (skip Modern check after this)
}

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

-- Merge defaults into existing table (only adds missing keys)
local function MergeDefaults(existing, defaults)
    if type(existing) ~= "table" or type(defaults) ~= "table" then
        return existing or defaults
    end
    
    for key, defaultValue in pairs(defaults) do
        if existing[key] == nil then
            if type(defaultValue) == "table" then
                existing[key] = DeepCopy(defaultValue)
            else
                existing[key] = defaultValue
            end
        elseif type(defaultValue) == "table" and type(existing[key]) == "table" then
            MergeDefaults(existing[key], defaultValue)
        end
    end
    
    return existing
end

-- Initialize database
function DB:Initialize()
    -- Create or update account-wide saved variables
    if not TweaksUI_Cooldowns_DB then
        TweaksUI_Cooldowns_DB = DeepCopy(DATABASE_DEFAULTS)
    end
    self.db = TweaksUI_Cooldowns_DB
    
    -- Create or update per-character saved variables
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = DeepCopy(CHAR_DATABASE_DEFAULTS)
    end
    self.charDb = TweaksUI_Cooldowns_CharDB
    
    -- Ensure all default keys exist
    self:EnsureDefaults()
    
    -- Run migrations if needed
    self:RunMigrations()
    
    TUICD:PrintDebug("Database initialized (character-specific mode)")
end

-- Ensure all default values exist
function DB:EnsureDefaults()
    -- Ensure global section exists
    if not self.db.global then
        self.db.global = DeepCopy(DATABASE_DEFAULTS.global)
    end
    
    -- Ensure character database has required sections
    if not self.charDb.modules then
        self.charDb.modules = {}
    end
    
    -- TUI:CD CRITICAL: Ensure core modules are enabled by default
    -- This handles existing installs that have an empty modules table
    if self.charDb.modules.cooldowns == nil then
        self.charDb.modules.cooldowns = true
    end
    if self.charDb.modules.layout == nil then
        self.charDb.modules.layout = true
    end
    -- Personal Resources defaults to disabled (opt-in feature)
    if self.charDb.modules.personalResources == nil then
        self.charDb.modules.personalResources = false
    end
    
    if not self.charDb.settings then
        self.charDb.settings = {}
    end
    if not self.charDb.cooldowns then
        self.charDb.cooldowns = {
            customEntries = {},
            trackerCache = {},
        }
    end
    -- Ensure container position tables exist (for profile system)
    if not self.charDb.uiFrameContainerPositions then
        self.charDb.uiFrameContainerPositions = {}
    end
    if not self.charDb.actionBarContainerPositions then
        self.charDb.actionBarContainerPositions = {}
    end
end

-- Run database migrations
function DB:RunMigrations()
    -- Migrate from profile-based to character-based storage
    if not self.charDb.migrated_1_4_0 then
        self:MigrateTo_1_4_0()
    end
    
    -- Update version
    if self.db.global then
        self.db.global.version = TUICD.VERSION
    end
end

-- Migration from 1.3.x profile system to 1.4.0 character-specific
function DB:MigrateTo_1_4_0()
    TUICD:PrintDebug("Running 1.4.0 migration: profile -> character-specific")
    
    local charKey = self:GetCharacterKey()
    local migratedSomething = false
    
    -- Check if old profile system exists AND this character had a profile assignment
    -- Only migrate if this character was actually using TweaksUI before
    if self.db.profiles and self.db.profileAssignments and self.db.profileAssignments[charKey] then
        -- Find this character's old profile
        local oldProfileName = self.db.profileAssignments[charKey]
        
        -- Get the old profile data
        local oldProfile = self.db.profiles[oldProfileName]
        
        -- Copy old profile settings to character settings
        if oldProfile then
            self.charDb.settings = self.charDb.settings or {}
            
            for moduleId, moduleSettings in pairs(oldProfile) do
                -- Only copy if character doesn't already have settings for this module
                if not self.charDb.settings[moduleId] or next(self.charDb.settings[moduleId]) == nil then
                    self.charDb.settings[moduleId] = DeepCopy(moduleSettings)
                    migratedSomething = true
                end
            end
        end
        
        -- Migrate module enable states from global to charDb ONLY for existing users
        if self.db.global and self.db.global.modules then
            for moduleId, enabled in pairs(self.db.global.modules) do
                -- Only migrate if charDb doesn't have this module state yet
                if self.charDb.modules[moduleId] == nil then
                    self.charDb.modules[moduleId] = enabled
                    migratedSomething = true
                end
            end
        end
        
        -- Preserve old profiles for potential future use (rename to legacyProfiles)
        if self.db.profiles and not self.db.legacyProfiles then
            self.db.legacyProfiles = DeepCopy(self.db.profiles)
        end
        
        -- Note: We don't delete the old data, just stop using it
    end
    
    -- Mark migration complete
    self.charDb.migrated_1_4_0 = true
    
    if migratedSomething then
        TUICD:Print("Settings migrated to character-specific storage.")
    end
end

-- Compare version strings (returns -1, 0, or 1)
function DB:CompareVersions(v1, v2)
    local function parseVersion(v)
        local major, minor, patch = v:match("(%d+)%.(%d+)%.(%d+)")
        return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
    end
    
    local m1, n1, p1 = parseVersion(v1)
    local m2, n2, p2 = parseVersion(v2)
    
    if m1 ~= m2 then return m1 < m2 and -1 or 1 end
    if n1 ~= n2 then return n1 < n2 and -1 or 1 end
    if p1 ~= p2 then return p1 < p2 and -1 or 1 end
    return 0
end

-- Get character key for this character
function DB:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

-- ============================================================================
-- MODULE SETTINGS (Character-Specific)
-- ============================================================================

-- Module enable/disable (per-character)
function DB:IsModuleEnabled(moduleId)
    if not self.charDb.modules then
        self.charDb.modules = {}
    end
    return self.charDb.modules[moduleId] == true
end

function DB:SetModuleEnabled(moduleId, enabled, skipEvents)
    if not self.charDb.modules then
        self.charDb.modules = {}
    end
    self.charDb.modules[moduleId] = enabled
    
    -- Only fire events if requested (not for modules requiring reload)
    if not skipEvents then
        if enabled then
            TUICD.Events:Fire(TUICD.EVENTS.MODULE_ENABLED, moduleId)
        else
            TUICD.Events:Fire(TUICD.EVENTS.MODULE_DISABLED, moduleId)
        end
    end
end

-- Get module-specific settings (from character database)
function DB:GetModuleSettings(moduleId)
    if not self.charDb.settings then
        self.charDb.settings = {}
    end
    if not self.charDb.settings[moduleId] then
        self.charDb.settings[moduleId] = {}
    end
    return self.charDb.settings[moduleId]
end

-- Set all module-specific settings at once (replaces entire settings table)
function DB:SetModuleSettings(moduleId, settingsTable)
    if not settingsTable then return end
    if not self.charDb.settings then
        self.charDb.settings = {}
    end
    self.charDb.settings[moduleId] = settingsTable
    TUICD.Events:Fire(TUICD.EVENTS.SETTINGS_CHANGED, moduleId, nil, nil)
end

-- Set a specific module setting
function DB:SetModuleSetting(moduleId, key, value)
    if not self.charDb.settings then
        self.charDb.settings = {}
    end
    if not self.charDb.settings[moduleId] then
        self.charDb.settings[moduleId] = {}
    end
    self.charDb.settings[moduleId][key] = value
    TUICD.Events:Fire(TUICD.EVENTS.SETTINGS_CHANGED, moduleId, key, value)
end

-- Get a specific module setting
function DB:GetModuleSetting(moduleId, key)
    if not self.charDb.settings or not self.charDb.settings[moduleId] then
        return nil
    end
    return self.charDb.settings[moduleId][key]
end

-- ============================================================================
-- GLOBAL SETTINGS (Account-Wide - Minimal)
-- ============================================================================

-- Get global setting
function DB:GetGlobal(key)
    if not self.db.global then return nil end
    return self.db.global[key]
end

-- Set global setting
function DB:SetGlobal(key, value)
    if not self.db.global then
        self.db.global = {}
    end
    self.db.global[key] = value
end

-- ============================================================================
-- CHARACTER-SPECIFIC DATA (Direct Access)
-- ============================================================================

-- Get character database
function DB:GetCharacterDB()
    return self.charDb
end

-- Get character-specific data
function DB:GetCharacterData(key)
    return self.charDb[key]
end

-- Set character-specific data
function DB:SetCharacterData(key, value)
    self.charDb[key] = value
end

-- ============================================================================
-- PROFILE SYSTEM (Disabled for 1.4.0 - Stubs for backwards compatibility)
-- ============================================================================

-- Get current "profile" name - now just returns character name
function DB:GetProfileName()
    return self:GetCharacterKey()
end

-- Profile functions disabled - print informational message
function DB:SetProfile(profileName)
    TUICD:Print("Profile switching is disabled. Settings are now character-specific.")
    TUICD:Print("Profile system will be redesigned in a future update.")
    return false
end

function DB:CreateProfile(profileName, copyFrom)
    TUICD:Print("Profile creation is disabled. Settings are now character-specific.")
    return false
end

function DB:DeleteProfile(profileName)
    TUICD:Print("Profile deletion is disabled. Settings are now character-specific.")
    return false
end

function DB:CopyProfile(sourceName, destName)
    TUICD:Print("Profile copying is disabled. Use Import/Export instead.")
    return false
end

function DB:RenameProfile(oldName, newName)
    TUICD:Print("Profile renaming is disabled. Settings are now character-specific.")
    return false
end

-- Get list of profiles - returns just current character for now
function DB:GetProfileList()
    return { self:GetCharacterKey() }
end

-- Profile exists check
function DB:ProfileExists(profileName)
    return profileName == self:GetCharacterKey()
end

-- Get profile (for backwards compatibility)
function DB:GetProfile(profileName)
    -- Always return character settings
    return self.charDb.settings
end

-- ============================================================================
-- SPEC PROFILES (Disabled for 1.4.0)
-- ============================================================================

function DB:GetSpecProfile(charKey, specIndex)
    return nil
end

function DB:SetSpecProfile(charKey, specIndex, profileName)
    -- No-op
end

function DB:IsSpecProfilesEnabled(charKey)
    return false
end

function DB:ClearSpecProfiles(charKey)
    -- No-op
end

function DB:GetAllSpecProfiles(charKey)
    return {}
end

function DB:OnSpecChanged()
    -- No-op - spec profiles disabled
end

-- ============================================================================
-- EXPORT/IMPORT HELPERS
-- ============================================================================

-- Get all settings for export
function DB:GetAllSettingsForExport()
    return {
        modules = DeepCopy(self.charDb.modules or {}),
        settings = DeepCopy(self.charDb.settings or {}),
    }
end

-- Import all settings
function DB:ImportAllSettings(data)
    if not data then return false end
    
    if data.modules then
        self.charDb.modules = DeepCopy(data.modules)
    end
    
    if data.settings then
        self.charDb.settings = DeepCopy(data.settings)
    end
    
    TUICD.Events:Fire(TUICD.EVENTS.SETTINGS_CHANGED, nil, nil, nil)
    return true
end

-- ============================================================================
-- TRACKER SETTINGS (for CooldownHighlights/BuffHighlights compatibility)
-- These functions provide access to tracker settings stored in the cooldowns module
-- ============================================================================

function DB:GetTrackerSettings(trackerKey)
    -- Get the cooldowns module settings
    local cooldownSettings = self:GetModuleSettings("cooldowns")
    if not cooldownSettings then return {} end
    
    -- Return the specific tracker's settings
    return cooldownSettings[trackerKey] or {}
end

function DB:GetTrackerSetting(trackerKey, key)
    local settings = self:GetTrackerSettings(trackerKey)
    return settings[key]
end

function DB:SetTrackerSetting(trackerKey, key, value)
    -- Get the cooldowns module settings
    local cooldownSettings = self:GetModuleSettings("cooldowns")
    if not cooldownSettings then
        cooldownSettings = {}
    end
    
    -- Ensure the tracker table exists
    if not cooldownSettings[trackerKey] then
        cooldownSettings[trackerKey] = {}
    end
    
    -- Set the value
    cooldownSettings[trackerKey][key] = value
    
    -- Save back to database
    self:SetModuleSettings("cooldowns", cooldownSettings)
    
    -- Fire event
    if TUICD.Events and TUICD.EVENTS then
        TUICD.Events:Fire(TUICD.EVENTS.SETTINGS_CHANGED, "cooldowns", key, value)
    end
end
