-- The server half of the build menu: the only place parts are really placed or deleted.
-- It trusts nothing a client sends. It checks the part exists, snaps it to the grid itself, checks it fits
-- on a build area with nothing in the way, and only lets you delete your own parts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("BuildMenu")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local Grid = require(Shared.Grid)

local placed = workspace:FindFirstChild(Config.PlacedFolder)
if not placed then
	placed = Instance.new("Folder")
	placed.Name = Config.PlacedFolder
	placed.Parent = workspace
end

local remote = Instance.new("RemoteFunction")
remote.Name = "BuildRequest"
remote.Parent = Shared

local buckets = {} -- [player] = { tokens, time }: how many requests they have left right now

local function allowed(player)
	local now = os.clock()
	local most = Config.RequestsPerSecond * 2
	local bucket = buckets[player] or { tokens = most, time = now }
	bucket.tokens = math.min(most, bucket.tokens + (now - bucket.time) * Config.RequestsPerSecond)
	bucket.time = now
	buckets[player] = bucket
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function isNumber(value)
	return type(value) == "number" and value == value and math.abs(value) < 1e6 -- a real number, not NaN or huge
end

local function countOwned(player)
	local count = 0
	for _, model in ipairs(placed:GetChildren()) do
		if model:GetAttribute("Owner") == player.UserId then
			count += 1
		end
	end
	return count
end

local function place(player, request)
	local entry = Catalog.find(request.id)
	if not entry then
		return { ok = false, reason = "That part doesn't exist" }
	end
	if not Grid.isArea(request.area) then
		return { ok = false, reason = "You can only build on the build area" }
	end
	if not (isNumber(request.x) and isNumber(request.z)) then
		return { ok = false, reason = "That isn't a spot" }
	end
	if countOwned(player) >= Config.MaxPartsPerPlayer then
		return { ok = false, reason = "You've placed as many parts as you can" }
	end
	local turns = isNumber(request.turns) and math.floor(request.turns) % 4 or 0
	local spot = Grid.solve(request.area, entry, request.x, request.z, turns)
	if not spot.inside then
		return { ok = false, reason = "It has to fit on the build area" }
	end
	if not Grid.isFree(spot, entry, placed) then
		return { ok = false, reason = "Something is in the way" }
	end

	local model = entry.model:Clone()
	if Config.AnchorPlacedParts then
		if model:IsA("BasePart") then
			model.Anchored = true
		end
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
	end
	model:PivotTo(spot.pivot)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("PartId", entry.id)
	model:SetAttribute("Floor", entry.floor)
	if model:IsA("Model") then
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- with streaming on, it arrives all at once
	end
	model.Parent = placed
	return { ok = true }
end

local function delete(player, request)
	local model = request.model
	if typeof(model) ~= "Instance" or model.Parent ~= placed then
		return { ok = false, reason = "That isn't a placed part" }
	end
	if model:GetAttribute("Owner") ~= player.UserId then
		return { ok = false, reason = "You can only delete your own parts" }
	end
	model:Destroy()
	return { ok = true }
end

remote.OnServerInvoke = function(player, request)
	if type(request) ~= "table" then
		return { ok = false, reason = "Bad request" }
	end
	if not allowed(player) then
		return { ok = false, reason = "Slow down a little" }
	end
	if request.action == "place" then
		return place(player, request)
	elseif request.action == "delete" then
		return delete(player, request)
	end
	return { ok = false, reason = "Bad request" }
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	if Config.RemovePartsOnLeave then
		for _, model in ipairs(placed:GetChildren()) do
			if model:GetAttribute("Owner") == player.UserId then
				model:Destroy()
			end
		end
	end
end)
