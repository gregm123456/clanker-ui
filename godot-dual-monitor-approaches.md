# Godot across two monitors: the two strategies

This document is written for the coding agents who will adapt Greg's existing 3D Godot code. It covers two strategies separately and in detail:

- **Strategy 1:** one Raspberry Pi 5 driving both screens as a single wide window.
- **Strategy 2:** two Raspberry Pis, one per screen, each rendering its half of one shared virtual image.

Greg already has code that runs 3D Godot scenes on Raspberry Pis. Neither strategy asks for a rewrite of the scene itself. Strategy 1 changes how the window is created. Strategy 2 changes how the camera is configured, plus how the two machines stay in step. The bezel between the screens is treated explicitly in both.

## Known setup

These facts are fixed and both strategies assume them:

| Item | Value |
| --- | --- |
| Engine | Godot 4.0.4 |
| Computer | Raspberry Pi 5 (Strategy 2 adds a second Pi) |
| Monitors | Two identical monitors, side by side |
| Orientation | Both portrait; one is rotated 180° relative to the other |
| Current state | App was built for one monitor and launched fullscreen; it now appears on only one of the two screens |
| Scene type | 3D, with perspective. Depth lining up across the split is the main concern |
| Timing | Frame-exact synchronisation between screens is a lesser concern; the eye is lenient about it |

