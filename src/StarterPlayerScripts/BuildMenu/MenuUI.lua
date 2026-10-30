-- Everything the build menu draws on your screen: the Build button, the panel with tabs and part cards,
-- the bar that tells you what to do while you place or delete, and the red messages when something
-- doesn't work. It only draws things. BuildController decides what happens when you press them.
--
-- Labels are plain words on purpose: Roblox draws many emoji and symbols as blank squares.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("BuildMenu"):WaitForChild("Config"))
local Ghost = require(script.Parent:WaitForChild("Ghost"))

local Theme = Config.Theme
local Keys = Config.Keys

local MenuUI = {}
MenuUI.__index = MenuUI

local PANEL_HEIGHT = 172
local BAR_HEIGHT = 44
local GAP = 8 -- space between the panel, the bar and the bottom of the screen
local CARD_WIDTH, CARD_HEIGHT = 104, 110
local MOST_WIDTH = 960
local FOV = 40 -- how wide the card pictures' camera sees, in degrees
local VIEW_FROM = Vector3.new(0.8, 0.7, -1).Unit -- card pictures look from the front right, a bit above (the front is -Z)
local SLIDE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_TIME = 1.6

-- What the bar says in each mode, on a computer and on a phone or tablet
local HINTS = {
	place = "Click the build area to place it",
	delete = "Click one of your parts to delete it",
}
local TOUCH_HINTS = {
	place = "Tap the build area to aim, then press Place",
	delete = "Tap one of your parts, then tap it again to delete it",
}

-- Makes an Instance and sets its properties. The Parent is set last, which is faster.
local function make(class, props)
	local thing = Instance.new(class)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			thing[key] = value
		end
	end
	thing.Parent = props.Parent
	return thing
end

-- Rounds the corners of a frame or button.
local function round(thing, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = thing })
end

-- A text button in the menu's colours.
local function button(props)
	props.BackgroundColor3 = props.BackgroundColor3 or Theme.Card
	props.TextColor3 = props.TextColor3 or Theme.Text
	props.TextSize = props.TextSize or 16
	props.Font = Theme.Font
	props.AutoButtonColor = true
	props.BorderSizePixel = 0
	local parent = props.Parent
	props.Parent = nil
	local thing = make("TextButton", props)
	round(thing, 8)
	thing.Parent = parent
	return thing
end

-- A line of text with no background.
local function label(props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or Theme.Text
	props.TextSize = props.TextSize or 16
	props.Font = Theme.Font
	return make("TextLabel", props)
end

-- A little 3D picture of a part, for its card.
local function preview(entry, size)
	local view = make("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = size,
	})
	local copy = Ghost.copy(entry.model)
	local box, boxSize
	if copy:IsA("BasePart") then
		box, boxSize = copy.CFrame, copy.Size
	else
		box, boxSize = copy:GetBoundingBox()
	end
	-- back off far enough that a ball round the whole part fits in the picture
	local radius = boxSize.Magnitude / 2
	local distance = radius / math.sin(math.rad(FOV / 2)) * 1.05
	local from = box:VectorToWorldSpace(VIEW_FROM) -- "front right" of the part itself, even if it's turned
	local camera = make("Camera", {
		FieldOfView = FOV,
		CFrame = CFrame.lookAt(box.Position + from * distance, box.Position),
		Parent = view,
	})
	view.CurrentCamera = camera
	view.LightDirection = -from -- the light comes from behind the camera, so the side you see is lit
	copy.Parent = view
	return view
end

