extends Control

const EFFECTS_EN := [
	"1: Redraw hand / Enhanced: Draw pairs", "2: Missile / Enhanced: 2 missiles",
	"3: Invincible 5s / Enhanced: 10s", "4: Scythe 15s, press R to kill / Enhanced: press R to start auto scythe",
	"5: View nearest hand 15s / Enhanced: View all hands 15s", "6: Cleanse / Enhanced: Auto cleanse",
	"7: Invisible 10s / Enhanced: 20s", "8: Coin, press R to change / Enhanced: 2 coins",
	"9: Rapier counter 3s / Enhanced: 6s", "10: Copy 1 card / Enhanced: Copy 2 cards",
	"11: Map reveal 10s / Enhanced: 20s", "12: Shield / Enhanced: 2 shields",
	"13: Enhance next effect / Enhanced: Sword",
]
const EFFECTS_JA := [
	"1: 手札交換 / 強化: ペアを引く", "2: ミサイル / 強化: ミサイル2発",
	"3: 5秒無敵 / 強化: 10秒無敵", "4: 鎌15秒、Rでキル / 強化: Rでオート鎌開始",
	"5: 最寄りの手札を見る15秒 / 強化: 全員の手札を見る15秒", "6: 状態回復 / 強化: 自動状態回復",
	"7: 10秒透明 / 強化: 20秒透明", "8: コイン、Rでチェンジ / 強化: コイン2回",
	"9: レイピアカウンター3秒 / 強化: 6秒", "10: カード1枚コピー / 強化: 2枚コピー",
	"11: 10秒マップ表示 / 強化: 20秒表示", "12: 盾1回 / 強化: 盾2回",
	"13: 次の効果を強化 / 強化: ソード",
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.035, 0.025, 0.045)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)
	content.add_child(_label(GameConfig.text("tutorial_title"), 44))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(900, 900)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.bbcode_enabled = true
	text.add_theme_font_size_override("normal_font_size", 20)
	var effects := EFFECTS_JA if GameConfig.language == "ja" else EFFECTS_EN
	text.text = "[font_size=28][b]%s[/b][/font_size]\n%s\n\n[font_size=28][b]%s[/b][/font_size]\n%s\n\n[font_size=28][b]%s[/b][/font_size]\n%s" % [
		GameConfig.text("tutorial_rules"), GameConfig.text("tutorial_rules_body"),
		GameConfig.text("tutorial_controls"), GameConfig.text("tutorial_controls_body"),
		GameConfig.text("tutorial_cards"), "\n".join(effects),
	]
	scroll.add_child(text)
	var back := Button.new()
	back.text = GameConfig.text("back")
	back.custom_minimum_size = Vector2(0, 56)
	back.pressed.connect(func() -> void:
		if bool(get_meta("overlay", false)):
			queue_free()
		else:
			get_tree().change_scene_to_file(GameConfig.tutorial_return_scene)
	)
	content.add_child(back)


func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label
