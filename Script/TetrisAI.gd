## Tetris AI：窮舉目前方塊的所有旋轉 × 欄位擺法，用經典加權公式（消行數/
## 疊高總和/洞數/起伏度）評分——2026-09-21 加強：現在會用到「所有功能」
## （見對戰規格）：
##   - hold()：額外算一次「如果現在 hold 交換，換上來的方塊擺最好能拿幾分」，
##     贏過直接用目前方塊夠多分才會真的 hold（避免每次都在瞎換）。
##   - next piece 預判：對立即分數排名前幾名的候選擺法，再往下看一步——把
##     next piece 疊上去，取那一步的最佳分數一起加權計入（只對前幾名做，
##     不是窮舉×窮舉，避免一幀內跑太貴）。
## 選好之後用跟真人一樣的 controller.hold()/move()/rotate()/hard_drop() 執行，
## 不偽造 Input 事件（每個 AI 都有自己私有的 TetrisGameController）。三個難度
## 只靠權重/反應延遲/選子雜訊做出差異，見
## memory/tetris_multiplayer_battle_design.md 對戰規格。
class_name TetrisAI
extends RefCounted

enum Level { EASY, NORMAL, HARD }

const _PRESETS := {
	Level.EASY: {
		"decision_delay": 0.6, "noise_chance": 0.35,
		"w_lines": 1.0, "w_height": 0.4, "w_holes": 0.5, "w_bumpiness": 0.2,
	},
	Level.NORMAL: {
		"decision_delay": 0.3, "noise_chance": 0.12,
		"w_lines": 1.2, "w_height": 0.6, "w_holes": 0.9, "w_bumpiness": 0.4,
	},
	Level.HARD: {
		"decision_delay": 0.1, "noise_chance": 0.03,
		"w_lines": 1.5, "w_height": 0.8, "w_holes": 1.2, "w_bumpiness": 0.6,
	},
}

## next piece 預判分數的權重。
const LOOKAHEAD_WEIGHT := 0.6
## 預判只對立即分數前幾名的候選擺法做，避免窮舉×窮舉的 O(n²) 成本。
const LOOKAHEAD_TOP_K := 5
## hold 換上來的方塊分數要贏過直接用目前方塊「多少」才值得真的去 hold。
const HOLD_BIAS := 1.5

## 執行規劃好的旋轉/位移動作時，每一步之間的間隔。
const STEP_INTERVAL := 0.05

var controller: TetrisGameController
var level: int = Level.NORMAL

var _rng: RandomNumberGenerator
var _think_timer: float = 0.0
var _step_timer: float = 0.0
var _plan: Array = []
var _has_plan: bool = false

func _init(game_controller: TetrisGameController, ai_level: int = Level.NORMAL, rng_seed: int = 0) -> void:
	controller = game_controller
	level = ai_level
	_rng = RandomNumberGenerator.new()
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	controller.piece_locked.connect(_on_piece_locked)

func _on_piece_locked() -> void:
	_has_plan = false
	_plan.clear()
	_think_timer = 0.0
	_step_timer = 0.0

func decide_and_act(delta: float) -> void:
	if controller.is_game_over or controller.is_clearing():
		return

	if not _has_plan:
		_think_timer += delta
		var preset: Dictionary = _PRESETS[level]
		if _think_timer >= preset["decision_delay"]:
			_build_plan(preset)
		return

	_step_timer += delta
	while _step_timer >= STEP_INTERVAL and not _plan.is_empty():
		_step_timer -= STEP_INTERVAL
		var action: String = _plan.pop_front()
		match action:
			"rotate_cw":
				controller.rotate(true)
			"rotate_ccw":
				controller.rotate(false)
			"move_left":
				controller.move(-1)
			"move_right":
				controller.move(1)

	if _has_plan and _plan.is_empty():
		_has_plan = false
		controller.hard_drop()

