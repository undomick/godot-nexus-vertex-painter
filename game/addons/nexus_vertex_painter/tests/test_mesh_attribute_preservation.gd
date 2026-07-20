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
	test_runtime_mesh_enables_fast_color_path()
	test_custom_uv3_preserved_after_apply_colors()
	test_multi_surface_materials_preserved()
	test_original_path_topology_mismatch_keeps_current_mesh()
	test_float_custom_rebuild_keeps_mesh()
	test_arrays_sync_never_wipes_live_mesh()
	test_revert_resolves_glb_subresource_path()
	test_bake_scene_path_needs_reimport()


func _create_mesh_with_uvs_and_custom_uv3() -> ArrayMesh:
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
	var uvs = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(0.5, 1.0)
	])
	var uv2 = PackedVector2Array([
		Vector2(0.25, 0.25),
		Vector2(0.75, 0.25),
		Vector2(0.5, 0.75)
	])
	var uv3 = PackedFloat32Array([
		0.11, 0.22,
		0.33, 0.44,
		0.55, 0.66,
	])
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_CUSTOM0] = uv3
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])

	var custom_flags: int = Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, custom_flags)
	return mesh


func _get_custom0_floats(mesh: Mesh, surf_idx: int) -> PackedFloat32Array:
	if not mesh is ArrayMesh:
		return PackedFloat32Array()
	var format: int = mesh.surface_get_format(surf_idx)
	if (format & Mesh.ARRAY_FORMAT_CUSTOM0) == 0:
		return PackedFloat32Array()
	var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(surf_idx)
	if arrays.size() <= Mesh.ARRAY_CUSTOM0:
		return PackedFloat32Array()
	var data: Variant = arrays[Mesh.ARRAY_CUSTOM0]
	if data is PackedFloat32Array:
		return data as PackedFloat32Array
	return PackedFloat32Array()


func test_custom_uv3_preserved_after_apply_colors() -> void:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _create_mesh_with_uvs_and_custom_uv3()
	add_child(mesh_instance)

	var original_custom: PackedFloat32Array = _get_custom0_floats(mesh_instance.mesh, 0)
	if original_custom.size() != 6:
		_fail("UV3 setup: expected 6 CUSTOM0 floats, got %d" % original_custom.size())
		return

	var data_node = VertexColorData.new()
	data_node.name = "VertexColorData"
	mesh_instance.add_child(data_node)
	data_node.initialize_from_mesh()
	data_node.surface_data[0] = PackedColorArray([
		Color(1, 0, 0, 1),
		Color(0, 1, 0, 1),
		Color(0, 0, 1, 1),
	])
	data_node._apply_colors()

	var result_mesh = mesh_instance.mesh
	if result_mesh == null:
		_fail("UV3: mesh is null after _apply_colors")
		return

	var result_custom: PackedFloat32Array = _get_custom0_floats(result_mesh, 0)
	if result_custom.size() != original_custom.size():
		_fail("UV3: CUSTOM0 size changed from %d to %d (extra UVs wiped)" % [
			original_custom.size(), result_custom.size()])
		return

	for i in range(original_custom.size()):
		if not is_equal_approx(original_custom[i], result_custom[i]):
			_fail("UV3: CUSTOM0[%d] changed from %s to %s" % [
				i, str(original_custom[i]), str(result_custom[i])])
			return


