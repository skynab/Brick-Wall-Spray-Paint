extends Node3D

## Top-level wiring for the Brick Wall Spray Paint app.
## Phase 7: spray tool + side menu + HUD, aiming behind an AimSource interface
## (Mouse / OptiTrack Tracker), with 3-point wall calibration and an optional
## proximity auto-spray trigger.

const MAX_UNDO := 20

@onready var _wall := $Wall as BrickWall
@onready var _camera: Camera3D = $Camera3D
@onready var _menu := $SideMenu as SideMenu
@onready var _hud := $Hud as Hud
@onready var _cursor := $SprayCursor as SprayCursor
@onready var _projection := $ProjectionWarp as ProjectionWarp

var _paint: PaintLayer
var _spray: SprayTool
var _wall_config: WallConfig
var _undo_stack: Array[Image] = []
var _stroke_active := false

var _aim_sources: Array[AimSource] = []
var _aim_index := 0
var _mouse: MouseAimSource
var _tracker: TrackerAimSource
var _tracker_settings: TrackerSettings

# Calibration flow state.
const CORNER_NAMES := ["TOP-LEFT", "TOP-RIGHT", "BOTTOM-LEFT"]
var _calibrating := false
var _calib_index := 0

# Proximity auto-spray trigger.
var _proximity_enabled := false
var _proximity_threshold := AppConfig.PROXIMITY_DEFAULT_THRESHOLD

# Wall clearing.
##   MANUAL — only clears on the Clear button / [X].
##   TIMER  — also auto-clears every `_clear_interval` seconds.
enum ClearMode { MANUAL, TIMER }
var _clear_mode := ClearMode.MANUAL
var _clear_interval := 100.0
var _clear_elapsed := 0.0


func _ready() -> void:
	print("App ready")
	_spray = SprayTool.new()
	_wall_config = _load_wall_config()
	if _wall != null:
		_wall.apply_dimensions(_wall_config.physical_size, _wall_config.resolution)
		_paint = _wall.get_paint_layer()
	_build_aim_sources()
	if _menu != null:
		_menu.setup(_spray)
		_menu.clear_requested.connect(_on_menu_clear)
		_menu.undo_requested.connect(_undo)
		_menu.save_requested.connect(_save_png)
		_menu.tool_changed.connect(_report_state)
		_menu.aim_source_selected.connect(_set_aim)
		_menu.calibrate_requested.connect(_start_calibration)
		_menu.aim_asset_id_changed.connect(_on_asset_id_changed)
		_menu.tracker_connect_requested.connect(_on_tracker_connect)
		_menu.tracker_offset_changed.connect(_on_tracker_offset)
		_menu.proximity_toggled.connect(func(on): _proximity_enabled = on)
		_menu.proximity_threshold_changed.connect(func(v): _proximity_threshold = v)
		_menu.clear_mode_changed.connect(_on_clear_mode_changed)
		_menu.clear_interval_changed.connect(func(v): _clear_interval = v)
		_menu.wall_selected.connect(_on_wall_selected)
		_menu.vignette_changed.connect(_on_vignette_changed)
		_menu.mouse_aim_changed.connect(_on_mouse_aim_changed)
		_menu.drips_toggled.connect(func(on): _spray.drips_enabled = on)
		_menu.wall_dimensions_changed.connect(_on_wall_dimensions_changed)
		_menu.fullscreen_toggled.connect(_set_fullscreen)
		_menu.set_aim_sources(_aim_labels(), _aim_index)
		if _wall_config != null:
			_menu.set_wall_dimensions(_wall_config.physical_size, _wall_config.resolution)
		if _tracker_settings != null:
			_menu.set_tracker_settings(
				_tracker_settings.server_ip,
				_tracker_settings.client_ip,
				_tracker_settings.use_multicast,
				_tracker_settings.position_offset,
			)
		_populate_walls()
	_frame_camera()
	get_viewport().size_changed.connect(_frame_camera)
	_update_aim_status()
	_report_state()


## Borderless fullscreen on the current monitor (so the render fills the LED
## wall) vs. a normal window. The viewport size_changed signal reframes the camera.
func _set_fullscreen(on: bool) -> void:
	get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED


func _toggle_fullscreen() -> void:
	var on := get_window().mode != Window.MODE_FULLSCREEN
	_set_fullscreen(on)
	if _menu != null:
		_menu.set_fullscreen(on)


## Position the camera so the whole wall fits the view, whatever its physical
## size/aspect. The wall shader is unshaded, so distance only affects framing.
func _frame_camera() -> void:
	if _camera == null or _wall == null:
		return
	var size := _wall.physical_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var vp := get_viewport().get_visible_rect().size
	var view_aspect := (vp.x / vp.y) if vp.y > 0.0 else (16.0 / 9.0)
	var t := tan(deg_to_rad(_camera.fov * 0.5))  # fov is vertical (KEEP_HEIGHT)
	if t <= 0.0:
		return
	var dist_h := (size.y * 0.5) / t                    # fit height
	var dist_w := (size.x * 0.5) / (t * view_aspect)    # fit width
	_camera.position = Vector3(0.0, 0.0, maxf(dist_h, dist_w) * 1.02)


