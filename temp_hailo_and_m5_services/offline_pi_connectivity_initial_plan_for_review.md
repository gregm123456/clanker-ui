# Resilient Pi-to-Pi connectivity

## Problem and approach

The Ethernet connection works without Wi-Fi, but the deployed Godot peers currently use Tailscale hostnames, and a successful DNS lookup does not prove that the resulting route works. Prefer Tailscale, then mDNS `.local`, then reserved Ethernet addresses. Make path selection responsive to actual connectivity, keep retrying indefinitely, and stay on a working fallback until it fails. Preserve the existing single-endpoint configuration and normal behavior for installations that do not opt in.

The direct Ethernet fallback carries the existing unencrypted, unauthenticated mesh UDP, snapshot TCP, and face HTTP traffic; it is intended only for the trusted, directly connected link. The user has accepted this trade-off.

## Todos

### 1. Design and configure resilient endpoints

- Extend `config/installation.template.cfg`, `scripts/installation_config.gd`, and the default template to accept an ordered list of peer endpoints and face-service endpoints, without changing the meaning of existing single-value entries or broadcast mode. Validate malformed entries and clearly report configuration errors.
- Configure the two deployments with explicit ordered candidates: the peer's Tailscale name, its `.local` name, then its stable Ethernet address. Configure the remote face client on m5image similarly. Preserve pi5ai2sd's existing local/loopback path to its own face service.
- Use a persistent NetworkManager-supported DHCP reservation for m5image on pi5ai2sd, rather than a static client address. First inspect the installed NetworkManager/dnsmasq mechanism and DHCP pool, choose and document a conflict-free address, and ensure the reservation survives restarts and does not change the existing shared Ethernet address of pi5ai2sd. Do not assume the current dynamically assigned `192.168.77.46` is permanently reserved.
- Plan safe deployment: back up and inspect the relevant user and network configuration; integrate existing changes; determine activation/rollback and SSH impact before applying. Do not restart networking, disconnect Wi-Fi, or reboot. If activation or verification requires it, stop and request the user's assistance.

### 2. Add bounded, responsive path selection

- Rework `scripts/peer_address_book.gd`, `scripts/udp_mesh_transport.gd`, and `scripts/mesh_network_bridge.gd` to resolve candidates asynchronously and track path-level reachability rather than treating DNS or UDP send success as peer health. Account for the fact that traffic from a peer arriving on one path does not prove a different outbound path works.
- Implement an explicit, correlated two-way peer probe/ack for each candidate, using source endpoint and peer identity to associate replies with the candidate. Keep ordinary messages and peer IDs compatible with existing clients; define and test how a mixed-version peer behaves without misclassifying it as unreachable. Avoid simultaneous full-state delivery on multiple paths and preserve recovery/replay of object state.
- Target at most **3 seconds on an unresponsive preferred candidate**, including name resolution and peer probing, then move to the next candidate; test this with controlled time. Apply similarly bounded candidate attempts, without blocking Godot's frame loop. Explicitly surface the distinction between DNS failure, transport timeout and protocol failure.
- Once a candidate works, keep using it while healthy. On loss, try candidates in preference order, with Tailscale first; if none works, keep cycling forever with a bounded delay/backoff that avoids flooding. Re-resolve failed names and expire stale cached addresses. Preserve the existing peer-offline behavior and make reconnection/state replay reliable. Log path transitions and repeated failures in a rate-limited, actionable way.

### 3. Cover snapshots and face requests

- Update `scripts/webcam_snapshot_client.gd` and wiring in `spinning_cube.gd` so remote snapshots use validated peer paths and promptly try other candidates on connection failures. Do not mark the network path bad solely because a camera has no frame or a JPEG is invalid; preserve request deduplication, size limits, and existing visible-portrait retry behavior.
- Update `scripts/face_attribute_client.gd` and its wiring to select configured face-service paths independently based on actual HTTP reachability. Fall back quickly on resolution/connection failures, not ordinary service errors, inference latency, or invalid results. Keep image encoding and request counts bounded, never accumulate an unbounded queue, and log failures. Define and test safe retry behavior for a POST whose outcome is ambiguous; avoid blindly duplicating inference or emitting duplicate face results.
- Background connectivity retries continue indefinitely, but individual snapshots and face images remain bounded and may fail or be dropped according to existing UI semantics. A future request can succeed when connectivity returns.

### 4. Test and document

- Add focused deterministic tests for configuration compatibility and invalid input; preferred-path success, timeouts, next-candidate selection, indefinitely repeated retry cycles, stable fallback, re-resolution after DHCP changes, one-way/stale-path failures, and peer restart/replay. Include mixed-version behavior, event deduplication, and independent snapshot/HTTP failure cases.
- Simulate DNS failures, blackholed endpoints, and lost replies with controlled local test doubles; assert the 3-second preferred-path bound, no frame-loop blocking, and bounded request/queue behavior. Run the existing relevant Godot headless tests and face/peer regression tests.
- Document endpoint configuration, DHCP reservation and rollback, trust implications, path logs, startup-order considerations, and operational checks in `README.md`. Distinguish simulated tests and current online checks from real offline evidence.

### 5. Deploy and verify safely

- Before deployment, inspect current repository and live host state, preserve concurrent work, and verify both Pis' application builds and config match the intended version. Apply only scoped changes, using backups and a documented rollback path; ensure the current remote management path remains available.
- Verify nondisruptively that the reservation is configured and active when safely possible, `.local` resolves both ways, the fallback addresses and ports work, the services respond, and the Godot clients exchange state and snapshots. Verify face inference if an appropriate test image and the existing service are available.
- For actual loss of internet, offline cold boot, DHCP renewal/reassignment, and full outage/recovery tests, provide the user a precise manual procedure and request their assistance separately. Do not disconnect networks or reboot remotely. Record any unverified cases instead of claiming offline readiness. Include recovery instructions if remote access becomes unavailable.

## Notes

- Baseline: pi5ai2sd has Ethernet `192.168.77.1/24` with NetworkManager shared mode and DHCP; m5image currently has DHCP address `192.168.77.46/24`. Both deployed clients currently use Tailscale-resolved unicast names and share UDP 9000 and TCP 9010; the face service is on pi5ai2sd port 5002.
- Tailscale can continue an established direct connection during an outage, but a working DNS lookup or prior connection is not proof of offline reboot/recovery. Do not assume its control plane or DERP is reachable.
- Preserve existing configuration, client compatibility, camera behavior, and unrelated changes. Audit other AI-service clients for cross-host dependencies; do not reconfigure unrelated services without a demonstrated dependency.
