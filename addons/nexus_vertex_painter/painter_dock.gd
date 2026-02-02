@tool
extends VBoxContainer

# --- SIGNALS ---
signal settings_changed
signal fill_requested(active_channels, value)
signal clear_requested(active_channels)
signal procedural_requested(type, settings)
signal texture_changed(texture)
signal bake_requested()
signal revert_requested()

# --- UI REFERENCES (Unique Names) ---

# Brush Settings
@onready var size_slider: Slider = %BrushSizeSlider
@onready var size_edit: LineEdit = %BrushSizeLineEdit
@onready var falloff_slider: Slider = %BrushFalloffSlider
@onready var falloff_edit: LineEdit = %BrushSizeLineEdit2
@onready var strength_slider: Slider = %BrushStrengthSlider
@onready var strength_edit: LineEdit = %BrushSizeLineEdit3
@onready var texture_drop: PanelContainer = %TextureDropZone

# Smart Masking UI - Slope
@onready var mask_slope_check: CheckBox = %MaskSlopeCheck
@onready var mask_slope_label: Label = %MaskSlopeLabel
@onready var mask_slope_slider: HSlider = %MaskSlopeSlider
@onready var mask_slope_value: LineEdit = %MaskSlopeValue
@onready var mask_slope_invert: CheckBox = %MaskSlopeInvert

# Smart Masking UI - Curvature (NEW v1.5)
@onready var mask_curv_check: CheckBox = %MaskCurvCheck
@onready var mask_curv_label: Label = %MaskCurvLabel
@onready var mask_curv_slider: Slider = %MaskCurvSlider
@onready var mask_curv_value: LineEdit = %MaskCurvValue
@onready var mask_curv_invert: CheckBox = %MaskCurvInvert

# Channels
@onready var btn_r: Button = %R_Btn
@onready var btn_g: Button = %G_Btn
@onready var btn_b: Button = %B_Btn
@onready var btn_a: Button = %A_Btn

# Tools / Modes
@onready var btn_add: Button = %Add_Button
@onready var btn_sub: Button = %Substract_Button
@onready var btn_set: Button = %Set_Button
@onready var btn_blur: Button = %Blur_Button
@onready var btn_sharpen: Button = %Sharpen_Button
@onready var btn_fill: Button = %Fill_Button
@onready var btn_clear: Button = %Clear_Button

# Procedural Tools
@onready var btn_proc_top: Button = %Proc_TopDown_Btn
@onready var btn_proc_bot: Button = %Proc_BottomUp_Btn
@onready var btn_proc_slope: Button = %Proc_Slope_Btn
@onready var btn_proc_noise: Button = %Proc_Noise_Btn

# Production
@onready var btn_bake: Button = %Bake_Button
@onready var btn_revert: Button = %Revert_Button

# Internal State
# 0 = Add, 1 = Subtract, 2 = Set, 3 = Blur, 4 = Sharpen
var _brush_mode: int = 0
var brush_angle: float = 0.0


