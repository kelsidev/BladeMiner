extends Control
class_name VirtualJoystick
## Виртуальный джойстик. Создаётся программно (аналогично кнопке
## "В МЕНЮ" в hud.gd), чтобы не трогать .tscn-файлы в редакторе.
##
## Обрабатывает И touch-, И mouse-события. Причина: при стандартной
## настройке проекта input_devices/pointing/emulate_mouse_from_touch=true
## Godot превращает тач по Control в InputEventMouseButton/MouseMotion,
## и raw-события InputEventScreenTouch/Drag в _gui_input до нас НЕ
## доходят. Если пользователь отключит эмуляцию - до нас дойдут именно
## тач-события. Обе ветки ниже покрывают оба случая, поэтому джойстик
## работает при любой настройке проекта.
##
## Мультитач: трекаем один конкретный палец по event.index. Остальные
## пальцы уходят в свои Control (кнопки/меню) - конфликтов нет, потому
## что у каждого Control свой _gui_input и Godot адресует событие в тот
## Control, над которым оно возникло.

@export var base_radius: float = 110.0
@export var knob_radius: float = 48.0
@export var dead_zone: float = 0.12

var _base_panel: Panel
var _knob_panel: Panel
var _touch_index: int = -1
var _center: Vector2

func _ready() -> void:
	# Нижний левый угол, отступ 20 единиц базового разрешения.
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	var side: float = base_radius * 2.0 + 40.0
	offset_left = 20.0
	offset_right = 20.0 + side
	offset_top = -(20.0 + side)
	offset_bottom = -20.0
	# STOP: касания внутри зоны джойстика не «протекают» в игровой мир
	# и не превращаются в эмулированные клики по нижележащим Control.
	mouse_filter = Control.MOUSE_FILTER_STOP

	_center = Vector2(side * 0.5, side * 0.5)

	_base_panel = Panel.new()
	_base_panel.size = Vector2(base_radius * 2.0, base_radius * 2.0)
	_base_panel.position = _center - Vector2(base_radius, base_radius)
	_base_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base_style := StyleBoxFlat.new()
	base_style.bg_color = Color(1.0, 1.0, 1.0, 0.13)
	base_style.border_color = Color(1.0, 1.0, 1.0, 0.25)
	base_style.set_border_width_all(3)
	base_style.set_corner_radius_all(int(base_radius))
	_base_panel.add_theme_stylebox_override("panel", base_style)
	add_child(_base_panel)

	_knob_panel = Panel.new()
	_knob_panel.size = Vector2(knob_radius * 2.0, knob_radius * 2.0)
	_knob_panel.position = _center - Vector2(knob_radius, knob_radius)
	_knob_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = Color(1.0, 1.0, 1.0, 0.38)
	knob_style.set_corner_radius_all(int(knob_radius))
	_knob_panel.add_theme_stylebox_override("panel", knob_style)
	add_child(_knob_panel)


func _gui_input(event: InputEvent) -> void:
	# Приводим все поддерживаемые события к четырём булевым/векторным
	# флагам - так логика ниже не размножается на 4 ветки.
	var local_pos: Vector2 = Vector2.ZERO
	var is_press: bool = false
	var is_release: bool = false
	var is_drag: bool = false
	var idx: int = 0

	if event is InputEventScreenTouch:
		# Тач-событие приходит в _gui_input уже в локальных координатах
		# Control (Godot 4 сам переводит позицию).
		local_pos = event.position
		is_press = event.pressed
		is_release = not event.pressed
		idx = event.index
	elif event is InputEventScreenDrag:
		local_pos = event.position
		is_drag = true
		idx = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Путь, работающий при emulate_mouse_from_touch = true (по
		# умолчанию): тач превращается в клик левой кнопкой мыши.
		local_pos = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventMouseMotion:
		# Тот же путь, но для перемещения пальца. В _gui_input
		# mouse-события уже в локальных координатах.
		local_pos = event.position
		is_drag = true
	else:
		return

	# Тач-события несут event.index. Если это НЕ тот палец, которым мы уже
	# управляем, игнорируем. Это защищает от ситуации, когда второй палец
	# случайно попадает в зону джойстика и пытается перехватить контроль.
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) \
			and _touch_index != -1 and idx != _touch_index:
		return

	if is_press and _touch_index == -1:
		_touch_index = idx
		_update_from(local_pos)
		accept_event()
	elif is_release and _touch_index != -1:
		_release()
		accept_event()
	elif is_drag and _touch_index != -1:
		# Держим палец, даже если он вышел за пределы Control - Godot
		# сохраняет захват до release, поэтому drag-события продолжают
		# приходить, и мы корректно дотягиваем вектор до края.
		_update_from(local_pos)
		accept_event()


func _update_from(local_pos: Vector2) -> void:
	var offset: Vector2 = local_pos - _center
	var max_len: float = base_radius
	if offset.length() > max_len:
		offset = offset.normalized() * max_len
	_knob_panel.position = _center + offset - Vector2(knob_radius, knob_radius)

	var norm: Vector2 = offset / max_len
	var length: float = norm.length()
	if length < dead_zone:
		MobileInput.move_vector = Vector2.ZERO
	else:
		# Убираем мёртвую зону, чтобы движение «оживало» плавно от её
		# края, а не прыгало сразу на dead_zone.
		var adjusted: float = (length - dead_zone) / (1.0 - dead_zone)
		MobileInput.move_vector = norm.normalized() * clamp(adjusted, 0.0, 1.0)


func _release() -> void:
	_touch_index = -1
	_knob_panel.position = _center - Vector2(knob_radius, knob_radius)
	MobileInput.move_vector = Vector2.ZERO
