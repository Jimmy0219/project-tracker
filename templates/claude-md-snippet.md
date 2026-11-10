<!-- project-tracker:begin -->
## 專案進度追蹤（project-tracker）

每個專案的進度集中存放在 `~/.project-tracker/projects/`，由選單列 App 即時顯示，讓不同 session 的 agent 能接手。

- **開工時**：執行 `ptrack file` 取得本專案進度檔路徑；檔案存在就先讀它，了解目前狀態、下一步與卡關事項。
- **收工前**（這次有修改專案檔案時必做）：
  1. 檔案不存在就先執行 `ptrack init`。
  2. 編輯進度檔，更新「目前狀態」「下一步」「待辦」「卡關／待決事項」（沒有就寫「（無）」），並視情況調整 frontmatter 的 `status`：`in_progress`／`blocked`／`paused`／`done`。
     - 待辦標記：`- [ ]` 未完成；**你完成的項目標 `- [?]`（待使用者確認），不要自己標 `- [x]`**；`- [x]` 代表使用者已確認，不要改回。
     - 使用者在 App 裡寫下的決定會出現在「下一步」開頭（「依使用者決定執行：…」）與「歷程」中，請照做。
  3. 執行 `ptrack log "<一句話描述這次做了什麼>"` 追加歷程。
  4. 執行 `ptrack stamp --agent "Claude Code (<模型名稱>)"`。
- 「下一步」要寫到新的 agent 不看對話紀錄也能直接開工的程度；需要使用者決定的事放進「卡關／待決事項」。
- `ptrack` 不在 PATH 時改用 `~/.project-tracker/bin/ptrack`。
<!-- project-tracker:end -->
