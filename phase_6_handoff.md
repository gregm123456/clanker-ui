# Phase 6 handoff notes

## Status

Phase 6 multi-client documentation and renderer compatibility handling are implemented. The
changes are static/editor-oriented and were made on the Mac; a live two-process mesh test still
requires a Godot runtime and reachable camera/network peers.

## Completed

- `scripts/udp_mesh_transport.gd` now documents the versioned UTF-8 JSON envelope, message types,
  payload contracts, identity rules, and malformed-packet behavior for non-Godot clients.
- `scripts/webcam_snapshot_server.gd` now documents the complete non-HTTP TCP snapshot protocol,
  little-endian length prefix, 20 MiB limit, connection lifecycle, and failure behavior.
- `scripts/remote_object_renderer.gd` explicitly treats `mesh_instance` as the supported kind and
  logs unknown kinds while rendering them as a generic box proxy. Invalid, non-finite, or
  non-positive remote dimensions use the neutral fallback size instead of producing an invalid
  mesh.
- `README.md` documents the stable UDP/TCP contracts, default ports, the distinction between UDP
  peer ports and TCP snapshot ports, and the existing requirement that wall geometry match across
  all nodes.

## Validation

- `git diff --check` should be run before handoff.
- Godot static diagnostics should be run for the touched GDScript files when a Godot editor is
  available.
- A live two-instance test, fragmented TCP response test, timeout test, and camera smoke test are
  still required on the target runtime/hardware as described in `phase_5_handoff.md`.