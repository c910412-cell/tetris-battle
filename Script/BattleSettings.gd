## 對戰規則設定＋分隊結果的共用狀態（autoload）。
## 這次（2026-09-21）先做本地端 UI 骨架，還沒有接 NetworkManager 的 RPC 廣播——
## 之後要讓房主在 RoomBattleSettings.tscn 選的設定、玩家在 TeamSelect.tscn 選的
## 隊伍同步給其他連線中的玩家時，比照 NetworkManager.gd 現成的「client 請求→
## host 驗證→host 廣播」慣例（參考它的 update_room_settings()/start_match()），
## 在這個 autoload 上加對應的 RPC 函式，不要去動 NetworkManager.gd 本體。
## 完整規格見 memory/tetris_multiplayer_battle_design.md。
extends Node

signal settings_changed
signal teams_changed

## 輔助瞄準（ghost piece）——對應 TetrisGameController.get_ghost_cells()。
var assist_ghost: bool = true
## 時間加速：是否隨比賽時間拉長自動加快下落速度（跟消行升等級是分開的機制）。
var time_acceleration: bool = false
## 幾回合勝利（1~5）。
var rounds_to_win: int = 3
## 傷害倍率 N（1~4，代表 1:1~1:4）：garbage = floor(累積消行數/N)，餘數累加。
var damage_ratio: int = 1
## 指定目標攻擊：關閉時隨機選目標、一段時間換一次；開啟時攻擊方手動選單一玩家。
var targeted_attack: bool = false
## 待定點點結算成真垃圾行的間隔秒數。
var settlement_seconds: int = 30
## 是否限制每個玩家在單一個結算間隔內最多能累積幾行待定點點——開啟時超過
## 上限的攻擊點數直接作廢（不會累積也不會轉送別人），避免被針對性連續攻擊
## 瞬間疊超多垃圾行；結算後歸零重新累積，見 BattleDirector._on_attack_ready()。
var garbage_cap_enabled: bool = true
## 上面那個上限的實際行數（2026-09-21 使用者指定預設 5 行）。
var garbage_cap_lines: int = 5
## 是否每個玩家各自獨立隨機出塊（預設關閉＝全員同一局共用同一份 7-bag 序列）。
var random_piece_per_player: bool = false
## AI 強度（0=簡單／1=普通／2=高級）。單人模式填入的 AI 機器人用這個強度；
## 這是房間設定裡「一個」全域欄位，不是每隻 AI 各自設定。
var ai_level: int = 1
const AI_LEVEL_NAMES: Array[String] = ["簡單", "普通", "高級"]

## 2026-09-23 使用者需求：落後方身上的垃圾行通常只有一個缺口，只能一行一行
## 清，而清 1 行在標準 guideline 攻擊力表裡是 0 點（見
## TetrisGameController.LINE_ATTACK_BY_COUNT），永遠反擊不了——開啟這個設定
## 後，清 1 行（且原本會是 0 點攻擊的情況,不含已經有分數的 T-Spin Mini 單行）
## 改算 0.5 點攻擊力，兩次累積才湊出 1 點，讓落後方有機會反敗為勝（見
## BattleDirector._comeback_adjusted_attack_power()）。預設關閉，維持官方
## guideline 的標準規則,不影響原本的平衡。
var single_line_counts_as_attack: bool = false

## 是否為「單人遊玩」模式（2026-09-21 補充：跟本地連線共用房間設定/分隊畫面，
## 差別是可以填 AI 機器人、不用等其他真人、「開始比賽」不會呼叫
## NetworkManager.start_match()）。Lobby.gd 的單人遊玩入口會把這個設成 true，
## 本地連線流程（RoomLobby._on_start_pressed）會設成 false。這個欄位本身
## 純粹是本機旗標，不同步。
var is_solo_mode: bool = false

## 連線對戰這一場比賽共用的隨機種子，由房主在 NetworkManager._do_start_match()
## 產生、隨開始比賽一起廣播（見該函式），BattleDirector._init() 拿這個取代
## 各自本地 randi()。0＝沒有外部種子（單機/AI 對戰，或還沒連線），
## BattleDirector 會照原本行為自己生一個。
var network_match_seed: int = 0
## BattleDirector 會照原本行為自己生一個。

