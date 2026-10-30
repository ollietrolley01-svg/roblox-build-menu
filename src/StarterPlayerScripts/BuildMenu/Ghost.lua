-- The see-through "ghost" that shows where a part will go before you place it: green when it fits,
-- red when it doesn't, standing on a flat plate the size of the grid squares it will cover.
-- It lives under your camera, so only you can see it, and nothing can bump into it or raycast into it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("BuildMenu"):WaitForChild("Config"))

local Theme = Config.Theme

local Ghost = {}
Ghost.__index = Ghost

local SHOWS = 0.55 -- how much of each part still shows in the ghost (1 = all of it, 0 = none)
local PLATE_LIFT = 0.08 -- the plate floats this far above the build area, so it never flickers

-- Things a copy must not keep: scripts would run, prompts and click detectors could be used, sounds would play.
local STRIP = { "LuaSourceContainer", "ProximityPrompt", "ClickDetector", "Sound" }

-- A copy of a model with nothing in it that could run, be clicked or make a noise.
-- The menu uses it for the little pictures on the cards too.
function Ghost.copy(model)
	local copy = model:Clone()
	for _, thing in ipairs(copy:GetDescendants()) do
		for _, class in ipairs(STRIP) do
			if thing:IsA(class) then
				thing:Destroy()
				break
			end
		end
	end
	return copy
end

-- True when an invisible part has nothing on it you could see (no picture, no sign).
local function blank(part)
	return part.Transparency >= 0.99
		and not part:FindFirstChildWhichIsA("Decal")
		and not part:FindFirstChildWhichIsA("SurfaceGui")
end

-- Makes a copy see-through and harmless: it can't be bumped, touched or hit by a raycast, and casts no shadow.
local function ghostly(copy)
	local parts = copy:GetDescendants()
	table.insert(parts, copy)
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			if blank(part) then
				-- The green tint would paint an invisible part (like a hidden root part) as a solid box,
				-- so it shrinks to a dot instead. Its position stays put, so the model's pivot doesn't move.
				part.Size = Vector3.new(0.001, 0.001, 0.001)
			end
			part.Transparency = 1 - (1 - part.Transparency) * SHOWS
		end
	end
end

-- Makes the ghost's folder, tint and plate. Call Show to draw it.
function Ghost.new()
	local self = setmetatable({}, Ghost)

	self.folder = Instance.new("Folder")
	self.folder.Name = "BuildGhost"
	self.folder.Parent = workspace.CurrentCamera

	-- The green or red glow over the copy
	self.tint = Instance.new("Highlight")
	self.tint.Name = "Tint"
	self.tint.FillTransparency = 0.55
	self.tint.OutlineTransparency = 0
	self.tint.DepthMode = Enum.HighlightDepthMode.Occluded
	self.tint.Enabled = false
	self.tint.Parent = self.folder

	-- The flat plate on the ground, with an outline round it
	self.plate = Instance.new("Part")
	self.plate.Name = "Footprint"
	self.plate.Anchored = true
	self.plate.CanCollide = false
	self.plate.CanQuery = false
	self.plate.CanTouch = false
	self.plate.CastShadow = false
	self.plate.Material = Enum.Material.SmoothPlastic
	self.plate.TopSurface = Enum.SurfaceType.Smooth
	self.plate.BottomSurface = Enum.SurfaceType.Smooth
	self.plate.Transparency = 0.5
	self.plate.Size = Vector3.new(1, 0.1, 1)
	self.outline = Instance.new("SelectionBox")
	self.outline.Name = "Outline"
	self.outline.LineThickness = 0.06
	self.outline.SurfaceTransparency = 1
	self.outline.Adornee = self.plate
	self.outline.Parent = self.plate

	self.entry = nil -- the part the copy is of
	self.copy = nil
	self.target = nil -- where the copy is heading
	self.current = nil -- where the copy is now (it glides to the target)
	self.good = nil
	return self
end

-- Draws the ghost of `entry` at `spot` (from Grid.solve). `good` true: green, false: red.
-- Call it every frame; it only makes a new copy when the part changes.
function Ghost:Show(entry, spot, good)
	if self.entry ~= entry then
		self:Clear()
		self.entry = entry
		self.copy = Ghost.copy(entry.model)
		self.copy.Name = "Copy"
		ghostly(self.copy)
	end

	local camera = workspace.CurrentCamera
	if self.folder.Parent ~= camera then
		self.folder.Parent = camera
	end

	self.target = spot.pivot
	if not self.current then
		-- just appeared: jump straight there instead of gliding in from somewhere else
		self.current = spot.pivot
		self.copy:PivotTo(spot.pivot)
	end
	if self.copy.Parent ~= self.folder then
		self.copy.Parent = self.folder
	end
	self.tint.Adornee = self.copy
	self.tint.Enabled = true

	if self.good ~= good then
		self.good = good
		local colour = good and Theme.Good or Theme.Bad
		self.tint.FillColor = colour
		self.tint.OutlineColor = colour
		self.plate.Color = colour
		self.outline.Color3 = colour
	end

	-- the plate snaps straight to the squares the part will cover
	self.plate.Size = Vector3.new(spot.boxSize.X, 0.1, spot.boxSize.Z)
	self.plate.CFrame = spot.ground * CFrame.new(0, PLATE_LIFT, 0)
	if self.plate.Parent ~= self.folder then
		self.plate.Parent = self.folder
	end
end

-- Glides the copy towards where it should be. Call it every frame with the frame time.
function Ghost:Step(dt)
	if not (self.copy and self.target and self.current) or self.copy.Parent == nil then
		return
	end
	self.current = self.current:Lerp(self.target, math.min(1, dt * 20))
	self.copy:PivotTo(self.current)
end

-- Hides the ghost but keeps the copy, for when you point somewhere you can't build.
function Ghost:Hide()
	if self.copy then
		self.copy.Parent = nil
	end
	self.plate.Parent = nil
	self.tint.Enabled = false
	self.tint.Adornee = nil
	self.current = nil
end

-- Hides the ghost and throws the copy away, for when you stop placing.
function Ghost:Clear()
	self:Hide()
	if self.copy then
		self.copy:Destroy()
	end
	self.copy = nil
	self.entry = nil
	self.target = nil
end

return Ghost
