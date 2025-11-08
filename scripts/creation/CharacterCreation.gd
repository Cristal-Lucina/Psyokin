extends Control
class_name CharacterCreation

signal creation_applied

# Cinematic stages
enum CinematicStage {
	OPENING_DIALOGUE_1,    # "Oh, I think they are regaining consciousness.."
	OPENING_DIALOGUE_2,    # "Check if they are aware."
	OPENING_DIALOGUE_3,    # "Hey, do you remember your name?"
	NAME_INPUT,            # Name input with validation
	DIALOGUE_RESPONSE_1,   # "They're speaking..."
	DIALOGUE_RESPONSE_2,   # "Nurse, go check..."
	STAT_SELECTION,        # Choose 3 stats
	PERK_QUESTION,         # "Choose a perk."
	PERK_SELECTION,        # Show 3 perks based on stats
	NURSE_RESPONSES,       # Nurse responses based on picks
	DIALOGUE_BANDAGES,     # "Ok, I think we can remove the bandages now."
	DIALOGUE_MEMORY,       # "Let's check your memory."
	DIALOGUE_MIRROR,       # "Do you recognize the person in the mirror?"
	CHARACTER_CUSTOMIZATION, # Pronoun, body, outfit, hair, hat
	FINAL_CONFIRMATION,    # "Does everything seem correct?"
	COMPLETE               # End of cinematic
}

# Styling constants (matching LoadoutPanel)
const PANEL_BG_COLOR := Color(0.15, 0.15, 0.15, 1.0)  # Dark gray, fully opaque
const PANEL_BORDER_COLOR := Color(1.0, 0.7, 0.75, 1.0)  # Pink border
const PANEL_BORDER_WIDTH := 2
const PANEL_CORNER_RADIUS := 8

# Cinematic constants
const LETTER_REVEAL_SPEED := 0.05  # 0.05 seconds per letter
const DIALOGUE_PAUSE := 1.5        # Pause between dialogue lines
const NURSE_RESPONSE_PAUSE := 2.0  # Pause between nurse responses

# ── Autoload paths ────────────────────────────────────────────────────────────
const GS_PATH      := "/root/aGameState"
const STATS_PATH   := "/root/aStatsSystem"
const PERK_PATH    := "/root/aPerkSystem"
const CPS_PATH     := "/root/aCombatProfileSystem"
const ROUTER_PATH  := "/root/aSceneRouter"

# Character directories
const CHAR_BASE_PATH = "res://assets/graphics/characters/"
const CHAR_VARIANTS = ["char_a_p1"]

# Layer configuration
const LAYERS = {
	"base": {"code": "0bas", "node_name": "BaseSprite", "path": ""},
	"outfit": {"code": "1out", "node_name": "OutfitSprite", "path": "1out"},
	"cloak": {"code": "2clo", "node_name": "CloakSprite", "path": "2clo"},
	"face": {"code": "3fac", "node_name": "FaceSprite", "path": "3fac"},
	"hair": {"code": "4har", "node_name": "HairSprite", "path": "4har"},
	"hat": {"code": "5hat", "node_name": "HatSprite", "path": "5hat"},
	"tool_a": {"code": "6tla", "node_name": "ToolASprite", "path": "6tla"},
	"tool_b": {"code": "7tlb", "node_name": "ToolBSprite", "path": "7tlb"}
}

# Direction mapping
const DIRECTIONS = {
	0: "South",
	1: "North",
	2: "East",
	3: "West"
}

# ── UI: unique_name_in_owner nodes from your scene ───────────────────────────
@onready var _name_in     : LineEdit      = %NameInput
@onready var _surname_in  : LineEdit      = %SurnameInput
@onready var _pron_in     : OptionButton  = %PronounInput

@onready var _body_in     : OptionButton  = %BodyIdInput
@onready var _outfit_in   : OptionButton  = %OutfitInput
@onready var _hair_in     : OptionButton  = %HairIdInput
@onready var _hat_in      : OptionButton  = %HatInput

@onready var _brw_cb      : CheckButton   = %StatBRW
@onready var _vtl_cb      : CheckButton   = %StatVTL
@onready var _tpo_cb      : CheckButton   = %StatTPO
@onready var _mnd_cb      : CheckButton   = %StatMND
@onready var _fcs_cb      : CheckButton   = %StatFCS

@onready var _perk_in     : OptionButton  = %PerkInput
@onready var _confirm_btn : Button        = %ConfirmBtn
@onready var _cancel_btn  : Button        = %CancelBtn

# Character preview
@onready var character_layers = $Margin/MainContainer/PreviewPanel/PreviewMargin/PreviewContainer/CenterContainer/CharacterLayers
@onready var frame_label = $Margin/MainContainer/PreviewPanel/PreviewMargin/PreviewContainer/AnimationControls/FrameLabel
@onready var direction_label = $Margin/MainContainer/PreviewPanel/PreviewMargin/PreviewContainer/AnimationControls/DirectionLabel

# ── state ────────────────────────────────────────────────────────────────────
var _selected_order : Array[String] = []       # keep order of picks (max 3)
var _perk_id_by_idx : Dictionary = {}          # index -> perk_id
var _perk_stat_by_idx : Dictionary = {}        # index -> stat_id (help text)

# Character state
var current_direction = 0  # South
var current_frame = 0
var available_parts = {}
var current_selections = {}
var selected_variants = {}  # Track variant codes for connecting animations

# Walk animation
var animation_timer = 0.0
var animation_speed = 0.135  # 135ms per frame for walk

# Cinematic state
var current_stage: CinematicStage = CinematicStage.OPENING_DIALOGUE_1
var cinematic_active: bool = true
var typing_active: bool = false
var typing_timer: float = 0.0
var typing_text: String = ""
var typing_index: int = 0
var typing_target_label: Label = null
var stage_timer: float = 0.0
var nurse_response_index: int = 0
var cinematic_name: String = ""
var cinematic_surname: String = ""
var waiting_for_input: bool = false

# Name input state
var name_input_stage: int = 0  # 0 = selecting first name field, 1 = first name keyboard, 2 = selecting last name field, 3 = last name keyboard
var keyboard_container: Control = null
var current_name_text: String = ""
var first_name_label: Label = null
var last_name_label: Label = null

# Stat selection state
var stat_focused_index: int = 0  # Which stat is currently focused (0-4 for stats, 5 for Continue button)
var stat_selected: Array[bool] = [false, false, false, false, false]  # Which stats are selected
var stat_panels: Array = []  # References to stat panel containers
var stat_continue_button: Button = null  # Reference to Continue button

# Keyboard navigation state
var keyboard_buttons: Array = []  # All keyboard buttons
var keyboard_focused_row: int = 0  # Current row (0-3: letters, 4: actions)
var keyboard_focused_col: int = 0  # Current column
var keyboard_grid_cols: int = 9  # 9 columns for letters

# Blinking up arrow
var arrow_label: Label = null
var cursor_blink_timer: float = 0.0
var cursor_visible: bool = true
const CURSOR_BLINK_SPEED := 0.5  # Blink every 0.5 seconds

# Cinematic UI references (will be created dynamically)
var cinematic_layer: CanvasLayer = null
var dialogue_label: Label = null
var name_input_container: Control = null
var stat_selection_container: Control = null
var perk_selection_container: Control = null
var customization_container: Control = null
var confirmation_container: Control = null
var continue_prompt: Label = null

# ── ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	print("Character Creation starting with cinematic opening...")

	# Apply LoadoutPanel styling to all panels
	_style_panels()

	scan_character_assets()
	_fill_basics()
	_wire_stat_toggles()
	_rebuild_perk_dropdown() # starts empty until picks

	# Hide/disable back button completely (keeps scene compatible)
	if _cancel_btn:
		_cancel_btn.hide()
		_cancel_btn.disabled = true
		_cancel_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Perk selection change → update gating
	if _perk_in and not _perk_in.item_selected.is_connected(_on_perk_selected):
		_perk_in.item_selected.connect(_on_perk_selected)

	if _confirm_btn and not _confirm_btn.pressed.is_connected(_on_confirm_pressed):
		_confirm_btn.pressed.connect(_on_confirm_pressed)

	# Wire character part selectors
	if _body_in and not _body_in.item_selected.is_connected(_on_body_selected):
		_body_in.item_selected.connect(_on_body_selected)
	if _outfit_in and not _outfit_in.item_selected.is_connected(_on_outfit_selected):
		_outfit_in.item_selected.connect(_on_outfit_selected)
	if _hair_in and not _hair_in.item_selected.is_connected(_on_hair_selected):
		_hair_in.item_selected.connect(_on_hair_selected)
	if _hat_in and not _hat_in.item_selected.is_connected(_on_hat_selected):
		_hat_in.item_selected.connect(_on_hat_selected)

	set_default_character()
	update_preview()
	_update_confirm_enabled()

	# Initialize cinematic opening
	_setup_cinematic()
	_hide_form()  # Hide the form initially - only shows if player says "No" at end

func _style_panels() -> void:
	"""Apply LoadoutPanel styling (dark gray background with pink border) to all panels"""
	var panels_to_style = [
		get_node_or_null("Margin/MainContainer/PreviewPanel"),
		get_node_or_null("Margin/MainContainer/FormPanel")
	]

	for panel in panels_to_style:
		if panel is PanelContainer:
			var style_box := StyleBoxFlat.new()
			style_box.bg_color = PANEL_BG_COLOR
			style_box.border_color = PANEL_BORDER_COLOR
			style_box.border_width_left = PANEL_BORDER_WIDTH
			style_box.border_width_right = PANEL_BORDER_WIDTH
			style_box.border_width_top = PANEL_BORDER_WIDTH
			style_box.border_width_bottom = PANEL_BORDER_WIDTH
			style_box.corner_radius_top_left = PANEL_CORNER_RADIUS
			style_box.corner_radius_top_right = PANEL_CORNER_RADIUS
			style_box.corner_radius_bottom_left = PANEL_CORNER_RADIUS
			style_box.corner_radius_bottom_right = PANEL_CORNER_RADIUS
			panel.add_theme_stylebox_override("panel", style_box)

			# Add 50px padding inside panels
			panel.add_theme_constant_override("margin_left", 50)
			panel.add_theme_constant_override("margin_top", 50)
			panel.add_theme_constant_override("margin_right", 50)
			panel.add_theme_constant_override("margin_bottom", 50)

	# Apply font size hierarchy (matching LoadoutPanel)
	_apply_font_sizes()

