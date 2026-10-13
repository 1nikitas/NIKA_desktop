import XCTest
@testable import NIKADesktop

final class DesktopTests: XCTestCase {
    func testSSEUnicodeAndTerminal() throws {
        XCTAssertEqual(try LlamaProvider.token(from: "data: {\"choices\":[{\"delta\":{\"content\":\"Привет 🌿\"}}]}"), "Привет 🌿")
        XCTAssertNil(try LlamaProvider.token(from: "data: [DONE]"))
        XCTAssertNil(try LlamaProvider.token(from: ": keepalive"))
        XCTAssertNil(try LlamaProvider.token(from: "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}"))
        XCTAssertThrowsError(try LlamaProvider.token(from: "data: invalid"))
    }
    func testIntegrityRejectsWrongSizeAndHash() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        let sha = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        XCTAssertNoThrow(try ModelLibrary.verify(file, expectedBytes: 3, expectedHash: sha))
        XCTAssertThrowsError(try ModelLibrary.verify(file, expectedBytes: 4, expectedHash: sha))
        XCTAssertThrowsError(try ModelLibrary.verify(file, expectedBytes: 3, expectedHash: String(repeating: "0", count: 64)))
    }
    @MainActor
    func testLocalHistorySurvivesRestartAndCloudSwitchNeverCopiesIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false)
        let local = LocalConversation(title: "Private", modelID: "mini", messages: [.init(role: "user", content: "private fact")])
        store.save(local)
        let reopened = DesktopStore(root: root, restoreCredentials: false)
        XCTAssertEqual(reopened.localChats.first?.messages.first?.content, "private fact")
        let workspace = Workspace(store: reopened)
        workspace.open(local)
        XCTAssertTrue(workspace.isLocal)
        workspace.selectProvider("cloud")
        XCTAssertFalse(workspace.isLocal)
        XCTAssertTrue(workspace.messages.isEmpty)
        XCTAssertNil(workspace.selectedID)
        XCTAssertEqual(reopened.localChats.count, 1)
        XCTAssertNil(reopened.client)
    }
    @MainActor
    func testMissingLocalModelDoesNotUseCloudOrLosePrompt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false)
        let workspace = Workspace(store: store)
        workspace.selectProvider("mini"); workspace.draft = "Only local"; workspace.send()
        for _ in 0..<30 { if !workspace.sending { break }; await Task.yield() }
        XCTAssertNotNil(workspace.error)
        XCTAssertTrue(workspace.isLocal)
        XCTAssertNil(store.client)
        XCTAssertEqual(workspace.messages.first?.content, "Only local")
        XCTAssertFalse(workspace.sending)
    }
    @MainActor
    func testChangingConversationFencesOldCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false)
        let workspace = Workspace(store: store)
        workspace.selectProvider("mini"); workspace.draft = "Old"; workspace.send()
        workspace.newChat(provider: "cloud")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(workspace.messages.isEmpty)
        XCTAssertNil(workspace.error)
        XCTAssertFalse(workspace.sending)
    }
    func testLocalAttachmentsKeepUnicodeAndRejectBinary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = root.appendingPathComponent("note.txt")
        try Data("Важный документ".utf8).write(to: text)
        let result = try await Workspace.localAttachmentText([text])
        XCTAssertTrue(result.contains("Важный документ"))
        let binary = root.appendingPathComponent("image.png")
        try Data([0xFF, 0xFE, 0xAA]).write(to: binary)
        do { _ = try await Workspace.localAttachmentText([binary]); XCTFail("Binary must not be sent as text") } catch { }
    }
    func testBackendEventsAndReceiptsDecodeUsingMobileContract() throws {
        let receipt = try JSONDecoder().decode(BFFSentMessage.self, from: Data(#"{"id":"task-1","chat_id":"chat-1","status":"pending"}"#.utf8))
        XCTAssertEqual(receipt.id, "task-1")
        let event = try JSONDecoder().decode(BFFWebSocketEvent.self, from: Data(#"{"type":"token","task_id":"task-1","data":"Hello","replay":true}"#.utf8))
        XCTAssertEqual(event.type, .token); XCTAssertEqual(event.taskID, receipt.id); XCTAssertEqual(event.replay, true)
    }
    func testBackendRejectsInsecurePublicEndpoint() throws {
        XCTAssertThrowsError(try BFFClient.normalizedBaseURL("http://example.org"))
        XCTAssertEqual(try BFFClient.normalizedBaseURL("https://nika-agent.ru/api/").absoluteString, "https://nika-agent.ru")
    }
    func testScheduleUsesNativeContractAndAccountTimezone() throws {
        let draft = NIKAErrandDraft(instruction: "  Morning summary  ", cadence: .weekdays,
                                   localTime: try .init(hour: 9, minute: 30), creationSource: .managementEntry)
        let data = try JSONEncoder().encode(BFFCreateScheduleRequest(draft: draft))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["instruction"] as? String, "Morning summary")
        XCTAssertEqual(json["local_time"] as? String, "09:30")
        XCTAssertEqual(json["cadence"] as? String, "weekdays")
        XCTAssertNil(json["timezone"]) // server resolves the account timezone
        XCTAssertEqual(json["creation_source"] as? String, "management_entry")
    }
    func testGoalsReadTheExistingAspirationAndMilestoneSchema() throws {
        let goal = DesktopGoal.decode(.object(["id": .string("g1"), "description": .string("Learn Swift"), "milestones": .array([.object(["id": .string("s1"), "title": .string("Build an app"), "status": .string("done")])])]))
        XCTAssertEqual(goal?.title, "Learn Swift")
        XCTAssertEqual(goal?.steps.first?.done, true)
        XCTAssertNil(DesktopGoal.decode(.object(["id": .string("g1")])))
    }
    @MainActor
    func testCorruptHistoryIsNeverOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("local-conversations.json")
        let original = Data("corrupt-but-recoverable".utf8)
        try original.write(to: file)
        let store = DesktopStore(root: root, restoreCredentials: false)
        XCTAssertNotNil(store.error)
        store.save(LocalConversation(title: "New", modelID: "mini"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    @MainActor
    func testDownloadInstallsOnlyAfterVerification() async throws {
        guard let address = ProcessInfo.processInfo.environment["NIKA_TEST_DOWNLOAD_URL"], let url = URL(string: address) else { throw XCTSkip("Local HTTP fixture not running") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ModelLibrary(root: root)
        let item = DesktopModel(id: "download-test", name: "Fixture", publisher: "Test", parameters: "", quantization: "", bytes: 3,
                                sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", url: url, filename: "test.gguf")
        library.models = [item]; library.download(item)
        for _ in 0..<200 { if library.installed.contains(item.id) || library.error != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(library.error)
        XCTAssertTrue(library.installed.contains(item.id))
        XCTAssertEqual(try Data(contentsOf: library.file(item)), Data("abc".utf8))
        await library.delete(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.file(item).path))
    }
    @MainActor
    func testRealWorkspaceSavesAndReopensOfflineAnswer() async throws {
        guard let path = ProcessInfo.processInfo.environment["NIKA_TEST_GGUF"] else { throw XCTSkip("Real GGUF not configured") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let models = root.appendingPathComponent("Models")
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DesktopModel.legacyCatalogue[0]
        try FileManager.default.linkItem(at: URL(fileURLWithPath: path), to: models.appendingPathComponent(model.filename))
        let store = DesktopStore(root: root, restoreCredentials: false)
        store.settings = InferenceSettings(context: 2048, temperature: 0, topP: 0.9, maxTokens: 64)
        let workspace = Workspace(store: store)
        workspace.selectProvider(model.id)
        workspace.draft = "What is two plus two? Reply with one number."
        workspace.send()
        for _ in 0..<1200 { if !workspace.sending { break }; try await Task.sleep(for: .milliseconds(100)) }
        if workspace.sending { workspace.stop(); XCTFail("Workspace turn timed out") }
        XCTAssertNil(workspace.error)
        XCTAssertTrue(workspace.messages.contains { $0.role == "assistant" && !$0.content.isEmpty })
        XCTAssertNil(store.client)
        workspace.draft = "Keep my draft"
        workspace.retry()
        for _ in 0..<1200 { if !workspace.sending { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(workspace.error)
        XCTAssertEqual(workspace.messages.count, 2)
        XCTAssertEqual(workspace.messages.last?.versions?.count, 2)
        XCTAssertEqual(workspace.draft, "Keep my draft")
        workspace.beginEdit(workspace.messages[0]); workspace.draft = "What is three plus three? Reply with one number."; workspace.send()
        for _ in 0..<1200 { if !workspace.sending { break }; try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(workspace.error); XCTAssertEqual(workspace.messages.count, 2)
        XCTAssertTrue(workspace.messages.first?.content.contains("three plus three") == true)
        if let output = ProcessInfo.processInfo.environment["NIKA_TEST_ARTIFACT_DIR"] {
            let directory = URL(fileURLWithPath: output); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(store.localChats).write(to: directory.appendingPathComponent("local-conversations.json"), options: .atomic)
        }
        await store.library.unload()
        let restored = DesktopStore(root: root, restoreCredentials: false)
        let chat = try XCTUnwrap(restored.localChats.first)
        XCTAssertEqual(chat.messages, workspace.messages)
        let reopened = Workspace(store: restored); reopened.open(chat)
        XCTAssertEqual(reopened.messages, workspace.messages)
        XCTAssertTrue(reopened.isLocal)
    }
    func testRealLocalRuntimeStreamsAndUnloads() async throws {
        guard let path = ProcessInfo.processInfo.environment["NIKA_TEST_GGUF"] else { throw XCTSkip("Set NIKA_TEST_GGUF to run real llama.cpp integration") }
        let provider = LlamaProvider()
        let settings = InferenceSettings(context: 2048, temperature: 0, topP: 0.9, maxTokens: 48)
        do {
            try await provider.load(model: URL(fileURLWithPath: path), settings: settings)
            let stream = try await provider.generate(messages: [.init(role: "user", content: "Reply with the number that is two plus two. Do not explain.")], settings: settings)
            var output = ""; var chunks = 0
            for try await token in stream { output += token; chunks += 1 }
            XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertGreaterThan(chunks, 0)
            print("LOCAL_RUNTIME_RESULT: \(output)")
            await provider.unload()
            do { _ = try await provider.generate(messages: [.init(role: "user", content: "Hello")], settings: settings); XCTFail("Unloaded runtime must reject generation") } catch { }
        } catch { await provider.unload(); throw error }
    }
}
