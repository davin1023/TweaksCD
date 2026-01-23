-- ============================================================================
-- TUICD: Restriction API Wrapper
-- Midnight addon restriction state monitoring and handling
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.RestrictionAPI = TUICD.RestrictionAPI or {}
local RestrictionAPI = TUICD.RestrictionAPI

-- ============================================================================
-- STATE TRACKING
-- ============================================================================

-- Cache of current restriction states
local restrictionStates = {}

-- Event frame for monitoring
local eventFrame = CreateFrame("Frame")

-- Initialize restriction states
local function InitializeStates()
    -- Initialize all restriction types
    for name, restrictionType in pairs(Enum.AddOnRestrictionType) do
        if type(restrictionType) == "number" then
            local success, state = pcall(C_RestrictedActions.GetRestrictionState, restrictionType)
            if success then
                restrictionStates[restrictionType] = state
            else
                restrictionStates[restrictionType] = Enum.AddOnRestrictionState.Inactive
            end
        end
    end
end

-- Handle restriction state changes
local function OnRestrictionStateChanged(restrictionType, newState)
    local oldState = restrictionStates[restrictionType]
    restrictionStates[restrictionType] = newState
    
    -- Fire TUICD event
    if TUICD.Events then
        TUICD.Events:Fire(TUICD.EVENTS.RESTRICTION_CHANGED, restrictionType, newState, oldState)
        
        -- Fire convenience events for secrets active/inactive
        if newState == Enum.AddOnRestrictionState.Active then
            TUICD.Events:Fire(TUICD.EVENTS.SECRETS_ACTIVE, restrictionType)
        elseif oldState == Enum.AddOnRestrictionState.Active and newState == Enum.AddOnRestrictionState.Inactive then
            TUICD.Events:Fire(TUICD.EVENTS.SECRETS_INACTIVE, restrictionType)
        end
    end
end

-- Register for events
eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restrictionType, newState = ...
        OnRestrictionStateChanged(restrictionType, newState)
    elseif event == "PLAYER_ENTERING_WORLD" then
        InitializeStates()
    end
end)

-- ============================================================================
-- STATE QUERIES
-- ============================================================================

-- Get current state for a restriction type
function RestrictionAPI:GetState(restrictionType)
    return restrictionStates[restrictionType] or Enum.AddOnRestrictionState.Inactive
end

-- Check if a restriction is currently active
function RestrictionAPI:IsActive(restrictionType)
    return self:GetState(restrictionType) == Enum.AddOnRestrictionState.Active
end

-- Check if a restriction is activating (transitioning to active)
function RestrictionAPI:IsActivating(restrictionType)
    return self:GetState(restrictionType) == Enum.AddOnRestrictionState.Activating
end

-- Check if a restriction is inactive
function RestrictionAPI:IsInactive(restrictionType)
    return self:GetState(restrictionType) == Enum.AddOnRestrictionState.Inactive
end

-- ============================================================================
-- CONVENIENCE QUERIES
-- ============================================================================

-- Check if combat restriction is active
function RestrictionAPI:IsInCombat()
    return self:IsActive(Enum.AddOnRestrictionType.Combat)
end

-- Check if encounter restriction is active
function RestrictionAPI:IsInEncounter()
    return self:IsActive(Enum.AddOnRestrictionType.Encounter)
end

-- Check if M+ restriction is active
function RestrictionAPI:IsInChallengeMode()
    return self:IsActive(Enum.AddOnRestrictionType.ChallengeMode)
end

-- Check if PvP restriction is active
function RestrictionAPI:IsInPvPMatch()
    return self:IsActive(Enum.AddOnRestrictionType.PvPMatch)
end

-- Check if map restriction is active
function RestrictionAPI:IsInRestrictedMap()
    return self:IsActive(Enum.AddOnRestrictionType.Map)
end

-- Check if ANY combat-related restriction is active
function RestrictionAPI:IsInRestrictedContent()
    return self:IsInCombat() or 
           self:IsInEncounter() or 
           self:IsInChallengeMode() or 
           self:IsInPvPMatch()
end

-- Check if in instance-related restriction (M+, encounter, PvP)
function RestrictionAPI:IsInRestrictedInstance()
    return self:IsInEncounter() or 
           self:IsInChallengeMode() or 
           self:IsInPvPMatch()
end

