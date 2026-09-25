## 對戰畫面裡一個對手的縮小版盤面。2026-09-21 起改成塞進 Battle.gd 依對手
## 人數（1~3）挑出的 `OpponentSlots1/2/3` 場景裡使用者自己排的 Slot 節點
## 底下的 `PanelAspect`（AspectRatioContainer，2026-09-25 新增，讓示意框永遠
## 是正確的棋盤比例，見 OpponentSlots1/2/3.tscn 的說明）——格子大小改成每次
## `_draw()` 依自己目前的 `size` 動態算，Slot 排多大這裡的棋盤就多大，使用者
## 換人數版面或拉 Slot 尺寸都不用改這裡的程式。純顯示元件，資料來源是
## BattleParticipant，戰鬥規則都在 BattleDirector，這裡不判斷任何規則。
##
## 2026-09-25 使用者要求名字文字改成「示意文字」——原本名字是這裡自己
## `draw_string()` 畫死的，字體大小沒地方調。改成跟 HoldLabel/NextLabel
## 同一套做法：`PanelAspect` 底下多一個真的 `NameLabel` 節點（跟這個
## OpponentPanel 同一層、共用 AspectRatioContainer 算出來的同一塊區域），
## 使用者直接在編輯器裡調它的字體大小/位置，這裡只負責每幀把文字內容寫
## 進去，不再自己畫字——名字預留高度也改成讀 NameLabel 目前的實際大小
## （跟著使用者調的字體大小走），不再是寫死的 LABEL_HEIGHT。
## 待定垃圾行點點也比照本地玩家（見 Battle.gd `_draw_pending_garbage_bar()`）
## 換成長條狀，一樣多一個真的 `GarbageBarAnchor` 節點給使用者調粗細/位置，
## 這裡讀它目前的寬度當作要幫棋盤讓出多少空間。
class_name OpponentPanel
extends Control

## 找不到 NameLabel/GarbageBarAnchor 節點時的備援尺寸（理論上不會發生，
## 場景裡兩個節點都有放，純粹避免哪天節點被誤刪時整個 _draw() 直接壞掉）。
const FALLBACK_LABEL_HEIGHT := 20.0
const FALLBACK_BAR_WIDTH := 8.0

## 由 Battle.gd 在 instantiate 之後立刻設定，設定好才會有東西可畫。
var participant: BattleParticipant
var pid: int = 0
## 指定目標攻擊開啟時，這個對手是不是玩家目前選的目標——Battle.gd 每幀更新，
## 用來決定要不要畫紅框。
var is_target: bool = false

## 這兩個都是跟自己同一層（parent 底下）的靜態場景節點，_ready() 快取一次
## 就好，不用每幀 find_child()。
var _name_label: Label
var _garbage_bar_anchor: Control

## 點擊/觸控這個面板時發出，Battle.gd 監聽這個訊號呼叫
## BattleDirector.set_manual_target()，不用再靠 Battle.gd 自己算全域座標
## 命中測試（Control 自己的 gui_input 本來就會處理觸控/滑鼠共通的命中判斷）。
signal panel_tapped(pid: int)

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	var parent := get_parent()
	_name_label = parent.get_node_or_null("NameLabel") as Label
	_garbage_bar_anchor = parent.get_node_or_null("GarbageBarAnchor") as Control

func _on_gui_input(event: InputEvent) -> void:
	var triggered: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if triggered:
		panel_tapped.emit(pid)

func _draw() -> void:
	if not participant:
		return
	if _name_label:
		_name_label.text = _label_text()
	var label_height := TetrisBoardRenderer.effective_size(_name_label).y if _name_label else FALLBACK_LABEL_HEIGHT
	var bar_width := TetrisBoardRenderer.effective_size(_garbage_bar_anchor).x if _garbage_bar_anchor else FALLBACK_BAR_WIDTH

	var origin := Vector2(bar_width, label_height)
	var available := Vector2(maxf(size.x - bar_width, 1.0), maxf(size.y - label_height, 1.0))
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

	## 垃圾長條：跟本地玩家那條同一個畫法（底色+由下往上填滿），畫在棋盤
	## 左側、緊貼 origin.x 左邊，高度對齊棋盤實際高度（不是整個面板高度）。
	var bar_rect := Rect2(Vector2(0, origin.y), Vector2(bar_width, board_size.y))
	draw_rect(bar_rect, Color(0.2, 0.2, 0.24), true)
	var garbage_ratio := clampf(float(participant.pending_garbage.size()) / float(TetrisBoard.VISIBLE_HEIGHT), 0.0, 1.0)
	var fill_height := bar_rect.size.y * garbage_ratio
	draw_rect(Rect2(Vector2(0, bar_rect.position.y + bar_rect.size.y - fill_height), Vector2(bar_width, fill_height)), TetrisPieceData.GARBAGE_COLOR, true)

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
