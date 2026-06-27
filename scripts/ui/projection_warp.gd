extends CanvasLayer
class_name ProjectionWarp

## Optional projector keystone. Warps the rendered frame through a projective
## transform defined by four draggable corners, so the image lands square on a
## physical wall the projector hits at an angle.
##
## Off by default (zero cost): the layer is hidden unless a non-identity
## calibration is loaded or the user is actively calibrating (toggle with [P]).
## Drawn under the menus (layer 0) so the UI stays unwarped.

const SHADER_PATH := "res://shaders/keystone.gdshader"
const HANDLE_PX := 18.0
const PICK_RADIUS := 30.0

var corners: PackedVector2Array          # screen UV (0..1), order TL, TR, BR, BL
var _calibrating := false
var _drag_index := -1

var _bbc: BackBufferCopy
var _warped: ColorRect
var _mat: ShaderMaterial
var _handles_root: Control
var _handle_rects: Array[ColorRect] = []


func _ready() -> void:
	layer = 0
	corners = _identity_corners()
	_build()
	_load()
	_apply()
	_refresh_active()
	get_viewport().size_changed.connect(_reposition_handles)
	_reposition_handles()


func is_calibrating() -> bool:
	return _calibrating


func toggle_calibration() -> void:
	_calibrating = not _calibrating
	if not _calibrating:
		_save()
	_refresh_active()
	_reposition_handles()


# --- Build ------------------------------------------------------------------

func _build() -> void:
	_bbc = BackBufferCopy.new()
	_bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_bbc)

	_warped = ColorRect.new()
	_warped.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warped.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_warped.material = _mat
	add_child(_warped)

	_handles_root = Control.new()
	_handles_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_handles_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_handles_root)
	for i in 4:
		var h := ColorRect.new()
		h.color = Color(1.0, 0.8, 0.1)
		h.size = Vector2(HANDLE_PX, HANDLE_PX)
		_handle_rects.append(h)
		_handles_root.add_child(h)


# --- Calibration input ------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _calibrating:
		return
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_index = _nearest_corner(event.position, vp)
		else:
			_drag_index = -1
		if _drag_index != -1:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_index != -1:
		corners[_drag_index] = (event.position / vp).clamp(Vector2.ZERO, Vector2.ONE)
		_apply()
		_reposition_handles()
		get_viewport().set_input_as_handled()


func _nearest_corner(pos: Vector2, vp: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS
	for i in corners.size():
		var d := (corners[i] * vp).distance_to(pos)
		if d <= best_d:
			best_d = d
			best = i
	return best


# --- Homography -------------------------------------------------------------

func _apply() -> void:
	_mat.set_shader_parameter("inv_homography", _inverse_homography())


## Inverse of the square->quad homography (i.e. screen -> source UV), as a Basis
## (passed to the shader's mat3 uniform).
func _inverse_homography() -> Basis:
	var x0 := corners[0].x; var y0 := corners[0].y
	var x1 := corners[1].x; var y1 := corners[1].y
	var x2 := corners[2].x; var y2 := corners[2].y
	var x3 := corners[3].x; var y3 := corners[3].y
	var dx1 := x1 - x2; var dx2 := x3 - x2; var dx3 := x0 - x1 + x2 - x3
	var dy1 := y1 - y2; var dy2 := y3 - y2; var dy3 := y0 - y1 + y2 - y3

	var a: float; var b: float; var c: float
	var d: float; var e: float; var f: float
	var g: float; var h: float
	if absf(dx3) < 0.000000001 and absf(dy3) < 0.000000001:
		a = x1 - x0; b = x2 - x1; c = x0
		d = y1 - y0; e = y2 - y1; f = y0
		g = 0.0; h = 0.0
	else:
		var den := dx1 * dy2 - dx2 * dy1
		if absf(den) < 0.000000001:
			return Basis() # degenerate -> identity
		g = (dx3 * dy2 - dx2 * dy3) / den
		h = (dx1 * dy3 - dx3 * dy1) / den
		a = x1 - x0 + g * x1; b = x3 - x0 + h * x3; c = x0
		d = y1 - y0 + g * y1; e = y3 - y0 + h * y3; f = y0

	# Math matrix [a b c; d e f; g h 1] as a Basis (columns), then invert.
	var hb := Basis(Vector3(a, d, g), Vector3(b, e, h), Vector3(c, f, 1.0))
	return hb.inverse()


# --- Activation / handles ---------------------------------------------------

func _refresh_active() -> void:
	visible = _calibrating or _is_calibrated()
	_handles_root.visible = _calibrating


func _reposition_handles() -> void:
	var vp := get_viewport().get_visible_rect().size
	for i in _handle_rects.size():
		_handle_rects[i].position = corners[i] * vp - Vector2(HANDLE_PX, HANDLE_PX) * 0.5


func _is_calibrated() -> bool:
	var ident := _identity_corners()
	for i in corners.size():
		if not corners[i].is_equal_approx(ident[i]):
			return true
	return false


func _identity_corners() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])


# --- Persistence ------------------------------------------------------------

func _load() -> void:
	var path := AppConfig.PROJECTION_CALIBRATION_PATH
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is ProjectionCalibration and res.corners.size() == 4:
			corners = res.corners.duplicate()


func _save() -> void:
	var res := ProjectionCalibration.new()
	res.corners = corners.duplicate()
	res.calibrated = _is_calibrated()
	var err := ResourceSaver.save(res, AppConfig.PROJECTION_CALIBRATION_PATH)
	if err != OK:
		push_warning("Failed to save projection calibration (%d)" % err)
