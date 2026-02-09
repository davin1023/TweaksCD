-- ============================================================================
-- TUICD: Personal Resources Module
-- Power bars, class resources (combo points, holy power, etc.), and player auras
-- ============================================================================

local ADDON_NAME, TUICD = ...

local PersonalResources = TUICD.ModuleManager:NewModule(
    TUICD.MODULE_IDS.PERSONAL_RESOURCES,
    "Personal Resources",
    "Customizable power bars, class resources, and player buff/debuff displays"
)

-- ============================================================================
-- MIDNIGHT API WRAPPERS (v2.0.0)
-- ============================================================================

local SpellAPI = TUICD.SpellAPI
local AuraAPI = TUICD.AuraAPI
local UnitAPI = TUICD.UnitAPI
local StatusBarAPI = TUICD.StatusBarAPI

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local HUB_WIDTH, HUB_HEIGHT = 200, 600
local PANEL_WIDTH, PANEL_HEIGHT = 420, 560
local BUTTON_HEIGHT, BUTTON_SPACING = 28, 6

local darkBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

local SPECIAL_RESOURCES = { 
    STAGGER = "STAGGER", 
    SOUL_FRAGMENTS = "SOUL_FRAGMENTS",
    MAELSTROM_WEAPON = "MAELSTROM_WEAPON",  -- Enhancement Shaman aura-based resource
    VOID_METAMORPHOSIS = "VOID_METAMORPHOSIS",  -- Devourer DH (hero spec 3) continuous resource
}

-- Aura-based resources tracked by spell ID
-- These are secondary resources that use aura stacks instead of power bars
local AURA_TRACKED_RESOURCES = {
    -- Enhancement Shaman: Maelstrom Weapon (max 10 stacks)
    [SPECIAL_RESOURCES.MAELSTROM_WEAPON] = {
        spellID = 344179,
        maxStacks = 10,
        class = "SHAMAN",
        specID = 263,  -- Enhancement
        name = "Maelstrom Weapon",
    },
}

-- Midnight non-secret aura spell IDs (confirmed in API changes)
-- These can be tracked without secret value restrictions
local MIDNIGHT_NON_SECRET_AURAS = {
    [344179] = true,   -- Maelstrom Weapon
    [1217607] = true,  -- Void Metamorphosis (Devourer DH)
    [1225789] = true,  -- Void Metamorphosis resource aura
    [1227702] = true,  -- Collapsing Star (Devourer DH)
}

-- Smooth bar interpolation (Midnight native)
local BAR_INTERPOLATION = Enum.StatusBarInterpolation.ExponentialEaseOut

-- In Midnight Beta 3+, secondary resources are no longer secret:
-- Combo Points, Runes, Soul Shards, Holy Power, Chi, Arcane Charges, Essence
-- UnitStagger is also non-secret for player now
local MIDNIGHT_NON_SECRET_RESOURCES = {
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Runes] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Essence] = true,
}

-- Forward declarations for layout registration functions
local RegisterAllPersonalResourcesWithLayout
local RegisterResourceBarWithLayout

-- Helper to set status bar value with optional smooth animation
local function SetBarValueSmooth(bar, value, useSmooth)
    if not bar then return end
    if useSmooth and BAR_INTERPOLATION then
        bar:SetValue(value, BAR_INTERPOLATION)
    else
        bar:SetValue(value)
    end
end

-- Check if a resource type returns non-secret values (either pre-Midnight special handling or Midnight relaxed)
local function IsNonSecretResource(resourceType)
    -- Always non-secret special resources
    if resourceType == SPECIAL_RESOURCES.STAGGER then return true end
    if resourceType == SPECIAL_RESOURCES.SOUL_FRAGMENTS then return true end
    if resourceType == SPECIAL_RESOURCES.MAELSTROM_WEAPON then return true end
    if resourceType == SPECIAL_RESOURCES.VOID_METAMORPHOSIS then return true end
    if resourceType == Enum.PowerType.Runes then return true end
    
    -- Secondary resources (Combo Points, Holy Power, Chi, Soul Shards, Arcane Charges, Essence)
    -- These are non-secret in Midnight
    if MIDNIGHT_NON_SECRET_RESOURCES[resourceType] then
        return true
    end
    
    return false
end

local PRIMARY_RESOURCES = {
    DEATHKNIGHT = Enum.PowerType.RunicPower,
    DEMONHUNTER = Enum.PowerType.Fury,
    DRUID = { default = Enum.PowerType.Mana, forms = { [1] = Enum.PowerType.Energy, [5] = Enum.PowerType.Rage, [31] = Enum.PowerType.LunarPower } },
    EVOKER = Enum.PowerType.Mana, HUNTER = Enum.PowerType.Focus, MAGE = Enum.PowerType.Mana,
    MONK = { [268] = Enum.PowerType.Energy, [269] = Enum.PowerType.Energy, [270] = Enum.PowerType.Mana },
    PALADIN = Enum.PowerType.Mana,
    PRIEST = { [256] = Enum.PowerType.Mana, [257] = Enum.PowerType.Mana, [258] = Enum.PowerType.Insanity },
    ROGUE = Enum.PowerType.Energy,
    SHAMAN = { [262] = Enum.PowerType.Maelstrom, [263] = Enum.PowerType.Mana, [264] = Enum.PowerType.Mana },
    WARLOCK = Enum.PowerType.Mana, WARRIOR = Enum.PowerType.Rage,
}

local SECONDARY_RESOURCES = {
    DEATHKNIGHT = Enum.PowerType.Runes,
    -- Demon Hunter secondary resources:
    -- Havoc (577/1): No secondary resource (Fury is primary)
    -- Vengeance (581/2): Soul Fragments (discrete, max 5)
    -- Devourer (hero spec 3): Void Metamorphosis (continuous bar, max 50)
    DEMONHUNTER = { 
        default = nil,  -- No default - each spec is different
        [577] = nil,                              -- Havoc: no secondary resource
        [581] = SPECIAL_RESOURCES.SOUL_FRAGMENTS, -- Vengeance: Soul Fragments
        [1] = nil,                                -- Havoc (spec index fallback)
        [2] = SPECIAL_RESOURCES.SOUL_FRAGMENTS,   -- Vengeance (spec index fallback)
        [3] = SPECIAL_RESOURCES.VOID_METAMORPHOSIS, -- Devourer (hero spec index)
    },
    DRUID = { forms = { [1] = Enum.PowerType.ComboPoints } },
    EVOKER = Enum.PowerType.Essence,
    MAGE = { [62] = Enum.PowerType.ArcaneCharges },
    -- Monk: specID 268=Brewmaster(Stagger), 269=Windwalker(Chi), 270=Mistweaver(none)
    -- Also include specIndex fallbacks: 1=Brewmaster, 3=Windwalker
    MONK = { [268] = SPECIAL_RESOURCES.STAGGER, [269] = Enum.PowerType.Chi, [1] = SPECIAL_RESOURCES.STAGGER, [3] = Enum.PowerType.Chi },
    PALADIN = Enum.PowerType.HolyPower,
    ROGUE = Enum.PowerType.ComboPoints,
    -- Enhancement Shaman (263) uses Maelstrom Weapon (aura-based stacking resource)
    -- Elemental (262) uses Maelstrom as primary power, Restoration (264) has no secondary
    -- Also include specIndex fallback: 2=Enhancement
    SHAMAN = { [263] = SPECIAL_RESOURCES.MAELSTROM_WEAPON, [2] = SPECIAL_RESOURCES.MAELSTROM_WEAPON },
    WARLOCK = Enum.PowerType.SoulShards,
}

local RESOURCE_COLORS = {
    [Enum.PowerType.Mana] = { r = 0, g = 0, b = 1 },
    [Enum.PowerType.Rage] = { r = 1, g = 0, b = 0 },
    [Enum.PowerType.Focus] = { r = 1, g = 0.5, b = 0.25 },
    [Enum.PowerType.Energy] = { r = 1, g = 1, b = 0 },
    [Enum.PowerType.ComboPoints] = { r = 1, g = 0.96, b = 0.41 },
    [Enum.PowerType.Runes] = { r = 0.5, g = 0.5, b = 0.5 },
    [Enum.PowerType.RunicPower] = { r = 0, g = 0.82, b = 1 },
    [Enum.PowerType.SoulShards] = { r = 0.58, g = 0.51, b = 0.79 },
    [Enum.PowerType.LunarPower] = { r = 0.3, g = 0.52, b = 0.9 },
    [Enum.PowerType.HolyPower] = { r = 0.95, g = 0.9, b = 0.6 },
    [Enum.PowerType.Maelstrom] = { r = 0, g = 0.5, b = 1 },
    [Enum.PowerType.Chi] = { r = 0.71, g = 1, b = 0.92 },
    [Enum.PowerType.Insanity] = { r = 0.4, g = 0, b = 0.8 },
    [Enum.PowerType.ArcaneCharges] = { r = 0.1, g = 0.1, b = 0.98 },
    [Enum.PowerType.Fury] = { r = 0.79, g = 0.26, b = 0.99 },
    [Enum.PowerType.Essence] = { r = 0.2, g = 0.58, b = 0.5 },
    [SPECIAL_RESOURCES.STAGGER] = { r = 0.52, g = 1, b = 0.52 },
    [SPECIAL_RESOURCES.SOUL_FRAGMENTS] = { r = 0.64, g = 0.19, b = 0.79 },
    [SPECIAL_RESOURCES.VOID_METAMORPHOSIS] = { r = 0.5, g = 0.0, b = 0.8 },  -- Deep purple for Void
    [SPECIAL_RESOURCES.MAELSTROM_WEAPON] = { r = 0.0, g = 0.5, b = 1.0 },  -- Blue like Maelstrom power
}

-- Gradient presets for per-point colors (10 points max for Maelstrom Weapon)
local GRADIENT_PRESETS = {
    {
        id = "green_to_red",
        name = "Green → Red",
        colors = {
            { 0.3, 1, 0.3, 1 },    -- 1: Light green
            { 0.5, 1, 0.3, 1 },    -- 2: Yellow-green
            { 0.7, 1, 0.2, 1 },    -- 3: Lime
            { 0.9, 0.9, 0.1, 1 },  -- 4: Yellow
            { 1, 0.7, 0, 1 },      -- 5: Gold
            { 1, 0.5, 0, 1 },      -- 6: Orange
            { 1, 0.3, 0, 1 },      -- 7: Dark orange
            { 1, 0.15, 0, 1 },     -- 8: Red-orange
            { 1, 0, 0, 1 },        -- 9: Red
            { 0.8, 0, 0.2, 1 },    -- 10: Deep red
        }
    },
    {
        id = "blue_to_purple",
        name = "Blue → Purple",
        colors = {
            { 0.3, 0.5, 1, 1 },    -- 1: Light blue
            { 0.35, 0.45, 1, 1 },  -- 2
            { 0.4, 0.4, 1, 1 },    -- 3
            { 0.5, 0.35, 1, 1 },   -- 4
            { 0.6, 0.3, 1, 1 },    -- 5: Blue-purple
            { 0.7, 0.25, 1, 1 },   -- 6
            { 0.75, 0.2, 0.95, 1 }, -- 7
            { 0.8, 0.15, 0.9, 1 }, -- 8
            { 0.85, 0.1, 0.85, 1 }, -- 9
            { 0.9, 0.05, 0.8, 1 }, -- 10: Deep purple
        }
    },
    {
        id = "light_blue_to_dark_blue",
        name = "Light Blue → Dark Blue",
        colors = {
            { 0.6, 0.85, 1, 1 },   -- 1: Very light blue
            { 0.5, 0.8, 1, 1 },    -- 2
            { 0.4, 0.75, 1, 1 },   -- 3
            { 0.3, 0.7, 1, 1 },    -- 4
            { 0.2, 0.6, 1, 1 },    -- 5: Medium blue
            { 0.15, 0.5, 0.95, 1 }, -- 6
            { 0.1, 0.4, 0.9, 1 },  -- 7
            { 0.08, 0.3, 0.85, 1 }, -- 8
            { 0.05, 0.2, 0.8, 1 }, -- 9
            { 0.02, 0.1, 0.7, 1 }, -- 10: Deep blue
        }
    },
    {
        id = "cyan_to_blue",
        name = "Cyan → Blue",
        colors = {
            { 0.2, 1, 1, 1 },      -- 1: Bright cyan
            { 0.18, 0.95, 1, 1 },  -- 2
            { 0.15, 0.85, 1, 1 },  -- 3
            { 0.12, 0.75, 1, 1 },  -- 4
            { 0.1, 0.65, 1, 1 },   -- 5
            { 0.08, 0.55, 1, 1 },  -- 6
            { 0.05, 0.45, 1, 1 },  -- 7
            { 0.03, 0.35, 1, 1 },  -- 8
            { 0.02, 0.25, 1, 1 },  -- 9
            { 0, 0.15, 1, 1 },     -- 10: Deep blue
        }
    },
    {
        id = "gold_to_white",
        name = "Gold → White",
        colors = {
            { 1, 0.75, 0, 1 },     -- 1: Gold
            { 1, 0.8, 0.15, 1 },   -- 2
            { 1, 0.85, 0.3, 1 },   -- 3
            { 1, 0.88, 0.45, 1 },  -- 4
            { 1, 0.9, 0.55, 1 },   -- 5
            { 1, 0.92, 0.65, 1 },  -- 6
            { 1, 0.94, 0.75, 1 },  -- 7
            { 1, 0.96, 0.85, 1 },  -- 8
            { 1, 0.98, 0.92, 1 },  -- 9
            { 1, 1, 1, 1 },        -- 10: White
        }
    },
    {
        id = "purple_to_pink",
        name = "Purple → Pink",
        colors = {
            { 0.5, 0.1, 0.8, 1 },  -- 1: Deep purple
            { 0.55, 0.15, 0.8, 1 }, -- 2
            { 0.6, 0.2, 0.8, 1 },  -- 3
            { 0.7, 0.25, 0.8, 1 }, -- 4
            { 0.8, 0.3, 0.8, 1 },  -- 5: Magenta
            { 0.85, 0.35, 0.75, 1 }, -- 6
            { 0.9, 0.4, 0.7, 1 },  -- 7
            { 0.95, 0.5, 0.65, 1 }, -- 8
            { 1, 0.6, 0.7, 1 },    -- 9
            { 1, 0.7, 0.8, 1 },    -- 10: Pink
        }
    },
    {
        id = "teal_to_green",
        name = "Teal → Green",
        colors = {
            { 0.2, 0.7, 0.7, 1 },  -- 1: Teal
            { 0.22, 0.75, 0.65, 1 }, -- 2
            { 0.25, 0.8, 0.6, 1 }, -- 3
            { 0.28, 0.85, 0.55, 1 }, -- 4
            { 0.3, 0.9, 0.5, 1 },  -- 5
            { 0.32, 0.92, 0.45, 1 }, -- 6
            { 0.35, 0.95, 0.4, 1 }, -- 7
            { 0.38, 0.97, 0.35, 1 }, -- 8
            { 0.4, 1, 0.3, 1 },    -- 9
            { 0.3, 1, 0.3, 1 },    -- 10: Bright green
        }
    },
    {
        id = "fire",
        name = "Fire (Red → Yellow)",
        colors = {
            { 0.7, 0, 0, 1 },      -- 1: Dark red
            { 0.85, 0.1, 0, 1 },   -- 2
            { 1, 0.2, 0, 1 },      -- 3: Red
            { 1, 0.35, 0, 1 },     -- 4
            { 1, 0.5, 0, 1 },      -- 5: Orange
            { 1, 0.6, 0, 1 },      -- 6
            { 1, 0.7, 0, 1 },      -- 7: Gold
            { 1, 0.8, 0.1, 1 },    -- 8
            { 1, 0.9, 0.2, 1 },    -- 9
            { 1, 1, 0.4, 1 },      -- 10: Bright yellow
        }
    },
    {
        id = "frost",
        name = "Frost (White → Blue)",
        colors = {
            { 1, 1, 1, 1 },        -- 1: White
            { 0.9, 0.95, 1, 1 },   -- 2
            { 0.8, 0.9, 1, 1 },    -- 3
            { 0.7, 0.85, 1, 1 },   -- 4
            { 0.6, 0.8, 1, 1 },    -- 5: Light blue
            { 0.5, 0.7, 1, 1 },    -- 6
            { 0.4, 0.6, 1, 1 },    -- 7
            { 0.3, 0.5, 1, 1 },    -- 8
            { 0.2, 0.4, 1, 1 },    -- 9
            { 0.1, 0.3, 0.9, 1 },  -- 10: Deep frost blue
        }
    },
    {
        id = "nature",
        name = "Nature (Brown → Green)",
        colors = {
            { 0.5, 0.35, 0.2, 1 }, -- 1: Brown
            { 0.5, 0.4, 0.2, 1 },  -- 2
            { 0.5, 0.5, 0.2, 1 },  -- 3
            { 0.5, 0.6, 0.2, 1 },  -- 4
            { 0.45, 0.7, 0.25, 1 }, -- 5: Olive
            { 0.4, 0.8, 0.3, 1 },  -- 6
            { 0.35, 0.85, 0.3, 1 }, -- 7
            { 0.3, 0.9, 0.3, 1 },  -- 8
            { 0.25, 0.95, 0.3, 1 }, -- 9
            { 0.2, 1, 0.3, 1 },    -- 10: Bright green
        }
    },
    {
        id = "rainbow",
        name = "Rainbow",
        colors = {
            { 1, 0, 0, 1 },        -- 1: Red
            { 1, 0.5, 0, 1 },      -- 2: Orange
            { 1, 1, 0, 1 },        -- 3: Yellow
            { 0.5, 1, 0, 1 },      -- 4: Lime
            { 0, 1, 0, 1 },        -- 5: Green
            { 0, 1, 0.5, 1 },      -- 6: Cyan-green
            { 0, 1, 1, 1 },        -- 7: Cyan
            { 0, 0.5, 1, 1 },      -- 8: Light blue
            { 0.5, 0, 1, 1 },      -- 9: Purple
            { 1, 0, 1, 1 },        -- 10: Magenta
        }
    },
}

-- Helper function to get current character's max secondary resource points
local function GetCurrentMaxResourcePoints()
    -- Ensure player info is initialized
    if not playerClass then 
        local _, class = UnitClass("player")
        playerClass = class
        local specIndex = GetSpecialization()
        playerSpecIndex = specIndex
        if specIndex then playerSpecID = GetSpecializationInfo(specIndex) end
    end
    if not playerClass then return 5 end  -- Default to 5 if still not initialized
    
    -- Get the resource type for this class/spec
    local data = SECONDARY_RESOURCES[playerClass]
    if not data then return 5 end
    
    local resourceType
    if type(data) == "table" and data.forms then
        local formID = GetShapeshiftFormID()
        resourceType = formID and data.forms[formID] or data.default
    elseif type(data) == "table" then
        resourceType = playerSpecID and data[playerSpecID]
        if not resourceType and playerSpecIndex then
            resourceType = data[playerSpecIndex]
        end
        resourceType = resourceType or data.default
    else
        resourceType = data
    end
    
    if not resourceType then return 5 end
    
    -- Special resources with known max values
    if resourceType == SPECIAL_RESOURCES.MAELSTROM_WEAPON then
        return 10  -- Maelstrom Weapon has 10 stacks
    elseif resourceType == SPECIAL_RESOURCES.SOUL_FRAGMENTS then
        return 6   -- Soul Fragments max is 6 (Vengeance DH)
    elseif resourceType == SPECIAL_RESOURCES.VOID_METAMORPHOSIS then
        return 50  -- Void Metamorphosis max is 50
    elseif resourceType == SPECIAL_RESOURCES.STAGGER then
        return 0   -- Stagger is continuous, not discrete
    elseif resourceType == Enum.PowerType.Runes then
        return 6   -- Death Knight runes
    end
    
    -- Query from UnitPowerMax for standard resources
    local max = UnitPowerMax("player", resourceType)
    if max and max > 0 then
        return max
    end
    
    -- Fallback defaults by resource type
    local defaults = {
        [Enum.PowerType.ComboPoints] = 7,  -- Max possible with talents
        [Enum.PowerType.HolyPower] = 5,
        [Enum.PowerType.Chi] = 6,          -- Max possible with talents
        [Enum.PowerType.SoulShards] = 5,
        [Enum.PowerType.ArcaneCharges] = 4,
        [Enum.PowerType.Essence] = 6,      -- Max possible
    }
    return defaults[resourceType] or 5
end

