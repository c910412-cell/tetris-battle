## 7-bag 隨機出塊順序產生器：每次把 7 種方塊各裝一個進袋子、Fisher-Yates
## 洗牌後依序吐出，保證每 7 個方塊裡每一種都恰好出現一次。
## 用獨立的 RandomNumberGenerator（不是全域 RNG）並支援 set_seed()，是為了
## 之後連線對戰時雙方可以用同一個 match seed 各自重建同一份出塊順序——
## 這輪還沒有網路呼叫端，但介面先留著（見專案 CLAUDE.md：盤面同步是下一輪
## 的獨立設計）。set_fixed_sequence() 是測試/重播用的逃生門，跳過洗牌邏輯。
class_name TetrisPieceRandomizer
extends RefCounted

var _rng: RandomNumberGenerator
var _bag: Array[TetrisPieceData.PieceType] = []
var _fixed_sequence: Array[TetrisPieceData.PieceType] = []
var _using_fixed_sequence: bool = false
var _fixed_index: int = 0

func _init(seed_value: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value
	_bag.clear()
	_using_fixed_sequence = false

func set_fixed_sequence(sequence: Array[TetrisPieceData.PieceType]) -> void:
	_fixed_sequence = sequence.duplicate()
	_fixed_index = 0
	_using_fixed_sequence = true

func get_next_piece() -> TetrisPieceData.PieceType:
	if _using_fixed_sequence:
		var piece: TetrisPieceData.PieceType = _fixed_sequence[_fixed_index % _fixed_sequence.size()]
		_fixed_index += 1
		return piece
	if _bag.is_empty():
		_refill_bag()
	return _bag.pop_front()

## 預覽接下來 N 個方塊，但不能影響之後 get_next_piece() 實際吐出的序列——
## 用 RNG 的 state 存/還原，確保「偷看」不會消耗掉真正要用的隨機數。
func peek_next_pieces(count: int) -> Array[TetrisPieceData.PieceType]:
	var preview: Array[TetrisPieceData.PieceType] = []
	if _using_fixed_sequence:
		for i in range(count):
			preview.append(_fixed_sequence[(_fixed_index + i) % _fixed_sequence.size()])
		return preview

	var saved_state := _rng.state
	var lookahead_bag: Array[TetrisPieceData.PieceType] = _bag.duplicate()
	while preview.size() < count:
		if lookahead_bag.is_empty():
			lookahead_bag = TetrisPieceData.ALL_PIECES.duplicate()
			_shuffle_fisher_yates(lookahead_bag)
		preview.append(lookahead_bag.pop_front())
	_rng.state = saved_state
	return preview

## 給連線對戰斷線重連用：RandomNumberGenerator 本身就有 `.state`（完整內部
## 狀態，peek_next_pieces() 已經在用這個做「偷看不消耗」的把戲），直接存這個
## 加上目前袋子裡還沒吐出的牌，重建出來的序列會跟原本接下去一模一樣，不用
## 自己重播 N 次去「追」到同一個位置。只支援一般模式，不支援
## set_fixed_sequence()（那個是測試/重播專用，不會在真正對戰裡用到）。
func get_snapshot() -> Dictionary:
	return {"rng_state": _rng.state, "bag": _bag.duplicate()}

func load_snapshot(snapshot: Dictionary) -> void:
	_rng.state = snapshot.get("rng_state", _rng.state)
	var bag: Array = snapshot.get("bag", [])
	_bag.assign(bag)
	_using_fixed_sequence = false

func _refill_bag() -> void:
	_bag = TetrisPieceData.ALL_PIECES.duplicate()
	_shuffle_fisher_yates(_bag)

func _shuffle_fisher_yates(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp
