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

# Panel animation settings
const BASE_LEFT_RATIO := 2.0
const BASE_CENTER_RATIO := 3.5
const BASE_RIGHT_RATIO := 4.5
const ACTIVE_SCALE := 1.10  # Active panel grows by 10%
const INACTIVE_SCALE := 0.95  # Inactive panels shrink by 5%
const ANIM_DURATION := 0.2  # Animation duration in seconds

# Panel references (for animation)
@onready var _party_panel: PanelContainer = get_node("%Party") if has_node("%Party") else null
@onready var _middle_panel: PanelContainer = get_node("%Middle") if has_node("%Middle") else null
@onready var _stats_panel: PanelContainer = get_node("%StatsColumn") if has_node("%StatsColumn") else null

@onready var _party_scroll: ScrollContainer = get_node("Row/Party/Margin/VBox/PartyScroll") as ScrollContainer
@onready var _party_list: VBoxContainer     = get_node("Row/Party/Margin/VBox/PartyScroll/PartyList") as VBoxContainer
# @onready var _member_name: Label         = get_node("Row/Middle/Margin/VBox/MemberName") as Label  # Removed

# Section header labels
@onready var _party_label: Label = get_node_or_null("Row/Party/Margin/VBox/PartyLabel") as Label
@onready var _mind_type_label: Label = get_node_or_null("Row/Middle/Margin/VBox/MindSection/MindLabel") as Label
@onready var _equipment_label: Label = get_node_or_null("Row/Middle/Margin/VBox/EquipmentLabel") as Label
@onready var _details_label: Label = get_node_or_null("Row/StatsColumn/Margin/VBox/DetailsLabel") as Label
@onready var _attributes_label: Label = get_node_or_null("Row/StatsColumn/Margin/VBox/StatsLabel") as Label

# Equipment slot labels (Weapon:, Armor:, etc.)
@onready var _w_label: Label = get_node_or_null("Row/Middle/Margin/VBox/Grid/WLabel") as Label
@onready var _a_label: Label = get_node_or_null("Row/Middle/Margin/VBox/Grid/ALabel") as Label
@onready var _h_label: Label = get_node_or_null("Row/Middle/Margin/VBox/Grid/HLabel") as Label
@onready var _f_label: Label = get_node_or_null("Row/Middle/Margin/VBox/Grid/FLabel") as Label
@onready var _b_label: Label = get_node_or_null("Row/Middle/Margin/VBox/Grid/BLabel") as Label

# Equipment value labels (item names)
@onready var _w_val: Label = get_node("Row/Middle/Margin/VBox/Grid/WHBox/WValue") as Label
@onready var _a_val: Label = get_node("Row/Middle/Margin/VBox/Grid/AHBox/AValue") as Label
@onready var _h_val: Label = get_node("Row/Middle/Margin/VBox/Grid/HHBox/HValue") as Label
@onready var _f_val: Label = get_node("Row/Middle/Margin/VBox/Grid/FHBox/FValue") as Label
@onready var _b_val: Label = get_node("Row/Middle/Margin/VBox/Grid/BHBox/BValue") as Label

@onready var _w_btn: Button = get_node_or_null("Row/Middle/Margin/VBox/Grid/WHBox/WBtn") as Button
@onready var _a_btn: Button = get_node_or_null("Row/Middle/Margin/VBox/Grid/AHBox/ABtn") as Button
@onready var _h_btn: Button = get_node_or_null("Row/Middle/Margin/VBox/Grid/HHBox/HBtn") as Button
@onready var _f_btn: Button = get_node_or_null("Row/Middle/Margin/VBox/Grid/FHBox/FBtn") as Button
@onready var _b_btn: Button = get_node_or_null("Row/Middle/Margin/VBox/Grid/BHBox/BBtn") as Button

@onready var _sigils_title: Label         = get_node_or_null("Row/Middle/Margin/VBox/Sigils/Title") as Label
@onready var _sigils_list:  GridContainer = get_node_or_null("Row/Middle/Margin/VBox/Sigils/List") as GridContainer
@onready var _btn_manage:   Button        = get_node_or_null("Row/Middle/Margin/VBox/Buttons/BtnManageSigils") as Button

@onready var _stats_grid:  GridContainer = get_node("Row/StatsColumn/Margin/VBox/StatsGrid") as GridContainer
@onready var _details_content: RichTextLabel = %DetailsContent
@onready var _mind_value:  Control       = get_node_or_null("Row/Middle/Margin/VBox/MindSection/MindRow/Value") as Control  # Can be Label or RichTextLabel
@onready var _mind_switch_btn: Button    = %SwitchBtn

var _labels: PackedStringArray = PackedStringArray()
var _tokens: PackedStringArray = PackedStringArray()
var _current_party_button: Button = null  # Currently selected party member button

var _gs:    Node = null
var _inv:   Node = null
var _sig:   Node = null
var _eq:    Node = null
var _stats: Node = null
var _cps:   Node = null  # CombatProfileSystem for battle stats

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
var _active_overlay: CanvasLayer = null  # CanvasLayer overlay for active popup

func _ready() -> void:
	super()  # Call PanelBase._ready()

	# Set process mode to work while game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	_gs    = get_node_or_null("/root/aGameState")
	_inv   = get_node_or_null("/root/aInventorySystem")
	_sig   = get_node_or_null("/root/aSigilSystem")
	_eq    = get_node_or_null("/root/aEquipmentSystem")
	_stats = get_node_or_null("/root/aStatsSystem")
	_cps   = get_node_or_null("/root/aCombatProfileSystem")

	if _w_btn: _w_btn.pressed.connect(Callable(self, "_on_slot_button").bind("weapon"))
	if _a_btn: _a_btn.pressed.connect(Callable(self, "_on_slot_button").bind("armor"))
	if _h_btn: _h_btn.pressed.connect(Callable(self, "_on_slot_button").bind("head"))
	if _f_btn: _f_btn.pressed.connect(Callable(self, "_on_slot_button").bind("foot"))
	if _b_btn: _b_btn.pressed.connect(Callable(self, "_on_slot_button").bind("bracelet"))

	# Party list is now button-based, signals connected per button

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

	# Connect Switch button to active type picker
	if _mind_switch_btn and not _mind_switch_btn.pressed.is_connected(_open_active_type_picker):
		_mind_switch_btn.pressed.connect(_open_active_type_picker)

	call_deferred("_first_fill")

	# polling fallback so UI never goes stale
	set_process(true)

## PanelBase callback - Called when LoadoutPanel gains focus
func _on_panel_gained_focus() -> void:
	super()  # Call parent
	var active = is_active()
	print("[LoadoutPanel] Panel gained focus - state: %s, is_active: %s" % [NavState.keys()[_nav_state], active])
	print("[LoadoutPanel] About to call _animate_panel_focus from gained_focus")

	# Restore focus based on current navigation state
	match _nav_state:
		NavState.PARTY_SELECT:
			print("[LoadoutPanel] Calling deferred _enter_party_select_state")
			call_deferred("_enter_party_select_state")
		NavState.EQUIPMENT_NAV:
			print("[LoadoutPanel] Calling deferred _restore_equipment_focus")
			call_deferred("_animate_panel_focus")
			call_deferred("_restore_equipment_focus")
		NavState.POPUP_ACTIVE:
			# Popup will handle its own focus when it's the active panel
			print("[LoadoutPanel] In POPUP_ACTIVE state, popup handles focus")
			pass

## PanelBase callback - Called when LoadoutPanel loses focus
func _on_panel_lost_focus() -> void:
	super()  # Call parent
	var active = is_active()
	print("[LoadoutPanel] Panel lost focus - state: %s, is_active: %s, registered: %s" % [NavState.keys()[_nav_state], active, is_registered()])
	# Don't auto-close popup - it's managed by panel stack
	# Don't change state - preserve it for when we regain focus

func _first_fill() -> void:
	# Apply Core Vibe styling
	_apply_core_vibe_styling()

	_refresh_party()
	if _party_list.get_child_count() > 0:
		var first_btn = _party_list.get_child(0) as Button
		if first_btn:
			first_btn.grab_focus()
			_on_party_button_focused(first_btn)
	_party_sig = _snapshot_party_signature()
	var cur := _current_token()
	_sigils_sig = _snapshot_sigil_signature(cur) if cur != "" else ""

