-- ============================================================================
-- TweaksUI: Cooldowns - Main
-- Core addon initialization and slash commands
-- Version 3.0.2 - Unified Architecture
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Make TUICD accessible globally
_G.TUICD = TUICD

-- ============================================================================
-- PRINT HELPERS
-- ============================================================================

function TUICD:Print(message)
    print(TUICD.CHAT_PREFIX .. message)
end

function TUICD:PrintError(message)
    print(TUICD.CHAT_PREFIX .. "|cffff0000" .. message .. "|r")
end

function TUICD:PrintDebug(message)
    if self.debugMode then
        print(TUICD.CHAT_PREFIX .. "|cff888888[DEBUG]|r " .. message)
    end
end

-- Central helper to toggle the main settings hub
function TUICD:ToggleSettings()
    if self.Settings and self.Settings.Toggle then
        self.Settings:Toggle()
    else
        self:PrintError("Settings UI not ready yet. Try again in a moment.")
    end
end

-- Debug mode
TUICD.debugMode = false

-- Force all visibility conditions to be bypassed
TUICD.forceAllVisible = false

function TUICD:SetDebugMode(enabled)
    self.debugMode = enabled
    self:Print("Debug mode " .. (enabled and "enabled" or "disabled"))
end

-- Toggle force-all-visible mode (bypasses all visibility conditions)
function TUICD:SetForceAllVisible(enabled, silent)
    self.forceAllVisible = enabled
    
    -- Save to database so it persists across reloads
    if self.Database then
        self.Database:SetGlobal("forceAllVisible", enabled)
    end
    
    if not silent then
        if enabled then
            self:Print("|cff00ff00All visibility conditions BYPASSED|r - everything is now visible")
            self:Print("Use |cffffff00/tuicd showall|r again to restore normal visibility")
        else
            self:Print("|cffff9900Visibility conditions RESTORED|r - normal visibility rules apply")
        end
    end
    
    -- Trigger visibility updates in Cooldowns module
    if self.Cooldowns and self.Cooldowns.UpdateAllTrackerVisibility then
        self.Cooldowns:UpdateAllTrackerVisibility()
    end
end

-- Load forceAllVisible state from database
function TUICD:LoadForceAllVisibleState()
    if self.Database then
        local saved = self.Database:GetGlobal("forceAllVisible")
        if saved then
            self.forceAllVisible = true
            C_Timer.After(2, function()
                self:SetForceAllVisible(true, true)
                self:Print("|cff00ff00Show All mode is ACTIVE|r - use /tuicd showall to disable")
            end)
        end
    end
end

-- ============================================================================
-- LEGACY MIGRATION
-- Migrates data from old TUI:CD 2.x format to new unified format
-- ============================================================================

