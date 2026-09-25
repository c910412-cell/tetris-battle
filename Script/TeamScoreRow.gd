## 隊伍戰績列（bo-N 星星）——2026-09-25 使用者要求：(1) 原本每隊各佔一行、
## 直的疊起來，改成全部隊伍擠在同一條橫的裡；(2) 後來又要求拿掉隊名文字、
## 只留星星，字體大小要能調、比照 MiniPiecePanel.gd 那套做法：這裡只放一個
## @export 數值，實際生成 Label 的邏輯還是在 Battle.gd
## （_populate_stars_row()），這裡不重複排版邏輯。
##
## 每隊一個星星 Label 動態生成塞進這個 HBoxContainer 裡（見 Battle.gd 的
## 說明），隊伍數量隨對戰人數變動,所以沒辦法像 HoldPanel/NextPanel 那樣
## 場景裡固定排好,只能靠這裡的字體大小設定去控制「生成出來的東西」多大。
## `theme_override_constants/separation`（在 .tscn 裡直接設）負責隊伍跟
## 隊伍之間的間距，跟這裡的字體大小是分開兩件事。
class_name TeamScoreRow
extends HBoxContainer

@export_range(8.0, 60.0, 1.0) var star_font_size: float = 28.0
