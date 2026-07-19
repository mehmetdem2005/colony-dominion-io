class_name AmbientDirector
extends Node

const BIOME_PATHS: Dictionary = {
	&"meadow": "res://audio/ambience/meadow_loop.ogg",
	&"forest": "res://audio/ambience/forest_loop.ogg",
	&"rocky": "res://audio/ambience/rocky_loop.ogg",
	&"dry": "res://audio/ambience/dry_loop.ogg",
}
const SWARM_PATH: String = "res://audio/ambience/ant_swarm_loop.ogg"
const SILENT_DB: float = -60.0

var _biome_players: Dictionary = {}
var _current_biome: StringName = &"forest"
var _swarm_player: AudioStreamPlayer
var _swarm_target_db: float = SILENT_DB
var _running: bool = false


func configure() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clear_players()
	_biome_players.clear()
	for biome_id in BIOME_PATHS:
		var player := AudioStreamPlayer.new()
		player.name = "Ambient_%s" % String(biome_id)
		player.bus = &"Ambient"
		player.stream = _load_looping_stream(String(BIOME_PATHS[biome_id]))
		player.volume_db = SILENT_DB
		add_child(player)
		_biome_players[biome_id] = player
	_swarm_player = AudioStreamPlayer.new()
	_swarm_player.name = "Ambient_Swarm"
	_swarm_player.bus = &"Units"
	_swarm_player.stream = _load_looping_stream(SWARM_PATH)
	_swarm_player.volume_db = SILENT_DB
	add_child(_swarm_player)
	set_process(true)


func start() -> void:
	_running = true
	for player_variant in _biome_players.values():
		var player := player_variant as AudioStreamPlayer
		if player.stream != null and not player.playing:
			player.play()
	if (
		is_instance_valid(_swarm_player)
		and _swarm_player.stream != null
		and not _swarm_player.playing
	):
		_swarm_player.play()


func stop() -> void:
	_running = false
	for player_variant in _biome_players.values():
		var player := player_variant as AudioStreamPlayer
		if is_instance_valid(player):
			player.stop()
	if is_instance_valid(_swarm_player):
		_swarm_player.stop()


func update_context(biome: StringName, swarm_intensity: float) -> void:
	if BIOME_PATHS.has(biome):
		_current_biome = biome
	var intensity: float = clampf(swarm_intensity, 0.0, 1.0)
	_swarm_target_db = lerpf(SILENT_DB, -17.0, smoothstep(0.05, 1.0, intensity))


func _process(delta: float) -> void:
	if not _running:
		return
	for biome_id in _biome_players:
		var player := _biome_players[biome_id] as AudioStreamPlayer
		if not is_instance_valid(player):
			continue
		var target_db: float = -17.0 if biome_id == _current_biome else SILENT_DB
		player.volume_db = move_toward(player.volume_db, target_db, 12.0 * delta)
	if is_instance_valid(_swarm_player):
		_swarm_player.volume_db = move_toward(
			_swarm_player.volume_db, _swarm_target_db, 16.0 * delta
		)


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
	_swarm_player = null
