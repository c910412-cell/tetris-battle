## 觸控/滑鼠共用的操作按鈕。2026-09-21 從 TouchScreenButton（Node2D，沒辦法用
## anchor、也不能放進 Container）改成 TextureButton（Control）——場景要改成
## Control+anchor/container 真的排版，TouchScreenButton 完全不吃這套，必須換
## 成 Control 系的按鈕才能在編輯器裡用錨點/容器排版、即時預覽。
## button_down/button_up 是 BaseButton 內建訊號，觸控（InputEventScreenTouch）
## 跟滑鼠都會觸發，語意跟原本 TouchScreenButton 的 pressed/released 完全對應
## （按下開始、放開結束，DAS/ARR 那種「按住持續」的操作靠這個）；
## project.godot 的 pointing/emulate_touch_from_mouse 也還是保留給其他純
## Node2D 輸入用，不影響這裡（Control 本來就原生吃兩種輸入來源）。
## 沒有指定 texture_normal 時退回程式產生的簡單圓形，方便替換美術素材前
## 場景還能看、還能測——把 texture_normal 設成真的貼圖之後這個 fallback
## 就不會啟動。
extends TextureButton

@export var input_action: String = ""
@export var button_color: Color = Color(1, 1, 1, 0.22)

## 沒貼圖時，fallback 圓形要烤幾 px——固定烤高解析度、靠 stretch_mode 縮放
## 成節點實際的錨點尺寸，兩者脫鉤，這樣不管你把節點錨點/尺寸調多大，圓形
## 都不會糊。
const FALLBACK_TEXTURE_SIZE := 240

## 按下時的視覺回饋——2026-09-21 使用者接上真的美術素材後改用這個：素材只有
## 一張（沒有另外畫「按下」狀態），用 modulate 稍微變暗代表按下，比另外生成
## 一張圓形貼圖蓋掉原本圖案（會整個換成別的形狀，很奇怪）合理。fallback
## 圓形沒貼圖時也走同一條路，不用兩套邏輯。
const PRESSED_MODULATE := Color(0.7, 0.7, 0.7)

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_SCALE
	if texture_normal == null:
		texture_normal = _make_circle_texture(button_color)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)

func _on_button_down() -> void:
	modulate = PRESSED_MODULATE
	if input_action != "":
		Input.action_press(input_action)

func _on_button_up() -> void:
	modulate = Color.WHITE
	if input_action != "":
		Input.action_release(input_action)

func _make_circle_texture(color: Color) -> ImageTexture:
	var n := FALLBACK_TEXTURE_SIZE
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var radius := n / 2.0
	var center := Vector2(radius, radius)
	for y in range(n):
		for x in range(n):
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
