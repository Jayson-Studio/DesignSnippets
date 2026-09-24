import AppKit
import SwiftUI

@main struct PickerTests {
    @MainActor static func main() {
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
        let rgbTokens = TokenParser.parse(":root { --carbon-400: rgba(39,39,42,1); --color-primary: var(--carbon-400); --border: 1px solid rgb(39 39 42); --radius: 8px; }", source: "theme.css")
        func subtitle(_ name: String) -> String { TokenPreview.pickerDefinition(rgbTokens.first { $0.name == name }!, tokens: rgbTokens) }
        precondition(subtitle("--color-primary") == "Carbon 400")
        precondition(subtitle("--carbon-400") == "Color")
        precondition(subtitle("--border") == "1px solid")
        precondition(subtitle("--radius") == "8px")
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
        precondition(TokenPreview.radius(TokenPreview.resolved(colors.first { $0.name == "--radius-sm" }!, tokens: colors)) == 6)
        let cyclic = [DesignToken(name: "--a", value: "var(--b)", kind: "Color", source: "test"), DesignToken(name: "--b", value: "var(--a)", kind: "Color", source: "test")]
        precondition(TokenPreview.color(TokenPreview.resolved(cyclic[0], tokens: cyclic)) == nil)

        let textToken = DesignToken(name: "--text-heading", value: #"{"fontSize":"24px","fontWeight":600}"#, kind: "Typography", source: "tokens.json")
        precondition(TokenPreview.definition(textToken,tokens: []) == "24px · Semibold")
        let fullText = DesignToken(name: "--text-h3", value: #"{"fontSize":"24px","fontWeight":600,"letterSpacing":"0.2px","lineHeight":"32px","fontFamily":["Inter","sans-serif"]}"#, kind: "Typography", source: "tokens.json")
        precondition(TokenPreview.pickerDefinition(fullText, tokens: []) == "24px · Semibold · Spacing 0.2px · Line height 32px · Inter, sans-serif")
        let cssTypography = TokenParser.parse("""
        :root { --text-h3: var(--text-h3-sm); --text-h3-sm: 24px; --font-family-body: 'Lato', sans-serif; --font-weight-bold: 700; }
        @layer base { h3 { font-family: var(--font-family-body); font-size: var(--text-h3); font-weight: var(--font-weight-bold); line-height: 1.5; } }
        """, source: "theme.css")
        let heading = cssTypography.first { $0.name == "--text-h3" }!
        precondition(TokenPreview.pickerDefinition(heading, tokens: cssTypography) == "24px · Bold · Line height 1.5 · 'Lato', sans-serif")
        precondition(TokenPreview.property(TokenPreview.typography(heading, tokens: cssTypography)?["fontWeight"]) == "700")
        let ambiguous = TokenParser.parse(":root { --size: 24px; } h3 { font-size: var(--size); font-weight: 700; } p { font-size: var(--size); font-weight: 400; }", source: "theme.css")
        precondition(ambiguous.first?.typography?["fontWeight"] == nil)
        let dimensionToken = DesignToken(name: "--text-body", value: #"{"fontSize":{"value":16,"unit":"px"},"fontWeight":400}"#, kind: "Typography", source: "tokens.json")
        precondition(TokenPreview.definition(dimensionToken,tokens: []) == "16px · Regular")
        precondition(TokenPreview.definition(accent,tokens: colors) == "Red · #ff0000")
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
        precondition(PickerPlacement.origin(anchor: top, visibleFrame: screen).y == 542)
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
        precondition(positions.origin(app: "editor-a", display: "right", frame: screen) == CGPoint(x: 1082, y: 8))
        positions.remove(app: "editor-a", display: "left")
        precondition(positions.origin(app: "editor-a", display: "left", frame: leftDisplay) == nil)
        precondition(positions.origin(app: "editor-a", display: "right", frame: screen) != nil)
        print("Picker permission, live filtering, and multi-display placement tests passed")
    }
}
