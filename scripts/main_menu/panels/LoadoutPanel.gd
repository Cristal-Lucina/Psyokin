## ═══════════════════════════════════════════════════════════════════════════
## LoadoutPanel - Party Member Equipment & Sigil UI
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Main menu panel for managing party member equipment (5 slots) and sigil
##   loadouts (bracelet socket assignments). Displays derived stats, active
##   sigils, and provides equip/unequip interfaces.
##
## RESPONSIBILITIES:
##   • Party member selection list
##   • Equipment slot display (weapon, armor, head, foot, bracelet)
##   • Sigil socket display (shows equipped sigils with level/XP/active skill)
##   • Derived stat calculation display (HP, MP, attack, defense, etc.)
##   • Equip/unequip popup menus for gear
##   • Sigil equip/remove interface
##   • Sigil Skills menu integration (manage sigil skills)
##   • Hero active type selection (Omega/Fire/Water/etc.)
##   • Real-time stat updates when equipment changes
##
## EQUIPMENT DISPLAY:
##   5 slots shown with labels and buttons:
##   • Weapon → Weapon Attack, Scale, Accuracy, Crit, Type, Special
##   • Armor → Physical Defense, Ailment Resistance
##   • Head → HP/MP Bonus, Mind Defense
##   • Foot → Physical/Mind Evasion, Speed
##   • Bracelet → Sigil Slots count, Active Sigil display
##
## SIGIL DISPLAY:
##   For each sigil socket in the equipped bracelet:
##   • Sigil name (from base def)
##   • Level (Lv 1-4 or MAX)
##   • Active skill (★ icon with skill name)
##   • Equip/Remove buttons
##
## CONNECTED SYSTEMS (Autoloads):
##   • GameState - Party roster, member data
##   • EquipmentSystem - Get/set equipment, item definitions
##   • SigilSystem - Get/set sigil loadouts, instance data
##   • InventorySystem - Available items for equipping
##   • StatsSystem - Derived stat calculations (HP, MP, pools)
##
## UI FEATURES:
##   • Polling fallback (refreshes every 0.5s to catch external changes)
##   • Signal-based reactivity (equipment_changed, loadout_changed, stats_changed)
##   • Popup menus for item selection
##   • SigilSkillMenu overlay for managing sigil active skills
##   • Hero-only active type picker (set hero's mind type override)
##
## KEY METHODS:
##   • _on_party_selected(index) - Switch displayed member
##   • _on_slot_button(slot) - Open equip menu for slot
##   • _on_equip_sigil(member, slot) - Open sigil selection menu
##   • _on_remove_sigil(member, slot) - Unequip sigil from slot
##   • _on_manage_sigils() - Open SigilSkillMenu overlay
##   • _refresh_all_for_current() - Update all displays for selected member
##
## ═══════════════════════════════════════════════════════════════════════════

extends PanelBase
class_name LoadoutPanel

@onready var _party_list: ItemList       = get_node("Row/Party/PartyList") as ItemList
@onready var _member_name: Label         = get_node("Row/Right/MemberName") as Label

@onready var _w_val: Label = get_node("Row/Right/Grid/WHBox/WValue") as Label
@onready var _a_val: Label = get_node("Row/Right/Grid/AHBox/AValue") as Label
@onready var _h_val: Label = get_node("Row/Right/Grid/HHBox/HValue") as Label
@onready var _f_val: Label = get_node("Row/Right/Grid/FHBox/FValue") as Label
@onready var _b_val: Label = get_node("Row/Right/Grid/BHBox/BValue") as Label

@onready var _w_btn: Button = get_node_or_null("Row/Right/Grid/WHBox/WBtn") as Button
@onready var _a_btn: Button = get_node_or_null("Row/Right/Grid/AHBox/ABtn") as Button
@onready var _h_btn: Button = get_node_or_null("Row/Right/Grid/HHBox/HBtn") as Button
@onready var _f_btn: Button = get_node_or_null("Row/Right/Grid/FHBox/FBtn") as Button
@onready var _b_btn: Button = get_node_or_null("Row/Right/Grid/BHBox/BBtn") as Button

@onready var _sigils_title: Label         = get_node_or_null("Row/Right/Sigils/Title") as Label
@onready var _sigils_list:  VBoxContainer = get_node_or_null("Row/Right/Sigils/List") as VBoxContainer
@onready var _btn_manage:   Button        = get_node_or_null("Row/Right/Buttons/BtnManageSigils") as Button

@onready var _stats_grid:  GridContainer = get_node("Row/StatsColumn/StatsGrid") as GridContainer
@onready var _mind_value:  Label         = get_node_or_null("Row/Right/MindRow/Value") as Label
@onready var _mind_row:    HBoxContainer = get_node_or_null("Row/Right/MindRow") as HBoxContainer

@onready var _active_name_lbl:  Label  = %ActiveNameLabel
@onready var _active_value_lbl: Label  = %ActiveValueLabel
@onready var _active_btn:       Button = %ActiveBtn

var _labels: PackedStringArray = PackedStringArray()
var _tokens: PackedStringArray = PackedStringArray()

var _gs:    Node = null
var _inv:   Node = null
var _sig:   Node = null
var _eq:    Node = null
var _stats: Node = null

const _SLOTS: Array[String] = ["weapon", "armor", "head", "foot", "bracelet"]
const STATS_FONT_SIZE: int = 9

# Skills menu scene lookup
const _SIGIL_MENU_SCENE_PATHS: Array[String] = [
	"res://SigilSkillMenu.tscn",
	"res://ui/sigils/SigilSkillMenu.tscn",
	"res://scenes/main_menu/panels/SigilSkillMenu.tscn",
	"res://ui/SigilSkillMenu.tscn",
]

# change tracking (for cheap polling fallback)
var _party_sig: String = ""
var _sigils_sig: String = ""
var _poll_accum: float = 0.0

# Controller navigation state - Simple state machine
enum NavState { PARTY_SELECT, EQUIPMENT_NAV, POPUP_ACTIVE }
var _nav_state: NavState = NavState.PARTY_SELECT
var _nav_elements: Array[Control] = []  # Ordered list of focusable elements in equipment mode
var _nav_index: int = 0  # Current selection index in equipment mode
var _active_popup: Control = null  # Currently open equipment popup panel

func _ready() -> void:
	super()  # Call PanelBase._ready()

	_gs    = get_node_or_null("/root/aGameState")
	_inv   = get_node_or_null("/root/aInventorySystem")
	_sig   = get_node_or_null("/root/aSigilSystem")
	_eq    = get_node_or_null("/root/aEquipmentSystem")
	_stats = get_node_or_null("/root/aStatsSystem")

	if _w_btn: _w_btn.pressed.connect(Callable(self, "_on_slot_button").bind("weapon"))
	if _a_btn: _a_btn.pressed.connect(Callable(self, "_on_slot_button").bind("armor"))
	if _h_btn: _h_btn.pressed.connect(Callable(self, "_on_slot_button").bind("head"))
	if _f_btn: _f_btn.pressed.connect(Callable(self, "_on_slot_button").bind("foot"))
	if _b_btn: _b_btn.pressed.connect(Callable(self, "_on_slot_button").bind("bracelet"))

	if not _party_list.item_selected.is_connected(Callable(self, "_on_party_selected")):
		_party_list.item_selected.connect(Callable(self, "_on_party_selected"))

	if _btn_manage and not _btn_manage.pressed.is_connected(Callable(self, "_on_manage_sigils")):
		_btn_manage.pressed.connect(Callable(self, "_on_manage_sigils"))

	if _eq and _eq.has_signal("equipment_changed"):
		if not _eq.is_connected("equipment_changed", Callable(self, "_on_equipment_changed")):
			_eq.connect("equipment_changed", Callable(self, "_on_equipment_changed"))

	if _sig and _sig.has_signal("loadout_changed"):
		if not _sig.is_connected("loadout_changed", Callable(self, "_on_sigils_changed")):
			_sig.connect("loadout_changed", Callable(self, "_on_sigils_changed"))

	# Extra refresh hooks (level ups, roster changes)
	_wire_refresh_signals()

	_setup_active_type_widgets()
	call_deferred("_first_fill")

	# polling fallback so UI never goes stale
	set_process(true)

