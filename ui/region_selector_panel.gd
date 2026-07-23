class_name RegionSelectorPanel
extends PanelContainer

## AAA server-region picker. Auto (nearest edge) is the recommended hero option;
## every real Edgegap location is listed underneath, grouped by continent with an
## honest proximity label instead of a fabricated ping. Selecting a region pins
## the next match to that city's edge node.

signal region_selected(region_id: String)
signal closed

# Continent grouping + a coarse, honest proximity band for a Türkiye/EU player.
# (No live probe exists for Edgegap edges, so we never show a fake millisecond
# number — the real ping is measured once the match connects.)
const REGION_META: Dictionary = {
	"frankfurt": {"group": "Avrupa", "proximity": "near"},
	"paris": {"group": "Avrupa", "proximity": "near"},
	"newark": {"group": "Kuzey Amerika", "proximity": "far"},
	"chicago": {"group": "Kuzey Amerika", "proximity": "far"},
	"dallas": {"group": "Kuzey Amerika", "proximity": "far"},
	"seattle": {"group": "Kuzey Amerika", "proximity": "far"},
	"fremont": {"group": "Kuzey Amerika", "proximity": "far"},
	"saopaulo": {"group": "Güney Amerika", "proximity": "farthest"},
	"mumbai": {"group": "Asya", "proximity": "far"},
	"singapore": {"group": "Asya", "proximity": "farthest"},
}
const GROUP_ORDER: Array[String] = ["Avrupa", "Kuzey Amerika", "Asya", "Güney Amerika"]

var _list: VBoxContainer
var _buttons: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(680.0, 620.0)
	_build()
	OnlineServices.regions_changed.connect(refresh)


func open_panel() -> void:
	visible = true
	refresh()


func close_panel() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	_buttons.clear()

	# Hero row: automatic nearest-edge placement (the recommended default).
	_add_region_card("auto", "Otomatik — En Yakın Sunucu", "AUTO", "auto", true)

	# Group the real locations by continent in a deliberate order.
	var by_group: Dictionary = {}
	for region in OnlineServices.get_regions():
		var region_id: String = String(region.get("id", ""))
		var meta: Dictionary = REGION_META.get(region_id, {})
		var group: String = String(meta.get("group", "Diğer"))
		if not by_group.has(group):
			by_group[group] = []
		(by_group[group] as Array).append(region)

	for group_name in GROUP_ORDER:
		if not by_group.has(group_name):
			continue
		var suffix: String = "  •  en yakın" if group_name == "Avrupa" else ""
		_list.add_child(ColonyUiKit.section_label(group_name + suffix))
		for region in by_group[group_name]:
			var region_id: String = String(region.get("id", ""))
			var meta: Dictionary = REGION_META.get(region_id, {})
			_add_region_card(
				region_id,
				String(region.get("display_name", region_id)),
				String(region.get("short_name", "")),
				String(meta.get("proximity", "far")),
				bool(region.get("enabled", true))
			)


func _build() -> void:
	add_theme_stylebox_override("panel", ColonyUiKit.panel_style())

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	add_child(root_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_box.add_child(header)
	var mark := ColonyUiKit.accent_bar(6.0, 34.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mark)
	var title := Label.new()
	title.text = "SUNUCU BÖLGESİ"
	ColonyUiKit.apply_label(title, 26, 800, ColonyUiKit.ACCENT)
	header.add_child(title)

	var hint := Label.new()
	hint.text = (
		"Otomatik, IP'ne en yakın Edgegap noktasını seçer (önerilen). "
		+ "İstersen belirli bir şehri sabitleyebilirsin — gerçek ping maçta ölçülür."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ColonyUiKit.apply_label(hint, 14, 400, ColonyUiKit.TEXT_SECONDARY)
	root_box.add_child(hint)

	root_box.add_child(ColonyUiKit.accent_bar(120.0, 2.0, Color(ColonyUiKit.ACCENT, 0.7)))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 7)
	scroll.add_child(_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root_box.add_child(footer)
	var close_button := Button.new()
	close_button.text = "KAPAT"
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ColonyUiKit.apply_button(close_button, &"ghost", 50.0)
	close_button.pressed.connect(close_panel)
	footer.add_child(close_button)


func _add_region_card(
	region_id: String, display_name: String, short_name: String, proximity: String, enabled: bool
) -> void:
	var is_selected: bool = region_id == NetworkSession.preferred_region_id
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not enabled
	button.text = (
		"%s%s   ·   %s   —   %s"
		% [
			"✓  " if is_selected else "",
			display_name,
			short_name,
			_proximity_label(region_id, proximity),
		]
	)
	ColonyUiKit.apply_button(button, &"primary" if is_selected else &"ghost", 58.0)
	button.pressed.connect(_select.bind(region_id))
	_list.add_child(button)
	_buttons[region_id] = button


func _proximity_label(region_id: String, proximity: String) -> String:
	if region_id == "auto":
		return "Önerilen • otomatik seçim"
	match proximity:
		"near":
			return "Düşük ping"
		"farthest":
			return "Çok yüksek ping"
		_:
			return "Yüksek ping"


func _select(region_id: String) -> void:
	OnlineServices.select_region(region_id)
	region_selected.emit(region_id)
	close_panel()
