extends Resource
class_name Nozzle

## Tunable parameters for one spray cap. Presets live in res://nozzles/*.tres.

## The geometric footprint of the spray cone. Drives how droplets are scattered
## around the aim point (see SprayTool._sample_offset).
##   ROUND    — even disc (classic cap).
##   OVAL     — disc stretched by `aspect` (fat/thin fan caps).
##   LINE     — narrow calligraphy stroke along the `angle` axis.
##   SQUARE   — uniform square footprint (stencil / hard cap edge).
##   SPLATTER — sparse jittered specks with size variation.
enum Shape { ROUND, OVAL, LINE, SQUARE, SPLATTER }

## Human-readable Shape names, indexed by the enum.
const SHAPE_LABELS := ["Round", "Oval", "Line", "Square", "Splatter"]

## Display name shown in the HUD / menu.
@export var nozzle_name: String = "Nozzle"
## Footprint geometry of the spray cone.
@export var shape: Shape = Shape.ROUND
## Width-to-height stretch of the footprint. 1 = symmetric; >1 widens along the
## local X axis (used by OVAL and LINE). Ignored by ROUND.
@export_range(1.0, 8.0, 0.1) var aspect: float = 1.0
## Rotation of the footprint in degrees. Orients OVAL/LINE/SQUARE patterns.
@export_range(-180.0, 180.0, 1.0) var angle: float = 0.0
## Overall spray-cone radius in paint pixels (max droplet distance from aim).
@export var radius_px: float = 60.0
## Droplets emitted per frame while the spray is held.
@export var flow: int = 12
## How spread out droplets are within the radius. 0 = tight cluster, 1 = full radius.
@export_range(0.0, 1.0) var scatter: float = 0.8
## Size of each individual droplet dab, in paint pixels.
@export var droplet_size_px: float = 8.0
## Edge feathering of each droplet. 0 = hard dot, 1 = fully soft.
@export_range(0.0, 1.0) var softness: float = 0.7
## Alpha added per droplet — controls how fast paint builds up.
@export_range(0.0, 1.0) var build_rate: float = 0.08
## Chance (0..1) a droplet seeds a drip. 0 until Phase 5.
@export_range(0.0, 1.0) var drip_chance: float = 0.0


## Display name of this nozzle's footprint shape.
func shape_label() -> String:
	return SHAPE_LABELS[shape] if shape >= 0 and shape < SHAPE_LABELS.size() else "?"
