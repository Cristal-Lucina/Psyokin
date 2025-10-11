extends Control

## TrainingMenu
## Lists available training “spots” for the current phase/day and lets the player
## pick one. Spots are provided by WorldSpotsSystem and can be gated by:
## - Phase (Morning/Afternoon/Evening)
## - Weekday mask
## - Date window
## - Context (stats, items, story flags) when using `get_available_spots_with_ctx`
##
## Flow
## - `_ready()` wires UI, sets some layout prefs, and builds the list.
## - `_refresh_title()` shows “Train at a Spot — <Phase> (<Weekday>)”.
## - `_rebuild_list()` constructs a gating context and queries the spots system.
## - For each spot, a button is added; pressing it calls `train_at_spot(spot_id)`,
##   then closes the menu on success.

## Scene refs (expected in the TrainingMenu scene)
@onready var list_box: VBoxContainer = $CenterContainer/Panel/MarginContainer/Root/Scroll/List
@onready var scroll: ScrollContainer  = $CenterContainer/Panel/MarginContainer/Root/Scroll
@onready var close_btn: Button        = $CenterContainer/Panel/MarginContainer/Root/HBoxContainer/CloseBtn
@onready var title_lbl: Label         = $CenterContainer/Panel/MarginContainer/Root/HBoxContainer/Title
@onready var hint_lbl: Label          = $CenterContainer/Panel/MarginContainer/Root/Hint

## Autoload paths used by this menu
const WORLD_SPOTS_PATH := "/root/aWorldSpotsSystem"  ## Provides available spots + train_at_spot()
const CALENDAR_PATH    := "/root/aCalendarSystem"    ## Supplies phase/weekday for the title
const STATS_PATH       := "/root/aStatsSystem"       ## Supplies current stat levels for gating
const INV_PATH         := "/root/aInventorySystem"   ## Supplies item ownership for gating

## Entry point: basic layout, connect close button, render title and list.
func _ready() -> void:
	# Give the list some breathing room
	scroll.custom_minimum_size = Vector2(0, 260)
	list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	close_btn.pressed.connect(_on_close_pressed)
	_refresh_title()
	_rebuild_list()

## Sets “Train at a Spot — <Phase> (<Weekday>)” using CalendarSystem if present.
func _refresh_title() -> void:
	var phase: String = "Unknown"
	var weekday: String = "?"
	var cal := get_node_or_null(CALENDAR_PATH)
	if cal:
		if cal.has_method("get_phase_name"):
			phase = String(cal.get_phase_name())
		if cal.has_method("get_weekday_name"):
			weekday = String(cal.get_weekday_name())
	# e.g. "Train at a Spot — Morning (Monday)"
	title_lbl.text = "Train at a Spot — %s (%s)" % [phase, weekday]

## Removes any existing list entries before rebuilding.
func _clear_list() -> void:
	for n in list_box.get_children():
		n.queue_free()

## Builds the spot list:
## - Assembles a gating context: { stats, items, flags }
## - Calls `get_available_spots_with_ctx(ctx)` if available (else fallback)
## - For each result, creates a Button with the name + stat grant summary
## - On press, tries to train at the spot and closes on success
func _rebuild_list() -> void:
	_clear_list()

	var ws := get_node_or_null(WORLD_SPOTS_PATH)
	if ws == null:
		hint_lbl.text = "WorldSpotsSystem not found."
		return

	# ---- Build gating context safely ---------------------------------------
	var stats_dict: Dictionary = {}
	var stats_sys := get_node_or_null(STATS_PATH)
	if stats_sys and stats_sys.has_method("get_stats_dict"):
		stats_dict = stats_sys.get_stats_dict()

	var item_ids: Array[String] = []
	var inv := get_node_or_null(INV_PATH)
	if inv:
		if inv.has_method("get_item_ids"):
			var arr: Array = inv.get_item_ids()
			for x in arr:
				item_ids.append(String(x))
		elif "inventory" in inv and typeof(inv.inventory) == TYPE_DICTIONARY:
			for k in inv.inventory.keys():
				if int(inv.inventory[k]) > 0:
					item_ids.append(String(k))

	var ctx := {
		"stats": stats_dict,
		"items": item_ids,
		"flags": [],  # plug story flags when ready
	}

	# ---- Query spots --------------------------------------------------------
	var spots: Array = []
	if ws.has_method("get_available_spots_with_ctx"):
		spots = ws.get_available_spots_with_ctx(ctx)
	elif ws.has_method("get_available_spots"):
		# fallback (no ctx gating)
		spots = ws.get_available_spots()

	if spots.is_empty():
		hint_lbl.text = "No spots available this phase."
		return

	hint_lbl.text = "Choose a spot available this phase"

	# ---- Build UI -----------------------------------------------------------
	for rec in spots:
		var name_text := String(rec.get("name", rec.get("spot_id", "???")))
		var stat_info := _format_stat_info(rec)

		var btn := Button.new()
		btn.text = "%s  %s" % [name_text, stat_info]
		btn.clip_text = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var spot_id := String(rec.get("spot_id", ""))
		btn.pressed.connect(func ():
			var ws2 := get_node_or_null(WORLD_SPOTS_PATH)
			if ws2 and ws2.train_at_spot(spot_id):
				queue_free()
			else:
				hint_lbl.text = "Could not train at %s." % name_text
		)

		list_box.add_child(btn)

	# Let the container recalc after dynamic adds
	await get_tree().process_frame

## Formats the stat grant part of each row based on the spot record:
## - mode "pairs": uses a map like { "BRW": 2, "FCS": 1 } → "(BRW +2, FCS +1)"
## - mode "rnd"  : show "(RND +X)" where X is base_sxp
## - mode "list" : split base across listed stats → "(BRW +1, VTL +1, ...)"
func _format_stat_info(rec: Dictionary) -> String:
	var mode := String(rec.get("stats_mode", "list"))
	if mode == "pairs":
		var map: Dictionary = rec.get("stats_map", {})
		var parts: Array = []
		for k in map.keys():
			parts.append("%s +%d" % [String(k), int(map[k])])
		return "(" + ", ".join(parts) + ")"
	elif mode == "rnd":
		var base_sxp: int = int(rec.get("base_sxp", 0))
		return "(RND +%d)" % base_sxp
	else:
		var lst: Array = rec.get("stats_list", [])
		var base_sxp_l: int = int(rec.get("base_sxp", 0))
		var per: int = 0
		if lst.size() > 0:
			per = int(max(1, round(float(base_sxp_l) / float(lst.size()))))
		var parts2: Array = []
		for s in lst:
			parts2.append("%s +%d" % [String(s), per])
		return "(" + ", ".join(parts2) + ")"

## Close the Training menu without choosing a spot.
func _on_close_pressed() -> void:
	queue_free()
