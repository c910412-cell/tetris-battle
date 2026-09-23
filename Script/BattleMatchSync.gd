## 對戰對戰中（Battle.tscn）的網路同步層——2026-09-23 連線對戰第二階段。
## BattleDirector.gd 刻意不直接依賴 NetworkManager/multiplayer（保持純邏輯、
## 離線也能單獨測試），所有真正的 RPC 收送、host 驗證、廣播都集中在這個
## 檔案，透過 BattleDirector 的一組訊號溝通（見該檔案開頭的訊號說明）。
##
## 這個檔案是一個 Node（不是 RefCounted）——Godot 的 @rpc 高階多人 API
## 只能定義在場景樹裡的 Node 上，且同一個節點在每台裝置上的「路徑」要一致
## 才能正確定址。Battle.gd 在 _ready() 用固定的名字動態 add_child() 這個
## 節點（不是寫在 Battle.tscn 裡的靜態節點——這樣完全不用碰使用者手動排版
## 過的場景檔，零風險），每台裝置都在同一個時間點、同一個父節點下加同名
## 節點，路徑自然一致。
##
## 每一輪（bo-N）Battle.gd 都會建立一個新的 BattleDirector，呼叫
## bind_director() 重新綁定訊號——這個節點本身跨輪次持續存在,只是換綁對象。
##
## 斷線重連（見 NetworkManager.gd 的 match_reconnect_claimed 等訊號說明）：
## ENet 的 peer id 是新連線自己配的、沒辦法指定重用舊的,所以這裡維護一組
## 「現在的真實 peer id」↔「BattleDirector 認得的 participant id」對照表
## （_real_peer_to_participant/_participant_to_real_peer），host 收到任何
## 帶著 participant_id 的請求都先查這個表（見 _resolve_sender_participant_id()），
## 對外目標定址（_real_peer_for()）也一樣要查表,不能直接假設 participant_id
## 就是真正的 ENet peer id。
##
## 這整個檔案完全沒辦法在這個開發環境（單一個 Godot 編輯器）用兩台真正的
## 裝置實機驗證——只做過 validate_script（語法/型別）跟單機模式（solo vs AI，
## 永遠是唯一一台裝置、永遠是權威、這裡的所有 RPC 分支都不會被觸發）下的
## 開機煙霧測試,確認沒有因為新增這個節點而讓既有的單人流程壞掉。真正的雙
## 裝置連線對戰行為（包含這裡最複雜的斷線重連）要等使用者拿兩台真機測才能
## 真正驗證。
class_name BattleMatchSync
extends Node

## 進度：目前已經按「繼續」的人數/總共需要幾個人（不含 AI/斷線中的人，
## 見 _required_continue_count()）——Battle.gd 監聽這個更新結算畫面文字。
signal continue_progress_updated(confirmed: int, total: int)
## 所有需要確認的人都按了「繼續」——Battle.gd 監聽這個呼叫 _start_round()。
signal next_round_confirmed

var _director: BattleDirector
var _is_host_authority: bool = true
var _local_participant_id: int = 0

var _real_peer_to_participant: Dictionary = {}
var _participant_to_real_peer: Dictionary = {}

## host 端專用：participant_id -> true，這一輪已經按過「繼續」的人（不含
## AI/斷線中的人，見 _required_continue_count()）——每次真的進到下一輪都會
## 清空（見 bind_director()），跟 NetworkManager._peer_ready 是完全不同的
## 兩個計時範圍（那個是整個房間等候階段，這個是「這一輪打完了」這個時間點）。
var _continue_confirmed: Dictionary = {}

func _ready() -> void:
	NetworkManager.match_peer_disconnected.connect(_on_network_peer_disconnected)
	NetworkManager.match_reconnect_claimed.connect(_on_match_reconnect_claimed)

## Battle.gd 每次 _start_round() 建立新的 BattleDirector 後呼叫這個重新綁定
## ——見檔案開頭的說明,上一輪的 director 不用手動解除連接,沒人再引用它,
## 訊號永遠不會再被觸發,GC 自然回收。
func bind_director(director: BattleDirector, is_host_authority: bool, local_participant_id: int) -> void:
	_director = director
	_is_host_authority = is_host_authority
	_local_participant_id = local_participant_id
	_continue_confirmed.clear()
	var participant_ids: Array = director.participants.keys()
	print("[Sync] bind_director my_id=%d is_host_authority=%s local_participant_id=%d networked=%s participants=%s" \
			% [multiplayer.get_unique_id(), is_host_authority, local_participant_id, _is_networked(), str(participant_ids)])
	director.local_board_changed.connect(_on_local_board_changed)
	director.attack_relay_needed.connect(_on_attack_relay_needed)
	director.pending_counts_changed.connect(_on_pending_counts_changed)
	director.remote_garbage_ready.connect(_on_remote_garbage_ready)
	director.elimination_report_needed.connect(_on_elimination_report_needed)
	director.elimination_synced.connect(_on_elimination_synced)
	director.round_ended.connect(_on_round_ended)

