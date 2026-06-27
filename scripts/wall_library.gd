extends RefCounted
class_name WallLibrary

## Discovers the available brick-wall background images. Designed to be reliable
## in an exported .exe, where listing res:// at runtime does NOT work.
##
## Three sources, in display order:
##   1. The built-in default (res://assets/brick_wall.jpg) — always present.
##   2. Bundled extras — compiled into BUNDLED_WALLS so they survive export.
##      (In the editor we also auto-discover res://assets/walls/ for convenience.)
##   3. External images — a "walls" folder placed next to the executable, scanned
##      and loaded at runtime. This is the drop-in path for an exported build:
##      add images beside the .exe, no rebuild needed.

const DEFAULT_WALL := "res://assets/brick_wall.jpg"
const BUNDLED_DIR := "res://assets/walls"
## Extra images shipped inside the build. Add a line here whenever a new image
## is committed to assets/walls/ so it appears in exported builds too.
const BUNDLED_WALLS: Array[String] = [
]
const IMAGE_EXTS := ["jpg", "jpeg", "png", "webp"]


## Absolute path of the external drop-in folder next to the executable.
static func external_dir() -> String:
	return OS.get_executable_path().get_base_dir().path_join("walls")


## Ordered list of selectable walls as { name, path } dictionaries. Paths that
## start with res:// are imported resources; anything else is an absolute file
## path loaded at runtime (see BrickWall.set_brick_texture).
static func list_walls() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for p in _all_paths():
		if seen.has(p):
			continue
		seen[p] = true
		out.append({"name": _pretty_name(p), "path": p})
	return out


static func _all_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	paths.append(DEFAULT_WALL)
	for p in BUNDLED_WALLS:
		paths.append(p)
	# Editor-only convenience: auto-discover images dropped into the bundled
	# folder without having to also list them in BUNDLED_WALLS.
	if OS.has_feature("editor"):
		_scan_into(BUNDLED_DIR, paths)
	# External folder beside the .exe (the export drop-in workflow).
	_scan_into(external_dir(), paths)
	return paths


## Append image files found directly inside `dir` to `paths` (sorted).
static func _scan_into(dir_path: String, paths: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var found := PackedStringArray()
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and IMAGE_EXTS.has(f.get_extension().to_lower()):
			found.append(dir_path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	found.sort()
	for p in found:
		paths.append(p)


## Turn a path into a friendly label, e.g. "red_brick-01.jpg" -> "Red Brick 01".
static func _pretty_name(path: String) -> String:
	var base := path.get_file().get_basename()
	return base.replace("_", " ").replace("-", " ").strip_edges().capitalize()
