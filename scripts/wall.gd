extends Node3D
class_name BrickWall

## The brick wall surface. Owns the visible quad and provides the geometry
## helpers the painting system needs: world<->UV mapping and ray/plane hits.
##
## The quad lies in its local XY plane, centered at the origin, front face
## pointing toward +Z (toward the camera). UV (0,0) is the top-left of the
## wall, (1,1) the bottom-right.

## Path to the brick albedo. Loaded at runtime so the scene never depends on
## Godot's import order / generated UIDs.
const BRICK_TEXTURE_PATH := "res://assets/brick_wall.jpg"
const WALL_SHADER_PATH := "res://shaders/wall_paint.gdshader"

## Default paint-layer resolution (16:9 to match the quad). Later phases read
## this when allocating the paint Image.
@export var paint_resolution: Vector2i = Vector2i(2048, 1152)

var _mesh: MeshInstance3D
var _quad_size: Vector2 = Vector2.ONE
var _paint: PaintLayer
var _material: ShaderMaterial
## Path of the brick image currently shown (selectable at runtime).
var _brick_path: String = BRICK_TEXTURE_PATH


func _ready() -> void:
	_mesh = $Mesh
	# Drive geometry + paint resolution from the central config.
	paint_resolution = AppConfig.PAINT_RESOLUTION
	var qm := _mesh.mesh as QuadMesh
	if qm != null:
		qm.size = AppConfig.WALL_SIZE
		_quad_size = qm.size

	# Create the paint accumulation layer.
	_paint = PaintLayer.new()
	_paint.name = "PaintLayer"
	add_child(_paint)
	_paint.setup(paint_resolution)

	# Composite brick + paint via the wall shader.
	_material = ShaderMaterial.new()
	_material.shader = load(WALL_SHADER_PATH)
	_material.set_shader_parameter("paint_tex", _paint.texture)
	_mesh.material_override = _material
	set_brick_texture(_brick_path)
	set_vignette(AppConfig.VIGNETTE_STRENGTH, AppConfig.VIGNETTE_EXTENT, AppConfig.VIGNETTE_SOFTNESS)


## The paint accumulation layer for this wall.
func get_paint_layer() -> PaintLayer:
	return _paint


## Swap the brick background image at runtime. Paint is unaffected (it lives in
## a separate layer composited on top). `path` may be an imported res:// resource
## or an absolute file path (external image loaded at runtime).
func set_brick_texture(path: String) -> void:
	var tex := _load_texture(path)
	if tex == null:
		push_warning("Could not load brick texture at %s" % path)
		return
	_brick_path = path
	if _material != null:
		_material.set_shader_parameter("brick_tex", tex)


## Path of the brick image currently displayed.
func current_brick_path() -> String:
	return _brick_path


## Set the vignette that darkens the brick toward the edges (under the paint).
##   strength : peak corner darkening, 0 = off.
##   extent   : normalized radius (0 centre .. 1 corner) where the fade begins.
##   softness : width of the fade.
func set_vignette(strength: float, extent: float, softness: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("vignette_strength", strength)
	_material.set_shader_parameter("vignette_extent", extent)
	_material.set_shader_parameter("vignette_softness", maxf(0.01, softness))


func _is_resource_path(path: String) -> bool:
	return path.begins_with("res://") or path.begins_with("user://")


func _load_texture(path: String) -> Texture2D:
	if _is_resource_path(path):
		return load(path) as Texture2D
	# External file beside the .exe: not imported, so load the raw image.
	var img := Image.load_from_file(path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## The current brick image as an Image (for compositing / saving).
func _brick_image() -> Image:
	if _is_resource_path(_brick_path):
		var t := load(_brick_path) as Texture2D
		return t.get_image() if t != null else null
	return Image.load_from_file(_brick_path)


## Build a flattened image of the wall as displayed: brick photo with the paint
## composited on top, at the paint resolution. Used for "save PNG".
func composite_to_image() -> Image:
	var img := _brick_image()
	if img != null:
		img.resize(paint_resolution.x, paint_resolution.y)
		img.convert(Image.FORMAT_RGBA8)
	else:
		img = Image.create(paint_resolution.x, paint_resolution.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.1, 0.1, 0.1, 1.0))
	# alpha-over the paint buffer onto the brick.
	img.blend_rect(_paint.image, Rect2i(Vector2i.ZERO, paint_resolution), Vector2i.ZERO)
	return img


## World-space size (width, height) of the wall face, in metres.
func world_size() -> Vector2:
	return _quad_size


## Convert a UV in [0,1]x[0,1] to an integer pixel in a texture of `res`.
func uv_to_pixel(uv: Vector2, res: Vector2i) -> Vector2i:
	var px := int(round(uv.x * float(res.x - 1)))
	var py := int(round(uv.y * float(res.y - 1)))
	return Vector2i(clampi(px, 0, res.x - 1), clampi(py, 0, res.y - 1))


## Convert a world point assumed to lie on the wall plane to a wall UV.
## Returns the UV (may fall outside [0,1] if the point is off the face).
func world_to_uv(world_pos: Vector3) -> Vector2:
	var local := _mesh.global_transform.affine_inverse() * world_pos
	return _local_to_uv(local)


## Convert a wall UV in [0,1]x[0,1] to a world-space point on the wall face.
## Inverse of world_to_uv; UVs outside [0,1] map past the face edges.
func uv_to_world(uv: Vector2) -> Vector3:
	var local := Vector3((uv.x - 0.5) * _quad_size.x, (0.5 - uv.y) * _quad_size.y, 0.0)
	return _mesh.global_transform * local


## Intersect a world-space ray (origin + direction) with the wall plane.
## Returns the hit UV if it lands on the face, or null on a miss / parallel ray.
func ray_plane_uv(origin: Vector3, direction: Vector3) -> Variant:
	var inv := _mesh.global_transform.affine_inverse()
	var lo := inv * origin
	var ld := inv.basis * direction
	if absf(ld.z) < 0.00000001:
		return null
	var t := -lo.z / ld.z
	if t < 0.0:
		return null
	var hit := lo + ld * t
	var uv := _local_to_uv(hit)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return null
	return uv


func _local_to_uv(local: Vector3) -> Vector2:
	var u := local.x / _quad_size.x + 0.5
	var v := 0.5 - local.y / _quad_size.y
	return Vector2(u, v)
