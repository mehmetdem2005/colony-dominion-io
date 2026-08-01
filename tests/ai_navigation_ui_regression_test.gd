extends Node

const DESIGN_WIDTH: float = 1280.0
const DESIGN_HEIGHT: float = 720.0

# Runs as a scene, not via --script.
#
# A --script run compiles this file, and everything it preloads, before the
# autoloads exist. MatchController's own preload of colony_controller.gd
# therefore resolved to a script that could not compile — UnitCatalog was not a
# known identifier yet — and the broken result was baked into the class
# constant, so `new()` failed and the test sat there forever with no way to
# recover. Loading the scene again does not help: the poisoned constant lives
# inside the already-compiled class. Booting this as the main scene registers
# the autoloads first, which is the only ordering that makes the gameplay stack
# loadable at all.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const AVOIDANCE_SCRIPT := preload("res://gameplay/units/local_obstacle_avoidance.gd")
const WORLD_OBSTACLE_BIT: int = 1 << 6


func _ready() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	var test_root := Node2D.new()
	get_tree().root.add_child(test_root)
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
	await get_tree().physics_frame

	var avoidance := AVOIDANCE_SCRIPT.new() as UnitLocalObstacleAvoidance
	avoidance.configure(113, body.global_position)
	var resolved: Vector2 = avoidance.resolve_velocity(
		body, Vector2(200.0, 0.0), 12.0, 1.0 / 60.0, WORLD_OBSTACLE_BIT
	)
	if absf(resolved.y) < 1.0:
		_fail("Local avoidance did not produce a tangential steering vector")
		return

	var hud := HUD_SCENE.instantiate() as ColonyHUD
	get_tree().root.add_child(hud)
	await get_tree().process_frame
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
	# These used to pin the old layout: a narrow vertical resource dock with the
	# minimap beside it. The HUD is now a horizontal resource strip with the
	# minimap beneath, so the numbers described a design that no longer exists.
	# What actually matters is unchanged — the docks have to fit the phone and
	# must not sit on top of each other — so that is what is checked.
	if resource_dock.size.x > DESIGN_WIDTH * 0.4:
		_fail(
			(
				"Resource strip takes more than 40%% of the screen width: %.0f of %.0f"
				% [resource_dock.size.x, DESIGN_WIDTH]
			)
		)
		return
	if production_dock.size.y > DESIGN_HEIGHT * 0.3:
		_fail(
			(
				"Production dock exceeds the mobile vertical budget: %.0f of %.0f"
				% [production_dock.size.y, DESIGN_HEIGHT]
			)
		)
		return
	for pair in [
		[resource_dock, minimap_dock, "resource strip", "minimap"],
		[resource_dock, production_dock, "resource strip", "production dock"],
		[minimap_dock, production_dock, "minimap", "production dock"],
	]:
		var first := pair[0] as Control
		var second := pair[1] as Control
		if Rect2(first.position, first.size).intersects(Rect2(second.position, second.size)):
			_fail("HUD docks overlap: %s and %s" % [pair[2], pair[3]])
			return

	print(
		(
			"PASS ai_navigation_ui_regression_test steering=%s resource=%s minimap=%s production=%s"
			% [resolved, resource_dock.size, minimap_dock.size, production_dock.size]
		)
	)
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