func _apply_core_vibe_styling() -> void:
	"""Apply Core Vibe neon-kawaii styling to LoadoutPanel"""

	# Style the three main panel containers with rounded neon borders
	# Note: No content_margin here - scene already has MarginContainers
	if _party_panel:
		var party_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (party)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		_party_panel.add_theme_stylebox_override("panel", party_style)

	if _middle_panel:
		var middle_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_GRAPE_VIOLET,        # Grape Violet border (equipment)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		_middle_panel.add_theme_stylebox_override("panel", middle_style)
		# Set minimum size to prevent squashing when equipment icons aren't present
		# Icons are taller than text, so we lock it to the "full equipment" size
		_middle_panel.custom_minimum_size = Vector2(405, 585)

	if _stats_panel:
		var stats_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (stats)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		_stats_panel.add_theme_stylebox_override("panel", stats_style)

	# Party list is now button-based, styling handled per-button in _create_party_member_card()

	# Style section headers (Bubble Magenta)
	if _party_label:
		aCoreVibeTheme.style_label(_party_label, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)
	if _mind_type_label:
		aCoreVibeTheme.style_label(_mind_type_label, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)
	if _equipment_label:
		aCoreVibeTheme.style_label(_equipment_label, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)
	if _details_label:
		aCoreVibeTheme.style_label(_details_label, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)
	if _attributes_label:
		aCoreVibeTheme.style_label(_attributes_label, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)

	# Style equipment slot labels (Milk White)
	if _w_label:
		aCoreVibeTheme.style_label(_w_label, aCoreVibeTheme.COLOR_MILK_WHITE, 12)
	if _a_label:
		aCoreVibeTheme.style_label(_a_label, aCoreVibeTheme.COLOR_MILK_WHITE, 12)
	if _h_label:
		aCoreVibeTheme.style_label(_h_label, aCoreVibeTheme.COLOR_MILK_WHITE, 12)
	if _f_label:
		aCoreVibeTheme.style_label(_f_label, aCoreVibeTheme.COLOR_MILK_WHITE, 12)
	if _b_label:
		aCoreVibeTheme.style_label(_b_label, aCoreVibeTheme.COLOR_MILK_WHITE, 12)

	# Style equipment value labels / item names (Sky Cyan)
	if _w_val:
		aCoreVibeTheme.style_label(_w_val, aCoreVibeTheme.COLOR_SKY_CYAN, 12)
	if _a_val:
		aCoreVibeTheme.style_label(_a_val, aCoreVibeTheme.COLOR_SKY_CYAN, 12)
	if _h_val:
		aCoreVibeTheme.style_label(_h_val, aCoreVibeTheme.COLOR_SKY_CYAN, 12)
	if _f_val:
		aCoreVibeTheme.style_label(_f_val, aCoreVibeTheme.COLOR_SKY_CYAN, 12)
	if _b_val:
		aCoreVibeTheme.style_label(_b_val, aCoreVibeTheme.COLOR_SKY_CYAN, 12)

	# Style equipment buttons
	if _w_btn:
		aCoreVibeTheme.style_button(_w_btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_SMALL)
	if _a_btn:
		aCoreVibeTheme.style_button(_a_btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_SMALL)
	if _h_btn:
		aCoreVibeTheme.style_button(_h_btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_SMALL)
	if _f_btn:
		aCoreVibeTheme.style_button(_f_btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_SMALL)
	if _b_btn:
		aCoreVibeTheme.style_button(_b_btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_SMALL)

	# Style sigils title (Bubble Magenta)
	if _sigils_title:
		aCoreVibeTheme.style_label(_sigils_title, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)

	# Style manage sigils button
	if _btn_manage:
		aCoreVibeTheme.style_button(_btn_manage, aCoreVibeTheme.COLOR_ELECTRIC_LIME, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)

	# Style mind section - will be set per-text in _refresh_mind_row
	# (Base color Milk White, with Sky Cyan for player active type)

	# Style switch button
	if _mind_switch_btn:
		aCoreVibeTheme.style_button(_mind_switch_btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)

	# Style details content
	if _details_content:
		_details_content.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_details_content.add_theme_font_size_override("normal_font_size", 12)

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

	# DEBUG: Print equipment loadout
	print("[DEBUG] Refreshing loadout for %s" % cur)
	print("  Weapon: %s" % equip.get("weapon", "(none)"))
	print("  Armor: %s" % equip.get("armor", "(none)"))
	print("  Head: %s" % equip.get("head", "(none)"))
	print("  Foot: %s" % equip.get("foot", "(none)"))
	print("  Bracelet: %s" % equip.get("bracelet", "(none)"))

	_set_slot_value(_w_val, String(equip.get("weapon","")), "weapon")
	_set_slot_value(_a_val, String(equip.get("armor","")), "armor")
	_set_slot_value(_h_val, String(equip.get("head","")), "head")
	_set_slot_value(_f_val, String(equip.get("foot","")), "foot")
	_set_slot_value(_b_val, String(equip.get("bracelet","")), "bracelet")
	_rebuild_stats_grid(cur, equip)
	_rebuild_sigils(cur)
	_refresh_mind_row(cur)

	# ALWAYS rebuild navigation when UI changes (equipment/sigils)
	# This ensures _nav_elements stays in sync even if popup is open
	# We check state before restoring focus, not before rebuilding
	call_deferred("_rebuild_equipment_navigation")

	# Only restore focus if we're actively in equipment mode
	if _nav_state == NavState.EQUIPMENT_NAV:
		call_deferred("_restore_equipment_focus")

	# DEBUG: Print panel sizes after layout
	call_deferred("_debug_print_panel_sizes")

func _on_sigil_instances_updated(_a=null,_b=null,_c=null) -> void:
	_refresh_all_for_current()

func _on_stats_changed() -> void:
	_refresh_all_for_current()

func _on_party_roster_changed(_arg=null) -> void:
	var keep: String = _current_token()
	_refresh_party()
	var idx: int = max(0, _tokens.find(keep))
	if _party_list.get_child_count() > 0:
		idx = clamp(idx, 0, _party_list.get_child_count() - 1)
		var btn = _party_list.get_child(idx) as Button
		if btn:
			btn.grab_focus()
			_on_party_button_focused(btn)
	_party_sig = _snapshot_party_signature()

# ────────────────── party ──────────────────
func _hero_name() -> String:
	var s: String = ""
	if _gs and _gs.has_method("get"):
		s = String(_gs.get("player_name"))
	if s.strip_edges() == "":
		s = "Player"
	# Extract first name only
	var space_index: int = s.find(" ")
	if space_index > 0:
		return s.substr(0, space_index)
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
	# Clear existing buttons
	for child in _party_list.get_children():
		child.queue_free()

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

	# Create button for each party member
	for i in range(_labels.size()):
		var btn = _create_party_member_card(_tokens[i], _labels[i])
		_party_list.add_child(btn)

func _create_party_member_card(token: String, display_name: String) -> Button:
	"""Create a styled button for a party member - matches StatusPanel style"""
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(0, 40)  # Same height as StatusPanel
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Store metadata
	btn.set_meta("member_token", token)
	btn.set_meta("member_name", display_name)

	# Connect signals
	btn.pressed.connect(_on_party_button_pressed.bind(btn))
	btn.focus_entered.connect(_on_party_button_focused.bind(btn))
	btn.focus_exited.connect(_on_party_button_unfocused.bind(btn))

	# Create label for name
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_label)

	# Style button (default unfocused state)
	_style_party_member_card(btn, false)

	return btn

func _style_party_member_card(btn: Button, is_focused: bool) -> void:
	"""Style a party member button based on focus state"""
	var style = StyleBoxFlat.new()

	# Dark rounded box background (INK_CHARCOAL)
	style.bg_color = aCoreVibeTheme.COLOR_INK_CHARCOAL
	style.border_width_left = 0
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.shadow_size = 0

	# Rounded corners
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12

	# Padding
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)

	# Update text color - Sky Cyan when focused, Milk White when not
	if btn.get_child_count() > 0:
		var label = btn.get_child(0) as Label
		if label:
			if is_focused:
				label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
			else:
				label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)

	# Handle arrow indicator
	if is_focused:
		_show_party_member_arrow(btn)
	else:
		_hide_party_member_arrow(btn)

func _show_party_member_arrow(btn: Button) -> void:
	"""Show arrow indicator to the right of selected party member"""
	# Check if arrow already exists
	var arrow = btn.get_node_or_null("SelectionArrow")
	if arrow:
		return  # Already exists

	# Create arrow indicator using Label (same as StatusPanel)
	var arrow_label := Label.new()
	arrow_label.name = "SelectionArrow"
	arrow_label.text = "◄"  # Left-pointing arrow
	arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow_label.add_theme_font_size_override("font_size", 43)
	arrow_label.modulate = Color(1, 1, 1, 1)  # White
	arrow_label.custom_minimum_size = Vector2(54, 72)
	arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Position manually to the right inside the button
	btn.add_child(arrow_label)

	await get_tree().process_frame

	# Position to the right side, vertically centered (shifted up 6px)
	var btn_size = btn.size
	arrow_label.position = Vector2(btn_size.x - 54, (btn_size.y - 72) / 2.0 - 6)
	arrow_label.size = Vector2(54, 72)

	# Start pulsing animation
	_start_party_arrow_pulse(arrow_label)

func _hide_party_member_arrow(btn: Button) -> void:
	"""Hide arrow indicator from party member"""
	var arrow = btn.get_node_or_null("SelectionArrow")
	if arrow:
		# Stop any running tween
		if arrow.has_meta("pulse_tween"):
			var tween = arrow.get_meta("pulse_tween")
			if tween and is_instance_valid(tween):
				tween.kill()
			arrow.remove_meta("pulse_tween")
		arrow.queue_free()

func _start_party_arrow_pulse(arrow: Control) -> void:
	"""Start pulsing animation for arrow - moves left and right"""
	if arrow.has_meta("pulse_tween"):
		var old_tween = arrow.get_meta("pulse_tween")
		if old_tween and is_instance_valid(old_tween):
			old_tween.kill()

	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse left 6 pixels then back to base position (matching StatusPanel)
	var base_x = arrow.position.x
	tween.tween_property(arrow, "position:x", base_x - 6, 0.6)
	tween.tween_property(arrow, "position:x", base_x, 0.6)

	arrow.set_meta("pulse_tween", tween)

func _on_party_button_pressed(btn: Button) -> void:
	"""Handle party member button being pressed"""
	btn.grab_focus()

func _on_party_button_focused(btn: Button) -> void:
	"""Handle party member button gaining focus"""
	_current_party_button = btn
	_style_party_member_card(btn, true)

	# Trigger the selection callback
	var token = String(btn.get_meta("member_token", ""))
	var idx = _tokens.find(token)
	if idx >= 0:
		_on_party_selected(idx)

func _on_party_button_unfocused(btn: Button) -> void:
	"""Handle party member button losing focus"""
	_style_party_member_card(btn, false)

func _display_for_token(token: String) -> String:
	if token == "hero":
		return _hero_name()
	# Use first name only for display
	if _gs and _gs.has_method("_first_name_for_id"):
		var v: Variant = _gs.call("_first_name_for_id", token)
		if typeof(v) == TYPE_STRING and String(v) != "":
			return String(v)
	return token.capitalize()

func _current_token() -> String:
	if _current_party_button and _current_party_button.has_meta("member_token"):
		return String(_current_party_button.get_meta("member_token"))
	return (_tokens[0] if _tokens.size() > 0 else "")