func _apply_font_sizes() -> void:
	"""Apply LoadoutPanel-style font size hierarchy"""
	# Titles: 16px (like LoadoutPanel section headers)
	var title_nodes = [
		get_node_or_null("Margin/MainContainer/PreviewPanel/PreviewContainer/Title"),
		get_node_or_null("Margin/MainContainer/FormPanel/Form/Title")
	]
	for node in title_nodes:
		if node is Label:
			node.add_theme_font_size_override("font_size", 16)

	# Section labels and important text: 12px
	var label_nodes = [
		get_node_or_null("Margin/MainContainer/FormPanel/Form/ScrollContainer/Grid/NameLable"),
		get_node_or_null("Margin/MainContainer/FormPanel/Form/ScrollContainer/Grid/SurnameLabel"),
		get_node_or_null("Margin/MainContainer/FormPanel/Form/ScrollContainer/Grid/PronounLabel"),
		get_node_or_null("Margin/MainContainer/FormPanel/Form/ScrollContainer/Grid/BodyLabel"),
		get_node_or_null("Margin/MainContainer/FormPanel/Form/ScrollContainer/Grid/OutfitLabel"),
		get_node_or_null("Margin/MainContainer/FormPanel/Form/ScrollContainer/Grid/HairLabel"),
		get_node_or_null("Margin/MainContainer/FormPanel/Form/ScrollContainer/Grid/HatLabel"),
		get_node_or_null("Margin/MainContainer/FormPanel/Form/StatsLabel"),
		get_node_or_null("Margin/MainContainer/FormPanel/Form/PerkLabel")
	]
	for node in label_nodes:
		if node is Label:
			node.add_theme_font_size_override("font_size", 12)

	# Small text and animation info: 10px (already the default, but set explicitly)
	var small_nodes = [
		get_node_or_null("Margin/MainContainer/PreviewPanel/PreviewContainer/AnimationControls/DirectionLabel"),
		get_node_or_null("Margin/MainContainer/PreviewPanel/PreviewContainer/AnimationControls/FrameLabel")
	]
	for node in small_nodes:
		if node is Label:
			node.add_theme_font_size_override("font_size", 10)

func _process(delta):
	# Walk animation cycling (6 frames)
	animation_timer += delta
	if animation_timer >= animation_speed:
		animation_timer = 0.0
		current_frame = (current_frame + 1) % 6  # Walk has 6 frames (0-5)
		update_frame_display()

	# Handle cinematic typing effect and stage transitions
	if cinematic_active:
		_process_cinematic(delta)

# ── Character Asset Scanning ─────────────────────────────────────────────────
func scan_character_assets():
	"""Scan the character assets folder to find all available parts"""
	print("Scanning character assets...")

	for variant in CHAR_VARIANTS:
		var variant_path = CHAR_BASE_PATH + variant + "/"
		var dir = DirAccess.open(variant_path)

		if dir == null:
			print("Could not open directory: ", variant_path)
			continue

		# Scan each layer
		for layer_key in LAYERS:
			var layer = LAYERS[layer_key]
			var layer_path = variant_path + layer.path

			if layer_key not in available_parts:
				available_parts[layer_key] = []

			# For base layer, files are directly in variant folder
			if layer.path == "":
				dir.list_dir_begin()
				var file_name = dir.get_next()
				while file_name != "":
					if file_name.ends_with(".png") and layer.code in file_name:
						var full_path = variant_path + file_name
						var variant_code = extract_variant_code(file_name.get_basename())
						available_parts[layer_key].append({
							"name": file_name.get_basename(),
							"path": full_path,
							"variant": variant_code
						})
					file_name = dir.get_next()
				dir.list_dir_end()
			else:
				# For other layers, check subdirectory
				var subdir = DirAccess.open(layer_path)
				if subdir:
					subdir.list_dir_begin()
					var file_name = subdir.get_next()
					while file_name != "":
						if file_name.ends_with(".png"):
							var full_path = layer_path + "/" + file_name
							var variant_code = extract_variant_code(file_name.get_basename())
							available_parts[layer_key].append({
								"name": file_name.get_basename(),
								"path": full_path,
								"variant": variant_code
							})
						file_name = subdir.get_next()
					subdir.list_dir_end()

	print("Asset scan complete. Found:")
	for layer_key in available_parts:
		print("  ", layer_key, ": ", available_parts[layer_key].size(), " items")

func extract_variant_code(filename: String) -> String:
	"""Extract the variant code from filename
	Example: 'char_a_p1_0bas_humn_v06' -> 'humn_v06'
	Example: 'char_a_p1_4har_bob1_v05' -> 'bob1_v05'
	"""
	# Split by underscores
	var parts = filename.split("_")

	# Find the part that contains the item code and variant
	# Format is usually: char_a_p1_LAYER_ITEM_VARIANT
	# We want the last two parts (ITEM_VARIANT)
	if parts.size() >= 2:
		var item_code = parts[parts.size() - 2]
		var variant_code = parts[parts.size() - 1]
		return item_code + "_" + variant_code

	return ""

func set_default_character():
	"""Set up a default character with base body"""
	if "base" in available_parts and available_parts["base"].size() > 0:
		_on_part_selected("base", available_parts["base"][0])

func _on_part_selected(layer_key: String, part):
	"""Handle part selection"""
	current_selections[layer_key] = part
	if part != null:
		selected_variants[layer_key] = part.variant
		print("Selected ", layer_key, ": variant = ", part.variant)
	else:
		selected_variants.erase(layer_key)
	update_preview()

func update_preview():
	"""Update the character preview with current selections"""
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite = character_layers.get_node(layer.node_name)

		if layer_key in current_selections and current_selections[layer_key] != null:
			var part = current_selections[layer_key]
			var texture = load(part.path)
			sprite.texture = texture
			sprite.visible = true
		else:
			sprite.texture = null
			sprite.visible = false

	update_frame_display()

func update_frame_display():
	"""Update the frame and direction display"""
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite = character_layers.get_node(layer.node_name)
		if sprite.visible and sprite.texture:
			# Walk animation is on rows 5-8 (direction + 4)
			var walk_row = current_direction + 4
			sprite.frame = walk_row * 8 + current_frame

	frame_label.text = "Walk Frame: " + str(current_frame + 1) + "/6"
	direction_label.text = "Direction: " + DIRECTIONS[current_direction]

# ── Character Part Selection Callbacks ───────────────────────────────────────
func _on_body_selected(idx: int):
	if idx == 0:  # "None" option
		_on_part_selected("base", null)
	elif "base" in available_parts and idx - 1 < available_parts["base"].size():
		_on_part_selected("base", available_parts["base"][idx - 1])

func _on_outfit_selected(idx: int):
	if idx == 0:  # "None" option
		_on_part_selected("outfit", null)
	elif "outfit" in available_parts and idx - 1 < available_parts["outfit"].size():
		_on_part_selected("outfit", available_parts["outfit"][idx - 1])

func _on_hair_selected(idx: int):
	if idx == 0:  # "None" option
		_on_part_selected("hair", null)
	elif "hair" in available_parts and idx - 1 < available_parts["hair"].size():
		_on_part_selected("hair", available_parts["hair"][idx - 1])

func _on_hat_selected(idx: int):
	if idx == 0:  # "None" option
		_on_part_selected("hat", null)
	elif "hat" in available_parts and idx - 1 < available_parts["hat"].size():
		_on_part_selected("hat", available_parts["hat"][idx - 1])

# ── UI fill / wiring ─────────────────────────────────────────────────────────
func _fill_basics() -> void:
	# Name fields: max 8 characters each
	if _name_in:
		_name_in.max_length = 8
		_name_in.placeholder_text = "First Name"
	if _surname_in:
		_surname_in.max_length = 8
		_surname_in.placeholder_text = "Last Name"

	# Pronouns
	if _pron_in and _pron_in.item_count == 0:
		for p in ["they", "she", "he"]:
			_pron_in.add_item(p)
		_pron_in.select(0)

	# Fill character part dropdowns
	_fill_part_dropdown(_body_in, "base")
	_fill_part_dropdown(_outfit_in, "outfit")
	_fill_part_dropdown(_hair_in, "hair")
	_fill_part_dropdown(_hat_in, "hat")

func _fill_part_dropdown(ob: OptionButton, layer_key: String) -> void:
	if ob == null: return
	if ob.item_count > 0: return

	# Add "None" option
	ob.add_item("None")

	# Add available parts
	if layer_key in available_parts:
		for part in available_parts[layer_key]:
			ob.add_item(part.name)

	ob.select(0)

func _wire_stat_toggles() -> void:
	_wire_stat_toggle(_brw_cb, "BRW")
	_wire_stat_toggle(_vtl_cb, "VTL")
	_wire_stat_toggle(_tpo_cb, "TPO")
	_wire_stat_toggle(_mnd_cb, "MND")
	_wire_stat_toggle(_fcs_cb, "FCS")

func _wire_stat_toggle(btn: CheckButton, stat_id: String) -> void:
	if btn and not btn.toggled.is_connected(_on_stat_toggled):
		btn.toggled.connect(_on_stat_toggled.bind(stat_id, btn))

