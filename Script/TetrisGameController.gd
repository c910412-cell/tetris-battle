## 單人/未來雙人共用的核心遊戲邏輯（重力、lock delay、旋轉+wall kick、
## 軟降/硬降、hold、ghost piece、計分/升等）。純 RefCounted、不依賴場景樹，
## 方便之後接上網路同步或無頭測試（見 TetrisBoard.gd 的 snapshot 介面）。
## Board.gd 只負責讀這個類別的狀態畫圖跟餵輸入，遊戲規則全部在這裡。
class_name TetrisGameController
extends RefCounted

## 一個方塊鎖定到盤面之後發出（不論有沒有消行）。
signal piece_locked
## 消行發生時發出，count 是這次同時消掉的行數（1~4）。
signal lines_cleared(count: int)
signal score_changed(score: int)
signal level_changed(level: int)
## 新方塊在生成點就放不下時發出（疊到頂）。
signal game_over
## 消行當下額外發出，給對戰的傷害/垃圾行系統用；不影響既有 lines_cleared
## 訊號（HUD 還在用那個）。attack_power 是這次要送出去的攻擊力（2026-09-22
## 起不再是單純行數，改成跟分數同一套 T-Spin/B2B/Combo/Perfect Clear 規則
## 算出來的小整數，見 _attack_power_for_clear()——分數本身量級太大不能直接
## 拿來當攻擊力，兩邊各自一張表分開調），gap_columns 是每一行「被這次鎖定
## 的方塊補上的那一欄」（見對戰規格：垃圾行缺口鏡射這個）。
signal attack_ready(attack_power: int, gap_columns: Array)
## 2026-09-24 新增：玩家主動造成的移動——左右移動成功、或按住「軟降」造成
## 真的往下移動一格時發出（純被動的一般重力下墜、硬降不算,硬降有自己的
## 音效,一般重力落下沒有操作感、不需要回饋音效）。給 SoundEffects.gd 接,
## 只有本地玩家自己的 controller 需要接,AI/遠端玩家的鏡像 controller 不用
## （呼叫端自己判斷,這裡只負責照實發訊號）。
signal piece_moved

const SPAWN_X := 3
const SPAWN_Y := 0

## lock delay：碰底後開始倒數，倒數期間每次成功移動/旋轉都會重置，但最多
## 重置 MAX_LOCK_RESETS 次，避免玩家瘋狂搖桿讓方塊無限不落地。
const LOCK_DELAY_SEC := 0.5
const MAX_LOCK_RESETS := 15

const BASE_GRAVITY_SEC := 1.0
const LINES_PER_LEVEL := 10
const GRAVITY_LEVEL_FACTOR := 0.85
const MIN_GRAVITY_SEC := 0.1

## 2026-09-22 補上 Tetris Guideline 通用連消規則（T-Spin/Back-to-Back/Combo/
## Perfect Clear），數值抄公開的 guideline 對照表（見 CLAUDE.md「Research
## Before Building」——這些是公開標準，不用自己亂猜比例）。全部乘 level 的
## 慣例延續原本單純消行分數的做法。
const LINE_SCORE_BY_COUNT := {1: 100, 2: 300, 3: 500, 4: 800}
## Tetris（4 行）接在上一次「難清」後面才有這個加成表；1~3 行普通消行沒有
## B2B 加成（guideline 只有 Tetris/T-Spin 算「難清」）。
const LINE_SCORE_B2B_BY_COUNT := {4: 1200}
const TSPIN_SCORE_BY_COUNT := {0: 400, 1: 800, 2: 1200, 3: 1600}
const TSPIN_SCORE_B2B_BY_COUNT := {1: 1200, 2: 1800, 3: 2400}
const TSPIN_MINI_SCORE_BY_COUNT := {0: 100, 1: 200}
const TSPIN_MINI_SCORE_B2B_BY_COUNT := {1: 400}
## Perfect Clear 是總分（取代同一次的一般消行分數，不是疊加上去）。
const PERFECT_CLEAR_SCORE_BY_COUNT := {1: 800, 2: 1200, 3: 1800, 4: 2000}
const PERFECT_CLEAR_SCORE_B2B_BY_COUNT := {4: 2600}
const COMBO_SCORE_PER_STEP := 50
const SOFT_DROP_POINTS_PER_CELL := 1
const HARD_DROP_POINTS_PER_CELL := 2

