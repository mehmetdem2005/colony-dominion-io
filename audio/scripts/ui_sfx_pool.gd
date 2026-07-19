class_name UISFXPool
extends Node

const DEFAULT_POOL_SIZE: int = 6
const HISTORY_TTL_MSEC: int = 30_000
const HISTORY_PRUNE_INTERVAL: int = 128

var _players: Array[AudioStreamPlayer] = []
var _slot_priorities: Array[int] = []
var _event_last_play_msec: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _play_attempt_count: int = 0


func configure(pool_size: int = DEFAULT_POOL_SIZE) -> void:
	_rng.seed = 934671
	_clear_players()
	_event_last_play_msec.clear()
	_play_attempt_count = 0
	for index in maxi(pool_size, 1):
		var player := AudioStreamPlayer.new()
		player.name = "UISFX_%02d" % index
		player.max_polyphony = 1
		player.finished.connect(_on_player_finished.bind(index))
		add_child(player)
		_players.append(player)
		_slot_priorities.append(-1)


func play_event(definition: AudioEventDefinition, context: Dictionary = {}) -> bool:
	if definition == null:
		return false
	var now_msec: int = Time.get_ticks_msec()
	_play_attempt_count += 1
	if _play_attempt_count % HISTORY_PRUNE_INTERVAL == 0:
		_prune_history(now_msec)
	var last_msec: int = int(_event_last_play_msec.get(definition.event_id, -1000000))
	if now_msec - last_msec < roundi(definition.cooldown_seconds * 1000.0):
		return false
	var slot: int = _find_slot(definition.priority)
	if slot < 0:
		return false
	var stream: AudioStream = definition.get_random_stream(_rng)
	if stream == null:
		return false
	var player: AudioStreamPlayer = _players[slot]
	if player.playing:
		player.stop()
	player.stream = stream
	player.bus = definition.bus
	player.pitch_scale = definition.get_random_pitch(_rng)
	var intensity: float = _safe_float(context.get("intensity", 1.0), 1.0)
	intensity = clampf(intensity, 0.1, 1.5)
	player.volume_db = definition.get_random_volume_db(_rng) + linear_to_db(intensity)
	_slot_priorities[slot] = definition.priority
	player.play()
	if not player.playing:
		_slot_priorities[slot] = -1
		return false
	_event_last_play_msec[definition.event_id] = now_msec
	return true


func stop_all() -> void:
	for index in _players.size():
		_players[index].stop()
		_slot_priorities[index] = -1


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
	return lowest_slot if incoming_priority >= lowest_priority else -1


func _on_player_finished(index: int) -> void:
	if index >= 0 and index < _slot_priorities.size():
		_slot_priorities[index] = -1


func _clear_players() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_players.clear()
	_slot_priorities.clear()


func _prune_history(now_msec: int) -> void:
	for event_id in _event_last_play_msec.keys():
		if now_msec - int(_event_last_play_msec[event_id]) > HISTORY_TTL_MSEC:
			_event_last_play_msec.erase(event_id)


func _safe_float(value: Variant, fallback: float) -> float:
	if not value is int and not value is float:
		return fallback
	var numeric: float = float(value)
	return numeric if is_finite(numeric) else fallback
