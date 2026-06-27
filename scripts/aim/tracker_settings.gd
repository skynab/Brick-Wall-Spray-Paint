extends Resource
class_name TrackerSettings

## Persisted OptiTrack / NatNet connection settings for the tracked spray
## canister. Edited from the side menu and applied to the OptiTrack singleton
## (best-effort — the plugin is wired in Phase 7). Saved to user:// so the rig
## comes back configured on the next launch.

## Motive server (the PC running Motive). Loopback for a single-PC setup.
@export var server_ip: String = "127.0.0.1"
## This machine's address the NatNet client binds to.
@export var client_ip: String = "127.0.0.1"
## Multicast (true) vs Unicast (false) — must match Motive's streaming setting.
@export var use_multicast: bool = true
## Manual offset added to the tracker origin, in world units (metres).
@export var position_offset: Vector3 = Vector3.ZERO
