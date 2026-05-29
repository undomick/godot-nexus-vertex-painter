#include "vertex_painter_core.h"
#include "vertex_painter_constants.h"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_data_tool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cmath>

namespace godot {

namespace {

enum PaintMode {
	MODE_ADD = 0,
	MODE_SUB = 1,
	MODE_SET = 2,
	MODE_BLUR = 3,
	MODE_SHARPEN = 4,
};

double pow4(double x) {
	double x2 = x * x;
	return x2 * x2;
}

double sample_image_at_uv(Image *img, double u, double v) {
	if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) {
		return 0.0;
	}
	int w = img->get_width();
	int h = img->get_height();
	if (w <= 0 || h <= 0) {
		return 0.0;
	}
	int x = (int)(u * (w - 1));
	int y = (int)(v * (h - 1));
	Color c = img->get_pixel(x, y);
	return c.r * c.a;
}

Vector2 rotate_uv(const Vector2 &uv, double angle) {
	Vector2 pivot(0.5, 0.5);
	double s = std::sin(angle);
	double c = std::cos(angle);
	Vector2 centered = uv - pivot;
	Vector2 rotated(centered.x * c - centered.y * s, centered.x * s + centered.y * c);
	return rotated + pivot;
}

Vector2 triplanar_face_uv(
		Vector2 raw_uv,
		bool flip_x_if_backface,
		bool is_backface,
		bool flip_x_always,
		double uv_scale,
		double brush_angle) {
	if (flip_x_if_backface && is_backface) {
		raw_uv.x = -raw_uv.x;
	}
	if (flip_x_always) {
		raw_uv.x = -raw_uv.x;
	}
	Vector2 uv = raw_uv * uv_scale + Vector2(0.5, 0.5);
	uv.y = 1.0 - uv.y;
	return rotate_uv(uv, brush_angle);
}

Vector3 triplanar_blend_weights(const Vector3 &normal) {
	Vector3 blending = normal.abs();
	blending.x = pow4(blending.x);
	blending.y = pow4(blending.y);
	blending.z = pow4(blending.z);
	double sum = blending.x + blending.y + blending.z;
	if (sum > 0.00001) {
		return blending / sum;
	}
	return Vector3(0, 1, 0);
}

double get_triplanar_sample(
		const Vector3 &brush_pos,
		const Vector3 &vert_pos,
		const Vector3 &vert_normal,
		double radius,
		double brush_angle,
		Image *img) {
	if (radius <= 0.0) {
		return 0.0;
	}

	Vector3 blending = triplanar_blend_weights(vert_normal);
	Vector3 rel_pos = vert_pos - brush_pos;
	double uv_scale = 1.0 / (radius * 2.0);

	Vector2 uv_y = triplanar_face_uv(
			Vector2(rel_pos.x, rel_pos.z),
			true, vert_normal.y < 0.0, true, uv_scale, brush_angle);
	Vector2 uv_z = triplanar_face_uv(
			Vector2(rel_pos.x, rel_pos.y),
			true, vert_normal.z < 0.0, false, uv_scale, brush_angle);
	Vector2 uv_x = triplanar_face_uv(
			Vector2(rel_pos.z, rel_pos.y),
			true, vert_normal.x < 0.0, true, uv_scale, brush_angle);

	double val_x = sample_image_at_uv(img, uv_x.x, uv_x.y);
	double val_y = sample_image_at_uv(img, uv_y.x, uv_y.y);
	double val_z = sample_image_at_uv(img, uv_z.x, uv_z.y);
	return val_x * blending.x + val_y * blending.y + val_z * blending.z;
}

double radial_falloff_weight(double dist, double brush_size, double falloff) {
	double hard_limit = 1.0 - falloff;
	double normalized = dist / brush_size;
	if (normalized <= hard_limit) {
		return 1.0;
	}
	double t = (normalized - hard_limit) / (1.0 - hard_limit);
	return 1.0 - t;
}

double texture_brush_weight(
		double dist,
		double brush_size,
		Image *brush_img,
		const Vector3 &world_pos,
		const Vector3 &world_normal,
		const Vector3 &brush_pos_global,
		double brush_angle) {
	double tex_val = get_triplanar_sample(
			brush_pos_global, world_pos, world_normal, brush_size, brush_angle, brush_img);
	const double edge_softness = 0.05;
	double t = (dist - (brush_size - edge_softness)) / edge_softness;
	if (t < 0.0) {
		t = 0.0;
	}
	if (t > 1.0) {
		t = 1.0;
	}
	return tex_val * (1.0 - t);
}

bool vertex_inside_brush_aabb(const Vector3 &v_pos, const Vector3 &local_hit, double brush_size) {
	if (std::abs(v_pos.x - local_hit.x) > brush_size) {
		return false;
	}
	if (std::abs(v_pos.y - local_hit.y) > brush_size) {
		return false;
	}
	if (std::abs(v_pos.z - local_hit.z) > brush_size) {
		return false;
	}
	return true;
}

bool vertex_fails_slope_mask(
		const Vector3 &normal,
		const Basis &world_basis,
		double slope_angle_cos,
		bool slope_invert) {
	Vector3 world_normal = world_basis.xform(normal).normalized();
	double dot = world_normal.dot(Vector3(0, 1, 0));
	if (slope_invert) {
		return dot > slope_angle_cos;
	}
	return dot < slope_angle_cos;
}

bool vertex_fails_front_projection(
		const Vector3 &local_normal,
		const Basis &world_basis,
		const Vector3 &hit_normal_world,
		bool front_face_only) {
	if (!front_face_only || hit_normal_world.length_squared() < 1e-8) {
		return false;
	}
	Vector3 world_normal = world_basis.xform(local_normal).normalized();
	return world_normal.dot(hit_normal_world) <= 0.0;
}

bool vertex_fails_curvature_mask(
		int vertex_idx,
		const Vector3 &my_normal,
		const PackedVector3Array &normals,
		const Dictionary &neighbor_map,
		double curv_sensitivity,
		bool curv_invert) {
	if (!neighbor_map.has(vertex_idx)) {
		return false;
	}
	PackedInt32Array neighbors = neighbor_map[vertex_idx];
	if (neighbors.is_empty()) {
		return false;
	}

	Vector3 avg_normal(0, 0, 0);
	for (int j = 0; j < neighbors.size(); j++) {
		int n_idx = neighbors[j];
		if (n_idx < normals.size()) {
			avg_normal += normals[n_idx];
		}
	}
	avg_normal = (avg_normal / (double)neighbors.size()).normalized();
	double flatness = my_normal.dot(avg_normal);
	double threshold = 1.0 - (curv_sensitivity * 0.2);
	if (curv_invert) {
		return flatness < threshold;
	}
	return flatness > threshold;
}

Vector4 average_neighbor_channels(
		int vertex_idx,
		const Color &center,
		const PackedColorArray &neighbor_colors,
		const Dictionary &neighbor_map,
		int vertex_count,
		const Vector4 &channels) {
	Vector4 avg(0, 0, 0, 0);
	double count = 0.0;
	PackedInt32Array neighbors = neighbor_map[vertex_idx];
	for (int j = 0; j < neighbors.size(); j++) {
		int n_idx = neighbors[j];
		if (n_idx < 0 || n_idx >= vertex_count) {
			continue;
		}
		Color nc = neighbor_colors[n_idx];
		avg.x += (channels.x > 0) ? nc.r : center.r;
		avg.y += (channels.y > 0) ? nc.g : center.g;
		avg.z += (channels.z > 0) ? nc.b : center.b;
		avg.w += (channels.w > 0) ? nc.a : center.a;
		count += 1.0;
	}
	if (count > 0.0) {
		avg /= count;
	}
	return avg;
}

void lerp_active_channels(Color &color, const Vector4 &target, const Vector4 &channels, double t) {
	if (channels.x > 0) {
		color.r = (float)Math::lerp((double)color.r, (double)target.x, t);
	}
	if (channels.y > 0) {
		color.g = (float)Math::lerp((double)color.g, (double)target.y, t);
	}
	if (channels.z > 0) {
		color.b = (float)Math::lerp((double)color.b, (double)target.z, t);
	}
	if (channels.w > 0) {
		color.a = (float)Math::lerp((double)color.a, (double)target.w, t);
	}
}

void sharpen_active_channels(Color &color, const Vector4 &neighbor_avg, const Vector4 &channels, double amount) {
	if (channels.x > 0) {
		color.r = CLAMP(color.r + (color.r - neighbor_avg.x) * amount, 0.0, 1.0);
	}
	if (channels.y > 0) {
		color.g = CLAMP(color.g + (color.g - neighbor_avg.y) * amount, 0.0, 1.0);
	}
	if (channels.z > 0) {
		color.b = CLAMP(color.b + (color.b - neighbor_avg.z) * amount, 0.0, 1.0);
	}
	if (channels.w > 0) {
		color.a = CLAMP(color.a + (color.a - neighbor_avg.w) * amount, 0.0, 1.0);
	}
}

void add_sub_active_channels(Color &color, const Vector4 &channels, double delta) {
	if (channels.x > 0) {
		color.r = CLAMP(color.r + delta, 0.0, 1.0);
	}
	if (channels.y > 0) {
		color.g = CLAMP(color.g + delta, 0.0, 1.0);
	}
	if (channels.z > 0) {
		color.b = CLAMP(color.b + delta, 0.0, 1.0);
	}
	if (channels.w > 0) {
		color.a = CLAMP(color.a + delta, 0.0, 1.0);
	}
}

} // namespace

