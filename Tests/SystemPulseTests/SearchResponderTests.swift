import AppKit
import Observation
import SwiftUI
import XCTest

@testable import SystemPulse

final class SearchResponderTests: XCTestCase {
    @MainActor
    func testEditCommandsKeepNativeNilTargetsAndCommandOnlyShortcuts() {
        let menu = ApplicationEditMenu.make()
        XCTAssertEqual(menu.items.map(\.title), ["Cut", "Copy", "Paste", "Select All"])
        XCTAssertEqual(menu.items.map(\.keyEquivalent), ["x", "c", "v", "a"])
        XCTAssertEqual(
            menu.items.map(\.action),
            [
                #selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)),
                #selector(NSText.selectAll(_:)),
            ])
        XCTAssertTrue(menu.items.allSatisfy { $0.target == nil })
        XCTAssertTrue(menu.items.allSatisfy { $0.keyEquivalentModifierMask == .command })
    }

    @MainActor
    func testHostedSearchFieldSelectAllAndReplacementUseLocalNativeEditor() async throws {
        let fixture = try makeFixture(query: "12345")
        defer { fixture.window.close() }
        XCTAssertTrue(fixture.window.makeFirstResponder(fixture.field))
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        XCTAssertTrue(PanelKeyboardPolicy.isTextResponder(editor))
        let menu = ApplicationEditMenu.make()
        let selectAll = try XCTUnwrap(menu.items.last)
        let action = try XCTUnwrap(selectAll.action)
        // Resolve through this owned offscreen window's responder, not NSApp's
        // real key window/menu and never a posted OS keyboard event.
        XCTAssertTrue(fixture.window.firstResponder?.tryToPerform(action, with: selectAll) == true)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 5))
        editor.insertText("0", replacementRange: editor.selectedRange())
        settle(fixture.window)
        XCTAssertEqual(editor.string, "0")
        XCTAssertEqual(fixture.model.query, "0")
        XCTAssertTrue(PanelKeyboardPolicy.isTextResponder(fixture.window.firstResponder))
    }

    @MainActor
    func testHostedSearchFocusRequestAndDigitEditingKeepBinding() async throws {
        let fixture = try makeFixture(query: "")
        defer { fixture.window.close() }
        fixture.model.focusRequest.toggle()
        settle(fixture.window)
        let editor = try XCTUnwrap(fixture.field.currentEditor() as? NSTextView)
        XCTAssertTrue(fixture.window.firstResponder === editor)
        for character in "12345" {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
        settle(fixture.window)
        XCTAssertEqual(fixture.model.query, "12345")
        XCTAssertTrue(PanelKeyboardPolicy.isTextResponder(fixture.window.firstResponder))
        XCTAssertNil(
            PanelKeyboardPolicy.topic(
                characters: "2", modifiers: [],
                isEditingText: PanelKeyboardPolicy.isTextResponder(fixture.window.firstResponder),
                hasDetail: false, topics: MetricTab.allCases))
    }

    @MainActor
    private func makeFixture(query: String) throws -> SearchResponderFixture {
        let model = SearchResponderModel(query: query)
        let hosting = NSHostingView(rootView: SearchResponderHarness(model: model))
        let frame = NSRect(x: 0, y: 0, width: 380, height: 80)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = frame
        settle(window)
        guard let field = textField(in: hosting) else {
            window.close()
            throw XCTUnwrapFailure.missingTextField
        }
        return SearchResponderFixture(model: model, window: window, field: field)
    }

    @MainActor
    private func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap { self.textField(in: $0) }.first
    }

    @MainActor
    private func settle(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        window.contentView?.layoutSubtreeIfNeeded()
    }
}

private enum XCTUnwrapFailure: Error { case missingTextField }

@MainActor
@Observable
private final class SearchResponderModel {
    var query: String
    var focusRequest = false
    init(query: String) { self.query = query }
}

private struct SearchResponderHarness: View {
    @Bindable var model: SearchResponderModel
    var body: some View {
        SearchField(text: $model.query, focusRequest: model.focusRequest)
            .padding(8)
    }
}

@MainActor
private struct SearchResponderFixture {
    let model: SearchResponderModel
    let window: NSWindow
    let field: NSTextField
}
