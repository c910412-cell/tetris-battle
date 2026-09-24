extends Node
## NetworkManager — 多人連線核心（autoload）。從 cube-combat 專案移植過來的
## 連線骨架（見該專案 docs/adr/0005：同 WiFi 直連、host 兼任伺服器，不架設
## 專用伺服器／docs/adr/0020：命中判定 host 權威、玩家移動各自客戶端權威
## 的設計慣例）。
##
## 這裡只留下跟「戰鬥/子彈/方塊」完全無關的部分：開房、用 UDP 在區網廣播
## 房間資訊、client 自動偵測並加入、房間設定/準備狀態同步、開始/結束比賽、
## RTT 量測。原版 NetworkManager.gd 另外有一大段子彈廣播/命中判定/環境方塊
## 權威交接（cube-combat 專屬），移植時刻意整段拿掉——真正要做的俄羅斯
## 方塊盤面同步（每個人自己的盤面/對手盤面預覽/攻擊行數傳遞等）還沒有
## 現成邏輯可以照抄，需要重新設計，之後就接在這個檔案（或新的
## BoardSync.gd）裡，沿用同一套「client 請求→host 驗證→host 廣播」慣例
## （可參考 update_room_settings()/start_match() 的寫法）。
##
## 開房跟搜尋房間走兩條獨立的 UDP socket，跟真正的連線（ENetMultiplayerPeer）
## 是分開的機制：廣播/搜尋只是「讓 client 找到 host 的區網位址」，找到之後
## 才用 ENet 建立真正的連線——這樣設計是因為 ENet 本身沒有「掃描區網有哪些
## 房間」的能力，只能點對點連線，找房間這一步得自己另外做。

signal rooms_updated
signal connection_failed(reason: String)
signal joined_as_client
signal match_starting
## 量到真正的 RTT（來回毫秒數）就發這個訊號——見 ping()/_ping()/_pong()的
## 說明。更新頻率/延遲相關的除錯畫面可以訂閱這個訊號直接顯示，不用憑感覺
## 猜延遲有多少。
signal ping_measured(rtt_msec: int)
## 房間設定(房名/人數上限/地圖/是否有密碼)或準備狀態改變時發出，不帶參數
## ——訂閱端（RoomLobby.gd）直接讀 NetworkManager 上對應的欄位/
## get_ready_states()，房主跟連線端共用同一份訊號、同一套讀取邏輯，不需要
## 分開維護兩套顯示。
signal room_state_updated
## client 端密碼錯誤或房間已滿被拒絕加入時發出，給 MultiplayerLobby 顯示
## 錯誤訊息、把畫面切回房間搜尋列表用。
signal room_join_rejected(reason: String)
## 房主在「房間等候」階段（還沒真的按下開始）離開/斷線時，其他還在等候
## 畫面的 client 收到——跟已經在對局場景裡才斷線（server_disconnected
## 既有的「整個回大廳」邏輯）是兩種不同情境，見 _on_server_disconnected()
## 的說明。
signal kicked_from_room(reason: String)
## 對戰中（_match_started==true）有人斷線——只有 HOST_PEER_ID 收得到
## peer_disconnected 訊號，所以這個訊號只會在真正的伺服器那台裝置上發出。
## Script/BattleMatchSync.gd 監聽這個訊號去標記 BattleParticipant.
## is_disconnected，這個檔案本身不知道 BattleDirector/BattleParticipant 是
## 什麼（見檔案開頭的說明：這裡刻意不碰任何戰鬥/方塊專屬的概念）。
signal match_peer_disconnected(peer_id: int)
## 對戰中跟 host 斷線後，這台裝置（一定是非 host 的 client）開始嘗試自動
## 重新連線——Battle.gd 收到這個可以顯示「重新連線中…」的畫面。
signal match_reconnecting
## 自動重試一次失敗了（連不上，或逾時沒收到 connected_to_server）——Battle.gd
## 收到這個可以顯示「重新連線失敗」+ 讓玩家自己按按鈕再試一次
## （retry_match_reconnect()）。
signal match_reconnect_failed
## 重新連上了（ENet 連線本身恢復，還沒認領回原本的參與者身分那一步）——
## Battle.gd 收到這個可以先把「重新連線中」畫面收掉。真正的盤面快照還原是
## Script/BattleMatchSync.gd 收到 host 送回來的資料才會做，跟這個訊號分開。
signal match_reconnected
## host 收到某個新連線帶著舊的 participant id 來認領（見
## _claim_match_reconnect()）——new_peer_id 是這個連線「現在」真正的 ENet
## peer id（跟斷線前的那個 id 不會一樣，ENet 的 peer id 是新連線自己配的,
## 沒辦法指定重用),claimed_participant_id 是它自稱斷線前是哪個參與者。這個
## 檔案只負責轉發、不驗證/不套用（要不要真的讓它認領成功是
## Script/BattleMatchSync.gd 的事，因為要查 BattleDirector 裡那個參與者是不是
## 真的處於斷線狀態，這個檔案不知道那個概念）。
signal match_reconnect_claimed(new_peer_id: int, claimed_participant_id: int)

## ENet 的伺服器永遠是 peer id 1（見 host_game() 的 create_server()）——這類
## 「只有一個人能拍板」的事情，統一認這個 id 當權威，不用另外維護一個
## 「誰是host」的狀態欄位。
const HOST_PEER_ID := 1

## 跟 cube-combat 專案的 8910/8911 錯開，避免兩個專案同時在同一個區網跑時
## 互相偵測到對方的房間廣播（GAME_PORT 只影響 ENet 連線本身能不能連上，
## 但 DISCOVERY_PORT 共用會讓兩邊的房間搜尋列表混進對方的房間資訊）。
const GAME_PORT := 8920
const DISCOVERY_PORT := 8921
const DISCOVERY_BROADCAST_ADDRESS := "255.255.255.255"
const DISCOVERY_INTERVAL_SECONDS := 1.0
## 房間資訊多久沒收到新的廣播就視為過期、從清單移除——涵蓋 host 直接關掉
## App、沒有機會送出「我離開了」通知的情況（廣播式探索天生沒有明確的「離開」
## 事件，只能用「多久沒再聽到」判斷還在不在）。
const ROOM_STALE_SECONDS := 3.0
## ENet 的 create_server() 一旦建立就不能再改 max_clients，這裡在傳輸層固定
## 開一個夠大的上限（含 host 共 MAX_SUPPORTED_PLAYERS 人），真正的人數限制
## 放在應用層擋（_submit_room_password() 收到新連線時比對 room_max_players）。
const MAX_SUPPORTED_PLAYERS := 4
## 開始比賽後大家一起切過去的對局場景。2026-09-23 起改接真正的對戰畫面
## Battle.tscn（原本指向空白佔位的 Board.tscn，只是讓連線骨架能先跑通
## 「開房→搜尋→加入→準備→開始→進場景」整條路，現在盤面同步第一階段
## 已經開始接，改指過去）。
const MATCH_SCENE_PATH := "res://Scenes/Battle.tscn"
const MULTIPLAYER_LOBBY_SCENE_PATH := "res://Scenes/MultiplayerLobby.tscn"

