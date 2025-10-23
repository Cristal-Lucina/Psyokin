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

# Modern phone styling
const PHONE_BEZEL_COLOR  : Color   = Color(0.08, 0.08, 0.1, 1.0)  # Dark bezel
const PHONE_SCREEN_COLOR : Color   = Color(0.05, 0.05, 0.08, 1.0) # Dark screen
const STATUS_BAR_HEIGHT  : float   = 32.0
const HOME_INDICATOR_HEIGHT : float = 24.0
const PHONE_CORNER_RADIUS : int    = 40
const ICON_SIZE          : float   = 64.0

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
var _home_indicator : Control     = null     # bottom home indicator bar

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
	# Left-aligned container for the phone (1/3rd of screen)
	_center = CenterContainer.new()
	_center.name = "Center"
	_center.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_center.anchor_right = 0.0  # Will be set in _layout_device
	add_child(_center)

	# Phone frame (PanelContainer → theme can give rounded panel/padding)
	_phone = PanelContainer.new()
	_phone.name = "Phone"

	# Create rounded phone bezel style
	var phone_style := StyleBoxFlat.new()
	phone_style.bg_color = PHONE_BEZEL_COLOR
	phone_style.corner_radius_top_left = PHONE_CORNER_RADIUS
	phone_style.corner_radius_top_right = PHONE_CORNER_RADIUS
	phone_style.corner_radius_bottom_left = PHONE_CORNER_RADIUS
	phone_style.corner_radius_bottom_right = PHONE_CORNER_RADIUS
	phone_style.content_margin_left = 16
	phone_style.content_margin_right = 16
	phone_style.content_margin_top = 20
	phone_style.content_margin_bottom = 16
	phone_style.shadow_color = Color(0, 0, 0, 0.5)
	phone_style.shadow_size = 20
	phone_style.shadow_offset = Vector2(0, 4)
	_phone.add_theme_stylebox_override("panel", phone_style)

	_center.add_child(_phone)

	# Root vertical layout inside the phone
	_vbox = VBoxContainer.new()
	_vbox.name = "Root"
	_vbox.add_theme_constant_override("separation", 0)
	_phone.add_child(_vbox)

	# Status bar (time + indicators) with modern phone look
	_header = HBoxContainer.new()
	_header.name = "StatusBar"
	_header.custom_minimum_size = Vector2(0, STATUS_BAR_HEIGHT)
	_header.add_theme_constant_override("separation", 8)
	_vbox.add_child(_header)

	# Time on left
	_time_lbl = Label.new()
	_time_lbl.name = "Time"
	_time_lbl.text = _format_time()
	_time_lbl.add_theme_font_size_override("font_size", 15)
	_time_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97, 1))
	_time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_child(_time_lbl)

	# Spacer to push icons to the right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)

	# Signal indicator (modern style)
	var signal_lbl := Label.new()
	signal_lbl.text = "⚫⚫⚫⚫"  # Signal dots
	signal_lbl.add_theme_font_size_override("font_size", 12)
	signal_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	signal_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_child(signal_lbl)

	# Battery indicator
	var battery_lbl := Label.new()
	battery_lbl.text = "100%"
	battery_lbl.add_theme_font_size_override("font_size", 15)
	battery_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97, 1))
	battery_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_child(battery_lbl)

	# Screen area — VBox so screens can add headers + content that expand
	_screen = VBoxContainer.new()
	_screen.name = "Screen"
	_screen.add_theme_constant_override("separation", 0)
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Add screen background
	var screen_bg := StyleBoxFlat.new()
	screen_bg.bg_color = PHONE_SCREEN_COLOR
	screen_bg.content_margin_left = 20
	screen_bg.content_margin_right = 20
	screen_bg.content_margin_top = 20
	screen_bg.content_margin_bottom = 20
	var screen_panel := PanelContainer.new()
	screen_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_panel.add_theme_stylebox_override("panel", screen_bg)
	screen_panel.add_child(_screen)
	_vbox.add_child(screen_panel)

	# Home indicator bar (modern gesture bar)
	_home_indicator = Control.new()
	_home_indicator.name = "HomeIndicator"
	_home_indicator.custom_minimum_size = Vector2(0, HOME_INDICATOR_HEIGHT)
	_vbox.add_child(_home_indicator)

	# Draw the indicator bar in the center
	var indicator_bar := ColorRect.new()
	indicator_bar.color = Color(0.6, 0.6, 0.65, 0.5)
	indicator_bar.custom_minimum_size = Vector2(120, 5)
	indicator_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	indicator_bar.position = Vector2(0, 10)

	var indicator_center := CenterContainer.new()
	indicator_center.add_child(indicator_bar)
	_home_indicator.add_child(indicator_center)
	indicator_center.set_anchors_preset(Control.PRESET_FULL_RECT)

