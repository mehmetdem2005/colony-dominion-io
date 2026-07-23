class_name OnlineMatchClient
extends Node2D

const PROXY_SCENE := preload("res://scenes/network/network_entity_proxy.tscn")
const WORLD_STREAM_SCRIPT := preload("res://gameplay/world/world_stream_manager.gd")

var world_bounds := Rect2(-18000.0, -12000.0, 36000.0, 24000.0)
var _world_stream: WorldStreamManager
var _proxies: Dictionary = {}
var _local_commander: NetworkEntityProxy = null
var _local_nest: NetworkEntityProxy = null
var _movement_input := Vector2.ZERO
var _joystick_input := Vector2.ZERO
var _input_left: float = 0.0
var _latest_player_state: Dictionary = {}
var _latest_colony_summaries: Array[Dictionary] = []
var _leaving: bool = false
var _input_enabled: bool = true
var _had_local_anchor: bool = false
var _lifecycle_state: StringName = &"connecting"
var _camera_anchor: Node2D = null

@onready var ground_root: Node2D = $World/Ground
@onready var decoration_root: Node2D = $World/Decorations
@onready var resource_root: Node2D = $World/Resources
@onready var entities_root: Node2D = $World/Entities
@onready var camera: PlayerCameraController = $PlayerCamera
@onready var hud: ColonyHUD = $HUD


func _ready() -> void:
	if not GameTransport.is_authenticated():
		push_error("Online match scene opened without an authenticated game session")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameSession.bind_match(self)
	GameTransport.snapshot_received.connect(_on_snapshot_received)
	GameTransport.player_state_received.connect(_on_player_state_received)
	GameTransport.client_disconnected.connect(_on_disconnected)
	GameTransport.reconnect_failed.connect(_on_reconnect_failed)
	GameTransport.match_ended.connect(_on_match_ended)
	hud.movement_requested.connect(_on_movement_changed)
	hud.command_requested.connect(_on_command_requested)
	hud.exit_requested.connect(_exit_to_menu)
	camera.set_world_bounds(world_bounds)
	if not hud.safe_frame_insets_changed.is_connected(camera.set_safe_frame_insets):
		hud.safe_frame_insets_changed.connect(camera.set_safe_frame_insets)
	camera.set_safe_frame_insets(hud.get_world_safe_frame_insets())
	_world_stream = WORLD_STREAM_SCRIPT.new() as WorldStreamManager
	add_child(_world_stream)
	_world_stream.configure(
		world_bounds, ground_root, decoration_root, resource_root, [], true, false
	)
	hud.bind_online(self, GameTransport.get_local_team_id())
	AudioSystem.enter_match()


func _exit_tree() -> void:
	if GameTransport.snapshot_received.is_connected(_on_snapshot_received):
		GameTransport.snapshot_received.disconnect(_on_snapshot_received)
	if GameTransport.player_state_received.is_connected(_on_player_state_received):
		GameTransport.player_state_received.disconnect(_on_player_state_received)
	if GameTransport.client_disconnected.is_connected(_on_disconnected):
		GameTransport.client_disconnected.disconnect(_on_disconnected)
	if GameTransport.reconnect_failed.is_connected(_on_reconnect_failed):
		GameTransport.reconnect_failed.disconnect(_on_reconnect_failed)
	if GameTransport.match_ended.is_connected(_on_match_ended):
		GameTransport.match_ended.disconnect(_on_match_ended)
	AudioSystem.enter_menu()


func _physics_process(delta: float) -> void:
	var keyboard := Vector2.ZERO
	if _input_enabled:
		keyboard = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_movement_input = (
		keyboard.limit_length(1.0)
		if keyboard.length_squared() > 0.01
		else (_joystick_input if _input_enabled else Vector2.ZERO)
	)
	if is_instance_valid(_local_commander):
		_local_commander.set_prediction_input(_movement_input)
	_input_left -= delta
	if _input_left <= 0.0:
		_input_left = 1.0 / NetworkProtocol.INPUT_HZ
		GameTransport.send_command(&"move", {"vector": _movement_input})
	if _input_enabled:
		_handle_keyboard_commands()


