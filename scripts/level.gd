extends Node

signal level_started(level_num: int)
signal level_finished(level_num: int)

var rock_count: int = 15

# ==================== ПОДГОНКА ФОНА ПОД ЭКРАН ====================
#
# Поле в сцене свёрстано жёстко (18x10 тайлов, масштаб 2, тайл 32px =
# 1152x640 мира). При stretch-режиме canvas_items + expand вьюпорт
# расширяется под другой аспект экрана, и за пределами поля проступал
# серый фон. Чтобы серых полос не было, декоративный пол достраивается
# до размеров видимой области.
#
# ВАЖНО: авторская арена НЕ меняется. Стены (Top) и SpawnZone остаются на
# месте, поэтому стены всегда видны, а игрок физически не может выйти за
# пределы арены. Достраивается только пол (Ground), у которого нет
# коллизии. Так подгонка не зависит от момента/размера ресайза и не
# ломает игровую логику.
const TILE_WORLD: float = 64.0
const FLOOR_TILES: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 0)]

var _origin_ground: Dictionary = {}

# ==================== СЮЖЕТНЫЕ УРОВНИ (12 -> 15) ====================
#
# Финальный баланс перед отправкой на модерацию Яндекс Игр.
#
# 12 сюжетных уровней давали среднее прохождение ~9-10 минут (без учёта
# рекламных пауз), что ниже целевых 10-15 минут. Добавлены три уровня
# (13, 14, 15) — при этом 15-й автоматически становится босс-уровнем
# (каждый пятый, см. is_boss_level), что даёт кульминацию сюжета.
#
# Кривая сложности сознательно сохранена:
#   1-4   — знакомство, только простые камни;
#   5     — первый босс (chaser, hp ×1.6);
#   6     — передышка: мало камней, но уже с chaser'ами;
#   7     — много простых камней, «прокачка»;
#   8-9   — появляются thrower и tank;
#   10    — второй босс (tank, hp ×1.85);
#   11-12 — плотные уровни со всеми типами камней;
#   13-14 — финальная сложность: мало «базовых», много живых;
#   15    — финальный босс (2 танка, hp ×2.1).
#
# Никаких искусственных задержек, огромных HP или бессмысленных волн
# не добавлено — только продление естественной прогрессии.
const LEVELS: Array[Dictionary] = [
	{"rock_count": 8,  "weights": [1, 0, 0, 0, 0, 0], "hp_extra": 1.0},   # 1
	{"rock_count": 10, "weights": [3, 1, 0, 0, 0, 0], "hp_extra": 1.0},   # 2
	{"rock_count": 9,  "weights": [2, 2, 1, 0, 0, 0], "hp_extra": 1.0},   # 3
	{"rock_count": 12, "weights": [2, 2, 1, 0, 0, 0], "hp_extra": 1.0},   # 4
	{"rock_count": 14, "weights": [3, 2, 1, 1, 0, 0], "hp_extra": 1.0},   # 5 BOSS
	{"rock_count": 6,  "weights": [0, 0, 1, 2, 0, 0], "hp_extra": 1.0},   # 6
	{"rock_count": 20, "weights": [5, 1, 0, 0, 0, 0], "hp_extra": 1.0},   # 7
	{"rock_count": 12, "weights": [1, 3, 2, 1, 1, 0], "hp_extra": 1.0},   # 8
	{"rock_count": 10, "weights": [0, 2, 3, 1, 2, 1], "hp_extra": 1.1},   # 9
	{"rock_count": 16, "weights": [1, 2, 2, 2, 2, 1], "hp_extra": 1.1},   # 10 BOSS
	{"rock_count": 24, "weights": [3, 3, 2, 1, 1, 1], "hp_extra": 1.0},   # 11
	{"rock_count": 14, "weights": [0, 1, 1, 2, 2, 3], "hp_extra": 1.3},   # 12
	{"rock_count": 18, "weights": [1, 1, 2, 3, 2, 3], "hp_extra": 1.35},  # 13 NEW
	{"rock_count": 16, "weights": [0, 1, 2, 3, 3, 3], "hp_extra": 1.45},  # 14 NEW
	{"rock_count": 14, "weights": [0, 1, 1, 2, 2, 3], "hp_extra": 1.3},   # 15 BOSS (override)
]

func generate_procedural_level(level_num: int) -> Dictionary:
	var extra: int = level_num - LEVELS.size()
	var count: int = int(round((5 + level_num) * 1.25))
	var chaser_weight: int = min(1 + int(extra / 3), 2)
	var thrower_weight: int = max(0, min(1 + int((extra - 3) / 3), 2))
	var tank_weight: int = max(0, min(1 + int((extra - 6) / 3), 2))
	var weights: Array = [2, 2, 2, chaser_weight, thrower_weight, tank_weight]
	return {"rock_count": count, "weights": weights, "hp_extra": 1.0 + extra * 0.05}

