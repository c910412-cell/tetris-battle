## 單人 vs AI（之後也給連線多人用）的對戰邏輯協調者。純 RefCounted，不掛
## 場景樹，由 Battle.gd 的 _process() 每幀呼叫 tick(delta)——跟
## TetrisGameController 一樣「純邏輯、畫面另外處理」的做法。
## 負責：驅動每個參與者的 controller/AI、傷害/抵消/結算的資料流、淘汰判定、
## 回合結束判定。完整規格見 memory/tetris_multiplayer_battle_design.md
## 第 6~8、11 節。2026-09-21 補上指定目標攻擊：真人玩家開啟房間設定的
## 「指定目標攻擊」時，可以在 Battle.gd 觸控選對手，選中的目標鎖住不會被
## 隨機重骰蓋掉（見 set_manual_target()）；AI 沒有觸控能力，一律維持隨機
## 目標。一輪定勝負（bo-N 多輪迴圈是 Battle.gd 那層的事，這裡只管單一輪）。
## 2026-09-23（連線對戰第二階段）：每個裝置只「本機模擬」自己的真人玩家＋
## （只有 host 權威裝置才模擬）AI，其他真人玩家的參與者要靠網路同步——這裡
## 只負責權威判定跟拆分要不要本機 tick，實際的 RPC 收送在新的
## Script/BattleMatchSync.gd（見該檔案），這裡透過訊號跟它溝通，不直接依賴
## NetworkManager/multiplayer，維持這個檔案純邏輯、可離線單獨測試。
class_name BattleDirector
extends RefCounted

## 剩一隊還有人存活時發出，winning_team 是贏的隊伍 index（平手時是 -1，
## 理論上很少發生）。這個訊號只會由 apply_round_end() 發出——權威裝置自己
## 判定完（_check_round_end()）或非權威裝置收到網路廣播後都走這個統一入口，
## 保證所有裝置看到的是同一個結果。
signal round_ended(winning_team: int)
## 任何一個參與者被淘汰時發出，給畫面更新用（例如切成旁觀畫面）。
signal participant_eliminated(participant_id: int)
## 結算時某個參與者身上的待定點點真的疊成垃圾行了（見 _settle_all()）——
## Battle.gd 拿這個訊號判斷「是不是本地玩家自己被打」來觸發震動回饋，跟
## _on_attack_ready() 累積待定點點的當下（還沒真的疊上盤面）是分開的時機點。
signal garbage_settled(participant_id: int, lines: int)

## 這台裝置本機模擬的某個參與者狀態改變了（鎖方塊或被疊垃圾行），需要把
## controller.get_resume_snapshot() 送出去給其他人（BattleMatchSync 監聽這個
## 訊號，不是本機模擬的參與者永遠不會發出這個）。
signal local_board_changed(participant_id: int)
## 非權威裝置自己鎖方塊觸發了 attack_ready，但攻擊/垃圾行結算是 host 權威、
## 這台裝置不能自己解算——BattleMatchSync 監聽這個訊號轉送給 host。
signal attack_relay_needed(participant_id: int, attack_power: float, gap_columns: Array)
## resolve_attack()／_settle_all() 讓某個參與者的 pending_garbage 數量變了
## （不管是被扣掉還是被加上），BattleMatchSync（host 端）監聽這個訊號廣播
## 目前每個人的待定點點數量給大家更新畫面。
signal pending_counts_changed
## _settle_all()（只會在 host 權威裝置上跑）決定要疊給某個「不是本機模擬」
## 的參與者（真正的遠端真人）垃圾行了——host 沒辦法直接操作對方的 controller
## （那台裝置才是真正模擬它的一方），BattleMatchSync 監聽這個訊號把
## gap_columns 送過去給那個人的裝置自己套用。
signal remote_garbage_ready(participant_id: int, gap_columns: Array)
## 非權威裝置上「本機自己的參與者」淘汰了，但回合結束判定是 host 權威、這台
## 裝置不能自己決定——BattleMatchSync 監聽這個訊號回報給 host。
signal elimination_report_needed(participant_id: int)
## host 權威裝置上有人淘汰了（不管是本機自己的、AI 的、還是遠端回報的），
## 需要廣播給所有人同步——BattleMatchSync（host 端）監聽這個訊號廣播出去。
signal elimination_synced(participant_id: int)

