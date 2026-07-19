extends SceneTree

const UNIT_SCENE := preload("res://scenes/units/unit.tscn")

const MINIMUM_TEXTURE_HEIGHTS: Dictionary = {
	"res://assets/units/commander.png": 512,
	"res://assets/units/worker.png": 512,
	"res://assets/units/soldier.png": 512,
	"res://assets/resources/seeds.png": 300,
	"res://assets/props/large_rock.png": 400,
	"res://assets/structures/nest_blue.png": 480,
}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)):
		_fail("Physics interpolation is disabled")
		return
	var unit := UNIT_SCENE.instantiate() as ColonyUnit
	root.add_child(unit)
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
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
