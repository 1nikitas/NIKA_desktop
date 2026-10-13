import SwiftUI

struct ProviderSettingsView: View {
    @ObservedObject var store: DesktopStore
    @State private var quota: BFFQuota?
    @State private var key = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    var body: some View {
        Form {
            if store.client == nil { Text("Войдите в NIKA в основных настройках.") }
            else {
                Section("Использование NIKA Cloud") {
                    if let quota {
                        if quota.enabled {
                            LabeledContent("Запросы", value: "\(quota.requestsUsed) / \(quota.requestsLimit)")
                            LabeledContent("Токены", value: "\(quota.tokensUsed) / \(quota.tokensLimit)")
                            if let date = quota.periodEndsAt { LabeledContent("Обновление лимита", value: date.formatted()) }
                        } else { Text("Ограничение квоты отключено сервером.") }
                        Label(quota.hasOpenRouterKey ? "Личный ключ подключён" : "Используется доступ NIKA", systemImage: "key")
                    } else if busy { ProgressView() }
                    Button("Обновить") { Task { await refresh() } }
                }
                Section("Свой ключ OpenRouter") {
                    Text("Ключ отправляется в ваш аккаунт NIKA для облачных запросов. Локальные модели его не используют.").font(.caption).foregroundStyle(.secondary)
                    SecureField("API key", text: $key)
                    HStack {
                        Button("Проверить и сохранить") { Task {
                            guard let client = store.client else { return }; busy = true; error = nil; notice = nil
                            defer { busy = false }
                            do { let result = try await client.setOpenRouterKey(key.trimmingCharacters(in: .whitespacesAndNewlines)); guard result.valid else { throw DesktopError(result.error ?? "Ключ не принят") }; key = ""; notice = "Ключ подключён"; await refresh() }
                            catch { self.error = error.localizedDescription }
                        } }.disabled(key.isEmpty || busy)
                        if quota?.hasOpenRouterKey == true { Button("Отключить ключ", role: .destructive) { Task {
                            do { try await store.client?.deleteOpenRouterKey(); notice = "Ключ отключён"; await refresh() } catch { self.error = error.localizedDescription }
                        } }.disabled(busy) }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let notice { Text(notice).foregroundStyle(.secondary) }
        }.formStyle(.grouped).task { await refresh() }
    }
    private func refresh() async {
        guard let client = store.client else { return }; busy = true; defer { busy = false }
        do { quota = try await client.quota(); error = nil } catch { self.error = error.localizedDescription }
    }
}