void VertexPainterCore::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("paint_surface",
					"positions", "normals", "colors", "local_hit",
					"radius_sq", "brush_size", "falloff", "strength", "mode", "channels",
					"brush_image", "brush_angle", "brush_pos_global", "mesh_global_transform",
					"neighbor_map", "use_slope_mask", "slope_angle_cos", "slope_invert",
					"use_curv_mask", "curv_sensitivity", "curv_invert",
					"front_face_only", "hit_normal_world"),
			&VertexPainterCore::paint_surface);

	ClassDB::bind_method(
			D_METHOD("build_neighbor_cache", "mesh", "surface_idx"),
			&VertexPainterCore::build_neighbor_cache);

	ClassDB::bind_method(
			D_METHOD("fill_surface", "colors", "channels", "is_fill"),
			&VertexPainterCore::fill_surface);

	ClassDB::bind_method(
			D_METHOD("apply_colors_to_mesh", "source_mesh", "surface_colors", "surface_materials"),
			&VertexPainterCore::apply_colors_to_mesh);

	ClassDB::bind_method(
			D_METHOD("pack_colors_to_rgba8", "colors"),
			&VertexPainterCore::pack_colors_to_rgba8);

	ClassDB::bind_method(D_METHOD("get_version"), &VertexPainterCore::get_version);
	ClassDB::bind_method(D_METHOD("get_author"), &VertexPainterCore::get_author);
}

