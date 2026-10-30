import Foundation
import CoreGraphics

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
        let menuSize = CGSize(width: 420, height: 630)
        for visible in [CGRect(x: 0, y: 90, width: 1920, height: 960), CGRect(x: -1512, y: 55, width: 1512, height: 950), CGRect(x: 0, y: 1080, width: 1920, height: 1050)] {
            let anchor = CGRect(x: visible.maxX - 80, y: visible.maxY, width: 22, height: 30)
            let frame = StatusMenuPlacement.frame(anchor: anchor, visible: visible, size: menuSize)!
            try check(visible.contains(frame) && frame.maxY < anchor.minY, "Keep status menu below its anchor on left/stacked displays")
        }
        try check(!StatusMenuPlacement.validAnchor(.zero, screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), barHeight: 30), "Reject uninitialized status button geometry")
        try check(!StatusMenuPlacement.validAnchor(CGRect(x: 0, y: 0, width: 22, height: 30), screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), barHeight: 30), "Never anchor the menu at bottom left")
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
        try check(index.tokens.first?.name == "--border-default" && index.revision == "revision"
                  && index.sourceFiles == ["src/styles/theme.css"], "Direct file indexing and persisted selection")
        MockProtocol.handler = { request in
            switch request.url!.path {
            case let path where path.contains("/commits/"):
                return (200, try data(["sha": "revision"]))
            case "/repos/test/system/contents/src/styles/theme.css":
                let theme = ":root { --background-color-cui-danger: var(\n --color-cui-red-10\n ); }"
                return (200, try data(["type": "file", "size": theme.utf8.count, "encoding": "base64", "content": Data(theme.utf8).base64EncodedString()] as [String: Any]))
            case "/repos/test/system/contents/src/styles":
                return (200, try data([["name": "theme.css", "type": "file", "size": 100], ["name": "variables.css", "type": "file", "size": 100]]))
            case "/repos/test/system/contents/src/styles/variables.css":
                let scales = ":root { --color-cui-red-10: #dc3b5d; } [data-theme=dark] { --color-cui-red-10: #ec5a72; }"
                return (200, try data(["type": "file", "size": scales.utf8.count, "encoding": "base64", "content": Data(scales.utf8).base64EncodedString()] as [String: Any]))
            default: throw SemanticError("Unexpected color scale request")
            }
        }
        let semanticIndex = try await client.index(repos[0], paths: ["src/styles/theme.css"], progress: { _ in })
        try check(semanticIndex.tokens.count == 1 && semanticIndex.referenceTokens?.first?.value == "#ec5a72"
                  && semanticIndex.colorReferencesScanned == true
                  && semanticIndex.sourceFiles == ["src/styles/theme.css"], "Resolve adjacent scales without exposing them as picker entries")
        MockProtocol.handler = { request in
            let path = request.url!.path
            if path.contains("/commits/") { return (200, try data(["sha": "revision"])) }
            if path.hasSuffix("/theme.css") {
                let theme = ":root { --color-danger: var(--brand-danger); }"
                return (200, try data(["type": "file", "size": theme.utf8.count, "encoding": "base64", "content": Data(theme.utf8).base64EncodedString()] as [String: Any]))
            }
            if path.hasSuffix("/a") || path.hasSuffix("/b") {
                return (200, try data([["name": "theme.css", "type": "file", "size": 100], ["name": "colors-base.css", "type": "file", "size": 100], ["name": "scales.css", "type": "file", "size": 100]]))
            }
            let hex = path.contains("/a/") ? "#111111" : "#222222"
            let content = path.hasSuffix("/colors-base.css") ? ":root { --raw-danger: \(hex); }" : ":root { --brand-danger: var(--raw-danger); }"
            return (200, try data(["type": "file", "size": content.utf8.count, "encoding": "base64", "content": Data(content.utf8).base64EncodedString()] as [String: Any]))
        }
        let separate = try await client.index(repos[0], paths: ["a/theme.css", "b/theme.css"], progress: { _ in })
        try check(separate.referenceTokens?.filter { $0.name == "--raw-danger" }.map(\.value).sorted() == ["#111111", "#222222"]
                  && separate.referenceTokens?.filter { $0.name == "--brand-danger" }.count == 2,
                  "Resolve alias chains and same-name scales separately for each selected folder")
        MockProtocol.handler = { request in
            switch request.url!.path {
            case let path where path.contains("/commits/"):
                return (200, try data(["sha": "revision"]))
            case "/repos/test/system/contents/src/styles/theme.css":
                let theme = ":root { --color-danger: var(--red-10); }"
                return (200, try data(["type": "file", "size": theme.utf8.count, "encoding": "base64", "content": Data(theme.utf8).base64EncodedString()] as [String: Any]))
            default: return (429, try data(["message": "API rate limit exceeded"]))
            }
        }
        do {
            _ = try await client.index(repos[0], paths: ["src/styles/theme.css"], progress: { _ in })
            throw SemanticError("Expected color directory error")
        } catch {
            try check(error.localizedDescription.contains("Could not inspect nearby color files"), "Surface nearby palette fetch failures")
        }
        let normalized = try GitHubClient.filePaths([" src/styles/theme.css ", "", "src/styles/theme.css", "design tokens.json"])
        try check(normalized == ["src/styles/theme.css", "design tokens.json"], "Normalize and deduplicate file paths")
        let svgSources = IconArtwork.fromSources(semantic: #"createSemanticIcon("UserIcon", UserRound); createSemanticIcon("StarFilledIcon", Star, true); createSemanticIcon("HelpIcon", CircleHelp)"#,
            providers: #"const SERVICE_PATH = "M0 0h24v24H0z"; createProviderIcon("ServiceIcon", SERVICE_PATH); createProviderOutlineIcon("ServiceOutlineIcon", SERVICE_PATH)"#)
        try check(svgSources.count == 5 && svgSources["StarFilledIcon"]!.contains("fill=\"white\""), "Real vector paths, aliases, and filled variants")
        try check(svgSources["ServiceOutlineIcon"]!.contains("stroke-width=\"1.5\""), "Provider outline geometry")
        let hostile = IconArtwork.fromSources(semantic: "", providers: #"const BAD_PATH = "<script>alert(1)</script>"; createProviderIcon("BadIcon", BAD_PATH)"#)
        try check(hostile.isEmpty, "Reject non-path markup in provider geometry")
        let illustrated = DesignToken(name: "UserIcon", value: "React icon", kind: "Icon", source: "icons.tsx", iconSVG: svgSources["UserIcon"])
        let decodedIcon = try JSONDecoder().decode(DesignToken.self, from: JSONEncoder().encode(illustrated))
        try check(decodedIcon.iconSVG == illustrated.iconSVG, "Artwork persists in the token cache")
        let iconExports = """
        // export const FakeIcon = nope
        export const SearchIcon = createIcon()
        export const StarFilledIcon = createIcon()
        export interface PropsIcon {}
        export { SearchIcon as FindIcon }
        """
        try check(IconCatalog.exports(iconExports) == ["FindIcon", "SearchIcon", "StarFilledIcon"], "Read icon exports and aliases without comments or types")
        try check(TokenParser.parse(iconExports, source: "icons.tsx").allSatisfy { $0.kind == "Icon" }, "TypeScript icon classification")
        let linked = try GitHubClient.filePaths(["https://github.com/test/system/blob/main/src/icons.tsx#L2"], repository: repos[0])
        try check(linked == ["src/icons.tsx"], "Accept active repository GitHub file links")
        for link in ["https://github.com/other/system/blob/main/src/icons.tsx", "https://github.com/test/system/blob/other/src/icons.tsx", "https://github.com/test/system/blob/main/../icons.tsx", "https://example.com/test/system/blob/main/icons.tsx"] {
            do { _ = try GitHubClient.filePaths([link], repository: repos[0]); throw SemanticError("FAIL: unsafe link accepted") }
            catch { try check(!error.localizedDescription.hasPrefix("FAIL:"), "Reject wrong repository/branch/host and traversal") }
        }
        let catalogFixture = """
        import * as SemanticIcons from "../../icons/semantic-icons"
        import * as GoIcons from "react-icons/go"
        const GIT_ICON_PATTERN = /Git|Repo(?![a-z])|Diff|Commit|Branch|Fork|Merge|PullRequest|Tag|History/
        const PROVIDER_ENTRIES = [["ServiceIcon", ServiceIcon, ServiceOutlineIcon]]
        export const ICON_CATALOG = [...LUCIDE_ENTRIES, ...OCTICON_ENTRIES, ...PROVIDER_ENTRIES]
        """
        let providerFixture = "export const ServiceIcon = make(); export const ServiceOutlineIcon = make()"
        let packageFixture = #"{"devDependencies":{"react-icons":"5.6.0"}}"#
        let catalogPath = "packages/ui/src/reference/components/icon-catalog.ts"
        var iconRequests = Set<String>()
        MockProtocol.handler = { request in
            if request.url!.path.contains("/commits/") { return (200, try data(["sha": "icon-revision"])) }
            try check(request.url!.query == "ref=icon-revision", "Pin all icon sources to the same revision")
            let prefix = "/repos/test/system/contents/"
            let path = String(request.url!.path.dropFirst(prefix.count))
            iconRequests.insert(path)
            let fixtures = [catalogPath: catalogFixture, "packages/ui/src/icons/semantic-icons.tsx": iconExports,
                            "packages/ui/src/icons/provider-icons.tsx": providerFixture, "packages/ui/package.json": packageFixture]
            guard let content = fixtures[path] else { throw SemanticError("Unexpected icon dependency") }
            return (200, try data(["type": "file", "size": content.utf8.count, "encoding": "base64", "content": Data(content.utf8).base64EncodedString()] as [String: Any]))
        }
        let iconIndex = try await client.index(repos[0], paths: ["https://github.com/test/system/blob/main/" + catalogPath], progress: { _ in })
        try check(iconIndex.tokens.count == 23 && iconIndex.tokens.allSatisfy { $0.source == catalogPath && $0.kind == "Icon" }, "Import full catalog and preserve tab source grouping")
        try check(iconIndex.tokens.contains { $0.name == "GoGitPullRequest" } && iconIndex.tokens.contains { $0.name == "ServiceOutlineIcon" }, "Include Git and outline provider variants")
        try check(iconRequests.count == 4 && iconIndex.sourceFiles == [catalogPath], "Read only the catalog and three explicit dependencies")
        do {
            _ = try IconCatalog.tokens(catalog: catalogFixture, semantic: iconExports, providers: providerFixture, package: "{}", source: catalogPath)
            throw SemanticError("FAIL: unknown icon dependency version accepted")
        } catch { try check(!error.localizedDescription.hasPrefix("FAIL:"), "Reject unsupported dependency versions") }
        do { _ = try IconCatalog.relativePath("../../escape", from: "src/icons.ts"); throw SemanticError("FAIL: traversal accepted") }
        catch { try check(!error.localizedDescription.hasPrefix("FAIL:"), "Bound dependency resolution to the repository") }
        for invalid in ["../tokens.css", "/tokens.css", "https://github.com/test/tokens.css", "src/", "theme.exe"] {
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
        try check(legacy.sourceFiles == nil && legacy.pickerTabs == nil && legacy.colorReferencesScanned == nil,
                  "Backward-compatible token cache")
        var withTab = index
        withTab.pickerTabs = [PickerTab(title: "Icons", path: "src/icons.json")]
        let restored = try JSONDecoder().decode(TokenIndex.self, from: JSONEncoder().encode(withTab))
        try check(restored.pickerTabs == withTab.pickerTabs, "Persist file-backed picker tabs")
        MockProtocol.handler = { _ in (401, Data()) }
        do { let _: GitHubUser = try await client.request("/user"); throw SemanticError("FAIL: expired credentials accepted") }
        catch { try check(error is GitHubAuthenticationError && error.localizedDescription.contains("expired"), "Typed expired-session error enables clearing stale connection status") }
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
