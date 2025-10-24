extends Control
class_name StatusEffectCheatBar

## StatusEffectCheatBar
## Cheat interface for applying status ailments, buffs, and debuffs to party members
## Based on Chapter 7 spec (combat status effects)

# ───────────────────────── Autoload paths ─────────────────────────
const GS_PATH: String = "/root/aGameState"
const COMBAT_PROF_PATH: String = "/root/aCombatProfileSystem"
const STATUS_PATH: String = "/root/aStatusEffects"

# ───────────────────────── UI nodes (runtime-created) ─────────────────────────
var _main_vbox: VBoxContainer = null

# Row 1: Member selector
var _member_row: HBoxContainer = null
var _member_pick: OptionButton = null

# Row 2: Ailments
var _ailment_row: HBoxContainer = null
var _ailment_pick: OptionButton = null
var _btn_apply_ailment: Button = null
var _btn_clear_ailment: Button = null

# Row 3: Buffs
var _buff_row: HBoxContainer = null
var _buff_pick: OptionButton = null
var _buff_duration_spin: SpinBox = null
var _btn_add_buff: Button = null
var _btn_remove_buff: Button = null
var _btn_clear_buffs: Button = null

# Row 4: Debuffs
var _debuff_row: HBoxContainer = null
var _debuff_pick: OptionButton = null
var _debuff_duration_spin: SpinBox = null
var _btn_add_debuff: Button = null
var _btn_remove_debuff: Button = null
var _btn_clear_debuffs: Button = null

# Row 5: Quick actions
var _quick_row: HBoxContainer = null
var _btn_clear_all_status: Button = null
var _btn_heal_full: Button = null

# ───────────────────────── System refs ─────────────────────────
var _gs: Node = null
var _combat_prof: Node = null
var _status: Node = null

# ───────────────────────── Data ─────────────────────────
# From Chapter 7 spec
var AILMENTS: PackedStringArray = PackedStringArray([
	"Poison", "Burn", "Sleep", "Freeze", "Mind Block",
	"Confused", "Charm", "Berserk", "Malaise"
])

var BUFFS: PackedStringArray = PackedStringArray([
	"Attack Up", "Mind Up", "Regen", "Haste",
	"Protect", "Shell", "Accuracy Up", "Evasion Up", "Skill ACC Boost"
])

var DEBUFFS: PackedStringArray = PackedStringArray([
	"Attack Down", "Defense Down", "Mind Down"
])

# ───────────────────────── Lifecycle ─────────────────────────
func _ready() -> void:
	_gs = get_node_or_null(GS_PATH)
	_combat_prof = get_node_or_null(COMBAT_PROF_PATH)
	_status = get_node_or_null(STATUS_PATH)

	_build_ui()
	_refresh_member_picker()

# ───────────────────────── UI Construction ─────────────────────────
func _build_ui() -> void:
	# Create dark background panel (90% opacity)
	var bg_panel := Panel.new()
	bg_panel.name = "BackgroundPanel"
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0, 0, 0, 0.9)  # 90% dark background
	bg_panel.add_theme_stylebox_override("panel", style_box)
	add_child(bg_panel)

	# Create main container
	_main_vbox = VBoxContainer.new()
	_main_vbox.name = "MainVBox"
	_main_vbox.add_theme_constant_override("separation", 4)
	_main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_vbox.offset_left = 10
	_main_vbox.offset_top = 10
	_main_vbox.offset_right = -10
	_main_vbox.offset_bottom = -10
	add_child(_main_vbox)

	# Title
	var title := Label.new()
	title.text = "Status Effects Cheat"
	title.add_theme_font_size_override("font_size", 10)
	_main_vbox.add_child(title)

	# Build each row
	_build_member_row()
	_build_ailment_row()
	_build_buff_row()
	_build_debuff_row()
	_build_quick_row()

func _build_member_row() -> void:
	_member_row = HBoxContainer.new()
	_member_row.name = "MemberRow"
	_member_row.add_theme_constant_override("separation", 6)
	_main_vbox.add_child(_member_row)

	var lbl := Label.new()
	lbl.text = "Member:"
	_member_row.add_child(lbl)

	_member_pick = OptionButton.new()
	_member_pick.custom_minimum_size = Vector2(100, 0)
	_style_option_button(_member_pick, 8, 210)
	_member_row.add_child(_member_pick)

