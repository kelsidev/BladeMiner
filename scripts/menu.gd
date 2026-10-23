extends Node2D

const LEVEL_SCENE_PATH := "res://levels/level1.tscn"
const GRAPHICS_SETTINGS_PANEL_SCRIPT := preload("res://scripts/graphics_settings_panel.gd")

@onready var play_button: Button = $UI/Center/MainPanel/ContentMargin/MainVBox/ButtonsVBox/PlayButton
@onready var endless_button: Button = $UI/Center/MainPanel/ContentMargin/MainVBox/ButtonsVBox/EndlessButton
@onready var lang_button: Button = $UI/Center/MainPanel/ContentMargin/MainVBox/ButtonsVBox/LangButton
@onready var settings_button: Button = $UI/Center/MainPanel/ContentMargin/MainVBox/ButtonsVBox/SettingsButton

@onready var ru_icon = preload("res://sprites/lang_icon_ru.png")
@onready var eng_icon = preload("res://sprites/lang_icon_en.png")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_update_play_button()
	_update_endless_button()
	_update_lang_button()
	_update_settings_button()
	$UI/VersionLabel.text = "v." + str(ProjectSettings.get_setting(
		"application/config/version", "dev"))

	if not Main.language_changed.is_connected(_on_language_changed):
		Main.language_changed.connect(_on_language_changed)

	# Ждём сигнал save_ready только если сейв ещё не загружен к моменту
	# открытия меню. Если SDK недоступен (или сейв успел прийти раньше —
	# например, при возврате из уровня через change_scene), кнопка уже
	# отрисована корректно в _update_play_button() выше.
	if not Main.save_loaded:
		if not Main.save_ready.is_connected(_on_save_ready):
			Main.save_ready.connect(_on_save_ready)

	if not lang_button.pressed.is_connected(_on_lang_button_pressed):
		lang_button.pressed.connect(_on_lang_button_pressed)
	if not settings_button.pressed.is_connected(_on_settings_button_pressed):
		settings_button.pressed.connect(_on_settings_button_pressed)

	if YandexSDK:
		YandexSDK.pause_state_changed.connect(_on_pause_state_changed)
		YandexSDK.pause_state_changed.connect(_on_pause_for_audio)
		# LoadingAPI.ready(): вызываем, когда меню полностью готово
		# и пользователь может начать играть (п. 1.19.2).
		# Если SDK уже инициализирован - сразу, иначе ждём сигнал.
		if YandexSDK.is_initialized:
			call_deferred("_send_game_ready_deferred")
		else:
			YandexSDK.sdk_initialized.connect(_on_sdk_initialized)


func _on_save_ready() -> void:
	# Облачный сейв получен (или точно отсутствует) — снимаем блокировку
	# с кнопок и перерисовываем их с учётом story_completed / current_level.
	if Main.save_ready.is_connected(_on_save_ready):
		Main.save_ready.disconnect(_on_save_ready)
	_update_play_button()
	_update_endless_button()


func _on_sdk_initialized() -> void:
	if YandexSDK:
		YandexSDK.sdk_initialized.disconnect(_on_sdk_initialized)
	call_deferred("_send_game_ready_deferred")


func _send_game_ready_deferred() -> void:
	if YandexSDK and YandexSDK.is_initialized:
		YandexSDK.send_game_ready()


func _on_settings_button_pressed() -> void:
	# Одновременно только одна панель.
	if has_node("GraphicsSettingsPanel"):
		return
	var layer := CanvasLayer.new()
	layer.name = "GraphicsSettingsPanel"
	layer.set_script(GRAPHICS_SETTINGS_PANEL_SCRIPT)
	add_child(layer)


func _on_pause_state_changed(is_paused: bool) -> void:
	get_tree().paused = is_paused


