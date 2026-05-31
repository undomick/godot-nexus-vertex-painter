extends Node

const MeshCombine := preload("res://addons/nexus_vertex_painter/vertex_paint_mesh_combine.gd")

var _errors: Array[String] = []


func _ready() -> void:
	_test_combine_two_boxes()
	_test_centered_origin()
	_test_count_combinable()
	if _errors.is_empty():
		print("test_mesh_combine: OK")
	else:
		for err in _errors:
			push_error("test_mesh_combine: " + err)


func _fail(message: String) -> void:
	_errors.append(message)


func _commit_cuboid(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_cuboid(size)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


func _test_count_combinable() -> void:
	var combiner: VertexPaintMeshCombine = MeshCombine.new()
	var root := Node3D.new()
	add_child(root)
	var a := MeshInstance3D.new()
	a.mesh = _commit_cuboid(Vector3.ONE)
	root.add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = _commit_cuboid(Vector3.ONE * 2.0)
	root.add_child(b)
	if combiner.count_combinable_mesh_instances([a, b]) != 2:
		_fail("expected two combinable meshes")
	root.queue_free()


func _test_combine_two_boxes() -> void:
	var combiner: VertexPaintMeshCombine = MeshCombine.new()
	var root := Node3D.new()
	add_child(root)

	var left := MeshInstance3D.new()
	left.mesh = _commit_cuboid(Vector3.ONE)
	left.position = Vector3(-2, 0, 0)
	root.add_child(left)

	var right := MeshInstance3D.new()
	right.mesh = _commit_cuboid(Vector3.ONE)
	right.position = Vector3(2, 0, 0)
	root.add_child(right)

	var result: Dictionary = combiner.combine_mesh_instances([left, right])
	var combined: ArrayMesh = result.get("mesh")
	if combined == null or combined.get_surface_count() < 1:
		_fail("combined mesh has no surfaces")
	if combined.get_aabb().size.length() < 3.0:
		_fail("combined AABB too small for separated boxes")
	root.queue_free()


func _test_centered_origin() -> void:
	var combiner: VertexPaintMeshCombine = MeshCombine.new()
	var mesh := _commit_cuboid(Vector3(2, 4, 6))
	var centered_result: Dictionary = combiner._center_mesh_at_aabb(mesh)
	var centered: ArrayMesh = centered_result.get("mesh")
	var aabb := centered.get_aabb()
	var center := aabb.position + aabb.size * 0.5
	if center.length() > 0.05:
		_fail("centered mesh origin expected near zero, got %s" % str(center))
