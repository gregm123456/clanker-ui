# Phase 4 handoff notes

## Status

Phase 4 remote proxy rendering is implemented in the current workspace and is ready for the Phase 5 snapshot-fetch agent.

The implementation follows the architecture described in `shared_space.md`: it listens to the shared `MeshSyncService`, filters out the local object, renders remote objects as lightweight proxy cubes, and tracks camera-frustum crossings so a snapshot fetch happens only on the rising edge from "outside" to "inside" the local view.

## Implemented file

- `scripts/remote_object_renderer.gd`
  - Connects to `MeshSyncService.shared_object_spawned`, `shared_object_transform_updated`, `shared_object_despawned`, and `peer_connection_changed`.
  - Ignores the local object id (`shared_object_id`) so the authoritative cube remains under scene control.
  - Creates a generic `MeshInstance3D` proxy with a `BoxMesh` and a duplicate `ShaderMaterial` when a foreign object spawns.
  - Updates the proxy `global_transform` from the networked position/rotation payloads.
  - Removes proxy nodes when remote peers go offline or when a despawn message arrives.
  - Uses `WallGeometryCalculator.frustum_size_at_distance()` in camera local space to detect when a proxy just crosses the local camera frustum.
  - Emits a `snapshot_requested(object_id, owner_peer_id)` signal for the next Phase 5 agent to consume.
  - Exposes `set_snapshot_request_callback(Callable)` as a non-signal hook for the Phase 5 implementation if a callback is easier than a direct signal connection.

## Scene wiring

`spinning_cube.gd` now instantiates and configures the renderer after the mesh sync controller has been configured and the bridge is attached:

- `RemoteObjectRenderer` is created as a child node.
- It is configured with the shared `MeshSyncService` returned by `SpinningCubeMeshSyncController.get_mesh_sync_service()`.
- It receives the local `shared_object_id` so it can ignore the authoritative object.
- It runs each frame in `_process()` so it can re-evaluate visibility crossing without adding transport logic to the scene.

## Phase 5 handoff target

The next agent should implement the one-shot snapshot fetch pipeline in the following order:

1. Connect a Phase 5 callback or signal listener to `RemoteObjectRenderer.snapshot_requested`.
2. Resolve the remote peer address via the existing peer config and `PeerAddressBook`.
3. Use a `WebcamSnapshotClient` to request a JPEG still from the owning peer.
4. Decode the returned image and apply it to the proxy's shader texture or fallback material path.
5. Keep the snapshot fetch to a single trigger per visibility crossing so it does not spam continuously while the object remains within frame.

## Phase 5-ready contract

The renderer intentionally does not fetch or decode images itself. That boundary is deliberate so the Phase 5 agent can own:

- the TCP still-image request/response protocol
- image decode and texture upload
- static image material setup
- any compatibility handling for new descriptor kinds or future object types

This keeps the rendering layer generic while leaving the snapshot provider as a separate concern.

## Validation status

Static VS Code diagnostics were checked after the implementation. The current workspace still lacks a Godot runtime on the Mac PATH, so a live scene test could not be executed in this environment. The implementation is therefore validated as syntax/editor-level correctness rather than a live Godot smoke test.

## Recommended smoke test for the next agent on a Mac with Godot installed

1. Run the project with distinct `--user-data-dir` values for two local instances.
2. Give each instance a unique `peer_id` and `this_node_column` value in the same wall layout.
3. Confirm that each instance receives remote spawn and transform updates from the other.
4. Confirm that a proxy cube appears for the other node's object.
5. Confirm that a snapshot request triggers once when the proxy enters the local camera frustum and not continuously while it remains visible.
6. Confirm that the proxy is removed when the peer times out or the object despawns.

The bridge and transport already deliver remote descriptors, transforms, and peer timeout notifications, so the Phase 5 agent can focus only on the snapshot fetch + texture application layer.