func _build_aim_sources() -> void:
	_aim_sources.clear()
	_mouse = MouseAimSource.new(_camera, _wall)
	_aim_sources.append(_mouse)
	var ot := get_node_or_null(AppConfig.OPTITRACK_SINGLETON_PATH)
	_tracker = TrackerAimSource.new(ot, _load_calibration())
	_tracker.asset_id = AppConfig.DEFAULT_RIGID_BODY_ID
	_tracker_settings = _load_tracker_settings()
	_tracker.configure(_tracker_settings.server_ip, _tracker_settings.client_ip, _tracker_settings.use_multicast)
	_tracker.position_offset = _tracker_settings.position_offset
	if _wall_config != null:
		_tracker.set_wall_size(_wall_config.physical_size)
	_aim_sources.append(_tracker)


func _aim_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for src in _aim_sources:
		labels.append(src.get_label())
	return labels


func _active_aim() -> AimSource:
	if _aim_index < 0 or _aim_index >= _aim_sources.size():
		return null
	return _aim_sources[_aim_index]


func _process(delta: float) -> void:
	_handle_actions()
	# Roll from the active aim source rotates shaped nozzle footprints.
	var src := _active_aim()
	if _spray != null:
		_spray.extra_roll_deg = src.get_roll() if src != null else 0.0
	_handle_spray()
	_update_cursor()
	_update_clear_timer(delta)
	_update_tracker_diagnostics()
	# Keep the tracker's connection state visible while it's the active source.
	if _active_aim() == _tracker:
		_update_aim_status()


# --- Spraying ---------------------------------------------------------------

func _handle_spray() -> void:
	if _paint == null:
		return

	# While dragging projector corners, the mouse must not paint.
	if _projection != null and _projection.is_calibrating():
		return

	# During wall calibration, the spray button captures wall corners instead of painting.
	if _calibrating:
		if Input.is_action_just_pressed("spray"):
			_capture_calibration_point()
		return

	if _should_spray():
		# Don't paint while the pointer is interacting with the menu.
		if _menu != null and _menu.is_pointing_at_menu():
			_stroke_active = false
			return
		var uv = _aim_uv()
		if uv == null:
			return
		if not _stroke_active:
			# Snapshot once at the start of a stroke so undo reverts the whole stroke.
			_push_undo()
			_stroke_active = true
		_spray.spray(_paint, uv)
	else:
		_stroke_active = false


## The spray trigger: keyboard/mouse, or proximity auto-spray when enabled and
## the tracked canister is close enough to the wall.
func _should_spray() -> bool:
	if Input.is_action_pressed("spray"):
		return true
	if _proximity_enabled and _tracker != null and _tracker.is_active():
		return _tracker.get_wall_distance() <= _proximity_threshold
	return false


func _aim_uv() -> Variant:
	if _wall == null:
		return null
	var src := _active_aim()
	if src == null:
		return null
	var ray := src.get_ray()
	if not ray.get("valid", false):
		return null
	return _wall.ray_plane_uv(ray["origin"], ray["direction"])


# --- Aim preview cursor -----------------------------------------------------

## Project the active nozzle's footprint outline onto the screen at the aim point.
func _update_cursor() -> void:
	if _cursor == null or _wall == null or _camera == null or _paint == null:
		return
	# Hide the preview during calibration flows or while using the menu.
	if _calibrating or (_projection != null and _projection.is_calibrating()):
		_cursor.clear()
		return
	if _menu != null and _menu.is_pointing_at_menu():
		_cursor.clear()
		return
	var uv = _aim_uv()
	if uv == null:
		_cursor.clear()
		return
	var loop := _spray.footprint_outline_uv(uv, _paint.get_resolution())
	var pts := PackedVector2Array()
	for p in loop:
		pts.append(_camera.unproject_position(_wall.uv_to_world(p)))
	var col := _spray.current_color()
	col.a = 0.7
	_cursor.set_outline(pts, col)


# --- Actions ----------------------------------------------------------------

