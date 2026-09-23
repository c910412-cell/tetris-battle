## PlayerSettings.gesture_controls_enabled 開啟時取代右側的左右旋轉/直接到底
## 三顆按鈕——覆蓋螢幕右半邊，放開時比對這次觸控的位移方向/大小：
##   - 位移超過 SWIPE_MIN_DISTANCE 視為滑動：左滑=左旋轉/右滑=右旋轉/
##     下滑=直接到底，一次滑動只觸發一次對應動作（不是持續拖曳跟隨）。
##   - 位移很小視為點擊：兩次點擊間隔夠短（DOUBLE_TAP_INTERVAL 內）、位置
##     夠接近（DOUBLE_TAP_DISTANCE 內）才判定為雙擊，觸發 Hold；單獨一次
##     點擊不做任何事（避免手滑誤觸）。
## Hold/Pause 兩顆按鈕維持原本按鈕形式不受影響，因為這兩顆按鈕在場景樹裡排
## 在這個節點之後（更晚加入＝輸入判定優先權更高），會先攔截自己範圍內的
## 觸控，不會被這裡蓋掉。
extends Control

const SWIPE_MIN_DISTANCE := 60.0
const DOUBLE_TAP_INTERVAL := 0.35
const DOUBLE_TAP_DISTANCE := 80.0

var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _last_tap_time: float = -10.0
var _last_tap_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_press_release(event.pressed, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_press_release(event.pressed, event.position)

func _handle_press_release(pressed: bool, pos: Vector2) -> void:
	if pressed:
		_drag_start = pos
		_dragging = true
	elif _dragging:
		_dragging = false
		_resolve_release(pos)

func _resolve_release(pos: Vector2) -> void:
	var delta := pos - _drag_start
	if delta.length() >= SWIPE_MIN_DISTANCE:
		_resolve_swipe(delta)
		_last_tap_time = -10.0 # 滑動不算點擊，中斷雙擊計時，避免「滑一下+點一下」誤判成雙擊。
		return
	_resolve_tap(pos)

func _resolve_swipe(delta: Vector2) -> void:
	if absf(delta.x) >= absf(delta.y):
		_trigger("tetris_rotate_ccw" if delta.x < 0 else "tetris_rotate_cw")
	elif delta.y > 0:
		_trigger("tetris_hard_drop")

func _resolve_tap(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_tap_time <= DOUBLE_TAP_INTERVAL and pos.distance_to(_last_tap_pos) <= DOUBLE_TAP_DISTANCE:
		_trigger("tetris_hold")
		_last_tap_time = -10.0
	else:
		_last_tap_time = now
		_last_tap_pos = pos

## rotate/hard_drop/hold 在 Board.gd／Battle.gd 都是用 is_action_just_pressed
## 輪詢的一次性動作（不像移動要持續按住），跟 TetrisTouchButton 的
## action_press/action_release 走同一條已驗證會動的路徑，這裡同框內按下又
## 放開一樣有效。
func _trigger(action: String) -> void:
	Input.action_press(action)
	Input.action_release(action)
