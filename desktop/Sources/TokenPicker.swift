import AppKit
import ApplicationServices
import Carbon
import SwiftUI

enum PickerLayout {
    static let width: CGFloat = 420
    static let height: CGFloat = 320
    static let size = CGSize(width: width, height: height)
}

@MainActor final class PickerState: ObservableObject {
    @Published var query = ""
    @Published private(set) var activeSection = "Foundations"
    @Published var selected = 0
    var sections: [String] {
        let additional = Set(tokens.map(\.pickerSection)).subtracting(["Foundations", "Getting Started", "Components", "Icons"]).sorted()
        return ["Foundations", "Getting Started", "Components"] + additional + ["Icons"]
    }
    func selectSection(_ section: String, pointer: CGPoint? = nil) {
        guard sections.contains(section) else { return }
        activeSection = section
        selected = 0
        selectionFromPointer = false
        lastPointerPosition = pointer
    }
    func moveSection(_ delta: Int, pointer: CGPoint? = nil) {
        let tabs = sections
        let current = tabs.firstIndex(of: activeSection) ?? 0
        selectSection(tabs[(current + delta % tabs.count + tabs.count) % tabs.count], pointer: pointer)
    }
    @Published var selectionFromPointer = false
    private var lastPointerPosition: CGPoint?
    @Published var tokens: [DesignToken] = []
    @Published var project = ""
    @Published var canInsert = true
    @Published var approximatePosition = false
    @Published var pointerPosition = false
    @Published var manualPosition = false
    @Published var manualOnly = false
    var choose: ((DesignToken) -> Void)?
    var dragHeader: ((CGPoint, Bool) -> Void)?
    var endHeaderDrag: (() -> Void)?
    var resetPosition: (() -> Void)?
    @discardableResult func appendQuery(_ text: String) -> Bool {
        guard Self.isQueryText(text) else { return false }
        query += text
        selected = 0
        return true
    }
    static func isQueryText(_ text: String) -> Bool {
        !text.isEmpty && !text.contains("#") && text.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
                && !(0xF700...0xF8FF).contains($0.value)
        }
    }
    func moveSelection(_ delta: Int, pointer: CGPoint? = nil) {
        selectionFromPointer = false
        lastPointerPosition = pointer
        let count = matches.count
        if count > 0 { selected = min(max(selected + delta, 0), count - 1) }
    }
    func hoverSelection(_ index: Int, at point: CGPoint) {
        guard matches.indices.contains(index), point != lastPointerPosition else { return }
        lastPointerPosition = point
        selectionFromPointer = true
        selected = index
    }
    func deleteQueryCharacter() { if !query.isEmpty { query.removeLast() }; selected = 0 }
    var matches: [DesignToken] {
        let candidates = tokens.filter { $0.pickerSection == activeSection }
        guard !query.isEmpty else { return candidates }
        func normalized(_ name: String) -> String {
            var value = name.lowercased()
            if value.hasPrefix("--") { value.removeFirst(2) }
            else if value.hasPrefix(".") { value.removeFirst() }
            return value
        }
        let needle = normalized(query)
        func rank(_ token: DesignToken) -> Int {
            let name = normalized(token.name)
            return name == needle ? 0 : name.hasPrefix(needle) ? 1 : 2
        }
        return candidates.enumerated().filter { $0.element.name.localizedCaseInsensitiveContains(query) }
            .sorted { left, right in
                let a = rank(left.element), b = rank(right.element)
                return a == b ? left.offset < right.offset : a < b
            }.map(\.element)
    }
}
struct PickerView: View {
    @ObservedObject var state: PickerState
    var body: some View {
        let matches = state.matches
        VStack(spacing: 0) {
            // Retain a drag target without adding header copy or stealing tab clicks.
            Color.clear.frame(height: 12).overlay(PickerDragHeader(state: state))
            ScrollViewReader { proxy in
                ScrollView {
                    if matches.isEmpty {
                        VStack(spacing: 6) {
                            Text(state.query.isEmpty ? "No entries in \(state.activeSection)" : "No matching entries")
                                .font(Protegia.font(12, bold: true))
                            Text(state.query.isEmpty ? "Entries appear here when included in your imported files." : "Try another search or switch tabs.")
                                .font(Protegia.font(11)).foregroundStyle(Protegia.tertiary)
                        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(30)
                    } else if state.activeSection == "Icons" {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, token in
                                entry(token, index: index, grid: true)
                            }
                        }.padding(.horizontal, 14).padding(.vertical, 4)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, token in
                                entry(token, index: index, grid: false)
                            }
                        }.padding(.horizontal, 14).padding(.vertical, 4)
                    }
                }
                .onChange(of: state.selected) { _, value in
                    if !state.selectionFromPointer, matches.indices.contains(value) { proxy.scrollTo(matches[value].id, anchor: .center) }
                }
                .onChange(of: state.query) { _, _ in
                    if let first = matches.first { proxy.scrollTo(first.id, anchor: .top) }
                }
                .onChange(of: state.activeSection) { _, _ in
                    if let first = matches.first { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(state.sections, id: \.self) { section in
                            Button { state.selectSection(section, pointer: NSEvent.mouseLocation) } label: {
                                Text(section).font(Protegia.font(12, bold: true)).fixedSize()
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(state.activeSection == section ? Protegia.level2 : .clear, in: Capsule())
                            }.buttonStyle(.plain).id(section)
                                .accessibilityAddTraits(state.activeSection == section ? .isSelected : [])
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 10)
                }.onChange(of: state.activeSection) { _, section in proxy.scrollTo(section, anchor: .center) }
            }
            ProtegiaDivider().padding(.horizontal, 14)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Protegia.tertiary)
                Text(state.query.isEmpty ? "Search for a token" : state.query)
                    .foregroundStyle(state.query.isEmpty ? Protegia.tertiary : Protegia.text).lineLimit(1)
                Spacer()
                Text("esc").font(Protegia.font(11)).foregroundStyle(Protegia.tertiary)
            }.padding(14).overlay(PickerDragHeader(state: state))
        }.frame(width: PickerLayout.width, height: PickerLayout.height).background(Protegia.base)
        .foregroundStyle(Protegia.text).font(Protegia.font(12)).tint(Protegia.accent).preferredColorScheme(.dark)
    }

    private func entry(_ token: DesignToken, index: Int, grid: Bool) -> some View {
        Button { state.choose?(token) } label: {
            Group {
                if grid {
                    VStack(spacing: 6) {
                        TokenBadge(token: token, tokens: state.tokens, size: 32)
                        Text(token.name).font(Protegia.font(9)).lineLimit(1)
                    }.frame(maxWidth: .infinity).frame(height: 64)
                } else {
                    HStack(spacing: 12) {
                        TokenBadge(token: token, tokens: state.tokens, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(token.name).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                            Text(TokenPreview.pickerDefinition(token, tokens: state.tokens))
                                .font(Protegia.font(11)).foregroundStyle(Protegia.tertiary).lineLimit(2)
                        }
                        Spacer(minLength: 6)
                        Text(index == state.selected ? "↵" : "").font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Protegia.secondary).frame(width: 15)
                    }.padding(10)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .background(index == state.selected ? Protegia.level2 : Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.controlRadius))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).id(token.id)
            .accessibilityLabel(token.name)
            .accessibilityAddTraits(index == state.selected ? .isSelected : [])
            .help("\(token.name): \(token.value)")
            .onContinuousHover { phase in
                if case .active = phase { state.hoverSelection(index, at: NSEvent.mouseLocation) }
            }
    }
}
// Move only our nonactivating panel; global coordinates avoid drag feedback.
private struct PickerDragHeader: NSViewRepresentable {
    let state: PickerState
    func makeNSView(context: Context) -> Header { let view = Header(); view.state = state; return view }
    func updateNSView(_ view: Header, context: Context) { view.state = state }
    final class Header: NSView {
        weak var state: PickerState?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) { state?.dragHeader?(NSEvent.mouseLocation, true) }
        override func mouseDragged(with event: NSEvent) { state?.dragHeader?(NSEvent.mouseLocation, false) }
        override func mouseUp(with event: NSEvent) { state?.endHeaderDrag?() }
        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()
            let item = NSMenuItem(title: "Reset saved position", action: #selector(resetPosition), keyEquivalent: "")
            item.target = self; menu.addItem(item); return menu
        }
        @objc private func resetPosition() { state?.resetPosition?() }
        override func viewDidMoveToWindow() { toolTip = "Drag to save a position for this app and display. Right-click to reset." }
    }
}

