-- ============================================================================
-- TweaksUI: Cooldowns - MultiTracker Frames
-- Frame rendering and cooldown management for multi-tracker system
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Wait for MultiTracker data layer to exist
if not TUICD.MultiTracker then
    C_Timer.After(0.5, function()
        if not TUICD.MultiTracker then
            print("|cffff0000[TUI:CD]|r MultiTrackerFrames requires MultiTracker.lua to be loaded first")
        end
    end)
    return
end

local MultiTracker = TUICD.MultiTracker
local MultiTrackerFrames = {}
TUICD.MultiTrackerFrames = MultiTrackerFrames

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local UPDATE_INTERVAL = 1.0  -- Fallback ticker (1 Hz, events handle most updates)
local GCD_THRESHOLD = 2.0    -- Filter out GCD from desaturation

-- Throttle for cooldown updates (events can fire rapidly)
local lastCooldownUpdate = 0
local COOLDOWN_THROTTLE = 0.1  -- 100ms throttle (was 50ms)

-- ============================================================================
-- STATE
-- ============================================================================

local trackerFrames = {}     -- [trackerKey] = frame
local trackerIcons = {}      -- [trackerKey] = { [entryKey] = iconFrame }
local updateTicker = nil
local enabled = false

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function dprint(msg)
    if TUICD.debugMode then
        print("|cff00ff00[TUI:CD MultiFrames]|r " .. msg)
    end
end

-- Apply edge style with proper aspect ratio cropping (zoom into texture, not stretch)
local function ApplyIconEdgeStyle(iconFrame, trackerKey, iconWidth, iconHeight)
    local icon = iconFrame.icon or iconFrame.Icon
    if not icon or not icon.SetTexCoord then return end
    
    local edgeStyle = MultiTracker:GetSetting(trackerKey, "iconEdgeStyle") or "sharp"
    local zoom = MultiTracker:GetSetting(trackerKey, "zoom") or 0.08
    local iconMask = iconFrame.iconMask
    
    -- Remove existing mask first
    if iconMask then
        pcall(function() icon:RemoveMaskTexture(iconMask) end)
    end
    
    if edgeStyle == "rounded" then
        -- Full texture for mask-based rounding, but still apply aspect ratio crop
        local left, right, top, bottom = 0, 1, 0, 1
        
        if iconWidth and iconHeight and iconWidth ~= iconHeight then
            if iconWidth > iconHeight then
                local cropAmount = (1 - iconHeight / iconWidth) / 2
                top = cropAmount
                bottom = 1 - cropAmount
            elseif iconHeight > iconWidth then
                local cropAmount = (1 - iconWidth / iconHeight) / 2
                left = cropAmount
                right = 1 - cropAmount
            end
        end
        
        icon:SetTexCoord(left, right, top, bottom)
        
        -- Apply mask
        if iconMask then
            pcall(function() icon:AddMaskTexture(iconMask) end)
        end
    elseif edgeStyle == "square" then
        -- No zoom, but apply aspect ratio crop
        local left, right, top, bottom = 0, 1, 0, 1
        
        if iconWidth and iconHeight and iconWidth ~= iconHeight then
            if iconWidth > iconHeight then
                local cropAmount = (1 - iconHeight / iconWidth) / 2
                top = cropAmount
                bottom = 1 - cropAmount
            elseif iconHeight > iconWidth then
                local cropAmount = (1 - iconWidth / iconHeight) / 2
                left = cropAmount
                right = 1 - cropAmount
            end
        end
        
        icon:SetTexCoord(left, right, top, bottom)
    else
        -- "sharp" (default) - zoom with aspect ratio cropping
        local left = zoom
        local right = 1 - zoom
        local top = zoom
        local bottom = 1 - zoom
        
        if iconWidth and iconHeight and iconWidth ~= iconHeight then
            if iconWidth > iconHeight then
                local cropAmount = (1 - iconHeight / iconWidth) / 2
                top = top + cropAmount * (1 - 2 * zoom)
                bottom = bottom - cropAmount * (1 - 2 * zoom)
            elseif iconHeight > iconWidth then
                local cropAmount = (1 - iconWidth / iconHeight) / 2
                left = left + cropAmount * (1 - 2 * zoom)
                right = right - cropAmount * (1 - 2 * zoom)
            end
        end
        
        icon:SetTexCoord(left, right, top, bottom)
    end
end

-- Get entry display info (texture, name, tracking info)
local function GetEntryDisplayInfo(entry)
    if not entry then return nil, nil, nil end
    
    if entry.type == "spell" then
        local spellInfo = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellInfo(entry.id)
        local texture = TUICD.SpellAPI and TUICD.SpellAPI:GetSpellTexture(entry.id)
        local name = spellInfo and spellInfo.name or ("Spell " .. entry.id)
        return name, texture, entry.id
        
    elseif entry.type == "item" then
        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(entry.id)
        return itemName or ("Item " .. entry.id), itemTexture, entry.id
        
    elseif entry.type == "equipped" then
        local slotID = entry.id
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            local texture = itemTexture or GetInventoryItemTexture("player", slotID)
            return itemName or ("Slot " .. slotID), texture, itemID
        else
            return "Empty Slot " .. slotID, GetInventoryItemTexture("player", slotID), nil
        end
    end
    
    return nil, nil, nil
end

-- Get tracking type and ID for cooldown queries
local function GetEntryTrackingID(entry)
    if not entry then return nil, nil end
    
    if entry.type == "spell" then
        return "spell", entry.id
    elseif entry.type == "item" then
        return "item", entry.id
    elseif entry.type == "equipped" then
        local itemID = GetInventoryItemID("player", entry.id)
        return "item", itemID
    end
    
    return nil, nil
end

-- Check if item has on-use ability
local function HasOnUseAbility(itemID)
    if not itemID then return false end
    local spellName, spellID = GetItemSpell(itemID)
    return spellName ~= nil or spellID ~= nil
end

-- ============================================================================
-- FRAME CREATION
-- ============================================================================

local function CreateTrackerFrame(trackerKey)
    if trackerFrames[trackerKey] then
        return trackerFrames[trackerKey]
    end
    
    -- Get saved position from MultiTracker with validation
    local savedPoint = MultiTracker:GetSetting(trackerKey, "point")
    local savedX = MultiTracker:GetSetting(trackerKey, "x")
    local savedY = MultiTracker:GetSetting(trackerKey, "y")
    
    -- Validate point is a valid anchor string
    local validPoints = { CENTER=true, TOP=true, BOTTOM=true, LEFT=true, RIGHT=true, 
                          TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true }
    if type(savedPoint) ~= "string" or not validPoints[savedPoint] then
        savedPoint = "CENTER"
    end
    
    -- Validate X and Y are numbers
    if type(savedX) ~= "number" then
        savedX = 0
    end
    if type(savedY) ~= "number" then
        savedY = -250 - (MultiTracker:GetTrackerIndex(trackerKey) or 1) * 60
    end
    
    dprint(string.format("CreateTrackerFrame %s: point=%s, x=%s, y=%s", 
        trackerKey, tostring(savedPoint), tostring(savedX), tostring(savedY)))
    
    local frame = CreateFrame("Frame", "TweaksUI_MultiTracker_" .. trackerKey, UIParent)
    frame:SetSize(200, 50)
    frame:SetPoint(savedPoint, UIParent, savedPoint, savedX, savedY)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    
    -- Drag handling (only when Layout mode is active)
    frame:SetScript("OnDragStart", function(self)
        if not TUICD.Layout or not TUICD.Layout:IsActive() then return end
        self:StartMoving()
    end)
    
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, _, x, y = self:GetPoint(1)
        MultiTracker:SetSetting(trackerKey, "point", point)
        MultiTracker:SetSetting(trackerKey, "x", x)
        MultiTracker:SetSetting(trackerKey, "y", y)
        dprint(string.format("Saved position for %s: %s, %.1f, %.1f", trackerKey, point, x, y))
    end)
    
    frame.trackerKey = trackerKey
    frame.icons = {}
    
    trackerFrames[trackerKey] = frame
    trackerIcons[trackerKey] = {}
    
    dprint("Created frame for " .. trackerKey)
    
    return frame