## PanelBase callback - Called when LoadoutPanel gains focus
func _on_panel_gained_focus() -> void:
	super()  # Call parent
	print("[LoadoutPanel] Panel gained focus - state: %s" % NavState.keys()[_nav_state])

	# Restore focus based on current navigation state
	match _nav_state:
		NavState.PARTY_SELECT:
			print("[LoadoutPanel] Calling deferred _enter_party_select_state")
			call_deferred("_enter_party_select_state")
		NavState.EQUIPMENT_NAV:
			print("[LoadoutPanel] Calling deferred _restore_equipment_focus")
			call_deferred("_restore_equipment_focus")
		NavState.POPUP_ACTIVE:
			# Popup will handle its own focus when it's the active panel
			print("[LoadoutPanel] In POPUP_ACTIVE state, popup handles focus")
			pass

## PanelBase callback - Called when LoadoutPanel loses focus
func _on_panel_lost_focus() -> void:
	super()  # Call parent
	print("[LoadoutPanel] Panel lost focus - state: %s" % NavState.keys()[_nav_state])
	# Don't auto-close popup - it's managed by panel stack
	# Don't change state - preserve it for when we regain focus

func _first_fill() -> void:
	_refresh_party()
	if _party_list.get_item_count() > 0:
		_party_list.select(0)
		_on_party_selected(0)
	_party_sig = _snapshot_party_signature()
	var cur := _current_token()
	_sigils_sig = _snapshot_sigil_signature(cur) if cur != "" else ""

# ────────────────── tiny util ──────────────────
func _connect_if(n: Object, sig: String, cb: Callable) -> void:
	if n and n.has_signal(sig):
		if not n.is_connected(sig, cb):
			n.connect(sig, cb)

func _wire_refresh_signals() -> void:
	# Instance XP/Level changes (canonical signal name)
	_connect_if(_sig, "instance_xp_changed",    Callable(self, "_on_sigil_instances_updated"))
	# Plus some aliases in case your system exposes them
	_connect_if(_sig, "sigils_changed",         Callable(self, "_on_sigil_instances_updated"))
	_connect_if(_sig, "sigil_instance_changed", Callable(self, "_on_sigil_instances_updated"))
	_connect_if(_sig, "sigil_level_changed",    Callable(self, "_on_sigil_instances_updated"))
	_connect_if(_sig, "sigil_xp_changed",       Callable(self, "_on_sigil_instances_updated"))

	# Party / roster updates
	_connect_if(_gs,  "party_changed",          Callable(self, "_on_party_roster_changed"))
	_connect_if(_gs,  "active_party_changed",   Callable(self, "_on_party_roster_changed"))
	_connect_if(_gs,  "roster_changed",         Callable(self, "_on_party_roster_changed"))
	_connect_if(_gs,  "member_joined",          Callable(self, "_on_party_roster_changed"))
	_connect_if(_gs,  "member_removed",         Callable(self, "_on_party_roster_changed"))

	# Derived stats bump (level-ups etc.)
	_connect_if(_stats, "stats_changed",        Callable(self, "_on_stats_changed"))

func _refresh_all_for_current() -> void:
	"""Refresh all display elements for currently selected party member
	Preserves navigation state (_nav_state and _nav_index)"""
	var cur: String = _current_token()
	if cur == "":
		return

	var equip: Dictionary = _fetch_equip_for(cur)
	_set_slot_value(_w_val, String(equip.get("weapon","")), "weapon")
	_set_slot_value(_a_val, String(equip.get("armor","")), "armor")
	_set_slot_value(_h_val, String(equip.get("head","")), "head")
	_set_slot_value(_f_val, String(equip.get("foot","")), "foot")
	_set_slot_value(_b_val, String(equip.get("bracelet","")), "bracelet")
	_rebuild_stats_grid(cur, equip)
	_rebuild_sigils(cur)
	_refresh_mind_row(cur)
	_refresh_active_type_row(cur)

	# Rebuild navigation elements if in equipment mode
	# This preserves _nav_state and _nav_index
	if _nav_state == NavState.EQUIPMENT_NAV:
		call_deferred("_rebuild_equipment_navigation_and_restore_focus")

func _on_sigil_instances_updated(_a=null,_b=null,_c=null) -> void:
	_refresh_all_for_current()

func _on_stats_changed() -> void:
	_refresh_all_for_current()

func _on_party_roster_changed(_arg=null) -> void:
	var keep: String = _current_token()
	_refresh_party()
	var idx: int = max(0, _tokens.find(keep))
	if _party_list.get_item_count() > 0:
		_party_list.select(idx)
		_on_party_selected(idx)
	_party_sig = _snapshot_party_signature()

# ────────────────── party ──────────────────
func _hero_name() -> String:
	var s: String = ""
	if _gs and _gs.has_method("get"):
		s = String(_gs.get("player_name"))
	if s.strip_edges() == "":
		s = "Player"
	return s

func _gather_party_tokens() -> Array[String]:
	var out: Array[String] = []
	if _gs == null:
		return out

	# Get active party members
	for m in ["get_active_party_ids", "get_party_ids", "list_active_party", "get_active_party"]:
		if _gs.has_method(m):
			var raw: Variant = _gs.call(m)
			if typeof(raw) == TYPE_PACKED_STRING_ARRAY:
				for s in (raw as PackedStringArray): out.append(String(s))
			elif typeof(raw) == TYPE_ARRAY:
				for s2 in (raw as Array): out.append(String(s2))
			if out.size() > 0: break

	if out.is_empty():
		for p in ["active_party_ids", "active_party", "party_ids", "party"]:
			var raw2: Variant = _gs.get(p) if _gs.has_method("get") else null
			if typeof(raw2) == TYPE_PACKED_STRING_ARRAY:
				for s3 in (raw2 as PackedStringArray): out.append(String(s3))
			elif typeof(raw2) == TYPE_ARRAY:
				for s4 in (raw2 as Array): out.append(String(s4))
			if out.size() > 0: break

	# Get benched members
	if _gs.has_method("get"):
		var bench_v: Variant = _gs.get("bench")
		if typeof(bench_v) == TYPE_PACKED_STRING_ARRAY:
			for s in (bench_v as PackedStringArray):
				if not out.has(String(s)):  # Avoid duplicates
					out.append(String(s))
		elif typeof(bench_v) == TYPE_ARRAY:
			for s in (bench_v as Array):
				if not out.has(String(s)):  # Avoid duplicates
					out.append(String(s))

	return out

func _refresh_party() -> void:
	_party_list.clear()
	_labels = PackedStringArray()
	_tokens = PackedStringArray()

	var tokens: Array[String] = _gather_party_tokens()
	var entries: Array = []

	for t in tokens:
		var tok: String = String(t)
		entries.append({"key": tok, "label": _display_for_token(tok)})

	if entries.is_empty():
		entries.append({"key": "hero", "label": _hero_name()})

	var seen: Dictionary = {}
	for e_v in entries:
		if typeof(e_v) != TYPE_DICTIONARY: continue
		var e: Dictionary = e_v
		var key: String = String(e.get("key",""))
		var label: String = String(e.get("label",""))
		if key == "" and label == "": continue
		var uniq: String = key + "@" + label
		if not seen.has(uniq):
			seen[uniq] = true
			_tokens.append(key if key != "" else label)
			_labels.append(label if label != "" else key)

	if _labels.is_empty():
		_tokens.append("hero")
		_labels.append(_hero_name())

	for i in range(_labels.size()):
		_party_list.add_item(_labels[i])

	_party_list.queue_redraw()

func _display_for_token(token: String) -> String:
	if token == "hero":
		return _hero_name()
	if _gs and _gs.has_method("_display_name_for_id"):
		var v: Variant = _gs.call("_display_name_for_id", token)
		if typeof(v) == TYPE_STRING and String(v) != "":
			return String(v)
	return token.capitalize()

