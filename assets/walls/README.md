# Bundled wall images

Drop additional brick-wall images here (`.jpg`/`.jpeg`/`.png`/`.webp`).
Filenames become menu labels: `black_brick.jpg` -> "Black Brick".

After adding a file:
1. List its `res://assets/walls/<name>` path in `BUNDLED_WALLS`
   (scripts/wall_library.gd) so it ships in exported builds.
2. Open the project in the Godot editor once so Godot imports it.
   It then appears in the in-app **Wall** dropdown.

## Expected files (already wired in BUNDLED_WALLS)

Save the five provided images here, exactly named:

| File | Image |
|------|-------|
| `black_brick.jpg`             | charcoal / near-black brick |
| `warm_glow_brick.jpg`         | red brick with a warm light glow in the centre |
| `dark_aged_brick.jpg`         | dark, weathered brown brick |
| `new_red_brick.jpg`           | clean uniform bright-red brick |
| `orange_weathered_brick.jpg`  | orange/tan weathered brick |

Until a file is present and imported, its entry is hidden from the dropdown
(WallLibrary skips res:// images that don't exist), so nothing breaks.

> Note: end-user installs can also drop images into a `walls/` folder placed
> next to the .exe — those are scanned and loaded at runtime, no rebuild needed.
