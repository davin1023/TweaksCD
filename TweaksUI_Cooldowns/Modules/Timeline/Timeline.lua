-- ============================================================================
-- TUI:CD Timeline - Main Module
-- Displays cooldowns as sliding icons on a horizontal timeline
--
-- Phase 1: Core infrastructure and data layer with GCD filtering
-- Phase 2: Visual frames with sliding icons
-- Phase 3: Settings panel and database persistence
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.Timeline = TUICD.Timeline or {}
local Timeline = TUICD.Timeline

local TimelineData = TUICD.TimelineData
local TimelineFrames  -- Will be set after load
local TimelineUI      -- Will be set after load

-- ============================================================================
-- MODULE STATE
-- ============================================================================

Timeline.loaded = false
Timeline.enabled = false
Timeline.initialized = false

-- ============================================================================
-- DEBUG
-- ============================================================================

local debugMode = false

local function dprint(...)
    if debugMode then
        print("|cff00ccff[Timeline]|r", ...)
    end
end

function Timeline:SetDebug(enabled)
    debugMode = enabled
    if TimelineData then
        TimelineData:SetDebug(enabled)
    end
    if TimelineFrames then
        TimelineFrames:SetDebug(enabled)
    end
    dprint("Debug mode:", enabled and "ON" or "OFF")
end

-- ============================================================================
-- SETTINGS (Placeholder - will be replaced by database in Phase 4)
-- ============================================================================

local DEFAULT_SETTINGS = {
    enabled = false,  -- Disabled by default until we verify it works
    width = 400,
    height = 24,
    iconSize = 24,
    maxDuration = 120,
    direction = "leftToRight",
    readyZoneWidth = 60,
}

local settings = {}

function Timeline:GetSettings()
    return settings
end

function Timeline:GetSetting(key)
    return settings[key]
end

function Timeline:SetSetting(key, value)
    settings[key] = value
    -- TODO: Save to database and refresh frames
end

-- Initialize settings with defaults
local function InitSettings()
    for k, v in pairs(DEFAULT_SETTINGS) do
        if settings[k] == nil then
            settings[k] = v
        end
    end
end

-- ============================================================================
-- EVENT FRAME
-- ============================================================================

local eventFrame = CreateFrame("Frame")
local registeredEvents = {}

local function RegisterEvent(event)
    if not registeredEvents[event] then
        eventFrame:RegisterEvent(event)
        registeredEvents[event] = true
    end
end

local function UnregisterEvent(event)
    if registeredEvents[event] then
        eventFrame:UnregisterEvent(event)
        registeredEvents[event] = nil
    end
end

local function UnregisterAllEvents()
    for event in pairs(registeredEvents) do
        eventFrame:UnregisterEvent(event)
    end
    wipe(registeredEvents)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

local function OnSpellUpdateCooldown()
    if not Timeline.enabled then return end
    
    -- Update all cooldown states
    local changes = TimelineData:UpdateAllStates()
    
    -- Log changes in debug mode
    if debugMode and next(changes) then
        for spellID, change in pairs(changes) do
            dprint(string.format("State change: %s (%d) %s",
                change.name, spellID, change.transition))
        end
    end
    
    -- TODO Phase 2: Update frame positions
end

local function OnPlayerEnteringWorld()
    dprint("PLAYER_ENTERING_WORLD")
    
    -- Rebuild spell list (CDM may have populated)
    C_Timer.After(1.0, function()
        if Timeline.enabled then
            TimelineData:RebuildSpellList()
            TimelineData:UpdateAllStates()
        end
    end)
end

local function OnPlayerSpecializationChanged()
    dprint("PLAYER_SPECIALIZATION_CHANGED")
    
    -- Rebuild spell list for new spec
    if Timeline.enabled then
        C_Timer.After(0.5, function()
            TimelineData:RebuildSpellList()
            TimelineData:UpdateAllStates()
        end)
    end
end

local function OnCooldownManagerInitialized()
    dprint("Cooldown Manager initialized")
    
    -- CDM has populated its viewers - rebuild our spell list
    if Timeline.enabled then
        TimelineData:RebuildSpellList()
        TimelineData:UpdateAllStates()
    end
end

-- Main event handler
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "SPELL_UPDATE_COOLDOWN" then
        OnSpellUpdateCooldown()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnPlayerEnteringWorld()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        OnPlayerSpecializationChanged()
    end
end)

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function Timeline:Initialize()
    if self.initialized then return end
    
    dprint("Initializing...")
    
    -- Load settings
    InitSettings()
    
    -- Get references to sub-modules (loaded after this file)
    TimelineFrames = TUICD.TimelineFrames
    TimelineUI = TUICD.TimelineUI
    
    -- Initialize UI (sets up database defaults) - but DON'T create frames yet
    -- Frames will be created when Enable() is called
    if TimelineUI then
        TimelineUI:Initialize()
    end
    
    -- DON'T initialize TimelineFrames here - the database isn't ready yet
    -- TimelineFrames will be initialized when Enable() is called
    
    -- Mark initialized
    self.initialized = true
    self.loaded = true
    
    dprint("Initialized (frame creation deferred)")
