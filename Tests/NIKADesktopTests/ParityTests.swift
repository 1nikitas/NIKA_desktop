import XCTest
import AppKit
@testable import NIKADesktop

final class ParityTests: XCTestCase {
    @MainActor
    func testRealLocalImageAnswerPersistsWithoutCloud() async throws {
        guard let path = ProcessInfo.processInfo.environment["NIKA_TEST_GGUF"], let projector = ProcessInfo.processInfo.environment["NIKA_TEST_PROJECTOR"] else { throw XCTSkip("Vision GGUF not configured") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false)
        let model = DesktopModel.legacyCatalogue[0]; let metadata = try XCTUnwrap(model.visionProjector)
        let auxiliary = DesktopModel(id: "mini-vision", name: "Vision", publisher: "Qwen", parameters: "", quantization: "F16", bytes: metadata.bytes, sha256: metadata.sha256, url: nil, filename: "mini-mmproj.gguf", auxiliaryFor: model.id)
        store.library.addDiscovered(auxiliary)
        try FileManager.default.linkItem(at: URL(fileURLWithPath: path), to: store.library.file(model))
        try FileManager.default.linkItem(at: URL(fileURLWithPath: projector), to: store.library.file(auxiliary))
        store.library.installed = [model.id, auxiliary.id]
        store.settings = InferenceSettings(context: 4096, temperature: 0, topP: 0.9, maxTokens: 48)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 224, pixelsHigh: 224, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 224, height: 224).fill(); NSGraphicsContext.restoreGraphicsState()
        let image = root.appendingPathComponent("red.png"); try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: image)
        let workspace = Workspace(store: store); workspace.selectProvider(model.id); workspace.draft = "What color fills this image? Reply with one word."; workspace.add([image]); workspace.send()
        for _ in 0..<1200 { if !workspace.sending { break }; try await Task.sleep(for: .milliseconds(100)) }
        if workspace.sending { workspace.stop(); XCTFail("Vision timed out") }
        await store.library.unload()
        XCTAssertNil(workspace.error)
        XCTAssertEqual(workspace.messages.first?.localImages?.count, 1)
        XCTAssertFalse(workspace.messages.last?.content.isEmpty ?? true)
        XCTAssertNil(store.client)
        print("LOCAL_VISION_RESULT: \(workspace.messages.last?.content ?? "")")
        let restored = DesktopStore(root: root, restoreCredentials: false)
        XCTAssertEqual(restored.localChats.first?.messages.first?.localImages?.count, 1)
    }
    @MainActor
    func testMacWebRTCCreatesRealAudioOfferWithoutCapturingMicrophone() async throws {
        let peer = try LiveDesktopVoice.makePeer(delegate: nil)
        defer { peer.close() }
        let offer = try await LiveDesktopVoice.offer(peer)
        XCTAssertTrue(offer.sdp.contains("m=audio"))
        XCTAssertTrue(offer.sdp.contains("opus/48000"))
    }
    func testLiveVoiceUsesSharedTranscriptAndDelegationProtocol() throws {
        let data = Data(#"{"type":"session.input_transcript.delta","delta":"Hello"}"#.utf8)
        guard case .transcript(let delta) = LiveVoiceServerEvent.parse(data) else { return XCTFail("Transcript not parsed") }
        XCTAssertEqual(delta.text, "Hello"); XCTAssertEqual(delta.speaker, .user)
        let reply = try JSONSerialization.jsonObject(with: LiveVoiceClientEvent.commentaryAppend(delegationID: "d", content: "Done", eventID: "e").encoded()) as? [String: String]
        XCTAssertEqual(reply?["delegation_id"], "d"); XCTAssertEqual(reply?["content"], "Done")
    }
    func testRemoteSpeechRequestMatchesMobileAndRejectsInvalidVoiceID() throws {
        let keys = DesktopSpeechKeys(key: "test-only", voiceID: "voice123", proxy: "")
        let request = try keys.request("Hello")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-only")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["model_id"] as? String, "eleven_flash_v2_5")
        XCTAssertThrowsError(try DesktopSpeechKeys(key: "test", voiceID: "../other", proxy: "").request("Hello"))
    }
    @MainActor
    func testNotificationActionRejectsPastDatesBeforeRequestingPermission() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertThrowsError(try LocalActionExecutor.notificationRequest(["title": "Past", "date": "1970-01-01T00:00:00Z"], now: now))
        let request = try LocalActionExecutor.notificationRequest(["title": "Later", "date": "2030-01-01T10:00:00Z"], now: now)
        XCTAssertEqual(request.content.title, "Later"); XCTAssertNotNil(request.trigger)
    }
    func testPersonalityAndBrowserBodiesMatchBackendContracts() {
        let personality = Workspace.personalityChatBody(title: "Work", name: "Editor", prompt: "Edit clearly", ephemeral: false)
        XCTAssertEqual(personality["personality"], .object(["name": .string("Editor"), "system_prompt": .string("Edit clearly")]))
        XCTAssertNil(personality["agent_id"])
        XCTAssertEqual(Workspace.browserAnswerBody(requestID: "r", answer: "Continue"), ["request_id": .string("r"), "answer": .string("Continue")])
    }
    func testLocalActionsRejectUnknownExecutionAndParsePreview() throws {
        XCTAssertNil(LocalAction.parse(#"{"tool":"shell","arguments":{"command":"rm -rf"}}"#))
        let action = try XCTUnwrap(LocalAction.parse(#"{"tool":"save_text_file","arguments":{"filename":"plan.md","content":"A plan"}}"#))
        XCTAssertEqual(action.detail, "plan.md"); XCTAssertEqual(action.arguments["content"], "A plan")
    }
    @MainActor
    func testLocalMemorySurvivesRestartWithoutCloudMutation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false)
        store.saveMemories([DesktopMemory(title: "Preference", detail: "Short answers")])
        let restored = DesktopStore(root: root, restoreCredentials: false)
        XCTAssertEqual(restored.localMemories.first?.detail, "Short answers"); XCTAssertNil(restored.client)
        XCTAssertTrue(restored.localMemoryContext.contains("Short answers"))
    }
    func testSharedMarkdownKeepsTableAndOrderedLists() {
        let blocks = MarkdownParser.parse("3. first\n4. second\n\n| A | B |\n|---|---|\n| One | Two |")
        XCTAssertTrue(blocks.contains { if case .list(let ordered, let start, _) = $0 { return ordered && start == 3 }; return false })
        XCTAssertTrue(blocks.contains { if case .table(let headers, let rows) = $0 { return headers == ["A", "B"] && rows == [["One", "Two"]] }; return false })
        XCTAssertEqual(MarkdownView.csv([["a,b", "\"quote\""]]), "\"a,b\",\"\"\"quote\"\"\"")
    }
    func testRangeRejectsWrongOffsetAndObjectSize() {
        XCTAssertTrue(DurableDownload.validRange("bytes 2-4/5", offset: 2, total: 5))
        XCTAssertFalse(DurableDownload.validRange("bytes 0-4/5", offset: 2, total: 5))
        XCTAssertFalse(DurableDownload.validRange("bytes 2-4/6", offset: 2, total: 5))
        XCTAssertFalse(DurableDownload.validRange(nil, offset: 0, total: 5))
    }
    func testHubOnlyOffersWholeVerifiableFilesAndPinsRevision() throws {
        let json = #"{"id":"publisher/model","sha":"fixedrevision","siblings":[{"rfilename":"model-Q4.gguf","lfs":{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":10}},{"rfilename":"mmproj.gguf","lfs":{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":10}},{"rfilename":"model-00001-of-00002.gguf","lfs":{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":10}},{"rfilename":"no-hash.gguf"}],"cardData":{"license":"apache-2.0"},"gguf":{"context_length":4096}}"#
        let models = try JSONDecoder().decode(HubModelInfo.self, from: Data(json.utf8)).models()
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.contextLimit, 4096)
        XCTAssertEqual(models.first?.license, "apache-2.0")
        XCTAssertTrue(models.first?.url?.path.contains("resolve/fixedrevision/") == true)
    }
    @MainActor
    func testRestorePreservesLocalDraftWithoutCloudAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false)
        let chat = LocalConversation(title: "Local", modelID: "mini", messages: [.init(role: "assistant", content: "Saved")]); store.save(chat)
        let first = Workspace(store: store); first.open(chat); first.draft = "Unsent"; first.inspector = true
        let state = try JSONDecoder().decode(WorkspaceSnapshot.self, from: JSONEncoder().encode(first.snapshot()))
        let next = Workspace(store: store); await next.restore(state)
        XCTAssertEqual(next.selectedID, chat.id); XCTAssertEqual(next.draft, "Unsent"); XCTAssertTrue(next.inspector); XCTAssertTrue(next.isLocal)
    }
    @MainActor
    func testCloudSnapshotCannotOpenInAnotherAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false); let workspace = Workspace(store: store)
        await workspace.restore(WorkspaceSnapshot(accountID: "someone-else", conversationID: "private", providerID: "cloud", cloudModel: "", draft: "Secret", inspector: true, attachments: []))
        XCTAssertTrue(workspace.draft.isEmpty); XCTAssertNil(workspace.selectedID)
    }
    @MainActor
    func testFailedRegenerationKeepsOriginalAnswerAndUnsentDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false); let workspace = Workspace(store: store)
        workspace.open(LocalConversation(title: "Earlier", modelID: "missing", messages: [.init(role: "user", content: "Question"), .init(role: "assistant", content: "Original answer")]))
        let baseline = workspace.messages; workspace.draft = "Unsent draft"; workspace.retry()
        for _ in 0..<100 { if !workspace.sending { break }; await Task.yield() }
        XCTAssertFalse(workspace.sending); XCTAssertEqual(workspace.messages, baseline); XCTAssertEqual(workspace.draft, "Unsent draft")
    }
    @MainActor
    func testVersionsPersistSelectedAnswer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false); let workspace = Workspace(store: store)
        var message = DesktopMessage(role: "assistant", content: "second")
        message.versions = [.init(content: "first", sources: [], media: nil), .init(content: "second", sources: [], media: nil)]; message.selectedVersion = 1
        workspace.open(LocalConversation(title: "Versions", modelID: "mini", messages: [message])); workspace.selectVersion(messageID: message.id, index: 0)
        let reopened = DesktopStore(root: root, restoreCredentials: false)
        XCTAssertEqual(reopened.localChats.first?.messages.first?.content, "first")
        XCTAssertEqual(reopened.localChats.first?.messages.first?.versions?.count, 2)
    }
    @MainActor
    func testDeletedLocalConversationNeverRestoresDraftIntoCloud() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DesktopStore(root: root, restoreCredentials: false); let workspace = Workspace(store: store)
        await workspace.restore(WorkspaceSnapshot(accountID: nil, conversationID: "deleted", providerID: "mini", cloudModel: "", draft: "Private draft", inspector: false, attachments: []))
        XCTAssertTrue(workspace.isLocal); XCTAssertEqual(workspace.draft, "Private draft")
    }
    func testBrowserQuestionRequiresServerRequestIdentity() throws {
        let valid = #"{"type":"browser_input_requested","task_id":"t","request_id":"r","question":"Continue?","options":["Yes","No"]}"#
        let event = try JSONDecoder().decode(BFFWebSocketEvent.self, from: Data(valid.utf8))
        let question = try XCTUnwrap(BrowserQuestion(event: event, chatID: "c"))
        XCTAssertEqual(question.options, ["Yes", "No"]); XCTAssertEqual(question.id, "r")
        let invalid = #"{"type":"browser_input_requested","task_id":"t","question":"Continue?"}"#
        XCTAssertNil(BrowserQuestion(event: try JSONDecoder().decode(BFFWebSocketEvent.self, from: Data(invalid.utf8)), chatID: "c"))
    }
    @MainActor
    func testResumeSurvivesFreshLibraryAndRangeIgnoredByServer() async throws {
        guard let address = ProcessInfo.processInfo.environment["NIKA_TEST_DOWNLOAD_URL"], let url = URL(string: address) else { throw XCTSkip("HTTP fixture not running") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DesktopModel(id: "resume", name: "Fixture", publisher: "test", parameters: "", quantization: "", bytes: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", url: url, filename: "resume.gguf", repository: "test/fixture")
        do { let original = ModelLibrary(root: root); original.addDiscovered(model); try Data("a".utf8).write(to: original.partialFile(model.id)) }
        let restored = ModelLibrary(root: root)
        XCTAssertEqual(restored.progress[model.id]?.received, 1)
        restored.download(model)
        for _ in 0..<200 { if restored.installed.contains(model.id) || restored.error != nil { break }; try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertNil(restored.error); XCTAssertTrue(restored.installed.contains(model.id)); XCTAssertEqual(try Data(contentsOf: restored.file(model)), Data("abc".utf8))
    }
}
