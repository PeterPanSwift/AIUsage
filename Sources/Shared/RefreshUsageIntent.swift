import AppIntents

struct RefreshUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "更新 AI 用量"
    static let description = IntentDescription("開啟 AI Usage 並更新 Codex、Claude 與 Antigravity 訂閱用量。")
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult {
        #if APP_HOST
        await UsageStore.shared.refresh()
        #endif
        return .result()
    }
}
