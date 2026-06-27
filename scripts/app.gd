extends Node3D

## Top-level wiring for the Brick Wall Spray Paint app.
## Phase 4: spray tool + collapsible side menu, kept two-way in sync with the
## keyboard. Nozzle/color switching, clear, multi-step undo, save-to-PNG.

const MAX_UNDO := 20

@onready var _wall := $Wall as BrickWall
@onready var _camera: Camera3D = $Camera3D
@onready var _menu := $SideMenu as SideMenu
@onready var _hud := $Hud as Hud

var _paint: PaintLayer
var _spray: SprayTool
var _undo_stack: Array[Image] = []
var _stroke_active := false

var _aim_sources: Array[AimSource] = []
var _aim_index := 0


func _ready() -> void:
	print("App ready")
	_spray = SprayTool.new()
	if _wall != null:
		_paint = _wall.get_paint_layer()
	_build_aim_sources()
	if _menu != null:
		_menu.setup(_spray)
		_menu.clear_requested.connect(_on_menu_clear)
		_menu.undo_requested.connect(_undo)
		_menu.save_requested.connect(_save_png)
		_menu.tool_changed.connect(_report_state)
		_menu.aim_source_selected.connect(_set_aim)
		_menu.set_aim_sources(_aim_labels(), _aim_index)
	_update_aim_status()
	_report_state()


func _build_aim_sources() -> void:
	_aim_sources.clear()
	_aim_sources.append(MouseAimSource.new(_camera))
	# Phase 7: _aim_sources.append(TrackerAimSource.new(<canister node>))


func _aim_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for src in _aim_sources:
		labels.append(src.get_label())
	return labels


func _active_aim() -> AimSource:
	if _aim_index < 0 or _aim_index >= _aim_sources.size():
		return null
	return _aim_sources[_aim_index]


func _process(_delta: float) -> void:
	_handle_actions()
	_handle_spray()


# --- Spraying ---------------------------------------------------------------

func _handle_spray() -> void:
	if _paint == null:
		return
	if Input.is_action_pressed("spray"):
		# Don't paint while the pointer is interacting with the menu.
		if _menu != null and _menu.is_pointing_at_menu():
			_stroke_active = false
			return
		var uv = _aim_uv()
		if uv == null:
			return
		if not _stroke_active:
			# Snapshot once at the start of a stroke so undo reverts the whole stroke.
			_push_undo()
			_stroke_active = true
		_spray.spray(_paint, uv)
	else:
		_stroke_active = false


func _aim_uv() -> Variant:
	if _wall == null:
		return null
	var src := _active_aim()
	if src == null:
		return null
	var ray := src.get_ray()
	if not ray.get("valid", false):
		return null
	return _wall.ray_plane_uv(ray["origin"], ray["direction"])


# --- Actions ----------------------------------------------------------------

func _handle_actions() -> void:
	if Input.is_action_just_pressed("cycle_nozzle"):
		_spray.cycle_nozzle()
		_sync_menu()
		_report_state()
	if Input.is_action_just_pressed("cycle_color"):
		_spray.cycle_color()
		_sync_menu()
		_report_state()
	for i in 6:
		if Input.is_action_just_pressed("palette_%d" % (i + 1)):
			_spray.set_color_index(i)
			_sync_menu()
			_report_state()
	if Input.is_action_just_pressed("toggle_menu"):
		if _menu != null:
			_menu.toggle()
	if Input.is_action_just_pressed("toggle_hud"):
		if _hud != null:
			_hud.toggle()
	if Input.is_action_just_pressed("cycle_aim"):
		if _aim_sources.size() > 1:
			_set_aim((_aim_index + 1) % _aim_sources.size())
	if Input.is_action_just_pressed("clear_wall"):
		_on_menu_clear()
	if Input.is_action_just_pressed("undo"):
		_undo()
	if Input.is_action_just_pressed("save_png"):
		_save_png()
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()


func _on_menu_clear() -> void:
	_push_undo()
	_paint.clear()
	print("Wall cleared")


func _sync_menu() -> void:
	if _menu != null:
		_menu.sync_from_tool()


func _set_aim(idx: int) -> void:
	if idx < 0 or idx >= _aim_sources.size():
		return
	_aim_index = idx
	if _menu != null:
		_menu.select_aim(idx)
	_update_aim_status()


func _update_aim_status() -> void:
	if _menu == null:
		return
	var src := _active_aim()
	if src == null:
		_menu.set_status("Aim: —")
		return
	_menu.set_status("Aim: %s (%s)" % [src.get_label(), "active" if src.is_active() else "inactive"])


func _push_undo() -> void:
	if _paint == null:
		return
	_undo_stack.append(_paint.snapshot())
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()


func _undo() -> void:
	if _undo_stack.is_empty():
		print("Nothing to undo")
		return
	_paint.restore(_undo_stack.pop_back())
	print("Undo")


func _save_png() -> void:
	if _wall == null:
		return
	var img := _wall.composite_to_image()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://brickwall_%s.png" % stamp
	if img.save_png(path) == OK:
		print("Saved -> %s" % ProjectSettings.globalize_path(path))
	else:
		push_warning("Save failed")


func _report_state() -> void:
	if _spray == null:
		return
	if _hud != null:
		_hud.set_state(_spray.current_nozzle().nozzle_name, _spray.current_color())
	print("Nozzle: %s | Color %d (#%s)" % [
		_spray.current_nozzle().nozzle_name,
		_spray.color_index + 1,
		_spray.current_color().to_html(false),
	])
