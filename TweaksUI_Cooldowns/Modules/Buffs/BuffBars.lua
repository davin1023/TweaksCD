-- ============================================================================
-- TUICD: Buff Timer Bars - Module Entry Point
-- Registers with ModuleManager, wires data layer to frame layer
-- Tracks buffs from CDM Buff Tracker via auraInstanceID
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Create module via ModuleManager
-- (MODULE_IDS.BUFF_BARS and EVENTS are defined in Constants.lua)
local BuffBars = TUICD.ModuleManager:NewModule(
    TUICD.MODULE_IDS.BUFF_BARS,
    "Buff Timer Bars",
    "Individual timer bars for tracked buffs (from CDM Buff Tracker)"
)

if not BuffBars then 
    print("|cffff0000[TUI:CD]|r BuffBars module failed to register!")
    return 
end

-- Expose globally for cross-module access
TUICD.BuffBars = BuffBars

local BuffBarsData = TUICD.BuffBarsData
local BuffBarsFrames = TUICD.BuffBarsFrames
local BuffBarsUI = TUICD.BuffBarsUI

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function BuffBars:OnInitialize()
    -- Ensure DB tables exist
    local db = TUICD.Database:GetDB()
    if not db then return end
    
    -- Initialize buffBars settings namespace
    if not db.buffBars then db.buffBars = {} end
    if not db.buffBars.spells then db.buffBars.spells = {} end
    if not db.buffBars.positions then db.buffBars.positions = {} end
    if not db.buffBars.dockSettings then db.buffBars.dockSettings = {} end
    
    -- Initialize BuffBarsData
    if BuffBarsData and BuffBarsData.Initialize then
        BuffBarsData:Initialize()
    end
    
    self.loaded = true
    TUICD:PrintDebug("BuffBars module initialized")
end

function BuffBars:OnEnable()
    -- Register data events first (sets up PLAYER_ENTERING_WORLD handler)
    if BuffBarsData and BuffBarsData.RegisterEvents then
        BuffBarsData:RegisterEvents()
    end
    
    -- Initialize frames (creates frame pool and sets up callbacks)
    if BuffBarsFrames and BuffBarsFrames.Initialize then
        BuffBarsFrames:Initialize()
    end

    -- Wire settings changes to frame config refresh
    if TUICD.Events then
        TUICD.Events:Register(TUICD.EVENTS.BUFF_BARS_SETTINGS_CHANGED, function(barKey, key, value)
            if barKey and BuffBarsFrames then
                BuffBarsFrames:OnConfigChanged(barKey)
            end
        end)
    end

    -- CRITICAL: If player is already in world (module enabled after login),
    -- we need to trigger discovery immediately since PLAYER_ENTERING_WORLD won't fire again
    if IsLoggedIn() and BuffBarsData then
        C_Timer.After(0.5, function()
            BuffBarsData:ImmediateStartup()
        end)
    end

    self.enabled = true
    TUICD:PrintDebug("BuffBars module enabled")
end

function BuffBars:OnDisable()
    -- Stop polling
    if BuffBarsData and BuffBarsData.StopPoll then
        BuffBarsData:StopPoll()
    end
    
    -- Unregister callbacks
    if BuffBarsData then
        BuffBarsData:UnregisterUpdateCallback("frames")
    end
    
    -- Hide all frames
    if BuffBarsFrames and BuffBarsFrames.HideAll then
        BuffBarsFrames:HideAll()
    end

    self.enabled = false
    TUICD:PrintDebug("BuffBars module disabled")
end

-- ============================================================================
-- SETTINGS UI INTEGRATION
-- ============================================================================

function BuffBars:GetSettingsPanel()
    if BuffBarsUI then
        return BuffBarsUI:GetOrCreatePanel()
    end
    return nil
end

function BuffBars:ToggleSettings()
    if BuffBarsUI then
        BuffBarsUI:Toggle()
    end
end

-- Alias for Settings hub compatibility
function BuffBars:TogglePanel()
    self:ToggleSettings()
end

-- ============================================================================
-- API
-- ============================================================================

-- Get tracked spells configuration
function BuffBars:GetTrackedSpells()
    if BuffBarsData then
        return BuffBarsData:GetTrackedSpells()
    end
    return {}
end

-- Toggle layout mode
function BuffBars:ToggleLayoutMode()
    if BuffBarsFrames then
        BuffBarsFrames:ToggleLayoutMode()
    end
end

-- Check if layout mode is active
function BuffBars:IsLayoutMode()
    if BuffBarsFrames then
        return BuffBarsFrames:IsLayoutMode()
    end
    return false
end

-- Force refresh all bars
function BuffBars:RefreshAll()
    if BuffBarsData and BuffBarsData.UpdateAll then
        BuffBarsData:UpdateAll()
    end
end

return BuffBars