Anything not in this table that the code needs — starting with the panel resolution — is listed under [Open questions](#open-questions-to-settle-before-coding) at the end. Do not guess those values into the code; read them from a shared configuration file so they can be filled in once measured.

## The shared geometry: one virtual image and a missing slice

Picture the two panels as one wide image with a thin vertical strip cut out of the middle. The cut-out strip is the combined bezel width where the two monitors meet: the physical frame on the right edge of the left panel, plus the frame on the left edge of the right panel, plus any air gap between them. Call its width `bezel_gap_mm`.

Nothing is ever drawn in that strip, in either strategy. An object travelling across the pair disappears behind the bezel for the width of the strip and reappears on the other panel, exactly as an object passes behind a real window frame. That is the behaviour Greg wants: the bezel reads as a frame, not as a seam where the image was torn and rejoined.

Convert the physical gap into image units once, and both strategies use the same number:

```text
gap_px = bezel_gap_mm / panel_width_mm * panel_px_width
total_virtual_width_px = panel_px_width + gap_px + panel_px_width
```

where `panel_px_width` is the panel's horizontal resolution in its portrait orientation and `panel_width_mm` is the width of the visible panel area in that same orientation. The left panel shows the first `panel_px_width` columns of the virtual image, the right panel shows the last `panel_px_width` columns, and the middle `gap_px` columns are shown nowhere.

If the gap is ignored (`gap_px = 0`), straight lines still meet at the seam, but the geometry is wrong in a subtler way: an object crossing the split jumps sideways by the bezel width, and in 3D the perspective on the two sides disagrees about where things are. With the gap included, a straight edge crossing both panels stays straight in the room, and near and far objects keep consistent parallax across the split.

## Strategy 1: one Pi, two screens

### Why the current build only fills one screen

Godot's fullscreen mode is per-monitor by design. A fullscreen window takes over the one monitor it sits on; there is no Godot setting that makes fullscreen cover two monitors, because the engine asks the operating system for one display at a time. This is not a bug in Greg's project and cannot be fixed inside the fullscreen path.

The way to span both screens is the opposite move: give up fullscreen, and use one ordinary window that happens to be exactly as large as the two screens combined, with no borders or title bar, positioned so its left half lands on the left monitor and its right half on the right monitor.

### The hard requirement: X11, not Wayland

A window can only stretch across two monitors if the display server lets an application position and size a window freely across the whole extended desktop. On Raspberry Pi OS that is true under X11 and not under Wayland:

- Raspberry Pi OS currently defaults to Wayland with the labwc compositor. Under Wayland, applications cannot set their own absolute window position, and the compositor will keep a window inside one output. A borderless window sized to the combined desktop gets clamped or confined to a single screen.
- Under X11, the window manager allows the spanning window, and the approach works.

Switch the Pi before touching any code:

1. Run `sudo raspi-config` and choose **Advanced Options → Wayland → W1 X11** (Openbox window manager with the X11 backend), then reboot.
2. After reboot, verify with `echo $XDG_SESSION_TYPE`. It must print `x11`. If it prints `wayland`, the switch did not take and nothing below will work.
3. Arrange the desktop in the screen configuration tool: the two outputs side by side, both portrait, with the 180°-rotated monitor set to its upright rotation, so the extended desktop is one rectangle with no overlap and no offset between the top edges.

Staying on X11 is a real cost of this strategy. It moves the Pi off the OS default, and anything else on that Pi that depends on the Wayland session (some remote-desktop and screen-sharing tools behave differently) has to be re-checked under X11.

### Why booting to init 3 does not help

Greg asked whether booting the Pi to a non-graphical runlevel (init 3 / multi-user target) would let Godot connect to the monitor pair more directly, as one continuous device. It would not, for this build:

- A standard Godot 4.0.4 Linux build opens its window through a display server — X11 or Wayland. With no graphical session running there is no display server to open a window on, and the engine can only run with `--headless`, which renders nothing to a screen.
- The spanning behaviour Greg wants is a property of the display server and window manager, not of Godot talking to the hardware. Removing the display server removes the mechanism that creates the extended desktop in the first place.
- Driving the two HDMI outputs as one surface without X11 would mean a custom engine build or a separate direct-rendering (DRM/KMS) compositor of your own. That is a different project, not a configuration change, and it is out of scope for adapting the existing code.

Short version for the agents: do not pursue the console-boot route. The display server is the tool here, and X11 is the one that does the job.

### Project and window changes

In Project Settings, the window must stop asking for fullscreen:

- Set the window mode to **Windowed**, not Fullscreen or Exclusive Fullscreen.
- Set **Borderless** on.
- Keep the stretch configuration consistent with the existing project; the window will now be the size of the combined desktop, so confirm the viewport's base size and stretch mode still produce the intended rendering at that size rather than at the old single-monitor size.

Then size and place the window from code at startup, computed from what the OS reports rather than hard-coded, so a resolution change does not silently break the layout:

```gdscript
# Runs once at startup, before the scene becomes visible.
# Requires an X11 session; under Wayland the position call is ignored
# and the size may be clamped to one screen.
func span_all_screens() -> void:
    var union := Rect2i()
    for i in DisplayServer.get_screen_count():
        var rect := Rect2i(
            DisplayServer.screen_get_position(i),
            DisplayServer.screen_get_size(i))
        union = union.merge(rect) if i > 0 else rect

    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    DisplayServer.window_set_position(union.position)
    DisplayServer.window_set_size(union.size)
```

Guard the single-screen case: if `get_screen_count()` returns 1 (a monitor unplugged, a cable swapped), fall back to that screen alone instead of sizing a window partly off-screen. Log the union rectangle and the session type at startup; when spanning fails in the field, those two lines are the diagnosis.

### Rendering the scene, and what to do about the bezel

The scene itself needs no camera work in the basic version. One camera renders the whole virtual image into the one wide window, so perspective and depth are automatically consistent — there is only one viewpoint and one render. This is the strategy's biggest advantage for Greg's main concern.

The bezel needs one decision:

- **Ignore the gap.** The default, zero-code option. The part of the image behind the physical bezels is rendered but hidden by the frames. Objects slide behind the bezel and come out the other side, but they travel zero extra distance while hidden, so motion across the split looks slightly compressed and a wide object appears narrower in the room than it should.
- **Compensate for the gap.** Split the wide window into two viewports, one per panel, each with its own camera sharing one eye point and rendering its slice of a wider frustum that includes the bezel strip. That is the same asymmetric-frustum technique described under Strategy 2, applied inside one process with two `SubViewport`s (or one viewport and a second `Window`). It restores correct geometry across the frame at the cost of importing Strategy 2's camera code and calibration.

Recommendation: ship the ignore-the-gap version first. It proves the spanning, the rotation and the autostart with the least new code. Add viewport-split compensation only if the hidden-strip effect is visibly wrong in the actual scene; the frustum code from Strategy 2 drops in unchanged.

### Running it unattended

- Autostart the exported build after the graphical session is up (a desktop autostart entry, or a systemd user service that waits for the X session), never from a bare console login — the window needs the X server running.
- Hide the mouse cursor and disable screen blanking and DPMS power saving on both outputs, or the installation will eventually show a cursor, a black screen, or one dark panel.
- Keep a remote way in (SSH) that does not depend on the spanning window working, so a bad layout can be fixed without unplugging monitors.

### Failure modes to expect

- **Window confined to one screen, no error.** Almost always means the session is still Wayland. Check `echo $XDG_SESSION_TYPE` first.
- **Window spans, but one side is upside down.** The 180°-rotated monitor's rotation is not set in the OS display settings. Fix it at the OS level, not in Godot.
- **Left and right halves swapped.** The OS arranged the outputs in the other order. The startup code spans the union either way; fix the arrangement in the screen configuration tool, or detect each screen's position and set content offset accordingly.
- **Tearing on one panel only.** Two outputs rarely refresh in perfect step from one compositor. Usually tolerable for a slow-moving scene; note it rather than chasing it.
- **Performance drop versus one screen.** Expected: the same Pi now shades roughly twice the pixels in one render. Profile before optimizing; reducing the render scale is the first lever.

### Strategy 1: pros and cons

Pros:

- One process, one scene, one camera. Synchronization between the halves is perfect by construction — there is nothing to sync.
- 3D perspective and depth across the split are automatically correct in the basic version, which is Greg's main concern.
- The adaptation is small and localised: project window settings, one startup function, OS configuration. The existing scene code is untouched.
- One machine to deploy to, update and restart.

Cons:

- Requires switching the Pi from the default Wayland session to X11, and staying there.
- One Pi renders both screens, so the per-screen performance budget is halved compared with Strategy 2.
- A single point of failure: if the Pi or the window fails, both screens go.
- Pixel-correct bezel compensation is not free here either — it needs the two-viewport frustum split borrowed from Strategy 2.

## Strategy 2: two Pis, one screen each

### Shape of the solution

Run the same Godot project on two Pis. Each Pi is connected to one monitor and runs the scene fullscreen on that monitor. A per-machine role — `left` or `right` — is the only difference between the two installs, and it should come from a small configuration file, a command-line argument, or the hostname: never from a code branch that has to be edited per Pi, or the two builds will drift.

Notice what disappears in this strategy: the window problem. Fullscreen is per-monitor, and here per-monitor is exactly right — each Pi has one monitor and wants to fill it. There is no spanning window, so there is **no X11 requirement**: each Pi can stay on the default Wayland session and run ordinary single-screen fullscreen. Verify that on the target build early, but do not import Strategy 1's session switch into this strategy.

The work moves to two new places: the camera, and keeping the two scene instances in step.

### The camera rule: one eye point, two frustum slices

This is the part that is easy to get wrong, so it is stated plainly here:

**Do not move the camera sideways per Pi.** Locking the field of view and then offsetting each camera node by half the total width gives each screen a different eye point. Two eye points means two perspectives: an object at one depth shifts by a different amount across the seam than an object at another depth, so depth visibly breaks exactly where the two images meet — the failure Greg is most concerned about.

Instead, both Pis share **one virtual eye point**:

- Identical camera position, orientation, near plane and far plane on both Pis. The camera rig in the scene must not be translated, rotated or scaled differently per role.
- What differs per Pi is only **which slice of that one camera's frustum it renders**. The left Pi renders the left portion of a single wide frustum, the right Pi renders the right portion, and the bezel strip between them is rendered by neither.

If the two renders were placed side by side, they would form exactly the image the single camera would have produced. That is what "matching the single-Pi setup pixel-for-pixel" means mechanically, and it is why depth survives the split: there is only ever one perspective, sampled twice.

### Implementing the slice in Godot 4.0.4

Godot 4.0's `Camera3D` supports this directly through its frustum projection mode:

- `Camera3D.frustum_offset` shifts the frustum sideways, but it **only takes effect when `projection` is `PROJECTION_FRUSTUM` (2)**. In the default `PROJECTION_PERSPECTIVE` mode the offset is silently ignored — a likely source of "I set it and nothing changed" confusion, so set the mode first and assert it in code.
- `camera.set_frustum(size, offset, z_near, z_far)` switches the camera to frustum mode in one call, taking the frustum size and offset in world units plus the clip planes.

Work in fractions of the total virtual width first, then convert to world units. Normalise one panel's width to 1:

```text
panel = 1
gap   = gap_px / panel_px_width          # from the shared bezel maths
total = panel + gap + panel              # 2 + gap

left_slice_centre  = 0.5                 # centre of the left panel's slice
right_slice_centre = panel + gap + 0.5   # centre of the right panel's slice
frustum_centre     = total / 2
```

Each Pi's frustum offset, as a fraction of the total frustum width, is its slice centre minus the frustum centre: the left Pi gets `-(panel + gap) / 2` of the total width, the right Pi gets `+(panel + gap) / 2`. Multiply by the frustum's total width in world units at the image plane to get the `offset.x` passed to `set_frustum()`, keeping `offset.y = 0` — the split is purely horizontal, since the panels are side by side and share the same vertical extent.

Two implementation warnings:

- **Sign conventions need one empirical check.** Build a test scene (below) and confirm the left Pi is shifted the correct way; if the halves render each other's slices, negate both offsets. Do this once, in the test scene, not by reasoning about the sign in the abstract.
- **If frustum mode's world-unit size semantics fight the scene** — for example a scene authored around a specific perspective field of view — the fallback is a custom `Projection` per Pi: the same eye point, with different left and right frustum planes computed from the same fractions. Keep the fractions module shared either way, so the two mechanisms cannot disagree about the geometry. Verify the exact 4.0.4 API route for a custom projection before committing to the fallback; the `set_frustum` path is the documented one.

### The bezel in this strategy: a window frame, not a join

The bezel compensation is already inside the maths above: the gap fraction pushes each slice outward by half the gap, so each Pi renders slightly *less* than half of the panel-only image, and the missing middle strip is exactly the strip the physical frames cover.

Concretely, this is what the viewer sees:

- A straight horizontal edge crossing both panels stays on one straight line in the room, passing behind the frames.
- An object moving across the split is hidden for the time it spends "behind" the bezel, and its speed looks constant, because the hidden distance is real distance in the virtual image.
- Near and far objects keep their relative shift (parallax) across the split, because both slices come from one eye point and one continuous frustum.

Skipping the gap term (`gap = 0`) still produces a working split and is a reasonable first test — the slices then meet exactly at the seam — but lines will kink at the frames and crossing objects will jump by the bezel width. Keep `gap` as a configuration value from the start so turning it on is a measurement, not a code change.

No viewing-distance measurement is needed for any of this. The split is defined entirely in screen-space fractions of the shared frustum; how far away a viewer stands changes how large the scene looks, not how the two halves join.

### The rotated monitor

One monitor is rotated 180° relative to the other. Handle that at the operating-system level on that Pi: set the display rotation in its screen configuration so the image it receives is upright, exactly as in Strategy 1. The role configuration (`left`/`right`) and the rotation are independent facts — do not fold "the rotated one" into the frustum code as a special case, or swapping a cable later will break the geometry silently. Which physical monitor is rotated, and whether it ends up on the left or the right, is an open question listed at the end.

### Keeping the two Pis in step

How much machinery this needs depends entirely on whether anything moves:

- **Static camera, static scene.** Almost nothing. Identical scene plus identical eye point produces identical stills; the two Pis can run completely independently.
- **Animated or simulated scene, fixed camera.** The Pis need the same scene *state* at the same moment: the same random seed, and a shared sense of elapsed time. Synchronize the Pi clocks (NTP over the local network), start the scene on a wall-clock boundary, and drive animation from elapsed wall time rather than from accumulated frame deltas, so small frame-rate differences do not accumulate into drift.
- **Moving camera or interactive scene.** State has to be shared continuously. Make one Pi the authority: it owns the camera rig and any simulation state, and sends updates to the other (Godot's built-in multiplayer over ENet, or a simple UDP broadcast of the camera transform and state each frame, is enough for a camera-plus-animation workload). The follower applies the received state and renders its own slice. Keep the transport on a wired local link if one is available; Wi-Fi jitter shows up as seam judder on a moving scene.
- **Startup.** Add a wait-for-peer step: each Pi holds a static first frame until both report ready, then both start on an agreed timestamp. Without it, a ten-second difference in boot time becomes a permanent ten-second offset in any looping animation.

What is *not* required: frame-lock or genlock. The Pi's HDMI outputs cannot be hardware-locked to each other, and per Greg's assessment the eye tolerates small timing differences between the halves. Vsync each Pi to its own monitor, keep the clocks in step, and accept a possible one-frame difference between sides on fast motion.

### Deployment and running unattended

- Export one build; deploy the identical build to both Pis. Role and all measured values (resolution, gap, network address of the peer) live in a per-Pi configuration file read at startup and logged verbatim, so a field report of "the seam is wrong" can be checked against what each Pi actually loaded.
- Autostart each Pi's build after its graphical session is up, with the wait-for-peer handshake above. Disable blanking and DPMS per Pi, and hide the cursor per Pi.
- A failure of one Pi leaves the other half running. Decide in advance whether that is the acceptable degraded state, or whether the survivor should blank itself; for an installation, a lone half-image usually looks more broken than a dark pair. Either way, make it a configuration choice, not an accident.

### Test scene: prove the seam before adapting the real scene

Build this once and use it to validate the frustum code, the offset signs and the gap value before touching Greg's scene:

1. A fine grid and a long diagonal line spanning the full virtual width — catches slice-order, sign and gap errors in one look.
2. Two spheres at clearly different depths, driven slowly across the split — catches the eye-point error: if the camera was translated per Pi, the near sphere and the far sphere disagree about where the seam is.
3. A rotating object centred on the seam — catches timing drift between the Pis over a few minutes.
4. A still frame held for several minutes — confirms a static scene needs no sync traffic at all.

### Strategy 2: pros and cons

Pros:

- Each screen gets a whole Pi of rendering budget, so per-screen resolution and scene complexity can be higher than in Strategy 1.
- No window spanning and no X11 requirement; each Pi uses ordinary single-monitor fullscreen on the default session.
- Scales in principle: a third panel later means a third Pi and a third frustum slice, with no change to the geometry model.
- The halves are independent machines, so one can be serviced or rebooted without re-rendering the other — subject to the degraded-state choice above.

Cons:

- Two machines to buy, power, deploy to, update and keep configured identically; every fix ships twice.
- Correctness rests on the frustum-slice camera code and its calibration (offset signs, gap measurement). A wrong sign or a stale configuration file produces a subtly wrong image, not an obvious failure.
- Moving content needs clock sync, a startup handshake and, for a moving camera, continuous state sharing — a networking problem Strategy 1 simply does not have.
- The two outputs can never be frame-locked, so very fast motion across the seam can show a one-frame tear between the halves.

## Head-to-head

| Aspect | Strategy 1: one Pi, two screens | Strategy 2: two Pis, one screen each |
| --- | --- | --- |
| Window approach | Borderless windowed, sized to both screens | Ordinary fullscreen per Pi |
| Display server | X11 required; Wayland blocks spanning | Default Wayland session is fine |
| Camera work | None for the basic version | Asymmetric frustum slices, one shared eye point |
| Bezel handling | Ignored by default; compensation needs a two-viewport split | Built into the frustum maths from the start |
| Sync between halves | Perfect by construction | Clock sync, plus state sharing if anything moves |
| Render budget | One Pi shades both screens | One Pi per screen |
| Deployment | One machine, one install | Two machines, one build, per-Pi role config |
| Main risk | Session reverts to Wayland and spanning silently fails | Calibration or config drift produces a subtly wrong seam |
| Failure of one unit | Both screens lost | One half lost; survivor behaviour is a config choice |

For Greg's stated priorities — depth and perspective correct across the split first, timing a distant second — Strategy 1 is the smaller, safer adaptation and the right first attempt. Strategy 2 earns its extra machinery if the single Pi cannot hold the frame rate at the combined resolution, or if the installation grows beyond two panels.

## Open questions to settle before coding

These are genuinely undetermined. The code should read every one of them from configuration; the values marked *measure* have to come from the physical installation, not from a spec sheet guess.

1. **Panel resolution** (*measure/confirm*): horizontal × vertical pixels of one panel in portrait orientation. Every size in both strategies derives from this.
2. **Visible panel width in millimetres** (*measure*): needed, with the resolution, to convert the bezel gap into pixels.
3. **Bezel gap in millimetres** (*measure*): the full hidden strip where the panels meet — right frame of the left monitor + left frame of the right monitor + any air gap between them. Is the few-millimetre figure Greg mentioned this combined strip, or one side's frame only?
4. **Left/right and rotation assignment**: which monitor sits on the left, and is the 180°-rotated monitor the left or the right one? For Strategy 2, which Pi drives which side, and how is the role assigned — hostname, config file, or something else?
5. **How the app runs**: exported Linux build, or launched from the Godot editor? This affects the autostart method and where window settings can be enforced.
6. **Current session type**: what does `echo $XDG_SESSION_TYPE` print on the Pi today? (Only blocks Strategy 1, but it is a one-minute check that decides whether the X11 switch is even needed.)
7. **Does the camera move?** A static camera makes Strategy 2's sync nearly free and Strategy 1's basic version fully sufficient. A moving camera is what forces the authority/follower networking in Strategy 2.
8. **Is all content 3D?** This document assumes a 3D perspective scene. Any 2D overlay (HUD, text, menus) needs its own split rule in Strategy 2 — which Pi draws it, or how it is divided — and that rule is not yet defined.
9. **Second Pi for Strategy 2**: is a second Pi 5 already available, and are the two Pis linked by wired Ethernet or only by Wi-Fi? The link decides how much sync traffic is safe to design for.
10. **Refresh rates**: do both monitors run at the same refresh rate? A mismatch is tolerable in both strategies but should be known before anyone chases a tearing complaint.
11. **Bezel compensation in Strategy 1**: is the ignore-the-gap version acceptable for the actual scene, or is correct frame geometry required from day one? This decides whether Strategy 1 stays a one-function change.
12. **Degraded behaviour in Strategy 2**: if one Pi fails, should the surviving half keep showing, or blank itself?

## Adaptation notes for the existing codebase

- Put everything display-related behind one small module: screen discovery and window placement (Strategy 1), or role loading and frustum setup (Strategy 2). The scene, its camera rig and its animation code should not know which strategy is running beyond a single "virtual display" configuration object carrying total width, gap fraction and this machine's slice.
- Keep the bezel/geometry fractions in one shared file used by both strategies. Strategy 1's optional viewport split and Strategy 2's per-Pi slices are the same maths; two copies of it will eventually disagree.
- Log at startup, on every run: session type, screen count and sizes, loaded role, panel and gap values, and the computed frustum offsets or window rectangle. Every known failure mode of both strategies is diagnosable from that one log block.
- Validate on the test scene first (Strategy 2 section), and for Strategy 1 validate spanning with an empty scene before running the real one: if the window does not span with nothing in it, the session is wrong and no scene code will fix it.

## Sources

- Godot 4.0 `Camera3D` documentation — `frustum_offset` ("Only effective if projection is PROJECTION_FRUSTUM"), `set_frustum(size, offset, z_near, z_far)`, and the `PROJECTION_FRUSTUM` mode: https://docs.godotengine.org/en/4.0/classes/class_camera3d.html
- Raspberry Pi OS, switching the session from Wayland/labwc to X11 via `sudo raspi-config` → Advanced Options → Wayland → W1 X11: https://forums.raspberrypi.com/viewtopic.php?t=385120
- Setup facts (Godot 4.0.4, identical portrait monitors, one rotated 180°, fullscreen build showing on one screen, init 3 question, depth-over-timing priority, bezel-as-frame requirement): Greg, in the conversation this document was written for.
