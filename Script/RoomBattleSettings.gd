## 房間設定畫面（RoomBattleSettings.tscn）——2026-09-25 拆分：原本這裡身兼
## 「房間資訊」跟「對戰規則」兩段，使用者要求拆成兩個畫面（對戰規則搬去
## 新的 BattleRules.tscn，見該檔案開頭的說明）。這個畫面現在只剩「房間
## 資訊」，只有多人（本地連線）流程會進來——單人遊玩由 Lobby.gd 直接
## change_scene_to_file 去 BattleRules.tscn，完全跳過這裡（單機沒有房間
## 可管）。
##
## 用法不變：`MultiplayerLobby.gd` 用跟原本 RoomLobby.tscn 一樣的
## instantiate/add_child 疊加模式開這裡，顯示房間名稱/密碼/人數上限/地圖/
## 玩家列表——房主可以編輯，client 唯讀。底下按鈕只有「返回」（取消連線）
## 跟「下一步」（不分房主/client，誰都可以按，各自本機切去 BattleRules.tscn
## 檢視/設定對戰規則，不需要互相等待——真正需要「大家都準備好才能開始」的
## 準備機制在 BattleRules.tscn 那邊，跟原本一樣）。
##
## 2026-09-22：版面沿用跟其他選單畫面同一套「直向/橫向各一份可排版場景檔」
## 做法（`Scenes/RoomBattleSettingsLayoutPortrait.tscn`／`...Landscape.tscn`）。
extends Control

@onready var title_label_portrait: Label = $PortraitLayout/TitleLabel
@onready var title_label_landscape: Label = $LandscapeLayout/TitleLabel
@onready var room_info_section_portrait: VBoxContainer = $PortraitLayout/SettingsScroll/SettingsList/RoomInfoSection
@onready var room_info_section_landscape: VBoxContainer = $LandscapeLayout/SettingsScroll/SettingsList/RoomInfoSection
@onready var map_option_portrait: OptionButton = $PortraitLayout/SettingsScroll/SettingsList/RoomInfoSection/MapRow/MapOption
@onready var map_option_landscape: OptionButton = $LandscapeLayout/SettingsScroll/SettingsList/RoomInfoSection/MapRow/MapOption
@onready var max_players_option_portrait: OptionButton = $PortraitLayout/SettingsScroll/SettingsList/RoomInfoSection/MaxPlayersRow/MaxPlayersOption
@onready var max_players_option_landscape: OptionButton = $LandscapeLayout/SettingsScroll/SettingsList/RoomInfoSection/MaxPlayersRow/MaxPlayersOption
@onready var room_name_edit_portrait: LineEdit = $PortraitLayout/SettingsScroll/SettingsList/RoomInfoSection/RoomNameRow/RoomNameEdit
@onready var room_name_edit_landscape: LineEdit = $LandscapeLayout/SettingsScroll/SettingsList/RoomInfoSection/RoomNameRow/RoomNameEdit
@onready var password_edit_portrait: LineEdit = $PortraitLayout/SettingsScroll/SettingsList/RoomInfoSection/PasswordRow/PasswordEdit
@onready var password_edit_landscape: LineEdit = $LandscapeLayout/SettingsScroll/SettingsList/RoomInfoSection/PasswordRow/PasswordEdit
@onready var connection_address_row_portrait: HBoxContainer = $PortraitLayout/SettingsScroll/SettingsList/RoomInfoSection/ConnectionAddressRow
@onready var connection_address_row_landscape: HBoxContainer = $LandscapeLayout/SettingsScroll/SettingsList/RoomInfoSection/ConnectionAddressRow
@onready var connection_address_edit_portrait: LineEdit = $PortraitLayout/SettingsScroll/SettingsList/RoomInfoSection/ConnectionAddressRow/ConnectionAddressEdit
@onready var connection_address_edit_landscape: LineEdit = $LandscapeLayout/SettingsScroll/SettingsList/RoomInfoSection/ConnectionAddressRow/ConnectionAddressEdit
@onready var player_list_content_portrait: VBoxContainer = $PortraitLayout/SettingsScroll/SettingsList/RoomInfoSection/PlayerListContent
@onready var player_list_content_landscape: VBoxContainer = $LandscapeLayout/SettingsScroll/SettingsList/RoomInfoSection/PlayerListContent

