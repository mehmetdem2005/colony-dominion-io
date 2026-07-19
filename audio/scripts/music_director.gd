class_name MusicDirector
extends Node

enum State {
	MENU,
	COLONY_CALM,
	RESOURCE_EXPANSION,
	THREAT,
	COMBAT_SMALL,
	COMBAT_LARGE,
	QUEEN_DANGER,
	RESULT,
}

const LAYER_PATHS: Dictionary = {
	&"base": "res://audio/music/colony_base.ogg",
	&"growth": "res://audio/music/colony_growth.ogg",
	&"tension": "res://audio/music/colony_tension.ogg",
	&"combat": "res://audio/music/colony_combat.ogg",
	&"critical": "res://audio/music/colony_critical.ogg",
}
const MENU_PATH: String = "res://audio/music/menu_theme.ogg"
const SILENT_DB: float = -60.0
const CROSSFADE_SPEED_DB: float = 18.0

var state: int = State.MENU
var _layers: Dictionary = {}
var _layer_targets: Dictionary = {}
var _menu_player: AudioStreamPlayer
var _mode_match: bool = false
var _menu_target_db: float = -10.0
var _threat: float = 0.0
var _combat: float = 0.0
var _queen_health: float = 1.0
var _growth: float = 0.0
var _recent_combat_left: float = 0.0
var _state_hold_left: float = 0.0


func configure() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clear_players()
	_layers.clear()
	_layer_targets.clear()
	for layer_id in LAYER_PATHS:
		var player := AudioStreamPlayer.new()
		player.name = "Music_%s" % String(layer_id)
		player.bus = &"Music"
		player.stream = _load_looping_stream(String(LAYER_PATHS[layer_id]))
		player.volume_db = SILENT_DB
		add_child(player)
		_layers[layer_id] = player
		_layer_targets[layer_id] = SILENT_DB
	_menu_player = AudioStreamPlayer.new()
	_menu_player.name = "Music_Menu"
	_menu_player.bus = &"Music"
	_menu_player.stream = _load_looping_stream(MENU_PATH)
	_menu_player.volume_db = -10.0
	add_child(_menu_player)
	set_process(true)


func enter_menu() -> void:
	_mode_match = false
	state = State.MENU
	_state_hold_left = 0.0
	for layer_id in _layer_targets:
		_layer_targets[layer_id] = SILENT_DB
	_menu_target_db = -10.0
	if is_instance_valid(_menu_player) and _menu_player.stream != null and not _menu_player.playing:
		_menu_player.volume_db = SILENT_DB
		_menu_player.play()


func enter_match() -> void:
	_mode_match = true
	state = State.COLONY_CALM
	_recent_combat_left = 0.0
	_state_hold_left = 1.5
	_menu_target_db = SILENT_DB
	for player_variant in _layers.values():
		var player := player_variant as AudioStreamPlayer
		if not is_instance_valid(player):
			continue
		player.stop()
		player.volume_db = SILENT_DB
		if player.stream != null:
			player.play(0.0)
	_update_layer_targets()


func enter_result() -> void:
	_mode_match = false
	state = State.RESULT
	_menu_target_db = SILENT_DB
	for layer_id in _layer_targets:
		_layer_targets[layer_id] = -24.0 if layer_id == &"base" else SILENT_DB


func update_metrics(threat: float, combat: float, queen_health: float, growth: float) -> void:
	_threat = clampf(threat, 0.0, 1.0) if is_finite(threat) else 0.0
	_combat = clampf(combat, 0.0, 1.0) if is_finite(combat) else 0.0
	_queen_health = clampf(queen_health, 0.0, 1.0) if is_finite(queen_health) else 1.0
	_growth = clampf(growth, 0.0, 1.0) if is_finite(growth) else 0.0


func notify_combat_event(intensity: float = 0.5) -> void:
	var safe_intensity: float = clampf(intensity, 0.0, 1.0) if is_finite(intensity) else 0.5
	_recent_combat_left = maxf(_recent_combat_left, lerpf(1.8, 4.2, safe_intensity))


func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if _recent_combat_left > 0.0:
		_recent_combat_left = maxf(0.0, _recent_combat_left - delta)
	if _state_hold_left > 0.0:
		_state_hold_left = maxf(0.0, _state_hold_left - delta)
	if _mode_match:
		_evaluate_state()
	for layer_id in _layers:
		var player := _layers[layer_id] as AudioStreamPlayer
		if not is_instance_valid(player):
			continue
		var target_db: float = float(_layer_targets.get(layer_id, SILENT_DB))
		player.volume_db = move_toward(player.volume_db, target_db, CROSSFADE_SPEED_DB * delta)
		if target_db <= SILENT_DB and player.volume_db <= SILENT_DB + 0.1 and not _mode_match:
			player.stop()
	if is_instance_valid(_menu_player):
		_menu_player.volume_db = move_toward(
			_menu_player.volume_db, _menu_target_db, CROSSFADE_SPEED_DB * delta
		)
		if (
			_menu_target_db <= SILENT_DB
			and _menu_player.volume_db <= SILENT_DB + 0.1
			and _menu_player.playing
		):
			_menu_player.stop()


func _evaluate_state() -> void:
	var requested: int = State.COLONY_CALM
	if _queen_health <= 0.30 and (_threat >= 0.12 or _combat >= 0.05 or _recent_combat_left > 0.0):
		requested = State.QUEEN_DANGER
	elif _combat >= 0.58:
		requested = State.COMBAT_LARGE
	elif _combat >= 0.14 or _recent_combat_left > 0.0:
		requested = State.COMBAT_SMALL
	elif _threat >= 0.20:
		requested = State.THREAT
	elif _growth >= 0.38:
		requested = State.RESOURCE_EXPANSION
	if requested == state:
		return
	if _state_hold_left > 0.0 and requested < state and requested != State.QUEEN_DANGER:
		return
	state = requested
	match state:
		State.QUEEN_DANGER:
			_state_hold_left = 3.0
		State.COMBAT_LARGE:
			_state_hold_left = 3.2
		State.COMBAT_SMALL:
			_state_hold_left = 2.4
		State.THREAT:
			_state_hold_left = 2.2
		_:
			_state_hold_left = 1.2
	_update_layer_targets()


func _update_layer_targets() -> void:
	var targets := {
		&"base": -11.0,
		&"growth": SILENT_DB,
		&"tension": SILENT_DB,
		&"combat": SILENT_DB,
		&"critical": SILENT_DB,
	}
	match state:
		State.RESOURCE_EXPANSION:
			targets[&"base"] = -12.0
			targets[&"growth"] = -17.0
		State.THREAT:
			targets[&"base"] = -15.0
			targets[&"tension"] = -15.0
		State.COMBAT_SMALL:
			targets[&"base"] = -17.0
			targets[&"tension"] = -18.0
			targets[&"combat"] = -14.0
		State.COMBAT_LARGE:
			targets[&"base"] = -19.0
			targets[&"tension"] = -15.0
			targets[&"combat"] = -9.5
		State.QUEEN_DANGER:
			targets[&"base"] = -21.0
			targets[&"tension"] = -14.0
			targets[&"combat"] = -12.0
			targets[&"critical"] = -8.5
		State.RESULT:
			targets[&"base"] = -24.0
	_layer_targets = targets


func _load_looping_stream(path: String) -> AudioStream:
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


func _clear_players() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_menu_player = null
