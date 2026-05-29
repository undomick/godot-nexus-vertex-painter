# Nexus Vertex Painter

[![Discord](https://img.shields.io/discord/1446024019341086864?label=Discord&logo=discord&style=flat-square&color=5865F2)](https://discord.gg/VTSpAEHHhW)
[![Ko-fi](https://img.shields.io/badge/Support%20me-Ko--fi-F16061?style=flat-square&logo=ko-fi&logoColor=white)](https://ko-fi.com/jundrie)

A professional vertex color painting tool for **Godot 4.6+** with manual brush painting and procedural generation on 3D meshes. Based on [undomick/godot-nexus-vertex-painter](https://github.com/undomick/godot-nexus-vertex-painter) with C++ GDExtension and extended editor features.

## Features

- **Manual Painting**: Add, Subtract, Set, Blur, and Sharpen modes with brush textures
- **Procedural Generation**: Top-down, slope, bottom-up, and noise-based painting
- **Smart Masking**: Slope and curvature masks; **Preview Smart Mask** overlay
- **Projection mode**: Both sides or front-only (raycast-facing vertices)
- **Vertex color preview**: Overlay painted colors on materials (**VC overlay** strength)
- **Fill & Clear**: Batch operations per channel (RGBA)
- **Bake**, **Bake to Scene**, **Revert**
- **Paint snapshot / transfer**: Preserve colors across Blender mesh reimport
- **Undo/Redo**: Full editor integration
- **C++ GDExtension**: Pre-built binaries for Windows, Linux, macOS (GDScript fallback)

## Requirements

- Godot **4.6** or later (`compatibility_minimum` in `.gdextension`)
- For large meshes: pre-built GDExtension binaries (see [Installation](docs/INSTALL.md))

Documentation: [docs/README.md](docs/README.md) · [User manual](docs/USER_MANUAL.md)

## Installation

### Recommended: Pre-built Binaries

1. Download `godot-nexus-vertex-painter-<version>.zip` from [Releases](https://github.com/undomick/godot-nexus-vertex-painter/releases)
2. Extract into your project so the `addons/` folder merges with your project's `addons/`
3. Enable the addon in **Project → Project Settings → Plugins**

The zip includes binaries for Windows, Linux, and macOS. The addon normally runs in **C++ mode**. If it falls back to GDScript, the pre-built binaries don't match your OS - either [build from source](docs/INSTALL.md#build-c-gdextension-from-source), or keep the GDScript fallback (you can delete the addon's `bin/` folder if you prefer).

### GDScript Only

Copy the addon without `bin/` or delete `bin/` after install. Works immediately; for meshes with 50k+ vertices, C++ is faster.

### Build from Source

If you develop the addon or need custom binaries: run `.\scripts\install_dependencies.ps1`, then `pip install scons` and `cd src && scons platform=windows target=editor` (or `linux`/`macos`). See [docs/INSTALL.md](docs/INSTALL.md) and [src/README.md](src/README.md) for details.

## Usage

1. Open a 3D scene with `MeshInstance3D` nodes
2. Select one or more meshes
3. Click **Vertex Paint** in the 3D editor toolbar (or Spatial menu)
4. Use the dock panel to configure brush settings and paint

### Shortcuts


| Shortcut            | Action                                                    |
| ------------------- | --------------------------------------------------------- |
| X / Y / Z           | Cycle brush mode (Add → Subtract → Set → Blur → Sharpen)  |
| 1 - 4               | Toggle R / G / B / A channels                             |
| Ctrl + Right Mouse  | Adjust brush size (vertical) and strength (horizontal)    |
| Shift + Right Mouse | Adjust falloff (vertical) and brush rotation (horizontal) |


## Project Structure

```
nexus_vertexpainter/
├── game/                    # Godot project & demo
│   ├── addons/
│   │   └── nexus_vertex_painter/   # Addon files
│   └── project.godot
├── src/                     # C++ GDExtension source (optional build)
│   ├── vertex_painter_core.cpp
│   └── README.md            # Build instructions
├── scripts/                 # Build & release helpers
│   ├── transfer_release.ps1     # Export release files (excludes .cursor, mcps, etc.)
│   └── install_dependencies.ps1 # Clone godot-cpp for C++ build
├── LICENSE
└── README.md
```

## Support & Community

Join the [Discord server](https://discord.gg/VTSpAEHHhW) to ask questions, suggest features, or show off your projects made with this addon.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

### Third-Party Attribution

- **Nexus Vertex Painter** ([undomick/godot-nexus-vertex-painter](https://github.com/undomick/godot-nexus-vertex-painter)): MIT License
- **godot-cpp**: MIT License - used for GDExtension bindings
- **Godot Engine**: MIT License - game engine

