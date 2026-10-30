"""Build BuildMenu.rbxlx: a small place to try the build menu in.

.rbxlx is Roblox's XML place format, so no Rojo is needed. The scripts come from src/, laid out the
way Rojo likes (see default.project.json), so Rojo works too.

  src/<Service>/...           one folder per Roblox service
  sub-folders                 become Folder instances
  *.server.lua / *.client.lua Script / LocalScript
  *.lua                       ModuleScript

The place also gets a baseplate, a 96 x 96 BuildArea, a spawn, and some sample parts in
ReplicatedStorage.BuildParts. Those parts live only in the place file (Rojo leaves them alone).

  python build_place.py [<root>] [--out <file>] [--test-marker]

--test-marker adds ReplicatedStorage.SL_TestMarker, which only the Studio test runner needs.
"""
import base64
import os
import pathlib
import struct
import sys
import time
import xml.etree.ElementTree as ET

args = [a for a in sys.argv[1:]]
TEST_MARKER = "--test-marker" in args
if TEST_MARKER:
    args.remove("--test-marker")
OUT_OVERRIDE = None
if "--out" in args:
    i = args.index("--out")
    OUT_OVERRIDE = pathlib.Path(args[i + 1])
    del args[i:i + 2]
ROOT = pathlib.Path(args[0] if args else pathlib.Path(__file__).parent)
SRC = ROOT / "src"
OUT = OUT_OVERRIDE or (ROOT / "BuildMenu.rbxlx")

# Roblox's numbers for each material and part shape
MATERIALS = {
    "SmoothPlastic": 272, "Neon": 288, "Wood": 512, "WoodPlanks": 528, "Slate": 800, "Concrete": 816,
    "Brick": 848, "Metal": 1088, "Grass": 1280, "Fabric": 1312, "Glass": 1568,
}
SHAPES = {"Ball": 0, "Block": 1, "Cylinder": 2}

# Turns, as the 9 numbers of a rotation (R00 R01 R02 R10 R11 R12 R20 R21 R22)
STRAIGHT = (1, 0, 0, 0, 1, 0, 0, 0, 1)
UPRIGHT = (0, -1, 0, 1, 0, 0, 0, 0, 1)  # a Cylinder's length runs along X: this stands it up
BACKWARDS = (-1, 0, 0, 0, 1, 0, 0, 0, -1)  # half a turn round, to face the other way

_referent = 0


def next_referent():
    global _referent
    _referent += 1
    return f"RBX{_referent}"


def item(parent, class_name, name):
    node = ET.SubElement(parent, "Item", {"class": class_name, "referent": next_referent()})
    props = ET.SubElement(node, "Properties")
    ET.SubElement(props, "string", {"name": "Name"}).text = name
    return node


def prop(node, kind, name, value):
    ET.SubElement(node.find("Properties"), kind, {"name": name}).text = value


def class_for(path):
    if path.name.endswith(".server.lua"):
        return "Script"
    if path.name.endswith(".client.lua"):
        return "LocalScript"
    return "ModuleScript"


def instance_name(path):
    return path.name.replace(".server.lua", "").replace(".client.lua", "").replace(".lua", "")


def add_tree(parent, directory):
    """Every .lua in `directory` as a script, every sub-folder as a Folder, sorted for stable output."""
    count = 0
    for path in sorted(directory.iterdir()):
        if path.is_dir():
            count += add_tree(item(parent, "Folder", path.name), path)
        elif path.suffix == ".lua":
            node = item(parent, class_for(path), instance_name(path))
            # ElementTree escapes &, < and > in text, which is exactly what ProtectedString needs.
            ET.SubElement(node.find("Properties"), "ProtectedString", {"name": "Source"}).text = path.read_text(encoding="utf-8")
            count += 1
    return count


def number(value):
    return format(float(value), ".6g")


def xyz(node, values, names):
    for name, value in zip(names, values):
        ET.SubElement(node, name).text = number(value)


def cframe(node, name, at, turn=STRAIGHT):
    frame = ET.SubElement(node.find("Properties"), "CoordinateFrame", {"name": name})
    xyz(frame, at, ("X", "Y", "Z"))
    xyz(frame, turn, ("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"))


def pivot(node, at, turn=STRAIGHT):
    """A Model's pivot (the point it's moved and turned around)."""
    optional = ET.SubElement(node.find("Properties"), "OptionalCoordinateFrame", {"name": "WorldPivotData"})
    frame = ET.SubElement(optional, "CFrame")
    xyz(frame, at, ("X", "Y", "Z"))
    xyz(frame, turn, ("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"))


def vector(node, name, values):
    xyz(ET.SubElement(node.find("Properties"), "Vector3", {"name": name}), values, ("X", "Y", "Z"))


def colour(node, rgb):
    r, g, b = rgb
    prop(node, "Color3uint8", "Color3uint8", str(0xFF000000 | (r << 16) | (g << 8) | b))


