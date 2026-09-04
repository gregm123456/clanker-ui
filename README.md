# clankerUI

A Godot 4 project featuring a spinning, shader-driven 3D cube interface with live webcam feed texture mapping.

## Features & Hardware Compatibility

- **Raspberry Pi 5 & Single Board Computers**: Runs in full screen using Vulkan (Mobile) or OpenGL ES (GL Compatibility) rendering.
- **Display Adaptability**: Dynamically adapts to any display size, resolution, and orientation (landscape, portrait, ultrawide, square) connected to the Raspberry Pi.
- **USB Camera Support**: Automatically detects and displays live video feeds from standard USB cameras connected via Video4Linux2 (V4L2) on Linux / Raspberry Pi, as well as native feeds on macOS/Windows/iOS.
- **Controls**:
  - `F11` or `Alt + Enter`: Toggle Full Screen / Windowed mode.
  - `Escape`: Quit application.

## Run

Open the project in Godot 4.7 or later, then run `main.tscn`.

```bash
godot --main-scene res://main.tscn
```

## License

This project is licensed under the [MIT License](LICENSE).