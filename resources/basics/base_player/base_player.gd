extends CharacterBody2D

# --- الثوابت (Constants) ---
const SPEED = 350.0
const JUMP_VELOCITY = -550.0
const SKINS_PATH := "res://resources/skins/"

const ACCELERATION = 3500.0       
const AIR_ACCELERATION = 2000.0   

# --- إعدادات القفز ---
@export var max_jumps: int = 2
var jumps_made: int = 0

# --- إعدادات وقت السماح بالنطة بعد السقوط (Coyote Time) ---
@export var coyote_time_max: float = 0.15 
var coyote_time_left: float = 0.0

# --- ✅ إعدادات التعلق بالحيط (Wall Slide / Wall Jump) ---
@export var wall_slide_speed: float = 80.0      # سرعة السقوط البطيئة على الحيطة
@export var wall_stick_time: float = 1.5        # مدة السماح بالقفز من الحيطة
@export var wall_jump_force: Vector2 = Vector2(400.0, -550.0)  # (دفع أفقي، دفع عمودي)

var wall_time_left: float = 0.0                 # العداد المتبقي
var wall_normal: float = 0.0                    # اتجاه الحيطة (-1 يسار، 1 يمين)
var is_wall_sliding: bool = false

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
		wall_time_left = 0.0
		is_wall_sliding = false

	# --- ✅ 2. منطق التعلق بالحيط ---
	is_wall_sliding = false
	
	if not is_on_floor() and is_on_wall() and velocity.y >= 0.0:
		# ناخد اتجاه الحيطة (لو الحيطة على الشمال، الnormal هيكون (1,0)، والعكس)
		wall_normal = get_wall_normal().x
		
		# ✅ نشحن العداد لو لسه مش شغال (أول لمسة للحيطة)
		if wall_time_left <= 0.0:
			wall_time_left = wall_stick_time
		
		# ✅ طول ما العداد شغال، اللاعب ملزوق
		if wall_time_left > 0.0:
			is_wall_sliding = true
			wall_time_left -= delta
			
			# تثبيت اللاعب على الحيطة (سقوط بطيء بدل السقوط الحر)
			velocity.y = min(velocity.y, wall_slide_speed)
			
			# ✅ تصفير سرعة X عشان يبقى ملزوق ومش بيتحرك أفقيًا
			velocity.x = 0.0
			
			# ✅ يخلي اللاعب يبص في اتجاه الحيطة (اختياري)
			skin_sprite.flip_h = wall_normal < 0.0
			first_hand.flip_h = wall_normal < 0.0
			second_hand.flip_h = wall_normal < 0.0
	
	# لو اللاعب بعد عن الحيطة، صفّر العداد
	if not is_on_wall():
		wall_time_left = 0.0

	# --- 3. استقبال أمر القفز (عادي + دابل جامب + قفز من الحيطة) ---
	if Input.is_action_just_pressed("ui_accept"):
		
		# ✅ أولوية القفز من الحيطة
		if is_wall_sliding and wall_time_left > 0.0:
			# القفز في الاتجاه المعاكس للحيطة + لفوق
			velocity.x = wall_normal * wall_jump_force.x
			velocity.y = wall_jump_force.y
			
			# تصفير العداد عشان ميقدرش يقفز تاني من نفس الحيطة
			wall_time_left = 0.0
			is_wall_sliding = false
			
			# ✅ نصفر الدابل جامب عشان يقدر يستخدمه بعد قفزة الحيطة
			jumps_made = 1
			
			change_animation("jump", 0.05)
		
		else:
			var can_ground_jump = is_on_floor() or coyote_time_left > 0.0
			
			if can_ground_jump and jumps_made == 0:
				jumps_made = 1
				coyote_time_left = 0.0
				velocity.y = JUMP_VELOCITY
				change_animation("jump", 0.05)
				
			elif jumps_made < max_jumps:
				jumps_made += 1
				velocity.y = JUMP_VELOCITY * 0.7
				movement_animation.play("jump", 0.05)

	# --- 4. الحركة مع التسارع وبدون احتكاك ---
	var direction := Input.get_axis("ui_left", "ui_right")
	
	# ✅ لو ملزوق بالحيطة، منتحكمش في velocity.x (التصقير فوق كفاية)
	if not is_wall_sliding:
		var target_speed = direction * SPEED
		
		if is_on_floor():
			velocity.x = move_toward(velocity.x, target_speed, ACCELERATION * delta)
		else:
			velocity.x = move_toward(velocity.x, target_speed, AIR_ACCELERATION * delta)

		# --- 5. قلب الاتجاه (Flipping) ---
		if direction != 0:
			var flip = direction < 0
			skin_sprite.flip_h = flip
			first_hand.flip_h = flip
			second_hand.flip_h = flip

	# --- 6. منطق الأنيميشن ---
	if not is_on_floor() and not is_wall_sliding:
		pass 
	elif is_on_floor():
		if jumps_made == 0: 
			if abs(velocity.x) > 50.0: 
				if velocity.x > 0:
					change_animation("move_right", 0.1)
				else:
					change_animation("move_left", 0.1)
			else:
				change_animation("idle", 0.1)

	move_and_slide()
