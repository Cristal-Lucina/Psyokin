# TileMap Tutorial for Psyokin

## Overview
Your Godot 4.4 project now has a complete TileMap setup ready to use! This guide will teach you how to use it to build levels.

## What Was Created

1. **TileSet Resource**: `resources/tilesets/environment_tileset.tres`
   - Contains all your tiles from the Tilemap.png spritesheet
   - Tile size: 48x48 pixels
   - Grid: 40 columns x 16 rows (640 total tiles)

2. **Game Level Scene**: `scenes/world/GameLevel.tscn`
   - Pre-configured with a TileMapLayer
   - Ready to use for building your levels

## How to Use the TileMap

### Opening the TileMap Editor

1. Open Godot and load your Psyokin project
2. In the FileSystem panel, navigate to `scenes/world/GameLevel.tscn`
3. Double-click to open the scene
4. In the Scene tree, select the **TileMapLayer** node
5. The TileMap editor will appear at the bottom of the screen

### Understanding the TileMap Editor Interface

When you select the TileMapLayer, you'll see:

- **TileSet panel** (bottom): Shows all available tiles from your spritesheet
- **Drawing tools** (top toolbar):
  - **Paint** (pencil icon): Draw individual tiles
  - **Line** (line icon): Draw straight lines of tiles
  - **Rectangle** (rectangle icon): Fill rectangular areas
  - **Bucket Fill** (bucket icon): Fill connected areas
  - **Erase** (eraser icon): Remove tiles

### Basic Drawing Workflow

1. **Select a tile**:
   - Click on any tile in the TileSet panel at the bottom
   - You can scroll through all 640 tiles available

2. **Choose a drawing tool**:
   - Click the Paint tool for individual tile placement
   - Or select Line/Rectangle for larger areas

3. **Draw in the viewport**:
   - Click in the 2D viewport to place tiles
   - Hold Shift while dragging to draw multiple tiles
   - Use the mouse wheel to zoom in/out

4. **Erase tiles**:
   - Select the Eraser tool
   - Click on tiles to remove them
   - Or right-click while any tool is selected

### Building a Simple Level

Here's a step-by-step example:

1. **Create a floor**:
   - Select a floor tile from the bottom panel
   - Choose the Rectangle tool
   - Drag across the bottom of the viewport to create a platform

2. **Add walls**:
   - Select wall tiles
   - Use the Paint tool to place them above the floor
   - Build up structures piece by piece

3. **Add platforms**:
   - Your tileset includes blue and red platforms with chains
   - Place these higher up for jumping puzzles

4. **Add decorations**:
   - Use the various decorative tiles to add detail
   - Windows, doors, props, etc.

### Advanced Features

#### Layers
You can add multiple TileMapLayer nodes to separate:
- Background decorations (Layer 1, z-index: -1)
- Main terrain (Layer 2, z-index: 0)
- Foreground details (Layer 3, z-index: 1)

To add a new layer:
1. Right-click on the GameLevel node
2. Select "Add Child Node"
3. Search for "TileMapLayer"
4. In the Inspector, set the TileSet to the same environment_tileset.tres
5. Adjust the z_index property to control layering

#### Collision Shapes (For Platformer Physics)

To add collision to your tiles:

1. Open `resources/tilesets/environment_tileset.tres` directly
2. In the TileSet editor, click "Physics Layers" and add a layer
3. Select a tile from the atlas
4. Click "Physics" in the right panel
5. Draw collision shapes for that tile
6. Repeat for all solid tiles (floors, walls, platforms)

Common collision patterns:
- **Full tile collision**: For solid blocks
- **Top-only collision**: For platforms you can jump through
- **Slopes**: For ramps and angled surfaces

#### Tile Properties

You can also add:
- **Terrain Sets**: For auto-tiling (connects tiles automatically)
- **Custom Data**: Store metadata like "damage zone" or "ice surface"
- **Animation**: Animate certain tiles (water, torches, etc.)

## Tips and Best Practices

1. **Use Grid Snapping**: Keep the grid enabled (it's on by default) for precise placement

2. **Zoom Appropriately**:
   - Zoom out (mouse wheel down) for big picture layout
   - Zoom in (mouse wheel up) for detail work

3. **Save Often**: Press Ctrl+S frequently while building

4. **Test in Game**:
   - Press F5 to run the game
   - Make sure to set GameLevel.tscn as a runnable scene or add it to your main scene

5. **Organize Tiles**:
   - Your tileset has 640 tiles - that's a lot!
   - Familiarize yourself with what's available by scrolling through
   - Consider taking notes on which row/column has what type of tiles

6. **Performance**:
   - TileMaps are very efficient
   - Don't worry about using lots of tiles
   - Godot optimizes rendering automatically

## Tile Organization in Your Spritesheet

Based on the Tilemap.png (1920x768, 40x16 grid at 48px/tile):

Looking at the preview:
- **Left side**: Building structures (houses, wooden platforms)
- **Center-left**: Props and objects (tables, chairs, containers)
- **Center**: Various floor and wall tiles
- **Center-right**: Platform pieces (metal platforms with chains)
- **Right side**: More structural pieces, windows, doors
- **Bottom-right**: Dark/cave tiles and platforming elements

## Next Steps

1. **Open the scene**: Load `scenes/world/GameLevel.tscn`
2. **Experiment**: Try drawing with different tiles
3. **Build something**: Create a small test room or platform section
4. **Add collision**: Configure physics on the tiles you want to be solid
5. **Integrate**: Add your character to the scene and test movement

## Keyboard Shortcuts

- **Paint**: P
- **Erase**: E
- **Fill**: F
- **Picker**: I (pick tile from viewport)
- **Grid Toggle**: G
- **Zoom In/Out**: Mouse Wheel or Ctrl + Mouse Wheel
- **Pan**: Middle Mouse Button + Drag or Space + Drag

## Common Issues

**Q: Tiles appear blurry or have weird lines between them**
A: The Tilemap.png import settings are already configured to prevent this (compress/mode=0, filter disabled)

**Q: Can't see the tiles in the editor**
A: Make sure the TileMapLayer node is selected and check that tile_set property points to environment_tileset.tres

**Q: Character falls through tiles**
A: You need to add collision shapes to your tiles (see "Collision Shapes" section above)

**Q: Changes to TileSet don't appear in scene**
A: Save the TileSet resource (Ctrl+S while editing it) and reload the scene

## Resources

- Godot TileMap Docs: https://docs.godotengine.org/en/stable/tutorials/2d/using_tilemaps.html
- Your TileSet: `resources/tilesets/environment_tileset.tres`
- Example Scene: `scenes/world/GameLevel.tscn`

Happy level building!
