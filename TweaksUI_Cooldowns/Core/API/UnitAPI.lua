-- ============================================================================
-- TUICD: Unit API Wrapper
-- Midnight-native unit API functions
-- Handles health, power, and unit comparison APIs
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.UnitAPI = TUICD.UnitAPI or {}
local UnitAPI = TUICD.UnitAPI

-- ============================================================================
-- HEALTH APIs
-- ============================================================================

-- Get unit health (may be secret in restricted contexts)
function UnitAPI:GetHealth(unit)
    if not unit then return 0 end
    return UnitHealth(unit)
end

-- Get unit max health (non-secret for player units)
function UnitAPI:GetHealthMax(unit)
    if not unit then return 0 end
    return UnitHealthMax(unit)
end

-- Get health percentage scaled to 0-100 range
-- Uses CurveConstants.ScaleTo100 (required for 0-100 in Midnight)
function UnitAPI:GetHealthPercent(unit, usePredicted, customCurve)
    if not unit then return 0 end
    return UnitHealthPercent(unit, usePredicted, customCurve or CurveConstants.ScaleTo100)
end

-- Get missing health
function UnitAPI:GetHealthMissing(unit)
    if not unit then return 0 end
    return UnitHealthMissing(unit)
end

-- Check if max health would be secret for this unit
function UnitAPI:IsHealthMaxSecret(unit)
    if not unit then return true end
    return C_Secrets.ShouldUnitHealthMaxBeSecret(unit)
end

-- ============================================================================
-- POWER APIs
-- ============================================================================

-- Get unit power (may be secret for primary resources)
function UnitAPI:GetPower(unit, powerType)
    if not unit then return 0 end
    return UnitPower(unit, powerType)
end

-- Get unit max power (non-secret for player units)
function UnitAPI:GetPowerMax(unit, powerType)
    if not unit then return 0 end
    return UnitPowerMax(unit, powerType)
end

-- Get power percentage scaled to 0-100 range
-- Uses CurveConstants.ScaleTo100 (required for 0-100 in Midnight)
function UnitAPI:GetPowerPercent(unit, powerType, customCurve)
    if not unit then return 0 end
    return UnitPowerPercent(unit, powerType, customCurve or CurveConstants.ScaleTo100)
end

-- Get missing power
function UnitAPI:GetPowerMissing(unit, powerType)
    if not unit then return 0 end
    return UnitPowerMissing(unit, powerType)
end

-- Get power type secrecy
function UnitAPI:GetPowerTypeSecrecy(powerType)
    return C_Secrets.GetPowerTypeSecrecy(powerType)
end

-- ============================================================================
-- SECONDARY RESOURCES (Non-secret in Midnight)
-- ============================================================================

-- These are specifically non-secret: Combo Points, Runes, Soul Shards,
-- Holy Power, Chi, Arcane Charges, Essence

-- Get combo points (non-secret)
function UnitAPI:GetComboPoints(unit, target)
    return GetComboPoints(unit or "player", target or "target")
end

-- Get charged power points (for empowered combo points)
function UnitAPI:GetChargedPowerPoints(unit)
    return GetUnitChargedPowerPoints(unit or "player")
end

-- Get stagger amount (non-secret for player)
function UnitAPI:GetStagger(unit)
    if not unit then return 0 end
    return UnitStagger(unit)
end

-- ============================================================================
-- UNIT COMPARISON
-- ============================================================================

-- Check if two units are the same
-- Note: Returns non-secret for target, focus, mouseover, softenemy, etc.
function UnitAPI:IsUnit(unit1, unit2)
    if not unit1 or not unit2 then return false end
    return UnitIsUnit(unit1, unit2)
end

-- Check if unit comparison would be secret
function UnitAPI:IsUnitComparisonSecret(unit1, unit2)
    if not unit1 or not unit2 then return true end
    return C_Secrets.ShouldUnitComparisonBeSecret(unit1, unit2)
end

-- Check if unit is player's current target (non-secret result)
function UnitAPI:IsPlayerTarget(unit)
    if not unit then return false end
    return UnitIsUnit(unit, "target")
end

-- Check if unit is player's focus (non-secret result)
function UnitAPI:IsPlayerFocus(unit)
    if not unit then return false end
    return UnitIsUnit(unit, "focus")
end

-- Check if unit is player's mouseover (non-secret result)
function UnitAPI:IsPlayerMouseover(unit)
    if not unit then return false end
    return UnitIsUnit(unit, "mouseover")
end

-- ============================================================================
-- UNIT IDENTITY
-- ============================================================================

-- Get unit name (may be secret for enemies in instances)
function UnitAPI:GetName(unit)
    if not unit then return nil end
    return UnitName(unit)
end

-- Get unit GUID (may be secret in restricted contexts)
function UnitAPI:GetGUID(unit)
    if not unit then return nil end
    return UnitGUID(unit)
