# Nexus Vertex Painter – Installation

## Recommended: Pre-built Binaries (All Platforms)

The release zip includes GDExtension binaries for Windows, Linux, and macOS in one archive.

1. Go to [Releases](https://github.com/undomick/godot-nexus-vertex-painter/releases).
2. Download `godot-nexus-vertex-painter-<version>.zip`.
3. Extract into your project so the `addons/` folder merges with your project's `addons/`.
4. Enable the addon in **Project → Project Settings → Plugins**.
5. Restart Godot if it was already open.

The addon normally starts in **C++ mode**. If it doesn't (you see it fall back to GDScript), the pre-built binaries are not compatible with your OS/architecture. You can either build from source (see below) or keep using the GDScript fallback – in that case you can optionally delete the `bin/` folder inside the addon to remove the unused binaries.

## GDScript Fallback Only

1. Copy the `nexus_vertex_painter` folder into your project's `addons/` directory (without the `bin/` folder, or delete it after install).
2. Enable the addon in **Project → Project Settings → Plugins**.

Works immediately. Best for small meshes; for 50k+ vertices, the C++ extension is significantly faster.

## Build C++ GDExtension from Source

If the pre-built binaries don't work on your system, build them yourself:

1. **Clone godot-cpp** (if not already present):

   ```bash
   cd src
   git clone -b 4.2 https://github.com/godotengine/godot-cpp godot-cpp
   cd godot-cpp
   git submodule update --init --recursive
   cd ..
   ```

2. **Build godot-cpp** (one-time):

   ```bash
   cd src/godot-cpp
   scons platform=windows target=editor   # or linux, macos
   cd ../..
   ```

3. **Build the extension**:

   ```bash
   cd src
   scons platform=windows target=editor
   ```

4. The compiled library is copied to `addons/nexus_vertex_painter/bin/<platform>/`.

### Prerequisites

- Python 3.x with SCons (`pip install scons`)
- C++ compiler: MSVC (Windows), GCC/Clang (Linux), Xcode (macOS)

See `src/README.md` for detailed build instructions and troubleshooting.
