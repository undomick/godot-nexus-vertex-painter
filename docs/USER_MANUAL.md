# Nexus Vertex Painter – User Manual

## Quick Start

1. Open a 3D scene with `MeshInstance3D` nodes that use **ArrayMesh**.
2. Select one or more meshes in the scene tree.
3. Click **Vertex Paint** in the 3D editor toolbar.
4. Use the dock panel to configure brush settings and paint on the mesh.

## Brush Modes

| Mode | Description |
|------|-------------|
| **Add** | Adds color to vertices (brightens). |
| **Subtract** | Removes color from vertices (darkens). |
| **Set** | Sets vertices to a fixed strength value. |
| **Blur** | Smooths vertex colors by averaging neighbors. |
| **Sharpen** | Increases contrast between neighboring vertices. |

## Shortcuts

| Shortcut | Action |
|----------|--------|
| **X** | Cycle brush mode forward (Add → Subtract → Set → Blur → Sharpen). |
| **Y** / **Z** | Cycle brush mode backward (QWERTZ / QWERTY layouts). |
| **1** | Toggle Red channel. |
| **2** | Toggle Green channel. |
| **3** | Toggle Blue channel. |
| **4** | Toggle Alpha channel. |
| **Ctrl + Right Mouse** | Adjust brush size (vertical) and strength (horizontal). |
| **Shift + Right Mouse** | Adjust falloff (vertical) and brush rotation (horizontal). |

## Procedural Tools

- **Top Down**: Paints surfaces facing upward.
- **Slope**: Paints sloped / wall surfaces.
- **Bottom Up**: Paints from bottom to top (e.g. for terrain).
- **Noise**: Applies procedural noise pattern.

Use the **Falloff** slider in settings to control sharpness/softness of procedural results.

## Smart Masking

- **Slope Mask**: Limit painting to surfaces within a slope angle. Invert to paint only steep surfaces.
- **Curvature Mask**: Limit painting to flat or curved areas based on neighbor-normal similarity.
- **Preview Smart Mask**: Temporary white/black overlay on the mesh showing which vertices would pass the active masks (does not change painted data).

## Projection (Settings)

- **Both sides** (default): Paint affects all vertices inside the brush volume.
- **Front only**: Only vertices facing the raycast hit normal are painted (reduces accidental back-face painting on thin geometry).

## Vertex color preview

- **Show vertex colors**: Renders painted colors as an overlay on top of your materials while editing.
- **VC overlay**: Slider for overlay strength (0 = invisible, 1 = full vertex colors).

Undo/redo and painting update this overlay automatically when it is enabled.

## Bake & Revert

- **Bake**: Saves vertex colors into a new mesh resource file (`.res` / `.tres`). The `VertexColorData` child node is removed; colors are permanent on that mesh resource.
- **Bake to Scene**: Bakes all `VertexColorData` nodes under the ancestor scene file (`.tscn`, `.scn`, `.gltf`, `.glb`), saves that scene, and reloads it. Requires the scene to be saved to disk first.
- **Revert**: Restores the mesh from `_vertex_paint_original_path` metadata and removes `VertexColorData` / preview materials.

**Important**: Revert is irreversible once the original file is overwritten. Use with care.

## Paint snapshot (Blender reimport)

When you replace mesh geometry in Blender and reimport, use **Export Paint Snapshot** and **Transfer from Snapshot** in the dock. See the addon doc [VERTEX_COLOR_TRANSFER.md](../game/addons/nexus_vertex_painter/docs/VERTEX_COLOR_TRANSFER.md) (path after install: `addons/nexus_vertex_painter/docs/VERTEX_COLOR_TRANSFER.md`).

## Project Settings

- **nexus/vertex_painter/collision_layer** (1–32): Physics layer used for paint raycasts.
- **nexus/vertex_painter/debug_logging**: Enable extra debug output in the Output panel.

## Supported Meshes

Only **ArrayMesh** is supported. Primitive meshes (BoxMesh, SphereMesh, etc.) are not supported for painting.

On the **first paint stroke**, meshes that store colors only in `ARRAY_CUSTOM` (e.g. Blender face-corner layers) are normalized to `ARRAY_COLOR` so painting and GPU sync work reliably. The original mesh path is stored for **Revert**.

For performance tips (uncompressed glTF, sync modes), see [PERFORMANCE.md](../game/addons/nexus_vertex_painter/docs/PERFORMANCE.md).

## 5-Layer Vertex Color Material Shader

Use the shader `vertex_color_material_blend.gdshader` to blend up to five materials based on vertex colors (RGBA channels). Each channel controls one layer’s influence.

### Setup

1. Create a **ShaderMaterial** and assign `addons/nexus_vertex_painter/shaders/vertex_color_material_blend.gdshader`.
2. For each layer, assign up to 3 textures:
   - **ORM** (R=AO, G=Roughness, B=Metallic)
   - **Albedo** (base color)
   - **Normal** (normal map)
3. Optional: Use **ORM** and **Normal** textures for multiple layers if they share the same properties.
4. Paint vertex colors: **Red** = layer 2, **Green** = layer 3, **Blue** = layer 4, **Alpha** = layer 5. Black = layer 1 (base).

### Parameters

- **UV Scale**: Scale factor for texture coordinates.
- **Blend Softness**: Softens transitions between layers (0 = hard edges).
- **Normal Scale**: Strength of the normal map effect.
