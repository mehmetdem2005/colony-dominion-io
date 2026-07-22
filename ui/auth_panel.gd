class_name AuthPanel
extends PanelContainer

signal authenticated
signal closed

var _status_panel: PanelContainer
var _status: Label
var _google_sign_in: Button
var _close_button: Button
var _busy: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(620.0, 430.0)
	_build()


func open_panel(_default_name: String = "") -> void:
	visible = true
	_set_status("Çevrim içi oynamak için Google hesabınla güvenli giriş yap.", &"neutral")
	call_deferred("_focus_google_button")


func close_panel() -> void:
	if _busy:
		OnlineServices.cancel_google_sign_in()
		_busy = false
	visible = false
	closed.emit()


func _build() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-330.0, -225.0)
	size = Vector2(660.0, 450.0)
	add_theme_stylebox_override("panel", ColonyUiKit.panel_style())

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	var eyebrow := Label.new()
	eyebrow.text = "COLONY DOMINION ID"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ColonyUiKit.apply_label(eyebrow, 12, 750, ColonyUiKit.ACCENT)
	box.add_child(eyebrow)

	var title := Label.new()
	title.text = "Google ile giriş yap"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ColonyUiKit.apply_label(title, 31, 750, ColonyUiKit.TEXT_PRIMARY)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = (
		"Oyuncu kimliğin, görünen adın ve çevrim içi ilerlemen doğrulanmış Google "
		+ "hesabına bağlanır. E-posta veya şifre formu kullanılmaz."
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(540.0, 58.0)
	ColonyUiKit.apply_label(subtitle, 15, 450, ColonyUiKit.TEXT_SECONDARY)
	box.add_child(subtitle)

	_google_sign_in = Button.new()
	_google_sign_in.text = "G  •  GOOGLE İLE DEVAM ET"
	_google_sign_in.custom_minimum_size = Vector2(500.0, 64.0)
	_google_sign_in.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ColonyUiKit.apply_button(_google_sign_in, &"primary", 64.0)
	_google_sign_in.pressed.connect(_on_google_sign_in)
	box.add_child(_google_sign_in)

	_status_panel = PanelContainer.new()
	_status_panel.custom_minimum_size = Vector2(540.0, 68.0)
	_status_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_status_panel)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ColonyUiKit.apply_label(_status, 14, 550, ColonyUiKit.TEXT_SECONDARY)
	_status_panel.add_child(_status)

	_close_button = Button.new()
	_close_button.text = "KAPAT"
	_close_button.custom_minimum_size = Vector2(190.0, 50.0)
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ColonyUiKit.apply_button(_close_button, &"ghost", 50.0)
	_close_button.pressed.connect(close_panel)
	box.add_child(_close_button)

	var note := Label.new()
	note.text = "Android'de Google hesabını oyundan çıkmadan telefonun güvenli hesap penceresinden seçersin; şifren oyuna veya Supabase'e verilmez."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(540.0, 38.0)
	ColonyUiKit.apply_label(note, 12, 450, ColonyUiKit.TEXT_MUTED)
	box.add_child(note)


func _on_google_sign_in() -> void:
	if _busy:
		return
	_set_busy(true, "Google hesap seçicisi açılıyor...")
	var result: Dictionary = await OnlineServices.sign_in_google()
	_set_busy(false, "")
	if not visible:
		return
	if bool(result.get("ok", false)):
		_set_status("Google hesabı bağlandı. Çevrim içi hizmetler hazırlanıyor.", &"success")
		visible = false
		authenticated.emit()
		return
	_show_error(String(result.get("error", "Google ile giriş başarısız")))


func _set_busy(value: bool, message: String) -> void:
	_busy = value
	_google_sign_in.disabled = value
	_close_button.text = "GOOGLE GİRİŞİNİ İPTAL ET" if value else "KAPAT"
	if not message.is_empty():
		_set_status(message, &"accent")


func _set_status(message: String, tone: StringName) -> void:
	_status.text = message
	_status_panel.add_theme_stylebox_override("panel", ColonyUiKit.status_style(tone))
	var color := ColonyUiKit.TEXT_SECONDARY
	if tone == &"success":
		color = ColonyUiKit.SUCCESS
	elif tone == &"danger":
		color = ColonyUiKit.DANGER
	elif tone == &"accent":
		color = ColonyUiKit.ACCENT
	_status.add_theme_color_override("font_color", color)


func _show_error(message: String) -> void:
	_set_status(message, &"danger")


func _focus_google_button() -> void:
	if is_instance_valid(_google_sign_in):
		_google_sign_in.grab_focus()
