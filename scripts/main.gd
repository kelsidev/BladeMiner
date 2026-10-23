extends Node

const SAVE_VERSION := 2
const MENU_SCENE_PATH := "res://levels/menu.tscn"

signal level_changed(level_num: int)
signal language_changed(code: String)
## Эмитится ровно один раз — когда облачный сейв получен (или когда мы
## точно убедились, что SDK недоступен). Используется меню, чтобы не
## запустить игру до того, как станет известен прогресс игрока.
signal save_ready

var level_controller: Node = null

var current_level = 1
var infinite_mode: bool = false
var story_completed: bool = false

# save_loaded становится true, как только облачный сейв получен (или как
# только мы убедились, что SDK недоступен). До этого момента все
# сохранения игнорируются — иначе можно было бы перезаписать облако
# дефолтным сейвом, пока не пришёл ответ от SDK.
var save_loaded: bool = false
var save_data: Dictionary = {}

# --- Язык ---
var current_language: String = "ru"
var _locale_was_synced: bool = true

# --- Базовые статы ---
var base_damage = 10.0
var damage = 10.0
var damage_mult = 1.0

var base_max_health = 30.0
var max_health = 30.0
var health_mult = 1.0

var chance_crit = 0.025
var crit_multiplier = 1.25
var move_speed_mult = 1.0
var money_multiplier = 1.0
var money = 0.0

var armor: float = 0.0

var lifesteal = 0.0
var dodge_chance = 0.0
var regen_mult = 1.0

var unlocked_skills: Dictionary = {}
var second_wind_used: bool = false

var player_died: bool = false
var defeat_mode: bool = false

func has_skill(skill_id: String) -> bool:
	return unlocked_skills.has(skill_id)

func unlock_skill(skill_id: String) -> void:
	unlocked_skills[skill_id] = true

# --- Параметры уровня ---
var current_type_weights: Array = [1, 1, 1, 0, 0, 0]
var level_hp_multiplier_extra: float = 1.0
var level_money_multiplier_extra: float = 1.0