func _on_party_selected(index: int) -> void:
	var _label: String = "(Unknown)"
	if index >= 0 and index < _labels.size():
		_label = _labels[index]
	# _member_name.text = _label.to_upper()  # Removed

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
func _style_popup_panel(popup_panel: Panel) -> void:
	"""Apply Core Vibe styling to a panel"""
	var panel_style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (general popup)
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_FULL,        # Fully opaque
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_LARGE          # 12px glow
	)
	popup_panel.add_theme_stylebox_override("panel", panel_style)

func _get_equipment_stats(item_id: String, slot: String) -> Dictionary:
	"""Extract relevant stats from an equipment item based on slot type"""
	if item_id == "" or item_id == "—":
		return {}

	var item_def: Dictionary = _item_def(item_id)
	var stats: Dictionary = {}

	match slot:
		"weapon":
			stats["Attack"] = int(item_def.get("base_watk", 0))
			stats["Accuracy"] = int(item_def.get("base_acc", 0))
			stats["Crit Rate"] = int(item_def.get("crit_bonus_pct", 0))
			stats["Skill Atk"] = int(item_def.get("skill_atk_boost", 0))
		"armor":
			stats["Phys Defense"] = int(item_def.get("armor_flat", 0))
			stats["Skill Defense"] = int(item_def.get("ward_flat", 0))
		"head":
			stats["HP Bonus"] = int(item_def.get("max_hp_boost", 0))
			stats["MP Bonus"] = int(item_def.get("max_mp_boost", 0))
			stats["Skill Defense"] = int(item_def.get("ward_flat", 0))
		"foot":
			stats["Evasion"] = int(item_def.get("base_eva", 0))
			stats["Speed"] = int(item_def.get("speed", 0))
		"bracelet":
			stats["Sigil Slots"] = int(item_def.get("sigil_slots", 0))

	return stats

func _compare_stat_value(current_val: int, new_val: int) -> Color:
	"""Return color based on stat comparison: Core Vibe colors"""
	if new_val > current_val:
		return aCoreVibeTheme.COLOR_ELECTRIC_LIME  # Electric Lime - better
	elif new_val < current_val:
		return aCoreVibeTheme.COLOR_BUBBLE_MAGENTA  # Bubble Magenta - worse
	else:
		return aCoreVibeTheme.COLOR_MILK_WHITE  # Milk White - same

func _build_equipment_comparison_panel(item_id: String, slot: String, current_stats: Dictionary, title: String) -> Panel:
	"""Build a comparison panel showing equipment stats"""
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(220, 280)
	_style_popup_panel(panel)

	# Add margin container for padding
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title (Core Vibe: Sky Cyan for popup titles)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
	vbox.add_child(title_label)

	# Item name (Core Vibe: Dimmed Milk White for empty, Electric Lime for filled)
	var name_label := Label.new()
	if item_id == "" or item_id == "—":
		name_label.text = "(Empty)"
		name_label.add_theme_color_override("font_color", Color(aCoreVibeTheme.COLOR_MILK_WHITE.r, aCoreVibeTheme.COLOR_MILK_WHITE.g, aCoreVibeTheme.COLOR_MILK_WHITE.b, 0.4))
	else:
		name_label.text = _pretty_item(item_id)
		name_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(name_label)

	# Show type for weapons and armor, or slot name for head/foot/bracelet
	if item_id != "" and item_id != "—":
		var item_def: Dictionary = _item_def(item_id)
		var type_text: String = ""

		if slot == "weapon" and item_def.has("watk_type_tag"):
			var wtype: String = String(item_def.get("watk_type_tag", "")).capitalize()
			if wtype != "":
				type_text = wtype
		elif slot == "armor" and item_def.has("armor_type"):
			var atype: String = String(item_def.get("armor_type", "")).capitalize()
			if atype != "":
				type_text = atype + " Armor"
		elif slot == "head":
			type_text = "Headwear"
		elif slot == "foot":
			type_text = "Footwear"
		elif slot == "bracelet":
			type_text = "Bracelet"

		if type_text != "":
			var type_label := Label.new()
			type_label.text = type_text
			type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			type_label.add_theme_font_size_override("font_size", 10)
			# Core Vibe: Citrus Yellow for type/category labels
			type_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_CITRUS_YELLOW)
			vbox.add_child(type_label)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Stats container
	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(stats_vbox)

	# Get stats for this item
	var item_stats: Dictionary = _get_equipment_stats(item_id, slot)

	# Display stats with color coding
	for stat_name in item_stats.keys():
		var value: int = item_stats[stat_name]
		var color: Color = Color(1.0, 1.0, 1.0)  # Default white

		# Compare with current stats if available
		if current_stats.has(stat_name):
			color = _compare_stat_value(current_stats[stat_name], value)

		var stat_hbox := HBoxContainer.new()
		stats_vbox.add_child(stat_hbox)

		# Stat name (Core Vibe: Milk White for stat labels)
		var stat_label := Label.new()
		stat_label.text = stat_name + ":"
		stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_label.add_theme_font_size_override("font_size", 11)
		stat_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		stat_hbox.add_child(stat_label)

		# Stat value with color
		var value_label := Label.new()
		value_label.text = str(value)
		value_label.add_theme_font_size_override("font_size", 11)
		value_label.add_theme_color_override("font_color", color)
		stat_hbox.add_child(value_label)

	# Add description if not empty
	if item_id != "" and item_id != "—":
		var item_def: Dictionary = _item_def(item_id)
		if item_def.has("description") and String(item_def.get("description", "")).strip_edges() != "":
			var desc_sep := HSeparator.new()
			vbox.add_child(desc_sep)

			var desc_label := Label.new()
			desc_label.text = String(item_def.get("description", ""))
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			desc_label.add_theme_font_size_override("font_size", 10)
			# Core Vibe: Semi-transparent Milk White for descriptions
			desc_label.add_theme_color_override("font_color", Color(aCoreVibeTheme.COLOR_MILK_WHITE.r, aCoreVibeTheme.COLOR_MILK_WHITE.g, aCoreVibeTheme.COLOR_MILK_WHITE.b, 0.7))
			vbox.add_child(desc_label)

	return panel

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

	# Get current equipment stats for comparison
	var current_stats: Dictionary = _get_equipment_stats(cur_id, slot)

	# Create CanvasLayer overlay for proper input blocking
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.process_priority = -1000
	get_tree().root.add_child(overlay)

	# Create main container for three-panel layout
	var main_container := Control.new()
	main_container.process_mode = Node.PROCESS_MODE_ALWAYS
	main_container.process_priority = -1000
	main_container.z_index = 100
	main_container.modulate = Color(1, 1, 1, 0)  # Start hidden to prevent flash
	overlay.add_child(main_container)

	# Set active popup and overlay immediately
	_active_popup = main_container
	_active_overlay = overlay

	# HBoxContainer to hold three panels side by side
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	main_container.add_child(hbox)

	# LEFT PANEL - Current Equipment
	var left_panel: Panel = _build_equipment_comparison_panel(cur_id, slot, {}, "CURRENT")
	hbox.add_child(left_panel)

	# CENTER PANEL - Selection List
	var center_panel := Panel.new()
	center_panel.custom_minimum_size = Vector2(320, 280)
	_style_popup_panel(center_panel)
	hbox.add_child(center_panel)

	# Center panel content
	var center_margin := MarginContainer.new()
	center_margin.add_theme_constant_override("margin_left", 20)
	center_margin.add_theme_constant_override("margin_top", 20)
	center_margin.add_theme_constant_override("margin_right", 20)
	center_margin.add_theme_constant_override("margin_bottom", 20)
	center_panel.add_child(center_margin)

	var center_vbox := VBoxContainer.new()
	center_vbox.add_theme_constant_override("separation", 8)
	center_margin.add_child(center_vbox)

	# Title label
	var title := Label.new()
	title.text = "Select %s" % slot.capitalize()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center_vbox.add_child(title)

	# Item list
	var item_list := ItemList.new()
	item_list.custom_minimum_size = Vector2(280, 200)
	item_list.focus_mode = Control.FOCUS_ALL
	center_vbox.add_child(item_list)

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
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(100, 40)
	back_btn.pressed.connect(_popup_cancel)
	center_vbox.add_child(back_btn)

	# RIGHT PANEL CONTAINER - Holds the comparison panel
	var right_container := Control.new()
	right_container.custom_minimum_size = Vector2(220, 280)
	hbox.add_child(right_container)

	# Create initial right panel
	var initial_item_id: String = ""
	if not item_ids.is_empty():
		initial_item_id = item_ids[0]
	var right_panel: Panel = _build_equipment_comparison_panel(initial_item_id, slot, current_stats, "COMPARING")
	right_container.add_child(right_panel)

	# Connect selection change to update right panel
	item_list.item_selected.connect(func(index: int) -> void:
		if index < 0 or index >= item_ids.size():
			return
		var selected_id: String = item_ids[index]

		# Clear old right panel immediately
		for child in right_container.get_children():
			right_container.remove_child(child)
			child.queue_free()

		# Create new right panel with selected item
		var new_panel: Panel = _build_equipment_comparison_panel(selected_id, slot, current_stats, "COMPARING")
		right_container.add_child(new_panel)
	)

	# Auto-size container to fit content - wait TWO frames for proper layout calculation
	await get_tree().process_frame
	await get_tree().process_frame

	# Center container on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	main_container.position = (viewport_size - hbox.size) / 2.0
	print("[LoadoutPanel] Equipment popup centered at: %s, size: %s" % [main_container.position, hbox.size])

	# Fade in popup (now that it's positioned)
	main_container.modulate = Color(1, 1, 1, 1)

	# Select first item and grab focus
	if item_list.item_count > 0:
		var first_enabled = 0
		for i in range(item_list.item_count):
			if not item_list.is_item_disabled(i):
				first_enabled = i
				break
		item_list.select(first_enabled)
		item_list.grab_focus()

	# Store metadata for controller input
	main_container.set_meta("_item_list", item_list)
	main_container.set_meta("_item_ids", item_ids)
	main_container.set_meta("_member_token", member_token)
	main_container.set_meta("_slot", slot)

	# Push popup to aPanelManager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		main_container.set_meta("_is_equipment_popup", true)
		panel_mgr.push_panel(main_container)
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

