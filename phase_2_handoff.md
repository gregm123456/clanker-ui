# Phase 2 handoff notes

## Status

Phase 2 is implemented in the current workspace and is ready for the Phase 3 networking agent to continue from.

The core work completed here is:

- shared wall geometry math now lives in `scripts/wall_geometry_calculator.gd`
- the per-node camera offset is computed from the wall layout config
- the shared 3D wall bounds are applied before mesh sync calibration emits
- the existing 2D viewport wrap math was refactored to use the same frustum helper as the new wall calculator

## Code changes

### `scripts/wall_geometry_calculator.gd`

This is the new pure utility used for the wall-aware calibration math.

It implements:

- `frustum_size_at_distance(camera: Camera3D, distance: float) -> Vector2`
- `compute_world_units_per_mm(camera: Camera3D, monitor_width_mm: float) -> float`
- `compute_node_camera_offset(wall_layout: Dictionary, world_units_per_mm: float) -> Vector3`
- `compute_wall_world_bounds(wall_layout: Dictionary, world_units_per_mm: float) -> Dictionary`

These functions compute:

- the camera frustum width/height from the active camera FOV or orthographic size
- the conversion factor from millimeters to world units for the current display
- the offset of this node inside the shared wall coordinate space
- the full wall bounds volume used for 3D wrap/clamp logic

### `spinning_cube.gd`

At startup, the scene now:

1. loads `InstallationConfig`
2. reads the wall config (`columns`, `rows`, `monitor_width_mm`, `monitor_height_mm`, `gap_mm`, `this_node_column`, `this_node_row`)
3. computes world-unit scaling from the active camera and monitor width
4. computes this node's camera offset inside the wall
5. computes the total wall bounds
6. writes the computed values into `installation_geometry` and the runtime bounds fields
7. forces the wall scenario onto 3D volume wrap mode (`bounds_mode = 2`, `bounds_behavior = 0`)
8. seeds `calibration_model.physical_position` before the mesh sync controller configures the camera

This means the existing calibration path already used by `SpinningCubeMeshSyncController` now receives the real node placement data without needing a custom phase-2-only hook.

### `scripts/spinning_cube_bounds_strategy.gd`

The 2D viewport wrap math now delegates to the shared `WallGeometryCalculator.frustum_size_at_distance()` implementation instead of duplicating its own frustum logic.

This keeps the viewport and wall calculations consistent and reduces the chance that they diverge later.

## Wall math summary

The wall offset and bounds are derived from the shared layout:

- `columns` and `rows` define the wall grid
- `monitor_width_mm` and `monitor_height_mm` define each panel size
- `gap_mm` defines the gap between adjacent columns/rows
- `this_node_column` and `this_node_row` determine this node's anchor inside the combined wall

The offset is computed as:

- x offset = (this_node_column - (columns - 1) / 2) * (monitor_width_mm + gap_mm)
- y offset = (this_node_row - (rows - 1) / 2) * (monitor_height_mm + gap_mm)
- then converted from mm into world units using the camera frustum math

The wall bounds are sized from the total width/height of all columns/rows combined and are centered at the origin.

## Validation status

### Static validation

VS Code diagnostics for the changed files report no errors:

- `spinning_cube.gd`
- `scripts/spinning_cube_bounds_strategy.gd`
- `scripts/wall_geometry_calculator.gd`

### Runtime validation

A headless Godot launch was attempted from this macOS workspace, but there is no Godot binary on the current PATH in this environment:

- `which godot` -> not found
- `which godot4` -> not found

So the code was validated syntactically via editor diagnostics, but not executed in a live Godot runtime on this machine.

## Phase 3 handoff target

The next agent should continue from here and implement the actual network transport layer, which is the next dependency after the wall geometry foundation.

The Phase 3 target is to build the transport + bridge stack described in `shared_space.md`:

1. `scripts/peer_address_book.gd`
   - parse `[peers]` entries from the config
   - resolve hostnames / Tailscale names lazily
   - cache results and retry when name resolution is temporarily unavailable

2. `scripts/udp_mesh_transport.gd`
   - bind `PacketPeerUDP`
   - support broadcast and unicast
   - send JSON-safe envelope messages
   - decode inbound packets and emit `message_received(dict)`
   - validate schema version and packet shape without crashing on malformed data

3. `scripts/mesh_network_bridge.gd`
   - attach to `MeshSyncService`
   - re-send outbound local updates from the existing publish points in `SpinningCubeMeshSyncController`
   - suppress network echo loops with a local guard
   - track peer presence / heartbeat timeout

4. `scripts/spinning_cube_mesh_sync_controller.gd`
   - add a `get_mesh_sync_service()` getter if needed by the bridge
   - ensure outbound `publish_*` calls can be forwarded to the network bridge in explicit local-send paths

5. `scripts/remote_object_renderer.gd` and snapshot pipeline
   - this is the Phase 4 layer, but the Phase 3 agent should leave the architecture ready for it by making the mesh sync / transport bridge and peer presence logic operational

## Important implementation notes for the Phase 3 agent

- treat `InstallationConfig` as the source of truth for node identity, peer addresses, and wall geometry
- keep wall layout math and calibration in `WallGeometryCalculator` rather than duplicating it in the networking layer
- the wall geometry is intentionally shared across all nodes, so Phase 3 should assume that each node has already computed the same world-space layout
- the transport schema is expected to be generic, not `SpinningCube`-specific, and should remain compatible with `TransformSyncSchema` and `MeshCalibrationModel` dictionaries

## Recommended next command on a Mac with Godot installed

Run the project in Godot from the repo root with a user-data override for two local instances if you want to smoke-test the wall calibration before networking:

```bash
GODOT_BIN=/Applications/Godot/Godot.app/Contents/MacOS/Godot
"$GODOT_BIN" --path . --main-scene res://main.tscn
```

For two-instance local tests, launch one instance with a separate `--user-data-dir` and distinct `this_node_column` / `node_id` values to confirm the per-node offset and wall bounds match the same shared installation geometry.
