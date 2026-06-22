extends Control

var item_name := ""
var time_left := 0.0
var duration := 0.0
var icon: Texture2D


func set_item(new_name: String, new_time_left: float, new_duration: float, new_icon: Texture2D = null) -> void:
	item_name = new_name
	time_left = new_time_left
	duration = new_duration
	icon = new_icon
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.45
	draw_circle(center, radius, Color(0.08, 0.08, 0.08, 0.9))
	draw_arc(center, radius, 0.0, TAU, 64, Color.WHITE, 4.0)

	if item_name.is_empty():
		draw_string(ThemeDB.fallback_font, center + Vector2(-4.0, 6.0), "R", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.55, 0.55, 0.55))
		return

	var ratio := clampf(time_left / duration, 0.0, 1.0) if duration > 0.0 else 1.0
	if duration > 0.0:
		draw_arc(center, radius - 7.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 64, Color(1.0 - ratio, ratio, 0.1), 10.0)
	if icon != null:
		draw_texture_rect(icon, Rect2(Vector2(20.0, 20.0), size - Vector2(40.0, 40.0)), false)
	elif item_name == "MISSILE":
		var missile_rect := Rect2(center - Vector2(9.0, 24.0), Vector2(18.0, 48.0))
		draw_rect(missile_rect, Color(0.02, 0.02, 0.02), true)
		draw_rect(missile_rect, Color.WHITE, false, 2.0)
		draw_circle(center + Vector2(0.0, -24.0), 9.0, Color(0.02, 0.02, 0.02))
		draw_arc(center + Vector2(0.0, -24.0), 9.0, PI, TAU, 16, Color.WHITE, 2.0)
	elif item_name == "SWORD":
		var blade_points := PackedVector2Array([
			center + Vector2(-5.0, -30.0),
			center + Vector2(5.0, -30.0),
			center + Vector2(5.0, 14.0),
			center + Vector2(-5.0, 14.0),
		])
		draw_colored_polygon(blade_points, Color(0.82, 0.88, 0.95))
		draw_polyline(blade_points + PackedVector2Array([blade_points[0]]), Color.WHITE, 2.0)
		draw_line(center + Vector2(-18.0, 14.0), center + Vector2(18.0, 14.0), Color(0.85, 0.65, 0.15), 5.0)
		draw_line(center + Vector2(0.0, 16.0), center + Vector2(0.0, 31.0), Color(0.45, 0.25, 0.08), 7.0)
	elif item_name == "SCYTHE":
		draw_arc(center + Vector2(3.0, -6.0), 25.0, -PI * 0.85, PI * 0.2, 32, Color(0.9, 0.92, 0.96), 6.0)
		draw_line(center + Vector2(-8.0, -9.0), center + Vector2(20.0, 28.0), Color(0.45, 0.25, 0.08), 6.0)
		draw_line(center + Vector2(-8.0, -9.0), center + Vector2(7.0, -17.0), Color(0.9, 0.92, 0.96), 4.0)
	elif item_name == "COIN":
		draw_circle(center, 24.0, Color(1.0, 0.72, 0.1))
		draw_arc(center, 24.0, 0.0, TAU, 48, Color(1.0, 0.95, 0.45), 4.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(-7.0, 9.0), "$", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, Color(0.45, 0.25, 0.02))
	elif item_name == "SHIELD":
		var shield_points := PackedVector2Array([
			center + Vector2(0.0, -30.0),
			center + Vector2(24.0, -18.0),
			center + Vector2(18.0, 14.0),
			center + Vector2(0.0, 30.0),
			center + Vector2(-18.0, 14.0),
			center + Vector2(-24.0, -18.0),
		])
		draw_colored_polygon(shield_points, Color(0.18, 0.42, 0.95))
		draw_polyline(shield_points + PackedVector2Array([shield_points[0]]), Color.WHITE, 3.0)
		draw_line(center + Vector2(0.0, -24.0), center + Vector2(0.0, 24.0), Color(0.85, 0.92, 1.0), 3.0)
	elif item_name == "RAPIER":
		draw_line(center + Vector2(-18.0, 24.0), center + Vector2(20.0, -28.0), Color(0.85, 0.9, 1.0), 5.0)
		draw_line(center + Vector2(-22.0, 12.0), center + Vector2(-6.0, 25.0), Color(0.9, 0.72, 0.18), 5.0)
		draw_circle(center + Vector2(-20.0, 25.0), 5.0, Color(0.55, 0.25, 0.08))
		draw_circle(center + Vector2(20.0, -28.0), 4.0, Color.WHITE)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(4.0, center.y + 6.0), item_name, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8.0, 12, Color.WHITE)
