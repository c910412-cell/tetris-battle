## 安全區域偵測（autoload）——2026-09-25 新增。一開始先做「偵測 + 螢幕上顯示
## 數字」讓使用者自己手機上看得到瀏海/手勢列吃掉多少像素，決定好要不要真的
## 套用之後，除錯用的數字疊層（橘色文字＋半透明色塊）已經按要求移除，這裡
## 只保留真正會用到的「偵測 + 套用邊距」部分。
##
## 套用邊距的做法（register_control()）：對戰畫面（BattleLayoutPortrait/
## Landscape.tscn）整份版面是照 1080x1920／1920x1080 這個固定基準尺寸、每個
## 節點手排絕對像素位置排出來的，不是「照比例撐滿父層」那種可以直接改尺寸
## 的排法——如果把整份版面拉伸/縮放去塞安全區，裡面每個節點的絕對位置全部
## 會跟著跑掉、等於重排一次。改成只做「整份版面平移」：把整個 PortraitLayout/
## LandscapeLayout 節點（原本錨點 0,0,0,0、固定貼在父層左上角）往右下移動
## (left, top) 這麼多像素，不改它的尺寸，裡面每個子節點的相對位置完全不用
## 動,底下棋盤(BoardAnchor)/按鈕都是用 global_position 動態算位置,平移之後
## 自動跟著對,不用額外處理。這只解決「別被瀏海/手勢列擋到」,不解決「長螢幕
## 比例比 1080x1920 還長,扣掉安全區還多出的空間怎麼運用」那個問題（那是另一
## 個還沒決定怎麼做的課題,見跟使用者討論的那輪對話）。
##
## 平移之後原本被版面佔住、現在讓出來的空隙（上方/左側）會露出底下的東西
## （引擎清除色，畫面上是灰色）——用 4 條黑色色塊補住,厚度剛好等於對應的
## 安全邊距,只蓋這幾條,不動其餘背景（使用者要求過，不要滿版塗黑）。色塊
## 塞在獨立、layer=-10 的 CanvasLayer 裡（比場景裡任何 CanvasLayer/棋盤本身
## 的 Node2D _draw() 都低),永遠墊在最下面,細節見 _ensure_backdrop() 的說明。
##
## 偵測做法比照 Godot 社群常見寫法（godot-x/safe-area-x 這個外掛的核心邏輯）：
## DisplayServer.get_display_safe_area() 回傳的是「螢幕座標」的安全矩形，
## 拿目前視窗的位置/大小（DisplayServer.window_get_position()/
## window_get_size()）去扣，算出上下左右各被吃掉多少像素。這個專案的伸縮
## 模式是 canvas_items（見 project.godot），已經查證過在這個模式下
## get_viewport_rect().size 回傳的就是「視窗實際像素大小」本身（不是
## project 設定的 1080x1920 基準值再另外縮放一次)，所以這裡算出來的像素
## 邊距跟 Board.gd 等既有畫面邏輯用的是同一個座標系統，可以直接拿來當
## Control 的 offset_* 用，不用再換算。桌機（Windows/macOS/Linux）沒有
## 瀏海/手勢列，四個邊距固定是 0。
extends Node

signal safe_area_changed(left: float, top: float, right: float, bottom: float)

var left: float = 0.0
var top: float = 0.0
var right: float = 0.0
var bottom: float = 0.0

var _registered_controls: Array[Control] = []
var _inset_controls: Array[Control] = []
var _backdrop_layers: Array[CanvasLayer] = []
var _inset_backdrop_roots: Array[Control] = []
## key=被排除的節點,value=它註冊當下的原始 position——見 exempt_from_
## translation() 的說明。
var _exempt_original_positions: Dictionary = {}

func _ready() -> void:
	get_tree().root.size_changed.connect(_refresh)
	call_deferred("_refresh")

