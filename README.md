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

**`Can't create an EGL context` / `MESA: error: Couldn't get V3D core IDENT0`**
This happens when launching over a remote/VNC session (e.g. `rpi-connect`/`wayvnc`) whose
compositor socket doesn't expose the real GPU the same way a local session does. As a
fallback, force software rendering:

```bash
LIBGL_ALWAYS_SOFTWARE=1 ./clankerUI.sh
```

Prefer testing on the Pi's local/attached display first; hardware-accelerated rendering should
work there without any extra environment variables.

**`arducam-pivariety.json not found` (or similar tuning-file warning) from `libcamera`**
Capture still works without it, but exposure/color may be suboptimal. Install the correct
tuning file for your sensor from your camera vendor's `libcamera` package, or ignore it if
image quality is acceptable.

**`gst-inspect-1.0 libcamerasrc` reports no such element**
`gstreamer1.0-libcamera` is not installed (see prerequisites above), or `GST_PLUGIN_PATH` is
overriding the system plugin search path. Run `gst-inspect-1.0 libcamerasrc` in a clean shell
(no `GST_PLUGIN_PATH`/`GST_PLUGIN_SYSTEM_PATH` set) to confirm.

**Camera works with `rpicam-hello` but the cube face stays on the fallback background**
Check the terminal log for `[csi_camera]`/`[webcam]` lines. A missing
`libcsi_camera.linux.arm64.so` or `csi_camera.gdextension` next to `clankerUI.arm64` is the
most common cause — re-check the deployment layout above.

## License

This project is licensed under the [MIT License](LICENSE).