extends RefCounted
class_name Localization
## Регистрация переводов RU/EN и хелперы нормализации локали.

const SUPPORTED_LOCALES: Array[String] = ["ru", "en"]
const DEFAULT_LOCALE: String = "ru"

const EN_TRANSLATIONS := {
	# ============ Меню ============
	"УНИЧТОЖАЙ КАМНИ. ПРОКАЧИВАЙСЯ. ВЫЖИВАЙ.": "SMASH ROCKS. LEVEL UP. SURVIVE.",
	"ИГРАТЬ": "PLAY",
	"ИГРАТЬ (СЮЖЕТ ПРОЙДЕН)": "PLAY (STORY COMPLETED)",
	"ИГРАТЬ — УРОВЕНЬ %d": "PLAY — LEVEL %d",
	"ПРОЙДЕНО": "COMPLETED",
	"ЗАГРУЗКА…": "LOADING…",
	"БЕСКОНЕЧНЫЙ РЕЖИМ": "ENDLESS MODE",
	"БЕСКОНЕЧНЫЙ РЕЖИМ (пройдите сюжет)": "ENDLESS MODE (complete the story)",
	"НАСТРОЙКИ": "SETTINGS",
	"СМЕНИТЬ ЯЗЫК(РУССКИЙ)": "CHANGE LANGUAGE (RUSSIAN)",
	"ЯЗЫК: РУССКИЙ": "LANGUAGE: RUSSIAN",
	"ЯЗЫК: ENGLISH": "LANGUAGE: ENGLISH",
	"Текущий язык: Русский.": "Current language: Russian.",
	"Текущий язык: English.": "Current language: English.",

	# ============ Настройки графики ============
	"НАСТРОЙКИ ГРАФИКИ": "GRAPHICS SETTINGS",
	"Пресет": "Preset",
	"Очень низкое": "Very Low",
	"Низкое": "Low",
	"Среднее": "Medium",
	"Высокое": "High",
	"Ограничение FPS": "FPS Limit",
	"Без ограничения": "Unlimited",
	"Вертикальная синхронизация": "VSync",
	"Эффекты частиц": "Particle Effects",
	"Всплывающие числа урона": "Floating Damage Numbers",
	"Тряска камней при ударе": "Rock Shake on Hit",
	"Динамическое освещение": "Dynamic Lighting",
	"Свечение": "Glow",
	"ЗАКРЫТЬ": "CLOSE",

	# ============ Настройки звука ============
	"ЗВУК": "SOUND",
	"Музыка": "Music",
	"Звуки": "Sound Effects",

	# ============ Управление (мобильные) ============
	"УПРАВЛЕНИЕ": "CONTROLS",
	"Способ управления": "Control scheme",
	"Касание (как на ПК)": "Touch (like on PC)",
	"Джойстик": "Joystick",

	# ============ HUD ============
	"Монет: %s (+%s%%)": "Coins: %s (+%s%%)",
	"Урон: %s": "Damage: %s",
	"Осталось камней: %d": "Rocks left: %d",
	"Уровень %d": "Level %d",
	"Уровень %d — БОСС": "Level %d — BOSS",
	"РЕРОЛЛ (%d)": "REROLL (%d)",
	"В МЕНЮ": "MENU",

	# ============ Экран завершения уровня ============
	"Уровень пройден!": "Level Complete!",
	"Камней уничтожено:": "Rocks destroyed:",
	"Монет получено:": "Money earned:",
	"ПРОДОЛЖИТЬ": "CONTINUE",

	# ============ Экран апгрейда ============
	"ВЫБРАТЬ УЛУЧШЕНИЕ": "CHOOSE AN UPGRADE",
	"ПРОПУСТИТЬ": "SKIP",

	# ============ Экран поражения ============
	"ВЫ ПРОИГРАЛИ": "YOU LOST",
	"ЗАНОВО": "RETRY",
	"УЛУЧШЕНИЕ (ОСЛАБЛЕННОЕ)": "WEAKENED UPGRADE",

	# ============ Редкости карточек ============
	"Обычный": "Common",
	"Редкий": "Rare",
	"Эпический": "Epic",
	"Легендарный": "Legendary",

	# ============ Баффы ============
	"УРОН": "DAMAGE",
	"ШАНС КРИТ. УДАРА": "CRIT CHANCE",
	"УРОН КРИТ. УДАРА": "CRIT DAMAGE",
	"БОГАТСТВО": "FORTUNE",
	"ЗДОРОВЬЕ": "HEALTH",
	"БРОНЯ": "ARMOR",
	"ВАМПИРИЗМ": "LIFESTEAL",
	"УКЛОНЕНИЕ": "DODGE",
	"РЕГЕНЕРАЦИЯ": "REGEN",
	"СКОРОСТЬ": "SPEED",

	# ============ Скиллы ============
	"ВТОРОЕ ДЫХАНИЕ": "SECOND WIND",
	"ШИПЫ": "THORNS",
	"ЦЕПНАЯ РЕАКЦИЯ": "CHAIN REACTION",
	"ЖАДНОСТЬ": "GREED",
	"СКИЛЛ": "SKILL",
	"Один раз за игру смертельный урон оставляет вас в живых с 30% здоровья": "Once per game, lethal damage leaves you alive with 30% health",
	"20% урона от ожившего камня возвращается ему же при попадании": "20% of damage from a living rock is reflected back on hit",
	"25% шанс, что разрушенный камень взорвётся и заденет соседние": "25% chance a destroyed rock explodes and damages nearby rocks",
	"+1 монета за каждый разрушенный камень (не зависит от богатства)": "+1 coin for each destroyed rock (not affected by fortune)",

	# ============ Цена ============
	"Цена: %d": "Cost: %d",

	# ============ Описания апгрейдов ============
	"+%s%% К УРОНУ": "+%s%% DAMAGE",
	"+%s%% К ШАНСУ КРИТ. УДАРА": "+%s%% CRIT CHANCE",
	"+%s%% К УРОНУ КРИТ. УДАРА": "+%s%% CRIT DAMAGE",
	"+%s%% К КОЛИЧЕСТВУ ПОЛУЧАЕМЫХ МОНЕТ": "+%s%% COIN GAIN",
	"+%s%% К ЗДОРОВЬЮ ИГРОКА": "+%s%% MAX HEALTH",
	"+%s%% К БРОНЕ (снижение получаемого урона)": "+%s%% ARMOR (damage reduction)",
	"+%s%% ВАМПИРИЗМА (лечение от нанесённого урона)": "+%s%% LIFESTEAL (heal from damage dealt)",
	"+%s%% К ШАНСУ УКЛОНЕНИЯ": "+%s%% DODGE CHANCE",
	"+%s%% К СИЛЕ РЕГЕНЕРАЦИИ": "+%s%% REGEN",
	"+%s%% К СКОРОСТИ ПЕРЕДВИЖЕНИЯ": "+%s%% MOVE SPEED",
}

static func register_all() -> void:
	var ru := Translation.new()
	ru.locale = "ru"
	for key in EN_TRANSLATIONS:
		ru.add_message(key, key)
	TranslationServer.add_translation(ru)

	var en := Translation.new()
	en.locale = "en"
	for key in EN_TRANSLATIONS:
		en.add_message(key, EN_TRANSLATIONS[key])
	TranslationServer.add_translation(en)

static func is_supported(code: String) -> bool:
	return code in SUPPORTED_LOCALES

## "ru-RU" -> "ru", "en_US" -> "en", "eng" -> "en", "rus" -> "ru".
static func normalize(raw: String) -> String:
	if raw.is_empty():
		return ""
	var s: String = raw.to_lower().strip_edges()

	match s:
		"eng":
			return "en"
		"rus":
			return "ru"

	var cut: int = -1
	var d: int = s.find("-")
	var u: int = s.find("_")
	if d != -1 and (u == -1 or d < u):
		cut = d
	elif u != -1:
		cut = u
	if cut != -1:
		s = s.substr(0, cut)
	return s if is_supported(s) else ""
