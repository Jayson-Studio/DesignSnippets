import SwiftUI
import AppKit

let semanticGreen = Protegia.accent
struct SemanticPanel: View {
    @ObservedObject var model: AppModel
    var appVersion: String
    var onDismiss: (() -> Void)?
    var onTabChange: ((String) -> Void)?
    @State private var search = ""
    @State private var selectedTab: String
    init(model: AppModel, appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
         initialTab: String = "Default", onDismiss: (() -> Void)? = nil,
         onTabChange: ((String) -> Void)? = nil) {
        self.model = model
        self.appVersion = appVersion
        self.onDismiss = onDismiss
        self.onTabChange = onTabChange
        _selectedTab = State(initialValue: initialTab)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "number.square.fill").font(Protegia.font(26)).foregroundStyle(semanticGreen)
                Text("DesignSnippets").font(Protegia.font(18, bold: true))
                Spacer()
                Text(appVersion).font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
                    .lineLimit(1).fixedSize().accessibilityLabel("Version \(appVersion)")
                Menu {
                    Button("Check for Updates…") { model.checkForUpdates?() }.disabled(!model.canCheckForUpdates)
                    Button("Preferences…") { model.screen = "preferences" }
                    if model.allowsDeveloperSetup { Button("GitHub App setup…") { model.screen = "setup" } }
                    Divider()
                    Button("Close menu") { onDismiss?() }
                    Button("Quit DesignSnippets") { NSApp.terminate(nil) }
                } label: {
                    Text("⋮")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(Protegia.secondary)
                        .frame(width: 24, height: 28).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(Protegia.secondary)
                    .accessibilityLabel("App menu").help("App menu")
            }.padding(Protegia.spaceLG)
            ProtegiaDivider()
            HStack(spacing: 0) {
                ForEach(["Default", "Preview"], id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab).font(Protegia.font(12, bold: true))
                            .foregroundStyle(selectedTab == tab ? Protegia.text : Protegia.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(alignment: .bottom) {
                                if selectedTab == tab { Rectangle().fill(Protegia.accent).frame(height: 2) }
                            }
                    }.buttonStyle(.plain).accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            ProtegiaDivider()
            if selectedTab == "Preview" {
                PreviewSandbox(model: model)
            } else { ScrollView {
                VStack(alignment: .leading, spacing: Protegia.spaceBase) {
                    if model.screen != "home" { Button { model.screen = "home"; model.error = nil } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Protegia.secondary).font(Protegia.font(12)) }
                    if let device = model.deviceCode { deviceView(device) }
                    else if model.screen == "setup" && model.allowsDeveloperSetup { setup }
                    else if model.screen == "preferences" { preferences }
                    else if model.screen == "projects" { projects }
                    else if model.screen == "files" { files }
                    else { home }
                    if model.busy { HStack(alignment: .top, spacing: 9) { ProgressView().controlSize(.small); Text(model.status).font(Protegia.font(12)).foregroundStyle(Protegia.secondary); Spacer(); Button("Cancel") { model.cancel() }.font(Protegia.font(10)) } }
                    if let error = model.error { Text(error).font(Protegia.font(12)).foregroundStyle(Protegia.destructive).textSelection(.enabled).padding(11).frame(maxWidth: .infinity, alignment: .leading).background(Protegia.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: 8)) }
                }.padding(Protegia.spaceLG)
            } }
            if selectedTab == "Default" {
                ProtegiaDivider()
                HStack {
                    Circle().fill(model.pickerEnabled ? Protegia.accent : Protegia.tertiary).frame(width: 5, height: 5)
                    Text(model.pickerEnabled ? "Snippets picker is on" : "Snippets picker is off").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
                    Spacer()
                    Button("Preferences…") { model.screen = "preferences" }.buttonStyle(.plain).font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
                }.padding(.horizontal, Protegia.spaceLG).padding(.vertical, 13)
            }
        }.frame(width: 420, height: selectedTab == "Preview" ? 480 : 620).background(Protegia.base)
        .foregroundStyle(Protegia.text).font(Protegia.font(14)).tint(Protegia.accent).preferredColorScheme(.dark)
        .onChange(of: selectedTab) { _, tab in onTabChange?(tab) }
        .onChange(of: model.screen) { _, screen in
            search = ""
            if screen != "home" { selectedTab = "Default" }
        }
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: Protegia.spaceBase) {
            if let index = model.activeIndex {
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.isGitHubConnected ? "ACTIVE PROJECT" : "CACHED PROJECT · GITHUB SIGNED OUT").font(Protegia.font(10, bold: true)).tracking(1.1).foregroundStyle(Protegia.secondary)
                    HStack {
                        Image(systemName: "folder").foregroundStyle(semanticGreen)
                        Menu { ForEach(model.indices, id: \.repository.id) { saved in Button(saved.repository.full_name) { model.select(saved.repository.id) } } } label: { Text(index.repository.full_name).font(Protegia.font(14, bold: true)) }.menuStyle(.borderlessButton)
                    }
                    HStack { Text("\(model.tokens.count) definitions · \(index.repository.id == 0 ? "Sample tokens" : index.repository.default_branch)"); Spacer(); if index.repository.id != 0 { Button { model.refreshTokens(index.repository) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(model.busy) } }.font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
                }.padding(13).background(Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.cardRadius))
                if model.needsColorRefresh {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color previews need an updated token cache.")
                            .font(Protegia.font(11, bold: true))
                        Button(!model.isGitHubConnected ? "Connect GitHub to update colors" : "Refresh color previews") {
                            if !model.isGitHubConnected { model.connectGitHub() }
                            else { model.refreshTokens(index.repository) }
                        }
                        .buttonStyle(.plain).font(Protegia.font(11)).foregroundStyle(semanticGreen).disabled(model.busy)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if index.repository.id != 0 {
                    Button { model.chooseFiles(index.repository) } label: { Label("Edit token files", systemImage: "doc.text") }.buttonStyle(.plain).font(Protegia.font(12)).foregroundStyle(Protegia.secondary).disabled(model.busy)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your system. Wherever you type.").font(Protegia.font(18, bold: true))
                    Text("Type your trigger (default: --) in a compatible text field, find a definition, and press Return to insert its name.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !model.pickerEnabled { Button(model.permissionGranted ? "Start system-wide picker" : "Allow Accessibility") { model.enablePicker() }.buttonStyle(ProtegiaButtonStyle()).tint(semanticGreen).frame(maxWidth: .infinity) }
                if let feedback = model.pickerFeedback { Text(feedback).font(Protegia.font(12)).foregroundStyle(Protegia.secondary) }
                if let notice = model.pickerNotice { Text(notice).font(Protegia.font(12)).foregroundStyle(Protegia.secondary) }
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(Protegia.secondary); TextField("Find a token…", text: $search).textFieldStyle(.plain) }.padding(9).background(Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.controlRadius))
                let filtered = model.tokens.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.source.localizedCaseInsensitiveContains(search) }
                if filtered.isEmpty { Text("No matching definitions.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary) }
                LazyVStack(spacing: 0) { ForEach(filtered.prefix(60)) { token in
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(token.name, forType: .string); model.status = "Copied \(token.name)" } label: {
                        HStack(spacing: 9) { TokenBadge(token: token, tokens: model.resolutionTokens); VStack(alignment: .leading, spacing: 4) { Text(token.name).font(.system(size: 11, design: .monospaced)).lineLimit(1); Text(TokenPreview.definition(token, tokens: model.resolutionTokens)).font(Protegia.font(10)).foregroundStyle(Protegia.secondary).lineLimit(1) }; Spacer(); Image(systemName: "doc.on.doc").font(Protegia.font(12)).foregroundStyle(Protegia.tertiary) }.padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Copy \(token.name)")
                } }
                if filtered.count > 60 { Text("Showing 60 of \(filtered.count). Search to narrow the list.").font(Protegia.font(10)).foregroundStyle(Protegia.secondary) }
                if !model.status.isEmpty && !model.busy { Text(model.status).font(Protegia.font(10)).foregroundStyle(Protegia.secondary) }
            } else {
                Image(systemName: "number").font(Protegia.font(35, bold: true)).foregroundStyle(semanticGreen).padding(.top, 14)
                Text("Your design system,\nright at your fingertips.").font(Protegia.font(28, bold: true)).tracking(-0.6)
                Text("Connect GitHub, choose a project, and bring its semantic names into the apps you already use.").font(Protegia.font(14)).foregroundStyle(Protegia.secondary).lineSpacing(4)
                VStack(alignment: .leading, spacing: Protegia.spaceBase) { onboardingRow("1", "Connect your GitHub account"); onboardingRow("2", "Choose a design-system project"); onboardingRow("--", "Reference tokens wherever you type") }.padding(.vertical, 9)
            }
            if !model.isGitHubConnected {
                Button { model.connectGitHub() } label: { Label("Connect GitHub", systemImage: "link").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(ProtegiaButtonStyle()).tint(semanticGreen).disabled(model.busy)
                Text("GitHub sign-in ends when the app restarts, including after updates. Reconnect to import or refresh; cached snippets still work.").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
                if model.activeIndex == nil { Button("Explore with sample tokens") { model.sample() }.buttonStyle(.plain).font(Protegia.font(12)).foregroundStyle(Protegia.secondary).frame(maxWidth: .infinity) }
            } else {
                Button { model.screen = "projects" } label: { Label("Choose another project", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(ProtegiaButtonStyle(variant: .outline)).disabled(model.busy)
                Text("Connected as @\(model.account ?? "")").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
            }
        }
    }
    private func onboardingRow(_ symbol: String, _ title: String) -> some View { HStack(spacing: 11) { Text(symbol).font(Protegia.font(12, bold: true)).foregroundStyle(semanticGreen).frame(width: 24, height: 24).background(semanticGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 6)); Text(title).font(Protegia.font(12)) } }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect the GitHub App").font(Protegia.font(24, bold: true))
            Text("One-time developer setup for this preview. Published builds will include these public settings, so users only see Connect GitHub.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
            VStack(alignment: .leading, spacing: 8) { Text("Public Client ID").font(Protegia.font(12)).foregroundStyle(Protegia.secondary); TextField("Iv1.…", text: $model.clientID) }.textFieldStyle(ProtegiaInputStyle())
            VStack(alignment: .leading, spacing: 8) { Text("GitHub App slug").font(Protegia.font(12)).foregroundStyle(Protegia.secondary); TextField("semantic-tokens", text: $model.appSlug) }.textFieldStyle(ProtegiaInputStyle())
            Text("Register a GitHub App with Contents: read-only, enable Device Flow, and disable webhooks. No client secret is needed in this app.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary).lineSpacing(3)
            Link("Register a GitHub App ↗", destination: URL(string: "https://github.com/settings/apps/new")!)
            Button("Save configuration") { model.saveConfiguration() }.buttonStyle(ProtegiaButtonStyle()).tint(semanticGreen)
        }
    }
    private var projects: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose your project").font(Protegia.font(24, bold: true))
            Text("Choose a repository, then select the file that defines its design tokens.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
            TextField("Search repositories…", text: $search).textFieldStyle(ProtegiaInputStyle())
            let matches = model.repositories.filter { search.isEmpty || $0.full_name.localizedCaseInsensitiveContains(search) }
            if !model.repositories.isEmpty {
                HStack { Text("\(matches.count) repositories"); Spacer(); Text(model.account.map { "@" + $0 } ?? "GitHub") }.font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
            }
            ForEach(matches) { repo in
                Button { model.chooseFiles(repo) } label: { HStack { Image(systemName: repo.private ? "lock" : "folder").foregroundStyle(Protegia.secondary); VStack(alignment: .leading, spacing: 4) { Text(repo.full_name).font(Protegia.font(12, bold: true)); Text("\(repo.private ? "Private" : "Public") · \(repo.default_branch)").font(Protegia.font(10)).foregroundStyle(Protegia.secondary) }; Spacer(); Image(systemName: "chevron.right").font(Protegia.font(10)).foregroundStyle(Protegia.secondary) }.padding(11).background(Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.controlRadius)) }.buttonStyle(.plain).disabled(model.busy)
            }
            if !model.repositories.isEmpty && matches.isEmpty {
                Text("No repositories match “\(search)”.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
                Button("Clear search") { search = "" }.buttonStyle(.plain)
            }
            if model.repositories.isEmpty && !model.busy && model.error == nil { Text("GitHub hasn’t shared any repositories with DesignSnippets yet. Grant access to your projects below. This list refreshes when you return.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary) }
            Button("Manage repository access on GitHub ↗") { model.installGitHubApp() }.buttonStyle(ProtegiaButtonStyle(variant: .outline))
            Button("Refresh project list") { model.refreshRepositories() }.disabled(model.busy)
        }
    }
    private var files: some View {
        VStack(alignment: .leading, spacing: Protegia.spaceBase) {
            Text("Choose your token file").font(Protegia.font(24, bold: true))
            if let repo = model.selectedRepository {
                Label(repo.full_name, systemImage: "folder").font(Protegia.font(14, bold: true))
                Text("Reading from \(repo.default_branch)").font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
            }
            Text("Choose the stylesheet that defines your design system. Nearby palette files may also be read to resolve color previews.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("File paths · one per line").font(Protegia.font(12))
                TextEditor(text: $model.tokenFilePaths).font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10).frame(height: 92)
                    .background(Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.controlRadius))
                    .accessibilityLabel("Token file paths").disabled(model.busy)
            }
            Text("For Protegia, use src/styles/theme.css. Paths are relative to the repository root.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
            HStack(spacing: 8) {
                ForEach(["src/styles/theme.css", "tokens.json"], id: \.self) { path in
                    Button(path) { model.tokenFilePaths = path }.font(Protegia.font(10)).buttonStyle(.plain).foregroundStyle(Protegia.accent).disabled(model.busy)
                }
            }
            Button { model.importSelectedFiles() } label: { Label("Load design tokens", systemImage: "arrow.down.doc").frame(maxWidth: .infinity) }.buttonStyle(ProtegiaButtonStyle()).disabled(model.busy || model.tokenFilePaths.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("CSS variables, classes, token JSON, and TypeScript icon exports/catalogs. Enter one repository path or GitHub file link per line. Refresh reuses these files.").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
        }
    }
    private func deviceView(_ code: DeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Finish connecting on GitHub").font(Protegia.font(24, bold: true))
            Text("Enter this one-time code in the browser window. You’ll approve access on GitHub.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
            Text(code.user_code).font(.system(size: 29, weight: .medium, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity).padding(19).background(Protegia.level1, in: RoundedRectangle(cornerRadius: 8))
            Button("Copy code") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code.user_code, forType: .string) }
            Link("Open GitHub authorization ↗", destination: URL(string: "https://github.com/login/device")!)
        }
    }
    private var preferences: some View {
        VStack(alignment: .leading, spacing: Protegia.spaceBase) {
            Text("Preferences").font(Protegia.font(24, bold: true))
            ProtegiaList {
                ProtegiaListItem(title: "Project folder", detail: model.activeIndex?.repository.full_name ?? "Choose a project first") {
                    Text(model.checkoutPath.isEmpty ? "No folder selected" : model.checkoutPath)
                        .font(Protegia.font(11)).foregroundStyle(Protegia.secondary).lineLimit(2)
                    Button(model.checkoutPath.isEmpty ? "Choose folder…" : "Change folder…") {
                        if let path = model.chooseLocalCheckout() { model.configureLocalCheckout(path) }
                    }.buttonStyle(ProtegiaButtonStyle(variant: .outline))
                        .disabled(model.activeIndex?.repository.id == nil || model.activeIndex?.repository.id == 0)
                    if let error = model.folderError { Text(error).font(Protegia.font(11)).foregroundStyle(Protegia.destructive) }
                }
                ProtegiaDivider()
                ProtegiaListItem(title: "Compatible apps", detail: "Choose where the picker appears. Password fields are excluded.") {
                    Toggle("Use in all compatible apps", isOn: $model.allApps).toggleStyle(.switch).font(Protegia.font(12))
                    if !model.allApps {
                        ForEach(model.supportedApps, id: \.id) { app in
                            Toggle(app.name, isOn: Binding(get: { model.enabledApps.contains(app.id) }, set: { enabled in
                                if enabled { model.enabledApps.insert(app.id) } else { model.enabledApps.remove(app.id) }
                            })).toggleStyle(.checkbox).font(Protegia.font(12))
                        }
                        if model.enabledApps.isEmpty { Text("Select an app or enable all compatible apps.").font(Protegia.font(11)).foregroundStyle(Protegia.secondary) }
                    }
                }
                ProtegiaDivider()
                ProtegiaListItem(title: "Accessibility", detail: model.permissionGranted ? "Access granted" : "Access needed to insert snippets") {
                    if let notice = model.pickerNotice { Text(notice).font(Protegia.font(11)).foregroundStyle(Protegia.secondary) }
                    if model.pickerRequested {
                        Button("Pause picker") { model.pausePicker() }.buttonStyle(ProtegiaButtonStyle(variant: .outline))
                    }
                    if !model.pickerEnabled {
                        Button(model.permissionGranted ? "Start picker" : "Allow Accessibility") { model.enablePicker() }.buttonStyle(ProtegiaButtonStyle())
                    }
                    Text("⌃⌥Space also opens the picker. Escape dismisses it.").font(Protegia.font(11)).foregroundStyle(Protegia.secondary)
                }
                ProtegiaDivider()
                ProtegiaListItem(title: "GitHub", detail: model.isGitHubConnected ? "Connected as @\(model.account ?? "")" : "Signed out · cached snippets remain available") {
                    if model.isGitHubConnected {
                        Button("Disconnect & clear cached tokens", role: .destructive) { model.disconnect() }
                            .buttonStyle(ProtegiaButtonStyle(variant: .outline))
                    } else {
                        Button("Connect GitHub") { model.connectGitHub() }.buttonStyle(ProtegiaButtonStyle()).disabled(model.busy)
                    }
                    if model.allowsDeveloperSetup { Button("GitHub App configuration…") { model.screen = "setup" }.buttonStyle(.plain) }
                }
                ProtegiaDivider()
                ProtegiaListItem(title: "Updates", detail: "Version \(appVersion)") {
                    Button("Check for Updates…") { model.checkForUpdates?() }
                        .buttonStyle(ProtegiaButtonStyle(variant: .outline)).disabled(!model.canCheckForUpdates)
                    if !model.updatesConfigured { Text("Updates are unavailable in this development build.").font(Protegia.font(11)).foregroundStyle(Protegia.secondary) }
                }
            }
        }
    }
}
