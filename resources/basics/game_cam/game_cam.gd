extends Camera2D

## Shared arena camera inspired by platform fighters. It automatically frames
## every active player in the "players" group and gracefully fades targets in
## and out when they spawn, die, disconnect, or respawn.

@export_group("Framing")
@export var frame_padding: Vector2 = Vector2(220.0, 150.0)
@export var minimum_frame_size: Vector2 = Vector2(700.0, 400.0)
@export var center_offset: Vector2 = Vector2(0.0, -35.0)
@export_range(0.1, 3.0, 0.01) var closest_zoom: float = 1.20
@export_range(0.1, 3.0, 0.01) var farthest_zoom: float = 0.65

@export_group("Movement Prediction")
@export_range(0.0, 1.0, 0.01) var look_ahead_time: float = 0.16
@export var max_look_ahead: float = 90.0

@export_group("Smoothing")
@export var position_smoothness: float = 5.5
@export var position_catchup_boost: float = 5.0
@export var zoom_out_smoothness: float = 7.0
@export var zoom_in_smoothness: float = 2.5
@export var position_dead_zone: float = 1.0
@export var zoom_dead_zone: float = 0.002
@export var target_fade_in_speed: float = 8.0
@export var target_fade_out_speed: float = 2.5
@export var snap_on_first_target: bool = true

@export_group("Camera Limits (0 = Unlimited)")
@export var custom_limit_left: int = 0:
	set(value):
		custom_limit_left = value
		_apply_camera_limits()

@export var custom_limit_right: int = 0:
	set(value):
		custom_limit_right = value
		_apply_camera_limits()

@export var custom_limit_top: int = 0:
	set(value):
		custom_limit_top = value
		_apply_camera_limits()

@export var custom_limit_bottom: int = 0:
	set(value):
		custom_limit_bottom = value
		_apply_camera_limits()

# Each entry keeps a weak reference, its latest useful position and a weight.
# Keeping the last position lets a dead/freed player leave the frame smoothly.
var _tracked_targets: Dictionary = {}
var _has_framed_targets: bool = false


func _ready() -> void:
	position_smoothing_enabled = false
	_apply_camera_limits()
	make_current()


func _process(delta: float) -> void:
	_update_tracked_targets(delta)

	var samples: Array[Dictionary] = _get_weighted_samples()
	if samples.is_empty():
		return

	var target_position: Vector2 = _calculate_weighted_center(samples)
	var target_zoom: Vector2 = _calculate_target_zoom(samples, target_position)
	target_position += center_offset

	if not _has_framed_targets and snap_on_first_target:
		global_position = target_position
		zoom = target_zoom
		_has_framed_targets = true
		return

	_has_framed_targets = true
	_apply_smoothing(target_position, target_zoom, delta)


func _update_tracked_targets(delta: float) -> void:
	var seen_ids: Dictionary = {}

	for candidate in get_tree().get_nodes_in_group("players"):
		if not candidate is Node2D:
			continue

		var player := candidate as Node2D
		if not is_instance_valid(player) or player.is_queued_for_deletion():
			continue

		var instance_id: int = player.get_instance_id()
		seen_ids[instance_id] = true

		if not _tracked_targets.has(instance_id):
			_tracked_targets[instance_id] = {
				"reference": weakref(player),
				"position": player.global_position,
				"weight": 0.0,
				"desired_weight": 0.0,
			}

		var data: Dictionary = _tracked_targets[instance_id]
		data["reference"] = weakref(player)
		data["position"] = _get_predicted_position(player)
		data["desired_weight"] = 1.0 if _is_player_trackable(player) else 0.0

	for instance_id in _tracked_targets.keys():
		var data: Dictionary = _tracked_targets[instance_id]
		if not seen_ids.has(instance_id):
			data["desired_weight"] = 0.0

		var current_weight: float = float(data["weight"])
		var desired_weight: float = float(data["desired_weight"])
		var fade_speed: float = (
			target_fade_in_speed
			if desired_weight > current_weight
			else target_fade_out_speed
		)
		data["weight"] = move_toward(
			current_weight,
			desired_weight,
			fade_speed * delta
		)

		if float(data["weight"]) <= 0.001 and desired_weight <= 0.0:
			_tracked_targets.erase(instance_id)


