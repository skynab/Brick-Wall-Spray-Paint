extends Resource
class_name TrackerCalibration

## Persisted 3-point calibration. The corners are canister (rigid-body) positions
## in tracker/Motive world space, captured while the canister touches the
## physical wall's TOP-LEFT, TOP-RIGHT and BOTTOM-LEFT corners. From these three
## points the tracker space is mapped onto the virtual wall's UV space.

@export var corners: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
@export var calibrated: bool = false
