import AppKit
import Observation

@MainActor
struct FolderSelectionClient {
    let begin: (@escaping (URL?) -> Void) -> Void
    let cancel: () -> Void

    static func live() -> Self {
        let presenter = NativeFolderPresenter()
        return Self(begin: { presenter.begin($0) }, cancel: { presenter.cancel() })
    }
}

/// Retained independently of the transient popover. Injected clients never
/// activate the app or present a native dialog during automated tests.
@Observable
@MainActor
final class FolderSelectionSession {
    static let shared = FolderSelectionSession(client: .live())
    private(set) var isPresenting = false
    private let client: FolderSelectionClient
    private var revision: UInt64 = 0
    @ObservationIgnored private var cancelSelection: (() -> Void)?

    init(client: FolderSelectionClient) { self.client = client }

    func present(for store: MonitorStore) {
        guard !isPresenting, let token = store.beginFolderSelection() else { return }
        revision &+= 1
        let request = revision
        isPresenting = true
        cancelSelection = { [weak store] in _ = store?.completeFolderSelection(nil, revision: token) }
        // Retain the owner until the panel resolves, not the store. A discarded
        // popover/store cannot accidentally start a scan from a delayed response.
        client.begin { [self, weak store] url in
            guard isPresenting, revision == request else { return }
            finish()
            _ = store?.completeFolderSelection(url, revision: token)
        }
    }

    func cancel() {
        guard isPresenting else { return }
        let cancellation = cancelSelection
        finish()
        cancellation?()
        client.cancel()
    }

    private func finish() {
        revision &+= 1
        isPresenting = false
        cancelSelection = nil
    }
}

@MainActor
private final class NativeFolderPresenter {
    private var panel: NSOpenPanel?
    private var revision: UInt64 = 0

    func begin(_ completion: @escaping (URL?) -> Void) {
        guard panel == nil else { return }
        revision &+= 1
        let request = revision
        let panel = NSOpenPanel()
        self.panel = panel
        panel.title = "Scan a folder"
        panel.message =
            "Read-only inventory of this folder, including hidden and package files. Nothing is deleted. Large folders may take time; you can cancel the scan. SystemPulse does not save the scan scope or add it to diagnostics."
        panel.prompt = "Scan Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = true
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, self.revision == request, self.panel === panel else { return }
            NSApp.activate()
            panel.begin { [weak self] response in
                guard let self, self.revision == request, self.panel === panel else { return }
                self.panel = nil
                completion(response == .OK ? panel.url : nil)
            }
        }
    }

    func cancel() {
        revision &+= 1
        let panel = panel
        self.panel = nil
        panel?.cancel(nil)
    }
}
