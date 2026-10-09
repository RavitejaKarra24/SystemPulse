import Foundation
import UniformTypeIdentifiers

/// The only numeric measurements permitted in schema v1. Names also identify CSV rows
/// and JSON fields; history must use these same raw units, not formatted chart values.
enum DiagnosticMetric: String, Codable, CaseIterable, Sendable {
    case cpuPercent
    case memoryUsedBytes
    case memoryTotalBytes
    case swapUsedBytes
    case networkDownloadBytesPerSecond
    case networkUploadBytesPerSecond
    case networkSessionBytesIn
    case networkSessionBytesOut
    case volumeTotalBytes
    case volumeAvailableBytes
    case batteryChargePercent
    case batteryHealthPercent
    case systemPowerWatts
    case batteryPowerWatts

    var unit: DiagnosticUnit {
        switch self {
        case .cpuPercent, .batteryChargePercent, .batteryHealthPercent: return .percent
        case .networkDownloadBytesPerSecond, .networkUploadBytesPerSecond: return .bytesPerSecond
        case .systemPowerWatts, .batteryPowerWatts: return .watts
        default: return .bytes
        }
    }
}

enum DiagnosticUnit: String, Codable, Sendable {
    case percent, bytes, bytesPerSecond, watts, boolean, text, count
}

/// Explicitly an estimate of headroom, NOT the macOS memory-pressure signal.
enum DiagnosticMemoryPressure: String, Codable, Sendable {
    case normal = "Estimated: Normal"
    case warning = "Estimated: Elevated"
    case critical = "Estimated: Critical"
}

struct DiagnosticHistoryRow: Codable, Sendable, Equatable {
    let timestamp: Date
    let metric: DiagnosticMetric
    let unit: DiagnosticUnit
    let value: Double

    init(timestamp: Date, metric: DiagnosticMetric, value: Double) {
        self.timestamp = timestamp
        self.metric = metric
        self.unit = metric.unit
        self.value = value
    }
}

/// Privacy allowlist: no process/device/interface/volume identity or paths.
/// All measurements may be nil while unavailable; nil JSON fields are omitted.
/// Network inputs MUST aggregate physical interfaces only. Session bytes are since
/// monitoring began, not lifetime interface counters. Volume available bytes must
/// retain the sampler's capacity semantics; they are not claimed as purgeable space.
/// History is caller-selected for ONE window, in caller order; no history is collected
/// here. Omit it with nil; [] explicitly means a selected window with no samples.
/// appVersion must be the application's version, never a machine/user identifier.
struct DiagnosticSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let capturedAt: Date
    let appVersion: String
    let units: [String: DiagnosticUnit]
    let cpuPercent: Double?
    let memoryUsedBytes: UInt64?
    let memoryTotalBytes: UInt64?
    let swapUsedBytes: UInt64?
    let memoryPressureEstimate: DiagnosticMemoryPressure?
    let networkDownloadBytesPerSecond: Double?
    let networkUploadBytesPerSecond: Double?
    let networkSessionBytesIn: UInt64?
    let networkSessionBytesOut: UInt64?
    let volumeTotalBytes: UInt64?
    let volumeAvailableBytes: UInt64?
    let batteryChargePercent: Double?
    let batteryHealthPercent: Double?
    let isCharging: Bool?
    let isPluggedIn: Bool?
    let lowPowerModeEnabled: Bool?
    /// Hardware-reported input, not a calibrated wall-power measurement.
    let systemPowerWatts: Double?
    /// Positive charging / negative discharging.
    let batteryPowerWatts: Double?
    let history: [DiagnosticHistoryRow]?

    init(
        capturedAt: Date, appVersion: String,
        cpuPercent: Double? = nil,
        memoryUsedBytes: UInt64? = nil, memoryTotalBytes: UInt64? = nil,
        swapUsedBytes: UInt64? = nil, memoryPressureEstimate: DiagnosticMemoryPressure? = nil,
        networkDownloadBytesPerSecond: Double? = nil, networkUploadBytesPerSecond: Double? = nil,
        networkSessionBytesIn: UInt64? = nil, networkSessionBytesOut: UInt64? = nil,
        volumeTotalBytes: UInt64? = nil, volumeAvailableBytes: UInt64? = nil,
        batteryChargePercent: Double? = nil, batteryHealthPercent: Double? = nil,
        isCharging: Bool? = nil, isPluggedIn: Bool? = nil, lowPowerModeEnabled: Bool? = nil,
        systemPowerWatts: Double? = nil, batteryPowerWatts: Double? = nil,
        history: [DiagnosticHistoryRow]? = nil
    ) {
        self.schemaVersion = 1
        self.capturedAt = capturedAt
        self.appVersion = appVersion
        self.units = Self.schemaUnits
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.memoryPressureEstimate = memoryPressureEstimate
        self.networkDownloadBytesPerSecond = networkDownloadBytesPerSecond
        self.networkUploadBytesPerSecond = networkUploadBytesPerSecond
        self.networkSessionBytesIn = networkSessionBytesIn
        self.networkSessionBytesOut = networkSessionBytesOut
        self.volumeTotalBytes = volumeTotalBytes
        self.volumeAvailableBytes = volumeAvailableBytes
        self.batteryChargePercent = batteryChargePercent
        self.batteryHealthPercent = batteryHealthPercent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.systemPowerWatts = systemPowerWatts
        self.batteryPowerWatts = batteryPowerWatts
        self.history = history
    }

    static var schemaUnits: [String: DiagnosticUnit] {
        var units = Dictionary(uniqueKeysWithValues: DiagnosticMetric.allCases.map { ($0.rawValue, $0.unit) })
        units["memoryPressureEstimate"] = .text
        for field in ["isCharging", "isPluggedIn", "lowPowerModeEnabled"] { units[field] = .boolean }
        return units
    }
}

