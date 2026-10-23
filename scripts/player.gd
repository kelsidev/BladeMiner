extends CharacterBody2D

signal player_died

@export var base_move_speed: float = 300.0
@export var rotation_speed: float = 10.0
@export var stop_distance: float = 5.0

@export var knockback_force: float = 100.0
@export var knockback_duration: float = 0.5
@export var base_damage_cooldown: float = 0.5

const THORNS_REFLECT_PERCENT: float = 0.20

@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar: TextureProgressBar = $HealthBar

var move_speed: float = 300.0
var damage_cooldown: float = 0.5

var knockback_velocity: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0
var damage_timers: Dictionary = {}

var health: float
var max_health: float

func _ready() -> void:
	add_to_group("player")
	Main.level_changed.connect(_on_level_changed)
	_sync_stats()

func _on_level_changed(_level_num: int) -> void:
	_sync_stats()

func _sync_stats() -> void:
	max_health = Main.max_health
	health = max_health

	move_speed = base_move_speed * Main.move_speed_mult
	damage_cooldown = base_damage_cooldown

	health_bar.max_value = max_health
	health_bar.value = health

func _physics_process(delta: float) -> void:
	var move_dir: Vector2 = _get_move_direction()

	if Main.game_active:
		if knockback_timer > 0.0:
			knockback_timer -= delta
			velocity = knockback_velocity
		else:
			velocity = move_dir * move_speed

		move_and_slide()

		_update_damage_cooldowns(delta)
		_handle_collisions()

		sprite.rotation += rotation_speed * delta


func _get_move_direction() -> Vector2:
	if MobileInput.is_mobile:
		return MobileInput.move_vector

	var mouse_pos: Vector2 = get_global_mouse_position()
	var distance: float = global_position.distance_to(mouse_pos)
	if distance <= stop_distance:
		return Vector2.ZERO
	return global_position.direction_to(mouse_pos)


func take_damage(amount: float, attacker: Node = null) -> void:
	if not Main.game_active:
		return

	if randf() <= Main.dodge_chance:
		_flash_dodge()
		return

	var actual_damage: float = amount * (1.0 - Main.armor)

	if Main.has_skill("thorns") and attacker != null and attacker.has_method("take_damage"):
		attacker.take_damage(amount * THORNS_REFLECT_PERCENT)

	if Main.has_skill("second_wind") and not Main.second_wind_used and actual_damage >= health:
		Main.second_wind_used = true
		health = max_health * 0.3
		health_bar.value = health
		_flash_damage()
		return

	health -= actual_damage
	health = clamp(health, 0.0, max_health)
	health_bar.value = health

	_flash_damage()

	if health <= 0.0:
		_die()

func _flash_damage() -> void:
	sprite.modulate = Color(1.0, 0.35, 0.35)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.2)

func _flash_dodge() -> void:
	sprite.modulate = Color(0.6, 0.85, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.15)

func _die() -> void:
	player_died.emit()
	Main.game_active = false
	Main.player_died = true
	if YandexSDK:
		YandexSDK.stop_gameplay()

func _update_damage_cooldowns(delta: float) -> void:
	# Use a local array to avoid modifying dict during iteration
	var keys_to_remove: Array = []
	for id in damage_timers:
		damage_timers[id] -= delta
		if damage_timers[id] <= 0.0:
			keys_to_remove.append(id)
	for id in keys_to_remove:
		damage_timers.erase(id)


func _handle_collisions() -> void:
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()

		if collider == null:
			continue

		if collider.has_method("notify_player_contact"):
			collider.notify_player_contact()

		if collider.has_method("take_damage"):
			var id: int = collider.get_instance_id()
			if not damage_timers.has(id):
				var dealt_damage: float = Main.damage
				collider.take_damage(dealt_damage)
				damage_timers[id] = damage_cooldown

				if Main.lifesteal > 0.0:
					health = clamp(health + dealt_damage * Main.lifesteal, 0.0, max_health)
					health_bar.value = health

				var push_dir: Vector2 = (global_position - collision.get_position()).normalized()
				if push_dir == Vector2.ZERO:
					push_dir = -collision.get_normal()
				knockback_velocity = push_dir * knockback_force
				knockback_timer = knockback_duration


func _on_heal_timer_timeout() -> void:
	if health < max_health:
		var heal_amount: float = max_health * 0.01 * Main.regen_mult
		health = health + heal_amount
		if health > max_health:
			health = max_health
		health_bar.value = health
