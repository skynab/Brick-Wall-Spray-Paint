extends CanvasLayer
class_name SideMenu

## Collapsible control panel anchored to the right edge. Built in code so the
## scene stays robust. Two-way bound to the SprayTool and the active Nozzle:
## editing a control updates the tool live; switching via keyboard calls
## sync_from_tool() to keep the controls in step.

signal clear_requested
signal undo_requested
signal save_requested
## Emitted when the menu changes the active nozzle or color, so the app can
## refresh other views (e.g. the HUD).
signal tool_changed
## Emitted when the drips on/off toggle changes.
signal drips_toggled(enabled: bool)
## Emitted when the user picks a different brick-wall background.
signal wall_selected(path: String)
## Emitted (on Apply) with the wall's physical size (m) and pixel resolution.
signal wall_dimensions_changed(physical_size: Vector2, resolution: Vector2i)
## Emitted when the fullscreen toggle changes.
signal fullscreen_toggled(enabled: bool)
## Emitted when any vignette control changes (carries all three current values).
signal vignette_changed(strength: float, extent: float, softness: float)
## Emitted when the mouse aim source's distance/pitch/yaw/roll change.
signal mouse_aim_changed(distance: float, pitch: float, yaw: float, roll: float)
## Emitted when the user picks a different aim source.
signal aim_source_selected(index: int)
## Tracker controls.
signal aim_asset_id_changed(id: int)
signal calibrate_requested
## Which three wall corners to sample (TrackerAimSource.CornerOrder index).
signal calib_order_changed(order: int)
signal proximity_toggled(enabled: bool)
signal proximity_threshold_changed(value: float)
## OptiTrack / NatNet connection settings.
signal tracker_connect_requested(server_ip: String, client_ip: String, multicast: bool)
signal tracker_offset_changed(offset: Vector3)
## Wall auto-clear controls.
signal clear_mode_changed(mode: int)
signal clear_interval_changed(seconds: float)

const PANEL_WIDTH := 320.0
const SLIDE_TIME := 0.22
const PREFS_PATH := "user://ui_prefs.cfg"

## Shape dropdown items, in Nozzle.Shape enum order.
const SHAPE_NAMES := ["Round", "Oval", "Line", "Square", "Splatter"]

# (property on Nozzle, label, min, max, step, is_int, is_advanced)
# Only Radius is shown in the Simple view; the rest live under Advanced.
const SLIDER_SPECS := [
	["radius_px", "Radius", 4.0, 250.0, 1.0, false, false],
	["flow", "Flow", 1.0, 40.0, 1.0, true, true],
	["scatter", "Scatter", 0.0, 1.0, 0.01, false, true],
	["droplet_size_px", "Droplet size", 1.0, 40.0, 1.0, false, true],
	["softness", "Softness", 0.0, 1.0, 0.01, false, true],
	["build_rate", "Build rate", 0.0, 1.0, 0.01, false, true],
	["aspect", "Aspect", 1.0, 8.0, 0.1, false, true],
	["angle", "Angle", -180.0, 180.0, 1.0, true, true],
]

var _spray: SprayTool

var _panel: PanelContainer
var _color_btn: ColorPickerButton
var _wall_opt: OptionButton
var _wall_paths: PackedStringArray = PackedStringArray()
var _nozzle_opt: OptionButton
var _shape_opt: OptionButton
var _output_slider: HSlider
var _output_label: Label
var _clear_interval_label: Label
var _clear_status: Label
var _vig_sliders: Dictionary = {}       # key -> HSlider
var _vig_labels: Dictionary = {}        # key -> Label
var _mouse_sliders: Dictionary = {}     # key -> HSlider
var _mouse_labels: Dictionary = {}      # key -> Label
var _aim_opt: OptionButton
var _server_ip_edit: LineEdit
var _client_ip_edit: LineEdit
var _multicast_opt: OptionButton
var _conn_status_label: Label           # live OptiTrack connection state
var _rb_pos_label: Label                # live rigid-body position
var _calib_order_opt: OptionButton      # which 3 corners to sample
var _offset_spins: Dictionary = {}      # "x"/"y"/"z" -> SpinBox
var _phys_w: SpinBox
var _phys_h: SpinBox
var _res_w: SpinBox
var _res_h: SpinBox
var _fullscreen_check: CheckButton
var _prox_value: Label
var _status: Label
var _sliders: Dictionary = {}       # key -> HSlider
var _slider_labels: Dictionary = {} # key -> Label

