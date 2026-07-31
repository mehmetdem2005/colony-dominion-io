extends SceneTree

## A remote unit's interpolation buffer must cover the spacing of that unit's
## own updates.
##
## The server sends a commander every tick, a nearby unit every second tick and
## a distant one every fifth. A single global buffer sized for the commander
## left every other unit without a future sample to interpolate toward: the
## render clock reached the newest sample it had, froze until the next one
## landed, then jumped. That reads as stutter and no amount of bandwidth or ping
## improves it.

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot_interval: int = NetworkProtocol.get_snapshot_interval_msec()
	# Commander, near unit, far unit: the cadences network_snapshot_builder uses.
	for interval_ticks in [1, 2, 5]:
		var spacing: int = snapshot_interval * interval_ticks
		var delay: int = NetworkProtocol.get_interpolation_delay_msec(0, spacing)
		if delay < spacing:
			_failures.append(
				(
					"Buffer is shorter than the entity's update spacing (%d ticks): %d < %d"
					% [interval_ticks, delay, spacing]
				)
			)

	# Jitter widens the buffer, never narrows it.
	var calm: int = NetworkProtocol.get_interpolation_delay_msec(0, snapshot_interval)
	var shaky: int = NetworkProtocol.get_interpolation_delay_msec(20, snapshot_interval)
	if shaky < calm:
		_failures.append("Jitter shrank the buffer instead of widening it")

	# An entity reporting no spacing yet still gets at least one snapshot
	# interval, so a freshly seen unit does not start out starved.
	if NetworkProtocol.get_interpolation_delay_msec(0, 0) < snapshot_interval:
		_failures.append("Default buffer is under one snapshot interval")

	# The ceiling has to leave room for the slowest cadence the server uses.
	if NetworkProtocol.MAX_INTERPOLATION_DELAY_MSEC < snapshot_interval * 5:
		_failures.append(
			(
				"Ceiling cannot cover the far-unit cadence: %d < %d"
				% [NetworkProtocol.MAX_INTERPOLATION_DELAY_MSEC, snapshot_interval * 5]
			)
		)

	# The snapshot rate and the authoritative tick rate must agree, because
	# NetworkEntityProxy converts tick numbers into milliseconds with the former.
	var rules_text: String = FileAccess.get_file_as_string(
		"res://data/match/default_match_rules.tres"
	)
	var expected: String = "server_tick_rate = %.1f" % NetworkProtocol.SNAPSHOT_HZ
	if not rules_text.contains(expected):
		_failures.append(
			"Match rules tick rate does not match SNAPSHOT_HZ; expected '%s'" % expected
		)

	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS interpolation_buffer_regression_test")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
