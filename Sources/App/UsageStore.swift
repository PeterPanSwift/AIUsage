import Foundation
import Observation
import WidgetKit
import OSLog

@MainActor @Observable
final class UsageStore {
    private let logger = Logger(subsystem: "local.aiusage", category: "refresh")
    static let shared = UsageStore()
    var snapshot = UsageSnapshot()
    var refreshing = false
    var cacheError: String?
    private var started = false
    private var refreshTask: Task<Void, Never>?

    func start() {
        guard !started else { return }
        started = true
        do { snapshot = try UsageCache.shared().read() }
        catch { cacheError = error.localizedDescription }
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task { await fetchAndSave() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func fetchAndSave() async {
        refreshing = true
        defer { refreshing = false }
        let paths = UsageService.allCases.map { ($0, UserDefaults.standard.string(forKey: "\($0.rawValue)Path") ?? "") }
        await withTaskGroup(of: (UsageService, ServiceUsage?, String?).self) { group in
            for (service, path) in paths {
                group.addTask {
                    do { return (service, try await UsageClient().fetch(service, executable: path), nil) }
                    catch { return (service, nil, error.localizedDescription) }
                }
            }
            for await (service, usage, error) in group {
                if let usage { snapshot[service] = usage }
                else { snapshot[service].error = error }
            }
        }
        // Publish one complete snapshot before asking the extension to read it.
        // Reloading all controls after each provider completed created bursts of
        // redundant reloads and let controls observe different partial snapshots.
        do {
            try UsageCache.shared().write(snapshot)
            cacheError = nil
            ControlCenter.shared.reloadAllControls()
            logger.info("Published complete usage snapshot; requested one controls reload")
        } catch {
            cacheError = error.localizedDescription
            logger.error("Could not publish shared usage snapshot: \(error.localizedDescription)")
        }
    }
}
