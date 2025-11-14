extends Node

## Core Vibe Theme System
## Centralized styling utilities for the neon-kawaii street pop aesthetic
## Provides consistent colors, StyleBox creation, and UI element styling

## ═══════════════════════════════════════════════════════════════════════════════
## NEON ORCHARD COLOR PALETTE
## ═══════════════════════════════════════════════════════════════════════════════

const COLOR_ELECTRIC_LIME = Color(0.78, 1.0, 0.24)      # #C8FF3D - Success, confirm
const COLOR_BUBBLE_MAGENTA = Color(1.0, 0.29, 0.85)     # #FF4AD9 - Warning, important
const COLOR_SKY_CYAN = Color(0.30, 0.91, 1.0)           # #4DE9FF - Primary, info
const COLOR_CITRUS_YELLOW = Color(1.0, 0.91, 0.30)      # #FFE84D - Attention, highlight
const COLOR_PLASMA_TEAL = Color(0.13, 0.89, 0.70)       # #20E3B2 - Active, progress
const COLOR_GRAPE_VIOLET = Color(0.54, 0.25, 0.99)      # #8A3FFC - Special, rare
const COLOR_NIGHT_NAVY = Color(0.04, 0.06, 0.10)        # #0A0F1A - Deep background
const COLOR_INK_CHARCOAL = Color(0.07, 0.09, 0.15)      # #111827 - Panel background
const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)        # #F4F7FB - Text

## ═══════════════════════════════════════════════════════════════════════════════
## DESIGN CONSTANTS
## ═══════════════════════════════════════════════════════════════════════════════

const CORNER_RADIUS_SMALL = 12   # Small UI elements, tight spaces
const CORNER_RADIUS_MEDIUM = 16  # Standard buttons, panels
const CORNER_RADIUS_LARGE = 20   # Large panels, pill capsules

const BORDER_WIDTH_THIN = 2      # Standard borders
const BORDER_WIDTH_THICK = 3     # Emphasized borders

const SHADOW_SIZE_SMALL = 4      # Subtle depth
const SHADOW_SIZE_MEDIUM = 6     # Standard glow
const SHADOW_SIZE_LARGE = 12     # Strong emphasis

const PANEL_OPACITY_SEMI = 0.85  # Semi-transparent panels
const PANEL_OPACITY_FULL = 0.95  # Nearly opaque panels
const SHADOW_OPACITY = 0.4       # Shadow/glow transparency

## ═══════════════════════════════════════════════════════════════════════════════
## PANEL STYLE CREATION
## ═══════════════════════════════════════════════════════════════════════════════

## Create a pill capsule panel style with neon border
func create_panel_style(
	border_color: Color = COLOR_SKY_CYAN,
	bg_color: Color = COLOR_INK_CHARCOAL,
	opacity: float = PANEL_OPACITY_SEMI,
	corner_radius: int = CORNER_RADIUS_MEDIUM,
	border_width: int = BORDER_WIDTH_THIN,
	shadow_size: int = SHADOW_SIZE_MEDIUM
) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()

	# Background with opacity
	style.bg_color = Color(bg_color.r, bg_color.g, bg_color.b, opacity)

	# Neon border
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width

	# Pill capsule corners
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius

	# Soft glow shadow
	style.shadow_color = Color(border_color.r, border_color.g, border_color.b, SHADOW_OPACITY)
	style.shadow_size = shadow_size

	return style

## Create a panel style without borders (background only)
func create_background_style(
	bg_color: Color = COLOR_NIGHT_NAVY,
	opacity: float = PANEL_OPACITY_FULL,
	corner_radius: int = CORNER_RADIUS_MEDIUM
) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(bg_color.r, bg_color.g, bg_color.b, opacity)

	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius

	return style

## ═══════════════════════════════════════════════════════════════════════════════
## BUTTON STYLE CREATION
## ═══════════════════════════════════════════════════════════════════════════════

