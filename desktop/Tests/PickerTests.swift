import AppKit
import SwiftUI

final class ColorCacheProtocol: URLProtocol {
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

@main struct PickerTests {
    @MainActor static func main() async {
        let testDefaults = UserDefaults(suiteName: "DesignSnippets.GitHubConfigurationTests")!
        let arguments = testDefaults.volatileDomain(forName: UserDefaults.argumentDomain)
        testDefaults.setVolatileDomain(arguments.merging(["githubClientID": "Iv1.stale", "githubAppSlug": "old-preview"]) { _, value in value }, forName: UserDefaults.argumentDomain)
        let release = AppModel(preview: true, info: ["SemanticGitHubClientID": "Iv1.release", "SemanticGitHubAppSlug": "release-app", "SemanticDeveloperSetupAllowed": false], defaults: testDefaults)
        precondition(release.clientID == "Iv1.release" && release.appSlug == "release-app" && !release.allowsDeveloperSetup)
        let development = AppModel(preview: true, info: ["SemanticDeveloperSetupAllowed": true], defaults: testDefaults)
        precondition(development.clientID == "Iv1.stale" && development.appSlug == "old-preview")
        let brokenRelease = AppModel(preview: true, info: [:], defaults: testDefaults)
        brokenRelease.connectGitHub()
        precondition(brokenRelease.clientID.isEmpty && brokenRelease.screen != "setup" && brokenRelease.error != nil)
        testDefaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let freshPreview = AppModel(preview: true, info: ["SemanticDeveloperSetupAllowed": true], defaults: UserDefaults(suiteName: UUID().uuidString)!)
        freshPreview.connectGitHub()
        precondition(freshPreview.screen == "setup")
        // Command-line defaults supply enable intent without writing user preferences.
        let model = AppModel(preview: true)
        precondition(model.pickerRequested && model.allApps)
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("color-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let cachedModel = AppModel(preview: true, cacheURL: cacheURL)
        let cachedRepo = Repository(id: 43, full_name: "example/colors", default_branch: "main", private: false)
        let cachedColor = DesignToken(name: "--color-danger", value: "var(--red-10)", kind: "Color", source: "theme.css")
        var oldIndex = TokenIndex(repository: cachedRepo, tokens: [cachedColor], syncedAt: Date(), revision: "old")
        cachedModel.indices = [oldIndex]; cachedModel.activeID = cachedRepo.id
        precondition(cachedModel.needsColorRefresh)
        oldIndex.colorReferencesScanned = true
        cachedModel.indices = [oldIndex]
        precondition(!cachedModel.needsColorRefresh)
        cachedModel.indices = [TokenIndex(repository: cachedRepo, tokens: [cachedColor], syncedAt: Date(), revision: "old")]
        let cacheConfiguration = URLSessionConfiguration.ephemeral
        cacheConfiguration.protocolClasses = [ColorCacheProtocol.self]
        let cacheClient = GitHubClient(token: "test", session: URLSession(configuration: cacheConfiguration))
        func response(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }
        ColorCacheProtocol.handler = { request in
            let path = request.url!.path
            if path.contains("/commits/") { return (200, response(["sha": "new"])) }
            if path.hasSuffix("/theme.css") {
                let css = ":root { --color-danger: var(--red-10); }"
                return (200, response(["type": "file", "size": css.utf8.count, "encoding": "base64", "content": Data(css.utf8).base64EncodedString()]))
            }
            if path.hasSuffix("/contents") { return (200, response([["name": "theme.css", "type": "file", "size": 100], ["name": "scales.css", "type": "file", "size": 100]])) }
            let css = ":root { --red-10: #ec5a72; }"
            return (200, response(["type": "file", "size": css.utf8.count, "encoding": "base64", "content": Data(css.utf8).base64EncodedString()]))
        }
        try! await cachedModel.refreshCachedColors(using: cacheClient)
        precondition(cachedModel.activeIndex?.sourceFiles == ["theme.css"]
                     && cachedModel.activeIndex?.referenceTokens?.first?.value == "#ec5a72"
                     && cachedModel.activeIndex?.colorReferencesScanned == true
                     && !cachedModel.needsColorRefresh)
        let savedColorCache = try! JSONDecoder().decode([TokenIndex].self, from: Data(contentsOf: cacheURL))
        precondition(savedColorCache.first?.referenceTokens?.first?.value == "#ec5a72")
        let retained = cachedModel.activeIndex!
        ColorCacheProtocol.handler = { _ in (403, response(["message": "API limit"])) }
        do { try await cachedModel.refreshCachedColors(using: cacheClient); preconditionFailure("Expected refresh failure") }
        catch { precondition(cachedModel.activeIndex?.revision == retained.revision && cachedModel.activeIndex?.referenceTokens?.count == retained.referenceTokens?.count) }
        precondition(model.allowsPicker(in: "example.unlisted-editor"))
        var allowed = false
        var starts = 0
        var stops = 0
        model.checkPermission = { allowed }
        model.configureMonitor = { starts += 1; model.pickerEnabled = true }
        model.stopMonitor = { stops += 1; model.pickerEnabled = false }
        model.reconcilePicker()
        precondition(starts == 0 && model.pickerNotice != nil)
        allowed = true
        model.returnedToApp()
        precondition(starts == 1 && model.permissionGranted && model.pickerNotice == nil)
        model.returnedToApp()
        precondition(starts == 1)
        allowed = false
        model.returnedToApp()
        precondition(stops == 1 && !model.pickerEnabled && model.pickerRequested)
        allowed = true
        model.returnedToApp()
        precondition(starts == 2 && model.pickerEnabled)
        let state = PickerState()
        let utilityTokens = TokenParser.parse(":root { --background-color-cui-base-1: #eeeeee; --text-color-cui-primary: #222222; --border-color-cui-default: #cccccc; --ring-color-cui-focus: #ff0000; --color-cui-base-1: #ffffff; }", source: "theme.css")
        let utilityIndex = TokenIndex(repository: cachedRepo, tokens: utilityTokens, syncedAt: Date(), revision: "utilities")
        let utilityPicker = PickerState()
        utilityPicker.updateIndex(utilityIndex)
        utilityPicker.query = "bg"
        precondition(utilityPicker.matches.map(\.name) == ["bg-cui-base-1"])
        precondition(utilityPicker.matches.first?.value == "var(--background-color-cui-base-1)")
        precondition(Set(utilityIndex.displayTokens.map(\.name)).isSuperset(of: ["text-cui-primary", "border-cui-default", "ring-cui-focus"]))
        precondition(utilityIndex.displayTokens.filter { $0.name == "bg-cui-base-1" }.count == 1)
        let displayModel = AppModel(preview: true, cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        displayModel.indices = [utilityIndex]; displayModel.activeID = cachedRepo.id
        precondition(displayModel.tokens.contains { $0.name == "bg-cui-base-1" })
        displayModel.indices = [TokenIndex(repository: cachedRepo, tokens: [], syncedAt: Date(), revision: "utilities")]
        precondition(displayModel.tokens.isEmpty)
        precondition(PickerCapture.isScreenshotApp("com.screenshot.iscreenshoter"))
        precondition(PickerCapture.isScreenshotApp("com.screenshot.iscreenshoter.shoterHelper"))
        precondition(!PickerCapture.isScreenshotApp("com.example.editor"))
        var captureGate = PickerDismissalGate()
        captureGate.outsideInput()
        precondition(!captureGate.appActivated("com.screenshot.iscreenshoter") && !captureGate.pending)
        precondition(!captureGate.elapsed(frontBundleID: "com.example.editor"))
        captureGate.outsideInput()
        precondition(!captureGate.elapsed(frontBundleID: "com.screenshot.iscreenshoter.shoterHelper"))
        captureGate.outsideInput()
        precondition(captureGate.elapsed(frontBundleID: "com.example.editor"))
        captureGate.outsideInput()
        precondition(captureGate.appActivated("com.example.editor"))
        state.tokens = TokenParser.parse(":root { --border-default: red; --border-focus: blue; --space-small: 4px; }", source: "theme.css")
        precondition(state.matches.count == 3)
        precondition(state.appendQuery("border"))
        precondition(Set(state.matches.map(\.name)) == ["--border-default", "--border-focus"])
        state.selected = 1
        precondition(state.appendQuery("-f") && state.selected == 0)
        precondition(state.matches.map(\.name) == ["--border-focus"])
        state.deleteQueryCharacter()
        precondition(state.matches.count == 2)
        state.query = ""
        precondition(state.appendQuery("é/:") && state.query == "é/:")
        precondition(!state.appendQuery(" ") && state.query == "é/:")
        precondition(!state.appendQuery("\u{00a0}") && !state.appendQuery("#font"))
        let typography = PickerState()
        typography.tokens = TokenParser.parse(":root { --text-body: 16px; --font-weight-bold: 700; --border-default: red; }", source: "theme.css")
        for letter in "text" { precondition(typography.appendQuery(String(letter))) }
        precondition(typography.matches.map(\.name) == ["--text-body"])
        precondition(!typography.appendQuery(" "))
        typography.query = ""
        for letter in "FONT" { precondition(typography.appendQuery(String(letter))) }
        precondition(typography.matches.map(\.name) == ["--font-weight-bold"])
        typography.deleteQueryCharacter()
        precondition(typography.matches.map(\.name) == ["--font-weight-bold"])
        let ranked = PickerState()
        ranked.tokens = TokenParser.parse(":root { --color-text-accent: red; --text-h3: 24px; --text: 16px; --text-body: 14px; }", source: "theme.css")
        ranked.query = "text"
        precondition(ranked.matches.map(\.name) == ["--text", "--text-body", "--text-h3", "--color-text-accent"])
        ranked.query = "TEXT"
        precondition(ranked.matches.first?.name == "--text")
        ranked.query = "--text"
        precondition(ranked.matches.map(\.name) == ["--text", "--text-body", "--text-h3"])
        ranked.query = ""
        precondition(ranked.matches == ranked.tokens)
        // The default tab keeps existing imports; added tabs display only their chosen file.
        let tabs = PickerState()
        tabs.tokens = TokenParser.parse(#"{"foundations":{"color":{"$value":"red"}},"components":{"button":{"$value":"button"}},"icons":{"check":{"$value":"✓","$type":"icon"}},"getting-started":{"install":{"$value":"setup"}}}"#, source: "tokens.json")
        precondition(tabs.sections == ["Foundations"] && tabs.matches.count == 4)
        let iconTab = PickerTab(title: "Icons", path: "icons.json")
        tabs.tabDefinitions = [iconTab]
        tabs.tokens += TokenParser.parse(#"{"check":{"$value":"✓","$type":"icon"}}"#, source: "icons.json")
        precondition(tabs.sections == ["Foundations", "Icons"] && tabs.matches.count == 4)
        let layout = PickerState()
        layout.tabDefinitions = [PickerTab(title: "Symbols", path: "icons.json"), PickerTab(title: "Icons", path: "components.json")]
        layout.tokens = [DesignToken(name: "check", value: "✓", kind: "Icon", source: "icons.json"),
                         DesignToken(name: "button", value: "Button", kind: "Class", source: "components.json")]
        layout.selectSection("Symbols")
        precondition(layout.usesIconGrid)
        layout.selectSection("Icons")
        precondition(!layout.usesIconGrid)
        tabs.query = "check"
        tabs.selected = 8
        tabs.moveSection(-1)
        precondition(tabs.activeSection == "Icons" && tabs.query == "check" && tabs.selected == 0)
        precondition(tabs.matches.map(\.name) == ["check"])
        tabs.moveSection(1)
        precondition(tabs.activeSection == "Foundations" && tabs.matches.map(\.name) == ["icons.check"])
        tabs.moveSelection(1)
        precondition(tabs.selected == 0)
        tabs.query = ""
        tabs.createTab()
        precondition(tabs.sections == ["Foundations", "Icons", "New tab"] && tabs.activeSection == "New tab")
        precondition(tabs.tabCreationStep == .title)
        precondition(tabs.displayTitle(for: "New tab") == "New tab")
        var importCancelled = false
        tabs.cancelTabImport = { importCancelled = true }
        tabs.tabBusy = true
        tabs.cancelTab()
        precondition(importCancelled && tabs.sections == ["Foundations", "Icons"] && tabs.activeSection == "Foundations")
        var requestedPath: String?
        var requestedTitle: String?
        tabs.addTab = { title, path in requestedTitle = title; requestedPath = path }
        tabs.createTab()
        tabs.submitTab()
        precondition(tabs.tabError == "Enter a title for this tab." && !tabs.tabBusy && requestedPath == nil)
        tabs.tabTitle = "Components"
        precondition(tabs.displayTitle(for: "New tab") == "Components")
        tabs.tabTitle = "1234567890123456789012345extra"
        precondition(tabs.tabTitle == "1234567890123456789012345")
        tabs.tabTitle = "Components"
        tabs.advanceTabCreation()
        precondition(tabs.tabCreationStep == .source && requestedPath == nil)
        tabs.returnToTabTitle()
        precondition(tabs.tabCreationStep == .title && tabs.tabTitle == "Components")
        tabs.advanceTabCreation()
        tabs.submitTab()
        precondition(tabs.tabError == "Enter a token file path." && requestedPath == nil && !tabs.tabBusy)
        tabs.tabFilePath = "src/components/button-tokens.json"
        tabs.submitTab()
        precondition(requestedTitle == "Components" && requestedPath == "src/components/button-tokens.json" && tabs.tabBusy)
        let componentsTab = PickerTab(title: requestedTitle!, path: requestedPath!)
        tabs.tabDefinitions.append(componentsTab)
        tabs.finishTab(componentsTab)
        precondition(!tabs.creatingTab && tabs.tabCreationStep == .title && tabs.activeSection == "Components" && tabs.tabTitle.isEmpty)
        precondition(tabs.sections == ["Foundations", "Icons", "Components"])
        precondition(PickerTab.title(for: "src/components/button-tokens.json", existing: [iconTab]) == "Button Tokens")
        precondition(PickerTab.title(for: "other/icons.css", existing: [iconTab]) == "Icons 2")
        // The Preview search field uses this handler for picker navigation and selection.
        let previewKeys = PickerState()
        previewKeys.tokens = state.tokens + [DesignToken(name: "--icon-check", value: "✓", kind: "Icon", source: "icons.json")]
        previewKeys.tabDefinitions = [iconTab]
        var previewChoice: String?
        previewKeys.choose = { previewChoice = $0.name }
        precondition(PreviewPickerKeyboard.handle(.downArrow, modifiers: [], state: previewKeys))
        precondition(previewKeys.selected == 1)
        precondition(PreviewPickerKeyboard.handle(.return, modifiers: [], state: previewKeys))
        precondition(previewChoice == "--border-focus")
        previewChoice = nil
        precondition(!PreviewPickerKeyboard.handle(.downArrow, modifiers: [.command], state: previewKeys))
        precondition(previewKeys.selected == 1)
        precondition(PreviewPickerKeyboard.handle(.rightArrow, modifiers: [], state: previewKeys))
        precondition(previewKeys.activeSection == "Icons")
        precondition(PreviewPickerKeyboard.handle(.tab, modifiers: [], state: previewKeys))
        precondition(previewChoice == "--icon-check")
        precondition(PreviewPickerKeyboard.handle(.leftArrow, modifiers: [], state: previewKeys))
        precondition(previewKeys.activeSection == "Foundations")
        previewKeys.query = "space"
        precondition(PreviewPickerKeyboard.handle(.escape, modifiers: [], state: previewKeys))
        precondition(previewKeys.query.isEmpty)
        precondition(!PreviewPickerKeyboard.handle("x", modifiers: [], state: previewKeys))
        previewKeys.selected = 2
        let repo = Repository(id: 1, full_name: "test/system", default_branch: "main", private: false)
        previewKeys.updateIndex(TokenIndex(repository: repo, tokens: TokenParser.parse(":root { --only: 4px; }", source: "theme.css"), syncedAt: Date(), revision: "one"))
        precondition(previewKeys.selected == 0 && previewKeys.matches.map(\.name) == ["--only"])
        previewKeys.updateIndex(TokenIndex(repository: repo, tokens: TokenParser.parse(#"{"check":{"$value":"✓","$type":"icon"}}"#, source: "icons.json"), syncedAt: Date(), revision: "two", pickerTabs: [iconTab]))
        precondition(previewKeys.activeSection == "Icons" && previewKeys.selected == 0)
        previewKeys.updateIndex(TokenIndex(repository: repo, tokens: [], syncedAt: Date(), revision: "empty"))
        precondition(previewKeys.activeSection == "Foundations" && previewKeys.sections == ["Foundations"])
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("index.json")
        let fileModel = AppModel(preview: true, cacheURL: cache)
        let imported = TokenIndex(repository: repo, tokens: TokenParser.parse(":root { --only: 4px; }", source: "theme.css"),
                                  syncedAt: Date(), revision: "existing", sourceFiles: ["theme.css"])
        fileModel.indices = [imported]; fileModel.activeID = repo.id
        var assignedTab: PickerTab?
        fileModel.addPickerTab(title: "Colors", path: "theme.css") { if case .success(let tab) = $0 { assignedTab = tab } }
        precondition(assignedTab?.title == "Colors" && fileModel.activeIndex?.pickerTabs == [assignedTab!])
        let cached = try! JSONDecoder().decode([TokenIndex].self, from: Data(contentsOf: cache))
        precondition(cached.first?.pickerTabs == [assignedTab!])
        var duplicateFailed = false
        fileModel.addPickerTab(title: "Another", path: "theme.css") { if case .failure = $0 { duplicateFailed = true } }
        precondition(duplicateFailed)
        var titleRejected = false
        fileModel.addPickerTab(title: "colors", path: "other.css") { if case .failure = $0 { titleRejected = true } }
        precondition(titleRejected)
        var longTitleRejected = false
        fileModel.addPickerTab(title: "12345678901234567890123456", path: "other.css") {
            if case .failure = $0 { longTitleRejected = true }
        }
        precondition(longTitleRejected)
        try? FileManager.default.removeItem(at: cache.deletingLastPathComponent())
        let cssSections = TokenParser.parse(":root { --icon-size: 16px; } .icon-check {} .button {}", source: "theme.css")
        precondition(cssSections.first { $0.name == "--icon-size" }?.pickerSection == "Foundations")
        precondition(cssSections.first { $0.name == ".icon-check" }?.pickerSection == "Icons")
        precondition(cssSections.first { $0.name == ".button" }?.pickerSection == "Components")
        let legacy = try! JSONDecoder().decode(DesignToken.self, from: Data(#"{"name":"--old","value":"4px","kind":"Dimension","source":"theme.css"}"#.utf8))
        precondition(legacy.pickerSection == "Foundations")
        let custom = DesignToken(name: "brand.logo", value: "Logo", kind: "Token", source: "tokens.json", section: "Brand")
        tabs.tokens.append(custom)
        tabs.selectSection("Foundations")
        precondition(!tabs.sections.contains("Brand"))
        precondition(tabs.matches.contains(custom))
        precondition(try! JSONDecoder().decode(DesignToken.self, from: JSONEncoder().encode(custom)) == custom)
        let rgbTokens = TokenParser.parse(":root { --carbon-400: rgba(39,39,42,1); --color-primary: var(--carbon-400); --border: 1px solid rgb(39 39 42); --radius: 8px; }", source: "theme.css")
        func subtitle(_ name: String) -> String { TokenPreview.pickerDefinition(rgbTokens.first { $0.name == name }!, tokens: rgbTokens) }
        precondition(subtitle("--color-primary") == "Carbon 400 · #27272A")
        precondition(subtitle("--carbon-400") == "Carbon 400 · #27272A")
        precondition(subtitle("--border") == "1px solid")
        precondition(subtitle("--radius") == "8px")
        let sass = TokenParser.parse("--color: #fff\n--spacing: 8px\n--color-danger: var(\n  --color\n)\n", source: "tokens.sass")
        precondition(sass.count == 3 && sass.first { $0.name == "--color" }?.value == "#fff"
                     && sass.first { $0.name == "--spacing" }?.value == "8px"
                     && TokenPreview.pickerDefinition(sass.first { $0.name == "--color-danger" }!, tokens: sass) == "Color · #FFFFFF")
        let radiusAlias = TokenParser.parse(":root { --radius-md: 8px; --border-radius: var(--radius-md); }", source: "theme.css")
        precondition(radiusAlias.first { $0.name == "--border-radius" }?.kind == "Radius")
        precondition(!state.appendQuery("\n") && !state.appendQuery("\u{F702}"))
        state.query = ""
        precondition(state.matches.count == 3)

        // Native fields, rich editor groups, and read-only/secure controls differ.
        precondition(PickerEditor.accepts(role: "AXTextArea", subrole: "", editable: false, writableSelection: false))
        precondition(PickerEditor.accepts(role: "AXGroup", subrole: "", editable: true, writableSelection: false))
        precondition(PickerEditor.accepts(role: "AXGroup", subrole: "", editable: false, writableSelection: true))
        precondition(!PickerEditor.accepts(role: "AXGroup", subrole: "", editable: false, writableSelection: false))
        precondition(!PickerEditor.accepts(role: "AXStaticText", subrole: "", editable: false, writableSelection: false))
        precondition(!PickerEditor.accepts(role: "AXTextField", subrole: kAXSecureTextFieldSubrole, editable: true, writableSelection: true))
        precondition(!PickerEditor.accepts(role: "AXSecureTextField", subrole: "", editable: true, writableSelection: true))
        // Deferred detection must account for # and characters typed during retries.
        let verified = PickerEditor.triggerRange(selection: CFRange(location: 12, length: 0), query: "border", hasHash: true, observed: "#border")
        precondition(verified?.location == 5)
        precondition(PickerEditor.triggerRange(selection: CFRange(location: 3, length: 0), query: "😀", hasHash: true, observed: "#😀")?.location == 0)
        precondition(PickerEditor.triggerRange(selection: CFRange(location: 12, length: 0), query: "border", hasHash: true, observed: "changed") == nil)
        precondition(PickerEditor.triggerRange(selection: nil, query: "", hasHash: true, observed: nil) == nil)
        precondition(PickerEditor.triggerRange(selection: CFRange(location: 0, length: 0), query: "", hasHash: true, observed: "#") == nil)
        precondition(PickerEditor.triggerRange(selection: CFRange(location: 5, length: 2), query: "", hasHash: false, observed: "") == nil)
        precondition(PickerEditor.triggerRange(selection: CFRange(location: 5, length: 0), query: "", hasHash: false, observed: "")?.location == 5)

        // Arrow navigation preserves the query and stops at each end of the list.
        state.query = "border"; state.selected = 0
        state.moveSelection(1)
        precondition(state.selected == 1 && state.query == "border" && state.matches.count == 2)
        state.moveSelection(1); precondition(state.selected == 1)
        state.moveSelection(-1); precondition(state.selected == 0)
        state.moveSelection(-1); precondition(state.selected == 0)
        let pointer = CGPoint(x: 100, y: 100)
        state.hoverSelection(1, at: pointer)
        precondition(state.selected == 1 && state.selectionFromPointer)
        state.moveSelection(-1, pointer: pointer)
        precondition(state.selected == 0 && !state.selectionFromPointer)
        state.hoverSelection(1, at: pointer)
        precondition(state.selected == 0) // Scrolling under a stationary pointer must not steal keyboard selection.
        state.hoverSelection(1, at: CGPoint(x: 101, y: 100))
        precondition(state.selected == 1 && state.selectionFromPointer)
        state.query = "no-result"; state.moveSelection(1); precondition(state.matches.isEmpty)
        let colors = TokenParser.parse(":root { --red: #ff0000; --accent: var(--red); --radius: 0.625rem; --radius-sm: calc(var(--radius) - 4px); }", source: "theme.css")
        let accent = colors.first { $0.name == "--accent" }!
        let red = TokenPreview.color(TokenPreview.resolved(accent, tokens: colors))!.usingColorSpace(.sRGB)!
        precondition(red.redComponent > 0.99 && red.greenComponent < 0.01)
        let oklch = TokenPreview.color("oklch(62.7955% 0.257683 29.2339)")!.usingColorSpace(.sRGB)!
        precondition(oklch.redComponent > 0.99 && oklch.greenComponent < 0.01 && oklch.blueComponent < 0.01)
        precondition(TokenPreview.color("rgb(100% 0% 0% / 50%)")!.alphaComponent == 0.5)
        precondition(TokenPreview.color("var(--missing)") == nil)
        precondition(TokenPreview.color("not-a-color") == nil)
        let danger = TokenParser.parse("""
        :root {
          --background-color-cui-danger: var(
            --color-cui-red-10
          );
          --background-color-cui-danger-subtle: var(--color-cui-red-3);
          --background-color-cui-danger-strong: var(--color-cui-red-11);
          --border-color-cui-danger: var(--color-cui-red-11);
          --text-color-cui-danger: var(--color-cui-red-11);
          --background-color-cui-danger-on: oklch(0.99 0 0);
          --text-color-cui-danger-on: oklch(0.99 0 0);
        }
        """, source: "theme.css")
        let redScale = TokenParser.parse(":root { --color-cui-red-3: #3a141e; --color-cui-red-10: #ec5a72; --color-cui-red-11: #ff949d; }", source: "scales.css")
        let dangerTokens = danger + redScale
        func dangerSubtitle(_ name: String) -> String { TokenPreview.pickerDefinition(danger.first { $0.name == name }!, tokens: dangerTokens) }
        precondition(dangerSubtitle("--background-color-cui-danger") == "Red 10 · #EC5A72")
        let chained = [DesignToken(name: "--color-cui-red-10", value: "var(--base-red)", kind: "Color", source: "scales.css"),
                       DesignToken(name: "--base-red", value: "#ec5a72", kind: "Color", source: "scales.css")]
        precondition(TokenPreview.pickerDefinition(danger[0], tokens: danger + chained) == "Red 10 · #EC5A72")
        let twoFolders = [DesignToken(name: "--color-danger", value: "var(--red-10)", kind: "Color", source: "a/theme.css"),
                          DesignToken(name: "--color-danger", value: "var(--red-10)", kind: "Color", source: "b/theme.css"),
                          DesignToken(name: "--red-10", value: "#111111", kind: "Color", source: "a/scales.css"),
                          DesignToken(name: "--red-10", value: "#222222", kind: "Color", source: "b/scales.css")]
        precondition(TokenPreview.pickerDefinition(twoFolders[0], tokens: twoFolders) == "Red 10 · #111111")
        precondition(TokenPreview.pickerDefinition(twoFolders[1], tokens: twoFolders) == "Red 10 · #222222")
        precondition(dangerSubtitle("--background-color-cui-danger-subtle") == "Red 3 · #3A141E")
        for name in ["--background-color-cui-danger-strong", "--border-color-cui-danger", "--text-color-cui-danger"] {
            precondition(dangerSubtitle(name) == "Red 11 · #FF949D")
            precondition(TokenPreview.colorPresentation(danger.first { $0.name == name }!, tokens: dangerTokens) != nil)
        }
        for name in ["--background-color-cui-danger-on", "--text-color-cui-danger-on"] {
            precondition(dangerSubtitle(name).hasPrefix("#"))
        }
        precondition(TokenPreview.radius(TokenPreview.resolved(colors.first { $0.name == "--radius-sm" }!, tokens: colors)) == 6)
        let cyclic = [DesignToken(name: "--a", value: "var(--b)", kind: "Color", source: "test"), DesignToken(name: "--b", value: "var(--a)", kind: "Color", source: "test")]
        precondition(TokenPreview.color(TokenPreview.resolved(cyclic[0], tokens: cyclic)) == nil)

        let textToken = DesignToken(name: "--text-heading", value: #"{"fontSize":"24px","fontWeight":600}"#, kind: "Typography", source: "tokens.json")
        precondition(TokenPreview.definition(textToken,tokens: []) == "24px · Semibold")
        let fullText = DesignToken(name: "--text-h3", value: #"{"fontSize":"24px","fontWeight":600,"letterSpacing":"0.2px","lineHeight":"32px","fontFamily":["Inter","sans-serif"]}"#, kind: "Typography", source: "tokens.json")
        precondition(TokenPreview.pickerDefinition(fullText, tokens: []) == "24px · Semibold · Spacing 0.2px · Line height 32px · Inter, sans-serif")
        let styledText = DesignToken(name: "--text-primary", value: #"{"fontSize":"88px","fontWeight":700,"color":"{brand.red}"}"#, kind: "Typography", source: "tokens.json")
        let brandRed = DesignToken(name: "brand.red", value: "#E83D4F", kind: "Color", source: "tokens.json")
        precondition(TokenPreview.isTextStyle(styledText))
        precondition(TokenPreview.typographyColor(styledText, tokens: [styledText, brandRed])?.usingColorSpace(.sRGB)?.redComponent == CGFloat(232.0 / 255.0))
        precondition(!TokenPreview.isTextStyle(brandRed))
        precondition(TokenPreview.color("rebeccapurple") != nil)
        precondition(TokenPreview.color("color(display-p3 1 0.5 0 / 0.8)")?.usingColorSpace(.displayP3)?.alphaComponent == 0.8)
        let cssTypography = TokenParser.parse("""
        :root { --text-h3: var(--text-h3-sm); --text-h3-sm: 24px; --font-family-body: 'Lato', sans-serif; --font-weight-bold: 700; --heading-color: #e83d4f; }
        @layer base { h3 { font-family: var(--font-family-body); font-size: var(--text-h3); font-weight: var(--font-weight-bold); line-height: 1.5; color: var(--heading-color); } }
        """, source: "theme.css")
        let heading = cssTypography.first { $0.name == "--text-h3" }!
        precondition(TokenPreview.isTextStyle(heading))
        precondition(TokenPreview.pickerDefinition(heading, tokens: cssTypography) == "24px · Bold · Line height 1.5 · 'Lato', sans-serif")
        precondition(TokenPreview.property(TokenPreview.typography(heading, tokens: cssTypography)?["fontWeight"]) == "700")
        precondition(TokenPreview.typographyColor(heading, tokens: cssTypography)?.usingColorSpace(.sRGB)?.redComponent == CGFloat(232.0 / 255.0))
        let namedSize = TokenParser.parse(":root { --size-h3: 24px; } h3 { font-size: var(--size-h3); font-weight: 600; }", source: "theme.css").first { $0.name == "--size-h3" }!
        precondition(TokenPreview.isTextStyle(namedSize))
        let ambiguous = TokenParser.parse(":root { --size: 24px; } h3 { font-size: var(--size); font-weight: 700; } p { font-size: var(--size); font-weight: 400; }", source: "theme.css")
        precondition(ambiguous.first?.typography?["fontWeight"] == nil)
        let dimensionToken = DesignToken(name: "--text-body", value: #"{"fontSize":{"value":16,"unit":"px"},"fontWeight":400}"#, kind: "Typography", source: "tokens.json")
        precondition(TokenPreview.definition(dimensionToken,tokens: []) == "16px · Regular")
        precondition(TokenPreview.definition(accent,tokens: colors) == "Red · #FF0000")
        let field = CGRect(x: 150, y: 200, width: 400, height: 100)
        let glyph = CGRect(x: 180, y: 230, width: 8, height: 20)
        precondition(PickerEditor.usesManualPosition(bundle: "com.openai.codex"))
        precondition(PickerEditor.trackedReplacementCount(bundle: "com.openai.codex", query: "font", hasHash: true, active: true) == 5)
        precondition(PickerEditor.trackedReplacementCount(bundle: "com.openai.codex", query: "", hasHash: true, active: true) == 1)
        precondition(PickerEditor.trackedReplacementCount(bundle: "com.openai.codex", query: "border", hasHash: false, active: true) == 6)
        precondition(PickerEditor.trackedReplacementCount(bundle: "com.openai.codex", query: "font", hasHash: true, active: false) == nil)
        precondition(PickerEditor.trackedReplacementCount(bundle: "another.app", query: "font", hasHash: true, active: true) == nil)
        precondition(PickerEditor.trackedReplacementCount(bundle: "com.openai.codex", query: "é", hasHash: true, active: true) == nil)
        precondition(PickerEditor.trackedReplacementCount(bundle: "com.openai.codex", query: "font size", hasHash: true, active: true) == nil)
        precondition(!PickerEditor.usesManualPosition(bundle: "com.openai.chat"))
        precondition(!PickerEditor.usesManualPosition(bundle: "com.apple.TextEdit"))
        precondition(PickerPlacement.anchor(glyph: glyph, caret: nil, field: field) == glyph)
        precondition(PickerPlacement.anchor(glyph: nil, caret: glyph, field: field) == glyph)
        precondition(PickerPlacement.anchor(glyph: nil, caret: nil, field: field) == field)
        precondition(PickerPlacement.anchor(glyph: .zero, caret: nil, field: field) == field)
        precondition(PickerPlacement.anchor(glyph: nil, caret: nil, field: nil) == nil)
        state.query = ""
        state.canInsert = false
        precondition(state.appendQuery("border") && state.matches.count == 2)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGRect(x: 200, y: 300, width: 10, height: 20)
        let above = PickerPlacement.origin(anchor: anchor, visibleFrame: screen)
        precondition(above == CGPoint(x: 200, y: 328))
        let top = CGRect(x: 200, y: 850, width: 10, height: 20)
        precondition(PickerPlacement.origin(anchor: top, visibleFrame: screen).y == top.minY - PickerLayout.height - 8)
        let right = PickerPlacement.origin(anchor: CGRect(x: 1400, y: 300, width: 10, height: 20), visibleFrame: screen)
        precondition(right.x + PickerLayout.width <= screen.maxX - 8)
        let leftDisplay = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let converted = PickerPlacement.appKitRect(CGRect(x: -1200, y: 580, width: 10, height: 20), screens: [screen, leftDisplay])
        precondition(converted == CGRect(x: -1200, y: 300, width: 10, height: 20))
        precondition(PickerPlacement.origin(anchor: converted, visibleFrame: leftDisplay) == CGPoint(x: -1200, y: 328))
        let upperDisplay = CGRect(x: 0, y: 900, width: 1440, height: 900)
        let upperAnchor = PickerPlacement.appKitRect(CGRect(x: 100, y: -420, width: 0, height: 20), screens: [screen, upperDisplay])
        precondition(PickerPlacement.origin(anchor: upperAnchor, visibleFrame: upperDisplay) == CGPoint(x: 100, y: 1328))
        // Remember only app/display coordinates, survive restart and rearrangement,
        // and never reuse Codex's placement in another editor or on another monitor.
        let suite = "PickerPositionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let positions = PickerPositionStore(defaults: defaults)
        let saved = CGPoint(x: -1200, y: 100)
        positions.save(saved, app: "editor-a", display: "left", frame: leftDisplay)
        let reopened = PickerPositionStore(defaults: UserDefaults(suiteName: suite)!)
        let restored = reopened.origin(app: "editor-a", display: "left", frame: leftDisplay)!
        precondition(abs(restored.x - saved.x) < 0.001 && abs(restored.y - saved.y) < 0.001)
        precondition(reopened.origin(app: "editor-b", display: "left", frame: leftDisplay) == nil)
        precondition(reopened.origin(app: "editor-a", display: "right", frame: screen) == nil)
        let resized = CGRect(x: 0, y: 900, width: 1024, height: 768)
        let moved = reopened.origin(app: "editor-a", display: "left", frame: resized)!
        precondition(resized.insetBy(dx: 8, dy: 8).contains(CGRect(origin: moved, size: PickerLayout.size)))
        positions.save(CGPoint(x: 99999, y: -99999), app: "editor-a", display: "right", frame: screen)
        precondition(positions.origin(app: "editor-a", display: "right", frame: screen) == CGPoint(x: screen.maxX - PickerLayout.width - 8, y: 8))
        positions.remove(app: "editor-a", display: "left")
        precondition(positions.origin(app: "editor-a", display: "left", frame: leftDisplay) == nil)
        precondition(positions.origin(app: "editor-a", display: "right", frame: screen) != nil)
        print("Picker permission, live filtering, and multi-display placement tests passed")
    }
}