func _current_token() -> String:
	var sel: PackedInt32Array = _party_list.get_selected_items()
	if sel.size() == 0:
		return (_tokens[0] if _tokens.size() > 0 else "")
	var i: int = sel[0]
	return (_tokens[i] if i >= 0 and i < _tokens.size() else "")

func _on_party_selected(index: int) -> void:
	var label: String = "(Unknown)"
	if index >= 0 and index < _labels.size():
		label = _labels[index]
	_member_name.text = label

	_refresh_all_for_current()
	_sigils_sig = _snapshot_sigil_signature(_current_token())

func _on_equipment_changed(member: String) -> void:
	var cur: String = _current_token()
	if cur == "" or cur.to_lower() != member.to_lower():
		return
	_refresh_all_for_current()

func _on_sigils_changed(member: String) -> void:
	var cur: String = _current_token()
	if cur == "" or cur.to_lower() != member.to_lower():
		return
	_refresh_all_for_current()
	_sigils_sig = _snapshot_sigil_signature(cur)

# ────────────────── equip menu ──────────────────
func _on_slot_button(slot: String) -> void:
	var token: String = _current_token()
	if token == "":
		return
	_show_item_menu_for_slot(token, slot)

func _show_item_menu_for_slot(member_token: String, slot: String) -> void:
	# Prevent multiple popups from being created simultaneously
	if _active_popup and is_instance_valid(_active_popup):
		print("[LoadoutPanel] Popup already open, ignoring request")
		return

	var items: PackedStringArray = _list_equippable(member_token, slot)
	var cur: Dictionary = _fetch_equip_for(member_token)
	var cur_id: String = String(cur.get(slot, ""))

	# Create custom popup using Control nodes for proper controller support
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.z_index = 100
	add_child(popup_panel)

	# Set active popup immediately to prevent multiple popups during async operations
	_active_popup = popup_panel

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	popup_panel.add_child(vbox)

	# Title label
	var title: Label = Label.new()
	title.text = "Select %s" % slot.capitalize()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Item list
	var item_list: ItemList = ItemList.new()
	item_list.custom_minimum_size = Vector2(280, 200)
	item_list.focus_mode = Control.FOCUS_ALL
	vbox.add_child(item_list)

	# Build item list data
	var item_ids: Array[String] = []

	# Add unequip option if something is equipped
	if cur_id != "" and cur_id != "—":
		item_list.add_item("← Unequip")
		item_ids.append("")  # Empty string = unequip

	# Add available items
	if items.is_empty():
		item_list.add_item("(No items available)")
		item_list.set_item_disabled(item_list.item_count - 1, true)
		item_ids.append("")
	else:
		for id in items:
			var label: String = _pretty_item(id)
			item_list.add_item(label)
			item_ids.append(id)

	# Add back button
	var back_btn: Button = Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(_popup_cancel)
	vbox.add_child(back_btn)

	# Auto-size panel to fit content
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0
	print("[LoadoutPanel] Popup centered at: %s, size: %s" % [popup_panel.position, popup_panel.size])

	# Select first item and grab focus
	if item_list.item_count > 0:
		var first_enabled = 0
		for i in range(item_list.item_count):
			if not item_list.is_item_disabled(i):
				first_enabled = i
				break
		item_list.select(first_enabled)
		item_list.grab_focus()

	# Store metadata for controller input (popup reference already set earlier)
	popup_panel.set_meta("_item_list", item_list)
	popup_panel.set_meta("_item_ids", item_ids)
	popup_panel.set_meta("_member_token", member_token)
	popup_panel.set_meta("_slot", slot)

	# Push popup to aPanelManager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		# Make popup a "fake panel" that aPanelManager can track
		popup_panel.set_meta("_is_equipment_popup", true)
		panel_mgr.push_panel(popup_panel)
		print("[LoadoutPanel] Pushed equipment popup to aPanelManager stack")

	# Set state to POPUP_ACTIVE
	_nav_state = NavState.POPUP_ACTIVE

	print("[LoadoutPanel] Equipment popup opened for %s - %d items" % [slot, item_ids.size()])

# ────────────────── sigils ──────────────────
func _sigil_disp(inst_id: String) -> String:
	var result: String = "(empty)"
	if inst_id == "":
		return result

	# name comes from base; level/star from instance
	var base_id: String = inst_id
	if _sig and _sig.has_method("get_base_from_instance"):
		base_id = String(_sig.call("get_base_from_instance", inst_id))

	var disp_name: String = base_id
	if _sig and _sig.has_method("get_display_name_for"):
		var n_v: Variant = _sig.call("get_display_name_for", base_id)
		if typeof(n_v) == TYPE_STRING:
			disp_name = String(n_v)

	var lv: int = 1
	if _sig and _sig.has_method("get_instance_level"):
		lv = int(_sig.call("get_instance_level", inst_id))

	var lv_str: String = ("MAX" if lv >= 4 else "Lv %d" % lv)

	var star: String = ""
	if _sig and _sig.has_method("get_active_skill_name_for_instance"):
		var a_v: Variant = _sig.call("get_active_skill_name_for_instance", inst_id)
		if typeof(a_v) == TYPE_STRING and String(a_v).strip_edges() != "":
			star = "  —  ★ " + String(a_v)

	result = "%s  (%s)%s" % [disp_name, lv_str, star]
	return result

func _rebuild_sigils(member_token: String) -> void:
	if _sigils_list == null:
		return
	for c in _sigils_list.get_children():
		c.queue_free()

	var cap: int = 0
	var sockets: PackedStringArray = PackedStringArray()
	if _sig:
		if _sig.has_method("get_capacity"): cap = int(_sig.call("get_capacity", member_token))
		if _sig.has_method("get_loadout"):
			var v2: Variant = _sig.call("get_loadout", member_token)
			if typeof(v2) == TYPE_PACKED_STRING_ARRAY:
				sockets = v2 as PackedStringArray
			elif typeof(v2) == TYPE_ARRAY:
				for s in (v2 as Array): sockets.append(String(s))

	var used: int = 0
	for s in sockets:
		if String(s) != "": used += 1

	if _sigils_title:
		_sigils_title.text = "Sigils  (%d/%d)" % [used, cap]

	if cap <= 0:
		var none: Label = Label.new()
		none.text = "No bracelet slots"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD
		_sigils_list.add_child(none)
		return

	for idx in range(cap):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var nm: Label = Label.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var cur_id: String = (String(sockets[idx]) if idx < sockets.size() else "")
		nm.text = (_sigil_disp(cur_id) if cur_id != "" else "(empty)")
		row.add_child(nm)

		# Always show "Equip…" button - popup will handle unequip option
		var btn: Button = Button.new()
		btn.text = "Equip…"
		btn.pressed.connect(Callable(self, "_on_equip_sigil").bind(member_token, idx))
		row.add_child(btn)

		_sigils_list.add_child(row)

	if _btn_manage:
		_btn_manage.disabled = false

func _on_equip_sigil(member_token: String, socket_index: int) -> void:
	"""Open sigil picker for a specific socket"""
	if _sig == null:
		return
	_show_sigil_picker_for_socket(member_token, socket_index)

