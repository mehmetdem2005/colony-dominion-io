extends Node

# Runs as a scene so the autoloads exist before the gameplay preloads compile.

## Every viewer's periodic snapshot work must fall on a different tick.
##
## The keyframe, the colony summary and the resource sweep were each scheduled
## on a global `server_tick % interval == 0`, which is the same tick for every
## viewer. One tick in forty therefore rebuilt a complete keyframe for all ten
## players of a full match at once, while the thirty-nine ticks around it did
## almost nothing — a server hitch on a fixed 1.3-second rhythm, and ten large
## packets leaving at the same instant.

const BUILDER_SCRIPT := preload("res://gameplay/network/network_snapshot_builder.gd")
const TEAMS: int = NetworkProtocol.DEFAULT_MAX_PLAYERS
const TICKS: int = 400

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for interval in [
		BUILDER_SCRIPT.KEYFRAME_INTERVAL_TICKS,
		BUILDER_SCRIPT.COLONY_SUMMARY_INTERVAL_TICKS,
		BUILDER_SCRIPT.RESOURCE_STATE_INTERVAL_TICKS,
	]:
		_check_interval(int(interval))
	_finish()


func _check_interval(interval: int) -> void:
	# With ten viewers and an interval of at least ten, no tick may carry more
	# than one viewer's periodic pass.
	var expected_peak: int = maxi(ceili(float(TEAMS) / float(interval)), 1)
	var worst_tick_load: int = 0
	var last_tick_by_team: Dictionary = {}
	var worst_spacing: int = 0
	for tick in TICKS:
		var due_this_tick: int = 0
		for team_id in TEAMS:
			if not BUILDER_SCRIPT.is_cadence_tick(tick, team_id, interval):
				continue
			due_this_tick += 1
			if last_tick_by_team.has(team_id):
				worst_spacing = maxi(worst_spacing, tick - int(last_tick_by_team[team_id]))
			last_tick_by_team[team_id] = tick
		worst_tick_load = maxi(worst_tick_load, due_this_tick)

	if worst_tick_load > expected_peak:
		_failures.append(
			(
				"Interval %d put %d viewers on one tick, at most %d may share it"
				% [interval, worst_tick_load, expected_peak]
			)
		)
	# Staggering must not make anyone wait longer than the cadence promises.
	if worst_spacing > interval:
		_failures.append(
			"Interval %d let a viewer wait %d ticks between passes" % [interval, worst_spacing]
		)
	if last_tick_by_team.size() != TEAMS:
		_failures.append(
			(
				"Interval %d never scheduled %d of the viewers"
				% [interval, TEAMS - last_tick_by_team.size()]
			)
		)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS snapshot_cadence_phase_regression_test")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
