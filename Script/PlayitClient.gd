extends Node
## PlayitClient（autoload）— 把 playit.gg 的帳號認領／建立 UDP 通道／啟動
## 轉發用的 playitd 常駐程式整套包進遊戲裡，見 RemoteConnect.gd「成為
## 伺服器」畫面的說明。
##
## 【2026-09-20，重要警告】這裡呼叫的 /tunnels/create、/tunnels/list 是從
## playit-agent 官方原始碼（github.com/playit-cloud/playit-agent，
## packages/api_client/src/api.rs 的 ReqTunnelsCreate/AccountTunnel 等
## struct 定義）反推出來的 REST API——playit 官方沒有公開文件，這兩支 API
## 的請求/回應格式沒有機會用真實帳號實際打過，只做到「跟原始碼的 serde
## 定義比對過欄位名稱/巢狀結構」這個程度的把握，不保證第一次呼叫就成功。
## 認領流程（/claim/setup、/claim/exchange，格式已對照 packages/playit-cli/
## src/main.rs 的 claim_exchange() 函式）跟啟動 playitd（下載到的
## playit-windows-x86_64.exe 已經實際下載下來跑過 --help 確認過參數，
## 見對話討論）這兩塊把握高很多。任何一步失敗都會透過 tunnel_failed/
## claim_failed 訊號給出清楚的錯誤訊息並保留手動退路——使用者永遠可以
## 自己到 playit.gg 網站後台手動建一次通道，把位址貼到「連結伺服器」畫面，
## 不依賴這裡的自動化。

signal claim_status_changed(text: String)
signal claimed()
signal claim_failed(reason: String)
signal tunnel_status_changed(text: String)
signal tunnel_ready(address: String, port: int)
signal tunnel_failed(reason: String)

const API_BASE := "https://api.playit.gg"
const SECRET_FILE_PATH := "user://playit_secret.txt"
const DAEMON_EXE_PATH := "user://playitd.exe"
## 見對話討論——這個確切的檔名已經實際下載下來、用 --help 跑過確認是
## 沒有 Windows 服務安裝流程的純前景常駐程式（跟 packages/playitd/src/
## bin/playitd.rs 的 --secret/--secret-path/--socket-path 參數完全對得
## 上），目前只做 Windows 版，其他平台之後有需要再另外處理。
const DAEMON_DOWNLOAD_URL := "https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-windows-x86_64.exe"
## 跟 NetworkManager.GAME_PORT 一致（見該檔案——跟 cube-combat 的 8910 錯開）。
const LOCAL_TUNNEL_PORT := 8920
const POLL_INTERVAL_SECONDS := 2.0
const MAX_ALLOCATION_POLL_ATTEMPTS := 20

var secret_key: String = ""
var tunnel_address: String = ""
var tunnel_port: int = 0

var _claim_code: String = ""
var _claim_polling: bool = false
var _daemon_pid: int = -1


func _ready() -> void:
	_load_secret()


func _exit_tree() -> void:
	stop_daemon()


func is_claimed() -> bool:
	return secret_key != ""


func has_tunnel() -> bool:
	return tunnel_address != "" and tunnel_port != 0


func _load_secret() -> void:
	if not FileAccess.file_exists(SECRET_FILE_PATH):
		return
	var file := FileAccess.open(SECRET_FILE_PATH, FileAccess.READ)
	if file:
		secret_key = file.get_as_text().strip_edges()
		file.close()


func _save_secret() -> void:
	var file := FileAccess.open(SECRET_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(secret_key)
		file.close()


## 【2026-09-20，見使用者需求：已登入畫面要有登出按鈕】清掉本機存的金鑰＋
## 通道資訊＋停掉轉發常駐程式，下次要用就得重新跑一次認領流程——用在
## 「這台電腦要換一個 playit 帳號」或「金鑰壞掉想重新來一次」這類情境。
func logout() -> void:
	stop_daemon()
	secret_key = ""
	tunnel_address = ""
	tunnel_port = 0
	if FileAccess.file_exists(SECRET_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SECRET_FILE_PATH))


