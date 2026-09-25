## 對戰畫面裡一個對手的縮小版盤面。2026-09-21 起改成塞進 Battle.gd 依對手
## 人數（1~3）挑出的 `OpponentSlots1/2/3` 場景裡使用者自己排的 Slot 節點
## 底下（anchor 設成 PRESET_FULL_RECT 填滿整個 Slot），不再是固定像素大小——
## 格子大小改成每次 `_draw()` 依自己目前的 `size` 動態算，Slot 排多大這裡的
## 棋盤就多大，使用者換人數版面或拉 Slot 尺寸都不用改這裡的程式。純顯示
## 元件，資料來源是 BattleParticipant，戰鬥規則都在 BattleDirector，這裡不
## 判斷任何規則。
class_name OpponentPanel
extends Control

## 名字文字的預留高度，畫面/命中範圍都要扣掉這塊，跟棋盤格子本體分開。
const LABEL_HEIGHT := 20.0

## 由 Battle.gd 在 instantiate 之後立刻設定，設定好才會有東西可畫。
var participant: BattleParticipant
var pid: int = 0
## 指定目標攻擊開啟時，這個對手是不是玩家目前選的目標——Battle.gd 每幀更新，
## 用來決定要不要畫紅框。
var is_target: bool = false

## 點擊/觸控這個面板時發出，Battle.gd 監聽這個訊號呼叫
## BattleDirector.set_manual_target()，不用再靠 Battle.gd 自己算全域座標
## 命中測試（Control 自己的 gui_input 本來就會處理觸控/滑鼠共通的命中判斷）。
signal panel_tapped(pid: int)

func _ready() -> void:
	gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	var triggered: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if triggered:
		panel_tapped.emit(pid)

func _draw() -> void:
	if not participant:
		return
	var origin := Vector2(0, LABEL_HEIGHT)
	var available := Vector2(size.x, maxf(size.y - LABEL_HEIGHT, 1.0))
	var cell_size := maxf(minf(available.x / TetrisBoard.WIDTH, available.y / TetrisBoard.VISIBLE_HEIGHT), 2.0)
	var board_size := Vector2(TetrisBoard.WIDTH * cell_size, TetrisBoard.VISIBLE_HEIGHT * cell_size)

	TetrisBoardRenderer.draw_board_frame(self, origin, cell_size)
	TetrisBoardRenderer.draw_locked_cells(self, participant.controller.board, origin, cell_size, participant.controller.get_clearing_rows())
	## 對手是「本機模擬」的（AI，在權威裝置上）才有即時的下落方塊位置可以畫；
	## 遠端真人的 controller 在這台裝置上只是網路同步過來的鏡像（見
	## BattleDirector.is_local 的說明），只有鎖定之後的盤面格子是準的，目前
	## 下落到哪裡沒有即時資料，畫出來只會是誤導人的殘留值，不畫。
	if not participant.is_eliminated and not participant.controller.is_clearing() and participant.is_local:
		TetrisBoardRenderer.draw_active_piece(self, participant.controller, origin, cell_size)

	## 2026-09-25 使用者要求名字在盤面正中央——用 HORIZONTAL_ALIGNMENT_CENTER
	## 一定要帶寬度參數（這裡帶整個面板的 size.x）才會真的置中，帶 -1 的話
	## CENTER 沒有意義（等同不置中，字會貼著畫布左邊）。
	draw_string(ThemeDB.fallback_font, Vector2(0, LABEL_HEIGHT - 6), _label_text(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 16)
	var dots_start := Vector2(origin.x - cell_size * 0.6, origin.y + (TetrisBoard.VISIBLE_HEIGHT - 0.5) * cell_size)
	TetrisBoardRenderer.draw_pending_dots(self, participant.pending_garbage.size(), dots_start, cell_size)

	## 斷線暫停中（見對戰規格：盤面暫停、等重連）——蓋一層半透明灰,跟單純
	## 「已淘汰」（文字提示,盤面本身還是清楚可見）視覺上要有區別。
	if participant.is_disconnected:
		draw_rect(Rect2(origin, board_size), Color(0.4, 0.4, 0.42, 0.55), true)

	if is_target:
		draw_rect(Rect2(origin, board_size).grow(4.0), Color(1.0, 0.15, 0.15), false, 4.0)

func _label_text() -> String:
	var text: String = BattleSettings.AI_LABELS.get(pid, "AI") if BattleSettings.is_ai(pid) else NetworkManager.get_peer_profile_name(pid)
	if participant.is_disconnected:
		text += "（暫停中）"
	elif participant.is_eliminated:
		text += "（已淘汰）"
	return text
