
extends CharacterBody2D

signal died(player: CharacterBody2D)
signal health_changed(current_health: int, maximum_health: int)

# ═══════════════════════════════════════
# Movement Constants
# ═══════════════════════════════════════

const SPEED: float = 350.0
const JUMP_VELOCITY: float = -550.0
const SKINS_PATH: String = "res://resources/skins/"

const ACCELERATION: float = 3500.0
const AIR_ACCELERATION: float = 2000.0

# ═══════════════════════════════════════
# Jump Settings
# ═══════════════════════════════════════

@export var max_jumps: int = 2
var jumps_made: int = 0

@export var coyote_time_max: float = 0.15
var coyote_time_left: float = 0.0

# ═══════════════════════════════════════
# Wall Settings
# ═══════════════════════════════════════

@export var wall_slide_speed: float = 80.0
@export var wall_stick_time: float = 1.5
@export var wall_jump_force: Vector2 = Vector2(400.0, -550.0)

var wall_time_left: float = 0.0
var wall_normal: float = 0.0
var is_wall_sliding: bool = false

var _last_wall_normal: float = 0.0
var _wall_contact_timer: float = 0.0

# ═══════════════════════════════════════
# Player / Network Settings
# ═══════════════════════════════════════

@export var current_skin: String = "red_rectangle"
var _applied_skin: String = ""
var display_name: String = "Player"
var _applied_display_name: String = ""

@export_group("Death")
@export var kill_zone_y: float = 1500.0
var is_dead: bool = false
var _applied_death_state: bool = false

@export_storage var owner_client_id: int = -1
@export_storage var initial_spawn_position: Vector2 = Vector2.ZERO
var ownership_initialized: bool = false
var is_local_player: bool = false
var camera_tracking_enabled: bool = true

var network_flip_h: bool = false
var network_animation: String = "idle"
var network_attack_sequence: int = 0

@export_group("Sword Combat")
@export var max_health: int = 100
@export var sword_damage: int = 25
@export var sword_knockback: Vector2 = Vector2(520.0, -260.0)
@export var sword_attack_duration: float = 0.46
@export var sword_combo_window: float = 0.34
@export var finisher_damage_multiplier: float = 1.45
@export var finisher_knockback_multiplier: float = 1.35
var health: int = 100

const SWORD_IDLE_ANGLE: float = 35.0
const SWORD_WINDUP_END: float = 0.26
const SWORD_ACTIVE_END: float = 0.60
const SWORD_COMBO_COUNT: int = 3

var _attack_time: float = 0.0
var _attack_active: bool = false
var _attack_can_damage: bool = false
var _attack_facing_left: bool = false
var _attack_serial: int = 0
var _seen_attack_sequence: int = 0
var _hit_targets: Dictionary = {}
var _hit_flash_time: float = 0.0
var _combo_step: int = 0
var _queued_combo_attacks: int = 0
var _combo_reset_left: float = 0.0

# ═══════════════════════════════════════
# Nodes
# ═══════════════════════════════════════

@onready var movement_animation: AnimationPlayer = $movement
@onready var skin_sprite: Sprite2D = $skin
@onready var first_hand: Sprite2D = $first_hand
@onready var second_hand: Sprite2D = $second_hand
@onready var player_camera: Camera2D = $Camera2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var name_label: Label = $name
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var sword_sprite: Sprite2D = $WeaponPivot/Sword
@onready var weapon_hand: Sprite2D = $WeaponPivot/GripHand
@onready var sword_hitbox: Area2D = $WeaponPivot/SwordHitbox
@onready var sword_tip: Marker2D = $WeaponPivot/SwordTip
@onready var sword_trail: Line2D = $SwordTrail

# ═══════════════════════════════════════
# Initialization
# ═══════════════════════════════════════