func reset_to_defaults() -> void:
	assist_ghost = true
	time_acceleration = false
	rounds_to_win = 3
	damage_ratio = 1
	targeted_attack = false
	settlement_seconds = 30
	garbage_cap_enabled = true
	garbage_cap_lines = 5
	random_piece_per_player = false
	ai_level = 1
	single_line_counts_as_attack = false
	settings_changed.emit()

## --- 分隊 -------------------------------------------------------------
## 4 個隊伍固定存在（不是隊伍上限放寬到 4 人）：保證一定有對抗目標、避免
## 玩家全擠同一隊，見 memory 規格第 5 節。每一格都是獨立座位
## （team_index, slot_index），不是只到隊伍層級——這是為了支援拖曳互換/
## 移動到指定格子（2026-09-21 補充需求）。

const TEAM_COUNT := 4
const MAX_PLAYERS_PER_TEAM := 3
const TEAM_NAMES: Array[String] = ["紅隊", "黃隊", "綠隊", "藍隊"]
const TEAM_COLORS: Array[Color] = [
	Color(0.85, 0.22, 0.22),
	Color(0.85, 0.78, 0.15),
	Color(0.2, 0.75, 0.3),
	Color(0.2, 0.45, 0.9),
]

## AI 身分是固定的三個負數 id（不會跟真人 peer_id 撞號，peer_id 一定是正數）。
## 顯示名稱固定是「AI 2號/3號/4號」——玩家自己算「1號」，這是使用者原話
## 「第一個按下去是玩家，第二個是ai二號」的字面延伸，不是動態依加入順序重編號。
const AI_IDS: Array[int] = [-1, -2, -3]
const AI_LABELS := {-1: "AI 2號", -2: "AI 3號", -3: "AI 4號"}

## participant_id（真人 peer_id 是正數／AI 是上面 AI_IDS 的負數）
## -> Vector2i(team_index, slot_index)。
var _placements: Dictionary = {}

func reset_team_assignments() -> void:
	_placements.clear()
	teams_changed.emit()

func is_ai(participant_id: int) -> bool:
	return participant_id < 0

## 目前還沒上場、編號最小的 AI 身分；三個都上場了回傳 0（代表沒有）。
func next_available_ai() -> int:
	for ai_id in AI_IDS:
		if not _placements.has(ai_id):
			return ai_id
	return 0

func get_placement(participant_id: int) -> Vector2i:
	return _placements.get(participant_id, Vector2i(-1, -1))

## 回傳格子上的人（participant_id），空格回傳 0。
func get_occupant(team_index: int, slot_index: int) -> int:
	for pid in _placements:
		var cell: Vector2i = _placements[pid]
		if cell.x == team_index and cell.y == slot_index:
			return pid
	return 0

## 目前有分到隊伍的所有 participant_id（真人+AI），給 BattleDirector 建立
## 對戰參與者用。
func get_all_placed_ids() -> Array:
	return _placements.keys()

func get_team_members(team_index: int) -> Array:
	var members: Array = []
	for pid in _placements:
		if _placements[pid].x == team_index:
			members.append(pid)
	return members

## 把 participant_id 放到指定格子。如果那格已經有別人，且 participant_id
## 原本也有格子，兩邊直接互換；如果 participant_id 是第一次上場（沒有舊格子），
## 原本佔那格的人會被直接請下場（正常情況下 UI 會先擋住這種操作，理論上不會
## 真的走到這個分支）。回傳 true 表示成功。
func place(participant_id: int, team_index: int, slot_index: int) -> bool:
	if team_index < 0 or team_index >= TEAM_COUNT:
		return false
	if slot_index < 0 or slot_index >= MAX_PLAYERS_PER_TEAM:
		return false
	var occupant := get_occupant(team_index, slot_index)
	var old_cell := get_placement(participant_id)
	if occupant != 0 and occupant != participant_id:
		if old_cell.x >= 0:
			_placements[occupant] = old_cell
		else:
			_placements.erase(occupant)
	_placements[participant_id] = Vector2i(team_index, slot_index)
	teams_changed.emit()
	return true

func remove(participant_id: int) -> void:
	if _placements.has(participant_id):
		_placements.erase(participant_id)
		teams_changed.emit()