# Phone takes left 1/3rd of screen
func _layout_device() -> void:
	if _center == null:
		return

	var vp: Vector2 = get_viewport_rect().size

	# Set the container to take up left 1/3rd of the screen
	_center.anchor_left = 0.0
	_center.anchor_top = 0.0
	_center.anchor_right = 0.333  # 1/3rd of screen
	_center.anchor_bottom = 1.0
	_center.offset_left = 0
	_center.offset_top = 0
	_center.offset_right = 0
	_center.offset_bottom = 0

	_center.size_flags_horizontal = Control.SIZE_FILL
	_center.size_flags_vertical = Control.SIZE_FILL

	# Phone maintains aspect ratio within the 1/3rd area
	if _phone:
		var available_width = vp.x * 0.333
		var available_height = vp.y

		# Maintain phone aspect ratio
		var phone_aspect = PHONE_DESIGN_SIZE.x / PHONE_DESIGN_SIZE.y
		var container_aspect = available_width / available_height

		if container_aspect > phone_aspect:
			# Container is wider - fit to height
			_phone.custom_minimum_size = Vector2(available_height * phone_aspect * 0.9, available_height * 0.95)
		else:
			# Container is taller - fit to width
			_phone.custom_minimum_size = Vector2(available_width * 0.9, available_width / phone_aspect * 0.95)

	_center.scale = Vector2(1.0, 1.0)

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

	# Add some top spacing
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 40)
	_screen_hold.add_child(top_spacer)

	_home_grid = GridContainer.new()
	_home_grid.columns = 4
	_home_grid.add_theme_constant_override("h_separation", 20)
	_home_grid.add_theme_constant_override("v_separation", 24)
	_home_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_screen_hold.add_child(_home_grid)

	# Modern app icons with colors
	_add_app_tile("messages", "Messages", "💬", Color(0.1, 0.6, 0.9))   # Blue
	_add_app_tile("contacts", "Contacts", "👤", Color(0.5, 0.5, 0.55))  # Gray
	_add_app_tile("bonds",    "Bonds",    "🤝", Color(0.9, 0.3, 0.5))   # Pink
	_add_app_tile("apps",     "Apps",     "⊞",  Color(0.3, 0.7, 0.4))   # Green
	_add_app_tile("settings", "Settings", "⚙",  Color(0.6, 0.6, 0.65))  # Gray

