extends Node

const SETTINGS_PATH: String = "user://audio_settings.cfg"
const BUS_PARENTS: Dictionary = {
	&"Music": &"Master",
	&"Ambient": &"Master",
	&"SFX": &"Master",
	&"Units": &"SFX",
	&"Combat": &"SFX",
	&"Environment": &"SFX",
	&"Colony": &"SFX",
	&"UI": &"Master",
}
const VOLUME_SETTING_IDS: Array[StringName] = [&"master", &"music", &"sfx", &"ambient", &"ui"]
const TOGGLE_SETTING_IDS: Array[StringName] = [&"vibration", &"mute_background"]
const DEFAULT_SETTINGS: Dictionary = {
	&"master": 1.0,
	&"music": 0.72,
	&"sfx": 0.86,
	&"ambient": 0.70,
	&"ui": 0.92,
	&"vibration": true,
	&"mute_background": true,
}

var _library := AudioEventLibrary.new()
var _world_pool: SFXPool2D
var _ui_pool: UISFXPool
var _music_director: MusicDirector
var _ambient_director: AmbientDirector
var _snapshot_controller: AudioSnapshotController
var _listener: AudioListener2D
var _settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var _listener_position := Vector2.ZERO
var _music_duck_db: float = 0.0
var _ambient_duck_db: float = 0.0
var _headless: bool = false
var _background_muted: bool = false
var _queen_danger_latched: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = _detect_headless()
	if _headless:
		set_process(false)
		return
	_configure_audio_buses()
	_load_settings()
	_library.load_all()
	_world_pool = SFXPool2D.new()
	_world_pool.name = "SFXPool2D"
	add_child(_world_pool)
	_world_pool.configure(22)
	_ui_pool = UISFXPool.new()
	_ui_pool.name = "UISFXPool"
	add_child(_ui_pool)
	_ui_pool.configure(6)
	_listener = AudioListener2D.new()
	_listener.name = "WorldAudioListener2D"
	add_child(_listener)
	_listener.make_current()
	_music_director = MusicDirector.new()
	_music_director.name = "MusicDirector"
	add_child(_music_director)
	_music_director.configure()
	_ambient_director = AmbientDirector.new()
	_ambient_director.name = "AmbientDirector"
	add_child(_ambient_director)
	_ambient_director.configure()
	_snapshot_controller = AudioSnapshotController.new()
	_snapshot_controller.name = "AudioSnapshotController"
	add_child(_snapshot_controller)
	_snapshot_controller.ducking_changed.connect(_on_ducking_changed)
	_apply_bus_levels()
	enter_menu()


func enter_menu() -> void:
	if not is_ready():
		return
	_queen_danger_latched = false
	_snapshot_controller.reset()
	_world_pool.stop_all()
	_ambient_director.stop()
	_music_director.enter_menu()


func enter_match() -> void:
	if not is_ready():
		return
	_queen_danger_latched = false
	_snapshot_controller.reset()
	_world_pool.stop_all()
	_music_director.enter_match()
	_ambient_director.start()


func update_gameplay_context(context: Dictionary) -> void:
	if not is_ready():
		return
	var requested_listener: Variant = context.get("listener_position", _listener_position)
	if requested_listener is Vector2 and requested_listener.is_finite():
		_listener_position = requested_listener
	if is_instance_valid(_listener):
		_listener.global_position = _listener_position
	var threat: float = _unit_interval(context.get("threat", 0.0), 0.0)
	var combat: float = _unit_interval(context.get("combat", 0.0), 0.0)
	var queen_health: float = _unit_interval(context.get("queen_health", 1.0), 1.0)
	var growth: float = _unit_interval(context.get("growth", 0.0), 0.0)
	var biome_variant: Variant = context.get("biome", &"forest")
	var biome: StringName = (
		StringName(biome_variant)
		if biome_variant is String or biome_variant is StringName
		else &"forest"
	)
	var swarm_intensity: float = _unit_interval(context.get("swarm_intensity", 0.0), 0.0)
	_music_director.update_metrics(threat, combat, queen_health, growth)
	_ambient_director.update_context(biome, swarm_intensity)
	var danger_now: bool = queen_health <= 0.28 and (threat >= 0.12 or combat >= 0.05)
	if danger_now and not _queen_danger_latched:
		_queen_danger_latched = true
		play_ui(&"queen_danger", {"intensity": 1.0})
		request_haptic(80, 0.75)
	elif queen_health >= 0.42:
		_queen_danger_latched = false


