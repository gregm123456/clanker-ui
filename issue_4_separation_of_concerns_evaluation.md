# Issue #4 Evaluation: Separation of Concerns and Parallel Feature Development

## Executive summary

Short answer: **partially, but not safely yet**.

- The project has a good foundational seam in the CSI camera provider (`addons/csi_camera/scripts/csi_camera_provider.gd`) and shader/material separation (`cube_shader.gdshader`).
- However, most runtime behavior is centralized in `spinning_cube.gd` (input handling, camera/feed setup, render-parameter updates, movement, and wraparound), so both requested features currently converge on the same file.
- As-is, building the two features in independent forks is possible, but merge conflict risk and logic coupling are high enough that **a small shared refactor first** is strongly recommended.

## Current separation-of-concerns status

### What is already separated reasonably well

1. **Rendering surface contract**
   - Webcam presentation is mostly expressed as shader parameters (`webcam_texture`, `webcam_mode`, `webcam_aspect`, fit/flip controls).
   - This is a useful contract for feature development because texture source and cube rendering are already somewhat decoupled.

2. **CSI hardware integration boundary**
   - `CsiCameraProvider` wraps CSI-specific behavior and exposes `start/stop/update/get_texture/get_aspect`.
   - This is a healthy abstraction and can be reused by future networking/camera topology work.

### Where concerns are currently mixed

1. **Single script orchestration hotspot (`spinning_cube.gd`)**
   - Handles user input/window mode, camera discovery, feed activation/retry policy, webcam datatype decisions, object movement, and wraparound.
   - Both new features will likely modify this script, increasing merge overlap.

2. **Movement model is 2D-in-3D-scene**
   - Position updates are only `x/y`; z is only used for rotation/camera distance calculations.
   - The movement assumptions are embedded directly in frame processing and wraparound logic.

3. **No multiplayer/network boundary yet**
   - No dedicated transport/synchronization component, state authority model, peer clock policy, or transform serialization layer.

4. **Limited test scaffolding for gameplay architecture changes**
   - Existing script-level test tooling focuses on CSI pipeline checks, not movement/network behavior.

## Can the two features be developed in separate forks and merged?

## Verdict

- **If done immediately without preparatory refactor:** high chance of painful conflicts and regressions.
- **If preceded by a small “seam creation” pass:** parallel development becomes realistic.

## Recommended approach

### Phase 0 (shared prep, short)
Create explicit interfaces/boundaries first, with minimal behavior change:

- Extract input/window toggles from `spinning_cube.gd` into a small controller.
- Extract movement/wraparound logic into a movement component with a transform API.
- Keep webcam source logic behind a camera-source adapter interface (current CSI provider + CameraServer path).
- Leave `spinning_cube.gd` as a thin scene coordinator.

After this, each feature can target mostly separate modules.

### Phase 1 (parallel forks)

- **Fork A (multiplayer mesh views):** networking, peer calibration, distributed camera offsets, shared-scene state sync.
- **Fork B (2D→3D movement):** movement model, z-aware constraints/wraparound, collision/interaction adaptations.

### Phase 2 (integration)

- Merge both into coordinator script and shared scene contracts.
- Run focused integration checks for camera offset correctness + movement synchronization behavior.

## Specific advice: Feature 1 (decentralized Raspberry Pi mesh “multiplayer” view wall)

1. **Define authority per data type before coding**
   - Example: calibration/origin data is operator-authoritative; object transforms may be single-owner or CRDT/event-driven.

2. **Do not couple networking directly to mesh node visuals**
   - Create a network sync service that emits typed signals/events.
   - Scene nodes subscribe; they do not parse packets.

3. **Create a calibration model resource**
   - Store per-node physical placement, orientation, viewport dimensions, and camera offset transforms in one explicit structure.

4. **Stabilize transform serialization early**
   - Use a versioned schema for position/rotation/time metadata to avoid protocol churn between forks.

5. **Plan for degraded/offline peers**
   - Nodes should continue rendering with last known shared state when peers drop.

6. **Keep the current CSI/video path independent from state sync**
   - Camera texture acquisition must remain local; synchronize scene state, not camera frames.

## Specific advice: Feature 2 (object movement from 2D to 3D)

1. **Move to a full `Vector3` velocity/acceleration model**
   - Keep a compatibility adapter for old 2D-style settings during transition.

2. **Separate motion integration from presentation**
   - A movement component updates transforms; rendering script only consumes transforms.

3. **Refactor wraparound/bounds as a strategy**
   - Current bounds are camera-relative x/y logic. Introduce pluggable bounds modes (none, 2D plane wrap, 3D volume wrap/clamp).

4. **Document world-axis conventions**
   - Explicitly define forward/up/right expectations and camera-relative vs world-relative movement rules.

5. **Design for future network determinism**
   - Use fixed-step movement update paths (or deterministic snapshots) to reduce divergence across mesh peers.

## General advice to development agents

1. **Touch the coordinator last**
   - Implement feature logic behind interfaces first, then wire into `spinning_cube.gd`.

2. **Adopt contract-first changes**
   - Define GDScript interfaces/resources/signals for movement, sync, and calibration before deep implementation.

3. **Minimize shared-file edits per PR**
   - Prefer new focused scripts over repeated edits to `spinning_cube.gd`.

4. **Use feature flags/exported toggles for staged rollout**
   - Keep old behavior selectable until both features are integrated.

5. **Require lightweight architecture checks in PRs**
   - Each PR should state: boundaries touched, interfaces added/changed, and merge-risk to the sibling feature branch.

## Prospects going forward

The project is **close to being parallel-feature friendly** because it is still small and has already introduced one useful abstraction (CSI provider). With one short boundary-focused refactor, separation of concerns can improve significantly and support robust independent workstreams for both requested features.

Without that refactor, development in tandem is safer in the short term—but it will likely slow delivery and increase regression risk as complexity grows.
