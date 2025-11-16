# Controller Icons

This directory contains individual controller button icons extracted from the original composite SVG file. Each icon has been separated into its own SVG file with the dark blue background removed, making them easy to use on any background.

## Directory Structure

```
Controller_Icons/
├── shoulder_buttons/    # Bumper and trigger buttons
│   ├── LB.svg          # Left Bumper
│   ├── RB.svg          # Right Bumper
│   ├── LT.svg          # Left Trigger
│   ├── RT.svg          # Right Trigger
│   ├── L1.svg          # PlayStation L1
│   ├── R1.svg          # PlayStation R1
│   ├── L2.svg          # PlayStation L2
│   └── R2.svg          # PlayStation R2
├── face_buttons/        # Main action buttons
│   ├── X_Button.svg    # PlayStation X (Cross)
│   ├── Circle_Button.svg   # PlayStation Circle
│   ├── Square_Button.svg   # PlayStation Square
│   └── Triangle_Button.svg # PlayStation Triangle
├── dpad/               # Directional pad buttons
│   ├── DPad_Up.svg
│   ├── DPad_Down.svg
│   ├── DPad_Left.svg
│   └── DPad_Right.svg
├── analog_sticks/      # Analog stick buttons
│   ├── L_Stick.svg     # Left stick
│   ├── R_Stick.svg     # Right stick
│   ├── L3.svg          # Left stick pressed
│   └── R3.svg          # Right stick pressed
└── special_buttons/    # Special controller buttons
    ├── Option.svg      # Options/Start button
    ├── Share.svg       # Share/Select button
    └── Touchpad.svg    # Touchpad icon

## Features

- **No Background**: All icons have had the dark blue background removed
- **Scalable**: SVG format allows infinite scaling without quality loss
- **Consistent Style**: All icons maintain the same visual style
- **Easy to Resize**: Each icon uses a viewBox attribute for easy scaling
- **Clean Colors**: White fill (#FFFFFF) for icon elements, dark (#1B2638) for text/labels

## Usage

### HTML
```html
<img src="shoulder_buttons/LB.svg" alt="Left Bumper" width="50" height="50">
```

### CSS
```css
.button-icon {
  background-image: url('face_buttons/X_Button.svg');
  background-size: contain;
  width: 32px;
  height: 32px;
}
```

### Inline SVG
You can also open any SVG file and copy its contents directly into your HTML for maximum control:
```html
<svg viewBox="..." width="32" height="32">
  <!-- SVG content -->
</svg>
```

## Customization

Since these are SVG files, you can easily customize them:
- Change colors by editing the `fill` attributes
- Adjust stroke widths
- Modify sizes via the `viewBox` attribute
- Add filters or effects

## File Naming Convention

- **LB/RB**: Xbox-style bumper buttons (Left/Right Bumper)
- **LT/RT**: Xbox-style trigger buttons (Left/Right Trigger)
- **L1/R1/L2/R2**: PlayStation-style shoulder buttons
- **L3/R3**: Analog stick press buttons
- Face buttons use PlayStation naming (X, Circle, Square, Triangle)

## License

These icons were extracted from the original controller icon sheet. Please ensure you have appropriate rights to use these icons in your project.
