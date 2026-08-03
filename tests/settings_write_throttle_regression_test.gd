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

	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS settings_write_throttle_regression_test")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