func _handle_actions() -> void:
	if Input.is_action_just_pressed("cycle_nozzle"):
		_spray.cycle_nozzle()
		_sync_menu()
		_report_state()
	if Input.is_action_just_pressed("cycle_color"):
		_spray.cycle_color()
		_sync_menu()
		_report_state()
	for i in 7:
		if Input.is_action_just_pressed("palette_%d" % (i + 1)):
			_spray.set_color_index(i)
			_sync_menu()
			_report_state()
	if Input.is_action_just_pressed("toggle_menu"):
		if _menu != null:
			_menu.toggle()
	if Input.is_action_just_pressed("toggle_hud"):
		if _hud != null:
			_hud.toggle()
	if Input.is_action_just_pressed("toggle_cursor"):
		if _cursor != null:
			_cursor.toggle()
	if Input.is_action_just_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
	if Input.is_action_just_pressed("cycle_aim"):
		if _aim_sources.size() > 1:
			_set_aim((_aim_index + 1) % _aim_sources.size())
	if Input.is_action_just_pressed("projection_calib"):
		if _projection != null:
			_projection.toggle_calibration()
	if Input.is_action_just_pressed("clear_wall"):
		_on_menu_clear()
	if Input.is_action_just_pressed("undo"):
		_undo()
	if Input.is_action_just_pressed("save_png"):
		_save_png()
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()


func _on_menu_clear() -> void:
	_clear_wall("Wall cleared")


# --- Wall background --------------------------------------------------------

func _populate_walls() -> void:
	if _menu == null or _wall == null:
		return
	var walls := WallLibrary.list_walls()
	var current := 0
	var active := _wall.current_brick_path()
	for i in walls.size():
		if String(walls[i].get("path", "")) == active:
			current = i
			break
	_menu.set_walls(walls, current)


func _on_wall_selected(path: String) -> void:
	if _wall != null:
		_wall.set_brick_texture(path)
		print("Wall -> %s" % path)


func _on_vignette_changed(strength: float, extent: float, softness: float) -> void:
	if _wall != null:
		_wall.set_vignette(strength, extent, softness)


func _on_mouse_aim_changed(distance: float, pitch: float, yaw: float, roll: float) -> void:
	if _mouse != null:
		_mouse.distance = distance
		_mouse.pitch_deg = pitch
		_mouse.yaw_deg = yaw
		_mouse.roll_deg = roll


## Clear the wall, snapshotting first so it can be undone, and reset the
## auto-clear countdown so a manual clear restarts the timer.
func _clear_wall(reason: String) -> void:
	if _paint == null:
		return
	_push_undo()
	_paint.clear()
	_clear_elapsed = 0.0
	print(reason)


# --- Auto-clear timer -------------------------------------------------------

func _on_clear_mode_changed(mode: int) -> void:
	_clear_mode = mode as ClearMode
	_clear_elapsed = 0.0
	if _menu != null and _clear_mode == ClearMode.MANUAL:
		_menu.set_clear_status("")


func _update_clear_timer(delta: float) -> void:
	if _paint == null or _clear_mode != ClearMode.TIMER:
		return
	_clear_elapsed += delta
	if _clear_elapsed >= _clear_interval:
		_clear_wall("Auto-cleared (timer)")
	if _menu != null:
		var remaining := maxf(0.0, _clear_interval - _clear_elapsed)
		_menu.set_clear_status("Clears in %ds" % int(ceil(remaining)))


func _sync_menu() -> void:
	if _menu != null:
		_menu.sync_from_tool()


func _set_aim(idx: int) -> void:
	if idx < 0 or idx >= _aim_sources.size():
		return
	_aim_index = idx
	if _menu != null:
		_menu.select_aim(idx)
	_update_aim_status()


func _update_aim_status() -> void:
	if _menu == null:
		return
	if _calibrating:
		return  # calibration prompts own the status line
	var src := _active_aim()
	if src == null:
		_menu.set_status("Aim: —")
		return
	var text := "Aim: %s (%s)" % [src.get_label(), "active" if src.is_active() else "inactive"]
	if src == _tracker:
		text += "  |  Calib: %s" % ("ok" if _tracker.is_calibrated() else "none")
	_menu.set_status(text)


## Push the live NatNet connection state + rigid-body position to the menu every
## frame, so the connection can be debugged regardless of the active aim source.
func _update_tracker_diagnostics() -> void:
	if _menu == null or _tracker == null:
		return
	var level := int(_tracker.connection_status())
	_menu.set_tracker_status(level, _tracker.connection_status_text(), _tracker.canister_position())


# --- Tracker calibration ----------------------------------------------------

func _start_calibration() -> void:
	if _tracker == null:
		return
	if not _tracker.is_active():
		_menu.set_status("Calibrate: tracker not connected")
		return
	# Make the tracker the active source so we can read the canister.
	_set_aim(_aim_sources.find(_tracker))
	_calibrating = true
	_calib_index = 0
	_prompt_calibration()


func _prompt_calibration() -> void:
	if _menu != null:
		_menu.set_status("Calibrate (%d/3): touch %s, press [Space]" % [_calib_index + 1, CORNER_NAMES[_calib_index]])


