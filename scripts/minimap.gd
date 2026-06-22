extends Control

var player_position := Vector3.ZERO
var revealed_positions: Array[Vector3] = []
var world_half_extent := 20.0


func set_world_half_extent(value: float) -> void:
	world_half_extent = maxf(value, 1.0)
	queue_redraw()


func set_data(new_player_position: Vector3, new_revealed_positions: Array[Vector3]) -> void:
	player_position = new_player_position
	revealed_positions = new_revealed_positions
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.47
	draw_circle(center, radius, Color(0.04, 0.04, 0.04, 0.86))
	var map_half_size := minf(size.x, size.y) * 0.36
	var room_rect := Rect2(center - Vector2.ONE * map_half_size, Vector2.ONE * map_half_size * 2.0)
	draw_rect(room_rect, Color(0.55, 0.35, 0.15), false, 2.0)
	_draw_walls()
	draw_circle(_world_to_map(player_position), 5.0, Color.LIME_GREEN)
	for revealed_position in revealed_positions:
		draw_circle(_world_to_map(revealed_position), 4.0, Color.RED)
	draw_arc(center, radius, 0.0, TAU, 64, Color.WHITE, 4.0)


func _draw_walls() -> void:
	var structure := get_tree().current_scene.get_node_or_null("Room/Structure")
	if structure == null:
		return
	for wall in structure.find_children("*", "StaticBody3D", true, false):
		if not wall.is_in_group("minimap_walls"):
			continue
		var collision := wall.get_node_or_null("Collision") as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var wall_size := (collision.shape as BoxShape3D).size
		var runs_along_x := wall_size.x >= wall_size.z
		var half_length := (wall_size.x if runs_along_x else wall_size.z) * 0.5
		var local_start := Vector3(-half_length, 0.0, 0.0) if runs_along_x else Vector3(0.0, 0.0, -half_length)
		var local_end := Vector3(half_length, 0.0, 0.0) if runs_along_x else Vector3(0.0, 0.0, half_length)
		draw_line(
			_world_to_map(collision.to_global(local_start)),
			_world_to_map(collision.to_global(local_end)),
			Color(0.84, 0.79, 0.7, 1.0),
			2.0,
			true
		)


func _world_to_map(world_position: Vector3) -> Vector2:
	var map_scale := minf(size.x, size.y) * 0.36 / world_half_extent
	return size * 0.5 + Vector2(world_position.x, world_position.z) * map_scale
