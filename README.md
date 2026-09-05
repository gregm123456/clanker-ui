# clankerUI

A Godot 4 project featuring a spinning, shader-driven 3D cube interface with live webcam feed texture mapping.

## Features & Hardware Compatibility

- **Raspberry Pi 5 & Single Board Computers**: Runs in full screen using Vulkan (Mobile) or OpenGL ES (GL Compatibility) rendering.
- **Display Adaptability**: Dynamically adapts to any display size, resolution, and orientation (landscape, portrait, ultrawide, square) connected to the Raspberry Pi.
- **USB Camera Support**: Automatically detects and displays live video feeds from standard USB cameras connected via Video4Linux2 (V4L2) on Linux / Raspberry Pi, as well as native feeds on macOS/Windows/iOS.
- **Controls**:
  - `F11` or `Alt + Enter`: Toggle Full Screen / Windowed mode.
  - `M`: Toggle mouse pointer visibility.
  - `Escape`: Quit application.

## Run

Open the project in Godot 4.7 or later, then run `main.tscn`.

```bash
godot --main-scene res://main.tscn
```

### Standalone on Raspberry Pi

Export a Linux/arm64 build from the Godot editor (Project → Export), copy the resulting
`clankerUI.arm64` + `clankerUI.pck` to the Pi, `chmod +x clankerUI.arm64`, then run it.

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
`clankerUI.sh` needed after each export. Just run `./clankerUI.sh` or `./clankerUI.arm64`
directly on the Pi.

## License

This project is licensed under the [MIT License](LICENSE).