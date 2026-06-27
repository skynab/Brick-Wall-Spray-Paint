extends Node
class_name PaintLayer

## Owns the paint accumulation buffer: an RGBA8 Image plus the ImageTexture that
## the wall shader samples. Brush dabs are blended into the Image (alpha-over,
## accumulating), and the texture is pushed to the GPU at most once per frame.

var image: Image
var texture: ImageTexture

var _resolution: Vector2i = Vector2i(2048, 1152)
var _dirty: bool = false
var _drips: Array[Dictionary] = []


func setup(resolution: Vector2i) -> void:
	_resolution = resolution
	image = Image.create(_resolution.x, _resolution.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	texture = ImageTexture.create_from_image(image)


func _process(_delta: float) -> void:
	if not _drips.is_empty():
		_update_drips()
	if _dirty:
		texture.update(image)
		_dirty = false


func get_resolution() -> Vector2i:
	return _resolution


## Blend a single soft circular dab into the buffer.
##   center_uv : hit point in [0,1] wall UV space.
##   color     : paint color (alpha ignored; opacity controls strength).
##   radius_px : dab radius in pixels.
##   opacity   : peak alpha added at the dab core (0..1).
##   softness  : 0 = hard disc, 1 = fully feathered gradient.
func stamp(center_uv: Vector2, color: Color, radius_px: float, opacity: float, softness: float) -> void:
	var c := Vector2(center_uv.x * float(_resolution.x - 1), center_uv.y * float(_resolution.y - 1))
	var r := maxf(1.0, radius_px)
	var inner := r * (1.0 - clampf(softness, 0.0, 1.0))

	var min_x := clampi(int(floor(c.x - r)), 0, _resolution.x - 1)
	var max_x := clampi(int(ceil(c.x + r)), 0, _resolution.x - 1)
	var min_y := clampi(int(floor(c.y - r)), 0, _resolution.y - 1)
	var max_y := clampi(int(ceil(c.y + r)), 0, _resolution.y - 1)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d := Vector2(float(x), float(y)).distance_to(c)
			if d > r:
				continue
			var falloff := 1.0
			if d > inner:
				falloff = 1.0 - smoothstep(inner, r, d)
			var a := falloff * opacity
			if a <= 0.0:
				continue
			_blend_pixel(x, y, color, a)

	_dirty = true


func clear() -> void:
	image.fill(Color(0, 0, 0, 0))
	_drips.clear()
	_dirty = true


## Start a drip running downward from `start_uv`. Cheap: one small dab per drip
## per frame; the trail persists in the accumulation buffer.
func seed_drip(start_uv: Vector2, color: Color, width: float, max_len: float) -> void:
	if _drips.size() >= AppConfig.MAX_ACTIVE_DRIPS:
		return
	_drips.append({
		"pos": Vector2(start_uv.x * float(_resolution.x - 1), start_uv.y * float(_resolution.y - 1)),
		"color": color,
		"width": width,
		"traveled": 0.0,
		"max_len": max_len,
	})


func _update_drips() -> void:
	var i := 0
	while i < _drips.size():
		var d: Dictionary = _drips[i]
		var pos: Vector2 = d.pos
		pos.y += AppConfig.DRIP_SPEED
		d.pos = pos
		var traveled: float = float(d.traveled) + AppConfig.DRIP_SPEED
		d.traveled = traveled
		var t: float = traveled / float(d.max_len)
		if t >= 1.0 or pos.y >= float(_resolution.y - 1):
			_drips.remove_at(i)
			continue
		var uv := Vector2(pos.x / float(_resolution.x - 1), pos.y / float(_resolution.y - 1))
		stamp(uv, d.color, float(d.width), (1.0 - t) * 0.5, 0.7)
		i += 1


## Return an independent copy of the current buffer (for undo).
func snapshot() -> Image:
	return image.duplicate()


## Restore a buffer previously returned by snapshot().
func restore(snap: Image) -> void:
	if snap == null:
		return
	image.copy_from(snap)
	_dirty = true


func save_png(path: String) -> Error:
	return image.save_png(path)


func _blend_pixel(x: int, y: int, color: Color, a: float) -> void:
	var src := image.get_pixel(x, y)
	var out_a := a + src.a * (1.0 - a)
	if out_a <= 0.0:
		return
	var inv := 1.0 / out_a
	var sw := src.a * (1.0 - a)
	var r := (color.r * a + src.r * sw) * inv
	var g := (color.g * a + src.g * sw) * inv
	var b := (color.b * a + src.b * sw) * inv
	image.set_pixel(x, y, Color(r, g, b, out_a))
