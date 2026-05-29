# Vertex Color Transfer (Mesh Reimport Workflow)

When you replace a mesh in Blender and reimport (new FBX/glTF), vertex indices change and painted colors stored in `VertexColorData` no longer match. This workflow preserves colors **approximately** using world-space nearest-neighbor matching.

## Recommended workflow

1. Paint vertex colors in Godot (optionally **Bake to Scene** for a backup in the scene file).
2. Select the `MeshInstance3D` and click **Export Paint Snapshot** (`.tres` or `.vcpaint`).
3. Edit geometry in Blender and export/reimport.
4. Select the new `MeshInstance3D` (same scene placement helps).
5. Adjust **Transfer max dist** and options if needed.
6. Click **Transfer from Snapshot** and pick the saved file.
7. Review with **Show vertex colors**, touch up by hand, then **Bake** when done.

## Transfer settings

| Setting | Description |
|---------|-------------|
| Transfer max dist | Maximum world-space distance to match a snapshot point |
| Normal filter | Ignore snapshot points on the opposite-facing side |
| Unmatched verts | **Black** or **Nearest** when no snapshot point is within max distance (Nearest uses the closest snapshot vertex regardless of distance) |

## Blender color attributes

If your mesh uses face-corner or custom-named color layers, paint in the Vertex Painter first (the addon normalizes to `ARRAY_COLOR` on the first stroke) or export vertex-domain `COLOR_0` from Blender for direct compatibility.

## Limitations

- Not a 1:1 replacement for Blender's Data Transfer modifier.
- New geometry, large retopo, or moved/scaled instances may need manual fixes.
- Overlapping geometry (mirrors, stacked shells) can pick the wrong neighbor.
- Performance uses a GDScript spatial grid; very large meshes (>500k snapshot points) may be slow.

## Performance note

C++ acceleration for transfer is not implemented yet; the GDScript grid hash is sufficient for typical terrain chunks. Report slow cases if you need a native path.

## Related docs

- User-facing overview: repository [USER_MANUAL.md](../../../../docs/USER_MANUAL.md) (Paint snapshot section)
- Painting performance: [PERFORMANCE.md](PERFORMANCE.md)