@onready var status_label_portrait: Label = $PortraitLayout/StatusLabel
@onready var status_label_landscape: Label = $LandscapeLayout/StatusLabel
@onready var back_button_portrait: Button = $PortraitLayout/BackButton
@onready var back_button_landscape: Button = $LandscapeLayout/BackButton
@onready var ready_button_portrait: Button = $PortraitLayout/ReadyButton
@onready var ready_button_landscape: Button = $LandscapeLayout/ReadyButton
@onready var next_button_portrait: Button = $PortraitLayout/NextButton
@onready var next_button_landscape: Button = $LandscapeLayout/NextButton

const MAP_OPTIONS: Array[Dictionary] = [
	{"id": "practice", "label": "練習場"},
]
const MAX_PLAYERS_OPTIONS: Array[int] = [1, 2, 3, 4]
## 2026-09-23：對戰同步層（BattleMatchSync/BattleDirector）從一開始就是用
## participants 字典驅動、沒有寫死配對數量，2 人連線測過穩定之後直接開放
## 到 4 人（NetworkManager.MAX_SUPPORTED_PLAYERS 這個傳輸層上限本來就是
## 4，之前只是應用層這裡刻意先鎖住 UI 選項）。
const MAX_PLAYERS_ENABLED_LIMIT := 4
const DEFAULT_MAX_PLAYERS := 2
## 2026-09-26 修正：這裡跟 BattleRules.gd 互相 preload 對方的場景，形成循環
## preload——見 BattleRules.gd 的 ROOM_SETTINGS_SCENE_PATH 那段說明。這個
## 方向（RoomBattleSettings→BattleRules）實測過沒有觸發「node count is 0」
## 那個問題（使用者流程剛好先載入這邊，這個方向是循環裡第一次解析,能正常
## 拿到完整資源），但為了不要之後載入順序一變又中招，改成跟另一邊同樣的
## 做法：只存路徑字串，需要的時候才 load()（執行期解析,不是編譯期),徹底
## 避開循環,不是只靠「這次順序剛好沒事」。
const BATTLE_RULES_SCENE_PATH := "res://Scenes/BattleRules.tscn"

var _is_owner: bool = false
var _is_ready: bool = false
## 房主端載入設定選單當下觸發的 item_selected/text_changed 不該真的送一次
## 廣播出去（那時候房間狀態還是預設值，會把 MultiplayerLobby 那邊已經送出
## 的真正設定蓋掉）。
var _initializing: bool = true
var _touch_helper_active: bool = false

func _ready() -> void:
	get_viewport().size_changed.connect(_apply_orientation_layout)
	_apply_orientation_layout()
	## 見 SafeArea.gd 開頭的說明——撐滿整個父層的 PortraitLayout 用
	## register_inset_control()。
	SafeArea.register_inset_control($PortraitLayout)

	_setup_room_info()

## 旋轉裝置、直向橫向比例翻轉時，切換顯示哪一組 PortraitLayout/
## LandscapeLayout，跟其他選單畫面同一套做法。
func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	$PortraitLayout.visible = is_portrait
	$LandscapeLayout.visible = not is_portrait

## --- 多人房間資訊（合併自舊 RoomLobby.gd） ------------------------------

