import AppKit
import SwiftUI
import CoreText

/// Native mapping of Protegia.sys dark tokens. Source snapshot: Resources/DesignSystem/protegia-theme.css.
/// Component contracts: Protegia/src/app/components/ui/{button,input}.tsx.
enum Protegia {
    static let base = color(24, 24, 27)       // --color-bg-base / neutral-900
    static let level1 = color(39, 39, 42)     // --color-bg-level1 / neutral-800
    static let level2 = color(63, 63, 69)     // --color-bg-level2 / neutral-700
    static let text = color(250, 250, 250)   // --color-text-primary / neutral-50
    static let secondary = color(212, 212, 216) // --color-text-secondary / neutral-300
    static let tertiary = color(113, 113, 121)  // --color-text-tertiary / neutral-500
    static let muted = color(161, 161, 169)     // --color-interactive-muted / neutral-400
    static let accent = color(0, 255, 119)   // --color-primary-green
    static let border = color(39, 39, 42)   // --color-border-default
    static let primary = Color.white       // --color-interactive-primary
    static let inverse = Color.black       // --color-text-on-primary
    static let destructive = color(240, 28, 30) // --color-feedback-destructive
    static let cardRadius: CGFloat = 8     // --radius-card
    static let controlRadius: CGFloat = 8  // --radius-md
    static let panelRadius: CGFloat = 14   // --radius-xl
    static let spaceXS: CGFloat = 8
    static let spaceSM: CGFloat = 12
    static let spaceBase: CGFloat = 16
    static let spaceLG: CGFloat = 24
    static func color(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1) }
    static func font(_ size: CGFloat, bold: Bool = false) -> Font { .custom(bold ? "Lato-Bold" : "Lato-Regular", fixedSize: size) }
    static func registerFonts() {
        for name in ["Lato-Regular", "Lato-Bold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
}
struct ProtegiaButtonStyle: ButtonStyle {
    enum Variant { case primary, outline }
    var variant: Variant = .primary
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Protegia.font(14, bold: true))
            .padding(.horizontal, Protegia.spaceBase)
            .frame(minHeight: 36)
            .foregroundStyle(variant == .primary ? Protegia.inverse : Protegia.text)
            .background(variant == .primary ? Protegia.primary : Protegia.base, in: RoundedRectangle(cornerRadius: Protegia.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Protegia.controlRadius).stroke(variant == .outline ? Protegia.level2 : .clear, lineWidth: 1))
            .opacity(!enabled ? 0.5 : configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Protegia.controlRadius))
    }
}
struct ProtegiaInputStyle: TextFieldStyle {
    @FocusState private var focused: Bool
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain)
            .font(Protegia.font(14)).foregroundStyle(Protegia.text)
            .padding(.horizontal, Protegia.spaceSM).frame(height: 36)
            .background(Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Protegia.controlRadius).stroke(focused ? Protegia.secondary : Protegia.border, lineWidth: 1))
            .focused($focused)
    }
}
struct ProtegiaDivider: View {
    var body: some View { Rectangle().fill(Protegia.border).frame(height: 1) }
}
