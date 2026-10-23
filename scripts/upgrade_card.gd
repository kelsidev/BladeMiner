extends PanelContainer

signal upgrade_click

@onready var card = $"."
@onready var rarity_label = $CardMargin/CardVBox/RarityLabel
@onready var name_label = $CardMargin/CardVBox/NameLabel
@onready var desc_label = $CardMargin/CardVBox/DescriptionLabel
@onready var icon = $CardMargin/CardVBox/IconCenter/Icon
@onready var price_label = $CardMargin/CardVBox/PriceLabel

var style: StyleBoxFlat = $".".get_theme_stylebox("panel").duplicate()

var plus_damage = 8
var plus_crit_chance = 5
var plus_crit_damage = 5
var plus_money_multiplier = 10
var plus_health = 8

# ЗАМЕНА: plus_attack_speed -> plus_armor.
# Значение 6% при полном потолке 60% и diminishing_bonus_capped даёт
# ощутимую, но не мгновенную защиту: примерно 5-6 обычных карточек до потолка.
var plus_armor = 6
var plus_lifesteal = 4
var plus_dodge_chance = 4
var plus_regen = 15
var plus_move_speed = 6

# Ключи (source-строки на русском) — через tr() превращаются в EN при locale=en.
var raritys = ["Обычный", "Редкий", "Эпический", "Легендарный"]
var raritys_colors = ["#ffffff", "#53cfbd", "#cfa3e9", "#e9aa46"]
var rarity_multiplier = [1.0, 1.25, 1.5, 2.0]

# ЗАМЕНА: "attack_speed" -> "armor" в списке баффов и ярлыков.
var buffs = ["damage", "crit_chance", "crit_damage", "money_multiplier", "health", "armor", "lifesteal", "dodge_chance", "regen", "move_speed"]
var buffs_label = ["УРОН", "ШАНС КРИТ. УДАРА", "УРОН КРИТ. УДАРА", "БОГАТСТВО", "ЗДОРОВЬЕ", "БРОНЯ", "ВАМПИРИЗМ", "УКЛОНЕНИЕ", "РЕГЕНЕРАЦИЯ", "СКОРОСТЬ"]

var skills = ["second_wind", "thorns", "explosive_kill", "money_magnet"]
var skills_label = {
	"second_wind": "ВТОРОЕ ДЫХАНИЕ",
	"thorns": "ШИПЫ",
	"explosive_kill": "ЦЕПНАЯ РЕАКЦИЯ",
	"money_magnet": "ЖАДНОСТЬ",
}
var skills_desc = {
	"second_wind": "Один раз за игру смертельный урон оставляет вас в живых с 30% здоровья",
	"thorns": "20% урона от ожившего камня возвращается ему же при попадании",
	"explosive_kill": "25% шанс, что разрушенный камень взорвётся и заденет соседние",
	"money_magnet": "+1 монета за каждый разрушенный камень (не зависит от богатства)",
}
var skills_price = {
	"second_wind": 60,
	"thorns": 40,
	"explosive_kill": 45,
	"money_magnet": 35,
}
const SKILL_COLOR = "#ff6b6b"
const SKILL_CHANCE: float = 0.18

# --- Режим «после поражения» ---
# После проигрыша карточка выдаётся ослабленной (эффект × DEFEAT_EFFECT_MULT)
# и со скидкой (цена × DEFEAT_COST_MULT). Затем цена дополнительно
# ограничивается сверху текущим количеством монет — так игрок может
# воспользоваться карточкой даже при 0 монет и не застрять на уровне.
#
# Эффективность поднята с 0.30 до 0.40: при балансе до правок rock.gd
# и level.gd 5 проигрышей на боссе давали ~1.5 обычных апгрейда, чего
# категорически не хватало, чтобы пробить стену. Теперь 3-4 поражения
# подряд реально выводят из тупика. 40% при цене 30% даёт соотношение
# «эффект/монета» ≈ 1.33× от обычной карточки — это осознанная плата за
# то, что игрок теряет время и прогресс, но не превращает смерть в
# выгодный фарм.
const DEFEAT_EFFECT_MULT: float = 0.40
const DEFEAT_COST_MULT: float = 0.30