## Nodes revealed only in the Advanced view.
var _advanced_nodes: Array[Control] = []
var _advanced := false
var _advanced_check: CheckButton

## Per-section collapsed state, keyed by the (upper-cased) section title. Persisted
## so the sidebar reopens the way the user left it.
var _collapsed: Dictionary = {}

var _shown := true
var _tween: Tween


func _ready() -> void:
	_load_prefs()
	_build_ui()
	_apply_advanced_visibility()
	get_viewport().size_changed.connect(_reposition)
	_reposition()


# --- Public API -------------------------------------------------------------

func setup(spray: SprayTool) -> void:
	_spray = spray
	_populate_nozzles()
	sync_from_tool()


## Pull every control's value from the tool / current nozzle (after a keyboard change).
func sync_from_tool() -> void:
	if _spray == null:
		return
	_nozzle_opt.select(_spray.nozzle_index)
	_color_btn.color = _spray.current_color()
	if _shape_opt != null:
		_shape_opt.select(int(_spray.current_nozzle().shape))
	if _output_slider != null:
		_output_slider.set_value_no_signal(_spray.output_rate)
		_output_label.text = "%.2fx" % _spray.output_rate
	_sync_sliders()


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


## Update the live OptiTrack diagnostics. `level` is the severity (0 = not
## connected, 1 = connected, 2 = rigid body streaming) used for colour; `text`
## is the label; `position` is the rigid-body Vector3, or null when unavailable.
func set_tracker_status(level: int, text: String, position) -> void:
	if _conn_status_label != null:
		_conn_status_label.text = text
		var col := Color(1, 0.4, 0.4)        # red — not connected
		if level >= 2:
			col = Color(0.4, 1.0, 0.5)       # green — rigid body streaming
		elif level == 1:
			col = Color(1.0, 0.85, 0.3)      # amber — connected, no rigid body
		_conn_status_label.add_theme_color_override("font_color", col)
	if _rb_pos_label != null:
		if position == null:
			_rb_pos_label.text = "Position: —"
		else:
			_rb_pos_label.text = "Position: (%.3f, %.3f, %.3f)" % [position.x, position.y, position.z]


## Update the auto-clear countdown line (driven by the app each frame).
func set_clear_status(text: String) -> void:
	if _clear_status != null:
		_clear_status.text = text


## Populate the wall-background dropdown. `walls` is an ordered list of
## { name, path } dictionaries (from WallLibrary); `current` is the selected row.
func set_walls(walls: Array, current: int) -> void:
	if _wall_opt == null:
		return
	_wall_opt.clear()
	_wall_paths = PackedStringArray()
	for w in walls:
		_wall_opt.add_item(String(w.get("name", "Wall")))
		_wall_paths.append(String(w.get("path", "")))
	if current >= 0 and current < _wall_paths.size():
		_wall_opt.select(current)


## Populate the aim-source dropdown and select the active one.
func set_aim_sources(labels: PackedStringArray, current: int) -> void:
	if _aim_opt == null:
		return
	_aim_opt.clear()
	for l in labels:
		_aim_opt.add_item(l)
	if current >= 0 and current < labels.size():
		_aim_opt.select(current)


## Reflect an aim change made elsewhere (e.g. the keyboard) without re-emitting.
func select_aim(index: int) -> void:
	if _aim_opt != null and index >= 0 and index < _aim_opt.item_count:
		_aim_opt.select(index)


## True when the panel is visible and the mouse is over it — used by the app to
## suppress spraying while the user interacts with the menu.
func is_pointing_at_menu() -> bool:
	if _panel == null:
		return false
	return _panel.get_global_rect().has_point(_panel.get_global_mouse_position())


