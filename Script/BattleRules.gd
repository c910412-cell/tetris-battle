## 對戰規則畫面（BattleRules.tscn）——2026-09-25 從 RoomBattleSettings.gd 拆
## 出來。原本「房間資訊＋對戰規則」合併成一個滿版 UI，使用者現在要求拆回
## 兩個畫面：
##   - 單人遊玩：Lobby.gd 直接 change_scene_to_file 過來（不經過
##     RoomBattleSettings.tscn，那個畫面現在只剩「房間資訊」，單機沒有房間
##     可管，完全跳過），按「下一步：分隊」進 TeamSelect.tscn。
##   - 本地連線（多人）：RoomBattleSettings.gd 按「下一步」之後，本機疊加
##     這個場景（跟 RoomBattleSettings.tscn 疊在 MultiplayerLobby.tscn 上面
##     同一套 instantiate/add_child/queue_free 慣例）——房主看得到規則可以
##     編輯、底下按鈕是「開始」（全員準備才能按）；client 只能看唯讀設定、
##     底下按鈕變成「準備」/「取消準備」，跟原本 RoomBattleSettings.gd 的
##     行為完全一樣，只是換了一個畫面。
## 對戰規則欄位寫進 BattleSettings（autoload），同步機制（sync_room_rules()/
## settings_changed 訊號）維持不變，見 memory/tetris_multiplayer_battle_design.md。
extends Control

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
@onready var single_line_attack_toggle_portrait: CheckButton = $PortraitLayout/SettingsScroll/SettingsList/SingleLineAttackRow/SingleLineAttackToggle
@onready var single_line_attack_toggle_landscape: CheckButton = $LandscapeLayout/SettingsScroll/SettingsList/SingleLineAttackRow/SingleLineAttackToggle

@onready var status_label_portrait: Label = $PortraitLayout/StatusLabel
@onready var status_label_landscape: Label = $LandscapeLayout/StatusLabel
@onready var back_button_portrait: Button = $PortraitLayout/BackButton
@onready var back_button_landscape: Button = $LandscapeLayout/BackButton
@onready var ready_button_portrait: Button = $PortraitLayout/ReadyButton
@onready var ready_button_landscape: Button = $LandscapeLayout/ReadyButton
@onready var next_button_portrait: Button = $PortraitLayout/NextButton
@onready var next_button_landscape: Button = $LandscapeLayout/NextButton

## 2026-09-26 修正：這裡跟 RoomBattleSettings.gd 互相 preload 對方的場景
## （這裡 preload RoomBattleSettings.tscn，那邊 preload BattleRules.tscn），
## 形成循環 preload——Godot 載入場景時會先載入它的腳本，腳本裡的
## const X = preload(...) 是「編譯期」就要解析完成的,兩個腳本互相
## preload 對方會形成循環依賴,其中一個方向解析到一半發現對方還在載入中
## （循環），為了不卡死會直接回傳一個空的/不完整的 PackedScene（不是
## null,是「node count is 0」的無效資源）——實測過：RoomBattleSettings.gd
## 那邊 preload BattleRules.tscn 沒事（因為使用者流程上先載入
## RoomBattleSettings.tscn,它的 preload 是「第一次」進入這個循環,能正常
## 解析),但 BattleRules.gd 這邊 preload RoomBattleSettings.tscn 就是循環
## 裡「第二次」進入同一個資源,解析到一半直接回傳空殼,呼叫
## .instantiate() 就會噴「Failed to instantiate scene state ...,node
## count is 0」這個錯誤,對戰規則畫面的「返回」整個沒有作用（使用者回報
## 「按返回還是會退到連線對戰」的真正原因）。修法：改成 load()（執行期才
## 解析，不是編譯期),避開循環——真正呼叫到 _on_room_info_return_requested()
## 的時候兩個腳本早就都載入完成了,不會再撞到循環。
const ROOM_SETTINGS_SCENE_PATH := "res://Scenes/RoomBattleSettings.tscn"

var _is_multiplayer: bool = false
var _is_owner: bool = false

