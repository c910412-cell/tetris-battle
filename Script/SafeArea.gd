## 安全區域偵測（autoload）——2026-09-25 新增。使用者想先看「手機瀏海/圓角/
## 手勢列吃掉多少像素、扣掉之後盤面比例還多出多少空間」，再決定怎麼運用多
## 出來的長度（見跟使用者討論長螢幕留白的那一輪對話）。
##
## 2026-09-25 補上真的套用邊距的部分（register_control()）：對戰畫面
## （BattleLayoutPortrait/Landscape.tscn）整份版面是照 1080x1920／1920x1080
## 這個固定基準尺寸、每個節點手排絕對像素位置排出來的，不是「照比例撐滿
## 父層」那種可以直接改尺寸的排法——如果把整份版面拉伸/縮放去塞安全區，
## 裡面每個節點的絕對位置全部會跟著跑掉、等於重排一次。改成只做「整份
## 版面平移」：把整個 PortraitLayout/LandscapeLayout 節點（原本錨點
## 0,0,0,0、固定貼在父層左上角）往右下移動 (left, top) 這麼多像素，不改
## 它的尺寸，裡面每個子節點的相對位置完全不用動,底下棋盤(BoardAnchor)/
## 按鈕都是用 global_position 動態算位置,平移之後自動跟著對,不用額外處理。
## 這只解決「別被瀏海/手勢列擋到」,不解決「長螢幕比例比 1080x1920 還長,
## 扣掉安全區還多出的空間怎麼運用」那個問題（那是另一個還沒決定怎麼做的
## 課題,見跟使用者討論的那輪對話）——多數有瀏海的手機同時也比較長,平移
## 這段距離用的就是那多出來的空間,不會反過來把畫面下緣推出安全區,但极端
## 情況（瀏海很深、螢幕又沒有比較長）目前沒有特別處理,先觀察實機數字。
##
## 做法比照 Godot 社群常見寫法（godot-x/safe-area-x 這個外掛的核心邏輯）：
## DisplayServer.get_display_safe_area() 回傳的是「螢幕座標」的安全矩形，
## 拿目前視窗的位置/大小（DisplayServer.window_get_position()/
## window_get_size()）去扣，算出上下左右各被吃掉多少像素。這個專案的伸縮
## 模式是 canvas_items（見 project.godot），已經查證過在這個模式下
## get_viewport_rect().size 回傳的就是「視窗實際像素大小」本身（不是
## project 設定的 1080x1920 基準值再另外縮放一次)，所以這裡算出來的像素
## 邊距跟 Board.gd 等既有畫面邏辯用的是同一個座標系統，之後真的要套用時
## 可以直接拿來當 Control 的 offset_* 用，不用再換算。
## 桌機（Windows/macOS/Linux）沒有瀏海/手勢列，四個邊距固定是 0。
extends Node

signal safe_area_changed(left: float, top: float, right: float, bottom: float)

## 這次盤面設計基準（見 project.godot 的 viewport_width/height）——用來換算
## 「照這個比例，安全區內多出多少像素」給使用者看，不是拿來真的限制盤面。
const REFERENCE_WIDTH := 1080.0
const REFERENCE_HEIGHT := 1920.0

var left: float = 0.0
var top: float = 0.0
var right: float = 0.0
var bottom: float = 0.0

var _debug_layer: CanvasLayer
var _debug_label: Label
var _registered_controls: Array[Control] = []
var _backdrop_layers: Array[CanvasLayer] = []

func _ready() -> void:
	get_tree().root.size_changed.connect(_refresh)
	PlayerSettings.settings_changed.connect(_on_player_settings_changed)
	_build_debug_overlay()
	call_deferred("_refresh")

func _refresh() -> void:
	var window_size := DisplayServer.window_get_size()
	if OS.get_name() in ["Android", "iOS"]:
		var window_rect := Rect2(DisplayServer.window_get_position(), window_size)
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
	_update_debug_overlay(Vector2(window_size))
	_apply_registered_controls()

func _on_player_settings_changed() -> void:
	_update_debug_visibility()

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

