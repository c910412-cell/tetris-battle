## SRS（Super Rotation System）方塊形狀與 wall kick 資料表。
## 純資料 + 靜態查表函式，不依賴場景樹。
## blockdrop/tetris-godot 兩個參考專案都沒有附授權條款，這裡刻意不搬它們的
## 程式碼或資料表，改成依照公開的 Tetris Guideline SRS 規格自己重新推導座標，
## 只是概念上延用「查表式 5-kick」這個標準做法（見 CLAUDE.md「Research Before
## Building」——SRS/7-bag 是公開標準演算法，不用也不該重新發明）。
class_name TetrisPieceData
extends RefCounted

enum PieceType { I, O, T, S, Z, J, L }

const ALL_PIECES: Array[PieceType] = [
	PieceType.I, PieceType.O, PieceType.T, PieceType.S,
	PieceType.Z, PieceType.J, PieceType.L,
]

## 每種方塊在 4 個旋轉狀態（0=spawn, 1=R, 2=180, 3=L）下佔用的格子座標。
## 座標系統：y 向下為正（跟 TetrisBoard 的格子座標一致），每種方塊的
## bounding box 大小在 4 個旋轉狀態間固定（I/O 是 4x4，其餘是 3x3），
## 這樣旋轉時只需要平移方塊「位置」而不用重新量測外框。
const _SHAPES: Dictionary = {
	PieceType.I: [
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
		[Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)],
		[Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)],
	],
	PieceType.O: [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
	],
	PieceType.T: [
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	],
	PieceType.S: [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	],
	PieceType.Z: [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)],
	],
	PieceType.J: [
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	],
	PieceType.L: [
		[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)],
	],
}

## 每種方塊的顯示顏色（guideline 慣用配色），畫面層直接查表使用。
const COLORS: Dictionary = {
	PieceType.I: Color(0.0, 0.85, 0.85),
	PieceType.O: Color(0.9, 0.85, 0.0),
	PieceType.T: Color(0.7, 0.0, 0.85),
	PieceType.S: Color(0.0, 0.85, 0.0),
	PieceType.Z: Color(0.85, 0.0, 0.0),
	PieceType.J: Color(0.0, 0.3, 0.9),
	PieceType.L: Color(0.9, 0.5, 0.0),
}

## 垃圾行（TetrisBoard.GARBAGE_CELL）的顯示顏色——白色，跟一般方塊的彩色
## 區分開，玩家一眼就能認出哪些是被攻擊疊上來的（見對戰規格第 7 節）。
const GARBAGE_COLOR := Color(0.85, 0.85, 0.85)

## JLSTZ 共用 wall kick 表（O 型不需要 kick，I 型另有專屬表，位移幅度不同）。
## key 是 "from>to"（旋轉狀態 0..3），value 是 5 組候選位移，第一組固定是
## (0,0)（不 kick 直接轉）。
const _KICKS_JLSTZ: Dictionary = {
	"0>1": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)],
	"1>0": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2)],
	"1>2": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2)],
	"2>1": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)],
	"2>3": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)],
	"3>2": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(-1, -2)],
	"3>0": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(-1, -2)],
	"0>3": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)],
}

const _KICKS_I: Dictionary = {
	"0>1": [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, -1), Vector2i(1, 2)],
	"1>0": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, 1), Vector2i(-1, -2)],
	"1>2": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, 2), Vector2i(2, -1)],
	"2>1": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, -2), Vector2i(-2, 1)],
	"2>3": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, 1), Vector2i(-1, -2)],
	"3>2": [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, -1), Vector2i(1, 2)],
	"3>0": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, -2), Vector2i(-2, 1)],
	"0>3": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, 2), Vector2i(2, -1)],
}

static func get_cells(type: PieceType, rotation: int) -> Array[Vector2i]:
	var states: Array = _SHAPES[type]
	var cells: Array[Vector2i] = []
	for c in states[posmod(rotation, 4)]:
		cells.append(c)
	return cells

static func get_wall_kicks(type: PieceType, from_rot: int, to_rot: int) -> Array[Vector2i]:
	if type == PieceType.O:
		return [Vector2i.ZERO]
	var key := "%d>%d" % [posmod(from_rot, 4), posmod(to_rot, 4)]
	var table: Dictionary = _KICKS_I if type == PieceType.I else _KICKS_JLSTZ
	var kicks: Array = table.get(key, [Vector2i.ZERO])
	var result: Array[Vector2i] = []
	for k in kicks:
		result.append(k)
	return result
