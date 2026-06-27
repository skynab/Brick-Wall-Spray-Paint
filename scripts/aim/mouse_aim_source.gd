extends AimSource
class_name MouseAimSource

## Aims via the camera and the current mouse position — the default device.
##
## The mouse only chooses a planar anchor on the wall. The spray "can" is then
## pulled back from that anchor along the wall normal by `distance`, and its
## spray direction is tilted by `pitch_deg` / `yaw_deg`. With distance 0 and no
## tilt this reproduces the original behaviour (spray hits straight under the
## cursor); pulling back and tilting offsets the hit, the offset growing with
## distance — like holding a real can away from the wall and angling it.

var _camera: Camera3D
var _wall: BrickWall

## How far the can sits off the wall, along its normal, in world units (metres).
var distance := 0.0
## Spray-direction tilt about the wall's right (X) and up (Y) axes, in degrees.
var pitch_deg := 0.0
var yaw_deg := 0.0


func _init(camera: Camera3D, wall: BrickWall = null) -> void:
	_camera = camera
	_wall = wall


func get_ray() -> Dictionary:
	if _camera == null or _wall == null:
		return {"valid": false}
	var m := _camera.get_viewport().get_mouse_position()
	var ray_o := _camera.project_ray_origin(m)
	var ray_d := _camera.project_ray_normal(m)
	# Mouse -> planar anchor on the wall plane.
	var anchor = _wall.ray_plane_world(ray_o, ray_d)
	if anchor == null:
		return {"valid": false}
	var normal := _wall.wall_normal()
	# Pull the can back off the wall, then tilt its forward (-normal) direction.
	var origin: Vector3 = anchor + normal * distance
	var fwd := -normal
	fwd = fwd.rotated(_wall.wall_right(), deg_to_rad(pitch_deg))
	fwd = fwd.rotated(_wall.wall_up(), deg_to_rad(yaw_deg))
	return {"origin": origin, "direction": fwd.normalized(), "valid": true}


func is_active() -> bool:
	return _camera != null and _wall != null


func get_label() -> String:
	return "Mouse"