## 2026-09-25 新增：整份版面平移之後，原本被版面蓋住的那塊（上方/左側被推開
## 讓出來的位置）會露出底下的東西，畫面上看起來是灰色，使用者回報看起來像
## 沒排版好，要求「只有 safe area 那一條變黑，不是整個背景變黑」。
## 第一版把黑色 ColorRect 做成滿版鋪整個視窗——結果不只補了空隙，還把整個
## 背景（本來就沒東西畫的地方，不只是這次平移新露出來的部分）都塗黑，範圍
## 遠大於使用者要的。改成只畫 4 條跟除錯疊層一樣大小/位置的色塊（上/下/左/
## 右，剛好等於 top/bottom/left/right 這幾個安全邊距的寬度），其餘地方不動。
## 另外一個踩坑（跟範圍無關,是疊圖順序)：黑色色塊本來塞在 register 節點的
## 父層（例如 BoardLayer）裡面,結果蓋掉棋盤——因為棋盤格子是 Battle.gd 自己
## （Node2D）用 _draw() 畫的、不在任何 CanvasLayer 底下,等於停在「最底層」
## (層級 0);BoardLayer 這個 CanvasLayer 預設 layer=1,比層級 0 高,色塊只要
## 跟 PortraitLayout/LandscapeLayout 擠在同一層,就會蓋在棋盤上面。修法：
## 另外開一個獨立的 CanvasLayer,layer 設成負數（-10),比場景裡任何
## CanvasLayer 跟 Node2D 本身的層級 0 都還低,色塊永遠墊在最底下,只有真的
## 沒人畫到的空隙才會透出黑色。這個新 CanvasLayer 掛在 register 節點的
## 「祖父層」（例如 BoardLayer 的父節點，也就是 Battle.tscn 的根節點）底下,
## 假設是這份專案一貫的 `XxxLayer(CanvasLayer) > PortraitLayout/
## LandscapeLayout` 排法,同一個祖父層只需要一塊,用固定節點名稱擋重複呼叫。
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

## 除錯疊層跟正式黑邊背景都是「4 個色塊各自貼齊上/下/左/右邊、厚度等於
## 對應的安全邊距」，共用同一份定位邏輯，不要維護兩份。傳進來的 rects 順序
## 固定是 [上, 下, 左, 右]（_build_debug_overlay()/_ensure_backdrop() 建立
## 的順序都一樣）。
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

## ---- 除錯顯示：4 條半透明紅色色塊標出被吃掉的範圍 + 文字寫出實際數字 ----

func _build_debug_overlay() -> void:
	_debug_layer = CanvasLayer.new()
	_debug_layer.layer = 100
	add_child(_debug_layer)

	for preset in [
		{"anchors": Vector4(0, 0, 1, 0), "offsets": Vector4(0, 0, 0, 0), "grow_v": Control.GROW_DIRECTION_END},
		{"anchors": Vector4(0, 1, 1, 1), "offsets": Vector4(0, 0, 0, 0), "grow_v": Control.GROW_DIRECTION_BEGIN},
		{"anchors": Vector4(0, 0, 0, 1), "offsets": Vector4(0, 0, 0, 0), "grow_v": Control.GROW_DIRECTION_END},
		{"anchors": Vector4(1, 0, 1, 1), "offsets": Vector4(0, 0, 0, 0), "grow_v": Control.GROW_DIRECTION_BEGIN},
	]:
		var rect := ColorRect.new()
		rect.color = Color(1.0, 0.0, 0.0, 0.35)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_debug_layer.add_child(rect)

	_debug_label = Label.new()
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_debug_label.add_theme_font_size_override("font_size", 22)
	_debug_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	_debug_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_debug_layer.add_child(_debug_label)

	_update_debug_visibility()

func _update_debug_visibility() -> void:
	_debug_layer.visible = PlayerSettings.show_safe_area_debug

func _update_debug_overlay(window_size: Vector2) -> void:
	var rects := []
	for child in _debug_layer.get_children():
		if child is ColorRect:
			rects.append(child)
	_position_edge_strips(rects)

	var safe_w := window_size.x - left - right
	var safe_h := window_size.y - top - bottom
	var is_portrait := window_size.y >= window_size.x
	var extra_text := ""
	if is_portrait and safe_w > 0:
		var expected_h := safe_w * (REFERENCE_HEIGHT / REFERENCE_WIDTH)
		extra_text = "照 9:16 基準比例，高度多出 %d px" % int(round(safe_h - expected_h))
	elif not is_portrait and safe_h > 0:
		var expected_w := safe_h * (REFERENCE_HEIGHT / REFERENCE_WIDTH)
		extra_text = "照 9:16 基準比例，寬度多出 %d px" % int(round(safe_w - expected_w))

	_debug_label.offset_top = top + 8.0
	_debug_label.text = "視窗 %d x %d ｜ 安全邊距　上%d 下%d 左%d 右%d\n安全區可用 %d x %d ｜ %s" % [
		int(window_size.x), int(window_size.y), int(top), int(bottom), int(left), int(right),
		int(safe_w), int(safe_h), extra_text,
	]
