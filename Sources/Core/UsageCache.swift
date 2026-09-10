import Foundation

public struct UsageCache: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public static func shared() throws -> UsageCache {
        guard let groupID = Bundle.main.object(forInfoDictionaryKey: "AIUsageAppGroup") as? String,
              !groupID.hasPrefix("."), !groupID.contains("$(") else {
            throw UsageError.message("請在 Xcode 設定 Development Team 後重新建置。")
        }
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw UsageError.message("無法存取 App Group。請確認 App 與擴充功能使用相同簽署團隊。")
        }
        return UsageCache(fileURL: directory.appendingPathComponent("usage-v1.json"))
    }
    public func read() throws -> UsageSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return UsageSnapshot() }
        return try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: fileURL))
    }
    public func write(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
