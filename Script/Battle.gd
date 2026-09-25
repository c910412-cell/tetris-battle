## 對戰畫面（見 memory/tetris_multiplayer_battle_design.md 第 6~8/10~12 節）。
## 本地玩家的輸入/DAS-ARR 邏輯直接比照 `Board.gd`；棋盤畫面呼叫共用的
## `TetrisBoardRenderer.gd`。單一輪的對戰規則（垃圾行/抵消/結算/淘汰）全部在
## `BattleDirector.gd` 裡；這裡負責：本地玩家輸入、畫面、開場倒數、
## 指定目標攻擊的觸控選目標、**bo-N 多輪迴圈**（贏 `BattleSettings.rounds_to_win`
## 場才算贏整場，用星星顯示戰績）。
## 版面 2026-09-21 改成場景裡用 Control+anchor 真的排版，而且直向/橫向是
## 兩個完全獨立的場景檔（`Scenes/BattleLayoutPortrait.tscn`／
## `Scenes/BattleLayoutLandscape.tscn`），`Battle.tscn` 的 `BoardLayer` 底下
## 用 instance 把兩份都放進來、只顯示其中一份——要調整版面直接開對應那個
## 場景檔編輯（各自的根節點就是設計基準尺寸 1080x1920／1920x1080，還有一個
## 只在編輯器顯示的 `FrameGuide` 框線標出範圍），不用在 Battle.tscn 裡改。
## 兩份場景裡都有 `BoardAnchor`（整個 10x20 棋盤要畫在哪個範圍，cell_size
## 從這個節點的 size 除以 10/20 算出來）/`CellAnchor`（單一格的位置+大小，
## 2026-09-21 起不再拿來算 cell_size，純粹留給之後要放「一格一格」重複背景
## 素材時當參考）/`HoldPanel`+`HoldLabel`/`NextPanel`+`NextLabel`/
## `SettlementBar`（結算倒數條）/`PendingDotsAnchor`（待定點點直條的起點，
## 之後點點要換成圖片就是這裡）/`StarsLabel`（2026-09-22 新增：bo-N 戰績星星，
## 使用者自己排位置、之後可換圖片素材，不再跟結算文字綁在同一個
## VBoxContainer 裡）/8 個觸控按鈕（含 2026-09-22 新增的 `PauseButton`，
## 貼圖已經接好）/`OpponentSlots1`/`OpponentSlots2`/`OpponentSlots3`（對手
## 縮小盤面要畫在哪個範圍，依「目前對手人數」1~3 三選一顯示，每個是一個
## 容器底下放 N 個手排的 Slot 節點——人數變了版面就整個換，不是同一組節點
## 自動撐大縮小）。對手縮小盤面本體（`OpponentPanel.gd`）由
## `_rebuild_opponent_panels()` 動態生成、塞進對應人數那組的 Slot 節點底下，
## 直向/橫向各自生成一份互不共用（切換方向時靠父節點 visible 一起隱藏，
## 不用重新生成）。
## 暫停（2026-09-22 新增，同日稍晚改成可排版場景）：`PauseLayer` 底下固定
## 一片不分方向、滿版的 `Backdrop`（半透明黑底，讓暫停畫面看起來懸浮在遊戲
## 上面，兩個方向都一樣不用排）＋直向/橫向各一份可排版場景檔
## （`Scenes/BattlePauseLayoutPortrait.tscn`／`...Landscape.tscn`，跟棋盤版面
## 同一套 instance 進 `PortraitLayout`/`LandscapeLayout`、跟著
## `_apply_orientation_layout()` 切換的做法），裡面放 `PauseLabel`/
## `PauseCountdownLabel`（倒數恢復用）/`ResumeButton`/`LeaveButton`/
## `VoteDotsLabel`（多人離開投票用）。單人 vs AI（目前唯一連得到這個場景的
## 路徑，用 `BattleSettings.is_solo_mode` 判斷——實測過
## `multiplayer.has_multiplayer_peer()` 這個底層連線旗標不可靠，見
## `_on_pause_pressed()` 的說明）按暫停沒有次數限制、立刻暫停；多人改成
## 「每人整場一次機會、任何人按繼續大家一起倒數恢復、離開要過半數投票」，
## 照 `NetworkManager.gd` 既有的 RPC 慣例寫在這個檔案下半部——連線多人對戰
## 目前還沒接到 `Battle.tscn`（`NetworkManager.MATCH_SCENE_PATH` 還指向舊的
## `Board.tscn` 佔位場景），這段連不到、沒辦法實機驗證,是使用者 2026-09-22
## 明確要求先寫好、之後接上連線對戰再一起驗證的。暫停鍵本身走
## `input_action`（"tetris_pause"）+ 輪詢 `is_action_just_pressed`（跟其他
## 7 個觸控按鈕同一套機制），不是連 Button 的 `pressed`/`button_up` 訊號——
## 手機實測那條路徑不可靠。
## 結算畫面（`ResultLayer`）同一套做法拆成 `Scenes/BattleResultLayoutPortrait.tscn`／
## `...Landscape.tscn`，放 `ResultLabel`/`ReturnButton`（bo-N 戰績星星已經
## 移到棋盤版面常態顯示，不在這裡，見 `StarsLabel` 的說明）。HUD 文字
## （分數/消行/等級/開場倒數）同一天也拆成
## `Scenes/BattleHudLayoutPortrait.tscn`／`...Landscape.tscn`，每個文字都是
## 獨立節點、使用者自己排位置。
extends Node2D

const DAS_SEC := 0.2
## 2026-09-24：按住不放的連續移動間隔（ARR）原本是這裡寫死的常數，使用者
## 要求把這類「手感」細項移到大廳設定畫面可以自己調——改成讀
## PlayerSettings.move_repeat_sec（見該檔案的說明，按鈕跟手勢共用同一套
## 輪詢邏輯,改一次兩邊一起變）,不再需要本機常數。DAS（按住到開始連續移動
## 前的延遲）維持寫死,使用者這次沒有要求這個也能調。
const COUNTDOWN_SECONDS := 3.0

## HUD 文字 2026-09-22 起併回 BattleLayoutPortrait/Landscape.tscn 跟棋盤/按鈕
## 同一個檔案（原本分開放在 BattleHudLayoutPortrait/Landscape.tscn，使用者
## 反應分成兩個檔案不方便一起排版）——所以路徑是 $BoardLayer/... 不是
## $HUD/...，不再有獨立的 HUD CanvasLayer。
@onready var score_label_portrait: Label = $BoardLayer/PortraitLayout/ScoreLabel
@onready var score_label_landscape: Label = $BoardLayer/LandscapeLayout/ScoreLabel
@onready var lines_label_portrait: Label = $BoardLayer/PortraitLayout/LinesLabel
@onready var lines_label_landscape: Label = $BoardLayer/LandscapeLayout/LinesLabel
@onready var level_label_portrait: Label = $BoardLayer/PortraitLayout/LevelLabel
@onready var level_label_landscape: Label = $BoardLayer/LandscapeLayout/LevelLabel
## 2026-09-24 新增：本地玩家自己被淘汰、但隊伍還沒整個輸掉時顯示的提示——
## 見 _on_participant_eliminated() 的說明。
@onready var eliminated_label_portrait: Label = $BoardLayer/PortraitLayout/EliminatedLabel
@onready var eliminated_label_landscape: Label = $BoardLayer/LandscapeLayout/EliminatedLabel