var is_skill_card: bool = false
var skill_id: String = ""

var base_prices = {
	"damage": 10,
	"crit_chance": 12,
	"crit_damage": 14,
	"money_multiplier": 15,
	"health": 8,
	# ЗАМЕНА: "attack_speed": 13 -> "armor": 13. Цена сохранена на прежнем
	# уровне: 13 монет - в одном диапазоне с dodge_chance (13) и lifesteal (12),
	# что соответствует их схожей роли "защитных" статов.
	"armor": 13,
	"lifesteal": 12,
	"dodge_chance": 13,
	"regen": 9,
	"move_speed": 7,
}

var rarity = null
var buff = null
var price: int = 0

# _process троттлинг: пересчёт достаточности денег - 6+ раз в секунду
# достаточно. Раньше update_affordability() вызывался каждый кадр,
# дергая modulate + add_theme_color_override.
var _afford_check_accum: float = 0.0
const AFFORD_CHECK_INTERVAL: float = 0.15


func _ready() -> void:
	get_tree().current_scene.get_node("Hud").reroll_signal.connect(reroll)

	Main.level_changed.connect(_on_level_changed)
	Main.language_changed.connect(_on_language_changed)
	roll()

func _on_level_changed(_level_num: int) -> void:
	roll()

func _on_language_changed(_code: String) -> void:
	_render()
	update_affordability()


# Возвращает ослабленное (или обычное) значение эффекта для конкретного
# базового значения с учётом редкости и текущего режима.
func _get_effect_value(buff_index: int, rarity_idx: int) -> float:
	var base: float
	match buff_index:
		0: base = plus_damage
		1: base = plus_crit_chance
		2: base = plus_crit_damage
		3: base = plus_money_multiplier
		4: base = plus_health
		# ЗАМЕНА: индекс 5 теперь armor (был attack_speed).
		5: base = plus_armor
		6: base = plus_lifesteal
		7: base = plus_dodge_chance
		8: base = plus_regen
		9: base = plus_move_speed
		_: base = 0.0

	var v: float = base * rarity_multiplier[rarity_idx]
	if Main.defeat_mode:
		v *= DEFEAT_EFFECT_MULT
	return v


# Рандомизация состояния карточки. Не трогает тексты — за них
# отвечает _render(), чтобы смена языка не переролливала карточку.
func roll():
	var available_skills: Array = []
	for s in skills:
		if not Main.has_skill(s):
			available_skills.append(s)

	is_skill_card = available_skills.size() > 0 and randf() < SKILL_CHANCE

	var cost_mult: float = DEFEAT_COST_MULT if Main.defeat_mode else 1.0

	if is_skill_card:
		skill_id = available_skills[randi_range(0, available_skills.size() - 1)]
		rarity = -1
		buff = -1
		price = int(round(skills_price[skill_id] * cost_mult))
		style.border_color = Color(SKILL_COLOR)
		$".".add_theme_stylebox_override("panel", style)

		print("SKILL: " + skill_id)
		print("price: " + str(price))
	else:
		skill_id = ""
		rarity = randi_range(0, 3)
		buff = randi_range(0, buffs.size() - 1)
		price = int(round(base_prices[buffs[buff]] * rarity_multiplier[rarity] * cost_mult))
		style.border_color = Color(raritys_colors[rarity])
		$".".add_theme_stylebox_override("panel", style)

		print(raritys[rarity])
		print(buffs[buff])
		print("price: " + str(price))

	# В режиме поражения гарантируем доступность: цена не больше, чем
	# монет у игрока. Если монет 0 — карточка бесплатна. Это тот самый
	# «страховочный клапан», который не даёт игроку застрять навсегда.
	# Злоупотребить этим нельзя: чтобы получить ещё одну карточку,
	# нужно снова проиграть (потеряв время и не продвинувшись).
	if Main.defeat_mode:
		var affordable: int = max(0, int(Main.money))
		if price > affordable:
			price = affordable

	_render()
	update_affordability()


