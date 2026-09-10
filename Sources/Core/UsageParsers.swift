import Foundation

public enum UsageParsers {
    public static func antigravity(_ data: Data, now: Date = .now) throws -> ServiceUsage {
        struct Bucket: Decodable {
            let bucketId: String
            let window: String
            let remainingFraction: Double?
            let resetTime: String?
            let disabled: Bool?
        }
        struct Group: Decodable { let displayName: String; let buckets: [Bucket]? }
        struct Summary: Decodable { let groups: [Group]? }
        struct Envelope: Decodable { let quota_summary: Summary?; let timestamp: String? }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let formatter = ISO8601DateFormatter()
        func date(_ text: String) -> Date? {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }
        var groups: [UsageQuotaGroup] = []
        for group in envelope.quota_summary?.groups ?? [] {
            var groupID: String?
            var windows: [UsageWindow] = []
            for bucket in group.buckets ?? [] {
                let period: UsagePeriod
                switch bucket.window {
                case "5h": period = .fiveHours
                case "weekly": period = .weekly
                default: continue
                }
                let suffix = "-" + bucket.window
                guard bucket.bucketId.hasSuffix(suffix) else {
                    throw UsageError.message("無法辨識 Antigravity 額度群組。")
                }
                let id = String(bucket.bucketId.dropLast(suffix.count))
                guard !id.isEmpty, groupID == nil || groupID == id else {
                    throw UsageError.message("Antigravity 額度群組包含不一致的識別碼。")
                }
                groupID = id
                guard bucket.disabled != true, let remaining = bucket.remainingFraction else { continue }
                guard remaining.isFinite, (0...1).contains(remaining),
                      !windows.contains(where: { $0.windowDurationMins == period.rawValue }) else {
                    throw UsageError.message("Antigravity 回傳無效或重複的額度。")
                }
                windows.append(UsageWindow(usedPercent: (1 - remaining) * 100,
                    windowDurationMins: period.rawValue, resetsAt: bucket.resetTime.flatMap(date)))
            }
            if let groupID {
                guard !groups.contains(where: { $0.id == groupID }) else {
                    throw UsageError.message("Antigravity 回傳重複的額度群組。")
                }
                groups.append(UsageQuotaGroup(id: groupID, name: group.displayName, windows: windows))
            }
        }
        guard groups.contains(where: { !$0.windows.isEmpty }) else {
            throw UsageError.message("Antigravity 未提供可用額度。請執行 agy-usage quota --json 檢查登入與方案狀態。")
        }
        return ServiceUsage(updatedAt: envelope.timestamp.flatMap(date) ?? now, quotaGroups: groups)
    }

    public static func codex(_ data: Data, now: Date = .now) throws -> ServiceUsage {
        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Int?
            let resetsAt: Double?
        }
        struct Bucket: Decodable { let primary: Window?; let secondary: Window?; let limitId: String? }
        struct Response: Decodable { let rateLimits: Bucket?; let rateLimitsByLimitId: [String: Bucket]? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let bucket: Bucket?
        if let buckets = response.rateLimitsByLimitId, !buckets.isEmpty {
            bucket = buckets["codex"] // Never silently use another model's quota.
        } else {
            bucket = response.rateLimits.flatMap { ($0.limitId == nil || $0.limitId == "codex") ? $0 : nil }
        }
        guard let bucket else { throw UsageError.message("Codex 未回傳訂閱用量，請確認 CLI 已登入 ChatGPT 帳號。") }
        let windows = try [bucket.primary, bucket.secondary].compactMap { window -> UsageWindow? in
            guard let window, let minutes = window.windowDurationMins,
                  UsagePeriod(rawValue: minutes) != nil else { return nil }
            guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else {
                throw UsageError.message("Codex 回傳無效的用量百分比。")
            }
            return UsageWindow(usedPercent: window.usedPercent, windowDurationMins: minutes,
                               resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:)))
        }
        guard !windows.isEmpty else { throw UsageError.message("Codex 未提供 5 小時或每週視窗。") }
        return ServiceUsage(windows: windows, updatedAt: now)
    }

    public static func claude(_ data: Data, now: Date = .now) throws -> ServiceUsage {
        struct Envelope: Decodable { let is_error: Bool?; let result: String? }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.is_error != true, let result = envelope.result else {
            throw UsageError.message("Claude /usage 執行失敗，請在終端機確認登入與訂閱狀態。")
        }
        // The top-level `usage` is token accounting, not subscription usage.
        let labels: [(String, UsagePeriod)] = [("Current session", .fiveHours), ("Current week (all models)", .weekly)]
        let windows = try labels.compactMap { label, period -> UsageWindow? in
            let pattern = "(?m)^" + NSRegularExpression.escapedPattern(for: label) + #":\s*([0-9]+(?:\.[0-9]+)?)% used(?:[^\n]*?resets ([^\n]+))?\s*$"#
            let regex = try NSRegularExpression(pattern: pattern)
            let ns = result as NSString
            guard let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: ns.length)),
                  let percent = Double(ns.substring(with: match.range(at: 1))), (0...100).contains(percent) else { return nil }
            let resetText = match.range(at: 2).location == NSNotFound ? nil : ns.substring(with: match.range(at: 2))
            return UsageWindow(usedPercent: percent, windowDurationMins: period.rawValue,
                               resetsAt: resetText.flatMap { claudeResetDate($0, now: now) })
        }
        guard !windows.isEmpty else {
            throw UsageError.message("無法辨識 Claude /usage 輸出。需要支援此指令的 Claude Code 版本。")
        }
        return ServiceUsage(windows: windows, updatedAt: now)
    }

    static func claudeResetDate(_ text: String, now: Date) -> Date? {
        // CLI emits English month/day and an explicit IANA time zone, without a year.
        guard let split = text.range(of: " (", options: .backwards), text.hasSuffix(")"),
              let zone = TimeZone(identifier: String(text[split.upperBound..<text.index(before: text.endIndex)])) else { return nil }
        let value = String(text[..<split.lowerBound]).replacingOccurrences(of: " at ", with: " ")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let year = calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.isLenient = false
        for format in ["yyyy MMM d h:mma", "yyyy MMM d ha"] {
            formatter.dateFormat = format
            for candidateYear in [year, year + 1] {
                if let date = formatter.date(from: "\(candidateYear) \(value)"),
                   date >= now.addingTimeInterval(-60), date < now.addingTimeInterval(8 * 86400) { return date }
            }
        }
        return nil // Preserve usage if a future CLI changes its reset-date format.
    }
}
