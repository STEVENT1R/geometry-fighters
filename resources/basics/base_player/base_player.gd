extends CharacterBody2D

# --- الثوابت (Constants) ---
const SPEED = 350.0
const JUMP_VELOCITY = -550.0            # قوة النطة العادية
const SKINS_PATH := "res://resources/skins/"

# ✅ إعدادات التسارع (بدون احتكاك)
# التسارع ده بيستخدم للحركة وللفرملة (الوقوف)
const ACCELERATION = 3500.0       
const AIR_ACCELERATION = 2000.0   

# --- إعدادات القفز ---
@export var max_jumps: int = 2   # 2 تعني دابل جامب
var jumps_made: int = 0

# --- إعدادات وقت السماح بالنطة بعد السقوط (Coyote Time) ---
@export var coyote_time_max: float = 0.15 
var coyote_time_left: float = 0.0

# --- المتغيرات (Variables) ---
@export var current_skin: String = "red_rectangle"

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


func change_animation(anim_name: String, blend_time: float = 0.15) -> void:
	if movement_animation.current_animation != anim_name:
		movement_animation.play(anim_name, blend_time)


func _physics_process(delta: float) -> void:
	# --- 1. الجاذبية وإعادة ضبط الحالة ---
	if not is_on_floor():
		velocity += get_gravity() * delta
		coyote_time_left -= delta
	else:
		coyote_time_left = coyote_time_max
		jumps_made = 0 

	# --- 2. استقبال أمر القفز (عادي + دابل جامب) ---
	if Input.is_action_just_pressed("ui_accept"):
		var can_ground_jump = is_on_floor() or coyote_time_left > 0.0
		
		if can_ground_jump and jumps_made == 0:
			# النطة العادية
			jumps_made = 1
			coyote_time_left = 0.0
			velocity.y = JUMP_VELOCITY
			change_animation("jump", 0.05)
			
		elif jumps_made < max_jumps:
			# ✅ الدابل جامب (نص النطة العادية بالظبط)
			jumps_made += 1
			velocity.y = JUMP_VELOCITY * 0.7
			movement_animation.play("jump", 0.05)

	# --- 3. الحركة مع التسارع وبدون احتكاك ---
	var direction := Input.get_axis("ui_left", "ui_right")
	var target_speed = direction * SPEED
	
	if is_on_floor():
		# لو بيدوس على زرار، بيتسارع ناحية سرعته القصوى
		# لو مبيدوسش (direction = 0)، بيتسارع ناحية الصفر (يعني بيفرمل بنفس التسارع)
		velocity.x = move_toward(velocity.x, target_speed, ACCELERATION * delta)
	else:
		# نفس الفكرة في الهواء
		velocity.x = move_toward(velocity.x, target_speed, AIR_ACCELERATION * delta)

	# --- 4. قلب الاتجاه (Flipping) ---
	if direction != 0:
		if direction > 0:
			skin_sprite.flip_h = false 
			first_hand.flip_h = false
			second_hand.flip_h = false
		elif direction < 0:
			skin_sprite.flip_h = true  
			first_hand.flip_h = true
			second_hand.flip_h = true

	# --- 5. منطق الأنيميشن ---
	if not is_on_floor():
		pass 
	else:
		if jumps_made == 0: 
			if abs(velocity.x) > 50.0: 
				if velocity.x > 0:
					change_animation("move_right", 0.1)
				else:
					change_animation("move_left", 0.1)
			else:
				change_animation("idle", 0.1)

	move_and_slide()
