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

## 2026-09-22：版面改成跟 Lobby/Board/Battle 同一套「直向/橫向各一份可排版
## 場景檔」做法（`Scenes/MultiplayerLobbyLayoutPortrait.tscn`／
## `...Landscape.tscn`），拿掉原本 CenterContainer/PanelContainer 那套自動
## 置中框，換成每個欄位獨立節點、使用者自己排位置。會動態變化的東西（狀態
## 文字/搜尋框內容/房間列表按鈕/按鈕 disabled 狀態）兩份都要同步寫，不是只
## 寫目前生效那份——玩家隨時可能轉裝置。
@onready var background: ColorRect = $Background
@onready var portrait_layout: Control = $PortraitLayout
@onready var landscape_layout: Control = $LandscapeLayout
@onready var host_button_portrait: Button = $PortraitLayout/HostModeButton
@onready var host_button_landscape: Button = $LandscapeLayout/HostModeButton
@onready var join_button_portrait: Button = $PortraitLayout/JoinModeButton
@onready var join_button_landscape: Button = $LandscapeLayout/JoinModeButton
@onready var close_button_portrait: Button = $PortraitLayout/CloseButton
@onready var close_button_landscape: Button = $LandscapeLayout/CloseButton
@onready var status_label_portrait: Label = $PortraitLayout/StatusLabel
@onready var status_label_landscape: Label = $LandscapeLayout/StatusLabel
@onready var search_edit_portrait: LineEdit = $PortraitLayout/SearchEdit
@onready var search_edit_landscape: LineEdit = $LandscapeLayout/SearchEdit
@onready var room_list_scroll_portrait: ScrollContainer = $PortraitLayout/RoomListScroll
@onready var room_list_scroll_landscape: ScrollContainer = $LandscapeLayout/RoomListScroll
@onready var room_list_content_portrait: VBoxContainer = $PortraitLayout/RoomListScroll/RoomListContent
@onready var room_list_content_landscape: VBoxContainer = $LandscapeLayout/RoomListScroll/RoomListContent

const ROOM_BUTTON_HEIGHT := 64
## 2026-09-21 第十三輪：改成疊加 RoomBattleSettings.tscn（房間資訊＋對戰規則
## 合併成一個滿版 UI，見該檔案開頭說明），不再用舊的 RoomLobby.tscn——用法
## （instantiate/add_child 疊加模式）完全沒變，下面的註解提到 RoomLobby.tscn
## 的地方描述的還是同一套「疊上去/queue_free 收掉」慣例，只是換了場景檔案。
const ROOM_LOBBY_SCENE: PackedScene = preload("res://Scenes/RoomBattleSettings.tscn")
const PASSWORD_PROMPT_SCENE_STYLE_MARGIN := 24

var _room_lobby_instance: Control = null
## 點了一個有密碼保護的房間、正在跳出密碼輸入框時，先記住是哪個房間，
## 密碼輸入框確認後才真的呼叫 join_game()——見 _show_password_prompt()。
var _pending_join_room: Dictionary = {}
var _password_prompt: Control = null
var _password_prompt_edit: LineEdit = null


func _ready() -> void:
	host_button_portrait.pressed.connect(_on_host_pressed)
	host_button_landscape.pressed.connect(_on_host_pressed)
	join_button_portrait.pressed.connect(_on_join_pressed)
	join_button_landscape.pressed.connect(_on_join_pressed)
	close_button_portrait.pressed.connect(_on_close_pressed)
	close_button_landscape.pressed.connect(_on_close_pressed)
	search_edit_portrait.text_changed.connect(_on_search_text_changed)
	search_edit_landscape.text_changed.connect(_on_search_text_changed)
	MobileLineEditHelper.enable_touch_as_mouse()
	MobileLineEditHelper.setup(search_edit_portrait)
	MobileLineEditHelper.setup(search_edit_landscape)
	MobileLineEditHelper.enable_defocus_on_background_tap(background)
	NetworkManager.rooms_updated.connect(_refresh_room_list)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.joined_as_client.connect(_on_joined_as_client)
	NetworkManager.room_join_rejected.connect(_on_join_rejected)
	_set_room_list_visible(false)
	_set_search_edit_visible(false)
	_set_status_text("選擇「開房」或「搜尋房間」")

	get_viewport().size_changed.connect(_apply_orientation_layout)
	_apply_orientation_layout()

	# 房主在 Board.tscn（見 NetworkManager.MATCH_SCENE_PATH）按下返回時
	# （NetworkManager.end_match()）會把這個場景整個當成
	# current_scene 重新載入（見 NetworkManager._end_match()），不是像平常
	# 那樣從 Lobby.tscn 疊加開啟——這裡連線本身（multiplayer_peer）從頭到尾
	# 沒斷，房主/連線端都還在房間裡，應該直接落地在 RoomLobby.tscn，不用
	# 使用者手動重新開房/搜尋加入一次。
	if multiplayer.multiplayer_peer != null:
		_set_host_join_disabled(true)
		_open_room_lobby()

## 旋轉裝置、直向橫向比例翻轉時，切換顯示哪一組 PortraitLayout/
## LandscapeLayout，跟 Lobby.gd/Board.gd 同一套做法。
func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	portrait_layout.visible = is_portrait
	landscape_layout.visible = not is_portrait


