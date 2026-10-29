
extends Control

const MAX_PLAYERS: int = 4
const MIN_PLAYERS: int = 2
const GAME_SCENE: String = "res://maps/map1/map1.tscn"

@onready var main_section: Control = $main
@onready var host_section: Control = $host
@onready var client_section: Control = $client

@onready var host_button: Button = $main/host
@onready var join_button: Button = $main/join
@onready var local_games: Label = $main/local_games

@onready var host_ready: Button = $host/ready
@onready var host_ready_text: Label = $host/ready/text
@onready var host_start: Button = $host/start

@onready var client_ready: Button = $client/ready
@onready var client_ready_text: Label = $client/ready/text

@onready var connecting_screen: ColorRect = $connecting_screen
@onready var connecting_state: Label = $connecting_screen/connecting_state

var my_ready: bool = false
var in_lobby: bool = false
var ready_states: Dictionary = {}
var available_lobbies: Array = []
var current_lobby_name: String = ""
var search_timer: Timer


func _ready() -> void:
	main_section.show()
	host_section.hide()
	client_section.hide()
	connecting_screen.hide()
	host_start.hide()
	
	
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.lobbies_received.connect(_on_lobbies_received)
	GDSync.client_joined.connect(_on_client_joined)
	GDSync.client_left.connect(_on_client_left)
	GDSync.player_data_changed.connect(_on_player_data_changed)
	GDSync.host_changed.connect(_on_host_changed)

	GDSync.expose_func(_remote_start_game)

	search_timer = Timer.new()
	search_timer.wait_time = 2.0
	search_timer.timeout.connect(_search_for_lan_games)
	add_child(search_timer)
	search_timer.start()

	GDSync.start_local_multiplayer()
	_search_for_lan_games()


# ═══════════════════════════════════════
# Lobby Discovery
# ═══════════════════════════════════════

func _search_for_lan_games() -> void:
	if in_lobby or not main_section.visible:
		return

	GDSync.get_public_lobbies()


func _on_lobbies_received(lobbies: Array) -> void:
	if in_lobby:
		return

	available_lobbies.clear()

	for lobby in lobbies:
		if not lobby is Dictionary:
			continue

		if int(lobby.get("PlayerCount", 0)) >= int(lobby.get("PlayerLimit", 4)):
			continue

		if not bool(lobby.get("Open", true)):
			continue

		available_lobbies.append(lobby)

	local_games.text = "%d LAN Games Found" % available_lobbies.size()


# ═══════════════════════════════════════
# Host / Join
# ═══════════════════════════════════════

func _on_host_pressed() -> void:
	if in_lobby:
		return

	_show_connecting("Creating lobby...")

	var room_name: String = "LAN_" + str(randi_range(10000, 99999))
	GDSync.lobby_create(room_name, "", true, MAX_PLAYERS)


func _on_join_pressed() -> void:
	if in_lobby:
		return

	if available_lobbies.is_empty():
		print("No games to join!")
		_search_for_lan_games()
		return

	_show_connecting("Joining lobby...")

	var lobby_name: String = str(available_lobbies[0]["Name"])
	GDSync.lobby_join(lobby_name, "")


func _on_lobby_created(lobby_name: String) -> void:
	print("[Network] Created: ", lobby_name)

	# Creating a lobby does not automatically join it.
	GDSync.lobby_join(lobby_name, "")


func _on_lobby_joined(lobby_name: String) -> void:
	in_lobby = true
	current_lobby_name = lobby_name
	my_ready = false

	ready_states.clear()

	_hide_connecting()
	main_section.hide()

	_refresh_role_ui()

	# Each client owns and updates their own Ready state.
	GDSync.player_set_data("Ready", false)

	print("[Network] Joined: ", lobby_name)
	print("[Network] My ID: ", GDSync.get_client_id())
	print("[Network] Is Host: ", GDSync.is_host())

	_check_all_ready()


