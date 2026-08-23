@tool
extends Node3D

const MAP_SIZE := 90.0
const WALL_HEIGHT := 6.0
const WALL_THICKNESS := 0.6
const MAIN_DOOR_WIDTH := 6.0
const HORIZONTAL_DOORS: Array[float] = [-30.0, -10.0, 10.0, 30.0]
const VERTICAL_DOORS: Array[float] = [-25.0, 0.0, 25.0]

@export_tool_button("Rebuild Mansion Map") var rebuild_action := _rebuild_map

var _wood := StandardMaterial3D.new()
var _wallpaper := StandardMaterial3D.new()
var _stone := StandardMaterial3D.new()
var _carpet := StandardMaterial3D.new()
var _gold := StandardMaterial3D.new()
var _dark_wood := StandardMaterial3D.new()
var _structure_root: Node3D
var _furniture_root: Node3D
var _decoration_root: Node3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_map()
	elif get_child_count() == 0:
		_rebuild_map()


func _rebuild_map() -> void:
	for child in get_children():
		child.free()

	_wood.albedo_color = Color(0.25, 0.11, 0.045)
	_wallpaper.albedo_color = Color(0.42, 0.13, 0.12)
	_stone.albedo_color = Color(0.22, 0.22, 0.24)
	_carpet.albedo_color = Color(0.36, 0.025, 0.035)
	_gold.albedo_color = Color(0.72, 0.52, 0.14)
	_dark_wood.albedo_color = Color(0.095, 0.045, 0.025)

	_structure_root = _add_category("Structure")
	_furniture_root = _add_category("Furniture")
	_decoration_root = _add_category("Decoration")
	_build_shell()
	_build_rooms()
	_build_furnishings()


func _build_shell() -> void:
	_add_box("Floor", Vector3(MAP_SIZE, 0.5, MAP_SIZE), Vector3(0, -0.25, 0), _wood)
	_add_box("NorthWall", Vector3(MAP_SIZE, WALL_HEIGHT, WALL_THICKNESS), Vector3(0, 3, -45), _stone)
	_add_box("SouthWall", Vector3(MAP_SIZE, WALL_HEIGHT, WALL_THICKNESS), Vector3(0, 3, 45), _stone)
	_add_box("EastWall", Vector3(WALL_THICKNESS, WALL_HEIGHT, MAP_SIZE), Vector3(45, 3, 0), _stone)
	_add_box("WestWall", Vector3(WALL_THICKNESS, WALL_HEIGHT, MAP_SIZE), Vector3(-45, 3, 0), _stone)

	# Long central carpet visually connects the entrance, grand hall, and rear gallery.
	_add_visual_box("CentralCarpet", Vector3(10, 0.08, 78), Vector3(0, 0.05, 0), _carpet)
	_add_visual_box("CrossCarpet", Vector3(72, 0.08, 8), Vector3(0, 0.06, 0), _carpet)


func _build_rooms() -> void:
	# Horizontal room divisions with central and side door openings.
	for z in [-25.0, 25.0]:
		_add_wall_segments_x(z, HORIZONTAL_DOORS, MAIN_DOOR_WIDTH)

	# Vertical wings create eight side rooms while preserving broad cross corridors.
	for x in [-25.0, 25.0]:
		_add_wall_segments_z(x, VERTICAL_DOORS, MAIN_DOOR_WIDTH)

	for z in [-25.0, 25.0]:
		for x in HORIZONTAL_DOORS:
			_add_door_posts(Vector3(x, 2.75, z), true)
	for x in [-25.0, 25.0]:
		for z in VERTICAL_DOORS:
			_add_door_posts(Vector3(x, 2.75, z), false)


