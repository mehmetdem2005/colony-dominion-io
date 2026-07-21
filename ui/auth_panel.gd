class_name AuthPanel
extends PanelContainer

signal authenticated
signal closed

var _email: LineEdit
var _password: LineEdit
var _display_name: LineEdit
var _status_panel: PanelContainer
var _status: Label
var _sign_in: Button
var _sign_up: Button
var _resend: Button
var _close_button: Button
var _busy: bool = false
var _last_signup_email: String = ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(620.0, 620.0)
	_build()


func open_panel(default_name: String = "") -> void:
	visible = true
	_display_name.text = default_name
	_set_status("E-posta adresinle giriş yap veya yeni hesap oluştur.", &"neutral")
	_resend.visible = not _last_signup_email.is_empty()
	call_deferred("_focus_email")


func close_panel() -> void:
	if _busy:
		return
	visible = false
	closed.emit()


func _build() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-330.0, -310.0)
	size = Vector2(660.0, 620.0)
	add_theme_stylebox_override("panel", ColonyUiKit.panel_style())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 13)
	add_child(box)

	var eyebrow := Label.new()
	eyebrow.text = "COLONY DOMINION ID"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ColonyUiKit.apply_label(eyebrow, 12, 750, ColonyUiKit.ACCENT)
	box.add_child(eyebrow)

	var title := Label.new()
	title.text = "Çevrim içi hesabın"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ColonyUiKit.apply_label(title, 30, 750, ColonyUiKit.TEXT_PRIMARY)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "İlerlemeni, oyuncu adını ve dereceli maçlarını güvenli biçimde eşitle."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ColonyUiKit.apply_label(subtitle, 15, 450, ColonyUiKit.TEXT_SECONDARY)
	box.add_child(subtitle)

	_email = _make_input("E-posta adresi", false)
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	box.add_child(_email)
	_password = _make_input("Şifre — en az 8 karakter", true)
	box.add_child(_password)
	_display_name = _make_input("Oyunda görünecek ad", false)
	_display_name.max_length = 24
	box.add_child(_display_name)

	_status_panel = PanelContainer.new()
	_status_panel.custom_minimum_size.y = 64.0
	box.add_child(_status_panel)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ColonyUiKit.apply_label(_status, 14, 550, ColonyUiKit.TEXT_SECONDARY)
	_status_panel.add_child(_status)

	_sign_in = Button.new()
	_sign_in.text = "GİRİŞ YAP"
	_sign_in.custom_minimum_size = Vector2(500.0, 58.0)
	_sign_in.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ColonyUiKit.apply_button(_sign_in, &"primary", 58.0)
	_sign_in.pressed.connect(_on_sign_in)
	box.add_child(_sign_in)

	_sign_up = Button.new()
	_sign_up.text = "YENİ HESAP OLUŞTUR"
	_sign_up.custom_minimum_size = Vector2(500.0, 56.0)
	_sign_up.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ColonyUiKit.apply_button(_sign_up, &"secondary", 56.0)
	_sign_up.pressed.connect(_on_sign_up)
	box.add_child(_sign_up)

	_resend = Button.new()
	_resend.text = "DOĞRULAMA E-POSTASINI TEKRAR GÖNDER"
	_resend.custom_minimum_size = Vector2(500.0, 52.0)
	_resend.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_resend.visible = false
	ColonyUiKit.apply_button(_resend, &"ghost", 52.0)
	_resend.pressed.connect(_on_resend_confirmation)
	box.add_child(_resend)

	_close_button = Button.new()
	_close_button.text = "KAPAT"
	_close_button.custom_minimum_size = Vector2(190.0, 48.0)
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ColonyUiKit.apply_button(_close_button, &"ghost", 48.0)
	_close_button.pressed.connect(close_panel)
	box.add_child(_close_button)

	var note := Label.new()
	note.text = (
		"Şifren cihazda saklanmaz. E-posta doğrulaması tamamlandıktan sonra "
		+ "bu ekrandan giriş yap."
	)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ColonyUiKit.apply_label(note, 12, 450, ColonyUiKit.TEXT_MUTED)
	box.add_child(note)


func _make_input(placeholder: String, secret: bool) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = secret
	input.custom_minimum_size = Vector2(500.0, 58.0)
	input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	input.clear_button_enabled = not secret
	ColonyUiKit.apply_input(input)
	return input


func _on_sign_in() -> void:
	if not _validate_inputs(false):
		return
	_set_busy(true, "Giriş bilgileri doğrulanıyor...")
	var result: Dictionary = await OnlineServices.auth.sign_in_email(_email.text, _password.text)
	_set_busy(false, "")
	if bool(result.get("ok", false)):
		_password.clear()
		_set_status("Giriş başarılı. Çevrim içi hizmetler hazırlanıyor.", &"success")
		visible = false
		authenticated.emit()
		return
	_show_error(String(result.get("error", "Giriş başarısız")))


func _on_sign_up() -> void:
	if not _validate_inputs(true):
		return
	_set_busy(true, "Hesap oluşturuluyor...")
	var email := _email.text.strip_edges()
	var result: Dictionary = await OnlineServices.auth.sign_up_email(
		email, _password.text, _display_name.text, _confirmation_redirect_url()
	)
	_set_busy(false, "")
	if bool(result.get("ok", false)):
		_password.clear()
		_last_signup_email = email
		if OnlineServices.auth.has_session():
			_set_status("Hesap oluşturuldu ve giriş yapıldı.", &"success")
			visible = false
			authenticated.emit()
		else:
			_set_status(
				"Doğrulama e-postası gönderildi. Bağlantıyı aç, sonra buraya dönüp Giriş Yap'a bas.",
				&"success"
			)
			_resend.visible = true
		return
	_show_error(String(result.get("error", "Kayıt başarısız")))


func _on_resend_confirmation() -> void:
	var email := _email.text.strip_edges()
	if email.is_empty():
		email = _last_signup_email
	if not email.contains("@"):
		_show_error("Doğrulama e-postasını yeniden göndermek için e-posta adresini yaz.")
		return
	_set_busy(true, "Doğrulama e-postası yeniden gönderiliyor...")
	var result: Dictionary = await OnlineServices.auth.resend_signup_confirmation(
		email, _confirmation_redirect_url()
	)
	_set_busy(false, "")
	if bool(result.get("ok", false)):
		_last_signup_email = email
		_resend.visible = true
		_set_status(
			"Yeni doğrulama e-postası gönderildi. En son gelen bağlantıyı kullan.", &"success"
		)
		return
	_show_error(String(result.get("error", "Doğrulama e-postası gönderilemedi")))


func _validate_inputs(require_name: bool) -> bool:
	if not _email.text.strip_edges().contains("@"):
		_show_error("Geçerli bir e-posta adresi gir.")
		return false
	if _password.text.length() < 8:
		_show_error("Şifre en az 8 karakter olmalı.")
		return false
	if require_name and _display_name.text.strip_edges().length() < 2:
		_show_error("Oyuncu adı en az 2 karakter olmalı.")
		return false
	return true


func _set_busy(value: bool, message: String) -> void:
	_busy = value
	_sign_in.disabled = value
	_sign_up.disabled = value
	_resend.disabled = value
	_close_button.disabled = value
	_email.editable = not value
	_password.editable = not value
	_display_name.editable = not value
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


func _confirmation_redirect_url() -> String:
	var base_url: String = OnlineServices.config.supabase_url.trim_suffix("/")
	return "%s/functions/v1/auth-confirmed" % base_url


func _focus_email() -> void:
	if is_instance_valid(_email):
		_email.grab_focus()
