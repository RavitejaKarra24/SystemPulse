import AppKit
import SwiftUI
import XCTest

@testable import SystemPulse

final class PanelKeyboardPolicyTests: XCTestCase {
    func testDestructiveConfirmationReturnIsExplicitlyCancelNotApproval() {
        XCTAssertEqual(DestructiveConfirmationKeyboard.cancelShortcut.key, .return)
        XCTAssertTrue(DestructiveConfirmationKeyboard.cancelShortcut.modifiers.isEmpty)
        XCTAssertNil(DestructiveConfirmationKeyboard.destructiveShortcut)
    }

    func testAllBareTopicDigitsRouteToVisibleTopics() {
        for topic in MetricTab.allCases {
            XCTAssertEqual(
                PanelKeyboardPolicy.topic(
                    characters: topic.keyEquivalent, modifiers: [],
                    isEditingText: false, hasDetail: false, topics: MetricTab.allCases), topic)
        }
    }

    func testEditingAndTextSelectionNeverBecomeTopicCommands() {
        for topic in MetricTab.allCases {
            XCTAssertNil(
                PanelKeyboardPolicy.topic(
                    characters: topic.keyEquivalent, modifiers: [],
                    isEditingText: true, hasDetail: false, topics: MetricTab.allCases))
        }
        XCTAssertFalse(PanelKeyboardPolicy.allowsBareShortcut(modifiers: [], isEditingText: true))
    }

    func testModifiedAndVoiceOverChordsAreNotConsumed() {
        let modifiers: [EventModifiers] = [
            .command, .control, .option, .shift, EventModifiers(rawValue: 1 << 30), [.control, .option],
            [.command, .shift],
        ]
        for flags in modifiers {
            XCTAssertFalse(PanelKeyboardPolicy.allowsBareShortcut(modifiers: flags, isEditingText: false))
            XCTAssertNil(
                PanelKeyboardPolicy.topic(
                    characters: "1", modifiers: flags, isEditingText: false,
                    hasDetail: false, topics: MetricTab.allCases))
        }
    }

    func testCapsLockAndNumericPadAreNotCommandChords() {
        for flags: EventModifiers in [.capsLock, .numericPad, [.capsLock, .numericPad]] {
            XCTAssertTrue(PanelKeyboardPolicy.allowsBareShortcut(modifiers: flags, isEditingText: false))
        }
    }

    func testVoiceOverCapsLockChordsRemainWithAssistiveTechnology() {
        for flags: EventModifiers in [.capsLock, [.capsLock, .numericPad]] {
            XCTAssertTrue(PanelKeyboardPolicy.allowsBareShortcut(modifiers: flags, isEditingText: false))
            XCTAssertFalse(
                PanelKeyboardPolicy.allowsBareShortcut(modifiers: flags, isEditingText: false, voiceOverEnabled: true))
            XCTAssertNil(
                PanelKeyboardPolicy.topic(
                    characters: "1", modifiers: flags, isEditingText: false,
                    hasDetail: false, topics: MetricTab.allCases, voiceOverEnabled: true))
        }
        for topic in MetricTab.allCases {
            XCTAssertFalse(
                PanelKeyboardPolicy.allowsProcessSearch(
                    modifiers: [.command, .capsLock], hasDetail: false,
                    topic: topic, voiceOverEnabled: true))
            XCTAssertEqual(
                PanelKeyboardPolicy.allowsProcessSearch(
                    modifiers: .command, hasDetail: false,
                    topic: topic, voiceOverEnabled: true), topic == .cpu || topic == .memory)
        }
    }

    func testNamedKeysAllowIncidentalQualifiersButNeverEditingOrCommandChords() {
        let qualifier = EventModifiers(rawValue: 1 << 30)
        for flags: EventModifiers in [[], .numericPad, qualifier, [.numericPad, qualifier]] {
            XCTAssertTrue(PanelKeyboardPolicy.allowsNamedKey(modifiers: flags, isEditingText: false))
            XCTAssertFalse(PanelKeyboardPolicy.allowsNamedKey(modifiers: flags, isEditingText: true))
            for command: EventModifiers in [.command, .control, .option, .shift, [.control, .option]] {
                XCTAssertFalse(
                    PanelKeyboardPolicy.allowsNamedKey(modifiers: flags.union(command), isEditingText: false))
            }
        }
        XCTAssertTrue(PanelKeyboardPolicy.allowsNamedKey(modifiers: .capsLock, isEditingText: false))
        XCTAssertFalse(
            PanelKeyboardPolicy.allowsNamedKey(modifiers: .capsLock, isEditingText: false, voiceOverEnabled: true))
    }

    func testHiddenTopicsAndDetailRoutesDoNotChangePanels() {
        XCTAssertNil(
            PanelKeyboardPolicy.topic(
                characters: "1", modifiers: [], isEditingText: false,
                hasDetail: false, topics: [.overview, .power]))
        XCTAssertNil(
            PanelKeyboardPolicy.topic(
                characters: "1", modifiers: [], isEditingText: false,
                hasDetail: true, topics: MetricTab.allCases))
        XCTAssertNil(
            PanelKeyboardPolicy.topic(
                characters: "12", modifiers: [], isEditingText: false,
                hasDetail: false, topics: MetricTab.allCases))
        XCTAssertNil(
            PanelKeyboardPolicy.topic(
                characters: "x", modifiers: [], isEditingText: false,
                hasDetail: false, topics: MetricTab.allCases))
    }

    func testFindIsCommandOnlyAndLimitedToTopLevelProcessTopics() {
        for topic in MetricTab.allCases {
            for flags: EventModifiers in [.command, [.command, .capsLock]] {
                XCTAssertEqual(
                    PanelKeyboardPolicy.allowsProcessSearch(modifiers: flags, hasDetail: false, topic: topic),
                    topic == .cpu || topic == .memory)
                XCTAssertFalse(PanelKeyboardPolicy.allowsProcessSearch(modifiers: flags, hasDetail: true, topic: topic))
            }
            for flags: EventModifiers in [
                [], [.command, .shift], [.command, .option], [.command, .control], [.control, .option],
                [.command, EventModifiers(rawValue: 1 << 30)],
            ] {
                XCTAssertFalse(
                    PanelKeyboardPolicy.allowsProcessSearch(modifiers: flags, hasDetail: false, topic: topic))
            }
        }
    }

    @MainActor
    func testResponderClassificationIsLocalAndDoesNotNeedAKeyWindowOrPermission() {
        let editor = NSTextView()
        editor.isEditable = true
        XCTAssertTrue(PanelKeyboardPolicy.isTextResponder(editor))
        editor.isEditable = false
        editor.isSelectable = true
        XCTAssertTrue(PanelKeyboardPolicy.isTextResponder(editor))
        editor.isSelectable = false
        XCTAssertFalse(PanelKeyboardPolicy.isTextResponder(editor))
        let field = NSTextField()
        field.isEditable = true
        XCTAssertTrue(PanelKeyboardPolicy.isTextResponder(field))
        field.isEditable = false
        field.isSelectable = false
        XCTAssertFalse(PanelKeyboardPolicy.isTextResponder(field))
        XCTAssertFalse(PanelKeyboardPolicy.isTextResponder(NSButton(title: "Fixture", target: nil, action: nil)))
        XCTAssertFalse(PanelKeyboardPolicy.isTextResponder(nil))
    }
}