## 攻擊力（垃圾行）獨立一張表，跟分數表脫鉤——分數乘了 level、量級動輒
## 上千，直接拿來當攻擊力會失控，且攻擊力不應該因為等級變高就跟著暴增。
## 2026-09-22 跟使用者確認過的數值：一般消行接近現有量級（1~4 行大致對應
## 0~4 點攻擊），T-Spin/Tetris/連段/全清額外加成，讓「分數對應攻擊」但兩邊
## 各自可調。0 行 T-Spin 不會走到這裡（見 _lock_active_piece()，沒消行不會
## emit attack_ready），所以下面兩張 T-Spin 表都不需要 0 行的 entry。
const LINE_ATTACK_BY_COUNT := {1: 0, 2: 1, 3: 2, 4: 4}
const TSPIN_ATTACK_BY_COUNT := {1: 2, 2: 4, 3: 6}
const TSPIN_MINI_ATTACK_BY_COUNT := {1: 1}
## 跟分數的 B2B 規則同一個判定（Tetris 或帶消行的 T-Spin 才算難清）,難清
## 接在上一次難清後面多送這麼多攻擊力。
const B2B_ATTACK_BONUS := 1
## 連段加成：每多連 2 次消行,多送 1 點攻擊力（COMBO_ATTACK_DIVISOR 拿來整除
## _combo_count，不是查表，數字小、規則簡單，不用另外開一張表）。
const COMBO_ATTACK_DIVISOR := 2
## Perfect Clear 攻擊力是固定值,取代（不是疊加）上面算出來的攻擊力——整個
## 盤面清空本來就該是最狠的一擊。
const PERFECT_CLEAR_ATTACK := 10

## 消行判定成立之後、真的把行移除之前的停頓秒數——2026-09-21 使用者回報
## AI 消行太快，肉眼根本來不及確認那一行是不是真的填滿了才消除（尤其 AI
## 幾乎瞬間下子，判定跟畫面刷新都在同一幀，玩家永遠看不到「整行滿了」的
## 那個畫面）。這個停頓純粹是視覺效果：滿行判定本身（find_full_lines()）
## 在停頓開始「之前」就已經算完、不會變動，停頓期間只是延後呼叫
## clear_lines()，畫面層趁這段時間把整行畫成 FLASH_COLOR 高亮，見
## TetrisBoardRenderer.draw_locked_cells() 的 flash_rows 參數。
const CLEAR_FLASH_SEC := 0.15

var board: TetrisBoard
var randomizer: TetrisPieceRandomizer

var score: int = 0
var lines_cleared_total: int = 0
var level: int = 1
var is_game_over: bool = false

## 軟降（按住「↓」，手勢/按鈕共用同一套輪詢邏輯）的下落間隔秒數——原本是
## 寫死的常數 SOFT_DROP_GRAVITY_SEC，2026-09-21/22 使用者陸續回報調過幾輪
## 手感（0.05 太快幾乎等於硬降→0.15 太慢→中間值 0.1→0.06→最後定案在原本
## 0.1 跟 0.06 中間）。2026-09-24 改成可設定的實例欄位、放進
## PlayerSettings.soft_drop_interval_sec 讓玩家自己在設定畫面調——這個類別
## 故意不直接讀 PlayerSettings（保持純邏輯、不依賴任何 autoload，可以離線
## 單獨測試,見檔案開頭的說明),呼叫端（Board.gd/Battle.gd）在建立本地玩家
## 的 controller 之後自己把這個欄位設成 PlayerSettings 目前的值。這裡的
## 0.08 只是「還沒被呼叫端覆寫時」的保底預設值，實際生效的是 PlayerSettings
## 那份、跨場景持久保存的設定。
var soft_drop_gravity_sec: float = 0.08

var _active_type: TetrisPieceData.PieceType
var _active_rotation: int = 0
var _active_pos: Vector2i = Vector2i.ZERO