@onready var portrait_layout: Control = $BoardLayer/PortraitLayout
@onready var landscape_layout: Control = $BoardLayer/LandscapeLayout
## 2026-09-22 起，這五個「盤面相關」節點改用 find_child() 在整個 Portrait/
## LandscapeLayout 子樹裡搜尋名字，不再寫死 `$BoardLayer/.../XXX` 的完整路徑
## ——因為使用者會在編輯器裡把 SettlementBar/PendingDotsAnchor 這類節點拖進
## BoardAnchor 底下（讓它們「跟著盤面走」的直覺操作），不管巢狀幾層、以後
## 又搬去哪個節點底下，只要名字沒改，這裡都找得到，不會再因為重新掛父節點
## 就整個 null 掉。按鈕類節點沒有這個問題（使用者不會去動它們的父節點），
## 維持原本寫死路徑就好，不用全部都改。
## 2026-09-25 修正：CountdownLabel 被拖進 BoardAspect 底下（跟著棋盤縮放）
## 之後，寫死路徑就會 null——跟這幾個一樣的問題，一起改用 find_child()。
@onready var countdown_label_portrait: Label = portrait_layout.find_child("CountdownLabel", true, false) as Label
@onready var countdown_label_landscape: Label = landscape_layout.find_child("CountdownLabel", true, false) as Label
@onready var board_anchor_portrait: Control = portrait_layout.find_child("BoardAnchor", true, false) as Control
@onready var hold_panel_portrait: Control = portrait_layout.find_child("HoldPanel", true, false) as Control
@onready var next_panel_portrait: Control = portrait_layout.find_child("NextPanel", true, false) as Control
@onready var settlement_bar_portrait: Control = portrait_layout.find_child("SettlementBar", true, false) as Control
@onready var pending_dots_anchor_portrait: PendingDotsAnchor = portrait_layout.find_child("PendingDotsAnchor", true, false) as PendingDotsAnchor
@onready var board_anchor_landscape: Control = landscape_layout.find_child("BoardAnchor", true, false) as Control
@onready var hold_panel_landscape: Control = landscape_layout.find_child("HoldPanel", true, false) as Control
@onready var next_panel_landscape: Control = landscape_layout.find_child("NextPanel", true, false) as Control
@onready var settlement_bar_landscape: Control = landscape_layout.find_child("SettlementBar", true, false) as Control
@onready var pending_dots_anchor_landscape: PendingDotsAnchor = landscape_layout.find_child("PendingDotsAnchor", true, false) as PendingDotsAnchor

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

## 對手縮小盤面依人數（1~3）分開排版，見上方檔案說明。索引 0=1 人、1=2 人、
## 2=3 人；直向/橫向各自一組，靠父節點（PortraitLayout/LandscapeLayout）
## visible 一起切換,不用另外處理。
@onready var opponent_slots_portrait: Array[Control] = [
	$BoardLayer/PortraitLayout/OpponentSlots1,
	$BoardLayer/PortraitLayout/OpponentSlots2,
	$BoardLayer/PortraitLayout/OpponentSlots3,
]
@onready var opponent_slots_landscape: Array[Control] = [
	$BoardLayer/LandscapeLayout/OpponentSlots1,
	$BoardLayer/LandscapeLayout/OpponentSlots2,
	$BoardLayer/LandscapeLayout/OpponentSlots3,
]

@onready var result_layer: CanvasLayer = $ResultLayer
@onready var result_layout_portrait: Control = $ResultLayer/PortraitLayout
@onready var result_layout_landscape: Control = $ResultLayer/LandscapeLayout
@onready var result_label_portrait: Label = $ResultLayer/PortraitLayout/ResultLabel
@onready var result_label_landscape: Label = $ResultLayer/LandscapeLayout/ResultLabel
@onready var return_button_portrait: Button = $ResultLayer/PortraitLayout/ReturnButton
@onready var return_button_landscape: Button = $ResultLayer/LandscapeLayout/ReturnButton
@onready var next_round_ready_button_portrait: Button = $ResultLayer/PortraitLayout/ReadyButton
@onready var next_round_ready_button_landscape: Button = $ResultLayer/LandscapeLayout/ReadyButton

## 2026-09-22：勝利星星移出結算文字下方的 VBoxContainer，改成場景裡跟
## HOLD/NEXT 標籤同一套做法的可排版節點（`StarsLabel`），使用者自己排位置、
## 之後也可以換成圖片素材，不用再靠 VBoxContainer 自動疊在文字下面。
@onready var stars_label_portrait: Label = $BoardLayer/PortraitLayout/StarsLabel
@onready var stars_label_landscape: Label = $BoardLayer/LandscapeLayout/StarsLabel

@onready var pause_layer: CanvasLayer = $PauseLayer
@onready var pause_layout_portrait: Control = $PauseLayer/PortraitLayout
@onready var pause_layout_landscape: Control = $PauseLayer/LandscapeLayout
@onready var pause_countdown_label_portrait: Label = $PauseLayer/PortraitLayout/PauseCountdownLabel
@onready var pause_countdown_label_landscape: Label = $PauseLayer/LandscapeLayout/PauseCountdownLabel
@onready var pause_resume_button_portrait: Button = $PauseLayer/PortraitLayout/ResumeButton
@onready var pause_resume_button_landscape: Button = $PauseLayer/LandscapeLayout/ResumeButton
@onready var pause_leave_button_portrait: Button = $PauseLayer/PortraitLayout/LeaveButton
@onready var pause_leave_button_landscape: Button = $PauseLayer/LandscapeLayout/LeaveButton
@onready var pause_vote_dots_label_portrait: Label = $PauseLayer/PortraitLayout/VoteDotsLabel
@onready var pause_vote_dots_label_landscape: Label = $PauseLayer/LandscapeLayout/VoteDotsLabel

## 2026-09-24 新增：暫停鈕旁邊的設定按鈕，開的是跟大廳齒輪按鈕完全同一份
## Settings.tscn（見 Lobby.gd._on_settings_pressed() 的 instantiate/
## add_child/tree_exited 慣例），對戰中也能調移動速度等個人設定,不用退出對戰
## 才能改。
## 2026-09-25：Portrait 版換成貼圖按鈕（見 Image/設定.png），跟 Landscape 那顆
## 還是文字+底色的 Button 不是同一種節點類型——兩邊都只用得到 BaseButton
## 共同的 pressed 訊號，型別標註改寬一點，兩種節點都收得下。
@onready var battle_settings_button_portrait: BaseButton = $BoardLayer/PortraitLayout/BattleSettingsButton
@onready var battle_settings_button_landscape: BaseButton = $BoardLayer/LandscapeLayout/BattleSettingsButton

var _director: BattleDirector
var _local_peer_id: int = 1
var _local_participant: BattleParticipant

@export var settings_scene: PackedScene = preload("res://Scenes/Settings.tscn")
var _settings_instance: Control = null

## 2026-09-23 連線對戰同步層：固定名字動態 add_child()（見該檔案開頭的
## 說明），跨輪次持續存在,每次 _start_round() 建立新的 _director 都重新呼叫
## bind_director() 換綁。單機/AI 對戰一樣會建立這個節點,但它內部
## _is_networked() 會擋掉所有真正的 RPC,行為不受影響。
var _match_sync: BattleMatchSync
## 下一輪「準備」（非房主）：跟 TeamSelect.gd 的 _is_ready 同一套模式。
var _is_next_round_ready: bool = false

var _move_dir: int = 0
var _das_timer: float = 0.0
var _arr_timer: float = 0.0

var _cell_size: float = 24.0
var _board_origin: Vector2 = Vector2.ZERO

## pid -> Array[OpponentPanel]（直向/橫向各一份，見上方檔案說明），隨每一輪
## 的參與者名單重新生成（見 _rebuild_opponent_panels()）。
var _opponent_panels: Dictionary = {}

var _countdown_remaining: float = COUNTDOWN_SECONDS
var _match_started: bool = false