end

-- ============================================================================
-- ICON CREATION
-- ============================================================================

local function CreateTrackerIcon(trackerKey, entry, parent)
    local displayName, displayTexture, trackingID = GetEntryDisplayInfo(entry)
    
    if not displayTexture then
        dprint(string.format("No texture for %s %d in %s", entry.type, entry.id, trackerKey))
        return nil
    end
    
    local trackType, trackID = GetEntryTrackingID(entry)
    local entryKey = entry.type .. "_" .. entry.id
    
    -- Create button frame
    local frame = CreateFrame("Button", "TweaksUI_MultiTracker_" .. trackerKey .. "_" .. entryKey, parent)
    frame:SetSize(36, 36)
    
    -- Create icon texture
    local icon = frame:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(frame)
    icon:SetTexture(displayTexture)
    
    -- Create mask for rounded corners
    local iconMask = frame:CreateMaskTexture()
    iconMask:SetAllPoints(icon)
    iconMask:SetTexture("Interface\\AddOns\\TweaksUI_Cooldowns\\Media\\Textures\\Masks\\Mask_Rounded", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    
    -- Apply edge style
    local edgeStyle = MultiTracker:GetSetting(trackerKey, "iconEdgeStyle") or "sharp"
    local zoom = MultiTracker:GetSetting(trackerKey, "zoom") or 0.08
    
    if edgeStyle == "rounded" then
        icon:SetTexCoord(0, 1, 0, 1)
        icon:AddMaskTexture(iconMask)
    elseif edgeStyle == "square" then
        icon:SetTexCoord(0, 1, 0, 1)
    else  -- "sharp"
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    end
    
    -- Cooldown frame
    local hideSweep = MultiTracker:GetSetting(trackerKey, "hideSweep") or false
    local showCountdownText = MultiTracker:GetSetting(trackerKey, "showCountdownText")
    if showCountdownText == nil then showCountdownText = true end
    
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints(frame)
    cd:SetDrawEdge(not hideSweep)
    cd:SetDrawSwipe(not hideSweep)
    cd:SetSwipeColor(0, 0, 0, 0.8)
    cd:SetHideCountdownNumbers(not showCountdownText)
    
    -- Apply cooldown text settings
    local cooldownTextScale = MultiTracker:GetSetting(trackerKey, "cooldownTextScale") or 1.0
    local cooldownTextOffsetX = MultiTracker:GetSetting(trackerKey, "cooldownTextOffsetX") or 0
    local cooldownTextOffsetY = MultiTracker:GetSetting(trackerKey, "cooldownTextOffsetY") or 0
    local cooldownTextColorR = MultiTracker:GetSetting(trackerKey, "cooldownTextColorR") or 1.0
    local cooldownTextColorG = MultiTracker:GetSetting(trackerKey, "cooldownTextColorG") or 0.82
    local cooldownTextColorB = MultiTracker:GetSetting(trackerKey, "cooldownTextColorB") or 0.0
    
    -- Find and style the cooldown text element (it's created by CooldownFrameTemplate)
    -- Use a timer to ensure the text element exists
    C_Timer.After(0.1, function()
        if cd and cd.GetRegions then
            for _, region in pairs({cd:GetRegions()}) do
                if region:IsObjectType("FontString") then
                    -- Apply scale
                    region:SetScale(cooldownTextScale)
                    -- Apply offset by adjusting the point
                    region:ClearAllPoints()
                    region:SetPoint("CENTER", cd, "CENTER", cooldownTextOffsetX, cooldownTextOffsetY)
                    -- Apply color
                    region:SetTextColor(cooldownTextColorR, cooldownTextColorG, cooldownTextColorB, 1)
                    break
                end
            end
        end
    end)
    
    -- Count text (stack/charge count)
    local countTextScale = MultiTracker:GetSetting(trackerKey, "countTextScale") or 1.0
    local countTextOffsetX = MultiTracker:GetSetting(trackerKey, "countTextOffsetX") or 0
    local countTextOffsetY = MultiTracker:GetSetting(trackerKey, "countTextOffsetY") or 0
    local countTextColorR = MultiTracker:GetSetting(trackerKey, "countTextColorR") or 1.0
    local countTextColorG = MultiTracker:GetSetting(trackerKey, "countTextColorG") or 1.0
    local countTextColorB = MultiTracker:GetSetting(trackerKey, "countTextColorB") or 1.0
    
    local countText = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    countText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2 + countTextOffsetX, 2 + countTextOffsetY)
    countText:SetJustifyH("RIGHT")
    countText:SetTextColor(countTextColorR, countTextColorG, countTextColorB, 1)
    countText:SetShadowOffset(1, -1)
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetDrawLayer("OVERLAY", 7)
    countText:SetScale(countTextScale)
    countText:Hide()
    
    -- Unusable overlay (black tint for not enough resources)
    -- Use explicit corner anchors to fill the entire frame
    local unusableColorR = MultiTracker:GetSetting(trackerKey, "unusableColorR") or 0.0
    local unusableColorG = MultiTracker:GetSetting(trackerKey, "unusableColorG") or 0.0
    local unusableColorB = MultiTracker:GetSetting(trackerKey, "unusableColorB") or 0.0
    local unusableAlpha = MultiTracker:GetSetting(trackerKey, "unusableAlpha") or 0.6
    local unusableOverlay = frame:CreateTexture(nil, "OVERLAY")
    unusableOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    unusableOverlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    unusableOverlay:SetColorTexture(unusableColorR, unusableColorG, unusableColorB, unusableAlpha)
    unusableOverlay:SetBlendMode("BLEND")
    unusableOverlay:SetDrawLayer("OVERLAY", 2)
    unusableOverlay:Hide()
    
    -- For rounded style, apply the mask to match icon shape
    if edgeStyle == "rounded" and iconMask then
        unusableOverlay:AddMaskTexture(iconMask)
    end
    
    -- Range overlay (red tint for out of range)
    -- Use explicit corner anchors to fill the entire frame
    local rangeColorR = MultiTracker:GetSetting(trackerKey, "outOfRangeColorR") or 1.0
    local rangeColorG = MultiTracker:GetSetting(trackerKey, "outOfRangeColorG") or 0.3
    local rangeColorB = MultiTracker:GetSetting(trackerKey, "outOfRangeColorB") or 0.3
    local rangeAlpha = MultiTracker:GetSetting(trackerKey, "outOfRangeAlpha") or 0.6
    local rangeOverlay = frame:CreateTexture(nil, "OVERLAY")
    rangeOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    rangeOverlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    rangeOverlay:SetColorTexture(rangeColorR, rangeColorG, rangeColorB, rangeAlpha)
    rangeOverlay:SetBlendMode("BLEND")
    rangeOverlay:SetDrawLayer("OVERLAY", 3)
    rangeOverlay:Hide()
    
    -- For rounded style, apply the mask to match icon shape
    if edgeStyle == "rounded" and iconMask then
        rangeOverlay:AddMaskTexture(iconMask)
    end
    
    -- Store references
    frame.icon = icon
    frame.Icon = icon
    frame.iconMask = iconMask
    frame.cooldown = cd
    frame.Cooldown = cd
    frame.count = countText
    frame.unusableOverlay = unusableOverlay
    frame.rangeOverlay = rangeOverlay
    frame.entry = entry
    frame.entryType = entry.type
    frame.entryID = entry.id
    frame.entryKey = entryKey
    frame.entryName = displayName
    frame.trackType = trackType
    frame.trackID = trackID
    frame.trackerKey = trackerKey
    
    -- Enable mouse for tooltips (unless clickthrough is enabled)
    local clickthrough = MultiTracker:GetSetting(trackerKey, "clickthrough") or false
    frame:EnableMouse(not clickthrough)
    -- Also disable mouse on cooldown frame (it can catch clicks otherwise)
    cd:EnableMouse(not clickthrough)
    if cd.SetMouseClickEnabled then
        cd:SetMouseClickEnabled(not clickthrough)
    end
    if cd.SetMouseMotionEnabled then
        cd:SetMouseMotionEnabled(not clickthrough)
    end
    if clickthrough then
        -- Set hit rect insets to ensure clickthrough works
        frame:SetHitRectInsets(10000, 10000, 10000, 10000)
        cd:SetHitRectInsets(10000, 10000, 10000, 10000)
    end
    
    -- Tooltip handling
    frame:SetScript("OnEnter", function(self)
        if InCombatLockdown() then return end
        -- Check clickthrough first (no tooltips if clickthrough enabled)
        if MultiTracker:GetSetting(trackerKey, "clickthrough") then return end
        if MultiTracker:GetSetting(trackerKey, "showTooltip") == false then return end
        
        pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local tType, tID = GetEntryTrackingID(self.entry)
            if tType == "item" and tID then
                local itemLink = select(2, GetItemInfo(tID))
                if itemLink then
                    GameTooltip:SetHyperlink(itemLink)
                else
                    local itemName = GetItemInfo(tID)
                    GameTooltip:AddLine(itemName or self.entryName or "Item", 1, 1, 1)
                    GameTooltip:AddLine("Item ID: " .. tID, 0.7, 0.7, 0.7)
                end
            elseif tType == "spell" and tID then
                GameTooltip:SetSpellByID(tID)
            else
                GameTooltip:AddLine(self.entryName or "Unknown")
            end
            GameTooltip:Show()
        end)
    end)
    
    frame:SetScript("OnLeave", function()
        if not InCombatLockdown() then
            GameTooltip:Hide()
        end
    end)
    
    dprint(string.format("Created icon: %s %d (%s) in %s", entry.type, entry.id, displayName or "?", trackerKey))
    
    return frame
