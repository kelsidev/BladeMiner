extends Node
## Автозагрузка (autoload) "MobileInput".
##
## Хранит флаг "игра запущена на сенсорном устройстве" и текущий вектор
## движения виртуального джойстика. К нему обращаются player.gd (читает
## вектор) и virtual_joystick.gd (пишет вектор).

## Вектор движения, выставленный виртуальным джойстиком.
## Длина 0.0..1.0: 0 = стик не тронут, 1 = выдвинут до края.
var move_vector: Vector2 = Vector2.ZERO

## true, если запущено на Android/iOS (или явно форсировано для отладки).
var is_mobile: bool = false


func _ready() -> void:
	# Отладочный флаг: чтобы потрогать мобильный UI прямо в редакторе,
	# можно запустить игру с ключом --mobile.
	var forced: bool = ("--mobile" in OS.get_cmdline_args()) \
		or ("--mobile" in OS.get_cmdline_user_args())

	# 1) Нативная мобильная сборка (Android/iOS).
	var native_mobile: bool = OS.has_feature("mobile")

	# 2) Web-сборка (например, Yandex Games) на тачскрин-устройстве.
	var web_touch: bool = OS.get_name() == "Web" and DisplayServer.is_touchscreen_available()

	is_mobile = forced or native_mobile or web_touch

	print("[MobileInput] is_mobile = ", is_mobile,
		" (forced=", forced,
		", native=", native_mobile,
		", web_touch=", web_touch, ")")


func reset() -> void:
	move_vector = Vector2.ZERO