## Платформенная пауза (например, свёрнутая вкладка в Яндекс Играх).
## Используем reason-based API AudioManager, чтобы этот mute корректно
## комбинировался с mute по причине "ad" и "focus_lost" и не перезаписывал
## их состояние. Пользовательская настройка громкости не затрагивается.
func _on_pause_for_audio(is_paused: bool) -> void:
	if not AudioManager:
		return
	if is_paused:
		AudioManager.mute_master("platform_pause")
	else:
		AudioManager.unmute_master("platform_pause")


func _on_language_changed(_code: String) -> void:
	_update_play_button()
	_update_endless_button()
	_update_lang_button()
	_update_settings_button()


## Приоритеты состояний кнопки PLAY:
##   1) Сейв ещё не загружен — ждём, кнопка disabled ("ЗАГРУЗКА…").
##   2) Сюжет пройден — сюжетный PLAY больше не нужен (для бесконечной
##      игры есть ENDLESS). Кнопка disabled ("ПРОЙДЕНО").
##   3) Обычный сюжетный запуск: "ИГРАТЬ" или "ИГРАТЬ — УРОВЕНЬ N".
func _update_play_button() -> void:
	if not Main.save_loaded:
		play_button.disabled = true
		play_button.text = tr("ЗАГРУЗКА…")
		return

	if Main.story_completed:
		play_button.disabled = true
		play_button.text = tr("ПРОЙДЕНО")
		return

	play_button.disabled = false
	var lvl: int = max(1, int(Main.save_data.get("current_level", 1)))
	if lvl <= 1:
		play_button.text = tr("ИГРАТЬ")
	else:
		play_button.text = tr("ИГРАТЬ — УРОВЕНЬ %d") % lvl


func _update_endless_button() -> void:
	# Пока сейв не загружен, мы не знаем, пройден ли сюжет — держим
	# кнопку в заблокированном состоянии. Текст оставляем стандартным,
	# чтобы не показывать «пройдите сюжет» игроку, который его уже прошёл.
	if not Main.save_loaded:
		endless_button.disabled = true
		endless_button.text = tr("БЕСКОНЕЧНЫЙ РЕЖИМ (пройдите сюжет)")
		return

	if Main.story_completed:
		endless_button.disabled = false
		endless_button.text = tr("БЕСКОНЕЧНЫЙ РЕЖИМ")
	else:
		endless_button.disabled = true
		endless_button.text = tr("БЕСКОНЕЧНЫЙ РЕЖИМ (пройдите сюжет)")


func _update_lang_button() -> void:
	if Main.current_language == "en":
		lang_button.text = "LANGUAGE: ENGLISH"
		lang_button.tooltip_text = "Current language: English."
		lang_button.icon = eng_icon
	else:
		lang_button.text = "ЯЗЫК: РУССКИЙ"
		lang_button.tooltip_text = "Текущий язык: Русский."
		lang_button.icon = ru_icon


## Текст кнопки настроек задаём кодом (а не в .tscn): панель содержит
## не только графику, но и схему управления — поэтому просто "НАСТРОЙКИ".
## tr() даст "SETTINGS" при locale=en.
func _update_settings_button() -> void:
	settings_button.text = tr("НАСТРОЙКИ")


func _on_lang_button_pressed() -> void:
	var next: String = "en" if Main.current_language == "ru" else "ru"
	Main.set_language(next)


func _on_play_button_pressed() -> void:
	# Двойная защита: даже если по какой-то причине кнопка осталась
	# активной до прихода save_ready или после прохождения сюжета, не
	# запускаем игру с потенциально неверным состоянием.
	if not Main.save_loaded:
		return
	if Main.story_completed:
		return
	Main.reset_game()
	get_tree().change_scene_to_file(LEVEL_SCENE_PATH)


func _on_endless_button_pressed() -> void:
	if not Main.save_loaded:
		return
	if not Main.story_completed:
		return
	Main.reset_game()
	Main.infinite_mode = true
	get_tree().change_scene_to_file(LEVEL_SCENE_PATH)
