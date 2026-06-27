extends RefCounted
class_name SprayTool

## Holds the active nozzle and color, and turns a single aim point into a burst
## of scattered droplets stamped into the paint layer.

const NOZZLE_PATHS := [
	"res://nozzles/fine_cap.tres",
	"res://nozzles/wide_cap.tres",
	"res://nozzles/ny_thin.tres",
	"res://nozzles/calligraphy.tres",
	"res://nozzles/stencil_cap.tres",
	"res://nozzles/splatter.tres",
]

var nozzles: Array[Nozzle] = []
## Disk path each loaded nozzle came from, parallel to `nozzles` (for reset).
var nozzle_paths: Array[String] = []
var nozzle_index: int = 0

var palette: Array[Color] = [
	Color("ff2d2d"), # red
	Color("ff8c1a"), # orange
	Color("ffe11a"), # yellow
	Color("39d353"), # green
	Color("3da5ff"), # blue
	Color("ffffff"), # white
	Color("000000"), # black
]
var color_index: int = 0
## The active paint color. Tracks the palette on index changes, but can also be
## set to an arbitrary color from the menu's color picker.
var active_color: Color = Color.WHITE

## Master spray-rate multiplier ("how fast the paint comes out"), applied on top
## of the active nozzle's flow. 1.0 = the nozzle's native rate. Global so it
## persists across nozzle changes, like turning the can's pressure up or down.
var output_rate: float = 1.0

## Extra footprint rotation (degrees) from the aim source's roll, added to each
## nozzle's own `angle` so shaped caps (e.g. NY Thin) can be spun while spraying.
var extra_roll_deg: float = 0.0

## When true, lingering over one spot too long seeds running drips. Off disables
## drips entirely.
var drips_enabled: bool = true

# Dwell tracking for heavy-buildup drips.
var _last_center: Vector2 = Vector2.ZERO
var _dwell: int = 0


func _init() -> void:
	for p in NOZZLE_PATHS:
		var n = load(p)
		if n is Nozzle:
			nozzles.append(n)
			nozzle_paths.append(p)
	if nozzles.is_empty():
		nozzles.append(Nozzle.new()) # safety fallback
		nozzle_paths.append("")
	active_color = palette[color_index]


func current_nozzle() -> Nozzle:
	return nozzles[nozzle_index]


func current_color() -> Color:
	return active_color


func cycle_nozzle() -> void:
	nozzle_index = (nozzle_index + 1) % nozzles.size()


func cycle_color() -> void:
	color_index = (color_index + 1) % palette.size()
	active_color = palette[color_index]


func set_color_index(i: int) -> void:
	if i >= 0 and i < palette.size():
		color_index = i
		active_color = palette[i]


## Set an arbitrary active color (from the color picker).
func set_color(c: Color) -> void:
	active_color = c


## Reload the active nozzle from disk, discarding any live slider edits made to
## the cached resource. Returns the fresh nozzle (or the current one on failure).
func reset_current_nozzle() -> Nozzle:
	var path := nozzle_paths[nozzle_index] if nozzle_index < nozzle_paths.size() else ""
	if path != "":
		var fresh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if fresh is Nozzle:
			nozzles[nozzle_index] = fresh
	return nozzles[nozzle_index]


## Emit one frame's worth of droplets around `center_uv` into the paint layer.
func spray(paint_layer: PaintLayer, center_uv: Vector2) -> void:
	var res := paint_layer.get_resolution()
	var noz := current_nozzle()
	var col := current_color()
	var center := Vector2(center_uv.x * float(res.x - 1), center_uv.y * float(res.y - 1))
	var spread := noz.radius_px * lerpf(0.15, 1.0, clampf(noz.scatter, 0.0, 1.0))
	var rot := deg_to_rad(noz.angle + extra_roll_deg)
	var flow := maxi(1, int(round(noz.flow * output_rate)))

	for i in flow:
		# Shape the footprint in unit space, scale to the cone, then orient it.
		var s := _sample_offset(noz.shape, maxf(noz.aspect, 1.0))
		var off: Vector2 = s.pos
		var norm: float = s.norm
		var size: float = s.size
		var p := center + (off * spread).rotated(rot)
		var uv := Vector2(p.x / float(res.x - 1), p.y / float(res.y - 1))
		# Feather the cone: droplets near the rim deposit less paint.
		var edge: float = 1.0 - smoothstep(AppConfig.SPRAY_EDGE_START, 1.0, norm)
		paint_layer.stamp(uv, col, noz.droplet_size_px * size, noz.build_rate * edge, noz.softness)

	# Drips only build up from dwelling too long over one spot (see below).
	if drips_enabled:
		_update_dwell_drips(paint_layer, center, center_uv, col, noz)
	else:
		_dwell = 0


