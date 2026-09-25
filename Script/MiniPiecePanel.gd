## HOLD/NEXT 面板裡「儲存/預告的方塊」縮圖——2026-09-25 使用者要求可以自己
## 調縮圖的位置/大小，原本 TetrisBoardRenderer.draw_mini_piece() 裡
## mini_cell 固定寫死 16px、永遠正中央，沒有地方可以調。比照
## PendingDotsAnchor.gd 同一套做法：這個節點掛在 HoldPanel/NextPanel 上，
## 這裡只放兩個 @export 數值，實際畫圖邏輯還是在 TetrisBoardRenderer.gd
## （Battle.gd 呼叫時把這兩個值讀出來傳進去），不要在這裡重複畫圖邏輯。
class_name MiniPiecePanel
extends Control

## 縮圖每一格的像素大小（原本寫死 16）。
@export_range(4.0, 40.0, 1.0) var mini_cell_size: float = 16.0
## 縮圖中心點相對於面板正中央的位移（像素），正值＝往右/往下。
@export var center_offset: Vector2 = Vector2.ZERO
