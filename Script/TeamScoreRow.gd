## 隊伍戰績列（bo-N 星星）——2026-09-25 使用者要求：(1) 原本每隊各佔一行、
## 直的疊起來，改成全部隊伍擠在同一條橫的裡；(2) 隊名文字跟星星的字體大小
## 要能分開調，比照 MiniPiecePanel.gd 那套做法：這裡只放兩個 @export 數值，
## 實際生成 Label 的邏輯還是在 Battle.gd（_refresh_stars_display()），這裡
## 不重複排版邏輯。
##
## 每隊一組小 HBoxContainer（隊名 Label + 星星 Label）動態生成塞進這個
## HBoxContainer 裡（見 Battle.gd 的說明），隊伍數量隨對戰人數變動,所以
## 沒辦法像 HoldPanel/NextPanel 那樣場景裡固定排好,只能靠這裡的字體大小
## 設定去控制「生成出來的東西」多大。
class_name TeamScoreRow
extends HBoxContainer

@export_range(8.0, 60.0, 1.0) var name_font_size: float = 24.0
@export_range(8.0, 60.0, 1.0) var star_font_size: float = 28.0