## 見 update_room_settings()——以下四個是房主端的權威房間設定，client 端
## 收到 _sync_room_state() 廣播後也會覆寫成同一份值方便畫面唯讀顯示，除了
## room_password：client 端從來不會被告知真正密碼字串（只會拿到
## room_has_password 這個布林值），見 _sync_room_state() 的說明。
var room_name: String = ""
var room_password: String = ""
var room_has_password: bool = false
var room_max_players: int = 2
var room_map_id: String = "practice"

## 「誰是 ENet 伺服器」跟「誰有房主權限（改設定/開始/結束比賽）」是分開的
## 兩件事：room_owner_peer_id 才是真正代表「目前誰是房主」的欄位，-1 代表
## 還沒有人認領（見 host_game() 的 owner_code 參數，支援「電腦當無頭橋接
## 站、房主身分由遠端手機認領」這個情境）。一般玩家用 MultiplayerLobby 的
## 「開房」（owner_code 留空）不受影響——host_game() 會立刻把這個欄位設成
## HOST_PEER_ID。房主權限相關的函式（update_room_settings()/start_match()/
## end_match()）一律檢查這個欄位，不是檢查「你是不是伺服器本人」。
var room_owner_peer_id: int = -1
## 房主專用代碼——電腦端 host_game() 開房時設定，遠端手機用
## join_as_owner_candidate() 送這組代碼過來認領房主身分（見
## _claim_room_owner_request() 的說明）。跟一般玩家加入房間用的
## room_password 是兩件事，職責分開。
var room_owner_code: String = ""

var is_hosting: bool = false
var is_discovering: bool = false
## 防止 _do_start_match 被重複觸發。cancel() 離開房間/回大廳時重設，下次
## 重新開房才能再次觸發。
var _match_started: bool = false
## 房主端：key＝client 的 peer_id，value＝是否已按過準備。懶生成——玩家真的
## 送出密碼驗證通過後才會被加進來（見 _submit_room_password()），不算房主
## 自己（房主不需要「準備」，見 start_match() 的開始條件判斷）。
var _peer_ready: Dictionary = {}
## 2026-09-24 新增：key＝peer_id（含房主的 HOST_PEER_ID），value＝
## {"name": String, "avatar_id": int}——PlayerProfile.gd 的名稱/頭貼是純
## 本機資料，原本完全不會被其他人看到（房間玩家列表/分隊格子/對戰對手
## 面板全部只能顯示 peer_id 這種對玩家而言毫無意義的數字）。跟
## _peer_ready 同一套「client 送、host 收、host 廣播」流程，搭
## _sync_room_state() 一起送出去，不需要另外開一條 RPC 通道。
var _peer_profiles: Dictionary = {}
## client 端：join_game() 呼叫時先記下密碼，等真的連上（connected_to_server）
## 才送出——ENet 的連線建立本身沒有內建「附帶資料」的管道，密碼驗證要在
## 連上之後另外用一個 RPC 補送，見 _on_connected_to_server() 的說明。
var _pending_join_password: String = ""
## join_as_owner_candidate() 呼叫時先記下房主代碼，等真的連上才送出——跟
## _pending_join_password 同一個理由，也同樣需要 _owner_claim_submitted
## 這個旗標擋掉 connected_to_server 訊號可能觸發兩次的問題（ENet 在手機
## 熱點/WiFi 這類環境偶爾會讓某個連線訊號對同一個對象觸發不只一次）。
var _pending_owner_code: String = ""
var _is_owner_claim_attempt: bool = false
var _owner_claim_submitted: bool = false

## 對戰中斷線重連用（見 match_reconnecting 等訊號的說明）：記住最後一次
## join_game()/join_as_owner_candidate() 用的位址/連接埠,斷線後才知道要
## 連回哪裡——不用讓玩家重新搜尋/手動輸入一次。_match_local_participant_id
## 是這台裝置本機真人玩家在 BattleSettings 分隊結果裡的 id（開賽那一刻的
## multiplayer.get_unique_id()，不會因為之後重新連線拿到新的 ENet peer id
## 而改變，靠這個認領回原本的參與者身分，見 _claim_match_reconnect()）。
var _last_join_address: String = ""
var _last_join_port: int = 0
var _match_local_participant_id: int = 0
var _is_reconnect_attempt: bool = false
var _reconnect_claim_submitted: bool = false

var _discovery_broadcast_socket: PacketPeerUDP
var _discovery_listen_socket: PacketPeerUDP
var _discovery_timer: float = 0.0
## key＝送出廣播那台裝置的來源 IP，value＝房間資訊字典（name/port/address/
## last_seen/has_password/current_players/max_players/map_id，見
## _broadcast_announcement()／_poll_discovery()）——用來源 IP 當 key 是
## 因為同一個房間的 host 每秒會重複廣播好幾次，要去重成一筆，不是每收到
## 一次封包就多一筆房間。
var _discovered_rooms: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## 開房：建立 ENet 伺服器＋開始廣播房間資訊＋記錄房間設定。max_players 是
## 「包含房主自己」的總人數上限，password 空字串代表公開房（不擋人）。
## owner_code 留空（預設，MultiplayerLobby 的「開房」一路都是這樣呼叫）：
## 開房的這個人（HOST_PEER_ID）立刻就是房主。owner_code 非空
## （RemoteConnect.gd 的「成為伺服器」呼叫）：房主身分留空不指派，等遠端
## 手機用同一組代碼呼叫 join_as_owner_candidate() 才會真的認領（見
## _claim_room_owner_request() 的說明），開房的這台電腦本身不會自動變房主
## ——這樣電腦端的 RoomLobby.tscn 會停在唯讀等候畫面，不會誤顯示成可編輯
## 設定的房主介面。
func host_game(new_room_name: String, max_players: int = 2, password: String = "", map_id: String = "practice", owner_code: String = "") -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_SUPPORTED_PLAYERS - 1)
	if err != OK:
		connection_failed.emit("無法開房（錯誤碼 %d）" % err)
		return false
	multiplayer.multiplayer_peer = peer
	room_name = new_room_name
	room_max_players = max_players
	room_password = password
	room_has_password = password != ""
	room_map_id = map_id
	room_owner_code = owner_code
	room_owner_peer_id = HOST_PEER_ID if owner_code == "" else -1
	is_hosting = true
	_peer_ready.clear()
	_peer_profiles.clear()
	_peer_profiles[HOST_PEER_ID] = {"name": PlayerProfile.player_name, "avatar_id": PlayerProfile.avatar_id}
	_start_broadcasting()
	return true


