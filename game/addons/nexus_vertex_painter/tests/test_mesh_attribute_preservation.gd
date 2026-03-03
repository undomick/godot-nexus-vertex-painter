extends Node
## Tests that mesh attributes (UVs, tangents, etc.) are NOT lost during vertex color painting.
## Run via: godot --path game --headless --script res://addons/nexus_vertex_painter/tests/run_tests.gd
##
## These tests verify the full pipeline: create mesh -> VertexColorData -> update_surface_colors
## -> _apply_colors -> mesh on MeshInstance3D. If UVs or other attributes are lost, the test fails.

var _errors: Array[String] = []


func _ready() -> void:
	_run_all_tests()
	if _errors.is_empty():
		print("Mesh Attribute Preservation: All tests passed.")
	else:
		for e in _errors:
			push_error(e)


func _fail(msg: String) -> void:
	_errors.append("FAIL: " + msg)


## Creates a triangle mesh with UVs (required for texture mapping, displacement, 5-layer shaders).
func _create_mesh_with_uvs() -> ArrayMesh:
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
		Color(0.2, 0.3, 0.4, 1.0),
		Color(0.5, 0.6, 0.7, 1.0),
		Color(0.8, 0.9, 1.0, 1.0)
	])
	# Distinct UVs - if these are lost, textures will be wrong
	var uvs = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(0.5, 1.0)
	])
	var indices = PackedInt32Array([0, 1, 2])

	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Extracts UVs from a mesh surface via MeshDataTool (works with compressed format).
## Returns null if surface has no UVs.
func _get_surface_uvs(mesh: Mesh, surf_idx: int) -> PackedVector2Array:
	var mdt = MeshDataTool.new()
	if mdt.create_from_surface(mesh, surf_idx) != OK:
		return PackedVector2Array()
	var format = mesh.surface_get_format(surf_idx)
	if (format & Mesh.ARRAY_FORMAT_TEX_UV) == 0:
		return PackedVector2Array()
	var vc = mdt.get_vertex_count()
	var uvs = PackedVector2Array()
	uvs.resize(vc)
	for i in range(vc):
		uvs[i] = mdt.get_vertex_uv(i)
	return uvs


## Extracts vertex colors from mesh (for comparison).
func _get_surface_colors(mesh: Mesh, surf_idx: int) -> PackedColorArray:
	var mdt = MeshDataTool.new()
	if mdt.create_from_surface(mesh, surf_idx) != OK:
		return PackedColorArray()
	var vc = mdt.get_vertex_count()
	var colors = PackedColorArray()
	colors.resize(vc)
	for i in range(vc):
		colors[i] = mdt.get_vertex_color(i)
	return colors


## Checks if mesh surface has UV format.
func _surface_has_uvs(mesh: Mesh, surf_idx: int) -> bool:
	if surf_idx < 0 or surf_idx >= mesh.get_surface_count():
		return false
	var format = mesh.surface_get_format(surf_idx)
	return (format & Mesh.ARRAY_FORMAT_TEX_UV) != 0


func test_uvs_preserved_via_manual_apply() -> void:
	# Same as above but call _apply_colors directly (no deferred) for deterministic test
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _create_mesh_with_uvs()
	add_child(mesh_instance)

	var original_uvs = _get_surface_uvs(mesh_instance.mesh, 0)
	if original_uvs.size() != 3:
		_fail("UV manual: original mesh should have 3 UVs, got " + str(original_uvs.size()))
		return

	var data_node = VertexColorData.new()
	data_node.name = "VertexColorData"
	mesh_instance.add_child(data_node)

	data_node.initialize_from_mesh()
	data_node.surface_data[0] = PackedColorArray([
		Color(0.5, 0.5, 0.5, 1),
		Color(0.5, 0.5, 0.5, 1),
		Color(0.5, 0.5, 0.5, 1)
	])
	data_node._apply_colors()

	var result_mesh = mesh_instance.mesh
	if result_mesh == null:
		_fail("UV manual: mesh is null after _apply_colors")
		return

	if not _surface_has_uvs(result_mesh, 0):
		_fail("UV manual: result mesh has NO UV format - UVs were LOST")

	var result_uvs = _get_surface_uvs(result_mesh, 0)
	if result_uvs.size() != original_uvs.size():
		_fail("UV manual: UV count changed from %d to %d" % [original_uvs.size(), result_uvs.size()])
		return

	for i in range(original_uvs.size()):
		if not original_uvs[i].is_equal_approx(result_uvs[i]):
			_fail("UV manual: UV[%d] changed from %s to %s" % [i, original_uvs[i], result_uvs[i]])
			return