func _sigil_disp_formatted(inst_id: String) -> String:
	"""Format sigil display with BBCode colors: name (Milk White) + level (Milk White) + active skill (Sky Cyan)"""
	if inst_id == "":
		return "(empty)"

	# Get base and instance data
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

	# Build formatted string with colors
	var milk_white_hex: String = "#F4F7FB"
	var sky_cyan_hex: String = "#4DE9FF"

	var result: String = "[color=%s]%s  (%s)[/color]" % [milk_white_hex, disp_name, lv_str]

	# Add active skill in Sky Cyan
	if _sig and _sig.has_method("get_active_skill_name_for_instance"):
		var a_v: Variant = _sig.call("get_active_skill_name_for_instance", inst_id)
		if typeof(a_v) == TYPE_STRING and String(a_v).strip_edges() != "":
			result += "  —  [color=%s]★ %s[/color]" % [sky_cyan_hex, String(a_v)]

	return result

func _create_empty_sigil_icon() -> TextureRect:
	"""Create item_1906 icon for empty sigil slot"""
	var icon_path: String = "res://assets/graphics/items/individual/item_1906.png"

	if not ResourceLoader.exists(icon_path):
		return null

	var icon: TextureRect = TextureRect.new()
	icon.name = "SigilIcon"
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_texture: Texture2D = load(icon_path)
	icon.texture = icon_texture

	return icon

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

	# DEBUG: Print sigil rebuild info
	print("[DEBUG] Rebuilding sigils for %s: capacity=%d, used=%d, total_slots=8" % [member_token, cap, used])

	# Title shows actual capacity from bracelet
	if _sigils_title:
		_sigils_title.text = "SIGILS  (%d/%d)" % [used, cap]

	# Always create 8 slots, but hide ones beyond bracelet capacity
	var total_slots: int = 8
	for idx in range(total_slots):
		var cur_id: String = (String(sockets[idx]) if idx < sockets.size() else "")

		# Create HBox to hold icon + label
		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.custom_minimum_size = Vector2(180, 0)
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Add icon if sigil is equipped or show item_1906 for empty
		if cur_id != "":
			var icon: TextureRect = _create_sigil_icon(cur_id)
			if icon:
				hbox.add_child(icon)
		else:
			# Show item_1906 icon for empty slots
			var empty_icon: TextureRect = _create_empty_sigil_icon()
			if empty_icon:
				hbox.add_child(empty_icon)

		# Create label with color formatting
		var nm: RichTextLabel = RichTextLabel.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.custom_minimum_size = Vector2(0, 24)  # Minimum height
		nm.fit_content = true
		nm.scroll_active = false
		nm.bbcode_enabled = true
		nm.add_theme_font_size_override("normal_font_size", 12)
		nm.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)

		if cur_id != "":
			nm.text = _sigil_disp_formatted(cur_id)
		else:
			# Empty slot - grey text
			nm.add_theme_color_override("default_color", Color(aCoreVibeTheme.COLOR_MILK_WHITE.r, aCoreVibeTheme.COLOR_MILK_WHITE.g, aCoreVibeTheme.COLOR_MILK_WHITE.b, 0.4))
			nm.text = "(empty)"

		hbox.add_child(nm)

		# Hide slots beyond bracelet capacity
		if idx >= cap:
			hbox.visible = false

		_sigils_list.add_child(hbox)

		# Always show "Equip" button - popup will handle unequip option
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(90, 18)  # Match equipment button size for grid alignment
		btn.add_theme_font_size_override("font_size", 11)
		btn.text = "Equip"
		# Core Vibe: Sky Cyan for sigil equip buttons
		aCoreVibeTheme.style_button(btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_SMALL)
		btn.pressed.connect(Callable(self, "_on_equip_sigil").bind(member_token, idx))

		# Hide button if slot is beyond capacity
		if idx >= cap:
			btn.visible = false

		_sigils_list.add_child(btn)

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

	# Create CanvasLayer overlay for proper input blocking
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.process_priority = -1000
	get_tree().root.add_child(overlay)

	# Create custom popup using Control nodes for proper controller support
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.process_priority = -1000
	popup_panel.z_index = 100
	popup_panel.custom_minimum_size = Vector2(340, 310)
	popup_panel.modulate = Color(1, 1, 1, 0)  # Start hidden to prevent flash in top-left corner
	_style_popup_panel(popup_panel)  # Apply ToastPopup styling
	overlay.add_child(popup_panel)

	# Set active popup and overlay immediately to prevent multiple popups
	_active_popup = popup_panel
	_active_overlay = overlay

	# Add margin container for padding (ToastPopup style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	popup_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title label (ToastPopup style)
	var title: Label = Label.new()
	title.text = "Select Sigil (Socket %d)" % (socket_index + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

	# Add back button (ToastPopup style)
	var back_btn: Button = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(100, 40)
	back_btn.pressed.connect(_popup_cancel)
	vbox.add_child(back_btn)

	# Auto-size panel to fit content - wait TWO frames for proper layout calculation
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(40, 40)  # Account for 20px margins on all sides
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0
	print("[LoadoutPanel] Sigil popup centered at: %s, size: %s" % [popup_panel.position, popup_panel.size])

	# Fade in popup (now that it's positioned)
	popup_panel.modulate = Color(1, 1, 1, 1)

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

	var milk_white_hex: String = "#F4F7FB"
	var sky_cyan_hex: String = "#4DE9FF"

	# Convert to RichTextLabel if needed
	if not (_mind_value is RichTextLabel):
		var parent = _mind_value.get_parent()
		if parent:
			var old_pos = _mind_value.get_index()
			var rtl = RichTextLabel.new()
			rtl.name = "Value"
			rtl.size_flags_horizontal = _mind_value.size_flags_horizontal
			rtl.size_flags_vertical = _mind_value.size_flags_vertical
			rtl.custom_minimum_size = _mind_value.custom_minimum_size
			rtl.fit_content = true
			rtl.scroll_active = false
			rtl.bbcode_enabled = true
			rtl.add_theme_font_size_override("normal_font_size", 14)

			parent.remove_child(_mind_value)
			_mind_value.queue_free()
			parent.add_child(rtl)
			parent.move_child(rtl, old_pos)
			_mind_value = rtl

	if member_token == "hero":
		# For player: "Omega" (Milk White) " - Active: " (Milk White) "Void" (Sky Cyan)
		var active_type: String = _get_hero_active_type()
		_mind_value.text = "[color=%s]%s  —  Active: [/color][color=%s]%s[/color]" % [milk_white_hex, mt, sky_cyan_hex, active_type]
		if _mind_switch_btn:
			_mind_switch_btn.text = "Switch"
			_mind_switch_btn.disabled = false
	else:
		# For other members: just "Data" (Milk White)
		_mind_value.text = "[color=%s]%s[/color]" % [milk_white_hex, (mt if mt != "" else "—")]
		if _mind_switch_btn:
			_mind_switch_btn.text = "—"
			_mind_switch_btn.disabled = true

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

	# Get the parent HBox to add icon to
	var parent_hbox: HBoxContainer = label.get_parent() as HBoxContainer

	if id == "" or id == "—":
		# Empty slot - show item_1906 icon with placeholder
		var placeholder: String = ""
		match slot:
			"weapon": placeholder = "(Weapon)"
			"armor": placeholder = "(Armor)"
			"head": placeholder = "(Headwear)"
			"foot": placeholder = "(Footwear)"
			"bracelet": placeholder = "(Bracelet)"
			_: placeholder = "—"

		label.text = placeholder
		# Core Vibe: Dimmed Milk White for empty slots
		label.add_theme_color_override("font_color", Color(aCoreVibeTheme.COLOR_MILK_WHITE.r, aCoreVibeTheme.COLOR_MILK_WHITE.g, aCoreVibeTheme.COLOR_MILK_WHITE.b, 0.4))

		# Show item_1906 icon for empty slots
		_set_empty_slot_icon(parent_hbox)
	else:
		# Has equipment - show item name
		var item_name: String = id
		if _eq and _eq.has_method("get_item_display_name"):
			var v: Variant = _eq.call("get_item_display_name", id)
			if typeof(v) == TYPE_STRING: item_name = String(v)

		label.text = item_name
		# Core Vibe: Sky Cyan for equipped items
		label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)

		# Add/update icon
		_set_equipment_icon(parent_hbox, id)

func _create_sigil_icon(instance_id: String) -> TextureRect:
	"""Create an icon TextureRect for a sigil instance"""
	if not _sig:
		return null

	# Get the base sigil ID from the instance
	var base_id: String = ""
	if _sig.has_method("get_base_id"):
		var v: Variant = _sig.call("get_base_id", instance_id)
		if typeof(v) == TYPE_STRING:
			base_id = String(v)

	if base_id == "":
		return null

	# Get item definition to find icon number
	var item_def: Dictionary = {}
	if _eq and _eq.has_method("get_item_def"):
		var v: Variant = _eq.get_item_def(base_id)
		if typeof(v) == TYPE_DICTIONARY:
			item_def = v as Dictionary

	# Check if item has icon
	if not item_def.has("icon") or item_def["icon"] == null:
		return null

	var icon_value = item_def["icon"]
	# Skip if icon is empty string or "null" string
	if typeof(icon_value) == TYPE_STRING and (icon_value == "" or icon_value == "null"):
		return null

	# Convert to string and pad to 4 digits
	var icon_num: String = str(icon_value).pad_zeros(4)
	var icon_path: String = "res://assets/graphics/items/individual/item_%s.png" % icon_num

	if not ResourceLoader.exists(icon_path):
		return null

	# Create icon TextureRect
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(24, 24)  # Small icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load and set texture
	var icon_texture: Texture2D = load(icon_path)
	icon.texture = icon_texture

	return icon

