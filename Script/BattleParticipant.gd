## 對戰裡的一個參與者（真人玩家或 AI 機器人），純資料+狀態容器，實際規則
## 都在 BattleDirector 裡跑。id 是真人的 peer_id（正數）或
## BattleSettings.AI_IDS 的其中一個（負數）。
class_name BattleParticipant
extends RefCounted

var id: int
var team_index: int
var controller: TetrisGameController
## 真人是 null；AI 才有。
var ai: TetrisAI = null
var is_eliminated: bool = false
## true＝這個參與者的 controller 由「這台裝置」實際模擬（tick 驅動、真的會
## 下方塊）；false＝這個參與者的盤面狀態要靠網路同步取得（見對戰規格：自己
## 操作永遠本機即時，其他人的盤面靠 host 轉發）。本機的真人玩家自己永遠
## is_local=true；AI 只有在「host 權威」那台裝置上才是 is_local=true（AI
## 決策不是逐 tick 都跟其他裝置一致的東西，只能有一台裝置真正模擬它，見
## BattleDirector._init() 的 is_host_authority 參數）；其他真人玩家的參與者
## 在這台裝置上永遠 is_local=false（這次 Milestone 還沒接上真正的網路同步，
## 是 Part C 的事，這裡只先把資料結構跟 tick() 分好）。
var is_local: bool = true
## true＝這個參與者斷線暫停中（見對戰規格：暫停盤面、等重連，team-alive
## 判定要整個排除他，不算存活也不算淘汰）。這次 Milestone 只加欄位跟讓
## BattleDirector 的存活判定會用到它，真正的斷線偵測/重連流程是 Part D 的事。
var is_disconnected: bool = false

## 別人打過來、還沒結算成真垃圾行的缺口欄位佇列（FIFO，依累積順序）。
var pending_garbage: Array = []
## 這個玩家自己消行換算傷害用的餘數進位（見對戰規格：不分現在打誰，一個
## 玩家共用一份）。2026-09-23 改成 float——開啟
## BattleSettings.single_line_counts_as_attack 時單行消行只算 0.5 點攻擊力
## （見 BattleDirector._comeback_adjusted_attack_power()），餘數會出現非整數。
var ratio_remainder: float = 0.0
## 目前這個玩家的攻擊目標（另一個 BattleParticipant 的 id）。
var current_target_id: int = 0
## true 代表 current_target_id 是玩家自己觸控選的（指定目標攻擊開啟時），
## BattleDirector 的隨機重骰計時器要跳過他，直到他選的目標淘汰才強制重選。
var manual_target_locked: bool = false

func _init(participant_id: int, participant_team: int, game_controller: TetrisGameController) -> void:
	id = participant_id
	team_index = participant_team
	controller = game_controller

func is_ai() -> bool:
	return id < 0