## 房主在房間等候畫面修改設定時呼叫（地圖/人數上限/密碼/房名）——立刻更新
## 本機權威資料＋重新廣播給所有已連線的 client（設定變更不會取消已經準備
## 好的 client 的準備狀態，這裡只更新設定本身，不碰 _peer_ready）。非房主
## 呼叫這個函式直接忽略，client 端的房間設定永遠是唯讀、只能等
## _sync_room_state() 廣播覆寫。
## 房主不保證就是 HOST_PEER_ID（見 room_owner_peer_id 的說明）——但真正
## 廣播出去的 _sync_room_state() 是 "authority" RPC，只有 HOST_PEER_ID 本人
## 呼叫得動（Godot 的 multiplayer authority 限制）。房主是遠端手機的話，
## 改成送一個 "any_peer" 請求給 HOST_PEER_ID 代為執行、代為廣播——跟
## start_match()/end_match() 同一套「client 請求→host 驗證執行→host 廣播」
## 慣例。
func update_room_settings(new_room_name: String, max_players: int, password: String, map_id: String) -> void:
	if multiplayer.get_unique_id() != room_owner_peer_id:
		return
	if multiplayer.get_unique_id() == HOST_PEER_ID:
		_apply_room_settings(new_room_name, max_players, password, map_id)
	else:
		_request_update_room_settings.rpc_id(HOST_PEER_ID, new_room_name, max_players, password, map_id)


@rpc("any_peer", "reliable")
func _request_update_room_settings(new_room_name: String, max_players: int, password: String, map_id: String) -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理
	if multiplayer.get_remote_sender_id() != room_owner_peer_id:
		return  # 防呆：只有目前認領到房主身分的那個人送的請求才算數
	_apply_room_settings(new_room_name, max_players, password, map_id)


func _apply_room_settings(new_room_name: String, max_players: int, password: String, map_id: String) -> void:
	room_name = new_room_name
	room_max_players = max_players
	room_password = password
	room_has_password = password != ""
	room_map_id = map_id
	_broadcast_room_state()


## client 端呼叫——切換自己的準備狀態，送給房主仲裁/記錄。房主自己不需要
## 「準備」（見 start_match() 的說明），呼叫這個函式直接忽略——房主可能是
## HOST_PEER_ID 本人，也可能是認領到房主身分的遠端手機，兩種都要擋。
func set_ready(is_ready: bool) -> void:
	if multiplayer.get_unique_id() == HOST_PEER_ID or multiplayer.get_unique_id() == room_owner_peer_id:
		return
	_set_ready.rpc_id(HOST_PEER_ID, is_ready)


@rpc("any_peer", "reliable")
func _set_ready(is_ready: bool) -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有房主才會真的受理準備狀態
	var sender_id := multiplayer.get_remote_sender_id()
	if not _peer_ready.has(sender_id):
		return  # 理論上不會發生——密碼驗證通過才會被加進 _peer_ready
	_peer_ready[sender_id] = is_ready
	_broadcast_room_state()


## 給 RoomLobby.gd 顯示玩家列表用——key＝peer_id，value＝是否已準備，不含
## 房主自己（房主的「已準備」語意由開始按鈕本身表達，不需要額外一筆）。
func get_ready_states() -> Dictionary:
	return _peer_ready.duplicate()


## 給 RoomBattleSettings.gd/TeamSelect.gd/OpponentPanel.gd 呼叫,把 peer_id
## 換成玩家自己取的名字——查不到（理論上不會發生,除非還沒收到第一次
## _sync_room_state 廣播）就退回「玩家」這個通用字。
func get_peer_profile_name(peer_id: int) -> String:
	if _peer_profiles.has(peer_id):
		return _peer_profiles[peer_id].get("name", "玩家")
	return "玩家"


func get_peer_profile_avatar_id(peer_id: int) -> int:
	if _peer_profiles.has(peer_id):
		return int(_peer_profiles[peer_id].get("avatar_id", 0))
	return 0


func _broadcast_room_state() -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return
	_sync_room_state.rpc(room_name, room_max_players, room_has_password, room_map_id, _peer_ready.duplicate(), room_owner_peer_id, _peer_profiles.duplicate())


## call_local——房主自己也走這條路徑更新，不用另外維護一份「房主本機直接
## 賦值」的重複邏輯，房主/client 的 RoomLobby.gd 收到同一個
## room_state_updated 訊號、讀同一組欄位，畫面邏輯完全共用。不廣播真正的
## 密碼字串，client 只拿得到 has_password 這個布林值。owner_peer_id：每個
## 收到端都要知道目前誰是房主，RoomLobby.gd 才能正確判斷自己是不是該顯示
## 可編輯設定的房主畫面。peer_profiles：2026-09-24 新增,見該欄位的說明。
@rpc("authority", "call_local", "reliable")
func _sync_room_state(sync_room_name: String, sync_max_players: int, has_password: bool, sync_map_id: String, ready_states: Dictionary, owner_peer_id: int, peer_profiles: Dictionary) -> void:
	room_name = sync_room_name
	room_max_players = sync_max_players
	room_has_password = has_password
	room_map_id = sync_map_id
	_peer_ready = ready_states
	room_owner_peer_id = owner_peer_id
	_peer_profiles = peer_profiles
	room_state_updated.emit()


func _start_broadcasting() -> void:
	_discovery_broadcast_socket = PacketPeerUDP.new()
	_discovery_broadcast_socket.set_broadcast_enabled(true)
	_discovery_timer = DISCOVERY_INTERVAL_SECONDS  # 立刻送出第一次，不用先等一輪間隔。


## 開始搜尋房間：綁定 UDP 監聽埠，等 _process() 逐影格收封包。
func start_discovery() -> void:
	if is_discovering:
		return
	_discovered_rooms.clear()
	_discovery_listen_socket = PacketPeerUDP.new()
	var err := _discovery_listen_socket.bind(DISCOVERY_PORT)
	if err != OK:
		connection_failed.emit("無法開始搜尋房間（錯誤碼 %d）" % err)
		return
	is_discovering = true


