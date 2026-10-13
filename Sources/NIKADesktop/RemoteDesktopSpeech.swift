import SwiftUI
import AVFoundation
import CFNetwork

struct DesktopSpeechKeys: Codable {
    var key = ""
    var voiceID = ""
    var proxy = ""
    static func read() throws -> Self {
        guard let data = try Vault.read(account: "elevenlabs") else { return .init() }
        return try JSONDecoder().decode(Self.self, from: data)
    }
    func save() throws { try Vault.write(try JSONEncoder().encode(self), account: "elevenlabs") }
    func request(_ text: String) throws -> URLRequest {
        guard !key.isEmpty, !voiceID.isEmpty, voiceID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw DesktopError("Укажите ключ и Voice ID ElevenLabs в настройках голоса.") }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream?output_format=mp3_22050_32")!)
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue(key, forHTTPHeaderField: "xi-api-key"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "model_id": "eleven_flash_v2_5", "language_code": "ru", "voice_settings": ["stability": 0.75, "similarity_boost": 0.75]])
        return request
    }
    func configuration() throws -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        if !proxy.isEmpty {
            guard let components = URLComponents(string: proxy.contains("://") ? proxy : "http://" + proxy), components.scheme == "http", let host = components.host, let port = components.port, (1...65535).contains(port), components.user == nil, components.password == nil else { throw DesktopError("Прокси: укажите host:port без логина и пароля.") }
            configuration.connectionProxyDictionary = [kCFNetworkProxiesHTTPEnable as String: 1, kCFNetworkProxiesHTTPProxy as String: host, kCFNetworkProxiesHTTPPort as String: port, kCFNetworkProxiesHTTPSEnable as String: 1, kCFNetworkProxiesHTTPSProxy as String: host, kCFNetworkProxiesHTTPSPort as String: port]
        }
        return configuration
    }
}
final class SpeechRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
}
struct RemoteSpeechSettings: View {
    @AppStorage("speechProvider") private var provider = "apple"
    @State private var keys = DesktopSpeechKeys()
    @State private var status: String?
    var body: some View {
        Section("Озвучивание ответа") {
            Picker("Провайдер", selection: $provider) { Text("Apple · на Mac").tag("apple"); Text("ElevenLabs · облако").tag("elevenlabs") }
            if provider == "elevenlabs" {
                Text("Текст облачных ответов будет отправляться в ElevenLabs. Локальные ответы всегда озвучиваются на Mac.").font(.caption).foregroundStyle(.secondary)
                SecureField("API key", text: $keys.key)
                TextField("Voice ID", text: $keys.voiceID)
                TextField("HTTP-прокси host:port (необязательно)", text: $keys.proxy)
                HStack {
                    Button("Сохранить в Keychain") { do { _ = try keys.request("Проверка"); _ = try keys.configuration(); try keys.save(); status = "Настройки сохранены" } catch { status = error.localizedDescription } }
                    Button("Удалить ключ", role: .destructive) { do { try Vault.write(nil, account: "elevenlabs"); keys = .init(); provider = "apple" } catch { status = error.localizedDescription } }
                }
                if let status { Text(status).font(.caption) }
            }
        }.task { do { keys = try await Task.detached { try DesktopSpeechKeys.read() }.value } catch { status = error.localizedDescription } }
    }
}
