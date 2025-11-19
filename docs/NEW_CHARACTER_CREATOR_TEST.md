# New Character Creator Test Scene

## Overview

This is a **test scene** for the new Mana Seed Character System with shader-based palette swapping. It allows you to customize characters using the new layered sprite system with color ramps.

## Location

- **Scene**: `scenes/experiments/NewCharacterCreator.tscn`
- **Script**: `scripts/experiments/NewCharacterCreator.gd`
- **Shader**: `assets/shaders/palette_swap.gdshader`
- **Assets**: `assets/graphics/characters/New Character System/SpriteSystem/`

## How to Run

1. Open Godot and load the Psyokin project
2. Navigate to `scenes/experiments/NewCharacterCreator.tscn`
3. Press **F6** or click "Run Current Scene" to launch the test scene

## Features

### 11 Customization Categories

Based on the Mana Seed system documentation:

1. **Body** (01body) - Skin ramps
2. **Legwear** (02sock) - 3-color ramps
3. **Footwear Small** (03fot1) - 3-color ramps (goes under pants)
4. **Bottomwear** (04lwr1/06lwr2/08lwr3) - 3-color ramps
   - Pants/Shorts (04lwr1)
   - Overalls (06lwr2)
   - Dresses/Skirts (08lwr3)
   - *Note: These are mutually exclusive - you can only wear one*
5. **Topwear** (05shrt) - 3-color ramps
6. **Footwear Large** (07fot2) - 3-color ramps (goes over pants)
7. **Handwear** (09hand) - 3-color ramps
8. **Overwear** (10outr) - 3-color ramps
9. **Neckwear** (11neck) - 4-color ramps
10. **Eyewear** (12face) - 3-color ramps
11. **Hairstyle** (13hair) - Hair ramps (5-color)
12. **Headwear** (14head) - 4-color ramps

### Shader-Based Color Swapping

The system uses a custom shader (`palette_swap.gdshader`) that supports:
- **3-color ramps** - Most clothing items
- **4-color ramps** - Headwear and neckwear
- **5-color hair ramps** - Hair colors
- **Skin ramps** - Body skin tones

### Layer System

Sprites are layered in the correct order (bottom to top) according to the Mana Seed documentation:
- 00undr → 01body → 02sock → 03fot1 → 04lwr1/06lwr2/08lwr3 → 05shrt → 07fot2 → 09hand → 10outr → 11neck → 12face → 13hair → 14head

### Special Features

- **Exclusive Groups**: Some layers are mutually exclusive (e.g., you can't wear pants AND a dress)
- **_e Flag Support**: Headwear with the `_e` flag will hide hair (e.g., headscarves)
- **Animation Preview**: Automatically cycles through walk animation frames
- **Direction Control**: View character from all 4 directions (South, North, East, West)

## Sprite Sheet Format

- **Size**: 1024x1024 pixels per sheet
- **Frame Size**: 64x64 pixels per sprite
- **Grid**: 16 columns × 16 rows
- **Total Frames**: 256 frames per sheet

## Naming Convention

Files follow the Mana Seed format:
```
fbas_XXlayer_itemname_00X_e
```

Example: `fbas_13hair_bob1_00.png`
- `fbas` - Farmer base sprite system
- `13hair` - Layer code (hair layer)
- `bob1` - Item name (bob hairstyle variant 1)
- `00` - Version number
- Optional `_e` flag for special behavior

### Palette Codes

The version number includes a palette code letter:
- `00a` - Single 3-color ramp
- `00b` - Single 4-color ramp
- `00c` - Two 3-color ramps
- `00d` - One 4-color + one 3-color ramp
- `00f` - One 4-color + 5-color hair ramp
- `00` (no letter) - Skin or other special ramp

## Current Limitations

This is a **test/experimental scene** with some current limitations:

1. **Placeholder Color Ramps**: Currently shows placeholder color ramp names. Full implementation requires parsing the actual palette image files to extract exact color values.

2. **Limited Color Ramp Options**: UI shows only first 10 color ramps per type for manageability. Can be expanded as needed.

3. **Frame Layout**: Assumes standard Mana Seed layout. May need adjustment if actual sprite sheets differ.

4. **No Save/Load**: Currently no ability to save or export character configurations.

## Next Steps

To fully implement the system:

1. **Parse Palette Images**: Read the actual color values from the palette PNG files
   - `mana seed 3-color ramps.png`
   - `mana seed 4-color ramps.png`
   - `mana seed hair ramps.png`
   - `mana seed skin ramps.png`

2. **Color Ramp Application**: Apply actual color values to shader parameters based on selected ramps

3. **UI Improvements**:
   - Visual color previews
   - Better organization of clothing options
   - Search/filter functionality

4. **Integration**: Connect to main game's character creation system

5. **Export**: Save character configurations to JSON or similar format

## Technical Details

### Shader Parameters

The `palette_swap.gdshader` uses these key parameters:
- `ramp_type` (int): 0=3-color, 1=4-color, 2=hair, 3=skin
- `base_Xcolor_N`: Base colors in the sprite (what to replace)
- `target_Xcolor_N`: Target colors from selected ramp (replacement colors)

### Color Ramp Files

Located in: `assets/graphics/characters/New Character System/SpriteSystem/_supporting files/palettes/`

- **Base Ramps**: Define the default colors in sprites
  - `3-color base ramp (00a).png`
  - `4-color base ramp (00b).png`
  - `hair color base ramp.png`
  - `skin color base ramp.png`

- **Mana Seed Ramps**: Define available color variations
  - `mana seed 3-color ramps.png`
  - `mana seed 4-color ramps.png`
  - `mana seed hair ramps.png`
  - `mana seed skin ramps.png`

## Troubleshooting

### No sprites appear
- Check console for "Asset scan complete" message
- Verify sprite files exist in the base_sheets folders
- Check that Godot has imported the PNG files (look for .import files)

### Wrong colors or shader not working
- Verify shader file is at `res://assets/shaders/palette_swap.gdshader`
- Check that sprite materials are being created correctly
- Current version uses default shader colors (palette parsing not yet implemented)

### Animation issues
- Verify sprite sheets are 1024x1024 with 16x16 grid
- Check that hframes=16 and vframes=16 on all sprite nodes
- Verify frame calculation in `update_frame_display()`

### Parts not layering correctly
- Check z_index values in LAYERS dictionary
- Verify sprite nodes are created in correct order in scene tree
- Ensure all sprites are children of CharacterLayers Node2D

## Credits

Character system based on **Mana Seed Farmer Sprite System** by Seliel the Shaper.
See `Sprite System readme.txt` for full documentation and usage guidelines.

## Testing Checklist

- [ ] Scene loads without errors
- [ ] All 11+ customization categories appear in UI
- [ ] Body sprite displays by default
- [ ] Can select different parts for each layer
- [ ] Can select "None" to hide layers
- [ ] Bottomwear options are mutually exclusive
- [ ] Direction buttons work (South/North/East/West)
- [ ] Animation cycles through frames automatically
- [ ] Color ramp selectors appear for appropriate layers
- [ ] Sprites layer in correct order
- [ ] No z-fighting or rendering issues
