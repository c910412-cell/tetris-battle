## 俄羅斯方塊單人練習盤面。持有一個 TetrisGameController 跑遊戲規則，
## 這個腳本只負責：讀輸入（鍵盤+觸控共用同一套 Input action）、每幀 tick
## 邏輯、畫面繪製。版面 2026-09-21 改成場景裡用 Control+anchor 真的排版，
## 而且直向/橫向是兩個完全獨立的場景檔（`Scenes/BoardLayoutPortrait.tscn`／
## `Scenes/BoardLayoutLandscape.tscn`），`Board.tscn` 的 `BoardLayer` 底下
## 用 instance 把兩份都放進來、只顯示其中一份——要調整版面直接開對應那個
## 場景檔編輯（各自的根節點就是設計基準尺寸 1080x1920／1920x1080，還有一個
## 只在編輯器顯示的 `FrameGuide` 框線標出範圍），不用在 Board.tscn 裡改。
## 兩份場景裡都有 `BoardAnchor`（整個 10x20 棋盤要畫在哪個範圍，cell_size 從
## 這個節點的 size 除以 10/20 算出來）/`CellAnchor`（單一格的位置+大小，
## 2026-09-21 起不再拿來算 cell_size，純粹留給之後要放「一格一格」重複背景
## 素材時當參考）/`HoldPanel`+`HoldLabel`/`NextPanel`+`NextLabel`/8 個觸控
## 按鈕（含 2026-09-22 新增的 `PauseButton`，貼圖已經接好，按鈕本身的位置/
## 大小也是各自場景裡的節點決定）。
## 2026-09-22 起，暫停畫面（`PauseLayer`）跟遊戲結束畫面（`GameOverLayer`）
## 也比照棋盤版面的做法拆成直向/橫向各一份可排版場景檔
## （`Scenes/BoardPauseLayoutPortrait.tscn`／`...Landscape.tscn`／
## `Scenes/BoardGameOverLayoutPortrait.tscn`／`...Landscape.tscn`），各自
## instance 進對應 CanvasLayer 底下的 `PortraitLayout`/`LandscapeLayout`，
## 跟著同一個 `_apply_orientation_layout()` 切換——`PauseLayer` 底下另外多一個
## 不分方向、固定滿版的 `Backdrop`（半透明黑底，讓暫停畫面看起來是「懸浮」在
## 遊戲上面，這個不需要排版，兩個方向都一樣滿版）。無盡模式的暫停沒有次數
## 限制/不用連線同步，見 `_on_pause_pressed()`。HUD 文字（分數/消行/等級/
## 最高紀錄）同一天也拆成 `Scenes/BoardHudLayoutPortrait.tscn`／
## `...Landscape.tscn`，不再用 VBoxContainer 自動疊字，每個文字都是獨立
## 節點、使用者自己排位置。
extends Node2D

const DAS_SEC := 0.2
## 2026-09-24：改讀 PlayerSettings.move_repeat_sec（大廳設定畫面可調，跟
## Battle.gd 共用同一份設定），不再是這裡寫死的常數——原本這裡跟 Battle.gd
## 各自寫死一份、還沒同步過（這裡停在舊的 0.05），統一之後不會再有兩邊
## 不一致的問題。

## 「無盡挑戰」模式的最高分紀錄（2026-09-21 補上，見大廳規格）：本機存檔，
## 不是連線排行榜。只有從 Lobby 的「無盡挑戰」入口玩才有意義，但這個場景
## 之後也會被對戰模式借用邏輯，所以存檔/讀檔失敗就靜靜當作 0 分，不擋畫面。
const HIGH_SCORE_SAVE_PATH := "user://endless_high_score.json"