func _capture_calibration_point() -> void:
	if _tracker == null:
		return
	if not _tracker.capture_corner(_calib_index):
		_menu.set_status("Capture failed — is the rigid body streaming?")
		return
	_calib_index += 1
	if _calib_index >= 3:
		_finish_calibration()
	else:
		_prompt_calibration()


func _finish_calibration() -> void:
	_calibrating = false
	var ok := _tracker.finalize_calibration()
	if ok:
		_save_calibration()
	if _menu != null:
		_menu.set_status("Calibration %s" % ("saved" if ok else "failed (degenerate)"))
	_update_aim_status()


func _on_asset_id_changed(id: int) -> void:
	if _tracker != null:
		_tracker.asset_id = id


func _on_tracker_connect(server_ip: String, client_ip: String, multicast: bool) -> void:
	if _tracker_settings == null:
		_tracker_settings = TrackerSettings.new()
	_tracker_settings.server_ip = server_ip
	_tracker_settings.client_ip = client_ip
	_tracker_settings.use_multicast = multicast
	if _tracker != null:
		_tracker.configure(server_ip, client_ip, multicast)
	_save_tracker_settings()
	_update_aim_status()
	print("Tracker connect: server=%s client=%s %s" % [server_ip, client_ip, "multicast" if multicast else "unicast"])


func _on_tracker_offset(offset: Vector3) -> void:
	if _tracker_settings == null:
		_tracker_settings = TrackerSettings.new()
	_tracker_settings.position_offset = offset
	if _tracker != null:
		_tracker.position_offset = offset
	_save_tracker_settings()


## Apply new physical/pixel wall dimensions: resize the quad, reallocate the
## paint buffer (clearing the wall), update the tracker mapping, and persist.
func _on_wall_dimensions_changed(physical_size: Vector2, resolution: Vector2i) -> void:
	if _wall_config == null:
		_wall_config = WallConfig.new()
	var res_changed := resolution != _wall_config.resolution
	_wall_config.physical_size = physical_size
	_wall_config.resolution = resolution
	if _wall != null:
		_wall.apply_dimensions(physical_size, resolution)
		_paint = _wall.get_paint_layer()
	if _tracker != null:
		_tracker.set_wall_size(physical_size)
	_frame_camera()
	if res_changed:
		# Old snapshots are a different size and can't be restored into the new buffer.
		_undo_stack.clear()
	_save_wall_config()
	print("Wall: %.3f x %.3f m, %d x %d px" % [physical_size.x, physical_size.y, resolution.x, resolution.y])


func _load_wall_config() -> WallConfig:
	var path := AppConfig.WALL_CONFIG_PATH
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is WallConfig:
			return res
	return WallConfig.new()


func _save_wall_config() -> void:
	if _wall_config == null:
		return
	var err := ResourceSaver.save(_wall_config, AppConfig.WALL_CONFIG_PATH)
	if err != OK:
		push_warning("Failed to save wall config (%d)" % err)


func _load_tracker_settings() -> TrackerSettings:
	var path := AppConfig.TRACKER_SETTINGS_PATH
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is TrackerSettings:
			return res
	return TrackerSettings.new()


func _save_tracker_settings() -> void:
	if _tracker_settings == null:
		return
	var err := ResourceSaver.save(_tracker_settings, AppConfig.TRACKER_SETTINGS_PATH)
	if err != OK:
		push_warning("Failed to save tracker settings (%d)" % err)


func _load_calibration() -> TrackerCalibration:
	var path := AppConfig.TRACKER_CALIBRATION_PATH
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is TrackerCalibration:
			return res
	return TrackerCalibration.new()


func _save_calibration() -> void:
	if _tracker == null:
		return
	var err := ResourceSaver.save(_tracker.calibration, AppConfig.TRACKER_CALIBRATION_PATH)
	if err != OK:
		push_warning("Failed to save tracker calibration (%d)" % err)


func _push_undo() -> void:
	if _paint == null:
		return
	_undo_stack.append(_paint.snapshot())
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()


func _undo() -> void:
	if _undo_stack.is_empty():
		print("Nothing to undo")
		return
	_paint.restore(_undo_stack.pop_back())
	print("Undo")


func _save_png() -> void:
	if _wall == null:
		return
	var img := _wall.composite_to_image()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://brickwall_%s.png" % stamp
	if img.save_png(path) == OK:
		print("Saved -> %s" % ProjectSettings.globalize_path(path))
	else:
		push_warning("Save failed")


func _report_state() -> void:
	if _spray == null:
		return
	if _hud != null:
		_hud.set_state(_spray.current_nozzle().nozzle_name, _spray.current_nozzle().shape_label(), _spray.current_color())
	print("Nozzle: %s | Color %d (#%s)" % [
		_spray.current_nozzle().nozzle_name,
		_spray.color_index + 1,
		_spray.current_color().to_html(false),
	])
