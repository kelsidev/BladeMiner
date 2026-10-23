extends Node
## Автозагрузка AdManager. Показывает полноэкранную рекламу Яндекс Игр
## в логических паузах (завершение уровня, проигрыш, выход в меню).
##
## Требования Яндекс Игр для коротких уровней (менее 5 минут):
##   - Реклама показывается только в логических паузах.
##   - Реклама никогда не появляется во время активного геймплея.
##   - Предупреждение с отсчётом не требуется, так как игрок сам инициирует
##     показ нажатием неигровой кнопки.
##   - Во время рекламы игра стоит на паузе, ввод заблокирован.
##
## ВАЖНО: request_ad_after_action() принимает on_complete. Этот колбэк
## вызывается РОВНО ОДИН РАЗ за один показ рекламы — и после успешного
## закрытия, и при ошибке (SDK недоступен, кулдаун, уже идёт другая
## реклама, ошибка показа). Это гарантирует, что игровой код, который
## ждёт окончания рекламы для перехода в меню или рестарта, не подвиснет
## и не отработает дважды.
##
## Приглушение звука на время рекламы: используется reason-based API
## AudioManager.mute_master("ad") / unmute_master("ad"). Это корректно
## комбинируется с mute по потере фокуса и не трогает пользовательские
## настройки громкости. Если пользователь до рекламы выключил звук
## (music_volume = 0), после рекламы звук не включится принудительно.

const COOLDOWN_SECONDS: float = 60.0

var _cooldown_timer: Timer
var _is_ad_in_progress: bool = false
var _main: Node = null

# Состояние до паузы.
var _prev_paused: bool = false
var _prev_game_active: bool = true

# Guard-флаг от двойного вызова on_complete при ошибке рекламы.
# YandexSDK.show_fullscreen_ad() при ошибке вызывает и on_error,
# и on_close(false). Оба колбэка ведут в _on_ad_finished(on_complete),
# поэтому без этого флага on_complete вызвался бы дважды.
var _ad_finish_guard: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = get_node_or_null("/root/Main")

	_cooldown_timer = Timer.new()
	_cooldown_timer.one_shot = true
	_cooldown_timer.wait_time = COOLDOWN_SECONDS
	add_child(_cooldown_timer)


# ==================== ПУБЛИЧНОЕ API ====================

## Запросить показ полноэкранной рекламы в логической паузе.
## on_complete вызывается ВСЕГДА (даже если реклама не показана),
## ровно один раз, чтобы вызывающий код мог безопасно продолжить
## (рестарт / смена сцены) без риска двойного срабатывания.
func request_ad_after_action(on_complete: Callable = Callable()) -> void:
	if _is_ad_in_progress:
		_call_callback(on_complete)
		return
	if not _cooldown_timer.is_stopped():
		_call_callback(on_complete)
		return
	if not YandexSDK or not YandexSDK.is_available:
		_call_callback(on_complete)
		return
	if YandexSDK.is_ad_in_progress():
		_call_callback(on_complete)
		return

	_start_ad_sequence(on_complete)


# ==================== ВНУТРЕННЕЕ ====================

func _call_callback(cb: Callable) -> void:
	if cb.is_valid():
		cb.call()


func _start_ad_sequence(on_complete: Callable) -> void:
	_is_ad_in_progress = true
	_ad_finish_guard = false

	_prev_paused = get_tree().paused
	if _main:
		_prev_game_active = _main.game_active

	# Пауза и блокировка игрового процесса.
	get_tree().paused = true
	if _main:
		_main.game_active = false

	# Приглушаем Master bus по причине "ad". Если параллельно активна
	# причина "focus_lost" (игрок потерял фокус в момент показа рекламы),
	# звук останется замьюченным, потому что причины комбинируются.
	if AudioManager:
		AudioManager.mute_master("ad")

	YandexSDK.show_fullscreen_ad(
		func(_was_shown: bool):
			_on_ad_finished(on_complete),
		func(_error_msg: String):
			_on_ad_finished(on_complete)
	)


func _on_ad_finished(on_complete: Callable) -> void:
	# Guard: при ошибке показа YandexSDK вызывает и on_error, и on_close(false).
	# Без этой защиты _on_ad_finished() и on_complete() сработали бы дважды.
	if _ad_finish_guard:
		return
	_ad_finish_guard = true

	_is_ad_in_progress = false

	# Снимаем mute по причине "ad". Если остались другие причины
	# (например, "focus_lost"), звук останется замьюченным — это корректно,
	# потому что в этот момент окно действительно без фокуса.
	# Пользовательская настройка громкости не затрагивается: если до рекламы
	# музыка/SFX были выставлены в 0, они останутся в 0.
	if AudioManager:
		AudioManager.unmute_master("ad")

	get_tree().paused = _prev_paused
	if _main:
		_main.game_active = _prev_game_active

	_cooldown_timer.start()

	# Передаём управление дальше — рестарт, смена сцены и т.п.
	# Вызывается ровно один раз за один показ рекламы.
	_call_callback(on_complete)