func _add_app_tile(kind: String, label: String, emoji: String, icon_color: Color) -> void:
	# Container for icon + label
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(80, 100)

	# Circular icon button
	var icon_btn := Button.new()
	icon_btn.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_btn.focus_mode = Control.FOCUS_ALL
	icon_btn.tooltip_text = label

	# Create rounded icon background
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = icon_color
	icon_style.corner_radius_top_left = int(ICON_SIZE * 0.25)
	icon_style.corner_radius_top_right = int(ICON_SIZE * 0.25)
	icon_style.corner_radius_bottom_left = int(ICON_SIZE * 0.25)
	icon_style.corner_radius_bottom_right = int(ICON_SIZE * 0.25)
	icon_btn.add_theme_stylebox_override("normal", icon_style)

	# Hover state
	var icon_style_hover := StyleBoxFlat.new()
	icon_style_hover.bg_color = icon_color.lightened(0.1)
	icon_style_hover.corner_radius_top_left = int(ICON_SIZE * 0.25)
	icon_style_hover.corner_radius_top_right = int(ICON_SIZE * 0.25)
	icon_style_hover.corner_radius_bottom_left = int(ICON_SIZE * 0.25)
	icon_style_hover.corner_radius_bottom_right = int(ICON_SIZE * 0.25)
	icon_btn.add_theme_stylebox_override("hover", icon_style_hover)

	# Pressed state
	var icon_style_pressed := StyleBoxFlat.new()
	icon_style_pressed.bg_color = icon_color.darkened(0.1)
	icon_style_pressed.corner_radius_top_left = int(ICON_SIZE * 0.25)
	icon_style_pressed.corner_radius_top_right = int(ICON_SIZE * 0.25)
	icon_style_pressed.corner_radius_bottom_left = int(ICON_SIZE * 0.25)
	icon_style_pressed.corner_radius_bottom_right = int(ICON_SIZE * 0.25)
	icon_btn.add_theme_stylebox_override("pressed", icon_style_pressed)

	icon_btn.text = emoji if USE_EMOJI else "●"
	icon_btn.add_theme_font_size_override("font_size", 32)
	icon_btn.add_theme_color_override("font_color", Color.WHITE)
	icon_btn.pressed.connect(func() -> void: _open_app(kind))

	vbox.add_child(icon_btn)

	# Label below icon
	var lbl := Label.new()
	lbl.text = label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(lbl)

	_home_grid.add_child(vbox)
	_tiles[kind] = icon_btn  # Store the button for badge updates

# -----------------------------------------------------------------------------#
# Shared UI bits
# -----------------------------------------------------------------------------#
func _make_header_row(title: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 44)

	# Back button (modern style)
	var back: Button = Button.new()
	back.text = "‹ Back"
	back.focus_mode = Control.FOCUS_ALL
	back.add_theme_font_size_override("font_size", 16)
	back.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))

	# Flat style for back button
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0, 0, 0, 0)  # Transparent
	back.add_theme_stylebox_override("normal", back_style)
	back.add_theme_stylebox_override("hover", back_style)
	back.add_theme_stylebox_override("pressed", back_style)

	back.pressed.connect(_show_home)
	row.add_child(back)

	# Spacer + centered title
	var spacer_l: Control = Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_l)

	var ttl: Label = Label.new()
	ttl.text = title
	ttl.add_theme_font_size_override("font_size", 17)
	ttl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97, 1))
	ttl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(ttl)

	var spacer_r: Control = Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_r)

	return row

func _panel_wrap(child: Control) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Modern card-style panel
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12, 0.6)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", panel_style)

	p.add_child(child)
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
			sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
			r.add_theme_color_override("default_color", Color(0.7, 0.7, 0.75, 1))
			r.text = "[center][i]Inbox is empty.[/i][/center]"
			body.add_child(r)

		"contacts":
			_screen_hold.add_child(_make_header_row("Contacts"))
			var lbl_c: Label = Label.new()
			lbl_c.text = "Contacts — TBD"
			lbl_c.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
			lbl_c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_screen_hold.add_child(_panel_wrap(lbl_c))

		"bonds":
			_screen_hold.add_child(_make_header_row("Circle Bonds"))
			var lbl_b: Label = Label.new()
			lbl_b.text = "Circle Bonds — TBD"
			lbl_b.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
			lbl_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_screen_hold.add_child(_panel_wrap(lbl_b))

		"apps":
			_screen_hold.add_child(_make_header_row("Apps"))
			var lbl_a: Label = Label.new()
			lbl_a.text = "Apps — TBD"
			lbl_a.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
			lbl_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_screen_hold.add_child(_panel_wrap(lbl_a))

		"settings":
			_screen_hold.add_child(_make_header_row("Settings"))
			var lbl_s: Label = Label.new()
			lbl_s.text = "Settings — TBD"
			lbl_s.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
			lbl_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
