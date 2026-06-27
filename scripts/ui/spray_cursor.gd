extends CanvasLayer
class_name SprayCursor

## A faint on-screen outline of the active nozzle's footprint at the aim point,
## so the user can see where (and at what size / shape / rotation) the next burst
## will land — essential when projecting onto a wall with no OS mouse cursor.
##
## The app feeds it a screen-space outline each frame (already projected from the
## wall through the camera); this node just draws it. Toggle with set_enabled().

var enabled := true

var _draw_layer: _Outline


## Inner Control that performs the actual drawing.
class _Outline extends Control:
	var points: PackedVector2Array = PackedVector2Array()
	var line_color: Color = Color(1, 1, 1, 0.6)

	func _draw() -> void:
		if points.size() >= 2:
			# `points` is a closed loop (last == first), drawn as a thin polyline.
			draw_polyline(points, line_color, 1.5, true)


func _ready() -> void:
	_draw_layer = _Outline.new()
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_draw_layer)


## Show a footprint outline. `points` must be a closed loop in screen space.
func set_outline(points: PackedVector2Array, color: Color) -> void:
	if not enabled:
		clear()
		return
	_draw_layer.points = points
	_draw_layer.line_color = color
	_draw_layer.queue_redraw()


## Hide the outline (e.g. when the aim is off the wall).
func clear() -> void:
	if _draw_layer.points.is_empty():
		return
	_draw_layer.points = PackedVector2Array()
	_draw_layer.queue_redraw()


func set_enabled(on: bool) -> void:
	enabled = on
	if not enabled:
		clear()


func toggle() -> void:
	set_enabled(not enabled)
