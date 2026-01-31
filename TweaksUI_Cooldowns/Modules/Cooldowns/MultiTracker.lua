-- ============================================================================
-- TweaksUI: Cooldowns - Multi Custom Tracker System
-- Allows creating up to 10 additional custom trackers on the fly
-- Each tracker has all features of the original custom tracker
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.MultiTracker = {}
local MultiTracker = TUICD.MultiTracker

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local MAX_TRACKERS = 10
local TRACKER_PREFIX = "multiCustom"  -- Keys will be "multiCustom1", "multiCustom2", etc.

-- Default trackers that are created on first init
-- multiCustom1 = Empty for manual user entries
-- multiCustom2 = Populated from CDM Essential viewer
-- multiCustom3 = Populated from CDM Utility viewer
local DEFAULT_TRACKERS = {
    { key = "multiCustom1", name = "Custom Tracker", source = nil },  -- Empty for user manual entries
    { key = "multiCustom2", name = "Essential Custom Tracker", source = "essential" },
    { key = "multiCustom3", name = "Utility Custom Tracker", source = "utility" },
}

-- Default settings for new trackers (mirrors TRACKER_DEFAULTS from Cooldowns.lua)
local TRACKER_DEFAULTS = {
    enabled = true,
    -- Icon size
    iconSize = 36,
    iconWidth = nil,
    iconHeight = nil,
    aspectRatio = "1:1",
    -- Layout
    columns = 4,
    rows = 0,
    spacingH = 2,
    spacingV = 2,
    growDirection = "RIGHT",
    growSecondary = "DOWN",
    alignment = "LEFT",
    reverseOrder = false,
    -- Custom Grid
    customLayout = "",
    -- Appearance
    zoom = 0.08,
    borderAlpha = 1.0,
    iconOpacity = 1.0,
    iconOpacityCombat = 1.0,
    iconEdgeStyle = "sharp",
    useMasque = false,
    -- Usability & Range States
    showUnusableState = false,      -- Tint when spell not usable (no resources)
    unusableColorR = 0.0,           -- Unusable overlay color (black by default)
    unusableColorG = 0.0,
    unusableColorB = 0.0,
    unusableAlpha = 0.6,            -- Unusable overlay alpha
    showOutOfRange = false,         -- Tint when spell out of range
    outOfRangeColorR = 1.0,         -- Red tint color
    outOfRangeColorG = 0.3,
    outOfRangeColorB = 0.3,
    outOfRangeAlpha = 0.6,          -- Overlay alpha
    -- Behavior
    showTooltip = true,
    clickthrough = false,       -- Allow clicks to pass through tracker
    -- Text - Cooldown numbers
    cooldownTextScale = 1.0,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownTextColorR = 1.0,
    cooldownTextColorG = 0.82,
    cooldownTextColorB = 0.0,
    cooldownTextFont = "Default",
    -- Text - Stack counts
    countTextScale = 1.0,
    countTextOffsetX = 0,
    countTextOffsetY = 0,
    countTextColorR = 1.0,
    countTextColorG = 1.0,
    countTextColorB = 1.0,
    countTextFont = "Default",
    -- Cooldown sweep
    hideSweep = false,
    showCountdownText = true,
    -- Visibility
    visibilityEnabled = false,
    showInCombat = true,
    showOutOfCombat = true,
    showSolo = true,
    showInParty = true,
    showInRaid = true,
    showInArena = true,
    showInBattleground = true,
    showInDungeon = true,
    showInScenario = true,
    showInDelve = true,
    -- Position
    point = "CENTER",
    x = 0,
    y = -250,
}

-- ============================================================================
-- DATABASE HELPERS
-- ============================================================================

local function InitializeStorage()
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = {}
    end
    TweaksUI_Cooldowns_CharDB.multiTrackers = TweaksUI_Cooldowns_CharDB.multiTrackers or {
        registry = {},  -- List of tracker definitions: { key, name, createdAt }
        settings = {},  -- [trackerKey] = settings table
        entries = {},   -- [trackerKey][specID] = { entries }
    }
end

local function GetMultiTrackerDB()
    InitializeStorage()
    return TweaksUI_Cooldowns_CharDB.multiTrackers
