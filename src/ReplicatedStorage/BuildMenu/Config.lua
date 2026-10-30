-- Build menu settings. Change these to make the menu your own.

local Config = {}

-- Where things live
Config.PartsFolder = "BuildParts" -- ReplicatedStorage.BuildParts: a folder per menu tab, a Model per part
Config.AreaName = "BuildArea" -- you can build on top of any part in Workspace with this name
Config.PlacedFolder = "PlacedParts" -- placed parts go into Workspace.PlacedParts

-- Placing
Config.GridSize = 2 -- studs per grid square
Config.FloorLift = 0.05 -- floor tiles stick up this far out of the build area, so nothing flickers
Config.MaxPartsPerPlayer = 300
Config.AnchorPlacedParts = true -- anchor every placed part so nothing falls over
Config.RemovePartsOnLeave = true -- a player's parts go when they leave
Config.RequestsPerSecond = 8 -- how fast one player may place or delete

-- Keys (PC). Phones and tablets get buttons instead.
Config.Keys = {
	Toggle = Enum.KeyCode.B, -- open / close the menu
	Rotate = Enum.KeyCode.R,
	Delete = Enum.KeyCode.X, -- delete mode on / off
	Stop = Enum.KeyCode.Q, -- stop placing or deleting
}

-- Colours and font
Config.Theme = {
	Panel = Color3.fromRGB(28, 30, 38),
	Card = Color3.fromRGB(46, 49, 61),
	Text = Color3.fromRGB(240, 240, 245),
	Muted = Color3.fromRGB(165, 170, 185),
	Accent = Color3.fromRGB(255, 176, 59),
	Good = Color3.fromRGB(90, 220, 120),
	Bad = Color3.fromRGB(235, 80, 70),
	Font = Enum.Font.GothamBold,
}

return Config
