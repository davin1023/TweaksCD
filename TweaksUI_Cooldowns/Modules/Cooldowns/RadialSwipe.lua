

local addonName,TUICD = ...

local RadialSwipe = {}

TUICD.RadialSwipe = RadialSwipe

-- Register inTweaksUI_Cooldowns namespaceTweaksUI_Cooldowns.RadialSwipe = RadialSwipe

-- =====================================================
-- CONSTANTS
-- =====================================================

-- Cooldowns longer than 2000ms (2 sec) are "real" cooldowns, not GCD (~1500ms)
local GCD_THRESHOLD = 2000

-- =====================================================
-- VERTEX CONSTANTS
-- =====================================================

local UPPER_LEFT_VERTEX = 1
local LOWER_LEFT_VERTEX = 2
local UPPER_RIGHT_VERTEX = 3
local LOWER_RIGHT_VERTEX = 4

-- =====================================================
-- HELPER FUNCTIONS
-- =====================================================

local floor = math.floor
local cos = math.cos
local sin = math.sin
local tan = math.tan
local rad = math.rad

-- =====================================================
-- TEXTURE COORDINATE SYSTEM
-- =====================================================

local TextureCoords = {}
TextureCoords.__index = TextureCoords

-- Default texture coordinate positions (corners of a square: 0,0 to 1,1)
local defaultTexCoord = {
  ULx = 0, ULy = 0,  -- Upper Left
  LLx = 0, LLy = 1,  -- Lower Left
  URx = 1, URy = 0,  -- Upper Right
  LRx = 1, LRy = 1,  -- Lower Right
}

-- Pre-calculated coordinates for exact 45-degree angles
local exactAngles = {
  {0.5, 0},    -- 0°
  {1, 0},      -- 45°
  {1, 0.5},    -- 90°
  {1, 1},      -- 135°
  {0.5, 1},    -- 180°
  {0, 1},      -- 225°
  {0, 0.5},    -- 270°
  {0, 0}       -- 315°
}

-- Pattern for which corners to use based on starting angle
-- This cycles through the corners in a specific order for proper wedge formation
local pointOrder = { 
  "LL", "UL", "UR", "LR", 
  "LL", "UL", "UR", "LR", 
  "LL", "UL", "UR", "LR" 
}

-- Convert angle (in degrees) to texture coordinate (0-1 range)
local function angleToCoord(angle)
  angle = angle % 360

  -- Use exact values for 45-degree increments (more precise)
  if (angle % 45 == 0) then
    local index = floor(angle / 45) + 1
    return exactAngles[index][1], exactAngles[index][2]
  end

  -- Calculate coordinate on the edge of the texture square
  -- Uses tangent to find where the angle ray intersects the square edges
  if (angle < 45) then
    return 0.5 + tan(rad(angle)) / 2, 0
  elseif (angle < 135) then
    return 1, 0.5 + tan(rad(angle - 90)) / 2
  elseif (angle < 225) then
    return 0.5 - tan(rad(angle)) / 2, 1
  elseif (angle < 315) then
    return 0, 0.5 - tan(rad(angle - 90)) / 2
  elseif (angle < 360) then
    return 0.5 + tan(rad(angle)) / 2, 0
  end
end

-- Transform a texture coordinate point (rotation, scaling, mirroring)
local function TransformPoint(x, y, scalex, scaley, texRotation, mirror_h, mirror_v)
  -- Center the coordinate
  x = x - 0.5
  y = y - 0.5

  -- Apply user scaling (removed sqrt(2) scaling that distorts textures)
  x = x / scalex
  y = y / scaley

  -- Apply mirroring
  if mirror_h then
    x = -x
  end
  if mirror_v then
    y = -y
  end

  -- Apply rotation
  local cos_rotation = cos(texRotation)
  local sin_rotation = sin(texRotation)
  x, y = cos_rotation * x - sin_rotation * y, sin_rotation * x + cos_rotation * y

  -- Move back from center
  x = x + 0.5
  y = y + 0.5

  return x, y
end