func _ready() -> void:
	_is_multiplayer = not BattleSettings.is_solo_mode

	## 見 RoomBattleSettings.gd 同一段說明——OptionButton 彈出的清單/SpinBox
	## 內部 LineEdit 都是各自獨立的 theme 設定，不會跟著外層的
	## theme_override_font_sizes/font_size 一起變，要另外蓋字體大小。
	for option in [rounds_to_win_option_portrait, damage_ratio_option_portrait, ai_level_option_portrait]:
		option.get_popup().add_theme_font_size_override("font_size", 40)
	for spin in [settlement_seconds_spin_portrait, garbage_cap_lines_spin_portrait]:
		spin.get_line_edit().add_theme_font_size_override("font_size", 40)

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

	for control in [assist_ghost_toggle_portrait, assist_ghost_toggle_landscape,
			time_acceleration_toggle_portrait, time_acceleration_toggle_landscape,
			rounds_to_win_option_portrait, rounds_to_win_option_landscape,
			damage_ratio_option_portrait, damage_ratio_option_landscape,
			targeted_attack_toggle_portrait, targeted_attack_toggle_landscape,
			garbage_cap_toggle_portrait, garbage_cap_toggle_landscape,
			random_piece_toggle_portrait, random_piece_toggle_landscape,
			ai_level_option_portrait, ai_level_option_landscape,
			single_line_attack_toggle_portrait, single_line_attack_toggle_landscape]:
		SoundEffects.connect_button(control)
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
	single_line_attack_toggle_portrait.toggled.connect(_on_single_line_attack_toggled)
	single_line_attack_toggle_landscape.toggled.connect(_on_single_line_attack_toggled)

	for button in [back_button_portrait, back_button_landscape, next_button_portrait, next_button_landscape]:
		SoundEffects.connect_button(button)
	back_button_portrait.pressed.connect(_on_back_pressed)
	back_button_landscape.pressed.connect(_on_back_pressed)
	next_button_portrait.pressed.connect(_on_next_pressed)
	next_button_landscape.pressed.connect(_on_next_pressed)

	get_viewport().size_changed.connect(_apply_orientation_layout)
	_apply_orientation_layout()
	## 見 SafeArea.gd 開頭的說明——撐滿整個父層的 PortraitLayout 用
	## register_inset_control()。
	SafeArea.register_inset_control($PortraitLayout)

	if _is_multiplayer:
		_setup_multiplayer()
	else:
		_set_next_button_text("下一步：分隊")
		_set_next_button_disabled(false)

func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	$PortraitLayout.visible = is_portrait
	$LandscapeLayout.visible = not is_portrait

func _setup_multiplayer() -> void:
	NetworkManager.room_state_updated.connect(_refresh_from_state)
	NetworkManager.kicked_from_room.connect(_on_kicked)
	NetworkManager.room_join_rejected.connect(_on_join_rejected)
	NetworkManager.room_info_return_requested.connect(_on_room_info_return_requested)
	_refresh_from_state()

## 2026-09-25 使用者要求的三個規則調整：
## (1) 房主這裡的按鈕文字改成「進入分隊」（原本沿用合併版的「開始」，跟
##     這個畫面現在的職責——只是最後確認規則、真正的分隊在下一個畫面——
##     對不上）。
## (2) 加入方（非房主）不應該在這個畫面看到「返回」——要離開房間只能在
##     房間設定畫面按（見 RoomBattleSettings.gd），這裡的加入方純粹唯讀
##     等待房主操作。
## (3) 房主的「返回」改成回房間設定畫面（NetworkManager.return_to_room_info()），
##     不是直接取消連線——回去之後大家要重新走一次「加入方按準備→房主按
##     下一步」，見該函式說明。
## 準備機制已經搬回房間設定畫面（使用者要求「要下一步也要連結方玩家準備」
## 提前到那一步驗證），這個畫面不用再管 ready_button/是否全員準備。
func _apply_owner_mode_ui() -> void:
	_is_owner = multiplayer.get_unique_id() == NetworkManager.room_owner_peer_id
	if _is_owner:
		_set_ready_button_visible(false)
		_set_next_button_visible(true)
		_set_next_button_text("進入分隊")
		_set_back_button_visible(true)
		_set_settings_editable(true)
		_set_status_text("")
	else:
		_set_next_button_visible(false)
		_set_ready_button_visible(false)
		_set_back_button_visible(false)
		_set_settings_editable(false)
		_set_status_text("等待房主進入分隊…")

