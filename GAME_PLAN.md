# Brick Wall Spray Paint — Build Game Plan

A phased plan for building the Godot spray‑paint app, with a copy‑paste **Claude prompt** for
each phase. Build it one phase at a time: paste a prompt, let Claude implement it, run the project,
confirm the *Acceptance check* passes, then move to the next prompt.

---

## 1. What we're building

A Godot 4 desktop application that:

- Renders a large 3D **brick wall** filling the screen (eventually projected onto a real surface).
- Lets you **spray paint** onto the wall, leaving persistent marks that build up over time.
- Supports **multiple nozzle types** (fine cap, wide cap, splatter) and **switchable colors**.
- Is driven by **keyboard** for now (spray / switch nozzle / change color / clear / save / toggle menu),
  with the **mouse** used to aim — a stand‑in for the tracked spray canister.
- Has a **collapsible side menu** for tuning spray properties, hideable while the app is in use.
- Is structured so that, in a later phase, the mouse aim is swapped for the **OptiTrack / NatNet**
  motion‑tracked canister with minimal rework.

## 2. Key technical decisions (locked in)

| Decision | Choice | Why |
|---|---|---|
| Engine | **Godot 4.3 or 4.4 (stable), Windows x86_64** | OptiTrack plugin requires Godot ≥ 4.1 and ships Windows x64 GDExtension DLLs (`NatNetLib.dll`). |
| Language | **GDScript** | Matches the plugin; fastest to iterate. |
| Paint storage | **CPU `Image` + `ImageTexture`** (V1) | Simple, deterministic spray semantics (scatter, buildup, drips), trivial save‑to‑PNG, easy clear/undo. Swap to a GPU SubViewport approach only if large brushes become a bottleneck. |
| Wall surface | Single `MeshInstance3D` quad with a `ShaderMaterial` compositing **brick albedo + paint texture** | Keeps brick and paint independent; paint can be cleared without reloading brick. |
| Aiming | **Mouse → ray → wall‑plane intersection → UV** now; abstracted behind an "aim source" so the tracker drops in later | Decouples input device from painting. |
| Spray trigger | Keyboard (hold), configurable | The physical canister has no button by default; keep trigger pluggable. |

## 3. Aiming + painting model (so prompts stay consistent)

- The wall is a flat quad of known world size and a known UV mapping (0..1 across the face).
- An **aim source** produces, each frame, a ray (origin + direction) in world space.
  - `MouseAimSource`: camera + mouse screen position → ray.
  - `TrackerAimSource` (later): canister position + forward direction from OptiTrack.
- Intersect the ray with the wall plane → world hit → UV → pixel coordinate in the paint `Image`.
- While the spray trigger is held, each frame emit droplets scattered around the hit pixel and
  blend the current color into the `Image`; `ImageTexture.update()` pushes it to the shader.

## 4. Target project structure

```
project.godot
main.tscn                 # root: wall + camera + light + controller + UI
scripts/
  app.gd                  # top-level wiring, input map, mode switching
  wall.gd                 # wall sizing, UV<->pixel helpers, plane intersection
  paint_layer.gd          # owns the Image/ImageTexture; stamp(), clear(), snapshot()
  spray_tool.gd           # spray loop: nozzle + color -> droplets -> paint_layer
  aim/aim_source.gd       # interface
  aim/mouse_aim_source.gd
  aim/tracker_aim_source.gd   # added in OptiTrack phase
  nozzles/nozzle.gd       # Resource: radius, flow, scatter, droplets, softness, drip
  ui/side_menu.gd
scenes/
  wall.tscn
  ui/side_menu.tscn
nozzles/                  # *.tres nozzle presets
assets/
  brick_wall.png          # the provided reference image (or a tiling brick texture)
addons/                   # OptiTrack plugin (added in final phase)
```

## 5. Controls (target scheme)

