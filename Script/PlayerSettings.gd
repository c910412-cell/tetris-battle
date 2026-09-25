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

## 2026-09-25 新增：自動轉向開關，預設關閉——關閉時鎖定直向（螢幕不會因為
## 使用者轉動裝置就跟著轉），開啟才恢復手機感應器自由旋轉。這裡管的是
## 「作業系統層級」的螢幕方向（DisplayServer.screen_set_orientation()），
## 跟 Battle.gd/Board.gd 等畫面自己依 viewport 寬高比切換 Portrait/
## Landscape 版面（_apply_orientation_layout()）是兩件不同的事——後者只要
## 螢幕真的變成橫的/直的都還是會切換版面，這個開關只決定「螢幕會不會因為
## 裝置轉動而變成橫的/直的」。
var auto_rotate_enabled: bool = false

func _ready() -> void:
	_load()
	_apply_auto_rotate()

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

func set_auto_rotate_enabled(enabled: bool) -> void:
	auto_rotate_enabled = enabled
	_save()
	_apply_auto_rotate()
	settings_changed.emit()

## 桌機沒有「轉動裝置」這回事，DisplayServer.screen_set_orientation() 在
## 桌機上是安靜的 no-op，但還是照平台判斷一次，跟 vibrate() 同一個習慣，
## 不要假設呼叫端會自己判斷平台。關閉時鎖定直向（SCREEN_ORIENTATION_
## PORTRAIT）——這個專案的基準版面就是直向設計（project.godot 的
## viewport_width/height 是 1080x1920），鎖定時選它當固定方向；開啟則還原
## 成 project.godot 原本設定的 SENSOR（跟著裝置感應器自由轉，四個方向都
## 可以)。
func _apply_auto_rotate() -> void:
	if not (OS.get_name() in ["Android", "iOS"]):
		return
	if auto_rotate_enabled:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	else:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)

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
	config.set_value("settings", "auto_rotate_enabled", auto_rotate_enabled)
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
	auto_rotate_enabled = config.get_value("settings", "auto_rotate_enabled", false)
