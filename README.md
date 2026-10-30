# Build Menu

A simple build menu for Roblox. Players open a menu, pick a part, see a see-through "ghost" of it
on the ground (green means it fits, red means it doesn't), and click to place it. They can turn
parts and delete their own parts. It works on PC and on phones and tablets.

You add your own parts just by putting Models in a folder. No code needed.

## Try it

1. Open `BuildMenu.rbxlx` in Roblox Studio.
2. Press **Play**.
3. Press **B** to open the menu (on a phone, tap the **Build** button on the left).
4. Pick a card, move your mouse over the grey square, and click to place.

## Put it in your own game

Copy these four things from `BuildMenu.rbxlx` into your game, into the same places:

| Copy this                                   | What it is                          |
| ------------------------------------------- | ----------------------------------- |
| `ReplicatedStorage.BuildMenu`               | the settings and the shared maths   |
| `ReplicatedStorage.BuildParts`              | the parts people can place          |
| `ServerScriptService.BuildServer`           | the server script that places parts |
| `StarterPlayer.StarterPlayerScripts.BuildMenu` | the menu, the ghost and the controls |

Then add a Part to Workspace and name it **BuildArea**. People can build on top of it.
Make it as big as you like, and you can have more than one. Anchor it.

Placed parts go into a folder called `Workspace.PlacedParts`. It is made for you.

## Add your own parts

Everything lives in `ReplicatedStorage.BuildParts`:

```
BuildParts
  Walls            <- a Folder is a tab in the menu
    Brick Wall     <- a Model is a card in that tab
    Window Wall
  Furniture
    Table
```

- **A folder is a tab. A Model inside it is a card.** A single Part works as a card too.
- Parts put straight into `BuildParts` (not in a folder) go into a tab called "Other".
- The card shows a little 3D picture of the model, so you don't need to make icons.
- Parts snap to a **2-stud grid**. Sizes that are whole numbers of grid squares (2, 4, 6, 8...) fit
  together best.
- **The front of a model is its -Z side**, the side Studio calls Front (the way its pivot's
  LookVector points). The ghost and the card picture both show that side to the player.
- Set the model's **PrimaryPart or pivot at its bottom centre**. The menu always stands the model on
  the ground by its lowest point, but the pivot's turn decides which way is the front, and a bottom
  pivot keeps everything tidy. All the sample models are made this way.
- Placed parts are anchored for you (see `AnchorPlacedParts` in the settings).
- Scripts, sounds, ProximityPrompts and ClickDetectors are taken off the ghost, so it can't do
  anything while you aim it. The real placed part keeps them, so a placed lamp can have a light
  switch.

### Attributes

You can add these in the Properties window (Attributes, then the **+** button):

| Attribute     | Put it on      | Type    | What it does                                                   |
| ------------- | -------------- | ------- | -------------------------------------------------------------- |
| `Floor`       | a folder or a model | boolean | makes it a floor tile: it lies flat and only bumps into other floor tiles, so walls and furniture can stand on it |
| `DisplayName` | a model        | string  | the name on the card (if you don't set it, the model's name is used) |
| `Order`       | a folder or a model | number  | lower numbers come first in the menu                    |

The sample `Floors` folder has `Floor` set to true, so everything in it is a floor tile.

## Controls

| What            | PC                         | Phone / tablet                          |
| --------------- | -------------------------- | --------------------------------------- |
| Open the menu   | **B**, or the Build button | the **Build** button                    |
| Pick a part     | click a card               | tap a card                              |
| Aim             | move the mouse             | tap the build area                      |
| Place           | left click                 | the **Place** button                    |
| Turn            | **R**, or the Rotate button | the **Rotate** button                  |
| Delete mode     | **X**, or the Delete button | the **Delete** button                  |
| Delete a part   | click one of your parts    | tap one of your parts, then tap it again |
| Stop            | **Q**, or the Stop button  | the **Stop** button                     |

Pick the same card again to stop placing. You can only delete your own parts.

## Settings

Open `ReplicatedStorage.BuildMenu.Config` to change things:

| Setting               | Starts as      | What it does                                         |
| --------------------- | -------------- | ---------------------------------------------------- |
| `PartsFolder`         | `"BuildParts"` | the folder in ReplicatedStorage that holds the parts |
| `AreaName`            | `"BuildArea"`  | you can build on any Workspace part with this name   |
| `PlacedFolder`        | `"PlacedParts"` | the Workspace folder placed parts go into           |
| `GridSize`            | `2`            | studs per grid square                                |
| `FloorLift`           | `0.05`         | floor tiles sit this far above the area so they don't flicker |
| `MaxPartsPerPlayer`   | `300`          | how many parts one player can place                  |
| `AnchorPlacedParts`   | `true`         | anchor every placed part so nothing falls over       |
| `RemovePartsOnLeave`  | `true`         | a player's parts go when they leave                  |
| `RequestsPerSecond`   | `8`            | how fast one player may place or delete              |
| `Keys`                | B, R, X, Q     | the PC keys for open, rotate, delete mode and stop   |
| `Theme`               | dark grey and orange | the menu colours and font                      |

## How the files fit together

```
ReplicatedStorage
  BuildMenu                 (shared by the server and every player)
    Config                  settings
    Catalog                 reads BuildParts and turns it into tabs and cards
    Grid                    the grid maths, so the ghost and the server always agree
    BuildRequest            a RemoteFunction the server makes when the game starts
  BuildParts                your parts

ServerScriptService
  BuildServer               checks every request and really places or deletes the part

StarterPlayer.StarterPlayerScripts
  BuildMenu
    BuildClient             starts everything (it's one line)
    BuildController         the brain: aiming, keys, taps, placing, deleting
    MenuUI                  the menu on the screen
    Ghost                   the see-through preview
```

When a player clicks to place, `BuildController` asks the server through `BuildRequest`. The
server does all the checks again itself (does the part exist, is it on a build area, is anything in
the way, is the player going too fast) and only then makes the real part. This stops cheaters
placing parts wherever they want.

Your own scripts can use the menu too. From a LocalScript:

```lua
local Build = require(game.Players.LocalPlayer.PlayerScripts:WaitForChild("BuildMenu"):WaitForChild("BuildController"))
Build.Open()
Build.Select("Furniture/Table") -- a part's id is "TabName/ModelName"
```

`BuildController` also has `Close`, `Toggle`, `Rotate`, `Place`, `DeleteMode`, `Delete`, `Stop`,
`AimAt` and `State`. The top of the file says what each one does.

## Remaking the place file

`build_place.py` rebuilds `BuildMenu.rbxlx` from the `src` folder (it needs Python 3):

```
python build_place.py
```

If you use Rojo, `default.project.json` syncs the scripts. `BuildParts` and `BuildArea` live only
in the place file, so Rojo leaves them alone.

## Ideas to add next

None of these are built yet. They are ideas for you to try:

- **Prices and money**: give each model a `Price` attribute and check the player can pay in `BuildServer`.
- **Saving**: save each player's parts with DataStoreService and load them back when they join.
- **Plots**: give each player their own build area so people don't build on top of each other.
- **Move and undo**: pick up a placed part and put it somewhere else, or undo the last thing you did.
- **Stacking**: let parts go on top of other parts, not just on the build area.
- **Gamepad**: controls for Xbox and other controllers.
