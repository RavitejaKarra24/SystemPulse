import Foundation
import XCTest

@testable import SystemPulse

final class AlertSettingsInputTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testIncompleteAndInvalidDraftsAreRejectedWithoutLosingText() {
        let input = SettingsAlertNumericInput.duration
        for text in ["", " ", "-", "+", ".", "1e", "1e-", "30junk", "30 40", "30%", "1,000"] {
            var draft = SettingsAlertNumericDraft()
            draft.text = text
            XCTAssertEqual(draft.commit(value: 60, input: input, locale: english), .rejected(.invalidNumber), text)
            XCTAssertEqual(draft.text, text, "Rejected input must remain available for correction")
            XCTAssertEqual(draft.error, .invalidNumber)
        }
    }

    func testFractionalSeparatorRequiresADigitBeforeCommitInEveryLocale() {
        for identifier in ["en_US", "de_DE", "fr_FR", "ar_EG"] {
            let locale = Locale(identifier: identifier)
            let separator = locale.decimalSeparator ?? "."
            let integer = SettingsAlertNumericInput.duration.text(for: 900, locale: locale)
            for input in [SettingsAlertNumericInput.duration, .cooldown, .threshold(.diskAvailable)] {
                var draft = SettingsAlertNumericDraft()
                draft.sync(value: 900, input: input, locale: locale, isEditing: false)
                for text in ["\(integer)\(separator)", " \(integer)\(separator) \n", "\(integer)\(separator)e2"] {
                    draft.text = text
                    XCTAssertEqual(
                        draft.commit(value: 900, input: input, locale: locale), .rejected(.invalidNumber),
                        "\(identifier): \(text)")
                    XCTAssertEqual(draft.text, text)
                    XCTAssertEqual(draft.error, .invalidNumber)
                }
                // Localized digits and complete decimal fractions remain valid.
                let storedValue = 900.5 * (input == .threshold(.diskAvailable) ? SettingsAlertUnits.bytesPerGB : 1)
                let complete = input.text(for: storedValue, locale: locale)
                XCTAssertEqual(input.validate(complete, locale: locale), .success(storedValue))
            }
        }
    }

    func testTypingDoesNotCommitAndACompleteDraftCanBeSubmitted() {
        var draft = SettingsAlertNumericDraft()
        let input = SettingsAlertNumericInput.threshold(.diskAvailable)
        draft.sync(value: 5_000_000_000, input: input, locale: english, isEditing: false)
        for text in ["", "5", "5.", "5.3", "5.37"] {
            draft.text = text
            draft.sync(value: 9_000_000_000, input: input, locale: english, isEditing: true)
            XCTAssertEqual(draft.text, text)
        }
        XCTAssertEqual(draft.commit(value: 5_000_000_000, input: input, locale: english), .changed(5_370_000_000))
        XCTAssertEqual(draft.text, "5.37")
        XCTAssertNil(draft.error)
    }

    func testNonfiniteNumbersAndOverflowAreRejectedEvenWhenUnchanged() {
        for input in [SettingsAlertNumericInput.duration, .cooldown, .threshold(.diskAvailable)] {
            for text in ["NaN", "nan", "inf", "-inf", "Infinity", "∞", "-∞", "1e999"] {
                XCTAssertEqual(input.commit(text, currentValue: .nan, locale: english), .rejected(.invalidNumber), text)
            }
            XCTAssertFalse(input.accepts(.nan))
            XCTAssertFalse(input.accepts(.infinity))
            XCTAssertFalse(input.accepts(-.infinity))
        }
        // The parsed GB value is finite, but converting it to bytes overflows.
        XCTAssertEqual(
            SettingsAlertNumericInput.threshold(.diskAvailable).validate("1e308", locale: english),
            .failure(.outOfRange))
    }

    func testDurationAndCooldownBoundsDoNotClamp() {
        let cases: [(SettingsAlertNumericInput, String, String, String, String)] = [
            (.duration, "30", "86400", "29.999", "86400.001"),
            (.cooldown, "900", "604800", "899.999", "604800.001"),
        ]
        for (input, minimum, maximum, below, above) in cases {
            XCTAssertEqual(input.validate(minimum, locale: english), .success(input.storedRange.lowerBound))
            XCTAssertEqual(input.validate(maximum, locale: english), .success(input.storedRange.upperBound))
            for text in [below, above, "-1", "0"] {
                XCTAssertEqual(
                    input.commit(text, currentValue: input.storedRange.lowerBound, locale: english),
                    .rejected(.outOfRange), text)
            }
            XCTAssertEqual(input.validate("900.5", locale: english), .success(900.5))
        }
    }

    func testEveryThresholdMatchesEngineSafetyBounds() {
        for kind in AlertKind.allCases {
            let input = SettingsAlertNumericInput.threshold(kind)
            for boundary in [input.storedRange.lowerBound, input.storedRange.upperBound] {
                let text = input.text(for: boundary, locale: english)
                XCTAssertEqual(input.validate(text, locale: english), .success(boundary), "\(kind): \(text)")
                var rule = AlertRule(kind: kind)
                rule.threshold = boundary
                XCTAssertEqual(rule.normalized(), rule)
            }
            for value in [input.storedRange.lowerBound - 1, input.storedRange.upperBound + 1] {
                XCTAssertFalse(input.accepts(value))
                XCTAssertEqual(
                    input.validate(input.text(for: value, locale: english), locale: english),
                    .failure(.outOfRange))
            }
        }
        XCTAssertEqual(
            SettingsAlertNumericInput.threshold(.cpuUsage).validate("0", locale: english), .failure(.outOfRange))
        XCTAssertEqual(
            SettingsAlertNumericInput.threshold(.thermal).validate("2.5", locale: english), .failure(.outOfRange))
    }

    func testDecimalGBConvertsToBytesNotGiB() {
        let input = SettingsAlertNumericInput.threshold(.diskAvailable)
        XCTAssertEqual(input.validate("12.5", locale: english), .success(12_500_000_000))
        XCTAssertEqual(input.validate("0.000000001", locale: english), .success(1))
        XCTAssertEqual(input.validate("0.0000000009", locale: english), .failure(.outOfRange))
        XCTAssertEqual(input.text(for: AlertRule(kind: .diskAvailable).threshold, locale: english), "5.36870912")
        XCTAssertEqual(input.validate("5.36870912", locale: english), .success(5_368_709_120))
    }

    func testLocaleAwareParsingFormattingAndWholeInputConsumption() {
        let input = SettingsAlertNumericInput.threshold(.diskAvailable)
        for identifier in ["de_DE", "fr_FR"] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(input.text(for: 12_500_000_000, locale: locale), "12,5")
            XCTAssertEqual(input.validate(" 12,5 \n", locale: locale), .success(12_500_000_000))
            XCTAssertEqual(input.validate("9,0e2", locale: locale), .success(900_000_000_000))
            for text in ["12.5", "12,5junk", "12,5,2", "1.000", "1\u{202F}000"] {
                XCTAssertEqual(input.validate(text, locale: locale), .failure(.invalidNumber), text)
            }
            let feedback = input.feedback(for: .outOfRange, locale: locale)
            XCTAssertTrue(feedback.contains("0,000000001"))
            XCTAssertTrue(feedback.contains("GB"))
        }
        XCTAssertEqual(input.validate("12,5", locale: english), .failure(.invalidNumber))
        XCTAssertEqual(SettingsAlertNumericInput.duration.validate("9e2", locale: english), .success(900))
    }

    func testCommaDecimalTimingRangesRejectWithoutClampingAndAllowCorrection() {
        for identifier in ["de_DE", "fr_FR"] {
            let locale = Locale(identifier: identifier)
            for input in [SettingsAlertNumericInput.duration, .cooldown] {
                var draft = SettingsAlertNumericDraft()
                let minimum = input.storedRange.lowerBound
                let maximum = input.storedRange.upperBound
                draft.sync(value: minimum, input: input, locale: locale, isEditing: false)
                for value in [minimum - 0.5, maximum + 0.5] {
                    let text = input.text(for: value, locale: locale)
                    draft.text = text
                    XCTAssertEqual(
                        draft.commit(value: minimum, input: input, locale: locale), .rejected(.outOfRange))
                    XCTAssertEqual(draft.text, text)
                    XCTAssertEqual(draft.error, .outOfRange)
                }
                draft.text = input.text(for: minimum + 0.5, locale: locale)
                XCTAssertEqual(
                    draft.commit(value: minimum, input: input, locale: locale), .changed(minimum + 0.5))
                XCTAssertNil(draft.error)
                draft.text = input.text(for: maximum, locale: locale)
                XCTAssertEqual(
                    draft.commit(value: minimum + 0.5, input: input, locale: locale), .changed(maximum))
            }
        }
    }

    func testFocusedDraftKeepsItsDecimalLocaleUntilCommitThenUsesLatestLocale() {
        let cases: [(SettingsAlertNumericInput, Double, Double)] = [
            (.threshold(.diskAvailable), 5_500_000_000, 12_500_000_000),
            (.duration, 60.5, 120.5), (.cooldown, 900.5, 1800.5),
        ]
        for (original, latest) in [("de_DE", "en_US"), ("en_US", "fr_FR")] {
            let originalLocale = Locale(identifier: original)
            let latestLocale = Locale(identifier: latest)
            for (input, value, editedValue) in cases {
                var draft = SettingsAlertNumericDraft()
                draft.sync(value: value, input: input, locale: originalLocale, isEditing: false)
                draft.text = input.text(for: editedValue, locale: originalLocale)
                let editedText = draft.text
                draft.sync(value: value, input: input, locale: latestLocale, isEditing: true)
                XCTAssertEqual(draft.text, editedText)
                XCTAssertEqual(
                    draft.commit(value: value, input: input, locale: latestLocale), .changed(editedValue))
                XCTAssertEqual(draft.text, input.text(for: editedValue, locale: latestLocale))
                XCTAssertNil(draft.error)
                // Return followed by focus loss must not request a second save.
                XCTAssertEqual(
                    draft.commit(value: editedValue, input: input, locale: latestLocale), .unchanged)
            }
        }
    }

    func testUntouchedLocaleChangedDraftKeepsPrecisionAndDoesNotOverwriteExternalValue() {
        let german = Locale(identifier: "de_DE")
        let input = SettingsAlertNumericInput.duration
        let value = 30.123456789123
        var draft = SettingsAlertNumericDraft()
        draft.sync(value: value, input: input, locale: german, isEditing: false)
        draft.sync(value: value, input: input, locale: english, isEditing: true)
        XCTAssertEqual(draft.commit(value: value, input: input, locale: english), .unchanged)
        XCTAssertEqual(draft.text, input.text(for: value, locale: english))
        draft.sync(value: value, input: input, locale: german, isEditing: false)
        draft.sync(value: 120.5, input: input, locale: english, isEditing: true)
        XCTAssertEqual(draft.commit(value: 120.5, input: input, locale: english), .unchanged)
        XCTAssertEqual(draft.text, "120.5")
        XCTAssertNil(draft.error)
    }

    func testLocaleChangeDuringRejectedEditingKeepsCorrectionAndCancelSemantics() {
        let german = Locale(identifier: "de_DE")
        let input = SettingsAlertNumericInput.cooldown
        var draft = SettingsAlertNumericDraft()
        draft.sync(value: 900.5, input: input, locale: german, isEditing: false)
        draft.text = "899,5"
        draft.sync(value: 1800.5, input: input, locale: english, isEditing: true)
        XCTAssertEqual(draft.commit(value: 1800.5, input: input, locale: english), .rejected(.outOfRange))
        XCTAssertEqual(draft.text, "899,5")
        draft.text = "900,"
        XCTAssertEqual(draft.commit(value: 1800.5, input: input, locale: english), .rejected(.invalidNumber))
        draft.text = "901,5"
        XCTAssertEqual(draft.commit(value: 1800.5, input: input, locale: english), .changed(901.5))
        XCTAssertEqual(draft.text, "901.5")
        XCTAssertNil(draft.error)
        draft.text = "-"
        XCTAssertEqual(draft.commit(value: 901.5, input: input, locale: english), .rejected(.invalidNumber))
        // Escape restores latest storage and adopts the current locale for the next edit.
        draft.sync(value: 1800.5, input: input, locale: english, isEditing: false)
        XCTAssertEqual(draft.text, "1800.5")
        XCTAssertNil(draft.error)
        draft.text = "1801.5"
        XCTAssertEqual(draft.commit(value: 1800.5, input: input, locale: english), .changed(1801.5))
    }

    func testValidExternalChangesSyncOnlyWhenNotEditingAndCancelRestoresLatestValue() {
        let input = SettingsAlertNumericInput.duration
        var draft = SettingsAlertNumericDraft()
        draft.sync(value: 60, input: input, locale: english, isEditing: false)
        XCTAssertEqual(draft.text, "60")
        draft.text = "-"
        draft.sync(value: 120, input: input, locale: english, isEditing: true)
        XCTAssertEqual(draft.text, "-")
        XCTAssertEqual(draft.commit(value: 120, input: input, locale: english), .rejected(.invalidNumber))
        draft.sync(value: .nan, input: input, locale: english, isEditing: false)
        XCTAssertEqual(draft.text, "-")
        XCTAssertNotNil(draft.error)
        // This is also the Escape action: restore current storage and clear feedback.
        draft.sync(value: 120, input: input, locale: english, isEditing: false)
        XCTAssertEqual(draft.text, "120")
        XCTAssertNil(draft.error)
        XCTAssertEqual(draft.commit(value: 120, input: input, locale: english), .unchanged)
        draft.sync(value: 240, input: input, locale: english, isEditing: false)
        XCTAssertEqual(draft.text, "240")
    }

    func testUntouchedFocusedFieldDoesNotOverwriteExternalChanges() {
        let input = SettingsAlertNumericInput.duration
        var draft = SettingsAlertNumericDraft()
        draft.sync(value: 60, input: input, locale: english, isEditing: false)
        draft.sync(value: 120, input: input, locale: english, isEditing: true)
        XCTAssertEqual(draft.text, "60")
        XCTAssertEqual(draft.commit(value: 120, input: input, locale: english), .unchanged)
        XCTAssertEqual(draft.text, "120")
        draft.text = "240"
        XCTAssertEqual(draft.commit(value: 180, input: input, locale: english), .changed(240))
    }

    func testUnchangedDoesNotRequestSaveOrRoundStoredPrecision() {
        let cases: [(SettingsAlertNumericInput, Double)] = [
            (.threshold(.diskAvailable), AlertRule(kind: .diskAvailable).threshold),
            (.threshold(.cpuUsage), 90), (.duration, 30.123456789123), (.cooldown, 900),
        ]
        var saves = 0
        for (input, value) in cases {
            var draft = SettingsAlertNumericDraft()
            draft.sync(value: value, input: input, locale: english, isEditing: false)
            let result = draft.commit(value: value, input: input, locale: english)
            if case .changed = result { saves += 1 }
            XCTAssertEqual(result, .unchanged)
        }
        XCTAssertEqual(saves, 0)
        let duration = SettingsAlertNumericInput.duration
        XCTAssertEqual(duration.commit("30.0", currentValue: 30, locale: english), .unchanged)
        // No-op detection must never bypass validation for invalid existing values.
        XCTAssertEqual(duration.commit("20", currentValue: 20, locale: english), .rejected(.outOfRange))
    }

    @MainActor
    func testRejectedCommitsLeavePreferencesAndPersistedRulesUntouched() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let originalRules = preferences.alertRules
        let originalData = fixture.defaults.data(forKey: "prefs.alertRules")
        var saves = 0
        for input in [SettingsAlertNumericInput.duration, .cooldown, .threshold(.diskAvailable)] {
            for text in ["", "-", "NaN", "1e999", "0", "-10", "900.", "900.e2", "999999999999999999999"] {
                var draft = SettingsAlertNumericDraft()
                draft.text = text
                let result = draft.commit(value: 900, input: input, locale: english)
                if case .changed(let value) = result {
                    saves += 1
                    var rules = preferences.alertRules
                    rules[0].duration = value
                    preferences.alertRules = rules
                }
                guard case .rejected = result else { return XCTFail("Unexpected acceptance: \(text)") }
                XCTAssertEqual(draft.text, text)
                XCTAssertEqual(preferences.alertRules, originalRules)
                XCTAssertEqual(fixture.defaults.data(forKey: "prefs.alertRules"), originalData)
            }
        }
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(fixture.makePreferences().alertRules, originalRules)
        XCTAssertEqual(fixture.login.registerCalls + fixture.login.unregisterCalls, 0)
    }

    @MainActor
    func testValidCommitsPersistEngineUnitsWithoutNormalization() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let index = try XCTUnwrap(preferences.alertRules.firstIndex { $0.kind == .diskAvailable })
        let edits: [(SettingsAlertNumericInput, WritableKeyPath<AlertRule, Double>, String, Double)] = [
            (.threshold(.diskAvailable), \.threshold, "12.5", 12_500_000_000),
            (.duration, \.duration, "30.5", 30.5),
            (.cooldown, \.cooldown, "900.5", 900.5),
        ]
        for (input, keyPath, text, expected) in edits {
            var draft = SettingsAlertNumericDraft()
            draft.sync(
                value: preferences.alertRules[index][keyPath: keyPath], input: input,
                locale: english, isEditing: false)
            draft.text = text
            guard
                case .changed(let value) = draft.commit(
                    value: preferences.alertRules[index][keyPath: keyPath], input: input, locale: english)
            else { return XCTFail("Expected valid changed value") }
            var rules = preferences.alertRules
            rules[index][keyPath: keyPath] = value
            XCTAssertEqual(rules[index].normalized(), rules[index])
            preferences.alertRules = rules
            XCTAssertEqual(preferences.alertRules[index][keyPath: keyPath], expected)
            XCTAssertEqual(fixture.makePreferences().alertRules[index][keyPath: keyPath], expected)
        }
        XCTAssertEqual(fixture.login.registerCalls + fixture.login.unregisterCalls, 0)
    }

    func testFeedbackIncludesReasonAllowedRangeAndNotSaved() {
        for input in [SettingsAlertNumericInput.duration, .cooldown, .threshold(.cpuUsage)] {
            for error in [SettingsAlertNumericInput.ValidationError.invalidNumber, .outOfRange] {
                let feedback = input.feedback(for: error, locale: english)
                XCTAssertTrue(feedback.contains("Allowed range:"))
                XCTAssertTrue(feedback.contains(input.text(for: input.storedRange.lowerBound, locale: english)))
                XCTAssertTrue(feedback.contains(input.text(for: input.storedRange.upperBound, locale: english)))
                XCTAssertTrue(feedback.contains("Not saved."))
            }
        }
    }
}
