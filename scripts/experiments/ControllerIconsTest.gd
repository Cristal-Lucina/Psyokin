extends Control

# Controller Icons Test Scene - Complete Collection
# Showcases all 51 controller button icons organized by platform

# Theme management
var current_theme = "Light"  # "Light" or "Dark"
var light_bg_color = Color(0.15, 0.15, 0.2, 1)  # Dark background for light icons
var dark_bg_color = Color(0.95, 0.95, 0.97, 1)  # Light background for dark icons
var icon_base_path_light = "res://assets/graphics/icons/UI/PNG and PSD - Light/Controller/1x/"
var icon_base_path_dark = "res://assets/graphics/icons/UI/PNG and PSD - Dark/Controller/1x/"
var icon_base_path = icon_base_path_light

# Icon definitions organized by controller type
var controller_icons = {
	"Xbox": {
		"Face": [
			{"id": 13, "name": "A", "asset": "Asset 82.png"},
			{"id": 12, "name": "B", "asset": "Asset 81.png"},
			{"id": 10, "name": "X", "asset": "Asset 79.png"},
			{"id": 11, "name": "Y", "asset": "Asset 80.png"},
		],
		"Shoulders": [
			{"id": 21, "name": "LB", "asset": "Asset 98.png"},
			{"id": 20, "name": "RB", "asset": "Asset 97.png"},
			{"id": 19, "name": "LT", "asset": "Asset 96.png"},
			{"id": 18, "name": "RT", "asset": "Asset 95.png"},
		],
		"D-Pad": [
			{"id": 17, "name": "Up", "asset": "Asset 71.png"},
			{"id": 15, "name": "Down", "asset": "Asset 69.png"},
			{"id": 14, "name": "Left", "asset": "Asset 68.png"},
			{"id": 16, "name": "Right", "asset": "Asset 70.png"},
		],
	},
	"PlayStation": {
		"Face": [
			{"id": 25, "name": "Cross", "asset": "Asset 86.png"},
			{"id": 22, "name": "Circle", "asset": "Asset 83.png"},
			{"id": 24, "name": "Square", "asset": "Asset 85.png"},
			{"id": 23, "name": "Triangle", "asset": "Asset 84.png"},
		],
		"Shoulders": [
			{"id": 33, "name": "L1", "asset": "Asset 94.png"},
			{"id": 32, "name": "R1", "asset": "Asset 93.png"},
			{"id": 31, "name": "L2", "asset": "Asset 92.png"},
			{"id": 30, "name": "R2", "asset": "Asset 91.png"},
		],
		"D-Pad": [
			{"id": 29, "name": "Up", "asset": "Asset 75.png"},
			{"id": 28, "name": "Down", "asset": "Asset 74.png"},
			{"id": 26, "name": "Left", "asset": "Asset 72.png"},
			{"id": 27, "name": "Right", "asset": "Asset 73.png"},
		],
		"Special": [
			{"id": 2, "name": "Share", "asset": "Asset 50.png"},
			{"id": 3, "name": "Options", "asset": "Asset 51.png"},
		],
	},
	"Nintendo": {
		"Face": [
			{"id": 12, "name": "B", "asset": "Asset 81.png"},
			{"id": 13, "name": "A", "asset": "Asset 82.png"},
			{"id": 11, "name": "Y", "asset": "Asset 80.png"},
			{"id": 10, "name": "X", "asset": "Asset 79.png"},
		],
		"Shoulders": [
			{"id": 21, "name": "LB", "asset": "Asset 98.png"},
			{"id": 20, "name": "RB", "asset": "Asset 97.png"},
			{"id": 19, "name": "LT", "asset": "Asset 96.png"},
			{"id": 18, "name": "RT", "asset": "Asset 95.png"},
		],
		"D-Pad": [
			{"id": 37, "name": "Up", "asset": "Asset 67.png"},
			{"id": 36, "name": "Down", "asset": "Asset 66.png"},
			{"id": 34, "name": "Left", "asset": "Asset 64.png"},
			{"id": 35, "name": "Right", "asset": "Asset 65.png"},
		],
		"Special": [
			{"id": 99, "name": "+ Button", "asset": "Asset 99.svg"},
			{"id": 100, "name": "- Button", "asset": "Asset 100.svg"},
		],
	},
	"Universal": {
		"Analog Sticks": [
			{"id": 7, "name": "Left Stick", "asset": "Asset 90.png"},
			{"id": 6, "name": "Right Stick", "asset": "Asset 89.png"},
			{"id": 5, "name": "L3", "asset": "Asset 88.png"},
			{"id": 4, "name": "R3", "asset": "Asset 87.png"},
		],
		"Left Stick Dir": [
			{"id": 49, "name": "Up", "asset": "Asset 62.png"},
			{"id": 50, "name": "Down", "asset": "Asset 63.png"},
			{"id": 47, "name": "Left", "asset": "Asset 60.png"},
			{"id": 48, "name": "Right", "asset": "Asset 61.png"},
		],
		"Right Stick Dir": [
			{"id": 45, "name": "Up", "asset": "Asset 58.png"},
			{"id": 46, "name": "Down", "asset": "Asset 59.png"},
			{"id": 43, "name": "Left", "asset": "Asset 56.png"},
			{"id": 44, "name": "Right", "asset": "Asset 57.png"},
		],
		"Generic Dir": [
			{"id": 38, "name": "Up", "asset": "Asset 52.png"},
			{"id": 41, "name": "Down", "asset": "Asset 55.png"},
			{"id": 39, "name": "Left", "asset": "Asset 53.png"},
			{"id": 40, "name": "Right", "asset": "Asset 54.png"},
			{"id": 42, "name": "D-Pad Any", "asset": "Asset 76.png"},
		],
	},
}

