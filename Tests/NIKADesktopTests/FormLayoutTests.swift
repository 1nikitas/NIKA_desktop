import XCTest
import SwiftUI
import AppKit
@testable import NIKADesktop

final class FormLayoutTests: XCTestCase {
    @MainActor func testBotInstructionFieldFitsAboveFooter() async throws {
        for height: CGFloat in [650, 550] {
            for dark in [true, false] {
                var draft = BotDraft(); draft.instructions = "Помогай планировать день.\nОтвечай коротко и по делу."
                let view = BotEditor(draft: draft, preferredHeight: height, presets: [], client: nil, editID: nil, saved: { _ in }).environment(\.colorScheme, dark ? .dark : .light)
                let hosting = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 590, height: height), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                hosting.frame = NSRect(x: 0, y: 0, width: 590, height: height)
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                hosting.layoutSubtreeIfNeeded()
                let fields = descendants(hosting).compactMap { $0 as? NSTextView }.filter { $0.isEditable }
                let text = try XCTUnwrap(fields.first)
                let scroll = try XCTUnwrap(text.enclosingScrollView)
                XCTAssertGreaterThan(scroll.bounds.height, 50)
                XCTAssertGreaterThanOrEqual(scroll.visibleRect.height, scroll.bounds.height - 1, "Instruction field clipped at height \(height)")
                let bounds = scroll.convert(scroll.bounds, to: hosting)
                XCTAssertTrue(hosting.bounds.contains(bounds), "Field outside form at \(height)")
                if let output = ProcessInfo.processInfo.environment["NIKA_LAYOUT_ARTIFACTS"], let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    let url = URL(fileURLWithPath: output).appendingPathComponent("bot-editor-\(Int(height))-\(dark ? "dark" : "light").png")
                    try bitmap.representation(using: .png, properties: [:])?.write(to: url)
                }
                window.close()
            }
        }
    }
    @MainActor func testConversationFitsNarrowAndWideWindows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false)
        for (width, height) in [(360.0, 450.0), (575.0, 540.0), (1000.0, 780.0), (1600.0, 1000.0)] {
            let workspace = Workspace(store: store)
            workspace.newChat(provider: "mini")
            workspace.messages = [
                .init(role: "user", content: "Сгенерируй мне кота в кедах"),
                .init(role: "assistant", content: "## Кот в кедах\n\nВот описание: рыжий кот в белых кедах идёт по улице.\n\n- Мягкий вечерний свет\n- Детали шерсти и обуви\n\n```swift\nlet description = \"a very long line which should scroll horizontally inside the code block instead of widening the conversation\"\n```"),
                .init(role: "user", content: "Сделай фон светлее. И добавь зелёный рюкзак.")
            ]
            workspace.draft = "Первая строка\nВторая строка\nТретья строка\nЧетвёртая строка\nПятая строка"
            let hosting = NSHostingView(rootView: ConversationView(workspace: workspace, showModels: {}, signIn: {}).environment(\.colorScheme, .dark))
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = hosting
            hosting.frame = .init(x: 0, y: 0, width: width, height: height)
            hosting.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(200)); hosting.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(hosting.frame.width, width + 1)
            XCTAssertLessThanOrEqual(hosting.frame.height, height + 1)
            let inputs = descendants(hosting).compactMap { $0 as? NSTextView }.filter { $0.isEditable }
            XCTAssertFalse(inputs.isEmpty, "Native composer must be present")
            for input in inputs {
                if let scroll = input.enclosingScrollView {
                    let bounds = scroll.convert(scroll.bounds, to: hosting)
                    XCTAssertTrue(hosting.bounds.insetBy(dx: -1, dy: -1).contains(bounds), "Composer outside \(width) × \(height): \(bounds)")
                }
            }
            let input = try XCTUnwrap(inputs.first)
            let editorScroll = try XCTUnwrap(input.enclosingScrollView)
            let multilineHeight = editorScroll.bounds.height
            for draft in ["", "Короткий вопрос", String(repeating: "Длинный черновик с переносом слов. ", count: 80), ""] {
                workspace.draft = draft
                try await Task.sleep(for: .milliseconds(100))
                hosting.layoutSubtreeIfNeeded()
                if draft.count < 30 {
                    XCTAssertLessThanOrEqual(editorScroll.bounds.height, 26, "Empty/short draft must release transcript space")
                    XCTAssertLessThan(editorScroll.bounds.height, multilineHeight)
                } else {
                    XCTAssertGreaterThan(editorScroll.bounds.height, 26, "Wrapped text must grow the editor")
                    XCTAssertLessThanOrEqual(editorScroll.bounds.height, height < 600 ? 73 : 109)
                    XCTAssertGreaterThan(input.bounds.height, editorScroll.contentSize.height, "Long draft must scroll internally")
                }
                XCTAssertTrue(hosting.bounds.insetBy(dx: -1, dy: -1).contains(editorScroll.convert(editorScroll.bounds, to: hosting)))
            }
            if let output = ProcessInfo.processInfo.environment["NIKA_LAYOUT_ARTIFACTS"], let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("chat-layout-\(Int(width)).png"))
            }
            window.close()
        }
    }
    @MainActor private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
