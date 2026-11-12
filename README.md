# project-tracker

在 macOS 選單列即時追蹤各專案進度的小工具。開不同的 AI agent session 推進不同專案時，每個 session 收工前會把進度寫進中央資料夾；選單列面板提供快速預覽，主視窗用來編輯，還能一鍵複製「交接 prompt」貼給下一個 agent。

```
Claude Code session ──(收工前更新)──▶ ~/.project-tracker/projects/<專案>.md
        ▲                                         │ FSEvents 即時監聽
   Stop hook 檢查：                                ▼
   改了專案檔案卻沒更新進度 → 要求補寫     選單列 App（SwiftUI MenuBarExtra）
```

## 功能

- **自動收集**：全域 `CLAUDE.md` 規則要求 agent 收工前更新進度；Stop hook 會檢查這次 session 是否用編輯工具改過專案檔案，改了卻沒更新進度檔就擋下，要求補寫
- **中央彙整**：進度檔集中放在 `~/.project-tracker/projects/`，專案資料夾不會多出任何檔案
- **選單列即時顯示**：每個專案顯示狀態、待辦完成度、下一步、卡關事項、最後更新時間與 agent；超過 7 天沒更新的進行中專案會以橘色標示時間
- **待決徽章**：有卡關／待決事項時，選單列圖示旁會顯示數字
- **一鍵交接**：「複製交接 prompt」會把目前狀態、下一步、未完成待辦、卡關與最近歷程組成一段文字，直接貼給新的 agent

### 兩種介面：選單列預覽＋主視窗編輯

- **選單列面板＝唯讀預覽**：每個專案只顯示狀態、進度條、第一個下一步與待決／待確認數量；點卡片就在主視窗打開該專案
- **主視窗＝編輯區**：左側專案清單（可搜尋、新增，右鍵快速操作），右側是寬版編輯區；寬度夠時分成兩欄（左：目前狀態、下一步、卡關；右：待辦、歷程）
- 主視窗可自由調整大小、拖到任何螢幕，下次打開會記得位置；開著時 App 會出現在 Dock 與 ⌘Tab，關掉後回到只在選單列待命
- 從 Finder／Spotlight 打開 App 會直接顯示主視窗；設定「登入時啟動」時開機只會待在選單列

### 行前檔：匯入既有專案時自動整理進度

- **行前檔**（`~/.project-tracker/onboarding.md`）是給 Claude 的匯入指引：要看哪些來源、怎麼歸納、寫成什麼格式、有哪些規則。主視窗側欄最下方「行前檔」可直接編輯（⌘S 儲存、可還原預設）
- 在主視窗「新增專案」選資料夾後，App 會在背景執行 `ptrack onboard`：Claude Code（`claude -p`）讀行前檔，從**專案文件、git 紀錄、過去的 Claude Code 對話與 memory、程式碼裡的 TODO／FIXME** 歸納出目前狀態、下一步、待辦、卡關與歷程，寫入進度檔
- 整理中會在側欄、選單列與編輯區顯示狀態；完成後顯示 Claude 的回報。推測完成的待辦標成 ⏳ 待確認、不確定的事放進「卡關／待決事項」，方便你核對
- 已追蹤的專案可從「更多」或右鍵選「用行前檔重新整理」；整理紀錄存在 `~/.project-tracker/logs/`
- **權限限制**：匯入用的 Claude 以 `--permission-mode dontAsk` 執行，只允許讀取（Read／Glob／Grep、唯讀的 git／ls／jq 等指令）與寫入**該專案的進度檔**；不會修改專案檔案，也不會留下 session 紀錄
- 需要能在終端機正常使用的 Claude Code；若出現 401／token 過期，執行 `claude auth login` 重新登入

### 在主視窗裡編輯

