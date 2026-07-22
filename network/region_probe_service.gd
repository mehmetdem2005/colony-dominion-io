class_name RegionProbeService
extends Node

signal region_updated(region_id: String, metrics: Dictionary)
signal cycle_completed(best_region_id: String)

const WARMUP_SAMPLE_COUNT: int = 1
const MEASURED_SAMPLE_COUNT: int = 3

var _regions: Array[Dictionary] = []
var _timeout_seconds: float = 2.5
var _cycle_generation: int = 0
var _pending_count: int = 0
var _metrics: Dictionary = {}
var _best_region_id: String = ""


func configure(regions: Array[Dictionary], timeout_seconds: float) -> void:
	_cycle_generation += 1
	_regions.clear()
	_metrics.clear()
	_best_region_id = ""
	_pending_count = 0
	for region in regions:
		if bool(region.get("enabled", true)):
			_regions.append(region.duplicate(true))
	_timeout_seconds = clampf(timeout_seconds, 0.5, 10.0)


func probe_all() -> void:
	_cycle_generation += 1
	var generation: int = _cycle_generation
	_pending_count = _regions.size()
	_best_region_id = ""
	if _pending_count == 0:
		cycle_completed.emit("")
		return
	for region in _regions:
		_probe_region(region, generation)


func get_metrics(region_id: String) -> Dictionary:
	return (_metrics.get(region_id, {}) as Dictionary).duplicate(true)


func get_best_region_id() -> String:
	return _best_region_id


func _probe_region(region: Dictionary, generation: int) -> void:
	var region_id: String = String(region.get("id", ""))
	var probe_url: String = String(region.get("probe_url", ""))
	var enabled: bool = bool(region.get("enabled", true))
	if not enabled or probe_url.is_empty():
		_finish_region(
			region_id,
			{
				"available": false,
				"configured": not probe_url.is_empty(),
				"ping_ms": -1,
				"jitter_ms": -1,
				"packet_loss": 1.0,
				"score": INF,
			},
			generation
		)
		return
	var client := HttpJsonClient.new()
	client.timeout_seconds = _timeout_seconds
	add_child(client)
	var samples: Array[int] = []
	var failures: int = 0
	var total_requests: int = WARMUP_SAMPLE_COUNT + MEASURED_SAMPLE_COUNT
	for sample_index in total_requests:
		var separator: String = "&" if probe_url.contains("?") else "?"
		var sample_url: String = (
			"%s%st=%d&s=%d"
			% [
				probe_url,
				separator,
				Time.get_ticks_msec(),
				sample_index,
			]
		)
		var response: Dictionary = await client.request_json(
			HTTPClient.METHOD_GET, sample_url, PackedStringArray(["Cache-Control: no-cache"])
		)
		if sample_index < WARMUP_SAMPLE_COUNT:
			continue
		var body_variant: Variant = response.get("body", {})
		var verified_target: bool = false
		if body_variant is Dictionary:
			var body: Dictionary = body_variant
			verified_target = (
				String(body.get("scope", "")) == "region-probe"
				and String(body.get("region", "")) == region_id
			)
		if bool(response.get("ok", false)) and verified_target:
			samples.append(maxi(int(response.get("elapsed_ms", 0)), 1))
		else:
			failures += 1
	client.queue_free()
	var metrics: Dictionary = _build_metrics(samples, failures)
	_finish_region(region_id, metrics, generation)


func _build_metrics(samples: Array[int], failures: int) -> Dictionary:
	if samples.is_empty():
		return {
			"available": false,
			"configured": true,
			"ping_ms": -1,
			"jitter_ms": -1,
			"packet_loss": 1.0,
			"score": INF,
		}
	samples.sort()
	var median_index: int = floori(float(samples.size()) * 0.5)
	var median: int = samples[median_index]
	var deviation_total: float = 0.0
	for sample in samples:
		deviation_total += absf(float(sample - median))
	var jitter: int = roundi(deviation_total / float(samples.size()))
	var packet_loss: float = float(failures) / float(MEASURED_SAMPLE_COUNT)
	var score: float = float(median) + float(jitter) * 2.0 + packet_loss * 400.0
	return {
		"available": true,
		"configured": true,
		"ping_ms": median,
		"jitter_ms": jitter,
		"packet_loss": packet_loss,
		"score": score,
	}


func _finish_region(region_id: String, metrics: Dictionary, generation: int) -> void:
	if generation != _cycle_generation:
		return
	_metrics[region_id] = metrics.duplicate(true)
	NetworkSession.update_region_metrics(region_id, metrics)
	region_updated.emit(region_id, metrics.duplicate(true))
	_pending_count = maxi(_pending_count - 1, 0)
	if _pending_count > 0:
		return
	_best_region_id = _select_best_region()
	cycle_completed.emit(_best_region_id)


func _select_best_region() -> String:
	var best_id: String = ""
	var best_score: float = INF
	for region in _regions:
		var region_id: String = String(region.get("id", ""))
		var metrics: Dictionary = _metrics.get(region_id, {})
		if not bool(metrics.get("available", false)):
			continue
		var score: float = float(metrics.get("score", INF))
		if score < best_score:
			best_score = score
			best_id = region_id
	return best_id
