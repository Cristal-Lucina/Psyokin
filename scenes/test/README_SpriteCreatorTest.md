# Sprite Creator Test Scene

## Overview
This test scene demonstrates the new Mana Seed Farmer Sprite System integration with Godot.

## Files
- **SpriteCreatorTest.tscn** - The test scene
- **FarmerSpriteAnimator.gd** - Animation script that handles the farmer sprite system

## How It Works

### Sprite System Details
- Uses 64x64 pixel cells arranged in a 16x16 grid (256 total cells)
- Supports layered paper doll system (body, hair, clothing, accessories, etc.)
- Frame numbers match the cell reference guide
- Timing values converted from milliseconds to seconds for Godot

### Controls
- **Arrow Keys**: Move character (tests walk animations)
- **Shift + Arrow Keys**: Run animations
- **Number Keys 1-8**: Test specific animations manually
  - 1: Walk Down
  - 2: Walk Up
  - 3: Walk Right
  - 4: Walk Left
  - 5: Run Down
  - 6: Run Up
  - 7: Run Right
  - 8: Run Left

## Animation System

The animation system reads data from the animation guide and implements:
- Frame sequences (cell numbers)
- Timing (converted from ms to seconds)
- Horizontal flipping for left-facing animations

### Current Implemented Animations
Based on the farmer base animation guide:
- Walk (Down, Up, Right, Left)
- Run (Down, Up, Right, Left)
- Idle (Down, Up, Right, Left)

### Adding New Animations
To add more animations from the guide:

1. Open the animation guide PNG: `assets/graphics/characters/New Character System/SpriteSystem/_supporting files/farmer base animation guide.png`

2. Find the animation you want (purple numbers = cell IDs, yellow numbers = timing in ms)

3. Add to the `animations` dictionary in `FarmerSpriteAnimator.gd`:
   ```gdscript
   "animation_name": [
       AnimationFrame.new(cell_number, timing_in_seconds, flip_horizontal),
       AnimationFrame.new(48, 0.138),  // Example
       AnimationFrame.new(49, 0.138, true),  // Flipped
   ]
   ```

## Sprite Layers

### Currently Active Layers
- **BodyLayer**: `fbas_01body_human_00.png`
- **HairLayer**: `fbas_13hair_twintail_00.png`

### Available Layers (from readme)
Layers are numbered from bottom to top:
- 00undr: Back elements (wings, cloak backs)
- 01body: Base body ✓ (currently used)
- 02sock: Leg wear
- 03fot1: Small footwear
- 04lwr1: Pants/shorts
- 05shrt: Shirts/blouses
- 06lwr2: Overalls
- 07fot2: Large footwear
- 08lwr3: Skirts/dresses
- 09hand: Gloves/bracers
- 10outr: Jackets/vests
- 11neck: Scarves/cloaks
- 12face: Glasses/masks
- 13hair: Hairstyles ✓ (currently used)
- 14head: Hats/hoods
- 15over: Top effects (front wings, magic)

### Adding More Layers
To add additional sprite layers:

1. Add the texture as an ExtResource in the .tscn file
2. Add a new Sprite2D node under FarmerSprite
3. Set: `texture_filter = 1`, `hframes = 16`, `vframes = 16`
4. Add the layer to the `apply_frame()` function in the script

## Next Steps

### For Testing
1. Open the scene in Godot: `scenes/test/SpriteCreatorTest.tscn`
2. Run the scene (F6)
3. Test the controls to verify animations work correctly

### For Integration
Once testing is complete, the animation system can be:
- Integrated into the main Player scene
- Extended with more animations (jump, push, pull, plant seeds, water, etc.)
- Enhanced with more costume layers
- Connected to player input system

## Notes
- All sprite sheets use 16x16 cell layout (not 8x8 like the old system)
- Some animations require horizontal flipping (left = right flipped)
- Timing values from the guide are in milliseconds (138ms = 0.138s)
- The white spin graphic in the guide means "flip this frame horizontally"

## References
- Animation Guide: `assets/graphics/characters/New Character System/SpriteSystem/_supporting files/farmer base animation guide.png`
- Cell Reference: `assets/graphics/characters/New Character System/SpriteSystem/_supporting files/farmer base cell reference.png`
- System Readme: `assets/graphics/characters/New Character System/SpriteSystem/Farmer Sprite System readme.txt`
