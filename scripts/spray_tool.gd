extends RefCounted
class_name SprayTool

## Holds the active nozzle and color, and turns a single aim point into a burst
## of scattered droplets stamped into the paint layer.

const NOZZLE_PATHS := [
	"res://nozzles/fine_cap.tres",
	"res://nozzles/wide_cap.tres",
	"res://nozzles/splatter.tres",
]

var nozzles: Array[Nozzle] = []
var nozzle_index: int = 0

var palette: Array[Color] = [
	Color("ff2d2d"), # red
	Color("ff8c1a"), # orange
	Color("ffe11a"), # yellow
	Color("39d353"), # green
	Color("3da5ff"), # blue
	Color("ffffff"), # white
]
var color_index: int = 0


func _init() -> void:
	for p in NOZZLE_PATHS:
		var n = load(p)
		if n is Nozzle:
			nozzles.append(n)
	if nozzles.is_empty():
		nozzles.append(Nozzle.new()) # safety fallback


func current_nozzle() -> Nozzle:
	return nozzles[nozzle_index]


func current_color() -> Color:
	return palette[color_index]


func cycle_nozzle() -> void:
	nozzle_index = (nozzle_index + 1) % nozzles.size()


func cycle_color() -> void:
	color_index = (color_index + 1) % palette.size()


func set_color_index(i: int) -> void:
	if i >= 0 and i < palette.size():
		color_index = i


## Emit one frame's worth of droplets around `center_uv` into the paint layer.
func spray(paint_layer: PaintLayer, center_uv: Vector2) -> void:
	var res := paint_layer.get_resolution()
	var noz := current_nozzle()
	var col := current_color()
	var center := Vector2(center_uv.x * float(res.x - 1), center_uv.y * float(res.y - 1))
	var spread := noz.radius_px * lerpf(0.15, 1.0, clampf(noz.scatter, 0.0, 1.0))

	for i in noz.flow:
		var ang := randf() * TAU
		var rad := sqrt(randf()) * spread # sqrt -> uniform area distribution
		var p := center + Vector2(cos(ang), sin(ang)) * rad
		var uv := Vector2(p.x / float(res.x - 1), p.y / float(res.y - 1))
		paint_layer.stamp(uv, col, noz.droplet_size_px, noz.build_rate, noz.softness)
