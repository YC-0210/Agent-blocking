# Agent Focus 台灣繁體中文

Branch: `codex/agent-zh-tw`. Worktree: `DOCard-ios-zh-tw`.
Base: integration `bafd12b`. This branch does not merge into the main integration
worktree, install on the owner's phone, or change live MCP/relay configuration.

## 文案與參考

- 系統名詞沿用 Apple 台灣用語：「螢幕使用時間」、App、網站、設定、允許。
  [Apple 台灣支援](https://support.apple.com/zh-tw/105121)
- 「專注模式」是 iOS 的通知管理功能；本產品使用「專注」、「本次專注時間」，
  避免混淆。[Apple 台灣專注模式說明](https://support.apple.com/zh-tw/guide/iphone/iph5c3f5b77b/ios)
- 參考同類產品的「專注時間」、「專注期間」表達，不逐字翻譯英文標語。
  [Forest 台灣商店頁面](https://apps.apple.com/tw/app/id866450515)
- Agent 統一稱為「AI 助理」；session 為「本次專注」；maximum 為「每次專注時間上限」。
  改上限不影響進行中的專注，文案保留這項區別。
- 「等待手機確認」不表示已生效；已超過預計結束時間也不直接宣稱已解除限制。
- 手機拒絕或工具錯誤顯示可採取的下一步，不直接顯示 `mode_not_approved` 等內部代碼。

完整原生文案見 [翻譯對照表](copy.md)。聊天室文案在
`experiments/agent-focus/src/ui/focus-i18n.mjs`，包括操作、輔助使用、驗證與各種收據狀態。

## 實作範圍

- App 設定三步驟、首頁狀態、緊急解鎖、連線與錯誤訊息。
- 系統封鎖畫面及通知擴充功能的顯示文字。
- 三個 bundle 各有 `AgentFocus.xcstrings`，以 iOS 語言設定選擇繁中／英文。
  使用獨立字串表，避免改動既有付費版／卡片流程的翻譯。
- APNs 初始提醒保留英文 body，加入 `loc-key`；兩個 key 放在 App 的
  Localizable 字串表，讓通知擴充功能未執行時也可由 iOS 翻譯。
  [Apple APNs 在地化說明](https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification)
- 聊天室選擇器依 MCP Apps host locale，未提供時依瀏覽器語言選擇繁中／英文；
  支援語言切換，保留正在編輯的數字。未支援的語言使用英文 fallback。
- 中文大標不套用英文的負字距。日期時間依顯示語言格式化，原本時區不變。
- 配對、時間與上限驗證、命令內容、收據／重試流程、通知路由、監控排程及
  shield effects 不變；APNs 僅新增顯示文字的在地化 key。

## 驗證

- Swift core: **76** tests pass.
- Node/MCP/relay/APNs: **84** tests pass，包括5個新的在地化測試。
  測試直接執行選擇器程式，使用隔離的 DOM／host adapter，未連到實際手機。
  涵蓋 locale 選擇、兩種時間選擇器、pending/unknown/applied/elapsed、中文錯誤、
  host 語言切換保留草稿，並確認顯示與語言切換不會送出命令。
- 獨立 iPhone13 模擬器：**2** UI tests pass，含繁中設定／套用中、放大字體下
  緊急解鎖可操作、以及英文 fallback。合計 **162** tests pass。
- Debug iOS Simulator app／extensions：**BUILD SUCCEEDED**。
- Release iOS app／extensions（compile only, signing disabled）：**BUILD SUCCEEDED**。
- 三份字串表共79個 entries（含各 bundle 重複項），中英格式參數數量及順序一致。
- `git diff --check` clean。

驗證紀錄：`/tmp/docard-zh-tw-swift.log`、`/tmp/docard-zh-tw-node-final.log`、
`/tmp/docard-zh-tw-debug.log`、`/tmp/docard-zh-tw-release.log`、
`/tmp/docard-zh-tw-capture-final.log`。

截圖為 production view 搭配模擬器 fixture，並非實機限制或推播成功的證據：

- [首次設定](screenshots/zh-tw-setup.png)
- [時間上限與時段](screenshots/zh-tw-limits.png)
- [正在套用](screenshots/zh-tw-applying.png)
- [放大字體及緊急解鎖](screenshots/zh-tw-large-text-emergency.png)
- [沒有進行中的專注](screenshots/zh-tw-idle.png)

合併後仍需以繁中 iPhone 檢查系統封鎖畫面、通知顯示與原生 App 選擇器。
聊天室目前以 host/DOM adapter 測試，尚未在真實聊天工具中做繁中視覺 walkthrough。