var _hold_type: TetrisPieceData.PieceType = TetrisPieceData.PieceType.I
var _has_hold_piece: bool = false
var _has_held_this_turn: bool = false

var _gravity_timer: float = 0.0
var _lock_timer: float = 0.0
var _lock_resets: int = 0
var _is_on_surface: bool = false
var _soft_drop_active: bool = false

var _is_clearing: bool = false
var _clear_flash_timer: float = 0.0
var _pending_clear_rows: Array[int] = []
var _pending_clear_gap_columns: Array[int] = []
## 鎖定前最後一次成功操作是不是旋轉——T-Spin 判定用（見 _detect_t_spin()），
## 只有 move()/rotate() 這種玩家/AI 主動操作會更新，重力自然下墜不算數（照
## 常見的簡化判定：轉完直接硬降也算數，因為硬降不會經過 move()）。
var _last_action_was_rotation: bool = false
## 0=無/1=Mini/2=完整——在 _lock_active_piece() 鎖定當下（消行前）就判定好，
## 消行閃爍停頓結束後 _finish_clear() 拿這個值計分，跟缺口欄位同一套「判定
## 在停頓開始前就定案」的做法（見 _lock_active_piece() 的說明）。
var _pending_t_spin_type: int = 0
## 連續清行數（不含這次），一次沒清到就歸零；上一次「難清」（Tetris/
## T-Spin）是不是緊接著這次，決定這次有沒有 Back-to-Back 加成。
var _combo_count: int = 0
var _back_to_back_active: bool = false

func _init(randomizer_seed: int = 0) -> void:
	board = TetrisBoard.new()
	randomizer = TetrisPieceRandomizer.new(randomizer_seed)
	_spawn_piece(randomizer.get_next_piece())

func peek_next_pieces(count: int = 3) -> Array[TetrisPieceData.PieceType]:
	return randomizer.peek_next_pieces(count)

## 沒有 hold 方塊時回傳 -1，畫面層以此判斷要不要畫 hold 預覽。
func get_hold_type() -> int:
	return _hold_type if _has_hold_piece else -1

func get_active_type() -> TetrisPieceData.PieceType:
	return _active_type

## 給 TetrisAI 規劃旋轉/位移步驟用：目前旋轉狀態（0~3）跟 bounding box
## 左上角世界座標。
func get_active_rotation() -> int:
	return _active_rotation

func get_active_position() -> Vector2i:
	return _active_pos

func get_active_cells() -> Array[Vector2i]:
	return _world_cells(_active_type, _active_rotation, _active_pos)

## ghost piece：跟真正下落共用同一個 _fits() 碰撞檢查，逐格模擬下移到底，
## 保證顯示的落點跟硬降真正落點永遠一致。
func get_ghost_cells() -> Array[Vector2i]:
	var ghost_pos := _active_pos
	while _fits(_active_type, _active_rotation, ghost_pos + Vector2i(0, 1)):
		ghost_pos.y += 1
	return _world_cells(_active_type, _active_rotation, ghost_pos)

## 消行閃爍停頓期間，有沒有正在下落的方塊可以顯示（給畫面層判斷要不要畫
## ghost/目前方塊——這段期間 _active_pos/_active_type 還是上一顆已經鎖定
## 的方塊的殘留值，直接拿去畫會跟盤面上剛鎖定的那顆重複）。
func is_clearing() -> bool:
	return _is_clearing

## 目前正在閃爍、即將被移除的行（視覺座標，已經是完整 TOTAL_HEIGHT 座標，
## 跟 TetrisBoardRenderer.draw_locked_cells() 的 flash_rows 參數配合使用）。
func get_clearing_rows() -> Array[int]:
	return _pending_clear_rows

