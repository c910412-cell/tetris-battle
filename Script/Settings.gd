## 設定畫面（震動回饋/手勢操作）——2026-09-22 新增。從 Lobby.tscn 右上角的
## 齒輪按鈕疊加開啟（跟 MultiplayerLobby 同一套 instantiate/add_child/
## tree_exited 慣例），關閉時 queue_free() 自己就好，底下的 Lobby.tscn 本來
## 就還活著，不像 MultiplayerLobby 有「被當成 current_scene 整個換上來」的
## 特殊情境。設定值本身讀/寫都是 PlayerSettings（autoload），這裡只負責畫面。
extends Control

@onready var portrait_layout: Control = $PortraitLayout
@onready var landscape_layout: Control = $LandscapeLayout
@onready var vibration_toggle_portrait: CheckButton = $PortraitLayout/VibrationRow/VibrationToggle
@onready var vibration_toggle_landscape: CheckButton = $LandscapeLayout/VibrationRow/VibrationToggle
@onready var gesture_toggle_portrait: CheckButton = $PortraitLayout/GestureRow/GestureToggle
@onready var gesture_toggle_landscape: CheckButton = $LandscapeLayout/GestureRow/GestureToggle
@onready var close_button_portrait: Button = $PortraitLayout/CloseButton
@onready var close_button_landscape: Button = $LandscapeLayout/CloseButton

func _ready() -> void:
	vibration_toggle_portrait.button_pressed = PlayerSettings.vibration_enabled
	vibration_toggle_landscape.button_pressed = PlayerSettings.vibration_enabled
	gesture_toggle_portrait.button_pressed = PlayerSettings.gesture_controls_enabled
	gesture_toggle_landscape.button_pressed = PlayerSettings.gesture_controls_enabled

	vibration_toggle_portrait.toggled.connect(_on_vibration_toggled)
	vibration_toggle_landscape.toggled.connect(_on_vibration_toggled)
	gesture_toggle_portrait.toggled.connect(_on_gesture_toggled)
	gesture_toggle_landscape.toggled.connect(_on_gesture_toggled)
	close_button_portrait.pressed.connect(_on_close_pressed)
	close_button_landscape.pressed.connect(_on_close_pressed)

	get_viewport().size_changed.connect(_apply_orientation_layout)
	_apply_orientation_layout()

func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	portrait_layout.visible = is_portrait
	landscape_layout.visible = not is_portrait

func _on_vibration_toggled(pressed: bool) -> void:
	PlayerSettings.set_vibration_enabled(pressed)
	vibration_toggle_portrait.button_pressed = pressed
	vibration_toggle_landscape.button_pressed = pressed

func _on_gesture_toggled(pressed: bool) -> void:
	PlayerSettings.set_gesture_controls_enabled(pressed)
	gesture_toggle_portrait.button_pressed = pressed
	gesture_toggle_landscape.button_pressed = pressed

func _on_close_pressed() -> void:
	queue_free()