# Отдельно от roll(), чтобы при смене языка просто перерисовать тексты.
func _render() -> void:
	if is_skill_card:
		name_label.text = tr(skills_label[skill_id])
		desc_label.text = tr(skills_desc[skill_id])
		rarity_label.text = "[color=" + SKILL_COLOR + "]" + tr("СКИЛЛ")
		price_label.text = tr("Цена: %d") % price
	else:
		name_label.text = tr(buffs_label[buff])
		description_buff(buff, rarity)
		rarity_label.text = "[color=" + raritys_colors[rarity] + "]" + tr(raritys[rarity])
		price_label.text = tr("Цена: %d") % price


func reroll():
	roll()
	print("reroll")

func _process(delta: float) -> void:
	_afford_check_accum += delta
	if _afford_check_accum < AFFORD_CHECK_INTERVAL:
		return
	_afford_check_accum = 0.0

	if not is_visible_in_tree():
		return
	update_affordability()


func update_affordability() -> void:
	var can_afford = Main.money >= price

	if can_afford:
		modulate = Color(1, 1, 1, 1)
		price_label.add_theme_color_override("font_color", Color(0.9411765, 0.7411765, 0.16862746, 1))
	else:
		modulate = Color(0.7, 0.7, 0.7, 1)
		price_label.add_theme_color_override("font_color", Color(0.9137255, 0.3529412, 0.3529412, 1))

func _shake_not_enough_money() -> void:
	var tween := create_tween()
	var base_pos := position
	tween.tween_property(self, "position", base_pos + Vector2(8, 0), 0.04)
	tween.tween_property(self, "position", base_pos - Vector2(8, 0), 0.08)
	tween.tween_property(self, "position", base_pos, 0.04)

