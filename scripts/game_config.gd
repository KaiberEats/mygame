extends Node

signal language_changed
signal ui_scale_changed

const TIME_OPTIONS: Array[int] = [5, 10, 15, 20, 25, 30]
const PLAYER_COLOR_OPTIONS := ["black", "red", "blue", "green", "purple", "pink", "cyan"]

var map_name := "Mansion"
var computer_count := 3
var deck_size := 53
var time_limit_minutes := 10
var language := "en"
var player_name := "Player"
var player_color_name := "black"
var tutorial_return_scene := "res://scenes/Title.tscn"
var ui_size_percent := 50


func _ready() -> void:
	InputMap.action_erase_events("hand_editor")
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.physical_keycode = KEY_TAB
	InputMap.action_add_event("hand_editor", tab_event)

var _translations := {
	"ja": {
		"game_start": "ゲーム開始", "tutorial": "チュートリアル", "resume": "ゲームに戻る",
		"settings": "設定", "title": "タイトルに戻る", "display": "画面設定",
		"key_controls": "キー操作", "language": "言語", "back": "戻る",
		"save_changes": "変更を保存",
		"screen": "スクリーン設定", "press_key": "キーを押してください...", "unbound": "未設定",
		"player_name": "プレイヤー名", "character_color": "キャラクターカラー", "ui_size": "UIサイズ",
		"color_black": "黒", "color_red": "赤", "color_blue": "青", "color_green": "緑", "color_purple": "紫", "color_pink": "ピンク", "color_cyan": "水色",
		"select_mode": "モード選択", "single_play": "シングルプレイ", "port": "ポート ", "host_server": "ホスト作成",
		"server_ip": "サーバーIPアドレス", "join_server": "サーバー参加", "quit_game": "ゲーム終了",
		"game_settings": "ゲーム設定", "map": "マップ", "computers": "コンピューター",
		"deck_cards": "デッキ枚数", "time_limit": "制限時間", "minutes": "%d分",
		"start_mansion": "マンションを開始", "open_settings": "設定を開く",
		"close_settings": "設定を閉じる", "deck": "デッキ", "kill": "キル", "change": "チェンジ",
		"hold_change": "チェンジ長押し", "changed": "チェンジ！", "stun": "スタン", "debug_return": "DEBUG: Classic Room",
		"killed": "キルされた！", "kill_notice": "%sをキル！", "joker_exchange": "ジョーカーは交換台で交換できない！",
		"ability_not_ready": "まだ能力は使えない！", "location_revealed": "場所がバレています", "hand_viewed": "手札を見られています",
		"win": "勝利", "place": "%d位", "result": "リザルト", "cards": "%d枚",
		"back_title": "タイトルに戻る", "drag_cards": "ドラッグして手札を並べ替え",
		"tutorial_title": "チュートリアル", "tutorial_rules": "基本ルール",
		"tutorial_rules_body": "制限時間内にペアを捨てて手札を減らします。手札が0枚になるか時間切れで終了します。\n手札が少ないほど上位ですが、ジョーカー所持者は最下位です。\nジョーカー所持者は相手をキルしてスタンさせ、チェンジできます。",
		"tutorial_controls": "操作", "tutorial_controls_body": "移動・ジャンプは設定で変更可能です。\n右クリック: ジョーカー所持時のキル / 左クリック: チェンジ / ペア1～4: カード効果 / R: ミサイル・剣・鎌・コインの使用\n能力発動後は10秒のクールタイムがあり、手札の下にゲージが表示されます。\n交換台は3枚のカードから狙ったカードを左クリック5秒長押しで交換します。\n鎌・コイン・レイピア・盾はアイテム欄に状態として表示されます。",
		"tutorial_cards": "カード効果",
	},
	"en": {
		"game_start": "Game Start", "tutorial": "Tutorial", "resume": "Resume",
		"settings": "Settings", "title": "Back to Title", "display": "Display",
		"key_controls": "Key Controls", "language": "Language", "back": "Back",
		"save_changes": "Save Changes",
		"screen": "Screen", "press_key": "Press a key...", "unbound": "Unbound",
		"player_name": "Player Name", "character_color": "Character Color", "ui_size": "UI Size",
		"color_black": "Black", "color_red": "Red", "color_blue": "Blue", "color_green": "Green", "color_purple": "Purple", "color_pink": "Pink", "color_cyan": "Light Blue",
		"select_mode": "Select Mode", "single_play": "Single Play", "port": "Port ", "host_server": "Host Server",
		"server_ip": "Server IP address", "join_server": "Join Server", "quit_game": "Quit Game",
		"game_settings": "Game Settings", "map": "Map", "computers": "Computers",
		"deck_cards": "Deck Cards", "time_limit": "Time Limit", "minutes": "%d minutes",
		"start_mansion": "Start Mansion", "open_settings": "Open game settings",
		"close_settings": "Close settings", "deck": "Deck", "kill": "Kill", "change": "Change",
		"hold_change": "Hold Change", "changed": "Change!", "stun": "Stun", "debug_return": "DEBUG: Classic Room",
		"killed": "Killed!", "kill_notice": "%s Kill!", "joker_exchange": "Joker cannot be changed at the exchange station!",
		"ability_not_ready": "Ability is not ready yet!", "location_revealed": "Location revealed", "hand_viewed": "Hand is being viewed",
		"win": "Win", "place": "%d Place", "result": "Result", "cards": "%d cards",
		"back_title": "Back to Title", "drag_cards": "Drag cards to reorder",
		"tutorial_title": "Tutorial", "tutorial_rules": "Basic Rules",
		"tutorial_rules_body": "Discard pairs to reduce your hand before time runs out. The game ends when a hand reaches zero or time expires.\nFewer cards rank higher, but the Joker holder always ranks last.\nThe Joker holder can kill, stun, and change cards with opponents.",
		"tutorial_controls": "Controls", "tutorial_controls_body": "Movement and jump keys can be changed in Settings.\nRight click: Joker kill / Left click: Change / Pair 1-4: Card effect / R: Use missile, sword, scythe, or coin\nAbilities have a 10-second cooldown after activation, shown under your hand.\nAim at one of the 3 exchange-station cards and hold left click for 5 seconds.\nScythe, coin, rapier, and shield are shown as status items in the item slot.",
		"tutorial_cards": "Card Effects",
	},
}


func text(key: String) -> String:
	return String(_translations.get(language, _translations["en"]).get(key, key))


func set_language(value: String) -> void:
	language = value
	language_changed.emit()


func set_ui_size_percent(value: int) -> void:
	ui_size_percent = clampi(value, 0, 100)
	ui_scale_changed.emit()


func player_color() -> Color:
	return color_for_name(player_color_name)


func color_for_name(color_name: String) -> Color:
	match color_name:
		"red":
			return Color(0.9, 0.08, 0.06)
		"blue":
			return Color(0.08, 0.24, 0.95)
		"green":
			return Color(0.05, 0.62, 0.16)
		"purple":
			return Color(0.5, 0.16, 0.9)
		"pink":
			return Color(1.0, 0.28, 0.68)
		"cyan":
			return Color(0.12, 0.78, 1.0)
		_:
			return Color(0.02, 0.02, 0.02)


func color_label(color_name: String) -> String:
	return text("color_%s" % color_name)


func default_deck_size_for_computers(count: int) -> int:
	var participant_count := count + 1
	return 53 + maxi(participant_count - 4, 0) * 13
