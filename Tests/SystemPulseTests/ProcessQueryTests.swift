import XCTest

@testable import SystemPulse

final class ProcessQueryTests: XCTestCase {
    func testWhitespaceOnlyQueryIsNotSearching() {
        let query = ProcessQuery(" \n\t\u{00A0} ")
        XCTAssertFalse(query.isSearching)
        XCTAssertEqual(query.normalizedText, "")
        XCTAssertTrue(query.matches(group(id: "app", name: "Example")))
    }

    func testNormalizesWhitespaceAndCase() {
        let query = ProcessQuery("  MY\t app\n ")
        XCTAssertEqual(query.normalizedText, "my app")
        XCTAssertTrue(query.matches(group(id: "app", name: "My   App")))
    }

    func testMatchesPIDExecutableAndBundleFields() {
        let app = group(
            id: "app", name: "Example",
            processes: [
                process(
                    pid: 4321, name: "Worker", executable: "/opt/tools/UniqueRunner",
                    bundlePath: "/Applications/Distinct App.app", bundleID: "com.example.background")
            ])
        for text in ["4321", "worker", "UNIQUERUNNER", "/opt/tools", "Distinct App.app", "com.example.background"] {
            XCTAssertTrue(ProcessQuery(text).matches(app), "Expected a match for \(text)")
        }
        XCTAssertFalse(ProcessQuery("missing").matches(app))
    }

    func testMatchesChildPIDAndCombinesTermsAcrossFields() {
        let app = group(
            id: "app", name: "Editor",
            processes: [
                process(pid: 200, name: "Editor"),
                process(pid: 201, name: "Language Worker", executable: "/usr/bin/language-server"),
            ])
        XCTAssertTrue(ProcessQuery("editor 201 language-server").matches(app))
        XCTAssertFalse(ProcessQuery("editor 999").matches(app))
    }

    func testSearchDoesNotTruncateMatchingGroups() {
        let groups = (1...24).map { group(id: "app-\($0)", name: "Matching app \($0)") }
        XCTAssertEqual(ProcessQuery("matching").apply(to: groups, sortBy: .cpu).count, 24)
        XCTAssertEqual(ProcessQuery("").apply(to: groups, sortBy: .memory).count, 24)
    }

    func testCPUSortsDescendingThenNameThenID() {
        let groups = [
            group(id: "z", name: "Alpha", cpu: 10),
            group(id: "b", name: "Beta", cpu: 10),
            group(id: "high", name: "Zulu", cpu: 20),
            group(id: "a", name: "alpha", cpu: 10),
        ]
        assertStableOrder(groups, metric: .cpu, expected: ["high", "a", "z", "b"])
    }

    func testMemorySortsDescendingThenNameThenID() {
        let groups = [
            group(id: "z", name: "Alpha", memory: 100),
            group(id: "b", name: "Beta", memory: 100),
            group(id: "high", name: "Zulu", memory: 200),
            group(id: "a", name: "alpha", memory: 100),
        ]
        assertStableOrder(groups, metric: .memory, expected: ["high", "a", "z", "b"])
    }

    func testMetricRankingUsesWholeGroupTotals() {
        let aggregate = group(
            id: "aggregate", name: "Aggregate",
            processes: [
                process(pid: 200, name: "Main", cpu: 8, memory: 80),
                process(pid: 201, name: "Helper", cpu: 8, memory: 80),
            ])
        let single = group(id: "single", name: "Single", cpu: 12, memory: 120)
        for metric in [ProcessQuery.SortMetric.cpu, .memory] {
            XCTAssertEqual(
                ProcessQuery("").apply(to: [single, aggregate], sortBy: metric).map(\.id),
                ["aggregate", "single"])
        }
    }

    private func assertStableOrder(
        _ groups: [ProcessGroup], metric: ProcessQuery.SortMetric, expected: [String],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for offset in groups.indices {
            let rotated = Array(groups.dropFirst(offset)) + Array(groups.prefix(offset))
            for input in [rotated, Array(rotated.reversed())] {
                XCTAssertEqual(
                    ProcessQuery("").apply(to: input, sortBy: metric).map(\.id), expected,
                    file: file, line: line)
            }
        }
    }

    private func group(
        id: String, name: String, cpu: Double = 0, memory: UInt64 = 0,
        processes: [ProcessStat]? = nil
    ) -> ProcessGroup {
        ProcessGroup(
            id: id, name: name, iconKey: nil, isSystemGroup: false,
            processes: processes ?? [process(pid: 200, name: name, cpu: cpu, memory: memory)])
    }

    private func process(
        pid: Int32, name: String, cpu: Double = 0, memory: UInt64 = 0,
        executable: String = "/usr/bin/example", bundlePath: String? = nil,
        bundleID: String? = nil
    ) -> ProcessStat {
        ProcessStat(
            id: pid, name: name, executablePath: executable, bundlePath: bundlePath,
            bundleIdentifier: bundleID, cpu: cpu, memory: memory, threadCount: 1, iconKey: "test")
    }
}
