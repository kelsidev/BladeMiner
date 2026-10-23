extends CanvasLayer

signal reroll_signal

var on_continue = false

const MAX_REROLLS := 3
var rerolls_left := MAX_REROLLS

const MobileUIScript := preload("res://scripts/mobile_ui.gd")

var _mobile_controls_layer: CanvasLayer = null
var _menu_button: Button = null

var _defeat_root: Control = null
var _defeat_shown: bool = false
var _defeat_level_label: Label = null

const HUD_UPDATE_INTERVAL: float = 0.2
var _hud_update_accum: float = 0.0

@onready var card_hbox: HBoxContainer = $UpgradeScreen/MainPanel/ContentMargin/MainVBox/CardHBox
@onready var reroll_button: Button = $UpgradeScreen/MainPanel/ContentMargin/MainVBox/RerollCenter/ActionsHBox/RerollButton

# Cached HUD node references to avoid deep path lookups every frame
@onready var _money_label: Label = $HUD/HBoxContainer/VBoxContainer3/Money
@onready var _damage_label: Label = $HUD/HBoxContainer/VBoxContainer3/Damage
@onready var _rocks_label: Label = $HUD/HBoxContainer/VBoxContainer2/Rocks
@onready var _level_progress: ProgressBar = $HUD/HBoxContainer/VBoxContainer/LevelProgress
@onready var _level_label: Label = $HUD/HBoxContainer/VBoxContainer/LevelProgress_Label

# Cached LevelCompleteUI stat labels
@onready var _rocks_destroyed_label: Label = $LevelCompleteUI/MainPanel/VBoxContainer/MarginContainer/StatsPanel/StatsGrid/RocksDestroyed/ValueLabel
@onready var _money_get_label: Label = $LevelCompleteUI/MainPanel/VBoxContainer/MarginContainer/StatsPanel/StatsGrid/MoneyGet/ValueLabel

# Static-text nodes, whose content is hardcoded in hud.tscn and must be
# re-applied via tr() on ready and on each language change.
@onready var _level_complete_title: Label = $LevelCompleteUI/MainPanel/VBoxContainer/TitleLabel
@onready var _rocks_destroyed_text: Label = $LevelCompleteUI/MainPanel/VBoxContainer/MarginContainer/StatsPanel/StatsGrid/RocksDestroyed/TextLabel
@onready var _money_get_text: Label = $LevelCompleteUI/MainPanel/VBoxContainer/MarginContainer/StatsPanel/StatsGrid/MoneyGet/TextLabel
@onready var _continue_button: Button = $LevelCompleteUI/MainPanel/VBoxContainer/ContinueButton
@onready var _upgrade_title: Label = $UpgradeScreen/MainPanel/ContentMargin/MainVBox/TitleCenter/TitleHBox/TitleLabel
@onready var _skip_button: Button = $UpgradeScreen/MainPanel/ContentMargin/MainVBox/RerollCenter/ActionsHBox/SkipButton


func _ready() -> void:
	visible = true

	$LevelCompleteUI.hide()
	$UpgradeScreen.hide()

	#if MobileInput.is_mobile:
		#$DebugLabel.hide()
		#_debug_label.text = "max_health: "+str(Main.max_health)+"\nchance_crit: "+str(Main.chance_crit)+" -> "+str(Main.chance_crit*100)+"%"+"\ncrit_multiplier: "+str(Main.crit_multiplier)+" ->"+str((Main.crit_multiplier-1)*100)+"%"+"\narmor: "+str(snappedf(Main.armor*100, 0.01))+"%"+"\nlifesteal: "+str(Main.lifesteal*100)+"%"+"\ndodge_chance: "+str(Main.dodge_chance*100)+"%"+"\nregen_mult: x"+str(Main.regen_mult)+"\nmove_speed_mult: x"+str(Main.move_speed_mult)+"\nskills: "+str(Main.unlocked_skills.keys())+"\nviewport_size: "+str(get_viewport().size)

	for card in card_hbox.get_children():
		if card.has_signal("upgrade_click"):
			card.upgrade_click.connect(_on_upgradeclick.bind(card))

	_update_reroll_button()
	_refresh_static_texts()
	Main.level_changed.connect(_on_level_changed)
	Main.language_changed.connect(_on_language_changed)

	call_deferred("_create_menu_button_deferred")
	call_deferred("_create_mobile_controls_deferred")
	call_deferred("_create_defeat_ui_deferred")


