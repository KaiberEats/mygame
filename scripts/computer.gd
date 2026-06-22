extends CharacterBody3D

const HAND_SORTER := preload("res://scripts/hand_sorter.gd")

@export var move_speed: float = 4.0
@export var turn_speed: float = 1.8
@export var jump_height: float = 2.0
@export var jump_interval_min: float = 1.5
@export var jump_interval_max: float = 3.0

@onready var visual_pivot: Node3D = $VisualPivot
@onready var body: MeshInstance3D = $VisualPivot/Body

var hand: Array[Dictionary] = []
var _move_direction := Vector3.ZERO
var _action_timer := 0.0
var _stun_time_left := 0.0
var _pending_stun_time := 0.0
var _is_stun_pose_active := false
var _pose_tween: Tween
var _speed_multiplier := 1.0
var _can_kill_without_joker := false
var _jump_timer := 0.0
var _barrier_effect: MeshInstance3D


func _ready() -> void:
	add_to_group("participants")
	_create_barrier_effect()
	_pick_random_action()
	_reset_jump_timer()


func _physics_process(delta: float) -> void:
	if NetworkManager.is_online and not multiplayer.is_server():
		return
	if not is_on_floor():
		velocity.y -= _get_gravity() * delta

	if _pending_stun_time > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if is_on_floor():
			_activate_stun(_pending_stun_time)
			_pending_stun_time = 0.0
		return

	if is_stunned():
		_stun_time_left = maxf(_stun_time_left - delta, 0.0)
		velocity = Vector3.ZERO
		move_and_slide()
		if not is_stunned():
			_set_stun_pose(false)
		return

	_jump_timer -= delta
	var chase_target := get_chase_target()
	if chase_target != null:
		_chase(chase_target, delta)
		_try_jump()
		move_and_slide()
		return

	_action_timer -= delta
	if _action_timer <= 0.0:
		_pick_random_action()

	velocity.x = _move_direction.x * move_speed * _speed_multiplier
	velocity.z = _move_direction.z * move_speed * _speed_multiplier
	_try_jump()
	move_and_slide()


func set_hand(cards: Array, force_sort: bool = false) -> void:
	var typed_cards: Array[Dictionary] = []
	for card in cards:
		if card is Dictionary:
			typed_cards.append(card)
	hand = HAND_SORTER.sort(typed_cards) if force_sort or typed_cards.size() > hand.size() else typed_cards


func add_card(card: Dictionary) -> void:
	var updated_hand: Array[Dictionary] = hand.duplicate()
	updated_hand.append(card)
	set_hand(updated_hand)


func has_joker() -> bool:
	for card in hand:
		if card.get("suit", "") == "joker":
			return true
	return false


func stun(seconds: float) -> void:
	if not is_on_floor() or velocity.y > 0.0:
		_pending_stun_time = maxf(_pending_stun_time, seconds)
		return
	_activate_stun(seconds)


func is_stunned() -> bool:
	return _stun_time_left > 0.0 or _pending_stun_time > 0.0


func is_stun_pending() -> bool:
	return _pending_stun_time > 0.0


func get_stun_time_left() -> float:
	return maxf(_stun_time_left, _pending_stun_time)


func clear_stun() -> void:
	_stun_time_left = 0.0
	_pending_stun_time = 0.0
	_set_stun_pose(false)


func set_stun_state(time_left: float, pending_time: float) -> void:
	_stun_time_left = maxf(time_left, 0.0)
	_pending_stun_time = maxf(pending_time, 0.0)
	_set_stun_pose(_stun_time_left > 0.0)


func set_speed_multiplier(value: float) -> void:
	_speed_multiplier = value


func set_can_kill_without_joker(value: bool) -> void:
	_can_kill_without_joker = value


func set_invisible(is_invisible: bool) -> void:
	visual_pivot.visible = not is_invisible


func set_gold_outline(is_active: bool) -> void:
	if is_active:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.75, 0.05, 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		body.material_overlay = material
	else:
		body.material_overlay = null


func set_barrier_active(is_active: bool) -> void:
	if _barrier_effect == null:
		_create_barrier_effect()
	_barrier_effect.visible = is_active


func get_view_origin() -> Vector3:
	return $CameraPivot.global_position


func get_view_forward() -> Vector3:
	return -$CameraPivot.global_transform.basis.z.normalized()


func get_chase_target() -> Node3D:
	if (not has_joker() and not _can_kill_without_joker) or is_stunned():
		return null

	var nearest_target: Node3D = null
	var nearest_distance_squared := INF
	for participant in get_tree().get_nodes_in_group("participants"):
		if participant == self or participant.is_stunned():
			continue

		var distance_squared: float = global_position.distance_squared_to(participant.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_target = participant

	return nearest_target


func _pick_random_action() -> void:
	_action_timer = randf_range(0.8, 2.2)
	rotate_y(randf_range(-PI, PI) * 0.35)

	if randf() < 0.25:
		_move_direction = Vector3.ZERO
	else:
		var local_direction := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		_move_direction = (global_transform.basis * local_direction).normalized()


func _chase(target: Node3D, delta: float) -> void:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	_move_direction = to_target.normalized()

	var target_angle := atan2(-_move_direction.x, -_move_direction.z)
	rotation.y = rotate_toward(rotation.y, target_angle, turn_speed * delta)
	velocity.x = _move_direction.x * move_speed * _speed_multiplier
	velocity.z = _move_direction.z * move_speed * _speed_multiplier


func _try_jump() -> void:
	if _jump_timer > 0.0 or not is_on_floor() or _move_direction.is_zero_approx():
		return
	velocity.y = sqrt(2.0 * _get_gravity() * jump_height)
	_reset_jump_timer()


func _reset_jump_timer() -> void:
	_jump_timer = randf_range(jump_interval_min, jump_interval_max)


func _get_gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func _activate_stun(seconds: float) -> void:
	_stun_time_left = maxf(_stun_time_left, seconds)
	velocity = Vector3.ZERO
	_set_stun_pose(true)


func _set_stun_pose(is_active: bool) -> void:
	if _is_stun_pose_active == is_active:
		return

	_is_stun_pose_active = is_active
	if _pose_tween != null:
		_pose_tween.kill()

	_pose_tween = create_tween().set_parallel()
	_pose_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(
		visual_pivot,
		"rotation:z",
		deg_to_rad(-90.0) if is_active else 0.0,
		0.3
	)
	_pose_tween.tween_property(
		visual_pivot,
		"position:y",
		0.5 if is_active else 0.0,
		0.3
	)


func _create_barrier_effect() -> void:
	_barrier_effect = MeshInstance3D.new()
	_barrier_effect.name = "BarrierEffect"
	var sphere := SphereMesh.new()
	sphere.radius = 1.15
	sphere.height = 2.45
	_barrier_effect.mesh = sphere
	_barrier_effect.position.y = 1.05
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.25, 0.55, 1.0, 0.22)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_barrier_effect.material_override = material
	_barrier_effect.visible = false
	add_child(_barrier_effect)