func _on_stat_toggled(pressed: bool, stat_id: String, btn: CheckButton) -> void:
	if pressed:
		if not _selected_order.has(stat_id):
			_selected_order.append(stat_id)
		if _selected_order.size() > 3:
			# too many – undo this one
			_selected_order.erase(stat_id)
			btn.set_pressed_no_signal(false)
	else:
		_selected_order.erase(stat_id)

	_rebuild_perk_dropdown()
	_update_confirm_enabled()

# ── perks (based on selected stats; only T1 options) ─────────────────────────
func _rebuild_perk_dropdown() -> void:
	if _perk_in == null:
		return
	_perk_in.clear()
	_perk_id_by_idx.clear()
	_perk_stat_by_idx.clear()

	# Build the offer list
	var picks: Array[String] = []
	for i in range(_selected_order.size()):
		picks.append(String(_selected_order[i]))
	var offers: Array = []

	var perk: Node = get_node_or_null(PERK_PATH)
	if perk and perk.has_method("get_starting_options"):
		var v: Variant = perk.call("get_starting_options", picks)
		if typeof(v) == TYPE_ARRAY:
			offers = v as Array
	elif picks.size() > 0:
		# Fallback: synthesize simple placeholder perks
		for i2 in range(picks.size()):
			var s2: String = picks[i2]
			offers.append({
				"stat": s2,
				"tier": 0,
				"id": "%s_t1" % s2.to_lower(),
				"name": "%s T1" % s2,
				"desc": "Tier-1 perk for %s." % s2
			})

	# Fill the dropdown
	_perk_in.add_item("— choose starting perk —")
	_perk_id_by_idx[0] = ""
	_perk_stat_by_idx[0] = ""

	var idx: int = 1
	for j in range(offers.size()):
		var it_v: Variant = offers[j]
		if typeof(it_v) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_v
		var line: String = "%s — %s" % [
			String(it.get("stat","")),
			String(it.get("name","Perk"))
		]
		_perk_in.add_item(line)
		_perk_id_by_idx[idx] = String(it.get("id",""))
		_perk_stat_by_idx[idx] = String(it.get("stat",""))
		idx += 1

	_perk_in.select(0)


func _on_perk_selected(_index: int) -> void:
	_update_confirm_enabled()

# ── confirm ──────────────────────────────────────────────────────────────────
func _on_confirm_pressed() -> void:
	# Validate name and surname are filled
	var name_text: String = (_name_in.text if _name_in else "").strip_edges()
	var surname_text: String = (_surname_in.text if _surname_in else "").strip_edges()

	if name_text == "" or surname_text == "":
		OS.alert("Please enter both a first name and last name.", "Character Creation")
		return

	# Hard gate: must have exactly 3 stats + a chosen perk
	if _selected_order.size() != 3 or _chosen_perk_id() == "":
		OS.alert("Pick 3 stats and 1 perk to continue.", "Character Creation")
		return

	# Validate at least base body is selected
	if "base" not in selected_variants:
		OS.alert("Please select at least a body type.", "Character Creation")
		return

	var pron_text: String = _opt_text(_pron_in)

	# Save character variant data to CharacterData autoload
	print("[CharacterCreation] Saving character variants: ", selected_variants)
	aCharacterData.set_character(selected_variants, current_selections)

	var gs: Node = get_node_or_null(GS_PATH)
	if gs:
		# Store full name for display
		var full_name: String = "%s %s" % [name_text, surname_text]
		if gs.has_method("set"):
			gs.set("player_name", full_name)
		print("[CharacterCreation] Setting hero_identity meta with variants: ", selected_variants)
		gs.set_meta("hero_identity", {
			"name": name_text,
			"surname": surname_text,
			"pronoun": pron_text,
			"character_variants": selected_variants.duplicate()
		})
		print("[CharacterCreation] Saved to GameState successfully")
		var picked := PackedStringArray()
		for i in range(_selected_order.size()):
			picked.append(_selected_order[i])
		gs.set_meta("hero_picked_stats", picked)
		# ensure hero in party
		if gs.has_method("get"):
			var pv: Variant = gs.get("party")
			var arr: Array = []
			if typeof(pv) == TYPE_ARRAY:
				arr = pv as Array
			if arr.is_empty() and gs.has_method("set"):
				gs.set("party", ["hero"])
		# default mind type
		if not gs.has_meta("hero_active_type"):
			gs.set_meta("hero_active_type", "Omega")

	# apply +1 level to chosen stats
	var st: Node = get_node_or_null(STATS_PATH)
	if st and st.has_method("apply_creation_boosts"):
		var picks_arr: Array = []
		for i2 in range(_selected_order.size()):
			picks_arr.append(_selected_order[i2])
		st.call("apply_creation_boosts", picks_arr)

	# Update HP/MP to max after stat boosts (if VTL or FCS were chosen)
	if gs and st:
		var new_level: int = 1
		var new_vtl: int = 1
		var new_fcs: int = 1
		if st.has_method("get_member_level"):
			new_level = int(st.call("get_member_level", "hero"))
		if st.has_method("get_member_stat_level"):
			new_vtl = int(st.call("get_member_stat_level", "hero", "VTL"))
			new_fcs = int(st.call("get_member_stat_level", "hero", "FCS"))

		var new_hp_max: int = 150 + (max(1, new_vtl) * max(1, new_level) * 6)
		var new_mp_max: int = 20 + int(round(float(max(1, new_fcs)) * float(max(1, new_level)) * 1.5))
		if st.has_method("compute_max_hp"):
			new_hp_max = int(st.call("compute_max_hp", new_level, new_vtl))
		if st.has_method("compute_max_mp"):
			new_mp_max = int(st.call("compute_max_mp", new_level, new_fcs))

		# Update member_data to set HP/MP to new max
		if gs.has_method("get"):
			var member_data_v: Variant = gs.get("member_data")
			if typeof(member_data_v) == TYPE_DICTIONARY:
				var member_data: Dictionary = member_data_v
				if not member_data.has("hero"):
					member_data["hero"] = {}
				var hero_data: Dictionary = member_data["hero"]
				hero_data["hp"] = new_hp_max
				hero_data["mp"] = new_mp_max
				if not hero_data.has("buffs"):
					hero_data["buffs"] = []
				if not hero_data.has("debuffs"):
					hero_data["debuffs"] = []

	# unlock chosen starting perk
	var chosen_perk_id: String = _chosen_perk_id()
	if chosen_perk_id != "":
		var ps: Node = get_node_or_null(PERK_PATH)
		if ps:
			if ps.has_method("unlock_by_id"):
				ps.call("unlock_by_id", chosen_perk_id)
			elif ps.has_method("unlock"):
				var idx2: int = (_perk_in.get_selected() if _perk_in else 0)
				ps.call("unlock", String(_perk_stat_by_idx.get(idx2,"")), 0)

	# refresh combat profiles
	var cps: Node = get_node_or_null(CPS_PATH)
	if cps and cps.has_method("refresh_all"):
		cps.call("refresh_all")

	# Nudge dorms to recompute bestie/rival from all THREE selected stats
	var dorms := get_node_or_null("/root/aDormSystem")
	if dorms and dorms.has_method("recompute_now"):
		dorms.call("recompute_now")

	creation_applied.emit()

	# optional routing forward only (no back)
	var router: Node = get_node_or_null(ROUTER_PATH)
	if router and router.has_method("goto_main"):
		router.call("goto_main")

# ── gating helpers ───────────────────────────────────────────────────────────
func _chosen_perk_id() -> String:
	if _perk_in == null:
		return ""
	var sel: int = _perk_in.get_selected()
	return String(_perk_id_by_idx.get(sel, ""))

func _update_confirm_enabled() -> void:
	if _confirm_btn == null: return
	var ready_stats: bool = (_selected_order.size() == 3)
	var ready_perk: bool = (_chosen_perk_id() != "")
	_confirm_btn.disabled = not (ready_stats and ready_perk)

# ── small helpers ─────────────────────────────────────────────────────────────
func _opt_text(ob: OptionButton) -> String:
	if ob == null: return ""
	var i: int = ob.get_selected()
	if i < 0: i = 0
	return ob.get_item_text(i)

# ══════════════════════════════════════════════════════════════════════════════
# CINEMATIC OPENING SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

# ── Cinematic Setup ──────────────────────────────────────────────────────────
func _setup_cinematic() -> void:
	"""Initialize the cinematic layer and start the opening sequence"""
	# Create cinematic overlay
	cinematic_layer = CanvasLayer.new()
	cinematic_layer.layer = 100  # Render above everything
	add_child(cinematic_layer)

	# Create black background
	var bg = ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cinematic_layer.add_child(bg)

	# Create container for dialogue and arrow
	var dialogue_container = VBoxContainer.new()
	dialogue_container.set_anchors_preset(Control.PRESET_CENTER)
	dialogue_container.anchor_left = 0.5
	dialogue_container.anchor_top = 0.5
	dialogue_container.anchor_right = 0.5
	dialogue_container.anchor_bottom = 0.5
	dialogue_container.offset_left = -400
	dialogue_container.offset_right = 400
	dialogue_container.offset_top = -50
	dialogue_container.offset_bottom = 50
	dialogue_container.add_theme_constant_override("separation", 10)
	cinematic_layer.add_child(dialogue_container)

	# Create dialogue label (for typing text)
	dialogue_label = Label.new()
	dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.add_theme_font_size_override("font_size", 18)
	dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	dialogue_label.text = ""
	dialogue_container.add_child(dialogue_label)

	# Create up arrow label (below the dialogue)
	arrow_label = Label.new()
	arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_label.add_theme_font_size_override("font_size", 24)
	arrow_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.75, 1.0))
	arrow_label.text = "↑"
	arrow_label.visible = false
	dialogue_container.add_child(arrow_label)

	# Create continue prompt
	continue_prompt = Label.new()
	continue_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	continue_prompt.anchor_top = 1.0
	continue_prompt.anchor_bottom = 1.0
	continue_prompt.offset_top = -50
	continue_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	continue_prompt.add_theme_font_size_override("font_size", 12)
	continue_prompt.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	continue_prompt.text = "Press Accept or Enter to continue..."
	continue_prompt.visible = false
	cinematic_layer.add_child(continue_prompt)

	# Start first stage
	_enter_stage(CinematicStage.OPENING_DIALOGUE_1)

