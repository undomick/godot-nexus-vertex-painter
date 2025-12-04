@tool
extends VBoxContainer

# --- SIGNALS ---
signal settings_changed
signal fill_requested(active_channels, value)
signal clear_requested(active_channels)
signal procedural_requested(type, settings)

# --- UI REFERENCES (Unique Names) ---

# Brush Settings
@onready var size_slider: Slider = %BrushSizeSlider
@onready var size_edit: LineEdit = %BrushSizeLineEdit
@onready var falloff_slider: Slider = %BrushFalloffSlider
@onready var falloff_edit: LineEdit = %BrushSizeLineEdit2
@onready var strength_slider: Slider = %BrushStrengthSlider
@onready var strength_edit: LineEdit = %BrushSizeLineEdit3

# Channels
@onready var btn_r: Button = %R_Btn
@onready var btn_g: Button = %G_Btn
@onready var btn_b: Button = %B_Btn
@onready var btn_a: Button = %A_Btn

# Tools / Modes
@onready var btn_add: Button = %Add_Button
@onready var btn_sub: Button = %Substract_Button
@onready var btn_fill: Button = %Fill_Button
@onready var btn_clear: Button = %Clear_Button

# Procedural Tools
@onready var btn_proc_top: Button = %Proc_TopDown_Btn
@onready var btn_proc_bot: Button = %Proc_BottomUp_Btn
@onready var btn_proc_slope: Button = %Proc_Slope_Btn
@onready var btn_proc_noise: Button = %Proc_Noise_Btn

# Internal State
var _brush_mode: int = 0 # 0 = Add, 1 = Subtract


func _ready() -> void:
	# 1. Setup Sliders (Bidirectional link)
	_setup_slider_link(size_slider, size_edit, 1.0)
	_setup_slider_link(falloff_slider, falloff_edit, 0.5)
	_setup_slider_link(strength_slider, strength_edit, 0.25)
	
	# 2. Setup Channels
	for btn in [btn_r, btn_g, btn_b, btn_a]:
		btn.toggle_mode = true
		if not btn.toggled.is_connected(_on_settings_changed_arg):
			btn.toggled.connect(_on_settings_changed_arg)
	
	# Default: Red channel active
	btn_r.button_pressed = true
	
	# 3. Setup Paint Modes
	btn_add.toggle_mode = true
	btn_sub.toggle_mode = true
	btn_add.button_pressed = true
	
	if not btn_add.pressed.is_connected(_on_mode_add_pressed):
		btn_add.pressed.connect(_on_mode_add_pressed)
	if not btn_sub.pressed.is_connected(_on_mode_sub_pressed):
		btn_sub.pressed.connect(_on_mode_sub_pressed)
	
	# 4. Setup Action Buttons
	if not btn_fill.pressed.is_connected(_on_fill_pressed):
		btn_fill.pressed.connect(_on_fill_pressed)
	if not btn_clear.pressed.is_connected(_on_clear_pressed):
		btn_clear.pressed.connect(_on_clear_pressed)

	# 5. Setup Procedural Buttons
	if not btn_proc_top.pressed.is_connected(_on_proc_top_pressed):
		btn_proc_top.pressed.connect(_on_proc_top_pressed)
	if not btn_proc_bot.pressed.is_connected(_on_proc_bot_pressed):
		btn_proc_bot.pressed.connect(_on_proc_bot_pressed)
	if not btn_proc_slope.pressed.is_connected(_on_proc_slope_pressed):
		btn_proc_slope.pressed.connect(_on_proc_slope_pressed)
	if not btn_proc_noise.pressed.is_connected(_on_proc_noise_pressed):
		btn_proc_noise.pressed.connect(_on_proc_noise_pressed)
	
	_update_all_button_visuals()
	set_ui_active(false)


func set_ui_active(active: bool):
	if active:
		modulate = Color(1, 1, 1, 1)
		process_mode = Node.PROCESS_MODE_INHERIT 
	else:
		modulate = Color(0.5, 0.5, 0.5, 0.5)
		process_mode = Node.PROCESS_MODE_DISABLED


# --- PUBLIC API ---

func get_settings() -> Dictionary:
	return {
		"size": size_slider.value,
		"strength": strength_slider.value,
		"falloff": falloff_slider.value,
		"channels": get_active_channels(),
		"mode": _brush_mode
	}


func get_active_channels() -> Vector4:
	return Vector4(
		1.0 if btn_r.button_pressed else 0.0,
		1.0 if btn_g.button_pressed else 0.0,
		1.0 if btn_b.button_pressed else 0.0,
		1.0 if btn_a.button_pressed else 0.0
	)