String VertexPainterCore::get_version() const {
	return String(vertex_painter::kVersion);
}

String VertexPainterCore::get_author() const {
	return String(vertex_painter::kAuthor);
}

PackedColorArray VertexPainterCore::paint_surface(
		const PackedVector3Array &p_positions,
		const PackedVector3Array &p_normals,
		const PackedColorArray &p_colors,
		const Vector3 &p_local_hit,
		double p_radius_sq,
		double p_brush_size,
		double p_falloff,
		double p_strength,
		int p_mode,
		const Vector4 &p_channels,
		const Ref<Image> &p_brush_image,
		double p_brush_angle,
		const Vector3 &p_brush_pos_global,
		const Transform3D &p_mesh_global_transform,
		const Dictionary &p_neighbor_map,
		bool p_use_slope_mask,
		double p_slope_angle_cos,
		bool p_slope_invert,
		bool p_use_curv_mask,
		double p_curv_sensitivity,
		bool p_curv_invert,
		bool p_front_face_only,
		const Vector3 &p_hit_normal_world) {

	if (p_brush_size <= 0.0 || p_falloff >= 1.0) {
		return p_colors;
	}

	int vertex_count = p_positions.size();
	if (p_colors.size() < (size_t)vertex_count) {
		return p_colors;
	}

	PackedColorArray colors = p_colors;
	PackedColorArray neighbor_colors;
	bool needs_neighbor_snapshot = (p_mode == MODE_BLUR || p_mode == MODE_SHARPEN);
	if (needs_neighbor_snapshot) {
		neighbor_colors = colors;
	}

	const Basis &world_basis = p_mesh_global_transform.basis;
	Image *brush_img = p_brush_image.ptr();
	bool has_brush_texture = brush_img && brush_img->get_width() > 0 && brush_img->get_height() > 0;

	for (int i = 0; i < vertex_count; i++) {
		Vector3 v_pos = p_positions[i];
		if (!vertex_inside_brush_aabb(v_pos, p_local_hit, p_brush_size)) {
			continue;
		}

		double dist_sq = v_pos.distance_squared_to(p_local_hit);
		if (dist_sq >= p_radius_sq) {
			continue;
		}

		if (p_use_slope_mask && i < p_normals.size()) {
			if (vertex_fails_slope_mask(p_normals[i], world_basis, p_slope_angle_cos, p_slope_invert)) {
				continue;
			}
		}

		if (i < p_normals.size()) {
			if (vertex_fails_front_projection(
						p_normals[i], world_basis, p_hit_normal_world, p_front_face_only)) {
				continue;
			}
		}

		if (p_use_curv_mask && i < p_normals.size()) {
			if (vertex_fails_curvature_mask(
						i, p_normals[i], p_normals, p_neighbor_map,
						p_curv_sensitivity, p_curv_invert)) {
				continue;
			}
		}

		Color color = colors[i];
		double dist = std::sqrt(dist_sq);
		double weight = 0.0;

		if (has_brush_texture) {
			Vector3 world_pos = p_mesh_global_transform.xform(v_pos);
			Vector3 world_normal(0, 1, 0);
			if (i < p_normals.size()) {
				world_normal = world_basis.xform(p_normals[i]).normalized();
			}
			weight = texture_brush_weight(
					dist, p_brush_size, brush_img, world_pos, world_normal,
					p_brush_pos_global, p_brush_angle);
		} else {
			weight = radial_falloff_weight(dist, p_brush_size, p_falloff);
		}

		if (p_mode == MODE_BLUR || p_mode == MODE_SHARPEN) {
			if (!p_neighbor_map.has(i)) {
				continue;
			}
			PackedInt32Array neighbors = p_neighbor_map[i];
			if (neighbors.is_empty()) {
				continue;
			}

			Vector4 neighbor_avg = average_neighbor_channels(
					i, color, neighbor_colors, p_neighbor_map, vertex_count, p_channels);
			double neighbor_strength = p_strength * weight * 0.5;

			if (p_mode == MODE_BLUR) {
				lerp_active_channels(color, neighbor_avg, p_channels, neighbor_strength);
			} else {
				sharpen_active_channels(color, neighbor_avg, p_channels, neighbor_strength);
			}
		} else if (p_mode == MODE_SET) {
			Vector4 target(p_strength, p_strength, p_strength, p_strength);
			lerp_active_channels(color, target, p_channels, weight);
		} else {
			double delta = p_strength * weight;
			if (p_mode == MODE_SUB) {
				delta = -delta;
			}
			add_sub_active_channels(color, p_channels, delta);
		}

		colors[i] = color;
	}

	return colors;
}