func _hide_form() -> void:
	"""Hide the standard character creation form"""
	var margin = get_node_or_null("Margin")
	if margin:
		margin.visible = false

func _show_form() -> void:
	"""Show the standard character creation form (fallback)"""
	var margin = get_node_or_null("Margin")
	if margin:
		margin.visible = true

# ── Typing Effect System ─────────────────────────────────────────────────────
func _start_typing(text: String, target_label: Label = null) -> void:
	"""Start typing effect for given text"""
	typing_active = true
	typing_text = text
	typing_index = 0
	typing_timer = 0.0
	typing_target_label = target_label if target_label else dialogue_label

	# Hide cursor when starting new typing
	_hide_cursor()

	if typing_target_label:
		typing_target_label.text = ""

func _process_typing(delta: float) -> void:
	"""Process letter-by-letter typing effect"""
	if not typing_active:
		return

	typing_timer += delta
	if typing_timer >= LETTER_REVEAL_SPEED:
		typing_timer = 0.0
		if typing_index < typing_text.length():
			typing_index += 1
			if typing_target_label:
				typing_target_label.text = typing_text.substr(0, typing_index)
		else:
			# Typing complete
			typing_active = false
			_on_typing_complete()

func _on_typing_complete() -> void:
	"""Called when typing animation finishes"""
	# Show cursor and wait for input for dialogue stages
	var is_dialogue_stage = current_stage in [
		CinematicStage.OPENING_DIALOGUE_1,
		CinematicStage.OPENING_DIALOGUE_2,
		CinematicStage.OPENING_DIALOGUE_3,
		CinematicStage.DIALOGUE_RESPONSE_1,
		CinematicStage.DIALOGUE_RESPONSE_2,
		CinematicStage.PERK_QUESTION,
		CinematicStage.DIALOGUE_BANDAGES,
		CinematicStage.DIALOGUE_MEMORY,
		CinematicStage.DIALOGUE_MIRROR
	]

	if is_dialogue_stage:
		_show_cursor_and_wait()
	else:
		# For other stages, just reset timer
		stage_timer = 0.0

func _show_cursor_and_wait() -> void:
	"""Show blinking up arrow and wait for player input"""
	waiting_for_input = true
	cursor_visible = true
	if arrow_label:
		arrow_label.visible = true
	if continue_prompt:
		continue_prompt.visible = true

func _hide_cursor() -> void:
	"""Hide the blinking up arrow"""
	waiting_for_input = false
	if arrow_label:
		arrow_label.visible = false
	if continue_prompt:
		continue_prompt.visible = false

# ── Cinematic Process Loop ───────────────────────────────────────────────────
func _process_cinematic(delta: float) -> void:
	"""Main cinematic update loop"""
	# Process typing
	if typing_active:
		_process_typing(delta)
	else:
		# Process blinking cursor
		if waiting_for_input:
			_process_cursor_blink(delta)
		else:
			# Process stage timer (for non-dialogue stages)
			stage_timer += delta

	# Handle stage-specific updates (only for non-dialogue stages)
	match current_stage:
		CinematicStage.NURSE_RESPONSES:
			_process_nurse_responses(delta)

func _process_cursor_blink(delta: float) -> void:
	"""Handle blinking up arrow animation"""
	cursor_blink_timer += delta
	if cursor_blink_timer >= CURSOR_BLINK_SPEED:
		cursor_blink_timer = 0.0
		cursor_visible = not cursor_visible
		if arrow_label:
			arrow_label.visible = cursor_visible

func _input(event: InputEvent) -> void:
	"""Handle input for advancing dialogue, name input, and stat selection (use _input to capture before ControllerManager)"""
	if not cinematic_active:
		return

	# Handle keyboard navigation when keyboard is visible
	if current_stage == CinematicStage.NAME_INPUT and keyboard_container:
		if event.is_action_pressed("ui_up"):
			get_viewport().set_input_as_handled()
			_handle_keyboard_navigation(0, -1)
			return
		elif event.is_action_pressed("ui_down"):
			get_viewport().set_input_as_handled()
			_handle_keyboard_navigation(0, 1)
			return
		elif event.is_action_pressed("ui_left"):
			get_viewport().set_input_as_handled()
			_handle_keyboard_navigation(-1, 0)
			return
		elif event.is_action_pressed("ui_right"):
			get_viewport().set_input_as_handled()
			_handle_keyboard_navigation(1, 0)
			return
		elif event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			_handle_keyboard_accept()
			return
		elif event is InputEventJoypadButton and event.pressed:
			get_viewport().set_input_as_handled()
			_handle_keyboard_accept()
			return
		return

	# Handle name input stage separately
	if current_stage == CinematicStage.NAME_INPUT and (name_input_stage == 0 or name_input_stage == 2):
		# We're on field selection, waiting for accept
		var should_accept = false

		if event.is_action_pressed("ui_accept"):
			should_accept = true
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				should_accept = true
		elif event is InputEventJoypadButton and event.pressed:
			should_accept = true

		if should_accept:
			get_viewport().set_input_as_handled()
			_handle_name_input_accept()
		return

	# Handle dialogue stages
	if not waiting_for_input:
		return

	# Check for accept input (ui_accept, Enter, Space, or directional buttons)
	var should_advance = false

	# Check for ui_accept action (works for gamepad A button, Enter, etc.)
	if event.is_action_pressed("ui_accept"):
		should_advance = true
		print("[Cinematic] Advancing via ui_accept")
	# Check for directional buttons as alternative
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		should_advance = true
		print("[Cinematic] Advancing via directional button")
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		should_advance = true
		print("[Cinematic] Advancing via directional button")
	# Also check for Space key explicitly
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			should_advance = true
			print("[Cinematic] Advancing via Space key")
	# Check for any joypad button
	elif event is InputEventJoypadButton and event.pressed:
		should_advance = true
		print("[Cinematic] Advancing via joypad button: ", event.button_index)

	if should_advance:
		get_viewport().set_input_as_handled()
		_hide_cursor()
		_advance_stage()

func _process_nurse_responses(delta: float) -> void:
	"""Process nurse responses one at a time"""
	if not typing_active and stage_timer >= NURSE_RESPONSE_PAUSE:
		nurse_response_index += 1
		if nurse_response_index < 5:  # 5 stats total
			_show_next_nurse_response()
		else:
			# All responses shown, advance to next stage
			_advance_stage()

# ── Stage Management ─────────────────────────────────────────────────────────
func _enter_stage(stage: CinematicStage) -> void:
	"""Enter a new cinematic stage"""
	current_stage = stage
	stage_timer = 0.0
	typing_active = false
	print("[Cinematic] Entering stage: ", CinematicStage.keys()[stage])

	match stage:
		CinematicStage.OPENING_DIALOGUE_1:
			_start_typing("Oh, I think they are regaining consciousness..")
		CinematicStage.OPENING_DIALOGUE_2:
			_start_typing("Check if they are aware.")
		CinematicStage.OPENING_DIALOGUE_3:
			_start_typing("Hey, do you remember your name?")
		CinematicStage.NAME_INPUT:
			_build_name_input_ui()
		CinematicStage.DIALOGUE_RESPONSE_1:
			dialogue_label.text = ""
			_start_typing("They're speaking and it seems their memory is intact!")
		CinematicStage.DIALOGUE_RESPONSE_2:
			_start_typing("Nurse, go check their vitals and reflexes.")
		CinematicStage.STAT_SELECTION:
			_build_stat_selection_ui()
		CinematicStage.PERK_QUESTION:
			dialogue_label.text = ""
			_start_typing("Choose a perk.")
		CinematicStage.PERK_SELECTION:
			_build_perk_selection_ui()
		CinematicStage.NURSE_RESPONSES:
			nurse_response_index = 0
			dialogue_label.text = ""
			_show_next_nurse_response()
		CinematicStage.DIALOGUE_BANDAGES:
			dialogue_label.text = ""
			_start_typing("Ok, I think we can remove the bandages now.")
		CinematicStage.DIALOGUE_MEMORY:
			_start_typing("Let's check your memory.")
		CinematicStage.DIALOGUE_MIRROR:
			_start_typing("Do you recognize the person in the mirror?")
		CinematicStage.CHARACTER_CUSTOMIZATION:
			_build_customization_ui()
		CinematicStage.FINAL_CONFIRMATION:
			_build_confirmation_ui()
		CinematicStage.COMPLETE:
			_complete_cinematic()

func _advance_stage() -> void:
	"""Advance to the next cinematic stage"""
	var next_stage = (current_stage + 1) as CinematicStage
	_enter_stage(next_stage)

func _complete_cinematic() -> void:
	"""Complete the cinematic and save character"""
	cinematic_active = false
	_apply_character_creation()

