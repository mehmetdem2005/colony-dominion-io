extends Node

# Runs as a scene so the autoloads exist before the HUD loads.

## The HUD has to fit every phone the game ships to, not just the design size.
##
## Its pieces are placed by arithmetic — a left clamp that keeps the production
## bar off the joystick, the bar itself, and a reserve for the command buttons —
## and that arithmetic silently stopped adding up once the bar grew: on a
## 1280-wide screen it needed 1298. The overlap was reported by a player before
## it was reported by a test, because nothing checked more than one size.
##
## Every ratio below is a real phone shape in landscape.

const VIEWPORT_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),  # 16:9, the design size
	Vector2i(1560, 720),  # 19.5:9, most modern phones
	Vector2i(1600, 720),  # 20:9, tall Android flagships
	Vector2i(1480, 720),  # 18.5:9
	Vector2i(960, 720),  # 4:3, tablets
	Vector2i(1024, 768),  # older tablets
]

var _failures: Array[String] = []


func _ready() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	if hud_scene == null:
		_fail("HUD scene could not be loaded")
		return
	# A SubViewport is the only way to control the size headlessly — the real
	# window cannot be resized there, so resizing it silently measured the same
	# viewport six times and proved nothing.
	for size in VIEWPORT_SIZES:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		get_tree().root.add_child(viewport)
		var hud := hud_scene.instantiate() as ColonyHUD
		if hud == null:
			_fail("HUD scene did not instantiate a ColonyHUD")
			return
		viewport.add_child(hud)
		await get_tree().process_frame
		if viewport.get_visible_rect().size != Vector2(size):
			_failures.append(
				(
					"Test kendi gorunum alanini kuramadi: istenen %s, gercek %s"
					% [size, viewport.get_visible_rect().size]
				)
			)
		hud._apply_responsive_layout()
		await get_tree().process_frame
		await get_tree().process_frame
		_check_size(hud, size)
		viewport.queue_free()
		await get_tree().process_frame

	_finish()


func _check_size(hud: ColonyHUD, size: Vector2i) -> void:
	var pieces: Array = [
		[hud.resources_panel, "kaynak seridi"],
		[hud.minimap_panel, "minimap"],
		[hud.production_panel, "uretim bari"],
		[hud.leaderboard_panel, "liderlik tablosu"],
		[hud.stick, "yon cubugu"],
		[hud.attack_button, "SALDIR"],
		[hud.gather_button, "HASAT"],
		[hud.rally_button, "GERI CAGIR"],
	]
	for index in pieces.size():
		var control := pieces[index][0] as Control
		if not is_instance_valid(control):
			continue
		var rect: Rect2 = _visual_rect(control)
		if rect.position.x < -1.0 or rect.position.y < -1.0:
			_failures.append(
				"%s ekranin disina tasti (sol/ust) %s: %s" % [pieces[index][1], size, rect]
			)
		if rect.end.x > float(size.x) + 1.0 or rect.end.y > float(size.y) + 1.0:
			_failures.append(
				"%s ekranin disina tasti (sag/alt) %s: %s" % [pieces[index][1], size, rect]
			)
		# Only the pieces that share the bottom band can collide; the panels
		# above are placed against different edges.
		for other_index in range(index + 1, pieces.size()):
			var other := pieces[other_index][0] as Control
			if not is_instance_valid(other):
				continue
			if rect.intersects(_visual_rect(other)):
				_failures.append(
					"%s ve %s cakisiyor %s" % [pieces[index][1], pieces[other_index][1], size]
				)


## What the piece really covers on screen. `get_global_rect()` reports the
## unscaled size next to the scaled position, so on any screen where the HUD
## scale is below 1 it describes a rectangle that is not the one the player
## sees — larger than reality, which would invent overlaps that are not there.
func _visual_rect(control: Control) -> Rect2:
	return control.get_global_transform() * Rect2(Vector2.ZERO, control.size)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS hud_layout_fit_regression_test")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