- **分段顯示**：目前狀態、下一步、待辦、卡關／待決事項、歷程各自成塊，有專屬顏色與圖示（側欄與選單列的小標籤用同樣配色）
- **每一段都能新增、編輯、刪除**：按區段右上角的 ＋ 新增（Enter 送出、可連續新增、Esc 取消）；雙擊項目或滑過後按 ✏️ 編輯；滑過按 🗑 刪除
- **待辦勾選與「待確認」**：agent 做完的待辦會標成 `- [?]`（⏳ 待確認），你按「確認」才算完成，或按「退回」改回未完成；也有「全部確認」
- **處理卡關**：每個待決事項可以按「已解決」，或按「決定…」寫下你的決定。決定會放到「下一步」第一項並寫進歷程，下一個 agent 就會照做
- **改狀態、改名**：右上角「變更狀態」；按名稱旁的 ✏️ 或雙擊名稱可改名
- **管理追蹤的專案**：側欄「新增專案」選資料夾就能新增；專案右鍵可改狀態、複製交接 prompt、在 Finder 顯示、停止追蹤
- **停止追蹤**：進度檔移到垃圾桶（可救回），資料夾加入忽略清單，Claude Code 不會再要求為它更新

App 寫入時會「重新讀檔 → 只改動被編輯的區段 → 原子寫回」，盡量避免和正在收工的 agent 互相覆蓋。

## 系統需求