func _show_sigil_picker_for_socket(member_token: String, socket_index: int) -> void:
	"""Show sigil picker popup using Panel-based system for controller support"""
	# Prevent multiple popups
	if _active_popup and is_instance_valid(_active_popup):
		print("[LoadoutPanel] Popup already open, ignoring sigil picker request")
		return

	print("[LoadoutPanel] === Opening Sigil Picker for %s, socket %d ===" % [member_token, socket_index])

	# Get member's mind type for debugging
	var member_mind := ""
	if _sig and _sig.has_method("resolve_member_mind_base"):
		member_mind = String(_sig.call("resolve_member_mind_base", member_token))
	print("[LoadoutPanel] Member mind type: %s" % member_mind)

	# Helper: allowed?
	var _allowed := func(school: String) -> bool:
		# Empty school means unknown - skip to be safe
		if school.strip_edges() == "":
			return false
		if _sig and _sig.has_method("is_school_allowed_for_member"):
			var allowed: bool = bool(_sig.call("is_school_allowed_for_member", member_token, school))
			return allowed
		# If no filtering method exists, allow all non-empty schools
		return true

	# Gather free instances and filter by mind type
	var free_instances_all := PackedStringArray()
	if _sig.has_method("list_free_instances"):
		var v0: Variant = _sig.call("list_free_instances")
		if typeof(v0) == TYPE_PACKED_STRING_ARRAY:
			free_instances_all = v0 as PackedStringArray
		elif typeof(v0) == TYPE_ARRAY:
			for s in (v0 as Array): free_instances_all.append(String(s))

	print("[LoadoutPanel] Found %d free instances total" % free_instances_all.size())

	var free_instances := PackedStringArray()
	for inst in free_instances_all:
		var school := ""
		if _sig.has_method("get_element_for_instance"):
			school = String(_sig.call("get_element_for_instance", inst))
		elif _sig.has_method("get_mind_for_instance"):
			school = String(_sig.call("get_mind_for_instance", inst))
		else:
			var base := (String(_sig.call("get_base_from_instance", inst)) if _sig.has_method("get_base_from_instance") else inst)
			if _sig.has_method("get_element_for"):
				school = String(_sig.call("get_element_for", base))

		var allowed: bool = _allowed.call(school)
		if allowed:
			free_instances.append(inst)
			print("[LoadoutPanel]   ✓ Instance: %s (school: %s)" % [_sigil_disp(inst), school])
		else:
			print("[LoadoutPanel]   ✗ Filtered out: %s (school: %s)" % [_sigil_disp(inst), school])

	# Gather base sigils from inventory and filter by mind type
	var base_ids_all := _collect_base_sigils()
	print("[LoadoutPanel] Found %d base sigils in inventory" % base_ids_all.size())

	var base_ids := PackedStringArray()
	for base in base_ids_all:
		var school := ""
		if _sig.has_method("get_element_for"):
			school = String(_sig.call("get_element_for", base))
		elif _sig.has_method("get_mind_for"):
			school = String(_sig.call("get_mind_for", base))

		var allowed: bool = _allowed.call(school)
		if allowed:
			base_ids.append(base)
			var label: String = (String(_sig.call("get_display_name_for", base)) if (_sig and _sig.has_method("get_display_name_for")) else base)
			print("[LoadoutPanel]   ✓ Base: %s (school: %s)" % [label, school])
		else:
			var label: String = (String(_sig.call("get_display_name_for", base)) if (_sig and _sig.has_method("get_display_name_for")) else base)
			print("[LoadoutPanel]   ✗ Filtered out: %s (school: %s)" % [label, school])

	# Create custom popup using Control nodes for proper controller support
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.z_index = 100
	add_child(popup_panel)

	# Set active popup immediately to prevent multiple popups
	_active_popup = popup_panel

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	popup_panel.add_child(vbox)

	# Title label
	var title: Label = Label.new()
	title.text = "Select Sigil (Socket %d)" % (socket_index + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Item list
	var item_list: ItemList = ItemList.new()
	item_list.custom_minimum_size = Vector2(300, 250)
	item_list.focus_mode = Control.FOCUS_ALL
	vbox.add_child(item_list)

	# Build item list with metadata
	var item_metadata: Array[Dictionary] = []

	# Add unequip option (check if socket has sigil)
	var current_sigils: Array = []
	if _sig.has_method("get_loadout"):
		var loadout: Variant = _sig.call("get_loadout", member_token)
		if typeof(loadout) == TYPE_ARRAY:
			current_sigils = loadout as Array

	if socket_index < current_sigils.size() and current_sigils[socket_index] != "":
		item_list.add_item("← Unequip")
		item_metadata.append({"kind": "unequip", "id": ""})

	# Add unslotted instances
	if free_instances.size() > 0:
		item_list.add_item("— Unslotted Instances —")
		item_list.set_item_disabled(item_list.item_count - 1, true)
		item_metadata.append({})  # Placeholder for disabled header

		for inst in free_instances:
			item_list.add_item(_sigil_disp(inst))
			item_metadata.append({"kind": "inst", "id": inst})

	# Add base sigils from inventory
	if base_ids.size() > 0:
		item_list.add_item("— From Inventory —")
		item_list.set_item_disabled(item_list.item_count - 1, true)
		item_metadata.append({})  # Placeholder for disabled header

		for base in base_ids:
			var label2: String = (String(_sig.call("get_display_name_for", base)) if (_sig and _sig.has_method("get_display_name_for")) else _pretty_item(base))
			item_list.add_item(label2)
			item_metadata.append({"kind": "base", "id": base})

	# Add fallback if no items
	if item_list.item_count == 0:
		item_list.add_item("(No sigils available)")
		item_list.set_item_disabled(0, true)
		item_metadata.append({})

	# Add back button
	var back_btn: Button = Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(_popup_cancel)
	vbox.add_child(back_btn)

	# Auto-size panel to fit content
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0
	print("[LoadoutPanel] Sigil popup centered at: %s, size: %s" % [popup_panel.position, popup_panel.size])

	# Select first enabled item and grab focus
	if item_list.item_count > 0:
		var first_enabled = 0
		for i in range(item_list.item_count):
			if not item_list.is_item_disabled(i):
				first_enabled = i
				break
		item_list.select(first_enabled)
		item_list.grab_focus()

	# Store metadata for controller input
	popup_panel.set_meta("_is_sigil_popup", true)
	popup_panel.set_meta("_item_list", item_list)
	popup_panel.set_meta("_item_metadata", item_metadata)
	popup_panel.set_meta("_member_token", member_token)
	popup_panel.set_meta("_socket_index", socket_index)

	# Push popup to aPanelManager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.push_panel(popup_panel)
		print("[LoadoutPanel] Pushed sigil popup to aPanelManager stack")

	# Set state to POPUP_ACTIVE
	_nav_state = NavState.POPUP_ACTIVE

	# Summary
	var has_unequip: bool = (socket_index < current_sigils.size() and current_sigils[socket_index] != "")
	print("[LoadoutPanel] Sigil popup opened for socket %d:" % socket_index)
	print("[LoadoutPanel]   - Has current sigil: %s" % has_unequip)
	print("[LoadoutPanel]   - Free instances: %d" % free_instances.size())
	print("[LoadoutPanel]   - Base sigils: %d" % base_ids.size())
	print("[LoadoutPanel]   - Total items in list: %d" % item_list.item_count)
	print("[LoadoutPanel] ===================================")

func _on_remove_sigil(member_token: String, socket_index: int) -> void:
	if _sig and _sig.has_method("remove_sigil_at"):
		_sig.call("remove_sigil_at", member_token, socket_index)
	_on_sigils_changed(member_token)

func _collect_base_sigils() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _inv == null:
		return out

	var defs: Dictionary = {}
	var counts: Dictionary = {}
	if _inv.has_method("get_item_defs"):
		var d_v: Variant = _inv.call("get_item_defs")
		if typeof(d_v) == TYPE_DICTIONARY: defs = d_v as Dictionary
	if _inv.has_method("get_counts_dict"):
		var c_v: Variant = _inv.call("get_counts_dict")
		if typeof(c_v) == TYPE_DICTIONARY: counts = c_v as Dictionary

	for id_v in counts.keys():
		var id: String = String(id_v)
		if int(counts.get(id, 0)) <= 0: continue
		var rec: Dictionary = defs.get(id, {}) as Dictionary
		var tag: String = ""
		for k in ["equip_slot","slot","equip","equip_to","category","cat","type"]:
			if rec.has(k) and typeof(rec[k]) == TYPE_STRING:
				tag = String(rec[k]).strip_edges().to_lower()
				break
		if tag == "sigil" or tag == "sigils":
			out.append(id)
	return out

# ────────────────── stats / mind ──────────────────
func _get_member_mind_type(member_token: String) -> String:
	if _sig and _sig.has_method("resolve_member_mind_base"):
		var v: Variant = _sig.call("resolve_member_mind_base", member_token)
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "": return String(v)
	if _gs and _gs.has_method("get_member_field"):
		var v2: Variant = _gs.call("get_member_field", member_token, "mind_type")
		if typeof(v2) == TYPE_STRING and String(v2).strip_edges() != "": return String(v2)
	return "Omega"

func _refresh_mind_row(member_token: String) -> void:
	if _mind_value == null: return
	var mt: String = _get_member_mind_type(member_token)
	_mind_value.text = (mt if mt != "" else "—")

func _fetch_equip_for(member_token: String) -> Dictionary:
	if _gs and _gs.has_method("get_member_equip"):
		var d_v: Variant = _gs.call("get_member_equip", member_token)
		if typeof(d_v) == TYPE_DICTIONARY:
			var d: Dictionary = d_v
			if d.has("feet") and not d.has("foot"): d["foot"] = String(d["feet"])
			for k in _SLOTS:
				if not d.has(k): d[k] = ""
			return d
	return {"weapon":"","armor":"","head":"","foot":"","bracelet":""}

func _pretty_item(id: String) -> String:
	if id == "" or id == "—": return "—"
	if _eq and _eq.has_method("get_item_display_name"):
		var v: Variant = _eq.call("get_item_display_name", id)
		if typeof(v) == TYPE_STRING: return String(v)
	return id

func _set_slot_value(label: Label, id: String, slot: String) -> void:
	if label == null:
		return

	if id == "" or id == "—":
		# Empty slot - show placeholder with grey color
		var placeholder: String = ""
		match slot:
			"weapon": placeholder = "(Weapon)"
			"armor": placeholder = "(Armor)"
			"head": placeholder = "(Headwear)"
			"foot": placeholder = "(Footwear)"
			"bracelet": placeholder = "(Bracelet)"
			_: placeholder = "—"

		label.text = placeholder
		# Set grey color using theme override
		label.add_theme_color_override("font_color", Color(0.533, 0.533, 0.533))
	else:
		# Has equipment - show item name with light blue color
		var item_name: String = id
		if _eq and _eq.has_method("get_item_display_name"):
			var v: Variant = _eq.call("get_item_display_name", id)
			if typeof(v) == TYPE_STRING: item_name = String(v)

		label.text = item_name
		# Set light blue color for equipped items
		label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))