func stop_discovery() -> void:
	if not is_discovering:
		return
	is_discovering = false
	if _discovery_listen_socket:
		_discovery_listen_socket.close()
		_discovery_listen_socket = null
	_discovered_rooms.clear()


func _process(delta: float) -> void:
	if is_hosting:
		_discovery_timer += delta
		if _discovery_timer >= DISCOVERY_INTERVAL_SECONDS:
			_discovery_timer = 0.0
			_broadcast_announcement()
	if is_discovering:
		_poll_discovery()
		_prune_stale_rooms()


## 不只送一次全域的 255.255.255.255，在裝了 Radmin VPN／Hamachi 這類虛擬
## 網卡的機器上會出問題——作業系統路由表可能選到虛擬網卡送出去，封包只在
## 虛擬網卡自己的私有網段打轉，永遠到不了手機真正在用的 WiFi 網段。改成對
## 「每一張」網卡各自的子網路廣播位址都送一次，不只依賴單一個全域位址
## ——見 _get_subnet_broadcast_addresses() 的說明。
func _broadcast_announcement() -> void:
	if not _discovery_broadcast_socket:
		return
	# current_players 每次廣播當下重新算（1 個房主 + _peer_ready 現有筆數），
	# 不是開房那一刻的快照——玩家陸續加入/離開時，外部還在瀏覽列表的人下一
	# 次收到廣播就能看到最新人數，不用等真的點進去才發現已經滿了。
	var payload := {
		"name": room_name,
		"port": GAME_PORT,
		"has_password": room_has_password,
		"current_players": _current_player_count(),
		"max_players": room_max_players,
		"map_id": room_map_id,
	}
	var bytes := JSON.stringify(payload).to_utf8_buffer()
	for broadcast_address in _get_subnet_broadcast_addresses():
		_discovery_broadcast_socket.connect_to_host(broadcast_address, DISCOVERY_PORT)
		_discovery_broadcast_socket.put_packet(bytes)


## Godot 的 IP.get_local_interfaces() 不會回傳子網路遮罩，沒辦法精準算出
## 每張網卡真正的定向廣播位址——這裡假設最常見的家用/手機熱點 /24
## （255.255.255.0）子網路，把自己位址的最後一段換成 255。對著虛擬網卡
## （VPN）自己的網段送一份沒有副作用，反正真正的手機不會在那個網段上，
## 只是白算一次，不影響真正 WiFi 網段那份能不能送到。一張網卡都找不到時
## 退回原本的全域廣播位址當保底。
func _get_subnet_broadcast_addresses() -> Array[String]:
	var result: Array[String] = []
	for iface: Dictionary in IP.get_local_interfaces():
		var addresses: PackedStringArray = iface["addresses"]
		for address: String in addresses:
			# 127. 是 loopback；含 ":" 是 IPv6；169.254. 是 APIPA，Windows
			# 給「沒有實際連上任何網路」的介面自動配的假位址，這幾類永遠連
			# 不出去，實測會讓 connect_to_host() 噴 "Unable to connect"，
			# 雖然不影響其他真正網卡照常送出去，但每次廣播都洗一堆錯誤
			# 訊息，這裡先濾掉不必要嘗試。
			if address.begins_with("127.") or address.contains(":") or address.begins_with("169.254."):
				continue
			var parts: PackedStringArray = address.split(".")
			if parts.size() != 4:
				continue
			result.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	if result.is_empty():
		result.append(DISCOVERY_BROADCAST_ADDRESS)
	return result


func _poll_discovery() -> void:
	var updated := false
	while _discovery_listen_socket.get_available_packet_count() > 0:
		var packet := _discovery_listen_socket.get_packet()
		var sender_ip := _discovery_listen_socket.get_packet_ip()
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if parsed is Dictionary and parsed.has("name") and parsed.has("port"):
			_discovered_rooms[sender_ip] = {
				"name": parsed["name"],
				"port": parsed["port"],
				"address": sender_ip,
				"last_seen": Time.get_ticks_msec() / 1000.0,
				"has_password": parsed.get("has_password", false),
				"current_players": parsed.get("current_players", 1),
				"max_players": parsed.get("max_players", 2),
				"map_id": parsed.get("map_id", "practice"),
			}
			updated = true
	if updated:
		rooms_updated.emit()


func _prune_stale_rooms() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var stale: Array = []
	for ip in _discovered_rooms:
		if now - (_discovered_rooms[ip]["last_seen"] as float) > ROOM_STALE_SECONDS:
			stale.append(ip)
	if stale.is_empty():
		return
	for ip in stale:
		_discovered_rooms.erase(ip)
	rooms_updated.emit()


func get_discovered_rooms() -> Array:
	return _discovered_rooms.values()


## 加入房間：address/port 來自搜尋到的房間資訊（見 _poll_discovery()），
## 不是使用者手動輸入。password 是使用者在密碼輸入框打的（房間沒密碼保護
## 時傳空字串），先記下來，真的連上（_on_connected_to_server()）才送出
## ——見 _pending_join_password 的說明。
func join_game(address: String, port: int, password: String = "") -> bool:
	stop_discovery()
	_last_join_address = address
	_last_join_port = port
	_pending_join_password = password
	_password_submitted = false
	_is_owner_claim_attempt = false
	_owner_claim_submitted = false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("無法連線（錯誤碼 %d）" % err)
		return false
	multiplayer.multiplayer_peer = peer
	return true


## RemoteConnect.gd 的「連結伺服器」呼叫——address/port 是玩家手動輸入的
## （電腦端 playit 通道給的位址，這個功能不透過區網廣播/搜尋），owner_code
## 是要拿來認領房主身分的代碼，跟一般 join_game() 的房間密碼是分開的兩件
## 事（見 room_owner_code 的說明）。連上之後走
## _claim_room_owner_request() 這條 RPC，不是 _submit_room_password()。
func join_as_owner_candidate(address: String, port: int, owner_code: String) -> bool:
	stop_discovery()
	_last_join_address = address
	_last_join_port = port
	_pending_join_password = ""
	_password_submitted = false
	_pending_owner_code = owner_code
	_is_owner_claim_attempt = true
	_owner_claim_submitted = false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("無法連線（錯誤碼 %d）" % err)
		return false
	multiplayer.multiplayer_peer = peer
	return true