func toggle() -> void:
	_shown = not _shown
	if _tween != null and _tween.is_running():
		_tween.kill()
	var target_x := _shown_x() if _shown else _hidden_x()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_panel, "position:x", target_x, SLIDE_TIME)


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)

	# Scroll the controls vertically so the (taller) Advanced list stays reachable
	# when it overflows the panel height.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# Title row: heading + Simple/Advanced toggle.
	var title_row := HBoxContainer.new()
	var title := _make_title("SPRAY CONTROLS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_advanced_check = CheckButton.new()
	_advanced_check.text = "Advanced"
	_advanced_check.button_pressed = _advanced
	_advanced_check.toggled.connect(_on_advanced_toggled)
	title_row.add_child(_advanced_check)
	vbox.add_child(title_row)

	# Wall background section (Simple)
	var wall_content := _add_section(vbox, "Wall")
	_wall_opt = OptionButton.new()
	_wall_opt.item_selected.connect(_on_wall_selected)
	wall_content.add_child(_wall_opt)

	# Color section (Simple)
	var color_content := _add_section(vbox, "Color")
	_color_btn = ColorPickerButton.new()
	_color_btn.custom_minimum_size = Vector2(0, 32)
	_color_btn.color_changed.connect(_on_color_changed)
	color_content.add_child(_color_btn)
	color_content.add_child(_make_palette_row())

	# Nozzle section (Simple): preset + shape + radius. (Advanced sliders live here too.)
	var nozzle_content := _add_section(vbox, "Nozzle")
	_nozzle_opt = OptionButton.new()
	_nozzle_opt.item_selected.connect(_on_nozzle_selected)
	nozzle_content.add_child(_nozzle_opt)

	var shape_row := HBoxContainer.new()
	var shape_label := Label.new()
	shape_label.text = "Shape"
	shape_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_row.add_child(shape_label)
	_shape_opt = OptionButton.new()
	for s in SHAPE_NAMES:
		_shape_opt.add_item(s)
	_shape_opt.item_selected.connect(_on_shape_selected)
	shape_row.add_child(_shape_opt)
	nozzle_content.add_child(shape_row)

	# Output rate (Simple): master "how fast the paint comes out" multiplier.
	var out_box := VBoxContainer.new()
	var out_header := HBoxContainer.new()
	var out_name := Label.new()
	out_name.text = "Output"
	out_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_label = Label.new()
	_output_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	out_header.add_child(out_name)
	out_header.add_child(_output_label)
	out_box.add_child(out_header)
	_output_slider = HSlider.new()
	_output_slider.min_value = 0.1
	_output_slider.max_value = 3.0
	_output_slider.step = 0.05
	_output_slider.value_changed.connect(_on_output_changed)
	out_box.add_child(_output_slider)
	nozzle_content.add_child(out_box)

	for spec in SLIDER_SPECS:
		var row := _make_slider_row(spec)
		nozzle_content.add_child(row)
		if bool(spec[6]):
			_advanced_nodes.append(row)

	# Drips on/off (Advanced). Drips only form when lingering over one spot.
	var drips_check := CheckButton.new()
	drips_check.text = "Drips"
	drips_check.button_pressed = true
	drips_check.toggled.connect(func(on): drips_toggled.emit(on))
	nozzle_content.add_child(drips_check)
	_advanced_nodes.append(drips_check)

	# Reset (Advanced): undo live slider edits.
	var reset_btn := _make_action_button("Reset nozzle", _on_reset_pressed)
	nozzle_content.add_child(reset_btn)
	_advanced_nodes.append(reset_btn)

	# Auto-clear section (Advanced).
	var clear_box := _build_clear_section()
	vbox.add_child(clear_box)
	_advanced_nodes.append(clear_box)

	# Vignette section (Advanced).
	var vig_box := _build_vignette_section()
	vbox.add_child(vig_box)
	_advanced_nodes.append(vig_box)

	# Mouse spray-source 3D placement (Advanced).
	var mouse_box := _build_mouse_aim_section()
	vbox.add_child(mouse_box)
	_advanced_nodes.append(mouse_box)

	# Wall dimensions (physical + pixels) — always visible; core to mapping the
	# render onto the real LED wall.
	vbox.add_child(_build_wall_size_section())

	# OptiTrack / tracker setup — always visible (not gated by Advanced), since
	# the tracked canister is the app's primary input.
	vbox.add_child(_build_optitrack_section())

	# Proximity auto-spray (Advanced — niche).
	var prox_box := _build_proximity_section()
	vbox.add_child(prox_box)
	_advanced_nodes.append(prox_box)

	vbox.add_child(HSeparator.new())

	# Action buttons (Simple)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.add_child(_make_action_button("Clear", func(): clear_requested.emit()))
	actions.add_child(_make_action_button("Undo", func(): undo_requested.emit()))
	actions.add_child(_make_action_button("Save", func(): save_requested.emit()))
	vbox.add_child(actions)

	vbox.add_child(HSeparator.new())

	# Status (OptiTrack state goes here later)
	_status = _make_label("Tracker: —")
	vbox.add_child(_status)

	var hint := _make_label("[M] hide  [Tab] nozzle  [C]/1-7 color")
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(hint)


## Build the wall auto-clear block (mode + interval + countdown).
func _build_clear_section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var content := _add_section(box, "Auto-clear")

	var mode_opt := OptionButton.new()
	mode_opt.add_item("Manual")   # index 0 -> ClearMode.MANUAL
	mode_opt.add_item("Timer")    # index 1 -> ClearMode.TIMER
	mode_opt.item_selected.connect(func(i): clear_mode_changed.emit(i))
	content.add_child(mode_opt)

	var int_header := HBoxContainer.new()
	var int_name := Label.new()
	int_name.text = "Interval"
	int_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear_interval_label = Label.new()
	_clear_interval_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clear_interval_label.text = "100s"
	int_header.add_child(int_name)
	int_header.add_child(_clear_interval_label)
	content.add_child(int_header)

	var int_slider := HSlider.new()
	int_slider.min_value = 10.0
	int_slider.max_value = 600.0
	int_slider.step = 5.0
	int_slider.value = 100.0
	int_slider.value_changed.connect(_on_clear_interval_changed)
	content.add_child(int_slider)

	_clear_status = _make_label("")
	_clear_status.modulate = Color(1, 1, 1, 0.6)
	content.add_child(_clear_status)

	return box


## Build the vignette block (strength / extent / softness), darkening the brick
## toward the edges. (property key, label, min, max, step, default)
## Defaults mirror AppConfig.VIGNETTE_* (kept as literals so this stays a const).
const VIGNETTE_SPECS := [
	["strength", "Strength", 0.0, 1.0, 0.01, 0.0],
	["extent", "Extent", 0.0, 1.2, 0.01, 0.7],
	["softness", "Softness", 0.01, 1.0, 0.01, 0.4],
]


func _build_vignette_section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var content := _add_section(box, "Vignette")

	for spec in VIGNETTE_SPECS:
		var key: String = spec[0]
		var header := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(spec[1])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.text = "%.2f" % float(spec[5])
		header.add_child(name_label)
		header.add_child(value_label)
		content.add_child(header)

		var slider := HSlider.new()
		slider.min_value = spec[2]
		slider.max_value = spec[3]
		slider.step = spec[4]
		slider.value = spec[5]
		slider.value_changed.connect(_on_vignette_changed)
		content.add_child(slider)

		_vig_sliders[key] = slider
		_vig_labels[key] = value_label

	return box


## Mouse spray-source placement controls. (key, label, min, max, step, default, unit)
const MOUSE_AIM_SPECS := [
	["distance", "Distance", 0.0, 2.5, 0.05, 0.0, " m"],
	["pitch", "Pitch", -70.0, 70.0, 1.0, 0.0, "°"],
	["yaw", "Yaw", -70.0, 70.0, 1.0, 0.0, "°"],
	["roll", "Roll", -180.0, 180.0, 1.0, 0.0, "°"],
]


func _build_mouse_aim_section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var content := _add_section(box, "Mouse aim (3D)")

	for spec in MOUSE_AIM_SPECS:
		var key: String = spec[0]
		var header := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(spec[1])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		header.add_child(name_label)
		header.add_child(value_label)
		content.add_child(header)

		var slider := HSlider.new()
		slider.min_value = spec[2]
		slider.max_value = spec[3]
		slider.step = spec[4]
		slider.value = spec[5]
		slider.value_changed.connect(_on_mouse_aim_changed)
		content.add_child(slider)

		_mouse_sliders[key] = slider
		_mouse_labels[key] = value_label
		_update_mouse_label(key)

	content.add_child(_make_action_button("Reset placement", _on_mouse_aim_reset))
	return box


## Always-visible wall-dimensions setup: physical size (m) + pixel resolution.
## Applied on the Apply button (changing resolution reallocates / clears paint).
func _build_wall_size_section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var content := _add_section(box, "Wall size")

	content.add_child(_make_label("Physical (m)"))
	var phys_row := HBoxContainer.new()
	phys_row.add_theme_constant_override("separation", 4)
	_phys_w = _make_dim_spin(0.1, 1000.0, 0.01, 7.1111, "W ")
	_phys_h = _make_dim_spin(0.1, 1000.0, 0.01, 4.0, "H ")
	phys_row.add_child(_phys_w)
	phys_row.add_child(_phys_h)
	content.add_child(phys_row)

	content.add_child(_make_label("Resolution (px)"))
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 4)
	_res_w = _make_dim_spin(16, 16384, 1, 2048, "W ")
	_res_h = _make_dim_spin(16, 16384, 1, 1152, "H ")
	res_row.add_child(_res_w)
	res_row.add_child(_res_h)
	content.add_child(res_row)

	content.add_child(_make_action_button("Apply size", _on_wall_apply))

	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = "Fullscreen (this monitor)"
	_fullscreen_check.toggled.connect(func(on): fullscreen_toggled.emit(on))
	content.add_child(_fullscreen_check)

	var note := _make_label("Match physical & pixel aspect. Changing resolution clears paint.")
	note.add_theme_font_size_override("font_size", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.5)
	content.add_child(note)
	return box