| Action | Key |
|---|---|
| Spray (hold) | `Space` or Left Mouse |
| Cycle nozzle | `Tab` (or `N`) |
| Cycle color | `C`; pick palette directly with `1`–`6` |
| Clear wall | `X` |
| Undo | `Ctrl+Z` |
| Save PNG of wall | `Ctrl+S` |
| Toggle side menu | `M` |
| Quit / release mouse | `Esc` |

---

## 6. How to use the prompts

1. Open this folder in Claude Code (Godot installed, the project will live in this repo root).
2. Paste **Phase 0**'s prompt. Let it create the project. Open it in the Godot editor once to let
   Godot import assets, then run.
3. Verify the *Acceptance check*. If something's off, tell Claude what you see — don't jump ahead.
4. Repeat for each phase. Phases are ordered so each one runs and is testable on its own.
5. Keep the OptiTrack zip handy; it's only needed in Phase 7.

> Tip: start each Claude prompt by reminding it of the engine: *"This is a Godot 4.4 GDScript
> project on Windows."* Each prompt below already states the contract and an acceptance check.

---

## Phase 0 — Project scaffold

**Prompt:**

```
This is a new Godot 4.4 (stable) GDScript project for Windows. Initialize it in the current
folder as the project root.

Create:
- project.godot configured for Godot 4.4, Forward+ renderer, window 1600x900, titled
  "Brick Wall Spray Paint", with a transparent-free opaque clear color.
- main.tscn with a root Node3D named "App" using scripts/app.gd (can be a near-empty
  _ready that prints "App ready" for now).
- The folder structure from the plan: scripts/, scripts/aim/, scripts/nozzles/ (use
  scripts/ subfolders), scenes/, scenes/ui/, nozzles/, assets/.
- An InputMap in project.godot with these actions and default bindings:
  spray (Space + Left Mouse), cycle_nozzle (Tab), cycle_color (C),
  palette_1..palette_6 (keys 1-6), clear_wall (X), undo (Ctrl+Z),
  save_png (Ctrl+S), toggle_menu (M), quit (Escape).
- A .gitignore already exists; don't overwrite it.

Do not implement gameplay yet. Acceptance: the project opens in Godot and runs, showing an
empty 3D viewport and printing "App ready".
```

**Acceptance check:** project runs; console prints `App ready`; the InputMap actions all exist.

---

## Phase 1 — The 3D brick wall

Drop the provided brick image into `assets/` first (rename to `brick_wall.png`). The reference
photo is `C:\Users\Candace\Downloads\...` brick image — copy it in, or use any seamless brick texture.

**Prompt:**

```
This is the Godot 4.4 spray-paint project. Build the wall scene.

assets/brick_wall.png is a brick texture. Create scenes/wall.tscn + scripts/wall.gd:
- A MeshInstance3D using a QuadMesh (or PlaneMesh oriented to face -Z) sized so the wall is
  about 6m wide with the same aspect ratio as brick_wall.png. Center it at the origin, facing
  the camera (+Z toward camera).
- For now use a StandardMaterial3D with brick_wall.png as albedo so we can see it. (We'll swap
  to a paint-compositing shader in a later phase.)
- A Camera3D positioned to frame the wall edge-to-edge, looking straight at it (orthographic OR
  perspective with the wall filling the view). The wall should fill the window with a small margin.
- Soft, even lighting (a DirectionalLight3D plus environment ambient) so brick detail reads but
  there are no harsh shadows. Add a WorldEnvironment with a neutral background.

scripts/wall.gd should expose helper methods (even if stubbed): the wall's world size,
world-to-UV, UV-to-pixel (given a target paint resolution), and ray-plane intersection that
returns the UV hit for a given ray origin+direction, or null if it misses.

Instance wall.tscn into main.tscn. Acceptance: running the project shows the brick wall filling
the screen, evenly lit, facing the camera.
```

**Acceptance check:** brick wall fills the window, evenly lit, camera square‑on.

---

## Phase 2 — Painting core (mouse → UV → persistent paint)

**Prompt:**

