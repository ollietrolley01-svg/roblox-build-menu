-- Reads the parts you can place from ReplicatedStorage.BuildParts.
--
--   BuildParts
--     Walls            <- a Folder is a tab in the menu
--       Brick Wall     <- a Model (or a single Part) is a card in that tab
--
-- Optional attributes (Properties window > Attributes > +):
--   on a tab folder   Order (number, lower comes first), Floor (true: everything in it is a floor tile)
--   on a model        DisplayName (text on the card), Order (number), Floor (true: a floor tile)
-- Floor tiles lie flat and only bump into other floor tiles, so walls and furniture can stand on them.
-- Parts straight inside BuildParts (not in a folder) go in an "Other" tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local Catalog = {}

local OTHER = "Other"
local measured = setmetatable({}, { __mode = "k" }) -- [model] = its entry, worked out once

local function partsFolder()
	return ReplicatedStorage:WaitForChild(Config.PartsFolder)
end

local function usable(thing)
	if thing:IsA("BasePart") then
		return true
	end
	return thing:IsA("Model") and thing:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function orderOf(thing)
	local order = thing:GetAttribute("Order")
	return type(order) == "number" and order or math.huge
end

local function sorted(a, b)
	if a.order ~= b.order then
		return a.order < b.order
	end
	return a.name < b.name
end

-- The menu entry for one model: its name, which tab it's in, and its size.
function Catalog.entry(model, tab)
	local entry = measured[model]
	if entry then
		return entry
	end
	local box, size
	if model:IsA("BasePart") then
		box, size = model.CFrame, model.Size
	else
		box, size = model:GetBoundingBox()
	end
	local bottom = box * CFrame.new(0, -size.Y / 2, 0)
	local tabName = tab and tab.Name or OTHER
	entry = {
		id = tabName .. "/" .. model.Name,
		name = model:GetAttribute("DisplayName") or model.Name,
		tab = tabName,
		order = orderOf(model),
		model = model,
		size = size,
		offset = bottom:ToObjectSpace(model:GetPivot()), -- the model's pivot, seen from its bottom centre
		floor = model:GetAttribute("Floor") == true or (tab ~= nil and tab:GetAttribute("Floor") == true),
	}
	measured[model] = entry
	return entry
end

-- Every tab with its parts, in menu order: { { name, items = { entry, ... } }, ... }
function Catalog.tabs()
	local tabs = {}
	local loose = {}
	for _, child in ipairs(partsFolder():GetChildren()) do
		if child:IsA("Folder") then
			local tab = { name = child.Name, order = orderOf(child), items = {} }
			for _, model in ipairs(child:GetChildren()) do
				if usable(model) then
					table.insert(tab.items, Catalog.entry(model, child))
				end
			end
			if #tab.items > 0 then
				table.insert(tabs, tab)
			end
		elseif usable(child) then
			table.insert(loose, Catalog.entry(child, nil))
		end
	end
	if #loose > 0 then
		table.insert(tabs, { name = OTHER, order = math.huge, items = loose })
	end
	table.sort(tabs, sorted)
	for _, tab in ipairs(tabs) do
		table.sort(tab.items, sorted)
	end
	return tabs
end

-- The entry for an id like "Walls/Brick Wall", or nil if there's no such part.
function Catalog.find(id)
	if type(id) ~= "string" then
		return nil
	end
	local tabName, name = string.match(id, "^(.-)/(.+)$")
	if not tabName then
		return nil
	end
	local root = partsFolder()
	local tab = root:FindFirstChild(tabName)
	local model
	if tab and tab:IsA("Folder") then
		model = tab:FindFirstChild(name)
	elseif tabName == OTHER then
		tab = nil
		model = root:FindFirstChild(name)
	end
	if model and usable(model) then
		return Catalog.entry(model, tab)
	end
	return nil
end

return Catalog
