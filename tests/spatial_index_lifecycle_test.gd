extends SceneTree

const SPATIAL_INDEX_SCRIPT := preload("res://gameplay/performance/unit_spatial_index.gd")


class DamageableStub:
	extends Node2D

	var team_id: int = 1
	var alive: bool = true

	func is_alive() -> bool:
		return alive


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var spatial_index: UnitSpatialIndex = SPATIAL_INDEX_SCRIPT.new(128.0)
	var enemy := DamageableStub.new()
	root.add_child(enemy)
	enemy.global_position = Vector2(40.0, 0.0)
	spatial_index._insert(enemy)

	var live_result: Node2D = spatial_index.find_nearest_enemy(0, Vector2.ZERO, 100.0)
	if live_result != enemy:
		push_error("Spatial index could not resolve a live enemy")
		quit(1)
		return

	enemy.free()
	var freed_result: Node2D = spatial_index.find_nearest_enemy(0, Vector2.ZERO, 100.0)
	if freed_result != null:
		push_error("Spatial index returned a freed enemy")
		quit(1)
		return
	if spatial_index.get_stale_entry_skip_count() <= 0:
		push_error("Spatial index did not record the stale instance id")
		quit(1)
		return

	print("PASS spatial_index_lifecycle_test")
	quit(0)
