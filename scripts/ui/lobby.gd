extends Control


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$Center/VBox/ClassicButton.pressed.connect(_start_map.bind("res://scenes/Main.tscn"))
	$Center/VBox/MansionButton.pressed.connect(_start_map.bind("res://scenes/Mansion.tscn"))
	$Center/VBox/BackButton.pressed.connect(_start_map.bind("res://scenes/Title.tscn"))


func _start_map(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
