@tool
extends PanelContainer

signal texture_changed(texture: Texture2D)

var _texture_rect: TextureRect
var _label: Label
var _btn_clear: Button
var current_texture: Texture2D = null

func _ready():
	# 1. Style the container
	custom_minimum_size = Vector2(0, 100)
	
	# Create a dark background style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	style.border_color = Color(0.3, 0.3, 0.3)
	
	# FIX: Set borders manually (no 'set_border_width_all' in GDScript)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	
	# FIX: Set corners manually (no 'corner_radius_all' in GDScript)
	var radius = 4
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	
	add_theme_stylebox_override("panel", style)
	
	# 2. Layout
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	var vbox = VBoxContainer.new()
	center.add_child(vbox)
	
	# 3. Texture Preview
	_texture_rect = TextureRect.new()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.custom_minimum_size = Vector2(64, 64)
	_texture_rect.visible = false # Hidden initially
	vbox.add_child(_texture_rect)
	
	# 4. Label
	_label = Label.new()
	_label.text = "Drop Stencil Texture Here"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(_label)
	
	# 5. Clear Button (Top Right Overlay)
	_btn_clear = Button.new()
	_btn_clear.text = "X"
	_btn_clear.flat = true
	_btn_clear.modulate = Color(1, 0.4, 0.4)
	_btn_clear.focus_mode = Control.FOCUS_NONE
	_btn_clear.visible = false
	_btn_clear.pressed.connect(clear_texture)
	
	# Manually position clear button
	_btn_clear.top_level = false
	_btn_clear.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_clear.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	# Wrapper for button positioning
	var header_margin = MarginContainer.new()
	header_margin.add_theme_constant_override("margin_right", 4)
	header_margin.add_theme_constant_override("margin_top", 4)
	header_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var btn_container = VBoxContainer.new()
	btn_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	header_margin.add_child(btn_container)
	btn_container.add_child(_btn_clear)
	add_child(header_margin)

func _can_drop_data(_at_position, data):
	if typeof(data) == TYPE_DICTIONARY and data.has("files"):
		var files = data["files"]
		if files.size() > 0:
			var ext = files[0].get_extension().to_lower()
			return ext in ["png", "jpg", "jpeg", "webp", "tga", "bmp"]
	return false

func _drop_data(_at_position, data):
	var file_path = data["files"][0]
	var tex = load(file_path)
	if tex is Texture2D:
		set_texture(tex)

func set_texture(tex: Texture2D):
	current_texture = tex
	_texture_rect.texture = tex
	
	# Toggle visibility
	if tex != null:
		_texture_rect.visible = true
		_label.visible = false
		_btn_clear.visible = true
		
		# Update Style to look active
		var style = get_theme_stylebox("panel").duplicate()
		style.border_color = Color(0.4, 0.6, 1.0) # Blue border
		style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
		add_theme_stylebox_override("panel", style)
	else:
		_texture_rect.visible = false
		_label.visible = true
		_btn_clear.visible = false
		
		# Reset Style
		var style = get_theme_stylebox("panel").duplicate()
		style.border_color = Color(0.3, 0.3, 0.3)
		style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
		add_theme_stylebox_override("panel", style)
		
	emit_signal("texture_changed", tex)

func clear_texture():
	set_texture(null)