## 2026-09-24 新增、後續使用者回報幾輪調整：白色波浪特效——由下往上一行
## 一行填白，填滿整個盤面後再由上往下一行一行清空。純視覺,不影響任何遊戲
## 邏輯判定。最後定案：只在「新一輪開場、清掉上一輪殘留盤面」這個時機點用
## （原本還有「本地玩家自己疊頂淘汰」那個觸發點，使用者回報不需要，已拿
## 掉）——見 _start_round()/_advance_round_transition_flash() 的說明。第一輪
## （_is_first_round）沒有舊盤面可以清，不播這個特效。
var _is_first_round: bool = true
## 使用者回報原本 0.025 太快，幾乎看不出一行一行的感覺——調到 0.05,搭配
## draw_cell()（見 _draw_round_transition_flash()）保留格線,才看得出真的是
## 「一格一格」填滿,不是一整塊純色。
const BOARD_FLASH_ROW_SEC := 0.05
var _round_transition_flash_active: bool = false
var _round_transition_flash_timer: float = 0.0
## 1＝由下往上填白（尚未點亮的行數上限，從 VISIBLE_HEIGHT 開始遞減到 0，
## 減到 0 的那一刻——整個盤面剛好全白蓋住——是真正把舊盤面資料換成新一輪
## 的時機點，見 _advance_round_transition_flash() 呼叫 _build_new_round()
## 的說明);2＝由上往下清空（已清空的行數,從 0 開始遞增到 VISIBLE_HEIGHT）。
## 兩個階段都用同一個意義：目前「白色」的行是 [_round_transition_flash_row,
## VISIBLE_HEIGHT-1]（含）這個連續區間。
var _round_transition_flash_phase: int = 0
var _round_transition_flash_row: int = 0

## bo-N 戰績：team_index -> 已經贏的回合數，整場比賽期間持續累加（跨回合
## 不歸零，只有整場比賽結束、返回大廳才會消失）。
var _team_round_wins: Dictionary = {}
## true＝結果畫面按下去要進下一輪；false＝已經整場結束，按下去回大廳。
var _pending_next_round: bool = false

const RESUME_COUNTDOWN_SECONDS := 3.0

## 暫停/離開投票：單人（solo vs AI，BattleSettings.is_solo_mode==true）
## 完全走本機分支,不用 RPC——目前唯一連得到 Battle.tscn 的路徑就是單人,見
## 上方檔案說明。多人分支照現有 NetworkManager.gd 的「client 請求→host 驗證
## →host 廣播」慣例先寫好，但連線多人對戰目前還沒有接到 Battle.tscn（
## NetworkManager.MATCH_SCENE_PATH 還是指向舊的 Board.tscn 佔位場景），這段
## 目前連不到、沒辦法實機驗證，是使用者 2026-09-22 明確要求先寫好、之後接上
## 連線對戰再一起驗證的。
var _is_paused: bool = false
var _is_resume_counting_down: bool = false
var _resume_countdown_remaining: float = 0.0
## 這個 peer 自己這整場比賽（含 bo-N 所有輪次）用掉了沒有——多人才有「一人
## 一次」的限制，不會在 _start_round() 重置（見 RPC 說明）。
var _local_pause_used: bool = false
## host 端專用記錄：peer_id -> true，誰已經用過那一次暫停機會。
var _pause_used_by: Dictionary = {}
## host 端專用記錄：peer_id -> true，誰投票要離開——每一輪重新開始時清空
## （見 _start_round()），跟 _pause_used_by/_local_pause_used 是整場比賽
## 才重置的規則不同。
var _leave_votes: Dictionary = {}

func _ready() -> void:
	_local_peer_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	_team_round_wins.clear()
	SoundEffects.connect_button(return_button_portrait)
	SoundEffects.connect_button(return_button_landscape)
	return_button_portrait.pressed.connect(_on_result_button_pressed)
	return_button_landscape.pressed.connect(_on_result_button_pressed)
	SoundEffects.connect_button(next_round_ready_button_portrait)
	SoundEffects.connect_button(next_round_ready_button_landscape)
	next_round_ready_button_portrait.pressed.connect(_on_next_round_ready_pressed)
	next_round_ready_button_landscape.pressed.connect(_on_next_round_ready_pressed)
	get_viewport().size_changed.connect(_apply_orientation_layout)
	## 2026-09-25 新增：見 SafeArea.gd 開頭的說明——整份版面平移，避開瀏海/
	## 手勢列，先只套用在這個對戰畫面（使用者要求先做這裡）。
	SafeArea.register_control(portrait_layout)
	SafeArea.register_control(landscape_layout)

	_match_sync = BattleMatchSync.new()
	_match_sync.name = "BattleMatchSync"
	add_child(_match_sync)
	_match_sync.next_round_confirmed.connect(_on_next_round_confirmed)
	_match_sync.continue_progress_updated.connect(_on_continue_progress_updated)

	pause_layer.visible = false
	SoundEffects.connect_button(pause_resume_button_portrait)
	SoundEffects.connect_button(pause_resume_button_landscape)
	pause_resume_button_portrait.pressed.connect(_on_pause_resume_pressed)
	pause_resume_button_landscape.pressed.connect(_on_pause_resume_pressed)
	SoundEffects.connect_button(pause_leave_button_portrait)
	SoundEffects.connect_button(pause_leave_button_landscape)
	pause_leave_button_portrait.pressed.connect(_on_pause_leave_pressed)
	pause_leave_button_landscape.pressed.connect(_on_pause_leave_pressed)

	SoundEffects.connect_button(battle_settings_button_portrait)
	SoundEffects.connect_button(battle_settings_button_landscape)
	battle_settings_button_portrait.pressed.connect(_on_battle_settings_pressed)
	battle_settings_button_landscape.pressed.connect(_on_battle_settings_pressed)

	PlayerSettings.settings_changed.connect(_apply_gesture_controls)
	PlayerSettings.settings_changed.connect(_apply_soft_drop_setting)
	_apply_gesture_controls()

	_start_round()

## 這台裝置對這場對戰是不是「host 權威」——AI 只能有一台裝置真正模擬、
## 攻擊/垃圾行結算跟回合勝負判定也只能有一台裝置真正算（見
## BattleDirector._is_host_authority 的說明），傳給 BattleDirector 決定
## 哪些參與者在這台裝置上是 is_local。單人/AI 對戰沒有連線，永遠是權威；
## 連線對戰要跟房主（NetworkManager.room_owner_peer_id，不是「是不是
## HOST_PEER_ID」——見 NetworkManager.gd 開頭的說明，兩者刻意分開）比對。
func _is_host_authority() -> bool:
	if BattleSettings.is_solo_mode or not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.get_unique_id() == NetworkManager.room_owner_peer_id

## 開始新的一輪：整場比賽期間會呼叫好幾次（bo-N 每輪都是全新盤面），
## _team_round_wins 不會在這裡重置。
## 2026-09-24 使用者需求再調整：第一輪沒有舊盤面可以清，直接建立＋正常
## 倒數，不播特效；第二輪開始（bo-N「下一輪」或多人的下一輪確認）才播放
## 清空轉場——而且要先播特效、播到「整個盤面全白蓋住」的那一刻才真的把
## 舊盤面換成新一輪的（見 _advance_round_transition_flash()），不是像原本
## 那樣一開始就建立新一輪、把舊盤面直接砍掉,特效才播在已經清空的空盤面上。
func _start_round() -> void:
	if _is_first_round:
		_is_first_round = false
		_build_new_round()
		_begin_countdown()
		return

	result_layer.visible = false
	_is_paused = false
	_is_resume_counting_down = false
	pause_layer.visible = false
	pause_vote_dots_label_portrait.visible = false
	pause_vote_dots_label_landscape.visible = false
	_leave_votes.clear()
	_match_started = false
	_set_countdown_visible(false)
	_start_round_transition_flash()

