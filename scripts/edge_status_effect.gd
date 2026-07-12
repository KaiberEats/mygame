extends Control

const BASE_EDGE_WIDTH := 86.0
const LAYER_COUNT := 10

var has_joker := false
var is_invincible := false
var has_barrier := false
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent()
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_fill_parent()
	_time += delta
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_fill_parent()


func _fill_parent() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func set_statuses(joker_active: bool, invincible_active: bool, barrier_active: bool) -> void:
	var changed := (
		has_joker != joker_active
		or is_invincible != invincible_active
		or has_barrier != barrier_active
	)
	has_joker = joker_active
	is_invincible = invincible_active
	has_barrier = barrier_active
	visible = has_joker or is_invincible or has_barrier
	if changed:
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	if has_joker:
		_draw_screen_vignette(Color(0.02, 0.0, 0.0, 0.34), 0.24)
		_draw_edge_glow(Color(0.01, 0.0, 0.0, 0.72), 1.55)
		_draw_edge_glow(Color(1.0, 0.0, 0.0, 0.62), 1.05)
		_draw_inner_frame(Color(0.95, 0.0, 0.0, 0.56), 1.0)
	if is_invincible:
		_draw_edge_glow(Color(1.0, 0.72, 0.04, 0.68), 1.18)
		_draw_inner_frame(Color(1.0, 0.86, 0.18, 0.72), 0.82)
		_draw_corner_bursts(Color(1.0, 0.78, 0.12, 0.72), 0.9)
	if has_barrier:
		_draw_edge_glow(Color(0.02, 0.36, 1.0, 0.66), 1.12)
		_draw_inner_frame(Color(0.18, 0.68, 1.0, 0.68), 0.72)
		_draw_corner_bursts(Color(0.14, 0.56, 1.0, 0.7), 0.78)
	if has_joker:
		_draw_cracks()


func _draw_edge_glow(color: Color, width_scale: float) -> void:
	var pulse := 0.82 + sin(_time * 5.4) * 0.18
	var edge_width := BASE_EDGE_WIDTH * width_scale
	for index in range(LAYER_COUNT):
		var ratio := 1.0 - float(index) / float(LAYER_COUNT)
		var layer_width := edge_width * ratio
		var alpha := color.a * ratio * ratio * pulse
		var layer_color := Color(color.r, color.g, color.b, alpha)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, layer_width)), layer_color)
		draw_rect(Rect2(Vector2(0.0, size.y - layer_width), Vector2(size.x, layer_width)), layer_color)
		draw_rect(Rect2(Vector2.ZERO, Vector2(layer_width, size.y)), layer_color)
		draw_rect(Rect2(Vector2(size.x - layer_width, 0.0), Vector2(layer_width, size.y)), layer_color)


func _draw_screen_vignette(color: Color, strength: float) -> void:
	var layer_count := 8
	for index in range(layer_count):
		var inset := minf(size.x, size.y) * 0.035 * float(index)
		var alpha := strength * (1.0 - float(index) / float(layer_count))
		var layer_color := Color(color.r, color.g, color.b, alpha)
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2.ONE * inset * 2.0), layer_color, false, 18.0)


func _draw_inner_frame(color: Color, width_scale: float) -> void:
	var pulse := 0.65 + sin(_time * 7.0) * 0.25
	var inset := 20.0 * width_scale
	var thickness := 5.0 * width_scale
	var frame_color := Color(color.r, color.g, color.b, color.a * pulse)
	draw_rect(Rect2(Vector2(inset, inset), size - Vector2.ONE * inset * 2.0), frame_color, false, thickness)


func _draw_corner_bursts(color: Color, width_scale: float) -> void:
	var length := 112.0 * width_scale
	var thickness := 10.0 * width_scale
	var pulse := 0.75 + sin(_time * 4.8) * 0.25
	var c := Color(color.r, color.g, color.b, color.a * pulse)
	var corners := [
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		Vector2(0.0, size.y),
		size,
	]
	for corner in corners:
		var x_dir := 1.0 if corner.x < size.x * 0.5 else -1.0
		var y_dir := 1.0 if corner.y < size.y * 0.5 else -1.0
		draw_line(corner, corner + Vector2(length * x_dir, 0.0), c, thickness, true)
		draw_line(corner, corner + Vector2(0.0, length * y_dir), c, thickness, true)


func _draw_cracks() -> void:
	var crack_color := Color(0.0, 0.0, 0.0, 0.72)
	var red_shadow := Color(0.7, 0.0, 0.0, 0.36)
	var cracks: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(size.x * 0.12, 0.0), Vector2(size.x * 0.15, 42.0), Vector2(size.x * 0.13, 84.0), Vector2(size.x * 0.2, 138.0)]),
		PackedVector2Array([Vector2(size.x * 0.44, 0.0), Vector2(size.x * 0.43, 34.0), Vector2(size.x * 0.49, 88.0), Vector2(size.x * 0.46, 138.0)]),
		PackedVector2Array([Vector2(size.x * 0.78, size.y), Vector2(size.x * 0.75, size.y - 44.0), Vector2(size.x * 0.81, size.y - 92.0), Vector2(size.x * 0.76, size.y - 148.0)]),
		PackedVector2Array([Vector2(0.0, size.y * 0.28), Vector2(46.0, size.y * 0.34), Vector2(86.0, size.y * 0.31), Vector2(142.0, size.y * 0.4)]),
		PackedVector2Array([Vector2(size.x, size.y * 0.62), Vector2(size.x - 48.0, size.y * 0.57), Vector2(size.x - 96.0, size.y * 0.66), Vector2(size.x - 154.0, size.y * 0.6)]),
		PackedVector2Array([Vector2(size.x * 0.04, size.y), Vector2(size.x * 0.07, size.y - 36.0), Vector2(size.x * 0.05, size.y - 78.0), Vector2(size.x * 0.11, size.y - 120.0)]),
		PackedVector2Array([Vector2(size.x * 0.96, 0.0), Vector2(size.x * 0.91, 44.0), Vector2(size.x * 0.94, 92.0), Vector2(size.x * 0.88, 132.0)]),
	]
	for points in cracks:
		_draw_crack(points, red_shadow, 9.0)
		_draw_crack(points, crack_color, 4.0)


func _draw_crack(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(points.size() - 1):
		draw_line(points[index], points[index + 1], color, width, true)
	for point in points:
		var branch_direction := 1.0 if point.x < size.x * 0.5 else -1.0
		var branch_end := point + Vector2(18.0, 12.0) * branch_direction
		if point.y > size.y * 0.5:
			branch_end.y -= 24.0
		draw_line(point, branch_end, color, width * 0.72, true)
		draw_circle(point, width * 0.55, color)
