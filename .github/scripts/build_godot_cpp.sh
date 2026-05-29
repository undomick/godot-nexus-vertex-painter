#!/usr/bin/env bash
# Build godot-cpp static libraries only (CI). Run from repo root.
set -euo pipefail

PLATFORM="${1:?platform: linux|windows|macos}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

cd src/godot-cpp

case "$PLATFORM" in
linux)
	for target in editor template_debug template_release; do
		scons platform=linux target="$target" arch=x86_64 -j"$JOBS"
	done
	;;
windows)
	for target in editor template_debug template_release; do
		scons platform=windows target="$target" arch=x86_64 -j"$JOBS"
	done
	;;
macos)
	for target in editor template_debug template_release; do
		scons platform=macos target="$target" arch=universal -j"$JOBS"
	done
	;;
*)
	echo "Unknown platform: $PLATFORM" >&2
	exit 1
	;;
esac