## 見 MobileLineEditHelper.enable_touch_as_mouse() 的說明——這個畫面關閉
## 時要對稱還原。
func _exit_tree() -> void:
	MobileLineEditHelper.restore_touch_emulation()


## 【2026-09-20】直接開房，用系統裝置 ID 前幾碼當預設房名——真正的房名/
## 密碼/人數上限/地圖交給 RoomLobby.tscn 編輯（見該檔案 _ready() 的說明：
## 進去之後會立刻補送一次完整設定），這裡先給一個堪用的預設值，不強迫
## 玩家在這個畫面就要先想好名字才能開房。
func _on_host_pressed() -> void:
	_set_room_list_visible(false)
	_set_search_edit_visible(false)
	_set_host_join_disabled(true)
	var unique_suffix := OS.get_unique_id().substr(0, 6) if OS.get_unique_id() != "" else "房間"
	if NetworkManager.host_game("%s 的房間" % unique_suffix):
		_set_status_text("")
		_open_room_lobby()
	else:
		_set_host_join_disabled(false)


func _on_join_pressed() -> void:
	_set_host_join_disabled(true)
	_set_status_text("搜尋房間中…")
	_set_room_list_visible(true)
	_set_search_edit_visible(true)
	NetworkManager.start_discovery()


## 兩份 SearchEdit（直向/橫向）只有使用者正在看的那份會真的被打字，這裡先
## 把內容同步到另一份（設定 .text 不會再觸發 text_changed，不會無限迴圈），
## 這樣轉裝置時另一份不會顯示過期內容，也不影響搜尋過濾邏輯只認一份文字。
func _on_search_text_changed(new_text: String) -> void:
	search_edit_portrait.text = new_text
	search_edit_landscape.text = new_text
	_refresh_room_list()


## 【2026-09-20，見使用者需求：房名搜尋＋密碼鎖頭＋已滿鎖住】依搜尋文字
## 過濾（房名包含搜尋字串，不分大小寫），密碼保護的房間加鎖頭圖示，已滿
## 的房間顯示「已滿」並停用按鈕——都在這裡的文字/disabled 上直接處理，
## 不需要另外做自訂按鈕場景。2026-09-22：直向/橫向各自的 RoomListContent
## 都要各生成一份按鈕（跟 OpponentPanel 的做法一樣），不是共用同一個節點。
func _refresh_room_list() -> void:
	for child in room_list_content_portrait.get_children():
		child.queue_free()
	for child in room_list_content_landscape.get_children():
		child.queue_free()
	var rooms := NetworkManager.get_discovered_rooms()
	var filter := search_edit_portrait.text.strip_edges().to_lower()
	var filtered: Array = []
	for room in rooms:
		if filter == "" or (room["name"] as String).to_lower().contains(filter):
			filtered.append(room)
	if rooms.is_empty():
		_set_status_text("搜尋房間中…（尚未找到）")
		return
	if filtered.is_empty():
		_set_status_text("找到 %d 個房間，但沒有符合搜尋的結果" % rooms.size())
		return
	_set_status_text("找到 %d 個房間，點選加入" % filtered.size())
	for room in filtered:
		room_list_content_portrait.add_child(_build_room_button(room))
		room_list_content_landscape.add_child(_build_room_button(room))

func _build_room_button(room: Dictionary) -> Button:
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
	return btn


func _on_room_selected(room: Dictionary) -> void:
	if room.get("has_password", false):
		_pending_join_room = room
		_show_password_prompt()
		return
	_start_join(room, "")


func _start_join(room: Dictionary, password: String) -> void:
	_set_status_text("連線中…")
	for child in room_list_content_portrait.get_children():
		(child as Button).disabled = true
	for child in room_list_content_landscape.get_children():
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
	_set_status_text(reason)
	_set_host_join_disabled(false)
	for child in room_list_content_portrait.get_children():
		(child as Button).disabled = false
	for child in room_list_content_landscape.get_children():
		(child as Button).disabled = false


func _on_connection_failed(reason: String) -> void:
	_set_status_text(reason)
	_set_host_join_disabled(false)
	_set_room_list_visible(false)
	_set_search_edit_visible(false)


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
	_set_host_join_disabled(false)
	_set_room_list_visible(false)
	_set_search_edit_visible(false)
	_set_status_text("選擇「開房」或「搜尋房間」")

## 直向/橫向兩份都要同步寫的小工具函式，見上方檔案說明。
func _set_status_text(text: String) -> void:
	status_label_portrait.text = text
	status_label_landscape.text = text

func _set_host_join_disabled(disabled: bool) -> void:
	host_button_portrait.disabled = disabled
	host_button_landscape.disabled = disabled
	join_button_portrait.disabled = disabled
	join_button_landscape.disabled = disabled

func _set_room_list_visible(v: bool) -> void:
	room_list_scroll_portrait.visible = v
	room_list_scroll_landscape.visible = v

func _set_search_edit_visible(v: bool) -> void:
	search_edit_portrait.visible = v
	search_edit_landscape.visible = v


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