# ── Name Input UI ────────────────────────────────────────────────────────────
func _build_name_input_ui() -> void:
	"""Build the name input UI with field selection"""
	# Hide dialogue label
	if dialogue_label:
		dialogue_label.visible = false

	# Reset name input state
	name_input_stage = 0
	cinematic_name = ""
	cinematic_surname = ""

	# Create name input container
	name_input_container = VBoxContainer.new()
	name_input_container.set_anchors_preset(Control.PRESET_CENTER)
	name_input_container.anchor_left = 0.5
	name_input_container.anchor_top = 0.5
	name_input_container.anchor_right = 0.5
	name_input_container.anchor_bottom = 0.5
	name_input_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	name_input_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	name_input_container.add_theme_constant_override("separation", 20)
	cinematic_layer.add_child(name_input_container)

	# First name display (panel with label)
	var first_title = Label.new()
	first_title.text = "First Name:"
	first_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	first_title.add_theme_font_size_override("font_size", 14)
	first_title.add_theme_color_override("font_color", Color.WHITE)
	name_input_container.add_child(first_title)

	var first_panel = PanelContainer.new()
	first_panel.custom_minimum_size = Vector2(300, 50)
	first_panel.name = "FirstNamePanel"
	var first_style = StyleBoxFlat.new()
	first_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	first_style.border_color = Color(1.0, 0.7, 0.75, 1.0)  # Pink - selected
	first_style.border_width_left = 3
	first_style.border_width_right = 3
	first_style.border_width_top = 3
	first_style.border_width_bottom = 3
	first_style.corner_radius_top_left = 8
	first_style.corner_radius_top_right = 8
	first_style.corner_radius_bottom_left = 8
	first_style.corner_radius_bottom_right = 8
	first_panel.add_theme_stylebox_override("panel", first_style)
	name_input_container.add_child(first_panel)

	first_name_label = Label.new()
	first_name_label.text = "___"
	first_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	first_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	first_name_label.add_theme_font_size_override("font_size", 18)
	first_name_label.add_theme_color_override("font_color", Color.WHITE)
	first_panel.add_child(first_name_label)

	# Last name display (panel with label)
	var last_title = Label.new()
	last_title.text = "Last Name:"
	last_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	last_title.add_theme_font_size_override("font_size", 14)
	last_title.add_theme_color_override("font_color", Color.WHITE)
	name_input_container.add_child(last_title)

	var last_panel = PanelContainer.new()
	last_panel.custom_minimum_size = Vector2(300, 50)
	last_panel.name = "LastNamePanel"
	var last_style = StyleBoxFlat.new()
	last_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	last_style.border_color = Color(0.5, 0.5, 0.5, 1.0)  # Gray - not selected
	last_style.border_width_left = 2
	last_style.border_width_right = 2
	last_style.border_width_top = 2
	last_style.border_width_bottom = 2
	last_style.corner_radius_top_left = 8
	last_style.corner_radius_top_right = 8
	last_style.corner_radius_bottom_left = 8
	last_style.corner_radius_bottom_right = 8
	last_panel.add_theme_stylebox_override("panel", last_style)
	name_input_container.add_child(last_panel)

	last_name_label = Label.new()
	last_name_label.text = "___"
	last_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	last_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	last_name_label.add_theme_font_size_override("font_size", 18)
	last_name_label.add_theme_color_override("font_color", Color.WHITE)
	last_panel.add_child(last_name_label)

	# Instruction label
	var instruction = Label.new()
	instruction.text = "Press Accept to enter name"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 12)
	instruction.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	instruction.name = "InstructionLabel"
	name_input_container.add_child(instruction)

	# Fade in the container
	name_input_container.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(name_input_container, "modulate", Color(1, 1, 1, 1), 0.5)

func _handle_name_input_accept() -> void:
	"""Handle accept button on name input field selection"""
	match name_input_stage:
		0:  # First name field selected - show keyboard
			current_name_text = cinematic_name  # Start with existing text (or empty)
			_show_keyboard()
			name_input_stage = 1
		2:  # Last name field selected - show keyboard
			current_name_text = cinematic_surname  # Start with existing text (or empty)
			_show_keyboard()
			name_input_stage = 3

func _show_keyboard() -> void:
	"""Show the on-screen keyboard with navigable grid"""
	# Hide instruction
	var instruction = name_input_container.get_node_or_null("InstructionLabel")
	if instruction:
		instruction.visible = false

	# Reset keyboard navigation state
	keyboard_focused_row = 0
	keyboard_focused_col = 0
	keyboard_buttons.clear()

	# Create keyboard container
	keyboard_container = VBoxContainer.new()
	keyboard_container.name = "KeyboardContainer"
	keyboard_container.add_theme_constant_override("separation", 10)
	name_input_container.add_child(keyboard_container)

	# Current text display
	var current_text_label = Label.new()
	current_text_label.name = "CurrentTextLabel"
	current_text_label.text = current_name_text if current_name_text else "___"
	current_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_text_label.add_theme_font_size_override("font_size", 20)
	current_text_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.75, 1.0))
	keyboard_container.add_child(current_text_label)

	# Letter grid (9 columns, 4 rows for uppercase and lowercase)
	var letter_grid = GridContainer.new()
	letter_grid.columns = keyboard_grid_cols
	letter_grid.add_theme_constant_override("h_separation", 3)
	letter_grid.add_theme_constant_override("v_separation", 3)
	keyboard_container.add_child(letter_grid)

	# Uppercase letters (A-Z split across 3 rows of 9)
	var uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for i in range(uppercase.length()):
		var letter = uppercase[i]
		var btn = _create_keyboard_button(letter, Vector2(40, 40))
		btn.pressed.connect(_on_keyboard_letter_pressed.bind(letter))
		letter_grid.add_child(btn)
		keyboard_buttons.append({"button": btn, "value": letter, "type": "letter"})

	# Add padding buttons to fill the grid (27 letters, need 36 for 4 rows of 9)
	for i in range(9):  # 9 more buttons to reach 36
		if i < 1:  # First button is spacer
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(40, 40)
			letter_grid.add_child(spacer)
		else:  # Rest are lowercase letters
			var lowercase_start = i - 1
			if lowercase_start < 26:
				var letter = uppercase[lowercase_start].to_lower()
				var btn = _create_keyboard_button(letter, Vector2(40, 40))
				btn.pressed.connect(_on_keyboard_letter_pressed.bind(letter))
				letter_grid.add_child(btn)
				keyboard_buttons.append({"button": btn, "value": letter, "type": "letter"})

	# Add remaining lowercase letters
	var lowercase_remaining = "hijklmnopqrstuvwxyz"
	for i in range(lowercase_remaining.length()):
		var letter = lowercase_remaining[i]
		var btn = _create_keyboard_button(letter, Vector2(40, 40))
		btn.pressed.connect(_on_keyboard_letter_pressed.bind(letter))
		letter_grid.add_child(btn)
		keyboard_buttons.append({"button": btn, "value": letter, "type": "letter"})

	# Bottom row with Backspace and Accept (centered)
	var bottom_row = HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.add_theme_constant_override("separation", 20)
	keyboard_container.add_child(bottom_row)

	var backspace_btn = _create_keyboard_button("⌫ Backspace", Vector2(150, 50))
	backspace_btn.pressed.connect(_on_keyboard_backspace_pressed)
	bottom_row.add_child(backspace_btn)
	keyboard_buttons.append({"button": backspace_btn, "value": "BACKSPACE", "type": "action"})

	var accept_btn = _create_keyboard_button("✓ Accept", Vector2(150, 50))
	accept_btn.pressed.connect(_on_keyboard_accept_pressed)
	bottom_row.add_child(accept_btn)
	keyboard_buttons.append({"button": accept_btn, "value": "ACCEPT", "type": "action"})

	# Set initial focus
	_update_keyboard_focus()

func _create_keyboard_button(text: String, size: Vector2) -> Button:
	"""Create a styled keyboard button"""
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = size
	btn.add_theme_font_size_override("font_size", 14)
	return btn

func _handle_keyboard_navigation(dx: int, dy: int) -> void:
	"""Handle directional navigation on keyboard"""
	# Calculate total rows (letters in grid + action row)
	var letter_button_count = 0
	for kb in keyboard_buttons:
		if kb["type"] == "letter":
			letter_button_count += 1

	var letter_rows = ceil(float(letter_button_count) / float(keyboard_grid_cols))
	var total_rows = int(letter_rows) + 1  # +1 for action row

	# Get current linear index
	var current_index = _get_keyboard_linear_index()

	if dy != 0:  # Vertical movement
		var new_row = keyboard_focused_row + dy
		new_row = clamp(new_row, 0, total_rows - 1)
		keyboard_focused_row = new_row

		# Adjust column if needed
		if keyboard_focused_row < letter_rows:
			# In letter grid
			keyboard_focused_col = clamp(keyboard_focused_col, 0, keyboard_grid_cols - 1)
		else:
			# In action row (only 2 buttons)
			keyboard_focused_col = clamp(keyboard_focused_col, 0, 1)

	if dx != 0:  # Horizontal movement
		if keyboard_focused_row < letter_rows:
			# In letter grid
			keyboard_focused_col += dx
			keyboard_focused_col = wrapi(keyboard_focused_col, 0, keyboard_grid_cols)
		else:
			# In action row
			keyboard_focused_col += dx
			keyboard_focused_col = wrapi(keyboard_focused_col, 0, 2)

	_update_keyboard_focus()

func _get_keyboard_linear_index() -> int:
	"""Get the linear index of currently focused keyboard button"""
	var letter_button_count = 0
	for kb in keyboard_buttons:
		if kb["type"] == "letter":
			letter_button_count += 1

	var letter_rows = ceil(float(letter_button_count) / float(keyboard_grid_cols))

	if keyboard_focused_row < letter_rows:
		return keyboard_focused_row * keyboard_grid_cols + keyboard_focused_col
	else:
		# Action row
		return letter_button_count + keyboard_focused_col

func _update_keyboard_focus() -> void:
	"""Update visual focus on keyboard"""
	var focused_index = _get_keyboard_linear_index()

	# Reset all buttons to normal style
	for i in range(keyboard_buttons.size()):
		var kb = keyboard_buttons[i]
		var btn = kb["button"]
		if i == focused_index:
			# Focused - add pink modulate
			btn.modulate = Color(1.0, 0.7, 0.75, 1.0)
		else:
			# Normal
			btn.modulate = Color.WHITE

