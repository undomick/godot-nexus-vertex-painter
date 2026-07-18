# Nexus Vertex Painter GDExtension (C++)

Performance-critical vertex painting logic implemented in C++ via GDExtension.

**Source code lives here (outside the Godot project).** Only compiled binaries are copied to `game/addons/nexus_vertex_painter/bin/`.

## Prerequisites

- Godot 4.6+
- Python 3.x with SCons (`pip install scons`)
- C++ compiler (MSVC on Windows, GCC/Clang on Linux, Xcode on macOS)

## Build Setup

### 1. Clone godot-cpp

From the project root:

```bash
# Windows
.\scripts\install_dependencies.ps1

# Linux / macOS
./scripts/install_dependencies.sh
```

Or manually:

```bash
cd src
git clone -b 4.5 https://github.com/godotengine/godot-cpp godot-cpp
cd godot-cpp
git submodule update --init --recursive
cd ..
```

If the repo uses submodules: `git submodule update --init --recursive` from the project root.

### 2. Build godot-cpp bindings

First build the C++ bindings (one-time, takes several minutes):

```bash
cd godot-cpp
scons platform=windows target=editor  # Use target=editor for development in Godot editor
cd ..
```

### 3. Build the extension

From `src/`, build all targets used by the addon (`editor`, `template_debug`, `template_release`):

| OS | SCons platform | arch |
|----|----------------|------|
| Windows | `windows` | `x86_64` |
| Linux | `linux` | `x86_64` |
| macOS | `macos` | `universal` |

```bash
# Example: Windows editor
scons platform=windows target=editor arch=x86_64

# Example: Linux release export
scons platform=linux target=template_release arch=x86_64

# Example: macOS (universal)
scons platform=macos target=editor arch=universal
```

Output: `game/addons/nexus_vertex_painter/bin/<platform>/`.

### Version metadata

Release version and author are defined in `vertex_painter_constants.h` (defaults) and can be overridden at build time:

```bash
# Windows PowerShell
$env:ADDON_VERSION="2.3.0"; $env:ADDON_AUTHOR="Michael Kulzer"
scons platform=windows target=editor arch=x86_64

# Linux / macOS
ADDON_VERSION=2.3.0 ADDON_AUTHOR="Michael Kulzer" scons platform=linux target=editor arch=x86_64
```

Keep in sync with `game/addons/nexus_vertex_painter/plugin.cfg` when bumping releases.

### 4. Verify

Open the Godot project (`game/`), ensure the addon is enabled. The GDExtension loads automatically. If the C++ extension is available, the vertex painter uses it for painting; otherwise it falls back to GDScript.

## Troubleshooting

- **Godot version mismatch**: For Godot 4.6.x use godot-cpp branch `4.5` (no `4.6` branch upstream yet).
- **custom_api_file**: If bindings fail, run `godot --dump-extension-api` and pass `custom_api_file=path/to/extension_api.json` to the godot-cpp scons command.
- **Editor vs template**: Use `target=editor` when testing in the editor; use `target=template_debug` or `target=template_release` for exported games.
