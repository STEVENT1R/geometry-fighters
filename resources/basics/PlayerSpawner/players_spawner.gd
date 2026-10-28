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

	var ids: Array[int] = NetworkSession.player_ids.duplicate()
	ids.sort()

	if ids.is_empty():
		push_error("[Spawner] No players found!")
		return

	started = true

	print("[Spawner] Players: ", ids)

	for i in range(ids.size()):
		var client_id: int = ids[i]
		var marker: Marker2D = spawn_points[i % spawn_points.size()]

		_spawn_player(client_id, marker)


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

	player.name = str(client_id)
	player.global_position = marker.global_position

	GDSync.set_gdsync_owner(player, client_id)

	spawned_players[client_id] = player

	print(
		"[Spawner] Spawned: ", client_id,
		" | Owner: ", GDSync.is_gdsync_owner(player),
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
