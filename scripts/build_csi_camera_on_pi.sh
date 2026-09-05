#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
addon_dir="$repo_root/addons/csi_camera"
godot_cpp_dir="${GODOT_CPP_DIR:-$addon_dir/godot-cpp}"
build_dir="$addon_dir/build"
output_dir="$addon_dir/bin"

command -v cmake >/dev/null || { echo "cmake is required" >&2; exit 1; }
command -v pkg-config >/dev/null || { echo "pkg-config is required" >&2; exit 1; }
pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 || { echo "GStreamer development packages are required" >&2; exit 1; }
command -v gst-inspect-1.0 >/dev/null || { echo "gst-inspect-1.0 is required" >&2; exit 1; }
gst-inspect-1.0 libcamerasrc >/dev/null || { echo "GStreamer libcamerasrc is unavailable" >&2; exit 1; }

if [[ ! -d "$godot_cpp_dir" ]]; then
  echo "godot-cpp checkout not found at $godot_cpp_dir" >&2
  exit 1
fi

cmake -S "$addon_dir" -B "$build_dir" -DGODOT_CPP_DIR="$godot_cpp_dir" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_dir" --parallel
mkdir -p "$output_dir"
cp "$build_dir/libcsi_camera.linux.arm64.so" "$output_dir/"
cp "$addon_dir/csi_camera.gdextension.template" "$addon_dir/csi_camera.gdextension"
file "$output_dir/libcsi_camera.linux.arm64.so"
ldd "$output_dir/libcsi_camera.linux.arm64.so"
