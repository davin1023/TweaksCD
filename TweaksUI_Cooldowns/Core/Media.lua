-- TUICD Media
-- Shared textures, fonts, sounds, and media management via LibSharedMedia-3.0

local ADDON_NAME, TUICD = ...

TUICD.Media = {}
local Media = TUICD.Media

-- Paths
local MEDIA_PATH = "Interface\\AddOns\\TweaksUI_Cooldowns\\Media\\"
local TEXTURE_PATH = MEDIA_PATH .. "Textures\\"
local FONT_PATH = MEDIA_PATH .. "Fonts\\"
local SOUND_PATH = MEDIA_PATH .. "Sounds\\"

-- LibSharedMedia reference
local LSM = nil

-- Built-in textures (registered with LSM on init)
Media.BuiltInTextures = {
    ["TUICD Flat"] = "Interface\\Buttons\\WHITE8x8",
    ["TUICD Classic WoW"] = TEXTURE_PATH .. "TUI_ClassicWoW",
    ["TUICD Embossed"] = TEXTURE_PATH .. "TUI_Embossed",
    ["TUICD Glass"] = TEXTURE_PATH .. "TUI_Glass",
    ["TUICD Glow Edge"] = TEXTURE_PATH .. "TUI_GlowEdge",
    ["TUICD Hard Bevel"] = TEXTURE_PATH .. "TUI_HardBevel",
    ["TUICD Soft Bevel"] = TEXTURE_PATH .. "TUI_SoftBevel",
    ["TUICD Soft Gradient"] = TEXTURE_PATH .. "TUI_SoftGradient",
}

-- Built-in fonts (registered with LSM on init)
Media.BuiltInFonts = {
    -- LSM already registers the default Blizzard fonts
    -- Add custom fonts here if bundled in Media/Fonts/
}

-- Built-in sounds (registered with LSM on init)
-- Blizzard sound file IDs that work with PlaySoundFile(fileID, channel)
Media.BuiltInSounds = {
    -- Alert / Notification
    ["TUI: Arrow Whoosh"]       = 567415,   -- UI_BNet_Toast
    ["TUI: Quest Complete"]     = 567439,   -- UI_QuestComplete
    ["TUI: Quest Activate"]     = 567400,   -- UI_QuestActivate
    ["TUI: Power Aura"]         = 569593,   -- UI_PowerAura_Generic
    ["TUI: Level Up"]           = 567431,   -- UI_LevelUp
    ["TUI: Raid Warning"]       = 567397,   -- UI_RaidBossWhisper
    ["TUI: PvP Flag"]           = 569200,   -- PVP_FlagTakenAlliance
    ["TUI: Ready Check"]        = 567478,   -- ReadyCheck
    -- Subtle / Soft
    ["TUI: Map Ping"]           = 567416,   -- UI_BNet_PM
    ["TUI: Loot Coin"]          = 567428,   -- LOOTWINDOWOPENCOINSOUND
    ["TUI: Enchant"]            = 567384,   -- ENCHANT_COMPLETE
    -- Combat / Action
    ["TUI: Proc"]               = 568975,   -- PROC_BLOODLUST
    ["TUI: Spell Fizzle"]       = 569772,   -- SPELL_FIZZLE
    ["TUI: Crowd Roar"]         = 569310,   -- PVP_CROWD_ROAR
}

-- Legacy texture paths (for backwards compatibility)
Media.LegacyTexturePaths = {
    ["Interface\\TargetingFrame\\UI-StatusBar"] = "Blizzard",
    ["Interface\\Buttons\\WHITE8x8"] = "TUICD Flat",
    ["Interface\\Buttons\\WHITE8X8"] = "TUICD Flat",
}