local function RunLegacyMigration()
    -- Check if we need to migrate from old format
    local charDb = TweaksUI_Cooldowns_CharDB
    if not charDb then return end
    
    -- ========================================================================
    -- DETECT VARIOUS OLD FORMATS
    -- ========================================================================
    
    -- Format 1: Old TUI:CD 2.x format (trackers table directly in CharDB)
    local hasTUICD2xFormat = charDb.trackers ~= nil
    
    -- Format 2: CMT format (check for CMT_CharDB global)
    local hasCMTFormat = _G.CMT_CharDB ~= nil and _G.CMT_CharDB.trackers ~= nil
    
    -- Format 3: Full TweaksUI format (check for TweaksUI_CharDB with cooldowns module)
    local hasTUIFormat = _G.TweaksUI_CharDB ~= nil and 
                         _G.TweaksUI_CharDB.settings ~= nil and 
                         _G.TweaksUI_CharDB.settings.cooldowns ~= nil
    
    -- Check if we've already migrated
    local needsMigration = false
    local migrationSource = nil
    
    if hasTUICD2xFormat then
        if not charDb._migratedFromLegacy then
            needsMigration = true
            migrationSource = "TUI:CD 2.x"
        elseif charDb._legacyMigrationVersion == "3.0.0" then
            -- v3.0.0 migration may have been incomplete
            if not charDb.settings or not charDb.settings.cooldowns then
                needsMigration = true
                migrationSource = "TUI:CD 2.x (incomplete)"
                TUICD:Print("Re-running migration (v3.0.0 migration was incomplete)...")
            elseif not charDb.settings.cooldowns.essential and not charDb.settings.cooldowns.utility then
                needsMigration = true
                migrationSource = "TUI:CD 2.x (incomplete)"
                TUICD:Print("Re-running migration (settings were not properly migrated)...")
            end
        end
    elseif hasCMTFormat then
        if not charDb._migratedFromCMT then
            needsMigration = true
            migrationSource = "CMT"
        end
    elseif hasTUIFormat then
        if not charDb._migratedFromTUI then
            needsMigration = true
            migrationSource = "TweaksUI"
        end
    end
    
    -- ========================================================================
    -- PERFORM MIGRATION
    -- ========================================================================
    
    if needsMigration and migrationSource then
        TUICD:Print("Migrating settings from " .. migrationSource .. " format...")
        
        -- Ensure settings structure exists
        charDb.settings = charDb.settings or {}
        charDb.settings.cooldowns = charDb.settings.cooldowns or {}
        charDb.settings.layout = charDb.settings.layout or {}
        
        local sourceDb = nil
        
        if migrationSource == "CMT" then
            sourceDb = _G.CMT_CharDB
        elseif migrationSource == "TweaksUI" then
            sourceDb = _G.TweaksUI_CharDB.settings.cooldowns
            -- Direct copy of cooldowns settings
            for key, value in pairs(sourceDb) do
                charDb.settings.cooldowns[key] = value
            end
            
            -- Also migrate layout positions from TweaksUI
            local tuiLayout = _G.TweaksUI_CharDB.settings and _G.TweaksUI_CharDB.settings.layout
            if tuiLayout and tuiLayout.elements then
                charDb.settings.layout.elements = charDb.settings.layout.elements or {}
                
                -- Copy cooldown-related element positions
                local cooldownElements = {
                    "EssentialCooldownViewer_TUIWrapper",
                    "UtilityCooldownViewer_TUIWrapper",
                    "BuffIconCooldownViewer_TUIWrapper",
                    "CustomTracker_TUIWrapper",
                }
                
                local migratedCount = 0
                for _, elementId in ipairs(cooldownElements) do
                    if tuiLayout.elements[elementId] then
                        charDb.settings.layout.elements[elementId] = {
                            point = tuiLayout.elements[elementId].point,
                            x = tuiLayout.elements[elementId].x,
                            y = tuiLayout.elements[elementId].y,
                            scale = tuiLayout.elements[elementId].scale,
                        }
                        migratedCount = migratedCount + 1
                        TUICD:PrintDebug("Migrated position: " .. elementId)
                    end
                end
                
                -- Also copy any Dock positions
                for elementId, pos in pairs(tuiLayout.elements) do
                    if elementId:match("^Dock_") then
                        charDb.settings.layout.elements[elementId] = {
                            point = pos.point,
                            x = pos.x,
                            y = pos.y,
                            scale = pos.scale,
                        }
                        migratedCount = migratedCount + 1
                        TUICD:PrintDebug("Migrated dock position: " .. elementId)
                    end
                end
                
                -- CRITICAL: Set dataVersion to 4 so Layout:OnInitialize doesn't clear our positions
                if migratedCount > 0 then
                    charDb.settings.layout.dataVersion = 4
                    TUICD:Print("Migrated " .. migratedCount .. " tracker positions from TweaksUI.")
                end
            end
            
            charDb._migratedFromTUI = true
            charDb._tuiMigrationVersion = TUICD.VERSION
            TUICD:Print("Migration from TweaksUI complete!")
            return
        else
            sourceDb = charDb  -- TUI:CD 2.x format
        end
        
        -- Migrate tracker settings
        if sourceDb.trackers then
            for trackerKey, trackerSettings in pairs(sourceDb.trackers) do
                charDb.settings.cooldowns[trackerKey] = trackerSettings
                TUICD:PrintDebug("Migrated tracker: " .. trackerKey)
            end
        end
        
        -- Migrate highlights
        if sourceDb.buffHighlights then
            charDb.settings.cooldowns.buffHighlights = sourceDb.buffHighlights
        end
        if sourceDb.essentialHighlights then
            charDb.settings.cooldowns.essentialHighlights = sourceDb.essentialHighlights
        end
        if sourceDb.utilityHighlights then
            charDb.settings.cooldowns.utilityHighlights = sourceDb.utilityHighlights
        end
        if sourceDb.customHighlights then
            charDb.settings.cooldowns.customHighlights = sourceDb.customHighlights
        end
        
        -- Migrate custom entries
        if sourceDb.customEntries then
            charDb.settings.cooldowns.customEntries = sourceDb.customEntries
        end
        
        -- Migrate container positions to layout format
        -- Map old container keys to new element IDs
        local containerToElementId = {
            essential = "EssentialCooldownViewer_TUIWrapper",
            utility = "UtilityCooldownViewer_TUIWrapper",
            buffs = "BuffIconCooldownViewer_TUIWrapper",
            customTrackers = "CustomTracker_TUIWrapper",
        }
        
        local migratedPositions = 0
        if sourceDb.containerPositions then
            charDb.settings.layout.elements = charDb.settings.layout.elements or {}
            for key, pos in pairs(sourceDb.containerPositions) do
                local elementId = containerToElementId[key]
                if elementId then
                    charDb.settings.layout.elements[elementId] = {
                        point = pos.point or "CENTER",
                        x = pos.x or 0,
                        y = pos.y or 0,
                        scale = 1,
                    }
                    migratedPositions = migratedPositions + 1
                    TUICD:PrintDebug("Migrated container position: " .. key .. " -> " .. elementId)
                end
            end
        end
        
        -- CRITICAL: Set dataVersion to 4 so Layout:OnInitialize doesn't clear our positions
        if migratedPositions > 0 then
            charDb.settings.layout.dataVersion = 4
            TUICD:Print("Migrated " .. migratedPositions .. " tracker positions.")
        end
        
        -- Mark migration complete
        if migrationSource == "CMT" then
            charDb._migratedFromCMT = true
            charDb._cmtMigrationVersion = TUICD.VERSION
        else
            charDb._migratedFromLegacy = true
            charDb._legacyMigrationVersion = TUICD.VERSION
        end
        
        TUICD:Print("Migration complete! Your settings have been preserved.")
        TUICD:Print("Use |cff00ccff/tuicd|r to open settings.")
    elseif not charDb._migratedFromLegacy and not hasTUICD2xFormat and not hasCMTFormat and not hasTUIFormat then
        -- No old data found and this is a fresh install
        -- Check if user might have old data in WTF folder that didn't load
        if not charDb._checkedForOldData then
            charDb._checkedForOldData = true
            -- Only show this message on first load
            C_Timer.After(5, function()
                if not charDb._migratedFromLegacy then
                    TUICD:Print("|cff888888No previous TUI:CD/CMT data detected.|r")
                    TUICD:Print("|cff888888If you have exported profiles, use |cff00ccff/tuicd|r → Profiles → Import|r")
                end
            end)
        end
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")

