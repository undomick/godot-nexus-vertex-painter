extends SceneTree
## Run only mesh attribute preservation tests.
## godot --path game --headless --script res://addons/nexus_vertex_painter/tests/run_mesh_tests_only.gd

var _test_node: Node
var _frame_count := 0

func _initialize() -> void:
	_test_node = load("res://addons/nexus_vertex_painter/tests/test_mesh_attribute_preservation.gd").new()
	root.add_child(_test_node)

func _idle(_delta: float) -> bool:
	_frame_count += 1
	if _frame_count >= 2:
		var exit_code := 1
		if _test_node.get("_errors") and _test_node._errors.size() > 0:
			for e in _test_node._errors:
				print("TEST FAIL: ", e)
		else:
			print("All mesh attribute preservation tests passed.")
			exit_code = 0
		quit(exit_code)
		return true
	return false