func _build_furnishings() -> void:
	# Keep the central cross corridor open while retaining columns deeper in the hall.
	for x in [-9.0, 9.0]:
		for z in [-16.0, 16.0]:
			_add_box("Column", Vector3(1.8, 5.4, 1.8), Vector3(x, 2.7, z), _stone)
			_add_visual_box("ColumnTrim", Vector3(2.5, 0.35, 2.5), Vector3(x, 0.18, z), _gold)

	# Dining tables and library shelves act as cover.
	for x in [-34.0, 34.0]:
		for z in [-33.0, 33.0]:
			_add_box("Table", Vector3(8, 1.4, 3), Vector3(x, 0.7, z), _dark_wood)
			_add_box("Shelf", Vector3(1.2, 4.2, 10), Vector3(x + (-6.0 if x > 0 else 6.0), 2.1, z), _dark_wood)

	# Low furniture in sitting rooms.
	for sofa_position in [
		Vector3(-34, 0.6, -15), Vector3(-34, 0.6, 15),
		Vector3(34, 0.6, -15), Vector3(34, 0.6, 15),
	]:
		_add_box("Sofa", Vector3(7, 1.2, 2.2), sofa_position, _wallpaper)

	# Offset the decorative plinth so both axes through the grand hall remain passable.
	_add_box("CentralPlinth", Vector3(5, 1.8, 5), Vector3(16, 0.9, -16), _stone)
	_add_visual_box("CentralOrnament", Vector3(2, 2.6, 2), Vector3(16, 3.1, -16), _gold)


func _add_wall_segments_x(z: float, door_centers: Array[float], door_width: float) -> void:
	var starts: Array[float] = [-MAP_SIZE * 0.5]
	var ends: Array[float] = []
	for door_center in door_centers:
		ends.append(door_center - door_width * 0.5)
		starts.append(door_center + door_width * 0.5)
	ends.append(MAP_SIZE * 0.5)
	for index in starts.size():
		var length := ends[index] - starts[index]
		if length > 0.1:
			_add_box("InteriorWall", Vector3(length, WALL_HEIGHT, WALL_THICKNESS), Vector3(starts[index] + length * 0.5, 3, z), _wallpaper)


func _add_wall_segments_z(x: float, door_centers: Array[float], door_width: float) -> void:
	var starts: Array[float] = [-MAP_SIZE * 0.5]
	var ends: Array[float] = []
	for door_center in door_centers:
		ends.append(door_center - door_width * 0.5)
		starts.append(door_center + door_width * 0.5)
	ends.append(MAP_SIZE * 0.5)
	for index in starts.size():
		var length := ends[index] - starts[index]
		if length > 0.1:
			_add_box("InteriorWall", Vector3(WALL_THICKNESS, WALL_HEIGHT, length), Vector3(x, 3, starts[index] + length * 0.5), _wallpaper)


func _add_door_posts(door_position: Vector3, opening_runs_along_x: bool) -> void:
	var offset := Vector3(MAIN_DOOR_WIDTH * 0.5, 0.0, 0.0) if opening_runs_along_x else Vector3(0.0, 0.0, MAIN_DOOR_WIDTH * 0.5)
	_add_visual_box("DoorFrame", Vector3(0.5, 5.5, 0.5), door_position - offset, _gold)
	_add_visual_box("DoorFrame", Vector3(0.5, 5.5, 0.5), door_position + offset, _gold)


func _add_box(node_name: String, box_size: Vector3, box_position: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = box_position
	if node_name.ends_with("Wall"):
		body.add_to_group("minimap_walls")
	var parent := _furniture_root if node_name in ["Table", "Shelf", "Sofa", "CentralPlinth"] else _structure_root
	parent.add_child(body)
	_set_editable_owner(body)

	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	_set_editable_owner(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = box_size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)
	_set_editable_owner(collision)


func _add_visual_box(node_name: String, box_size: Vector3, box_position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = box_position
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	_decoration_root.add_child(mesh_instance)
	_set_editable_owner(mesh_instance)


func _add_category(category_name: String) -> Node3D:
	var category := Node3D.new()
	category.name = category_name
	add_child(category)
	_set_editable_owner(category)
	return category


func _set_editable_owner(node: Node) -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		node.owner = get_tree().edited_scene_root
