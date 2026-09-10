import SwiftUI
import WidgetKit

@main
struct UsageControls: WidgetBundle {
    var body: some Widget {
        CodexFiveHourControl()
        CodexWeeklyControl()
        ClaudeFiveHourControl()
        ClaudeWeeklyControl()
        AntigravityGeminiFiveHourControl()
        AntigravityGeminiWeeklyControl()
        AntigravityThirdPartyFiveHourControl()
        AntigravityThirdPartyWeeklyControl()
    }
}

struct UsageControlValueProvider: ControlValueProvider {
    let service: UsageService
    var previewValue: ServiceUsage {
        let windows = [UsageWindow(usedPercent: 25, windowDurationMins: 300, resetsAt: nil),
                       UsageWindow(usedPercent: 42, windowDurationMins: 10080, resetsAt: nil)]
        return ServiceUsage(windows: windows, updatedAt: .now, quotaGroups: service == .antigravity ? [
            UsageQuotaGroup(id: "gemini", name: "Gemini Models", windows: windows),
            UsageQuotaGroup(id: "3p", name: "Claude and GPT models", windows: windows)
        ] : nil)
    }
    func currentValue() async throws -> ServiceUsage {
        try UsageCache.shared().read()[service]
    }
}

struct AntigravityGeminiFiveHourControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.aiusage.antigravity.gemini.fiveHours", provider: UsageControlValueProvider(service: .antigravity)) { usage in
            ControlWidgetButton(action: RefreshUsageIntent()) {
                Label("AG Gemini 5h · \(usage.percentText(.fiveHours, groupID: "gemini"))", systemImage: "sparkles")
                    .controlWidgetActionHint("開啟並更新")
            }
        }.displayName("Antigravity Gemini · 5 小時").description("Antigravity Gemini 群組的 5 小時已使用百分比。")
    }
}
struct AntigravityGeminiWeeklyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.aiusage.antigravity.gemini.weekly", provider: UsageControlValueProvider(service: .antigravity)) { usage in
            ControlWidgetButton(action: RefreshUsageIntent()) {
                Label("AG Gemini 週 · \(usage.percentText(.weekly, groupID: "gemini"))", systemImage: "sparkles")
                    .controlWidgetActionHint("開啟並更新")
            }
        }.displayName("Antigravity Gemini · 每週").description("Antigravity Gemini 群組的每週已使用百分比。")
    }
}
struct AntigravityThirdPartyFiveHourControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.aiusage.antigravity.thirdParty.fiveHours", provider: UsageControlValueProvider(service: .antigravity)) { usage in
            ControlWidgetButton(action: RefreshUsageIntent()) {
                Label("AG Claude/GPT 5h · \(usage.percentText(.fiveHours, groupID: "3p"))", systemImage: "sparkles")
                    .controlWidgetActionHint("開啟並更新")
            }
        }.displayName("Antigravity Claude／GPT · 5 小時").description("Antigravity Claude／GPT 群組的 5 小時已使用百分比。")
    }
}
struct AntigravityThirdPartyWeeklyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.aiusage.antigravity.thirdParty.weekly", provider: UsageControlValueProvider(service: .antigravity)) { usage in
            ControlWidgetButton(action: RefreshUsageIntent()) {
                Label("AG Claude/GPT 週 · \(usage.percentText(.weekly, groupID: "3p"))", systemImage: "sparkles")
                    .controlWidgetActionHint("開啟並更新")
            }
        }.displayName("Antigravity Claude／GPT · 每週").description("Antigravity Claude／GPT 群組的每週已使用百分比。")
    }
}

struct CodexFiveHourControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.aiusage.codex.fiveHours", provider: UsageControlValueProvider(service: .codex)) { usage in
            ControlWidgetButton(action: RefreshUsageIntent()) {
                Label("Codex 5h · \(usage.percentText(.fiveHours))", systemImage: "terminal")
                    .controlWidgetActionHint("開啟並更新")
            }
        }.displayName("Codex · 5 小時").description("Codex 5 小時已使用百分比；點擊開啟 App 更新。")
    }
}
struct CodexWeeklyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.aiusage.codex.weekly", provider: UsageControlValueProvider(service: .codex)) { usage in
            ControlWidgetButton(action: RefreshUsageIntent()) {
                Label("Codex 週 · \(usage.percentText(.weekly))", systemImage: "terminal")
                    .controlWidgetActionHint("開啟並更新")
            }
        }.displayName("Codex · 每週").description("Codex 每週已使用百分比；點擊開啟 App 更新。")
    }
}
struct ClaudeFiveHourControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.aiusage.claude.fiveHours", provider: UsageControlValueProvider(service: .claude)) { usage in
            ControlWidgetButton(action: RefreshUsageIntent()) {
                Label("Claude 5h · \(usage.percentText(.fiveHours))", systemImage: "sparkle")
                    .controlWidgetActionHint("開啟並更新")
            }
        }.displayName("Claude · 5 小時").description("Claude 5 小時已使用百分比；點擊開啟 App 更新。")
    }
}
struct ClaudeWeeklyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.aiusage.claude.weekly", provider: UsageControlValueProvider(service: .claude)) { usage in
            ControlWidgetButton(action: RefreshUsageIntent()) {
                Label("Claude 週 · \(usage.percentText(.weekly))", systemImage: "sparkle")
                    .controlWidgetActionHint("開啟並更新")
            }
        }.displayName("Claude · 每週").description("Claude 所有模型每週已使用百分比；點擊開啟 App 更新。")
    }
}
