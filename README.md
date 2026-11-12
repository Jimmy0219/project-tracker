# project-tracker

追蹤各專案在 Claude Code 裡的進度的 macOS 小工具。每個專案一份 `PROGRESS.md`，由 Claude 在完成任務時更新；Project Tracker 即時監看這些檔案，在選單列與主視窗顯示「目標、現在、任務、等你決定、紀錄」，並顯示 Claude 是否正在工作。

```
匯入說明 md ──丟給──▶ 專案的 Claude Code ──建立──▶ PROGRESS.md（專案根目錄）
                                │                         │
                    CLAUDE.md 加入回報規則            拖進 Project Tracker
                                │                         │
                 之後每完成一項任務就更新 ───────────▶ 即時顯示（＋Claude 工作中燈號）
```

## 使用流程

1. **丟給 Claude**：在 App 的「匯入說明」把 `import-guide.md` 拖進該專案的 Claude Code 對話框（或複製全文貼上）
2. **Claude 建檔**：Claude 依說明分析專案文件、git 紀錄、過去對話與程式碼 TODO，在專案根目錄建立 `PROGRESS.md`，並在專案的 `CLAUDE.md` 加入「每完成一項就更新」的規則
3. **拖回來**：把 `PROGRESS.md`（或專案資料夾）拖進 Project Tracker 的主視窗或選單列面板
4. **之後**：照常用 Claude Code 開發；每完成一項任務 Claude 就會更新 `PROGRESS.md`，App 立刻反映

## 介面

- **選單列面板（預覽）**：每個專案一張卡片——名稱、Claude 工作中燈號、任務進度、下一步、等你決定的數量；點卡片打開主視窗
- **主視窗（編輯）**：左側專案清單（搜尋、拖入匯入）；右側上方是「目標」「現在」各一句，下方是「任務」（第一個未完成的標成「下一步」）、「等你決定」、「紀錄」
  - 任務可勾選、新增、雙擊編輯、刪除；超過 20 字會提醒
  - 「等你決定」按「回答」寫下決定：問題移除、決定變成下一步任務並記入紀錄，Claude 下次開工就會照做
  - 狀態可設為進行中／暫停／完成；「停止追蹤」只從清單移除，不會刪除檔案
- **Claude 工作中燈號**：監看 `~/.claude/projects/` 下該專案的對話紀錄，最近 2 分鐘有動作就亮綠燈（不呼叫 API、不花費額度）
- 主視窗可調整大小、記住位置；開著時出現在 Dock，關掉後回到只在選單列

## PROGRESS.md 格式

```markdown
---
project: 專案名稱
status: in_progress        # in_progress / paused / done
---

## 目標
一句話

## 現在
一句話

## 任務
- [x] 已完成
- [ ] 下一步（第一個未完成）
- [ ] 之後要做的

## 等你決定
- 需要你回答的問題？

## 紀錄
- 2026-01-01 12:00 發生了什麼
```

每一項建議 20 字以內。完整的格式與規則寫在 `templates/import-guide.md`，可以在 App 的「匯入說明」裡修改。

## 系統需求與安裝

- macOS 14 以上（在 macOS 15 Sequoia、M1 上開發）
- Command Line Tools（`xcode-select --install`），需要 `swiftc`
- [Claude Code](https://claude.com/claude-code)

```bash
git clone https://github.com/Jimmy0219/project-tracker.git ~/Desktop/project-tracker
cd ~/Desktop/project-tracker
scripts/install.sh
```

安裝腳本會放入匯入說明（`~/.project-tracker/import-guide.md`，已存在則保留你的版本）、清除舊版（v0.x）留下的全域規則／Stop hook／ptrack，然後編譯並安裝 `~/Applications/Project Tracker.app`。開機自動啟動：選單列面板齒輪 →「登入時啟動」。

> - **首次編譯很慢**：Command Line Tools 要先建立 Foundation／SwiftUI 的模組快取，8GB M1 上可能要數分鐘
> - **`redefinition of module 'SwiftBridging'`**：舊版 Command Line Tools 殘留檔造成，`build-app.sh` 會自動繞過；根治可執行 `sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap`
> - **看不到選單列圖示**：Ice／Bartender 等工具可能把它收進隱藏區，請拖到顯示區；或從 Spotlight 打開 App 使用主視窗

## 資料位置

| 位置 | 內容 |
| --- | --- |
| `<專案>/PROGRESS.md` | 專案進度（由 Claude 與 App 共同編輯） |
| `<專案>/CLAUDE.md` | 回報規則（由 Claude 依匯入說明加入） |
| `~/.project-tracker/tracked.json` | 追蹤中的 PROGRESS.md 路徑清單 |
| `~/.project-tracker/import-guide.md` | 匯入說明（可在 App 修改） |

## 專案結構

```
Sources/ProjectTracker/
  App.swift              進入點、選單列徽章、主視窗控制
  Store.swift            追蹤清單、即時監看（FSEvents）、Claude 活動燈號、寫回
  Document.swift         PROGRESS.md 讀寫模型（只改寫被編輯的區段）
  Parser.swift           轉成顯示用資料
  Models.swift           資料模型
  MenuPreview.swift      選單列預覽、右鍵選單、設定
  MainWindow.swift       主視窗側欄（拖入匯入、搜尋）
  EditorView.swift       編輯區
  ImportGuideView.swift  匯入說明頁（可拖曳檔案給 Claude）
  Components.swift       共用元件與配色
templates/import-guide.md  預設匯入說明
scripts/build-app.sh       用 swiftc 編譯並打包 .app
scripts/install.sh         安裝與清除舊版
scripts/make-icon.swift    繪製 App 圖示
```

## 解除安裝

```bash
pkill -x ProjectTracker; rm -rf ~/Applications/Project\ Tracker.app ~/.project-tracker
```

各專案裡的 `PROGRESS.md` 與 `CLAUDE.md` 回報規則可視需要自行保留或刪除。

## 授權

MIT
