---
name: redeploy-pi-clients
description: Redeploy the clanker-ui Godot client to the Raspberry Pis (pi5ai2sd and m5image) after code, shader, or scene changes. Use when asked to deploy, redeploy, push, or restart the installation clients.
---

# Redeploy the Godot client on the Pis

Script, shader, scene, and default-config changes ship in `clankerUI.pck`. The
`clankerUI.arm64` binary rarely changes, so only re-export it if the Godot engine
version or export template changes.

## Targets

- `gregm@pi5ai2sd` and `gregm@m5image` (Tailscale hostnames; SSH keys are already set up on the Mac; passwordless `sudo`).
- Each Pi has the app in `/home/gregm/` (`clankerUI.arm64`, `clankerUI.pck`, `clankerUI.sh`).
- The client runs as the **user** service `clankerui.service`. Use `systemctl --user`, not `sudo systemctl`.
- Per-node settings live in `~/.local/share/godot/app_userdata/clankerUI/installation.cfg`. A deploy doesn't touch them. A key missing from that file falls back to the code default.

## Steps

1. Export the pack from the repo root. The preset is named `Linux`:

   ```sh
   /Applications/Godot.app/Contents/MacOS/Godot --headless --export-pack "Linux" /tmp/clankerUI.pck
   ```

   Look for `[ DONE ] savepack`. The size can match the old pack by coincidence, so don't treat that as "unchanged".

2. For each Pi, back up the old pack, install the new one, restart, and verify:

   ```sh
   for h in pi5ai2sd m5image; do
     scp -q /tmp/clankerUI.pck gregm@$h:/tmp/new.pck &&
     ssh gregm@$h 'cp ~/clankerUI.pck ~/clankerUI-before-<short-tag>.pck &&
       cp /tmp/new.pck ~/clankerUI.pck &&
       systemctl --user restart clankerui.service; sleep 5;
       systemctl --user is-active clankerui.service'
   done
   rm /tmp/clankerUI.pck
   ```

   Expect `active` from each.

3. Tell the user what changed, and that backups are at `~/clankerUI-before-<tag>.pck`.

## Rollback

```sh
ssh gregm@<host> 'cp ~/clankerUI-before-<tag>.pck ~/clankerUI.pck && systemctl --user restart clankerui.service'
```

## Notes

- A peer-ordered or network-protocol change needs both Pis updated together; deploy to both before judging behavior.
- Per-node config changes go in that Pi's `installation.cfg`, not the pack.
- The README's "Standalone on Raspberry Pi" section covers first-time setup and the CSI camera extension.
