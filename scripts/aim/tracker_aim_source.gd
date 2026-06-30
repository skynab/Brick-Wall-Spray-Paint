extends AimSource
class_name TrackerAimSource

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

## Connection diagnostics, in increasing order of "good" so the value doubles as
## a severity level for UI colouring (see connection_status()).
enum ConnectionStatus { DISCONNECTED, CONNECTED, RIGID_BODY }

# Cached tracker-space -> virtual-wall-space linear map.
var _linear: Basis = Basis()
var _world_tl: Vector3 = Vector3.ZERO
var _mapped := false


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
		var o := _linear * (pos - calibration.corners[0]) + _world_tl + position_offset
		var d := (_linear * fwd).normalized()
		return {"origin": o, "direction": d, "valid": true}
	# Uncalibrated: raw pose so motion is visible (likely misaligned until calibrated).
	return {"origin": pos + position_offset, "direction": fwd, "valid": true}


## Distance from the canister to the (virtual) wall plane, in world units.
func get_wall_distance() -> float:
	if not is_active() or not _mapped:
		return INF
	var pos: Vector3 = optitrack.get_rigid_body_pos(asset_id)
	var o := _linear * (pos - calibration.corners[0]) + _world_tl
	return absf(o.z)


# --- Calibration ------------------------------------------------------------

## Capture the current canister position as corner `index` (0=TL, 1=TR, 2=BL).
func capture_corner(index: int) -> bool:
	var p = canister_position()
	if p == null or index < 0 or index > 2:
		return false
	if calibration.corners.size() < 3:
		calibration.corners.resize(3)
	calibration.corners[index] = p
	return true


## Mark calibration complete and rebuild the mapping. Returns true on success.
func finalize_calibration() -> bool:
	calibration.calibrated = true
	recompute()
	return _mapped


func recompute() -> void:
	_mapped = false
	if calibration == null or not calibration.calibrated or calibration.corners.size() < 3:
		return
	var w := wall_size.x
	var h := wall_size.y
	_world_tl = Vector3(-w * 0.5, h * 0.5, 0.0)
	# Virtual wall basis spanning the face (+U right, +V down, N out-of-plane).
	var world_u := Vector3(w, 0, 0)
	var world_v := Vector3(0, -h, 0)
	var world_n := world_u.cross(world_v)
	# Tracker-space basis from the three captured corners.
	var tracker_u: Vector3 = calibration.corners[1] - calibration.corners[0]
	var tracker_v: Vector3 = calibration.corners[2] - calibration.corners[0]
	var tracker_n := tracker_u.cross(tracker_v)
	if tracker_n.length() < 0.000001:
		push_warning("Tracker calibration is degenerate (corners collinear/coincident).")
		return
	var a := Basis(tracker_u, tracker_v, tracker_n)
	var b := Basis(world_u, world_v, world_n)
	_linear = b * a.inverse()
	_mapped = true
