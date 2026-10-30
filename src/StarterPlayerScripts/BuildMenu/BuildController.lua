-- The brain of the build menu on your screen. It opens and closes the menu, moves the ghost to where you
-- point, and asks the server to place or delete parts (the server has the last word on both).
--
-- Your own LocalScripts can use it too, for example a shop button that opens the menu on a part:
--
--   local Build = require(game.Players.LocalPlayer.PlayerScripts:WaitForChild("BuildMenu"):WaitForChild("BuildController"))
--   Build.Select("Furniture/Table")
--
--   Start()           gets everything ready (BuildClient does this for you)
--   Open() Close() Toggle()
--   Select(id)        start placing a part, by its id ("Tab/Model name") or its catalog entry.
--                     Picking the part you're already placing stops placing.
--   Rotate()          a quarter turn
--   Place()           place it where the ghost is. Gives back true, or false and the reason.
--   DeleteMode(on)    delete mode on (true), off (false), or the other way round (nothing)
--   Delete(model)     delete one of your placed parts (nothing: the one you're pointing at)
--   Stop()            stop placing or deleting
--   AimAt(point)      aim at a spot in the world instead of where the mouse is
--   State()           what the menu is doing right now, as a table

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("BuildMenu")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Grid = require(Shared:WaitForChild("Grid"))
local Ghost = require(script.Parent:WaitForChild("Ghost"))
local MenuUI = require(script.Parent:WaitForChild("MenuUI"))

local player = Players.LocalPlayer
local Keys = Config.Keys
local Theme = Config.Theme

local RANGE = 1000 -- how far away you can point, in studs

local BuildController = {}

local started = false -- Start has begun
local ready = false -- Start has finished
local ui, ghost, remote, placed
local glow -- the red outline on the part you're about to delete
local placeRay, deleteRay -- what the pointing rays go through

local isOpen = false
local mode = "idle" -- "idle", "place" or "delete"
local selected = nil -- the catalog entry you're placing
local turns = 0 -- quarter turns, 0 to 3
local aim = nil -- where the ghost is: { area, spot, good }
local held = nil -- a spot in the world to aim at instead of the mouse (a tap on a phone, or AimAt)
local target = nil -- in delete mode, the placed part you're pointing at
local busy = false -- waiting for the server to answer
local dirty = true -- the parts in BuildParts changed, so the tabs need making again

-- Waits until Start has finished (and starts it if nobody has yet).
local function ensureStarted()
	if not started then
		BuildController.Start()
	end
	while not ready do
		task.wait()
	end
end

local function partsFolder()
	return ReplicatedStorage:FindFirstChild(Config.PartsFolder)
end

-- The catalog entry for an id, or nil. (Catalog.find would wait forever if BuildParts is missing.)
local function findEntry(id)
	if type(id) ~= "string" or not partsFolder() then
		return nil
	end
	return Catalog.find(id)
end

-- The pointing rays never hit the ghost or your own character. When placing they go through placed parts
-- too, so you always aim at the build area underneath.
local function refreshRays()
	local skip = { ghost.folder }
	if player.Character then
		table.insert(skip, player.Character)
	end
	deleteRay.FilterDescendantsInstances = skip
	local skipPlaced = table.clone(skip)
	table.insert(skipPlaced, placed)
	placeRay.FilterDescendantsInstances = skipPlaced
end

local function setMode(newMode)
	mode = newMode
	ui:SetMode(newMode)
end

-- Puts the red outline on `thing` (nil: on nothing).
local function setTarget(thing)
	if thing == target then
		return
	end
	target = thing
	glow.Adornee = thing
	glow.Enabled = thing ~= nil
end

-- The placed part that `part` belongs to, but only if it's yours.
local function ownedRoot(part)
	local thing = part and Grid.placedRoot(part, placed)
	if thing and thing:GetAttribute("Owner") == player.UserId then
		return thing
	end
	return nil
end

-- Your placed part at a spot in the world (a part standing on a floor tile wins over the tile).
local function ownedAt(point)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { placed }
	local found = nil
	for _, part in ipairs(workspace:GetPartBoundsInRadius(point, 0.25, params)) do
		local thing = ownedRoot(part)
		if thing and (not found or found:GetAttribute("Floor") == true) then
			found = thing
		end
	end
	return found
end

-- Where the ghost goes for a ray, or nil when the ray doesn't land on top of a build area.
local function aimFor(origin, direction)
	local hit = workspace:Raycast(origin, direction, placeRay)
	if not hit or not Grid.isArea(hit.Instance) then
		return nil
	end
	local area = hit.Instance
	if hit.Normal:Dot(area.CFrame.UpVector) < 0.5 then
		return nil -- the side or bottom of the area, not the top
	end
	local here = area.CFrame:PointToObjectSpace(hit.Position) -- studs from the area's centre
	local spot = Grid.solve(area, selected, here.X, here.Z, turns)
	return { area = area, spot = spot, good = spot.inside and Grid.isFree(spot, selected, placed) }
end

-- The ray from the mouse into the world, or nil on a phone or tablet.
local function mouseRay()
	local camera = workspace.CurrentCamera
	if not (camera and UserInputService.MouseEnabled) then
		return nil
	end
	local where = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(where.X, where.Y)
end

-- Runs every frame: moves the ghost, or the red outline in delete mode.
local function update(dt)
	if mode == "place" and selected then
		if held then
			-- straight down onto the spot
			aim = aimFor(held + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0))
		else
			local ray = mouseRay()
			aim = ray and aimFor(ray.Origin, ray.Direction * RANGE)
		end
		if aim then
			ghost:Show(selected, aim.spot, aim.good)
		else
			ghost:Hide()
		end
		ghost:Step(dt)
	elseif mode == "delete" then
		if held then
			-- a tap (or AimAt) picked the part: keep it unless it has gone
			if target and target.Parent ~= placed then
				setTarget(nil)
			end
		else
			local ray = mouseRay()
			local hit = ray and workspace:Raycast(ray.Origin, ray.Direction * RANGE, deleteRay)
			setTarget(hit and ownedRoot(hit.Instance))
		end
	end
