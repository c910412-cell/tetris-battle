## PlayerSettings.gesture_controls_enabled 開啟時取代左側的左右移動/軟降三顆
## 按鈕——螢幕左半邊變成方向手勢區：滑動方向決定動作（左滑=左移一格/右滑=
## 右移一格/下滑=軟降），一旦滑動超過門檻就送出 action_press 且**不馬上放開**
## ——手指持續按著不放，Board.gd／Battle.gd 既有的 DAS/ARR（水平移動）跟軟降
## 輪詢邏輯就會接手「按著加速」，跟按鈕的按下/放開語意完全對應，不用在這裡
## 重新實作一次移動節奏。放開手指才 action_release。方向一旦判定就鎖定到
## 放開為止（滑動途中改變方向不會重新判定），跟右側 TetrisGestureZone（一次
## 性滑動+雙擊）是不同的手勢模型，故意拆成兩個腳本。
extends Control

const COMMIT_DISTANCE := 40.0

var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _active_action: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_press_release(event.pressed, event.position)
	elif event is InputEventScreenDrag:
		_handle_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_press_release(event.pressed, event.position)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_handle_drag(event.position)

func _handle_press_release(pressed: bool, pos: Vector2) -> void:
	if pressed:
		_drag_start = pos
		_dragging = true
		_active_action = ""
	elif _dragging:
		_dragging = false
		if _active_action != "":
			Input.action_release(_active_action)
		_active_action = ""

func _handle_drag(pos: Vector2) -> void:
	if not _dragging or _active_action != "":
		return
	var delta := pos - _drag_start
	if delta.length() < COMMIT_DISTANCE:
		return
	var action := ""
	if absf(delta.x) >= absf(delta.y):
		action = "tetris_move_left" if delta.x < 0 else "tetris_move_right"
	elif delta.y > 0:
		action = "tetris_soft_drop"
	if action == "":
		return
	_active_action = action
	Input.action_press(action)
