## 分隊畫面（TeamSelect.tscn）。4×3 格子＝4 個隊伍（紅黃綠藍，直的四條顏色）
## 各佔一欄、每欄 3 格（跟 BattleSettings.MAX_PLAYERS_PER_TEAM 一致，2026-09-21
## 從原本的 4×4 改過來——原本第 4 格永遠禁用顯示灰色「—」，沒有意義，拿掉）。
## 見 memory 規格「為什麼固定開 4 隊」的說明：保留 4 隊是為了保證一定有對抗
## 目標，不是把單隊人數上限放寬。
##
## 互動規則（2026-09-21 確認版）：
##   - 點空格：多人連線模式下＝把自己移過去；單人模式下＝依序加入下一個身分
##     （玩家自己先上場，之後每點一次空格依序補上一隻 AI，最多 3 隻）。
##   - 點已經有人的格子：那個人（不分玩家或 AI）直接被請下場——多人連線模式
##     下只有點自己的格子才有效，不能踢真人隊友。
##   - 拖曳：把一格拖到另一格，會把兩邊的人互換／搬過去（`TeamSelectCell.gd`
##     實作實際拖放事件，這裡提供 can_drag_cell()/can_drop_on_cell()/
##     handle_cell_drop() 給它呼叫）。
##
## 這次先做本地單機可測試版本，「其他真人玩家選了誰」還沒接 NetworkManager 的
## RPC 廣播。完整規格見 memory/tetris_multiplayer_battle_design.md。
extends Control

const CellScript := preload("res://Script/TeamSelectCell.gd")

## 2026-09-22：版面改成跟其他選單畫面同一套「直向/橫向各一份可排版場景檔」
## 做法（`Scenes/TeamSelectLayoutPortrait.tscn`／`...Landscape.tscn`）。
## `%UniqueName` 這種 scene-unique-name 存取法只在「同一份場景檔內」有效、
## 不會穿透 instance 邊界，所以改成明確的 $PortraitLayout/...、
## $LandscapeLayout/... 路徑。TeamGrid（4×3 拖放格子）本身維持動態生成
## ——不是把 12 個格子個別手排位置（那樣會打斷 TeamSelectCell.gd 的拖放
## index 邏輯），而是把「整個 GridContainer 放在哪個範圍」交給使用者排，
## 裡面的 12 顆格子還是程式生成，直向/橫向各生成一份（跟 OpponentPanel 同
## 一套做法），操作其中一份會透過共用的 BattleSettings 狀態同步反映到另一份。
@onready var portrait_layout: Control = $PortraitLayout
@onready var landscape_layout: Control = $LandscapeLayout
@onready var grid_portrait: GridContainer = $PortraitLayout/TeamGrid
@onready var grid_landscape: GridContainer = $LandscapeLayout/TeamGrid
@onready var start_button_portrait: Button = $PortraitLayout/StartButton
@onready var start_button_landscape: Button = $LandscapeLayout/StartButton
@onready var ready_button_portrait: Button = $PortraitLayout/ReadyButton
@onready var ready_button_landscape: Button = $LandscapeLayout/ReadyButton
@onready var back_button_portrait: Button = $PortraitLayout/BackButton
@onready var back_button_landscape: Button = $LandscapeLayout/BackButton
@onready var status_label_portrait: Label = $PortraitLayout/StatusLabel
@onready var status_label_landscape: Label = $LandscapeLayout/StatusLabel

var _cells_portrait: Array = []
var _cells_landscape: Array = []
var _local_peer_id: int = 1
## 2026-09-23：跟 RoomBattleSettings.gd 同一套「房主看得到開始鈕、其他人
## 只看得到準備鈕」模式——單機模式沒有房主/其他人的分別，永遠當成
## _is_owner=true（維持原本單機行為：只有一顆開始鈕）。
var _is_owner: bool = false
var _is_ready: bool = false

