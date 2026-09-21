import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@MainActor final class PickerState: ObservableObject {
    @Published var query = ""
    @Published var selected = 0
    @Published var tokens: [DesignToken] = []
    @Published var project = ""
    @Published var canInsert = true
    @Published var approximatePosition = false
    @Published var pointerPosition = false
    var choose: ((DesignToken) -> Void)?
    @discardableResult func appendQuery(_ text: String) -> Bool {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) else { return false }
        query += text
        selected = 0
        return true
    }
    func moveSelection(_ delta: Int) {
        let count = matches.count
        if count > 0 { selected = (selected + delta + count) % count }
    }
    func deleteQueryCharacter() { if !query.isEmpty { query.removeLast() }; selected = 0 }
    var matches: [DesignToken] { tokens.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
}
struct PickerView: View {
    @ObservedObject var state: PickerState
    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "number").foregroundStyle(semanticGreen); Text(state.query.isEmpty ? "Reference a token" : state.query).font(Protegia.font(12, bold: true)).lineLimit(1); Spacer(); Text("esc").font(Protegia.font(10)).foregroundStyle(Protegia.tertiary) }.padding(14)
            ProtegiaDivider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if state.matches.isEmpty { Text("No matching tokens").font(Protegia.font(12)).foregroundStyle(Protegia.secondary).padding(25) }
                        ForEach(Array(state.matches.enumerated()), id: \.element.id) { index, token in
                            Button { state.choose?(token) } label: {
                                HStack(spacing: 9) {
                                    TokenBadge(token: token, tokens: state.tokens)
                                    VStack(alignment: .leading, spacing: 4) { Text(token.name).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1); Text(token.source).font(Protegia.font(10)).foregroundStyle(Protegia.secondary).lineLimit(1) }
                                    Spacer(minLength: 6)
                                    Text(index == state.selected ? "↵" : token.value).font(.system(size: 10, design: .monospaced)).foregroundStyle(Protegia.secondary).lineLimit(1).frame(maxWidth: 75)
                                }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(index == state.selected ? Protegia.level1 : .clear, in: RoundedRectangle(cornerRadius: Protegia.controlRadius)).contentShape(Rectangle())
                            }.buttonStyle(.plain).id(index)
                        }
                    }.padding(5)
                }.onChange(of: state.selected) { _, value in proxy.scrollTo(value, anchor: .center) }
                .onChange(of: state.query) { _, _ in proxy.scrollTo(0, anchor: .top) }
            }
            if state.approximatePosition { Text(state.pointerPosition ? "Copy mode · approximate position; cursor unavailable" : "Positioned near the field; cursor location unavailable").font(Protegia.font(10)).foregroundStyle(Protegia.secondary).padding(.horizontal, 10) }
            ProtegiaDivider()
            HStack { Text(state.project).lineLimit(1); Spacer(); Text(state.canInsert ? "↑↓ select  ·  ↵ insert" : "↵ copy · paste into editor") }.font(Protegia.font(10)).foregroundStyle(Protegia.secondary).padding(11)
        }.frame(width: 385, height: 338).background(Protegia.base)
        .foregroundStyle(Protegia.text).font(Protegia.font(12)).tint(Protegia.accent).preferredColorScheme(.dark)
    }
}
enum PickerPlacement {
    static func anchor(glyph: CGRect?, caret: CGRect?, field: CGRect?) -> CGRect? {
        for candidate in [glyph, caret, field] {
            if let rect = candidate, rect.minX.isFinite, rect.minY.isFinite,
               rect.width.isFinite, rect.height.isFinite, rect.width >= 0, rect.height > 0 { return rect }
        }
        return nil
    }
    static func appKitRect(_ accessibilityRect: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(x: accessibilityRect.minX, y: desktopTop - accessibilityRect.maxY,
               width: accessibilityRect.width, height: accessibilityRect.height)
    }
    static func origin(anchor: CGRect, visibleFrame: CGRect, size: CGSize = CGSize(width: 385, height: 338)) -> CGPoint {
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
    private var secureFocusDetected = false
    private var fallbackPoint = CGPoint.zero
    private var lastClick: (pid: pid_t, point: CGPoint)?
    private var injected = false
    private var notification: NSObjectProtocol?
    private var preparedApps: Set<pid_t> = []
    private let eventMarker: Int64 = 0x53454D41
    init(model: AppModel) {
        self.model = model
        state.choose = { [weak self] in self?.insert($0) }
        notification = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(); self?.prepareFrontApp() }
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
        prepareFrontApp()
    }
    func stop() {
        dismiss()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; model.pickerEnabled = false
    }
    private func prepareFrontApp() {
        guard model.pickerEnabled, let app = NSWorkspace.shared.frontmostApplication,
              let bundle = app.bundleIdentifier, model.allowsPicker(in: bundle),
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        prepareAccessibility(app.processIdentifier)
    }
    private func prepareAccessibility(_ pid: pid_t) {
        guard !preparedApps.contains(pid) else { return }
        // Electron documents this request for third-party assistive tools. It exposes
        // the app's tree; it does not grant or change macOS Accessibility permission.
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        preparedApps.insert(pid)
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
                lastClick = (app.processIdentifier, NSEvent.mouseLocation)
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
        // Only normal typing is handled. Editing shortcuts dismiss without interception.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { dismiss(); return false }
        // Navigation belongs to the picker, even while focus resolution is pending.
        // Do not make synchronous accessibility calls before consuming arrow keys.
        if (pendingTrigger || target != nil || copyOnlyFallback), front.processIdentifier == pid, code == 125 || code == 126 {
            state.moveSelection(code == 125 ? 1 : -1)
            return true
        }
        if pendingTrigger {
            if code == 51 && !flags.contains(.maskAlternate) && !state.query.isEmpty { state.deleteQueryCharacter(); return false }
            if state.appendQuery(text) { return false }
            dismiss(); return false
        }
        if target != nil || copyOnlyFallback {
            guard front.processIdentifier == pid else { dismiss(); return false }
            if !copyOnlyFallback {
                guard let current = focusedElement(pid), let target, CFEqual(current, target) else { dismiss(); return false }
            }
            if code == 53 { dismiss(); return true }
            if code == 125 || code == 126 {
                state.moveSelection(code == 125 ? 1 : -1)
                return true
            }
            if code == 36 || code == 76 || code == 48 {
                guard !state.matches.isEmpty else { dismiss(); return false }
                insert(state.matches[min(state.selected, state.matches.count - 1)]); return true
            }
            if code == 51 {
                if flags.contains(.maskAlternate) { dismiss(); return false }
                if state.query.isEmpty { dismiss() } else { state.deleteQueryCharacter(); schedulePlacement() }
                return false
            }
            if state.appendQuery(text) {
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
        secureFocusDetected = false
        fallbackPoint = lastClick?.pid == pid ? lastClick!.point : NSEvent.mouseLocation
        state.tokens = model.tokens; state.project = model.activeIndex?.repository.full_name ?? ""; state.selected = 0
        // AX requests from inside the event-tap callback can block delivery to the editor.
        // Resolve focus after delivery, with retries for lazily-created accessibility trees.
        beginTask = Task { [weak self] in
            for delay: UInt64 in [25_000_000, 75_000_000, 150_000_000] {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard let self, self.pendingTrigger,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                self.prepareAccessibility(pid)
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
        // Position-only use does not authorize insertion into an unknown editor.
        if let focused = rawFocusedElement(pid), !isSecure(focused), let selection = range(focused),
           let rect = bounds(focused, range: CFRange(location: selection.location, length: 0)) {
            let caret = PickerPlacement.appKitRect(rect, desktopTop: NSScreen.screens.first?.frame.maxY ?? 0)
            fallbackPoint = CGPoint(x: caret.minX, y: caret.maxY)
            state.pointerPosition = false; state.approximatePosition = false
        }
        state.tokens = index.tokens; state.project = index.repository.full_name
        model.pickerFeedback = "This editor uses copy mode. Select a token, then replace your # search text by pasting it."
        showPicker()
    }
    private func showPicker() {
        if panel == nil {
            let created = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 385, height: 338), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
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
    private func fieldBounds(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    private func schedulePlacement() {
        placementTask?.cancel()
        if copyOnlyFallback {
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(fallbackPoint) }) ?? NSScreen.main else { return }
            let anchor = CGRect(origin: fallbackPoint, size: CGSize(width: 1, height: 1))
            panel?.setFrameOrigin(PickerPlacement.origin(anchor: anchor, visibleFrame: screen.visibleFrame))
            panel?.orderFrontRegardless()
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
                // Cursor support varies independently of permission and text insertion.
                guard let rect = PickerPlacement.anchor(glyph: glyph, caret: caret, field: self.fieldBounds(target)) else { continue }
                self.state.approximatePosition = glyph == nil && caret == nil
                let anchor = PickerPlacement.appKitRect(rect, desktopTop: NSScreen.screens.first?.frame.maxY ?? 0)
                guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) || $0.frame.contains(anchor.origin) }) else { continue }
                self.panel?.setFrameOrigin(PickerPlacement.origin(anchor: anchor, visibleFrame: screen.visibleFrame))
                self.panel?.orderFrontRegardless()
            }
            if let self, self.target != nil, self.panel?.isVisible != true {
                self.openCopyOnlyFallback()
            }
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
        guard let target, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == pid,
              let current = focusedElement(pid), CFEqual(target, current), isEditable(current),
              let start = initialRange, let selection = range(current), selection.length == 0,
              selection.location == start.location + state.query.utf16.count + (triggerHasHash ? 1 : 0) else {
            model.status = "Text focus changed. No token was inserted."; dismiss(); return
        }
        let count = state.query.count + (triggerHasHash ? 1 : 0)
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
    func dismiss() { beginTask?.cancel(); beginTask = nil; pendingTrigger = false; copyOnlyFallback = false; state.pointerPosition = false; placementTask?.cancel(); placementTask = nil; panel?.orderOut(nil); target = nil; initialRange = nil; state.query = "" }
}