func weighted_random_index(weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return randi_range(0, weights.size() - 1)
	var r: float = randf_range(0.0, total)
	var cumulative: float = 0.0
	for i in weights.size():
		cumulative += weights[i]
		if r <= cumulative:
			return i
	return weights.size() - 1

var need_rocks = 15
var left_rocks = 15
var destroyed_rocks = 0
var getted_money = 0
var game_active = true

const rock_scene: PackedScene = preload("res://objects/rock.tscn")
var rocks_positions: Array[Vector2] = []
var max_attempts: int = 30
var rock_size_px: float = 32.0
var rock_scale: float = 2.375
var rock_radius: float = (rock_size_px * rock_scale) / 2.0
var min_distance: float = rock_radius * 2.0
var spawned_rocks: Array[Node] = []

# --- Убывающая полезность ---
const CRIT_CHANCE_CAP: float = 0.75
const CRIT_DAMAGE_DIMINISH_K: float = 1.0
const MONEY_MULT_DIMINISH_K: float = 1.0
const DAMAGE_DIMINISH_K: float = 1.0
const HEALTH_DIMINISH_K: float = 1.0
const ARMOR_CAP: float = 0.60
const REGEN_DIMINISH_K: float = 1.0
const MOVE_SPEED_DIMINISH_K: float = 1.0
const LIFESTEAL_CAP: float = 0.20
const DODGE_CHANCE_CAP: float = 0.40
const STAT_ROUND_STEP: float = 0.0001

func apply_diminishing_bonus_capped(current: float, cap: float, raw_fraction: float) -> float:
	var new_value = current + raw_fraction * (cap - current)
	new_value = clamp(new_value, 0.0, cap)
	return snappedf(new_value, STAT_ROUND_STEP)

func apply_diminishing_multiplier(current: float, raw_fraction: float, k: float) -> float:
	var current_bonus = current - 1.0
	var increment = raw_fraction / (1.0 + current_bonus * k)
	var new_bonus = current_bonus + increment
	return snappedf(1.0 + new_bonus, STAT_ROUND_STEP)

# ==================== ИНИЦИАЛИЗАЦИЯ ====================
#
# Прогресс хранится ТОЛЬКО в облаке Яндекс Игр. Локальный файл больше
# не используется (это осознанный отказ от local-first в пользу
# cloud-only). Если SDK недоступен — прогресс не сохраняется вообще;
# save_loaded становится true, и дальнейшие save-вызовы просто no-op.

func _ready() -> void:
	Localization.register_all()
	save_data = _get_default_save_data()
	_apply_save_data(save_data)
	_apply_saved_or_default_language()

	if YandexSDK:
		YandexSDK.sdk_initialized.connect(_on_sdk_initialized)
		if YandexSDK.is_initialized:
			_on_sdk_initialized()
		YandexSDK.save_loaded.connect(_on_cloud_save_loaded)
		YandexSDK.save_completed.connect(_on_cloud_save_completed)
	else:
		push_warning("[Main] YandexSDK autoload not found. Progress will NOT be saved.")
		save_loaded = true
		# Сигнал эмитим отложенно: меню (главная сцена) подключается к нему
		# в своём _ready(), который отработает уже после автозагрузок.
		# call_deferred гарантирует, что подписчик успеет подключиться.
		call_deferred("_emit_save_ready")


func _emit_save_ready() -> void:
	save_ready.emit()


func _on_sdk_initialized() -> void:
	print("[Main] YandexSDK initialized.")
	if not save_data.has("language_manual"):
		var detected: String = YandexSDK.get_platform_language()
		var normalized: String = Localization.normalize(detected)
		if normalized != "":
			_apply_language(normalized)
		else:
			print("[Lang] Platform language not supported or empty; keeping '",
				current_language, "'")
	_force_locale(current_language)
	YandexSDK.load_save()


# ==================== ЯЗЫК ====================

func _apply_saved_or_default_language() -> void:
	var code: String = Localization.DEFAULT_LOCALE
	if save_data.has("language"):
		var s: String = Localization.normalize(String(save_data["language"]))
		if s != "":
			code = s
	_apply_language(code)


func _apply_language(code: String) -> void:
	if not Localization.is_supported(code):
		code = Localization.DEFAULT_LOCALE
	current_language = code
	_force_locale(code)
	_locale_was_synced = true
	language_changed.emit(code)


func _force_locale(code: String) -> void:
	TranslationServer.set_locale(code)
	if code != TranslationServer.get_locale():
		TranslationServer.set_locale(code)


func get_language() -> String:
	return current_language


func set_language(code: String) -> void:
	code = Localization.normalize(code)
	if code == "":
		return
	_apply_language(code)
	save_data["language"] = code
	save_data["language_manual"] = true
	# Если облачный сейв уже загружен — сразу отправим выбор в облако.
	# Если нет — выбор запомнится в save_data и уедет при следующем save.
	if save_loaded:
		_save_progress()


# ==================== ДЕРЖИМ ЛОКАЛЬ СИНХРОНИЗИРОВАННОЙ ====================

func _process(_delta: float) -> void:
	var active: String = Localization.normalize(TranslationServer.get_locale())
	var is_synced: bool = (active == current_language)
	if not is_synced:
		TranslationServer.set_locale(current_language)
		if _locale_was_synced:
			_locale_was_synced = false
			call_deferred("_emit_language_changed")
	elif not _locale_was_synced:
		_locale_was_synced = true

	if Input.is_action_just_pressed("restart"):
		restart_level()


func _emit_language_changed() -> void:
	language_changed.emit(current_language)


# ==================== СОХРАНЕНИЯ (cloud-only) ====================

func _get_default_save_data() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"story_completed": false,
		"current_level": 1,
		"timestamp": 0,
		"money": 0.0,
		"damage_mult": 1.0,
		"health_mult": 1.0,
		"chance_crit": 0.025,
		"crit_multiplier": 1.25,
		"move_speed_mult": 1.0,
		"money_multiplier": 1.0,
		"armor": 0.0,
		"lifesteal": 0.0,
		"dodge_chance": 0.0,
		"regen_mult": 1.0,
		"second_wind_used": false,
		"unlocked_skills": [],
	}


func _apply_save_data(data: Dictionary) -> void:
	if data.has("story_completed") and typeof(data["story_completed"]) == TYPE_BOOL:
		story_completed = data["story_completed"]
	else:
		story_completed = false
	_apply_player_state(data)


