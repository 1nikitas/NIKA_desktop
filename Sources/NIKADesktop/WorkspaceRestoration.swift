import Foundation

struct WorkspaceSnapshot: Codable, Equatable {
    var accountID: String?
    var conversationID: String?
    var providerID: String
    var cloudModel: String
    var draft: String
    var inspector: Bool
    var attachments: [Data]
}
extension Workspace {
    func snapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(accountID: isLocal ? nil : store.login?.session.clientID, conversationID: selectedID,
                          providerID: providerID, cloudModel: cloudModel, draft: draft, inspector: inspector,
                          attachments: attachments.compactMap { try? $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) })
    }
    func restore(_ state: WorkspaceSnapshot) async {
        guard !sending, messages.isEmpty, draft.isEmpty else { return }
        guard state.providerID != "cloud" || state.accountID == store.login?.session.clientID else { return }
        newChat(provider: state.providerID)
        if let id = state.conversationID {
            if state.providerID != "cloud", let chat = store.localChats.first(where: { $0.id == id }) { open(chat) }
            else if state.providerID == "cloud", let client = store.client {
                do { let info = try await client.fetchChatInfo(id: id); guard messages.isEmpty, draft.isEmpty, providerID == state.providerID else { return }; await open(info); guard selectedID == id, providerID == "cloud" else { return } } catch { self.error = error.localizedDescription }
            }
        } else { newChat(provider: state.providerID) }
        draft = state.draft; cloudModel = state.cloudModel; inspector = state.inspector
        attachments = state.attachments.compactMap { data in var stale = false; return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) }
    }
}
