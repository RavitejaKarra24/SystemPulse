import AppKit
import Observation
import SwiftUI

/// Capture is requested once when a format is selected, never during view rendering.
/// onResult receives (message, isError); Cancel emits no result and writes nothing.
@MainActor
struct DiagnosticsExportButton: View {
    let makeSnapshot: () -> DiagnosticSnapshot
    let onResult: (String, Bool) -> Void

    @State private var session = DiagnosticsExportSession.shared

    var body: some View {
        Menu {
            Button("Export JSON…") { export(.json) }
            Button("Export CSV…") { export(.csv) }
        } label: {
            Label("Export diagnostics", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .fixedSize()
        .disabled(session.isPresenting)
        .help(
            "Save latest-known readings and five minutes of CPU, memory, network and power history as JSON or CSV. No private identifiers are included."
        )
        .accessibilityLabel("Export diagnostics")
        .accessibilityHint("Choose JSON or CSV, then choose where to save the file.")
    }

    private func export(_ format: DiagnosticsFormat) {
        guard !session.isPresenting else { return }
        session.present(snapshot: makeSnapshot(), format: format, onResult: onResult)
    }
}

/// An app-lifetime owner, not a sheet attached to the transient popover. Closing the
/// popover must not destroy the panel or its completion handler. At most one export
/// runs at a time, even if the popover is reopened while the panel is visible.
@Observable
@MainActor
private final class DiagnosticsExportSession {
    static let shared = DiagnosticsExportSession()
    private(set) var isPresenting = false
    @ObservationIgnored private var panel: NSSavePanel?

    func present(snapshot: DiagnosticSnapshot, format: DiagnosticsFormat, onResult: @escaping (String, Bool) -> Void) {
        guard !isPresenting else { return }
        isPresenting = true
        let panel = NSSavePanel()
        self.panel = panel
        panel.title = "Export diagnostics"
        panel.message =
            "Save latest-known readings and five minutes of CPU, memory, aggregate network and power history. No device identity, processes, addresses or paths. Unavailable readings are omitted in JSON and blank in CSV."
        panel.prompt = "Export"
        panel.allowedContentTypes = [format.contentType]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = format.defaultFilename
        panel.isExtensionHidden = false

        // Let Menu's tracking loop finish before opening an independent app-modal
        // panel. Activation is needed for a menu-bar utility with no normal window.
        DispatchQueue.main.async { [self] in
            NSApp.activate()
            panel.begin { [self] response in
                guard response == .OK else {
                    self.finish()
                    return
                }
                guard let destination = panel.url else {
                    self.finish()
                    onResult("Diagnostics were not saved: no destination was selected.", true)
                    _ = NSApp.presentError(DiagnosticExportError.invalidDestination)
                    return
                }
                Task { [self] in
                    do {
                        // Encoding/writing larger selected histories must not block UI.
                        _ = try await Task.detached(priority: .userInitiated) {
                            try DiagnosticsExport.save(snapshot: snapshot, format: format, destination: destination)
                        }.value
                        self.finish()
                        onResult("Diagnostics exported as \(format.rawValue.uppercased()).", false)
                    } catch {
                        self.finish()
                        onResult("Diagnostics were not saved: \(error.localizedDescription)", true)
                        // The save panel may have closed the popover. A toast alone
                        // would hide the failure; AppKit presents an accessible alert.
                        NSApp.activate()
                        _ = NSApp.presentError(error)
                    }
                }
            }
        }
    }

    private func finish() {
        panel = nil
        isPresenting = false
    }
}
