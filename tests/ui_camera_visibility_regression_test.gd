extends SceneTree

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const CAMERA_SCRIPT := preload("res://gameplay/world/camera_controller.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var camera := CAMERA_SCRIPT.new() as PlayerCameraController
	camera.set_safe_frame_insets(Vector4(24.0, 72.0, 24.0, 190.0))
	var viewport_size := Vector2(1280.0, 720.0)
	var safe_rect: Rect2 = camera.get_gameplay_safe_rect_for_size(viewport_size)
	var moving_up_screen: Vector2 = camera.get_desired_target_screen_position(
		viewport_size, Vector2.UP
	)
	var moving_down_screen: Vector2 = camera.get_desired_target_screen_position(
		viewport_size, Vector2.DOWN
	)
	if not safe_rect.has_point(moving_up_screen) or not safe_rect.has_point(moving_down_screen):
		camera.free()
		_fail("Camera target escaped the HUD-safe gameplay rectangle")
		return
	if moving_up_screen.y >= safe_rect.get_center().y:
		camera.free()
		_fail("Moving upward does not reserve screen space for the trailing swarm")
		return
	if moving_down_screen.y <= safe_rect.get_center().y:
		camera.free()
		_fail("Movement-direction framing is not symmetric")
		return
	camera.free()

	var hud := HUD_SCENE.instantiate() as ColonyHUD
	root.add_child(hud)
	await process_frame
	hud._apply_responsive_layout()
	await process_frame

	var resource_rect: Rect2 = hud.resources_panel.get_global_rect()
	var minimap_rect: Rect2 = hud.minimap_panel.get_global_rect()
	var production_rect: Rect2 = hud.production_panel.get_global_rect()
	var gather_rect: Rect2 = hud.gather_button.get_global_rect()
	var attack_rect: Rect2 = hud.attack_button.get_global_rect()
	if resource_rect.intersects(minimap_rect):
		_fail("Resource dock and minimap overlap")
		return
	if production_rect.intersects(gather_rect) or production_rect.intersects(attack_rect):
		_fail("Production dock overlaps right-side command controls")
		return
	var safe_insets: Vector4 = hud.get_world_safe_frame_insets()
	if safe_insets.w < 176.0:
		_fail("Camera bottom inset does not cover the production dock")
		return

	hud.stick._set_value(Vector2(0.7, -0.4))
	hud._on_audio_settings_pressed()
	if not hud.stick.value.is_zero_approx():
		_fail("Opening a modal panel did not release the movement stick")
		return
	if not hud.audio_settings_panel.visible:
		_fail("Audio settings panel failed to open")
		return
	hud._close_audio_settings()

	print(
		(
			"PASS ui_camera_visibility_regression_test safe=%s up=%s production=%s"
			% [safe_rect, moving_up_screen, production_rect]
		)
	)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
