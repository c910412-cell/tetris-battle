extends CanvasLayer
class_name Lobby

## Lobby.gd — 遊戲大廳。開機第一個進的畫面，三個入口：
##   - 「單人練習」：直接切換到 Board.tscn（目前是空白佔位，見該檔案）。
##   - 「連線對戰」：疊加開啟 MultiplayerLobby.tscn（同 WiFi 區網廣播/搜尋）。
##   - 「遠端連線」：疊加開啟 RemoteConnect.tscn（不同網路，走 playit.gg
##     通道）。
## 從 cube-combat 專案移植的連線骨架——這裡沒有搬過去該專案的「行為」系統
## 入口（BehaviorSlotUI 等），那套是方塊對戰特有的攻擊模組系統，跟俄羅斯
## 方塊無關。

@export var practice_scene_path: String = "res://Scenes/Board.tscn"
## 見 docs/adr/0005/0020（cube-combat 專案）——連線骨架第一步，開房/搜尋
## 房間的畫面。
@export var multiplayer_lobby_scene: PackedScene = preload("res://Scenes/MultiplayerLobby.tscn")
## 跟 multiplayer_lobby_scene 平行的另一條入口——這裡完全不透過區網 UDP
## 廣播，見 RemoteConnect.gd 的說明。
@export var remote_connect_scene: PackedScene = preload("res://Scenes/RemoteConnect.tscn")

@onready var practice_cell: Button = $Root/CenterContainer/MainColumn/ModePanel/ModeMargin/ModeScroll/ModeRow/PracticeCell
@onready var online_battle_cell: Button = $Root/CenterContainer/MainColumn/ModePanel/ModeMargin/ModeScroll/ModeRow/OnlineBattleCell
@onready var remote_battle_cell: Button = $Root/CenterContainer/MainColumn/ModePanel/ModeMargin/ModeScroll/ModeRow/RemoteBattleCell

var _multiplayer_lobby_instance: Control = null
var _remote_connect_instance: Control = null


func _ready() -> void:
	practice_cell.pressed.connect(_on_practice_pressed)
	online_battle_cell.pressed.connect(_on_online_battle_pressed)
	remote_battle_cell.pressed.connect(_on_remote_battle_pressed)


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


func _on_remote_battle_pressed() -> void:
	if _remote_connect_instance and is_instance_valid(_remote_connect_instance):
		return
	_remote_connect_instance = remote_connect_scene.instantiate()
	add_child(_remote_connect_instance)
	_remote_connect_instance.tree_exited.connect(_on_remote_connect_closed)


func _on_remote_connect_closed() -> void:
	_remote_connect_instance = null


func _on_practice_pressed() -> void:
	get_tree().change_scene_to_file(practice_scene_path)