func _hide_equipment_icon(hbox: HBoxContainer) -> void:
	"""Hide or remove the icon from equipment slot"""
	if not hbox:
		return
	var icon: TextureRect = hbox.get_node_or_null("EquipIcon")
	if icon:
		icon.visible = false

func _set_equipment_icon(hbox: HBoxContainer, item_id: String) -> void:
	"""Set the icon for an equipped item"""
	if not hbox:
		return

	# Get item definition to find icon number
	var item_def: Dictionary = {}
	if _eq and _eq.has_method("get_item_def"):
		var v: Variant = _eq.get_item_def(item_id)
		if typeof(v) == TYPE_DICTIONARY:
			item_def = v as Dictionary

	# Check if item has icon
	if not item_def.has("icon") or item_def["icon"] == null:
		_hide_equipment_icon(hbox)
		return

	var icon_value = item_def["icon"]
	# Skip if icon is empty string or "null" string
	if typeof(icon_value) == TYPE_STRING and (icon_value == "" or icon_value == "null"):
		_hide_equipment_icon(hbox)
		return

	# Convert to string and pad to 4 digits
	var icon_num: String = str(icon_value).pad_zeros(4)
	var icon_path: String = "res://assets/graphics/items/individual/item_%s.png" % icon_num

	if not ResourceLoader.exists(icon_path):
		_hide_equipment_icon(hbox)
		return

	# Get or create icon TextureRect
	var icon: TextureRect = hbox.get_node_or_null("EquipIcon")
	if not icon:
		icon = TextureRect.new()
		icon.name = "EquipIcon"
		icon.custom_minimum_size = Vector2(24, 24)  # Small icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Add icon before the label
		hbox.add_child(icon)
		hbox.move_child(icon, 0)

	# Load and set texture
	var icon_texture: Texture2D = load(icon_path)
	icon.texture = icon_texture
	icon.visible = true

func _set_empty_slot_icon(hbox: HBoxContainer) -> void:
	"""Set the item_1906 icon for an empty equipment slot"""
	if not hbox:
		return

	var icon_path: String = "res://assets/graphics/items/individual/item_1906.png"

	if not ResourceLoader.exists(icon_path):
		print("[LoadoutPanel] Warning: item_1906.png not found at %s" % icon_path)
		_hide_equipment_icon(hbox)
		return

	# Get or create icon TextureRect
	var icon: TextureRect = hbox.get_node_or_null("EquipIcon")
	if not icon:
		icon = TextureRect.new()
		icon.name = "EquipIcon"
		icon.custom_minimum_size = Vector2(24, 24)  # Small icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Add icon before the label
		hbox.add_child(icon)
		hbox.move_child(icon, 0)

	# Load and set texture
	var icon_texture: Texture2D = load(icon_path)
	icon.texture = icon_texture
	icon.visible = true

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
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.custom_minimum_size = Vector2(180, 0)  # Approximately 30 characters at 12pt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_font_size_override("font_size", 12)
	return l

func _value_cell(txt: String) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_font_size_override("font_size", 12)
	return l

func _get_initiative_tier(tpo: int) -> int:
	"""Get initiative tier based on TPO value (1-4)"""
	if tpo <= 3:
		return 1
	elif tpo <= 6:
		return 2
	elif tpo <= 9:
		return 3
	else:
		return 4

func _get_dice_notation(tier: int) -> String:
	"""Get dice notation for initiative tier"""
	match tier:
		1: return "1D20"
		2: return "2D20"
		3: return "3D20"
		4: return "4D20"
		_: return "1D20"

func _create_stat_cell(stat_label: String, value: String) -> PanelContainer:
	"""Create a rounded Core Vibe stat cell"""
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 30)

	# Core Vibe: Ink Charcoal background with rounded corners
	var style := StyleBoxFlat.new()
	style.bg_color = aCoreVibeTheme.COLOR_INK_CHARCOAL
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	# Add margin for padding inside cell
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	# HBoxContainer to hold label and value side by side
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	margin.add_child(hbox)

	# Label - 20 characters wide (Core Vibe: Milk White)
	var label := Label.new()
	label.text = stat_label
	label.custom_minimum_size = Vector2(120, 0)  # ~20 characters at 12pt
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hbox.add_child(label)

	# Value - 5 characters wide (Core Vibe: Sky Cyan for stat values)
	var value_label := Label.new()
	value_label.text = value
	value_label.custom_minimum_size = Vector2(30, 0)  # ~5 characters at 12pt
	value_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

	return panel

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

func _rebuild_stats_grid(member_token: String, _equip: Dictionary) -> void:
	"""Build battle stats grid from CombatProfileSystem (matches StatsPanel)"""
	if _stats_grid == null: return
	_clear_stats_grid()

	if not _cps:
		print("[LoadoutPanel] CombatProfileSystem not available")
		return

	# Get combat profile
	var profile: Dictionary = {}
	if _cps.has_method("get_profile"):
		var profile_v = _cps.call("get_profile", member_token)
		if typeof(profile_v) == TYPE_DICTIONARY:
			profile = profile_v

	# Display all battle stats in 2 columns
	var weapon: Dictionary = profile.get("weapon", {})
	var defense: Dictionary = profile.get("defense", {})
	var stats: Dictionary = profile.get("stats", {})

	# Get core stats for calculations
	var brw: int = stats.get("BRW", 1)
	var mnd: int = stats.get("MND", 1)
	var tpo: int = stats.get("TPO", 1)
	var vtl: int = stats.get("VTL", 1)
	var _fcs: int = stats.get("FCS", 1)

	# Calculate derived stats with new formulas
	var skill_atk_bonus: int = weapon.get("skill_atk_boost", 0)
	var s_atk: int = mnd + skill_atk_bonus

	# Accuracy: Base + TPO×2.0 (each TPO point adds 0.20 percentage points)
	var weapon_acc: int = weapon.get("accuracy", 0)
	var tpo_acc_bonus: float = tpo * 2.0
	var total_acc: float = weapon_acc + tpo_acc_bonus

	# Crit Rate: 5% + BRW×0.5% + weapon/equipment bonuses
	var weapon_crit: int = weapon.get("crit_bonus_pct", 0)
	var crit_rate: float = 5.0 + (brw * 0.5) + weapon_crit
	crit_rate = clamp(crit_rate, 5.0, 50.0)

	# Ailment Power: MND×2%
	var ailment_bonus: float = mnd * 2.0

	# Evasion with stat contribution (VTL×2.0)
	var base_eva: int = defense.get("peva", 0)
	var vtl_eva_bonus: float = vtl * 2.0
	var _total_eva: float = base_eva + vtl_eva_bonus

	# Initiative: Get TPO tier and speed bonus
	var speed_bonus: int = defense.get("speed", 0)
	var init_tier: int = _get_initiative_tier(tpo)
	var init_text: String = "%s + %d" % [_get_dice_notation(init_tier), speed_bonus]

	# Display stats in order: HP/MP/PATK/SATK/PDEF/SDEF/ACC/INIT/CRIT BOOST/AIL BOOST
	_stats_grid.add_child(_create_stat_cell("Max HP", str(profile.get("hp_max", 0))))
	_stats_grid.add_child(_create_stat_cell("Max MP", str(profile.get("mp_max", 0))))
	_stats_grid.add_child(_create_stat_cell("Physical Attack", str(weapon.get("attack", 0))))
	_stats_grid.add_child(_create_stat_cell("Skill Attack", str(s_atk)))
	_stats_grid.add_child(_create_stat_cell("Physical Defense", str(defense.get("pdef", 0))))
	_stats_grid.add_child(_create_stat_cell("Skill Defense", str(defense.get("mdef", 0))))
	_stats_grid.add_child(_create_stat_cell("Accuracy", "%.1f%%" % total_acc))
	_stats_grid.add_child(_create_stat_cell("Initiative", init_text))
	_stats_grid.add_child(_create_stat_cell("Crit Boost", "+%.1f%%" % crit_rate))
	_stats_grid.add_child(_create_stat_cell("Ailment Boost", "+%.0f%%" % ailment_bonus))

# ────────────────── Details Display ──────────────────
func _update_details_for_focused_element() -> void:
	"""Update the details panel based on currently focused equipment/sigil"""
	if not _details_content:
		return

	# Check if we're in equipment navigation mode
	if _nav_state != NavState.EQUIPMENT_NAV or _nav_index < 0 or _nav_index >= _nav_elements.size():
		_details_content.text = "[i]Select equipment or sigil to view details.[/i]"
		return

	var focused = _nav_elements[_nav_index]
	if not is_instance_valid(focused):
		return

	var member_token: String = _current_token()
	if member_token == "":
		return

	# Determine which equipment slot or sigil this button belongs to
	var slot: String = ""
	var sigil_index: int = -1

	# Check equipment buttons
	if focused == _w_btn:
		slot = "weapon"
	elif focused == _a_btn:
		slot = "armor"
	elif focused == _h_btn:
		slot = "head"
	elif focused == _f_btn:
		slot = "foot"
	elif focused == _b_btn:
		slot = "bracelet"
	elif focused == _btn_manage:
		_details_content.text = "[b]Manage Sigils[/b]\n\nOpen the Sigil Skills menu to configure active skills for each equipped sigil."
		return
	elif focused == _mind_switch_btn:
		var base_type: String = _get_member_mind_type(member_token)
		var cur_type: String = _get_hero_active_type()

		# Get weakness and resistance
		var weakness: String = _get_type_weakness(cur_type)
		var resistance: String = _get_type_resistance(cur_type)

		var details: String = "[b]Switch Active Type[/b]\n\n"

		if member_token == "hero":
			details += "[b]Omega Typing[/b]\n"
			details += "Base Type: [color=#FFC0CB]%s[/color]\n\n" % base_type

		details += "[b]Current Active Type:[/b] [color=#FFC0CB]%s[/color]\n" % cur_type

		if weakness != "":
			details += "Weak to: [color=#FF6666]%s[/color]\n" % weakness
		else:
			details += "Weak to: None\n"

		if resistance != "":
			details += "Resists: [color=#66FF66]%s[/color]\n" % resistance
		else:
			details += "Resists: None\n"

		details += "\nSwitch your active type to match sigil schools and optimize type effectiveness."

		_details_content.text = details
		return
	else:
		# Check if it's a sigil button
		if _sigils_list:
			var idx_counter: int = 0
			for child in _sigils_list.get_children():
				if not is_instance_valid(child) or child.is_queued_for_deletion():
					continue
				if child is Button:
					if child == focused:
						sigil_index = idx_counter  # Button index directly corresponds to sigil slot
						break
					idx_counter += 1

	# Show equipment details
	if slot != "":
		_show_equipment_details(member_token, slot)
	# Show sigil details
	elif sigil_index >= 0:
		_show_sigil_details(member_token, sigil_index)
	else:
		_details_content.text = "[i]Select equipment or sigil to view details.[/i]"