-- Helper function to apply a gradient preset to perPointColors
local function ApplyGradientPreset(cfg, presetId)
    for _, preset in ipairs(GRADIENT_PRESETS) do
        if preset.id == presetId then
            cfg.gradientPreset = presetId
            for i = 1, 10 do
                if preset.colors[i] then
                    -- Update values IN the existing table (don't replace the table)
                    -- This preserves references held by color picker buttons
                    if not cfg.perPointColors[i] then
                        cfg.perPointColors[i] = {}
                    end
                    cfg.perPointColors[i][1] = preset.colors[i][1]
                    cfg.perPointColors[i][2] = preset.colors[i][2]
                    cfg.perPointColors[i][3] = preset.colors[i][3]
                    cfg.perPointColors[i][4] = preset.colors[i][4]
                end
            end
            return true
        end
    end
    return false
end

local TEXT_FORMATS = {
    { id = "none", name = "Hidden" }, { id = "current", name = "Current" }, { id = "current_max", name = "Current / Max" }, { id = "percent", name = "Percent" },
}

local DEFAULT_SETTINGS = {
    enabled = false,
    healthBar = {
        enabled = true, width = 200, height = 20,  -- Enable by default when module is enabled
        texture = "Blizzard",
        font = "Friz Quadrata TT",
        positionX = 0, positionY = -180, anchor = "CENTER",
        showBorder = true, borderColor = { 0, 0, 0, 1 }, borderSize = 1,
        backgroundColor = { 0.1, 0.1, 0.1, 0.8 },
        useClassColor = true, useHealthGradient = false, customColor = { 0, 0.8, 0, 1 },
        showText = true, textFormat = "current_max", textFontSize = 11, textFontOutline = "OUTLINE",
        textColor = { 1, 1, 1, 1 },
        textPosition = "CENTER",  -- "LEFT", "CENTER", "RIGHT"
        textOffsetX = 0,
        textOffsetY = 0,
        abbreviateNumbers = true,
        -- Absorb overlay
        showAbsorb = false,
        absorbColor = { 0.8, 0.8, 0.2, 0.7 },  -- Yellow with transparency
        absorbShowText = false,
        absorbTextFormat = "current",  -- "current", "percent"
        absorbTextFontSize = 10,
        absorbTextPosition = "RIGHT",  -- "LEFT", "CENTER", "RIGHT"
        absorbTextOffsetX = 0,
        absorbTextOffsetY = 0,
        absorbTextColor = { 1, 1, 1, 1 },
        -- Masking
        maskShape = "none",
        -- Visibility (OR logic)
        visibilityEnabled = false,
        showInCombat = true, showOutOfCombat = true,
        showHasTarget = true, showNoTarget = true,
        showSolo = true, showInParty = true, showInRaid = true, showInInstance = true,
        -- Fade
        fadeEnabled = false, fadeDelay = 3.0, fadeAlpha = 0.3,
    },
    powerBar = {
        enabled = true, width = 200, height = 16,  -- Enable by default when module is enabled
        texture = "Blizzard",
        font = "Friz Quadrata TT",
        positionX = 0, positionY = -200, anchor = "CENTER",
        showBorder = true, borderColor = { 0, 0, 0, 1 }, borderSize = 1,
        backgroundColor = { 0.1, 0.1, 0.1, 0.8 },
        useClassColor = false, useResourceColor = true, customColor = { 0, 0.8, 0, 1 },
        showText = true, textFormat = "current", textFontSize = 11, textFontOutline = "OUTLINE",
        textColor = { 1, 1, 1, 1 },
        -- Masking
        maskShape = "none",
        -- Visibility (OR logic)
        visibilityEnabled = false,
        showInCombat = true, showOutOfCombat = true,
        showHasTarget = true, showNoTarget = true,
        showSolo = true, showInParty = true, showInRaid = true, showInInstance = true,
        -- Fade
        fadeEnabled = false, fadeDelay = 3.0, fadeAlpha = 0.3,
    },
    classPower = {
        enabled = true, width = 200, height = 12, spacing = 3,  -- Enable by default when module is enabled
        positionX = 0, positionY = -220, anchor = "CENTER",
        showBorder = true, borderColor = { 0, 0, 0, 1 }, borderSize = 1,
        backgroundColor = { 0.15, 0.15, 0.15, 0.8 }, inactiveColor = { 0.2, 0.2, 0.2, 0.6 },
        useClassColor = false, useResourceColor = true, customColor = { 1, 0.8, 0, 1 },
        usePerPointColors = false,
        gradientPreset = "green_to_red",  -- Default gradient preset
        perPointColors = {
            { 0.3, 1, 0.3, 1 },    -- 1: Light green
            { 0.5, 1, 0.3, 1 },    -- 2: Yellow-green
            { 0.7, 1, 0.2, 1 },    -- 3: Lime
            { 0.9, 0.9, 0.1, 1 },  -- 4: Yellow
            { 1, 0.7, 0, 1 },      -- 5: Gold
            { 1, 0.5, 0, 1 },      -- 6: Orange
            { 1, 0.3, 0, 1 },      -- 7: Dark orange
            { 1, 0.15, 0, 1 },     -- 8: Red-orange
            { 1, 0, 0, 1 },        -- 9: Red
            { 0.8, 0, 0.2, 1 },    -- 10: Deep red
        },
        showText = false, textFormat = "current", textFontSize = 12, textFontOutline = "OUTLINE",
        textFont = "Friz Quadrata TT", textOffsetX = 0, textOffsetY = 0,
        textColor = { 1, 1, 1, 1 },
        -- Soul Fragments gradient overlay style (Vengeance DH)
        -- "none" = solid color, "green" = dark to light green, "purple" = DH fury purple to white
        soulFragmentsGradient = "purple",
        -- Masking
        maskShape = "none",
        -- Visibility (OR logic)
        visibilityEnabled = false,
        showInCombat = true, showOutOfCombat = true,
        showHasTarget = true, showNoTarget = true,
        showSolo = true, showInParty = true, showInRaid = true, showInInstance = true,
        -- Fade
        fadeEnabled = false, fadeDelay = 3.0, fadeAlpha = 0.3,
    },
    runes = { showCooldownText = true, cooldownFontSize = 10, cooldownFontOutline = "OUTLINE", sortByRecharge = true },
    soulFragments = {
        enabled = false,  -- Default to disabled for new installs (Vengeance DH feature)
        style = "fel",  -- "flame", "fel", or "void"
        scale = 0.25,   -- Default to 64x64 (256 * 0.25)
        positionX = 0, positionY = -220, anchor = "CENTER",
        countFontSize = 28,
        countFontOutline = "OUTLINE",
        countColor = { 1, 1, 1, 1 },
        countOffsetY = 0,  -- Vertical offset for fine-tuning position
        showLabel = true,
        labelFontSize = 10,
        labelFontOutline = "OUTLINE",
        labelColor = { 0.7, 0.5, 0.8, 0.8 },
        -- Visibility (OR logic)
        visibilityEnabled = false,
        showInCombat = true, showOutOfCombat = true,
        showHasTarget = true, showNoTarget = true,
        showSolo = true, showInParty = true, showInRaid = true, showInInstance = true,
        -- Fade
        fadeEnabled = false, fadeDelay = 3.0, fadeAlpha = 0.3,
    },
    global = { scale = 1.0, hideBlizzardBars = true },
    stagger = {
        -- Stagger-specific color options (display uses classPower position/size)
        useDynamicColor = true,  -- Color changes based on stagger level
        lightColor = { 0.52, 1, 0.52, 1 },      -- Green: <30%
        moderateColor = { 1, 0.85, 0.35, 1 },   -- Yellow: 30-60%
        heavyColor = { 1, 0.35, 0.35, 1 },      -- Red: >60%
        customColor = { 0.52, 1, 0.52, 1 },     -- Used when useDynamicColor is false
        -- Stagger-specific text options
        textFormat = "percent",  -- "amount", "percent", "both" - default to percent
    },
    -- Player Buffs Display
    buffs = {
        enabled = false,
        -- Position (independent frame)
        positionX = 0, positionY = -260, anchor = "CENTER",
        
        -- Layout mode: "standard" or "custom"
        layoutMode = "standard",
        
        -- Standard layout options
        size = 28,
        spacing = 3,
        maxAuras = 16,
        wrapAfter = 8,
        growDirection = "RIGHT",  -- RIGHT, LEFT, UP, DOWN
        wrapDirection = "DOWN",   -- DOWN, UP, LEFT, RIGHT
        horizontalAlign = "CENTER",  -- LEFT, CENTER, RIGHT
        verticalAlign = "TOP",       -- TOP, MIDDLE, BOTTOM
        
        -- Custom (CMT-style) layout options
        rowPattern = "4,4,4,4",  -- Comma-separated numbers
        alignment = "CENTER",  -- LEFT, CENTER, RIGHT
        scale = 1.0,
        zoom = 1.0,  -- Icon texture zoom (crop edges)
        compactMode = false,
        compactOffset = -4,
        hSpacing = 3,
        vSpacing = 3,
        reverseOrder = false,
        
        -- Sorting (Midnight Beta 4+)
        sortBy = "default",  -- "default", "duration", "name"
        sortDirection = "normal",  -- "normal", "reverse"
        
        -- Icon display
        showDuration = true,
        showDurationText = true,
        durationFontSize = 10,
        durationPosition = "CENTER",
        showStacks = true,
        stackFontSize = 10,
        stackPosition = "BOTTOMRIGHT",
        showBorder = true,
        borderColor = { 0, 0, 0, 1 },
        
        -- Filtering
        hidePermanent = false,  -- Hide buffs with no duration
        showOnlyMyBuffs = false,  -- Only show buffs cast by the player
        
        -- Visibility (OR logic)
        visibilityEnabled = false,
        showInCombat = true, showOutOfCombat = true,
        showHasTarget = true, showNoTarget = true,
        showSolo = true, showInParty = true, showInRaid = true, showInInstance = true,
        
        -- Fade
        fadeEnabled = false, fadeDelay = 3.0, fadeAlpha = 0.3,
    },
    -- Player Debuffs Display
    debuffs = {
        enabled = false,
        -- Position (independent frame)
        positionX = 0, positionY = -310, anchor = "CENTER",
        
        -- Layout mode: "standard" or "custom"
        layoutMode = "standard",
        
        -- Standard layout options
        size = 28,
        spacing = 3,
        maxAuras = 16,
        wrapAfter = 8,
        growDirection = "RIGHT",
        wrapDirection = "DOWN",
        horizontalAlign = "CENTER",  -- LEFT, CENTER, RIGHT
        verticalAlign = "TOP",       -- TOP, MIDDLE, BOTTOM
        
        -- Custom (CMT-style) layout options
        rowPattern = "4,4,4,4",
        alignment = "CENTER",
        scale = 1.0,
        zoom = 1.0,
        compactMode = false,
        compactOffset = -4,
        hSpacing = 3,
        vSpacing = 3,
        reverseOrder = false,
        
        -- Sorting (Midnight Beta 4+)
        sortBy = "default",  -- "default", "duration", "name"
        sortDirection = "normal",  -- "normal", "reverse"
        
        -- Icon display
        showDuration = true,
        showDurationText = true,
        durationFontSize = 10,
        durationPosition = "CENTER",
        showStacks = true,
        stackFontSize = 10,
        stackPosition = "BOTTOMRIGHT",
        showBorder = true,
        borderColor = { 0, 0, 0, 1 },
        
        -- Debuff-specific
        colorByDispelType = true,
        dispelBorderOnly = true,  -- Only color border, not whole icon
        
        -- Filtering
        hidePermanent = false,
        showOnlyMyDebuffs = false,  -- Only show debuffs cast by the player
        
        -- Visibility (OR logic)
        visibilityEnabled = false,
        showInCombat = true, showOutOfCombat = true,
        showHasTarget = true, showNoTarget = true,
        showSolo = true, showInParty = true, showInRaid = true, showInInstance = true,
        
        -- Fade
        fadeEnabled = false, fadeDelay = 3.0, fadeAlpha = 0.3,
    },
}

local settings, personalResourcesHub, settingsPanels, currentOpenPanel = nil, nil, {}, nil
local healthBarFrame, powerBarFrame, classPowerFrame, classPowerSegments = nil, nil, nil, {}
local soulFragmentFrame = nil
local buffsFrame, debuffsFrame = nil, nil  -- Player aura frames
local buffsIcons, debuffsIcons = {}, {}    -- Icon pools for auras
local secretValueDecoder, eventFrame = nil, nil
local playerClass, playerSpecIndex, playerSpecID = nil, nil, nil
local cachedMaxPrimary, cachedMaxSecondary = 100, 5
local runeUpdateTicker, soulFragmentTicker = nil, nil
local visibilityState = { health = { visible = true, lastActivity = 0 }, power = { visible = true, lastActivity = 0 }, class = { visible = true, lastActivity = 0 }, soul = { visible = true, lastActivity = 0 }, stagger = { visible = true, lastActivity = 0 }, buffs = { visible = true, lastActivity = 0 }, debuffs = { visible = true, lastActivity = 0 } }
local layoutWrappers = {}  -- TUIFrame wrappers for Layout integration

local function DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do copy[k] = DeepCopy(v) end
    return copy
end

local function EnsureDefaults(tbl, defaults)
    for k, v in pairs(defaults) do
        if tbl[k] == nil then
            tbl[k] = type(v) == "table" and DeepCopy(v) or v
        elseif type(v) == "table" and type(tbl[k]) == "table" then
            EnsureDefaults(tbl[k], v)
        end
    end
end

local function GetResourceColor(powerType)
    if RESOURCE_COLORS[powerType] then
        local c = RESOURCE_COLORS[powerType]
        return c.r, c.g, c.b
    end
    local info = PowerBarColor[powerType]
    return info and info.r or 1, info and info.g or 1, info and info.b or 1
end

local function GetClassColor()
    local c = RAID_CLASS_COLORS[playerClass]
    return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

local function EnsureDecoder()
    if not secretValueDecoder then
        secretValueDecoder = CreateFrame("StatusBar", nil, UIParent)
        secretValueDecoder:SetSize(100, 1)
        secretValueDecoder:SetPoint("TOPLEFT", -200, -200)
        secretValueDecoder:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
        secretValueDecoder:Hide()
    end
end

local function IsValueAtLeast(secretValue, threshold)
    EnsureDecoder()
    secretValueDecoder:SetMinMaxValues(0, threshold)
    secretValueDecoder:SetValue(secretValue or 0)
    local fill = secretValueDecoder:GetStatusBarTexture()
    if fill then
        local bw, fw = secretValueDecoder:GetWidth(), fill:GetWidth()
        if bw > 0 and fw >= bw - 0.1 then return true end
    end
    return false
end

-- Soul Fragment tracking via Blizzard's bar (works in combat)
-- GetSpellCastCount returns secret values during combat, so we use the bar instead
local SOUL_CLEAVE_SPELL_ID = 228477
local SPIRIT_BOMB_SPELL_ID = 247454
local SOUL_FRAGMENTS_MAX = 6  -- Vengeance can have up to 6 Soul Fragments
local soulFragmentSecretValue = 0

local function GetSoulFragmentSecretValue()
    -- Primary method: Use Blizzard's DemonHunterSoulFragmentsBar
    -- This works in combat unlike GetSpellCastCount which returns secrets
    local bar = _G["DemonHunterSoulFragmentsBar"]
    if bar and bar.GetValue then
        -- Ensure bar is shown (hidden bars still work for GetValue)
        if not bar:IsShown() then
            pcall(function()
                bar:Show()
                bar:SetAlpha(0)  -- Hidden but functional
            end)
        end
        
        local ok, current = pcall(bar.GetValue, bar)
        if ok and current and type(current) == "number" then
            return math.floor(current)  -- Soul Fragments are discrete integers
        end
    end
    
    -- Fallback: Try GetSpellCastCount (only works out of combat)
    -- Wrap in pcall and verify it's a real number, not a secret
    if C_Spell and C_Spell.GetSpellCastCount then
        local ok, count = pcall(C_Spell.GetSpellCastCount, SOUL_CLEAVE_SPELL_ID)
        if ok and count and type(count) == "number" then
            return count
        end
    end
    
    -- Return cached value or 0 - never return a secret
    return soulFragmentSecretValue or 0
end

local function UpdateSoulFragmentSecretValue()
    local newValue = GetSoulFragmentSecretValue()
    -- Only update if we got a valid number
    if type(newValue) == "number" then
        soulFragmentSecretValue = newValue
    end
end

-- Maelstrom Weapon tracking via aura (Enhancement Shaman)
-- Spell ID 344179 is confirmed non-secret in Midnight (PTR 1+)
local MAELSTROM_WEAPON_SPELL_ID = 344179
local maelstromWeaponStacks = 0
local maelstromWeaponMaxStacks = 10

local function GetMaelstromWeaponStacks()
    -- Method 1: Try GetPlayerAuraBySpellID first (works out of combat and open world)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, MAELSTROM_WEAPON_SPELL_ID)
        if ok and auraData and auraData.applications then
            return auraData.applications, maelstromWeaponMaxStacks
        end
    end
    
    -- Method 2: GetAuraDataByIndex iteration (for dungeon/encounter combat)
    -- Don't wrap GetAuraDataByIndex in pcall - it seems to interfere
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local i = 1
        while i <= 40 do  -- Safety limit
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then break end
            
            -- Use pcall only for the comparison (secret spellIds will fail)
            local matchOk, isMatch = pcall(function()
                return auraData.spellId == MAELSTROM_WEAPON_SPELL_ID
            end)
            if matchOk and isMatch then
                return auraData.applications or 0, maelstromWeaponMaxStacks
            end
            i = i + 1
        end
    end
    
    -- Method 3: AuraUtil.FindAuraByName (older API fallback)
    if AuraUtil and AuraUtil.FindAuraByName then
        local ok, name, _, count = pcall(AuraUtil.FindAuraByName, "Maelstrom Weapon", "player", "HELPFUL")
        if ok and name then
            return count or 0, maelstromWeaponMaxStacks
        end
    end
    
    return 0, maelstromWeaponMaxStacks
end

local function UpdateMaelstromWeaponStacks()
    maelstromWeaponStacks = GetMaelstromWeaponStacks()
end

-- Void Metamorphosis tracking (Devourer Demon Hunter)
-- Uses the Blizzard DemonHunterSoulFragmentsBar which is repurposed for Void Meta
local VOID_METAMORPHOSIS_MAX = 50
local voidMetamorphosisCurrent = 0

local function GetVoidMetamorphosisValue()
    -- Primary method: Use Blizzard's DemonHunterSoulFragmentsBar
    -- This bar is repurposed for Devourer's Void Metamorphosis resource
    local bar = _G["DemonHunterSoulFragmentsBar"]
    if bar then
        -- Ensure bar exists and is functional (show it hidden if needed)
        if not bar:IsShown() then
            bar:Show()
            bar:SetAlpha(0)  -- Hidden but functional
        end
        
        local current = bar:GetValue() or 0
        local _, max = bar:GetMinMaxValues()
        return current, max or VOID_METAMORPHOSIS_MAX
    end
    
    -- Fallback: Try to find the bar through PlayerFrame children
    if PlayerFrame then
        for _, child in pairs({PlayerFrame:GetChildren()}) do
            local name = child:GetName()
            if name and (name:find("Devourer") or name:find("VoidMeta") or name:find("SoulFragments")) then
                if child.GetValue then
                    local current = child:GetValue() or 0
                    local _, max = child:GetMinMaxValues()
                    return current, max or VOID_METAMORPHOSIS_MAX
                end
            end
        end
    end
    
    return 0, VOID_METAMORPHOSIS_MAX
end

local function UpdateVoidMetamorphosisValue()
    voidMetamorphosisCurrent = GetVoidMetamorphosisValue()
end

local function GetPlayerInfo()
    local _, class = UnitClass("player")
    playerClass = class
    local specIndex = GetSpecialization()
    playerSpecIndex = specIndex
    if specIndex then playerSpecID = GetSpecializationInfo(specIndex) end
    
    -- Auto-enable class power bar for Brewmaster Monks (stagger uses the class power bar)
    if settings and playerClass == "MONK" then
        local isBrewmaster = (playerSpecID == 268) or (playerSpecIndex == 1)
        if isBrewmaster and settings.classPower and not settings.classPower.enabled then
            settings.classPower.enabled = true
            TUICD:PrintDebug("Auto-enabled class power bar for Brewmaster (Stagger)")
        end
    end
    
    -- Auto-enable class power bar for Enhancement Shamans (Maelstrom Weapon uses the class power bar)
    if settings and playerClass == "SHAMAN" then
        local isEnhancement = (playerSpecID == 263) or (playerSpecIndex == 2)
        if isEnhancement and settings.classPower and not settings.classPower.enabled then
            settings.classPower.enabled = true
            TUICD:PrintDebug("Auto-enabled class power bar for Enhancement (Maelstrom Weapon)")
        end
    end
    
    -- Auto-enable class power bar for Demon Hunters with secondary resources
    -- Vengeance (spec 2): Soul Fragments - discrete segments
    -- Devourer (spec 3): Void Metamorphosis - continuous bar
    if settings and playerClass == "DEMONHUNTER" then
        local isVengeance = (playerSpecID == 581) or (playerSpecIndex == 2)
        local isDevourer = (playerSpecIndex == 3)  -- Devourer is hero spec index 3
        if (isVengeance or isDevourer) and settings.classPower and not settings.classPower.enabled then
            settings.classPower.enabled = true
            if isDevourer then
                TUICD:PrintDebug("Auto-enabled class power bar for Devourer (Void Metamorphosis)")
            else
                TUICD:PrintDebug("Auto-enabled class power bar for Vengeance (Soul Fragments)")
            end
        end
    end
end

-- Check if a resource type uses continuous bar display (vs discrete segments)
local function IsContinuousResource(resourceType)
    if resourceType == SPECIAL_RESOURCES.STAGGER then return true end
    if resourceType == SPECIAL_RESOURCES.VOID_METAMORPHOSIS then return true end
    -- Soul Fragments returns secret values in combat - GetSpellCastCount(228477) is secret
    -- Blizzard did NOT whitelist Vengeance Soul Fragments (only Devourer's Void Meta auras)
    -- So we must use continuous bar display since we can't do comparisons on secret values
    if resourceType == SPECIAL_RESOURCES.SOUL_FRAGMENTS then return true end
    return false
end

local function GetPrimaryResource()
    if not playerClass then GetPlayerInfo() end
    local data = PRIMARY_RESOURCES[playerClass]
    if not data then return nil end
    if type(data) == "table" and data.forms then
        local formID = GetShapeshiftFormID()
        return formID and data.forms[formID] or data.default or Enum.PowerType.Mana
    end
    if type(data) == "table" then
        return playerSpecID and data[playerSpecID] or data.default or Enum.PowerType.Mana
    end
    return data
end

local function GetSecondaryResource()
    if not playerClass then GetPlayerInfo() end
    
    local data = SECONDARY_RESOURCES[playerClass]
    if not data then return nil end
    if type(data) == "table" and data.forms then
        local formID = GetShapeshiftFormID()
        return formID and data.forms[formID] or data.default
    end
    if type(data) == "table" then
        -- Try spec ID first, then fall back to spec index
        local result = playerSpecID and data[playerSpecID]
        if not result and playerSpecIndex then
            result = data[playerSpecIndex]
        end
        return result or data.default
    end
    return data
end

local function GetPrimaryResourceValues()
    local powerType = GetPrimaryResource()
    if not powerType then return nil, nil, nil end
    local current = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    if max then cachedMaxPrimary = max end
    if not max or max == 0 then return nil, nil, nil end
    return current, max, powerType
end

local function GetSecondaryResourceValues()
    local resourceType = GetSecondaryResource()
    if not resourceType then return nil, nil, nil end
    
    if resourceType == SPECIAL_RESOURCES.STAGGER then
        -- UnitStagger may return secret values in dungeons/encounters
        -- Return raw values and let the status bar handle it
        local stagger = UnitStagger("player") or 0
        local maxHealth = UnitHealthMax("player") or 1
        -- DO NOT set cachedMaxSecondary here - maxHealth is too large and would break
        -- discrete segment display if resourceType becomes nil in a race condition
        -- Stagger uses a continuous status bar, not segments, so it doesn't need caching
        -- Return stagger as raw value, use maxHealth as max (not 100)
        -- The bar will display correctly and we avoid arithmetic on secrets
        return stagger, maxHealth, resourceType, stagger
    end
    
    if resourceType == SPECIAL_RESOURCES.SOUL_FRAGMENTS then
        -- Soul Fragments - GetSpellCastCount returns SECRET values in combat
        -- Blizzard did NOT whitelist Vengeance Soul Fragments
        -- DemonHunterSoulFragmentsBar only works for Devourer (0-50), not Vengeance (0-6)
        -- So we return the secret value directly - StatusBar:SetValue() accepts secrets
        local count = 0
        if C_Spell and C_Spell.GetSpellCastCount then
            count = C_Spell.GetSpellCastCount(SOUL_CLEAVE_SPELL_ID) or 0
        end
        cachedMaxSecondary = SOUL_FRAGMENTS_MAX
        -- Return raw value (may be secret) for continuous bar display
        return count, SOUL_FRAGMENTS_MAX, resourceType, count
    end
    
    if resourceType == SPECIAL_RESOURCES.VOID_METAMORPHOSIS then
        -- Devourer DH uses Blizzard's DemonHunterSoulFragmentsBar for Void Metamorphosis
        -- This is a continuous bar resource (0-50)
        local current, max = GetVoidMetamorphosisValue()
        -- DO NOT cache max in cachedMaxSecondary - 50 is too large for discrete segments
        -- and would cause issues if spec changes to one with discrete resources
        return current, max, resourceType, current
    end
    
    if resourceType == SPECIAL_RESOURCES.MAELSTROM_WEAPON then
        -- Enhancement Shaman's Maelstrom Weapon is aura-based
        -- In Midnight, this aura is flagged as non-secret (spell ID 344179)
        UpdateMaelstromWeaponStacks()
        local current, max = GetMaelstromWeaponStacks()
        cachedMaxSecondary = max
        return current, max, resourceType
    end
    
    if resourceType == Enum.PowerType.Runes then
        local max = UnitPowerMax("player", resourceType) or 6
        cachedMaxSecondary = max
        local ready = 0
        for i = 1, max do
            local _, _, runeReady = GetRuneCooldown(i)
            if runeReady then ready = ready + 1 end
        end
        return ready, max, resourceType
    end
    
    -- In Midnight Beta 3+, secondary resources (Combo Points, Soul Shards, Holy Power, 
    -- Chi, Arcane Charges, Essence) are no longer secret
    local current = UnitPower("player", resourceType)
    local max = UnitPowerMax("player", resourceType)
    if max then cachedMaxSecondary = max end
    if not max or max == 0 then return nil, nil, nil end
    
    -- For Midnight non-secret resources, we can now do math operations directly
    -- Previously we had to use workarounds for secret values
    return current, max, resourceType
end

local function IsNormalValueResource(resourceType)
    -- Use the new Midnight-aware non-secret resource check
    return IsNonSecretResource(resourceType)
end

-- Get current player state for visibility
local function GetPlayerState()
    local state = {
        inCombat = UnitAffectingCombat("player"),
        hasTarget = UnitExists("target"),
        inInstance = IsInInstance(),
        inRaid = IsInRaid(),
        inParty = IsInGroup() and not IsInRaid(),
        solo = not IsInGroup(),
    }
    return state
end

-- Check visibility conditions (OR logic)
local function CheckVisibilityConditions(cfg)
    -- Force all visible mode bypasses all visibility conditions
    if TUICD.forceAllVisible then return true end
    
    if not cfg.visibilityEnabled then return true end
    
    local state = GetPlayerState()
    
    if state.inCombat and cfg.showInCombat then return true end
    if not state.inCombat and cfg.showOutOfCombat then return true end
    if state.hasTarget and cfg.showHasTarget then return true end
    if not state.hasTarget and cfg.showNoTarget then return true end
    if state.solo and cfg.showSolo then return true end
    if state.inParty and cfg.showInParty then return true end
    if state.inRaid and cfg.showInRaid then return true end
    if state.inInstance and cfg.showInInstance then return true end
    
    return false
end

local function ShouldShowHealthBar()
    if not settings or not settings.healthBar or not settings.healthBar.enabled then return false end
    return CheckVisibilityConditions(settings.healthBar)
end

local function ShouldShowPowerBar()
    if not settings or not settings.powerBar.enabled then return false end
    return CheckVisibilityConditions(settings.powerBar)
end

local function ShouldShowClassPower()
    if not settings or not settings.classPower.enabled then return false end
    if not GetSecondaryResource() then return false end
    return CheckVisibilityConditions(settings.classPower)
end

local function ShouldShowSoulFragments()
    -- Soul fragments now handled by class power bar segments, not separate icon frame
    return false
end

local function GetFadeAlpha(barType)
    local cfg
    if barType == "health" then
        cfg = settings.healthBar
    elseif barType == "power" then
        cfg = settings.powerBar
    elseif barType == "class" then
        cfg = settings.classPower
    elseif barType == "soul" then
        cfg = settings.soulFragments
    else
        return 1
    end
    
    local state = visibilityState[barType]
    if not state then return 1 end
    
    if not cfg.fadeEnabled then return 1 end
    
    local now = GetTime()
    if (now - state.lastActivity) > cfg.fadeDelay then
        return cfg.fadeAlpha
    end
    return 1
end

local function MarkActivity(barType)
    visibilityState[barType].lastActivity = GetTime()
end

-- ============================================================================
-- HEALTH BAR
-- ============================================================================

local function CreateHealthBar()
    if healthBarFrame then return healthBarFrame end
    local cfg = settings.healthBar
    local frame = CreateFrame("Frame", "TUICD_PersonalResources_HealthBar", UIParent, "BackdropTemplate")
    frame:SetSize(cfg.width, cfg.height)
    -- Use fallback defaults if position values were cleared by migration
    local anchor = cfg.anchor or "CENTER"
    local posX = cfg.positionX or 0
    local posY = cfg.positionY or -180
    frame:SetPoint(anchor, UIParent, anchor, posX, posY)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:SetClampedToScreen(true)
    
    -- START HIDDEN: Prevent visible position jumps during initialization
    frame:SetAlpha(0)
    if TUICD.TUIFrame and TUICD.TUIFrame.RegisterPendingFrame then
        TUICD.TUIFrame.RegisterPendingFrame(frame)
    end
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(cfg.backgroundColor[1], cfg.backgroundColor[2], cfg.backgroundColor[3], cfg.backgroundColor[4] or 0.8)
    frame.background = bg
    
    local sb = CreateFrame("StatusBar", nil, frame)
    sb:SetAllPoints()
    sb:SetStatusBarTexture(TUICD.Media:GetTextureWithGlobal(cfg.texture))
    sb:GetStatusBarTexture():SetDrawLayer("ARTWORK")
    sb:SetMinMaxValues(0, 100)
    sb:SetValue(100)
    frame.statusBar = sb
    
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = cfg.borderSize or 1 })
    border:SetBackdropBorderColor(cfg.borderColor[1], cfg.borderColor[2], cfg.borderColor[3], cfg.borderColor[4] or 1)
    frame.border = border
    if not cfg.showBorder then border:Hide() end
    
    local text = sb:CreateFontString(nil, "OVERLAY")
    text:SetFont(TUICD.Media:GetFontWithGlobal(cfg.font), cfg.textFontSize, TUICD.Media:GetOutlineWithGlobal(cfg.textFontOutline))
    text:SetPoint("CENTER", 0, 0)
    text:SetTextColor(cfg.textColor[1], cfg.textColor[2], cfg.textColor[3], cfg.textColor[4] or 1)
    frame.text = text
    if not cfg.showText then text:Hide() end
    
    -- Absorb overlay (sits on top of health bar, extends from current health)
    local absorbBar = CreateFrame("StatusBar", nil, frame)
    absorbBar:SetAllPoints(sb)
    absorbBar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Fill")
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:SetFrameLevel(sb:GetFrameLevel() + 1)
    -- Fill from the right side (like Blizzard's absorb bars)
    absorbBar:SetFillStyle(Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Reverse or "REVERSE")
    -- Apply color from settings
    absorbBar:SetStatusBarColor(cfg.absorbColor[1], cfg.absorbColor[2], cfg.absorbColor[3], cfg.absorbColor[4] or 0.7)
    absorbBar:Hide()
    frame.absorbBar = absorbBar
    
    -- Absorb glow/spark at the edge (Blizzard style)
    local overGlow = absorbBar:CreateTexture(nil, "OVERLAY")
    overGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
    overGlow:SetBlendMode("ADD")
    overGlow:SetSize(8, cfg.height)
    overGlow:SetPoint("RIGHT", absorbBar:GetStatusBarTexture(), "LEFT", 4, 0)
    overGlow:Hide()
    absorbBar.overGlow = overGlow
    
    -- Absorb text
    local absorbText = absorbBar:CreateFontString(nil, "OVERLAY")
    absorbText:SetFont(TUICD.Media:GetFontWithGlobal(cfg.font), cfg.absorbTextFontSize, TUICD.Media:GetOutlineWithGlobal(cfg.textFontOutline))
    absorbText:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    absorbText:SetTextColor(cfg.absorbTextColor[1], cfg.absorbTextColor[2], cfg.absorbTextColor[3], cfg.absorbTextColor[4] or 1)
    absorbText:Hide()
    absorbBar.text = absorbText
    
    frame:Hide()
    healthBarFrame = frame
    
    return frame
end

local function GetHealthGradientColor(percent)
    -- Green at full health, yellow at 50%, red at low health
    if percent > 0.5 then
        local factor = (percent - 0.5) * 2  -- 0-1 as health goes from 50% to 100%
        return 1 - factor, 1, 0  -- Yellow to Green
    else
        local factor = percent * 2  -- 0-1 as health goes from 0% to 50%
        return 1, factor, 0  -- Red to Yellow
    end
end

-- Health gradient color curve for Midnight API (avoids secret value arithmetic)
local healthGradientCurve = nil
local function GetOrCreateHealthGradientCurve()
    if healthGradientCurve then return healthGradientCurve end
    
    -- CreateColorCurve is a Midnight API
    if CreateColorCurve then
        healthGradientCurve = CreateColorCurve()
        healthGradientCurve:AddPoint(0, CreateColor(1, 0, 0, 1))      -- Red at 0%
        healthGradientCurve:AddPoint(0.5, CreateColor(1, 1, 0, 1))    -- Yellow at 50%
        healthGradientCurve:AddPoint(1, CreateColor(0, 1, 0, 1))      -- Green at 100%
        return healthGradientCurve
    end
    return nil
end

local function UpdateHealthBar()
    if not healthBarFrame then CreateHealthBar() end
    if not ShouldShowHealthBar() then healthBarFrame:Hide() return end
    
    local current = UnitHealth("player")
    local max = UnitHealthMax("player")
    if not current or not max or max == 0 then healthBarFrame:Hide() return end
    
    local cfg = settings.healthBar
    healthBarFrame.statusBar:SetMinMaxValues(0, max)
    SetBarValueSmooth(healthBarFrame.statusBar, current, true)  -- Always use smooth in Midnight
    
    -- Set bar color
    if cfg.useHealthGradient then
        -- Use color curve for Midnight (avoids arithmetic on secret values)
        local curve = GetOrCreateHealthGradientCurve()
        if curve and UnitHealthPercent then
            local ok, colorMixin = pcall(UnitHealthPercent, "player", false, curve)
            if ok and colorMixin and colorMixin.GetRGB then
                healthBarFrame.statusBar:SetStatusBarColor(colorMixin:GetRGB())
            else
                healthBarFrame.statusBar:SetStatusBarColor(0, 1, 0)  -- Fallback to green
            end
        else
            -- No curve available - fallback to green
            healthBarFrame.statusBar:SetStatusBarColor(0, 1, 0)
        end
    elseif cfg.useClassColor then
        local r, g, b = GetClassColor()
        healthBarFrame.statusBar:SetStatusBarColor(r, g, b)
    else
        healthBarFrame.statusBar:SetStatusBarColor(cfg.customColor[1], cfg.customColor[2], cfg.customColor[3])
    end
    
    -- Update text
    if cfg.showText then
        if cfg.textFormat == "current" then
            local displayCurrent = cfg.abbreviateNumbers and AbbreviateLargeNumbers(current) or current
            healthBarFrame.text:SetText(tostring(displayCurrent))
        elseif cfg.textFormat == "current_max" then
            local displayCurrent = cfg.abbreviateNumbers and AbbreviateLargeNumbers(current) or current
            local displayMax = cfg.abbreviateNumbers and AbbreviateLargeNumbers(max) or max
            healthBarFrame.text:SetText(displayCurrent .. " / " .. displayMax)
        elseif cfg.textFormat == "percent" then
            -- Use UnitHealthPercent for Midnight (handles secret values)
            if UnitHealthPercent then
                local ok, pct = pcall(UnitHealthPercent, "player", false, CurveConstants and CurveConstants.ScaleTo100)
                if ok and pct then
                    healthBarFrame.text:SetFormattedText("%.0f%%", pct)
                else
                    healthBarFrame.text:SetText("?%")
                end
            else
                healthBarFrame.text:SetText("?%")
            end
        else
            healthBarFrame.text:SetText("")
        end
        healthBarFrame.text:Show()
    else
        healthBarFrame.text:Hide()
    end
    
    MarkActivity("health")
    healthBarFrame:SetAlpha(GetFadeAlpha("health"))
    healthBarFrame:Show()
end

local function UpdateAbsorbOverlay()
    if not healthBarFrame or not healthBarFrame.absorbBar then return end
    local cfg = settings.healthBar
    
    if not cfg.showAbsorb then
        healthBarFrame.absorbBar:Hide()
        if healthBarFrame.absorbBar.overGlow then
            healthBarFrame.absorbBar.overGlow:Hide()
        end
        if healthBarFrame.absorbBar.text then
            healthBarFrame.absorbBar.text:Hide()
        end
        return
    end
    
    -- In Midnight, UnitGetTotalAbsorbs returns secret values
    -- StatusBars handle secret values natively via SetValue() - just pass it through
    local maxHealth = UnitHealthMax("player") or 1
    local absorb = UnitGetTotalAbsorbs("player") or 0
    
    healthBarFrame.absorbBar:SetMinMaxValues(0, maxHealth)
    healthBarFrame.absorbBar:SetValue(absorb)
    healthBarFrame.absorbBar:Show()
    
    -- Show glow effect (but not when using non-square masks - it won't look right at curved edges)
    if healthBarFrame.absorbBar.overGlow then
        local maskShape = cfg.maskShape or "none"
        if maskShape == "none" then
            healthBarFrame.absorbBar.overGlow:SetSize(8, cfg.height)
            healthBarFrame.absorbBar.overGlow:Show()
        else
            healthBarFrame.absorbBar.overGlow:Hide()
        end
    end
    
    -- Update absorb text (using AbbreviateLargeNumbers which handles secret values)
    -- Note: Percent format not possible with Midnight's secret values - no UnitAbsorbPercent API
    if cfg.absorbShowText and healthBarFrame.absorbBar.text then
        healthBarFrame.absorbBar.text:SetText(AbbreviateLargeNumbers(absorb))
        healthBarFrame.absorbBar.text:Show()
    elseif healthBarFrame.absorbBar.text then
        healthBarFrame.absorbBar.text:Hide()
    end
end

-- ============================================================================
-- POWER BAR
-- ============================================================================

local function CreatePowerBar()
    if powerBarFrame then return powerBarFrame end
    local cfg = settings.powerBar
    local frame = CreateFrame("Frame", "TUICD_PersonalResources_PowerBar", UIParent, "BackdropTemplate")
    frame:SetSize(cfg.width, cfg.height)
    -- Use fallback defaults if position values were cleared by migration
    local anchor = cfg.anchor or "CENTER"
    local posX = cfg.positionX or 0
    local posY = cfg.positionY or -200
    frame:SetPoint(anchor, UIParent, anchor, posX, posY)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:SetClampedToScreen(true)
    
    -- START HIDDEN: Prevent visible position jumps during initialization
    frame:SetAlpha(0)
    if TUICD.TUIFrame and TUICD.TUIFrame.RegisterPendingFrame then
        TUICD.TUIFrame.RegisterPendingFrame(frame)
    end
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(cfg.backgroundColor[1], cfg.backgroundColor[2], cfg.backgroundColor[3], cfg.backgroundColor[4] or 0.8)
    frame.background = bg
    
    local sb = CreateFrame("StatusBar", nil, frame)
    sb:SetAllPoints()
    sb:SetStatusBarTexture(TUICD.Media:GetTextureWithGlobal(cfg.texture))
    sb:GetStatusBarTexture():SetDrawLayer("ARTWORK")
    sb:SetMinMaxValues(0, 100)
    sb:SetValue(100)
    frame.statusBar = sb
    
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = cfg.borderSize or 1 })
    border:SetBackdropBorderColor(cfg.borderColor[1], cfg.borderColor[2], cfg.borderColor[3], cfg.borderColor[4] or 1)
    frame.border = border
    if not cfg.showBorder then border:Hide() end
    
    local text = sb:CreateFontString(nil, "OVERLAY")
    text:SetFont(TUICD.Media:GetFontWithGlobal(cfg.font), cfg.textFontSize, TUICD.Media:GetOutlineWithGlobal(cfg.textFontOutline))
    text:SetPoint("CENTER", 0, 0)
    text:SetTextColor(cfg.textColor[1], cfg.textColor[2], cfg.textColor[3], cfg.textColor[4] or 1)
    frame.text = text
    if not cfg.showText then text:Hide() end
    
    frame:Hide()
    powerBarFrame = frame
    
    -- Register with Edit Mode
    if TUICD.EditMode then
        TUICD.EditMode:RegisterFrame(frame, {
            name = "TUICD: Power Bar",
            onPositionChanged = function(f, point, x, y)
                settings.powerBar.positionX = x
                settings.powerBar.positionY = y
                settings.powerBar.anchor = point
            end,
            default = { point = cfg.anchor or "CENTER", x = cfg.positionX or 0, y = cfg.positionY or -200 },
        })
    end
    
    return frame
