class_name SurfaceColorBinding
extends RefCounted

const CHANNEL_NONE := -1

const _CUSTOM_ARRAY_INDICES: Array[int] = [
	Mesh.ARRAY_CUSTOM0,
	Mesh.ARRAY_CUSTOM1,
	Mesh.ARRAY_CUSTOM2,
	Mesh.ARRAY_CUSTOM3,
]

const _CUSTOM_FORMAT_FLAGS: Array[int] = [
	Mesh.ARRAY_FORMAT_CUSTOM0,
	Mesh.ARRAY_FORMAT_CUSTOM1,
	Mesh.ARRAY_FORMAT_CUSTOM2,
	Mesh.ARRAY_FORMAT_CUSTOM3,
]

const _CUSTOM_FORMAT_SHIFTS: Array[int] = [
	Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT,
	Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT,
	Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT,
	Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT,
]


static func channel_label(channel: int) -> String:
	if channel == Mesh.ARRAY_COLOR:
		return "ARRAY_COLOR"
	if channel >= Mesh.ARRAY_CUSTOM0 and channel <= Mesh.ARRAY_CUSTOM3:
		return "CUSTOM%d" % (channel - Mesh.ARRAY_CUSTOM0)
	if channel == CHANNEL_NONE:
		return "none"
	return "unknown"


static func detect_color_channel(mesh: Mesh, surf_idx: int) -> int:
	if mesh == null or surf_idx < 0 or surf_idx >= mesh.get_surface_count():
		return CHANNEL_NONE

	var format: int = mesh.surface_get_format(surf_idx)
	if (format & Mesh.ARRAY_FORMAT_COLOR) != 0:
		return Mesh.ARRAY_COLOR

	for i in range(_CUSTOM_ARRAY_INDICES.size()):
		if (format & _CUSTOM_FORMAT_FLAGS[i]) == 0:
			continue
		var slot: int = _CUSTOM_ARRAY_INDICES[i]
		if _custom_slot_looks_like_vertex_colors(mesh, surf_idx, slot):
			return slot

	return CHANNEL_NONE


static func read_surface_colors(mesh: Mesh, surf_idx: int, channel: int = CHANNEL_NONE) -> PackedColorArray:
	if mesh == null or surf_idx < 0 or surf_idx >= mesh.get_surface_count():
		return PackedColorArray()

	if channel == CHANNEL_NONE:
		channel = detect_color_channel(mesh, surf_idx)
	if channel == CHANNEL_NONE:
		return PackedColorArray()

	var vertex_count: int = mesh.surface_get_array_len(surf_idx)
	if vertex_count <= 0:
		return PackedColorArray()

	if channel == Mesh.ARRAY_COLOR:
		return _read_array_color(mesh, surf_idx, vertex_count)
	return _read_custom_slot(mesh, surf_idx, channel, vertex_count)


## True when colors should be kept in surface_data (skip engine-default uniform white).
static func colors_are_paintable(colors: PackedColorArray) -> bool:
	if colors.is_empty():
		return false
	var first: Color = colors[0]
	var sample_count: int = mini(colors.size(), 128)
	for i in range(1, sample_count):
		if _color_diff_sq(colors[i], first) > 0.000001:
			return true
	if first.is_equal_approx(Color.WHITE):
		return false
	return true


static func mesh_has_array_color_channel(mesh: Mesh) -> bool:
	if mesh == null:
		return false
	for i in range(mesh.get_surface_count()):
		if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0:
			return true
	return false


static func _read_array_color(mesh: Mesh, surf_idx: int, vertex_count: int) -> PackedColorArray:
	if mesh is ArrayMesh:
		var format: int = mesh.surface_get_format(surf_idx)
		if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0:
			var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(surf_idx)
			if arrays.size() > Mesh.ARRAY_COLOR:
				var data: Variant = arrays[Mesh.ARRAY_COLOR]
				if data is PackedColorArray:
					return _resize_colors(data as PackedColorArray, vertex_count)

	var mdt := MeshDataTool.new()
	if mdt.create_from_surface(mesh, surf_idx) != OK:
		return PackedColorArray()
	if mdt.get_vertex_count() != vertex_count:
		vertex_count = mdt.get_vertex_count()
	var colors := PackedColorArray()
	colors.resize(vertex_count)
	for i in range(vertex_count):
		colors[i] = mdt.get_vertex_color(i)
	return colors


static func _read_custom_slot(mesh: Mesh, surf_idx: int, slot: int, vertex_count: int) -> PackedColorArray:
	if not mesh is ArrayMesh:
		return PackedColorArray()

	var format: int = mesh.surface_get_format(surf_idx)
	if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
		# Compressed CUSTOM cannot be read reliably; normalize rebuild will add ARRAY_COLOR.
		return PackedColorArray()

	var arrays: Array = mesh.surface_get_arrays(surf_idx)
	if arrays.size() <= slot:
		return PackedColorArray()

	var data: Variant = arrays[slot]
	if data is PackedColorArray:
		return _resize_colors(data as PackedColorArray, vertex_count)
	if data is PackedByteArray:
		return _colors_from_rgba8_bytes(data as PackedByteArray, vertex_count)
	if data is PackedFloat32Array:
		var floats: PackedFloat32Array = data
		if _float_custom_looks_like_bone_weights(floats, vertex_count):
			return PackedColorArray()
		return _colors_from_float4(floats, vertex_count)

	return PackedColorArray()