func _handle_keyboard_accept() -> void:
	"""Handle accept button press on keyboard"""
	var focused_index = _get_keyboard_linear_index()
	if focused_index >= 0 and focused_index < keyboard_buttons.size():
		var kb = keyboard_buttons[focused_index]
		var value = kb["value"]

		if value == "BACKSPACE":
			_on_keyboard_backspace_pressed()
		elif value == "ACCEPT":
			_on_keyboard_accept_pressed()
		else:
			# It's a letter
			_on_keyboard_letter_pressed(value)

func _on_keyboard_letter_pressed(letter: String) -> void:
	"""Handle letter button press on keyboard"""
	if current_name_text.length() < 8:  # Max 8 characters
		current_name_text += letter
		_update_keyboard_display()

func _on_keyboard_backspace_pressed() -> void:
	"""Handle backspace on keyboard"""
	if current_name_text.length() > 0:
		current_name_text = current_name_text.substr(0, current_name_text.length() - 1)
		_update_keyboard_display()

func _update_keyboard_display() -> void:
	"""Update the keyboard's current text display"""
	if keyboard_container:
		var text_label = keyboard_container.get_node_or_null("CurrentTextLabel")
		if text_label:
			text_label.text = current_name_text if current_name_text else "___"

func _on_keyboard_accept_pressed() -> void:
	"""Handle accept button on keyboard"""
	if current_name_text.is_empty():
		return  # Don't accept empty names

	# Hide keyboard
	if keyboard_container:
		keyboard_container.queue_free()
		keyboard_container = null

	# Store the name in the appropriate field
	match name_input_stage:
		1:  # Was entering first name
			cinematic_name = current_name_text
			if first_name_label:
				first_name_label.text = cinematic_name
			# Move to last name field
			_update_name_field_selection(false)  # Deselect first
			_update_name_field_selection(true)   # Select last
			name_input_stage = 2
			# Show instruction again
			var instruction = name_input_container.get_node_or_null("InstructionLabel")
			if instruction:
				instruction.visible = true
				instruction.text = "Press Accept to enter last name"
		3:  # Was entering last name
			cinematic_surname = current_name_text
			if last_name_label:
				last_name_label.text = cinematic_surname
			# Finalize names and advance
			_finalize_names()

func _update_name_field_selection(is_last_name: bool) -> void:
	"""Update the visual selection of name fields"""
	if not name_input_container:
		return

	var first_panel = name_input_container.get_node_or_null("FirstNamePanel")
	var last_panel = name_input_container.get_node_or_null("LastNamePanel")

	if first_panel and last_panel:
		# Create pink style for selected
		var selected_style = StyleBoxFlat.new()
		selected_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
		selected_style.border_color = Color(1.0, 0.7, 0.75, 1.0)
		selected_style.border_width_left = 3
		selected_style.border_width_right = 3
		selected_style.border_width_top = 3
		selected_style.border_width_bottom = 3
		selected_style.corner_radius_top_left = 8
		selected_style.corner_radius_top_right = 8
		selected_style.corner_radius_bottom_left = 8
		selected_style.corner_radius_bottom_right = 8

		# Create gray style for unselected
		var unselected_style = StyleBoxFlat.new()
		unselected_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
		unselected_style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		unselected_style.border_width_left = 2
		unselected_style.border_width_right = 2
		unselected_style.border_width_top = 2
		unselected_style.border_width_bottom = 2
		unselected_style.corner_radius_top_left = 8
		unselected_style.corner_radius_top_right = 8
		unselected_style.corner_radius_bottom_left = 8
		unselected_style.corner_radius_bottom_right = 8

		if is_last_name:
			first_panel.add_theme_stylebox_override("panel", unselected_style)
			last_panel.add_theme_stylebox_override("panel", selected_style)
		else:
			first_panel.add_theme_stylebox_override("panel", selected_style)
			last_panel.add_theme_stylebox_override("panel", unselected_style)

func _finalize_names() -> void:
	"""Finalize name input and advance to next stage"""
	# Store in the existing form fields too
	if _name_in:
		_name_in.text = cinematic_name
	if _surname_in:
		_surname_in.text = cinematic_surname

	# Fade out and advance
	var tween = create_tween()
	tween.tween_property(name_input_container, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.tween_callback(func():
		name_input_container.queue_free()
		name_input_container = null
		dialogue_label.visible = true
		_advance_stage()
	)

# ── Stat Selection UI ────────────────────────────────────────────────────────
func _build_stat_selection_ui() -> void:
	"""Build the stat selection UI with simple toggle buttons"""
	# Hide dialogue label
	if dialogue_label:
		dialogue_label.visible = false

	# Reset stat selection state
	stat_selected = [false, false, false, false, false]
	stat_panels.clear()

	# Create stat selection container
	stat_selection_container = VBoxContainer.new()
	stat_selection_container.set_anchors_preset(Control.PRESET_CENTER)
	stat_selection_container.anchor_left = 0.5
	stat_selection_container.anchor_top = 0.5
	stat_selection_container.anchor_right = 0.5
	stat_selection_container.anchor_bottom = 0.5
	stat_selection_container.offset_left = -400
	stat_selection_container.offset_right = 400
	stat_selection_container.offset_top = -300
	stat_selection_container.offset_bottom = 300
	stat_selection_container.add_theme_constant_override("separation", 10)
	stat_selection_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let input pass to children
	cinematic_layer.add_child(stat_selection_container)

	# Title
	var title = Label.new()
	title.text = "What are your strengths? Choose 3."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.WHITE)
	stat_selection_container.add_child(title)

	# Stat names and descriptions
	var stats = [
		{"name": "BRAWN", "id": "BRW", "desc": "Physical attack power and weapon damage"},
		{"name": "VITALITY", "id": "VTL", "desc": "Maximum health and physical defense"},
		{"name": "TEMPO", "id": "TPO", "desc": "Initiative and action speed"},
		{"name": "MIND", "id": "MND", "desc": "Sigil power and skill damage"},
		{"name": "FOCUS", "id": "FCS", "desc": "Maximum MP and skill accuracy"}
	]

	# Create stat toggle buttons
	for i in range(stats.size()):
		var stat_button = CheckButton.new()
		stat_button.text = "%s - %s" % [stats[i]["name"], stats[i]["desc"]]
		stat_button.custom_minimum_size = Vector2(750, 50)
		stat_button.add_theme_font_size_override("font_size", 16)
		stat_button.button_pressed = false
		stat_button.name = "StatButton_%d" % i
		stat_button.toggled.connect(_on_stat_button_toggled.bind(i))
		stat_button.focus_mode = Control.FOCUS_ALL  # Enable focus for controller
		stat_button.toggle_mode = true  # Ensure toggle mode is on

		stat_selection_container.add_child(stat_button)
		stat_panels.append(stat_button)

	# Continue button
	var continue_btn_container = CenterContainer.new()
	stat_selection_container.add_child(continue_btn_container)

	stat_continue_button = Button.new()
	stat_continue_button.text = "Continue"
	stat_continue_button.name = "ContinueButton"
	stat_continue_button.custom_minimum_size = Vector2(200, 50)
	stat_continue_button.add_theme_font_size_override("font_size", 16)
	stat_continue_button.disabled = true  # Disabled until 3 stats selected
	stat_continue_button.pressed.connect(_on_stats_accepted)
	stat_continue_button.focus_mode = Control.FOCUS_ALL  # Enable focus for controller
	continue_btn_container.add_child(stat_continue_button)

	# Set up focus neighbors for proper up/down navigation
	for i in range(stat_panels.size()):
		var btn = stat_panels[i]
		if i > 0:
			# Set previous button as up neighbor
			btn.focus_neighbor_top = btn.get_path_to(stat_panels[i - 1])
		if i < stat_panels.size() - 1:
			# Set next button as down neighbor
			btn.focus_neighbor_bottom = btn.get_path_to(stat_panels[i + 1])
		else:
			# Last stat button -> Continue button
			btn.focus_neighbor_bottom = btn.get_path_to(stat_continue_button)

	# Continue button -> back to first stat
	if stat_panels.size() > 0:
		stat_continue_button.focus_neighbor_top = stat_continue_button.get_path_to(stat_panels[stat_panels.size() - 1])
		stat_continue_button.focus_neighbor_bottom = stat_continue_button.get_path_to(stat_panels[0])

		# First stat gets initial focus
		stat_panels[0].grab_focus()

	# Fade in and then set focus
	stat_selection_container.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(stat_selection_container, "modulate", Color(1, 1, 1, 1), 0.5)
	tween.tween_callback(func():
		# Ensure first button has focus after fade in
		if stat_panels.size() > 0:
			print("[Stat Selection] Setting focus to first button after fade")
			stat_panels[0].grab_focus()
	)

func _on_stat_button_toggled(button_pressed: bool, index: int) -> void:
	"""Handle stat button toggle"""
	print("[Stat Selection] Button ", index, " toggled: ", button_pressed)
	var selected_count = stat_selected.count(true)

	if button_pressed:
		# Trying to turn on
		if selected_count >= 3:
			# Already have 3 selected, reject this
			var btn = stat_panels[index]
			if btn:
				btn.set_pressed_no_signal(false)
			return
		else:
			stat_selected[index] = true
	else:
		# Turning off
		stat_selected[index] = false

	# Update Continue button
	_update_continue_button()

func _update_continue_button() -> void:
	"""Enable/disable the Continue button based on selection count"""
	if stat_continue_button:
		var selected_count = stat_selected.count(true)
		stat_continue_button.disabled = (selected_count != 3)

