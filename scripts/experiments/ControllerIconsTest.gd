extends Control

# Controller Icons Test Scene
# Showcases all 27 individual controller button icons

func _ready():
	print("Controller Icons Test loaded - displaying all 27 icons")
	_print_icon_info()

func _print_icon_info():
	"""Print information about all loaded icons"""
	print("\n=== Controller Button Icons ===")
	print("Total Icons: 27")
	print("\nCategories:")
	print("  - Shoulder Buttons: 8 (LB, RB, LT, RT, L1, R1, L2, R2)")
	print("  - Face Buttons: 4 (X, Circle, Square, Triangle)")
	print("  - D-Pad: 4 (Up, Down, Left, Right)")
	print("  - Analog Sticks: 4 (L Stick, R Stick, L3, R3)")
	print("  - Special Buttons: 3 (Option, Share, Touchpad)")
	print("  - Trigger Indicators: 4 (L/R Trigger Up/Down)")
	print("\nAll icons are SVG format with transparent backgrounds")
	print("===============================\n")

func _on_back_pressed():
	"""Handle back button press"""
	print("Returning to main menu...")
	# You can change this to go wherever you want
	# For now, we'll just try to go back to the character creator or main menu
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
