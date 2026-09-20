extends RefCounted
class_name NetworkSnapshotBuffer

## 【2026-09-13，見連線效能討論／docs/adr/0020】給 RemoteAvatar/RemoteBullet
## 共用的「快照內插」緩衝——取代原本兩邊各自的 lerp(當前值, 最新收到的值)。
##
## 原本的做法只會朝「最新收到的一筆」追趕，發送端（不管是手機還是 PC）只要
## 幀率一不規律，這裡收到新資料的時間點就跟著不規律，畫面上看起來就是頓挫的
## ——單靠接收端調 lerp 係數救不回一個本身就不規律的輸入訊號。
##
## 改成比照 Minecraft 這類遊戲的做法：接收端永遠刻意晚一點點（RENDER_DELAY_
## MSEC）顯示，在「已經收到的兩筆快照之間」內插，而不是追向最新那一筆——這樣
## 不管封包送達的時間點多不規律，只要兩筆快照之間的間隔還在合理範圍內，內插
## 出來的畫面永遠是平滑的等速移動，把「模擬/網路多不穩定」跟「畫面看起來順不
## 順」徹底切開。代價是固定多了這一點點顯示延遲，對「看著螢幕上跑來跑去的別人
## /別人的子彈」這種用途感覺不出來（不是在幫對方瞄準這種需要零延遲的場合）。
##
## 用接收端自己的本機時間戳（Time.get_ticks_msec()）當快照時間，不用發送端
## 時間戳——這是區網對等連線（沒有專用伺服器、沒有做時鐘同步）最簡單可靠的
## 做法，見 docs/adr/0005：不架設專用伺服器。

const MAX_SNAPSHOTS := 8

var _snapshots: Array[Dictionary] = []


## data 是呼叫端自訂的欄位（例如 {"pos": Vector3, "rot_y": float}），這個
## 緩衝完全不關心裡面放什麼，只負責記錄「收到的時間點＋內容」跟事後內插。
func push(data: Dictionary) -> void:
	_snapshots.append({"t": Time.get_ticks_msec(), "data": data})
	if _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


## 【2026-09-19，見「放開方塊時本機畫面閃一下」的調查】權威易主時呼叫——
## 從「本機是權威」變成「本機不是權威、改看廣播」的那一刻，緩衝裡如果還
## 留著上一次當權威之前（可能是很久以前）收到的舊快照，sample() 會直接
## 把這份過期資料當「最新」拿出來顯示，畫面上就是瞬間跳回一個舊位置，等
## 新的廣播抵達才跳回來——本機當權威期間完全不會收到自己這顆的廣播（見
## push() 只在收到廣播時被呼叫），緩衝在那整段期間只會越放越舊，不會
## 自然過期或被覆蓋掉。清空之後 sample() 在新資料抵達前只會回傳空字典，
## 呼叫端（AmmoCube._physics_process()）看到空字典就什麼都不做，維持原地
## 不動，不會顯示過期位置。
func clear() -> void:
	_snapshots.clear()


## 回傳 {"a": Dictionary, "b": Dictionary, "t": float} 讓呼叫端自己對 a/b
## 兩筆快照的個別欄位做內插（Vector3.lerp／lerp_angle／Quaternion.slerp
## 各自的內插方式不一樣，這裡不假設欄位長什麼樣子）。t 是 0~1 的內插比例。
## 緩衝完全沒有資料時回傳空字典，呼叫端要自己判斷跳過。
func sample(delay_msec: int) -> Dictionary:
	if _snapshots.is_empty():
		return {}
	if _snapshots.size() == 1:
		# 只有一筆，沒有兩筆可以內插，沒得選——就顯示這一筆。
		return {"a": _snapshots[0]["data"], "b": _snapshots[0]["data"], "t": 0.0}
	var render_time := Time.get_ticks_msec() - delay_msec
	# 【2026-09-17，見剛生成方塊抓取回溯 bug 的調查】暖機期（剛開始收資料，
	# 累積的時間跨度還不到一個延遲量）：改用「目前收到的最新一筆」而不是
	# 最舊那筆——用最舊那筆會讓畫面卡在一個已經過期的位置不動（例如方塊
	# 剛生成、還沒累積滿 120ms 資料時就被抓走，抓取當下畫面停在生成瞬間的
	# 位置，等緩衝之後補上真實資料才「追趕」過去，看起來像是抓取瞬間回溯
	# 又追上手的快速來回跳動）。改用最新一筆沒有這個問題：暖機期這極短
	# 一段時間裡沒有平滑內插可言（畢竟才剛開始收資料），與其卡在過期位置，
	# 不如直接跟著最新收到的真實資料走，等資料量夠了自然接回正常的內插。
	if render_time <= _snapshots[0]["t"]:
		# 【2026-09-20，見使用者回報「分裂瞬間觀察端卡頓，FPS沒掉」的調查】
		# 上面這段暖機期判斷本身是對的（見上方說明），但原本的處理方式是
		# 「直接跳到最新一筆」，完全不內插——單顆物件這樣做因為只有一個東西
		# 在跳，不明顯；分裂一次同時有 3 顆子彈同時經歷這段暖機期，3 顆都在
		# 用同一個「收到新資料就瞬間跳過去、中間完全靜止」的節奏更新，疊加
		# 起來就是使用者說的卡頓（FPS 沒掉，因為這不是效能問題，是每次收到
		# 新快照時位置用跳的，不是滑過去的，畫面看起來一格一格頓)。
		# 改成：如果已經收到至少兩筆，改成在「最後兩筆」之間內插（不用
		# render_time 那套延遲基準，直接用即時的 now 對這兩筆的時間差算
		# 比例）——一樣是「跟著最新真實資料走」（不會卡在過期位置，跟原本
		# 修過的 bug 無關），差別只是收到第二筆之後，改成平滑滑過去，不是
		# 瞬間跳過去；超過第二筆的時間點自然夾到 1.0，停在最新位置，等下一筆
		# 抵達再繼續滑，直到資料量夠了自然接回正常的延遲內插（上面的迴圈）。
		if _snapshots.size() < 2:
			var newest: Dictionary = _snapshots[-1]["data"]
			return {"a": newest, "b": newest, "t": 0.0}
		var warmup_a: Dictionary = _snapshots[-2]
		var warmup_b: Dictionary = _snapshots[-1]
		var warmup_span: int = warmup_b["t"] - warmup_a["t"]
		var warmup_frac: float = 1.0 if warmup_span <= 0 else clampf(float(Time.get_ticks_msec() - int(warmup_a["t"])) / float(warmup_span), 0.0, 1.0)
		return {"a": warmup_a["data"], "b": warmup_b["data"], "t": warmup_frac}
	for i in range(_snapshots.size() - 1):
		var s0: Dictionary = _snapshots[i]
		var s1: Dictionary = _snapshots[i + 1]
		if render_time >= s0["t"] and render_time <= s1["t"]:
			var span: int = s1["t"] - s0["t"]
			var frac: float = 0.0 if span <= 0 else float(render_time - int(s0["t"])) / float(span)
			return {"a": s0["data"], "b": s1["data"], "t": frac}
	# render_time 比目前收到最新的一筆還新（封包延遲/漏包、追不上設定的延遲
	# 量）——停在最新那筆，好過用外插硬猜一個可能完全不對的未來位置。
	var last: Dictionary = _snapshots[-1]["data"]
	return {"a": last, "b": last, "t": 0.0}
