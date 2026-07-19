class_name AudioEventDefinition
extends Resource

@export var event_id: StringName = &""
@export var stream_paths: PackedStringArray = PackedStringArray()
@export var bus: StringName = &"SFX"
@export var positional: bool = true
@export_range(-40.0, 6.0, 0.1) var volume_db_min: float = -6.0
@export_range(-40.0, 6.0, 0.1) var volume_db_max: float = -3.0
@export_range(0.5, 2.0, 0.01) var pitch_min: float = 0.94
@export_range(0.5, 2.0, 0.01) var pitch_max: float = 1.06
@export_range(1, 32, 1) var max_instances: int = 4
@export_range(0.0, 3.0, 0.01) var cooldown_seconds: float = 0.05
@export_range(0.0, 5.0, 0.01) var emitter_cooldown_seconds: float = 0.12
@export_range(64.0, 5000.0, 1.0) var max_distance: float = 1350.0
@export_range(0, 100, 1) var priority: int = 50
@export_range(0.0, 12.0, 0.1) var ducking_db: float = 0.0
@export_range(0.0, 2.0, 0.01) var ducking_seconds: float = 0.0

var _cached_streams: Array[AudioStream] = []
var _load_attempted: bool = false


func get_random_stream(rng: RandomNumberGenerator) -> AudioStream:
	_ensure_streams_loaded()
	if _cached_streams.is_empty():
		return null
	return _cached_streams[rng.randi_range(0, _cached_streams.size() - 1)]


func get_random_volume_db(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(minf(volume_db_min, volume_db_max), maxf(volume_db_min, volume_db_max))


func get_random_pitch(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))


func _ensure_streams_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	for path in stream_paths:
		var stream := load(path) as AudioStream
		if stream != null:
			_cached_streams.append(stream)