end

function Timeline:Enable()
    if not self.initialized then
        self:Initialize()
    end
    
    -- Always ensure frame is shown, even if already "enabled"
    -- This fixes state sync issues where enabled flag is true but frame isn't visible
    local wasEnabled = self.enabled
    
    if not wasEnabled then
        dprint("Enabling...")
        
        -- Register events
        RegisterEvent("SPELL_UPDATE_COOLDOWN")
        RegisterEvent("PLAYER_ENTERING_WORLD")
        RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        
        -- Build spell list (may be empty if CDM hasn't populated yet)
        TimelineData:RebuildSpellList()
        
        -- Initial state update
        TimelineData:UpdateAllStates()
        
        -- Schedule delayed rebuilds to catch entries after CDM populates
        -- This is necessary because CDM/MultiTracker populate asynchronously
        C_Timer.After(0.5, function()
            if Timeline.enabled then
                TimelineData:RebuildSpellList()
                TimelineData:UpdateAllStates()
            end
        end)
        C_Timer.After(1.5, function()
            if Timeline.enabled then
                TimelineData:RebuildSpellList()
                TimelineData:UpdateAllStates()
            end
        end)
        C_Timer.After(3.0, function()
            if Timeline.enabled then
                TimelineData:RebuildSpellList()
                TimelineData:UpdateAllStates()
            end
        end)
    end
    
    -- Always ensure visual frames are shown (even if state thought it was enabled)
    if TimelineFrames then
        TimelineFrames:Initialize()  -- Ensure frame exists
        TimelineFrames:Enable()       -- Show it
    else
        dprint("WARNING: TimelineFrames not available!")
    end
    
    self.enabled = true
    
    if not wasEnabled then
        dprint("Enabled")
    else
        dprint("Re-synced (was enabled but frame may have been hidden)")
    end
end

function Timeline:Disable()
    if not self.enabled then return end
    
    dprint("Disabling...")
    
    -- Unregister events
    UnregisterAllEvents()
    
    -- Disable visual frames
    if TimelineFrames then
        TimelineFrames:Disable()
    end
    
    self.enabled = false
    
    dprint("Disabled")
end

function Timeline:Toggle()
    if self.enabled then
        self:Disable()
    else
        self:Enable()
    end
end

function Timeline:IsEnabled()
    return self.enabled
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

local function HandleSlashCommand(msg)
    local args = {}
    for word in string.gmatch(msg or "", "%S+") do
        table.insert(args, word)  -- Keep original case for some values
    end
    
    local cmd = args[1] and string.lower(args[1]) or ""
    local arg2 = args[2]
    
    if cmd == "" or cmd == "help" then
        print("|cff00ccff[TUI:CD Timeline]|r Commands:")
        print("  /tuicdtl - Toggle timeline on/off")
        print("  /tuicdtl settings - Open settings panel")
        print("  /tuicdtl debug - Toggle debug mode")
        print("  /tuicdtl spells - List tracked spells")
        print("  /tuicdtl states - Show cooldown states")
        print("  /tuicdtl test - Test GCD filtering")
        print("  /tuicdtl refresh - Rebuild spell list")
        print("  /tuicdtl status - Show module status")
        print("|cff888888Quick Settings:|r")
        print("  /tuicdtl maxdur <seconds> - Set timeline length (default: 30)")
        print("  /tuicdtl iconsize <size> - Set icon size (default: 36)")
        print("  /tuicdtl offset <pixels> - Icon vertical offset (default: 0)")
        print("  /tuicdtl aspect <ratio> - Icon aspect (1:1, 4:3, 16:9, etc)")
        print("  /tuicdtl textsize <size> - Duration text size (default: 10)")
        print("  /tuicdtl textoffset <pixels> - Text position (+ above, - below icon)")
        print("  /tuicdtl text - Toggle duration text on/off")
        print("  /tuicdtl sweep - Toggle cooldown sweep on/off")
        print("  /tuicdtl barwidth <pixels> - Set bar width (default: 400)")
        
    elseif cmd == "debug" then
        debugMode = not debugMode
        Timeline:SetDebug(debugMode)
        print("|cff00ccff[Timeline]|r Debug mode:", debugMode and "|cff00ff00ON|r" or "|cffff0000OFF|r")
        
    elseif cmd == "settings" or cmd == "config" or cmd == "options" then
        if TimelineUI then
            TimelineUI:Toggle()
        else
            print("|cffff0000[Timeline]|r Settings panel not available")
        end
        
    elseif cmd == "spells" then
        TimelineData:DumpTrackedSpells()
        
    elseif cmd == "states" then
        TimelineData:DumpCooldownStates()
        
    elseif cmd == "test" then
        TimelineData:TestGCDFilter()
        
    elseif cmd == "refresh" then
        TimelineData:RebuildSpellList()
        TimelineData:UpdateAllStates()
        print("|cff00ccff[Timeline]|r Spell list refreshed")
        
    elseif cmd == "status" then
        print("|cff00ccff[TUI:CD Timeline]|r Status:")
        print("  Initialized:", Timeline.initialized and "Yes" or "No")
        print("  Enabled (runtime):", Timeline.enabled and "|cff00ff00Yes|r" or "|cffff0000No|r")
        
        -- Check database enabled state
        local dbEnabled = "unknown"
        local DB = TUICD.Database
        if DB and DB.GetModuleSetting then
            local val = DB:GetModuleSetting("timeline", "enabled")
            dbEnabled = val and "|cff00ff00true|r" or "|cffff0000false|r"
        end
        print("  Enabled (database):", dbEnabled)
        print("  Debug:", debugMode and "On" or "Off")
        
        -- Frame state
        if TimelineFrames then
            local frame = TimelineFrames:GetFrame()
            if frame then
                print("  Frame exists:", "|cff00ff00Yes|r")
                print("  Frame shown:", frame:IsShown() and "|cff00ff00Yes|r" or "|cffff0000No|r")
            else
                print("  Frame exists:", "|cffff8800No (not created)|r")
            end
        end
        
        local spellCount = 0
        for _ in pairs(TimelineData:GetTrackedSpells()) do
            spellCount = spellCount + 1
        end
        print("  Tracked Spells:", spellCount)
        
        local onCD, ready = 0, 0
        for _, state in pairs(TimelineData:GetAllStates()) do
            if state.isOnCD then onCD = onCD + 1 else ready = ready + 1 end
        end
        print("  On Cooldown:", onCD)
        print("  Ready:", ready)
        
        -- Show current settings
        if TimelineFrames then
            print("|cff888888Current Settings:|r")
            print("  maxDuration:", TimelineFrames:GetSetting("maxDuration") .. "s")
            print("  iconSize:", TimelineFrames:GetSetting("iconSize"))
            print("  iconAspectRatio:", TimelineFrames:GetSetting("iconAspectRatio"))
            print("  iconVerticalOffset:", TimelineFrames:GetSetting("iconVerticalOffset"))
            print("  cooldownTextSize:", TimelineFrames:GetSetting("cooldownTextSize"))
            print("  cooldownTextOffset:", TimelineFrames:GetSetting("cooldownTextOffset") or 0)
            print("  showCooldownText:", TimelineFrames:GetSetting("showCooldownText") and "Yes" or "No")
            print("  showCooldownSweep:", TimelineFrames:GetSetting("showCooldownSweep") and "Yes" or "No")
            print("  barWidth:", TimelineFrames:GetSetting("barWidth"))
            print("  showBackground:", TimelineFrames:GetSetting("showBackground") and "Yes" or "No")
        end
        
    elseif cmd == "on" or cmd == "enable" then
        Timeline:Enable()
        print("|cff00ccff[Timeline]|r Enabled")
        
    elseif cmd == "off" or cmd == "disable" then
        Timeline:Disable()
        print("|cff00ccff[Timeline]|r Disabled")
    
    -- Settings commands
    elseif cmd == "maxdur" or cmd == "maxduration" then
        local val = tonumber(arg2)
        if val and val > 0 then
            TimelineFrames:SetSetting("maxDuration", val)
            print("|cff00ccff[Timeline]|r Max duration set to", val, "seconds")
        else
            print("|cff00ccff[Timeline]|r Current max duration:", TimelineFrames:GetSetting("maxDuration"), "seconds")
            print("  Usage: /tuicdtl maxdur <seconds>")
        end
        
    elseif cmd == "iconsize" or cmd == "size" then
        local val = tonumber(arg2)
        if val and val > 0 then
            TimelineFrames:SetSetting("iconSize", val)
            print("|cff00ccff[Timeline]|r Icon size set to", val)
        else
            print("|cff00ccff[Timeline]|r Current icon size:", TimelineFrames:GetSetting("iconSize"))
            print("  Usage: /tuicdtl iconsize <pixels>")
        end
        
    elseif cmd == "offset" or cmd == "voffset" then
        local val = tonumber(arg2)
        if val then
            TimelineFrames:SetSetting("iconVerticalOffset", val)
            print("|cff00ccff[Timeline]|r Vertical offset set to", val)
        else
            print("|cff00ccff[Timeline]|r Current vertical offset:", TimelineFrames:GetSetting("iconVerticalOffset"))
            print("  Usage: /tuicdtl offset <pixels> (0 = on bar, positive = above, negative = below)")
        end
        
    elseif cmd == "aspect" or cmd == "ratio" then
        if arg2 then
            local validRatios = { ["1:1"]=true, ["4:3"]=true, ["3:4"]=true, ["16:9"]=true, ["9:16"]=true, ["2:1"]=true, ["1:2"]=true }
            if validRatios[arg2] then
                TimelineFrames:SetSetting("iconAspectRatio", arg2)
                print("|cff00ccff[Timeline]|r Aspect ratio set to", arg2)
            else
                print("|cffff0000[Timeline]|r Invalid ratio. Valid options: 1:1, 4:3, 3:4, 16:9, 9:16, 2:1, 1:2")
            end
        else
            print("|cff00ccff[Timeline]|r Current aspect ratio:", TimelineFrames:GetSetting("iconAspectRatio"))
            print("  Usage: /tuicdtl aspect <ratio> (1:1, 4:3, 3:4, 16:9, 9:16, 2:1, 1:2)")
        end
        
    elseif cmd == "textsize" then
        local val = tonumber(arg2)
        if val and val > 0 then
            TimelineFrames:SetSetting("cooldownTextSize", val)
            print("|cff00ccff[Timeline]|r Text size set to", val)
        else
            print("|cff00ccff[Timeline]|r Current text size:", TimelineFrames:GetSetting("cooldownTextSize"))
            print("  Usage: /tuicdtl textsize <size>")
        end
        
    elseif cmd == "textoffset" or cmd == "toffset" then
        local val = tonumber(arg2)
        if val then
            TimelineFrames:SetSetting("cooldownTextOffset", val)
            print("|cff00ccff[Timeline]|r Text offset set to", val)
        else
            print("|cff00ccff[Timeline]|r Current text offset:", TimelineFrames:GetSetting("cooldownTextOffset") or 0)
            print("  Usage: /tuicdtl textoffset <pixels> (positive = above, negative = below)")
        end
        
    elseif cmd == "text" then
        local current = TimelineFrames:GetSetting("showCooldownText")
        TimelineFrames:SetSetting("showCooldownText", not current)
        print("|cff00ccff[Timeline]|r Duration text:", (not current) and "|cff00ff00ON|r" or "|cffff0000OFF|r")
        
    elseif cmd == "sweep" then
        local current = TimelineFrames:GetSetting("showCooldownSweep")
        TimelineFrames:SetSetting("showCooldownSweep", not current)
        print("|cff00ccff[Timeline]|r Cooldown sweep:", (not current) and "|cff00ff00ON|r" or "|cffff0000OFF|r")
        
    elseif cmd == "barwidth" or cmd == "width" then
        local val = tonumber(arg2)
        if val and val > 0 then
            TimelineFrames:SetSetting("barWidth", val)
            print("|cff00ccff[Timeline]|r Bar width set to", val)
        else
            print("|cff00ccff[Timeline]|r Current bar width:", TimelineFrames:GetSetting("barWidth"))
            print("  Usage: /tuicdtl barwidth <pixels>")
        end
        
    else
        -- Toggle
        Timeline:Toggle()
        print("|cff00ccff[Timeline]|r", Timeline.enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r")
    end
end

-- Register slash command
SLASH_TUICDTIMELINE1 = "/tuicdtl"
SLASH_TUICDTIMELINE2 = "/tuicdtimeline"
SlashCmdList["TUICDTIMELINE"] = HandleSlashCommand

-- ============================================================================
-- ADDON LOAD HOOK
-- ============================================================================

-- Hook into TUICD initialization if available
if TUICD.Events and TUICD.Events.Register then
    TUICD.Events:Register("TUICD_INITIALIZED", function()
        -- First, initialize the Timeline module (sets up references)
        Timeline:Initialize()
        
        -- Then check if enabled in settings and auto-enable
        -- Use a delay to ensure CDM and other systems are ready
        C_Timer.After(0.8, function()
            -- Try to get setting from database
            local enabled = false
            local DB = TUICD.Database
            if DB and DB.GetModuleSetting then
                enabled = DB:GetModuleSetting("timeline", "enabled")
            end
            
            if enabled then
                Timeline:Enable()
            end
        end)
    end, "Timeline")
else
    -- Fallback if Events system isn't available (shouldn't happen)
    print("|cffff0000[Timeline] ERROR: Events system not available!|r")
end

-- DON'T initialize on ADDON_LOADED - the database isn't ready yet
-- Wait for TUICD_INITIALIZED which fires after Main.lua's Initialize() completes

-- ============================================================================
-- RETURN
-- ============================================================================

return Timeline