def attributes(node, values):
    """Attributes, in Roblox's binary format: how many, then for each its name, a type byte and the value."""
    data = bytearray(struct.pack("<I", len(values)))
    for key, value in values.items():
        raw = key.encode("utf-8")
        data += struct.pack("<I", len(raw)) + raw
        if isinstance(value, bool):  # (before numbers: in Python True is a number too)
            data += bytes([0x03, 1 if value else 0])
        elif isinstance(value, (int, float)):
            data += bytes([0x06]) + struct.pack("<d", float(value))
        elif isinstance(value, str):
            raw = value.encode("utf-8")
            data += bytes([0x02]) + struct.pack("<I", len(raw)) + raw
        else:
            raise TypeError(f"attribute {key}: only true/false, numbers and text are supported")
    prop(node, "BinaryString", "AttributesSerialize", base64.b64encode(bytes(data)).decode("ascii"))


def part(parent, name, size, at, rgb, material, shape="Block", turn=STRAIGHT, transparency=0, shadow=True, class_name="Part"):
    node = item(parent, class_name, name)
    prop(node, "bool", "Anchored", "true")
    cframe(node, "CFrame", at, turn)
    vector(node, "size", size)
    colour(node, rgb)
    prop(node, "token", "Material", str(MATERIALS[material]))
    prop(node, "token", "shape", str(SHAPES[shape]))
    prop(node, "token", "TopSurface", "0")
    prop(node, "token", "BottomSurface", "0")
    if transparency:
        prop(node, "float", "Transparency", number(transparency))
    if not shadow:
        prop(node, "bool", "CastShadow", "false")
    return node


def model(parent, name, order):
    """A Model whose pivot is at its bottom centre, at the origin: build its parts around (0, 0, 0)
    with the bottom at y = 0 and the front facing -Z."""
    node = item(parent, "Model", name)
    pivot(node, (0, 0, 0))
    attributes(node, {"Order": order})
    return node


def tab(parent, name, order, floor=False):
    node = item(parent, "Folder", name)
    values = {"Order": order}
    if floor:
        values["Floor"] = True
    attributes(node, values)
    return node


WOOD = (150, 100, 60)
DARK_WOOD = (115, 75, 45)
BRICK = (165, 80, 60)
METAL = (70, 72, 78)


def build_parts(replicated):
    """The sample parts: a Folder per tab, a Model per card."""
    root = item(replicated, "Folder", "BuildParts")
    count = 0

    floors = tab(root, "Floors", 1, floor=True)
    wood = model(floors, "Wood Floor", 1)
    part(wood, "Floor", (8, 0.4, 8), (0, 0.2, 0), (165, 115, 70), "WoodPlanks")
    stone = model(floors, "Stone Tile", 2)
    part(stone, "Tile", (4, 0.4, 4), (0, 0.2, 0), (140, 140, 148), "Slate")
    count += 2

    walls = tab(root, "Walls", 2)
    brick = model(walls, "Brick Wall", 1)
    part(brick, "Wall", (8, 8, 1), (0, 4, 0), BRICK, "Brick")
    window = model(walls, "Window Wall", 2)
    part(window, "Bottom", (8, 2.5, 1), (0, 1.25, 0), BRICK, "Brick")
    part(window, "Top", (8, 1.5, 1), (0, 7.25, 0), BRICK, "Brick")
    part(window, "Left", (1.5, 4, 1), (-3.25, 4.5, 0), BRICK, "Brick")
    part(window, "Right", (1.5, 4, 1), (3.25, 4.5, 0), BRICK, "Brick")
    part(window, "Glass", (5, 4, 0.2), (0, 4.5, 0), (170, 210, 230), "Glass", transparency=0.5)
    count += 2

    furniture = tab(root, "Furniture", 3)
    table = model(furniture, "Table", 1)
    part(table, "Top", (6, 0.4, 4), (0, 2.8, 0), WOOD, "Wood")
    for x in (-2.6, 2.6):
        for z in (-1.6, 1.6):
            part(table, "Leg", (0.4, 2.6, 0.4), (x, 1.3, z), WOOD, "Wood")
    chair = model(furniture, "Chair", 2)
    part(chair, "Seat", (2, 0.3, 2), (0, 1.65, 0), DARK_WOOD, "Wood")
    for x in (-0.8, 0.8):
        for z in (-0.8, 0.8):
            part(chair, "Leg", (0.3, 1.5, 0.3), (x, 0.75, z), DARK_WOOD, "Wood")
    part(chair, "Back", (2, 2, 0.3), (0, 2.8, 0.85), DARK_WOOD, "Wood")  # at the back (+Z): the front is -Z
    count += 2

    decor = tab(root, "Decor", 4)
    lamp = model(decor, "Lamp", 1)
    part(lamp, "Base", (0.3, 2, 2), (0, 0.15, 0), METAL, "Metal", "Cylinder", UPRIGHT)
    part(lamp, "Pole", (4.9, 0.3, 0.3), (0, 2.75, 0), METAL, "Metal", "Cylinder", UPRIGHT)
    bulb = part(lamp, "Bulb", (0.9, 0.9, 0.9), (0, 5, 0), (255, 220, 150), "Neon", "Ball", shadow=False)
    light = item(bulb, "PointLight", "Light")
    prop(light, "float", "Range", "16")
    prop(light, "float", "Brightness", "1.5")
    shine = ET.SubElement(light.find("Properties"), "Color3", {"name": "Color"})
    xyz(shine, (1, 0.82, 0.6), ("R", "G", "B"))
    prop(light, "bool", "Shadows", "true")
    # the shade casts no shadow, so the light still gets out
    part(lamp, "Shade", (1.4, 2.4, 2.4), (0, 5.9, 0), (240, 225, 190), "Fabric", "Cylinder", UPRIGHT, transparency=0.1, shadow=False)
    plant = model(decor, "Plant", 2)
    part(plant, "Pot", (1.6, 1.8, 1.8), (0, 0.8, 0), (180, 95, 60), "Concrete", "Cylinder", UPRIGHT)
    part(plant, "Soil", (0.1, 1.6, 1.6), (0, 1.6, 0), (75, 55, 40), "Concrete", "Cylinder", UPRIGHT)
    leaves = (70, 150, 70)
    part(plant, "Leaves", (1.6, 1.6, 1.6), (0, 2.3, 0), leaves, "Grass", "Ball")
    part(plant, "Leaves", (1.1, 1.1, 1.1), (0.35, 2.9, 0.2), leaves, "Grass", "Ball")
    part(plant, "Leaves", (1, 1, 1), (-0.35, 2.85, -0.2), leaves, "Grass", "Ball")
    part(plant, "Leaves", (0.9, 0.9, 0.9), (0.05, 3.4, 0), leaves, "Grass", "Ball")
    count += 2
    return count


