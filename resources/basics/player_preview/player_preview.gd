extends Node2D

const SKINS_PATH: String = "res://resources/skins/"

@onready var skin_sprite: Sprite2D = $skin
@onready var first_hand: Sprite2D = $first_hand
@onready var second_hand: Sprite2D = $second_hand
@onready var movement_animation: AnimationPlayer = $movement

var displayed_skin: String = ""


func _ready() -> void:
	if movement_animation.has_animation("idle"):
		movement_animation.play("idle")


func show_skin(skin_name: String) -> bool:
	var resource_path: String = SKINS_PATH + skin_name + ".tres"
	if not ResourceLoader.exists(resource_path):
		push_warning("Preview skin not found: %s" % resource_path)
		return false

	var skin_resource: SkinResource = load(resource_path) as SkinResource
	if skin_resource == null or skin_resource.skin == null:
		push_warning("Invalid preview skin: %s" % resource_path)
		return false

	skin_sprite.texture = skin_resource.skin
	if skin_resource.hand != null:
		first_hand.texture = skin_resource.hand
		second_hand.texture = skin_resource.hand

	displayed_skin = skin_name
	return true