static func _custom_format_flag_for_slot(slot: int) -> int:
	for i in range(_CUSTOM_ARRAY_INDICES.size()):
		if _CUSTOM_ARRAY_INDICES[i] == slot:
			return _CUSTOM_FORMAT_FLAGS[i]
	return 0


static func _custom_format_shift_for_slot(slot: int) -> int:
	for i in range(_CUSTOM_ARRAY_INDICES.size()):
		if _CUSTOM_ARRAY_INDICES[i] == slot:
			return _CUSTOM_FORMAT_SHIFTS[i]
	return 0


## True for custom formats that can hold vertex colors (not RG/R float UV extras).
static func custom_format_looks_like_color(custom_type: int) -> bool:
	match custom_type:
		Mesh.ARRAY_CUSTOM_RGBA8_UNORM, \
		Mesh.ARRAY_CUSTOM_RGBA8_SNORM, \
		Mesh.ARRAY_CUSTOM_RGBA_HALF, \
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT:
			return true
		_:
			return false


static func _custom_slot_format_type(mesh: Mesh, surf_idx: int, slot: int) -> int:
	var shift: int = _custom_format_shift_for_slot(slot)
	var format: int = mesh.surface_get_format(surf_idx)
	return (format >> shift) & Mesh.ARRAY_FORMAT_CUSTOM_MASK


static func _custom_slot_looks_like_vertex_colors(mesh: Mesh, surf_idx: int, slot: int) -> bool:
	var vertex_count: int = mesh.surface_get_array_len(surf_idx)
	if vertex_count <= 0:
		return false

	if not mesh is ArrayMesh:
		return false

	var format: int = mesh.surface_get_format(surf_idx)
	if (format & _custom_format_flag_for_slot(slot)) == 0:
		return false

	var custom_type: int = _custom_slot_format_type(mesh, surf_idx, slot)
	if not custom_format_looks_like_color(custom_type):
		return false

	if (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
		return true

	var arrays: Array = mesh.surface_get_arrays(surf_idx)
	if arrays.size() <= slot:
		return false

	var data: Variant = arrays[slot]
	if data is PackedColorArray:
		return _packed_colors_have_variation(data as PackedColorArray)
	if data is PackedByteArray:
		var colors_from_bytes: PackedColorArray = _colors_from_rgba8_bytes(data as PackedByteArray, vertex_count)
		return _packed_colors_have_variation(colors_from_bytes)
	if data is PackedFloat32Array:
		var floats: PackedFloat32Array = data
		if _float_custom_looks_like_bone_weights(floats, vertex_count):
			return false
		var colors_from_float: PackedColorArray = _colors_from_float4(floats, vertex_count)
		return _packed_colors_have_variation(colors_from_float)

	return false


static func _color_diff_sq(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	var da: float = a.a - b.a
	return dr * dr + dg * dg + db * db + da * da


static func _packed_colors_have_variation(colors: PackedColorArray) -> bool:
	if colors.is_empty():
		return false
	var first: Color = colors[0]
	var sample_count: int = mini(colors.size(), 128)
	for i in range(1, sample_count):
		if _color_diff_sq(colors[i], first) > 0.000001:
			return true
	# Uniform but non-default white: still treat as color data (e.g. flat fill).
	if first.r < 0.99 or first.g < 0.99 or first.b < 0.99 or first.a < 0.99:
		return true
	return colors.size() > 0


static func _float_custom_looks_like_bone_weights(floats: PackedFloat32Array, vertex_count: int) -> bool:
	var components_per_vertex: int = 4
	if floats.size() < vertex_count * components_per_vertex:
		return false

	var weight_like: int = 0
	var sample_count: int = mini(vertex_count, 64)
	for i in range(sample_count):
		var base: int = i * components_per_vertex
		var s: float = floats[base] + floats[base + 1] + floats[base + 2] + floats[base + 3]
		if absf(s - 1.0) < 0.08:
			weight_like += 1
	return weight_like >= sample_count / 2


static func _colors_from_rgba8_bytes(bytes: PackedByteArray, vertex_count: int) -> PackedColorArray:
	var colors := PackedColorArray()
	if bytes.size() < vertex_count * 4:
		return colors
	colors.resize(vertex_count)
	for i in range(vertex_count):
		var base: int = i * 4
		colors[i] = Color(
				bytes[base] / 255.0,
				bytes[base + 1] / 255.0,
				bytes[base + 2] / 255.0,
				bytes[base + 3] / 255.0)
	return colors


static func _colors_from_float4(floats: PackedFloat32Array, vertex_count: int) -> PackedColorArray:
	var colors := PackedColorArray()
	if floats.size() < vertex_count * 4:
		return colors
	colors.resize(vertex_count)
	for i in range(vertex_count):
		var base: int = i * 4
		colors[i] = Color(floats[base], floats[base + 1], floats[base + 2], floats[base + 3])
	return colors


static func _resize_colors(colors: PackedColorArray, vertex_count: int) -> PackedColorArray:
	if colors.size() == vertex_count:
		return colors
	var out := colors.duplicate()
	if out.size() > vertex_count:
		return out.slice(0, vertex_count)
	out.resize(vertex_count)
	return out