func tick(delta: float) -> void:
	if is_game_over:
		return

	if _is_clearing:
		_clear_flash_timer += delta
		if _clear_flash_timer >= CLEAR_FLASH_SEC:
			_finish_clear()
		return

	var gravity_interval := soft_drop_gravity_sec if _soft_drop_active else _current_gravity_interval()
	## 2026-09-22：_gravity_timer 最多只留一個 interval 的量，不會累積補跳
	## 額度——原本的寫法（只把單一幀擋在一步，但多出來的時間留到下一幀繼續
	## 消化）在掉幀/裝置效能不穩時，會讓接下來好幾幀連續觸發下移，玩起來
	## 視覺上還是像「連續觸發、格子沒有真的停到位」（使用者實測回報）。這裡
	## 直接把超過一格份量的時間捨棄掉（不補償），保證每次 tick 最多下移一格
	## 、而且絕不會因為前面欠了時間就連續好幾幀狂跳。
	_gravity_timer = minf(_gravity_timer + delta, gravity_interval)
	if _gravity_timer >= gravity_interval and not is_game_over:
		_gravity_timer = 0.0
		_apply_gravity_step()

	if is_game_over:
		return

	if _is_on_surface:
		_lock_timer += delta
		if _lock_timer >= LOCK_DELAY_SEC:
			_lock_active_piece()
	else:
		_lock_timer = 0.0

func move(dx: int) -> bool:
	if is_game_over or _is_clearing:
		return false
	var new_pos := _active_pos + Vector2i(dx, 0)
	if _fits(_active_type, _active_rotation, new_pos):
		_active_pos = new_pos
		_last_action_was_rotation = false
		_notify_piece_manipulated()
		piece_moved.emit()
		return true
	return false

func rotate(clockwise: bool) -> bool:
	if is_game_over or _is_clearing:
		return false
	var from_rot := _active_rotation
	var to_rot := posmod(from_rot + (1 if clockwise else -1), 4)
	var kicks := TetrisPieceData.get_wall_kicks(_active_type, from_rot, to_rot)
	for kick in kicks:
		var candidate := _active_pos + kick
		if _fits(_active_type, to_rot, candidate):
			_active_rotation = to_rot
			_active_pos = candidate
			_last_action_was_rotation = true
			_notify_piece_manipulated()
			return true
	return false

func set_soft_drop(active: bool) -> void:
	_soft_drop_active = active

func hard_drop() -> void:
	if is_game_over or _is_clearing:
		return
	var distance := 0
	while _fits(_active_type, _active_rotation, _active_pos + Vector2i(0, 1)):
		_active_pos.y += 1
		distance += 1
	_add_score(distance * HARD_DROP_POINTS_PER_CELL)
	_lock_active_piece()

func hold() -> void:
	if is_game_over or _is_clearing or _has_held_this_turn:
		return
	_has_held_this_turn = true
	var incoming_type := _active_type
	if _has_hold_piece:
		var swapped_type := _hold_type
		_hold_type = incoming_type
		_spawn_piece(swapped_type)
	else:
		_hold_type = incoming_type
		_has_hold_piece = true
		_spawn_piece(randomizer.get_next_piece())

func _apply_gravity_step() -> void:
	if _fits(_active_type, _active_rotation, _active_pos + Vector2i(0, 1)):
		_active_pos.y += 1
		_is_on_surface = false
		_lock_timer = 0.0
		if _soft_drop_active:
			_add_score(SOFT_DROP_POINTS_PER_CELL)
			piece_moved.emit()
	else:
		_is_on_surface = true

func _notify_piece_manipulated() -> void:
	_is_on_surface = not _fits(_active_type, _active_rotation, _active_pos + Vector2i(0, 1))
	if _is_on_surface and _lock_resets < MAX_LOCK_RESETS:
		_lock_timer = 0.0
		_lock_resets += 1