-- A card for one part: its picture, its name, and an orange outline when it's the one you picked.
local function card(entry, order, picked)
	local thing = make("TextButton", {
		Name = entry.name,
		Text = "",
		AutoButtonColor = true,
		BackgroundColor3 = Theme.Card,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
	})
	thing:SetAttribute("PartId", entry.id)
	round(thing, 8)
	local stroke = make("UIStroke", {
		Name = "Picked",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, -- outline the card, not its text
		Color = Theme.Accent,
		Thickness = 3,
		Enabled = picked,
		Parent = thing,
	})
	local picture = preview(entry, UDim2.fromOffset(CARD_WIDTH - 8, 76))
	picture.Position = UDim2.fromOffset(4, 4)
	picture.Parent = thing
	local name = label({
		Name = "Label",
		Text = entry.name,
		TextScaled = true, -- long names shrink to fit
		TextWrapped = true,
		Position = UDim2.fromOffset(4, 82),
		Size = UDim2.fromOffset(CARD_WIDTH - 8, 24),
		Parent = thing,
	})
	make("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 8, Parent = name })
	return thing, stroke
end

-- Builds the whole menu. `actions` are the functions its buttons call:
-- toggle(), pick(entry), delete(), rotate(), place() and stop().
function MenuUI.new(actions)
	local self = setmetatable({}, MenuUI)
	self.actions = actions
	self.touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled -- a phone or tablet
	self.open = false
	self.mode = "idle"
	self.tabs = {}
	self.tab = nil -- the name of the tab you're looking at
	self.picked = nil -- the id of the card with the outline
	self.tabButtons = {}
	self.cardStrokes = {}
	self.scale = 1
	self.slideCount = 0
	self.flashCount = 0

	local function keyText(key)
		return self.touch and "" or ("  [" .. key.Name .. "]")
	end

	self.gui = make("ScreenGui", {
		Name = "BuildMenu",
		ResetOnSpawn = false, -- keep the menu when you respawn
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	-- The Build button on the left
	self.toggle = button({
		Name = "Toggle",
		Text = "Build" .. keyText(Keys.Toggle),
		TextSize = 18,
		BackgroundColor3 = Theme.Panel,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(self.touch and 96 or 124, 44),
		Parent = self.gui,
	})
	self.toggleStroke = make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Theme.Accent,
		Thickness = 2,
		Enabled = false,
		Parent = self.toggle,
	})
	self.toggle.Activated:Connect(function()
		actions.toggle()
	end)

	-- The panel at the bottom
	self.panel = make("Frame", {
		Name = "Panel",
		Active = true, -- clicks on the panel stay on the panel and don't place anything behind it
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(MOST_WIDTH, PANEL_HEIGHT),
		Visible = false,
		Parent = self.gui,
	})
	round(self.panel, 12)
	self.panelScale = make("UIScale", { Parent = self.panel })

	-- The tabs along the top of the panel
	self.tabsFrame = make("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -134, 0, 30),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Muted,
		Parent = self.panel,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.tabsFrame,
	})

	-- The Delete button at the top right
	self.deleteButton = button({
		Name = "Delete",
		Text = "Delete" .. keyText(Keys.Delete),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(110, 30),
		Parent = self.panel,
	})
	self.deleteButton.Activated:Connect(function()
		actions.delete()
	end)

	-- The row of part cards
	self.cards = make("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 46),
		Size = UDim2.new(1, -16, 0, 118),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Muted,
		Parent = self.panel,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.cards,
	})

	-- What the panel says when there are no parts yet
	self.empty = label({
		Name = "Empty",
		Text = "add Models to ReplicatedStorage." .. Config.PartsFolder,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(8, 46),
		Size = UDim2.new(1, -16, 0, CARD_HEIGHT),
		Visible = false,
		Parent = self.panel,
	})

	-- The bar above the panel: what to do now, and the Rotate, Place and Stop buttons
	self.bar = make("Frame", {
		Name = "ActionBar",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(MOST_WIDTH, BAR_HEIGHT),
		Visible = false,
		Parent = self.gui,
	})
	round(self.bar, 10)
	self.barScale = make("UIScale", { Parent = self.bar })
	self.hint = label({
		Name = "Hint",
		TextColor3 = Theme.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -12, 1, 0),
		Parent = self.bar,
	})
	local buttons = make("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(1, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(0, 34),
		Parent = self.bar,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttons,
	})
	self.rotateButton = button({
		Name = "Rotate",
		Text = "Rotate" .. keyText(Keys.Rotate),
		LayoutOrder = 1,
		Size = UDim2.fromOffset(self.touch and 88 or 112, 34),
		Visible = false,
		Parent = buttons,
	})
	self.placeButton = button({
		Name = "Place",
		Text = "Place",
		TextColor3 = Theme.Panel,
		BackgroundColor3 = Theme.Good,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(88, 34),
		Visible = false,
		Parent = buttons,
	})
	self.stopButton = button({
		Name = "Stop",
		Text = "Stop" .. keyText(Keys.Stop),
		LayoutOrder = 3,
		Size = UDim2.fromOffset(self.touch and 80 or 96, 34),
		Visible = false,
		Parent = buttons,
	})
	self.rotateButton.Activated:Connect(function()
		actions.rotate()
	end)
	self.placeButton.Activated:Connect(function()
		actions.place()
	end)
	self.stopButton.Activated:Connect(function()
		actions.stop()
	end)

	-- The red message that pops up when something doesn't work, just above the bar
	self.flash = label({
		Name = "Flash",
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Theme.Panel,
		TextColor3 = Theme.Bad,
		AnchorPoint = Vector2.new(0.5, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		Visible = false,
		Parent = self.gui,
	})
	round(self.flash, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = self.flash })
	self.flashScale = make("UIScale", { Parent = self.flash })

	-- Fit the menu to the screen now, and again whenever the screen changes size (like turning a phone)
	local watching
	local function watchCamera()
		if watching then
			watching:Disconnect()
			watching = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			watching = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				self:Layout()
			end)
		end
		self:Layout()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	self:SetMode("idle")
	self.gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return self
