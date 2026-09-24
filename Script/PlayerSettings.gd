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
## 2026-09-24 新增：音效總開關（見 SoundEffects.gd）——跟震動回饋同一套
## 「關掉就整個安靜跳過」模式。
var sound_effects_enabled: bool = true

## 2026-09-24 新增：左右移動「按住不放」的連續移動節奏——按鈕
## （TetrisTouchButton.gd 觸發 tetris_move_left/right）跟手勢
## （TetrisGestureMoveZone.gd 是送同一個 input action，見該檔案開頭的說明）
## 共用同一份設定，數字是每一格之間的間隔秒數，越小移動越快。原本是
## Board.gd/Battle.gd 各自寫死的常數（曾經不一致，Board.gd 還停在舊的
## 0.05），現在統一放這裡、可以在設定畫面調。
var move_repeat_sec: float = 0.03
## 軟降（按住「↓」）的下落間隔秒數，越小下降越快——原本是
## TetrisGameController.SOFT_DROP_GRAVITY_SEC 寫死的常數，現在改成這裡的
## 設定值，由 Board.gd/Battle.gd 在建立本地玩家的 controller 之後指派進去
## （TetrisGameController 本身故意不直接讀 PlayerSettings，保持純邏輯、
## 可以離線單獨測試，見該檔案開頭的說明）。
var soft_drop_interval_sec: float = 0.08

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

func set_sound_effects_enabled(enabled: bool) -> void:
	sound_effects_enabled = enabled
	_save()
	settings_changed.emit()

func set_move_repeat_sec(value: float) -> void:
	move_repeat_sec = value
	_save()
	settings_changed.emit()

func set_soft_drop_interval_sec(value: float) -> void:
	soft_drop_interval_sec = value
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
	config.set_value("settings", "sound_effects_enabled", sound_effects_enabled)
	config.set_value("settings", "move_repeat_sec", move_repeat_sec)
	config.set_value("settings", "soft_drop_interval_sec", soft_drop_interval_sec)
	config.save(SAVE_PATH)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	vibration_enabled = config.get_value("settings", "vibration_enabled", true)
	gesture_controls_enabled = config.get_value("settings", "gesture_controls_enabled", false)
	sound_effects_enabled = config.get_value("settings", "sound_effects_enabled", true)
	move_repeat_sec = config.get_value("settings", "move_repeat_sec", 0.03)
	soft_drop_interval_sec = config.get_value("settings", "soft_drop_interval_sec", 0.08)