func _make_dim_spin(min_v: float, max_v: float, step: float, value: float, prefix: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.prefix = prefix
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


## Always-visible OptiTrack setup: aim source, NatNet connection, rigid body,
## origin offset, connect + calibrate.
func _build_optitrack_section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var content := _add_section(box, "OptiTrack")

	# Live NatNet diagnostics (updated every frame from the tracker).
	_conn_status_label = _make_label("Not Connected")
	_conn_status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	content.add_child(_conn_status_label)
	_rb_pos_label = _make_label("Position: —")
	_rb_pos_label.modulate = Color(1, 1, 1, 0.7)
	_rb_pos_label.add_theme_font_size_override("font_size", 11)
	content.add_child(_rb_pos_label)

	content.add_child(_make_label("Aim source"))
	_aim_opt = OptionButton.new()
	_aim_opt.item_selected.connect(_on_aim_selected)
	content.add_child(_aim_opt)

	_server_ip_edit = _make_ip_row(content, "Server IP", "127.0.0.1")
	_client_ip_edit = _make_ip_row(content, "Client IP", "127.0.0.1")

	var conn_row := HBoxContainer.new()
	var conn_label := Label.new()
	conn_label.text = "Connection"
	conn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conn_row.add_child(conn_label)
	_multicast_opt = OptionButton.new()
	_multicast_opt.add_item("Multicast")  # index 0 -> multicast
	_multicast_opt.add_item("Unicast")    # index 1 -> unicast
	conn_row.add_child(_multicast_opt)
	content.add_child(conn_row)

	var id_row := HBoxContainer.new()
	var id_label := Label.new()
	id_label.text = "Rigid Body ID"
	id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(id_label)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 9999
	spin.step = 1
	spin.value = 1
	spin.value_changed.connect(func(v): aim_asset_id_changed.emit(int(v)))
	id_row.add_child(spin)
	content.add_child(id_row)

	content.add_child(_make_action_button("Connect", _on_connect_pressed))

	# Manual origin offset (X / Y / Z) for the tracker data.
	content.add_child(_make_label("Origin offset (m)"))
	var off_row := HBoxContainer.new()
	off_row.add_theme_constant_override("separation", 4)
	for axis in ["x", "y", "z"]:
		var s := SpinBox.new()
		s.min_value = -100.0
		s.max_value = 100.0
		s.step = 0.01
		s.value = 0.0
		s.prefix = axis.to_upper() + " "
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(_on_offset_changed)
		off_row.add_child(s)
		_offset_spins[axis] = s
	content.add_child(off_row)

	# Which three adjacent wall corners to sample during calibration.
	content.add_child(_make_label("Calibration corners (in order)"))
	_calib_order_opt = OptionButton.new()
	for label in TrackerAimSource.CORNER_ORDER_LABELS:
		_calib_order_opt.add_item(label)
	_calib_order_opt.item_selected.connect(func(i): calib_order_changed.emit(i))
	content.add_child(_calib_order_opt)

	content.add_child(_make_action_button("Calibrate wall (3 corners)", func(): calibrate_requested.emit()))
	return box


## Build a labeled IP-address text field row and return its LineEdit.
func _make_ip_row(parent: VBoxContainer, label_text: String, default_ip: String) -> LineEdit:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = default_ip
	edit.placeholder_text = "127.0.0.1"
	edit.custom_minimum_size = Vector2(130, 0)
	row.add_child(edit)
	parent.add_child(row)
	return edit


## Proximity auto-spray block (Advanced).
func _build_proximity_section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var content := _add_section(box, "Proximity")

	var prox_check := CheckBox.new()
	prox_check.text = "Auto-spray near wall"
	prox_check.toggled.connect(func(on): proximity_toggled.emit(on))
	content.add_child(prox_check)

	var prox_header := HBoxContainer.new()
	var prox_name := Label.new()
	prox_name.text = "Threshold (m)"
	prox_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prox_value = Label.new()
	_prox_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prox_value.text = "%.3f" % 0.05
	prox_header.add_child(prox_name)
	prox_header.add_child(_prox_value)
	content.add_child(prox_header)
	var prox_slider := HSlider.new()
	prox_slider.min_value = 0.01
	prox_slider.max_value = 0.5
	prox_slider.step = 0.005
	prox_slider.value = 0.05
	prox_slider.value_changed.connect(_on_prox_slider_changed)
	content.add_child(prox_slider)

	return box


func _make_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


## Add a collapsible section to `parent`: a clickable banded header plus a content
## container whose visibility the header toggles. Returns the content container —
## callers add the section's controls to it. Collapse state is restored from prefs.
func _add_section(parent: Control, title: String) -> VBoxContainer:
	var header := _make_section_header(title)
	parent.add_child(header)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	parent.add_child(content)
	var expanded := not bool(_collapsed.get(String(header.get_meta("title")), false))
	content.visible = expanded
	_update_section_header(header, expanded)
	header.pressed.connect(_toggle_section.bind(header, content))
	return content


## Flip a section between expanded/collapsed and remember it.
func _toggle_section(header: Button, content: Control) -> void:
	var expanded := not content.visible
	content.visible = expanded
	_update_section_header(header, expanded)
	_collapsed[String(header.get_meta("title"))] = not expanded
	_save_prefs()


## Refresh a header's disclosure arrow for the given expanded state.
func _update_section_header(header: Button, expanded: bool) -> void:
	header.text = ("▾  " if expanded else "▸  ") + String(header.get_meta("title"))


## A distinct, banded section header (as a button) so groups are easy to tell
## apart and can be clicked to collapse. The disclosure arrow is set by
## _update_section_header; the bare title is stashed in metadata.
func _make_section_header(text: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta("title", text.to_upper())
	b.text = text.to_upper()
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.42, 0.62, 0.55)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(4)
	sb.content_margin_left = 8
	# A bright accent bar down the left edge.
	sb.border_color = Color(0.45, 0.75, 1.0)
	sb.border_width_left = 3
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.26, 0.50, 0.72, 0.7)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	b.add_theme_stylebox_override("focus", sb)
	return b


