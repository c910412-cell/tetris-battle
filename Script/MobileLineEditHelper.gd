class_name MobileLineEditHelper
extends RefCounted

## 【2026-09-20，第二輪修正，見使用者回報：(1) 手機要能點文字中間做編輯，
## 不是每次都跳到最後 (2) 電腦打字時游標一直被強制送到最後】第一版做法
## （手動攔截 InputEventScreenTouch 做 hit-test、每次 text_changed 都強制
## 把 caret 推到文字尾端）矯枉過正：文字尾端優先只該在「剛聚焦、還沒開始
## 打字」那一瞬間生效，卻被寫成「每一次文字改變都重新推到底」——PC 端真的
## 打字時（滑鼠點中間插入字元）反而被這裡的 text_changed 監聽器每一下都
## 彈回文字尾端，手機端也完全沒有「觸控點在文字中間哪個字元」的定位邏輯，
## 永遠只能整段選到最後。
##
## 改用 Godot 內建的「觸控模擬滑鼠」機制（Input.emulate_mouse_from_touch，
## 見 https://docs.godotengine.org/ 對應項目），讓 LineEdit 原生的點擊定位
## 游標/拖曳選取通通免費拿到，不用自己重新刻一套文字量測。這個專案全域
## 關掉這個設定（見 project.godot 的 input_devices/pointing/emulate_mouse_
## from_touch=false），理由是遊戲畫面裡不希望觸控被誤判成滑鼠點擊（3D
## 戰鬥操作），但在「純選單、沒有即時戰鬥判定」的畫面（房間設定/搜尋
## 房間）短暫開回來沒有那個副作用，畫面關閉時記得還原，不影響其他畫面。
##
## 「已經聚焦中的欄位再次點擊不會重新彈出鍵盤」這個坑（Godot 內部判斷
## 「本來就聚焦中」，不會重新觸發 FOCUS_ENTER）改用 focus_entered 訊號
## 手動補呼叫 DisplayServer.virtual_keyboard_show()——這個訊號在「原生
## 點擊聚焦」跟「程式呼叫 grab_focus()」都會觸發，不用像第一版那樣自己
## 攔截觸控事件才能決定「該不該聚焦」，LineEdit.virtual_keyboard_enabled
## 這裡關閉，避免 Godot 自動彈的鍵盤跟這裡手動呼叫的重複觸發兩次。
##
## 「鍵盤上的完成/送出鍵不會清掉 LineEdit 內部的聚焦狀態」這個坑維持
## 第一版的修法：text_submitted 時主動呼叫 release_focus()＋virtual_
## keyboard_hide()。
##
## 【2026-09-20，第三輪修正，見使用者回報「按掉鍵盤後再點同一個輸入框，
## 叫不出鍵盤」】根因：虛擬鍵盤被使用者手動收起（點鍵盤上的收起鍵、點
## 螢幕其他地方等）時，Android/iOS 系統只是關掉鍵盤視窗，不保證會讓
## LineEdit 觸發 focus_exited——Godot 這邊可能仍然認為這個欄位「還在
## 聚焦中」，這裡原本唯一呼叫 virtual_keyboard_show() 的地方是 focus_
## entered，欄位沒有真的失焦過，自然不會再觸發一次，鍵盤因此叫不回來。
## 改成額外掛一個 gui_input，只要偵測到滑鼠/觸控點擊（不管當下有沒有
## 聚焦）都主動重新呼叫一次 virtual_keyboard_show()，不依賴 focus_entered
## 這個訊號是否真的觸發——跟 focus_entered 那份呼叫同時存在也沒問題，
## 虛擬鍵盤原生就是重複呼叫顯示是安全的空操作。


static var _emulation_enabled_count: int = 0
static var _original_emulation_state: bool = false


## 呼叫端（RoomLobby.gd／MultiplayerLobby.gd）_ready() 呼叫一次——開啟
## 觸控模擬滑鼠，讓這個畫面上所有 LineEdit 原生的點擊定位/拖曳選取直接
## 可以用。用計數器而不是單純的 bool：RoomLobby 開著的同時 MultiplayerLobby
## 也還活著（疊層畫面，見 RoomLobby.gd 開頭的說明），兩邊都會各自呼叫一次
## enable/restore，只有「最後一個畫面關閉」才真的還原成專案預設值，避免
## 底層那個畫面還在、卻先被上層畫面關閉時提早還原掉。
static func enable_touch_as_mouse() -> void:
	if _emulation_enabled_count == 0:
		_original_emulation_state = Input.emulate_mouse_from_touch
		Input.emulate_mouse_from_touch = true
	_emulation_enabled_count += 1


## 呼叫端 _exit_tree()（不是 tree_exited 訊號——要在真正離開場景樹那一刻
## 同步執行，不能延後一影格，避免使用者立刻又開另一個有文字輸入的畫面時
## 這裡的還原動作跟下一個畫面的 enable_touch_as_mouse() 交錯執行順序）
## 呼叫一次。
static func restore_touch_emulation() -> void:
	_emulation_enabled_count = maxi(0, _emulation_enabled_count - 1)
	if _emulation_enabled_count == 0:
		Input.emulate_mouse_from_touch = _original_emulation_state


## 【2026-09-20，見使用者回報「點擊非輸入框的地方，游標殘留」】原生
## Godot 的焦點規則：點擊沒有可聚焦元件的空白區域，不會自動讓原本聚焦的
## 欄位失焦（桌面應用常見行為，但手機使用者預期點旁邊空白處游標/鍵盤就該
## 收起）。呼叫端在畫面最底層的背景節點（例如 RoomLobby.tscn 的
## Background ColorRect）呼叫一次——Godot 的滑鼠/觸控事件由上層往下層
## 傳遞，點擊會先被文字框/按鈕接走，只有真的點在「什麼都沒有」的地方才會
## 傳到最底層的背景，這時候才把目前聚焦的欄位手動 release_focus()＋收起
## 鍵盤。background 的 mouse_filter 要能接收事件（STOP），不然事件會直接
## 穿透消失，永遠傳不到這裡。
static func enable_defocus_on_background_tap(background: Control) -> void:
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.gui_input.connect(func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		var viewport := background.get_viewport()
		if not viewport:
			return
		var focus_owner := viewport.gui_get_focus_owner()
		if focus_owner is LineEdit:
			focus_owner.release_focus()
			DisplayServer.virtual_keyboard_hide()
	)


## 呼叫端 _ready() 對每個要顧到的 LineEdit 呼叫一次。keyboard_type 給密碼
## 這類純數字欄位傳 DisplayServer.KEYBOARD_TYPE_NUMBER，手機會彈出數字
## 鍵盤，預設是一般鍵盤。
static func setup(line_edit: LineEdit, keyboard_type: int = DisplayServer.KEYBOARD_TYPE_DEFAULT) -> void:
	line_edit.virtual_keyboard_enabled = false
	var show_keyboard := func() -> void:
		DisplayServer.virtual_keyboard_show(line_edit.text, Rect2(), keyboard_type, -1, line_edit.caret_column, line_edit.caret_column)
	line_edit.focus_entered.connect(show_keyboard)
	line_edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			show_keyboard.call()
	)
	line_edit.text_submitted.connect(func(_new_text: String) -> void:
		line_edit.release_focus()
		DisplayServer.virtual_keyboard_hide()
	)
