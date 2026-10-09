import AppKit

/// Bounded, template status artwork. Numeric titles use native, appearance-aware text separately.
enum MenuBarRenderer {
    /// A visualization ceiling, not a claim about the Mac's link capacity.
    private static let networkGaugeCeiling = 2.0 * 1_048_576

    static func image(
        readings: MenuBarReadings,
        metrics: [MenuBarMetric],
        style: Preferences.MenuBarStyle
    ) -> NSImage {
        let metrics = MenuBarMetric.normalized(metrics)
        let description = accessibilityDescription(readings: readings, metrics: metrics)
        let image: NSImage
        switch style {
        case .gauges:
            image = NSImage(size: NSSize(width: metrics.count * 26, height: 18), flipped: false) { _ in
                for (index, metric) in metrics.enumerated() {
                    drawLabeledBar(
                        x: CGFloat(index * 26), label: gaugeLabel(metric),
                        value: gaugeValue(metric, readings: readings))
                }
                return true
            }
        case .compact, .detailed, .iconOnly:
            // A generic pulse, never CPU/memory gauges masquerading as an icon-only style.
            image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
                let pulse = NSBezierPath()
                pulse.move(to: NSPoint(x: 1, y: 9))
                for point in [
                    NSPoint(x: 5, y: 9), NSPoint(x: 7, y: 15), NSPoint(x: 10, y: 3),
                    NSPoint(x: 12, y: 9), NSPoint(x: 17, y: 9),
                ] {
                    pulse.line(to: point)
                }
                pulse.lineWidth = 1.5
                pulse.lineJoinStyle = .round
                pulse.lineCapStyle = .round
                NSColor.black.setStroke()  // Template alpha, not a fixed light/dark foreground.
                pulse.stroke()
                return true
            }
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    static func title(
        readings: MenuBarReadings,
        metrics: [MenuBarMetric],
        style: Preferences.MenuBarStyle
    ) -> NSAttributedString {
        let metrics = MenuBarMetric.normalized(metrics)
        let text: String
        switch style {
        case .gauges, .iconOnly:
            text = ""
        case .compact, .detailed:
            text = metrics.map { metric in
                numericTitle(metric, readings: readings, detailed: style == .detailed)
            }.joined(separator: "  ")
        }
        // Five metrics remain readable without consuming an unbounded status-item width.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: metrics.count > 3 ? 10 : 11, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    static func accessibilityDescription(readings: MenuBarReadings, metrics: [MenuBarMetric]) -> String {
        MenuBarMetric.normalized(metrics).map { metric in
            switch metric {
            case .network:
                return "Network: download \(spokenRate(readings.networkDownloadBps)), "
                    + "upload \(spokenRate(readings.networkUploadBps)); aggregate \(spokenRate(aggregateRate(readings))); "
                    + "aggregate gauge full scale "
                    + "2 MiB/s (download + upload, clamped)"
            case .disk:
                let capacity = readings.diskAvailableBytes.map { "\($0) bytes available" } ?? "availability unavailable"
                return "Disk: home volume, \(spokenPercent(readings.diskUsedPercent)) used; \(capacity)"
            case .cpu:
                return "CPU: \(spokenPercent(readings.cpuPercent))"
            case .memory:
                return "Memory: \(spokenPercent(readings.memoryPercent))"
            case .battery:
                return "Battery: \(spokenPercent(readings.batteryChargePercent))"
            }
        }.joined(separator: "; ")
    }

    // MARK: - Compatibility (no preference reads or writes)

    static func image(
        cpu: Double, memory: Double, netIn: Double, netOut: Double,
        style: Preferences.MenuBarStyle, showNetwork: Bool
    ) -> NSImage {
        image(
            readings: MenuBarReadings(
                cpuPercent: cpu, memoryPercent: memory, networkDownloadBps: netIn, networkUploadBps: netOut),
            metrics: showNetwork ? [.cpu, .memory, .network] : [.cpu, .memory], style: style)
    }

    static func title(
        cpu: Double, memory: Double, netIn: Double, netOut: Double,
        style: Preferences.MenuBarStyle, showNetwork: Bool
    ) -> NSAttributedString {
        title(
            readings: MenuBarReadings(
                cpuPercent: cpu, memoryPercent: memory, networkDownloadBps: netIn, networkUploadBps: netOut),
            metrics: showNetwork ? [.cpu, .memory, .network] : [.cpu, .memory], style: style)
    }

    // MARK: - Validation and bounded formatting

    private static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value  // Normalize signed zero for both text and geometry.
    }