func _build_ailment_row() -> void:
	_ailment_row = HBoxContainer.new()
	_ailment_row.name = "AilmentRow"
	_ailment_row.add_theme_constant_override("separation", 6)
	_main_vbox.add_child(_ailment_row)

	var lbl := Label.new()
	lbl.text = "Ailment:"
	_ailment_row.add_child(lbl)

	_ailment_pick = OptionButton.new()
	_ailment_pick.custom_minimum_size = Vector2(100, 0)
	_style_option_button(_ailment_pick, 8, 210)
	_ailment_row.add_child(_ailment_pick)

	# Populate ailments
	for ailment in AILMENTS:
		_ailment_pick.add_item(ailment)
		_ailment_pick.set_item_metadata(_ailment_pick.get_item_count() - 1, ailment)

	_btn_apply_ailment = Button.new()
	_btn_apply_ailment.text = "Apply"
	_btn_apply_ailment.add_theme_font_size_override("font_size", 8)
	_btn_apply_ailment.pressed.connect(_on_apply_ailment)
	_ailment_row.add_child(_btn_apply_ailment)

	_btn_clear_ailment = Button.new()
	_btn_clear_ailment.text = "Clear"
	_btn_clear_ailment.add_theme_font_size_override("font_size", 8)
	_btn_clear_ailment.pressed.connect(_on_clear_ailment)
	_ailment_row.add_child(_btn_clear_ailment)

func _build_buff_row() -> void:
	_buff_row = HBoxContainer.new()
	_buff_row.name = "BuffRow"
	_buff_row.add_theme_constant_override("separation", 6)
	_main_vbox.add_child(_buff_row)

	var lbl := Label.new()
	lbl.text = "Buff:"
	_buff_row.add_child(lbl)

	_buff_pick = OptionButton.new()
	_buff_pick.custom_minimum_size = Vector2(100, 0)
	_style_option_button(_buff_pick, 8, 210)
	_buff_row.add_child(_buff_pick)

	# Populate buffs
	for buff in BUFFS:
		_buff_pick.add_item(buff)
		_buff_pick.set_item_metadata(_buff_pick.get_item_count() - 1, buff)

	var dur_lbl := Label.new()
	dur_lbl.text = "Turns:"
	_buff_row.add_child(dur_lbl)

	_buff_duration_spin = SpinBox.new()
	_buff_duration_spin.min_value = 1
	_buff_duration_spin.max_value = 99
	_buff_duration_spin.value = 3
	_buff_duration_spin.custom_minimum_size = Vector2(50, 0)
	_buff_row.add_child(_buff_duration_spin)

	_btn_add_buff = Button.new()
	_btn_add_buff.text = "Add"
	_btn_add_buff.add_theme_font_size_override("font_size", 8)
	_btn_add_buff.pressed.connect(_on_add_buff)
	_buff_row.add_child(_btn_add_buff)

	_btn_remove_buff = Button.new()
	_btn_remove_buff.text = "Remove"
	_btn_remove_buff.add_theme_font_size_override("font_size", 8)
	_btn_remove_buff.pressed.connect(_on_remove_buff)
	_buff_row.add_child(_btn_remove_buff)

	_btn_clear_buffs = Button.new()
	_btn_clear_buffs.text = "Clear All"
	_btn_clear_buffs.add_theme_font_size_override("font_size", 8)
	_btn_clear_buffs.pressed.connect(_on_clear_buffs)
	_buff_row.add_child(_btn_clear_buffs)