## 這個 RPC 的送出者「現在」代表哪個 participant_id——預設是身分對照（沒有
## 重連過的一般連線,真實 peer id 就是 participant id 本身),重連過的話查
## 對照表（見檔案開頭的說明）。
func _resolve_sender_participant_id() -> int:
	var real_id := multiplayer.get_remote_sender_id()
	return _real_peer_to_participant.get(real_id, real_id)

## 反過來：這個 participant_id 現在真正的 ENet peer id 是多少（給
## rpc_id() 定址用）——同樣預設身分對照,重連過才查表。
func _real_peer_for(participant_id: int) -> int:
	return _participant_to_real_peer.get(participant_id, participant_id)

## 單機/AI 對戰（is_solo_mode）也會是「host 權威」（唯一一台裝置，永遠是
## 權威，見 BattleDirector._is_host_authority 的說明），但根本沒有連線
## ——這裡的訊號處理常常一邊檢查「是不是權威」一邊直接送 RPC，權威判斷在
## 單機下一樣會過，如果不額外擋「有沒有真正連線」，單機模式下每次鎖方塊/
## 結算/淘汰/回合結束都會嘗試對一個不存在的連線送 RPC。實測前先保守擋起來
## ，比自己猜 Godot 沒有 peer 時 rpc() 的行為安全。
func _is_networked() -> bool:
	return multiplayer.has_multiplayer_peer()

## --- C：盤面狀態（鎖方塊/被疊垃圾行）同步 --------------------------------

func _on_local_board_changed(participant_id: int) -> void:
	if not _is_networked():
		print("[Sync] _on_local_board_changed participant=%d SKIPPED (not networked)" % participant_id)
		return
	var participant: BattleParticipant = _director.participants.get(participant_id)
	if participant == null:
		print("[Sync] _on_local_board_changed participant=%d SKIPPED (not found in director.participants)" % participant_id)
		return
	var snapshot: Dictionary = participant.controller.get_resume_snapshot()
	if _is_host_authority:
		print("[Sync] _on_local_board_changed participant=%d -> broadcast _sync_board_state.rpc()" % participant_id)
		_sync_board_state.rpc(participant_id, snapshot)
	else:
		print("[Sync] _on_local_board_changed participant=%d -> rpc_id host _request_report_board_state" % participant_id)
		_request_report_board_state.rpc_id(NetworkManager.HOST_PEER_ID, participant_id, snapshot)

@rpc("any_peer", "reliable")
func _request_report_board_state(participant_id: int, snapshot: Dictionary) -> void:
	print("[Sync] RECEIVED _request_report_board_state participant=%d my_id=%d" % [participant_id, multiplayer.get_unique_id()])
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return  # 防呆：只有伺服器本人才會真的受理
	if _resolve_sender_participant_id() != participant_id:
		print("[Sync] _request_report_board_state REJECTED sender mismatch: resolved=%d claimed=%d" % [_resolve_sender_participant_id(), participant_id])
		return  # 只能回報自己的盤面,不能假冒別人
	_sync_board_state.rpc(participant_id, snapshot)

## call_local——host 自己收到別人回報時也會走到這裡再廣播一次,順便套用在
## 自己身上（雖然通常對 host 自己沒意義,見下面 is_local 的防呆),跟其他
## 檔案裡既有的 call_local 慣例一致,不用另外維護重複邏輯。
@rpc("authority", "call_local", "reliable")
func _sync_board_state(participant_id: int, snapshot: Dictionary) -> void:
	var participant: BattleParticipant = _director.participants.get(participant_id)
	if participant == null:
		print("[Sync] RECEIVED _sync_board_state participant=%d SKIPPED (not found)" % participant_id)
		return
	if participant.is_local:
		print("[Sync] RECEIVED _sync_board_state participant=%d SKIPPED (is_local on this device)" % participant_id)
		return
	print("[Sync] RECEIVED _sync_board_state participant=%d -> restore_from_snapshot APPLIED" % participant_id)
	participant.controller.restore_from_snapshot(snapshot)