## 隨機目標多久重骰一次——使用者還沒定案，先寫死一個合理值。
## TODO: 之後可能要改成 BattleSettings 裡的房間設定欄位。
const TARGET_REROLL_SECONDS := 15.0

var participants: Dictionary = {} # participant_id(int) -> BattleParticipant
var is_round_over: bool = false

var _settlement_timer: float = 0.0
var _target_reroll_timer: float = 0.0

## true＝這台裝置對這場對戰有「host 權威」——攻擊/垃圾行結算跟回合勝負判定
## 只能有一台裝置真正跑（不然每台裝置各自算一次，餘數進位/隨機目標都會
## 各自跑出不同結果，直接對不上），所有其他裝置只能等 host 決定後用網路
## 廣播套用結果（見上面幾個訊號跟 Script/BattleMatchSync.gd）。單機/AI 對戰
## 只有一台裝置，永遠是權威，行為跟改之前完全一樣。
var _is_host_authority: bool = true
## 這台裝置本機真人玩家的 participant id——只有這個 id 的參與者「一定」是
## is_local（真人玩家的操作永遠本機即時，不等網路）；用來判斷淘汰/斷線事件
## 是不是「發生在自己身上」，需不需要主動回報給 host（見
## elimination_report_needed 的說明）。
var _local_participant_id: int = 0

## forced_seed：連線對戰時由房主產生、透過 NetworkManager._start_match() 廣播
## 給所有人（見 Battle.gd 傳入 BattleSettings.network_match_seed），確保每個
## 人重建出同一份 7-bag 出塊順序；0（預設，單機/AI 對戰）代表沒有外部種子，
## 照原本行為自己 randi() 一個——跟之前完全相同，行為不變。
## local_participant_id：這台裝置本機真人玩家的 id（Battle.gd 傳入
## _local_peer_id）；0（預設）代表沒有本機真人（純觀戰/測試用不到）。
## is_host_authority：這台裝置是不是對這場對戰的權威（見上面欄位說明）；
## Battle.gd 傳入時單機/AI 對戰永遠 true,連線對戰才會傳
## `multiplayer.get_unique_id() == NetworkManager.room_owner_peer_id`。
func _init(forced_seed: int = 0, local_participant_id: int = 0, is_host_authority: bool = true) -> void:
	_is_host_authority = is_host_authority
	_local_participant_id = local_participant_id
	var shared_seed := forced_seed if forced_seed != 0 else randi()
	if shared_seed == 0:
		shared_seed = 1

	for participant_id in BattleSettings.get_all_placed_ids():
		var cell: Vector2i = BattleSettings.get_placement(participant_id)
		var controller_seed := 0 if BattleSettings.random_piece_per_player else shared_seed
		var controller := TetrisGameController.new(controller_seed)
		var participant := BattleParticipant.new(participant_id, cell.x, controller)
		## 本機真人自己永遠是本機模擬；AI 只有權威裝置才本機模擬（見
		## is_local 欄位說明）；其他真人玩家這台裝置上永遠不是本機模擬,盤面
		## 要等網路同步（Script/BattleMatchSync.gd）才有資料來源。
		participant.is_local = (participant_id == local_participant_id) \
				or (_is_host_authority and participant.is_ai())
		if participant.is_ai():
			participant.ai = TetrisAI.new(controller, BattleSettings.ai_level)
		participants[participant_id] = participant
		controller.piece_locked.connect(_on_piece_locked.bind(participant))
		controller.attack_ready.connect(_on_attack_ready.bind(participant))
		controller.game_over.connect(_on_participant_game_over.bind(participant))

	for participant_id in participants:
		_retarget(participants[participant_id])