end

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

-- ============================================================================
-- REGISTRY MANAGEMENT
-- ============================================================================

-- Get list of all registered trackers
function MultiTracker:GetTrackerList()
    local db = GetMultiTrackerDB()
    return db.registry or {}
end

-- Get tracker info by key
function MultiTracker:GetTrackerInfo(trackerKey)
    local db = GetMultiTrackerDB()
    for _, tracker in ipairs(db.registry or {}) do
        if tracker.key == trackerKey then
            return tracker
        end
    end
    return nil
end

-- Check if a tracker is a default (Essential/Utility - cannot be deleted)
function MultiTracker:IsDefaultTracker(trackerKey)
    local tracker = self:GetTrackerInfo(trackerKey)
    return tracker and tracker.source ~= nil
end

-- Check if a tracker can be deleted (not a default tracker)
function MultiTracker:CanDeleteTracker(trackerKey)
    return not self:IsDefaultTracker(trackerKey)
end

-- Get count of registered trackers
function MultiTracker:GetTrackerCount()
    local db = GetMultiTrackerDB()
    return #(db.registry or {})
end

-- Get index of a tracker in the registry (1-based)
function MultiTracker:GetTrackerIndex(trackerKey)
    local db = GetMultiTrackerDB()
    for i, tracker in ipairs(db.registry or {}) do
        if tracker.key == trackerKey then
            return i
        end
    end
    -- Extract number from key as fallback
    local num = tonumber(trackerKey:match(TRACKER_PREFIX .. "(%d+)"))
    return num or 1
end

-- Check if we can create more trackers
function MultiTracker:CanCreateTracker()
    return self:GetTrackerCount() < MAX_TRACKERS
end

-- Find next available tracker number
local function GetNextTrackerNumber()
    local db = GetMultiTrackerDB()
    local usedNumbers = {}
    
    for _, tracker in ipairs(db.registry or {}) do
        local num = tonumber(tracker.key:match(TRACKER_PREFIX .. "(%d+)"))
        if num then
            usedNumbers[num] = true
        end
    end
    
    for i = 1, MAX_TRACKERS do
        if not usedNumbers[i] then
            return i
        end
    end
    
    return nil
end

-- Create a new tracker
function MultiTracker:CreateTracker(name)
    if not self:CanCreateTracker() then
        return nil, "Maximum number of trackers reached (" .. MAX_TRACKERS .. ")"
    end
    
    local db = GetMultiTrackerDB()
    local nextNum = GetNextTrackerNumber()
    
    if not nextNum then
        return nil, "No available tracker slots"
    end
    
    local trackerKey = TRACKER_PREFIX .. nextNum
    local trackerName = name or ("Custom Tracker " .. nextNum)
    
    -- Create registry entry
    table.insert(db.registry, {
        key = trackerKey,
        name = trackerName,
        createdAt = time(),
    })
    
    -- Initialize settings with defaults
    db.settings[trackerKey] = DeepCopy(TRACKER_DEFAULTS)
    
    -- Offset position so trackers don't stack on top of each other
    db.settings[trackerKey].y = -250 - ((nextNum - 1) * 60)
    
    -- Initialize empty entries table
    db.entries[trackerKey] = {}
    
    TUICD:Print(string.format("Created tracker: |cffffcc00%s|r (%s)", trackerName, trackerKey))
    
    -- Fire event for UI to update
    if TUICD.Events and TUICD.EVENTS then
        TUICD.Events:Fire(TUICD.EVENTS.SETTINGS_CHANGED, "multiTracker", "created", trackerKey)
    end
    
    -- Notify frames module
    if TUICD.MultiTrackerFrames then
        TUICD.MultiTrackerFrames:OnTrackerCreated(trackerKey)
    end
    
    return trackerKey, trackerName
end

