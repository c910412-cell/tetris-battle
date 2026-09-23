## 房間設定畫面（RoomBattleSettings.tscn）——2026-09-21 第十三輪合併：原本
## 「房間資訊/準備狀態」（舊 RoomLobby.gd）跟「對戰規則」是先後兩個畫面，
## 使用者要求整合成一個滿版 UI，不要分開。這個場景現在身兼兩種用途：
##   - 單人遊玩：`Lobby.gd` 直接 change_scene_to_file 過來，RoomInfoSection
##     整段隱藏（沒有真人房間可管），按「下一步：分隊」永遠可按。
##   - 本地連線（多人）：`MultiplayerLobby.gd` 用跟原本 RoomLobby.tscn 一樣的
##     instantiate/add_child 疊加模式開這裡，RoomInfoSection 顯示房間名稱/
##     密碼/人數上限/地圖/玩家準備狀態——房主看得到「對戰規則」可以編輯、
##     底下按鈕是「開始」（全員準備才能按）；client 只能看唯讀設定、底下
##     按鈕變成「準備」/「取消準備」，沒有「下一步」按鈕（要等房主按開始，
##     見 NetworkManager.start_match() 之後真正廣播切場景的說明）。
## 對戰規則欄位寫進 BattleSettings（autoload）還沒有經過 NetworkManager 的
## RPC 廣播給其他玩家——之後要同步時比照 NetworkManager.gd「client 請求→
## host 驗證→host 廣播」的慣例接上去。完整規格見
## memory/tetris_multiplayer_battle_design.md。
##
## 2026-09-22：版面改成跟其他選單畫面同一套「直向/橫向各一份可排版場景檔」
## 做法（`Scenes/RoomBattleSettingsLayoutPortrait.tscn`／`...Landscape.tscn`）。
## 內容量很大（房間資訊 5 欄+玩家列表+對戰規則 9 欄+狀態文字+3 顆按鈕），
## 逐一手排 20 幾個欄位兩次太瑣碎，所以「SettingsScroll 整塊要放在畫面哪個
## 範圍」交給使用者排（直向/橫向各自一個 ScrollContainer），裡面的欄位維持
## 原本的 VBoxContainer 自動堆疊，不用使用者一格一格排。標題/狀態文字/
## 返回/準備/下一步這幾個比較關鍵的元素則各自獨立排版。`%UniqueName` 這種
## scene-unique-name 存取法不會穿透 instance 邊界，所以全部改成明確的
## $PortraitLayout/...、$LandscapeLayout/... 路徑，會動態變化的欄位
## （選項/開關/文字/玩家列表）兩份都要同步寫，不是只寫目前生效那份。
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
@onready var battle_rules_title_portrait: Label = $PortraitLayout/SettingsScroll/SettingsList/BattleRulesTitle
@onready var battle_rules_title_landscape: Label = $LandscapeLayout/SettingsScroll/SettingsList/BattleRulesTitle

