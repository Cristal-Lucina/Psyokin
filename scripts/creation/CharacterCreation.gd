extends Control
class_name CharacterCreation

signal creation_applied

# Styling constants (matching LoadoutPanel)
const PANEL_BG_COLOR := Color(0.15, 0.15, 0.15, 1.0)  # Dark gray, fully opaque
const PANEL_BORDER_COLOR := Color(1.0, 0.7, 0.75, 1.0)  # Pink border
const PANEL_BORDER_WIDTH := 2
const PANEL_CORNER_RADIUS := 8

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

# ── ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	print("Character Creation starting...")

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
	# Name fields: max 10 characters each
	if _name_in:
		_name_in.max_length = 10
		_name_in.placeholder_text = "First Name"
	if _surname_in:
		_surname_in.max_length = 10
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

func _on_cancel_pressed() -> void:
	# Disabled, but kept for scene compatibility
	pass
