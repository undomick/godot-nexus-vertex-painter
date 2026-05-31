@tool
extends VBoxContainer

const SETTINGS_PREFIX := "plugin/nexus_vertex_painter/collapsible/"

@export var title: String = "Category":
	set(value):
		title = value
		if _header_btn: _header_btn.text = value

@export var start_open: bool = true

var _header_btn: Button

func _ready() -> void:
	# @tool reload can leave a stale header button; remove before creating a new one.
	for child in get_children():
		if child is Button and child.name == "_InternalHeaderBtn":
			child.queue_free()

	var is_open := _load_open_state()

	_header_btn = Button.new()
	_header_btn.name = "_InternalHeaderBtn"
	_header_btn.text = title
	_header_btn.toggle_mode = true
	_header_btn.button_pressed = is_open
	_header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	if Engine.is_editor_hint():
		_update_icon(is_open)

	_header_btn.toggled.connect(_on_toggle)
	add_child(_header_btn)
	if _header_btn.get_index() != 0:
		move_child(_header_btn, 0)
	_on_toggle(is_open)


func _setting_key() -> String:
	return SETTINGS_PREFIX + str(name)


func _editor_settings() -> EditorSettings:
	return EditorInterface.get_editor_settings()


func _load_open_state() -> bool:
	if not Engine.is_editor_hint():
		return start_open
	var settings := _editor_settings()
	var key := _setting_key()
	if settings.has_setting(key):
		return settings.get_setting(key)
	return start_open


func _save_open_state(open: bool) -> void:
	if not Engine.is_editor_hint():
		return
	_editor_settings().set_setting(_setting_key(), open)


func _on_toggle(pressed: bool) -> void:
	# Visibility only; do not reparent dock children (keeps .tscn references stable).
	for i in range(get_child_count()):
		var child = get_child(i)
		if child != _header_btn:
			child.visible = pressed
			
	if Engine.is_editor_hint() and _header_btn:
		_update_icon(pressed)
		_save_open_state(pressed)


func _update_icon(pressed: bool) -> void:
	var gui_base = EditorInterface.get_base_control()
	if pressed:
		_header_btn.icon = gui_base.get_theme_icon("GuiTreeArrowDown", "EditorIcons")
	else:
		_header_btn.icon = gui_base.get_theme_icon("GuiTreeArrowRight", "EditorIcons")