end

-- ============================================================================
-- COOLDOWN UPDATES
-- ============================================================================

-- Update usability state (desaturate when no resources)
local function UpdateIconUsabilityState(iconFrame)
    if not iconFrame or not iconFrame.unusableOverlay then return end
    
    local trackerKey = iconFrame.trackerKey
    local showUnusable = MultiTracker:GetSetting(trackerKey, "showUnusableState")
    
    if not showUnusable then
        -- Not tracking usability, just clear state
        iconFrame.unusableOverlay:Hide()
        iconFrame.isUnusable = false
        return
    end
    
    local trackType, trackID = GetEntryTrackingID(iconFrame.entry)
    
    if trackType == "spell" and trackID then
        pcall(function()
            local usable, insufficientPower = C_Spell.IsSpellUsable(trackID)
            iconFrame.isUnusable = insufficientPower or (not usable)
            
            if iconFrame.isUnusable then
                -- Update overlay color from settings
                local r = MultiTracker:GetSetting(trackerKey, "unusableColorR") or 0.0
                local g = MultiTracker:GetSetting(trackerKey, "unusableColorG") or 0.0
                local b = MultiTracker:GetSetting(trackerKey, "unusableColorB") or 0.0
                local a = MultiTracker:GetSetting(trackerKey, "unusableAlpha") or 0.6
                iconFrame.unusableOverlay:SetColorTexture(r, g, b, a)
                iconFrame.unusableOverlay:Show()
            else
                iconFrame.unusableOverlay:Hide()
            end
        end)
    elseif trackType == "item" and trackID then
        -- Items: check if count > 0
        pcall(function()
            local count = C_Item.GetItemCount(trackID, false, false, false)
            iconFrame.isUnusable = (count == 0)
            
            if iconFrame.isUnusable then
                local r = MultiTracker:GetSetting(trackerKey, "unusableColorR") or 0.0
                local g = MultiTracker:GetSetting(trackerKey, "unusableColorG") or 0.0
                local b = MultiTracker:GetSetting(trackerKey, "unusableColorB") or 0.0
                local a = MultiTracker:GetSetting(trackerKey, "unusableAlpha") or 0.6
                iconFrame.unusableOverlay:SetColorTexture(r, g, b, a)
                iconFrame.unusableOverlay:Show()
            else
                iconFrame.unusableOverlay:Hide()
            end
        end)
    else
        iconFrame.isUnusable = false
        iconFrame.unusableOverlay:Hide()
    end
end

-- Update range state (red tint when out of range)
local function UpdateIconRangeState(iconFrame)
    if not iconFrame or not iconFrame.rangeOverlay then return end
    
    local trackerKey = iconFrame.trackerKey
    local showOutOfRange = MultiTracker:GetSetting(trackerKey, "showOutOfRange")
    
    if not showOutOfRange then
        iconFrame.rangeOverlay:Hide()
        iconFrame.isOutOfRange = false
        return
    end
    
    local trackType, trackID = GetEntryTrackingID(iconFrame.entry)
    
    if trackType == "spell" and trackID then
        pcall(function()
            -- IsSpellInRange returns: true = in range, false = out of range, nil = no range requirement or no target
            local inRange = C_Spell.IsSpellInRange(trackID, "target")
            
            if inRange == false then
                -- Explicitly out of range
                iconFrame.isOutOfRange = true
                
                -- Update overlay color from settings
                local r = MultiTracker:GetSetting(trackerKey, "outOfRangeColorR") or 1.0
                local g = MultiTracker:GetSetting(trackerKey, "outOfRangeColorG") or 0.3
                local b = MultiTracker:GetSetting(trackerKey, "outOfRangeColorB") or 0.3
                local a = MultiTracker:GetSetting(trackerKey, "outOfRangeAlpha") or 0.6
                iconFrame.rangeOverlay:SetColorTexture(r, g, b, a)
                iconFrame.rangeOverlay:Show()
            else
                -- In range, no target, or no range requirement
                iconFrame.isOutOfRange = false
                iconFrame.rangeOverlay:Hide()
            end
        end)
    else
        iconFrame.isOutOfRange = false
        iconFrame.rangeOverlay:Hide()
    end
end

local function UpdateIconCooldown(iconFrame)
    if not iconFrame or not iconFrame.cooldown then return end
    
    local trackType, trackID = GetEntryTrackingID(iconFrame.entry)
    local trackerKey = iconFrame.trackerKey
    
    -- Update texture if equipped item changed
    if iconFrame.entry.type == "equipped" then
        local displayName, displayTexture, newTrackID = GetEntryDisplayInfo(iconFrame.entry)
        if displayTexture and iconFrame.icon then
            iconFrame.icon:SetTexture(displayTexture)
        end
        iconFrame.trackID = newTrackID
        trackID = newTrackID
    end
    
    if not trackType or not trackID then
        pcall(function() iconFrame.cooldown:Clear() end)
        pcall(function() iconFrame.count:Hide() end)
        pcall(function()
            if iconFrame.icon and iconFrame.icon.SetDesaturated then
                iconFrame.icon:SetDesaturated(false)
            end
            if iconFrame.rangeOverlay then
                iconFrame.rangeOverlay:Hide()
            end
            if iconFrame.unusableOverlay then
                iconFrame.unusableOverlay:Hide()
            end
        end)
        return
    end
    
    local isOnCooldown = false
    
    if trackType == "item" then
        local start, duration, enable = C_Container.GetItemCooldown(trackID)
        if start and duration and duration > 0 then
            pcall(function() iconFrame.cooldown:SetCooldown(start, duration) end)
            local remaining = (start + duration) - GetTime()
            if duration > GCD_THRESHOLD and remaining > 0.1 then
                isOnCooldown = true
            end
        else
            pcall(function() iconFrame.cooldown:Clear() end)
        end
        
        -- Update count
        pcall(function()
            local count = C_Item.GetItemCount(trackID, false, false, false)
            if count and count > 1 then
                iconFrame.count:SetText(count)
                iconFrame.count:Show()
            else
                iconFrame.count:Hide()
            end
        end)
        
    elseif trackType == "spell" then
        local cooldownSet = false
        local isRestricted = InCombatLockdown()
        
        -- Try Duration Objects first (Midnight API)
        if C_Spell.GetSpellChargesCooldownDuration then
            pcall(function()
                local chargeDuration = C_Spell.GetSpellChargesCooldownDuration(trackID)
                if chargeDuration then
                    iconFrame.cooldown:SetCooldownFromDurationObject(chargeDuration, true)
                    cooldownSet = true
                end
            end)
        end
        
        if not cooldownSet and C_Spell.GetSpellCooldownDuration then
            pcall(function()
                local duration = C_Spell.GetSpellCooldownDuration(trackID)
                if duration then
                    iconFrame.cooldown:SetCooldownFromDurationObject(duration, true)
                    cooldownSet = true
                end
            end)
        end
        
        -- Traditional API fallback (only outside combat)
        if not cooldownSet and not isRestricted then
            pcall(function()
                local info = C_Spell.GetSpellCooldown(trackID)
                if info and info.duration and info.startTime then
                    if info.duration > 0 then
                        iconFrame.cooldown:SetCooldown(info.startTime, info.duration)
                        local remaining = (info.startTime + info.duration) - GetTime()
                        if info.duration > GCD_THRESHOLD and remaining > 0.1 then
                            isOnCooldown = true
                        end
                    else
                        iconFrame.cooldown:Clear()
                    end
                end
            end)
        end
        
        -- Update charges
        pcall(function()
            local chargeInfo = C_Spell.GetSpellCharges(trackID)
            if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
                if chargeInfo.currentCharges and chargeInfo.currentCharges < chargeInfo.maxCharges then
                    iconFrame.count:SetText(chargeInfo.currentCharges)
                    iconFrame.count:Show()
                else
                    iconFrame.count:Hide()
                end
            else
                iconFrame.count:Hide()
            end
        end)
    end
    
    -- Store cooldown state
    iconFrame.isOnCooldown = isOnCooldown
    
    -- Update usability and range states (these use overlays now)
    UpdateIconUsabilityState(iconFrame)
    UpdateIconRangeState(iconFrame)
    
    -- Apply desaturation only for cooldown state
    pcall(function()
        if iconFrame.icon and iconFrame.icon.SetDesaturated then
            iconFrame.icon:SetDesaturated(isOnCooldown)
        end
    end)