-- Delete a tracker
function MultiTracker:DeleteTracker(trackerKey)
    local db = GetMultiTrackerDB()
    
    -- Find and remove from registry
    local found = false
    local trackerName = trackerKey
    
    for i, tracker in ipairs(db.registry) do
        if tracker.key == trackerKey then
            trackerName = tracker.name
            table.remove(db.registry, i)
            found = true
            break
        end
    end
    
    if not found then
        return false, "Tracker not found: " .. trackerKey
    end
    
    -- Clean up settings and entries
    db.settings[trackerKey] = nil
    db.entries[trackerKey] = nil
    
    -- Destroy frame if it exists
    local frameName = "TweaksUI_MultiTracker_" .. trackerKey
    local frame = _G[frameName]
    if frame then
        frame:Hide()
        frame:SetParent(nil)
        _G[frameName] = nil
    end
    
    TUICD:Print(string.format("Deleted tracker: |cffffcc00%s|r", trackerName))
    
    -- Notify frames module first (before firing event)
    if TUICD.MultiTrackerFrames then
        TUICD.MultiTrackerFrames:OnTrackerDeleted(trackerKey)
    end
    
    -- Fire event for UI to update
    if TUICD.Events and TUICD.EVENTS then
        TUICD.Events:Fire(TUICD.EVENTS.SETTINGS_CHANGED, "multiTracker", "deleted", trackerKey)
    end
    
    return true
end

-- Rename a tracker
function MultiTracker:RenameTracker(trackerKey, newName)
    local db = GetMultiTrackerDB()
    
    for _, tracker in ipairs(db.registry) do
        if tracker.key == trackerKey then
            local oldName = tracker.name
            tracker.name = newName
            TUICD:Print(string.format("Renamed tracker: |cffffcc00%s|r -> |cffffcc00%s|r", oldName, newName))
            return true
        end
    end
    
    return false, "Tracker not found: " .. trackerKey
end

-- Get tracker info by key
function MultiTracker:GetTrackerInfo(trackerKey)
    local db = GetMultiTrackerDB()
    
    for _, tracker in ipairs(db.registry) do
        if tracker.key == trackerKey then
            return tracker
        end
    end
    
    return nil
end

-- ============================================================================
-- SETTINGS MANAGEMENT
-- ============================================================================

-- Get all settings for a tracker
function MultiTracker:GetSettings(trackerKey)
    local db = GetMultiTrackerDB()
    
    if not db.settings[trackerKey] then
        db.settings[trackerKey] = DeepCopy(TRACKER_DEFAULTS)
    end
    
    return db.settings[trackerKey]
end

-- Get a specific setting
function MultiTracker:GetSetting(trackerKey, key)
    local settings = self:GetSettings(trackerKey)
    local value = settings[key]
    
    if value == nil then
        return TRACKER_DEFAULTS[key]
    end
    
    return value
end

-- Set a specific setting
function MultiTracker:SetSetting(trackerKey, key, value)
    local db = GetMultiTrackerDB()
    
    if not db.settings[trackerKey] then
        db.settings[trackerKey] = DeepCopy(TRACKER_DEFAULTS)
    end
    
    db.settings[trackerKey][key] = value
    
    -- When enabling/disabling a source-based tracker, sync hideTracker on the original
    if key == "enabled" then
        MultiTracker:SyncSourceTrackerVisibility(trackerKey, value)
    end
    
    -- Notify frames module
    if TUICD.MultiTrackerFrames then
        TUICD.MultiTrackerFrames:OnSettingsChanged(trackerKey, key, value)
    end
    
    -- Fire event for UI to update
    if TUICD.Events and TUICD.EVENTS then
        TUICD.Events:Fire(TUICD.EVENTS.SETTINGS_CHANGED, trackerKey, key, value)
    end
end

-- ============================================================================
-- ENTRY MANAGEMENT (Spells/Items per Spec)
-- ============================================================================

-- Get current spec ID
local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return specID
end

-- Get entries for a tracker (current spec)
function MultiTracker:GetEntries(trackerKey, specID)
    local db = GetMultiTrackerDB()
    specID = specID or GetCurrentSpecID()
    
    if not specID then return {} end
    
    db.entries[trackerKey] = db.entries[trackerKey] or {}
    db.entries[trackerKey][specID] = db.entries[trackerKey][specID] or {}
    
    return db.entries[trackerKey][specID]
end

