extends SceneTree

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const AVOIDANCE_SCRIPT := preload("res://gameplay/units/local_obstacle_avoidance.gd")
const WORLD_OBSTACLE_BIT: int = 1 << 6


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var test_root := Node2D.new()
	root.add_child(test_root)
	var body := CharacterBody2D.new()
	var body_shape_node := CollisionShape2D.new()
	var body_shape := CircleShape2D.new()
	body_shape.radius = 12.0
	body_shape_node.shape = body_shape
	body.add_child(body_shape_node)
	test_root.add_child(body)
	body.global_position = Vector2.ZERO

	var obstacle := StaticBody2D.new()
	obstacle.collision_layer = WORLD_OBSTACLE_BIT
	var obstacle_shape_node := CollisionShape2D.new()
	var obstacle_shape := CircleShape2D.new()
	obstacle_shape.radius = 30.0
	obstacle_shape_node.shape = obstacle_shape
	obstacle.add_child(obstacle_shape_node)
	test_root.add_child(obstacle)
	obstacle.global_position = Vector2(74.0, 0.0)
	await physics_frame

	var avoidance := AVOIDANCE_SCRIPT.new() as UnitLocalObstacleAvoidance
	avoidance.configure(113, body.global_position)
	var resolved: Vector2 = avoidance.resolve_velocity(
		body, Vector2(200.0, 0.0), 12.0, 1.0 / 60.0, WORLD_OBSTACLE_BIT
	)
	if absf(resolved.y) < 1.0:
		_fail("Local avoidance did not produce a tangential steering vector")
		return

	var hud := HUD_SCENE.instantiate() as ColonyHUD
	root.add_child(hud)
	await process_frame
	var hud_root := hud.get_node_or_null("HUDRoot") as Control
	if hud_root == null:
		_fail("HUD root was not created")
		return
	var resource_dock := hud_root.get_node_or_null("ResourceDock") as Control
	var minimap_dock := hud_root.get_node_or_null("MinimapDock") as Control
	var production_dock := hud_root.get_node_or_null("ProductionDock") as Control
	if resource_dock == null or minimap_dock == null or production_dock == null:
		_fail("One or more production HUD docks are missing")
		return
	if resource_dock.size.x > 150.0:
		_fail("Resource dock is wider than the compact mobile target")
		return
	if minimap_dock.position.x <= resource_dock.position.x + resource_dock.size.x:
		_fail("Minimap is not positioned beside the resource dock")
		return
	if production_dock.size.y > 170.0:
		_fail("Production dock exceeds the mobile vertical budget")
		return

	print(
		(
			"PASS ai_navigation_ui_regression_test steering=%s resource=%s minimap=%s production=%s"
			% [resolved, resource_dock.size, minimap_dock.size, production_dock.size]
		)
	)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
