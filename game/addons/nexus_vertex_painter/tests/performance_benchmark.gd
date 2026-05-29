extends Node
## Performance benchmark: paint_surface, prep_cache, and GPU sync paths.
## Launched by run_performance.gd (runs in _ready when engine is ready).

const VERTEX_COUNTS := [5_000, 20_000, 50_000]
const WARMUP_RUNS := 1
const BENCHMARK_RUNS := 3
const STROKE_DABS := 50

var _results: Array[Dictionary] = []


func _ready() -> void:
	print("=== Nexus Vertex Painter Performance Benchmark ===")
	print("")
	_run_paint_surface_benchmark()
	print("")
	_run_prep_cache_benchmark()
	print("")
	_run_gpu_sync_benchmark()
	print("")
	_print_results()


func _run_paint_surface_benchmark() -> void:
	var has_cpp := ClassDB.class_exists("VertexPainterCore")
	var cpp_core = null
	if has_cpp:
		cpp_core = ClassDB.instantiate("VertexPainterCore")
		if not cpp_core:
			has_cpp = false

	print("C++ GDExtension available: %s" % has_cpp)
	print("")

	for vert_count in VERTEX_COUNTS:
		print("  paint_surface @ %d vertices..." % vert_count)
		var positions := _create_positions(vert_count)
		var normals := _create_normals(vert_count)
		var colors := _create_colors(vert_count)

		var local_hit := Vector3(0.5, 0.5, 0.5)
		var radius_sq := 1.0
		var brush_size := 1.0
		var falloff := 0.5
		var strength := 0.25
		var mode := 0
		var channels := Vector4(1, 1, 1, 1)
		var brush_image: Image = null
		var brush_angle := 0.0
		var brush_pos_global := Vector3(0.5, 0.5, 0.5)
		var mesh_transform := Transform3D.IDENTITY
		var neighbor_map := {}
		var use_slope_mask := false
		var slope_angle_cos := 0.0
		var slope_invert := false
		var use_curv_mask := false
		var curv_sensitivity := 0.5
		var curv_invert := false

		var result := {"vertices": vert_count, "cpp_ms": 0.0, "gd_ms": 0.0, "prep_arrays_ms": 0.0,
			"prep_mdt_ms": 0.0, "gpu_arrays_ms": 0.0, "gpu_attrib_ms": 0.0}

		if has_cpp and cpp_core:
			for r in range(WARMUP_RUNS):
				var colors_copy := colors.duplicate()
				cpp_core.paint_surface(
					positions, normals, colors_copy, local_hit,
					radius_sq, brush_size, falloff, strength, mode, channels,
					brush_image, brush_angle, brush_pos_global, mesh_transform,
					neighbor_map, use_slope_mask, slope_angle_cos, slope_invert,
					use_curv_mask, curv_sensitivity, curv_invert,
					false, Vector3.UP
				)
			var cpp_times: Array[float] = []
			for r in range(BENCHMARK_RUNS):
				var colors_copy := colors.duplicate()
				var t0 := Time.get_ticks_usec()
				cpp_core.paint_surface(
					positions, normals, colors_copy, local_hit,
					radius_sq, brush_size, falloff, strength, mode, channels,
					brush_image, brush_angle, brush_pos_global, mesh_transform,
					neighbor_map, use_slope_mask, slope_angle_cos, slope_invert,
					use_curv_mask, curv_sensitivity, curv_invert,
					false, Vector3.UP
				)
				cpp_times.append((Time.get_ticks_usec() - t0) / 1000.0)
			cpp_times.sort()
			result["cpp_ms"] = cpp_times[BENCHMARK_RUNS / 2]

		for r in range(WARMUP_RUNS):
			var colors_copy := colors.duplicate()
			_paint_surface_gdscript(
				positions, normals, colors_copy, local_hit,
				radius_sq, brush_size, falloff, strength, channels
			)
		var gd_times: Array[float] = []
		for r in range(BENCHMARK_RUNS):
			var colors_copy := colors.duplicate()
			var t0 := Time.get_ticks_usec()
			_paint_surface_gdscript(
				positions, normals, colors_copy, local_hit,
				radius_sq, brush_size, falloff, strength, channels
			)
			gd_times.append((Time.get_ticks_usec() - t0) / 1000.0)
		gd_times.sort()
		result["gd_ms"] = gd_times[BENCHMARK_RUNS / 2]

		_results.append(result)


func _run_prep_cache_benchmark() -> void:
	print("prep_cache (20k verts, single surface):")
	var mesh := _make_test_mesh(20_000)
	var data := VertexColorData.new()

	for r in range(WARMUP_RUNS):
		data._prep_cache(mesh)

	var t0 := Time.get_ticks_usec()
	data._prep_cache(mesh)
	var arrays_ms := (Time.get_ticks_usec() - t0) / 1000.0

	if _results.size() > 0:
		_results[1]["prep_arrays_ms"] = arrays_ms
	print("  surface_get_arrays path: %.2f ms" % arrays_ms)