end

-- Get creature ID from unit (may be secret in instances)
function UnitAPI:GetCreatureID(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    
    -- Parse creature ID from GUID
    local creatureID = select(6, strsplit("-", guid))
    return tonumber(creatureID)
end

-- ============================================================================
-- UNIT STATE
-- ============================================================================

-- Check if unit exists
function UnitAPI:Exists(unit)
    if not unit then return false end
    return UnitExists(unit)
end

-- Check if unit is dead
function UnitAPI:IsDead(unit)
    if not unit then return false end
    return UnitIsDead(unit) or UnitIsGhost(unit)
end

-- Check if unit is connected (for players)
function UnitAPI:IsConnected(unit)
    if not unit then return false end
    return UnitIsConnected(unit)
end

-- Check if unit is in range
function UnitAPI:InRange(unit)
    if not unit then return false end
    return UnitInRange(unit)
end

-- Get unit reaction (hostile/neutral/friendly)
function UnitAPI:GetReaction(unit)
    if not unit then return nil end
    return UnitReaction("player", unit)
end

-- Check if unit is hostile
function UnitAPI:IsHostile(unit)
    local reaction = self:GetReaction(unit)
    return reaction and reaction <= 4
end

-- Check if unit is friendly
function UnitAPI:IsFriendly(unit)
    local reaction = self:GetReaction(unit)
    return reaction and reaction >= 5
end

-- ============================================================================
-- UNIT CLASSIFICATION
-- ============================================================================

-- Get unit classification (normal, elite, rare, rareelite, worldboss)
function UnitAPI:GetClassification(unit)
    if not unit then return nil end
    return UnitClassification(unit)
end

-- Check if unit is a boss
function UnitAPI:IsBoss(unit)
    local classification = self:GetClassification(unit)
    return classification == "worldboss" or UnitLevel(unit) == -1
end

-- Check if unit is elite
function UnitAPI:IsElite(unit)
    local classification = self:GetClassification(unit)
    return classification == "elite" or classification == "rareelite" or classification == "worldboss"
end

-- Check if unit is rare
function UnitAPI:IsRare(unit)
    local classification = self:GetClassification(unit)
    return classification == "rare" or classification == "rareelite"
end

-- ============================================================================
-- PLAYER-SPECIFIC
-- ============================================================================

-- Check if unit is the player
function UnitAPI:IsPlayer(unit)
    if not unit then return false end
    return UnitIsUnit(unit, "player")
end

-- Check if unit is in player's group
function UnitAPI:IsInGroup(unit)
    if not unit then return false end
    return UnitInParty(unit) or UnitInRaid(unit)
end

-- Get player's spec ID
function UnitAPI:GetPlayerSpecID()
    return GetSpecialization() and GetSpecializationInfo(GetSpecialization())
end

-- Get player's class
function UnitAPI:GetPlayerClass()
    local _, class = UnitClass("player")
    return class
end

-- ============================================================================
-- MOUNTED / TRAVEL FORM
-- ============================================================================

-- Check if player is mounted OR in druid travel form
-- This treats druid travel forms as "mounted" for visibility purposes
function UnitAPI:IsMountedOrTravelForm()
    -- First check standard mounted state
    if IsMounted() then
        return true
    end
    
    -- Check for druid travel forms
    local _, playerClass = UnitClass("player")
    if playerClass == "DRUID" then
        local formID = GetShapeshiftForm()
        -- Druid travel-related forms:
        -- The exact indices can vary but we check common travel form indices
        -- Form 3 is typically Travel Form (ground/flight)
        -- Form 4 is typically Aquatic Form
        -- We also check GetShapeshiftFormID for the spell ID
        if formID and formID > 0 then
            local spellID = select(4, GetShapeshiftFormInfo(formID))
            -- Known travel form spell IDs
            if spellID == 783 or      -- Travel Form
               spellID == 165962 or   -- Flight Form (old)
               spellID == 210053 or   -- Mount Form (stag)
               spellID == 1066 then   -- Aquatic Form
                return true
            end
        end
    end
    
    -- Also check shaman Ghost Wolf (optional - uncomment if desired)
    -- if playerClass == "SHAMAN" then
    --     local aura = C_UnitAuras.GetPlayerAuraBySpellID(2645) -- Ghost Wolf
    --     if aura then return true end
    -- end
    
    return false
end

-- ============================================================================
-- THREAT
-- ============================================================================

-- Get threat status for unit
function UnitAPI:GetThreatStatus(unit, otherUnit)
    if not unit then return 0 end
    return UnitThreatSituation(unit, otherUnit)
end

-- Check if unit has aggro
function UnitAPI:HasAggro(unit)
    local status = self:GetThreatStatus(unit)
    return status and status >= 2
end

return UnitAPI
