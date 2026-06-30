extends AimSource
class_name TrackerAimSource

## The three adjacent wall corners to sample, in capture order. Each option walks
## the rectangle's perimeter starting from a different corner, so whichever three
## corners are easiest to reach physically can be used. The remaining (fourth)
## corner — and the wall's width/height — are derived from the three samples.
enum CornerOrder { TL_BL_BR, BL_BR_TR, BR_TR_TL, TR_TL_BL }

## Human-readable corner sequence per CornerOrder (used for capture prompts).
const CORNER_SEQUENCES := [
	["TOP-LEFT", "BOTTOM-LEFT", "BOTTOM-RIGHT"],
	["BOTTOM-LEFT", "BOTTOM-RIGHT", "TOP-RIGHT"],
	["BOTTOM-RIGHT", "TOP-RIGHT", "TOP-LEFT"],
	["TOP-RIGHT", "TOP-LEFT", "BOTTOM-LEFT"],
]

## Short dropdown labels per CornerOrder.
const CORNER_ORDER_LABELS := [
	"TL → BL → BR",
	"BL → BR → TR",
	"BR → TR → TL",
	"TR → TL → BL",
]

## Aims the spray from a Motive rigid body (the spray canister), streamed via the
## OptiTrack plugin. Reads pose directly from the OptiTrack autoload singleton so
## the project doesn't depend on the plugin being installed — when the singleton
## is absent the source is simply inactive.
##
## Plugin API used (verified from OptiTrack_Godot_Plugin_1.0.0):
##   OptiTrack.is_connected_to_motive() -> bool
##   OptiTrack.get_rigid_body_pos(asset_id) -> Vector3
##   OptiTrack.get_rigid_body_rot(asset_id) -> Quaternion

# Untyped on purpose: the plugin's MotiveClient methods aren't on base Node, so
# this must be a dynamic dispatch target. Holds /root/OptiTrack, or null.
var optitrack
var asset_id: int = 1
var forward_axis: Vector3 = Vector3(0, 0, -1)
var position_offset: Vector3 = Vector3.ZERO
var calibration: TrackerCalibration
## Physical wall size (metres) the tracker space is mapped onto.
var wall_size: Vector2 = AppConfig.WALL_SIZE

# NatNet connection settings (applied to the plugin singleton, best-effort).
var server_ip: String = "127.0.0.1"
var client_ip: String = "127.0.0.1"
var use_multicast: bool = true

## Max distance (m) from the wall plane the nozzle maps onto the wall. Beyond it,
## get_ray() reports invalid so no preview/spray appears.
var max_spray_distance: float = AppConfig.MAX_SPRAY_DISTANCE_DEFAULT

## Connection diagnostics, in increasing order of "good" so the value doubles as
## a severity level for UI colouring (see connection_status()).
enum ConnectionStatus { DISCONNECTED, CONNECTED, RIGID_BODY }

# Cached tracker-space -> virtual-wall-space linear map.
var _linear: Basis = Basis()
var _world_tl: Vector3 = Vector3.ZERO
var _origin_tracker: Vector3 = Vector3.ZERO  # tracker-space top-left (mapping origin)
var _mapped := false
## Physical wall size (m) derived from the last finalized calibration triangle.
var _derived_size: Vector2 = Vector2.ZERO


func _init(optitrack_singleton: Node, calib: TrackerCalibration = null) -> void:
	optitrack = optitrack_singleton
	forward_axis = AppConfig.CANISTER_FORWARD_AXIS
	calibration = calib if calib != null else TrackerCalibration.new()
	recompute()


func set_optitrack(node: Node) -> void:
	optitrack = node


## Update the physical wall size and rebuild the tracker -> wall mapping.
func set_wall_size(size: Vector2) -> void:
	wall_size = size
	recompute()


