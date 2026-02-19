@tool
class_name VertexPainterLog
extends RefCounted

## Central logging for Nexus Vertex Painter.
## Debug output is controlled by Project Setting nexus/vertex_painter/debug_logging.
## Errors are shown to the user via Godot's output panel (push_error).

const LOG_PREFIX := "Vertex Painter: "
const PROJECT_SETTING_DEBUG := "nexus/vertex_painter/debug_logging"


static func debug(msg: String) -> void:
	if not ProjectSettings.has_setting(PROJECT_SETTING_DEBUG):
		return
	if ProjectSettings.get_setting(PROJECT_SETTING_DEBUG) != true:
		return
	print(LOG_PREFIX + msg)


static func info(msg: String) -> void:
	if not ProjectSettings.has_setting(PROJECT_SETTING_DEBUG):
		return
	if ProjectSettings.get_setting(PROJECT_SETTING_DEBUG) == true:
		print(LOG_PREFIX + msg)


static func warn(msg: String, show_to_user: bool = true) -> void:
	var full_msg := LOG_PREFIX + msg
	printerr(full_msg)
	if show_to_user:
		push_warning(full_msg)


static func error(msg: String, show_to_user: bool = true) -> void:
	var full_msg := LOG_PREFIX + msg
	printerr(full_msg)
	if show_to_user:
		push_error(full_msg)