## 特效播到全白蓋住畫面的那一刻呼叫（見 _advance_round_transition_flash()）
## ——這裡才是原本 _start_round() 建立新一輪盤面/重新連訊號的地方,只是
## 現在延後到特效蓋住畫面之後才做,玩家不會看到「舊盤面瞬間消失」。
func _build_new_round() -> void:
	_director = BattleDirector.new(BattleSettings.network_match_seed, _local_peer_id, _is_host_authority())
	_local_participant = _director.participants.get(_local_peer_id)
	_director.round_ended.connect(_on_round_ended)
	_director.garbage_settled.connect(_on_garbage_settled)
	_director.participant_eliminated.connect(_on_participant_eliminated)
	_match_sync.bind_director(_director, _is_host_authority(), _local_peer_id)
	_apply_soft_drop_setting()

	_set_score_text("分數: 0")
	_set_lines_text("消行: 0")
	_set_level_text("等級: 1")
	if _local_participant:
		_local_participant.controller.score_changed.connect(_on_score_changed)
		_local_participant.controller.lines_cleared.connect(_on_lines_cleared)
		_local_participant.controller.level_changed.connect(_on_level_changed)
		_local_participant.controller.piece_moved.connect(SoundEffects.play_move)

	eliminated_label_portrait.visible = false
	eliminated_label_landscape.visible = false

	_rebuild_opponent_panels()
	_apply_orientation_layout()

	## 2026-09-22：星星常態顯示在版面上（不再只有結算畫面才出現）——這裡先用
	## 「這一輪開始前」的戰績填一次，讓玩家整局遊玩期間都看得到目前戰況；
	## _on_round_ended() 那邊算完這輪結果後會再刷新一次文字。
	_refresh_stars_display()
	_move_dir = 0
	_das_timer = 0.0
	_arr_timer = 0.0

## 特效完全播完（已經退到不剩半點白色）才呼叫，或第一輪沒有特效直接呼叫
## ——這裡才真的開始倒數,落點/目前方塊也是這個時間點才會開始畫（見 _draw()
## 的 _round_transition_flash_active 判斷)，等於「倒數出現、落點顯示一起
## 出現」。
func _begin_countdown() -> void:
	_countdown_remaining = COUNTDOWN_SECONDS
	_match_started = false
	_set_countdown_visible(true)

## 旋轉裝置、直向橫向比例翻轉時，切換顯示哪一組 PortraitLayout/
## LandscapeLayout——棋盤/HOLD/NEXT/結算條/點點欄/觸控按鈕的位置全部是那個
## 場景檔裡的節點決定，這裡不用再算。暫停/結算彈窗（2026-09-22 起也拆成
## 直向/橫向各一份可排版場景檔）一起跟著切，不管目前彈窗有沒有顯示都先切好
## ——彈窗真的跳出來的那一刻，裡面顯示的就已經是正確方向那份。沒翻轉時
## 重複呼叫也沒差，不用自己追蹤上次的方向。
func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	portrait_layout.visible = is_portrait
	landscape_layout.visible = not is_portrait
	pause_layout_portrait.visible = is_portrait
	pause_layout_landscape.visible = not is_portrait
	result_layout_portrait.visible = is_portrait
	result_layout_landscape.visible = not is_portrait

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

## 跟 Lobby.gd._on_settings_pressed() 同一套 instantiate/add_child/
## tree_exited 慣例——不會影響對局本身（暫停/繼續都不用觸發），純粹是疊在
## 畫面上的個人設定視窗。
## Battle 這個節點本身是 Node2D，不像 Lobby.gd 那樣自己就是 CanvasLayer——
## 直接 add_child() 到 self 的話,Settings 畫面會落在預設的 layer 0,被
## BoardLayer/PauseLayer/ResultLayer 這幾個 layer 1 的 CanvasLayer 蓋過去
## （實機截圖證實：暫停鈕旁邊按下去,設定畫面確實跳出來,但棋盤觸控按鈕/HUD
## 反而疊在設定畫面上面,擋住看不清楚)。改成包一層 CanvasLayer（layer 設
## 比 1 高)再把 Settings 塞進去,保證蓋過對戰畫面本身的所有 CanvasLayer。
func _on_battle_settings_pressed() -> void:
	if _settings_instance and is_instance_valid(_settings_instance):
		return
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 5
	add_child(overlay_layer)
	_settings_instance = settings_scene.instantiate()
	overlay_layer.add_child(_settings_instance)
	_settings_instance.tree_exited.connect(_on_battle_settings_closed.bind(overlay_layer))

func _on_battle_settings_closed(overlay_layer: CanvasLayer) -> void:
	_settings_instance = null
	overlay_layer.queue_free()

## 軟降速度是個人手感偏好（PlayerSettings.soft_drop_interval_sec），只套用
## 在本地玩家自己的 controller——AI/遠端真人的 controller 不需要也不該受這台
## 裝置的個人設定影響（見 TetrisGameController.soft_drop_gravity_sec 的
## 說明）。連上 PlayerSettings.settings_changed，玩家在對戰中用暫停鈕旁邊
## 新增的設定按鈕調整時可以立刻生效，不用等到下一輪重開才套用。
func _apply_soft_drop_setting() -> void:
	if _local_participant:
		_local_participant.controller.soft_drop_gravity_sec = PlayerSettings.soft_drop_interval_sec

## 依目前對手人數（1~3，超過 3 個先卡在 3 人那組版面，多出來的人重複塞進
## 最後一個 Slot——目前單人模式最多 3 隻 AI 碰不到這個上限，之後連線多人
## 真的會超過 3 個對手時再回來加第 4/5...組版面）挑對應那組 OpponentSlots，
## 直向/橫向各生成一份 OpponentPanel（不共用同一個節點，切換方向時才不用
## 重新生成，只是跟著父節點一起隱藏）。
func _rebuild_opponent_panels() -> void:
	for slots_group in opponent_slots_portrait + opponent_slots_landscape:
		for slot in slots_group.get_children():
			for child in slot.get_children():
				child.queue_free()
	_opponent_panels.clear()

	var opponent_ids: Array = []
	for pid in _director.participants:
		if pid != _local_peer_id:
			opponent_ids.append(pid)

	var count := clampi(opponent_ids.size(), 1, 3)
	for i in range(opponent_slots_portrait.size()):
		opponent_slots_portrait[i].visible = (i == count - 1)
		opponent_slots_landscape[i].visible = (i == count - 1)

	var portrait_slots := opponent_slots_portrait[count - 1].get_children()
	var landscape_slots := opponent_slots_landscape[count - 1].get_children()
	for i in range(opponent_ids.size()):
		var pid: int = opponent_ids[i]
		var slot_index := i % portrait_slots.size()
		_opponent_panels[pid] = [
			_spawn_opponent_panel(pid, portrait_slots[slot_index]),
			_spawn_opponent_panel(pid, landscape_slots[slot_index]),
		]

func _spawn_opponent_panel(pid: int, slot: Control) -> OpponentPanel:
	var panel := OpponentPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.participant = _director.participants[pid]
	panel.pid = pid
	## 這個對手所在隊伍目前的 bo-N 戰績星星（跟本地玩家版面上那顆共用同一套
	## _stars_for_team()）——每輪開始時 _rebuild_opponent_panels() 都會重新
	## 生成面板，這裡設一次就好，不用另外做「戰績改變就刷新」的機制。
	panel.stars_text = _stars_for_team(panel.participant.team_index, maxi(BattleSettings.rounds_to_win, 1))
	panel.panel_tapped.connect(_on_opponent_panel_tapped)
	slot.add_child(panel)
	return panel

