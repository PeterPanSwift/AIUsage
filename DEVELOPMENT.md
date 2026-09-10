# AI Usage — macOS 27

SwiftUI 選單列 App，加上八個 WidgetKit `ControlWidget`：Codex、Claude 各兩個（5 小時／每週），Antigravity 的 Gemini 與 Claude／GPT 群組各兩個（5 小時／每週）。控制項標題顯示已使用百分比；點擊後開啟主 App 並更新。主畫面包含進度條、重置時間及錯誤狀態。

## 執行

1. 使用 Xcode 27 開啟 `AIUsage.xcodeproj`。
2. 在專案 Signing & Capabilities 選擇自己的 Development Team，讓兩個 target 使用同一團隊。
3. 執行 `AIUsage` scheme。請先在終端機完成 `codex login`、Claude Code 登入，以及 `/Applications/agy-usage/agy-usage login`。
4. 在控制中心的「編輯控制項目」搜尋 AI Usage，加入所需的控制項。百分比放在主標題中；請使用有文字標籤的控制項尺寸。

App 保持執行時，每 5 分鐘更新一次；關閉視窗仍保留選單列 App。結束 App 後不會定時執行 CLI。控制項只讀快取，點擊控制項會重新啟動 App 更新。系統決定控制項何時重新讀取及如何呈現；這不是 Widget timeline。

CLI 預設從 `/opt/homebrew/bin`、`/usr/local/bin`、`~/.local/bin`、`~/.cargo/bin` 尋找，Antigravity 優先使用 `/Applications/agy-usage/agy-usage`。設定頁可覆寫各 CLI 的絕對路徑。Process 直接傳入引數，不透過 shell 執行。

## 資料來源

- Codex：啟動 `codex app-server`，以 stdio newline-delimited JSON-RPC 依序執行 `initialize`、等待回應、`initialized`、`account/rateLimits/read`。以 RPC id 配對回應，忽略通知；優先採用 `rateLimitsByLimitId.codex`，舊版本才使用 `rateLimits`。依 `windowDurationMins` 的 300 / 10080 分類，保留 `usedPercent` 與秒級 Unix `resetsAt`。
- Claude：執行 `claude -p "/usage" --output-format json --no-session-persistence`，解析 JSON 的 `result` 中 `Current session` 與 `Current week (all models)`。不使用 token 統計的 `usage`，也不誤讀模型專屬的週用量。日期解析處理 CLI 的英文格式、IANA 時區及跨年；不認得日期時保留百分比並顯示重置時間未提供。

Claude 此輸出是 CLI 文字格式，未來版本或語系變更可能需要更新 parser。本機已驗證 Codex CLI 0.145.0、Claude Code 2.1.267。

### Antigravity

執行 `/Applications/agy-usage/agy-usage quota --json`，讀取 `quota_summary.groups[].buckets[]`。依 `bucketId` 的 `gemini`／`3p` 群組識別碼與 `window`（`5h`／`weekly`）分組，顯示 `(1 - remainingFraction) × 100` 的已使用百分比與 ISO 8601 `resetTime`。CLI 進度文字在 stderr，stdout 是可直接解析的 JSON。每次更新只執行一次 agy-usage，同時取得全部群組。

未提供或停用的額度顯示「—」，不視為 0%；Gemini 與 Claude／GPT 不合併計算。JSON 中的 email、prompt credits 與帳號資訊不寫入共享快取。使用回傳的 `timestamp` 作為資料時間，原指令保留 CLI 自身的 5 分鐘快取行為，不附加 `--force`。舊版雙服務快取可直接讀取，Antigravity 會在下一次更新補齊。

可單獨驗證此來源：`swift run usage-probe antigravity`。

## 共享資料與執行位置

主 App 關閉 App Sandbox，才能執行本機 CLI 並沿用其登入環境；Widget 擴充功能啟用 Sandbox，只讀取 App Group 中的 `usage-v1.json`。這個架構適合本機使用與 Developer ID 發佈，不是 Mac App Store sandbox 架構。

