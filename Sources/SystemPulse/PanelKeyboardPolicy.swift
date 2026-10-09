import AppKit
import SwiftUI

/// Bare panel shortcuts must not intercept editing or assistive-key chords.
/// Native text controls and modal dialogs retain their own key handling.
enum PanelKeyboardPolicy {
    static func allowsBareShortcut(modifiers: EventModifiers, isEditingText: Bool, voiceOverEnabled: Bool = false)
        -> Bool
    {
        // Caps Lock can be VoiceOver's modifier. Conservatively leave that
        // chord to assistive technology, even if it is only a locked state.
        let tolerated: EventModifiers = voiceOverEnabled ? .numericPad : [.capsLock, .numericPad]
        return !isEditingText && modifiers.subtracting(tolerated).isEmpty
    }

    /// Named keys may carry incidental function-key/numeric-pad qualifiers.
    /// Reject command chords, not those transport flags (notably on arrows).
    static func allowsNamedKey(modifiers: EventModifiers, isEditingText: Bool, voiceOverEnabled: Bool = false) -> Bool {
        !isEditingText && modifiers.intersection([.command, .control, .option, .shift]).isEmpty
            && (!voiceOverEnabled || !modifiers.contains(.capsLock))
    }

    static func topic(
        characters: String, modifiers: EventModifiers, isEditingText: Bool,
        hasDetail: Bool, topics: [MetricTab], voiceOverEnabled: Bool = false
    ) -> MetricTab? {
        guard !hasDetail,
            allowsBareShortcut(modifiers: modifiers, isEditingText: isEditingText, voiceOverEnabled: voiceOverEnabled)
        else { return nil }
        return topics.first { $0.keyEquivalent == characters }
    }

    static func allowsProcessSearch(
        modifiers: EventModifiers, hasDetail: Bool, topic: MetricTab, voiceOverEnabled: Bool = false
    ) -> Bool {
        modifiers.subtracting(voiceOverEnabled ? [] : .capsLock) == .command && !hasDetail
            && (topic == .cpu || topic == .memory)
    }

    @MainActor
    static func isTextResponder(_ responder: NSResponder?) -> Bool {
        if let text = responder as? NSTextView { return text.isEditable || text.isSelectable }
        if let text = responder as? NSTextField { return text.isEditable || text.isSelectable }
        return false
    }

    @MainActor
    static var textResponderIsActive: Bool { isTextResponder(NSApp.keyWindow?.firstResponder) }

    @MainActor
    static var voiceOverIsActive: Bool { NSWorkspace.shared.isVoiceOverEnabled }
}