## 斷線暫停/重連（見 BattleParticipant.is_disconnected 說明）：排除在存活
## 判定/選目標池之外,重新檢查一次回合有沒有結束。真正的斷線偵測/重連流程
## 在 Script/BattleMatchSync.gd（監聽 NetworkManager 的連線事件），這裡只是
## 給它呼叫的進入點。
func set_participant_disconnected(participant_id: int, disconnected: bool) -> void:
	if not participants.has(participant_id):
		return
	var participant: BattleParticipant = participants[participant_id]
	if participant.is_disconnected == disconnected:
		return
	participant.is_disconnected = disconnected
	if not disconnected:
		return
	for other_id in participants:
		var other: BattleParticipant = participants[other_id]
		if not other.is_eliminated and not other.is_disconnected and other.current_target_id == participant.id:
			_retarget(other)
	if _is_host_authority:
		_check_round_end()

func tick(delta: float) -> void:
	if is_round_over:
		return

	## 每台裝置只驅動「本機模擬」的參與者（自己＋權威裝置上的 AI）——其他
	## 真人玩家的 controller 不能在這裡瞎跑,他們的盤面狀態要靠網路同步
	## 取得,不然每台裝置會各自演化出不同的盤面。
	for participant_id in participants:
		var participant: BattleParticipant = participants[participant_id]
		if participant.is_eliminated or participant.is_disconnected or not participant.is_local:
			continue
		participant.controller.tick(delta)
		if participant.ai:
			participant.ai.decide_and_act(delta)

	## 2026-09-23 使用者回報：連結端（非權威裝置）的結算倒數條完全不會動——
	## 根因是 get_settlement_progress() 純粹讀本機的 _settlement_timer,是每
	## 台裝置自己畫自己的（不是靠網路同步畫面),但這個計時器原本整段都在
	## 「只有權威裝置才會執行」的區塊裡,非權威裝置的 _settlement_timer 永遠
	## 停在 0,倒數條當然不會動。改成：計時本身（純顯示用途）每台裝置都自己
	## 走,保持跟權威裝置大致同步；但「時間到了要不要真的結算」這個判斷
	## （_settle_all()）仍然只有權威裝置會做,非權威裝置這裡計時器歸零純粹是
	## 讓倒數條重新跑一輪,不會誤觸發真正的結算。
	_settlement_timer += delta
	if _settlement_timer >= BattleSettings.settlement_seconds:
		_settlement_timer = 0.0
		if _is_host_authority:
			_settle_all()

	## 目標重骰/回合勝負判定是 host 權威（見 _is_host_authority 說明）——非
	## 權威裝置這裡直接跳過,等網路廣播套用權威裝置算出來的結果。
	if not _is_host_authority:
		return

	_target_reroll_timer += delta
	if _target_reroll_timer >= TARGET_REROLL_SECONDS:
		_target_reroll_timer = 0.0
		for participant_id in participants:
			var participant: BattleParticipant = participants[participant_id]
			if not participant.is_eliminated and not participant.is_disconnected and not participant.manual_target_locked:
				_retarget(participant)

func get_settlement_progress() -> float:
	return clampf(_settlement_timer / maxf(BattleSettings.settlement_seconds, 0.01), 0.0, 1.0)

func get_alive_opponents(participant: BattleParticipant) -> Array:
	var result: Array = []
	for pid in participants:
		var other: BattleParticipant = participants[pid]
		if other.id != participant.id and not other.is_eliminated and not other.is_disconnected \
				and other.team_index != participant.team_index:
			result.append(other.id)
	return result

func _retarget(participant: BattleParticipant) -> void:
	var options := get_alive_opponents(participant)
	participant.current_target_id = options[randi() % options.size()] if not options.is_empty() else 0
	participant.manual_target_locked = false

## 指定目標攻擊：真人玩家觸控選對手時呼叫（見 Battle.gd）。目標必須是還活著
## 的敵隊參與者，選中後鎖住不會被隨機重骰蓋掉，直到目標淘汰才會強制換人。
## 回傳 true 表示選擇成功。
func set_manual_target(participant_id: int, target_id: int) -> bool:
	if not participants.has(participant_id) or not participants.has(target_id):
		return false
	var participant: BattleParticipant = participants[participant_id]
	var target: BattleParticipant = participants[target_id]
	if participant.is_eliminated or target.is_eliminated:
		return false
	if participant.team_index == target.team_index:
		return false
	participant.current_target_id = target_id
	participant.manual_target_locked = true
	return true

