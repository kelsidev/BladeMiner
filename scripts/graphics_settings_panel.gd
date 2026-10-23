extends CanvasLayer
## Панель настроек графики и звука. Открывается из menu.gd по кнопке
## "НАСТРОЙКИ". Создаётся программно — не требует правок .tscn.
##
## Основная часть контента обёрнута в ScrollContainer: заголовок и кнопка
## "ЗАКРЫТЬ" закреплены, а середина скроллится. Так панель гарантированно
## помещается даже в очень низком окне, и закрыть её можно всегда.
##
## Тач-скролл на мобильных:
##   Godot 4's ScrollContainer не получает drag-события, если касание
##   началось на CheckBox / OptionButton / HSlider: эти контролы
##   захватывают press и становятся mouse_focus, а ScrollContainer
##   в этой drag-сессии уже не участвует. Поэтому дополнительно
##   перехватываем тач/mouse-drag через _input и прокручиваем контейнер
##   вручную (см. секцию ТАЧ-СКРОЛЛ в конце файла).

const BG_COLOR := Color(0, 0, 0, 0.65)

# Верхняя граница высоты прокручиваемой части (когда места много).
const SCROLL_MAX_HEIGHT: float = 340.0
# Нижняя граница (когда окно маленькое, но скролл обязан быть видимым).
const SCROLL_MIN_HEIGHT: float = 120.0
# Сколько места «съедают» заголовок, два сепаратора и кнопка закрытия
# вместе с вертикальными отступами панели. Используется, чтобы посчитать
# доступную высоту под скролл.
const PANEL_OVERHEAD: float = 210.0

# --- Ручная обработка тач-скролла ---
#
# Порог DRAG_THRESHOLD_PX нужен, чтобы короткий тап по чекбоксу не
# отменялся, а осознанный скролл-жест - срабатывал.
const DRAG_THRESHOLD_PX: float = 12.0

var _scroll: ScrollContainer = null
# -2 = нет активного жеста, -1 = мышь, >= 0 = индекс тач-пальца.
var _drag_index: int = -2
var _drag_start_y: float = 0.0
var _drag_last_y: float = 0.0
var _drag_started_in_scroll: bool = false
var _drag_activated: bool = false


