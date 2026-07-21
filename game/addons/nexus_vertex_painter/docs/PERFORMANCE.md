# Nexus Vertex Painter – Performance

## Benchmark (paint_surface + cache + GPU sync)

The benchmark compares C++ `paint_surface`, `_prep_cache` (arrays vs MeshDataTool), and stroke GPU sync.

### Run the benchmark

1. **From command line** (Godot in PATH):
   ```bash
   cd game
   godot --path . --headless --script res://addons/nexus_vertex_painter/tests/run_performance.gd
   ```

2. **Windows**: Double-click `addons/nexus_vertex_painter/tests/run_performance.bat`  
   Edit the batch file to set `GODOT_PATH` to your Godot executable if needed.

### Reference results (Godot 4.6, Windows)

`paint_surface` (ADD mode) with C++ GDExtension is typically **~30x faster** than the GDScript fallback (see historical v2.0 benchmark table in repo history).

The benchmark also prints **prep_cache** and **arrays runtime sync / dab** timings for 20k vertices.

## Paint sync modes (v2.2+)

During strokes the addon picks one of two GPU update strategies:

| Mode | When | Stroke update |
|------|------|----------------|
| **attribute** (stroke default after setup) | Mesh has `ARRAY_COLOR` + `ARRAY_FLAG_USE_DYNAMIC_UPDATE` (uncompressed) | `surface_update_attribute_region` — **does not** reassign `MeshInstance3D.mesh` (avoids Inspector rebuild / jitter) |
| **arrays** (one-shot upgrade / fallback) | Uncompressed mesh with readable `surface_get_arrays`, but not yet dynamic | Duplicate cached surface arrays, inject `surface_data`, build a **new** `ArrayMesh` with `USE_DYNAMIC_UPDATE`, assign once, then promote to attribute |

Compressed attributes or missing array cache also start on the attribute path; live upload still needs a paintable (uncompressed + dynamic) mesh after normalize/rebuild.

**Normalize / rebuild** prefers `surface_get_arrays` (GDScript hybrid, then C++ arrays path). MeshDataTool is used only for compressed surfaces or when arrays are invalid. C++ `apply_colors_to_mesh` no longer blocks the fast arrays rebuild.

**`_prep_cache`** uses `surface_get_arrays` for positions/normals when possible; MeshDataTool is fallback only.

## Paintable meshes (visibility)

Vertex painting only shows in the viewport when the **active material** reads vertex colors (`vertex_color_use_as_albedo` on `StandardMaterial3D`, or a vertex-color shader). `material_override` on `MeshInstance3D` overrides all surfaces.

For best performance:

- **No** `Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES` on paintable surfaces
- `ARRAY_COLOR` present after normalize (automatic on first paint for CUSTOM / face-corner imports)
- After the first paint sync, surfaces use `ARRAY_FLAG_USE_DYNAMIC_UPDATE` so strokes stay on the attribute path

**glTF import:** enable `meshes/force_disable_compression=true` on paintable assets, then reimport.

**Blender color attributes:** Vertex-domain `COLOR_0` maps directly to Godot `ARRAY_COLOR`. Face-corner layers or custom names (e.g. `_paint`) often import into `ARRAY_CUSTOM0`–`CUSTOM3` instead. On the first paint stroke the addon **normalizes** the mesh to `ARRAY_COLOR` (preserves UVs/materials, stores the original path in `_vertex_paint_original_path`).

**Decompression:** Compressed glTF surfaces are rebuilt into an uncompressed `ArrayMesh` on the first paint (or when loading saved `surface_data`).

**Debug:** Enable Project Settings `nexus/vertex_painter/debug_logging` to print per-surface diagnostics (`sync=arrays|attribute`, `compress`, `dynamic`) in the output panel.

## Related docs

- [VERTEX_COLOR_TRANSFER.md](VERTEX_COLOR_TRANSFER.md) – snapshot workflow after Blender reimport
- [PLUGIN_SMOKE_CHECKLIST.md](PLUGIN_SMOKE_CHECKLIST.md) – editor regression checklist
- [USER_MANUAL.md](../../../../docs/USER_MANUAL.md) – brush modes, bake, preview overlay