## Create a button style set (normal, hover, pressed, disabled)
func create_button_styles(
	accent_color: Color = COLOR_SKY_CYAN,
	corner_radius: int = CORNER_RADIUS_LARGE,
	border_width: int = BORDER_WIDTH_THIN
) -> Dictionary:
	# Normal state - dark fill with neon border
	var normal = StyleBoxFlat.new()
	normal.bg_color = COLOR_NIGHT_NAVY
	normal.border_color = accent_color
	normal.border_width_left = border_width
	normal.border_width_right = border_width
	normal.border_width_top = border_width
	normal.border_width_bottom = border_width
	normal.corner_radius_top_left = corner_radius
	normal.corner_radius_top_right = corner_radius
	normal.corner_radius_bottom_left = corner_radius
	normal.corner_radius_bottom_right = corner_radius
	normal.shadow_color = Color(accent_color.r, accent_color.g, accent_color.b, SHADOW_OPACITY)
	normal.shadow_size = SHADOW_SIZE_SMALL

	# Hover state - brighter glow
	var hover = normal.duplicate()
	hover.shadow_size = SHADOW_SIZE_MEDIUM
	hover.shadow_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.6)

	# Pressed state - filled with accent color
	var pressed = normal.duplicate()
	pressed.bg_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.3)
	pressed.shadow_size = SHADOW_SIZE_SMALL

	# Disabled state - dimmed
	var disabled = normal.duplicate()
	disabled.bg_color = Color(0.1, 0.1, 0.1)
	disabled.border_color = Color(0.3, 0.3, 0.3)
	disabled.shadow_size = 0

	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"disabled": disabled
	}

## Apply button styles to a button node
func style_button(
	button: Button,
	accent_color: Color = COLOR_SKY_CYAN,
	corner_radius: int = CORNER_RADIUS_LARGE
) -> void:
	var styles = create_button_styles(accent_color, corner_radius)
	button.add_theme_stylebox_override("normal", styles.normal)
	button.add_theme_stylebox_override("hover", styles.hover)
	button.add_theme_stylebox_override("pressed", styles.pressed)
	button.add_theme_stylebox_override("disabled", styles.disabled)
	button.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	button.add_theme_color_override("font_hover_color", accent_color)
	button.add_theme_color_override("font_pressed_color", COLOR_MILK_WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))

## Apply inverted button styles (bright background, dark text, no focus border)
func style_button_inverted(
	button: Button,
	bg_color: Color = COLOR_SKY_CYAN,
	text_color: Color = COLOR_NIGHT_NAVY,
	corner_radius: int = CORNER_RADIUS_SMALL
) -> void:
	# Normal state - bright fill, no border, subtle shadow
	var normal = StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.border_width_left = 0
	normal.border_width_right = 0
	normal.border_width_top = 0
	normal.border_width_bottom = 0
	normal.corner_radius_top_left = corner_radius
	normal.corner_radius_top_right = corner_radius
	normal.corner_radius_bottom_left = corner_radius
	normal.corner_radius_bottom_right = corner_radius
	normal.shadow_color = Color(bg_color.r, bg_color.g, bg_color.b, SHADOW_OPACITY)
	normal.shadow_size = SHADOW_SIZE_SMALL

	# Hover state - brighter glow
	var hover = normal.duplicate()
	hover.shadow_size = SHADOW_SIZE_MEDIUM
	hover.shadow_color = Color(bg_color.r, bg_color.g, bg_color.b, 0.7)
	hover.bg_color = Color(bg_color.r * 1.1, bg_color.g * 1.1, bg_color.b * 1.1)  # Slightly brighter

	# Pressed state - slightly darker
	var pressed = normal.duplicate()
	pressed.bg_color = Color(bg_color.r * 0.8, bg_color.g * 0.8, bg_color.b * 0.8)
	pressed.shadow_size = SHADOW_SIZE_SMALL

	# Disabled state - dimmed
	var disabled = normal.duplicate()
	disabled.bg_color = Color(bg_color.r * 0.5, bg_color.g * 0.5, bg_color.b * 0.5, 0.5)
	disabled.shadow_size = 0

	# Focus state - same as normal (no ugly white box)
	var focus = normal.duplicate()

	# Apply all styles
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", focus)

	# Set font colors
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_disabled_color", Color(text_color.r, text_color.g, text_color.b, 0.5))

