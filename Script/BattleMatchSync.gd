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

## host 端專用：每次 bind_director()（＝真的開始新的一輪）遞增，給重連時
## 判斷「這個人斷線的時候是第幾輪」用（見 _disconnected_at_round/
## _on_match_reconnect_claimed() 的說明）。
var _round_number: int = 0
## host 端專用：participant_id -> 斷線當下是第幾輪。重連認領時如果現在的
## _round_number 已經往前走了（代表其他人已經開始新的一輪，這個人整段錯過
## 了),代表回不去了——2026-09-23 使用者明確要求先做簡單版：偵測到跨輪就讓
## 這個人整個踢回大廳,不嘗試把新一輪當下所有人的盤面/星星戰績整包送給他
## 無縫接軌（那個要做的事情很多,之後真的需要再回來做完整版）。
var _disconnected_at_round: Dictionary = {}

## host 端專用：目前還在斷線暫停中、還沒重連回來的人（participant_id ->
## true）。2026-09-23 使用者回報：淘汰的灰階畫面在斷線的人身上「進到下一輪
## 就恢復正常」——根因是每次 bind_director() 換綁的是全新的 BattleDirector，
## 新的 BattleParticipant 一律從 is_disconnected=false 開始（見
## BattleDirector._init()，完全沒有「這個人上一輪就已經斷線、還沒接回來」
## 的概念）。這份記錄跨輪次持續存在（不會因為換 director 就清空），成功重連
## 才會在 _on_match_reconnect_claimed() 清掉,bind_director() 換綁新一輪時
## 拿來把還沒回來的人重新標記回 is_disconnected=true。
var _still_disconnected: Dictionary = {}

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
	_round_number += 1
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

	## 把還沒重連回來的人重新標記成斷線（見 _still_disconnected 的說明）——
	## 只有 host 權威裝置需要做這件事並廣播出去,其他裝置等這個廣播套用就好,
	## 不用自己重複判斷（新一輪剛綁定,其他裝置的 _director 這時也已經是新的
	## 了,收到 _sync_disconnected 時 _director 不會是 null）。
	if _is_host_authority:
		for pid in _still_disconnected:
			if director.participants.has(pid):
				director.set_participant_disconnected(pid, true)
				_sync_disconnected.rpc(pid, true)

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

func _on_attack_relay_needed(participant_id: int, attack_power: float, gap_columns: Array) -> void:
	print("[Sync] _on_attack_relay_needed participant=%d -> rpc_id host _request_resolve_attack" % participant_id)
	_request_resolve_attack.rpc_id(NetworkManager.HOST_PEER_ID, participant_id, attack_power, gap_columns)

@rpc("any_peer", "reliable")
func _request_resolve_attack(participant_id: int, attack_power: float, gap_columns: Array) -> void:
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

## 2026-09-23 修正實機回報的兩個問題,根因都在這個函式：
## (1) 「連結端自己看不到自己的待定點點」——原本用 participant.is_local 判斷
##     要不要更新,理由寫的是「非本機模擬的參與者只需要數量」,但這個判斷條件
##     搞混了兩件事：is_local 指的是「這個參與者的真正棋盤是不是這台裝置在
##     模擬」,不代表「這台裝置本來就有這個參與者正確的 pending_garbage
##     資料」——pending_garbage 的累積（_apply_attack()）只會在權威裝置上
##     跑,非權威裝置不管是看別人還是看自己,都要靠這個廣播才知道正確數量,
##     原本的 is_local 排除條件反而把「自己」這個最需要更新的對象排除掉了。
## (2) 「垃圾根本沒有真的疊上盤面」——這個函式是 call_local,權威裝置自己
##     廣播出去也會執行到這裡；權威裝置對「不是本機模擬」的參與者（也就是
##     其他真人)一樣會走進迴圈,用 arr.resize() 產生的「只有長度、內容是
##     null」的假陣列直接覆蓋掉 participant.pending_garbage——而這個
##     participant 物件跟 _apply_attack() 剛剛寫入真正缺口欄位資料的物件是
##     同一個(權威裝置只有一份 director),等於權威裝置自己把自己剛算好的
##     真正資料，立刻用假資料蓋掉,_settle_all() 之後拿到的就是壞資料。
## 修正：整個函式只在「非權威裝置」上生效（權威裝置自己的資料本來就是正確
## 來源,不需要也不能被這個廣播覆寫）,而且不排除 is_local,所有參與者
## （包含自己）都更新——反正非權威裝置的 pending_garbage 本來就只拿來顯示
## 點點數量用,不會被拿去真的 inject_garbage()（那個由權威裝置決定要不要
## 轉送,見 remote_garbage_ready 的說明），填什麼值都無所謂,只要長度對就好。
@rpc("authority", "call_local", "reliable")
func _sync_pending_counts(counts: Dictionary) -> void:
	if _is_host_authority:
		return
	for pid in counts:
		var participant: BattleParticipant = _director.participants.get(pid)
		if participant == null:
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
	_disconnected_at_round[participant_id] = _round_number
	_still_disconnected[participant_id] = true
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
## 2026-09-23 使用者回報：斷線的人如果是在「跨輪」之後才重新連上（其他人
## 已經開始新的一輪、bind_director() 已經換綁成新的 BattleDirector），下面
## 這段邏輯完全沒有「回合是不是同一個」的概念——會直接把新一輪、全新的
## controller 快照送回去，但重連的人自己那台裝置的 Battle.gd/BattleMatchSync
## 完全沒經歷新一輪的 _start_round()（他們斷線期間錯過了
## _broadcast_start_next_round.rpc()，那是不重播的一次性廣播），畫面上其他
## 東西（team_round_wins 星星、對手名單、結算畫面）全部還停在斷線前的舊
## 一輪，只有這個 controller 的盤面被偷偷換成新一輪的空板——整個畫面變成
## 新舊資料混在一起。先做簡單版（使用者明確要求）：偵測到「斷線當下的輪數
## 不等於現在的輪數」就不嘗試接回去，直接讓這個人整個踢回大廳,自己重新
## 搜尋/加入房間。
func _on_match_reconnect_claimed(new_peer_id: int, claimed_participant_id: int) -> void:
	if not _is_host_authority or _director == null:
		return
	var participant: BattleParticipant = _director.participants.get(claimed_participant_id)
	if participant == null or not participant.is_disconnected:
		return
	if _disconnected_at_round.get(claimed_participant_id, _round_number) != _round_number:
		_reject_stale_reconnect.rpc_id(new_peer_id)
		return
	_real_peer_to_participant[new_peer_id] = claimed_participant_id
	_participant_to_real_peer[claimed_participant_id] = new_peer_id
	_still_disconnected.erase(claimed_participant_id)
	_director.set_participant_disconnected(claimed_participant_id, false)
	_sync_disconnected.rpc(claimed_participant_id, false)
	if not participant.is_eliminated:
		_deliver_resume_snapshot.rpc_id(new_peer_id, claimed_participant_id, participant.controller.get_resume_snapshot())

