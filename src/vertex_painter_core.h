#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class VertexPainterCore : public RefCounted {
	GDCLASS(VertexPainterCore, RefCounted)

protected:
	static void _bind_methods();

public:
	VertexPainterCore() = default;
	~VertexPainterCore() override = default;

	PackedColorArray paint_surface(
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
			const Vector3 &p_hit_normal_world);

	Dictionary build_neighbor_cache(const Ref<ArrayMesh> &p_mesh, int p_surface_idx);

	PackedColorArray fill_surface(const PackedColorArray &p_colors, const Vector4 &p_channels, bool p_is_fill);

	Ref<ArrayMesh> apply_colors_to_mesh(
			const Ref<Mesh> &p_source_mesh,
			const Dictionary &p_surface_colors,
			const Dictionary &p_surface_materials);

	PackedByteArray pack_colors_to_rgba8(const PackedColorArray &p_colors);

	String get_version() const;
	String get_author() const;
};

}