func _ready() -> void:
	layer = 200

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	panel.add_theme_stylebox_override("panel", UIStyle.make_panel_style(20, true))
	center.add_child(panel)

	# Отступы уменьшены с 44/44/44/40 до 32/32/28/24 — панель стала ниже
	# и компактнее, но стилистика та же.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = tr("НАСТРОЙКИ")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.apply_label_style(title, UIStyle.FONT_SIZE_TITLE_SMALL, UIStyle.COLOR_TEXT)
	vbox.add_child(title)

	vbox.add_child(_separator())

	# --- Скролл для основной части настроек ---
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = scroll

	var viewport_h: float = get_viewport().get_visible_rect().size.y
	var available: float = viewport_h - PANEL_OVERHEAD
	var scroll_h: float = clampf(available, SCROLL_MIN_HEIGHT, SCROLL_MAX_HEIGHT)
	scroll.custom_minimum_size = Vector2(0, scroll_h)
	vbox.add_child(scroll)

	# Содержимое скролла. size_flags_horizontal = EXPAND_FILL обязателен,
	# иначе внутри ScrollContainer дочерние ряды «схлопнутся» по ширине.
	var content := VBoxContainer.new()
	content.name = "SettingsContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	# ==================== ГРАФИКА ====================

	var preset_row := _make_row(content, tr("Пресет"))
	var preset_opt := OptionButton.new()
	preset_opt.name = "PresetOption"
	preset_opt.custom_minimum_size = Vector2(0, 36)
	UIStyle.apply_primary_button(preset_opt, 6)
	for p in [GraphicsSettings.Preset.VERY_LOW, GraphicsSettings.Preset.LOW,
			GraphicsSettings.Preset.MEDIUM, GraphicsSettings.Preset.HIGH]:
		preset_opt.add_item(tr(GraphicsSettings.PRESET_NAMES[p]), int(p))
	preset_opt.item_selected.connect(func(i):
		GraphicsSettings.set_preset(preset_opt.get_item_id(i))
	)
	preset_row.add_child(preset_opt)

	var fps_row := _make_row(content, tr("Ограничение FPS"))
	var fps_opt := OptionButton.new()
	fps_opt.name = "FpsOption"
	fps_opt.custom_minimum_size = Vector2(0, 36)
	UIStyle.apply_primary_button(fps_opt, 6)
	fps_opt.add_item(tr("Без ограничения"), 0)
	fps_opt.add_item("30 FPS", 30)
	fps_opt.add_item("45 FPS", 45)
	fps_opt.add_item("60 FPS", 60)
	fps_opt.add_item("120 FPS", 120)
	fps_opt.item_selected.connect(func(i):
		GraphicsSettings.set_value("max_fps", fps_opt.get_item_id(i))
	)
	fps_row.add_child(fps_opt)

	_make_check(content, "vsync",     tr("Вертикальная синхронизация"))
	_make_check(content, "particles", tr("Эффекты частиц"))
	_make_check(content, "damage",    tr("Всплывающие числа урона"))
	_make_check(content, "shake",     tr("Тряска камней при ударе"))
	_make_check(content, "lighting",  tr("Динамическое освещение"))
	_make_check(content, "glow",      tr("Свечение"))

	content.add_child(_separator())

	# ==================== ЗВУК ====================

	var audio_title := Label.new()
	audio_title.text = tr("ЗВУК")
	audio_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.apply_label_style(audio_title, UIStyle.FONT_SIZE_BODY, UIStyle.COLOR_TEXT_MUTED)
	content.add_child(audio_title)

	_make_slider_row(content, "music_volume", tr("Музыка"))
	_make_slider_row(content, "sfx_volume",   tr("Звуки"))

	# ==================== ЗАКРЫТЬ (всегда видна) ====================

	vbox.add_child(_separator())

	var close_btn := Button.new()
	close_btn.text = tr("ЗАКРЫТЬ")
	close_btn.custom_minimum_size = Vector2(0, 48)
	UIStyle.apply_primary_button(close_btn, 10)
	close_btn.pressed.connect(_on_close_pressed)
	vbox.add_child(close_btn)

	GraphicsSettings.settings_changed.connect(_refresh_ui)
	GraphicsSettings.audio_changed.connect(_refresh_audio_ui)
	_refresh_ui()


func _separator() -> HSeparator:
	var s := HSeparator.new()
	UIStyle.apply_separator(s)
	return s