func _list_equippable(member_token: String, slot: String) -> PackedStringArray:
	if _eq and _eq.has_method("list_equippable"):
		var v2: Variant = _eq.call("list_equippable", member_token, slot)
		if typeof(v2) == TYPE_PACKED_STRING_ARRAY: return v2 as PackedStringArray
		if typeof(v2) == TYPE_ARRAY:
			var out2: PackedStringArray = PackedStringArray()
			for e2 in (v2 as Array): out2.append(String(e2))
			return out2
	return PackedStringArray()

func _clear_stats_grid() -> void:
	if _stats_grid == null: return
	for c in _stats_grid.get_children():
		c.queue_free()

func _label_cell(txt: String) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", STATS_FONT_SIZE)
	return l

func _value_cell(txt: String) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", STATS_FONT_SIZE)
	return l

func _fmt_num(n: float) -> String:
	var as_int: int = int(round(n))
	return str(as_int) if abs(n - float(as_int)) < 0.0001 else str(snapped(n, 0.1))

func _stat_for_member(member_token: String, s: String) -> int:
	if _gs and _gs.has_method("get_member_stat"):
		return int(_gs.call("get_member_stat", member_token, s))
	return 1

func _item_def(id: String) -> Dictionary:
	var empty: Dictionary = {}
	if id == "" or id == "—": return empty
	if _eq and _eq.has_method("get_item_def"):
		var v: Variant = _eq.call("get_item_def", id)
		if typeof(v) == TYPE_DICTIONARY: return v as Dictionary
	if _inv and _inv.has_method("get_item_defs"):
		var d: Variant = _inv.call("get_item_defs")
		if typeof(d) == TYPE_DICTIONARY:
			var defs: Dictionary = d
			return defs.get(id, empty) as Dictionary
	return empty

func _eva_mods_from_other(equip: Dictionary, exclude_id: String) -> int:
	var sum: int = 0
	for k in ["weapon","armor","head","bracelet"]:
		var id: String = String(equip.get(k,""))
		if id == "" or id == exclude_id: continue
		var d: Dictionary = _item_def(id)
		if d.has("base_eva"):
			sum += int(d.get("base_eva",0))
	return sum

func _rebuild_stats_grid(member_token: String, equip: Dictionary) -> void:
	if _stats_grid == null: return
	_clear_stats_grid()

	var lvl: int = 1
	var hp_max: int = 0
	var mp_max: int = 0
	if _gs and _gs.has_method("compute_member_pools"):
		var pools: Dictionary = _gs.call("compute_member_pools", member_token)
		lvl    = int(pools.get("level", 1))
		hp_max = int(pools.get("hp_max", 0))
		mp_max = int(pools.get("mp_max", 0))

	var d_wea:  Dictionary = _item_def(String(equip.get("weapon","")))
	var d_arm:  Dictionary = _item_def(String(equip.get("armor","")))
	var d_head: Dictionary = _item_def(String(equip.get("head","")))
	var d_foot: Dictionary = _item_def(String(equip.get("foot","")))
	var d_brac: Dictionary = _item_def(String(equip.get("bracelet","")))

	var brw: int = _stat_for_member(member_token, "BRW")
	var base_watk: int   = int(d_wea.get("base_watk", 0))
	var scale_brw: float = float(d_wea.get("scale_brw", 0.0))
	var weapon_attack: int = base_watk + int(round(scale_brw * float(brw)))
	var weapon_scale: String = _fmt_num(scale_brw)
	var weapon_acc: int = int(d_wea.get("base_acc", 0))
	var skill_acc_boost: int = int(d_wea.get("skill_acc_boost", 0))
	var crit_bonus: int = int(d_wea.get("crit_bonus_pct", 0))
	var type_raw: String = String(d_wea.get("watk_type_tag","")).strip_edges().to_lower()
	var weapon_type: String = ("Neutral" if (type_raw == "" or type_raw == "wand") else type_raw.capitalize())
	var special: String = ("NL" if _as_bool(d_wea.get("non_lethal", false)) else "—")

	var vtl: int = _stat_for_member(member_token, "VTL")
	var armor_flat: int = int(d_arm.get("armor_flat", 0))
	var pdef: int = int(round(float(armor_flat) * (5.0 + 0.25 * float(vtl))))
	var ail_res: int = int(d_arm.get("ail_resist_pct", 0))

	var fcs: int = _stat_for_member(member_token, "FCS")
	var hp_bonus: int = int(d_head.get("max_hp_boost", 0))
	var mp_bonus: int = int(d_head.get("max_mp_boost", 0))
	var ward_flat: int = int(d_head.get("ward_flat", 0))
	var mdef: int = int(round(float(ward_flat) * (5.0 + 0.25 * float(fcs))))

	var base_eva: int = int(d_foot.get("base_eva", 0))
	var mods: int = _eva_mods_from_other(equip, String(equip.get("foot","")))
	var peva: int = base_eva + int(round(0.25 * float(vtl))) + mods
	var meva: int = base_eva + int(round(0.25 * float(fcs))) + mods
	var speed: int = int(d_foot.get("speed", 0))

	var slots: int = int(d_brac.get("sigil_slots", 0))

	var _pair: Callable = func(lbl: String, val: String) -> void:
		_stats_grid.add_child(_label_cell(lbl))
		_stats_grid.add_child(_value_cell(val))

	# Core stats
	_pair.call("Level", str(lvl))
	_pair.call("HP", str(hp_max))
	_pair.call("MP", str(mp_max))

	# Weapon stats
	if not d_wea.is_empty():
		_pair.call("W.Attack", str(weapon_attack))
		_pair.call("W.Acc", str(weapon_acc))
		_pair.call("W.Type", weapon_type)
		_pair.call("Crit %", str(crit_bonus))
		if skill_acc_boost > 0:
			_pair.call("Skill Acc", str(skill_acc_boost))
		if special != "—":
			_pair.call("Special", special)

	# Armor stats
	if not d_arm.is_empty():
		_pair.call("P.Def", str(pdef))
		_pair.call("Ail.Res %", str(ail_res))

	# Head stats
	if not d_head.is_empty():
		if hp_bonus > 0:
			_pair.call("HP Bonus", str(hp_bonus))
		if mp_bonus > 0:
			_pair.call("MP Bonus", str(mp_bonus))
		_pair.call("M.Def", str(mdef))

	# Foot stats
	if not d_foot.is_empty():
		_pair.call("P.Eva", str(peva))
		_pair.call("M.Eva", str(meva))
		_pair.call("Speed", str(speed))

	# Bracelet stats
	if not d_brac.is_empty():
		_pair.call("Sigils", str(slots))

