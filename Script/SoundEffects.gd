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
extends Node

const MOVE_SOUND: AudioStream = preload("res://Sound/移動音效.wav")
const HARD_DROP_SOUND: AudioStream = preload("res://Sound/快速落下.mp3")
const LINE_CLEAR_SOUND: AudioStream = preload("res://Sound/方塊消除.mp3")
const BUTTON_SOUND: AudioStream = preload("res://Sound/按按鈕.wav")

const POOL_SIZE := 8

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
	var player := _players[_next_player_index]
	_next_player_index = (_next_player_index + 1) % _players.size()
	player.stream = stream
	player.play()
