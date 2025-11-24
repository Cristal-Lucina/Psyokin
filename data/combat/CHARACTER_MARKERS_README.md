# Character Marker Positioning Guide

This guide explains how to adjust character positioning, sprite sizes, shadow placement, and turn indicator animations in battle using CSV configuration files.

## Files Overview

1. **character_marker_positions.csv** - Controls where characters appear and their visual properties
2. **turn_indicator_animation.csv** - Controls the panel slide animation when it's a character's turn

---

## 1. character_marker_positions.csv

Controls the exact positioning and visual properties of character sprites (both allies and enemies) in battle.

### What Are Character Markers?

Character markers are the visual representation of combatants in battle. Each marker includes:
- **Sprite** - The character's animated sprite (70px height by default)
- **Shadow** - A circle shadow beneath the character
- **Position** - X/Y coordinates within the marker panel
- **Formation Offset** - Depth positioning for 2.5D fighting formation effect

### Column Descriptions

| Column | Description | Example | Notes |
|--------|-------------|---------|-------|
| **position_id** | Unique ID (1-6) | 1 | Auto-increment |
| **side** | ally or enemy | ally | Which side of battle |
| **position_index** | Position in formation (0-2) | 0 | 0=top, 1=middle, 2=bottom |
| **position_name** | Descriptive name | Hero/Top | For reference |
| **sprite_x** | Sprite X position | 40 | Pixels from left edge of panel |
| **sprite_y** | Sprite Y position | 40 | Pixels from top edge of panel |
| **sprite_scale** | Sprite scale multiplier | 4.375 | Scale factor (4.375 = 70px height) |
| **x_offset** | Formation depth offset | -60 | Negative=left, positive=right |
| **shadow_x** | Shadow X position | 40 | Pixels from left edge |
| **shadow_y** | Shadow Y position | 55 | Pixels from top edge |
| **shadow_scale_x** | Shadow horizontal scale | 3 | Width multiplier |
| **shadow_scale_y** | Shadow vertical scale | 1.5 | Height multiplier (ellipse) |
| **z_index** | Layering order | 108 | Higher=in front (108-110) |
| **slide_distance** | Turn panel slide distance | 140 | Pixels to slide on turn |
| **slide_duration** | Slide animation duration | 0.3 | Seconds |
| **slide_ease** | Slide easing function | CUBIC_OUT | Animation curve |
| **notes** | Developer notes | Hero position - no offset | Documentation |

### Understanding Positioning

#### Base Positions (sprite_x, sprite_y)
The base position is where the sprite appears within its marker panel.

```
Default: (40, 40)
- X: 40px from left edge
- Y: 40px from top edge

To move character right: Increase sprite_x (e.g., 60)
To move character left: Decrease sprite_x (e.g., 20)
To move character down: Increase sprite_y (e.g., 50)
To move character up: Decrease sprite_y (e.g., 30)
```

#### Formation Offset (x_offset)
Creates the 2.5D fighting formation effect where characters at bottom appear in front.

**Allies (left side):**
```csv
position_index,x_offset,sprite_x,Effect
0,-0,-40,Top ally - no offset
1,-60,-20,Middle - 60px to the left
2,-120,-80,Bottom - 120px to the left (most forward)
```

**Enemies (right side):**
```csv
position_index,x_offset,sprite_x,Effect
0,0,40,Top enemy - no offset
1,60,100,Middle - 60px to the right
2,120,160,Bottom - 120px to the right (most forward)
```

**Visual Effect:**
```
Allies:              Enemies:
  Hero (0)              Enemy (0)
    Ally1 (60px←)         Enemy1 (→60px)
      Ally2 (120px←)        Enemy2 (→120px)
```

#### Z-Index Layering
Controls which sprites appear in front of others.

```csv
position_index,z_index,Visibility
0,108,Furthest back
1,109,Middle layer
2,110,Frontmost (appears over other characters)
```

**Lower z-index = behind**
**Higher z-index = in front**

### Sprite Scaling

The `sprite_scale` value determines character size:

```csv
sprite_scale,Height (approx),Use Case
3.0,48px,Small enemies (rats, bugs)
4.375,70px,Standard characters (default)
5.0,80px,Large characters
6.5,104px,Boss characters
8.0,128px,Giant bosses
```

**Formula:** `height ≈ 16 * sprite_scale` (base sprite is 16px)

### Shadow Configuration

Shadows create depth perception beneath characters.

**Position:**
```csv
shadow_x,shadow_y,Effect
40,55,Directly under sprite (default)
35,55,Shadow slightly to left
45,55,Shadow slightly to right
40,60,Shadow further down (taller character)
```

