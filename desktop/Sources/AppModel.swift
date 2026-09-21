import AppKit
import SwiftUI

@MainActor final class AppModel: ObservableObject {
    @Published var clientID = ""
    @Published var appSlug = ""
    let allowsDeveloperSetup: Bool
    @Published var account: String? = nil
    @Published var selectedRepository: Repository? = nil
    @Published var tokenFilePaths = "src/styles/theme.css"
    @Published var repositories: [Repository] = []
    @Published var indices: [TokenIndex] = []
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
    private let cacheURL: URL
    var activeIndex: TokenIndex? { indices.first { $0.repository.id == activeID } }
    var tokens: [DesignToken] { activeIndex?.tokens ?? [] }
    let supportedApps: [(name: String, id: String)] = [
        ("ChatGPT", "com.openai.chat"), ("Codex", "com.openai.codex"), ("Claude", "com.anthropic.claudefordesktop"),
        ("Cursor", "com.todesktop.230313mzl4w4u92"), ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Google Chrome", "com.google.Chrome"), ("Safari", "com.apple.Safari"),
        ("Arc", "company.thebrowser.Browser"), ("TextEdit (for testing)", "com.apple.TextEdit")
    ]
    init(preview: Bool = false, info: [String: Any] = Bundle.main.infoDictionary ?? [:], defaults: UserDefaults = .standard) {
        allowsDeveloperSetup = info["SemanticDeveloperSetupAllowed"] as? Bool ?? false
        clientID = (info["SemanticGitHubClientID"] as? String ?? (allowsDeveloperSetup ? defaults.string(forKey: "githubClientID") : nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        appSlug = (info["SemanticGitHubAppSlug"] as? String ?? (allowsDeveloperSetup ? defaults.string(forKey: "githubAppSlug") : nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Semantic/token-index.json")
        if preview { return }
        if let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode([TokenIndex].self, from: data) { indices = saved }
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
            } catch is CancellationError { }
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
    func refreshTokens(_ repo: Repository) {
        guard let paths = indices.first(where: { $0.repository.id == repo.id })?.sourceFiles else { chooseFiles(repo); return }
        sync(repo, paths: paths)
    }
    func sync(_ repo: Repository, paths: [String]) {
        guard token != nil else { error = "Connect GitHub before syncing this repository."; screen = "home"; return }
        task?.cancel(); busy = true; error = nil; status = "Opening selected token files…"
        task = Task {
            do {
                let index = try await GitHubClient(token: token).index(repo, paths: paths) { message in
                    await MainActor.run { self.status = message }
                }
                try Task.checkCancellation()
                var updated = indices.filter { $0.repository.id != repo.id }; updated.append(index)
                try persist(updated)
                indices = updated; select(repo.id); screen = "home"; status = "Loaded \(index.tokens.count) semantic definitions."
            } catch is CancellationError { status = "Sync canceled. Previous tokens are unchanged." }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func cancel() { task?.cancel(); deviceCode = nil }
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