    private static func aggregateRate(_ readings: MenuBarReadings) -> Double? {
        guard let download = valid(readings.networkDownloadBps), let upload = valid(readings.networkUploadBps) else {
            return nil
        }
        return valid(download + upload)  // Overflow is unknown, not infinity or a fabricated zero.
    }

    private static func percent(_ value: Double?) -> String {
        guard let value = valid(value) else { return "—" }
        return value < 1000 ? String(format: "%.0f%%", value) : String(format: "%.1e%%", value)
    }

    private static func rate(_ value: Double?) -> String {
        guard let original = valid(value) else { return "—" }
        var value = original
        let units = ["B/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s", "PiB/s", "EiB/s"]
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == units.count - 1, value >= 1000 {
            return String(format: "%.1eB/s", original)
        }
        return String(format: unit == 0 || value >= 10 ? "%.0f%@" : "%.1f%@", value, units[unit])
    }

    /// Unsigned integer arithmetic throughout: UInt64.max is never narrowed to Int64 or rounded via Double.
    private static func capacity(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
        var divisor: UInt64 = 1
        var unit = 0
        while bytes / divisor >= 1024, unit < units.count - 1 {
            divisor *= 1024
            unit += 1
        }
        let whole = bytes / divisor
        if unit == 0 { return "\(whole)B" }
        // Truncate displayed tenths; the accessibility description retains the exact byte count.
        // The largest divisor is 2^60, so multiplying its remainder by ten cannot overflow UInt64.
        let tenth = (bytes % divisor) * 10 / divisor
        return "\(whole).\(tenth)\(units[unit])"
    }

    private static func spokenPercent(_ value: Double?) -> String {
        valid(value) == nil ? "unavailable" : percent(value)
    }

    private static func spokenRate(_ value: Double?) -> String {
        valid(value) == nil ? "unavailable" : rate(value)
    }

    private static func numericTitle(_ metric: MenuBarMetric, readings: MenuBarReadings, detailed: Bool) -> String {
        switch metric {
        case .cpu: return "CPU \(percent(readings.cpuPercent))"
        case .memory: return "MEM \(percent(readings.memoryPercent))"
        case .battery: return "BAT \(percent(readings.batteryChargePercent))"
        case .disk:
            return detailed
                ? "DISK \(capacity(readings.diskAvailableBytes)) free" : "DISK \(percent(readings.diskUsedPercent))"
        case .network:
            return detailed
                ? "NET ↓\(rate(readings.networkDownloadBps)) ↑\(rate(readings.networkUploadBps))"
                : "NET \(rate(aggregateRate(readings)))"
        }
    }

    private static func gaugeLabel(_ metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu: return "C"
        case .memory: return "M"
        case .network: return "N"
        case .disk: return "D"
        case .battery: return "B"
        }
    }

    private static func gaugeValue(_ metric: MenuBarMetric, readings: MenuBarReadings) -> Double? {
        let value: Double?
        switch metric {
        case .cpu: value = valid(readings.cpuPercent).map { $0 / 100 }
        case .memory: value = valid(readings.memoryPercent).map { $0 / 100 }
        case .network: value = aggregateRate(readings).map { $0 / networkGaugeCeiling }
        case .disk: value = valid(readings.diskUsedPercent).map { $0 / 100 }
        case .battery: value = valid(readings.batteryChargePercent).map { $0 / 100 }
        }
        return value.map { min(1, $0) }
    }

    // MARK: - Drawing

    private static func drawLabeledBar(x: CGFloat, label: String, value: Double?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (label as NSString).draw(
            in: NSRect(x: x, y: 2, width: 8, height: 14),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
            ])
        let track = NSRect(x: x + 9, y: 4, width: 14, height: 10)
        let outline = NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5)
        outline.lineWidth = 0.75
        NSColor.black.setStroke()
        outline.stroke()
        let interior = track.insetBy(dx: 1, dy: 1)
        guard let value else {
            // Unknown is visibly different from a measured empty track.
            let dash = NSBezierPath()
            dash.move(to: NSPoint(x: interior.minX + 2, y: interior.midY))
            dash.line(to: NSPoint(x: interior.maxX - 2, y: interior.midY))
            dash.lineWidth = 1
            dash.stroke()
            return
        }
        guard value > 0 else { return }  // A legitimate zero has exactly zero fill.
        NSColor.black.setFill()
        NSRect(x: interior.minX, y: interior.minY, width: interior.width, height: interior.height * CGFloat(value))
            .fill()
    }
}