const BOSS_LEVEL_INTERVAL: int = 5

func is_boss_level(level_num: int) -> bool:
	return level_num > 0 and level_num % BOSS_LEVEL_INTERVAL == 0

func _boss_type_weights(level_num: int) -> Array:
	if level_num >= 9:
		return [0, 0, 0, 0, 0, 1]
	elif level_num >= 8:
		return [0, 0, 0, 0, 1, 0]
	elif level_num >= 5:
		return [0, 0, 0, 1, 0, 0]
	return [0, 0, 1, 0, 0, 0]

func _apply_boss_overrides(data: Dictionary, level_num: int) -> Dictionary:
	var boss_index: int = level_num / BOSS_LEVEL_INTERVAL
	data.rock_count = min(1 + int((boss_index - 1) / 2), 4)
	data.weights = _boss_type_weights(level_num)
	# Множитель HP босса снижен с 2.5 до 1.6. Комбинированно с level-скейлом
	# это давало ×3.81 на 5 уровне - непроходимо. Теперь ~×2.16.
	# Награда за босса осталась, чтобы победа над ним была ощутимо ценной.
	data.hp_extra = 1.6 + 0.25 * (boss_index - 1)
	data.money_extra = 3.0 + 0.5 * (boss_index - 1)
	return data

func get_level_data(level_num: int) -> Dictionary:
	var data: Dictionary
	if level_num >= 1 and level_num <= LEVELS.size():
		data = LEVELS[level_num - 1].duplicate(true)
	else:
		data = generate_procedural_level(level_num)
	if is_boss_level(level_num):
		data = _apply_boss_overrides(data, level_num)
	return data

func is_last_story_level(level_num: int) -> bool:
	return level_num >= LEVELS.size()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Main.level_controller = self
	_capture_original_field()
	_setup_background()
	_setup_camera()
	_fit_field_to_viewport()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_apply_graphics_settings()
	if not GraphicsSettings.settings_changed.is_connected(_apply_graphics_settings):
		GraphicsSettings.settings_changed.connect(_apply_graphics_settings)

	# Platform pause handling (п.1.19.4): pause game tree and mute audio
	# when platform requests pause (e.g. tab switch, ad overlay).
	if YandexSDK:
		YandexSDK.pause_state_changed.connect(_on_pause_state_changed)
		YandexSDK.pause_state_changed.connect(_on_pause_for_audio)

	start_level(Main.current_level)


func _on_pause_state_changed(is_paused: bool) -> void:
	get_tree().paused = is_paused


func _on_pause_for_audio(is_paused: bool) -> void:
	if not AudioManager:
		return
	if is_paused:
		AudioManager.mute_master("platform_pause")
	else:
		AudioManager.unmute_master("platform_pause")


# Применяет настройки графики к объектам, специфичным для уровня.
# Environment и PointLight2D - самые тяжёлые GPU-эффекты в сцене,
# поэтому их нужно уметь полностью выключать.
func _apply_graphics_settings() -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		GraphicsSettings.apply_environment(we.environment)
	var light := get_node_or_null("PointLight2D")
	if light:
		GraphicsSettings.apply_light(light)


# Фолбэк-заливка на случай щелей между тайлами (например, из-за
# округления при масштабировании). Поле теперь достраивается до краёв
# экрана, поэтому цвет подобран под модулированный пол, чтобы заливка
# была незаметна.
func _setup_background() -> void:
	if has_node("BackgroundLayer"):
		return

	var layer := CanvasLayer.new()
	layer.name = "BackgroundLayer"
	layer.layer = -10

	var rect := ColorRect.new()
	rect.name = "BackgroundRect"
	rect.anchor_left = 0.0
	rect.anchor_top = 0.0
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(0.133, 0.133, 0.153)
	layer.add_child(rect)

	add_child(layer)


# Запоминаем авторскую раскладку пола ДО первой подгонки — она нужна,
# чтобы не менять вид центральной части арены.
func _capture_original_field() -> void:
	var ground := get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return
	for y in range(ground.get_used_rect().position.y,
			ground.get_used_rect().end.y):
		for x in range(ground.get_used_rect().position.x,
				ground.get_used_rect().end.x):
			var cell := Vector2i(x, y)
			var src: int = ground.get_cell_source_id(cell)
			if src != -1:
				_origin_ground[cell] = ground.get_cell_atlas_coords(cell)


