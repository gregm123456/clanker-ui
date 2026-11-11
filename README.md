# clankerUI

clankerUI is a Godot 4 experience for turning one or more displays into windows onto a
shared, animated 3D scene. Objects move through the scene, while a shader-driven cube
shows a live camera feed. Each display can show its calibrated part of the virtual
space, so the installation feels like one continuous world rather than a collection
of separate screens.

The Godot scene is the experience: it renders the world, handles movement and input,
and displays local camera video. Supporting services let multiple Raspberry Pis share
object state, use per-display installation settings, and show a still from another
node's camera when a remote object comes into view. You can run the project on a
desktop to explore and edit the scene, or deploy it to Raspberry Pi for an installation.

## Contents

- [The experience and hardware](#features-and-hardware-compatibility)
- [Run in development](#run-development)
- [Refresh the Godot class cache](#refresh-the-godot-class-cache)
- [Configure the Godot scene and object movement](#configure-the-3d-space-and-objects)
  - [World axes and movement](#world-axes-and-movement)
- [Configure each installation node](#per-node-installation-config-userinstallationcfg)
  - [Drive two portrait displays from one Pi](#one-pi-driving-two-portrait-displays)
  - [Automatic startup](#automatic-startup-on-the-two-pis)
  - [Shared screen-edge wrapping](#shared-screen-edge-wrapping)
  - [Remote webcam snapshots](#one-shot-remote-webcam-snapshots)
- [Runtime architecture and network protocol](#runtime-architecture)
- [Standalone Raspberry Pi deployment](#standalone-on-raspberry-pi)
  - [Export the project](#1-export-the-godot-project)
  - [Build the CSI camera extension](#2-build-the-csi-camera-native-extension-one-time-on-the-pi)
  - [Run](#3-run)
  - [Troubleshooting](#troubleshooting)
- [License](#license)

## Features and hardware compatibility

- **Raspberry Pi 5 & Single Board Computers**: Runs in full screen using Vulkan (Mobile) or OpenGL ES (GL Compatibility) rendering.
- **Display Adaptability**: Dynamically adapts to any display size, resolution, and orientation (landscape, portrait, ultrawide, square) connected to the Raspberry Pi.
- **USB Camera Support**: Automatically detects and displays live video feeds from standard USB cameras connected via Video4Linux2 (V4L2) on Linux / Raspberry Pi, as well as native feeds on macOS/Windows/iOS.
- **CSI Camera Support**: On Raspberry Pi, a native GDExtension (`addons/csi_camera`) captures
  directly from `libcamera` via GStreamer's `libcamerasrc`, bypassing the raw V4L2 CSI nodes
  entirely. This is the preferred camera source on Linux; if the extension or camera is
  unavailable, the app falls back to the USB/V4L2 `CameraServer` path automatically.
- **Controls**:
  - `F11` or `Alt + Enter`: Toggle Full Screen / Windowed mode.
  - `M`: Toggle mouse pointer visibility.
  - `Escape`: Quit application.

## Run (development)

Open the project in Godot 4.7 or later, then run `main.tscn`.

```bash
godot --main-scene res://main.tscn
```

On macOS/Windows/iOS, or on Linux with only a USB webcam attached, this uses the built-in
`CameraServer` path with no extra setup. The native CSI extension only loads on Linux
(`addons/csi_camera/csi_camera.gdextension` restricts its library entries to
`linux.arm64`), so it is skipped on other platforms.

## Refresh the Godot class cache

After every `git pull` or merge, refresh the class cache. Godot stores `class_name`
registrations in `.godot/global_script_class_cache.cfg`. This cache is **not** rebuilt
automatically when you run the project from the command line
(`Godot --main-scene res://main.tscn`) — it's only rebuilt when the editor
itself does a project scan.

If a pull/merge adds, removes, or renames a `class_name` script (e.g.
`MeshCalibrationModel`, `InstallationGeometry`) and the cache is stale,
`spinning_cube.gd` fails to compile with errors such as:

```
SCRIPT ERROR: Parse Error: Could not find type "MeshCalibrationModel" in the current scope.
ERROR: Failed to load script "res://spinning_cube.gd" with error "Parse error".
```

The symptom in the running app is a **static, non-spinning cube with no
camera image** — the whole `spinning_cube.gd` script silently failed to load,
so nothing it controls runs.

**Fix**: run this once after pulling/merging (and any time you add/rename a
`class_name` script yourself):

```sh
scripts/refresh_godot_class_cache.sh
```

This runs a headless editor pass (`Godot --headless --editor --quit-after 20`)
that rescans the project and rewrites `.godot/global_script_class_cache.cfg`.
Set `GODOT_BIN=/path/to/Godot` if your Godot binary isn't at the default macOS
location or on `PATH`. Make this a routine step in your pull workflow — it's
cheap and safe to run even when nothing changed.

## Configure the 3D space and objects

The 3D space is the scene made from `Node3D` nodes. In the editor, open `main.tscn` and
select a node in the Scene dock. Set its properties in the Inspector, or edit the same
values in the scene file when making repeatable deployments.

### World axes and movement

- **World axes**: `+X` = right, `+Y` = up, `+Z` = toward camera (default camera forward is `-Z`).
- **Movement vectors** (`move_velocity`, `move_acceleration`) are interpreted in **world space**, not camera-relative space.
- **Bounds modes**:
  - `2D Viewport Wrap` evaluates camera-relative X/Y viewport extents.
  - `3D Volume Bounds` evaluates world-space bounds, intended to align with physical installation geometry (`InstallationGeometry` resource) and supports both wrap and hard-wall clamp behavior.
- **Determinism path**: enable `use_fixed_step_movement` to run motion integration in `_physics_process` for fixed-step updates.

### Space parameters

These nodes define the space in the default scene:

| Node | Parameters to set | Effect |
| --- | --- | --- |
| `Camera3D` | `Transform > Position`, `Transform > Rotation`, `Fov` | Defines the viewer, camera angle, distance, and perspective. The default camera is at `(0, 0, 4)`, looking along `-Z`, with a `65` degree field of view. |
| `WorldEnvironment` | `Environment > Background`, ambient light, tonemapping, glow | Defines the background and global lighting response. |
| `DirectionalLight3D` and `DirectionalLight3D_Fill` | `Transform > Rotation`, `Light Color`, `Light Energy`, shadows | Defines the direction, color, and strength of the scene lights. |
| `SpinningCube` | `Transform > Position`, `Transform > Rotation`, `Mesh` | Defines the object's starting transform and visible geometry. |

For a different object, add a `Node3D` or `MeshInstance3D` under `Main`, assign a mesh,
and set its transform. A `Node3D` transform is composed of:

- **Position**: local translation `(x, y, z)`. With the default `Main` root at the origin,
  this is also the object's initial world position.
- **Rotation**: local Euler angles around X, Y, and Z. Godot's Inspector displays degrees;
  GDScript rotation methods use radians.
- **Scale**: local size multiplier `(x, y, z)`. Keep the scale at `(1, 1, 1)` when the
  mesh's own dimensions should control its size.

The `BoxMesh` size is separate from the node transform. For example, set `BoxMesh > Size`
to `(4.25, 4.25, 0.05)` to change the mesh dimensions, or set `SpinningCube > Transform
> Scale` to change the whole object including its children.

### Object movement and rotation

Select `SpinningCube` and set these exported properties:

| Property | Type and units | Meaning |
| --- | --- | --- |
| `floating_portrait` | Boolean | Uses a gentle upright wobble, a random 5–8-second near-view hold, a 1.5-second retreat and a 1-second fade-in at the front. X/Y drift remains active, with bounces at the top and bottom of the view. Enabled in the default scene. |
| `tumble_speed` | `Vector3`, radians/second | Continuous rotation speed around X, Y, and Z. For example `(0, 1.0, 0)` rotates around Y only. A negative value reverses that axis. |
| `move_velocity` | `Vector3`, world units/second | Initial movement velocity on X, Y, and Z. For example `(0.5, 1.0, 0)` moves right and up without moving toward or away from the camera. |
| `move_acceleration` | `Vector3`, world units/second squared | Added to velocity every update. Use `(0, 0, 0)` for constant velocity. |
| `use_fixed_step_movement` | Boolean | Updates movement in `_physics_process` for more repeatable fixed-step motion. |
| `enable_wraparound` | Boolean | Enables the selected boundary strategy. |
| `bounds_mode` | `None`, `2D Viewport Wrap`, or `3D Volume Bounds` | Chooses whether the object has no bounds, wraps against the camera-relative viewport, or uses a world-space volume. |
| `wrap_margin` | World units | Extra distance beyond the visible 2D viewport before the object wraps. It does not change 3D volume bounds. |
| `bounds_behavior` | `Wrap` or `Hard Wall Clamp` | For `3D Volume Bounds`, either teleports the object to the opposite side or clamps it at the wall. |
| `bounds_volume_center` | `Vector3`, world units | Center of the 3D bounds volume when no `InstallationGeometry` resource is assigned. |
| `bounds_volume_half_extents` | `Vector3`, world units | Half-width, half-height, and half-depth of the 3D bounds volume. The full volume is `center +/- half_extents`. |

With `floating_portrait` disabled, the runtime applies movement each update in this order:

1. Rotate the object using `tumble_speed * delta` around X, Y, and Z.
2. Update velocity using `move_velocity += move_acceleration * delta`.
3. Translate the object using `position += move_velocity * delta`.
4. Apply the selected viewport or 3D-volume bounds rule.

With it enabled, wobble is bounded relative to the starting rotation, depth is
controlled by the portrait cycle, and only the X/Y components of `move_velocity`
are used. `tumble_speed` and `move_acceleration` do not apply. With bounds enabled,
the whole portrait bounces off the vertical edges of the shared view while its
horizontal wrapping remains unchanged. It retreats up to 60 world units (limited
by configured 3D volume bounds; shared-screen bounds expand to accommodate it),
fades out near the end, and reappears near the starting
depth with a new random hold and horizontal direction at the same speed. On a
shared wall, it reappears just inside the edge opposite that direction, so it
drifts across the view. Opacity is synchronized with remote objects. Disable `floating_portrait`
to retain the original tumbling motion.

The object starts with the Position and Rotation values saved in the scene, then movement
changes its transform while the application runs. The current `spinning_cube.gd` also
randomizes `tumble_speed` and `move_velocity` during startup. To make Inspector values
remain exact, remove or disable that `randomize_speed_and_velocity()` call before relying
on fixed motion values.

### Example scene values

The following is the relevant shape of a `.tscn` configuration. `Vector3` values use
`(x, y, z)` order, and rotation values written in a scene file use radians:

```ini
[node name="SpinningCube" type="MeshInstance3D" parent="."]
position = Vector3(0, 0, 0)
rotation = Vector3(0, 0, 0)
scale = Vector3(1, 1, 1)
tumble_speed = Vector3(0, 0.7, 0)
move_velocity = Vector3(0.5, 1.0, 0)
move_acceleration = Vector3(0, 0, 0)
enable_wraparound = true
bounds_mode = 1
wrap_margin = 0.3
```

For a 3D installation volume, use `bounds_mode = 2`, set `bounds_behavior` to `0` for
wrap or `1` for hard-wall clamping, and configure `bounds_volume_center` and
`bounds_volume_half_extents`. An `InstallationGeometry` resource can be assigned instead
when the same physical bounds should be shared by multiple objects.

## Per-node installation config (`user://installation.cfg`)

Each Pi keeps its own local config in its Godot user-data directory so the same exported app
can run in different wall positions without rebuilding. On first run the project writes a
template config to `user://installation.cfg` and logs the resolved filesystem path via
`ProjectSettings.globalize_path("user://installation.cfg")`.

The canonical template lives in `config/installation.template.cfg` and is copied into place
when the file is missing. The file is intentionally user-editable and supports the following
sections and values:

```ini
[node]
node_id = local_display
peer_id = local

[wall]
columns = 2
rows = 1
monitor_width_mm = 168.0
monitor_height_mm = 300.0
gap_mm = 5.0
this_node_column = 0
this_node_row = 0
rotation_z_degrees = 0.0

[network]
mode = broadcast
udp_port = 9000
broadcast_address = 255.255.255.255
snapshot_tcp_port = 9010
heartbeat_interval_sec = 2.0
peer_timeout_sec = 15.0

[peers]
pi_right = 192.168.1.42:9000

[camera]
feed_index = 0
prefer_csi_camera = true
csi_camera_width = 960
csi_camera_height = 540
csi_camera_fps = 30
csi_camera_name =
csi_rotate_180 = false
webcam_fit_mode = 0
flip_webcam_horizontal = true

[faces]
service_url = "http://pi5ai2sd:5002/v1/attributes"
max_portraits = 10
```

At startup the scene applies these values as overrides to the exported defaults for:

- `mesh_node_id`
- `mesh_peer_id`
- `webcam_feed_index`
- `prefer_csi_camera`
- `csi_camera_width`
- `csi_camera_height`
- `csi_rotate_180` (rotates the native CSI feed and its shared snapshots, without affecting USB cameras)
- `csi_camera_fps`
- `csi_camera_name`
- `webcam_fit_mode`
- `flip_webcam_horizontal`

The exported values remain the editor-time fallback when a config value is absent or blank.
The `[faces]` values select the Hailo face-attributes endpoint and the maximum number
of face portraits retained per app instance. The defaults also apply to existing configs
without that section.

### One Pi driving two portrait displays

The normal single-screen mode remains the default. To use one Pi for two adjacent
screens, add the following to that Pi's existing `user://installation.cfg`:

```ini
[display]
combined_wall = true
left_screen = -1
right_screen = -1
```

With exactly two screens, `-1` selects them automatically. If there are more,
set both entries to distinct Godot screen indices; startup logs show the selected
rectangles. The screens must have equal logical sizes and be adjacent and
top-aligned. Arrange and rotate each output in the desktop configuration so
both images are upright; the two physical panels may be rotated 180 degrees
relative to each other. Do not apply that physical rotation again to the camera.

Set `[wall]` to two columns and one row. Set `monitor_width_mm` and
`monitor_height_mm` to the **visible** portrait panel dimensions, and `gap_mm`
to the measured combined bezel/air gap. For the Waveshare panels the published
visible width is approximately 64.8 mm; a 6 mm gap is approximately 56 pixels
at 600 pixels wide. Use `gap_mm = 0` to disable compensation. Existing
`this_node_column` and `rotation_z_degrees` settings do not move or rotate the
camera in combined-wall mode. Existing user configuration files are never
rewritten by this option.

The app renders one wider virtual image and omits the gap between its two
panel-sized slices. If layout detection or window placement fails, it logs a
warning and starts the usual one-screen scene. A topology change during combined
operation restarts display setup. F11/Alt-Enter restore the spanning rectangle
in combined mode; Escape and M retain their normal functions.

On `pi5ai2sd`, native Wayland currently reports unusable monitor positions to
Godot 4.7.2. To launch the installed build across both displays, log in as the
desktop user while its graphical session is running, then run this command from
the directory containing `clankerUI.sh` (including when connected over SSH):

```sh
XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
  ./clankerUI.sh --display-driver x11 -- --combined-wall
```

This selects XWayland and supplies the graphical-session environment used in
testing. `-- --combined-wall` enables combined mode for this run even if the
config does not. The socket and display names above are specific to the tested
session; use the actual desktop session's values if they differ.

Check the startup log for `backend=X11`, the two 600×1024 screen rectangles,
matching requested and actual spanning windows, and a 1200×1024 root viewport.
The window dimensions alone do not guarantee that the viewport resized. If the log says `X11
Display is not available`, check the graphical session and its environment. If
the app warns that the screens are not adjacent and equally sized or that the
window placement failed, it falls back to one screen; check the desktop display
layout before relaunching.

For a static grid and diagonal seam check, add
`-- --combined-wall --calibrate-display` to the launch command. The displayed
grid includes the hidden bezel strip, so its diagonal should continue behind
the physical gap rather than meet at the two visible edges.

The headless peer retains its existing shared-object and one-shot snapshot
protocol. A Pi without a monitor is not necessarily running Godot with
`--headless`; verify its CSI capture and peer connection separately. Touchscreen
input mapping is not configured by combined-wall mode.

#### Automatic startup on the two Pis

`pi5ai2sd` and `m5image` are configured to start the graphical Godot client
after their `gregm` desktop automatically logs in. A desktop autostart entry
starts the `clankerui` user service; systemd restarts it after an abnormal exit,
but not a normal exit. `pi5ai2sd` starts in combined-wall mode. `m5image`
starts a graphical window on its desktop, including its virtual desktop when
no monitor is connected; it does not use Godot's `--headless` mode.

One of the display Pi's panels is powered by `m5image`. Power on `m5image`
before starting `pi5ai2sd`, and make sure both panels are powered and detected.
If the display client starts before both outputs are ready, it can fall back to
one screen and will not automatically switch back when the second appears.
After both outputs are ready, restart the display client as `gregm`:

```sh
XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user restart clankerui.service
```

On either Pi, use the same environment prefix with `systemctl --user status
clankerui.service` or `systemctl --user stop clankerui.service` to check or stop
the app. The startup entry is `~/.config/autostart/clankerui.desktop`; the
service is `~/.config/systemd/user/clankerui.service`. The desktop session must
be running for automatic startup.

#### Shared screen-edge wrapping

To wrap objects only after they have fully left the combined view, add the same
settings to **every object-owning peer**, including headless peers:

```ini
[shared_screen_wrap]
enabled = true
panel_width_px = 600
panel_height_px = 1024
```

These are the logical portrait dimensions of one panel. All peers must also use
the same `[wall]` dimensions and gap and the same scene camera pose and FOV.
The virtual view includes the bezel gap; local viewport size and per-node camera
calibration do not determine the wrap edges. The existing depth wrap is retained.
When disabled (the default), the existing volume wrapping remains unchanged.
This option currently supports a two-column, one-row wall and a perspective camera
with height-locked FOV. If the combined display falls back to one screen, the
shared wrap reference remains the full wall.

> Hard requirement: all Pi nodes in the same installation must agree on the wall geometry
> (`columns`, `rows`, `monitor_width_mm`, `monitor_height_mm`, `gap_mm`) so the shared 3D
> world matches across screens. The per-node `this_node_column` and `this_node_row` values
> determine each Pi's placement inside that shared wall. `rotation_z_degrees` is per-node:
> positive values rotate the display counterclockwise in the world view, and negative values
> rotate it clockwise. For the current pair, use `-90` on the left clockwise-rotated node and
> `90` on the right counterclockwise-rotated node.

### One-shot remote webcam snapshots

Each node also listens on `network.snapshot_tcp_port` (default `9010`). When a remote proxy
crosses into the local camera frustum, the renderer requests one still image from the owning
peer. The TCP request is `GET /snapshot` followed by a newline. The response is a little-endian
4-byte JPEG length followed by exactly that many JPEG bytes; the connection then closes.

The snapshot server captures the current CPU-readable frame from the configured webcam or CSI
provider. The client decodes it into an `ImageTexture` and applies it to the proxy's shader.
Requests are polled asynchronously, have a short timeout, and are deduplicated per object while
in flight. A failed fetch leaves the proxy's existing neutral material or previous still intact.
The renderer only triggers on an outside-to-inside visibility transition, so a visible proxy does
not continuously fetch images.

### Face portraits

Each floating portrait's depth-cycle re-entry triggers face extraction from its camera:
the local camera supplies its current frame, while remote cameras supply a fresh snapshot
from their owning peers. Frames are sent asynchronously to the configured Hailo
`/v1/attributes` service. Every returned face crop is displayed at 1.5 times its original
pixel dimensions in a moving foreground overlay spanning the display. Each axis jiggles at
an independently randomized speed, ranging from the previous speeds to roughly 10 times
their maximum. The latest 10 crops
across cameras are retained by default; repeated appearances of the same person are
kept. Nothing is written to disk by the app.

Each portrait has a label: `M` for a male model score strictly above 0.70, `F` for
a female model score strictly above 0.70, and `?` otherwise. These are model
estimates, not verified attributes. The service determines which faces it detects
and limits detections per image (currently 10 by default).

Extraction is enabled on each app instance. Both peers must run this version to
publish and consume portrait-cycle markers; older peers continue to display snapshots
but cannot trigger remote extraction. Face extraction requires `floating_portrait`
and, for remote cameras, a working mesh connection and snapshot server. Missing frames,
unreachable services and saturated requests are logged; existing portraits remain
visible. Images are sent over HTTP to the configured host, so use a trusted network
and an appropriate service endpoint.

## Runtime architecture

- `spinning_cube.gd` now acts as a thin scene coordinator.
- `scripts/spinning_cube_input_controller.gd` owns keyboard input and window/mouse mode toggles.
- `scripts/spinning_cube_movement_controller.gd` owns tumbling, full 3D movement integration (velocity + acceleration), and bounds strategy evaluation.
- `scripts/spinning_cube_bounds_strategy.gd` provides pluggable bounds modes (none, 2D viewport wrap, 3D volume wrap/clamp).
- `scripts/webcam_camera_source_adapter.gd` owns webcam source selection and runtime updates while preserving the existing `CsiCameraProvider` and `CameraServer` paths.
- `scripts/spinning_cube_mesh_sync_controller.gd` owns mesh-sync orchestration and keeps `spinning_cube.gd` limited to wiring scene-level dependencies.
- `scripts/mesh_sync_service.gd` now owns typed shared-scene events for calibration, object lifecycle, and transform updates so scene nodes never parse transport payloads directly.
- `scripts/mesh_calibration_model.gd` stores per-node physical placement, orientation, viewport sizing, and camera offset data in one explicit resource model.
- `scripts/transform_sync_schema.gd` defines the versioned transform payload used for shared-scene state sync while keeping camera frame acquisition local-only.
- `scripts/peer_address_book.gd` lazily resolves configured IPv4 addresses and hostnames, including Tailscale names, with cached results and retry backoff.
- `scripts/udp_mesh_transport.gd` provides versioned JSON-over-UDP broadcast, unicast, or combined transport on the configured UDP port.
- `scripts/mesh_network_bridge.gd` connects the generic UDP envelope to `MeshSyncService`, forwards local spawn/calibration/transform updates, applies remote messages under an echo-prevention guard, and tracks peer heartbeat timeouts.
- `scripts/webcam_snapshot_server.gd` serves one JPEG still per TCP request without blocking the scene loop.
- `scripts/webcam_snapshot_client.gd` fetches and decodes one remote JPEG asynchronously.
- `scripts/remote_object_renderer.gd` requests snapshots on frustum-entry transitions and applies returned textures to proxy materials.

The Phase 3 UDP envelope is:

```json
{"version":1,"type":"transform|calibration|spawn|despawn|heartbeat","sender_peer_id":"peer-id","payload":{}}
```

Transform payloads use `TransformSyncSchema`, including optional portrait-cycle
sequence and incarnation fields for updated floating-portrait peers. Calibration payloads use the JSON-safe
dictionary form of `MeshCalibrationModel`; spawn and despawn payloads include `object_id`.
Unknown message types, unsupported versions, malformed JSON, and invalid payload shapes are
dropped without terminating the receiver. The network bridge is generic and does not render
remote objects; Phase 4 owns that scene behavior.

The envelope is the stable interoperability boundary for future clients: `sender_peer_id` is
the process identity, while `payload.object_id` identifies a shared object. A `spawn` payload
must contain the object descriptor and its `object_id`; a `transform` payload uses the existing
`TransformSyncSchema`, with optional `opacity` defaulting to 1 for older senders. Both peers
must support opacity for synchronized portrait re-entry; a `calibration` payload uses `MeshCalibrationModel.to_dictionary()`;
`despawn` contains only `object_id`; and `heartbeat` may use an empty object. Senders should use
the same `udp_port` for broadcast and configured unicast destinations. The `[peers]` port is the
UDP destination port; snapshot requests always use the remote node's `snapshot_tcp_port`.

The TCP snapshot wire format is deliberately not HTTP: send UTF-8 `GET /snapshot\n`, read a
little-endian uint32 JPEG length, then read exactly that many JPEG bytes. The maximum accepted
JPEG is 20 MiB. A closed connection means the request failed; clients retain the previous still
or neutral proxy material and do not retry continuously while the proxy remains visible.

## Standalone on Raspberry Pi

There are two parts to a full Raspberry Pi deployment:

1. Export the Godot project itself (`clankerUI.arm64` + `clankerUI.pck`) — required for both
   USB and CSI cameras.
2. Build the native CSI camera extension (`libcsi_camera.linux.arm64.so`) — only required if
   you want to use a Raspberry Pi CSI/ribbon-cable camera (e.g. Arducam, Camera Module 3).
   Skip this section entirely if you're only using a USB webcam.

### 1. Export the Godot project

Export a Linux/arm64 build from the Godot editor (Project → Export), which produces
`clankerUI.arm64` + `clankerUI.pck`.

On Raspberry Pi OS with a Wayland compositor that doesn't support the `wp-fifo` /
`wp-presentation` protocols, the Vulkan (Forward Mobile) renderer can hang on the boot splash
waiting on a presentation callback that never arrives. To avoid this, `project.godot` sets a
platform override so **Linux exports always use the GL Compatibility renderer** regardless of
the default (Mobile) used on other platforms:

```ini
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.linuxbsd="gl_compatibility"
```

This applies automatically to every Linux export — no command-line flags or manual edits to
`clankerUI.sh` needed after each export.

Copy `clankerUI.arm64`, `clankerUI.pck`, and `clankerUI.sh` to the Pi, then:

```bash
chmod +x clankerUI.arm64 clankerUI.sh
./clankerUI.sh
```

This alone is sufficient for a USB webcam. For a CSI camera, continue below.

### 2. Build the CSI camera native extension (one-time, on the Pi)

The CSI camera path is a small GDExtension (`addons/csi_camera`) that wraps a GStreamer
`libcamerasrc ! videoconvert ! appsink` pipeline and hands RGBA frames to Godot. It must be
compiled on a Raspberry Pi running 64-bit Raspberry Pi OS, because it links against the Pi's
installed `libcamera`/GStreamer/Godot headers.

#### Prerequisites

Confirm the camera works with the system camera stack before building anything:

```bash
rpicam-hello -n -t 2000
```

If this fails, fix the camera/overlay first (e.g. `dtoverlay=<your-sensor>,cam1` in
`/boot/firmware/config.txt`) — the GDExtension cannot work around a broken `libcamera` stack.

Install build tools and the GStreamer/libcamera development packages:

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake pkg-config git python3-pip \
  scons \
  gstreamer1.0-tools gstreamer1.0-libcamera \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

Verify the `libcamera` GStreamer plugin is present:

```bash
gst-inspect-1.0 libcamerasrc
```

#### Build the matching Godot C++ bindings (`godot-cpp`)

The extension needs `godot-cpp` bindings that match the Godot API version used by the editor
that exported the project (this repo targets Godot 4.7):

```bash
cd addons/csi_camera
git clone --depth 1 https://github.com/godotengine/godot-cpp.git
cd godot-cpp
scons platform=linux arch=arm64 target=template_release api_version=4.7 -j2
cd ../../..
```

This produces `addons/csi_camera/godot-cpp/bin/libgodot-cpp.linux.template_release.arm64.a`.
It only needs to be built once per Pi/toolchain; `addons/csi_camera/godot-cpp/` is git-ignored.

#### Build and test the camera pipeline in isolation

Before building the extension, confirm GStreamer can negotiate the capture pipeline on its own:

```bash
scripts/test_csi_camera_pipeline.sh
```

This runs a short `libcamerasrc ! videoconvert ! appsink` pipeline at 960×540/30fps and exits
successfully if frames were captured. Override resolution/fps with `CSI_CAMERA_WIDTH`,
`CSI_CAMERA_HEIGHT`, `CSI_CAMERA_FPS` environment variables if needed.

#### Build the extension

```bash
scripts/build_csi_camera_on_pi.sh
```

This script verifies `cmake`, `pkg-config`, GStreamer, and `libcamerasrc` are available, then
configures and builds `addons/csi_camera` with CMake, copies the resulting
`libcsi_camera.linux.arm64.so` into `addons/csi_camera/bin/`, and generates the active
`addons/csi_camera/csi_camera.gdextension` manifest from
`csi_camera.gdextension.template` (the manifest is git-ignored so macOS/Windows checkouts
never see a dangling Linux-only extension reference).

Verify the result:

```bash
file addons/csi_camera/bin/libcsi_camera.linux.arm64.so
ldd addons/csi_camera/bin/libcsi_camera.linux.arm64.so
```

#### Deploy alongside the exported project

Copy the extension manifest and compiled library next to the already-exported
`clankerUI.arm64` / `clankerUI.pck` on the Pi, preserving the relative path:

```text
clankerUI.arm64
clankerUI.pck
clankerUI.sh
addons/
  csi_camera/
    csi_camera.gdextension
    bin/
      libcsi_camera.linux.arm64.so
```

No changes to `clankerUI.sh` or `clankerUI.arm64` are needed — Godot resolves
`res://addons/csi_camera/...` relative to the executable's working directory, and
`clankerUI.sh` already `cd`s there before launching.

### 3. Run

The same launcher works for USB and CSI cameras:

```bash
./clankerUI.sh
```

At startup, `spinning_cube.gd` tries the native CSI provider first (`prefer_csi_camera = true`
by default); if `addons/csi_camera/csi_camera.gdextension` or its `.so` is missing, or the
camera fails to start, it logs the reason and falls back to the USB/V4L2 `CameraServer` path.
Watch the terminal for one of:

```text
[csi_camera] started 960x540 @ 30 fps
[webcam] using CSI camera provider at 960x540 @ 30 fps
```

or, on fallback:

```text
[webcam] CSI provider unavailable: <reason>
```

### Troubleshooting

**Running over a remote/VNC session (e.g. `rpi-connect`/`wayvnc`, or SSH into an existing
desktop session) instead of the Pi's local/attached display**
An SSH shell does not automatically inherit the desktop session's display environment. Find
the running session's values first (from an SSH shell, not the desktop itself):

```bash
loginctl list-sessions --no-legend
ps -u "$USER" -o pid,args | grep -E 'labwc|Xwayland|wayland'
```

Look for a process environment containing `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`,
`XDG_RUNTIME_DIR=/run/user/<uid>`, and `XAUTHORITY=/home/<user>/.Xauthority` (values will vary
per system), then pass them explicitly:

```bash
DISPLAY=:0 \
XAUTHORITY="$HOME/.Xauthority" \
./clankerUI.sh
```

Prefer testing on the Pi's local/attached display first — plugging in a real monitor and
running `./clankerUI.sh` from a terminal there needs none of this.

**`Can't create an EGL context` / `MESA: error: Couldn't get V3D core IDENT0`**
On some remote/VNC sessions, the compositor's GPU/DRI device selection doesn't match a local
session, and hardware-accelerated EGL fails outright even with a correct `DISPLAY`. Two
environment variables are the usual culprits:

- `DRI_PRIME` and `MESA_LOADER_DRIVER_OVERRIDE`, if set (e.g. inherited from a prior shell or
  `.bashrc`), can force Mesa to pick the wrong GPU driver. Unset them:
  `env -u DRI_PRIME -u MESA_LOADER_DRIVER_OVERRIDE ./clankerUI.sh`

If unsetting those doesn't help, fall back to software rendering (slower, but works anywhere
X11/Xwayland is reachable):

```bash
env \
  -u DRI_PRIME \
  -u MESA_LOADER_DRIVER_OVERRIDE \
  LIBGL_ALWAYS_SOFTWARE=1 \
  DISPLAY=:0 \
  XAUTHORITY="$HOME/.Xauthority" \
  ./clankerUI.sh \
  --display-driver x11 \
  --rendering-method gl_compatibility
```

- `LIBGL_ALWAYS_SOFTWARE=1` forces Mesa's `llvmpipe` software renderer instead of the V3D GPU
  driver.
- `--display-driver x11` skips Godot's Wayland backend (which hit the same EGL failure here)
  in favor of Xwayland, which is present on Raspberry Pi OS's default `labwc` desktop.
- `--rendering-method gl_compatibility` matches the renderer already baked into the Linux
  export (see `project.godot`), so it's not strictly required here but is harmless to repeat.

Prefer testing on the Pi's local/attached display first; hardware-accelerated rendering should
work there without any of the above.

**`GST_PLUGIN_PATH` / `LD_LIBRARY_PATH` pointing at a custom directory**
These are **not** part of a normal deployment. They're only needed if GStreamer/`libcamera`
packages were staged manually into a non-system prefix (for example, while working around a
missing `sudo` password during development) instead of installed with
`sudo apt install ...gstreamer1.0-libcamera...` as documented above. If you followed the
prerequisites section, the system linker and GStreamer's default plugin scanner already find
everything in `/usr/lib/aarch64-linux-gnu`, and neither variable should be set when running
`clankerUI.sh`.

**`arducam-pivariety.json not found` (or similar tuning-file warning) from `libcamera`**
Capture still works without it, but exposure/color may be suboptimal. Install the correct
tuning file for your sensor from your camera vendor's `libcamera` package, or ignore it if
image quality is acceptable.

**`gst-inspect-1.0 libcamerasrc` reports no such element**
`gstreamer1.0-libcamera` is not installed (see prerequisites above), or a leftover
`GST_PLUGIN_PATH`/`GST_PLUGIN_SYSTEM_PATH` from manual package staging (see above) is
overriding the system plugin search path. Run `gst-inspect-1.0 libcamerasrc` in a clean shell
(no `GST_PLUGIN_PATH`/`GST_PLUGIN_SYSTEM_PATH` set) to confirm.

**Camera works with `rpicam-hello` but the cube face stays on the fallback background**
Check the terminal log for `[csi_camera]`/`[webcam]` lines. A missing
`libcsi_camera.linux.arm64.so` or `csi_camera.gdextension` next to `clankerUI.arm64` is the
most common cause — re-check the deployment layout above.

## License

This project is licensed under the [MIT License](LICENSE).