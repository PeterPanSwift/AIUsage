import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1789027200) // 2026-09-10 08:00 UTC

@Test func codexUsesNamedBucketAndDuration() throws {
    let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1789449574},"secondary":{"usedPercent":15,"windowDurationMins":300,"resetsAt":1789044076}},"other":{"primary":{"usedPercent":88,"windowDurationMins":300}}}}"#.utf8)
    let value = try UsageParsers.codex(data, now: now)
    #expect(value.window(.fiveHours)?.usedPercent == 15)
    #expect(value.window(.weekly)?.usedPercent == 12)
    #expect(value.window(.fiveHours)?.resetsAt == Date(timeIntervalSince1970: 1789044076))
}

@Test func codexDoesNotInventMissingWindow() throws {
    let value = try UsageParsers.codex(Data(#"{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":300},"secondary":null}}"#.utf8))
    #expect(value.window(.weekly) == nil)
    #expect(value.percentText(.weekly) == "—")
}

@Test func codexRejectsWrongBucketAndInvalidPercent() {
    for json in [#"{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":12,"windowDurationMins":300}}}}"#,
                 #"{"rateLimits":{"primary":{"usedPercent":101,"windowDurationMins":300}}}"#,
                 #"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":60}}}"#] {
        #expect(throws: (any Error).self) { try UsageParsers.codex(Data(json.utf8)) }
    }
}

private func envelope(_ result: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["is_error":false,"result":result,"usage":["input_tokens":9999]])
}

@Test func claudeParsesRealCLIShapeAndAllModels() throws {
    let value = try UsageParsers.claude(envelope("Current session: 9% used · resets Sep 10 at 8:10pm (Asia/Taipei)\nCurrent week (all models): 25% used · resets Sep 15 at 10am (Asia/Taipei)\nCurrent week (Fable): 37% used · resets Sep 15 at 10am (Asia/Taipei)"), now: now)
    #expect(value.window(.fiveHours)?.usedPercent == 9)
    #expect(value.window(.weekly)?.usedPercent == 25)
    #expect(value.window(.fiveHours)?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-10T12:10:00Z"))
    #expect(value.window(.weekly)?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-15T02:00:00Z"))
}

@Test func claudeHandlesYearRolloverAndUnknownDate() throws {
    let december = ISO8601DateFormatter().date(from: "2026-12-31T12:00:00Z")!
    let result = try UsageParsers.claude(envelope("Current session: 0% used · resets a future date\nCurrent week (all models): 12.5% used · resets Jan 2 at 10am (Asia/Taipei)"), now: december)
    #expect(result.window(.fiveHours)?.usedPercent == 0)
    #expect(result.window(.fiveHours)?.resetsAt == nil)
    #expect(result.window(.weekly)?.resetsAt == ISO8601DateFormatter().date(from: "2027-01-02T02:00:00Z"))
}

@Test func claudeRejectsTokenUsageAndErrors() {
    for json in [#"{"usage":{"input_tokens":10},"result":"Unknown command: usage"}"#,
                 #"{"is_error":true,"result":"Current session: 5% used"}"#] {
        #expect(throws: (any Error).self) { try UsageParsers.claude(Data(json.utf8)) }
    }
}

@Test func cacheRoundTripAndStaleState() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = UsageCache(fileURL: directory.appendingPathComponent("usage.json"))
    #expect(try cache.read().codex.updatedAt == nil)
    var snapshot = UsageSnapshot()
    snapshot.codex = ServiceUsage(windows: [.init(usedPercent: 50, windowDurationMins: 300, resetsAt: now.addingTimeInterval(300))], updatedAt: now)
    try cache.write(snapshot)
    #expect(try cache.read().codex == snapshot.codex)
    #expect(snapshot.codex.percentText(.fiveHours, at: now) == "50%")
    #expect(snapshot.codex.percentText(.fiveHours, at: now.addingTimeInterval(301)).contains("舊資料"))
    #expect(snapshot.codex.isStale(at: now.addingTimeInterval(601)))
    snapshot.codex.error = "Offline"
    #expect(snapshot.codex.percentText(.fiveHours, at: now).contains("舊資料"))
}

@Test func processTimeoutIsBounded() throws {
    let session = try CommandSession(path: "/bin/sleep", arguments: ["10"], timeout: .milliseconds(100))
    defer { session.close() }
    let start = ContinuousClock.now
    #expect(throws: (any Error).self) { try session.allOutput() }
    #expect(ContinuousClock.now - start < .seconds(2))
}