func _ready() -> void:
    # 1. Setup Sliders
    _setup_slider_link(size_slider, size_edit, 1.0)
    _setup_slider_link(falloff_slider, falloff_edit, 0.5)
    _setup_slider_link(strength_slider, strength_edit, 0.25)
    
    # Slope setup
    _setup_slider_link(mask_slope_slider, mask_slope_value, 45.0)
    
    # Curvature setup
    _setup_slider_link(mask_curv_slider, mask_curv_value, 0.5)
    
    # 2. Setup Channels
    for btn in [btn_r, btn_g, btn_b, btn_a]:
        btn.toggle_mode = true
        if not btn.toggled.is_connected(_on_settings_changed_arg):
            btn.toggled.connect(_on_settings_changed_arg)
    
    btn_r.button_pressed = true
    
    # 3. Setup Paint Modes
    btn_add.toggle_mode = true
    btn_sub.toggle_mode = true
    btn_set.toggle_mode = true
    btn_blur.toggle_mode = true
    btn_sharpen.toggle_mode = true # NEW
    
    btn_add.button_pressed = true
    
    if not btn_add.pressed.is_connected(_on_mode_add_pressed):
        btn_add.pressed.connect(_on_mode_add_pressed)
    if not btn_sub.pressed.is_connected(_on_mode_sub_pressed):
        btn_sub.pressed.connect(_on_mode_sub_pressed)
    if not btn_set.pressed.is_connected(_on_mode_set_pressed):
        btn_set.pressed.connect(_on_mode_set_pressed)
    if not btn_blur.pressed.is_connected(_on_mode_blur_pressed):
        btn_blur.pressed.connect(_on_mode_blur_pressed)
    if not btn_sharpen.pressed.is_connected(_on_mode_sharpen_pressed):
        btn_sharpen.pressed.connect(_on_mode_sharpen_pressed)
    
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
    
    # 6. Connect Texture Drop
    if not texture_drop.texture_changed.is_connected(_on_texture_changed):
        texture_drop.texture_changed.connect(_on_texture_changed)
        
    # 7. Setup Mask Toggles (Slope)
    if not mask_slope_check.toggled.is_connected(_on_mask_check_toggled):
        mask_slope_check.toggled.connect(_on_mask_check_toggled)
        
    if not mask_slope_invert.toggled.is_connected(_on_settings_changed_arg):
        mask_slope_invert.toggled.connect(_on_settings_changed_arg)

    # 8. Setup Mask Toggles (Curvature - NEW)
    if not mask_curv_check.toggled.is_connected(_on_mask_check_toggled):
        mask_curv_check.toggled.connect(_on_mask_check_toggled)
    
    if not mask_curv_invert.toggled.is_connected(_on_settings_changed_arg):
        mask_curv_invert.toggled.connect(_on_settings_changed_arg)
    
    # 9. Setup Bake & Revert
    if not btn_bake.pressed.is_connected(_on_bake_pressed):
        btn_bake.pressed.connect(_on_bake_pressed)
    
    if not btn_revert.pressed.is_connected(_on_revert_pressed):
        btn_revert.pressed.connect(_on_revert_pressed)
    
    _update_all_button_visuals()
    _update_mask_ui_state()
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
        "mode": _brush_mode,
        "brush_texture": texture_drop.current_texture,
        "brush_angle": brush_angle,
        
        # Slope Mask
        "mask_slope_enabled": mask_slope_check.button_pressed,
        "mask_slope_angle": mask_slope_slider.value,
        "mask_slope_invert": mask_slope_invert.button_pressed,
        
        # Curvature Mask
        "mask_curv_enabled": mask_curv_check.button_pressed,
        "mask_curv_sensitivity": mask_curv_slider.value,
        "mask_curv_invert": mask_curv_invert.button_pressed
    }

# --- API FOR MOUSE SHORTCUTS ---

func set_brush_size(value: float): size_slider.value = value
func set_brush_strength(value: float): strength_slider.value = value
func set_brush_falloff(value: float): falloff_slider.value = value

func rotate_brush(delta_radians: float):
    brush_angle += delta_radians
    # Keep angle clean (0 to 2PI)
    brush_angle = wrapf(brush_angle, 0.0, TAU)
    emit_signal("settings_changed")

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
    if edit:
        # Initial Text Set
        if slider.step >= 1.0: edit.text = str(int(default_val))
        else: edit.text = str(default_val)
        
        # Connect LineEdit Submit -> Slider
        if edit.text_submitted.is_connected(_on_edit_submitted): edit.text_submitted.disconnect(_on_edit_submitted)
        edit.text_submitted.connect(func(text):
            if text.is_valid_float():
                var val = clamp(text.to_float(), slider.min_value, slider.max_value)
                slider.value = val
                if slider.step >= 1.0: edit.text = str(int(val))
                else: edit.text = str(val)
                edit.release_focus()
            else: edit.text = str(slider.value)
        )

    # Connect Slider Changed -> LineEdit
    if slider.value_changed.is_connected(_on_slider_changed): slider.value_changed.disconnect(_on_slider_changed)
    slider.value_changed.connect(func(val):
        if edit:
            if slider.step >= 1.0: edit.text = str(int(val))
            else: edit.text = str(snapped(val, 0.01))
        emit_signal("settings_changed")
    )

func _on_slider_changed(_val): emit_signal("settings_changed")
func _on_edit_submitted(_text): pass
func _on_settings_changed_arg(_arg):
    _update_all_button_visuals()
    emit_signal("settings_changed")
func _on_texture_changed(tex: Texture2D):
    emit_signal("texture_changed", tex)
func _on_bake_pressed():
    emit_signal("bake_requested")
func _on_revert_pressed():
    emit_signal("revert_requested")

# --- VISUAL UPDATE HELPER ---

func _update_all_button_visuals():
    _apply_active_style(btn_r, Color(0.8, 0.2, 0.2, 0.4), Color(1.0, 0.4, 0.4))
    _apply_active_style(btn_g, Color(0.2, 0.8, 0.2, 0.4), Color(0.4, 1.0, 0.4))
    _apply_active_style(btn_b, Color(0.2, 0.2, 0.8, 0.4), Color(0.4, 0.4, 1.0))
    _apply_active_style(btn_a, Color(0.8, 0.8, 0.8, 0.4), Color(1.0, 1.0, 1.0))
    
    var accent = get_theme_color("accent_color", "Editor")
    var bg_accent = accent
    bg_accent.a = 0.4
    
    _apply_active_style(btn_add, bg_accent, accent)
    _apply_active_style(btn_sub, bg_accent, accent)
    _apply_active_style(btn_set, bg_accent, accent)
    _apply_active_style(btn_blur, bg_accent, accent)
    _apply_active_style(btn_sharpen, bg_accent, accent)

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
        btn.add_theme_stylebox_override("focus", style)
    else:
        btn.remove_theme_stylebox_override("normal")
        btn.remove_theme_stylebox_override("hover")
        btn.remove_theme_stylebox_override("pressed")
        btn.remove_theme_stylebox_override("focus")