func test_multi_surface_materials_preserved() -> void:
	var arr0 := []
	arr0.resize(Mesh.ARRAY_MAX)
	arr0[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0.5, 1, 0)])
	arr0[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 1, 0)])
	arr0[Mesh.ARRAY_COLOR] = PackedColorArray([
		Color.WHITE, Color.WHITE, Color.WHITE])
	arr0[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])

	var arr1 := arr0.duplicate(true)

	var mat0 := StandardMaterial3D.new()
	mat0.albedo_color = Color(1, 0, 0)
	var mat1 := StandardMaterial3D.new()
	mat1.albedo_color = Color(0, 1, 0)

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr0)
	mesh.surface_set_material(0, mat0)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr1)
	mesh.surface_set_material(1, mat1)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	var data_node = VertexColorData.new()
	mesh_instance.add_child(data_node)
	data_node.initialize_from_mesh()
	data_node.surface_data[0] = PackedColorArray([Color.RED, Color.RED, Color.RED])
	data_node.surface_data[1] = PackedColorArray([Color.GREEN, Color.GREEN, Color.GREEN])
	data_node._apply_colors()

	var result: Mesh = mesh_instance.mesh
	if result == null or result.get_surface_count() < 2:
		_fail("Materials: expected 2 surfaces after apply")
		return

	var r0: Material = result.surface_get_material(0)
	var r1: Material = result.surface_get_material(1)
	if r0 != mat0:
		_fail("Materials: surface 0 material was lost or replaced")
	if r1 != mat1:
		_fail("Materials: surface 1 material was lost or replaced")


## Door-style bug: meta points at a multi-surface "original" while the instance has a
## different 1-surface mesh. Paint rebuild must keep the current topology.
func test_original_path_topology_mismatch_keeps_current_mesh() -> void:
	var current := _create_mesh_with_uvs()
	var current_verts: int = current.surface_get_array_len(0)

	var other_arr := []
	other_arr.resize(Mesh.ARRAY_MAX)
	other_arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(1, 2, 0),
		Vector3(0, 0, 1), Vector3(2, 0, 1), Vector3(1, 2, 1)])
	other_arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 1, 0)])
	other_arr[Mesh.ARRAY_COLOR] = PackedColorArray([
		Color.WHITE, Color.WHITE, Color.WHITE,
		Color.WHITE, Color.WHITE, Color.WHITE])
	other_arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var other_mesh := ArrayMesh.new()
	other_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, other_arr)
	other_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, other_arr.duplicate(true))
	other_mesh.resource_path = "res://addons/nexus_vertex_painter/tests/_fake_original_multi.mesh"

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = current
	mesh_instance.set_meta("_vertex_paint_original_path", other_mesh.resource_path)
	# Keep other_mesh alive via a dummy load path simulation: inject into ResourceLoader
	# is not possible; instead verify _pick_source_mesh ignores meta and uses current.
	add_child(mesh_instance)

	var data_node := VertexColorData.new()
	mesh_instance.add_child(data_node)
	data_node.initialize_from_mesh()

	var picked: Mesh = data_node._pick_source_mesh(mesh_instance, current)
	if picked != current:
		_fail("Topology: _pick_source_mesh must return current mesh, not original_path target")
		return

	data_node.surface_data[0] = PackedColorArray([
		Color(1, 0, 0, 1), Color(0, 1, 0, 1), Color(0, 0, 1, 1)])
	data_node._apply_colors()

	var result: Mesh = mesh_instance.mesh
	if result == null:
		_fail("Topology: mesh became null after apply")
		return
	if result.get_surface_count() != 1:
		_fail("Topology: expected 1 surface after apply, got %d" % result.get_surface_count())
		return
	if result.surface_get_array_len(0) != current_verts:
		_fail("Topology: vertex count changed from %d to %d" % [
			current_verts, result.surface_get_array_len(0)])
		return

	# Keep other_mesh referenced so GDScript does not free it mid-test.
	if other_mesh.get_surface_count() < 2:
		_fail("Topology setup: other mesh should have 2 surfaces")


## Float CUSTOM with wrong/default format bits must still rebuild (Door PACKED_BYTE_ARRAY case).
func test_float_custom_rebuild_keeps_mesh() -> void:
	var mesh: ArrayMesh = _create_mesh_with_uvs_and_custom_uv3()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	var data_node := VertexColorData.new()
	mesh_instance.add_child(data_node)
	data_node.initialize_from_mesh()
	data_node.surface_data[0] = PackedColorArray([
		Color(1, 0, 0, 1), Color(0, 1, 0, 1), Color(0, 0, 1, 1)])
	data_node._apply_colors()

	var result: Mesh = mesh_instance.mesh
	if result == null or result.get_surface_count() < 1:
		_fail("Float CUSTOM: mesh lost surfaces after _apply_colors")
		return
	if result.surface_get_array_len(0) != 3:
		_fail("Float CUSTOM: vertex count changed after rebuild")


