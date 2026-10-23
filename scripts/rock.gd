extends StaticBody2D
class_name Rock

signal rock_destroyed

@export var shake_strength: float = 8.0
@export var shake_duration: float = 0.4
@export var shake_count: int = 8

var original_position: Vector2
var current_tween: Tween

const default_texture = preload("res://sprites/rock.png")
const alive_texture = preload("res://sprites/rock_enemy.png")
const crit_icon_texture = preload("res://sprites/crit_icon.png")
const damage_font = preload("res://fonts/montserrat.bold.ttf")

const type_rock = ["default", "strong", "big", "alive_chaser", "alive_thrower", "alive_tank"]
const rock_hp = [25, 30, 37, 40, 40, 95]
const rock_size = [2.0, 2.25, 2.5, 2.75, 2.6, 3.3]
const rock_reward = [1.2, 1.8, 3.5, 5.5, 6.5, 10.0]

var alive_chaser_index: int = type_rock.find("alive_chaser")
var alive_thrower_index: int = type_rock.find("alive_thrower")
var alive_tank_index: int = type_rock.find("alive_tank")
var alive_type_indices: Array = [alive_chaser_index, alive_thrower_index, alive_tank_index]

const alive_chase_speed      = [0.0, 0.0, 0.0, 70.0, 45.0, 38.0]
const alive_detection_range  = [0.0, 0.0, 0.0, 260.0, 320.0, 230.0]
const alive_attack_range     = [0.0, 0.0, 0.0, 60.0, 230.0, 70.0]
const alive_keep_distance    = [0.0, 0.0, 0.0, 0.0, 150.0, 0.0]
const alive_attack_interval  = [0.0, 0.0, 0.0, 1.0, 1.7, 1.3]
const alive_attack_damage    = [0.0, 0.0, 0.0, 3.5, 4.0, 6.5]
const alive_projectile_speed = [0.0, 0.0, 0.0, 0.0, 260.0, 0.0]

var forced_type: int = -1
var type
@onready var damage_particle = $DamageRock
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var health_bar: TextureProgressBar = get_node_or_null("HealthBar") as TextureProgressBar

@onready var _crit_particles = get_node_or_null("CritRock")
@onready var _crit_sparkles = get_node_or_null("CritRockSparkles")
@onready var _break_particles = get_node_or_null("BreakRock")

var player_ref: Node2D = null
var attack_cooldown: float = 0.0

var _ai_accum: float = 0.0

# --- Damage text object pool ---
# ВАЖНО (оптимизация памяти):
#   Раньше пул хранил Array[Node] со ССЫЛКАМИ на контейнеры всплывающих
#   чисел. Эти контейнеры - дети current_scene, поэтому при любом
#   change_scene_to_file() они освобождаются вместе со сценой, а
#   статический массив (он живёт вне жизненного цикла сцены) продолжал
#   держать ссылки. На следующей сцене _get_damage_text_container()
#   мог достать из пула уже мёртвый Node и упасть на get_child(1).
#   Плюс сам факт хранения ссылок в статике мешал корректной уборке.
#
#   Теперь храним WeakRef: после освобождения узла get_ref() вернёт null,
#   а pop-цикл молча выкидывает такие записи. Пул самовосстанавливается,
#   утечки нет, крэшей нет.
static var _damage_text_pool: Array[WeakRef] = []
static var _damage_text_pool_max: int = 20


class ThrownRock extends Node2D:
	var velocity: Vector2 = Vector2.ZERO
	var damage: float = 0.0
	var life_left: float = 2.5
	var hit_radius: float = 24.0
	var target: Node2D = null
	var source_rock: Node = null

	# Кэшируем текстуру один раз на класс: preload в _ready() каждый раз
	# — это лишняя работа на каждый снаряд. Хотя preload кэшируется
	# движком, держим ссылку в const и переиспользуем.
	const _projectile_texture: Texture2D = preload("res://sprites/rock_enemy.png")

	func _ready() -> void:
		var sprite := TextureRect.new()
		sprite.texture = _projectile_texture
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.custom_minimum_size = Vector2(48, 48)
		sprite.pivot = Vector2(24, 24)
		sprite.modulate = Color(0.55, 0.75, 1.0)
		add_child(sprite)

	func _physics_process(delta: float) -> void:
		life_left -= delta
		if life_left <= 0.0:
			queue_free()
			return

		global_position += velocity * delta

		if is_instance_valid(target):
			if global_position.distance_to(target.global_position) <= hit_radius:
				if target.has_method("take_damage"):
					var attacker_ref: Node = source_rock if is_instance_valid(source_rock) else null
					target.take_damage(damage, attacker_ref)
				queue_free()