func _ready():
	print("=== Controller Icons Test - Complete Collection ===")
	print("Loading 51 controller button icons...")

	# Set initial theme (dark background for light icons)
	_apply_theme()
	_build_icon_display()
	_print_icon_summary()

func _on_theme_toggle():
	"""Toggle between light and dark themes"""
	if current_theme == "Light":
		current_theme = "Dark"
		icon_base_path = icon_base_path_dark
		$"MarginContainer/MainVBox/Header/ThemeToggle".text = "Switch to Light Theme"
	else:
		current_theme = "Light"
		icon_base_path = icon_base_path_light
		$"MarginContainer/MainVBox/Header/ThemeToggle".text = "Switch to Dark Theme"

	_apply_theme()
	_rebuild_display()
	print("Switched to %s theme" % current_theme)

func _apply_theme():
	"""Apply the current theme colors"""
	var bg_panel = $BackgroundPanel
	var title_label = $MarginContainer/MainVBox/Title
	var footer_types = $"MarginContainer/MainVBox/Footer/ControllerTypes"
	var footer_info = $"MarginContainer/MainVBox/Footer/Info"

	if current_theme == "Light":
		# Dark background for light icons
		bg_panel.color = light_bg_color
		title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
		footer_types.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1))
		footer_info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 1))
	else:
		# Light background for dark icons
		bg_panel.color = dark_bg_color
		title_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15, 1))
		footer_types.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25, 1))
		footer_info.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45, 1))

func _rebuild_display():
	"""Rebuild the icon display with new theme"""
	_build_icon_display()

func _build_icon_display():
	"""Dynamically build the icon display grid"""
	var grid = $MarginContainer/MainVBox/ScrollContainer/ContentGrid

	# Clear any existing children
	for child in grid.get_children():
		child.queue_free()

	# Build icons organized by controller type
	for controller_type in ["Xbox", "PlayStation", "Nintendo", "Universal"]:
		# Add controller type header
		var type_label = Label.new()
		type_label.text = controller_type
		type_label.add_theme_font_size_override("font_size", 20)

		# Apply theme-appropriate color
		if current_theme == "Light":
			type_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
		else:
			type_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15, 1))

		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_label.custom_minimum_size = Vector2(600, 40)
		grid.add_child(type_label)

		# Add empty spacers to fill the row
		for i in range(7):
			var spacer = Control.new()
			grid.add_child(spacer)

		# Add icons for this controller type
		var type_data = controller_icons[controller_type]
		for category_name in type_data.keys():
			# Add category label
			var cat_label = Label.new()
			cat_label.text = category_name + ":"
			cat_label.add_theme_font_size_override("font_size", 14)

			# Apply theme-appropriate color
			if current_theme == "Light":
				cat_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
			else:
				cat_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.35, 1))

			cat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cat_label.custom_minimum_size = Vector2(120, 80)
			grid.add_child(cat_label)

			# Add icons in this category
			for icon_data in type_data[category_name]:
				var icon_box = _create_icon_box(icon_data)
				grid.add_child(icon_box)

			# Fill remaining cells in row
			var icons_in_row = type_data[category_name].size()
			var spacers_needed = (8 - ((icons_in_row + 1) % 8)) % 8
			for i in range(spacers_needed):
				var spacer = Control.new()
				grid.add_child(spacer)

func _create_icon_box(icon_data: Dictionary) -> VBoxContainer:
	"""Create a display box for an icon"""
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(70, 80)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# Create texture rect for the icon
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(48, 48)
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Load the texture - remap asset numbers for dark theme
	var asset_name = icon_data["asset"]

	# Dark theme: Assets 1-49 = Light theme Assets 50-98
	# Special handling: Assets 99-100 (Nintendo +/-) exist in both themes
	if current_theme == "Dark" and not asset_name.begins_with("Asset 99") and not asset_name.begins_with("Asset 100"):
		# Extract the asset number and subtract 49
		var asset_num = int(asset_name.replace("Asset ", "").replace(".png", ""))
		if asset_num >= 50 and asset_num <= 98:
			asset_name = "Asset " + str(asset_num - 49) + ".png"

	var texture_path = icon_base_path + asset_name
	if ResourceLoader.exists(texture_path):
		tex_rect.texture = load(texture_path)
	else:
		print("Warning: Icon not found at " + texture_path)

	vbox.add_child(tex_rect)

	# Create label for the icon name
	var label = Label.new()
	label.text = icon_data["name"]
	label.add_theme_font_size_override("font_size", 11)

	# Apply theme-appropriate color
	if current_theme == "Light":
		label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1))
	else:
		label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25, 1))

	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	return vbox

func _print_icon_summary():
	"""Print summary of loaded icons"""
	var total_icons = 0
	for controller_type in controller_icons.keys():
		var type_count = 0
		for category in controller_icons[controller_type].keys():
			type_count += controller_icons[controller_type][category].size()
		print("  %s: %d icons" % [controller_type, type_count])
		total_icons += type_count

	print("\nTotal: %d controller icons loaded" % total_icons)
	print("=========================================\n")

func _on_back_pressed():
	"""Handle back button press"""
	print("Returning to main menu...")

	# Try to go to main menu or character creator
	if ResourceLoader.exists("res://scenes/main_menu/MainMenu.tscn"):
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")
	elif ResourceLoader.exists("res://scenes/main/Main.tscn"):
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	else:
		print("No main menu scene found - staying in test scene")

func _input(event):
	"""Handle keyboard input for quick navigation"""
	if event is InputEventKey and event.pressed:
		# Press ESC or Q to go back
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_Q:
			_on_back_pressed()
