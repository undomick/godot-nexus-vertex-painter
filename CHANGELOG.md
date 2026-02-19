# Changelog

All notable changes to Nexus Vertex Painter will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-02-19

### Added

- **5-Layer Vertex Color Material Shader** (`vertex_color_material_blend.gdshader`): Blends up to five materials by vertex color (RGBA). Each layer: ORM, Albedo, Normal. Tangent-space normal blending.
- **C++ GDExtension for performance**: Critical painting logic migrated from GDScript to C++
  - `paint_surface()`: Native vertex loop with Manhattan pre-check, triplanar texture sampling, slope/curvature masks, and all blend modes (ADD, SUB, SET, BLUR, SHARPEN)
  - `build_neighbor_cache()`: Fast neighbor topology lookup for Blur/Sharpen tools
  - `fill_surface()`: Optimized Fill/Clear operations
- Automatic fallback to GDScript when C++ extension is not available (e.g. missing compiled binary)
- GDExtension build system (SConstruct, godot-cpp) in project `src/` folder
- Compiled binaries deployed to `addons/nexus_vertex_painter/bin/` only (source code outside Godot project)

### Changed

- Project structure: C++ sources and build files moved to `src/` at project root
- Significantly improved performance on detailed models with high vertex counts
- Requires Godot 4.2+ for GDExtension compatibility

### Fixed

- Performance bottleneck on models with >50k vertices when painting
- Slow Blur/Sharpen tools due to mesh topology analysis

---

## [1.6] - (previous)

- Manual vertex color painting
- Procedural generation (top-down, slope, bottom-up, noise)
- Fill/Clear, Bake, Revert
- Brush texture support, triplanar sampling
- Slope and curvature masks
- Undo/Redo support
