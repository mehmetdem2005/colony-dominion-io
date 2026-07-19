class_name HudEventBinder
extends RefCounted

var _hub: MatchEventHub = null
var _bindings: Array[Dictionary] = []


func bind(hub: MatchEventHub, target: Object) -> void:
	unbind()
	if not is_instance_valid(hub) or not is_instance_valid(target):
		return
	_hub = hub
	_bindings = [
		{"signal": _hub.inventory_changed, "callback": Callable(target, "_on_inventory_changed")},
		{
			"signal": _hub.leaderboard_changed,
			"callback": Callable(target, "_on_leaderboard_changed")
		},
		{"signal": _hub.match_time_changed, "callback": Callable(target, "_on_match_time_changed")},
		{
			"signal": _hub.production_queue_changed,
			"callback": Callable(target, "_on_production_queue_changed"),
		},
		{
			"signal": _hub.colony_progress_changed,
			"callback": Callable(target, "_on_colony_progress_changed"),
		},
		{
			"signal": _hub.squad_state_changed,
			"callback": Callable(target, "_on_squad_state_changed")
		},
		{
			"signal": _hub.formation_spread_changed,
			"callback": Callable(target, "_on_formation_spread_changed"),
		},
		{
			"signal": _hub.gather_state_changed,
			"callback": Callable(target, "_on_gather_state_changed")
		},
		{"signal": _hub.toast_requested, "callback": Callable(target, "_show_toast")},
		{"signal": _hub.match_ended, "callback": Callable(target, "_on_match_ended")},
	]
	for binding in _bindings:
		var source: Signal = binding.get("signal")
		var callback: Callable = binding.get("callback")
		if not source.is_connected(callback):
			source.connect(callback)


func unbind() -> void:
	for binding in _bindings:
		var source: Signal = binding.get("signal")
		var callback: Callable = binding.get("callback")
		if source.is_connected(callback):
			source.disconnect(callback)
	_bindings.clear()
	_hub = null
