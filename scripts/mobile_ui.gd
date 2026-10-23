extends CanvasLayer
## Слой мобильного управления. Создаётся из hud.gd::_create_mobile_controls_deferred()
## программно — не требует правок .tscn.
##
## Содержит виртуальный джойстик в нижнем левом углу. Кнопка перезапуска
## уровня убрана: возврат в меню доступен через "В МЕНЮ" (правый верхний
## угол), а рестарт — отладочная функция, которая на мобиле чаще мешает.

const VirtualJoystickScript := preload("res://scripts/virtual_joystick.gd")

func _ready() -> void:
	# layer 50: выше игрового мира и обычного HUD уровня, но ниже
	# кнопки "В МЕНЮ" (layer 100), чтобы та оставалась кликабельной.
	layer = 50

	var joystick := Control.new()
	joystick.name = "Joystick"
	joystick.set_script(VirtualJoystickScript)
	add_child(joystick)