```
Godot 4.4 spray-paint project. Add the paint layer and make the wall show paint.

1. scripts/paint_layer.gd (a Node3D or RefCounted owned by the wall): owns an Image of fixed
   resolution matched to the brick aspect (e.g. 2048 x <aspect>), format RGBA8, initially fully
   transparent, plus an ImageTexture created from it.
   - stamp(center_uv: Vector2, color: Color, radius_px: float, opacity: float, softness: float):
     blends a single soft circular dab into the Image around center_uv, with a smooth alpha
     falloff to the edge, accumulating alpha (clamped to 1). Only touch the affected sub-rect for
     performance, and call ImageTexture.update() once per frame, not per dab.
   - clear(): resets to transparent. snapshot()/restore(): for undo. save_png(path).

2. Replace the wall's StandardMaterial3D with a ShaderMaterial whose shader composites:
   final = brick_albedo, then paint.rgb over it by paint.a (alpha-over). Feed brick_wall.png and
   the paint ImageTexture as uniforms.

3. Temporary test driver in scripts/app.gd: while the "spray" action is held, take the mouse
   position, build a camera ray, call wall.gd's ray-plane intersection to get the UV, and if it
   hits, stamp a fixed-size red dab. Defer the real spray tool to the next phase.

Acceptance: hold Space (or left mouse) and move the mouse over the wall — a red painted trail
builds up on the brick and persists. It does not clear between frames.
```

**Acceptance check:** holding spray + moving mouse paints a persistent red trail on the brick.

---

## Phase 3 — Spray tool, nozzles, and colors

**Prompt:**

```
Godot 4.4 spray-paint project. Turn the test dab into a real spray tool with nozzles and colors.

1. scripts/nozzles/nozzle.gd: a Resource (class_name Nozzle) with exported params:
   name, radius_px, flow (droplets per frame while held), scatter (spread radius as a fraction
   of radius_px), droplet_size_px, softness (edge falloff), build_rate (opacity added per droplet),
   drip_chance (0 for now). Create three .tres presets in nozzles/:
   - Fine Cap: small radius, low scatter, high build -> crisp line.
   - Wide Cap: large radius, soft falloff, low build -> broad fade.
   - Splatter: large scatter, few large droplets, some build -> speckle.

2. scripts/spray_tool.gd: holds the current nozzle, current color, and a palette of ~6 colors.
   Each frame the spray action is held and the aim hits the wall, scatter `flow` droplets within
   the nozzle radius around the hit UV (use a disc/gaussian distribution), and stamp each into
   paint_layer with the nozzle's droplet size, softness, and build_rate. Opacity builds up the
   longer you hold over one spot.

3. Wire input in app.gd:
   - cycle_nozzle -> next nozzle preset.
   - cycle_color -> next palette color; palette_1..6 -> pick that color directly.
   - clear_wall -> paint_layer.clear(); undo -> restore last snapshot (snapshot on spray start);
     save_png -> save the composited wall (brick + paint) to a timestamped PNG in user://.
   Print the active nozzle and color name to the console on change.

Acceptance: spraying produces a soft spray pattern (not a hard dab); Tab changes the pattern
character; C and number keys change color; X clears; Ctrl+Z undoes the last stroke; Ctrl+S saves
a PNG.
```

**Acceptance check:** spray looks like spray; nozzle/color switching, clear, undo, and save all work.

---

## Phase 4 — Collapsible side menu

**Prompt:**

```
Godot 4.4 spray-paint project. Add a hideable side control menu.

Create scenes/ui/side_menu.tscn + scripts/ui/side_menu.gd as a CanvasLayer/Control anchored to
the right edge, in a PanelContainer. It exposes live controls bound two-way to the spray tool and
nozzle:
- A ColorPickerButton for the current color, plus swatch buttons for the palette.
- An OptionButton (dropdown) to select the active nozzle preset.
- Sliders with value labels for: radius, flow, scatter, droplet size, softness, build rate,
  drip amount. Editing a slider updates the *current* nozzle's runtime params live.
- Buttons: Clear, Undo, Save PNG.
- A read-only status line (we'll later show OptiTrack connection state here).

Behavior:
- Toggle the whole panel with the toggle_menu action (M): slide it off-screen to the right and
  back with a short Tween. Start visible.
- Changing a control updates the spray tool immediately; switching nozzle via keyboard updates
  the menu controls to match (keep them in sync).
- The menu must not capture the spray input when the mouse is over the wall area; spraying still
  works while the menu is open, and is suppressed only when the cursor is actually over a menu widget.

Acceptance: M hides/shows the menu smoothly; sliders change spray behavior in real time; keyboard
and menu stay in sync.
```

