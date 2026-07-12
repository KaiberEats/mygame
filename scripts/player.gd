extends CharacterBody3D

signal hand_changed(cards: Array[Dictionary])

const HAND_SORTER := preload("res://scripts/hand_sorter.gd")

@export var move_speed: float = 7.0
@export var mouse_sensitivity: float = 0.0025
@export var jump_height: float = 2.0

@onready var visual_pivot: Node3D = $VisualPivot
@onready var body: MeshInstance3D = $VisualPivot/Body
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var third_person_camera: Camera3D = $ThirdPersonCamera

var hand: Array[Dictionary] = []
var _pitch := 0.0
var _stun_time_left := 0.0
var _pending_stun_time := 0.0
var _is_stun_pose_active := false
var _pose_tween: Tween
var _speed_multiplier := 1.0
var display_name := "Player"
var _body_material: StandardMaterial3D
var _input_enabled := true
var _barrier_effect: MeshInstance3D
var _barrier_active := false


func _ready() -> void:
	add_to_group("participants")
	_body_material = body.get_active_material(0).duplicate() as StandardMaterial3D
	body.material_override = _body_material
	_create_barrier_effect()
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		ensure_local_camera()
	else:
		camera.current = false
		third_person_camera.current = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if not is_stunned() and event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-80.0), deg_to_rad(80.0))
		camera_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	_update_stun(delta)
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y -= _get_gravity() * delta

	if _pending_stun_time > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_update_third_person_camera()
		return

	if is_stunned() or not _input_enabled:
		velocity = Vector3.ZERO
		move_and_slide()
		_update_third_person_camera()
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	velocity.x = direction.x * move_speed * _speed_multiplier
	velocity.z = direction.z * move_speed * _speed_multiplier
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = sqrt(2.0 * _get_gravity() * jump_height)

	move_and_slide()
	if NetworkManager.is_online:
		_sync_transform.rpc(global_transform)


func set_hand(cards: Array, force_sort: bool = false) -> void:
	var typed_cards: Array[Dictionary] = []
	for card in cards:
		if card is Dictionary:
			typed_cards.append(card)
	hand = HAND_SORTER.sort(typed_cards) if force_sort or typed_cards.size() > hand.size() else typed_cards
	hand_changed.emit(hand)


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
	if is_multiplayer_authority() and (not is_on_floor() or velocity.y > 0.0):
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


func set_body_color(color: Color) -> void:
	if _body_material == null:
		_body_material = StandardMaterial3D.new()
		body.material_override = _body_material
	_body_material.albedo_color = color


func set_input_enabled(is_enabled: bool) -> void:
	_input_enabled = is_enabled


func set_barrier_active(is_active: bool) -> void:
	if _barrier_effect == null:
		_create_barrier_effect()
	_barrier_active = is_active
	_update_barrier_visibility()


func get_view_origin() -> Vector3:
	return camera.global_position


func get_view_forward() -> Vector3:
	return -camera.global_transform.basis.z.normalized()


func get_display_name() -> String:
	return display_name


func ensure_local_camera() -> void:
	if not is_multiplayer_authority():
		camera.current = false
		third_person_camera.current = false
		_update_barrier_visibility()
		return

	if is_stunned():
		third_person_camera.make_current()
	else:
		camera.make_current()
	_update_barrier_visibility()


func _get_gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func _activate_stun(seconds: float) -> void:
	_stun_time_left = maxf(_stun_time_left, seconds)
	velocity = Vector3.ZERO
	_set_stun_pose(true)


func _update_stun(delta: float) -> void:
	if _pending_stun_time > 0.0 and is_on_floor():
		_activate_stun(_pending_stun_time)
		_pending_stun_time = 0.0
	if _stun_time_left <= 0.0:
		return
	_stun_time_left = maxf(_stun_time_left - delta, 0.0)
	if _stun_time_left <= 0.0:
		_set_stun_pose(false)


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

	ensure_local_camera()


func _update_third_person_camera() -> void:
	if not third_person_camera.current:
		return

	var target := global_position + Vector3(0.0, 1.25, 0.0)
	var desired := global_transform * Vector3(0.0, 3.5, 5.0)
	var direction := desired - target
	var distance := direction.length()
	if distance <= 0.01:
		return
	direction /= distance

	var camera_position := desired
	var query := PhysicsRayQueryParameters3D.create(target, desired)
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_distance: float = target.distance_to(hit["position"])
		camera_position = target + direction * maxf(hit_distance - 0.25, 0.75)

	third_person_camera.global_position = camera_position
	third_person_camera.look_at(target, Vector3.UP)


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


func _update_barrier_visibility() -> void:
	if _barrier_effect == null:
		return
	var is_local_first_person := is_multiplayer_authority() and camera.current
	_barrier_effect.visible = _barrier_active and not is_local_first_person


@rpc("authority", "call_remote", "unreliable")
func _sync_transform(new_transform: Transform3D) -> void:
	global_transform = new_transform