## 開始認領流程——產生一組認領碼、組成網址、用系統瀏覽器打開，背景輪詢
## 直到使用者在瀏覽器按下確認。已經認領過（本機存有 secret_key）就直接
## 當作完成，不用重新跑一次。
func start_claim() -> void:
	if is_claimed():
		claimed.emit()
		return
	_claim_code = _generate_claim_code()
	var claim_url := "https://playit.gg/claim/%s" % _claim_code
	OS.shell_open(claim_url)
	claim_status_changed.emit("已開啟瀏覽器，請在裡面完成登入/確認…")
	_claim_polling = true
	_claim_setup_tick()


func _generate_claim_code() -> String:
	var bytes := PackedByteArray()
	for i in 5:
		bytes.append(randi() % 256)
	return bytes.hex_encode()


func _claim_setup_tick() -> void:
	if not _claim_polling:
		return
	var payload := {
		"code": _claim_code,
		# 見 packages/api_client/src/api.rs 的 ClaimAgentType——rename 是
		# "self-managed"（連字號，不是底線），這裡照原始碼定義的字串送出。
		"agent_type": "self-managed",
		"version": "tetris-battle-embedded",
	}
	_post(API_BASE + "/claim/setup", payload, _on_claim_setup_response)


func _on_claim_setup_response(ok: bool, status: String, data: Variant) -> void:
	if not _claim_polling:
		return  # 使用者可能已經取消/離開畫面，見 cancel_claim()
	if not ok:
		claim_status_changed.emit("查詢中…（%s）" % status)
		await get_tree().create_timer(POLL_INTERVAL_SECONDS).timeout
		_claim_setup_tick()
		return
	# 見 ClaimSetupResponse 的說明——這是一個沒有附加資料的字串列舉，
	# data 欄位就是純字串本身，不是物件。
	var response_str := str(data)
	match response_str:
		"UserAccepted":
			_claim_polling = false
			_exchange_claim()
		"UserRejected":
			_claim_polling = false
			claim_failed.emit("認領被拒絕，請重新嘗試")
		_:
			claim_status_changed.emit("等待瀏覽器確認…")
			await get_tree().create_timer(POLL_INTERVAL_SECONDS).timeout
			_claim_setup_tick()


func cancel_claim() -> void:
	_claim_polling = false


func _exchange_claim() -> void:
	_post(API_BASE + "/claim/exchange", {"code": _claim_code}, _on_claim_exchange_response)


func _on_claim_exchange_response(ok: bool, status: String, data: Variant) -> void:
	if not ok:
		claim_failed.emit("認領交換失敗（%s）" % status)
		return
	var key := ""
	if data is Dictionary:
		key = str((data as Dictionary).get("secret_key", ""))
	if key == "":
		claim_failed.emit("認領交換回應沒有金鑰")
		return
	secret_key = key
	_save_secret()
	claimed.emit()


## 建立/取得通道，並啟動本機的 playitd 轉發常駐程式——尚未登入直接失敗，
## 不會呼叫端誤以為在跑。
## 【2026-09-20，見使用者實測回報「建立通道失敗 InvalidAgentId」】這裡
## 整段重寫過——原本猜 origin 用 "default" 類型可以讓伺服器自動指派給呼叫
## 端自己的 agent，實測發現不對："default" 其實是專門給 AgentType::Default
## 這種特殊帳號類型用的，不是「自動指派給目前這個 agent」的意思，我們的
## agent 是認領流程建立的 "self-managed" 類型，要改用 "agent" 這個 origin
## 類型、明確帶上自己的 agent_id 才行——agent_id 從 /agents/rundata 這支
## API 查（見 packages/api_client/src/api.rs 的 AgentRunData.agent_id，
## 這支 API 不用帶任何參數，只靠 Authorization header 就知道是在問哪個
## agent）。這支 API 同時回傳 tunnels 陣列，也一併拿來判斷「這個 agent
## 是不是已經有指向 8910 的通道了」，不用再另外呼叫 /tunnels/list。
var _agent_id: String = ""