end

-- Update just usability states for all icons (event-driven)
local function UpdateAllUsabilityStates()
    for trackerKey, icons in pairs(trackerIcons) do
        if MultiTracker:GetSetting(trackerKey, "enabled") and MultiTracker:GetSetting(trackerKey, "showUnusableState") then
            for _, iconFrame in pairs(icons) do
                pcall(function()
                    UpdateIconUsabilityState(iconFrame)
                end)
            end
        end
    end
end

-- Update just range states for all icons (event-driven)
local function UpdateAllRangeStates()
    for trackerKey, icons in pairs(trackerIcons) do
        if MultiTracker:GetSetting(trackerKey, "enabled") and MultiTracker:GetSetting(trackerKey, "showOutOfRange") then
            for _, iconFrame in pairs(icons) do
                pcall(UpdateIconRangeState, iconFrame)
            end
        end
    end
end

local function UpdateAllCooldowns()
    for trackerKey, icons in pairs(trackerIcons) do
        if MultiTracker:GetSetting(trackerKey, "enabled") then
            for _, iconFrame in pairs(icons) do
                pcall(UpdateIconCooldown, iconFrame)
            end
        end
    end
end

-- ============================================================================
-- LAYOUT
-- ============================================================================

local function LayoutTrackerIcons(trackerKey)
    local frame = trackerFrames[trackerKey]
    local icons = trackerIcons[trackerKey]
    if not frame or not icons then return end
    
    -- Apply per-icon hidden state before layout (matching Cooldowns.lua pattern)
    local CooldownHighlights = TUICD.CooldownHighlights
    local allIcons = {}
    for _, iconFrame in pairs(icons) do
        table.insert(allIcons, iconFrame)
    end
    
    -- Sort by listIndex first so hidden check uses correct slot indices
    table.sort(allIcons, function(a, b)
        return (a.listIndex or 0) < (b.listIndex or 0)
    end)
    
    -- Apply hidden state
    for idx, iconFrame in ipairs(allIcons) do
        local isHidden = CooldownHighlights and CooldownHighlights:IsIconHidden(trackerKey, idx)
        if isHidden then
            iconFrame:SetAlpha(0)
            iconFrame._TUI_hiddenByPerIcon = true
        else
            if iconFrame._TUI_hiddenByPerIcon then
                -- Was hidden, now unhidden — restore alpha
                iconFrame:SetAlpha(1)
            end
            iconFrame._TUI_hiddenByPerIcon = false
        end
    end
    
    -- Collect visible icons (hidden icons at alpha=0 still show, so filter by IsShown)
    local visibleIcons = {}
    for _, iconFrame in ipairs(allIcons) do
        if iconFrame:IsShown() then
            table.insert(visibleIcons, iconFrame)
        end
    end
    
    local iconCount = #visibleIcons
    if iconCount == 0 then
        frame:SetSize(10, 10)
        return
    end
    
    -- Get layout settings (use same names as UI)
    local iconSize = MultiTracker:GetSetting(trackerKey, "iconSize") or 36
    local columns = MultiTracker:GetSetting(trackerKey, "columns") or 4
    local hSpacing = MultiTracker:GetSetting(trackerKey, "spacingH") or 2
    local vSpacing = MultiTracker:GetSetting(trackerKey, "spacingV") or 2
    local growH = MultiTracker:GetSetting(trackerKey, "growDirection") or "RIGHT"
    local growV = MultiTracker:GetSetting(trackerKey, "growSecondary") or "DOWN"
    local reverseOrder = MultiTracker:GetSetting(trackerKey, "reverseOrder") or false
    local alignment = MultiTracker:GetSetting(trackerKey, "alignment") or "LEFT"
    
    -- Custom grid settings
    local useCustomGrid = MultiTracker:GetSetting(trackerKey, "useCustomGrid") or false
    local customLayout = MultiTracker:GetSetting(trackerKey, "customLayout") or ""
    local customGridMode = MultiTracker:GetSetting(trackerKey, "customGridMode") or "ROW"
    local customGridAlign = MultiTracker:GetSetting(trackerKey, "customGridAlign") or "LEFT"
    
    -- Handle aspect ratio
    local aspectRatio = MultiTracker:GetSetting(trackerKey, "aspectRatio") or "1:1"
    local iconWidth, iconHeight = iconSize, iconSize
    if aspectRatio == "custom" then
        iconWidth = MultiTracker:GetSetting(trackerKey, "iconWidth") or iconSize
        iconHeight = MultiTracker:GetSetting(trackerKey, "iconHeight") or iconSize
    elseif aspectRatio == "4:3" then
        iconHeight = iconSize * 0.75
    elseif aspectRatio == "3:4" then
        iconWidth = iconSize * 0.75
    elseif aspectRatio == "16:9" then
        iconHeight = iconSize * 0.5625
    elseif aspectRatio == "9:16" then
        iconWidth = iconSize * 0.5625
    elseif aspectRatio == "2:1" then
        iconHeight = iconSize * 0.5
    elseif aspectRatio == "1:2" then
        iconWidth = iconSize * 0.5
    end
    
    -- Reverse order if needed
    if reverseOrder then
        local reversed = {}
        for i = #visibleIcons, 1, -1 do
            table.insert(reversed, visibleIcons[i])
        end
        visibleIcons = reversed
    end
    
    -- Parse custom grid pattern
    local customRowSizes = {}
    local useCustomLayout = false
    
    if useCustomGrid then
        if customLayout ~= "" then
            for num in customLayout:gmatch("(%d+)") do
                local n = tonumber(num)
                if n and n >= 0 then
                    table.insert(customRowSizes, n)
                    if n > 0 then
                        useCustomLayout = true
                    end
                end
            end
        end
        -- Default to all icons on one row if no valid pattern
        if #customRowSizes == 0 then
            customRowSizes = { iconCount }
        end
        useCustomLayout = true
    end
    
    -- ================================================================
    -- CUSTOM GRID LAYOUT
    -- ================================================================
    if useCustomLayout and #customRowSizes > 0 then
        local iconIdx = 1
        local maxPrimary = 0
        local totalSecondary = 0
        
        -- Determine overflow size (use last non-zero pattern value)
        local overflowSize = customRowSizes[#customRowSizes]
        if overflowSize == 0 then
            for i = #customRowSizes, 1, -1 do
                if customRowSizes[i] > 0 then
                    overflowSize = customRowSizes[i]
                    break
                end
            end
        end
        if overflowSize == 0 then overflowSize = columns end
        
        -- Track placed icons for alignment pass
        local placedIcons = {}
        
        if customGridMode == "COLUMN" then
            -- COLUMN MODE: Fill down (primary), then wrap right (secondary)
            local currentCol = 0
            
            for _, colSize in ipairs(customRowSizes) do
                if colSize == 0 then
                    currentCol = currentCol + 1
                else
                    local iconsInThisCol = 0
                    for rowIdx = 1, colSize do
                        if iconIdx <= iconCount then
                            local iconFrame = visibleIcons[iconIdx]
                            iconIdx = iconIdx + 1
                            iconFrame:SetSize(iconWidth, iconHeight)
                            ApplyIconEdgeStyle(iconFrame, trackerKey, iconWidth, iconHeight)
                            table.insert(placedIcons, {icon = iconFrame, col = currentCol, row = rowIdx - 1, groupSize = colSize})
                            iconsInThisCol = iconsInThisCol + 1
                        end
                    end
                    if iconsInThisCol > 0 then
                        maxPrimary = math.max(maxPrimary, iconsInThisCol)
                        totalSecondary = currentCol + 1
                    end
                    currentCol = currentCol + 1
                end
            end
            
            -- Handle overflow
            while iconIdx <= iconCount do
                local iconsInThisCol = 0
                local overflowStartIdx = #placedIcons + 1
                for rowIdx = 1, overflowSize do
                    if iconIdx <= iconCount then
                        local iconFrame = visibleIcons[iconIdx]
                        iconIdx = iconIdx + 1
                        iconFrame:SetSize(iconWidth, iconHeight)
                        ApplyIconEdgeStyle(iconFrame, trackerKey, iconWidth, iconHeight)
                        table.insert(placedIcons, {icon = iconFrame, col = currentCol, row = rowIdx - 1, groupSize = 0})
                        iconsInThisCol = iconsInThisCol + 1
                    end
                end
                for i = overflowStartIdx, #placedIcons do
                    placedIcons[i].groupSize = iconsInThisCol
                end
                if iconsInThisCol > 0 then
                    maxPrimary = math.max(maxPrimary, iconsInThisCol)
                    totalSecondary = currentCol + 1
                end
                currentCol = currentCol + 1
            end
            
            -- Calculate frame size and position icons
            local frameWidth = totalSecondary * iconWidth + (totalSecondary - 1) * hSpacing
            local frameHeight = maxPrimary * iconHeight + (maxPrimary - 1) * vSpacing
            frame:SetSize(frameWidth, frameHeight)
            
            for _, placed in ipairs(placedIcons) do
                placed.icon:ClearAllPoints()
                local xOffset = placed.col * (iconWidth + hSpacing)
                local yOffset = placed.row * (iconHeight + vSpacing)
                
                -- Apply alignment within column
                if customGridAlign == "CENTER" then
                    yOffset = yOffset + (maxPrimary - placed.groupSize) * (iconHeight + vSpacing) / 2
                elseif customGridAlign == "BOTTOM" then
                    yOffset = yOffset + (maxPrimary - placed.groupSize) * (iconHeight + vSpacing)
                end
                
                if growH == "LEFT" then xOffset = -xOffset end
                if growV == "UP" then yOffset = -yOffset else yOffset = -yOffset end
                
                local anchor = "TOPLEFT"
                if growH == "LEFT" then anchor = "TOPRIGHT" end
                
                placed.icon:SetPoint(anchor, frame, anchor, xOffset, yOffset)
            end
        else
            -- ROW MODE: Fill across (primary), then wrap down (secondary)
            local currentRow = 0
            
            for _, rowSize in ipairs(customRowSizes) do
                if rowSize == 0 then
                    currentRow = currentRow + 1
                else
                    local iconsInThisRow = 0
                    for colIdx = 1, rowSize do
                        if iconIdx <= iconCount then
                            local iconFrame = visibleIcons[iconIdx]
                            iconIdx = iconIdx + 1
                            iconFrame:SetSize(iconWidth, iconHeight)
                            ApplyIconEdgeStyle(iconFrame, trackerKey, iconWidth, iconHeight)
                            table.insert(placedIcons, {icon = iconFrame, row = currentRow, col = colIdx - 1, groupSize = rowSize})
                            iconsInThisRow = iconsInThisRow + 1
                        end
                    end
                    if iconsInThisRow > 0 then
                        maxPrimary = math.max(maxPrimary, iconsInThisRow)
                        totalSecondary = currentRow + 1
                    end
                    currentRow = currentRow + 1
                end
            end
            
            -- Handle overflow
            while iconIdx <= iconCount do
                local iconsInThisRow = 0
                local overflowStartIdx = #placedIcons + 1
                for colIdx = 1, overflowSize do
                    if iconIdx <= iconCount then
                        local iconFrame = visibleIcons[iconIdx]
                        iconIdx = iconIdx + 1
                        iconFrame:SetSize(iconWidth, iconHeight)
                        ApplyIconEdgeStyle(iconFrame, trackerKey, iconWidth, iconHeight)
                        table.insert(placedIcons, {icon = iconFrame, row = currentRow, col = colIdx - 1, groupSize = 0})
                        iconsInThisRow = iconsInThisRow + 1
                    end
                end
                for i = overflowStartIdx, #placedIcons do
                    placedIcons[i].groupSize = iconsInThisRow
                end
                if iconsInThisRow > 0 then
                    maxPrimary = math.max(maxPrimary, iconsInThisRow)
                    totalSecondary = currentRow + 1
                end
                currentRow = currentRow + 1
            end
            
            -- Calculate frame size and position icons
            local frameWidth = maxPrimary * iconWidth + (maxPrimary - 1) * hSpacing
            local frameHeight = totalSecondary * iconHeight + (totalSecondary - 1) * vSpacing
            frame:SetSize(frameWidth, frameHeight)
            
            for _, placed in ipairs(placedIcons) do
                placed.icon:ClearAllPoints()
                local xOffset = placed.col * (iconWidth + hSpacing)
                local yOffset = placed.row * (iconHeight + vSpacing)
                
                -- Apply alignment within row
                if customGridAlign == "CENTER" then
                    xOffset = xOffset + (maxPrimary - placed.groupSize) * (iconWidth + hSpacing) / 2
                elseif customGridAlign == "RIGHT" then
                    xOffset = xOffset + (maxPrimary - placed.groupSize) * (iconWidth + hSpacing)
                end
                
                if growH == "LEFT" then xOffset = -xOffset end
                if growV == "UP" then yOffset = -yOffset else yOffset = -yOffset end
                
                local anchor = "TOPLEFT"
                if growH == "LEFT" and growV == "DOWN" then anchor = "TOPRIGHT"
                elseif growH == "RIGHT" and growV == "UP" then anchor = "BOTTOMLEFT"
                elseif growH == "LEFT" and growV == "UP" then anchor = "BOTTOMRIGHT"
                end
                
                placed.icon:SetPoint(anchor, frame, anchor, xOffset, yOffset)
            end
        end
        
        dprint(string.format("Layout %s (custom): %d icons, pattern=%s, mode=%s", 
            trackerKey, iconCount, customLayout, customGridMode))
        return
    end
    
    -- ================================================================
    -- STANDARD GRID LAYOUT
    -- ================================================================
    local rows = math.ceil(iconCount / columns)
    local actualCols = math.min(columns, iconCount)
    
    -- Calculate frame size
    local totalWidth = actualCols * iconWidth + (actualCols - 1) * hSpacing
    local totalHeight = rows * iconHeight + (rows - 1) * vSpacing
    frame:SetSize(totalWidth, totalHeight)
    
    -- Position icons
    for i, iconFrame in ipairs(visibleIcons) do
        iconFrame:ClearAllPoints()
        iconFrame:SetSize(iconWidth, iconHeight)
        ApplyIconEdgeStyle(iconFrame, trackerKey, iconWidth, iconHeight)
        
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        
        local xOffset, yOffset
        
        if growH == "RIGHT" then
            xOffset = col * (iconWidth + hSpacing)
        else
            xOffset = -col * (iconWidth + hSpacing)
        end
        
        if growV == "DOWN" then
            yOffset = -row * (iconHeight + vSpacing)
        else
            yOffset = row * (iconHeight + vSpacing)
        end
        
        local anchor = "TOPLEFT"
        if growH == "LEFT" and growV == "DOWN" then anchor = "TOPRIGHT"
        elseif growH == "RIGHT" and growV == "UP" then anchor = "BOTTOMLEFT"
        elseif growH == "LEFT" and growV == "UP" then anchor = "BOTTOMRIGHT"
        end
        
        iconFrame:SetPoint(anchor, frame, anchor, xOffset, yOffset)
    end
    
    dprint(string.format("Layout %s: %d icons, %dx%d", trackerKey, iconCount, actualCols, rows))
end

-- ============================================================================
-- VISIBILITY
-- ============================================================================

local function ShouldTrackerBeVisible(trackerKey)
    -- Check master enable
    if not MultiTracker:GetSetting(trackerKey, "enabled") then
        return false
    end
    
    -- Force all visible mode bypasses all visibility conditions
    if TUICD.forceAllVisible then
        return true
    end
    
    -- Always show in Edit Mode for positioning
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return true
    end
    
    -- Check if visibility rules are enabled
    local visibilityEnabled = MultiTracker:GetSetting(trackerKey, "visibilityEnabled")
    if not visibilityEnabled then
        return true  -- Visibility system disabled = always show
    end
    
    -- Build current player state
    local inCombat = UnitAffectingCombat("player")
    local inRaid = IsInRaid()
    local inGroup = IsInGroup()
    local isSolo = not inGroup
    local hasTarget = UnitExists("target")
    local isMounted = (TUICD.UnitAPI and TUICD.UnitAPI.IsMountedOrTravelForm)
                      and TUICD.UnitAPI:IsMountedOrTravelForm() or IsMounted()
    
    local _, instanceType = IsInInstance()
    local inInstance = (instanceType == "party" or instanceType == "raid")
    local inArena = (instanceType == "arena")
    local inBattleground = (instanceType == "pvp")
    
    -- OR logic: if ANY checked condition matches current state, show the tracker
    if inCombat and MultiTracker:GetSetting(trackerKey, "showInCombat") then return true end
    if not inCombat and MultiTracker:GetSetting(trackerKey, "showOutOfCombat") then return true end
    if isSolo and MultiTracker:GetSetting(trackerKey, "showSolo") then return true end
    if inGroup and not inRaid and MultiTracker:GetSetting(trackerKey, "showInParty") then return true end
    if inRaid and MultiTracker:GetSetting(trackerKey, "showInRaid") then return true end
    if inInstance and MultiTracker:GetSetting(trackerKey, "showInInstance") then return true end
    if inArena and MultiTracker:GetSetting(trackerKey, "showInArena") then return true end
    if inBattleground and MultiTracker:GetSetting(trackerKey, "showInBattleground") then return true end
    if instanceType == "party" and MultiTracker:GetSetting(trackerKey, "showInDungeon") then return true end
    if hasTarget and MultiTracker:GetSetting(trackerKey, "showHasTarget") then return true end
    if not hasTarget and MultiTracker:GetSetting(trackerKey, "showNoTarget") then return true end
    if isMounted and MultiTracker:GetSetting(trackerKey, "showMounted") then return true end
    if not isMounted and MultiTracker:GetSetting(trackerKey, "showNotMounted") then return true end
    
    -- No conditions matched = hide
    return false
end

local function UpdateTrackerVisibility(trackerKey)
    local frame = trackerFrames[trackerKey]
    if not frame then return end
    
    local shouldShow = ShouldTrackerBeVisible(trackerKey)
    
    if shouldShow then
        frame:Show()
        -- Apply combat-aware opacity
        local inCombat = UnitAffectingCombat("player")
        local alpha = inCombat 
            and (MultiTracker:GetSetting(trackerKey, "combatOpacity") or 1)
            or (MultiTracker:GetSetting(trackerKey, "outOfCombatOpacity") or 1)
        frame:SetAlpha(alpha)
    else
        frame:Hide()
    end
end

local function UpdateAllVisibility()
    for trackerKey, _ in pairs(trackerFrames) do
        pcall(UpdateTrackerVisibility, trackerKey)
    end
end

-- Visibility ticker: polls every 0.5s for state changes that don't have events
-- (target changes, mount state) — matches the original Cooldowns.lua pattern
local visibilityTicker = nil

local function StartVisibilityTicker()
    if visibilityTicker then return end
    
    -- Check if any multi-tracker has visibility enabled
    local anyEnabled = false
    for trackerKey, _ in pairs(trackerFrames) do
        if MultiTracker:GetSetting(trackerKey, "visibilityEnabled") then
            anyEnabled = true
            break
        end
    end
    
    if not anyEnabled then return end
    
    visibilityTicker = C_Timer.NewTicker(0.5, function()
        UpdateAllVisibility()
    end)
end

local function StopVisibilityTicker()
    if visibilityTicker then
        visibilityTicker:Cancel()
        visibilityTicker = nil
    end
end

-- Restart the ticker when settings change (called from settings panel)
function MultiTrackerFrames:RestartVisibilityTicker()
    StopVisibilityTicker()
    StartVisibilityTicker()
end

-- ============================================================================
-- REBUILD
-- ============================================================================

function MultiTrackerFrames:RebuildTracker(trackerKey)
    -- Create frame if needed
    local frame = trackerFrames[trackerKey]
    if not frame then
        frame = CreateTrackerFrame(trackerKey)
    end
    
    -- Clear existing icons
    if trackerIcons[trackerKey] then
        for _, iconFrame in pairs(trackerIcons[trackerKey]) do
            iconFrame:Hide()
            iconFrame:SetParent(nil)
        end
    end
    trackerIcons[trackerKey] = {}
    
    -- Check if enabled
    if not MultiTracker:GetSetting(trackerKey, "enabled") then
        frame:Hide()
        return
    end
    
    -- Get entries for current spec
    local specID = GetSpecializationInfo(GetSpecialization() or 1) or 0
    local entries = MultiTracker:GetEntries(trackerKey, specID)
    
    -- Create icons for enabled entries
    local displayIndex = 0
    for i, entry in ipairs(entries) do
        local isEnabled = entry.enabled ~= false
        
        if isEnabled then
            local entryKey = entry.type .. "_" .. entry.id
            
            -- For equipped entries, check if slot has usable item
            if entry.type == "equipped" then
                local itemID = GetInventoryItemID("player", entry.id)
                if itemID and HasOnUseAbility(itemID) then
                    local iconFrame = CreateTrackerIcon(trackerKey, entry, frame)
                    if iconFrame then
                        displayIndex = displayIndex + 1
                        iconFrame.listIndex = displayIndex
                        iconFrame.entryIndex = i
                        trackerIcons[trackerKey][entryKey] = iconFrame
                    end
                end
            else
                local iconFrame = CreateTrackerIcon(trackerKey, entry, frame)
                if iconFrame then
                    displayIndex = displayIndex + 1
                    iconFrame.listIndex = displayIndex
                    iconFrame.entryIndex = i
                    trackerIcons[trackerKey][entryKey] = iconFrame
                end
            end
        end
    end
    
    -- Layout icons
    LayoutTrackerIcons(trackerKey)
    
    -- Update visibility
    UpdateTrackerVisibility(trackerKey)
    
    dprint(string.format("Rebuilt %s: %d icons from %d entries", trackerKey, displayIndex, #entries))
end

function MultiTrackerFrames:RebuildAllTrackers()
    local trackerList = MultiTracker:GetTrackerList()
    for _, tracker in ipairs(trackerList) do
        self:RebuildTracker(tracker.key)
    end
end

function MultiTrackerFrames:LayoutTracker(trackerKey)
    LayoutTrackerIcons(trackerKey)
end

-- ============================================================================
-- LAYOUT MODE INTEGRATION
-- ============================================================================

local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
local layoutWrappers = {}

local function RegisterTrackerWithLayout(trackerKey)
    local frame = trackerFrames[trackerKey]
    if not frame or layoutWrappers[trackerKey] then return end
    
    local Layout = TUICD.Layout
    if not Layout then return end
    
    local trackerInfo = nil
    local trackerList = MultiTracker:GetTrackerList()
    for _, t in ipairs(trackerList) do
        if t.key == trackerKey then
            trackerInfo = t
            break
        end
    end
    
    local displayName = trackerInfo and trackerInfo.name or trackerKey
    local wrapperId = "multiTracker_" .. trackerKey
    
    -- Create TUIFrame wrapper
    local wrapper = {
        frame = frame,
        id = wrapperId,
        
        defaultPosition = {
            point = "CENTER",
            x = 0,
            y = -250 - (MultiTracker:GetTrackerIndex(trackerKey) or 1) * 60,
        },
        
        -- Frame visibility methods (delegate to underlying frame)
        IsShown = function(self)
            return frame:IsShown()
        end,
        
        IsVisible = function(self)
            return frame:IsVisible()
        end,
        
        Show = function(self)
            frame:Show()
        end,
        
        Hide = function(self)
            frame:Hide()
        end,
        
        GetPosition = function(self)
            local point, _, _, x, y = frame:GetPoint(1)
            return point or "CENTER", x or 0, y or 0
        end,
        
        SetPosition = function(self, point, x, y)
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point, x, y)
            -- Save to MultiTracker
            MultiTracker:SetSetting(trackerKey, "point", point)
            MultiTracker:SetSetting(trackerKey, "x", x)
            MultiTracker:SetSetting(trackerKey, "y", y)
        end,
        
        GetScale = function(self)
            return frame:GetScale()
        end,
        
        SetScale = function(self, scale)
            frame:SetScale(scale)
        end,
        
        GetSnapTarget = function(self, tolerance)
            if not FlyPaper then return nil end
            tolerance = tolerance or 15
            local point, relFrame, relPoint, x, y = FlyPaper.GetBestAnchorForGroup(
                frame, "TUICD", tolerance
            )
            if point and relFrame then
                return relFrame, point, relPoint, x, y
            end
            return nil
        end,
        
        GetSaveData = function(self)
            local left = frame:GetLeft()
            local bottom = frame:GetBottom()
            if not left or not bottom then
                local point, _, _, x, y = frame:GetPoint(1)
                return { point = point or "CENTER", x = x or 0, y = y or 0, scale = self:GetScale() }
            end
            return { point = "BOTTOMLEFT", x = left, y = bottom, scale = self:GetScale() }
        end,
        
        LoadSaveData = function(self, data)
            if not data then return end
            if InCombatLockdown() then return end
            
            local point = data.point or "CENTER"
            local x = data.x or 0
            local y = data.y or 0
            
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point, x, y)
            
            if data.scale then
                frame:SetScale(data.scale)
            end
            
            -- Save to MultiTracker
            MultiTracker:SetSetting(trackerKey, "point", point)
            MultiTracker:SetSetting(trackerKey, "x", x)
            MultiTracker:SetSetting(trackerKey, "y", y)
        end,
        
        sizeLocked = false,
        SetSizeLocked = function(self, locked) self.sizeLocked = locked end,
        IsSizeLocked = function(self) return self.sizeLocked end,
        GetSize = function(self) return frame:GetSize() end,
        ForceSetSize = function(self, w, h) frame:SetSize(w, h) end,
    }
    
    frame.tuiFrame = wrapper
    layoutWrappers[trackerKey] = wrapper
    
    -- Register with FlyPaper
    if FlyPaper then
        FlyPaper.AddFrame("TUICD", wrapperId, frame)
    end
    
    -- Register with Layout
    Layout:RegisterElement(wrapperId, {
        name = "Multi: " .. displayName,
        category = "Cooldowns",
        tuiFrame = wrapper,
        defaultPosition = wrapper.defaultPosition,
    })
    
    dprint("Registered " .. trackerKey .. " with Layout as '" .. displayName .. "'")
end

function MultiTrackerFrames:RegisterAllWithLayout()
    local trackerList = MultiTracker:GetTrackerList()
    for _, tracker in ipairs(trackerList) do
        if trackerFrames[tracker.key] then
            RegisterTrackerWithLayout(tracker.key)
        end
    end
end

function MultiTrackerFrames:UnregisterFromLayout(trackerKey)
    local wrapper = layoutWrappers[trackerKey]
    if not wrapper then return end
    
    local Layout = TUICD.Layout
    if Layout then
        Layout:UnregisterElement("multiTracker_" .. trackerKey)
    end
    
    if FlyPaper then
        -- FlyPaper doesn't have RemoveFrame, but the frame will be garbage collected
    end
    
    layoutWrappers[trackerKey] = nil
end

-- Hide all tracker frames (used during reset)
function MultiTrackerFrames:HideAllTrackers()
    for trackerKey, frame in pairs(trackerFrames) do
        if frame and frame.Hide then
            frame:Hide()
        end
        -- Unregister from layout
        self:UnregisterFromLayout(trackerKey)
    end
    
    -- Clear the frames table
    wipe(trackerFrames)
    wipe(layoutWrappers)
    
    dprint("All tracker frames hidden and cleared")
end

-- ============================================================================
-- UPDATE TICKER
-- ============================================================================

local function StartUpdates()
    if updateTicker then return end
    
    updateTicker = C_Timer.NewTicker(UPDATE_INTERVAL, function()
        if enabled then
            pcall(UpdateAllCooldowns)
            pcall(UpdateAllVisibility)
        end
    end)
    
    dprint("Update ticker started")
end

local function StopUpdates()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
        dprint("Update ticker stopped")
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function MultiTrackerFrames:Enable()
    if enabled then return end
    enabled = true
    
    -- Build all trackers
    self:RebuildAllTrackers()
    
    -- Register with Layout after frames exist
    C_Timer.After(0.5, function()
        self:RegisterAllWithLayout()
    end)
    
    -- Reinitialize multiCustom highlights now that tracker icons exist
    C_Timer.After(1, function()
        if TUICD.CooldownHighlights then
            -- Re-initialize any multiCustom trackers that have saved highlight data
            for dbKey, _ in pairs(TweaksUI_Cooldowns_CharDB or {}) do
                if type(dbKey) == "string" and dbKey:match("^multiCustom%d+Highlights$") then
                    local trackerKey = dbKey:gsub("Highlights$", "")
                    -- Force re-initialization by clearing the flag
                    TUICD.CooldownHighlights:ResetInitialized(trackerKey)
                    TUICD.CooldownHighlights:Initialize(trackerKey)
                end
            end
        end
    end)
    
    -- Start updates
    StartUpdates()
    
    dprint("MultiTrackerFrames enabled")
end

function MultiTrackerFrames:Disable()
    if not enabled then return end
    enabled = false
    
    StopUpdates()
    
    -- Hide all frames
    for trackerKey, frame in pairs(trackerFrames) do
        frame:Hide()
    end
    
    dprint("MultiTrackerFrames disabled")
end

function MultiTrackerFrames:IsEnabled()
    return enabled
end

function MultiTrackerFrames:GetFrame(trackerKey)
    return trackerFrames[trackerKey]
end

function MultiTrackerFrames:GetIcons(trackerKey)
    return trackerIcons[trackerKey]
end

-- Called when a tracker is created via MultiTracker
function MultiTrackerFrames:OnTrackerCreated(trackerKey)
    if enabled then
        self:RebuildTracker(trackerKey)
        C_Timer.After(0.2, function()
            RegisterTrackerWithLayout(trackerKey)
        end)
    end
end

-- Called when a tracker is deleted via MultiTracker
function MultiTrackerFrames:OnTrackerDeleted(trackerKey)
    self:UnregisterFromLayout(trackerKey)
    
    -- Clean up icons
    if trackerIcons[trackerKey] then
        for _, iconFrame in pairs(trackerIcons[trackerKey]) do
            iconFrame:Hide()
            iconFrame:SetParent(nil)
        end
        trackerIcons[trackerKey] = nil
    end
    
    -- Clean up frame
    if trackerFrames[trackerKey] then
        trackerFrames[trackerKey]:Hide()
        trackerFrames[trackerKey] = nil
    end
end

-- Called when tracker settings change
function MultiTrackerFrames:OnSettingsChanged(trackerKey, setting, value)
    if not enabled then return end
    
    -- Layout-related settings need relayout
    local layoutSettings = {
        iconSize = true, columns = true, hSpacing = true, vSpacing = true,
        growHorizontal = true, growVertical = true, reverseOrder = true, aspectRatio = true
    }
    
    if layoutSettings[setting] then
        LayoutTrackerIcons(trackerKey)
    elseif setting == "enabled" then
        self:RebuildTracker(trackerKey)
    else
        -- Visual settings need icon rebuild
        self:RebuildTracker(trackerKey)
    end
end

-- Called when entries change
function MultiTrackerFrames:OnEntriesChanged(trackerKey)
    if enabled then
        self:RebuildTracker(trackerKey)
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Auto-enable when Cooldowns module is ready
C_Timer.After(3, function()
    if TUICD.Database and TUICD.Database:IsModuleEnabled(TUICD.MODULE_IDS.COOLDOWNS) then
        MultiTrackerFrames:Enable()
    end
end)

-- Throttle for usability updates (SPELL_UPDATE_USABLE can fire frequently)
local lastUsabilityUpdate = 0
local USABILITY_THROTTLE = 0.1  -- 100ms throttle (was 50ms)

-- Listen for spec changes, usability changes, target changes, cooldown changes, and visibility changes
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
-- Cooldown events (event-driven cooldown updates)
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
-- Visibility events (event-driven visibility updates)
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not enabled then return end
    
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        dprint("Spec changed, rebuilding all multi-trackers")
        MultiTrackerFrames:RebuildAllTrackers()
        
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Rebuild trackers that have equipped slot entries
        local trackerList = MultiTracker:GetTrackerList()
        for _, tracker in ipairs(trackerList) do
            local specID = GetSpecializationInfo(GetSpecialization() or 1) or 0
            local entries = MultiTracker:GetEntries(tracker.key, specID)
            for _, entry in ipairs(entries) do
                if entry.type == "equipped" then
                    MultiTrackerFrames:RebuildTracker(tracker.key)
                    break
                end
            end
        end
        
    elseif event == "SPELL_UPDATE_USABLE" then
        -- Throttle usability updates
        local now = GetTime()
        if now - lastUsabilityUpdate >= USABILITY_THROTTLE then
            lastUsabilityUpdate = now
            UpdateAllUsabilityStates()
        end
        
    elseif event == "UNIT_POWER_UPDATE" then
        local unit = ...
        if unit == "player" then
            -- Throttle usability updates
            local now = GetTime()
            if now - lastUsabilityUpdate >= USABILITY_THROTTLE then
                lastUsabilityUpdate = now
                UpdateAllUsabilityStates()
            end
        end
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Update range states when target changes
        UpdateAllRangeStates()
        -- Also update visibility (for "Has Target" / "No Target" conditions)
        pcall(UpdateAllVisibility)
        
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        -- Throttle cooldown updates (these events can fire rapidly)
        local now = GetTime()
        if now - lastCooldownUpdate >= COOLDOWN_THROTTLE then
            lastCooldownUpdate = now
            pcall(UpdateAllCooldowns)
        end
        
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" 
           or event == "GROUP_ROSTER_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" 
           or event == "PLAYER_ENTERING_WORLD" then
        -- Update visibility when combat/group/zone state changes
        pcall(UpdateAllVisibility)
        -- Start/restart visibility ticker on world enter
        if event == "PLAYER_ENTERING_WORLD" then
            pcall(StartVisibilityTicker)
        end
    end
end)

