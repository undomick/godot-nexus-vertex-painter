# Nexus Vertex Painter – Installation

## Method 1: Addon Only (GDScript Fallback)

1. Copy the `nexus_vertex_painter` folder into your project’s `addons/` directory.
2. In Godot: **Project → Project Settings → Plugins**
3. Enable **Nexus Vertex Painter**.

The addon works immediately with the GDScript fallback. For meshes with many vertices (50k+), performance is better with the C++ extension.

## Method 2a: Pre-built C++ Binaries (Recommended)

We provide pre-compiled GDExtension binaries for Windows, Linux, and macOS:

1. Go to the [Releases](https://github.com/undomick/godot-nexus-vertex-painter/releases) section of this repository.
2. Download the archive for your platform (`linux-editor-x86_64.zip`, `windows-editor-x86_64.zip`, or `macos-editor-universal.zip`).
3. Extract the contents into your project's `addons/nexus_vertex_painter/bin/` folder.
4. **Folder names:** The GDExtension expects subfolders named `windows/`, `linux/`, or `macos/`. If the ZIP uses different names (e.g. `windows-editor-x86_64`, `linux-editor-x86_64`, `macos-editor-universal`), rename the extracted folder accordingly before or after copying into `bin/`:
   - `windows-editor-x86_64` → `windows`
   - `linux-editor-x86_64` → `linux`
   - `macos-editor-universal` → `macos`
5. Restart Godot if it was already open.

No compiler or build tools required.

## Method 2b: Build C++ GDExtension Yourself

If pre-built binaries are not available for your platform, you can build from source:

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

### Platform Notes

- **Windows**: Use `platform=windows`
- **Linux**: Use `platform=linux`
- **macOS**: Use `platform=macos` and optionally `arch=universal` for universal binary

See `src/README.md` in the project root for more build details and troubleshooting.
