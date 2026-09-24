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
## 2026-09-24 新增：左右移動/軟降的速度細項，見 PlayerSettings.move_repeat_sec/
## soft_drop_interval_sec 的說明。
@onready var move_speed_spin_portrait: SpinBox = $PortraitLayout/MoveSpeedRow/MoveSpeedSpin
@onready var move_speed_spin_landscape: SpinBox = $LandscapeLayout/MoveSpeedRow/MoveSpeedSpin
@onready var soft_drop_speed_spin_portrait: SpinBox = $PortraitLayout/SoftDropSpeedRow/SoftDropSpeedSpin
@onready var soft_drop_speed_spin_landscape: SpinBox = $LandscapeLayout/SoftDropSpeedRow/SoftDropSpeedSpin
@onready var close_button_portrait: Button = $PortraitLayout/CloseButton
@onready var close_button_landscape: Button = $LandscapeLayout/CloseButton

func _ready() -> void:
	vibration_toggle_portrait.button_pressed = PlayerSettings.vibration_enabled
	vibration_toggle_landscape.button_pressed = PlayerSettings.vibration_enabled
	gesture_toggle_portrait.button_pressed = PlayerSettings.gesture_controls_enabled
	gesture_toggle_landscape.button_pressed = PlayerSettings.gesture_controls_enabled
	move_speed_spin_portrait.value = PlayerSettings.move_repeat_sec
	move_speed_spin_landscape.value = PlayerSettings.move_repeat_sec
	soft_drop_speed_spin_portrait.value = PlayerSettings.soft_drop_interval_sec
	soft_drop_speed_spin_landscape.value = PlayerSettings.soft_drop_interval_sec

	vibration_toggle_portrait.toggled.connect(_on_vibration_toggled)
	vibration_toggle_landscape.toggled.connect(_on_vibration_toggled)
	gesture_toggle_portrait.toggled.connect(_on_gesture_toggled)
	gesture_toggle_landscape.toggled.connect(_on_gesture_toggled)
	move_speed_spin_portrait.value_changed.connect(_on_move_speed_changed)
	move_speed_spin_landscape.value_changed.connect(_on_move_speed_changed)
	soft_drop_speed_spin_portrait.value_changed.connect(_on_soft_drop_speed_changed)
	soft_drop_speed_spin_landscape.value_changed.connect(_on_soft_drop_speed_changed)
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

func _on_move_speed_changed(value: float) -> void:
	PlayerSettings.set_move_repeat_sec(value)
	move_speed_spin_portrait.value = value
	move_speed_spin_landscape.value = value

func _on_soft_drop_speed_changed(value: float) -> void:
	PlayerSettings.set_soft_drop_interval_sec(value)
	soft_drop_speed_spin_portrait.value = value
	soft_drop_speed_spin_landscape.value = value

func _on_close_pressed() -> void:
	queue_free()