# --- INTERNAL LOGIC & HANDLERS ---

func _setup_slider_link(slider: Slider, edit: LineEdit, default_val: float) -> void:
	slider.value = default_val
	edit.text = str(default_val)
	
	# Prevent duplicate connections on reload
	if slider.value_changed.is_connected(_on_slider_changed):
		slider.value_changed.disconnect(_on_slider_changed)
	
	slider.value_changed.connect(func(val): 
		edit.text = str(snapped(val, 0.01))
		emit_signal("settings_changed")
	)
	
	if edit.text_submitted.is_connected(_on_edit_submitted):
		edit.text_submitted.disconnect(_on_edit_submitted)
		
	edit.text_submitted.connect(func(text):
		if text.is_valid_float():
			var val = clamp(text.to_float(), slider.min_value, slider.max_value)
			slider.value = val
			edit.text = str(val)
			edit.release_focus()
		else:
			edit.text = str(slider.value)
	)

# Dummy handlers to check connection existence
func _on_slider_changed(_val): pass
func _on_edit_submitted(_text): pass
func _on_settings_changed_arg(_arg):
	_update_all_button_visuals()
	emit_signal("settings_changed")

# --- VISUAL UPDATE HELPER ---

func _update_all_button_visuals():
	_apply_active_style(btn_r, Color(0.8, 0.2, 0.2, 0.4), Color(1.0, 0.4, 0.4)) # Rot
	_apply_active_style(btn_g, Color(0.2, 0.8, 0.2, 0.4), Color(0.4, 1.0, 0.4)) # Grün
	_apply_active_style(btn_b, Color(0.2, 0.2, 0.8, 0.4), Color(0.4, 0.4, 1.0)) # Blau
	_apply_active_style(btn_a, Color(0.8, 0.8, 0.8, 0.4), Color(1.0, 1.0, 1.0)) # Weiß/Alpha
	
	# Tool Buttons
	var accent = get_theme_color("accent_color", "Editor")
	var bg_accent = accent
	bg_accent.a = 0.4
	
	_apply_active_style(btn_add, bg_accent, accent)
	_apply_active_style(btn_sub, bg_accent, accent)

func _apply_active_style(btn: Button, bg_color: Color, border_color: Color):
	if btn.button_pressed:
		var style = StyleBoxFlat.new()
		style.bg_color = bg_color
		style.border_color = border_color
		
		style.border_width_bottom = 2
		style.border_width_top = 2
		style.border_width_left = 2
		style.border_width_right = 2
		
		var radius = 4
		style.corner_radius_top_left = radius
		style.corner_radius_top_right = radius
		style.corner_radius_bottom_right = radius
		style.corner_radius_bottom_left = radius
		
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("focus", style) # Auch bei Fokus
	else:
		# remove style -> Standard Godot Look
		btn.remove_theme_stylebox_override("normal")
		btn.remove_theme_stylebox_override("hover")
		btn.remove_theme_stylebox_override("pressed")
		btn.remove_theme_stylebox_override("focus")

# --- BUTTON HANDLERS ---

func _on_mode_add_pressed() -> void:
	_brush_mode = 0
	btn_add.button_pressed = true
	btn_sub.button_pressed = false
	_update_all_button_visuals()
	emit_signal("settings_changed")

func _on_mode_sub_pressed() -> void:
	_brush_mode = 1
	btn_sub.button_pressed = true
	btn_add.button_pressed = false
	_update_all_button_visuals()
	emit_signal("settings_changed")

func _on_fill_pressed() -> void:
	emit_signal("fill_requested", get_active_channels(), 1.0)

func _on_clear_pressed() -> void:
	emit_signal("clear_requested", get_active_channels())

func _on_proc_top_pressed():
	emit_signal("procedural_requested", "top_down", get_settings())

func _on_proc_bot_pressed():
	emit_signal("procedural_requested", "bottom_up", get_settings())

func _on_proc_slope_pressed():
	emit_signal("procedural_requested", "slope", get_settings())

func _on_proc_noise_pressed():
	emit_signal("procedural_requested", "noise", get_settings())

# --- SHORTCUT HANDLERS ---

func toggle_add_subtract():
	# Toggle between 0 (Add) and 1 (Subtract)
	if _brush_mode == 0:
		_on_mode_sub_pressed()
	else:
		_on_mode_add_pressed()

func toggle_channel_by_index(index: int):
	# 0=R, 1=G, 2=B, 3=A
	var buttons = [btn_r, btn_g, btn_b, btn_a]
	if index >= 0 and index < buttons.size():
		var btn = buttons[index]
		btn.button_pressed = !btn.button_pressed
