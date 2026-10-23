class_name UIStyle
extends RefCounted
## Единый источник визуального стиля для программно создаваемого UI.
##
## Все значения взяты из существующих .tscn-файлов проекта:
##   - menu.tscn         (панель, PlayButton, EndlessButton)
##   - hud.tscn          (UpgradeScreen, RerollButton/SkipButton, ContinueButton)
##   - UpgradeCard.tscn  (фон карточки, сепаратор)
##
## Задача: любой UI, созданный через GDScript, должен выглядеть как
## продолжение этих сцен, а не как отдельная система.

# --- Шрифт ---
const FONT: FontFile = preload("res://fonts/montserrat.bold.ttf")
const FONT_SIZE_TITLE: int = 34
const FONT_SIZE_TITLE_SMALL: int = 24
const FONT_SIZE_BUTTON: int = 18
const FONT_SIZE_BODY: int = 16
const FONT_SIZE_SMALL: int = 14
const FONT_SIZE_TINY: int = 12

# --- Палитра (эталон — menu.tscn / hud.tscn / UpgradeCard.tscn) ---
const COLOR_PANEL_BG := Color(0.08235294, 0.07450981, 0.101960786, 1.0)
const COLOR_PANEL_BORDER := Color(1.353256, 0.8926054, 0.19116017, 1.0)
const COLOR_PANEL_SHADOW := Color(0, 0, 0, 0.35)

const COLOR_PANEL_DARK_BG := Color(0.05490196, 0.078431375, 0.11764706, 1.0)
const COLOR_PANEL_DARK_BORDER := Color(0.16862746, 0.24313726, 0.33333334, 1.0)

const COLOR_STAT_BG := Color(0.03137255, 0.047058824, 0.07058824, 1.0)
const COLOR_STAT_BORDER := Color(0.101960786, 0.14117648, 0.2, 1.0)

const COLOR_TEXT := Color(0.9411765, 0.9490196, 0.9607843, 1.0)
const COLOR_TEXT_MUTED := Color(0.5647059, 0.59607846, 0.65882355, 1.0)
const COLOR_ACCENT_GOLD := Color(0.9411765, 0.7411765, 0.16862746, 1.0)
const COLOR_DANGER := Color(0.9137255, 0.3529412, 0.3529412, 1.0)
const COLOR_SEPARATOR := Color(0.22745098, 0.24705882, 0.2901961, 1.0)

# --- Кнопки ---
# Основная синяя (menu.tscn::PlayButton, hud.tscn::ContinueButton)
const COLOR_PRIMARY_BG := Color(0.0, 0.35686275, 0.61960787, 1.0)
const COLOR_PRIMARY_BORDER := Color(0.0, 0.44138998, 0.7580579, 1.0)
const COLOR_PRIMARY_HOVER := Color(0.0, 0.41011435, 0.7068303, 1.0)
const COLOR_PRIMARY_PRESSED := Color(0.0, 0.45714575, 0.78386474, 1.0)

# Вторичная фиолетовая (menu.tscn::EndlessButton)
const COLOR_SECONDARY_BG := Color(0.29803923, 0.10980392, 0.49803922, 1.0)
const COLOR_SECONDARY_BORDER := Color(0.5411765, 0.21960784, 0.8784314, 1.0)
const COLOR_SECONDARY_HOVER := Color(0.37254903, 0.14509805, 0.60784316, 1.0)
const COLOR_SECONDARY_PRESSED := Color(0.34901962, 0.12941177, 0.56078434, 1.0)

# Контурная серая (hud.tscn::RerollButton / SkipButton)
const COLOR_OUTLINE_BORDER := Color(0.49878418, 0.4987843, 0.49878395, 1.0)
const COLOR_OUTLINE_HOVER_BG := Color(0, 0, 0, 0.15686275)
const COLOR_OUTLINE_PRESSED_BG := Color(0.6, 0.6, 0.6, 0.23137255)


# ==================== ПАНЕЛИ ====================

