extends RefCounted
class_name AppConfig

## Single place for the app's tunable constants.

# --- Wall / paint surface (defaults; overridden at runtime by WallConfig) ---
const WALL_SIZE := Vector2(7.1111, 4.0)        # metres (16:9)
const PAINT_RESOLUTION := Vector2i(2048, 1152) # paint buffer pixels (16:9)
## Persisted physical + pixel wall dimensions.
const WALL_CONFIG_PATH := "user://wall_config.tres"

# --- Spray feathering ---
## Normalized cone distance where droplet opacity starts fading toward the rim.
const SPRAY_EDGE_START := 0.65

# --- Vignette (darkens the brick toward the edges, under the paint) ---
## Peak darkening at the corners, 0 = off. Off by default; the operator dials it in.
const VIGNETTE_STRENGTH := 0.0
## Normalized radius (0 = centre, 1 = corner) where darkening begins.
const VIGNETTE_EXTENT := 0.7
## Width of the fade from clear to full darkening.
const VIGNETTE_SOFTNESS := 0.4

# --- Drips ---
const MAX_ACTIVE_DRIPS := 64
const DRIP_SPEED := 3.0            # px advanced per frame
const DRIP_WIDTH := 3.0            # dab radius of the running head
const DRIP_MIN_LEN := 40.0         # px
const DRIP_MAX_LEN := 170.0        # px
const DRIP_DWELL_FRAMES := 72      # frames (~1.2s at 60fps) lingering in one spot before a drip
const DRIP_DWELL_SEED_CHANCE := 0.06

# --- OptiTrack / tracker ---
const OPTITRACK_SINGLETON_PATH := "/root/OptiTrack"
const TRACKER_CALIBRATION_PATH := "user://tracker_calibration.tres"
const TRACKER_SETTINGS_PATH := "user://tracker_settings.tres"
const DEFAULT_RIGID_BODY_ID := 1
## Local axis of the canister rigid body that points out of the nozzle.
const CANISTER_FORWARD_AXIS := Vector3(0, 0, -1)
## Default proximity auto-spray threshold, in wall/world units (~metres).
const PROXIMITY_DEFAULT_THRESHOLD := 0.05
## Max distance (m) the tracked nozzle can be from the wall plane and still map
## onto it. Beyond this the preview/spray is suppressed.
const MAX_SPRAY_DISTANCE_DEFAULT := 1.0

# --- Projection mapping ---
const PROJECTION_CALIBRATION_PATH := "user://projection_calibration.tres"