## ═══════════════════════════════════════════════════════════════════════════════
## TAB STYLE CREATION
## ═══════════════════════════════════════════════════════════════════════════════

## Create tab button styles (selected vs unselected)
func create_tab_styles(
	accent_color: Color = COLOR_SKY_CYAN,
	corner_radius: int = CORNER_RADIUS_MEDIUM
) -> Dictionary:
	# Unselected tab - subtle border
	var unselected = StyleBoxFlat.new()
	unselected.bg_color = Color(COLOR_INK_CHARCOAL.r, COLOR_INK_CHARCOAL.g, COLOR_INK_CHARCOAL.b, 0.5)
	unselected.border_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.3)
	unselected.border_width_left = 1
	unselected.border_width_right = 1
	unselected.border_width_top = 1
	unselected.border_width_bottom = 1
	unselected.corner_radius_top_left = corner_radius
	unselected.corner_radius_top_right = corner_radius
	unselected.corner_radius_bottom_left = corner_radius
	unselected.corner_radius_bottom_right = corner_radius

	# Selected tab - bright neon border and glow
	var selected = StyleBoxFlat.new()
	selected.bg_color = Color(COLOR_INK_CHARCOAL.r, COLOR_INK_CHARCOAL.g, COLOR_INK_CHARCOAL.b, 0.9)
	selected.border_color = accent_color
	selected.border_width_left = BORDER_WIDTH_THIN
	selected.border_width_right = BORDER_WIDTH_THIN
	selected.border_width_top = BORDER_WIDTH_THIN
	selected.border_width_bottom = BORDER_WIDTH_THIN
	selected.corner_radius_top_left = corner_radius
	selected.corner_radius_top_right = corner_radius
	selected.corner_radius_bottom_left = corner_radius
	selected.corner_radius_bottom_right = corner_radius
	selected.shadow_color = Color(accent_color.r, accent_color.g, accent_color.b, SHADOW_OPACITY)
	selected.shadow_size = SHADOW_SIZE_MEDIUM

	return {
		"unselected": unselected,
		"selected": selected
	}

## Apply tab styles to a button
func style_tab(
	button: Button,
	accent_color: Color = COLOR_SKY_CYAN,
	is_selected: bool = false
) -> void:
	var styles = create_tab_styles(accent_color)
	if is_selected:
		button.add_theme_stylebox_override("normal", styles.selected)
		button.add_theme_color_override("font_color", accent_color)
	else:
		button.add_theme_stylebox_override("normal", styles.unselected)
		button.add_theme_color_override("font_color", Color(COLOR_MILK_WHITE.r, COLOR_MILK_WHITE.g, COLOR_MILK_WHITE.b, 0.7))

## ═══════════════════════════════════════════════════════════════════════════════
## SEPARATOR & LINE STYLES
## ═══════════════════════════════════════════════════════════════════════════════

## Create a neon separator line style
func create_separator_style(
	color: Color = COLOR_SKY_CYAN,
	thickness: int = 2
) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.shadow_color = Color(color.r, color.g, color.b, SHADOW_OPACITY)
	style.shadow_size = SHADOW_SIZE_SMALL
	return style

## ═══════════════════════════════════════════════════════════════════════════════
## TEXT & LABEL STYLING
## ═══════════════════════════════════════════════════════════════════════════════

## Style a label with Core Vibe colors
func style_label(
	label: Label,
	color: Color = COLOR_MILK_WHITE,
	font_size: int = 16
) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)