**Scale:**
```csv
shadow_scale_x,shadow_scale_y,Shape
3,1.5,Standard ellipse (default)
4,1.5,Wider shadow (large character)
2,1,Narrow shadow (slim character)
3,2,Rounder shadow
```

### Example Configurations

#### Making Allies Closer Together

**Before (Current):**
```csv
position_id,side,position_index,sprite_x,x_offset
1,ally,0,40,0
2,ally,1,-20,-60
3,ally,2,-80,-120
```

**After (Tighter Formation):**
```csv
position_id,side,position_index,sprite_x,x_offset
1,ally,0,40,0
2,ally,1,10,-30
3,ally,2,-20,-60
```

#### Making Characters Larger

**Before:**
```csv
sprite_scale,sprite_y
4.375,40
```

**After:**
```csv
sprite_scale,sprite_y
5.5,35
```
*Increased scale to 5.5 and moved up 5px to compensate*

#### Adjusting Shadow for Tall Character

**Before:**
```csv
shadow_y,shadow_scale_x,shadow_scale_y
55,3,1.5
```

**After:**
```csv
shadow_y,shadow_scale_x,shadow_scale_y
65,3.5,1.5
```
*Moved shadow down 10px and made it wider*

---

## 2. turn_indicator_animation.csv

Controls the panel slide animation that happens when it's a character's turn.

### Column Descriptions

| Column | Description | Valid Values | Notes |
|--------|-------------|--------------|-------|
| **animation_id** | Unique ID | 1 | Single config row |
| **animation_name** | Name | TURN_PANEL_SLIDE | For reference |
| **enabled** | Animation on/off | TRUE/FALSE | Disable to skip animation |
| **slide_distance** | How far to slide | 140 (pixels) | Distance in pixels |
| **slide_forward_duration** | Slide out time | 0.3 (seconds) | Duration of slide forward |
| **slide_forward_trans** | Transition type | CUBIC, ELASTIC, BOUNCE, etc. | Animation curve |
| **slide_forward_ease** | Easing mode | OUT, IN, IN_OUT, OUT_IN | Easing direction |
| **slide_back_duration** | Slide back time | 0.2 (seconds) | Duration of slide back |
| **slide_back_trans** | Transition type | CUBIC, ELASTIC, BOUNCE, etc. | Animation curve |
| **slide_back_ease** | Easing mode | IN, OUT, IN_OUT, OUT_IN | Easing direction |
| **notes** | Description | - | Documentation |

### Transition Types

| Type | Effect | Use For |
|------|--------|---------|
| **LINEAR** | Constant speed | Mechanical movement |
| **SINE** | Smooth gentle curve | Subtle animations |
| **QUAD** | Gentle acceleration | Soft movement |
| **CUBIC** | Medium acceleration | Natural movement (default) |
| **QUART** | Strong acceleration | Punchy animations |
| **QUINT** | Very strong acceleration | Dramatic effect |
| **EXPO** | Exponential curve | Explosive movement |
| **CIRC** | Circular curve | Smooth arc |
| **BOUNCE** | Bouncing effect | Playful, energetic |
| **ELASTIC** | Spring-like overshoot | Cartoony, elastic |
| **BACK** | Slight overshoot | Anticipation effect |
| **SPRING** | Physical spring simulation | Bouncy, physics-based |

### Ease Types

| Type | Effect |
|------|--------|
| **OUT** | Fast start, slow end (default for forward) |
| **IN** | Slow start, fast end (default for back) |
| **IN_OUT** | Slow start, fast middle, slow end |
| **OUT_IN** | Fast start, slow middle, fast end |

### Animation Examples

#### Default (Current)
```csv
slide_distance,slide_forward_duration,slide_forward_trans,slide_forward_ease,slide_back_duration,slide_back_trans,slide_back_ease
140,0.3,CUBIC,OUT,0.2,CUBIC,IN
```
*Smooth natural slide forward, quick return*

#### Bouncy/Playful
```csv
slide_distance,slide_forward_duration,slide_forward_trans,slide_forward_ease,slide_back_duration,slide_back_trans,slide_back_ease
140,0.4,BOUNCE,OUT,0.3,ELASTIC,IN
```
*Bounces forward, springs back*

#### Snappy/Fast
```csv
slide_distance,slide_forward_duration,slide_forward_trans,slide_forward_ease,slide_back_duration,slide_back_trans,slide_back_ease
100,0.15,QUAD,OUT,0.1,QUAD,IN
```
*Quick short slide, fast return*

#### Dramatic/Boss
```csv
slide_distance,slide_forward_duration,slide_forward_trans,slide_forward_ease,slide_back_duration,slide_back_trans,slide_back_ease
200,0.5,EXPO,OUT,0.4,BACK,IN
```
*Large explosive slide, anticipation on return*

