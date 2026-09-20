extends Control
class_name RemoteConnect
## 【2026-09-20，見使用者需求：電腦當橋接站/無頭伺服器，房主身分由遠端
## 手機用代碼認領】大廳新增的「遠端連線」入口——跟 MultiplayerLobby.tscn
## （同 WiFi 搜尋房間）是平行的兩條路徑，不會互相影響：這裡完全不透過
## 區網 UDP 廣播，位址/代碼都是使用者手動輸入（見對話討論：拿掉自動房間
## 列表，改用手動代碼分享）。
##
## 三種模式：
## - 成為伺服器（電腦專用，見 _ready() 的平台判斷）：先登入 playit.gg
##   （見 PlayitClient.gd 的說明——整套認領流程包在遊戲裡，不用切去瀏覽器
##   自己複製貼上任何東西，只有「按下確認」那個動作躲不掉），登入成功後
##   建立通道＋啟動轉發常駐程式，畫面上顯示可複製的連線位址。接著二選一：
##   「開啟」＝呼叫 NetworkManager.host_game() 帶上 owner_code，這台電腦
##   本身不會自動變房主（見 NetworkManager.room_owner_peer_id 的說明），
##   等某個裝置用同一組代碼呼叫 join_as_owner_candidate() 才會真的認領；
##   「自己開房間」＝owner_code 留空，立刻變成一般的房主，跳到平常那套
##   可編輯設定的房間畫面（跟 MultiplayerLobby「開房」流程一致），但通道
##   還是會建立，遠端朋友一樣能用位址連進來。兩者互斥，見 _set_action_
##   buttons_disabled() 的說明。
## - 連結伺服器（認領房主）：輸入對方的連線位址（例如 playit.gg 給的位址）
##   + 房主代碼，呼叫 NetworkManager.join_as_owner_candidate()，成功後這個
##   裝置就會變成代理房主，能編輯房間設定/按開始。
## - 加入遠端連線（見使用者需求：一般玩家沒有管道可以連進已經開好的房間）：
##   輸入位址 + 房間密碼（不是房主代碼，一般玩家不需要也不該知道房主代碼），
##   呼叫既有的 NetworkManager.join_game()，跟同 WiFi 搜尋房間點進去加入是
##   同一條路徑，只是位址來源是手動輸入而不是區網廣播搜到的。

@onready var background: ColorRect = $Background
@onready var back_button: Button = $CenterContainer/Panel/Margin/Layout/TopBar/BackButton
@onready var become_server_button: Button = $CenterContainer/Panel/Margin/Layout/ModeRow/BecomeServerButton
@onready var connect_server_button: Button = $CenterContainer/Panel/Margin/Layout/ModeRow/ConnectServerButton
@onready var join_remote_button: Button = $CenterContainer/Panel/Margin/Layout/ModeRow/JoinRemoteButton
@onready var become_server_section: VBoxContainer = $CenterContainer/Panel/Margin/Layout/BecomeServerSection
@onready var connect_server_section: VBoxContainer = $CenterContainer/Panel/Margin/Layout/ConnectServerSection
@onready var join_remote_section: VBoxContainer = $CenterContainer/Panel/Margin/Layout/JoinRemoteSection

@onready var help_button: Button = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/InfoRow/HelpButton
@onready var register_link_button: LinkButton = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/RegisterLinkButton
@onready var login_button: Button = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/LoginButton
@onready var login_status_label: Label = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/LoginStatusRow/LoginStatusLabel
@onready var logout_button: Button = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/LoginStatusRow/LogoutButton
@onready var post_login_section: VBoxContainer = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/PostLoginSection
@onready var address_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/PostLoginSection/AddressEdit
@onready var become_owner_code_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/PostLoginSection/OwnerCodeEdit
@onready var start_server_button: Button = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/PostLoginSection/ActionRow/StartServerButton
@onready var host_myself_button: Button = $CenterContainer/Panel/Margin/Layout/BecomeServerSection/PostLoginSection/ActionRow/HostMyselfButton

@onready var connect_address_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/ConnectServerSection/AddressEdit
@onready var connect_owner_code_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/ConnectServerSection/OwnerCodeEdit
@onready var connect_confirm_button: Button = $CenterContainer/Panel/Margin/Layout/ConnectServerSection/ConnectConfirmButton