## 開房/搜尋房間畫面關閉時呼叫（見 MultiplayerLobby.gd）——不管當下是還在
## 搜尋、還在等人加入、還是已經連上，都乾淨收掉，回到大廳可以重新選擇。
func cancel() -> void:
	stop_discovery()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if _discovery_broadcast_socket:
		_discovery_broadcast_socket.close()
		_discovery_broadcast_socket = null
	is_hosting = false
	_match_started = false
	_peer_ready.clear()
	_peer_profiles.clear()
	_pending_join_password = ""
	_password_submitted = false
	_pending_owner_code = ""
	_is_owner_claim_attempt = false
	_owner_claim_submitted = false
	room_name = ""
	room_password = ""
	room_has_password = false
	room_max_players = 2
	room_map_id = "practice"
	room_owner_peer_id = -1
	room_owner_code = ""
	_last_join_address = ""
	_last_join_port = 0
	_match_local_participant_id = 0
	_is_reconnect_attempt = false
	_reconnect_claim_submitted = false


## 任一端斷線時呼叫。
## TODO（俄羅斯方塊盤面同步接上之後）：這裡在 cube-combat 原版會通知場景
## 清掉離線玩家的化身/子彈殘影——這個專案還沒有對戰畫面，之後接上對手盤面
## 顯示時，可能需要在這裡加一段「清掉這個 peer_id 對應的對手盤面預覽」，
## 參考做法可以看 cube-combat 的 Level.remove_remote_avatar()。
##
## 如果這個 peer 離開時還在 _peer_ready（代表還在房間等候階段、還沒真的
## 開打），一併把它從房間狀態移除＋重新廣播——讓房主/其他 client 的等候
## 畫面即時看到玩家列表少了一格，不用等下一輪 room_state_updated 才發現。
## 如果斷線的這個 peer 正好是目前認領到房主身分的那個人（電腦當無頭橋接
## 站、房主是遠端手機的情境），房主身分要跟著清空、重新開放給下一個知道
## 代碼的人認領——不然房主一斷線，沒有人能再改設定/按開始，房間會卡死。
## 只有 HOST_PEER_ID（真正的伺服器）才會執行到這裡（peer_disconnected
## 訊號本來就只有伺服器收得到其他 peer 的斷線通知），不用另外判斷。
## 2026-09-23：對戰已經開始的話（_match_started）不要跑下面這段大廳清理
## 邏輯——房間等候階段的「這格空出來、重新廣播人數」跟對戰中的「這個人的
## 盤面要暫停、等重連」是完全不同的處理方式,見 match_peer_disconnected 訊號
## 的說明。房主本人（room_owner_peer_id）此時也不清空——房主是遠端手機的
## 情境下,房主斷線一樣走「暫停等重連」,不是清空房主身分（那是等候階段才有
## 意義的概念，對局中房主斷線由 Script/BattleMatchSync.gd 決定要怎麼處理)。
func _on_peer_disconnected(peer_id: int) -> void:
	if _match_started:
		match_peer_disconnected.emit(peer_id)
		return
	var room_state_changed := false
	if _peer_ready.has(peer_id):
		_peer_ready.erase(peer_id)
		_peer_profiles.erase(peer_id)
		room_state_changed = true
	if peer_id == room_owner_peer_id:
		room_owner_peer_id = -1
		room_state_changed = true
	if room_state_changed:
		_broadcast_room_state()


## client 端：ENet 連線真的建立後，立刻送出密碼驗證（見
## _pending_join_password 的說明）——房主收到、驗證通過才會把這個 peer 加進
## _peer_ready、廣播房間狀態，在那之前這個 client 雖然在傳輸層已經連上，但
## 應用層完全不會被當成房間裡的一員。
##
## ENet 有機會讓某個連線訊號對同一個對象觸發不只一次（手機熱點/WiFi 這類
## 環境偶爾會有短暫斷線又重連的情況）——connected_to_server 一樣可能觸發
## 兩次。用一個旗標擋掉第二次：只送一次，送過就不再送，避免「已經清空的
## 密碼」被重送一次而被誤判成密碼錯誤踢掉。
var _password_submitted: bool = false

## _is_owner_claim_attempt 分辨這次連線是走一般房間密碼加入(join_game())，
## 還是拿代碼認領房主身分(join_as_owner_candidate())——兩條路徑互斥，送
## 不同的 RPC，見下面兩個 handler 各自的說明。
func _on_connected_to_server() -> void:
	joined_as_client.emit()
	if _is_reconnect_attempt:
		if _reconnect_claim_submitted:
			return
		_reconnect_claim_submitted = true
		_is_reconnect_attempt = false
		match_reconnected.emit()
		_claim_match_reconnect.rpc_id(HOST_PEER_ID, _match_local_participant_id)
		return
	if _is_owner_claim_attempt:
		if _owner_claim_submitted:
			return
		_owner_claim_submitted = true
		_claim_room_owner_request.rpc_id(HOST_PEER_ID, _pending_owner_code, PlayerProfile.player_name, PlayerProfile.avatar_id)
		return
	if _password_submitted:
		return
	_password_submitted = true
	_submit_room_password.rpc_id(HOST_PEER_ID, _pending_join_password, PlayerProfile.player_name, PlayerProfile.avatar_id)


@rpc("any_peer", "reliable")
func _submit_room_password(password: String, player_name: String, avatar_id: int) -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有房主才會真的受理密碼驗證
	var sender_id := multiplayer.get_remote_sender_id()
	# host 端也補一層防呆：這個 peer 已經驗證通過、在房間裡了，不會因為任何
	# 理由的重複送達被重新踢出去（已經在 _peer_ready 裡代表當初一定驗證
	# 通過，不用再驗一次）。
	if _peer_ready.has(sender_id):
		return
	if room_password != "" and password != room_password:
		_reject_join.rpc_id(sender_id, "密碼錯誤")
		_finish_reject_peer(sender_id)
		return
	if _current_player_count() >= room_max_players:
		_reject_join.rpc_id(sender_id, "房間已滿")
		_finish_reject_peer(sender_id)
		return
	_peer_ready[sender_id] = false
	_peer_profiles[sender_id] = {"name": player_name, "avatar_id": avatar_id}
	_broadcast_room_state()


## HOST_PEER_ID 只有在它自己就是房主時才算一個名額，純中繼站情境（房主是
## 遠端手機、電腦只是無頭橋接站）不算——否則遠端房主一連上，這台電腦就已經
## 白佔了一個名額，2 人房間會變成其他人永遠進不來。
func _current_player_count() -> int:
	var host_counts_as_player := room_owner_peer_id == HOST_PEER_ID
	return (1 if host_counts_as_player else 0) + _peer_ready.size()


