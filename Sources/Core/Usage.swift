import Foundation

public enum UsageService: String, Codable, CaseIterable, Sendable, Identifiable {
    case codex, claude, antigravity
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .antigravity: "Antigravity"
        }
    }
}

public enum UsagePeriod: Int, Codable, CaseIterable, Sendable, Identifiable {
    case fiveHours = 300, weekly = 10080
    public var id: Int { rawValue }
    public var title: LocalizedStringResource { self == .fiveHours ? "5 小時" : "每週" }
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int
    public let resetsAt: Date?
    public init(usedPercent: Double, windowDurationMins: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct UsageQuotaGroup: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let windows: [UsageWindow]
    public init(id: String, name: String, windows: [UsageWindow]) {
        self.id = id; self.name = name; self.windows = windows
    }
}

public struct ServiceUsage: Codable, Equatable, Sendable {
    public var windows: [UsageWindow] = []
    // Optional to decode caches produced before grouped quotas were supported.
    public var quotaGroups: [UsageQuotaGroup]?
    public var updatedAt: Date?
    public var error: String?
    public init(windows: [UsageWindow] = [], updatedAt: Date? = nil, error: String? = nil, quotaGroups: [UsageQuotaGroup]? = nil) {
        self.windows = windows; self.updatedAt = updatedAt; self.error = error; self.quotaGroups = quotaGroups
    }
    public func window(_ period: UsagePeriod, groupID: String? = nil) -> UsageWindow? {
        let source = groupID.map { id in quotaGroups?.first { $0.id == id }?.windows ?? [] } ?? windows
        return source.first { $0.windowDurationMins == period.rawValue }
    }
    public func isStale(at now: Date = .now) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > 600 || error != nil
    }
    public func percentText(_ period: UsagePeriod, groupID: String? = nil, at now: Date = .now) -> String {
        guard let window = window(period, groupID: groupID) else { return "—" }
        let expired = window.resetsAt.map { $0 <= now } ?? false
        let percent = window.usedPercent.formatted(.number.precision(.fractionLength(0...1))) + "%"
        return (isStale(at: now) || expired) ? "\(percent) · 舊資料" : percent
    }
}

public struct UsageSnapshot: Codable, Sendable {
    public var codex = ServiceUsage()
    public var claude = ServiceUsage()
    public var antigravity = ServiceUsage()
    public init() {}
    private enum CodingKeys: String, CodingKey { case codex, claude, antigravity }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        codex = try values.decodeIfPresent(ServiceUsage.self, forKey: .codex) ?? ServiceUsage()
        claude = try values.decodeIfPresent(ServiceUsage.self, forKey: .claude) ?? ServiceUsage()
        antigravity = try values.decodeIfPresent(ServiceUsage.self, forKey: .antigravity) ?? ServiceUsage()
    }
    public subscript(service: UsageService) -> ServiceUsage {
        get {
            switch service {
            case .codex: codex
            case .claude: claude
            case .antigravity: antigravity
            }
        }
        set {
            switch service {
            case .codex: codex = newValue
            case .claude: claude = newValue
            case .antigravity: antigravity = newValue
            }
        }
    }
}

public enum UsageError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}
