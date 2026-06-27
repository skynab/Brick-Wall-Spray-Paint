extends Resource
class_name ProjectionCalibration

## Persisted projector keystone: the four output corners in screen-UV space
## (0..1), ordered TL, TR, BR, BL. Identity corners mean "no warp".

@export var corners: PackedVector2Array = PackedVector2Array([
	Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
])
@export var calibrated: bool = false
