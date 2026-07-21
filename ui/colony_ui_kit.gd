class_name ColonyUiKit
extends RefCounted

const BACKDROP := Color("090b0b")
const SURFACE := Color("121515")
const SURFACE_RAISED := Color("181c1c")
const SURFACE_SELECTED := Color("1f261f")
const BORDER := Color("394140")
const BORDER_STRONG := Color("5c6966")
const ACCENT := Color("f1b83b")
const ACCENT_HOVER := Color("ffc957")
const SUCCESS := Color("55c88a")
const DANGER := Color("ff7469")
const TEXT_PRIMARY := Color("f4f2e9")
const TEXT_SECONDARY := Color("b8bfba")
const TEXT_MUTED := Color("7f8984")


static func apply_label(
	label: Label, font_size: int, weight: int = 400, color: Color = TEXT_PRIMARY
) -> void:
	label.add_theme_font_override("font", make_font(weight))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


static func apply_rich_text(
	label: RichTextLabel, font_size: int, weight: int = 400, color: Color = TEXT_PRIMARY
) -> void:
	label.add_theme_font_override("normal_font", make_font(weight))
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", color)


static func apply_button(button: Button, variant: StringName, height: float = 52.0) -> void:
	button.custom_minimum_size.y = height
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", make_font(650))
	button.add_theme_font_size_override("font_size", 16)

	var palette: Dictionary = _button_palette(variant)
	var background: Color = palette.get("background", SURFACE_RAISED)
	var hover_color: Color = palette.get("hover", SURFACE_SELECTED)
	var pressed_color: Color = palette.get("pressed", SURFACE)
	var border_color: Color = palette.get("border", BORDER)
	var border_hover_color: Color = palette.get("border_hover", BORDER_STRONG)
	var text_color: Color = palette.get("text", TEXT_PRIMARY)
	var text_hover_color: Color = palette.get("text_hover", TEXT_PRIMARY)
	var normal := rounded_style(
		background, border_color, 1, 14, Vector4(16.0, 12.0, 16.0, 12.0)
	)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover_color
	hover.border_color = border_hover_color
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = pressed_color
	pressed.content_margin_top += 2.0
	pressed.content_margin_bottom = maxf(pressed.content_margin_bottom - 2.0, 0.0)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(background, 0.42)
	disabled.border_color = Color(border_color, 0.34)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = ACCENT
	focus.set_border_width_all(2)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_hover_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_hover_color)
	button.add_theme_color_override("font_disabled_color", Color(TEXT_MUTED, 0.74))


static func apply_input(input: LineEdit) -> void:
	input.custom_minimum_size.y = 58.0
	input.add_theme_font_override("font", make_font(500))
	input.add_theme_font_size_override("font_size", 17)
	input.add_theme_color_override("font_color", TEXT_PRIMARY)
	input.add_theme_color_override("font_placeholder_color", Color(TEXT_MUTED, 0.92))
	input.add_theme_color_override("caret_color", ACCENT)
	var normal := rounded_style(
		Color("0d1010"), BORDER, 1, 13, Vector4(16.0, 13.0, 16.0, 13.0)
	)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color("111514")
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	input.add_theme_stylebox_override("normal", normal)
	input.add_theme_stylebox_override("focus", focus)
	input.add_theme_stylebox_override("read_only", normal)


static func panel_style() -> StyleBoxFlat:
	return rounded_style(
		Color(SURFACE, 0.985),
		Color(ACCENT, 0.92),
		2,
		24,
		Vector4(26.0, 24.0, 26.0, 24.0)
	)


static func card_style(selected: bool = false) -> StyleBoxFlat:
	return rounded_style(
		SURFACE_SELECTED if selected else SURFACE_RAISED,
		Color(ACCENT, 0.88) if selected else BORDER,
		2 if selected else 1,
		16,
		Vector4(10.0, 10.0, 10.0, 10.0)
	)


static func status_style(tone: StringName = &"neutral") -> StyleBoxFlat:
	var border := BORDER
	var background := Color("0e1111")
	match tone:
		&"success":
			border = Color(SUCCESS, 0.72)
			background = Color(SUCCESS, 0.08)
		&"danger":
			border = Color(DANGER, 0.72)
			background = Color(DANGER, 0.08)
		&"accent":
			border = Color(ACCENT, 0.72)
			background = Color(ACCENT, 0.07)
	return rounded_style(background, border, 1, 12, Vector4(14.0, 10.0, 14.0, 10.0))


static func rounded_style(
	background: Color,
	border: Color,
	border_width: int,
	radius: int,
	margins: Vector4 = Vector4.ZERO
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	return style


static func make_font(weight: int = 400) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Roboto", "Noto Sans", "sans-serif"])
	font.font_weight = clampi(weight, 100, 900)
	font.allow_system_fallback = true
	font.force_autohinter = true
	return font


static func _button_palette(variant: StringName) -> Dictionary:
	match variant:
		&"primary":
			return {
				"background": ACCENT,
				"hover": ACCENT_HOVER,
				"pressed": ACCENT.darkened(0.13),
				"border": ACCENT.lightened(0.20),
				"border_hover": ACCENT.lightened(0.34),
				"text": Color("17130a"),
				"text_hover": Color("0d0b06"),
			}
		&"danger":
			return {
				"background": Color(DANGER, 0.15),
				"hover": Color(DANGER, 0.24),
				"pressed": Color(DANGER, 0.11),
				"border": Color(DANGER, 0.75),
				"border_hover": DANGER,
				"text": Color("ffd8d4"),
				"text_hover": Color.WHITE,
			}
		&"ghost":
			return {
				"background": Color("101313"),
				"hover": Color("1a1f1e"),
				"pressed": Color("0b0e0e"),
				"border": BORDER,
				"border_hover": BORDER_STRONG,
				"text": TEXT_SECONDARY,
				"text_hover": TEXT_PRIMARY,
			}
		_:
			return {
				"background": Color("171b1a"),
				"hover": Color("222826"),
				"pressed": Color("101313"),
				"border": BORDER_STRONG,
				"border_hover": Color(ACCENT, 0.72),
				"text": TEXT_PRIMARY,
				"text_hover": Color.WHITE,
			}
