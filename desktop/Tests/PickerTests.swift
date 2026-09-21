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
        precondition(state.appendQuery("é /: ") && state.query == "é /: ")
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

        // Arrow navigation preserves the filtered query and wraps within its results.
        state.query = "border"; state.selected = 0
        state.moveSelection(1)
        precondition(state.selected == 1 && state.query == "border" && state.matches.count == 2)
        state.moveSelection(1); precondition(state.selected == 0)
        state.moveSelection(-1); precondition(state.selected == 1)
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

        let field = CGRect(x: 150, y: 200, width: 400, height: 100)
        let glyph = CGRect(x: 180, y: 230, width: 8, height: 20)
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
        precondition(PickerPlacement.origin(anchor: top, visibleFrame: screen).y == 504)
        let right = PickerPlacement.origin(anchor: CGRect(x: 1400, y: 300, width: 10, height: 20), visibleFrame: screen)
        precondition(right.x + 385 <= screen.maxX - 8)
        let leftDisplay = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let converted = PickerPlacement.appKitRect(CGRect(x: -1200, y: 580, width: 10, height: 20), desktopTop: 900)
        precondition(converted == CGRect(x: -1200, y: 300, width: 10, height: 20))
        precondition(PickerPlacement.origin(anchor: converted, visibleFrame: leftDisplay) == CGPoint(x: -1200, y: 328))
        let upperDisplay = CGRect(x: 0, y: 900, width: 1440, height: 900)
        let upperAnchor = PickerPlacement.appKitRect(CGRect(x: 100, y: -420, width: 0, height: 20), desktopTop: 900)
        precondition(PickerPlacement.origin(anchor: upperAnchor, visibleFrame: upperDisplay) == CGPoint(x: 100, y: 1328))
        print("Picker permission, live filtering, and multi-display placement tests passed")
    }
}
