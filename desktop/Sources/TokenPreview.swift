import AppKit
import SwiftUI

enum TokenPreview {
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
    var body: some View {
        let value = TokenPreview.resolved(token, tokens: tokens)
        let kind = token.kind.lowercased()
        Group {
            if kind == "color", let color = TokenPreview.color(value) {
                RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: color)).overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.25),lineWidth: 1)).padding(3)
            } else if kind == "radius" || token.name.contains("radius"), let radius = TokenPreview.radius(value) {
                RadiusCorner(radius: min(radius,16)).stroke(Protegia.text,style: StrokeStyle(lineWidth: 2,lineCap: .round)).padding(5)
            } else if kind == "typography" || token.name.contains("font") || token.name.contains("text-size") {
                let family = value.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) ?? ""
                Text("Aa").font(token.name.contains("family") ? .custom(family,size: 14) : .system(size: 14,weight: token.name.contains("weight") && (Double(value) ?? 400) >= 600 ? .bold : .regular))
            } else {
                Text(kind == "color" ? "?" : kind == "class" ? "." : "#").font(.system(size: 13,weight: .medium)).foregroundStyle(Protegia.secondary)
            }
        }.frame(width: 28,height: 28).background(Protegia.level1,in: RoundedRectangle(cornerRadius: 5)).help("\(token.name): \(value)")
    }
}