## --- C：攻擊/垃圾行結算同步 ----------------------------------------------

func _on_attack_relay_needed(participant_id: int, attack_power: int, gap_columns: Array) -> void:
	print("[Sync] _on_attack_relay_needed participant=%d -> rpc_id host _request_resolve_attack" % participant_id)
	_request_resolve_attack.rpc_id(NetworkManager.HOST_PEER_ID, participant_id, attack_power, gap_columns)

@rpc("any_peer", "reliable")
func _request_resolve_attack(participant_id: int, attack_power: int, gap_columns: Array) -> void:
	print("[Sync] RECEIVED _request_resolve_attack participant=%d my_id=%d" % [participant_id, multiplayer.get_unique_id()])
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return
	if _resolve_sender_participant_id() != participant_id:
		print("[Sync] _request_resolve_attack REJECTED sender mismatch")
		return
	_director.resolve_attack(participant_id, attack_power, gap_columns)

## 給大家看到最新的待定點點數量用（顯示用途,不含真正的缺口欄位資料——
## 只有 host 真的需要缺口欄位去 inject_garbage()，見 _sync_pending_counts()
## 只送數量的說明）。
func _on_pending_counts_changed() -> void:
	if not _is_host_authority or not _is_networked():
		return
	var counts := {}
	for pid in _director.participants:
		counts[pid] = _director.participants[pid].pending_garbage.size()
	print("[Sync] _on_pending_counts_changed -> broadcast _sync_pending_counts.rpc(%s)" % str(counts))
	_sync_pending_counts.rpc(counts)

## 非本機模擬的參與者收到的只是「數量」，不是真的缺口欄位——他們的
## pending_garbage 在這台裝置上只用來顯示點點數（OpponentPanel.gd 讀
## .size()），不會被拿去真的 inject_garbage()（那個只有本機模擬那一方會做，
## 見 BattleDirector._settle_all()/apply_injected_garbage()），填什麼值都
## 無所謂，只要長度對就好。
@rpc("authority", "call_local", "reliable")
func _sync_pending_counts(counts: Dictionary) -> void:
	for pid in counts:
		var participant: BattleParticipant = _director.participants.get(pid)
		if participant == null or participant.is_local:
			continue
		var arr: Array = []
		arr.resize(int(counts[pid]))
		participant.pending_garbage = arr

## host 決定要疊給某個「還在線上的遠端真人」垃圾行了（見
## BattleDirector._settle_all()）——轉送給那個人的裝置自己套用（那台裝置
## 才是真正模擬那個 controller 的一方,host 不能代打）。
func _on_remote_garbage_ready(participant_id: int, gap_columns: Array) -> void:
	print("[Sync] _on_remote_garbage_ready participant=%d target_real_peer=%d lines=%d" % [participant_id, _real_peer_for(participant_id), gap_columns.size()])
	_apply_garbage.rpc_id(_real_peer_for(participant_id), gap_columns)

@rpc("authority", "reliable")
func _apply_garbage(gap_columns: Array) -> void:
	print("[Sync] RECEIVED _apply_garbage lines=%d -> apply_injected_garbage for local_participant=%d" % [gap_columns.size(), _local_participant_id])
	_director.apply_injected_garbage(_local_participant_id, gap_columns)

## --- C：淘汰/回合結束同步 -------------------------------------------------

func _on_elimination_report_needed(participant_id: int) -> void:
	_request_report_elimination.rpc_id(NetworkManager.HOST_PEER_ID, participant_id)

@rpc("any_peer", "reliable")
func _request_report_elimination(participant_id: int) -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return
	if _resolve_sender_participant_id() != participant_id:
		return
	_director.report_remote_elimination(participant_id)

func _on_elimination_synced(participant_id: int) -> void:
	if not _is_host_authority or not _is_networked():
		return
	_sync_elimination.rpc(participant_id)

@rpc("authority", "reliable")
func _sync_elimination(participant_id: int) -> void:
	_director.apply_remote_elimination(participant_id)

func _on_round_ended(winning_team: int) -> void:
	if not _is_host_authority or not _is_networked():
		return
	print("[Sync] _on_round_ended winning_team=%d -> broadcast _sync_round_end.rpc()" % winning_team)
	_sync_round_end.rpc(winning_team)

@rpc("authority", "reliable")
func _sync_round_end(winning_team: int) -> void:
	_director.apply_round_end(winning_team)

## --- D：斷線暫停/重連 ------------------------------------------------------