#### Disabled
```csv
enabled
FALSE
```
*Set enabled to FALSE to completely disable turn indicator sliding*

---

## Making Adjustments

### Quick Adjustments

**Move all characters up 10px:**
1. Open `character_marker_positions.csv`
2. Change all `sprite_y` values from `40` to `30`
3. Change all `shadow_y` values from `55` to `45`
4. Save and reload battle

**Make characters 20% larger:**
1. Find current `sprite_scale` (e.g., `4.375`)
2. Multiply by 1.2: `4.375 * 1.2 = 5.25`
3. Update all `sprite_scale` values to `5.25`
4. Adjust `sprite_y` up by 5-10px to compensate
5. Save and reload battle

**Tighten formation spacing:**
1. Find `x_offset` values for position_index 1 and 2
2. Reduce the absolute values by half:
   - `ally,1,-60` → `-30`
   - `ally,2,-120` → `-60`
   - `enemy,1,60` → `30`
   - `enemy,2,120` → `60`
3. Update corresponding `sprite_x` values
4. Save and reload battle

**Make turn slide more dramatic:**
1. Open `turn_indicator_animation.csv`
2. Change `slide_distance` from `140` to `200`
3. Change `slide_forward_trans` from `CUBIC` to `EXPO`
4. Change `slide_forward_duration` from `0.3` to `0.5`
5. Save and reload battle

### Testing Your Changes

1. **Save the CSV file** in your text editor
2. **Launch the battle scene** in Godot
3. **Watch the console** for `[BattleFlowConfigLoader]` messages
4. **Observe character positioning** when battle starts
5. **Watch turn animations** when characters take their turn
6. **Adjust values** and repeat until satisfied

### Troubleshooting

**Characters appearing in wrong position:**
- Check `sprite_x` and `sprite_y` values
- Ensure `position_index` matches correctly (0, 1, 2)
- Verify `side` is "ally" or "enemy" (lowercase)

**Shadow not aligned:**
- Shadow position is independent of sprite
- Set `shadow_x = sprite_x` for direct alignment
- Adjust `shadow_y` to be 10-20px below sprite base

**Characters overlapping:**
- Check `z_index` values (should be 108, 109, 110)
- Verify `x_offset` creates proper spacing
- Ensure formation offsets don't conflict

**Turn animation not working:**
- Check `enabled` is TRUE in `turn_indicator_animation.csv`
- Verify `slide_distance` is not 0
- Check console for any CSV loading errors

**Sprites too large/small:**
- Adjust `sprite_scale` value
- Standard: 4.375 (70px height)
- Large: 5.5-6.5, Small: 3.0-4.0

---

## Advanced Tips

### Creating Asymmetric Formations

You can create unique formations for allies vs enemies:

**Allies (V-formation):**
```csv
position_index,x_offset,sprite_y
0,0,30
1,-60,45
2,-120,60
```

**Enemies (Line formation):**
```csv
position_index,x_offset,sprite_y
0,0,40
1,60,40
2,120,40
```

### Dynamic Boss Sizing

For boss battles, increase scale and adjust position:

```csv
position_id,side,position_index,sprite_scale,sprite_x,sprite_y,shadow_scale_x,z_index
4,enemy,0,8.0,20,10,5,110
```
*Large boss (8x scale), positioned higher, bigger shadow, front z-index*

### Perspective Depth Effect

Adjust Y positions to enhance 3D depth illusion:

```csv
position_index,sprite_y,Effect
0,35,Top (back) - higher on screen
1,42,Middle
2,50,Bottom (front) - lower on screen
```

### Animation Personality

Match animations to character types:

**Agile/Fast Characters:**
```csv
slide_distance,duration,trans,ease
120,0.2,QUAD,OUT
```

**Heavy/Slow Characters:**
```csv
slide_distance,duration,trans,ease
100,0.5,EXPO,IN_OUT
```

**Magical/Mystical:**
```csv
slide_distance,duration,trans,ease
160,0.4,ELASTIC,OUT
```

---

## Reference Values

### Standard Scales
- **3.0** = 48px (small)
- **4.375** = 70px (standard)
- **6.0** = 96px (large)
- **8.0** = 128px (boss)

### Standard Z-Indices
- **104** = Shadows
- **108** = Back row sprites
- **109** = Middle row sprites
- **110** = Front row sprites

### Standard Durations
- **0.1-0.2s** = Very fast/snappy
- **0.3-0.4s** = Normal speed
- **0.5-0.7s** = Slow/dramatic
- **1.0s+** = Very slow/cinematic