@onready var join_address_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/JoinRemoteSection/AddressEdit
@onready var join_password_edit: LineEdit = $CenterContainer/Panel/Margin/Layout/JoinRemoteSection/PasswordEdit
@onready var join_confirm_button: Button = $CenterContainer/Panel/Margin/Layout/JoinRemoteSection/JoinConfirmButton

@onready var status_label: Label = $CenterContainer/Panel/Margin/Layout/StatusLabel

const ROOM_LOBBY_SCENE: PackedScene = preload("res://Scenes/RoomLobby.tscn")

var _room_lobby_instance: Control = null
## 見 _on_start_server_pressed()/_on_host_myself_pressed() 的說明——記住
## 使用者按的是哪一顆，通道準備好之後才知道要用哪一組 owner_code 呼叫
## host_game()。
var _pending_owner_code_for_host: String = ""
## 【2026-09-20，見使用者回報「成為伺服器的電腦本身不用跳出房間UI」】
## true 代表這台電腦是按「開啟」變成無人操作的中繼站（owner_code 非空，
## 房主身分留給遠端裝置認領）——這種情況不開 RoomLobby.tscn（電腦本身
## 不需要操作那個畫面，見 _start_room_after_tunnel() 的分支判斷），改成
## 留在這個畫面上顯示狀態，靠 NetworkManager.room_state_updated 監聽「有人
## 連進來認領房主了嗎」，見 _on_room_state_updated() 的說明。按「自己開
## 房間」時這裡是 false，維持原本跳進 RoomLobby.tscn 的行為（電腦本身就是
## 房主，需要操作那個畫面）。
var _dedicated_hosting_active: bool = false


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	become_server_button.pressed.connect(_on_become_server_mode_pressed)
	connect_server_button.pressed.connect(_on_connect_server_mode_pressed)
	join_remote_button.pressed.connect(_on_join_remote_mode_pressed)
	help_button.pressed.connect(_on_help_pressed)
	login_button.pressed.connect(_on_login_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	start_server_button.pressed.connect(_on_start_server_pressed)
	host_myself_button.pressed.connect(_on_host_myself_pressed)
	connect_confirm_button.pressed.connect(_on_connect_server_confirm_pressed)
	join_confirm_button.pressed.connect(_on_join_remote_confirm_pressed)

	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.joined_as_client.connect(_on_joined_as_client)
	NetworkManager.room_join_rejected.connect(_on_join_rejected)
	NetworkManager.room_state_updated.connect(_on_room_state_updated)
	NetworkManager.match_starting.connect(_on_match_starting)

	PlayitClient.claim_status_changed.connect(_on_playit_claim_status_changed)
	PlayitClient.claimed.connect(_on_playit_claimed)
	PlayitClient.claim_failed.connect(_on_playit_claim_failed)
	PlayitClient.tunnel_status_changed.connect(_on_playit_tunnel_status_changed)
	PlayitClient.tunnel_ready.connect(_on_playit_tunnel_ready)
	PlayitClient.tunnel_failed.connect(_on_playit_tunnel_failed)

	MobileLineEditHelper.enable_touch_as_mouse()
	MobileLineEditHelper.setup(become_owner_code_edit)
	MobileLineEditHelper.setup(connect_address_edit)
	MobileLineEditHelper.setup(connect_owner_code_edit)
	MobileLineEditHelper.setup(join_address_edit)
	MobileLineEditHelper.setup(join_password_edit, DisplayServer.KEYBOARD_TYPE_NUMBER)
	MobileLineEditHelper.enable_defocus_on_background_tap(background)

	# 【2026-09-20，見使用者需求：成為伺服器是電腦專用功能】手機（含平板）
	# 隱藏這個選項——不是技術上做不到，是實務上不適合（見對話討論：背景
	# 執行限制/行動網路不穩定/跟遊戲本身搶資源），直接不顯示避免誤按。
	# 【2026-09-20，見使用者回報「打包的 apk 沒有排除電腦專用 UI」】原本用
	# OS.has_feature("mobile") 判斷——實測發現用線材連接裝置直接從編輯器
	# 執行沒問題，但真的打包出來的 APK 卻沒被正確排除，代表這個 feature tag
	# 在不同匯出方式下的回報不夠穩定。改用 OS.get_name() 直接比對平台名稱，
	# 這是最基本、最不會受匯出設定影響的判斷方式。
	if OS.get_name() in ["Android", "iOS"]:
		become_server_button.hide()

	become_server_section.hide()
	connect_server_section.hide()
	join_remote_section.hide()
	post_login_section.hide()

	# 已經登入過（本機存有金鑰，見 PlayitClient._load_secret()）就不用
	# 每次都重新跑一次認領流程。
	if PlayitClient.is_claimed():
		_show_post_login_section()


## 見 MobileLineEditHelper.enable_touch_as_mouse() 的說明——這個畫面關閉
## 時要對稱還原。
func _exit_tree() -> void:
	MobileLineEditHelper.restore_touch_emulation()


func _on_back_pressed() -> void:
	if is_instance_valid(_room_lobby_instance):
		return
	NetworkManager.cancel()
	queue_free()


## 【2026-09-20，見使用者需求：加入遠端連線】三個模式互斥，共用同一個
## helper 決定要顯示哪一個、隱藏其餘兩個，不用像原本兩個模式各自寫一份
## show/hide，之後要再加模式也只要改這裡一個地方。
func _show_mode_section(section: VBoxContainer) -> void:
	become_server_section.visible = section == become_server_section
	connect_server_section.visible = section == connect_server_section
	join_remote_section.visible = section == join_remote_section
	status_label.text = ""


func _on_become_server_mode_pressed() -> void:
	_show_mode_section(become_server_section)


func _on_connect_server_mode_pressed() -> void:
	_show_mode_section(connect_server_section)


func _on_join_remote_mode_pressed() -> void:
	_show_mode_section(join_remote_section)


func _on_login_pressed() -> void:
	login_button.disabled = true
	PlayitClient.start_claim()


func _on_playit_claim_status_changed(text: String) -> void:
	login_status_label.text = text


func _on_playit_claimed() -> void:
	_show_post_login_section()


func _on_playit_claim_failed(reason: String) -> void:
	login_status_label.text = reason
	login_button.disabled = false


func _show_post_login_section() -> void:
	register_link_button.hide()
	login_button.hide()
	login_status_label.text = "已登入"
	logout_button.show()
	post_login_section.show()


## 【2026-09-20，見使用者需求：已登入要有登出按鈕】清掉本機存的 playit
## 金鑰，畫面退回登入前的狀態——不影響 NetworkManager 這邊已經在跑的房間
## （如果有的話），單純只是「這台電腦要換一個 playit 帳號」的入口。
func _on_logout_pressed() -> void:
	PlayitClient.logout()
	register_link_button.show()
	login_button.show()
	login_button.disabled = false
	logout_button.hide()
	login_status_label.text = ""
	post_login_section.hide()
	address_edit.text = ""


## 【2026-09-20，見使用者需求：第一次註冊的玩家需要說明】跟
## MultiplayerLobby._show_password_prompt() 同一套「疊一個 ColorRect+
## PanelContainer 上去，不用另外開場景檔」的做法——內容涵蓋這次對話裡
## 使用者實際卡關問過的幾個點（playit 的設置精靈要選哪個、確認頁面上的
## 「Agent is offline」是不是正常、瀏覽器分頁什麼時候能關），不是憑空
## 寫的通用教學。
func _on_help_pressed() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	panel.add_child(margin)

	# 外層 VBoxContainer 放「捲動內容」＋「固定在底部的關閉鈕」——關閉鈕
	# 不放進 ScrollContainer 裡面，不然內容一長，捲到下面才看得到關閉鈕。
	var outer_layout := VBoxContainer.new()
	outer_layout.add_theme_constant_override("separation", 14)
	margin.add_child(outer_layout)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	outer_layout.add_child(scroll)

	var text_layout := VBoxContainer.new()
	text_layout.add_theme_constant_override("separation", 10)
	scroll.add_child(text_layout)

	var title := Label.new()
	title.text = "第一次架設橋接站？"
	title.add_theme_font_size_override("font_size", 22)
	text_layout.add_child(title)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.text = "【登入】\n1. 到 playit.gg 免費註冊一組帳號（也可以按下方「登入」直接跳出登入頁面來註冊）。\n\n2. 註冊過程如果跳出「Where do you want to integrate Playit?」的選單，選「Your Computer」那個選項——但不用照著它走完整套安裝流程，只要確定帳號已經登入就好，這個畫面可以直接關掉。\n\n3. 按這個畫面上的「登入」，遊戲會自動開一個瀏覽器分頁，顯示「Claim Agent」畫面，按右下角「Add Agent」確認。\n\n4. 確認後可能會跳到「Agent is offline，請啟動 playit 程式」——這是正常的，不用理它。直接切回遊戲，畫面會自動偵測到你按下確認、自動完成登入，這個瀏覽器分頁這時候就可以關掉了。\n\n【建立通道】\n5. 按「開啟」或「自己開房間」——playit 對「自動建立通道」這件事有嚴格的防濫用機制（會要求真人在網頁上手動輸入確認句、不能用貼上的），所以這一步幾乎一定會跳出「建立通道失敗」，這是預期中的，不是壞掉，直接進行下一步的手動流程就好。不管成功或失敗，這一步都會讓轉發程式在背景啟動起來，這是下一步網站流程能不能跑得動的關鍵，所以不能跳過這一步直接去網站操作。\n\n6. 到 playit.gg 網站，找到你的代理人（Agent，通常顯示成「from-key-xxxx」），點進去，按「≡」（列表/設定圖示），選「New Tunnel（新隧道）」。\n\n7. 依序填寫：隧道命名（隨便打，例如遊戲名稱）→ Tunnel Type 選 UDP → Port Count 填 1 → Roblox Prohibited 按確認 → Software Description 要老實描述在跑什麼（例如「自製多人連線遊戲伺服器」，不能填 test，否則有被停用帳號的風險）→ Usage Confirmation 照畫面顯示的英文句子一字不漏手動打一遍（不能貼上）→ Public Endpoint 選 Free Network → Origin Config 的 Local IP 填 127.0.0.1、Local Port 填 8910（這是這個遊戲固定使用的連線 port，每個人都填一樣的數字）、Proxy Protocol 維持 None → 按「Create Tunnel」。\n\n8. 建立完成後，網站會顯示一組位址（例如 xxxx.tun.ply.gg:12345），回遊戲重新按一次「開啟」或「自己開房間」，這次會自動偵測到剛剛建好的這條通道、自動帶入位址，之後就不用再手動了。\n\n【連線品質】\n9. 免費帳號用的是 playit 的共用中繼站，本來就會比同 WiFi 直連多繞一手，延遲會比較高，這是免費方案架構上的限制，不是設定錯誤：房主自己連上通道大約 ping 100ms 起跳，其他人連進來大約 300ms 以上，實際數字依雙方實際地理位置、當下中繼站負載會有落差。想改善的話可以留意 playit 後台有沒有可選的中繼站/地區設定，付費方案可能提供更多或更近的中繼站，但目前沒有實測驗證能降到多低。"
	text_layout.add_child(body)

	var close_button := Button.new()
	close_button.text = "關閉"
	close_button.pressed.connect(func() -> void: overlay.queue_free())
	outer_layout.add_child(close_button)


## 【2026-09-20，見使用者需求：開啟伺服器跟自己開房間只能擇一】兩顆按鈕
## 共用同一套「建立通道→啟動轉發程式→呼叫 host_game()」流程，差別只在
## 最後 host_game() 帶的 owner_code 是不是空字串——見 _pending_owner_code_
## for_host 的說明。
## 【2026-09-20，見使用者需求：開啟後這顆鈕要能變成關閉】_dedicated_
## hosting_active 為 true 時（已經按過一次「開啟」，中繼站正在跑），再按
## 這顆鈕變成「關閉」的意思——見 _stop_dedicated_hosting() 的說明。
func _on_start_server_pressed() -> void:
	if _dedicated_hosting_active:
		_stop_dedicated_hosting()
		return
	var owner_code := become_owner_code_edit.text.strip_edges()
	if owner_code == "":
		status_label.text = "請先設定房主代碼"
		return
	_pending_owner_code_for_host = owner_code
	_begin_hosting_with_tunnel()


## 見 _on_start_server_pressed() 的說明——中繼站按「關閉」時呼叫，等同
## RoomLobby.gd 房主按「返回」的效果（cancel() 整個收掉連線/房間設定），
## 只是這裡是無人操作的中繼站模式，沒有 RoomLobby.tscn 可以按返回，改成
## 這顆鈕自己承擔同樣的角色。
func _stop_dedicated_hosting() -> void:
	NetworkManager.cancel()
	_dedicated_hosting_active = false
	start_server_button.text = "開啟\n（等待遠端房主）"
	address_edit.text = ""
	status_label.text = ""
	_set_action_buttons_disabled(false)


func _on_host_myself_pressed() -> void:
	_pending_owner_code_for_host = ""
	_begin_hosting_with_tunnel()


func _begin_hosting_with_tunnel() -> void:
	_set_action_buttons_disabled(true)
	status_label.text = ""
	PlayitClient.ensure_tunnel_and_daemon()


func _on_playit_tunnel_status_changed(text: String) -> void:
	status_label.text = text


func _on_playit_tunnel_ready(address: String, port: int) -> void:
	address_edit.text = "%s:%d" % [address, port]
	_start_room_after_tunnel()


## 【2026-09-20，見使用者回報「畫面直接跳進房間，錯誤訊息一閃就不見」】
## 原本這裡失敗會直接繼續開房，但 RoomLobby 一疊上去這則錯誤文字就被蓋住
## 了，使用者根本來不及看到失敗原因——通道建立這一步本來就是這次整合裡
## 最沒把握的一塊（見對話討論），失敗時更需要讓使用者看清楚錯誤內容才能
## 回報除錯，不能悄悄跳過。改成：顯示錯誤、把按鈕恢復可按，不自動繼續開
## 房——使用者確認錯誤內容後，可以自己選擇重試（再按一次同一顆鈕）或
## 暫時放棄遠端功能。
func _on_playit_tunnel_failed(reason: String) -> void:
	status_label.text = reason
	_set_action_buttons_disabled(false)


## 【2026-09-20，見使用者回報「成為伺服器的電腦本身不用跳出房間UI」】
## _pending_owner_code_for_host 非空（按了「開啟」）：這台電腦是無人操作
## 的中繼站，不開 RoomLobby.tscn，留在這個畫面顯示狀態就好；owner_code
## 空字串（按了「自己開房間」）：這台電腦自己就是房主，維持原本跳進
## RoomLobby.tscn 的行為，因為這種情況真的需要操作那個畫面。
##
## 【2026-09-20，見使用者回報「房間名稱不用在這裡出現，是房主決定的」】
## 這裡固定給一個預設名稱，真正的房主（不管是這台電腦自己，還是遠端認領
## 到房主身分的裝置）進了 RoomLobby.tscn 都能自己改，不需要在架站當下
## 就先決定好。
func _start_room_after_tunnel() -> void:
	if not NetworkManager.host_game("遠端房間", 2, "", "practice", _pending_owner_code_for_host):
		_set_action_buttons_disabled(false)
		return
	if _pending_owner_code_for_host == "":
		_open_room_lobby()
		return
	_dedicated_hosting_active = true
	status_label.text = "伺服器已開啟，等待遠端房主用代碼連線"
	# 見 _on_start_server_pressed() 的說明——「開啟」這顆鈕接下來要能按
	# 「關閉」把中繼站收掉，所以要重新解禁，不能繼續維持 _begin_hosting_
	# with_tunnel() 一開始整批 disable 的狀態；「自己開房間」跟兩顆模式鈕
	# 維持鎖住，避免中繼站跑著的時候又切去別的模式搞混。
	start_server_button.text = "關閉"
	start_server_button.disabled = false


## 見 _dedicated_hosting_active 的說明——只在「開啟」（無人操作的中繼站）
## 模式下才需要靠這個訊號更新狀態文字，「自己開房間」已經切去 RoomLobby.
## tscn 顯示，這裡不用管。
func _on_room_state_updated() -> void:
	if not _dedicated_hosting_active:
		return
	if NetworkManager.room_owner_peer_id != -1:
		status_label.text = "已有房主連線，房間可以開始遊戲了"
	else:
		status_label.text = "伺服器已開啟，等待遠端房主用代碼連線"


## 【2026-09-20，見使用者需求：電腦當中繼站時不該跟著進關卡】
## NetworkManager._start_match() 已經改成中繼站模式下不切場景，這裡負責
## 把畫面上的狀態文字也一併更新，讓操作電腦的人知道遊戲真的開打了，不是
## 卡住沒反應。
func _on_match_starting() -> void:
	if not _dedicated_hosting_active:
		return
	status_label.text = "遊戲進行中…"


## 【2026-09-20】位址輸入格式是「host:port」，跟 playit.gg 給的位址格式
## 一致；沒填 port 就用預設的遊戲連線 port，方便區網測試時只打 IP。這裡是
## 「連結伺服器（認領房主）」流程，送的是房主代碼，走 join_as_owner_
## candidate()——跟下面 _on_join_remote_confirm_pressed() 送房間密碼、走
## 一般 join_game() 是兩條不同的路徑，不要搞混。
func _on_connect_server_confirm_pressed() -> void:
	var address_text := connect_address_edit.text.strip_edges()
	var owner_code := connect_owner_code_edit.text.strip_edges()
	if address_text == "" or owner_code == "":
		status_label.text = "請輸入位址跟房主代碼"
		return
	var address := address_text
	var port := NetworkManager.GAME_PORT
	if address_text.contains(":"):
		var parts := address_text.split(":")
		address = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = parts[1].to_int()
	_set_action_buttons_disabled(true)
	status_label.text = "連線中…"
	if not NetworkManager.join_as_owner_candidate(address, port, owner_code):
		_set_action_buttons_disabled(false)


## 【2026-09-20，見使用者需求：其他玩家需要管道加入已經開好的房間】一般
## 玩家用的入口——不需要、也不該知道房主代碼，只需要位址跟（如果房主有
## 設的話）房間密碼，跟同 WiFi 搜尋房間點進去加入走的是同一條既有路徑
## （NetworkManager.join_game()），成功後一樣是唯讀的等候畫面，不會取得
## 房主權限。
func _on_join_remote_confirm_pressed() -> void:
	var address_text := join_address_edit.text.strip_edges()
	if address_text == "":
		status_label.text = "請輸入位址"
		return
	var password := join_password_edit.text.strip_edges()
	var address := address_text
	var port := NetworkManager.GAME_PORT
	if address_text.contains(":"):
		var parts := address_text.split(":")
		address = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = parts[1].to_int()
	_set_action_buttons_disabled(true)
	status_label.text = "連線中…"
	if not NetworkManager.join_game(address, port, password):
		_set_action_buttons_disabled(false)


func _set_action_buttons_disabled(disabled: bool) -> void:
	start_server_button.disabled = disabled
	host_myself_button.disabled = disabled
	become_server_button.disabled = disabled
	connect_server_button.disabled = disabled
	connect_confirm_button.disabled = disabled
	join_remote_button.disabled = disabled
	join_confirm_button.disabled = disabled


func _on_joined_as_client() -> void:
	_open_room_lobby()


func _on_join_rejected(reason: String) -> void:
	if is_instance_valid(_room_lobby_instance):
		return
	status_label.text = reason
	_set_action_buttons_disabled(false)


func _on_connection_failed(reason: String) -> void:
	status_label.text = reason
	_set_action_buttons_disabled(false)


func _open_room_lobby() -> void:
	if is_instance_valid(_room_lobby_instance):
		return
	_room_lobby_instance = ROOM_LOBBY_SCENE.instantiate()
	add_child(_room_lobby_instance)
	_room_lobby_instance.tree_exited.connect(_on_room_lobby_closed)


func _on_room_lobby_closed() -> void:
	_room_lobby_instance = null
	_set_action_buttons_disabled(false)
	become_server_section.hide()
	connect_server_section.hide()
	join_remote_section.hide()
	status_label.text = ""