func ensure_tunnel_and_daemon() -> void:
	if not is_claimed():
		tunnel_failed.emit("尚未登入")
		return
	if has_tunnel():
		_start_daemon()
		return
	tunnel_status_changed.emit("查詢代理人資訊…")
	_post_authed("/agents/rundata", {}, _on_rundata_response)


func _on_rundata_response(ok: bool, status: String, data: Variant) -> void:
	if not ok:
		tunnel_failed.emit("查詢代理人資訊失敗（%s）——可以改用手動流程：自己到 playit.gg 網站後台建一次 UDP 通道指向 localhost:%d，再把位址貼到「連結伺服器」畫面" % [status, LOCAL_TUNNEL_PORT])
		return
	var rundata: Dictionary = data if data is Dictionary else {}
	_agent_id = str(rundata.get("agent_id", ""))
	if _agent_id == "":
		tunnel_failed.emit("查詢代理人資訊回應沒有 agent_id")
		return
	# 見 AgentTunnel 的說明——已經配置好（不是還在 pending）的通道才會出現
	# 在這個陣列裡，有直接可用的 assigned_domain/port，不用另外再查一次
	# 配置狀態。
	var tunnels: Array = rundata.get("tunnels", [])
	for tunnel in tunnels:
		if not (tunnel is Dictionary):
			continue
		var entry: Dictionary = tunnel
		if int(entry.get("local_port", -1)) != LOCAL_TUNNEL_PORT:
			continue
		var domain := str(entry.get("assigned_domain", ""))
		var port_range: Dictionary = entry.get("port", {})
		var port := int(port_range.get("from", 0))
		if domain != "" and port != 0:
			tunnel_address = domain
			tunnel_port = port
			_start_daemon()
			return
	_create_tunnel()


func _create_tunnel() -> void:
	tunnel_status_changed.emit("建立通道中…")
	# 見 packages/api_client/src/api.rs 的 ReqTunnelsCreate／TunnelOriginCreate
	# ——改用 "agent" 這個 origin 類型＋明確帶上 _agent_id（見上方的更正
	# 說明）。alloc 留 null 讓 playit 自動配置，不用先查可用的配置區域/UUID。
	# 【2026-09-20，見使用者實測回報「TunnelTypeRequiresDescription」】這個
	# 錯誤字串沒有出現在 packages/api_client/src/api.rs 已知的錯誤列舉裡
	# （官方伺服器的驗證邏輯比這個開源 client repo 新），只能從字面猜——
	# 猜測是「沒有選預先定義的遊戲類型（tunnel_type 留 null）時，name 這
	# 欄位要當成說明文字，不能是太短的代稱」，先試著把 name 換成完整一點
	# 的描述句，不行的話再依實測結果調整。
	var payload := {
		"name": "俄羅斯方塊對戰 遊戲房間橋接通道",
		# 【2026-09-20，見使用者實際跑一次網站上的手動建立通道流程】網站在
		# 這一步的欄位標籤明確寫「Software Description」（要求誠實描述在
		# 跑什麼軟體，不能填 test，否則有被停用/封鎖帳號的風險，見網站上
		# 的警語）——這是比之前 "description" 更精確的線索，改用
		# "software_description" 這個更貼近欄位標籤命名習慣的鍵名再試一次。
		"software_description": "Tetris Battle multiplayer game server",
		"tunnel_type": null,
		"port_type": "udp",
		"port_count": 1,
		"origin": {
			"type": "agent",
			"data": {"agent_id": _agent_id, "local_ip": "127.0.0.1", "local_port": LOCAL_TUNNEL_PORT},
		},
		"enabled": true,
		"alloc": null,
		"firewall_id": null,
		"proxy_protocol": null,
	}
	_post_authed("/tunnels/create", payload, _on_tunnel_create_response)


