import Foundation

final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
@main struct Tests {
    static func check(_ value: Bool, _ message: String) throws { if !value { throw SemanticError("FAIL: " + message) } }
    static func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    static func main() async throws {
        let tokens = TokenParser.parse("""
        /* --fake: red; .fake {} */
        :root { --border-default: #e2e8f0; --radius-md: 8px; --spacing-sm: 4px; }
        .button-primary:hover, .card { background: url(asset.png); opacity: 0.5; }
        """, source: "tokens.css")
        try check(Set(tokens.map(\.name)) == Set(["--border-default", "--radius-md", "--spacing-sm", ".button-primary", ".card"]), "Extract real definitions and ignore comments/declaration fragments")
        try check(tokens.first { $0.name == "--border-default" }?.kind == "Color", "Color classification")
        try check(tokens.first { $0.name == "--radius-md" }?.kind == "Radius", "Radius classification")
        let jsonTokens = TokenParser.parse(#"{"color":{"$type":"color","border":{"$value":"{palette.gray.200}"}},"space":{"small":{"value":4,"type":"dimension"}}}"#, source: "design.tokens.json")
        try check(jsonTokens.map(\.name) == ["color.border", "space.small"], "Nested token JSON")
        try check(jsonTokens.first?.value == "{palette.gray.200}" && jsonTokens.first?.kind == "Color", "Preserve aliases and inherit token type")
        try check(TokenParser.parse("invalid", source: "tokens.json").isEmpty, "Malformed JSON is ignored")
        try check(!TokenParser.eligible("node_modules/system/tokens.css") && !TokenParser.eligible("dist/styles.css") && !TokenParser.eligible("package.json"), "Exclude generated and unrelated files")
        try check(TokenParser.eligible("src/theme.json") && TokenParser.eligible("src/styles.scss"), "Include themes and styles")
        let unsafe = TokenParser.parse(#"{"danger\nsubmit":{"$value":"red"},"safe":{"$value":"green"}}"#, source: "tokens.json")
        try check(unsafe.count == 1 && unsafe.first?.name == "safe", "Never insert control characters from repository token names")
        let duplicates = TokenParser.parse(":root { --a: red; --a: blue; }", source: "light.css") + TokenParser.parse(":root { --a: black; }", source: "dark.css")
        try check(TokenParser.unique(duplicates).count == 2, "Preserve theme source variants")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        let client = GitHubClient(token: "test-token", session: URLSession(configuration: configuration))
        MockProtocol.handler = { request in
            try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "Bearer authorization")
            if request.url!.path == "/user/repos" { return (200, try data([["id": 1, "full_name": "test/system", "default_branch": "main", "private": true]])) }
            throw SemanticError("Unexpected request")
        }
        let repos = try await client.repositories()
        try check(repos.count == 1 && repos[0].full_name == "test/system", "List authenticated repositories directly")
        MockProtocol.handler = { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
            let rows: [[String: Any]] = page == "1" ? (1...100).map { ["id": $0, "full_name": "test/repo-\($0)", "default_branch": "main", "private": false] } : [["id": 101, "full_name": "test/last-page", "default_branch": "main", "private": true]]
            return (200, try data(rows))
        }
        let paged = try await client.repositories()
        try check(paged.count == 101 && paged.contains { $0.id == 101 }, "Load repositories beyond the first page")
        MockProtocol.handler = { _ in (200, try data([])) }
        let empty = try await client.repositories()
        try check(empty.isEmpty, "Empty access list is preserved without fabricated repositories")
        MockProtocol.handler = { request in
            if request.url!.path.contains("/commits/") { return (200, try data(["sha": "revision"])) }
            try check(request.url!.path == "/repos/test/system/contents/src/styles/theme.css", "Fetch selected file directly, never a repository tree")
            try check(request.url!.query == "ref=revision", "Read files at a pinned commit")
            return (200, try data(["type": "file", "size": 40, "encoding": "base64", "content": Data(":root { --border-default: #eeeeee; }".utf8).base64EncodedString()]))
        }
        let index = try await client.index(repos[0], paths: ["src/styles/theme.css"], progress: { _ in })
        try check(index.tokens.first?.name == "--border-default" && index.revision == "revision" && index.sourceFiles == ["src/styles/theme.css"], "Direct file indexing and persisted selection")
        let normalized = try GitHubClient.filePaths([" src/styles/theme.css ", "", "src/styles/theme.css", "design tokens.json"])
        try check(normalized == ["src/styles/theme.css", "design tokens.json"], "Normalize and deduplicate file paths")
        for invalid in ["../tokens.css", "/tokens.css", "https://github.com/test/tokens.css", "src/", "theme.ts"] {
            do { _ = try GitHubClient.filePaths([invalid]); throw SemanticError("FAIL: invalid path accepted") }
            catch { try check(!error.localizedDescription.hasPrefix("FAIL:"), "Reject invalid token paths") }
        }
        MockProtocol.handler = { request in
            if request.url!.path.contains("/commits/") { return (200, try data(["sha": "revision"])) }
            return (404, Data())
        }
        do { _ = try await client.index(repos[0], paths: ["missing.css"], progress: { _ in }); throw SemanticError("FAIL: missing file accepted") }
        catch { try check(error.localizedDescription.contains("missing.css") && error.localizedDescription.contains("could not find"), "Actionable missing file error") }
        MockProtocol.handler = { request in
            if request.url!.path.contains("/commits/") { return (200, try data(["sha": "revision"])) }
            return (200, try data(["type": "file", "size": 2_000_000]))
        }
        do { _ = try await client.index(repos[0], paths: ["large.css"], progress: { _ in }); throw SemanticError("FAIL: oversized file accepted") }
        catch { try check(error.localizedDescription.contains("1 MB"), "Reject oversized files") }
        // Old caches without a file selection must still open after upgrading.
        let old = try data(["repository": ["id": 1, "full_name": "test/system", "default_branch": "main", "private": true], "tokens": [], "syncedAt": 0, "revision": "old"])
        let legacy = try JSONDecoder().decode(TokenIndex.self, from: old)
        try check(legacy.sourceFiles == nil, "Backward-compatible token cache")
        MockProtocol.handler = { _ in (401, Data()) }
        do { let _: GitHubUser = try await client.request("/user"); throw SemanticError("FAIL: expired credentials accepted") }
        catch { try check(error.localizedDescription.contains("expired"), "Actionable expired-session error") }
        MockProtocol.handler = { request in
            try check(request.url!.host == "github.com" && request.httpMethod == "POST", "Device flow request targets GitHub")
            try check(request.value(forHTTPHeaderField: "Authorization") == nil, "Do not send account token in device-code request")
            return (200, try data(["device_code":"secret-test", "user_code":"TEST-CODE", "verification_uri":"https://github.com/login/device", "expires_in":900, "interval":5]))
        }
        let device = try await client.beginLogin(clientID: "Iv1.example")
        try check(device.user_code == "TEST-CODE", "Device flow response decoding")
        print("PASS: parser, theme variants, exclusions, repository pagination, direct-file indexing, path validation, missing/large files, cache migration, expired auth, and device-flow contract")
    }
}
