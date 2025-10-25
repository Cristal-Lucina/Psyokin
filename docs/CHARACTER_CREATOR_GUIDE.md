# Character Creator Experiment

## Overview

This is a standalone experimental scene for testing the Mana Seed character layering system. It allows you to mix and match different character parts (body, outfit, hair, hats) and see them layer correctly in real-time. The character displays in idle/standing pose for easy customization preview.

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
- **Character Display**: Shows the layered character in idle/standing pose
- **Pose Label**: Shows "Pose: Idle" (frame 0 of each direction)
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

### Viewing Directions

- The character displays the **idle/standing pose** (frame 0)
- Use **Direction buttons** to rotate the character
- See all 4 facing directions: South, West, East, North
- Animation is **disabled** to focus on customization

**Note**: To enable walk animation, uncomment the `_process()` function in CharacterCreator.gd

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

### Enabling Animation (Optional)

Animation is currently **disabled** to show only the idle standing pose. To re-enable the walk animation:

1. Open `scripts/experiments/CharacterCreator.gd`
2. Uncomment the animation variables (lines 52-53):
```gdscript
var animation_timer = 0.0
var animation_speed = 0.135  # 135ms per frame (walk speed)
```
3. Uncomment the `_process()` function (lines 64-70)
4. Change line 206 back to: `frame_label.text = "Frame: " + str(current_frame)`

Animation speed can be adjusted:
- Walk: 0.135 (135ms per frame)
- Run: See original guide for variable frame timing
- Slower: Increase the value (e.g., 0.200)
- Faster: Decrease the value (e.g., 0.100)

### Frame Calculation

Frames are calculated as:
```gdscript
frame_index = direction_row * 8 + current_frame
```

- Direction 0 (South): frames 0-7
- Direction 1 (West): frames 8-15
- Direction 2 (East): frames 16-23
- Direction 3 (North): frames 24-31

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