func _make_row(parent: Node, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyle.apply_label_style(l, UIStyle.FONT_SIZE_BODY, UIStyle.COLOR_TEXT)
	row.add_child(l)
	return row


func _make_check(parent: Node, key: String, label_text: String) -> void:
	var c := CheckBox.new()
	c.name = "Check_" + key
	c.text = label_text
	UIStyle.apply_label_style(c, UIStyle.FONT_SIZE_BODY, UIStyle.COLOR_TEXT)
	c.toggled.connect(func(v):
		GraphicsSettings.set_value(_checkbox_key_to_setting(key), v)
	)
	parent.add_child(c)


func _make_slider_row(parent: Node, key: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(120, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyle.apply_label_style(l, UIStyle.FONT_SIZE_BODY, UIStyle.COLOR_TEXT)
	row.add_child(l)

	var slider := HSlider.new()
	slider.name = "Slider_" + key
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 28)
	slider.value_changed.connect(func(v: float):
		if key == "music_volume":
			GraphicsSettings.set_music_volume(v)
		else:
			GraphicsSettings.set_sfx_volume(v)
		_update_slider_label(key, v)
	)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.name = "ValueLabel_" + key
	value_label.custom_minimum_size = Vector2(52, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyle.apply_label_style(value_label, UIStyle.FONT_SIZE_SMALL, UIStyle.COLOR_TEXT_MUTED)
	row.add_child(value_label)


func _update_slider_label(key: String, value: float) -> void:
	var l := _find("ValueLabel_" + key) as Label
	if l:
		l.text = "%d%%" % roundi(value * 100.0)


func _sync_slider(key: String, value: float) -> void:
	var s := _find("Slider_" + key) as HSlider
	if s:
		s.set_value_no_signal(value)
	_update_slider_label(key, value)


func _checkbox_key_to_setting(key: String) -> String:
	match key:
		"vsync":     return "vsync"
		"particles": return "particles_enabled"
		"damage":    return "damage_numbers"
		"shake":     return "shake_enabled"
		"lighting":  return "lighting_enabled"
		"glow":      return "glow_enabled"
	return key


func _refresh_ui() -> void:
	var preset_opt := _find("PresetOption") as OptionButton
	if preset_opt:
		var want := int(GraphicsSettings.current_preset)
		for i in preset_opt.item_count:
			if preset_opt.get_item_id(i) == want:
				preset_opt.select(i)
				break

	var fps_opt := _find("FpsOption") as OptionButton
	if fps_opt:
		var want_fps := int(GraphicsSettings.get_value("max_fps", 0))
		for i in fps_opt.item_count:
			if fps_opt.get_item_id(i) == want_fps:
				fps_opt.select(i)
				break

	_sync_check("vsync",     bool(GraphicsSettings.get_value("vsync", true)))
	_sync_check("particles", bool(GraphicsSettings.get_value("particles_enabled", true)))
	_sync_check("damage",    bool(GraphicsSettings.get_value("damage_numbers", true)))
	_sync_check("shake",     bool(GraphicsSettings.get_value("shake_enabled", true)))
	_sync_check("lighting",  bool(GraphicsSettings.get_value("lighting_enabled", true)))
	_sync_check("glow",      bool(GraphicsSettings.get_value("glow_enabled", true)))

	_refresh_audio_ui()


func _refresh_audio_ui() -> void:
	_sync_slider("music_volume", GraphicsSettings.music_volume)
	_sync_slider("sfx_volume",   GraphicsSettings.sfx_volume)


func _sync_check(key: String, value: bool) -> void:
	var c := _find("Check_" + key) as CheckBox
	if c:
		c.set_pressed_no_signal(value)


func _find(node_name: String) -> Node:
	return find_child(node_name, true, false)


func _on_close_pressed() -> void:
	queue_free()


# ==================== ТАЧ-СКРОЛЛ ====================
#
# Перехватываем press/drag/release на уровне CanvasLayer. Если жест начался
# внутри области ScrollContainer и сместился по вертикали больше, чем на
# DRAG_THRESHOLD_PX, считаем его скроллом:
#   - сами двигаем scroll_vertical;
#   - поглощаем событие через set_input_as_handled(), чтобы CheckBox под
#     пальцем не воспринял drag как нажатие.
#
# Работает и с тачем (InputEventScreenTouch/Drag), и с мышью — на случай
# отладки на десктопе и на случай emulate_mouse_from_touch=true на Web.

func _input(event: InputEvent) -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	if not visible:
		return

	var pos: Vector2
	var idx: int = -2
	var is_press: bool = false
	var is_release: bool = false
	var is_drag: bool = false

	if event is InputEventScreenTouch:
		pos = event.position
		idx = event.index
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventScreenDrag:
		pos = event.position
		idx = event.index
		is_drag = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		idx = -1
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pos = event.position
		idx = -1
		is_drag = true
	else:
		return

	if is_press and _drag_index == -2:
		_drag_index = idx
		_drag_start_y = pos.y
		_drag_last_y = pos.y
		_drag_started_in_scroll = _scroll.get_global_rect().has_point(pos)
		_drag_activated = false

	elif is_release and idx == _drag_index:
		var was_activated: bool = _drag_activated
		_drag_index = -2
		_drag_started_in_scroll = false
		_drag_activated = false
		# Если игрок скроллил — «съедаем» release, чтобы CheckBox под
		# пальцем не засчитался как нажатый после drag-жеста.
		if was_activated:
			get_viewport().set_input_as_handled()

	elif is_drag and idx == _drag_index and _drag_started_in_scroll:
		if not _drag_activated:
			if abs(pos.y - _drag_start_y) >= DRAG_THRESHOLD_PX:
				_drag_activated = true
		if _drag_activated:
			var dy: float = pos.y - _drag_last_y
			_scroll.scroll_vertical -= int(dy)
			_drag_last_y = pos.y
			get_viewport().set_input_as_handled()