-- Check if entry exists
function MultiTracker:EntryExists(trackerKey, entryType, entryID)
    local entries = self:GetEntries(trackerKey)
    
    for _, entry in ipairs(entries) do
        if entry.type == entryType and entry.id == entryID then
            return true
        end
    end
    
    return false
end

-- Add an entry (spell or item)
function MultiTracker:AddEntry(trackerKey, entryType, idOrName, source)
    local specID = GetCurrentSpecID()
    if not specID then
        return false, "Could not determine current spec"
    end
    
    local db = GetMultiTrackerDB()
    db.entries[trackerKey] = db.entries[trackerKey] or {}
    db.entries[trackerKey][specID] = db.entries[trackerKey][specID] or {}
    
    local entries = db.entries[trackerKey][specID]
    local entryID, entryName, entryTexture
    
    if entryType == "spell" then
        local numID = tonumber(idOrName)
        if numID then
            local spellInfo = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellInfo(numID)
            if spellInfo then
                entryID = numID
                entryName = spellInfo.name
                entryTexture = TUICD.SpellAPI:GetSpellTexture(numID)
            else
                return false, "Spell ID not found: " .. numID
            end
        else
            local spellInfo = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellInfo(idOrName)
            if spellInfo then
                entryID = spellInfo.spellID
                entryName = spellInfo.name
                entryTexture = TUICD.SpellAPI:GetSpellTexture(entryID)
            else
                return false, "Spell not found: " .. idOrName
            end
        end
        
    elseif entryType == "item" then
        local numID = tonumber(idOrName)
        if numID then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(numID)
            if itemName then
                entryID = numID
                entryName = itemName
                entryTexture = itemTexture
            else
                C_Item.RequestLoadItemDataByID(numID)
                entryID = numID
                entryName = "Loading..."
                entryTexture = nil
            end
        else
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
        -- Equipped slot tracking (slotID)
        local slotID = tonumber(idOrName)
        if not slotID then
            return false, "Invalid slot ID: " .. tostring(idOrName)
        end
        
        -- Validate slot ID (valid equipment slots are 1-19)
        if slotID < 1 or slotID > 19 then
            return false, "Invalid equipment slot: " .. slotID
        end
        
        entryID = slotID
        -- Get current item name for display
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local itemName = GetItemInfo(itemID)
            entryName = itemName or ("Slot " .. slotID)
        else
            entryName = "Slot " .. slotID
        end
    else
        return false, "Invalid entry type: " .. tostring(entryType)
    end
    
    -- Check for duplicates
    if self:EntryExists(trackerKey, entryType, entryID) then
        return false, "Already tracking this " .. entryType
    end
    
    -- Add entry
    table.insert(entries, {
        type = entryType,
        id = entryID,
        enabled = true,
        source = source,
    })
    
    TUICD:Print(string.format("Added %s |cffffcc00%s|r (%d) to tracker", entryType, entryName, entryID))
    
    -- Rebuild tracker display
    self:RebuildTracker(trackerKey)
    
    return true, entryName
end

-- Remove an entry by index
function MultiTracker:RemoveEntry(trackerKey, index)
    local entries = self:GetEntries(trackerKey)
    
    if index < 1 or index > #entries then
        return false, "Invalid entry index"
    end
    
    local entry = entries[index]
    local entryName = "Unknown"
    
    if entry.type == "spell" then
        local spellInfo = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellInfo(entry.id)
        entryName = spellInfo and spellInfo.name or entry.id
    elseif entry.type == "item" then
        local itemName = GetItemInfo(entry.id)
        entryName = itemName or entry.id
    end
    
    table.remove(entries, index)
    
    TUICD:Print(string.format("Removed |cffffcc00%s|r from tracker", entryName))
    
    -- Rebuild tracker display
    self:RebuildTracker(trackerKey)
    
    return true
end

-- Toggle entry enabled state
function MultiTracker:ToggleEntry(trackerKey, index)
    local entries = self:GetEntries(trackerKey)
    
    if index < 1 or index > #entries then
        return false, "Invalid entry index"
    end
    
    entries[index].enabled = not entries[index].enabled
    
    -- Rebuild tracker display
    self:RebuildTracker(trackerKey)
    
    return true, entries[index].enabled
end

