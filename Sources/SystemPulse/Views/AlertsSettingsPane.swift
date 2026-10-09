import Foundation
import RegexBuilder
import SwiftUI

/// Decimal GB is a display unit only. The engine and persistence always use bytes.
enum SettingsAlertUnits {
    static let bytesPerGB = 1_000_000_000.0

    static func displayedThreshold(_ bytes: Double, kind: AlertKind) -> Double {
        kind == .diskAvailable ? bytes / bytesPerGB : bytes
    }

    static func storedThreshold(_ value: Double, kind: AlertKind) -> Double {
        kind == .diskAvailable ? value * bytesPerGB : value
    }
}

@MainActor
enum SettingsAlertActions {
    /// Only call from an explicit user action, never from view appearance or restored preferences.
    @discardableResult
    static func setEnabled(
        _ enabled: Bool, preferences: Preferences, notifications: LocalNotificationService
    ) -> Task<Void, Never>? {
        preferences.alertsEnabled = enabled
        guard enabled else { return nil }
        return Task {
            // A quick enable-then-disable must not leave a queued permission prompt.
            guard preferences.alertsEnabled else { return }
            await notifications.requestAuthorization()
        }
    }
}

@MainActor
struct AlertsSettingsPane: View {
    let preferences: Preferences
    let notifications: LocalNotificationService

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Enable alerts",
                    isOn: Binding(
                        get: { preferences.alertsEnabled },
                        set: {
                            SettingsAlertActions.setEnabled(
                                $0, preferences: preferences, notifications: notifications)
                        })
                )
                .disabled(notifications.isRequesting && !preferences.alertsEnabled)
                LabeledContent("Notification permission", value: notifications.authorizationStatusLabel)
                if preferences.alertsEnabled && !notifications.canDeliver {
                    Label(
                        "Notifications cannot be delivered. If permission was denied, allow SystemPulse in System Settings → Notifications.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let error = notifications.lastError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
                if !notifications.canDeliver {
                    Button(notifications.isRequesting ? "Requesting Permission…" : "Enable Notifications…") {
                        SettingsAlertActions.setEnabled(
                            true, preferences: preferences, notifications: notifications)
                    }
                    .disabled(notifications.isRequesting)
                    .help("Enable alerts and explicitly request macOS notification permission")
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(
                    "Alerts are off by default. Notifications are silent, with no startup spam. Merely opening Settings never asks for permission."
                )
            }
            Section {
                Text(
                    "Sustained duration is how long a condition must remain beyond its threshold. Cooldown is the minimum time between notifications for that rule. Unavailable readings do not trigger alerts."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            ForEach(AlertKind.allCases) { kind in
                AlertRuleSettingsSection(preferences: preferences, kind: kind)
                    .disabled(!preferences.alertsEnabled)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .task { await notifications.refreshAuthorization() }
    }
}

@MainActor
private struct AlertRuleSettingsSection: View {
    let preferences: Preferences
    let kind: AlertKind

    private var rule: AlertRule {
        preferences.alertRules.first { $0.kind == kind }
            ?? AlertRule(kind: kind, enabled: false)
    }

    private var thresholdLabel: String {
        switch kind {
        case .cpuUsage: return "Usage at or above (%)"
        case .memoryHeadroom: return "Estimated free + cached at or below (%)"
        case .diskAvailable: return "Home volume available at or below (GB)"
        case .batteryCharge: return "Charge on battery at or below (%)"
        case .thermal: return "Thermal state at or above"
        }
    }

    var body: some View {
        Section {
            Toggle("Enable \(kind.title) alert", isOn: binding(\.enabled))
            Group {
                if kind == .thermal {
                    Picker(thresholdLabel, selection: binding(\.threshold)) {
                        Text("Serious").tag(2.0)
                        Text("Critical").tag(3.0)
                    }
                } else {
                    SettingsNumberField(
                        title: thresholdLabel, value: binding(\.threshold), input: .threshold(kind))
                }
                SettingsNumberField(
                    title: "Sustained duration (seconds)", value: binding(\.duration), input: .duration)
                SettingsNumberField(title: "Cooldown (seconds)", value: binding(\.cooldown), input: .cooldown)
            }
            .disabled(!rule.enabled)
        } header: {
            Text(kind.title)
        } footer: {
            Text(footnote)
        }
    }

    private var footnote: String {
        let timing = "Duration: 30–86,400 seconds. Cooldown: 900–604,800 seconds."
        switch kind {
        case .diskAvailable:
            return
                "Uses the home volume's available capacity, not the volume selected in Disk. APFS volumes can share container space. 1 GB = 1 billion bytes; the 5 GiB default is about 5.37 GB. \(timing)"
        case .memoryHeadroom:
            return
                "Headroom estimates free + cached memory as a percentage of total memory, not macOS memory pressure. Threshold: 0–100%. \(timing)"
        case .thermal:
            return "Serious and Critical are macOS thermal states. \(timing)"
        case .cpuUsage:
            return "Threshold: 1–100%. \(timing)"
        case .batteryCharge:
            return "Only evaluated on battery power, not while plugged in or charging. Threshold: 0–100%. \(timing)"
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AlertRule, Value>) -> Binding<Value> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { value in
                var rules = preferences.alertRules
                guard let index = rules.firstIndex(where: { $0.kind == kind }) else { return }
                rules[index][keyPath: keyPath] = value
                preferences.alertRules = rules
            })
    }
}

/// Pure validation/commit policy. Values returned by `commit` are in engine units
/// (bytes for disk thresholds), ready for persistence without normalization.
enum SettingsAlertNumericInput: Equatable {
    case threshold(AlertKind)
    case duration
    case cooldown

    enum ValidationError: Error, Equatable {
        case invalidNumber
        case outOfRange
    }

    enum Commit: Equatable {
        case rejected(ValidationError)
        case unchanged
        case changed(Double)
    }

    var storedRange: ClosedRange<Double> {
        switch self {
        case .threshold(.cpuUsage): return 1...100
        case .threshold(.memoryHeadroom), .threshold(.batteryCharge): return 0...100
        case .threshold(.diskAvailable): return 1...1_125_899_906_842_624
        case .threshold(.thermal): return 2...3
        case .duration: return AlertRule.minimumDuration...86_400
        case .cooldown: return AlertRule.minimumCooldown...604_800
        }
    }

    private var scale: Double {
        self == .threshold(.diskAvailable) ? SettingsAlertUnits.bytesPerGB : 1
    }

    private func format(locale: Locale) -> FloatingPointFormatStyle<Double> {
        .number.grouping(.never).precision(.fractionLength(0...9)).locale(locale)
    }

    func text(for storedValue: Double, locale: Locale) -> String {
        format(locale: locale).format(storedValue / scale)
    }

    func accepts(_ storedValue: Double) -> Bool {
        storedValue.isFinite && storedRange.contains(storedValue)
            && (self != .threshold(.thermal) || storedValue.rounded() == storedValue)
    }

    func validate(_ draft: String, locale: Locale) -> Result<Double, ValidationError> {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let style = format(locale: locale)
        // ParseStrategy alone accepts prefixes ("30junk" → 30). The Foundation
        // format's consuming parser must match the entire draft, without grouping.
        guard trimmed.wholeMatch(of: Regex { style }) != nil,
            let number = try? FloatingPointParseStrategy(format: style, lenient: false).parse(trimmed),
            number.isFinite
        else { return .failure(.invalidNumber) }
        let storedValue = number * scale
        guard accepts(storedValue) else { return .failure(.outOfRange) }
        return .success(storedValue)
    }

    func commit(_ draft: String, currentValue: Double, locale: Locale) -> Commit {
        switch validate(draft, locale: locale) {
        case .failure(let error): return .rejected(error)
        case .success(let storedValue):
            // An untouched formatted value must not round the persisted value.
            // Validate first: even unchanged-looking invalid input is rejected.
            if storedValue == currentValue
                || (accepts(currentValue)
                    && draft.trimmingCharacters(in: .whitespacesAndNewlines) == text(for: currentValue, locale: locale))
            {
                return .unchanged
            }
            return .changed(storedValue)
        }
    }

    func feedback(for error: ValidationError, locale: Locale) -> String {
        let unit: String
        switch self {
        case .threshold(.diskAvailable): unit = "GB"
        case .threshold(.thermal): unit = "(whole thermal levels)"
        case .threshold: unit = "%"
        case .duration, .cooldown: unit = "seconds"
        }
        let range =
            "Allowed range: \(text(for: storedRange.lowerBound, locale: locale))–\(text(for: storedRange.upperBound, locale: locale)) \(unit)."
        let reason =
            error == .invalidNumber ? "Enter a complete, finite number." : "Value is outside the allowed range."
        return "\(reason) \(range) Not saved."
    }
}

/// Local draft state is independent of Preferences and can be exercised without UI.
struct SettingsAlertNumericDraft {
    var text = ""
    private(set) var error: SettingsAlertNumericInput.ValidationError?
    private var synchronizedText = ""

    mutating func sync(value: Double, input: SettingsAlertNumericInput, locale: Locale, isEditing: Bool) {
        guard !isEditing, input.accepts(value) else { return }
        text = input.text(for: value, locale: locale)
        synchronizedText = text
        error = nil
    }

    mutating func commit(
        value: Double, input: SettingsAlertNumericInput, locale: Locale
    ) -> SettingsAlertNumericInput.Commit {
        let result = input.commit(text, currentValue: value, locale: locale)
        switch result {
        case .rejected(let failure): error = failure
        case .unchanged: sync(value: value, input: input, locale: locale, isEditing: false)
        case .changed(let newValue):
            // Focusing an untouched field must not overwrite a newer external rule.
            // This check follows validation, so it cannot hide rejected input.
            if text == synchronizedText, input.accepts(value) {
                sync(value: value, input: input, locale: locale, isEditing: false)
                return .unchanged
            }
            sync(value: newValue, input: input, locale: locale, isEditing: false)
        }
        return result
    }
}

private struct SettingsNumberField: View {
    let title: String
    @Binding var value: Double
    let input: SettingsAlertNumericInput
    @Environment(\.locale) private var locale
    @FocusState private var isFocused: Bool
    @State private var draft = SettingsAlertNumericDraft()

    private var feedback: String? {
        draft.error.map { input.feedback(for: $0, locale: locale) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                TextField(title, text: $draft.text)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(minWidth: 110, idealWidth: 110, maxWidth: 160)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .onExitCommand {
                        guard isFocused else { return }
                        // Escape restores the latest stored value, never the rejected draft.
                        draft.sync(value: value, input: input, locale: locale, isEditing: false)
                        isFocused = false
                    }
                    .accessibilityLabel(title)
                    .accessibilityHint(feedback ?? "Saved on Return or when leaving the field. Escape cancels editing.")
            }
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(title): \(feedback)")
            }
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused && !focused { commit() }
        }
        .onChange(of: value, initial: true) {
            draft.sync(value: value, input: input, locale: locale, isEditing: isFocused)
        }
        .onChange(of: locale) {
            draft.sync(value: value, input: input, locale: locale, isEditing: isFocused)
        }
    }

    private func commit() {
        if case .changed(let newValue) = draft.commit(value: value, input: input, locale: locale) {
            value = newValue
        }
    }
}
