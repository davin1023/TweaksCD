-- ============================================================================
-- TweaksUI: Cooldowns - Constants
-- Core constants and configuration values
-- Version 3.0.0 - Unified Architecture
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Version info
TUICD.VERSION = "3.3.0"
TUICD.ADDON_NAME = ADDON_NAME

-- Build info - Midnight-only (12.0.0+)
TUICD.BUILD_VERSION = select(4, GetBuildInfo())
TUICD.MIN_WOW_VERSION = 120000
TUICD.EXPANSION = "Midnight"

-- Midnight is always true in 3.0+ (we require it)
TUICD.IS_MIDNIGHT = true

-- Module identifiers (cooldowns-focused subset)
TUICD.MODULE_IDS = {
    COOLDOWNS = "cooldowns",
    LAYOUT = "layout",
    BARS = "bars",
    PERSONAL_RESOURCES = "personalResources",
}

-- Module display names (for UI)
TUICD.MODULE_NAMES = {
    [TUICD.MODULE_IDS.COOLDOWNS] = "Cooldown Trackers",
    [TUICD.MODULE_IDS.LAYOUT] = "Layout",
    [TUICD.MODULE_IDS.BARS] = "Timer Bars",
    [TUICD.MODULE_IDS.PERSONAL_RESOURCES] = "Personal Resources",
}

-- Module load order
TUICD.MODULE_LOAD_ORDER = {
    TUICD.MODULE_IDS.LAYOUT,
    TUICD.MODULE_IDS.COOLDOWNS,
    TUICD.MODULE_IDS.BARS,
    TUICD.MODULE_IDS.PERSONAL_RESOURCES,
}

-- Events
TUICD.EVENTS = {
    -- Core initialization event (fired after all modules are initialized)
    INITIALIZED = "TUICD_INITIALIZED",
    MODULE_ENABLED = "TUICD_ModuleEnabled",
    MODULE_DISABLED = "TUICD_ModuleDisabled",
    SETTINGS_CHANGED = "TUICD_SettingsChanged",
    PROFILE_CHANGED = "TUICD_ProfileChanged",
    -- Profile system events
    PROFILE_SAVED = "TUICD_ProfileSaved",
    PROFILE_LOADED = "TUICD_ProfileLoaded",
    PROFILE_DELETED = "TUICD_ProfileDeleted",
    PROFILE_DIRTY = "TUICD_ProfileDirty",
    PROFILE_NEEDS_RELOAD = "TUICD_ProfileNeedsReload",
    PROFILE_SPEC_SWITCH_BLOCKED = "TUICD_ProfileSpecSwitchBlocked",
    PRESET_APPLIED = "TUICD_PresetApplied",
    PRESET_SAVED = "TUICD_PresetSaved",
    -- Midnight restriction events
    RESTRICTION_CHANGED = "TUICD_RestrictionChanged",
    SECRETS_ACTIVE = "TUICD_SecretsActive",
    SECRETS_INACTIVE = "TUICD_SecretsInactive",
    -- Bars module events
    BARS_SETTINGS_CHANGED = "TUICD_BarsSettingsChanged",
    BARS_DATA_UPDATED = "TUICD_BarsDataUpdated",
    -- BuffBars module events
    BUFFBARS_SETTINGS_CHANGED = "TUICD_BuffBarsSettingsChanged",
    BUFFBARS_DATA_UPDATED = "TUICD_BuffBarsDataUpdated",
}

-- Default colors
TUICD.COLORS = {
    PRIMARY = { r = 0, g = 0.8, b = 1 },       -- Cyan (TUI:CD brand)
    SECONDARY = { r = 0.5, g = 0.5, b = 0.5 },
    WARNING = { r = 1, g = 0.8, b = 0 },
    ERROR = { r = 1, g = 0.2, b = 0.2 },
    SUCCESS = { r = 0, g = 1, b = 0 },
}

-- Chat prefix for messages
TUICD.CHAT_PREFIX = "|cff00ccff[TUI:CD]|r "

-- Slash commands
TUICD.SLASH_COMMANDS = {
    "/tuicd",
    "/cmt",  -- Legacy CMT alias
}

-- Modules that require a reload to fully disable
TUICD.MODULES_REQUIRE_RELOAD = {
    [TUICD.MODULE_IDS.COOLDOWNS] = true,
}

-- ============================================================================
-- UI STANDARDS (Settings Panel Consistency)
-- ============================================================================

