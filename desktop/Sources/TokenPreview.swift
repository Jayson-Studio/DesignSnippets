import AppKit
import SwiftUI

enum TokenPreview {
    static func fontWeight(_ value: String) -> Font.Weight {
        switch value.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "") {
        case "100", "thin": return .ultraLight
        case "200", "extralight": return .thin
        case "300", "light": return .light
        case "500", "medium": return .medium
        case "600", "semibold", "demibold": return .semibold
        case "700", "bold": return .bold
        case "800", "extrabold": return .heavy
        case "900", "black": return .black
        default: return .regular
        }
    }
    static func resolved(_ token: DesignToken, tokens: [DesignToken]) -> String {
        var value = token.value
        var visited = Set<String>()
        for _ in 0..<16 {
            guard let match = TokenParser.matches(#"var\((--[\w-]+)(?:,\s*([^()]+))?\)|\{([\w.-]+)\}"#, value).first else { break }
            let name = match[1].isEmpty ? match[3] : match[1]
            guard visited.insert(name).inserted else { break }
            let referenced = tokens.first { $0.name == name && $0.source == token.source } ?? tokens.first { $0.name == name }
            guard let replacement = referenced?.value ?? (match[2].isEmpty ? nil : match[2]) else { break }
            value = value.replacingOccurrences(of: match[0], with: replacement)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func typography(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func typography(_ token: DesignToken, tokens: [DesignToken]) -> [String: Any]? {
        guard let properties = token.typography.map({ $0 as [String: Any] }) ?? typography(token.value) else { return typography(resolved(token, tokens: tokens)) }
        return properties.mapValues { value in
            guard let string = property(value) else { return value }
            return resolved(DesignToken(name: token.name, value: string, kind: token.kind, source: token.source), tokens: tokens)
        }
    }
    static func weightName(_ value: String) -> String {
        ["100":"Thin", "200":"Extra light", "300":"Light", "400":"Regular", "500":"Medium", "600":"Semibold", "700":"Bold", "800":"Extra bold", "900":"Black"][value] ?? value.capitalized
    }
    static func property(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let families = value as? [String] { return families.joined(separator: ", ") }
        if let dimension = value as? [String: Any], let number = dimension["value"], let unit = dimension["unit"] as? String { return "\(number)\(unit)" }
        return String(describing: value)
    }
    static func definition(_ token: DesignToken, tokens: [DesignToken]) -> String {
        let value = resolved(token, tokens: tokens)
        if let properties = typography(token, tokens: tokens) {
            let parts = [property(properties["fontSize"]), property(properties["fontWeight"]).map(weightName), property(properties["letterSpacing"]).map { "Spacing \($0)" }, property(properties["lineHeight"]).map { "Line height \($0)" }, property(properties["fontFamily"])].compactMap { $0 }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
        if token.name.contains("weight") { return weightName(value) }
        if let match = TokenParser.matches(#"^var\((--[\w-]+)\)$|^\{([\w.-]+)\}$"#, token.value).first {
            let alias = (match[1].isEmpty ? match[2] : String(match[1].dropFirst(2))).replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: ".", with: " ").capitalized
            return value == token.value ? token.value : "\(alias) · \(value)"
        }
        return value
    }
    static func pickerDefinition(_ token: DesignToken, tokens: [DesignToken]) -> String {
        let text = definition(token, tokens: tokens)
            .replacingOccurrences(of: #"(?i)\brgba?\([^()]*\)"#, with: "", options: .regularExpression)
        let parts = text.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Color" : parts.joined(separator: " · ")
    }
    static func color(_ raw: String) -> NSColor? {
        let value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let named: [String: String] = ["white":"#ffffff", "black":"#000000", "red":"#ff0000", "blue":"#0000ff", "green":"#008000", "transparent":"#00000000"]
        if let hex = named[value] { return color(hex) }
        if value.hasPrefix("#") {
            var hex = String(value.dropFirst())
            if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard [6,8].contains(hex.count), let number = UInt64(hex, radix: 16) else { return nil }
            if hex.count == 6 { return NSColor(srgbRed: Double((number >> 16) & 255)/255, green: Double((number >> 8) & 255)/255, blue: Double(number & 255)/255, alpha: 1) }
            return NSColor(srgbRed: Double((number >> 24) & 255)/255, green: Double((number >> 16) & 255)/255, blue: Double((number >> 8) & 255)/255, alpha: Double(number & 255)/255)
        }
        guard let open = value.firstIndex(of: "("), value.hasSuffix(")") else { return nil }
        let function = String(value[..<open])
        let parts = value[value.index(after: open)..<value.index(before: value.endIndex)].replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "/", with: " ").split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        func number(_ text: String, percentScale: Double = 1) -> Double? {
            guard let n = Double(text.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "deg", with: "")), n.isFinite else { return nil }
            return text.hasSuffix("%") ? n / 100 * percentScale : n
        }
        guard let a = number(parts[0]), let b = number(parts[1]), let c = number(parts[2]), let alpha = parts.count == 4 ? number(parts[3]) : 1 else { return nil }
        func result(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: min(1,max(0,r)), green: min(1,max(0,g)), blue: min(1,max(0,b)), alpha: min(1,max(0,alpha))) }
        if function == "rgb" || function == "rgba" { return result(parts[0].hasSuffix("%") ? a : a/255, parts[1].hasSuffix("%") ? b : b/255, parts[2].hasSuffix("%") ? c : c/255) }
        if function == "hsl" || function == "hsla" {
            let h = (a.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)/60
            let chroma = (1-abs(2*c-1))*b, x = (1-abs(h.truncatingRemainder(dividingBy: 2)-1))*(1-abs(2*c-1))*b, m = c-chroma/2
            let rgb: (Double,Double,Double)
            switch h { case ..<1: rgb=(chroma,x,0); case ..<2: rgb=(x,chroma,0); case ..<3: rgb=(0,chroma,x); case ..<4: rgb=(0,x,chroma); case ..<5: rgb=(x,0,chroma); default: rgb=(chroma,0,x) }
            return result(rgb.0+m,rgb.1+m,rgb.2+m)
        }
        if function == "oklch" || function == "oklab" {
            let aa = function == "oklch" ? b * cos(c * .pi / 180) : b
            let bb = function == "oklch" ? b * sin(c * .pi / 180) : c
            let l = pow(a + 0.3963377774*aa + 0.2158037573*bb,3)
            let m = pow(a - 0.1055613458*aa - 0.0638541728*bb,3)
            let s = pow(a - 0.0894841775*aa - 1.291485548*bb,3)
            func gamma(_ v: Double) -> Double { v <= 0.0031308 ? 12.92*v : 1.055*pow(v,1/2.4)-0.055 }
            return result(gamma(4.0767416621*l-3.3077115913*m+0.2309699292*s),gamma(-1.2684380046*l+2.6097574011*m-0.3413193965*s),gamma(-0.0041960863*l-0.7034186147*m+1.707614701*s))
        }
        return nil
    }
    static func radius(_ value: String) -> Double? {
        func length(_ text: String) -> Double? {
            guard let match = TokenParser.matches(#"^\s*(-?[0-9.]+)(px|rem)?\s*$"#, text).first, let n = Double(match[1]), n.isFinite else { return nil }
            return n * (match[2] == "rem" ? 16 : 1)
        }
        if let n = length(value) { return max(0,n) }
        if let m = TokenParser.matches(#"^calc\(([^()]+?)\s+([+-])\s+([^()]+)\)$"#, value).first, let a = length(m[1]), let b = length(m[3]) { return max(0,a + (m[2] == "+" ? b : -b)) }
        return nil
    }
}

struct RadiusCorner: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(max(radius,0),min(rect.width,rect.height)-2)
        var p = Path(); p.move(to: CGPoint(x: 2,y: rect.maxY)); p.addLine(to: CGPoint(x: 2,y: 2+r))
        p.addQuadCurve(to: CGPoint(x: 2+r,y: 2), control: CGPoint(x: 2,y: 2)); p.addLine(to: CGPoint(x: rect.maxX,y: 2)); return p
    }
}
struct TokenBadge: View {
    let token: DesignToken
    var tokens: [DesignToken] = []
    var size: CGFloat = 48
    var body: some View {
        let value = TokenPreview.resolved(token, tokens: tokens)
        let kind = token.kind.lowercased()
        let properties = TokenPreview.typography(token, tokens: tokens)
        let radius = TokenPreview.radius(value)
        let isText = kind == "typography" || token.name.contains("font") || (token.name.contains("text") && kind != "color")
        ZStack(alignment: .topLeading) {
            Color.white.opacity(0.19)
            if kind == "color", let color = TokenPreview.color(value) {
                RoundedRectangle(cornerRadius: size * 0.13).fill(Color(nsColor: color))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.13).stroke(.white.opacity(0.15),lineWidth: 0.5)).padding(size * 0.16)
            } else if (kind == "radius" || token.name.contains("radius")), let radius {
                UnevenRoundedRectangle(topLeadingRadius: min(radius,size * 0.3)).fill(.white.opacity(0.8))
                    .frame(width: size * 0.66, height: size * 0.66).offset(x: size * 0.4,y: size * 0.4)
                RadiusCorner(radius: min(radius,size * 0.3)).stroke(Color.red,style: StrokeStyle(lineWidth: 1.3,lineCap: .round))
                    .frame(width: size * 0.28,height: size * 0.28).offset(x: size * 0.4 - 2,y: size * 0.4 - 2)
                Text("\(radius.formatted(.number.precision(.fractionLength(0...1))))px").font(.system(size: size * 0.16,weight: .semibold)).foregroundStyle(.red).padding(size * 0.14)
            } else if isText {
                let family = TokenPreview.property(properties?["fontFamily"]) ?? (token.name.contains("family") ? value : "")
                let cleanFamily = family.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) ?? ""
                let weight = TokenPreview.property(properties?["fontWeight"]) ?? (token.name.contains("weight") ? value : "400")
                let fontSizeValue = TokenPreview.property(properties?["fontSize"]) ?? (token.name.contains("size") || token.name.hasPrefix("--text-") ? value : "16px")
                let fontSize = max(1, TokenPreview.radius(fontSizeValue) ?? Double(fontSizeValue) ?? 16)
                let fontWeight = TokenPreview.fontWeight(weight)
                Text("Heading").font(cleanFamily.isEmpty ? .system(size: fontSize, weight: fontWeight) : .custom(cleanFamily, size: fontSize).weight(fontWeight))
                    .fixedSize(horizontal: true, vertical: true).foregroundStyle(.white)
                    .frame(width: size - 12, height: size - 12, alignment: .topLeading)
                    .clipped().padding(6)
            } else {
                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.14)).overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.85),lineWidth: 1)).padding(size * 0.18)
            }
        }.frame(width: size,height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.19))
            .help("\(token.name): \(TokenPreview.definition(token,tokens: tokens)) · \(token.source)")
    }
}
