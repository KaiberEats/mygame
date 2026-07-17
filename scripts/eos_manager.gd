extends Node

signal initialization_completed
signal initialization_failed(message: String)
signal login_completed(product_user_id: String)
signal login_failed(message: String)

const CREDENTIALS_PATH := "res://eos_credentials.local.cfg"
const PRODUCT_NAME := "joker"
const PRODUCT_VERSION := "0.1.0"
const REQUIRED_VALUES := [
	["product", "product_id", "PRODUCT_ID"],
	["product", "sandbox_id", "SANDBOX_ID"],
	["product", "deployment_id", "DEPLOYMENT_ID"],
	["client", "client_id", "CLIENT_ID"],
	["client", "client_secret", "CLIENT_SECRET"],
]

var is_initialized := false
var initialization_has_failed := false
var is_logged_in := false
var last_error := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	HLog.log_level = HLog.LogLevel.INFO
	HPlatform.log_msg.connect(_on_eos_log_message)
	HAuth.logged_in.connect(_on_logged_in)
	HAuth.login_error.connect(_on_login_error)
	initialize_async()


func initialize_async() -> bool:
	if is_initialized:
		return true

	var config := ConfigFile.new()
	var load_error := config.load(CREDENTIALS_PATH)
	if load_error != OK:
		return _fail_initialization(
			"EOS認証情報ファイルを読み込めません: %s" % CREDENTIALS_PATH
		)

	var missing_values := _find_missing_values(config)
	if not missing_values.is_empty():
		return _fail_initialization(
			"EOS認証情報が未入力です: %s\n%s を編集してください。" % [
				", ".join(missing_values),
				CREDENTIALS_PATH,
			]
		)

	var credentials := HCredentials.new()
	credentials.product_name = PRODUCT_NAME
	credentials.product_version = PRODUCT_VERSION
	credentials.product_id = _config_value(config, "product", "product_id")
	credentials.sandbox_id = _config_value(config, "product", "sandbox_id")
	credentials.deployment_id = _config_value(config, "product", "deployment_id")
	credentials.client_id = _config_value(config, "client", "client_id")
	credentials.client_secret = _config_value(config, "client", "client_secret")

	var setup_succeeded := await HPlatform.setup_eos_async(credentials)
	if not setup_succeeded:
		return _fail_initialization(
			"EOS Platformの初期化に失敗しました。Godotの出力ログを確認してください。"
		)

	var log_result := HPlatform.set_eos_log_level(
		EOS.Logging.LogCategory.AllCategories,
		EOS.Logging.LogLevel.Info
	)
	if not EOS.is_success(log_result):
		push_warning("EOS SDKのログレベル設定に失敗しました: %s" % EOS.result_str(log_result))

	is_initialized = true
	initialization_has_failed = false
	last_error = ""
	initialization_completed.emit()
	print("EOS Platform initialized successfully.")
	return true


func login_with_devtool_async(
	credential_name: String,
	server_url: String = "localhost:4545"
) -> bool:
	if not await _ensure_initialized_async():
		return false
	if credential_name.strip_edges().is_empty():
		return _fail_login("Developer Authentication ToolのCredential Nameが空です。")

	var succeeded := await HAuth.login_devtool_async(
		server_url.strip_edges(),
		credential_name.strip_edges()
	)
	if not succeeded:
		return _fail_login("Developer Authentication Toolによるログインに失敗しました。")
	return true


func login_with_account_portal_async() -> bool:
	if not await _ensure_initialized_async():
		return false
	var succeeded := await HAuth.login_account_portal_async()
	if not succeeded:
		return _fail_login("Epic Account Portalによるログインに失敗しました。")
	return true


func logout_async() -> bool:
	if not is_logged_in:
		return true
	var result := await HAuth.logout_async()
	if not EOS.is_success(result):
		last_error = "EOSログアウトに失敗しました: %s" % EOS.result_str(result)
		push_error(last_error)
		return false
	is_logged_in = false
	return true


func _ensure_initialized_async() -> bool:
	if is_initialized:
		return true
	return await initialize_async()


func _find_missing_values(config: ConfigFile) -> PackedStringArray:
	var missing := PackedStringArray()
	for required_value in REQUIRED_VALUES:
		var section: String = required_value[0]
		var key: String = required_value[1]
		var display_name: String = required_value[2]
		var value := _config_value(config, section, key)
		if value.is_empty() or value.begins_with("ここに_"):
			missing.append(display_name)
	return missing


func _config_value(config: ConfigFile, section: String, key: String) -> String:
	return String(config.get_value(section, key, "")).strip_edges()


func _fail_initialization(message: String) -> bool:
	initialization_has_failed = true
	last_error = message
	push_error(message)
	initialization_failed.emit(message)
	return false


func _fail_login(message: String) -> bool:
	last_error = message
	push_error(message)
	login_failed.emit(message)
	return false


func _on_logged_in() -> void:
	is_logged_in = true
	last_error = ""
	login_completed.emit(HAuth.product_user_id)
	print("EOS login succeeded. Product User ID: %s" % HAuth.product_user_id)


func _on_login_error(result_code: EOS.Result) -> void:
	_fail_login("EOSログインエラー: %s" % EOS.result_str(result_code))


func _on_eos_log_message(message: EOS.Logging.LogMessage) -> void:
	print("EOS [%s] %s" % [message.category, message.message])
