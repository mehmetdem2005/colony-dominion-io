extends Node

# Runs as a scene so the autoloads exist before anything here loads.

## The region probe must go quiet while the player is in a match.
##
## Its timer never stopped. Every twelve seconds a player in a match opened a
## fresh HTTPS connection to each of the ten regions, four requests apiece, on
## the same phone radio that was carrying the match — and then overwrote the
## connection state with "Bölgeler ölçülüyor". Both cost the most on a weak
## connection, which is the connection least able to absorb them, so the
## measurement made the very latency it was there to measure.

## Unroutable on purpose: the discard port refuses at once, so the test never
## reaches the network.
const DEAD_PROBE_URL: String = "http://127.0.0.1:9/health"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var probe: RegionProbeService = OnlineServices.region_probe
	if not is_instance_valid(probe):
		_fail("OnlineServices has no region probe service")
		return
	probe.configure(
		[{"id": "test-region", "probe_url": DEAD_PROBE_URL, "enabled": true}] as Array[Dictionary],
		0.5
	)

	for state in OnlineServices.PROBE_BLOCKING_STATES:
		NetworkSession.set_connection_state(state, "test")
		var before: int = probe.get_cycle_generation()
		OnlineServices.probe_regions()
		if probe.get_cycle_generation() != before:
			_failures.append("Probe cycle started while the connection state was %d" % state)
		if NetworkSession.connection_state != state:
			_failures.append(
				(
					"Probing overwrote connection state %d with %d"
					% [state, NetworkSession.connection_state]
				)
			)

	# Outside a match it must still measure, or the region list has no pings.
	NetworkSession.set_connection_state(NetworkSession.ConnectionState.IDLE, "test")
	var idle_generation: int = probe.get_cycle_generation()
	OnlineServices.probe_regions()
	if probe.get_cycle_generation() == idle_generation:
		_failures.append("Probe cycle did not start from an idle menu")
	if NetworkSession.connection_state != NetworkSession.ConnectionState.PROBING:
		_failures.append("Probing from the menu did not report itself")

	# A superseded cycle has to stop issuing requests, not run to the end of its
	# samples: on a connection slow enough that a cycle outlives the probe
	# interval, the stale cycles pile up on top of each other.
	await get_tree().process_frame
	var issued_before_supersede: int = probe.get_requests_issued()
	probe.probe_all()
	await get_tree().process_frame
	await get_tree().process_frame
	var issued_after: int = probe.get_requests_issued()
	var samples_per_region: int = (
		RegionProbeService.WARMUP_SAMPLE_COUNT + RegionProbeService.MEASURED_SAMPLE_COUNT
	)
	if issued_after - issued_before_supersede > samples_per_region:
		_failures.append(
			(
				"A superseded cycle kept probing: %d requests where one cycle is %d"
				% [issued_after - issued_before_supersede, samples_per_region]
			)
		)

	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS region_probe_gating_regression_test")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