static func make_panel_style(radius: int = 20, with_shadow: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_PANEL_BG
	s.border_color = COLOR_PANEL_BORDER
	s.set_border_width_all(2)
	s.border_width_bottom = 1
	s.border_blend = true
	s.set_corner_radius_all(radius)
	if with_shadow:
		s.shadow_color = COLOR_PANEL_SHADOW
		s.shadow_size = 24
	return s


static func make_danger_panel_style(radius: int = 20, with_shadow: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_PANEL_BG
	s.border_color = COLOR_DANGER
	s.set_border_width_all(2)
	s.border_width_bottom = 1
	s.border_blend = true
	s.set_corner_radius_all(radius)
	if with_shadow:
		s.shadow_color = COLOR_PANEL_SHADOW
		s.shadow_size = 24
	return s


static func make_dark_panel_style(radius: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_PANEL_DARK_BG
	s.border_color = COLOR_PANEL_DARK_BORDER
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	return s


static func make_stat_panel_style(radius: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_STAT_BG
	s.border_color = COLOR_STAT_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	return s


# ==================== КНОПКИ ====================

static func _make_button_box(bg: Color, border: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if border_width > 0:
		s.border_color = border
		s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	return s


static func apply_primary_button(button: Button, radius: int = 10) -> void:
	button.add_theme_stylebox_override("normal",
		_make_button_box(COLOR_PRIMARY_BG, COLOR_PRIMARY_BORDER, radius))
	button.add_theme_stylebox_override("hover",
		_make_button_box(COLOR_PRIMARY_HOVER, COLOR_PRIMARY_BORDER, radius))
	button.add_theme_stylebox_override("pressed",
		_make_button_box(COLOR_PRIMARY_PRESSED, COLOR_PRIMARY_BORDER, radius))
	var disabled := _make_button_box(COLOR_PRIMARY_BG, COLOR_PRIMARY_BORDER, radius)
	disabled.bg_color = Color(COLOR_PRIMARY_BG.r, COLOR_PRIMARY_BG.g, COLOR_PRIMARY_BG.b, 0.45)
	button.add_theme_stylebox_override("disabled", disabled)
	_apply_button_text(button)


static func apply_secondary_button(button: Button, radius: int = 10) -> void:
	button.add_theme_stylebox_override("normal",
		_make_button_box(COLOR_SECONDARY_BG, COLOR_SECONDARY_BORDER, radius))
	button.add_theme_stylebox_override("hover",
		_make_button_box(COLOR_SECONDARY_HOVER, COLOR_SECONDARY_BORDER, radius))
	button.add_theme_stylebox_override("pressed",
		_make_button_box(COLOR_SECONDARY_PRESSED, COLOR_SECONDARY_BORDER, radius))
	_apply_button_text(button)


static func apply_outline_button(button: Button, radius: int = 20) -> void:
	button.add_theme_stylebox_override("normal",
		_make_button_box(Color(0, 0, 0, 0), COLOR_OUTLINE_BORDER, radius))
	button.add_theme_stylebox_override("hover",
		_make_button_box(COLOR_OUTLINE_HOVER_BG, COLOR_OUTLINE_BORDER, radius))
	button.add_theme_stylebox_override("pressed",
		_make_button_box(COLOR_OUTLINE_PRESSED_BG, COLOR_OUTLINE_BORDER, radius))
	_apply_button_text(button)


static func apply_danger_button(button: Button, radius: int = 10) -> void:
	var danger_bg := Color(0.61960787, 0.09803922, 0.09803922, 1.0)
	var danger_hover := Color(0.7176471, 0.12941177, 0.12941177, 1.0)
	var danger_pressed := Color(0.8156863, 0.14901961, 0.14901961, 1.0)
	button.add_theme_stylebox_override("normal",
		_make_button_box(danger_bg, COLOR_DANGER, radius))
	button.add_theme_stylebox_override("hover",
		_make_button_box(danger_hover, COLOR_DANGER, radius))
	button.add_theme_stylebox_override("pressed",
		_make_button_box(danger_pressed, COLOR_DANGER, radius))
	_apply_button_text(button)


static func _apply_button_text(button: Control) -> void:
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", FONT_SIZE_BUTTON)
	button.add_theme_color_override("font_color", COLOR_TEXT)


# ==================== ТЕКСТ / СЕПАРАТОРЫ ====================

static func apply_label_style(control: Control, size: int = FONT_SIZE_BODY,
		color: Color = COLOR_TEXT) -> void:
	control.add_theme_font_override("font", FONT)
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)


static func apply_separator(sep: HSeparator) -> void:
	var s := StyleBoxLine.new()
	s.color = COLOR_SEPARATOR
	s.thickness = 1
	sep.add_theme_stylebox_override("separator", s)