-- Move an entry from one position to another within a tracker
function MultiTracker:MoveEntry(trackerKey, fromIndex, toIndex)
    local entries = self:GetEntries(trackerKey)
    
    if not entries or #entries == 0 then
        return false, "No entries"
    end
    
    if fromIndex < 1 or fromIndex > #entries then
        return false, "Invalid from index"
    end
    
    if toIndex < 1 or toIndex > #entries then
        return false, "Invalid to index"
    end
    
    if fromIndex == toIndex then
        return true  -- Nothing to do
    end
    
    -- Remove entry from old position
    local entry = table.remove(entries, fromIndex)
    
    -- Insert at new position
    table.insert(entries, toIndex, entry)
    
    -- Rebuild tracker display
    self:RebuildTracker(trackerKey)
    
    return true
end

-- Set the enabled state of an entry at a specific index
function MultiTracker:SetEntryEnabled(trackerKey, index, enabled)
    local entries = self:GetEntries(trackerKey)
    
    if not entries or index < 1 or index > #entries then
        return false, "Invalid entry index"
    end
    
    entries[index].enabled = enabled
    
    -- Rebuild tracker display
    self:RebuildTracker(trackerKey)
    
    return true
end

-- ============================================================================
-- FRAME MANAGEMENT (Placeholder - actual rendering integrated with Cooldowns.lua)
-- ============================================================================

-- Tracker frames storage
MultiTracker.frames = {}
MultiTracker.icons = {}  -- [trackerKey] = { entryKey = iconFrame }

-- Rebuild a specific tracker (placeholder - needs integration with Cooldowns.lua)
function MultiTracker:RebuildTracker(trackerKey)
    -- Notify frames module to rebuild
    if TUICD.MultiTrackerFrames then
        TUICD.MultiTrackerFrames:OnEntriesChanged(trackerKey)
    end
    
    -- Fire event for UI to update
    if TUICD.Events and TUICD.EVENTS then
        TUICD.Events:Fire(TUICD.EVENTS.SETTINGS_CHANGED, trackerKey, "rebuild", true)
    end
end

