extends Control
class_name PhoneMenu

## PhoneMenu — code-built UI (no scene deps beyond optional Backdrop)
## - Constant on-screen size (centered); scales down only if the window is tiny
## - Home grid of app tiles
## - Screen holder fills correctly and clears between apps
## - Optional emoji labels (toggle USE_EMOJI if your font can’t render them)
## - Remembers last app via /root/aSettings ("phone_last")
## - set_badge(kind, count) appends a small count to the label

# -----------------------------------------------------------------------------#
# Config
# -----------------------------------------------------------------------------#
const USE_EMOJI          : bool    = true
const PHONE_DESIGN_SIZE  : Vector2 = Vector2(420, 820)  # target device size (px)
const PHONE_SAFE_MARGIN  : float   = 48.0               # keep gap to window edges
const PHONE_SCALE_TO_FIT : bool    = true               # downscale to fit if needed

# Optional scene child (ok if missing)
@onready var _backdrop: ColorRect = get_node_or_null("Backdrop") as ColorRect

# Built at runtime
var _center     : CenterContainer = null
var _phone      : PanelContainer  = null
var _vbox       : VBoxContainer   = null
var _header     : HBoxContainer   = null
var _time_lbl   : Label           = null
var _screen     : VBoxContainer   = null     # container for current screen
var _screen_hold: VBoxContainer   = null     # active screen root
var _home_grid  : GridContainer   = null

# kind -> Button (for badge updates)
var _tiles: Dictionary = {}

# -----------------------------------------------------------------------------#
# Lifecycle
# -----------------------------------------------------------------------------#
func _ready() -> void:
	_purge_runtime_children()

	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_build_device_ui()
	_layout_device()
	_show_home()

	# Restore last opened app, if any
	var s: Node = get_node_or_null("/root/aSettings")
	if s and s.has_method("get_value"):
		var last: String = String(s.call("get_value", "phone_last", ""))
		if last != "":
			_open_app(last)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_device()

# -----------------------------------------------------------------------------#
# Cleanup
# -----------------------------------------------------------------------------#
func _purge_runtime_children() -> void:
	for c in get_children():
		if c == _backdrop:
			continue
		(c as Node).queue_free()
	await get_tree().process_frame

# -----------------------------------------------------------------------------#
# Build device
# -----------------------------------------------------------------------------#
func _build_device_ui() -> void:
	# Center container so we can scale/center the whole phone easily
	_center = CenterContainer.new()
	_center.name = "Center"
	add_child(_center)

	# Phone frame (PanelContainer → theme can give rounded panel/padding)
	_phone = PanelContainer.new()
	_phone.name = "Phone"
	_phone.add_theme_constant_override("margin_left",   12)
	_phone.add_theme_constant_override("margin_right",  12)
	_phone.add_theme_constant_override("margin_top",    12)
	_phone.add_theme_constant_override("margin_bottom", 12)
	_center.add_child(_phone)

	# Root vertical layout inside the phone
	_vbox = VBoxContainer.new()
	_vbox.name = "Root"
	_vbox.add_theme_constant_override("separation", 12)
	_phone.add_child(_vbox)

	# Header (time + simple indicators)
	_header = HBoxContainer.new()
	_header.name = "Header"
	_header.add_theme_constant_override("separation", 12)
	_vbox.add_child(_header)

	_time_lbl = Label.new()
	_time_lbl.name = "Time"
	_time_lbl.text = _format_time()
	_header.add_child(_time_lbl)

	var dots: Label = Label.new()
	dots.text = "••••"
	_header.add_child(dots)

	var battery: Label = Label.new()
	battery.text = "▮▮▮▮"
	_header.add_child(battery)

	# Screen area — VBox so screens can add headers + content that expand
	_screen = VBoxContainer.new()
	_screen.name = "Screen"
	_screen.add_theme_constant_override("separation", 10)
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_screen)

# Constant size (downscale only if window is too small)
func _layout_device() -> void:
	if _center == null:
		return

	_center.custom_minimum_size = PHONE_DESIGN_SIZE
	_center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_center.size_flags_vertical   = Control.SIZE_SHRINK_CENTER

	var s: float = 1.0
	if PHONE_SCALE_TO_FIT:
		var vp: Vector2 = get_viewport_rect().size
		var sx: float = (vp.x - PHONE_SAFE_MARGIN) / PHONE_DESIGN_SIZE.x
		var sy: float = (vp.y - PHONE_SAFE_MARGIN) / PHONE_DESIGN_SIZE.y
		s = min(1.0, min(sx, sy))
	_center.scale = Vector2(s, s)

# -----------------------------------------------------------------------------#
# Screen management
# -----------------------------------------------------------------------------#
func _clear_screen() -> void:
	if _screen == null:
		return
	for c in _screen.get_children():
		(c as Node).queue_free()
	# fresh screen root that stretches
	_screen_hold = VBoxContainer.new()
	_screen_hold.add_theme_constant_override("separation", 8)
	_screen_hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen_hold.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_screen.add_child(_screen_hold)