Dictionary VertexPainterCore::build_neighbor_cache(const Ref<ArrayMesh> &p_mesh, int p_surface_idx) {
	Dictionary result;
	if (p_mesh.is_null()) {
		return result;
	}

	Ref<MeshDataTool> mdt;
	mdt.instantiate();
	if (mdt->create_from_surface(p_mesh, p_surface_idx) != OK) {
		return result;
	}

	int vert_count = mdt->get_vertex_count();
	for (int v = 0; v < vert_count; v++) {
		PackedInt32Array n_list;
		PackedInt32Array edge_indices = mdt->get_vertex_edges(v);
		for (int j = 0; j < edge_indices.size(); j++) {
			int edge_idx = edge_indices[j];
			int v1 = mdt->get_edge_vertex(edge_idx, 0);
			int v2 = mdt->get_edge_vertex(edge_idx, 1);
			int other = (v1 == v) ? v2 : v1;
			n_list.append(other);
		}
		result[v] = n_list;
	}
	return result;
}

PackedColorArray VertexPainterCore::fill_surface(
		const PackedColorArray &p_colors,
		const Vector4 &p_channels,
		bool p_is_fill) {
	PackedColorArray colors = p_colors;
	double value = p_is_fill ? 1.0 : 0.0;
	for (int i = 0; i < colors.size(); i++) {
		Color c = colors[i];
		if (p_channels.x > 0) {
			c.r = value;
		}
		if (p_channels.y > 0) {
			c.g = value;
		}
		if (p_channels.z > 0) {
			c.b = value;
		}
		if (p_channels.w > 0) {
			c.a = value;
		}
		colors[i] = c;
	}
	return colors;
}