## 一個「本機模擬」的參與者鎖定了一顆方塊——不管有沒有消行都要把新的盤面
## 狀態同步出去（見 local_board_changed 的說明），跟消行/垃圾行結算是分開的
## 觸發時機點（鎖方塊一定會發生；消行/結算不一定）。
func _on_piece_locked(participant: BattleParticipant) -> void:
	if participant.is_local:
		print("[Sync] piece_locked participant=%d is_local=%s -> emit local_board_changed" % [participant.id, participant.is_local])
		local_board_changed.emit(participant.id)

## 結算：把每個參與者累積的待定垃圾行整包疊上他自己的盤面。只會在 host 權威
## 裝置上跑（tick() 已經擋過一次）。三種情況分開處理：(a) 本機模擬（host 自己
## /AI）直接呼叫 inject_garbage()；(b) 已經斷線暫停中的遠端真人——沒有連線
## 可以轉發，host 直接套用在自己保留的那份鏡像上，等重連時
## get_resume_snapshot() 就會包含這些已經疊上去的垃圾行（斷線不是攻擊免死金
## 牌）；(c) 還在線上的遠端真人——host 不能直接動它的 controller（那台裝置
## 才是真正模擬它的一方），改發 remote_garbage_ready 訊號請
## Script/BattleMatchSync.gd 轉送過去給它自己套用。
func _settle_all() -> void:
	for participant_id in participants:
		var participant: BattleParticipant = participants[participant_id]
		if participant.is_eliminated or participant.pending_garbage.is_empty():
			continue
		var gap_columns: Array[int] = []
		for gap in participant.pending_garbage:
			gap_columns.append(gap)
		participant.pending_garbage.clear()
		if participant.is_local or participant.is_disconnected:
			print("[Sync] _settle_all participant=%d is_local=%s is_disconnected=%s -> inject_garbage directly, lines=%d" % [participant_id, participant.is_local, participant.is_disconnected, gap_columns.size()])
			participant.controller.inject_garbage(gap_columns)
			if participant.is_local:
				local_board_changed.emit(participant_id)
		else:
			print("[Sync] _settle_all participant=%d is remote -> emit remote_garbage_ready, lines=%d" % [participant_id, gap_columns.size()])
			remote_garbage_ready.emit(participant_id, gap_columns)
		garbage_settled.emit(participant_id, gap_columns.size())
	pending_counts_changed.emit()

## 給 Script/BattleMatchSync.gd 呼叫：host 收到遠端真人回報「我鎖了一顆方塊
## 消行了」之後，用這個入口跑跟本機一樣的攻擊解算邏輯（不用假造一個
## BattleParticipant 綁定，直接用 participant_id 查表）。
func resolve_attack(participant_id: int, attack_power: float, gap_columns: Array) -> void:
	var participant: BattleParticipant = participants.get(participant_id)
	if participant == null or participant.is_eliminated:
		return
	_apply_attack(participant, attack_power, gap_columns)

## 消行→防禦優先、剩餘才攻擊的貨幣模型（見對戰規格第 6/11 節，已跟使用者
## 逐條確認過）：attack_power（2026-09-22 起由 TetrisGameController 依 T-Spin/
## Back-to-Back/Combo/Perfect Clear 規則算好的攻擊力，不再是單純行數，見
## TetrisGameController._attack_power_for_clear()）先套用傷害倍率公式（每個
## 玩家一份共用餘數，不分現在打誰），換算出的點數先抵消自己身上的待定點點，
## 抵消完還有剩才送給目前目標當攻擊——2026-09-21 補上垃圾行上限：
## BattleSettings.garbage_cap_enabled 開啟時，目標的待定點點在單一結算間隔
## 內最多疊到 garbage_cap_lines（預設 5）行，超過的攻擊點數直接作廢。
func _on_attack_ready(attack_power: int, gap_columns: Array, participant: BattleParticipant) -> void:
	if participant.is_eliminated:
		return
	var effective_power := _comeback_adjusted_attack_power(attack_power, gap_columns.size())
	## 攻擊/垃圾行結算是 host 權威（見 _is_host_authority 說明）——非權威裝置
	## 自己不能跑出一份結算結果，改把原始資料轉送給 host（見
	## attack_relay_needed 的說明，Script/BattleMatchSync.gd 負責真正轉送）。
	## BattleSettings.single_line_counts_as_attack 是廣播同步過的房間設定,
	## 非權威裝置這裡讀到的值跟 host 一致,在這裡先調整好、兩條路徑共用同一個
	## 已調整過的值,不用在 host 端再判斷一次。
	if not _is_host_authority:
		print("[Sync] attack_ready participant=%d not host authority -> emit attack_relay_needed" % participant.id)
		attack_relay_needed.emit(participant.id, effective_power, gap_columns)
		return
	print("[Sync] attack_ready participant=%d host authority -> _apply_attack directly" % participant.id)
	_apply_attack(participant, effective_power, gap_columns)