## Create a label with pill capsule background
func create_pill_label(
	text: String,
	accent_color: Color = COLOR_SKY_CYAN,
	font_size: int = 16
) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = create_panel_style(accent_color, COLOR_INK_CHARCOAL, PANEL_OPACITY_SEMI, CORNER_RADIUS_SMALL)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.text = text
	style_label(label, accent_color, font_size)
	panel.add_child(label)

	return panel

## ═══════════════════════════════════════════════════════════════════════════════
## PROGRESS BAR STYLING
## ═══════════════════════════════════════════════════════════════════════════════

## Create styled progress bar backgrounds and fills
func create_progress_bar_styles(
	fill_color: Color = COLOR_PLASMA_TEAL,
	bg_color: Color = COLOR_INK_CHARCOAL
) -> Dictionary:
	# Background
	var background = StyleBoxFlat.new()
	background.bg_color = bg_color
	background.corner_radius_top_left = CORNER_RADIUS_SMALL
	background.corner_radius_top_right = CORNER_RADIUS_SMALL
	background.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	background.corner_radius_bottom_right = CORNER_RADIUS_SMALL

	# Fill with neon glow
	var fill = StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left = CORNER_RADIUS_SMALL
	fill.corner_radius_top_right = CORNER_RADIUS_SMALL
	fill.corner_radius_bottom_left = CORNER_RADIUS_SMALL
	fill.corner_radius_bottom_right = CORNER_RADIUS_SMALL
	fill.shadow_color = Color(fill_color.r, fill_color.g, fill_color.b, 0.6)
	fill.shadow_size = SHADOW_SIZE_SMALL

	return {
		"background": background,
		"fill": fill
	}

## Apply progress bar styles to a ProgressBar node
func style_progress_bar(
	progress_bar: ProgressBar,
	fill_color: Color = COLOR_PLASMA_TEAL
) -> void:
	var styles = create_progress_bar_styles(fill_color)
	progress_bar.add_theme_stylebox_override("background", styles.background)
	progress_bar.add_theme_stylebox_override("fill", styles.fill)

## ═══════════════════════════════════════════════════════════════════════════════
## ANIMATION HELPERS
## ═══════════════════════════════════════════════════════════════════════════════

## Create an elastic bounce tween for button highlights
func create_bounce_tween(node: Node, target: Node, property: String, target_value: Variant, duration: float = 0.3) -> Tween:
	var tween = node.create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(target, property, target_value, duration)
	return tween

## Create a pulsing glow animation
func create_pulse_tween(node: Node, target: Node, property: String, min_value: Variant, max_value: Variant, duration: float = 1.5) -> Tween:
	var tween = node.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_loops()
	tween.tween_property(target, property, max_value, duration / 2.0)
	tween.tween_property(target, property, min_value, duration / 2.0)
	return tween

## ═══════════════════════════════════════════════════════════════════════════════
## UTILITY FUNCTIONS
## ═══════════════════════════════════════════════════════════════════════════════

## Get a random neon accent color
func get_random_accent() -> Color:
	var accents = [COLOR_ELECTRIC_LIME, COLOR_BUBBLE_MAGENTA, COLOR_SKY_CYAN, COLOR_CITRUS_YELLOW, COLOR_PLASMA_TEAL, COLOR_GRAPE_VIOLET]
	return accents[randi() % accents.size()]

## Get color for semantic meaning
func get_semantic_color(semantic: String) -> Color:
	match semantic:
		"primary", "info": return COLOR_SKY_CYAN
		"success", "confirm": return COLOR_ELECTRIC_LIME
		"warning", "important": return COLOR_BUBBLE_MAGENTA
		"attention", "highlight": return COLOR_CITRUS_YELLOW
		"active", "progress": return COLOR_PLASMA_TEAL
		"special", "rare": return COLOR_GRAPE_VIOLET
		_: return COLOR_MILK_WHITE
