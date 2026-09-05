## Plan: Arducam CSI Camera Integration

Integrate Raspberry Pi CSI capture into the existing Godot project as a Linux/arm64 GDExtension using GStreamer `libcamerasrc` and `appsink`, while preserving the current Godot `CameraServer` path for macOS and USB-camera fallback. Build the native extension on the Raspberry Pi first so it links against the Pi's installed GStreamer/libcamera stack, then deploy the extension alongside the existing Godot arm64 export.

**Steps**

1. **Lock the runtime contract and repository boundary**
   - Keep the extension source inside the current repository in an isolated `addons/csi_camera/` module; do not create a new repository.
   - Treat the existing shader contract as the integration boundary: the camera provider must deliver one ordinary RGB/RGBA `Texture2D` plus width/height or aspect metadata. Avoid feeding raw Bayer data or Pi-specific `/dev/video*` nodes to GDScript.
   - Runtime policy: on Linux/Raspberry Pi, try the native CSI provider first; if the extension is missing, cannot initialize, or loses the camera, retain the existing `CameraServer` USB fallback. On macOS, use only the existing `CameraServer` path.
   - First implementation target: Arducam IMX462 Pivariety on Raspberry Pi 5 / Raspberry Pi OS 64-bit, with a 960x540 or 1280x720 processed stream at 30 fps.

2. **Add the native extension skeleton**
   - Add `addons/csi_camera/csi_camera.gdextension` with Linux arm64 release/debug library entries and Godot 4.7 compatibility metadata.
   - Add native source/build files under `addons/csi_camera/src/` and a `CMakeLists.txt` or equivalent Pi build script. Use the matching Godot 4.7 `godot-cpp` headers/bindings and register one small class, such as `CsiCamera`, with methods for start, stop, poll/update, status, frame dimensions, and latest frame access.
   - Keep generated build output and downloaded bindings out of source control; add the needed patterns to `.gitignore`.
   - Make the extension load harmlessly when its Linux library is absent on macOS by keeping the `.gdextension` platform library declaration Linux-only and guarding GDScript access with class/extension availability checks.

3. **Implement the GStreamer/libcamera capture path in native code**
   - Build a pipeline equivalent to `libcamerasrc camera-name=... ! video/x-raw,width=960,height=540,framerate=30/1 ! videoconvert ! video/x-raw,format=RGBA ! appsink ...`.
   - Do not select `/dev/video0`, `/dev/video1`, or a numbered PiSP node directly. Let `libcamerasrc` discover and configure the Arducam sensor, CSI graph, PiSP ISP, and tuning pipeline.
   - Expose camera selection by libcamera camera identity/name if needed; default to the first available camera, with an optional camera-name property for `cam1` deployments. Do not confuse the physical connector label `cam1` with a V4L2 node number.
   - Configure `appsink` for live operation with `drop=true`, `max-buffers=1`, and synchronous/asynchronous settings that prevent stale frames from accumulating. Copy only the latest complete RGBA frame into a mutex-protected or double-buffered native frame store.
   - Ensure GStreamer bus errors, state transitions, EOS, missing plugins, and caps mismatches become readable status/error strings exposed to GDScript. Stop and tear down the pipeline deterministically in the destructor and on explicit stop.
   - Keep GStreamer callbacks off the Godot scene/render thread. On the Godot side, poll for a completed frame during `_process` and upload it to a Godot `ImageTexture` on the main thread.
   - Use a fixed, bounded frame buffer and avoid returning pointers into a GStreamer buffer after the sample is released. Validate stride, buffer size, dimensions, and pixel format before publishing a frame.

4. **Choose the simplest Godot frame-transfer API and prove it with a spike**
   - Prefer a native method that returns/copies the latest RGBA bytes into a Godot `PackedByteArray` or equivalent, then create/update an `Image` and `ImageTexture` in GDScript. This is less efficient than zero-copy but is much simpler and more portable for a single 960x540 cube texture; optimize only if profiling shows a problem.
   - Add a minimal native/GDScript smoke path before integrating with the cube: start capture, wait for a frame, verify nonzero dimensions and changing frame sequence/timestamps, stop capture, and report errors.
   - If the Godot binding cannot safely expose large per-frame byte arrays at the desired rate, replace only this transfer boundary with a native `ImageTexture`/RenderingServer upload path; keep the GStreamer pipeline and provider API unchanged.

5. **Add a GDScript camera-provider abstraction**
   - Add a small script such as `csi_camera_provider.gd` or `camera_source.gd` that owns source selection and exposes a unified state: inactive/starting/active/error, texture, aspect, and error text.
   - Implement the CSI provider wrapper around the native `CsiCamera` class and a separate adapter for the existing `CameraServer` implementation. Keep platform selection explicit: native CSI only on Linux when the extension class is available; CameraServer elsewhere or as fallback.
   - Update the provider each frame, update the `ImageTexture` only when a new native frame is available, and preserve the last valid frame during transient capture errors.
   - Ensure stopping/restarting releases `CameraTexture`, `ImageTexture`, native camera handles, and signal connections without leaving a camera pipeline running after scene exit.