## 2026-09-23 使用者需求：落後方身上的垃圾通常只有一個缺口、只能一行一行清,
## 清 1 行在標準 guideline 攻擊力表是 0 點（TetrisGameController.
## LINE_ATTACK_BY_COUNT[1]），永遠反擊不了——開啟設定後,單純清 1 行（
## raw_power<=0 這個條件保證只補「原本真的是 0 點」的情況,已經有分數的
## T-Spin Mini 單行攻擊力是 1,不會被這裡蓋掉/降低)改算 0.5 點,兩次累積湊出
## 1 點。故意不改 TetrisGameController 本體的攻擊力表——那份是官方 guideline
## 標準分數,保持純邏輯、跟房間設定脫鉤,這個調整只在對戰層（這裡）疊加。
func _comeback_adjusted_attack_power(raw_power: int, cleared_line_count: int) -> float:
	if BattleSettings.single_line_counts_as_attack and cleared_line_count == 1 and raw_power <= 0:
		return 0.5
	return float(raw_power)

func _apply_attack(participant: BattleParticipant, attack_power: float, gap_columns: Array) -> void:
	participant.ratio_remainder += attack_power
	var ratio: int = maxi(BattleSettings.damage_ratio, 1)
	var points: int = int(participant.ratio_remainder / float(ratio))
	participant.ratio_remainder = fmod(participant.ratio_remainder, float(ratio))
	if points <= 0:
		return

	var canceled: int = mini(points, participant.pending_garbage.size())
	for _i in range(canceled):
		participant.pending_garbage.pop_front()
	var leftover := points - canceled
	if leftover > 0:
		if participant.current_target_id == 0 or not participants.has(participant.current_target_id) \
				or participants[participant.current_target_id].is_eliminated \
				or participants[participant.current_target_id].is_disconnected:
			_retarget(participant)
		if participant.current_target_id != 0:
			var target: BattleParticipant = participants[participant.current_target_id]
			for i in range(leftover):
				if BattleSettings.garbage_cap_enabled and target.pending_garbage.size() >= BattleSettings.garbage_cap_lines:
					break # 已達單一結算間隔的垃圾行上限，剩餘點數直接作廢。
				target.pending_garbage.append(int(gap_columns[i % gap_columns.size()]))
	print("[Sync] _apply_attack done for participant=%d -> emit pending_counts_changed" % participant.id)
	pending_counts_changed.emit()

## 給 Script/BattleMatchSync.gd 呼叫：host 收到遠端真人自己套用垃圾行之後
## 回報過來的「我被疊上垃圾行了」——跟 _settle_all() 的 (c) 分支是一體兩面：
## host 決定要疊多少（remote_garbage_ready），對方真的套用完之後把結果告訴
## host（這個函式）,host 這裡也直接對自己保留的那份鏡像做同樣的事,讓
## get_resume_snapshot() 之後重連時是最新狀態,也讓
## Script/BattleMatchSync.gd 能繼續走同一套 local_board_changed 廣播鏈路
## 通知其他旁觀者。
func apply_injected_garbage(participant_id: int, gap_columns: Array) -> void:
	var participant: BattleParticipant = participants.get(participant_id)
	if participant == null:
		return
	var typed: Array[int] = []
	for gap in gap_columns:
		typed.append(int(gap))
	participant.controller.inject_garbage(typed)
	local_board_changed.emit(participant_id)