func _ready() -> void:
	apply_skin(current_skin)
	_apply_display_name()
	health = max_health
	GDSync.expose_func(_receive_sword_hit)

	var jump_anim: Animation = movement_animation.get_animation("jump")

	if jump_anim:
		jump_anim.loop_mode = Animation.LOOP_NONE

	_apply_flip(false)
	_reset_sword_pose()

	player_camera.enabled = false



func _multiplayer_ready() -> void:
	# GD-Sync calls this only after the replicated starting properties have
	# been applied, so owner ID and spawn position are already available.
	_initialize_network()


func _initialize_network() -> void:
	if not is_inside_tree():
		return

	if owner_client_id == -1:
		push_warning(
			"[Player] Missing owner ID for " + str(name)
		)
		return

	# NodeInstantiator does not replicate position changes made while spawning.
	# The spawner sends this explicit value as part of the starting properties.
	global_position = initial_spawn_position
	apply_skin(current_skin)

	# Ownership can arrive just before or just after the replicated player.
	# Wait briefly so the synchronizer never starts with the wrong authority.
	var owner_wait_frames: int = 0
	while (
		GDSync.get_gdsync_owner(self) != owner_client_id
		and owner_wait_frames < 60
	):
		owner_wait_frames += 1
		await get_tree().process_frame

	if GDSync.get_gdsync_owner(self) != owner_client_id:
		push_error(
			"[Player] Ownership mismatch for %s: expected %s, got %s"
			% [
				get_path(),
				owner_client_id,
				GDSync.get_gdsync_owner(self),
			]
		)
		return

	is_local_player = (
		owner_client_id == GDSync.get_client_id()
	)

	ownership_initialized = true

	var shared_camera_exists: bool = (
		get_tree().get_first_node_in_group("game_camera") != null
	)
	player_camera.enabled = is_local_player and not shared_camera_exists

	if player_camera.enabled:
		player_camera.make_current()

	print(
		"[Player] Local ID: ", GDSync.get_client_id(),
		" | Player ID: ", owner_client_id,
		" | Local: ", is_local_player,
		" | GDSync Owner: ", GDSync.is_gdsync_owner(self)
	)


func set_camera_tracking_enabled(enabled: bool) -> void:
	# Death/respawn systems can call this instead of knowing about GameCam.
	camera_tracking_enabled = enabled


func die() -> void:
	if is_dead:
		return
	is_dead = true
	camera_tracking_enabled = false
	velocity = Vector2.ZERO
	_cancel_sword_attack()
	_apply_death_state()