@onready var assist_ghost_toggle_portrait: CheckButton = $PortraitLayout/SettingsScroll/SettingsList/AssistGhostRow/AssistGhostToggle
@onready var assist_ghost_toggle_landscape: CheckButton = $LandscapeLayout/SettingsScroll/SettingsList/AssistGhostRow/AssistGhostToggle
@onready var time_acceleration_toggle_portrait: CheckButton = $PortraitLayout/SettingsScroll/SettingsList/TimeAccelerationRow/TimeAccelerationToggle
@onready var time_acceleration_toggle_landscape: CheckButton = $LandscapeLayout/SettingsScroll/SettingsList/TimeAccelerationRow/TimeAccelerationToggle
@onready var rounds_to_win_option_portrait: OptionButton = $PortraitLayout/SettingsScroll/SettingsList/RoundsToWinRow/RoundsToWinOption
@onready var rounds_to_win_option_landscape: OptionButton = $LandscapeLayout/SettingsScroll/SettingsList/RoundsToWinRow/RoundsToWinOption
@onready var damage_ratio_option_portrait: OptionButton = $PortraitLayout/SettingsScroll/SettingsList/DamageRatioRow/DamageRatioOption
@onready var damage_ratio_option_landscape: OptionButton = $LandscapeLayout/SettingsScroll/SettingsList/DamageRatioRow/DamageRatioOption
@onready var targeted_attack_toggle_portrait: CheckButton = $PortraitLayout/SettingsScroll/SettingsList/TargetedAttackRow/TargetedAttackToggle
@onready var targeted_attack_toggle_landscape: CheckButton = $LandscapeLayout/SettingsScroll/SettingsList/TargetedAttackRow/TargetedAttackToggle
@onready var settlement_seconds_spin_portrait: SpinBox = $PortraitLayout/SettingsScroll/SettingsList/SettlementSecondsRow/SettlementSecondsSpin
@onready var settlement_seconds_spin_landscape: SpinBox = $LandscapeLayout/SettingsScroll/SettingsList/SettlementSecondsRow/SettlementSecondsSpin
@onready var garbage_cap_toggle_portrait: CheckButton = $PortraitLayout/SettingsScroll/SettingsList/GarbageCapRow/GarbageCapToggle
@onready var garbage_cap_toggle_landscape: CheckButton = $LandscapeLayout/SettingsScroll/SettingsList/GarbageCapRow/GarbageCapToggle
@onready var garbage_cap_lines_spin_portrait: SpinBox = $PortraitLayout/SettingsScroll/SettingsList/GarbageCapLinesRow/GarbageCapLinesSpin
@onready var garbage_cap_lines_spin_landscape: SpinBox = $LandscapeLayout/SettingsScroll/SettingsList/GarbageCapLinesRow/GarbageCapLinesSpin
@onready var random_piece_toggle_portrait: CheckButton = $PortraitLayout/SettingsScroll/SettingsList/RandomPieceRow/RandomPieceToggle
@onready var random_piece_toggle_landscape: CheckButton = $LandscapeLayout/SettingsScroll/SettingsList/RandomPieceRow/RandomPieceToggle
@onready var ai_level_option_portrait: OptionButton = $PortraitLayout/SettingsScroll/SettingsList/AiLevelRow/AiLevelOption
@onready var ai_level_option_landscape: OptionButton = $LandscapeLayout/SettingsScroll/SettingsList/AiLevelRow/AiLevelOption

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

var _is_multiplayer: bool = false
var _is_owner: bool = false
var _is_ready: bool = false
## 房主端載入設定選單當下觸發的 item_selected/text_changed 不該真的送一次
## 廣播出去（那時候房間狀態還是預設值，會把 MultiplayerLobby 那邊已經送出
## 的真正設定蓋掉）。
var _initializing: bool = true
var _touch_helper_active: bool = false

func _ready() -> void:
	_is_multiplayer = not BattleSettings.is_solo_mode

	for i in range(1, 6):
		rounds_to_win_option_portrait.add_item("%d 回合" % i, i)
		rounds_to_win_option_landscape.add_item("%d 回合" % i, i)
	for n in range(1, 5):
		damage_ratio_option_portrait.add_item("1 : %d" % n, n)
		damage_ratio_option_landscape.add_item("1 : %d" % n, n)
	for i in range(BattleSettings.AI_LEVEL_NAMES.size()):
		ai_level_option_portrait.add_item(BattleSettings.AI_LEVEL_NAMES[i], i)
		ai_level_option_landscape.add_item(BattleSettings.AI_LEVEL_NAMES[i], i)

	_populate_rule_controls_from_settings()
	BattleSettings.settings_changed.connect(_on_room_rules_changed)

	assist_ghost_toggle_portrait.toggled.connect(_on_assist_ghost_toggled)
	assist_ghost_toggle_landscape.toggled.connect(_on_assist_ghost_toggled)
	time_acceleration_toggle_portrait.toggled.connect(_on_time_acceleration_toggled)
	time_acceleration_toggle_landscape.toggled.connect(_on_time_acceleration_toggled)
	rounds_to_win_option_portrait.item_selected.connect(_on_rounds_to_win_selected)
	rounds_to_win_option_landscape.item_selected.connect(_on_rounds_to_win_selected)
	damage_ratio_option_portrait.item_selected.connect(_on_damage_ratio_selected)
	damage_ratio_option_landscape.item_selected.connect(_on_damage_ratio_selected)
	targeted_attack_toggle_portrait.toggled.connect(_on_targeted_attack_toggled)
	targeted_attack_toggle_landscape.toggled.connect(_on_targeted_attack_toggled)
	settlement_seconds_spin_portrait.value_changed.connect(_on_settlement_seconds_changed)
	settlement_seconds_spin_landscape.value_changed.connect(_on_settlement_seconds_changed)
	garbage_cap_toggle_portrait.toggled.connect(_on_garbage_cap_toggled)
	garbage_cap_toggle_landscape.toggled.connect(_on_garbage_cap_toggled)
	garbage_cap_lines_spin_portrait.value_changed.connect(_on_garbage_cap_lines_changed)
	garbage_cap_lines_spin_landscape.value_changed.connect(_on_garbage_cap_lines_changed)
	random_piece_toggle_portrait.toggled.connect(_on_random_piece_toggled)
	random_piece_toggle_landscape.toggled.connect(_on_random_piece_toggled)
	ai_level_option_portrait.item_selected.connect(_on_ai_level_selected)
	ai_level_option_landscape.item_selected.connect(_on_ai_level_selected)

	back_button_portrait.pressed.connect(_on_back_pressed)
	back_button_landscape.pressed.connect(_on_back_pressed)
	ready_button_portrait.pressed.connect(_on_ready_pressed)
	ready_button_landscape.pressed.connect(_on_ready_pressed)
	next_button_portrait.pressed.connect(_on_next_pressed)
	next_button_landscape.pressed.connect(_on_next_pressed)

	get_viewport().size_changed.connect(_apply_orientation_layout)
	_apply_orientation_layout()

	if _is_multiplayer:
		_setup_room_info()
	else:
		_set_room_info_and_rules_visible(false)
		_set_title_text("房間設定")
		_set_next_button_text("下一步：分隊")
		_set_next_button_disabled(false)

