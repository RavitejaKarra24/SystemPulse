import Foundation

extension MonitorStore {
    /// Capture latest-known readings once, only on user request. Device identity,
    /// process lists, IP addresses, paths and volume names never cross this boundary.
    func diagnosticSnapshot(capturedAt: Date = .now) -> DiagnosticSnapshot {
        let memoryAvailable = memoryTotal > 0
        let networkAvailable = netInHistory.count > 1 && networkInterfaces.contains(where: \.isPresent)
        let capacityTotal = selectedVolume.map(\.totalBytes) ?? (diskTotal > 0 ? diskTotal : nil)
        // A selected volume with unavailable metadata must not silently export home-volume values.
        let capacityAvailable = selectedVolume.map(\.availableBytes) ?? (diskTotal > 0 ? diskFree : nil)
        let pressure: DiagnosticMemoryPressure?
        if memoryAvailable {
            switch memoryBreakdown.pressure {
            case .normal: pressure = .normal
            case .warning: pressure = .warning
            case .critical: pressure = .critical
            }
        } else {
            pressure = nil
        }
        return DiagnosticSnapshot(
            capturedAt: capturedAt,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
            cpuPercent: hasCPUReading ? Self.nonnegativeFinite(cpuUsage) : nil,
            memoryUsedBytes: memoryAvailable ? memoryUsed : nil,
            memoryTotalBytes: memoryAvailable ? memoryTotal : nil,
            swapUsedBytes: memoryBreakdown.swapUsed,
            memoryPressureEstimate: pressure,
            networkDownloadBytesPerSecond: networkAvailable ? Self.nonnegativeFinite(netInRate) : nil,
            networkUploadBytesPerSecond: networkAvailable ? Self.nonnegativeFinite(netOutRate) : nil,
            networkSessionBytesIn: networkAvailable ? sessionBytesIn : nil,
            networkSessionBytesOut: networkAvailable ? sessionBytesOut : nil,
            volumeTotalBytes: capacityTotal,
            volumeAvailableBytes: capacityAvailable,
            batteryChargePercent: power.hasBattery && power.hasChargeReading
                ? Self.nonnegativeFinite(power.chargePercent) : nil,
            batteryHealthPercent: power.healthPercent > 0 ? Self.nonnegativeFinite(power.healthPercent) : nil,
            isCharging: power.hasChargeReading ? power.isCharging : nil,
            isPluggedIn: power.isPluggedIn ? true : (power.hasChargeReading ? false : nil),
            lowPowerModeEnabled: power.lowPowerModeEnabled,
            systemPowerWatts: power.systemPowerWatts.flatMap(Self.nonnegativeFinite),
            batteryPowerWatts: power.batteryPowerWatts.flatMap { $0.isFinite ? $0 : nil },
            history: diagnosticHistory(endingAt: capturedAt)
        )
    }

    private func diagnosticHistory(endingAt timestamp: Date) -> [DiagnosticHistoryRow]? {
        // Export a fixed, disclosed window, independent of any frozen/selected chart.
        let series: [(DiagnosticMetric, MetricHistory)] = [
            (.cpuPercent, cpuTimeline), (.memoryUsedBytes, memoryTimeline),
            (.networkDownloadBytesPerSecond, downloadTimeline),
            (.networkUploadBytesPerSecond, uploadTimeline), (.systemPowerWatts, powerDrawTimeline),
        ]
        var rows: [DiagnosticHistoryRow] = []
        for (metric, history) in series {
            for point in history.points(in: .fiveMinutes, endingAt: timestamp) {
                rows.append(DiagnosticHistoryRow(timestamp: point.timestamp, metric: metric, value: point.value))
            }
        }
        rows.sort {
            if $0.timestamp == $1.timestamp { return $0.metric.rawValue < $1.metric.rawValue }
            return $0.timestamp < $1.timestamp
        }
        return rows.isEmpty ? nil : rows
    }

    private static func nonnegativeFinite(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }
}
