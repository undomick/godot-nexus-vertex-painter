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

## Bake & Revert

- **Bake**: Saves the current vertex colors into the mesh file (`.res`). The `VertexColorData` node is removed and colors become permanent.
- **Revert**: Restores the mesh to its original state from the saved resource path (if available).

**Important**: Revert is irreversible once the original file is overwritten. Use with care.

## Project Settings

- **nexus/vertex_painter/collision_layer** (1–32): Physics layer used for paint raycasts.
- **nexus/vertex_painter/debug_logging**: Enable extra debug output in the Output panel.

## Supported Meshes

Only **ArrayMesh** is supported. Primitive meshes (BoxMesh, SphereMesh, etc.) are not supported for painting.

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
