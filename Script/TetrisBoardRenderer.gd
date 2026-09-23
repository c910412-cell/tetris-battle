## 共用的 Tetris 棋盤畫面繪製工具（棋盤格/鎖定方塊/ghost/hold-next 面板/
## 垃圾行）。純靜態函式，不持有狀態——`Board.gd`（無盡挑戰，完整版面）跟
## `Battle.gd`（對戰畫面，自己的盤面用完整版、對手用縮小版）都呼叫這裡，
## 避免同一份畫圖邏輯維護兩份（2026-09-21 從 Board.gd 抽出來，見
## Milestone 1 對戰計畫）。所有函式的 `ci` 參數必須是正在自己 `_draw()`
## callback 裡的那個 CanvasItem（Godot 的畫圖呼叫只在該節點的 redraw
## pass 期間有效）。
class_name TetrisBoardRenderer
extends RefCounted

const GRID_LINE_COLOR := Color(0.2, 0.2, 0.24)
const BG_COLOR := Color(0.08, 0.08, 0.1)
## 消行閃爍停頓期間（見 TetrisGameController.CLEAR_FLASH_SEC）整行畫成這個
## 顏色，蓋掉方塊原本的顏色，讓玩家能一眼看出「這行判定滿了、即將消除」。
const FLASH_COLOR := Color(1.0, 1.0, 1.0)
## 待定垃圾行點點的美術素材（2026-09-21 使用者提供，見 Image/ 資料夾）。
## Battle.gd 自己的盤面跟 OpponentPanel.gd 對手縮小版共用同一張，集中放在
## 這裡載入一次，不用兩邊各自 preload。
const DOT_TEXTURE := preload("res://Image/垃圾點點.png")

## 2026-09-22：算「使用者排版節點」的實際視覺大小要用這個，不要直接讀
## `.size`——使用者可能用 Inspector 的 Scale（或縮放工具）調整過這個節點
## 本身，也可能把它拖進另一個有 Scale 的父節點底下（例如塞進 BoardAnchor
## 裡），這裡用 `get_global_transform().get_scale()` 把「自己的 Scale」+
## 「所有祖先節點的 Scale」都疊乘進去，才會跟編輯器裡實際看到的視覺大小
## 一致，不管巢狀幾層都準。Board.gd/Battle.gd 算 cell_size、Hold/Next 面板
## 範圍、結算倒數條範圍都要透過這個，不要自己重算一次。
static func effective_size(control: Control) -> Vector2:
	return control.size * control.get_global_transform().get_scale()

static func draw_board_frame(ci: CanvasItem, origin: Vector2, cell_size: float) -> void:
	var board_w := cell_size * TetrisBoard.WIDTH
	var board_h := cell_size * TetrisBoard.VISIBLE_HEIGHT
	ci.draw_rect(Rect2(origin, Vector2(board_w, board_h)), BG_COLOR, true)
	for x in range(TetrisBoard.WIDTH + 1):
		var px := origin.x + x * cell_size
		ci.draw_line(Vector2(px, origin.y), Vector2(px, origin.y + board_h), GRID_LINE_COLOR)
	for y in range(TetrisBoard.VISIBLE_HEIGHT + 1):
		var py := origin.y + y * cell_size
		ci.draw_line(Vector2(origin.x, py), Vector2(origin.x + board_w, py), GRID_LINE_COLOR)

## 垃圾行（TetrisBoard.GARBAGE_CELL）畫白色，一般方塊查 TetrisPieceData.COLORS。
## flash_rows 是目前正在消行閃爍停頓中的行（TOTAL_HEIGHT 座標，見
## TetrisGameController.get_clearing_rows()）——這些行整行畫成 FLASH_COLOR，
## 蓋掉底下原本的顏色判斷，不影響其餘正常格子。
static func draw_locked_cells(ci: CanvasItem, board: TetrisBoard, origin: Vector2, cell_size: float, flash_rows: Array = []) -> void:
	for y in range(TetrisBoard.BUFFER_ROWS, TetrisBoard.TOTAL_HEIGHT):
		var is_flashing := flash_rows.has(y)
		for x in range(TetrisBoard.WIDTH):
			var value := board.get_cell(x, y)
			if value == TetrisBoard.EMPTY_CELL:
				continue
			if is_flashing:
				draw_cell(ci, origin, cell_size, x, y - TetrisBoard.BUFFER_ROWS, FLASH_COLOR)
			elif value == TetrisBoard.GARBAGE_CELL:
				draw_cell(ci, origin, cell_size, x, y - TetrisBoard.BUFFER_ROWS, TetrisPieceData.GARBAGE_COLOR)
			else:
				draw_cell(ci, origin, cell_size, x, y - TetrisBoard.BUFFER_ROWS, TetrisPieceData.COLORS[value])