local addonLoaded = false
local playerLoggedIn = false

local function Initialize()
    if not addonLoaded or not playerLoggedIn then
        return
    end
    
    TUICD:PrintDebug("Initializing v" .. TUICD.VERSION)
    
    -- Initialize database
    TUICD.Database:Initialize()
    
    -- Run legacy migration before anything else
    RunLegacyMigration()
    
    -- Initialize GlobalScale
    if TUICD.GlobalScale then
        TUICD.GlobalScale:Initialize()
    end
    
    -- Initialize Profiles system
    if TUICD.Profiles then
        TUICD.Profiles:Initialize()
    end
    
    -- Initialize ProfileImportExport
    if TUICD.ProfileImportExport then
        TUICD.ProfileImportExport:Initialize()
    end
    
    -- Initialize media
    TUICD.Media:Initialize()
    
    -- Initialize SnapLocking (standalone utility, not a module)
    if TUICD.SnapLocking and TUICD.SnapLocking.Initialize then
        TUICD.SnapLocking:Initialize()
    end
    
    -- Initialize all registered modules (including Layout and Cooldowns)
    if TUICD.ModuleManager then
        TUICD.ModuleManager:InitializeAll()
        TUICD.ModuleManager:EnableAll()
    end
    
    -- Initialize minimap button
    if TUICD.MinimapButton then
        TUICD.MinimapButton:Initialize()
    end
    
    -- Apply snap attachments after frames are created
    if TUICD.SnapLocking then
        C_Timer.After(2, function()
            TUICD.SnapLocking:ApplyAllAttachments()
        end)
    end
    
    -- Load forceAllVisible state
    TUICD:LoadForceAllVisibleState()
    
    TUICD:Print("v" .. TUICD.VERSION .. " Loaded - Type |cffFFFFFF/tuicd|r to open settings")