## 旋轉裝置、直向橫向比例翻轉時，切換顯示哪一組 PortraitLayout/
## LandscapeLayout，跟其他選單畫面同一套做法。
func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	$PortraitLayout.visible = is_portrait
	$LandscapeLayout.visible = not is_portrait

## --- 多人房間資訊（合併自舊 RoomLobby.gd） ------------------------------

func _setup_room_info() -> void:
	_set_room_info_and_rules_visible(true)

	_setup_map_options()
	_setup_max_players_options()
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
	map_option_portrait.item_selected.connect(_on_map_option_changed)
	map_option_landscape.item_selected.connect(_on_map_option_changed)
	max_players_option_portrait.item_selected.connect(_on_max_players_option_changed)
	max_players_option_landscape.item_selected.connect(_on_max_players_option_changed)
	NetworkManager.room_state_updated.connect(_refresh_from_state)
	NetworkManager.kicked_from_room.connect(_on_kicked)
	NetworkManager.room_join_rejected.connect(_on_join_rejected)

	_apply_owner_mode_ui()
	_apply_connection_address_display()

	_initializing = false
	# 房主端（一般開房流程，owner 立刻就是 HOST_PEER_ID 本人）：畫面剛生成時
	# 的預設選項就是真正要送出去的第一份房間設定，補送一次讓 NetworkManager
	# 的房間狀態跟畫面上顯示的完全一致（見 MultiplayerLobby._on_host_pressed()
	# 已經帶了房間名稱，這裡不用再覆寫一次）。RemoteConnect.gd「成為伺服器」
	# 流程開房當下 owner 還沒人認領，_is_owner 這裡是 false，不會跑進這個
	# 分支，不會用空白的 UI 預設值覆蓋掉已經帶入的真正設定。
	if _is_owner and multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		room_name_edit_portrait.text = NetworkManager.room_name
		room_name_edit_landscape.text = NetworkManager.room_name
		_apply_local_settings_to_network()
	_refresh_from_state()

func _exit_tree() -> void:
	if _touch_helper_active:
		MobileLineEditHelper.restore_touch_emulation()

func _apply_owner_mode_ui() -> void:
	_is_owner = multiplayer.get_unique_id() == NetworkManager.room_owner_peer_id
	if _is_owner:
		_set_title_text("房間設定")
		_set_ready_button_visible(false)
		_set_next_button_visible(true)
		_set_next_button_text("開始")
		_set_settings_editable(true)
	else:
		_set_title_text("房間等候")
		_set_next_button_visible(false)
		_set_ready_button_visible(true)
		_set_settings_editable(false)

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

func _on_room_name_changed(new_text: String) -> void:
	room_name_edit_portrait.text = new_text
	room_name_edit_landscape.text = new_text
	_apply_local_settings_to_network()