# ═══════════════════════════════════════
# Player Tracking
# ═══════════════════════════════════════

func _on_client_joined(client_id: int) -> void:
	if not in_lobby:
		return

	var key: String = str(client_id)

	if not ready_states.has(key):
		ready_states[key] = false

	print("[Network] Player joined: ", client_id)

	_check_all_ready()


func _on_client_left(client_id: int) -> void:
	if not in_lobby:
		return

	ready_states.erase(str(client_id))

	print("[Network] Player left: ", client_id)

	_check_all_ready()


func _on_player_data_changed(
	client_id: int,
	key: String,
	value: Variant
) -> void:
	if not in_lobby:
		return

	if key != "Ready":
		return

	ready_states[str(client_id)] = bool(value)

	print(
		"[Network] Player ",
		client_id,
		" Ready: ",
		value
	)

	_check_all_ready()


# ═══════════════════════════════════════
# Ready System
# ═══════════════════════════════════════

func _on_host_ready_pressed() -> void:
	_toggle_ready()


func _on_client_ready_pressed() -> void:
	_toggle_ready()


func _toggle_ready() -> void:
	if not in_lobby:
		return

	my_ready = not my_ready

	GDSync.player_set_data("Ready", my_ready)

	var my_id: String = str(GDSync.get_client_id())
	ready_states[my_id] = my_ready

	_update_ready_ui()

	print("[Network] My Ready: ", my_ready)

	_check_all_ready()


func _update_ready_ui() -> void:
	var label_node: Label

	if GDSync.is_host():
		label_node = host_ready_text
	else:
		label_node = client_ready_text

	if my_ready:
		label_node.text = "Ready"
		label_node.modulate = Color.WHITE
	else:
		label_node.text = "Not Ready"
		label_node.modulate = Color.RED


func _check_all_ready() -> void:
	if not in_lobby:
		host_start.hide()
		return

	if not GDSync.is_host():
		host_start.hide()
		return

	var player_count: int = ready_states.size()
	var all_ready: bool = player_count >= MIN_PLAYERS

	for state in ready_states.values():
		if not bool(state):
			all_ready = false
			break

	host_start.visible = all_ready

	print(
		"[Host] Players: ",
		player_count,
		" | States: ",
		ready_states,
		" | Can Start: ",
		all_ready
	)


# ═══════════════════════════════════════
# Host Migration
# ═══════════════════════════════════════

func _on_host_changed(
	_is_new_host: bool,
	_new_host_id: int
) -> void:
	if not in_lobby:
		return

	_refresh_role_ui()
	_check_all_ready()


func _refresh_role_ui() -> void:
	if not in_lobby:
		return

	var am_host: bool = GDSync.is_host()

	host_section.visible = am_host
	client_section.visible = not am_host

	_update_ready_ui()
	_check_all_ready()


# ═══════════════════════════════════════
# Start Game
# ═══════════════════════════════════════

func _on_host_start_pressed() -> void:
	if not GDSync.is_host():
		return

	_check_all_ready()

	if not host_start.visible:
		return

	host_start.disabled = true
	_remote_start_game()
	GDSync.call_func(_remote_start_game)

	# Give every peer a rendered frame for the transition overlay before the
	# synchronized scene load begins.
	await get_tree().create_timer(0.15).timeout

	# The match spawns a fixed snapshot of the current lobby members.
	# Prevent late joins from entering without a corresponding player.
	GDSync.lobby_close()
	GDSync.change_scene(GAME_SCENE)


func _remote_start_game() -> void:
	_show_connecting("Starting game...")

	main_section.hide()
	host_section.hide()
	client_section.hide()


# ═══════════════════════════════════════
# Connecting UI
# ═══════════════════════════════════════

func _show_connecting(message: String) -> void:
	connecting_state.text = message
	connecting_screen.show()


func _hide_connecting() -> void:
	connecting_screen.hide()
