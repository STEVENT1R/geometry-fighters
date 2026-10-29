
extends CharacterBody2D

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

@export_storage var owner_client_id: int = -1
@export_storage var initial_spawn_position: Vector2 = Vector2.ZERO
var ownership_initialized: bool = false
var is_local_player: bool = false
var camera_tracking_enabled: bool = true

var network_flip_h: bool = false
var network_animation: String = "idle"

# ═══════════════════════════════════════
# Nodes
# ═══════════════════════════════════════

@onready var movement_animation: AnimationPlayer = $movement
@onready var skin_sprite: Sprite2D = $skin
@onready var first_hand: Sprite2D = $first_hand
@onready var second_hand: Sprite2D = $second_hand
@onready var player_camera: Camera2D = $Camera2D

# ═══════════════════════════════════════
# Initialization
# ═══════════════════════════════════════

func _ready() -> void:
	apply_skin(current_skin)

	var jump_anim: Animation = movement_animation.get_animation("jump")

	if jump_anim:
		jump_anim.loop_mode = Animation.LOOP_NONE

	_apply_flip(false)

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


# ═══════════════════════════════════════
# Visual Synchronization
# ═══════════════════════════════════════

func _process(_delta: float) -> void:
	if not ownership_initialized:
		return

	if current_skin != _applied_skin:
		apply_skin(current_skin)

	if is_local_player:
		return

	_apply_flip(network_flip_h)

	if network_animation != "":
		_play_animation(network_animation)


func _apply_flip(flip: bool) -> void:
	skin_sprite.flip_h = flip
	first_hand.flip_h = flip
	second_hand.flip_h = flip


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

	current_skin = skin_name
	_applied_skin = skin_name


# ═══════════════════════════════════════
# Physics
# ═══════════════════════════════════════

func _physics_process(delta: float) -> void:
	if not ownership_initialized:
		return

	# Only the owning client processes movement.
	if not is_local_player:
		return

	var direction: float = Input.get_axis(
		"ui_left",
		"ui_right"
	)

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

	if _wall_contact_timer > 0.0:
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