func _ready() -> void:
	_local_peer_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	_is_owner = BattleSettings.is_solo_mode or multiplayer.get_unique_id() == NetworkManager.room_owner_peer_id
	# 2026-09-23：連線模式不要在這裡清空——BattleSettings._placements 是跨場景
	# 持續存在的 autoload 狀態，這個畫面載入時如果已經連上線，代表房主/其他人
	# 可能已經先分好隊了，各自清一次自己本機那份會馬上跟大家對不上（而且沒有
	# 廣播出去，等於偷偷把畫面跟真正狀態岔開）。只有單機/還沒連線時才清，跟
	# 「這是全新一局，把上一局的分隊清掉重來」這個意圖一致。
	if BattleSettings.is_solo_mode or not multiplayer.has_multiplayer_peer():
		BattleSettings.reset_team_assignments()
	_cells_portrait = _build_grid(grid_portrait)
	_cells_landscape = _build_grid(grid_landscape)
	_apply_owner_mode_ui()
	_refresh_grid()
	start_button_portrait.pressed.connect(_on_start_pressed)
	start_button_landscape.pressed.connect(_on_start_pressed)
	ready_button_portrait.pressed.connect(_on_ready_pressed)
	ready_button_landscape.pressed.connect(_on_ready_pressed)
	back_button_portrait.pressed.connect(_on_back_pressed)
	back_button_landscape.pressed.connect(_on_back_pressed)
	BattleSettings.teams_changed.connect(_refresh_grid)
	if not BattleSettings.is_solo_mode:
		NetworkManager.room_state_updated.connect(_refresh_from_network_state)

	get_viewport().size_changed.connect(_apply_orientation_layout)
	_apply_orientation_layout()

## 房主看得到「開始比賽」（等所有人都分好隊、按過準備才能按）；其他人只
## 看得到「準備」（分好隊之後按，跟 RoomBattleSettings.gd 的
## _apply_owner_mode_ui() 同一套模式，NetworkManager.set_ready() 本身也已經
## 擋掉房主呼叫，這裡只是連 UI 都不給房主看到）。
func _apply_owner_mode_ui() -> void:
	start_button_portrait.visible = _is_owner
	start_button_landscape.visible = _is_owner
	ready_button_portrait.visible = not _is_owner
	ready_button_landscape.visible = not _is_owner
	# 2026-09-23 使用者需求：返回也要跟開始/準備一樣只有房主看得到——單機
	# 模式 _is_owner 永遠是 true（見上面欄位說明），行為不變。
	back_button_portrait.visible = _is_owner
	back_button_landscape.visible = _is_owner

func _refresh_from_network_state() -> void:
	_apply_owner_mode_ui()
	_refresh_start_button()

func _on_ready_pressed() -> void:
	_is_ready = not _is_ready
	var text := "取消準備" if _is_ready else "準備"
	ready_button_portrait.text = text
	ready_button_landscape.text = text
	NetworkManager.set_ready(_is_ready)

## 旋轉裝置、直向橫向比例翻轉時，切換顯示哪一組 PortraitLayout/
## LandscapeLayout，跟其他選單畫面同一套做法。
func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	portrait_layout.visible = is_portrait
	landscape_layout.visible = not is_portrait

func _build_grid(grid: GridContainer) -> Array:
	var cells: Array = []
	grid.columns = BattleSettings.TEAM_COUNT
	for row in range(BattleSettings.MAX_PLAYERS_PER_TEAM):
		for team_index in range(BattleSettings.TEAM_COUNT):
			var cell: Button = CellScript.new()
			cell.team_index = team_index
			cell.slot_index = row
			cell.controller = self
			cell.custom_minimum_size = Vector2(0, 140)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_theme_font_size_override("font_size", 22)
			## 2026-09-24 新增：真人格子要顯示頭貼（見 _refresh_cells()），讓圖示
			## 依格子高度縮放，不要維持頭貼原始 256x256 撐爆整個格子。
			cell.expand_icon = true
			cell.add_theme_constant_override("icon_max_width", 72)
			## 2026-09-24 使用者回報：頭貼原本固定貼在格子最左邊、文字獨立置中,
			## 兩者中間空一大段、視覺上沒有「同一組」的感覺——icon_alignment
			## 預設是 LEFT,要跟 alignment（文字,預設就是 CENTER）一樣設成
			## CENTER,Godot 才會把頭貼+文字當一組整體置中,不是各自獨立對齊。
			## h_separation 縮小讓頭貼跟文字排更緊。
			cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_theme_constant_override("h_separation", 10)
			var style := StyleBoxFlat.new()
			style.bg_color = BattleSettings.TEAM_COLORS[team_index]
			style.corner_radius_top_left = 12
			style.corner_radius_top_right = 12
			style.corner_radius_bottom_left = 12
			style.corner_radius_bottom_right = 12
			cell.add_theme_stylebox_override("normal", style)
			cell.add_theme_stylebox_override("hover", style)
			cell.add_theme_stylebox_override("pressed", style)
			cell.add_theme_stylebox_override("disabled", style)
			cell.pressed.connect(_on_cell_pressed.bind(team_index, row))
			grid.add_child(cell)
			cells.append(cell)
	return cells

