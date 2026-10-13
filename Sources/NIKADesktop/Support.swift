import Foundation
import SwiftUI
import Security
import LocalAuthentication

func L(_ text: String) -> String { text }
func LF(_ text: String, _ args: CVarArg...) -> String { String(format: text, arguments: args) }
struct DesktopError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Vault {
    static let service = "com.nika.desktop.session"
    static func read(account: String = "session") throws -> Data? {
        var query = base; query[kSecAttrAccount as String] = account
        let context = LAContext(); context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DesktopError("Keychain: \(status)") }
        return result as? Data
    }
    static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "session"]
    }
    static func write(_ data: Data?, account: String = "session") throws {
        var base = Self.base; base[kSecAttrAccount as String] = account
        guard let data else {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw DesktopError("Keychain: \(status)") }
            return
        }
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = base
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw DesktopError("Keychain: \(added)") }
        } else if status != errSecSuccess { throw DesktopError("Keychain: \(status)") }
    }
}

enum DesktopStyle {
    static let readingWidth: CGFloat = 760
    static let pageInset: CGFloat = 32
    static let composerRadius: CGFloat = 20
    static let panelRadius: CGFloat = 14
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
}

struct EmptyWorkspace: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 26, weight: .semibold, design: .rounded))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 410)
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
func L(_ text: String, _ args: CVarArg...) -> String { String(format: text, arguments: args) }
enum ChatAttachmentKind: String { case file, video, roundVideo = "round_video" }