## HUD 文字 2026-09-22 起併回 BoardLayoutPortrait/Landscape.tscn 跟棋盤/按鈕
## 同一個檔案（原本分開放在 BoardHudLayoutPortrait/Landscape.tscn，使用者
## 反應分成兩個檔案不方便一起排版）——所以路徑是 $BoardLayer/... 不是
## $HUD/...，不再有獨立的 HUD CanvasLayer。
@onready var score_label_portrait: Label = $BoardLayer/PortraitLayout/ScoreLabel
@onready var score_label_landscape: Label = $BoardLayer/LandscapeLayout/ScoreLabel
@onready var lines_label_portrait: Label = $BoardLayer/PortraitLayout/LinesLabel
@onready var lines_label_landscape: Label = $BoardLayer/LandscapeLayout/LinesLabel
@onready var level_label_portrait: Label = $BoardLayer/PortraitLayout/LevelLabel
@onready var level_label_landscape: Label = $BoardLayer/LandscapeLayout/LevelLabel
@onready var high_score_label_portrait: Label = $BoardLayer/PortraitLayout/HighScoreLabel
@onready var high_score_label_landscape: Label = $BoardLayer/LandscapeLayout/HighScoreLabel

@onready var portrait_layout: Control = $BoardLayer/PortraitLayout
@onready var landscape_layout: Control = $BoardLayer/LandscapeLayout
## 2026-09-22 起改用 find_child() 在整個 Portrait/LandscapeLayout 子樹裡搜尋
## 名字，不再寫死完整路徑——使用者會在編輯器裡把這些節點拖到 BoardAnchor
## 底下（讓它們「跟著盤面走」），不管巢狀幾層都找得到，不會因為重新掛父
## 節點就 null 掉（見 Battle.gd 同樣的處理，那邊已經因為這個原因斷過兩次）。
@onready var board_anchor_portrait: Control = portrait_layout.find_child("BoardAnchor", true, false) as Control
## 2026-09-25：型別改成 MiniPiecePanel，讓使用者自己調 HOLD/NEXT 縮圖方塊的
## 大小/位置，見該檔案說明。
@onready var hold_panel_portrait: MiniPiecePanel = portrait_layout.find_child("HoldPanel", true, false) as MiniPiecePanel
@onready var next_panel_portrait: MiniPiecePanel = portrait_layout.find_child("NextPanel", true, false) as MiniPiecePanel
@onready var board_anchor_landscape: Control = landscape_layout.find_child("BoardAnchor", true, false) as Control
@onready var hold_panel_landscape: MiniPiecePanel = landscape_layout.find_child("HoldPanel", true, false) as MiniPiecePanel
@onready var next_panel_landscape: MiniPiecePanel = landscape_layout.find_child("NextPanel", true, false) as MiniPiecePanel

## 手勢操作開關（PlayerSettings.gesture_controls_enabled）：開啟時這六顆按鈕
## 隱藏，改用 GestureZone（右側：滑動旋轉/到底＋雙擊 hold）/MoveGestureZone
## （左側：滑動方向決定移動/軟降，按住加速）偵測手勢，見 _apply_gesture_controls()。
@onready var rotate_ccw_button_portrait: Control = $BoardLayer/PortraitLayout/RotateCCWButton
@onready var rotate_cw_button_portrait: Control = $BoardLayer/PortraitLayout/RotateCWButton
@onready var hard_drop_button_portrait: Control = $BoardLayer/PortraitLayout/HardDropButton
@onready var gesture_zone_portrait: Control = $BoardLayer/PortraitLayout/GestureZone
@onready var move_left_button_portrait: Control = $BoardLayer/PortraitLayout/MoveLeftButton
@onready var move_right_button_portrait: Control = $BoardLayer/PortraitLayout/MoveRightButton
@onready var soft_drop_button_portrait: Control = $BoardLayer/PortraitLayout/SoftDropButton
@onready var move_gesture_zone_portrait: Control = $BoardLayer/PortraitLayout/MoveGestureZone
@onready var hold_button_portrait: Control = $BoardLayer/PortraitLayout/HoldButton
@onready var rotate_ccw_button_landscape: Control = $BoardLayer/LandscapeLayout/RotateCCWButton
@onready var rotate_cw_button_landscape: Control = $BoardLayer/LandscapeLayout/RotateCWButton
@onready var hard_drop_button_landscape: Control = $BoardLayer/LandscapeLayout/HardDropButton
@onready var gesture_zone_landscape: Control = $BoardLayer/LandscapeLayout/GestureZone
@onready var move_left_button_landscape: Control = $BoardLayer/LandscapeLayout/MoveLeftButton
@onready var move_right_button_landscape: Control = $BoardLayer/LandscapeLayout/MoveRightButton
@onready var soft_drop_button_landscape: Control = $BoardLayer/LandscapeLayout/SoftDropButton
@onready var move_gesture_zone_landscape: Control = $BoardLayer/LandscapeLayout/MoveGestureZone
@onready var hold_button_landscape: Control = $BoardLayer/LandscapeLayout/HoldButton

