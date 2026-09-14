# clankerUI

A Godot 4 project featuring a spinning, shader-driven 3D cube interface with live webcam feed texture mapping.

## Features & Hardware Compatibility

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

## ⚠️ Required after every `git pull` / merge: refresh the Godot class cache

Godot caches all `class_name` script registrations in
`.godot/global_script_class_cache.cfg`. This cache is **not** rebuilt
automatically when you run the project from the command line
(`Godot --main-scene res://main.tscn`) — it's only rebuilt when the editor
itself does a project scan.

If you pull/merge a change that adds, removes, or renames a `class_name`
script (e.g. `MeshCalibrationModel`, `InstallationGeometry`) and the cache is
stale, `spinning_cube.gd` fails to compile with errors such as:

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

## World axis and movement conventions

- **World axes**: `+X` = right, `+Y` = up, `+Z` = toward camera (default camera forward is `-Z`).
- **Movement vectors** (`move_velocity`, `move_acceleration`) are interpreted in **world space**, not camera-relative space.
- **Bounds modes**:
  - `2D Viewport Wrap` evaluates camera-relative X/Y viewport extents.
  - `3D Volume Bounds` evaluates world-space bounds, intended to align with physical installation geometry (`InstallationGeometry` resource) and supports both wrap and hard-wall clamp behavior.
- **Determinism path**: enable `use_fixed_step_movement` to run motion integration in `_physics_process` for fixed-step updates.

## Configure the 3D space and objects

The 3D space is the scene made from `Node3D` nodes. In the editor, open `main.tscn` and
select a node in the Scene dock. Set its properties in the Inspector, or edit the same
values in the scene file when making repeatable deployments.

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

The runtime applies movement each update in this order:

1. Rotate the object using `tumble_speed * delta` around X, Y, and Z.
2. Update velocity using `move_velocity += move_acceleration * delta`.
3. Translate the object using `position += move_velocity * delta`.
4. Apply the selected viewport or 3D-volume bounds rule.

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

## Run (development)

Open the project in Godot 4.7 or later, then run `main.tscn`.

```bash
godot --main-scene res://main.tscn
```

On macOS/Windows/iOS, or on Linux with only a USB webcam attached, this uses the built-in
`CameraServer` path with no extra setup. The native CSI extension only loads on Linux
(`addons/csi_camera/csi_camera.gdextension` restricts its library entries to
`linux.arm64`), so it is silently skipped everywhere else.

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