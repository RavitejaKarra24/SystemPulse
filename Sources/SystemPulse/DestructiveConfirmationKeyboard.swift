import SwiftUI

/// Explicitly make cancellation the Return action in destructive alerts.
/// The cancel role retains native modal cancellation/Escape semantics; actual
/// OS interaction remains a separate human validation gate.
enum DestructiveConfirmationKeyboard {
    static let cancelShortcut = KeyboardShortcut.defaultAction
    static let destructiveShortcut: KeyboardShortcut? = nil
}