func _on_stats_accepted() -> void:
	"""Handle stat selection acceptance"""
	# Verify exactly 3 stats are selected
	var selected_count = stat_selected.count(true)
	if selected_count != 3:
		return  # Button should be disabled anyway

	# Convert selections to stat IDs and apply to form
	var stat_ids = ["BRW", "VTL", "TPO", "MND", "FCS"]
	_selected_order.clear()

	# Deselect all checkboxes first
	if _brw_cb: _brw_cb.set_pressed_no_signal(false)
	if _vtl_cb: _vtl_cb.set_pressed_no_signal(false)
	if _tpo_cb: _tpo_cb.set_pressed_no_signal(false)
	if _mnd_cb: _mnd_cb.set_pressed_no_signal(false)
	if _fcs_cb: _fcs_cb.set_pressed_no_signal(false)

	# Apply selections
	for i in range(stat_selected.size()):
		if stat_selected[i]:
			var stat_id = stat_ids[i]
			_selected_order.append(stat_id)

			# Check the corresponding checkbox
			match stat_id:
				"BRW": if _brw_cb: _brw_cb.set_pressed_no_signal(true)
				"VTL": if _vtl_cb: _vtl_cb.set_pressed_no_signal(true)
				"TPO": if _tpo_cb: _tpo_cb.set_pressed_no_signal(true)
				"MND": if _mnd_cb: _mnd_cb.set_pressed_no_signal(true)
				"FCS": if _fcs_cb: _fcs_cb.set_pressed_no_signal(true)

	# Rebuild perk dropdown with new selections
	_rebuild_perk_dropdown()

	# Fade out and advance
	var tween = create_tween()
	tween.tween_property(stat_selection_container, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.tween_callback(func():
		stat_selection_container.queue_free()
		stat_selection_container = null
		dialogue_label.visible = true
		_advance_stage()
	)

# ── Perk Selection UI ────────────────────────────────────────────────────────
func _build_perk_selection_ui() -> void:
	"""Build the perk selection UI with simple toggle buttons"""
	# Hide dialogue label
	if dialogue_label:
		dialogue_label.visible = false

	# Create perk selection container
	perk_selection_container = VBoxContainer.new()
	perk_selection_container.set_anchors_preset(Control.PRESET_CENTER)
	perk_selection_container.anchor_left = 0.5
	perk_selection_container.anchor_top = 0.5
	perk_selection_container.anchor_right = 0.5
	perk_selection_container.anchor_bottom = 0.5
	perk_selection_container.offset_left = -400
	perk_selection_container.offset_right = 400
	perk_selection_container.offset_top = -300
	perk_selection_container.offset_bottom = 300
	perk_selection_container.add_theme_constant_override("separation", 10)
	perk_selection_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let input pass to children
	cinematic_layer.add_child(perk_selection_container)

	# Title
	var title = Label.new()
	title.text = "Choose a Perk"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.WHITE)
	perk_selection_container.add_child(title)

	# Get available perks
	var perk_system = get_node_or_null(PERK_PATH)
	var perk_buttons: Array = []

	print("[Perk Selection] Building perk selection UI")
	if perk_system and perk_system.has_method("get_starting_options"):
		var picks: Array[String] = []
		for s in _selected_order:
			picks.append(s)
		var offers: Array = perk_system.call("get_starting_options", picks)
		print("[Perk Selection] Got ", offers.size(), " perk offers")

		# Create toggle button for each perk
		for i in range(offers.size()):
			var offer = offers[i]
			if typeof(offer) != TYPE_DICTIONARY:
				continue

			var stat = str(offer.get("stat", ""))
			var name = str(offer.get("name", "Unknown"))
			var desc = str(offer.get("desc", "No description"))

			var perk_button = CheckButton.new()
			perk_button.text = "%s - %s: %s" % [stat, name, desc]
			perk_button.custom_minimum_size = Vector2(750, 50)
			perk_button.add_theme_font_size_override("font_size", 14)
			perk_button.button_pressed = false
			perk_button.name = "PerkButton_%d" % i
			perk_button.set_meta("perk_data", offer)
			perk_button.toggled.connect(_on_perk_button_toggled.bind(perk_button))
			perk_button.focus_mode = Control.FOCUS_ALL  # Enable focus for controller
			perk_button.toggle_mode = true  # Ensure toggle mode is on

			perk_selection_container.add_child(perk_button)
			perk_buttons.append(perk_button)

	# Store buttons for later use
	perk_selection_container.set_meta("perk_buttons", perk_buttons)

	# Continue button
	var continue_btn_container = CenterContainer.new()
	perk_selection_container.add_child(continue_btn_container)

	var continue_btn = Button.new()
	continue_btn.text = "Continue"
	continue_btn.name = "ContinueButton"
	continue_btn.custom_minimum_size = Vector2(200, 50)
	continue_btn.add_theme_font_size_override("font_size", 16)
	continue_btn.disabled = true  # Disabled until a perk is selected
	continue_btn.pressed.connect(_on_perk_accepted)
	continue_btn.focus_mode = Control.FOCUS_ALL  # Enable focus for controller
	continue_btn_container.add_child(continue_btn)

	# Set up focus neighbors for proper up/down navigation
	for i in range(perk_buttons.size()):
		var btn = perk_buttons[i]
		if i > 0:
			# Set previous button as up neighbor
			btn.focus_neighbor_top = btn.get_path_to(perk_buttons[i - 1])
		if i < perk_buttons.size() - 1:
			# Set next button as down neighbor
			btn.focus_neighbor_bottom = btn.get_path_to(perk_buttons[i + 1])
		else:
			# Last perk button -> Continue button
			btn.focus_neighbor_bottom = btn.get_path_to(continue_btn)

	# Continue button -> back to first perk
	if perk_buttons.size() > 0:
		continue_btn.focus_neighbor_top = continue_btn.get_path_to(perk_buttons[perk_buttons.size() - 1])
		continue_btn.focus_neighbor_bottom = continue_btn.get_path_to(perk_buttons[0])

		# First perk gets initial focus
		perk_buttons[0].grab_focus()

	# Fade in and then set focus
	perk_selection_container.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(perk_selection_container, "modulate", Color(1, 1, 1, 1), 0.5)
	tween.tween_callback(func():
		# Ensure first button has focus after fade in
		var perk_buttons = perk_selection_container.get_meta("perk_buttons", [])
		if perk_buttons.size() > 0:
			print("[Perk Selection] Setting focus to first perk button after fade")
			perk_buttons[0].grab_focus()
	)

func _on_perk_button_toggled(button_pressed: bool, toggled_button: CheckButton) -> void:
	"""Handle perk button toggle - only allow one selection (radio button behavior)"""
	print("[Perk Selection] Button toggled: ", button_pressed)
	if not perk_selection_container:
		print("[Perk Selection] ERROR: No perk_selection_container!")
		return

	if button_pressed:
		print("[Perk Selection] Perk selected, deselecting others")
		# Deselect all other perk buttons
		var perk_buttons = perk_selection_container.get_meta("perk_buttons", [])
		for btn in perk_buttons:
			if btn != toggled_button:
				btn.set_pressed_no_signal(false)

		# Enable Continue button
		var continue_btn = perk_selection_container.get_node_or_null("CenterContainer/ContinueButton")
		if continue_btn:
			print("[Perk Selection] Enabling Continue button")
			continue_btn.disabled = false
	else:
		print("[Perk Selection] Attempting to deselect - preventing")
		# Don't allow deselecting - keep it selected (radio button behavior)
		toggled_button.set_pressed_no_signal(true)

