extends Node

var local_team_id: int = 0
var current_match: Node = null
var player_controller: Node = null
var player_name: String = "Mehmet"
var rng := RandomNumberGenerator.new()
var match_seed: int = 738291
var online_assignment: Dictionary = {}


func _ready() -> void:
	rng.randomize()
	match_seed = int(rng.randi_range(1, 2_000_000_000))
	var environment_seed: String = OS.get_environment("MATCH_SEED")
	if environment_seed.is_valid_int():
		match_seed = maxi(1, int(environment_seed))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			match_seed = maxi(1, int(argument.trim_prefix("--seed=")))


func bind_match(match_node: Node) -> void:
	current_match = match_node


func bind_player(controller: Node) -> void:
	player_controller = controller


func set_player_name(value: String) -> void:
	var cleaned := value.strip_edges()
	if cleaned.is_empty():
		cleaned = "QueenAnt"
	player_name = cleaned.left(16)


func prepare_offline_match() -> int:
	online_assignment.clear()
	NetworkSession.set_offline()
	return prepare_new_match()


func prepare_online_match(assignment: Dictionary) -> void:
	online_assignment = assignment.duplicate(true)
	NetworkSession.set_online()
	NetworkSession.set_match_assignment(online_assignment)


func prepare_new_match() -> int:
	match_seed = int(rng.randi_range(1, 2_000_000_000))
	return match_seed


func set_match_seed(value: int) -> void:
	match_seed = maxi(1, value)


func get_match_seed() -> int:
	return match_seed


func clear() -> void:
	current_match = null
	player_controller = null
	online_assignment.clear()
