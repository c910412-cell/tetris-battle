## 玩家個人資料（顯示名稱/頭貼）——2026-09-24 新增。跟 PlayerSettings（震動/
## 手勢/移動速度這類「操作手感」偏好）是分開的兩件事：這裡放的是「這個人是
## 誰」，存在 user:// 底下，重開 App 也要記得。從 Lobby.tscn 左上角的頭貼
## 方塊進入 ProfileScreen.tscn 調整。
extends Node

signal profile_changed

const SAVE_PATH := "user://player_profile.cfg"

## 頭貼先用預設畫廊（Image/Avatars/Avatar0.png ~ AvatarN.png，見
## ProfileScreen.gd 讀取畫廊縮圖的說明）——使用者確認過，之後如果要換成
## 「從手機相簿選真正的照片」需要另外接原生檔案存取權限，這次先不做。
const AVATAR_COUNT := 6
const AVATAR_PATH_FORMAT := "res://Image/Avatars/Avatar%d.png"

var player_name: String = "玩家"
var avatar_id: int = 0

func _ready() -> void:
	_load()

func get_avatar_texture() -> Texture2D:
	return load(AVATAR_PATH_FORMAT % clampi(avatar_id, 0, AVATAR_COUNT - 1))

func get_avatar_texture_for(id: int) -> Texture2D:
	return load(AVATAR_PATH_FORMAT % clampi(id, 0, AVATAR_COUNT - 1))

## 名稱長度/空白限制放在這裡（唯一入口），ProfileScreen.gd 不用重複判斷。
func set_player_name(new_name: String) -> void:
	var trimmed := new_name.strip_edges()
	if trimmed == "":
		return
	player_name = trimmed.substr(0, 12)
	_save()
	profile_changed.emit()

func set_avatar_id(id: int) -> void:
	if id < 0 or id >= AVATAR_COUNT:
		return
	avatar_id = id
	_save()
	profile_changed.emit()

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "player_name", player_name)
	config.set_value("profile", "avatar_id", avatar_id)
	config.save(SAVE_PATH)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	player_name = config.get_value("profile", "player_name", "玩家")
	avatar_id = config.get_value("profile", "avatar_id", 0)
