import AppKit
import SwiftUI

/// Bare panel shortcuts must not intercept editing or modified-key chords.
/// Native text controls and modal dialogs retain their own key handling.
enum PanelKeyboardPolicy {
    static func allowsBareShortcut(modifiers: EventModifiers, isEditingText: Bool)
        -> Bool
    {
        let tolerated: EventModifiers = [.capsLock, .numericPad]
        return !isEditingText && modifiers.subtracting(tolerated).isEmpty
    }

    /// Named keys may carry incidental function-key/numeric-pad qualifiers.
    /// Reject command chords, not those transport flags (notably on arrows).
    static func allowsNamedKey(modifiers: EventModifiers, isEditingText: Bool) -> Bool {
        !isEditingText && modifiers.intersection([.command, .control, .option, .shift]).isEmpty
    }

    static func topic(
        characters: String, modifiers: EventModifiers, isEditingText: Bool,
        hasDetail: Bool, topics: [MetricTab]
    ) -> MetricTab? {
        guard !hasDetail,
            allowsBareShortcut(modifiers: modifiers, isEditingText: isEditingText)
        else { return nil }
        return topics.first { $0.keyEquivalent == characters }
    }

    static func allowsProcessSearch(
        modifiers: EventModifiers, hasDetail: Bool, topic: MetricTab
    ) -> Bool {
        modifiers.subtracting(.capsLock) == .command && !hasDetail
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

}
