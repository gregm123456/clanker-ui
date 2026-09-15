# Phase 1 handoff notes

## Implemented

This repo now includes the Phase 1 config foundation:

- `scripts/installation_config.gd` loads and validates `user://installation.cfg`
- A `res://config/installation.template.cfg` template is copied into the user data dir on first launch if missing
- `spinning_cube.gd` loads the config before its component setup and applies config overrides to mesh identity and webcam settings
- `README.md` documents the config file layout and the requirement that the wall geometry must match across all nodes

Important: when using Godot's `ConfigFile`, string values must be quoted in the `.cfg` file. This is required for values like `node_id = "local_display"` and `peer_id = "local"` to parse correctly on the local Mac toolchain.

## User config path

On first run, the app writes a template to:

- `user://installation.cfg`

The resolved absolute path is logged at startup using:

- `ProjectSettings.globalize_path("user://installation.cfg")`

## Current runtime behavior

The config values override the scene defaults only when they are present and valid:

- `mesh_node_id`
- `mesh_peer_id`
- `webcam_feed_index`
- `prefer_csi_camera`
- `csi_camera_width`
- `csi_camera_height`
- `csi_camera_fps`
- `csi_camera_name`
- `webcam_fit_mode`
- `flip_webcam_horizontal`

The scene-exported values remain as the fallback defaults if the config file is absent or a setting is blank.

## Next handoff target for Phase 2

The agent doing Phase 2 should continue from this baseline and implement:

1. wall geometry math and per-node camera offset calculation
2. 3D wall bounds configuration
3. shared network bridge and UDP transport
4. remote proxy rendering and snapshot fetching

The Phase 2 agent should treat the config contract as the source of truth for node identity, peer addresses, wall geometry, and camera settings.