## Pick one droplet's position within a nozzle's footprint, in unit space
## (roughly -1..1, before the cone radius and rotation are applied). Returns:
##   pos  : Vector2 offset in unit footprint space.
##   norm : 0 (core) .. 1 (rim), used for edge feathering.
##   size : per-droplet droplet-size multiplier.
func _sample_offset(shape: int, aspect: float) -> Dictionary:
	match shape:
		Nozzle.Shape.OVAL:
			# Disc stretched along local X — fat/thin fan caps.
			var ang := randf() * TAU
			var r := sqrt(randf())
			return {"pos": Vector2(cos(ang) * r * aspect, sin(ang) * r), "norm": r, "size": 1.0}
		Nozzle.Shape.LINE:
			# Long thin calligraphy stroke; ends feather, sides stay crisp.
			var t := randf() * 2.0 - 1.0
			var perp := (randf() * 2.0 - 1.0) * 0.12
			return {"pos": Vector2(t * aspect, perp), "norm": absf(t), "size": 1.0}
		Nozzle.Shape.SQUARE:
			# Uniform rectangular footprint (stencil / hard cap edge).
			var x := (randf() * 2.0 - 1.0) * aspect
			var y := randf() * 2.0 - 1.0
			return {"pos": Vector2(x, y), "norm": maxf(absf(x) / aspect, absf(y)), "size": 1.0}
		Nozzle.Shape.SPLATTER:
			# Sparse specks with strong size variation.
			var ang := randf() * TAU
			var r := sqrt(randf())
			return {"pos": Vector2(cos(ang), sin(ang)) * r, "norm": r, "size": randf_range(0.4, 1.7)}
		_:
			# ROUND: even disc (uniform area).
			var ang := randf() * TAU
			var r := sqrt(randf())
			return {"pos": Vector2(cos(ang), sin(ang)) * r, "norm": r, "size": 1.0}


## Seed a drip when the spray lingers over one spot (heavy build-up). The drip
## starts at a random point inside the footprint so wide/line shapes drip across
## their whole width, not just from the centre.
func _update_dwell_drips(paint_layer: PaintLayer, center: Vector2, _center_uv: Vector2, col: Color, noz: Nozzle) -> void:
	if center.distance_to(_last_center) < noz.radius_px * 0.5:
		_dwell += 1
	else:
		_dwell = 0
	_last_center = center
	if _dwell >= AppConfig.DRIP_DWELL_FRAMES and randf() < AppConfig.DRIP_DWELL_SEED_CHANCE:
		var res := paint_layer.get_resolution()
		var spread := noz.radius_px * lerpf(0.15, 1.0, clampf(noz.scatter, 0.0, 1.0))
		var s := _sample_offset(noz.shape, maxf(noz.aspect, 1.0))
		var off: Vector2 = s.pos
		var sp := center + (off * spread).rotated(deg_to_rad(noz.angle))
		var seed_uv := Vector2(sp.x / float(res.x - 1), sp.y / float(res.y - 1))
		paint_layer.seed_drip(seed_uv, col, AppConfig.DRIP_WIDTH, randf_range(AppConfig.DRIP_MIN_LEN, AppConfig.DRIP_MAX_LEN))
		_dwell = int(_dwell * 0.5)


## Closed-loop outline of the current nozzle's footprint, in wall-UV space, for
## the aim cursor. Mirrors the geometry that spray()/_sample_offset produces.
func footprint_outline_uv(center_uv: Vector2, res: Vector2i) -> PackedVector2Array:
	var noz := current_nozzle()
	var spread := noz.radius_px * lerpf(0.15, 1.0, clampf(noz.scatter, 0.0, 1.0))
	var rot := deg_to_rad(noz.angle + extra_roll_deg)
	var aspect := maxf(noz.aspect, 1.0)
	var center := Vector2(center_uv.x * float(res.x - 1), center_uv.y * float(res.y - 1))
	var out := PackedVector2Array()
	for u in _outline_unit(noz.shape, aspect):
		var p := center + (u * spread).rotated(rot)
		out.append(Vector2(p.x / float(res.x - 1), p.y / float(res.y - 1)))
	return out


## Unit-space outline points (closed loop) for a footprint shape.
func _outline_unit(shape: int, aspect: float) -> PackedVector2Array:
	match shape:
		Nozzle.Shape.OVAL:
			return _ellipse_loop(aspect, 1.0)
		Nozzle.Shape.LINE:
			return _rect_loop(aspect, 0.12)
		Nozzle.Shape.SQUARE:
			return _rect_loop(aspect, 1.0)
		_:
			# ROUND / SPLATTER: a circle bounding the spray cone.
			return _ellipse_loop(1.0, 1.0)


func _ellipse_loop(rx: float, ry: float, segments: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):  # +1 closes the loop
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _rect_loop(hx: float, hy: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy), Vector2(-hx, -hy),
	])