**Acceptance check:** `M` toggles the menu; controls drive spray params live; no input conflicts.

---

## Phase 5 — Polish pass

**Prompt:**

```
Godot 4.4 spray-paint project. Polish the spray feel and robustness.

- Drips: when build-up at a spot exceeds a threshold (or per nozzle drip_chance), spawn occasional
  vertical drip streaks that run downward a short, randomized distance, fading out. Keep it cheap.
- Overspray/feather at the edge of each spray cone so wide-cap strokes fade naturally.
- A small on-screen HUD (toggle with the menu or always-on, your call) showing current nozzle and
  color, and a one-line key legend, dismissible.
- Multi-level undo (a small ring buffer of snapshots) instead of single-step.
- Make the paint resolution and wall size configurable constants in one place.
- Confirm it holds ~60 fps while spraying continuously with the widest nozzle; if not, only update
  the affected Image sub-rect and throttle ImageTexture.update() to once per frame.

Acceptance: drips occur on heavy build-up, edges feather, HUD shows state, multi-undo works, and
continuous wide-cap spraying stays smooth.
```

**Acceptance check:** drips, feathered edges, HUD, multi‑undo, smooth at 60 fps.

---

## Phase 6 — Aim‑source abstraction (prep for the tracker)

Do this **before** wiring OptiTrack so the integration is a drop‑in.

**Prompt:**

```
Godot 4.4 spray-paint project. Refactor aiming behind an interface so we can swap mouse for a
motion tracker later without touching the spray tool.

- scripts/aim/aim_source.gd: a base class/interface with get_ray() -> {origin: Vector3,
  direction: Vector3} in world space, and is_active()/get_debug_label().
- scripts/aim/mouse_aim_source.gd: implements it using the camera + mouse position (the current
  behavior).
- Change spray_tool.gd / app.gd to consume the active AimSource instead of reading the mouse
  directly. The wall's ray-plane intersection already takes origin+direction, so feed it the ray.
- Add a runtime switch (a menu toggle + a key) to choose the aim source; only "Mouse" exists now,
  but leave an obvious place to register "Tracker".

Acceptance: behavior is identical to before, but all aiming now flows through AimSource. Confirm
spray still works exactly as in Phase 5.
```

**Acceptance check:** identical behavior, but aiming is fully behind `AimSource`.

---

## Phase 7 — OptiTrack / NatNet integration (the tracked canister)

Context for Claude — the plugin's real API (verified from `OptiTrack_Godot_Plugin_1.0.0.zip`):

- Installing the plugin autoloads a singleton at `/root/OptiTrack` (a `MotiveClient`).
- Connection is configured via the editor's OptiTrack dock (Server IP = Motive PC, Client IP =
  this PC, Multicast must match Motive's streaming setting) and `optitrack_settings.tres`.
- A scene‑tree node type **`OptiTrackRigidBody`** (Node3D) animates to a Motive rigid body when you
  set its `rigid_body_asset_ID` and the connection is live. It also has `position_offset` /
  `rotation_offset`.
- Runtime accessors on the singleton: `OptiTrack.is_connected_to_motive()`,
  `OptiTrack.get_rigid_body_pos(asset_id) -> Vector3`,
  `OptiTrack.get_rigid_body_rot(asset_id) -> Quaternion`.
- Requires Godot ≥ 4.1, Windows x86_64; `NatNetLib.dll` must be in `addons/optitrack_plugin/bin/`.

**Setup steps (do these by hand, not via prompt):**
1. Unzip `OptiTrack_Godot_Plugin_1.0.0.zip`. Copy
   `example-project/addons/optitrack_plugin/` into this project's `addons/` folder.