## Обновляет статические надписи, захардкоженные в hud.tscn.
## Вызывается из _ready() и при каждой смене языка.
func _refresh_static_texts() -> void:
	_level_complete_title.text = tr("Уровень пройден!")
	_rocks_destroyed_text.text = tr("Камней уничтожено:")
	_money_get_text.text = tr("Монет получено:")
	_continue_button.text = tr("ПРОДОЛЖИТЬ")
	_upgrade_title.text = tr("ВЫБРАТЬ УЛУЧШЕНИЕ")
	_skip_button.text = tr("ПРОПУСТИТЬ")


func _on_level_changed(_level_num: int) -> void:
	on_continue = false
	rerolls_left = MAX_REROLLS
	_update_reroll_button()
	_defeat_shown = false
	if _defeat_root:
		_defeat_root.visible = false
	# Обновляем метку уровня на экране поражения сразу при смене уровня,
	# чтобы она никогда не показывала устаревшее значение.
	_update_defeat_level_label()
	$LevelCompleteUI.hide()
	$UpgradeScreen.hide()


func _on_language_changed(_code: String) -> void:
	_update_reroll_button()
	_refresh_static_texts()
	if _menu_button != null and is_instance_valid(_menu_button):
		_menu_button.text = tr("В МЕНЮ")
	_update_defeat_level_label()
	_refresh_hud()


## Обновляет метку "Уровень N" на экране поражения. Вызывается при смене
## уровня, смене языка и перед показом экрана поражения — так метка всегда
## отражает актуальный Main.current_level, даже если HUD живёт между уровнями.
func _update_defeat_level_label() -> void:
	if _defeat_level_label != null and is_instance_valid(_defeat_level_label):
		_defeat_level_label.text = tr("Уровень %d") % Main.current_level


func _process(delta: float) -> void:
	_hud_update_accum += delta
	if _hud_update_accum >= HUD_UPDATE_INTERVAL:
		_hud_update_accum = 0.0
		_refresh_hud()

	_update_end_screens()


func _refresh_hud() -> void:
	Main.money = snappedf(Main.money, 0.1)
	Main.damage = snappedf(Main.damage, 0.01)

	var money_pct: int = int((Main.money_multiplier - 1) * 100)
	_money_label.text = tr("Монет: %s (+%s%%)") % [str(Main.money), str(money_pct)]
	_damage_label.text = tr("Урон: %s") % str(Main.damage)
	_rocks_label.text = tr("Осталось камней: %d") % (Main.need_rocks - Main.destroyed_rocks)

	_level_progress.max_value = Main.need_rocks
	_level_progress.value = Main.destroyed_rocks

	var level_label_text: String
	if Main.level_controller != null and Main.level_controller.is_boss_level(Main.current_level):
		level_label_text = tr("Уровень %d — БОСС") % Main.current_level
	else:
		level_label_text = tr("Уровень %d") % Main.current_level
	_level_label.text = level_label_text

#	if not MobileInput.is_mobile:
#		_debug_label.text = "max_health: "+str(Main.max_health)+"\nchance_crit: "+str(Main.chance_crit)+" -> "+str(Main.chance_crit*100)+"%"+"\ncrit_multiplier: "+str(Main.crit_multiplier)+" ->"+str((Main.crit_multiplier-1)*100)+"%"+"\narmor: "+str(snappedf(Main.armor*100, 0.01))+"%"+"\nlifesteal: "+str(Main.lifesteal*100)+"%"+"\ndodge_chance: "+str(Main.dodge_chance*100)+"%"+"\nregen_mult: x"+str(Main.regen_mult)+"\nmove_speed_mult: x"+str(Main.move_speed_mult)+"\nskills: "+str(Main.unlocked_skills.keys())+"\nviewport_size: "+str(get_viewport().size)


func _update_end_screens() -> void:
	if Main.game_active:
		return

	if Main.player_died:
		if not _defeat_shown:
			_defeat_shown = true
			# Перед показом экрана поражения синхронизируем метку уровня:
			# HUD живёт между уровнями и без этого показал бы значение
			# с момента создания (обычно «Уровень 1»).
			_update_defeat_level_label()
			$LevelCompleteUI.hide()
			$UpgradeScreen.hide()
			if _defeat_root:
				_defeat_root.visible = true
			_set_mobile_controls_visible(false)
		return

	if on_continue == false:
		_rocks_destroyed_label.text = str(Main.destroyed_rocks)
		_money_get_label.text = str(Main.getted_money)
		$LevelCompleteUI.show()
		_set_mobile_controls_visible(false)


func _on_continue_button_pressed() -> void:
	if Main.game_active == false:
		$LevelCompleteUI.hide()
		$UpgradeScreen.show()
		_set_mobile_controls_visible(false)
		on_continue = true


