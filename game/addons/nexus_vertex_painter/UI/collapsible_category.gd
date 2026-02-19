@tool
extends VBoxContainer

@export var title: String = "Category":
	set(value):
		title = value
		if _header_btn: _header_btn.text = value

@export var start_open: bool = true

var _header_btn: Button

func _ready() -> void:
	# Clean up artifacts from previous tool reloads
	for child in get_children():
		if child is Button and child.name == "_InternalHeaderBtn":
			child.queue_free()
	
	# Initialize the toggle button
	_header_btn = Button.new()
	_header_btn.name = "_InternalHeaderBtn"
	_header_btn.text = title
	_header_btn.toggle_mode = true
	_header_btn.button_pressed = start_open
	_header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# Setup Editor Icons
	if Engine.is_editor_hint():
		_update_icon(start_open)
	
	_header_btn.toggled.connect(_on_toggle)
	
	# Add button to the scene and move it to the very top
	add_child(_header_btn)
	move_child(_header_btn, 0)
	
	# Apply initial state
	_on_toggle(start_open)


func _on_toggle(pressed: bool) -> void:
	# Toggle visibility of content (all children except the header button)
	# We do NOT reparent nodes to ensure scene stability.
	for i in range(get_child_count()):
		var child = get_child(i)
		if child != _header_btn:
			child.visible = pressed
			
	if Engine.is_editor_hint() and _header_btn:
		_update_icon(pressed)


func _update_icon(pressed: bool):
	# Fetches standard arrow icons from the Godot Editor theme
	var gui_base = EditorInterface.get_base_control()
	if pressed:
		_header_btn.icon = gui_base.get_theme_icon("GuiTreeArrowDown", "EditorIcons")
	else:
		_header_btn.icon = gui_base.get_theme_icon("GuiTreeArrowRight", "EditorIcons")
