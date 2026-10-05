import Foundation

struct DeviceCode: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let expires_in: Int
    let interval: Int
}
struct AccessGrant: Decodable {
    let access_token: String?
    let expires_in: Int?
    let error: String?
    let error_description: String?
}
struct GitHubUser: Decodable { let login: String }
struct GitHubClient {
    var token: String? = nil
    var session: URLSession = .shared
    func request<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        guard let url = URL(string: "https://api.github.com" + path) else { throw SemanticError("Invalid GitHub request.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DesignSnippets-macOS", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SemanticError("GitHub returned an invalid response.") }
        if response.statusCode == 404 { throw SemanticError("GitHub could not find that file, branch, or repository. Check the path and repository access.") }
        if response.statusCode == 401 { throw SemanticError("Your GitHub session expired. Disconnect and sign in again.") }
        if response.statusCode == 403 || response.statusCode == 429 { throw SemanticError("GitHub denied this request or the API limit was reached. Check repository access and try again later.") }
        guard (200..<300).contains(response.statusCode) else { throw SemanticError("GitHub request failed (\(response.statusCode)). Check that DesignSnippets is installed on this repository with Contents: read access.") }
        return try JSONDecoder().decode(type, from: data)
    }
    func oauth<T: Decodable>(_ endpoint: String, parameters: [String: String], as type: T.Type = T.self) async throws -> T {
        var request = URLRequest(url: URL(string: "https://github.com/login/" + endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw SemanticError("GitHub sign-in failed. Check the Client ID and enable device flow in the GitHub App settings.") }
        if type == DeviceCode.self, let payload = try? JSONDecoder().decode(AccessGrant.self, from: data), let error = payload.error {
            throw SemanticError(payload.error_description ?? error)
        }
        return try JSONDecoder().decode(type, from: data)
    }
    func beginLogin(clientID: String) async throws -> DeviceCode {
        try await oauth("device/code", parameters: ["client_id": clientID])
    }
    func awaitLogin(clientID: String, device: DeviceCode) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(device.expires_in))
        var interval = max(device.interval, 5)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()
            let grant: AccessGrant = try await oauth("oauth/access_token", parameters: ["client_id": clientID, "device_code": device.device_code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
            if let token = grant.access_token { return token }
            switch grant.error {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw SemanticError("GitHub authorization was declined. You can try again when ready.")
            case "expired_token": throw SemanticError("The sign-in code expired. Start sign-in again.")
            default: throw SemanticError(grant.error_description ?? "GitHub could not complete sign-in.")
            }
        }
        throw SemanticError("The sign-in code expired. Start sign-in again.")
    }
    func repositories() async throws -> [Repository] {
        var result: [Repository] = []
        var page = 1
        while true {
            try Task.checkCancellation()
            let repos: [Repository] = try await request("/user/repos?per_page=100&page=\(page)&sort=full_name&direction=asc")
            result += repos
            if repos.count < 100 { break }
            page += 1
        }
        return Dictionary(grouping: result, by: \.id).compactMap { $0.value.first }.sorted { $0.full_name.localizedCaseInsensitiveCompare($1.full_name) == .orderedAscending }
    }
    static func filePaths(_ input: [String]) throws -> [String] {
        var paths: [String] = []
        for raw in input {
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty { continue }
            guard !path.hasPrefix("/"), !path.contains(":"), !path.contains("\\"),
                  !path.components(separatedBy: "/").contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
                  !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SemanticError("Use a repository-relative file path, such as src/styles/theme.css, rather than a URL or folder path.")
            }
            guard ["css", "scss", "sass", "less", "json"].contains((path as NSString).pathExtension.lowercased()) else {
                throw SemanticError("Choose a CSS, SCSS, Sass, Less, or JSON token file.")
            }
            if !paths.contains(path) { paths.append(path) }
        }
        guard !paths.isEmpty else { throw SemanticError("Enter at least one token file path.") }
        guard paths.count <= 20 else { throw SemanticError("Choose up to 20 token files per project.") }
        return paths
    }
    func fileText(_ repo: Repository, path: String) async throws -> String {
        struct File: Decodable { let type: String; let size: Int; let content: String?; let encoding: String? }
        let path = try Self.filePaths([path])[0]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encodedPath = path.components(separatedBy: "/").map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
        let branch = repo.default_branch.addingPercentEncoding(withAllowedCharacters: allowed) ?? repo.default_branch
        let file: File = try await request("/repos/\(repo.full_name)/contents/\(encodedPath)?ref=\(branch)")
        guard file.type == "file", file.size <= 1_000_000, file.encoding == "base64",
              let content = file.content, let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters),
              let text = String(data: data, encoding: .utf8) else {
            throw SemanticError("Could not read \(path) as a text file.")
        }
        return text
    }
    static func definitionLine(_ token: DesignToken, in text: String) -> Int? {
        let name: String
        if !token.name.hasPrefix("--"), let alias = TokenParser.matches(#"^var\((--[\w-]+)\)$"#, token.value).first?[1] { name = alias }
        else { name = token.name }
        if token.source.lowercased().hasSuffix(".json") {
            return jsonDefinitionLine(name, in: text)
        }
        let searchable: String
        let comments = try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#)
        let sanitized = NSMutableString(string: text)
        for match in (comments?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? []).reversed() {
            let comment = (text as NSString).substring(with: match.range)
            sanitized.replaceCharacters(in: match.range, with: String(comment.map { $0 == "\n" ? "\n" : " " }))
        }
        searchable = sanitized as String
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern: String
        if name.hasPrefix("--") { pattern = "(?m)(?:^|[;{])\\s*(" + escaped + ")\\s*:" }
        else if name.hasPrefix(".") { pattern = "(?m)(" + escaped + ")(?=[\\s:{.#>])" }
        else {
            let key = NSRegularExpression.escapedPattern(for: String(name.split(separator: ".").last ?? ""))
            pattern = "(\"" + key + "\")\\s*:"
        }
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: searchable, range: NSRange(location: 0, length: (searchable as NSString).length)) else { return nil }
        let preceding = (searchable as NSString).substring(to: match.range(at: 1).location)
        return preceding.reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
    }
    private static func jsonDefinitionLine(_ name: String, in text: String) -> Int? {
        let units = Array(text.utf16)
        var position = 0
        var line = 1
        var locations: [String: [Int]] = [:]
        func advance() {
            if units[position] == 10 { line += 1 }
            position += 1
        }
        func whitespace() {
            while position < units.count && [9, 10, 13, 32].contains(units[position]) { advance() }
        }
        func readString() -> String? {
            guard position < units.count, units[position] == 34 else { return nil }
            let start = position
            advance()
            while position < units.count {
                let character = units[position]
                advance()
                if character == 92 {
                    if position < units.count { advance() }
                } else if character == 34 {
                    let literal = String(decoding: units[start..<position], as: UTF16.self)
                    guard let data = literal.data(using: .utf8) else { return nil }
                    return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
                }
            }
            return nil
        }
        func walk(_ path: [String]) {
            whitespace()
            guard position < units.count else { return }
            if units[position] == 123 {
                advance()
                while position < units.count {
                    whitespace()
                    if position < units.count, units[position] == 125 { advance(); return }
                    let keyLine = line
                    guard let key = readString() else { return }
                    whitespace()
                    guard position < units.count, units[position] == 58 else { return }
                    advance()
                    let child = path + [key]
                    if !key.hasPrefix("$"), key != "type" { locations[child.joined(separator: "."), default: []].append(keyLine) }
                    walk(child)
                    whitespace()
                    if position < units.count, units[position] == 44 { advance() }
                    else if position < units.count, units[position] == 125 { advance(); return }
                    else { return }
                }
            } else if units[position] == 91 {
                advance()
                while position < units.count {
                    whitespace()
                    if position < units.count, units[position] == 93 { advance(); return }
                    walk(path)
                    whitespace()
                    if position < units.count, units[position] == 44 { advance() }
                    else if position < units.count, units[position] == 93 { advance(); return }
                    else { return }
                }
            } else if units[position] == 34 { _ = readString() }
            else {
                while position < units.count && ![44, 93, 125].contains(units[position]) { advance() }
            }
        }
        walk([])
        guard let lines = locations[name], lines.count == 1 else { return nil }
        return lines[0]
    }
    static func definitionURL(_ repo: Repository, path: String, line: Int? = nil, editor: String = "GitHub.dev") -> URL? {
        let names = repo.full_name.split(separator: "/")
        guard names.count == 2, let path = try? filePaths([path])[0] else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard ["GitHub.dev", "GitHub"].contains(editor) else { return nil }
        let parts = names.map(String.init) + [editor == "GitHub.dev" ? "blob" : "edit", repo.default_branch] + path.components(separatedBy: "/")
        var url = URLComponents()
        url.scheme = "https"
        url.host = editor == "GitHub.dev" ? "github.dev" : "github.com"
        url.percentEncodedPath = "/" + parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
        if editor == "GitHub.dev", let line, line > 0 { url.fragment = "L\(line)" }
        return url.url
    }
    func index(_ repo: Repository, paths input: [String], progress: @escaping @Sendable (String) async -> Void) async throws -> TokenIndex {
        struct Commit: Decodable { let sha: String }
        struct File: Decodable { let type: String; let size: Int; let content: String?; let encoding: String? }
        struct DirectoryEntry: Decodable { let name: String; let type: String; let size: Int }
        func encodedPath(_ path: String) -> String {
            path.components(separatedBy: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 }.joined(separator: "/")
        }
        let paths = try Self.filePaths(input)
        let branch = repo.default_branch.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? repo.default_branch
        await progress("Opening \(repo.default_branch)…")
        let commit: Commit = try await request("/repos/\(repo.full_name)/commits/\(branch)")
        var tokens: [DesignToken] = []
        for (position, path) in paths.enumerated() {
            try Task.checkCancellation()
            await progress("Reading \(position + 1) of \(paths.count): \(path)")
            let file: File
            do { file = try await request("/repos/\(repo.full_name)/contents/\(encodedPath(path))?ref=\(commit.sha)") }
            catch let error as DecodingError { _ = error; throw SemanticError("\(path) is not a readable file. Enter a file path rather than a directory.") }
            catch { throw SemanticError("Could not read \(path). \(error.localizedDescription)") }
            guard file.type == "file", file.size <= 1_000_000 else { throw SemanticError("\(path) must be a regular text file smaller than 1 MB.") }
            guard file.encoding == "base64", let content = file.content,
                  let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters),
                  let text = String(data: data, encoding: .utf8) else { throw SemanticError("Could not decode \(path) as UTF-8 text. Previous tokens are unchanged.") }
            let parsed = TokenParser.parse(text, source: path)
            guard !parsed.isEmpty else { throw SemanticError("No definitions found in \(path). Choose a stylesheet with CSS variables/classes, or token JSON with value or $value definitions. Previous tokens are unchanged.") }
            tokens += parsed
        }
        let selected = TokenParser.unique(tokens)
        var references: [DesignToken] = []
        let folders = Set(paths.map { ($0 as NSString).deletingLastPathComponent }).sorted()
        for folder in folders {
            let local = selected.filter { ($0.source as NSString).deletingLastPathComponent == folder }
            var localReferences: [DesignToken] = []
            var missing = Self.missingColorReferences(in: local)
            if missing.isEmpty { continue }
            await progress("Resolving color scales in \(folder.isEmpty ? "the repository root" : folder)…")
            try Task.checkCancellation()
            let directory = folder.isEmpty ? "" : "/\(encodedPath(folder))"
            let entries: [DirectoryEntry]
            do { entries = try await request("/repos/\(repo.full_name)/contents\(directory)?ref=\(commit.sha)") }
            catch is CancellationError { throw CancellationError() }
            catch { throw SemanticError("Could not inspect nearby color files in \(folder.isEmpty ? "the repository root" : folder). \(error.localizedDescription)") }
            let candidates = entries.filter { entry in
                let ext = (entry.name as NSString).pathExtension.lowercased()
                return entry.type == "file" && entry.size <= 1_000_000
                    && ["css", "scss", "sass", "less"].contains(ext)
            }.sorted { left, right in
                func priority(_ name: String) -> Int {
                    let stem = (name as NSString).deletingPathExtension.lowercased()
                    return ["scale", "color", "palette", "token", "variable"].contains(where: stem.contains) ? 0 : 1
                }
                return priority(left.name) == priority(right.name) ? left.name < right.name : priority(left.name) < priority(right.name)
            }
            var parsedCandidates: [[DesignToken]] = []
            var supportingError: Error?
            func addNeededCandidates() {
                var added = true
                while added && !missing.isEmpty {
                    added = false
                    var position = 0
                    while position < parsedCandidates.count {
                        if !Set(parsedCandidates[position].map(\.name)).isDisjoint(with: missing) {
                            localReferences += parsedCandidates.remove(at: position)
                            missing = Self.missingColorReferences(in: local + localReferences)
                            added = true
                        } else { position += 1 }
                    }
                }
            }
            for candidate in candidates where !missing.isEmpty {
                try Task.checkCancellation()
                let path = folder.isEmpty ? candidate.name : "\(folder)/\(candidate.name)"
                if paths.contains(path) { continue }
                do {
                    let file: File = try await request("/repos/\(repo.full_name)/contents/\(encodedPath(path))?ref=\(commit.sha)")
                    guard file.type == "file", file.size <= 1_000_000, file.encoding == "base64",
                          let content = file.content, let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters),
                          let text = String(data: data, encoding: .utf8) else { continue }
                    let parsed = TokenParser.parse(text, source: path)
                    parsedCandidates.append(parsed)
                    addNeededCandidates()
                } catch is CancellationError { throw CancellationError() }
                catch { supportingError = error }
            }
            if !missing.isEmpty, let supportingError {
                throw SemanticError("Could not finish resolving nearby color files in \(folder.isEmpty ? "the repository root" : folder). \(supportingError.localizedDescription) Previous tokens are unchanged.")
            }
            references += localReferences
        }
        return TokenIndex(repository: repo, tokens: selected, syncedAt: Date(), revision: commit.sha,
                          sourceFiles: paths, referenceTokens: references.isEmpty ? nil : TokenParser.unique(references),
                          colorReferencesScanned: true)
    }

    private static func missingColorReferences(in tokens: [DesignToken]) -> Set<String> {
        let available = Set(tokens.map(\.name))
        let byName = Dictionary(grouping: tokens, by: \.name)
        var pending = tokens.filter { $0.kind.lowercased() == "color" }.flatMap { token in
            TokenParser.matches(#"var\(\s*(--[\w-]+)"#, token.value).map { $0[1] }
        }
        var referenced = Set<String>()
        while let name = pending.popLast() {
            guard referenced.insert(name).inserted else { continue }
            for token in byName[name] ?? [] {
                pending += TokenParser.matches(#"var\(\s*(--[\w-]+)"#, token.value).map { $0[1] }
            }
        }
        return referenced.subtracting(available)
    }

}