func _make_palette_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	# Build swatches once the tool is set; placeholder filled in _populate_nozzles.
	row.name = "PaletteRow"
	return row


func _make_slider_row(spec: Array) -> VBoxContainer:
	var key: String = spec[0]
	var box := VBoxContainer.new()
	var header := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = String(spec[1])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(name_label)
	header.add_child(value_label)
	box.add_child(header)

	var slider := HSlider.new()
	slider.min_value = spec[2]
	slider.max_value = spec[3]
	slider.step = spec[4]
	slider.value_changed.connect(_on_slider_changed.bind(key, bool(spec[5]), value_label))
	box.add_child(slider)

	_sliders[key] = slider
	_slider_labels[key] = value_label
	return box


func _make_action_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


# --- Tool binding -----------------------------------------------------------

func _populate_nozzles() -> void:
	_nozzle_opt.clear()
	for n in _spray.nozzles:
		_nozzle_opt.add_item(n.nozzle_name)

	# (Re)build palette swatches now that we have the tool.
	var row := _panel.find_child("PaletteRow", true, false) as HBoxContainer
	if row != null:
		for c in row.get_children():
			c.queue_free()
		for i in _spray.palette.size():
			var sw := Button.new()
			sw.custom_minimum_size = Vector2(0, 24)
			sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var style := StyleBoxFlat.new()
			style.bg_color = _spray.palette[i]
			style.set_corner_radius_all(3)
			sw.add_theme_stylebox_override("normal", style)
			sw.add_theme_stylebox_override("hover", style)
			sw.add_theme_stylebox_override("pressed", style)
			sw.pressed.connect(_on_swatch_pressed.bind(i))
			row.add_child(sw)


