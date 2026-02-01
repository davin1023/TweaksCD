-- ============================================================================
-- TUICD: Spell API Wrapper
-- Midnight-native spell API functions
-- All functions use C_Spell namespace directly - no fallbacks
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.SpellAPI = TUICD.SpellAPI or {}
local SpellAPI = TUICD.SpellAPI

-- ============================================================================
-- SPELL INFO
-- ============================================================================

-- Get spell info (returns SpellInfo table or nil)
function SpellAPI:GetSpellInfo(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellInfo(spellID)
end

-- Get spell name
function SpellAPI:GetSpellName(spellID)
    if not spellID then return nil end
    local info = C_Spell.GetSpellInfo(spellID)
    return info and info.name
end

-- Get spell icon texture ID
function SpellAPI:GetSpellTexture(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellTexture(spellID)
end

-- Check if spell is known/usable
function SpellAPI:IsSpellKnown(spellID)
    if not spellID then return false end
    return IsSpellKnown(spellID) or IsPlayerSpell(spellID)
end

-- Check if spell is usable (has resources, not on cooldown conceptually)
function SpellAPI:IsSpellUsable(spellID)
    if not spellID then return false end
    return C_Spell.IsSpellUsable(spellID)
end

-- ============================================================================
-- COOLDOWNS - Duration Object Based
-- ============================================================================

-- Get cooldown as Duration Object (primary method for 2.0+)
function SpellAPI:GetCooldownDuration(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellCooldownDuration(spellID)
end

-- Get charges cooldown as Duration Object
function SpellAPI:GetChargesDuration(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellChargesCooldownDuration(spellID)
end

-- Get loss of control cooldown as Duration Object
function SpellAPI:GetLossOfControlDuration(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellLossOfControlCooldownDuration(spellID)
end

-- Get cooldown info struct (for when you need all fields)
function SpellAPI:GetCooldownInfo(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellCooldown(spellID)
end

-- Get charges info struct
function SpellAPI:GetChargesInfo(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellCharges(spellID)
end

-- ============================================================================
-- COOLDOWN HELPERS
-- ============================================================================

-- Apply cooldown to a cooldown frame using Duration Object
function SpellAPI:ApplyCooldownToFrame(cooldownFrame, spellID, clearIfZero)
    if not cooldownFrame or not spellID then return false end
    
    local duration = self:GetCooldownDuration(spellID)
    if duration then
        cooldownFrame:SetCooldownFromDurationObject(duration, clearIfZero ~= false)
        return true
    end
    return false
end

-- Apply charges cooldown to a cooldown frame
function SpellAPI:ApplyChargesCooldownToFrame(cooldownFrame, spellID, clearIfZero)
    if not cooldownFrame or not spellID then return false end
    
    local duration = self:GetChargesDuration(spellID)
    if duration then
        cooldownFrame:SetCooldownFromDurationObject(duration, clearIfZero ~= false)
        return true
    end
    return false
end

-- Check if spell is on cooldown (simple boolean check)
function SpellAPI:IsOnCooldown(spellID)
    if not spellID then return false end
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then return false end
    
    -- Check if it's a real cooldown (not just GCD)
    if info.duration and info.duration > 1.5 then
        return true
    end
    return false
end

-- Get remaining cooldown time via Duration Object
-- Note: C_Spell.GetSpellCooldownRemaining was REMOVED in Midnight PTR 1
-- Use Duration Object's GetRemainingDuration instead (may return secret value)
function SpellAPI:GetCooldownRemaining(spellID)
    if not spellID then return 0 end
    local durationObj = self:GetCooldownDuration(spellID)
    if durationObj then
        local ok, remaining = pcall(durationObj.GetRemainingDuration, durationObj)
        if ok then return remaining end
    end
    return 0
end

-- Get cooldown remaining as percentage via Duration Object
-- Note: C_Spell.GetSpellCooldownRemainingPercent was REMOVED in Midnight PTR 1
-- Use Duration Object's EvaluateRemainingDuration with a curve instead
function SpellAPI:GetCooldownRemainingPercent(spellID, curve)
    if not spellID then return 0 end
    local durationObj = self:GetCooldownDuration(spellID)
    if durationObj then
        local scaleCurve = curve or (CurveConstants and CurveConstants.ScaleTo100)
        if scaleCurve then
            local ok, result = pcall(durationObj.EvaluateRemainingDuration, durationObj, scaleCurve)
            if ok then return result end
        end
    end
    return 0
end

-- ============================================================================
-- DISPLAY COUNT
-- ============================================================================

-- Get display count for consumable spells (charges, stacks, etc.)
function SpellAPI:GetDisplayCount(spellID)
    if not spellID then return nil end
    return C_Spell.GetSpellDisplayCount(spellID)
end

-- ============================================================================
-- SPELL PROPERTIES
-- ============================================================================

-- Check if spell is harmful (offensive)
function SpellAPI:IsHarmful(spellID)
    if not spellID then return false end
    return C_Spell.IsSpellHarmful(spellID)
end

-- Check if spell is helpful (beneficial)
function SpellAPI:IsHelpful(spellID)
    if not spellID then return false end
    return C_Spell.IsSpellHelpful(spellID)
end

-- Check if spell is "important" (per Blizzard's classification)
function SpellAPI:IsImportant(spellID)
    if not spellID then return false end
    return C_Spell.IsSpellImportant(spellID)
end

-- Check if spell is consumable (uses charges or items)
function SpellAPI:IsConsumable(spellID)
    if not spellID then return false end
    return C_Spell.IsConsumableSpell(spellID)
end

-- Check if spell is in range of target
function SpellAPI:IsInRange(spellID, unit)
    if not spellID then return nil end
    return C_Spell.IsSpellInRange(spellID, unit or "target")
end

-- Check if spell is usable (has resources, not on cooldown preventing use, etc.)
-- Returns: usable, insufficientPower
function SpellAPI:IsUsable(spellID)
    if not spellID then return false, false end
    if C_Spell and C_Spell.IsSpellUsable then
        return C_Spell.IsSpellUsable(spellID)
    elseif IsUsableSpell then
        return IsUsableSpell(spellID)
    end
    return true, false  -- Assume usable if API unavailable
end

-- ============================================================================
-- SECRECY CHECKS
-- ============================================================================

-- Check if spell cooldown is secret (always/contextual/never)
function SpellAPI:GetCooldownSecrecy(spellID)
    if not spellID then return nil end
    return C_Secrets.GetSpellCooldownSecrecy(spellID)
end

-- Check if spell cooldown is currently secret
function SpellAPI:IsCooldownCurrentlySecret(spellID)
    if not spellID then return false end
    local secrecy = C_Secrets.GetSpellCooldownSecrecy(spellID)
    if secrecy == Enum.SecrecyLevel.NeverSecret then
        return false
    elseif secrecy == Enum.SecrecyLevel.AlwaysSecret then
        return true
    else
        -- Contextual - check current restriction state
        return C_Secrets.ShouldSpellCooldownBeSecret(spellID)
    end
end

-- Check if spell aura is secret
function SpellAPI:GetAuraSecrecy(spellID)
    if not spellID then return nil end
    return C_Secrets.GetSpellAuraSecrecy(spellID)
end

-- Check if spell cast is secret
function SpellAPI:GetCastSecrecy(spellID)
    if not spellID then return nil end
    return C_Secrets.GetSpellCastSecrecy(spellID)
end

-- ============================================================================
-- SPELL LOOKUP BY NAME
-- ============================================================================

-- Find spell ID by name (searches player's known spells)
function SpellAPI:FindSpellIDByName(spellName)
    if not spellName then return nil end
    
    -- Try direct lookup first
    local spellInfo = C_Spell.GetSpellInfo(spellName)
    if spellInfo then
        return spellInfo.spellID
    end
    
    return nil
end

-- ============================================================================
-- GCD HANDLING
-- ============================================================================

-- GCD spell ID (used for tracking global cooldown)
SpellAPI.GCD_SPELL_ID = 61304

-- Get GCD duration object
function SpellAPI:GetGCDDuration()
    return self:GetCooldownDuration(self.GCD_SPELL_ID)
end

-- Check if GCD is active
function SpellAPI:IsGCDActive()
    local info = self:GetCooldownInfo(self.GCD_SPELL_ID)
    return info and info.duration and info.duration > 0
end

return SpellAPI