func _build_debuff_row() -> void:
	_debuff_row = HBoxContainer.new()
	_debuff_row.name = "DebuffRow"
	_debuff_row.add_theme_constant_override("separation", 6)
	_main_vbox.add_child(_debuff_row)

	var lbl := Label.new()
	lbl.text = "Debuff:"
	_debuff_row.add_child(lbl)

	_debuff_pick = OptionButton.new()
	_debuff_pick.custom_minimum_size = Vector2(100, 0)
	_style_option_button(_debuff_pick, 8, 210)
	_debuff_row.add_child(_debuff_pick)

	# Populate debuffs
	for debuff in DEBUFFS:
		_debuff_pick.add_item(debuff)
		_debuff_pick.set_item_metadata(_debuff_pick.get_item_count() - 1, debuff)

	var dur_lbl := Label.new()
	dur_lbl.text = "Turns:"
	_debuff_row.add_child(dur_lbl)

	_debuff_duration_spin = SpinBox.new()
	_debuff_duration_spin.min_value = 1
	_debuff_duration_spin.max_value = 99
	_debuff_duration_spin.value = 3
	_debuff_duration_spin.custom_minimum_size = Vector2(50, 0)
	_debuff_row.add_child(_debuff_duration_spin)

	_btn_add_debuff = Button.new()
	_btn_add_debuff.text = "Add"
	_btn_add_debuff.add_theme_font_size_override("font_size", 8)
	_btn_add_debuff.pressed.connect(_on_add_debuff)
	_debuff_row.add_child(_btn_add_debuff)

	_btn_remove_debuff = Button.new()
	_btn_remove_debuff.text = "Remove"
	_btn_remove_debuff.add_theme_font_size_override("font_size", 8)
	_btn_remove_debuff.pressed.connect(_on_remove_debuff)
	_debuff_row.add_child(_btn_remove_debuff)

	_btn_clear_debuffs = Button.new()
	_btn_clear_debuffs.text = "Clear All"
	_btn_clear_debuffs.add_theme_font_size_override("font_size", 8)
	_btn_clear_debuffs.pressed.connect(_on_clear_debuffs)
	_debuff_row.add_child(_btn_clear_debuffs)

func _build_quick_row() -> void:
	_quick_row = HBoxContainer.new()
	_quick_row.name = "QuickRow"
	_quick_row.add_theme_constant_override("separation", 6)
	_main_vbox.add_child(_quick_row)

	_btn_clear_all_status = Button.new()
	_btn_clear_all_status.text = "Clear All Status (Member)"
	_btn_clear_all_status.add_theme_font_size_override("font_size", 8)
	_btn_clear_all_status.pressed.connect(_on_clear_all_status)
	_quick_row.add_child(_btn_clear_all_status)

	_btn_heal_full = Button.new()
	_btn_heal_full.text = "Heal Party to Full"
	_btn_heal_full.add_theme_font_size_override("font_size", 8)
	_btn_heal_full.pressed.connect(_on_heal_full)
	_quick_row.add_child(_btn_heal_full)

# ───────────────────────── Helpers ─────────────────────────
func _style_option_button(ob: OptionButton, font_px: int, popup_max_h: int, popup_max_w: int = 300) -> void:
	if ob == null:
		return
	ob.add_theme_font_size_override("font_size", font_px)
	var pm: PopupMenu = ob.get_popup()
	if pm:
		pm.add_theme_font_size_override("font_size", font_px)
		pm.max_size = Vector2i(popup_max_w, popup_max_h)

func _refresh_member_picker() -> void:
	if _member_pick == null:
		return
	_member_pick.clear()

	var members: Array[String] = _get_all_party_members()
	if members.is_empty():
		members.append("hero")

	for member in members:
		var display: String = _get_display_name(member)
		_member_pick.add_item(display)
		_member_pick.set_item_metadata(_member_pick.get_item_count() - 1, member)

func _get_all_party_members() -> Array[String]:
	var out: Array[String] = []
	if _gs == null:
		return out

	# Get active party
	if _gs.has_method("get_active_party_ids"):
		var v: Variant = _gs.call("get_active_party_ids")
		if typeof(v) == TYPE_ARRAY:
			for m in (v as Array):
				out.append(String(m))
		elif typeof(v) == TYPE_PACKED_STRING_ARRAY:
			for m in (v as PackedStringArray):
				out.append(String(m))

	# Get benched
	if _gs.has_method("get"):
		var bench_v: Variant = _gs.get("bench")
		if typeof(bench_v) == TYPE_ARRAY:
			for m in (bench_v as Array):
				var mid := String(m)
				if not out.has(mid):
					out.append(mid)
		elif typeof(bench_v) == TYPE_PACKED_STRING_ARRAY:
			for m in (bench_v as PackedStringArray):
				var mid := String(m)
				if not out.has(mid):
					out.append(mid)

	return out