func play_sfx(event_id: StringName, world_position: Vector2, context: Dictionary = {}) -> bool:
	if not is_ready():
		return false
	var definition: AudioEventDefinition = _library.get_event(event_id)
	if definition == null:
		return false
	var played: bool = false
	if definition.positional:
		played = _world_pool.play_event(definition, world_position, _listener_position, context)
	else:
		played = _ui_pool.play_event(definition, context)
	if played:
		_after_event_played(definition, context)
	return played


func play_ui(event_id: StringName = &"ui_press", context: Dictionary = {}) -> bool:
	if not is_ready():
		return false
	var definition: AudioEventDefinition = _library.get_event(event_id)
	if definition == null or definition.positional:
		return false
	var played: bool = _ui_pool.play_event(definition, context)
	if played:
		_after_event_played(definition, context)
	return played


func play_resource(
	resource_type: StringName, world_position: Vector2, context: Dictionary = {}
) -> bool:
	var event_id := StringName("resource_%s" % String(resource_type))
	return play_sfx(event_id, world_position, context)


func notify_match_end(player_won: bool) -> void:
	if not is_ready():
		return
	_music_director.enter_result()
	play_ui(&"match_victory" if player_won else &"match_defeat", {"intensity": 1.0})
	request_haptic(120 if player_won else 180, 0.85)


func set_volume(category: StringName, value: float) -> void:
	if not VOLUME_SETTING_IDS.has(category) or not is_finite(value):
		return
	_settings[category] = clampf(value, 0.0, 1.0)
	_apply_bus_levels()
	_save_settings()


func set_toggle(setting_id: StringName, enabled: bool) -> void:
	if not TOGGLE_SETTING_IDS.has(setting_id):
		return
	_settings[setting_id] = enabled
	if setting_id == &"mute_background" and not enabled and _background_muted:
		_background_muted = false
		_apply_bus_levels()
	_save_settings()


func get_setting(setting_id: StringName) -> Variant:
	return _settings.get(setting_id, DEFAULT_SETTINGS.get(setting_id))


func request_haptic(duration_ms: int = 22, amplitude: float = 0.45) -> void:
	if not bool(_settings.get(&"vibration", true)) or _headless:
		return
	var safe_amplitude: float = amplitude if is_finite(amplitude) else 0.45
	Input.vibrate_handheld(maxi(duration_ms, 1), clampf(safe_amplitude, 0.0, 1.0))


func is_ready() -> bool:
	return (
		not _headless
		and is_instance_valid(_world_pool)
		and is_instance_valid(_ui_pool)
		and is_instance_valid(_music_director)
		and is_instance_valid(_ambient_director)
		and is_instance_valid(_snapshot_controller)
		and is_instance_valid(_listener)
	)


func get_debug_stats() -> Dictionary:
	return {
		"ready": is_ready(),
		"event_count": _library.get_event_count(),
		"listener_position": _listener_position,
		"settings": _settings.duplicate(true),
	}


func _unit_interval(value: Variant, fallback: float) -> float:
	if not value is float and not value is int:
		return clampf(fallback, 0.0, 1.0)
	var numeric: float = float(value)
	if not is_finite(numeric):
		return clampf(fallback, 0.0, 1.0)
	return clampf(numeric, 0.0, 1.0)


func _notification(what: int) -> void:
	if _headless:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if bool(_settings.get(&"mute_background", true)):
			_background_muted = true
			_apply_bus_levels()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _background_muted:
			_background_muted = false
			_apply_bus_levels()


