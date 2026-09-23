extends Control
class_name RoomLobby

## 【2026-09-20，見使用者需求：開房設定畫面＋房間等候畫面】房主按下「開房」
## 或 client 成功加入房間後顯示的畫面——房主/client 共用同一個場景，靠
## multiplayer.get_unique_id() == NetworkManager.room_owner_peer_id 切換
## 「可編輯設定＋開始按鈕」跟「唯讀顯示＋準備按鈕」兩種模式，不需要維護
## 兩份幾乎一樣的畫面。MultiplayerLobby.gd 用跟 BehaviorSlotUI 一樣的
## instantiate/add_child/tree_exited 模式開啟這裡，不用自己處理跟上一層的
## 開關邏輯——這裡 queue_free() 時，底下的 MultiplayerLobby（房間搜尋畫面）
## 本來就還活著，直接看得到，不用重新生成。
##
## 【2026-09-20，見使用者需求：電腦當無頭伺服器，房主身分由遠端手機用
## 代碼認領】房主不再保證是 HOST_PEER_ID 本人（見 NetworkManager.
## room_owner_peer_id 的說明）：
## - 一般 MultiplayerLobby「開房」流程：owner 立刻就是 HOST_PEER_ID，跟
##   改動前行為完全一樣。
## - RemoteConnect.gd「成為伺服器」流程：這台電腦開房當下 owner 還沒人
##   認領（-1），這裡的畫面會落在「唯讀等候」模式，不會誤顯示成房主。
## - RemoteConnect.gd「連結伺服器」流程：房主身分是連線成功後才透過
##   NetworkManager 的認領 RPC 非同步取得，這個畫面可能先以「還不是房主」
##   的狀態顯示出來，等 room_state_updated 送達才變成房主模式——見
##   _apply_owner_mode_ui() 每次 _refresh_from_state() 都會重新判斷，不是
##   只在 _ready() 判斷一次。

@onready var background: ColorRect = $Background
@onready var title_label: Label = $CenterContainer/Panel/Margin/Layout/TopBar/TitleLabel
@onready var back_button: Button = $CenterContainer/Panel/Margin/Layout/TopBar/BackButton
@onready var map_option: OptionButton = $CenterContainer/Panel/Margin/Layout/SettingsSection/MapRow/MapOption
@onready var max_players_option: OptionButton = $CenterContainer/Panel/Margin/Layout/SettingsSection/MaxPlayersRow/MaxPlayersOption
@onready var room_name_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/SettingsSection/RoomNameRow/RoomNameEdit
@onready var password_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/SettingsSection/PasswordRow/PasswordEdit
@onready var connection_address_row: HBoxContainer = $CenterContainer/Panel/Margin/Layout/SettingsSection/ConnectionAddressRow
@onready var connection_address_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/SettingsSection/ConnectionAddressRow/ConnectionAddressEdit
@onready var player_list_content: VBoxContainer = $CenterContainer/Panel/Margin/Layout/PlayerListScroll/PlayerListContent
@onready var status_label: Label = $CenterContainer/Panel/Margin/Layout/StatusLabel
@onready var ready_button: Button = $CenterContainer/Panel/Margin/Layout/BottomBar/ReadyButton
@onready var start_button: Button = $CenterContainer/Panel/Margin/Layout/BottomBar/StartButton

## 地圖清單先寫死在腳本常數，不用另外拉一份資源檔——目前真的能選的只有
## 「練習場」一個，之後真的有第二張地圖時再擴充這個陣列即可，UI/存取邏輯
## 都不用跟著改。
const MAP_OPTIONS: Array[Dictionary] = [
	{"id": "practice", "label": "練習場"},
]
## 【2026-09-20，見使用者需求釐清：人數上限 1~4】index 對應「包含房主自己
## 的總人數上限」實際數字。2026-09-23：跟 RoomBattleSettings.gd 同步開放到
## 4 人（這個檔案是舊版、已被 RoomBattleSettings.tscn 取代的死碼，見
## MultiplayerLobby.gd 的說明，這裡只是保持跟現役版本一致，不會被實際跑到）。
const MAX_PLAYERS_OPTIONS: Array[int] = [1, 2, 3, 4]
const MAX_PLAYERS_ENABLED_LIMIT := 4
const DEFAULT_MAX_PLAYERS := 2

var _is_owner: bool = false
var _is_ready: bool = false
## 見 _apply_local_settings_to_network() 的說明——房主端載入設定選單當下
## 觸發的 item_selected/text_changed 不該真的送一次廣播出去（那時候還沒
## 真的呼叫 host_game()／NetworkManager 的房間狀態還是預設值，會把使用者
## 從 MultiplayerLobby 那邊已經送出的真正設定蓋掉）。
var _initializing: bool = true