func respawn_at(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	is_dead = false
	health = max_health
	health_changed.emit(health, max_health)
	camera_tracking_enabled = true
	_apply_death_state()


func _apply_death_state() -> void:
	var was_dead: bool = _applied_death_state
	_applied_death_state = is_dead
	visible = not is_dead
	collision_shape.set_deferred("disabled", is_dead)

	if is_dead:
		movement_animation.stop()
		player_camera.enabled = false
		if not was_dead:
			died.emit(self)
	elif ownership_initialized:
		var shared_camera_exists: bool = (
			get_tree().get_first_node_in_group("game_camera") != null
		)
		player_camera.enabled = is_local_player and not shared_camera_exists
		if player_camera.enabled:
			player_camera.make_current()


# ═══════════════════════════════════════
# Visual Synchronization
# ═══════════════════════════════════════

func _process(delta: float) -> void:
	if not ownership_initialized:
		return

	if current_skin != _applied_skin:
		apply_skin(current_skin)
	if display_name != _applied_display_name:
		_apply_display_name()

	if is_dead != _applied_death_state:
		_apply_death_state()

	if not is_local_player and network_attack_sequence != _seen_attack_sequence:
		_seen_attack_sequence = network_attack_sequence
		var remote_combo_step: int = clampi(
			network_attack_sequence % 10,
			1,
			SWORD_COMBO_COUNT
		)
		_begin_sword_attack(false, remote_combo_step)

	_update_sword_combat(delta)
	_update_hit_feedback(delta)

	if is_local_player:
		return

	_apply_flip(network_flip_h)

	if network_animation != "":
		_play_animation(network_animation)


func _apply_flip(flip: bool) -> void:
	skin_sprite.flip_h = flip
	first_hand.flip_h = flip
	second_hand.flip_h = flip
	# Mirror the swing angle instead of scaling the pivot. Scaling a vertical
	# sword mirrors its artwork, but leaves the rotated attack arc unchanged.
	weapon_pivot.scale = Vector2.ONE
	sword_sprite.flip_h = flip
	weapon_hand.flip_h = flip
	# The animated grip replaces the hand holding the sword.
	first_hand.visible = flip
	second_hand.visible = not flip


func _play_animation(
	anim_name: String,
	blend_time: float = 0.15
) -> void:
	if not movement_animation.has_animation(anim_name):
		return

	if movement_animation.current_animation != anim_name:
		movement_animation.play(anim_name, blend_time)


func change_animation(
	anim_name: String,
	blend_time: float = 0.15
) -> void:
	_play_animation(anim_name, blend_time)

	if is_local_player:
		network_animation = anim_name


# ═══════════════════════════════════════
# Skin System
# ═══════════════════════════════════════

func apply_skin(skin_name: String) -> void:
	var path: String = SKINS_PATH + skin_name + ".tres"

	if not ResourceLoader.exists(path):
		push_warning("Skin not found: %s" % path)
		return

	var res: SkinResource = load(path) as SkinResource

	if res == null or res.skin == null:
		push_warning("Invalid skin resource: %s" % path)
		return

	skin_sprite.texture = res.skin

	if res.hand:
		first_hand.texture = res.hand
		second_hand.texture = res.hand
		weapon_hand.texture = res.hand

	current_skin = skin_name
	_applied_skin = skin_name


func _apply_display_name() -> void:
	name_label.text = display_name
	_applied_display_name = display_name


# Sword Combat

func _queue_sword_attack() -> void:
	if is_dead:
		return

	if _attack_active:
		var remaining_attacks: int = SWORD_COMBO_COUNT - _combo_step
		_queued_combo_attacks = mini(
			_queued_combo_attacks + 1,
			remaining_attacks
		)
		return

	if _combo_reset_left > 0.0 and _combo_step < SWORD_COMBO_COUNT:
		_combo_step += 1
	else:
		_combo_step = 1

	_begin_sword_attack(true, _combo_step)


func _begin_sword_attack(
	from_local_input: bool = true,
	combo_step: int = 1
) -> void:
	if is_dead:
		return
	if from_local_input and _attack_active:
		return

	_combo_step = clampi(combo_step, 1, SWORD_COMBO_COUNT)
	_combo_reset_left = 0.0
	_attack_facing_left = network_flip_h
	_attack_active = true
	_attack_can_damage = false
	_attack_time = 0.0
	_hit_targets.clear()
	sword_trail.clear_points()
	sword_trail.modulate.a = 0.0

	if from_local_input:
		_attack_serial += 1
		network_attack_sequence = _attack_serial * 10 + _combo_step
		_seen_attack_sequence = network_attack_sequence


func _cancel_sword_attack() -> void:
	_attack_active = false
	_attack_can_damage = false
	_attack_time = 0.0
	_combo_step = 0
	_queued_combo_attacks = 0
	_combo_reset_left = 0.0
	_hit_targets.clear()
	sword_trail.clear_points()
	_reset_sword_pose()


func _reset_sword_pose() -> void:
	if not is_instance_valid(weapon_pivot):
		return
	var facing_sign: float = -1.0 if network_flip_h else 1.0
	weapon_pivot.rotation = deg_to_rad(SWORD_IDLE_ANGLE * facing_sign)
	weapon_pivot.position = _weapon_hand_position()
	weapon_hand.rotation = deg_to_rad(
		-SWORD_IDLE_ANGLE * 0.22 * facing_sign
	)


func _weapon_facing_left() -> bool:
	return _attack_facing_left if _attack_active else network_flip_h


func _weapon_hand_position() -> Vector2:
	return second_hand.position if _weapon_facing_left() else first_hand.position


func _smoothstep(value: float) -> float:
	var clamped: float = clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


func _combo_angles() -> Vector3:
	match _combo_step:
		2:
			return Vector3(SWORD_IDLE_ANGLE, 118.0, -82.0)
		3:
			return Vector3(SWORD_IDLE_ANGLE, -142.0, 128.0)
		_:
			return Vector3(SWORD_IDLE_ANGLE, -78.0, 112.0)


func _combo_hand_offsets() -> Array[Vector2]:
	match _combo_step:
		2:
			return [Vector2(10.0, -8.0), Vector2(-16.0, 8.0)]
		3:
			return [Vector2(-14.0, -18.0), Vector2(22.0, 15.0)]
		_:
			return [Vector2(-10.0, -7.0), Vector2(16.0, 9.0)]


func _current_attack_duration() -> float:
	match _combo_step:
		2:
			return sword_attack_duration * 0.92
		3:
			return sword_attack_duration * 1.20
		_:
			return sword_attack_duration


func _update_sword_combat(delta: float) -> void:
	var base_position: Vector2 = _weapon_hand_position()
	var facing_left: bool = _weapon_facing_left()
	var facing_sign: float = -1.0 if facing_left else 1.0

	if not _attack_active:
		if _combo_reset_left > 0.0:
			_combo_reset_left = maxf(_combo_reset_left - delta, 0.0)
			if _combo_reset_left <= 0.0:
				_combo_step = 0
				_queued_combo_attacks = 0

		weapon_pivot.position = base_position
		weapon_pivot.rotation = lerp_angle(
			weapon_pivot.rotation,
			deg_to_rad(SWORD_IDLE_ANGLE * facing_sign),
			1.0 - exp(-18.0 * delta)
		)
		weapon_hand.rotation = lerp_angle(
			weapon_hand.rotation,
			deg_to_rad(-SWORD_IDLE_ANGLE * 0.22 * facing_sign),
			1.0 - exp(-18.0 * delta)
		)
		sword_trail.modulate.a = move_toward(
			sword_trail.modulate.a,
			0.0,
			delta * 5.0
		)
		if sword_trail.modulate.a <= 0.01:
			sword_trail.clear_points()
		return

	_attack_time += delta
	var progress: float = clampf(
		_attack_time / maxf(_current_attack_duration(), 0.01),
		0.0,
		1.0
	)
	var combo_angles: Vector3 = _combo_angles()
	var combo_offsets: Array[Vector2] = _combo_hand_offsets()
	var start_angle: float = combo_angles.x
	var windup_angle: float = combo_angles.y
	var follow_through_angle: float = combo_angles.z
	var windup_offset: Vector2 = combo_offsets[0]
	var follow_through_offset: Vector2 = combo_offsets[1]
	var angle_degrees: float
	var hand_offset: Vector2

	if progress < SWORD_WINDUP_END:
		var phase: float = _smoothstep(progress / SWORD_WINDUP_END)
		angle_degrees = lerpf(
			start_angle,
			windup_angle,
			phase
		)
		hand_offset = windup_offset * phase
		_attack_can_damage = false
	elif progress < SWORD_ACTIVE_END:
		var phase: float = _smoothstep(
			(progress - SWORD_WINDUP_END)
			/ (SWORD_ACTIVE_END - SWORD_WINDUP_END)
		)
		angle_degrees = lerpf(
			windup_angle,
			follow_through_angle,
			phase
		)
		hand_offset = windup_offset.lerp(follow_through_offset, phase)
		_attack_can_damage = phase > 0.12 and phase < 0.92
	else:
		var phase: float = _smoothstep(
			(progress - SWORD_ACTIVE_END)
			/ (1.0 - SWORD_ACTIVE_END)
		)
		angle_degrees = lerpf(
			follow_through_angle,
			SWORD_IDLE_ANGLE,
			phase
		)
		hand_offset = follow_through_offset.lerp(Vector2.ZERO, phase)
		_attack_can_damage = false

	# WeaponPivot's children are mirrored for left-facing attacks. Mirror the
	# procedural hand travel too, otherwise the grip moves away from the body.
	if facing_left:
		hand_offset.x *= -1.0

	weapon_pivot.position = base_position + hand_offset
	weapon_pivot.rotation = deg_to_rad(angle_degrees * facing_sign)
	weapon_hand.rotation = deg_to_rad(
		-angle_degrees * 0.22 * facing_sign
	)

	if _attack_can_damage:
		_update_sword_trail()
		if is_local_player:
			_check_sword_hits()
	else:
		sword_trail.modulate.a = move_toward(
			sword_trail.modulate.a,
			0.0,
			delta * 2.8
		)

	if progress >= 1.0:
		_attack_active = false
		_attack_can_damage = false
		_combo_reset_left = sword_combo_window

		if is_local_player and _queued_combo_attacks > 0 and _combo_step < SWORD_COMBO_COUNT:
			_queued_combo_attacks -= 1
			_combo_step += 1
			_begin_sword_attack(true, _combo_step)
		elif _combo_step >= SWORD_COMBO_COUNT:
			_queued_combo_attacks = 0


func _update_sword_trail() -> void:
	sword_trail.modulate.a = 0.72
	sword_trail.add_point(to_local(sword_tip.global_position))
	while sword_trail.get_point_count() > 8:
		sword_trail.remove_point(0)


func _check_sword_hits() -> void:
	for body: Node2D in sword_hitbox.get_overlapping_bodies():
		if body == self or not body.has_method("_receive_sword_hit"):
			continue

		var target_key: int = body.get_instance_id()
		if _hit_targets.has(target_key):
			continue
		_hit_targets[target_key] = true

		var direction: float = -1.0 if _attack_facing_left else 1.0
		var damage: int = sword_damage
		var knockback_multiplier: float = 1.0
		if _combo_step == SWORD_COMBO_COUNT:
			damage = roundi(sword_damage * finisher_damage_multiplier)
			knockback_multiplier = finisher_knockback_multiplier
		var knockback := Vector2(
			sword_knockback.x * direction * knockback_multiplier,
			sword_knockback.y * knockback_multiplier
		)
		var target_owner: int = body.get("owner_client_id")

		if target_owner == GDSync.get_client_id():
			body.call(
				"_receive_sword_hit",
				owner_client_id,
				damage,
				knockback,
				false
			)
		elif target_owner != -1:
			GDSync.call_func_on(
				target_owner,
				Callable(body, "_receive_sword_hit"),
				owner_client_id,
				damage,
				knockback,
				true
			)


func _receive_sword_hit(
	attacker_client_id: int,
	damage: int,
	knockback: Vector2,
	validate_sender: bool = true
) -> void:
	if not is_local_player or is_dead:
		return

	if validate_sender:
		var sender_id: int = GDSync.get_sender_id()
		if sender_id != attacker_client_id:
			return

	health = maxi(health - maxi(damage, 0), 0)
	velocity = knockback
	_hit_flash_time = 0.13
	health_changed.emit(health, max_health)

	if health <= 0:
		die()


func _update_hit_feedback(delta: float) -> void:
	if _hit_flash_time > 0.0:
		_hit_flash_time -= delta
		modulate = Color(1.0, 0.48, 0.48, 1.0)
	else:
		modulate = Color.WHITE


# ═══════════════════════════════════════
# Physics
# ═══════════════════════════════════════

func _physics_process(delta: float) -> void:
	if not ownership_initialized:
		return

	# Only the owning client processes movement.
	if not is_local_player or is_dead:
		return

	var direction: float = Input.get_axis(
		"ui_left",
		"ui_right"
	)

	if Input.is_action_just_pressed("attack"):
		_queue_sword_attack()

	# ─────────────────────────────────────
	# 1. Gravity
	# ─────────────────────────────────────

	if not is_on_floor():
		velocity += get_gravity() * delta
		coyote_time_left -= delta
	else:
		coyote_time_left = coyote_time_max
		jumps_made = 0
		wall_time_left = 0.0
		is_wall_sliding = false

	# ─────────────────────────────────────
	# 2. Wall Slide
	# ─────────────────────────────────────

	is_wall_sliding = false

	if not is_on_floor() and is_on_wall() and velocity.y >= 0.0:
		wall_normal = get_wall_normal().x

		if direction != 0.0 and sign(direction) == sign(wall_normal):
			wall_time_left = 0.0
		else:
			if wall_time_left <= 0.0:
				wall_time_left = wall_stick_time

			if wall_time_left > 0.0:
				is_wall_sliding = true
				wall_time_left -= delta

				velocity.y = min(
					velocity.y,
					wall_slide_speed
				)

				velocity.x = 0.0

	if not is_on_wall():
		wall_time_left = 0.0

	# ─────────────────────────────────────
	# 3. Jump / Double Jump / Wall Jump
	# ─────────────────────────────────────

	if Input.is_action_just_pressed("ui_accept"):

		if is_wall_sliding and wall_time_left > 0.0:
			velocity.x = wall_normal * wall_jump_force.x
			velocity.y = wall_jump_force.y

			wall_time_left = 0.0
			is_wall_sliding = false
			jumps_made = 1

			change_animation("jump", 0.05)

		else:
			var can_ground_jump: bool = (
				is_on_floor()
				or coyote_time_left > 0.0
			)

			if can_ground_jump and jumps_made == 0:
				jumps_made = 1
				coyote_time_left = 0.0
				velocity.y = JUMP_VELOCITY

				change_animation("jump", 0.05)

			elif jumps_made < max_jumps:
				jumps_made += 1
				velocity.y = JUMP_VELOCITY * 0.7

				change_animation("jump", 0.05)

	# ─────────────────────────────────────
	# 4. Horizontal Movement
	# ─────────────────────────────────────

	if not is_wall_sliding:
		var target_speed: float = direction * SPEED

		if is_on_floor():
			velocity.x = move_toward(
				velocity.x,
				target_speed,
				ACCELERATION * delta
			)
		else:
			velocity.x = move_toward(
				velocity.x,
				target_speed,
				AIR_ACCELERATION * delta
			)

	# ─────────────────────────────────────
	# 5. Flip Direction
	# ─────────────────────────────────────

	if is_on_wall():
		_last_wall_normal = get_wall_normal().x
		_wall_contact_timer = 0.1
	elif _wall_contact_timer > 0.0:
		_wall_contact_timer -= delta

	var flip: bool = network_flip_h

	if _attack_active:
		# Keep the entire attack on its starting side. Turning input is applied
		# after recovery instead of snapping the sword through the body.
		flip = _attack_facing_left
	elif _wall_contact_timer > 0.0:
		flip = _last_wall_normal < 0.0
	elif direction != 0.0:
		flip = direction < 0.0

	network_flip_h = flip
	_apply_flip(flip)

	# ─────────────────────────────────────
	# 6. Animations
	# ─────────────────────────────────────

	if not is_on_floor() and not is_wall_sliding:
		pass
	elif is_on_floor():
		if jumps_made == 0:
			if abs(velocity.x) > 50.0:
				if velocity.x > 0.0:
					change_animation("move_right", 0.1)
				else:
					change_animation("move_left", 0.1)
			else:
				change_animation("idle", 0.1)

	# ─────────────────────────────────────
	# 7. Apply Movement
	# ─────────────────────────────────────

	move_and_slide()

	if global_position.y > kill_zone_y:
		die()
