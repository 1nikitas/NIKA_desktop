import SwiftUI
import AuthenticationServices

struct AppleSignIn: View {
    @ObservedObject var store: DesktopStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        SignInWithAppleButton(.signIn) { request in request.requestedScopes = [.fullName, .email] } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                    store.error = "Apple не вернула токен входа."; return
                }
                Task { await store.apple(token: token, name: credential.fullName) }
            case .failure(let error):
                if (error as NSError).code != ASAuthorizationError.canceled.rawValue { store.error = "Вход Apple недоступен: \(error.localizedDescription)" }
            }
        }.signInWithAppleButtonStyle(scheme == .dark ? .white : .black).frame(height: 36).disabled(store.busy)
    }
}
