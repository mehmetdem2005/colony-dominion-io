extends Node

# Runs as a scene so the autoloads exist before the gameplay preloads compile.

## The per-tick snapshot cap must limit what is transmitted, never what the
## client is told exists.
##
## Applying the cap before collecting the relevant set made every entity ranked
## past MAX_SNAPSHOT_ENTITIES arrive as a despawn, so the client destroyed its
## proxy; a tick later a slightly different set survived the cut and the proxy
## was rebuilt. In a fight large enough to exceed the cap — ten colonies of
## seventy ants clears it comfortably — the ants at the boundary blinked in and
## out continuously.

const BUILDER_SCRIPT := preload("res://gameplay/network/network_snapshot_builder.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var builder = BUILDER_SCRIPT.new()
	var over_cap: int = NetworkProtocol.MAX_SNAPSHOT_ENTITIES + 40

	# First pass: everything in radius is seen for the first time.
	var relevant_first: Dictionary = {}
	var entities_first: Array[Dictionary] = _make_batch(over_cap, 0.0)
	builder._finalize_entity_batch(entities_first, relevant_first, 0, 1)

	if relevant_first.size() != over_cap:
		_failures.append(
			(
				"Relevant set dropped entities the cap only meant to defer: %d of %d"
				% [relevant_first.size(), over_cap]
			)
		)
	if entities_first.size() > NetworkProtocol.MAX_SNAPSHOT_ENTITIES:
		_failures.append("Transmitted batch exceeded the per-tick cap")

	var despawned_first: PackedInt64Array = builder._collect_despawns(0, relevant_first)
	if despawned_first.size() != 0:
		_failures.append("First sight of an entity reported it as despawned")

	# Second pass: the same population, nudged so the distance ordering shifts.
	# Nothing left the radius, so nothing may be despawned.
	var relevant_second: Dictionary = {}
	var entities_second: Array[Dictionary] = _make_batch(over_cap, 5.0)
	builder._finalize_entity_batch(entities_second, relevant_second, 0, 2)
	var despawned_second: PackedInt64Array = builder._collect_despawns(0, relevant_second)
	if despawned_second.size() != 0:
		_failures.append(
			(
				"Entities still in radius were despawned because they ranked past the cap: %d"
				% despawned_second.size()
			)
		)

	# Third pass: a genuinely smaller population must still despawn the rest,
	# otherwise the fix would leak proxies instead of churning them.
	var relevant_third: Dictionary = {}
	var entities_third: Array[Dictionary] = _make_batch(10, 0.0)
	builder._finalize_entity_batch(entities_third, relevant_third, 0, 3)
	var despawned_third: PackedInt64Array = builder._collect_despawns(0, relevant_third)
	if despawned_third.size() != over_cap - 10:
		_failures.append(
			(
				"Entities that really left the radius were not despawned: %d, expected %d"
				% [despawned_third.size(), over_cap - 10]
			)
		)

	# Fourth pass: the cap must be spent on entities that actually carry an
	# update. Ranking the whole in-radius list first meant entities whose turn in
	# the send rotation had not come round consumed cap slots and were then
	# discarded, so the far units — sorted last, and due least often — could go
	# without an update indefinitely and sit frozen at a stale position.
	var relevant_fourth: Dictionary = {}
	var entities_fourth: Array[Dictionary] = _make_batch(over_cap, 0.0)
	# Only the farthest handful are due; everything nearer is waiting its turn.
	for entity in entities_fourth:
		entity["_due"] = int(entity.get("id", 0)) > over_cap - 6
	builder._finalize_entity_batch(entities_fourth, relevant_fourth, 0, 4)
	if entities_fourth.size() != 6:
		_failures.append(
			(
				"Cap was spent on entities with no update to send: transmitted %d, expected 6"
				% entities_fourth.size()
			)
		)
	for entity in entities_fourth:
		if int(entity.get("id", 0)) <= over_cap - 6:
			_failures.append("An entity that was not due was transmitted anyway")
			break

	_run_starvation_pass(builder)
	_finish()


## Fifth pass: a fight big enough that more entities are due than the cap can
## carry must not park the same ones forever.
##
## Ranking due entities by distance alone is a stable order, so once demand
## exceeds the cap the farthest units lose every tick, for the whole match. They
## are inside the radius, so they are never despawned either — the player just
## watches a rank of ants stand frozen at a position minutes out of date while
## the fight moves on around them.
func _run_starvation_pass(builder: Variant) -> void:
	const NEAR_COUNT: int = 200
	const FAR_COUNT: int = 400
	const TICKS: int = 240
	# One second at the 30 Hz snapshot rate. Demand here is 1.4x the cap, so a
	# fair rotation stretches the 2- and 5-tick cadences to about 3 and 7.
	const MAX_ACCEPTABLE_GAP_TICKS: int = 30

	builder.reset()
	var last_seen: Dictionary = {}
	for tick in range(1, TICKS + 1):
		var batch: Array[Dictionary] = []
		for index in NEAR_COUNT + FAR_COUNT:
			var entity_id: int = index + 1
			var interval: int = 2 if index < NEAR_COUNT else 5
			(
				batch
				. append(
					{
						"id": entity_id,
						"team": 1,
						"kind": &"worker",
						"position": Vector2i(index, 0),
						"health": 255,
						"_distance_sq": float(index) * 100.0,
						"_interval": interval,
						"_due": builder._is_entity_due(0, entity_id, interval, tick),
					}
				)
			)
		var relevant: Dictionary = {}
		builder._finalize_entity_batch(batch, relevant, 0, tick)
		for entity in batch:
			last_seen[int(entity.get("id", 0))] = tick

	var worst_gap: int = 0
	var worst_id: int = 0
	for index in NEAR_COUNT + FAR_COUNT:
		var entity_id: int = index + 1
		var gap: int = TICKS - int(last_seen.get(entity_id, 0))
		if gap > worst_gap:
			worst_gap = gap
			worst_id = entity_id
	if worst_gap > MAX_ACCEPTABLE_GAP_TICKS:
		_failures.append(
			(
				"Entity %d went %d ticks without an update while the cap was oversubscribed"
				% [worst_id, worst_gap]
			)
		)


func _make_batch(count: int, jitter: float) -> Array[Dictionary]:
	var entities: Array[Dictionary] = []
	for index in count:
		(
			entities
			. append(
				{
					"id": index + 1,
					"team": 1,
					"kind": &"worker",
					"position": Vector2i(index, 0),
					"health": 255,
					"_distance_sq": float(index) * 100.0 + jitter * float((index % 7) - 3),
					"_due": true,
				}
			)
		)
	return entities


func _finish() -> void:
	if _failures.is_empty():
		print("PASS snapshot_entity_cap_regression_test")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)
