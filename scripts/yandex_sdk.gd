extends Node
## Автозагрузка YandexSDK (обёртка над плагином WebBus).
## Единый слой для взаимодействия с платформенными SDK.

signal sdk_initialized
signal save_loaded(data: Dictionary)
signal save_completed(success: bool)
signal language_detected(code: String)
signal pause_state_changed(is_paused: bool)

const SAVE_KEY := "blade_miner_save"

var is_initialized: bool = false
var is_available: bool = false
var _game_ready_sent: bool = false

var _webbus: Node = null

# Флаг, что реклама в данный момент показывается/ожидается.
# Нужен, чтобы AdManager не запустил второй показ.
var _ad_in_progress: bool = false


func _ready() -> void:
	_webbus = get_node_or_null("/root/WebBus")

	if _webbus == null:
		print("[YandexSDK] WebBus autoload not found. Running without SDK.")
		is_available = false
		call_deferred("_emit_initialized_fallback")
		return

	if OS.get_name() != "Web":
		print("[YandexSDK] Not a web build. SDK disabled.")
		is_available = false
		call_deferred("_emit_initialized_fallback")
		return

	call_deferred("_await_webbus_init")


func _await_webbus_init() -> void:
	if _webbus.get("is_init") == true:
		_on_webbus_ready()
		return

	if _webbus.has_signal("inited"):
		await _webbus.inited
		_on_webbus_ready()
	else:
		_on_webbus_ready()


func _emit_initialized_fallback() -> void:
	is_initialized = true
	sdk_initialized.emit()


func _on_webbus_ready() -> void:
	print("[YandexSDK] WebBus initialized.")
	is_available = true
	is_initialized = true

	# Платформенная пауза: WebBus сам следит за фокусом окна/вкладки
	# (window blur/focus + document.visibilitychange) и даёт публичные
	# сигналы focused/unfocused — см. документацию плагина
	# (https://talkafk.github.io/WebBus/usage/pause/). Пробрасываем их
	# в pause_state_changed, на который уже подписан menu.gd.
	if _webbus.has_signal("focused") and not _webbus.focused.is_connected(_on_webbus_focused):
		_webbus.focused.connect(_on_webbus_focused)
	if _webbus.has_signal("unfocused") and not _webbus.unfocused.is_connected(_on_webbus_unfocused):
		_webbus.unfocused.connect(_on_webbus_unfocused)

	sdk_initialized.emit()


func _on_webbus_focused() -> void:
	pause_state_changed.emit(false)


func _on_webbus_unfocused() -> void:
	pause_state_changed.emit(true)


# ==================== СОХРАНЕНИЯ ====================

func load_save() -> void:
	if not is_available or _webbus == null:
		save_loaded.emit({})
		return

	var result: Dictionary = await _webbus.get_data(SAVE_KEY)

	if result.has(SAVE_KEY) and result[SAVE_KEY] is Dictionary:
		save_loaded.emit(result[SAVE_KEY])
	else:
		print("[YandexSDK] No cloud save data found.")
		save_loaded.emit({})


func save_data(data: Dictionary) -> void:
	if not is_available or _webbus == null:
		save_completed.emit(false)
		return

	var wrapped: Dictionary = { SAVE_KEY: data }
	_webbus.set_data(wrapped)
	save_completed.emit(true)


# ==================== ЯЗЫК ====================

func get_platform_language() -> String:
	if not is_available or _webbus == null:
		return ""
	var lang: String = _webbus.get_language()
	match lang:
		"eng":
			return "en"
		"rus":
			return "ru"
		_:
			return lang


# ==================== GAME READY ====================

func _send_game_ready_now() -> void:
	if _game_ready_sent:
		return
	if not is_available or _webbus == null:
		return

	_webbus.call("ready")
	_game_ready_sent = true
	print("[YandexSDK] game_ready sent.")


func send_game_ready() -> void:
	_send_game_ready_now()


# ==================== РАЗМЕТКА ГЕЙМПЛЕЯ ====================
## Обёртка над WebBus.start_gameplay()/stop_gameplay() (GameplayAPI.start()/
## stop() на Yandex). Вызывать start_gameplay() при начале/возобновлении
## активной игровой сессии, stop_gameplay() — на любом логическом перерыве
## (меню, экран апгрейда, экран поражения). Требование п. 1.19.3.

func start_gameplay() -> void:
	if not is_available or _webbus == null:
		return
	if _webbus.has_method("start_gameplay"):
		_webbus.start_gameplay()


func stop_gameplay() -> void:
	if not is_available or _webbus == null:
		return
	if _webbus.has_method("stop_gameplay"):
		_webbus.stop_gameplay()


# ==================== РЕКЛАМА ====================

## Возвращает true, если реклама сейчас показывается или ожидается.
func is_ad_in_progress() -> bool:
	return _ad_in_progress


## Показывает полноэкранную рекламу.
## on_close(was_shown: bool) — вызывается при закрытии (was_shown = была ли показана).
## on_error(msg: String) — вызывается при ошибке.
func show_fullscreen_ad(on_close: Callable = Callable(), on_error: Callable = Callable()) -> void:
	if _ad_in_progress:
		# Уже идёт показ — не запускаем второй.
		if on_error.is_valid():
			on_error.call("ad_already_in_progress")
		return

	if not is_available or _webbus == null:
		if on_error.is_valid():
			on_error.call("SDK not available")
		if on_close.is_valid():
			on_close.call(false)
		return

	_ad_in_progress = true

	var _closed_called := false
	var _error_called := false

	var close_cb = func():
		if _closed_called:
			return
		_closed_called = true
		_ad_in_progress = false
		if on_close.is_valid():
			on_close.call(true)

	var error_cb = func(msg: String = "ad_error"):
		if _error_called:
			return
		_error_called = true
		_ad_in_progress = false
		if on_error.is_valid():
			on_error.call(msg)
		# После ошибки тоже нужно дать сигнал закрытия, чтобы игра
		# гарантированно сняла паузу.
		if on_close.is_valid():
			on_close.call(false)

	_webbus.ad_closed.connect(close_cb, CONNECT_ONE_SHOT)
	_webbus.ad_error.connect(error_cb, CONNECT_ONE_SHOT)
	_webbus.show_ad()


func show_rewarded_video(
		on_rewarded: Callable = Callable(),
		on_close: Callable = Callable(),
		on_error: Callable = Callable()
	) -> void:
	if not is_available or _webbus == null:
		if on_error.is_valid():
			on_error.call("SDK not available")
		return

	var rewarded_cb = func():
		if on_rewarded.is_valid():
			on_rewarded.call()
	var close_cb = func():
		if on_close.is_valid():
			on_close.call()
	var error_cb = func(msg: String = "ad_error"):
		if on_error.is_valid():
			on_error.call(msg)

	_webbus.reward_added.connect(rewarded_cb, CONNECT_ONE_SHOT)
	_webbus.ad_closed.connect(close_cb, CONNECT_ONE_SHOT)
	_webbus.ad_error.connect(error_cb, CONNECT_ONE_SHOT)
	_webbus.show_rewarded_ad()