static func draw_ghost(ci: CanvasItem, controller: TetrisGameController, origin: Vector2, cell_size: float) -> void:
	var color: Color = TetrisPieceData.COLORS[controller.get_active_type()]
	for c in controller.get_ghost_cells():
		if c.y >= TetrisBoard.BUFFER_ROWS:
			draw_cell_outline(ci, origin, cell_size, c.x, c.y - TetrisBoard.BUFFER_ROWS, color)

static func draw_active_piece(ci: CanvasItem, controller: TetrisGameController, origin: Vector2, cell_size: float) -> void:
	var color: Color = TetrisPieceData.COLORS[controller.get_active_type()]
	for c in controller.get_active_cells():
		if c.y >= TetrisBoard.BUFFER_ROWS:
			draw_cell(ci, origin, cell_size, c.x, c.y - TetrisBoard.BUFFER_ROWS, color)

static func draw_cell(ci: CanvasItem, origin: Vector2, cell_size: float, col: int, row: int, color: Color) -> void:
	var pos := origin + Vector2(col, row) * cell_size
	ci.draw_rect(Rect2(pos + Vector2(1, 1), Vector2(cell_size - 2, cell_size - 2)), color, true)

static func draw_cell_outline(ci: CanvasItem, origin: Vector2, cell_size: float, col: int, row: int, color: Color) -> void:
	var pos := origin + Vector2(col, row) * cell_size
	ci.draw_rect(Rect2(pos + Vector2(2, 2), Vector2(cell_size - 4, cell_size - 4)), Color(color, 0.45), false, 2.0)

## 面板背景（HOLD/NEXT 的白底框）。標題文字（"HOLD"/"NEXT"）2026-09-21 改成
## 場景裡真的 Label 節點（`HoldLabel`/`NextLabel`），使用者自己排位置，這裡
## 不再用 draw_string 畫死。
static func draw_side_panel_bg(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, Color(0.12, 0.12, 0.16), true)
	ci.draw_rect(rect, Color(0.3, 0.3, 0.35), false, 2.0)

static func draw_side_panel(ci: CanvasItem, rect: Rect2, type: int) -> void:
	draw_side_panel_bg(ci, rect)
	if type >= 0:
		draw_mini_piece(ci, rect, type)

static func draw_mini_piece(ci: CanvasItem, rect: Rect2, type: int) -> void:
	var mini_cell := 16.0
	var cells := TetrisPieceData.get_cells(type as TetrisPieceData.PieceType, 0)
	var origin := rect.position + rect.size / 2.0 - Vector2(mini_cell * 2, mini_cell * 2)
	var color: Color = TetrisPieceData.COLORS[type]
	for c in cells:
		var pos := origin + Vector2(c.x, c.y) * mini_cell
		ci.draw_rect(Rect2(pos + Vector2(1, 1), Vector2(mini_cell - 2, mini_cell - 2)), color, true)

## 待定垃圾行的小點點，一個點代表一行還沒結算的垃圾行，由下往上疊，畫
## DOT_TEXTURE 貼圖（2026-09-21 從畫圓形改成真的美術素材）。
## Battle.gd（自己的盤面）跟 OpponentPanel.gd（對手縮小版）共用這個，不要
## 各自複製一份。start_pos 是「最下面那個點」要畫的位置——2026-09-22 起
## Battle.gd 改成每一幀直接用目前的 board origin/cell_size 現算（不再讀
## `PendingDotsAnchor` 節點自己的固定座標），確保盤面被使用者放大縮小時
## 點點永遠對齊在正確的格子正中間，OpponentPanel 縮小版盤面本來就是自己
## 現算。spacing 是每個點之間的垂直間距（通常直接傳 cell_size，這樣點的
## 間距才會跟著格子大小縮放）。size_ratio 是點的貼圖大小相對 spacing 的
## 比例——2026-09-22 起拆成參數讓外部（PendingDotsAnchor.dot_size_ratio）
## 自己控制大小，不是內部寫死 0.55；因為還是乘上 spacing（=目前 cell_size），
## 使用者調完比例後，盤面縮放時點的大小還是會跟著等比例縮放，不用重調。
## 點數上限跟盤面可視高度一樣（20），避免異常狀況下無限往上疊到畫面其他地方。
static func draw_pending_dots(ci: CanvasItem, count: int, start_pos: Vector2, spacing: float, size_ratio: float = 0.55) -> void:
	var capped_count := mini(count, TetrisBoard.VISIBLE_HEIGHT)
	var size := spacing * size_ratio
	var half := size / 2.0
	for i in range(capped_count):
		var dot_y := start_pos.y - i * spacing
		ci.draw_texture_rect(DOT_TEXTURE, Rect2(Vector2(start_pos.x - half, dot_y - half), Vector2(size, size)), false)