const EXPLOSIVE_KILL_CHANCE: float = 0.25
const EXPLOSIVE_KILL_RADIUS: float = 140.0
const EXPLOSIVE_KILL_DAMAGE_FRACTION: float = 0.5
const MONEY_MAGNET_FLAT_BONUS: float = 1.0

@export var max_health: float = 10
var health: float


func _ready() -> void:
	original_position = position

	type = forced_type if forced_type != -1 else Main.weighted_random_index(Main.current_type_weights)

	var hp_multiplier: float = (1.0 + Main.current_level * 0.07) * Main.level_hp_multiplier_extra
	max_health = (rock_hp[type] + Main.current_level * 2.0) * hp_multiplier
	scale = Vector2(rock_size[type], rock_size[type])

	health = max_health

	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health

	if sprite:
		if type == alive_chaser_index:
			sprite.texture = alive_texture
			sprite.modulate = Color(1, 1, 1)
		elif type == alive_thrower_index:
			sprite.texture = alive_texture
			sprite.modulate = Color(0.55, 0.75, 1.0)
		elif type == alive_tank_index:
			sprite.texture = alive_texture
			sprite.modulate = Color(0.55, 0.55, 0.6)
		else:
			sprite.texture = default_texture

	if type in alive_type_indices:
		player_ref = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	if type not in alive_type_indices or not Main.game_active:
		return

	var tick_hz: float = float(GraphicsSettings.get_value("ai_tick_hz", 0.0))
	if tick_hz > 0.0:
		_ai_accum += delta
		var interval: float = 1.0 / tick_hz
		if _ai_accum < interval:
			return
		delta = _ai_accum
		_ai_accum = 0.0

	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	if not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(player_ref):
			return

	var distance: float = global_position.distance_to(player_ref.global_position)
	var is_shaking: bool = current_tween and current_tween.is_valid()

	if type == alive_thrower_index:
		if distance < alive_keep_distance[type]:
			if not is_shaking:
				var away_dir: Vector2 = player_ref.global_position.direction_to(global_position)
				position += away_dir * alive_chase_speed[type] * delta
				original_position = position
		elif distance <= alive_attack_range[type]:
			_try_attack()
		elif distance <= alive_detection_range[type]:
			if not is_shaking:
				var approach_dir: Vector2 = global_position.direction_to(player_ref.global_position)
				position += approach_dir * alive_chase_speed[type] * delta
				original_position = position
	else:
		if distance <= alive_attack_range[type]:
			_try_attack()
		elif distance <= alive_detection_range[type]:
			if not is_shaking:
				var direction: Vector2 = global_position.direction_to(player_ref.global_position)
				position += direction * alive_chase_speed[type] * delta
				original_position = position


func notify_player_contact() -> void:
	if type in alive_type_indices:
		_try_attack()

func _try_attack() -> void:
	if attack_cooldown > 0.0:
		return
	_attack_player()
	attack_cooldown = alive_attack_interval[type]

func _attack_player() -> void:
	var scaled_damage: float = alive_attack_damage[type] * (1.0 + (Main.current_level - 1) * 0.05)

	if type == alive_thrower_index:
		_throw_rock_at_player(scaled_damage)
	elif player_ref.has_method("take_damage"):
		player_ref.take_damage(scaled_damage, self)

	shake()

func _throw_rock_at_player(damage: float) -> void:
	if not is_instance_valid(player_ref):
		return

	var projectile := ThrownRock.new()
	projectile.damage = damage
	projectile.target = player_ref
	projectile.source_rock = self

	var direction: Vector2 = global_position.direction_to(player_ref.global_position)
	projectile.velocity = direction * alive_projectile_speed[type]

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position


func damage_text(amount: float, is_crit: bool = false) -> void:
	if not bool(GraphicsSettings.get_value("damage_numbers", true)):
		return

	var container: Node = _get_damage_text_container()
	if container == null:
		return

	var label: Label = container.get_child(1) as Label
	if is_crit:
		var icon: TextureRect = container.get_child(0) as TextureRect
		icon.visible = true
		label.add_theme_font_size_override("font_size", 32)
		label.add_theme_color_override("font_color", Color.RED)
	else:
		if container.get_child_count() > 0:
			var icon: TextureRect = container.get_child(0) as TextureRect
			icon.visible = false
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", Color.WHITE)

	label.text = str(snappedf(amount, 0.1))

	container.global_position = global_position + Vector2(randf_range(-15, 15), -20)
	container.visible = true
	container.modulate = Color(1, 1, 1, 1)

	var tween := container.create_tween()
	tween.set_parallel(true)
	tween.tween_property(container, "global_position:y", container.global_position.y - 40, 0.8)
	tween.tween_property(container, "modulate:a", 0.0, 0.8).set_delay(0.2)
	tween.tween_callback(_return_damage_text_container.bind(container))