## 跟 _submit_room_password() 同一套防呆邏輯（idempotent、同一個計時器延後
## 斷線讓拒絕原因先送達），差別在驗證的是 room_owner_code 不是
## room_password，成功後直接把 room_owner_peer_id 設成這個 peer，不經過
## _peer_ready（房主不用「準備」，見 set_ready() 的說明，跟一般 HOST_PEER_ID
## 房主的既有邏輯一致）。同一時間只會有一個人認領成功——room_owner_peer_id
## != -1 代表已經有人認領了，之後不管誰再送同一組代碼過來都會被拒絕。
@rpc("any_peer", "reliable")
func _claim_room_owner_request(code: String, player_name: String, avatar_id: int) -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理認領請求
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == room_owner_peer_id:
		return  # 已經是房主了（reliable RPC 有機會重複送達），不用重新處理
	if room_owner_peer_id != -1:
		_reject_join.rpc_id(sender_id, "已經有人是房主了")
		_finish_reject_peer(sender_id)
		return
	if room_owner_code == "" or code != room_owner_code:
		_reject_join.rpc_id(sender_id, "房主代碼錯誤")
		_finish_reject_peer(sender_id)
		return
	room_owner_peer_id = sender_id
	# 一般玩家加入預設 false（要按準備），房主不用準備，這裡直接給 true，
	# 順便讓 start_match() 的「大家都準備好了」判斷不會被房主自己卡住，也
	# 讓房主會正確出現在 RoomLobby.gd 的玩家列表／_broadcast_announcement()
	# 的人數統計裡。
	_peer_ready[sender_id] = true
	_peer_profiles[sender_id] = {"name": player_name, "avatar_id": avatar_id}
	_broadcast_room_state()


## 用一個很短的計時器延後真正斷線，讓上面那則 reliable RPC 有時間真的送達
## 對方（斷線本身也是非同步的網路動作，理論上 reliable RPC 已經進了送出
## 佇列，正常狀況下會比斷線指令先處理完，這裡的延遲純粹是多一層保險）。
func _finish_reject_peer(peer_id: int) -> void:
	var timer := get_tree().create_timer(0.3)
	timer.timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
	)


@rpc("authority", "reliable")
func _reject_join(reason: String) -> void:
	room_join_rejected.emit(reason)


func _on_connection_failed() -> void:
	if _is_reconnect_attempt:
		_is_reconnect_attempt = false
		multiplayer.multiplayer_peer = null
		match_reconnect_failed.emit()
		return
	connection_failed.emit("連線失敗，對方可能已離開或網路不通")
	multiplayer.multiplayer_peer = null


## 房主離開的時機點分兩種：還在房間等候階段（還沒真的按下開始，房主可能
## 只是想改設定又反悔、或單純不玩了）跟已經在對局場景（Board.tscn）裡打到
## 一半——後者維持「整個回大廳」的邏輯（真的在玩,斷線就是斷線,沒有等候
## 畫面可以退回去)；前者不用整個重載場景，只要讓 RoomLobby.gd 自己關掉、
## 退回房間搜尋列表就好（見 kicked_from_room 訊號的說明），
## MultiplayerLobby.tscn 本來就還活著在底下，不用重新生成。
## 2026-09-23：對戰中（MATCH_SCENE_PATH）斷線不再直接強制退回大廳——改成
## 嘗試自動重新連線（見 _try_match_reconnect()），留在原本的對局場景（不切
## 場景、不 cancel()，BattleDirector/BattleParticipant 這些純邏輯物件全部
## 留在記憶體裡不受影響，重連成功後 host 直接把保留的快照送回來接上就好，
## 不用重新初始化任何東西）。連不回去（見 match_reconnect_failed）才由
## Battle.gd 自己決定要不要退回大廳,這個檔案不強制。房間等候階段（還沒真的
## 開打）斷線維持原本「整個回大廳/回房間搜尋列表」的行為不變。
func _on_server_disconnected() -> void:
	var current := get_tree().current_scene
	if current and current.scene_file_path == MATCH_SCENE_PATH:
		_try_match_reconnect()
	else:
		cancel()
		kicked_from_room.emit("房主已離開房間")

## 只嘗試連線層的重試,不做自動重複迴圈——手機網路環境不穩定,自動狂重試
## 容易越幫越忙,失敗一次就交給使用者自己決定要不要用 UI 上的按鈕
## （retry_match_reconnect()）再試。這整段完全沒辦法在這個開發環境用單一個
## 編輯器實機驗證雙裝置情境,是先寫好架構、真正可靠度要等使用者拿兩台真機測。
func _try_match_reconnect() -> void:
	if _last_join_address == "":
		match_reconnect_failed.emit()
		return
	match_reconnecting.emit()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_last_join_address, _last_join_port)
	if err != OK:
		match_reconnect_failed.emit()
		return
	_is_reconnect_attempt = true
	_reconnect_claim_submitted = false
	multiplayer.multiplayer_peer = peer


## 給 Battle.gd 的「重新連線中」畫面上的按鈕呼叫——上一次自動/手動嘗試失敗後
## 再試一次。
func retry_match_reconnect() -> void:
	_try_match_reconnect()


## client 連上之後帶著斷線前的 participant id 來認領（見
## _match_local_participant_id 的說明）——這裡只轉發給
## Script/BattleMatchSync.gd（透過 match_reconnect_claimed 訊號),不驗證/
## 不套用,因為要不要真的讓它認領成功要查 BattleDirector 裡那個參與者是不是
## 真的處於斷線狀態,這個檔案不知道那個概念（見檔案開頭的說明）。
@rpc("any_peer", "reliable")
func _claim_match_reconnect(claimed_participant_id: int) -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理
	match_reconnect_claimed.emit(multiplayer.get_remote_sender_id(), claimed_participant_id)


## 2026-09-23 使用者回報：房主在 RoomBattleSettings.tscn 按下「開始」之後
## 只有房主自己看得到分隊畫面，其他人卡在原地——原因是那顆按鈕
## （RoomBattleSettings._on_next_pressed()）原本只是本機自己
## change_scene_to_file("TeamSelect.tscn")，沒有透過網路通知其他人一起切
## 過去，一直是純本機動作，沒人做過。跟 start_match()/end_match() 同一套
## 「client 請求→host 驗證→host 廣播」慣例，這裡補上，讓房主按下去時大家
## 一起切到分隊畫面（真正開始比賽仍然是分隊完成後另外呼叫 start_match()，
## 這裡只負責這一個中間步驟）。
func advance_to_team_select() -> void:
	if multiplayer.get_unique_id() != room_owner_peer_id:
		return
	if multiplayer.get_unique_id() == HOST_PEER_ID:
		_do_advance_to_team_select()
	else:
		_request_advance_to_team_select.rpc_id(HOST_PEER_ID)


