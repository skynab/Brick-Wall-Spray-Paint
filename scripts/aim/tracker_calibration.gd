extends Resource
class_name TrackerCalibration

## Persisted 3-point calibration. The corners are canister (rigid-body) positions
## in tracker/Motive world space, captured while the canister touches three
## adjacent physical-wall corners. `corner_order` records which three corners (and
## in what order) were sampled — see TrackerAimSource.CornerOrder. From these three
## points the wall's physical size and its placement relative to the tracker are
## derived, and tracker space is mapped onto the virtual wall's UV space.

## Sampled rigid-body positions, in the order dictated by `corner_order`.
@export var corners: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
## Which TrackerAimSource.CornerOrder the corners were captured in.
@export var corner_order: int = 0
@export var calibrated: bool = false