func take_damage(amount: float) -> void:
	AudioManager.play_stone_hit()

	var particles_on: bool = bool(GraphicsSettings.get_value("particles_enabled", true))
	var shake_on: bool = bool(GraphicsSettings.get_value("shake_enabled", true))
	var numbers_on: bool = bool(GraphicsSettings.get_value("damage_numbers", true))

	var is_crit: bool = randf_range(0.00, 1.00) <= Main.chance_crit
	if is_crit:
		var crit_damage: float = amount * Main.crit_multiplier
		health -= crit_damage
		health = max(health, 0)
		if numbers_on:
			damage_text(crit_damage, true)
		if particles_on:
			if _crit_particles:
				_crit_particles.restart()
				_crit_particles.emitting = true
			if _crit_sparkles:
				_crit_sparkles.restart()
				_crit_sparkles.emitting = true
	else:
		health -= amount
		health = max(health, 0)
		if particles_on and damage_particle:
			damage_particle.restart()
			damage_particle.emitting = true
		if numbers_on:
			damage_text(amount, false)

	if health_bar:
		health_bar.value = health

	if shake_on:
		shake()

	if health <= 0:
		if _break_particles:
			remove_child(_break_particles)
			get_parent().add_child(_break_particles)
			_break_particles.global_position = global_position
			_break_particles.emitting = true

			var lifetime: float = 1.0
			if "lifetime" in _break_particles:
				lifetime = float(_break_particles.lifetime)
			var timer = get_tree().create_timer(lifetime)
			timer.timeout.connect(_break_particles.queue_free)

		rock_destroyed.emit()
		queue_free()

		var level_bonus_multiplier: float = 1.0 + (Main.current_level - 1) * 0.20
		var base_reward: float = rock_reward[type] * Main.money_multiplier \
			* Main.level_money_multiplier_extra * level_bonus_multiplier
		var additional_money: float = base_reward * randf_range(0.0, 0.5)
		var total_reward: float = base_reward + additional_money

		Main.getted_money += snappedf(total_reward, 0.1)
		Main.money += total_reward
		Main.left_rocks -= 1
		Main.destroyed_rocks += 1

		if Main.has_skill("money_magnet"):
			Main.getted_money += MONEY_MAGNET_FLAT_BONUS
			Main.money += MONEY_MAGNET_FLAT_BONUS

		if Main.has_skill("explosive_kill") and randf() <= EXPLOSIVE_KILL_CHANCE:
			_trigger_chain_explosion()


func _trigger_chain_explosion() -> void:
	var splash_damage: float = Main.damage * EXPLOSIVE_KILL_DAMAGE_FRACTION
	for other_rock in Main.spawned_rocks:
		if not is_instance_valid(other_rock) or other_rock == self:
			continue
		if other_rock.global_position.distance_to(global_position) <= EXPLOSIVE_KILL_RADIUS:
			if other_rock.has_method("take_damage"):
				other_rock.take_damage(splash_damage)


func shake():
	if current_tween and current_tween.is_valid():
		current_tween.kill()
		position = original_position

	current_tween = create_tween()
	var step_time = shake_duration / shake_count

	for i in shake_count:
		var strength = shake_strength * (1.0 - float(i) / shake_count)
		var offset = Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)
		current_tween.tween_property(self, "position", original_position + offset, step_time) \
			.set_trans(Tween.TRANS_SINE)
	current_tween.tween_property(self, "position", original_position, step_time)


# --- Damage text object pool implementation ---

func _get_damage_text_container() -> Node:
	# WeakRef-пул: если контейнер был освобождён (например, при смене сцены),
	# get_ref() вернёт null — просто выкидываем запись и идём дальше.
	while _damage_text_pool.size() > 0:
		var ref: WeakRef = _damage_text_pool.pop_back()
		if ref == null:
			continue
		var pooled: Object = ref.get_ref()
		if pooled != null and is_instance_valid(pooled):
			return pooled as Node

	var scene := get_tree().current_scene
	if scene == null:
		return null

	var container := HBoxContainer.new()
	container.z_index = 100
	container.add_theme_constant_override("separation", 4)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_process_mode(Node.PROCESS_MODE_ALWAYS)

	var icon := TextureRect.new()
	icon.texture = Rock.crit_icon_texture
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(28, 28)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.visible = false
	container.add_child(icon)

	var label := Label.new()
	label.z_index = 100
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_override("font", Rock.damage_font)
	container.add_child(label)

	scene.add_child(container)
	container.visible = false
	return container


static func _return_damage_text_container(container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	container.visible = false
	if _damage_text_pool.size() < _damage_text_pool_max:
		_damage_text_pool.append(weakref(container))
	else:
		container.queue_free()
