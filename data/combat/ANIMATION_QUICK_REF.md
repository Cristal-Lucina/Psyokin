# Quick Reference: Character Animations vs Panel Animations

## The Confusion (Fixed!)

You correctly identified that there were TWO different animation systems that got mixed up:

1. **Character SPRITE Animations** - Which animation the character plays (Run, Jump, Idle, etc.)
2. **Turn PANEL Slide** - How far the marker panel slides left/right

## Fixed Structure

### character_marker_positions.csv - Controls CHARACTER behavior

**Sprite Animations (references sprite_animations_data.csv):**
```csv
turn_start_anim,turn_start_direction,turn_end_anim,turn_end_direction
Run,RIGHT,Run,RIGHT
```
- `turn_start_anim` - Which animation to play when turn starts (e.g., "Run", "Jump", "Idle")
- `turn_start_direction` - Direction for that animation ("LEFT", "RIGHT", "UP", "DOWN")
- `turn_end_anim` - Which animation to play when turn ends
- `turn_end_direction` - Direction for turn end animation

**Sprite Position Sliding:**
```csv
slide_forward_distance,slide_forward_duration,slide_back_distance,slide_back_duration
30,0.3,-30,0.3
```
- `slide_forward_distance` - How far sprite slides in pixels (+ = right, - = left)
- `slide_forward_duration` - How long the slide takes in seconds
- `slide_back_distance` - How far to slide back (usually negative of forward)
- `slide_back_duration` - Duration of slide back

### turn_indicator_animation.csv - Controls PANEL sliding

**Panel Slide Animation:**
```csv
slide_distance,slide_forward_duration,slide_forward_trans,slide_forward_ease
140,0.3,CUBIC,OUT
```
- This controls the PANEL moving left/right to indicate whose turn it is
- Completely separate from character sprite movement

## Now You Can Configure

### To change which animation plays on turn start:

**Make hero jump instead of run:**
```csv
position_id,turn_start_anim,turn_start_direction
1,Jump,DOWN
```

### To change how far character slides:

**Make characters slide further:**
```csv
position_id,slide_forward_distance,slide_back_distance
1,50,-50
```

### To change panel slide behavior:

**Make panel slide more dramatically:**
```csv
animation_id,slide_distance,slide_forward_trans
1,200,BOUNCE
```

## Available Sprite Animations

From `sprite_animations_data.csv`, you can use any animation like:
- **Run** - Running animation
- **Idle** - Standing still
- **Jump** - Jumping
- **Crouch** - Crouching
- **Hurt** - Taking damage
- **Attack** - Generic attack
- **Wand Strike**, **Sword Strike**, etc. - Weapon-specific attacks
- And more!

## Summary

**Before (Confusing):**
- Character marker CSV had "slide" properties that conflicted with panel slide
- No way to specify WHICH character animation to play

**After (Fixed):**
- `character_marker_positions.csv` = Character sprite animations and position
- `turn_indicator_animation.csv` = Panel slide animation
- Now properly references sprite animation system!
