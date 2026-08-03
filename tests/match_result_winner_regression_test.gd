extends Node

# Runs as a scene so the autoloads exist before the gameplay preloads compile.

## The ranked result must credit the colony that actually won.
##
## The winner used to be resolved by matching the winning display name against
## every colony in the match. Nothing makes display names unique — they come
## from the player, and the default name guarantees collisions — so two players
## called the same thing resolved to whichever colony came last in the list.
## The result row was then written against the wrong team, and the player who
## won was recorded as having lost.

const SHARED_NAME: String = "Karınca"

var _failures: Array[String] = []
var _match: MatchController = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var match_scene := load("res://scenes/server_game.tscn") as PackedScene
	if match_scene == null:
		_fail("Match scene could not be loaded")
		return
	_match = match_scene.instantiate() as MatchController
	if _match == null:
		_fail("Match scene did not instantiate a MatchController")
		return
	get_tree().root.add_child(_match)
	await get_tree().process_frame
	if _match.controllers.size() < 2:
		_fail("Server match did not create a second colony")
		return

	# Two players, the same name. The winner is the earlier team, so a lookup by
	# name lands on the later one and gets it exactly wrong.
	var winner: ColonyController = _match.controllers[0]
	var impostor: ColonyController = _match.controllers[1]
	winner.set_display_name(SHARED_NAME)
	impostor.set_display_name(SHARED_NAME)

	GameTransport.set("_match", _match)
	(
		GameTransport
		. set(
			"_participant_history",
			{
				"player-winner": {"team_id": winner.team_id, "disconnected": false},
				"player-impostor": {"team_id": impostor.team_id, "disconnected": false},
			}
		)
	)

	var payload: Dictionary = GameTransport._build_match_result_payload(winner.team_id)
	var participants_variant: Variant = payload.get("participants", [])
	if not participants_variant is Array or (participants_variant as Array).size() != 2:
		_fail("Match result payload did not carry both participants")
		return
	var participants: Array = participants_variant
	var first: Dictionary = participants[0]
	if int(first.get("team_id", -1)) != winner.team_id:
		_failures.append(
			(
				"Result credited team %d, but team %d won (both colonies are named %s)"
				% [int(first.get("team_id", -1)), winner.team_id, SHARED_NAME]
			)
		)
	if int(first.get("placement", 0)) != 1:
		_failures.append("Winning colony was not placed first")

	# The signal the server reads the winner from has to carry the id at all.
	var hub_signals: Array = MatchEventHub.new().get_signal_list()
	var carries_team_id: bool = false
	for signal_info in hub_signals:
		if String(signal_info.get("name", "")) != "match_ended":
			continue
		for argument in signal_info.get("args", []):
			if String(argument.get("name", "")) == "winner_team_id":
				carries_team_id = true
	if not carries_team_id:
		_failures.append("match_ended does not carry the winning team id")

	_finish()


func _finish() -> void:
	if is_instance_valid(_match):
		_match.queue_free()
	if _failures.is_empty():
		print("PASS match_result_winner_regression_test")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