func _process(delta: float) -> void:
	## 2026-09-22：暫停鍵改成跟其他 7 個按鈕一樣走 input_action + 輪詢
	## is_action_just_pressed（不再連 Button 的 pressed/button_up 訊號）——
	## 使用者回報連了 button_up 之後手機上按鈕本身有反應（會變色）,但遊戲
	## 邏輯完全沒被觸發,可見問題出在「Button 訊號」這條路徑本身在那台裝置
	## 上不可靠,不是接錯訊號。改用跟其他按鈕完全相同、已確認會動的機制。
	if Input.is_action_just_pressed("tetris_pause"):
		_on_pause_pressed()

	## 2026-09-24：新一輪清空轉場特效播放期間，整個新一輪都還沒真的開始
	## （連 _director 都還沒建立、倒數都還沒開始跳），這段期間本來就什麼都
	## 不該跑，播完才進入正常的倒數流程（見 _advance_round_transition_
	## flash()）。
	if _round_transition_flash_active:
		_advance_round_transition_flash(delta)
		queue_redraw()
		return

	if not _match_started:
		_countdown_remaining -= delta
		if _countdown_remaining > 0.0:
			_set_countdown_text(str(ceili(_countdown_remaining)))
		elif _countdown_remaining > -0.6:
			_set_countdown_text("GO!")
		else:
			_match_started = true
			_set_countdown_visible(false)
		queue_redraw()
		return

	if _is_paused:
		if _is_resume_counting_down:
			_resume_countdown_remaining -= delta
			if _resume_countdown_remaining <= 0.0:
				_is_resume_counting_down = false
				_is_paused = false
				pause_layer.visible = false
			else:
				var countdown_text := str(ceili(_resume_countdown_remaining))
				pause_countdown_label_portrait.text = countdown_text
				pause_countdown_label_landscape.text = countdown_text
		return

	if _local_participant and not _local_participant.is_eliminated:
		_handle_input(delta)
	_director.tick(delta)
	_refresh_opponent_panels()
	queue_redraw()

## 指定目標攻擊：房間設定開啟時，每個 OpponentPanel 自己會用 gui_input 偵測
## 觸控/點擊（見 OpponentPanel.gd），這裡只負責收訊號、轉呼叫
## BattleDirector.set_manual_target()，不用再自己算全域座標命中測試。
func _on_opponent_panel_tapped(pid: int) -> void:
	if not _match_started or not BattleSettings.targeted_attack:
		return
	if not _local_participant or _local_participant.is_eliminated:
		return
	_director.set_manual_target(_local_participant.id, pid)

func _refresh_opponent_panels() -> void:
	for pid in _opponent_panels:
		var is_target: bool = BattleSettings.targeted_attack and _local_participant != null \
			and _local_participant.current_target_id == pid
		for panel: OpponentPanel in _opponent_panels[pid]:
			panel.is_target = is_target
			panel.queue_redraw()

## 暫停鍵：單人（solo vs AI）沒有次數限制、按下立刻暫停；多人每人整場只有
## 一次機會，送出去給 host 仲裁（見 _request_pause()），自己不會立刻暫停,
## 要等 host 廣播回來（_broadcast_pause()）才真的暫停——這樣才能保證所有人
## 看到的「已暫停」狀態一致,不會有人先暫停、有人還在跑。
## 2026-09-22 除錯發現：判斷「是不是單人」原本用 multiplayer.has_multiplayer_peer()，
## 實測發現這個底層連線旗標不可靠（直接跑 Battle.tscn 這種非典型流程下會誤判
## 成 true，導致單人也走進多人 RPC 分支、送出去的 RPC 沒有任何連線可以接、
## 完全靜默失敗——玩家會看到按鈕本身有反應（觸控有送達），但暫停畫面完全
## 不會出現，跟使用者回報的症狀一致）。改用 BattleSettings.is_solo_mode——
## 這是 Lobby.gd 選「單人遊玩」時就明確設定好的旗標，語意上就是「這場是不是
## 單人」，比從底層連線狀態反推可靠、也不會受連線時序影響。
func _on_pause_pressed() -> void:
	if _is_paused or not _match_started or result_layer.visible:
		return
	if BattleSettings.is_solo_mode:
		_is_paused = true
		_show_pause_layer()
		return
	if _local_pause_used:
		return
	## 2026-09-23 修正：房主自己按暫停時,rpc_id(HOST_PEER_ID) 是「對自己送
	## RPC」——Godot 的 rpc_id() 對自己這個目標不會本機直接呼叫（除非 RPC
	## 本身有 call_local,但 _request_pause 是 any_peer,沒有),會直接被引擎
	## 擋掉、印出 "RPC '...' on yourself is not allowed by selected mode."
	## 然後什麼事都不會發生——這正是使用者回報「房主按暫停/離開沒反應」的
	## 根本原因（已經從實機測試的 log 直接證實)。照 NetworkManager.gd 既有
	## 慣例,房主自己是就直接呼叫處理函式,不透過 RPC 繞一圈。
	if multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		_handle_pause_request(NetworkManager.HOST_PEER_ID)
	else:
		_request_pause.rpc_id(NetworkManager.HOST_PEER_ID)

func _on_pause_resume_pressed() -> void:
	if not _is_paused or _is_resume_counting_down:
		return
	if BattleSettings.is_solo_mode:
		_is_paused = false
		pause_layer.visible = false
		return
	if multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		_handle_resume_request()
	else:
		_request_resume.rpc_id(NetworkManager.HOST_PEER_ID)

func _on_pause_leave_pressed() -> void:
	if BattleSettings.is_solo_mode:
		get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")
		return
	if multiplayer.get_unique_id() == NetworkManager.HOST_PEER_ID:
		_handle_leave_vote(NetworkManager.HOST_PEER_ID)
	else:
		_request_leave_vote.rpc_id(NetworkManager.HOST_PEER_ID)

func _show_pause_layer() -> void:
	pause_layer.visible = true
	pause_countdown_label_portrait.visible = false
	pause_countdown_label_landscape.visible = false
	pause_vote_dots_label_portrait.visible = not BattleSettings.is_solo_mode
	pause_vote_dots_label_landscape.visible = not BattleSettings.is_solo_mode
	if not BattleSettings.is_solo_mode:
		_update_vote_dots(0, _real_participant_count())

## 2026-09-23 使用者需求：離開投票的「過半數」門檻要跟著目前真的還在線上的
## 人數浮動——中途斷線的人不該繼續佔在分母裡（他既不能投票、也不該讓其他人
## 更難湊出過半數）。
func _real_participant_count() -> int:
	var count := 0
	for pid in _director.participants:
		var participant: BattleParticipant = _director.participants[pid]
		if not BattleSettings.is_ai(pid) and not participant.is_disconnected:
			count += 1
	return count

func _update_vote_dots(vote_count: int, total: int) -> void:
	var text := ""
	for i in range(total):
		text += "●" if i < vote_count else "○"
	pause_vote_dots_label_portrait.text = text
	pause_vote_dots_label_landscape.text = text

## ---- 多人暫停/離開投票 RPC（照 NetworkManager.gd 既有的「client 請求→
## host 驗證→host 廣播」慣例；目前連線多人對戰還沒接到 Battle.tscn，這段
## 連不到、沒辦法實機驗證，見上方檔案說明）----

@rpc("any_peer", "reliable")
func _request_pause() -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理
	_handle_pause_request(multiplayer.get_remote_sender_id())

func _handle_pause_request(sender_id: int) -> void:
	if _is_paused or _pause_used_by.has(sender_id):
		return  # 已經暫停中，或這個人這場已經用掉他的那一次機會
	_pause_used_by[sender_id] = true
	_broadcast_pause.rpc(sender_id)

## call_local——host 自己也走這條路徑暫停，不用另外維護一份重複邏輯。
## user_id 是誰觸發的這次暫停，每個收到端各自比對是不是自己，只標記自己
## 那份 _local_pause_used，不會誤標到別人身上。
@rpc("authority", "call_local", "reliable")
func _broadcast_pause(user_id: int) -> void:
	_is_paused = true
	if user_id == multiplayer.get_unique_id():
		_local_pause_used = true
	_show_pause_layer()

