extends Node
## Persistent display and graphics settings.
##
## Loaded as an autoload so the stored window mode, refresh limits and quality
## level are applied at boot (before any scene renders) and re-applied whenever
## the player changes them from the settings panel.

signal settings_changed

const SETTINGS_PATH: String = "user://display_settings.cfg"

enum WindowMode { WINDOWED, FULLSCREEN }
enum Quality { LOW, MEDIUM, HIGH }

const FPS_OPTIONS: Array[int] = [30, 60, 120, 0]
const DEFAULTS: Dictionary = {
	"window_mode": WindowMode.WINDOWED,
	"vsync": true,
	"max_fps": 60,
	"quality": Quality.HIGH,
	"show_fps": false,
}

var _settings: Dictionary = DEFAULTS.duplicate(true)
var _headless: bool = false
var _fps_layer: CanvasLayer
var _fps_label: Label
var _fps_accumulator: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = _detect_headless()
	_load()
	if _headless:
		set_process(false)
		return
	_build_fps_overlay()
	apply_all()


func _process(delta: float) -> void:
	if not bool(_settings.get("show_fps", false)) or not is_instance_valid(_fps_label):
		return
	_fps_accumulator += delta
	if _fps_accumulator < 0.25:
		return
	_fps_accumulator = 0.0
	_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func get_value(key: String) -> Variant:
	return _settings.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	_settings[key] = value
	_save()
	if not _headless:
		apply_all()
	settings_changed.emit()


func reset_to_defaults() -> void:
	_settings = DEFAULTS.duplicate(true)
	_save()
	if not _headless:
		apply_all()
	settings_changed.emit()


func apply_all() -> void:
	if _headless:
		return
	_apply_window_mode()
	_apply_vsync()
	_apply_max_fps()
	_apply_quality()
	_apply_fps_overlay()


func _apply_window_mode() -> void:
	if OS.has_feature("mobile"):
		return
	var mode: int = int(_settings.get("window_mode", WindowMode.WINDOWED))
	var target: DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if mode == WindowMode.FULLSCREEN
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != target:
		DisplayServer.window_set_mode(target)


func _apply_vsync() -> void:
	var enabled: bool = bool(_settings.get("vsync", true))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	)


func _apply_max_fps() -> void:
	var fps: int = int(_settings.get("max_fps", 60))
	Engine.max_fps = maxi(fps, 0)


func _apply_quality() -> void:
	var window: Window = get_window()
	if window == null:
		return
	var quality: int = int(_settings.get("quality", Quality.HIGH))
	match quality:
		Quality.LOW:
			window.msaa_2d = Viewport.MSAA_DISABLED
		Quality.MEDIUM:
			window.msaa_2d = Viewport.MSAA_2X
		_:
			window.msaa_2d = Viewport.MSAA_4X


func _apply_fps_overlay() -> void:
	if not is_instance_valid(_fps_label):
		return
	_fps_label.visible = bool(_settings.get("show_fps", false))


func _build_fps_overlay() -> void:
	_fps_layer = CanvasLayer.new()
	_fps_layer.name = "FpsOverlayLayer"
	_fps_layer.layer = 512
	add_child(_fps_layer)
	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-118.0, 8.0)
	_fps_label.custom_minimum_size = Vector2(110.0, 24.0)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.62, 1.0))
	_fps_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = false
	_fps_layer.add_child(_fps_label)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for key in DEFAULTS:
		if config.has_section_key("display", key):
			_settings[key] = config.get_value("display", key, DEFAULTS[key])


func _save() -> void:
	var config := ConfigFile.new()
	for key in _settings:
		config.set_value("display", key, _settings[key])
	config.save(SETTINGS_PATH)


func _detect_headless() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")