func _setup_camera() -> void:
	if has_node("LevelCamera"):
		return
	var cam := Camera2D.new()
	cam.name = "LevelCamera"
	cam.position = Vector2(576.0, 320.0)
	cam.zoom = Vector2(1.0, 1.0)
	cam.enabled = true
	add_child(cam)
	cam.make_current()


func _on_viewport_resized() -> void:
	_fit_field_to_viewport()


# Cached values for incremental update optimization
var _prev_min_cell: Vector2i = Vector2i(-1, -1)
var _prev_max_cell: Vector2i = Vector2i(-1, -1)
var _prev_zoom: float = -1.0


# Достраивает декоративный пол до краёв видимой области. Стены (Top) и
# SpawnZone не трогаются: арена остаётся прежней, стены видны, игрок
# всегда внутри, а серый фон не проступает при любом аспекте.
# Также подгоняет зум камеры, чтобы арена (1152x640) всегда полностью
# помещалась во вьюпорт (п. 1.10.1).
func _fit_field_to_viewport() -> void:
	var ground := get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return

	var cam := get_node_or_null("LevelCamera") as Camera2D
	if cam == null:
		return

	# Arena size in world pixels (18x10 tiles * 64px).
	const ARENA_SIZE: Vector2 = Vector2(1152.0, 640.0)
	const ARENA_CENTER: Vector2 = Vector2(576.0, 320.0)

	var view: Vector2 = get_viewport().get_visible_rect().size

	# Calculate zoom to fit arena in viewport.
	# Zoom = min(viewport_width / arena_width, viewport_height / arena_height)
	var zoom_x: float = view.x / ARENA_SIZE.x
	var zoom_y: float = view.y / ARENA_SIZE.y
	var zoom: float = min(zoom_x, zoom_y)

	# Don't zoom in beyond 1.0 (original size).
	zoom = min(zoom, 1.0)

	cam.zoom = Vector2(zoom, zoom)
	cam.position = ARENA_CENTER

	# Now calculate visible tile range based on zoomed viewport.
	var half: Vector2 = (view / cam.zoom) * 0.5
	var min_cell := Vector2i(
		int(floor((ARENA_CENTER.x - half.x) / TILE_WORLD)),
		int(floor((ARENA_CENTER.y - half.y) / TILE_WORLD)))
	var max_cell := Vector2i(
		int(ceil((ARENA_CENTER.x + half.x) / TILE_WORLD)) - 1,
		int(ceil((ARENA_CENTER.y + half.y) / TILE_WORLD)) - 1)

	# Skip rebuild if visible range hasn't changed (optimization for resize events)
	if _prev_min_cell == min_cell and _prev_max_cell == max_cell and _prev_zoom == zoom:
		return
	_prev_min_cell = min_cell
	_prev_max_cell = max_cell
	_prev_zoom = zoom

	ground.clear()
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)
			var atlas: Vector2i = _origin_ground.get(cell, _floor_tile_for(cell))
			ground.set_cell(cell, 0, atlas)


# Детерминированный "шум" для тайлов пола вне авторской раскладки:
# рисунок стабилен между перестройками поля.
func _floor_tile_for(cell: Vector2i) -> Vector2i:
	var h: int = (cell.x * 92837111) ^ (cell.y * 689287499)
	return FLOOR_TILES[posmod(h, FLOOR_TILES.size())]


func _process(_delta: float) -> void:
	finish_level()


func start_level(level_num: int) -> void:
	Main.current_level = level_num

	var level_data: Dictionary = get_level_data(level_num)
	rock_count = level_data.rock_count

	Main.current_type_weights = level_data.weights
	Main.level_hp_multiplier_extra = level_data.get("hp_extra", 1.0)
	Main.level_money_multiplier_extra = level_data.get("money_extra", 1.0)

	Main.destroyed_rocks = 0
	Main.getted_money = 0
	Main.left_rocks = rock_count
	Main.need_rocks = rock_count

	Main.clear_rocks()
	Main.generate_rocks(rock_count, get_tree().current_scene, $SpawnZone)

	if YandexSDK:
		YandexSDK.start_gameplay()

	level_started.emit(level_num)


func finish_level() -> void:
	if not Main.game_active:
		return
	var destroyed_rocks = Main.destroyed_rocks
	if destroyed_rocks >= rock_count:
		Main.game_active = false
		Main.mark_level_completed(Main.current_level)
		if YandexSDK:
			YandexSDK.stop_gameplay()
		level_finished.emit(Main.current_level)
