import SwiftUI
import AppKit

@main
struct AIUsageApp: App {
    @State private var store = UsageStore.shared
    init() { UsageStore.shared.start() }

    var body: some Scene {
        WindowGroup("AI Usage", id: "usage") {
            DashboardView(store: store)
        }
        .defaultSize(width: 520, height: 760)
        MenuBarExtra("AI Usage", systemImage: "chart.bar.xaxis") {
            DashboardView(store: store, compact: true)
                .frame(width: 380, height: 600)
        }
        .menuBarExtraStyle(.window)
        Settings { CLISettingsView() }
    }
}

struct DashboardView: View {
    let store: UsageStore
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Usage").font(.title2.bold())
                    Text("訂閱用量 · 已使用百分比").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.refreshing { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.refreshing).help("更新用量")
            }
            ScrollView {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 16) {
                        ForEach(UsageService.allCases) { service in
                            ServiceUsageView(service: service, usage: store.snapshot[service], now: context.date)
                        }
                    }
                }
            }
            if let error = store.cacheError { Text(error).font(.caption).foregroundStyle(.red) }
            Text("在控制中心選擇「編輯控制項目」，搜尋 AI Usage，即可加入用量控制項。App 執行期間每 5 分鐘更新。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SettingsLink { Label("設定", systemImage: "gearshape") }
                Spacer()
                if compact { Button("結束") { NSApplication.shared.terminate(nil) } }
            }
            .font(.caption)
        }
        .padding(24)
        .frame(minHeight: 440)
    }
}

struct ServiceUsageView: View {
    let service: UsageService
    let usage: ServiceUsage
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(service.name).font(.headline)
                Spacer()
                if let date = usage.updatedAt {
                    Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                        .help("上次成功更新")
                }
            }
            if service == .antigravity {
                if let groups = usage.quotaGroups, !groups.isEmpty {
                    ForEach(groups) { group in
                        QuotaGroupView(group: group, usage: usage, now: now)
                    }
                } else { Text("尚無額度資料").font(.caption).foregroundStyle(.secondary) }
            } else {
                ForEach(UsagePeriod.allCases) { period in
                    UsageRow(period: period, usage: usage, now: now)
                }
            }
            if let error = usage.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct QuotaGroupView: View {
    let group: UsageQuotaGroup
    let usage: ServiceUsage
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.name).font(.subheadline.bold()).foregroundStyle(.secondary)
            ForEach(UsagePeriod.allCases) { period in
                UsageRow(period: period, usage: usage, now: now, groupID: group.id)
            }
        }
    }
}

struct UsageRow: View {
    let period: UsagePeriod
    let usage: ServiceUsage
    let now: Date
    var groupID: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(period.title).font(.subheadline)
                Spacer()
                Text(usage.percentText(period, groupID: groupID, at: now)).monospacedDigit().font(.subheadline.bold())
            }
            if let window = usage.window(period, groupID: groupID) {
                ProgressView(value: window.usedPercent, total: 100)
                    .tint(window.usedPercent >= 90 ? .orange : .accentColor)
                if let reset = window.resetsAt {
                    Text("重置：\(reset, format: .dateTime.month().day().hour().minute())")
                        .font(.caption2).foregroundStyle(.secondary)
                } else { Text("重置時間未提供").font(.caption2).foregroundStyle(.secondary) }
            } else { Text("尚無資料").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

struct CLISettingsView: View {
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("antigravityPath") private var antigravityPath = ""
    var body: some View {
        Form {
            TextField("Codex 路徑", text: $codexPath, prompt: Text("自動尋找"))
            TextField("Claude 路徑", text: $claudePath, prompt: Text("自動尋找"))
            TextField("Antigravity 路徑", text: $antigravityPath, prompt: Text("/Applications/agy-usage/agy-usage"))
            Text("Antigravity 優先使用 /Applications/agy-usage/agy-usage；其餘會尋找 Homebrew、~/.local/bin 與 ~/.cargo/bin。請先在終端機登入各 CLI。")
                .font(.caption).foregroundStyle(.secondary)
            Button("儲存並更新") { Task { await UsageStore.shared.refresh() } }
        }.padding(24).frame(width: 520)
    }
}
