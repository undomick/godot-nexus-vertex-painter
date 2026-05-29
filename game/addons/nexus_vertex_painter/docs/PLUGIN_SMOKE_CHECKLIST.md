# Editor smoke checklist

Use after plugin or GDExtension changes (CI unit tests do not cover the full editor UI).

## Automated

```bash
cd game
godot --path . --headless --script res://addons/nexus_vertex_painter/tests/run_tests.gd
```

Expected: VertexColorData, mesh attribute preservation, and surface color binding suites pass.

Optional performance run:

```bash
godot --path . --headless --script res://addons/nexus_vertex_painter/tests/run_performance.gd
```

## Manual (editor)

1. Enable **Vertex Paint** on a `MeshInstance3D` (colliders appear).
2. Paint stroke; **Undo** / **Redo** updates the viewport immediately.
3. **Show vertex colors** on/off; adjust **VC overlay** strength.
4. **Preview Smart Mask** with slope/curvature masks.
5. **Fill** / **Clear** / **Procedural** tools.
6. **Bake** (`.res`), **Bake to Scene**, **Revert**.
7. **Export Paint Snapshot** (save dialog, `.tres` with point count in Output) / **Transfer from Snapshot** (see [VERTEX_COLOR_TRANSFER.md](VERTEX_COLOR_TRANSFER.md)).
8. **Revert** only restores meshes that have `_vertex_paint_original_path` (not the snapshot workflow).