## --- 點擊：加入/移除 ---------------------------------------------------

func _on_cell_pressed(team_index: int, slot_index: int) -> void:
	var occupant := BattleSettings.get_occupant(team_index, slot_index)
	if occupant != 0:
		_try_remove(occupant)
		return
	_try_add(team_index, slot_index)

func _try_remove(occupant: int) -> void:
	if BattleSettings.is_solo_mode:
		# 單人模式：玩家自己或任何一隻 AI 都能直接請下場。
		BattleSettings.push_removal(occupant)
	elif occupant == _local_peer_id:
		# 連線模式：只能移除自己，不能踢真人隊友（BattleSettings.push_removal()
		# 伺服器端也會再擋一次，這裡只是不要白送一個一定會被拒絕的請求）。
		BattleSettings.push_removal(occupant)

func _try_add(team_index: int, slot_index: int) -> void:
	if BattleSettings.is_solo_mode:
		var participant := _local_peer_id
		if BattleSettings.get_placement(_local_peer_id).x >= 0:
			participant = BattleSettings.next_available_ai()
			if participant == 0:
				return # 三隻 AI 都已經上場了
		BattleSettings.push_placement(participant, team_index, slot_index)
	else:
		BattleSettings.push_placement(_local_peer_id, team_index, slot_index)

## --- 拖放：給 TeamSelectCell.gd 呼叫 ------------------------------------

func can_drag_cell(team_index: int, slot_index: int) -> bool:
	var occupant := BattleSettings.get_occupant(team_index, slot_index)
	if occupant == 0:
		return false
	if BattleSettings.is_solo_mode:
		return true # 玩家自己或任何一隻 AI 都能拖
	return occupant == _local_peer_id # 連線模式只能拖自己

func can_drop_on_cell(_team_index: int, _slot_index: int) -> bool:
	return true

func handle_cell_drop(from_team: int, from_slot: int, to_team: int, to_slot: int) -> void:
	if from_team == to_team and from_slot == to_slot:
		return
	var occupant := BattleSettings.get_occupant(from_team, from_slot)
	if occupant == 0:
		return
	if not can_drag_cell(from_team, from_slot):
		return
	BattleSettings.push_placement(occupant, to_team, to_slot)

## --- 畫面刷新 ------------------------------------------------------------

func _refresh_grid() -> void:
	_refresh_cells(_cells_portrait)
	_refresh_cells(_cells_landscape)
	_refresh_start_button()

