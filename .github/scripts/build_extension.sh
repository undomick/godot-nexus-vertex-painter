#!/usr/bin/env bash
# Build the addon GDExtension only (expects godot-cpp already built). Run from repo root.
set -euo pipefail

PLATFORM="${1:?platform: linux|windows|macos}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

cd src

case "$PLATFORM" in
linux)
	for target in editor template_debug template_release; do
		scons platform=linux target="$target" arch=x86_64 build_library=no -j"$JOBS"
	done
	;;
windows)
	for target in editor template_debug template_release; do
		scons platform=windows target="$target" arch=x86_64 build_library=no -j"$JOBS"
	done
	;;
macos)
	for target in editor template_debug template_release; do
		scons platform=macos target="$target" arch=universal build_library=no -j"$JOBS"
	done
	;;
*)
	echo "Unknown platform: $PLATFORM" >&2
	exit 1
	;;
esac