func _show_equipment_details(member_token: String, slot: String) -> void:
	"""Display details for a specific equipment slot"""
	var equip: Dictionary = _fetch_equip_for(member_token)
	var item_id: String = String(equip.get(slot, ""))

	if item_id == "" or item_id == "—":
		var slot_name: String = slot.capitalize()
		_details_content.text = "[b]%s[/b]\n\n[i]No %s equipped[/i]\n\nPress Accept to equip an item." % [slot_name, slot.to_lower()]
		return

	# Get item definition
	var item_def: Dictionary = _item_def(item_id)
	var display_name: String = _pretty_item(item_id)

	# Build details string
	var details: String = "[b]%s[/b]\n" % display_name

	# Add item type
	var slot_label: String = slot.capitalize()
	if slot == "head":
		slot_label = "Headwear"
	elif slot == "foot":
		slot_label = "Footwear"
	details += "[color=#888888]%s[/color]\n\n" % slot_label

	# Add stats based on slot type
	match slot:
		"weapon":
			if item_def.has("base_watk"):
				details += "Attack: [color=#FFC0CB]%d[/color]\n" % int(item_def.get("base_watk", 0))
			if item_def.has("base_acc"):
				details += "Accuracy: [color=#FFC0CB]%d%%[/color]\n" % int(item_def.get("base_acc", 0))
			if item_def.has("crit_bonus_pct"):
				details += "Crit Rate: [color=#FFC0CB]%d%%[/color]\n" % int(item_def.get("crit_bonus_pct", 0))
			if item_def.has("skill_atk_boost"):
				details += "Skill Atk: [color=#FFC0CB]%d[/color]\n" % int(item_def.get("skill_atk_boost", 0))
			if item_def.has("watk_type_tag"):
				var wtype: String = String(item_def.get("watk_type_tag", ""))
				details += "Type: [color=#FFC0CB]%s[/color]\n" % wtype
				var weakness: String = _get_weapon_type_weakness(wtype)
				if weakness != "":
					details += "Weak to: [color=#FF6666]%s[/color]\n" % weakness
				elif wtype.to_lower() == "wand":
					details += "[color=#FF8866]+10%% Physical Damage Taken[/color]\n"

		"armor":
			if item_def.has("armor_flat"):
				details += "Physical Defense: [color=#FFC0CB]%d[/color]\n" % int(item_def.get("armor_flat", 0))
			if item_def.has("ward_flat"):
				details += "Skill Defense: [color=#FFC0CB]%d[/color]\n" % int(item_def.get("ward_flat", 0))
			if item_def.has("armor_type"):
				var atype: String = String(item_def.get("armor_type", "")).capitalize()
				if atype != "":
					details += "Type: [color=#FFC0CB]%s[/color]\n" % atype

		"head":
			if item_def.has("max_hp_boost"):
				details += "HP Bonus: [color=#FFC0CB]+%d[/color]\n" % int(item_def.get("max_hp_boost", 0))
			if item_def.has("max_mp_boost"):
				details += "MP Bonus: [color=#FFC0CB]+%d[/color]\n" % int(item_def.get("max_mp_boost", 0))
			if item_def.has("ward_flat"):
				details += "Skill Defense: [color=#FFC0CB]%d[/color]\n" % int(item_def.get("ward_flat", 0))

		"foot":
			if item_def.has("base_eva"):
				details += "Evasion: [color=#FFC0CB]%d[/color]\n" % int(item_def.get("base_eva", 0))
			if item_def.has("speed"):
				details += "Speed: [color=#FFC0CB]%d[/color]\n" % int(item_def.get("speed", 0))

		"bracelet":
			if item_def.has("sigil_slots"):
				details += "Sigil Slots: [color=#FFC0CB]%d[/color]\n" % int(item_def.get("sigil_slots", 0))

	# Add description if available
	if item_def.has("description") and String(item_def.get("description", "")).strip_edges() != "":
		details += "\n[color=#AAAAAA]%s[/color]" % String(item_def.get("description", ""))

	_details_content.text = details

func _show_sigil_details(member_token: String, socket_index: int) -> void:
	"""Display details for a specific sigil socket"""
	if not _sig:
		return

	# Get current sigil in this socket
	var sockets: PackedStringArray = PackedStringArray()
	if _sig.has_method("get_loadout"):
		var v: Variant = _sig.call("get_loadout", member_token)
		if typeof(v) == TYPE_PACKED_STRING_ARRAY:
			sockets = v as PackedStringArray
		elif typeof(v) == TYPE_ARRAY:
			for s in (v as Array): sockets.append(String(s))

	if socket_index >= sockets.size() or String(sockets[socket_index]) == "":
		_details_content.text = "[b]Sigil Socket %d[/b]\n\n[i]Empty socket[/i]\n\nPress Accept to equip a sigil." % (socket_index + 1)
		return

	var inst_id: String = String(sockets[socket_index])

	# Get base sigil ID
	var base_id: String = inst_id
	if _sig.has_method("get_base_from_instance"):
		base_id = String(_sig.call("get_base_from_instance", inst_id))

	# Get display name
	var display_name: String = base_id
	if _sig.has_method("get_display_name_for"):
		var v: Variant = _sig.call("get_display_name_for", base_id)
		if typeof(v) == TYPE_STRING:
			display_name = String(v)

	# Get level
	var level: int = 1
	if _sig.has_method("get_instance_level"):
		level = int(_sig.call("get_instance_level", inst_id))

	var level_str: String = "MAX" if level >= 4 else "Level %d" % level

	# Get element/school
	var school: String = ""
	if _sig.has_method("get_element_for_instance"):
		school = String(_sig.call("get_element_for_instance", inst_id))
	elif _sig.has_method("get_element_for"):
		school = String(_sig.call("get_element_for", base_id))

	# Get active skill
	var active_skill: String = ""
	if _sig.has_method("get_active_skill_name_for_instance"):
		var v: Variant = _sig.call("get_active_skill_name_for_instance", inst_id)
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			active_skill = String(v)

	# Build details
	var details: String = "[b]%s[/b]\n" % display_name
	details += "[color=#888888]Sigil - Socket %d[/color]\n\n" % (socket_index + 1)
	details += "Level: [color=#FFC0CB]%s[/color]\n" % level_str

	if school != "":
		details += "School: [color=#FFC0CB]%s[/color]\n" % school

	if active_skill != "":
		details += "Active Skill: [color=#FFC0CB]★ %s[/color]\n" % active_skill
	else:
		details += "Active Skill: [color=#888888]None[/color]\n"

	# Add XP if not maxed
	if level < 4 and _sig.has_method("get_instance_xp"):
		var xp: int = int(_sig.call("get_instance_xp", inst_id))
		var xp_needed: int = 100  # Default, could be calculated based on level
		details += "\nXP: [color=#FFC0CB]%d / %d[/color]" % [xp, xp_needed]

	_details_content.text = details

# ────────────────── Active Type (hero) ──────────────────
func _get_type_weakness(mind_type: String) -> String:
	"""Get what type the given type is weak to"""
	var type_lower: String = mind_type.to_lower()
	match type_lower:
		"fire": return "Water"
		"water": return "Earth"
		"earth": return "Air"
		"air": return "Fire"
		"data": return "Void"
		"void": return "Data"
		"omega": return ""
		_: return ""

func _get_type_resistance(mind_type: String) -> String:
	"""Get what type the given type resists"""
	var type_lower: String = mind_type.to_lower()
	match type_lower:
		"fire": return "Air"
		"water": return "Fire"
		"earth": return "Water"
		"air": return "Earth"
		"data": return "Data"
		"void": return "Void"
		"omega": return ""
		_: return ""

