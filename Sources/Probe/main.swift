import Foundation
import UsageCore

let requested = CommandLine.arguments.dropFirst().compactMap(UsageService.init(rawValue:))
for service in requested.isEmpty ? UsageService.allCases : requested {
    do {
        let usage = try await UsageClient().fetch(service)
        print(service.name)
        let groups = usage.quotaGroups ?? [UsageQuotaGroup(id: "", name: service.name, windows: usage.windows)]
        for group in groups {
            let groupID: String? = group.id.isEmpty ? nil : group.id
            for period in UsagePeriod.allCases {
                print("  \(group.name) · \(period.rawValue) minutes: \(usage.percentText(period, groupID: groupID)); reset: \(String(describing: usage.window(period, groupID: groupID)?.resetsAt))")
            }
        }
    } catch {
        print("\(service.name): \(error.localizedDescription)")
        exit(1)
    }
}