## 共用的淘汰簿記——is_eliminated/pending_garbage/其他人的重新選目標，
## 不含「這是不是回合結束/要不要廣播」的判斷（那些交給呼叫端，見
## _on_participant_game_over()/report_remote_elimination()）。
func _eliminate_participant(participant: BattleParticipant) -> void:
	if participant.is_eliminated:
		return
	participant.is_eliminated = true
	participant.pending_garbage.clear() # 已確認：直接消失，不轉給接手隊友
	participant_eliminated.emit(participant.id)
	for other_id in participants:
		var other: BattleParticipant = participants[other_id]
		if not other.is_eliminated and not other.is_disconnected and other.current_target_id == participant.id:
			_retarget(other)

## 玩家淘汰＝旁觀模式：controller 已經自己停在 game_over 狀態、不會再 tick
## 出新變化，這裡只處理對戰層級的後續。host 權威裝置上（包含它自己/AI/已經
## 斷線暫停中的遠端真人這三種都可能從這裡觸發，見 _settle_all() 的說明）直接
## 判定回合有沒有結束＋標記要廣播；非權威裝置上如果剛好是「本機自己」淘汰
## （唯一一種非權威裝置的 controller 真的會被 tick 到、真的能自己觸發
## game_over 的情況），沒辦法自己決定回合結束，改回報給 host。
func _on_participant_game_over(participant: BattleParticipant) -> void:
	print("[Sync] participant_game_over participant=%d is_host_authority=%s" % [participant.id, _is_host_authority])
	_eliminate_participant(participant)
	if _is_host_authority:
		elimination_synced.emit(participant.id)
		_check_round_end()
	elif participant.id == _local_participant_id:
		print("[Sync] -> emit elimination_report_needed for own participant=%d" % participant.id)
		elimination_report_needed.emit(participant.id)

## 給 Script/BattleMatchSync.gd 呼叫：host 收到遠端真人回報「我被淘汰了」
## 之後，用這個入口套用（跟本機淘汰共用同一套 _eliminate_participant()簿記）
## 並接著判定回合結束。
func report_remote_elimination(participant_id: int) -> void:
	var participant: BattleParticipant = participants.get(participant_id)
	if participant == null or participant.is_eliminated:
		return
	_eliminate_participant(participant)
	elimination_synced.emit(participant_id)
	_check_round_end()

## 給 Script/BattleMatchSync.gd 呼叫：非權威裝置收到 host 廣播「某個參與者
## 淘汰了」之後，套用同一套簿記，但不做回合結束判定（那個結果會透過
## apply_round_end() 另外廣播過來，不用自己重複判定）。
func apply_remote_elimination(participant_id: int) -> void:
	var participant: BattleParticipant = participants.get(participant_id)
	if participant == null:
		return
	_eliminate_participant(participant)

## 回合勝負判定是 host 權威（見 _is_host_authority 說明）——非權威裝置不會
## 自己算出「誰贏了」,要等權威裝置算完透過網路廣播呼叫 apply_round_end() 套用
## 同一個結果,不然不同裝置可能因為個別淘汰時間點些許誤差而判定出不一樣的
## 贏家。
func _check_round_end() -> void:
	if not _is_host_authority:
		return
	var alive_teams := {}
	for participant_id in participants:
		var participant: BattleParticipant = participants[participant_id]
		if not participant.is_eliminated and not participant.is_disconnected:
			alive_teams[participant.team_index] = true
	if alive_teams.size() <= 1:
		var winning_team := -1
		for team in alive_teams:
			winning_team = team
		print("[Sync] _check_round_end -> winning_team=%d" % winning_team)
		apply_round_end(winning_team)

## 套用回合結束結果——權威裝置自己算完直接呼叫;非權威裝置收到網路廣播後
## 也呼叫這個,兩邊看到的是同一個 winning_team,不會各自判定出不同結果。
func apply_round_end(winning_team: int) -> void:
	if is_round_over:
		return
	is_round_over = true
	round_ended.emit(winning_team)