roblox = ET.Element("roblox", {
    "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
    "xsi:noNamespaceSchemaLocation": "http://www.roblox.com/roblox.xsd",
    "version": "4",
})

total = 0

workspace = item(roblox, "Workspace", "Workspace")
prop(workspace, "bool", "StreamingEnabled", "false")  # a small place: everything is always there
part(workspace, "Baseplate", (512, 4, 512), (0, -2, 0), (90, 150, 80), "Grass")  # top at y = 0
part(workspace, "BuildArea", (96, 1, 96), (0, 0.5, 0), (205, 205, 210), "Concrete")  # top at y = 1
spawn = part(workspace, "SpawnLocation", (12, 1, 12), (0, 0.5, -56), (110, 120, 135), "SmoothPlastic", turn=BACKWARDS, class_name="SpawnLocation")
prop(spawn, "int", "Duration", "0")  # no force field bubble

lighting = item(roblox, "Lighting", "Lighting")
prop(lighting, "token", "Technology", "4")  # Future
prop(lighting, "float", "ClockTime", "14")
prop(lighting, "float", "Brightness", "2")
prop(lighting, "bool", "GlobalShadows", "true")

replicated = item(roblox, "ReplicatedStorage", "ReplicatedStorage")
total += add_tree(replicated, SRC / "ReplicatedStorage")
models = build_parts(replicated)
if TEST_MARKER:
    # Name goes last: the test runner looks for exactly '<string name="Name">SL_TestMarker</string></Properties>'
    marker = ET.SubElement(replicated, "Item", {"class": "BoolValue", "referent": next_referent()})
    marker_props = ET.SubElement(marker, "Properties")
    ET.SubElement(marker_props, "bool", {"name": "Value"}).text = "true"
    ET.SubElement(marker_props, "string", {"name": "Name"}).text = "SL_TestMarker"

server = item(roblox, "ServerScriptService", "ServerScriptService")
total += add_tree(server, SRC / "ServerScriptService")

starter = item(roblox, "StarterPlayer", "StarterPlayer")
starter_scripts = item(starter, "StarterPlayerScripts", "StarterPlayerScripts")
total += add_tree(starter_scripts, SRC / "StarterPlayerScripts")

# Write a private temp file and swap it in all at once, so nobody ever opens a half-written place.
tmp = OUT.with_name(f"{OUT.name}.{os.getpid()}.tmp")
ET.ElementTree(roblox).write(tmp, encoding="utf-8", xml_declaration=True)
for attempt in range(50):
    try:
        os.replace(tmp, OUT)
        break
    except PermissionError:
        time.sleep(0.2)
else:
    os.remove(tmp)
    sys.exit(f"could not replace {OUT}: it is held open by another process")

print(f"wrote {OUT}")
print(f"scripts embedded: {total}")
print(f"sample parts: {models}")
print(f"size: {OUT.stat().st_size / 1024:.0f} KB")