@onready var pause_layer: CanvasLayer = $PauseLayer
@onready var pause_layout_portrait: Control = $PauseLayer/PortraitLayout
@onready var pause_layout_landscape: Control = $PauseLayer/LandscapeLayout
@onready var pause_resume_button_portrait: Button = $PauseLayer/PortraitLayout/ResumeButton
@onready var pause_resume_button_landscape: Button = $PauseLayer/LandscapeLayout/ResumeButton
@onready var pause_leave_button_portrait: Button = $PauseLayer/PortraitLayout/LeaveButton
@onready var pause_leave_button_landscape: Button = $PauseLayer/LandscapeLayout/LeaveButton

@onready var game_over_layer: CanvasLayer = $GameOverLayer
@onready var game_over_layout_portrait: Control = $GameOverLayer/PortraitLayout
@onready var game_over_layout_landscape: Control = $GameOverLayer/LandscapeLayout
@onready var return_button_portrait: Button = $GameOverLayer/PortraitLayout/ReturnButton
@onready var return_button_landscape: Button = $GameOverLayer/LandscapeLayout/ReturnButton

## 2026-09-24 新增：暫停鈕旁邊的設定按鈕，跟 Battle.gd 同一份 Settings.tscn，
## 跟大廳齒輪按鈕同一套 instantiate/add_child/tree_exited 慣例。
@onready var board_settings_button_portrait: Button = $BoardLayer/PortraitLayout/BoardSettingsButton
@onready var board_settings_button_landscape: Button = $BoardLayer/LandscapeLayout/BoardSettingsButton
@export var settings_scene: PackedScene = preload("res://Scenes/Settings.tscn")
var _settings_instance: Control = null

var _controller: TetrisGameController

var _move_dir: int = 0
var _das_timer: float = 0.0
var _arr_timer: float = 0.0

## 無盡模式的暫停沒有次數限制、不用連線同步（純本機單人）——按下就停、按
## 繼續就馬上恢復，不用像對戰畫面那樣考慮多人一起暫停/倒數恢復。
var _is_paused: bool = false

## 每幀從目前那組 CellAnchor 的實際 rect 重新算，不快取——Control 的 anchor
## 在 viewport resize/旋轉時是引擎自動重算，這裡只要每次畫圖前讀一次現值即可。
var _cell_size: float = 24.0
var _board_origin: Vector2 = Vector2.ZERO

var _high_score: int = 0
var _is_new_high_score: bool = false

