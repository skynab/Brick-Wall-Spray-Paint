extends Resource
class_name Nozzle

## Tunable parameters for one spray cap. Presets live in res://nozzles/*.tres.

## Display name shown in the HUD / menu.
@export var nozzle_name: String = "Nozzle"
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