- macOS 14 以上（在 macOS 15 Sequoia、M1 上開發與測試）
- Xcode 或 Command Line Tools（`xcode-select --install`），需要 `swiftc`
- `python3`（只用標準函式庫）、`jq`（`brew install jq`）
- [Claude Code](https://claude.com/claude-code)

## 安裝

```bash
git clone https://github.com/Jimmy0219/project-tracker.git ~/Desktop/project-tracker
cd ~/Desktop/project-tracker
scripts/install.sh
```

安裝腳本會：

1. 把 `ptrack` 複製到 `~/.project-tracker/bin/`，並在 `~/.local/bin/` 建立連結
2. 在 `~/.claude/CLAUDE.md` 加入進度追蹤規則（以 `<!-- project-tracker:begin/end -->` 包住，重複執行會覆蓋而不會重複）
3. 在 `~/.claude/settings.json` 註冊 Stop hook（修改前自動備份成 `settings.json.bak.<時間>`）
4. 編譯 App、安裝到 `~/Applications/Project Tracker.app` 並啟動

參數：`--no-app` 只裝 CLI／規則／hook；`--no-hook` 不修改 `settings.json`。

想開機自動啟動：點選單列面板右上角齒輪 →「登入時啟動」。

> 有用 Ice／Bartender 等選單列管理工具的話，新圖示可能被收進隱藏區，請手動拖到顯示區；或直接從 Spotlight 打開 App 使用主視窗。

> **首次編譯很慢？** Command Line Tools 需要先把 Foundation／SwiftUI 編進模組快取，在 8GB 的 M1 上可能要好幾分鐘，之後就快了。
>
> **出現 `redefinition of module 'SwiftBridging'`？** 這是舊版 Command Line Tools 殘留檔造成的，`build-app.sh` 會自動繞過。想根治可執行
> `sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap`（新版的 `bridging.modulemap` 內容相同）。

## 進度檔格式

`~/.project-tracker/projects/<資料夾名稱>-<路徑雜湊>.md`，Markdown + YAML frontmatter：

```markdown
---
project: 人工智慧導論期中期末報告
path: /Users/me/Desktop/人工智慧導論＿期中期末報告
status: in_progress        # in_progress / blocked / paused / done
agent: Claude Code (Opus 5.5)
updated: 2026-11-10T21:30:00+08:00
---

## 目前狀態
RAG 檢索模組完成，正在調整 chunk 大小。

## 下一步
- 用 50 題測試集跑檢索準確率

## 待辦
- [x] 建立向量資料庫
- [ ] 評估檢索準確率

## 卡關／待決事項
- 需要決定 embedding 模型要用本機還是 API

## 歷程
- 2026-11-10 21:30 完成 RAG 檢索模組
```

- 待辦有三種標記：`- [ ]` 未完成、`- [?]` agent 回報完成（待使用者確認）、`- [x]` 使用者已確認；完成度只計算 `- [x]`
- 選單列徽章數字 = 卡關／待決事項 + 待確認待辦（暫停與已完成的專案不計）
- 「卡關／待決事項」每一項都會計入選單列徽章；寫「（無）」代表沒有
- 「（…）」整行括號的文字視為佔位內容，不會顯示
- 最後更新時間取檔案修改時間與 `updated` 欄位中較新者

## ptrack 指令

| 指令 | 說明 |
| --- | --- |
| `ptrack file [路徑]` | 印出專案進度檔的路徑 |
| `ptrack init [路徑] [--name 名稱]` | 建立進度檔（已存在則不動） |
| `ptrack log [路徑] 訊息` | 在「歷程」追加一行，自動加時間 |
| `ptrack stamp [路徑] [--agent 名稱]` | 更新 `updated`／`agent` 欄位 |
| `ptrack list` | 列出所有追蹤中的專案 |
| `ptrack root [路徑]` | 印出判定的專案根目錄 |
| `ptrack onboard [路徑] [--model M] [--print]` | 依行前檔請 Claude 整理既有進度並寫入進度檔；`--print` 只印出 prompt |
| `ptrack hook-stop` | Claude Code Stop hook 入口（從 stdin 讀 JSON） |

`[路徑]` 省略時使用目前目錄；位於 git repo 內時以 repo 根目錄為專案。

## 設定

- **忽略資料夾**：家目錄、`~/Desktop`、`~/Documents`、`~/Downloads`、`/tmp` 預設不當成專案。其他路徑可寫進 `~/.project-tracker/ignore`，一行一個，結尾加 `/*` 代表連子資料夾一起忽略
- **暫時停用 hook**：啟動 Claude Code 前設定環境變數 `PTRACK_DISABLE=1`
- **自訂資料位置**：環境變數 `PTRACK_HOME`（CLI 與 App 都會讀）

## 限制

- Stop hook 只偵測 Edit／Write／MultiEdit／NotebookEdit 工具的修改；只用 Bash 改檔案的 session 不會被提醒（全域規則仍會要求 agent 更新）
- 網頁版／雲端的 Claude Code session 無法寫入本機檔案，目前只支援本機 session
- 目前只針對 Claude Code；其他 agent 只要照同樣格式寫進度檔，App 一樣能顯示
- 在 App 裡編輯某個區段時，該區段會以標準格式重寫：清單型區段（下一步、待辦、卡關）裡非清單的散文會被移除，其他區段不受影響

## 專案結構

```
bin/ptrack                      CLI 與 Stop hook（Python 標準函式庫）
Sources/ProjectTracker/         SwiftUI 選單列 App
  App.swift                     進入點、選單列徽章、主視窗控制（AppKit NSWindow）
  Store.swift                   FSEvents 監聽、載入、編輯／新增／停止追蹤
  Document.swift                進度檔的讀寫模型（保留未知區段，只改寫被編輯的區段）
  Parser.swift                  轉成顯示用資料、清單與待辦解析
  Models.swift                  資料模型（專案狀態、待辦三態）
  MainWindow.swift              主視窗：側欄清單（搜尋、新增）
  EditorView.swift              主視窗編輯區：頁首與各區段的編輯功能
  MenuPreview.swift             選單列唯讀預覽、右鍵選單、設定
  OnboardingBriefView.swift     行前檔編輯器
  Components.swift              共用元件（區段框、可編輯列、新增欄位、配色）
  Handoff.swift                 交接 prompt 產生
Resources/Info.plist            App 設定（LSUIElement：不顯示在 Dock）
Resources/AppIcon.icns          App 圖示（由 scripts/make-icon.swift 產生）
templates/claude-md-snippet.md  寫入 ~/.claude/CLAUDE.md 的規則
templates/onboarding.md         預設行前檔（安裝時複製到 ~/.project-tracker/onboarding.md）
scripts/build-app.sh            用 swiftc 編譯並打包 .app
scripts/install.sh              一鍵安裝
scripts/make-icon.swift         用程式繪製 App 圖示並輸出 iconset
```

重新產生圖示：

```bash
swiftc scripts/make-icon.swift -o build/make-icon && build/make-icon build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

## 解除安裝

```bash
pkill -x ProjectTracker; rm -rf ~/Applications/Project\ Tracker.app ~/.local/bin/ptrack
```

再手動移除 `~/.claude/CLAUDE.md` 中 `project-tracker:begin/end` 之間的區塊，以及 `~/.claude/settings.json` 裡的 `ptrack hook-stop` hook。進度資料在 `~/.project-tracker/`，要保留或刪除都可以。

## 授權

MIT
