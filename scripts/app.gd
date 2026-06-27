extends Node3D

## Top-level wiring for the Brick Wall Spray Paint app.
## Phase 2: temporary test driver — hold the spray action and a red dab follows
## the mouse on the wall. Replaced by the real spray tool in Phase 3.

@onready var _wall := $Wall as BrickWall
@onready var _camera: Camera3D = $Camera3D

var _paint: PaintLayer


func _ready() -> void:
	print("App ready")
	if _wall != null:
		_paint = _wall.get_paint_layer()


func _process(_delta: float) -> void:
	if Input.is_action_pressed("spray"):
		_spray_test()


func _spray_test() -> void:
	if _paint == null or _wall == null or _camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var uv = _wall.ray_plane_uv(origin, dir)
	if uv == null:
		return
	# Fixed test dab; real spray semantics arrive in Phase 3.
	_paint.stamp(uv, Color(0.85, 0.1, 0.1), 24.0, 0.5, 0.6)