6. **Refactor `spinning_cube.gd` to consume the provider**
   - Replace the current direct camera setup in `_setup_webcam`, `_activate_feed`, `_update_feed_mode`, and the retry logic with the provider selection/start/update lifecycle.
   - Preserve existing exported controls where they remain meaningful: `enable_webcam`, `webcam_feed_index` for USB fallback, `webcam_fit_mode`, `flip_webcam_horizontal`, fullscreen, cursor, movement, and wraparound.
   - Add narrowly scoped exported CSI settings only if needed, such as preferred width, height, fps, and optional libcamera camera name. Defaults should match the Arducam test path rather than expose every GStreamer option.
   - For CSI frames, always set shader `webcam_mode=1` (ordinary RGB/RGBA texture), set `webcam_texture` to the provider texture, clear or ignore the CbCr texture, and derive `webcam_aspect` from actual frame dimensions.
   - Retain the current macOS/iOS YCbCr handling and Linux USB CameraServer RGB handling in the fallback adapter. Keep the existing shader unchanged unless the native upload path requires a texture-format-specific change.
   - Add clear startup logs identifying the selected source, requested caps, negotiated dimensions/fps, and fallback reason. Avoid retry loops that repeatedly start a failed native pipeline faster than every few seconds.

7. **Wire the extension into the project and packaging**
   - Add the `.gdextension` resource to the project so it is included by the existing `export_filter="all_resources"` export.
   - Confirm the Linux arm64 shared library is located at the exact path referenced by the manifest and is executable/readable by the runtime user. Keep macOS from attempting to load a nonexistent Linux library.
   - Update `project.godot` only where necessary; retain the Linux GL Compatibility override because it addresses the existing Raspberry Pi Wayland/Vulkan presentation issue.
   - Update `clankerUI.sh` only if needed to set a library search path or diagnostic environment variables. Prefer system GStreamer libraries and avoid bundling Pi-specific shared libraries unless deployment testing proves the target image lacks them.
   - Add an optional `camera-diagnostics` command/script or a documented Godot diagnostic mode that prints extension availability, GStreamer plugin availability, negotiated caps, frame count, and last error.

8. **Create the Raspberry Pi build procedure**
   - Document the exact Pi prerequisites: 64-bit Raspberry Pi OS, working Arducam overlay `dtoverlay=arducam-pivariety,cam1`, `rpicam-hello` success, matching Godot 4.7 `godot-cpp` bindings, compiler/CMake/SCons, GStreamer development packages, `gstreamer1.0-libcamera`/`libcamerasrc` availability, and `v4l-utils` for diagnostics.
   - Build `godot-cpp` for `linuxbsd`, `arm64`, and the matching release/debug target on the Pi. Build the extension against those bindings and installed GStreamer headers/libraries.
   - Copy or install the resulting `.so` into `addons/csi_camera/bin/linux.arm64/` (or the manifest’s chosen runtime path), run Godot headless/editor import validation, then export the project to `clankerUI.arm64` and `clankerUI.pck`.
   - Provide a repeatable build script that fails on missing `pkg-config` modules, missing GStreamer `libcamerasrc`, wrong architecture, wrong Godot ABI, or absent output library.

9. **Validate in progressively broader stages**
   - Native unit/smoke validation: extension loads; `CsiCamera.start()` succeeds; first frame arrives; frame sequence advances; stop/restart works; GStreamer errors are surfaced.
   - Camera pipeline validation on `m5image`: `rpicam-hello -n -t 2000` or equivalent no-preview capture succeeds; `gst-inspect-1.0 libcamerasrc` succeeds; a standalone GStreamer test pipeline negotiates the requested RGB/RGBA caps and receives frames.
   - Godot validation on the Pi: run windowed first, verify the cube remains responsive, camera appears on five faces, no stale-frame buildup, correct aspect/flip/fit modes, clean Escape shutdown, and clean restart. Then verify fullscreen and the existing F11/Alt+Enter/M controls.
   - Fallback validation: temporarily hide/rename the extension library or stop the CSI source; verify the app reports the reason and still uses a USB V4L2 camera when present. On macOS, verify the existing CameraServer path remains functional and no Linux extension-load errors appear.
   - Performance validation: measure CPU usage, frame rate, and latency at 960x540 and 1280x720. Confirm bounded memory use and no GStreamer queue growth after at least 10 minutes.
   - Packaging validation: export a clean arm64 build, copy only the documented artifacts to a fresh Pi directory, run without the source checkout, and confirm all required shared libraries are resolved.