func _apply_player_state(data: Dictionary) -> void:
	money             = float(data.get("money", 0.0))
	damage_mult       = float(data.get("damage_mult", 1.0))
	health_mult       = float(data.get("health_mult", 1.0))
	chance_crit       = float(data.get("chance_crit", 0.025))
	crit_multiplier   = float(data.get("crit_multiplier", 1.25))
	move_speed_mult   = float(data.get("move_speed_mult", 1.0))
	money_multiplier  = float(data.get("money_multiplier", 1.0))
	armor             = clampf(float(data.get("armor", 0.0)), 0.0, ARMOR_CAP)
	lifesteal         = float(data.get("lifesteal", 0.0))
	dodge_chance      = float(data.get("dodge_chance", 0.0))
	regen_mult        = float(data.get("regen_mult", 1.0))
	second_wind_used  = bool(data.get("second_wind_used", false))

	damage = base_damage * damage_mult
	max_health = base_max_health * health_mult

	unlocked_skills.clear()
	var arr: Variant = data.get("unlocked_skills", [])
	if typeof(arr) == TYPE_ARRAY:
		for s in arr:
			unlocked_skills[str(s)] = true


func _collect_player_state() -> void:
	save_data["money"] = money
	save_data["damage_mult"] = damage_mult
	save_data["health_mult"] = health_mult
	save_data["chance_crit"] = chance_crit
	save_data["crit_multiplier"] = crit_multiplier
	save_data["move_speed_mult"] = move_speed_mult
	save_data["money_multiplier"] = money_multiplier
	save_data["armor"] = armor
	save_data["lifesteal"] = lifesteal
	save_data["dodge_chance"] = dodge_chance
	save_data["regen_mult"] = regen_mult
	save_data["second_wind_used"] = second_wind_used
	save_data["unlocked_skills"] = unlocked_skills.keys()


func _on_cloud_save_loaded(data: Dictionary) -> void:
	if not data.is_empty():
		if data.has("save_version") and int(data["save_version"]) > SAVE_VERSION:
			push_warning("[Save] Cloud save version is newer than game. Ignoring cloud data.")
			save_loaded = true
			save_ready.emit()
			return

		print("[Save] Applying cloud save.")
		save_data = data
		_apply_save_data(save_data)

		if save_data.has("language"):
			var cloud_lang: String = Localization.normalize(String(save_data["language"]))
			if cloud_lang != "":
				_apply_language(cloud_lang)
	else:
		# Облако пустое: либо новый игрок, либо игрок сбросил онлайн-данные
		# через интерфейс Яндекс Игр. В обоих случаях — стартуем с нуля
		# и сразу же публикуем дефолтный сейв в облако, чтобы зафиксировать
		# это состояние.
		print("[Save] Cloud empty. Starting fresh; uploading default save.")
		save_data = _get_default_save_data()
		_apply_save_data(save_data)
		_apply_player_state(save_data)
		if YandexSDK and YandexSDK.is_available:
			YandexSDK.save_data(save_data)

	save_loaded = true
	save_ready.emit()


func save_now() -> void:
	_save_progress()


func _save_progress(override_current_level: int = -1) -> void:
	if not save_loaded:
		return

	save_data["timestamp"] = int(Time.get_unix_time_from_system())
	save_data["save_version"] = SAVE_VERSION
	save_data["story_completed"] = story_completed

	# save_data["current_level"] — это уровень, на котором игрок продолжит
	# в следующей сессии, а НЕ тот, на котором он сейчас играет.
	#
	# Когда уровень пройден, mark_level_completed() передаёт сюда следующий
	# уровень через override. Обычные сохранения (покупка апгрейда, кнопка
	# "В МЕНЮ", экран поражения, смена языка) НЕ должны откатывать значение
	# назад к только что завершённому уровню — поэтому берём max().
	#
	# Дополнительно это защищает от гонки: облачный сейв с более высоким
	# уровнем может прийти позже, чем игрок начнёт играть — max() не даст
	# «догнать» его вниз и откатить прогресс.
	var stored_level: int = max(1, int(save_data.get("current_level", 1)))
	var candidate: int = override_current_level if override_current_level > 0 else current_level
	save_data["current_level"] = max(stored_level, candidate)

	_collect_player_state()

	if YandexSDK and YandexSDK.is_available:
		YandexSDK.save_data(save_data)


func _on_cloud_save_completed(success: bool) -> void:
	if not success:
		push_warning("[Save] Cloud save failed. Progress is only in memory this session.")


