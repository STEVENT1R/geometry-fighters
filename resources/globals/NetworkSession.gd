
extends Node

var player_ids: Array[int] = []
var selected_skin: String = "red_rectangle"


func _ready() -> void:
	GDSync.client_joined.connect(_on_client_joined)
	GDSync.client_left.connect(_on_client_left)
	GDSync.lobby_joined.connect(_on_lobby_joined)


func _on_lobby_joined(_lobby_name: String) -> void:
	player_ids.clear()

	_add_player(GDSync.get_client_id())
	GDSync.player_set_data("Skin", selected_skin)

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
	if GDSync.is_active():
		GDSync.player_set_data("Skin", selected_skin)
	return true