func _run_gpu_sync_benchmark() -> void:
	print("gpu sync (20k verts, %d dabs):" % STROKE_DABS)
	var mesh := _make_test_mesh(20_000)
	var data := _make_data_node_with_mesh(mesh)
	data._cache_source_arrays(mesh)
	data._detect_paint_sync_mode(mesh)
	data.surface_data[0] = _create_colors(20_000)

	for r in range(WARMUP_RUNS):
		data._sync_colors_via_arrays_runtime_mesh()

	var t0 := Time.get_ticks_usec()
	for i in range(STROKE_DABS):
		data.surface_data[0] = data.surface_data[0].duplicate()
		data._sync_colors_via_arrays_runtime_mesh()
	var arrays_ms := (Time.get_ticks_usec() - t0) / 1000.0 / float(STROKE_DABS)

	if _results.size() > 0:
		_results[1]["gpu_arrays_ms"] = arrays_ms
	print("  arrays runtime sync / dab: %.2f ms" % arrays_ms)


func _make_test_mesh(vertex_count: int) -> ArrayMesh:
	var positions := _create_positions(vertex_count)
	var normals := _create_normals(vertex_count)
	var colors := _create_colors(vertex_count)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_data_node_with_mesh(mesh: ArrayMesh) -> VertexColorData:
	var data := VertexColorData.new()
	var parent := MeshInstance3D.new()
	parent.mesh = mesh
	parent.add_child(data)
	data._source_mesh = mesh
	data._runtime_mesh = mesh
	data._prep_cache(mesh)
	return data


func _paint_surface_gdscript(
		positions: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray,
		local_hit: Vector3,
		radius_sq: float,
		brush_size: float,
		falloff: float,
		strength: float,
		channels: Vector4
) -> void:
	var vertex_count := positions.size()
	for i in range(vertex_count):
		var v_pos := positions[i]

		if abs(v_pos.x - local_hit.x) > brush_size: continue
		if abs(v_pos.y - local_hit.y) > brush_size: continue
		if abs(v_pos.z - local_hit.z) > brush_size: continue

		var dist_sq := v_pos.distance_squared_to(local_hit)
		if dist_sq >= radius_sq: continue

		var color := colors[i]
		var dist := sqrt(dist_sq)
		var weight: float
		var hard_limit := 1.0 - falloff
		if dist / brush_size > hard_limit:
			var t := ((dist / brush_size) - hard_limit) / (1.0 - hard_limit)
			weight = 1.0 - t
		else:
			weight = 1.0

		var blend_op := 1.0
		var s := strength * weight * blend_op
		if channels.x > 0: color.r = clamp(color.r + s, 0.0, 1.0)
		if channels.y > 0: color.g = clamp(color.g + s, 0.0, 1.0)
		if channels.z > 0: color.b = clamp(color.b + s, 0.0, 1.0)
		if channels.w > 0: color.a = clamp(color.a + s, 0.0, 1.0)

		colors[i] = color


func _create_positions(n: int) -> PackedVector3Array:
	var arr := PackedVector3Array()
	arr.resize(n)
	for i in range(n):
		arr[i] = Vector3(randf(), randf(), randf())
	return arr


func _create_normals(n: int) -> PackedVector3Array:
	var arr := PackedVector3Array()
	arr.resize(n)
	var up := Vector3(0, 1, 0)
	for i in range(n):
		arr[i] = up
	return arr


func _create_colors(n: int) -> PackedColorArray:
	var arr := PackedColorArray()
	arr.resize(n)
	arr.fill(Color.BLACK)
	return arr


func _print_results() -> void:
	print("| Vertices | C++ (ms) | GDScript (ms) | Speedup |")
	print("|----------|----------|---------------|--------|")

	var total_speedup := 0.0
	var speedup_count := 0

	for r in _results:
		var speedup := 0.0
		if r["cpp_ms"] > 0.0:
			speedup = r["gd_ms"] / r["cpp_ms"]
			total_speedup += speedup
			speedup_count += 1

		var speedup_str := "-"
		if speedup > 0.0:
			speedup_str = "%.1fx" % speedup

		print("| %s | %s | %s | %s |" % [
			str(r["vertices"]),
			"%.1f" % r["cpp_ms"] if r["cpp_ms"] > 0 else "-",
			"%.1f" % r["gd_ms"],
			speedup_str
		])

	if speedup_count > 0:
		print("")
		print("Average C++ speedup: %.1fx" % (total_speedup / speedup_count))

	if _results.size() > 1:
		var mid: Dictionary = _results[1]
		print("")
		print("GPU / cache (20k): prep_cache=%.2f ms, arrays_sync/dab=%.2f ms" % [
			mid.get("prep_arrays_ms", 0.0),
			mid.get("gpu_arrays_ms", 0.0)
		])