func _sync_sliders() -> void:
	var noz := _spray.current_nozzle()
	for key in _sliders.keys():
		var slider: HSlider = _sliders[key]
		var v: float = float(noz.get(key))
		slider.set_value_no_signal(v)
		_update_slider_label(key, v, _is_int_key(key))


func _is_int_key(key: String) -> bool:
	for spec in SLIDER_SPECS:
		if spec[0] == key:
			return bool(spec[5])
	return false


func _update_slider_label(key: String, value: float, is_int: bool) -> void:
	var label: Label = _slider_labels[key]
	label.text = str(int(round(value))) if is_int else "%.2f" % value


# --- Signal handlers --------------------------------------------------------

func _on_color_changed(c: Color) -> void:
	if _spray != null:
		_spray.set_color(c)
		tool_changed.emit()


func _on_swatch_pressed(i: int) -> void:
	if _spray == null:
		return
	_spray.set_color_index(i)
	_color_btn.color = _spray.current_color()
	tool_changed.emit()


func _on_nozzle_selected(idx: int) -> void:
	if _spray == null:
		return
	_spray.nozzle_index = idx
	if _shape_opt != null:
		_shape_opt.select(int(_spray.current_nozzle().shape))
	_sync_sliders()
	tool_changed.emit()


func _on_shape_selected(idx: int) -> void:
	if _spray == null:
		return
	_spray.current_nozzle().shape = idx as Nozzle.Shape
	tool_changed.emit()