func _setup_room_info() -> void:
	_setup_map_options()
	_setup_max_players_options()
	## 2026-09-25：這兩顆下拉選單拆分時漏掉了 popup 字體大小的修正（原本在
	## 合併版的 RoomBattleSettings.gd 裡跟 RoundsToWin/DamageRatio/AiLevel
	## 那幾顆一起蓋，那幾顆已經跟著搬去 BattleRules.gd，但 Map/MaxPlayers
	## 這兩顆屬於房間資訊、留在這裡卻沒有一起搬過去）——見
	## BattleRules.gd 同一段說明：OptionButton 本身的文字/它彈出的 PopupMenu
	## 是兩組獨立的 theme 設定，要另外對 get_popup() 蓋字體大小。
	for option in [map_option_portrait, max_players_option_portrait]:
		option.get_popup().add_theme_font_size_override("font_size", 40)
	MobileLineEditHelper.enable_touch_as_mouse()
	_touch_helper_active = true
	MobileLineEditHelper.setup(room_name_edit_portrait)
	MobileLineEditHelper.setup(room_name_edit_landscape)
	MobileLineEditHelper.setup(password_edit_portrait, DisplayServer.KEYBOARD_TYPE_NUMBER)
	MobileLineEditHelper.setup(password_edit_landscape, DisplayServer.KEYBOARD_TYPE_NUMBER)
	MobileLineEditHelper.enable_defocus_on_background_tap($Background)

	room_name_edit_portrait.text_changed.connect(_on_room_name_changed)
	room_name_edit_landscape.text_changed.connect(_on_room_name_changed)
	password_edit_portrait.text_changed.connect(_on_password_field_changed)
	password_edit_landscape.text_changed.connect(_on_password_field_changed)
	SoundEffects.connect_button(map_option_portrait)
	SoundEffects.connect_button(map_option_landscape)
	SoundEffects.connect_button(max_players_option_portrait)
	SoundEffects.connect_button(max_players_option_landscape)
	map_option_portrait.item_selected.connect(_on_map_option_changed)
	map_option_landscape.item_selected.connect(_on_map_option_changed)
	max_players_option_portrait.item_selected.connect(_on_max_players_option_changed)
	max_players_option_landscape.item_selected.connect(_on_max_players_option_changed)
	NetworkManager.room_state_updated.connect(_refresh_from_state)
	NetworkManager.kicked_from_room.connect(_on_kicked)
	NetworkManager.room_join_rejected.connect(_on_join_rejected)
	NetworkManager.battle_rules_advance_requested.connect(_on_battle_rules_advance_requested)

	for button in [back_button_portrait, back_button_landscape, ready_button_portrait,
			ready_button_landscape, next_button_portrait, next_button_landscape]:
		SoundEffects.connect_button(button)
	back_button_portrait.pressed.connect(_on_back_pressed)
	back_button_landscape.pressed.connect(_on_back_pressed)
	ready_button_portrait.pressed.connect(_on_ready_pressed)
	ready_button_landscape.pressed.connect(_on_ready_pressed)
	next_button_portrait.pressed.connect(_on_next_pressed)
	next_button_landscape.pressed.connect(_on_next_pressed)

	_apply_owner_mode_ui()
	_apply_connection_address_display()

	_initializing = false
	# 房主端（一般開房流程，owner 立刻就是 HOST_PEER_ID 本人）：先把畫面上的
	# 選項同步成 NetworkManager 目前真正的權威值,再送一次讓兩邊完全一致
	# （見 MultiplayerLobby._on_host_pressed() 已經帶了房間名稱，這裡不用
	# 再覆寫一次）。RemoteConnect.gd「成為伺服器」流程開房當下 owner 還沒人
	# 認領，_is_owner 這裡是 false，不會跑進這個分支，不會用空白的 UI 預設值
	# 覆蓋掉已經帶入的真正設定。
	if _is_owner and multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		room_name_edit_portrait.text = NetworkManager.room_name
		room_name_edit_landscape.text = NetworkManager.room_name
		password_edit_portrait.text = NetworkManager.room_password
		password_edit_landscape.text = NetworkManager.room_password
		var map_index := 0
		for i in MAP_OPTIONS.size():
			if MAP_OPTIONS[i]["id"] == NetworkManager.room_map_id:
				map_index = i
				break
		map_option_portrait.selected = map_index
		map_option_landscape.selected = map_index
		var players_index := MAX_PLAYERS_OPTIONS.find(NetworkManager.room_max_players)
		if players_index >= 0:
			max_players_option_portrait.selected = players_index
			max_players_option_landscape.selected = players_index
		_apply_local_settings_to_network()
	_refresh_from_state()

func _exit_tree() -> void:
	if _touch_helper_active:
		MobileLineEditHelper.restore_touch_emulation()