10. **Document end-to-end deployment and operations**
   - Expand `README.md` with the architecture, supported camera modes, exact Pi package installation, overlay/tuning-file notes, extension build commands, export commands, SCP/SSH deployment, permissions, and diagnostics.
   - Deployment flow: verify camera with `rpicam-hello`; build/install the extension on the Pi; export `clankerUI.arm64` and `clankerUI.pck`; copy them plus `clankerUI.sh` and the native `.so`/addon resources; `chmod +x` the launcher and binary; run `./clankerUI.sh`.
   - Include a systemd user/service example only after interactive execution works, with `After=graphical-session.target`, the correct `DISPLAY`/Wayland environment, working directory, restart policy, and log capture. Do not make systemd the first debugging path.
   - Document cleanup/shutdown, how to collect Godot/GStreamer logs, how to restore USB-only behavior, and how to update the extension and PCK together.

**Relevant files**
- `/Users/gregm/genai/clanker-ui/spinning_cube.gd` — replace direct camera ownership with the unified provider while preserving cube motion, shader setup, controls, and USB fallback behavior.
- `/Users/gregm/genai/clanker-ui/cube_shader.gdshader` — likely unchanged; retain its existing RGB/YCbCr uniforms and fit/flip behavior as the texture contract.
- `/Users/gregm/genai/clanker-ui/main.tscn` — update exported provider/camera properties only if the new wrapper exposes them in the scene.
- `/Users/gregm/genai/clanker-ui/project.godot` — retain renderer settings; add only required extension/resource configuration.
- `/Users/gregm/genai/clanker-ui/export_presets.cfg` — verify Linux arm64 export includes the addon and native library; leave existing separate PCK packaging unless testing requires a change.
- `/Users/gregm/genai/clanker-ui/clankerUI.sh` — preserve the launcher; optionally add diagnostics/library path handling if deployment requires it.
- `/Users/gregm/genai/clanker-ui/README.md` — replace USB-only compatibility claims with CSI-first/USB-fallback architecture and complete build/deployment instructions.
- `/Users/gregm/genai/clanker-ui/.gitignore` — ignore native build directories, downloaded `godot-cpp`, and generated binaries except intentionally packaged release artifacts.
- `/Users/gregm/genai/clanker-ui/addons/csi_camera/csi_camera.gdextension` — new Godot extension manifest.
- `/Users/gregm/genai/clanker-ui/addons/csi_camera/src/` — new registered native camera class, GStreamer pipeline, bounded latest-frame buffer, and entry point.
- `/Users/gregm/genai/clanker-ui/addons/csi_camera/scripts/` — new GDScript provider/adapter and optional diagnostic helper.
- `/Users/gregm/genai/clanker-ui/addons/csi_camera/bin/linux.arm64/` — generated/deployed arm64 shared library referenced by the manifest.
- `/Users/gregm/genai/clanker-ui/scripts/build_csi_camera_on_pi.sh` — new repeatable Pi-side dependency/build/install script.
- `/Users/gregm/genai/clanker-ui/scripts/test_csi_camera_pipeline.sh` — new standalone GStreamer/libcamera smoke test.

**Verification**
1. Run Godot project validation on macOS and confirm the current scene still loads, the cube renders, and a USB/native macOS camera remains usable.
2. On the Pi, verify the camera stack independently: `rpicam-hello -n -t 2000`, `gst-inspect-1.0 libcamerasrc`, and the documented standalone appsink pipeline at the chosen resolution.
3. Build the extension on the Pi and verify architecture/linkage with `file`, `ldd`, and `pkg-config` checks; load it from a minimal Godot smoke scene before touching the cube.
4. Run the full app on the Pi windowed, then fullscreen, and verify live frames, fit modes, mirroring, frame dimensions/aspect, retry/fallback, and clean shutdown/restart.
5. Export a clean Linux arm64 package, deploy to a fresh directory using only documented files, and run it without the development checkout.
6. Run a 10-minute soak test while monitoring frame rate, memory, CPU, and logs; confirm no unbounded queue or repeated pipeline restart.

**Decisions**
- Integrate into the current repository; do not create a new repository.
- Raspberry Pi runtime preference: Arducam CSI via libcamera/GStreamer first, current Godot CameraServer USB path second.
- macOS development: preserve existing CameraServer path; native CSI extension is Linux-only.
- First native build target: build on the Raspberry Pi rather than cross-compiling from macOS.
- Use libcamera/GStreamer camera discovery and configuration; never bind application logic to `/dev/video0`, `/dev/video1`, or PiSP node numbering.
- Prefer a simple latest-frame RGBA copy into Godot before attempting zero-copy GPU integration.
- Keep the current renderer/export approach and existing shader unless an executable test demonstrates a necessary change.

**Further Considerations**
1. Before implementation, confirm the exact package name and availability of `libcamerasrc` on the target Raspberry Pi OS image; package names differ across Raspberry Pi OS releases. The build script should discover this via `pkg-config`/`gst-inspect`, not assume one package name.
2. Confirm whether the Arducam tuning file is installed on the Pi. Missing `arducam-pivariety.json` did not prevent capture, but it should be fixed separately for image quality and documented as a camera-stack prerequisite.
3. If the extension’s frame-copy path consumes too much CPU at the chosen resolution, optimize only after profiling; do not begin with zero-copy complexity.
