extends Control
class_name ProgressionCheatBar

## A small, code-built bar that lets you add:
## - LXP (character XP → auto-levels & milestone perk points)
## - SXP (per-stat XP; toggle to ignore weekly fatigue)
## - BPP (perk points)
##
## Lives in your Main scene. No external nodes required.

const STAT_IDS: PackedStringArray = ["BRW","VTL","TPO","FCS","MND"]
const CHEAT_PATH: String = "/root/aCheatSystem"


@onready var _row  : HBoxContainer = HBoxContainer.new()
@onready var _lbl  : Label         = Label.new()

# LXP
@onready var _lxp_amt : SpinBox = SpinBox.new()
@onready var _btn_lxp_add    : Button = Button.new()
@onready var _btn_lxp_900    : Button = Button.new()
@onready var _btn_lxp_2400   : Button = Button.new()
@onready var _btn_lxp_6000   : Button = Button.new()

# SXP
@onready var _stat_pick      : OptionButton = OptionButton.new()
@onready var _sxp_amt        : SpinBox      = SpinBox.new()
@onready var _chk_ignore_fat : CheckBox     = CheckBox.new()
@onready var _btn_sxp_add    : Button       = Button.new()

# Perk
@onready var _bpp_amt        : SpinBox = SpinBox.new()
@onready var _btn_bpp_add    : Button  = Button.new()

func _ready() -> void:
	# layout container
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 36)
	_row.add_theme_constant_override("separation", 8)
	add_child(_row)

	# title
	_lbl.text = "Progression Cheats:"
	_lbl.custom_minimum_size = Vector2(160, 0)
	_row.add_child(_lbl)

	# --- LXP cluster ---
	var lxp_lbl := Label.new(); lxp_lbl.text = "LXP"
	_row.add_child(lxp_lbl)

	_lxp_amt.min_value = 0; _lxp_amt.max_value = 999999; _lxp_amt.step = 10
	_lxp_amt.value = 900
	_lxp_amt.custom_minimum_size = Vector2(80, 0)
	_row.add_child(_lxp_amt)

	_btn_lxp_add.text = "Add"
	_btn_lxp_900.text = "+900"
	_btn_lxp_2400.text = "+2400"
	_btn_lxp_6000.text = "+6000"
	_row.add_child(_btn_lxp_add)
	_row.add_child(_btn_lxp_900)
	_row.add_child(_btn_lxp_2400)
	_row.add_child(_btn_lxp_6000)

	# --- SXP cluster ---
	var sxp_lbl := Label.new(); sxp_lbl.text = "SXP"
	_row.add_child(sxp_lbl)

	for s in STAT_IDS: _stat_pick.add_item(s)
	_stat_pick.custom_minimum_size = Vector2(90, 0)
	_row.add_child(_stat_pick)

	_sxp_amt.min_value = 0; _sxp_amt.max_value = 10000; _sxp_amt.step = 5
	_sxp_amt.value = 50
	_sxp_amt.custom_minimum_size = Vector2(76, 0)
	_row.add_child(_sxp_amt)

	_chk_ignore_fat.text = "Ignore fatigue"
	_chk_ignore_fat.button_pressed = true
	_row.add_child(_chk_ignore_fat)

	_btn_sxp_add.text = "Add"
	_row.add_child(_btn_sxp_add)

	# --- BPP cluster ---
	var bpp_lbl := Label.new(); bpp_lbl.text = "Perk"
	_row.add_child(bpp_lbl)

	_bpp_amt.min_value = 0; _bpp_amt.max_value = 99; _bpp_amt.step = 1
	_bpp_amt.value = 1
	_bpp_amt.custom_minimum_size = Vector2(64, 0)
	_row.add_child(_bpp_amt)

	_btn_bpp_add.text = "Add"
	_row.add_child(_btn_bpp_add)

	# wire signals
	if not _btn_lxp_add.pressed.is_connected(_on_lxp_add):      _btn_lxp_add.pressed.connect(_on_lxp_add)
	if not _btn_lxp_900.pressed.is_connected(_on_lxp_900):      _btn_lxp_900.pressed.connect(_on_lxp_900)
	if not _btn_lxp_2400.pressed.is_connected(_on_lxp_2400):    _btn_lxp_2400.pressed.connect(_on_lxp_2400)
	if not _btn_lxp_6000.pressed.is_connected(_on_lxp_6000):    _btn_lxp_6000.pressed.connect(_on_lxp_6000)

	if not _btn_sxp_add.pressed.is_connected(_on_sxp_add):      _btn_sxp_add.pressed.connect(_on_sxp_add)
	if not _btn_bpp_add.pressed.is_connected(_on_bpp_add):      _btn_bpp_add.pressed.connect(_on_bpp_add)

	# gently pin to top-left with some padding
	position = Vector2(12, 8)

# ---------------- handlers ----------------

func _on_lxp_add() -> void:
	_apply_lxp(int(_lxp_amt.value))

func _on_lxp_900() -> void:
	_apply_lxp(900)

func _on_lxp_2400() -> void:
	_apply_lxp(2400)

func _on_lxp_6000() -> void:
	_apply_lxp(6000)

func _on_sxp_add() -> void:
	var idx: int = _stat_pick.get_selected()
	var stat: String = _stat_pick.get_item_text(idx) if idx >= 0 else "BRW"
	var amt: int = int(_sxp_amt.value)
	var ignore_fatigue: bool = _chk_ignore_fat.button_pressed
	_apply_sxp(stat, amt, ignore_fatigue)

func _on_bpp_add() -> void:
	_apply_bpp(int(_bpp_amt.value))

# ---------------- core calls (use your autoload) ----------------

func _apply_lxp(amount: int) -> void:
	if amount <= 0: return
	var cs: Node = get_node_or_null(CHEAT_PATH)
	if cs and cs.has_method("add_lxp"):
		cs.call("add_lxp", amount)
	else:
		push_warning("CheatSystem not found or missing add_lxp(). Add Autoload named 'aCheatSystem'.")

func _apply_sxp(stat_id: String, amount: int, ignore_fatigue: bool) -> void:
	if amount <= 0: return
	var cs: Node = get_node_or_null(CHEAT_PATH)
	if cs and cs.has_method("add_sxp"):
		cs.call("add_sxp", stat_id, amount, ignore_fatigue)
	else:
		push_warning("CheatSystem not found or missing add_sxp(stat, amt, ignore_fatigue).")

func _apply_bpp(amount: int) -> void:
	if amount <= 0: return
	var cs: Node = get_node_or_null(CHEAT_PATH)
	if cs and cs.has_method("add_perk_points"):
		cs.call("add_perk_points", amount)
	else:
		push_warning("CheatSystem not found or missing add_perk_points().")
