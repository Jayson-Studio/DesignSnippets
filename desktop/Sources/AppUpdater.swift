import AppKit
import Combine
import Sparkle

@MainActor final class AppUpdater {
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    init(model: AppModel, beforeCheck: @escaping () -> Void) {
        let info = Bundle.main.infoDictionary ?? [:]
        guard UpdateConfiguration.isValid(feed: info["SUFeedURL"] as? String, publicKey: info["SUPublicEDKey"] as? String) else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        model.updatesConfigured = true
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak model] available in model?.canCheckForUpdates = available }
        model.checkForUpdates = { [weak controller] in
            beforeCheck()
            NSApp.activate(ignoringOtherApps: true)
            controller?.checkForUpdates(nil)
        }
        // Sparkle owns consent, scheduling, signature validation, installation, and relaunch.
        // No automatic download/install preference is forced on the user.
        controller.startUpdater()
    }
}
