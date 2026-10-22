extends CharacterBody2D

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

const SKINS_PATH := "res://resources/skins/"

@export var current_skin: String = "red_rectangle"

func _ready() -> void:
	apply_skin(current_skin)

func apply_skin(skin_name: String) -> void:
	var path := SKINS_PATH + skin_name + ".tres"

	if not ResourceLoader.exists(path):
		push_warning("Skin not found: %s" % path)
		return

	# هذا السطر سيعمل الآن بعد فصل السكريبت
	var res: SkinResource = load(path) as SkinResource
	
	if res == null or res.skin == null:
		push_warning("Invalid skin resource or skin is null: %s" % path)
		return

	$skin.texture = res.skin
	current_skin = skin_name

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()
