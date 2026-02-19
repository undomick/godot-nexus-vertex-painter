# Nexus Vertex Painter GDExtension (C++)

Performance-critical vertex painting logic implemented in C++ via GDExtension.

**Source code lives here (outside the Godot project).** Only compiled binaries are copied to `game/addons/nexus_vertex_painter/bin/`.

## Prerequisites

- Godot 4.2+ (tested with 4.6)
- Python 3.x with SCons (`pip install scons`)
- C++ compiler (MSVC on Windows, GCC/Clang on Linux, Xcode on macOS)

## Build Setup

### 1. Clone godot-cpp

```bash
cd src
git clone -b 4.2 https://github.com/godotengine/godot-cpp godot-cpp
cd godot-cpp
git submodule update --init --recursive
cd ..
```

### 2. Build godot-cpp bindings

First build the C++ bindings (one-time, takes several minutes):

```bash
cd godot-cpp
scons platform=windows target=editor  # Use target=editor for development in Godot editor
cd ..
```

### 3. Build the extension

```bash
# From src folder - use target=editor for editor development
scons platform=windows target=editor
```

The compiled library is written to `game/addons/nexus_vertex_painter/bin/windows/` (or linux/, macos/).

For exported games, build with template targets:

```bash
scons platform=windows target=template_debug   # Debug exports
scons platform=windows target=template_release  # Release exports
```

### 4. Verify

Open the Godot project (`game/`), ensure the addon is enabled. The GDExtension loads automatically. If the C++ extension is available, the vertex painter uses it for painting; otherwise it falls back to GDScript.

## Troubleshooting

- **Godot version mismatch**: Use the godot-cpp branch matching your Godot version (4.2, 4.3, etc.). For Godot 4.6, try branch `4.2` or the latest stable.
- **custom_api_file**: If bindings fail, run `godot --dump-extension-api` and pass `custom_api_file=path/to/extension_api.json` to the godot-cpp scons command.
- **Editor vs template**: Use `target=editor` when testing in the editor; use `target=template_debug` or `target=template_release` for exported games.
