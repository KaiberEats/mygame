extends CharacterBody3D

@export var speed := 14.0
@export var turn_speed := 5.0

var target: Node3D
var shooter: Node3D
var game: Node


func setup(new_shooter: Node3D, new_target: Node3D, new_game: Node) -> void:
	shooter = new_shooter
	target = new_target
	game = new_game
	add_collision_exception_with(shooter)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return

	var desired := (target.global_position + Vector3.UP - global_position).normalized()
	var direction := (-global_transform.basis.z).slerp(desired, clampf(turn_speed * delta, 0.0, 1.0)).normalized()
	look_at(global_position + direction, Vector3.UP)
	velocity = direction * speed
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	if collision.get_collider() == target:
		game.on_missile_hit(target)
	queue_free()