func _on_password_field_changed(new_text: String) -> void:
	var digits_only := ""
	for character in new_text:
		if character.is_valid_int():
			digits_only += character
	if digits_only.length() > 4:
		digits_only = digits_only.substr(0, 4)
	password_edit_portrait.set_deferred("text", digits_only)
	password_edit_landscape.set_deferred("text", digits_only)
	if digits_only == new_text:
		# 兩份都要同步：使用者打字的那份自己保持原本的 caret，另一份只是
		# 跟著同步內容，caret 沒有意義但設定一下也無妨。
		pass
	else:
		password_edit_portrait.set_deferred("caret_column", digits_only.length())
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
	# 2026-09-23 補齊：原本只有房間資訊 4 欄會依房主身分唯讀化，9 條對戰規則
	# 列一直是誰都能改——現在規則會真的廣播出去了，非房主這邊改了也沒用
	# （送出去會被伺服器擋），UI 上乾脆一起鎖起來，不要讓非房主誤以為自己
	# 改得動。garbage_cap_lines 的 editable 比較特殊，跟另一個開關連動，見
	# _sync_garbage_cap_lines_editable()。
	assist_ghost_toggle_portrait.disabled = not editable
	assist_ghost_toggle_landscape.disabled = not editable
	time_acceleration_toggle_portrait.disabled = not editable
	time_acceleration_toggle_landscape.disabled = not editable
	rounds_to_win_option_portrait.disabled = not editable
	rounds_to_win_option_landscape.disabled = not editable
	damage_ratio_option_portrait.disabled = not editable
	damage_ratio_option_landscape.disabled = not editable
	targeted_attack_toggle_portrait.disabled = not editable
	targeted_attack_toggle_landscape.disabled = not editable
	settlement_seconds_spin_portrait.editable = editable
	settlement_seconds_spin_landscape.editable = editable
	garbage_cap_toggle_portrait.disabled = not editable
	garbage_cap_toggle_landscape.disabled = not editable
	random_piece_toggle_portrait.disabled = not editable
	random_piece_toggle_landscape.disabled = not editable
	ai_level_option_portrait.disabled = not editable
	ai_level_option_landscape.disabled = not editable
	_sync_garbage_cap_lines_editable()

## garbage_cap_lines 這個輸入框本來就有自己的「上面那個開關有沒有開」連動
## （見 _on_garbage_cap_toggled()），現在還要疊上「是不是房主」——兩個條件
## 都要滿足才真的可以編輯，任一個關掉都要鎖起來。
func _sync_garbage_cap_lines_editable() -> void:
	var editable := _is_owner and BattleSettings.garbage_cap_enabled
	if not _is_multiplayer:
		editable = BattleSettings.garbage_cap_enabled
	garbage_cap_lines_spin_portrait.editable = editable
	garbage_cap_lines_spin_landscape.editable = editable

## 把目前 BattleSettings 的 10 個規則欄位套進畫面控制項——_ready() 第一次
## 進畫面用，收到 BattleSettings.settings_changed（房主廣播回來/單機本地
## 變更）時也用同一份，兩邊不要各寫一次。
func _populate_rule_controls_from_settings() -> void:
	assist_ghost_toggle_portrait.button_pressed = BattleSettings.assist_ghost
	assist_ghost_toggle_landscape.button_pressed = BattleSettings.assist_ghost
	time_acceleration_toggle_portrait.button_pressed = BattleSettings.time_acceleration
	time_acceleration_toggle_landscape.button_pressed = BattleSettings.time_acceleration
	_select_option_by_id(rounds_to_win_option_portrait, BattleSettings.rounds_to_win)
	_select_option_by_id(rounds_to_win_option_landscape, BattleSettings.rounds_to_win)
	_select_option_by_id(damage_ratio_option_portrait, BattleSettings.damage_ratio)
	_select_option_by_id(damage_ratio_option_landscape, BattleSettings.damage_ratio)
	targeted_attack_toggle_portrait.button_pressed = BattleSettings.targeted_attack
	targeted_attack_toggle_landscape.button_pressed = BattleSettings.targeted_attack
	settlement_seconds_spin_portrait.value = BattleSettings.settlement_seconds
	settlement_seconds_spin_landscape.value = BattleSettings.settlement_seconds
	garbage_cap_toggle_portrait.button_pressed = BattleSettings.garbage_cap_enabled
	garbage_cap_toggle_landscape.button_pressed = BattleSettings.garbage_cap_enabled
	garbage_cap_lines_spin_portrait.value = BattleSettings.garbage_cap_lines
	garbage_cap_lines_spin_landscape.value = BattleSettings.garbage_cap_lines
	random_piece_toggle_portrait.button_pressed = BattleSettings.random_piece_per_player
	random_piece_toggle_landscape.button_pressed = BattleSettings.random_piece_per_player
	_select_option_by_id(ai_level_option_portrait, BattleSettings.ai_level)
	_select_option_by_id(ai_level_option_landscape, BattleSettings.ai_level)
	_sync_garbage_cap_lines_editable()

