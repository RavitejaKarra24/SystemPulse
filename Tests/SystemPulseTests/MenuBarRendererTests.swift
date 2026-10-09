import AppKit
import XCTest

@testable import SystemPulse

final class MenuBarRendererTests: XCTestCase {
    private let fixture = MenuBarReadings(
        cpuPercent: 25, memoryPercent: 50,
        networkDownloadBps: 1_048_576, networkUploadBps: 1024,
        diskUsedPercent: 75, diskAvailableBytes: 10 << 30, batteryChargePercent: 80)

    func testMetricIdentifiersTitlesSymbolsAndCodable() throws {
        XCTAssertEqual(MenuBarMetric.allCases.map(\.rawValue), ["cpu", "memory", "network", "disk", "battery"])
        XCTAssertEqual(MenuBarMetric.allCases.map(\.id), MenuBarMetric.allCases.map(\.rawValue))
        XCTAssertEqual(MenuBarMetric.allCases.map(\.title), ["CPU", "Memory", "Network", "Disk", "Battery"])
        for metric in MenuBarMetric.allCases {
            XCTAssertFalse(metric.symbol.isEmpty)
            XCTAssertNotNil(NSImage(systemSymbolName: metric.symbol, accessibilityDescription: metric.title))
            XCTAssertEqual(try JSONDecoder().decode(MenuBarMetric.self, from: JSONEncoder().encode(metric)), metric)
        }
    }

    func testReadingsDefaultToUnavailableAndNormalizeWithoutReordering() {
        let empty = MenuBarReadings()
        XCTAssertNil(empty.cpuPercent)
        XCTAssertNil(empty.memoryPercent)
        XCTAssertNil(empty.networkDownloadBps)
        XCTAssertNil(empty.networkUploadBps)
        XCTAssertNil(empty.diskUsedPercent)
        XCTAssertNil(empty.diskAvailableBytes)
        XCTAssertNil(empty.batteryChargePercent)
        XCTAssertEqual(MenuBarMetric.normalized([]), [.cpu])
        XCTAssertEqual(MenuBarMetric.normalized([.battery, .disk, .battery, .cpu, .disk]), [.battery, .disk, .cpu])
        XCTAssertEqual(MenuBarMetric.normalized(Array(repeating: .memory, count: 100_000) + [.cpu]), [.memory])
    }