func _after_event_played(definition: AudioEventDefinition, context: Dictionary) -> void:
	if definition.ducking_db > 0.0 and definition.ducking_seconds > 0.0:
		_snapshot_controller.trigger(definition.ducking_db, definition.ducking_seconds)
	if definition.bus == &"Combat" or definition.event_id in [&"nest_hurt", &"nest_destroyed"]:
		_music_director.notify_combat_event(_unit_interval(context.get("intensity", 0.5), 0.5))


func _configure_audio_buses() -> void:
	for bus_name in BUS_PARENTS:
		_ensure_bus_exists(bus_name)
	for bus_name in BUS_PARENTS:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			AudioServer.set_bus_send(bus_index, BUS_PARENTS[bus_name])
	var master_index: int = AudioServer.get_bus_index(&"Master")
	if master_index < 0:
		return
	var hard_limiter: AudioEffectHardLimiter = null
	for effect_index in range(AudioServer.get_bus_effect_count(master_index) - 1, -1, -1):
		var effect: AudioEffect = AudioServer.get_bus_effect(master_index, effect_index)
		if effect is AudioEffectHardLimiter and hard_limiter == null:
			hard_limiter = effect as AudioEffectHardLimiter
		if effect is AudioEffectHardLimiter or effect is AudioEffectLimiter:
			AudioServer.remove_bus_effect(master_index, effect_index)
	if hard_limiter == null:
		hard_limiter = AudioEffectHardLimiter.new()
		hard_limiter.ceiling_db = -0.3
	AudioServer.add_bus_effect(master_index, hard_limiter)


func _ensure_bus_exists(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)


func _on_ducking_changed(music_db: float, ambient_db: float) -> void:
	_music_duck_db = music_db
	_ambient_duck_db = ambient_db
	_apply_bus_levels()


func _apply_bus_levels() -> void:
	if _headless:
		return
	_apply_bus_setting(&"Master", float(_settings.get(&"master", 1.0)), 0.0)
	_apply_bus_setting(&"Music", float(_settings.get(&"music", 0.72)), _music_duck_db)
	_apply_bus_setting(&"SFX", float(_settings.get(&"sfx", 0.86)), 0.0)
	_apply_bus_setting(&"Ambient", float(_settings.get(&"ambient", 0.70)), _ambient_duck_db)
	_apply_bus_setting(&"UI", float(_settings.get(&"ui", 0.92)), 0.0)


func _apply_bus_setting(bus_name: StringName, linear_value: float, offset_db: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var muted: bool = linear_value <= 0.0001 or (_background_muted and bus_name == &"Master")
	AudioServer.set_bus_mute(index, muted)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear_value, 0.0001)) + offset_db)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for setting_id in VOLUME_SETTING_IDS:
		var raw_value: Variant = config.get_value(
			"audio", String(setting_id), DEFAULT_SETTINGS[setting_id]
		)
		var parsed_value: float = (
			float(raw_value)
			if raw_value is float or raw_value is int
			else float(DEFAULT_SETTINGS[setting_id])
		)
		_settings[setting_id] = (
			clampf(parsed_value, 0.0, 1.0)
			if is_finite(parsed_value)
			else DEFAULT_SETTINGS[setting_id]
		)
	for setting_id in TOGGLE_SETTING_IDS:
		var raw_toggle: Variant = config.get_value(
			"audio", String(setting_id), DEFAULT_SETTINGS[setting_id]
		)
		_settings[setting_id] = (raw_toggle if raw_toggle is bool else DEFAULT_SETTINGS[setting_id])


func _save_settings() -> void:
	var config := ConfigFile.new()
	for setting_id in _settings:
		config.set_value("audio", String(setting_id), _settings[setting_id])
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Audio settings could not be saved: %s" % error_string(error))


func _detect_headless() -> bool:
	return (
		OS.has_feature("dedicated_server")
		or DisplayServer.get_name() == "headless"
		or "--server" in OS.get_cmdline_user_args()
	)