func _on_snapshot_received(snapshot: Dictionary) -> void:
	var server_tick: int = int(snapshot.get("server_tick", -1))
	var entities_variant: Variant = snapshot.get("entities", [])
	if entities_variant is Array:
		for entity_variant in entities_variant:
			if not entity_variant is Dictionary:
				continue
			_apply_entity_snapshot(entity_variant as Dictionary, server_tick)
	var colonies_variant: Variant = snapshot.get("colonies", [])
	if colonies_variant is Array and not (colonies_variant as Array).is_empty():
		_latest_colony_summaries.clear()
		for colony_variant in colonies_variant:
			if colony_variant is Dictionary:
				_latest_colony_summaries.append((colony_variant as Dictionary).duplicate(true))
		hud.apply_online_leaderboard(_build_leaderboard_entries())
	var resource_states: Variant = snapshot.get("resource_states", [])
	if resource_states is Array and is_instance_valid(_world_stream):
		_world_stream.apply_network_resource_states(resource_states as Array)
	var despawned_variant: Variant = snapshot.get("despawned", PackedInt64Array())
	if despawned_variant is PackedInt64Array:
		for entity_id in despawned_variant as PackedInt64Array:
			_remove_proxy(entity_id)
	elif despawned_variant is Array:
		for entity_id_variant in despawned_variant:
			_remove_proxy(int(entity_id_variant))
	_refresh_local_lifecycle()


func _apply_entity_snapshot(data: Dictionary, server_tick: int) -> void:
	var entity_id: int = int(data.get("id", 0))
	if entity_id <= 0:
		return
	var proxy: NetworkEntityProxy = _proxies.get(entity_id) as NetworkEntityProxy
	if not is_instance_valid(proxy):
		proxy = PROXY_SCENE.instantiate() as NetworkEntityProxy
		entities_root.add_child(proxy)
		proxy.configure(
			entity_id, int(data.get("team", -1)), StringName(data.get("kind", &"worker"))
		)
		_proxies[entity_id] = proxy
	proxy.apply_snapshot(data, server_tick)
	var local_team: bool = int(data.get("team", -1)) == GameTransport.get_local_team_id()
	if not local_team:
		return
	var kind := StringName(data.get("kind", &""))
	if kind == &"commander":
		_bind_local_commander(proxy)
	elif kind == &"nest":
		_bind_local_nest(proxy)


func _bind_local_commander(proxy: NetworkEntityProxy) -> void:
	if _local_commander == proxy:
		return
	if is_instance_valid(_local_commander):
		_local_commander.set_local_commander(false)
	_local_commander = proxy
	_local_commander.set_local_commander(true)
	_had_local_anchor = true


func _bind_local_nest(proxy: NetworkEntityProxy) -> void:
	if _local_nest == proxy:
		return
	_local_nest = proxy
	_had_local_anchor = true


func _remove_proxy(entity_id: int) -> void:
	var proxy: NetworkEntityProxy = _proxies.get(entity_id) as NetworkEntityProxy
	_proxies.erase(entity_id)
	if not is_instance_valid(proxy):
		return
	if proxy == _local_commander:
		_local_commander.set_local_commander(false)
		_local_commander = null
	if proxy == _local_nest:
		_local_nest = null
	proxy.queue_free()


func _refresh_local_lifecycle() -> void:
	if _lifecycle_state == &"finished":
		return
	if is_instance_valid(_local_commander):
		_set_lifecycle(&"active")
		_set_camera_anchor(_local_commander)
		return
	if is_instance_valid(_local_nest):
		_set_lifecycle(
			&"respawning",
			"Komutanın öldü. Kamera yuvayı takip ediyor; yeniden doğduğunda kontrol otomatik dönecek."
		)
		_set_camera_anchor(_local_nest)
		return
	if _had_local_anchor:
		_set_lifecycle(
			&"eliminated",
			"Yuvan ve komutanın yok edildi. Maçtan güvenli biçimde ana menüye dönebilirsin."
		)
		_set_camera_anchor(null)


func _set_lifecycle(state: StringName, detail: String = "") -> void:
	var changed: bool = _lifecycle_state != state
	_lifecycle_state = state
	_input_enabled = state == &"active"
	if not _input_enabled:
		_joystick_input = Vector2.ZERO
		_movement_input = Vector2.ZERO
		if is_instance_valid(_local_commander):
			_local_commander.set_prediction_input(Vector2.ZERO)
	if changed or state != &"active":
		hud.set_lifecycle_state(state, detail)


func _set_camera_anchor(anchor: Node2D) -> void:
	if _camera_anchor == anchor:
		return
	_camera_anchor = anchor
	camera.set_target(anchor)
	if not is_instance_valid(_world_stream):
		return
	if is_instance_valid(anchor):
		_world_stream.set_interest_target(anchor)
		_world_stream.prime_initial_area()
	else:
		_world_stream.clear_interest_targets()


func _on_player_state_received(state: Dictionary) -> void:
	_latest_player_state = state.duplicate(true)
	hud.apply_online_player_state(state)
	if bool(state.get("eliminated", false)):
		_set_lifecycle(&"eliminated", "Sunucu koloninin elendiğini doğruladı.")


