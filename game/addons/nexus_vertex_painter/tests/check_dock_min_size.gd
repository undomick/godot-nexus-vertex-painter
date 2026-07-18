#!/usr/bin/env gdscript
## Headless structural check for Godot 4.7 bottom-bar fix.
extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://addons/nexus_vertex_painter/painter_dock.tscn")
	if packed == null:
		push_error("FAIL: could not load painter_dock.tscn")
		quit(1)
		return

	var dock: Control = packed.instantiate()
	if dock == null:
		push_error("FAIL: instantiate returned null")
		quit(1)
		return

	if not (dock is ScrollContainer):
		push_error("FAIL: root is %s, expected ScrollContainer" % dock.get_class())
		quit(1)
		return

	var content := dock.get_node_or_null("Content")
	if content == null or not (content is VBoxContainer):
		push_error("FAIL: missing Content VBoxContainer")
		quit(1)
		return

	# ScrollContainer min height must stay small (not the full dock content height).
	var min_size: Vector2 = dock.get_combined_minimum_size()
	var content_min: Vector2 = content.get_combined_minimum_size()
	print("PainterDock (ScrollContainer) min_size=%s" % min_size)
	print("Content (VBoxContainer) min_size=%s" % content_min)

	if content_min.y < 400.0:
		push_error("FAIL: content min height unexpectedly small (%.1f); scene may be broken" % content_min.y)
		quit(1)
		return

	# Scroll root should not inherit the full content height as its own minimum.
	if min_size.y >= content_min.y * 0.5:
		push_error(
			"FAIL: ScrollContainer min height (%.1f) is too close to content (%.1f); bottom bar may still be pushed off-screen"
			% [min_size.y, content_min.y]
		)
		quit(1)
		return

	print("OK: ScrollContainer keeps small min height while content remains tall.")
	dock.free()
	quit(0)