@rpc("any_peer", "reliable")
func _request_advance_to_team_select() -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理
	if multiplayer.get_remote_sender_id() != room_owner_peer_id:
		return  # 防呆：只有目前認領到房主身分的那個人送的請求才算數
	_do_advance_to_team_select()


func _do_advance_to_team_select() -> void:
	# 2026-09-23 使用者需求：分隊畫面要跟房間設定畫面同一套「加入方按準備、
	# 房主按開始」——_peer_ready 這份狀態在房間設定階段已經被大家按過一輪
	# 「準備」（不然房主的開始鈕不會亮），進分隊畫面前先整批重設回 false,
	# 逼大家在分隊畫面重新按一次準備（分好隊之後才按,不是延用舊的準備
	# 狀態），不然大家一進來就會直接顯示「已準備」，分隊畫面的準備機制形同
	# 虛設。
	for peer_id in _peer_ready:
		_peer_ready[peer_id] = false
	_broadcast_room_state()
	_advance_to_team_select.rpc()


## call_local——房主自己也走這條路徑切場景，不用另外維護一份重複邏輯。
@rpc("authority", "call_local", "reliable")
func _advance_to_team_select() -> void:
	get_tree().change_scene_to_file("res://Scenes/TeamSelect.tscn")


## 2026-09-23 使用者需求：分隊畫面的「返回」應該只有房主能按，而且要帶大家
## 一起回到房間設定畫面（原本 TeamSelect.gd 的返回鈕是純本機動作，誰都能按、
## 也只有自己切場景,其他人卡在分隊畫面看不到房主在調設定）——跟
## advance_to_team_select() 反方向的同一套「client 請求→host 驗證→host
## 廣播」慣例。多人的房間設定畫面（RoomBattleSettings.tscn）本來就是疊在
## MultiplayerLobby.tscn 上面的 overlay（不是獨立場景,見該檔案開頭的說明),
## 這裡跟 _end_match() 一樣切回 MULTIPLAYER_LOBBY_SCENE_PATH,
## MultiplayerLobby.gd._ready() 偵測到連線還在會自動重新疊出房間設定畫面,
## 不用在這裡自己處理 overlay 生成。
func return_to_room_settings() -> void:
	if multiplayer.get_unique_id() != room_owner_peer_id:
		return
	if multiplayer.get_unique_id() == HOST_PEER_ID:
		_do_return_to_room_settings()
	else:
		_request_return_to_room_settings.rpc_id(HOST_PEER_ID)


@rpc("any_peer", "reliable")
func _request_return_to_room_settings() -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理
	if multiplayer.get_remote_sender_id() != room_owner_peer_id:
		return  # 防呆：只有目前認領到房主身分的那個人送的請求才算數
	_do_return_to_room_settings()


func _do_return_to_room_settings() -> void:
	# 分隊結果不用清（跟 _do_advance_to_team_select() 進來時一樣,可能只是
	# 房主想回去看一下設定,不代表要放棄目前分好的隊)——真的要重新分隊時,
	# RoomBattleSettings._on_next_pressed() 再按下一步會自己清一次
	# （push_reset_team_assignments()）。準備狀態要重置,回到房間設定畫面
	# 邏輯上是全新一輪「大家重新準備」的起點。
	for peer_id in _peer_ready:
		_peer_ready[peer_id] = false
	_broadcast_room_state()
	_return_to_room_settings.rpc()


## call_local——房主自己也走這條路徑切場景，不用另外維護一份重複邏輯。
@rpc("authority", "call_local", "reliable")
func _return_to_room_settings() -> void:
	get_tree().change_scene_to_file(MULTIPLAYER_LOBBY_SCENE_PATH)


## 房主在房間等候畫面按下「開始」時呼叫（見 RoomLobby.gd）。單人房間
## （room_max_players 剛好等於目前總人數 1）不需要等任何人準備，房主自己
## 按下就能進——這裡用「目前有沒有其他人在房間裡」判斷，不是看
## room_max_players 的數字本身（房主可能把上限設 2 但還沒有人加入，這時
## 房主一樣可以直接開始，不用因為「上限是 2」就誤判成需要等人）。
## 房主不保證是 HOST_PEER_ID 本人（見 room_owner_peer_id 的說明),但真正
## 觸發全體切場景的 _start_match() 是 "authority" RPC,只有 HOST_PEER_ID
## 本人呼叫得動——房主是遠端手機時改成送請求給 HOST_PEER_ID 代為檢查/代為
## 廣播,跟 update_room_settings() 同一套 relay 慣例。
func start_match() -> void:
	if multiplayer.get_unique_id() != room_owner_peer_id:
		return
	if multiplayer.get_unique_id() == HOST_PEER_ID:
		_do_start_match()
	else:
		_request_start_match.rpc_id(HOST_PEER_ID)


@rpc("any_peer", "reliable")
func _request_start_match() -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理
	if multiplayer.get_remote_sender_id() != room_owner_peer_id:
		return  # 防呆：只有目前認領到房主身分的那個人送的請求才算數
	_do_start_match()


func _do_start_match() -> void:
	if _match_started:
		return
	for ready in _peer_ready.values():
		if not ready:
			return  # 還有人沒準備好，擋掉
	_match_started = true
	# 2026-09-23：房主在這裡產生這一場比賽共用的隨機種子，隨著開始比賽一起
	# 廣播出去（BattleSettings.network_match_seed，BattleDirector._init() 拿
	# 這個取代各自本地 randi()），確保 random_piece_per_player 關閉時大家重建
	# 出同一份 7-bag 出塊順序。bo-N 之後每一輪要不要重新配種、輪間怎麼讓大家
	# 一起切下一輪，屬於第二階段（拆分模擬架構）要解決的範圍，這裡先只處理
	# 「開賽第一輪」。
	var match_seed := randi()
	if match_seed == 0:
		match_seed = 1
	_start_match.rpc(match_seed)