end

-- Where the panel sits when it's open, and where it hides (just below the screen) when it's shut.
function MenuUI:openPosition()
	return UDim2.new(0.5, 0, 1, -GAP)
end

function MenuUI:closedPosition()
	return UDim2.new(0.5, 0, 1, PANEL_HEIGHT * self.scale + 40)
end

-- Sizes everything to fit the screen. Small screens get a smaller menu, and phones leave room at the
-- sides for the thumbstick and the jump button.
function MenuUI:Layout()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local screen = camera.ViewportSize
	local scale = math.clamp(screen.Y / 720, 0.62, 1)
	local room = self.touch and 360 or 40
	local width = math.max(200, math.min(MOST_WIDTH, (screen.X - room) / scale))
	self.scale = scale
	self.panelScale.Scale = scale
	self.barScale.Scale = scale
	self.flashScale.Scale = scale
	self.panel.Size = UDim2.fromOffset(width, PANEL_HEIGHT)
	self.bar.Size = UDim2.fromOffset(width, BAR_HEIGHT)
	local barBottom = GAP + PANEL_HEIGHT * scale + GAP
	self.bar.Position = UDim2.new(0.5, 0, 1, -barBottom)
	self.flash.Position = UDim2.new(0.5, 0, 1, -(barBottom + BAR_HEIGHT * scale + GAP))
	-- stop any slide and put the panel straight where it belongs
	self.slideCount += 1
	if self.slide then
		self.slide:Cancel()
		self.slide = nil
	end
	self.panel.Position = self.open and self:openPosition() or self:closedPosition()
	self.panel.Visible = self.open
end