## 2026-09-25 第一版：加入方原本可以自己按「下一步」提前跳去對戰規則畫面，
## 跟原本合併成一頁時「加入方要等房主按開始」的規則不一致——改成只有房主
## 看得到/按得動「下一步」。
## 2026-09-25 第二版：使用者進一步要求「房主沒有第二個人不能下一步、而且
## 要下一步也要連結方玩家準備」——單純「房主可以按」還不夠，要把原本在
## BattleRules.tscn 那套「加入方按準備、房主等全員準備才能按下一步」的
## 準備機制提前搬來這裡（BattleRules.tscn 那邊現在不用再管準備狀態，見
## 該檔案的說明），這裡才是使用者要求準備的階段。
func _apply_owner_mode_ui() -> void:
	_is_owner = multiplayer.get_unique_id() == NetworkManager.room_owner_peer_id
	if _is_owner:
		_set_title_text("房間設定")
		_set_settings_editable(true)
		_set_next_button_visible(true)
		_set_ready_button_visible(false)
	else:
		_set_title_text("房間等候")
		_set_settings_editable(false)
		_set_next_button_visible(false)
		_set_ready_button_visible(true)

## 房主端：連線對戰至少要有一個其他玩家加入、而且全部準備好才能按「下一步」
## ——房主自己單獨一人時不可以按下去進對戰規則畫面（跟 TeamSelect.gd 的
## 開始鈕同一套「has_other_player and all_ready」判斷）。
func _refresh_next_button() -> void:
	if not _is_owner:
		return
	var ready_states := NetworkManager.get_ready_states()
	var has_other_player := not ready_states.is_empty()
	var all_ready := true
	for ready in ready_states.values():
		if not ready:
			all_ready = false
			break
	_set_next_button_disabled(not (has_other_player and all_ready))
	if not has_other_player:
		_set_status_text("等待其他玩家加入…")
	elif not all_ready:
		_set_status_text("等待所有玩家準備…")
	else:
		_set_status_text("")

func _on_ready_pressed() -> void:
	_is_ready = not _is_ready
	var text := "取消準備" if _is_ready else "準備"
	ready_button_portrait.text = text
	ready_button_landscape.text = text
	NetworkManager.set_ready(_is_ready)

func _apply_connection_address_display() -> void:
	var is_server_itself := multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID
	if is_server_itself and PlayitClient.has_tunnel():
		var address_text := "%s:%d" % [PlayitClient.tunnel_address, PlayitClient.tunnel_port]
		connection_address_row_portrait.show()
		connection_address_row_landscape.show()
		connection_address_edit_portrait.text = address_text
		connection_address_edit_landscape.text = address_text
	else:
		connection_address_row_portrait.hide()
		connection_address_row_landscape.hide()

## 2026-09-25 使用者回報：手機打字/刪字時游標一直跳到第一格——根因是這裡
## 原本不管使用者正在打的是 portrait 還是 landscape 那份，兩份的 .text 都
## 無條件重新賦值一次；LineEdit 的 .text setter 會把 caret 重置掉，即使賦的
## 值跟原本一模一樣也一樣會重置，所以使用者正在打字的那個欄位每打一個字
## 都被自己的 text_changed handler 反過來把自己的 caret 打斷一次。改成只
## 同步「內容真的不一樣」的那一份（也就是使用者沒有正在打的那份鏡像欄位），
## 使用者正在打字的欄位完全不去動它，caret 自然不會被打斷。
func _on_room_name_changed(new_text: String) -> void:
	if room_name_edit_portrait.text != new_text:
		room_name_edit_portrait.set_deferred("text", new_text)
		room_name_edit_portrait.set_deferred("caret_column", new_text.length())
	if room_name_edit_landscape.text != new_text:
		room_name_edit_landscape.set_deferred("text", new_text)
		room_name_edit_landscape.set_deferred("caret_column", new_text.length())
	_apply_local_settings_to_network()

func _on_password_field_changed(new_text: String) -> void:
	var digits_only := ""
	for character in new_text:
		if character.is_valid_int():
			digits_only += character
	if digits_only.length() > 4:
		digits_only = digits_only.substr(0, 4)
	# 見 _on_room_name_changed() 的說明——同一個坑，只同步內容真的不一樣的
	# 那一份，使用者正在打字的欄位（就算要濾掉非數字字元，濾完結果如果跟
	# 使用者原本打的一樣）不要去動它的 .text，caret 才不會被打斷。
	if password_edit_portrait.text != digits_only:
		password_edit_portrait.set_deferred("text", digits_only)
		password_edit_portrait.set_deferred("caret_column", digits_only.length())
	if password_edit_landscape.text != digits_only:
		password_edit_landscape.set_deferred("text", digits_only)
		password_edit_landscape.set_deferred("caret_column", digits_only.length())
	_apply_local_settings_to_network()

