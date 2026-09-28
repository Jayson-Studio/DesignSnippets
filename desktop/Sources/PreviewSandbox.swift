import AppKit
import SwiftUI

/// A local editor that exercises the same PickerView and PickerState as the
/// system-wide picker, without sending keystrokes to another application.
@MainActor final class PreviewSession: ObservableObject {
    @Published var text = ""
    @Published var isOpen = false
    var selection = NSRange(location: 0, length: 0)
    var triggerRange: NSRange?
    private var dismissedTriggerLocation: Int?
    let picker = PickerState()

    init() { picker.choose = { [weak self] token in self?.insert(token) } }

    func update(_ value: String, selection: NSRange) {
        text = value
        self.selection = selection
        let prefix = (value as NSString).substring(to: min(selection.location, (value as NSString).length))
        let hash = (prefix as NSString).range(of: "#", options: .backwards)
        guard selection.length == 0, hash.location != NSNotFound else {
            if hash.location == NSNotFound { dismissedTriggerLocation = nil }
            close(); return
        }
        let start = hash.location
        let suffix = (prefix as NSString).substring(from: NSMaxRange(hash))
        guard suffix.isEmpty || PickerState.isQueryText(suffix) else {
            dismissedTriggerLocation = nil
            close(); return
        }
        if dismissedTriggerLocation == start { close(); return }
        triggerRange = NSRange(location: start, length: 1 + suffix.utf16.count)
        picker.query = suffix
        picker.selected = 0
        picker.canInsert = true
        if !isOpen { picker.selectSection("Foundations") }
        isOpen = !picker.tokens.isEmpty
    }

    func command(_ keyCode: UInt16) -> Bool {
        guard isOpen else { return false }
        switch keyCode {
        case 123, 124: picker.moveSection(keyCode == 124 ? 1 : -1); return true
        case 125, 126: picker.moveSelection(keyCode == 125 ? 1 : -1); return true
        case 53: dismissedTriggerLocation = triggerRange?.location; close(); return true
        case 36, 76, 48:
            guard !picker.matches.isEmpty else { close(); return false }
            insert(picker.matches[min(picker.selected, picker.matches.count - 1)])
            return true
        default: return false
        }
    }

    private func insert(_ token: DesignToken) {
        guard let range = triggerRange else { return }
        text = (text as NSString).replacingCharacters(in: range, with: token.name)
        selection = NSRange(location: range.location + token.name.utf16.count, length: 0)
        dismissedTriggerLocation = nil
        close()
    }

    func close() { isOpen = false; triggerRange = nil }
}

struct PreviewSandbox: View {
    @ObservedObject var model: AppModel
    @StateObject private var session = PreviewSession()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Try the picker").font(Protegia.font(18, bold: true))
                if !session.isOpen {
                    Text("Type # below to open the same picker used in other apps. Search, switch sections with ← →, select with ↑ ↓, and press Return to insert.")
                        .font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.tokens.isEmpty && !session.isOpen {
                    Text("Choose a project or explore sample tokens in Default to start previewing.")
                        .font(Protegia.font(12)).foregroundStyle(Protegia.secondary)
                }
                ZStack(alignment: .topLeading) {
                    PreviewEditor(session: session)
                    if session.text.isEmpty {
                        Text("Type here, then enter #…")
                            .font(Protegia.font(13)).foregroundStyle(Protegia.tertiary)
                            .padding(.leading, 13).padding(.top, 12).allowsHitTesting(false)
                    }
                }
                .frame(height: session.isOpen ? 72 : 110)
                .background(Protegia.level1, in: RoundedRectangle(cornerRadius: Protegia.controlRadius))
                .clipShape(RoundedRectangle(cornerRadius: Protegia.controlRadius))
                if !session.isOpen {
                    Text("This sandbox changes only the text above.")
                        .font(Protegia.font(10)).foregroundStyle(Protegia.tertiary)
                }
            }.padding(Protegia.spaceLG)
            if session.isOpen {
                ProtegiaDivider()
                PickerView(state: session.picker)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { session.picker.tokens = model.tokens }
        .onReceive(model.$indices) { indices in
            session.picker.tokens = indices.first(where: { $0.repository.id == model.activeID })?.tokens ?? []
        }
        .onChange(of: model.activeID) { _, _ in session.picker.tokens = model.tokens }
    }
}

private struct PreviewEditor: NSViewRepresentable {
    @ObservedObject var session: PreviewSession

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let editor = PreviewTextView()
        editor.frame = NSRect(origin: .zero, size: scroll.contentSize)
        editor.autoresizingMask = [.width]
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.drawsBackground = false
        editor.textColor = NSColor(Protegia.text)
        editor.font = NSFont.systemFont(ofSize: 13)
        editor.textContainerInset = NSSize(width: 9, height: 9)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.onCommand = { [weak session] keyCode in session?.command(keyCode) ?? false }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? PreviewTextView else { return }
        if editor.string != session.text {
            editor.string = session.text
            editor.setSelectedRange(session.selection)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let session: PreviewSession
        init(session: PreviewSession) { self.session = session }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            session.update(editor.string, selection: editor.selectedRange())
        }
    }

    final class PreviewTextView: NSTextView {
        var onCommand: ((UInt16) -> Bool)?
        override func keyDown(with event: NSEvent) {
            if onCommand?(event.keyCode) == true { return }
            super.keyDown(with: event)
        }
    }
}
