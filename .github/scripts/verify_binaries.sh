#!/usr/bin/env bash
# Verify GDExtension binaries exist after SCons build (CI).
set -euo pipefail

BIN_ROOT="${1:-game/addons/nexus_vertex_painter/bin}"
PLATFORM="${2:?platform required: linux|windows|macos}"

check_file() {
	local path="$1"
	if [ ! -f "$path" ]; then
		echo "Missing: $path" >&2
		return 1
	fi
	echo "OK: $path"
}

case "$PLATFORM" in
linux)
	check_file "$BIN_ROOT/linux/nexus_vertex_painter.linux.editor.x86_64.so"
	check_file "$BIN_ROOT/linux/nexus_vertex_painter.linux.template_debug.x86_64.so"
	check_file "$BIN_ROOT/linux/nexus_vertex_painter.linux.template_release.x86_64.so"
	;;
windows)
	check_file "$BIN_ROOT/windows/nexus_vertex_painter.windows.editor.x86_64.dll"
	check_file "$BIN_ROOT/windows/nexus_vertex_painter.windows.template_debug.x86_64.dll"
	check_file "$BIN_ROOT/windows/nexus_vertex_painter.windows.template_release.x86_64.dll"
	;;
macos)
	check_file "$BIN_ROOT/macos/nexus_vertex_painter.macos.editor.universal.dylib"
	check_file "$BIN_ROOT/macos/nexus_vertex_painter.macos.template_debug.universal.dylib"
	check_file "$BIN_ROOT/macos/nexus_vertex_painter.macos.template_release.universal.dylib"
	;;
*)
	echo "Unknown platform: $PLATFORM" >&2
	exit 1
	;;
esac