-- Create a new texture coordinate handler
function TextureCoords:New(texture)
  local coords = setmetatable({}, TextureCoords)
  coords.texture = texture

  -- Texture coordinates (0-1 range, where texture content is mapped)
  coords.ULx, coords.ULy = 0, 0
  coords.LLx, coords.LLy = 0, 1
  coords.URx, coords.URy = 1, 0
  coords.LRx, coords.LRy = 1, 1

  -- Vertex offsets (pixel offsets for physically moving corners)
  coords.ULvx, coords.ULvy = 0, 0
  coords.LLvx, coords.LLvy = 0, 0
  coords.URvx, coords.URvy = 0, 0
  coords.LRvx, coords.LRvy = 0, 0

  return coords
end

-- Move a corner to a specific texture coordinate position
function TextureCoords:MoveCorner(width, height, corner, x, y)
  -- Calculate how far this corner moved from its default position
  local rx = defaultTexCoord[corner .. "x"] - x
  local ry = defaultTexCoord[corner .. "y"] - y

  -- Convert to pixel offsets (this physically pulls the corner)
  self[corner .. "vx"] = -rx * width
  self[corner .. "vy"] = ry * height

  -- Store the texture coordinate
  self[corner .. "x"] = x
  self[corner .. "y"] = y
end

-- Apply the coordinates and show the texture
function TextureCoords:Show()
  self:Apply()
  self.texture:Show()
end

-- Hide the texture
function TextureCoords:Hide()
  self.texture:Hide()
end

-- Apply vertex offsets and texture coordinates to the WoW texture object
function TextureCoords:Apply()
  -- Move the physical vertices (creates the wedge shape)
  self.texture:SetVertexOffset(UPPER_RIGHT_VERTEX, self.URvx, self.URvy)
  self.texture:SetVertexOffset(UPPER_LEFT_VERTEX, self.ULvx, self.ULvy)
  self.texture:SetVertexOffset(LOWER_RIGHT_VERTEX, self.LRvx, self.LRvy)
  self.texture:SetVertexOffset(LOWER_LEFT_VERTEX, self.LLvx, self.LLvy)

  -- Map texture coordinates to those vertices
  self.texture:SetTexCoord(self.ULx, self.ULy, self.LLx, self.LLy, self.URx, self.URy, self.LRx, self.LRy)
end

-- Reset to show full texture (no wedge)
function TextureCoords:SetFull()
  self.ULx, self.ULy = 0, 0
  self.LLx, self.LLy = 0, 1
  self.URx, self.URy = 1, 0
  self.LRx, self.LRy = 1, 1

  self.ULvx, self.ULvy = 0, 0
  self.LLvx, self.LLvy = 0, 0
  self.URvx, self.URvy = 0, 0
  self.LRvx, self.LRvy = 0, 0
end

-- Set coordinates to create a wedge between two angles
function TextureCoords:SetAngle(width, height, angle1, angle2)
  -- Determine which quadrant the start angle is in
  local index = floor((angle1 + 45) / 90)

  -- Get the corner names based on the quadrant
  local middleCorner = pointOrder[index + 1]  -- Center point
  local startCorner = pointOrder[index + 2]   -- Where wedge starts
  local endCorner1 = pointOrder[index + 3]    -- First end point
  local endCorner2 = pointOrder[index + 4]    -- Second end point

  -- Position the corners
  self:MoveCorner(width, height, middleCorner, 0.5, 0.5)  -- Center
  self:MoveCorner(width, height, startCorner, angleToCoord(angle1))  -- Start edge

  -- Determine if we need corner bridging
  local edge1 = floor((angle1 - 45) / 90)
  local edge2 = floor((angle2 - 45) / 90)

  if (edge1 == edge2) then
    -- Simple case: both angles in same zone
    self:MoveCorner(width, height, endCorner1, angleToCoord(angle2))
  else
    -- Complex case: need to bridge across zone boundary
    self:MoveCorner(width, height, endCorner1, 
                    defaultTexCoord[endCorner1 .. "x"], 
                    defaultTexCoord[endCorner1 .. "y"])
  end

  -- Always set the final end corner
  self:MoveCorner(width, height, endCorner2, angleToCoord(angle2))
end

-- Apply transformations to all corners
function TextureCoords:Transform(scalex, scaley, texRotation, mirror_h, mirror_v)
  self.ULx, self.ULy = TransformPoint(self.ULx, self.ULy, scalex, scaley, texRotation, mirror_h, mirror_v)
  self.LLx, self.LLy = TransformPoint(self.LLx, self.LLy, scalex, scaley, texRotation, mirror_h, mirror_v)
  self.URx, self.URy = TransformPoint(self.URx, self.URy, scalex, scaley, texRotation, mirror_h, mirror_v)
  self.LRx, self.LRy = TransformPoint(self.LRx, self.LRy, scalex, scaley, texRotation, mirror_h, mirror_v)