# ────────────────── Active Type (hero) ──────────────────
func _setup_active_type_widgets() -> void:
	if _active_btn != null and not _active_btn.pressed.is_connected(_open_active_type_picker):
		_active_btn.pressed.connect(_open_active_type_picker)

func _refresh_active_type_row(member_token: String) -> void:
	var is_hero: bool = (member_token == "hero" or member_token.strip_edges().to_lower() == _hero_name().strip_edges().to_lower())
	var do_show: bool = is_hero and _active_name_lbl != null and _active_value_lbl != null and _active_btn != null
	if not do_show:
		if _active_name_lbl:  _active_name_lbl.visible = false
		if _active_value_lbl: _active_value_lbl.visible = false
		if _active_btn:       _active_btn.visible = false
		return

	var cur: String = _get_hero_active_type()
	_active_name_lbl.visible = true
	_active_value_lbl.text = (cur if cur != "" else "Omega")
	_active_value_lbl.visible = true
	_active_btn.visible = true

func _get_hero_active_type() -> String:
	if _gs:
		if _gs.has_meta("hero_active_type"):
			var mv: Variant = _gs.get_meta("hero_active_type")
			if typeof(mv) == TYPE_STRING and String(mv).strip_edges() != "":
				return String(mv)
		if _gs.has_method("get"):
			var v: Variant = _gs.get("hero_active_type")
			if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
				return String(v)
	return "Omega"

func _set_hero_active_type(school: String) -> void:
	var val: String = school.strip_edges()
	if val == "": val = "Omega"
	if _gs:
		_gs.set_meta("hero_active_type", val)
		if _gs.has_method("set"): _gs.set("hero_active_type", val)
	if _stats and _stats.has_signal("stats_changed"): _stats.emit_signal("stats_changed")

func _collect_all_schools() -> Array[String]:
	var out: Array[String] = []
	if _inv and _inv.has_method("get_item_defs"):
		var v: Variant = _inv.call("get_item_defs")
		if typeof(v) == TYPE_DICTIONARY:
			var defs: Dictionary = v
			for id_v in defs.keys():
				var rec: Dictionary = defs[id_v]
				var tag: String = ""
				for k in ["equip_slot","slot","equip","equip_to","category","cat","type"]:
					if rec.has(k) and typeof(rec[k]) == TYPE_STRING:
						tag = String(rec[k]).strip_edges().to_lower()
						break
				if tag != "sigil" and tag != "sigils":
					continue
				for sk in ["sigil_school","school","mind_type","mind_type_tag","mind_tag"]:
					if rec.has(sk) and typeof(rec[sk]) == TYPE_STRING:
						var s: String = String(rec[sk]).strip_edges()
						if s != "":
							var cap: String = s.capitalize()
							if not out.has(cap): out.append(cap)
						break
	if out.is_empty(): out = ["Omega","Fire","Water","Earth","Air","Data","Void"]
	out.sort()
	return out

func _open_active_type_picker() -> void:
	var token: String = _current_token()
	if not (token == "hero" or token.strip_edges().to_lower() == _hero_name().strip_edges().to_lower()):
		return
	var schools: Array[String] = _collect_all_schools()
	var cur: String = _get_hero_active_type()

	var pm: PopupMenu = PopupMenu.new()
	add_child(pm)
	pm.add_item("Omega")
	pm.set_item_metadata(0, "Omega")
	pm.set_item_checked(0, cur.strip_edges().to_lower() == "omega")
	pm.add_separator()
	for s in schools:
		if s == "Omega": continue
		pm.add_item(s)
		pm.set_item_metadata(pm.get_item_count() - 1, s)
		if s.strip_edges().to_lower() == cur.strip_edges().to_lower():
			pm.set_item_checked(pm.get_item_count() - 1, true)

	var _pick: Callable = func(i: int) -> void:
		var meta: Variant = pm.get_item_metadata(i)
		pm.queue_free()
		if typeof(meta) == TYPE_STRING:
			_set_hero_active_type(String(meta))
			_refresh_active_type_row("hero")

	pm.index_pressed.connect(_pick)
	pm.id_pressed.connect(func(idnum: int) -> void:
		_pick.call(pm.get_item_index(idnum))
	)
	pm.popup(Rect2(get_global_mouse_position(), Vector2(200, 0)))

# ────────────────── Manage Sigils action ──────────────────
func _instance_sigil_menu_scene() -> Control:
	for p in _SIGIL_MENU_SCENE_PATHS:
		if ResourceLoader.exists(p):
			var ps: PackedScene = load(p)
			var inst: Node = ps.instantiate()
			if inst is Control:
				return inst as Control
	return SigilSkillMenu.new()

func _on_manage_sigils() -> void:
	var token: String = _current_token()
	if token == "":
		print("[LoadoutPanel] ERROR: Cannot open sigil menu - no member selected")
		return

	print("[LoadoutPanel] Opening sigil menu for member: %s" % token)
	var menu: Control = _instance_sigil_menu_scene()

	# IMPORTANT: Set member BEFORE adding to tree so _ready() has the member set
	if menu.has_method("set_member"):
		menu.call("set_member", token)
		print("[LoadoutPanel] Set member to: %s" % token)

	var layer := CanvasLayer.new()
	layer.layer = 128  # Higher layer to ensure it's on top of pause/menu screens
	layer.name = "SigilMenuLayer"

	get_tree().root.add_child(layer)
	layer.add_child(menu)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure it captures mouse input
	menu.z_index = 1000  # Force high z-index

	if not menu.tree_exited.is_connected(Callable(self, "_on_overlay_closed")):
		menu.tree_exited.connect(Callable(self, "_on_overlay_closed").bind(layer))

	print("[LoadoutPanel] Sigil menu added to tree")
	print("[LoadoutPanel] Menu visible: %s, position: %s, size: %s" % [menu.visible, menu.global_position, menu.size])
	print("[LoadoutPanel] Layer: %d, z_index: %d, mouse_filter: %d" % [layer.layer, menu.z_index, menu.mouse_filter])

	# Debug: Check what else is in the scene tree
	await get_tree().process_frame
	print("[LoadoutPanel] All CanvasLayers in root:")
	for child in get_tree().root.get_children():
		if child is CanvasLayer:
			var cl := child as CanvasLayer
			print("  - %s (layer %d)" % [child.name, cl.layer])

func _on_overlay_closed(layer: CanvasLayer) -> void:
	if is_instance_valid(layer):
		layer.queue_free()
	# In case levels/skills changed while overlay was open
	_refresh_all_for_current()

# ────────────────── polling fallback ──────────────────
func _snapshot_party_signature() -> String:
	return ",".join(_gather_party_tokens())

func _snapshot_sigil_signature(member: String) -> String:
	if _sig and _sig.has_method("get_loadout"):
		var v: Variant = _sig.call("get_loadout", member)
		var arr: Array = (Array(v) if typeof(v) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY] else [])
		var parts: Array[String] = []
		for s in arr:
			var inst: String = String(s)
			if inst == "":
				parts.append("_")
			else:
				var lv: int = (_sig.call("get_instance_level", inst) if (_sig and _sig.has_method("get_instance_level")) else 0)
				parts.append("%s:%d" % [inst, int(lv)])
		return "|".join(parts)
	return ""

