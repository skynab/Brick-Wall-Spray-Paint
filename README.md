# Brick Wall Spray Paint

A Godot 4 desktop app for spray painting a virtual brick wall, built to be
projected onto a real surface and driven by a motion-tracked spray canister
(OptiTrack / NatNet). The mouse stands in for the canister during development.

Paint accumulates on the wall over time and persists until cleared. It's aimed
at installations and interactive exhibits.

## Features

- **Brick walls** — pick the background from bundled images, or drop your own
  into a `walls/` folder next to the executable (see *Adding wall images*).
- **Nozzle shapes** — Round, Oval, Line, Square and Splatter caps, each with
  size, scatter, softness, build-up, stretch (aspect) and rotation (angle).
  Presets: Fine Cap, Fat Cap, NY Thin, Calligraphy, Stencil Cap, Splatter.
- **Colors** — a quick palette (red, orange, yellow, green, blue, white, black)
  plus a full color picker.
- **Output rate** — a master "how fast the paint comes out" control.
- **Drips** — paint runs only after lingering over one spot too long; toggleable.
- **3D mouse aim** — the mouse sets a planar anchor; distance, pitch, yaw and
  roll move/tilt the can in front of the wall (roll spins shaped nozzles).
- **Vignette** — darken the brick toward the edges (under the paint).
- **Auto-clear** — clear manually only, or on a timer.
- **Spray preview cursor**, on-screen HUD, and a collapsible control menu with a
  Simple/Advanced toggle.
- **OptiTrack / NatNet** setup in-app: server/client IP, multicast vs unicast,
  rigid-body ID, origin offset, and 3-point wall calibration.
- **Projection mapping** — keystone/corner-warp calibration for aligning the
  rendered wall to a physical one.

## Controls

| Action | Key |
|---|---|
| Spray | `Space` / Left Mouse |
| Cycle nozzle | `Tab` |
| Cycle color / pick directly | `C` / `1`–`7` |
| Clear wall | `X` |
| Undo | `Ctrl+Z` |
| Save PNG | `Ctrl+S` |
| Toggle menu | `M` |
| Toggle HUD | `H` |
| Toggle spray cursor | `V` |
| Switch aim (Mouse/Tracker) | `T` |
| Projection calibration | `P` |
| Quit | `Esc` |

Saved images go to the Godot `user://` data folder.

## Running

1. Open the project folder in **Godot 4.x** (Windows x86_64).
2. Let it import assets on first open, then press **Play** (F5).

For an installation, export a Windows build and run it borderless-fullscreen on
the projector output.

## Adding wall images

- **Inside the build:** put an image in `assets/walls/`, add its
  `res://assets/walls/<name>` path to `BUNDLED_WALLS` in
  [`scripts/wall_library.gd`](scripts/wall_library.gd), then open the editor once
  to import it.
- **Without rebuilding (exported app):** drop images into a `walls/` folder
  beside the `.exe`; they're scanned and loaded at runtime.

Filenames become menu labels (`red_brick_01.jpg` → "Red Brick 01").

## Project layout

```
main.tscn            # root scene: wall, camera, light, UI, controller
scripts/
  app.gd             # top-level wiring + input
  wall.gd            # wall geometry, UV<->world, brick image switching
  paint_layer.gd     # the persistent paint buffer (Image + ImageTexture)
  spray_tool.gd      # nozzles + color -> droplets -> paint
  wall_library.gd    # discovers selectable wall images
  aim/               # AimSource interface: mouse + OptiTrack tracker
  nozzles/nozzle.gd  # nozzle Resource (shape/size/etc.)
  ui/                # side menu, HUD, spray cursor, projection warp
nozzles/             # *.tres nozzle presets
assets/walls/        # bundled wall images
shaders/             # brick + paint compositing, keystone warp
```

See [`GAME_PLAN.md`](GAME_PLAN.md) for the phased build plan and
[`OPTITRACK_SETUP.md`](OPTITRACK_SETUP.md) for tracker setup.
