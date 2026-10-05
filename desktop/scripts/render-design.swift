import AppKit
import SwiftUI
import CoreText

@main struct RenderDesign {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        for name in ["Lato-Regular", "Lato-Bold"] {
            let url = URL(fileURLWithPath: "desktop/Resources/Fonts/\(name).ttf")
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let directory = URL(fileURLWithPath: "desktop/build/design-previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func render<V: View>(_ view: V, name: String, mutate: (() -> Void)? = nil) throws {
            let host = NSHostingView(rootView: view)
            let size = name.hasPrefix("token-picker") ? NSSize(width: PickerLayout.width, height: PickerLayout.height)
                : NSSize(width: 420, height: name == "preview-menu" ? 480 : 620)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            if let mutate {
                mutate()
                RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            }
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SemanticError("Could not render \(name)") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SemanticError("Could not encode \(name)") }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
        let model = AppModel(preview: true)
        try render(SemanticPanel(model: model, appVersion: "0.3.11"), name: "onboarding")
        model.screen = "setup"
        try render(SemanticPanel(model: model), name: "github-setup")
        model.screen = "projects"
        model.account = "example-studio"
        model.repositories = [Repository(id: 1, full_name: "example-studio/design-system", default_branch: "main", private: true), Repository(id: 2, full_name: "example-studio/web-app", default_branch: "main", private: false)]
        try render(SemanticPanel(model: model), name: "repositories")
        model.selectedRepository = model.repositories[0]
        model.screen = "files"
        try render(SemanticPanel(model: model), name: "token-file-selection")
        model.account = nil
        model.screen = "preferences"
        try render(SemanticPanel(model: model), name: "preferences")
        let previewModel = AppModel(preview: true)
        let previewRepo = Repository(id: 42, full_name: "Example / DesignSnippets", default_branch: "main", private: false)
        let previewTokens = [
            DesignToken(name: "--icon-cui-dot-cycle", value: "8px", kind: "Dimension", source: "theme.css"),
            DesignToken(name: "--icon-cui-select-in", value: "200ms", kind: "Dimension", source: "theme.css"),
            DesignToken(name: "--icon-cui-select-out", value: "150ms", kind: "Dimension", source: "theme.css")
        ]
        previewModel.indices = [TokenIndex(repository: previewRepo, tokens: previewTokens, syncedAt: Date(), revision: "fixture")]
        previewModel.activeID = previewRepo.id
        try render(SemanticPanel(model: previewModel, appVersion: "0.3.14", initialTab: "Preview"), name: "preview-menu")
        let staleModel = AppModel(preview: true)
        let staleRepo = Repository(id: 43, full_name: "Jayson-Studio/mono", default_branch: "main", private: false)
        staleModel.indices = [TokenIndex(repository: staleRepo,
                                         tokens: [DesignToken(name: "--background-color-cui-accent", value: "var(--color-cui-orange-9)", kind: "Color", source: "packages/carrot-ui/src/theme.css")],
                                         syncedAt: Date(), revision: "old", sourceFiles: ["packages/carrot-ui/src/theme.css"])]
        staleModel.activeID = staleRepo.id
        try render(SemanticPanel(model: staleModel, appVersion: "0.3.17"), name: "stale-color-cache")
        let picker = PickerState()
        picker.project = "Protegia / design system"
        picker.query = ""
        picker.tokens = [DesignToken(name: "--color-border-default", value: "#27272a", kind: "Color", source: "src/styles/theme.css"), DesignToken(name: "--border-default", value: "1px solid…", kind: "Token", source: "src/styles/theme.css"), DesignToken(name: "--border-focus", value: "1px solid…", kind: "Token", source: "src/styles/theme.css")]
        picker.tokens = [DesignToken(name: "--color-accent", value: "oklch(62.7955% 0.257683 29.2339)", kind: "Color", source: "theme.css"), DesignToken(name: "--font-weight-bold", value: "700", kind: "Typography", source: "theme.css"), DesignToken(name: "--radius-card", value: "8px", kind: "Radius", source: "theme.css")]
        picker.tokens = [DesignToken(name: "--radius-cui-dot-cycle", value: "8px", kind: "Radius", source: "theme.css"), DesignToken(name: "--color-cui-primary", value: "var(--color-cui-red-10)", kind: "Color", source: "theme.css"), DesignToken(name: "--text-cui-primary", value: #"{"fontSize":"24px","fontWeight":600}"#, kind: "Typography", source: "theme.css")]
        picker.referenceTokens = [DesignToken(name: "--color-cui-red-10", value: "#ec5a72", kind: "Color", source: "scales.css")]
        try render(PickerView(state: picker), name: "token-picker")
        picker.openDefinition = { _ in }
        picker.hoveredTokenID = picker.tokens[2].id
        try render(PickerView(state: picker), name: "token-picker-hover-action")
        picker.hoveredTokenID = nil
        picker.tabDefinitions = [PickerTab(title: "Components", path: "components.json"), PickerTab(title: "Icons", path: "icons.json")]
        picker.toggleSettings()
        try render(PickerView(state: picker), name: "token-picker-settings-general")
        picker.settingsSection = .tokens("Icons")
        try render(PickerView(state: picker), name: "token-picker-settings-icons")
        picker.toggleSettings()
        picker.openError = "Could not locate this definition in the selected project folder."
        try render(PickerView(state: picker), name: "token-picker-open-error")
        picker.openError = nil
        picker.tabDefinitions = []
        picker.canInsert = false
        picker.approximatePosition = true
        try render(PickerView(state: picker), name: "token-picker-fallback")
        picker.manualPosition = true
        picker.manualOnly = true
        try render(PickerView(state: picker), name: "token-picker-saved-position")
        picker.tokens += [DesignToken(name: "--font-body", value: "16px", kind: "Typography", source: "theme.css"), DesignToken(name: "--font-weight-bold", value: "700", kind: "Typography", source: "theme.css")]
        try render(PickerView(state: picker), name: "token-picker-live-font") {
            for character in "font" { picker.appendQuery(String(character)) }
        }
        try render(PickerView(state: picker), name: "token-picker-live-empty") { picker.appendQuery("zz") }
        try render(PickerView(state: picker), name: "token-picker-live-backspace") {
            picker.deleteQueryCharacter(); picker.deleteQueryCharacter()
        }
        picker.query = ""
        picker.tokens = [DesignToken(name: "--carbon-400", value: "rgb(90, 90, 96)", kind: "Color", source: "theme.css"), DesignToken(name: "--color-text-accent", value: "var(--carbon-400)", kind: "Color", source: "theme.css"), DesignToken(name: "--text-h3", value: #"{"fontSize":"24px","fontWeight":600,"letterSpacing":"0.2px","lineHeight":"32px","fontFamily":"Inter"}"#, kind: "Typography", source: "theme.css")]
        try render(PickerView(state: picker), name: "token-picker-ranked-text") { picker.appendQuery("text") }
        picker.query = ""
        picker.tokens = [
            DesignToken(name: "--text-cui-secondary", value: ##"{"fontSize":"24px","fontWeight":600,"color":"#ffffff"}"##, kind: "Typography", source: "theme.css"),
            DesignToken(name: "--text-cui-primary", value: ##"{"fontSize":"88px","fontWeight":700,"color":"#ff7373"}"##, kind: "Typography", source: "theme.css")
        ]
        try render(PickerView(state: picker), name: "token-picker-text-styles")
        picker.query = ""
        picker.tokens = TokenParser.parse(":root { --text-cui-base: 1rem; --text-cui-base--line-height: 1.5rem; --text-cui-lg: 1.25rem; --text-cui-lg--line-height: 1.75rem; --text-cui-sm: 0.875rem; }", source: "theme.css")
        try render(PickerView(state: picker), name: "token-picker-rem-text") { picker.appendQuery("text") }
        picker.query = ""
        picker.tabDefinitions = [PickerTab(title: "Components", path: "components.json"), PickerTab(title: "Icons", path: "icons.json")]
        picker.tokens += [DesignToken(name: "components.button", value: "Button", kind: "Class", source: "components.json", section: "Components")]
        try render(PickerView(state: picker), name: "token-picker-components") { picker.selectSection("Components") }
        picker.tokens += [("close", "×"), ("check", "✓"), ("plus", "+"), ("arrow", "→"), ("star", "☆"), ("circle", "○")].map {
            DesignToken(name: "icons." + $0.0, value: $0.1, kind: "Icon", source: "icons.json", section: "Icons")
        }
        try render(PickerView(state: picker), name: "token-picker-icons") { picker.selectSection("Icons") }
        try render(PickerView(state: picker), name: "token-picker-new-tab") {
            picker.createTab()
            picker.tabTitle = "New components"
        }
        try render(PickerView(state: picker), name: "token-picker-new-tab-source") { picker.advanceTabCreation() }
        picker.selectSection("Foundations")
        if let flag = CommandLine.arguments.firstIndex(of: "--token-fixture"), CommandLine.arguments.indices.contains(flag + 1) {
            let indices = try JSONDecoder().decode([TokenIndex].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[flag + 1])))
            picker.tokens = indices.first?.tokens ?? []
            picker.query = "text-h3"
            try render(PickerView(state: picker), name: "token-picker-source-typography")
        }
        print("Rendered onboarding, GitHub setup, preferences, and token picker.")
    }
}