-- ============================================================================
-- CLICKTHROUGH
-- ============================================================================

-- Apply clickthrough setting to all icons in a tracker
function MultiTrackerFrames:ApplyClickthrough(trackerKey)
    local icons = trackerIcons[trackerKey]
    local trackerFrame = trackerFrames[trackerKey]
    
    local clickthrough = MultiTracker:GetSetting(trackerKey, "clickthrough") or false
    local enableMouse = not clickthrough
    
    -- Helper to recursively set mouse state on frame and all children
    local function SetMouseRecursive(frame, enable)
        if not frame then return end
        
        -- Set mouse enabled state
        if frame.EnableMouse then
            pcall(function() frame:EnableMouse(enable) end)
        end
        
        -- SetMouseClickEnabled for button-type frames
        if frame.SetMouseClickEnabled then
            pcall(function() frame:SetMouseClickEnabled(enable) end)
        end
        
        -- SetMouseMotionEnabled to control hover detection
        if frame.SetMouseMotionEnabled then
            pcall(function() frame:SetMouseMotionEnabled(enable) end)
        end
        
        -- SetHitRectInsets to shrink/restore hit area
        if frame.SetHitRectInsets then
            if enable then
                pcall(function() frame:SetHitRectInsets(0, 0, 0, 0) end)
            else
                pcall(function() frame:SetHitRectInsets(10000, 10000, 10000, 10000) end)
            end
        end
        
        -- Process all children recursively
        if frame.GetChildren then
            local children = {frame:GetChildren()}
            for _, child in ipairs(children) do
                SetMouseRecursive(child, enable)
            end
        end
    end
    
    -- Apply to the tracker container frame itself (but keep drag working in Layout mode)
    if trackerFrame then
        -- Only disable mouse on tracker frame when NOT in layout mode
        local inLayoutMode = TUICD.Layout and TUICD.Layout:IsActive()
        if clickthrough and not inLayoutMode then
            pcall(function() trackerFrame:EnableMouse(false) end)
            pcall(function() trackerFrame:SetHitRectInsets(10000, 10000, 10000, 10000) end)
        else
            pcall(function() trackerFrame:EnableMouse(true) end)
            pcall(function() trackerFrame:SetHitRectInsets(0, 0, 0, 0) end)
        end
    end
    
    -- Apply to all icon frames and their children
    if icons then
        for _, iconFrame in pairs(icons) do
            if iconFrame then
                SetMouseRecursive(iconFrame, enableMouse)
            end
        end
    end
    
    dprint(string.format("[%s] Applied clickthrough: %s", trackerKey, tostring(clickthrough)))