-- Legacy font paths (for backwards compatibility)
Media.LegacyFontPaths = {
    ["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata TT",
    ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
    ["Fonts\\MORPHEUS.TTF"] = "Morpheus",
    ["Fonts\\SKURRI.TTF"] = "Skurri",
}

-- Defaults
Media.DEFAULT_STATUSBAR = "Blizzard"
Media.DEFAULT_FONT = "Friz Quadrata TT"
Media.DEFAULT_SOUND = "None"
Media.DEFAULT_BACKGROUND = "Blizzard Dialog Background"
Media.DEFAULT_BORDER = "Blizzard Tooltip"

function Media:Initialize()
    -- Get LibSharedMedia (should always succeed since we bundle it)
    if LibStub then
        LSM = LibStub("LibSharedMedia-3.0", true)
    end
    
    if LSM then
        -- Register our custom textures with LSM
        for name, path in pairs(Media.BuiltInTextures) do
            LSM:Register("statusbar", name, path)
        end
        
        -- Register our custom fonts with LSM
        for name, path in pairs(Media.BuiltInFonts) do
            LSM:Register("font", name, path)
        end
        
        -- Register our custom sounds with LSM (only string paths, not fileIDs)
        for name, path in pairs(Media.BuiltInSounds) do
            if type(path) == "string" then
                LSM:Register("sound", name, path)
            end
        end
        
        -- Print counts (always, for debugging)
        local textureCount = LSM:List("statusbar") and #LSM:List("statusbar") or 0
        local fontCount = LSM:List("font") and #LSM:List("font") or 0
        local soundCount = LSM:List("sound") and #LSM:List("sound") or 0
        TUICD:PrintDebug("Media loaded: " .. textureCount .. " textures, " .. fontCount .. " fonts, " .. soundCount .. " sounds")
    else
        TUICD:PrintError("LibSharedMedia-3.0 not found - media selection will be limited")
    end
end

-- Debug command to list available media
function Media:PrintMediaList(mediaType)
    if not LSM then
        TUICD:Print("LSM not available")
        return
    end
    
    mediaType = mediaType or "statusbar"
    local list = LSM:List(mediaType)
    if list then
        TUICD:Print(mediaType .. " (" .. #list .. "):")
        for i, name in ipairs(list) do
            print("  " .. i .. ". " .. name)
        end
    else
        TUICD:Print("No " .. mediaType .. " found")
    end
end

-- ============================================================================
-- STATUS BAR TEXTURES
-- ============================================================================

-- Get a status bar texture path from a texture name
-- @param name string - The texture name (e.g., "Blizzard", "TUICD Flat")
-- @return string - The texture path
function Media:GetStatusBarTexture(name)
    -- Handle nil/empty
    if not name or name == "" then
        return self:GetStatusBarTexture(Media.DEFAULT_STATUSBAR)
    end
    
    -- If it looks like a path (contains backslash), try to convert it to a name
    if string.find(name, "\\") then
        local convertedName = Media.LegacyTexturePaths[name]
        if convertedName then
            name = convertedName
        else
            -- It's a custom path, return as-is
            return name
        end
    end
    
    -- If LSM is available and has this texture, use it
    if LSM and LSM:IsValid("statusbar", name) then
        return LSM:Fetch("statusbar", name)
    end
    
    -- Check our built-in textures
    if Media.BuiltInTextures[name] then
        return Media.BuiltInTextures[name]
    end
    
    -- Default fallback
    if LSM then
        return LSM:Fetch("statusbar", Media.DEFAULT_STATUSBAR)
    end
    
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

-- Get sorted list of status bar texture names (for dropdowns)
-- @return table - Array of texture names, sorted alphabetically
function Media:GetStatusBarList()
    if LSM then
        return LSM:List("statusbar")
    end
    
    -- Fallback if LSM not available
    local list = {}
    for name in pairs(Media.BuiltInTextures) do
        table.insert(list, name)
    end
    table.insert(list, "Blizzard")
    table.sort(list)
    return list
end

-- Check if a status bar texture name is valid
function Media:IsValidStatusBar(name)
    if not name then return false end
    if LSM then
        return LSM:IsValid("statusbar", name)
    end
    return Media.BuiltInTextures[name] ~= nil
end

-- ============================================================================
-- FONTS
-- ============================================================================

-- Get a font path from a font name
-- @param name string - The font name (e.g., "Friz Quadrata TT", "Arial Narrow")
-- @return string - The font path
function Media:GetFont(name)
    -- Handle nil/empty
    if not name or name == "" then
        return self:GetFont(Media.DEFAULT_FONT)
    end
    
    -- If it looks like a path (contains backslash), try to convert it to a name
    if string.find(name, "\\") then
        local convertedName = Media.LegacyFontPaths[name]
        if convertedName then
            name = convertedName
        else
            -- It's a custom path, return as-is
            return name
        end
    end
    
    -- If LSM is available and has this font, use it
    if LSM and LSM:IsValid("font", name) then
        return LSM:Fetch("font", name)
    end
    
    -- Check our built-in fonts
    if Media.BuiltInFonts[name] then
        return Media.BuiltInFonts[name]
    end
    
    -- Default fallback
    if LSM then
        return LSM:Fetch("font", Media.DEFAULT_FONT)
    end
    
    return "Fonts\\FRIZQT__.TTF"
end

-- Get sorted list of font names (for dropdowns)
-- @return table - Array of font names, sorted alphabetically
function Media:GetFontList()
    if LSM then
        return LSM:List("font")
    end
    
    -- Fallback if LSM not available
    local list = {"Friz Quadrata TT", "Arial Narrow", "Morpheus", "Skurri"}
    table.sort(list)
    return list
end

-- Check if a font name is valid
function Media:IsValidFont(name)
    if not name then return false end
    if LSM then
        return LSM:IsValid("font", name)
    end
    return Media.BuiltInFonts[name] ~= nil or Media.LegacyFontPaths["Fonts\\" .. name] ~= nil
end

-- ============================================================================
-- SOUNDS
-- ============================================================================

-- Get a sound file path from a sound name
-- @param name string - The sound name (e.g., "Whisper", "None")
-- @return string|nil - The sound path, or nil if "None"
function Media:GetSound(name)
    -- Handle nil/empty/None
    if not name or name == "" or name == "None" then
        return nil
    end
    
    -- If LSM is available and has this sound, use it
    if LSM and LSM:IsValid("sound", name) then
        return LSM:Fetch("sound", name)
    end
    
    -- Check our built-in sounds
    if Media.BuiltInSounds[name] then
        return Media.BuiltInSounds[name]
    end
    
    return nil
end

-- Get sorted list of sound names (for dropdowns)
-- @return table - Array of sound names, sorted alphabetically
function Media:GetSoundList()
    if LSM then
        return LSM:List("sound")
    end
    
    -- Fallback if LSM not available
    local list = {"None"}
    for name in pairs(Media.BuiltInSounds) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

-- Check if a sound name is valid
function Media:IsValidSound(name)
    if not name or name == "None" then return true end  -- None is always valid
    if LSM then
        return LSM:IsValid("sound", name)
    end
    return Media.BuiltInSounds[name] ~= nil
end

-- Play a sound by name
-- @param name string - The sound name from LSM
-- @param channel string - Optional sound channel ("Master", "SFX", "Music", "Ambience", "Dialog")
function Media:PlaySound(name, channel)
    local soundPath = self:GetSound(name)
    if soundPath then
        PlaySoundFile(soundPath, channel or "Master")
    end
end

-- Get sorted list of sounds with TUI presets first, then LSM sounds
-- @return table - Array: {"None", "TUI: ...", "TUI: ...", ..., "LSM Sound 1", ...}
function Media:GetSoundListWithPresets()
    local list = {"None"}
    -- Add our presets first (sorted)
    local presets = {}
    for name in pairs(Media.BuiltInSounds) do
        table.insert(presets, name)
    end
    table.sort(presets)
    for _, name in ipairs(presets) do
        table.insert(list, name)
    end
    -- Add LSM sounds (skip duplicates already registered from our presets)
    if LSM then
        local lsmList = LSM:List("sound")
        if lsmList then
            for _, name in ipairs(lsmList) do
                if not Media.BuiltInSounds[name] then
                    table.insert(list, name)
                end
            end
        end
    end
    return list
end

-- Debounced alert sound playback (prevents spam when many icons transition at once)
local soundLastPlayed = {}
local SOUND_COOLDOWN = 0.1  -- seconds between same sound

function Media:PlayAlertSound(name)
    if not name or name == "" or name == "None" then return end
    local now = GetTime()
    if soundLastPlayed[name] and (now - soundLastPlayed[name]) < SOUND_COOLDOWN then
        return  -- Debounce
    end
    soundLastPlayed[name] = now
    self:PlaySound(name, "Master")
end

-- ============================================================================
-- BACKGROUNDS & BORDERS
-- ============================================================================

-- Get a background texture path
-- @param name string - The background name
-- @return string - The background texture path
function Media:GetBackground(name)
    if not name or name == "" then
        name = Media.DEFAULT_BACKGROUND
    end
    
    if LSM and LSM:IsValid("background", name) then
        return LSM:Fetch("background", name)
    end
    
    return "Interface\\DialogFrame\\UI-DialogBox-Background"
end

-- Get sorted list of background names
-- @return table - Array of background names
function Media:GetBackgroundList()
    if LSM then
        return LSM:List("background")
    end
    return {"Blizzard Dialog Background", "Solid"}
end

-- Check if a background name is valid
function Media:IsValidBackground(name)
    if not name then return false end
    if LSM then
        return LSM:IsValid("background", name)
    end
    return false
end

-- Get a border texture path
-- @param name string - The border name
-- @return string - The border texture path
function Media:GetBorder(name)
    if not name or name == "" or name == "None" then
        return nil
    end
    
    if LSM and LSM:IsValid("border", name) then
        return LSM:Fetch("border", name)
    end
    
    return "Interface\\Tooltips\\UI-Tooltip-Border"
end

-- Get sorted list of border names
-- @return table - Array of border names
function Media:GetBorderList()
    if LSM then
        return LSM:List("border")
    end
    return {"None", "Blizzard Tooltip"}
end

-- Check if a border name is valid
function Media:IsValidBorder(name)
    if not name or name == "None" then return true end
    if LSM then
        return LSM:IsValid("border", name)
    end
    return false
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Check if LSM is available
function Media:HasSharedMedia()
    return LSM ~= nil
end

-- Get raw LSM reference (for advanced usage)
function Media:GetLSM()
    return LSM
end

-- Convert a legacy texture path to a texture name
-- Returns nil if not a recognized legacy path
function Media:ConvertLegacyTexturePath(path)
    if not path then return nil end
    return Media.LegacyTexturePaths[path]
end

-- Convert a legacy font path to a font name
-- Returns nil if not a recognized legacy path
function Media:ConvertLegacyFontPath(path)
    if not path then return nil end
    return Media.LegacyFontPaths[path]
end

-- Register a callback for when new media is registered
-- Useful for refreshing dropdowns when user installs new texture packs
-- @param callback function - Called with (mediaType, name) when media is registered
function Media:RegisterCallback(callback)
    if LSM then
        LSM.RegisterCallback(self, "LibSharedMedia_Registered", callback)
    end
end

-- Unregister callbacks
function Media:UnregisterCallback()
    if LSM then
        LSM.UnregisterCallback(self, "LibSharedMedia_Registered")
    end
end

-- ============================================================================
-- GLOBAL FONT SYSTEM
-- ============================================================================

-- Get the global font name (if enabled)
-- @return string|nil - Global font name, or nil if not using global font
function Media:GetGlobalFontName()
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings and settings.mediaSettings.useGlobalFont then
            return settings.mediaSettings.globalFont
        end
    end
    return nil
end

-- Get font path, respecting global font setting
-- @param moduleFontName string - The module's specific font setting (or nil)
-- @return string - The font path to use
function Media:GetFontWithGlobal(moduleFontName)
    local globalFont = self:GetGlobalFontName()
    if globalFont then
        return self:GetFont(globalFont)
    end
    return self:GetFont(moduleFontName)
end

-- Check if global font override is enabled
function Media:IsUsingGlobalFont()
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            return settings.mediaSettings.useGlobalFont
        end
    end
    return false
end

-- Set global font (convenience function)
function Media:SetGlobalFont(fontName)
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            settings.mediaSettings.globalFont = fontName
        end
    end
end

-- Enable/disable global font override
function Media:SetUseGlobalFont(enabled)
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            settings.mediaSettings.useGlobalFont = enabled
        end
    end
end

-- Get the global font outline (if global font is enabled)
-- @return string|nil - Outline flag ("", "OUTLINE", "THICKOUTLINE"), or nil if not using global font
function Media:GetGlobalFontOutline()
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings and settings.mediaSettings.useGlobalFont then
            return settings.mediaSettings.globalFontOutline or "OUTLINE"
        end
    end
    return nil
end

-- Get font outline, respecting global font setting
-- @param moduleOutline string - The module's specific outline setting (or nil)
-- @return string - The outline flag to use
function Media:GetOutlineWithGlobal(moduleOutline)
    local globalOutline = self:GetGlobalFontOutline()
    if globalOutline then
        return globalOutline
    end
    return moduleOutline or "OUTLINE"
end

-- Set global font outline (convenience function)
function Media:SetGlobalFontOutline(outline)
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            settings.mediaSettings.globalFontOutline = outline
        end
    end
end

-- ============================================================================
-- GLOBAL TEXTURE SYSTEM
-- ============================================================================

-- Get the global texture name (if enabled)
-- @return string|nil - Global texture name, or nil if not using global texture
function Media:GetGlobalTextureName()
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings and settings.mediaSettings.useGlobalTexture then
            return settings.mediaSettings.globalTexture
        end
    end
    return nil
end

-- Get texture path, respecting global texture setting
-- @param moduleTextureName string - The module's specific texture setting (or nil)
-- @return string - The texture path to use
function Media:GetTextureWithGlobal(moduleTextureName)
    local globalTexture = self:GetGlobalTextureName()
    if globalTexture then
        return self:GetStatusBarTexture(globalTexture)
    end
    return self:GetStatusBarTexture(moduleTextureName)
end

-- Check if global texture override is enabled
function Media:IsUsingGlobalTexture()
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            return settings.mediaSettings.useGlobalTexture
        end
    end
    return false
end

-- Set global texture (convenience function)
function Media:SetGlobalTexture(textureName)
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            settings.mediaSettings.globalTexture = textureName
        end
    end
end

-- Enable/disable global texture override
function Media:SetUseGlobalTexture(enabled)
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            settings.mediaSettings.useGlobalTexture = enabled
        end
    end
end

-- ============================================================================
-- GLOBAL ICON EDGE STYLE SYSTEM
-- ============================================================================

-- Get the global icon edge style (if enabled)
-- @return string|nil - Global icon edge style ("sharp", "rounded", "square"), or nil if not using global
function Media:GetGlobalIconEdgeStyle()
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings and settings.mediaSettings.useGlobalIconEdgeStyle then
            return settings.mediaSettings.globalIconEdgeStyle
        end
    end
    return nil
end

-- Check if global icon edge style override is enabled
function Media:IsUsingGlobalIconEdgeStyle()
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            return settings.mediaSettings.useGlobalIconEdgeStyle == true
        end
    end
    return false
end

-- Get icon edge style, respecting global override
-- @param moduleStyle string - Module-specific icon edge style
-- @return string - Icon edge style to use
function Media:GetIconEdgeStyleWithGlobal(moduleStyle)
    local globalStyle = self:GetGlobalIconEdgeStyle()
    if globalStyle then
        return globalStyle
    end
    return moduleStyle or "sharp"
end

-- Set global icon edge style (convenience function)
function Media:SetGlobalIconEdgeStyle(style)
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            settings.mediaSettings.globalIconEdgeStyle = style
        end
    end
end

-- Enable/disable global icon edge style override
function Media:SetUseGlobalIconEdgeStyle(enabled)
    if TUICD.General then
        local settings = TUICD.General:GetSettings()
        if settings and settings.mediaSettings then
            settings.mediaSettings.useGlobalIconEdgeStyle = enabled
        end
    end
end

-- ============================================================================
-- UI HELPERS
-- ============================================================================

-- Create a font dropdown with each font rendered in its own style
-- @param parent Frame - Parent frame for the dropdown
-- @param name string - Unique global name for the dropdown
-- @param x number - X offset
-- @param y number - Y offset  
-- @param width number - Dropdown width (default 180)
-- @param currentFont string - Current font name
-- @param onChange function - Callback when font changes, receives (fontName)
-- @return dropdown Frame
function Media:CreateFontDropdown(parent, name, x, y, width, currentFont, onChange)
    width = width or 180
    currentFont = currentFont or "Friz Quadrata TT"
    
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_SetText(dropdown, currentFont)
    
    -- Store current value
    dropdown.currentFont = currentFont
    
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local fontList = Media:GetFontList()
        for _, fontName in ipairs(fontList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = fontName
            info.checked = (dropdown.currentFont == fontName)
            info.func = function()
                dropdown.currentFont = fontName
                UIDropDownMenu_SetText(dropdown, fontName)
                if onChange then
                    onChange(fontName)
                end
            end
            UIDropDownMenu_AddButton(info)
        end
        
        -- After adding buttons, set each one's font to display in its own style
        C_Timer.After(0.01, function()
            local listFrame = _G["DropDownList1"]
            if listFrame and listFrame:IsShown() then
                for i = 1, 30 do
                    local button = _G["DropDownList1Button" .. i]
                    if button and button:IsShown() then
                        local buttonText = _G["DropDownList1Button" .. i .. "NormalText"]
                        if buttonText then
                            local fontName = buttonText:GetText()
                            if fontName then
                                local fontPath = Media:GetFont(fontName)
                                if fontPath then
                                    pcall(function()
                                        buttonText:SetFont(fontPath, 12, "")
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end)
    
    dropdown.GetSelectedFont = function(self)
        return self.currentFont
    end
    
    dropdown.SetSelectedFont = function(self, fontName)
        self.currentFont = fontName
        UIDropDownMenu_SetText(self, fontName)
    end
    
    return dropdown
end

-- Create a texture dropdown with preview
function Media:CreateTextureDropdown(parent, name, x, y, width, currentTexture, onChange)
    width = width or 180
    currentTexture = currentTexture or "Blizzard"
    
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_SetText(dropdown, currentTexture)
    dropdown.currentTexture = currentTexture
    
    -- Preview bar
    local previewBar = CreateFrame("StatusBar", nil, parent)
    previewBar:SetPoint("LEFT", dropdown, "RIGHT", 5, 2)
    previewBar:SetSize(80, 14)
    previewBar:SetMinMaxValues(0, 1)
    previewBar:SetValue(0.7)
    previewBar:SetStatusBarTexture(Media:GetStatusBarTexture(currentTexture))
    previewBar:SetStatusBarColor(0, 0.8, 0.2, 1)
    
    local previewBg = previewBar:CreateTexture(nil, "BACKGROUND")
    previewBg:SetAllPoints()
    previewBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    dropdown.previewBar = previewBar
    
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local textureList = Media:GetStatusBarList()
        for _, texName in ipairs(textureList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = texName
            info.checked = (dropdown.currentTexture == texName)
            info.func = function()
                dropdown.currentTexture = texName
                UIDropDownMenu_SetText(dropdown, texName)
                previewBar:SetStatusBarTexture(Media:GetStatusBarTexture(texName))
                if onChange then
                    onChange(texName)
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    dropdown.GetSelectedTexture = function(self)
        return self.currentTexture
    end
    
    dropdown.SetSelectedTexture = function(self, texName)
        self.currentTexture = texName
        UIDropDownMenu_SetText(self, texName)
        previewBar:SetStatusBarTexture(Media:GetStatusBarTexture(texName))
    end
    
    return dropdown, previewBar
end

-- Create a sound dropdown with play button
function Media:CreateSoundDropdown(parent, name, x, y, width, currentSound, onChange)
    width = width or 180
    currentSound = currentSound or "None"
    
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_SetText(dropdown, currentSound)
    dropdown.currentSound = currentSound
    
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local soundList = Media:GetSoundListWithPresets()
        for _, soundName in ipairs(soundList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = soundName
            info.checked = (dropdown.currentSound == soundName)
            info.func = function()
                dropdown.currentSound = soundName
                UIDropDownMenu_SetText(dropdown, soundName)
                if onChange then
                    onChange(soundName)
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    -- Enable scrolling for large sound lists
    
    -- Play button
    local playBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    playBtn:SetPoint("LEFT", dropdown, "RIGHT", -5, 2)
    playBtn:SetSize(50, 22)
    playBtn:SetText("Play")
    playBtn:SetScript("OnClick", function()
        if dropdown.currentSound and dropdown.currentSound ~= "None" then
            Media:PlaySound(dropdown.currentSound)
        end
    end)
    
    dropdown.GetSelectedSound = function(self)
        return self.currentSound
    end
    
    dropdown.SetSelectedSound = function(self, soundName)
        self.currentSound = soundName
        UIDropDownMenu_SetText(self, soundName)
    end
    
    return dropdown, playBtn
end