## 兩步決策：先用便宜的「只算立即分數」比較直接用目前方塊 vs hold 換一個
## 方塊，決定要不要 hold；只對最後真的要用的那個方塊做一次有預判的完整搜尋。
func _build_plan(preset: Dictionary) -> void:
	var current_type := controller.get_active_type()
	var hold_type := controller.get_hold_type()
	var next_types := controller.peek_next_pieces(1)
	var lookahead_type: TetrisPieceData.PieceType = next_types[0] if not next_types.is_empty() else current_type

	var start_rotation := controller.get_active_rotation()
	var start_pos := controller.get_active_position()
	var snapshot := controller.board.get_snapshot()

	var direct_cheap := _search_best_placement(current_type, lookahead_type, snapshot, start_pos.y, preset, false)
	var swapped_type: TetrisPieceData.PieceType = hold_type if hold_type >= 0 else lookahead_type
	var hold_cheap := _search_best_placement(swapped_type, lookahead_type, snapshot, TetrisGameController.SPAWN_Y, preset, false)

	var direct_has_choice: bool = not direct_cheap.is_empty()
	var hold_has_choice: bool = not hold_cheap.is_empty()
	var use_hold: bool = hold_has_choice and (not direct_has_choice or hold_cheap["score"] > direct_cheap["score"] + HOLD_BIAS)

	var chosen: Dictionary
	if use_hold:
		controller.hold()
		start_rotation = controller.get_active_rotation()
		start_pos = controller.get_active_position()
		chosen = _search_best_placement(swapped_type, lookahead_type, snapshot, TetrisGameController.SPAWN_Y, preset, true)
	else:
		chosen = _search_best_placement(current_type, lookahead_type, snapshot, start_pos.y, preset, true)

	if chosen.is_empty():
		_has_plan = true
		_plan = []
		return

	_plan = _build_action_sequence(start_rotation, start_pos.x, chosen["rotation"], chosen["x"])
	_has_plan = true

## 窮舉 piece_type 的旋轉×欄位擺法。use_lookahead=false 時只回傳立即分數
## 最高的（便宜，給 hold 判斷用）；true 時對前幾名額外模擬 lookahead_type
## 疊上去能拿幾分一起加權。找不到任何合法擺法回傳空 Dictionary。
func _search_best_placement(piece_type: TetrisPieceData.PieceType, lookahead_type: TetrisPieceData.PieceType, snapshot: Dictionary, spawn_y: int, preset: Dictionary, use_lookahead: bool) -> Dictionary:
	var candidates: Array = []
	for rotation in range(4):
		var cells_local := TetrisPieceData.get_cells(piece_type, rotation)
		var min_local_x := 999
		var max_local_x := -999
		for c in cells_local:
			min_local_x = min(min_local_x, c.x)
			max_local_x = max(max_local_x, c.x)

		for x in range(-min_local_x, TetrisBoard.WIDTH - max_local_x):
			var temp_board := TetrisBoard.new()
			temp_board.load_snapshot(snapshot)
			var drop_pos := Vector2i(x, spawn_y)
			while temp_board.can_place(_offset_cells(cells_local, drop_pos + Vector2i(0, 1))):
				drop_pos.y += 1
			if not temp_board.can_place(_offset_cells(cells_local, drop_pos)):
				continue

			var immediate_score := _evaluate(temp_board, cells_local, drop_pos, piece_type, preset)
			candidates.append({"rotation": rotation, "x": x, "score": immediate_score, "board": temp_board})

	if candidates.is_empty():
		return {}

	candidates.sort_custom(func(a, b): return a["score"] > b["score"])

	if not use_lookahead:
		return candidates[0]

	var top_count: int = mini(LOOKAHEAD_TOP_K, candidates.size())
	for i in range(top_count):
		var candidate: Dictionary = candidates[i]
		var lookahead_score := _best_lookahead_score(candidate["board"], lookahead_type, preset)
		candidate["score"] = candidate["score"] + LOOKAHEAD_WEIGHT * lookahead_score
	var top_candidates := candidates.slice(0, top_count)
	top_candidates.sort_custom(func(a, b): return a["score"] > b["score"])

	var choice: Dictionary = top_candidates[0]
	if top_candidates.size() > 1 and _rng.randf() < preset["noise_chance"]:
		var pick := _rng.randi_range(0, min(2, top_candidates.size() - 1))
		choice = top_candidates[pick]
	return choice