end

-- Apply clickthrough to all trackers
function MultiTrackerFrames:ApplyAllClickthrough()
    for trackerKey in pairs(trackerFrames) do
        self:ApplyClickthrough(trackerKey)
    end
end

-- ============================================================================
-- SLASH COMMAND
-- ============================================================================

SLASH_TUICDMULTIFRAMES1 = "/tuicdmultiframes"
SlashCmdList["TUICDMULTIFRAMES"] = function(msg)
    msg = msg:lower():trim()
    
    if msg == "rebuild" then
        MultiTrackerFrames:RebuildAllTrackers()
        print("|cff00ccff[TUI:CD]|r Rebuilt all multi-tracker frames")
    elseif msg == "enable" then
        MultiTrackerFrames:Enable()
        print("|cff00ccff[TUI:CD]|r MultiTrackerFrames enabled")
    elseif msg == "disable" then
        MultiTrackerFrames:Disable()
        print("|cff00ccff[TUI:CD]|r MultiTrackerFrames disabled")
    elseif msg == "status" then
        print("|cff00ccff[TUI:CD]|r MultiTrackerFrames status:")
        print("  Enabled: " .. (enabled and "YES" or "NO"))
        local count = 0
        for _ in pairs(trackerFrames) do count = count + 1 end
        print("  Active frames: " .. count)
    else
        print("|cff00ccff[TUI:CD]|r MultiTrackerFrames commands:")
        print("  /tuicdmultiframes rebuild - Rebuild all frames")
        print("  /tuicdmultiframes enable - Enable system")
        print("  /tuicdmultiframes disable - Disable system")
        print("  /tuicdmultiframes status - Show status")
    end
end

dprint("MultiTrackerFrames module loaded")