func _lock_active_piece() -> void:
	var locked_cells := get_active_cells()
	## T-Spin 判定要在真的鎖進盤面「之前」用當下的盤面做，跟鎖不鎖這顆方塊
	## 無關（角落格子本來就不會跟這顆方塊自己的格子重疊）——這裡先算好存起來，
	## 跟缺口欄位一樣「停頓開始前就定案」。
	var t_spin_type := _detect_t_spin()
	board.lock_cells(locked_cells, _active_type)
	piece_locked.emit()

	var full_rows := board.find_full_lines()
	if full_rows.is_empty():
		_combo_count = 0
		if t_spin_type > 0:
			_add_score(_base_clear_score(0, t_spin_type, false) * level)
		_has_held_this_turn = false
		_spawn_piece(randomizer.get_next_piece())
		return

	# 每一行一定是被這次鎖定的方塊補上最後的空格才會變滿（不然上次鎖定
	# 完就會被清掉了），所以每一行都找得到至少一個屬於這次方塊的格子；
	# 同一行如果方塊佔了不只一格，取最左邊那格當缺口欄（見對戰規格）。
	# 缺口欄跟滿行判定都在這裡、閃爍停頓「開始之前」就已經算好定案，停頓
	# 只是延後 clear_lines() 實際執行跟後續訊號發送的時機，不影響判定結果。
	var gap_columns: Array[int] = []
	for row in full_rows:
		var gap_col := -1
		for c in locked_cells:
			if c.y == row and (gap_col == -1 or c.x < gap_col):
				gap_col = c.x
		gap_columns.append(gap_col)

	_pending_clear_rows = full_rows
	_pending_clear_gap_columns = gap_columns
	_pending_t_spin_type = t_spin_type
	_is_clearing = true
	_clear_flash_timer = 0.0

## 閃爍停頓結束後真正執行消行——見 CLEAR_FLASH_SEC 的說明。計分順序：先用
## 「這次清除之前」的 _back_to_back_active/_combo_count 算這次的分數，算完
## 才更新這兩個狀態給下一次用（不能先更新，不然這次自己會吃到自己剛觸發的
## B2B/combo）。
func _finish_clear() -> void:
	var count := board.clear_lines(_pending_clear_rows)
	lines_cleared_total += count
	var is_perfect := board.is_board_empty()
	var combo_bonus := COMBO_SCORE_PER_STEP * _combo_count if count > 0 else 0
	_add_score((_base_clear_score(count, _pending_t_spin_type, is_perfect) + combo_bonus) * level)
	var attack_power := _attack_power_for_clear(count, _pending_t_spin_type, is_perfect)
	_update_streaks(count)
	lines_cleared.emit(count)
	attack_ready.emit(attack_power, _pending_clear_gap_columns)
	var new_level := 1 + int(lines_cleared_total / float(LINES_PER_LEVEL))
	if new_level != level:
		level = new_level
		level_changed.emit(level)

	_is_clearing = false
	_pending_clear_rows = []
	_pending_clear_gap_columns = []
	_pending_t_spin_type = 0
	_has_held_this_turn = false
	_spawn_piece(randomizer.get_next_piece())

## count 是這次清掉的行數，t_spin_type 是 _detect_t_spin() 的結果，is_perfect
## 是清完之後盤面是否全空——Perfect Clear 的分數表本身就是「總分」，會蓋掉
## 一般消行/T-Spin 分數，不是疊加（照 guideline 慣例）。
func _base_clear_score(count: int, t_spin_type: int, is_perfect: bool) -> int:
	if is_perfect and count > 0:
		if _back_to_back_active and PERFECT_CLEAR_SCORE_B2B_BY_COUNT.has(count):
			return PERFECT_CLEAR_SCORE_B2B_BY_COUNT[count]
		return int(PERFECT_CLEAR_SCORE_BY_COUNT.get(count, 0))
	if t_spin_type == 2:
		if _back_to_back_active and TSPIN_SCORE_B2B_BY_COUNT.has(count):
			return TSPIN_SCORE_B2B_BY_COUNT[count]
		return int(TSPIN_SCORE_BY_COUNT.get(count, 0))
	if t_spin_type == 1:
		if _back_to_back_active and TSPIN_MINI_SCORE_B2B_BY_COUNT.has(count):
			return TSPIN_MINI_SCORE_B2B_BY_COUNT[count]
		return int(TSPIN_MINI_SCORE_BY_COUNT.get(count, 0))
	if _back_to_back_active and LINE_SCORE_B2B_BY_COUNT.has(count):
		return LINE_SCORE_B2B_BY_COUNT[count]
	return int(LINE_SCORE_BY_COUNT.get(count, 0))