func mark_level_completed(cleared_level: int) -> void:
	_save_progress(cleared_level + 1)


# ==================== ИГРОВАЯ ЛОГИКА ====================

func load_level(level_num: int) -> void:
	if level_controller == null:
		print("Ошибка: level_controller не назначен — level.gd не зарегистрировался в Main")
		return

	current_level = level_num
	game_active = true
	player_died = false
	defeat_mode = false

	level_controller.start_level(current_level)
	level_changed.emit(current_level)


func load_next_level() -> void:
	if not infinite_mode \
			and level_controller != null \
			and level_controller.has_method("is_last_story_level") \
			and level_controller.is_last_story_level(current_level):

		story_completed = true
		_save_progress()

		level_controller = null
		get_tree().change_scene_to_file(MENU_SCENE_PATH)
		return

	load_level(current_level + 1)


func restart_level() -> void:
	load_level(current_level)


func clear_rocks() -> void:
	for rock in spawned_rocks:
		if is_instance_valid(rock):
			var rock_parent := rock.get_parent()
			if rock_parent:
				rock_parent.remove_child(rock)
			rock.queue_free()
	spawned_rocks.clear()
	rocks_positions.clear()


func generate_rocks(count: int, parent: Node2D, zone: ReferenceRect) -> void:
	rocks_positions.clear()

	var zone_global_pos: Vector2 = zone.global_position
	var zone_size: Vector2 = zone.size
	var margin: float = rock_radius
	var usable_size: Vector2 = zone_size - Vector2(margin, margin) * 2.0
	usable_size.x = max(usable_size.x, 0.0)
	usable_size.y = max(usable_size.y, 0.0)

	var cell_size: float = min_distance
	var grid_width: int = max(1, int(ceil(usable_size.x / cell_size)))
	var grid_height: int = max(1, int(ceil(usable_size.y / cell_size)))
	var grid: Array = []
	for x in range(grid_width):
		grid.append([])
		for y in range(grid_height):
			grid[x].append([])

	for i in count:
		var rock = rock_scene.instantiate()
		var spawn_pos_global: Vector2 = Vector2.ZERO
		var valid_pos: bool = false
		var attempts: int = 0
		while not valid_pos and attempts < max_attempts:
			spawn_pos_global = zone_global_pos + Vector2(margin, margin) + Vector2(
				randf_range(0.0, usable_size.x),
				randf_range(0.0, usable_size.y)
			)
			var rel_x: float = spawn_pos_global.x - (zone_global_pos.x + margin)
			var rel_y: float = spawn_pos_global.y - (zone_global_pos.y + margin)
			var gx: int = clampi(int(rel_x / cell_size), 0, grid_width - 1)
			var gy: int = clampi(int(rel_y / cell_size), 0, grid_height - 1)

			valid_pos = true
			for dx in range(-1, 2):
				if not valid_pos:
					break
				for dy in range(-1, 2):
					var nx: int = gx + dx
					var ny: int = gy + dy
					if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
						for existing_pos in grid[nx][ny]:
							if spawn_pos_global.distance_to(existing_pos) < min_distance:
								valid_pos = false
								break
					if not valid_pos:
						break
			attempts += 1

		var rel_x2: float = spawn_pos_global.x - (zone_global_pos.x + margin)
		var rel_y2: float = spawn_pos_global.y - (zone_global_pos.y + margin)
		var final_gx: int = clampi(int(rel_x2 / cell_size), 0, grid_width - 1)
		var final_gy: int = clampi(int(rel_y2 / cell_size), 0, grid_height - 1)
		grid[final_gx][final_gy].append(spawn_pos_global)
		rocks_positions.append(spawn_pos_global)
		rock.position = parent.to_local(spawn_pos_global)
		rock.z_index = 1
		parent.add_child(rock)
		spawned_rocks.append(rock)


func reset_game() -> void:
	current_level = max(1, int(save_data.get("current_level", 1)))
	game_active = true
	infinite_mode = false
	player_died = false
	defeat_mode = false

	_apply_player_state(save_data)

	current_type_weights = [1, 1, 1, 0, 0, 0]
	level_hp_multiplier_extra = 1.0
	level_money_multiplier_extra = 1.0
	need_rocks = 15
	left_rocks = 15
	destroyed_rocks = 0
	getted_money = 0

	spawned_rocks.clear()
	rocks_positions.clear()
	level_controller = null
