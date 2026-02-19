# Nexus Vertex Painter

[![Discord](https://img.shields.io/discord/1446024019341086864?label=Discord&logo=discord&style=flat-square&color=5865F2)](https://discord.gg/HMxbzqWCgQ)
[![Ko-fi](https://img.shields.io/badge/Support%20me-Ko--fi-F16061?style=flat-square&logo=ko-fi&logoColor=white)](https://ko-fi.com/jundrie)

A professional vertex color painting tool for Godot 4.2+ that supports manual brush painting and procedural generation on 3D meshes. Based on [undomick/godot-nexus-vertex-painter](https://github.com/undomick/godot-nexus-vertex-painter) with additional C++ GDExtension and extended features.

## Features

- **Manual Painting**: Add, Subtract, Set, Blur, and Sharpen modes with brush textures
- **Procedural Generation**: Top-down, slope, bottom-up, and noise-based painting
- **Smart Masking**: Slope and curvature masks for precise control
- **Fill & Clear**: Batch operations per channel (RGBA)
- **Bake & Revert**: Save to mesh file or revert to original
- **Undo/Redo**: Full editor integration
- **C++ GDExtension**: Optional native performance boost

## Requirements

- Godot 4.2 or later (tested with 4.6)
- For maximum performance: pre-built GDExtension binaries (see Installation)

## Installation

### Quick Install (GDScript only)

1. Copy the `addons/nexus_vertex_painter` folder into your project's `addons/` directory
2. Enable the addon in Project → Project Settings → Plugins
3. The addon works immediately with the GDScript fallback

### With C++ for Better Performance

For large meshes, the C++ GDExtension significantly improves painting speed. See [docs/INSTALL.md](docs/INSTALL.md) for build instructions.

**Pre-built binaries**: Check [Releases](https://github.com/undomick/godot-nexus-vertex-painter/releases) for Windows, Linux, and macOS binaries.

### Building from Source (C++ GDExtension)

If you work on the source code and need to build the C++ extension:

1. Run `.\scripts\install_dependencies.ps1` to clone godot-cpp and init submodules
2. Run `pip install scons`, then `cd src` and `scons platform=windows target=editor` (or linux/macos)

See [src/README.md](src/README.md) for detailed build instructions.

## Usage

1. Open a 3D scene with `MeshInstance3D` nodes
2. Select one or more meshes
3. Click **Vertex Paint** in the 3D editor toolbar (or Spatial menu)
4. Use the dock panel to configure brush settings and paint

### Shortcuts

| Shortcut | Action |
|----------|--------|
| X / Y / Z | Cycle brush mode (Add → Subtract → Set → Blur → Sharpen) |
| 1–4 | Toggle R / G / B / A channels |
| Ctrl + Right Mouse | Adjust brush size (vertical) and strength (horizontal) |
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

Join the [Discord server](https://discord.gg/HMxbzqWCgQ) to ask questions, suggest features, or show off your projects made with this addon.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

### Third-Party Attribution

- **Nexus Vertex Painter** ([undomick/godot-nexus-vertex-painter](https://github.com/undomick/godot-nexus-vertex-painter)): MIT License – original addon
- **godot-cpp**: MIT License – used for GDExtension bindings
- **Godot Engine**: MIT License – game engine