func _is_player_trackable(player: Node2D) -> bool:
	if not player.is_visible_in_tree():
		return false
	if "camera_tracking_enabled" in player:
		return bool(player.get("camera_tracking_enabled"))
	return true


func _get_predicted_position(player: Node2D) -> Vector2:
	var predicted_position: Vector2 = player.global_position
	if not "velocity" in player:
		return predicted_position

	var player_velocity: Variant = player.get("velocity")
	if not player_velocity is Vector2:
		return predicted_position

	var look_ahead: Vector2 = (player_velocity as Vector2) * look_ahead_time
	if look_ahead.length() > max_look_ahead:
		look_ahead = look_ahead.normalized() * max_look_ahead
	return predicted_position + look_ahead


func _get_weighted_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for data_variant in _tracked_targets.values():
		var data: Dictionary = data_variant
		var weight: float = float(data["weight"])
		if weight <= 0.001:
			continue
		samples.append({
			"position": data["position"],
			"weight": weight,
		})
	return samples


func _calculate_weighted_center(samples: Array[Dictionary]) -> Vector2:
	var weighted_position := Vector2.ZERO
	var total_weight: float = 0.0
	for sample in samples:
		var weight: float = float(sample["weight"])
		weighted_position += (sample["position"] as Vector2) * weight
		total_weight += weight
	return weighted_position / maxf(total_weight, 0.001)


func _calculate_target_zoom(
	samples: Array[Dictionary],
	frame_center: Vector2
) -> Vector2:
	var half_extents := Vector2.ZERO
	for sample in samples:
		var sample_position: Vector2 = sample["position"]
		var weight: float = float(sample["weight"])
		var distance_from_center: Vector2 = (sample_position - frame_center).abs()
		half_extents.x = maxf(half_extents.x, distance_from_center.x * weight)
		half_extents.y = maxf(half_extents.y, distance_from_center.y * weight)

	var required_size: Vector2 = half_extents * 2.0 + frame_padding * 2.0
	required_size.x = maxf(required_size.x, minimum_frame_size.x)
	required_size.y = maxf(required_size.y, minimum_frame_size.y)

	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return zoom

	var fit_zoom: float = minf(
		viewport_size.x / required_size.x,
		viewport_size.y / required_size.y
	)
	fit_zoom = clampf(fit_zoom, farthest_zoom, closest_zoom)
	return Vector2.ONE * fit_zoom


func _apply_smoothing(
	target_position: Vector2,
	target_zoom: Vector2,
	delta: float
) -> void:
	var position_distance: float = global_position.distance_to(target_position)
	if position_distance > position_dead_zone:
		var catchup: float = clampf(
			position_distance / 300.0,
			0.0,
			1.0
		) * position_catchup_boost
		var position_weight: float = 1.0 - exp(
			-(position_smoothness + catchup) * delta
		)
		global_position = global_position.lerp(target_position, position_weight)

	if absf(zoom.x - target_zoom.x) > zoom_dead_zone:
		var zooming_out: bool = target_zoom.x < zoom.x
		var zoom_speed: float = (
			zoom_out_smoothness if zooming_out else zoom_in_smoothness
		)
		var zoom_weight: float = 1.0 - exp(-zoom_speed * delta)
		zoom = zoom.lerp(target_zoom, zoom_weight)


func _apply_camera_limits() -> void:
	limit_left = custom_limit_left if custom_limit_left != 0 else -10000000
	limit_right = custom_limit_right if custom_limit_right != 0 else 10000000
	limit_top = custom_limit_top if custom_limit_top != 0 else -10000000
	limit_bottom = custom_limit_bottom if custom_limit_bottom != 0 else 10000000
