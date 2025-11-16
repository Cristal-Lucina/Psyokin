# Controller Icons Test Scene

## Overview
This test scene showcases all 27 individual controller button icons that were extracted from the composite SVG files.

## Location
- **Scene File:** `scenes/experiments/ControllerIconsTest.tscn`
- **Script File:** `scripts/experiments/ControllerIconsTest.gd`

## How to Run
1. Open the project in Godot
2. Navigate to `scenes/experiments/ControllerIconsTest.tscn`
3. Press F6 (or click "Run Current Scene" in Godot)
4. Alternatively, set it as the main scene and press F5

## Features
- Displays all 27 controller button icons organized by category
- Categories:
  - **Shoulder Buttons** (8): LB, RB, LT, RT, L1, R1, L2, R2
  - **Face Buttons** (4): X, Circle, Square, Triangle
  - **D-Pad** (4): Up, Down, Left, Right
  - **Analog Sticks** (4): L Stick, R Stick, L3, R3
  - **Special Buttons** (3): Option, Share, Touchpad
  - **Trigger Indicators** (4): L/R Trigger Up/Down

- Scrollable layout for easy viewing
- Each icon is displayed at 64x64 pixels with proper scaling
- All icons maintain transparency and can be viewed on any background
- Back button to return to main menu
- ESC or Q key for quick exit

## Icon Sources
All icons are loaded from:
`assets/graphics/icons/UI/Controller_Icons/[category]/[icon_name].svg`

## Technical Details
- Uses `TextureRect` nodes with stretch mode 5 (keep aspect centered)
- SVG format ensures scalability without quality loss
- Dark background (#1B2638 → RGB: 15%, 15%, 20%) for better visibility
- Organized using VBoxContainer and HBoxContainer for clean layout
- Responsive design with ScrollContainer for overflow handling

## Usage in Your Project
This test scene serves as a reference for:
1. How to load and display the controller icons
2. Proper sizing and scaling of SVG icons
3. Layout organization for icon displays
4. Integration examples for UI elements

You can copy individual icon display sections to use in your own UI panels.
