-- ============================================================================
-- TUI:CD: Buff Identity Bridge
-- Combat-safe spellID identification for BuffIconCooldownViewer frames
--
-- PROBLEM: During combat/M+/encounters, aura APIs return secret values.
-- icon.spellID, icon:GetSpellID(), and auraData.spellId all become tainted.
-- GetPlayerAuraBySpellID is blocked entirely.
--
-- SOLUTION: Hook CDM's SetAuraInstanceInfo on each buff frame.
-- Read cooldownInfo.spellID (static CDM config data, NEVER secret) and
-- auraInstanceID (non-secret since Alpha 6) to build a combat-safe
-- identity mapping that persists through all restriction states.
--
-- CONSUMERS: BuffHighlights, BuffBarsData, BuffBarsFrames, BuffBarsUI
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.BuffIdentityBridge = {}
local Bridge = TUICD.BuffIdentityBridge

local SpellAPI = TUICD.SpellAPI

-- ============================================================================
-- STATE
-- ============================================================================

-- Core identity mappings (combat-safe, populated from CDM hooks)
local auraIDToSpell = {}    -- [auraInstanceID] = { spellID, name, texture }
local spellIDToAuraID = {}  -- [spellID] = auraInstanceID (current active only)

-- Slot position mappings (rebuilt on Layout, transient)
local slotToSpellID = {}    -- [slotIndex] = spellID
local spellIDToSlot = {}    -- [spellID] = slotIndex

-- Hook tracking
local hookedFrames = {}     -- [frame] = true
local viewerHooked = false
local initialized = false

-- Debug
local debugMode = false

local function dprint(msg)
    if debugMode then
        print("|cff88ccff[BIB]|r " .. msg)
    end
end

-- ============================================================================
-- SPELL IDENTITY EXTRACTION
-- ============================================================================

-- Extract spellID from a CDM frame's static config data.
-- cooldownInfo.spellID comes from CDM configuration, NOT runtime aura queries.
-- It is never secret because it represents "which spell this slot is configured
-- to track", not "what aura is currently active".
local function GetFrameSpellID(frame)
    -- cooldownID is CDM's canary for pool activity.
    -- Cleared when frame is released back to pool = frame is inactive.
    if not frame.cooldownInfo or not frame.cooldownID then
        return nil
    end

    local cooldownInfo = frame.cooldownInfo

    -- Some spells are passives that link to a different buff spell.
    -- e.g. a passive talent links to the buff it grants.
    -- linkedSpellIDs contains the actual buff spellID in these cases.
    if cooldownInfo.linkedSpellIDs and cooldownInfo.linkedSpellIDs[1] then
        return cooldownInfo.linkedSpellIDs[1]
    end

    return cooldownInfo.spellID
end

-- ============================================================================
-- CDM FRAME HOOKS
-- ============================================================================

-- Called when CDM assigns aura data to a buff frame.
-- This is our primary identity capture point.
local function OnSetAuraInstanceInfo(frame, cdmAuraInstance)
    local spellID = GetFrameSpellID(frame)
    if not spellID then return end

    local auraInstanceID = cdmAuraInstance.auraInstanceID
    if not auraInstanceID then return end

    -- Check if we already have this exact mapping (avoid redundant work)
    local existing = auraIDToSpell[auraInstanceID]
    if existing and existing.spellID == spellID then
        return
    end

    -- If this auraInstanceID previously mapped to a different spell, clean up
    if existing and existing.spellID ~= spellID then
        spellIDToAuraID[existing.spellID] = nil
    end

    -- If this spellID previously mapped to a different auraInstanceID, clean up
    local oldAuraID = spellIDToAuraID[spellID]
    if oldAuraID and oldAuraID ~= auraInstanceID then
        auraIDToSpell[oldAuraID] = nil
    end

    -- Resolve name and texture from static spell data (always non-secret)
    local name, texture
    if SpellAPI then
        name = SpellAPI:GetSpellName(spellID)
        texture = SpellAPI:GetSpellTexture(spellID)
    elseif C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            name = info.name
            texture = C_Spell.GetSpellTexture(spellID)
        end
    end

    -- Store the mapping
    auraIDToSpell[auraInstanceID] = {
        spellID = spellID,
        name = name or ("Spell " .. spellID),
        texture = texture,
    }
    spellIDToAuraID[spellID] = auraInstanceID

    dprint(string.format("Captured: auraID %s → spellID %s (%s)",
        tostring(auraInstanceID), tostring(spellID), tostring(name)))

    -- Notify consumers
    TUICD.Events:Fire("BRIDGE_IDENTITY_UPDATED", spellID, auraInstanceID)
end

