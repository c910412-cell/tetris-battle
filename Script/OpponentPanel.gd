## 對戰畫面裡一個對手的縮小版盤面。2026-09-21 起改成塞進 Battle.gd 依對手
## 人數（1~3）挑出的 `OpponentSlots1/2/3` 場景裡使用者自己排的 Slot 節點
## 底下——格子大小改成每次 `_draw()` 依自己目前的 `size` 動態算，Slot 排多
## 大這裡的棋盤就多大，使用者換人數版面或拉 Slot 尺寸都不用改這裡的程式。
## 純顯示元件，資料來源是 BattleParticipant，戰鬥規則都在 BattleDirector，
## 這裡不判斷任何規則。
##
## 2026-09-25 使用者要求名字文字改成「示意文字」——原本名字是這裡自己
## `draw_string()` 畫死的，字體大小沒地方調。改成跟 HoldLabel/NextLabel
## 同一套做法：場景裡多一個真的 `NameLabel` 節點，使用者直接在編輯器裡調
## 它的字體大小/位置，這裡只負責每幀把文字內容寫進去，不再自己畫字——
## 名字預留高度也改成讀 NameLabel 目前的實際大小（跟著使用者調的字體大小
## 走），不再是寫死的 LABEL_HEIGHT。待定垃圾行點點也比照本地玩家（見
## Battle.gd `_draw_pending_garbage_bar()`）換成長條狀，一樣多一個真的
## `GarbageBarAnchor` 節點給使用者調粗細/位置，這裡讀它目前的寬度當作要
## 幫棋盤讓出多少空間。
## 這個節點跟 NameLabel/GarbageBarAnchor 是同一層的兄弟節點,見
## OpponentSlots1/2/3.tscn 裡的 `PanelContent`（純 Control,不是 Container）
## ——一開始直接放在 PanelAspect（AspectRatioContainer）底下,結果 Container
## 會整個無視子節點自己的 anchor/offset,NameLabel/GarbageBarAnchor 沒辦法
## 只當一小條、直接撐滿整個示意框,擠壓到這裡剩下的可用空間趨近於 0
## （使用者回報「別人盤面變得怪怪的」)——加了 PanelContent 這層之後才修好,
## 這裡的程式碼本身不用跟著改,因為都是靠 get_parent() 找同層兄弟節點,
## 父節點換了但層次關係沒變。
class_name OpponentPanel
extends Control

## 找不到 NameLabel/GarbageBarAnchor 節點時的備援尺寸（理論上不會發生，
## 場景裡兩個節點都有放，純粹避免哪天節點被誤刪時整個 _draw() 直接壞掉）。
const FALLBACK_LABEL_HEIGHT := 20.0
const FALLBACK_BAR_WIDTH := 8.0
## 2026-09-26 使用者要求：名字太長被切掉,改成自動縮小字體讓整個名字塞得下,
## 不要裁切/省略號——縮小的上限（也就是名字夠短時維持的大小）是使用者在
## 編輯器裡對 NameLabel 設定的字體大小,_ready() 快取這個原始值,之後只會
## 往下縮,不會放大。
const MIN_NAME_FONT_SIZE := 10.0

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
## NameLabel 原始（最大）字體大小,_ready() 讀一次使用者在編輯器裡設的值。
var _base_name_font_size: float = 20.0
## 2026-09-26 使用者回報：改用「NameLabel 固定 Control 高度打折扣」之後,
## 不同對手人數（OpponentSlots1/2/3,每組的 NameLabel 框高使用者各自設定,
## 沒有統一）打完折扣還是可能比實際文字高度矮,名字下緣被棋盤蓋住。使用者
## 明確要求「統一固定在棋盤上方 3px」——這只能用「目前字體大小實際的行高」
## 才算得準（跟框高完全無關,不管哪組 Slot 都一樣量得到正確答案）,所以這裡
## 改回讀即時字體大小算行高,棋盤大小會因此隨名字字體縮放有小幅變化（同一
## 字型行高差距通常只有幾 px,對整體棋盤大小影響很小),換來的是「名字絕對
## 不會被棋盤蓋住」這個更重要的保證。做法：快取上一幀縮完的字體大小,本幀
## 開頭用它量行高,本幀縮完再更新回來,一兩幀內收斂,肉眼看不出延遲。
var _current_name_font_size: float = 20.0
const NAME_TO_BOARD_GAP_PX := 3.0