@rpc("any_peer", "reliable")
func _request_resume() -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return
	_handle_resume_request()

func _handle_resume_request() -> void:
	if not _is_paused or _is_resume_counting_down:
		return
	_broadcast_resume_countdown.rpc()

## 任何一個人按繼續都會走到這裡——不是只有暫停的那個人才能按。倒數本身在
## 每個 peer 自己的 _process() 本機跑,不用逐幀再送 RPC,容許幾影格誤差
## （反正目前也還沒有真正的盤面逐幀同步)。
@rpc("authority", "call_local", "reliable")
func _broadcast_resume_countdown() -> void:
	_is_resume_counting_down = true
	_resume_countdown_remaining = RESUME_COUNTDOWN_SECONDS
	pause_countdown_label_portrait.visible = true
	pause_countdown_label_landscape.visible = true

@rpc("any_peer", "reliable")
func _request_leave_vote() -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return
	_handle_leave_vote(multiplayer.get_remote_sender_id())

## 2026-09-23 修正：使用者明確要求「離開」是回到房間（可以直接開下一局），
## 不是整個斷線回主選單——這裡原本自己送一個 _broadcast_leave_match RPC
## 切去 Lobby.tscn（連 NetworkManager.cancel() 都要自己補），現在直接重用
## NetworkManager.end_match() 既有的「房主在對局場景按返回」邏輯（見該函式
## 說明）：保留房間本身（連線/房間設定），帶大家一起回到 MultiplayerLobby
## （會自動重新開啟 RoomBattleSettings.tscn 房間等候畫面），房主可以直接開
## 下一局，不用整個重新搜尋/加入。這個函式只會在 host 這台裝置上執行（見
## _on_pause_leave_pressed()／_request_leave_vote() 的呼叫路徑），
## end_match() 內部會再檢查一次「呼叫者是不是房主」才會真的生效。
func _handle_leave_vote(sender_id: int) -> void:
	if _leave_votes.has(sender_id):
		return  # 每人只能投一次，不能反悔取消
	_leave_votes[sender_id] = true
	var total := _real_participant_count()
	if _leave_votes.size() * 2 > total:
		NetworkManager.end_match()
	else:
		_broadcast_leave_votes.rpc(_leave_votes.size(), total)

@rpc("authority", "call_local", "reliable")
func _broadcast_leave_votes(vote_count: int, total: int) -> void:
	_update_vote_dots(vote_count, total)

func _handle_input(delta: float) -> void:
	var controller := _local_participant.controller
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
			controller.move(dir)
	elif dir != 0:
		_das_timer += delta
		if _das_timer >= DAS_SEC:
			_arr_timer += delta
			var arr_sec := maxf(PlayerSettings.move_repeat_sec, 0.01)
			while _arr_timer >= arr_sec:
				_arr_timer -= arr_sec
				controller.move(dir)

	controller.set_soft_drop(Input.is_action_pressed("tetris_soft_drop"))

	if Input.is_action_just_pressed("tetris_hard_drop"):
		controller.hard_drop()
		SoundEffects.play_hard_drop()
	if Input.is_action_just_pressed("tetris_rotate_cw"):
		controller.rotate(true)
	if Input.is_action_just_pressed("tetris_rotate_ccw"):
		controller.rotate(false)
	if Input.is_action_just_pressed("tetris_hold"):
		controller.hold()

func _on_score_changed(new_score: int) -> void:
	_set_score_text("分數: %d" % new_score)

func _on_lines_cleared(count: int) -> void:
	_set_lines_text("消行: %d" % _local_participant.controller.lines_cleared_total)
	if count > 0:
		PlayerSettings.vibrate(20 + count * 10)
		SoundEffects.play_line_clear()

func _on_level_changed(new_level: int) -> void:
	_set_level_text("等級: %d" % new_level)

## HUD 文字（分數/消行/等級/倒數）2026-09-22 起也拆成直向/橫向各一份可排版
## 場景檔（`Scenes/BattleHudLayoutPortrait.tscn`／`...Landscape.tscn`），跟其他
## 彈窗同一套做法：直向/橫向兩份都要寫，不是只寫目前生效那份。
func _set_score_text(text: String) -> void:
	score_label_portrait.text = text
	score_label_landscape.text = text

func _set_lines_text(text: String) -> void:
	lines_label_portrait.text = text
	lines_label_landscape.text = text

func _set_level_text(text: String) -> void:
	level_label_portrait.text = text
	level_label_landscape.text = text

func _set_countdown_text(text: String) -> void:
	countdown_label_portrait.text = text
	countdown_label_landscape.text = text

func _set_countdown_visible(v: bool) -> void:
	countdown_label_portrait.visible = v
	countdown_label_landscape.visible = v

## 只有「自己」身上真的疊上垃圾行才震動——對手被打不用管。
func _on_garbage_settled(participant_id: int, lines: int) -> void:
	if lines <= 0 or not _local_participant or participant_id != _local_participant.id:
		return
	PlayerSettings.vibrate(30 + lines * 20)

## 自己被淘汰（旁觀模式開始）給一個比消行更明顯的震動；隊友/對手淘汰不用管。
## 2026-09-24 使用者回報兩個問題,都是同一個根因：原本沒檢查「自己被淘汰的
## 當下,隊伍是不是還有其他人活著」——(1) 單人模式常見的設定是玩家自己單獨
## 一隊、沒有隊友,這種情況一淘汰就等於整隊輸了,回合會在同一個呼叫鏈裡
## 緊接著結束（_check_round_end() 同步觸發),「已被淘汰/等待隊友」這句話
## 根本不成立、卻還是會跳出來,而且沒有先隱藏就被結算畫面蓋上去,兩層畫面
## 疊在一起。(2) 就算隊伍還有人,也該先確認「有人可以等」才顯示,不是自己
## 一淘汰就無條件顯示。修法：只有隊伍裡還有其他活著的人時才顯示這個提示；
## _on_round_ended() 那邊也補一道保險,回合真的結束時一定先把提示藏起來
## （不管前面有沒有顯示過),不會殘留到結算畫面上。
func _on_participant_eliminated(participant_id: int) -> void:
	if not _local_participant or participant_id != _local_participant.id:
		return
	PlayerSettings.vibrate(200)
	if _local_team_has_survivor():
		eliminated_label_portrait.visible = true
		eliminated_label_landscape.visible = true

## 本地玩家所在隊伍，除了自己之外還有沒有其他還活著（沒淘汰、沒斷線）的人
## ——「已被淘汰/等待隊友」這句話只有在真的還有隊友可以等時才成立。
func _local_team_has_survivor() -> bool:
	for pid in _director.participants:
		var other: BattleParticipant = _director.participants[pid]
		if other.id != _local_participant.id and other.team_index == _local_participant.team_index \
				and not other.is_eliminated and not other.is_disconnected:
			return true
	return false

func _start_round_transition_flash() -> void:
	_round_transition_flash_active = true
	_round_transition_flash_timer = 0.0
	_round_transition_flash_phase = 1
	_round_transition_flash_row = TetrisBoard.VISIBLE_HEIGHT