func _get_weapon_type_weakness(weapon_type: String) -> String:
	"""Get what weapon type this type is weak to"""
	var type_lower: String = weapon_type.to_lower()
	match type_lower:
		"slash": return "Pierce"
		"pierce": return "Impact"
		"impact": return "Slash"
		"blunt": return "Slash"
		"wand": return ""  # Wand has no triangle weakness
		_: return ""

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
	"""Show active type picker popup using Panel-based system for controller support"""
	var token: String = _current_token()
	if not (token == "hero" or token.strip_edges().to_lower() == _hero_name().strip_edges().to_lower()):
		return

	# Prevent multiple popups
	if _active_popup and is_instance_valid(_active_popup):
		print("[LoadoutPanel] Popup already open, ignoring active type picker request")
		return

	var schools: Array[String] = _collect_all_schools()
	var cur: String = _get_hero_active_type()

	print("[LoadoutPanel] === Opening Active Type Picker ===")
	print("[LoadoutPanel] Current active type: %s" % cur)

	# Create CanvasLayer overlay for proper input blocking
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.process_priority = -1000
	get_tree().root.add_child(overlay)

	# Create custom popup using Control nodes for proper controller support
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.process_priority = -1000
	popup_panel.z_index = 100
	popup_panel.custom_minimum_size = Vector2(290, 260)
	popup_panel.modulate = Color(1, 1, 1, 0)  # Start hidden to prevent flash in top-left corner
	_style_popup_panel(popup_panel)  # Apply ToastPopup styling
	overlay.add_child(popup_panel)

	# Set active popup and overlay immediately to prevent multiple popups
	_active_popup = popup_panel
	_active_overlay = overlay

	# Add margin container for padding (ToastPopup style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	popup_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title label (ToastPopup style)
	var title: Label = Label.new()
	title.text = "Select Active Type"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	# Item list
	var item_list: ItemList = ItemList.new()
	item_list.custom_minimum_size = Vector2(250, 200)
	item_list.focus_mode = Control.FOCUS_ALL
	vbox.add_child(item_list)

	# Build item list with metadata
	var item_metadata: Array[String] = []

	# Add Omega first
	item_list.add_item("Omega")
	item_metadata.append("Omega")
	if cur.strip_edges().to_lower() == "omega":
		item_list.select(0)

	# Add separator (as disabled item)
	item_list.add_item("───────")
	item_list.set_item_disabled(item_list.item_count - 1, true)
	item_metadata.append("")  # Placeholder for disabled separator

	# Add other schools
	for s in schools:
		if s == "Omega":
			continue
		item_list.add_item(s)
		item_metadata.append(s)
		if s.strip_edges().to_lower() == cur.strip_edges().to_lower():
			item_list.select(item_list.item_count - 1)

	# Add back button (ToastPopup style)
	var back_btn: Button = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(100, 40)
	back_btn.pressed.connect(_popup_cancel)
	vbox.add_child(back_btn)

	# Auto-size panel to fit content - wait TWO frames for proper layout calculation
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(40, 40)  # Account for 20px margins on all sides
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0
	print("[LoadoutPanel] Active type popup centered at: %s, size: %s" % [popup_panel.position, popup_panel.size])

	# Fade in popup (now that it's positioned)
	popup_panel.modulate = Color(1, 1, 1, 1)

	# Select first enabled item if nothing selected, and grab focus
	if item_list.item_count > 0:
		var has_selection = item_list.get_selected_items().size() > 0
		if not has_selection:
			# Find first non-disabled item
			for i in range(item_list.item_count):
				if not item_list.is_item_disabled(i):
					item_list.select(i)
					break
		item_list.grab_focus()

	# Store metadata for controller input
	popup_panel.set_meta("_is_active_type_popup", true)
	popup_panel.set_meta("_item_list", item_list)
	popup_panel.set_meta("_item_metadata", item_metadata)

	# Push popup to aPanelManager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.push_panel(popup_panel)
		print("[LoadoutPanel] Pushed active type popup to aPanelManager stack")

	# Set state to POPUP_ACTIVE
	_nav_state = NavState.POPUP_ACTIVE

	print("[LoadoutPanel] Active type popup opened with %d items" % item_list.item_count)
	print("[LoadoutPanel] ===================================")


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
	"""Open Sigil Skill Menu via panel stack"""
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

	# Add to tree first (required before pushing to panel manager)
	add_child(menu)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.z_index = 100

	# Push to panel manager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.push_panel(menu)
		print("[LoadoutPanel] Pushed SigilSkillMenu to panel stack")

	# Connect cleanup signal
	if not menu.tree_exited.is_connected(Callable(self, "_on_sigil_menu_closed")):
		menu.tree_exited.connect(Callable(self, "_on_sigil_menu_closed"))

	# Update LoadoutPanel state
	_nav_state = NavState.POPUP_ACTIVE
	print("[LoadoutPanel] SigilSkillMenu opened, state = POPUP_ACTIVE")

func _on_sigil_menu_closing() -> void:
	"""Called by SigilSkillMenu BEFORE it closes - set state before panel pops"""
	print("[LoadoutPanel] SigilSkillMenu closing, setting state to EQUIPMENT_NAV")
	_nav_state = NavState.EQUIPMENT_NAV
	# Now when panel_gained_focus runs, it will see EQUIPMENT_NAV and restore focus

func _on_sigil_menu_closed() -> void:
	"""Called when SigilSkillMenu is fully closed (tree_exited)"""
	print("[LoadoutPanel] SigilSkillMenu closed, refreshing loadout")
	# In case levels/skills changed while menu was open
	call_deferred("_refresh_all_for_current")

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

	# STATE 1: POPUP_ACTIVE - Handle even when not "active" (popup is on top in panel stack)
	if _nav_state == NavState.POPUP_ACTIVE:
		_handle_popup_input(event)
		# NOTE: _handle_popup_input decides which inputs to mark as handled
		# Navigation (up/down) is NOT marked as handled, so ItemList can navigate
		return

	# Only handle other states if we're the active panel
	# Accept input when EITHER:
	#   1. We're in PanelManager stack and active (is_active=true)
	#   2. We're managed by GameMenu tabs (visible=true AND not registered in PanelManager)
	# This prevents accepting input after being popped from PanelManager but still visible
	var active = is_active() or (visible and not is_registered())
	if event is InputEventJoypadButton and event.pressed:
		print("[LoadoutPanel._input] Button %d, is_active=%s, visible=%s, registered=%s, nav_state=%s" % [event.button_index, is_active(), visible, is_registered(), _nav_state])
	if not active:
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
	"""Handle input when popup is active (equipment, sigil picker, or sigil menu)

	Only intercept accept/back for equipment/sigil picker popups.
	For SigilSkillMenu, do nothing - it handles its own input.
	"""
	# If SigilSkillMenu is open, don't handle any input - it handles everything
	if _has_active_sigil_menu():
		return

	# Handle equipment/sigil/active type picker popup input
	if event.is_action_pressed("menu_accept"):
		# Route to appropriate handler based on popup type
		if _active_popup and _active_popup.get_meta("_is_active_type_popup", false):
			_popup_accept_active_type()
		elif _active_popup and _active_popup.get_meta("_is_sigil_popup", false):
			_popup_accept_sigil()
		else:
			_popup_accept_item()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		_popup_cancel()
		get_viewport().set_input_as_handled()
	# NOTE: Do NOT handle move_up/move_down here - let ItemList handle its own navigation

func _has_active_sigil_menu() -> bool:
	"""Check if SigilSkillMenu is currently open as a child"""
	for child in get_children():
		if child.get_class() == "SigilSkillMenu" or child.name.contains("SigilSkillMenu"):
			return true
	return false

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
		_popup_close_and_return_to_equipment()
		# Call AFTER popup closes so state is EQUIPMENT_NAV
		call_deferred("_on_sigils_changed", member_token)
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
		_popup_close_and_return_to_equipment()
		# Call AFTER popup closes so state is EQUIPMENT_NAV
		call_deferred("_on_sigils_changed", member_token)
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
				_popup_close_and_return_to_equipment()
				# Call AFTER popup closes so state is EQUIPMENT_NAV
				call_deferred("_on_sigils_changed", member_token)
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
		elif final_inst == "":
			print("[LoadoutPanel] ✗ No instance to equip")

		_popup_close_and_return_to_equipment()
		# Call AFTER popup closes so state is EQUIPMENT_NAV
		call_deferred("_on_sigils_changed", member_token)
		return

	# Unknown kind - just close
	print("[LoadoutPanel] ERROR: Unknown sigil kind: %s" % kind)
	_popup_cancel()

func _popup_accept_active_type() -> void:
	"""User pressed accept on active type popup - set the new active type"""
	if not _active_popup or not is_instance_valid(_active_popup):
		print("[LoadoutPanel] ERROR: No active popup")
		return

	var item_list: ItemList = _active_popup.get_meta("_item_list", null)
	var item_metadata: Array = _active_popup.get_meta("_item_metadata", [])

	if not item_list:
		print("[LoadoutPanel] ERROR: No item_list in active type popup")
		_popup_cancel()
		return

	var picks: PackedInt32Array = item_list.get_selected_items()
	if picks.size() == 0:
		print("[LoadoutPanel] No active type selected")
		_popup_cancel()
		return

	var idx: int = picks[0]
	if idx < 0 or idx >= item_metadata.size():
		print("[LoadoutPanel] Invalid selection index: %d" % idx)
		_popup_cancel()
		return

	# Check if it's a disabled separator
	if item_list.is_item_disabled(idx):
		print("[LoadoutPanel] Selected item is disabled (separator)")
		return  # Don't close, let user select again

	var selected_type: String = item_metadata[idx]
	if selected_type == "":
		print("[LoadoutPanel] Empty active type selected")
		_popup_cancel()
		return

	print("[LoadoutPanel] Setting hero active type to: %s" % selected_type)
	_set_hero_active_type(selected_type)
	_refresh_mind_row("hero")

	_popup_close_and_return_to_equipment()

func _popup_cancel() -> void:
	"""User pressed back on popup - close without equipping"""
	_popup_close_and_return_to_equipment()

