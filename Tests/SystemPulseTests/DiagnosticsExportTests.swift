import Foundation
import UniformTypeIdentifiers
import XCTest

@testable import SystemPulse

final class DiagnosticsExportTests: XCTestCase {
    private let capturedAt = Date(timeIntervalSince1970: 100.125)
    private let timestamp = "1970-01-01T00:01:40.125Z"

    private func fixture(history: [DiagnosticHistoryRow]? = nil) -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            capturedAt: capturedAt, appVersion: "1.3.0",
            cpuPercent: 12.5, memoryUsedBytes: 8_000_000_001, memoryTotalBytes: 16_000_000_000,
            swapUsedBytes: 500, memoryPressureEstimate: .warning,
            networkDownloadBytesPerSecond: 1234.5, networkUploadBytesPerSecond: 678.25,
            networkSessionBytesIn: 12345, networkSessionBytesOut: 67890,
            volumeTotalBytes: 1_000_000_000_000, volumeAvailableBytes: 250_000_000_000,
            batteryChargePercent: 80.5, batteryHealthPercent: 94.25,
            isCharging: false, isPluggedIn: true, lowPowerModeEnabled: false,
            systemPowerWatts: 30.5, batteryPowerWatts: -5.25, history: history)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ data: Data) throws -> DiagnosticSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid UTC timestamp")
            }
            return date
        }
        return try decoder.decode(DiagnosticSnapshot.self, from: data)
    }

    func testJSONDecodesRawMeasurementsAndFractionalUTCTimestamps() throws {
        let data = try DiagnosticsExport.encode(snapshot: fixture(), format: .json)
        let json = try object(data)
        let snapshot = try decode(data)
        XCTAssertEqual(json["capturedAt"] as? String, timestamp)
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.appVersion, "1.3.0")
        XCTAssertEqual(snapshot.capturedAt.timeIntervalSince1970, capturedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(snapshot.cpuPercent, 12.5)
        XCTAssertEqual(snapshot.memoryUsedBytes, 8_000_000_001)
        XCTAssertEqual(snapshot.memoryTotalBytes, 16_000_000_000)
        XCTAssertEqual(snapshot.swapUsedBytes, 500)
        XCTAssertEqual(snapshot.memoryPressureEstimate, .warning)
        XCTAssertEqual(snapshot.networkDownloadBytesPerSecond, 1234.5)
        XCTAssertEqual(snapshot.networkUploadBytesPerSecond, 678.25)
        XCTAssertEqual(snapshot.networkSessionBytesIn, 12345)
        XCTAssertEqual(snapshot.networkSessionBytesOut, 67890)
        XCTAssertEqual(snapshot.volumeTotalBytes, 1_000_000_000_000)
        XCTAssertEqual(snapshot.volumeAvailableBytes, 250_000_000_000)
        XCTAssertEqual(snapshot.batteryChargePercent, 80.5)
        XCTAssertEqual(snapshot.batteryHealthPercent, 94.25)
        XCTAssertEqual(snapshot.isCharging, false)
        XCTAssertEqual(snapshot.isPluggedIn, true)
        XCTAssertEqual(snapshot.lowPowerModeEnabled, false)
        XCTAssertEqual(snapshot.systemPowerWatts, 30.5)
        XCTAssertEqual(snapshot.batteryPowerWatts, -5.25)
    }

    func testJSONExplicitUnitAllowlistAndEstimatedPressureWording() throws {
        let json = try object(DiagnosticsExport.encode(snapshot: fixture(), format: .json))
        let units = try XCTUnwrap(json["units"] as? [String: String])
        for metric in DiagnosticMetric.allCases { XCTAssertEqual(units[metric.rawValue], metric.unit.rawValue) }
        XCTAssertEqual(units["cpuPercent"], "percent")
        XCTAssertEqual(units["memoryUsedBytes"], "bytes")
        XCTAssertEqual(units["networkUploadBytesPerSecond"], "bytesPerSecond")
        XCTAssertEqual(units["batteryPowerWatts"], "watts")
        XCTAssertEqual(units["lowPowerModeEnabled"], "boolean")
        XCTAssertEqual(units["memoryPressureEstimate"], "text")
        XCTAssertEqual(json["memoryPressureEstimate"] as? String, "Estimated: Elevated")
        XCTAssertEqual(DiagnosticMemoryPressure.normal.rawValue, "Estimated: Normal")
        XCTAssertEqual(DiagnosticMemoryPressure.critical.rawValue, "Estimated: Critical")
    }

    func testSchemaOnlyContainsPrivacySafeAllowlistedFields() throws {
        let json = try object(DiagnosticsExport.encode(snapshot: fixture(), format: .json))
        let expected = Set(DiagnosticMetric.allCases.map(\.rawValue)).union([
            "schemaVersion", "capturedAt", "appVersion", "units", "memoryPressureEstimate",
            "isCharging", "isPluggedIn", "lowPowerModeEnabled",
        ])
        XCTAssertEqual(Set(json.keys), expected)
        let csv = String(decoding: try DiagnosticsExport.encode(snapshot: fixture(), format: .csv), as: UTF8.self)
        for forbidden in [
            "processName", "executablePath", "username", "hostname", "SSID", "localIP", "publicIP", "mountPath",
            "/Users/", "/Volumes/",
        ] {
            XCTAssertNil(json[forbidden])
            XCTAssertFalse(csv.contains(forbidden))
        }
    }

    func testUnavailableJSONFieldsAreOmittedRatherThanInventedZeroes() throws {
        let snapshot = DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1.3.0")
        let json = try object(DiagnosticsExport.encode(snapshot: snapshot, format: .json))
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "capturedAt", "appVersion", "units"])
        let decoded = try decode(DiagnosticsExport.encode(snapshot: snapshot, format: .json))
        XCTAssertNil(decoded.cpuPercent)
        XCTAssertNil(decoded.swapUsedBytes)
        XCTAssertNil(decoded.volumeTotalBytes)
        XCTAssertNil(decoded.batteryChargePercent)
        XCTAssertNil(decoded.lowPowerModeEnabled)
        XCTAssertNil(decoded.history)
    }

    func testZeroAndFalseAreAvailableValues() throws {
        let snapshot = DiagnosticSnapshot(
            capturedAt: capturedAt, appVersion: "1.3.0", cpuPercent: 0, swapUsedBytes: 0,
            isCharging: false, lowPowerModeEnabled: false)
        let decoded = try decode(DiagnosticsExport.encode(snapshot: snapshot, format: .json))
        XCTAssertEqual(decoded.cpuPercent, 0)
        XCTAssertEqual(decoded.swapUsedBytes, 0)
        XCTAssertEqual(decoded.isCharging, false)
        let csv = String(decoding: try DiagnosticsExport.encode(snapshot: snapshot, format: .csv), as: UTF8.self)
        XCTAssertTrue(csv.contains("\(timestamp),swapUsedBytes,bytes,0,snapshot\r\n"))
        XCTAssertTrue(csv.contains("\(timestamp),lowPowerModeEnabled,boolean,false,snapshot\r\n"))
    }

    func testByteCountersRemainExactAtUInt64Maximum() throws {
        let snapshot = DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1.3.0", networkSessionBytesIn: .max)
        let json = try DiagnosticsExport.encode(snapshot: snapshot, format: .json)
        XCTAssertEqual(try decode(json).networkSessionBytesIn, UInt64.max)
        XCTAssertTrue(String(decoding: json, as: UTF8.self).contains("18446744073709551615"))
        let csv = try DiagnosticsExport.encode(snapshot: snapshot, format: .csv)
        XCTAssertTrue(String(decoding: csv, as: UTF8.self).contains("networkSessionBytesIn,bytes,18446744073709551615"))
    }

    func testEncodingsAreDeterministicAndJSONKeysSorted() throws {
        for format in DiagnosticsFormat.allCases {
            XCTAssertEqual(
                try DiagnosticsExport.encode(snapshot: fixture(), format: format),
                try DiagnosticsExport.encode(snapshot: fixture(), format: format))
        }
        let json = String(decoding: try DiagnosticsExport.encode(snapshot: fixture(), format: .json), as: UTF8.self)
        XCTAssertTrue(json.hasPrefix("{\"appVersion\":\"1.3.0\",\"batteryChargePercent\":80.5,"))
        let units = try XCTUnwrap(json.range(of: "\"units\":{"))
        XCTAssertTrue(
            json[units.upperBound...].hasPrefix(
                "\"batteryChargePercent\":\"percent\",\"batteryHealthPercent\":\"percent\","))
    }

    func testCSVHeaderMetadataFieldOrderAndRawUnits() throws {
        let csv = String(decoding: try DiagnosticsExport.encode(snapshot: fixture(), format: .csv), as: UTF8.self)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "timestamp,metric,unit,value,recordType")
        XCTAssertEqual(lines[1], "\(timestamp),schemaVersion,count,1,metadata")
        XCTAssertEqual(lines[2], "\(timestamp),appVersion,text,1.3.0,metadata")
        XCTAssertEqual(lines[3], "\(timestamp),cpuPercent,percent,12.5,snapshot")
        XCTAssertEqual(lines[4], "\(timestamp),memoryUsedBytes,bytes,8000000001,snapshot")
        XCTAssertTrue(lines.contains("\(timestamp),memoryPressureEstimate,text,Estimated: Elevated,snapshot"))
        XCTAssertTrue(lines.contains("\(timestamp),networkDownloadBytesPerSecond,bytesPerSecond,1234.5,snapshot"))
        XCTAssertTrue(lines.contains("\(timestamp),batteryPowerWatts,watts,-5.25,snapshot"))
        XCTAssertEqual(lines.last, "")
        XCTAssertEqual(lines.count, 22)  // header, two metadata, 18 measurements, final CRLF
    }

    func testCSVUnavailableValuesHaveBlankCells() throws {
        let snapshot = DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1.3.0")
        let csv = String(decoding: try DiagnosticsExport.encode(snapshot: snapshot, format: .csv), as: UTF8.self)
        XCTAssertTrue(csv.contains("\(timestamp),swapUsedBytes,bytes,,snapshot\r\n"))
        XCTAssertTrue(csv.contains("\(timestamp),volumeAvailableBytes,bytes,,snapshot\r\n"))
        XCTAssertTrue(csv.contains("\(timestamp),batteryChargePercent,percent,,snapshot\r\n"))
        XCTAssertTrue(csv.contains("\(timestamp),lowPowerModeEnabled,boolean,,snapshot\r\n"))
    }

    func testCSVRFC4180EscapingOfCommasQuotesCRAndLF() throws {
        for version in ["1,2", "1\"2", "1\r2", "1\n2", "1,\"2\"\r\n3", "β 1.0"] {
            let snapshot = DiagnosticSnapshot(capturedAt: capturedAt, appVersion: version)
            let csv = String(decoding: try DiagnosticsExport.encode(snapshot: snapshot, format: .csv), as: UTF8.self)
            let expected =
                version == "β 1.0" ? version : "\"" + version.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            XCTAssertTrue(csv.contains("\(timestamp),appVersion,text,\(expected),metadata\r\n"), version)
            XCTAssertEqual(try decode(DiagnosticsExport.encode(snapshot: snapshot, format: .json)).appVersion, version)
        }
    }

    func testHistoryPreservesActualTimestampsOrderAndMetricUnits() throws {
        let history = [
            DiagnosticHistoryRow(
                timestamp: capturedAt.addingTimeInterval(-2), metric: .networkUploadBytesPerSecond, value: 42.25),
            DiagnosticHistoryRow(timestamp: capturedAt.addingTimeInterval(-1), metric: .cpuPercent, value: 7.5),
        ]
        let snapshot = fixture(history: history)
        let data = try DiagnosticsExport.encode(snapshot: snapshot, format: .json)
        XCTAssertEqual(try decode(data).history, history)
        let json = try object(data)
        let rows = try XCTUnwrap(json["history"] as? [[String: Any]])
        XCTAssertEqual(Set(rows[0].keys), ["timestamp", "metric", "unit", "value"])
        XCTAssertEqual(rows[0]["timestamp"] as? String, "1970-01-01T00:01:38.125Z")
        XCTAssertEqual(rows[0]["unit"] as? String, "bytesPerSecond")
        let csv = String(decoding: try DiagnosticsExport.encode(snapshot: snapshot, format: .csv), as: UTF8.self)
        XCTAssertTrue(
            csv.hasSuffix(
                "1970-01-01T00:01:38.125Z,networkUploadBytesPerSecond,bytesPerSecond,42.25,history\r\n"
                    + "1970-01-01T00:01:39.125Z,cpuPercent,percent,7.5,history\r\n"))
    }

    func testEmptyHistoryIsExplicitAndDoesNotInventSamples() throws {
        let json = try object(DiagnosticsExport.encode(snapshot: fixture(history: []), format: .json))
        XCTAssertEqual((json["history"] as? [Any])?.count, 0)
        XCTAssertEqual(
            try DiagnosticsExport.encode(snapshot: fixture(history: []), format: .csv),
            try DiagnosticsExport.encode(snapshot: fixture(), format: .csv))
    }

    func testAllNonfiniteSnapshotMeasurementsAreRejectedInBothFormats() {
        for value in [Double.nan, .infinity, -.infinity] {
            let snapshots = [
                DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1", cpuPercent: value),
                DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1", networkDownloadBytesPerSecond: value),
                DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1", networkUploadBytesPerSecond: value),
                DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1", batteryChargePercent: value),
                DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1", batteryHealthPercent: value),
                DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1", systemPowerWatts: value),
                DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1", batteryPowerWatts: value),
            ]
            for snapshot in snapshots {
                for format in DiagnosticsFormat.allCases {
                    XCTAssertThrowsError(try DiagnosticsExport.encode(snapshot: snapshot, format: format)) { error in
                        guard case DiagnosticExportError.nonfiniteValue = error else {
                            return XCTFail("Unexpected error: \(error)")
                        }
                    }
                }
            }
        }
    }

    func testNonfiniteHistoryMeasurementsAreRejected() {
        for value in [Double.nan, .infinity, -.infinity] {
            let row = DiagnosticHistoryRow(timestamp: capturedAt, metric: .cpuPercent, value: value)
            for format in DiagnosticsFormat.allCases {
                XCTAssertThrowsError(try DiagnosticsExport.encode(snapshot: fixture(history: [row]), format: format))
            }
        }
    }

    func testInvalidSnapshotAndHistoryTimestampsAreRejected() {
        for date in [Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: -62_135_596_801)] {
            let snapshot = DiagnosticSnapshot(capturedAt: date, appVersion: "1.3.0")
            let row = DiagnosticHistoryRow(timestamp: date, metric: .cpuPercent, value: 1)
            for format in DiagnosticsFormat.allCases {
                XCTAssertThrowsError(try DiagnosticsExport.encode(snapshot: snapshot, format: format))
                XCTAssertThrowsError(try DiagnosticsExport.encode(snapshot: fixture(history: [row]), format: format))
            }
        }
    }

    func testDecodedUnsupportedSchemaAndAlteredUnitsCannotBeExported() throws {
        let json = try object(DiagnosticsExport.encode(snapshot: fixture(), format: .json))
        for replacement in [["schemaVersion": 2], ["units": ["cpuPercent": "bytes"]]] as [[String: Any]] {
            let altered = json.merging(replacement) { _, new in new }
            let snapshot = try decode(JSONSerialization.data(withJSONObject: altered))
            for format in DiagnosticsFormat.allCases {
                XCTAssertThrowsError(try DiagnosticsExport.encode(snapshot: snapshot, format: format))
            }
        }
    }

    func testDecodedHistoryWithWrongUnitsCannotBeExported() throws {
        let row = DiagnosticHistoryRow(timestamp: capturedAt, metric: .cpuPercent, value: 1)
        var json = try object(DiagnosticsExport.encode(snapshot: fixture(history: [row]), format: .json))
        var rows = try XCTUnwrap(json["history"] as? [[String: Any]])
        rows[0]["unit"] = "bytes"
        json["history"] = rows
        let snapshot = try decode(JSONSerialization.data(withJSONObject: json))
        for format in DiagnosticsFormat.allCases {
            XCTAssertThrowsError(try DiagnosticsExport.encode(snapshot: snapshot, format: format))
        }
    }

    func testCancelDoesNotEncodeOrInvokeWriterEvenWithInvalidMeasurements() throws {
        let invalid = DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1", cpuPercent: .nan)
        var writes = 0
        for format in DiagnosticsFormat.allCases {
            XCTAssertFalse(
                try DiagnosticsExport.save(snapshot: invalid, format: format, destination: nil) { _, _ in writes += 1 })
        }
        XCTAssertEqual(writes, 0)
    }

    func testConfirmedDestinationWritesExactEncodingOnce() throws {
        let destination = URL(fileURLWithPath: "/tmp/SystemPulse-diagnostics.json")
        var writes = 0
        XCTAssertTrue(
            try DiagnosticsExport.save(snapshot: fixture(), format: .json, destination: destination) { data, url in
                writes += 1
                XCTAssertEqual(url, destination)
                XCTAssertEqual(data, try DiagnosticsExport.encode(snapshot: fixture(), format: .json))
            })
        XCTAssertEqual(writes, 1)
    }

    func testWriteErrorsPropagateWithoutFalseSuccess() {
        enum WriteFailure: Error { case denied }
        var writes = 0
        XCTAssertThrowsError(
            try DiagnosticsExport.save(
                snapshot: fixture(), format: .csv, destination: URL(fileURLWithPath: "/tmp/export.csv")
            ) { _, _ in
                writes += 1
                throw WriteFailure.denied
            }
        ) { error in
            guard case WriteFailure.denied = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(writes, 1)
    }

    func testInvalidDataAndNonFileDestinationNeverInvokeWriter() throws {
        let nonFile = try XCTUnwrap(URL(string: "diagnostics:destination"))
        let invalid = DiagnosticSnapshot(capturedAt: capturedAt, appVersion: "1", cpuPercent: .nan)
        var writes = 0
        XCTAssertThrowsError(
            try DiagnosticsExport.save(snapshot: fixture(), format: .json, destination: nonFile) { _, _ in writes += 1 }
        )
        XCTAssertThrowsError(
            try DiagnosticsExport.save(
                snapshot: invalid, format: .csv, destination: URL(fileURLWithPath: "/tmp/export.csv")
            ) { _, _ in
                writes += 1
            })
        XCTAssertEqual(writes, 0)
    }

    func testDefaultWriterSavesReplacesAndReportsFilesystemFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("export.json")
        XCTAssertTrue(try DiagnosticsExport.save(snapshot: fixture(), format: .json, destination: destination))
        XCTAssertEqual(
            try Data(contentsOf: destination), try DiagnosticsExport.encode(snapshot: fixture(), format: .json))
        XCTAssertTrue(try DiagnosticsExport.save(snapshot: fixture(), format: .csv, destination: destination))
        let bytes = try Data(contentsOf: destination)
        XCTAssertEqual(bytes, try DiagnosticsExport.encode(snapshot: fixture(), format: .csv))
        let missingParent = directory.appendingPathComponent("missing/export.csv")
        XCTAssertThrowsError(try DiagnosticsExport.save(snapshot: fixture(), format: .csv, destination: missingParent))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingParent.path))
        XCTAssertFalse(try DiagnosticsExport.save(snapshot: fixture(), format: .json, destination: nil))
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    func testFormatTypesAndDefaultFilenamesHaveNoPrivateNames() {
        XCTAssertEqual(DiagnosticsFormat.json.contentType, .json)
        XCTAssertEqual(DiagnosticsFormat.csv.contentType, .commaSeparatedText)
        XCTAssertEqual(DiagnosticsFormat.json.fileExtension, "json")
        XCTAssertEqual(DiagnosticsFormat.csv.fileExtension, "csv")
        XCTAssertEqual(DiagnosticsFormat.json.defaultFilename, "SystemPulse-diagnostics.json")
        XCTAssertEqual(DiagnosticsFormat.csv.defaultFilename, "SystemPulse-diagnostics.csv")
    }
}
