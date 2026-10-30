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
struct PickerTab: Codable, Identifiable, Equatable {
    let title: String
    let path: String
    var id: String { path }

    static func title(for path: String, existing: [PickerTab]) -> String {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let words = name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
        let title = words.map { $0.capitalized }.joined(separator: " ")
        let base = title.isEmpty ? "Untitled" : title
        let used = Set(existing.map { $0.title.lowercased() }).union(["foundations", "new tab"])
        if !used.contains(base.lowercased()) { return base }
        var suffix = 2
        while used.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }
}
struct TokenIndex: Codable {
    let repository: Repository
    let tokens: [DesignToken]
    let syncedAt: Date
    let revision: String
    var sourceFiles: [String]? = nil
    var pickerTabs: [PickerTab]? = nil
    var referenceTokens: [DesignToken]? = nil
    var colorReferencesScanned: Bool? = nil
    // Tailwind utility names are derived at display time so existing cached projects
    // gain them without requiring a new GitHub import.
    var displayTokens: [DesignToken] { TokenParser.withUtilityAliases(tokens) }
}
struct SemanticError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum TokenParser {
    static func withUtilityAliases(_ tokens: [DesignToken]) -> [DesignToken] {
        let namespaces = [
            ("--background-color-", "bg-"),
            ("--text-color-", "text-"),
            ("--border-color-", "border-"),
            ("--ring-color-", "ring-")
        ]
        let aliases = tokens.compactMap { token -> DesignToken? in
            guard let (variablePrefix, utilityPrefix) = namespaces.first(where: { token.name.hasPrefix($0.0) }),
                  token.name.count > variablePrefix.count else { return nil }
            return DesignToken(name: utilityPrefix + token.name.dropFirst(variablePrefix.count),
                               value: "var(\(token.name))", kind: "Color", source: token.source)
        }
        return unique(aliases + tokens)
    }
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0)) }
        }
    }
    static func parse(_ text: String, source: String) -> [DesignToken] {
        if ["ts", "tsx"].contains((source as NSString).pathExtension.lowercased()) {
            return IconCatalog.exports(text).map { DesignToken(name: $0, value: "React icon", kind: "Icon", source: source) }
        }
        if source.lowercased().hasSuffix(".json") { return parseJSON(text, source: source) }
        let text = text.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        var result: [DesignToken] = []
        for parts in matches(#"(--[a-zA-Z_][\w-]*)[ \t]*:[ \t]*((?:(?!\n[ \t]*--[a-zA-Z_][\w-]*[ \t]*:)[^;{}])+)"#, text) {
            let value = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = parts[1]
            let kind: String
            let colorLiteral = value.range(of: #"^(#|rgba?\(|hsla?\(|oklch\(|oklab\(|color\()"#, options: .regularExpression) != nil
            let colorName = name.range(of: "color|background|foreground|surface|accent|border", options: .regularExpression) != nil && !name.contains("width")
            if name.contains("radius") { kind = "Radius" }
            else if colorLiteral || colorName && (value.hasPrefix("var(") || value.hasPrefix("{") || ["white", "black", "red", "blue", "green", "transparent"].contains(value.lowercased())) { kind = "Color" }
            else if name.contains("font") || name.contains("line-height") || name.contains("letter-spacing") { kind = "Typography" }
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
        let keys = ["font-family": "fontFamily", "font-size": "fontSize", "font-weight": "fontWeight", "letter-spacing": "letterSpacing", "line-height": "lineHeight", "color": "color"]
        for block in matches(#"([^{}]+)\{([^{}]*)\}"#, text) {
            var properties: [String: String] = [:]
            for declaration in matches(#"(?:^|;)\s*(font-family|font-size|font-weight|letter-spacing|line-height|color)\s*:\s*([^;{}]+)"#, block[2]) {
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

// Static readers only: imported TypeScript is never evaluated.
enum IconCatalog {
    // Export metadata from https://unpkg.com/react-icons@5.6.0/go/index.d.ts.
    // Match the Git-only filter used by Carrot UI's unified catalog.
    static let octiconsVersion = "5.6.0"
    static let octicons = ["GoCommit", "GoDiff", "GoFileDiff", "GoGitBranch", "GoGitCommit", "GoGitCompare", "GoGitMerge", "GoGitMergeQueue", "GoGitPullRequest", "GoGitPullRequestClosed", "GoGitPullRequestDraft", "GoHistory", "GoRepo", "GoRepoForked", "GoRepoLocked", "GoRepoPush", "GoRepoTemplate", "GoTag"]
    static func exports(_ text: String) -> [String] {
        let clean = text.replacingOccurrences(of: #"/\*[\s\S]*?\*/|(?m)^\s*//[^\n]*"#, with: "", options: .regularExpression)
        var names = TokenParser.matches(#"\bexport\s+(?:declare\s+)?(?:const|function|class)\s+([A-Z][A-Za-z0-9]*Icon)\b"#, clean).map { $0[1] }
        for block in TokenParser.matches(#"\bexport\s*\{([^}]+)\}"#, clean) {
            for item in block[1].components(separatedBy: ",") {
                if let match = TokenParser.matches(#"^\s*[A-Za-z][A-Za-z0-9]*(?:\s+as\s+([A-Z][A-Za-z0-9]*Icon))?\s*$"#, item).first {
                    let name = match[1].isEmpty ? item.trimmingCharacters(in: .whitespacesAndNewlines) : match[1]
                    if name.hasSuffix("Icon") { names.append(name) }
                }
            }
        }
        return Array(Set(names)).sorted()
    }
    static func relativePath(_ module: String, from path: String) throws -> String {
        guard module.hasPrefix(".") else { throw SemanticError("Only repository-local icon sources can be followed.") }
        var parts = path.split(separator: "/").dropLast().map(String.init)
        for part in module.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard !parts.isEmpty else { throw SemanticError("Icon source points outside the repository.") }
                parts.removeLast()
            } else { parts.append(String(part)) }
        }
        return try GitHubClient.filePaths([parts.joined(separator: "/") + ((module as NSString).pathExtension.isEmpty ? ".tsx" : "")])[0]
    }
    static func semanticModule(_ text: String) throws -> String {
        guard text.contains("ICON_CATALOG"), text.contains("LUCIDE_ENTRIES"), text.contains("PROVIDER_ENTRIES"),
              text.contains("OCTICON_ENTRIES"), text.contains("react-icons/go"),
              text.contains(#"/Git|Repo(?![a-z])|Diff|Commit|Branch|Fork|Merge|PullRequest|Tag|History/"#),
              let module = TokenParser.matches(#"import\s+\*\s+as\s+SemanticIcons\s+from\s+["']([^"']+)["']"#, text).first?[1] else {
            throw SemanticError("This dynamic icon catalog is not supported. Import its icon export file or a token JSON export instead.")
        }
        return module
    }
    static func tokens(catalog: String, semantic: String, providers: String, package: String, source: String) throws -> [DesignToken] {
        let data = Data(package.utf8)
        let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dependencies = manifest?["dependencies"] as? [String: String] ?? [:]
        let devDependencies = manifest?["devDependencies"] as? [String: String] ?? [:]
        guard (dependencies["react-icons"] ?? devDependencies["react-icons"]) == octiconsVersion else {
            throw SemanticError("This catalog needs react-icons 5.6.0. Its dependency version changed; update Design Snippets before importing it.")
        }
        let semanticNames = exports(semantic)
        let availableProviders = Set(exports(providers))
        var providerNames: [String] = []
        for row in TokenParser.matches(#"\[\s*["']([A-Za-z][A-Za-z0-9]*Icon)["']\s*,\s*([A-Za-z][A-Za-z0-9]*Icon)\s*,\s*(undefined|[A-Za-z][A-Za-z0-9]*Icon)\s*\]"#, catalog) {
            guard row[1] == row[2] else { throw SemanticError("Unsupported provider icon alias in catalog.") }
            providerNames.append(row[2])
            if row[3] != "undefined" { providerNames.append(row[3]) }
        }
        guard !semanticNames.isEmpty, !providerNames.isEmpty, Set(providerNames).isSubset(of: availableProviders) else {
            throw SemanticError("Could not resolve all catalog icon exports. Previous tokens are unchanged.")
        }
        let groups = [(semanticNames, "Lucide semantic icon"), (providerNames, "Provider icon"), (octicons, "Git Octicon")]
        return TokenParser.unique(groups.flatMap { names, label in
            names.map { DesignToken(name: $0, value: label, kind: "Icon", source: source) }
        })
    }
}