func _get_display_name(member_id: String) -> String:
	if member_id == "hero" and _gs:
		var nm_v: Variant = _gs.get("player_name")
		if typeof(nm_v) == TYPE_STRING and String(nm_v).strip_edges() != "":
			return String(nm_v)
		return "Hero"
	return member_id.capitalize()

func _selected_member() -> String:
	if _member_pick == null:
		return ""
	var idx: int = _member_pick.get_selected()
	if idx < 0:
		return ""
	return String(_member_pick.get_item_metadata(idx))

func _selected_ailment() -> String:
	if _ailment_pick == null:
		return ""
	var idx: int = _ailment_pick.get_selected()
	if idx < 0:
		return ""
	return String(_ailment_pick.get_item_metadata(idx))

func _selected_buff() -> String:
	if _buff_pick == null:
		return ""
	var idx: int = _buff_pick.get_selected()
	if idx < 0:
		return ""
	return String(_buff_pick.get_item_metadata(idx))

func _selected_debuff() -> String:
	if _debuff_pick == null:
		return ""
	var idx: int = _debuff_pick.get_selected()
	if idx < 0:
		return ""
	return String(_debuff_pick.get_item_metadata(idx))

# ───────────────────────── Actions ─────────────────────────
func _on_apply_ailment() -> void:
	var member: String = _selected_member()
	var ailment: String = _selected_ailment()
	if member == "" or ailment == "":
		print("[StatusEffectCheatBar] No member or ailment selected")
		return

	_apply_ailment_to_member(member, ailment)
	print("[StatusEffectCheatBar] Applied '%s' to %s" % [ailment, member])

func _on_clear_ailment() -> void:
	var member: String = _selected_member()
	if member == "":
		print("[StatusEffectCheatBar] No member selected")
		return

	_apply_ailment_to_member(member, "")
	print("[StatusEffectCheatBar] Cleared ailment for %s" % member)

func _on_add_buff() -> void:
	var member: String = _selected_member()
	var buff: String = _selected_buff()
	if member == "" or buff == "":
		print("[StatusEffectCheatBar] No member or buff selected")
		return

	var turns: int = int(_buff_duration_spin.value) if _buff_duration_spin else 3
	_add_buff_to_member(member, buff, turns)
	print("[StatusEffectCheatBar] Added buff '%s' (%d turns) to %s" % [buff, turns, member])

func _on_remove_buff() -> void:
	var member: String = _selected_member()
	var buff: String = _selected_buff()
	if member == "" or buff == "":
		print("[StatusEffectCheatBar] No member or buff selected")
		return

	_remove_buff_from_member(member, buff)
	print("[StatusEffectCheatBar] Removed buff '%s' from %s" % [buff, member])

func _on_clear_buffs() -> void:
	var member: String = _selected_member()
	if member == "":
		print("[StatusEffectCheatBar] No member selected")
		return

	_clear_buffs_for_member(member)
	print("[StatusEffectCheatBar] Cleared all buffs for %s" % member)

func _on_add_debuff() -> void:
	var member: String = _selected_member()
	var debuff: String = _selected_debuff()
	if member == "" or debuff == "":
		print("[StatusEffectCheatBar] No member or debuff selected")
		return

	var turns: int = int(_debuff_duration_spin.value) if _debuff_duration_spin else 3
	_add_debuff_to_member(member, debuff, turns)
	print("[StatusEffectCheatBar] Added debuff '%s' (%d turns) to %s" % [debuff, turns, member])

func _on_remove_debuff() -> void:
	var member: String = _selected_member()
	var debuff: String = _selected_debuff()
	if member == "" or debuff == "":
		print("[StatusEffectCheatBar] No member or debuff selected")
		return

	_remove_debuff_from_member(member, debuff)
	print("[StatusEffectCheatBar] Removed debuff '%s' from %s" % [debuff, member])

func _on_clear_debuffs() -> void:
	var member: String = _selected_member()
	if member == "":
		print("[StatusEffectCheatBar] No member selected")
		return

	_clear_debuffs_for_member(member)
	print("[StatusEffectCheatBar] Cleared all debuffs for %s" % member)