func _ready() -> void:
	_setup_map_options()
	_setup_max_players_options()
	MobileLineEditHelper.enable_touch_as_mouse()
	MobileLineEditHelper.setup(room_name_edit)
	MobileLineEditHelper.setup(password_edit, DisplayServer.KEYBOARD_TYPE_NUMBER)
	MobileLineEditHelper.enable_defocus_on_background_tap(background)

	back_button.pressed.connect(_on_back_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	room_name_edit.text_changed.connect(_on_settings_field_changed)
	password_edit.text_changed.connect(_on_password_field_changed)
	map_option.item_selected.connect(_on_settings_option_changed)
	max_players_option.item_selected.connect(_on_settings_option_changed)
	NetworkManager.room_state_updated.connect(_refresh_from_state)
	NetworkManager.kicked_from_room.connect(_on_kicked)
	NetworkManager.room_join_rejected.connect(_on_join_rejected)

	_apply_owner_mode_ui()
	_apply_connection_address_display()

	_initializing = false
	# 房主端（一般開房流程,owner 立刻就是 HOST_PEER_ID 本人）：畫面剛生成時
	# 的預設選項（人數上限預設 2、地圖預設第一個、房名/密碼欄位空白）就是
	# 真正要送出去的第一份房間設定，見 MultiplayerLobby._on_host_pressed()
	# 的說明——那邊呼叫 host_game() 已經帶了使用者取的房間名稱，這裡不用
	# 再覆寫一次房名，只補送一次完整設定讓 NetworkManager 的房間狀態跟畫面
	# 上顯示的完全一致。RemoteConnect.gd「成為伺服器」流程開房當下 owner
	# 還沒人認領，_is_owner 這裡是 false，不會跑進這個分支，不會用空白的
	# UI 預設值覆蓋掉 host_game() 呼叫時已經帶入的真正設定。
	if _is_owner and multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		room_name_edit.text = NetworkManager.room_name
		_apply_local_settings_to_network()
	_refresh_from_state()


## 【2026-09-20，見使用者需求：電腦當無頭伺服器，房主身分由遠端手機用
## 代碼認領】拆出來獨立呼叫，不是只在 _ready() 判斷一次——「連結伺服器」
## 流程下，這個畫面可能先以「還不是房主」開啟（認領 RPC 還在網路上），
## 等 room_state_updated 真的送達才變成房主，見 _refresh_from_state()
## 也會呼叫這裡重新判斷。
func _apply_owner_mode_ui() -> void:
	_is_owner = multiplayer.get_unique_id() == NetworkManager.room_owner_peer_id
	if _is_owner:
		title_label.text = "房間設定"
		ready_button.hide()
		start_button.show()
		_set_settings_editable(true)
	else:
		title_label.text = "房間等候"
		start_button.hide()
		ready_button.show()
		_set_settings_editable(false)


## 【2026-09-20，見使用者回報「房間等候畫面看不到連線位址，手機不知道要
## 填什麼」】RemoteConnect.gd「成為伺服器」流程建好通道後，位址只顯示在
## 那個畫面的欄位裡——一旦 RoomLobby 疊在上面，操作電腦的人就再也看不到
## 那組位址了，除非按返回（會整個取消房間）。這裡在「架站的這台電腦自己」
## 的畫面上常駐顯示一次，不用離開房間畫面就能複製給要連進來的人。只有
## 伺服器本人（HOST_PEER_ID）看得到，且真的有通道時才顯示——一般玩家/
## 認領到房主身分的遠端手機都不需要看這個（他們是連進來的那一端，不是
## 架站的那一端）。
func _apply_connection_address_display() -> void:
	var is_server_itself := multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID
	if is_server_itself and PlayitClient.has_tunnel():
		connection_address_row.show()
		connection_address_edit.text = "%s:%d" % [PlayitClient.tunnel_address, PlayitClient.tunnel_port]
	else:
		connection_address_row.hide()


## 見 MobileLineEditHelper.enable_touch_as_mouse() 的說明——這個畫面關閉
## 時要對稱還原，不能只靠 _ready() 開的那一份一直留著。
func _exit_tree() -> void:
	MobileLineEditHelper.restore_touch_emulation()


## 見使用者需求：密碼設四位數就好——這裡只接受數字、最多 4 碼，非數字
## 字元直接濾掉（例如貼上帶了空白或符號的文字）。用 set_deferred 修改
## text，避免在 text_changed 訊號正在處理的當下又立刻觸發一次同一個訊號
## 造成重入。
func _on_password_field_changed(new_text: String) -> void:
	var digits_only := ""
	for character in new_text:
		if character.is_valid_int():
			digits_only += character
	if digits_only.length() > 4:
		digits_only = digits_only.substr(0, 4)
	if digits_only != new_text:
		password_edit.set_deferred("text", digits_only)
		password_edit.set_deferred("caret_column", digits_only.length())
	_apply_local_settings_to_network()


func _setup_map_options() -> void:
	map_option.clear()
	for entry in MAP_OPTIONS:
		map_option.add_item(entry["label"])
	map_option.selected = 0


## 見 MAX_PLAYERS_ENABLED_LIMIT 的說明——3/4 人現在選項本身還在，但設成
## disabled 並在文字後面加註記，玩家看得到「以後會開放」但選不了。
func _setup_max_players_options() -> void:
	max_players_option.clear()
	for count in MAX_PLAYERS_OPTIONS:
		max_players_option.add_item("%d 人" % count)
	for i in MAX_PLAYERS_OPTIONS.size():
		if MAX_PLAYERS_OPTIONS[i] > MAX_PLAYERS_ENABLED_LIMIT:
			max_players_option.set_item_disabled(i, true)
			max_players_option.set_item_text(i, "%d 人（敬請期待）" % MAX_PLAYERS_OPTIONS[i])
	var default_index := MAX_PLAYERS_OPTIONS.find(DEFAULT_MAX_PLAYERS)
	max_players_option.selected = maxi(default_index, 0)


## 【2026-09-20，見使用者需求：唯讀欄位點下去不該有反應】只設定
## editable=false 不夠——Godot 的 LineEdit 點擊聚焦（grab_click_focus）不
## 看 editable，唯讀欄位一樣會被點成焦點，手機因此照樣彈出虛擬鍵盤、
## 電腦照樣看得到游標跑進去，只是打字沒有效果，跟「點了完全沒反應」的
## 需求不一樣。額外把 focus_mode 關掉（FOCUS_NONE）：Godot 的
## grab_focus() 對 focus_mode == FOCUS_NONE 的節點是直接跳過的 no-op，
## 點擊唯讀欄位就真的不會聚焦，MobileLineEditHelper 掛在 focus_entered
## 上的虛擬鍵盤呼叫自然也不會觸發，不用在 helper 那邊另外加判斷。
func _set_settings_editable(editable: bool) -> void:
	map_option.disabled = not editable
	max_players_option.disabled = not editable
	room_name_edit.editable = editable
	room_name_edit.focus_mode = FOCUS_ALL if editable else FOCUS_NONE
	password_edit.editable = editable
	password_edit.focus_mode = FOCUS_ALL if editable else FOCUS_NONE


## 房主本機修改設定的共用入口——不管是哪個欄位觸發，一律重新讀一次全部
## 四個欄位目前的值送給 NetworkManager，不用每個欄位各自組一份 payload
## （update_room_settings() 本來就是整包覆寫，見該函式的說明）。
func _apply_local_settings_to_network() -> void:
	if not _is_owner or _initializing:
		return
	var map_id: String = MAP_OPTIONS[map_option.selected]["id"]
	var max_players: int = MAX_PLAYERS_OPTIONS[max_players_option.selected]
	NetworkManager.update_room_settings(room_name_edit.text, max_players, password_edit.text, map_id)


func _on_settings_option_changed(_index: int) -> void:
	_apply_local_settings_to_network()


func _on_settings_field_changed(_new_text: String) -> void:
	_apply_local_settings_to_network()


## NetworkManager.room_state_updated 觸發時呼叫——房主/client 共用同一套
## 刷新邏輯。client 端（唯讀）直接把收到的權威值寫回畫面；房主端不覆寫
## 自己正在編輯的欄位（自己本機的輸入永遠是最新的，不需要等廣播繞一圈
## 回來才顯示，也避免使用者打字打到一半畫面被自己剛送出的廣播蓋掉）。
func _refresh_from_state() -> void:
	_apply_owner_mode_ui()
	if not _is_owner:
		var map_index := 0
		for i in MAP_OPTIONS.size():
			if MAP_OPTIONS[i]["id"] == NetworkManager.room_map_id:
				map_index = i
				break
		map_option.selected = map_index
		var players_index := MAX_PLAYERS_OPTIONS.find(NetworkManager.room_max_players)
		if players_index >= 0:
			max_players_option.selected = players_index
		room_name_edit.text = NetworkManager.room_name
		# client 端唯讀——不知道也不需要知道真正密碼字串（host 端才看得到，
		# 見 password_edit 節點的 secret 屬性已經移除），這裡只顯示「有沒有
		# 設密碼」，不用假的星號字元數量誤導使用者密碼長度。
		password_edit.text = "（已設定密碼）" if NetworkManager.room_has_password else "（無密碼）"
	_refresh_player_list()
	_refresh_start_button()


## 【2026-09-20】目前沒有玩家暱稱系統（見使用者需求釐清：這次只做房間
## 名稱，不牽涉玩家暱稱），玩家列表只能顯示「房主」/「玩家」＋準備狀態，
## 不是個人化的名字——之後如果要顯示暱稱，這裡是唯一要改的地方。
##
## 【2026-09-20，見使用者需求：電腦當無頭伺服器，房主身分由遠端手機用
## 代碼認領】伺服器本人（HOST_PEER_ID）不一定是房主——是的話顯示「房主」
## （跟改動前一樣），不是的話（純中繼站）完全不顯示這一行，因為它不算
## 玩家、不佔人數（見 NetworkManager._current_player_count() 的說明），
## 顯示出來只會誤導使用者以為它占用了一個名額。真正的房主（另外那個遠端
## 認領到權限的玩家）會在下面 ready_states 迴圈裡以「房主」顯示。
func _refresh_player_list() -> void:
	for child in player_list_content.get_children():
		child.queue_free()
	var owner_peer_id := NetworkManager.room_owner_peer_id
	if owner_peer_id == NetworkManager.HOST_PEER_ID:
		_add_player_row("房主", null)
	var ready_states := NetworkManager.get_ready_states()
	for peer_id in ready_states:
		if peer_id == owner_peer_id:
			_add_player_row("房主", null)
		else:
			_add_player_row("玩家", ready_states[peer_id] as bool)


func _add_player_row(label_text: String, is_ready) -> void:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 18)
	row.add_child(name_label)
	var state_label := Label.new()
	if is_ready == null:
		state_label.text = "房主"
		state_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	else:
		state_label.text = "已準備" if is_ready else "未準備"
		state_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.5) if is_ready else Color(0.7, 0.7, 0.7))
	state_label.add_theme_font_size_override("font_size", 18)
	row.add_child(state_label)
	player_list_content.add_child(row)