## 攻擊力（給 BattleDirector 的垃圾行系統用）——跟 _base_clear_score() 同一套
## 判定順序，但查獨立的攻擊力表（見常數區說明，量級跟分數脫鉤）。跟分數
## 一樣要用「這次清除之前」的 _back_to_back_active/_combo_count 算，呼叫端
## （_finish_clear()）保證在 _update_streaks() 之前呼叫這個函式。
func _attack_power_for_clear(count: int, t_spin_type: int, is_perfect: bool) -> int:
	if is_perfect and count > 0:
		return PERFECT_CLEAR_ATTACK
	var power := 0
	if t_spin_type == 2:
		power = int(TSPIN_ATTACK_BY_COUNT.get(count, 0))
	elif t_spin_type == 1:
		power = int(TSPIN_MINI_ATTACK_BY_COUNT.get(count, 0))
	else:
		power = int(LINE_ATTACK_BY_COUNT.get(count, 0))
	var is_difficult := count == 4 or t_spin_type > 0
	if is_difficult and _back_to_back_active:
		power += B2B_ATTACK_BONUS
	power += int(_combo_count / COMBO_ATTACK_DIVISOR)
	return power

## Tetris（4 行）或任何有清到行的 T-Spin 算「難清」，會延續/開啟 B2B；1~3 行
## 的普通消行會打斷 B2B（照 guideline，這兩種以外都不算難清）。
func _update_streaks(count: int) -> void:
	if count <= 0:
		_combo_count = 0
		return
	_combo_count += 1
	_back_to_back_active = (count == 4 or _pending_t_spin_type > 0)

## 3-corner T-Spin 判定：T 型方塊、鎖定前最後一次成功操作是旋轉（不是位移）
## 才有機會成立，且「中心格」四個角要至少 3 個被佔用（牆外/地板外/既有方塊
## 都算佔用）。面向 T 尖端方向的兩個角都佔用算完整 T-Spin，否則算 Mini（標準
## 簡化判定，不含官方規則「用第 5 組 kick 一律算完整」的特例，但絕大多數
## 情況跟正式判定一致）。回傳 0=無/1=Mini/2=完整。
func _detect_t_spin() -> int:
	if _active_type != TetrisPieceData.PieceType.T or not _last_action_was_rotation:
		return 0
	var center := _active_pos + Vector2i(1, 1)
	var corner_offsets := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	var front_indices: Array
	match posmod(_active_rotation, 4):
		0: front_indices = [0, 1]
		1: front_indices = [1, 3]
		2: front_indices = [2, 3]
		_: front_indices = [0, 2]
	var corners_filled := 0
	var front_filled := 0
	for i in range(4):
		var corner: Vector2i = center + corner_offsets[i]
		var occupied := corner.x < 0 or corner.x >= TetrisBoard.WIDTH or corner.y >= TetrisBoard.TOTAL_HEIGHT \
			or (corner.y >= 0 and board.get_cell(corner.x, corner.y) != TetrisBoard.EMPTY_CELL)
		if occupied:
			corners_filled += 1
			if front_indices.has(i):
				front_filled += 1
	if corners_filled < 3:
		return 0
	return 2 if front_filled == 2 else 1

## 把待定的垃圾行真的疊上盤面（結算），由 BattleDirector 呼叫。
## gap_columns 陣列長度＝要疊幾行，元素是每行的缺口欄位。盤面整體往上推之後
## 目前下落方塊也要跟著往上平移，保持跟盤面內容的相對位置不變（這個平移
## 本身完全正常，不代表爆頂——下落方塊平移後的絕對座標變得很負是常態，
## 見 board.add_garbage_rows() 的說明）。真正的淘汰判斷是：(a) 被推出上緣
## 捨棄的那幾行本來就有真方塊，或 (b) 平移後目前方塊跟盤面（含新垃圾）
## 重疊放不下——(b) 這項如果正好在消行閃爍停頓期間觸發就跳過：_active_pos/
## _active_type 這時候還是上一顆「已經鎖進 board 裡」的殘留值，拿去跟剛平移
## 過的盤面比對一定會判定成「跟自己重疊」而誤判爆頂；停頓結束後
## _finish_clear() 會 respawn 新方塊，那時候的 _spawn_piece() 自己會做真正
## 有效的爆頂檢查，不會漏掉。
func inject_garbage(gap_columns: Array[int]) -> void:
	if is_game_over or gap_columns.is_empty():
		return
	var overflowed := board.add_garbage_rows(gap_columns)
	_active_pos.y -= gap_columns.size()
	if overflowed or (not _is_clearing and not _fits(_active_type, _active_rotation, _active_pos)):
		is_game_over = true
		game_over.emit()