func _on_reroll_button_pressed() -> void:
	if rerolls_left <= 0:
		return
	rerolls_left -= 1
	reroll_signal.emit()
	_update_reroll_button()


func _update_reroll_button() -> void:
	reroll_button.text = tr("РЕРОЛЛ (%d)") % rerolls_left
	reroll_button.disabled = rerolls_left <= 0


func _on_skip_button_pressed() -> void:
	$UpgradeScreen.hide()
	_set_mobile_controls_visible(true)
	# Логическая пауза: игрок нажал "Пропустить"/"Заново" -> реклама ->
	# либо следующий уровень, либо рестарт текущего (в режиме поражения).
	_show_ad_and_then(_after_upgrade_action)


func _on_upgradeclick(card: Node) -> void:
	$UpgradeScreen.hide()
	_set_mobile_controls_visible(true)
	# Логическая пауза: игрок выбрал апгрейд -> реклама -> следующий
	# уровень (или рестарт текущего, если это «камбэк» после поражения).
	_show_ad_and_then(_after_upgrade_action)


## Что делать после экрана апгрейда, когда игрок уже выбрал карточку
## или нажал "Заново":
##   - обычный сценарий (после победы) — грузим следующий уровень;
##   - сценарий после поражения (Main.defeat_mode) — рестартим тот же.
func _after_upgrade_action() -> void:
	if Main.defeat_mode:
		Main.restart_level()
	else:
		Main.load_next_level()


# ==================== ЭКРАН ПОРАЖЕНИЯ ====================

func _create_defeat_ui_deferred() -> void:
	if _defeat_root != null and is_instance_valid(_defeat_root):
		return

	var root := Control.new()
	root.name = "DefeatUI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	_defeat_root = root

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	# Та же панель, что в menu.tscn/hud.tscn, но с красной рамкой —
	# визуальный сигнал "поражение" в рамках общей стилистики.
	panel.add_theme_stylebox_override("panel", UIStyle.make_danger_panel_style(20, true))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = tr("ВЫ ПРОИГРАЛИ")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.apply_label_style(title, UIStyle.FONT_SIZE_TITLE_SMALL, UIStyle.COLOR_DANGER)
	vbox.add_child(title)

	var stats_label := Label.new()
	stats_label.text = tr("Уровень %d") % Main.current_level
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyle.apply_label_style(stats_label, UIStyle.FONT_SIZE_BODY, UIStyle.COLOR_TEXT_MUTED)
	vbox.add_child(stats_label)
	# Сохраняем ссылку — метку нужно обновлять при смене уровня, потому что
	# HUD переживает переходы между уровнями без пересоздания сцены.
	_defeat_level_label = stats_label

	# «Камбэк»-улучшение: открывает обычный UpgradeScreen в ослабленном
	# режиме. Игрок гарантированно может купить карточку, поэтому
	# тупиковая ситуация невозможна.
	var comeback_btn := Button.new()
	comeback_btn.text = tr("УЛУЧШЕНИЕ (ОСЛАБЛЕННОЕ)")
	comeback_btn.custom_minimum_size = Vector2(0, 52)
	UIStyle.apply_primary_button(comeback_btn, 10)
	comeback_btn.pressed.connect(_on_defeat_upgrade_pressed)
	vbox.add_child(comeback_btn)

	var retry_btn := Button.new()
	retry_btn.text = tr("ЗАНОВО")
	retry_btn.custom_minimum_size = Vector2(0, 52)
	UIStyle.apply_outline_button(retry_btn, 10)
	retry_btn.pressed.connect(_on_defeat_retry_pressed)
	vbox.add_child(retry_btn)

	var menu_btn := Button.new()
	menu_btn.text = tr("В МЕНЮ")
	menu_btn.custom_minimum_size = Vector2(0, 52)
	UIStyle.apply_outline_button(menu_btn, 10)
	menu_btn.pressed.connect(_on_defeat_menu_pressed)
	vbox.add_child(menu_btn)


## Открывает уже существующий UpgradeScreen в режиме поражения.
## Никакой параллельной системы апгрейдов — переиспользуются те же
## карточки, тот же сигнал reroll_signal, та же логика покупки.
func _on_defeat_upgrade_pressed() -> void:
	if _defeat_root:
		_defeat_root.visible = false
	# Включаем ослабленный режим ДО reroll: карточки при roll() читают
	# Main.defeat_mode и рассчитывают эффект/цену с учётом него.
	Main.defeat_mode = true
	on_continue = true
	reroll_signal.emit()
	$UpgradeScreen.show()
	_set_mobile_controls_visible(false)


