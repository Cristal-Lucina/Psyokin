# Character Creator Experiment

## Overview

This is a standalone experimental scene for testing the Mana Seed character layering system. It allows you to mix and match different character parts (body, outfit, hair, hats) and see them layer correctly in real-time. The character plays the walk animation automatically.

## Location

- **Scene**: `scenes/experiments/CharacterCreator.tscn`
- **Script**: `scripts/experiments/CharacterCreator.gd`
- **Assets**: `assets/graphics/characters/`

## How to Use

### Opening the Character Creator

1. Open Godot and load your Psyokin project
2. Navigate to `scenes/experiments/CharacterCreator.tscn`
3. Double-click to open the scene
4. Press F6 or click "Run Current Scene" to launch

### Interface

The character creator has two main panels:

#### Left Panel: Preview
- **Character Display**: Shows the layered character with auto-playing walk animation
- **Frame Counter**: Shows current walk animation frame (1-6)
- **Direction Label**: Shows current facing direction

#### Right Panel: Controls
- **Base Body (0bas)**: Select skin tone/body variant
- **Outfit (1out)**: Choose clothing
- **Hair (4har)**: Select hairstyle and color
- **Hat (5hat)**: Choose headwear
- **Direction Buttons**: Change facing (South, West, East, North)

### Selecting Parts

1. **Click any button** in the right panel to select that part
2. The character preview updates **immediately**
3. Click **"None"** to remove a layer
4. Parts automatically **layer correctly** (base → outfit → hair → hat)

### Animation

- The character **automatically animates** using the walk cycle
- **6 frames** loop continuously (frames 0-5 from rows 5-8)
- Animation speed: 135ms per frame
- Use **Direction buttons** to see all 4 facing directions

## Character System Details

### Layer Order (Bottom to Top)

According to the Mana Seed documentation:

1. **0bot** - Behind everything (not implemented yet)
2. **0bas** - Base body (required)
3. **1out** - Outfit/clothing
4. **2clo** - Cloaks and capes
5. **3fac** - Face items (glasses, masks)
6. **4har** - Hair
7. **5hat** - Hats and hoods
8. **6tla** - Tool Layer A (weapons)
9. **7tlb** - Tool Layer B (shields, off-hand)

Currently implemented: Base, Outfit, Hair, Hat

### Sprite Sheet Format

- **Size**: 512x512 pixels per sheet
- **Frame Size**: 64x64 pixels per sprite
- **Grid**: 8 columns × 8 rows
- **Layout**:
  - Rows 1-4: Walk animation (4 directions × 8 frames)
  - Row 1: South (down)
  - Row 2: West (left)
  - Row 3: East (right)
  - Row 4: North (up)

### Naming Convention

Files follow this pattern:
```
char_a_p1_1out_pfpn_v01.png
```

Breaking it down:
- `char` - Character sheet
- `a` - Character type A
- `p1` - Page 1 (walk/run animations)
- `1out` - Layer code (outfit)
- `pfpn` - Item code (peasant farmer pants)
- `v01` - Variant/color 01

### Available Variants

The system scans these character folders:
- `char_a_pONE1` - Character variant 1
- `char_a_pONE2` - Character variant 2
- `char_a_pONE3` - Character variant 3
- `char_a_p1` - Base page 1

## Development Notes

### Adding New Layers

To add support for more layers (cloaks, face items, tools):

1. **Add layer definition** in `LAYERS` dictionary (CharacterCreator.gd:20)
2. **Add sprite node** to scene (copy existing sprite, rename)
3. **Add UI section** in the controls panel
4. **Update populate_ui()** to create buttons for new layer

Example for adding cloaks:
```gdscript
# In LAYERS dict:
"cloak": {"code": "2clo", "node_name": "CloakSprite", "path": "2clo"}

# In populate_ui():
var cloak_container = parts_container.get_node("CloakSection/CloakOptions")
populate_layer_options(cloak_container, "cloak")
```

### Animation Speed

Current animation timing (CharacterCreator.gd:53):
```gdscript
var animation_speed = 0.135  # 135ms per frame (walk speed)
```

Change this to adjust animation playback speed:
- Walk: 0.135 (135ms per frame) - **current setting**
- Slower: Increase the value (e.g., 0.200)
- Faster: Decrease the value (e.g., 0.100)
- Run: See original Mana Seed guide for variable frame timing

### Frame Calculation

Frames are calculated for walk animation as:
```gdscript
walk_row = current_direction + 4  # Walk is on rows 5-8 (indices 4-7)
frame_index = walk_row * 8 + current_frame
```

**Walk Animation Rows:**
- Direction 0 (South): row 5 (index 4), frames 32-37
- Direction 1 (West): row 6 (index 5), frames 40-45
- Direction 2 (East): row 7 (index 6), frames 48-53
- Direction 3 (North): row 8 (index 7), frames 56-61

**Sprite Sheet Layout (512x512, 8x8 grid):**
- Rows 1-4: Idle, push, pull, jump
- Rows 5-8: Walk animation (6 frames each)

## Future Enhancements

### Planned Features
- [ ] Export character configuration to JSON
- [ ] Save/load character presets
- [ ] Animation speed control slider
- [ ] Support for all 8 layers
- [ ] Support for other animation pages (p2, p3, p4)
- [ ] Color/palette swapping
- [ ] Frame-by-frame animation scrubbing
- [ ] Multiple animation types (run, farm, fish, etc.)

### Integration Ideas
- Create character presets for NPCs
- Build character creation UI for player customization
- Generate character sprites for the game at runtime
- Create animation previews for the character creator system

## Troubleshooting

### No character parts appear
- Check that character assets are in `assets/graphics/characters/`
- Check console for "Asset scan complete" message
- Verify .import files exist for PNG files

### Character looks wrong
- Verify layer order in scene tree matches documentation
- Check that all sprites have `texture_filter = 1` (nearest neighbor)
- Ensure `hframes = 8` and `vframes = 8` on all sprites

### Animation too fast/slow
- Adjust `animation_speed` variable in script
- Default is 0.135 (135ms per frame)

### Parts don't align
- All sprites should be 512x512 with 64x64 frames
- Check that sprite positions are all (0, 0)
- Verify sprites are in same Node2D container

## Technical Reference

### Key Files
- **Scene**: scenes/experiments/CharacterCreator.tscn
- **Script**: scripts/experiments/CharacterCreator.gd
- **Original Guide**: assets/graphics/characters/guides/using this base.txt
- **Layer Guide**: assets/graphics/characters/guides/paper doll demonstration.png

### Script Functions
- `scan_character_assets()` - Finds all character parts
- `populate_ui()` - Creates selection buttons
- `update_preview()` - Applies selected parts to sprites
- `update_frame_display()` - Updates animation frame
- `_on_part_selected()` - Handles part selection
- `_on_direction_changed()` - Changes facing direction

## Credits

Character assets from the **Mana Seed Character Base** system.
See `assets/graphics/characters/guides/` for original documentation.
