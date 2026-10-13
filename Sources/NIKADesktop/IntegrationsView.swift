import SwiftUI
import WebKit

struct IntegrationStatus: Decodable {
    struct State: Decodable { let connected_at: String; let status: String? }
    let connected: [String: State]
}
struct IntegrationCapture: Decodable, Identifiable {
    let capture_id: String
    let login_url: String
    let upload_token: String?
    let cookie_domains: [String]
    var id: String { capture_id }
}
struct IntegrationsView: View {
    @ObservedObject var store: DesktopStore
    let signIn: () -> Void
    @State private var status: IntegrationStatus?
    @State private var capture: IntegrationCapture?
    @State private var error: String?
    @State private var busy = false
    // Matches client-api/app/routes/integrations.py INTEGRATION_LOGIN_URLS.
    let services = [("dodo", "Додо Пицца"), ("mac", "Вкусно — и точка"), ("bk", "Бургер Кинг"), ("kfc", "KFC"),
                    ("yandex_eda", "Яндекс Еда"), ("delivery", "Delivery"), ("samokat", "Самокат"), ("kuper", "Купер"),
                    ("wb", "Wildberries"), ("ozon", "Ozon"), ("ya_market", "Яндекс Маркет"), ("ya_taxi", "Яндекс Такси"), ("ya_go", "Яндекс Go"), ("whoosh", "Whoosh")]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Подключения").font(.system(size: 30, weight: .medium, design: .rounded))
            Text("Войдите в сервис, чтобы облачный агент мог действовать с вашего разрешения.").foregroundStyle(.secondary)
            if store.client == nil { Button("Войти в NIKA", action: signIn).buttonStyle(.borderedProminent); Spacer() }
            else {
                if let error { Text(error).foregroundStyle(.red); Button("Повторить") { Task { await refresh() } } }
                if busy { ProgressView() }
                List(services, id: \.0) { slug, title in
                    HStack {
                        Label(title, systemImage: "link"); Spacer()
                        if let connected = status?.connected[slug] {
                            Text(connected.status ?? "Подключено").font(.caption).foregroundStyle(.secondary)
                            Button("Отключить") { Task { await disconnect(slug) } }
                        } else {
                            Button("Подключить") { Task { await connect(slug) } }
                        }
                    }.padding(.vertical, 8).disabled(busy)
                }.listStyle(.inset)
            }
        }.padding(32).task { await refresh() }
            .sheet(item: $capture) { capture in
                if let client = store.client { IntegrationLoginView(capture: capture, api: DesktopAPI(client: client)) { self.capture = nil; Task { await refresh() } } }
            }
    }
    private func refresh() async {
        guard let client = store.client else { return }; busy = true; defer { busy = false }
        do { status = try await DesktopAPI(client: client).request("integrations/status"); error = nil } catch { self.error = error.localizedDescription }
    }
    private func connect(_ slug: String) async {
        guard let client = store.client else { return }; busy = true; defer { busy = false }
        do { capture = try await DesktopAPI(client: client).request("integrations/\(slug)/capture", method: "POST"); error = nil } catch { self.error = error.localizedDescription }
    }
    private func disconnect(_ slug: String) async {
        guard let client = store.client else { return }; busy = true
        do { let _: EmptyResponse = try await DesktopAPI(client: client).request("integrations/\(slug)", method: "DELETE"); await refresh() } catch { self.error = error.localizedDescription }
        busy = false
    }
}

@MainActor
final class IntegrationBrowser: ObservableObject {
    let view: WKWebView
    init() { let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent(); view = WKWebView(frame: .zero, configuration: configuration) }
}
struct IntegrationLoginView: View {
    let capture: IntegrationCapture
    let api: DesktopAPI
    let done: () -> Void
    @StateObject private var browser = IntegrationBrowser()
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        VStack(spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text("Войдите в сервис").font(.headline); Text("После входа нажмите «Разрешить NIKA». Сессия этого сервиса будет передана вашему облачному агенту.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Отмена", action: done) }.padding(18)
            Divider()
            if let url = URL(string: capture.login_url), url.scheme == "https" { IntegrationWebView(view: browser.view, url: url) }
            else { Text("Сервер не вернул безопасный адрес входа.").padding() }
            Divider()
            HStack { if let error { Text(error).font(.caption).foregroundStyle(.red) }; Spacer(); if busy { ProgressView().controlSize(.small) }; Button("Разрешить NIKA") { Task { await finish() } }.buttonStyle(.borderedProminent).disabled(busy) }.padding(18)
        }.frame(width: DesktopFormLayout.width(860), height: DesktopFormLayout.height(680))
    }
    private func finish() async {
        busy = true; defer { busy = false }
        do {
            guard let token = capture.upload_token else { throw DesktopError("Сервер не выдал разрешение на подключение.") }
            let cookies = await browser.view.configuration.websiteDataStore.httpCookieStore.allCookies()
            let allowed = capture.cookie_domains.isEmpty ? [URL(string: capture.login_url)?.host ?? ""] : capture.cookie_domains
            let selected = cookies.filter { cookie in
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                return allowed.contains { !($0.isEmpty) && (domain == $0.lowercased() || domain.hasSuffix("." + $0.lowercased())) }
            }
            guard !selected.isEmpty else { throw DesktopError("Сессия пока не появилась. Завершите вход на странице сервиса.") }
            let values: [BFFJSONValue] = selected.map { cookie in
                var fields: [String: BFFJSONValue] = ["name": .string(cookie.name), "value": .string(cookie.value), "domain": .string(cookie.domain), "path": .string(cookie.path), "secure": .bool(cookie.isSecure), "http_only": .bool(cookie.isHTTPOnly)]
                if let expires = cookie.expiresDate { fields["expires_at"] = .number(expires.timeIntervalSince1970) }
                return .object(fields)
            }
            let _: EmptyResponse = try await api.request("integrations/capture/\(capture.id)/cookies", method: "POST", body: ["upload_token": .string(token), "cookies": .array(values)])
            let _: EmptyResponse = try await api.request("integrations/capture/\(capture.id)/complete", method: "POST", body: [:])
            done()
        } catch { self.error = error.localizedDescription }
    }
}
struct IntegrationWebView: NSViewRepresentable {
    let view: WKWebView; let url: URL
    func makeNSView(context: Context) -> WKWebView { view.load(URLRequest(url: url)); return view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
