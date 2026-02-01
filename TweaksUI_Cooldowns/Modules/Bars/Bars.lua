-- ============================================================================
-- TUICD: Timer Bars - Module Entry Point
-- Registers with ModuleManager, wires data layer to frame layer
-- Cooldown-only tracking via compound barKeys (e.g. "258920:cd")
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Create module via ModuleManager
local Bars = TUICD.ModuleManager:NewModule(
    TUICD.MODULE_IDS.BARS,
    "Timer Bars",
    "Individual timer bars for tracked cooldowns"
)

if not Bars then return end

-- Expose globally for cross-module access
TUICD.Bars = Bars

local BarsData = TUICD.BarsData
local BarsFrames = TUICD.BarsFrames
local BarsUI = TUICD.BarsUI

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

function Bars:OnInitialize()
    -- Ensure DB tables exist (also triggers migration if needed)
    local settings = TUICD.Database:GetModuleSettings("bars")
    if not settings.spells then settings.spells = {} end
    if not settings.positions then settings.positions = {} end

    self.loaded = true
    TUICD:PrintDebug("Bars module initialized")
end

function Bars:OnEnable()
    -- Register data events (instant response layer)
    BarsData:RegisterEvents()

    -- Wire data updates to frame updates
    BarsData:RegisterUpdateCallback("frames", function(barKey)
        BarsFrames:OnDataUpdate(barKey)
    end)

    -- Wire settings changes to frame config refresh
    TUICD.Events:Register(TUICD.EVENTS.BARS_SETTINGS_CHANGED, function(barKey, key, value)
        if barKey then
            BarsFrames:OnConfigChanged(barKey)
        end
    end)

    -- Wire spell add/remove events
    TUICD.Events:Register(TUICD.EVENTS.BARS_DATA_UPDATED, function(barKey, action)
        if action == "added" then
            BarsFrames:OnSpellAdded(barKey)
        elseif action == "removed" then
            BarsFrames:OnSpellRemoved(barKey)
        end
        BarsUI:Refresh()
    end)

    -- Create frames for all tracked spells
    BarsFrames:CreateAllBars()

    -- ====================================================================
    -- UNIFIED TICKER: detection + display in one pass, 5x per second
    -- ====================================================================
    self.unifiedTicker = C_Timer.NewTicker(0.2, function()
        local spells = BarsData:GetTrackedSpells()
        for barKey, config in pairs(spells) do
            if config.enabled then
                BarsData:UpdateCooldownState(barKey)
                BarsFrames:UpdateBarDisplay(barKey)
            end
        end
    end)

    -- Also start text ticker (updates time text at 10hz)
    BarsFrames:StartTextTicker()

    -- Initial state + display update (delayed for API readiness)
    C_Timer.After(0.5, function()
        local spells = BarsData:GetTrackedSpells()
        for barKey, config in pairs(spells) do
            if config.enabled then
                BarsData:UpdateCooldownState(barKey)
                BarsFrames:UpdateBarDisplay(barKey)
            end
        end
        TUICD:Print("Bars active: " .. BarsData:GetSpellCount() .. " spells tracked, ticker running.")
    end)

    -- Register with Layout Mode
    if TUICD.Layout then
        TUICD.Layout:RegisterCallback("OnLayoutModeEnter", function()
            BarsFrames:EnterLayoutMode()
        end)
        TUICD.Layout:RegisterCallback("OnLayoutModeExit", function()
            BarsFrames:ExitLayoutMode()
        end)
    end

    self.enabled = true
    TUICD:PrintDebug("Bars module enabled")
end

function Bars:OnDisable()
    if self.unifiedTicker then
        self.unifiedTicker:Cancel()
        self.unifiedTicker = nil
    end
    BarsFrames:StopTextTicker()
    BarsFrames:DestroyAllBars()
    BarsData:UnregisterEvents()
    BarsData:UnregisterUpdateCallback("frames")

    self.enabled = false
    TUICD:PrintDebug("Bars module disabled")
end

-- ============================================================================
-- PANEL CONTROL (called from Settings hub)
-- ============================================================================

function Bars:TogglePanel()
    BarsUI:Toggle()
end

function Bars:HideAllPanels()
    BarsUI:HideAllPanels()
end

-- ============================================================================
-- SLASH COMMAND HELPERS
-- ============================================================================

-- /tuicd bars add <spellID>
-- /tuicd bars remove <barKey or spellID>
-- /tuicd bars list
function Bars:HandleSlashCommand(args)
    if not args or args == "" then
        self:TogglePanel()
        return
    end

    local cmd, arg1 = strsplit(" ", args, 2)
    cmd = cmd and cmd:lower() or ""

    if cmd == "add" then
        local spellID = tonumber(arg1)
        if not spellID then
            TUICD:Print("Usage: /tuicd bars add <spellID>")
            return
        end
        local barKey = BarsData:AddSpell(spellID, BarsData.TYPE_COOLDOWN)
        if barKey then
            BarsFrames:OnSpellAdded(barKey)
            local name = TUICD.SpellAPI:GetSpellName(spellID) or tostring(spellID)
            TUICD:Print("Added bar for: " .. name)
        else
            TUICD:Print("Spell " .. spellID .. " is already tracked.")
        end

    elseif cmd == "remove" then
        if not arg1 then
            TUICD:Print("Usage: /tuicd bars remove <barKey or spellID>")
            return
        end
        -- Try as barKey first (e.g. "258920:cd")
        if BarsData:RemoveSpell(arg1) then
            BarsFrames:OnSpellRemoved(arg1)
            TUICD:Print("Removed bar: " .. arg1)
        else
            -- Try as spellID
            local spellID = tonumber(arg1)
            if spellID then
                local barKey = BarsData.MakeBarKey(spellID, BarsData.TYPE_COOLDOWN)
                if BarsData:RemoveSpell(barKey) then
                    BarsFrames:OnSpellRemoved(barKey)
                    TUICD:Print("Removed bar for spell " .. spellID)
                else
                    TUICD:Print("Spell " .. spellID .. " is not tracked.")
                end
            else
                TUICD:Print("Bar key " .. arg1 .. " not found.")
            end
        end

    elseif cmd == "list" then
        local spells = BarsData:GetSpellList()
        if #spells == 0 then
            TUICD:Print("No spells tracked in Timer Bars.")
        else
            TUICD:Print("Timer Bars (" .. #spells .. " entries):")
            for _, entry in ipairs(spells) do
                local state = BarsData:GetSpellState(entry.barKey)
                local status = state and state.isActive and "|cffff0000ON CD|r" or "|cff00ff00Ready|r"
                print(string.format("  %s [%s] - %s", entry.name, entry.barKey, status))
            end
        end

    else
        TUICD:Print("Timer Bars commands: add <spellID>, remove <barKey>, list")
    end
end

return Bars