## 非房主收到房主廣播回來的規則（或單機本地變更）時，把畫面刷新成最新值
## ——房主自己廣播出去也會 call_local 觸發到這裡，用同一份值再套一次沒有
## 副作用（等於重新整理成跟自己剛剛改的一樣）。
func _on_room_rules_changed() -> void:
	_populate_rule_controls_from_settings()

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
		_add_player_row("房主", null)
	var ready_states := NetworkManager.get_ready_states()
	for peer_id in ready_states:
		if peer_id == owner_peer_id:
			_add_player_row("房主", null)
		else:
			_add_player_row("玩家", ready_states[peer_id] as bool)

func _add_player_row(label_text: String, is_ready) -> void:
	player_list_content_portrait.add_child(_build_player_row(label_text, is_ready))
	player_list_content_landscape.add_child(_build_player_row(label_text, is_ready))

func _build_player_row(label_text: String, is_ready) -> HBoxContainer:
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
	return row

## 房主端：連線對戰至少要有一個其他玩家加入、而且全部準備好才能按「開始」
## ——房主自己單獨一人時不可以按下去進分隊畫面（2026-09-21 使用者回報：
## 原本 ready_states 為空時 all_ready 空迴圈恆真，房主可以在沒人加入時就
## 直接開始，等於自己跟自己對戰，已修正）。
func _refresh_next_button() -> void:
	if not _is_multiplayer or not _is_owner:
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

func _on_kicked(reason: String) -> void:
	_set_status_text(reason)
	back_button_portrait.disabled = true
	back_button_landscape.disabled = true
	ready_button_portrait.disabled = true
	ready_button_landscape.disabled = true
	await get_tree().create_timer(1.5).timeout
	queue_free()

func _on_join_rejected(reason: String) -> void:
	_set_status_text(reason)
	await get_tree().create_timer(1.5).timeout
	queue_free()

## --- 對戰規則（原本就有，維持不變） --------------------------------------

func _select_option_by_id(option: OptionButton, id: int) -> void:
	for i in range(option.item_count):
		if option.get_item_id(i) == id:
			option.select(i)
			return

## 2026-09-23 起這 10 個 handler 改叫 BattleSettings.sync_room_rules()（取代
## 直接 emit/什麼都不做）——單機/還沒連線時等同原本行為；連線中會依房主身分
## 決定要不要真的送出去（非房主呼叫到這裡理論上不會發生，因為 UI 已經被
## _set_settings_editable() 唯讀化，這裡是保險，多呼叫一次沒有副作用）。

func _on_assist_ghost_toggled(pressed: bool) -> void:
	BattleSettings.assist_ghost = pressed
	assist_ghost_toggle_portrait.button_pressed = pressed
	assist_ghost_toggle_landscape.button_pressed = pressed
	BattleSettings.sync_room_rules()

func _on_time_acceleration_toggled(pressed: bool) -> void:
	BattleSettings.time_acceleration = pressed
	time_acceleration_toggle_portrait.button_pressed = pressed
	time_acceleration_toggle_landscape.button_pressed = pressed
	BattleSettings.sync_room_rules()

func _on_rounds_to_win_selected(index: int) -> void:
	BattleSettings.rounds_to_win = rounds_to_win_option_portrait.get_item_id(index)
	rounds_to_win_option_portrait.select(index)
	rounds_to_win_option_landscape.select(index)
	BattleSettings.sync_room_rules()

func _on_damage_ratio_selected(index: int) -> void:
	BattleSettings.damage_ratio = damage_ratio_option_portrait.get_item_id(index)
	damage_ratio_option_portrait.select(index)
	damage_ratio_option_landscape.select(index)
	BattleSettings.sync_room_rules()

func _on_targeted_attack_toggled(pressed: bool) -> void:
	BattleSettings.targeted_attack = pressed
	targeted_attack_toggle_portrait.button_pressed = pressed
	targeted_attack_toggle_landscape.button_pressed = pressed
	BattleSettings.sync_room_rules()

func _on_settlement_seconds_changed(value: float) -> void:
	BattleSettings.settlement_seconds = int(value)
	settlement_seconds_spin_portrait.value = value
	settlement_seconds_spin_landscape.value = value
	BattleSettings.sync_room_rules()

