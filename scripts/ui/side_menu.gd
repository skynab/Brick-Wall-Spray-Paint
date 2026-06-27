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
## Emitted when the user picks a different aim source.
signal aim_source_selected(index: int)
## Tracker controls.
signal aim_asset_id_changed(id: int)
signal calibrate_requested
signal proximity_toggled(enabled: bool)
signal proximity_threshold_changed(value: float)

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
	["drip_chance", "Drip", 0.0, 1.0, 0.01, false, true],
	["aspect", "Aspect", 1.0, 8.0, 0.1, false, true],
	["angle", "Angle", -180.0, 180.0, 1.0, true, true],
]

var _spray: SprayTool

var _panel: PanelContainer
var _color_btn: ColorPickerButton
var _nozzle_opt: OptionButton
var _shape_opt: OptionButton
var _aim_opt: OptionButton
var _prox_value: Label
var _status: Label
var _sliders: Dictionary = {}       # key -> HSlider
var _slider_labels: Dictionary = {} # key -> Label

## Nodes revealed only in the Advanced view.
var _advanced_nodes: Array[Control] = []
var _advanced := false
var _advanced_check: CheckButton

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
	_sync_sliders()


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

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

	# Color section (Simple)
	vbox.add_child(_make_label("Color"))
	_color_btn = ColorPickerButton.new()
	_color_btn.custom_minimum_size = Vector2(0, 32)
	_color_btn.color_changed.connect(_on_color_changed)
	vbox.add_child(_color_btn)
	vbox.add_child(_make_palette_row())

	vbox.add_child(HSeparator.new())

	# Nozzle section (Simple): preset + shape + radius.
	vbox.add_child(_make_label("Nozzle"))
	_nozzle_opt = OptionButton.new()
	_nozzle_opt.item_selected.connect(_on_nozzle_selected)
	vbox.add_child(_nozzle_opt)

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
	vbox.add_child(shape_row)

	for spec in SLIDER_SPECS:
		var row := _make_slider_row(spec)
		vbox.add_child(row)
		if bool(spec[6]):
			_advanced_nodes.append(row)

	# Reset (Advanced): undo live slider edits.
	var reset_btn := _make_action_button("Reset nozzle", _on_reset_pressed)
	vbox.add_child(reset_btn)
	_advanced_nodes.append(reset_btn)

	# Aim source + tracker section (Advanced).
	var tracker_box := _build_tracker_section()
	vbox.add_child(tracker_box)
	_advanced_nodes.append(tracker_box)

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

	var hint := _make_label("[M] hide  [Tab] nozzle  [C]/1-6 color")
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(hint)


## Build the aim-source / OptiTrack block as one collapsible container.
func _build_tracker_section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	box.add_child(HSeparator.new())
	box.add_child(_make_label("Aim source"))
	_aim_opt = OptionButton.new()
	_aim_opt.item_selected.connect(_on_aim_selected)
	box.add_child(_aim_opt)

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
	box.add_child(id_row)

	var calib_btn := Button.new()
	calib_btn.text = "Calibrate wall (3 corners)"
	calib_btn.pressed.connect(func(): calibrate_requested.emit())
	box.add_child(calib_btn)

	var prox_check := CheckBox.new()
	prox_check.text = "Auto-spray near wall"
	prox_check.toggled.connect(func(on): proximity_toggled.emit(on))
	box.add_child(prox_check)

	var prox_box := VBoxContainer.new()
	var prox_header := HBoxContainer.new()
	var prox_name := Label.new()
	prox_name.text = "Proximity"
	prox_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prox_value = Label.new()
	_prox_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prox_value.text = "%.3f" % 0.05
	prox_header.add_child(prox_name)
	prox_header.add_child(_prox_value)
	prox_box.add_child(prox_header)
	var prox_slider := HSlider.new()
	prox_slider.min_value = 0.01
	prox_slider.max_value = 0.5
	prox_slider.step = 0.005
	prox_slider.value = 0.05
	prox_slider.value_changed.connect(_on_prox_slider_changed)
	prox_box.add_child(prox_slider)
	box.add_child(prox_box)

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
	_spray.current_nozzle().shape = idx
	tool_changed.emit()


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


func _on_aim_selected(idx: int) -> void:
	aim_source_selected.emit(idx)


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


func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)  # keep any other keys
	cfg.set_value("menu", "advanced", _advanced)
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
