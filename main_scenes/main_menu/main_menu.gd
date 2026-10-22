extends Control



func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://main_scenes/multiplayer/multiplayer.tscn")