end

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        addonLoaded = true
        Initialize()
    elseif event == "PLAYER_LOGIN" then
        playerLoggedIn = true
        Initialize()
    end
end)

-- ============================================================================
-- PLAYER_LOGOUT CLEANUP
-- ============================================================================

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    TUICD:PrintDebug("PLAYER_LOGOUT: Restoring Blizzard frames...")
    
    -- Restore all docked icons
    if TUICD.Docks and TUICD.Docks.RestoreAllDockedIcons then
        pcall(function()
            TUICD.Docks:RestoreAllDockedIcons()
        end)
    end
    
    TUICD:PrintDebug("PLAYER_LOGOUT: Cleanup complete")
end)

-- ============================================================================
-- SLASH COMMAND HANDLER
-- ============================================================================

local function HandleSlashCommand(msg)
    local cmd, args = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()
    
    if cmd == "" or cmd == "settings" or cmd == "options" then
        TUICD:ToggleSettings()
        
    elseif cmd == "help" then
        TUICD:Print("|cff00ccff=== TUI: Cooldowns Commands ===|r")
        TUICD:Print("|cffffff00/tuicd|r - Open settings hub")
        TUICD:Print("|cffffff00/tuicd layout|r - Toggle Layout Mode")
        TUICD:Print("|cffffff00/tuicd patchnotes|r - Show What's New")
        TUICD:Print("|cffffff00/tuicd cdm|r - Open Blizzard Cooldown Manager")
        TUICD:Print("|cffffff00/tuicd showall|r - Toggle visibility bypass")
        TUICD:Print("|cffffff00/tuicd status|r - Show debug status info")
        TUICD:Print("|cffffff00/tuicd debug|r - Toggle debug mode")
        TUICD:Print("|cffffff00/tuicd dock|r - Dock management commands")
        TUICD:Print("|cffffff00/tuicd remigrate|r - Re-import positions from TweaksUI")
        TUICD:Print("|cffffff00/tuicd migrateprofiles|r - Convert old profiles to 3.0 format")
        TUICD:Print("|cffffff00/tuicd version|r - Show version info")
        TUICD:Print("|cffffff00/tuicdresetmulti|r - Reset all multi-trackers")
        TUICD:Print("|cffffff00/cdm|r - Toggle Blizzard Cooldown Settings")
        TUICD:Print("|cffffff00/rl|r - Reload UI")
        
    elseif cmd == "layout" then
        if TUICD.Layout then
            TUICD.Layout:Toggle()
        else
            TUICD:PrintError("Layout module not available")
        end
        
    elseif cmd == "patchnotes" or cmd == "whatsnew" or cmd == "changelog" then
        if TUICD.PatchNotes then
            TUICD.PatchNotes:Show()
        else
            TUICD:PrintError("Patch notes not available")
        end
        
    elseif cmd == "cdm" or cmd == "cooldownmanager" then
        -- Open Blizzard's Cooldown Settings frame
        local cooldownFrame = CooldownViewerSettings or _G["CooldownViewerSettings"]
        if cooldownFrame then
            if cooldownFrame:IsShown() then
                cooldownFrame:Hide()
            else
                cooldownFrame:Show()
            end
        else
            TUICD:PrintError("Cooldown Settings not available")
        end
        
    elseif cmd == "showall" then
        TUICD:SetForceAllVisible(not TUICD.forceAllVisible)
        
    elseif cmd == "debug" then
        TUICD:SetDebugMode(not TUICD.debugMode)
        
    elseif cmd == "mounted" then
        -- Debug mounted state detection
        local isMounted = IsMounted()
        local isMountedOrTravel = TUICD.UnitAPI and TUICD.UnitAPI:IsMountedOrTravelForm() or false
        local _, playerClass = UnitClass("player")
        local formID = GetShapeshiftForm()
        local formSpellID = nil
        local formName = nil
        if formID and formID > 0 then
            local _, _, _, spellID = GetShapeshiftFormInfo(formID)
            formSpellID = spellID
            if spellID and C_Spell and C_Spell.GetSpellInfo then
                local info = C_Spell.GetSpellInfo(spellID)
                if info then
                    formName = info.name
                end
            end
        end
        
        TUICD:Print("|cff00ccff=== Mounted State Debug ===|r")
        TUICD:Print("IsMounted(): " .. tostring(isMounted))
        TUICD:Print("IsMountedOrTravelForm(): " .. tostring(isMountedOrTravel))
        TUICD:Print("Player Class: " .. tostring(playerClass))
        TUICD:Print("Shapeshift Form ID: " .. tostring(formID))
        TUICD:Print("Form Spell ID: " .. tostring(formSpellID))
        TUICD:Print("Form Name: " .. tostring(formName))
        
    elseif cmd == "version" or cmd == "ver" then
        TUICD:Print("Version: |cff00ff00" .. TUICD.VERSION .. "|r")
        TUICD:Print("WoW Build: " .. TUICD.BUILD_VERSION)
        TUICD:Print("Expansion: " .. TUICD.EXPANSION)
        
    elseif cmd == "status" then
        -- Debug status check
        TUICD:Print("|cff00ccff=== TUI:CD Status ===|r")
        
        -- Check modules
        local mm = TUICD.ModuleManager
        if mm then
            local modules = mm:GetAllModules()
            for id, mod in pairs(modules) do
                local state = mod.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
                TUICD:Print(string.format("Module '%s': %s (loaded=%s)", id, state, tostring(mod.loaded)))
            end
        end
        
        -- Check Blizzard viewers
        local viewers = {"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer"}
        TUICD:Print("|cff00ccffBlizzard Viewers:|r")
        for _, name in ipairs(viewers) do
            local v = _G[name]
            if v then
                local shown = v:IsShown() and "shown" or "hidden"
                local alpha = v:GetAlpha()
                TUICD:Print(string.format("  %s: exists (%s, alpha=%.2f)", name, shown, alpha))
            else
                TUICD:Print(string.format("  %s: |cffff0000NOT FOUND|r - Enable in Edit Mode!", name))
            end
        end
        
        -- Check Layout elements
        if TUICD.Layout then
            local elements = TUICD.Layout:GetAllElements()
            local count = 0
            for _ in pairs(elements) do count = count + 1 end
            TUICD:Print(string.format("|cff00ccffLayout elements:|r %d registered", count))
        end
        
    elseif cmd == "reset" then
        StaticPopupDialogs["TUICD_RESET_CONFIRM"] = {
            text = "Are you sure you want to reset ALL TUI: Cooldowns settings?\n\nThis cannot be undone!",
            button1 = "Reset",
            button2 = "Cancel",
            OnAccept = function()
                TweaksUI_Cooldowns_CharDB = nil
                TweaksUI_Cooldowns_DB = nil
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("TUICD_RESET_CONFIRM")
        
    elseif cmd == "remigrate" then
        -- Re-run migration for users who lost positions
        local charDb = TweaksUI_Cooldowns_CharDB
        if not charDb then
            TUICD:PrintError("No character database found")
            return
        end
        
        -- Check if TweaksUI data is available
        if _G.TweaksUI_CharDB and _G.TweaksUI_CharDB.settings and _G.TweaksUI_CharDB.settings.layout then
            local tuiLayout = _G.TweaksUI_CharDB.settings.layout
            if tuiLayout.elements then
                charDb.settings = charDb.settings or {}
                charDb.settings.layout = charDb.settings.layout or {}
                charDb.settings.layout.elements = charDb.settings.layout.elements or {}
                
                local cooldownElements = {
                    "EssentialCooldownViewer_TUIWrapper",
                    "UtilityCooldownViewer_TUIWrapper",
                    "BuffIconCooldownViewer_TUIWrapper",
                    "CustomTracker_TUIWrapper",
                }
                
                local migratedCount = 0
                for _, elementId in ipairs(cooldownElements) do
                    if tuiLayout.elements[elementId] then
                        charDb.settings.layout.elements[elementId] = {
                            point = tuiLayout.elements[elementId].point,
                            x = tuiLayout.elements[elementId].x,
                            y = tuiLayout.elements[elementId].y,
                            scale = tuiLayout.elements[elementId].scale,
                        }
                        migratedCount = migratedCount + 1
                    end
                end
                
                -- Also copy Dock positions
                for elementId, pos in pairs(tuiLayout.elements) do
                    if elementId:match("^Dock_") then
                        charDb.settings.layout.elements[elementId] = {
                            point = pos.point,
                            x = pos.x,
                            y = pos.y,
                            scale = pos.scale,
                        }
                        migratedCount = migratedCount + 1
                    end
                end
                
                charDb.settings.layout.dataVersion = 4
                
                if migratedCount > 0 then
                    TUICD:Print("Re-migrated " .. migratedCount .. " positions from TweaksUI.")
                    TUICD:Print("Reload UI to apply positions: |cff00ff00/rl|r")
                else
                    TUICD:Print("No positions found in TweaksUI data.")
                end
            else
                TUICD:PrintError("No layout data found in TweaksUI.")
            end
        else
            TUICD:PrintError("TweaksUI character data not found. Make sure TweaksUI is installed and has been loaded at least once.")
        end
        
    elseif cmd == "migrateprofiles" then
        -- Force migration of all stored profiles from old format to new format
        if not TweaksUI_Cooldowns_DB or not TweaksUI_Cooldowns_DB.profiles then
            TUICD:Print("No stored profiles found.")
            return
        end
        
        local migratedCount = 0
        local skippedCount = 0
        
        for name, profileData in pairs(TweaksUI_Cooldowns_DB.profiles) do
            -- Check if this is old format (has trackers but no modules)
            if profileData.trackers ~= nil and profileData.modules == nil then
                TUICD:Print("Migrating profile: |cffffff00" .. name .. "|r")
                
                -- Convert to new format
                local converted = {
                    modules = {
                        cooldowns = {},
                        layout = {
                            elements = {},
                            dataVersion = 4,
                        },
                    },
                    enabled = {
                        cooldowns = true,
                    },
                }
                
                -- Convert tracker settings
                if profileData.trackers then
                    for trackerKey, trackerSettings in pairs(profileData.trackers) do
                        converted.modules.cooldowns[trackerKey] = trackerSettings
                    end
                end
                
                -- Convert container positions
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
                
                -- Copy highlight settings
                if profileData.buffHighlights then converted.buffHighlights = profileData.buffHighlights end
                if profileData.essentialHighlights then converted.essentialHighlights = profileData.essentialHighlights end
                if profileData.utilityHighlights then converted.utilityHighlights = profileData.utilityHighlights end
                if profileData.customHighlights then converted.customHighlights = profileData.customHighlights end
                
                -- Convert custom entries
                if profileData.customEntries then
                    converted.cooldowns = { customEntries = profileData.customEntries }
                end
                
                -- Copy docks and metadata
                if profileData.docks then converted.docks = profileData.docks end
                if profileData.savedAt then converted.savedAt = profileData.savedAt end
                if profileData.addonVersion then converted.addonVersion = profileData.addonVersion end
                
                TweaksUI_Cooldowns_DB.profiles[name] = converted
                migratedCount = migratedCount + 1
            else
                skippedCount = skippedCount + 1
            end
        end
        
        if migratedCount > 0 then
            TUICD:Print("|cff00ff00Migrated " .. migratedCount .. " profile(s) to 3.0 format.|r")
            TUICD:Print("You can now switch profiles normally.")
        else
            TUICD:Print("No old-format profiles found to migrate. (" .. skippedCount .. " already in 3.0 format)")
        end
        
    elseif cmd == "dock" then
        -- Dock management commands
        local subcmd, subargs = args:match("^(%S*)%s*(.*)$")
        subcmd = (subcmd or ""):lower()
        
        if subcmd == "" or subcmd == "help" then
            TUICD:Print("|cff00ccff=== Dock Commands ===|r")
            TUICD:Print("|cffffff00/tuicd dock cleanup|r - Remove orphaned assignments (? icons)")
            TUICD:Print("|cffffff00/tuicd dock cleanup <1-4>|r - Cleanup specific dock only")
            TUICD:Print("|cffffff00/tuicd dock clear <1-4>|r - Clear all assignments from a dock")
            TUICD:Print("|cffffff00/tuicd dock list|r - List all dock assignments")
            
        elseif subcmd == "cleanup" then
            if not TUICD.Modules or not TUICD.Modules.Docks then
                TUICD:PrintError("Docks module not available")
                return
            end
            local dockNum = tonumber(subargs)
            TUICD.Modules.Docks:CleanupOrphans(dockNum)
            
        elseif subcmd == "clear" then
            if not TUICD.Modules or not TUICD.Modules.Docks then
                TUICD:PrintError("Docks module not available")
                return
            end
            local dockNum = tonumber(subargs)
            if not dockNum then
                TUICD:PrintError("Usage: /tuicd dock clear <1-4>")
                return
            end
            TUICD.Modules.Docks:ClearDock(dockNum)
            
        elseif subcmd == "list" then
            TUICD:Print("|cff00ccff=== Dock Assignments ===|r")
            local totalCount = 0
            
            -- List BuffHighlights dock assignments
            local buffDB = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.buffHighlights
            if buffDB and buffDB.dockAssignment then
                for slotIndex, dockIndex in pairs(buffDB.dockAssignment) do
                    if dockIndex then
                        TUICD:Print(string.format("  Dock %d: |cffffff00buffs|r slot %d", dockIndex, slotIndex))
                        totalCount = totalCount + 1
                    end
                end
            end
            
            -- List CooldownHighlights dock assignments
            for _, trackerKey in ipairs({"essential", "utility", "customTrackers"}) do
                local db = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB[trackerKey .. "Highlights"]
                if db and db.dockAssignment then
                    for slotIndex, dockIndex in pairs(db.dockAssignment) do
                        if dockIndex then
                            TUICD:Print(string.format("  Dock %d: |cffffff00%s|r slot %d", dockIndex, trackerKey, slotIndex))
                            totalCount = totalCount + 1
                        end
                    end
                end
            end
            
            if totalCount == 0 then
                TUICD:Print("  (no dock assignments)")
            else
                TUICD:Print(string.format("Total: %d assignment(s)", totalCount))
            end
        else
            TUICD:Print("Unknown dock command: " .. subcmd)
            TUICD:Print("Type /tuicd dock help for commands")
        end
        
    else
        TUICD:Print("Unknown command: " .. cmd)
        TUICD:Print("Type /tuicd help for commands")
    end
end

-- Reset multi-trackers slash command
SLASH_TUICDRESETMULTI1 = "/tuicdresetmulti"
SlashCmdList["TUICDRESETMULTI"] = function()
    StaticPopupDialogs["TUICD_RESET_MULTI"] = {
        text = "Reset ALL multi-trackers? This will delete all entries and settings. Cannot be undone.",
        button1 = "Reset",
        button2 = "Cancel",
        OnAccept = function()
            if TUICD.MultiTracker and TUICD.MultiTracker.ResetAllTrackers then
                TUICD.MultiTracker:ResetAllTrackers()
            else
                TUICD:PrintError("MultiTracker system not available")
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("TUICD_RESET_MULTI")
end

-- Register slash commands
for _, cmd in ipairs(TUICD.SLASH_COMMANDS) do
    local cmdName = cmd:upper():gsub("/", "")
    _G["SLASH_" .. cmdName .. "1"] = cmd
    SlashCmdList[cmdName] = HandleSlashCommand
end

-- Additional standalone commands
SLASH_TUICDLAYOUT1 = "/tuicdlayout"
SlashCmdList["TUICDLAYOUT"] = function(msg)
    local subcmd = msg:lower():match("^(%S*)") or ""
    
    if subcmd == "grid" then
        if TUICD.Layout then
            TUICD.Layout:ToggleGrid()
        end
    else
        if TUICD.Layout then
            TUICD.Layout:Toggle()
        end
    end
end

-- Quick reload command
SLASH_RL1 = "/rl"
SlashCmdList["RL"] = function()
    ReloadUI()
end

-- Edit Mode shortcut
SLASH_EM1 = "/em"
SlashCmdList["EM"] = function()
    if EditModeManagerFrame then
        if EditModeManagerFrame:IsShown() then
            HideUIPanel(EditModeManagerFrame)
        else
            ShowUIPanel(EditModeManagerFrame)
        end
    end
end

-- Blizzard Cooldown Manager shortcut
SLASH_CDM1 = "/cdm"
SlashCmdList["CDM"] = function()
    -- CooldownViewerSettings is Blizzard's Cooldown Settings frame
    local cooldownFrame = CooldownViewerSettings or _G["CooldownViewerSettings"]
    
    if cooldownFrame then
        if cooldownFrame:IsShown() then
            cooldownFrame:Hide()
        else
            cooldownFrame:Show()
        end
    else
        TUICD:PrintError("Cooldown Settings not available.")
    end
end
