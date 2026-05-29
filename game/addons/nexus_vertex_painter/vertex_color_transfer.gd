class_name VertexColorTransfer
extends RefCounted

const UNMATCHED_BLACK := 0
const UNMATCHED_NEAREST := 1

const _NEIGHBOR_OFFSETS: Array[Vector3i] = [
	Vector3i(-1, -1, -1), Vector3i(0, -1, -1), Vector3i(1, -1, -1),
	Vector3i(-1, 0, -1), Vector3i(0, 0, -1), Vector3i(1, 0, -1),
	Vector3i(-1, 1, -1), Vector3i(0, 1, -1), Vector3i(1, 1, -1),
	Vector3i(-1, -1, 0), Vector3i(0, -1, 0), Vector3i(1, -1, 0),
	Vector3i(-1, 0, 0), Vector3i(0, 0, 0), Vector3i(1, 0, 0),
	Vector3i(-1, 1, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
	Vector3i(-1, -1, 1), Vector3i(0, -1, 1), Vector3i(1, -1, 1),
	Vector3i(-1, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 1),
	Vector3i(-1, 1, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1),
]


static func transfer_to_mesh(
		snapshot: VertexColorPaintSnapshot,
		mesh_instance: MeshInstance3D,
		options: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if snapshot == null or snapshot.colors.is_empty():
		VertexPainterLog.warn("Paint snapshot is empty.")
		return result
	if not mesh_instance or not mesh_instance.mesh:
		VertexPainterLog.warn("Target mesh instance has no mesh.")
		return result

	var max_distance: float = maxf(options.get("max_distance", 0.5), 0.0001)
	var max_dist_sq: float = max_distance * max_distance
	var use_normal_filter: bool = options.get("use_normal_filter", true)
	var unmatched_mode: int = options.get("unmatched_fill", UNMATCHED_BLACK)
	var use_nearest_fallback: bool = unmatched_mode == UNMATCHED_NEAREST

	var spatial_index: Dictionary = _build_spatial_index(snapshot, max_distance)
	var xform: Transform3D = mesh_instance.global_transform
	var basis: Basis = xform.basis
	var mesh: Mesh = mesh_instance.mesh

	for surf_idx in range(mesh.get_surface_count()):
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(mesh, surf_idx) != OK:
			continue
		var vertex_count: int = mdt.get_vertex_count()
		var out_colors := PackedColorArray()
		out_colors.resize(vertex_count)
		for i in range(vertex_count):
			var world_pos: Vector3 = xform * mdt.get_vertex(i)
			var world_normal: Vector3 = (basis * mdt.get_vertex_normal(i)).normalized()
			var nearest_idx: int = _find_nearest_in_index(
					spatial_index, snapshot, world_pos, world_normal, max_dist_sq, use_normal_filter)
			if nearest_idx >= 0:
				out_colors[i] = snapshot.colors[nearest_idx]
			elif use_nearest_fallback:
				var fallback_idx: int = _find_nearest_in_snapshot(
						snapshot, world_pos, world_normal, use_normal_filter)
				if fallback_idx >= 0:
					out_colors[i] = snapshot.colors[fallback_idx]
				else:
					out_colors[i] = Color.BLACK
			else:
				out_colors[i] = Color.BLACK
		result[surf_idx] = out_colors

	return result


static func _build_spatial_index(snapshot: VertexColorPaintSnapshot, max_distance: float) -> Dictionary:
	var cell_size: float = maxf(max_distance, 0.05)
	var cells: Dictionary = {}
	for i in range(snapshot.world_positions.size()):
		var key: Vector3i = _cell_key(snapshot.world_positions[i], cell_size)
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(i)
	return {"cell_size": cell_size, "cells": cells}


static func _find_nearest_in_index(
		spatial_index: Dictionary,
		snapshot: VertexColorPaintSnapshot,
		world_pos: Vector3,
		world_normal: Vector3,
		max_dist_sq: float,
		use_normal_filter: bool) -> int:
	var cells: Dictionary = spatial_index["cells"]
	var best_idx: int = -1
	var best_dist_sq: float = max_dist_sq
	var base_key: Vector3i = _cell_key(world_pos, spatial_index["cell_size"])

	for offset in _NEIGHBOR_OFFSETS:
		var key: Vector3i = base_key + offset
		if not cells.has(key):
			continue
		for src_idx in cells[key]:
			var dist_sq: float = world_pos.distance_squared_to(snapshot.world_positions[src_idx])
			if dist_sq >= best_dist_sq:
				continue
			if use_normal_filter and snapshot.world_normals.size() > src_idx:
				if world_normal.dot(snapshot.world_normals[src_idx]) <= 0.0:
					continue
			best_dist_sq = dist_sq
			best_idx = src_idx

	return best_idx


static func _find_nearest_in_snapshot(
		snapshot: VertexColorPaintSnapshot,
		world_pos: Vector3,
		world_normal: Vector3,
		use_normal_filter: bool) -> int:
	var best_idx: int = -1
	var best_dist_sq: float = INF
	for src_idx in range(snapshot.world_positions.size()):
		var dist_sq: float = world_pos.distance_squared_to(snapshot.world_positions[src_idx])
		if dist_sq >= best_dist_sq:
			continue
		if use_normal_filter and snapshot.world_normals.size() > src_idx:
			if world_normal.dot(snapshot.world_normals[src_idx]) <= 0.0:
				continue
		best_dist_sq = dist_sq
		best_idx = src_idx
	return best_idx


static func _cell_key(pos: Vector3, cell_size: float) -> Vector3i:
	return Vector3i(
			floori(pos.x / cell_size),
			floori(pos.y / cell_size),
			floori(pos.z / cell_size))
