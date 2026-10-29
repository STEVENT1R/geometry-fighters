extends Node

@export var base_player: PackedScene
@export var spawn_points: Array[Marker2D] = []

var spawned_players: Dictionary = {}
var started: bool = false


func _ready() -> void:
	GDSync.client_left.connect(_on_client_left)
	call_deferred("_spawn_all_players")


func _spawn_all_players() -> void:
	if started or not GDSync.is_host():
		return

	if base_player == null or spawn_points.is_empty():
		push_error("[Spawner] Missing player scene or spawn points!")
		return

	# Read the authoritative lobby membership at the moment the synchronized
	# scene is ready instead of depending on a separately maintained cache.
	var ids: Array[int] = []
	for lobby_client_id in GDSync.lobby_get_all_clients():
		ids.append(int(lobby_client_id))
	ids.sort()

	if ids.is_empty():
		push_error("[Spawner] No players found!")
		return

	started = true

	print("[Spawner] Players: ", ids)

	for i in range(ids.size()):
		var client_id: int = ids[i]
		var marker: Marker2D = spawn_points[i % spawn_points.size()]

		await _spawn_player(client_id, marker)


func _spawn_player(client_id: int, marker: Marker2D) -> void:
	if spawned_players.has(client_id):
		return

	var player: Node2D = GDSync.multiplayer_instantiate(
		base_player,
		get_parent(),
		true,
		PackedStringArray(),
		true
	)

	if player == null:
		push_error("[Spawner] Failed to spawn player!")
		return

	# Keep GD-Sync's generated name unchanged. Ownership messages use the
	# NodePath, so renaming here can make the owner request target a path that
	# does not exist yet on remote clients.
	player.set("owner_client_id", client_id)
	player.set("initial_spawn_position", marker.global_position)
	player.set(
		"current_skin",
		str(GDSync.player_get_data(client_id, "Skin", "red_rectangle"))
	)
	player.global_position = marker.global_position
	spawned_players[client_id] = player

	# multiplayer_instantiate sends its remote spawn with call_deferred().
	# Assigning ownership in the same frame sends the owner request first, and
	# remote clients discard it before the player exists. Waiting one frame
	# guarantees the reliable spawn request is queued before ownership.
	await get_tree().process_frame

	if not is_instance_valid(player) or not player.is_inside_tree():
		spawned_players.erase(client_id)
		return

	GDSync.set_gdsync_owner(player, client_id)

	if GDSync.get_gdsync_owner(player) != client_id:
		push_error(
			"[Spawner] Failed to assign owner %s to %s"
			% [client_id, player.get_path()]
		)
		spawned_players.erase(client_id)
		GDSync.multiplayer_queue_free(player)
		return

	print(
		"[Spawner] Spawned: ", client_id,
		" | Owner ID: ", GDSync.get_gdsync_owner(player),
		" | Node: ", player.name,
		" | Position: ", player.global_position
	)


func _on_client_left(client_id: int) -> void:
	if not GDSync.is_host():
		return

	if not spawned_players.has(client_id):
		return

	var player: Node = spawned_players[client_id]

	if is_instance_valid(player):
		GDSync.multiplayer_queue_free(player)

	spawned_players.erase(client_id)