func _setup_map_options() -> void:
	for option in [map_option_portrait, map_option_landscape]:
		option.clear()
		for entry in MAP_OPTIONS:
			option.add_item(entry["label"])
		option.selected = 0

func _setup_max_players_options() -> void:
	for option in [max_players_option_portrait, max_players_option_landscape]:
		option.clear()
		for count in MAX_PLAYERS_OPTIONS:
			option.add_item("%d 人" % count)
		for i in MAX_PLAYERS_OPTIONS.size():
			if MAX_PLAYERS_OPTIONS[i] > MAX_PLAYERS_ENABLED_LIMIT:
				option.set_item_disabled(i, true)
				option.set_item_text(i, "%d 人（敬請期待）" % MAX_PLAYERS_OPTIONS[i])
		var default_index := MAX_PLAYERS_OPTIONS.find(DEFAULT_MAX_PLAYERS)
		option.selected = maxi(default_index, 0)

func _set_settings_editable(editable: bool) -> void:
	map_option_portrait.disabled = not editable
	map_option_landscape.disabled = not editable
	max_players_option_portrait.disabled = not editable
	max_players_option_landscape.disabled = not editable
	room_name_edit_portrait.editable = editable
	room_name_edit_landscape.editable = editable
	var focus_mode := Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	room_name_edit_portrait.focus_mode = focus_mode
	room_name_edit_landscape.focus_mode = focus_mode
	password_edit_portrait.editable = editable
	password_edit_landscape.editable = editable
	password_edit_portrait.focus_mode = focus_mode
	password_edit_landscape.focus_mode = focus_mode

func _apply_local_settings_to_network() -> void:
	if not _is_owner or _initializing:
		return
	var map_id: String = MAP_OPTIONS[map_option_portrait.selected]["id"]
	var max_players: int = MAX_PLAYERS_OPTIONS[max_players_option_portrait.selected]
	NetworkManager.update_room_settings(room_name_edit_portrait.text, max_players, password_edit_portrait.text, map_id)

func _on_map_option_changed(index: int) -> void:
	map_option_portrait.selected = index
	map_option_landscape.selected = index
	_apply_local_settings_to_network()

func _on_max_players_option_changed(index: int) -> void:
	max_players_option_portrait.selected = index
	max_players_option_landscape.selected = index
	_apply_local_settings_to_network()

func _refresh_from_state() -> void:
	_apply_owner_mode_ui()
	if not _is_owner:
		var map_index := 0
		for i in MAP_OPTIONS.size():
			if MAP_OPTIONS[i]["id"] == NetworkManager.room_map_id:
				map_index = i
				break
		map_option_portrait.selected = map_index
		map_option_landscape.selected = map_index
		var players_index := MAX_PLAYERS_OPTIONS.find(NetworkManager.room_max_players)
		if players_index >= 0:
			max_players_option_portrait.selected = players_index
			max_players_option_landscape.selected = players_index
		room_name_edit_portrait.text = NetworkManager.room_name
		room_name_edit_landscape.text = NetworkManager.room_name
		var password_text := "（已設定密碼）" if NetworkManager.room_has_password else "（無密碼）"
		password_edit_portrait.text = password_text
		password_edit_landscape.text = password_text
	_refresh_player_list()
	_refresh_next_button()

## 直向/橫向各自的 PlayerListContent 都要各生成一份列（跟 OpponentPanel／
## MultiplayerLobby 的房間列表同一套做法），不是共用同一個節點。
func _refresh_player_list() -> void:
	for child in player_list_content_portrait.get_children():
		child.queue_free()
	for child in player_list_content_landscape.get_children():
		child.queue_free()
	var owner_peer_id := NetworkManager.room_owner_peer_id
	if owner_peer_id == NetworkManager.HOST_PEER_ID:
		_add_player_row(owner_peer_id, null)
	var ready_states := NetworkManager.get_ready_states()
	for peer_id in ready_states:
		if peer_id == owner_peer_id:
			_add_player_row(peer_id, null)
		else:
			_add_player_row(peer_id, ready_states[peer_id] as bool)

