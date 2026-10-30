import AppKit
import SwiftUI
import CoreText

/// Native mapping of Protegia.sys light and dark tokens. Source snapshot: Resources/DesignSystem/protegia-theme.css.
/// Component contracts: Protegia/src/app/components/ui/{button,input}.tsx.
enum Protegia {
    static let base = adaptive(light: (250, 250, 250), dark: (24, 24, 27))
    static let level1 = adaptive(light: (244, 244, 245), dark: (39, 39, 42))
    static let level2 = adaptive(light: (228, 228, 231), dark: (63, 63, 69))
    static let text = adaptive(light: (24, 24, 27), dark: (250, 250, 250))
    static let secondary = adaptive(light: (82, 82, 90), dark: (212, 212, 216))
    static let tertiary = color(113, 113, 121)  // --color-text-tertiary / neutral-500
    static let muted = color(161, 161, 169)     // --color-interactive-muted / neutral-400
    static let accent = color(0, 255, 119)   // --color-primary-green
    static let border = adaptive(light: (228, 228, 231), dark: (39, 39, 42))
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
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
        })
    }
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
            .background(Protegia.base, in: RoundedRectangle(cornerRadius: Protegia.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Protegia.controlRadius).stroke(focused ? Protegia.secondary : Protegia.level2, lineWidth: 1))
            .focused($focused)
    }
}
struct ProtegiaDivider: View {
    var body: some View { Rectangle().fill(Protegia.border).frame(height: 1) }
}

/// Native grouped-list composition using Protegia's surface, divider and spacing tokens.
struct ProtegiaList<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.cardRadius))
            .clipShape(RoundedRectangle(cornerRadius: Protegia.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Protegia.cardRadius).stroke(Protegia.level2, lineWidth: 1))
    }
}
struct ProtegiaListItem<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Protegia.spaceXS) {
            Text(title).font(Protegia.font(12, bold: true)).foregroundStyle(Protegia.text)
            if let detail {
                Text(detail).font(Protegia.font(11)).foregroundStyle(Protegia.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }.padding(Protegia.spaceSM).frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// Mirrors the Input/SelectTrigger control height, inset, radius and border contract.
struct ProtegiaSelectLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: Protegia.spaceXS) {
            Text(title).lineLimit(1)
            Spacer(minLength: Protegia.spaceXS)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
        }.font(Protegia.font(12)).foregroundStyle(Protegia.text)
            .padding(.horizontal, Protegia.spaceSM).frame(height: 36)
            .background(Protegia.base, in: RoundedRectangle(cornerRadius: Protegia.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Protegia.controlRadius).stroke(Protegia.level2, lineWidth: 1))
    }
}