// Fractions of usable display space survive monitor rearrangement/resizing.
struct PickerPositionStore {
    var defaults: UserDefaults = .standard
    private let key = "pickerSavedPositions"
    private var positions: [String: [String: [Double]]] {
        defaults.dictionary(forKey: key) as? [String: [String: [Double]]] ?? [:]
    }
    func save(_ origin: CGPoint, app: String, display: String, frame: CGRect) {
        let area = frame.insetBy(dx: 8, dy: 8)
        let point = PickerPlacement.clamp(origin, visibleFrame: frame)
        let coordinates = [Double((point.x - area.minX) / max(1, area.width - PickerLayout.width)),
                           Double((point.y - area.minY) / max(1, area.height - PickerLayout.height))]
        var all = positions; all[app, default: [:]][display] = coordinates; defaults.set(all, forKey: key)
    }
    func origin(app: String, display: String, frame: CGRect) -> CGPoint? {
        guard let values = positions[app]?[display], values.count == 2, values.allSatisfy({ $0.isFinite }) else { return nil }
        let area = frame.insetBy(dx: 8, dy: 8)
        return PickerPlacement.clamp(CGPoint(x: area.minX + CGFloat(values[0]) * max(0, area.width - PickerLayout.width),
                                            y: area.minY + CGFloat(values[1]) * max(0, area.height - PickerLayout.height)), visibleFrame: frame)
    }
    func remove(app: String, display: String) {
        var all = positions; all[app]?[display] = nil; defaults.set(all, forKey: key)
    }
}
enum PickerPlacement {
    static func clamp(_ point: CGPoint, visibleFrame: CGRect) -> CGPoint {
        let area = visibleFrame.insetBy(dx: 8, dy: 8)
        return CGPoint(x: min(max(point.x, area.minX), max(area.minX, area.maxX - PickerLayout.width)),
                       y: min(max(point.y, area.minY), max(area.minY, area.maxY - PickerLayout.height)))
    }
    static func anchor(glyph: CGRect?, caret: CGRect?, field: CGRect?) -> CGRect? {
        for candidate in [glyph, caret, field] {
            if let rect = candidate, rect.minX.isFinite, rect.minY.isFinite,
               rect.size.width.isFinite, rect.size.height.isFinite, rect.size.width >= 0, rect.size.height > 0 { return rect }
        }
        return nil
    }
    /// Accessibility uses the display at AppKit's global origin as its top-left
    /// coordinate reference. Resolve that display explicitly; the array order is
    /// not a reliable monitor identity when status-bar focus changes.
    static func appKitRect(_ accessibilityRect: CGRect, screens: [CGRect]) -> CGRect {
        let coordinateScreen = screens.first(where: { $0.origin == .zero }) ?? screens.first
        let desktopTop = coordinateScreen?.maxY ?? 0
        return CGRect(x: accessibilityRect.minX, y: desktopTop - accessibilityRect.maxY,
               width: accessibilityRect.width, height: accessibilityRect.height)
    }
    static func origin(anchor: CGRect, visibleFrame: CGRect, size: CGSize = PickerLayout.size) -> CGPoint {
        let inset = visibleFrame.insetBy(dx: 8, dy: 8)
        let x = min(max(anchor.minX, inset.minX), max(inset.minX, inset.maxX - size.width))
        let above = anchor.maxY + 8
        let below = anchor.minY - size.height - 8
        let preferred = above + size.height <= inset.maxY ? above : below
        let y = min(max(preferred, inset.minY), max(inset.minY, inset.maxY - size.height))
        return CGPoint(x: x, y: y)
    }
}