func _on_ai_level_selected(index: int) -> void:
	BattleSettings.ai_level = ai_level_option_portrait.get_item_id(index)
	ai_level_option_portrait.select(index)
	ai_level_option_landscape.select(index)
	BattleSettings.sync_room_rules()

func _on_garbage_cap_toggled(pressed: bool) -> void:
	BattleSettings.garbage_cap_enabled = pressed
	garbage_cap_toggle_portrait.button_pressed = pressed
	garbage_cap_toggle_landscape.button_pressed = pressed
	garbage_cap_lines_spin_portrait.editable = pressed
	garbage_cap_lines_spin_landscape.editable = pressed
	BattleSettings.sync_room_rules()

func _on_garbage_cap_lines_changed(value: float) -> void:
	BattleSettings.garbage_cap_lines = int(value)
	garbage_cap_lines_spin_portrait.value = value
	garbage_cap_lines_spin_landscape.value = value
	BattleSettings.sync_room_rules()

func _on_random_piece_toggled(pressed: bool) -> void:
	BattleSettings.random_piece_per_player = pressed
	random_piece_toggle_portrait.button_pressed = pressed
	random_piece_toggle_landscape.button_pressed = pressed
	BattleSettings.sync_room_rules()

## 2026-09-23 修正：多人模式下這顆按鈕（房主端顯示「開始」）原本只是本機
## 自己切場景，其他人沒有跟著切過去、卡在這個畫面——改叫
## NetworkManager.advance_to_team_select()，讓房主之外的人也會一起被帶去
## 分隊畫面（見該函式的說明）。單機模式沒有連線，維持原本直接切場景。
## 2026-09-23 再修正：使用者回報「離開對戰回房間、重新開始」這條路徑分隊
## 畫面會卡住開始不了——根因是 BattleSettings._placements 是跨場景持續存在
## 的 autoload 狀態，TeamSelect.gd 進畫面時刻意不清空它（見該檔案 _ready()
## 的說明：一般連線流程進分隊畫面時可能大家已經先分好隊了，本機自己清一次
## 會偷偷跟大家真正的狀態岔開）——但這代表上一場比賽留下的分隊結果會一路
## 殘留到下一場，可能佔掉格子或讓判斷「大家都分好隊了」的邏輯對不上目前這
## 場真正在線上的人。改成房主每次要帶大家進分隊畫面前,先用既有的
## push_reset_team_assignments()（伺服器端會再驗一次身分,非房主呼叫沒有
## 作用,可以放心一定呼叫)清空、廣播給所有人，保證每次進分隊畫面都是乾淨的
## 起點,不會有上一場的殘留。
func _on_next_pressed() -> void:
	BattleSettings.settings_changed.emit()
	if _is_multiplayer:
		BattleSettings.push_reset_team_assignments()
		NetworkManager.advance_to_team_select()
	else:
		get_tree().change_scene_to_file("res://Scenes/TeamSelect.tscn")

## 單人模式是 change_scene_to_file 直接進來的獨立場景，返回要換場景；多人
## 模式是疊在 MultiplayerLobby 上面的 overlay（跟舊 RoomLobby.tscn 一樣的
## instantiate/add_child 模式），返回只要 queue_free() 自己、底下的
## MultiplayerLobby（房間搜尋畫面）本來就還活著，不用重新生成。
func _on_back_pressed() -> void:
	if _is_multiplayer:
		NetworkManager.cancel()
		queue_free()
	else:
		get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")

## ---- 直向/橫向兩份同步寫的小工具函式 ------------------------------------

func _set_title_text(text: String) -> void:
	title_label_portrait.text = text
	title_label_landscape.text = text

func _set_status_text(text: String) -> void:
	status_label_portrait.text = text
	status_label_landscape.text = text

func _set_room_info_and_rules_visible(v: bool) -> void:
	room_info_section_portrait.visible = v
	room_info_section_landscape.visible = v
	battle_rules_title_portrait.visible = v
	battle_rules_title_landscape.visible = v

func _set_next_button_text(text: String) -> void:
	next_button_portrait.text = text
	next_button_landscape.text = text

func _set_next_button_disabled(disabled: bool) -> void:
	next_button_portrait.disabled = disabled
	next_button_landscape.disabled = disabled

func _set_next_button_visible(v: bool) -> void:
	next_button_portrait.visible = v
	next_button_landscape.visible = v

func _set_ready_button_visible(v: bool) -> void:
	ready_button_portrait.visible = v
	ready_button_landscape.visible = v
