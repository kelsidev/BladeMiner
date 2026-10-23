extends Node
## Автозагрузка "AudioManager". Централизованно управляет всем звуком:
##   - фоновая музыка (единый AudioStreamPlayer, продолжает играть между сценами);
##   - SFX клика по любой интерактивной кнопке (BaseButton);
##   - SFX удара по камню (вызывается из rock.gd::take_damage()).
##
## Клик по кнопкам подключается автоматически через SceneTree.node_added —
## не нужно вручную трогать .tscn или дублировать код в каждом скрипте UI.
##
## Громкость музыки и SFX регулируется GraphicsSettings (секция [audio]
## в user://graphics.cfg). Пауза/мьют платформы по-прежнему работает через
## AudioServer.set_bus_mute(0, ...) в menu.gd — этот же Master bus
## используют все наши плееры.
##
## Автостоп для длинных SFX: у каждого плеера из пула есть персональный
## Timer. Если звук передан с max_duration > 0 — по истечении этого времени
## плеер будет остановлен принудительно. Так stone_hit.wav гарантированно
## звучит не дольше STONE_HIT_MAX_DURATION секунд.
##
## Web/HTML5:
##   - Браузеры блокируют autoplay до первого пользовательского действия.
##     Мы НЕ обходим это ограничение: игра просто ждёт первого реального
##     ввода (клик/тач/клавиша/джойстик) и уже тогда, при необходимости,
##     перезапускает музыку. Никаких скрытых кликов и эмуляции ввода.
##   - Фоновый OST зациклен на уровне самого аудиоресурса (loop = true),
##     поэтому завершения трека не происходит и повторных play() нет.
##     Дополнительно подключён finished как фолбэк для форматов без loop.
##
## Приглушение Master bus (mute_master/unmute_master):
##   - Используется reason-based схема: звук замьючен, пока активна хотя бы
##     одна причина. Это позволяет независимо комбинировать mute при показе
##     рекламы, при потере фокуса окна и при паузе платформы, не перезаписывая
##     состояние друг друга.
##   - НЕ трогает пользовательские настройки громкости (music_volume/sfx_volume):
##     они применяются через volume_db на плеерах, отдельно от bus mute.
##   - Если пользователь выставил громкость в 0 (SILENT_DB), после снятия
##     mute-причины плеер остаётся «тихим» — принудительного включения звука
##     не происходит.

const MUSIC_PATH := "res://audio/OST-Blade-Miner.ogg"
const BUTTON_CLICK_PATH := "res://audio/button_click.wav"
const STONE_HIT_PATH := "res://audio/stone_hit.wav"

# Пул SFX-плееров, чтобы можно было накладывать звуки (например, при быстром
# комбо ударов по камню) без обрыва предыдущего воспроизведения.
const SFX_POOL_SIZE := 6

const MUSIC_VOLUME_DB := -8.0
const BUTTON_CLICK_VOLUME_DB := -10.0
const STONE_HIT_VOLUME_DB := -6.0

# Максимальная длительность звука удара по камню. Даже если .wav-файл
# длиннее — воспроизведение принудительно остановится через это время.
const STONE_HIT_MAX_DURATION := 0.5

# Порог, после которого считаем, что музыка реально играет (а не просто
# "playing == true, но браузер не пускает звук"). Если после первого
# пользовательского действия позиция трека уже больше этого значения —
# autoplay был разрешён, и перезапускать трек не нужно.
const MUSIC_ALREADY_PLAYING_THRESHOLD_SEC := 0.5

# Тишина в dB, если ползунок громкости стоит на 0.
# linear_to_db(0) даёт -inf, что ломает расчёты; -80 dB ниже порога
# слышимости, но плеер продолжает «играть» позицию — при возврате громкости
# звук появляется мгновенно, без рестарта трека.
const SILENT_DB := -80.0

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_stop_timers: Array[Timer] = []
var _sfx_next: int = 0

var _button_click: AudioStream
var _stone_hit: AudioStream

# instance_id -> true, чтобы не подключать один и тот же Button дважды.
var _hooked_buttons: Dictionary = {}

# Одноразовая разблокировка autoplay на первое реальное пользовательское
# действие. После срабатывания отключаем _input, чтобы не тратить кадры.
var _autoplay_unlock_done: bool = false

# --- Причины, по которым Master bus временно замьючен ---
# Позволяет независимо управлять несколькими причинами паузы звука
# (реклама, потеря фокуса, пауза платформы), не перезаписывая состояние
# друг друга. Пока словарь не пуст — Master bus замьючен.
var _master_mute_reasons: Dictionary = {}

# Флаг, что окно/приложение потеряло фокус. Защищает от двойного срабатывания
# при одновременном приходе NOTIFICATION_APPLICATION_FOCUS_OUT и
# NOTIFICATION_WM_WINDOW_FOCUS_OUT (на некоторых платформах приходят оба).
var _focus_lost: bool = false


