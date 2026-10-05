import AppKit
import SwiftUI

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct MenuArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct MenuWindowContent: View {
    let model: AppModel
    let onDismiss: () -> Void
    let onTabChange: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            MenuArrow().fill(Protegia.base).frame(width: 20, height: 10)
            SemanticPanel(model: model, onDismiss: onDismiss, onTabChange: onTabChange)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Protegia.level2, lineWidth: 1))
        }
        .frame(width: 420)
        .background(Color.clear)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menuPanel: MenuPanel!
    private var model: AppModel!
    private var picker: TokenPicker!
    private var updater: AppUpdater?
    private var menuHeight: CGFloat = 620
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        Protegia.registerFonts()
        NSApp.appearance = NSAppearance(named: .darkAqua)
        model = AppModel(); picker = TokenPicker(model: model)
        model.configureMonitor = { [weak self] in self?.picker.start() }
        model.stopMonitor = { [weak self] in self?.picker.stop() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "number.square", accessibilityDescription: "DesignSnippets")
            button.image?.isTemplate = true
            button.target = self; button.action = #selector(toggle)
            button.toolTip = "DesignSnippets — your design system, wherever you type"
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menuPanel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: menuHeight + 10),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        menuPanel.isOpaque = false
        menuPanel.backgroundColor = .clear
        menuPanel.hasShadow = true
        menuPanel.level = .popUpMenu
        menuPanel.isFloatingPanel = true
        menuPanel.hidesOnDeactivate = false
        menuPanel.canHide = false
        menuPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: MenuWindowContent(model: model, onDismiss: { [weak self] in
            self?.closePanel()
        }) { [weak self] tab in
            self?.resizeMenu(for: tab)
        })
        host.frame = NSRect(x: 0, y: 0, width: 420, height: menuHeight + 10)
        host.autoresizingMask = [.width, .height]
        menuPanel.contentView = host
        updater = AppUpdater(model: model) { [weak self] in self?.closePanel() }
        model.reconcilePicker()
        toggle()
    }
    func applicationDidBecomeActive(_ notification: Notification) { model?.returnedToApp() }
    private func installMainMenu() {
        // This app starts through NSApplication.run(), so it has no automatic
        // SwiftUI Edit menu. Nil targets route shortcuts to the focused editor.
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "DesignSnippets")
        appMenu.addItem(withTitle: "Quit DesignSnippets", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    @objc private func toggle() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open DesignSnippets", action: #selector(showPanel), keyEquivalent: "").target = self
            let updateItem = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            updateItem.target = self
            menu.autoenablesItems = false
            updateItem.isEnabled = model.canCheckForUpdates
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit DesignSnippets", action: #selector(quit), keyEquivalent: "q").target = self
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
            return
        }
        if menuPanel.isVisible { closePanel() } else { showPanel() }
    }
    private func closePanel() {
        menuPanel.orderOut(nil)
    }
    private func resizeMenu(for tab: String) {
        menuHeight = tab == "Preview" ? 480 : 620
        menuPanel.setContentSize(NSSize(width: 420, height: menuHeight + 10))
        positionMenu()
    }
    @objc private func showPanel() {
        picker.dismiss()
        positionMenu()
        menuPanel.orderFrontRegardless()
        menuPanel.makeKey()
    }
    private func positionMenu() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }) ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = menuPanel.frame.size
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(anchor.minY - size.height - 2, visible.minY + 8), visible.maxY - size.height)
        menuPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    @objc private func checkForUpdates() { model.checkForUpdates?() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { picker.stop() }
}
@main struct SemanticApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
