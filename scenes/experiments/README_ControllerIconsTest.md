# Controller Icons Test Scene - Complete Collection

## Overview
Comprehensive test scene showcasing all 49 controller button icons from the PNG asset collection, organized by platform.

## Location
- **Scene File:** `scenes/experiments/ControllerIconsTest.tscn`
- **Script File:** `scripts/experiments/ControllerIconsTest.gd`

## How to Run
1. Open the project in Godot
2. Navigate to `scenes/experiments/ControllerIconsTest.tscn`
3. Press F6 (or click "Run Current Scene")
4. Alternatively, set it as the main scene and press F5

## Icon Organization

### Xbox Controller (14 icons)
- **Face Buttons**: A, B, X, Y
- **Shoulders**: LB, RB, LT, RT
- **D-Pad**: Up, Down, Left, Right
- **Special**: Share, Options

### PlayStation Controller (12 icons)
- **Face Buttons**: Cross, Circle, Square, Triangle
- **Shoulders**: L1, R1, L2, R2
- **D-Pad**: Up, Down, Left, Right

### Nintendo Controller (4+ icons)
- **D-Pad**: Up, Down, Left, Right
- **Note**: Uses Xbox-style shoulder buttons (LB/RB/LT/RT)

### Universal Controls (19 icons)
- **Analog Sticks**: Left Stick, Right Stick, L3, R3
- **Left Stick Directions**: Up, Down, Left, Right
- **Right Stick Directions**: Up, Down, Left, Right
- **Generic Directions**: Up, Down, Left, Right, D-Pad Any
- **Special**: Share, Options

## Icon Source
All icons are loaded from:
`assets/graphics/icons/UI/PNG and PSD - Light/Controller/1x/`

Icons are named as `Asset 50.png` through `Asset 98.png`.

## Features
- **Dynamic Layout**: Icons are generated programmatically at runtime
- **Organized Display**: Icons grouped by controller type and category
- **Light Theme**: Uses light background for optimal PNG visibility
- **Scrollable**: Grid container with scroll support for all icons
- **Navigation**: ESC or Q key to exit, Back button to return to main menu
- **Console Output**: Prints icon count summary on load

## Asset Mapping

The scene uses the following asset mapping:

| Asset | Button | Category |
|-------|--------|----------|
| 50 | Share | Universal |
| 51 | Options | Universal |
| 52-55 | Direction Up/Left/Right/Down | Generic |
| 56-59 | Right Stick Left/Right/Up/Down | Universal |
| 60-63 | Left Stick Left/Right/Up/Down | Universal |
| 64-67 | Nintendo D-Pad Left/Right/Down/Up | Nintendo |
| 68-71 | Xbox D-Pad Left/Down/Right/Up | Xbox |
| 72-75 | PlayStation D-Pad Left/Right/Down/Up | PlayStation |
| 76 | D-Pad Any | Universal |
| 77-78 | Xbox Share/Options | Xbox |
| 79-82 | Xbox X/Y/B/A | Xbox |
| 83-86 | PlayStation Circle/Triangle/Square/X | PlayStation |
| 87-90 | R3/L3/Right Stick/Left Stick | Universal |
| 91-94 | PlayStation R2/L2/R1/L1 | PlayStation |
| 95-98 | Xbox RT/LT/RB/LB | Xbox |

## Technical Details
- **Grid Layout**: 8-column GridContainer for organized display
- **Dynamic Creation**: Icons created at runtime using GDScript
- **PNG Format**: All icons are 1x scale PNG files from Light theme
- **Resource Loading**: Uses ResourceLoader for efficient icon loading
- **Platform Support**: Supports Xbox, PlayStation, Nintendo, and Universal controls

## Usage in Your Project
This test scene serves as a reference for:
1. Complete controller icon asset catalog
2. Platform-specific button mapping
3. Dynamic icon loading and display
4. UI layout organization examples
5. Cross-platform controller support

You can copy icon references from the script's `controller_icons` dictionary for use in your own UI panels and control remapping screens.
