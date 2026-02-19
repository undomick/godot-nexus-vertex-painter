extends SceneTree
## Performance benchmark launcher (like run_tests.gd).
## Run: godot --path game --headless --script res://addons/nexus_vertex_painter/tests/run_performance.gd

var _bench_node: Node
var _frame_count := 0


func _initialize() -> void:
	_bench_node = load("res://addons/nexus_vertex_painter/tests/performance_benchmark.gd").new()
	root.add_child(_bench_node)


func _idle(_delta: float) -> bool:
	_frame_count += 1
	if _frame_count >= 2:
		quit(0)
		return true
	return false