// Rich editors may expose an editable AXGroup or a focused child of a text area.
// Never treat a generic container or a read-only selection as an editor.
enum PickerEditor {
    static func usesManualPosition(bundle: String) -> Bool { bundle == "com.openai.codex" }
    // Without an AX range, replacement is limited to an uninterrupted session
    // of simple token characters. Composed/IME text retains copy-only behavior.
    static func trackedReplacementCount(bundle: String, query: String, hasHash: Bool, active: Bool) -> Int? {
        guard active, usesManualPosition(bundle: bundle), query.unicodeScalars.allSatisfy({
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "_-.:/".unicodeScalars.contains($0))
        }) else { return nil }
        return query.count + (hasHash ? 1 : 0)
    }
    static func accepts(role: String, subrole: String, editable: Bool, writableSelection: Bool) -> Bool {
        guard role != "AXSecureTextField", subrole != kAXSecureTextFieldSubrole else { return false }
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
            || editable || writableSelection
    }
    static func triggerRange(selection: CFRange?, query: String, hasHash: Bool, observed: String?) -> CFRange? {
        let expected = (hasHash ? "#" : "") + query
        guard let selection, selection.length == 0, selection.location >= expected.utf16.count,
              observed == expected else { return nil }
        return CFRange(location: selection.location - expected.utf16.count, length: 0)
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class TokenPicker {
    let model: AppModel
    let state = PickerState()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var panel: FloatingPanel?
    private var target: AXUIElement?
    private var pid: pid_t = 0
    private var triggerHasHash = true
    private var initialRange: CFRange?
    private var placementTask: Task<Void, Never>?
    private var beginTask: Task<Void, Never>?
    private var pendingTrigger = false
    private var copyOnlyFallback = false
    private var trackedSessionValid = true
    private var secureFocusDetected = false
    private var fallbackPoint = CGPoint.zero
    private var fallbackAnchor: CGRect?
    private var lastClick: (pid: pid_t, point: CGPoint, date: Date)?
    private var injected = false
    private var notification: NSObjectProtocol?
    private let positions = PickerPositionStore()
    private var ownerBundle = ""
    private var positionDisplay: String?
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?
    private let eventMarker: Int64 = 0x53454D41
    init(model: AppModel) {
        self.model = model
        state.choose = { [weak self] in self?.insert($0) }
        state.dragHeader = { [weak self] point, began in self?.dragHeader(point, began: began) }
        state.endHeaderDrag = { [weak self] in self?.endHeaderDrag() }
        state.resetPosition = { [weak self] in self?.resetPosition() }
        notification = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }
    func start() {
        stop()
        guard AXIsProcessTrusted() else { model.error = "Accessibility access is required to insert tokens."; return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let picker = Unmanaged<TokenPicker>.fromOpaque(context).takeUnretainedValue()
                return picker.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { model.error = "macOS could not enable the keyboard hook. Confirm Accessibility access, then quit and reopen DesignSnippets."; return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        model.pickerEnabled = true; model.error = nil
    }
    func stop() {
        dismiss()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; model.pickerEnabled = false
    }
    private func rawFocusedElement(_ pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        var item: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &item) == .success,
              let item, CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(item, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.05)
        return element
    }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    private func range(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }
    private func isSecure(_ element: AXUIElement) -> Bool {
        (attribute(element, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole
            || (attribute(element, kAXRoleAttribute) as? String) == "AXSecureTextField"
    }
    private func isEditable(_ element: AXUIElement) -> Bool {
        var writable = DarwinBoolean(false)
        let writableSelection = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success && writable.boolValue
        return PickerEditor.accepts(role: attribute(element, kAXRoleAttribute) as? String ?? "",
                                    subrole: attribute(element, kAXSubroleAttribute) as? String ?? "",
                                    editable: (attribute(element, "AXEditable") as? Bool) == true,
                                    writableSelection: writableSelection)
    }
    private func elementAttribute(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = attribute(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let result = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(result, 0.05)
        return result
    }
    private func focusedElement(_ pid: pid_t) -> AXUIElement? {
        guard var current = rawFocusedElement(pid) else { return nil }
        // Follow explicit focus only: never pick an arbitrary text field in a window.
        for _ in 0..<6 {
            if isSecure(current) { secureFocusDetected = true; return nil }
            guard let child = elementAttribute(current, kAXFocusedUIElementAttribute), !CFEqual(child, current) else { break }
            current = child
        }
        var candidate: AXUIElement?
        // A focused static-text child can belong to an editable contenteditable container.
        // Check ancestors for secure fields before returning any candidate.
        for _ in 0..<12 {
            if isSecure(current) { secureFocusDetected = true; return nil }
            if candidate == nil, isEditable(current) { candidate = current }
            guard let parent = elementAttribute(current, kAXParentAttribute), !CFEqual(parent, current) else { break }
            current = parent
        }
        return candidate
    }
    private func triggerText(_ element: AXUIElement, selection: CFRange?, count: Int) -> String? {
        guard let selection, selection.length == 0, selection.location >= count else { return nil }
        if count == 0 { return "" }
        var requested = CFRange(location: selection.location - count, length: count)
        guard let value = AXValueCreate(.cfRange, &requested) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, value, &result) == .success else { return nil }
        return result as? String
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { dismiss(); if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false }
        if IsSecureEventInputEnabled() { dismiss(); return false }
        if event.getIntegerValueField(.eventSourceUserData) == eventMarker || injected { return false }
        if type == .leftMouseDown || type == .rightMouseDown {
            if type == .leftMouseDown, let app = NSWorkspace.shared.frontmostApplication,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               panel?.frame.contains(NSEvent.mouseLocation) != true {
                lastClick = (app.processIdentifier, NSEvent.mouseLocation, Date())
            }
            if pendingTrigger { dismiss() }
            if let panel, panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) { dismiss() }
            return false
        }
        guard type == .keyDown, let front = NSWorkspace.shared.frontmostApplication,
              let bundle = front.bundleIdentifier, model.allowsPicker(in: bundle), front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !model.tokens.isEmpty else { dismiss(); return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        var length = 0
        var chars = [UniChar](repeating: 0, count: 64)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        let text = String(utf16CodeUnits: chars, count: min(length, chars.count))
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if code == 49 && flags == [.maskControl, .maskAlternate] { begin(front.processIdentifier, hasHash: false); return true }
        // Printable Shift characters can filter; modified navigation and editor
        // shortcuts still dismiss and pass through unchanged.
        let isHashTrigger = text == "#" && flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty ||
            (flags.contains(.maskShift) && !isHashTrigger && !PickerState.isQueryText(text)) {
            dismiss(); return false
        }
        // A fresh # starts a new query, even if an earlier picker is still open.
        if isHashTrigger { begin(front.processIdentifier, hasHash: true); return false }
        // Leave the space in the editor but stop tracking the completed query.
        if (pendingTrigger || target != nil || copyOnlyFallback),
           text.rangeOfCharacter(from: .whitespaces) != nil, code != 48 {
            dismiss(); return false
        }
        if (pendingTrigger || target != nil || copyOnlyFallback), front.processIdentifier == pid,
           flags.isEmpty, [123, 124, 125, 126].contains(code) {
            if code == 123 || code == 124 {
                state.moveSection(code == 124 ? 1 : -1, pointer: NSEvent.mouseLocation)
            } else {
                state.moveSelection(code == 125 ? 1 : -1, pointer: NSEvent.mouseLocation)
            }
            return true
        }
        if pendingTrigger {
            if code == 125 || code == 126 { dismiss(); return false }
            if code == 51 && !flags.contains(.maskAlternate) && !state.query.isEmpty { state.deleteQueryCharacter(); return false }
            if state.appendQuery(text) { updateTrackedInsertion(); return false }
            dismiss(); return false
        }
        if target != nil || copyOnlyFallback {
            guard front.processIdentifier == pid else { dismiss(); return false }
            if !copyOnlyFallback {
                guard let current = focusedElement(pid), let target, CFEqual(current, target) else { dismiss(); return false }
            }
            if code == 53 { dismiss(); return true }
            if code == 125 || code == 126 { dismiss(); return false }
            if code == 36 || code == 76 || code == 48 {
                guard !state.matches.isEmpty else { dismiss(); return false }
                insert(state.matches[min(state.selected, state.matches.count - 1)]); return true
            }
            if code == 51 {
                if flags.contains(.maskAlternate) { dismiss(); return false }
                if state.query.isEmpty { dismiss() } else { state.deleteQueryCharacter(); updateTrackedInsertion(); schedulePlacement() }
                return false
            }
            if state.appendQuery(text) {
                updateTrackedInsertion()
                schedulePlacement()
                return false
            }
            dismiss()
        }
        if text == "#" { begin(front.processIdentifier, hasHash: true) }
        return false
    }
    private func begin(_ pid: pid_t, hasHash: Bool) {
        dismiss()
        self.pid = pid; triggerHasHash = hasHash; pendingTrigger = true
        ownerBundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        secureFocusDetected = false
        state.manualOnly = PickerEditor.usesManualPosition(bundle: ownerBundle)
        // Preserve the last click in this app even when the pointer moves while typing.
        fallbackPoint = lastClick?.pid == pid ? lastClick!.point : NSEvent.mouseLocation
        state.tokens = model.tokens; state.selectSection("Foundations", pointer: NSEvent.mouseLocation); state.project = model.activeIndex?.repository.full_name ?? ""; state.selected = 0
        // AX requests from inside the event-tap callback can block delivery to the editor.
        // Resolve focus after delivery, with retries for lazily-created accessibility trees.
        beginTask = Task { [weak self] in
            if let self, self.state.manualOnly {
                do { try await Task.sleep(nanoseconds: 25_000_000) } catch { return }
                guard self.pendingTrigger else { return }
                // Check secure focus only; Codex uses no caret-position queries.
                _ = self.focusedElement(pid)
                self.openCopyOnlyFallback()
                return
            }
            for delay: UInt64 in [25_000_000, 75_000_000, 150_000_000] {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard let self, self.pendingTrigger,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                guard !IsSecureEventInputEnabled() else { self.dismiss(); return }
                guard let element = self.focusedElement(pid), let index = self.model.activeIndex else {
                    if self.secureFocusDetected { self.dismiss(); return }
                    continue
                }
                let selected = self.range(element)
                if let selected, selected.length != 0 { continue }
                let expected = (hasHash ? "#" : "") + self.state.query
                let observed = self.triggerText(element, selection: selected, count: expected.utf16.count)
                let start = PickerEditor.triggerRange(selection: selected, query: self.state.query, hasHash: hasHash, observed: observed)
                // Only replace text if the editor confirms the exact trigger/query range.
                self.initialRange = start
                self.state.canInsert = start != nil
                self.state.approximatePosition = false
                self.target = element; self.pendingTrigger = false
                self.state.tokens = index.tokens; self.state.project = index.repository.full_name
                self.model.pickerFeedback = nil
                self.showPicker()
                return
            }
            guard let self, self.pendingTrigger else { return }
            self.openCopyOnlyFallback()
        }
    }
    private func openCopyOnlyFallback() {
        guard !secureFocusDetected, !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let index = model.activeIndex else { dismiss(); return }
        pendingTrigger = false; target = nil; initialRange = nil; copyOnlyFallback = true
        state.canInsert = false; state.approximatePosition = true; state.pointerPosition = true
        updateTrackedInsertion()
        // Position-only use does not authorize insertion into an unknown editor.
        if !state.manualOnly, let focused = rawFocusedElement(pid), !isSecure(focused) {
            if let selection = range(focused),
               let rect = bounds(focused, range: CFRange(location: selection.location, length: 0)) {
                let caret = appKitRect(rect)
                fallbackAnchor = caret
                fallbackPoint = CGPoint(x: caret.minX, y: caret.maxY)
                state.pointerPosition = false; state.approximatePosition = false

            }
        }
        state.tokens = index.tokens; state.project = index.repository.full_name
        model.pickerFeedback = state.canInsert ? nil : "This editor uses copy mode. Select a token, then replace your # search text by pasting it."
        showPicker()
    }
    private func showPicker() {
        if panel == nil {
            let created = FloatingPanel(contentRect: NSRect(origin: .zero, size: PickerLayout.size), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            created.level = .popUpMenu; created.isFloatingPanel = true; created.hidesOnDeactivate = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.backgroundColor = .clear; created.isOpaque = false; created.hasShadow = true
            let host = NSHostingView(rootView: PickerView(state: state))
            host.wantsLayer = true; host.layer?.cornerRadius = Protegia.panelRadius; host.layer?.masksToBounds = true
            created.contentView = host; panel = created
        }
        schedulePlacement()
    }
    private func bounds(_ element: AXUIElement, range: CFRange) -> CGRect? {
        var requested = range
        guard let value = AXValueCreate(.cfRange, &requested) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(result, to: AXValue.self), .cgRect, &rect),
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.height > 0 else { return nil }
        return rect
    }
    private func appKitRect(_ accessibilityRect: CGRect) -> CGRect {
        PickerPlacement.appKitRect(accessibilityRect, screens: NSScreen.screens.map(\.frame))
    }
    private func schedulePlacement() {
        placementTask?.cancel()
        if state.manualPosition { return }
        if copyOnlyFallback {
            let anchor = fallbackAnchor ?? CGRect(origin: fallbackPoint, size: CGSize(width: 1, height: 1))
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) || $0.frame.intersects(anchor) }) ?? NSScreen.main else { return }
            place(anchor: anchor, screen: screen)
            return
        }
        // The event tap runs before the editor inserts #. Read its glyph bounds after
        // delivery, retrying briefly for editors that publish Accessibility asynchronously.
        placementTask = Task { [weak self] in
            for delay: UInt64 in [25_000_000, 60_000_000, 120_000_000] {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard let self, let target = self.target,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == self.pid,
                      let current = self.focusedElement(self.pid), CFEqual(target, current), self.isEditable(current) else { return }
                let glyph = self.initialRange.flatMap { self.bounds(target, range: CFRange(location: $0.location, length: self.triggerHasHash ? 1 : 0)) }
                let caret = self.initialRange.flatMap { self.bounds(target, range: $0) }
                if self.secureFocusDetected { self.dismiss(); return }
                // Cursor support varies independently of permission and text insertion.
                let rect = PickerPlacement.anchor(glyph: glyph, caret: caret, field: nil)
                self.state.approximatePosition = rect == nil
                self.state.pointerPosition = rect == nil
                let anchor = rect.map { self.appKitRect($0) }
                    ?? CGRect(origin: self.fallbackPoint, size: CGSize(width: 1, height: 1))
                guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) || $0.frame.contains(anchor.origin) }) else { continue }
                self.place(anchor: anchor, screen: screen)
                if self.state.manualPosition { return }
            }
            if let self, self.target != nil, self.panel?.isVisible != true {
                self.openCopyOnlyFallback()
            }
        }
    }
    private func updateTrackedInsertion() {
        if state.manualOnly {
            state.canInsert = PickerEditor.trackedReplacementCount(bundle: ownerBundle, query: state.query,
                hasHash: triggerHasHash, active: trackedSessionValid && (pendingTrigger || copyOnlyFallback)) != nil
            if !state.canInsert { trackedSessionValid = false }
        }
    }
    private func insert(_ token: DesignToken) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              !IsSecureEventInputEnabled() else { dismiss(); return }
        if !state.canInsert {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(token.name, forType: .string)
            model.status = "Copied \(token.name). Replace your # search text by pasting the token."
            dismiss()
            return
        }
        let trackedCount = PickerEditor.trackedReplacementCount(bundle: ownerBundle, query: state.query,
            hasHash: triggerHasHash, active: trackedSessionValid && copyOnlyFallback && state.manualOnly)
        if trackedCount != nil {
            // Keyboard/navigation, external clicks and app switches dismiss this
            // session. Recheck secure focus before replacing the tracked #query.
            _ = focusedElement(pid)
            guard !secureFocusDetected, !IsSecureEventInputEnabled(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { dismiss(); return }
        } else {
        guard let target, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == pid,
              let current = focusedElement(pid), CFEqual(target, current), isEditable(current),
              let start = initialRange, let selection = range(current), selection.length == 0,
              selection.location == start.location + state.query.utf16.count + (triggerHasHash ? 1 : 0) else {
            model.status = "Text focus changed. No token was inserted."; dismiss(); return
        }
        }
        let count = trackedCount ?? (state.query.count + (triggerHasHash ? 1 : 0))
        let destination = pid
        dismiss(); injected = true
        let eventSource = CGEventSource(stateID: .privateState)
        func post(_ event: CGEvent?) {
            event?.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            event?.flags = []
            event?.postToPid(destination)
        }
        for _ in 0..<count { post(CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: true)); post(CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: false)) }
        // Unicode events avoid overwriting the user's clipboard. Never send a Return key.
        let characters = Array(token.name.utf16)
        for chunkStart in stride(from: 0, to: characters.count, by: 20) {
            let chunk = Array(characters[chunkStart..<min(chunkStart + 20, characters.count)])
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            up?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            post(down); post(up)
        }
        injected = false
    }
    private func displayKey(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if let number, let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return number?.stringValue ?? screen.localizedName
    }
    private func place(anchor: CGRect, screen: NSScreen) {
        let display = displayKey(screen)
        positionDisplay = display
        if state.approximatePosition, !ownerBundle.isEmpty,
           let origin = positions.origin(app: ownerBundle, display: display, frame: screen.visibleFrame) {
            state.manualPosition = true
            panel?.setFrameOrigin(origin)
        } else {
            panel?.setFrameOrigin(PickerPlacement.origin(anchor: anchor, visibleFrame: screen.visibleFrame))
        }
        if state.manualOnly { state.manualPosition = true }
        panel?.orderFrontRegardless()
    }
    private func dragHeader(_ point: CGPoint, began: Bool) {
        guard let panel, panel.isVisible else { return }
        if began { placementTask?.cancel(); dragStart = (point, panel.frame.origin); return }
        guard let start = dragStart,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? panel.screen else { return }
        placementTask?.cancel()
        state.manualPosition = true
        let origin = CGPoint(x: start.origin.x + point.x - start.mouse.x, y: start.origin.y + point.y - start.mouse.y)
        panel.setFrameOrigin(PickerPlacement.clamp(origin, visibleFrame: screen.visibleFrame))
        positionDisplay = displayKey(screen)
    }
    private func endHeaderDrag() {
        defer { dragStart = nil }
        guard dragStart != nil, state.manualPosition, !ownerBundle.isEmpty, let panel,
              let screen = NSScreen.screens.first(where: { displayKey($0) == positionDisplay }) else { return }
        positions.save(panel.frame.origin, app: ownerBundle, display: displayKey(screen), frame: screen.visibleFrame)
    }
    private func resetPosition() {
        if let display = positionDisplay { positions.remove(app: ownerBundle, display: display) }
        state.manualPosition = false; dragStart = nil
        schedulePlacement()
    }
    func dismiss() {
        beginTask?.cancel(); beginTask = nil; pendingTrigger = false
        copyOnlyFallback = false; fallbackAnchor = nil; trackedSessionValid = true
        state.pointerPosition = false; state.manualPosition = false; state.manualOnly = false
        dragStart = nil; positionDisplay = nil
        placementTask?.cancel(); placementTask = nil
        panel?.orderOut(nil); target = nil; initialRange = nil; state.query = ""
    }

}