## 2026-09-24 使用者需求：格子裡除了文字，多人連線的真人格子要多畫頭貼
## （見 PlayerProfile.gd/NetworkManager._peer_profiles 的說明）——單機模式
## 的「你」跟 AI 沒有頭貼概念，維持原本純文字。
func _refresh_cells(cells: Array) -> void:
	for i in range(cells.size()):
		var team_index := i % BattleSettings.TEAM_COUNT
		var slot_index := i / BattleSettings.TEAM_COUNT
		var cell: Button = cells[i]
		var occupant := BattleSettings.get_occupant(team_index, slot_index)
		cell.icon = null
		if occupant == 0:
			cell.text = ""
			cell.disabled = false
			cell.modulate = Color(1, 1, 1, 0.7)
		elif occupant == _local_peer_id:
			## 2026-09-24 使用者需求：自己那格也直接顯示頭貼+名稱，不管單人還是
			## 多人模式，不再用「你」這個通用字（PlayerProfile 是純本機資料，
			## 單機模式一樣讀得到，不需要另外判斷 is_solo_mode）。
			cell.text = PlayerProfile.player_name
			cell.icon = PlayerProfile.get_avatar_texture()
			cell.disabled = false
			cell.modulate = Color(1, 1, 1, 1)
		elif BattleSettings.is_ai(occupant):
			cell.text = BattleSettings.AI_LABELS.get(occupant, "AI")
			cell.disabled = false
			cell.modulate = Color(1, 1, 1, 1)
		else:
			cell.text = NetworkManager.get_peer_profile_name(occupant)
			cell.icon = PlayerProfile.get_avatar_texture_for(NetworkManager.get_peer_profile_avatar_id(occupant))
			cell.disabled = false
			cell.modulate = Color(1, 1, 1, 1)

## 2026-09-23：多人模式下「可以開始」除了原本的「所有人都選好隊伍」，
## 再加一條「所有人都按過準備」（跟房間設定畫面同一套模式）——單機模式
## 沒有這個概念，維持原本只看「有沒有分好隊」。非房主完全看不到開始鈕
## （見 _apply_owner_mode_ui()），這裡的 disabled 賦值對他們不會有作用，
## 但邏輯統一寫，不用特別分支跳過。
func _refresh_start_button() -> void:
	var can_start: bool
	var status_text: String
	if BattleSettings.is_solo_mode:
		can_start = BattleSettings.has_opponent_for_solo(_local_peer_id)
		status_text = "可以開始比賽" if can_start else "先分好隊、至少放一個對手（AI）"
	elif not _is_owner:
		can_start = false
		status_text = "已準備，等待房主開始" if _is_ready else "分好隊之後按下「準備」"
	else:
		var peer_ids := _get_connected_peer_ids()
		var all_assigned := BattleSettings.all_assigned(peer_ids)
		var ready_states := NetworkManager.get_ready_states()
		var has_other_player := not ready_states.is_empty()
		var all_ready := true
		for ready in ready_states.values():
			if not ready:
				all_ready = false
				break
		can_start = has_other_player and all_assigned and all_ready
		if not has_other_player:
			status_text = "等待其他玩家加入…"
		elif not all_assigned:
			status_text = "等待所有玩家選好隊伍…"
		elif not all_ready:
			status_text = "等待所有玩家按下準備…"
		else:
			status_text = "所有人都準備好了，可以開始"
	status_label_portrait.text = status_text
	status_label_landscape.text = status_text
	start_button_portrait.disabled = not can_start
	start_button_landscape.disabled = not can_start

func _get_connected_peer_ids() -> Array:
	var ready_states: Dictionary = NetworkManager.get_ready_states()
	if not ready_states.is_empty():
		return ready_states.keys()
	return [_local_peer_id]

func _on_start_pressed() -> void:
	if BattleSettings.is_solo_mode:
		# 單人模式沒有連線房間，不呼叫 NetworkManager——直接進對戰盤面
		# （Battle.tscn，2026-09-21 Milestone 1 做好）。
		get_tree().change_scene_to_file("res://Scenes/Battle.tscn")
	else:
		NetworkManager.start_match()

## 2026-09-23 修正：多人模式下這顆鈕原本只是本機自己切場景，其他人沒有
## 跟著切過去、卡在分隊畫面（房主如果回去調設定，其他人完全看不到）——改叫
## NetworkManager.return_to_room_settings()，讓房主之外的人也一起被帶回
## 房間設定畫面（見該函式的說明）。單機模式沒有連線，維持原本直接切場景。
func _on_back_pressed() -> void:
	if BattleSettings.is_solo_mode:
		get_tree().change_scene_to_file("res://Scenes/RoomBattleSettings.tscn")
	else:
		NetworkManager.return_to_room_settings()
