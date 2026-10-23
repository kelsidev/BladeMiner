extends Node
## Автозагрузка "GraphicsSettings". Хранит и применяет графические настройки.
## Отдельный файл сохранения (user://graphics.cfg), НЕ смешивается с игровым
## прогрессом (Main.save_data / YandexSDK).
##
## В том же файле хранятся и настройки звука (секция [audio]), но они
## намеренно вынесены из словаря settings: смена графического пресета
## не должна сбрасывать громкость.

signal settings_changed
signal audio_changed

const CONFIG_PATH := "user://graphics.cfg"
const CONFIG_SECTION := "graphics"
const AUDIO_SECTION := "audio"

# --- Аудио (0.0..1.0). Хранится отдельно от PRESETS. ---
const DEFAULT_MUSIC_VOLUME: float = 0.8
const DEFAULT_SFX_VOLUME: float = 0.8

var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME

enum Preset { VERY_LOW, LOW, MEDIUM, HIGH }

const PRESET_NAMES := {
	Preset.VERY_LOW: "Очень низкое",
	Preset.LOW:      "Низкое",
	Preset.MEDIUM:   "Среднее",
	Preset.HIGH:     "Высокое",
}

const PRESETS := {
	Preset.VERY_LOW: {
		"max_fps": 30,
		"vsync": false,
		"particles_enabled": false,
		"damage_numbers": false,
		"shake_enabled": false,
		"lighting_enabled": false,
		"glow_enabled": false,
		"saturation_enabled": false,
		"ai_tick_hz": 5.0,
	},
	Preset.LOW: {
		"max_fps": 45,
		"vsync": false,
		"particles_enabled": true,
		"damage_numbers": true,
		"shake_enabled": false,
		"lighting_enabled": false,
		"glow_enabled": false,
		"saturation_enabled": false,
		"ai_tick_hz": 10.0,
	},
	Preset.MEDIUM: {
		"max_fps": 60,
		"vsync": false,
		"particles_enabled": true,
		"damage_numbers": true,
		"shake_enabled": true,
		"lighting_enabled": true,
		"glow_enabled": false,
		"saturation_enabled": true,
		"ai_tick_hz": 30.0,
	},
	Preset.HIGH: {
		"max_fps": 0,
		"vsync": true,
		"particles_enabled": true,
		"damage_numbers": true,
		"shake_enabled": true,
		"lighting_enabled": true,
		"glow_enabled": true,
		"saturation_enabled": true,
		"ai_tick_hz": 0.0,
	},
}

var current_preset: Preset = Preset.HIGH
var settings: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_apply_runtime_settings()


# ==================== Публичное API ====================

func set_preset(preset: int) -> void:
	var p: Preset = preset as Preset
	if not PRESETS.has(p):
		return
	current_preset = p
	settings = (PRESETS[p] as Dictionary).duplicate()
	_apply_runtime_settings()
	_save_settings()
	settings_changed.emit()


func set_value(key: String, value) -> void:
	if not settings.has(key):
		return
	if settings[key] == value:
		return
	settings[key] = value
	_apply_runtime_settings()
	_save_settings()
	settings_changed.emit()


func get_value(key: String, default_value = null) -> Variant:
	return settings.get(key, default_value)


# --- Аудио ---

func set_music_volume(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(music_volume, value):
		return
	music_volume = value
	_save_settings()
	audio_changed.emit()


func set_sfx_volume(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(sfx_volume, value):
		return
	sfx_volume = value
	_save_settings()
	audio_changed.emit()


func get_music_volume() -> float:
	return music_volume


func get_sfx_volume() -> float:
	return sfx_volume


func apply_environment(env: Environment) -> void:
	if env == null:
		return
	env.glow_enabled = bool(settings.get("glow_enabled", true))
	env.adjustment_enabled = bool(settings.get("saturation_enabled", true))


func apply_light(light: Node) -> void:
	if light == null:
		return
	if light is CanvasItem:
		(light as CanvasItem).visible = bool(settings.get("lighting_enabled", true))


# ==================== Внутреннее ====================

func _apply_runtime_settings() -> void:
	var fps: int = int(settings.get("max_fps", 60))
	Engine.max_fps = fps

	var use_vsync: bool = bool(settings.get("vsync", true))
	var mode: int = DisplayServer.VSYNC_ENABLED if use_vsync else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var loaded: bool = cfg.load(CONFIG_PATH) == OK

	# --- Аудио (независимо от графического пресета) ---
	if loaded:
		music_volume = clampf(
			float(cfg.get_value(AUDIO_SECTION, "music_volume", DEFAULT_MUSIC_VOLUME)),
			0.0, 1.0)
		sfx_volume = clampf(
			float(cfg.get_value(AUDIO_SECTION, "sfx_volume", DEFAULT_SFX_VOLUME)),
			0.0, 1.0)
	else:
		music_volume = DEFAULT_MUSIC_VOLUME
		sfx_volume = DEFAULT_SFX_VOLUME

	# --- Графика ---
	if loaded:
		var raw_preset: int = int(cfg.get_value(CONFIG_SECTION, "preset", -1))
		if raw_preset >= 0 and PRESETS.has(raw_preset as Preset):
			current_preset = raw_preset as Preset
		else:
			current_preset = _detect_default_preset()

		settings = (PRESETS[current_preset] as Dictionary).duplicate()
		var saved: Variant = cfg.get_value(CONFIG_SECTION, "settings", null)
		if typeof(saved) == TYPE_DICTIONARY:
			for k in (saved as Dictionary).keys():
				if settings.has(k):
					settings[k] = (saved as Dictionary)[k]
	else:
		current_preset = _detect_default_preset()
		settings = (PRESETS[current_preset] as Dictionary).duplicate()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	# Загружаем существующий файл, чтобы не потерять чужие секции.
	cfg.load(CONFIG_PATH)
	cfg.set_value(CONFIG_SECTION, "preset", int(current_preset))
	cfg.set_value(CONFIG_SECTION, "settings", settings)
	cfg.set_value(AUDIO_SECTION, "music_volume", music_volume)
	cfg.set_value(AUDIO_SECTION, "sfx_volume", sfx_volume)
	cfg.save(CONFIG_PATH)


func _detect_default_preset() -> Preset:
	if OS.has_feature("mobile"):
		return Preset.LOW

	if OS.get_name() == "Web" and DisplayServer.is_touchscreen_available():
		return Preset.LOW

	var cores: int = OS.get_processor_count()
	var mem_mb: int = 0
	var mem_info: Dictionary = OS.get_memory_info()
	if mem_info.has("physical"):
		mem_mb = int(mem_info["physical"]) / (1024 * 1024)
	if cores <= 2 or (mem_mb > 0 and mem_mb < 3000):
		return Preset.VERY_LOW
	if cores <= 4:
		return Preset.MEDIUM
	return Preset.HIGH