-- Shows the tabs and cards for `tabs` (from Catalog.tabs()). Keeps the same tab open if it's still there.
function MenuUI:ShowTabs(tabs)
	self.tabs = tabs
	for _, child in ipairs(self.tabsFrame:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	self.tabButtons = {}
	local keep = nil
	for index, tab in ipairs(tabs) do
		local thing = button({
			Name = tab.name,
			Text = tab.name,
			TextSize = 15,
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = index,
			Size = UDim2.new(0, 0, 1, 0),
			Parent = self.tabsFrame,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = thing })
		thing.Activated:Connect(function()
			self:SelectTab(tab.name)
		end)
		self.tabButtons[tab.name] = thing
		if tab.name == self.tab then
			keep = tab.name
		end
	end
	self.empty.Visible = #tabs == 0
	self.tab = nil -- so SelectTab makes the cards again
	self:SelectTab(keep or (tabs[1] and tabs[1].name))
end

-- Shows the cards of the tab called `name`.
function MenuUI:SelectTab(name)
	if name == self.tab then
		return
	end
	self.tab = name
	for tabName, thing in pairs(self.tabButtons) do
		local on = tabName == name
		thing.BackgroundColor3 = on and Theme.Accent or Theme.Card
		thing.TextColor3 = on and Theme.Panel or Theme.Text
	end
	for _, child in ipairs(self.cards:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	self.cardStrokes = {}
	self.cards.CanvasPosition = Vector2.zero
	local items = {}
	for _, tab in ipairs(self.tabs) do
		if tab.name == name then
			items = tab.items
			break
		end
	end
	for index, entry in ipairs(items) do
		local thing, stroke = card(entry, index, entry.id == self.picked)
		thing.Activated:Connect(function()
			self.actions.pick(entry)
		end)
		self.cardStrokes[entry.id] = stroke
		thing.Parent = self.cards
	end
end

-- Puts the orange outline on the card with this id (nil: on no card).
function MenuUI:MarkPicked(id)
	self.picked = id
	for partId, stroke in pairs(self.cardStrokes) do
		stroke.Enabled = partId == id
	end
end

-- Slides the panel up (true) or down (false).
function MenuUI:SetOpen(open)
	self.open = open
	self.toggleStroke.Enabled = open
	self.slideCount += 1
	local count = self.slideCount
	if self.slide then
		self.slide:Cancel()
	end
	if open then
		self.panel.Visible = true
	end
	self.slide = TweenService:Create(self.panel, SLIDE, {
		Position = open and self:openPosition() or self:closedPosition(),
	})
	self.slide.Completed:Connect(function()
		-- hide it once it has slid away (unless it was opened again meanwhile)
		if count == self.slideCount and not self.open then
			self.panel.Visible = false
		end
	end)
	self.slide:Play()
	self:showBar()
end

-- Shows the bar only while the menu is open and you're placing or deleting.
function MenuUI:showBar()
	self.bar.Visible = self.open and self.mode ~= "idle"
	-- the hint gets all the room the buttons don't use
	local used = 6
	for _, thing in ipairs({ self.rotateButton, self.placeButton, self.stopButton }) do
		if thing.Visible then
			used += thing.Size.X.Offset + 6
		end
	end
	self.hint.Size = UDim2.new(1, -(12 + used + 6), 1, 0)
end

-- Switches the buttons and the hint to "idle", "place" or "delete".
function MenuUI:SetMode(mode)
	self.mode = mode
	local deleting = mode == "delete"
	self.deleteButton.BackgroundColor3 = deleting and Theme.Bad or Theme.Card
	self.rotateButton.Visible = mode == "place"
	self.placeButton.Visible = mode == "place" and self.touch
	self.stopButton.Visible = mode ~= "idle"
	self.hint.Text = (self.touch and TOUCH_HINTS or HINTS)[mode] or ""
	self:showBar()
end

-- Shows a short red message, like the reason a part couldn't be placed.
function MenuUI:Flash(text)
	self.flashCount += 1
	local count = self.flashCount
	self.flash.Text = text
	self.flash.Visible = true
	task.delay(FLASH_TIME, function()
		-- only hide it if no newer message came along
		if count == self.flashCount then
			self.flash.Visible = false
		end
	end)
end

return MenuUI