static PackedColorArray build_surface_colors(const Variant &p_colors_var, int p_vertex_count) {
	PackedColorArray colors;
	colors.resize(p_vertex_count);
	colors.fill(Color(0, 0, 0, 1));
	if (p_colors_var.get_type() == Variant::PACKED_COLOR_ARRAY) {
		PackedColorArray src_colors = p_colors_var;
		const int copy_count = MIN(p_vertex_count, src_colors.size());
		for (int i = 0; i < copy_count; i++) {
			colors[i] = src_colors[i];
		}
	}
	return colors;
}

static bool apply_surface_via_arrays(
		ArrayMesh *p_result,
		ArrayMesh *p_source,
		int p_surf_idx,
		const Dictionary &p_surface_colors,
		const Dictionary &p_surface_materials) {
	const uint64_t fmt = p_source->surface_get_format(p_surf_idx);
	if (fmt & (uint64_t)Mesh::ARRAY_FLAG_COMPRESS_ATTRIBUTES) {
		return false;
	}

	Array arrays = p_source->surface_get_arrays(p_surf_idx);
	if (arrays.is_empty() || arrays.size() < Mesh::ARRAY_MAX) {
		return false;
	}

	Variant verts_var = arrays[Mesh::ARRAY_VERTEX];
	if (verts_var.get_type() != Variant::PACKED_VECTOR3_ARRAY) {
		return false;
	}
	const PackedVector3Array verts = verts_var;
	if (verts.is_empty()) {
		return false;
	}

	const int vertex_count = verts.size();
	Variant colors_var = p_surface_colors.get(p_surf_idx, Variant());
	arrays[Mesh::ARRAY_COLOR] = build_surface_colors(colors_var, vertex_count);

	const int count_before = p_result->get_surface_count();
	p_result->add_surface_from_arrays(
			Mesh::PRIMITIVE_TRIANGLES,
			arrays,
			TypedArray<Array>(),
			Dictionary(),
			0);

	if (p_result->get_surface_count() == count_before) {
		return false;
	}

	const int last_surface = p_result->get_surface_count() - 1;
	Variant mat_var = p_surface_materials.get(p_surf_idx, Variant());
	if (mat_var.get_type() == Variant::OBJECT) {
		Ref<Material> mat(mat_var);
		if (mat.is_valid()) {
			p_result->surface_set_material(last_surface, mat);
		}
	}
	return true;
}