func get_minimap_snapshot() -> Dictionary:
	var local_team: int = GameTransport.get_local_team_id()
	var colony_entries_by_team: Dictionary = {}

	# 1. Seed an entry for EVERY colony from its authoritative summary, so distant
	#    colonies (which have no nearby, relevance-culled proxy) still show their
	#    nest on the minimap instead of vanishing.
	for summary in _latest_colony_summaries:
		var summary_team: int = int(summary.get("team", -1))
		if summary_team < 0:
			continue
		var nest_variant: Variant = summary.get("nest", Vector2.INF)
		colony_entries_by_team[summary_team] = {
			"team_id": summary_team,
			"color": ColonyVisualCatalog.team_color(summary_team),
			"commander": Vector2.INF,
			"facing": Vector2.UP,
			"nest": nest_variant if nest_variant is Vector2 else Vector2.INF,
			"army_size": int(summary.get("army", 0)),
			"active": bool(summary.get("active", true)),
			"is_player": summary_team == local_team,
		}

	# 2. Overlay live proxy positions where we have them: the moving commander,
	#    and the nest if the summary did not carry one yet.
	for proxy_variant in _proxies.values():
		var proxy := proxy_variant as NetworkEntityProxy
		if not is_instance_valid(proxy):
			continue
		var proxy_team: int = proxy.team_id
		var entry: Dictionary = (
			colony_entries_by_team
			. get(
				proxy_team,
				{
					"team_id": proxy_team,
					"color": ColonyVisualCatalog.team_color(proxy_team),
					"commander": Vector2.INF,
					"facing": Vector2.UP,
					"nest": Vector2.INF,
					"army_size": 0,
					"active": true,
					"is_player": proxy_team == local_team,
				}
			)
		)
		if proxy.kind == &"commander":
			entry["commander"] = proxy.global_position
			entry["facing"] = proxy.facing_direction
		elif proxy.kind == &"nest":
			entry["nest"] = proxy.global_position
		colony_entries_by_team[proxy_team] = entry

	var chunk_entries: Array[Dictionary] = []
	var resource_points: Array[Dictionary] = []
	var loaded_chunks: Array[Vector2i] = []
	var chunk_size: float = 1200.0
	if is_instance_valid(_world_stream):
		chunk_entries = _world_stream.get_minimap_chunk_entries()
		resource_points = _world_stream.get_minimap_resource_points()
		loaded_chunks = _world_stream.get_loaded_chunk_coords()
		chunk_size = _world_stream.get_chunk_size()
	return {
		"world_bounds": world_bounds,
		"colonies": colony_entries_by_team.values(),
		"view_rect": camera.get_world_view_rect() if is_instance_valid(camera) else Rect2(),
		"loaded_chunks": loaded_chunks,
		"chunk_entries": chunk_entries,
		"resources": resource_points,
		"chunk_size": chunk_size,
	}


func _build_leaderboard_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for summary in _latest_colony_summaries:
		var team_id: int = int(summary.get("team", -1))
		(
			entries
			. append(
				{
					"name": String(summary.get("name", "Koloni %d" % (team_id + 1))),
					"score": int(summary.get("score", 0)),
					"eliminated": not bool(summary.get("active", true)),
					"team_color": ColonyVisualCatalog.team_color(team_id),
				}
			)
		)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	return entries


func _on_movement_changed(value: Vector2) -> void:
	_joystick_input = (
		value.limit_length(1.0) if _input_enabled and value.is_finite() else Vector2.ZERO
	)


func _on_command_requested(command_type: StringName, payload: Dictionary) -> void:
	if _input_enabled:
		GameTransport.send_command(command_type, payload)


func _handle_keyboard_commands() -> void:
	if Input.is_action_just_pressed("attack_command"):
		GameTransport.send_command(&"attack")
	if Input.is_action_just_pressed("gather_command"):
		GameTransport.send_command(&"gather")
	if Input.is_action_just_pressed("rally_command"):
		GameTransport.send_command(&"rally")
	if Input.is_action_just_pressed("split_command"):
		GameTransport.send_command(&"split")
	if Input.is_action_just_pressed("spread_command"):
		GameTransport.send_command(&"spread")
	if Input.is_action_just_pressed("merge_command"):
		GameTransport.send_command(&"merge")


func _on_match_ended(winner_name: String) -> void:
	_lifecycle_state = &"finished"
	_input_enabled = false
	_movement_input = Vector2.ZERO
	var player_won: bool = winner_name.strip_edges() == GameSession.player_name.strip_edges()
	hud.show_match_result(winner_name, player_won)


func _on_disconnected(message: String) -> void:
	hud.show_toast(message)


func _on_reconnect_failed(message: String) -> void:
	hud.show_toast(message)
	await get_tree().create_timer(1.5, true, false, true).timeout
	_exit_to_menu()


func _exit_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	_input_enabled = false
	GameTransport.disconnect_from_game("Maçtan çıkıldı")
	GameSession.clear()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