func _add_player_row(peer_id: int, is_ready) -> void:
	player_list_content_portrait.add_child(_build_player_row(peer_id, is_ready))
	player_list_content_landscape.add_child(_build_player_row(peer_id, is_ready))

## 玩家列表文字 50px，跟其他選單文字比起來原本的 18px 太小；頭像用
## NetworkManager.get_peer_profile_avatar_id() 已經有跟房主/其他玩家同步過
## （見 _claim_room_owner_request()/_submit_room_password() 那幾個 RPC），
## 頭像用 custom_minimum_size 卡成正方形、跟名稱文字一樣用 vertical_alignment
## 置中，兩個視覺高度對齊。
func _build_player_row(peer_id: int, is_ready) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var avatar := TextureRect.new()
	avatar.texture = PlayerProfile.get_avatar_texture_for(NetworkManager.get_peer_profile_avatar_id(peer_id))
	avatar.custom_minimum_size = Vector2(50, 50)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(avatar)
	var name_label := Label.new()
	name_label.text = NetworkManager.get_peer_profile_name(peer_id)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 50)
	row.add_child(name_label)
	var state_label := Label.new()
	if is_ready == null:
		state_label.text = "房主"
		state_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	else:
		state_label.text = "已準備" if is_ready else "未準備"
		state_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.5) if is_ready else Color(0.7, 0.7, 0.7))
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state_label.add_theme_font_size_override("font_size", 50)
	row.add_child(state_label)
	return row

func _on_kicked(reason: String) -> void:
	_set_status_text(reason)
	back_button_portrait.disabled = true
	back_button_landscape.disabled = true
	ready_button_portrait.disabled = true
	ready_button_landscape.disabled = true
	next_button_portrait.disabled = true
	next_button_landscape.disabled = true
	await get_tree().create_timer(1.5).timeout
	queue_free()

func _on_join_rejected(reason: String) -> void:
	_set_status_text(reason)
	await get_tree().create_timer(1.5).timeout
	queue_free()

## 2026-09-25 修正：只有房主按得到這顆鈕（見 _apply_owner_mode_ui()），呼叫
## NetworkManager.advance_to_battle_rules() 讓房主之外的人也一起被帶去對戰
## 規則畫面，不是自己 queue_free() 就好——跟 TeamSelect.gd 的開始鈕同一套
## 「client 請求→host 驗證→host 廣播」慣例，真正的畫面切換動作在
## _on_battle_rules_advance_requested() 做。
func _on_next_pressed() -> void:
	NetworkManager.advance_to_battle_rules()

## NetworkManager.battle_rules_advance_requested 訊號的處理——房主/client
## 都會收到（RPC 是 call_local），疊加 BattleRules.tscn、queue_free() 自己，
## 底下的 MultiplayerLobby 本來就還活著。
func _on_battle_rules_advance_requested() -> void:
	var battle_rules_scene: PackedScene = load(BATTLE_RULES_SCENE_PATH)
	var battle_rules_instance: Control = battle_rules_scene.instantiate()
	get_parent().add_child(battle_rules_instance)
	queue_free()

## 疊在 MultiplayerLobby.tscn 上面的 overlay（跟舊 RoomLobby.tscn 一樣的
## instantiate/add_child 模式），返回只要 queue_free() 自己就好，底下的
## MultiplayerLobby（房間搜尋畫面）本來就還活著，不用重新生成。
func _on_back_pressed() -> void:
	NetworkManager.cancel()
	queue_free()

## ---- 直向/橫向兩份同步寫的小工具函式 ------------------------------------

func _set_title_text(text: String) -> void:
	title_label_portrait.text = text
	title_label_landscape.text = text

func _set_status_text(text: String) -> void:
	status_label_portrait.text = text
	status_label_landscape.text = text

func _set_next_button_visible(v: bool) -> void:
	next_button_portrait.visible = v
	next_button_landscape.visible = v

func _set_next_button_disabled(disabled: bool) -> void:
	next_button_portrait.disabled = disabled
	next_button_landscape.disabled = disabled

func _set_ready_button_visible(v: bool) -> void:
	ready_button_portrait.visible = v
	ready_button_landscape.visible = v
