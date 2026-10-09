import QuickLook
import SwiftUI

struct FolderInventoryCard: View {
    let store: MonitorStore
    @State private var search = ""
    @State private var filter = FolderInventory.Filter.all
    @State private var selectedID: String?
    @State private var previewURL: URL?

    private var rows: [FolderInventoryEntry] {
        store.folderInventory?.rows(search: search, filter: filter) ?? []
    }
    private var selected: FolderInventoryEntry? { rows.first { $0.id == selectedID } }
    private var actionsBlocked: Bool {
        store.isScanning || store.isChoosingScanFolder || store.pollingState == .stopped
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Explore observed files")
                        .font(Theme.rowNameFont)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if store.folderNavigation.count > 1 {
                        Button("Back") { _ = store.backToParentFolder() }
                            .controlSize(.small)
                            .disabled(actionsBlocked)
                            .accessibilityLabel("Rescan parent folder")
                            .help("Returns within the selected root and starts a new read-only scan.")
                    }
                }
                Text(
                    "Up to 100 largest measured files and 256 discovered immediate folders. Search filters only these retained rows—not the entire disk."
                )
                .font(Theme.smallCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("Search retained names or paths", text: $search)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search retained inventory")
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear inventory search")
                    }
                }
                .font(Theme.captionFont)
                .padding(8)
                .background(Theme.insetFill, in: RoundedRectangle(cornerRadius: 8))
                Picker("Inventory type", selection: $filter) {
                    ForEach(FolderInventory.Filter.allCases, id: \.self) { type in Text(type.rawValue).tag(type) }
                }
                .pickerStyle(.segmented)
                if let inventory = store.folderInventory {
                    Text(disclosure(inventory))
                        .font(Theme.smallCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if rows.isEmpty {
                    Text(
                        store.isScanning
                            ? "Collecting observed inventory…"
                            : "No retained rows match. Empty or unmeasured scope is shown by scan status above."
                    )
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                } else {
                    List(rows, selection: $selectedID) { entry in
                        inventoryRow(entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("Quick Look") { preview(entry) }.disabled(actionsBlocked)
                                Button("Show in Finder") { reveal(entry) }.disabled(actionsBlocked)
                                if entry.isDirectory {
                                    Button("Scan this folder") { open(entry) }.disabled(actionsBlocked)
                                }
                            }
                    }
                    .listStyle(.plain)
                    .frame(height: CGFloat(min(rows.count, 6)) * 48 + 12)
                    .onKeyPress(keys: [.space], phases: .down) { press in
                        guard
                            PanelKeyboardPolicy.allowsNamedKey(
                                modifiers: press.modifiers, isEditingText: PanelKeyboardPolicy.textResponderIsActive,
                                voiceOverEnabled: PanelKeyboardPolicy.voiceOverIsActive
                            ), let selected, !actionsBlocked
                        else { return .ignored }
                        preview(selected)
                        return .handled
                    }
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        guard
                            PanelKeyboardPolicy.allowsNamedKey(
                                modifiers: press.modifiers, isEditingText: PanelKeyboardPolicy.textResponderIsActive,
                                voiceOverEnabled: PanelKeyboardPolicy.voiceOverIsActive
                            ), let selected, selected.isDirectory, !actionsBlocked
                        else { return .ignored }
                        open(selected)
                        return .handled
                    }
                    .accessibilityLabel(
                        "Retained folder inventory. Select a row; Space previews, Return scans a folder.")
                }
                if let selected {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(relativePath(selected.url))
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Logical: \(ByteFormatter.format(selected.logicalBytes)) · Allocated: \(selected.allocatedBytes.map(ByteFormatter.format) ?? "unavailable")"
                        )
                        .font(Theme.smallCaption)
                        .foregroundStyle(Theme.textSecondary)
                        Text(
                            "Allocated bytes are filesystem-reported, not exclusive or recoverable space. Clones, compression, sparse files and hard links affect accounting. Folder sizes are sums of successfully observed files, not atomic snapshots."
                        )
                        .font(Theme.smallCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Quick Look") { preview(selected) }
                            Button("Finder") { reveal(selected) }
                            if selected.isDirectory { Button("Scan Folder") { open(selected) } }
                        }
                        .controlSize(.small)
                        .disabled(actionsBlocked)
                    }
                }
                Text("Read-only. Quick Look is handled by macOS; unsupported file types may only show metadata.")
                    .font(Theme.smallCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: rows.map(\.id)) {
            if !rows.contains(where: { $0.id == selectedID }) {
                selectedID = nil
                previewURL = nil
            }
        }
        .onChange(of: store.diskScanRevision) {
            selectedID = nil
            previewURL = nil
        }
        .onChange(of: store.isChoosingScanFolder) { if store.isChoosingScanFolder { previewURL = nil } }
    }

    private func inventoryRow(_ entry: FolderInventoryEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(Theme.captionFont).lineLimit(1)
                Text(entry.isDirectory ? "\(entry.fileCount) observed files" : relativePath(entry.url))
                    .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(ByteFormatter.format(entry.logicalBytes)).font(Theme.smallCaption).monospacedDigit()
        }
        .padding(.vertical, 3)
        .help(entry.url.path)
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            entry.isDirectory ? "Select then Return to scan, or Space to preview." : "Select then Space to preview.")
    }

    private func disclosure(_ inventory: FolderInventory) -> String {
        var message = "\(inventory.observedFileCount) files measured · \(inventory.largestFiles.count) largest retained"
        if inventory.omittedDirectoryCount > 0 {
            message += " · \(inventory.omittedDirectoryCount) folder rows omitted"
        }
        if store.isScanning || store.scanResultsArePartial { message += " · partial observations" }
        return message
    }

    private func relativePath(_ url: URL) -> String {
        guard let root = store.scanScope.folderURL, url.path.hasPrefix(root.path + "/") else {
            return url.lastPathComponent
        }
        return String(url.path.dropFirst(root.path.count + 1))
    }

    private func preview(_ entry: FolderInventoryEntry) {
        guard let url = store.inventoryActionURL(for: entry) else {
            store.showToast("Item changed or is unavailable · scan again", isError: true)
            return
        }
        previewURL = url
    }

    private func reveal(_ entry: FolderInventoryEntry) {
        guard let url = store.inventoryActionURL(for: entry) else {
            store.showToast("Item changed or is unavailable · scan again", isError: true)
            return
        }
        store.revealInFinder(path: url.path)
    }

    private func open(_ entry: FolderInventoryEntry) {
        guard store.drillIntoFolder(entry) else {
            store.showToast("Folder changed, is unavailable, or the navigation limit was reached", isError: true)
            return
        }
    }
}
