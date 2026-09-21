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
        func render<V: View>(_ view: V, name: String) throws {
            let host = NSHostingView(rootView: view)
            let size = name.hasPrefix("token-picker") ? NSSize(width: 385, height: 338) : NSSize(width: 420, height: 620)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SemanticError("Could not render \(name)") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SemanticError("Could not encode \(name)") }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
        let model = AppModel(preview: true)
        try render(SemanticPanel(model: model), name: "onboarding")
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
        let picker = PickerState()
        picker.project = "Protegia / design system"
        picker.query = ""
        picker.tokens = [DesignToken(name: "--color-border-default", value: "#27272a", kind: "Color", source: "src/styles/theme.css"), DesignToken(name: "--border-default", value: "1px solid…", kind: "Token", source: "src/styles/theme.css"), DesignToken(name: "--border-focus", value: "1px solid…", kind: "Token", source: "src/styles/theme.css")]
        picker.tokens = [DesignToken(name: "--color-accent", value: "oklch(62.7955% 0.257683 29.2339)", kind: "Color", source: "theme.css"), DesignToken(name: "--font-weight-bold", value: "700", kind: "Typography", source: "theme.css"), DesignToken(name: "--radius-card", value: "8px", kind: "Radius", source: "theme.css")]
        try render(PickerView(state: picker), name: "token-picker")
        picker.canInsert = false
        picker.approximatePosition = true
        try render(PickerView(state: picker), name: "token-picker-fallback")
        print("Rendered onboarding, GitHub setup, preferences, and token picker.")
    }
}