## board_after 是已經鎖定目前這塊、消完行之後的盤面，窮舉 lookahead_type
## 能拿到的最高分（一層預判，不模擬更深的連鎖）。
func _best_lookahead_score(board_after: TetrisBoard, lookahead_type: TetrisPieceData.PieceType, preset: Dictionary) -> float:
	var best_score := -INF
	var found_any := false
	var snapshot := board_after.get_snapshot()
	for rotation in range(4):
		var cells_local := TetrisPieceData.get_cells(lookahead_type, rotation)
		var min_local_x := 999
		var max_local_x := -999
		for c in cells_local:
			min_local_x = min(min_local_x, c.x)
			max_local_x = max(max_local_x, c.x)
		for x in range(-min_local_x, TetrisBoard.WIDTH - max_local_x):
			var temp_board := TetrisBoard.new()
			temp_board.load_snapshot(snapshot)
			var drop_pos := Vector2i(x, 0)
			while temp_board.can_place(_offset_cells(cells_local, drop_pos + Vector2i(0, 1))):
				drop_pos.y += 1
			if not temp_board.can_place(_offset_cells(cells_local, drop_pos)):
				continue
			var score := _evaluate(temp_board, cells_local, drop_pos, lookahead_type, preset)
			if score > best_score:
				best_score = score
				found_any = true
	return best_score if found_any else 0.0

## 先轉到目標旋轉狀態、再平移到目標欄。SRS wall kick 偶爾會在旋轉時順便
## 平移方塊，這裡沒有重新讀取旋轉後的實際位置去修正位移量——極端情況下
## 可能落點跟預期差一兩欄，但 move()/rotate() 本身一定合法。
func _build_action_sequence(start_rotation: int, start_x: int, target_rotation: int, target_x: int) -> Array:
	var actions: Array = []
	var cw_steps := posmod(target_rotation - start_rotation, 4)
	if cw_steps <= 4 - cw_steps:
		for _i in range(cw_steps):
			actions.append("rotate_cw")
	else:
		for _i in range(4 - cw_steps):
			actions.append("rotate_ccw")

	var dx := target_x - start_x
	for _i in range(abs(dx)):
		actions.append("move_right" if dx > 0 else "move_left")
	return actions

func _offset_cells(cells_local: Array, pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in cells_local:
		result.append(c + pos)
	return result

func _evaluate(temp_board: TetrisBoard, cells_local: Array, drop_pos: Vector2i, piece_type: TetrisPieceData.PieceType, preset: Dictionary) -> float:
	temp_board.lock_cells(_offset_cells(cells_local, drop_pos), piece_type)
	var full_rows := temp_board.find_full_lines()
	var lines := full_rows.size()
	if lines > 0:
		temp_board.clear_lines(full_rows)

	var heights: Array[int] = []
	heights.resize(TetrisBoard.WIDTH)
	var holes := 0
	for x in range(TetrisBoard.WIDTH):
		var found_top := false
		var col_height := 0
		for y in range(TetrisBoard.TOTAL_HEIGHT):
			if temp_board.get_cell(x, y) != TetrisBoard.EMPTY_CELL:
				if not found_top:
					col_height = TetrisBoard.TOTAL_HEIGHT - y
					found_top = true
			elif found_top:
				holes += 1
		heights[x] = col_height

	var aggregate_height := 0
	for h in heights:
		aggregate_height += h
	var bumpiness := 0
	for x in range(TetrisBoard.WIDTH - 1):
		bumpiness += abs(heights[x] - heights[x + 1])

	return (preset["w_lines"] * lines
		- preset["w_height"] * aggregate_height
		- preset["w_holes"] * holes
		- preset["w_bumpiness"] * bumpiness)
