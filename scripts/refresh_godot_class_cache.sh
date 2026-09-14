#!/usr/bin/env bash
# Rebuilds Godot's global class_name cache (.godot/global_script_class_cache.cfg).
#
# Why this exists: running the project from source via `--main-scene` (as
# opposed to opening it in the editor first) does NOT register newly added or
# renamed `class_name` scripts. If the cache is stale, spinning_cube.gd (and
# anything else referencing those classes) fails to compile with errors like:
#   SCRIPT ERROR: Parse Error: Could not find type "X" in the current scope.
# and the app silently falls back to a static, non-moving, camera-less cube.
#
# Run this once after pulling/merging any change that adds, removes, or
# renames a `class_name` script anywhere under scripts/ or addons/.
#
# Usage:
#   scripts/refresh_godot_class_cache.sh
#   GODOT_BIN=/path/to/Godot scripts/refresh_godot_class_cache.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -n "${GODOT_BIN:-}" ]; then
	GODOT="$GODOT_BIN"
elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
	GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
elif command -v godot >/dev/null 2>&1; then
	GODOT="$(command -v godot)"
elif command -v godot4 >/dev/null 2>&1; then
	GODOT="$(command -v godot4)"
else
	echo "error: could not find a Godot editor binary. Set GODOT_BIN=/path/to/Godot and retry." >&2
	exit 1
fi

echo "Using Godot binary: $GODOT"
echo "Rebuilding global class cache for: $REPO_ROOT"

cd "$REPO_ROOT"
"$GODOT" --headless --editor --quit-after 20

echo "Done. .godot/global_script_class_cache.cfg has been refreshed."