func _ready() -> void:
	# Работаем даже когда дерево на паузе (пауза платформы/реклама).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_button_click = load(BUTTON_CLICK_PATH)
	_stone_hit = load(STONE_HIT_PATH)

	_setup_music_player()
	_setup_sfx_pool()

	# Подписываемся на изменения громкости из GraphicsSettings.
	if GraphicsSettings:
		if not GraphicsSettings.audio_changed.is_connected(_on_audio_changed):
			GraphicsSettings.audio_changed.connect(_on_audio_changed)

	# --- Автоподключение звука клика ко всем BaseButton ---
	# node_added срабатывает и для уже существующих узлов главной сцены
	# (она добавляется после автолоадов), и для создаваемых в рантайме
	# (кнопка "В МЕНЮ" в hud.gd, панель настроек графики, карточки апгрейдов).
	get_tree().node_added.connect(_on_node_added)
	# На всякий случай сканируем дерево — вдруг что-то уже было добавлено.
	call_deferred("_hook_existing_buttons")


# ==================== Публичное API ====================

func play_button_click() -> void:
	# Клик не ограничиваем по времени: max_duration = 0.
	_play_sfx(_button_click, BUTTON_CLICK_VOLUME_DB, 0.0)


func play_stone_hit() -> void:
	# Удар по камню режем до STONE_HIT_MAX_DURATION секунд.
	_play_sfx(_stone_hit, STONE_HIT_VOLUME_DB, STONE_HIT_MAX_DURATION)


# ==================== Пауза звука (mute Master bus) ====================

## Замьютить Master bus по указанной причине.
## Причины комбинируются: пока активна хотя бы одна — Master bus замьючен.
## НЕ меняет пользовательские настройки громкости (music_volume / sfx_volume),
## они применяются через volume_db отдельных плееров.
func mute_master(reason: String) -> void:
	if _master_mute_reasons.has(reason):
		return
	_master_mute_reasons[reason] = true
	_apply_master_mute()


## Снять mute Master bus для указанной причины. Если остались другие
## активные причины — звук останется замьюченным. Если пользователь сам
## выставил громкость в 0 (SILENT_DB), тишина сохранится — принудительного
## включения звука не произойдёт.
func unmute_master(reason: String) -> void:
	if not _master_mute_reasons.has(reason):
		return
	_master_mute_reasons.erase(reason)
	_apply_master_mute()


func _apply_master_mute() -> void:
	# Master bus mute применяется при наличии хотя бы одной активной причины.
	AudioServer.set_bus_mute(0, not _master_mute_reasons.is_empty())


# ==================== Потеря фокуса окна/вкладки ====================

## На Web и десктопе Godot рассылает разные уведомления при потере фокуса.
## Обрабатываем оба, а флаг _focus_lost защищает от повторного срабатывания.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_on_focus_out()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_on_focus_in()


func _on_focus_out() -> void:
	if _focus_lost:
		return
	_focus_lost = true
	# Идемпотентно: если реклама уже замьютила Master bus,
	# дополнительный mute("focus_lost") не изменит состояние,
	# но причина останется зафиксирована и будет снята при возврате фокуса.
	mute_master("focus_lost")


func _on_focus_in() -> void:
	if not _focus_lost:
		return
	_focus_lost = false
	# Если параллельно активна причина "ad" (реклама), Master bus
	# останется замьюченным — рекламная тишина не будет прервана.
	unmute_master("focus_lost")


# ==================== Настройка музыки ====================

func _setup_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Master"
	_music_player.volume_db = _effective_music_db()

	var music_stream: AudioStream = load(MUSIC_PATH)
	if music_stream != null:
		_enable_stream_loop(music_stream)
	_music_player.stream = music_stream

	# Фолбэк на случай, если loop по какой-то причине не сработает:
	# при включённом loop сигнал finished не приходит, поэтому дублирования
	# не будет. Если формат не поддерживает loop — плеер перезапустит трек.
	_music_player.finished.connect(_on_music_finished)

	add_child(_music_player)

	_start_music()


## Включает зацикливание на уровне самого аудиоресурса — самый надёжный
## способ для Godot 4: движок сам бесшовно повторяет трек, без пауз и
## без повторных вызовов play().
func _enable_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


func _setup_sfx_pool() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SfxPlayer%d" % i
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)

		var t := Timer.new()
		t.name = "SfxStopTimer%d" % i
		t.one_shot = true
		p.add_child(t)
		# По таймауту останавливаем именно этот плеер.
		t.timeout.connect(p.stop)
		_sfx_stop_timers.append(t)


# ==================== Громкость ====================

func _on_audio_changed() -> void:
	if _music_player != null and is_instance_valid(_music_player):
		_music_player.volume_db = _effective_music_db()


