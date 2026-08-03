extends Node

# Runs as a scene so the autoloads exist before anything here loads.

## Recording a region ping must not write the settings file every time.
##
## In a match the region ping is re-recorded on every pong — once a second — and
## each of those saved user://network_settings.cfg. When the region is automatic
## it saved twice, because reselecting the same region stored the preference
## again. That is a synchronous flash write a couple of times a second, on the
## main thread, for the length of the match: a frame hitch on a fixed rhythm,
## and pointless wear on the device.

const SAMPLES: int = 40

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	NetworkSession.flush_settings()
	var writes_before: int = NetworkSession.get_settings_write_count()
	for index in SAMPLES:
		NetworkSession.record_region_ping("frankfurt", 60 + index % 5)
	var writes_after: int = NetworkSession.get_settings_write_count()
	var writes: int = writes_after - writes_before
	# The interval is five seconds and this loop takes microseconds, so one
	# write is the most that can be justified.
	if writes > 1:
		_failures.append(
			"%d ping samples caused %d settings writes, expected at most 1" % [SAMPLES, writes]
		)

	# Throttling the write must not throttle the value.
	var expected: int = NetworkSession.measured_region_pings.get("frankfurt", -1)
	if expected < 0:
		_failures.append("Region ping was not recorded in memory")

	# Whatever was held back has to reach the disk when the app closes.
	NetworkSession.flush_settings()
	if NetworkSession.get_settings_write_count() <= writes_after:
		_failures.append("Pending settings were never flushed")
	var stored := ConfigFile.new()
	if stored.load(NetworkSession.SETTINGS_PATH) != OK:
		_failures.append("Settings file was not written at all")
	else:
		var pings_variant: Variant = stored.get_value("network", "measured_region_pings", {})
		var pings: Dictionary = pings_variant if pings_variant is Dictionary else {}
		if int(pings.get("frankfurt", -1)) != expected:
			_failures.append(
				(
					"Flushed file holds %s, memory holds %d"
					% [str(pings.get("frankfurt", -1)), expected]
				)
			)

	_check_audio_slider_drag()
	_finish()


## A volume slider reports every step of a drag, and each step wrote the audio
## settings file — dozens of synchronous flash writes for one swipe, felt as a
## stutter on the device the player is adjusting.
func _check_audio_slider_drag() -> void:
	AudioSystem.flush_settings()
	var writes_before: int = AudioSystem.get_settings_write_count()
	for index in SAMPLES:
		AudioSystem.set_volume(&"music", float(index) / float(SAMPLES))
	var writes: int = AudioSystem.get_settings_write_count() - writes_before
	if writes > 1:
		_failures.append(
			(
				"%d slider steps caused %d audio settings writes, expected at most 1"
				% [SAMPLES, writes]
			)
		)
	var expected: float = float(SAMPLES - 1) / float(SAMPLES)
	if not is_equal_approx(float(AudioSystem.get_setting(&"music")), expected):
		_failures.append("Audio volume did not follow the slider while the write was held")
	AudioSystem.flush_settings()
	var stored := ConfigFile.new()
	if stored.load(AudioSystem.SETTINGS_PATH) != OK:
		_failures.append("Audio settings file was not written at all")
	elif not is_equal_approx(float(stored.get_value("audio", "music", -1.0)), expected):
		_failures.append("Flushed audio settings do not match the value in memory")


func _finish() -> void:
	if _failures.is_empty():
		print("PASS settings_write_throttle_regression_test")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