func _ready() -> void:
	_controller = TetrisGameController.new()
	_controller.soft_drop_gravity_sec = PlayerSettings.soft_drop_interval_sec
	_controller.score_changed.connect(_on_score_changed)
	_controller.lines_cleared.connect(_on_lines_cleared)
	_controller.level_changed.connect(_on_level_changed)
	_controller.game_over.connect(_on_game_over)
	_controller.piece_moved.connect(SoundEffects.play_move)

	_high_score = _load_high_score()
	_set_score_text("分數: 0")
	_set_lines_text("消行: 0")
	_set_level_text("等級: 1")
	_set_high_score_text("最高紀錄: %d" % _high_score)
	game_over_layer.visible = false
	SoundEffects.connect_button(return_button_portrait)
	SoundEffects.connect_button(return_button_landscape)
	return_button_portrait.pressed.connect(_on_return_pressed)
	return_button_landscape.pressed.connect(_on_return_pressed)

	pause_layer.visible = false
	SoundEffects.connect_button(pause_resume_button_portrait)
	SoundEffects.connect_button(pause_resume_button_landscape)
	pause_resume_button_portrait.pressed.connect(_on_pause_resume_pressed)
	pause_resume_button_landscape.pressed.connect(_on_pause_resume_pressed)
	SoundEffects.connect_button(pause_leave_button_portrait)
	SoundEffects.connect_button(pause_leave_button_landscape)
	pause_leave_button_portrait.pressed.connect(_on_return_pressed)
	pause_leave_button_landscape.pressed.connect(_on_return_pressed)

	SoundEffects.connect_button(board_settings_button_portrait)
	SoundEffects.connect_button(board_settings_button_landscape)
	board_settings_button_portrait.pressed.connect(_on_board_settings_pressed)
	board_settings_button_landscape.pressed.connect(_on_board_settings_pressed)

	get_viewport().size_changed.connect(_apply_orientation_layout)
	_apply_orientation_layout()
	## 2026-09-25 新增：無盡挑戰的實際遊玩畫面（BoardLayer 底下這份）不用補
	## safe area（使用者要求排除單人/本地對戰的遊玩介面，這裡比照辦理）；
	## 但暫停/結束這兩層覆蓋畫面不是遊玩介面本身,而且跟 Battle.tscn 的
	## PauseLayer/ResultLayer 是同一種「固定 1080x1920 基準尺寸」排版方式,
	## 一樣用 register_control()。
	SafeArea.register_control(pause_layout_portrait)
	SafeArea.register_control(pause_layout_landscape)
	SafeArea.register_control(game_over_layout_portrait)
	SafeArea.register_control(game_over_layout_landscape)

	PlayerSettings.settings_changed.connect(_apply_gesture_controls)
	_apply_gesture_controls()
	PlayerSettings.settings_changed.connect(_apply_soft_drop_setting)

func _on_pause_pressed() -> void:
	if _is_paused or _controller.is_game_over:
		return
	_is_paused = true
	pause_layer.visible = true

func _on_pause_resume_pressed() -> void:
	_is_paused = false
	pause_layer.visible = false

## 旋轉裝置、直向橫向比例翻轉時，切換顯示哪一組 PortraitLayout/
## LandscapeLayout——棋盤/HOLD/NEXT/觸控按鈕的位置全部是那個場景檔裡的節點
## 決定，這裡不用再算。沒翻轉時重複呼叫也沒差，不用自己追蹤上次的方向。
func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	portrait_layout.visible = is_portrait
	landscape_layout.visible = not is_portrait
	pause_layout_portrait.visible = is_portrait
	pause_layout_landscape.visible = not is_portrait
	game_over_layout_portrait.visible = is_portrait
	game_over_layout_landscape.visible = not is_portrait

## PlayerSettings.gesture_controls_enabled 開啟時把左右旋轉/直接到底三顆按鈕
## 藏起來、換成 GestureZone 接手滑動手勢；兩份方向都要切，不是只切目前生效
## 那份（跟其他設定一樣，切換方向時不能有殘留舊狀態）。
func _apply_gesture_controls() -> void:
	var use_gestures := PlayerSettings.gesture_controls_enabled
	for button in [rotate_ccw_button_portrait, rotate_cw_button_portrait, hard_drop_button_portrait,
			move_left_button_portrait, move_right_button_portrait, soft_drop_button_portrait, hold_button_portrait,
			rotate_ccw_button_landscape, rotate_cw_button_landscape, hard_drop_button_landscape,
			move_left_button_landscape, move_right_button_landscape, soft_drop_button_landscape, hold_button_landscape]:
		button.visible = not use_gestures
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE if use_gestures else Control.MOUSE_FILTER_STOP
	for zone in [gesture_zone_portrait, gesture_zone_landscape, move_gesture_zone_portrait, move_gesture_zone_landscape]:
		zone.visible = use_gestures
		zone.mouse_filter = Control.MOUSE_FILTER_STOP if use_gestures else Control.MOUSE_FILTER_IGNORE

func _apply_soft_drop_setting() -> void:
	_controller.soft_drop_gravity_sec = PlayerSettings.soft_drop_interval_sec

