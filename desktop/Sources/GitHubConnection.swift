import Foundation
import Security

enum GitHubAuthenticationError: LocalizedError {
    case reconnect
    var errorDescription: String? { "Your GitHub connection expired or was revoked. Connect GitHub again; cached definitions are still available." }
}

struct GitHubSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let refreshExpiresAt: Date?

    init(grant: AccessGrant, now: Date = Date()) throws {
        guard let token = grant.access_token, !token.isEmpty else {
            throw SemanticError("GitHub could not renew the connection. Try again later.")
        }
        accessToken = token
        refreshToken = grant.refresh_token
        expiresAt = grant.expires_in.map { now.addingTimeInterval(TimeInterval($0)) }
        refreshExpiresAt = grant.refresh_token_expires_in.map { now.addingTimeInterval(TimeInterval($0)) }
    }
}

protocol GitHubSessionStore {
    func read(clientID: String) throws -> GitHubSession?
    func write(_ session: GitHubSession, clientID: String) throws
    func delete(clientID: String) throws
}

struct KeychainGitHubSessionStore: GitHubSessionStore {
    private func query(_ clientID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.semantic.desktop.github-session-v1",
         kSecAttrAccount as String: clientID]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw SemanticError("Could not access the saved GitHub connection in Keychain (\(status)).")
        }
    }
    func read(clientID: String) throws -> GitHubSession? {
        var attributes = query(clientID)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw SemanticError("Could not read the saved GitHub connection.") }
        return try JSONDecoder().decode(GitHubSession.self, from: data)
    }
    func write(_ session: GitHubSession, clientID: String) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query(clientID) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(clientID)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(attributes as CFDictionary, nil))
        } else { try check(status) }
    }
    func delete(clientID: String) throws {
        let status = SecItemDelete(query(clientID) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}

@MainActor final class GitHubConnection {
    private let store: GitHubSessionStore
    private(set) var session: GitHubSession?
    private var needsSave = false
    init(store: GitHubSessionStore = KeychainGitHubSessionStore()) { self.store = store }
    func restore(clientID: String) throws { session = try store.read(clientID: clientID); needsSave = false }
    func save(_ session: GitHubSession, clientID: String) throws {
        self.session = session
        needsSave = true
        try store.write(session, clientID: clientID)
        needsSave = false
    }
    func disconnect(clientID: String) throws {
        try store.delete(clientID: clientID)
        session = nil
        needsSave = false
    }
    func accessToken(clientID: String, client: GitHubClient = GitHubClient(), now: Date = Date()) async throws -> String {
        guard let session else { throw GitHubAuthenticationError.reconnect }
        if let expiry = session.expiresAt, expiry <= now.addingTimeInterval(60) {
            guard let refresh = session.refreshToken,
                  session.refreshExpiresAt.map({ $0 > now }) ?? true else { throw GitHubAuthenticationError.reconnect }
            let renewed = try await client.refreshSession(clientID: clientID, refreshToken: refresh)
            // Persist rotated credentials even if the caller was just cancelled.
            try save(renewed, clientID: clientID)
            try Task.checkCancellation()
            return renewed.accessToken
        }
        if needsSave { try save(session, clientID: clientID) }
        return session.accessToken
    }
}
