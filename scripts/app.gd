extends Node3D

## Top-level wiring for the Brick Wall Spray Paint app.
## Phase 4: spray tool + collapsible side menu, kept two-way in sync with the
## keyboard. Nozzle/color switching, clear, multi-step undo, save-to-PNG.

const MAX_UNDO := 20

@onready var _wall := $Wall as BrickWall
@onready var _camera: Camera3D = $Camera3D
@onready var _menu := $SideMenu as SideMenu

var _paint: PaintLayer
var _spray: SprayTool
var _undo_stack: Array[Image] = []
var _stroke_active := false


func _ready() -> void:
	print("App ready")
	_spray = SprayTool.new()
	if _wall != null:
		_paint = _wall.get_paint_layer()
	if _menu != null:
		_menu.setup(_spray)
		_menu.clear_requested.connect(_on_menu_clear)
		_menu.undo_requested.connect(_undo)
		_menu.save_requested.connect(_save_png)
	_report_state()


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
	if _wall == null or _camera == null:
		return null
	var m := get_viewport().get_mouse_position()
	return _wall.ray_plane_uv(_camera.project_ray_origin(m), _camera.project_ray_normal(m))


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
	print("Nozzle: %s | Color %d (#%s)" % [
		_spray.current_nozzle().nozzle_name,
		_spray.color_index + 1,
		_spray.current_color().to_html(false),
	])
