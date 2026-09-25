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
@onready var sound_toggle_portrait: CheckButton = $PortraitLayout/SoundRow/SoundToggle
@onready var sound_toggle_landscape: CheckButton = $LandscapeLayout/SoundRow/SoundToggle
## 2026-09-25 新增：見 SafeArea.gd 開頭的說明——先讓使用者自己手機上看得到
## 安全區數字，這顆開關讓他們看完可以關掉。
@onready var safe_area_debug_toggle_portrait: CheckButton = $PortraitLayout/SafeAreaDebugRow/SafeAreaDebugToggle
@onready var safe_area_debug_toggle_landscape: CheckButton = $LandscapeLayout/SafeAreaDebugRow/SafeAreaDebugToggle
@onready var close_button_portrait: Button = $PortraitLayout/CloseButton
@onready var close_button_landscape: Button = $LandscapeLayout/CloseButton

func _ready() -> void:
	vibration_toggle_portrait.button_pressed = PlayerSettings.vibration_enabled
	vibration_toggle_landscape.button_pressed = PlayerSettings.vibration_enabled
	gesture_toggle_portrait.button_pressed = PlayerSettings.gesture_controls_enabled
	gesture_toggle_landscape.button_pressed = PlayerSettings.gesture_controls_enabled
	sound_toggle_portrait.button_pressed = PlayerSettings.sound_effects_enabled
	sound_toggle_landscape.button_pressed = PlayerSettings.sound_effects_enabled
	safe_area_debug_toggle_portrait.button_pressed = PlayerSettings.show_safe_area_debug
	safe_area_debug_toggle_landscape.button_pressed = PlayerSettings.show_safe_area_debug
	move_speed_spin_portrait.value = PlayerSettings.move_repeat_sec
	move_speed_spin_landscape.value = PlayerSettings.move_repeat_sec
	soft_drop_speed_spin_portrait.value = PlayerSettings.soft_drop_interval_sec
	soft_drop_speed_spin_landscape.value = PlayerSettings.soft_drop_interval_sec

	# 2026-09-24：這幾個開關本身是 CheckButton（繼承 BaseButton），跟選單按鈕
	# 共用同一套 connect_button()（接的也是 button_down，按下就有聲音，不用
	# 等切換完成），開關「這個設定值本身有沒有開」的邏輯不受影響。
	for toggle in [vibration_toggle_portrait, vibration_toggle_landscape,
			gesture_toggle_portrait, gesture_toggle_landscape,
			sound_toggle_portrait, sound_toggle_landscape,
			safe_area_debug_toggle_portrait, safe_area_debug_toggle_landscape]:
		SoundEffects.connect_button(toggle)
	vibration_toggle_portrait.toggled.connect(_on_vibration_toggled)
	vibration_toggle_landscape.toggled.connect(_on_vibration_toggled)
	gesture_toggle_portrait.toggled.connect(_on_gesture_toggled)
	gesture_toggle_landscape.toggled.connect(_on_gesture_toggled)
	sound_toggle_portrait.toggled.connect(_on_sound_toggled)
	sound_toggle_landscape.toggled.connect(_on_sound_toggled)
	safe_area_debug_toggle_portrait.toggled.connect(_on_safe_area_debug_toggled)
	safe_area_debug_toggle_landscape.toggled.connect(_on_safe_area_debug_toggled)
	move_speed_spin_portrait.value_changed.connect(_on_move_speed_changed)
	move_speed_spin_landscape.value_changed.connect(_on_move_speed_changed)
	soft_drop_speed_spin_portrait.value_changed.connect(_on_soft_drop_speed_changed)
	soft_drop_speed_spin_landscape.value_changed.connect(_on_soft_drop_speed_changed)
	SoundEffects.connect_button(close_button_portrait)
	SoundEffects.connect_button(close_button_landscape)
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

func _on_sound_toggled(pressed: bool) -> void:
	PlayerSettings.set_sound_effects_enabled(pressed)
	sound_toggle_portrait.button_pressed = pressed
	sound_toggle_landscape.button_pressed = pressed

func _on_safe_area_debug_toggled(pressed: bool) -> void:
	PlayerSettings.set_show_safe_area_debug(pressed)
	safe_area_debug_toggle_portrait.button_pressed = pressed
	safe_area_debug_toggle_landscape.button_pressed = pressed

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
