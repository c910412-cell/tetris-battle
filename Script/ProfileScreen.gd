## 個人資料畫面（頭貼/名稱，之後可能加成就）——2026-09-24 新增。從
## Lobby.tscn 左上角的頭貼方塊疊加開啟（跟 Settings.tscn 同一套
## instantiate/add_child/tree_exited 慣例），關閉時 queue_free() 自己就好。
## 資料本身讀/寫都是 PlayerProfile（autoload），這裡只負責畫面。頭貼先用
## PlayerProfile.AVATAR_COUNT 張預設畫廊縮圖，不是從手機相簿選真正的照片
## （使用者確認過，那個需要另外接原生檔案存取權限，這次先不做）。
extends Control

@onready var portrait_layout: Control = $PortraitLayout
@onready var landscape_layout: Control = $LandscapeLayout
@onready var avatar_preview_portrait: TextureRect = $PortraitLayout/AvatarPreview
@onready var avatar_preview_landscape: TextureRect = $LandscapeLayout/AvatarPreview
@onready var name_edit_portrait: LineEdit = $PortraitLayout/NameEdit
@onready var name_edit_landscape: LineEdit = $LandscapeLayout/NameEdit
@onready var avatar_grid_portrait: GridContainer = $PortraitLayout/AvatarGrid
@onready var avatar_grid_landscape: GridContainer = $LandscapeLayout/AvatarGrid
@onready var close_button_portrait: Button = $PortraitLayout/CloseButton
@onready var close_button_landscape: Button = $LandscapeLayout/CloseButton

var _avatar_buttons_portrait: Array = []
var _avatar_buttons_landscape: Array = []
var _touch_helper_active: bool = false

func _ready() -> void:
	name_edit_portrait.text = PlayerProfile.player_name
	name_edit_landscape.text = PlayerProfile.player_name

	avatar_grid_portrait.columns = 3
	avatar_grid_landscape.columns = 3
	_avatar_buttons_portrait = _build_avatar_grid(avatar_grid_portrait)
	_avatar_buttons_landscape = _build_avatar_grid(avatar_grid_landscape)
	_refresh_avatar_selection()

	name_edit_portrait.text_submitted.connect(_on_name_submitted)
	name_edit_landscape.text_submitted.connect(_on_name_submitted)
	name_edit_portrait.focus_exited.connect(_on_name_focus_exited.bind(name_edit_portrait))
	name_edit_landscape.focus_exited.connect(_on_name_focus_exited.bind(name_edit_landscape))
	close_button_portrait.pressed.connect(_on_close_pressed)
	close_button_landscape.pressed.connect(_on_close_pressed)

	## 這個畫面有 LineEdit（名稱輸入），跟 RoomBattleSettings.gd 同一套「短暫
	## 開回觸控模擬滑鼠」做法（見 MobileLineEditHelper.gd 開頭的說明）。
	MobileLineEditHelper.enable_touch_as_mouse()
	_touch_helper_active = true
	MobileLineEditHelper.setup(name_edit_portrait)
	MobileLineEditHelper.setup(name_edit_landscape)
	MobileLineEditHelper.enable_defocus_on_background_tap($Background)

	get_viewport().size_changed.connect(_apply_orientation_layout)
	_apply_orientation_layout()

func _exit_tree() -> void:
	if _touch_helper_active:
		MobileLineEditHelper.restore_touch_emulation()

func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	portrait_layout.visible = is_portrait
	landscape_layout.visible = not is_portrait

## 頭貼畫廊固定就是 PlayerProfile.AVATAR_COUNT 張,不用像 TeamSelect.gd 那樣
## 處理拖放/動態人數,單純生成一排可以點的縮圖按鈕。
func _build_avatar_grid(grid: GridContainer) -> Array:
	var buttons: Array = []
	for i in range(PlayerProfile.AVATAR_COUNT):
		var button := TextureButton.new()
		button.texture_normal = PlayerProfile.get_avatar_texture_for(i)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = Vector2(140, 140)
		button.pressed.connect(_on_avatar_picked.bind(i))
		grid.add_child(button)
		buttons.append(button)
	return buttons

func _on_avatar_picked(id: int) -> void:
	PlayerProfile.set_avatar_id(id)
	_refresh_avatar_selection()

## 選中的那張稍微放大+不透明,其他張半透明——不用額外的外框素材就能表達
## 「目前選中哪一張」。
func _refresh_avatar_selection() -> void:
	var texture := PlayerProfile.get_avatar_texture()
	avatar_preview_portrait.texture = texture
	avatar_preview_landscape.texture = texture
	for i in range(_avatar_buttons_portrait.size()):
		var is_selected := i == PlayerProfile.avatar_id
		var scale_value := 1.0 if is_selected else 0.85
		_avatar_buttons_portrait[i].modulate = Color(1, 1, 1, 1) if is_selected else Color(1, 1, 1, 0.5)
		_avatar_buttons_portrait[i].pivot_offset = _avatar_buttons_portrait[i].size / 2.0
		_avatar_buttons_portrait[i].scale = Vector2(scale_value, scale_value)
		_avatar_buttons_landscape[i].modulate = Color(1, 1, 1, 1) if is_selected else Color(1, 1, 1, 0.5)
		_avatar_buttons_landscape[i].pivot_offset = _avatar_buttons_landscape[i].size / 2.0
		_avatar_buttons_landscape[i].scale = Vector2(scale_value, scale_value)

func _on_name_submitted(new_text: String) -> void:
	PlayerProfile.set_player_name(new_text)
	name_edit_portrait.text = PlayerProfile.player_name
	name_edit_landscape.text = PlayerProfile.player_name

func _on_name_focus_exited(edit: LineEdit) -> void:
	PlayerProfile.set_player_name(edit.text)
	name_edit_portrait.text = PlayerProfile.player_name
	name_edit_landscape.text = PlayerProfile.player_name

func _on_close_pressed() -> void:
	queue_free()
