extends CharacterBody2D

# --- الثوابت (Constants) ---
const SPEED = 350.0
const JUMP_VELOCITY = -400.0
const SKINS_PATH := "res://resources/skins/"

# --- إعدادات النعومة والانزلاق ---
const ACCELERATION = 1500.0     
const FRICTION = 4000.0         
const AIR_ACCELERATION = 800.0  
const AIR_FRICTION = 500.0      

# --- المتغيرات (Variables) ---
@export var current_skin: String = "red_rectangle"

var is_jumping: bool = false
var jump_force_applied: bool = false

# --- العقد (Nodes) ---
@onready var movement_animation = $movement
@onready var skin_sprite = $skin 
@onready var first_hand = $first_hand
@onready var second_hand = $second_hand


func _ready() -> void:
	apply_skin(current_skin)
	
	var jump_anim = movement_animation.get_animation("jump")
	if jump_anim:
		jump_anim.loop_mode = Animation.LOOP_NONE
		
	if skin_sprite:
		skin_sprite.flip_h = false
		first_hand.flip_h = false
		second_hand.flip_h = false


func apply_skin(skin_name: String) -> void:
	var path := SKINS_PATH + skin_name + ".tres"

	if not ResourceLoader.exists(path):
		push_warning("Skin not found: %s" % path)
		return

	var res: SkinResource = load(path) as SkinResource
	
	if res == null or res.skin == null:
		push_warning("Invalid skin resource or skin is null: %s" % path)
		return

	skin_sprite.texture = res.skin
	
	if res.hand:
		first_hand.texture = res.hand
		second_hand.texture = res.hand
		
	current_skin = skin_name


# دالة جديدة لعمل انتقال ناعم بين الأنيميشنز
func change_animation(anim_name: String, blend_time: float = 0.15) -> void:
	# بنتأكد إن الأنيميشن المطلوب مختلف عن اللي شغال حالياً عشان منقطعش الدمج
	if movement_animation.current_animation != anim_name:
		movement_animation.play(anim_name, blend_time)


func _physics_process(delta: float) -> void:
	# --- 1. الجاذبية وإعادة ضبط الحالة ---
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		if is_jumping and jump_force_applied:
			is_jumping = false
			jump_force_applied = false

	# --- 2. استقبال أمر القفز ---
	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and not is_jumping:
		is_jumping = true
		jump_force_applied = false
		# استخدمنا الدالة الجديدة هنا مع وقت دمج سريع (0.05) عشان النطة تبان فورية
		change_animation("jump", 0.05)

	# --- 3. تطبيق قوة القفز ---
	if is_jumping and not jump_force_applied:
		if movement_animation.current_animation == "jump" and movement_animation.current_animation_position >= 0.01:
			velocity.y = JUMP_VELOCITY
			jump_force_applied = true

	# --- 4. الحركة الناعمة (Smooth Movement) ---
	var direction := Input.get_axis("ui_left", "ui_right")
	var target_speed = direction * SPEED

	if is_on_floor():
		if direction != 0:
			velocity.x = move_toward(velocity.x, target_speed, ACCELERATION * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
	else:
		if direction != 0:
			velocity.x = move_toward(velocity.x, target_speed, AIR_ACCELERATION * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, AIR_FRICTION * delta)

	# --- 5. قلب الاتجاه (Flipping) ---
	if direction != 0:
		if direction > 0:
			skin_sprite.flip_h = false 
			first_hand.flip_h = false
			second_hand.flip_h = false
		elif direction < 0:
			skin_sprite.flip_h = true  
			first_hand.flip_h = true
			second_hand.flip_h = true

	# --- 6. منطق الأنيميشن ---
	if not is_on_floor():
		# في الهواء، سيب أنيميشن الـ jump شغال ومتستدعيش play كل فريم
		pass 
	else:
		if not is_jumping:
			if abs(velocity.x) > 50.0: 
				if velocity.x > 0:
					change_animation("move_right", 0.1) # وقت دمج 0.2 ثانية
				else:
					change_animation("move_left", 0.1)
			else:
				change_animation("idle", 0.1)

	move_and_slide()