## 房主端：所有連線中的玩家都準備好才能按「開始」，單人房間（沒有其他人
## 連進來）不用等任何人，見 NetworkManager.start_match() 的說明。
func _refresh_start_button() -> void:
	if not _is_owner:
		return
	var ready_states := NetworkManager.get_ready_states()
	var all_ready := true
	for ready in ready_states.values():
		if not ready:
			all_ready = false
			break
	start_button.disabled = not all_ready
	status_label.text = "" if all_ready else "等待所有玩家準備…"


func _on_back_pressed() -> void:
	NetworkManager.cancel()
	queue_free()


func _on_ready_pressed() -> void:
	_is_ready = not _is_ready
	ready_button.text = "取消準備" if _is_ready else "準備"
	NetworkManager.set_ready(_is_ready)


## 2026-09-21 起：按「開始」不再直接 NetworkManager.start_match()（那個是真的
## 把大家送進 Board.tscn），改成先進房主專屬的對戰規則設定畫面
## （RoomBattleSettings.tscn）→ 分隊畫面（TeamSelect.tscn），設定/分隊都完成後
## 才由 TeamSelect.gd 呼叫 NetworkManager.start_match()。見
## memory/tetris_multiplayer_battle_design.md 的規格記錄。
func _on_start_pressed() -> void:
	BattleSettings.is_solo_mode = false
	get_tree().change_scene_to_file("res://Scenes/RoomBattleSettings.tscn")


## 房主在等候階段離開/斷線（見 NetworkManager._on_server_disconnected()
## 的說明）——短暫顯示訊息後自己關掉，退回底下還活著的房間搜尋畫面。
func _on_kicked(reason: String) -> void:
	status_label.text = reason
	back_button.disabled = true
	ready_button.disabled = true
	await get_tree().create_timer(1.5).timeout
	queue_free()


## 理論上不會在這個畫面收到——密碼錯誤/房間已滿是在「點選房間」那一刻
## （MultiplayerLobby 還沒切換進這個畫面）就會被拒絕，這裡是防呆，避免
## 極端時序下這個畫面已經生成、才收到遲到的拒絕訊息卡住不會消失。
func _on_join_rejected(reason: String) -> void:
	status_label.text = reason
	await get_tree().create_timer(1.5).timeout
	queue_free()
