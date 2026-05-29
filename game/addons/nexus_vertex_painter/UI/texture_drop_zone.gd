@tool
extends PanelContainer

signal texture_changed(texture: Texture2D)

const TEXTURE_EXTENSIONS: PackedStringArray = [
	"png", "jpg", "jpeg", "webp", "tga", "bmp",
]

var _texture_rect: TextureRect
var _label: Label
var _btn_clear: Button
var current_texture: Texture2D = null


func _ready() -> void:
	custom_minimum_size = Vector2(0, 100)
	add_theme_stylebox_override("panel", _make_panel_style(false))
	_build_ui()


func _make_panel_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if active:
		style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
		style.border_color = Color(0.4, 0.6, 1.0)
	else:
		style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
		style.border_color = Color(0.3, 0.3, 0.3)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	return style


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	center.add_child(vbox)

	_texture_rect = TextureRect.new()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.custom_minimum_size = Vector2(64, 64)
	_texture_rect.visible = false
	vbox.add_child(_texture_rect)

	_label = Label.new()
	_label.text = "Drop Stencil Texture Here"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(_label)

	_btn_clear = Button.new()
	_btn_clear.text = "X"
	_btn_clear.flat = true
	_btn_clear.modulate = Color(1, 0.4, 0.4)
	_btn_clear.focus_mode = Control.FOCUS_NONE
	_btn_clear.visible = false
	_btn_clear.pressed.connect(clear_texture)
	_btn_clear.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_clear.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_right", 4)
	header_margin.add_theme_constant_override("margin_top", 4)
	header_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Let drag-and-drop hit the panel, not the clear-button overlay.
	header_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var btn_container := VBoxContainer.new()
	btn_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_margin.add_child(btn_container)
	btn_container.add_child(_btn_clear)
	add_child(header_margin)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("files"):
		return false
	var files: PackedStringArray = data["files"]
	if files.is_empty():
		return false
	return files[0].get_extension().to_lower() in TEXTURE_EXTENSIONS


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var file_path: String = data["files"][0]
	var tex: Resource = load(file_path)
	if tex is Texture2D:
		set_texture(tex)
	else:
		push_warning(
				"Vertex Painter: Failed to load texture from '%s' (not a valid Texture2D)." % file_path)


func set_texture(tex: Texture2D) -> void:
	current_texture = tex
	_texture_rect.texture = tex

	var has_texture := tex != null
	_texture_rect.visible = has_texture
	_label.visible = not has_texture
	_btn_clear.visible = has_texture
	add_theme_stylebox_override("panel", _make_panel_style(has_texture))

	texture_changed.emit(tex)


func clear_texture() -> void:
	set_texture(null)