## 同樣的 CanvasLayer 包裝理由見 Battle.gd._on_battle_settings_pressed()
## 的說明——Board 也是 Node2D，直接掛在 self 上會被 BoardLayer/PauseLayer/
## GameOverLayer 這些 layer 1 的 CanvasLayer 蓋過去。
func _on_board_settings_pressed() -> void:
	if _settings_instance and is_instance_valid(_settings_instance):
		return
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 5
	add_child(overlay_layer)
	_settings_instance = settings_scene.instantiate()
	overlay_layer.add_child(_settings_instance)
	_settings_instance.tree_exited.connect(_on_board_settings_closed.bind(overlay_layer))

func _on_board_settings_closed(overlay_layer: CanvasLayer) -> void:
	_settings_instance = null
	overlay_layer.queue_free()

func _process(delta: float) -> void:
	## 2026-09-22：暫停鍵改成跟其他 7 個按鈕一樣走 input_action + 輪詢
	## is_action_just_pressed（不再連 Button 的 pressed/button_up 訊號）——
	## 使用者回報連了 button_up 之後手機上按鈕本身有反應（會變色）,但遊戲
	## 邏輯完全沒被觸發,可見問題出在「Button 訊號」這條路徑本身在那台裝置
	## 上不可靠,不是我這邊接錯訊號。改用跟其他按鈕完全相同、已確認會動的
	## 機制,不用再賭訊號會不會發出來。
	if Input.is_action_just_pressed("tetris_pause"):
		_on_pause_pressed()
	if _is_paused:
		return
	if not _controller.is_game_over:
		_handle_input(delta)
		_controller.tick(delta)
	queue_redraw()

func _handle_input(delta: float) -> void:
	var left := Input.is_action_pressed("tetris_move_left")
	var right := Input.is_action_pressed("tetris_move_right")
	var dir := 0
	if left and not right:
		dir = -1
	elif right and not left:
		dir = 1

	if dir != _move_dir:
		_move_dir = dir
		_das_timer = 0.0
		_arr_timer = 0.0
		if dir != 0:
			_controller.move(dir)
	elif dir != 0:
		_das_timer += delta
		if _das_timer >= DAS_SEC:
			_arr_timer += delta
			var arr_sec := maxf(PlayerSettings.move_repeat_sec, 0.01)
			while _arr_timer >= arr_sec:
				_arr_timer -= arr_sec
				_controller.move(dir)

	_controller.set_soft_drop(Input.is_action_pressed("tetris_soft_drop"))

	if Input.is_action_just_pressed("tetris_hard_drop"):
		_controller.hard_drop()
		SoundEffects.play_hard_drop()
	if Input.is_action_just_pressed("tetris_rotate_cw"):
		_controller.rotate(true)
	if Input.is_action_just_pressed("tetris_rotate_ccw"):
		_controller.rotate(false)
	if Input.is_action_just_pressed("tetris_hold"):
		_controller.hold()

func _on_score_changed(new_score: int) -> void:
	_set_score_text("分數: %d" % new_score)
	if new_score > _high_score:
		_high_score = new_score
		_is_new_high_score = true
		_set_high_score_text("最高紀錄: %d（新紀錄！）" % _high_score)
		_save_high_score(_high_score)

func _on_lines_cleared(count: int) -> void:
	_set_lines_text("消行: %d" % _controller.lines_cleared_total)
	if count > 0:
		PlayerSettings.vibrate(30 + count * 20)
		SoundEffects.play_line_clear()

func _on_level_changed(new_level: int) -> void:
	_set_level_text("等級: %d" % new_level)

func _on_game_over() -> void:
	game_over_layer.visible = true
	_set_high_score_text("最高紀錄: %d（新紀錄！）" % _high_score if _is_new_high_score else "最高紀錄: %d" % _high_score)
	PlayerSettings.vibrate(200)

## HUD 文字（分數/消行/等級/最高紀錄）2026-09-22 起也拆成直向/橫向各一份
## 可排版場景檔（`Scenes/BoardHudLayoutPortrait.tscn`／`...Landscape.tscn`），
## 跟其他彈窗同一套做法：直向/橫向兩份都要寫，不是只寫目前生效那份。
func _set_score_text(text: String) -> void:
	score_label_portrait.text = text
	score_label_landscape.text = text