func _on_perk_accepted() -> void:
	"""Handle perk selection acceptance"""
	if not perk_selection_container:
		return

	# Find which perk button is selected
	var perk_buttons = perk_selection_container.get_meta("perk_buttons", [])
	var selected_perk_data = null

	for btn in perk_buttons:
		if btn.button_pressed:
			selected_perk_data = btn.get_meta("perk_data", null)
			break

	if not selected_perk_data:
		return  # Continue button should be disabled if nothing selected anyway

	# Get selected perk and apply to form
	if typeof(selected_perk_data) == TYPE_DICTIONARY:
		var perk_id = str(selected_perk_data.get("id", ""))

		# Find and select this perk in the original dropdown
		if _perk_in:
			for i in range(_perk_in.item_count):
				if _perk_id_by_idx.get(i, "") == perk_id:
					_perk_in.select(i)
					break

	# Fade out and advance
	var tween = create_tween()
	tween.tween_property(perk_selection_container, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.tween_callback(func():
		perk_selection_container.queue_free()
		perk_selection_container = null
		dialogue_label.visible = true
		_advance_stage()
	)

# ── Nurse Responses ──────────────────────────────────────────────────────────
func _show_next_nurse_response() -> void:
	"""Show the next nurse response based on stat selections"""
	var stat_ids = ["BRW", "VTL", "TPO", "MND", "FCS"]
	var stat_names = ["BRAWN", "VITALITY", "TEMPO", "MIND", "FOCUS"]

	if nurse_response_index >= 5:
		return

	var stat_id = stat_ids[nurse_response_index]
	var stat_name = stat_names[nurse_response_index]
	var is_selected = _selected_order.has(stat_id)

	var responses_positive = {
		"BRW": "They have a strong grip!",
		"VTL": "I'm surprised with how fast they heal.",
		"TPO": "Reflexes check out great.",
		"MND": "The EEG test shows massive neural activity!",
		"FCS": "The auditory test shows superb focus."
	}

	var responses_negative = {
		"BRW": "Their grip is still a bit weak.",
		"VTL": "Some of these wounds still haven't healed.",
		"TPO": "Reflexes seem out of sync.",
		"MND": "The EEG indicates recovering neural activity.",
		"FCS": "Not very responsive to the auditory test."
	}

	var response = responses_positive[stat_id] if is_selected else responses_negative[stat_id]

	# Add current responses to dialogue
	if dialogue_label.text.is_empty():
		dialogue_label.text = response
	else:
		dialogue_label.text += "\n\n" + response

	stage_timer = 0.0

# ── Character Customization UI ───────────────────────────────────────────────
func _build_customization_ui() -> void:
	"""Build character customization UI (pronoun, body, outfit, hair, hat)"""
	# Hide dialogue label
	if dialogue_label:
		dialogue_label.visible = false

	# Create customization container
	customization_container = Control.new()
	customization_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	cinematic_layer.add_child(customization_container)

	# Title
	var title = Label.new()
	title.text = "Customize Your Appearance"
	title.position = Vector2(0, 30)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	customization_container.add_child(title)

	# Main container
	var main = HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_CENTER)
	main.anchor_left = 0.5
	main.anchor_top = 0.5
	main.anchor_right = 0.5
	main.anchor_bottom = 0.5
	main.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main.grow_vertical = Control.GROW_DIRECTION_BOTH
	main.offset_left = -500
	main.offset_top = -250
	main.offset_right = 500
	main.offset_bottom = 250
	main.add_theme_constant_override("separation", 30)
	customization_container.add_child(main)

	# Left: Options
	var options_panel = _create_styled_panel()
	options_panel.custom_minimum_size = Vector2(400, 500)
	main.add_child(options_panel)

	var options = VBoxContainer.new()
	options.add_theme_constant_override("separation", 15)
	options_panel.add_child(options)

	# Create new dropdowns that mirror the original ones
	var pronoun_dd = OptionButton.new()
	pronoun_dd.name = "CinematicPronoun"
	for i in range(_pron_in.item_count):
		pronoun_dd.add_item(_pron_in.get_item_text(i))
	pronoun_dd.select(_pron_in.get_selected())
	pronoun_dd.item_selected.connect(_on_cinematic_dropdown_changed.bind("pronoun", pronoun_dd))
	_add_customization_option(options, "Pronoun:", pronoun_dd)

	var body_dd = OptionButton.new()
	body_dd.name = "CinematicBody"
	for i in range(_body_in.item_count):
		body_dd.add_item(_body_in.get_item_text(i))
	body_dd.select(_body_in.get_selected())
	body_dd.item_selected.connect(_on_cinematic_dropdown_changed.bind("body", body_dd))
	_add_customization_option(options, "Body Type:", body_dd)

	var outfit_dd = OptionButton.new()
	outfit_dd.name = "CinematicOutfit"
	for i in range(_outfit_in.item_count):
		outfit_dd.add_item(_outfit_in.get_item_text(i))
	outfit_dd.select(_outfit_in.get_selected())
	outfit_dd.item_selected.connect(_on_cinematic_dropdown_changed.bind("outfit", outfit_dd))
	_add_customization_option(options, "Outfit:", outfit_dd)

	var hair_dd = OptionButton.new()
	hair_dd.name = "CinematicHair"
	for i in range(_hair_in.item_count):
		hair_dd.add_item(_hair_in.get_item_text(i))
	hair_dd.select(_hair_in.get_selected())
	hair_dd.item_selected.connect(_on_cinematic_dropdown_changed.bind("hair", hair_dd))
	_add_customization_option(options, "Hair:", hair_dd)

	var hat_dd = OptionButton.new()
	hat_dd.name = "CinematicHat"
	for i in range(_hat_in.item_count):
		hat_dd.add_item(_hat_in.get_item_text(i))
	hat_dd.select(_hat_in.get_selected())
	hat_dd.item_selected.connect(_on_cinematic_dropdown_changed.bind("hat", hat_dd))
	_add_customization_option(options, "Hat:", hat_dd)

	# Right: Character Preview
	var preview_panel = _create_styled_panel()
	preview_panel.custom_minimum_size = Vector2(500, 500)
	main.add_child(preview_panel)

	var preview_container = VBoxContainer.new()
	preview_panel.add_child(preview_container)

	var preview_label = Label.new()
	preview_label.text = "Character Preview"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.add_theme_font_size_override("font_size", 16)
	preview_container.add_child(preview_label)

	# Use the existing character_layers (already displays current selection)
	# Just make them visible in the cinematic layer by showing the preview panel
	# The preview updates automatically as dropdowns change via existing system

	# Accept button
	var accept_btn = Button.new()
	accept_btn.text = "Accept"
	accept_btn.position = Vector2(0, -60)
	accept_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	accept_btn.anchor_top = 1.0
	accept_btn.anchor_bottom = 1.0
	accept_btn.custom_minimum_size = Vector2(200, 50)
	accept_btn.add_theme_font_size_override("font_size", 16)
	accept_btn.pressed.connect(_on_customization_accepted)
	customization_container.add_child(accept_btn)

	# Fade in
	customization_container.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(customization_container, "modulate", Color(1, 1, 1, 1), 0.5)

func _on_cinematic_dropdown_changed(index: int, type: String, dropdown: OptionButton) -> void:
	"""Handle dropdown changes in cinematic customization UI"""
	# Sync to the original form dropdowns to update preview
	match type:
		"pronoun":
			_pron_in.select(index)
		"body":
			_body_in.select(index)
			_on_body_selected(index)
		"outfit":
			_outfit_in.select(index)
			_on_outfit_selected(index)
		"hair":
			_hair_in.select(index)
			_on_hair_selected(index)
		"hat":
			_hat_in.select(index)
			_on_hat_selected(index)

func _add_customization_option(parent: VBoxContainer, label_text: String, option_button: OptionButton) -> void:
	"""Add a customization option to the parent container"""
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	option_button.custom_minimum_size = Vector2(250, 0)
	option_button.add_theme_font_size_override("font_size", 14)
	row.add_child(option_button)

	parent.add_child(row)

func _on_customization_accepted() -> void:
	"""Handle customization acceptance"""
	# Selections are already synced to original form via _on_cinematic_dropdown_changed

	# Fade out and advance
	var tween = create_tween()
	tween.tween_property(customization_container, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.tween_callback(func():
		customization_container.queue_free()
		customization_container = null
		dialogue_label.visible = true
		_advance_stage()
	)

# ── Final Confirmation ───────────────────────────────────────────────────────
func _build_confirmation_ui() -> void:
	"""Build final confirmation UI"""
	# Hide dialogue label initially
	if dialogue_label:
		dialogue_label.visible = true
		dialogue_label.text = ""

	# Type out the question
	_start_typing("Does everything seem correct?")

	# Create confirmation container
	confirmation_container = Control.new()
	confirmation_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	cinematic_layer.add_child(confirmation_container)

	# Yes/No buttons
	var buttons = HBoxContainer.new()
	buttons.set_anchors_preset(Control.PRESET_CENTER)
	buttons.anchor_left = 0.5
	buttons.anchor_top = 0.6
	buttons.anchor_right = 0.5
	buttons.anchor_bottom = 0.6
	buttons.grow_horizontal = Control.GROW_DIRECTION_BOTH
	buttons.grow_vertical = Control.GROW_DIRECTION_BOTH
	buttons.add_theme_constant_override("separation", 40)
	confirmation_container.add_child(buttons)

	# Yes button
	var yes_btn = Button.new()
	yes_btn.text = "Yes"
	yes_btn.custom_minimum_size = Vector2(150, 60)
	yes_btn.add_theme_font_size_override("font_size", 18)
	yes_btn.pressed.connect(_on_confirmation_yes)
	buttons.add_child(yes_btn)

	# No button
	var no_btn = Button.new()
	no_btn.text = "No"
	no_btn.custom_minimum_size = Vector2(150, 60)
	no_btn.add_theme_font_size_override("font_size", 18)
	no_btn.pressed.connect(_on_confirmation_no)
	buttons.add_child(no_btn)

	# Fade in buttons
	confirmation_container.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(confirmation_container, "modulate", Color(1, 1, 1, 1), 0.5)

func _on_confirmation_yes() -> void:
	"""Handle Yes - proceed with character creation"""
	_advance_stage()  # Go to COMPLETE

func _on_confirmation_no() -> void:
	"""Handle No - show fallback form"""
	# Clean up cinematic layer
	if cinematic_layer:
		cinematic_layer.queue_free()
		cinematic_layer = null

	cinematic_active = false

	# Show the standard form
	_show_form()

	# The existing _on_confirm_pressed will handle the final save

# ── Apply Character Creation ─────────────────────────────────────────────────
func _apply_character_creation() -> void:
	"""Apply the character creation and proceed to main game"""
	# All data is already in the form fields, just trigger the confirm
	_on_confirm_pressed()

# ── Helper Functions ─────────────────────────────────────────────────────────
func _create_styled_panel() -> PanelContainer:
	"""Create a styled panel container matching the LoadoutPanel style"""
	var panel = PanelContainer.new()

	var style_box = StyleBoxFlat.new()
	style_box.bg_color = PANEL_BG_COLOR
	style_box.border_color = PANEL_BORDER_COLOR
	style_box.border_width_left = PANEL_BORDER_WIDTH
	style_box.border_width_right = PANEL_BORDER_WIDTH
	style_box.border_width_top = PANEL_BORDER_WIDTH
	style_box.border_width_bottom = PANEL_BORDER_WIDTH
	style_box.corner_radius_top_left = PANEL_CORNER_RADIUS
	style_box.corner_radius_top_right = PANEL_CORNER_RADIUS
	style_box.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	style_box.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	panel.add_theme_stylebox_override("panel", style_box)

	# Add padding
	panel.add_theme_constant_override("margin_left", 20)
	panel.add_theme_constant_override("margin_top", 20)
	panel.add_theme_constant_override("margin_right", 20)
	panel.add_theme_constant_override("margin_bottom", 20)

	return panel

# ══════════════════════════════════════════════════════════════════════════════
# END OF CINEMATIC SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

func _on_cancel_pressed() -> void:
	# Disabled, but kept for scene compatibility
	pass
