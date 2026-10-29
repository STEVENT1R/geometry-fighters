extends Node2D

@onready var attacker: CharacterBody2D = $Attacker
@onready var target: CharacterBody2D = $Target


func _ready() -> void:
	attacker.display_name = "SWORD TEST"
	attacker.current_skin = "red_rectangle"
	attacker.ownership_initialized = true
	attacker.is_local_player = false
	attacker.network_attack_sequence = 1

	target.display_name = "TARGET"
	target.current_skin = "purple_rectangle"
	target.ownership_initialized = true
	target.is_local_player = false

	await get_tree().create_timer(0.225).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("res://sword_combat_preview.png")
	get_tree().quit()
