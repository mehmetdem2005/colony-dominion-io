class_name AuthPanel
extends PanelContainer

signal authenticated
signal closed

var _email: LineEdit
var _password: LineEdit
var _display_name: LineEdit
var _status: Label
var _sign_in: Button
var _sign_up: Button
var _busy: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func open_panel(default_name: String = "") -> void:
	visible = true
	_display_name.text = default_name
	_status.text = ""
	_email.grab_focus()


func close_panel() -> void:
	if _busy:
		return
	visible = false
	closed.emit()


func _build() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-310.0, -260.0)
	size = Vector2(620.0, 520.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.026, 0.022, 0.98)
	style.border_color = Color(0.92, 0.70, 0.19, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 26.0
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "ÇEVRİM İÇİ HESAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("ffd45a"))
	box.add_child(title)

	_email = _make_input("E-posta", false)
	box.add_child(_email)
	_password = _make_input("Şifre — en az 8 karakter", true)
	box.add_child(_password)
	_display_name = _make_input("Görünen oyuncu adı", false)
	_display_name.max_length = 24
	box.add_child(_display_name)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 54.0
	_status.add_theme_font_size_override("font_size", 15)
	box.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_sign_in = Button.new()
	_sign_in.text = "GİRİŞ YAP"
	_sign_in.custom_minimum_size = Vector2(210.0, 58.0)
	_sign_in.pressed.connect(_on_sign_in)
	buttons.add_child(_sign_in)
	_sign_up = Button.new()
	_sign_up.text = "HESAP OLUŞTUR"
	_sign_up.custom_minimum_size = Vector2(210.0, 58.0)
	_sign_up.pressed.connect(_on_sign_up)
	buttons.add_child(_sign_up)

	var close_button := Button.new()
	close_button.text = "KAPAT"
	close_button.custom_minimum_size = Vector2(180.0, 48.0)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close_panel)
	box.add_child(close_button)

	var note := Label.new()
	note.text = "Parola uygulama içinde saklanmaz. Service-role veya gizli sunucu anahtarı istemciye konmaz."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.70, 0.74, 0.67, 1.0))
	box.add_child(note)


func _make_input(placeholder: String, secret: bool) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = secret
	input.custom_minimum_size = Vector2(500.0, 54.0)
	input.add_theme_font_size_override("font_size", 18)
	return input


func _on_sign_in() -> void:
	if not _validate_inputs(false):
		return
	_set_busy(true, "Giriş yapılıyor...")
	var result: Dictionary = await OnlineServices.auth.sign_in_email(_email.text, _password.text)
	_set_busy(false, "")
	if bool(result.get("ok", false)):
		_password.clear()
		_status.text = "Giriş başarılı"
		visible = false
		authenticated.emit()
		return
	_show_error(String(result.get("error", "Giriş başarısız")))


func _on_sign_up() -> void:
	if not _validate_inputs(true):
		return
	_set_busy(true, "Hesap oluşturuluyor...")
	var result: Dictionary = await OnlineServices.auth.sign_up_email(
		_email.text, _password.text, _display_name.text
	)
	_set_busy(false, "")
	if bool(result.get("ok", false)):
		_password.clear()
		if OnlineServices.auth.has_session():
			_status.text = "Hesap oluşturuldu"
			visible = false
			authenticated.emit()
		else:
			_status.text = "Hesap oluşturuldu. E-posta doğrulamasını tamamla."
		return
	_show_error(String(result.get("error", "Kayıt başarısız")))


func _validate_inputs(require_name: bool) -> bool:
	if not _email.text.contains("@"):
		_show_error("Geçerli bir e-posta adresi gir")
		return false
	if _password.text.length() < 8:
		_show_error("Şifre en az 8 karakter olmalı")
		return false
	if require_name and _display_name.text.strip_edges().length() < 2:
		_show_error("Görünen oyuncu adı en az 2 karakter olmalı")
		return false
	return true


func _set_busy(value: bool, message: String) -> void:
	_busy = value
	_sign_in.disabled = value
	_sign_up.disabled = value
	_email.editable = not value
	_password.editable = not value
	_display_name.editable = not value
	_status.text = message
	_status.add_theme_color_override("font_color", Color(0.88, 0.82, 0.56, 1.0))


func _show_error(message: String) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", Color(1.0, 0.38, 0.30, 1.0))
