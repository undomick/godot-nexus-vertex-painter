extends Node

const Preview := preload("res://addons/nexus_vertex_painter/vertex_paint_preview.gd")

var _errors: Array[String] = []


func _ready() -> void:
	_test_vertex_location_mesh()
	if _errors.is_empty():
		print("test_vertex_location_preview: OK")
	else:
		for err in _errors:
			push_error("test_vertex_location_preview: " + err)


func _fail(message: String) -> void:
	_errors.append(message)


func _add_triangle_surface(
		mesh: ArrayMesh,
		vertices: PackedVector3Array,
		normals: PackedVector3Array) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if not normals.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _test_vertex_location_mesh() -> void:
	var source_mesh := ArrayMesh.new()
	var vertices_with_normals := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
	])
	var normals := PackedVector3Array([
		Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD,
	])
	var vertices_without_normals := PackedVector3Array([
		Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(2, 1, 0),
	])
	_add_triangle_surface(source_mesh, vertices_with_normals, normals)
	_add_triangle_surface(source_mesh, vertices_with_normals, normals)
	_add_triangle_surface(source_mesh, vertices_without_normals, PackedVector3Array())

	var preview: VertexPaintPreview = Preview.new()
	var point_mesh := preview._build_vertex_location_mesh(source_mesh)
	if point_mesh.get_surface_count() != 1:
		_fail("expected one combined point surface")
		return

	if point_mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_POINTS:
		_fail("vertex locations must use point primitives")
		return
	var arrays := point_mesh.surface_get_arrays(0)
	var point_positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if point_positions.size() != vertices_with_normals.size() + vertices_without_normals.size():
		_fail("point surface did not merge duplicate vertex locations")
	var marker_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if marker_colors.size() != point_positions.size():
		_fail("point surface did not retain normal availability")
		return
	if marker_colors[0].a != 1.0 or marker_colors[vertices_with_normals.size()].a != 0.0:
		_fail("point surface did not retain normal availability")
