## 音效系統（autoload）——2026-09-24 新增。使用者提供 4 個音效素材（Sound/
## 資料夾），對應關係（跟使用者逐條確認過）：
##   移動音效  —— 左右移動＋軟降（按住「↓」造成的下降,不含硬降）
##   快速落下.mp3  —— 硬降
##   方塊消除.mp3  —— 消行
##   按按鈕    —— 選單類按鈕（大廳/設定/房間設定/分隊/結算/暫停這些
##                     UI 按鈕），不含核心操作按鈕（移動/旋轉/軟降/硬降/
##                     hold/暫停，這些走 TetrisTouchButton.gd 的觸控輪詢,
##                     使用者明確要求不要加音效,見該檔案開頭的說明)。
## 「移動音效」「按按鈕」原始檔是 .m4a——Godot 4 的內建音訊匯入器只認
## WAV/MP3/Ogg Vorbis 三種，不認 .m4a（AAC），preload() 會失敗,而且因為
## 這個檔案是 autoload、所有場景都要靠它才能啟動,那個失敗的 preload 會讓
## 整個遊戲進程在啟動階段就卡住（實測：不是丟出明確的腳本錯誤,而是連
## 這個自動化測試工具的「執行期連線」都建立不起來,一開始很難判斷是這個
## 原因)。已經用 Windows 內建的 Media Transcoding API 轉成同名 .wav
## （PCM,48kHz),原始 .m4a 檔案還留在資料夾裡沒有刪除,只是程式碼這裡
## 改讀轉檔後的 .wav。
## 用一小池 AudioStreamPlayer 輪流播放（不是只有一個），允許短時間內重疊
## 的音效（例如按住左右移動連續觸發）不會互相打斷、蓋掉前一個還沒播完的。
## 2026-09-25 使用者回報電腦端音效「有時候有、有時候沒有」——最可能的
## 根因：原本是「不管三七二十一,固定輪到下一個位置」的純輪流,如果觸發
## 得夠密集（例如移動音效在 DAS/ARR 很快的設定下,每十幾毫秒就觸發一次,
## 遠比一個音效片段的播放時間短),池子還沒繞完一圈,前一個位置可能都還在
## 播放中——這時候直接把還在播放中的 AudioStreamPlayer 的 stream 換掉、
## 重新 play(),偶爾會讓那次播放悄悄消失（音訊伺服器來不及切換,不是每次
## 都會發生,所以才會「有時候有有時候沒有」)。改成優先選「目前沒在播放」
## 的那個位置,真的全部都在忙才退回輪流（寧可切掉最舊的那個,也不要整個
## 沒聲音）。池子大小也從 8 加到 16，降低密集觸發時全部忙碌的機率。
## 2026-09-24 改成 button_down 觸發後使用者回報「還是有一點延遲」——實際
## 用工具讀 wav 的 PCM 資料量測發現不是訊號時機的問題，是素材檔案本身開頭
## 就錄到一段幾乎無聲的留白（按按鈕.wav 開頭約 305ms、移動音效.wav 開頭約
## 105ms 才出現真正的音量），已經直接把兩個 .wav 檔開頭的留白裁掉（只留
## 8ms 預留、避免切太準造成爆音），聲音內容本身沒有變。之後如果又要重新
## 用素材資料夾裡的 .m4a 轉檔，記得轉完要先確認開頭有沒有留白，不要預設
## 轉出來的檔案開頭就是乾淨的。
extends Node

const MOVE_SOUND: AudioStream = preload("res://Sound/移動音效.wav")
const HARD_DROP_SOUND: AudioStream = preload("res://Sound/快速落下.mp3")
const LINE_CLEAR_SOUND: AudioStream = preload("res://Sound/方塊消除.mp3")
const BUTTON_SOUND: AudioStream = preload("res://Sound/按按鈕.wav")

const POOL_SIZE := 16

var _players: Array[AudioStreamPlayer] = []
var _next_player_index := 0

func _ready() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

func play_move() -> void:
	_play(MOVE_SOUND)

func play_hard_drop() -> void:
	_play(HARD_DROP_SOUND)

func play_line_clear() -> void:
	_play(LINE_CLEAR_SOUND)

func play_button() -> void:
	_play(BUTTON_SOUND)

## 選單類按鈕的呼叫端只要在 _ready() 把自己的 Button/TextureButton 丟進來
## 呼叫一次就好，不用各自接訊號、各自判斷音效開關——音量/開關以後統一從
## 這裡管。2026-09-24 使用者回報音效感覺延遲——根因是 BaseButton 的
## `pressed` 訊號預設在「放開」的那一刻才觸發（action_mode 預設是
## ACTION_MODE_BUTTON_RELEASE，這是 Godot 的標準行為，讓使用者按錯可以
## 滑開取消，不算 bug，但拿來當音效回饋觸發點確實會感覺慢半拍）,改成接
## `button_down`（一按下去、還沒放開就觸發,不受 action_mode 影響)——只換
## 音效的觸發點,呼叫端自己另外接的 `pressed`（真正的按鈕動作，例如切換
## 畫面）完全不受影響,還是放開才生效,不會變成「按下去就誤觸發換畫面」。
func connect_button(button: BaseButton) -> void:
	button.button_down.connect(play_button)

func _play(stream: AudioStream) -> void:
	if not PlayerSettings.sound_effects_enabled:
		return
	var player := _pick_player()
	player.stream = stream
	player.play()

## 優先找一個目前沒在播放的位置（不用搶正在播放中的那個,見上面的說明）；
## 從 _next_player_index 開始找一輪,找到就順便把輪流指標推到它後面一個,
## 維持輪流的公平性。萬一密集到全部都在播放中（極端情況）,退回原本單純
## 輪流的做法,切掉最舊的那個,至少保證有聲音。
func _pick_player() -> AudioStreamPlayer:
	var count := _players.size()
	for offset in range(count):
		var idx := (_next_player_index + offset) % count
		if not _players[idx].playing:
			_next_player_index = (idx + 1) % count
			return _players[idx]
	var player := _players[_next_player_index]
	_next_player_index = (_next_player_index + 1) % count
	return player