## 房主在對局場景（Board.tscn）裡按下「返回」時呼叫，取代「整個 cancel()
## 斷線回主選單」的行為——房間本身（伺服器連線/房間設定）保留，只是帶所有
## 人一起退回房間等候畫面，房主可以直接開下一局，其他人不用重新搜尋加入。
## 非房主按同一顆鈕維持原本「真的離開」的行為，這裡不處理那個情境。
## 跟 start_match() 同一個理由——房主不保證是 HOST_PEER_ID 本人，這裡真正
## 動手的部分（_do_end_match()）只有 HOST_PEER_ID 呼叫得動（要重開廣播
## socket、要呼叫 "authority" 的 _end_match RPC），房主是遠端手機時改成
## 送請求代為執行。
func end_match() -> void:
	if multiplayer.get_unique_id() != room_owner_peer_id:
		return
	if multiplayer.get_unique_id() == HOST_PEER_ID:
		_do_end_match()
	else:
		_request_end_match.rpc_id(HOST_PEER_ID)


@rpc("any_peer", "reliable")
func _request_end_match() -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理
	if multiplayer.get_remote_sender_id() != room_owner_peer_id:
		return  # 防呆：只有目前認領到房主身分的那個人送的請求才算數
	_do_end_match()


func _do_end_match() -> void:
	if not _match_started:
		return
	_match_started = false
	BattleSettings.network_match_seed = 0
	# 2026-09-23 使用者回報：對戰中途斷線、沒有重連回來的人（見
	# match_peer_disconnected 的說明：對戰中斷線刻意不清 _peer_ready,是為了
	# 讓他有機會重連回同一場對局)一旦這場對局真的結束了,如果他們沒有回來,
	# 早就不是真正還連著的人了——原本這裡只是把所有值重設成 false,不會清掉
	# 任何 key,這些人會永遠卡在房間人數/玩家列表裡占位置,即使他已經關掉
	# 遊戲。用 multiplayer.get_peers()（目前真的還連著的 ENet peer id)過濾,
	# 不在裡面的一律移除。
	var live_peers := multiplayer.get_peers()
	for peer_id in _peer_ready.keys():
		if not live_peers.has(peer_id):
			_peer_ready.erase(peer_id)
			_peer_profiles.erase(peer_id)
		else:
			_peer_ready[peer_id] = false
	_broadcast_room_state()
	# 開始比賽時關掉了廣播 socket，這裡要重新打開，房間才會再次出現在其他
	# 人的搜尋列表裡（「房間再次開放」）。
	if not _discovery_broadcast_socket:
		_start_broadcasting()
	_end_match.rpc()


## call_local——房主自己也走這條路徑切場景，不用另外維護一份重複邏輯。
## 切回 MultiplayerLobby.tscn（不是 Lobby.tscn 主選單）：見該檔案 _ready()
## 的說明，偵測到 multiplayer.multiplayer_peer 還在（連線沒斷）會自動重新
## 開啟 RoomLobby.tscn，玩家因此直接落地在房間等候畫面，不用手動重新開房
## /搜尋加入。
@rpc("authority", "call_local", "reliable")
func _end_match() -> void:
	get_tree().change_scene_to_file(MULTIPLAYER_LOBBY_SCENE_PATH)


## 廣播給所有人（含自己，call_local）：一起進對局場景。雙方各自獨立呼叫
## change_scene_to_file 開自己那份 Board.tscn。房主是遠端裝置、這台電腦
## 純粹是無人操作的中繼站時（room_owner_peer_id 不是 HOST_PEER_ID 本人），
## 直接不切場景——留在 RemoteConnect.gd 那個畫面，不生成/操作自己的畫面。
## 電腦自己就是房主（「自己開房間」流程）時維持原本既有行為，正常進場景。
@rpc("authority", "call_local", "reliable")
func _start_match(match_seed: int) -> void:
	BattleSettings.network_match_seed = match_seed
	## 記住這一刻的 peer id 當作「這台裝置本機真人玩家的參與者身分」——見
	## _match_local_participant_id 的說明，之後真的斷線重連時要拿這個去
	## 認領，不能用重連當下的 multiplayer.get_unique_id()（那時候已經是
	## 全新連線配的新 id 了）。
	_match_local_participant_id = multiplayer.get_unique_id()
	if multiplayer.get_unique_id() == HOST_PEER_ID and room_owner_peer_id != HOST_PEER_ID:
		match_starting.emit()
		if _discovery_broadcast_socket:
			_discovery_broadcast_socket.close()
			_discovery_broadcast_socket = null
		return
	# 防呆：reliable RPC 本身在網路層有機會被重複送達，這裡收到端再擋一次
	# ——已經在 Board.tscn（或正在切換過去的半途）就不要再切一次。
	var current := get_tree().current_scene
	if current and current.scene_file_path == MATCH_SCENE_PATH:
		return
	match_starting.emit()
	if _discovery_broadcast_socket:
		_discovery_broadcast_socket.close()
		_discovery_broadcast_socket = null
	get_tree().change_scene_to_file(MATCH_SCENE_PATH)


## 量測真正的網路來回時間（RTT）——不用猜，直接量。client 送出當下的本機
## 時間戳，host 收到立刻原封不動送回去，client 收到後用「現在的本機時間」
## 減掉「送出時的時間戳」，得到這一趟真正花了多少毫秒。用 unreliable（不是
## unreliable_ordered）——量測 RTT 只在乎「這一趟」單獨花多久，不需要保證
## 送達順序，也不需要 reliable 的重送機制介入影響量到的數字（reliable 遺失
## 重送會讓量到的時間包含重試等待，失真）。host 自己呼叫沒有意義（RTT 應該
## 是 0），呼叫端自己判斷要不要跳過，這裡不重複判斷。
##
## 對戰盤面同步做好之後，這個訊號量到的 RTT 也可以拿來動態調整「盤面狀態
## 廣播多久送一次」這類更新頻率參數，不用寫死一個數字。
func ping(local_send_time_msec: int) -> void:
	_ping.rpc_id(HOST_PEER_ID, local_send_time_msec, multiplayer.get_unique_id())


@rpc("any_peer", "unreliable")
func _ping(send_time_msec: int, sender_id: int) -> void:
	if multiplayer.get_unique_id() != HOST_PEER_ID:
		return  # 防呆：只有 host 才會真的回應（本來就只該送給 host，見呼叫端）
	_pong.rpc_id(sender_id, send_time_msec)


@rpc("authority", "unreliable")
func _pong(send_time_msec: int) -> void:
	var rtt_msec := Time.get_ticks_msec() - send_time_msec
	ping_measured.emit(rtt_msec)