end

-- =====================================================
-- RADIAL SWIPE (MAIN API)
-- =====================================================

--Initialize Radial Swipe
function RadialSwipe:InitializeRadialSwipe(parent, size)
	parent.radialSwipe = RadialSwipe:CreateSpinner(parent)
    parent.radialSwipe:SetTexture("Interface\\AddOns\\TweaksUI_Cooldowns\\Media\\Textures\\square_outline.tga")  -- Hexagon texture
    parent.radialSwipe:SetColor(1, 1, 1, 1)  -- White overlay
    parent.radialSwipe:SetBlendMode("BLEND")
    parent.radialSwipe:SetSize(size, size)  -- Match parent size, not hardcoded 200x200
    parent.radialSwipe:SetProgressValue(1, 0, 360) --start with a full icon display
    parent.radialSwipe:Hide()  -- Hidden when no cooldown
    parent.radialSwipeDefaultSize = size
end

-- Create a new radial swipe spinner
function RadialSwipe:CreateSpinner(parent)
  local spinner = {
    parent = parent,
    textures = {},
    coords = {},
    angle1 = 0,
    angle2 = 360,
    crop_x = 1,
    crop_y = 1,
    texRotation = 0,
    scalex = 1,
    scaley = 1,
    mirror = false,
    mirror_h = false,
    mirror_v = false,
    visible = false,
    width = 100,
    height = 100,
    offset = 0
  }

  -- Create 3 textures (for handling different angle ranges)
  for i = 1, 3 do
    local texture = parent:CreateTexture(nil, "OVERLAY")
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    texture:SetTexCoord(0, 1, 0, 1)  -- Ensure proper texture mapping
    texture:SetAllPoints(parent)
    spinner.textures[i] = texture
    spinner.coords[i] = TextureCoords:New(texture)
  end

  setmetatable(spinner, {__index = RadialSwipe})
  return spinner
end

-- Set the texture image file
function RadialSwipe:SetTexture(texturePath)
  for i = 1, 3 do
    self.textures[i]:SetTexture(texturePath)
  end
end

-- Set the color/tint of the texture
function RadialSwipe:SetColor(r, g, b, a)
  for i = 1, 3 do
    self.textures[i]:SetVertexColor(r, g, b, a)
  end
end

-- Set the blend mode
function RadialSwipe:SetBlendMode(blendMode)
  for i = 1, 3 do
    self.textures[i]:SetBlendMode(blendMode)
  end
end

-- Set desaturation
function RadialSwipe:SetDesaturated(desaturated)
  for i = 1, 3 do
    self.textures[i]:SetDesaturated(desaturated)
  end
end

-- Set position offset
function RadialSwipe:SetOffset(x, y)
  self.offsetX = x or 0
  self.offsetY = y or 0
  -- Update texture positions
  for i = 1, 3 do
    self.textures[i]:ClearAllPoints()
    self.textures[i]:SetPoint("CENTER", self.parent, "CENTER", self.offsetX, self.offsetY)
    self.textures[i]:SetSize(self.width, self.height)
  end
end

