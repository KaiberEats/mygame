extends Node

signal lobby_changed
signal search_completed(lobbies: Array[HLobby])
signal operation_failed(message: String)

const BUCKET_ID := "joker_0_1_0"
const MAX_MEMBERS := 9
const ATTR_ROOM_NAME := "ROOM_NAME"
const ATTR_GAME_VERSION := "GAME_VERSION"
const ATTR_GAME_STARTED := "GAME_STARTED"

var current_lobby: HLobby
var search_results: Array[HLobby] = []
var is_busy := false
var last_error := ""


func create_lobby_async(room_name: String) -> bool:
	if not _can_start_operation():
		return false
	if current_lobby != null and current_lobby.is_valid():
		return _fail("すでにEOS Lobbyへ参加しています。")

	is_busy = true
	var options := EOS.Lobby.CreateLobbyOptions.new()
	options.local_user_id = HAuth.product_user_id
	options.bucket_id = BUCKET_ID
	options.max_lobby_members = MAX_MEMBERS
	options.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	options.presence_enabled = true
	options.allow_invites = true
	options.enable_join_by_id = false
	options.enable_rtc_room = false

	var lobby := await HLobbies.create_lobby_async(options)
	if lobby == null:
		is_busy = false
		return _fail("EOS Lobbyの作成に失敗しました。")

	current_lobby = lobby
	_connect_current_lobby_signals()
	current_lobby.add_attribute(ATTR_ROOM_NAME, _normalized_room_name(room_name))
	current_lobby.add_attribute(ATTR_GAME_VERSION, EOSManager.PRODUCT_VERSION)
	current_lobby.add_attribute(ATTR_GAME_STARTED, false)
	if not await current_lobby.update_async():
		await _close_current_lobby_async()
		is_busy = false
		return _fail("EOS Lobby属性の設定に失敗しました。")

	is_busy = false
	last_error = ""
	lobby_changed.emit()
	return true


func search_lobbies_async() -> Array[HLobby]:
	if not _can_start_operation():
		return []
	is_busy = true
	var result = await HLobbies.search_by_bucket_id_async(BUCKET_ID)
	is_busy = false
	if result == null:
		_fail("EOS Lobbyの検索に失敗しました。")
		return []

	search_results.clear()
	for lobby in result:
		if lobby is HLobby:
			search_results.append(lobby)
	last_error = ""
	search_completed.emit(search_results)
	return search_results


func join_lobby_async(result_index: int) -> bool:
	if not _can_start_operation():
		return false
	if current_lobby != null and current_lobby.is_valid():
		return _fail("すでにEOS Lobbyへ参加しています。")
	if result_index < 0 or result_index >= search_results.size():
		return _fail("参加するEOS Lobbyを選択してください。")

	is_busy = true
	var joined_lobby := await HLobbies.join_async(search_results[result_index]) as HLobby
	is_busy = false
	if joined_lobby == null:
		return _fail("EOS Lobbyへの参加に失敗しました。")

	current_lobby = joined_lobby
	_connect_current_lobby_signals()
	last_error = ""
	lobby_changed.emit()
	return true


func leave_lobby_async() -> bool:
	if is_busy:
		return false
	if current_lobby == null or not current_lobby.is_valid():
		return _fail("参加中のEOS Lobbyがありません。")

	is_busy = true
	var succeeded := await _close_current_lobby_async()
	is_busy = false
	if not succeeded:
		return _fail("EOS Lobbyの退出または解散に失敗しました。")

	last_error = ""
	lobby_changed.emit()
	return true


func is_in_lobby() -> bool:
	return current_lobby != null and current_lobby.is_valid()


func current_room_name() -> String:
	if not is_in_lobby():
		return ""
	return room_name_for(current_lobby)


func current_member_count() -> int:
	return current_lobby.members.size() if is_in_lobby() else 0


func room_name_for(lobby: HLobby) -> String:
	if lobby == null:
		return ""
	var attribute = lobby.get_attribute(ATTR_ROOM_NAME)
	if attribute is Dictionary and attribute.has("value"):
		return String(attribute.value)
	return "Unnamed Room"


func lobby_summary(lobby: HLobby) -> String:
	if lobby == null:
		return ""
	return "%s  (%d/%d)" % [room_name_for(lobby), lobby.members.size(), lobby.max_members]


func _can_start_operation() -> bool:
	if is_busy:
		return _fail("EOS Lobby処理を実行中です。")
	if not EOSManager.is_logged_in or HAuth.product_user_id.is_empty():
		return _fail("先にEOSへログインしてください。")
	return true


func _connect_current_lobby_signals() -> void:
	if current_lobby == null:
		return
	if not current_lobby.lobby_updated.is_connected(_on_lobby_updated):
		current_lobby.lobby_updated.connect(_on_lobby_updated)
	if not current_lobby.kicked_from_lobby.is_connected(_on_removed_from_lobby):
		current_lobby.kicked_from_lobby.connect(_on_removed_from_lobby)


func _close_current_lobby_async() -> bool:
	if current_lobby == null or not current_lobby.is_valid():
		current_lobby = null
		return true
	var lobby := current_lobby
	var succeeded: bool
	if lobby.is_owner():
		succeeded = await lobby.destroy_async()
	else:
		succeeded = await lobby.leave_async()
	if succeeded:
		current_lobby = null
	return succeeded


func _normalized_room_name(room_name: String) -> String:
	var normalized := room_name.strip_edges()
	return normalized.left(32) if not normalized.is_empty() else "Joker Room"


func _fail(message: String) -> bool:
	last_error = message
	push_error(message)
	operation_failed.emit(message)
	return false


func _on_lobby_updated() -> void:
	lobby_changed.emit()


func _on_removed_from_lobby() -> void:
	current_lobby = null
	lobby_changed.emit()