func description_buff(buff: int, rarity: int):
	var desc_text
	var value
	match buff:
		0:
			value = _get_effect_value(0, rarity)
			var new_dmg_mult = Main.apply_diminishing_multiplier(Main.damage_mult, value/100, Main.DAMAGE_DIMINISH_K)
			var real_gain0 = snappedf((new_dmg_mult - Main.damage_mult)*100, 0.01)
			desc_label.text = tr("+%s%% К УРОНУ") % str(real_gain0)
		1:
			value = _get_effect_value(1, rarity)
			var new_chance = Main.apply_diminishing_bonus_capped(Main.chance_crit, Main.CRIT_CHANCE_CAP, value/100)
			var real_gain = snappedf((new_chance - Main.chance_crit)*100, 0.01)
			desc_label.text = tr("+%s%% К ШАНСУ КРИТ. УДАРА") % str(real_gain)
		2:
			value = _get_effect_value(2, rarity)
			var new_crit_mult = Main.apply_diminishing_multiplier(Main.crit_multiplier, value/100, Main.CRIT_DAMAGE_DIMINISH_K)
			var real_gain2 = snappedf((new_crit_mult - Main.crit_multiplier)*100, 0.01)
			desc_label.text = tr("+%s%% К УРОНУ КРИТ. УДАРА") % str(real_gain2)
		3:
			value = _get_effect_value(3, rarity)
			var new_money_mult = Main.apply_diminishing_multiplier(Main.money_multiplier, value/100, Main.MONEY_MULT_DIMINISH_K)
			var real_gain3 = snappedf((new_money_mult - Main.money_multiplier)*100, 0.01)
			desc_label.text = tr("+%s%% К КОЛИЧЕСТВУ ПОЛУЧАЕМЫХ МОНЕТ") % str(real_gain3)
		4:
			value = _get_effect_value(4, rarity)
			var new_hp_mult = Main.apply_diminishing_multiplier(Main.health_mult, value/100, Main.HEALTH_DIMINISH_K)
			var real_gain4 = snappedf((new_hp_mult - Main.health_mult)*100, 0.01)
			desc_label.text = tr("+%s%% К ЗДОРОВЬЮ ИГРОКА") % str(real_gain4)
		5:
			# ЗАМЕНА: было "+% К СКОРОСТИ АТАКИ". Теперь броня.
			# Используем ту же diminishing_bonus_capped, что у dodge/lifesteal,
			# потому что броня - тоже доля от 0 до жёсткого потолка.
			value = _get_effect_value(5, rarity)
			var new_armor = Main.apply_diminishing_bonus_capped(Main.armor, Main.ARMOR_CAP, value/100)
			var real_gain5 = snappedf((new_armor - Main.armor)*100, 0.01)
			desc_label.text = tr("+%s%% К БРОНЕ (снижение получаемого урона)") % str(real_gain5)
		6:
			value = _get_effect_value(6, rarity)
			var new_ls = Main.apply_diminishing_bonus_capped(Main.lifesteal, Main.LIFESTEAL_CAP, value/100)
			var real_gain6 = snappedf((new_ls - Main.lifesteal)*100, 0.01)
			desc_label.text = tr("+%s%% ВАМПИРИЗМА (лечение от нанесённого урона)") % str(real_gain6)
		7:
			value = _get_effect_value(7, rarity)
			var new_dc = Main.apply_diminishing_bonus_capped(Main.dodge_chance, Main.DODGE_CHANCE_CAP, value/100)
			var real_gain7 = snappedf((new_dc - Main.dodge_chance)*100, 0.01)
			desc_label.text = tr("+%s%% К ШАНСУ УКЛОНЕНИЯ") % str(real_gain7)
		8:
			value = _get_effect_value(8, rarity)
			var new_rg = Main.apply_diminishing_multiplier(Main.regen_mult, value/100, Main.REGEN_DIMINISH_K)
			var real_gain8 = snappedf((new_rg - Main.regen_mult)*100, 0.01)
			desc_label.text = tr("+%s%% К СИЛЕ РЕГЕНЕРАЦИИ") % str(real_gain8)
		9:
			value = _get_effect_value(9, rarity)
			var new_ms = Main.apply_diminishing_multiplier(Main.move_speed_mult, value/100, Main.MOVE_SPEED_DIMINISH_K)
			var real_gain9 = snappedf((new_ms - Main.move_speed_mult)*100, 0.01)
			desc_label.text = tr("+%s%% К СКОРОСТИ ПЕРЕДВИЖЕНИЯ") % str(real_gain9)