# --- UI LOGIC HANDLERS ---

func _on_mask_check_toggled(pressed: bool):
    _update_mask_ui_state()
    emit_signal("settings_changed")

func _update_mask_ui_state():
    # Slope UI
    var slope_enabled = mask_slope_check.button_pressed
    mask_slope_slider.editable = slope_enabled
    mask_slope_value.editable = slope_enabled
    mask_slope_invert.disabled = not slope_enabled
    var opacity_slope = 1.0 if slope_enabled else 0.5
    mask_slope_label.modulate.a = opacity_slope
    mask_slope_slider.modulate.a = opacity_slope
    mask_slope_value.modulate.a = opacity_slope
    mask_slope_invert.modulate.a = opacity_slope
    
    # Curvature UI (NEW)
    var curv_enabled = mask_curv_check.button_pressed
    mask_curv_slider.editable = curv_enabled
    mask_curv_value.editable = curv_enabled
    mask_curv_invert.disabled = not curv_enabled
    var opacity_curv = 1.0 if curv_enabled else 0.5
    mask_curv_label.modulate.a = opacity_curv
    mask_curv_slider.modulate.a = opacity_curv
    mask_curv_value.modulate.a = opacity_curv 
    mask_curv_invert.modulate.a = opacity_curv

# --- BUTTON HANDLERS ---

func _on_mode_add_pressed() -> void:
    _brush_mode = 0
    _reset_mode_toggles()
    btn_add.button_pressed = true
    _update_all_button_visuals()
    emit_signal("settings_changed")

func _on_mode_sub_pressed() -> void:
    _brush_mode = 1
    _reset_mode_toggles()
    btn_sub.button_pressed = true
    _update_all_button_visuals()
    emit_signal("settings_changed")

func _on_mode_set_pressed() -> void:
    _brush_mode = 2
    _reset_mode_toggles()
    btn_set.button_pressed = true
    _update_all_button_visuals()
    emit_signal("settings_changed")

func _on_mode_blur_pressed() -> void:
    _brush_mode = 3
    _reset_mode_toggles()
    btn_blur.button_pressed = true
    _update_all_button_visuals()
    emit_signal("settings_changed")

func _on_mode_sharpen_pressed() -> void:
    _brush_mode = 4
    _reset_mode_toggles()
    btn_sharpen.button_pressed = true
    _update_all_button_visuals()
    emit_signal("settings_changed")

func _reset_mode_toggles():
    btn_add.button_pressed = false
    btn_sub.button_pressed = false
    btn_set.button_pressed = false
    btn_blur.button_pressed = false
    btn_sharpen.button_pressed = false

func _on_fill_pressed() -> void: emit_signal("fill_requested", get_active_channels(), 1.0)
func _on_clear_pressed() -> void: emit_signal("clear_requested", get_active_channels())
func _on_proc_top_pressed(): emit_signal("procedural_requested", "top_down", get_settings())
func _on_proc_bot_pressed(): emit_signal("procedural_requested", "bottom_up", get_settings())
func _on_proc_slope_pressed(): emit_signal("procedural_requested", "slope", get_settings())
func _on_proc_noise_pressed(): emit_signal("procedural_requested", "noise", get_settings())

# --- SHORTCUT HANDLERS ---

func toggle_add_subtract(reverse: bool = false):
    # Cycle: Add(0) -> Sub(1) -> Set(2) -> Blur(3) -> Sharpen(4)
    var count = 5
    if reverse:
        _brush_mode -= 1
        if _brush_mode < 0: _brush_mode = count - 1
    else:
        _brush_mode += 1
        if _brush_mode >= count: _brush_mode = 0
    
    # Trigger Button Logic to update UI and Signals
    if _brush_mode == 0: _on_mode_add_pressed()
    elif _brush_mode == 1: _on_mode_sub_pressed()
    elif _brush_mode == 2: _on_mode_set_pressed()
    elif _brush_mode == 3: _on_mode_blur_pressed()
    elif _brush_mode == 4: _on_mode_sharpen_pressed()

func toggle_channel_by_index(index: int):
    var buttons = [btn_r, btn_g, btn_b, btn_a]
    if index >= 0 and index < buttons.size():
        var btn = buttons[index]
        btn.button_pressed = !btn.button_pressed