## 見 BOARD_FLASH_ROW_SEC 的說明。填到滿（phase 1 結束）的那一刻呼叫
## _build_new_round()——這是舊盤面真正被換成新一輪的時間點，畫面上這時候
## 剛好整片全白蓋住，玩家看不到「盤面瞬間清空」的痕跡。清到底（phase 2
## 結束、整片白色都退完）才呼叫 _begin_countdown()，倒數文字跟目前方塊/
## 落點顯示（見 _draw() 的判斷）都在這個時間點才一起出現。
func _advance_round_transition_flash(delta: float) -> void:
	_round_transition_flash_timer += delta
	while _round_transition_flash_active and _round_transition_flash_timer >= BOARD_FLASH_ROW_SEC:
		_round_transition_flash_timer -= BOARD_FLASH_ROW_SEC
		if _round_transition_flash_phase == 1:
			_round_transition_flash_row -= 1
			if _round_transition_flash_row <= 0:
				_round_transition_flash_row = 0
				_round_transition_flash_phase = 2
				_build_new_round()
		else:
			_round_transition_flash_row += 1
			if _round_transition_flash_row >= TetrisBoard.VISIBLE_HEIGHT:
				_round_transition_flash_active = false
				_begin_countdown()

## bo-N 判定：贏這輪的隊伍戰績+1，達到 BattleSettings.rounds_to_win 就是整場
## 比賽結束；沒達到就顯示這輪結果，按鈕變成「下一輪」。
func _on_round_ended(winning_team: int) -> void:
	## 見 _on_participant_eliminated() 的說明——回合真的結束了,不管前面有沒有
	## 顯示過「已被淘汰」都先藏起來,避免跟這裡即將顯示的結算畫面疊在一起。
	eliminated_label_portrait.visible = false
	eliminated_label_landscape.visible = false
	if winning_team != -1:
		_team_round_wins[winning_team] = _team_round_wins.get(winning_team, 0) + 1

	var target_wins: int = maxi(BattleSettings.rounds_to_win, 1)
	var match_winner := -1
	for team in _team_round_wins:
		if _team_round_wins[team] >= target_wins:
			match_winner = team
			break

	result_layer.visible = true
	_refresh_stars_display()

	if match_winner != -1:
		_pending_next_round = false
		if _local_participant and _local_participant.team_index == match_winner:
			_set_result_text("你贏得整場比賽！")
		else:
			_set_result_text("你輸了整場比賽")
	else:
		_pending_next_round = true
		if winning_team == -1:
			_set_result_text("這輪平手")
		elif _local_participant and _local_participant.team_index == winning_team:
			_set_result_text("你贏了這輪！")
		else:
			_set_result_text("你輸了這輪")

	_refresh_result_buttons()

## 多人模式下「下一輪」/「返回大廳」比照房間設定/分隊畫面「加入方按準備、
## 房主按開始」模式（2026-09-23 使用者明確要求一致，不要「大家按同一顆鈕」
## 的投票模式）——單機模式沒有連線、沒有其他人要等，維持原本「一顆鈕、
## 自己按了就走」的行為。整場比賽結束時（!_pending_next_round）只有房主
## 看得到「返回大廳」（NetworkManager.end_match() 本來就只有房主呼叫得動，
## 見該函式說明），其他人只能等房主按。
func _refresh_result_buttons() -> void:
	if BattleSettings.is_solo_mode:
		_set_return_button_visible(true)
		_set_next_round_ready_button_visible(false)
		_set_return_button_text("下一輪" if _pending_next_round else "返回大廳")
		return_button_portrait.disabled = false
		return_button_landscape.disabled = false
		return

	if not _pending_next_round:
		_set_return_button_visible(_is_host_authority())
		_set_next_round_ready_button_visible(false)
		_set_return_button_text("返回大廳")
		return_button_portrait.disabled = false
		return_button_landscape.disabled = false
		return

	_is_next_round_ready = false
	if _is_host_authority():
		_set_return_button_visible(true)
		_set_next_round_ready_button_visible(false)
		_set_return_button_text("下一輪開始 (0/%d)" % _match_sync.get_required_continue_count())
		return_button_portrait.disabled = true
		return_button_landscape.disabled = true
	else:
		_set_return_button_visible(false)
		_set_next_round_ready_button_visible(true)
		_set_next_round_ready_text("準備")

func _set_result_text(text: String) -> void:
	result_label_portrait.text = text
	result_label_landscape.text = text

func _set_return_button_text(text: String) -> void:
	return_button_portrait.text = text
	return_button_landscape.text = text

func _set_return_button_visible(v: bool) -> void:
	return_button_portrait.visible = v
	return_button_landscape.visible = v

func _set_next_round_ready_button_visible(v: bool) -> void:
	next_round_ready_button_portrait.visible = v
	next_round_ready_button_landscape.visible = v

func _set_next_round_ready_text(text: String) -> void:
	next_round_ready_button_portrait.text = text
	next_round_ready_button_landscape.text = text

## 常態顯示在版面上的整場戰績摘要（2026-09-22 起不再只有結算畫面才顯示，
## _start_round()/_on_round_ended() 都會呼叫這個，直向/橫向兩份都寫,不是只
## 寫目前生效那份——玩家隨時可能轉裝置,兩份都要有正確內容才不會轉完星星
## 就不見）。
func _refresh_stars_display() -> void:
	var target_wins: int = maxi(BattleSettings.rounds_to_win, 1)
	var stars_text := _build_stars_text(target_wins)
	stars_label_portrait.visible = true
	stars_label_portrait.text = stars_text
	stars_label_landscape.visible = true
	stars_label_landscape.text = stars_text

func _build_stars_text(target_wins: int) -> String:
	var lines: Array[String] = []
	for team in range(BattleSettings.TEAM_COUNT):
		if not _team_in_play(team):
			continue
		lines.append("%s %s" % [BattleSettings.TEAM_NAMES[team], _stars_for_team(team, target_wins)])
	return "\n".join(lines)

## 給單一隊伍的星星字串（"★★☆" 這種），本地玩家的整場摘要
## （_build_stars_text()）跟每個對手縮小盤面自己那顆星星提示
## （_spawn_opponent_panel()）共用同一份，不要各自重算一次。
func _stars_for_team(team_index: int, target_wins: int) -> String:
	var wins: int = _team_round_wins.get(team_index, 0)
	var stars := ""
	for i in range(target_wins):
		stars += "★" if i < wins else "☆"
	return stars

func _team_in_play(team_index: int) -> bool:
	for pid in _director.participants:
		if _director.participants[pid].team_index == team_index:
			return true
	return false

## 單機：跟原本行為完全一樣，一顆鈕自己按了就走。多人：這顆鈕現在只有房主
## 看得到（見 _refresh_result_buttons()），「下一輪」呼叫
## _match_sync.start_next_round()（房主端再驗一次所有人是否都準備好）、
## 「返回大廳」呼叫 NetworkManager.end_match()（帶大家一起回房間，不是整個
## 斷線回主選單，見該函式說明）。
func _on_result_button_pressed() -> void:
	if BattleSettings.is_solo_mode:
		if _pending_next_round:
			_start_round()
		else:
			get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")
		return
	if _pending_next_round:
		_match_sync.start_next_round()
	else:
		NetworkManager.end_match()

## 非房主的「準備」/「取消準備」——跟 TeamSelect._on_ready_pressed() 同一套
## 模式，切換本機狀態、送給 host 標記，等房主那邊看到大家都準備好才會按下
## 「下一輪開始」。
func _on_next_round_ready_pressed() -> void:
	_is_next_round_ready = not _is_next_round_ready
	_set_next_round_ready_text("取消準備" if _is_next_round_ready else "準備")
	_match_sync.request_continue(_is_next_round_ready)

## 房主按下「下一輪開始」、所有人都確認後,BattleMatchSync 廣播回來——大家
## 一起真的開始下一輪。
func _on_next_round_confirmed() -> void:
	_start_round()

## 房主端顯示「還差幾個人準備好」；非房主不需要這份文字（跟 TeamSelect 一樣
## 只顯示「已準備/等待房主」的靜態文字,不用即時人數)。
func _on_continue_progress_updated(confirmed: int, total: int) -> void:
	if not _is_host_authority() or _pending_next_round == false:
		return
	_set_return_button_text("下一輪開始 (%d/%d)" % [confirmed, total])
	var can_start := confirmed >= total
	return_button_portrait.disabled = not can_start
	return_button_landscape.disabled = not can_start