2. Open the project in Godot → Project → Project Settings → Plugins → enable **OptiTrack**.
3. In the OptiTrack dock, set Server IP / Client IP / Multicast to match Motive, Start Connection,
   confirm the indicator is green and the canister rigid body appears in the Asset List.

**Prompt:**

```
Godot 4.4 spray-paint project. The OptiTrack plugin is now installed under addons/optitrack_plugin
and enabled, and a rigid body for the spray canister is streaming from Motive. Wire it as a
tracker-driven aim source.

Plugin API I will rely on (already verified):
- Autoload singleton at /root/OptiTrack (MotiveClient).
- OptiTrack.is_connected_to_motive() -> bool
- OptiTrack.get_rigid_body_pos(asset_id: int) -> Vector3
- OptiTrack.get_rigid_body_rot(asset_id: int) -> Quaternion
- An OptiTrackRigidBody Node3D type that auto-animates to a Motive asset id.

Do this:
1. Add an OptiTrackRigidBody node to main.tscn to represent the spray canister; expose its
   rigid_body_asset_ID. Optionally parent a small mesh (a stand-in can) to visualize it.
2. scripts/aim/tracker_aim_source.gd implementing AimSource: each frame, read the canister's
   world transform (from the OptiTrackRigidBody node, or directly via
   OptiTrack.get_rigid_body_pos/_rot with the asset id). get_ray() returns origin = canister
   position and direction = canister forward axis (the local -Z of its basis built from the
   quaternion). is_active() returns OptiTrack.is_connected_to_motive().
3. Register "Tracker" in the aim-source switch from Phase 6 so the menu/key can toggle
   Mouse <-> Tracker. Show OptiTrack.is_connected_to_motive() in the side-menu status line.
4. Calibration: add exported position/rotation/scale offsets (and a simple "set wall plane from
   tracker" helper) so the physical capture volume maps onto the virtual wall. Provide a 2-3 point
   calibration routine: aim at named wall corners, capture tracker rays, and solve the offset/scale
   that lines the tracker space up with the wall UV space. Persist the calibration to a resource.
5. Keep the spray trigger on the keyboard for now, but route it through a single configurable
   "trigger source" so a future physical/proximity trigger can replace it. (A proximity option:
   auto-spray when the canister-to-wall distance is under a menu-set threshold — add it behind a
   toggle, off by default.)

Acceptance: with Mouse selected, behavior is unchanged. With Tracker selected and Motive connected,
moving the physical canister moves the spray hit point on the wall; the status line shows
"Connected"; calibration aligns the spray point with where the canister actually points.
```

**Acceptance check:** toggling to *Tracker* with Motive live drives the spray point from the physical
canister; status shows Connected; calibration lines up the aim.

---

## Phase 8 (optional) — Projector / display alignment

For projecting onto a real wall: run the app borderless‑fullscreen on the projector output, and add
a calibration overlay (draggable corner handles applying a homography/keystone) so the rendered wall
matches the physical wall. Prompt Claude to add a "projection calibration" mode toggled by a key,
saving the corner warp to a resource, only once the tracker phase works.

---

## 7. Risks & notes

- **Plugin is Windows‑only x64 + Godot ≥ 4.1.** Stay on 4.3/4.4 stable; don't upgrade past what the
  GDExtension supports, and keep `NatNetLib.dll` next to the plugin DLL.
- **Coordinate alignment** (Motive metres, Y‑up vs Godot) is the hardest part of Phase 7 — that's why
  calibration and the `OptiTrackRigidBody` offsets exist. Budget time there.
- **CPU paint cost**: if wide‑cap continuous spray drops frames, switch `paint_layer` to a GPU
  SubViewport accumulation (non‑clearing render target) — keep the same `stamp()/clear()/snapshot()`
  interface so nothing else changes.
- **The trigger**: the physical can has no button. Decide later between keyboard, a second tracked
  marker, or proximity‑to‑wall auto‑spray (stubbed in Phase 7).
```