func _on_tunnel_create_response(ok: bool, status: String, data: Variant) -> void:
	if not ok:
		tunnel_failed.emit("建立通道失敗（%s）——可以改用手動流程：自己到 playit.gg 網站後台建一次 UDP 通道指向 localhost:%d，再把位址貼到「連結伺服器」畫面" % [status, LOCAL_TUNNEL_PORT])
		# 【2026-09-20，見使用者實測回報「其他人也要手動啟動 exe 嗎」】自動
		# 建立通道失敗時，原本這裡就直接結束，代理人程式完全沒有機會被啟動
		# ——但 playit 網站「新增通道」那頁的 Origin Config 區塊要等代理人
		# 真的連線上才會讀取完成（見對話討論的實測結果），如果沒有人手動
		# 用指令列先啟動代理人程式，使用者自己走手動流程也會卡在同一個地方
		# 出不去。這裡改成：自動建立雖然失敗，還是把代理人程式帶上線（不會
		# 顯示 tunnel_ready，因為還沒有真正的通道位址），讓使用者自己走
		# 手動流程時，網站那邊已經看得到代理人在線，不需要另外找人幫忙下
		# 指令。
		_ensure_daemon_online(func() -> void: pass)
		return
	var tunnel_id := str((data as Dictionary).get("id", "")) if data is Dictionary else ""
	if tunnel_id == "":
		tunnel_failed.emit("建立通道回應沒有 id")
		return
	_poll_allocation(tunnel_id)


## 剛建立的通道要等 playit 那邊真的配置好位址才會出現在 /agents/rundata
## 的 tunnels 陣列裡（配置完成前會先出現在 pending 陣列），這裡定期重新
## 查詢直到出現或超過重試次數。
func _poll_allocation(tunnel_id: String, attempts_left: int = MAX_ALLOCATION_POLL_ATTEMPTS) -> void:
	if attempts_left <= 0:
		tunnel_failed.emit("通道一直沒有配置到位址，請改用手動流程")
		return
	_post_authed("/agents/rundata", {}, func(ok: bool, status: String, data: Variant) -> void:
		if not ok:
			await get_tree().create_timer(POLL_INTERVAL_SECONDS).timeout
			_poll_allocation(tunnel_id, attempts_left - 1)
			return
		var rundata: Dictionary = data if data is Dictionary else {}
		var tunnels: Array = rundata.get("tunnels", [])
		for tunnel in tunnels:
			if not (tunnel is Dictionary):
				continue
			var entry: Dictionary = tunnel
			if str(entry.get("id", "")) != tunnel_id:
				continue
			var domain := str(entry.get("assigned_domain", ""))
			var port_range: Dictionary = entry.get("port", {})
			var port := int(port_range.get("from", 0))
			if domain == "" or port == 0:
				break
			tunnel_address = domain
			tunnel_port = port
			_start_daemon()
			return
		tunnel_status_changed.emit("等待配置位址…")
		await get_tree().create_timer(POLL_INTERVAL_SECONDS).timeout
		_poll_allocation(tunnel_id, attempts_left - 1)
	)


func _start_daemon() -> void:
	_ensure_daemon_online(func() -> void: tunnel_ready.emit(tunnel_address, tunnel_port))