func _on_button_pressed() -> void:
	if Main.money < price:
		_shake_not_enough_money()
		return

	Main.money -= price

	if is_skill_card:
		Main.unlock_skill(skill_id)
		print("Скилл получен: " + skill_id)
		# Скилл - необратимое изменение: сохраняем сразу же.
		Main.save_now()
		upgrade_click.emit()
		return

	var value
	match buff:
		0:
			value = _get_effect_value(0, rarity)
			var old_dmg_mult = Main.damage_mult
			Main.damage_mult = Main.apply_diminishing_multiplier(Main.damage_mult, value/100, Main.DAMAGE_DIMINISH_K)
			Main.damage = Main.base_damage * Main.damage_mult
			print("+" + str(snappedf((Main.damage_mult-old_dmg_mult)*100, 0.01)) + "% К УРОНУ (реальный прирост)\nТекущий урон: " + str(Main.damage))
		1:
			value = _get_effect_value(1, rarity)
			var old_chance = Main.chance_crit
			Main.chance_crit = Main.apply_diminishing_bonus_capped(Main.chance_crit, Main.CRIT_CHANCE_CAP, value/100)
			print("+" + str(snappedf((Main.chance_crit-old_chance)*100, 0.01)) + "% К ШАНСУ КРИТА (реальный прирост)\nТекущий шанс крита: " + str(Main.chance_crit))
		2:
			value = _get_effect_value(2, rarity)
			var old_crit_mult = Main.crit_multiplier
			Main.crit_multiplier = Main.apply_diminishing_multiplier(Main.crit_multiplier, value/100, Main.CRIT_DAMAGE_DIMINISH_K)
			print("+" + str(snappedf((Main.crit_multiplier-old_crit_mult)*100, 0.01)) + "% К КРИТ УРОНУ (реальный прирост)\nТекущий крит урон: " + str(Main.crit_multiplier))
		3:
			value = _get_effect_value(3, rarity)
			var old_money_mult = Main.money_multiplier
			Main.money_multiplier = Main.apply_diminishing_multiplier(Main.money_multiplier, value/100, Main.MONEY_MULT_DIMINISH_K)
			print("+" + str(snappedf((Main.money_multiplier-old_money_mult)*100, 0.01)) + "% К КОЛИЧЕСТВУ МОНЕТ (реальный прирост)\nТекущий money multiplier: " + str(Main.money_multiplier))
		4:
			value = _get_effect_value(4, rarity)
			var old_hp_mult = Main.health_mult
			Main.health_mult = Main.apply_diminishing_multiplier(Main.health_mult, value/100, Main.HEALTH_DIMINISH_K)
			Main.max_health = Main.base_max_health * Main.health_mult
			print("+" + str(snappedf((Main.health_mult-old_hp_mult)*100, 0.01)) + "% К ЗДОРОВЬЮ (реальный прирост)\nЗдоровье игрока: " + str(Main.max_health))
		5:
			# ЗАМЕНА: было "К СКОРОСТИ АТАКИ". Теперь броня.
			value = _get_effect_value(5, rarity)
			var old_armor = Main.armor
			Main.armor = Main.apply_diminishing_bonus_capped(Main.armor, Main.ARMOR_CAP, value/100)
			print("+" + str(snappedf((Main.armor-old_armor)*100, 0.01)) + "% К БРОНЕ (реальный прирост)\nТекущая броня: " + str(Main.armor*100) + "%")
		6:
			value = _get_effect_value(6, rarity)
			var old_ls = Main.lifesteal
			Main.lifesteal = Main.apply_diminishing_bonus_capped(Main.lifesteal, Main.LIFESTEAL_CAP, value/100)
			print("+" + str(snappedf((Main.lifesteal-old_ls)*100, 0.01)) + "% ВАМПИРИЗМА\nТекущий вампиризм: " + str(Main.lifesteal))
		7:
			value = _get_effect_value(7, rarity)
			var old_dc = Main.dodge_chance
			Main.dodge_chance = Main.apply_diminishing_bonus_capped(Main.dodge_chance, Main.DODGE_CHANCE_CAP, value/100)
			print("+" + str(snappedf((Main.dodge_chance-old_dc)*100, 0.01)) + "% К УКЛОНЕНИЮ\nТекущий шанс уклонения: " + str(Main.dodge_chance))
		8:
			value = _get_effect_value(8, rarity)
			var old_rg = Main.regen_mult
			Main.regen_mult = Main.apply_diminishing_multiplier(Main.regen_mult, value/100, Main.REGEN_DIMINISH_K)
			print("+" + str(snappedf((Main.regen_mult-old_rg)*100, 0.01)) + "% К РЕГЕНЕРАЦИИ\nТекущий множитель: " + str(Main.regen_mult))
		9:
			value = _get_effect_value(9, rarity)
			var old_ms = Main.move_speed_mult
			Main.move_speed_mult = Main.apply_diminishing_multiplier(Main.move_speed_mult, value/100, Main.MOVE_SPEED_DIMINISH_K)
			print("+" + str(snappedf((Main.move_speed_mult-old_ms)*100, 0.01)) + "% К СКОРОСТИ ПЕРЕДВИЖЕНИЯ\nТекущий множитель: " + str(Main.move_speed_mult))

	# Каждая покупка апгрейда — сохраняем немедленно.
	Main.save_now()
	upgrade_click.emit()
