import AppKit
import Combine
import Sparkle

/// Retained for the app lifetime; Sparkle owns downloading, validation and installation.
@MainActor final class UpdateController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    private var availability: AnyCancellable?
    private let beforeShowingUpdate: () -> Void

    init(model: AppModel, beforeShowingUpdate: @escaping () -> Void) {
        self.beforeShowingUpdate = beforeShowingUpdate
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        availability = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak model] available in model?.canCheckForUpdates = available }
        model.onCheckForUpdates = { [weak self] in
            guard let self, self.controller.updater.canCheckForUpdates else { return }
            self.beforeShowingUpdate()
            self.controller.checkForUpdates(nil)
        }
        controller.startUpdater()
        // Sparkle permits a launch check immediately after startup. Respect its saved preference.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    func standardUserDriverWillShowModalAlert() { beforeShowingUpdate() }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if handleShowingUpdate { beforeShowingUpdate() }
    }
}