-- Hook a single CDM item frame
local function HookFrame(viewer, frame)
    if not frame or hookedFrames[frame] then return end
    if not frame.SetAuraInstanceInfo then return end

    hookedFrames[frame] = true

    hooksecurefunc(frame, "SetAuraInstanceInfo", function(self, cdmAuraInstance)
        local ok, err = pcall(OnSetAuraInstanceInfo, self, cdmAuraInstance)
        if not ok then
            dprint("SetAuraInstanceInfo hook error: " .. tostring(err))
        end
    end)

    dprint("Hooked frame: " .. tostring(frame:GetName() or frame))
end

-- ============================================================================
-- SLOT POSITION MAPPING
-- ============================================================================

-- Rebuild slotToSpellID from current viewer child order.
-- Called after Layout fires, when visual positions are known.
local function RebuildSlotMap()
    wipe(slotToSpellID)
    wipe(spellIDToSlot)

    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then return end

    local children = { viewer:GetChildren() }
    local shown = {}

    for _, child in ipairs(children) do
        if child:IsShown() and child.cooldownInfo then
            local spellID = GetFrameSpellID(child)
            if spellID then
                -- Get position for sort (wrap in pcall for secret anchor safety)
                local top, left = 0, 0
                local ok = pcall(function()
                    top = child:GetTop() or 0
                    left = child:GetLeft() or 0
                end)
                -- Skip if positions are secret
                if ok and not (issecretvalue and (issecretvalue(top) or issecretvalue(left))) then
                    shown[#shown + 1] = { frame = child, spellID = spellID, top = top, left = left }
                end
            end
        end
    end

    -- Sort by visual position (reading order: top-to-bottom, left-to-right)
    local sortOK = pcall(function()
        table.sort(shown, function(a, b)
            if math.abs(a.top - b.top) > 5 then return a.top > b.top end
            return a.left < b.left
        end)
    end)

    if sortOK then
        for i, entry in ipairs(shown) do
            slotToSpellID[i] = entry.spellID
            spellIDToSlot[entry.spellID] = i
        end
    end

    dprint(string.format("Slot map rebuilt: %d entries", #shown))
    for i, spellID in ipairs(slotToSpellID) do
        local info = auraIDToSpell[spellIDToAuraID[spellID] or -1]
        dprint(string.format("  Slot %d → spellID %d (%s)", i, spellID,
            info and info.name or "?"))
    end

    TUICD.Events:Fire("BRIDGE_SLOT_MAP_UPDATED")
end

-- ============================================================================
-- VIEWER HOOK SETUP
-- ============================================================================

local function HookViewer()
    if viewerHooked then return end

    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then return end

    viewerHooked = true

    -- Hook OnAcquireItemFrame to catch new frames as CDM creates them from pool
    if viewer.OnAcquireItemFrame then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(self, frame)
            HookFrame(self, frame)
        end)
        dprint("Hooked OnAcquireItemFrame")
    end

    -- Retroactively hook any existing children
    local children = { viewer:GetChildren() }
    for _, child in ipairs(children) do
        HookFrame(viewer, child)
    end
    dprint(string.format("Retroactively hooked %d existing children", #children))

    -- Hook Layout to rebuild slot position mapping after CDM reorganizes
    if viewer.Layout then
        hooksecurefunc(viewer, "Layout", function(self)
            -- Defer to avoid taint propagation (same pattern as Cooldowns.lua)
            C_Timer.After(0, function()
                if not viewer or not viewer:IsShown() then return end
                -- Only rebuild when we can read positions (not restricted)
                if not InCombatLockdown() then
                    RebuildSlotMap()
                end
            end)
        end)
        dprint("Hooked Layout for slot mapping")
    end

    -- Hook Show for initial/re-show slot mapping
    hooksecurefunc(viewer, "Show", function(self)
        C_Timer.After(0, function()
            if not viewer or not viewer:IsShown() then return end
            if not InCombatLockdown() then
                RebuildSlotMap()
            end
        end)
    end)

    -- Initial slot map if already visible
    if viewer:IsShown() and not InCombatLockdown() then
        C_Timer.After(0, function()
            RebuildSlotMap()
        end)
    end

    dprint("Viewer fully hooked")
end

-- ============================================================================
-- INITIALIZATION & LIFECYCLE
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Fresh zone/login: wipe all mappings and rehook
        Bridge:WipeAll()

        -- Attempt viewer hook (may not exist yet on first login)
        C_Timer.After(0.5, function()
            HookViewer()
        end)
        -- Retry a bit later in case CDM loads slowly
        C_Timer.After(2.0, function()
            if not viewerHooked then
                HookViewer()
            end
            -- Always try a slot map rebuild once things are settled
            if not InCombatLockdown() then
                RebuildSlotMap()
            end
        end)

        initialized = true

    elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        -- Spec change: buffs change entirely, wipe identity mappings
        -- Slot mappings get rebuilt on next Layout
        Bridge:WipeIdentity()
        dprint("Spec changed — identity mappings wiped")

        -- Rebuild slot map after CDM updates (give it time)
        C_Timer.After(1.0, function()
            if not InCombatLockdown() then
                RebuildSlotMap()
            end
        end)

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: rebuild slot map (positions may have been stale)
        C_Timer.After(0.1, function()
            RebuildSlotMap()
        end)
    end
end)

-- ============================================================================
-- PUBLIC API: Core Identity Lookups
-- ============================================================================

-- Get spellID for a given slot position (1-based layout order)
function Bridge:GetSpellIDForSlot(slotIndex)
    return slotToSpellID[slotIndex]
end

-- Get slot position for a spellID (nil if not currently slotted)
function Bridge:GetSlotForSpellID(spellID)
    return spellIDToSlot[spellID]
end

-- Get spellID for an auraInstanceID
function Bridge:GetSpellIDForAuraID(auraInstanceID)
    local entry = auraIDToSpell[auraInstanceID]
    return entry and entry.spellID
end

-- Get current auraInstanceID for a spellID (nil if buff not active)
function Bridge:GetAuraIDForSpellID(spellID)
    return spellIDToAuraID[spellID]
end

-- ============================================================================
-- PUBLIC API: Bulk Data
-- ============================================================================

-- Get a copy of the current slot→spellID mapping
function Bridge:GetSlotToSpellIDMap()
    local copy = {}
    for k, v in pairs(slotToSpellID) do
        copy[k] = v
    end
    return copy
end

-- Get all spellIDs the bridge currently knows about (from CDM hooks)
function Bridge:GetAllKnownSpellIDs()
    local result = {}
    for spellID, _ in pairs(spellIDToAuraID) do
        result[spellID] = true
    end
    -- Also include slot-mapped spellIDs that might not have active auras
    for _, spellID in pairs(slotToSpellID) do
        result[spellID] = true
    end
    return result
end

-- Get total count of slots currently mapped
function Bridge:GetSlotCount()
    local count = 0
    for _ in pairs(slotToSpellID) do count = count + 1 end
    return count
end

-- ============================================================================
-- PUBLIC API: State Queries
-- ============================================================================

-- Check if a buff (by spellID) is currently active
function Bridge:IsBuffActive(spellID)
    local auraID = spellIDToAuraID[spellID]
    if not auraID then return false end

    -- Verify it's still valid using combat-safe filter API
    if C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID then
        -- If it's NOT filtered out by HELPFUL|PLAYER, it's an active player buff
        local filtered = C_UnitAuras.IsAuraFilteredOutByInstanceID(
            "player", auraID, "HELPFUL|PLAYER"
        )
        return not filtered
    end

    -- Fallback: trust the mapping
    return true
end

-- Get full info for a spellID
function Bridge:GetBuffInfo(spellID)
    local auraID = spellIDToAuraID[spellID]
    if not auraID then
        -- No active aura, but we may still have spell metadata
        local name, texture
        if SpellAPI then
            name = SpellAPI:GetSpellName(spellID)
            texture = SpellAPI:GetSpellTexture(spellID)
        end
        if name then
            return {
                spellID = spellID,
                name = name,
                texture = texture,
                auraInstanceID = nil,
                isActive = false,
            }
        end
        return nil
    end

    local entry = auraIDToSpell[auraID]
    return {
        spellID = spellID,
        name = entry and entry.name or ("Spell " .. spellID),
        texture = entry and entry.texture,
        auraInstanceID = auraID,
        isActive = Bridge:IsBuffActive(spellID),
    }
end

-- ============================================================================
-- PUBLIC API: Cache Management
-- ============================================================================

-- Full reset of all mappings
function Bridge:WipeAll()
    wipe(auraIDToSpell)
    wipe(spellIDToAuraID)
    wipe(slotToSpellID)
    wipe(spellIDToSlot)
    dprint("All mappings wiped")
end

-- Wipe identity mappings only (auraID↔spellID), keep slot positions
function Bridge:WipeIdentity()
    wipe(auraIDToSpell)
    wipe(spellIDToAuraID)
    dprint("Identity mappings wiped")
end

-- Wipe slot position mappings only
function Bridge:WipeSlotMappings()
    wipe(slotToSpellID)
    wipe(spellIDToSlot)
    dprint("Slot mappings wiped")
end

-- Force rebuild slot map (callable from outside, e.g. refresh button)
function Bridge:ForceRebuildSlotMap()
    if InCombatLockdown() then
        dprint("Can't rebuild slot map in combat, deferring")
        -- Will rebuild on PLAYER_REGEN_ENABLED
        return
    end
    RebuildSlotMap()
end

-- ============================================================================
-- PUBLIC API: Debug & Diagnostics
-- ============================================================================

function Bridge:ToggleDebug()
    debugMode = not debugMode
    TUICD:Print("BuffIdentityBridge debug: " .. (debugMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

function Bridge:IsInitialized()
    return initialized
end

function Bridge:IsViewerHooked()
    return viewerHooked
end

function Bridge:GetHookedFrameCount()
    local count = 0
    for _ in pairs(hookedFrames) do count = count + 1 end
    return count
end

function Bridge:DumpStatus()
    print("|cff88ccff=== BuffIdentityBridge Status ===|r")
    print("Initialized: " .. tostring(initialized))
    print("Viewer hooked: " .. tostring(viewerHooked))
    print("Hooked frames: " .. Bridge:GetHookedFrameCount())
    print("Identity mappings (auraID→spell): " .. (function()
        local c = 0; for _ in pairs(auraIDToSpell) do c = c + 1 end; return c
    end)())
    print("Active spells (spell→auraID): " .. (function()
        local c = 0; for _ in pairs(spellIDToAuraID) do c = c + 1 end; return c
    end)())
    print("Slot mappings: " .. Bridge:GetSlotCount())

    local viewer = _G["BuffIconCooldownViewer"]
    print("Viewer exists: " .. tostring(viewer ~= nil))
    if viewer then
        print("Viewer shown: " .. tostring(viewer:IsShown()))
        print("Viewer children: " .. tostring(select('#', viewer:GetChildren())))
    end

    -- Check restriction state
    if TUICD.RestrictionAPI then
        print("Auras secret: " .. tostring(TUICD.RestrictionAPI:AreAurasSecret()))
    end
end

function Bridge:DumpMappings()
    print("|cff88ccff=== Slot → SpellID Mappings ===|r")
    if next(slotToSpellID) then
        local maxSlot = 0
        for k in pairs(slotToSpellID) do
            if k > maxSlot then maxSlot = k end
        end
        for i = 1, maxSlot do
            local spellID = slotToSpellID[i]
            if spellID then
                local auraID = spellIDToAuraID[spellID]
                local entry = auraID and auraIDToSpell[auraID]
                local name = entry and entry.name or (SpellAPI and SpellAPI:GetSpellName(spellID)) or "?"
                local active = Bridge:IsBuffActive(spellID)
                print(string.format("  Slot %d → |cffffd100%d|r %s %s(auraID: %s)",
                    i, spellID, name,
                    active and "|cff00ff00ACTIVE|r " or "|cff888888inactive|r ",
                    tostring(auraID or "none")))
            end
        end
    else
        print("  (no slot mappings — viewer may not be visible)")
    end

    print("|cff88ccff=== Identity Mappings (auraID → Spell) ===|r")
    local count = 0
    for auraID, entry in pairs(auraIDToSpell) do
        count = count + 1
        print(string.format("  auraID %s → spellID %d (%s)",
            tostring(auraID), entry.spellID, entry.name))
    end
    if count == 0 then
        print("  (no identity mappings — no SetAuraInstanceInfo hooks have fired)")
    end
end

-- ============================================================================
-- SLASH COMMAND INTEGRATION
-- ============================================================================

-- Called from Main.lua slash command handler
function Bridge:HandleSlashCommand(args)
    if not args or args == "" then
        -- Show help
        TUICD:Print("BuffIdentityBridge commands:")
        TUICD:Print("  /tuicd bridge dump    — Show all mappings")
        TUICD:Print("  /tuicd bridge status  — Show bridge status")
        TUICD:Print("  /tuicd bridge reset   — Wipe all caches")
        TUICD:Print("  /tuicd bridge rebuild — Force slot map rebuild")
        TUICD:Print("  /tuicd bridge debug   — Toggle debug output")
        return
    end

    local subcmd = strsplit(" ", args, 2)
    subcmd = subcmd and subcmd:lower() or ""

    if subcmd == "dump" or subcmd == "mappings" then
        Bridge:DumpMappings()
    elseif subcmd == "status" then
        Bridge:DumpStatus()
    elseif subcmd == "reset" then
        Bridge:WipeAll()
        TUICD:Print("BuffIdentityBridge: All mappings reset")
        -- Trigger rebuild
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                RebuildSlotMap()
            end
        end)
    elseif subcmd == "debug" then
        Bridge:ToggleDebug()
    elseif subcmd == "rebuild" then
        Bridge:ForceRebuildSlotMap()
        TUICD:Print("BuffIdentityBridge: Slot map rebuild requested")
    else
        TUICD:Print("Unknown bridge command: " .. subcmd)
        TUICD:Print("Type /tuicd bridge for help")
    end
end
