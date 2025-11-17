# Controller Icons Test Scene - Complete Collection

## Overview
Comprehensive test scene showcasing all 51 controller button icons from the PNG asset collection, organized by platform with theme switching support.

## Location
- **Scene File:** `scenes/experiments/ControllerIconsTest.tscn`
- **Script File:** `scripts/experiments/ControllerIconsTest.gd`

## How to Run
1. Open the project in Godot
2. Navigate to `scenes/experiments/ControllerIconsTest.tscn`
3. Press F6 (or click "Run Current Scene")
4. Alternatively, set it as the main scene and press F5

## Features

### Theme Switching
- **Toggle Button** at the top of the screen
- **Light Theme**: Dark background (#15151A) for light-colored icons
- **Dark Theme**: Light background (#F5F5F7) for dark-colored icons
- Icons automatically reload from appropriate folder when switching themes
- All text colors adapt to maintain readability

### Organization by Platform

#### Xbox Controller (12 icons)
- **Face Buttons**: A, B, X, Y
- **Shoulders**: LB, RB, LT, RT
- **D-Pad**: Up, Down, Left, Right

#### PlayStation Controller (14 icons)
- **Face Buttons**: Cross, Circle, Square, Triangle
- **Shoulders**: L1, R1, L2, R2
- **D-Pad**: Up, Down, Left, Right
- **Special**: Share, Options (PlayStation exclusive)

#### Nintendo Controller (14 icons)
- **Face Buttons**: B, A, Y, X (in Nintendo layout order)
- **Shoulders**: LB, RB, LT, RT (uses Xbox-style shoulder buttons)
- **D-Pad**: Up, Down, Left, Right
- **Special**: + Button, - Button (Nintendo exclusive buttons with circle borders)

#### Universal Controls (17 icons)
- **Analog Sticks**: Left Stick, Right Stick, L3, R3
- **Left Stick Directions**: Up, Down, Left, Right
- **Right Stick Directions**: Up, Down, Left, Right
- **Generic Directions**: Up, Down, Left, Right, D-Pad Any

## New Assets Created

### Nintendo Special Buttons
- **Asset 99.svg**: + Button (plus sign in circle)
- **Asset 100.svg**: - Button (minus sign in circle)

Both created in:
- `assets/graphics/icons/UI/PNG and PSD - Light/Controller/1x/`
- `assets/graphics/icons/UI/PNG and PSD - Dark/Controller/1x/`

## Icon Source
Icons are loaded dynamically from:
- **Light Theme**: `assets/graphics/icons/UI/PNG and PSD - Light/Controller/1x/`
- **Dark Theme**: `assets/graphics/icons/UI/PNG and PSD - Dark/Controller/1x/`

## Platform-Specific Notes

### Xbox
- Standard Xbox controller layout
- LB/RB (bumpers) and LT/RT (triggers)
- No Share/Options buttons (these are PlayStation-specific)

### PlayStation
- Standard DualShock/DualSense layout
- L1/R1 (bumpers) and L2/R2 (triggers)
- Share and Options buttons included

### Nintendo
- Uses Xbox face buttons in Nintendo order: B, A, Y, X
- Uses Xbox shoulder buttons (LB/RB/LT/RT) as Nintendo uses same style
- Custom + and - buttons for menu/system buttons
- Nintendo-specific D-pad icons

### Universal
- Platform-agnostic icons
- Generic directional indicators
- Analog stick representations

## Asset Mapping

| Asset Range | Description | Category |
|-------------|-------------|----------|
| 50-51 | Share/Options | PlayStation Special |
| 52-55 | Generic Directions | Universal |
| 56-63 | Stick Directions | Universal |
| 64-67 | Nintendo D-Pad | Nintendo |
| 68-71 | Xbox D-Pad | Xbox |
| 72-75 | PlayStation D-Pad | PlayStation |
| 76 | D-Pad Any | Universal |
| 79-82 | Xbox Face (X/Y/B/A) | Xbox |
| 83-86 | PS Face (Circle/Triangle/Square/Cross) | PlayStation |
| 87-90 | Analog Sticks (R3/L3/Right/Left) | Universal |
| 91-94 | PlayStation Shoulders (R2/L2/R1/L1) | PlayStation |
| 95-98 | Xbox Shoulders (RT/LT/RB/LB) | Xbox & Nintendo |
| 99-100 | +/- Buttons | Nintendo Special |

## Controls
- **Theme Toggle Button**: Switch between Light and Dark themes
- **ESC or Q**: Quick exit
- **Back Button**: Return to main menu

## Technical Details
- **Grid Layout**: 8-column GridContainer for organized display
- **Dynamic Creation**: Icons created at runtime using GDScript
- **Theme System**: Automatic background and text color adjustment
- **Resource Loading**: Efficient theme-based icon loading
- **Platform Support**: Xbox, PlayStation, Nintendo, and Universal controls

## Usage in Your Project
This test scene serves as a reference for:
1. Complete controller icon catalog with theme support
2. Platform-specific button mapping
3. Theme switching implementation
4. Dynamic icon loading from different asset folders
5. Cross-platform controller support
6. Nintendo-specific button creation

You can copy icon references from the script's `controller_icons` dictionary for use in your own UI panels and control remapping screens.
