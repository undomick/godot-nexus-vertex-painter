#!/usr/bin/env bash
# Clone godot-cpp and init submodules. Run from project root.
set -euo pipefail

GODOT_CPP_BRANCH="${GODOT_CPP_BRANCH:-4.6}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/src"
GODOT_CPP_DIR="$SRC_DIR/godot-cpp"

echo "Nexus Vertex Painter - Install Dependencies"
echo "Project root: $PROJECT_ROOT"
echo "godot-cpp branch: $GODOT_CPP_BRANCH"
echo ""

if [ ! -d "$SRC_DIR" ]; then
	echo "Error: src/ not found." >&2
	exit 1
fi

if ! command -v git >/dev/null 2>&1; then
	echo "Error: git is required." >&2
	exit 1
fi

if command -v scons >/dev/null 2>&1; then
	scons --version
else
	echo "Warning: scons not found. Install with: pip install scons"
fi

SKIP_CLONE=0
if [ -d "$GODOT_CPP_DIR" ] && [ -n "$(ls -A "$GODOT_CPP_DIR" 2>/dev/null | grep -v '^\.')" ]; then
	echo "godot-cpp already exists. Skipping clone."
	SKIP_CLONE=1
fi

if [ "$SKIP_CLONE" -eq 0 ]; then
	echo "Cloning godot-cpp (branch $GODOT_CPP_BRANCH)..."
	(
		cd "$SRC_DIR"
		git clone -b "$GODOT_CPP_BRANCH" https://github.com/godotengine/godot-cpp godot-cpp
	)
fi

if [ -d "$GODOT_CPP_DIR" ]; then
	echo "Initializing godot-cpp submodules..."
	(
		cd "$GODOT_CPP_DIR"
		git submodule update --init --recursive
	)
fi

echo ""
echo "Dependencies installed."
echo "Build (from src/):"
echo "  scons platform=linux target=editor arch=x86_64"
echo "  scons platform=windows target=editor arch=x86_64"
echo "  scons platform=macos target=editor arch=universal"