func _on_output_changed(v: float) -> void:
	if _spray != null:
		_spray.output_rate = v
	if _output_label != null:
		_output_label.text = "%.2fx" % v


func _on_clear_interval_changed(v: float) -> void:
	if _clear_interval_label != null:
		_clear_interval_label.text = "%ds" % int(v)
	clear_interval_changed.emit(v)


func _on_vignette_changed(_v: float) -> void:
	for key in _vig_sliders.keys():
		var label: Label = _vig_labels[key]
		label.text = "%.2f" % float(_vig_sliders[key].value)
	vignette_changed.emit(
		float(_vig_sliders["strength"].value),
		float(_vig_sliders["extent"].value),
		float(_vig_sliders["softness"].value),
	)


func _on_mouse_aim_changed(_v: float) -> void:
	for key in _mouse_sliders.keys():
		_update_mouse_label(key)
	_emit_mouse_aim()


func _on_mouse_aim_reset() -> void:
	for spec in MOUSE_AIM_SPECS:
		var slider: HSlider = _mouse_sliders[spec[0]]
		slider.set_value_no_signal(float(spec[5]))
		_update_mouse_label(spec[0])
	_emit_mouse_aim()


func _emit_mouse_aim() -> void:
	mouse_aim_changed.emit(
		float(_mouse_sliders["distance"].value),
		float(_mouse_sliders["pitch"].value),
		float(_mouse_sliders["yaw"].value),
		float(_mouse_sliders["roll"].value),
	)


func _update_mouse_label(key: String) -> void:
	var slider: HSlider = _mouse_sliders[key]
	var label: Label = _mouse_labels[key]
	var unit := ""
	for spec in MOUSE_AIM_SPECS:
		if spec[0] == key:
			unit = String(spec[6])
			break
	if key == "distance":
		label.text = "%.2f%s" % [slider.value, unit]
	else:
		label.text = "%d%s" % [int(round(slider.value)), unit]


func _on_reset_pressed() -> void:
	if _spray == null:
		return
	_spray.reset_current_nozzle()
	sync_from_tool()
	tool_changed.emit()


