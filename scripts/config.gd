extends RefCounted
class_name AppConfig

## Single place for the app's tunable constants.

# --- Wall / paint surface ---
const WALL_SIZE := Vector2(7.1111, 4.0)        # metres (16:9)
const PAINT_RESOLUTION := Vector2i(2048, 1152) # paint buffer pixels (16:9)

# --- Spray feathering ---
## Normalized cone distance where droplet opacity starts fading toward the rim.
const SPRAY_EDGE_START := 0.65

# --- Drips ---
const MAX_ACTIVE_DRIPS := 64
const DRIP_SPEED := 3.0            # px advanced per frame
const DRIP_WIDTH := 3.0            # dab radius of the running head
const DRIP_MIN_LEN := 40.0         # px
const DRIP_MAX_LEN := 170.0        # px
const DRIP_DWELL_FRAMES := 36      # frames lingering before a heavy-buildup drip
const DRIP_DWELL_SEED_CHANCE := 0.05
