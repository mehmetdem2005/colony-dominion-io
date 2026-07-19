class_name WorldResourceNode
extends Area2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var resource_type: StringName = &"seed"
var amount: int = 40
var max_amount: int = 40
var respawn_delay: float = 22.0
var stream_chunk := Vector2i.ZERO
var stream_local_id: int = -1
var stream_active: bool = false
var activation_generation: int = 0

var _respawn_left: float = 0.0
var _base_scale := Vector2.ONE
var _focus_left: float = 0.0
var _focus_color := Color.WHITE
var _focus_radius: float = 46.0
var _suspended_at_msec: int = 0


func _ready() -> void:
	add_to_group("resource_nodes")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	collision_shape.disabled = true
	set_physics_process(false)


func configure(
	type_id: StringName, texture: Texture2D, starting_amount: int, world_size: float
) -> void:
	if not is_in_group("resource_nodes"):
		add_to_group("resource_nodes")
	activation_generation += 1
	resource_type = type_id
	max_amount = maxi(starting_amount, 1)
	amount = max_amount
	var safe_world_size: float = world_size if is_finite(world_size) and world_size > 1.0 else 32.0
	sprite.texture = texture
	if texture != null:
		var longest: float = float(max(texture.get_width(), texture.get_height()))
		var factor: float = safe_world_size / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * factor
		_base_scale = sprite.scale
	var circle := collision_shape.shape as CircleShape2D
	if circle != null:
		circle.radius = safe_world_size * 0.38
	_focus_radius = safe_world_size * 0.56
	_focus_left = 0.0
	_respawn_left = 0.0
	stream_active = true
	z_index = WorldDepthPolicy.depth_z(
		global_position.y, WorldDepthPolicy.RESOURCE_STRUCTURE_SUB_LAYER
	)
	_suspended_at_msec = 0
	_refresh_visual()
	_apply_stream_state()


func activate_streamed(
	type_id: StringName,
	texture: Texture2D,
	starting_amount: int,
	world_size: float,
	chunk_coord: Vector2i,
	local_id: int,
	saved_state: Dictionary,
	elapsed_unloaded: float,
	new_respawn_delay: float
) -> void:
	stream_chunk = chunk_coord
	stream_local_id = local_id
	respawn_delay = (
		new_respawn_delay if is_finite(new_respawn_delay) and new_respawn_delay > 0.0 else 24.0
	)
	configure(type_id, texture, starting_amount, world_size)
	if not saved_state.is_empty():
		amount = clampi(int(saved_state.get("amount", starting_amount)), 0, max_amount)
		_respawn_left = maxf(0.0, float(saved_state.get("respawn_left", 0.0)) - elapsed_unloaded)
		if amount <= 0 and _respawn_left <= 0.0:
			amount = max_amount
	_refresh_visual()
	# Streamed resources are constructed over multiple frames. They become visible
	# only when the completed runtime atomically applies ACTIVE residency.
	set_stream_residency(false)


func refresh_world_depth() -> void:
	z_index = WorldDepthPolicy.depth_z(
		global_position.y, WorldDepthPolicy.RESOURCE_STRUCTURE_SUB_LAYER
	)


func deactivate_streamed() -> void:
	_focus_left = 0.0
	set_stream_residency(false)
	remove_from_group("resource_nodes")
	if is_instance_valid(sprite):
		sprite.texture = null


func set_stream_residency(enabled: bool) -> void:
	if enabled:
		if not stream_active:
			_advance_suspended_respawn()
		stream_active = true
		_suspended_at_msec = 0
	else:
		if stream_active:
			_suspended_at_msec = Time.get_ticks_msec()
		stream_active = false
		_focus_left = 0.0
	_apply_stream_state()


func capture_stream_state() -> Dictionary:
	var saved_respawn_left: float = _respawn_left
	if not stream_active and amount <= 0 and _suspended_at_msec > 0:
		var elapsed: float = maxf(0.0, float(Time.get_ticks_msec() - _suspended_at_msec) / 1000.0)
		saved_respawn_left = maxf(0.0, saved_respawn_left - elapsed)
	return {"amount": amount, "respawn_left": saved_respawn_left}


func show_harvest_focus(color: Color, duration: float) -> void:
	if not stream_active or amount <= 0:
		return
	_focus_color = color
	_focus_left = maxf(duration, 0.0) if is_finite(duration) else 0.0
	_update_processing_state()
	_request_redraw()


func apply_authoritative_state(new_amount: int, authoritative_max_amount: int = -1) -> void:
	if authoritative_max_amount > 0:
		max_amount = authoritative_max_amount
	amount = clampi(new_amount, 0, maxi(max_amount, 1))
	_respawn_left = 0.0
	if amount <= 0:
		_focus_left = 0.0
	_refresh_visual()
	_apply_stream_state()


func harvest(requested: int) -> int:
	if not stream_active or amount <= 0 or requested <= 0:
		return 0
	var taken: int = mini(requested, amount)
	amount -= taken
	_refresh_visual()
	if amount <= 0:
		_focus_left = 0.0
		_respawn_left = respawn_delay
	_apply_stream_state()
	return taken


func is_available() -> bool:
	return stream_active and amount > 0 and visible


func matches_activation(generation: int) -> bool:
	return generation > 0 and activation_generation == generation


func _physics_process(delta: float) -> void:
	advance_simulation(delta)


func advance_simulation(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if _focus_left > 0.0:
		_focus_left = maxf(0.0, _focus_left - delta)
		_request_redraw()
	if not stream_active or amount > 0:
		_update_processing_state()
		return
	_respawn_left -= delta
	if _respawn_left <= 0.0:
		amount = max_amount
		_refresh_visual()
	_apply_stream_state()


func _refresh_visual() -> void:
	if max_amount <= 0 or not is_instance_valid(sprite):
		return
	var ratio: float = clampf(float(amount) / float(max_amount), 0.0, 1.0)
	sprite.scale = _base_scale * lerpf(0.65, 1.0, ratio)
	modulate.a = lerpf(0.62, 1.0, ratio)


func _advance_suspended_respawn() -> void:
	if amount > 0 or _suspended_at_msec <= 0:
		return
	var elapsed: float = maxf(0.0, float(Time.get_ticks_msec() - _suspended_at_msec) / 1000.0)
	_respawn_left = maxf(0.0, _respawn_left - elapsed)
	if _respawn_left <= 0.0:
		amount = max_amount
		_refresh_visual()


func _apply_stream_state() -> void:
	var available: bool = stream_active and amount > 0
	visible = available
	monitoring = false
	if is_instance_valid(collision_shape):
		collision_shape.disabled = true
	_update_processing_state()


func _update_processing_state() -> void:
	set_physics_process(false)


func _request_redraw() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		queue_redraw()


func _draw() -> void:
	if _focus_left <= 0.0 or not stream_active or amount <= 0:
		return
	var focus_color := Color(_focus_color.r, _focus_color.g, _focus_color.b, 1.0)
	# A stable segmented marker replaces the time-driven translucent pulse. It
	# remains readable in a swarm without producing fog-like alpha accumulation.
	for segment_index in 4:
		var center_angle: float = PI * 0.25 + float(segment_index) * PI * 0.5
		draw_arc(
			Vector2.ZERO,
			_focus_radius + 4.0,
			center_angle - 0.30,
			center_angle + 0.30,
			6,
			Color(0.02, 0.015, 0.01, 1.0),
			6.0,
			false
		)
		draw_arc(
			Vector2.ZERO,
			_focus_radius + 3.0,
			center_angle - 0.30,
			center_angle + 0.30,
			6,
			focus_color,
			3.0,
			false
		)