func _on_clear_all_status() -> void:
	var member: String = _selected_member()
	if member == "":
		print("[StatusEffectCheatBar] No member selected")
		return

	_clear_all_status_for_member(member)
	print("[StatusEffectCheatBar] Cleared ALL status effects for %s" % member)

func _on_heal_full() -> void:
	if _combat_prof and _combat_prof.has_method("heal_all_to_full"):
		_combat_prof.call("heal_all_to_full")
		print("[StatusEffectCheatBar] Healed all party members to full HP/MP")
	else:
		print("[StatusEffectCheatBar] CombatProfileSystem not found or missing heal_all_to_full method")

# ───────────────────────── System Integration ─────────────────────────
func _apply_ailment_to_member(member: String, ailment: String) -> void:
	# Update StatusEffects system
	if _status and _status.has_method("set_ailment"):
		_status.call("set_ailment", member, ailment)

	# Update GameState.member_data for persistence
	if _gs and _gs.has_method("get"):
		var member_data_v: Variant = _gs.get("member_data")
		if typeof(member_data_v) == TYPE_DICTIONARY:
			var member_data: Dictionary = member_data_v
			if not member_data.has(member):
				member_data[member] = {}
			var rec: Dictionary = member_data[member]
			rec["ailment"] = ailment
			member_data[member] = rec
			if _gs.has_method("set"):
				_gs.set("member_data", member_data)

	# Refresh combat profile
	if _combat_prof and _combat_prof.has_method("refresh_member"):
		_combat_prof.call("refresh_member", member)

func _add_buff_to_member(member: String, buff_id: String, turns: int) -> void:
	var buff_data: Dictionary = {"id": buff_id, "turns": turns, "stacks": 1}

	# Update StatusEffects system
	if _status and _status.has_method("add_buff"):
		_status.call("add_buff", member, buff_data)

	# Update GameState.member_data for persistence
	if _gs and _gs.has_method("get"):
		var member_data_v: Variant = _gs.get("member_data")
		if typeof(member_data_v) == TYPE_DICTIONARY:
			var member_data: Dictionary = member_data_v
			if not member_data.has(member):
				member_data[member] = {}
			var rec: Dictionary = member_data[member]
			var buffs: Array = rec.get("buffs", []) as Array
			buffs.append(buff_data.duplicate())
			rec["buffs"] = buffs
			member_data[member] = rec
			if _gs.has_method("set"):
				_gs.set("member_data", member_data)

	# Refresh combat profile
	if _combat_prof and _combat_prof.has_method("refresh_member"):
		_combat_prof.call("refresh_member", member)

func _remove_buff_from_member(member: String, buff_id: String) -> void:
	# Update StatusEffects system
	if _status and _status.has_method("remove_buff"):
		_status.call("remove_buff", member, buff_id)

	# Update GameState.member_data for persistence
	if _gs and _gs.has_method("get"):
		var member_data_v: Variant = _gs.get("member_data")
		if typeof(member_data_v) == TYPE_DICTIONARY:
			var member_data: Dictionary = member_data_v
			if member_data.has(member):
				var rec: Dictionary = member_data[member]
				var buffs: Array = rec.get("buffs", []) as Array
				var filtered: Array = []
				for b in buffs:
					if typeof(b) == TYPE_DICTIONARY:
						var bd: Dictionary = b
						if String(bd.get("id", "")) != buff_id:
							filtered.append(bd)
				rec["buffs"] = filtered
				member_data[member] = rec
				if _gs.has_method("set"):
					_gs.set("member_data", member_data)

	# Refresh combat profile
	if _combat_prof and _combat_prof.has_method("refresh_member"):
		_combat_prof.call("refresh_member", member)

