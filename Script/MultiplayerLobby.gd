extends Control
class_name MultiplayerLobby
## 連線對戰的開房/搜尋房間畫面——從 cube-combat 專案移植過來的連線骨架
## （見該專案 docs/adr/0005/0020），Tetris 對戰盤面同步邏輯還沒接上，只有
## 連線/大廳/房間等候這幾層是現成的。抄 Lobby.gd 開啟這個場景的模式：
## Lobby._on_online_battle_pressed() instantiate/add_child 這個場景、監聽
## tree_exited 知道何時關閉，這裡完全不用自己處理跟 Lobby 之間的開關邏輯。
##
## 連線成功（NetworkManager 對所有人廣播 _start_match RPC）後場景會切換到
## Board.tscn（見 NetworkManager.MATCH_SCENE_PATH）——但那只是把玩家加進
## 房間狀態，真正切換場景要等房主在 RoomLobby.tscn 按下「開始」。這裡的
## 職責收斂成「選模式／設定要開的房間／搜尋並選一個房間」，選完之後一律
## 交給 RoomLobby.tscn（見 _open_room_lobby()），不自己處理「連線成功後」
## 的畫面。

@onready var background: ColorRect = $Background
@onready var host_button: Button = $CenterContainer/Panel/Margin/Layout/ModeRow/HostModeButton
@onready var join_button: Button = $CenterContainer/Panel/Margin/Layout/ModeRow/JoinModeButton
@onready var close_button: Button = $CenterContainer/Panel/Margin/Layout/TopBar/CloseButton
@onready var status_label: Label = $CenterContainer/Panel/Margin/Layout/StatusLabel
@onready var search_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/SearchEdit
@onready var room_list_scroll: ScrollContainer = $CenterContainer/Panel/Margin/Layout/RoomListScroll
@onready var room_list_content: VBoxContainer = $CenterContainer/Panel/Margin/Layout/RoomListScroll/RoomListContent

const ROOM_BUTTON_HEIGHT := 64
const ROOM_LOBBY_SCENE: PackedScene = preload("res://Scenes/RoomLobby.tscn")
const PASSWORD_PROMPT_SCENE_STYLE_MARGIN := 24

var _room_lobby_instance: Control = null
## 點了一個有密碼保護的房間、正在跳出密碼輸入框時，先記住是哪個房間，
## 密碼輸入框確認後才真的呼叫 join_game()——見 _show_password_prompt()。
var _pending_join_room: Dictionary = {}
var _password_prompt: Control = null
var _password_prompt_edit: LineEdit = null


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	close_button.pressed.connect(_on_close_pressed)
	search_edit.text_changed.connect(_on_search_text_changed)
	MobileLineEditHelper.enable_touch_as_mouse()
	MobileLineEditHelper.setup(search_edit)
	MobileLineEditHelper.enable_defocus_on_background_tap(background)
	NetworkManager.rooms_updated.connect(_refresh_room_list)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.joined_as_client.connect(_on_joined_as_client)
	NetworkManager.room_join_rejected.connect(_on_join_rejected)
	room_list_scroll.hide()
	search_edit.hide()
	status_label.text = "選擇「開房」或「搜尋房間」"

	# 房主在 Board.tscn（見 NetworkManager.MATCH_SCENE_PATH）按下返回時
	# （NetworkManager.end_match()）會把這個場景整個當成
	# current_scene 重新載入（見 NetworkManager._end_match()），不是像平常
	# 那樣從 Lobby.tscn 疊加開啟——這裡連線本身（multiplayer_peer）從頭到尾
	# 沒斷，房主/連線端都還在房間裡，應該直接落地在 RoomLobby.tscn，不用
	# 使用者手動重新開房/搜尋加入一次。
	if multiplayer.multiplayer_peer != null:
		host_button.disabled = true
		join_button.disabled = true
		_open_room_lobby()


## 見 MobileLineEditHelper.enable_touch_as_mouse() 的說明——這個畫面關閉
## 時要對稱還原。
func _exit_tree() -> void:
	MobileLineEditHelper.restore_touch_emulation()


