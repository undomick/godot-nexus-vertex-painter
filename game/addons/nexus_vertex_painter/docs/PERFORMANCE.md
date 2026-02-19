# Nexus Vertex Painter – Performance

## Benchmark (v1.6 vs v2.0)

A performance benchmark compares the C++ GDExtension with the GDScript fallback.

### Run the benchmark

1. **From command line** (Godot in PATH):
   ```bash
   cd game
   godot --path . --headless --script res://addons/nexus_vertex_painter/tests/run_performance.gd
   ```

2. **Windows**: Double-click `addons/nexus_vertex_painter/tests/run_performance.bat`  
   Edit the batch file to set `GODOT_PATH` to your Godot executable if needed.

3. **With full path**:
   ```bash
   "C:\Path\To\Godot.exe" --path "C:\Path\To\nexus_vertexpainter\game" --headless --script res://addons/nexus_vertex_painter/tests/run_performance.gd
   ```

### Reference results (Godot 4.6, Windows)

```
=== Nexus Vertex Painter Performance Benchmark ===

C++ GDExtension available: true

  Benchmarking 5000 vertices...
  Benchmarking 20000 vertices...
  Benchmarking 50000 vertices...
  Benchmarking 100000 vertices...

| Vertices | C++ (ms) | GDScript (ms) | Speedup |
|----------|----------|---------------|--------|
| 5000     | 0.1      | 3.0           | 31.2x  |
| 20000    | 0.4      | 12.2          | 30.1x  |
| 50000    | 1.0      | 30.3          | 29.9x  |
| 100000   | 2.2      | 60.9          | 27.5x  |

Average C++ speedup: 29.7x
```

**Migration v1.6 → v2.0:** ca. **30x schneller** für paint_surface (ADD mode) bei Nutzung der C++ GDExtension. Ergebnisse können je nach Hardware variieren (typisch 20x–35x).
