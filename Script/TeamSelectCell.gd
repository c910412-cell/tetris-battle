## 分隊畫面的單一格子。一般點擊（沒有拖曳位移）由 TeamSelect.gd 透過
## `pressed` 訊號處理加入/移除；這個腳本額外實作 Godot 內建的 Control
## 拖放（`_get_drag_data`/`_can_drop_data`/`_drop_data`），讓玩家可以用拖曳
## 把自己或 AI 移到別的格子、跟別人互換（2026-09-21 補充需求，見
## memory/tetris_multiplayer_battle_design.md）。
extends Button

var team_index: int = -1
var slot_index: int = -1
## 指回 TeamSelect.gd，實際的搬移/驗證邏輯都在那邊做，這裡只轉發座標。
var controller: Node = null

func _get_drag_data(_at_position: Vector2) -> Variant:
	if controller == null or not controller.can_drag_cell(team_index, slot_index):
		return null
	var preview := Label.new()
	preview.text = text
	preview.add_theme_font_size_override("font_size", 22)
	set_drag_preview(preview)
	return {"from_team": team_index, "from_slot": slot_index}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if controller == null or typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("from_team") or not data.has("from_slot"):
		return false
	return controller.can_drop_on_cell(team_index, slot_index)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	controller.handle_cell_drop(data["from_team"], data["from_slot"], team_index, slot_index)