-- Set rotation (in degrees)
function RadialSwipe:SetRotation(rotation)
  -- Convert degrees to radians (Lua's trig functions use radians)
  self.texRotation = rad(rotation or 0)
  -- Rotation will be applied in UpdateTextures through texture coordinate transformation
  if self.visible then
    self:UpdateTextures()
  end
end

-- Show the spinner
function RadialSwipe:Show()
  self.visible = true
  self:UpdateTextures()
end

-- Hide the spinner
function RadialSwipe:Hide()
  self.visible = false
  for i = 1, 3 do
    self.textures[i]:Hide()
  end
end

-- Set the width
function RadialSwipe:SetWidth(width)
  self.width = width
end

-- Set the height
function RadialSwipe:SetHeight(height)
  self.height = height
end

-- Set both width and height
function RadialSwipe:SetSize(width, height)
  self.width = width
  self.height = height

  -- Resize and center the textures (apply current offset if set)
  local offsetX = self.offsetX or 0
  local offsetY = self.offsetY or 0
  for i = 1, 3 do
    self.textures[i]:ClearAllPoints()
    self.textures[i]:SetSize(width, height)
    self.textures[i]:SetPoint("CENTER", self.parent, "CENTER", offsetX, offsetY)
  end
	self:UpdateTextures()
end

-- Set rotation (in radians)
function RadialSwipe:SetAuraRotation(radians)
  for i = 1, 3 do
    self.textures[i]:SetRotation(radians)
  end
end

-- Set texture coordinate rotation
function RadialSwipe:SetTexRotation(rotation)
  self.texRotation = rotation
  self:UpdateTextures()
end

-- Set mirroring
function RadialSwipe:SetMirror(mirror)
  self.mirror = mirror
  self:UpdateTextures()
end

-- Set cropping
function RadialSwipe:SetCropX(crop_x)
  self.crop_x = crop_x
  self:UpdateTextures()
end

function RadialSwipe:SetCropY(crop_y)
  self.crop_y = crop_y
  self:UpdateTextures()
end

-- Set scale
function RadialSwipe:SetScale(scalex, scaley)
  self.scalex = scalex or 1
  self.scaley = scaley or 1

  -- Handle negative scale as mirroring
  if self.scalex < 0 then
    self.mirror_h = true
    self.scalex = -self.scalex
  end
  if self.scaley < 0 then
    self.mirror_v = true
    self.scaley = -self.scaley
  end

  self:UpdateTextures()
end

function RadialSwipe:OnUpdate(parentFrame)
	if not parentFrame.cooldown or not parentFrame.cooldown.GetCooldownTimes then
		return
	end
	
	local start, duration = parentFrame.cooldown:GetCooldownTimes()
	
	-- Initialize cooldown tracking on first call (requires valid cooldown data)
	if not parentFrame.radialSwipe.realCooldownStart or not parentFrame.radialSwipe.realCooldownDuration then 
		local startSec = start / 1000
		local durationSec = duration / 1000
		parentFrame.radialSwipe.realCooldownStart = startSec
		parentFrame.radialSwipe.realCooldownDuration = durationSec
	end

	local currentTime = GetTime()
	local elapsed = currentTime - parentFrame.radialSwipe.realCooldownStart
	local progress = elapsed / parentFrame.radialSwipe.realCooldownDuration

	-- Exit conditions: cooldown cancelled, completed, or it's actually a GCD
	if 
    parentFrame.isOnCooldown == false
    or progress >= 1
    or (not start or not duration or duration == 0 or duration < GCD_THRESHOLD) then
		-- Cooldown finished/cancelled/GCD - stop recursion and apply final visibility
		local radialDisplayState = TUICD.CooldownHighlights:GetState(parentFrame.trackerKey, "radialSwipe.displayState." .. parentFrame.slotIndex) or "always"
		if radialDisplayState == "always" or radialDisplayState == "available" then
			parentFrame.radialSwipe:SetProgressValue(1, 0, 360)
			parentFrame.radialSwipe:Show()
		else
			parentFrame.radialSwipe:Hide()
		end
		
		-- Clear tracking
		parentFrame.radialSwipe.realCooldownActive = false
		parentFrame.radialSwipe.realCooldownStart = nil
		parentFrame.radialSwipe.realCooldownDuration = nil
	else
		-- Continue animating - update display and recurse with throttling
		parentFrame.radialSwipe:SetProgressValue(progress, 0, 360)
		parentFrame.radialSwipe:Show()
		-- Recursive call with 50ms throttle (20 Hz update rate)
		C_Timer.After(0.05, function()
			RadialSwipe:OnUpdate(parentFrame)
		end)
	end
end

-- Update the texture geometry based on current angles
function RadialSwipe:UpdateTextures()
  if not self.visible then 
    return 
  end

  local angle1 = self.angle1
  local angle2 = self.angle2

  if not angle1 or not angle2 then 
    return 
  end

  local width = self.width * self.scalex + 2 * self.offset
  local height = self.height * self.scaley + 2 * self.offset

  if width == 0 or height == 0 then 
    return 
  end

  local crop_x = self.crop_x
  local crop_y = self.crop_y
  local texRotation = self.texRotation
  local mirror_h = self.mirror_h
  if self.mirror then
    mirror_h = not mirror_h
  end
  local mirror_v = self.mirror_v

  -- CASE 1: Full circle (360°)
  if angle2 - angle1 >= 360 then
    self.coords[1]:SetFull()
    self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
    self.coords[1]:Show()
    self.coords[2]:Hide()
    self.coords[3]:Hide()
    return
  end

  -- CASE 2: No progress (0°)
  if angle1 == angle2 then
    self.coords[1]:Hide()
    self.coords[2]:Hide()
    self.coords[3]:Hide()
    return
  end

  -- CASE 3: Partial arc - determine how many segments needed
  local index1 = floor((angle1 + 45) / 90)
  local index2 = floor((angle2 + 45) / 90)

  if index1 + 1 >= index2 then
    -- Single segment (arc < ~135°)
    self.coords[1]:SetAngle(width, height, angle1, angle2)
    self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
    self.coords[1]:Show()
    self.coords[2]:Hide()
    self.coords[3]:Hide()

  elseif index1 + 3 >= index2 then
    -- Two segments (arc ~135-315°)
    local firstEndAngle = (index1 + 1) * 90 + 45

    self.coords[1]:SetAngle(width, height, angle1, firstEndAngle)
    self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
    self.coords[1]:Show()

    self.coords[2]:SetAngle(width, height, firstEndAngle, angle2)
    self.coords[2]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
    self.coords[2]:Show()

    self.coords[3]:Hide()

  else
    -- Three segments (arc ~315-360°)
    local firstEndAngle = (index1 + 1) * 90 + 45
    local secondEndAngle = firstEndAngle + 180

    self.coords[1]:SetAngle(width, height, angle1, firstEndAngle)
    self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
    self.coords[1]:Show()

    self.coords[2]:SetAngle(width, height, firstEndAngle, secondEndAngle)
    self.coords[2]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
    self.coords[2]:Show()

    self.coords[3]:SetAngle(width, height, secondEndAngle, angle2)
    self.coords[3]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
    self.coords[3]:Show()
  end
end

-- Set the progress angles directly
function RadialSwipe:SetProgress(angle1, angle2)
  self.angle1 = angle1
  self.angle2 = angle2
  self:UpdateTextures()
end

-- Set progress as percentage (0-1) - CLOCKWISE fill
function RadialSwipe:SetProgressValue(progress, startAngle, endAngle)
  startAngle = startAngle or 0
  endAngle = endAngle or 360
  progress = math.max(0, math.min(1, progress))

  local angle = (endAngle - startAngle) * progress + startAngle
  self:SetProgress(startAngle, angle)
end

-- Set progress as percentage (0-1) - COUNTERCLOCKWISE drain (for cooldowns)
function RadialSwipe:SetProgressValueInverse(progress, startAngle, endAngle)
  startAngle = startAngle or 0
  endAngle = endAngle or 360
  progress = math.max(0, math.min(1, progress))
  progress = 1 - progress  -- Invert

  local angle = (endAngle - startAngle) * progress + startAngle
  self:SetProgress(angle, endAngle)
end

--[[
Wild growth: Interface\PVPFrame\Icons\PVP-Banner-Emblem-5
Innervate: Interface\PVPFrame\Icons\PVP-Banner-Emblem-56
green wings thing: Interface\PVPFrame\Icons\PVP-Banner-Emblem-31
single tree: Interface\PVPFrame\Icons\PVP-Banner-Emblem-75
bird claw: Interface\PVPFrame\Icons\PVP-Banner-Emblem-3
dragon roar: Interface\PVPFrame\Icons\PVP-Banner-Emblem-26
mystical orb: Interface\PVPFrame\Icons\PVP-Banner-Emblem-73
arcane blast: Interface\PVPFrame\Icons\PVP-Banner-Emblem-74
smoke: Interface\Custom\smoke.tga
health pot: Interface\PVPFrame\Icons\PVP-Banner-Emblem-22
bull head: Interface\PVPFrame\Icons\PVP-Banner-Emblem-2
cleanse: Interface\custom\cleanse.tga
shield: Interface\PVPFrame\Icons\PVP-Banner-Emblem-10
bear paw: Interface\PVPFrame\Icons\PVP-Banner-Emblem-91
bird: Interface\custom\phoenix.tga
fist: Interface\PVPFrame\Icons\PVP-Banner-Emblem-69
angel: Interface\custom\lastwings.tga
]]