func _ensure_screen_ready() -> void:
	if _screen_hold == null or not is_instance_valid(_screen_hold):
		_clear_screen()

# -----------------------------------------------------------------------------#
# Home
# -----------------------------------------------------------------------------#
func _show_home() -> void:
	_ensure_screen_ready()
	_clear_screen()

	_home_grid = GridContainer.new()
	_home_grid.columns = 4
	_home_grid.add_theme_constant_override("h_separation", 12)
	_home_grid.add_theme_constant_override("v_separation", 14)
	_home_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_grid.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_screen_hold.add_child(_home_grid)

	_add_app_tile("messages", "Messages", ( "💬" if USE_EMOJI else "" ))
	_add_app_tile("contacts", "Contacts", ( "👤" if USE_EMOJI else "" ))
	_add_app_tile("bonds",    "Bonds",    ( "🤝" if USE_EMOJI else "" ))
	_add_app_tile("apps",     "Apps",     ( "✴"  if USE_EMOJI else "" ))
	_add_app_tile("settings", "Settings", ( "⚙"  if USE_EMOJI else "" ))

func _add_app_tile(kind: String, label: String, emoji: String) -> void:
	var b: Button = Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size   = Vector2(96, 96)
	b.focus_mode            = Control.FOCUS_ALL
	b.clip_text             = false
	b.tooltip_text          = label
	b.text = (emoji + "\n" + label) if emoji != "" else label
	b.pressed.connect(func() -> void: _open_app(kind))
	_home_grid.add_child(b)
	_tiles[kind] = b

# -----------------------------------------------------------------------------#
# Shared UI bits
# -----------------------------------------------------------------------------#
func _make_header_row(title: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var back: Button = Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(_show_home)
	row.add_child(back)

	# spacer + centered title
	var spacer_l: Control = Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_l)

	var ttl: Label = Label.new()
	ttl.text = title
	row.add_child(ttl)

	var spacer_r: Control = Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_r)

	return row

func _panel_wrap(child: Control) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override("margin_left",  10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top",    8)
	pad.add_theme_constant_override("margin_bottom", 8)
	p.add_child(pad)
	pad.add_child(child)
	return p

# -----------------------------------------------------------------------------#
# Apps
# -----------------------------------------------------------------------------#
func _open_app(kind: String) -> void:
	# remember last
	var s: Node = get_node_or_null("/root/aSettings")
	if s and s.has_method("set_value"):
		s.call("set_value", "phone_last", kind)

	_ensure_screen_ready()
	_clear_screen()

	match kind:
		"messages":
			_screen_hold.add_child(_make_header_row("Messages"))

			var sc: ScrollContainer = ScrollContainer.new()
			sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sc.size_flags_vertical   = Control.SIZE_EXPAND_FILL
			_screen_hold.add_child(_panel_wrap(sc))

			var body: VBoxContainer = VBoxContainer.new()
			body.add_theme_constant_override("separation", 8)
			body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sc.add_child(body)

			# Empty inbox placeholder
			var r: RichTextLabel = RichTextLabel.new()
			r.bbcode_enabled = true
			r.fit_content = true
			r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			r.text = "[i]Inbox is empty.[/i]"
			body.add_child(r)

		"contacts":
			_screen_hold.add_child(_make_header_row("Contacts"))
			var lbl_c: Label = Label.new()
			lbl_c.text = "Contacts — TBD"
			_screen_hold.add_child(_panel_wrap(lbl_c))

		"bonds":
			_screen_hold.add_child(_make_header_row("Circle Bonds"))
			var lbl_b: Label = Label.new()
			lbl_b.text = "Circle Bonds — TBD"
			_screen_hold.add_child(_panel_wrap(lbl_b))

		"apps":
			_screen_hold.add_child(_make_header_row("Apps"))
			var lbl_a: Label = Label.new()
			lbl_a.text = "Apps — TBD"
			_screen_hold.add_child(_panel_wrap(lbl_a))

		"settings":
			_screen_hold.add_child(_make_header_row("Settings"))
			var lbl_s: Label = Label.new()
			lbl_s.text = "Settings — TBD"
			_screen_hold.add_child(_panel_wrap(lbl_s))

		_:
			_show_home()

# -----------------------------------------------------------------------------#
# Badges
# -----------------------------------------------------------------------------#
func set_badge(kind: String, count: int) -> void:
	var b: Button = _tiles.get(kind, null) as Button
	if b == null:
		return
	var lines: PackedStringArray = b.text.split("\n")
	if lines.size() == 2:
		var cap: String = lines[0]
		var label: String = lines[1].strip_edges()
		b.text = "%s\n%s%s" % [cap, label, ("  (%d)" % count) if count > 0 else ""]
	else:
		b.text = "%s%s" % [b.text, ("  (%d)" % count) if count > 0 else ""]

# -----------------------------------------------------------------------------#
# Utils
# -----------------------------------------------------------------------------#
func _format_time() -> String:
	var t: Dictionary = Time.get_time_dict_from_system()
	return "%02d:%02d" % [int(t.get("hour", 0)), int(t.get("minute", 0))]
