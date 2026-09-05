#!/usr/bin/env bash
set -euo pipefail

width="${CSI_CAMERA_WIDTH:-960}"
height="${CSI_CAMERA_HEIGHT:-540}"
fps="${CSI_CAMERA_FPS:-30}"

command -v gst-launch-1.0 >/dev/null || { echo "gst-launch-1.0 is required" >&2; exit 1; }
gst-inspect-1.0 libcamerasrc >/dev/null || { echo "GStreamer libcamerasrc is unavailable" >&2; exit 1; }

pipeline=(
  libcamerasrc
  "video/x-raw,format=NV12,width=${width},height=${height},framerate=${fps}/1"
  '!'
  videoconvert
  '!'
  'video/x-raw,format=RGBA'
  '!'
  appsink
  'drop=true'
  'max-buffers=1'
  'sync=false'
)

echo "Testing libcamera pipeline at ${width}x${height} @ ${fps} fps"
set +e
timeout "${CSI_CAMERA_TIMEOUT:-5}s" gst-launch-1.0 -e "${pipeline[@]}" >/dev/null
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
  exit "$status"
fi