## Apply NatNet connection settings and (re)connect. The exact plugin property /
## method names aren't guaranteed, so each push is guarded — unknown ones are
## skipped. With no plugin installed this just records the values for later.
func configure(p_server_ip: String, p_client_ip: String, p_multicast: bool) -> void:
	server_ip = p_server_ip
	client_ip = p_client_ip
	use_multicast = p_multicast
	if optitrack == null:
		return
	_try_set(optitrack, "server_address", server_ip)
	_try_set(optitrack, "client_address", client_ip)
	_try_set(optitrack, "local_address", client_ip)
	_try_set(optitrack, "use_multicast", use_multicast)
	for m in ["connect_to_server", "start_connection", "connect_to_motive"]:
		if optitrack.has_method(m):
			optitrack.call(m)
			break


## Set a property on `obj` only if it actually exists (avoids plugin-version errors).
func _try_set(obj, prop: String, value) -> void:
	if obj == null:
		return
	for p in obj.get_property_list():
		if p.get("name", "") == prop:
			obj.set(prop, value)
			return


func is_active() -> bool:
	return optitrack != null and optitrack.is_connected_to_motive()


## Current NatNet connection state, for diagnostics in the UI:
##   DISCONNECTED — no plugin installed, or not connected to Motive.
##   CONNECTED    — connected to Motive, but the selected rigid body isn't streaming.
##   RIGID_BODY   — connected and the selected rigid body is being tracked.
func connection_status() -> ConnectionStatus:
	if optitrack == null or not optitrack.is_connected_to_motive():
		return ConnectionStatus.DISCONNECTED
	if _rigid_body_tracked():
		return ConnectionStatus.RIGID_BODY
	return ConnectionStatus.CONNECTED


## Human-readable form of connection_status().
func connection_status_text() -> String:
	match connection_status():
		ConnectionStatus.RIGID_BODY:
			return "Rigid Body Connected"
		ConnectionStatus.CONNECTED:
			return "Connected"
		_:
			return "Not Connected"


## True when the selected rigid body is actually streaming pose data. Prefers an
## explicit plugin query if the installed version exposes one; otherwise infers
## from the pose, since an untracked body reports the origin.
func _rigid_body_tracked() -> bool:
	if optitrack == null:
		return false
	for m in ["is_rigid_body_tracked", "is_rigid_body_valid", "is_rigid_body_active"]:
		if optitrack.has_method(m):
			return bool(optitrack.call(m, asset_id))
	var p = optitrack.get_rigid_body_pos(asset_id)
	return p != null and p != Vector3.ZERO


func get_label() -> String:
	return "Tracker"


func is_calibrated() -> bool:
	return _mapped


## Raw canister position in tracker space, or null if unavailable.
func canister_position() -> Variant:
	if not is_active():
		return null
	return optitrack.get_rigid_body_pos(asset_id)


func get_ray() -> Dictionary:
	if not is_active():
		return {"valid": false}
	var pos: Vector3 = optitrack.get_rigid_body_pos(asset_id)
	var rot: Quaternion = optitrack.get_rigid_body_rot(asset_id)
	var fwd: Vector3 = (rot * forward_axis).normalized()
	if _mapped:
		var o := _linear * (pos - _origin_tracker) + _world_tl + position_offset
		# Map the nozzle straight onto the wall (perpendicular projection) rather
		# than relying on can orientation — but only while it's close enough.
		if absf(o.z) > max_spray_distance:
			return {"valid": false}
		var d := Vector3(0, 0, -1) if o.z >= 0.0 else Vector3(0, 0, 1)
		return {"origin": o, "direction": d, "valid": true}
	# Uncalibrated: raw pose so motion is visible (likely misaligned until calibrated).
	return {"origin": pos + position_offset, "direction": fwd, "valid": true}


## Distance from the canister to the (virtual) wall plane, in world units.
func get_wall_distance() -> float:
	if not is_active() or not _mapped:
		return INF
	var pos: Vector3 = optitrack.get_rigid_body_pos(asset_id)
	var o := _linear * (pos - _origin_tracker) + _world_tl + position_offset
	return absf(o.z)