## 【2026-09-20】直接開房，用系統裝置 ID 前幾碼當預設房名——真正的房名/
## 密碼/人數上限/地圖交給 RoomLobby.tscn 編輯（見該檔案 _ready() 的說明：
## 進去之後會立刻補送一次完整設定），這裡先給一個堪用的預設值，不強迫
## 玩家在這個畫面就要先想好名字才能開房。
func _on_host_pressed() -> void:
	room_list_scroll.hide()
	search_edit.hide()
	host_button.disabled = true
	join_button.disabled = true
	var unique_suffix := OS.get_unique_id().substr(0, 6) if OS.get_unique_id() != "" else "房間"
	if NetworkManager.host_game("%s 的房間" % unique_suffix):
		status_label.text = ""
		_open_room_lobby()
	else:
		host_button.disabled = false
		join_button.disabled = false


func _on_join_pressed() -> void:
	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "搜尋房間中…"
	room_list_scroll.show()
	search_edit.show()
	NetworkManager.start_discovery()


func _on_search_text_changed(_new_text: String) -> void:
	_refresh_room_list()


## 【2026-09-20，見使用者需求：房名搜尋＋密碼鎖頭＋已滿鎖住】依搜尋文字
## 過濾（房名包含搜尋字串，不分大小寫），密碼保護的房間加鎖頭圖示，已滿
## 的房間顯示「已滿」並停用按鈕——都在這裡的文字/disabled 上直接處理，
## 不需要另外做自訂按鈕場景。
func _refresh_room_list() -> void:
	for child in room_list_content.get_children():
		child.queue_free()
	var rooms := NetworkManager.get_discovered_rooms()
	var filter := search_edit.text.strip_edges().to_lower()
	var filtered: Array = []
	for room in rooms:
		if filter == "" or (room["name"] as String).to_lower().contains(filter):
			filtered.append(room)
	if rooms.is_empty():
		status_label.text = "搜尋房間中…（尚未找到）"
		return
	if filtered.is_empty():
		status_label.text = "找到 %d 個房間，但沒有符合搜尋的結果" % rooms.size()
		return
	status_label.text = "找到 %d 個房間，點選加入" % filtered.size()
	for room in filtered:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, ROOM_BUTTON_HEIGHT)
		var current_players: int = room.get("current_players", 1)
		var max_players: int = room.get("max_players", 2)
		var is_full := current_players >= max_players
		var lock_icon := "🔒 " if room.get("has_password", false) else ""
		var status_text := "（已滿）" if is_full else "（%d/%d）" % [current_players, max_players]
		btn.text = "%s%s %s" % [lock_icon, room["name"], status_text]
		btn.disabled = is_full
		btn.pressed.connect(_on_room_selected.bind(room))
		room_list_content.add_child(btn)


func _on_room_selected(room: Dictionary) -> void:
	if room.get("has_password", false):
		_pending_join_room = room
		_show_password_prompt()
		return
	_start_join(room, "")


func _start_join(room: Dictionary, password: String) -> void:
	status_label.text = "連線中…"
	for child in room_list_content.get_children():
		(child as Button).disabled = true
	NetworkManager.join_game(room["address"], room["port"], password)


## 【2026-09-20，見使用者需求：密碼真的會擋人】點選有密碼保護的房間時，
## 跳出一個小輸入框，跟房間搜尋畫面同一層（加在 self 底下，蓋在房間列表
## 上面）——不用另外開一個場景檔，這個彈窗夠簡單，直接用程式碼組出來。
func _show_password_prompt() -> void:
	if is_instance_valid(_password_prompt):
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, PASSWORD_PROMPT_SCENE_STYLE_MARGIN)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "這個房間需要密碼"
	title.add_theme_font_size_override("font_size", 20)
	layout.add_child(title)

	var edit := LineEdit.new()
	edit.placeholder_text = "輸入 4 位數密碼"
	edit.max_length = 4
	edit.virtual_keyboard_enabled = false
	edit.text_changed.connect(_on_password_prompt_text_changed.bind(edit))
	MobileLineEditHelper.setup(edit, DisplayServer.KEYBOARD_TYPE_NUMBER)
	layout.add_child(edit)
	_password_prompt_edit = edit

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	layout.add_child(button_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_on_password_prompt_cancelled)
	button_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "確認"
	confirm_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	confirm_btn.pressed.connect(_on_password_prompt_confirmed)
	button_row.add_child(confirm_btn)

	edit.text_submitted.connect(func(_t: String) -> void: _on_password_prompt_confirmed())

	_password_prompt = overlay