func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < 0.5:
		return
	_poll_accum = 0.0

	# Party drift?
	var p_sig := _snapshot_party_signature()
	if p_sig != _party_sig:
		_party_sig = p_sig
		_on_party_roster_changed()
		return

	# Sigil level drift for current
	var cur := _current_token()
	if cur != "":
		var s_sig := _snapshot_sigil_signature(cur)
		if s_sig != _sigils_sig:
			_sigils_sig = s_sig
			_refresh_all_for_current()

func _as_bool(v: Variant) -> bool:
	match typeof(v):
		TYPE_BOOL:   return v
		TYPE_INT:    return int(v) != 0
		TYPE_FLOAT:  return float(v) != 0.0
		TYPE_STRING:
			var s := String(v).strip_edges().to_lower()
			return s in ["true","1","yes","y","on","t"]
		_:           return false

## ═══════════════════════════════════════════════════════════════
## CONTROLLER NAVIGATION - Clean State Machine
## ═══════════════════════════════════════════════════════════════
##
## State Flow:
##   PARTY_SELECT → (Accept) → EQUIPMENT_NAV → (Equip btn) → POPUP_ACTIVE
##   POPUP_ACTIVE → (Accept/Back) → EQUIPMENT_NAV
##   EQUIPMENT_NAV → (Back) → PARTY_SELECT
##   PARTY_SELECT → (Back) → Pop panel (exit to StatusPanel)
##
## ═══════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	"""Single entry point for all controller input - Clean state machine

	Uses _input() instead of _unhandled_input() to have same priority as GameMenu,
	allowing us to mark input as handled before GameMenu intercepts it.
	"""

	# STATE 1: POPUP_ACTIVE - Handle accept/back, let navigation pass to ItemList
	if _nav_state == NavState.POPUP_ACTIVE:
		_handle_popup_input(event)
		# NOTE: _handle_popup_input decides which inputs to mark as handled
		# Navigation (up/down) is NOT marked as handled, so ItemList can navigate
		return

	# Only handle input if we're the active panel
	if not is_active():
		return

	# STATE 2: PARTY_SELECT
	if _nav_state == NavState.PARTY_SELECT:
		_handle_party_select_input(event)
		return

	# STATE 3: EQUIPMENT_NAV
	if _nav_state == NavState.EQUIPMENT_NAV:
		_handle_equipment_nav_input(event)
		return

## ─────────────────────── STATE 1: POPUP_ACTIVE ───────────────────────

func _handle_popup_input(event: InputEvent) -> void:
	"""Handle input when popup is active (equipment or sigil)

	Only intercept accept/back - let navigation (up/down) pass to ItemList
	"""
	if event.is_action_pressed("menu_accept"):
		# Route to appropriate handler based on popup type
		if _active_popup and _active_popup.get_meta("_is_sigil_popup", false):
			_popup_accept_sigil()
		else:
			_popup_accept_item()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		_popup_cancel()
		get_viewport().set_input_as_handled()
	# NOTE: Do NOT handle move_up/move_down here - let ItemList handle its own navigation

func _popup_accept_item() -> void:
	"""User pressed accept on popup - equip the selected item"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	var item_list: ItemList = _active_popup.get_meta("_item_list", null)
	var item_ids: Array = _active_popup.get_meta("_item_ids", [])
	var member_token: String = _active_popup.get_meta("_member_token", "")
	var slot: String = _active_popup.get_meta("_slot", "")

	if not item_list:
		_popup_cancel()
		return

	var selected = item_list.get_selected_items()
	if selected.is_empty():
		print("[LoadoutPanel] No item selected - closing popup")
		_popup_cancel()
		return

	var idx: int = selected[0]
	if idx < 0 or idx >= item_ids.size():
		print("[LoadoutPanel] Invalid selection index")
		_popup_cancel()
		return

	var item_id: String = item_ids[idx]
	print("[LoadoutPanel] Equipping: '%s' to %s" % [item_id, slot])

	# Equip the item
	if item_id == "":
		# Unequip
		if _eq and _eq.has_method("unequip_slot"):
			_eq.call("unequip_slot", member_token, slot)
	else:
		# Equip
		if _eq and _eq.has_method("equip_item"):
			_eq.call("equip_item", member_token, item_id)

	# Special bracelet handling
	if slot == "bracelet" and _sig and _sig.has_method("on_bracelet_changed"):
		_sig.call("on_bracelet_changed", member_token)

	# Close popup and return to EQUIPMENT_NAV (stay at same position!)
	_popup_close_and_return_to_equipment()

func _popup_accept_sigil() -> void:
	"""User pressed accept on sigil popup - equip/unequip the selected sigil"""
	if not _active_popup or not is_instance_valid(_active_popup):
		print("[LoadoutPanel] ERROR: No active popup")
		return

	var item_list: ItemList = _active_popup.get_meta("_item_list", null)
	var item_metadata: Array = _active_popup.get_meta("_item_metadata", [])
	var member_token: String = _active_popup.get_meta("_member_token", "")
	var socket_index: int = _active_popup.get_meta("_socket_index", -1)

	if not item_list or socket_index < 0:
		print("[LoadoutPanel] ERROR: Invalid popup metadata")
		_popup_cancel()
		return

	var selected = item_list.get_selected_items()
	if selected.is_empty():
		print("[LoadoutPanel] No sigil selected - closing popup")
		_popup_cancel()
		return

	var idx: int = selected[0]
	if idx < 0 or idx >= item_metadata.size():
		print("[LoadoutPanel] ERROR: Invalid selection index %d (metadata size: %d)" % [idx, item_metadata.size()])
		_popup_cancel()
		return

	var meta: Dictionary = item_metadata[idx]
	var kind: String = meta.get("kind", "")
	var id: String = meta.get("id", "")

	print("[LoadoutPanel] === Sigil Equip Action ===" )
	print("[LoadoutPanel]   Member: %s" % member_token)
	print("[LoadoutPanel]   Socket: %d" % socket_index)
	print("[LoadoutPanel]   Kind: %s" % kind)
	print("[LoadoutPanel]   ID: %s" % id)

	# Handle unequip
	if kind == "unequip":
		print("[LoadoutPanel] Unequipping sigil from socket %d" % socket_index)
		if _sig and _sig.has_method("remove_sigil_at"):
			_sig.call("remove_sigil_at", member_token, socket_index)
			print("[LoadoutPanel] ✓ Sigil unequipped")
		else:
			print("[LoadoutPanel] ✗ remove_sigil_at method not available")
		_on_sigils_changed(member_token)
		_popup_close_and_return_to_equipment()
		return

	# Handle instance equip
	if kind == "inst":
		print("[LoadoutPanel] Equipping instance: %s" % id)
		if _sig and _sig.has_method("equip_into_socket"):
			var ok: bool = bool(_sig.call("equip_into_socket", member_token, socket_index, id))
			if ok:
				print("[LoadoutPanel] ✓ Instance equipped successfully")
				if _sig.has_method("on_bracelet_changed"):
					_sig.call("on_bracelet_changed", member_token)
			else:
				print("[LoadoutPanel] ✗ Failed to equip instance")
		else:
			print("[LoadoutPanel] ✗ equip_into_socket method not available")
		_on_sigils_changed(member_token)
		_popup_close_and_return_to_equipment()
		return

	# Handle base sigil equip
	if kind == "base":
		print("[LoadoutPanel] Equipping base sigil: %s" % id)
		var final_inst: String = ""

		# Try direct equip from inventory first
		if _sig.has_method("equip_from_inventory"):
			print("[LoadoutPanel] Trying direct equip from inventory...")
			var ok_direct: bool = bool(_sig.call("equip_from_inventory", member_token, socket_index, id))
			if ok_direct:
				print("[LoadoutPanel] ✓ Equipped directly from inventory")
				_on_sigils_changed(member_token)
				_popup_close_and_return_to_equipment()
				return
			else:
				print("[LoadoutPanel] Direct equip failed, trying draft...")

		# Otherwise, draft instance then equip
		if _sig.has_method("draft_from_inventory"):
			var drafted: Variant = _sig.call("draft_from_inventory", id)
			if typeof(drafted) == TYPE_STRING:
				final_inst = String(drafted)
				print("[LoadoutPanel] Drafted instance: %s" % final_inst)
			else:
				print("[LoadoutPanel] ✗ Failed to draft instance")

		if final_inst != "" and _sig.has_method("equip_into_socket"):
			var ok_e: bool = bool(_sig.call("equip_into_socket", member_token, socket_index, final_inst))
			if ok_e:
				print("[LoadoutPanel] ✓ Drafted instance equipped successfully")
				if _sig.has_method("on_bracelet_changed"):
					_sig.call("on_bracelet_changed", member_token)
			else:
				print("[LoadoutPanel] ✗ Failed to equip drafted instance")
			_on_sigils_changed(member_token)
		elif final_inst == "":
			print("[LoadoutPanel] ✗ No instance to equip")

		_popup_close_and_return_to_equipment()
		return

	# Unknown kind - just close
	print("[LoadoutPanel] ERROR: Unknown sigil kind: %s" % kind)
	_popup_cancel()

