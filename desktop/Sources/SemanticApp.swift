import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: AppModel!
    private var picker: TokenPicker!
    private var updater: AppUpdater?
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
        popover = NSPopover(); popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 620)
        popover.contentViewController = NSHostingController(rootView: SemanticPanel(model: model))
        updater = AppUpdater(model: model) { [weak self] in self?.popover.performClose(nil) }
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
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }
    @objc private func showPanel() {
        guard let button = statusItem.button else { return }
        picker.dismiss()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
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
