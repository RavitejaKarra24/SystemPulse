import SwiftUI
import XCTest

@testable import SystemPulse

final class MonitoringInsightsTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 100_000)

    private func samples(
        value: Double = 85, span: Int = 30, endingOffset: TimeInterval = 0, cadence: Int = 1
    ) -> [TimedMetricSample] {
        stride(from: -span, through: 0, by: cadence).map {
            TimedMetricSample(timestamp: now.addingTimeInterval(Double($0) + endingOffset), value: value)
        }
    }

    private func insights(_ input: InsightInput) -> [MonitoringInsight] {
        InsightEngine.insights(for: input, at: now)
    }

    func testHiddenModulesDoNotConsumeVisibleInsightBudget() {
        let input = InsightInput(
            memoryHeadroomPercent: 5, swapUsedBytes: 1 << 30, diskAvailableBytes: 1 << 30,
            batteryChargePercent: 10, isOnBattery: true, thermalLevel: 2,
            topConsumerName: "Fixture", topConsumerCPU: 42, topConsumerSampledAt: now)
        XCTAssertFalse(insights(input).contains { $0.id == "cpu-consumer" })
        let visible = InsightEngine.insights(for: input, at: now, visibleMetrics: [.cpu])
        XCTAssertEqual(visible.map(\.id), ["cpu-consumer"])
        XCTAssertTrue(InsightEngine.insights(for: input, at: now, visibleMetrics: []).isEmpty)
    }

    func testDefaultInputKeepsMissingValuesUnknown() {
        let input = InsightInput()
        XCTAssertTrue(input.cpuPoints.isEmpty)
        XCTAssertNil(input.memoryHeadroomPercent)
        XCTAssertNil(input.memoryUsedBytes)
        XCTAssertNil(input.memoryTotalBytes)
        XCTAssertNil(input.swapUsedBytes)
        XCTAssertNil(input.diskAvailableBytes)
        XCTAssertNil(input.batteryChargePercent)
        XCTAssertFalse(input.isOnBattery)
        XCTAssertNil(input.thermalLevel)
        XCTAssertNil(input.topConsumerName)
        XCTAssertNil(input.topConsumerCPU)
        XCTAssertNil(input.topConsumerSampledAt)
        XCTAssertTrue(insights(input).isEmpty)
    }

    func testNonqualifyingReadingsDoNotCreateBlanketHealthClaim() {
        XCTAssertTrue(
            insights(
                InsightInput(
                    cpuPoints: samples(value: 10), memoryHeadroomPercent: 70, swapUsedBytes: 0,
                    diskAvailableBytes: 20 << 30, batteryChargePercent: 80, isOnBattery: true, thermalLevel: 0)
            ).isEmpty)
    }

    func testCPUReportsMeasuredSampleAverageSpanAndThreshold() throws {
        let observation = try XCTUnwrap(insights(InsightInput(cpuPoints: samples())).first)
        XCTAssertEqual(observation.id, "cpu-average")
        XCTAssertEqual(observation.metric, .cpu)
        XCTAssertTrue(observation.detail.contains("85.0%"))
        XCTAssertTrue(observation.detail.contains("30.0 seconds"))
        XCTAssertTrue(observation.detail.contains("31 raw readings"))
        XCTAssertTrue(observation.detail.contains("≥80%"))
        XCTAssertTrue(observation.detail.contains("Sample-weighted"))
        XCTAssertTrue(observation.detail.contains("last 60 seconds"))
        XCTAssertFalse(observation.detail.lowercased().contains("peak"))
    }

    func testCPUThresholdIsInclusiveAndRequiresThirtySecondSpan() {
        XCTAssertEqual(insights(InsightInput(cpuPoints: samples(value: 80))).count, 1)
        XCTAssertTrue(insights(InsightInput(cpuPoints: samples(value: 79.99))).isEmpty)
        XCTAssertTrue(insights(InsightInput(cpuPoints: samples(span: 29))).isEmpty)
        XCTAssertTrue(insights(InsightInput(cpuPoints: samples(span: 0))).isEmpty)
    }

    func testAverageIsComputedFromRawSamplesNotJustLatestValue() throws {
        var points = samples(value: 90)
        points[points.count - 1] = TimedMetricSample(timestamp: now, value: 0)
        let observation = try XCTUnwrap(insights(InsightInput(cpuPoints: points)).first)
        XCTAssertTrue(observation.detail.contains("87.1%"))
        // A current spike does not make a low-average window qualify.
        points = samples(value: 1)
        points[points.count - 1] = TimedMetricSample(timestamp: now, value: 100)
        XCTAssertTrue(insights(InsightInput(cpuPoints: points)).isEmpty)
    }

    func testCPULatestReadingMustBeFresh() {
        XCTAssertEqual(insights(InsightInput(cpuPoints: samples(endingOffset: -4.5))).count, 1)
        XCTAssertTrue(insights(InsightInput(cpuPoints: samples(endingOffset: -4.501))).isEmpty)
        XCTAssertTrue(insights(InsightInput(cpuPoints: samples(endingOffset: -90))).isEmpty)
    }

    func testCPUContinuityAllowsBoundaryButDoesNotBridgeLargerGaps() {
        let boundary = (0...8).map {
            TimedMetricSample(timestamp: now.addingTimeInterval(Double($0 - 8) * 4.5), value: 85)
        }
        XCTAssertEqual(insights(InsightInput(cpuPoints: boundary)).count, 1)
        let tooSparse = (0...8).map {
            TimedMetricSample(timestamp: now.addingTimeInterval(Double($0 - 8) * 4.501), value: 85)
        }
        XCTAssertTrue(insights(InsightInput(cpuPoints: tooSparse)).isEmpty)
        let separated = samples(span: 35, endingOffset: -20) + samples(span: 10)
        XCTAssertTrue(insights(InsightInput(cpuPoints: separated)).isEmpty)
    }

    func testFreshContiguousSuffixCanQualifyAfterGap() throws {
        let points = samples(span: 10, endingOffset: -50) + samples(span: 30)
        let observation = try XCTUnwrap(insights(InsightInput(cpuPoints: points)).first)
        XCTAssertTrue(observation.detail.contains("30.0 seconds"))
        XCTAssertTrue(observation.detail.contains("31 raw readings"))
    }

    func testCPUWindowExcludesOldAndFutureValues() {
        let oldHigh = samples(value: 100, span: 100, endingOffset: -61)
        XCTAssertTrue(insights(InsightInput(cpuPoints: oldHigh + samples(value: 20))).isEmpty)
        let future = TimedMetricSample(timestamp: now.addingTimeInterval(1), value: 100)
        XCTAssertTrue(insights(InsightInput(cpuPoints: samples(value: 20) + [future])).isEmpty)
        XCTAssertTrue(insights(InsightInput(cpuPoints: [future])).isEmpty)
        // Ten-second aggregates are too sparse to be treated as raw continuous observations.
        XCTAssertTrue(insights(InsightInput(cpuPoints: samples(span: 60, cadence: 10))).isEmpty)
    }

    func testCPUWindowIsBoundedToSixtySeconds() throws {
        let observation = try XCTUnwrap(insights(InsightInput(cpuPoints: samples(span: 300))).first)
        XCTAssertTrue(observation.detail.contains("60.0 seconds"))
        XCTAssertTrue(observation.detail.contains("61 raw readings"))
    }

    func testMalformedCPUValuesRejectCPUWithoutSuppressingOtherRules() {
        for value in [Double.nan, .infinity, -.infinity, -1, 100.01] {
            var points = samples()
            points[10] = TimedMetricSample(timestamp: points[10].timestamp, value: value)
            let result = insights(InsightInput(cpuPoints: points, thermalLevel: 2))
            XCTAssertEqual(result.map(\.id), ["thermal"])
        }
        XCTAssertEqual(insights(InsightInput(cpuPoints: samples(value: 100))).count, 1)
    }

    func testInvalidCPUDateDuplicateAndOutOfOrderStreamsAreRejected() {
        var invalid = samples()
        invalid[10] = TimedMetricSample(timestamp: Date(timeIntervalSinceReferenceDate: .nan), value: 90)
        var duplicate = samples()
        duplicate.insert(duplicate[10], at: 10)
        var unordered = samples()
        unordered.swapAt(10, 11)
        for points in [invalid, duplicate, unordered, Array(samples().reversed())] {
            XCTAssertTrue(insights(InsightInput(cpuPoints: points)).isEmpty)
        }
    }

    func testInvalidEvaluationDateReturnsNoObservations() {
        let input = InsightInput(cpuPoints: samples(), thermalLevel: 3)
        for interval in [Double.nan, .infinity, -.infinity] {
            XCTAssertTrue(
                InsightEngine.insights(for: input, at: Date(timeIntervalSinceReferenceDate: interval)).isEmpty)
        }
    }

    func testMemoryHeadroomIsExplicitEstimateWithNumericFacts() throws {
        let observation = try XCTUnwrap(
            insights(
                InsightInput(
                    memoryHeadroomPercent: 10, memoryUsedBytes: 8 << 30,
                    memoryTotalBytes: 16 << 30, swapUsedBytes: 1 << 30)
            ).first)
        XCTAssertEqual(observation.metric, .memory)
        XCTAssertTrue(observation.detail.contains("free + cached"))
        XCTAssertTrue(observation.detail.contains("10.0%"))
        XCTAssertTrue(observation.detail.contains("<18%"))
        XCTAssertTrue(observation.detail.contains("not Activity Monitor"))
        XCTAssertTrue(observation.detail.contains("8.0 GiB of 16.0 GiB"))
        XCTAssertTrue(observation.detail.contains("Swap currently used: 1.0 GiB"))
        XCTAssertFalse(observation.detail.lowercased().contains("clean"))
    }

    func testMemoryHeadroomThresholdAndInvalidValues() {
        XCTAssertEqual(insights(InsightInput(memoryHeadroomPercent: 17.9)).count, 1)
        XCTAssertEqual(insights(InsightInput(memoryHeadroomPercent: 0)).count, 1)
        for value in [18, 100, -1, 101, Double.nan, .infinity] {
            XCTAssertTrue(insights(InsightInput(memoryHeadroomPercent: value)).isEmpty)
        }
    }

    func testSwapIsFactualEvenWithoutHeadroom() throws {
        let observation = try XCTUnwrap(insights(InsightInput(swapUsedBytes: 1)).first)
        XCTAssertEqual(observation.title, "Swap in use")
        XCTAssertTrue(observation.detail.contains("1 B"))
        XCTAssertTrue(observation.detail.contains("not a rate or proof of current pressure"))
        XCTAssertFalse(observation.detail.contains("headroom"))
        XCTAssertTrue(insights(InsightInput(swapUsedBytes: 0)).isEmpty)
        XCTAssertTrue(insights(InsightInput(memoryUsedBytes: 8 << 30, memoryTotalBytes: 8 << 30)).isEmpty)
    }

    func testInconsistentMemoryTotalsAreNotPresentedAsMeasurements() throws {
        for total in [UInt64(0), 1] {
            let observation = try XCTUnwrap(
                insights(InsightInput(memoryHeadroomPercent: 10, memoryUsedBytes: 2, memoryTotalBytes: total)).first)
            XCTAssertFalse(observation.detail.contains("memory in use"))
        }
    }

    func testUnsignedByteFormattingHandlesFullUInt64RangeWithoutNarrowing() throws {
        let observation = try XCTUnwrap(
            insights(
                InsightInput(
                    memoryHeadroomPercent: 0, memoryUsedBytes: .max,
                    memoryTotalBytes: .max, swapUsedBytes: .max)
            ).first)
        XCTAssertTrue(observation.detail.contains("16.0 EiB"))
        XCTAssertFalse(observation.detail.contains("-"))
        XCTAssertFalse(observation.detail.lowercased().contains("nan"))
    }

    func testDiskThresholdHasAPFSCaveatAndCorrectTarget() throws {
        let observation = try XCTUnwrap(insights(InsightInput(diskAvailableBytes: (5 << 30) - 1)).first)
        XCTAssertEqual(observation.metric, .disk)
        XCTAssertTrue(observation.detail.contains("below the 5 GiB threshold"))
        XCTAssertTrue(observation.detail.contains("APFS important-usage"))
        XCTAssertTrue(observation.detail.contains("not a measurement of purgeable bytes"))
        XCTAssertEqual(insights(InsightInput(diskAvailableBytes: 0)).count, 1)
        XCTAssertTrue(insights(InsightInput(diskAvailableBytes: 5 << 30)).isEmpty)
        XCTAssertTrue(insights(InsightInput(diskAvailableBytes: .max)).isEmpty)
    }

    func testThermalPublicOrdinalsOnlyQualifySeriousAndCritical() throws {
        for level in [-1, 0, 1, 4, Int.max] {
            XCTAssertTrue(insights(InsightInput(thermalLevel: level)).isEmpty)
        }
        for level in [2, 3] {
            let observation = try XCTUnwrap(insights(InsightInput(thermalLevel: level)).first)
            XCTAssertEqual(observation.id, "thermal")
            XCTAssertEqual(observation.metric, .power)
            XCTAssertTrue(observation.detail.contains("level \(level) of 0–3; threshold 2"))
            XCTAssertTrue(observation.detail.contains("not a temperature reading"))
        }
    }

    func testBatteryNeedsKnownValidChargeAndBatteryPower() throws {
        for charge in [0.0, 20] {
            let observation = try XCTUnwrap(
                insights(InsightInput(batteryChargePercent: charge, isOnBattery: true)).first)
            XCTAssertEqual(observation.metric, .power)
            XCTAssertEqual(observation.id, "battery-charge")
            XCTAssertTrue(observation.detail.contains("threshold ≤20%"))
        }
        XCTAssertTrue(insights(InsightInput(isOnBattery: true)).isEmpty)
        XCTAssertTrue(insights(InsightInput(batteryChargePercent: 10, isOnBattery: false)).isEmpty)
        for charge in [20.001, 100, -1, 101, Double.nan, .infinity] {
            XCTAssertTrue(insights(InsightInput(batteryChargePercent: charge, isOnBattery: true)).isEmpty)
        }
    }

    func testTopConsumerIsFreshMulticoreSnapshotNotCausalAttribution() throws {
        let observation = try XCTUnwrap(
            insights(
                InsightInput(
                    topConsumerName: "Renderer", topConsumerCPU: 245,
                    topConsumerSampledAt: now.addingTimeInterval(-15))
            ).first)
        XCTAssertEqual(observation.id, "cpu-consumer")
        XCTAssertEqual(observation.metric, .cpu)
        XCTAssertTrue(observation.detail.contains("245.0%"))
        XCTAssertTrue(observation.detail.contains("15.0 seconds ago"))
        XCTAssertTrue(observation.detail.contains("100% represents one core"))
        XCTAssertTrue(observation.detail.contains("does not establish the cause"))
    }

    func testConsumerMissingInvalidStaleOrFutureInputsAreOmitted() {
        for offset in [-15.001, 0.001] {
            XCTAssertTrue(
                insights(
                    InsightInput(
                        topConsumerName: "Renderer", topConsumerCPU: 100,
                        topConsumerSampledAt: now.addingTimeInterval(offset))
                ).isEmpty)
        }
        for cpu in [0, -1, Double.nan, .infinity] {
            XCTAssertTrue(
                insights(InsightInput(topConsumerName: "Renderer", topConsumerCPU: cpu, topConsumerSampledAt: now))
                    .isEmpty)
        }
        for input in [
            InsightInput(topConsumerCPU: 100, topConsumerSampledAt: now),
            InsightInput(topConsumerName: "Renderer", topConsumerSampledAt: now),
            InsightInput(topConsumerName: "Renderer", topConsumerCPU: 100),
            InsightInput(
                topConsumerName: "Renderer", topConsumerCPU: 100,
                topConsumerSampledAt: Date(timeIntervalSinceReferenceDate: .nan)),
            InsightInput(topConsumerName: " \n\u{202E}", topConsumerCPU: 100, topConsumerSampledAt: now),
        ] {
            XCTAssertTrue(insights(input).isEmpty)
        }
    }

    func testConsumerNamesAreBoundedVerbatimSafeDisplayAndNotIdentity() throws {
        let name = "\u{202E}App\u{0000}\n\u{202C} " + String(repeating: "x", count: 1_000)
        let observation = try XCTUnwrap(
            insights(InsightInput(topConsumerName: name, topConsumerCPU: 1, topConsumerSampledAt: now)).first)
        XCTAssertFalse(observation.detail.contains("\u{202E}"))
        XCTAssertFalse(observation.detail.contains("\u{202C}"))
        XCTAssertFalse(observation.detail.contains("\u{0000}"))
        XCTAssertFalse(observation.detail.contains("\n"))
        XCTAssertTrue(observation.detail.contains("…:"))
        XCTAssertLessThan(observation.detail.count, 450)
        let renamed = try XCTUnwrap(
            insights(InsightInput(topConsumerName: "Other app", topConsumerCPU: 300, topConsumerSampledAt: now)).first)
        XCTAssertEqual(observation.id, renamed.id)
        XCTAssertFalse(observation.id.contains("App"))
    }

    func testConsumerExtremeFiniteCPUIsSafeAndCompact() throws {
        let observation = try XCTUnwrap(
            insights(
                InsightInput(
                    topConsumerName: "Renderer", topConsumerCPU: .greatestFiniteMagnitude,
                    topConsumerSampledAt: now)
            ).first)
        XCTAssertLessThan(observation.detail.count, 400)
    }

    func testRulesAreDeterministicCappedAndHaveStableUniqueIDs() {
        let input = InsightInput(
            cpuPoints: samples(), memoryHeadroomPercent: 5, diskAvailableBytes: 1,
            batteryChargePercent: 10, isOnBattery: true, thermalLevel: 3,
            topConsumerName: "Renderer", topConsumerCPU: 200, topConsumerSampledAt: now)
        let first = insights(input)
        XCTAssertEqual(first, insights(input))
        XCTAssertEqual(first.count, InsightEngine.maximumInsights)
        XCTAssertEqual(first.map(\.id), ["thermal", "cpu-average", "memory-observation", "disk-availability"])
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        let changed = insights(
            InsightInput(
                cpuPoints: samples(value: 95), memoryHeadroomPercent: 1, diskAvailableBytes: 2, thermalLevel: 2))
        XCTAssertEqual(first.map(\.id), changed.map(\.id))
    }

    @MainActor
    func testCardContractAndDefensiveRowCap() {
        let rows = (0..<6).map {
            MonitoringInsight(id: "fixture-\($0)", title: "Observation", detail: "Measured detail", metric: .memory)
        }
        var selected: MetricTab?
        let card = InsightsCard(insights: rows) { selected = $0 }
        XCTAssertEqual(card.insights.count, 4)
        card.onSelect(.memory)
        XCTAssertEqual(selected, .memory)
    }

    /// Offscreen fixtures only: does not start telemetry or persist process names/screenshots.
    @MainActor
    func testCardRendersEmptyAndMeasuredContentInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for rows in [[], insights(InsightInput(cpuPoints: samples(), memoryHeadroomPercent: 10))] {
                let card = InsightsCard(insights: rows) { _ in }
                    .frame(width: 380)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: card)
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertGreaterThan(image.size.height, 100)
                XCTAssertEqual(image.size.width, 380)
            }
        }
    }
}
