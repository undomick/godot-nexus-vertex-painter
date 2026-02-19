extends SceneTree
## Test runner for Nexus Vertex Painter.
## Run: godot --path game --headless --script res://addons/nexus_vertex_painter/tests/run_tests.gd
## Script must extend SceneTree for godot --script to accept it as entry point.

var _test_node: Node
var _frame_count := 0


func _initialize() -> void:
	_test_node = load("res://addons/nexus_vertex_painter/tests/test_vertex_color_data.gd").new()
	root.add_child(_test_node)


func _idle(_delta: float) -> bool:
	_frame_count += 1
	if _frame_count >= 2:
		var exit_code := 0
		if _test_node.get("_errors") and _test_node._errors.size() > 0:
			exit_code = 1
		quit(exit_code)
		return true
	return false