func _set_lines_text(text: String) -> void:
	lines_label_portrait.text = text
	lines_label_landscape.text = text

func _set_level_text(text: String) -> void:
	level_label_portrait.text = text
	level_label_landscape.text = text

func _set_high_score_text(text: String) -> void:
	high_score_label_portrait.text = text
	high_score_label_landscape.text = text

func _load_high_score() -> int:
	if not FileAccess.file_exists(HIGH_SCORE_SAVE_PATH):
		return 0
	var file := FileAccess.open(HIGH_SCORE_SAVE_PATH, FileAccess.READ)
	if file == null:
		return 0
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.has("high_score"):
		return int(parsed["high_score"])
	return 0

func _save_high_score(value: int) -> void:
	var file := FileAccess.open(HIGH_SCORE_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"high_score": value}))

func _on_return_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")

## 目前生效的那組（Portrait 或 Landscape）BoardAnchor/HoldPanel/NextPanel——
## portrait_layout.visible 就是 _apply_orientation_layout() 剛設好的狀態，
## 直接拿來判斷，不用另外存一份 is_portrait。
func _active_board_anchor() -> Control:
	return board_anchor_portrait if portrait_layout.visible else board_anchor_landscape

func _active_hold_panel() -> MiniPiecePanel:
	return hold_panel_portrait if portrait_layout.visible else hold_panel_landscape

func _active_next_panel() -> MiniPiecePanel:
	return next_panel_portrait if portrait_layout.visible else next_panel_landscape

## 畫圖邏輯抽到 TetrisBoardRenderer.gd 共用（Battle.gd 對戰畫面也會用同一份），
## 這裡只負責讀目前生效的 BoardAnchor/HoldPanel/NextPanel 節點的 rect 算
## cell_size/origin 再傳進去，不要複製一份畫圖邏輯回來。
func _draw() -> void:
	var board_anchor := _active_board_anchor()
	var hold_panel := _active_hold_panel()
	var next_panel := _active_next_panel()

	## 2026-09-22：改用 TetrisBoardRenderer.effective_size()（size × 自己＋
	## 所有祖先節點疊乘起來的 Scale），不要只讀 size——使用者可能用 Scale
	## 調整這個節點本身，也可能把它塞進別的有 Scale 的父節點底下，這樣不管
	## 巢狀幾層，算出來的大小都會跟編輯器裡實際看到的視覺大小一致。
	var board_effective_size := TetrisBoardRenderer.effective_size(board_anchor)
	_cell_size = maxf(minf(board_effective_size.x / TetrisBoard.WIDTH, board_effective_size.y / TetrisBoard.VISIBLE_HEIGHT), 8.0)
	_board_origin = board_anchor.global_position

	TetrisBoardRenderer.draw_board_frame(self, _board_origin, _cell_size)
	TetrisBoardRenderer.draw_locked_cells(self, _controller.board, _board_origin, _cell_size, _controller.get_clearing_rows())
	if not _controller.is_clearing():
		TetrisBoardRenderer.draw_ghost(self, _controller, _board_origin, _cell_size)
		TetrisBoardRenderer.draw_active_piece(self, _controller, _board_origin, _cell_size)

	var hold_rect := Rect2(hold_panel.global_position, TetrisBoardRenderer.effective_size(hold_panel))
	var next_rect := Rect2(next_panel.global_position, TetrisBoardRenderer.effective_size(next_panel))
	TetrisBoardRenderer.draw_side_panel(self, hold_rect, _controller.get_hold_type(), hold_panel.mini_cell_size, hold_panel.center_offset)
	TetrisBoardRenderer.draw_side_panel_bg(self, next_rect)
	var upcoming := _controller.peek_next_pieces(1)
	if not upcoming.is_empty():
		TetrisBoardRenderer.draw_mini_piece(self, next_rect, upcoming[0], next_panel.mini_cell_size, next_panel.center_offset)
