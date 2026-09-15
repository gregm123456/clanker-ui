# Phase 3 handoff notes

## Status

Phase 3 UDP mesh networking is implemented in the current workspace and ready for the Phase 4
remote-object-rendering agent. The implementation is intended to run on the Mac during
development and on the exported Raspberry Pi build without scene-specific transport code.

## Implemented files

- `scripts/peer_address_book.gd`
  - Parses the typed peer dictionaries produced by `InstallationConfig.get_peers()`.
  - Resolves IPv4 literals immediately and hostnames lazily with `IP.resolve_hostname()`.
  - Caches successful results and backs off failed resolutions for two seconds so unavailable
    Tailscale/LAN names are retried without logging once per transform frame.
  - Exposes resolved `peer_id`, original `host`, IPv4 `address`, and `port` dictionaries.
- `scripts/udp_mesh_transport.gd`
  - Binds `PacketPeerUDP` to `network.udp_port` and enables broadcast sending.
  - Supports `broadcast`, `unicast`, and `both` modes.
  - Sends one JSON packet to the broadcast address and/or each resolved configured peer.
  - Polls packets in `_process`, validates the protocol version, message type, sender, and
    dictionary payload, then emits `message_received(Dictionary)`.
  - Drops malformed or unsupported packets without throwing from the receive loop.
- `scripts/mesh_network_bridge.gd`
  - Owns the transport and connects it to one `MeshSyncService` instance.
  - Sends local calibration, spawn, transform, and despawn envelopes through explicit methods.
  - Applies remote messages while `_applying_remote` is set, preventing future bridge send
    hooks from echoing network state.
  - Tracks traffic from every remote peer, emits online state through `MeshSyncService`, sends
    periodic heartbeats, and marks silent peers offline after `peer_timeout_sec`.
- `scripts/spinning_cube_mesh_sync_controller.gd`
  - Added `get_mesh_sync_service()` and `attach_network_bridge()`.
  - Local publish points forward their already-normalized payloads to the bridge.
  - Bridge attachment replays the local descriptor, calibration, and current transform once.
- `spinning_cube.gd`
  - Creates/configures the bridge after the existing mesh-sync controller is configured.
  - Passes network settings, peer entries, and the configured local `peer_id` from
    `InstallationConfig`.
  - Shuts down the bridge during scene exit.
- `scripts/mesh_calibration_model.gd`
  - Calibration dictionaries now use JSON-safe arrays for vectors and quaternion rotation.
  - Added `from_dictionary()` for remote calibration application.

## Wire contract

Every UDP packet has this shape:

```json
{
  "version": 1,
  "type": "transform | calibration | spawn | despawn | heartbeat",
  "sender_peer_id": "pi-north",
  "payload": {}
}
```

`transform` payloads are produced by `TransformSyncSchema.serialize_transform()` and include
their own schema version, object id, owner peer id, timestamp, position array, and rotation
array. `calibration` payloads are produced by `MeshCalibrationModel.to_dictionary()`. `spawn`
payloads contain the normalized descriptor plus `object_id` and `owner_peer_id`; `despawn`
payloads contain only `object_id`; heartbeat payloads are empty dictionaries.

The bridge ignores packets whose sender is the local peer. It stamps a missing remote transform
owner with the envelope sender before handing the payload to `MeshSyncService`. It does not
instantiate nodes or make material decisions. That boundary is deliberate: Phase 4 should
listen to the service signals and render remote objects independently of UDP details.

## Configuration for local Mac testing

Use separate Godot `--user-data-dir` values for each instance so each process gets a distinct
`user://installation.cfg`. For two local instances, use different `peer_id` values and configure
each peer in `[peers]` with the other instance's host and UDP port. Set `network.mode = "unicast"`
to avoid relying on loopback broadcast, or use `both` to exercise both paths. The UDP port must
be available to both instances only when using separate ports; unicast peer entries may point at
the corresponding port.

## Validation

VS Code diagnostics pass for all changed GDScript files. A live Godot runtime check could not be
run in this Mac workspace because neither `godot` nor `godot4` is installed on `PATH`. Before a
hardware or two-instance smoke test, run:

```bash
scripts/refresh_godot_class_cache.sh
```

Then verify startup logs show UDP binding, send two instances' heartbeats/transforms, and confirm
peer timeout changes arrive through `MeshSyncService.peer_connection_changed` when one process
is stopped.

## Phase 4 starting point

The next agent should add `scripts/remote_object_renderer.gd` and attach it to the same
`MeshSyncService` returned by `SpinningCubeMeshSyncController.get_mesh_sync_service()`. It should
listen to `shared_object_spawned`, `shared_object_transform_updated`,
`shared_object_despawned`, and `peer_connection_changed`, ignore the local
`shared_object_id`, and use the existing wall geometry for visibility-crossing logic. The Phase 3
bridge already delivers remote descriptors and transforms and reports stale peers offline; no
transport changes are required for normal proxy rendering.

Do not move wall calibration or scene rendering into the network scripts. The bridge's only
responsibilities are transport, normalization boundary, peer presence, and forwarding typed
service updates.