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


func _ready() -> void:
	_mesh = $Mesh
	var qm := _mesh.mesh as QuadMesh
	if qm != null:
		_quad_size = qm.size

	# Create the paint accumulation layer.
	_paint = PaintLayer.new()
	_paint.name = "PaintLayer"
	add_child(_paint)
	_paint.setup(paint_resolution)

	# Composite brick + paint via the wall shader.
	var brick_tex := load(BRICK_TEXTURE_PATH)
	if brick_tex == null:
		push_warning("Brick texture not found at %s — open the project in the editor once so it imports." % BRICK_TEXTURE_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = load(WALL_SHADER_PATH)
	mat.set_shader_parameter("brick_tex", brick_tex)
	mat.set_shader_parameter("paint_tex", _paint.texture)
	_mesh.material_override = mat


## The paint accumulation layer for this wall.
func get_paint_layer() -> PaintLayer:
	return _paint


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
