extends Camera2D

# --- إعدادات النعومة ---
@export_group("Camera Smoothing")
@export var position_smoothness: float = 5.0 # كل ما زاد الرقم، الكاميرا تتحرك أسرع
@export var zoom_smoothness: float = 3.0

# --- إعدادات الليميت (0 = مفتوح / لا يوجد ليميت) ---
@export_group("Camera Limits (0 = Unlimited)")
@export var custom_limit_left: int = 0:
	set(value):
		custom_limit_left = value
		limit_left = value if value != 0 else -10000000 # رقم ضخم جداً يعني مفتوح

@export var custom_limit_right: int = 0:
	set(value):
		custom_limit_right = value
		limit_right = value if value != 0 else 10000000

@export var custom_limit_top: int = 0:
	set(value):
		custom_limit_top = value
		limit_top = value if value != 0 else -10000000

@export var custom_limit_bottom: int = 0:
	set(value):
		custom_limit_bottom = value
		limit_bottom = value if value != 0 else 10000000

# --- إعدادات الـ Zoom (Brawlhalla Style) ---
@export_group("Camera Zoom")
@export var min_zoom: Vector2 = Vector2(1.0, 1.0) # أقصى تقريب
@export var max_zoom: Vector2 = Vector2(0.5, 0.5) # أقصى تباعد (تصغير)
@export var zoom_margin: float = 300.0 # مسافة إضافية حوالين اللاعبين قبل ما الكاميرا تبعد
@export var zoom_speed_scale: float = 500.0 # سرعة استجابة الـ Zoom

var target_position: Vector2
var target_zoom: Vector2


func _ready() -> void:
	# تفعيل خصائص الكاميرا المهمة
	position_smoothing_enabled = false # هنعمل النعومة يدوياً بالكود
	make_current()


func _physics_process(delta: float) -> void:
	# 1. جلب كل اللاعبين الموجودين في الـ group
	var players = get_tree().get_nodes_in_group("players")
	
	# لو مفيش لاعبين، الكاميرا متعملش حاجة
	if players.size() == 0:
		return

	# 2. حساب متوسط موقع اللاعبين (المركز)
	var average_pos = Vector2.ZERO
	for player in players:
		average_pos += player.global_position
	average_pos /= players.size()

	# 3. حساب أقصى مسافة بين اللاعبين (عشان الـ Zoom)
	var max_distance = 0.0
	if players.size() > 1:
		for i in range(players.size()):
			for j in range(i + 1, players.size()):
				var dist = players[i].global_position.distance_to(players[j].global_position)
				if dist > max_distance:
					max_distance = dist
	
	# حساب الـ Zoom المطلوب بناءً على المسافة
	# كل ما المسافة تزيد، الـ Zoom يقل (الكاميرا تبعد)
	var zoom_factor = clamp(max_distance / zoom_speed_scale, 0.0, 1.0)
	target_zoom = min_zoom.lerp(max_zoom, zoom_factor)

	# 4. تطبيق النعومة (Lerp)
	# نستخدم معادلة الأس عشان النعومة تكون ثابتة على كل الـ Framerates
	var pos_weight = 1.0 - exp(-position_smoothness * delta)
	var zoom_weight = 1.0 - exp(-zoom_smoothness * delta)

	global_position = global_position.lerp(average_pos, pos_weight)
	zoom = zoom.lerp(target_zoom, zoom_weight)