## 見 RoomLobby._on_password_field_changed() 同一個道理——密碼是 4 位數字，
## 非數字字元直接濾掉。
func _on_password_prompt_text_changed(new_text: String, edit: LineEdit) -> void:
	var digits_only := ""
	for character in new_text:
		if character.is_valid_int():
			digits_only += character
	if digits_only.length() > 4:
		digits_only = digits_only.substr(0, 4)
	if digits_only != new_text:
		edit.set_deferred("text", digits_only)
		edit.set_deferred("caret_column", digits_only.length())


func _on_password_prompt_cancelled() -> void:
	_close_password_prompt()
	_pending_join_room = {}


func _on_password_prompt_confirmed() -> void:
	var password := _password_prompt_edit.text if is_instance_valid(_password_prompt_edit) else ""
	var room := _pending_join_room
	_close_password_prompt()
	_start_join(room, password)


func _close_password_prompt() -> void:
	if is_instance_valid(_password_prompt):
		_password_prompt.queue_free()
	_password_prompt = null
	_password_prompt_edit = null


## client 端：ENet 連線真的建立成功時呼叫——這裡還不知道密碼有沒有驗證
## 通過（那是後續的非同步 RPC），但可以先開 RoomLobby.tscn 讓玩家看到
## 「連線中/等候」的畫面，真的被拒絕的話 RoomLobby.gd 自己會處理
## room_join_rejected（見該檔案 _on_join_rejected() 的說明）。
func _on_joined_as_client() -> void:
	_open_room_lobby()


## 【2026-09-20】密碼錯誤/房間已滿——這個訊號在兩種時機都可能收到：(1)
## 還沒切到 RoomLobby.tscn 之前（正常情況，密碼驗證比 RoomLobby 生成快）
## (2) RoomLobby.tscn 已經生成了才收到（見該檔案自己也訂閱了同一個訊號
## 當防呆）。這裡只在自己還活著、RoomLobby 還沒開之前處理，已經開了就讓
## RoomLobby.gd 自己收尾，避免兩邊都想關閉/都想顯示訊息互相打架。
func _on_join_rejected(reason: String) -> void:
	if is_instance_valid(_room_lobby_instance):
		return
	status_label.text = reason
	host_button.disabled = false
	join_button.disabled = false
	for child in room_list_content.get_children():
		(child as Button).disabled = false


func _on_connection_failed(reason: String) -> void:
	status_label.text = reason
	host_button.disabled = false
	join_button.disabled = false
	room_list_scroll.hide()
	search_edit.hide()


func _open_room_lobby() -> void:
	if is_instance_valid(_room_lobby_instance):
		return
	_room_lobby_instance = ROOM_LOBBY_SCENE.instantiate()
	add_child(_room_lobby_instance)
	_room_lobby_instance.tree_exited.connect(_on_room_lobby_closed)


## RoomLobby.tscn 自己關掉（返回/被踢/密碼被拒）時呼叫——回到這個畫面
## 原本的房間搜尋狀態，讓玩家可以重新選擇開房或搜尋房間。
func _on_room_lobby_closed() -> void:
	_room_lobby_instance = null
	host_button.disabled = false
	join_button.disabled = false
	room_list_scroll.hide()
	search_edit.hide()
	status_label.text = "選擇「開房」或「搜尋房間」"


## 【2026-09-20】平常這個畫面是疊加在 Lobby.tscn 上面的子節點（見
## Lobby._on_online_battle_pressed()），關閉時 queue_free() 自己、底下的
## Lobby.tscn 本來就還活著。但房主從 Board.tscn 按返回回到房間時（見
## NetworkManager.end_match()）這個畫面是直接被當成 current_scene 整個
## 換上來的，不是疊加——這種情況下沒有「底下的 Lobby」，queue_free() 自己
## 會留下空場景樹，要改成整個換場景回 Lobby.tscn。用 get_tree().current_
## scene == self 判斷是哪一種情境，不用另外維護一個旗標。
func _on_close_pressed() -> void:
	NetworkManager.cancel()
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")
	else:
		queue_free()