-- ============================================================================
-- ALL ACTIVE RESTRICTIONS
-- ============================================================================

-- Get list of all currently active restrictions
function RestrictionAPI:GetActiveRestrictions()
    local active = {}
    for restrictionType, state in pairs(restrictionStates) do
        if state == Enum.AddOnRestrictionState.Active then
            table.insert(active, restrictionType)
        end
    end
    return active
end

-- Get human-readable names for restriction types
function RestrictionAPI:GetRestrictionName(restrictionType)
    local names = {
        [Enum.AddOnRestrictionType.Combat] = "Combat",
        [Enum.AddOnRestrictionType.Encounter] = "Encounter",
        [Enum.AddOnRestrictionType.ChallengeMode] = "Mythic+",
        [Enum.AddOnRestrictionType.PvPMatch] = "PvP Match",
        [Enum.AddOnRestrictionType.Map] = "Map",
    }
    return names[restrictionType] or "Unknown"
end

-- ============================================================================
-- SECRECY CHECKS
-- ============================================================================

-- Check if cooldowns are currently secret
function RestrictionAPI:AreCooldownsSecret()
    return self:IsInRestrictedContent()
end

-- Check if auras are currently secret
function RestrictionAPI:AreAurasSecret()
    return self:IsInRestrictedContent()
end

-- Check if unit identity is currently secret (in instance)
function RestrictionAPI:IsUnitIdentitySecret()
    return self:IsInRestrictedInstance() or self:IsInRestrictedMap()
end

-- Check if spellcasts are currently secret
function RestrictionAPI:AreSpellcastsSecret()
    -- Player's own casts are never secret
    -- Enemy casts are secret in restricted content
    return self:IsInRestrictedContent()
end

-- ============================================================================
-- SPECIFIC API SECRECY CHECKS
-- ============================================================================

-- Check if a specific spell's cooldown would be secret right now
function RestrictionAPI:WouldSpellCooldownBeSecret(spellID)
    if not spellID then return true end
    return C_Secrets.ShouldSpellCooldownBeSecret(spellID)
end

-- Check if a specific unit's spellcast would be secret right now
function RestrictionAPI:WouldUnitSpellCastBeSecret(unit)
    if not unit then return true end
    return C_Secrets.ShouldUnitSpellCastBeSecret(unit)
end

-- Check if unit comparison would be secret
function RestrictionAPI:WouldUnitComparisonBeSecret(unit1, unit2)
    if not unit1 or not unit2 then return true end
    return C_Secrets.ShouldUnitComparisonBeSecret(unit1, unit2)
end

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

-- Print current restriction status
function RestrictionAPI:PrintStatus()
    TUICD:Print("=== Restriction Status ===")
    
    local typeNames = {
        [Enum.AddOnRestrictionType.Combat] = "Combat",
        [Enum.AddOnRestrictionType.Encounter] = "Encounter", 
        [Enum.AddOnRestrictionType.ChallengeMode] = "Challenge Mode (M+)",
        [Enum.AddOnRestrictionType.PvPMatch] = "PvP Match",
        [Enum.AddOnRestrictionType.Map] = "Map",
    }
    
    local stateNames = {
        [Enum.AddOnRestrictionState.Inactive] = "|cff888888Inactive|r",
        [Enum.AddOnRestrictionState.Activating] = "|cffffff00Activating|r",
        [Enum.AddOnRestrictionState.Active] = "|cffff0000ACTIVE|r",
    }
    
    for restrictionType, name in pairs(typeNames) do
        local state = self:GetState(restrictionType)
        local stateStr = stateNames[state] or "Unknown"
        print(string.format("  %s: %s", name, stateStr))
    end
    
    print("")
    TUICD:Print("Cooldowns Secret: " .. (self:AreCooldownsSecret() and "|cffff0000YES|r" or "|cff00ff00No|r"))
    TUICD:Print("Auras Secret: " .. (self:AreAurasSecret() and "|cffff0000YES|r" or "|cff00ff00No|r"))
    TUICD:Print("Unit Identity Secret: " .. (self:IsUnitIdentitySecret() and "|cffff0000YES|r" or "|cff00ff00No|r"))
end

-- Slash command
SLASH_TUIRESTRICT1 = "/tuirestrict"
SlashCmdList["TUIRESTRICT"] = function()
    RestrictionAPI:PrintStatus()
end

return RestrictionAPI