## 收到這個代表「你斷線的時候比賽已經進了新的一輪，接不回去了」——直接整個
## 斷線回大廳，使用者需要自己重新搜尋/加入房間（見上面
## _on_match_reconnect_claimed() 的說明，這是刻意選的簡化版本）。
@rpc("authority", "reliable")
func _reject_stale_reconnect() -> void:
	NetworkManager.cancel()
	get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")

@rpc("authority", "reliable")
func _deliver_resume_snapshot(participant_id: int, snapshot: Dictionary) -> void:
	if participant_id != _local_participant_id:
		return
	var participant: BattleParticipant = _director.participants.get(participant_id)
	if participant:
		participant.controller.restore_from_snapshot(snapshot)

## --- E：下一輪（跟房間設定/分隊畫面同一套「加入方按準備、房主按開始」）---

## 2026-09-23 改版：使用者明確要求下一輪的轉場要跟房間設定/分隊畫面一致
## （不要「大家按同一顆鈕、湊齊人數自動開始」的投票模式）——非房主按
## 「準備」只標記/取消自己的確認狀態,不會自動開始；房主等所有其他真人都
## 確認後,自己按「下一輪開始」（見 start_next_round()）才真的觸發。房主
## 自己不用準備（_required_continue_count() 排除 _local_participant_id,
## 跟 RoomBattleSettings/TeamSelect 房主不用準備是同一個道理)。
## Battle.gd 的結算畫面「準備」按鈕在多人模式下呼叫這個——單機/AI 對戰不會
## 走到這裡（Battle.gd 那層直接判斷 is_solo_mode 分流)。
func request_continue(is_ready: bool) -> void:
	if _is_host_authority:
		_mark_continue(_local_participant_id, is_ready)
	else:
		_request_continue.rpc_id(NetworkManager.HOST_PEER_ID, _local_participant_id, is_ready)

@rpc("any_peer", "reliable")
func _request_continue(participant_id: int, is_ready: bool) -> void:
	if multiplayer.get_unique_id() != NetworkManager.HOST_PEER_ID:
		return
	if _resolve_sender_participant_id() != participant_id:
		return
	_mark_continue(participant_id, is_ready)

func _mark_continue(participant_id: int, is_ready: bool) -> void:
	if is_ready:
		_continue_confirmed[participant_id] = true
	else:
		_continue_confirmed.erase(participant_id)
	_sync_continue_progress.rpc(_continue_confirmed.size(), _required_continue_count())

## 房主專用：Battle.gd 的「下一輪開始」按鈕呼叫——只有所有其他真人都已確認
## 準備才會真的觸發（Battle.gd 那邊也會依同一個條件把按鈕 disabled,這裡是
## 伺服器端再擋一次,不是只靠前端）。非房主呼叫直接忽略。
func start_next_round() -> void:
	if not _is_host_authority:
		return
	if _continue_confirmed.size() < _required_continue_count():
		return
	_continue_confirmed.clear()
	_broadcast_start_next_round.rpc()

## 給 Battle.gd 算「房主開始鈕要等幾個人」的顯示文字用（結算畫面剛出現、
## 還沒收到任何 continue_progress_updated 廣播那一刻的初始值)。
func get_required_continue_count() -> int:
	return _required_continue_count()

## 需要按「準備」的人數：排除房主自己（不用準備,由他按「下一輪開始」)、
## AI（不會按按鈕)跟目前斷線暫停中的人（見對戰規格已確認的規則：下一輪
## 開始不等他們,一樣盤面暫停）。理論上結果可能是 0（目前沒有其他真人,不太
## 會發生,但不用防呆成至少 1——不然房主的開始鈕會被自己卡住永遠打不開)。
func _required_continue_count() -> int:
	var count := 0
	for pid in _director.participants:
		if pid == _local_participant_id:
			continue
		if BattleSettings.is_ai(pid):
			continue
		var participant: BattleParticipant = _director.participants[pid]
		if participant.is_disconnected:
			continue
		count += 1
	return count

@rpc("authority", "call_local", "reliable")
func _sync_continue_progress(confirmed: int, total: int) -> void:
	continue_progress_updated.emit(confirmed, total)

@rpc("authority", "call_local", "reliable")
func _broadcast_start_next_round() -> void:
	next_round_confirmed.emit()