## 目前生效的那組（Portrait 或 Landscape）節點——portrait_layout.visible 就是
## _apply_orientation_layout() 剛設好的狀態，直接拿來判斷，不用另外存一份
## is_portrait。
func _active_board_anchor() -> Control:
	return board_anchor_portrait if portrait_layout.visible else board_anchor_landscape

func _active_hold_panel() -> Control:
	return hold_panel_portrait if portrait_layout.visible else hold_panel_landscape

func _active_next_panel() -> Control:
	return next_panel_portrait if portrait_layout.visible else next_panel_landscape

func _active_settlement_bar() -> Control:
	return settlement_bar_portrait if portrait_layout.visible else settlement_bar_landscape

func _active_pending_dots_anchor() -> PendingDotsAnchor:
	return pending_dots_anchor_portrait if portrait_layout.visible else pending_dots_anchor_landscape

## 畫圖邏輯抽到 TetrisBoardRenderer.gd 共用（Board.gd 也用同一份），這裡只
## 負責讀目前生效的 BoardAnchor/HoldPanel/NextPanel/SettlementBar/
## PendingDotsAnchor 節點的 rect 算 cell_size/origin 再傳進去，不再自己用
## 公式算版面位置——對手縮小盤面則是各自的 OpponentPanel 自己在 _draw()
## 裡處理，不在這裡畫。
func _draw() -> void:
	if not _local_participant:
		return
	var controller := _local_participant.controller

	var board_anchor := _active_board_anchor()
	## 2026-09-22：改用 TetrisBoardRenderer.effective_size()（size × 自己＋
	## 所有祖先節點疊乘起來的 Scale），不要只讀 size——使用者可能用 Scale
	## 調整這個節點本身，也可能把它塞進別的有 Scale 的父節點底下，這樣不管
	## 巢狀幾層，算出來的大小都會跟編輯器裡實際看到的視覺大小一致。
	var board_effective_size := TetrisBoardRenderer.effective_size(board_anchor)
	_cell_size = maxf(minf(board_effective_size.x / TetrisBoard.WIDTH, board_effective_size.y / TetrisBoard.VISIBLE_HEIGHT), 8.0)
	_board_origin = board_anchor.global_position

	TetrisBoardRenderer.draw_board_frame(self, _board_origin, _cell_size)
	TetrisBoardRenderer.draw_locked_cells(self, controller.board, _board_origin, _cell_size, controller.get_clearing_rows())
	if _round_transition_flash_active:
		_draw_round_transition_flash()
	## 2026-09-24 使用者需求：目前方塊/落點要等特效播完才出現，跟倒數文字
	## 一起出現（見 _begin_countdown() 的說明），特效播放期間先不畫。
	if not _round_transition_flash_active and not controller.is_game_over and not controller.is_clearing():
		TetrisBoardRenderer.draw_ghost(self, controller, _board_origin, _cell_size)
		TetrisBoardRenderer.draw_active_piece(self, controller, _board_origin, _cell_size)

	var hold_panel := _active_hold_panel()
	var next_panel := _active_next_panel()
	var hold_rect := Rect2(hold_panel.global_position, TetrisBoardRenderer.effective_size(hold_panel))
	var next_rect := Rect2(next_panel.global_position, TetrisBoardRenderer.effective_size(next_panel))
	TetrisBoardRenderer.draw_side_panel(self, hold_rect, controller.get_hold_type())
	TetrisBoardRenderer.draw_side_panel_bg(self, next_rect)
	var upcoming := controller.peek_next_pieces(1)
	if not upcoming.is_empty():
		TetrisBoardRenderer.draw_mini_piece(self, next_rect, upcoming[0])

	## Y 座標改成從 _board_origin/_cell_size 現算（鎖定在最下面那個可視行的
	## 上下正中間），不要直接讀 PendingDotsAnchor 節點的固定座標——這樣
	## BoardAnchor 被使用者放大/縮小時，點點的間距（spacing=_cell_size，本來
	## 就會跟著縮放）跟起始高度才會一起跟著變，不會維持在縮放前的舊位置。
	## X 座標維持讀 PendingDotsAnchor（使用者自己排要離盤面多遠）。
	## 2026-09-22 起 X/Y 都改成每一幀直接用目前的 _board_origin/_cell_size
	## 現算（不再讀 PendingDotsAnchor 節點自己的固定座標）：第一顆點對齊在
	## 最下面那個可視行的正中間，水平固定在盤面左邊 0.6 格的距離——跟對手
	## 縮小盤面（OpponentPanel.gd）現算 dots_start 的公式是同一套，使用者把
	## BoardAnchor 放大縮小時，點的位置/間距/大小（dot_size_ratio，見
	## PendingDotsAnchor.gd）就都會自動跟著正確換算，不用手動重排這個節點。
	var dots_anchor := _active_pending_dots_anchor()
	var dots_start_pos := Vector2(
		_board_origin.x - _cell_size * 0.6,
		_board_origin.y + TetrisBoard.VISIBLE_HEIGHT * _cell_size - _cell_size / 2.0,
	)
	TetrisBoardRenderer.draw_pending_dots(self, _local_participant.pending_garbage.size(), dots_start_pos, _cell_size, dots_anchor.dot_size_ratio)
	_draw_settlement_bar()

## 找到長度對不上的真正原因：BoardAnchor 沒有精準卡在 10:20 的比例
## （寬度算出來的 cell_size 比高度算出來的還大，多出來的水平空間被讓掉，
## 見 _draw() 的 min(width/10, height/20)）——所以 BoardAnchor 自己的寬度
## 一定比「棋盤實際畫出來的寬度」還寬，SettlementBar 用 BoardAnchor 的比例
## 去抓自己的寬度，理所當然會比棋盤本身還長。改成寬度／X 座標直接鎖定
## _cell_size*10／_board_origin.x（棋盤實際畫出來的範圍，跟 PendingDotsAnchor
## 現算位置同一個原則），保證永遠精準對齊棋盤兩側，不受 BoardAnchor 比例
## 影響；高度／Y 座標維持讀節點本身（粗細、離棋盤多遠讓使用者自己決定）。
func _draw_settlement_bar() -> void:
	var bar := _active_settlement_bar()
	var bar_height := TetrisBoardRenderer.effective_size(bar).y
	var bar_rect := Rect2(Vector2(_board_origin.x, bar.global_position.y), Vector2(_cell_size * TetrisBoard.WIDTH, bar_height))
	var progress := _director.get_settlement_progress()
	draw_rect(bar_rect, Color(0.2, 0.2, 0.24), true)
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * progress, bar_rect.size.y)), Color(0.9, 0.6, 0.2), true)

## 見 BOARD_FLASH_ROW_SEC 的說明——目前「白色」的行永遠是
## [_round_transition_flash_row, VISIBLE_HEIGHT-1] 這個連續區間。畫在剛畫好
## 的（舊一輪，直到 phase 1 結束前都還是舊資料，見
## _advance_round_transition_flash() 的說明）鎖定格子上面——用跟鎖定方塊
## 同一個 TetrisBoardRenderer.draw_cell()（每格內縮 1px），格與格之間會
## 露出底色當格線，看起來才像「一格一格」疊起來，不是一片死白。
func _draw_round_transition_flash() -> void:
	if _round_transition_flash_row >= TetrisBoard.VISIBLE_HEIGHT:
		return
	for row in range(_round_transition_flash_row, TetrisBoard.VISIBLE_HEIGHT):
		for col in range(TetrisBoard.WIDTH):
			TetrisBoardRenderer.draw_cell(self, _board_origin, _cell_size, col, row, Color(1, 1, 1, 1))
