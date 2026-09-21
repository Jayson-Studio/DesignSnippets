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
    func index(_ repo: Repository, paths input: [String], progress: @escaping @Sendable (String) async -> Void) async throws -> TokenIndex {
        struct Commit: Decodable { let sha: String }
        struct File: Decodable { let type: String; let size: Int; let content: String?; let encoding: String? }
        let paths = try Self.filePaths(input)
        let branch = repo.default_branch.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? repo.default_branch
        await progress("Opening \(repo.default_branch)…")
        let commit: Commit = try await request("/repos/\(repo.full_name)/commits/\(branch)")
        var tokens: [DesignToken] = []
        for (position, path) in paths.enumerated() {
            try Task.checkCancellation()
            await progress("Reading \(position + 1) of \(paths.count): \(path)")
            let encoded = path.components(separatedBy: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 }.joined(separator: "/")
            let file: File
            do { file = try await request("/repos/\(repo.full_name)/contents/\(encoded)?ref=\(commit.sha)") }
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
        return TokenIndex(repository: repo, tokens: TokenParser.unique(tokens), syncedAt: Date(), revision: commit.sha, sourceFiles: paths)
    }

}

