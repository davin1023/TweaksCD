-- ============================================================================
-- TweaksUI: Cooldowns - CDM Scraper Helper
-- Scrapes spell IDs from Blizzard's Cooldown Manager and adds them to 
-- the custom tracker at login (only adds spells not already present)
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.CDMScraper = {}
local CDMScraper = TUICD.CDMScraper

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

-- Which CDM viewers to scrape from
local VIEWERS_TO_SCRAPE = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}

-- Delay after login before scraping (seconds)
-- CDM needs time to populate its icons
local SCRAPE_DELAY = 2.0

-- ============================================================================
-- UTILITIES
-- ============================================================================

-- Check if a frame is an icon (has an Icon texture)
local function IsIcon(frame)
    if not frame then return false end
    if not frame.GetObjectType then return false end
    local objType = frame:GetObjectType()
    if objType ~= "Frame" and objType ~= "Button" then return false end
    -- Must have an Icon texture child
    return (frame.Icon or frame.icon) ~= nil
end

-- Collect icons from a viewer
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
    
    return icons
end

-- Extract spell ID from an icon
local function GetIconSpellID(icon)
    if not icon then return nil end
    
    -- Try direct properties first
    local spellID = icon.spellID or icon.SpellID or icon.spellId
    
    -- Try GetSpellID method
    if not spellID and icon.GetSpellID then
        pcall(function() spellID = icon:GetSpellID() end)
    end
    
    -- Validate it's a real number
    if spellID and type(spellID) == "number" and spellID > 0 then
        return spellID
    end
    
    return nil
end

-- Get current spec ID
local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return specID
end

-- Initialize custom entries storage
local function InitializeStorage()
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = {}
    end
    TweaksUI_Cooldowns_CharDB.cooldowns = TweaksUI_Cooldowns_CharDB.cooldowns or {}
    TweaksUI_Cooldowns_CharDB.cooldowns.customEntries = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries or {}
end

-- ============================================================================
-- MULTITRACKER-AWARE HELPERS
-- ============================================================================

-- Ensure multi-tracker storage exists
local function EnsureMultiTrackerStorage(trackerKey)
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = {}
    end
    TweaksUI_Cooldowns_CharDB.multiTrackers = TweaksUI_Cooldowns_CharDB.multiTrackers or {
        registry = {},
        settings = {},
        entries = {},
    }
    TweaksUI_Cooldowns_CharDB.multiTrackers.entries[trackerKey] = 
        TweaksUI_Cooldowns_CharDB.multiTrackers.entries[trackerKey] or {}
end

-- Check if spell already exists in a specific multi-tracker
local function SpellExistsInTracker(trackerKey, specID, spellID)
    EnsureMultiTrackerStorage(trackerKey)
    
    local trackerEntries = TweaksUI_Cooldowns_CharDB.multiTrackers.entries[trackerKey]
    local entries = trackerEntries[specID]
    if not entries then return false end
    
    for _, entry in ipairs(entries) do
        if entry.type == "spell" and entry.id == spellID then
            return true
        end
    end
    
    return false
end

-- Add spell to a specific multi-tracker
local function AddSpellToTracker(trackerKey, specID, spellID, source)
    EnsureMultiTrackerStorage(trackerKey)
    
    local trackerEntries = TweaksUI_Cooldowns_CharDB.multiTrackers.entries[trackerKey]
    trackerEntries[specID] = trackerEntries[specID] or {}
    
    local entries = trackerEntries[specID]
    
    table.insert(entries, {
        type = "spell",
        id = spellID,
        enabled = true,
        source = source,  -- "essential" or "utility"
    })
    
    -- Cache spell info
    TweaksUI_Cooldowns_CharDB.cooldowns = TweaksUI_Cooldowns_CharDB.cooldowns or {}
    TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache = 
        TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache or {}
    
    local spellInfo = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellInfo(spellID)
    if spellInfo then
        local cacheKey = "spell_" .. spellID
        TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache[cacheKey] = {
            name = spellInfo.name,
            texture = TUICD.SpellAPI:GetSpellTexture(spellID),
            source = source,
        }
    end
    
    return true
end

-- ============================================================================
-- LEGACY HELPERS (kept for backwards compatibility)
-- ============================================================================

