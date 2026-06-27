extends RefCounted
class_name AimSource

## Interface for anything that aims the spray at the wall. Implementations return
## a world-space ray; the wall turns that into a UV hit. Swapping the mouse for
## the OptiTrack canister (Phase 7) means adding another AimSource — nothing in
## the spray tool changes.

## Returns { "origin": Vector3, "direction": Vector3, "valid": bool }.
## When "valid" is false the other fields may be absent — always check it first.
func get_ray() -> Dictionary:
	return {"valid": false}


## Whether this source can currently produce aim (e.g. tracker connected).
func is_active() -> bool:
	return false


## Short label for the menu / HUD.
func get_label() -> String:
	return "None"
