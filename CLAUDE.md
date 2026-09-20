# 俄羅斯方塊對戰 (Tetris Battle)

跟 cube-combat 是兩個完全獨立的 Godot 專案（各自的 git repo、各自的
Claude Code 對話記錄/memory、各自的 .mcp.json），只有連線對戰的骨架
（NetworkManager/RemoteConnect/PlayitClient/RoomLobby/MultiplayerLobby）
是從 cube-combat 移植過來的起點，見下方「WiFi 連線對戰」一節。

## Godot AI Bridge Connection

Before doing any live-editor work in Godot (scene inspection, node edits,
running scenes, runtime diagnostics), connect first:

```
godot_connect {}
```

- The "Godot AI Bridge" plugin (`tetris-battle/addons/godot_ai_bridge`) is
  set to auto-enable on project load, so it's already listening on
  **`ws://127.0.0.1:6551`** (not 6550 — deliberately different from
  cube-combat's port so both editors can run at the same time without
  colliding) whenever the Godot 4.7.1 editor has this project open.
- This project's `.mcp.json` points the `godot-mcp` server at this
  project's own path with `--port 6551` to match.
- Connecting does not happen automatically just because Godot and VS Code
  are open — it requires an explicit `godot_connect` call from within a
  Claude Code conversation. Do this as the first step of any task that
  touches the live editor.
- If `godot_connect` fails, the Godot editor likely isn't running yet, or
  the plugin got disabled — fall back to file-based tools
  (`godot_read_scene`, `godot_write_script`, `godot_write_shader`, etc.)
  and say so explicitly rather than assuming live state.
- Use the `godot-interactive` skill for the full live-editor workflow
  (session reuse, refresh/save rules, validation before running).

## Research Before Building Or Fixing

Before implementing a new system, or fixing a non-trivial bug, search
first (WebSearch, GitHub) for existing resources, libraries, or write-ups
that already solve the same problem — especially for:

- Godot shader effects (post-processing, VFX)
- Common gameplay systems (state machines, save/load, scoring, etc.)
- Tetris-specific mechanics (SRS rotation system, 7-bag randomizer, lock
  delay, kick tables) — these have well-documented standard algorithms,
  don't reinvent them from scratch
- Bugs whose root cause is likely a known engine quirk or common pitfall,
  not something unique to this project

Prefer adapting a proven, well-tested approach over writing one from
scratch — but adapt it to this project's actual conventions (Godot
Shading Language, not raw GLSL; this project's existing script/scene
structure), don't paste code in unmodified.

## WiFi 連線對戰（重點功能）

這是這個專案的重點功能：同 WiFi 區網直連對戰，遠端（不同網路）也能連
——這兩條路徑的連線骨架已經從 cube-combat 移植過來、可以完整跑通「開房
→ 搜尋 → 加入 → 準備 → 開始 → 進場景」，但**盤面對戰本身的同步邏輯還沒
有實作**，需要新設計。

已經移植、可直接用的部分：

- `Script/NetworkManager.gd`（autoload）— 開房/加入房間、UDP 區網廣播
  搜尋房間、密碼保護、人數上限、房主權限（含「電腦當無頭橋接站、房主
  身分由遠端手機認領」這個進階情境）、準備狀態同步、開始/結束比賽、
  RTT 量測（`ping()`/`ping_measured` 訊號）。用的 port 是 `GAME_PORT
  = 8920`／`DISCOVERY_PORT = 8921`，刻意跟 cube-combat 的 8910/8911
  錯開，避免兩個專案同時在同一個區網跑時互相偵測到對方的房間。
- `Script/RemoteConnect.gd` + `Scenes/RemoteConnect.tscn` — 不同網路
  的連線畫面（透過 `PlayitClient.gd` 建立 playit.gg 通道）。
- `Script/PlayitClient.gd`（autoload）— playit.gg API 用戶端，`
  LOCAL_TUNNEL_PORT` 已同步改成 8920，跟 `NetworkManager.GAME_PORT`
  一致。
- `Script/RoomLobby.gd` + `Scenes/RoomLobby.tscn` — 房間等候畫面（房名
  /人數上限/地圖/密碼/準備狀態/開始按鈕）。
- `Script/MultiplayerLobby.gd` + `Scenes/MultiplayerLobby.tscn` — 開房
  設定/搜尋房間列表畫面。
- `Script/NetworkSnapshotBuffer.gd` — 給位置類資料用的內插緩衝工具類別
  （取樣時間戳 + 內插），還沒有任何呼叫端在用，是移植過來的通用工具。
- `Script/MobileLineEditHelper.gd` — 手機上 LineEdit 輸入框的輔助行為
  （RemoteConnect.gd 的位址/代碼輸入用得到）。

刻意沒有移植的部分（cube-combat 專屬，這個專案用不到）：子彈廣播、命中
判定 host 權威、環境方塊生成/摧毀/權威交接、化身(RemoteAvatar)/子彈
(RemoteBullet) 同步顯示——這些是方塊對戰的戰鬥系統，俄羅斯方塊需要的是
「雙方盤面（含目前下落的方塊/下一個方塊/已消行數）要不要同步、多久同步
一次、對手畫面要不要做成簡化預覽」這種完全不同的同步模型，之後要重新
設計，可以參考 `NetworkManager.gd` 裡現成的「client 請求 → host 驗證 →
host 廣播」RPC 慣例（`update_room_settings()`/`start_match()` 是最簡單
的範例）。

`Scenes/Board.tscn` 目前是空白佔位場景（`NetworkManager.MATCH_SCENE_
PATH` 指向這裡）——連線骨架已經能把雙方一起送進這個場景，真正的俄羅斯
方塊盤面畫面/邏輯還沒開始做。

更新頻率／延遲相關的既有機制：`NetworkManager.ping()` 已經有 RTT 量測
可用（`ping_measured(rtt_msec)` 訊號），之後設計盤面狀態廣播頻率時可以
直接拿來動態調整，不用憑感覺猜。