func _effective_music_db() -> float:
	var v: float = GraphicsSettings.music_volume if GraphicsSettings else 1.0
	return MUSIC_VOLUME_DB + _safe_linear_to_db(v)


## linear_to_db(0) возвращает -inf, что ломает арифметику и логику mute.
## Возвращаем SILENT_DB (-80 dB) — ниже порога слышимости, но плеер
## продолжает «играть» позицию.
func _safe_linear_to_db(v: float) -> float:
	if v <= 0.0:
		return SILENT_DB
	return linear_to_db(v)


# ==================== Разблокировка autoplay (Web) ====================

## Ловим ЛЮБОЕ реальное пользовательское действие ровно один раз.
## Слушаем событие, но ничего не эмулируем и не подсовываем.
func _input(event: InputEvent) -> void:
	if _autoplay_unlock_done:
		return
	if _is_real_user_gesture(event):
		_try_unlock_autoplay()


func _is_real_user_gesture(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


func _try_unlock_autoplay() -> void:
	_autoplay_unlock_done = true
	# Больше нас не интересует ввод — экономим вызовы.
	set_process_input(false)

	if _music_player == null or not is_instance_valid(_music_player):
		return
	if _music_player.stream == null:
		return

	# Если браузер уже разрешал autoplay — плеер реально играет и позиция
	# трека успела уйти вперёд. Тогда ничего не трогаем, чтобы не рестартить
	# уже слышимую музыку.
	if _music_player.playing \
			and _music_player.get_playback_position() > MUSIC_ALREADY_PLAYING_THRESHOLD_SEC:
		return

	# Иначе: либо плеер не playing, либо он "playing", но браузер молчал
	# (WebAudio был suspended). После текущего пользовательского действия
	# контекст уже разблокирован, поэтому play() с этого момента даст звук.
	_music_player.play()


func _on_music_finished() -> void:
	# Достигается только если loop не сработал (например, формат без loop).
	# Тогда перезапускаем вручную. При включённом loop finished не приходит,
	# поэтому дублирования воспроизведения нет.
	if _music_player != null \
			and is_instance_valid(_music_player) \
			and _music_player.stream != null:
		_music_player.play()


# ==================== Внутреннее ====================

func _start_music() -> void:
	if _music_player == null or _music_player.stream == null:
		return
	# Защита от случайного повторного запуска.
	if _music_player.playing:
		return
	_music_player.play()


func _play_sfx(stream: AudioStream, volume_db: float, max_duration: float) -> void:
	if stream == null:
		return
	if _sfx_players.is_empty():
		return

	# Round-robin по пулу: следующий звук берёт следующий плеер.
	# Старый звук на предыдущем плеере не обрывается.
	var idx: int = _sfx_next
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()

	var p: AudioStreamPlayer = _sfx_players[idx]
	var t: Timer = _sfx_stop_timers[idx]

	# КРИТИЧНО: сначала гасим возможный прошлый автостоп на этом плеере.
	# Иначе таймер, запущенный предыдущим stone_hit, мог бы «выстрелить»
	# уже во время нового звука и оборвать его раньше времени.
	t.stop()

	# SFX-громкость читается в момент воспроизведения (а не через сигнал):
	# иначе пришлось бы обходить весь пул и переприменять громкость.
	var sfx_mult: float = GraphicsSettings.sfx_volume if GraphicsSettings else 1.0
	p.stream = stream
	p.volume_db = volume_db + _safe_linear_to_db(sfx_mult)
	p.play()

	# Ставим автостоп только если он нужен (для music/click max_duration = 0).
	if max_duration > 0.0:
		t.start(max_duration)


# ==================== Хук на кнопки ====================

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node as BaseButton)


func _hook_existing_buttons() -> void:
	var root := get_tree().root
	if root and root.get_child_count() > 0:
		var current_scene := root.get_child(root.get_child_count() - 1)
		if current_scene:
			_hook_children_recursive(current_scene, 2)


func _hook_children_recursive(node: Node, depth: int) -> void:
	if depth <= 0:
		return
	for child in node.get_children():
		if child is BaseButton:
			_hook_button(child as BaseButton)
		_hook_children_recursive(child, depth - 1)


func _hook_button(button: BaseButton) -> void:
	var id: int = button.get_instance_id()
	if _hooked_buttons.has(id):
		return
	_hooked_buttons[id] = true

	if not button.pressed.is_connected(_on_any_button_pressed):
		button.pressed.connect(_on_any_button_pressed)

	# Чистим кэш при удалении, чтобы instance_id не «залипал» и
	# кнопку можно было корректно переподключить при повторном добавлении.
	if not button.tree_exiting.is_connected(_on_button_exiting):
		button.tree_exiting.connect(_on_button_exiting.bind(id), CONNECT_ONE_SHOT)


func _on_button_exiting(id: int) -> void:
	_hooked_buttons.erase(id)


func _on_any_button_pressed() -> void:
	play_button_click()
