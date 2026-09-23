## 玩家個人裝置設定（震動回饋/手勢操作）——2026-09-22 新增。跟 BattleSettings
## （每場對戰共用、不落地存檔的房間規則）是分開的兩件事：這裡放的是「這台
## 裝置上、這個人」的長期偏好，存在 user:// 底下，重開 App 也要記得，從
## Lobby.tscn 右上角的設定按鈕進入 Settings.tscn 調整。
extends Node

signal settings_changed

const SAVE_PATH := "user://player_settings.cfg"

## 震動回饋（消行/被攻擊疊垃圾行/淘汰時）——手機端才有意義，桌機上
## vibrate() 直接安靜跳過。
var vibration_enabled: bool = true
## 手勢操作：開啟後 Board.tscn／Battle.tscn 右側的左右旋轉/直接到底三顆
## 按鈕會消失，改成螢幕右半邊滑動偵測（左滑=左旋轉/右滑=右旋轉/下滑=直接
## 到底），見 TetrisGestureZone.gd。
var gesture_controls_enabled: bool = false

func _ready() -> void:
	_load()

func set_vibration_enabled(enabled: bool) -> void:
	vibration_enabled = enabled
	_save()
	settings_changed.emit()

func set_gesture_controls_enabled(enabled: bool) -> void:
	gesture_controls_enabled = enabled
	_save()
	settings_changed.emit()

## 震動回饋的統一入口——關掉開關或在桌機上跑都直接安靜跳過，呼叫端不用自己
## 判斷平台/開關狀態。
func vibrate(duration_msec: int = 40) -> void:
	if not vibration_enabled:
		return
	if not (OS.get_name() in ["Android", "iOS"]):
		return
	Input.vibrate_handheld(duration_msec)

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("settings", "vibration_enabled", vibration_enabled)
	config.set_value("settings", "gesture_controls_enabled", gesture_controls_enabled)
	config.save(SAVE_PATH)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	vibration_enabled = config.get_value("settings", "vibration_enabled", true)
	gesture_controls_enabled = config.get_value("settings", "gesture_controls_enabled", false)