func _popup_cancel() -> void:
	"""User pressed back on popup - close without equipping"""
	_popup_close_and_return_to_equipment()

func _popup_close_and_return_to_equipment() -> void:
	"""Close popup and return to EQUIPMENT_NAV state at same nav index"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	print("[LoadoutPanel] Closing popup, returning to equipment mode")

	# Store popup reference and clear BEFORE popping (prevents double-free)
	var popup_to_close = _active_popup
	_active_popup = null

	# CRITICAL: Set state to EQUIPMENT_NAV BEFORE popping
	# pop_panel() synchronously calls _on_panel_gained_focus(), which needs correct state
	_nav_state = NavState.EQUIPMENT_NAV

	# Pop from panel manager
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr and panel_mgr.is_panel_active(popup_to_close):
		panel_mgr.pop_panel()

	popup_to_close.queue_free()

	# Focus will be restored by _on_panel_gained_focus() when panel_mgr.pop_panel() returns
	# No need to call _restore_equipment_focus here

## ─────────────────────── STATE 2: PARTY_SELECT ───────────────────────

func _handle_party_select_input(event: InputEvent) -> void:
	"""Handle input when in party select mode"""
	if event.is_action_pressed("move_up"):
		_navigate_party(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate_party(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		_transition_to_equipment_nav()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		_exit_loadout_panel()
		get_viewport().set_input_as_handled()

func _navigate_party(delta: int) -> void:
	"""Navigate up/down in party list"""
	if not _party_list or _party_list.get_item_count() == 0:
		return

	var current = _party_list.get_selected_items()
	var idx = current[0] if current.size() > 0 else 0
	idx = clamp(idx + delta, 0, _party_list.get_item_count() - 1)

	_party_list.select(idx)
	_party_list.ensure_current_is_visible()
	_on_party_selected(idx)  # Manually trigger signal

func _transition_to_equipment_nav() -> void:
	"""Transition from PARTY_SELECT to EQUIPMENT_NAV"""
	print("[LoadoutPanel] Transition: PARTY_SELECT → EQUIPMENT_NAV")
	_nav_state = NavState.EQUIPMENT_NAV
	_nav_index = 0  # Start at first equipment button
	call_deferred("_rebuild_equipment_navigation_and_focus_first")

func _exit_loadout_panel() -> void:
	"""Exit LoadoutPanel back to previous panel (StatusPanel)"""
	print("[LoadoutPanel] Exiting to previous panel")
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.pop_panel()

func _enter_party_select_state() -> void:
	"""Enter PARTY_SELECT state and grab focus on party list"""
	_nav_state = NavState.PARTY_SELECT
	if _party_list and _party_list.get_item_count() > 0:
		_party_list.grab_focus()
		if _party_list.get_selected_items().is_empty():
			_party_list.select(0)
	print("[LoadoutPanel] Entered PARTY_SELECT state")

## ─────────────────────── STATE 3: EQUIPMENT_NAV ───────────────────────

func _handle_equipment_nav_input(event: InputEvent) -> void:
	"""Handle input when navigating equipment buttons"""
	if event.is_action_pressed("move_up"):
		_navigate_equipment(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate_equipment(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		_activate_current_equipment_button()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		_transition_to_party_select()
		get_viewport().set_input_as_handled()

func _navigate_equipment(delta: int) -> void:
	"""Navigate up/down through equipment buttons"""
	if _nav_elements.is_empty():
		return

	_nav_index = clamp(_nav_index + delta, 0, _nav_elements.size() - 1)
	_focus_equipment_element(_nav_index)

func _activate_current_equipment_button() -> void:
	"""Press the currently focused equipment button"""
	var focused = get_viewport().gui_get_focus_owner()
	if focused and focused is Button:
		focused.emit_signal("pressed")
	elif _nav_index >= 0 and _nav_index < _nav_elements.size():
		var element = _nav_elements[_nav_index]
		if is_instance_valid(element) and element is Button:
			element.emit_signal("pressed")

func _transition_to_party_select() -> void:
	"""Transition from EQUIPMENT_NAV to PARTY_SELECT"""
	print("[LoadoutPanel] Transition: EQUIPMENT_NAV → PARTY_SELECT")
	_nav_state = NavState.PARTY_SELECT
	call_deferred("_enter_party_select_state")

func _rebuild_equipment_navigation_and_focus_first() -> void:
	"""Rebuild navigation elements and focus the first one"""
	_rebuild_equipment_navigation()
	_nav_index = 0
	if _nav_elements.size() > 0:
		_focus_equipment_element(0)

func _rebuild_equipment_navigation_and_restore_focus() -> void:
	"""Rebuild navigation elements and restore focus to current index"""
	_rebuild_equipment_navigation()
	if _nav_index >= 0 and _nav_index < _nav_elements.size():
		_focus_equipment_element(_nav_index)

func _rebuild_equipment_navigation() -> void:
	"""Build list of focusable equipment elements"""
	_nav_elements.clear()

	# Equipment slot buttons
	if _w_btn: _nav_elements.append(_w_btn)
	if _a_btn: _nav_elements.append(_a_btn)
	if _h_btn: _nav_elements.append(_h_btn)
	if _f_btn: _nav_elements.append(_f_btn)
	if _b_btn: _nav_elements.append(_b_btn)

	# Sigil slot buttons
	if _sigils_list:
		for child in _sigils_list.get_children():
			if child is HBoxContainer:
				for subchild in child.get_children():
					if subchild is Button:
						_nav_elements.append(subchild)

	# Special buttons
	if _btn_manage: _nav_elements.append(_btn_manage)
	if _active_btn: _nav_elements.append(_active_btn)

	print("[LoadoutPanel] Built navigation: %d elements" % _nav_elements.size())

func _focus_equipment_element(index: int) -> void:
	"""Focus the equipment element at given index"""
	print("[LoadoutPanel] _focus_equipment_element: index %d of %d elements" % [index, _nav_elements.size()])
	if index < 0 or index >= _nav_elements.size():
		print("[LoadoutPanel] Index out of bounds!")
		return

	var element = _nav_elements[index]
	if is_instance_valid(element) and element is Control:
		element.grab_focus()
		print("[LoadoutPanel] Grabbed focus on element: %s" % element.name)
	else:
		print("[LoadoutPanel] Element invalid or not a Control")

func _restore_equipment_focus() -> void:
	"""Restore focus to current equipment navigation index"""
	print("[LoadoutPanel] _restore_equipment_focus called: %d elements, index %d" % [_nav_elements.size(), _nav_index])
	if _nav_elements.is_empty():
		print("[LoadoutPanel] Nav elements empty, rebuilding...")
		call_deferred("_rebuild_equipment_navigation_and_restore_focus")
	else:
		print("[LoadoutPanel] Focusing element at index %d" % _nav_index)
		_focus_equipment_element(_nav_index)
		if _nav_index < _nav_elements.size():
			var elem = _nav_elements[_nav_index]
			print("[LoadoutPanel] Element valid: %s, is Control: %s" % [is_instance_valid(elem), elem is Control if is_instance_valid(elem) else "N/A"])