-- Check if spell already exists in original custom entries
local function SpellExists(specID, spellID)
    InitializeStorage()
    
    local entries = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID]
    if not entries then return false end
    
    for _, entry in ipairs(entries) do
        if entry.type == "spell" and entry.id == spellID then
            return true
        end
    end
    
    return false
end

-- Add spell to original custom entries (NOT USED BY DEFAULT - kept for backwards compatibility)
local function AddSpell(specID, spellID, source)
    InitializeStorage()
    
    TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] = 
        TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] or {}
    
    local entries = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID]
    
    table.insert(entries, {
        type = "spell",
        id = spellID,
        enabled = true,
        source = source,
    })
    
    return true
end

-- ============================================================================
-- MAIN SCRAPER FUNCTION
-- ============================================================================

function CDMScraper:ScrapeAndAdd()
    local specID = GetCurrentSpecID()
    if not specID then
        TUICD:PrintDebug("CDMScraper: Could not determine current spec")
        return 0
    end
    
    local addedCount = 0
    local scrapedSpells = {}  -- Track to avoid duplicates across viewers
    local results = {
        essential = {},
        utility = {},
    }
    
    -- Map viewer names to source keys
    local viewerKeyMap = {
        ["EssentialCooldownViewer"] = "essential",
        ["UtilityCooldownViewer"] = "utility",
    }
    
    -- Map source keys to multi-tracker keys
    -- multiCustom1 = empty for user manual entries
    -- Essential → multiCustom2, Utility → multiCustom3
    local sourceToTrackerKey = {
        ["essential"] = "multiCustom2",
        ["utility"] = "multiCustom3",
    }
    
    -- Scrape each viewer
    for _, viewerName in ipairs(VIEWERS_TO_SCRAPE) do
        local viewer = _G[viewerName]
        local sourceKey = viewerKeyMap[viewerName] or viewerName
        local trackerKey = sourceToTrackerKey[sourceKey]
        
        if viewer and trackerKey then
            local icons = CollectIcons(viewer)
            
            for _, icon in ipairs(icons) do
                local spellID = GetIconSpellID(icon)
                if spellID and not scrapedSpells[spellID] then
                    scrapedSpells[spellID] = sourceKey
                    
                    -- Check if already in the target multi-tracker
                    if not SpellExistsInTracker(trackerKey, specID, spellID) then
                        if AddSpellToTracker(trackerKey, specID, spellID, sourceKey) then
                            addedCount = addedCount + 1
                            
                            -- Get spell name for results
                            local spellInfo = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellInfo(spellID)
                            local spellName = spellInfo and spellInfo.name or "Unknown"
                            
                            table.insert(results[sourceKey], {
                                id = spellID,
                                name = spellName,
                            })
                            
                            TUICD:PrintDebug(string.format("CDMScraper: Added %s (%d) to %s", spellName, spellID, trackerKey))
                        end
                    end
                end
            end
        else
            if not viewer then
                TUICD:PrintDebug("CDMScraper: Viewer not found: " .. viewerName)
            end
        end
    end
    
    -- Rebuild the multi-trackers after adding spells
    if addedCount > 0 and TUICD.MultiTracker then
        for _, trackerKey in pairs(sourceToTrackerKey) do
            TUICD.MultiTracker:RebuildTracker(trackerKey)
        end
    end
    
    -- Print summary by source
    if addedCount > 0 then
        for source, spells in pairs(results) do
            if #spells > 0 then
                local names = {}
                for _, spell in ipairs(spells) do
                    table.insert(names, spell.name)
                end
                local trackerName = source == "essential" and "Essential Custom Tracker" or "Utility Custom Tracker"
                TUICD:Print(string.format("|cffffcc00%s:|r %s", trackerName, table.concat(names, ", ")))
            end
        end
    end
    
    return addedCount
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local scraperFrame = CreateFrame("Frame")
local hasFiredThisSession = false
local retryCount = 0
local MAX_RETRIES = 10  -- Try up to 10 times (20 seconds total)

-- Check if CDM viewers exist and are ready
local function ViewersExist()
    for _, viewerName in ipairs(VIEWERS_TO_SCRAPE) do
        local viewer = _G[viewerName]
        if viewer then
            return true
        end
    end
    return false
