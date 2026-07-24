class_name OnlineProfilePanel
extends PanelContainer

signal closed

enum ViewMode {
	COMBINED,
	PROFILE,
	RANKING,
}

var _title: Label
var _summary: Label
var _history: Label
var _leaderboard: Label
var _refresh_button: Button
var _view_mode: ViewMode = ViewMode.COMBINED


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-360.0, -300.0)
	size = Vector2(720.0, 600.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.025, 0.02, 0.98)
	style.border_color = Color(0.30, 0.75, 1.0, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	style.set_content_margin_all(24.0)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	_title = Label.new()
	_title.text = "ÇEVRİM İÇİ PROFİL"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 27)
	box.add_child(_title)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 20)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_summary)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 18)
	box.add_child(columns)
	_history = Label.new()
	_history.custom_minimum_size = Vector2(310.0, 390.0)
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history.add_theme_font_size_override("font_size", 15)
	columns.add_child(_history)
	_leaderboard = Label.new()
	_leaderboard.custom_minimum_size = Vector2(320.0, 390.0)
	_leaderboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leaderboard.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_leaderboard.add_theme_font_size_override("font_size", 15)
	columns.add_child(_leaderboard)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_refresh_button = Button.new()
	_refresh_button.text = "YENİLE"
	_refresh_button.pressed.connect(_refresh)
	row.add_child(_refresh_button)
	var close_button := Button.new()
	close_button.text = "KAPAT"
	close_button.pressed.connect(_close)
	row.add_child(close_button)


func open_panel() -> void:
	_open_mode(ViewMode.COMBINED)


func open_profile() -> void:
	_open_mode(ViewMode.PROFILE)


func open_ranking() -> void:
	_open_mode(ViewMode.RANKING)


func _open_mode(mode: ViewMode) -> void:
	_view_mode = mode
	_apply_mode_layout()
	visible = true
	_refresh()


func _apply_mode_layout() -> void:
	match _view_mode:
		ViewMode.PROFILE:
			_title.text = "OYUNCU PROFİLİ"
			_summary.visible = true
			_history.visible = true
			_leaderboard.visible = false
			_history.custom_minimum_size = Vector2(640.0, 390.0)
		ViewMode.RANKING:
			_title.text = "SEZON SIRALAMASI"
			_summary.visible = false
			_history.visible = false
			_leaderboard.visible = true
			_leaderboard.custom_minimum_size = Vector2(640.0, 430.0)
		_:
			_title.text = "ÇEVRİM İÇİ PROFİL"
			_summary.visible = true
			_history.visible = true
			_leaderboard.visible = true
			_history.custom_minimum_size = Vector2(310.0, 390.0)
			_leaderboard.custom_minimum_size = Vector2(320.0, 390.0)


func _refresh() -> void:
	_refresh_button.disabled = true
	_summary.text = ""
	_history.text = ""
	_leaderboard.text = ""
	match _view_mode:
		ViewMode.PROFILE:
			_summary.text = "Profil yükleniyor..."
			var profile_rating_result: Dictionary = await OnlineServices.data.fetch_current_rating()
			var profile_history_result: Dictionary = await OnlineServices.data.fetch_rating_history(
				8
			)
			_summary.text = _format_rating(profile_rating_result)
			_history.text = _format_history(profile_history_result)
		ViewMode.RANKING:
			_leaderboard.text = "Sıralama yükleniyor..."
			var ranking_result: Dictionary = await OnlineServices.data.fetch_leaderboard(20)
			_leaderboard.text = _format_leaderboard(ranking_result)
		_:
			_summary.text = "Profil yükleniyor..."
			var combined_rating_result: Dictionary = await (
				OnlineServices.data.fetch_current_rating()
			)
			var combined_history_result: Dictionary = await (
				OnlineServices.data.fetch_rating_history(8)
			)
			var combined_leaderboard_result: Dictionary = await (
				OnlineServices.data.fetch_leaderboard(12)
			)
			_summary.text = _format_rating(combined_rating_result)
			_history.text = _format_history(combined_history_result)
			_leaderboard.text = _format_leaderboard(combined_leaderboard_result)
	_refresh_button.disabled = false


func _format_rating(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return "Puan bilgisi alınamadı"
	var rows: Variant = result.get("body", [])
	if not rows is Array or (rows as Array).is_empty():
		return "Puan 1000 • Henüz dereceli maç yok"
	var row: Dictionary = (rows as Array)[0]
	return (
		"Puan %d • Zirve %d • %dG / %dM • %d maç"
		% [
			int(row.get("rating", 1000)),
			int(row.get("peak_rating", 1000)),
			int(row.get("wins", 0)),
			int(row.get("losses", 0)),
			int(row.get("matches_played", 0))
		]
	)


func _format_history(result: Dictionary) -> String:
	var text: String = "SON MAÇLAR\n\n"
	var rows: Variant = result.get("body", [])
	if not bool(result.get("ok", false)) or not rows is Array:
		return text + "Geçmiş alınamadı"
	for row_variant in rows as Array:
		if not row_variant is Dictionary:
			continue
		var row: Dictionary = row_variant
		var delta: int = int(row.get("rating_delta", 0))
		text += (
			"%d. sıra  •  %s%d  → %d\n"
			% [
				int(row.get("placement", 0)),
				"+" if delta >= 0 else "",
				delta,
				int(row.get("rating_after", 1000))
			]
		)
	return text + ("Henüz maç yok" if (rows as Array).is_empty() else "")


func _format_leaderboard(result: Dictionary) -> String:
	var text: String = "SEZON LİDERLERİ\n\n"
	var rows: Variant = result.get("body", [])
	if not bool(result.get("ok", false)) or not rows is Array:
		return text + "Liderlik tablosu alınamadı"
	for row_variant in rows as Array:
		if not row_variant is Dictionary:
			continue
		var row: Dictionary = row_variant
		text += (
			"%d. %s  —  %d\n"
			% [
				int(row.get("rank", 0)),
				String(row.get("display_name", "Player")).left(18),
				int(row.get("rating", 1000))
			]
		)
	return text


func _close() -> void:
	visible = false
	closed.emit()
