extends Node
## Tests for CUSTOM / ARRAY_COLOR channel detection and mesh normalization.

var _errors: Array[String] = []


func _ready() -> void:
	_run_all_tests()
	if _errors.is_empty():
		print("SurfaceColorBinding: All tests passed.")
	else:
		for e in _errors:
			push_error(e)


func _fail(msg: String) -> void:
	_errors.append("FAIL: " + msg)


func _create_mesh_custom0_only() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0.5, 1, 0),
	])
	var norms := PackedVector3Array([
		Vector3(0, 1, 0),
		Vector3(0, 1, 0),
		Vector3(0, 1, 0),
	])
	var rgba := PackedByteArray()
	rgba.resize(12)
	rgba[0] = 255
	rgba[4] = 0
	rgba[5] = 255
	rgba[8] = 0
	rgba[9] = 0
	rgba[10] = 255
	rgba[3] = 255
	rgba[7] = 255
	rgba[11] = 255

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_CUSTOM0] = rgba
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])

	var custom_flags: int = Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var flags: int = custom_flags | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


func _create_mesh_color_and_bone_custom0() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0.5, 1, 0),
	])
	var norms := PackedVector3Array([
		Vector3(0, 1, 0),
		Vector3(0, 1, 0),
		Vector3(0, 1, 0),
	])
	var colors := PackedColorArray([
		Color(0.2, 0.3, 0.4, 1.0),
		Color(0.5, 0.6, 0.7, 1.0),
		Color(0.8, 0.9, 1.0, 1.0),
	])
	var weights := PackedFloat32Array()
	weights.resize(12)
	for i in range(3):
		weights[i * 4] = 1.0

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = weights
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])

	var custom_flags: int = Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var flags: int = custom_flags | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


func test_detect_custom0_channel() -> void:
	var mesh: ArrayMesh = _create_mesh_custom0_only()
	var channel: int = SurfaceColorBinding.detect_color_channel(mesh, 0)
	if channel != Mesh.ARRAY_CUSTOM0:
		_fail("Expected CUSTOM0 channel, got %s" % SurfaceColorBinding.channel_label(channel))


func test_read_custom0_colors() -> void:
	var mesh: ArrayMesh = _create_mesh_custom0_only()
	var colors: PackedColorArray = SurfaceColorBinding.read_surface_colors(mesh, 0)
	if colors.size() != 3:
		_fail("Expected 3 custom colors, got %d" % colors.size())
		return
	if colors[0].r < 0.9:
		_fail("Expected red on vertex 0, got %s" % str(colors[0]))


func test_normalize_custom0_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _create_mesh_custom0_only()
	add_child(mesh_instance)

	var data_node := VertexColorData.new()
	data_node.name = "VertexColorData"
	mesh_instance.add_child(data_node)
	data_node.initialize_from_mesh()

	if not data_node.mesh_needs_color_normalize(mesh_instance.mesh):
		_fail("CUSTOM-only mesh should need color normalize")

	var normalized: bool = data_node.ensure_paintable_color_mesh()
	if not normalized:
		_fail("ensure_paintable_color_mesh should return true on first call")

	var fmt: int = mesh_instance.mesh.surface_get_format(0)
	if (fmt & Mesh.ARRAY_FORMAT_COLOR) == 0:
		_fail("Normalized mesh should have ARRAY_COLOR")

	if data_node.surface_data.is_empty():
		_fail("surface_data should contain imported custom colors")


func test_live_upload_with_color_and_bone_custom() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _create_mesh_color_and_bone_custom0()
	add_child(mesh_instance)

	var data_node := VertexColorData.new()
	mesh_instance.add_child(data_node)
	data_node._bind_paint_mesh_from_parent()

	if not data_node.surface_supports_live_color_upload(0):
		_fail("Mesh with ARRAY_COLOR and bone CUSTOM0 should support live color upload")


func _run_all_tests() -> void:
	test_detect_custom0_channel()
	test_read_custom0_colors()
	test_normalize_custom0_mesh()
	test_live_upload_with_color_and_bone_custom()