func _on_defeat_retry_pressed() -> void:
	if _defeat_root:
		_defeat_root.visible = false
	_defeat_shown = false
	# Реклама -> рестарт уровня.
	_show_ad_and_then(_after_defeat_retry)


func _on_defeat_menu_pressed() -> void:
	Main.save_now()
	Main.level_controller = null
	_set_mobile_controls_visible(false)
	if _defeat_root:
		_defeat_root.visible = false
	_defeat_shown = false
	# Реклама -> переход в меню.
	_show_ad_and_then(_goto_main_menu)


# ==================== ИМЕНОВАННЫЕ КОЛБЭКИ ====================
#
# Раньше это были многострочные лямбды, переданные прямо в
# _show_ad_and_then(). В Godot 4.6 парсер на такой конструкции
# сходит с ума («Expected end of file»). Именованные методы решают
# проблему и заодно читаются понятнее.

func _after_defeat_retry() -> void:
	Main.restart_level()


func _goto_main_menu() -> void:
	get_tree().change_scene_to_file(Main.MENU_SCENE_PATH)


# ==================== ОБЩИЙ ХЕЛПЕР ДЛЯ ПОКАЗА РЕКЛАМЫ ====================

func _show_ad_and_then(action: Callable) -> void:
	if AdManager:
		AdManager.request_ad_after_action(action)
	else:
		# SDK отсутствует — просто выполняем действие без рекламы.
		if action.is_valid():
			action.call()


# --- Кнопка "В МЕНЮ" -------------------------------------------------

func _create_menu_button_deferred() -> void:
	var host: Node = get_parent()
	if host == null:
		host = get_tree().current_scene
	if host == null:
		host = self

	if host.has_node("MenuButtonLayer"):
		return

	var menu_layer := CanvasLayer.new()
	menu_layer.name = "MenuButtonLayer"
	menu_layer.layer = 100

	var menu_button := Button.new()
	menu_button.name = "MenuButton"
	menu_button.text = tr("В МЕНЮ")
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	menu_button.anchor_left = 1.0
	menu_button.anchor_right = 1.0
	menu_button.anchor_top = 0.0
	menu_button.anchor_bottom = 0.0
	var btn_width: float = 220.0 if MobileInput.is_mobile else 135.0
	var btn_height: float = 70.0 if MobileInput.is_mobile else 40.0
	menu_button.offset_left = -btn_width - 15.0
	menu_button.offset_right = -15.0
	menu_button.offset_top = 15.0
	menu_button.offset_bottom = 15.0 + btn_height
	# Контурный серый стиль — тот же, что у Reroll/Skip в hud.tscn:
	# маленькая вспомогательная кнопка поверх игрового мира.
	UIStyle.apply_primary_button(menu_button, 10)
	menu_button.add_theme_font_size_override("font_size", 22 if MobileInput.is_mobile else 16)
	menu_button.pressed.connect(_on_menu_button_pressed)

	menu_layer.add_child(menu_button)
	host.add_child(menu_layer)
	_menu_button = menu_button


# --- Мобильный слой ---------------------------------------------------

func _create_mobile_controls_deferred() -> void:
	if not MobileInput.is_mobile:
		return

	var host: Node = get_parent()
	if host == null:
		host = get_tree().current_scene
	if host == null:
		host = self

	if host.has_node("MobileControlsLayer"):
		return

	var layer := CanvasLayer.new()
	layer.name = "MobileControlsLayer"
	layer.set_script(MobileUIScript)
	host.add_child(layer)
	_mobile_controls_layer = layer


func _set_mobile_controls_visible(v: bool) -> void:
	if _mobile_controls_layer and is_instance_valid(_mobile_controls_layer):
		_mobile_controls_layer.visible = v


func _on_menu_button_pressed() -> void:
	on_continue = true
	Main.save_now()
	Main.level_controller = null
	_set_mobile_controls_visible(false)
	# Кнопка "В МЕНЮ" может быть нажата посреди активного уровня (не только
	# после победы/поражения) — на этот случай сами закрываем разметку
	# геймплея. Если она уже была закрыта (level.gd::finish_level или
	# player.gd::_die), повторный вызов безопасен и ничего не ломает.
	if YandexSDK:
		YandexSDK.stop_gameplay()
	# Логическая пауза: игрок нажал "В МЕНЮ" -> реклама -> смена сцены.
	_show_ad_and_then(_goto_main_menu)