enum DiagnosticsFormat: String, CaseIterable, Sendable {
    case json, csv

    var fileExtension: String { rawValue }
    var contentType: UTType { self == .json ? .json : .commaSeparatedText }
    var defaultFilename: String { "SystemPulse-diagnostics.\(fileExtension)" }
}

enum DiagnosticExportError: LocalizedError {
    case invalidSchema
    case invalidTimestamp
    case nonfiniteValue(String)
    case invalidHistoryUnit
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .invalidSchema: return "The diagnostics schema or units are unsupported."
        case .invalidTimestamp: return "A diagnostics timestamp is invalid."
        case .nonfiniteValue(let metric): return "The \(metric) measurement is not finite."
        case .invalidHistoryUnit: return "A history measurement has the wrong unit."
        case .invalidDestination: return "No valid local export destination was selected."
        }
    }
}

enum DiagnosticsExport {
    /// Pure, deterministic UTF-8 encoding. JSON uses sorted keys and ISO8601 UTC
    /// milliseconds. CSV uses RFC4180 CRLF records, a final CRLF, and columns
    /// timestamp,metric,unit,value,recordType. First come schemaVersion/count and appVersion/text,
    /// then snapshot fields in schema order (unavailable values blank), then history
    /// rows using their actual timestamps. History uses the same metric names/units.
    /// No pretty/localized byte, percent, or rate formatting; integers remain exact.
    static func encode(snapshot: DiagnosticSnapshot, format: DiagnosticsFormat) throws -> Data {
        guard snapshot.schemaVersion == 1, snapshot.units == DiagnosticSnapshot.schemaUnits else {
            throw DiagnosticExportError.invalidSchema
        }
        let timestamp = try utcTimestamp(snapshot.capturedAt)
        let measurements = try snapshotMeasurements(snapshot)
        for row in snapshot.history ?? [] {
            _ = try utcTimestamp(row.timestamp)
            guard row.unit == row.metric.unit else { throw DiagnosticExportError.invalidHistoryUnit }
            guard row.value.isFinite else { throw DiagnosticExportError.nonfiniteValue(row.metric.rawValue) }
        }
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(utcTimestamp(date))
            }
            return try encoder.encode(snapshot)
        case .csv:
            var rows = [["timestamp", "metric", "unit", "value", "recordType"]]
            rows.append([timestamp, "schemaVersion", "count", String(snapshot.schemaVersion), "metadata"])
            rows.append([timestamp, "appVersion", "text", snapshot.appVersion, "metadata"])
            for (metric, value) in measurements {
                guard let unit = snapshot.units[metric] else { throw DiagnosticExportError.invalidSchema }
                rows.append([timestamp, metric, unit.rawValue, value, "snapshot"])
            }
            for row in snapshot.history ?? [] {
                rows.append([
                    try utcTimestamp(row.timestamp), row.metric.rawValue, row.unit.rawValue, String(row.value),
                    "history",
                ])
            }
            let csv = rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
            return Data(csv.utf8)
        }
    }

    /// nil destination is cancellation: no encoding, file access, or writer call.
    /// A non-nil URL must come ONLY from confirmed user selection. Atomic writing
    /// avoids a partially replaced file. Errors propagate; callers must report failure.
    @discardableResult
    static func save(
        snapshot: DiagnosticSnapshot, format: DiagnosticsFormat, destination: URL?,
        writer: (Data, URL) throws -> Void = { data, url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try data.write(to: url, options: .atomic)
        }
    ) throws -> Bool {
        guard let destination else { return false }
        guard destination.isFileURL else { throw DiagnosticExportError.invalidDestination }
        let data = try encode(snapshot: snapshot, format: format)
        try writer(data, destination)
        return true
    }

    private static func utcTimestamp(_ date: Date) throws -> String {
        // Restrict to four-digit ISO8601 years before invoking Foundation's formatter.
        guard date.timeIntervalSince1970.isFinite,
            date.timeIntervalSince1970 >= -62_135_596_800,
            date.timeIntervalSince1970 < 253_402_300_800
        else { throw DiagnosticExportError.invalidTimestamp }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func csvField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\r") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func snapshotMeasurements(_ snapshot: DiagnosticSnapshot) throws -> [(String, String)] {
        func number(_ value: Double?, _ metric: DiagnosticMetric) throws -> String {
            guard let value else { return "" }
            guard value.isFinite else { throw DiagnosticExportError.nonfiniteValue(metric.rawValue) }
            return String(value)  // Swift's numeric representation is locale-independent.
        }
        func bytes(_ value: UInt64?) -> String { value.map { String($0) } ?? "" }
        func boolean(_ value: Bool?) -> String { value.map { $0 ? "true" : "false" } ?? "" }
        return try [
            ("cpuPercent", number(snapshot.cpuPercent, .cpuPercent)),
            ("memoryUsedBytes", bytes(snapshot.memoryUsedBytes)),
            ("memoryTotalBytes", bytes(snapshot.memoryTotalBytes)),
            ("swapUsedBytes", bytes(snapshot.swapUsedBytes)),
            ("memoryPressureEstimate", snapshot.memoryPressureEstimate?.rawValue ?? ""),
            (
                "networkDownloadBytesPerSecond",
                number(snapshot.networkDownloadBytesPerSecond, .networkDownloadBytesPerSecond)
            ),
            ("networkUploadBytesPerSecond", number(snapshot.networkUploadBytesPerSecond, .networkUploadBytesPerSecond)),
            ("networkSessionBytesIn", bytes(snapshot.networkSessionBytesIn)),
            ("networkSessionBytesOut", bytes(snapshot.networkSessionBytesOut)),
            ("volumeTotalBytes", bytes(snapshot.volumeTotalBytes)),
            ("volumeAvailableBytes", bytes(snapshot.volumeAvailableBytes)),
            ("batteryChargePercent", number(snapshot.batteryChargePercent, .batteryChargePercent)),
            ("batteryHealthPercent", number(snapshot.batteryHealthPercent, .batteryHealthPercent)),
            ("isCharging", boolean(snapshot.isCharging)),
            ("isPluggedIn", boolean(snapshot.isPluggedIn)),
            ("lowPowerModeEnabled", boolean(snapshot.lowPowerModeEnabled)),
            ("systemPowerWatts", number(snapshot.systemPowerWatts, .systemPowerWatts)),
            ("batteryPowerWatts", number(snapshot.batteryPowerWatts, .batteryPowerWatts)),
        ]
    }
}
