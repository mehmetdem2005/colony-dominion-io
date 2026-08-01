extends Node

# Runs as a scene, not via --script: a --script run compiles this file, and
# everything it preloads, before the autoloads exist, so unit.tscn's script
# cannot compile and instantiate() hands back null. The test then had no way to
# report that and simply never terminated.

const MINIMUM_TEXTURE_HEIGHTS: Dictionary = {
	"res://assets/units/commander.png": 512,
	"res://assets/units/worker.png": 512,
	"res://assets/units/soldier.png": 512,
	"res://assets/resources/seeds.png": 300,
	"res://assets/props/large_rock.png": 400,
	"res://assets/structures/nest_blue.png": 480,
}


func _ready() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	if not bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)):
		_fail("Physics interpolation is disabled")
		return
	var unit_scene := load("res://scenes/units/unit.tscn") as PackedScene
	if unit_scene == null:
		_fail("Unit scene could not be loaded")
		return
	var unit := unit_scene.instantiate() as ColonyUnit
	if unit == null:
		_fail("Unit scene did not instantiate a ColonyUnit")
		return
	get_tree().root.add_child(unit)
	var unit_sprite := unit.get_node("VisualRoot/Sprite2D") as Sprite2D
	if unit_sprite.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		_fail("Unit art is not using smooth downscale filtering")
		return
	for path_variant in MINIMUM_TEXTURE_HEIGHTS.keys():
		var path: String = String(path_variant)
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			_fail("Could not decode visual asset: %s" % path)
			return
		if image.get_height() < int(MINIMUM_TEXTURE_HEIGHTS[path]):
			_fail("Visual asset was destructively downscaled: %s" % path)
			return
	print("PASS visual_quality_regression_test")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