@Test func processReadsOutputAndChecksExit() throws {
    let session = try CommandSession(path: "/usr/bin/printf", arguments: ["hello"])
    defer { session.close() }
    #expect(try session.allOutput() == Data("hello".utf8))
    let failure = try CommandSession(path: "/usr/bin/false", arguments: [])
    defer { failure.close() }
    #expect(throws: (any Error).self) { try failure.allOutput() }
}

private func antigravityEnvelope(remaining: String = "0.75", disabled: String = "null", reset: String = "2026-09-16T15:40:01.123Z") -> Data {
    Data("""
    {"email":"not-stored@example.com","timestamp":"2026-09-10T08:00:00.123+00:00",
     "quota_summary":{"buckets":null,"groups":[
      {"displayName":"Gemini Models","buckets":[
       {"bucketId":"gemini-weekly","window":"weekly","remainingFraction":\(remaining),"disabled":\(disabled),"resetTime":"\(reset)"},
       {"bucketId":"gemini-5h","window":"5h","remainingFraction":1,"resetTime":"2026-09-10T13:45:25Z"}]},
      {"displayName":"Claude and GPT models","buckets":[
       {"bucketId":"3p-weekly","window":"weekly","remainingFraction":0,"resetTime":null},
       {"bucketId":"3p-5h","window":"5h","remainingFraction":0.6,"resetTime":null}]}]}}
    """.utf8)
}

@Test func antigravityKeepsGroupsSeparateAndConvertsRemaining() throws {
    let usage = try UsageParsers.antigravity(antigravityEnvelope(), now: now)
    #expect(usage.quotaGroups?.map(\.id) == ["gemini", "3p"])
    #expect(usage.window(.weekly) == nil)
    #expect(usage.window(.weekly, groupID: "gemini")?.usedPercent == 25)
    #expect(usage.window(.fiveHours, groupID: "gemini")?.usedPercent == 0)
    #expect(usage.window(.weekly, groupID: "3p")?.usedPercent == 100)
    #expect(usage.window(.fiveHours, groupID: "3p")?.usedPercent == 40)
    #expect(usage.window(.fiveHours, groupID: "gemini")?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-10T13:45:25Z"))
    #expect(usage.window(.weekly, groupID: "gemini")?.resetsAt != nil)
    #expect(abs(usage.updatedAt!.timeIntervalSince(now) - 0.123) < 0.001)
    #expect(!String(decoding: try JSONEncoder().encode(usage), as: UTF8.self).contains("not-stored"))
}

@Test func antigravityMissingAndDisabledAreNotZero() throws {
    for fixture in [antigravityEnvelope(remaining: "null"), antigravityEnvelope(disabled: "true")] {
        let usage = try UsageParsers.antigravity(fixture)
        #expect(usage.window(.weekly, groupID: "gemini") == nil)
        #expect(usage.percentText(.weekly, groupID: "gemini") == "—")
        #expect(usage.window(.weekly, groupID: "3p")?.usedPercent == 100)
    }
    let usage = try UsageParsers.antigravity(antigravityEnvelope(reset: "unknown"))
    #expect(usage.window(.weekly, groupID: "gemini")?.resetsAt == nil)
    #expect(usage.window(.weekly, groupID: "gemini")?.usedPercent == 25)
}

@Test func antigravityRejectsInvalidAndEmptyQuota() {
    for fixture in [antigravityEnvelope(remaining: "1.1"), antigravityEnvelope(remaining: "-0.1"),
                    Data(#"{"quota_summary":{"groups":[]}}"#.utf8), Data(#"{"error":"not logged in"}"#.utf8)] {
        #expect(throws: (any Error).self) { try UsageParsers.antigravity(fixture) }
    }
}

@Test func legacyCacheSurvivesAddingAntigravity() throws {
    let data = Data(#"{"codex":{"windows":[{"usedPercent":20,"windowDurationMins":300}],"updatedAt":100},"claude":{"windows":[]}}"#.utf8)
    var snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
    #expect(snapshot.codex.window(.fiveHours)?.usedPercent == 20)
    #expect(snapshot.codex.quotaGroups == nil)
    #expect(snapshot.antigravity == ServiceUsage())
    snapshot[.antigravity] = try UsageParsers.antigravity(antigravityEnvelope())
    let restored = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(restored.antigravity == snapshot.antigravity)
    #expect(restored.codex.window(.fiveHours)?.usedPercent == 20)
    var failed = restored.antigravity
    failed.error = "Offline"
    #expect(failed.percentText(.weekly, groupID: "gemini", at: now).contains("舊資料"))
}