end

-- Makes the tabs and cards again from what's in BuildParts now.
local function refreshTabs()
	dirty = false
	local tabs = {}
	if partsFolder() then
		tabs = Catalog.tabs()
	end
	ui:ShowTabs(tabs)
	if selected then
		local fresh = findEntry(selected.id)
		if fresh then
			selected = fresh -- the same part, maybe changed
		else
			BuildController.Stop() -- the part you were placing has gone
		end
	end
end

-- Notices when parts are added to or taken out of BuildParts, so the menu shows them next time it opens.
local function watchParts()
	local watched = nil
	local function watch()
		local folder = partsFolder()
		if folder == watched then
			return
		end
		watched = folder
		dirty = true
		if folder then
			local function changed()
				dirty = true
			end
			folder.DescendantAdded:Connect(changed)
			folder.DescendantRemoving:Connect(changed)
		end
	end
	ReplicatedStorage.ChildAdded:Connect(watch)
	ReplicatedStorage.ChildRemoved:Connect(function(child)
		if child == watched then
			watched = nil
			dirty = true
			watch()
		end
	end)
	watch()
end

-- What happens after the server answers: a red message if it said no.
local function finish(ok, reply)
	if not ok or type(reply) ~= "table" then
		local reason = "Something went wrong, try again"
		ui:Flash(reason)
		return false, reason
	end
	if not reply.ok then
		local reason = type(reply.reason) == "string" and reply.reason or "That didn't work"
		ui:Flash(reason)
		return false, reason
	end
	return true
end

-- A tap on a phone or tablet (not on a button).
local function onTap(where, processed)
	if processed or mode == "idle" then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local ray = camera:ScreenPointToRay(where.X, where.Y)
	if mode == "place" then
		local hit = workspace:Raycast(ray.Origin, ray.Direction * RANGE, placeRay)
		if hit and Grid.isArea(hit.Instance) then
			held = hit.Position -- the ghost moves here; the Place button places it
		end
	elseif mode == "delete" then
		local hit = workspace:Raycast(ray.Origin, ray.Direction * RANGE, deleteRay)
		local thing = hit and ownedRoot(hit.Instance)
		if thing and thing == target then
			BuildController.Delete(thing) -- the second tap on the same part
		else
			held = thing and hit.Position or nil
			setTarget(thing) -- the first tap picks it
		end
	end
end

local function onInput(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if processed then
			return -- the click was on a button
		end
		if mode == "place" then
			BuildController.Place()
		elseif mode == "delete" and target then
			BuildController.Delete()
		end
		return
	end
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return -- typing in the chat, for example
	end
	if input.KeyCode == Keys.Toggle then
		BuildController.Toggle()
	elseif input.KeyCode == Keys.Rotate then
		if mode == "place" then
			BuildController.Rotate()
		end
	elseif input.KeyCode == Keys.Delete then
		BuildController.DeleteMode()
	elseif input.KeyCode == Keys.Stop then
		if mode ~= "idle" then
			BuildController.Stop()
		end
	end
end

-- Gets everything ready. BuildClient calls this when you join; calling it again does nothing.
function BuildController.Start()
	if started then
		ensureStarted()
		return BuildController
	end
	started = true

	remote = Shared:WaitForChild("BuildRequest")
	placed = workspace:WaitForChild(Config.PlacedFolder)

	ghost = Ghost.new()
	glow = Instance.new("Highlight")
	glow.Name = "DeleteTarget"
	glow.FillColor = Theme.Bad
	glow.OutlineColor = Theme.Bad
	glow.FillTransparency = 0.5
	glow.OutlineTransparency = 0
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Enabled = false
	glow.Parent = ghost.folder

	placeRay = RaycastParams.new()
	placeRay.FilterType = Enum.RaycastFilterType.Exclude
	deleteRay = RaycastParams.new()
	deleteRay.FilterType = Enum.RaycastFilterType.Exclude
	refreshRays()
	player.CharacterAdded:Connect(refreshRays)

	ui = MenuUI.new({
		toggle = function()
			BuildController.Toggle()
		end,
		pick = function(entry)
			BuildController.Select(entry)
		end,
		delete = function()
			BuildController.DeleteMode()
		end,
		rotate = function()
			BuildController.Rotate()
		end,
		place = function()
			BuildController.Place()
		end,
		stop = function()
			BuildController.Stop()
		end,
	})

	watchParts()
	UserInputService.InputBegan:Connect(onInput)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			held = nil -- the mouse moved, so aim with the mouse again
		end
	end)
	UserInputService.TouchTapInWorld:Connect(onTap)
	RunService:BindToRenderStep("BuildMenu", Enum.RenderPriority.Camera.Value + 1, update)

	ready = true
	return BuildController