func _popup_close_and_return_to_equipment() -> void:
	"""Close popup and return to EQUIPMENT_NAV state at same nav index"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	print("[LoadoutPanel] Closing popup, returning to equipment mode")

	# Store popup and overlay references and clear BEFORE popping (prevents double-free)
	var popup_to_close = _active_popup
	var overlay_to_close = _active_overlay
	_active_popup = null
	_active_overlay = null

	# CRITICAL: Set state to EQUIPMENT_NAV BEFORE popping
	# pop_panel() synchronously calls _on_panel_gained_focus(), which needs correct state
	_nav_state = NavState.EQUIPMENT_NAV

	# Pop from panel manager
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr and panel_mgr.is_panel_active(popup_to_close):
		panel_mgr.pop_panel()

	popup_to_close.queue_free()
	if overlay_to_close and is_instance_valid(overlay_to_close):
		overlay_to_close.queue_free()

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
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		# Block left/right navigation in party select mode
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		_transition_to_equipment_nav()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		# Only mark as handled if we actually exited via PanelManager
		# Otherwise let it bubble to GameMenu
		if _exit_loadout_panel():
			get_viewport().set_input_as_handled()

func _navigate_party(delta: int) -> void:
	"""Navigate up/down in party list"""
	if not _party_list or _party_list.get_child_count() == 0:
		return

	# Find current button index
	var idx = 0
	if _current_party_button:
		for i in range(_party_list.get_child_count()):
			if _party_list.get_child(i) == _current_party_button:
				idx = i
				break

	# Navigate to new index
	idx = clamp(idx + delta, 0, _party_list.get_child_count() - 1)

	# Grab focus on new button
	var btn = _party_list.get_child(idx) as Button
	if btn:
		btn.grab_focus()
		_on_party_button_focused(btn)

func _transition_to_equipment_nav() -> void:
	"""Transition from PARTY_SELECT to EQUIPMENT_NAV"""
	print("[LoadoutPanel] Transition: PARTY_SELECT → EQUIPMENT_NAV")
	_nav_state = NavState.EQUIPMENT_NAV
	_nav_index = 0  # Start at first equipment button
	print("[LoadoutPanel] Calling _animate_panel_focus from transition_to_equipment_nav")
	call_deferred("_animate_panel_focus")
	call_deferred("_rebuild_equipment_navigation_and_focus_first")

func _exit_loadout_panel() -> bool:
	"""Exit LoadoutPanel back to previous panel (StatusPanel)

	Only works when panel is in PanelManager stack. When managed by GameMenu tabs,
	don't try to exit - let the back button bubble up to GameMenu instead.

	Returns: true if we tried to exit via PanelManager, false if we're not in the stack
	"""
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if not panel_mgr:
		print("[LoadoutPanel] No PanelManager - ignoring exit")
		return false

	# Check stack depth - if we're at depth 2 (StatusPanel + LoadoutPanel),
	# we're being managed by GameMenu and should NOT pop ourselves
	var stack_depth: int = panel_mgr.get_stack_depth()
	print("[LoadoutPanel] Back pressed - stack depth: %d, is_active: %s, registered: %s" % [stack_depth, is_active(), is_registered()])

	if stack_depth <= 2:
		print("[LoadoutPanel] Being managed by GameMenu - letting back button bubble up")
		# Don't handle the input - let it bubble up to GameMenu
		return false

	# We're deeper in the stack (e.g., popup open) - pop ourselves
	print("[LoadoutPanel] Exiting to previous panel via PanelManager")
	panel_mgr.pop_panel()
	return true

func _enter_party_select_state() -> void:
	"""Enter PARTY_SELECT state and grab focus on party list"""
	_nav_state = NavState.PARTY_SELECT
	if _party_list and _party_list.get_child_count() > 0:
		# Find current button or grab first one
		var btn_to_focus: Button = _current_party_button
		if not btn_to_focus or not is_instance_valid(btn_to_focus):
			btn_to_focus = _party_list.get_child(0) as Button
		if btn_to_focus:
			btn_to_focus.grab_focus()
	print("[LoadoutPanel] Entered PARTY_SELECT state")
	print("[LoadoutPanel] Calling _animate_panel_focus from enter_party_select_state")
	call_deferred("_animate_panel_focus")

func _animate_panel_focus() -> void:
	"""Animate panels to highlight which one is currently active"""
	print("[LoadoutPanel] _animate_panel_focus called, _nav_state: %s" % NavState.keys()[_nav_state])
	print("[LoadoutPanel] Panel refs - party: %s, middle: %s, stats: %s" % [_party_panel != null, _middle_panel != null, _stats_panel != null])

	if not _party_panel or not _middle_panel or not _stats_panel:
		print("[LoadoutPanel] ERROR: Missing panel references!")
		return

	var left_ratio := BASE_LEFT_RATIO
	var center_ratio := BASE_CENTER_RATIO
	var right_ratio := BASE_RIGHT_RATIO  # Stats panel always stays at base size

	# Determine which panel gets the active scale (only left and center panels animate)
	match _nav_state:
		NavState.PARTY_SELECT:
			left_ratio = BASE_LEFT_RATIO * ACTIVE_SCALE
			center_ratio = BASE_CENTER_RATIO * INACTIVE_SCALE
			# right_ratio stays at BASE_RIGHT_RATIO
		NavState.EQUIPMENT_NAV:
			left_ratio = BASE_LEFT_RATIO * INACTIVE_SCALE
			center_ratio = BASE_CENTER_RATIO * ACTIVE_SCALE
			# right_ratio stays at BASE_RIGHT_RATIO
		NavState.POPUP_ACTIVE:
			# When popup is active, shrink both left and center
			left_ratio = BASE_LEFT_RATIO * INACTIVE_SCALE
			center_ratio = BASE_CENTER_RATIO * INACTIVE_SCALE
			# right_ratio stays at BASE_RIGHT_RATIO

	print("[LoadoutPanel] Animation ratios - left: %.2f, center: %.2f, right: %.2f" % [left_ratio, center_ratio, right_ratio])

	# Create tweens for smooth animation
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(_party_panel, "size_flags_stretch_ratio", left_ratio, ANIM_DURATION)
	tween.tween_property(_middle_panel, "size_flags_stretch_ratio", center_ratio, ANIM_DURATION)
	tween.tween_property(_stats_panel, "size_flags_stretch_ratio", right_ratio, ANIM_DURATION)

	print("[LoadoutPanel] Tween created and started")

## ─────────────────────── STATE 3: EQUIPMENT_NAV ───────────────────────

func _handle_equipment_nav_input(event: InputEvent) -> void:
	"""Handle input when navigating equipment buttons (vertical-only navigation)"""
	if event.is_action_pressed("move_up"):
		_navigate_equipment(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate_equipment(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		# Explicitly block left/right input in equipment mode (vertical-only navigation)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		_activate_current_equipment_button()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		_transition_to_party_select()
		get_viewport().set_input_as_handled()

func _navigate_equipment(delta: int) -> void:
	"""Navigate up/down through equipment buttons (wraps around cyclically)"""
	if _nav_elements.is_empty():
		return

	# Wrap around: pressing down at bottom goes to top, pressing up at top goes to bottom
	var nav_size = _nav_elements.size()
	_nav_index = (_nav_index + delta + nav_size) % nav_size
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
	print("[LoadoutPanel] _rebuild_equipment_navigation_and_restore_focus called")
	_rebuild_equipment_navigation()
	if _nav_index >= 0 and _nav_index < _nav_elements.size():
		_focus_equipment_element(_nav_index)
		print("[LoadoutPanel] Focus restored to index %d" % _nav_index)
	else:
		print("[LoadoutPanel] Index %d out of range (0-%d)" % [_nav_index, _nav_elements.size() - 1])

func _rebuild_equipment_navigation() -> void:
	"""Build list of focusable equipment elements

	Navigation cycles vertically through elements in this order:
	Weapon → Armor → Head → Foot → Bracelet → Sigil Slots → Manage Sigil → Active Type → back to Weapon
	"""
	_nav_elements.clear()

	# Equipment slot buttons (order matters - this determines vertical navigation flow)
	if _w_btn: _nav_elements.append(_w_btn)  # Weapon
	if _a_btn: _nav_elements.append(_a_btn)  # Armor
	if _h_btn: _nav_elements.append(_h_btn)  # Head
	if _f_btn: _nav_elements.append(_f_btn)  # Foot
	if _b_btn: _nav_elements.append(_b_btn)  # Bracelet

	# Sigil slot buttons - GridContainer has Label and Button as direct children
	# FILTER OUT nodes queued for deletion (dynamic count based on equipped sigils)
	if _sigils_list:
		for child in _sigils_list.get_children():
			# Skip nodes queued for deletion (from queue_free())
			if not is_instance_valid(child) or child.is_queued_for_deletion():
				continue
			# Skip invisible elements (locked sigil slots)
			if not child.visible:
				continue
			# In 2x4 grid, buttons are direct children (labels are skipped)
			if child is Button:
				_nav_elements.append(child)  # Sigil slot equip buttons

	# Special buttons (always at the end of navigation cycle)
	if _btn_manage: _nav_elements.append(_btn_manage)  # Manage Sigil button
	if _mind_switch_btn and not _mind_switch_btn.disabled: _nav_elements.append(_mind_switch_btn)  # Switch button (player only)

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
		# Update details panel for the focused element
		_update_details_for_focused_element()
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
			print("[LoadoutPanel] Element valid: %s, is Control: %s" % [is_instance_valid(elem), str(elem is Control) if is_instance_valid(elem) else "N/A"])

func _debug_print_panel_sizes() -> void:
	"""Debug function to print panel sizes after layout"""
	print("\n=== LOADOUT PANEL DEBUG - Panel Sizes ===")

	if _party_panel:
		print("[DEBUG] Party Panel:")
		print("  - Size: %s" % _party_panel.size)
		print("  - Position: %s" % _party_panel.position)
		print("  - Custom Min Size: %s" % _party_panel.custom_minimum_size)

	if _middle_panel:
		print("[DEBUG] Middle/Center Panel (Equipment & Sigils):")
		print("  - Size: %s" % _middle_panel.size)
		print("  - Position: %s" % _middle_panel.position)
		print("  - Custom Min Size: %s" % _middle_panel.custom_minimum_size)

		# Get child container info for more detail
		var margin = _middle_panel.get_node_or_null("Margin")
		if margin:
			print("  - Margin Container Size: %s" % margin.size)
			var vbox = margin.get_node_or_null("VBox")
			if vbox:
				print("  - VBox Size: %s" % vbox.size)
				print("  - VBox Children Count: %d" % vbox.get_child_count())

				# Count sigils displayed
				if _sigils_list:
					var visible_sigils = 0
					for child in _sigils_list.get_children():
						if child.visible:
							visible_sigils += 1
					print("  - Visible Sigil Rows: %d" % (visible_sigils / 2.0))  # Divide by 2 because each row has label + button

	if _stats_panel:
		print("[DEBUG] Stats Panel:")
		print("  - Size: %s" % _stats_panel.size)
		print("  - Position: %s" % _stats_panel.position)
		print("  - Custom Min Size: %s" % _stats_panel.custom_minimum_size)

	print("=== END PANEL DEBUG ===\n")
