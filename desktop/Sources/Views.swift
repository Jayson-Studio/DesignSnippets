import SwiftUI
import AppKit

let semanticGreen = Protegia.accent
struct SemanticPanel: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "number.square.fill").font(Protegia.font(26)).foregroundStyle(semanticGreen)
                Text("DesignSnippets").font(Protegia.font(18, bold: true))
                Spacer()
                Text("DESKTOP PREVIEW").font(Protegia.font(10, bold: true)).tracking(1).foregroundStyle(Protegia.secondary)
                Menu { Button("Check for Updates…") { model.checkForUpdates?() }.disabled(!model.canCheckForUpdates); Button("Preferences…") { model.screen = "preferences" }; Button("GitHub App setup…") { model.screen = "setup" }; ProtegiaDivider(); Button("Quit DesignSnippets") { NSApp.terminate(nil) } } label: { Image(systemName: "ellipsis.circle").font(Protegia.font(18)) }.menuStyle(.borderlessButton).frame(width: 23)
            }.padding(Protegia.spaceLG)
            ProtegiaDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: Protegia.spaceBase) {
                    if model.screen != "home" { Button { model.screen = "home"; model.error = nil } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Protegia.secondary).font(Protegia.font(12)) }
                    if let device = model.deviceCode { deviceView(device) }
                    else if model.screen == "setup" { setup }
                    else if model.screen == "preferences" { preferences }
                    else if model.screen == "projects" { projects }
                    else if model.screen == "files" { files }
                    else { home }
                    if model.busy { HStack(alignment: .top, spacing: 9) { ProgressView().controlSize(.small); Text(model.status).font(Protegia.font(12)).foregroundStyle(Protegia.secondary); Spacer(); Button("Cancel") { model.cancel() }.font(Protegia.font(10)) } }
                    if let error = model.error { Text(error).font(Protegia.font(12)).foregroundStyle(Protegia.destructive).textSelection(.enabled).padding(11).frame(maxWidth: .infinity, alignment: .leading).background(Protegia.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: 8)) }
                }.padding(Protegia.spaceLG)
            }
            ProtegiaDivider()
            HStack {
                Circle().fill(model.pickerEnabled ? Protegia.accent : Protegia.tertiary).frame(width: 5, height: 5)
                Text(model.pickerEnabled ? "# picker is on" : "# picker is off").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
                Spacer()
                Button("Preferences…") { model.screen = "preferences" }.buttonStyle(.plain).font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
            }.padding(.horizontal, Protegia.spaceLG).padding(.vertical, 13)
        }.frame(width: 420, height: 620).background(Protegia.base)
        .foregroundStyle(Protegia.text).font(Protegia.font(14)).tint(Protegia.accent).preferredColorScheme(.dark)
        .onChange(of: model.screen) { _, _ in search = "" }
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: Protegia.spaceBase) {
            if let index = model.activeIndex {
                VStack(alignment: .leading, spacing: 9) {
                    Text("ACTIVE PROJECT").font(Protegia.font(10, bold: true)).tracking(1.1).foregroundStyle(Protegia.secondary)
                    HStack {
                        Image(systemName: "folder").foregroundStyle(semanticGreen)
                        Menu { ForEach(model.indices, id: \.repository.id) { saved in Button(saved.repository.full_name) { model.select(saved.repository.id) } } } label: { Text(index.repository.full_name).font(Protegia.font(14, bold: true)) }.menuStyle(.borderlessButton)
                    }
                    HStack { Text("\(index.tokens.count) definitions · \(index.repository.id == 0 ? "Sample tokens" : index.repository.default_branch)"); Spacer(); if index.repository.id != 0 { Button { model.refreshTokens(index.repository) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(model.busy) } }.font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
                }.padding(13).background(Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.cardRadius))
                if index.repository.id != 0 {
                    Button { model.chooseFiles(index.repository) } label: { Label("Edit token files", systemImage: "doc.text") }.buttonStyle(.plain).font(Protegia.font(12)).foregroundStyle(Protegia.secondary).disabled(model.busy)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your system. Wherever you type.").font(Protegia.font(18, bold: true))
                    Text("Type # in a compatible text field, find a definition, and press Return to insert its name.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !model.pickerEnabled { Button(model.permissionGranted ? "Start system-wide picker" : "Allow Accessibility") { model.enablePicker() }.buttonStyle(ProtegiaButtonStyle()).tint(semanticGreen).frame(maxWidth: .infinity) }
                if let feedback = model.pickerFeedback { Text(feedback).font(Protegia.font(12)).foregroundStyle(Protegia.secondary) }
                if let notice = model.pickerNotice { Text(notice).font(Protegia.font(12)).foregroundStyle(Protegia.secondary) }
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(Protegia.secondary); TextField("Find a token…", text: $search).textFieldStyle(.plain) }.padding(9).background(Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.controlRadius))
                let filtered = index.tokens.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.source.localizedCaseInsensitiveContains(search) }
                if filtered.isEmpty { Text("No matching definitions.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary) }
                LazyVStack(spacing: 0) { ForEach(filtered.prefix(60)) { token in
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(token.name, forType: .string); model.status = "Copied \(token.name)" } label: {
                        HStack(spacing: 9) { TokenBadge(token: token, tokens: model.tokens); VStack(alignment: .leading, spacing: 4) { Text(token.name).font(.system(size: 11, design: .monospaced)).lineLimit(1); Text(token.source).font(Protegia.font(10)).foregroundStyle(Protegia.secondary).lineLimit(1) }; Spacer(); Image(systemName: "doc.on.doc").font(Protegia.font(12)).foregroundStyle(Protegia.tertiary) }.padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Copy \(token.name)")
                } }
                if filtered.count > 60 { Text("Showing 60 of \(filtered.count). Search to narrow the list.").font(Protegia.font(10)).foregroundStyle(Protegia.secondary) }
                if !model.status.isEmpty && !model.busy { Text(model.status).font(Protegia.font(10)).foregroundStyle(Protegia.secondary) }
            } else {
                Image(systemName: "number").font(Protegia.font(35, bold: true)).foregroundStyle(semanticGreen).padding(.top, 14)
                Text("Your design system,\nright at your fingertips.").font(Protegia.font(28, bold: true)).tracking(-0.6)
                Text("Connect GitHub, choose a project, and bring its semantic names into the apps you already use.").font(Protegia.font(14)).foregroundStyle(Protegia.secondary).lineSpacing(4)
                VStack(alignment: .leading, spacing: Protegia.spaceBase) { onboardingRow("1", "Connect your GitHub account"); onboardingRow("2", "Choose a design-system project"); onboardingRow("#", "Reference tokens wherever you type") }.padding(.vertical, 9)
            }
            if model.account == nil {
                Button { model.connectGitHub() } label: { Label("Connect GitHub", systemImage: "link").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(ProtegiaButtonStyle()).tint(semanticGreen).disabled(model.busy)
                Text("Sign in each time you open DesignSnippets. Your GitHub session is kept only until you quit.").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
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
            Text("Point DesignSnippets to the stylesheet that defines your design system. Only the files you choose are read.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
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
            Text("CSS variables, classes, and token JSON. Add another line if your system uses multiple files. Refresh will reuse these paths.").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
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
            Text("Make it part of your flow.").font(Protegia.font(24, bold: true))
            Toggle("Use in all compatible apps", isOn: $model.allApps).toggleStyle(.switch).font(Protegia.font(12))
            if !model.allApps {
            Text("USE ONLY IN THESE APPS").font(Protegia.font(10, bold: true)).tracking(1).foregroundStyle(Protegia.secondary)
            ForEach(model.supportedApps, id: \.id) { app in Toggle(app.name, isOn: Binding(get: { model.enabledApps.contains(app.id) }, set: { enabled in if enabled { model.enabledApps.insert(app.id) } else { model.enabledApps.remove(app.id) } })).toggleStyle(.checkbox).font(Protegia.font(12)) }
            }
            ProtegiaDivider()
            Text("The picker works across compatible apps by default. Turn off the switch to limit it to selected apps. Query text stays in memory and is never stored or sent to GitHub. Password fields are excluded. Some custom editors may not expose a compatible text field.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary).lineSpacing(3)
            Text(model.permissionGranted ? "Accessibility access granted" : "Accessibility access needed").font(Protegia.font(12, bold: true))
            if let notice = model.pickerNotice { Text(notice).font(Protegia.font(12)).foregroundStyle(Protegia.secondary) }
            if !model.allApps && model.enabledApps.isEmpty { Text("Select an app below the switch, or use all compatible apps.").font(Protegia.font(12)).foregroundStyle(Protegia.secondary) }
            if model.pickerRequested { Button("Pause token picker") { model.pausePicker() } }
            if !model.pickerEnabled { Button(model.permissionGranted ? "Start token picker" : "Allow Accessibility") { model.enablePicker() }.buttonStyle(ProtegiaButtonStyle()).tint(semanticGreen) }
            Text("Your picker setting is remembered when DesignSnippets restarts.").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
            Text("⌃⌥Space also opens the picker in a supported text field. Escape dismisses it without changing your text.").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
            ProtegiaDivider()
            Text("Updates").font(Protegia.font(12, bold: true))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Preview")").font(Protegia.font(10)).foregroundStyle(Protegia.secondary)
            Button("Check for Updates…") { model.checkForUpdates?() }.disabled(!model.canCheckForUpdates)
            if !model.updatesConfigured { Text("In-app updates are not available in this development build.").font(Protegia.font(10)).foregroundStyle(Protegia.secondary) }
            Button("GitHub App configuration…") { model.screen = "setup" }.buttonStyle(.plain).foregroundStyle(Protegia.secondary)
            if model.account != nil { Button("Disconnect GitHub & clear cached tokens", role: .destructive) { model.disconnect() }.font(Protegia.font(10)) }
        }
    }
}