App Group 使用 macOS 支援的 `$(DEVELOPMENT_TEAM).local.aiusage.shared`，由 Info.plist 與 entitlements 同步展開。不需註冊新 App Group 或取得 provisioning profile，仍必須使用相同有效開發者憑證簽署兩個 target。`RefreshUsageIntent` 使用 `.foreground` 與 macOS 27 的 `allowedExecutionTargets = .main`，在主 App 執行 CLI。

快取使用原子寫入，僅儲存百分比、視窗長度、重置／更新時間與 App 產生的錯誤訊息；不儲存 CLI 原始輸出、憑證或對話。三家可獨立成功或失敗，失敗保留上次成功值並標記舊資料。超過 10 分鐘或重置時間已到亦標記舊資料，不推測用量已歸零。CLI 請求限時 30 秒、最多讀取 2 MB，結束時清理子程序。

## 建置與驗證

```sh
xcodebuild -project AIUsage.xcodeproj -scheme AIUsage \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build DEVELOPMENT_TEAM=YOUR_TEAM_ID build

# 不需簽署的編譯檢查；此產物不能驗證 App Group runtime。
xcodebuild -project AIUsage.xcodeproj -scheme AIUsage \
  -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

swift test
swift run usage-probe
```

`usage-probe` 會使用現有 CLI 登入，實際讀取三家用量。測試不連線，涵蓋 bucket 選擇、視窗分類、缺失／錯誤資料、Claude 日期／時區／跨年、快取與過期狀態、程序讀取／退出碼／逾時。

2026-09-10 驗證：Xcode 27 Debug 編譯與 Apple Development 簽署成功；`codesign --verify --deep --strict` 成功；9 項 Swift Testing 測試通過；Swift CLI probe 與 App 畫面均取得兩家的四個真實數值及重置時間；`pluginkit` 已列出擴充功能。控制中心 UI 自動化逾時，尚未驗證新增控制項後的標題呈現、擴充功能讀取快取與點擊喚醒路徑，需在控制中心手動驗收。

已附可直接開啟的 Xcode 專案。只有需要重新產生專案時才需 Ruby `xcodeproj` gem：`DEVELOPMENT_TEAM=YOUR_TEAM_ID ruby Scripts/generate-project.rb`。不需 XcodeGen 或第三方 Swift 套件。

## 參考

- [Codex app-server 官方協定](https://learn.chatgpt.com/docs/app-server)
- [Claude Code 程式化執行與 JSON 輸出](https://code.claude.com/docs/en/headless)
- [Apple 控制項生命週期](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)
- [macOS App Group 與簽署規則](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

Antigravity 更新驗證（2026-09-10）：簽署建置成功，13 項測試通過；`usage-probe antigravity` 與重新啟動後的 App 實際顯示兩個群組、四項百分比及重置時間，並已檢查捲動版面。新增四個控制項完成編譯，控制中心內新增與點擊的手動驗收仍待進行。

### 控制項目資料庫仍顯示舊版時

主 App 與 Widget 擴充功能是獨立程序，重啟主 App 不會更新仍在執行的擴充功能。新增控制項種類時，同步提高兩個 Info.plist 的 `CFBundleShortVersionString` 與 `CFBundleVersion`，重新建置並結束舊的 `AIUsageControls` 程序。可使用 `pluginkit -a` 重新登錄產物內的 `.appex`；若資料庫仍保留舊清單，再重新啟動 ControlCenter 並開啟資料庫。不要刪除使用者的控制中心配置或共享用量快取。

本次修正為 `1.1 (2)`：確認原擴充程序在 16:42 啟動，早於 16:51 的 Antigravity 建置。更新版本、重新登錄及重啟後，16:55 的 ControlCenter 系統記錄對 Antigravity 四個種類均回報 `Content load successful`、`hasError? false` 與 `Received initial update`，證實新控制項的資料庫預覽已載入。加入後的實際值與點擊仍是另一項驗收。
