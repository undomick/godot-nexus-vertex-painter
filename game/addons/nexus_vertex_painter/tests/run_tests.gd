extends SceneTree
## Test runner for Nexus Vertex Painter.
## Run: godot --path game --headless --script res://addons/nexus_vertex_painter/tests/run_tests.gd
## Script must extend SceneTree for godot --script to accept it as entry point.

var _test_nodes: Array[Node] = []
var _frame_count := 0


func _initialize() -> void:
	var test_node_1 = load("res://addons/nexus_vertex_painter/tests/test_vertex_color_data.gd").new()
	var test_node_2 = load("res://addons/nexus_vertex_painter/tests/test_mesh_attribute_preservation.gd").new()
	root.add_child(test_node_1)
	root.add_child(test_node_2)
	_test_nodes.append(test_node_1)
	_test_nodes.append(test_node_2)


func _idle(_delta: float) -> bool:
	_frame_count += 1
	if _frame_count >= 2:
		var exit_code := 0
		for node in _test_nodes:
			if node.get("_errors") and node._errors.size() > 0:
				exit_code = 1
				break
		quit(exit_code)
		return true
	return false
