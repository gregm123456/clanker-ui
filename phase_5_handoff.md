# Phase 5 handoff notes

## Status

Phase 5 one-shot webcam snapshot fetch is implemented in the current workspace. The Mac
implementation is editor/static-diagnostics validated; a live Godot scene and camera smoke test
still require a Godot runtime and camera hardware.

## Implemented files

- `scripts/webcam_snapshot_server.gd`
  - Listens on `network.snapshot_tcp_port`.
  - Polls `TCPServer` and accepted `StreamPeerTCP` connections without blocking the render loop.
  - Accepts the one-line request `GET /snapshot`.
  - Captures `CameraSourceAdapter.get_current_frame_image()` and encodes a JPEG.
  - Sends a little-endian 4-byte length followed by the JPEG bytes, then closes the connection.
  - Rejects malformed requests, unavailable frames, oversized JPEGs, and stale connections.
- `scripts/webcam_snapshot_client.gd`
  - Resolves the owning peer through `PeerAddressBook`.
  - Connects to the configured snapshot TCP port with a polled state machine.
  - Handles fragmented headers and JPEG bodies, validates a 20 MiB size limit, decodes JPEG data,
    and emits an `ImageTexture` through `snapshot_received`.
  - Deduplicates requests by object id and times out failed requests.
- `scripts/camera_source_adapter.gd`
  - Defines the generic `get_current_frame_image()` hook.
- `scripts/webcam_camera_source_adapter.gd`
  - Returns a CPU-readable `CameraFeed` image or the latest CSI image.
- `addons/csi_camera/scripts/csi_camera_provider.gd`
  - Retains the latest CSI `Image` alongside the GPU texture and exposes it for snapshots.
- `scripts/remote_object_renderer.gd`
  - Applies a completed `ImageTexture` to the proxy shader using the existing static-image path.
- `spinning_cube.gd`
  - Creates the snapshot server and client, configures them from installation settings, connects
    the renderer callback, and logs failed fetches.

## Runtime contract

The renderer emits `snapshot_requested(object_id, owner_peer_id)` only on a rising edge from
outside to inside the local camera frustum. `spinning_cube.gd` forwards that request to the
client. On success, the client emits `snapshot_received(object_id, owner_peer_id, texture)` and
the renderer applies the texture with `webcam_mode = 1`. There is no continuous remote video
stream and no snapshot retry loop while the proxy remains visible.

The TCP protocol is intentionally small and independent of the SpinningCube scene:

1. Client sends UTF-8 `GET /snapshot\\n`.
2. Server sends a little-endian uint32 JPEG length.
3. Server sends exactly that many JPEG bytes and closes.

## Validation completed

Static diagnostics report no errors for every Phase 5 file and all touched integration files. The
workspace does not currently have Godot on the Mac PATH, so no live two-process or TCP integration
smoke test was possible here.

## Recommended Phase 6 checks

1. Refresh the Godot global class cache before launching after the new `class_name` scripts are pulled.
2. Run two instances with distinct `user://` directories, peer ids, UDP ports if needed, and
   snapshot TCP ports. Confirm a remote proxy requests one snapshot on frustum entry.
3. Confirm the returned still appears on the proxy and a second request occurs only after the proxy
   leaves and re-enters the frustum.
4. Test a server with no camera frame, a refused TCP connection, a fragmented response, and a
   timeout. Each failure should leave the proxy rendered with its fallback or previous texture.
5. Test the CSI provider on Pi hardware and the `CameraFeed` path on macOS/USB camera hardware.
6. Confirm all nodes use matching wall geometry and that their snapshot ports are reachable through
   the configured LAN or Tailscale addresses.
