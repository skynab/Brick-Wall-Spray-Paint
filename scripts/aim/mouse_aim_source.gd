extends AimSource
class_name MouseAimSource

## Aims via the camera and the current mouse position — the default device.

var _camera: Camera3D


func _init(camera: Camera3D) -> void:
	_camera = camera


func get_ray() -> Dictionary:
	if _camera == null:
		return {"valid": false}
	var m := _camera.get_viewport().get_mouse_position()
	return {
		"origin": _camera.project_ray_origin(m),
		"direction": _camera.project_ray_normal(m),
		"valid": true,
	}


func is_active() -> bool:
	return _camera != null


func get_label() -> String:
	return "Mouse"
