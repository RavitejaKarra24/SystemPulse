import Foundation
import XCTest

@testable import SystemPulse

final class HardwareTelemetryNoteTests: XCTestCase {
    func testScopeNotesHaveStableUniqueIDsAndDescribeCollectionNotLiveAvailability() {
        let notes = HardwareTelemetryNote.allCases
        XCTAssertEqual(notes.count, 6)
        XCTAssertEqual(Set(notes.map(\.id)).count, notes.count)
        XCTAssertEqual(HardwareTelemetryNote.thermalState.scopeLabel, "Public macOS APIs")
        XCTAssertEqual(HardwareTelemetryNote.batteryDetails.scopeLabel, "Hardware-dependent")
        for note in [HardwareTelemetryNote.graphics, .additionalSensors, .accessoryBatteries] {
            XCTAssertEqual(note.scopeLabel, "Not collected")
        }
        for note in notes {
            XCTAssertFalse(note.title.isEmpty)
            XCTAssertFalse(note.explanation.isEmpty)
        }
    }

    func testBatteryAndThermalCaveatsNeverClaimChipTemperatureOrCalibratedEnergy() {
        let battery = HardwareTelemetryNote.batteryDetails.explanation
        XCTAssertTrue(battery.contains("hardware-specific registry"))
        XCTAssertTrue(battery.contains("not CPU/GPU temperature"))
        XCTAssertTrue(battery.contains("not calibrated wall power or energy"))
        XCTAssertTrue(HardwareTelemetryNote.thermalState.explanation.contains("not degrees Celsius"))
        XCTAssertTrue(
            HardwareTelemetryNote.additionalSensors.explanation.contains("No temperature or fan reading is inferred"))
    }

    func testUncollectedScopeDoesNotPromiseGeneralBluetoothOrWholeMachineMetalCounters() {
        XCTAssertTrue(HardwareTelemetryNote.graphics.explanation.contains("do not establish whole-machine"))
        XCTAssertTrue(HardwareTelemetryNote.accessoryBatteries.explanation.contains("No Bluetooth scanning"))
        XCTAssertTrue(HardwareTelemetryNote.accessoryBatteries.explanation.contains("no Input Monitoring request"))
        XCTAssertTrue(
            HardwareTelemetryNote.accessoryBatteries.explanation.contains(
                "no accessory charge or connection state is inferred"))
    }

    func testDisclosureAddsNoBluetoothLocationOrInputMonitoringPrivacyKeys() throws {
        // Inspect source metadata only, never query authorization or create a
        // Bluetooth/HID manager. These keys need deliberate opt-in design if
        // a future permission-gated feature is implemented.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let unexpectedKeys = plist.keys.filter {
            $0.hasPrefix("NSBluetooth") || $0.hasPrefix("NSLocation") || $0.hasPrefix("NSInputMonitoring")
        }
        XCTAssertTrue(unexpectedKeys.isEmpty)
    }
}