## 給連線對戰斷線重連用（2026-09-23）：只還原到「上一顆鎖定完的狀態」，不含
## 正在下落到一半、還沒鎖定的那顆方塊——跟使用者確認過的簡化（重新連上後
## 直接從 randomizer 的下一顆重新 spawn，不接回斷線當下正在操作的那顆）。
## 呼叫端（BattleDirector）要保證擷取快照的時機點不是在 _is_clearing 消行
## 閃爍停頓期間（那段期間盤面/分數都還沒真正定案，見 _lock_active_piece()/
## _finish_clear() 的說明），等 tick() 正常跑完（不在停頓中）才能擷取，不然
## 存到一半算完的狀態，重連後對不上。
func get_resume_snapshot() -> Dictionary:
	return {
		"board": board.get_snapshot(),
		"randomizer": randomizer.get_snapshot(),
		"score": score,
		"lines_cleared_total": lines_cleared_total,
		"level": level,
		"hold_type": _hold_type,
		"has_hold_piece": _has_hold_piece,
		"combo_count": _combo_count,
		"back_to_back_active": _back_to_back_active,
	}

## 還原快照並直接生一顆新方塊接著玩（見上面 get_resume_snapshot() 的說明：
## 不還原正在下落到一半的那顆）。is_game_over 明確重設成 false——快照本來就
## 只會在「還沒淘汰」的狀態下擷取，這裡是防呆，不是預期會用到的分支。
func restore_from_snapshot(snapshot: Dictionary) -> void:
	board.load_snapshot(snapshot.get("board", {}))
	randomizer.load_snapshot(snapshot.get("randomizer", {}))
	score = snapshot.get("score", 0)
	lines_cleared_total = snapshot.get("lines_cleared_total", 0)
	level = snapshot.get("level", 1)
	_hold_type = snapshot.get("hold_type", TetrisPieceData.PieceType.I)
	_has_hold_piece = snapshot.get("has_hold_piece", false)
	_combo_count = snapshot.get("combo_count", 0)
	_back_to_back_active = snapshot.get("back_to_back_active", false)
	_has_held_this_turn = false
	is_game_over = false
	_is_clearing = false
	_pending_clear_rows = []
	_pending_clear_gap_columns = []
	_pending_t_spin_type = 0
	_spawn_piece(randomizer.get_next_piece())

func _spawn_piece(type: TetrisPieceData.PieceType) -> void:
	_active_type = type
	_active_rotation = 0
	_active_pos = Vector2i(SPAWN_X, SPAWN_Y)
	_gravity_timer = 0.0
	_lock_timer = 0.0
	_lock_resets = 0
	_is_on_surface = false
	_last_action_was_rotation = false
	if not _fits(_active_type, _active_rotation, _active_pos):
		is_game_over = true
		game_over.emit()

func _fits(type: TetrisPieceData.PieceType, rotation: int, pos: Vector2i) -> bool:
	return board.can_place(_world_cells(type, rotation, pos))

func _world_cells(type: TetrisPieceData.PieceType, rotation: int, pos: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in TetrisPieceData.get_cells(type, rotation):
		cells.append(c + pos)
	return cells

func _current_gravity_interval() -> float:
	var interval := BASE_GRAVITY_SEC * pow(GRAVITY_LEVEL_FACTOR, level - 1)
	return max(interval, MIN_GRAVITY_SEC)

func _add_score(amount: int) -> void:
	if amount <= 0:
		return
	score += amount
	score_changed.emit(score)
