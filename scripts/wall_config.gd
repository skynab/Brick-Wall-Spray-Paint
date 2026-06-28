extends Resource
class_name WallConfig

## Persisted physical + pixel dimensions of the wall, so the rendered visual can
## be mapped to a real LED wall. Physical size drives the 3D quad and the
## tracker -> wall mapping (real-world object position -> wall coordinates);
## resolution drives the paint buffer's pixel grid (ideally the LED panel's).
##
## Keep the physical and pixel aspect ratios equal to avoid distortion.

## Real-world wall size in metres (width, height).
@export var physical_size: Vector2 = Vector2(7.1111, 4.0)
## Pixel resolution of the wall (width, height).
@export var resolution: Vector2i = Vector2i(2048, 1152)
