class_name SFXPool2D
extends Node

const DEFAULT_POOL_SIZE: int = 22
const HISTORY_TTL_MSEC: int = 30_000
const HISTORY_PRUNE_INTERVAL: int = 128

var _players: Array[AudioStreamPlayer2D] = []
var _slot_event_ids: Array[StringName] = []
var _slot_priorities: Array[int] = []
var _event_last_play_msec: Dictionary = {}
var _emitter_last_play_msec: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _play_attempt_count: int = 0


func configure(pool_size: int = DEFAULT_POOL_SIZE) -> void:
	_rng.seed = 4632026
	_clear_players()
	_event_last_play_msec.clear()
	_emitter_last_play_msec.clear()
	_play_attempt_count = 0
	for index in maxi(pool_size, 1):
		var player := AudioStreamPlayer2D.new()
		player.name = "WorldSFX_%02d" % index
		player.max_polyphony = 1
		player.panning_strength = 1.0
		player.finished.connect(_on_player_finished.bind(index))
		add_child(player)
		_players.append(player)
		_slot_event_ids.append(&"")
		_slot_priorities.append(-1)


func play_event(
	definition: AudioEventDefinition,
	world_position: Vector2,
	listener_position: Vector2,
	context: Dictionary = {}
) -> bool:
	if (
		definition == null
		or not definition.positional
		or not world_position.is_finite()
		or not listener_position.is_finite()
	):
		return false
	var distance_squared: float = world_position.distance_squared_to(listener_position)
	if distance_squared > definition.max_distance * definition.max_distance:
		return false
	var now_msec: int = Time.get_ticks_msec()
	_play_attempt_count += 1
	if _play_attempt_count % HISTORY_PRUNE_INTERVAL == 0:
		_prune_history(now_msec)
	var last_event_msec: int = int(_event_last_play_msec.get(definition.event_id, -1000000))
	if now_msec - last_event_msec < roundi(definition.cooldown_seconds * 1000.0):
		return false
	var emitter_id: int = _safe_int(context.get("emitter_id", 0), 0)
	var emitter_key: String = ""
	if emitter_id != 0 and definition.emitter_cooldown_seconds > 0.0:
		emitter_key = "%s:%d" % [String(definition.event_id), emitter_id]
		var last_emitter_msec: int = int(_emitter_last_play_msec.get(emitter_key, -1000000))
		if now_msec - last_emitter_msec < roundi(definition.emitter_cooldown_seconds * 1000.0):
			return false
	if _count_event_instances(definition.event_id) >= definition.max_instances:
		return false
	var slot: int = _find_slot(definition.priority)
	if slot < 0:
		return false
	var stream: AudioStream = definition.get_random_stream(_rng)
	if stream == null:
		return false
	var player: AudioStreamPlayer2D = _players[slot]
	if player.playing:
		player.stop()
	player.stream = stream
	player.bus = definition.bus
	player.global_position = world_position
	player.max_distance = definition.max_distance
	player.attenuation = 1.0
	player.pitch_scale = definition.get_random_pitch(_rng)
	var intensity: float = _safe_float(context.get("intensity", 1.0), 1.0)
	intensity = clampf(intensity, 0.1, 1.5)
	player.volume_db = definition.get_random_volume_db(_rng) + linear_to_db(intensity)
	_slot_event_ids[slot] = definition.event_id
	_slot_priorities[slot] = definition.priority
	player.play()
	if not player.playing:
		_clear_slot(slot)
		return false
	_event_last_play_msec[definition.event_id] = now_msec
	if not emitter_key.is_empty():
		_emitter_last_play_msec[emitter_key] = now_msec
	return true


func stop_all() -> void:
	for index in _players.size():
		_players[index].stop()
		_clear_slot(index)


func _count_event_instances(event_id: StringName) -> int:
	var count: int = 0
	for index in _players.size():
		if _players[index].playing and _slot_event_ids[index] == event_id:
			count += 1
	return count


func _find_slot(incoming_priority: int) -> int:
	for index in _players.size():
		if not _players[index].playing:
			return index
	var lowest_priority: int = 101
	var lowest_slot: int = -1
	for index in _players.size():
		if _slot_priorities[index] < lowest_priority:
			lowest_priority = _slot_priorities[index]
			lowest_slot = index
	return lowest_slot if incoming_priority > lowest_priority else -1


func _on_player_finished(index: int) -> void:
	_clear_slot(index)


func _clear_slot(index: int) -> void:
	if index < 0 or index >= _players.size():
		return
	_slot_event_ids[index] = &""
	_slot_priorities[index] = -1


func _clear_players() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_players.clear()
	_slot_event_ids.clear()
	_slot_priorities.clear()


func _prune_history(now_msec: int) -> void:
	for event_id in _event_last_play_msec.keys():
		if now_msec - int(_event_last_play_msec[event_id]) > HISTORY_TTL_MSEC:
			_event_last_play_msec.erase(event_id)
	for emitter_key in _emitter_last_play_msec.keys():
		if now_msec - int(_emitter_last_play_msec[emitter_key]) > HISTORY_TTL_MSEC:
			_emitter_last_play_msec.erase(emitter_key)


func _safe_int(value: Variant, fallback: int) -> int:
	return int(value) if value is int else fallback


func _safe_float(value: Variant, fallback: float) -> float:
	if not value is int and not value is float:
		return fallback
	var numeric: float = float(value)
	return numeric if is_finite(numeric) else fallback
