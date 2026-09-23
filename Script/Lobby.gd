extends CanvasLayer
class_name Lobby

## Lobby.gd — 遊戲大廳。開機第一個進的畫面，2026-09-21 起改成三個模式入口
## （見 memory/tetris_multiplayer_battle_design.md 規格記錄）：
##   - 「單人遊玩」：不連線，直接進 RoomBattleSettings.tscn（設
##     `BattleSettings.is_solo_mode = true`），跟本地連線共用房間設定/分隊
##     畫面，差別是分隊畫面可以自己填 AI 機器人。
##   - 「本地連線」：疊加開啟 MultiplayerLobby.tscn（同 WiFi 區網廣播/搜尋），
##     流程不變——房主在 RoomLobby.tscn 按「開始」之後，現在會先經過
##     RoomBattleSettings.tscn（對戰規則設定）跟 TeamSelect.tscn（分隊），
##     才真正呼叫 NetworkManager.start_match()。
##   - 「無盡挑戰」：直接切換到 Board.tscn（單人練習盤面），內建最高分紀錄。
## 「遠端連線」（不同網路，playit.gg）這次不放在大廳——使用者確認這次不需要
## （RemoteConnect.tscn/PlayitClient.gd 保留檔案，只是入口先拿掉）。
## 從 cube-combat 專案移植的連線骨架——這裡沒有搬過去該專案的「行為」系統
## 入口（BehaviorSlotUI 等），那套是方塊對戰特有的攻擊模組系統，跟俄羅斯
## 方塊無關。

@export var endless_scene_path: String = "res://Scenes/Board.tscn"
## 見 docs/adr/0005/0020（cube-combat 專案）——連線骨架第一步，開房/搜尋
## 房間的畫面。
@export var multiplayer_lobby_scene: PackedScene = preload("res://Scenes/MultiplayerLobby.tscn")
## 2026-09-22：大廳右上角齒輪按鈕，疊加開啟設定畫面（震動回饋/手勢操作），
## 跟本地連線入口同一套 instantiate/add_child/tree_exited 慣例。
@export var settings_scene: PackedScene = preload("res://Scenes/Settings.tscn")

## 2026-09-22：版面改成跟 Board/Battle 同一套「直向/橫向各一份可排版場景檔」
## 做法（`Scenes/LobbyLayoutPortrait.tscn`／`...Landscape.tscn`），拿掉原本
## CenterContainer/VBoxContainer/ScrollContainer 那套自動置中/排列，換成
## 3 顆按鈕+標題各自獨立節點、使用者自己排位置。
@onready var portrait_layout: Control = $Root/PortraitLayout
@onready var landscape_layout: Control = $Root/LandscapeLayout
@onready var solo_play_cell_portrait: Button = $Root/PortraitLayout/SoloPlayCell
@onready var solo_play_cell_landscape: Button = $Root/LandscapeLayout/SoloPlayCell
@onready var online_battle_cell_portrait: Button = $Root/PortraitLayout/OnlineBattleCell
@onready var online_battle_cell_landscape: Button = $Root/LandscapeLayout/OnlineBattleCell
@onready var endless_cell_portrait: Button = $Root/PortraitLayout/EndlessCell
@onready var endless_cell_landscape: Button = $Root/LandscapeLayout/EndlessCell
@onready var settings_button_portrait: Button = $Root/PortraitLayout/SettingsButton
@onready var settings_button_landscape: Button = $Root/LandscapeLayout/SettingsButton

var _multiplayer_lobby_instance: Control = null
var _settings_instance: Control = null


func _ready() -> void:
	solo_play_cell_portrait.pressed.connect(_on_solo_play_pressed)
	solo_play_cell_landscape.pressed.connect(_on_solo_play_pressed)
	online_battle_cell_portrait.pressed.connect(_on_online_battle_pressed)
	online_battle_cell_landscape.pressed.connect(_on_online_battle_pressed)
	endless_cell_portrait.pressed.connect(_on_endless_pressed)
	endless_cell_landscape.pressed.connect(_on_endless_pressed)
	settings_button_portrait.pressed.connect(_on_settings_pressed)
	settings_button_landscape.pressed.connect(_on_settings_pressed)

	get_viewport().size_changed.connect(_apply_orientation_layout)
	_apply_orientation_layout()

## 旋轉裝置、直向橫向比例翻轉時，切換顯示哪一組 PortraitLayout/
## LandscapeLayout，跟 Board.gd/Battle.gd 同一套做法。
func _apply_orientation_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var is_portrait := viewport_size.y >= viewport_size.x
	portrait_layout.visible = is_portrait
	landscape_layout.visible = not is_portrait


## 跟 _on_remote_battle_pressed() 同一套 instantiate/add_child/tree_exited
## 模式，關閉時不用自己收尾。
func _on_online_battle_pressed() -> void:
	if _multiplayer_lobby_instance and is_instance_valid(_multiplayer_lobby_instance):
		return
	_multiplayer_lobby_instance = multiplayer_lobby_scene.instantiate()
	add_child(_multiplayer_lobby_instance)
	_multiplayer_lobby_instance.tree_exited.connect(_on_multiplayer_lobby_closed)


func _on_multiplayer_lobby_closed() -> void:
	_multiplayer_lobby_instance = null


func _on_settings_pressed() -> void:
	if _settings_instance and is_instance_valid(_settings_instance):
		return
	_settings_instance = settings_scene.instantiate()
	add_child(_settings_instance)
	_settings_instance.tree_exited.connect(_on_settings_closed)


func _on_settings_closed() -> void:
	_settings_instance = null


func _on_solo_play_pressed() -> void:
	BattleSettings.is_solo_mode = true
	BattleSettings.reset_team_assignments()
	get_tree().change_scene_to_file("res://Scenes/RoomBattleSettings.tscn")


func _on_endless_pressed() -> void:
	get_tree().change_scene_to_file(endless_scene_path)