# --- Calibration ------------------------------------------------------------

## The corner sequence (capture prompts) for the active CornerOrder.
func corner_sequence() -> Array:
	return CORNER_SEQUENCES[clampi(calibration.corner_order, 0, CORNER_SEQUENCES.size() - 1)]


## Select which three corners (and order) the next calibration samples.
func set_corner_order(order: int) -> void:
	calibration.corner_order = clampi(order, 0, CORNER_SEQUENCES.size() - 1)


## Capture the current canister position as the `index`-th corner of the active
## sequence (0/1/2, in corner_order). Returns false if the body isn't streaming.
func capture_corner(index: int) -> bool:
	var p = canister_position()
	if p == null or index < 0 or index > 2:
		return false
	if calibration.corners.size() < 3:
		calibration.corners.resize(3)
	calibration.corners[index] = p
	return true


## Mark calibration complete and rebuild the mapping. Returns true on success.
## On success, derived_wall_size() holds the wall size measured from the triangle.
func finalize_calibration() -> bool:
	calibration.calibrated = true
	recompute()
	return _mapped


## Wall size (m) derived from the last finalized calibration triangle, or ZERO.
func derived_wall_size() -> Vector2:
	return _derived_size


## Reconstruct the wall's TOP-LEFT, TOP-RIGHT and BOTTOM-LEFT corners (tracker
## space) from the three captured samples, accounting for capture order. The
## wall is a rectangle, so the unsampled corner is implied by the other three.
## Returns [TL, TR, BL].
func _canonical_corners() -> Array:
	var p0: Vector3 = calibration.corners[0]
	var p1: Vector3 = calibration.corners[1]
	var p2: Vector3 = calibration.corners[2]
	match calibration.corner_order:
		CornerOrder.BL_BR_TR:
			# p0=BL, p1=BR, p2=TR  ->  TL = TR + (BL - BR)
			return [p2 + (p0 - p1), p2, p0]
		CornerOrder.BR_TR_TL:
			# p0=BR, p1=TR, p2=TL  ->  BL = TL + (BR - TR)
			return [p2, p1, p2 + (p0 - p1)]
		CornerOrder.TR_TL_BL:
			# p0=TR, p1=TL, p2=BL  (already canonical, reordered)
			return [p1, p0, p2]
		_:
			# CornerOrder.TL_BL_BR: p0=TL, p1=BL, p2=BR  ->  TR = TL + (BR - BL)
			return [p0, p0 + (p2 - p1), p1]


func recompute() -> void:
	_mapped = false
	if calibration == null or not calibration.calibrated or calibration.corners.size() < 3:
		return
	var canon := _canonical_corners()
	var corner_tl: Vector3 = canon[0]
	var corner_tr: Vector3 = canon[1]
	var corner_bl: Vector3 = canon[2]
	# Physical wall size measured directly from the sampled triangle.
	_derived_size = Vector2((corner_tr - corner_tl).length(), (corner_bl - corner_tl).length())
	var w := wall_size.x
	var h := wall_size.y
	_origin_tracker = corner_tl
	_world_tl = Vector3(-w * 0.5, h * 0.5, 0.0)
	# Virtual wall basis spanning the face (+U right, +V down, N out-of-plane).
	var world_u := Vector3(w, 0, 0)
	var world_v := Vector3(0, -h, 0)
	var world_n := world_u.cross(world_v)
	# Tracker-space basis from the reconstructed corners.
	var tracker_u: Vector3 = corner_tr - corner_tl
	var tracker_v: Vector3 = corner_bl - corner_tl
	var tracker_n := tracker_u.cross(tracker_v)
	if tracker_n.length() < 0.000001:
		push_warning("Tracker calibration is degenerate (corners collinear/coincident).")
		return
	var a := Basis(tracker_u, tracker_v, tracker_n)
	var b := Basis(world_u, world_v, world_n)
	_linear = b * a.inverse()
	_mapped = true
