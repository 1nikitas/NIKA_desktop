import XCTest
import AppKit
@testable import NIKADesktop

final class PersonalBotsTests: XCTestCase {
    static let fixture = #"{"id":"bot-1","title":"Учитель","created_at":"2026-10-12","updated_at":"2026-10-12","is_individual_agent":true,"personality":{"name":"Мой учитель","avatar":"kruglaya","instructions":"Объясняй коротко","instructions_label":"Учитель","preset":{"id":"teacher","name":"Учитель"},"role":null}}"#
    func testBotKeepsChatIdentityAndEditorPreset() throws {
        let bot = try JSONDecoder().decode(PersonalBot.self, from: Data(Self.fixture.utf8))
        XCTAssertEqual(bot.chat.id, "bot-1"); XCTAssertEqual(bot.name, "Мой учитель")
        let draft = BotDraft(bot)
        XCTAssertEqual(draft.body["preset_id"], .string("teacher"))
        XCTAssertEqual(draft.body["instructions"], .string("Объясняй коротко"))
        XCTAssertEqual(draft.body["role_id"], .null)
        XCTAssertNil(draft.body["system_prompt"], "Server owns the actual personality prompt")
    }
    func testCustomEditorClearsPresetExplicitlyAndValidatesLimits() throws {
        var draft = BotDraft(try JSONDecoder().decode(PersonalBot.self, from: Data(Self.fixture.utf8)))
        draft.presetID = ""; XCTAssertEqual(draft.body["preset_id"], .null)
        draft.name = "  "; XCTAssertFalse(draft.valid)
        draft.name = "Мой бот"; draft.instructions = String(repeating: "я", count: 8001); XCTAssertFalse(draft.valid)
        draft.instructions = "Помогай"; XCTAssertTrue(draft.valid)
        draft.avatar = "custom"; draft.image = "data:image/png;base64,abc"
        XCTAssertEqual(draft.body["avatar_image"], .string(draft.image))
        draft.avatar = "nika"; XCTAssertNil(draft.body["avatar_image"])
    }
    func testMaterialFilesWithoutDownloadIDAndUnsafeLinks() throws {
        let data = Data(#"{"files":[{"file_id":null,"filename":"Notes.pdf","mime_type":"application/pdf","message_id":"m"}],"links":[{"url":"javascript:alert(1)","title":"x","domain":"x"}]}"#.utf8)
        let result = try JSONDecoder().decode(BotMaterials.self, from: data)
        XCTAssertNil(result.files[0].file_id); XCTAssertNil(result.links[0].safeURL)
    }
    func testAuthenticatedCRUDMatchesAPIAnd204Decodes() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BotHTTPFixture.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let client = try BFFClient(baseURL: "https://bots.test", initialTokens: .init(accessToken: "test-access", refreshToken: ""))
        let api = DesktopAPI(client: client, session: session)
        let list: [PersonalBot] = try await api.request("personal-agents")
        XCTAssertEqual(list.first?.id, "bot-1")
        let created: PersonalBot = try await api.request("personal-agents", method: "POST", body: BotDraft().body)
        XCTAssertEqual(created.id, "bot-1")
        var draft = BotDraft(created); draft.name = "Новое имя"
        let updated: PersonalBot = try await api.request("personal-agents/bot-1", method: "PATCH", body: draft.body)
        XCTAssertEqual(updated.id, "bot-1")
        let _: EmptyResponse = try await api.request("personal-agents/bot-1", method: "DELETE")
        do { let _: EmptyResponse = try await api.request("personal-agents/failure"); XCTFail("Must report backend failures") }
        catch { XCTAssertTrue(error.localizedDescription.contains("503")) }
    }
}
private final class BotHTTPFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "bots.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
        let path = request.url!.path
        XCTAssertTrue(path.hasPrefix("/api/personal-agents"))
        let status = path.hasSuffix("failure") ? 503 : request.httpMethod == "DELETE" ? 204 : request.httpMethod == "POST" ? 201 : 200
        let payload = status == 204 ? "" : status == 503 ? "Unavailable" : request.httpMethod == "GET" ? "[\(PersonalBotsTests.fixture)]" : PersonalBotsTests.fixture
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