func test_meshdatatool_commit_preserves_uvs() -> void:
	# Direct test: does MeshDataTool.commit_to_surface preserve UVs when we only set colors?
	var source = _create_mesh_with_uvs()
	var original_uvs = _get_surface_uvs(source, 0)
	if original_uvs.size() != 3:
		_fail("MDT direct: source should have 3 UVs")
		return

	var mdt = MeshDataTool.new()
	if mdt.create_from_surface(source, 0) != OK:
		_fail("MDT direct: create_from_surface failed")
		return

	for i in range(3):
		mdt.set_vertex_color(i, Color(1, 0, 0, 1))

	var result_mesh = ArrayMesh.new()
	mdt.commit_to_surface(result_mesh)

	var result_uvs = _get_surface_uvs(result_mesh, 0)
	if result_uvs.size() != 3:
		_fail("MDT direct: commit_to_surface produced mesh with %d UVs" % result_uvs.size())
		return

	for i in range(3):
		if not original_uvs[i].is_equal_approx(result_uvs[i]):
			_fail("MDT direct: MeshDataTool.commit_to_surface LOST UV[%d]: %s -> %s" % [i, original_uvs[i], result_uvs[i]])
			return


func _run_all_tests() -> void:
	test_meshdatatool_commit_preserves_uvs()
	test_uvs_preserved_via_manual_apply()
	test_uvs_preserved_after_apply_colors_sync()


func test_uvs_preserved_after_apply_colors_sync() -> void:
	# Synchronous version - call _apply_colors directly after update_surface_colors
	# (update_surface_colors uses _try_fast_color_update or _apply_colors internally)
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _create_mesh_with_uvs()
	add_child(mesh_instance)

	var original_uvs = _get_surface_uvs(mesh_instance.mesh, 0)
	if original_uvs.size() != 3:
		_fail("UV sync: original mesh should have 3 UVs, got " + str(original_uvs.size()))
		return

	var data_node = VertexColorData.new()
	data_node.name = "VertexColorData"
	mesh_instance.add_child(data_node)

	data_node.initialize_from_mesh()
	var new_colors = PackedColorArray([
		Color(0.9, 0.1, 0.2, 1),
		Color(0.1, 0.9, 0.2, 1),
		Color(0.1, 0.2, 0.9, 1)
	])
	data_node.update_surface_colors(0, new_colors)

	var result_mesh = mesh_instance.mesh
	if result_mesh == null:
		_fail("UV sync: mesh is null after update_surface_colors")
		return

	if not _surface_has_uvs(result_mesh, 0):
		_fail("UV sync: result mesh has NO UV format - UVs were LOST (update_surface_colors path)")

	var result_uvs = _get_surface_uvs(result_mesh, 0)
	if result_uvs.size() != original_uvs.size():
		_fail("UV sync: UV count changed from %d to %d" % [original_uvs.size(), result_uvs.size()])
		return

	for i in range(original_uvs.size()):
		if not original_uvs[i].is_equal_approx(result_uvs[i]):
			_fail("UV sync: UV[%d] changed from %s to %s" % [i, original_uvs[i], result_uvs[i]])
			return
