-- Grid maths shared by your screen (where the ghost goes) and the server (where the part really goes),
-- so both always agree.

local Config = require(script.Parent.Config)

local Grid = {}

-- True when `part` is a build area: a part in Workspace named Config.AreaName.
function Grid.isArea(part)
	return typeof(part) == "Instance"
		and part:IsA("BasePart")
		and part.Name == Config.AreaName
		and part:IsDescendantOf(workspace)
end

-- How many grid squares a part covers across (x) and deep (z) after `turns` quarter turns.
function Grid.cells(entry, turns)
	local size = Config.GridSize
	local x = math.max(1, math.ceil(entry.size.X / size - 0.01))
	local z = math.max(1, math.ceil(entry.size.Z / size - 0.01))
	if turns % 2 == 1 then
		x, z = z, x
	end
	return x, z
end

-- Snaps a spot on a build area to the grid and works out everything about putting `entry` there.
-- x and z are studs from the area's centre, in the area's own directions (so turned areas work too).
-- Returns:
--   x, z          the snapped spot (this is what the client sends the server)
--   pivot         the CFrame to PivotTo the model to
--   ground        a CFrame on the area's top surface under the middle of the part
--   box, boxSize  the space the part takes up
--   inside        true when all of it is on the area
function Grid.solve(area, entry, x, z, turns)
	local size = Config.GridSize
	local cellsX, cellsZ = Grid.cells(entry, turns)
	local half = area.Size / 2
	-- the part's corner goes on a grid line, counted from the area's corner
	local minX = math.floor((x - cellsX * size / 2 + half.X) / size + 0.5) * size - half.X
	local minZ = math.floor((z - cellsZ * size / 2 + half.Z) / size + 0.5) * size - half.Z
	local maxX, maxZ = minX + cellsX * size, minZ + cellsZ * size
	local midX, midZ = (minX + maxX) / 2, (minZ + maxZ) / 2
	local height = entry.size.Y
	-- floor tiles sink into the area until only Config.FloorLift sticks out; everything else stands on top
	local baseY = half.Y + (entry.floor and Config.FloorLift - height or 0)
	local bottom = area.CFrame * CFrame.new(midX, baseY, midZ) * CFrame.Angles(0, turns * math.pi / 2, 0)
	local edge = 0.001
	return {
		x = midX,
		z = midZ,
		pivot = bottom * entry.offset,
		ground = area.CFrame * CFrame.new(midX, half.Y, midZ),
		box = area.CFrame * CFrame.new(midX, baseY + height / 2, midZ),
		boxSize = Vector3.new(cellsX * size, height, cellsZ * size),
		inside = minX >= -half.X - edge and maxX <= half.X + edge and minZ >= -half.Z - edge and maxZ <= half.Z + edge,
	}
end

-- The placed model (a child of the PlacedParts folder) that `part` belongs to, or nil.
function Grid.placedRoot(part, placed)
	local thing = part
	while thing and thing.Parent ~= placed do
		thing = thing.Parent
	end
	return thing
end

-- True when nothing already placed is in the way of `spot`. Floor tiles only bump into floor tiles and
-- everything else only into everything else, so walls and furniture can stand on floors.
function Grid.isFree(spot, entry, placed)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { placed }
	-- a little smaller than the squares, so parts can stand right next to each other
	local inside = spot.boxSize - Vector3.new(0.1, 0.1, 0.1)
	for _, part in ipairs(workspace:GetPartBoundsInBox(spot.box, inside, params)) do
		local thing = Grid.placedRoot(part, placed)
		if thing and (thing:GetAttribute("Floor") == true) == entry.floor then
			return false
		end
	end
	return true
end

return Grid
