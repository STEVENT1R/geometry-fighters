
extends Node

const PROFILE_PATH: String = "user://player_profile.cfg"
const PROFILE_SECTION: String = "player"

var player_ids: Array[int] = []
var selected_skin: String = "red_rectangle"
var selected_name: String = "Player"


func _ready() -> void:
	_load_profile()
	GDSync.client_joined.connect(_on_client_joined)
	GDSync.client_left.connect(_on_client_left)
	GDSync.lobby_joined.connect(_on_lobby_joined)


func _on_lobby_joined(_lobby_name: String) -> void:
	player_ids.clear()

	_add_player(GDSync.get_client_id())
	GDSync.player_set_data("Skin", selected_skin)
	GDSync.player_set_data("DisplayName", selected_name)
	GDSync.player_set_username(selected_name)

	print("[NetworkSession] Joined lobby")
	print("[NetworkSession] Players: ", player_ids)


func _on_client_joined(client_id: int) -> void:
	_add_player(client_id)

	print("[NetworkSession] Player joined: ", client_id)
	print("[NetworkSession] Players: ", player_ids)


func _on_client_left(client_id: int) -> void:
	player_ids.erase(client_id)

	print("[NetworkSession] Player left: ", client_id)
	print("[NetworkSession] Players: ", player_ids)


func _add_player(client_id: int) -> void:
	if not player_ids.has(client_id):
		player_ids.append(client_id)
		player_ids.sort()


func set_selected_skin(skin_name: String) -> bool:
	var skin_path: String = "res://resources/skins/" + skin_name + ".tres"
	if not ResourceLoader.exists(skin_path):
		push_warning("Cannot select missing skin: %s" % skin_name)
		return false

	selected_skin = skin_name
	_save_profile()
	if GDSync.is_active():
		GDSync.player_set_data("Skin", selected_skin)
	return true


func validate_player_name(player_name: String) -> String:
	var clean_name: String = player_name.strip_edges()
	if clean_name.length() < 2:
		return "Name must be at least 2 characters"
	if clean_name.length() > 16:
		return "Name cannot exceed 16 characters"

	for index in range(clean_name.length()):
		if clean_name.unicode_at(index) < 32:
			return "Name contains invalid characters"
	return ""


func set_player_name(player_name: String) -> bool:
	var clean_name: String = player_name.strip_edges()
	var validation_error: String = validate_player_name(clean_name)
	if validation_error != "":
		push_warning(validation_error)
		return false

	selected_name = clean_name
	_save_profile()
	if GDSync.is_active():
		GDSync.player_set_data("DisplayName", selected_name)
		GDSync.player_set_username(selected_name)
	return true


func _load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) != OK:
		return

	var stored_skin: String = str(
		config.get_value(PROFILE_SECTION, "skin", selected_skin)
	)
	var stored_name: String = str(
		config.get_value(PROFILE_SECTION, "name", selected_name)
	)

	if ResourceLoader.exists("res://resources/skins/" + stored_skin + ".tres"):
		selected_skin = stored_skin
	if validate_player_name(stored_name) == "":
		selected_name = stored_name


func _save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value(PROFILE_SECTION, "skin", selected_skin)
	config.set_value(PROFILE_SECTION, "name", selected_name)
	var error: Error = config.save(PROFILE_PATH)
	if error != OK:
		push_warning("Could not save player profile: %s" % error_string(error))
