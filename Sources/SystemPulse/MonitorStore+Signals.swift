import Foundation

extension MonitorStore {
    /// Only fresh, supported values cross the menu-bar / alert boundary. The
    /// overview and menu bar always describe aggregate networking and home capacity.
    func menuBarReadings(at timestamp: Date = .now) -> MenuBarReadings {
        let countersFresh = isFresh(latestSampleAt, at: timestamp, within: 15)
        let diskFresh = isFresh(latestHomeDiskSampleAt, at: timestamp, within: 25) && diskTotal > 0
        let powerFresh = isFresh(latestPowerSampleAt, at: timestamp, within: 15)
        let networkKnown = countersFresh && netInHistory.count >= 2 && networkInterfaces.contains(where: \.isPresent)
        return MenuBarReadings(
            cpuPercent: isFresh(latestCPUSampleAt, at: timestamp, within: 15) && !perCoreCPU.isEmpty ? cpuUsage : nil,
            memoryPercent: isFresh(latestMemorySampleAt, at: timestamp, within: 15) && memoryTotal > 0
                ? memoryUsage : nil,
            networkDownloadBps: networkKnown ? netInRate : nil,
            networkUploadBps: networkKnown ? netOutRate : nil,
            diskUsedPercent: diskFresh ? diskUsage : nil,
            diskAvailableBytes: diskFresh ? diskFree : nil,
            batteryChargePercent: powerFresh && power.hasBattery && power.hasChargeReading ? power.chargePercent : nil
        )
    }

    func alertMeasurements(at timestamp: Date) -> [AlertKind: Double] {
        let readings = menuBarReadings(at: timestamp)
        var measurements: [AlertKind: Double] = [:]
        if let cpu = readings.cpuPercent, cpu.isFinite, (0...100).contains(cpu) { measurements[.cpuUsage] = cpu }
        if let headroom = memoryHeadroom(at: timestamp) { measurements[.memoryHeadroom] = headroom }
        if let available = readings.diskAvailableBytes { measurements[.diskAvailable] = Double(available) }
        if let charge = readings.batteryChargePercent, !power.isPluggedIn, !power.isCharging,
            charge.isFinite, (0...100).contains(charge)
        {
            measurements[.batteryCharge] = charge
        }
        if isFresh(latestThermalSampleAt, at: timestamp, within: 15) {
            let level = systemInfo.thermalState.rawValue
            if (0...3).contains(level) { measurements[.thermal] = Double(level) }
        }
        return measurements
    }

    func sampledAlertMeasurements(at timestamp: Date) -> [AlertKind: SampledAlertValue] {
        var result: [AlertKind: SampledAlertValue] = [:]
        for (kind, value) in alertMeasurements(at: timestamp) {
            let date: Date?
            switch kind {
            case .cpuUsage: date = latestCPUSampleAt
            case .memoryHeadroom: date = latestMemorySampleAt
            case .diskAvailable: date = latestHomeDiskSampleAt
            case .batteryCharge: date = latestPowerSampleAt
            case .thermal: date = latestThermalSampleAt
            }
            if let date { result[kind] = SampledAlertValue(value: value, sampledAt: date) }
        }
        return result
    }

    func monitoringInsights(at timestamp: Date = .now, visibleModules: [MetricTab]? = nil) -> [MonitoringInsight] {
        let readings = menuBarReadings(at: timestamp)
        let memoryKnown = readings.memoryPercent != nil
        let cpuKnown = readings.cpuPercent.map { $0.isFinite && (0...100).contains($0) } ?? false
        let input = InsightInput(
            cpuPoints: cpuKnown ? cpuTimeline.points(in: .fiveMinutes, endingAt: timestamp) : [],
            memoryHeadroomPercent: memoryHeadroom(at: timestamp),
            memoryUsedBytes: memoryKnown ? memoryUsed : nil,
            memoryTotalBytes: memoryKnown ? memoryTotal : nil,
            swapUsedBytes: memoryKnown ? memoryBreakdown.swapUsed : nil,
            diskAvailableBytes: readings.diskAvailableBytes,
            batteryChargePercent: readings.batteryChargePercent,
            isOnBattery: power.hasBattery && power.hasChargeReading && !power.isPluggedIn && !power.isCharging,
            thermalLevel: isFresh(latestThermalSampleAt, at: timestamp, within: 15)
                ? systemInfo.thermalState.rawValue : nil,
            topConsumerName: topProcessName == "—" ? nil : topProcessName,
            topConsumerCPU: latestProcessSampleAt == nil ? nil : topProcessCPU,
            topConsumerSampledAt: latestProcessSampleAt
        )
        return InsightEngine.insights(for: input, at: timestamp, visibleMetrics: visibleModules.map { Set($0) })
    }

    private func memoryHeadroom(at timestamp: Date) -> Double? {
        guard isFresh(latestMemorySampleAt, at: timestamp, within: 15), memoryTotal > 0 else { return nil }
        // Convert before addition: no unsigned overflow, and this remains explicitly
        // estimated free+cached headroom, not the Activity Monitor pressure signal.
        let available = Double(memoryBreakdown.free) + Double(memoryBreakdown.cached)
        return min(100, max(0, available / Double(memoryTotal) * 100))
    }

    private func isFresh(_ sampledAt: Date?, at timestamp: Date, within limit: TimeInterval) -> Bool {
        guard let sampledAt else { return false }
        let age = timestamp.timeIntervalSince(sampledAt)
        return age.isFinite && age >= 0 && age <= limit
    }
}
