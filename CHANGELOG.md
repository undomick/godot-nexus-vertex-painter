# Changelog

All notable changes to Nexus Vertex Painter will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-03-03

### Added

- Additional shaders for vertex color workflows
- **Preview Smart Mask**: Visual overlay to preview which areas the slope/curvature mask will affect before painting (white = paintable, black = masked out)

### Fixed

- Meshes could disappear under certain circumstances while painting; runtime mesh rebuild is now more robust
- Division-by-zero guards (brush_size, falloff, radius) in C++ and GDScript; null-checks for `get_world_3d()`, Bake/Revert `load()`, `surface_get_arrays`, camera, `create_trimesh_shape`; `get_neighbors` safe access when cache build fails; `_runtime_mesh` null-guard; `colors.resize(vertex_count)` validation in paint path; procedural slope/bottom_up edge cases; image dimension checks in texture sampling
- **Bake/Revert**: Mesh type validation for loaded resources; undo history cleared on Bake to prevent stale references
- **Data integrity**: `_ensure_packed_color_array` uses slice when shrinking to avoid mutating original; Preview overlays cleared after Bake
- **Performance**: Single raycast instead of per-mesh; early exit when no channels active (Fill/Clear); central `_get_mask_settings()` helper; C++ explicit `PackedInt32Array` for neighbor map
- **UX**: Texture drop zone now warns when load fails or resource is not a Texture2D

### Known Issues

- Surfaces that previously did not support vertex colors should now receive them; however, during painting the debug output may be flooded with the following error:
  - `ERROR: servers/rendering/rendering_server.cpp:784 - Condition "p_arrays[ai].get_type() != Variant::PACKED_BYTE_ARRAY" is true. Returning: ERR_INVALID_PARAMETER`
  - `ERROR: Invalid array format for surface.`
  - `ERROR: scene/resources/mesh.cpp:1825 - Condition "err != OK" is true.`
  - This appears to be related to Godot's handling of compressed mesh attributes (e.g. `ARRAY_FLAG_COMPRESSED`) when using `surface_update_attribute_region` or similar fast-path updates.

---

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