end

local function UpdatePowerBar()
    if not powerBarFrame then CreatePowerBar() end
    if not ShouldShowPowerBar() then powerBarFrame:Hide() return end
    
    local current, max, powerType = GetPrimaryResourceValues()
    if not current or not max then powerBarFrame:Hide() return end
    
    local cfg = settings.powerBar
    powerBarFrame.statusBar:SetMinMaxValues(0, max)
    -- Use smooth animation (Midnight native)
    SetBarValueSmooth(powerBarFrame.statusBar, current, true)
    
    local r, g, b
    if cfg.useClassColor then r, g, b = GetClassColor()
    elseif cfg.useResourceColor then r, g, b = GetResourceColor(powerType)
    else r, g, b = cfg.customColor[1], cfg.customColor[2], cfg.customColor[3] end
    powerBarFrame.statusBar:SetStatusBarColor(r, g, b)
    
    if cfg.showText then
        if cfg.textFormat == "current" then
            powerBarFrame.text:SetFormattedText("%d", current)
        elseif cfg.textFormat == "current_max" then
            powerBarFrame.text:SetFormattedText("%d / %d", current, max)
        elseif cfg.textFormat == "percent" then
            if UnitPowerPercent then
                -- UnitPower signature is (unit, powerType, unmodified)
                -- So UnitPowerPercent is likely (unit, powerType, unmodified, curve)
                -- Health has no powerType so it's (unit, unmodified, curve)
                local curve = CurveConstants and CurveConstants.ScaleTo100
                local ok, pct = pcall(UnitPowerPercent, "player", powerType, false, curve)
                if ok and pct then
                    powerBarFrame.text:SetFormattedText("%.0f%%", pct)
                else
                    powerBarFrame.text:SetText("?%")
                end
            else
                powerBarFrame.text:SetText("?%")
            end
        else
            powerBarFrame.text:SetText("")
        end
        powerBarFrame.text:Show()
    else
        powerBarFrame.text:Hide()
    end
    
    MarkActivity("power")
    powerBarFrame:SetAlpha(GetFadeAlpha("power"))
    powerBarFrame:Show()
end

