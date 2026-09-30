import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: AppModel!
    private var picker: TokenPicker!
    private var updater: AppUpdater?
    private var allowingPopoverClose = false
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
        // Keep the menu visible while another app, including a screen capture tool, takes focus.
        // The status item remains the explicit control for opening and closing it.
        popover = NSPopover(); popover.behavior = .applicationDefined; popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 620)
        popover.contentViewController = NSHostingController(rootView: SemanticPanel(model: model, onDismiss: { [weak self] in
            self?.closePanel()
        }) { [weak self] tab in
            self?.popover.contentSize = NSSize(width: 420, height: tab == "Preview" ? 480 : 620)
        })
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
        if popover.isShown { closePanel() } else { showPanel() }
    }
    private func closePanel() {
        guard popover.isShown else { return }
        allowingPopoverClose = true
        popover.performClose(nil)
    }
    func popoverShouldClose(_ popover: NSPopover) -> Bool { allowingPopoverClose }
    func popoverDidClose(_ notification: Notification) { allowingPopoverClose = false }
    @objc private func showPanel() {
        guard let button = statusItem.button else { return }
        picker.dismiss()
        // The status-item button belongs to the menu bar on the display where its
        // icon is visible. Keeping the popover attached to that button is more
        // reliable than activating the accessory app, which can move focus to a
        // different display and make AppKit reposition the popover.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Popovers use a panel window, which otherwise hides when this accessory app
        // loses focus to a capture tool even when the popover itself stays open.
        popover.contentViewController?.view.window?.hidesOnDeactivate = false
    }
    @objc private func checkForUpdates() { model.checkForUpdates?() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        allowingPopoverClose = true
        picker.stop()
    }
}
@main struct SemanticApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