-- Standard panel dimensions
TUICD.UI = {
    -- Hub Panel (slightly smaller for fewer options)
    HUB_WIDTH = 200,
    HUB_HEIGHT = 350,
    
    -- Settings Panel (docked to hub)
    PANEL_WIDTH = 420,
    PANEL_HEIGHT = 600,
    
    -- Button dimensions
    BUTTON_HEIGHT = 28,
    BUTTON_SPACING = 6,
    
    -- Tab dimensions
    TAB_HEIGHT = 24,
    TAB_SPACING = 4,
    TAB_BAR_Y = -40,           -- Y offset from panel top
    TAB_CONTENT_Y = -72,       -- Y offset for content below tabs
    
    -- Control spacing
    CONTROL_SPACING = 26,      -- Vertical space between controls
    SLIDER_SPACING = 30,       -- Vertical space for sliders
    SECTION_SPACING = 16,      -- Space between sections
    CHECKBOX_SPACING = 26,     -- Vertical space for checkboxes
    DROPDOWN_SPACING = 50,     -- Vertical space for dropdowns
    
    -- Scroll content height (default)
    SCROLL_CHILD_HEIGHT = 800,
    
    -- Indentation
    INDENT = 20,               -- Indentation for sub-options
}

-- Standard colors
TUICD.UI.COLORS = {
    -- Tab colors
    TAB_ACTIVE = { r = 1, g = 0.82, b = 0 },       -- Gold
    TAB_INACTIVE = { r = 0.6, g = 0.6, b = 0.6 },  -- Grey
    TAB_HOVER = { r = 0.8, g = 0.8, b = 0.8 },     -- Light grey
    
    -- Tab backgrounds
    TAB_BG_ACTIVE = { r = 0.2, g = 0.2, b = 0.2, a = 0.8 },
    TAB_BG_INACTIVE = { r = 0.1, g = 0.1, b = 0.1, a = 0.5 },
    TAB_BG_HOVER = { r = 0.15, g = 0.15, b = 0.15, a = 0.7 },
    
    -- Headers
    HEADER = { r = 1, g = 0.82, b = 0 },           -- Gold (|cffffcc00)
    SECTION_LABEL = { r = 0.67, g = 0.67, b = 0.67 },  -- Grey (|cffaaaaaa)
    MUTED = { r = 0.53, g = 0.53, b = 0.53 },      -- Dark grey (|cff888888)
    
    -- Status
    ENABLED = { r = 0, g = 1, b = 0 },             -- Green
    DISABLED = { r = 1, g = 0.2, b = 0.2 },        -- Red
    WARNING = { r = 1, g = 0.8, b = 0 },           -- Yellow
}

-- Standard backdrop (used by ALL settings panels)
TUICD.UI.DARK_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
}

-- Backdrop colors
TUICD.UI.BACKDROP_COLOR = { r = 0.08, g = 0.08, b = 0.08, a = 0.95 }
TUICD.UI.BACKDROP_BORDER_COLOR = { r = 0.4, g = 0.4, b = 0.4, a = 1 }

-- ============================================================================
-- STANDARD TAB NAMES (use these for consistency)
-- ============================================================================

TUICD.UI.TABS = {
    -- Common tabs (in display order)
    LAYOUT = "Layout",
    APPEARANCE = "Appearance", 
    TEXT = "Text",
    VISIBILITY = "Visibility",
    
    -- Module-specific tabs
    PER_ICON = "Per-Icon",
    ENTRIES = "Entries",
    COLORS = "Colors",
    CUSTOM = "Custom",
    
    -- Resource bar tabs (for future Personal Resources)
    SIZE = "Size",
    BAR_COLOR = "Color",
}

-- ============================================================================
-- STANDARD SECTION HEADERS (use these for consistency)
-- ============================================================================

TUICD.UI.HEADERS = {
    -- Layout sections
    SIZE = "Size",
    GRID_LAYOUT = "Grid Layout",
    GROWTH_DIRECTION = "Growth Direction",
    POSITION = "Position",
    
    -- Appearance sections
    COLORS = "Colors",
    BORDER = "Border",
    BACKGROUND = "Background",
    TEXTURES = "Textures",
    
    -- Text sections
    TEXT_SETTINGS = "Text Settings",
    FONT = "Font",
    COOLDOWN_TEXT = "Cooldown Text",
    COUNT_TEXT = "Count Text",
    
    -- Visibility sections
    VISIBILITY_CONDITIONS = "Visibility Conditions",
    FADE_SETTINGS = "Fade Settings",
    
    -- Other common sections
    BEHAVIOR = "Behavior",
    INTERACTION = "Interaction",
}