static bool apply_surface_via_mdt(
		ArrayMesh *p_result,
		const Ref<Mesh> &p_source_mesh,
		int p_surf_idx,
		const Dictionary &p_surface_colors,
		const Dictionary &p_surface_materials) {
	Ref<MeshDataTool> mdt;
	mdt.instantiate();
	if (mdt->create_from_surface(p_source_mesh, p_surf_idx) != OK) {
		return false;
	}

	const int vertex_count = mdt->get_vertex_count();
	const int face_count = mdt->get_face_count();

	uint64_t fmt = 0;
	ArrayMesh *arr_mesh = Object::cast_to<ArrayMesh>(p_source_mesh.ptr());
	if (arr_mesh) {
		fmt = arr_mesh->surface_get_format(p_surf_idx);
	} else {
		fmt = mdt->get_format();
	}

	const uint32_t FMT_TEX_UV = (uint32_t)Mesh::ARRAY_FORMAT_TEX_UV;
	const uint32_t FMT_TEX_UV2 = (uint32_t)Mesh::ARRAY_FORMAT_TEX_UV2;
	const uint32_t FMT_TANGENT = (uint32_t)Mesh::ARRAY_FORMAT_TANGENT;

	PackedVector3Array vertices;
	vertices.resize(vertex_count);
	PackedVector3Array normals;
	normals.resize(vertex_count);

	for (int i = 0; i < vertex_count; i++) {
		vertices[i] = mdt->get_vertex(i);
		normals[i] = mdt->get_vertex_normal(i);
	}

	Variant colors_var = p_surface_colors.get(p_surf_idx, Variant());
	PackedColorArray colors = build_surface_colors(colors_var, vertex_count);

	PackedInt32Array indices;
	indices.resize(face_count * 3);
	for (int f = 0; f < face_count; f++) {
		indices[f * 3 + 0] = mdt->get_face_vertex(f, 0);
		indices[f * 3 + 1] = mdt->get_face_vertex(f, 1);
		indices[f * 3 + 2] = mdt->get_face_vertex(f, 2);
	}

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = vertices;
	arrays[Mesh::ARRAY_NORMAL] = normals;
	arrays[Mesh::ARRAY_COLOR] = colors;
	arrays[Mesh::ARRAY_INDEX] = indices;

	if (fmt & FMT_TEX_UV) {
		PackedVector2Array uvs;
		uvs.resize(vertex_count);
		for (int i = 0; i < vertex_count; i++) {
			uvs[i] = mdt->get_vertex_uv(i);
		}
		arrays[Mesh::ARRAY_TEX_UV] = uvs;
	}
	if (fmt & FMT_TEX_UV2) {
		PackedVector2Array uv2;
		uv2.resize(vertex_count);
		for (int i = 0; i < vertex_count; i++) {
			uv2[i] = mdt->get_vertex_uv2(i);
		}
		arrays[Mesh::ARRAY_TEX_UV2] = uv2;
	}
	if (fmt & FMT_TANGENT) {
		PackedFloat32Array tangents;
		tangents.resize(vertex_count * 4);
		for (int i = 0; i < vertex_count; i++) {
			Plane t = mdt->get_vertex_tangent(i);
			tangents[i * 4 + 0] = t.normal.x;
			tangents[i * 4 + 1] = t.normal.y;
			tangents[i * 4 + 2] = t.normal.z;
			tangents[i * 4 + 3] = t.d;
		}
		arrays[Mesh::ARRAY_TANGENT] = tangents;
	}

	uint64_t build_flags = 0;
	if (fmt & (uint64_t)Mesh::ARRAY_FLAG_COMPRESS_ATTRIBUTES) {
		build_flags = 0;
	} else if (fmt & (uint64_t)Mesh::ARRAY_FLAG_USE_DYNAMIC_UPDATE) {
		build_flags = Mesh::ARRAY_FLAG_USE_DYNAMIC_UPDATE;
	}

	const int count_before = p_result->get_surface_count();
	p_result->add_surface_from_arrays(
			Mesh::PRIMITIVE_TRIANGLES,
			arrays,
			TypedArray<Array>(),
			Dictionary(),
			build_flags);

	if (p_result->get_surface_count() == count_before) {
		return false;
	}

	const int last_surface = p_result->get_surface_count() - 1;
	Variant mat_var = p_surface_materials.get(p_surf_idx, Variant());
	if (mat_var.get_type() == Variant::OBJECT) {
		Ref<Material> mat(mat_var);
		if (mat.is_valid()) {
			p_result->surface_set_material(last_surface, mat);
		}
	}
	return true;
}

Ref<ArrayMesh> VertexPainterCore::apply_colors_to_mesh(
		const Ref<Mesh> &p_source_mesh,
		const Dictionary &p_surface_colors,
		const Dictionary &p_surface_materials) {
	Ref<ArrayMesh> result;
	if (p_source_mesh.is_null()) {
		return result;
	}

	ArrayMesh *source_mesh = Object::cast_to<ArrayMesh>(p_source_mesh.ptr());

	result.instantiate();
	result->clear_surfaces();

	const int surface_count = p_source_mesh->get_surface_count();
	for (int surf_idx = 0; surf_idx < surface_count; surf_idx++) {
		bool added = false;
		if (source_mesh) {
			added = apply_surface_via_arrays(result.ptr(), source_mesh, surf_idx, p_surface_colors, p_surface_materials);
		}
		if (!added) {
			apply_surface_via_mdt(result.ptr(), p_source_mesh, surf_idx, p_surface_colors, p_surface_materials);
		}
	}

	return result;
}

PackedByteArray VertexPainterCore::pack_colors_to_rgba8(const PackedColorArray &p_colors) {
	PackedByteArray result;
	int n = p_colors.size();
	result.resize(n * 4);
	uint8_t *dst = result.ptrw();
	for (int i = 0; i < n; i++) {
		Color c = p_colors[i];
		int ofs = i * 4;
		dst[ofs + 0] = (uint8_t)c.get_r8();
		dst[ofs + 1] = (uint8_t)c.get_g8();
		dst[ofs + 2] = (uint8_t)c.get_b8();
		dst[ofs + 3] = (uint8_t)c.get_a8();
	}
	return result;
}

}
