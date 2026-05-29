@tool
class_name VertexColorPaintSnapshot
extends Resource

const FORMAT_VERSION := 1

@export var format_version: int = FORMAT_VERSION
@export var source_mesh_path: String = ""
@export var mesh_instance_name: String = ""
@export var capture_transform: Transform3D = Transform3D.IDENTITY
@export var world_positions: PackedVector3Array = PackedVector3Array()
@export var world_normals: PackedVector3Array = PackedVector3Array()
@export var colors: PackedColorArray = PackedColorArray()


static func capture_from_mesh_instance(mesh_instance: MeshInstance3D, data_node: VertexColorData = null) -> VertexColorPaintSnapshot:
	var snap := VertexColorPaintSnapshot.new()
	if not mesh_instance or not mesh_instance.mesh:
		return snap

	snap.mesh_instance_name = mesh_instance.name
	if mesh_instance.mesh.resource_path:
		snap.source_mesh_path = mesh_instance.mesh.resource_path
	snap.capture_transform = mesh_instance.global_transform

	if data_node and not data_node.surface_data.is_empty():
		_append_from_vertex_color_data(snap, mesh_instance, data_node)
	elif _mesh_has_vertex_colors(mesh_instance.mesh):
		_append_from_mesh_colors(snap, mesh_instance)
	else:
		VertexPainterLog.warn("No vertex color data to export on '%s'." % mesh_instance.name)

	return snap


static func _append_from_vertex_color_data(
		snap: VertexColorPaintSnapshot,
		mesh_instance: MeshInstance3D,
		data_node: VertexColorData) -> void:
	if data_node._cache_positions.is_empty():
		data_node._prep_cache(mesh_instance.mesh)

	var xform: Transform3D = mesh_instance.global_transform
	var basis: Basis = xform.basis

	for surf_idx in data_node.surface_data.keys():
		var local_positions: PackedVector3Array = data_node.get_positions(surf_idx)
		var local_normals: PackedVector3Array = data_node.get_normals(surf_idx)
		var surf_colors: PackedColorArray = data_node.surface_data[surf_idx]
		var count: int = mini(local_positions.size(), surf_colors.size())
		for i in range(count):
			snap.world_positions.append(xform * local_positions[i])
			if i < local_normals.size():
				snap.world_normals.append((basis * local_normals[i]).normalized())
			else:
				snap.world_normals.append(Vector3.UP)
			snap.colors.append(surf_colors[i])


static func _append_from_mesh_colors(snap: VertexColorPaintSnapshot, mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	var xform: Transform3D = mesh_instance.global_transform
	var basis: Basis = xform.basis

	for surf_idx in range(mesh.get_surface_count()):
		var format: int = mesh.surface_get_format(surf_idx)
		if (format & Mesh.ARRAY_FORMAT_COLOR) == 0:
			continue
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(mesh, surf_idx) != OK:
			continue
		var vc: int = mdt.get_vertex_count()
		for i in range(vc):
			snap.world_positions.append(xform * mdt.get_vertex(i))
			snap.world_normals.append((basis * mdt.get_vertex_normal(i)).normalized())
			snap.colors.append(mdt.get_vertex_color(i))


static func _mesh_has_vertex_colors(mesh: Mesh) -> bool:
	for i in range(mesh.get_surface_count()):
		if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0:
			return true
	return false