func all_assigned(peer_ids: Array) -> bool:
	for peer_id in peer_ids:
		if not _placements.has(peer_id):
			return false
	return true

## 單人模式的「開始比賽」門檻：玩家自己要分隊，而且至少要有一個人（通常是 AI）
## 在跟玩家不同的隊伍——0 個對手（大家都跟玩家同隊）不能開始，避免跟「無盡
## 挑戰」意義重複。
func has_opponent_for_solo(local_peer_id: int) -> bool:
	var my_cell := get_placement(local_peer_id)
	if my_cell.x < 0:
		return false
	for pid in _placements:
		if pid != local_peer_id and _placements[pid].x != my_cell.x:
			return true
	return false

## --- 連線同步（2026-09-23 新增，多人連線第一階段）------------------------
## 跟 NetworkManager.gd 同一套「client 請求→host 驗證→host 廣播」慣例，
## 獨立寫在這裡，沒有動 NetworkManager.gd 本體（除了 MATCH_SCENE_PATH 跟
## 開賽種子廣播這兩個一定要接在它那邊的部分）。單機模式或還沒連線時，所有
## 入口函式都直接退回原本的純本地寫法，行為完全不變。
##
## 房間規則（10 個欄位）只有房主能改——RoomBattleSettings.gd 的 9 條規則列
## 現在也會依 _is_owner 唯讀化（原本只有房間資訊 4 欄有做，這次補齊），這裡
## 是伺服器端再擋一次，不是只靠前端。分隊結果不同：任何已連線玩家都能請求
## 把「自己」放到任一格（可能觸發跟原本佔位者互換，沿用 place() 既有邏輯），
## 只有房主能動 AI 身分（AI 不屬於任何一個 peer，只有房主能代管）。

func _is_networked() -> bool:
	return not is_solo_mode and multiplayer.has_multiplayer_peer()

## RoomBattleSettings.gd 的 10 個 _on_*_toggled/_selected/_changed 在本機寫入
## BattleSettings.xxx 之後呼叫這個，取代直接 emit settings_changed——單機/
## 還沒連線時只是照原本行為本地生效；連線中非房主時忽略（UI 本來就唯讀，
## 這裡防呆）；房主端打包目前全部欄位廣播出去。
func sync_room_rules() -> void:
	if not _is_networked():
		settings_changed.emit()
		return
	if multiplayer.get_unique_id() != NetworkManager.room_owner_peer_id:
		return
	if multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		_broadcast_room_rules(_pack_room_rules())
	else:
		_request_sync_room_rules.rpc_id(NetworkManager.HOST_PEER_ID, _pack_room_rules())

func _pack_room_rules() -> Dictionary:
	return {
		"assist_ghost": assist_ghost,
		"time_acceleration": time_acceleration,
		"rounds_to_win": rounds_to_win,
		"damage_ratio": damage_ratio,
		"targeted_attack": targeted_attack,
		"settlement_seconds": settlement_seconds,
		"garbage_cap_enabled": garbage_cap_enabled,
		"garbage_cap_lines": garbage_cap_lines,
		"random_piece_per_player": random_piece_per_player,
		"ai_level": ai_level,
		"single_line_counts_as_attack": single_line_counts_as_attack,
	}

func _apply_room_rules(rules: Dictionary) -> void:
	assist_ghost = rules.get("assist_ghost", assist_ghost)
	time_acceleration = rules.get("time_acceleration", time_acceleration)
	rounds_to_win = rules.get("rounds_to_win", rounds_to_win)
	damage_ratio = rules.get("damage_ratio", damage_ratio)
	targeted_attack = rules.get("targeted_attack", targeted_attack)
	settlement_seconds = rules.get("settlement_seconds", settlement_seconds)
	garbage_cap_enabled = rules.get("garbage_cap_enabled", garbage_cap_enabled)
	garbage_cap_lines = rules.get("garbage_cap_lines", garbage_cap_lines)
	random_piece_per_player = rules.get("random_piece_per_player", random_piece_per_player)
	ai_level = rules.get("ai_level", ai_level)
	single_line_counts_as_attack = rules.get("single_line_counts_as_attack", single_line_counts_as_attack)
	settings_changed.emit()