## 只有 host 會收到 NetworkManager.match_peer_disconnected（見該訊號說明：
## 只有真正的 ENet 伺服器才收得到 peer_disconnected）。
func _on_network_peer_disconnected(peer_id: int) -> void:
	if not _is_host_authority or _director == null:
		return
	var participant_id: int = _real_peer_to_participant.get(peer_id, peer_id)
	if not _director.participants.has(participant_id):
		return
	_director.set_participant_disconnected(participant_id, true)
	_sync_disconnected.rpc(participant_id, true)

@rpc("authority", "reliable")
func _sync_disconnected(participant_id: int, disconnected: bool) -> void:
	_director.set_participant_disconnected(participant_id, disconnected)

## host 收到重連認領請求（見 NetworkManager.gd 的 match_reconnect_claimed
## 說明）：只有「目前真的處於斷線暫停狀態」的參與者才准被認領，避免有人
## 亂送一個沒斷線的 id 過來搞亂對照表。認領成功：登記新舊 id 對照、解除
## 暫停狀態、廣播給大家、把保留的完整快照（board/randomizer/score/hold/
## combo 等,見 TetrisGameController.get_resume_snapshot()）直接送回給這個
## 新連線——已經被淘汰的人不用送快照（見該函式呼叫端的說明：不能讓重連
## 復活一個真的輸掉的人,restore_from_snapshot() 會把 is_game_over 重設成
## false,只有還沒真的輸、單純斷線暫停的人才適用)。
func _on_match_reconnect_claimed(new_peer_id: int, claimed_participant_id: int) -> void:
	if not _is_host_authority or _director == null:
		return
	var participant: BattleParticipant = _director.participants.get(claimed_participant_id)
	if participant == null or not participant.is_disconnected:
		return
	_real_peer_to_participant[new_peer_id] = claimed_participant_id
	_participant_to_real_peer[claimed_participant_id] = new_peer_id
	_director.set_participant_disconnected(claimed_participant_id, false)
	_sync_disconnected.rpc(claimed_participant_id, false)
	if not participant.is_eliminated:
		_deliver_resume_snapshot.rpc_id(new_peer_id, claimed_participant_id, participant.controller.get_resume_snapshot())

@rpc("authority", "reliable")
func _deliver_resume_snapshot(participant_id: int, snapshot: Dictionary) -> void:
	if participant_id != _local_participant_id:
		return
	var participant: BattleParticipant = _director.participants.get(participant_id)
	if participant:
		participant.controller.restore_from_snapshot(snapshot)

## --- E：下一輪共識（全員都按「繼續」才真的開始下一輪）---------------------

## Battle.gd 的結算畫面按鈕在多人模式下呼叫這個,取代直接呼叫 _start_round()
## ——單機/AI 對戰不會走到這裡（Battle.gd 那層直接判斷 is_solo_mode 分流)。
func request_continue() -> void:
	if _is_host_authority:
		_mark_continue(_local_participant_id)
	else:
		_request_continue.rpc_id(NetworkManager.HOST_PEER_ID, _local_participant_id)

@rpc("any_peer", "reliable")
func _request_continue(participant_id: int) -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return
	if _resolve_sender_participant_id() != participant_id:
		return
	_mark_continue(participant_id)

func _mark_continue(participant_id: int) -> void:
	if _continue_confirmed.get(participant_id, false):
		return
	_continue_confirmed[participant_id] = true
	var total := _required_continue_count()
	_sync_continue_progress.rpc(_continue_confirmed.size(), total)
	if _continue_confirmed.size() >= total:
		_continue_confirmed.clear()
		_broadcast_start_next_round.rpc()

## 需要按「繼續」的人數：排除 AI（不會按按鈕）跟目前斷線暫停中的人（見對戰
## 規格已確認的規則：下一輪開始不等他們,一樣盤面暫停),至少 1 人（理論上
## 不會真的是 0,防呆用)。
func _required_continue_count() -> int:
	var count := 0
	for pid in _director.participants:
		if BattleSettings.is_ai(pid):
			continue
		var participant: BattleParticipant = _director.participants[pid]
		if participant.is_disconnected:
			continue
		count += 1
	return maxi(count, 1)

@rpc("authority", "call_local", "reliable")
func _sync_continue_progress(confirmed: int, total: int) -> void:
	continue_progress_updated.emit(confirmed, total)

@rpc("authority", "call_local", "reliable")
func _broadcast_start_next_round() -> void:
	next_round_confirmed.emit()
