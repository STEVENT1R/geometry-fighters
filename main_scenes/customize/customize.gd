extends Control

const SKINS_DIRECTORY: String = "res://resources/skins"

@onready var next_button: TextureButton = $next
@onready var previous_button: TextureButton = $prev
@onready var equip_button: Button = $character_done
@onready var equip_text: Label = $character_done/text
@onready var preview: Node = $player_preview/player_preview
@onready var name_input: LineEdit = $name
@onready var name_done_button: Button = $name_done
@onready var name_done_text: Label = $name_done/text
@onready var status_label: Label = $status

var available_skins: Array[String] = []
var selected_index: int = 0


func _ready() -> void:
	name_input.max_length = 16
	name_input.text = NetworkSession.selected_name

	next_button.pressed.connect(_on_next_pressed)
	previous_button.pressed.connect(_on_previous_pressed)
	equip_button.pressed.connect(_on_character_done_pressed)
	name_done_button.pressed.connect(_on_name_done_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	name_input.text_changed.connect(_on_name_text_changed)

	_load_available_skins()
	_show_saved_skin()


func _load_available_skins() -> void:
	available_skins.clear()
	for file_name in DirAccess.get_files_at(SKINS_DIRECTORY):
		if file_name.get_extension().to_lower() != "tres":
			continue

		var skin_name: String = file_name.get_basename()
		var resource_path: String = SKINS_DIRECTORY + "/" + file_name
		var resource: Resource = load(resource_path)
		if resource is SkinResource and (resource as SkinResource).skin != null:
			available_skins.append(skin_name)

	available_skins.sort()
	var has_skins: bool = not available_skins.is_empty()
	next_button.disabled = not has_skins
	previous_button.disabled = not has_skins
	equip_button.disabled = not has_skins

	if not has_skins:
		_show_status("Add SkinResource files to resources/skins", true)


func _show_saved_skin() -> void:
	if available_skins.is_empty():
		return

	var saved_index: int = available_skins.find(NetworkSession.selected_skin)
	selected_index = saved_index if saved_index >= 0 else 0
	_update_preview()


func _update_preview() -> void:
	if available_skins.is_empty():
		return

	selected_index = wrapi(selected_index, 0, available_skins.size())
	var skin_name: String = available_skins[selected_index]
	preview.call("show_skin", skin_name)
	equip_text.text = (
		"Equipped" if skin_name == NetworkSession.selected_skin else "Equip"
	)


func _on_next_pressed() -> void:
	selected_index += 1
	_update_preview()


func _on_previous_pressed() -> void:
	selected_index -= 1
	_update_preview()


func _on_character_done_pressed() -> void:
	if available_skins.is_empty():
		return

	var skin_name: String = available_skins[selected_index]
	if NetworkSession.set_selected_skin(skin_name):
		equip_text.text = "Equipped"
		status_label.text = ""


func _on_name_done_pressed() -> void:
	_save_name(name_input.text)


func _on_name_submitted(player_name: String) -> void:
	_save_name(player_name)


func _on_name_text_changed(_new_text: String) -> void:
	name_done_text.modulate = Color.WHITE


func _save_name(player_name: String) -> void:
	var validation_error: String = NetworkSession.validate_player_name(player_name)
	if validation_error != "":
		_show_status(validation_error, true)
		name_input.grab_focus()
		return

	if NetworkSession.set_player_name(player_name):
		name_input.text = NetworkSession.selected_name
		name_input.release_focus()
		name_done_text.modulate = Color("00bb42ff")
		status_label.text = ""


func _show_status(message: String, is_error: bool) -> void:
	status_label.text = message
	status_label.modulate = Color("ff6b6b") if is_error else Color("8dff9b")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://main_scenes/main_menu/main_menu.tscn")