func _on_advanced_toggled(on: bool) -> void:
	_advanced = on
	_apply_advanced_visibility()
	_save_prefs()


func _on_wall_selected(idx: int) -> void:
	if idx >= 0 and idx < _wall_paths.size():
		wall_selected.emit(_wall_paths[idx])


func _on_aim_selected(idx: int) -> void:
	aim_source_selected.emit(idx)


func _on_wall_apply() -> void:
	if _phys_w == null:
		return
	wall_dimensions_changed.emit(
		Vector2(_phys_w.value, _phys_h.value),
		Vector2i(int(_res_w.value), int(_res_h.value)),
	)


## Reflect the fullscreen state in the checkbox without re-emitting (e.g. when
## toggled by the keyboard).
func set_fullscreen(on: bool) -> void:
	if _fullscreen_check != null:
		_fullscreen_check.set_pressed_no_signal(on)


## Initialize the wall-dimension controls (no signals fired).
func set_wall_dimensions(physical_size: Vector2, resolution: Vector2i) -> void:
	if _phys_w != null:
		_phys_w.set_value_no_signal(physical_size.x)
		_phys_h.set_value_no_signal(physical_size.y)
		_res_w.set_value_no_signal(resolution.x)
		_res_h.set_value_no_signal(resolution.y)


func _on_connect_pressed() -> void:
	if _server_ip_edit == null:
		return
	tracker_connect_requested.emit(
		_server_ip_edit.text,
		_client_ip_edit.text,
		_multicast_opt.selected == 0,
	)


func _on_offset_changed(_v: float) -> void:
	tracker_offset_changed.emit(Vector3(
		float(_offset_spins["x"].value),
		float(_offset_spins["y"].value),
		float(_offset_spins["z"].value),
	))


## Initialize the OptiTrack controls from persisted settings (no signals fired).
func set_tracker_settings(server_ip: String, client_ip: String, multicast: bool, pos_offset: Vector3) -> void:
	if _server_ip_edit != null:
		_server_ip_edit.text = server_ip
	if _client_ip_edit != null:
		_client_ip_edit.text = client_ip
	if _multicast_opt != null:
		_multicast_opt.select(0 if multicast else 1)
	if _offset_spins.has("x"):
		_offset_spins["x"].set_value_no_signal(pos_offset.x)
		_offset_spins["y"].set_value_no_signal(pos_offset.y)
		_offset_spins["z"].set_value_no_signal(pos_offset.z)


## Set the calibration corner-order dropdown (no signal fired).
func set_calib_order(order: int) -> void:
	if _calib_order_opt != null and order >= 0 and order < _calib_order_opt.item_count:
		_calib_order_opt.select(order)


func _on_prox_slider_changed(v: float) -> void:
	if _prox_value != null:
		_prox_value.text = "%.3f" % v
	proximity_threshold_changed.emit(v)


func _on_slider_changed(value: float, key: String, is_int: bool, value_label: Label) -> void:
	if _spray == null:
		return
	var noz := _spray.current_nozzle()
	if is_int:
		noz.set(key, int(round(value)))
	else:
		noz.set(key, value)
	value_label.text = str(int(round(value))) if is_int else "%.2f" % value


# --- Advanced view + prefs --------------------------------------------------

func _apply_advanced_visibility() -> void:
	for node in _advanced_nodes:
		if node != null:
			node.visible = _advanced


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) == OK:
		_advanced = bool(cfg.get_value("menu", "advanced", false))
		var c = cfg.get_value("menu", "collapsed", {})
		if c is Dictionary:
			_collapsed = c


func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)  # keep any other keys
	cfg.set_value("menu", "advanced", _advanced)
	cfg.set_value("menu", "collapsed", _collapsed)
	cfg.save(PREFS_PATH)


# --- Layout / sliding -------------------------------------------------------

func _reposition() -> void:
	var vp := get_viewport().get_visible_rect().size
	_panel.size = Vector2(PANEL_WIDTH, vp.y)
	_panel.position = Vector2(_shown_x() if _shown else _hidden_x(), 0.0)


func _shown_x() -> float:
	return get_viewport().get_visible_rect().size.x - PANEL_WIDTH


func _hidden_x() -> float:
	return get_viewport().get_visible_rect().size.x
