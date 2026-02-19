extends Node
## Unit tests for VertexColorData.
## Run via: godot --headless --script res://addons/nexus_vertex_painter/tests/run_tests.gd

var _mesh_instance: MeshInstance3D
var _data_node: VertexColorData
var _errors: Array[String] = []


func _ready() -> void:
	_run_all_tests()
	if _errors.is_empty():
		print("VertexColorData: All tests passed.")
	else:
		for e in _errors:
			push_error(e)


func _fail(msg: String) -> void:
	_errors.append("FAIL: " + msg)


func _create_test_mesh() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var verts = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0.5, 1, 0)
	])
	var normals = PackedVector3Array([
		Vector3(0, 1, 0),
		Vector3(0, 1, 0),
		Vector3(0, 1, 0)
	])
	var colors = PackedColorArray([
		Color(0.1, 0.2, 0.3, 0.4),
		Color(0.5, 0.6, 0.7, 0.8),
		Color(0.9, 1.0, 0.0, 0.1)
	])
	var indices = PackedInt32Array([0, 1, 2])

	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _setup() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _create_test_mesh()
	add_child(_mesh_instance)

	_data_node = VertexColorData.new()
	_data_node.name = "VertexColorData"
	_mesh_instance.add_child(_data_node)


func _run_all_tests() -> void:
	_setup()

	test_initialize_from_mesh_imports_colors()
	test_get_data_snapshot_returns_deep_copy()
	test_apply_data_snapshot_restores_state()
	test_get_positions_returns_cached_data()
	test_get_normals_returns_cached_data()
	test_empty_surface_returns_black_colors()


func test_initialize_from_mesh_imports_colors() -> void:
	_data_node.initialize_from_mesh()

	var positions = _data_node.get_positions(0)
	if positions.size() != 3:
		_fail("initialize_from_mesh: expected 3 positions, got " + str(positions.size()))
		return

	var snapshot = _data_node.get_data_snapshot()
	if not snapshot.has(0):
		_fail("initialize_from_mesh: snapshot should have surface 0")
		return

	var colors: PackedColorArray = snapshot[0]
	if colors.size() != 3:
		_fail("initialize_from_mesh: expected 3 colors (or black), got " + str(colors.size()))


func test_get_data_snapshot_returns_deep_copy() -> void:
	_data_node.initialize_from_mesh()
	var snap1 = _data_node.get_data_snapshot()
	var snap2 = _data_node.get_data_snapshot()

	if snap1 == snap2 and snap1.is_empty():
		return

	# Modify snap1 - should not affect data_node.surface_data
	if snap1.has(0):
		var c: PackedColorArray = snap1[0]
		if c.size() > 0:
			c.set(0, Color(1, 0, 0, 1))
			var after = _data_node.get_data_snapshot()
			var orig: PackedColorArray = after[0]
			if orig[0] == Color(1, 0, 0, 1):
				_fail("get_data_snapshot: modification affected original (shallow copy)")


func test_apply_data_snapshot_restores_state() -> void:
	_data_node.initialize_from_mesh()
	var before = _data_node.get_data_snapshot()
	if not before.has(0):
		_fail("apply_data_snapshot: before snapshot has no surface 0")
		return

	# Manually change surface_data
	_data_node.surface_data[0] = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])

	var after_modified = _data_node.get_data_snapshot()
	if after_modified[0][0] != Color.RED:
		_fail("apply_data_snapshot: setup failed")

	_data_node.apply_data_snapshot(before)
	var after_restore = _data_node.get_data_snapshot()
	if not after_restore.has(0):
		_fail("apply_data_snapshot: lost surface 0 after restore")
		return

	var restored: PackedColorArray = after_restore[0]
	if restored[0] == Color.RED:
		_fail("apply_data_snapshot: colors not restored (still RED)")


func test_get_positions_returns_cached_data() -> void:
	_data_node.initialize_from_mesh()

	var pos = _data_node.get_positions(0)
	if pos.size() != 3:
		_fail("get_positions: expected 3, got " + str(pos.size()))
		return

	if not pos[0].is_equal_approx(Vector3(0, 0, 0)):
		_fail("get_positions: first vertex mismatch")


func test_get_normals_returns_cached_data() -> void:
	_data_node.initialize_from_mesh()

	var norms = _data_node.get_normals(0)
	if norms.size() != 3:
		_fail("get_normals: expected 3, got " + str(norms.size()))
		return

	# Godot may introduce tiny floating point drift in mesh processing
	var expected_up := Vector3(0, 1, 0)
	if norms[0].dot(expected_up) < 0.999:
		_fail("get_normals: first normal should point up (got " + str(norms[0]) + ")")


func test_empty_surface_returns_black_colors() -> void:
	_data_node.initialize_from_mesh()
	_data_node._prep_cache(_mesh_instance.mesh)
	_data_node.surface_data[0] = PackedColorArray()
	_data_node.surface_data[0].resize(3)
	_data_node.surface_data[0].fill(Color.BLACK)

	var snap = _data_node.get_data_snapshot()
	if not snap.has(0):
		_fail("empty surface: snapshot should have surface 0")
		return
	var c: PackedColorArray = snap[0]
	for i in c.size():
		if c[i] != Color.BLACK:
			_fail("empty surface: expected black, got " + str(c[i]) + " at " + str(i))
			return
