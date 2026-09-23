## 純邏輯棋盤（10 寬 × 20 高視覺區 + 2 隱藏緩衝行在最上方），不依賴場景樹。
## 供 TetrisGameController 呼叫，也是之後網路同步「盤面狀態」序列化的基本
## 單位（get_snapshot/load_snapshot 先寫好，這輪沒有呼叫端，同
## NetworkSnapshotBuffer.gd 目前「先移植、還沒人用」的做法一致）。
class_name TetrisBoard
extends RefCounted

const WIDTH := 10
const VISIBLE_HEIGHT := 20
const BUFFER_ROWS := 2
const TOTAL_HEIGHT := VISIBLE_HEIGHT + BUFFER_ROWS

const EMPTY_CELL := -1
## 垃圾行格子的哨兵值，跟 TetrisPieceData.PieceType 的 0~6 區隔開，畫面層
## 用這個值判斷要畫白色（TetrisPieceData.GARBAGE_COLOR）而不是查 COLORS 表。
const GARBAGE_CELL := 7

var _grid: Array = []

func _init() -> void:
	clear()

func clear() -> void:
	_grid = []
	for _y in range(TOTAL_HEIGHT):
		var row: Array = []
		row.resize(WIDTH)
		row.fill(EMPTY_CELL)
		_grid.append(row)

func get_cell(x: int, y: int) -> int:
	if x < 0 or x >= WIDTH or y < 0 or y >= TOTAL_HEIGHT:
		return EMPTY_CELL
	return _grid[y][x]

## 檢查一組世界座標格子是否全部可放置：沒有超出左右邊界/沒有穿過地板、
## 也沒有跟既有方塊重疊。y<0（緩衝行上緣以上）允許暫時超出，讓方塊可以
## 從生成點旋轉時稍微超出頂端。
func can_place(cells: Array[Vector2i]) -> bool:
	for c in cells:
		if c.x < 0 or c.x >= WIDTH:
			return false
		if c.y >= TOTAL_HEIGHT:
			return false
		if c.y >= 0 and _grid[c.y][c.x] != EMPTY_CELL:
			return false
	return true

func lock_cells(cells: Array[Vector2i], type: TetrisPieceData.PieceType) -> void:
	for c in cells:
		if c.y >= 0:
			_grid[c.y][c.x] = type

func find_full_lines() -> Array[int]:
	var full_rows: Array[int] = []
	for y in range(TOTAL_HEIGHT):
		var full := true
		for x in range(WIDTH):
			if _grid[y][x] == EMPTY_CELL:
				full = false
				break
		if full:
			full_rows.append(y)
	return full_rows

## 整體重建而非逐行搬移，避免多行同時消除時的 index 位移錯誤。
func clear_lines(rows_to_clear: Array[int]) -> int:
	if rows_to_clear.is_empty():
		return 0
	var clear_set := {}
	for r in rows_to_clear:
		clear_set[r] = true
	var surviving: Array = []
	for y in range(TOTAL_HEIGHT):
		if not clear_set.has(y):
			surviving.append(_grid[y])
	var new_grid: Array = []
	for _i in range(rows_to_clear.size()):
		var row: Array = []
		row.resize(WIDTH)
		row.fill(EMPTY_CELL)
		new_grid.append(row)
	new_grid.append_array(surviving)
	_grid = new_grid
	return rows_to_clear.size()

## 從底部插入垃圾行、把既有內容整體往上推。gap_columns 陣列長度＝要插入
## 幾行，每個元素是那一行「沒有被垃圾填滿」的缺口欄位。回傳 true 代表被推
## 出上緣、捨棄掉的那幾行裡本來就有真的方塊（=堆疊被推爆頂，呼叫端
## TetrisGameController.inject_garbage() 靠這個判斷是不是要淘汰，不是靠
## 目前下落方塊被推去哪裡——那個永遠會變、不代表真的爆頂，之前拿它來判斷
## 是誤判的舊版寫法，已修正，見對戰規格踩坑紀錄）。
func add_garbage_rows(gap_columns: Array[int]) -> bool:
	if gap_columns.is_empty():
		return false
	var count := gap_columns.size()
	var discarded: Array = _grid.slice(0, count)
	var overflowed := false
	for row in discarded:
		for cell in row:
			if cell != EMPTY_CELL:
				overflowed = true
				break
		if overflowed:
			break
	var surviving: Array = _grid.slice(count, TOTAL_HEIGHT)
	var new_grid: Array = surviving.duplicate()
	for gap in gap_columns:
		var row: Array = []
		row.resize(WIDTH)
		row.fill(GARBAGE_CELL)
		if gap >= 0 and gap < WIDTH:
			row[gap] = EMPTY_CELL
		new_grid.append(row)
	_grid = new_grid
	return overflowed

## 給 Perfect Clear 判斷用：盤面（含緩衝行）整個掃一次是否全空。
func is_board_empty() -> bool:
	for y in range(TOTAL_HEIGHT):
		for x in range(WIDTH):
			if _grid[y][x] != EMPTY_CELL:
				return false
	return true

func get_snapshot() -> Dictionary:
	return {"grid": _grid.duplicate(true)}

func load_snapshot(snapshot: Dictionary) -> void:
	_grid = (snapshot.get("grid", []) as Array).duplicate(true)