## 見 _on_tunnel_create_response() 的說明——這裡拆成獨立函式，讓「自動
## 建立通道失敗，但還是要讓代理人上線方便使用者自己走手動流程」跟「自動
## 建立成功，上線後要真的觸發 tunnel_ready」共用同一套下載/啟動邏輯，
## 差別只在完成後要不要送出 tunnel_ready 訊號（用 on_ready callback 決定）。
func _ensure_daemon_online(on_ready: Callable) -> void:
	if _daemon_pid != -1 and OS.is_process_running(_daemon_pid):
		on_ready.call()
		return
	tunnel_status_changed.emit("啟動轉發程式…")
	if not FileAccess.file_exists(DAEMON_EXE_PATH):
		_download_daemon(on_ready)
		return
	_launch_daemon(on_ready)


func _download_daemon(on_ready: Callable) -> void:
	tunnel_status_changed.emit("下載轉發程式…")
	var request := HTTPRequest.new()
	add_child(request)
	request.download_file = ProjectSettings.globalize_path(DAEMON_EXE_PATH)
	request.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		request.queue_free()
		if response_code != 200:
			tunnel_failed.emit("下載轉發程式失敗（狀態碼 %d）" % response_code)
			return
		_launch_daemon(on_ready)
	)
	var err := request.request(DAEMON_DOWNLOAD_URL)
	if err != OK:
		request.queue_free()
		tunnel_failed.emit("下載轉發程式失敗（錯誤碼 %d）" % err)


func _launch_daemon(on_ready: Callable) -> void:
	var exe_path := ProjectSettings.globalize_path(DAEMON_EXE_PATH)
	var pid := OS.create_process(exe_path, ["--secret", secret_key])
	if pid == -1:
		tunnel_failed.emit("啟動轉發程式失敗")
		return
	_daemon_pid = pid
	on_ready.call()


func stop_daemon() -> void:
	if _daemon_pid != -1:
		if OS.is_process_running(_daemon_pid):
			OS.kill(_daemon_pid)
		_daemon_pid = -1


## 共用的 POST 請求 helper（不帶認證）——見 _post_authed() 帶認證的版本。
## callback 簽名：(ok: bool, status: String, data: Variant)，ok 代表
## HTTP 200 且 status=="success"；status 失敗時是錯誤描述字串，data 是
## 回應內的 data 欄位（見 ApiResult 的 status/data 包裝格式）。
func _post(url: String, payload: Dictionary, callback: Callable) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		_handle_response(response_code, body, callback)
	)
	var err := request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request.queue_free()
		callback.call(false, "網路請求失敗（錯誤碼 %d）" % err, null)


func _post_authed(path: String, payload: Dictionary, callback: Callable) -> void:
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		_handle_response(response_code, body, callback)
	)
	# 見 packages/api_client/src/lib.rs 的認證格式——"Agent-Key <secret>"。
	var headers := ["Content-Type: application/json", "Authorization: Agent-Key %s" % secret_key]
	var err := request.request(API_BASE + path, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request.queue_free()
		callback.call(false, "網路請求失敗（錯誤碼 %d）" % err, null)


func _handle_response(response_code: int, body: PackedByteArray, callback: Callable) -> void:
	if response_code == 429:
		callback.call(false, "請求太頻繁，稍後再試", null)
		return
	if response_code != 200:
		# 【2026-09-20，見使用者回報「HTTP 400」】原本這裡只回傳狀態碼，看
		# 不出伺服器實際拒絕的原因——這支 API 沒有公開文件（見 PlayitClient.gd
		# 開頭的警告），出錯時body 內容是唯一能拿來對照、修正請求格式的線索，
		# 一併帶出來，不要只顯示數字。
		var body_text := body.get_string_from_utf8()
		callback.call(false, "HTTP %d: %s" % [response_code, body_text] if body_text != "" else "HTTP %d" % response_code, null)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		callback.call(false, "回應格式異常", null)
		return
	var envelope: Dictionary = parsed
	# 見 ApiResult 的說明——{"status":"success"/"fail"/"error","data":...}。
	if str(envelope.get("status", "")) != "success":
		callback.call(false, JSON.stringify(envelope.get("data", envelope)), null)
		return
	callback.call(true, "", envelope.get("data"))
