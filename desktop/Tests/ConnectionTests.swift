import Foundation

private final class MemorySessionStore: GitHubSessionStore {
    var values: [String: GitHubSession] = [:]
    var rejectWrites = false
    func read(clientID: String) throws -> GitHubSession? { values[clientID] }
    func write(_ session: GitHubSession, clientID: String) throws {
        if rejectWrites { throw SemanticError("Keychain unavailable") }
        values[clientID] = session
    }
    func delete(clientID: String) throws { values[clientID] = nil }
}

@MainActor func testPersistentGitHubConnection() async throws {
    func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
    func session(_ value: [String: Any], now: Date = Date()) throws -> GitHubSession {
        try GitHubSession(grant: JSONDecoder().decode(AccessGrant.self, from: data(value)), now: now)
    }
    let store = MemorySessionStore()
    let connection = GitHubConnection(store: store)
    let now = Date()
    try connection.save(session(["access_token": "old", "expires_in": 0, "refresh_token": "refresh", "refresh_token_expires_in": 3600], now: now), clientID: "test")
    let restored = GitHubConnection(store: store)
    try restored.restore(clientID: "test")
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ColorCacheProtocol.self]
    let transport = URLSession(configuration: config)
    let client = GitHubClient(session: transport)
    var renewals = 0
    ColorCacheProtocol.handler = { request in
        precondition(request.url?.absoluteString == "https://github.com/login/oauth/access_token")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        // URLSession can provide the form body as a stream to URLProtocol.
        let stream = request.httpBodyStream
        stream?.open()
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = stream?.read(&bytes, maxLength: bytes.count) ?? 0
        stream?.close()
        let body = request.httpBody ?? Data(bytes.prefix(max(0, count)))
        let form = String(decoding: body, as: UTF8.self)
        precondition(form.contains("grant_type=refresh_token") && form.contains("refresh_token=refresh") && !form.contains("client_secret"))
        renewals += 1
        return (200, data(["access_token": "new", "expires_in": 28800, "refresh_token": "rotated", "refresh_token_expires_in": 15897600]))
    }
    let token = try await restored.accessToken(clientID: "test", client: client, now: now)
    precondition(token == "new" && renewals == 1 && store.values["test"]?.refreshToken == "rotated")
    _ = try await restored.accessToken(clientID: "test", client: client, now: now)
    precondition(renewals == 1)
    let otherApp = GitHubConnection(store: store)
    try otherApp.restore(clientID: "different")
    precondition(otherApp.session == nil)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = directory.appendingPathComponent("tokens.json")
    let repo = Repository(id: 777, full_name: "test/private-design", default_branch: "main", private: true)
    var original = TokenIndex(repository: repo, tokens: TokenParser.parse(":root { --accent: red; }", source: "theme.css"), syncedAt: now, revision: "old")
    original.sourceFiles = ["theme.css"]
    original.pickerTabs = [PickerTab(title: "Theme", path: "theme.css")]
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode([original]).write(to: cache)
    let model = AppModel(info: ["SemanticGitHubClientID": "test", "SemanticGitHubAppSlug": "test-app"], cacheURL: cache, connection: GitHubConnection(store: store))
    model.githubSession = transport
    model.screen = "preferences"
    ColorCacheProtocol.handler = { request in
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer new")
        switch request.url!.path {
        case "/user": return (200, data(["login": "test-user"]))
        case "/user/repos": return (200, data([["id": 777, "full_name": repo.full_name, "default_branch": "main", "private": true]]))
        case let path where path.contains("/commits/"): return (200, data(["sha": "new-revision"]))
        default:
            let css = ":root { --accent: blue; }"
            return (200, data(["type": "file", "size": css.utf8.count, "encoding": "base64", "content": Data(css.utf8).base64EncodedString()]))
        }
    }
    func settle() async throws {
        for _ in 0..<1000 {
            if !model.busy { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        preconditionFailure("Connection test timed out")
    }
    model.startGitHubConnection()
    try await settle()
    precondition(model.account == "test-user" && model.activeIndex?.revision == "new-revision")
    precondition(model.tokens.first?.value == "blue" && model.activeIndex?.pickerTabs == original.pickerTabs)
    precondition(model.screen == "preferences")
    let saved = try Data(contentsOf: cache)
    precondition(!String(decoding: saved, as: UTF8.self).contains("rotated"))
    ColorCacheProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    model.automaticallySync()
    try await settle()
    precondition(model.account == "test-user" && store.values["test"] != nil && model.tokens.first?.value == "blue")
    let offlineCache = try Data(contentsOf: cache)
    precondition(offlineCache == saved)
    ColorCacheProtocol.handler = { _ in (401, data(["message": "Bad credentials"])) }
    model.automaticallySync()
    try await settle()
    precondition(model.account == nil && store.values["test"] == nil && model.tokens.first?.value == "blue")
    precondition(model.error?.contains("Connect GitHub again") == true)
    try connection.save(session(["access_token": "logout-test"]), clientID: "test")
    model.disconnect()
    precondition(store.values["test"] == nil && model.indices.isEmpty && !FileManager.default.fileExists(atPath: cache.path))
    model.stopGitHubConnection()

    try restored.save(session(["access_token": "expired", "expires_in": 0, "refresh_token": "expired-refresh", "refresh_token_expires_in": -1]), clientID: "test")
    do { _ = try await restored.accessToken(clientID: "test", client: client); preconditionFailure("Expired refresh must reconnect") }
    catch is GitHubAuthenticationError { }
    try restored.save(session(["access_token": "expired", "expires_in": 0, "refresh_token": "refresh", "refresh_token_expires_in": 3600]), clientID: "test")
    ColorCacheProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    do { _ = try await restored.accessToken(clientID: "test", client: client); preconditionFailure("Offline refresh must fail") }
    catch { precondition(store.values["test"]?.refreshToken == "refresh") }
    ColorCacheProtocol.handler = { _ in (200, data(["error": "bad_refresh_token"])) }
    do { _ = try await restored.accessToken(clientID: "test", client: client); preconditionFailure("Revoked refresh must reconnect") }
    catch is GitHubAuthenticationError { }
    ColorCacheProtocol.handler = { _ in (200, data(["access_token": "after-rotation", "expires_in": 28800, "refresh_token": "after-rotation-refresh"])) }
    store.rejectWrites = true
    do { _ = try await restored.accessToken(clientID: "test", client: client); preconditionFailure("Keychain failures must surface") }
    catch { precondition(restored.session?.refreshToken == "after-rotation-refresh") }
    store.rejectWrites = false
    let retried = try await restored.accessToken(clientID: "test", client: client)
    precondition(retried == "after-rotation" && store.values["test"]?.refreshToken == "after-rotation-refresh")
    print("Persistent connection, refresh rotation, automatic private-project sync, offline cache, revoked access, and disconnect tests passed")
}