local function CreateClassPowerSegment(parent, index, w, h)
    local seg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    seg:SetSize(w, h)
    
    local bg = seg:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    seg.background = bg
    
    local fill = seg:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    seg.fill = fill
    
    local border = CreateFrame("Frame", nil, seg, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    seg.border = border
    
    local cd = seg:CreateFontString(nil, "OVERLAY")
    cd:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    cd:SetPoint("CENTER")
    cd:SetTextColor(1, 1, 1, 1)
    cd:Hide()
    seg.cooldownText = cd
    
    return seg
end

local function CreateClassPowerFrame()
    if classPowerFrame then return classPowerFrame end
    local cfg = settings.classPower
    local scale = settings.global and settings.global.scale or 1
    local frame = CreateFrame("Frame", "TUICD_PersonalResources_ClassPower", UIParent)
    frame:SetSize(cfg.width * scale, cfg.height * scale)
    -- Use fallback defaults if position values were cleared by migration
    local anchor = cfg.anchor or "CENTER"
    local posX = cfg.positionX or 0
    local posY = cfg.positionY or -220
    frame:SetPoint(anchor, UIParent, anchor, posX, posY)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(11)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:SetClampedToScreen(true)
    
    -- START HIDDEN: Prevent visible position jumps during initialization
    frame:SetAlpha(0)
    if TUICD.TUIFrame and TUICD.TUIFrame.RegisterPendingFrame then
        TUICD.TUIFrame.RegisterPendingFrame(frame)
    end
    
    -- Status bar for continuous resources (Stagger, etc.)
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetAllPoints()
    statusBar:SetMinMaxValues(0, 100)
    statusBar:SetValue(0)
    local tex = TUICD.Media:GetTextureWithGlobal(cfg.texture or "Blizzard") or "Interface\\TargetingFrame\\UI-StatusBar"
    statusBar:SetStatusBarTexture(tex)
    statusBar:Hide()
    frame.statusBar = statusBar
    
    -- Background for status bar
    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    frame.statusBarBg = bg
    
    -- Border for status bar
    local border = CreateFrame("Frame", nil, statusBar, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    border:Hide()
    frame.statusBarBorder = border
    
    -- Segment dividers overlay (for Soul Fragments - makes continuous bar look like 6 pips)
    -- Create 5 dividers to split the bar into 6 visual segments
    local dividers = {}
    for i = 1, 5 do
        local divider = statusBar:CreateTexture(nil, "OVERLAY")
        divider:SetColorTexture(0, 0, 0, 0.9)  -- Dark divider lines
        divider:SetWidth(2)  -- 2 pixel wide divider
        divider:SetPoint("TOP", statusBar, "TOP", 0, 0)
        divider:SetPoint("BOTTOM", statusBar, "BOTTOM", 0, 0)
        -- Position will be set dynamically based on bar width
        divider:Hide()
        dividers[i] = divider
    end
    frame.segmentDividers = dividers
    
    -- Segment color overlays (for Soul Fragments gradient effect)
    -- 6 overlays that can be colored individually to create gradient from dark to light
    local segmentOverlays = {}
    for i = 1, 6 do
        local overlay = statusBar:CreateTexture(nil, "ARTWORK", nil, 1)  -- Above bar texture
        overlay:SetColorTexture(1, 1, 1, 1)
        overlay:Hide()
        segmentOverlays[i] = overlay
    end
    frame.segmentOverlays = segmentOverlays
    
    -- Text overlay frame (ensures text is above the status bar)
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.textOverlay = textOverlay
    
    local text = textOverlay:CreateFontString(nil, "OVERLAY")
    local fontPath = TUICD.Media:GetFont(cfg.textFont) or STANDARD_TEXT_FONT
    text:SetFont(fontPath, cfg.textFontSize, cfg.textFontOutline)
    text:SetPoint("CENTER", frame, "CENTER", cfg.textOffsetX or 0, cfg.textOffsetY or 0)
    text:SetTextColor(cfg.textColor[1], cfg.textColor[2], cfg.textColor[3], cfg.textColor[4] or 1)
    text:Hide()
    frame.text = text
    
    frame:Hide()
    classPowerFrame = frame
    
    -- Register with Edit Mode
    if TUICD.EditMode then
        TUICD.EditMode:RegisterFrame(frame, {
            name = "TUICD: Class Power",
            onPositionChanged = function(f, point, x, y)
                settings.classPower.positionX = x
                settings.classPower.positionY = y
                settings.classPower.anchor = point
            end,
            default = { point = cfg.anchor or "CENTER", x = cfg.positionX or 0, y = cfg.positionY or -220 },
        })
    end
    
    return frame
end

-- Separate Soul Fragment display frame (Vengeance DH only)
local function CreateSoulFragmentFrame()
    if soulFragmentFrame then return soulFragmentFrame end
    local sfCfg = settings.soulFragments
    local baseSize = 256
    local scaledSize = baseSize * sfCfg.scale
    
    local frame = CreateFrame("Frame", "TUICD_PersonalResources_SoulFragments", UIParent)
    frame:SetSize(scaledSize, scaledSize)
    -- Use fallback defaults if position values were cleared by migration
    local anchor = sfCfg.anchor or "CENTER"
    local posX = sfCfg.positionX or 0
    local posY = sfCfg.positionY or -220
    frame:SetPoint(anchor, UIParent, anchor, posX, posY)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(11)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:SetClampedToScreen(true)
    frame:Hide()
    
    -- Background texture (the custom image)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\AddOns\\TweaksUI_Cooldowns\\Media\\Textures\\SoulFragments_" .. sfCfg.style)
    frame.texture = texture
    
    -- Count text (centered on the image)
    local countText = frame:CreateFontString(nil, "OVERLAY")
    countText:SetFont(STANDARD_TEXT_FONT, sfCfg.countFontSize, sfCfg.countFontOutline)
    countText:SetPoint("CENTER", 0, sfCfg.countOffsetY)
    countText:SetTextColor(sfCfg.countColor[1], sfCfg.countColor[2], sfCfg.countColor[3], sfCfg.countColor[4] or 1)
    frame.countText = countText
    
    -- Label text (below the image)
    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, sfCfg.labelFontSize, sfCfg.labelFontOutline)
    label:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    label:SetText("Soul Fragments")
    label:SetTextColor(sfCfg.labelColor[1], sfCfg.labelColor[2], sfCfg.labelColor[3], sfCfg.labelColor[4] or 1)
    if not sfCfg.showLabel then label:Hide() end
    frame.label = label
    
    soulFragmentFrame = frame
    
    -- Register with Edit Mode
    if TUICD.EditMode then
        TUICD.EditMode:RegisterFrame(frame, {
            name = "TUICD: Soul Fragments",
            onPositionChanged = function(f, point, x, y)
                settings.soulFragments.positionX = x
                settings.soulFragments.positionY = y
                settings.soulFragments.anchor = point
            end,
            default = { point = sfCfg.anchor or "CENTER", x = sfCfg.positionX or 0, y = sfCfg.positionY or -220 },
        })
    end
    
    return frame
end

local function UpdateClassPowerSegments(maxPoints)
    if not classPowerFrame then CreateClassPowerFrame() end
    
    -- Safety cap: never create more than 10 segments (max discrete resource is 7 for Arcane Charges)
    -- This prevents catastrophic memory/CPU issues if maxPoints is corrupted (e.g., stagger's maxHealth leaking)
    if maxPoints > 10 then
        maxPoints = 5
    end
    
    local cfg = settings.classPower
    local scale = settings.global and settings.global.scale or 1
    local spacing = cfg.spacing * scale
    local scaledWidth = cfg.width * scale
    local scaledHeight = cfg.height * scale
    local segW = (scaledWidth - spacing * (maxPoints - 1)) / maxPoints
    
    for i = 1, maxPoints do
        if not classPowerSegments[i] then
            classPowerSegments[i] = CreateClassPowerSegment(classPowerFrame, i, segW, scaledHeight)
        end
        local seg = classPowerSegments[i]
        seg:SetSize(segW, scaledHeight)
        seg:ClearAllPoints()
        seg:SetPoint("LEFT", classPowerFrame, "LEFT", (i-1) * (segW + spacing), 0)
        
        if cfg.showBorder then
            seg.border:Show()
            seg.border:SetBackdropBorderColor(cfg.borderColor[1], cfg.borderColor[2], cfg.borderColor[3], cfg.borderColor[4] or 1)
        else
            seg.border:Hide()
        end
        
        seg.background:SetColorTexture(cfg.inactiveColor[1], cfg.inactiveColor[2], cfg.inactiveColor[3], cfg.inactiveColor[4] or 0.6)
        seg:Show()
    end
    
    for i = maxPoints + 1, #classPowerSegments do
        if classPowerSegments[i] then classPowerSegments[i]:Hide() end
    end
end

local function GetSegmentColor(index, resourceType)
    local cfg = settings.classPower
    if cfg.usePerPointColors and cfg.perPointColors[index] then
        local c = cfg.perPointColors[index]
        return c[1], c[2], c[3], c[4] or 1
    end
    if cfg.useClassColor then
        local r, g, b = GetClassColor()
        return r, g, b, 1
    end
    if cfg.useResourceColor then
        local r, g, b = GetResourceColor(resourceType)
        return r, g, b, 1
    end
    local c = cfg.customColor
    return c[1], c[2], c[3], c[4] or 1
end

local function UpdateClassPower()
    if not classPowerFrame then CreateClassPowerFrame() end
    
    local current, max, resourceType, rawValue = GetSecondaryResourceValues()
    
    -- Note: Soul Fragments (Vengeance DH) now uses class power segments like other discrete resources
    -- Void Metamorphosis (Devourer DH) uses the continuous bar display
    -- The dedicated soulFragmentFrame icon display can still be used separately if enabled
    
    if not ShouldShowClassPower() then classPowerFrame:Hide() return end
    if not resourceType then classPowerFrame:Hide() return end
    
    local cfg = settings.classPower
    local scale = settings.global and settings.global.scale or 1
    classPowerFrame:SetSize(cfg.width * scale, cfg.height * scale)
    
    -- Check if this is a continuous resource (like Stagger, Void Metamorphosis) vs discrete (like Combo Points, Soul Fragments)
    if IsContinuousResource(resourceType) then
        -- CONTINUOUS RESOURCE DISPLAY (Status Bar)
        -- Hide segments, show status bar
        for i = 1, #classPowerSegments do
            if classPowerSegments[i] then classPowerSegments[i]:Hide() end
        end
        
        -- Update status bar
        classPowerFrame.statusBar:SetMinMaxValues(0, max)
        SetBarValueSmooth(classPowerFrame.statusBar, current, true)  -- Always smooth in Midnight
        
        -- Get color based on resource type
        local r, g, b, a
        if resourceType == SPECIAL_RESOURCES.STAGGER then
            -- Use stagger-specific coloring (dynamic based on level)
            local staggerCfg = settings.stagger
            if staggerCfg and staggerCfg.useDynamicColor then
                -- current is raw stagger, max is maxHealth
                -- Calculate stagger percent safely (might be secret)
                local staggerPct = 0
                local ok, pct = pcall(function()
                    if max > 0 then
                        return (current / max) * 100
                    end
                    return 0
                end)
                if ok then
                    staggerPct = pct
                end
                
                -- Now compare (might still fail if pcall didn't work)
                local compareOk, isHeavy = pcall(function() return staggerPct >= 60 end)
                local _, isModerate = pcall(function() return staggerPct >= 30 end)
                
                if compareOk and isHeavy then
                    r, g, b, a = staggerCfg.heavyColor[1], staggerCfg.heavyColor[2], staggerCfg.heavyColor[3], staggerCfg.heavyColor[4] or 1
                elseif compareOk and isModerate then
                    r, g, b, a = staggerCfg.moderateColor[1], staggerCfg.moderateColor[2], staggerCfg.moderateColor[3], staggerCfg.moderateColor[4] or 1
                else
                    -- Light stagger or couldn't compare (secret value) - use light color
                    r, g, b, a = staggerCfg.lightColor[1], staggerCfg.lightColor[2], staggerCfg.lightColor[3], staggerCfg.lightColor[4] or 1
                end
            else
                local c = staggerCfg and staggerCfg.customColor or { 0.52, 1, 0.52, 1 }
                r, g, b, a = c[1], c[2], c[3], c[4] or 1
            end
        else
            -- Default coloring for other continuous resources
            if cfg.useClassColor then
                r, g, b = GetClassColor()
                a = 1
            elseif cfg.useResourceColor then
                r, g, b = GetResourceColor(resourceType)
                a = 1
            else
                r, g, b, a = cfg.customColor[1], cfg.customColor[2], cfg.customColor[3], cfg.customColor[4] or 1
            end
        end
        classPowerFrame.statusBar:SetStatusBarColor(r, g, b, a or 1)
        
        -- Update background
        local bgColor = settings.stagger and settings.stagger.backgroundColor or { 0.1, 0.1, 0.1, 0.8 }
        classPowerFrame.statusBarBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.8)
        
        -- Update border
        if cfg.showBorder then
            classPowerFrame.statusBarBorder:SetBackdropBorderColor(cfg.borderColor[1], cfg.borderColor[2], cfg.borderColor[3], cfg.borderColor[4] or 1)
            classPowerFrame.statusBarBorder:Show()
        else
            classPowerFrame.statusBarBorder:Hide()
        end
        
        classPowerFrame.statusBar:Show()
        
        -- Soul Fragments gradient presets (start color, end color for SetGradient)
        -- SetGradient only supports 2 colors, so we use dark->light
        local SOUL_FRAGMENT_GRADIENTS = {
            none = nil,  -- No gradient, use solid bar color
            green = {
                start = { 0.05, 0.25, 0.05, 1.0 },  -- Very dark green
                finish = { 0.75, 1.00, 0.50, 1.0 },  -- Bright green
            },
            purple = {
                start = { 0.30, 0.05, 0.40, 1.0 },  -- Dark purple (DH fury)
                finish = { 1.00, 0.90, 1.00, 1.0 },  -- Nearly white
            },
        }
        
        -- Handle segment dividers (for Soul Fragments visual - makes bar look like 6 pips)
        if classPowerFrame.segmentDividers then
            if resourceType == SPECIAL_RESOURCES.SOUL_FRAGMENTS and max == 6 then
                -- Show dividers for Soul Fragments
                local barWidth = classPowerFrame.statusBar:GetWidth()
                local barHeight = classPowerFrame.statusBar:GetHeight()
                local segmentWidth = barWidth / 6
                
                -- Calculate effective scale to keep dividers at exactly 1 pixel visually
                local effectiveScale = classPowerFrame:GetEffectiveScale()
                local dividerWidth = 1 / effectiveScale
                
                -- Position dividers
                for i = 1, 5 do
                    local divider = classPowerFrame.segmentDividers[i]
                    if divider then
                        divider:ClearAllPoints()
                        -- Position at 1/6, 2/6, 3/6, 4/6, 5/6 of bar width from left
                        local xOffset = (segmentWidth * i) - (barWidth / 2)
                        divider:SetPoint("CENTER", classPowerFrame.statusBar, "CENTER", xOffset, 0)
                        divider:SetWidth(dividerWidth)
                        divider:SetHeight(barHeight)
                        divider:Show()
                    end
                end
                
                -- Apply gradient to the statusbar texture itself (properly clipped by fill level)
                local gradientStyle = cfg.soulFragmentsGradient or "purple"
                local gradientColors = SOUL_FRAGMENT_GRADIENTS[gradientStyle]
                local barTexture = classPowerFrame.statusBar:GetStatusBarTexture()
                
                if gradientColors and barTexture then
                    -- Use SetGradient for horizontal gradient from dark to light
                    local s = gradientColors.start
                    local f = gradientColors.finish
                    barTexture:SetGradient("HORIZONTAL", 
                        CreateColor(s[1], s[2], s[3], s[4]), 
                        CreateColor(f[1], f[2], f[3], f[4]))
                elseif barTexture then
                    -- No gradient - reset to solid color (use SetStatusBarColor which was set above)
                    barTexture:SetGradient("HORIZONTAL", 
                        CreateColor(r, g, b, a or 1), 
                        CreateColor(r, g, b, a or 1))
                end
                
                -- Hide segment overlays (not used anymore)
                if classPowerFrame.segmentOverlays then
                    for i = 1, 6 do
                        if classPowerFrame.segmentOverlays[i] then
                            classPowerFrame.segmentOverlays[i]:Hide()
                        end
                    end
                end
            else
                -- Hide dividers for other continuous resources (Stagger, Void Meta)
                for i = 1, 5 do
                    if classPowerFrame.segmentDividers[i] then
                        classPowerFrame.segmentDividers[i]:Hide()
                    end
                end
                -- Hide overlays
                if classPowerFrame.segmentOverlays then
                    for i = 1, 6 do
                        if classPowerFrame.segmentOverlays[i] then
                            classPowerFrame.segmentOverlays[i]:Hide()
                        end
                    end
                end
                -- Reset gradient to solid color for non-Soul-Fragment resources
                local barTexture = classPowerFrame.statusBar:GetStatusBarTexture()
                if barTexture then
                    barTexture:SetGradient("HORIZONTAL", 
                        CreateColor(r, g, b, a or 1), 
                        CreateColor(r, g, b, a or 1))
                end
            end
        end
        
        -- Update text for continuous resources - always show for stagger
        local showStaggerText = (resourceType == SPECIAL_RESOURCES.STAGGER) or cfg.showText
        if showStaggerText then
            -- Position text in center of bar for continuous resources (with offset)
            classPowerFrame.text:ClearAllPoints()
            classPowerFrame.text:SetPoint("CENTER", classPowerFrame.statusBar, "CENTER", cfg.textOffsetX or 0, cfg.textOffsetY or 0)
            
            -- Update font settings
            local fontPath = TUICD.Media:GetFont(cfg.textFont) or STANDARD_TEXT_FONT
            classPowerFrame.text:SetFont(fontPath, cfg.textFontSize, cfg.textFontOutline)
            classPowerFrame.text:SetTextColor(cfg.textColor[1], cfg.textColor[2], cfg.textColor[3], cfg.textColor[4] or 1)
            
            if resourceType == SPECIAL_RESOURCES.STAGGER then
                local staggerCfg = settings.stagger
                local textFormat = staggerCfg and staggerCfg.textFormat or "percent"
                -- current is now raw stagger, max is maxHealth
                -- Use AbbreviateLargeNumbers which handles secret values
                if textFormat == "amount" then
                    -- Show actual stagger amount
                    classPowerFrame.text:SetText(AbbreviateLargeNumbers(current))
                elseif textFormat == "percent" then
                    -- For percent, we need to calculate safely
                    -- Use UnitStagger and maxHealth - try to avoid arithmetic on secrets
                    if UnitHealthPercent and max > 0 then
                        -- Try using a custom approach - stagger/maxHealth * 100
                        -- Since we can't do math on secrets, just show the abbreviated value
                        -- or use SetFormattedText which might handle it
                        local ok, result = pcall(function()
                            return (current / max) * 100
                        end)
                        if ok then
                            classPowerFrame.text:SetFormattedText("%.0f%%", result)
                        else
                            -- Fallback - just show abbreviated amount
                            classPowerFrame.text:SetText(AbbreviateLargeNumbers(current))
                        end
                    else
                        classPowerFrame.text:SetText(AbbreviateLargeNumbers(current))
                    end
                elseif textFormat == "both" then
                    -- For both, try percent calculation, fallback to just amount
                    local ok, pct = pcall(function()
                        return (current / max) * 100
                    end)
                    if ok then
                        -- Use string.format with AbbreviateLargeNumbers for amount part
                        local amountStr = AbbreviateLargeNumbers(current)
                        classPowerFrame.text:SetText(amountStr .. " (" .. string.format("%.0f%%", pct) .. ")")
                    else
                        classPowerFrame.text:SetText(AbbreviateLargeNumbers(current))
                    end
                end
            else
                -- Generic continuous resource text (Void Metamorphosis, Soul Fragments, etc.)
                -- These values may be secret during combat, so use pcall for arithmetic
                if cfg.textFormat == "percent" then
                    local ok, pct = pcall(function() return (current / max) * 100 end)
                    if ok then
                        classPowerFrame.text:SetFormattedText("%.0f%%", pct)
                    else
                        classPowerFrame.text:SetText(AbbreviateLargeNumbers(current))
                    end
                elseif resourceType == SPECIAL_RESOURCES.VOID_METAMORPHOSIS then
                    -- Void Meta: show current/max 
                    if cfg.textFormat == "current" then
                        classPowerFrame.text:SetText(tostring(current))
                    else
                        local textStr = string.format("%s / %d", tostring(current), max)
                        classPowerFrame.text:SetText(textStr)
                    end
                elseif resourceType == SPECIAL_RESOURCES.SOUL_FRAGMENTS then
                    -- Soul Fragments: current may be secret, use tostring() 
                    if cfg.textFormat == "current" then
                        classPowerFrame.text:SetText(tostring(current))
                    else
                        local textStr = string.format("%s / %d", tostring(current), max)
                        classPowerFrame.text:SetText(textStr)
                    end
                else
                    -- Fallback for other continuous resources
                    if cfg.textFormat == "current" then
                        classPowerFrame.text:SetText(AbbreviateLargeNumbers(current))
                    elseif cfg.textFormat == "current_max" then
                        local textStr = string.format("%s / %d", tostring(current), max)
                        classPowerFrame.text:SetText(textStr)
                    else
                        classPowerFrame.text:SetText(AbbreviateLargeNumbers(current))
                    end
                end
            end
            classPowerFrame.text:Show()
        else
            classPowerFrame.text:Hide()
        end
    else
        -- DISCRETE RESOURCE DISPLAY (Segments)
        -- Hide status bar, show segments
        classPowerFrame.statusBar:Hide()
        classPowerFrame.statusBarBorder:Hide()
        
        -- Safety cap: discrete resources should never exceed 10 segments
        -- Max is 10 for Maelstrom Weapon, 7 for Arcane Charges, 6 for Runes, etc.
        -- cachedMaxSecondary could be incorrectly large if it was set by Stagger (which uses maxHealth)
        local safeMax = cachedMaxSecondary > 0 and cachedMaxSecondary or 5
        if safeMax > 10 then
            safeMax = 5  -- Reset to safe default - this is likely a stagger leak
            if TUICD.PrintDebug then
                TUICD:PrintDebug("PersonalResources: cachedMaxSecondary=" .. tostring(cachedMaxSecondary) .. " is too large for segments, resetting to 5")
            end
        end
        UpdateClassPowerSegments(safeMax)
        
        local isNormal = IsNormalValueResource(resourceType)
        
        for i = 1, safeMax do
            local seg = classPowerSegments[i]
            if seg then
                local r, g, b, a = GetSegmentColor(i, resourceType)
                seg.fill:SetColorTexture(r, g, b, a)
                
                -- All discrete resources now use real numbers (Soul Fragments uses bar:GetValue())
                local isActive
                if isNormal then
                    isActive = (current >= i)
                else
                    isActive = IsValueAtLeast(current, i)
                end
                
                if isActive then
                    seg.fill:SetAlpha(1)
                    seg.fill:Show()
                else
                    seg.fill:Hide()
                end
            end
        end
        
        if cfg.showText then
            -- Reposition text below segments for discrete resources (with offset)
            classPowerFrame.text:ClearAllPoints()
            classPowerFrame.text:SetPoint("CENTER", cfg.textOffsetX or 0, -cfg.height - 5 + (cfg.textOffsetY or 0))
            
            -- Update font settings
            local fontPath = TUICD.Media:GetFont(cfg.textFont) or STANDARD_TEXT_FONT
            classPowerFrame.text:SetFont(fontPath, cfg.textFontSize, cfg.textFontOutline)
            classPowerFrame.text:SetTextColor(cfg.textColor[1], cfg.textColor[2], cfg.textColor[3], cfg.textColor[4] or 1)
            
            if isNormal then
                if cfg.textFormat == "percent" then
                    classPowerFrame.text:SetFormattedText("%.0f%%", (current / safeMax) * 100)
                elseif cfg.textFormat == "current" then
                    classPowerFrame.text:SetText(current .. "")
                else
                    classPowerFrame.text:SetText(current .. "/" .. safeMax)
                end
            else
                if cfg.textFormat == "percent" then
                    local ok, pct = pcall(function() return (current / safeMax) * 100 end)
                    if ok then
                        classPowerFrame.text:SetFormattedText("%.0f%%", pct)
                    else
                        classPowerFrame.text:SetFormattedText("%d", current)
                    end
                elseif cfg.textFormat == "current" then
                    classPowerFrame.text:SetFormattedText("%d", current)
                else
                    classPowerFrame.text:SetFormattedText("%d/%d", current, safeMax)
                end
            end
            classPowerFrame.text:Show()
        else
            classPowerFrame.text:Hide()
        end
    end
    
    MarkActivity("class")
    classPowerFrame:SetAlpha(GetFadeAlpha("class"))
    classPowerFrame:Show()
end

local function UpdateSoulFragments()
    if playerClass ~= "DEMONHUNTER" then return end
    if GetSecondaryResource() ~= SPECIAL_RESOURCES.SOUL_FRAGMENTS then return end
    
    if not ShouldShowSoulFragments() then
        if soulFragmentFrame then soulFragmentFrame:Hide() end
        return
    end
    
    if not soulFragmentFrame then CreateSoulFragmentFrame() end
    
    -- Update the count display
    UpdateSoulFragmentSecretValue()
    local count = soulFragmentSecretValue or 0
    soulFragmentFrame.countText:SetFormattedText("%d", count)
    
    MarkActivity("soul")
    soulFragmentFrame:SetAlpha(GetFadeAlpha("soul"))
    soulFragmentFrame:Show()
end

-- ============================================================================
-- STAGGER UPDATE TICKER (Brewmaster Monk)
-- ============================================================================

local staggerUpdateTicker = nil

local function StartStaggerUpdateTicker()
    if staggerUpdateTicker or playerClass ~= "MONK" then return end
    if GetSecondaryResource() ~= SPECIAL_RESOURCES.STAGGER then return end
    staggerUpdateTicker = C_Timer.NewTicker(0.1, function()
        if settings and settings.enabled and settings.classPower.enabled then 
            UpdateClassPower()
        else 
            if staggerUpdateTicker then staggerUpdateTicker:Cancel() staggerUpdateTicker = nil end 
        end
    end)
end

local function StopStaggerUpdateTicker()
    if staggerUpdateTicker then staggerUpdateTicker:Cancel() staggerUpdateTicker = nil end
end

local function UpdateRuneDisplay()
    if playerClass ~= "DEATHKNIGHT" or not classPowerFrame or not classPowerFrame:IsShown() then return end
    local cfg, runeCfg = settings.classPower, settings.runes
    local max = cachedMaxSecondary > 0 and cachedMaxSecondary or 6
    local now = GetTime()
    
    local states = {}
    for i = 1, max do
        local start, dur, ready = GetRuneCooldown(i)
        local rem = 0
        if not ready and start and dur and dur > 0 then rem = math.max(0, dur - (now - start)) end
        states[i] = { ready = ready, remaining = rem }
    end
    
    if runeCfg.sortByRecharge then
        table.sort(states, function(a, b)
            if a.ready ~= b.ready then return a.ready end
            return a.remaining < b.remaining
        end)
    end
    
    for i = 1, max do
        local seg, st = classPowerSegments[i], states[i]
        if seg and st then
            local r, g, b, a = GetSegmentColor(i, Enum.PowerType.Runes)
            if st.ready then
                seg.fill:SetColorTexture(r, g, b, a)
                seg.fill:Show()
                seg.cooldownText:Hide()
            else
                seg.fill:SetColorTexture(r*0.4, g*0.4, b*0.4, a*0.6)
                seg.fill:Show()
                if runeCfg.showCooldownText then
                    seg.cooldownText:SetText(string.format("%.1f", st.remaining))
                    seg.cooldownText:SetFont(STANDARD_TEXT_FONT, runeCfg.cooldownFontSize, runeCfg.cooldownFontOutline)
                    seg.cooldownText:Show()
                else
                    seg.cooldownText:Hide()
                end
            end
        end
    end
end

local function StartRuneUpdateTicker()
    if runeUpdateTicker or playerClass ~= "DEATHKNIGHT" then return end
    runeUpdateTicker = C_Timer.NewTicker(0.1, function()
        if settings and settings.enabled and settings.classPower.enabled then UpdateRuneDisplay()
        else if runeUpdateTicker then runeUpdateTicker:Cancel() runeUpdateTicker = nil end end
    end)
end

local function StopRuneUpdateTicker()
    if runeUpdateTicker then runeUpdateTicker:Cancel() runeUpdateTicker = nil end
end

local function StartSoulFragmentTicker()
    if soulFragmentTicker or playerClass ~= "DEMONHUNTER" then return end
    if GetSecondaryResource() ~= SPECIAL_RESOURCES.SOUL_FRAGMENTS then return end
    soulFragmentTicker = C_Timer.NewTicker(0.1, function()
        if settings and settings.enabled then
            -- Update class power bar segments (soul fragments now use class power bar)
            if settings.classPower.enabled then
                UpdateClassPower()
            end
            -- Old icon display removed - soul fragments use class power bar segments now
        else 
            if soulFragmentTicker then soulFragmentTicker:Cancel() soulFragmentTicker = nil end 
        end
    end)
end

local function StopSoulFragmentTicker()
    if soulFragmentTicker then soulFragmentTicker:Cancel() soulFragmentTicker = nil end
end

-- Maelstrom Weapon ticker for Enhancement Shaman
local maelstromWeaponTicker = nil

local function StartMaelstromWeaponTicker()
    if maelstromWeaponTicker or playerClass ~= "SHAMAN" then return end
    if GetSecondaryResource() ~= SPECIAL_RESOURCES.MAELSTROM_WEAPON then return end
    maelstromWeaponTicker = C_Timer.NewTicker(0.1, function()
        if settings and settings.enabled and settings.classPower.enabled then 
            UpdateClassPower()
        else 
            if maelstromWeaponTicker then maelstromWeaponTicker:Cancel() maelstromWeaponTicker = nil end 
        end
    end)
end

local function StopMaelstromWeaponTicker()
    if maelstromWeaponTicker then maelstromWeaponTicker:Cancel() maelstromWeaponTicker = nil end
end

-- Void Metamorphosis ticker for Devourer Demon Hunter
local voidMetamorphosisTicker = nil

local function StartVoidMetamorphosisTicker()
    if voidMetamorphosisTicker or playerClass ~= "DEMONHUNTER" then return end
    if GetSecondaryResource() ~= SPECIAL_RESOURCES.VOID_METAMORPHOSIS then return end
    voidMetamorphosisTicker = C_Timer.NewTicker(0.1, function()
        if settings and settings.enabled and settings.classPower.enabled then 
            UpdateClassPower()
        else 
            if voidMetamorphosisTicker then voidMetamorphosisTicker:Cancel() voidMetamorphosisTicker = nil end 
        end
    end)
end

local function StopVoidMetamorphosisTicker()
    if voidMetamorphosisTicker then voidMetamorphosisTicker:Cancel() voidMetamorphosisTicker = nil end
end

local blizzardFramesHidden = false

local function HideBlizzardResourceFrames()
    if not settings.global.hideBlizzardBars or blizzardFramesHidden or InCombatLockdown() then return end
    if PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain then
        local m = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        if m.ClassPowerBar then m.ClassPowerBar:SetAlpha(0) end
        if m.ComboPointsFrame then m.ComboPointsFrame:SetAlpha(0) end
        if m.RuneFrame then m.RuneFrame:SetAlpha(0) end
    end
    if PaladinPowerBarFrame then PaladinPowerBarFrame:SetAlpha(0) end
    if WarlockPowerFrame then WarlockPowerFrame:SetAlpha(0) end
    if MonkHarmonyBarFrame then MonkHarmonyBarFrame:SetAlpha(0) end
    if MonkStaggerBar then MonkStaggerBar:SetAlpha(0) end
    if MageArcaneChargesFrame then MageArcaneChargesFrame:SetAlpha(0) end
    if EssencePlayerFrame then EssencePlayerFrame:SetAlpha(0) end
    if RuneFrame then RuneFrame:SetAlpha(0) end
    blizzardFramesHidden = true
end

local function ShowBlizzardResourceFrames()
    if not blizzardFramesHidden or InCombatLockdown() then return end
    if PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain then
        local m = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        if m.ClassPowerBar then m.ClassPowerBar:SetAlpha(1) end
        if m.ComboPointsFrame then m.ComboPointsFrame:SetAlpha(1) end
        if m.RuneFrame then m.RuneFrame:SetAlpha(1) end
    end
    if PaladinPowerBarFrame then PaladinPowerBarFrame:SetAlpha(1) end
    if WarlockPowerFrame then WarlockPowerFrame:SetAlpha(1) end
    if MonkHarmonyBarFrame then MonkHarmonyBarFrame:SetAlpha(1) end
    if MonkStaggerBar then MonkStaggerBar:SetAlpha(1) end
    if MageArcaneChargesFrame then MageArcaneChargesFrame:SetAlpha(1) end
    if EssencePlayerFrame then EssencePlayerFrame:SetAlpha(1) end
    if RuneFrame then RuneFrame:SetAlpha(1) end
    blizzardFramesHidden = false
end

local function RefreshHealthBarLayout()
    if not healthBarFrame then return end
    local cfg = settings.healthBar
    healthBarFrame:SetSize(cfg.width * settings.global.scale, cfg.height * settings.global.scale)
    
    -- Only set position if NOT parented to a Layout wrapper
    if not layoutWrappers["healthBar"] then
        healthBarFrame:ClearAllPoints()
        local anchor = cfg.anchor or "CENTER"
        local posX = cfg.positionX or 0
        local posY = cfg.positionY or -180
        healthBarFrame:SetPoint(anchor, UIParent, anchor, posX, posY)
    else
        -- Update wrapper size to match bar
        layoutWrappers["healthBar"]:SetSize(cfg.width * settings.global.scale, cfg.height * settings.global.scale)
    end
    
    healthBarFrame.statusBar:SetStatusBarTexture(TUICD.Media:GetTextureWithGlobal(cfg.texture))
    healthBarFrame.background:SetColorTexture(cfg.backgroundColor[1], cfg.backgroundColor[2], cfg.backgroundColor[3], cfg.backgroundColor[4] or 0.8)
    if cfg.showBorder then
        healthBarFrame.border:Show()
        healthBarFrame.border:SetBackdropBorderColor(cfg.borderColor[1], cfg.borderColor[2], cfg.borderColor[3], cfg.borderColor[4] or 1)
    else
        healthBarFrame.border:Hide()
    end
    healthBarFrame.text:SetFont(TUICD.Media:GetFontWithGlobal(cfg.font), cfg.textFontSize, TUICD.Media:GetOutlineWithGlobal(cfg.textFontOutline))
    healthBarFrame.text:SetTextColor(cfg.textColor[1], cfg.textColor[2], cfg.textColor[3], cfg.textColor[4] or 1)
    
    -- Position health text
    healthBarFrame.text:ClearAllPoints()
    local pos = cfg.textPosition or "CENTER"
    local offsetX = cfg.textOffsetX or 0
    local offsetY = cfg.textOffsetY or 0
    if pos == "LEFT" then
        healthBarFrame.text:SetPoint("LEFT", healthBarFrame, "LEFT", 4 + offsetX, offsetY)
    elseif pos == "RIGHT" then
        healthBarFrame.text:SetPoint("RIGHT", healthBarFrame, "RIGHT", -4 + offsetX, offsetY)
    else -- CENTER
        healthBarFrame.text:SetPoint("CENTER", healthBarFrame, "CENTER", offsetX, offsetY)
    end
    
    if cfg.showText then healthBarFrame.text:Show() else healthBarFrame.text:Hide() end
    
    -- Refresh absorb overlay
    if healthBarFrame.absorbBar then
        -- Apply color
        healthBarFrame.absorbBar:SetStatusBarColor(cfg.absorbColor[1], cfg.absorbColor[2], cfg.absorbColor[3], cfg.absorbColor[4] or 0.7)
        
        -- Update glow size
        if healthBarFrame.absorbBar.overGlow then
            healthBarFrame.absorbBar.overGlow:SetSize(8, cfg.height * settings.global.scale)
        end
        
        -- Update text styling and position
        if healthBarFrame.absorbBar.text then
            healthBarFrame.absorbBar.text:SetFont(TUICD.Media:GetFontWithGlobal(cfg.font), cfg.absorbTextFontSize, TUICD.Media:GetOutlineWithGlobal(cfg.textFontOutline))
            healthBarFrame.absorbBar.text:SetTextColor(cfg.absorbTextColor[1], cfg.absorbTextColor[2], cfg.absorbTextColor[3], cfg.absorbTextColor[4] or 1)
            
            -- Position text based on setting
            healthBarFrame.absorbBar.text:ClearAllPoints()
            local pos = cfg.absorbTextPosition or "RIGHT"
            local offsetX = cfg.absorbTextOffsetX or 0
            local offsetY = cfg.absorbTextOffsetY or 0
            if pos == "LEFT" then
                healthBarFrame.absorbBar.text:SetPoint("LEFT", healthBarFrame, "LEFT", 4 + offsetX, offsetY)
            elseif pos == "CENTER" then
                healthBarFrame.absorbBar.text:SetPoint("CENTER", healthBarFrame, "CENTER", offsetX, offsetY)
            else -- RIGHT
                healthBarFrame.absorbBar.text:SetPoint("RIGHT", healthBarFrame, "RIGHT", -4 + offsetX, offsetY)
            end
        end
        
        UpdateAbsorbOverlay()
    end
    
    -- Apply bar masking
    if TUICD.BarMasking and cfg.maskShape then
        TUICD.BarMasking:ApplyToStatusBar(healthBarFrame.statusBar, cfg.maskShape)
        -- Also apply to absorb bar
        if healthBarFrame.absorbBar then
            TUICD.BarMasking:ApplyToStatusBar(healthBarFrame.absorbBar, cfg.maskShape)
        end
    end
end

local function RefreshPowerBarLayout()
    if not powerBarFrame then return end
    local cfg = settings.powerBar
    
    powerBarFrame:SetSize(cfg.width * settings.global.scale, cfg.height * settings.global.scale)
    
    -- Only set position if NOT parented to a Layout wrapper
    -- When parented to wrapper, the wrapper handles positioning
    if not layoutWrappers["powerBar"] then
        powerBarFrame:ClearAllPoints()
        local anchor = cfg.anchor or "CENTER"
        local posX = cfg.positionX or 0
        local posY = cfg.positionY or -200
        powerBarFrame:SetPoint(anchor, UIParent, anchor, posX, posY)
    else
        -- Update wrapper size to match bar
        layoutWrappers["powerBar"]:SetSize(cfg.width * settings.global.scale, cfg.height * settings.global.scale)
    end
    
    powerBarFrame.statusBar:SetStatusBarTexture(TUICD.Media:GetTextureWithGlobal(cfg.texture))
    powerBarFrame.background:SetColorTexture(cfg.backgroundColor[1], cfg.backgroundColor[2], cfg.backgroundColor[3], cfg.backgroundColor[4] or 0.8)
    if cfg.showBorder then
        powerBarFrame.border:Show()
        powerBarFrame.border:SetBackdropBorderColor(cfg.borderColor[1], cfg.borderColor[2], cfg.borderColor[3], cfg.borderColor[4] or 1)
    else
        powerBarFrame.border:Hide()
    end
    powerBarFrame.text:SetFont(TUICD.Media:GetFontWithGlobal(cfg.font), cfg.textFontSize, TUICD.Media:GetOutlineWithGlobal(cfg.textFontOutline))
    powerBarFrame.text:SetTextColor(cfg.textColor[1], cfg.textColor[2], cfg.textColor[3], cfg.textColor[4] or 1)
    if cfg.showText then powerBarFrame.text:Show() else powerBarFrame.text:Hide() end
    
    -- Apply bar masking
    if TUICD.BarMasking and cfg.maskShape then
        TUICD.BarMasking:ApplyToStatusBar(powerBarFrame.statusBar, cfg.maskShape)
    end
end

local function RefreshClassPowerLayout()
    if not classPowerFrame then return end
    local cfg = settings.classPower
    classPowerFrame:SetSize(cfg.width * settings.global.scale, cfg.height * settings.global.scale)
    
    -- Only set position if NOT parented to a Layout wrapper
    if not layoutWrappers["classPower"] then
        classPowerFrame:ClearAllPoints()
        local anchor = cfg.anchor or "CENTER"
        local posX = cfg.positionX or 0
        local posY = cfg.positionY or -220
        classPowerFrame:SetPoint(anchor, UIParent, anchor, posX, posY)
    else
        -- Update wrapper size to match bar
        layoutWrappers["classPower"]:SetSize(cfg.width * settings.global.scale, cfg.height * settings.global.scale)
    end
    
    classPowerFrame.text:SetFont(STANDARD_TEXT_FONT, cfg.textFontSize, cfg.textFontOutline)
    classPowerFrame.text:SetTextColor(cfg.textColor[1], cfg.textColor[2], cfg.textColor[3], cfg.textColor[4] or 1)
    if cachedMaxSecondary > 0 then UpdateClassPowerSegments(cachedMaxSecondary) end
end

local function RefreshSoulFragmentDisplay()
    if not soulFragmentFrame then return end
    local sfCfg = settings.soulFragments
    local baseSize = 256
    local scaledSize = baseSize * sfCfg.scale
    
    -- Update size and position
    soulFragmentFrame:SetSize(scaledSize, scaledSize)
    
    -- Only set position if NOT parented to a Layout wrapper
    if not layoutWrappers["soulFragments"] then
        soulFragmentFrame:ClearAllPoints()
        local anchor = sfCfg.anchor or "CENTER"
        local posX = sfCfg.positionX or 0
        local posY = sfCfg.positionY or -220
        soulFragmentFrame:SetPoint(anchor, UIParent, anchor, posX, posY)
    else
        -- Update wrapper size to match bar
        layoutWrappers["soulFragments"]:SetSize(scaledSize, scaledSize)
    end
    
    -- Update texture (with fallback)
    local texturePath = "Interface\\AddOns\\TweaksUI_Cooldowns\\Media\\Textures\\SoulFragments_" .. sfCfg.style
    soulFragmentFrame.texture:SetTexture(texturePath)
    
    -- If texture failed to load, use a fallback
    if not soulFragmentFrame.texture:GetTexture() then
        soulFragmentFrame.texture:SetTexture("Interface\\Icons\\Spell_Shadow_SoulLeech_3")
        soulFragmentFrame.texture:SetTexCoord(0, 1, 0, 1)
    end
    
    -- Update count text
    soulFragmentFrame.countText:SetFont(STANDARD_TEXT_FONT, sfCfg.countFontSize, sfCfg.countFontOutline)
    soulFragmentFrame.countText:ClearAllPoints()
    soulFragmentFrame.countText:SetPoint("CENTER", 0, sfCfg.countOffsetY)
    soulFragmentFrame.countText:SetTextColor(sfCfg.countColor[1], sfCfg.countColor[2], sfCfg.countColor[3], sfCfg.countColor[4] or 1)
    
    -- Update label
    soulFragmentFrame.label:SetFont(STANDARD_TEXT_FONT, sfCfg.labelFontSize, sfCfg.labelFontOutline)
    soulFragmentFrame.label:SetTextColor(sfCfg.labelColor[1], sfCfg.labelColor[2], sfCfg.labelColor[3], sfCfg.labelColor[4] or 1)
    if sfCfg.showLabel then
        soulFragmentFrame.label:Show()
    else
        soulFragmentFrame.label:Hide()
    end
end

-- ============================================================================
-- PLAYER AURAS (Buffs & Debuffs)
-- ============================================================================

-- Midnight API detection for auras (now uses TUICD.API compatibility layer)
local function HasAuraSorting()
    return C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs and Enum and Enum.UnitAuraSortRule
end

local function HasStringTruncate()
    return C_StringUtil and C_StringUtil.TruncateWhenZero
end

-- Dispel type colors
local DISPEL_COLORS = {
    Magic = { 0.2, 0.6, 1, 1 },
    Curse = { 0.6, 0, 1, 1 },
    Disease = { 0.6, 0.4, 0, 1 },
    Poison = { 0, 0.6, 0, 1 },
}

local function GetDispelColor(dispelType)
    if dispelType and DISPEL_COLORS[dispelType] then
        local c = DISPEL_COLORS[dispelType]
        return c[1], c[2], c[3], c[4]
    end
    return 0.5, 0.5, 0.5, 1
end

-- Create a single aura icon
local function CreateAuraIcon(parent, index)
    -- Regular button - using OnClick handler for buff cancellation
    -- Note: SecureActionButtonTemplate's cancelaura action appears to be blocked in Midnight
    local icon = CreateFrame("Button", nil, parent)
    icon:SetFrameLevel(parent:GetFrameLevel() + 1)
    icon:EnableMouse(true)
    
    -- Register for both buttons
    icon:RegisterForClicks("AnyUp")
    
    -- Right-click handler for buff cancellation
    icon:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.isBuff and not InCombatLockdown() then
            pcall(function()
                if self.spellName and CancelSpellByName then
                    CancelSpellByName(self.spellName)
                end
            end)
        end
    end)
    
    -- Icon texture
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    -- Cooldown frame for duration spiral
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetDrawBling(false)
    icon.cooldown:SetDrawSwipe(true)
    icon.cooldown:SetReverse(true)
    icon.cooldown:SetHideCountdownNumbers(false)  -- Use Blizzard's built-in text (works with secret values)
    icon.cooldown:EnableMouse(false)  -- Allow clicks to pass through to parent
    
    -- Border frame
    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetPoint("TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    icon.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    icon.border:Hide()
    
    -- Text overlay frame
    icon.textOverlay = CreateFrame("Frame", nil, icon)
    icon.textOverlay:SetAllPoints()
    icon.textOverlay:SetFrameLevel(icon:GetFrameLevel() + 10)
    icon.textOverlay:EnableMouse(false)  -- Allow clicks to pass through to parent
    
    -- Stack count text
    icon.stackText = icon.textOverlay:CreateFontString(nil, "OVERLAY")
    icon.stackText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    icon.stackText:SetPoint("BOTTOMRIGHT", 0, 0)
    icon.stackText:SetTextColor(1, 1, 1, 1)
    icon.stackText:SetJustifyH("RIGHT")
    
    -- Duration text (no longer used - Blizzard's CooldownFrameTemplate handles it)
    icon.durationText = icon.textOverlay:CreateFontString(nil, "OVERLAY")
    icon.durationText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    icon.durationText:SetPoint("CENTER", 0, 0)
    icon.durationText:SetTextColor(1, 1, 1, 1)
    icon.durationText:SetJustifyH("CENTER")
    icon.durationText:Hide()  -- Blizzard's cooldown handles duration text now
    
    icon.index = index
    icon.auraInstanceID = nil
    icon.showDurationText = false
    
    -- Duration text is now handled by Blizzard's CooldownFrameTemplate
    -- with SetHideCountdownNumbers(false) - works with secret values and abbreviates times
    -- No OnUpdate needed for duration text
    
    -- Tooltip support
    icon:SetScript("OnEnter", function(self)
        if self.auraInstanceID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(function()
                if self.isBuff then
                    if GameTooltip.SetUnitBuffByAuraInstanceID then
                        GameTooltip:SetUnitBuffByAuraInstanceID("player", self.auraInstanceID)
                    else
                        GameTooltip:SetUnitAura("player", self.auraInstanceID)
                    end
                else
                    if GameTooltip.SetUnitDebuffByAuraInstanceID then
                        GameTooltip:SetUnitDebuffByAuraInstanceID("player", self.auraInstanceID)
                    else
                        GameTooltip:SetUnitAura("player", self.auraInstanceID)
                    end
                end
            end)
            GameTooltip:Show()
        end
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    icon:Hide()
    return icon
end

-- Create aura container frame (for buffs or debuffs)
local function CreateAuraContainer(containerType)
    local cfg = settings[containerType]
    if not cfg then return nil end
    
    local frameName = "TUICD_PersonalResources_" .. containerType
    local frame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    frame:SetSize(200, 100)  -- Will be resized by layout
    local anchor = cfg.anchor or "CENTER"
    local posX = cfg.positionX or 0
    local posY = cfg.positionY or 0
    frame:SetPoint(anchor, UIParent, anchor, posX, posY)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(15)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:SetClampedToScreen(true)
    
    frame.containerType = containerType
    frame.icons = {}
    
    -- Create icon pool (max 32 icons)
    for i = 1, 32 do
        local icon = CreateAuraIcon(frame, i)
        icon.isBuff = (containerType == "buffs")
        frame.icons[i] = icon
    end
    
    frame:Hide()
    return frame
end

-- Parse row pattern string to table
local function ParseRowPattern(patternStr)
    local pattern = {}
    for num in string.gmatch(patternStr or "4,4,4,4", "%d+") do
        table.insert(pattern, tonumber(num))
    end
    if #pattern == 0 then pattern = {4, 4, 4, 4} end
    return pattern
end

-- Compute grid from icons and pattern (CMT-style)
local function ComputeAuraGrid(numIcons, pattern)
    local grid = {}
    local idx = 1
    for _, rowSize in ipairs(pattern) do
        local row = {}
        for _ = 1, rowSize do
            if idx <= numIcons then
                table.insert(row, idx)
                idx = idx + 1
            end
        end
        if #row > 0 then table.insert(grid, row) end
    end
    return grid
end

-- Get max row width for alignment
local function GetMaxRowWidth(grid, iconSize, spacing)
    local maxW = 0
    for _, row in ipairs(grid) do
        local w = (#row * iconSize) + ((#row - 1) * spacing)
        if w > maxW then maxW = w end
    end
    return maxW
end

-- Apply texture zoom to icon
local function ApplyIconZoom(icon, zoomLevel)
    if not icon or not icon.texture then return end
    if zoomLevel and zoomLevel > 1.0 then
        local visibleSize = 1.0 / zoomLevel
        local offset = (1.0 - visibleSize) / 2.0
        icon.texture:SetTexCoord(offset, offset + visibleSize, offset, offset + visibleSize)
    else
        icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Layout auras using standard grid
local function LayoutAurasStandard(container, cfg, numAuras)
    if not container or not cfg then return end
    
    local size = cfg.size or 28
    local spacing = cfg.spacing or 3
    local wrapAfter = cfg.wrapAfter or 8
    local growDir = cfg.growDirection or "RIGHT"
    local wrapDir = cfg.wrapDirection or "DOWN"
    local hAlign = cfg.horizontalAlign or "CENTER"
    local vAlign = cfg.verticalAlign or "TOP"
    local scale = cfg.scale or 1.0
    local zoom = cfg.zoom or 1.0
    local maxAuras = cfg.maxAuras or 16
    
    -- Calculate container size based on MAX auras, not current count
    -- This keeps the frame from moving around as auras come and go
    local maxCols = math.min(maxAuras, wrapAfter)
    local maxRows = math.ceil(maxAuras / wrapAfter)
    local containerWidth = (maxCols * size) + ((maxCols - 1) * spacing)
    local containerHeight = (maxRows * size) + ((maxRows - 1) * spacing)
    container:SetSize(containerWidth * scale, containerHeight * scale)
    
    -- Calculate alignment base offsets
    -- These shift all icons within the container based on alignment
    local alignOffsetX, alignOffsetY = 0, 0
    
    -- Horizontal alignment affects X positioning
    if hAlign == "LEFT" then
        alignOffsetX = 0
    elseif hAlign == "CENTER" then
        alignOffsetX = containerWidth / 2
    elseif hAlign == "RIGHT" then
        alignOffsetX = containerWidth
    end
    
    -- Vertical alignment affects Y positioning
    if vAlign == "TOP" then
        alignOffsetY = 0
    elseif vAlign == "MIDDLE" then
        alignOffsetY = -containerHeight / 2
    elseif vAlign == "BOTTOM" then
        alignOffsetY = -containerHeight
    end
    
    for i, icon in ipairs(container.icons) do
        if i <= maxAuras then
            icon:SetSize(size, size)
            icon:SetScale(scale)
            icon:ClearAllPoints()
            
            local row = math.floor((i - 1) / wrapAfter)
            local col = (i - 1) % wrapAfter
            
            -- Calculate icon position within the grid
            local gridX, gridY = 0, 0
            
            if growDir == "RIGHT" then
                gridX = col * (size + spacing)
            elseif growDir == "LEFT" then
                gridX = (maxCols - 1 - col) * (size + spacing)
            elseif growDir == "UP" then
                gridY = col * (size + spacing)
            elseif growDir == "DOWN" then
                gridY = -col * (size + spacing)
            end
            
            if wrapDir == "DOWN" then
                gridY = gridY - (row * (size + spacing))
            elseif wrapDir == "UP" then
                gridY = gridY + (row * (size + spacing))
            elseif wrapDir == "LEFT" then
                gridX = gridX - (row * (size + spacing))
            elseif wrapDir == "RIGHT" then
                gridX = gridX + (row * (size + spacing))
            end
            
            -- Apply alignment - position relative to alignment anchor
            local xOffset, yOffset
            
            if hAlign == "LEFT" then
                xOffset = gridX
            elseif hAlign == "CENTER" then
                xOffset = gridX - (containerWidth / 2) + (size / 2)
            elseif hAlign == "RIGHT" then
                xOffset = gridX - containerWidth + size
            else
                xOffset = gridX
            end
            
            if vAlign == "TOP" then
                yOffset = gridY
            elseif vAlign == "MIDDLE" then
                yOffset = gridY + (containerHeight / 2) - (size / 2)
            elseif vAlign == "BOTTOM" then
                yOffset = gridY + containerHeight - size
            else
                yOffset = gridY
            end
            
            -- Determine anchor point based on alignment
            local anchor = "TOPLEFT"
            if hAlign == "CENTER" then
                if vAlign == "TOP" then anchor = "TOP"
                elseif vAlign == "MIDDLE" then anchor = "CENTER"
                elseif vAlign == "BOTTOM" then anchor = "BOTTOM"
                end
            elseif hAlign == "RIGHT" then
                if vAlign == "TOP" then anchor = "TOPRIGHT"
                elseif vAlign == "MIDDLE" then anchor = "RIGHT"
                elseif vAlign == "BOTTOM" then anchor = "BOTTOMRIGHT"
                end
            else -- LEFT
                if vAlign == "TOP" then anchor = "TOPLEFT"
                elseif vAlign == "MIDDLE" then anchor = "LEFT"
                elseif vAlign == "BOTTOM" then anchor = "BOTTOMLEFT"
                end
            end
            
            icon:SetPoint(anchor, container, anchor, xOffset, yOffset)
            ApplyIconZoom(icon, zoom)
            
            -- Update text sizes
            icon.stackText:SetFont(STANDARD_TEXT_FONT, cfg.stackFontSize or 10, "OUTLINE")
            icon.stackText:ClearAllPoints()
            icon.stackText:SetPoint(cfg.stackPosition or "BOTTOMRIGHT", 0, 0)
            
            -- Duration text is handled by Blizzard's CooldownFrameTemplate now
            if icon.durationText then
                icon.durationText:Hide()
            end
        end
    end
end

-- Layout auras using custom CMT-style row pattern
local function LayoutAurasCustom(container, cfg, numAuras)
    if not container or not cfg then return end
    
    local pattern = ParseRowPattern(cfg.rowPattern)
    local size = cfg.size or 28
    local hSpacing = cfg.compactMode and cfg.compactOffset or cfg.hSpacing or 3
    local vSpacing = cfg.compactMode and cfg.compactOffset or cfg.vSpacing or 3
    local align = cfg.alignment or "CENTER"
    local scale = cfg.scale or 1.0
    local zoom = cfg.zoom or 1.0
    local reverseOrder = cfg.reverseOrder
    local maxAuras = cfg.maxAuras or 16
    
    local effectiveCount = math.min(numAuras, maxAuras)
    
    -- Calculate container size based on MAX auras, not current count
    -- This keeps the frame from moving around as auras come and go
    local maxGrid = ComputeAuraGrid(maxAuras, pattern)
    local maxW = GetMaxRowWidth(maxGrid, size, hSpacing)
    local maxTotalHeight = (#maxGrid * size) + ((#maxGrid - 1) * vSpacing)
    container:SetSize(maxW * scale, maxTotalHeight * scale)
    
    -- Compute actual grid for positioning current auras
    local grid = ComputeAuraGrid(effectiveCount, pattern)
    
    -- Build icon index order (optionally reversed)
    local iconIndices = {}
    for i = 1, effectiveCount do iconIndices[i] = i end
    if reverseOrder then
        local reversed = {}
        for i = #iconIndices, 1, -1 do table.insert(reversed, iconIndices[i]) end
        iconIndices = reversed
    end
    
    -- Position icons
    local iconIdx = 1
    local y = 0
    for rowIdx, row in ipairs(grid) do
        local rowW = (#row * size) + ((#row - 1) * hSpacing)
        local x0 = 0
        if align == "CENTER" then x0 = (maxW - rowW) / 2
        elseif align == "RIGHT" then x0 = maxW - rowW end
        
        for colIdx, _ in ipairs(row) do
            if iconIdx <= #iconIndices then
                local iconI = iconIndices[iconIdx]
                local icon = container.icons[iconI]
                if icon then
                    icon:SetSize(size, size)
                    icon:SetScale(scale)
                    icon:ClearAllPoints()
                    
                    local x = x0 + ((colIdx - 1) * (size + hSpacing))
                    icon:SetPoint("TOPLEFT", container, "TOPLEFT", x, -y)
                    ApplyIconZoom(icon, zoom)
                    
                    -- Update text sizes
                    icon.stackText:SetFont(STANDARD_TEXT_FONT, cfg.stackFontSize or 10, "OUTLINE")
                    icon.stackText:ClearAllPoints()
                    icon.stackText:SetPoint(cfg.stackPosition or "BOTTOMRIGHT", 0, 0)
                    
                    -- Duration text is handled by Blizzard's CooldownFrameTemplate now
                    if icon.durationText then
                        icon.durationText:Hide()
                    end
                end
                iconIdx = iconIdx + 1
            end
        end
        y = y + size + vSpacing
    end
end

-- Check if buffs should be shown
local function ShouldShowBuffs()
    if not settings or not settings.buffs or not settings.buffs.enabled then return false end
    return CheckVisibilityConditions(settings.buffs)
end

-- Check if debuffs should be shown
local function ShouldShowDebuffs()
    if not settings or not settings.debuffs or not settings.debuffs.enabled then return false end
    return CheckVisibilityConditions(settings.debuffs)
end

-- Update aura container with actual aura data
local function UpdateAuraContainer(container, cfg, isBuff)
    if not container or not cfg or not cfg.enabled then
        if container then container:Hide() end
        return
    end
    
    -- Check visibility conditions
    local shouldShow = isBuff and ShouldShowBuffs() or ShouldShowDebuffs()
    if not shouldShow then
        container:Hide()
        return
    end
    
    container:Show()
    
    local maxAuras = cfg.maxAuras or 16
    local filter = isBuff and "HELPFUL" or "HARMFUL"
    
    -- Hide all icons first
    for i, icon in ipairs(container.icons) do
        icon:Hide()
        icon.auraInstanceID = nil
        icon.spellName = nil
        icon.showDurationText = false
        icon.expirationTime = 0
        icon.durationText:Hide()
    end
    
    -- Get real aura data using the most reliable method
    local auras = {}
    
    -- Primary method: Iterate through aura indices (most reliable in Midnight)
    -- This loops through all possible indices regardless of "holes"
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local success, aura = pcall(function()
                return C_UnitAuras.GetAuraDataByIndex("player", i, filter)
            end)
            if success and aura then
                aura.auraIndex = i  -- Store the original index for cancelaura
                table.insert(auras, aura)
            end
            -- Don't break early - there might be gaps in indices
        end
    end
    
    -- Fallback: use C_UnitAuras.GetUnitAuras
    if #auras == 0 and C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local success, auraList = pcall(function()
            return C_UnitAuras.GetUnitAuras("player", filter)
        end)
        if success and auraList then
            for _, auraData in ipairs(auraList) do
                if auraData then
                    table.insert(auras, auraData)
                end
            end
        end
    end
    
    -- Final fallback: use AuraUtil.ForEachAura
    if #auras == 0 and AuraUtil and AuraUtil.ForEachAura then
        pcall(function()
            AuraUtil.ForEachAura("player", filter, 40, function(aura)
                if aura then
                    table.insert(auras, aura)
                end
                return false  -- Continue iterating
            end, true)
        end)
    end
    
    -- Limit to maxAuras for display
    while #auras > maxAuras do
        table.remove(auras)
    end
    
    local hidePermanent = cfg.hidePermanent
    
    -- Layout icons based on mode
    if cfg.layoutMode == "custom" then
        LayoutAurasCustom(container, cfg, #auras)
    else
        LayoutAurasStandard(container, cfg, #auras)
    end
    
    -- Update icons with aura data
    for i, auraData in ipairs(auras) do
        if i > maxAuras then break end
        
        local icon = container.icons[i]
        if icon and auraData then
            icon.auraInstanceID = auraData.auraInstanceID
            
            -- Store spell name on icon for right-click cancel
            if isBuff then
                pcall(function()
                    icon.spellName = auraData.name
                end)
            end
            
            -- Hide permanent auras using SetAlphaFromBoolean
            if hidePermanent and auraData.auraInstanceID and C_UnitAuras.DoesAuraHaveExpirationTime then
                pcall(function()
                    local hasExpiration = C_UnitAuras.DoesAuraHaveExpirationTime("player", auraData.auraInstanceID)
                    if icon.SetAlphaFromBoolean then
                        icon:SetAlphaFromBoolean(hasExpiration, 1.0, 0.0)
                    end
                end)
            else
                icon:SetAlpha(1.0)
            end
            
            -- Icon texture
            if auraData.icon then
                icon.texture:SetTexture(auraData.icon)
                icon.texture:SetVertexColor(1, 1, 1, 1)
            end
            
            -- Duration/cooldown spiral
            if cfg.showDuration then
                local cooldownSet = false
                
                -- Use TUICD.API compatibility layer for setting cooldown from aura
                if auraData.auraInstanceID then
                    cooldownSet = TUICD.API.SetCooldownFromAura(icon.cooldown, "player", auraData.auraInstanceID)
                    if cooldownSet then
                        icon.cooldown:Show()
                    end
                end
                
                -- Fallback: Traditional SetCooldown using aura data directly
                if not cooldownSet and auraData.expirationTime and auraData.duration and auraData.duration > 0 then
                    local startTime = auraData.expirationTime - auraData.duration
                    icon.cooldown:SetCooldown(startTime, auraData.duration)
                    icon.cooldown:Show()
                    cooldownSet = true
                end
                
                if not cooldownSet then icon.cooldown:Hide() end
            else
                icon.cooldown:Hide()
            end
            
            -- Duration text is now handled by Blizzard's CooldownFrameTemplate
            -- with SetHideCountdownNumbers(false) - works with secret values and abbreviates times
            if icon.durationText then
                icon.durationText:Hide()
            end
            
            -- Stack count (only show if count > 1)
            -- In Midnight, GetAuraApplicationDisplayCount returns empty string if count < minBound (2)
            -- The returned value is secret, so we can't compare it - just set it directly
            if cfg.showStacks then
                local stackShown = false
                if auraData.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                    pcall(function()
                        -- minBound of 2 means empty string returned for counts 0 or 1
                        local countText = C_UnitAuras.GetAuraApplicationDisplayCount("player", auraData.auraInstanceID, 2)
                        -- Set text directly - countText may be secret, empty strings display nothing
                        icon.stackText:SetText(countText or "")
                        icon.stackText:Show()
                        stackShown = true
                    end)
                end
                -- Fallback: try direct applications (wrapped in pcall for secret comparison)
                if not stackShown and auraData.applications then
                    pcall(function()
                        if auraData.applications > 1 then
                            icon.stackText:SetText(tostring(auraData.applications))
                            icon.stackText:Show()
                            stackShown = true
                        end
                    end)
                end
                if not stackShown then icon.stackText:Hide() end
            else
                icon.stackText:Hide()
            end
            
            -- Dispel type coloring for debuffs
            local dispelColorApplied = false
            if not isBuff and cfg.colorByDispelType then
                pcall(function()
                    if auraData.dispelName then
                        local r, g, b, a = GetDispelColor(auraData.dispelName)
                        if cfg.dispelBorderOnly then
                            icon.border:SetVertexColor(r, g, b, a)
                            icon.border:Show()
                        else
                            icon.texture:SetVertexColor(r, g, b, 1)
                        end
                        dispelColorApplied = true
                    end
                end)
            end
            
            if not dispelColorApplied then
                if cfg.showBorder then
                    icon.border:SetVertexColor(unpack(cfg.borderColor or { 0, 0, 0, 1 }))
                    icon.border:Show()
                else
                    icon.border:Hide()
                end
            end
            
            icon:Show()
        end
    end
end

-- Create buffs frame
local function CreateBuffsFrame()
    if buffsFrame then return buffsFrame end
    buffsFrame = CreateAuraContainer("buffs")
    return buffsFrame
end

-- Create debuffs frame
local function CreateDebuffsFrame()
    if debuffsFrame then return debuffsFrame end
    debuffsFrame = CreateAuraContainer("debuffs")
    return debuffsFrame
end

-- Refresh buffs layout
local function RefreshBuffsLayout()
    if not buffsFrame then CreateBuffsFrame() end
    if not buffsFrame then return end
    
    local cfg = settings.buffs
    if not layoutWrappers["buffs"] then
        buffsFrame:ClearAllPoints()
        local anchor = cfg.anchor or "CENTER"
        local posX = cfg.positionX or 0
        local posY = cfg.positionY or 0
        buffsFrame:SetPoint(anchor, UIParent, anchor, posX, posY)
    else
        -- Update wrapper size to match container (will be resized again in UpdateBuffs)
        local w, h = buffsFrame:GetSize()
        if w > 0 and h > 0 then
            layoutWrappers["buffs"]:SetSize(w, h)
        end
    end
end

-- Refresh debuffs layout
local function RefreshDebuffsLayout()
    if not debuffsFrame then CreateDebuffsFrame() end
    if not debuffsFrame then return end
    
    local cfg = settings.debuffs
    if not layoutWrappers["debuffs"] then
        debuffsFrame:ClearAllPoints()
        local anchor = cfg.anchor or "CENTER"
        local posX = cfg.positionX or 0
        local posY = cfg.positionY or 0
        debuffsFrame:SetPoint(anchor, UIParent, anchor, posX, posY)
    else
        -- Update wrapper size to match container (will be resized again in UpdateDebuffs)
        local w, h = debuffsFrame:GetSize()
        if w > 0 and h > 0 then
            layoutWrappers["debuffs"]:SetSize(w, h)
        end
    end
end

-- Update buffs display
local function UpdateBuffs()
    if not buffsFrame then CreateBuffsFrame() end
    if not buffsFrame then return end
    UpdateAuraContainer(buffsFrame, settings.buffs, true)
    -- Update wrapper size after layout
    if layoutWrappers["buffs"] then
        local w, h = buffsFrame:GetSize()
        if w > 0 and h > 0 then
            layoutWrappers["buffs"]:SetSize(w, h)
        end
    end
end

-- Update debuffs display
local function UpdateDebuffs()
    if not debuffsFrame then CreateDebuffsFrame() end
    if not debuffsFrame then return end
    UpdateAuraContainer(debuffsFrame, settings.debuffs, false)
    -- Update wrapper size after layout
    if layoutWrappers["debuffs"] then
        local w, h = debuffsFrame:GetSize()
        if w > 0 and h > 0 then
            layoutWrappers["debuffs"]:SetSize(w, h)
        end
    end
end

local function RefreshAllBars()
    RefreshHealthBarLayout()
    RefreshPowerBarLayout()
    RefreshClassPowerLayout()
    RefreshSoulFragmentDisplay()
    RefreshBuffsLayout()
    RefreshDebuffsLayout()
    UpdateHealthBar()
    UpdateAbsorbOverlay()
    UpdatePowerBar()
    UpdateClassPower()
    UpdateSoulFragments()
    UpdateBuffs()
    UpdateDebuffs()
end

-- Module-level wrapper for external calls
function PersonalResources:RefreshAllBars()
    RefreshAllBars()
end

-- Refresh from database settings (used when presets are applied)
function PersonalResources:RefreshFromDatabase()
    -- Clear cached settings
    settings = nil
    
    -- Re-load settings from database
    settings = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.PERSONAL_RESOURCES)
    if not settings then
        settings = DeepCopy(DEFAULT_SETTINGS)
    end
    EnsureDefaults(settings, DEFAULT_SETTINGS)
    
    -- Refresh all bars
    RefreshAllBars()
    
    -- Update Blizzard bar visibility
    if settings.global and settings.global.hideBlizzardBars then
        HideBlizzardResourceFrames()
    else
        ShowBlizzardResourceFrames()
    end
    
    if TUICD.PrintDebug then
        TUICD:PrintDebug("PersonalResources: Refreshed settings from database")
    end
    
    return true
end

local function OnEvent(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        GetPlayerInfo()
        GetPrimaryResourceValues()
        GetSecondaryResourceValues()
        C_Timer.After(0.5, function()
            if settings and settings.enabled then
                HideBlizzardResourceFrames()
                RefreshAllBars()
                if playerClass == "DEATHKNIGHT" then StartRuneUpdateTicker() end
                if playerClass == "DEMONHUNTER" then 
                    StartSoulFragmentTicker()  -- Will only start if Vengeance
                    StartVoidMetamorphosisTicker()  -- Will only start if Devourer
                end
                if playerClass == "MONK" then StartStaggerUpdateTicker() end
                if playerClass == "SHAMAN" then StartMaelstromWeaponTicker() end
            end
        end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        GetPlayerInfo()
        GetPrimaryResourceValues()
        GetSecondaryResourceValues()
        RefreshAllBars()
        StopRuneUpdateTicker()
        StopSoulFragmentTicker()
        StopVoidMetamorphosisTicker()
        StopStaggerUpdateTicker()
        StopMaelstromWeaponTicker()
        if playerClass == "DEATHKNIGHT" then StartRuneUpdateTicker() end
        if playerClass == "DEMONHUNTER" then 
            StartSoulFragmentTicker()  -- Will only start if Vengeance
            StartVoidMetamorphosisTicker()  -- Will only start if Devourer
        end
        if playerClass == "MONK" then StartStaggerUpdateTicker() end
        if playerClass == "SHAMAN" then StartMaelstromWeaponTicker() end
    elseif event == "TRAIT_CONFIG_UPDATED" then
        -- Talent changed - refresh resources
        if playerClass == "DEMONHUNTER" then
            GetSecondaryResourceValues()
            RefreshAllBars()
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        GetSecondaryResourceValues()
        RefreshAllBars()
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        if ... == "player" then
            UpdatePowerBar()
            -- DK uses rune ticker, DH uses soul fragment or void meta ticker, Monk BrM uses stagger ticker,
            -- Enhancement Shaman uses maelstrom weapon ticker (aura-based)
            local secondaryRes = GetSecondaryResource()
            local usesTickerUpdate = (
                playerClass == "DEATHKNIGHT" or 
                playerClass == "DEMONHUNTER" or
                (playerClass == "MONK" and secondaryRes == SPECIAL_RESOURCES.STAGGER) or
                (playerClass == "SHAMAN" and secondaryRes == SPECIAL_RESOURCES.MAELSTROM_WEAPON)
            )
            if not usesTickerUpdate then 
                UpdateClassPower()
            end
        end
    elseif event == "UNIT_MAXPOWER" then
        if ... == "player" then
            GetPrimaryResourceValues()
            GetSecondaryResourceValues()
            RefreshAllBars()
        end
    elseif event == "UNIT_MAXHEALTH" then
        if ... == "player" then
            UpdateHealthBar()
        end
    elseif event == "UNIT_HEALTH" then
        if ... == "player" then
            -- Update health bar
            UpdateHealthBar()
            UpdateAbsorbOverlay()
            -- Stagger is based on health percentage, so update on health changes too
            if playerClass == "MONK" then
                UpdateClassPower()
            end
        end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        if ... == "player" then
            UpdateAbsorbOverlay()
        end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        UpdateHealthBar()
        UpdateAbsorbOverlay()
        UpdatePowerBar()
        UpdateClassPower()
        UpdateBuffs()
        UpdateDebuffs()
    elseif event == "RUNE_POWER_UPDATE" then
        if playerClass == "DEATHKNIGHT" then UpdateClassPower() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        UpdateHealthBar()
        UpdateAbsorbOverlay()
        UpdatePowerBar()
        UpdateClassPower()
        UpdateBuffs()
        UpdateDebuffs()
    elseif event == "UNIT_AURA" then
        local unit, updateInfo = ...
        if unit == "player" then
            UpdateBuffs()
            UpdateDebuffs()
            -- Enhancement Shaman: Maelstrom Weapon is an aura-based resource
            -- Update class power when auras change (ticker handles continuous updates)
            if playerClass == "SHAMAN" and GetSecondaryResource() == SPECIAL_RESOURCES.MAELSTROM_WEAPON then
                UpdateMaelstromWeaponStacks()
                UpdateClassPower()
            end
        end
    end
end

local function RegisterEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    end
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")  -- Hero talent changes
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    eventFrame:RegisterEvent("UNIT_POWER_FREQUENT")
    eventFrame:RegisterEvent("UNIT_MAXPOWER")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("UNIT_AURA")
end

local function UnregisterEvents()
    if eventFrame then eventFrame:UnregisterAllEvents() end
end

-- Preview Window
-- ============================================================================
-- TEST MODE - Shows all enabled displays with simulated data
-- ============================================================================

-- Settings UI Hub
function PersonalResources:ShowHub(parentPanel)
    -- Close other module panels when opening Personal Resources
    if TUICD.Cooldowns and TUICD.Cooldowns.HideTrackerPanels then
        TUICD.Cooldowns:HideTrackerPanels()
    end
    if TUICD.DocksUI then TUICD.DocksUI:Hide() end
    if TUICD.MultiTrackerUI and TUICD.MultiTrackerUI.HideAllPanels then
        TUICD.MultiTrackerUI:HideAllPanels()
    end
    
    if personalResourcesHub then
        personalResourcesHub:ClearAllPoints()
        personalResourcesHub:SetPoint("TOPLEFT", parentPanel, "TOPRIGHT", 0, 0)
        personalResourcesHub:Show()
        return
    end
    
    local hub = CreateFrame("Frame", "TUICD_PersonalResources_Hub", UIParent, "BackdropTemplate")
    hub:SetSize(HUB_WIDTH, HUB_HEIGHT + 50)  -- Increased height for preset dropdown
    hub:SetPoint("TOPLEFT", parentPanel, "TOPRIGHT", 0, 0)
    hub:SetBackdrop(darkBackdrop)
    hub:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    hub:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    hub:SetFrameStrata("DIALOG")
    hub:SetMovable(true)
    hub:EnableMouse(true)
    hub:SetClampedToScreen(true)
    personalResourcesHub = hub
    
    local title = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Resource Bars")
    title:SetTextColor(1, 0.82, 0)
    
    local closeBtn = CreateFrame("Button", nil, hub, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)
    closeBtn:SetScript("OnClick", function() self:HideAllPanels() end)
    
    hub:SetScript("OnHide", function()
        for _, p in pairs(settingsPanels) do if p and p.Hide then p:Hide() end end
        currentOpenPanel = nil
    end)
    
    hub:RegisterForDrag("LeftButton")
    hub:SetScript("OnDragStart", hub.StartMoving)
    hub:SetScript("OnDragStop", hub.StopMovingOrSizing)
    
    local yOff = -38
    local bw = HUB_WIDTH - 20
    
    -- Enable Module Checkbox
    local enableCb = CreateFrame("CheckButton", nil, hub, "UICheckButtonTemplate")
    enableCb:SetPoint("TOPLEFT", 10, yOff)
    enableCb:SetSize(24, 24)
    enableCb:SetChecked(TUICD.Database:IsModuleEnabled(TUICD.MODULE_IDS.PERSONAL_RESOURCES))
    
    local enableLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableLabel:SetPoint("LEFT", enableCb, "RIGHT", 4, 0)
    enableLabel:SetText("Enable Module")
    
    enableCb:SetScript("OnClick", function(self)
        local enabled = self:GetChecked()
        TUICD.Database:SetModuleEnabled(TUICD.MODULE_IDS.PERSONAL_RESOURCES, enabled, true)
        if enabled then
            PersonalResources:OnEnable()
            TUICD:Print("Personal Resources |cff00ff00enabled|r - bars will appear based on visibility settings")
        else
            PersonalResources:OnDisable()
            TUICD:Print("Personal Resources |cffff0000disabled|r")
        end
    end)
    yOff = yOff - 30
    
    -- Add Preset Dropdown
    if TUICD.PresetDropdown then
        local presetContainer, nextY = TUICD.PresetDropdown:Create(
            hub,
            "personalResources",
            "Personal Resources",
            yOff,
            {
                width = 120,
                showSaveButton = true,
                showDeleteButton = true,
            }
        )
        yOff = nextY - 8
    end
    
    local sl = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sl:SetPoint("TOP", 0, yOff)
    sl:SetText("|cff888888Settings|r")
    yOff = yOff - 16
    
    local buttons = { 
        {id="general",name="General"}, 
        {id="healthbar",name="Health Bar"},
        {id="powerbar",name="Power Bar"}, 
        {id="classpower",name="Class Power"}, 
        {id="buffs",name="Player Buffs"},
        {id="debuffs",name="Player Debuffs"},
        {id="visibility",name="Visibility"} 
    }
    
    -- Add Stagger button for Brewmaster Monks
    if playerClass == "MONK" and GetSecondaryResource() == SPECIAL_RESOURCES.STAGGER then
        table.insert(buttons, {id="stagger",name="Stagger"})
    end
    
    for _, cat in ipairs(buttons) do
        local btn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
        btn:SetSize(bw, BUTTON_HEIGHT)
        btn:SetPoint("TOP", 0, yOff)
        btn:SetText(cat.name)
        btn:SetScript("OnClick", function() self:TogglePanel(cat.id) end)
        yOff = yOff - BUTTON_HEIGHT - BUTTON_SPACING
    end
    
    yOff = yOff - 8
    local sep = hub:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOP", 0, yOff)
    sep:SetSize(bw, 1)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    yOff = yOff - 12
    
    hub:Show()
end

function PersonalResources:HideAllPanels()
    if personalResourcesHub then personalResourcesHub:Hide() end
    for _, p in pairs(settingsPanels) do if p and p.Hide then p:Hide() end end
    currentOpenPanel = nil
end

-- Wrapper for TUI:CD Settings integration
function PersonalResources:ToggleSettingsPanel(parentPanel)
    if personalResourcesHub and personalResourcesHub:IsShown() then
        self:HideAllPanels()
    else
        -- Close other module hubs when opening Personal Resources
        if TUICD.Cooldowns and TUICD.Cooldowns.HideAllPanels then
            TUICD.Cooldowns:HideAllPanels()
        end
        if TUICD.MultiTrackerUI and TUICD.MultiTrackerUI.HideAllPanels then
            TUICD.MultiTrackerUI:HideAllPanels()
        end
        
        self:ShowHub(parentPanel)
    end
end

local function CreateSettingsPanel(panelId, panelTitle, createContent)
    local panel = CreateFrame("Frame", "TUICD_PersonalResources_" .. panelId, UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:Hide()
    
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", 0, -12)
    t:SetText(panelTitle)
    t:SetTextColor(1, 0.82, 0)
    
    local cb = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    cb:SetPoint("TOPRIGHT", -3, -3)
    cb:SetScript("OnClick", function() panel:Hide() end)
    
    local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -40)
    sf:SetPoint("BOTTOMRIGHT", -30, 12)
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(PANEL_WIDTH - 50, 800)
    sf:SetScrollChild(sc)
    panel.scrollChild = sc
    
    if createContent then createContent(sc) end
    settingsPanels[panelId] = panel
    return panel
end

-- Tabbed settings panel for Class Power (with optional Soul Fragments tab for DH)
local function CreateTabbedSettingsPanel(panelId, panelTitle, tabs)
    local panel = CreateFrame("Frame", "TUICD_PersonalResources_" .. panelId, UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:Hide()
    
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", 0, -12)
    t:SetText(panelTitle)
    t:SetTextColor(1, 0.82, 0)
    
    local cb = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    cb:SetPoint("TOPRIGHT", -3, -3)
    cb:SetScript("OnClick", function() panel:Hide() end)
    
    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT", 12, -35)
    tabBar:SetPoint("TOPRIGHT", -12, -35)
    tabBar:SetHeight(24)
    
    local tabButtons = {}
    local tabContents = {}
    local activeTab = nil
    
    local function SelectTab(tabKey)
        for key, btn in pairs(tabButtons) do
            if key == tabKey then
                btn:GetFontString():SetTextColor(1, 0.82, 0)  -- Gold active
                btn.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            else
                btn:GetFontString():SetTextColor(0.6, 0.6, 0.6)  -- Grey inactive
                btn.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
            end
        end
        for key, content in pairs(tabContents) do
            content.scrollFrame:SetShown(key == tabKey)
        end
        activeTab = tabKey
    end
    
    local xOffset = 0
    for i, tab in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetHeight(22)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        btn.bg = bg
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER")
        text:SetText(tab.label)
        btn:SetFontString(text)
        btn:SetWidth(text:GetStringWidth() + 24)
        
        btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
        
        btn:SetScript("OnClick", function()
            SelectTab(tab.key)
        end)
        btn:SetScript("OnEnter", function(self)
            if activeTab ~= tab.key then
                self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.7)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if activeTab ~= tab.key then
                self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
            end
        end)
        
        tabButtons[tab.key] = btn
        xOffset = xOffset + btn:GetWidth() + 4
        
        -- Create scroll frame for this tab's content
        local sf = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -62)
        sf:SetPoint("BOTTOMRIGHT", -30, 12)
        sf:Hide()
        
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetSize(PANEL_WIDTH - 50, 800)
        sf:SetScrollChild(sc)
        
        tabContents[tab.key] = { scrollFrame = sf, scrollChild = sc }
        
        -- Call tab builder
        if tab.builder then
            tab.builder(sc)
        end
    end
    
    -- Select first tab
    SelectTab(tabs[1].key)
    
    settingsPanels[panelId] = panel
    return panel
end

function PersonalResources:TogglePanel(panelId)
    if currentOpenPanel and currentOpenPanel ~= panelId and settingsPanels[currentOpenPanel] then
        settingsPanels[currentOpenPanel]:Hide()
    end
    if not settingsPanels[panelId] then self:CreatePanel(panelId) end
    local panel = settingsPanels[panelId]
    if not panel then return end
    if panel:IsShown() then
        panel:Hide()
        currentOpenPanel = nil
    else
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", personalResourcesHub, "TOPRIGHT", 0, 0)
        panel:Show()
        currentOpenPanel = panelId
    end
end

local function CreateCheckbox(parent, x, y, label, getFunc, setFunc)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(24, 24)
    cb:SetChecked(getFunc())
    local txt = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    txt:SetText(label)
    cb:SetScript("OnClick", function(self) setFunc(self:GetChecked()) PersonalResources:SaveSettings() RefreshAllBars() end)
    return y - 26
end

local function CreateSlider(parent, x, y, label, min, max, step, getFunc, setFunc)
    local isFloat = step < 1
    local decimals = 0
    if isFloat then
        local stepStr = tostring(step)
        local _, decPart = stepStr:match("(%d+)%.?(%d*)")
        decimals = decPart and #decPart or 2
    end
    
    -- Use centralized slider with input
    local container = TUICD.Utilities:CreateSliderWithInput(parent, {
        label = label .. ":",
        min = min,
        max = max,
        step = step,
        value = getFunc(),
        isFloat = isFloat,
        decimals = decimals,
        width = 140,
        labelWidth = 120,
        valueWidth = 45,
        onValueChanged = function(value)
            setFunc(value)
            RefreshAllBars()
        end,
    })
    container:SetPoint("TOPLEFT", x, y)
    
    return y - 30
end

local function CreateColorPicker(parent, x, y, label, color)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x + 28, y)
    lbl:SetText(label)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetPoint("TOPLEFT", x, y - 4)
    btn:SetSize(22, 22)
    btn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
    btn:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    -- Store color reference on button for external updates
    btn.colorRef = color
    btn.UpdateColor = function(self)
        local c = self.colorRef
        self:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    end
    btn:SetScript("OnClick", function()
        local r, g, b, a = color[1], color[2], color[3], color[4] or 1
        
        -- Modern ColorPicker API (Dragonflight+)
        local info = {
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = 1 - (ColorPickerFrame:GetColorAlpha() or 0)
                color[1], color[2], color[3], color[4] = nr, ng, nb, na
                btn:SetBackdropColor(nr, ng, nb, na)
                RefreshAllBars()
            end,
            opacityFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = 1 - (ColorPickerFrame:GetColorAlpha() or 0)
                color[1], color[2], color[3], color[4] = nr, ng, nb, na
                btn:SetBackdropColor(nr, ng, nb, na)
                RefreshAllBars()
            end,
            cancelFunc = function(prev)
                color[1], color[2], color[3], color[4] = prev.r, prev.g, prev.b, 1 - (prev.a or 0)
                btn:SetBackdropColor(prev.r, prev.g, prev.b, 1 - (prev.a or 0))
            end,
            hasOpacity = true,
            opacity = 1 - a,
            r = r,
            g = g,
            b = b,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    return y - 28, btn
end

local dropdownCounter = 0
local function CreateDropdown(parent, x, y, label, options, getFunc, setFunc)
    dropdownCounter = dropdownCounter + 1
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)
    local dd = CreateFrame("Frame", "TUICD_RB_DD_" .. dropdownCounter, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y - 18)
    UIDropDownMenu_SetWidth(dd, 150)
    local curVal = getFunc()
    local curText = curVal
    for _, o in ipairs(options) do if o.id == curVal then curText = o.name break end end
    UIDropDownMenu_SetText(dd, curText)
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, o in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value, info.checked = o.name, o.id, (getFunc() == o.id)
            info.func = function() setFunc(o.id) UIDropDownMenu_SetText(dd, o.name) RefreshAllBars() end
            UIDropDownMenu_AddButton(info)
        end
    end)
    return y - 50
end

-- Edit box for text input (like row patterns)
local function CreateEditBox(parent, x, y, label, width, getFunc, setFunc)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)
    
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", x + 4, y - 18)
    editBox:SetSize(width or 150, 20)
    editBox:SetAutoFocus(false)
    editBox:SetText(getFunc() or "")
    editBox:SetCursorPosition(0)
    
    editBox:SetScript("OnEnterPressed", function(self)
        setFunc(self:GetText())
        self:ClearFocus()
        RefreshAllBars()
    end)
    
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(getFunc() or "")
        self:ClearFocus()
    end)
    
    -- Also update on focus lost
    editBox:SetScript("OnEditFocusLost", function(self)
        local newVal = self:GetText()
        if newVal ~= getFunc() then
            setFunc(newVal)
            RefreshAllBars()
        end
    end)
    
    return y - 45
end

-- Texture dropdown using LibSharedMedia
local function CreateTextureDropdown(parent, x, y, label, getFunc, setFunc)
    dropdownCounter = dropdownCounter + 1
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)
    
    local dd = CreateFrame("Frame", "TUICD_RB_Tex_" .. dropdownCounter, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y - 18)
    UIDropDownMenu_SetWidth(dd, 150)
    UIDropDownMenu_SetText(dd, getFunc() or "Blizzard")
    
    UIDropDownMenu_Initialize(dd, function(self, level)
        local textures = TUICD.Media:GetStatusBarList()
        for _, texName in ipairs(textures) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = texName
            info.checked = (getFunc() == texName)
            info.func = function()
                setFunc(texName)
                UIDropDownMenu_SetText(dd, texName)
                RefreshAllBars()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    -- Add preview bar
    local previewBar = CreateFrame("StatusBar", nil, parent)
    previewBar:SetPoint("TOPLEFT", x + 170, y - 5)
    previewBar:SetSize(100, 14)
    previewBar:SetMinMaxValues(0, 1)
    previewBar:SetValue(0.7)
    previewBar:SetStatusBarTexture(TUICD.Media:GetStatusBarTexture(getFunc()))
    previewBar:SetStatusBarColor(0, 0.8, 0, 1)
    
    local previewBg = previewBar:CreateTexture(nil, "BACKGROUND")
    previewBg:SetAllPoints()
    previewBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    -- Update preview when dropdown changes
    local origSetFunc = setFunc
    setFunc = function(v)
        origSetFunc(v)
        previewBar:SetStatusBarTexture(TUICD.Media:GetStatusBarTexture(v))
    end
    
    return y - 50
end

-- Font dropdown using LibSharedMedia
local function CreateFontDropdown(parent, x, y, label, getFunc, setFunc)
    dropdownCounter = dropdownCounter + 1
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)
    
    local dd = CreateFrame("Frame", "TUICD_RB_Font_" .. dropdownCounter, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y - 18)
    UIDropDownMenu_SetWidth(dd, 150)
    UIDropDownMenu_SetText(dd, getFunc() or "Friz Quadrata TT")
    
    UIDropDownMenu_Initialize(dd, function(self, level)
        local fonts = TUICD.Media:GetFontList()
        for _, fontName in ipairs(fonts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = fontName
            info.checked = (getFunc() == fontName)
            info.func = function()
                setFunc(fontName)
                UIDropDownMenu_SetText(dd, fontName)
                RefreshAllBars()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    -- Add preview text
    local previewText = parent:CreateFontString(nil, "OVERLAY")
    previewText:SetPoint("TOPLEFT", x + 170, y - 5)
    previewText:SetFont(TUICD.Media:GetFont(getFunc()), 12, "OUTLINE")
    previewText:SetText("Preview 123")
    previewText:SetTextColor(1, 1, 1, 1)
    
    -- Update preview when dropdown changes
    local origSetFunc = setFunc
    setFunc = function(v)
        origSetFunc(v)
        previewText:SetFont(TUICD.Media:GetFont(v), 12, "OUTLINE")
    end
    
    return y - 50
end

local function CreateHeader(parent, x, y, text)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y)
    h:SetText("|cffffcc00" .. text .. "|r")
    return y - 20
end

local function CreateSeparator(parent, y)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 0, y)
    sep:SetSize(PANEL_WIDTH - 60, 1)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    return y - 15
end

function PersonalResources:CreatePanel(panelId)
    if panelId == "general" then
        CreateSettingsPanel("general", "General Settings", function(p)
            local y = -10
            y = CreateSlider(p, 10, y, "Global Scale", 0.25, 4, 0.05,
                function() return settings.global.scale end,
                function(v) settings.global.scale = v end)
            y = CreateCheckbox(p, 10, y, "Hide Blizzard Resource Bars",
                function() return settings.global.hideBlizzardBars end,
                function(c) settings.global.hideBlizzardBars = c if c then HideBlizzardResourceFrames() else ShowBlizzardResourceFrames() end end)
            y = CreateSeparator(p, y - 10)
            local info = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            info:SetPoint("TOPLEFT", 10, y)
            info:SetWidth(PANEL_WIDTH - 70)
            info:SetJustifyH("LEFT")
            info:SetText("|cff888888Use Blizzard's Edit Mode (ESC > Edit Mode) to reposition the resource bars.|r")
            y = y - 40
            local rb = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            rb:SetPoint("TOPLEFT", 10, y)
            rb:SetSize(140, 26)
            rb:SetText("Reset Positions")
            rb:SetScript("OnClick", function()
                settings.healthBar.positionX, settings.healthBar.positionY, settings.healthBar.anchor = 0, -180, "CENTER"
                settings.powerBar.positionX, settings.powerBar.positionY, settings.powerBar.anchor = 0, -200, "CENTER"
                settings.classPower.positionX, settings.classPower.positionY, settings.classPower.anchor = 0, -220, "CENTER"
                RefreshAllBars()
                TUICD:Print("Positions reset")
            end)
        end)
    elseif panelId == "healthbar" then
        local cfg = settings.healthBar
        local tabs = {
            {
                key = "layout",
                label = "Layout",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Enable Health Bar",
                        function() return cfg.enabled end, function(c) cfg.enabled = c end)
                    
                    y = CreateHeader(p, 10, y - 10, "Size")
                    y = CreateSlider(p, 10, y, "Width", 50, 1000, 1, function() return cfg.width end, function(v) cfg.width = v end)
                    y = CreateSlider(p, 10, y, "Height", 4, 100, 1, function() return cfg.height end, function(v) cfg.height = v end)
                end
            },
            {
                key = "appearance",
                label = "Appearance",
                builder = function(p)
                    local y = -10
                    
                    y = CreateTextureDropdown(p, 10, y, "Bar Texture", function() return cfg.texture end, function(v) cfg.texture = v end)
                    
                    local maskShapeOptions = {}
                    if TUICD.BarMasking then
                        for _, shape in ipairs(TUICD.BarMasking:GetShapeList()) do
                            table.insert(maskShapeOptions, { id = shape, name = TUICD.BarMasking:GetShapeName(shape) })
                        end
                    else
                        maskShapeOptions = { { id = "none", name = "Square (None)" } }
                    end
                    y = CreateDropdown(p, 10, y, "Bar Shape", maskShapeOptions, function() return cfg.maskShape or "none" end, function(v) cfg.maskShape = v end)
                    
                    y = CreateCheckbox(p, 10, y, "Show Border", function() return cfg.showBorder end, function(c) cfg.showBorder = c end)
                    y = CreateColorPicker(p, 10, y, "Background", cfg.backgroundColor)
                    y = CreateColorPicker(p, 10, y, "Border Color", cfg.borderColor)
                    
                    y = CreateHeader(p, 10, y - 10, "Bar Color")
                    y = CreateCheckbox(p, 10, y, "Use Class Color", function() return cfg.useClassColor end,
                        function(c) cfg.useClassColor = c if c then cfg.useHealthGradient = false end end)
                    y = CreateCheckbox(p, 10, y, "Use Health Gradient (Green → Yellow → Red)", function() return cfg.useHealthGradient end,
                        function(c) cfg.useHealthGradient = c if c then cfg.useClassColor = false end end)
                    y = CreateColorPicker(p, 10, y, "Custom Color", cfg.customColor)
                end
            },
            {
                key = "text",
                label = "Text",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Show Text", function() return cfg.showText end, function(c) cfg.showText = c end)
                    
                    local healthTextFormats = {
                        { id = "none", name = "Hidden" }, 
                        { id = "current", name = "Current" }, 
                        { id = "current_max", name = "Current / Max" },
                        { id = "percent", name = "Percent" },
                    }
                    y = CreateDropdown(p, 10, y, "Text Format", healthTextFormats, function() return cfg.textFormat end, function(v) cfg.textFormat = v end)
                    y = CreateCheckbox(p, 10, y, "Abbreviate Numbers (85k)", function() return cfg.abbreviateNumbers end, function(c) cfg.abbreviateNumbers = c end)
                    y = CreateFontDropdown(p, 10, y, "Font", function() return cfg.font end, function(v) cfg.font = v end)
                    y = CreateSlider(p, 10, y, "Font Size", 8, 48, 1, function() return cfg.textFontSize end, function(v) cfg.textFontSize = v end)
                    y = CreateColorPicker(p, 10, y, "Text Color", cfg.textColor)
                    
                    local healthTextPositions = {
                        { id = "LEFT", name = "Left" },
                        { id = "CENTER", name = "Center" },
                        { id = "RIGHT", name = "Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Text Position", healthTextPositions, function() return cfg.textPosition end, function(v) cfg.textPosition = v end)
                    y = CreateSlider(p, 10, y, "Text Offset X", -100, 100, 1, function() return cfg.textOffsetX end, function(v) cfg.textOffsetX = v end)
                    y = CreateSlider(p, 10, y, "Text Offset Y", -40, 40, 1, function() return cfg.textOffsetY end, function(v) cfg.textOffsetY = v end)
                end
            },
            {
                key = "absorb",
                label = "Absorb",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Show Absorb Overlay", function() return cfg.showAbsorb end, function(c) cfg.showAbsorb = c end)
                    y = CreateColorPicker(p, 10, y, "Absorb Color", cfg.absorbColor)
                    
                    y = CreateHeader(p, 10, y - 10, "Absorb Text")
                    y = CreateCheckbox(p, 10, y, "Show Absorb Text", function() return cfg.absorbShowText end, function(c) cfg.absorbShowText = c end)
                    
                    local absorbTextPositions = {
                        { id = "LEFT", name = "Left" },
                        { id = "CENTER", name = "Center" },
                        { id = "RIGHT", name = "Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Text Position", absorbTextPositions, function() return cfg.absorbTextPosition end, function(v) cfg.absorbTextPosition = v end)
                    y = CreateSlider(p, 10, y, "Text Size", 8, 40, 1, function() return cfg.absorbTextFontSize end, function(v) cfg.absorbTextFontSize = v end)
                    y = CreateSlider(p, 10, y, "Offset X", -100, 100, 1, function() return cfg.absorbTextOffsetX end, function(v) cfg.absorbTextOffsetX = v end)
                    y = CreateSlider(p, 10, y, "Offset Y", -40, 40, 1, function() return cfg.absorbTextOffsetY end, function(v) cfg.absorbTextOffsetY = v end)
                    y = CreateColorPicker(p, 10, y, "Text Color", cfg.absorbTextColor)
                end
            },
            {
                key = "visibility",
                label = "Visibility",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Enable Visibility Conditions",
                        function() return cfg.visibilityEnabled end, function(c) cfg.visibilityEnabled = c end)
                    
                    y = CreateHeader(p, 10, y - 10, "Show When (OR logic)")
                    y = CreateCheckbox(p, 10, y, "In Combat", function() return cfg.showInCombat end, function(c) cfg.showInCombat = c end)
                    y = CreateCheckbox(p, 10, y, "Out of Combat", function() return cfg.showOutOfCombat end, function(c) cfg.showOutOfCombat = c end)
                    y = CreateCheckbox(p, 10, y, "Has Target", function() return cfg.showHasTarget end, function(c) cfg.showHasTarget = c end)
                    y = CreateCheckbox(p, 10, y, "No Target", function() return cfg.showNoTarget end, function(c) cfg.showNoTarget = c end)
                    y = CreateCheckbox(p, 10, y, "Solo", function() return cfg.showSolo end, function(c) cfg.showSolo = c end)
                    y = CreateCheckbox(p, 10, y, "In Party", function() return cfg.showInParty end, function(c) cfg.showInParty = c end)
                    y = CreateCheckbox(p, 10, y, "In Raid", function() return cfg.showInRaid end, function(c) cfg.showInRaid = c end)
                    y = CreateCheckbox(p, 10, y, "In Instance", function() return cfg.showInInstance end, function(c) cfg.showInInstance = c end)
                    
                    y = CreateHeader(p, 10, y - 10, "Fade")
                    y = CreateCheckbox(p, 10, y, "Enable Fade", function() return cfg.fadeEnabled end, function(c) cfg.fadeEnabled = c end)
                    y = CreateSlider(p, 10, y, "Fade Delay (sec)", 0, 20, 0.5, function() return cfg.fadeDelay end, function(v) cfg.fadeDelay = v end)
                    y = CreateSlider(p, 10, y, "Fade Alpha", 0, 1, 0.05, function() return cfg.fadeAlpha end, function(v) cfg.fadeAlpha = v end)
                end
            },
        }
        CreateTabbedSettingsPanel("healthbar", "Health Bar", tabs)
    elseif panelId == "powerbar" then
        local cfg = settings.powerBar
        local tabs = {
            {
                key = "layout",
                label = "Layout",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Enable Power Bar",
                        function() return cfg.enabled end, function(c) cfg.enabled = c end)
                    
                    y = CreateHeader(p, 10, y - 10, "Size")
                    y = CreateSlider(p, 10, y, "Width", 50, 800, 1, function() return cfg.width end, function(v) cfg.width = v end)
                    y = CreateSlider(p, 10, y, "Height", 4, 80, 1, function() return cfg.height end, function(v) cfg.height = v end)
                end
            },
            {
                key = "appearance",
                label = "Appearance",
                builder = function(p)
                    local y = -10
                    
                    y = CreateTextureDropdown(p, 10, y, "Bar Texture", function() return cfg.texture end, function(v) cfg.texture = v end)
                    
                    local maskShapeOptions = {}
                    if TUICD.BarMasking then
                        for _, shape in ipairs(TUICD.BarMasking:GetShapeList()) do
                            table.insert(maskShapeOptions, { id = shape, name = TUICD.BarMasking:GetShapeName(shape) })
                        end
                    else
                        maskShapeOptions = { { id = "none", name = "Square (None)" } }
                    end
                    y = CreateDropdown(p, 10, y, "Bar Shape", maskShapeOptions, function() return cfg.maskShape or "none" end, function(v) cfg.maskShape = v end)
                    
                    y = CreateCheckbox(p, 10, y, "Show Border", function() return cfg.showBorder end, function(c) cfg.showBorder = c end)
                    y = CreateColorPicker(p, 10, y, "Background", cfg.backgroundColor)
                    y = CreateColorPicker(p, 10, y, "Border Color", cfg.borderColor)
                    
                    y = CreateHeader(p, 10, y - 10, "Bar Color")
                    y = CreateCheckbox(p, 10, y, "Use Class Color", function() return cfg.useClassColor end,
                        function(c) cfg.useClassColor = c if c then cfg.useResourceColor = false end end)
                    y = CreateCheckbox(p, 10, y, "Use Resource Color", function() return cfg.useResourceColor end,
                        function(c) cfg.useResourceColor = c if c then cfg.useClassColor = false end end)
                    y = CreateColorPicker(p, 10, y, "Custom Color", cfg.customColor)
                end
            },
            {
                key = "text",
                label = "Text",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Show Text", function() return cfg.showText end, function(c) cfg.showText = c end)
                    y = CreateDropdown(p, 10, y, "Text Format", TEXT_FORMATS, function() return cfg.textFormat end, function(v) cfg.textFormat = v end)
                    y = CreateFontDropdown(p, 10, y, "Font", function() return cfg.font end, function(v) cfg.font = v end)
                    y = CreateSlider(p, 10, y, "Font Size", 8, 48, 1, function() return cfg.textFontSize end, function(v) cfg.textFontSize = v end)
                    y = CreateColorPicker(p, 10, y, "Text Color", cfg.textColor)
                end
            },
            {
                key = "visibility",
                label = "Visibility",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Enable Visibility Conditions",
                        function() return cfg.visibilityEnabled end, function(c) cfg.visibilityEnabled = c end)
                    
                    y = CreateHeader(p, 10, y - 10, "Show When (OR logic)")
                    y = CreateCheckbox(p, 10, y, "In Combat", function() return cfg.showInCombat end, function(c) cfg.showInCombat = c end)
                    y = CreateCheckbox(p, 10, y, "Out of Combat", function() return cfg.showOutOfCombat end, function(c) cfg.showOutOfCombat = c end)
                    y = CreateCheckbox(p, 10, y, "Has Target", function() return cfg.showHasTarget end, function(c) cfg.showHasTarget = c end)
                    y = CreateCheckbox(p, 10, y, "No Target", function() return cfg.showNoTarget end, function(c) cfg.showNoTarget = c end)
                    y = CreateCheckbox(p, 10, y, "Solo", function() return cfg.showSolo end, function(c) cfg.showSolo = c end)
                    y = CreateCheckbox(p, 10, y, "In Party", function() return cfg.showInParty end, function(c) cfg.showInParty = c end)
                    y = CreateCheckbox(p, 10, y, "In Raid", function() return cfg.showInRaid end, function(c) cfg.showInRaid = c end)
                    y = CreateCheckbox(p, 10, y, "In Instance", function() return cfg.showInInstance end, function(c) cfg.showInInstance = c end)
                    
                    y = CreateHeader(p, 10, y - 10, "Fade")
                    y = CreateCheckbox(p, 10, y, "Enable Fade", function() return cfg.fadeEnabled end, function(c) cfg.fadeEnabled = c end)
                    y = CreateSlider(p, 10, y, "Fade Delay (sec)", 0, 20, 0.5, function() return cfg.fadeDelay end, function(v) cfg.fadeDelay = v end)
                    y = CreateSlider(p, 10, y, "Fade Alpha", 0, 1, 0.05, function() return cfg.fadeAlpha end, function(v) cfg.fadeAlpha = v end)
                end
            },
        }
        CreateTabbedSettingsPanel("powerbar", "Power Bar", tabs)
    elseif panelId == "classpower" then
        -- For Demon Hunters, use tabbed panel with Soul Fragments tab
        if playerClass == "DEMONHUNTER" then
            local tabs = {
                {
                    key = "settings",
                    label = "Settings",
                    builder = function(p)
                        local y, cfg = -10, settings.classPower
                        
                        y = CreateCheckbox(p, 10, y, "Enable Class Power",
                            function() return cfg.enabled end, function(c) cfg.enabled = c end)
                        
                        y = CreateHeader(p, 10, y - 10, "Size")
                        y = CreateSlider(p, 10, y, "Width", 50, 800, 1, function() return cfg.width end, function(v) cfg.width = v end)
                        y = CreateSlider(p, 10, y, "Height", 4, 60, 1, function() return cfg.height end, function(v) cfg.height = v end)
                        y = CreateSlider(p, 10, y, "Spacing", 0, 40, 1, function() return cfg.spacing end, function(v) cfg.spacing = v end)
                        
                        y = CreateHeader(p, 10, y - 10, "Appearance")
                        
                        local maskShapeOptions = {}
                        if TUICD.BarMasking then
                            for _, shape in ipairs(TUICD.BarMasking:GetShapeList()) do
                                table.insert(maskShapeOptions, { id = shape, name = TUICD.BarMasking:GetShapeName(shape) })
                            end
                        else
                            maskShapeOptions = { { id = "none", name = "Square (None)" } }
                        end
                        y = CreateDropdown(p, 10, y, "Segment Shape", maskShapeOptions, function() return cfg.maskShape or "none" end, function(v) cfg.maskShape = v end)
                        
                        y = CreateCheckbox(p, 10, y, "Show Border", function() return cfg.showBorder end, function(c) cfg.showBorder = c end)
                        y = CreateColorPicker(p, 10, y, "Inactive Color", cfg.inactiveColor)
                        y = CreateColorPicker(p, 10, y, "Border Color", cfg.borderColor)
                        
                        y = CreateHeader(p, 10, y - 10, "Segment Color")
                        y = CreateCheckbox(p, 10, y, "Use Class Color", function() return cfg.useClassColor end,
                            function(c) cfg.useClassColor = c if c then cfg.useResourceColor = false cfg.usePerPointColors = false end end)
                        y = CreateCheckbox(p, 10, y, "Use Resource Color", function() return cfg.useResourceColor end,
                            function(c) cfg.useResourceColor = c if c then cfg.useClassColor = false cfg.usePerPointColors = false end end)
                        y = CreateCheckbox(p, 10, y, "Per-Point Gradient", function() return cfg.usePerPointColors end,
                            function(c) cfg.usePerPointColors = c if c then cfg.useClassColor = false cfg.useResourceColor = false end end)
                        y = CreateColorPicker(p, 10, y, "Custom Color", cfg.customColor)
                        
                        y = CreateHeader(p, 10, y - 10, "Gradient Preset")
                        local gradientOptions = {}
                        for _, preset in ipairs(GRADIENT_PRESETS) do
                            table.insert(gradientOptions, { id = preset.id, name = preset.name })
                        end
                        table.insert(gradientOptions, { id = "custom", name = "Custom" })
                        
                        local currentMaxPoints = GetCurrentMaxResourcePoints()
                        if currentMaxPoints == 0 then currentMaxPoints = 5 end
                        local maxDisplayPoints = 10
                        p.perPointColorButtons = p.perPointColorButtons or {}
                        
                        y = CreateDropdown(p, 10, y, "Preset", gradientOptions, 
                            function() return cfg.gradientPreset or "green_to_red" end, 
                            function(v) 
                                if v ~= "custom" then
                                    ApplyGradientPreset(cfg, v)
                                    cfg.usePerPointColors = true
                                    cfg.useClassColor = false
                                    cfg.useResourceColor = false
                                else
                                    cfg.gradientPreset = "custom"
                                end
                                if p.perPointColorButtons then
                                    for i, btn in ipairs(p.perPointColorButtons) do
                                        if btn and btn.UpdateColor then btn:UpdateColor() end
                                    end
                                end
                                RefreshAllBars()
                            end)
                        
                        y = CreateHeader(p, 10, y - 10, "Per-Point Colors")
                        for i = 1, maxDisplayPoints do
                            local isActive = i <= currentMaxPoints
                            local labelText = isActive and ("Point " .. i) or ("|cff666666Point " .. i .. "|r")
                            local newY, colorBtn = CreateColorPicker(p, 10, y, labelText, cfg.perPointColors[i])
                            y = newY
                            p.perPointColorButtons[i] = colorBtn
                        end
                        
                        y = CreateSeparator(p, y - 10)
                        y = CreateHeader(p, 10, y - 5, "Text")
                        y = CreateCheckbox(p, 10, y, "Show Text", function() return cfg.showText end, function(c) cfg.showText = c end)
                        local cpTextFormats = {
                            { id = "current", name = "Current" },
                            { id = "current_max", name = "Current / Max" },
                            { id = "percent", name = "Percent" },
                        }
                        y = CreateDropdown(p, 10, y, "Text Format", cpTextFormats, function() return cfg.textFormat end, function(v) cfg.textFormat = v end)
                        y = CreateFontDropdown(p, 10, y, "Font", function() return cfg.textFont end, function(v) cfg.textFont = v end)
                        y = CreateSlider(p, 10, y, "Font Size", 6, 48, 1, function() return cfg.textFontSize end, function(v) cfg.textFontSize = v end)
                        
                        local outlineOptions = {
                            { id = "NONE", name = "None" },
                            { id = "OUTLINE", name = "Outline" },
                            { id = "THICKOUTLINE", name = "Thick Outline" },
                        }
                        y = CreateDropdown(p, 10, y, "Outline", outlineOptions, function() return cfg.textFontOutline end, function(v) cfg.textFontOutline = v end)
                        y = CreateSlider(p, 10, y, "Offset X", -100, 100, 1, function() return cfg.textOffsetX end, function(v) cfg.textOffsetX = v end)
                        y = CreateSlider(p, 10, y, "Offset Y", -100, 100, 1, function() return cfg.textOffsetY end, function(v) cfg.textOffsetY = v end)
                        y = CreateColorPicker(p, 10, y, "Text Color", cfg.textColor)
                    end
                },
                {
                    key = "visibility",
                    label = "Visibility",
                    builder = function(p)
                        local y, cfg = -10, settings.classPower
                        
                        y = CreateCheckbox(p, 10, y, "Enable Visibility Conditions", function() return cfg.visibilityEnabled end, function(c) cfg.visibilityEnabled = c end)
                        
                        y = CreateHeader(p, 10, y - 10, "Show When (OR logic)")
                        y = CreateCheckbox(p, 10, y, "In Combat", function() return cfg.showInCombat end, function(c) cfg.showInCombat = c end)
                        y = CreateCheckbox(p, 10, y, "Out of Combat", function() return cfg.showOutOfCombat end, function(c) cfg.showOutOfCombat = c end)
                        y = CreateCheckbox(p, 10, y, "Has Target", function() return cfg.showHasTarget end, function(c) cfg.showHasTarget = c end)
                        y = CreateCheckbox(p, 10, y, "No Target", function() return cfg.showNoTarget end, function(c) cfg.showNoTarget = c end)
                        y = CreateCheckbox(p, 10, y, "Solo", function() return cfg.showSolo end, function(c) cfg.showSolo = c end)
                        y = CreateCheckbox(p, 10, y, "In Party", function() return cfg.showInParty end, function(c) cfg.showInParty = c end)
                        y = CreateCheckbox(p, 10, y, "In Raid", function() return cfg.showInRaid end, function(c) cfg.showInRaid = c end)
                        y = CreateCheckbox(p, 10, y, "In Instance", function() return cfg.showInInstance end, function(c) cfg.showInInstance = c end)
                        
                        y = CreateHeader(p, 10, y - 10, "Fade")
                        y = CreateCheckbox(p, 10, y, "Enable Fade", function() return cfg.fadeEnabled end, function(c) cfg.fadeEnabled = c end)
                        y = CreateSlider(p, 10, y, "Fade Delay (sec)", 0, 20, 0.5, function() return cfg.fadeDelay end, function(v) cfg.fadeDelay = v end)
                        y = CreateSlider(p, 10, y, "Fade Alpha", 0, 1, 0.05, function() return cfg.fadeAlpha end, function(v) cfg.fadeAlpha = v end)
                    end
                },
                {
                    key = "soulfragments",
                    label = "Soul Fragments",
                    builder = function(p)
                        local y = -10
                        local cpCfg = settings.classPower
                        
                        local info = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        info:SetPoint("TOPLEFT", 10, y)
                        info:SetWidth(PANEL_WIDTH - 70)
                        info:SetJustifyH("LEFT")
                        info:SetText("|cffffd100Soul Fragments|r are displayed as a continuous bar with segment dividers.")
                        y = y - 30
                        
                        y = CreateHeader(p, 10, y - 5, "Bar Gradient Style")
                        
                        local sfGradientOptions = {
                            { id = "none", name = "Solid Color (No Gradient)" },
                            { id = "green", name = "Dark to Light Green" },
                            { id = "purple", name = "Purple to White (Fury)" },
                        }
                        y = CreateDropdown(p, 10, y, "Gradient", sfGradientOptions, 
                            function() return cpCfg.soulFragmentsGradient or "purple" end, 
                            function(v) cpCfg.soulFragmentsGradient = v end)
                        
                        y = CreateSeparator(p, y - 10)
                        
                        local note = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        note:SetPoint("TOPLEFT", 10, y - 5)
                        note:SetWidth(PANEL_WIDTH - 70)
                        note:SetJustifyH("LEFT")
                        note:SetTextColor(0.6, 0.6, 0.6)
                        note:SetText("Size, position, and appearance settings are in the Settings tab.\nVisibility and fade settings are in the Visibility tab.")
                    end
                },
            }
            CreateTabbedSettingsPanel("classpower", "Class Power", tabs)
        else
            -- Non-DH classes use regular panel
            CreateSettingsPanel("classpower", "Class Power", function(p)
                local y, cfg = -10, settings.classPower
                
                y = CreateCheckbox(p, 10, y, "Enable Class Power",
                    function() return cfg.enabled end, function(c) cfg.enabled = c end)
                
                y = CreateHeader(p, 10, y - 10, "Size")
                y = CreateSlider(p, 10, y, "Width", 50, 800, 1, function() return cfg.width end, function(v) cfg.width = v end)
                y = CreateSlider(p, 10, y, "Height", 4, 60, 1, function() return cfg.height end, function(v) cfg.height = v end)
                y = CreateSlider(p, 10, y, "Spacing", 0, 40, 1, function() return cfg.spacing end, function(v) cfg.spacing = v end)
                
                y = CreateHeader(p, 10, y - 10, "Appearance")
                
                local maskShapeOptions = {}
                if TUICD.BarMasking then
                    for _, shape in ipairs(TUICD.BarMasking:GetShapeList()) do
                        table.insert(maskShapeOptions, { id = shape, name = TUICD.BarMasking:GetShapeName(shape) })
                    end
                else
                    maskShapeOptions = { { id = "none", name = "Square (None)" } }
                end
                y = CreateDropdown(p, 10, y, "Segment Shape", maskShapeOptions, function() return cfg.maskShape or "none" end, function(v) cfg.maskShape = v end)
                
                y = CreateCheckbox(p, 10, y, "Show Border", function() return cfg.showBorder end, function(c) cfg.showBorder = c end)
                y = CreateColorPicker(p, 10, y, "Inactive Color", cfg.inactiveColor)
                y = CreateColorPicker(p, 10, y, "Border Color", cfg.borderColor)
                
                y = CreateHeader(p, 10, y - 10, "Segment Color")
                y = CreateCheckbox(p, 10, y, "Use Class Color", function() return cfg.useClassColor end,
                    function(c) cfg.useClassColor = c if c then cfg.useResourceColor = false cfg.usePerPointColors = false end end)
                y = CreateCheckbox(p, 10, y, "Use Resource Color", function() return cfg.useResourceColor end,
                    function(c) cfg.useResourceColor = c if c then cfg.useClassColor = false cfg.usePerPointColors = false end end)
                y = CreateCheckbox(p, 10, y, "Per-Point Gradient", function() return cfg.usePerPointColors end,
                    function(c) cfg.usePerPointColors = c if c then cfg.useClassColor = false cfg.useResourceColor = false end end)
                y = CreateColorPicker(p, 10, y, "Custom Color", cfg.customColor)
                
                y = CreateHeader(p, 10, y - 10, "Gradient Preset")
                local gradientOptions = {}
                for _, preset in ipairs(GRADIENT_PRESETS) do
                    table.insert(gradientOptions, { id = preset.id, name = preset.name })
                end
                table.insert(gradientOptions, { id = "custom", name = "Custom" })
                
                local currentMaxPoints = GetCurrentMaxResourcePoints()
                if currentMaxPoints == 0 then currentMaxPoints = 5 end
                local maxDisplayPoints = 10
                p.perPointColorButtons = p.perPointColorButtons or {}
                
                y = CreateDropdown(p, 10, y, "Preset", gradientOptions, 
                    function() return cfg.gradientPreset or "green_to_red" end, 
                    function(v) 
                        if v ~= "custom" then
                            ApplyGradientPreset(cfg, v)
                            cfg.usePerPointColors = true
                            cfg.useClassColor = false
                            cfg.useResourceColor = false
                        else
                            cfg.gradientPreset = "custom"
                        end
                        if p.perPointColorButtons then
                            for i, btn in ipairs(p.perPointColorButtons) do
                                if btn and btn.UpdateColor then btn:UpdateColor() end
                            end
                        end
                        RefreshAllBars()
                    end)
                
                y = CreateHeader(p, 10, y - 10, "Per-Point Colors")
                for i = 1, maxDisplayPoints do
                    local isActive = i <= currentMaxPoints
                    local labelText = isActive and ("Point " .. i) or ("|cff666666Point " .. i .. "|r")
                    local newY, colorBtn = CreateColorPicker(p, 10, y, labelText, cfg.perPointColors[i])
                    y = newY
                    p.perPointColorButtons[i] = colorBtn
                end
                
                y = CreateSeparator(p, y - 10)
                y = CreateHeader(p, 10, y - 5, "Text")
                y = CreateCheckbox(p, 10, y, "Show Text", function() return cfg.showText end, function(c) cfg.showText = c end)
                y = CreateFontDropdown(p, 10, y, "Font", function() return cfg.textFont end, function(v) cfg.textFont = v end)
                y = CreateSlider(p, 10, y, "Font Size", 6, 48, 1, function() return cfg.textFontSize end, function(v) cfg.textFontSize = v end)
                
                local outlineOptions = {
                    { id = "NONE", name = "None" },
                    { id = "OUTLINE", name = "Outline" },
                    { id = "THICKOUTLINE", name = "Thick Outline" },
                }
                y = CreateDropdown(p, 10, y, "Outline", outlineOptions, function() return cfg.textFontOutline end, function(v) cfg.textFontOutline = v end)
                y = CreateSlider(p, 10, y, "Offset X", -50, 50, 1, function() return cfg.textOffsetX end, function(v) cfg.textOffsetX = v end)
                y = CreateSlider(p, 10, y, "Offset Y", -50, 50, 1, function() return cfg.textOffsetY end, function(v) cfg.textOffsetY = v end)
                y = CreateColorPicker(p, 10, y, "Text Color", cfg.textColor)
                
                y = CreateSeparator(p, y - 10)
                y = CreateHeader(p, 10, y - 5, "Visibility")
                y = CreateCheckbox(p, 10, y, "Enable Visibility Conditions", function() return cfg.visibilityEnabled end, function(c) cfg.visibilityEnabled = c end)
                y = CreateCheckbox(p, 10, y, "In Combat", function() return cfg.showInCombat end, function(c) cfg.showInCombat = c end)
                y = CreateCheckbox(p, 10, y, "Out of Combat", function() return cfg.showOutOfCombat end, function(c) cfg.showOutOfCombat = c end)
                y = CreateCheckbox(p, 10, y, "Has Target", function() return cfg.showHasTarget end, function(c) cfg.showHasTarget = c end)
                y = CreateCheckbox(p, 10, y, "No Target", function() return cfg.showNoTarget end, function(c) cfg.showNoTarget = c end)
                y = CreateCheckbox(p, 10, y, "Solo", function() return cfg.showSolo end, function(c) cfg.showSolo = c end)
                y = CreateCheckbox(p, 10, y, "In Party", function() return cfg.showInParty end, function(c) cfg.showInParty = c end)
                y = CreateCheckbox(p, 10, y, "In Raid", function() return cfg.showInRaid end, function(c) cfg.showInRaid = c end)
                y = CreateCheckbox(p, 10, y, "In Instance", function() return cfg.showInInstance end, function(c) cfg.showInInstance = c end)
                
                y = CreateHeader(p, 10, y - 10, "Fade")
                y = CreateCheckbox(p, 10, y, "Enable Fade", function() return cfg.fadeEnabled end, function(c) cfg.fadeEnabled = c end)
                y = CreateSlider(p, 10, y, "Fade Delay (sec)", 0, 10, 0.5, function() return cfg.fadeDelay end, function(v) cfg.fadeDelay = v end)
                y = CreateSlider(p, 10, y, "Fade Alpha", 0, 1, 0.05, function() return cfg.fadeAlpha end, function(v) cfg.fadeAlpha = v end)
                
                -- Stagger visibility (Brewmaster Monk only)
                if playerClass == "MONK" and GetSecondaryResource() == SPECIAL_RESOURCES.STAGGER then
                    y = CreateSeparator(p, y - 10)
                    
                    y = CreateHeader(p, 10, y - 5, "Stagger")
                    y = CreateCheckbox(p, 10, y, "Enable Visibility Conditions",
                        function() return settings.stagger.visibilityEnabled end,
                        function(c) settings.stagger.visibilityEnabled = c end)
                    y = CreateCheckbox(p, 10, y, "In Combat", function() return settings.stagger.showInCombat end, function(c) settings.stagger.showInCombat = c end)
                    y = CreateCheckbox(p, 10, y, "Out of Combat", function() return settings.stagger.showOutOfCombat end, function(c) settings.stagger.showOutOfCombat = c end)
                    y = CreateCheckbox(p, 10, y, "Has Target", function() return settings.stagger.showHasTarget end, function(c) settings.stagger.showHasTarget = c end)
                    y = CreateCheckbox(p, 10, y, "No Target", function() return settings.stagger.showNoTarget end, function(c) settings.stagger.showNoTarget = c end)
                    y = CreateCheckbox(p, 10, y, "Solo", function() return settings.stagger.showSolo end, function(c) settings.stagger.showSolo = c end)
                    y = CreateCheckbox(p, 10, y, "In Party", function() return settings.stagger.showInParty end, function(c) settings.stagger.showInParty = c end)
                    y = CreateCheckbox(p, 10, y, "In Raid", function() return settings.stagger.showInRaid end, function(c) settings.stagger.showInRaid = c end)
                    y = CreateCheckbox(p, 10, y, "In Instance", function() return settings.stagger.showInInstance end, function(c) settings.stagger.showInInstance = c end)
                    
                    y = CreateHeader(p, 10, y - 10, "Stagger Fade")
                    y = CreateCheckbox(p, 10, y, "Enable Fade", function() return settings.stagger.fadeEnabled end, function(c) settings.stagger.fadeEnabled = c end)
                    y = CreateSlider(p, 10, y, "Fade Delay (sec)", 0, 10, 0.5, function() return settings.stagger.fadeDelay end, function(v) settings.stagger.fadeDelay = v end)
                    y = CreateSlider(p, 10, y, "Fade Alpha", 0, 1, 0.05, function() return settings.stagger.fadeAlpha end, function(v) settings.stagger.fadeAlpha = v end)
                end
            end)
        end
    end
    
    -- Stagger panel for Brewmaster Monks
    if playerClass == "MONK" then
        CreateSettingsPanel("stagger", "Stagger", function(p)
            local cfg = settings.stagger
            local y = -10
            
            -- Note: Stagger uses the class power bar area
            local note = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("TOPLEFT", 10, y)
            note:SetWidth(PANEL_WIDTH - 70)
            note:SetJustifyH("LEFT")
            note:SetText("|cff888888Stagger replaces the class power segments with a continuous bar.\nPosition and size are controlled in the Class Power panel.|r")
            y = y - 35
            
            y = CreateCheckbox(p, 10, y, "Enable Stagger Display", 
                function() return settings.classPower.enabled end, 
                function(c) 
                    settings.classPower.enabled = c 
                    if c then 
                        StartStaggerUpdateTicker() 
                        UpdateClassPower()
                    else 
                        StopStaggerUpdateTicker()
                        if classPowerFrame then classPowerFrame:Hide() end 
                    end 
                end)
            
            y = CreateSeparator(p, y - 5)
            y = CreateHeader(p, 10, y - 5, "Color Options")
            
            y = CreateCheckbox(p, 10, y, "Use Dynamic Color (Green → Yellow → Red)", 
                function() return cfg.useDynamicColor end, 
                function(c) cfg.useDynamicColor = c UpdateClassPower() end)
            
            y = CreateColorPicker(p, 10, y, "Light Stagger (<30%)", cfg.lightColor)
            y = CreateColorPicker(p, 10, y, "Moderate Stagger (30-60%)", cfg.moderateColor)
            y = CreateColorPicker(p, 10, y, "Heavy Stagger (>60%)", cfg.heavyColor)
            y = CreateColorPicker(p, 10, y, "Custom Color (if dynamic disabled)", cfg.customColor)
            
            y = CreateSeparator(p, y - 5)
            y = CreateHeader(p, 10, y - 5, "Text Options")
            
            y = CreateCheckbox(p, 10, y, "Show Text", 
                function() return settings.classPower.showText end, 
                function(c) settings.classPower.showText = c UpdateClassPower() end)
            
            local textFormatOptions = { 
                { id = "amount", name = "Amount (23.5K)" }, 
                { id = "percent", name = "Percent (45%)" }, 
                { id = "both", name = "Both (23.5K (45%))" } 
            }
            y = CreateDropdown(p, 10, y, "Text Format", textFormatOptions, 
                function() return cfg.textFormat end, 
                function(v) cfg.textFormat = v UpdateClassPower() end)
            
            y = CreateSeparator(p, y - 10)
            
            local info = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            info:SetPoint("TOPLEFT", 10, y - 5)
            info:SetWidth(PANEL_WIDTH - 70)
            info:SetJustifyH("LEFT")
            info:SetText("|cff888888Stagger bar shows how much damage is being delayed.\n\nColor thresholds:\n• Green: Light stagger (<30%)\n• Yellow: Moderate (30-60%)\n• Red: Heavy stagger (>60%)\n\nUse Edit Mode to position the bar.|r")
        end)
    end
    
    -- Player Buffs panel
    if panelId == "buffs" then
        local cfg = settings.buffs
        local tabs = {
            {
                key = "layout",
                label = "Layout",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Enable Player Buffs Display",
                        function() return cfg.enabled end, 
                        function(c) cfg.enabled = c RefreshAllBars() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Position")
                    y = CreateSlider(p, 10, y, "X Offset", -1000, 1000, 1, 
                        function() return cfg.positionX end, 
                        function(v) cfg.positionX = v RefreshBuffsLayout() end)
                    y = CreateSlider(p, 10, y, "Y Offset", -1000, 1000, 1, 
                        function() return cfg.positionY end, 
                        function(v) cfg.positionY = v RefreshBuffsLayout() end)
                    
                    local anchorPoints = {
                        { id = "CENTER", name = "Center" },
                        { id = "TOPLEFT", name = "Top Left" },
                        { id = "TOP", name = "Top" },
                        { id = "TOPRIGHT", name = "Top Right" },
                        { id = "LEFT", name = "Left" },
                        { id = "RIGHT", name = "Right" },
                        { id = "BOTTOMLEFT", name = "Bottom Left" },
                        { id = "BOTTOM", name = "Bottom" },
                        { id = "BOTTOMRIGHT", name = "Bottom Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Anchor Point", anchorPoints, 
                        function() return cfg.anchor end, 
                        function(v) cfg.anchor = v RefreshBuffsLayout() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Size")
                    y = CreateSlider(p, 10, y, "Icon Size", 16, 64, 1, 
                        function() return cfg.size end, 
                        function(v) cfg.size = v UpdateBuffs() end)
                    y = CreateSlider(p, 10, y, "Max Auras", 1, 32, 1, 
                        function() return cfg.maxAuras end, 
                        function(v) cfg.maxAuras = v UpdateBuffs() end)
                    y = CreateSlider(p, 10, y, "Scale", 0.5, 2.0, 0.05, 
                        function() return cfg.scale end, 
                        function(v) cfg.scale = v UpdateBuffs() end)
                    y = CreateSlider(p, 10, y, "Icon Zoom", 1.0, 1.5, 0.05, 
                        function() return cfg.zoom end, 
                        function(v) cfg.zoom = v UpdateBuffs() end)
                end
            },
            {
                key = "grid",
                label = "Grid",
                builder = function(p)
                    local y = -10
                    
                    local layoutModes = {
                        { id = "standard", name = "Standard Grid" },
                        { id = "custom", name = "Custom Row Pattern" },
                    }
                    y = CreateDropdown(p, 10, y, "Layout Mode", layoutModes, 
                        function() return cfg.layoutMode end, 
                        function(v) cfg.layoutMode = v UpdateBuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Standard Layout")
                    y = CreateSlider(p, 10, y, "Spacing", 0, 20, 1, 
                        function() return cfg.spacing end, 
                        function(v) cfg.spacing = v UpdateBuffs() end)
                    y = CreateSlider(p, 10, y, "Wrap After", 1, 16, 1, 
                        function() return cfg.wrapAfter end, 
                        function(v) cfg.wrapAfter = v UpdateBuffs() end)
                    
                    local growDirections = {
                        { id = "RIGHT", name = "Right" },
                        { id = "LEFT", name = "Left" },
                        { id = "UP", name = "Up" },
                        { id = "DOWN", name = "Down" },
                    }
                    y = CreateDropdown(p, 10, y, "Grow Direction", growDirections, 
                        function() return cfg.growDirection end, 
                        function(v) cfg.growDirection = v UpdateBuffs() end)
                    y = CreateDropdown(p, 10, y, "Wrap Direction", growDirections, 
                        function() return cfg.wrapDirection end, 
                        function(v) cfg.wrapDirection = v UpdateBuffs() end)
                    
                    local horizontalAligns = {
                        { id = "LEFT", name = "Left" },
                        { id = "CENTER", name = "Center" },
                        { id = "RIGHT", name = "Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Horizontal Align", horizontalAligns, 
                        function() return cfg.horizontalAlign end, 
                        function(v) cfg.horizontalAlign = v UpdateBuffs() end)
                    
                    local verticalAligns = {
                        { id = "TOP", name = "Top" },
                        { id = "MIDDLE", name = "Middle" },
                        { id = "BOTTOM", name = "Bottom" },
                    }
                    y = CreateDropdown(p, 10, y, "Vertical Align", verticalAligns, 
                        function() return cfg.verticalAlign end, 
                        function(v) cfg.verticalAlign = v UpdateBuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Custom Layout")
                    y = CreateEditBox(p, 10, y, "Row Pattern", 150,
                        function() return cfg.rowPattern end, 
                        function(v) cfg.rowPattern = v UpdateBuffs() end)
                    
                    local alignments = {
                        { id = "LEFT", name = "Left" },
                        { id = "CENTER", name = "Center" },
                        { id = "RIGHT", name = "Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Alignment", alignments, 
                        function() return cfg.alignment end, 
                        function(v) cfg.alignment = v UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "Compact Mode",
                        function() return cfg.compactMode end, 
                        function(c) cfg.compactMode = c UpdateBuffs() end)
                    y = CreateSlider(p, 10, y, "Compact Offset", -10, 0, 1, 
                        function() return cfg.compactOffset end, 
                        function(v) cfg.compactOffset = v UpdateBuffs() end)
                    y = CreateSlider(p, 10, y, "H Spacing", 0, 20, 1, 
                        function() return cfg.hSpacing end, 
                        function(v) cfg.hSpacing = v UpdateBuffs() end)
                    y = CreateSlider(p, 10, y, "V Spacing", 0, 20, 1, 
                        function() return cfg.vSpacing end, 
                        function(v) cfg.vSpacing = v UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "Reverse Order",
                        function() return cfg.reverseOrder end, 
                        function(c) cfg.reverseOrder = c UpdateBuffs() end)
                    
                    y = CreateSeparator(p, y - 10)
                    local info = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    info:SetPoint("TOPLEFT", 10, y - 5)
                    info:SetWidth(PANEL_WIDTH - 70)
                    info:SetJustifyH("LEFT")
                    info:SetText("|cff888888Row Pattern: comma-separated numbers.\nExamples:\n• 4,4,4,4 = 4x4 grid\n• 1,3,5,3,1 = diamond shape\n• 8 = single row of 8|r")
                end
            },
            {
                key = "icons",
                label = "Icons",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Show Duration Sweep",
                        function() return cfg.showDuration end, 
                        function(c) cfg.showDuration = c UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "Show Duration Text",
                        function() return cfg.showDurationText end, 
                        function(c) cfg.showDurationText = c UpdateBuffs() end)
                    y = CreateSlider(p, 10, y, "Duration Font Size", 6, 16, 1, 
                        function() return cfg.durationFontSize end, 
                        function(v) cfg.durationFontSize = v UpdateBuffs() end)
                    
                    local textPositions = {
                        { id = "TOP", name = "Top" },
                        { id = "CENTER", name = "Center" },
                        { id = "BOTTOM", name = "Bottom" },
                    }
                    y = CreateDropdown(p, 10, y, "Duration Position", textPositions, 
                        function() return cfg.durationPosition end, 
                        function(v) cfg.durationPosition = v UpdateBuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Stacks")
                    y = CreateCheckbox(p, 10, y, "Show Stack Count",
                        function() return cfg.showStacks end, 
                        function(c) cfg.showStacks = c UpdateBuffs() end)
                    y = CreateSlider(p, 10, y, "Stack Font Size", 6, 16, 1, 
                        function() return cfg.stackFontSize end, 
                        function(v) cfg.stackFontSize = v UpdateBuffs() end)
                    
                    local stackPositions = {
                        { id = "TOPLEFT", name = "Top Left" },
                        { id = "TOPRIGHT", name = "Top Right" },
                        { id = "BOTTOMLEFT", name = "Bottom Left" },
                        { id = "BOTTOMRIGHT", name = "Bottom Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Stack Position", stackPositions, 
                        function() return cfg.stackPosition end, 
                        function(v) cfg.stackPosition = v UpdateBuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Border")
                    y = CreateCheckbox(p, 10, y, "Show Border",
                        function() return cfg.showBorder end, 
                        function(c) cfg.showBorder = c UpdateBuffs() end)
                    y = CreateColorPicker(p, 10, y, "Border Color", cfg.borderColor)
                    
                    y = CreateHeader(p, 10, y - 10, "Sorting (Midnight)")
                    local sortByOptions = {
                        { id = "default", name = "Default" },
                        { id = "duration", name = "Duration" },
                        { id = "name", name = "Name" },
                    }
                    y = CreateDropdown(p, 10, y, "Sort By", sortByOptions, 
                        function() return cfg.sortBy end, 
                        function(v) cfg.sortBy = v UpdateBuffs() end)
                    
                    local sortDirOptions = {
                        { id = "normal", name = "Normal" },
                        { id = "reverse", name = "Reverse" },
                    }
                    y = CreateDropdown(p, 10, y, "Sort Direction", sortDirOptions, 
                        function() return cfg.sortDirection end, 
                        function(v) cfg.sortDirection = v UpdateBuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Filtering")
                    y = CreateCheckbox(p, 10, y, "Hide Permanent Buffs (no duration)",
                        function() return cfg.hidePermanent end, 
                        function(c) cfg.hidePermanent = c UpdateBuffs() end)
                    -- Note: "Show Only My Buffs" removed - sourceUnit is secret in Midnight
                end
            },
            {
                key = "visibility",
                label = "Visibility",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Enable Visibility Conditions",
                        function() return cfg.visibilityEnabled end, 
                        function(c) cfg.visibilityEnabled = c UpdateBuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Show When (OR logic)")
                    y = CreateCheckbox(p, 10, y, "In Combat", 
                        function() return cfg.showInCombat end, 
                        function(c) cfg.showInCombat = c UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "Out of Combat", 
                        function() return cfg.showOutOfCombat end, 
                        function(c) cfg.showOutOfCombat = c UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "Has Target", 
                        function() return cfg.showHasTarget end, 
                        function(c) cfg.showHasTarget = c UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "No Target", 
                        function() return cfg.showNoTarget end, 
                        function(c) cfg.showNoTarget = c UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "Solo", 
                        function() return cfg.showSolo end, 
                        function(c) cfg.showSolo = c UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "In Party", 
                        function() return cfg.showInParty end, 
                        function(c) cfg.showInParty = c UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "In Raid", 
                        function() return cfg.showInRaid end, 
                        function(c) cfg.showInRaid = c UpdateBuffs() end)
                    y = CreateCheckbox(p, 10, y, "In Instance", 
                        function() return cfg.showInInstance end, 
                        function(c) cfg.showInInstance = c UpdateBuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Fade")
                    y = CreateCheckbox(p, 10, y, "Enable Fade", 
                        function() return cfg.fadeEnabled end, 
                        function(c) cfg.fadeEnabled = c end)
                    y = CreateSlider(p, 10, y, "Fade Delay (sec)", 0, 10, 0.5, 
                        function() return cfg.fadeDelay end, 
                        function(v) cfg.fadeDelay = v end)
                    y = CreateSlider(p, 10, y, "Fade Alpha", 0, 1, 0.05, 
                        function() return cfg.fadeAlpha end, 
                        function(v) cfg.fadeAlpha = v end)
                end
            },
        }
        CreateTabbedSettingsPanel("buffs", "Player Buffs", tabs)
    end
    
    -- Player Debuffs panel
    if panelId == "debuffs" then
        local cfg = settings.debuffs
        local tabs = {
            {
                key = "layout",
                label = "Layout",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Enable Player Debuffs Display",
                        function() return cfg.enabled end, 
                        function(c) cfg.enabled = c RefreshAllBars() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Position")
                    y = CreateSlider(p, 10, y, "X Offset", -1000, 1000, 1, 
                        function() return cfg.positionX end, 
                        function(v) cfg.positionX = v RefreshDebuffsLayout() end)
                    y = CreateSlider(p, 10, y, "Y Offset", -1000, 1000, 1, 
                        function() return cfg.positionY end, 
                        function(v) cfg.positionY = v RefreshDebuffsLayout() end)
                    
                    local anchorPoints = {
                        { id = "CENTER", name = "Center" },
                        { id = "TOPLEFT", name = "Top Left" },
                        { id = "TOP", name = "Top" },
                        { id = "TOPRIGHT", name = "Top Right" },
                        { id = "LEFT", name = "Left" },
                        { id = "RIGHT", name = "Right" },
                        { id = "BOTTOMLEFT", name = "Bottom Left" },
                        { id = "BOTTOM", name = "Bottom" },
                        { id = "BOTTOMRIGHT", name = "Bottom Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Anchor Point", anchorPoints, 
                        function() return cfg.anchor end, 
                        function(v) cfg.anchor = v RefreshDebuffsLayout() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Size")
                    y = CreateSlider(p, 10, y, "Icon Size", 16, 64, 1, 
                        function() return cfg.size end, 
                        function(v) cfg.size = v UpdateDebuffs() end)
                    y = CreateSlider(p, 10, y, "Max Auras", 1, 32, 1, 
                        function() return cfg.maxAuras end, 
                        function(v) cfg.maxAuras = v UpdateDebuffs() end)
                    y = CreateSlider(p, 10, y, "Scale", 0.5, 2.0, 0.05, 
                        function() return cfg.scale end, 
                        function(v) cfg.scale = v UpdateDebuffs() end)
                    y = CreateSlider(p, 10, y, "Icon Zoom", 1.0, 1.5, 0.05, 
                        function() return cfg.zoom end, 
                        function(v) cfg.zoom = v UpdateDebuffs() end)
                end
            },
            {
                key = "grid",
                label = "Grid",
                builder = function(p)
                    local y = -10
                    
                    local layoutModes = {
                        { id = "standard", name = "Standard Grid" },
                        { id = "custom", name = "Custom Row Pattern" },
                    }
                    y = CreateDropdown(p, 10, y, "Layout Mode", layoutModes, 
                        function() return cfg.layoutMode end, 
                        function(v) cfg.layoutMode = v UpdateDebuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Standard Layout")
                    y = CreateSlider(p, 10, y, "Spacing", 0, 20, 1, 
                        function() return cfg.spacing end, 
                        function(v) cfg.spacing = v UpdateDebuffs() end)
                    y = CreateSlider(p, 10, y, "Wrap After", 1, 16, 1, 
                        function() return cfg.wrapAfter end, 
                        function(v) cfg.wrapAfter = v UpdateDebuffs() end)
                    
                    local growDirections = {
                        { id = "RIGHT", name = "Right" },
                        { id = "LEFT", name = "Left" },
                        { id = "UP", name = "Up" },
                        { id = "DOWN", name = "Down" },
                    }
                    y = CreateDropdown(p, 10, y, "Grow Direction", growDirections, 
                        function() return cfg.growDirection end, 
                        function(v) cfg.growDirection = v UpdateDebuffs() end)
                    y = CreateDropdown(p, 10, y, "Wrap Direction", growDirections, 
                        function() return cfg.wrapDirection end, 
                        function(v) cfg.wrapDirection = v UpdateDebuffs() end)
                    
                    local horizontalAligns = {
                        { id = "LEFT", name = "Left" },
                        { id = "CENTER", name = "Center" },
                        { id = "RIGHT", name = "Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Horizontal Align", horizontalAligns, 
                        function() return cfg.horizontalAlign end, 
                        function(v) cfg.horizontalAlign = v UpdateDebuffs() end)
                    
                    local verticalAligns = {
                        { id = "TOP", name = "Top" },
                        { id = "MIDDLE", name = "Middle" },
                        { id = "BOTTOM", name = "Bottom" },
                    }
                    y = CreateDropdown(p, 10, y, "Vertical Align", verticalAligns, 
                        function() return cfg.verticalAlign end, 
                        function(v) cfg.verticalAlign = v UpdateDebuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Custom Layout")
                    y = CreateEditBox(p, 10, y, "Row Pattern", 150,
                        function() return cfg.rowPattern end, 
                        function(v) cfg.rowPattern = v UpdateDebuffs() end)
                    
                    local alignments = {
                        { id = "LEFT", name = "Left" },
                        { id = "CENTER", name = "Center" },
                        { id = "RIGHT", name = "Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Alignment", alignments, 
                        function() return cfg.alignment end, 
                        function(v) cfg.alignment = v UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "Compact Mode",
                        function() return cfg.compactMode end, 
                        function(c) cfg.compactMode = c UpdateDebuffs() end)
                    y = CreateSlider(p, 10, y, "Compact Offset", -10, 0, 1, 
                        function() return cfg.compactOffset end, 
                        function(v) cfg.compactOffset = v UpdateDebuffs() end)
                    y = CreateSlider(p, 10, y, "H Spacing", 0, 20, 1, 
                        function() return cfg.hSpacing end, 
                        function(v) cfg.hSpacing = v UpdateDebuffs() end)
                    y = CreateSlider(p, 10, y, "V Spacing", 0, 20, 1, 
                        function() return cfg.vSpacing end, 
                        function(v) cfg.vSpacing = v UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "Reverse Order",
                        function() return cfg.reverseOrder end, 
                        function(c) cfg.reverseOrder = c UpdateDebuffs() end)
                    
                    y = CreateSeparator(p, y - 10)
                    local info = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    info:SetPoint("TOPLEFT", 10, y - 5)
                    info:SetWidth(PANEL_WIDTH - 70)
                    info:SetJustifyH("LEFT")
                    info:SetText("|cff888888Row Pattern: comma-separated numbers.\nExamples:\n• 4,4,4,4 = 4x4 grid\n• 1,3,5,3,1 = diamond shape\n• 8 = single row of 8|r")
                end
            },
            {
                key = "icons",
                label = "Icons",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Show Duration Sweep",
                        function() return cfg.showDuration end, 
                        function(c) cfg.showDuration = c UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "Show Duration Text",
                        function() return cfg.showDurationText end, 
                        function(c) cfg.showDurationText = c UpdateDebuffs() end)
                    y = CreateSlider(p, 10, y, "Duration Font Size", 6, 16, 1, 
                        function() return cfg.durationFontSize end, 
                        function(v) cfg.durationFontSize = v UpdateDebuffs() end)
                    
                    local textPositions = {
                        { id = "TOP", name = "Top" },
                        { id = "CENTER", name = "Center" },
                        { id = "BOTTOM", name = "Bottom" },
                    }
                    y = CreateDropdown(p, 10, y, "Duration Position", textPositions, 
                        function() return cfg.durationPosition end, 
                        function(v) cfg.durationPosition = v UpdateDebuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Stacks")
                    y = CreateCheckbox(p, 10, y, "Show Stack Count",
                        function() return cfg.showStacks end, 
                        function(c) cfg.showStacks = c UpdateDebuffs() end)
                    y = CreateSlider(p, 10, y, "Stack Font Size", 6, 16, 1, 
                        function() return cfg.stackFontSize end, 
                        function(v) cfg.stackFontSize = v UpdateDebuffs() end)
                    
                    local stackPositions = {
                        { id = "TOPLEFT", name = "Top Left" },
                        { id = "TOPRIGHT", name = "Top Right" },
                        { id = "BOTTOMLEFT", name = "Bottom Left" },
                        { id = "BOTTOMRIGHT", name = "Bottom Right" },
                    }
                    y = CreateDropdown(p, 10, y, "Stack Position", stackPositions, 
                        function() return cfg.stackPosition end, 
                        function(v) cfg.stackPosition = v UpdateDebuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Border")
                    y = CreateCheckbox(p, 10, y, "Show Border",
                        function() return cfg.showBorder end, 
                        function(c) cfg.showBorder = c UpdateDebuffs() end)
                    y = CreateColorPicker(p, 10, y, "Border Color", cfg.borderColor)
                    
                    y = CreateHeader(p, 10, y - 10, "Debuff Coloring")
                    y = CreateCheckbox(p, 10, y, "Color by Dispel Type",
                        function() return cfg.colorByDispelType end, 
                        function(c) cfg.colorByDispelType = c UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "Dispel Color Border Only",
                        function() return cfg.dispelBorderOnly end, 
                        function(c) cfg.dispelBorderOnly = c UpdateDebuffs() end)
                    
                    y = CreateSeparator(p, y - 10)
                    local info = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    info:SetPoint("TOPLEFT", 10, y - 5)
                    info:SetWidth(PANEL_WIDTH - 70)
                    info:SetJustifyH("LEFT")
                    info:SetText("|cff888888Dispel colors:\n• Magic = Blue\n• Curse = Purple\n• Disease = Brown\n• Poison = Green|r")
                    
                    y = CreateHeader(p, 10, y - 60, "Sorting (Midnight)")
                    local sortByOptions = {
                        { id = "default", name = "Default" },
                        { id = "duration", name = "Duration" },
                        { id = "name", name = "Name" },
                    }
                    y = CreateDropdown(p, 10, y, "Sort By", sortByOptions, 
                        function() return cfg.sortBy end, 
                        function(v) cfg.sortBy = v UpdateDebuffs() end)
                    
                    local sortDirOptions = {
                        { id = "normal", name = "Normal" },
                        { id = "reverse", name = "Reverse" },
                    }
                    y = CreateDropdown(p, 10, y, "Sort Direction", sortDirOptions, 
                        function() return cfg.sortDirection end, 
                        function(v) cfg.sortDirection = v UpdateDebuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Filtering")
                    y = CreateCheckbox(p, 10, y, "Hide Permanent Debuffs (no duration)",
                        function() return cfg.hidePermanent end, 
                        function(c) cfg.hidePermanent = c UpdateDebuffs() end)
                    -- Note: "Show Only My Debuffs" removed - sourceUnit is secret in Midnight
                end
            },
            {
                key = "visibility",
                label = "Visibility",
                builder = function(p)
                    local y = -10
                    
                    y = CreateCheckbox(p, 10, y, "Enable Visibility Conditions",
                        function() return cfg.visibilityEnabled end, 
                        function(c) cfg.visibilityEnabled = c UpdateDebuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Show When (OR logic)")
                    y = CreateCheckbox(p, 10, y, "In Combat", 
                        function() return cfg.showInCombat end, 
                        function(c) cfg.showInCombat = c UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "Out of Combat", 
                        function() return cfg.showOutOfCombat end, 
                        function(c) cfg.showOutOfCombat = c UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "Has Target", 
                        function() return cfg.showHasTarget end, 
                        function(c) cfg.showHasTarget = c UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "No Target", 
                        function() return cfg.showNoTarget end, 
                        function(c) cfg.showNoTarget = c UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "Solo", 
                        function() return cfg.showSolo end, 
                        function(c) cfg.showSolo = c UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "In Party", 
                        function() return cfg.showInParty end, 
                        function(c) cfg.showInParty = c UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "In Raid", 
                        function() return cfg.showInRaid end, 
                        function(c) cfg.showInRaid = c UpdateDebuffs() end)
                    y = CreateCheckbox(p, 10, y, "In Instance", 
                        function() return cfg.showInInstance end, 
                        function(c) cfg.showInInstance = c UpdateDebuffs() end)
                    
                    y = CreateHeader(p, 10, y - 10, "Fade")
                    y = CreateCheckbox(p, 10, y, "Enable Fade", 
                        function() return cfg.fadeEnabled end, 
                        function(c) cfg.fadeEnabled = c end)
                    y = CreateSlider(p, 10, y, "Fade Delay (sec)", 0, 10, 0.5, 
                        function() return cfg.fadeDelay end, 
                        function(v) cfg.fadeDelay = v end)
                    y = CreateSlider(p, 10, y, "Fade Alpha", 0, 1, 0.05, 
                        function() return cfg.fadeAlpha end, 
                        function(v) cfg.fadeAlpha = v end)
                end
            },
        }
        CreateTabbedSettingsPanel("debuffs", "Player Debuffs", tabs)
    end
end

-- Module Lifecycle
function PersonalResources:OnInitialize()
    local db = TUICD.Database:GetModuleSettings(self.id)
    if not db then
        db = DeepCopy(DEFAULT_SETTINGS)
        TUICD.Database:SetModuleSettings(self.id, db)
    end
    EnsureDefaults(db, DEFAULT_SETTINGS)
    settings = db
    GetPlayerInfo()
end

function PersonalResources:OnEnable()
    if not settings then return end
    settings.enabled = true
    CreateHealthBar()
    CreatePowerBar()
    CreateClassPowerFrame()
    -- Soul fragment icon frame removed - now uses class power bar segments
    CreateBuffsFrame()
    CreateDebuffsFrame()
    RegisterEvents()
    C_Timer.After(0.1, HideBlizzardResourceFrames)
    if playerClass == "DEATHKNIGHT" then StartRuneUpdateTicker() end
    if playerClass == "DEMONHUNTER" then 
        StartSoulFragmentTicker()  -- Updates class power bar for Vengeance
        StartVoidMetamorphosisTicker()  -- Will only start if Devourer
    end
    if playerClass == "MONK" then StartStaggerUpdateTicker() end
    if playerClass == "SHAMAN" then StartMaelstromWeaponTicker() end
    C_Timer.After(0.2, RefreshAllBars)
    -- Additional delayed refresh to pick up global media settings
    C_Timer.After(0.6, function()
        if TUICD.Media and (TUICD.Media:IsUsingGlobalTexture() or TUICD.Media:IsUsingGlobalFont()) then
            RefreshAllBars()
        end
    end)
    
    -- Register with EditModeManager to hide during Edit Mode
    if TUICD.EditMode then
        TUICD.EditMode:RegisterReskinHandler("PersonalResources",
            function()  -- Hide
                -- Hide our custom resource bars
                if powerBarFrame then powerBarFrame:Hide() end
                if classPowerFrame then classPowerFrame:Hide() end
                if soulFragmentFrame then soulFragmentFrame:Hide() end
                if buffsFrame then buffsFrame:Hide() end
                if debuffsFrame then debuffsFrame:Hide() end
                -- Restore Blizzard resource frames temporarily
                ShowBlizzardResourceFrames()
            end,
            function()  -- Show
                -- Hide Blizzard frames again and show ours
                HideBlizzardResourceFrames()
                RefreshAllBars()
            end
        )
    end
    
    -- Register with Layout Mode (delayed to ensure frames are fully created)
    C_Timer.After(0.3, function()
        if TUICD.Layout then
            RegisterAllPersonalResourcesWithLayout()
        end
    end)
    
    TUICD:PrintDebug("Personal Resources enabled")
end

function PersonalResources:OnDisable()
    if not settings then return end
    settings.enabled = false
    UnregisterEvents()
    StopRuneUpdateTicker()
    StopSoulFragmentTicker()
    StopVoidMetamorphosisTicker()
    StopStaggerUpdateTicker()
    StopMaelstromWeaponTicker()
    if powerBarFrame then powerBarFrame:Hide() end
    if classPowerFrame then classPowerFrame:Hide() end
    if soulFragmentFrame then soulFragmentFrame:Hide() end
    if buffsFrame then buffsFrame:Hide() end
    if debuffsFrame then debuffsFrame:Hide() end
    ShowBlizzardResourceFrames()
    TUICD:Print("Personal Resources |cffff0000disabled|r")
end

-- Handle profile changes
function PersonalResources:OnProfileChanged(profileName)
    TUICD:PrintDebug("PersonalResources OnProfileChanged:", profileName)
    
    -- Invalidate settings cache
    settings = nil
    
    -- Reload settings from new profile
    local db = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.PERSONAL_RESOURCES)
    if not db then db = {} end
    EnsureDefaults(db, DEFAULT_SETTINGS)
    settings = db
    
    -- If module is enabled, refresh everything
    if self.enabled then
        RefreshAllBars()
    end
end

function PersonalResources:GetSettings() return settings end
function PersonalResources:SaveSettings() if settings then TUICD.Database:SetModuleSettings(self.id, settings) end end
function PersonalResources:RefreshAll() RefreshAllBars() end

-- ============================================================================
-- LAYOUT INTEGRATION
-- ============================================================================

RegisterResourceBarWithLayout = function(barType, frame, displayName)
    local Layout = TUICD.Layout
    local TUIFrame = TUICD.TUIFrame
    
    if not Layout or not TUIFrame then 
        return nil 
    end
    if not frame then 
        return nil 
    end
    if layoutWrappers[barType] then 
        return layoutWrappers[barType] 
    end
    
    local barSettings = settings[barType]
    if not barSettings then 
        return nil 
    end
    
    local width = frame:GetWidth() or 200
    local height = frame:GetHeight() or 30
    
    -- Ensure minimum size for aura containers
    if (barType == "buffs" or barType == "debuffs") and (width < 50 or height < 20) then
        width = 200
        height = 100
    end
    
    -- Get actual screen position of the frame (or calculate from settings)
    local x, y
    -- Create TUIFrame wrapper
    local wrapper = TUIFrame:New("resourcebar_" .. barType, {
        width = width,
        height = height,
        name = displayName,
    })
    
    if not wrapper then return nil end
    
    -- Get Layout saved position and apply it properly
    local layoutSettings = Layout:GetSettings()
    local savedPos = layoutSettings and layoutSettings.elements and layoutSettings.elements["resourcebar_" .. barType]
    
    if savedPos and savedPos.x ~= nil and savedPos.y ~= nil then
        -- Use Layout saved position (handles CENTER coords properly and fades in)
        wrapper:LoadSaveData(savedPos)
    else
        -- Fall back to settings position
        local point = barSettings.anchor or "CENTER"
        local posX = barSettings.positionX or 0
        local posY = barSettings.positionY or 0
        wrapper:SetPosition(point, UIParent, point, posX, posY)
    end
    
    -- Parent bar frame to wrapper
    frame:SetParent(wrapper.frame)
    frame:ClearAllPoints()
    
    -- For aura containers, anchor to TOPLEFT only (they resize dynamically)
    -- For other bars, stretch to fill the wrapper
    if barType == "buffs" or barType == "debuffs" then
        frame:SetPoint("TOPLEFT", wrapper.frame, "TOPLEFT", 0, 0)
    else
        frame:SetPoint("TOPLEFT", wrapper.frame, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", wrapper.frame, "BOTTOMRIGHT", 0, 0)
    end
    
    -- Register with Layout module
    Layout:RegisterElement("resourcebar_" .. barType, {
        name = displayName,
        category = Layout.CATEGORIES.RESOURCE_BARS,
        tuiFrame = wrapper,
        defaultPosition = { point = barSettings.anchor or "CENTER", x = barSettings.positionX or 0, y = barSettings.positionY or 0 },
        onPositionChanged = function(id, saveData)
            if saveData and settings[barType] then
                settings[barType].positionX = saveData.x
                settings[barType].positionY = saveData.y
                settings[barType].anchor = saveData.point or "CENTER"
            end
        end,
        -- NEW: Handle size changes from Layout size matching
        -- This ensures matched sizes are saved to module settings and persist across reloads
        onSizeChanged = function(id, newWidth, newHeight)
            if settings[barType] then
                local scale = settings.global and settings.global.scale or 1
                -- Save the unscaled size to settings
                if scale > 0 then
                    settings[barType].width = newWidth / scale
                    settings[barType].height = newHeight / scale
                else
                    settings[barType].width = newWidth
                    settings[barType].height = newHeight
                end
                
                if TUICD.PrintDebug then
                    TUICD:PrintDebug(string.format("PersonalResources: Saved matched size for %s: %.0fx%.0f (unscaled)", 
                        barType, settings[barType].width, settings[barType].height))
                end
            end
        end,
    })
    
    layoutWrappers[barType] = wrapper
    return wrapper
end

RegisterAllPersonalResourcesWithLayout = function()
    local Layout = TUICD.Layout
    local TUIFrame = TUICD.TUIFrame
    
    if not Layout then
        C_Timer.After(1, RegisterAllPersonalResourcesWithLayout)
        return
    end
    
    if not TUIFrame then
        return
    end
    
    -- Register health bar
    if healthBarFrame and not layoutWrappers["healthBar"] then
        RegisterResourceBarWithLayout("healthBar", healthBarFrame, "Health Bar")
    end
    
    -- Register power bar
    if powerBarFrame and not layoutWrappers["powerBar"] then
        RegisterResourceBarWithLayout("powerBar", powerBarFrame, "Power Bar")
    end
    
    -- Register class power
    if classPowerFrame and not layoutWrappers["classPower"] then
        RegisterResourceBarWithLayout("classPower", classPowerFrame, "Class Power")
    end
    
    -- Soul fragment icon frame removed - now uses class power bar segments
    
    -- Register buffs
    if buffsFrame and not layoutWrappers["buffs"] then
        RegisterResourceBarWithLayout("buffs", buffsFrame, "Player Buffs")
    end
    
    -- Register debuffs
    if debuffsFrame and not layoutWrappers["debuffs"] then
        RegisterResourceBarWithLayout("debuffs", debuffsFrame, "Player Debuffs")
    end
    
    -- Register Layout mode callbacks (only once)
    if not PersonalResources._layoutCallbacksRegistered then
        PersonalResources._layoutCallbacksRegistered = true
        
        Layout:RegisterCallback("OnLayoutModeEnter", function()
        -- Register any bars that weren't registered before (created after initial registration)
        local registered = false
        if healthBarFrame and not layoutWrappers["healthBar"] then
            RegisterResourceBarWithLayout("healthBar", healthBarFrame, "Health Bar")
            registered = true
        end
        if powerBarFrame and not layoutWrappers["powerBar"] then
            RegisterResourceBarWithLayout("powerBar", powerBarFrame, "Power Bar")
            registered = true
        end
        if classPowerFrame and not layoutWrappers["classPower"] then
            RegisterResourceBarWithLayout("classPower", classPowerFrame, "Class Power")
            registered = true
        end
        -- Soul fragment icon frame removed - now uses class power bar segments
        if buffsFrame and not layoutWrappers["buffs"] then
            RegisterResourceBarWithLayout("buffs", buffsFrame, "Player Buffs")
            registered = true
        end
        if debuffsFrame and not layoutWrappers["debuffs"] then
            RegisterResourceBarWithLayout("debuffs", debuffsFrame, "Player Debuffs")
            registered = true
        end
        
        -- Force show all bars and wrappers for positioning
        if healthBarFrame then
            healthBarFrame:Show()
            healthBarFrame:SetAlpha(1)
            if layoutWrappers["healthBar"] then
                layoutWrappers["healthBar"].frame:Show()
            end
        end
        if powerBarFrame then 
            powerBarFrame:Show()
            powerBarFrame:SetAlpha(1)
            if layoutWrappers["powerBar"] then
                layoutWrappers["powerBar"].frame:Show()
            end
        end
        if classPowerFrame then 
            classPowerFrame:Show()
            classPowerFrame:SetAlpha(1)
            if layoutWrappers["classPower"] then
                layoutWrappers["classPower"].frame:Show()
            end
        end
        -- Soul fragment icon frame removed - now uses class power bar segments
        if soulFragmentFrame then 
            soulFragmentFrame:Hide()
        end
        if buffsFrame then 
            buffsFrame:Show()
            buffsFrame:SetAlpha(1)
            if layoutWrappers["buffs"] then
                layoutWrappers["buffs"].frame:Show()
            end
        end
        if debuffsFrame then 
            debuffsFrame:Show()
            debuffsFrame:SetAlpha(1)
            if layoutWrappers["debuffs"] then
                layoutWrappers["debuffs"].frame:Show()
            end
        end
        
        -- If we registered new elements, force Layout to recreate overlays
        if registered then
            C_Timer.After(0.1, function()
                if Layout.CreateAllOverlays then
                    Layout:CreateAllOverlays()
                end
            end)
        end
    end)
    
    Layout:RegisterCallback("OnLayoutModeExit", function()
        -- Restore normal visibility
        RefreshAllBars()
    end)
    end  -- end of _layoutCallbacksRegistered check
end

-- Expose for external use
function PersonalResources:GetLayoutWrapper(barType)
    return layoutWrappers[barType]
end

TUICD.PersonalResources = PersonalResources

-- Register with Layout after module loads (only if enabled)
C_Timer.After(4, function()
    if TUICD.Database and TUICD.Database:IsModuleEnabled(TUICD.MODULE_IDS.PERSONAL_RESOURCES) then
        RegisterAllPersonalResourcesWithLayout()
    end
end)
