extends SceneTree

const REQUIRED_MUSIC: Array[String] = [
	"res://audio/music/menu_theme.ogg",
	"res://audio/music/colony_base.ogg",
	"res://audio/music/colony_growth.ogg",
	"res://audio/music/colony_tension.ogg",
	"res://audio/music/colony_combat.ogg",
	"res://audio/music/colony_critical.ogg",
]
const REQUIRED_AMBIENCE: Array[String] = [
	"res://audio/ambience/meadow_loop.ogg",
	"res://audio/ambience/forest_loop.ogg",
	"res://audio/ambience/rocky_loop.ogg",
	"res://audio/ambience/dry_loop.ogg",
	"res://audio/ambience/ant_swarm_loop.ogg",
]


func _init() -> void:
	var failures: Array[String] = []
	var library := AudioEventLibrary.new()
	library.load_all()
	if library.get_event_count() != AudioEventLibrary.EVENT_PATHS.size():
		failures.append(
			(
				"Audio event count mismatch: %d/%d"
				% [library.get_event_count(), AudioEventLibrary.EVENT_PATHS.size()]
			)
		)
	for event_path in AudioEventLibrary.EVENT_PATHS:
		if not ResourceLoader.exists(event_path, "Resource"):
			failures.append("Missing event resource: %s" % event_path)
			continue
		var definition := load(event_path) as AudioEventDefinition
		if definition == null:
			failures.append("Invalid event resource: %s" % event_path)
			continue
		if definition.stream_paths.is_empty():
			failures.append("Event has no variants: %s" % definition.event_id)
		for stream_path in definition.stream_paths:
			if not ResourceLoader.exists(stream_path, "AudioStream"):
				failures.append("Missing stream: %s" % stream_path)
		if definition.max_instances <= 0:
			failures.append("Invalid max_instances: %s" % definition.event_id)
		if definition.positional and definition.max_distance <= 0.0:
			failures.append("Invalid max_distance: %s" % definition.event_id)
	for stream_path in REQUIRED_MUSIC:
		if not ResourceLoader.exists(stream_path, "AudioStream"):
			failures.append("Missing music stem: %s" % stream_path)
	for stream_path in REQUIRED_AMBIENCE:
		if not ResourceLoader.exists(stream_path, "AudioStream"):
			failures.append("Missing ambience stem: %s" % stream_path)
	if failures.is_empty():
		print("AUDIO_SYSTEM_REGRESSION_OK events=%d" % library.get_event_count())
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