func _clear_buffs_for_member(member: String) -> void:
	# Update GameState.member_data
	if _gs and _gs.has_method("get"):
		var member_data_v: Variant = _gs.get("member_data")
		if typeof(member_data_v) == TYPE_DICTIONARY:
			var member_data: Dictionary = member_data_v
			if not member_data.has(member):
				member_data[member] = {}
			var rec: Dictionary = member_data[member]
			rec["buffs"] = []
			member_data[member] = rec
			if _gs.has_method("set"):
				_gs.set("member_data", member_data)

	# Update StatusEffects system (clear each buff individually)
	if _status and _status.has_method("get_buffs_for"):
		var buffs: Array = _status.call("get_buffs_for", member)
		for b in buffs:
			if typeof(b) == TYPE_DICTIONARY and _status.has_method("remove_buff"):
				_status.call("remove_buff", member, String(b.get("id", "")))

	# Refresh combat profile
	if _combat_prof and _combat_prof.has_method("refresh_member"):
		_combat_prof.call("refresh_member", member)

func _add_debuff_to_member(member: String, debuff_id: String, turns: int) -> void:
	var debuff_data: Dictionary = {"id": debuff_id, "turns": turns, "stacks": 1}

	# Update StatusEffects system
	if _status and _status.has_method("add_debuff"):
		_status.call("add_debuff", member, debuff_data)

	# Update GameState.member_data for persistence
	if _gs and _gs.has_method("get"):
		var member_data_v: Variant = _gs.get("member_data")
		if typeof(member_data_v) == TYPE_DICTIONARY:
			var member_data: Dictionary = member_data_v
			if not member_data.has(member):
				member_data[member] = {}
			var rec: Dictionary = member_data[member]
			var debuffs: Array = rec.get("debuffs", []) as Array
			debuffs.append(debuff_data.duplicate())
			rec["debuffs"] = debuffs
			member_data[member] = rec
			if _gs.has_method("set"):
				_gs.set("member_data", member_data)

	# Refresh combat profile
	if _combat_prof and _combat_prof.has_method("refresh_member"):
		_combat_prof.call("refresh_member", member)

func _remove_debuff_from_member(member: String, debuff_id: String) -> void:
	# Update StatusEffects system
	if _status and _status.has_method("remove_debuff"):
		_status.call("remove_debuff", member, debuff_id)

	# Update GameState.member_data for persistence
	if _gs and _gs.has_method("get"):
		var member_data_v: Variant = _gs.get("member_data")
		if typeof(member_data_v) == TYPE_DICTIONARY:
			var member_data: Dictionary = member_data_v
			if member_data.has(member):
				var rec: Dictionary = member_data[member]
				var debuffs: Array = rec.get("debuffs", []) as Array
				var filtered: Array = []
				for d in debuffs:
					if typeof(d) == TYPE_DICTIONARY:
						var dd: Dictionary = d
						if String(dd.get("id", "")) != debuff_id:
							filtered.append(dd)
				rec["debuffs"] = filtered
				member_data[member] = rec
				if _gs.has_method("set"):
					_gs.set("member_data", member_data)

	# Refresh combat profile
	if _combat_prof and _combat_prof.has_method("refresh_member"):
		_combat_prof.call("refresh_member", member)

func _clear_debuffs_for_member(member: String) -> void:
	# Update GameState.member_data
	if _gs and _gs.has_method("get"):
		var member_data_v: Variant = _gs.get("member_data")
		if typeof(member_data_v) == TYPE_DICTIONARY:
			var member_data: Dictionary = member_data_v
			if not member_data.has(member):
				member_data[member] = {}
			var rec: Dictionary = member_data[member]
			rec["debuffs"] = []
			member_data[member] = rec
			if _gs.has_method("set"):
				_gs.set("member_data", member_data)

	# Update StatusEffects system (clear each debuff individually)
	if _status and _status.has_method("get_debuffs_for"):
		var debuffs: Array = _status.call("get_debuffs_for", member)
		for d in debuffs:
			if typeof(d) == TYPE_DICTIONARY and _status.has_method("remove_debuff"):
				_status.call("remove_debuff", member, String(d.get("id", "")))

	# Refresh combat profile
	if _combat_prof and _combat_prof.has_method("refresh_member"):
		_combat_prof.call("refresh_member", member)

func _clear_all_status_for_member(member: String) -> void:
	_apply_ailment_to_member(member, "")
	_clear_buffs_for_member(member)
	_clear_debuffs_for_member(member)

	# Also clear from StatusEffects system
	if _status and _status.has_method("clear_member"):
		_status.call("clear_member", member)
