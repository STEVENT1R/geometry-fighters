extends Control





func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://main_scenes/main_menu/main_menu.tscn")
