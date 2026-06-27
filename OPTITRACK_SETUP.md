# OptiTrack / NatNet Setup (Phase 7)

The tracker code is already in the project and is **inert until the plugin is installed** —
the app runs normally on mouse aim without it. Follow these steps to drive the spray from a
tracked canister.

## 1. Install the plugin

1. Unzip `OptiTrack_Godot_Plugin_1.0.0.zip`.
2. Copy `example-project/addons/optitrack_plugin/` into this project's `addons/` folder
   (so you have `addons/optitrack_plugin/...`, including `bin/NatNetLib.dll`).
3. Open the project in Godot → **Project → Project Settings → Plugins** → enable **OptiTrack**.
   This registers the `/root/OptiTrack` autoload (a `MotiveClient`).

## 2. Connect to Motive

In the editor's **OptiTrack dock** (lower right): set **Server IP** (Motive PC),
**Client IP** (this PC), and **Multicast** to match Motive's streaming settings, then
**Start Connection**. The indicator turns green and your rigid bodies appear in the Asset List.

## 3. Point the app at the canister rigid body

- Run the app, open the side menu (`M`), set **Rigid Body ID** to the canister's asset ID in Motive.
- Switch **Aim source** to **Tracker** (or press `T`). The status line shows
  `Aim: Tracker (active) | Calib: none` once connected.

> The app reads the pose directly via `OptiTrack.get_rigid_body_pos/_rot(id)`, so you do **not**
> need to add an `OptiTrackRigidBody` node. If you want to *see* the canister in the 3D view, you
> may optionally add one (with the plugin installed) and assign the same asset ID — it's
> visualization only and doesn't affect aiming.

## 4. Calibrate the wall (maps tracker space → wall)

Click **Calibrate wall (3 corners)** in the menu (must be connected). Then, following the status
prompts, touch the canister to each physical wall corner and press **Space** to capture:

1. **TOP-LEFT**, 2. **TOP-RIGHT**, 3. **BOTTOM-LEFT**.

The three points define the wall plane and its axes in tracker space; the app builds a linear map
onto the virtual wall's UV space and saves it to `user://tracker_calibration.tres` (auto-loaded on
next launch). After this, pointing the physical canister moves the spray hit point on the wall.

## 5. Trigger options

- **Keyboard (default):** hold `Space` to spray, exactly as with the mouse.
- **Proximity auto-spray (optional):** tick **Auto-spray near wall** and set the **Proximity**
  threshold. When enabled and the calibrated canister is within the threshold distance of the wall
  plane, it sprays automatically — a stand-in for a physical trigger. Off by default.

## Tuning notes

- **Forward axis:** the nozzle direction is the canister rigid body's local `-Z`
  (`AppConfig.CANISTER_FORWARD_AXIS`). If your rigid body's "forward" is a different axis, change
  that constant.
- **Fine offset:** `TrackerAimSource.position_offset` nudges the mapped origin if needed.
- **Re-calibrate** any time the wall, projector, or capture volume moves.
- **Units:** the proximity threshold is in wall/world units (≈ metres, since the wall is sized in
  metres and corners are captured in Motive metres).