func _on_room_info_return_requested() -> void:
	var room_settings_scene: PackedScene = load(ROOM_SETTINGS_SCENE_PATH)
	var room_settings_instance: Control = room_settings_scene.instantiate()
	get_parent().add_child(room_settings_instance)
	queue_free()

func _set_settings_editable(editable: bool) -> void:
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
	single_line_attack_toggle_portrait.disabled = not editable
	single_line_attack_toggle_landscape.disabled = not editable
	_sync_garbage_cap_lines_editable()

func _sync_garbage_cap_lines_editable() -> void:
	var editable := _is_owner and BattleSettings.garbage_cap_enabled
	if not _is_multiplayer:
		editable = BattleSettings.garbage_cap_enabled
	garbage_cap_lines_spin_portrait.editable = editable
	garbage_cap_lines_spin_landscape.editable = editable

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
	single_line_attack_toggle_portrait.button_pressed = BattleSettings.single_line_counts_as_attack
	single_line_attack_toggle_landscape.button_pressed = BattleSettings.single_line_counts_as_attack
	_sync_garbage_cap_lines_editable()

func _on_room_rules_changed() -> void:
	_populate_rule_controls_from_settings()

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

func _select_option_by_id(option: OptionButton, id: int) -> void:
	for i in range(option.item_count):
		if option.get_item_id(i) == id:
			option.select(i)
			return

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

func _on_single_line_attack_toggled(pressed: bool) -> void:
	BattleSettings.single_line_counts_as_attack = pressed
	single_line_attack_toggle_portrait.button_pressed = pressed
	single_line_attack_toggle_landscape.button_pressed = pressed
	BattleSettings.sync_room_rules()

func _refresh_from_state() -> void:
	_apply_owner_mode_ui()
	if _is_owner:
		BattleSettings.sync_room_rules()
	_refresh_next_button()

## 準備狀態已經在房間設定畫面驗證過（要進來這個畫面,房主當初一定是在
## has_other_player+all_ready 都成立的狀況下按的「下一步」),這裡只留一個
## 保險：如果對戰規則畫面開著開著唯一的其他玩家中途離開了,房主的按鈕要
## 跟著鎖起來,不能自己跟自己分隊。
func _refresh_next_button() -> void:
	if not _is_multiplayer or not _is_owner:
		return
	var has_other_player := not NetworkManager.get_ready_states().is_empty()
	_set_next_button_disabled(not has_other_player)
	_set_status_text("" if has_other_player else "等待其他玩家加入…")

## 見 RoomBattleSettings.gd 同一段說明——多人模式下這顆按鈕（房主端顯示
## 「進入分隊」）呼叫 NetworkManager.advance_to_team_select()，讓房主之外的
## 人也會一起被帶去分隊畫面；單機模式沒有連線，直接切場景。
func _on_next_pressed() -> void:
	BattleSettings.settings_changed.emit()
	if _is_multiplayer:
		BattleSettings.push_reset_team_assignments()
		NetworkManager.advance_to_team_select()
	else:
		get_tree().change_scene_to_file("res://Scenes/TeamSelect.tscn")

## 單人模式是 change_scene_to_file 直接進來的獨立場景，返回要換場景（回大廳）；
## 多人模式只有房主看得到/按得到這顆鈕（見 _apply_owner_mode_ui()），呼叫
## NetworkManager.return_to_room_info() 讓大家一起回到房間設定畫面，不是
## 直接取消連線——真正的畫面切換在 _on_room_info_return_requested() 做。
func _on_back_pressed() -> void:
	if _is_multiplayer:
		NetworkManager.return_to_room_info()
	else:
		get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")

func _set_status_text(text: String) -> void:
	status_label_portrait.text = text
	status_label_landscape.text = text

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

func _set_back_button_visible(v: bool) -> void:
	back_button_portrait.visible = v
	back_button_landscape.visible = v
