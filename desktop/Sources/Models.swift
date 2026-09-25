import Foundation

struct DesignToken: Codable, Identifiable, Equatable {
    var id: String { "\(source):\(name)" }
    let name: String
    let value: String
    let kind: String
    let source: String
    var typography: [String: String]? = nil
    var section: String? = nil

    var pickerSection: String {
        if let section, !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return section }
        if kind.lowercased() == "icon" || kind == "Class" && name.range(of: #"^\.(?:icon|ico)[-_]"#, options: .regularExpression) != nil { return "Icons" }
        let parts = source.lowercased().split(separator: "/").map(String.init)
        for (path, title) in [("getting-started", "Getting Started"), ("icons", "Icons"), ("brand", "Brand"), ("pages", "Pages"), ("widgets", "Widgets"), ("elements", "Elements"), ("components", "Components")] {
            if parts.contains(path) { return title }
        }
        return kind == "Class" ? "Components" : "Foundations"
    }
}
struct Repository: Codable, Identifiable, Equatable {
    let id: Int
    let full_name: String
    let default_branch: String
    let `private`: Bool
}
struct TokenIndex: Codable {
    let repository: Repository
    let tokens: [DesignToken]
    let syncedAt: Date
    let revision: String
    var sourceFiles: [String]? = nil
}
struct SemanticError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum TokenParser {
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0)) }
        }
    }
    static func parse(_ text: String, source: String) -> [DesignToken] {
        if source.lowercased().hasSuffix(".json") { return parseJSON(text, source: source) }
        let text = text.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        var result: [DesignToken] = []
        for parts in matches(#"(--[a-zA-Z_][\w-]*)\s*:\s*([^;{}\n]+)"#, text) {
            let value = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = parts[1]
            let kind: String
            if name.contains("radius") { kind = "Radius" }
            else if name.contains("font") || name.contains("line-height") || name.contains("letter-spacing") { kind = "Typography" }
            else if value.range(of: #"^(#|rgb|hsl|oklch|oklab|color\()"#, options: .regularExpression) != nil || name.range(of: "color|background|foreground|surface|accent|border", options: .regularExpression) != nil && !name.contains("width") { kind = "Color" }
            else { kind = "Dimension" }
            result.append(DesignToken(name: name, value: value, kind: kind, source: source))
        }
        // Only inspect selector portions; decimal values and file extensions in declarations are not classes.
        for block in matches(#"(?:^|[{}])\s*([^{}]+)\{"#, text) {
            if block[1].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") { continue }
            for name in matches(#"\.([a-zA-Z_][\w-]*)"#, block[1]) {
                result.append(DesignToken(name: "." + name[1], value: "CSS class", kind: "Class", source: source))
            }
        }
        // Associate a size token with typography declared where that token is
        // used. Keep only properties that agree across usages; never guess a
        // single weight/family when the same size is used by different styles.
        var styles: [String: [[String: String]]] = [:]
        let keys = ["font-family": "fontFamily", "font-size": "fontSize", "font-weight": "fontWeight", "letter-spacing": "letterSpacing", "line-height": "lineHeight"]
        for block in matches(#"([^{}]+)\{([^{}]*)\}"#, text) {
            var properties: [String: String] = [:]
            for declaration in matches(#"(?:^|;)\s*(font-family|font-size|font-weight|letter-spacing|line-height)\s*:\s*([^;{}]+)"#, block[2]) {
                properties[keys[declaration[1]]!] = declaration[2].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let size = properties["fontSize"], let name = matches(#"^var\((--[\w-]+)\)$"#, size).first?[1] else { continue }
            styles[name, default: []].append(properties)
        }
        return unique(result).map { token in
            var token = token
            if let usages = styles[token.name], let first = usages.first {
                token.typography = first.filter { key, value in usages.allSatisfy { $0[key] == value } }
            }
            return token
        }
    }
    static func parseJSON(_ text: String, source: String) -> [DesignToken] {
        guard let data = text.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var result: [DesignToken] = []
        func walk(_ node: [String: Any], path: [String], inheritedType: String?) {
            let type = node["$type"] as? String ?? node["type"] as? String ?? inheritedType
            if let value = node["$value"] ?? node["value"], !path.isEmpty {
                guard path.allSatisfy({ $0.range(of: #"^[a-zA-Z_][a-zA-Z0-9_.-]*$"#, options: .regularExpression) != nil }), path.joined(separator: ".").count <= 160 else { return }
                let string: String
                if let raw = value as? String { string = raw }
                else if let number = value as? NSNumber { string = number.stringValue }
                else if JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let raw = String(data: data, encoding: .utf8) { string = raw }
                else { return }
                let headings = ["foundations": "Foundations", "foundation-tokens": "Foundations", "getting-started": "Getting Started", "components": "Components", "icons": "Icons", "brand": "Brand", "pages": "Pages", "widgets": "Widgets", "elements": "Elements"]
                let section = path.first.flatMap { headings[$0.lowercased()] }
                result.append(DesignToken(name: path.joined(separator: "."), value: string, kind: type?.capitalized ?? "Token", source: source, section: section))
                return
            }
            for key in node.keys.sorted() where !key.hasPrefix("$") && key != "type" {
                if let child = node[key] as? [String: Any] { walk(child, path: path + [key], inheritedType: type) }
            }
        }
        walk(root, path: [], inheritedType: nil)
        return unique(result)
    }
    static func unique(_ tokens: [DesignToken]) -> [DesignToken] {
        // Preserve alternative declarations from separate theme files; de-duplicate within each source.
        var values: [String: DesignToken] = [:]
        tokens.forEach { values[$0.id] = $0 }
        return values.values.sorted { $0.name == $1.name ? $0.source < $1.source : $0.name < $1.name }
    }
    static func eligible(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        let excluded: Set<String> = ["node_modules", "vendor", "dist", "build", ".git", ".next", "coverage"]
        guard !components.contains(where: { excluded.contains(String($0)) }), !path.hasSuffix(".min.css") else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        return ["css", "scss", "sass", "less"].contains(ext) || ext == "json" && path.lowercased().range(of: "token|theme|semantic", options: .regularExpression) != nil
    }
}