    @MainActor
    func testEveryStyleAndIndividualMetricHasNamedAccessibilityAndNativeArtwork() throws {
        for style in Preferences.MenuBarStyle.allCases {
            for metric in MenuBarMetric.allCases {
                let image = MenuBarRenderer.image(readings: fixture, metrics: [metric], style: style)
                XCTAssertTrue(image.isTemplate)
                XCTAssertEqual(image.size.height, 18)
                XCTAssertTrue(image.size.width.isFinite && image.size.width > 0)
                XCTAssertTrue(image.accessibilityDescription?.contains(metric.title) == true)
                let title = MenuBarRenderer.title(readings: fixture, metrics: [metric], style: style)
                XCTAssertEqual(title.length == 0, style == .gauges || style == .iconOnly)
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    let bitmap = try rasterize(image, appearance: appearance)
                    assertPixelBounds(bitmap)
                }
            }
        }
    }

    @MainActor
    func testChosenOrderInEveryStyleAndGaugePixels() throws {
        let metrics: [MenuBarMetric] = [.battery, .disk, .network, .memory, .cpu]
        for style in Preferences.MenuBarStyle.allCases {
            let image = MenuBarRenderer.image(readings: fixture, metrics: metrics, style: style)
            let title = MenuBarRenderer.title(readings: fixture, metrics: metrics, style: style)
            let description = MenuBarRenderer.accessibilityDescription(readings: fixture, metrics: metrics)
            assertOrdered(["Battery:", "Disk:", "Network:", "Memory:", "CPU:"], in: description)
            if style == .compact || style == .detailed {
                assertOrdered(["BAT", "DISK", "NET", "MEM", "CPU"], in: title.string)
                XCTAssertLessThanOrEqual(title.size().width + image.size.width, 420)
            } else if style == .gauges {
                XCTAssertEqual(image.size.width, 130)
                let bitmap = try rasterize(image)
                // A reversed list must reverse cells, not just their accessibility names.
                let reversed = try rasterize(
                    MenuBarRenderer.image(readings: fixture, metrics: metrics.reversed(), style: style))
                for index in 0..<5 {
                    XCTAssertEqual(cellAlpha(bitmap, index: index), cellAlpha(reversed, index: 4 - index))
                }
            }
        }
    }

    func testTitlesUseRealValuesAndExplicitUnits() {
        XCTAssertEqual(
            MenuBarRenderer.title(readings: fixture, metrics: MenuBarMetric.allCases, style: .compact).string,
            "CPU 25%  MEM 50%  NET 1.0MiB/s  DISK 75%  BAT 80%")
        XCTAssertEqual(
            MenuBarRenderer.title(readings: fixture, metrics: [.network, .disk], style: .detailed).string,
            "NET ↓1.0MiB/s ↑1.0KiB/s  DISK 10.0GiB free")
        let description = MenuBarRenderer.accessibilityDescription(readings: fixture, metrics: [.network, .disk])
        XCTAssertTrue(description.contains("2 MiB/s (download + upload, clamped)"))
        XCTAssertTrue(description.contains("10737418240 bytes available"))
        XCTAssertTrue(description.contains("Disk: home volume"))
    }

    @MainActor
    func testUnknownZeroNegativeAndNonfiniteAcrossAllStyles() throws {
        let values: [Double?] = [nil, 0, -Double.zero, -1, .nan, .infinity, -.infinity, .greatestFiniteMagnitude]
        for value in values {
            let readings = MenuBarReadings(
                cpuPercent: value, memoryPercent: value,
                networkDownloadBps: value, networkUploadBps: value,
                diskUsedPercent: value, batteryChargePercent: value)
            for style in Preferences.MenuBarStyle.allCases {
                let image = MenuBarRenderer.image(readings: readings, metrics: MenuBarMetric.allCases, style: style)
                let title = MenuBarRenderer.title(readings: readings, metrics: MenuBarMetric.allCases, style: style)
                let description = MenuBarRenderer.accessibilityDescription(
                    readings: readings, metrics: MenuBarMetric.allCases)
                XCTAssertTrue(image.size.width.isFinite && image.size.height.isFinite)
                XCTAssertLessThanOrEqual(image.size.width, 130)
                XCTAssertLessThan(title.size().width, 650)
                XCTAssertFalse(title.string.lowercased().contains("nan"))
                XCTAssertFalse(title.string.lowercased().contains("inf"))
                if value == nil || value?.isFinite == false || (value ?? 0) < 0 {
                    XCTAssertTrue(description.contains("Battery: unavailable"))
                    if style == .compact || style == .detailed {
                        XCTAssertTrue(title.string.contains("CPU —"))
                        XCTAssertFalse(title.string.contains("0%"))
                    }
                } else if value == 0 {
                    XCTAssertTrue(description.contains("Battery: 0%"))
                    if style == .compact {
                        XCTAssertTrue(title.string.contains("NET 0B/s"))
                    }
                }
                assertPixelBounds(try rasterize(image))
            }
        }
    }

    @MainActor
    func testZeroHasNoFillUnknownHasDashAndGeometryClampsAtFull() throws {
        let zero = try rasterize(
            MenuBarRenderer.image(readings: MenuBarReadings(cpuPercent: 0), metrics: [.cpu], style: .gauges))
        let unknown = try rasterize(MenuBarRenderer.image(readings: MenuBarReadings(), metrics: [.cpu], style: .gauges))
        let full = try rasterize(
            MenuBarRenderer.image(readings: MenuBarReadings(cpuPercent: 100), metrics: [.cpu], style: .gauges))
        let over = try rasterize(
            MenuBarRenderer.image(
                readings: MenuBarReadings(cpuPercent: .greatestFiniteMagnitude), metrics: [.cpu], style: .gauges))
        // Interior excludes the outline. At 2x this is the center of the bar, not its label.
        XCTAssertEqual(interiorAlpha(zero), 0)
        XCTAssertGreaterThan(interiorAlpha(unknown), 0)
        XCTAssertGreaterThan(interiorAlpha(full), interiorAlpha(unknown))
        XCTAssertEqual(cellAlpha(full, index: 0), cellAlpha(over, index: 0))
    }

    @MainActor
    func testNetworkAggregateCeilingAndMissingHalf() throws {
        let atCeiling = MenuBarReadings(networkDownloadBps: 1_048_576, networkUploadBps: 1_048_576)
        let above = MenuBarReadings(networkDownloadBps: 10_485_760, networkUploadBps: 1_048_576)
        let missing = MenuBarReadings(networkDownloadBps: 0)
        let full = try rasterize(MenuBarRenderer.image(readings: atCeiling, metrics: [.network], style: .gauges))
        let clamped = try rasterize(MenuBarRenderer.image(readings: above, metrics: [.network], style: .gauges))
        XCTAssertEqual(cellAlpha(full, index: 0), cellAlpha(clamped, index: 0))
        XCTAssertEqual(MenuBarRenderer.title(readings: missing, metrics: [.network], style: .compact).string, "NET —")
        XCTAssertEqual(
            MenuBarRenderer.title(readings: missing, metrics: [.network], style: .detailed).string, "NET ↓0B/s ↑—")
        XCTAssertEqual(
            MenuBarRenderer.title(
                readings: MenuBarReadings(
                    networkDownloadBps: .greatestFiniteMagnitude, networkUploadBps: .greatestFiniteMagnitude),
                metrics: [.network], style: .compact
            ).string, "NET —")
    }

    func testRateBoundariesAndTitlesDoNotClampMeasuredPercentages() {
        for (value, expected) in [(0.0, "0B/s"), (1000, "1000B/s"), (1023, "1023B/s"), (1024, "1.0KiB/s")] {
            XCTAssertEqual(
                MenuBarRenderer.title(
                    readings: MenuBarReadings(networkDownloadBps: value, networkUploadBps: 0),
                    metrics: [.network], style: .compact
                ).string,
                "NET \(expected)")
        }
        XCTAssertEqual(
            MenuBarRenderer.title(readings: MenuBarReadings(cpuPercent: 175), metrics: [.cpu], style: .compact).string,
            "CPU 175%")
    }

    func testUnsignedCapacityFormattingAndExactDescription() {
        let cases: [(UInt64?, String)] = [
            (nil, "—"), (0, "0B"), (1023, "1023B"), (1024, "1.0KiB"),
            (1536, "1.5KiB"), (UInt64.max, "15.9EiB"),
        ]
        for (bytes, expected) in cases {
            let readings = MenuBarReadings(diskAvailableBytes: bytes)
            XCTAssertEqual(
                MenuBarRenderer.title(readings: readings, metrics: [.disk], style: .detailed).string,
                "DISK \(expected) free")
            if let bytes {
                XCTAssertTrue(
                    MenuBarRenderer.accessibilityDescription(readings: readings, metrics: [.disk]).contains(
                        "\(bytes) bytes available"))
            }
        }
    }

    @MainActor
    func testIconIsIndependentOfReadingsAndSelection() throws {
        let first = try rasterize(
            MenuBarRenderer.image(readings: fixture, metrics: [.battery, .disk], style: .iconOnly))
        let second = try rasterize(MenuBarRenderer.image(readings: MenuBarReadings(), metrics: [], style: .iconOnly))
        XCTAssertEqual(cellAlpha(first, index: 0, cellWidth: 18), cellAlpha(second, index: 0, cellWidth: 18))
    }

    @MainActor
    func testNormalizationAppliesToAllRendererEntryPointsAndLegacyWrappers() throws {
        for style in Preferences.MenuBarStyle.allCases {
            let unreasonable = Array(repeating: MenuBarMetric.allCases, count: 20_000).flatMap { $0 }
            XCTAssertEqual(
                MenuBarRenderer.title(readings: fixture, metrics: unreasonable, style: style).string,
                MenuBarRenderer.title(readings: fixture, metrics: MenuBarMetric.allCases, style: style).string)
            XCTAssertEqual(
                MenuBarRenderer.image(readings: fixture, metrics: unreasonable, style: style).size,
                MenuBarRenderer.image(readings: fixture, metrics: MenuBarMetric.allCases, style: style).size)
            let duplicate: [MenuBarMetric] = [.battery, .cpu, .battery, .cpu]
            XCTAssertEqual(
                MenuBarRenderer.title(readings: fixture, metrics: duplicate, style: style).string,
                MenuBarRenderer.title(readings: fixture, metrics: [.battery, .cpu], style: style).string)
            XCTAssertEqual(
                MenuBarRenderer.image(readings: fixture, metrics: duplicate, style: style).size,
                MenuBarRenderer.image(readings: fixture, metrics: [.battery, .cpu], style: style).size)
            XCTAssertEqual(
                MenuBarRenderer.title(readings: fixture, metrics: [], style: style).string,
                MenuBarRenderer.title(readings: fixture, metrics: [.cpu], style: style).string)
            for showNetwork in [false, true] {
                let metrics: [MenuBarMetric] = showNetwork ? [.cpu, .memory, .network] : [.cpu, .memory]
                XCTAssertEqual(
                    MenuBarRenderer.title(
                        cpu: 25, memory: 50, netIn: 1_048_576, netOut: 1024, style: style, showNetwork: showNetwork
                    ).string,
                    MenuBarRenderer.title(readings: fixture, metrics: metrics, style: style).string)
                let legacy = MenuBarRenderer.image(
                    cpu: 25, memory: 50, netIn: 1_048_576, netOut: 1024, style: style, showNetwork: showNetwork)
                let modern = MenuBarRenderer.image(readings: fixture, metrics: metrics, style: style)
                XCTAssertEqual(legacy.size, modern.size)
                XCTAssertEqual(legacy.accessibilityDescription, modern.accessibilityDescription)
                assertPixelBounds(try rasterize(legacy))
            }
        }
        XCTAssertEqual(
            MenuBarRenderer.accessibilityDescription(readings: fixture, metrics: [.disk, .disk, .cpu]),
            MenuBarRenderer.accessibilityDescription(readings: fixture, metrics: [.disk, .cpu]))
        XCTAssertEqual(
            MenuBarRenderer.accessibilityDescription(readings: fixture, metrics: []),
            MenuBarRenderer.accessibilityDescription(readings: fixture, metrics: [.cpu]))
    }

    private func assertOrdered(_ tokens: [String], in text: String, file: StaticString = #filePath, line: UInt = #line)
    {
        var remaining = text[...]
        for token in tokens {
            guard let range = remaining.range(of: token) else {
                XCTFail("Missing or out-of-order \(token) in \(text)", file: file, line: line)
                return
            }
            remaining = remaining[range.upperBound...]
        }
    }

    /// Native AppKit drawing into a deterministic 2x transparent bitmap; no window or preferences needed.
    @MainActor
    private func rasterize(_ image: NSImage, appearance: NSAppearance.Name = .aqua) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = image.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        let appearance = try XCTUnwrap(NSAppearance(named: appearance))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1)
        }
        return bitmap
    }

    private func assertPixelBounds(_ bitmap: NSBitmapImageRep, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(bitmap.pixelsWide, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(bitmap.pixelsWide, 260, file: file, line: line)
        XCTAssertEqual(bitmap.pixelsHigh, 36, file: file, line: line)
        var visible = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y) else {
                    XCTFail("Unreadable pixel", file: file, line: line)
                    return
                }
                XCTAssertTrue(color.alphaComponent.isFinite, file: file, line: line)
                XCTAssertTrue((0...1).contains(color.alphaComponent), file: file, line: line)
                if color.alphaComponent > 0 { visible += 1 }
            }
        }
        XCTAssertGreaterThan(visible, 0, file: file, line: line)
        XCTAssertLessThan(visible, bitmap.pixelsWide * bitmap.pixelsHigh, file: file, line: line)
    }

    private func cellAlpha(_ bitmap: NSBitmapImageRep, index: Int, cellWidth: Int = 26) -> [CGFloat] {
        (0..<bitmap.pixelsHigh).flatMap { y in
            (index * cellWidth * 2..<(index + 1) * cellWidth * 2).map { x in
                bitmap.colorAt(x: x, y: y)?.alphaComponent ?? -1
            }
        }
    }

    private func interiorAlpha(_ bitmap: NSBitmapImageRep) -> CGFloat {
        (12..<24).reduce(CGFloat.zero) { total, y in
            total
                + (22..<42).reduce(CGFloat.zero) { subtotal, x in
                    subtotal + (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                }
        }
    }
}