end

function BuildController.Open()
	ensureStarted()
	if isOpen then
		return
	end
	isOpen = true
	if dirty then
		refreshTabs()
	end
	ui:SetOpen(true)
end

function BuildController.Close()
	ensureStarted()
	if not isOpen then
		return
	end
	BuildController.Stop()
	isOpen = false
	ui:SetOpen(false)
end

function BuildController.Toggle()
	ensureStarted()
	if isOpen then
		BuildController.Close()
	else
		BuildController.Open()
	end
end

-- Start placing a part. `entryOrId` is a catalog entry or an id like "Walls/Brick Wall".
-- Gives back the entry, or nil if you stopped or there's no such part.
function BuildController.Select(entryOrId)
	ensureStarted()
	local id = type(entryOrId) == "table" and entryOrId.id or entryOrId
	if mode == "place" and selected and selected.id == id then
		BuildController.Stop() -- picking the same part again stops
		return nil
	end
	local entry = findEntry(id)
	if not entry then
		ui:Flash("That part doesn't exist")
		return nil
	end
	BuildController.Open()
	if dirty then
		refreshTabs() -- so the part's tab is in the menu even if it was added while the menu was open
	end
	setTarget(nil)
	selected = entry
	ui:MarkPicked(entry.id)
	ui:SelectTab(entry.tab)
	setMode("place")
	return entry
end

function BuildController.Rotate()
	ensureStarted()
	turns = (turns + 1) % 4
end

-- Asks the server to place the part where the ghost is. Gives back true, or false and the reason.
function BuildController.Place()
	ensureStarted()
	if mode ~= "place" or not selected then
		return false, "Pick a part first"
	end
	if busy then
		return false, "Busy"
	end
	if not aim then
		ui:Flash("Point at the build area")
		return false, "Point at the build area"
	end
	busy = true
	local ok, reply = pcall(remote.InvokeServer, remote, {
		action = "place",
		id = selected.id,
		area = aim.area,
		x = aim.spot.x,
		z = aim.spot.z,
		turns = turns,
	})
	busy = false
	return finish(ok, reply)
end

-- Delete mode on (true), off (false), or the other way round (nothing).
function BuildController.DeleteMode(on)
	ensureStarted()
	if on == nil then
		on = mode ~= "delete"
	end
	if on then
		BuildController.Open()
		selected = nil
		aim = nil
		held = nil
		ghost:Clear()
		ui:MarkPicked(nil)
		setMode("delete")
	elseif mode == "delete" then
		BuildController.Stop()
	end
end

-- Asks the server to delete `model` (nothing: the part you're pointing at). Gives back true, or false and the reason.
function BuildController.Delete(model)
	ensureStarted()
	model = model or target
	if not model then
		ui:Flash("Point at one of your parts")
		return false, "Point at one of your parts"
	end
	if busy then
		return false, "Busy"
	end
	busy = true
	local ok, reply = pcall(remote.InvokeServer, remote, { action = "delete", model = model })
	busy = false
	local done, reason = finish(ok, reply)
	if done and model == target then
		setTarget(nil)
		held = nil
	end
	return done, reason
end

-- Stop placing or deleting (the menu stays open).
function BuildController.Stop()
	ensureStarted()
	selected = nil
	aim = nil
	held = nil
	ghost:Clear()
	setTarget(nil)
	ui:MarkPicked(nil)
	setMode("idle")
end

-- Aim at a spot in the world instead of where the mouse is, until the mouse moves.
-- When placing, the ghost goes there. In delete mode, your part at that spot gets the red outline.
function BuildController.AimAt(point)
	ensureStarted()
	if typeof(point) ~= "Vector3" then
		return
	end
	held = point
	if mode == "delete" then
		setTarget(ownedAt(point))
	end
	update(0)
end

-- What the menu is doing right now.
function BuildController.State()
	local where = nil
	if aim then
		where = {
			area = aim.area,
			x = aim.spot.x,
			z = aim.spot.z,
			inside = aim.spot.inside,
			good = aim.good,
			pivot = aim.spot.pivot,
		}
	end
	return {
		started = started,
		ready = ready,
		open = isOpen,
		mode = mode,
		selected = selected and selected.id or nil,
		turns = turns,
		aim = where,
		target = target,
		busy = busy,
	}
end

return BuildController