-- Rebuild all multi-trackers
function MultiTracker:RebuildAllTrackers()
    for _, tracker in ipairs(self:GetTrackerList()) do
        self:RebuildTracker(tracker.key)
    end
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_TUICDMULTI1 = "/tuicdmulti"
SlashCmdList["TUICDMULTI"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    
    local cmd = args[1] and args[1]:lower() or "help"
    
    if cmd == "help" or cmd == "?" then
        TUICD:Print("Multi-Tracker commands:")
        TUICD:Print("  /tuicdmulti list - List all custom trackers")
        TUICD:Print("  /tuicdmulti create [name] - Create a new tracker")
        TUICD:Print("  /tuicdmulti delete <key> - Delete a tracker")
        TUICD:Print("  /tuicdmulti rename <key> <name> - Rename a tracker")
        TUICD:Print("  /tuicdmulti add <key> spell <id> - Add spell to tracker")
        TUICD:Print("  /tuicdmulti add <key> item <id> - Add item to tracker")
        TUICD:Print("  /tuicdmulti remove <key> <index> - Remove entry by index")
        TUICD:Print("  /tuicdmulti entries <key> - List entries in tracker")
        TUICD:Print("  /tuicdmulti toggle <key> - Enable/disable tracker")
        return
    end
    
    if cmd == "list" then
        local trackers = MultiTracker:GetTrackerList()
        if #trackers == 0 then
            TUICD:Print("No custom trackers created. Use '/tuicdmulti create' to make one.")
        else
            TUICD:Print(string.format("Custom Trackers (%d/%d):", #trackers, MAX_TRACKERS))
            for i, tracker in ipairs(trackers) do
                local settings = MultiTracker:GetSettings(tracker.key)
                local status = settings.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
                local entryCount = #MultiTracker:GetEntries(tracker.key)
                TUICD:Print(string.format("  %d. [%s] |cffffcc00%s|r (%s) - %d entries", 
                    i, status, tracker.name, tracker.key, entryCount))
            end
        end
        return
    end
    
    if cmd == "create" then
        local name = table.concat(args, " ", 2)
        if name == "" then name = nil end
        
        local key, result = MultiTracker:CreateTracker(name)
        if not key then
            TUICD:Print("|cffff0000Error:|r " .. result)
        end
        return
    end
    
    if cmd == "delete" then
        local key = args[2]
        if not key then
            TUICD:Print("Usage: /tuicdmulti delete <key>")
            return
        end
        
        local success, err = MultiTracker:DeleteTracker(key)
        if not success then
            TUICD:Print("|cffff0000Error:|r " .. err)
        end
        return
    end
    
    if cmd == "rename" then
        local key = args[2]
        local newName = table.concat(args, " ", 3)
        
        if not key or newName == "" then
            TUICD:Print("Usage: /tuicdmulti rename <key> <new name>")
            return
        end
        
        local success, err = MultiTracker:RenameTracker(key, newName)
        if not success then
            TUICD:Print("|cffff0000Error:|r " .. err)
        end
        return
    end
    
    if cmd == "add" then
        local key = args[2]
        local entryType = args[3] and args[3]:lower()
        local idOrName = args[4]
        
        if not key or not entryType or not idOrName then
            TUICD:Print("Usage: /tuicdmulti add <key> spell|item <id or name>")
            return
        end
        
        if entryType ~= "spell" and entryType ~= "item" then
            TUICD:Print("Entry type must be 'spell' or 'item'")
            return
        end
        
        -- Check if tracker exists
        if not MultiTracker:GetTrackerInfo(key) then
            TUICD:Print("|cffff0000Error:|r Tracker not found: " .. key)
            return
        end
        
        local success, result = MultiTracker:AddEntry(key, entryType, idOrName)
        if not success then
            TUICD:Print("|cffff0000Error:|r " .. result)
        end
        return
    end
    
    if cmd == "remove" then
        local key = args[2]
        local index = tonumber(args[3])
        
        if not key or not index then
            TUICD:Print("Usage: /tuicdmulti remove <key> <index>")
            return
        end
        
        local success, err = MultiTracker:RemoveEntry(key, index)
        if not success then
            TUICD:Print("|cffff0000Error:|r " .. err)
        end
        return
    end
    
    if cmd == "entries" then
        local key = args[2]
        
        if not key then
            TUICD:Print("Usage: /tuicdmulti entries <key>")
            return
        end
        
        local tracker = MultiTracker:GetTrackerInfo(key)
        if not tracker then
            TUICD:Print("|cffff0000Error:|r Tracker not found: " .. key)
            return
        end
        
        local entries = MultiTracker:GetEntries(key)
        
        if #entries == 0 then
            TUICD:Print(string.format("No entries in |cffffcc00%s|r for current spec", tracker.name))
        else
            TUICD:Print(string.format("Entries in |cffffcc00%s|r:", tracker.name))
            for i, entry in ipairs(entries) do
                local name = "Unknown"
                if entry.type == "spell" then
                    local spellInfo = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellInfo(entry.id)
                    name = spellInfo and spellInfo.name or entry.id
                elseif entry.type == "item" then
                    name = GetItemInfo(entry.id) or entry.id
                end
                
                local status = entry.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
                local source = entry.source and string.format(" |cff888888(%s)|r", entry.source) or ""
                TUICD:Print(string.format("  %d. [%s] %s: %s (%d)%s", 
                    i, status, entry.type, name, entry.id, source))
            end
        end
        return
    end
    
    if cmd == "toggle" then
        local key = args[2]
        
        if not key then
            TUICD:Print("Usage: /tuicdmulti toggle <key>")
            return
        end
        
        local tracker = MultiTracker:GetTrackerInfo(key)
        if not tracker then
            TUICD:Print("|cffff0000Error:|r Tracker not found: " .. key)
            return
        end
        
        local settings = MultiTracker:GetSettings(key)
        settings.enabled = not settings.enabled
        
        local status = settings.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
        TUICD:Print(string.format("Tracker |cffffcc00%s|r is now %s", tracker.name, status))
        
        -- Sync hideTracker on source tracker (Essential/Utility)
        MultiTracker:SyncSourceTrackerVisibility(key, settings.enabled)
        
        MultiTracker:RebuildTracker(key)
        return
    end
    
    -- Unknown command
    TUICD:Print("Unknown command. Type '/tuicdmulti help' for usage.")
end

-- ============================================================================
-- DEFAULT TRACKER CREATION
-- ============================================================================

-- Create default trackers if they don't exist
-- Called once on first init
local function CreateDefaultTrackers()
    local db = GetMultiTrackerDB()
    
    -- Check if defaults already exist
    local existingKeys = {}
    for _, tracker in ipairs(db.registry) do
        existingKeys[tracker.key] = true
    end
    
    local createdCount = 0
    for i, defaultTracker in ipairs(DEFAULT_TRACKERS) do
        if not existingKeys[defaultTracker.key] then
            -- Create registry entry
            table.insert(db.registry, {
                key = defaultTracker.key,
                name = defaultTracker.name,
                createdAt = time(),
                isDefault = true,  -- Mark as default tracker
                source = defaultTracker.source,  -- "essential", "utility", or nil
            })
            
            -- Initialize settings with defaults
            db.settings[defaultTracker.key] = DeepCopy(TRACKER_DEFAULTS)
            
            -- Source-based trackers (Essential/Utility copies) start disabled
            -- so existing users aren't surprised by new frames appearing
            if defaultTracker.source then
                db.settings[defaultTracker.key].enabled = false
            end
            
            -- Offset position so trackers don't stack
            db.settings[defaultTracker.key].y = -250 - ((i - 1) * 60)
            
            -- Initialize empty entries table
            db.entries[defaultTracker.key] = {}
            
            createdCount = createdCount + 1
            TUICD:PrintDebug(string.format("Created default tracker: %s (%s)", defaultTracker.name, defaultTracker.key))
        end
    end
    
    if createdCount > 0 then
        TUICD:PrintDebug(string.format("Created %d default tracker(s)", createdCount))
    end
    
    return createdCount
end

-- Get the tracker key for a given source type
-- Returns the tracker key that should receive spells from a given CDM source
function MultiTracker:GetTrackerKeyForSource(source)
    for _, defaultTracker in ipairs(DEFAULT_TRACKERS) do
        if defaultTracker.source == source then
            return defaultTracker.key
        end
    end
    return nil
end

-- Sync the hideTracker state on the original Essential/Utility tracker
-- When a source-based multi-tracker is enabled, hide the original to prevent duplicates
-- When disabled, unhide the original so it shows again
function MultiTracker:SyncSourceTrackerVisibility(trackerKey, enabled)
    local tracker = MultiTracker:GetTrackerInfo(trackerKey)
    if not tracker or not tracker.source then return end
    
    local CooldownHighlights = TUICD.CooldownHighlights
    if not CooldownHighlights then return end
    
    local sourceKey = tracker.source
    
    CooldownHighlights:UpdateState(sourceKey, {}, {
        statePath = "hideTracker",
        value = enabled
    })
    
    -- Persist the change
    if TUICD.Cooldowns and TUICD.Cooldowns.SaveSettings then
        TUICD.Cooldowns:SaveSettings()
    end
    
    -- Update checkbox UI if the per-icon panel is open
    local checkFrame = _G["TweaksCD_" .. sourceKey .. "_HideTrackerCheck"]
    if checkFrame then
        checkFrame:SetChecked(enabled)
    end
end

-- Clear all entries from a specific tracker
function MultiTracker:ClearTracker(trackerKey)
    local db = GetTrackerDB()
    if not db then return false end
    
    if db.entries and db.entries[trackerKey] then
        wipe(db.entries[trackerKey])
        TUICD:PrintDebug("Cleared all entries from tracker: " .. trackerKey)
        return true
    end
    return false
end

-- Reset all multi-trackers to defaults (clears all entries and recreates default trackers)
function MultiTracker:ResetAllTrackers()
    local db = GetTrackerDB()
    if not db then return false end
    
    -- Clear all tracker data
    if db.trackers then wipe(db.trackers) end
    if db.entries then wipe(db.entries) end
    if db.settings then wipe(db.settings) end
    if db.positions then wipe(db.positions) end
    if db.perIconSettings then wipe(db.perIconSettings) end
    
    -- Recreate defaults
    InitializeStorage()
    CreateDefaultTrackers()
    
    -- Hide all tracker frames
    if TUICD.MultiTrackerFrames then
        TUICD.MultiTrackerFrames:HideAllTrackers()
    end
    
    TUICD:Print("|cff00ff00All multi-trackers have been reset!|r")
    TUICD:Print("Reload UI to see changes: |cffffff00/rl|r")
    
    return true
end

-- ============================================================================
-- LEGACY CUSTOM ENTRIES MIGRATION (pre-3.0.4 → multiCustom1)
-- ============================================================================

-- Migrates entries from the old single custom tracker system
-- (TweaksUI_Cooldowns_CharDB.cooldowns.customEntries) into multiCustom1
local function MigrateLegacyCustomEntries()
    local charDb = TweaksUI_Cooldowns_CharDB
    if not charDb then return end

    -- Already migrated?
    if charDb._legacyCustomEntriesMigrated then return end

    -- Source: old custom entries keyed by specID
    local oldEntries = charDb.cooldowns
                   and charDb.cooldowns.customEntries
    if not oldEntries then
        -- Also check settings.cooldowns path (post-3.0 format migration put them there)
        oldEntries = charDb.settings
                 and charDb.settings.cooldowns
                 and charDb.settings.cooldowns.customEntries
    end

    if not oldEntries or not next(oldEntries) then
        -- Nothing to migrate
        charDb._legacyCustomEntriesMigrated = true
        return
    end

    -- Target: multiCustom1 (the default "Custom Tracker")
    local targetKey = "multiCustom1"
    local db = GetMultiTrackerDB()

    -- Make sure target tracker exists in registry
    local targetExists = false
    for _, tracker in ipairs(db.registry) do
        if tracker.key == targetKey then
            targetExists = true
            break
        end
    end

    if not targetExists then
        -- CreateDefaultTrackers should have made it, but just in case
        TUICD:PrintDebug("Migration target " .. targetKey .. " not found, skipping")
        return
    end

    db.entries[targetKey] = db.entries[targetKey] or {}

    local totalMigrated = 0
    local totalSkipped = 0

    for specID, specEntries in pairs(oldEntries) do
        if type(specID) == "number" and type(specEntries) == "table" and #specEntries > 0 then
            db.entries[targetKey][specID] = db.entries[targetKey][specID] or {}
            local targetList = db.entries[targetKey][specID]

            -- Build a quick lookup of what's already in the target
            local existingLookup = {}
            for _, entry in ipairs(targetList) do
                local key = (entry.type or "") .. "_" .. (entry.id or "")
                existingLookup[key] = true
            end

            for _, entry in ipairs(specEntries) do
                if entry.type and entry.id then
                    local key = entry.type .. "_" .. entry.id
                    if not existingLookup[key] then
                        table.insert(targetList, {
                            type    = entry.type,
                            id      = entry.id,
                            enabled = (entry.enabled ~= false),  -- default true
                            source  = "legacy_migration",
                        })
                        existingLookup[key] = true
                        totalMigrated = totalMigrated + 1
                    else
                        totalSkipped = totalSkipped + 1
                    end
                end
            end
        end
    end

    -- Mark migration complete regardless of count
    charDb._legacyCustomEntriesMigrated = true

    if totalMigrated > 0 then
        -- Enable the tracker if it was disabled, since user clearly had entries
        local settings = db.settings[targetKey]
        if settings and not settings.enabled then
            settings.enabled = true
        end

        TUICD:Print(string.format(
            "Migrated |cffffcc00%d|r custom tracker %s to |cff00ccff%s|r.",
            totalMigrated,
            totalMigrated == 1 and "entry" or "entries",
            "Custom Tracker"
        ))
        if totalSkipped > 0 then
            TUICD:PrintDebug(totalSkipped .. " duplicate(s) skipped during migration.")
        end
    else
        TUICD:PrintDebug("Legacy custom entries migration: nothing new to migrate.")
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Initialize on load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    InitializeStorage()
    CreateDefaultTrackers()
    MigrateLegacyCustomEntries()
    TUICD:PrintDebug("MultiTracker system initialized")
end)