end

-- Check if CDM viewers have icons ready to scrape
local function HasIconsReady()
    for _, viewerName in ipairs(VIEWERS_TO_SCRAPE) do
        local viewer = _G[viewerName]
        if viewer then
            local icons = CollectIcons(viewer)
            if #icons > 0 then
                return true
            end
        end
    end
    return false
end

-- Attempt to scrape, retry if CDM not ready yet
local function TryScrape()
    if hasFiredThisSession then return end
    
    retryCount = retryCount + 1
    
    -- Proceed if we have icons OR if viewers exist and we've waited long enough
    local hasIcons = HasIconsReady()
    local viewersReady = ViewersExist()
    local waitedLongEnough = retryCount >= 3  -- After 6 seconds, try anyway
    
    if hasIcons or (viewersReady and waitedLongEnough) then
        hasFiredThisSession = true
        
        local added = CDMScraper:ScrapeAndAdd()
        
        if added > 0 then
            TUICD:Print(string.format("CDM Scraper: Added %d spell(s) to Custom Tracker", added))
            
            -- Refresh custom tracker display if it exists
            if TUICD.Cooldowns and TUICD.Cooldowns.RebuildCustomTrackerIcons then
                TUICD.Cooldowns:RebuildCustomTrackerIcons()
            end
        end
    elseif retryCount < MAX_RETRIES then
        -- CDM not ready yet, try again in 2 seconds
        C_Timer.After(2.0, TryScrape)
    else
        TUICD:PrintDebug("CDM Scraper: Gave up waiting for CDM viewers after " .. MAX_RETRIES .. " attempts")
        hasFiredThisSession = true  -- Don't try again
    end
end

scraperFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
scraperFrame:SetScript("OnEvent", function(self, event, isLogin, isReload)
    -- Only run once per session
    if hasFiredThisSession then return end
    
    -- Start trying after initial delay
    C_Timer.After(SCRAPE_DELAY, TryScrape)
end)

-- ============================================================================
-- SLASH COMMAND FOR MANUAL SCRAPING
-- ============================================================================

-- Add a manual scrape command (debug only)
SLASH_TUICDMSCRAPE1 = "/tuicdscrape"
SlashCmdList["TUICDMSCRAPE"] = function(msg)
    if not TUICD.debugMode then
        TUICD:Print("Debug mode required. Use |cffFFFFFF/tuicd debug|r to enable.")
        return
    end
    if msg == "help" or msg == "?" then
        TUICD:Print("CDM Scraper commands:")
        TUICD:Print("  /tuicdscrape - Scrape CDM and add new spells to Custom Tracker")
        TUICD:Print("  /tuicdscrape list - Show current entries with sources")
        return
    end
    
    if msg == "list" then
        -- List current custom entries with sources
        local specID = GetCurrentSpecID()
        if not specID then
            TUICD:Print("Could not determine current spec")
            return
        end
        
        InitializeStorage()
        local entries = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID]
        
        if not entries or #entries == 0 then
            TUICD:Print("No custom entries for current spec")
            return
        end
        
        TUICD:Print(string.format("Custom Tracker entries for spec %d:", specID))
        
        for i, entry in ipairs(entries) do
            if entry.type == "spell" then
                local spellInfo = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellInfo(entry.id)
                local name = spellInfo and spellInfo.name or "Unknown"
                local source = entry.source and string.format(" |cff888888(%s)|r", entry.source) or ""
                local status = entry.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
                TUICD:Print(string.format("  %d. [%s] %s (%d)%s", i, status, name, entry.id, source))
            end
        end
        return
    end
    
    -- Default: run scrape
    local added = CDMScraper:ScrapeAndAdd()
    
    if added > 0 then
        TUICD:Print(string.format("CDM Scraper: Added %d spell(s) to Custom Tracker", added))
        
        -- Refresh custom tracker display if it exists
        if TUICD.Cooldowns and TUICD.Cooldowns.RebuildCustomTrackerIcons then
            TUICD.Cooldowns:RebuildCustomTrackerIcons()
        end
    else
        TUICD:Print("CDM Scraper: No new spells to add (all CDM spells already in Custom Tracker)")
    end
end
