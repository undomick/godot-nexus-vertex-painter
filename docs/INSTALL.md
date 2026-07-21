# Nexus Vertex Painter – Installation

Requires **Godot 4.6+** (addon `compatibility_minimum = 4.6`).

## Recommended: Pre-built Binaries (All Platforms)

The release zip includes GDExtension binaries for **Windows**, **Linux**, and **macOS** (editor, `template_debug`, and `template_release` per platform).

1. Go to [Releases](https://github.com/undomick/godot-nexus-vertex-painter/releases).
2. Download `godot-nexus-vertex-painter-<version>.zip`.
3. Extract into your project so the `addons/` folder merges with your project's `addons/`.
4. Enable the addon in **Project → Project Settings → Plugins**.
5. Restart Godot if it was already open.

The addon normally starts in **C++ mode** (check the Output panel: `Nexus Vertex Painter GDExtension v…` and `C++ Mode v…` in the toolbar message). If it falls back to GDScript, the pre-built binaries do not match your OS/architecture. Either [build from source](#build-c-gdextension-from-source) or delete the `bin/` folder and use the GDScript fallback.

## GDScript Fallback Only

1. Copy the `nexus_vertex_painter` folder into your project's `addons/` directory (without the `bin/` folder, or delete `bin/` after install).
2. Enable the addon in **Project → Project Settings → Plugins**.

Works immediately. Best for small meshes; for 50k+ vertices, the C++ extension is significantly faster.

## Build C++ GDExtension from Source

Use this when developing the addon repository or when release binaries are missing for your platform.

### 1. Get godot-cpp

From the **repository root**:

```powershell
# Windows
.\scripts\install_dependencies.ps1
```

```bash
# Linux / macOS
./scripts/install_dependencies.sh
```

Or with git submodules (after clone):

```bash
git submodule update --init --recursive
```

If `src/godot-cpp` is empty after clone, run `scripts/install_dependencies.sh` (or the PowerShell script). CI uses the same fallback when the submodule gitlink is not in the tree yet.

**godot-cpp branch:** For Godot **4.6**, clone branch **`4.5`** (there is no `4.6` branch on [godot-cpp](https://github.com/godotengine/godot-cpp) yet; 4.5 bindings are compatible with Godot 4.6).

Manual clone (`src/` folder):

```bash
cd src
git clone -b 4.5 https://github.com/godotengine/godot-cpp godot-cpp
cd godot-cpp && git submodule update --init --recursive && cd ../..
```

### 2. Build godot-cpp (one-time per platform)

```bash
cd src/godot-cpp
# Windows
scons platform=windows target=editor arch=x86_64
# Linux
scons platform=linux target=editor arch=x86_64
# macOS
scons platform=macos target=editor arch=universal
cd ../..
```

### 3. Build the extension (all export targets)

From `src/`, build **editor**, **template_debug**, and **template_release** for your platform:

```bash
cd src
scons platform=windows target=editor arch=x86_64
scons platform=windows target=template_debug arch=x86_64
scons platform=windows target=template_release arch=x86_64
```

Replace `platform` / `arch` as in [src/README.md](../src/README.md).

Output when building **this repo**: `game/addons/nexus_vertex_painter/bin/<platform>/`.  
When using the addon in another project, that path is `addons/nexus_vertex_painter/bin/<platform>/`.

Optional version metadata at build time:

```bash
ADDON_VERSION=2.3.2 ADDON_AUTHOR="Michael Kulzer" scons platform=linux target=editor arch=x86_64
```

### Prerequisites

- Python 3.x with SCons (`pip install scons`)
- C++ toolchain: MSVC or MinGW (Windows), GCC/Clang (Linux), Xcode (macOS)

See [src/README.md](../src/README.md) for troubleshooting (Godot/godot-cpp version match, `env.Clone` for defines, locked DLL on Windows).