## Arrays sync must not clear parent.mesh in-place when rebuild would fail.
func test_arrays_sync_never_wipes_live_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _create_mesh_with_uvs_and_custom_uv3()
	add_child(mesh_instance)

	var data_node := VertexColorData.new()
	mesh_instance.add_child(data_node)
	data_node.initialize_from_mesh()
	data_node._bind_paint_mesh_from_parent()
	# Force alias condition that previously wiped the live mesh.
	data_node._runtime_mesh = mesh_instance.mesh as ArrayMesh
	data_node.surface_data[0] = PackedColorArray([
		Color(0.2, 0.3, 0.4, 1), Color(0.5, 0.6, 0.7, 1), Color(0.8, 0.9, 1.0, 1)])
	data_node._sync_colors_via_arrays_runtime_mesh()

	var result: Mesh = mesh_instance.mesh
	if result == null or result.get_surface_count() < 1:
		_fail("Alias sync: live mesh was wiped (0 surfaces)")
		return
	if result.surface_get_array_len(0) != 3:
		_fail("Alias sync: unexpected vertex count after sync")


## Revert must resolve imported GLB paths (res://file.glb::ArrayMesh_xxx).
func test_revert_resolves_glb_subresource_path() -> void:
	var glb_path := "res://props/assets/_door_/door1.glb"
	if not ResourceLoader.exists(glb_path):
		return

	var scene := load(glb_path) as PackedScene
	if scene == null:
		_fail("Revert GLB: could not load PackedScene")
		return

	var inst: Node = scene.instantiate()
	var want_path: String = ""
	var surface_count: int = 0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst.mesh and mesh_inst.mesh.resource_path.contains("::"):
			want_path = mesh_inst.mesh.resource_path
			surface_count = mesh_inst.mesh.get_surface_count()
			break
	inst.free()

	if want_path.is_empty():
		_fail("Revert GLB: no MeshInstance3D with :: resource_path in door1.glb")
		return

	var bake := VertexPaintBake.new()
	var loaded: Mesh = bake.load_mesh_from_original_path(want_path)
	if loaded == null:
		_fail("Revert GLB: load_mesh_from_original_path returned null for %s" % want_path)
		return
	if loaded.get_surface_count() != surface_count:
		_fail("Revert GLB: surface count mismatch after resolve")


func test_bake_scene_path_needs_reimport() -> void:
	if VertexPaintBake.scene_path_needs_reimport("res://foo.tscn"):
		_fail("Bake: .tscn must not use reimport_files")
	if VertexPaintBake.scene_path_needs_reimport("res://foo.scn"):
		_fail("Bake: .scn must not use reimport_files")
	if not VertexPaintBake.scene_path_needs_reimport("res://foo.glb"):
		_fail("Bake: .glb should use reimport_files")
	if not VertexPaintBake.scene_path_needs_reimport("res://foo.gltf"):
		_fail("Bake: .gltf should use reimport_files")


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


func test_runtime_mesh_enables_fast_color_path() -> void:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _create_mesh_with_uvs()
	add_child(mesh_instance)

	var data_node = VertexColorData.new()
	data_node.name = "VertexColorData"
	mesh_instance.add_child(data_node)
	data_node.initialize_from_mesh()
	data_node._apply_colors()

	var runtime: ArrayMesh = mesh_instance.mesh as ArrayMesh
	if runtime == null:
		_fail("Fast path: runtime mesh is not ArrayMesh")
		return

	data_node._cache_source_arrays(runtime)
	data_node._detect_paint_sync_mode(runtime)

	var colors := data_node.surface_data[0] as PackedColorArray
	colors[0] = Color(1, 0, 0, 1)
	var uploaded: bool = false
	if data_node._uses_arrays_color_sync(0):
		data_node._sync_colors_via_arrays_runtime_mesh()
		uploaded = true
	elif data_node._try_fast_color_update(0, colors):
		uploaded = true
	if not uploaded:
		_fail("Color upload: arrays sync and attribute path both failed")
