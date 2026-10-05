import AppKit
import SwiftUI

enum LocalDefinition {
    static func applicationURL(bundleID: String, appNames: [String]) -> URL? {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return app }
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
        return fallbackApplicationURL(bundleID: bundleID, appNames: appNames, roots: roots)
    }
    static func fallbackApplicationURL(bundleID: String, appNames: [String], roots: [URL]) -> URL? {
        for root in roots {
            for appName in appNames {
                let app = root.appendingPathComponent("\(appName).app", isDirectory: true)
                let info = app.appendingPathComponent("Contents/Info.plist")
                if let data = try? Data(contentsOf: info),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   plist["CFBundleIdentifier"] as? String == bundleID { return app }
            }
        }
        return nil
    }
    static func fileURL(checkout: String, source: String) -> URL? {
        guard let path = try? GitHubClient.filePaths([source]).first else { return nil }
        let root = URL(fileURLWithPath: checkout, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }
    static func line(_ token: DesignToken, at file: URL) -> Int? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return GitHubClient.definitionLine(token, in: text)
    }
    static func goToArgument(file: URL, line: Int) -> String { "\(file.path):\(line)" }
    static func codeSessionURL(editor: PreferredEditor, file: URL, line: Int, checkout: String) -> URL? {
        guard editor == .codex || editor == .claude else { return nil }
        let prompt = "Open \(file.path) at line \(line) (\(file.lastPathComponent)) and show the definition. Do not edit the file."
        var link = URLComponents()
        link.scheme = editor == .codex ? "codex" : "claude"
        link.host = editor == .codex ? "threads" : "code"
        link.path = "/new"
        link.queryItems = editor == .codex
            ? [URLQueryItem(name: "path", value: checkout), URLQueryItem(name: "prompt", value: prompt)]
            : [URLQueryItem(name: "folder", value: checkout), URLQueryItem(name: "q", value: prompt)]
        return link.url
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var clientID = ""
    @Published var appSlug = ""
    let allowsDeveloperSetup: Bool
    @Published var account: String? = nil
    @Published var selectedRepository: Repository? = nil
    @Published var tokenFilePaths = "src/styles/theme.css"
    @Published var repositories: [Repository] = []
    @Published var indices: [TokenIndex] = [] {
        didSet { displayedTokensByRepository.removeAll() }
    }
    @Published var activeID: Int? = nil
    @Published var deviceCode: DeviceCode? = nil
    @Published var updatesConfigured = false
    @Published var canCheckForUpdates = false
    var checkForUpdates: (() -> Void)?
    @Published var busy = false
    @Published var status = ""
    @Published var error: String? = nil
    @Published var screen = "home"
    @Published var enabledApps: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledApps") ?? []) {
        didSet { UserDefaults.standard.set(Array(enabledApps), forKey: "enabledApps") }
    }
    @Published var allApps = UserDefaults.standard.object(forKey: "pickerAllApps") as? Bool ?? true {
        didSet { UserDefaults.standard.set(allApps, forKey: "pickerAllApps") }
    }
    @Published private(set) var pickerRequested = UserDefaults.standard.bool(forKey: "pickerRequested")
    @Published var pickerNotice: String? = nil
    @Published var pickerFeedback: String? = nil
    var checkPermission: () -> Bool = { AXIsProcessTrusted() }
    @Published var pickerEnabled = false
    @Published var permissionGranted = AXIsProcessTrusted()
    var configureMonitor: (() -> Void)?
    var stopMonitor: (() -> Void)?
    private var task: Task<Void, Never>?
    private var refreshAfterGitHub = false
    private var token: String?
    private var displayedTokensByRepository: [Int: [DesignToken]] = [:]
    private let cacheURL: URL
    var activeIndex: TokenIndex? { indices.first { $0.repository.id == activeID } }
    var tokens: [DesignToken] {
        guard let index = activeIndex else { return [] }
        if let cached = displayedTokensByRepository[index.repository.id] { return cached }
        let displayed = index.displayTokens
        displayedTokensByRepository[index.repository.id] = displayed
        return displayed
    }
    var resolutionTokens: [DesignToken] { tokens + (activeIndex?.referenceTokens ?? []) }
    func chooseLocalCheckout() -> String? {
        guard let repository = activeIndex?.repository, repository.id != 0 else {
            error = "Connect a GitHub project before choosing a local checkout."
            return nil
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the local checkout of \(repository.full_name)."
        panel.prompt = "Use folder"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }
    func openDefinition(_ definition: DesignToken, editor: String = PreferredEditor.vscode.rawValue) {
        guard let repository = activeIndex?.repository, repository.id != 0 else {
            error = "Connect a GitHub project to open token definitions."
            return
        }
        guard let chosen = PreferredEditor(rawValue: editor) else { return }
        guard let checkout = UserDefaults.standard.string(forKey: "pickerCheckout:\(repository.id)"), !checkout.isEmpty else {
            error = "Choose a local checkout in General settings to open definitions in \(chosen.rawValue)."
            return
        }
        guard let file = LocalDefinition.fileURL(checkout: checkout, source: definition.source) else {
            error = "\(definition.source) was not found in the selected local checkout. Choose the matching folder in General settings."
            return
        }
        guard let line = LocalDefinition.line(definition, at: file) else {
            error = "Could not locate \(definition.name) in the local file. Refresh the project or choose the matching checkout."
            return
        }
        do {
            try launchEditor(chosen, file: file, line: line, checkout: checkout)
        } catch {
            self.error = error.localizedDescription
        }
    }
    private func launchEditor(_ editor: PreferredEditor, file: URL, line: Int, checkout: String) throws {
        if editor == .codex || editor == .claude {
            let bundleID = editor == .codex ? "com.openai.codex" : "com.anthropic.claudefordesktop"
            let appNames = editor == .codex ? ["Codex", "ChatGPT"] : ["Claude"]
            guard LocalDefinition.applicationURL(bundleID: bundleID, appNames: appNames) != nil else {
                throw SemanticError("Install \(editor.rawValue) to open this definition.")
            }
            guard let url = LocalDefinition.codeSessionURL(editor: editor, file: file, line: line, checkout: checkout),
                  NSWorkspace.shared.open(url) else {
                throw SemanticError("Could not open \(editor.rawValue).")
            }
            return
        }
        let bundleID: String
        let appName: String
        let command: String
        switch editor {
        case .vscode:
            bundleID = "com.microsoft.VSCode"
            appName = "Visual Studio Code"
            command = "code"
        case .cursor:
            bundleID = "com.todesktop.230313mzl4w4u92"
            appName = "Cursor"
            command = "cursor"
        case .codex, .claude:
            return
        }
        guard let app = LocalDefinition.applicationURL(bundleID: bundleID, appNames: [appName]) else {
            throw SemanticError("Install \(editor.rawValue) to open this definition.")
        }
        let executable = app.appendingPathComponent("Contents/Resources/app/bin/\(command)")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw SemanticError("Could not find the \(editor.rawValue) command in the installed app.")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--goto", LocalDefinition.goToArgument(file: file, line: line)]
        process.currentDirectoryURL = URL(fileURLWithPath: checkout, isDirectory: true)
        process.terminationHandler = { _ in }
        try process.run()
    }
    var needsColorRefresh: Bool {
        guard let index = activeIndex, index.repository.id != 0, index.colorReferencesScanned != true else { return false }
        return index.tokens.contains { $0.kind.lowercased() == "color" && $0.value.contains("var(") }
    }
    let supportedApps: [(name: String, id: String)] = [
        ("ChatGPT", "com.openai.chat"), ("Codex", "com.openai.codex"), ("Claude", "com.anthropic.claudefordesktop"),
        ("Cursor", "com.todesktop.230313mzl4w4u92"), ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Google Chrome", "com.google.Chrome"), ("Safari", "com.apple.Safari"),
        ("Arc", "company.thebrowser.Browser"), ("TextEdit (for testing)", "com.apple.TextEdit")
    ]
    init(preview: Bool = false, info: [String: Any] = Bundle.main.infoDictionary ?? [:],
         defaults: UserDefaults = .standard, cacheURL: URL? = nil) {
        allowsDeveloperSetup = info["SemanticDeveloperSetupAllowed"] as? Bool ?? false
        clientID = (info["SemanticGitHubClientID"] as? String ?? (allowsDeveloperSetup ? defaults.string(forKey: "githubClientID") : nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        appSlug = (info["SemanticGitHubAppSlug"] as? String ?? (allowsDeveloperSetup ? defaults.string(forKey: "githubAppSlug") : nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Semantic/token-index.json")
        if preview { return }
        if let data = try? Data(contentsOf: self.cacheURL), let saved = try? JSONDecoder().decode([TokenIndex].self, from: data) { indices = saved }
        let saved = UserDefaults.standard.object(forKey: "activeRepository") as? Int
        activeID = indices.first(where: { $0.repository.id == saved })?.repository.id ?? indices.first?.repository.id
        // GitHub credentials live only in memory. Each launch starts signed out.
    }
    func select(_ id: Int) { activeID = id; UserDefaults.standard.set(id, forKey: "activeRepository") }
    func saveConfiguration() {
        guard allowsDeveloperSetup else { return }
        clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        appSlug = appSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, clientID.range(of: #"^[a-zA-Z0-9_.-]+$"#, options: .regularExpression) != nil,
              appSlug.range(of: #"^[a-zA-Z0-9-]+$"#, options: .regularExpression) != nil else {
            error = "Enter the public Client ID and GitHub App slug. The slug is the name in github.com/apps/your-app."; return
        }
        UserDefaults.standard.set(clientID, forKey: "githubClientID")
        UserDefaults.standard.set(appSlug, forKey: "githubAppSlug")
        error = nil; screen = "home"
    }
    func connectGitHub() {
        guard !clientID.isEmpty, !appSlug.isEmpty else { missingGitHubConfiguration(); return }
        task?.cancel(); busy = true; error = nil; status = "Starting GitHub sign-in…"
        task = Task {
            do {
                let client = GitHubClient()
                let code = try await client.beginLogin(clientID: clientID)
                try Task.checkCancellation()
                deviceCode = code; status = "Enter the code on GitHub to connect."
                // A fixed GitHub URL prevents an unexpected auth response from opening arbitrary hosts.
                NSWorkspace.shared.open(URL(string: "https://github.com/login/device")!)
                let accessToken = try await client.awaitLogin(clientID: clientID, device: code)
                try Task.checkCancellation()
                token = accessToken; deviceCode = nil
                try await loadRepositories()
                if needsColorRefresh {
                    do { try await refreshCachedColors(using: GitHubClient(token: accessToken)) }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        self.error = "Could not refresh cached color previews. \(error.localizedDescription)"
                        status = "Cached definitions are unchanged."
                        screen = "home"
                    }
                }
            } catch is CancellationError {
                status = account == nil ? "" : "Color refresh canceled. Cached definitions are unchanged."
                if account != nil { screen = "home" }
            }
            catch { self.error = error.localizedDescription }
            busy = false; deviceCode = nil
        }
    }
    private func loadRepositories() async throws {
        status = "Loading your GitHub projects…"
        let client = GitHubClient(token: token)
        let user: GitHubUser = try await client.request("/user")
        let repos = try await client.repositories()
        try Task.checkCancellation()
        account = user.login; repositories = repos; status = ""; screen = "projects"
    }
    func refreshCachedColors(using client: GitHubClient) async throws {
        guard let old = activeIndex else { return }
        let paths = old.sourceFiles ?? Array(Set(old.tokens.map(\.source))).sorted()
        guard !paths.isEmpty else { throw SemanticError("Choose the project's token files and refresh them.") }
        status = "Updating cached color previews…"
        var updated = try await client.index(old.repository, paths: paths) { message in
            await MainActor.run { self.status = message }
        }
        try Task.checkCancellation()
        updated.pickerTabs = (old.pickerTabs ?? []).filter { paths.contains($0.path) }
        let saved = indices.map { $0.repository.id == old.repository.id ? updated : $0 }
        try persist(saved)
        indices = saved
        status = "Updated color previews for \(old.repository.full_name)."
        screen = "home"
    }
    func refreshRepositories() {
        task?.cancel(); busy = true; error = nil
        task = Task {
            do { try await loadRepositories() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func chooseFiles(_ repo: Repository) {
        guard !busy else { return }
        selectedRepository = repo
        tokenFilePaths = (indices.first { $0.repository.id == repo.id }?.sourceFiles ?? ["src/styles/theme.css"]).joined(separator: "\n")
        error = nil; status = ""; screen = "files"
    }
    func importSelectedFiles() {
        guard let repo = selectedRepository else { return }
        do { sync(repo, paths: try GitHubClient.filePaths(tokenFilePaths.components(separatedBy: .newlines))) }
        catch { self.error = error.localizedDescription }
    }
    func addPickerTab(title rawTitle: String, path rawPath: String, completion: @escaping (Result<PickerTab, Error>) -> Void) {
        guard let index = activeIndex else { completion(.failure(SemanticError("Choose a project before adding a tab."))); return }
        guard !busy else { completion(.failure(SemanticError("Wait for the current import to finish."))); return }
        do {
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= PickerState.maxTabTitleLength,
                  !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SemanticError("Enter a tab title of up to 25 characters.")
            }
            let path = try GitHubClient.filePaths([rawPath])[0]
            let paths = index.sourceFiles ?? Array(Set(index.tokens.map(\.source))).sorted()
            let tabs = index.pickerTabs ?? []
            guard !["foundations", "new tab"].contains(title.lowercased()),
                  !tabs.contains(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) else {
                throw SemanticError("Choose a unique tab title.")
            }
            guard !tabs.contains(where: { $0.path == path }) else { throw SemanticError("This file already has a tab.") }
            let tab = PickerTab(title: title, path: path)
            if paths.contains(path) {
                var updatedIndex = index
                updatedIndex.pickerTabs = tabs + [tab]
                let updated = indices.map { $0.repository.id == index.repository.id ? updatedIndex : $0 }
                try persist(updated)
                indices = updated
                completion(.success(tab))
                return
            }
            guard index.repository.id != 0 else { throw SemanticError("Connect a GitHub project to add a new token file.") }
            sync(index.repository, paths: paths + [path], pickerTabs: tabs + [tab]) { result in
                completion(result.map { _ in tab })
            }
        } catch { completion(.failure(error)) }
    }
    func refreshTokens(_ repo: Repository) {
        guard let index = indices.first(where: { $0.repository.id == repo.id }) else { chooseFiles(repo); return }
        let paths = index.sourceFiles ?? Array(Set(index.tokens.map(\.source))).sorted()
        guard !paths.isEmpty else { chooseFiles(repo); return }
        sync(repo, paths: paths)
    }
    func sync(_ repo: Repository, paths: [String], pickerTabs: [PickerTab]? = nil,
              completion: ((Result<TokenIndex, Error>) -> Void)? = nil) {
        guard token != nil else {
            let problem = SemanticError("Connect GitHub before syncing this repository.")
            if let completion { completion(.failure(problem)) } else { error = problem.localizedDescription; screen = "home" }
            return
        }
        task?.cancel(); busy = true; error = nil; status = "Opening selected token files…"
        task = Task {
            do {
                var index = try await GitHubClient(token: token).index(repo, paths: paths) { message in
                    await MainActor.run { self.status = message }
                }
                try Task.checkCancellation()
                index.pickerTabs = (pickerTabs ?? indices.first(where: { $0.repository.id == repo.id })?.pickerTabs ?? [])
                    .filter { paths.contains($0.path) }
                var updated = indices.filter { $0.repository.id != repo.id }; updated.append(index)
                try persist(updated)
                indices = updated; select(repo.id)
                if completion == nil { screen = "home" }
                status = "Loaded \(index.tokens.count) semantic definitions."
                completion?(.success(index))
            } catch is CancellationError {
                status = "Sync canceled. Previous tokens are unchanged."
                completion?(.failure(CancellationError()))
            } catch {
                if let completion { completion(.failure(error)) } else { self.error = error.localizedDescription }
            }
            busy = false
        }
    }
    func cancel() { task?.cancel(); deviceCode = nil }
    func cancelPickerTabImport() { task?.cancel() }
    func disconnect() {
        task?.cancel(); pausePicker()
        token = nil; account = nil; repositories = []; deviceCode = nil
        // Disconnect also clears repository definitions so private metadata is not retained.
        indices = []; activeID = nil; try? FileManager.default.removeItem(at: cacheURL)
        status = "GitHub disconnected and cached definitions cleared."; screen = "home"; busy = false
    }
    func sample() {
        let repository = Repository(id: 0, full_name: "Example / DesignSnippets", default_branch: "sample", private: false)
        let tokens = TokenParser.parse("""
        :root {
          --border-default: #e2e8f0;
          --border-focus: #6366f1;
          --background-default: #ffffff;
          --foreground-muted: #64748b;
          --accent-default: #276c51;
          --radius-md: 8px;
          --spacing-md: 16px;
        }
        .button-primary { color: var(--foreground-muted); }
        """, source: "example/tokens.css")
        let index = TokenIndex(repository: repository, tokens: tokens, syncedAt: Date(), revision: "sample")
        indices = indices.filter { $0.repository.id != 0 } + [index]; select(0); screen = "home"
        do { try persist(indices) } catch { self.error = error.localizedDescription }
    }
    private func persist(_ values: [TokenIndex]) throws {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(values).write(to: cacheURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    }
    func installGitHubApp() {
        guard appSlug.range(of: #"^[a-zA-Z0-9-]+$"#, options: .regularExpression) != nil else { missingGitHubConfiguration(); return }
        refreshAfterGitHub = true
        NSWorkspace.shared.open(URL(string: "https://github.com/apps/\(appSlug)/installations/new")!)
    }
    func returnedToApp() {
        reconcilePicker()
        guard refreshAfterGitHub, !busy, token != nil else { return }
        refreshAfterGitHub = false
        refreshRepositories()
    }
    private func missingGitHubConfiguration() {
        if allowsDeveloperSetup { screen = "setup" }
        else { error = "This build is missing its GitHub configuration. Please install an updated release of DesignSnippets." }
    }
    func allowsPicker(in bundle: String) -> Bool { allApps || enabledApps.contains(bundle) }
    func reconcilePicker() {
        permissionGranted = checkPermission()
        guard permissionGranted else {
            if pickerEnabled { stopMonitor?() }
            pickerNotice = pickerRequested ? "macOS has not granted Accessibility to this copy of DesignSnippets. Enable it in System Settings → Privacy & Security → Accessibility, then return here. If it is already enabled, quit DesignSnippets and add the current app again." : nil
            return
        }
        pickerNotice = nil
        if pickerRequested && !pickerEnabled { configureMonitor?() }
    }
    func enablePicker() {
        pickerRequested = true
        UserDefaults.standard.set(true, forKey: "pickerRequested")
        reconcilePicker()
        if !permissionGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }
    func pausePicker() {
        pickerRequested = false
        UserDefaults.standard.set(false, forKey: "pickerRequested")
        stopMonitor?()
        pickerEnabled = false
        pickerNotice = nil
    }
}
