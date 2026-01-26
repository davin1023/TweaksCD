-- ============================================================================
-- TweaksUI: Cooldowns - Minimap Button
-- Draggable minimap button to access settings
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.MinimapButton = {}
local MinimapButton = TUICD.MinimapButton

-- ============================================================================
-- STATE
-- ============================================================================

local button = nil
local isDragging = false

-- ============================================================================
-- POSITION CALCULATION
-- ============================================================================

local function UpdateButtonPosition()
    if not button then return end
    
    local angle = TUICD.Database:GetGlobal("minimapButtonAngle") or 225
    
    -- Calculate radius based on minimap size
    local minimapWidth = Minimap:GetWidth() or 140
    local minimapHeight = Minimap:GetHeight() or 140
    local minimapRadius = math.min(minimapWidth, minimapHeight) / 2
    
    local radius = minimapRadius + 5  -- Sit slightly outside the edge
    local radian = math.rad(angle)
    local x = math.cos(radian) * radius
    local y = math.sin(radian) * radius
    
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- ============================================================================
-- BUTTON CREATION
-- ============================================================================

local function CreateButton()
    if button then return button end
    
    button = CreateFrame("Button", "TUICD_MinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    -- Border overlay (create first so we can position icon relative to visible area)
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(54, 54)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    
    -- Icon texture - offset to match the border's visual center
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)  -- Offset to align with border's visual center
    
    -- Try to use addon icon if it exists, otherwise use a default
    local iconPath = "Interface\\AddOns\\TweaksUI_Cooldowns\\Media\\Textures\\TweaksUI_Icon"
    if not icon:SetTexture(iconPath) then
        icon:SetTexture("Interface\\Icons\\Spell_Nature_TimeStop")
    end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Slight crop to remove icon border
    
    -- Circular mask - also offset to match
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(21, 21)
    mask:SetPoint("CENTER", button, "CENTER", 0, 1)  -- Match icon offset
    icon:AddMaskTexture(mask)
    
    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("TweaksUI: Cooldowns", 0, 0.8, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Left-click:|r Open settings", 1, 1, 1)
        GameTooltip:AddLine("|cff00ff00Right-click:|r Toggle Layout Mode", 1, 1, 1)
        GameTooltip:AddLine("|cff00ff00Drag:|r Move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click handler
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            TUICD:ToggleSettings()
        elseif btn == "RightButton" then
            if TUICD.Layout then
                TUICD.Layout:Toggle()
            elseif TUICD.LayoutUI then
                TUICD.LayoutUI:Toggle()
            end
        end
    end)
    
    -- Drag handling
    button:SetScript("OnDragStart", function(self)
        isDragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.deg(math.atan2(cy/scale - my, cx/scale - mx))
            TUICD.Database:SetGlobal("minimapButtonAngle", angle)
            UpdateButtonPosition()
        end)
    end)
    
    button:SetScript("OnDragStop", function(self)
        isDragging = false
        self:SetScript("OnUpdate", nil)
    end)
    
    return button
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function MinimapButton:Show()
    if button then
        button:Show()
    end
end

function MinimapButton:Hide()
    if button then
        button:Hide()
    end
end

function MinimapButton:Toggle()
    if button then
        if button:IsShown() then
            self:Hide()
        else
            self:Show()
        end
    end
end

function MinimapButton:IsShown()
    return button and button:IsShown()
end

function MinimapButton:SetShown(shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
    TUICD.Database:SetGlobal("showMinimapButton", shown)
end

function MinimapButton:Initialize()
    CreateButton()
    UpdateButtonPosition()
    
    -- Show or hide based on saved setting
    local showButton = TUICD.Database:GetGlobal("showMinimapButton")
    if showButton == nil then
        showButton = true  -- Default to shown
        TUICD.Database:SetGlobal("showMinimapButton", true)
    end
    
    if showButton then
        button:Show()
    else
        button:Hide()
    end
end

-- ============================================================================
-- SLASH COMMAND FOR MINIMAP BUTTON
-- ============================================================================

SLASH_TUICDMINIMAP1 = "/tuicdminimap"
SlashCmdList["TUICDMINIMAP"] = function(msg)
    msg = (msg or ""):lower():trim()
    
    if msg == "show" then
        MinimapButton:SetShown(true)
        TUICD:Print("Minimap button shown.")
    elseif msg == "hide" then
        MinimapButton:SetShown(false)
        TUICD:Print("Minimap button hidden.")
    elseif msg == "toggle" then
        local newState = not MinimapButton:IsShown()
        MinimapButton:SetShown(newState)
        TUICD:Print("Minimap button " .. (newState and "shown" or "hidden") .. ".")
    else
        -- Just toggle
        local newState = not MinimapButton:IsShown()
        MinimapButton:SetShown(newState)
        TUICD:Print("Minimap button " .. (newState and "shown" or "hidden") .. ". Use /tuicdminimap show|hide|toggle")
    end
end