@rpc("any_peer", "reliable")
func _request_sync_room_rules(rules: Dictionary) -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理
	if multiplayer.get_remote_sender_id() != NetworkManager.room_owner_peer_id:
		return  # 防呆：只有目前認領到房主身分的那個人送的請求才算數
	_broadcast_room_rules(rules)

func _broadcast_room_rules(rules: Dictionary) -> void:
	_sync_room_rules.rpc(rules)

## call_local——房主自己也走這條路徑生效，跟 NetworkManager._sync_room_state()
## 同一個理由，不用另外維護一份「房主本機直接賦值」的重複邏輯。
@rpc("authority", "call_local", "reliable")
func _sync_room_rules(rules: Dictionary) -> void:
	_apply_room_rules(rules)

## --- 分隊結果同步 ---------------------------------------------------------
## TeamSelect.gd／TeamSelectCell.gd 原本直接呼叫的 place()/remove()，連線
## 情境下改叫這兩個入口——它們會做權限檢查，本機/單機直接退回原本的
## place()/remove()。

func push_placement(participant_id: int, team_index: int, slot_index: int) -> void:
	if not _is_networked():
		place(participant_id, team_index, slot_index)
		return
	if not _can_move(participant_id):
		return
	if multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		_apply_placement(participant_id, team_index, slot_index)
	else:
		_request_push_placement.rpc_id(NetworkManager.HOST_PEER_ID, participant_id, team_index, slot_index)

func push_removal(participant_id: int) -> void:
	if not _is_networked():
		remove(participant_id)
		return
	if not _can_move(participant_id):
		return
	if multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		_apply_removal(participant_id)
	else:
		_request_push_removal.rpc_id(NetworkManager.HOST_PEER_ID, participant_id)

func push_reset_team_assignments() -> void:
	if not _is_networked():
		reset_team_assignments()
		return
	if multiplayer.get_unique_id() != NetworkManager.room_owner_peer_id:
		return
	if multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		_placements.clear()
		_broadcast_placements()
	else:
		_request_reset_team_assignments.rpc_id(NetworkManager.HOST_PEER_ID)

## 本機呼叫端的權限判斷：只能動自己，AI 只有房主能動。伺服器收到請求時
## （_request_push_placement()/_request_push_removal()）會用送出者的 peer_id
## 再驗一次同一條規則，不是只靠前端擋。
func _can_move(participant_id: int) -> bool:
	var my_id := multiplayer.get_unique_id()
	if is_ai(participant_id):
		return my_id == NetworkManager.room_owner_peer_id
	return participant_id == my_id or my_id == NetworkManager.room_owner_peer_id

func _apply_placement(participant_id: int, team_index: int, slot_index: int) -> void:
	place(participant_id, team_index, slot_index)
	_broadcast_placements()

func _apply_removal(participant_id: int) -> void:
	remove(participant_id)
	_broadcast_placements()

@rpc("any_peer", "reliable")
func _request_push_placement(participant_id: int, team_index: int, slot_index: int) -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return
	if not _sender_can_move(participant_id):
		return
	_apply_placement(participant_id, team_index, slot_index)

@rpc("any_peer", "reliable")
func _request_push_removal(participant_id: int) -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return
	if not _sender_can_move(participant_id):
		return
	_apply_removal(participant_id)

@rpc("any_peer", "reliable")
func _request_reset_team_assignments() -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return
	if multiplayer.get_remote_sender_id() != NetworkManager.room_owner_peer_id:
		return
	_placements.clear()
	_broadcast_placements()

## 伺服器端版本的 _can_move()，判斷依據是「這個 RPC 是誰送來的」
## （get_remote_sender_id()），不是本機的 multiplayer.get_unique_id()。
func _sender_can_move(participant_id: int) -> bool:
	var sender_id := multiplayer.get_remote_sender_id()
	if is_ai(participant_id):
		return sender_id == NetworkManager.room_owner_peer_id
	return participant_id == sender_id or sender_id == NetworkManager.room_owner_peer_id

func _broadcast_placements() -> void:
	_sync_placements.rpc(_placements.duplicate())

@rpc("authority", "call_local", "reliable")
func _sync_placements(placements: Dictionary) -> void:
	_placements = placements
	teams_changed.emit()