## 點擊/觸控這個面板時發出，Battle.gd 監聽這個訊號呼叫
## BattleDirector.set_manual_target()，不用再靠 Battle.gd 自己算全域座標
## 命中測試（Control 自己的 gui_input 本來就會處理觸控/滑鼠共通的命中判斷）。
signal panel_tapped(pid: int)

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	var parent := get_parent()
	_name_label = parent.get_node_or_null("NameLabel") as Label
	_garbage_bar_anchor = parent.get_node_or_null("GarbageBarAnchor") as Control
	if _name_label:
		_base_name_font_size = _name_label.get_theme_font_size("font_size")
		_current_name_font_size = _base_name_font_size

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
		## 2026-09-25 使用者要求名字依隊伍改色（紅隊用紅色等等），跟分隊/
		## 戰績文字共用同一份 BattleSettings.TEAM_COLORS，顏色定義只放一個
		## 地方。
		_name_label.add_theme_color_override("font_color", BattleSettings.TEAM_COLORS[participant.team_index])
	## 見 _current_name_font_size 宣告處的說明——用「上一幀縮完的字體大小」
	## 量真正的行高 + 固定 3px,不管對手人數/哪組 Slot 的 NameLabel 框高設多少,
	## 都保證名字下緣到棋盤上緣一定剛好 3px,不會被蓋住。
	var label_height := _name_label.get_theme_font("font").get_height(_current_name_font_size) + NAME_TO_BOARD_GAP_PX if _name_label else FALLBACK_LABEL_HEIGHT
	var bar_width := TetrisBoardRenderer.effective_size(_garbage_bar_anchor).x if _garbage_bar_anchor else FALLBACK_BAR_WIDTH

	var origin := Vector2(bar_width, label_height)
	var available := Vector2(maxf(size.x - bar_width, 1.0), maxf(size.y - label_height, 1.0))
	var cell_size := maxf(minf(available.x / TetrisBoard.WIDTH, available.y / TetrisBoard.VISIBLE_HEIGHT), 2.0)
	var board_size := Vector2(TetrisBoard.WIDTH * cell_size, TetrisBoard.VISIBLE_HEIGHT * cell_size)

	## 2026-09-25 使用者回報名字沒有置中在「盤面+垃圾長條」中間——因為
	## NameLabel 原本的寬度是跟著它自己的 anchor 撐滿整個 PanelContent
	## 寬度,但棋盤實際畫出來的寬度常常比 PanelContent 窄（高度優先撐滿時,
	## 寬度會letterbox留白在右側),名字用 HORIZONTAL_ALIGNMENT_CENTER 置中
	## 的對象是「NameLabel 自己的寬度」,不是「棋盤實際占用的寬度」,兩個對
	## 不起來就會看起來偏移。改成每一幀直接把 NameLabel 的水平範圍蓋成
	## 「垃圾長條+棋盤實際寬度」（bar_width + board_size.x),這樣它內部的
	## CENTER 對齊就一定準——垂直位置/字體大小還是使用者自己在編輯器調的,
	## 這裡不動。
	if _name_label:
		## 2026-09-26 真正抓到的 bug：先設 size.x 再量寬度不會準——Label 沒開
		## clip_text 時,get_minimum_size() 會用「目前字體大小」量出完整文字
		## 需要的寬度,Godot 的 Control 會把 size 硬拉回不小於這個最小值,等於
		## 我這裡想縮小的 size.x 馬上被蓋回去（實測 available_width 量出來
		## 跟 natural_width 一模一樣,就是被蓋回去的鐵證）。改成先用「棋盤實際
		## 寬度」（跟 size.x 無關、獨立算出來的 bar_width+board_size.x）決定
		## 字體大小,字體真的縮小之後,Label 自己的最小寬度也跟著變小,這時候
		## 再設 size.x 才不會被拉回去。額外開 clip_text 當保險,就算哪天順序
		## 又被改壞,也只會裁字不會整個爆版。
		_name_label.clip_text = true
		var target_width := bar_width + board_size.x
		_current_name_font_size = _fit_name_label_font(target_width)
		_name_label.position.x = 0.0
		_name_label.size.x = target_width

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

## 見上面 MIN_NAME_FONT_SIZE 的說明——用「原始（最大）字體大小」量一次名字
## 實際要多寬,塞不下 available_width（呼叫端傳進來的就是「垃圾長條+棋盤
## 實際寬度」,滿足使用者要求的「名字最寬對齊各自盤面」）就照比例縮小,塞
## 得下就直接用原始大小,不會因為之前縮小過又忘記還原。縮小後的字體大小是
## 直接按比例換算、四捨五入成整數字體大小,字型在不同大小的 hinting/取整
## 不會完全線性,換算完再拿「縮小後的大小」重新量一次實際寬度,超出就再降
## 一級,保證絕對不會超出 available_width（不只是「理論上差不多」）。回傳
## 縮完的字體大小給呼叫端存起來,下一幀量行高用（見 _current_name_font_size
## 宣告處的說明）。
func _fit_name_label_font(available_width: float) -> float:
	var font := _name_label.get_theme_font("font")
	var natural_width := font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _base_name_font_size).x
	var fitted_size := int(_base_name_font_size)
	if natural_width > available_width and natural_width > 0.0:
		fitted_size = int(maxf(floor(_base_name_font_size * available_width / natural_width), MIN_NAME_FONT_SIZE))
		while fitted_size > MIN_NAME_FONT_SIZE and font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_size).x > available_width:
			fitted_size -= 1
	_name_label.add_theme_font_size_override("font_size", fitted_size)
	return fitted_size

func _label_text() -> String:
	var text: String = BattleSettings.AI_LABELS.get(pid, "AI") if BattleSettings.is_ai(pid) else NetworkManager.get_peer_profile_name(pid)
	if participant.is_disconnected:
		text += "（暫停中）"
	elif participant.is_eliminated:
		text += "（已淘汰）"
	return text