func _refresh() -> void:
	if OS.get_name() in ["Android", "iOS"]:
		var window_rect := Rect2(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		var safe_rect := Rect2(DisplayServer.get_display_safe_area())
		left = maxf(0.0, safe_rect.position.x - window_rect.position.x)
		top = maxf(0.0, safe_rect.position.y - window_rect.position.y)
		right = maxf(0.0, window_rect.end.x - safe_rect.end.x)
		bottom = maxf(0.0, window_rect.end.y - safe_rect.end.y)
	else:
		left = 0.0
		top = 0.0
		right = 0.0
		bottom = 0.0
	safe_area_changed.emit(left, top, right, bottom)
	_apply_registered_controls()
	_apply_inset_controls()
	_apply_exempt_controls()

## 呼叫端（例如 Battle.gd）在 _ready() 把自己版面的最外層節點（例如
## portrait_layout/landscape_layout）丟進來註冊一次就好，這裡會立刻套用
## 目前的邊距，之後視窗大小/安全區變了（轉向、換裝置）也會自動重新套用，
## 呼叫端不用自己接 safe_area_changed。節點被 queue_free() 之後會在下一次
## 重算時自動從清單裡濾掉，不用手動取消註冊。
func register_control(control: Control) -> void:
	_ensure_backdrop(control)
	if control not in _registered_controls:
		_registered_controls.append(control)
	_position_control(control)

## 黑色色塊本來塞在 register 節點的父層（例如 BoardLayer）裡面,結果蓋掉
## 棋盤——因為棋盤格子是 Battle.gd 自己（Node2D）用 _draw() 畫的、不在任何
## CanvasLayer 底下,等於停在「最底層」(層級 0);BoardLayer 這個 CanvasLayer
## 預設 layer=1,比層級 0 高,色塊只要跟 PortraitLayout/LandscapeLayout 擠在
## 同一層,就會蓋在棋盤上面。修法：另外開一個獨立的 CanvasLayer,layer 設成
## 負數（-10),比場景裡任何 CanvasLayer 跟 Node2D 本身的層級 0 都還低,色塊
## 永遠墊在最下面,只有真的沒人畫到的空隙才會透出黑色。這個新 CanvasLayer
## 掛在 register 節點的「祖父層」（例如 BoardLayer 的父節點，也就是
## Battle.tscn 的根節點）底下,假設是這份專案一貫的 `XxxLayer(CanvasLayer) >
## PortraitLayout/LandscapeLayout` 排法,同一個祖父層只需要一塊,用固定節點
## 名稱擋重複呼叫。
const _BACKDROP_NAME := "__SafeAreaBackdrop"

func _ensure_backdrop(control: Control) -> void:
	var parent := control.get_parent()
	if parent == null:
		return
	var host := parent.get_parent()
	if host == null or host.has_node(_BACKDROP_NAME):
		return
	var backdrop_layer := CanvasLayer.new()
	backdrop_layer.name = _BACKDROP_NAME
	backdrop_layer.layer = -10
	host.add_child(backdrop_layer)
	host.move_child(backdrop_layer, 0)
	for i in range(4):
		var rect := ColorRect.new()
		rect.color = Color.BLACK
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop_layer.add_child(rect)
	_backdrop_layers.append(backdrop_layer)
	_position_edge_strips(backdrop_layer.get_children())

func _apply_registered_controls() -> void:
	_registered_controls = _registered_controls.filter(func(c): return is_instance_valid(c))
	for control in _registered_controls:
		_position_control(control)
	_backdrop_layers = _backdrop_layers.filter(func(l): return is_instance_valid(l))
	for backdrop_layer in _backdrop_layers:
		_position_edge_strips(backdrop_layer.get_children())

## 4 個色塊各自貼齊上/下/左/右邊、厚度等於對應的安全邊距。傳進來的 rects
## 順序固定是 [上, 下, 左, 右]（_ensure_backdrop() 建立的順序）。
func _position_edge_strips(rects: Array) -> void:
	if rects.size() != 4:
		return
	var top_rect: ColorRect = rects[0]
	top_rect.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_rect.offset_bottom = top

	var bottom_rect: ColorRect = rects[1]
	bottom_rect.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_rect.offset_top = -bottom

	var left_rect: ColorRect = rects[2]
	left_rect.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left_rect.offset_right = left

	var right_rect: ColorRect = rects[3]
	right_rect.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right_rect.offset_left = -right

## 只平移、不改尺寸——理由見檔案開頭的說明。假設 control 錨點是 (0,0,0,0)
## （這幾份版面的根節點本來就是這樣，見 BattleLayoutPortrait/Landscape.tscn），
## 這種錨點下 position 直接對應 offset_left/offset_top，設 position 就相當於
## 整塊往右下移動，不影響子節點的相對位置。
func _position_control(control: Control) -> void:
	control.position = Vector2(left, top)

## 2026-09-25 新增：Lobby/Settings/MultiplayerLobby 這些選單畫面的
## PortraitLayout 跟 Battle.tscn 不是同一種排版方式——這些是「錨點撐滿整個
## 父層」（anchor 0,0,1,1），視窗多大它就多大，不是 Battle 那種固定
## 1080x1920、靠 position 整塊平移的做法。實測過：對這種撐滿型節點呼叫
## register_control()（設 .position）幾乎沒有視覺效果——因為錨點右/下都
## 釘死在父層邊緣，只調 position 只會在錨點允許的範圍內牽動左上角一點點，
## 右/下邊緣完全不會跟著內縮。改成直接調整四邊 offset：offset_left=+left、
## offset_top=+top、offset_right=-right、offset_bottom=-bottom，把整個
## 可用矩形往內縮，撐滿型底下的子節點（它們的錨點是相對這個矩形算的）就會
## 自動落在縮小後的安全範圍內，效果上等同於這塊區域本身變小了。
##
## 2026-09-25 修正（第一版）：黑色背景補丁原本想跟 register_control() 共用
## _ensure_backdrop()（祖父層 + layer=-10 CanvasLayer），但那是 Battle/Board
## 專用的考量（棋盤格子是 Node2D._draw() 畫的、不在任何 CanvasLayer 底下，
## 要墊在 BoardLayer 這個 CanvasLayer 之外才不會蓋到棋盤）。
##
## 2026-09-25 修正（第二版，取代第一版）：改成「直接父層」+ 仍然用
## layer=-10 CanvasLayer 那版，實機測試後發現還是沒有正確顯示——這些選單
## 對話框（Settings/RoomBattleSettings/TeamSelect/ProfileScreen/
## MultiplayerLobby/Lobby）每個都自己有一塊滿版不透明的「Background」
## ColorRect（跟 PortraitLayout 同一層的手足節點），而 CanvasLayer 的 layer
## 排序是「跨整個 viewport 的全域排序」，不受巢狀在哪個節點底下影響——
## layer=-10 永遠比這些畫面自己這層（沒特別設 layer、預設值）還低，等於
## 永遠畫在 Background 底下，被完全蓋住，跟擺在祖父層還是父層無關，問題
## 出在「用 CanvasLayer」這個做法本身，對這種有滿版不透明背景的畫面用不上。
## 改成完全不用 CanvasLayer，直接塞 4 個 ColorRect 當普通子節點，用
## host.move_child() 插在 Background 跟 PortraitLayout 中間（一般 Control
## 手足節點是照樹狀順序畫、後面蓋前面，插在這兩者中間就會「蓋在 Background
## 上面、被 PortraitLayout 蓋住」，正是要的效果）。這幾個對話框的節點順序
## 固定是 Background、PortraitLayout、LandscapeLayout（見各自 .tscn），
## control.get_index() 抓到的就是 PortraitLayout 當下的索引，插在那個位置
## 剛好卡在 Background 之後、PortraitLayout 之前。
func register_inset_control(control: Control) -> void:
	_ensure_inset_backdrop(control)
	if control not in _inset_controls:
		_inset_controls.append(control)
	_position_inset_control(control)

func _ensure_inset_backdrop(control: Control) -> void:
	var host := control.get_parent()
	if host == null or host.has_node(_BACKDROP_NAME):
		return
	var backdrop_root := Control.new()
	backdrop_root.name = _BACKDROP_NAME
	backdrop_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(backdrop_root)
	host.move_child(backdrop_root, control.get_index())
	for i in range(4):
		var rect := ColorRect.new()
		rect.color = Color.BLACK
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop_root.add_child(rect)
	_inset_backdrop_roots.append(backdrop_root)
	_position_edge_strips(backdrop_root.get_children())

func _apply_inset_controls() -> void:
	_inset_controls = _inset_controls.filter(func(c): return is_instance_valid(c))
	for control in _inset_controls:
		_position_inset_control(control)
	_inset_backdrop_roots = _inset_backdrop_roots.filter(func(r): return is_instance_valid(r))
	for backdrop_root in _inset_backdrop_roots:
		_position_edge_strips(backdrop_root.get_children())

func _position_inset_control(control: Control) -> void:
	control.offset_left = left
	control.offset_top = top
	control.offset_right = -right
	control.offset_bottom = -bottom

## 2026-09-25 新增：使用者要求操控按鈕（移動/旋轉那些）「拆開」，不要跟著
## 整份版面一起被 safe area 往下推——這些按鈕是 register_control() 那個
## 節點（portrait_layout/landscape_layout）底下的子節點，父層整塊平移
## (left, top) 之後，子節點沒動過自己的 position，全域座標一樣會跟著父層
## 一起偏移。做法：記住這個節點「註冊當下」的 position 當作它的原始設計
## 位置，之後每次父層平移改變時，把它自己的 position 設成
## 「原始位置 - (left, top)」抵銷掉父層的平移，讓它的全域座標維持不變
## （視覺上完全不跟著父層移動）。呼叫端只要在 _ready() 呼叫一次就好，跟
## register_control() 一樣之後轉向/換裝置都會自動重算。
func exempt_from_translation(control: Control) -> void:
	if control not in _exempt_original_positions:
		_exempt_original_positions[control] = control.position
	_position_exempt_control(control)

func _apply_exempt_controls() -> void:
	var stale: Array = []
	for control in _exempt_original_positions:
		if not is_instance_valid(control):
			stale.append(control)
			continue
		_position_exempt_control(control)
	for control in stale:
		_exempt_original_positions.erase(control)

func _position_exempt_control(control: Control) -> void:
	var original: Vector2 = _exempt_original_positions[control]
	control.position = original - Vector2(left, top)
